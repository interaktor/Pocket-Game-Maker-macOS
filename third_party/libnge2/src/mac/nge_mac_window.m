/***************************************************************************
 *            nge_mac_window.m
 *
 *  macOS (Cocoa + NSOpenGL) platform backend for libnge2 / PGM-Mac.
 *
 *  libnge2 is a polling engine (nge_main.c drives `app->mainloop()` in a
 *  tight loop, and nge_input.c polls via InputProc()). Cocoa, on the other
 *  hand, wants to run its own event loop. The bridge used here is the
 *  classic one: we never call -[NSApplication run]; instead we pump the run
 *  loop manually from nge_mac_poll_event() with nextEventMatchingMask: and
 *  dispatch whatever we pull out. Widget events are turned into a small
 *  ring buffer of nge_mac_event, which nge_input.c then drains.
 ***************************************************************************/

#import <Cocoa/Cocoa.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>

#include <stdlib.h>
#include <string.h>
#include "nge_mac.h"

/* ------------------------------------------------------------------ */
/* event queue                                                        */
/* ------------------------------------------------------------------ */

#define EVQ_SIZE 512

static nge_mac_event g_evq[EVQ_SIZE];
static int g_evq_head = 0;   /* read  */
static int g_evq_tail = 0;   /* write */
static int g_quit_requested = 0;

static void evq_push(int type, int code, int x, int y)
{
	int next = (g_evq_tail + 1) % EVQ_SIZE;
	if (next == g_evq_head)
		return; /* full: drop, better than blocking the UI */
	g_evq[g_evq_tail].type = type;
	g_evq[g_evq_tail].code = code;
	g_evq[g_evq_tail].x = x;
	g_evq[g_evq_tail].y = y;
	g_evq_tail = next;
}

static int evq_pop(nge_mac_event *ev)
{
	if (g_evq_head == g_evq_tail)
		return 0;
	*ev = g_evq[g_evq_head];
	g_evq_head = (g_evq_head + 1) % EVQ_SIZE;
	return 1;
}

/* ------------------------------------------------------------------ */
/* macOS virtual keycode -> PGM keycode                               */
/*                                                                    */
/* PGM's native layer registers PSP_BUTTON_* into Lua. On Windows those */
/* are the plain ASCII letters from nge_input.h ('W','S','A','D','I',   */
/* 'L','K','J','E','U','V','B','N','M'). We reproduce exactly the same */
/* values so that PGM's Lua framework (KeySetting.lua, FindScene.lua …) */
/* keeps working unchanged, and additionally accept the arrow keys as   */
/* aliases for the D-pad, which makes the port pleasant with a keyboard.*/
/* ------------------------------------------------------------------ */

static int map_keycode(unsigned short kc)
{
	switch (kc) {
	/* D-pad: physical WASD plus arrow-key aliases */
	case 0x0D: return 'W';  /* kVK_ANSI_W  = up    */
	case 0x01: return 'S';  /* kVK_ANSI_S  = down  */
	case 0x00: return 'A';  /* kVK_ANSI_A  = left  */
	case 0x02: return 'D';  /* kVK_ANSI_D  = right */
	case 0x7E: return 'W';  /* kVK_UpArrow    */
	case 0x7D: return 'S';  /* kVK_DownArrow  */
	case 0x7B: return 'A';  /* kVK_LeftArrow  */
	case 0x7C: return 'D';  /* kVK_RightArrow */

	/* Face buttons */
	case 0x22: return 'I';  /* kVK_ANSI_I  = triangle */
	case 0x25: return 'L';  /* kVK_ANSI_L  = circle   */
	case 0x28: return 'K';  /* kVK_ANSI_K  = cross    */
	case 0x26: return 'J';  /* kVK_ANSI_J  = square   */

	/* Shoulders */
	case 0x0E: return 'E';  /* kVK_ANSI_E  = L trigger */
	case 0x20: return 'U';  /* kVK_ANSI_U  = R trigger */

	/* System buttons */
	case 0x09: return 'V';  /* kVK_ANSI_V  = select    */
	case 0x0B: return 'B';  /* kVK_ANSI_B  = start     */
	case 0x2D: return 'N';  /* kVK_ANSI_N  = home/quit */
	case 0x2E: return 'M';  /* kVK_ANSI_M  = hold      */

	/* Convenience aliases that feel natural on a desktop keyboard */
	case 0x24: return 'K';  /* Return  ~ confirm  */
	case 0x31: return 'K';  /* Space   ~ confirm  */
	case 0x27: return 'K';  /* '       ~ confirm  */
	case 0x35: return 'N';  /* Escape  ~ home/quit */
	case 0x30: return 'V';  /* Tab     ~ select   */
	case 0x0C: return 'U';  /* Q       ~ R trigger */
	case 0x0F: return 'E';  /* R       ~ L trigger */

	default:   return -1;
	}
}

/* ------------------------------------------------------------------ */
/* view                                                               */
/* ------------------------------------------------------------------ */

@interface NgeMacView : NSOpenGLView
@end

static int view_height_css(NSView *v)
{
	NSRect b = [v bounds];
	return (int)b.size.height;
}

@implementation NgeMacView

- (void)prepareOpenGL
{
	[super prepareOpenGL];
	GLint one = 1;
	[[self openGLContext] setValues:&one
					   forParameter:NSOpenGLContextParameterSwapInterval];
}

- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)e { (void)e; return YES; }
- (BOOL)isOpaque { return YES; }
- (BOOL)wantsUpdateLayer { return NO; }

- (void)drawRect:(NSRect)dirtyRect
{
	(void)dirtyRect;
	/* nge2 redraws everything every frame; nothing to do here. */
}

- (void)keyDown:(NSEvent *)e
{
	int code;
	/* PGM/PSP semantics: one press -> one btn_down, repeats are ignored.
	   This matches the PSP's polled button state and avoids the wildly
	   different macOS key-repeat rates leaking into game logic. */
	if ([e isARepeat])
		return;
	code = map_keycode([e keyCode]);
	if (code >= 0)
		evq_push(NGE_MAC_EV_KEYDOWN, code, 0, 0);
}

- (void)keyUp:(NSEvent *)e
{
	int code = map_keycode([e keyCode]);
	if (code >= 0)
		evq_push(NGE_MAC_EV_KEYUP, code, 0, 0);
}

/* nge2 wants top-left origin coordinates, Cocoa gives bottom-left. */
- (void)pushMouse:(NSEvent *)e type:(int)type code:(int)code
{
	NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
	evq_push(type, code, (int)p.x, view_height_css(self) - (int)p.y);
}

- (void)mouseDown:(NSEvent *)e
{
	[self pushMouse:e type:NGE_MAC_EV_MOUSEDOWN code:NGE_MAC_MOUSE_LEFT];
}
- (void)mouseUp:(NSEvent *)e
{
	[self pushMouse:e type:NGE_MAC_EV_MOUSEUP code:NGE_MAC_MOUSE_LEFT];
}
- (void)rightMouseDown:(NSEvent *)e
{
	[self pushMouse:e type:NGE_MAC_EV_MOUSEDOWN code:NGE_MAC_MOUSE_RIGHT];
}
- (void)rightMouseUp:(NSEvent *)e
{
	[self pushMouse:e type:NGE_MAC_EV_MOUSEUP code:NGE_MAC_MOUSE_RIGHT];
}
- (void)otherMouseDown:(NSEvent *)e
{
	[self pushMouse:e type:NGE_MAC_EV_MOUSEDOWN code:NGE_MAC_MOUSE_MIDDLE];
}
- (void)otherMouseUp:(NSEvent *)e
{
	[self pushMouse:e type:NGE_MAC_EV_MOUSEUP code:NGE_MAC_MOUSE_MIDDLE];
}
- (void)mouseMoved:(NSEvent *)e
{
	[self pushMouse:e type:NGE_MAC_EV_MOUSEMOVE code:0];
}
- (void)mouseDragged:(NSEvent *)e
{
	[self pushMouse:e type:NGE_MAC_EV_MOUSEMOVE code:0];
}

@end

/* ------------------------------------------------------------------ */
/* window + GL context                                                */
/* ------------------------------------------------------------------ */

static NSWindow *g_window = nil;
static NgeMacView *g_view = nil;
static NSOpenGLContext *g_context = nil;

@interface NgeMacWindowDelegate : NSObject <NSWindowDelegate>
@end

@implementation NgeMacWindowDelegate
- (BOOL)windowShouldClose:(NSWindow *)sender
{
	(void)sender;
	evq_push(NGE_MAC_EV_QUIT, 0, 0, 0);
	return NO; /* we tear down ourselves once the engine notices */
}
- (void)windowDidResize:(NSNotification *)note
{
	(void)note;
	if (g_context)
		[g_context update];
}
@end

static NgeMacWindowDelegate *g_delegate = nil;

int nge_mac_window_create(const char *name, int w, int h, int fullscreen)
{
	@autoreleasepool {
		NSOpenGLPixelFormatAttribute attrs[16];
		int n = 0;
		NSOpenGLPixelFormat *pf;
		NSRect contentRect;
		NSString *title;

		if (w <= 0) w = 480;
		if (h <= 0) h = 272;

		[NSApplication sharedApplication];
		[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
		[NSApp finishLaunching];

		/* Legacy profile: nge2 renders with fixed-function GL 1.x/2.x
		   (glOrtho, glVertexPointer, glTexEnv, ...). */
		attrs[n++] = NSOpenGLPFADoubleBuffer;
		attrs[n++] = NSOpenGLPFAColorSize;   attrs[n++] = 24;
		attrs[n++] = NSOpenGLPFAAlphaSize;   attrs[n++] = 8;
		attrs[n++] = NSOpenGLPFADepthSize;   attrs[n++] = 0;
		attrs[n++] = NSOpenGLPFAAccelerated;
		attrs[n++] = 0;

		pf = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
		if (!pf) {
			NSLog(@"nge_mac: failed to create NSOpenGLPixelFormat");
			return -1;
		}

		contentRect = NSMakeRect(0, 0, w, h);
		g_window = [[NSWindow alloc]
			initWithContentRect:contentRect
					  styleMask:(NSWindowStyleMaskTitled |
								 NSWindowStyleMaskClosable |
								 NSWindowStyleMaskMiniaturizable)
						backing:NSBackingStoreBuffered
						  defer:NO];
		if (!g_window) {
			NSLog(@"nge_mac: failed to create NSWindow");
			return -1;
		}

		title = (name && name[0])
			? [NSString stringWithUTF8String:name]
			: @"PGM";
		[g_window setTitle:title];
		[g_window setReleasedWhenClosed:NO];
		/* Diagnostic: PGM_MAC_DEBUG_BG=1 paints the window solid red so we can
		   tell "window not composited" apart from "GL surface not attached". */
		if (getenv("PGM_MAC_DEBUG_BG"))
			[g_window setBackgroundColor:[NSColor redColor]];
		[g_window center];
		{
			NSRect wf = [g_window frame];
			NSLog(@"nge_mac: window %.0fx%.0f at (%.0f,%.0f) visible=%d",
				  wf.size.width, wf.size.height, wf.origin.x, wf.origin.y,
				  (int)[g_window isVisible]);
		}

		g_delegate = [[NgeMacWindowDelegate alloc] init];
		[g_window setDelegate:g_delegate];

		/* 1:1 pixel mapping – PGM is a 480x272 pixel-art engine. */
		g_view = [[NgeMacView alloc] initWithFrame:contentRect
									   pixelFormat:pf];
		[g_view setWantsBestResolutionOpenGLSurface:NO];
		[g_window setContentView:g_view];

		/* NSOpenGLView owns the context it was initialised with. */
		g_context = [g_view openGLContext];
		if (!g_context) {
			NSLog(@"nge_mac: view has no NSOpenGLContext");
			return -1;
		}
		[g_context setView:g_view];
		[g_context makeCurrentContext];
		[g_context update];

		[g_window makeFirstResponder:g_view];
		[g_window makeKeyAndOrderFront:nil];
		[NSApp activateIgnoringOtherApps:YES];

		/* Give the window server a display cycle, otherwise the window
		   exists in AppKit's model but is never composited to the screen
		   (we never call -[NSApplication run]). */
		[NSApp updateWindows];
		[g_window displayIfNeeded];
		CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, true);

		if (fullscreen) {
			/* Best-effort: a borderless fullscreen window. PGM ships
			   PGM_SCREEN_FULL=false so this is rarely exercised. */
			[g_window toggleFullScreen:nil];
		}

		return 0;
	}
}

void nge_mac_window_destroy(void)
{
	@autoreleasepool {
		/* Teardown order matters. NSOpenGLView *owns* the NSOpenGLContext it
		   was initialised with, so we must not release it ourselves: doing so
		   leaves the view with a dangling context and -[NSOpenGLView dealloc]
		   crashes inside objc_msgSend while invalidating GL states. Detach the
		   view from the window first, then let the window release everything. */
		if (g_context) {
			[NSOpenGLContext clearCurrentContext];
			g_context = nil;   /* borrowed reference – owned by g_view */
		}
		if (g_window) {
			[g_window setDelegate:nil];
			[g_window orderOut:nil];
			[g_window release];
			g_window = nil;
		}
		if (g_view) {
			/* The window's contentView owned a reference; this releases ours. */
			[g_view setOpenGLContext:nil];
			[g_view release];
			g_view = nil;
		}
		if (g_delegate) {
			[g_delegate release];
			g_delegate = nil;
		}
	}
}

void nge_mac_swap_buffers(void)
{
	if (g_context) {
		[g_context makeCurrentContext];
		[g_context flushBuffer];
	}
}

void nge_mac_get_size(int *w, int *h)
{
	if (w) *w = 0;
	if (h) *h = 0;
	if (!g_view)
		return;
	NSRect b = [g_view bounds];
	if (w) *w = (int)b.size.width;
	if (h) *h = (int)b.size.height;
}

void nge_mac_request_quit(void)
{
	g_quit_requested = 1;
	evq_push(NGE_MAC_EV_QUIT, 0, 0, 0);
}

/* Diagnostic: report the real AppKit window state every N polls. Enabled by
   setting PGM_MAC_DEBUG_WINDOW=1 in the environment. */
static void nge_mac_debug_window_state(void)
{
	static int tick = 0;
	NSRect f;
	if (!getenv("PGM_MAC_DEBUG_WINDOW"))
		return;
	if ((tick++ % 60) != 0)
		return;
	if (!g_window) {
		NSLog(@"nge_mac: no window");
		return;
	}
	f = [g_window frame];
	NSLog(@"nge_mac: visible=%d occl=%lu alpha=%.2f frame=%.0fx%.0f@(%.0f,%.0f) "
		  @"keyWindow=%d mainWindow=%d active=%d",
		  (int)[g_window isVisible],
		  (unsigned long)[g_window occlusionState],
		  (double)[g_window alphaValue],
		  f.size.width, f.size.height, f.origin.x, f.origin.y,
		  (int)[g_window isKeyWindow],
		  (int)[g_window isMainWindow],
		  (int)[NSApp isActive]);
}

int nge_mac_poll_event(nge_mac_event *ev)
{
	if (!ev)
		return 0;

	nge_mac_debug_window_state();

	if (evq_pop(ev))
		return 1;

	@autoreleasepool {
		int guard = 0;
		/* Pump the Cocoa run loop until either a widget event lands in
		   our queue or the OS has nothing left for us this frame. */
		while (guard++ < 64) {
			NSEvent *e = [NSApp nextEventMatchingMask:NSEventMaskAny
										   untilDate:[NSDate distantPast]
											  inMode:NSDefaultRunLoopMode
											 dequeue:YES];
			if (!e)
				break;
			[NSApp sendEvent:e];
			[NSApp updateWindows];
			if (evq_pop(ev))
				return 1;
		}
		/* Let CoreAnimation/the window server commit what we flushed. */
		CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, true);
	}

	if (g_quit_requested && evq_pop(ev))
		return 1;

	return 0;
}

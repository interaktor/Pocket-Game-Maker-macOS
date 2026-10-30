/***************************************************************************
 *            nge_mac.h
 *
 *  macOS (Cocoa + NSOpenGL) platform backend for libnge2.
 *
 *  This file is part of the PGM-Mac port. It provides the small C surface
 *  that nge_graphics.c / nge_input.c use on NGE_MAC, keeping all
 *  Objective-C confined to nge_mac_window.m.
 ***************************************************************************/

#ifndef _NGE_MAC_H
#define _NGE_MAC_H

#ifdef __cplusplus
extern "C" {
#endif

/* Event kinds handed back to nge_input.c */
enum {
	NGE_MAC_EV_NONE = 0,
	NGE_MAC_EV_KEYDOWN,
	NGE_MAC_EV_KEYUP,
	NGE_MAC_EV_MOUSEDOWN,
	NGE_MAC_EV_MOUSEUP,
	NGE_MAC_EV_MOUSEMOVE,
	NGE_MAC_EV_QUIT
};

typedef struct nge_mac_event {
	int type;   /* one of NGE_MAC_EV_* */
	int code;   /* PGM keycode (see nge_input.h PSP_BUTTON_*) or mouse button */
	int x, y;   /* mouse position in window pixels */
} nge_mac_event;

/* Mouse buttons, matching MOUSE_*_DOWN/UP in nge_input.h */
#define NGE_MAC_MOUSE_LEFT   1
#define NGE_MAC_MOUSE_RIGHT  2
#define NGE_MAC_MOUSE_MIDDLE 3

/**
 * Create the window and a legacy (fixed-function, GL 2.1) OpenGL context,
 * then make it current. Returns 0 on success.
 */
int  nge_mac_window_create(const char *name, int w, int h, int fullscreen);

/** Destroy the window and release the GL context. */
void nge_mac_window_destroy(void);

/** Present the back buffer. */
void nge_mac_swap_buffers(void);

/** Pump the Cocoa run loop; fills *ev and returns 1 when an event is ready. */
int  nge_mac_poll_event(nge_mac_event *ev);

/** Current drawable size in pixels. */
void nge_mac_get_size(int *w, int *h);

/** Ask for application termination at the next poll. */
void nge_mac_request_quit(void);

#ifdef __cplusplus
}
#endif

#endif /* _NGE_MAC_H */

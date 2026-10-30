/***************************************************************************
 *            p1_smoke.c
 *
 *  P1 acceptance test for the macOS (NGE_MAC) libnge2 backend.
 *
 *  Creates a 480x272 window through the Cocoa/NSOpenGL backend, renders a
 *  deterministic test pattern using only nge2's core drawing calls (so it
 *  needs no external art assets), snapshots the framebuffer back through
 *  glReadPixels, writes it out as a PNG and exits.
 *
 *  Exit code 0 means: window created, GL context current, drawing worked,
 *  framebuffer readback worked, PNG written.
 *
 *  Usage: p1_smoke [frames] [output.png]
 ***************************************************************************/

#include "libnge2.h"
#include "nge_png.h"

/* libnge2's nge_main.h does "#define main NGE_main" so that the nge2_main
   library can own the real entry point. This test is a plain standalone
   program, so take the name back. */
#undef main

#include <OpenGL/gl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SCR_W 480
#define SCR_H 272

static int g_quit = 0;

static void on_btn_down(int keycode)
{
	if (keycode == PSP_BUTTON_HOME || keycode == PSP_BUTTON_START ||
		keycode == PSP_BUTTON_SELECT)
		g_quit = 1;
}

static void on_btn_up(int keycode)
{
	(void)keycode;
}

static void dump_gl_state(const char *tag)
{
	GLint vp[4] = {0, 0, 0, 0};
	GLint sc[4] = {0, 0, 0, 0};
	screen_context_p s = GetScreenContext();

	glGetIntegerv(GL_VIEWPORT, vp);
	glGetIntegerv(GL_SCISSOR_BOX, sc);
	printf("%s: viewport=%dx%d+%d+%d scissor=%dx%d+%d+%d "
		   "screen=%dx%d ori=%dx%d\n",
		   tag, vp[2], vp[3], vp[0], vp[1],
		   sc[2], sc[3], sc[0], sc[1],
		   s->width, s->height, s->ori_width, s->ori_height);
	fflush(stdout);
}

/* A pattern that is trivial to verify by eye: solid colour quadrants, a white
   frame, and a known-position marker. No gradients -> no ambiguity. */
static void draw_pattern(int frame)
{
	int dtype = DISPLAY_PIXEL_FORMAT_8888;

	BeginScene(1);

	/* Three quadrants of pure primaries; bottom-right keeps the clear colour. */
	FillRect(0, 0, SCR_W / 2, SCR_H / 2, MAKE_RGB(255, 0, 0), dtype);
	FillRect(SCR_W / 2, 0, SCR_W / 2, SCR_H / 2, MAKE_RGB(0, 255, 0), dtype);
	FillRect(0, SCR_H / 2, SCR_W / 2, SCR_H / 2, MAKE_RGB(0, 0, 255), dtype);

	/* White frame: reveals Y-flip / scissor mistakes immediately. */
	FillRect(0, 0, SCR_W, 2, MAKE_RGB(255, 255, 255), dtype);
	FillRect(0, SCR_H - 2, SCR_W, 2, MAKE_RGB(255, 255, 255), dtype);
	FillRect(0, 0, 2, SCR_H, MAKE_RGB(255, 255, 255), dtype);
	FillRect(SCR_W - 2, 0, 2, SCR_H, MAKE_RGB(255, 255, 255), dtype);

	/* 20x20 white marker whose top-left corner must land on (40,40). */
	FillRect(40, 40, 20, 20, MAKE_RGB(255, 255, 255), dtype);

	/* A diagonal from the top-left corner to the bottom-right corner. */
	DrawLine(0, 0, SCR_W, SCR_H, MAKE_RGB(255, 255, 0), dtype);

	/* Moving marker: proves the render loop advances. */
	FillRect((float)((frame * 6) % (SCR_W - 30)), 200.0f, 30.0f, 30.0f,
			 MAKE_RGB(255, 0, 255), dtype);
}

int main(int argc, char *argv[])
{
	int frames = (argc > 1) ? atoi(argv[1]) : 30;
	const char *out = (argc > 2) ? argv[2] : "p1_smoke.png";
	int i;
	int rc = 0;
	image_p shot = NULL;

	if (frames <= 0)
		frames = 30;

	/* Must be set before NGE_Init: it drives InitGraphics(). */
	NGE_SetScreenContext("PGM-Mac P1 Smoke Test", SCR_W, SCR_H, 16, 0);
	NGE_Init(INIT_VIDEO);

	InitInput(on_btn_down, on_btn_up, 0);
	InitMouse(NULL, NULL);

	printf("p1_smoke: rendering %d frames at %dx%d\n", frames, SCR_W, SCR_H);
	dump_gl_state("after init");

	for (i = 0; i < frames && !g_quit; i++) {
		InputProc();
		draw_pattern(i);
		if (i == 0)
			dump_gl_state("after first frame");

		/* Grab the frame before swapping: glReadPixels hits the back
		   buffer, which is what we just drew into. */
		if (i == frames - 1)
			shot = ScreenToImage();

		EndScene();
		LimitFps(60);
	}

	if (shot != NULL) {
		if (image_save_png(shot, out, 1) != 0)
			printf("p1_smoke: wrote %s\n", out);
		else {
			printf("p1_smoke: image_save_png FAILED\n");
			rc = 3;
		}
		image_free(shot);
	} else {
		printf("p1_smoke: ScreenToImage returned NULL\n");
		rc = 4;
	}

	NGE_Quit();
	printf("p1_smoke: done (rc=%d)\n", rc);
	return rc;
}

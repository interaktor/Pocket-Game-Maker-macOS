/***************************************************************************
 *            pgm_input.c
 *
 *  输入回调桥接。
 *
 *  engine.sys 末尾会调用：
 *
 *      ControlInit("press_down","press_up","analog")
 *      TouchInit("mouse_down","mouse_up","mouse_move")
 *
 *  这里传的是 **Lua 全局函数名**。宿主必须把它们记下来，再注册成 C 回调，
 *  这样 nge2 的按键事件才能回到 Lua 的场景方法：
 *
 *      nge_mac 事件队列 -> nge_input.c InputProc -> btn_down()
 *          -> pgm_input 的跳板 -> Lua press_down(key) -> scene:key_down(key)
 *
 *  如果只是"记一下不接上"，键盘就完全没反应（之前就是这样）。
 ***************************************************************************/

#include <stdio.h>
#include <string.h>

#include "pgm.h"
#include "nge_input.h"

static char g_down[64], g_up[64], g_analog[64];
static char g_mdown[64], g_mup[64], g_mmove[64];

/* ------------------------------------------------------------------ */

static void call_lua(const char *name, int nargs, const int *argv)
{
	lua_State *L = g_pgm.L;
	int i;

	if (!name || !name[0] || !L)
		return;
	lua_getglobal(L, name);
	if (!lua_isfunction(L, -1)) {
		lua_pop(L, 1);
		return;
	}
	for (i = 0; i < nargs; i++)
		lua_pushinteger(L, argv[i]);
	if (lua_pcall(L, nargs, 0, 0) != 0) {
		const char *msg = lua_tostring(L, -1);
		pgm_log("!! 输入回调 %s 出错: %s\n", name, msg ? msg : "?");
		lua_pop(L, 1);
	}
}

static void call1(const char *name, int a)
{
	int v[1];
	v[0] = a;
	call_lua(name, 1, v);
}

/* ---- nge2 侧回调 ---- */

static void on_btn_down(int key) { call1(g_down, key); }
static void on_btn_up(int key)   { call1(g_up, key); }

static void on_analog(unsigned char x, unsigned char y)
{
	int v[2];
	v[0] = x;
	v[1] = y;
	call_lua(g_analog, 2, v);
}

/* Lua 侧签名是 mouse_down(id,x,y,prev_x,prev_y,tapCount) */
static void on_mouse_btn(int type, int x, int y)
{
	int v[6];
	v[0] = type;
	v[1] = x;
	v[2] = y;
	v[3] = 0;
	v[4] = 0;
	v[5] = 1;
	call_lua((type == MOUSE_LBUTTON_DOWN || type == MOUSE_RBUTTON_DOWN ||
			  type == MOUSE_MBUTTON_DOWN) ? g_mdown : g_mup, 6, v);
}

static void on_mouse_move(int x, int y)
{
	int v[6];
	v[0] = 1;
	v[1] = x;
	v[2] = y;
	v[3] = 0;
	v[4] = 0;
	v[5] = 1;
	call_lua(g_mmove, 6, v);
}

/* ------------------------------------------------------------------ */
/* 对 Lua 暴露的接口                                                   */
/* ------------------------------------------------------------------ */

int pgm_api_control_init(lua_State *L)
{
	const char *d = luaL_optstring(L, 1, "");
	const char *u = luaL_optstring(L, 2, "");
	const char *a = luaL_optstring(L, 3, "");

	snprintf(g_down, sizeof(g_down), "%s", d);
	snprintf(g_up, sizeof(g_up), "%s", u);
	snprintf(g_analog, sizeof(g_analog), "%s", a);

	InitInput(on_btn_down, on_btn_up, 0);
	if (a[0])
		InitAnalog(on_analog);

	pgm_log("[api ] ControlInit(%s, %s, %s) -> 已挂接\n", d, u, a);
	return 0;
}

int pgm_api_touch_init(lua_State *L)
{
	const char *d = luaL_optstring(L, 1, "");
	const char *u = luaL_optstring(L, 2, "");
	const char *m = luaL_optstring(L, 3, "");

	snprintf(g_mdown, sizeof(g_mdown), "%s", d);
	snprintf(g_mup, sizeof(g_mup), "%s", u);
	snprintf(g_mmove, sizeof(g_mmove), "%s", m);

	InitMouse(on_mouse_btn, on_mouse_move);
	pgm_log("[api ] TouchInit(%s, %s, %s) -> 已挂接\n", d, u, m);
	return 0;
}

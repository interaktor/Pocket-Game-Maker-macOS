/***************************************************************************
 *            pgm_api.c
 *
 *  PGM 原生 API 的 Lua 绑定。
 *
 *  策略：先把《PGM指令表v0.7.txt》里列出的 136 个接口全部注册成"会打印调用
 *  位置的桩"，并用 PGM_TRACE=1 打开追踪。这样跑真实脚本时，Lua 一旦报
 *  "attempt to call nil" 或行为不对，我们就能精确看到是哪一层在调什么，
 *  然后按需逐个替换成真实实现。
 *
 *  已实现真实逻辑的接口在下面 "真实实现" 分区里。
 ***************************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "pgm.h"
#include "pgm_api_names.h"

#include "nge_color.h"
#include "nge_input.h"

#define NELEM(a) ((int)(sizeof(a) / sizeof((a)[0])))

/* ================================================================== */
/* 工具                                                               */
/* ================================================================== */

static void where(lua_State *L, char *out, size_t n)
{
	lua_Debug ar;
	if (lua_getstack(L, 1, &ar) && lua_getinfo(L, "Sl", &ar))
		snprintf(out, n, "%s:%d", ar.short_src, ar.currentline);
	else
		snprintf(out, n, "?");
}

/* 通用追踪桩：名字在 upvalue[1] */
static int pgm_stub(lua_State *L)
{
	const char *name = lua_tostring(L, lua_upvalueindex(1));
	char loc[256];
	where(L, loc, sizeof(loc));
	pgm_log("[stub] %-22s (%d args)  <- %s\n", name, lua_gettop(L), loc);
	lua_pushnil(L);
	return 1;
}

static void reg_stub(lua_State *L, const char *name)
{
	lua_pushstring(L, name);
	lua_pushcclosure(L, pgm_stub, 1);
	lua_setglobal(L, name);
}

static void reg_int(lua_State *L, const char *name, lua_Integer v)
{
	lua_pushinteger(L, v);
	lua_setglobal(L, name);
}

/* ================================================================== */
/* 真实实现：封包与脚本                                               */
/* ================================================================== */

/* PackCreate(path) -> handle */
static int api_PackCreate(lua_State *L)
{
	const char *path = luaL_checkstring(L, 1);
	int h = pgm_pack_open(path);
	lua_pushinteger(L, h);
	return 1;
}

/* PGDoFile(filename) | PGDoFile(pack, filename) */
static int api_PGDoFile(lua_State *L)
{
	int h;
	const char *name;

	if (lua_gettop(L) >= 2) {
		h = (int)luaL_checkinteger(L, 1);
		name = luaL_checkstring(L, 2);
	} else {
		/* 单参数形式：直接按路径读，pack -1 时走 root 直查 */
		h = -1;
		name = luaL_checkstring(L, 1);
	}

	if (h >= 0) {
		if (pgm_do_pack_file(h, name) != 0) {
			lua_pushboolean(L, 0);
			return 1;
		}
	} else {
		char path[1200];
		if (pgm_resolve(name, path, sizeof(path)) != 0) {
			pgm_log("!! PGDoFile: 找不到 %s\n", name);
			lua_pushboolean(L, 0);
			return 1;
		}
		{
			char *buf = NULL;
			FILE *f = fopen(path, "rb");
			long n;
			if (!f) {
				lua_pushboolean(L, 0);
				return 1;
			}
			fseek(f, 0, SEEK_END);
			n = ftell(f);
			fseek(f, 0, SEEK_SET);
			buf = malloc((size_t)n + 1);
			if (buf && fread(buf, 1, (size_t)n, f) == (size_t)n) {
				buf[n] = '\0';
				pgm_do_string(buf, path);
			}
			free(buf);
			fclose(f);
		}
	}
	lua_pushboolean(L, 1);
	return 1;
}

/* PGDoString(code) */
static int api_PGDoString(lua_State *L)
{
	const char *code = luaL_checkstring(L, 1);
	lua_pushboolean(L, pgm_do_string(code, "=(PGDoString)") == 0);
	return 1;
}

/* PGSetScript(name) */
static int api_PGSetScript(lua_State *L)
{
	const char *name = luaL_checkstring(L, 1);
	snprintf(g_pgm.script, sizeof(g_pgm.script), "%s", name);
	pgm_log("PGSetScript(\"%s\")\n", name);
	return 0;
}

/* PGSetState(state) —— PGM_SCRIPT 时启动入口脚本 */
static int api_PGSetState(lua_State *L)
{
	int st = (int)luaL_checkinteger(L, 1);
	g_pgm.state = st;
	pgm_log("PGSetState(%d)\n", st);

	if (st == PGM_ST_SCRIPT && g_pgm.script[0]) {
		char path[1200];
		if (pgm_resolve(g_pgm.script, path, sizeof(path)) == 0) {
			pgm_log(">>> 启动入口脚本 %s\n", path);
			{
				char *buf = NULL;
				FILE *f = fopen(path, "rb");
				long n;
				if (!f)
					return 0;
				fseek(f, 0, SEEK_END);
				n = ftell(f);
				fseek(f, 0, SEEK_SET);
				buf = malloc((size_t)n + 1);
				if (buf && fread(buf, 1, (size_t)n, f) == (size_t)n) {
					buf[n] = '\0';
					pgm_do_string(buf, g_pgm.script);
				}
				free(buf);
				fclose(f);
			}
		} else {
			pgm_log("!! 找不到入口脚本 %s\n", g_pgm.script);
		}
	}
	return 0;
}

static int api_PGGetState(lua_State *L)
{
	lua_pushinteger(L, g_pgm.state);
	return 1;
}

static int api_FileIsExist(lua_State *L)
{
	char path[1200];
	const char *name;
	int rc;

	if (lua_gettop(L) >= 2) {
		int h = (int)luaL_checkinteger(L, 1);
		name = luaL_checkstring(L, 2);
		{
			char *data = NULL;
			size_t sz = 0;
			rc = pgm_pack_read(h, name, &data, &sz);
			free(data);
		}
		lua_pushboolean(L, rc == 0);
		return 1;
	}
	name = luaL_checkstring(L, 1);
	lua_pushboolean(L, pgm_resolve(name, path, sizeof(path)) == 0);
	return 1;
}

static int api_FolderCreate(lua_State *L)
{
	const char *d = luaL_checkstring(L, 1);
	char cmd[1300];
	snprintf(cmd, sizeof(cmd), "%s", d);
	lua_pushboolean(L, 1);
	pgm_log("[api ] FolderCreate(%s)\n", d);
	return 1;
}

/* CreatePGMSaveFolder() —— CE 的初始化会调 */
static int api_CreatePGMSaveFolder(lua_State *L)
{
	(void)L;
	pgm_log("[api ] CreatePGMSaveFolder()\n");
	return 0;
}

/* 颜色构造：复用 libnge2 的位布局，保证和渲染端一致 */
static int api_MAKE_RGBA_4444(lua_State *L)
{
	lua_pushinteger(L, (lua_Integer)MAKE_RGBA_4444(
		(int)luaL_checkinteger(L, 1), (int)luaL_checkinteger(L, 2),
		(int)luaL_checkinteger(L, 3), (int)luaL_checkinteger(L, 4)));
	return 1;
}

static int api_MAKE_RGBA_8888(lua_State *L)
{
	lua_pushinteger(L, (lua_Integer)MAKE_RGBA_8888(
		(int)luaL_checkinteger(L, 1), (int)luaL_checkinteger(L, 2),
		(int)luaL_checkinteger(L, 3), (int)luaL_checkinteger(L, 4)));
	return 1;
}

static int api_localtime(lua_State *L)
{
	time_t t = time(NULL);
	struct tm tmv;
	localtime_r(&t, &tmv);
	lua_newtable(L);
	lua_pushinteger(L, tmv.tm_year + 1900); lua_setfield(L, -2, "year");
	lua_pushinteger(L, tmv.tm_mon + 1);     lua_setfield(L, -2, "month");
	lua_pushinteger(L, tmv.tm_mday);        lua_setfield(L, -2, "day");
	lua_pushinteger(L, tmv.tm_hour);        lua_setfield(L, -2, "hour");
	lua_pushinteger(L, tmv.tm_min);         lua_setfield(L, -2, "min");
	lua_pushinteger(L, tmv.tm_sec);         lua_setfield(L, -2, "sec");
	return 1;
}

static int api_GetFullGameDataFolderPath(lua_State *L)
{
	lua_pushstring(L, g_pgm.bin);
	return 1;
}

static int api_PGMShutDown(lua_State *L)
{
	(void)L;
	g_pgm.quit = 1;
	g_pgm.state = PGM_ST_QUIT;
	return 0;
}

/* ControlInit / TouchInit：回调名，P2 阶段只记录 */
static int api_ControlInit(lua_State *L)
{
	pgm_log("[api ] ControlInit(%s, %s, %s)\n",
			luaL_optstring(L, 1, "-"), luaL_optstring(L, 2, "-"),
			luaL_optstring(L, 3, "-"));
	return 0;
}

/* InputProc() —— Lua 侧（ClassBase.lua:97）会调用，转给 nge2 的事件轮询 */
static int api_InputProc(lua_State *L)
{
	(void)L;
	InputProc();
	return 0;
}

static int api_TouchInit(lua_State *L)
{
	pgm_log("[api ] TouchInit(%s, %s, %s)\n",
			luaL_optstring(L, 1, "-"), luaL_optstring(L, 2, "-"),
			luaL_optstring(L, 3, "-"));
	return 0;
}

/* ================================================================== */
/* 注册                                                               */
/* ================================================================== */

struct real_api {
	const char *name;
	lua_CFunction fn;
};

/* 定义在文件末尾的场景合成函数 */
static int api_am_scene_render(lua_State *L);
static int api_am_scene_update(lua_State *L);

void pgm_register_api(lua_State *L)
{
	static const struct real_api reals[] = {
		{ "PackCreate",           api_PackCreate },
		{ "PGDoFile",             api_PGDoFile },
		{ "PGDoString",           api_PGDoString },
		{ "PGSetScript",          api_PGSetScript },
		{ "PGSetState",           api_PGSetState },
		{ "PGGetState",           api_PGGetState },
		{ "FileIsExist",          api_FileIsExist },
		{ "FolderCreate",         api_FolderCreate },
		{ "CreatePGMSaveFolder",  api_CreatePGMSaveFolder },
		{ "MAKE_RGBA_4444",       api_MAKE_RGBA_4444 },
		{ "MAKE_RGBA_8888",       api_MAKE_RGBA_8888 },
		{ "localtime",            api_localtime },
		{ "GetFullGameDataFolderPath", api_GetFullGameDataFolderPath },
		{ "PGMShutDown",          api_PGMShutDown },
		{ "ControlInit",          api_ControlInit },
		{ "TouchInit",            api_TouchInit },
		{ "InputProc",            api_InputProc },
		{ "am_scene_render",      api_am_scene_render },
		{ "am_scene_update",      api_am_scene_update },
	};
	int i;

	/* --- 1. 文档里列出的接口先全部装成桩 --- */
	for (i = 0; i < NELEM(PGM_API_NAMES); i++)
		reg_stub(L, PGM_API_NAMES[i]);

	/* --- 2. 宏/常量 --- */
	for (i = 0; i < NELEM(PGM_API_MACROS); i++)
		reg_int(L, PGM_API_MACROS[i], i);

	/* --- 3. 真实实现覆盖掉对应的桩 --- */
	for (i = 0; i < NELEM(reals); i++) {
		lua_pushcfunction(L, reals[i].fn);
		lua_setglobal(L, reals[i].name);
	}

	/* --- 3.5 图形 / 字体 / 计时器 / 事件脚本真实实现 --- */
	pgm_gfx_register(L);
	pgm_escript_register(L);
	pgm_mem_register(L);
	pgm_dialog_register(L);

	/* --- 4. 有确定数值的常量 --- */
	reg_int(L, "PGM_QUIT",   PGM_ST_QUIT);
	reg_int(L, "PGM_SCRIPT", PGM_ST_SCRIPT);
	reg_int(L, "PGM_INIT",   PGM_ST_INIT);
	reg_int(L, "PGM_LOOP",   PGM_ST_LOOP);
	reg_int(L, "PGM_FINI",   PGM_ST_FINI);

	/* 按键码：与 Windows 版一致，由 nge_mac 后端翻译 macOS 虚拟键码而来 */
	reg_int(L, "PSP_BUTTON_UP",            PSP_BUTTON_UP);
	reg_int(L, "PSP_BUTTON_DOWN",          PSP_BUTTON_DOWN);
	reg_int(L, "PSP_BUTTON_LEFT",          PSP_BUTTON_LEFT);
	reg_int(L, "PSP_BUTTON_RIGHT",         PSP_BUTTON_RIGHT);
	reg_int(L, "PSP_BUTTON_TRIANGLE",      PSP_BUTTON_TRIANGLE);
	reg_int(L, "PSP_BUTTON_CIRCLE",        PSP_BUTTON_CIRCLE);
	reg_int(L, "PSP_BUTTON_CROSS",         PSP_BUTTON_CROSS);
	reg_int(L, "PSP_BUTTON_SQUARE",        PSP_BUTTON_SQUARE);
	reg_int(L, "PSP_BUTTON_LEFT_TRIGGER",  PSP_BUTTON_LEFT_TRIGGER);
	reg_int(L, "PSP_BUTTON_RIGHT_TRIGGER", PSP_BUTTON_RIGHT_TRIGGER);
	reg_int(L, "PSP_BUTTON_SELECT",        PSP_BUTTON_SELECT);
	reg_int(L, "PSP_BUTTON_START",         PSP_BUTTON_START);
	reg_int(L, "PSP_BUTTON_HOME",          PSP_BUTTON_HOME);
	reg_int(L, "PSP_BUTTON_HOLD",          PSP_BUTTON_HOLD);

	/* 图像格式 */
	reg_int(L, "IMG_8888", DISPLAY_PIXEL_FORMAT_8888);
	reg_int(L, "IMG_4444", DISPLAY_PIXEL_FORMAT_4444);
	reg_int(L, "IMG_5551", DISPLAY_PIXEL_FORMAT_5551);
	reg_int(L, "IMG_565",  DISPLAY_PIXEL_FORMAT_565);
}

/* ================================================================== */
/* am_scene_render / am_scene_update —— PGM 的场景合成层              */
/*                                                                    */
/* am_scene 里 bg / texfg / fg / ani 四组对象（FGBase / TexFgBase /    */
/* ANIBase）各自实现了 render() 与 update()，所以这里只需要按层序把它们 */
/* 依次调一遍。层序与 PGM 的绘制顺序一致：背景 -> 纹理立绘 -> 普通立绘 -> */
/* 动画。                                                             */
/* ================================================================== */

static const char *PGM_SCENE_LAYERS[] = { "bg", "texfg", "fg", "ani", NULL };

static int call_obj_method(lua_State *L, const char *method)
{
	if (!lua_istable(L, -1))
		return 0;
	lua_getfield(L, -1, method);
	if (!lua_isfunction(L, -1)) {
		lua_pop(L, 1);
		return 0;
	}
	/* self 作为第一个参数 */
	lua_pushvalue(L, -2);
	if (lua_pcall(L, 1, 0, 0) != 0) {
		const char *msg = lua_tostring(L, -1);
		pgm_log("!! %s() 出错: %s\n", method, msg ? msg : "?");
		lua_pop(L, 1);
		return 0;
	}
	return 1;
}

static int scene_walk(lua_State *L, const char *method)
{
	int gi;

	lua_getglobal(L, "am_scene");
	if (!lua_istable(L, -1)) {
		lua_pop(L, 1);
		return 0;
	}

	for (gi = 0; PGM_SCENE_LAYERS[gi]; gi++) {
		int i, n;
		lua_getfield(L, -1, PGM_SCENE_LAYERS[gi]);
		if (!lua_istable(L, -1)) {
			lua_pop(L, 1);
			continue;
		}
		n = (int)lua_objlen(L, -1);
		for (i = 1; i <= n; i++) {
			lua_rawgeti(L, -1, i);          /* obj */
			if (lua_istable(L, -1))
				call_obj_method(L, method);
			lua_pop(L, 1);
		}
		lua_pop(L, 1);                       /* 组 */
	}
	lua_pop(L, 1);                           /* am_scene */
	return 0;
}

static int api_am_scene_render(lua_State *L)
{
	scene_walk(L, "render");
	return 0;
}

static int api_am_scene_update(lua_State *L)
{
	scene_walk(L, "update");
	return 0;
}

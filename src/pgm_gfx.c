/***************************************************************************
 *            pgm_gfx.c
 *
 *  PGM 原生 API 的图形 / 字体 / 计时器实现，全部架在 libnge2 之上。
 *
 *  约定：
 *    * image 与 font 用 Lua userdata 包装，靠 __gc 自动释放，避免泄漏；
 *    * 资源通过封包句柄读取（gmdata.bin 资源包），不直接碰文件系统，
 *      这样玩家拿到的"只有 bin/ 目录"的游戏也能跑。
 ***************************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "pgm.h"

#include "nge.h"
#include "nge_color.h"
#include "nge_graphics.h"
#include "nge_image.h"
#include "nge_font.h"
#include "nge_timer.h"
#include "nge_png.h"
#include "nge_debug_log.h"
#include "nge_input.h"

#define NELEM(a) ((int)(sizeof(a) / sizeof((a)[0])))

/* ================================================================== */
/* image / font 的 userdata 包装                                      */
/* ================================================================== */

typedef struct {
	image_p img;
} pgm_image_ud;

typedef struct {
	PFont pf;
} pgm_font_ud;

typedef struct {
	nge_timer *t;
} pgm_timer_ud;

static int im_gc(lua_State *L)
{
	pgm_image_ud *u = (pgm_image_ud *)lua_touserdata(L, 1);
	if (u && u->img) {
		image_free(u->img);
		u->img = NULL;
	}
	return 0;
}

static int font_gc(lua_State *L)
{
	pgm_font_ud *u = (pgm_font_ud *)lua_touserdata(L, 1);
	if (u && u->pf) {
		font_destory(u->pf);
		u->pf = NULL;
	}
	return 0;
}

static int timer_gc(lua_State *L)
{
	pgm_timer_ud *u = (pgm_timer_ud *)lua_touserdata(L, 1);
	if (u && u->t) {
		timer_free(u->t);
		u->t = NULL;
	}
	return 0;
}

static void new_meta(lua_State *L, const char *name, lua_CFunction gc)
{
	luaL_newmetatable(L, name);
	lua_pushcfunction(L, gc);
	lua_setfield(L, -2, "__gc");
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);
}

static pgm_image_ud *push_image(lua_State *L, image_p img)
{
	pgm_image_ud *u;
	if (!img) {
		lua_pushnil(L);
		return NULL;
	}
	u = (pgm_image_ud *)lua_newuserdata(L, sizeof(*u));
	u->img = img;
	luaL_getmetatable(L, "PGMImage");
	lua_setmetatable(L, -2);
	return u;
}

/* 从 Lua 取 image_p；nil / lightuserdata / userdata 都接受 */
static image_p to_image(lua_State *L, int idx)
{
	if (lua_isnoneornil(L, idx))
		return NULL;
	if (lua_type(L, idx) == LUA_TUSERDATA) {
		pgm_image_ud *u = (pgm_image_ud *)lua_touserdata(L, idx);
		if (u && u->img)
			return u->img;
	}
	return NULL;
}

static PFont to_font(lua_State *L, int idx)
{
	if (lua_isnoneornil(L, idx))
		return NULL;
	if (lua_type(L, idx) == LUA_TUSERDATA) {
		pgm_font_ud *u = (pgm_font_ud *)lua_touserdata(L, idx);
		if (u && u->pf)
			return u->pf;
	}
	return NULL;
}

/* ================================================================== */
/* 图像                                                               */
/* ================================================================== */

static int api_ImageCreate(lua_State *L)
{
	int w = (int)luaL_checkinteger(L, 1);
	int h = (int)luaL_checkinteger(L, 2);
	int mode = (int)luaL_optinteger(L, 3, DISPLAY_PIXEL_FORMAT_4444);
	push_image(L, image_create(w, h, mode));
	return 1;
}

/* ImageLoad([pack,] filename [, mode]) */
static int api_ImageLoad(lua_State *L)
{
	int top = lua_gettop(L);
	int pack = -1, idx = 1, mode = DISPLAY_PIXEL_FORMAT_4444;
	const char *name;
	char *data = NULL;
	size_t size = 0;
	image_p img = NULL;
	const char *path = NULL;
	char resolved[1024];

	if (top >= 3 || (top >= 2 && lua_isnumber(L, 1))) {
		pack = (int)luaL_checkinteger(L, 1);
		idx = 2;
	}
	name = luaL_checkstring(L, idx);
	if (top > idx && lua_isnumber(L, idx + 1))
		mode = (int)luaL_checkinteger(L, idx + 1);

	if (pack >= 0 && pgm_pack_read(pack, name, &data, &size) == 0) {
		img = image_load_buf(data, (int)size, mode, 0);
		free(data);
	}
	if (!img) {
		/* 回退：直接查文件（开发期 src/ 或 bin/ 下的散装资源） */
		if (pgm_resolve(name, resolved, sizeof(resolved)) == 0)
			path = resolved;
		if (path)
			img = image_load(path, mode, 0);
	}
	if (getenv("PGM_TRACE_IMG"))
		pgm_log("[img] %-20s pack=%d -> %s\n", name, pack,
				img ? "OK" : "失败");
	if (!img)
		pgm_log("!! ImageLoad 失败: %s\n", name);
	push_image(L, img);
	return 1;
}

static int api_ImageFree(lua_State *L)
{
	pgm_image_ud *u = (pgm_image_ud *)lua_touserdata(L, 1);
	if (u && u->img) {
		image_free(u->img);
		u->img = NULL;
	}
	return 0;
}

static int api_ImageGetW(lua_State *L)
{
	image_p img = to_image(L, 1);
	lua_pushinteger(L, img ? (lua_Integer)img->w : 0);
	return 1;
}

static int api_ImageGetH(lua_State *L)
{
	image_p img = to_image(L, 1);
	lua_pushinteger(L, img ? (lua_Integer)img->h : 0);
	return 1;
}

static int api_ImageClone(lua_State *L)
{
	push_image(L, image_clone(to_image(L, 1)));
	return 1;
}

/* ImageClear(img) —— 清空图像内容（DialogLayer:clear 用它清文本层） */
static int api_ImageClear(lua_State *L)
{
	image_p img = to_image(L, 1);
	if (img)
		image_clear(img);
	return 0;
}

static int api_ImageSetMask(lua_State *L)
{
	image_p img = to_image(L, 1);
	if (img && lua_gettop(L) >= 2)
		img->mask = (uint32_t)luaL_checkinteger(L, 2);
	return 0;
}

/* DrawImage(img, sx,sy,sw,sh, dx,dy,dw,dh) */
static int api_DrawImage(lua_State *L)
{
	image_p img = to_image(L, 1);
	if (!img)
		return 0;
	DrawImage(img,
			  (float)luaL_optnumber(L, 2, 0), (float)luaL_optnumber(L, 3, 0),
			  (float)luaL_optnumber(L, 4, (lua_Number)img->w),
			  (float)luaL_optnumber(L, 5, (lua_Number)img->h),
			  (float)luaL_optnumber(L, 6, 0), (float)luaL_optnumber(L, 7, 0),
			  (float)luaL_optnumber(L, 8, (lua_Number)img->w),
			  (float)luaL_optnumber(L, 9, (lua_Number)img->h));
	return 0;
}

/* RenderQuad(img, sx,sy,sw,sh, dx,dy, xscale,yscale, angle, mask) */
static int api_RenderQuad(lua_State *L)
{
	image_p img = to_image(L, 1);
	if (!img)
		return 0;
	RenderQuad(img,
			   (float)luaL_optnumber(L, 2, 0), (float)luaL_optnumber(L, 3, 0),
			   (float)luaL_optnumber(L, 4, (lua_Number)img->w),
			   (float)luaL_optnumber(L, 5, (lua_Number)img->h),
			   (float)luaL_optnumber(L, 6, 0), (float)luaL_optnumber(L, 7, 0),
			   (float)luaL_optnumber(L, 8, 1), (float)luaL_optnumber(L, 9, 1),
			   (float)luaL_optnumber(L, 10, 0),
			   (int)luaL_optinteger(L, 11, (lua_Integer)img->mask));
	return 0;
}

static int api_ImageToScreen(lua_State *L)
{
	image_p img = to_image(L, 1);
	if (!img)
		return 0;
	ImageToScreen(img, (float)luaL_optnumber(L, 2, 0),
				  (float)luaL_optnumber(L, 3, 0));
	return 0;
}

static int api_SetClip(lua_State *L)
{
	SetClip((int)luaL_checkinteger(L, 1), (int)luaL_checkinteger(L, 2),
			(int)luaL_checkinteger(L, 3), (int)luaL_checkinteger(L, 4));
	return 0;
}

static int api_ResetClip(lua_State *L)
{
	(void)L;
	ResetClip();
	return 0;
}

static int api_SetScreenColor(lua_State *L)
{
	SetScreenColor((uint8_t)luaL_optinteger(L, 1, 0),
				   (uint8_t)luaL_optinteger(L, 2, 0),
				   (uint8_t)luaL_optinteger(L, 3, 0),
				   (uint8_t)luaL_optinteger(L, 4, 255));
	return 0;
}

static int api_BeginScene(lua_State *L)
{
	BeginScene((uint8_t)luaL_optinteger(L, 1, 1));
	return 0;
}

static int api_EndScene(lua_State *L)
{
	(void)L;
	EndScene();
	return 0;
}

static int api_ScreenToImage(lua_State *L)
{
	(void)L;
	push_image(L, ScreenToImage());
	return 1;
}

/* ================================================================== */
/* 字体                                                               */
/* ================================================================== */

/* FontCreate(file, size) */
static int api_FontCreate(lua_State *L)
{
	const char *file = luaL_checkstring(L, 1);
	int size = (int)luaL_optinteger(L, 2, 12);
	char resolved[1024];
	const char *path = file;
	PFont pf = NULL;
	pgm_font_ud *u;

	/* 字体是散装文件（bin/data/font/ 下），不走封包 */
	if (pgm_resolve(file, resolved, sizeof(resolved)) == 0)
		path = resolved;
	else {
		char buf[1300];
		snprintf(buf, sizeof(buf), "%s/../data/font/%s", g_pgm.bin, file);
		if (access(buf, R_OK) == 0)
			path = buf;
	}

	pf = create_font_freetype(path, size, DISPLAY_PIXEL_FORMAT_4444);
	if (!pf)
		pgm_log("!! FontCreate 失败: %s\n", path);

	u = (pgm_font_ud *)lua_newuserdata(L, sizeof(*u));
	u->pf = pf;
	luaL_getmetatable(L, "PGMFont");
	lua_setmetatable(L, -2);
	return 1;
}

static int api_FontSetColor(lua_State *L)
{
	PFont pf = to_font(L, 1);
	if (pf && lua_gettop(L) >= 2)
		font_setcolor(pf, (uint32_t)luaL_checkinteger(L, 2));
	return 0;
}

/* FontDraw(font, area_image, text, dx, dy)
 *
 * 注意参数顺序是"绘制区图像在前、文本在后"（见 SpeakScene.lua:410），
 * 但 Lua 侧也有 (font, text, area, dx, dy) 的写法，所以这里按类型自动识别：
 * 第 2 个参数若是 image userdata 就当 area，否则当文本。
 */
static int api_FontDraw(lua_State *L)
{
	PFont pf = to_font(L, 1);
	image_p area = NULL;
	const char *text = NULL;
	int dx, dy;

	if (to_image(L, 2)) {
		area = to_image(L, 2);
		text = luaL_optstring(L, 3, "");
		dx = (int)luaL_optinteger(L, 4, 0);
		dy = (int)luaL_optinteger(L, 5, 0);
	} else {
		text = luaL_optstring(L, 2, "");
		area = to_image(L, 3);
		dx = (int)luaL_optinteger(L, 4, 0);
		dy = (int)luaL_optinteger(L, 5, 0);
	}

	if (pf && text && text[0])
		font_drawtext(pf, text, (int)strlen(text), area, dx, dy,
					  FONT_SHOW_NORMAL);
	return 0;
}

static int api_FontResize(lua_State *L)
{
	(void)L;
	return 0;
}

static int api_FontDelete(lua_State *L)
{
	pgm_font_ud *u = (pgm_font_ud *)lua_touserdata(L, 1);
	if (u && u->pf) {
		font_destory(u->pf);
		u->pf = NULL;
	}
	return 0;
}

/* ================================================================== */
/* 计时器                                                             */
/* ================================================================== */

static int api_TimerCreate(lua_State *L)
{
	pgm_timer_ud *u = (pgm_timer_ud *)lua_newuserdata(L, sizeof(*u));
	u->t = timer_create();
	luaL_getmetatable(L, "PGMTimer");
	lua_setmetatable(L, -2);
	return 1;
}

static nge_timer *to_timer(lua_State *L, int idx)
{
	pgm_timer_ud *u;
	if (lua_type(L, idx) != LUA_TUSERDATA)
		return NULL;
	u = (pgm_timer_ud *)lua_touserdata(L, idx);
	return u ? u->t : NULL;
}

static int api_TimerStart(lua_State *L)
{
	nge_timer *t = to_timer(L, 1);
	if (t)
		t->start(t);
	return 0;
}

static int api_TimerStop(lua_State *L)
{
	nge_timer *t = to_timer(L, 1);
	if (t)
		t->stop(t);
	return 0;
}

static int api_TimerGetTicks(lua_State *L)
{
	nge_timer *t = to_timer(L, 1);
	lua_pushinteger(L, t ? (lua_Integer)t->get_ticks(t) : 0);
	return 1;
}

static int api_TimerDelete(lua_State *L)
{
	pgm_timer_ud *u = (pgm_timer_ud *)lua_touserdata(L, 1);
	if (u && u->t) {
		timer_free(u->t);
		u->t = NULL;
	}
	return 0;
}

/* ================================================================== */
/* 音频占位（P4 接 CoreAudio）                                        */
/* ================================================================== */

static int api_SoundCreate(lua_State *L)
{
	lua_pushinteger(L, 1);
	return 1;
}

static int api_SoundNoop(lua_State *L)
{
	(void)L;
	return 0;
}

/* ================================================================== */
/* 文本层清空                                                          */
/*                                                                    */
/* textclear 是原生 API。Lua 侧的文本层是 DialogLayer.new()，它的 quad[]  */
/* 是一组离屏 image，文字先画在 quad 上、再由 text_layer_render() 贴到屏幕。 */
/* 不实现 textclear 的话上一句不会消失，会和下一句叠在一起。              */
/* ================================================================== */

static int api_textclear(lua_State *L)
{
	int i, n;

	lua_getglobal(L, "text_layer");
	if (!lua_istable(L, -1)) {
		lua_pop(L, 1);
		return 0;
	}
	lua_getfield(L, -1, "quad");
	if (!lua_istable(L, -1)) {
		lua_pop(L, 2);
		return 0;
	}
	n = (int)lua_objlen(L, -1);
	for (i = 1; i <= n; i++) {
		image_p img;
		lua_rawgeti(L, -1, i);
		img = to_image(L, -1);
		if (img)
			image_clear(img);
		lua_pop(L, 1);
	}
	lua_pop(L, 2);
	return 0;
}

/* ================================================================== */
/* 注册                                                               */
/* ================================================================== */

struct gfx_api {
	const char *name;
	lua_CFunction fn;
};

void pgm_gfx_register(lua_State *L)
{
	static const struct gfx_api api[] = {
		{ "ImageCreate",     api_ImageCreate },
		{ "ImageLoad",       api_ImageLoad },
		{ "CacheImageLoad",  api_ImageLoad },   /* PGM 的缓存版，语义相同 */
		{ "ImageFree",       api_ImageFree },
		{ "ImageGetW",       api_ImageGetW },
		{ "ImageGetH",       api_ImageGetH },
		{ "ImageClone",      api_ImageClone },
		{ "ImageClear",      api_ImageClear },
		{ "ImageSetMask",    api_ImageSetMask },
		{ "DrawImage",       api_DrawImage },
		{ "RenderQuad",      api_RenderQuad },
		{ "ImageToScreen",   api_ImageToScreen },
		{ "SetClip",         api_SetClip },
		{ "ResetClip",       api_ResetClip },
		{ "SetScreenColor",  api_SetScreenColor },
		{ "BeginScene",      api_BeginScene },
		{ "EndScene",        api_EndScene },
		{ "ScreenToImage",   api_ScreenToImage },
		{ "textclear",       api_textclear },

		{ "FontCreate",      api_FontCreate },
		{ "FontSetColor",    api_FontSetColor },
		{ "FontDraw",        api_FontDraw },
		{ "FontResize",      api_FontResize },
		{ "FontDelete",      api_FontDelete },

		{ "TimerCreate",     api_TimerCreate },
		{ "TimerStart",      api_TimerStart },
		{ "TimerStop",       api_TimerStop },
		{ "TimerGetTicks",   api_TimerGetTicks },
		{ "TimerDelete",     api_TimerDelete },

		{ "SoundCreate",     api_SoundCreate },
		{ "CacheClear",      api_SoundNoop },   /* 缓存清理：我们不做缓存 */
	};
	int i;

	new_meta(L, "PGMImage", im_gc);
	new_meta(L, "PGMFont", font_gc);
	new_meta(L, "PGMTimer", timer_gc);

	for (i = 0; i < NELEM(api); i++) {
		lua_pushcfunction(L, api[i].fn);
		lua_setglobal(L, api[i].name);
	}
	/* 音频接口先全部注册成 no-op，P4 换成真实实现 */
	{
		static const char *sound_noop[] = {
			"SoundLoad", "SoundUnload", "SoundPlay", "SoundStop",
			"SoundPause", "SoundResume", "SoundRewind", "SoundVolume",
			"SoundEos", "SoundDelete", "bgm", "bgmstop", "bgmfade",
			"voice", "voicestop", "voicereplay", "sound", "soundstop",
			"mp3load", "mp3unload", "mp3play", "mp3stop", "mp3pause",
			"mp3resume", "mp3replay", "mp3volume", "mp3playtime",
			"mp3isfinish", "mp3fadein", "mp3fadeout",
			"MovieCreate", "MovieDelete", "MoviePlay", "MovieEos",
			"pmplay",
		};
		int k;
		for (k = 0; k < NELEM(sound_noop); k++)
			lua_register(L, sound_noop[k], api_SoundNoop);
	}
}

/* ================================================================== */
/* 视频初始化 / 截图                                                  */
/* ================================================================== */

static int lua_int_global(lua_State *L, const char *name, int def)
{
	int v = def;
	lua_getglobal(L, name);
	if (lua_isnumber(L, -1))
		v = (int)lua_tointeger(L, -1);
	lua_pop(L, 1);
	return v;
}

static const char *lua_str_global(lua_State *L, const char *name,
								  const char *def)
{
	static char buf[128];
	const char *s = def;
	lua_getglobal(L, name);
	if (lua_isstring(L, -1))
		s = lua_tostring(L, -1);
	snprintf(buf, sizeof(buf), "%s", s);
	lua_pop(L, 1);
	return buf;
}

static int gfx_inited = 0;

int pgm_gfx_start(void)
{
	lua_State *L = g_pgm.L;
	int w, h, bpp, full;
	const char *name;

	if (gfx_inited)
		return 0;

	w = lua_int_global(L, "PGM_SCREEN_WIDTH", 480);
	h = lua_int_global(L, "PGM_SCREEN_HEIGHT", 272);
	bpp = 16;
	lua_getglobal(L, "PGM_SCREEN_FULL");
	full = lua_toboolean(L, -1);
	lua_pop(L, 1);
	name = lua_str_global(L, "PGM_SCREEN_NAME", "PGM-Mac");

	pgm_log("视频: %dx%d full=%d \"%s\"\n", w, h, full, name);

	NGE_SetScreenContext(name, w, h, bpp, full);
	NGE_Init(INIT_VIDEO);
	InitInput(NULL, NULL, 0);
	InitMouse(NULL, NULL);

	gfx_inited = 1;
	return 0;
}

void pgm_gfx_capture(const char *png)
{
	image_p shot;

	if (!png || !gfx_inited)
		return;
	shot = ScreenToImage();
	if (!shot) {
		pgm_log("!! 截图失败: ScreenToImage 返回 NULL\n");
		return;
	}
	if (image_save_png(shot, png, 1) != 0)
		pgm_log("截图已写出: %s\n", png);
	else
		pgm_log("!! 截图写出失败: %s\n", png);
	image_free(shot);
}

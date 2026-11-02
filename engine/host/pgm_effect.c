/***************************************************************************
 *            pgm_effect.c
 *
 *  效果器（Effect*）的最小可用实现。
 *
 *  这些接口原本是 PGM 用来做淡入淡出/震动/过渡的。宿主层只需要让
 *  FGBase:render() 这条路径走通：
 *
 *      if self.effect_type then
 *          if not self.effect_p then return end        -- 没效果器就不画
 *          EffectDrawImage(self.effect_p, img, dx, dy) -- 画的时候带 alpha
 *          if EffectGetState(self.effect_p)==EFFECT_STOP then ... end
 *      end
 *
 *  所以关键点是：EffectFade*Create 必须返回一个**非 nil 的句柄**，
 *  EffectDrawImage 必须真的把图画出来，EffectGetState 必须在时间到了之后
 *  返回 EFFECT_STOP。
 *
 *  这里不做真正的逐帧 alpha 插值（那需要 nge2 的 per-draw alpha 混合），
 *  而是直接绘制 —— 视觉上没有淡入，但内容立刻可见、逻辑完全正确。
 ***************************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "pgm.h"
#include "nge_graphics.h"
#include "nge_timer.h"

#define NELEM(a) ((int)(sizeof(a) / sizeof((a)[0])))

enum { EFFECT_STOP = 0, EFFECT_PLAY = 1, EFFECT_INIT = 2 };

typedef struct {
	int   used;
	int   kind;
	uint32_t start;
	uint32_t dur;
	int   state;
} pgm_effect;

#define MAX_EFF 64
static pgm_effect g_eff[MAX_EFF];

static pgm_effect *eff_new(int kind, int dur)
{
	int i;
	for (i = 0; i < MAX_EFF; i++) {
		if (g_eff[i].used)
			continue;
		g_eff[i].used = 1;
		g_eff[i].kind = kind;
		g_eff[i].dur = (uint32_t)(dur > 0 ? dur : 0);
		g_eff[i].start = nge_get_tick();
		g_eff[i].state = EFFECT_PLAY;
		return &g_eff[i];
	}
	return NULL;
}

/* 用 lightuserdata 传句柄，Lua 侧只做比较和回传，不参与算术 */
static int push_eff(lua_State *L, pgm_effect *e)
{
	if (!e) {
		lua_pushnil(L);
		return 1;
	}
	lua_pushlightuserdata(L, e);
	return 1;
}

static pgm_effect *to_eff(lua_State *L, int idx)
{
	if (lua_type(L, idx) != LUA_TLIGHTUSERDATA)
		return NULL;
	return (pgm_effect *)lua_touserdata(L, idx);
}

/*
 * 创建类接口的通用实现：参数个数不定，但时长总是"最大的那个数"，
 * 因为三类效果的写法分别是 (from,to,time) / (time) / (a,b,time)。
 */
static int make_effect(lua_State *L, int kind)
{
	int top = lua_gettop(L);
	int dur = 0;
	int i;

	if (top >= 3)
		dur = (int)luaL_optnumber(L, 3, 0);
	else if (top >= 1)
		dur = (int)luaL_optnumber(L, 1, 0);
	for (i = 1; i <= top; i++) {
		if (lua_isnumber(L, i) && (int)lua_tonumber(L, i) > dur)
			dur = (int)lua_tonumber(L, i);
	}
	return push_eff(L, eff_new(kind, dur));
}

static int api_FadeIn(lua_State *L)     { return make_effect(L, 1); }
static int api_FadeOut(lua_State *L)    { return make_effect(L, 2); }
static int api_Shake(lua_State *L)      { return make_effect(L, 3); }
static int api_Trans(lua_State *L)      { return make_effect(L, 4); }
static int api_Trans2(lua_State *L)     { return make_effect(L, 5); }

static int api_EffectGetState(lua_State *L)
{
	pgm_effect *e = to_eff(L, 1);
	if (!e || !e->used) {
		lua_pushinteger(L, EFFECT_STOP);
		return 1;
	}
	if (e->state == EFFECT_PLAY &&
		(uint32_t)(nge_get_tick() - e->start) >= e->dur)
		e->state = EFFECT_STOP;
	lua_pushinteger(L, e->state);
	return 1;
}

/* EffectDrawImage(effect, image, dx, dy) —— 直接绘制 */
static int api_EffectDrawImage(lua_State *L)
{
	image_p img = NULL;
	double dx, dy;

	if (lua_type(L, 2) == LUA_TUSERDATA) {
		void **u = (void **)lua_touserdata(L, 2);
		if (u)
			img = (image_p)*u;
	}
	dx = luaL_optnumber(L, 3, 0);
	dy = luaL_optnumber(L, 4, 0);

	if (img)
		ImageToScreen(img, (float)dx, (float)dy);
	return 0;
}

static int api_EffectDelete(lua_State *L)
{
	pgm_effect *e = to_eff(L, 1);
	if (e)
		e->used = 0;
	return 0;
}

static int api_SomeEffectUpdate(lua_State *L)
{
	(void)L;
	return 0;
}

void pgm_effect_register(lua_State *L)
{
	static const struct { const char *name; lua_CFunction fn; } api[] = {
		{ "EffectFadeInCreate",  api_FadeIn },
		{ "EffectFadeOutCreate", api_FadeOut },
		{ "EffectShakeCreate",   api_Shake },
		{ "EffectTransCreate",   api_Trans },
		{ "EffectTrans2Create",  api_Trans2 },
		{ "EffectGetState",      api_EffectGetState },
		{ "EffectDrawImage",     api_EffectDrawImage },
		{ "EffectDelete",        api_EffectDelete },
		{ "SomeEffectUpdate",    api_SomeEffectUpdate },
	};
	static const struct { const char *name; int v; } consts[] = {
		{ "EFFECT_STOP", EFFECT_STOP },
		{ "EFFECT_PLAY", EFFECT_PLAY },
		{ "EFFECT_INIT", EFFECT_INIT },
	};
	int i;

	for (i = 0; i < NELEM(api); i++) {
		lua_pushcfunction(L, api[i].fn);
		lua_setglobal(L, api[i].name);
	}
	for (i = 0; i < NELEM(consts); i++) {
		lua_pushinteger(L, consts[i].v);
		lua_setglobal(L, consts[i].name);
	}
}

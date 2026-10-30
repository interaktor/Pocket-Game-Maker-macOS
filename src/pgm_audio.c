/***************************************************************************
 *            pgm_audio.c
 *
 *  把 PGM 的音频 API 接到 libnge2 的 coolaudio 之上（macOS 后端是
 *  AVAudioPlayer，见 third_party/libnge2/coolaudio/nge_audio_mac.m）。
 *
 *  Lua 侧的签名（见 cefunctions.lua / base.lua）：
 *      mp3load(file, index)        按槽位加载 BGM
 *      mp3play/stop/pause/resume/replay(index)
 *      mp3volume(index, vol)  mp3isfinish(index)  mp3playtime(index)
 *      SoundCreate(pos)            创建一个音效对象，返回句柄
 *      SoundLoad(h, filename) / SoundLoad(h, buf, size)
 *      SoundPlay(h, times)  SoundStop/Pause/Resume/Unload/Volume(h, ...)
 *
 *  文件名会依次在 bin/data/{bgm,voice,sound}/ 下查找。
 ***************************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "pgm.h"
#include "audio_interface.h"

#define NELEM(a) ((int)(sizeof(a) / sizeof((a)[0])))
#define MP3_SLOTS 8

static audio_play_p g_mp3[MP3_SLOTS];

/* 把音频文件名解析成真实路径 */
static int resolve_audio(const char *name, char *out, size_t outsz)
{
	static const char *dirs[] = { "bgm/", "voice/", "sound/", "video/", NULL };
	struct stat st;
	int i;

	if (!name || !name[0])
		return -1;

	for (i = 0; dirs[i]; i++) {
		snprintf(out, outsz, "%s/data/%s%s", g_pgm.bin, dirs[i], name);
		if (stat(out, &st) == 0)
			return 0;
	}
	/* 再试绝对路径 / 工程相对路径 */
	if (pgm_resolve(name, out, outsz) == 0)
		return 0;
	snprintf(out, outsz, "%s", name);
	return 0;
}

static audio_play_p slot(lua_State *L, int idx)
{
	int i = (int)luaL_optinteger(L, idx, 0);
	if (i < 0 || i >= MP3_SLOTS)
		return NULL;
	return g_mp3[i];
}

/* ---- mp3 槽位 ---- */

static int api_mp3load(lua_State *L)
{
	const char *file = luaL_checkstring(L, 1);
	int i = (int)luaL_optinteger(L, 2, -1);
	char path[1200];
	audio_play_p p;

	if (i < 0 || i >= MP3_SLOTS)
		return 0;
	resolve_audio(file, path, sizeof(path));

	if (!g_mp3[i])
		g_mp3[i] = CreateMp3Player();
	p = g_mp3[i];
	if (p)
		p->load(p, path);
	return 0;
}

static int api_mp3play(lua_State *L)
{
	audio_play_p p = slot(L, 1);
	if (p)
		p->play(p, -1, 0);      /* 循环播放 */
	return 0;
}

static int api_mp3stop(lua_State *L)
{
	audio_play_p p = slot(L, 1);
	if (p)
		p->stop(p);
	return 0;
}

static int api_mp3pause(lua_State *L)
{
	audio_play_p p = slot(L, 1);
	if (p)
		p->pause(p);
	return 0;
}

static int api_mp3resume(lua_State *L)
{
	audio_play_p p = slot(L, 1);
	if (p)
		p->resume(p);
	return 0;
}

static int api_mp3replay(lua_State *L)
{
	audio_play_p p = slot(L, 1);
	if (p) {
		p->rewind(p);
		p->play(p, -1, 0);
	}
	return 0;
}

static int api_mp3volume(lua_State *L)
{
	audio_play_p p = slot(L, 1);
	int v = (int)luaL_optinteger(L, 2, 100);
	if (p)
		p->volume(p, v);
	return 0;
}

static int api_mp3unload(lua_State *L)
{
	int i = (int)luaL_optinteger(L, 1, -1);
	if (i >= 0 && i < MP3_SLOTS && g_mp3[i]) {
		g_mp3[i]->destroy(g_mp3[i]);
		g_mp3[i] = NULL;
	}
	return 0;
}

static int api_mp3isfinish(lua_State *L)
{
	audio_play_p p = slot(L, 1);
	lua_pushboolean(L, p ? p->iseof(p) : 1);
	return 1;
}

static int api_mp3playtime(lua_State *L)
{
	audio_play_p p = slot(L, 1);
	(void)p;
	lua_pushinteger(L, 0);   /* 虚表没暴露当前时间，暂返回 0 */
	return 1;
}

/* ---- 音效对象 ---- */

static int api_SoundCreate(lua_State *L)
{
	audio_play_p p = CreateWavPlayer();
	(void)L;
	if (!p) {
		lua_pushnil(L);
		return 1;
	}
	lua_pushlightuserdata(L, p);
	return 1;
}

static audio_play_p to_sound(lua_State *L, int idx)
{
	if (lua_type(L, idx) != LUA_TLIGHTUSERDATA)
		return NULL;
	return (audio_play_p)lua_touserdata(L, idx);
}

/* SoundLoad(h, filename) | SoundLoad(h, buffer, size) */
static int api_SoundLoad(lua_State *L)
{
	audio_play_p p = to_sound(L, 1);
	char path[1200];

	if (!p)
		return 0;
	if (lua_gettop(L) >= 3 && lua_isstring(L, 2) && lua_isnumber(L, 3)) {
		size_t n = (size_t)lua_tointeger(L, 3);
		p->load_buf(p, lua_tostring(L, 2), (int)n);
		return 0;
	}
	resolve_audio(luaL_checkstring(L, 2), path, sizeof(path));
	p->load(p, path);
	return 0;
}

static int api_SoundPlay(lua_State *L)
{
	audio_play_p p = to_sound(L, 1);
	int times = (int)luaL_optinteger(L, 2, 1);
	if (p)
		p->play(p, times, 0);
	return 0;
}

static int api_SoundStop(lua_State *L)
{
	audio_play_p p = to_sound(L, 1);
	if (p)
		p->stop(p);
	return 0;
}

static int api_SoundPause(lua_State *L)
{
	audio_play_p p = to_sound(L, 1);
	if (p)
		p->pause(p);
	return 0;
}

static int api_SoundResume(lua_State *L)
{
	audio_play_p p = to_sound(L, 1);
	if (p)
		p->resume(p);
	return 0;
}

static int api_SoundVolume(lua_State *L)
{
	audio_play_p p = to_sound(L, 1);
	if (p)
		p->volume(p, (int)luaL_optinteger(L, 2, 100));
	return 0;
}

static int api_SoundUnload(lua_State *L)
{
	audio_play_p p = to_sound(L, 1);
	if (p) {
		p->destroy(p);
		/* 句柄已失效，Lua 侧会置 false */
	}
	return 0;
}

void pgm_audio_register(lua_State *L)
{
	static const struct { const char *name; lua_CFunction fn; } api[] = {
		{ "mp3load",       api_mp3load },
		{ "mp3play",       api_mp3play },
		{ "mp3stop",       api_mp3stop },
		{ "mp3pause",      api_mp3pause },
		{ "mp3resume",     api_mp3resume },
		{ "mp3replay",     api_mp3replay },
		{ "mp3volume",     api_mp3volume },
		{ "mp3unload",     api_mp3unload },
		{ "mp3isfinish",   api_mp3isfinish },
		{ "mp3playtime",   api_mp3playtime },
		{ "SoundCreate",   api_SoundCreate },
		{ "SoundLoad",     api_SoundLoad },
		{ "SoundPlay",     api_SoundPlay },
		{ "SoundStop",     api_SoundStop },
		{ "SoundPause",    api_SoundPause },
		{ "SoundResume",   api_SoundResume },
		{ "SoundVolume",   api_SoundVolume },
		{ "SoundUnload",   api_SoundUnload },
	};
	int i;
	for (i = 0; i < NELEM(api); i++) {
		lua_pushcfunction(L, api[i].fn);
		lua_setglobal(L, api[i].name);
	}
}

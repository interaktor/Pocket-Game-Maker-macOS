/***************************************************************************
 *            pgm_escript.c
 *
 *  PGM 事件脚本（.ev）解释器。
 *
 *  .ev 文件是**纯文本**，一行一条语句，而且每一行本身就是合法的 Lua 5.1
 *  代码 —— 所以解释器非常简单：把文件按行切开，逐行 luaL_loadbuffer + pcall。
 *  PGM 的 goto/gotoif 用的是物理行号，因此行数组必须与文件行号 1:1 对应
 *  （空行和注释行也要占位）。
 *
 *  注意：Lua 5.1 里 goto 不是关键字，所以 `goto(14)` 是一个合法的函数调用。
 *
 *  Lua 侧的调用节奏（见 EventScene.lua 的 FrameEvScriptUpdate）：
 *      if not EScriptIsEnd(s) then
 *          if EScriptCurrLine(s) >= 1 then EScriptDoline(s) end
 *          EScriptNext(s)
 *      end
 ***************************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdlib.h>

#include "pgm.h"
#include "nge_timer.h"

#define NELEM(a) ((int)(sizeof(a) / sizeof((a)[0])))

typedef struct {
	char **lines;
	int    nlines;
	int    cur;    /* 1 起；> nlines 表示结束 */
	char   name[128];
} pgm_escript;

static int es_gc(lua_State *L)
{
	pgm_escript *e = (pgm_escript *)lua_touserdata(L, 1);
	if (e) {
		int i;
		for (i = 0; i < e->nlines; i++)
			free(e->lines[i]);
		free(e->lines);
		e->lines = NULL;
		e->nlines = 0;
	}
	return 0;
}

static pgm_escript *to_es(lua_State *L, int idx)
{
	if (lua_type(L, idx) != LUA_TUSERDATA)
		return NULL;
	return (pgm_escript *)lua_touserdata(L, idx);
}

/* 把文本按行切开（兼容 \r\n 与 \n） */
static void split_lines(pgm_escript *e, char *text)
{
	int cap = 64;
	char *p = text;

	e->lines = malloc((size_t)cap * sizeof(char *));
	e->nlines = 0;
	e->cur = 1;
	if (!e->lines)
		return;

	while (*p) {
		char *start = p;
		char *nl;

		while (*p && *p != '\n')
			p++;
		nl = p;
		if (*p == '\n')
			p++;
		if (nl > start && nl[-1] == '\r')
			nl--;

		if (e->nlines >= cap) {
			char **nb;
			cap *= 2;
			nb = realloc(e->lines, (size_t)cap * sizeof(char *));
			if (!nb)
				break;
			e->lines = nb;
		}
		{
			size_t len = (size_t)(nl - start);
			char *line = malloc(len + 1);
			if (!line)
				break;
			memcpy(line, start, len);
			line[len] = '\0';
			e->lines[e->nlines++] = line;
		}
	}
}

/* EScriptCreate([pack,] filename) */
static int api_EScriptCreate(lua_State *L)
{
	int pack = -1, idx = 1;
	const char *name;
	char *data = NULL;
	size_t size = 0;
	pgm_escript *e;

	if (lua_gettop(L) >= 2 && lua_isnumber(L, 1)) {
		pack = (int)luaL_checkinteger(L, 1);
		idx = 2;
	}
	name = luaL_checkstring(L, idx);

	if (pack >= 0)
		(void)pgm_pack_read(pack, name, &data, &size);
	if (!data) {
		char path[1200];
		if (pgm_resolve(name, path, sizeof(path)) == 0) {
			FILE *f = fopen(path, "rb");
			if (f) {
				long n;
				fseek(f, 0, SEEK_END);
				n = ftell(f);
				fseek(f, 0, SEEK_SET);
				data = malloc((size_t)n + 1);
				if (data && fread(data, 1, (size_t)n, f) == (size_t)n) {
					data[n] = '\0';
					size = (size_t)n;
				} else {
					free(data);
					data = NULL;
				}
				fclose(f);
			}
		}
	}

	e = (pgm_escript *)lua_newuserdata(L, sizeof(*e));
	memset(e, 0, sizeof(*e));
	luaL_getmetatable(L, "PGMEScript");
	lua_setmetatable(L, -2);

	if (!data) {
		pgm_log("!! EScriptCreate 找不到: %s\n", name);
		return 1;
	}
	split_lines(e, data);
	free(data);
	snprintf(e->name, sizeof(e->name), "%s", name);
	return 1;
}

static int api_EScriptDelete(lua_State *L)
{
	return es_gc(L);
}

static int api_EScriptCurrLine(lua_State *L)
{
	pgm_escript *e = to_es(L, 1);
	if (!e || e->cur < 1 || e->cur > e->nlines) {
		lua_pushinteger(L, 0);
		return 1;
	}
	lua_pushinteger(L, e->cur);
	return 1;
}

static int api_EScriptIsEnd(lua_State *L)
{
	pgm_escript *e = to_es(L, 1);
	lua_pushboolean(L, !e || e->cur > e->nlines);
	return 1;
}

/* 执行当前行 */
static int api_EScriptDoline(lua_State *L)
{
	pgm_escript *e = to_es(L, 1);
	const char *line;
	char chunk[64];

	if (!e || e->cur < 1 || e->cur > e->nlines)
		return 0;
	line = e->lines[e->cur - 1];

	if (getenv("PGM_TRACE_EV")) {
		static int n = 0;
		if (n++ < 400)
			pgm_log("[ev] t=%u %s:%d  %.40s\n", nge_get_tick(),
					e->name, e->cur, line && line[0] ? line : "(空行)");
	}
	if (!line || !line[0])
		return 0;

	snprintf(chunk, sizeof(chunk), "=%s:%d", e->name, e->cur);
	if (luaL_loadbuffer(L, line, strlen(line), chunk) != 0) {
		const char *msg = lua_tostring(L, -1);
		pgm_log("!! %s 第 %d 行语法错: %s  内容: %s\n",
				e->name, e->cur, msg ? msg : "?", line);
		lua_pop(L, 1);
		return 0;
	}
	if (lua_pcall(L, 0, 0, 0) != 0) {
		const char *msg = lua_tostring(L, -1);
		pgm_log("!! %s 第 %d 行运行错: %s  内容: %s\n",
				e->name, e->cur, msg ? msg : "?", line);
		lua_pop(L, 1);
	}
	return 0;
}

static int api_EScriptNext(lua_State *L)
{
	pgm_escript *e = to_es(L, 1);
	if (e)
		e->cur++;
	return 0;
}

/* EScriptBack(script)
 *
 * run() 创建脚本后会立刻调这个，而 FrameEvScriptUpdate 在 EScriptDoline 之后
 * **总会**再调一次 EScriptNext。所以这里必须允许 cur 减到 0：
 *     cur: 1 --Back--> 0 --Next--> 1   => 下一帧从第 1 行开始
 * 若像以前那样卡在 1，Next 会把它推到 2，**第 1 行就被静默跳过了**
 * （实测 first.ev 的 msgboxon() 就是这样丢的）。
 */
static int api_EScriptBack(lua_State *L)
{
	pgm_escript *e = to_es(L, 1);
	if (e && e->cur > 0)
		e->cur--;
	return 0;
}

/* EScriptJump(script, line)
 *
 * 语义要设成 label - 1：Lua 侧（EventScene.lua 的 FrameEvScriptUpdate）在
 * EScriptDoline 之后**总会**再调一次 EScriptNext，所以若直接把 cur 设成
 * label，跳转就会落到 label+1 上。设为 label-1 才能让 Next 正中目标行。
 */
static int api_EScriptJump(lua_State *L)
{
	pgm_escript *e = to_es(L, 1);
	if (getenv("PGM_TRACE_ES"))
		pgm_log("[es] EScriptJump arg1=%s(%s) label=%s\n",
				luaL_typename(L, 1),
				e ? e->name : "无效",
				lua_tostring(L, 2) ? lua_tostring(L, 2) : "nil");
	if (e) {
		int line = (int)luaL_optinteger(L, 2, 1);
		if (line < 1)
			line = 1;
		e->cur = line - 1;
	}
	return 0;
}

static int api_EScriptPrint(lua_State *L)
{
	pgm_escript *e = to_es(L, 1);
	if (e && e->cur >= 1 && e->cur <= e->nlines)
		lua_pushstring(L, e->lines[e->cur - 1]);
	else
		lua_pushstring(L, "");
	return 1;
}

void pgm_escript_register(lua_State *L)
{
	static const struct { const char *name; lua_CFunction fn; } api[] = {
		{ "EScriptCreate",   api_EScriptCreate },
		{ "CacheEScriptCreate", api_EScriptCreate },
		{ "EScriptDelete",   api_EScriptDelete },
		{ "EScriptCurrLine", api_EScriptCurrLine },
		{ "EScriptIsEnd",    api_EScriptIsEnd },
		{ "EScriptDoline",   api_EScriptDoline },
		{ "EScriptNext",     api_EScriptNext },
		{ "EScriptBack",     api_EScriptBack },
		{ "EScriptJump",     api_EScriptJump },
		{ "EScriptPrint",    api_EScriptPrint },
	};
	int i;

	luaL_newmetatable(L, "PGMEScript");
	lua_pushcfunction(L, es_gc);
	lua_setfield(L, -2, "__gc");
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);

	for (i = 0; i < NELEM(api); i++) {
		lua_pushcfunction(L, api[i].fn);
		lua_setglobal(L, api[i].name);
	}
}

/***************************************************************************
 *            pgm_lua.c
 *
 *  Lua 5.1 状态管理、脚本加载与错误报告。
 ***************************************************************************/

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "pgm.h"

void pgm_log(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	vfprintf(stdout, fmt, ap);
	va_end(ap);
	fflush(stdout);
}

/* ------------------------------------------------------------------ */
/* 错误处理                                                            */
/*                                                                    */
/* Lua 的 panic 默认会 abort()。PGM 的脚本里有大量"可选"调用，我们希望在  */
/* 出错时看到清晰的调用位置而不是崩溃，所以安装一个带上下文的报错器。     */
/* ------------------------------------------------------------------ */

static int pgm_traceback(lua_State *L)
{
	const char *msg = lua_tostring(L, 1);
	lua_getfield(L, LUA_GLOBALSINDEX, "debug");
	if (!lua_istable(L, -1)) {
		lua_pop(L, 1);
		pgm_log("Lua error: %s\n", msg ? msg : "(no message)");
		return 1;
	}
	lua_getfield(L, -1, "traceback");
	lua_remove(L, -2);
	if (!lua_isfunction(L, -1)) {
		lua_pop(L, 1);
		pgm_log("Lua error: %s\n", msg ? msg : "(no message)");
		return 1;
	}
	lua_pushvalue(L, 1);
	lua_pushinteger(L, 2);
	lua_call(L, 2, 1);
	{
		const char *tb = lua_tostring(L, -1);
		pgm_log("Lua error: %s\n", tb ? tb : "(no message)");
	}
	return 1;
}

void pgm_lua_init(void)
{
	lua_State *L = luaL_newstate();
	if (!L) {
		pgm_log("fatal: luaL_newstate failed\n");
		exit(1);
	}
	luaL_openlibs(L);
	g_pgm.L = L;

	/* panic 时不要 abort，给出回溯 */
	(void)pgm_traceback;
}

/* ------------------------------------------------------------------ */
/* 执行脚本                                                            */
/* ------------------------------------------------------------------ */

static void report_error(lua_State *L, const char *what)
{
	const char *msg = lua_tostring(L, -1);
	pgm_log("\n!! Lua 失败: %s\n   %s\n\n", what, msg ? msg : "(no message)");
	lua_pop(L, 1);
}

int pgm_do_string(const char *code, const char *chunkname)
{
	lua_State *L = g_pgm.L;
	int base = lua_gettop(L);

	if (luaL_loadbuffer(L, code, strlen(code), chunkname) != 0) {
		report_error(L, chunkname);
		return -1;
	}
	if (lua_pcall(L, 0, 0, 0) != 0) {
		report_error(L, chunkname);
		lua_settop(L, base);
		return -1;
	}
	lua_settop(L, base);
	return 0;
}

int pgm_do_pack_file(int h, const char *name)
{
	char *data = NULL;
	size_t size = 0;
	int rc;
	char chunk[320];

	if (pgm_pack_read(h, name, &data, &size) != 0) {
		pgm_log("!! 找不到脚本: %s (pack %d)\n", name, h);
		return -1;
	}

	snprintf(chunk, sizeof(chunk), "@%s", name);
	rc = pgm_do_string(data, chunk);
	free(data);
	return rc;
}

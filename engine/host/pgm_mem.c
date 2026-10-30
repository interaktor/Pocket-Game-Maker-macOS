/***************************************************************************
 *            pgm_mem.c
 *
 *  PGM 的"内存缓冲区 + 定长字段读写"API。
 *
 *  PGM 的存档系统把结构体手工序列化到一块裸内存里，Lua 侧的写法是：
 *
 *      local buffer,size = PGBufferCreate(1024 * 64)
 *      local offset = 0
 *      MEMNUMCPY(buffer+offset, 65535, MEM_SINT32)
 *      offset = offset + MEMMODESIZE(MEM_SINT32)
 *      MEMSTRCPY(buffer+offset, GAME_NAME, MEM_UINT8_64)
 *
 *  所以 **PGBufferCreate 返回的是数字地址**（不是 userdata），Lua 里才能直接
 *  做 `buffer + offset` 的指针算术。地址用 double 存，arm64 的 48 位指针精度足够。
 *
 *  为了安全，所有分配到一块登记表里，MEM* 在写入前会检查是否越界。
 ***************************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include "pgm.h"

#define NELEM(a) ((int)(sizeof(a) / sizeof((a)[0])))
#define PGM_MAX_BUF 64

typedef struct {
	uintptr_t addr;
	size_t    size;
	int       used;
} pgm_buf;

static pgm_buf g_bufs[PGM_MAX_BUF];

/* 定长字段模式 */
enum {
	M_U8_16 = 0, M_U8_32, M_U8_64, M_U8_128, M_U8_256,
	M_U8_512, M_U8_1024, M_U8_2048, M_U8_4096,
	M_SINT8, M_UINT8, M_SINT16, M_UINT16,
	M_SINT32, M_UINT32, M_FLOAT, M_DOUBLE
};

static size_t mode_size(int mode)
{
	switch (mode) {
	case M_U8_16:   return 16;
	case M_U8_32:   return 32;
	case M_U8_64:   return 64;
	case M_U8_128:  return 128;
	case M_U8_256:  return 256;
	case M_U8_512:  return 512;
	case M_U8_1024: return 1024;
	case M_U8_2048: return 2048;
	case M_U8_4096: return 4096;
	case M_SINT8:
	case M_UINT8:   return 1;
	case M_SINT16:
	case M_UINT16:  return 2;
	case M_SINT32:
	case M_UINT32:
	case M_FLOAT:   return 4;
	case M_DOUBLE:  return 8;
	}
	return 0;
}

static int mode_is_string(int mode)
{
	return mode >= M_U8_16 && mode <= M_U8_4096;
}

/* 校验 [addr, addr+len) 落在某个已登记的缓冲区里 */
static int range_ok(uintptr_t addr, size_t len)
{
	int i;
	for (i = 0; i < PGM_MAX_BUF; i++) {
		if (!g_bufs[i].used)
			continue;
		if (addr >= g_bufs[i].addr &&
			addr + len <= g_bufs[i].addr + g_bufs[i].size)
			return 1;
	}
	return 0;
}

static uintptr_t buf_alloc(size_t size)
{
	int i;
	void *p;

	if (size == 0)
		size = 1;
	for (i = 0; i < PGM_MAX_BUF; i++) {
		if (g_bufs[i].used)
			continue;
		p = calloc(1, size);
		if (!p)
			return 0;
		g_bufs[i].used = 1;
		g_bufs[i].addr = (uintptr_t)p;
		g_bufs[i].size = size;
		return (uintptr_t)p;
	}
	pgm_log("!! 缓冲区表已满（%d），PGBufferCreate 失败\n", PGM_MAX_BUF);
	return 0;
}

static void buf_free(uintptr_t addr)
{
	int i;
	for (i = 0; i < PGM_MAX_BUF; i++) {
		if (g_bufs[i].used && g_bufs[i].addr == addr) {
			free((void *)addr);
			g_bufs[i].used = 0;
			return;
		}
	}
}

/*
 * PGBufferCreate(size)
 * PGBufferCreate(filename)
 * PGBufferCreate(pack, filename)
 *   -> buffer(数字地址), size
 */
static int api_PGBufferCreate(lua_State *L)
{
	int top = lua_gettop(L);
	uintptr_t addr = 0;
	size_t size = 0;

	if (top == 0) {
		lua_pushnil(L);
		return 1;
	}

	if (top >= 2) {
		/* (pack, filename) */
		int pack = (int)luaL_checkinteger(L, 1);
		const char *name = luaL_checkstring(L, 2);
		char *data = NULL;
		size_t n = 0;

		if (pgm_pack_read(pack, name, &data, &n) == 0) {
			addr = buf_alloc(n);
			if (addr) {
				memcpy((void *)addr, data, n);
				size = n;
			}
			free(data);
		}
	} else if (lua_isnumber(L, 1)) {
		/* (size) */
		size = (size_t)luaL_checknumber(L, 1);
		addr = buf_alloc(size);
	} else {
		/* (filename) */
		const char *name = luaL_checkstring(L, 1);
		char path[1200];
		FILE *f = NULL;

		if (pgm_resolve(name, path, sizeof(path)) == 0)
			f = fopen(path, "rb");
		if (!f) {
			/* 存档路径以 / 开头或是绝对路径时直接试 */
			f = fopen(name, "rb");
		}
		if (f) {
			long n;
			fseek(f, 0, SEEK_END);
			n = ftell(f);
			fseek(f, 0, SEEK_SET);
			if (n >= 0) {
				addr = buf_alloc((size_t)n);
				if (addr && fread((void *)addr, 1, (size_t)n, f) == (size_t)n)
					size = (size_t)n;
			}
			fclose(f);
		}
	}

	if (!addr) {
		lua_pushnil(L);
		return 1;
	}
	lua_pushnumber(L, (lua_Number)addr);
	lua_pushnumber(L, (lua_Number)size);
	return 2;
}

static int api_PGBufferDelete(lua_State *L)
{
	if (lua_isnumber(L, 1))
		buf_free((uintptr_t)lua_tonumber(L, 1));
	return 0;
}

/* WriteBuffer(buffer, filename, size) */
static int api_WriteBuffer(lua_State *L)
{
	uintptr_t addr = (uintptr_t)luaL_checknumber(L, 1);
	const char *name = luaL_checkstring(L, 2);
	size_t size = (size_t)luaL_optnumber(L, 3, 0);
	char path[1200];
	FILE *f;

	/* 写目标可能还不存在，pgm_resolve 只找已有文件，所以走可写路径 */
	pgm_write_path(name, path, sizeof(path));

	f = fopen(path, "wb");
	if (!f) {
		pgm_log("!! WriteBuffer 打不开: %s\n", path);
		lua_pushboolean(L, 0);
		return 1;
	}
	if (size == 0)
		size = 1;
	fwrite((void *)addr, 1, size, f);
	fclose(f);
	lua_pushboolean(L, 1);
	return 1;
}

static int api_MEMSET(lua_State *L)
{
	uintptr_t addr = (uintptr_t)luaL_checknumber(L, 1);
	int v = (int)luaL_checkinteger(L, 2);
	size_t n = (size_t)luaL_checknumber(L, 3);
	if (range_ok(addr, n))
		memset((void *)addr, v, n);
	return 0;
}

static int api_MEMCPY(lua_State *L)
{
	uintptr_t dst = (uintptr_t)luaL_checknumber(L, 1);
	uintptr_t src = (uintptr_t)luaL_checknumber(L, 2);
	size_t n = (size_t)luaL_checknumber(L, 3);
	if (range_ok(dst, n) && range_ok(src, n))
		memcpy((void *)dst, (void *)src, n);
	return 0;
}

static int api_MEMMODESIZE(lua_State *L)
{
	lua_pushnumber(L, (lua_Number)mode_size((int)luaL_checkinteger(L, 1)));
	return 1;
}

/* MEMSTRCPY(addr, string, mode) */
static int api_MEMSTRCPY(lua_State *L)
{
	uintptr_t addr = (uintptr_t)luaL_checknumber(L, 1);
	const char *s = luaL_optstring(L, 2, "");
	int mode = (int)luaL_checkinteger(L, 3);
	size_t slot = mode_size(mode);
	size_t len;

	if (!range_ok(addr, slot) || slot == 0)
		return 0;
	len = strlen(s);
	if (len > slot)
		len = slot;
	memset((void *)addr, 0, slot);
	memcpy((void *)addr, s, len);
	return 0;
}

/* MEMGETSTR(addr, mode) */
static int api_MEMGETSTR(lua_State *L)
{
	uintptr_t addr = (uintptr_t)luaL_checknumber(L, 1);
	int mode = (int)luaL_checkinteger(L, 2);
	size_t slot = mode_size(mode);
	char tmp[4096];

	if (!range_ok(addr, slot) || slot == 0 || slot > sizeof(tmp)) {
		lua_pushstring(L, "");
		return 1;
	}
	memcpy(tmp, (void *)addr, slot);
	tmp[slot] = '\0';
	lua_pushstring(L, tmp);
	return 1;
}

/* MEMNUMCPY(addr, value, mode) */
static int api_MEMNUMCPY(lua_State *L)
{
	uintptr_t addr = (uintptr_t)luaL_checknumber(L, 1);
	lua_Number v = luaL_optnumber(L, 2, 0);
	int mode = (int)luaL_checkinteger(L, 3);

	if (!range_ok(addr, mode_size(mode)))
		return 0;

	switch (mode) {
	case M_SINT8:   *(int8_t *)addr = (int8_t)v; break;
	case M_UINT8:   *(uint8_t *)addr = (uint8_t)v; break;
	case M_SINT16:  *(int16_t *)addr = (int16_t)v; break;
	case M_UINT16:  *(uint16_t *)addr = (uint16_t)v; break;
	case M_SINT32:  *(int32_t *)addr = (int32_t)v; break;
	case M_UINT32:  *(uint32_t *)addr = (uint32_t)v; break;
	case M_FLOAT:   *(float *)addr = (float)v; break;
	case M_DOUBLE:  *(double *)addr = (double)v; break;
	default:
		if (mode_is_string(mode)) {
			/* 字符串模式下按 NUL 结尾的整数文本写入 */
			char tmp[32];
			size_t slot = mode_size(mode);
			snprintf(tmp, sizeof(tmp), "%d", (int)v);
			memset((void *)addr, 0, slot);
			memcpy((void *)addr, tmp, strlen(tmp) < slot ? strlen(tmp) : slot);
		}
		break;
	}
	return 0;
}

/* MEMGETNUM(addr, mode) */
static int api_MEMGETNUM(lua_State *L)
{
	uintptr_t addr = (uintptr_t)luaL_checknumber(L, 1);
	int mode = (int)luaL_checkinteger(L, 2);
	lua_Number v = 0;

	if (!range_ok(addr, mode_size(mode))) {
		lua_pushnumber(L, 0);
		return 1;
	}

	switch (mode) {
	case M_SINT8:   v = *(int8_t *)addr; break;
	case M_UINT8:   v = *(uint8_t *)addr; break;
	case M_SINT16:  v = *(int16_t *)addr; break;
	case M_UINT16:  v = *(uint16_t *)addr; break;
	case M_SINT32:  v = *(int32_t *)addr; break;
	case M_UINT32:  v = *(uint32_t *)addr; break;
	case M_FLOAT:   v = *(float *)addr; break;
	case M_DOUBLE:  v = *(double *)addr; break;
	default:
		if (mode_is_string(mode))
			v = atof((const char *)addr);
		break;
	}
	lua_pushnumber(L, v);
	return 1;
}

/* GetFullGameDataFolderPath([num]) / GetFullPubGameDataFolderPath([num]) */
static int api_GetFullGameDataFolderPath(lua_State *L)
{
	char path[1200];
	(void)L;
	snprintf(path, sizeof(path), "%s/PGMSAVEDATA", g_pgm.root);
	lua_pushstring(L, path);
	return 1;
}

void pgm_mem_register(lua_State *L)
{
	static const struct { const char *name; lua_CFunction fn; } api[] = {
		{ "PGBufferCreate", api_PGBufferCreate },
		{ "PGBufferDelete", api_PGBufferDelete },
		{ "WriteBuffer",    api_WriteBuffer },
		{ "MEMSET",         api_MEMSET },
		{ "MEMCPY",         api_MEMCPY },
		{ "MEMMODESIZE",    api_MEMMODESIZE },
		{ "MEMSTRCPY",      api_MEMSTRCPY },
		{ "MEMGETSTR",      api_MEMGETSTR },
		{ "MEMNUMCPY",      api_MEMNUMCPY },
		{ "MEMGETNUM",      api_MEMGETNUM },
	};
	static const char *const modes[] = {
		"MEM_UINT8_16", "MEM_UINT8_32", "MEM_UINT8_64", "MEM_UINT8_128",
		"MEM_UINT8_256", "MEM_UINT8_512", "MEM_UINT8_1024",
		"MEM_UINT8_2048", "MEM_UINT8_4096",
		"MEM_SINT8", "MEM_UINT8", "MEM_SINT16", "MEM_UINT16",
		"MEM_SINT32", "MEM_UINT32", "MEM_FLOAT", "MEM_DOUBLE",
	};
	int i;

	for (i = 0; i < NELEM(api); i++) {
		lua_pushcfunction(L, api[i].fn);
		lua_setglobal(L, api[i].name);
	}
	for (i = 0; i < NELEM(modes); i++) {
		lua_pushinteger(L, i);
		lua_setglobal(L, modes[i]);
	}

	/* 存档目录路径：覆盖 api.c 里的简单实现 */
	lua_pushcfunction(L, api_GetFullGameDataFolderPath);
	lua_setglobal(L, "GetFullGameDataFolderPath");
	lua_pushcfunction(L, api_GetFullGameDataFolderPath);
	lua_setglobal(L, "GetFullPubGameDataFolderPath");
}

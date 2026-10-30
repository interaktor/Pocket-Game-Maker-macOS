/***************************************************************************
 *            pgm_dialog.c
 *
 *  DialogCreate(text) —— 把对话文本解析成"绘制单元"数组。
 *
 *  SpeakScene.lua 逐帧消费这个数组，按 unit.type 决定怎么画：
 *
 *    PGD_UINT8    单字节字符（ASCII），绘制后宽度 +DIALOG_FONT_WIDTH
 *    PGD_SINT8    双字节字符（GBK 汉字），按实际字形宽度前进
 *    PGD_NEWLINE  换行，value = 换几行
 *    PGD_TABLE    连续空格，value = 个数
 *    PGD_COLOR    [c=RRGGBB] 开始着色，value = 颜色
 *    PGD_DCOLOR   [/c] 结束着色
 *
 *  返回 table：{ [1..count] = {type=, value=}, count = n }
 ***************************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "pgm.h"
#include "nge_color.h"
#include "nge_font.h"

#define NELEM(a) ((int)(sizeof(a) / sizeof((a)[0])))

/* 与 PGM 指令表里的 PGD_* 一致 */
enum {
	PGD_UNKNOWN = 0, PGD_SINT8, PGD_UINT8, PGD_CODE, PGD_NEWLINE,
	PGD_TABLE, PGD_COLOR, PGD_DCOLOR, PGD_DELAY, PGD_WAITKEY
};

typedef struct {
	lua_State *L;
	int        tbl;    /* 结果表在栈上的绝对索引 */
	int        n;
} dlg;

static void add_unit(dlg *d, int type, const char *sval, double nval,
					 int has_num)
{
	lua_pushvalue(d->L, d->tbl);          /* 表 */
	lua_newtable(d->L);                   /* unit */

	lua_pushinteger(d->L, type);
	lua_setfield(d->L, -2, "type");

	if (has_num) {
		lua_pushnumber(d->L, nval);
		lua_setfield(d->L, -2, "value");
	} else {
		lua_pushstring(d->L, sval ? sval : "");
		lua_setfield(d->L, -2, "value");
	}

	lua_rawseti(d->L, -2, ++d->n);
	lua_pop(d->L, 1);
}

static int hex2(const char *s)
{
	int v = 0, i;
	for (i = 0; i < 2; i++) {
		char c = s[i];
		v <<= 4;
		if (c >= '0' && c <= '9') v |= c - '0';
		else if (c >= 'a' && c <= 'f') v |= c - 'a' + 10;
		else if (c >= 'A' && c <= 'F') v |= c - 'A' + 10;
	}
	return v;
}

/* [c=RRGGBB] -> 颜色；返回消耗的字节数，0 表示不是颜色标签 */
static int parse_color_tag(const unsigned char *p, uint32_t *out)
{
	if (p[0] != '[' || (p[1] != 'c' && p[1] != 'C') || p[2] != '=')
		return 0;
	if (strlen((const char *)p) < 10)
		return 0;
	{
		int r = hex2((const char *)p + 3);
		int g = hex2((const char *)p + 5);
		int b = hex2((const char *)p + 7);
		*out = MAKE_RGBA_4444(r, g, b, 255);
		return 10;   /* "[c=RRGGBB]" */
	}
}

static int is_dcolor_tag(const unsigned char *p)
{
	return p[0] == '[' && p[1] == '/' && (p[2] == 'c' || p[2] == 'C') &&
		p[3] == ']';
}

/* FontTextSize(font, text) —— 单字宽度 */
static int api_FontTextSize(lua_State *L)
{
	PFont pf = NULL;
	const char *s = luaL_optstring(L, 2, "");
	int w = 0, h = 0, b = 0;

	if (lua_type(L, 1) == LUA_TUSERDATA) {
		void **u = (void **)lua_touserdata(L, 1);
		if (u)
			pf = (PFont)*u;
	}
	if (pf && s && *s)
		font_textsize(pf, s, (int)strlen(s), &w, &h, &b);
	lua_pushinteger(L, w);
	return 1;
}

static int api_DialogCreate(lua_State *L)
{
	const char *text = luaL_optstring(L, 1, "");
	const unsigned char *p = (const unsigned char *)text;
	dlg d;

	d.L = L;
	d.n = 0;
	lua_newtable(L);
	d.tbl = lua_gettop(L);

	while (*p) {
		uint32_t color;
		int used;

		/* 着色标签 */
		used = parse_color_tag(p, &color);
		if (used) {
			add_unit(&d, PGD_COLOR, NULL, (double)color, 1);
			p += used;
			continue;
		}
		if (is_dcolor_tag(p)) {
			add_unit(&d, PGD_DCOLOR, NULL, 0, 1);
			p += 4;
			continue;
		}

		/* 换行 */
		if (*p == '\n') {
			add_unit(&d, PGD_NEWLINE, NULL, 1, 1);
			p++;
			continue;
		}
		if (*p == '\r') {
			p++;
			continue;
		}

		/* 连续半角空格 -> 一个 TABLE 单元 */
		if (*p == ' ') {
			int n = 0;
			while (*p == ' ') { n++; p++; }
			add_unit(&d, PGD_TABLE, NULL, (double)n, 1);
			continue;
		}

		/* GBK 双字节 */
		if (*p >= 0x81) {
			char buf[3];
			buf[0] = (char)p[0];
			buf[1] = p[1] ? (char)p[1] : '\0';
			buf[2] = '\0';
			add_unit(&d, PGD_SINT8, buf, 0, 0);
			p += (p[1] ? 2 : 1);
			continue;
		}

		/* 其余按单字节字符 */
		{
			char buf[2];
			buf[0] = (char)*p;
			buf[1] = '\0';
			add_unit(&d, PGD_UINT8, buf, 0, 0);
			p++;
		}
	}

	lua_pushinteger(L, d.n);
	lua_setfield(L, -2, "count");
	return 1;
}

void pgm_dialog_register(lua_State *L)
{
	static const struct { const char *name; lua_CFunction fn; } api[] = {
		{ "DialogCreate", api_DialogCreate },
		{ "FontTextSize", api_FontTextSize },
	};
	static const struct { const char *name; int v; } consts[] = {
		{ "PGD_UNKNOWN", PGD_UNKNOWN }, { "PGD_SINT8", PGD_SINT8 },
		{ "PGD_UINT8", PGD_UINT8 },     { "PGD_CODE", PGD_CODE },
		{ "PGD_NEWLINE", PGD_NEWLINE }, { "PGD_TABLE", PGD_TABLE },
		{ "PGD_COLOR", PGD_COLOR },     { "PGD_DCOLOR", PGD_DCOLOR },
		{ "PGD_DELAY", PGD_DELAY },     { "PGD_WAITKEY", PGD_WAITKEY },
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

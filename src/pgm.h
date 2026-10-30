/***************************************************************************
 *            pgm.h
 *
 *  PGM-Mac —— PGM 引擎宿主层
 *
 *  PGM 的原始宿主（LuaLibs.cpp / MyGame.cpp / PGMap.cpp / amp_package.cpp）
 *  从未公开源码。这里是依据 PGM 自带的 Lua 框架和公开的
 *  《PGM指令表v0.7.txt》重新实现的独立版本。
 ***************************************************************************/

#ifndef _PGM_H
#define _PGM_H

#include <stdint.h>
#include <stddef.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

/* 引擎状态：与 PGM 指令表里的 PGM_* 宏对应 */
enum {
	PGM_ST_QUIT   = 0,
	PGM_ST_SCRIPT = 1,
	PGM_ST_INIT   = 2,
	PGM_ST_LOOP   = 3,
	PGM_ST_FINI   = 4
};

/* 封包句柄的种类 */
enum {
	PGM_PACK_NONE = 0,
	PGM_PACK_DIR,   /* 明文的 src/ 目录（开发期 / 未打包的游戏） */
	PGM_PACK_BIN,   /* gmcode.bin —— 脚本包：按行存储 + 加密 */
	PGM_PACK_RES    /* gmdata.bin —— 资源包：整文件原样存储，不加密 */
};

typedef struct pgm_dir_entry {
	char     name[128];
	uint32_t off;
	uint32_t size;
	int      valid;
} pgm_dir_entry;

typedef struct pgm_pack {
	int  kind;
	char path[1024];
	/* PGM_PACK_BIN：整个封包常驻内存 + 目录 */
	unsigned char  *data;
	size_t          data_size;
	pgm_dir_entry  *ents;
	int             nents;
	int             stride;   /* 目录项步长：脚本包 128 / 资源包 124 */
} pgm_pack;

#define PGM_MAX_PACK 8

typedef struct pgm_game {
	char root[1024];  /* 游戏根目录，含 bin/ 与 src/ */
	char bin[1024];   /* <root>/bin  —— 运行时目录，pgm.ini / data/ 在此 */
	char src[1024];   /* <root>/src  —— 未打包脚本目录 */

	pgm_pack packs[PGM_MAX_PACK];

	int  state;
	int  quit;
	char script[256];  /* PGSetScript 指定的入口脚本（engine.sys） */

	int  trace;        /* 非 0 时打印每次原生 API 调用 */

	lua_State *L;

	/* 窗口参数，由 pgm.ini 设定 */
	int  screen_w, screen_h, screen_bpp, screen_full;
	char screen_name[128];
} pgm_game;

extern pgm_game g_pgm;

/* ---- 路径工具 ---- */
/* 在 root/bin 与 root/src 下依次查找 relpath，成功时写入 out */
int pgm_resolve(const char *relpath, char *out, size_t outsz);
/* 递归建目录（等价 mkdir -p） */
int pgm_mkdir_p(const char *path);
/* 把相对名解析成"游戏根目录下的可写路径"，并顺手建好父目录 */
int pgm_write_path(const char *name, char *out, size_t outsz);

/* ---- 封包 ---- */
int  pgm_pack_open(const char *path);          /* 返回句柄索引，失败 <0 */
int  pgm_pack_read(int h, const char *name, char **data, size_t *size);
void pgm_pack_close_all(void);

/* ---- 音频 ---- */
void pgm_audio_register(lua_State *L);

/* ---- 输入回调桥接 ---- */
int pgm_api_control_init(lua_State *L);
int pgm_api_touch_init(lua_State *L);

/* ---- 效果器 ---- */
void pgm_effect_register(lua_State *L);

/* ---- 对话文本解析 ---- */
void pgm_dialog_register(lua_State *L);

/* ---- 内存缓冲区 / 定长字段 ---- */
void pgm_mem_register(lua_State *L);

/* ---- 事件脚本解释器 ---- */
void pgm_escript_register(lua_State *L);

/* ---- 图形 / 字体 / 计时器 ---- */
void pgm_gfx_register(lua_State *L);
int  pgm_gfx_start(void);              /* 用 Lua 的 PGM_SCREEN_* 初始化视频 */
void pgm_gfx_capture(const char *png); /* 抓一帧存 PNG（验证用） */

/* ---- Lua 侧 ---- */
void pgm_lua_init(void);
void pgm_register_api(lua_State *L);
/* 从封包读取并执行一个脚本；失败时打印 Lua 错误 */
int  pgm_do_pack_file(int h, const char *name);
int  pgm_do_string(const char *code, const char *chunkname);

/* ---- 日志 ---- */
void pgm_log(const char *fmt, ...);

#endif /* _PGM_H */

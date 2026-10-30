/***************************************************************************
 *            pgm_main.c
 *
 *  PGM-Mac 宿主入口。
 *
 *  启动顺序与 PGM 原始宿主一致：
 *    1. 定位游戏根目录（含 bin/ 与 src/）
 *    2. 起 Lua 状态、注册原生 API
 *    3. 执行 bin/pgm.ini —— 它是纯 Lua 赋值，末尾调用
 *         PGSetScript("engine.sys")
 *         PGSetState(PGM_SCRIPT)
 *       于是 4 由 pgm.ini 自己触发
 *    4. PGSetState(PGM_SCRIPT) 加载 engine.sys：
 *         PackCreate(data/gmcode.bin) / PackCreate(data/gmdata.bin)
 *         include("lg_init.lua") -> 逐层 include 出整个框架
 *
 *  P2 的验收标准就是走到 4 不崩、并看到 lg_init.lua 及其子脚本被逐个加载。
 ***************************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "pgm.h"
#include "nge.h"
#include "nge_graphics.h"
#include "nge_input.h"

static int is_dir(const char *p)
{
	struct stat st;
	return stat(p, &st) == 0 && S_ISDIR(st.st_mode);
}

static int is_file(const char *p)
{
	struct stat st;
	return stat(p, &st) == 0 && S_ISREG(st.st_mode);
}

/* 从一个候选路径向上找，直到包含 bin/ 或 src/ 的目录 */
static int find_game_root(const char *start, char *out, size_t outsz)
{
	char cur[1024];
	snprintf(cur, sizeof(cur), "%s", start);

	for (;;) {
		char probe[1200];
		snprintf(probe, sizeof(probe), "%s/bin", cur);
		if (is_dir(probe)) {
			snprintf(out, outsz, "%s", cur);
			return 0;
		}
		/* 也接受本身就是 bin/ 的情况 */
		snprintf(probe, sizeof(probe), "%s/pgm.ini", cur);
		if (is_file(probe)) {
			snprintf(out, outsz, "%s", cur);
			return 0;
		}
		{
			char *slash = strrchr(cur, '/');
			if (!slash || slash == cur)
				return -1;
			*slash = '\0';
		}
	}
}

static char *read_file(const char *path, long *out_len)
{
	FILE *f = fopen(path, "rb");
	long n;
	char *buf;

	if (!f)
		return NULL;
	fseek(f, 0, SEEK_END);
	n = ftell(f);
	fseek(f, 0, SEEK_SET);
	if (n < 0) {
		fclose(f);
		return NULL;
	}
	buf = malloc((size_t)n + 1);
	if (!buf) {
		fclose(f);
		return NULL;
	}
	if (fread(buf, 1, (size_t)n, f) != (size_t)n) {
		free(buf);
		fclose(f);
		return NULL;
	}
	buf[n] = '\0';
	fclose(f);
	if (out_len)
		*out_len = n;
	return buf;
}

int main(int argc, char *argv[])
{
	const char *arg;
	char ini[1200];
	char *code = NULL;

	setvbuf(stdout, NULL, _IONBF, 0);

	arg = (argc > 1) ? argv[1] : ".";

	if (find_game_root(arg, g_pgm.root, sizeof(g_pgm.root)) != 0) {
		fprintf(stderr,
				"找不到游戏目录：%s\n"
				"用法: %s <游戏目录>\n"
				"      目录里应包含 bin/pgm.ini 和 src/\n",
				arg, argv[0]);
		return 2;
	}

	/* 归一化成绝对路径：后面会 chdir 到 bin/，相对路径会失效 */
	{
		char abs[1024];
		if (realpath(g_pgm.root, abs) != NULL)
			snprintf(g_pgm.root, sizeof(g_pgm.root), "%s", abs);
	}

	snprintf(g_pgm.bin, sizeof(g_pgm.bin), "%s/bin", g_pgm.root);
	snprintf(g_pgm.src, sizeof(g_pgm.src), "%s/src", g_pgm.root);

	pgm_log("=== PGM-Mac 宿主 ===\n");
	pgm_log("游戏根目录 : %s\n", g_pgm.root);
	pgm_log("bin        : %s%s\n", g_pgm.bin,
			is_dir(g_pgm.bin) ? "" : "  (不存在)");
	pgm_log("src        : %s%s\n", g_pgm.src,
			is_dir(g_pgm.src) ? "" : "  (不存在)");
	pgm_log("Lua        : %s\n", LUA_RELEASE);
	pgm_log("\n");

	/* ---- 找 pgm.ini ---- */
	snprintf(ini, sizeof(ini), "%s/pgm.ini", g_pgm.bin);
	if (!is_file(ini)) {
		snprintf(ini, sizeof(ini), "%s/pgm.ini", g_pgm.root);
		if (!is_file(ini)) {
			fprintf(stderr, "找不到 pgm.ini\n");
			return 3;
		}
	}

	/* ---- 起 Lua ---- */
	pgm_lua_init();
	pgm_register_api(g_pgm.L);

	/* ---- 执行 pgm.ini，它会触发 PGSetScript + PGSetState ---- */
	{
		long len = 0;
		char cwd[1024];

		code = read_file(ini, &len);
		if (!code) {
			fprintf(stderr, "读不了 %s\n", ini);
			return 4;
		}

		/* PGM 的资源路径是相对 bin/ 的，切换过去 */
		if (!getcwd(cwd, sizeof(cwd)))
			cwd[0] = '\0';
		if (is_dir(g_pgm.bin))
			(void)chdir(g_pgm.bin);

		pgm_log(">>> 执行 %s\n\n", ini);
		if (pgm_do_string(code, "pgm.ini") != 0) {
			free(code);
			return 5;
		}
		free(code);

		if (cwd[0])
			(void)chdir(cwd);
	}

	/*
	 * 兼容性补丁：FGBase:load 里用 event[255] 选择 ImageClone 的方式
	 *
	 *     if event[255] == 0 then self.image_p[i+1] = ImageClone(image)
	 *     elseif event[255] == 1 then self.image_p[i+1] = ImageClone(image,1) end
	 *
	 * 但 event[255] 在整个 Lua 框架里从未被赋值过（globals.lua 只有
	 * event = {}），所以两个分支都不匹配，image_p 永远保持 false，
	 * 于是所有精灵（消息框/背景/立绘）都不会被绘制。
	 * 原版宿主应该是在原生层给 event 提供了默认值，这里补上。
	 */
	{
		lua_State *L2 = g_pgm.L;
		lua_getglobal(L2, "event");
		if (lua_istable(L2, -1)) {
			lua_pushinteger(L2, 255);
			lua_rawget(L2, -2);
			if (lua_isnil(L2, -1)) {
				lua_pop(L2, 1);
				lua_pushinteger(L2, 255);
				lua_pushinteger(L2, 0);
				lua_rawset(L2, -3);
				pgm_log("compat: event[255] 默认置 0（原版由原生层提供）\n");
			} else {
				lua_pop(L2, 1);
			}
		}
		lua_pop(L2, 1);
	}

	/* ---- 进入主循环：engine.sys 末尾会 PGSetState(PGM_LOOP) ---- */
	if (g_pgm.state == PGM_ST_LOOP && !g_pgm.quit) {
		const char *s_frames = getenv("PGM_MAC_FRAMES");
		const char *s_shot = getenv("PGM_MAC_SHOT");
		int max_frames = s_frames ? atoi(s_frames) : 0;
		int i, autokey = 0;
		lua_State *L = g_pgm.L;

		pgm_gfx_start();

		pgm_log("进入主循环 (PGLoop)，帧数上限=%d\n",
				max_frames > 0 ? max_frames : 0);

		/* 自动按键：每 autokey 帧模拟一次 CIRCLE 键
		   （对话要按键才推进，自动化验证需要这个）*/
		{
			const char *ak = getenv("PGM_MAC_AUTOKEY");
			autokey = ak ? atoi(ak) : 0;
		}

		for (i = 0; !g_pgm.quit && (max_frames <= 0 || i < max_frames); i++) {
			InputProc();

			if (autokey > 0 && (i % autokey) == 0) {
				/* 取引擎自己注册的按下/抬起回调（engine.sys 里的 press_down/up）*/
				static const char *cbs[2] = { "press_down", "press_up" };
				int k;
				for (k = 0; k < 2; k++) {
					lua_getglobal(L, cbs[k]);
					if (lua_isfunction(L, -1)) {
						/* 对话推进用 CIRCLE（见 SpeakScene:KeyDown），
						   CROSS 是 drawhide() 隐藏对话框 */
						lua_pushinteger(L, PSP_BUTTON_CIRCLE);
						if (lua_pcall(L, 1, 0, 0) != 0)
							lua_pop(L, 1);
					} else {
						lua_pop(L, 1);
					}
				}
			}

			lua_getglobal(L, "PGLoop");
			if (!lua_isfunction(L, -1)) {
				pgm_log("!! PGLoop 未定义\n");
				lua_pop(L, 1);
				break;
			}
			if (lua_pcall(L, 0, 0, 0) != 0) {
				const char *msg = lua_tostring(L, -1);
				pgm_log("\n!! PGLoop 第 %d 帧出错: %s\n", i,
						msg ? msg : "(no message)");
				lua_pop(L, 1);
				break;
			}
			LimitFps(60);
		}

		pgm_log("主循环结束，共 %d 帧\n", i);
		pgm_gfx_capture(s_shot);
	}

	pgm_log("\n=== 结束 (state=%d, quit=%d) ===\n", g_pgm.state, g_pgm.quit);
	return 0;
}

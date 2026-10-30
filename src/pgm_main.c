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

	pgm_log("\n=== P2 阶段结束 (state=%d, quit=%d) ===\n",
			g_pgm.state, g_pgm.quit);
	return 0;
}

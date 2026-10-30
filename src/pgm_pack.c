/***************************************************************************
 *            pgm_pack.c
 *
 *  封包抽象层。
 *
 *  PGM 有两种资源来源：
 *    1. 打包后的 gmcode.bin（脚本）与 gmdata.bin（图片）—— 玩家拿到的游戏
 *       只有这个。
 *    2. 未打包的 src/ 目录 —— 作者开发时用，脚本是明文 .lua/.ev。
 *
 *  当前实现只完成了 (2)。(1) 的容器结构已经解出来了（见
 *  docs/PACK-FORMAT.md）：128 字节目录项 {u32, u32, offset, size,
 *  char name[112]}，偏移链首尾闭合；但每个条目的载荷编码还没破解，
 *  所以 PGM_PACK_BIN 暂时返回 -1 并给出明确提示。
 ***************************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "pgm.h"

pgm_game g_pgm;

static int pack_count = 0;

/* ------------------------------------------------------------------ */
/* 路径解析：先 bin/，后 src/                                          */
/* ------------------------------------------------------------------ */

int pgm_resolve(const char *relpath, char *out, size_t outsz)
{
	static const char *subdirs[] = { "", "bin/", "src/", "bin/data/", NULL };
	int i;

	for (i = 0; subdirs[i]; i++) {
		struct stat st;
		snprintf(out, outsz, "%s/%s%s", g_pgm.root, subdirs[i], relpath);
		if (stat(out, &st) == 0 && S_ISREG(st.st_mode))
			return 0;
	}
	/* 也试试直接相对 bin/ 的 data/ 前缀 */
	snprintf(out, outsz, "%s/bin/%s", g_pgm.root, relpath);
	if (stat(out, &(struct stat){0}) == 0)
		return 0;

	out[0] = '\0';
	return -1;
}

/* ------------------------------------------------------------------ */
/* 文本型 pack 名 -> 目录型句柄                                        */
/*                                                                    */
/*  engine.sys 里是 PackCreate(PGM_RES_FOLDER .. PGM_PACK_CODE)，也就是  */
/*  "data/gmcode.bin"。在只支持目录模式的阶段，把它映射到 src/ 目录。    */
/* ------------------------------------------------------------------ */

static int looks_binary_pack(const char *path)
{
	FILE *f;
	unsigned char sig[8];
	size_t n;

	f = fopen(path, "rb");
	if (!f)
		return 0;
	n = fread(sig, 1, sizeof(sig), f);
	fclose(f);
	if (n < 8)
		return 0;

	/* gmdata.bin 的第一个条目就是原始 PNG */
	if (memcmp(sig, "\x89PNG\r\n\x1a\n", 8) == 0)
		return 1;

	/* gmcode.bin 开头是 [u32 nameLen][...]，nameLen 合理且后面接 u32 */
	{
		unsigned int len = sig[0] | (sig[1] << 8) | (sig[2] << 16) |
			((unsigned)sig[3] << 24);
		if (len > 0 && len < 256)
			return 1;
	}
	return 0;
}

int pgm_pack_open(const char *path)
{
	char resolved[1024];
	int h;

	if (pack_count >= PGM_MAX_PACK)
		return -1;

	h = pack_count++;

	if (pgm_resolve(path, resolved, sizeof(resolved)) == 0 &&
		looks_binary_pack(resolved)) {
		pgm_log("pack: %s 是二进制封包，但封包载荷解码尚未实现 "
				"(见 docs/PACK-FORMAT.md)，改用 src/ 目录\n", resolved);
		snprintf(g_pgm.packs[h].path, sizeof(g_pgm.packs[h].path),
				 "%s/src", g_pgm.root);
		g_pgm.packs[h].kind = PGM_PACK_DIR;
		return h;
	}

	snprintf(g_pgm.packs[h].path, sizeof(g_pgm.packs[h].path), "%s/src",
			 g_pgm.root);
	g_pgm.packs[h].kind = PGM_PACK_DIR;
	pgm_log("pack: \"%s\" -> 目录模式 %s\n", path, g_pgm.packs[h].path);
	return h;
}

int pgm_pack_read(int h, const char *name, char **data, size_t *size)
{
	char path[1300];
	FILE *f;
	long n;
	char *buf;

	*data = NULL;
	*size = 0;

	if (h < 0 || h >= pack_count)
		return -1;

	if (g_pgm.packs[h].kind == PGM_PACK_DIR) {
		/* 先按原样找，再按 src/system/ 找（PGM 的 include 只用文件名） */
		static const char *sub[] = { "", "system/", "user/", "files/", NULL };
		int i;
		for (i = 0; sub[i]; i++) {
			snprintf(path, sizeof(path), "%s/%s%s",
					 g_pgm.packs[h].path, sub[i], name);
			f = fopen(path, "rb");
			if (f)
				goto found;
		}
		return -1;
	}

	return -1;

found:
	fseek(f, 0, SEEK_END);
	n = ftell(f);
	fseek(f, 0, SEEK_SET);
	if (n < 0) {
		fclose(f);
		return -1;
	}
	buf = malloc((size_t)n + 1);
	if (!buf) {
		fclose(f);
		return -1;
	}
	if (fread(buf, 1, (size_t)n, f) != (size_t)n) {
		free(buf);
		fclose(f);
		return -1;
	}
	buf[n] = '\0';
	fclose(f);
	*data = buf;
	*size = (size_t)n;
	return 0;
}

void pgm_pack_close_all(void)
{
	pack_count = 0;
}

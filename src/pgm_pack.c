/***************************************************************************
 *            pgm_pack.c
 *
 *  封包读取层。支持两种来源：
 *
 *    1. PGM_PACK_BIN —— gmcode.bin / gmdata.bin 二进制封包（玩家拿到的形态）
 *    2. PGM_PACK_DIR —— 明文的 src/ 目录（作者开发期使用）
 *
 *  封包格式的完整逆向记录见 docs/PACK-FORMAT.md。摘要：
 *
 *    容器   [数据区][128B × N 目录项][trailer]
 *    目录项 {u32 保留, u32 ?, u32 数据偏移, u32 数据长度, char 文件名[112]}
 *    载荷   一串 [u32 行长][行长个字节]，每行一条记录
 *    加密   plain[i] = cipher[i] ^ KEY[i % 64]     （索引 = 记录内偏移）
 *           另外打包器为避免密文出现 0x00，会把 plain==KEY[i] 的位置原样写出，
 *           解出的 0 需要填回 KEY[i]。
 *    坑     目录字段整体错位一格：第 i 个名字的 offset/size 写在 i+1 条的头部
 ***************************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "pgm.h"

pgm_game g_pgm;

static int pack_count = 0;

/* ------------------------------------------------------------------ */
/* 密钥流：64 字节固定表（见 docs/PACK-FORMAT.md 4.2）                  */
/* ------------------------------------------------------------------ */
static const unsigned char PGM_KEY[64] = {
	0x32, 0x5a, 0x5c, 0x59, 0x50, 0x40, 0x30, 0x33,
	0x7d, 0x30, 0x7b, 0x78, 0x7e, 0x64, 0x30, 0x33,
	0x7d, 0x50, 0x57, 0x45, 0x5a, 0x57, 0x45, 0x5a,
	0x57, 0x41, 0x57, 0x54, 0x7e, 0x64, 0x59, 0x50,
	0x5c, 0x4d, 0x50, 0x40, 0x50, 0x53, 0x49, 0x30,
	0x7b, 0x78, 0x7e, 0x7b, 0x30, 0x33, 0x59, 0x5e,
	0x65, 0x7b, 0x5a, 0x57, 0x46, 0x51, 0x49, 0x7b,
	0x69, 0x48, 0x46, 0x51, 0x6f, 0x64, 0x54, 0x32
};

#define DIR_STRIDE 128
#define DIR_NAME_OFF 16

static uint32_t rd32(const unsigned char *p)
{
	return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
		((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

/* ------------------------------------------------------------------ */
/* 路径解析：先 bin/，后 src/                                          */
/* ------------------------------------------------------------------ */

int pgm_resolve(const char *relpath, char *out, size_t outsz)
{
	static const char *subdirs[] = { "", "bin/", "src/", "src/system/",
									 "src/user/", "bin/data/", NULL };
	int i;
	struct stat st;

	for (i = 0; subdirs[i]; i++) {
		snprintf(out, outsz, "%s/%s%s", g_pgm.root, subdirs[i], relpath);
		if (stat(out, &st) == 0 && S_ISREG(st.st_mode))
			return 0;
	}
	out[0] = '\0';
	return -1;
}

/* ------------------------------------------------------------------ */
/* 二进制封包：目录解析                                                */
/* ------------------------------------------------------------------ */

/* 校验从 start 起 nums 条记录是否像合法目录；成功填 ents，返回 1 */
static int read_entries(const unsigned char *d, size_t n, size_t start,
						int nums, int stride, int field_off, int name_off,
						pgm_dir_entry **out)
{
	pgm_dir_entry *e;
	int i;

	if (start + (size_t)nums * stride > n)
		return 0;
	e = calloc((size_t)nums, sizeof(*e));
	if (!e)
		return 0;

	for (i = 0; i < nums; i++) {
		size_t p = start + (size_t)i * stride;
		uint32_t off = rd32(d + p + field_off);
		uint32_t size = rd32(d + p + field_off + 4);
		size_t k;
		int len = 0;

		for (k = 0; k < (size_t)(stride - name_off); k++) {
			unsigned char c = d[p + name_off + k];
			if (c == 0)
				break;
			if (c < 0x20 || len >= (int)sizeof(e[i].name) - 1) {
				free(e);
				return 0;
			}
			e[i].name[len++] = (char)c;
		}
		if (len == 0) {
			free(e);
			return 0;
		}
		e[i].name[len] = '\0';
		e[i].off = off;
		e[i].size = size;
		e[i].valid = (size > 0 && (size_t)off + size <= start);
	}

	*out = e;
	{
		int ok = 0;
		for (i = 0; i < nums; i++)
			ok += e[i].valid;
		return ok;
	}
}

/* 解析容器，成功返回目录起点与条目 */
static int parse_bin_dir(const unsigned char *d, size_t n,
						 pgm_dir_entry **ents, int *nents, size_t *dir_start,
						 int *stride_out)
{
	/* trailer 长度与 nums 字段位置因版本而异，逐个候选尝试 */
	static const int tlens[] = { 100, 96, 104, 92, 88, 84, 108, 112, 80, 76 };
	static const int noffs[] = { 20, 16, 12, 8, 24, 4 };
	int ti, ni;
	pgm_dir_entry *best_e = NULL;
	int best_ok = 0, best_n = 0, best_stride = 0;
	size_t best_start = 0;

	for (ti = 0; ti < (int)(sizeof(tlens) / sizeof(tlens[0])); ti++) {
		size_t t;
		if ((size_t)tlens[ti] >= n)
			continue;
		t = n - tlens[ti];
		for (ni = 0; ni < (int)(sizeof(noffs) / sizeof(noffs[0])); ni++) {
			uint32_t nums;
			size_t start;
			pgm_dir_entry *e = NULL;

			if (t + noffs[ni] + 4 > n)
				continue;
			nums = rd32(d + t + noffs[ni]);
			if (nums <= 1 || nums > 4096)
				continue;
			/* trailer 里的条目数偶尔比实际多 1（gmdata.bin 就是 63 vs 62），
			   所以对 nums 与 nums-1 都试一次 */
			{
				/* 两种目录布局：脚本包步长 128（名字在 +16），
				   资源包步长 124（名字在 +8）。 */
				/* 脚本包：字段 @+8，名字 @+16；资源包：字段 @+0，名字 @+8 */
				static const struct { int stride, field_off, name_off; } lay[] =
					{ { 128, 8, 16 }, { 124, 0, 8 } };
				int cand, li;
				for (cand = 0; cand < 2; cand++) {
					uint32_t nn = nums - (uint32_t)cand;
					if (nn <= 1)
						continue;
					for (li = 0; li < 2; li++) {
						if (t < (size_t)nn * lay[li].stride)
							continue;
						start = t - (size_t)nn * lay[li].stride;
						int ok = read_entries(d, n, start, (int)nn,
											  lay[li].stride,
											  lay[li].field_off,
											  lay[li].name_off, &e);
						/* 选"合法条目最多"的候选：条目数猜大时开头会多出
						   垃圾记录，合法数反而变少，据此排除 */
						/* 打分：
						   * 脚本包（步长 128）天然有"第一条字段是垃圾"的现象，
						     所以允许一条非法，此时按条目数给分；
						   * 条目数猜大时开头会多出多条垃圾记录，合法数会明显偏低，
						     自然被淘汰。 */
						int score = (ok >= (int)nn - 1) ? (int)nn : ok;
						if (ok >= 2 && score > best_ok) {
							free(best_e);
							best_ok = score;
							best_e = e;
							best_n = (int)nn;
							best_start = start;
							best_stride = lay[li].stride;
						} else {
							free(e);
						}
						e = NULL;
					}
				}
			}
		}
	}
	if (best_e) {
		*ents = best_e;
		*nents = best_n;
		*dir_start = best_start;
		*stride_out = best_stride;
		return 1;
	}
	return 0;
}

/* 目录字段整体错位一格：名字 i 用 i+1 的字段；最后一条用未认领区间 */
static void reconcile_dir(pgm_dir_entry *e, int nums, size_t dir_start,
						  const unsigned char *d, size_t n, int stride)
{
	int i;
	uint32_t *off = calloc((size_t)nums, sizeof(uint32_t));
	uint32_t *size = calloc((size_t)nums, sizeof(uint32_t));

	if (!off || !size) {
		free(off);
		free(size);
		return;
	}
	for (i = 0; i < nums; i++) {
		off[i] = e[i].off;
		size[i] = e[i].size;
	}
	for (i = 0; i + 1 < nums; i++) {
		e[i].off = off[i + 1];
		e[i].size = size[i + 1];
		e[i].valid = (size[i + 1] > 0 &&
					  (size_t)off[i + 1] + size[i + 1] <= dir_start);
	}

	/* 未认领的最大空档补给最后一条 */
	if (nums >= 1) {
		unsigned char *cover = calloc(dir_start + 1, 1);
		uint32_t bestA = 0, bestB = 0;
		int have = 0;
		if (cover) {
			for (i = 0; i + 1 < nums; i++) {
				uint32_t a = e[i].off, b;
				if (!e[i].valid)
					continue;
				b = a + e[i].size;
				if (b > dir_start)
					b = (uint32_t)dir_start;
				if (b > a)
					memset(cover + a, 1, b - a);
			}
			{
				size_t p = 0;
				while (p < dir_start) {
					size_t q = p;
					if (cover[p]) {
						p++;
						continue;
					}
					while (q < dir_start && !cover[q])
						q++;
					if (q - p > 8 && (uint32_t)(q - p) > bestB - bestA) {
						bestA = (uint32_t)p;
						bestB = (uint32_t)q;
						have = 1;
					}
					p = q + 1;
				}
			}
			free(cover);
		}
		if (have) {
			e[nums - 1].off = bestA;
			e[nums - 1].size = bestB - bestA;
			e[nums - 1].valid = 1;
		} else {
			e[nums - 1].valid = 0;
		}
	}
	(void)d;
	(void)n;
	(void)stride;
	free(off);
	free(size);
}

/* ------------------------------------------------------------------ */
/* 二进制封包：按名字取出并解密一个文件                                  */
/* ------------------------------------------------------------------ */

static int read_bin_file(pgm_pack *pk, const char *name, char **out,
						 size_t *out_size)
{
	int i;
	pgm_dir_entry *e = NULL;

	for (i = 0; i < pk->nents; i++) {
		if (pk->ents[i].valid && strcmp(pk->ents[i].name, name) == 0) {
			e = &pk->ents[i];
			break;
		}
	}
	if (!e)
		return -1;

	{
		size_t s = e->off, end = e->off + e->size;
		size_t cap = e->size + 1;
		unsigned char *buf = malloc(cap);
		size_t len = 0;
		int nrec = 0;

		if (!buf)
			return -1;

		while (s + 4 <= end) {
			uint32_t ln = rd32(pk->data + s);
			size_t k;

			if (ln > 65535 || s + 4 + ln > end)
				break;
			if (nrec > 0) {
				/* 记录之间用 \r\n 连接 */
				if (len + 2 > cap) {
					size_t nc = cap * 2 + 64;
					unsigned char *nb = realloc(buf, nc);
					if (!nb) { free(buf); return -1; }
					buf = nb; cap = nc;
				}
				buf[len++] = '\r';
				buf[len++] = '\n';
			}
			if (len + ln > cap) {
				size_t nc = (cap + ln) * 2 + 64;
				unsigned char *nb = realloc(buf, nc);
				if (!nb) { free(buf); return -1; }
				buf = nb; cap = nc;
			}
			for (k = 0; k < ln; k++) {
				unsigned char c = pk->data[s + 4 + k];
				unsigned char key = PGM_KEY[(s + 4 + k) % 64];
				unsigned char p;
				(void)key;
				p = c ^ PGM_KEY[k % 64];
				/* anti-NUL：打包器避免密文出现 0x00，解出的 0 还原为 KEY */
				if (p == 0 && c == PGM_KEY[k % 64])
					p = PGM_KEY[k % 64];
				buf[len++] = p;
			}
			s += 4 + ln;
			nrec++;
		}
		buf[len] = '\0';
		*out = (char *)buf;
		*out_size = len;
		return 0;
	}
}

/* ------------------------------------------------------------------ */
/* 打开 / 读取                                                        */
/* ------------------------------------------------------------------ */

static int looks_binary_pack(const unsigned char *sig, size_t n)
{
	if (n >= 8 && memcmp(sig, "\x89PNG\r\n\x1a\n", 8) == 0)
		return 1;   /* gmdata.bin 第一个条目就是原始 PNG */
	if (n >= 4) {
		uint32_t len = rd32(sig);
		if (len > 0 && len < 4096)
			return 1;
	}
	return 0;
}

int pgm_pack_open(const char *path)
{
	char resolved[1024];
	int h;
	FILE *f;
	long fsz;
	unsigned char *data;
	pgm_dir_entry *ents = NULL;
	int nents = 0;
	size_t dir_start = 0;
	int stride = 0;

	if (pack_count >= PGM_MAX_PACK)
		return -1;
	h = pack_count;

	if (pgm_resolve(path, resolved, sizeof(resolved)) != 0)
		return -1;

	f = fopen(resolved, "rb");
	if (!f)
		return -1;
	fseek(f, 0, SEEK_END);
	fsz = ftell(f);
	fseek(f, 0, SEEK_SET);
	if (fsz <= 0) {
		fclose(f);
		return -1;
	}
	data = malloc((size_t)fsz);
	if (!data || fread(data, 1, (size_t)fsz, f) != (size_t)fsz) {
		free(data);
		fclose(f);
		return -1;
	}
	fclose(f);

	if (!looks_binary_pack(data, (size_t)fsz)) {
		char *dummy;
		size_t ds;

		/* 取第一个 [u32 len] 进行试探 */
		free(data);
		(void)dummy;
		(void)ds;
		return -1;
	}

	if (!parse_bin_dir(data, (size_t)fsz, &ents, &nents, &dir_start,
					   &stride)) {
		pgm_log("pack: %s 的目录解析失败\n", resolved);
		free(data);
		return -1;
	}
	/* 只有脚本包（步长 128）存在"目录字段错位一格"的问题 */
	if (stride == 128)
		reconcile_dir(ents, nents, dir_start, data, (size_t)fsz, stride);

	g_pgm.packs[h].kind = (stride == 128) ? PGM_PACK_BIN : PGM_PACK_RES;
	snprintf(g_pgm.packs[h].path, sizeof(g_pgm.packs[h].path), "%s",
			 resolved);
	g_pgm.packs[h].data = data;
	g_pgm.packs[h].data_size = (size_t)fsz;
	g_pgm.packs[h].ents = ents;
	g_pgm.packs[h].nents = nents;
	g_pgm.packs[h].stride = stride;

	pack_count++;
	pgm_log("pack: %s -> %s，%d 个条目（目录 @0x%zx，步长 %d）\n",
			resolved,
			(stride == 128) ? "脚本封包" : "资源封包",
			nents, dir_start, stride);
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

	if (g_pgm.packs[h].kind == PGM_PACK_BIN)
		return read_bin_file(&g_pgm.packs[h], name, data, size);

	if (g_pgm.packs[h].kind == PGM_PACK_RES) {
		/* 资源包：条目就是整个文件的原始字节，不加密、不按行切 */
		int i;
		for (i = 0; i < g_pgm.packs[h].nents; i++) {
			pgm_dir_entry *e = &g_pgm.packs[h].ents[i];
			char *buf;
			if (!e->valid || strcmp(e->name, name) != 0)
				continue;
			buf = malloc(e->size + 1);
			if (!buf)
				return -1;
			memcpy(buf, g_pgm.packs[h].data + e->off, e->size);
			buf[e->size] = '\0';
			*data = buf;
			*size = e->size;
			return 0;
		}
		return -1;
	}

	if (g_pgm.packs[h].kind == PGM_PACK_DIR) {
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
	int i;
	for (i = 0; i < pack_count; i++) {
		free(g_pgm.packs[i].data);
		free(g_pgm.packs[i].ents);
	}
	memset(g_pgm.packs, 0, sizeof(g_pgm.packs));
	pack_count = 0;
}

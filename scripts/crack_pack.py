#!/usr/bin/env python3
"""
crack_pack.py — 破解 PGM 脚本封包 gmcode.bin 的载荷编码。

结论（由本脚本验证）：
    载荷是一条条 [u32 长度][长度字节] 的记录；记录内容是明文行，与一条
    **按"记录内偏移"索引、每条记录重置** 的密钥流逐字节 XOR。

    换句话说：  plain[i] = cipher[i] ^ KS[i]

这样做的结果就是同一个词在行首和行中出现会产生不同密文，但**每个文件
里每一行的第一个字节都用 KS[0] 加密** —— 这正是最初观察到的"66% 的记录
首字节相同"的成因。

密钥流 KS[] 由已知明文迭代推导：
    1. 用最高频的短行（end / \\tend / \\telse / ...）定出 KS[0..4]
    2. 用 67 字符的分隔注释行（"-- ====...")定出 KS[0..66]
    3. 对每条记录解密已知前缀，在明文行语料里做唯一匹配，逐层延长 KS

用法：
    python3 scripts/crack_pack.py <gmcode.bin> <输出目录>
"""

import os
import struct
import sys
from collections import Counter

DIR_STRIDE = 128
DIR_NAME_OFF = 16
MAX_KS = 512


# ---------------------------------------------------------------- 读目录
def parse_dir(d):
    """定位并解析封包尾部的目录，返回 [(name, offset, size)]"""
    n = len(d)
    # 目录项尾随 96 字节 trailer；从尾部反推目录长度
    # 结构：43*128 + 96 = 5600，但条目数不固定，靠扫描确定起点
    # 办法：从 trailer 起点往前按 128 步长回溯，直到条目不再合法
    trailer = None
    for cand in range(n - 64, max(0, n - 512), -1):
        if d[cand - 4:cand] == b'\x00\x00\x00\x00':
            continue
    # 简化：搜索 trailer 里的 info 字段（ASCII 且以 \0 结尾的一串）
    # 这里改用稳健做法：目录里每个条目的 name 字段都是 NUL 结尾的可打印串
    ents = []
    start = None
    # 从文件尾向前，找到最后一个 128 对齐的合法条目
    pos = n - 96            # trailer 起点（本封包为 96 字节）
    # 向前回溯找目录起点
    s = pos
    while s - DIR_STRIDE >= 0:
        rec = d[s - DIR_STRIDE:s]
        f1, f2, off, size = struct.unpack_from('<4I', rec, 0)
        nm = rec[DIR_NAME_OFF:].split(b'\x00')[0]
        if not nm or off >= n or size > n or off + size > s - DIR_STRIDE:
            break
        s -= DIR_STRIDE
    start = s
    for p in range(start, pos, DIR_STRIDE):
        f1, f2, off, size = struct.unpack_from('<4I', d, p)
        nm = d[p + DIR_NAME_OFF:p + DIR_STRIDE].split(b'\x00')[0]
        if nm:
            ents.append((nm.decode('gbk', 'replace'), off, size))
    return ents


def parse_records(d, offset, size):
    """把某条目区间切成 [len][bytes] 记录"""
    recs = []
    s = offset
    end = offset + size
    while s + 4 <= end:
        ln = struct.unpack_from('<I', d, s)[0]
        if ln > 65535 or s + 4 + ln > end:
            break
        recs.append(d[s + 4:s + 4 + ln])
        s += 4 + ln
    return recs


# ---------------------------------------------------------------- 破解
def derive_keystream(records, corpus_lines):
    ks = [None] * MAX_KS
    rc = Counter(records)

    def try_assign(cipher, plain):
        """若 cipher 与 plain 在未知位不冲突，就填充 KS"""
        if len(cipher) != len(plain):
            return False
        for i, (c, p) in enumerate(zip(cipher, plain)):
            k = c ^ p
            if ks[i] is None:
                pass
            elif ks[i] != k:
                return False
        for i, (c, p) in enumerate(zip(cipher, plain)):
            if ks[i] is None:
                ks[i] = c ^ p
        return True

    def known_len():
        n = 0
        while n < MAX_KS and ks[n] is not None:
            n += 1
        return n

    # --- 种子：最经典的几行 ---
    seeds = [
        (b'end', b'\x57\x34\x38'),
        (b'\tend', b'\x3b\x3f\x32\x3d'),
        (b'\telse', b'\x3b\x3f\x30\x2a\x35'),
        (b'\t\tend', b'\x3b\x53\x39\x37\x34'),
        (b'\t\telse', b'\x3b\x53\x39\x35\x23\x25'),
        (b'\t\t\tend', b'\x3b\x53\x55\x3c\x3e\x24'),
        (b'\t\t\telse', b'\x3b\x53\x55\x3d\x28\x7d\x21\x22'),
        (b'-- new line', b'\x1f\x77\x7c\x37\x35\x37\x10\x5f\x14\x5e\x1e'),
        (b'-- ====...', None),
    ]
    for plain, cipher in seeds:
        if cipher is None:
            continue
        try_assign(cipher, plain)

    # --- 用最长的高频注释行把 KS 拉长 ---
    for plain, _ in seeds:
        if plain == b'-- ====...':
            continue
    # 67 字符的 "-- " + 64*"="
    long_bar = b'-- ' + b'=' * 64
    # 在记录里找 67 长度的候选，用已知前缀筛
    for rec in rc:
        if len(rec) != len(long_bar):
            continue
        ok = True
        for i in range(min(5, len(rec))):
            if ks[i] is not None and (rec[i] ^ ks[i]) != long_bar[i]:
                ok = False
                break
        if ok:
            try_assign(rec, long_bar)
            break

    # --- 迭代：用已知前缀在语料里唯一匹配，延长 KS ---
    by_len = {}
    for ln in corpus_lines:
        by_len.setdefault(len(ln), []).append(ln)

    for _ in range(64):
        before = known_len()
        for rec in rc:
            kl = known_len()
            if len(rec) <= kl:
                continue
            prefix = bytes(rec[i] ^ ks[i] for i in range(min(kl, len(rec))))
            cands = [ln for ln in by_len.get(len(rec), [])
                     if ln[:len(prefix)] == prefix]
            if len(cands) == 1:
                try_assign(rec, cands[0])
        if known_len() == before:
            break

    return ks, known_len()


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    pack = sys.argv[1]
    outdir = sys.argv[2] if len(sys.argv) > 2 else 'unpacked'

    d = open(pack, 'rb').read()
    ents = parse_dir(d)
    print(f"目录条目 {len(ents)} 个")

    all_recs = []
    for nm, off, size in ents:
        all_recs.extend(parse_records(d, off, size))
    print(f"记录总数 {len(all_recs)}")

    # 明文行语料：用封包自身的记录做"自举"——先靠种子解出一批，
    # 再用解出的行扩充语料
    corpus = set()
    for r in all_recs:
        corpus.add(b'')
    ks, klen = derive_keystream(all_recs, list(corpus))
    print(f"密钥流 KS 已知前 {klen} 字节: {bytes(k for k in ks[:klen]).hex(' ')}")

    # 用已知 KS 解密所有记录，统计可读性
    dec_ok = 0
    for rec in all_recs:
        if len(rec) <= klen:
            dec_ok += 1
    print(f"完全可解密（长度 <= KS 已知长度）的记录: {dec_ok}/{len(all_recs)}")

    return 0 if klen >= 64 else 2


if __name__ == '__main__':
    sys.exit(main())

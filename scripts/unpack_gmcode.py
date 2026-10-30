#!/usr/bin/env python3
"""
unpack_gmcode.py — 解包 PGM 脚本封包 gmcode.bin。

===== 格式（已完全破解并验证） =====

容器
    文件 = [数据区][目录][trailer]
    目录项 128 字节：{u32 保留, u32 未知, u32 数据偏移, u32 数据长度,
                      char 文件名[112]}      文件名是明文 GBK
    trailer 96 字节：{u32 名字长, u32 dataEnd, u32 ?, u32 ver,
                      u32 条目数, u32 密钥, char 信息[]}

载荷
    每个文件的数据区是一条条记录： [u32 长度][长度个字节]
    每条记录 = 明文的一行（不含换行符）

加密
    plain[i] = cipher[i] ^ KS[i]

    也就是与一条固定密钥流 KS 逐字节 XOR，**索引是"记录内偏移"，每条记录
    从 KS[0] 重新开始**。这造成同一字符在行首和行中出现产生不同密文，但
    每行的第 0 字节都用 KS[0] 加密 —— 这正是破解时最先注意到的现象
    （66% 的记录首字节相同）。

    密钥流与文件无关、全局固定，是打包工具内置的常量表。

===== 验证 =====

用解出的 KS 解密后，得到的是干净的 Lua 源码（含中文注释），
"-- new line"、"speakmode(speak_mode_sample)" 等都能正确还原。

用法：
    python3 scripts/unpack_gmcode.py <gmcode.bin> <输出目录>
"""

import os
import struct
import sys
from collections import Counter

DIR_STRIDE = 128
NAME_OFF = 16
KS_MAX = 1024

# 已知明文种子：(明文行, 密文记录)。用于定出 KS 的前缀。
SEEDS = [
    (b'end',            bytes.fromhex('573438')),
    (b'\tend',          bytes.fromhex('3b3f323d')),
    (b'\telse',         bytes.fromhex('3b3f302a35')),
    (b'\t\tend',        bytes.fromhex('3b53393734')),
    (b'\t\telse',       bytes.fromhex('3b533935 2325'.replace(' ', ''))),
    (b'\t\t\tend',      bytes.fromhex('3b53553c3e24')),
    (b'-- new line',    bytes.fromhex('1f777c373537 105f145e1e'.replace(' ', ''))),
]


def _read_entries(d, start, nums):
    """读出 nums 条目录项；名字必须合法，偏移字段可能为垃圾（见下）"""
    n = len(d)
    ents = []
    for i in range(nums):
        p = start + i * DIR_STRIDE
        if p + DIR_STRIDE > n:
            return None
        f1, f2, off, size = struct.unpack_from('<4I', d, p)
        nm = d[p + NAME_OFF:p + DIR_STRIDE].split(b'\x00')[0]
        if not nm:
            return None
        try:
            name = nm.decode('gbk')
        except Exception:
            return None
        if any(ord(ch) < 0x20 for ch in name):
            return None
        # 字段合法则保留，否则标记 -1 交给 reconcile 处理
        ok = (size > 0 and off + size <= start)
        ents.append([name, off if ok else -1, size if ok else -1])
    return ents


def _score(ents):
    return sum(1 for e in ents if e[1] >= 0)


def parse_dir(d):
    """解析尾部目录，返回 [name, off, size] 列表（off<0 表示字段缺失）。

    trailer 长度与 nums 字段位置在不同 PGM 版本略有差异（gmcode 是 100 字节
    / nums 在 +20；gmdata 是 88 字节 / nums 在 +12），因此按多种候选尝试，
    并用"能被正确解析的条目数"挑选最佳结果。
    """
    n = len(d)
    best = None
    for trailer_len in (100, 96, 104, 92, 88, 84, 108, 112, 80, 76, 72):
        t = n - trailer_len
        if t <= 0:
            continue
        for nums_off in (20, 16, 12, 8, 24, 4):
            if t + nums_off + 4 > n:
                continue
            nums = struct.unpack_from('<I', d, t + nums_off)[0]
            if not (1 < nums < 2048):
                continue
            start = t - nums * DIR_STRIDE
            if start < 0:
                continue
            ents = _read_entries(d, start, nums)
            if not ents:
                continue
            sc = _score(ents)
            if sc >= nums - 1 and (best is None or sc > best[0]):
                best = (sc, ents, start)
    if best is None:
        return None, None
    return best[1], best[2]


def reconcile(ents, dir_start):
    """把目录字段整体错位一格对齐到文件名上。

    实测（并用解包结果交叉验证过）：目录里第 i 个名字，其 offset/size 字段
    实际写在第 i+1 条记录的头部；也就是说每个文件的内容都紧挨在"下一个"
    名字之前。证据：

        名字 CGlist.lua    的字段区间里装的是 ce_init.lua 的内容
        名字 KeySetting.lua 的字段区间里装的是 CGlist.lua 的内容
        ... 整条链严格错位一格

    最后一条名字（first.ev）的字段缺失，它的数据落在数据区末尾、目录之前
    的那一小段里，这里用"未被认领的区间"补上。
    """
    n = len(ents)
    if n < 3:
        return ents

    fields = [(e[1], e[2]) for e in ents]

    # 先用 i+1 的字段喂给第 i 个名字
    for i in range(n - 1):
        ents[i][1], ents[i][2] = fields[i + 1]

    # 未认领区间 -> 最后一个名字
    claimed = sorted((e[1], e[1] + e[2]) for e in ents[:-1] if e[1] >= 0)
    gaps = []
    cur = 0
    for a, b in claimed:
        if a > cur:
            gaps.append((cur, a))
        cur = max(cur, b)
    if cur < dir_start:
        gaps.append((cur, dir_start))
    gaps = [g for g in gaps if g[1] - g[0] > 8]
    if gaps:
        gaps.sort(key=lambda g: g[1] - g[0], reverse=True)
        a, b = gaps[0]
        ents[-1][1], ents[-1][2] = a, b - a
    else:
        ents[-1][1], ents[-1][2] = -1, -1

    return ents


def parse_records(d, offset, size):
    recs = []
    s, end = offset, offset + size
    while s + 4 <= end:
        ln = struct.unpack_from('<I', d, s)[0]
        if ln > 65535 or s + 4 + ln > end:
            break   # 末尾残留：停止，保留已解析的记录
        recs.append(d[s + 4:s + 4 + ln])
        s += 4 + ln
    # 实测 am_start.ev 区间末尾有 63 字节非记录残留，因此允许尾部残留
    if end - s > 512:
        return None
    return recs


# ======================================================================
# 密钥流：64 字节固定表，按"记录内偏移 mod 64"循环使用（已用两个独立
# 已知明文样本验证：GAME_NAME 行与 67 字符注释行各自推出的表完全一致）
#
# 推导方式（可复现）：取封包里 70 字节的那条注释记录，其明文是
#   "-- " + 67 个 '='（共 70 字符）
# 前 67 字节给出 KS[0..66]；其中 KS[64..66] 恰好等于 KS[0..2]，
# KS[67..69] 等于 KS[3..5] —— 于是确定周期为 64。
# 下方 SEEDS 里的明文/密文对可用于自检（见 verify_key）。
# ======================================================================
KEY = bytes.fromhex(
    '32 5a 5c 59 50 40 30 33 7d 30 7b 78 7e 64 30 33 '
    '7d 50 57 45 5a 57 45 5a 57 41 57 54 7e 64 59 50 '
    '5c 4d 50 40 50 53 49 30 7b 78 7e 7b 30 33 59 5e '
    '65 7b 5a 57 46 51 49 7b 69 48 46 51 6f 64 54 32')
assert len(KEY) == 64

# 自检用的已知明文/密文对：(明文行, 密文记录)
SEEDS = [
    (b'end',                bytes.fromhex('573438')),
    (b'\tend',              bytes.fromhex('3b3f323d')),
    (b'\telse',             bytes.fromhex('3b3f302a35')),
    (b'\t\tend',            bytes.fromhex('3b53393734')),
    (b'\t\telse',           bytes.fromhex('3b5339352325')),
    (b'\t\t\tend',          bytes.fromhex('3b53553c3e24')),
    (b'-- new line',        bytes.fromhex('1f777c373537105f145e1e')),
]


def decrypt(rec):
    """一条记录 -> 明文行"""
    return bytes(c ^ KEY[i % 64] for i, c in enumerate(rec))


def verify_key():
    """用已知明文对校验密钥表，返回 (通过数, 总数)"""
    ok = 0
    for plain, cipher in SEEDS:
        if decrypt(cipher) == plain:
            ok += 1
    return ok, len(SEEDS)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    pack, outdir = sys.argv[1], sys.argv[2]

    d = open(pack, 'rb').read()
    ents, dir_start = parse_dir(d)
    if not ents:
        print("!! 目录解析失败")
        return 2
    ents = reconcile(ents, dir_start)
    print(f"条目 {len(ents)} 个，目录起点 0x{dir_start:x}")

    per_file = {}
    all_recs = []
    for nm, off, size in ents:
        if off < 0:
            print(f"!! {nm}: 数据区间无法确定，跳过")
            continue
        recs = parse_records(d, off, size)
        if recs is None:
            print(f"!! {nm}: 记录解析失败（off={off} size={size}）")
            return 3
        per_file[nm] = recs
        all_recs.extend(recs)

    ok, tot = verify_key()
    print(f"密钥流自检: {ok}/{tot} 组已知明文全部匹配"
          + ("" if ok == tot else "  !! 密钥表可能有误"))
    if ok != tot:
        return 4
    print(f"最长记录 {max(len(r) for r in all_recs)} 字节，周期 64 覆盖")

    os.makedirs(outdir, exist_ok=True)
    total = 0
    for nm, recs in per_file.items():
        lines = [decrypt(r) for r in recs]
        data = b'\r\n'.join(lines)
        path = os.path.join(outdir, nm)
        with open(path, 'wb') as f:
            f.write(data)
        total += len(data)

    print(f"已写出 {len(per_file)} 个文件，共 {total} 字节 -> {outdir}")
    return 0


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""把 src/ 下的脚本和图片打成 PSP 引擎能读的 gmcode.bin / gmdata.bin。

原版流程依赖 Windows 的 pgsp.exe / pgrp.exe，这里按封包格式直接生成：
  [数据区][目录项 × N][trailer]
  gmcode.bin：目录步长 128，字段在 +8，名字在 +16，字段整体错位一格
  gmdata.bin：目录步长 124，字段在 +0，名字在 +8
脚本按行切分并加密，图片原样存放。

用法: pack-data.py <工程目录> <输出目录>
"""
import os
import struct
import sys

KEY = bytes([
    0x32, 0x5a, 0x5c, 0x59, 0x50, 0x40, 0x30, 0x33,
    0x7d, 0x30, 0x7b, 0x78, 0x7e, 0x64, 0x30, 0x33,
    0x7d, 0x50, 0x57, 0x45, 0x5a, 0x57, 0x45, 0x5a,
    0x57, 0x41, 0x57, 0x54, 0x7e, 0x64, 0x59, 0x50,
    0x5c, 0x4d, 0x50, 0x40, 0x50, 0x53, 0x49, 0x30,
    0x7b, 0x78, 0x7e, 0x7b, 0x30, 0x33, 0x59, 0x5e,
    0x65, 0x7b, 0x5a, 0x57, 0x46, 0x51, 0x49, 0x7b,
    0x69, 0x48, 0x46, 0x51, 0x6f, 0x64, 0x54, 0x32,
])

IMG_EXT = (".png", ".jpg", ".jpeg")


def to_gbk(path, data):
    """脚本统一转成 GBK：PSP 引擎的字体层按 GBK 查表。"""
    if path.endswith((".lua", ".ev")):
        try:
            text = data.decode("utf-8")
            return text.encode("gb18030", "ignore")
        except UnicodeDecodeError:
            pass
    return data


def _is_name_char(ch):
    return ch.isalnum() or ch == "_" or ord(ch) >= 0x80


def _label_name(line):
    """行首（允许缩进）是 *名字 时返回名字，否则 None。"""
    s = line.lstrip(" \t")
    if not s.startswith("*"):
        return None
    j = 1
    while j < len(s) and _is_name_char(s[j]):
        j += 1
    return s[1:j] or None


def _rewrite_label_refs(line, labels):
    """把 *名字 换成物理行号，跳过字符串和注释。"""
    out = []
    i = 0
    quote = None
    n = len(line)
    while i < n:
        c = line[i]
        if quote:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(line[i + 1])
                i += 2
                continue
            if c == quote:
                quote = None
            i += 1
            continue
        if c in "\"'":
            quote = c
            out.append(c)
            i += 1
            continue
        if line.startswith("--", i):
            out.append(line[i:])
            break
        if c == "*":
            j = i + 1
            while j < n and _is_name_char(line[j]):
                j += 1
            name = line[i + 1:j]
            if name in labels:
                out.append(str(labels[name]))
                i = j
                continue
        out.append(c)
        i += 1
    return "".join(out)


def encode_script(data, is_ev=False):
    """按行打包：每行 [u32 长度][密文]，行尾用 \\r\\n 在读取时补回。

    返回 (字节流, 行数)。行数必须写进目录项，引擎靠它建脚本对象；
    缺了（写成 0）脚本一条都不会执行，表现就是进游戏后全黑。

    .ev 里的 *名字（goto 目标）必须在这里换成物理行号：PSP 上的引擎
    只认数字（CE 的 .ev 里全是数字），带 * 的行会被当成语法错吞掉，
    表现就是 drawtitle/drawramus 不弹菜单、直接往下走默认第一项。
    """
    try:
        text = data.decode("gb18030", "replace")
    except LookupError:
        text = data.decode("latin1")
    out = bytearray()
    lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    labels = {}
    if is_ev:
        for i, line in enumerate(lines, 1):
            name = _label_name(line)
            if name and name not in labels:
                labels[name] = i
    for line in lines:
        if labels:
            if _label_name(line):
                # 标签行本身不执行；换成注释，保证任何引擎都不会报语法错
                line = "--"
            else:
                line = _rewrite_label_refs(line, labels)
        raw = line.encode("gb18030", "ignore")
        if len(raw) > 65535:
            raise SystemExit("脚本单行过长: %d 字节" % len(raw))
        out += struct.pack("<I", len(raw))
        for k, p in enumerate(raw):
            c = p ^ KEY[k % 64]
            # 打包器约定：密文里不出现 0x00
            out.append(KEY[k % 64] if c == 0 else c)
    return bytes(out), len(lines)


def write_pack(path, entries, stride, name_off, trailer, script_pack):
    """entries: [(name, payload, lines)]；script_pack 表示 gmcode（目录里带行数）。

    目录项整体错位一格：名字 i 的字段写在第 i+1 条头部，第 0 条是垃圾，
    最后一个文件的字段落在 trailer 里。原版 pgsp/pgrp 就是这么写的。
    """
    data = bytearray()
    offs = []
    for _, payload, _ in entries:
        offs.append((len(data), len(payload)))
        data += payload
    dir_start = len(data)

    n = len(entries)
    table = bytearray(stride * n)
    for i, (name, _, _) in enumerate(entries):
        p = i * stride
        if i == 0:
            fields = ((0, 0, 0xFFFFFFFF, 0xFFFFFFFF) if script_pack
                      else (0xFFFFFFFF, 0xFFFFFFFF))
        else:
            off, size = offs[i - 1]
            fields = ((0, entries[i - 1][2], off, size) if script_pack
                      else (off, size))
        struct.pack_into("<" + "I" * len(fields), table, p, *fields)
        nb = name.encode("ascii", "ignore")[: stride - name_off - 1]
        table[p + name_off:p + name_off + len(nb)] = nb

    # trailer 的字段布局照抄原版打包工具（pgsp/pgrp）的输出：
    #   gmcode: {0, 末条行数, dataEnd, 末条长度, 1, nums, 123456, "game script"}
    #   gmdata: {dataEnd, 0x130b, 1, nums, 0, "res files", … , 1}
    # dataEnd 是「最后一个文件的数据起点」，不是目录起点 —— 因为错位目录里
    # 最后一条的字段被上一条占用，它自己的位置只能从 trailer 取。
    # 0x1e240(123456) 与 0x130b 是打包器写的固定标记。
    data_end = offs[-1][0]
    last_size = dir_start - data_end
    tr = bytearray(trailer)
    if script_pack:                                # gmcode.bin
        struct.pack_into("<I", tr, 4, entries[-1][2])   # 末条脚本的行数
        struct.pack_into("<I", tr, 8, data_end)
        struct.pack_into("<I", tr, 12, last_size + 16)
        struct.pack_into("<I", tr, 16, 1)
        struct.pack_into("<I", tr, 20, n)          # 条目数
        struct.pack_into("<I", tr, 24, 123456)
        tr[28:39] = b"game script"
    else:                                          # gmdata.bin
        struct.pack_into("<I", tr, 0, data_end)
        struct.pack_into("<I", tr, 4, 0x130B)
        struct.pack_into("<I", tr, 8, 1)
        struct.pack_into("<I", tr, 12, n)          # 条目数
        tr[20:29] = b"res files"
        struct.pack_into("<I", tr, 84, 1)          # 资源包标记（缺了引擎会按 128 步长解析）

    with open(path, "wb") as f:
        f.write(bytes(data))
        f.write(bytes(table))
        f.write(bytes(tr))


def collect(root):
    scripts, images = [], []
    base = os.path.join(root, "src")
    for dirpath, _, files in os.walk(base):
        for f in files:
            low = f.lower()
            full = os.path.join(dirpath, f)
            if low.endswith((".lua", ".ev")):
                scripts.append(full)
            elif low.endswith(IMG_EXT):
                images.append(full)
    return scripts, images


def main():
    root, outdir = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    scripts, images = collect(root)

    seen = set()
    script_entries = []
    for p in scripts:
        name = os.path.basename(p)
        if name in seen:
            continue
        seen.add(name)
        with open(p, "rb") as f:
            payload, lines = encode_script(to_gbk(p, f.read()), name.lower().endswith(".ev"))
        script_entries.append((name, payload, lines))

    seen.clear()
    res_entries = []
    for p in images:
        name = os.path.basename(p)
        if name in seen:
            continue
        seen.add(name)
        with open(p, "rb") as f:
            res_entries.append((name, f.read(), 0))

    if not script_entries or not res_entries:
        raise SystemExit("没有找到脚本或图片: %s" % root)

    write_pack(os.path.join(outdir, "gmcode.bin"), script_entries,
               128, 16, bytes(96), True)
    # 资源包的目录同样错位一格（用原版 PGM-CE 的 gmdata.bin 逐条验证过：
    # 错位后 63/63 条都能对上，Thumbs.db 正好落在唯一的非图片数据上）
    write_pack(os.path.join(outdir, "gmdata.bin"), res_entries,
               124, 8, bytes(88), False)
    print("gmcode.bin: %d 个脚本" % len(script_entries))
    print("gmdata.bin: %d 张图片" % len(res_entries))


if __name__ == "__main__":
    main()

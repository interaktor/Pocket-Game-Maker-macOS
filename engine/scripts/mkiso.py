#!/usr/bin/env python3
"""最小 ISO9660 生成器 —— 保留文件名大小写（PSP 的 PGM 引擎需要小写路径）"""
import os, sys, struct

SECTOR = 2048
DATE7 = bytes([126, 1, 1, 0, 0, 0, 0])          # 2026-01-01
DATE17 = b'2026010100000000' + b'\x00'

def b16(v): return struct.pack('<H', v) + struct.pack('>H', v)
def b32(v): return struct.pack('<I', v) + struct.pack('>I', v)

def rec(name, extent, size, is_dir):
    rl = 33 + len(name)
    if rl % 2: rl += 1
    b = bytearray([rl, 0])
    b += b32(extent) + b32(size) + DATE7
    b.append(2 if is_dir else 0)
    b += bytes([0, 0]) + b16(1)
    b.append(len(name)); b += name
    b += b'\x00' * (rl - len(b))
    return bytes(b)

class Node:
    __slots__ = ('name','path','isdir','children','size','extent','num','_sz','parent')
    def __init__(self, name, path, isdir):
        self.name, self.path, self.isdir = name, path, isdir
        self.children, self.size, self.extent, self.num = [], 0, 0, 0

def scan(path, name=''):
    n = Node(name, path, os.path.isdir(path))
    if n.isdir:
        for e in sorted(os.listdir(path)):
            n.children.append(scan(os.path.join(path, e), e))
    else:
        n.size = os.path.getsize(path)
    return n

def main():
    src, out = sys.argv[1], sys.argv[2]
    root = scan(src, '')
    dirs, files = [], []
    def collect(n, depth):
        (dirs if n.isdir else files).append(n)
        for c in n.children: collect(c, depth+1)
    for c in root.children: collect(c, 0)
    root.num = 1
    alldirs = [root] + dirs
    for i, d in enumerate(alldirs[1:], start=2): d.num = i

    def dir_size(n):
        sz = 68
        for c in n.children:
            rl = 33 + len(c.name.encode())
            if rl % 2: rl += 1
            sz += rl
        return ((sz + SECTOR - 1) // SECTOR) * SECTOR

    pvd_sector = 16
    term_sector = 17
    lpt_sector = 18
    nsec_l = ((len(alldirs) * 10 + 200) // SECTOR + 1)
    mpt_sector = lpt_sector + nsec_l
    cur = mpt_sector + nsec_l
    for d in alldirs:
        d.extent = cur
        d._sz = dir_size(d) if False else dir_size(d)
        cur += d._sz // SECTOR
    for f in files:
        f.extent = cur
        cur += (f.size + SECTOR - 1) // SECTOR
    total = cur

    # 路径表
    def pt(be):
        o = bytearray()
        for d in alldirs:
            nm = d.name.encode()
            o.append(len(nm)); o.append(0)
            o += struct.pack('>I' if be else '<I', d.extent)
            o += struct.pack('>H' if be else '<H', (0 if d is root else d.parent.num))
            o += nm
            if len(nm) % 2: o.append(0)
        return bytes(o)
    for d in alldirs: d.parent = root
    for d in alldirs:
        for c in d.children:
            if c.isdir: c.parent = d
    lpt, mpt = pt(False), pt(True)

    img = bytearray(total * SECTOR)
    # PVD
    p = bytearray(SECTOR)
    p[0] = 1; p[1:6] = b'CD001'; p[6] = 1
    p[8:40] = b'PGM-MAC'.ljust(32)
    p[40:72] = b'PSPGAME'.ljust(32)
    p[80:88] = b32(total)
    p[120:124] = b16(1); p[124:128] = b16(1)
    p[128:132] = b16(SECTOR)
    p[132:140] = b32(len(lpt))
    p[140:144] = struct.pack('<I', lpt_sector)
    p[148:152] = struct.pack('>I', mpt_sector)
    p[156:190] = rec(b'\x00', root.extent, root._sz, True)
    p[574:702] = b'PGM-MAC'.ljust(128)
    p[813:829] = DATE17; p[830:846] = DATE17
    p[847:863] = b'0'*16; p[864:880] = b'0'*16
    p[881] = 1
    img[pvd_sector*SECTOR:(pvd_sector+1)*SECTOR] = p
    # 终止符
    t = bytearray(SECTOR); t[0] = 255; t[1:6] = b'CD001'; t[6] = 1
    img[term_sector*SECTOR:(term_sector+1)*SECTOR] = t
    # 路径表
    off = lpt_sector*SECTOR; img[off:off+len(lpt)] = lpt
    off = mpt_sector*SECTOR; img[off:off+len(mpt)] = mpt
    # 目录
    for d in alldirs:
        buf = bytearray()
        buf += rec(b'\x00', d.extent, d._sz, True)
        buf += rec(b'\x01', (d.parent.extent if d is not root else d.extent),
                   (d.parent._sz if d is not root else d._sz), True)
        for c in d.children:
            buf += rec(c.name.encode(), c.extent,
                       c._sz if c.isdir else c.size, c.isdir)
        need = ((len(buf) + SECTOR - 1) // SECTOR) * SECTOR
        if need > d._sz:
            raise SystemExit(f'目录 {d.name} 超出预算')
        img[d.extent*SECTOR : d.extent*SECTOR + len(buf)] = buf
    # 文件
    for f in files:
        with open(f.path, 'rb') as fp:
            data = fp.read()
        img[f.extent*SECTOR : f.extent*SECTOR + len(data)] = data

    open(out, 'wb').write(img)
    print(f'完成: {out} ({total*SECTOR/1048576:.1f} MB, {len(alldirs)} 目录, {len(files)} 文件)')

main()

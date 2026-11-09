#!/bin/sh
# export-iso.sh — 把工程打成 PSP 用的 ISO
#
# 用法: export-iso.sh <工程目录> <输出.iso> [ISO 内显示名] [PSP模板目录]
set -e
GAME="$1"
OUT="$2"
TITLE="${3:-PGM Game}"
TPL="${4:-}"

[ -d "$GAME/bin" ] || { echo "!! $GAME 不是 PGM 工程"; exit 1; }
[ -n "$TPL" ] || { echo "!! 缺少 PSP 模板目录"; exit 1; }
[ -d "$TPL/PSP_GAME" ] || { echo "!! 模板里没有 PSP_GAME: $TPL"; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

echo ">> 复制 PSP_GAME 模板"
cp -R "$TPL/PSP_GAME" "$STAGE/PSP_GAME"
SD="$STAGE/PSP_GAME/SYSDIR"

echo ">> 放入游戏数据"
cp -R "$GAME/bin/data" "$SD/data"
[ -f "$GAME/bin/engine.sys" ] && cp "$GAME/bin/engine.sys" "$SD/engine.sys"
[ -f "$GAME/bin/pgm.ini" ]    && cp "$GAME/bin/pgm.ini"    "$SD/pgm.ini"
rm -rf "$SD/data/PGMSAVEDATA"

echo ">> 写入标题"
python3 - "$STAGE/PSP_GAME/PARAM.SFO" "$TITLE" <<'PY'
import sys, struct
path, title = sys.argv[1], sys.argv[2]
b = bytearray(open(path,'rb').read())
if b[:4] != b'\x00PSF':
    print("  PARAM.SFO 格式不对，跳过"); raise SystemExit
keytab, datatab, count = struct.unpack_from('<III', b, 8)
for i in range(count):
    off = 20 + i*16
    koff, fmt, dlen, dmax, doff = struct.unpack_from('<HHIII', b, off)
    kstart = keytab + koff
    key = bytes(b[kstart:b.index(0, kstart)]).decode('ascii','ignore')
    if key != 'TITLE':
        continue
    raw = title.encode('utf-8') + b'\0'
    if len(raw) > dmax:
        raw = title.encode('utf-8')[:dmax-1] + b'\0'
        print(f"  标题过长，已截断到 {dmax-1} 字节")
    b[datatab+doff:datatab+doff+dmax] = raw + b'\0'*(dmax-len(raw))
    struct.pack_into('<I', b, off+4, len(raw))
    open(path,'wb').write(bytes(b))
    print(f"  标题 = {title}")
    break
else:
    print("  没找到 TITLE 字段")
PY

echo ">> 生成 ISO"
rm -f "$OUT"
# 用自带生成器：保留文件名大小写（hdiutil 会强制转大写，PSP 引擎读不到小写路径）
python3 "$(dirname "$0")/mkiso.py" "$STAGE" "$OUT"
echo "完成: $OUT ($(du -h "$OUT" | cut -f1))"

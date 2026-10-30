#!/bin/sh
#
# new-project.sh — 从当前工程复制出一个新游戏
#
# 用法: ./scripts/new-project.sh 我的游戏 [放在哪个目录]

set -e
NAME="$1"
DEST="${2:-.}"
[ -z "$NAME" ] && { echo "用法: $0 <工程名> [目录]"; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$DEST"
case "$NAME" in
	*/*) OUT="$NAME" ;;
	*)   OUT="$DEST/$NAME" ;;
esac
[ -e "$OUT" ] && { echo "!! $OUT 已存在"; exit 1; }

mkdir -p "$OUT"
cp -R "$ROOT/bin" "$OUT/bin"
mkdir -p "$OUT/src"
cp "$ROOT/src/am_start.ev" "$ROOT/src/pubdata.ev" "$OUT/src/"
cp -R "$ROOT/src/system" "$OUT/src/system"
cp -R "$ROOT/src/files" "$OUT/src/files"
mkdir -p "$OUT/src/user"

# 只保留一张占位背景，清掉示例画册
rm -rf "$OUT/src/files/gallery/"*.png "$OUT/PGMSAVEDATA" 2>/dev/null || true

cat > "$OUT/src/user/main.ev" <<'TEMPLATE'
-- 你的剧本就写在这个文件里
-- 一句台词两行：text(...) 然后 textcl()

*start
msgboxon()
bg("backdrop.png")

text("第一句台词写在这里。")
textcl()

text("旁白","带人名的台词这样写。")
textcl()

jump("main.ev")
TEMPLATE

echo ">> 已创建: $OUT"
echo
echo "    cd \"$OUT\" && ./run.sh"
echo "    改 src/user/main.ev"

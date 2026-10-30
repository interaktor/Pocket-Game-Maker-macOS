#!/bin/sh
#
# new-project.sh — 从骨架创建一个新游戏工程
#
# 用法：
#   ./scripts/new-project.sh 我的游戏
#   ./scripts/new-project.sh 我的游戏 ~/Desktop
#
# 生成后：
#   cd 我的游戏 && ./run.sh
# 然后编辑 src/user/main.ev 就行。

set -e

NAME="$1"
DEST="${2:-.}"

if [ -z "$NAME" ]; then
	echo "用法: $0 <工程名> [放在哪个目录]"
	echo "例子: $0 我的第一个游戏"
	exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/starter"

if [ ! -d "$SRC" ]; then
	echo "!! 找不到骨架目录: $SRC"
	exit 1
fi

mkdir -p "$DEST"
case "$NAME" in
	*/*) OUT="$NAME" ;;          # 给了完整路径就直接用
	*)   OUT="$DEST/$NAME" ;;
esac

if [ -e "$OUT" ]; then
	echo "!! $OUT 已经存在了，换个名字或者先删掉"
	exit 1
fi

cp -R "$SRC" "$OUT"
rm -rf "$OUT/PGMSAVEDATA"

echo ">> 已创建: $OUT"
echo
echo "接下来："
echo "    cd \"$OUT\""
echo "    ./run.sh              # 跑起来看看"
echo "    编辑 src/user/main.ev  # 写你的剧情"
echo
echo "如果跑不动，先构建引擎："
echo "    cd \"$ROOT\" && ./scripts/build.sh Release"

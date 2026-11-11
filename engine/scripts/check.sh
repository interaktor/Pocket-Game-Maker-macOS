#!/bin/sh
# check.sh — 提交前的冒烟测试：编译 + 跑游戏 + 统计报错
#
# 用法: ./engine/scripts/check.sh [工程目录]
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GAME="${1:-$ROOT}"
REL="$ROOT/build/Release"
FAIL=0

say() { printf '%-28s %s\n' "$1" "$2"; }

echo ">> 编译工作台"
if "$ROOT/engine/scripts/build-studio.sh" >/tmp/check_studio.log 2>&1; then
	say "  build-studio" "OK"
else
	say "  build-studio" "失败 → /tmp/check_studio.log"; FAIL=1
fi

echo ">> 编译引擎"
if [ -x "$REL/pgm-mac" ]; then
	say "  build" "已存在，跳过"
else
	if "$ROOT/engine/scripts/build.sh" Release >/tmp/check_engine.log 2>&1; then
		say "  build" "OK"
	else
		say "  build" "失败 → /tmp/check_engine.log"; FAIL=1
	fi
fi

if [ ! -x "$REL/pgm-mac" ]; then
	echo "没有引擎，跳过运行测试"; exit 1
fi

echo ">> 运行 300 帧"
LOG=/tmp/check_run.log
PGM_MAC_FRAMES=300 "$REL/pgm-mac" "$GAME" >"$LOG" 2>&1 || true
ERRS=$(grep -c '!!' "$LOG" 2>/dev/null || true)
say "  报错数" "$ERRS"
if [ "$ERRS" != "0" ]; then
	echo "  前几条："
	grep '!!' "$LOG" | head -5 | sed 's/^/    /'
	FAIL=1
fi

rm -rf "$GAME/PGMSAVEDATA" 2>/dev/null || true

echo
if [ "$FAIL" = "0" ]; then
	echo "通过 ✓"
else
	echo "有问题 ✗ 看上面的日志"
	exit 1
fi

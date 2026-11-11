#!/bin/sh
# check.sh — 提交前的冒烟测试：编译 + 跑游戏 + 统计报错 + 回归测试
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
# 引擎源码比二进制新时必须重编，避免测试跑在旧二进制上
NEED_BUILD=1
if [ -x "$REL/pgm-mac" ]; then
	NEWER=$(find "$ROOT/engine" -type f \( -name '*.c' -o -name '*.h' \) \
		-newer "$REL/pgm-mac" -print 2>/dev/null | head -1)
	[ -z "$NEWER" ] && NEED_BUILD=0
fi
if [ "$NEED_BUILD" = "0" ]; then
	say "  build" "已是最新，跳过"
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
SAVE="$GAME/PGMSAVEDATA"
HAD_SAVE=0
[ -e "$SAVE" ] && HAD_SAVE=1
PGM_MAC_FRAMES=300 "$REL/pgm-mac" "$GAME" >"$LOG" 2>&1 || true
ERRS=$(grep -c '!!' "$LOG" 2>/dev/null || true)
say "  报错数" "$ERRS"
if [ "$ERRS" != "0" ]; then
	echo "  前几条："
	grep '!!' "$LOG" | head -5 | sed 's/^/    /'
	FAIL=1
fi

# 测试自己生成的存档只在原本没有时才清掉，别删玩家已有的存档
if [ "$HAD_SAVE" = "0" ]; then
	rm -rf "$SAVE" 2>/dev/null || true
fi

echo ">> 回归测试"
if "$ROOT/engine/scripts/regress.sh" >/tmp/check_regress.log 2>&1; then
	say "  regress" "OK"
else
	say "  regress" "失败 → /tmp/check_regress.log"; FAIL=1
fi

echo
if [ "$FAIL" = "0" ]; then
	echo "通过 ✓"
else
	echo "有问题 ✗ 看上面的日志"
	exit 1
fi

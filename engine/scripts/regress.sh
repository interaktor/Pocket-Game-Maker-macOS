#!/bin/sh
# regress.sh — PGM Studio / 引擎 回归测试
#
# 全部在临时目录里跑，不会修改当前工程。
# 用法: ./engine/scripts/regress.sh
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REL="$ROOT/build/Release"
OUT="$ROOT/build/Regress"
TMP="${TMPDIR:-/tmp}/pgm_regress_last"
BIN="$OUT/studio_regress"
FAIL=0

say() { printf '%-28s %s\n' "$1" "$2"; }

cleanup() { [ "$FAIL" = "0" ] && rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

rm -rf "$TMP"
mkdir -p "$TMP" "$OUT"

echo ">> 编译工作台测试"
if clang -fobjc-arc -O1 \
	-framework Cocoa -framework ImageIO -framework AVFoundation -framework CoreText \
	-o "$BIN" "$ROOT/engine/tests/studio_regress.m" >"$TMP/build.log" 2>&1; then
	say "  studio_regress" "OK"
else
	say "  studio_regress" "编译失败"
	sed 's/^/    /' "$TMP/build.log" | tail -20
	exit 1
fi

echo ">> 工作台逻辑"
if "$BIN" "$ROOT" "$TMP/projroot" >"$TMP/studio.log" 2>&1; then
	say "  studio" "通过"
else
	say "  studio" "失败"
	FAIL=1
fi
grep -E '^(PASS|FAIL)' "$TMP/studio.log" | sed 's/^/    /' || true
if [ "$FAIL" != "0" ]; then
	echo "    日志: $TMP/studio.log"
fi

if [ ! -x "$REL/pgm-mac" ]; then
	echo "没有引擎，跳过引擎测试"; exit 1
fi

echo ">> 引擎：启用标题画面"
LOG="$TMP/title.log"
PGM_MAC_FRAMES=90 "$REL/pgm-mac" "$TMP/projroot/proj" >"$LOG" 2>&1 || true
if grep -q '主循环结束' "$LOG" && ! grep -q '!!' "$LOG"; then
	say "  title" "OK（无报错）"
else
	say "  title" "失败"
	grep '!!' "$LOG" | head -5 | sed 's/^/    /' || true
	FAIL=1
fi

echo ">> 引擎：标题缺图不崩溃"
MISS="$TMP/notitle"
cp -R "$TMP/projroot/proj" "$MISS"
rm -f "$MISS/src/files/bg/title.png"
LOG2="$TMP/missing.log"
PGM_MAC_FRAMES=60 "$REL/pgm-mac" "$MISS" >"$LOG2" 2>&1 || true
if grep -q '主循环结束' "$LOG2"; then
	say "  missing-image" "OK（未崩溃）"
else
	say "  missing-image" "失败"
	tail -8 "$LOG2" | sed 's/^/    /'
	FAIL=1
fi

echo ">> 导出 ISO：自定义图标/背景/标题"
ICON="$TMP/icon0.png"
PIC="$TMP/pic1.png"
ISO="$TMP/game.iso"
BACKDROP="$TMP/projroot/proj/src/files/bg/backdrop.png"
sips -z 80 144 "$BACKDROP" --out "$ICON" >/dev/null 2>&1
sips -z 272 480 "$BACKDROP" --out "$PIC" >/dev/null 2>&1
if sh "$ROOT/engine/scripts/export-iso.sh" "$TMP/projroot/proj" "$ISO" \
	"回归测试" "" "$ICON" "$PIC" >"$TMP/iso.log" 2>&1 &&
	[ -f "$ISO" ] &&
	grep -q '自定义图标' "$TMP/iso.log" &&
	grep -q '自定义背景' "$TMP/iso.log" &&
	grep -q '标题 = 回归测试' "$TMP/iso.log"; then
	if command -v bsdtar >/dev/null 2>&1; then
		LIST=$(bsdtar -tf "$ISO" 2>/dev/null || true)
		case "$LIST" in
			*ICON0.PNG*PIC1.PNG*|*PIC1.PNG*ICON0.PNG*)
				say "  iso" "OK（含 ICON0/PIC1）" ;;
			*)
				say "  iso" "失败（ISO 里缺图标或背景图）"; FAIL=1 ;;
		esac
	else
		say "  iso" "OK（无 bsdtar，跳过内容校验）"
	fi
else
	say "  iso" "失败"
	tail -8 "$TMP/iso.log" | sed 's/^/    /' || true
	FAIL=1
fi

echo
if [ "$FAIL" = "0" ]; then
	echo "回归通过 ✓"
else
	echo "回归失败 ✗"
	exit 1
fi

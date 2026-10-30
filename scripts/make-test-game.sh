#!/bin/sh
#
# make-test-game.sh — 组装一个可用于测试的 PGM 游戏目录。
#
# 为什么要组装：
#   PGM_CE 的仓库里 bin/ 和 src/ 是"拆分"状态的 —— bin/data/gmcode.bin 是
#   打包好的完整脚本集（含原版 v0.83 与 CE 两套框架共 43 个脚本），而
#   src/ 只放了 CE 自己那 24 个，缺少 lg_init.lua 依赖的 12 个原版脚本。
#
#   本脚本按"CE 优先、原版补缺"的规则合成一个完整 src/，正是 gmcode.bin
#   里那一份的内容。这样在封包载荷解码完成之前，也能真实验证 Lua 宿主。
#
# 用法：
#   ./scripts/make-test-game.sh [输出目录]
#   默认输出到 build/testgame

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/testgame}"

CE="${PGM_CE_DIR:-$ROOT/../PGM-CE}"
ORIG="${PGM_ORIG_DIR:-$ROOT/../PGM-orig/PGMv0.83完整版}"

if [ ! -d "$CE/bin" ]; then
	echo "!! 找不到 PGM_CE: $CE"
	echo "   请设置 PGM_CE_DIR 环境变量指向 PGM_CE 的 checkout"
	exit 1
fi
if [ ! -d "$ORIG/src" ]; then
	echo "!! 找不到原版: $ORIG"
	echo "   请设置 PGM_ORIG_DIR 环境变量"
	exit 1
fi

echo ">> PGM_CE  : $CE"
echo ">> 原版    : $ORIG"
echo ">> 输出    : $OUT"

rm -rf "$OUT"
mkdir -p "$OUT"

# bin/ 直接用 CE 的（含 pgm.ini、engine.sys、data/、字体等）
cp -R "$CE/bin" "$OUT/bin"

# src/ = 原版打底
cp -R "$ORIG/src" "$OUT/src"

# 再用 CE 的覆盖（CE 优先）
cp -R "$CE/src/." "$OUT/src/"

# ---------------------------------------------------------------------
# 测试树适配：原版的 lg_init.lua 不知道 CE 新增的 animation.lua /
# KeySetting.lua，但 CE 的 globals.lua 需要 ANIBase（由 animation.lua 定义）。
# CE 真正发行版的 lg_init.lua 一定是改编过的，但那份内容只在打包好的
# gmcode.bin 里。在封包解码完成之前，这里显式补上，让测试树自洽。
# 仅影响 build/testgame，不修改上游仓库。
# ---------------------------------------------------------------------
python3 - "$OUT/src/lg_init.lua" <<'PY'
import sys
p = sys.argv[1]
d = open(p, 'rb').read().decode('gb18030', 'replace')
if 'animation.lua' not in d:
    d = d.replace('include("globals.lua")',
                  'include("animation.lua")\ninclude("KeySetting.lua")\n'
                  'include("globals.lua")', 1)
    open(p, 'wb').write(d.encode('gb18030', 'replace'))
    print(">> 已为测试树补入 animation.lua / KeySetting.lua 依赖")
PY

# 统计
n=$(find "$OUT/src" -name '*.lua' -o -name '*.ev' | wc -l | tr -d ' ')
echo ">> 合成完成：src/ 共 $n 个脚本"
echo ">> 运行： ./build/Debug/pgm-mac $OUT"

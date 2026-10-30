#!/bin/sh
#
# build.sh — 在 macOS 上构建 libnge2（带 NGE_MAC 后端）和 P1 冒烟测试。
#
# 用法：
#   ./scripts/build.sh              # Release
#   ./scripts/build.sh Debug        # Debug（默认）
#   ./scripts/build.sh Debug clean  # 先清干净再构建
#
# 依赖（二选一）：
#   * Homebrew: brew install libpng jpeg-turbo giflib freetype
#   * MacPorts: sudo port install libpng libjpeg-turbo giflib freetype
#
# 说明：在 P2 引入 PGM 宿主层之后，这里会换成顶层 CMakeLists.txt 的
# add_subdirectory 结构；当前阶段 libnge2 自身的 CMakeLists 就是构建入口。

set -e

TYPE="${1:-Debug}"
CLEAN="$2"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build/$TYPE"

if [ "$CLEAN" = "clean" ]; then
	echo ">> 清理 $BUILD"
	rm -rf "$BUILD"
fi

# ---- 找到依赖前缀 -------------------------------------------------------
PREFIX=""
for p in /opt/homebrew /usr/local /opt/local; do
	if [ -d "$p/include" ] && [ -f "$p/include/png.h" ]; then
		PREFIX="$p"
		break
	fi
done
if [ -z "$PREFIX" ]; then
	echo "!! 找不到 libpng。请先装依赖："
	echo "   brew install libpng jpeg-turbo giflib freetype"
	echo "   或 sudo port install libpng libjpeg-turbo giflib freetype"
	exit 1
fi
echo ">> 依赖前缀: $PREFIX"

# ---- 检查补丁是否已应用 -------------------------------------------------
if ! grep -q 'PGM-Mac: src/charsets' "$ROOT/third_party/libnge2/CMakeLists.txt" 2>/dev/null; then
	echo ">> 应用 macOS 补丁"
	python3 "$ROOT/scripts/apply_mac_patches.py"
fi

# ---- 配置与编译 ---------------------------------------------------------
mkdir -p "$BUILD"
cd "$BUILD"

# 明确部署目标，避免 "built for newer macOS than being linked" 这类警告
OSX_MIN="$(sw_vers -productVersion | cut -d. -f1-2)"

cmake \
	-DCMAKE_OSX_DEPLOYMENT_TARGET="$OSX_MIN" \
	-DBUILD_FOR=Normal \
	-DBUILD_SAMPLES=OFF \
	-DCMAKE_BUILD_TYPE="$TYPE" \
	-DUNZIP_FOUND=TRUE \
	-DCMAKE_PREFIX_PATH="$PREFIX" \
	-DFREETYPE_INCLUDE_DIRS="$PREFIX/include/freetype2" \
	-DCMAKE_C_FLAGS="-I$PREFIX/include -I$PREFIX/include/freetype2" \
	-DCMAKE_CXX_FLAGS="-I$PREFIX/include -I$PREFIX/include/freetype2" \
	-DCMAKE_OBJC_FLAGS="-I$PREFIX/include" \
	-DCMAKE_EXE_LINKER_FLAGS="-L$PREFIX/lib" \
	"$ROOT/third_party/libnge2"

make -j"$(sysctl -n hw.ncpu)"

# ---- P1 冒烟测试 --------------------------------------------------------
LIB_SUFFIX=""
if [ "$TYPE" = "Debug" ]; then LIB_SUFFIX="_d"; fi

echo ">> 构建 P1 冒烟测试"
cc -o "$BUILD/p1_smoke" "$ROOT/tests/p1_smoke.c" \
	-I "$ROOT/third_party/libnge2/include" \
	-I "$PREFIX/include" \
	-I "$PREFIX/include/freetype2" \
	-DGL_SILENCE_DEPRECATION \
	-mmacosx-version-min="$OSX_MIN" \
	-L "$BUILD/lib" -L "$PREFIX/lib" \
	-l"nge2$LIB_SUFFIX" -l"coolaudio$LIB_SUFFIX" \
	-lpng -ljpeg -lgif -lfreetype -lz \
	-framework Cocoa -framework OpenGL -framework AVFoundation

# ---- Lua 5.1.4 -----------------------------------------------------------
LUA_SRC="$ROOT/third_party/lua-5.1.4/src"
if [ ! -f "$BUILD/lib/liblua5.1.a" ]; then
	echo ">> 构建 Lua 5.1.4"
	mkdir -p "$BUILD/luaobj"
	( cd "$LUA_SRC" && for f in *.c; do
		cc -c -O2 -DLUA_USE_MACOSX -I. "$f" -o "$BUILD/luaobj/${f%.c}.o" || exit 1
	  done )
	ar rcs "$BUILD/lib/liblua5.1.a" "$BUILD"/luaobj/*.o
	rm -rf "$BUILD/luaobj"
fi

# ---- PGM 宿主 ------------------------------------------------------------
# 注意：src/pgm_audio.c 暂不纳入构建。它把 SoundCreate 覆盖成返回
# AVAudioPlayer 对象，但运行时 api_SoundVolume 会调到空函数指针而崩溃
# （详见 docs/HOST-STATUS.md 与 third_party/libnge2/coolaudio/nge_audio_mac.m）。
# 音频修好后再把它加回下面的源文件列表。
echo ">> 构建 PGM 宿主"
cc -o "$BUILD/pgm-mac" \
	"$ROOT/src/pgm_main.c" \
	"$ROOT/src/pgm_lua.c" \
	"$ROOT/src/pgm_pack.c" \
	"$ROOT/src/pgm_api.c" \
	"$ROOT/src/pgm_gfx.c" \
	"$ROOT/src/pgm_escript.c" \
	"$ROOT/src/pgm_mem.c" \
	"$ROOT/src/pgm_dialog.c" \
	"$ROOT/src/pgm_effect.c" \
	"$ROOT/src/pgm_input.c" \
	-I "$LUA_SRC" \
	-I "$ROOT/third_party/libnge2/include" \
	-I "$PREFIX/include" \
	-DLUA_USE_MACOSX -DGL_SILENCE_DEPRECATION \
	-mmacosx-version-min="$OSX_MIN" \
	"$BUILD/lib/libnge2$LIB_SUFFIX.a" "$BUILD/lib/liblua5.1.a" \
	-L "$BUILD/lib" -L "$PREFIX/lib" \
	-l"coolaudio$LIB_SUFFIX" -lpng -ljpeg -lgif -lfreetype -lz \
	-framework Cocoa -framework OpenGL -framework AVFoundation -lm

echo
echo "构建完成。验收测试："
echo "  $BUILD/p1_smoke 20 /tmp/p1_smoke.png     # P1: 渲染"
echo "  ./scripts/make-test-game.sh              # 组装测试游戏目录"
echo "  $BUILD/pgm-mac build/testgame            # 加载 PGM 脚本框架"
echo "  PGM_MAC_FRAMES=60 PGM_MAC_SHOT=/tmp/g.png $BUILD/pgm-mac ../PGM-CE  # 跑主循环并截图"
echo
echo "打包成可双击的 .app："
echo "  ./scripts/build.sh Release && ./scripts/make-app.sh Release ../PGM-CE"

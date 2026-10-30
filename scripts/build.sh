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
	-framework Cocoa -framework OpenGL

echo
echo "构建完成。运行验收测试："
echo "  $BUILD/p1_smoke 20 /tmp/p1_smoke.png"

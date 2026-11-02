#!/bin/sh
#
# make-app.sh — 把 pgm-mac 打包成可双击运行的 PGM.app
#
# 做的事：
#   1. 建 .app 目录结构（Contents/MacOS、Contents/Frameworks、Contents/Resources）
#   2. 把 libpng/libjpeg/libgif/libfreetype/libz 这些第三方 dylib 复制进去
#   3. 用 install_name_tool 把依赖改写成 @executable_path/../Frameworks/...
#      这样在没装 MacPorts/Homebrew 的机器上也能跑
#   4. 写 Info.plist
#   5. ad-hoc 签名（Apple Silicon 上未签名的二进制会被拒绝执行）
#
# 用法：
#   ./scripts/make-app.sh [Release|Debug] [游戏目录]
#   不带游戏目录时，app 内会放一个 game/ 占位说明，启动时提示拖拽游戏文件夹进来。

set -e

TYPE="${1:-Release}"
GAME_DIR="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build/$TYPE"
APP="$ROOT/build/PGM.app"

if [ ! -x "$BUILD/pgm-mac" ]; then
	echo "!! 找不到 $BUILD/pgm-mac，请先运行 ./scripts/build.sh $TYPE"
	exit 1
fi

echo ">> 清理 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"

# ---- 1. 主程序 ----------------------------------------------------------
cp "$BUILD/pgm-mac" "$APP/Contents/MacOS/PGM"
chmod +x "$APP/Contents/MacOS/PGM"

# ---- 2. 第三方 dylib ----------------------------------------------------
echo ">> 收集动态依赖"
DEPS=$(otool -L "$BUILD/pgm-mac" \
	| awk 'NR>1 {print $1}' \
	| grep -E '^/(opt|usr/local)/' || true)

for d in $DEPS; do
	base=$(basename "$d")
	# 只拷实文件，符号链接按真实文件处理
	real=$(readlink -f "$d" 2>/dev/null || echo "$d")
	cp "$real" "$APP/Contents/Frameworks/$base"
	chmod u+w "$APP/Contents/Frameworks/$base"
	echo "   + $base"
done

# ---- 3. 改依赖路径 ------------------------------------------------------
echo ">> 改写 install name"
for f in "$APP/Contents/Frameworks/"*.dylib; do
	[ -e "$f" ] || continue
	base=$(basename "$f")
	# 自己的 id
	install_name_tool -id "@executable_path/../Frameworks/$base" "$f" 2>/dev/null || true
	# 它对其它库的依赖
	for g in "$APP/Contents/Frameworks/"*.dylib; do
		[ -e "$g" ] || continue
		gb=$(basename "$g")
		old=$(otool -L "$f" | awk 'NR>1 {print $1}' | grep -E "/$gb\$" || true)
		[ -n "$old" ] && install_name_tool -change "$old" \
			"@executable_path/../Frameworks/$gb" "$f" 2>/dev/null || true
	done
done

# 主程序对所有库的依赖
for g in "$APP/Contents/Frameworks/"*.dylib; do
	[ -e "$g" ] || continue
	gb=$(basename "$g")
	old=$(otool -L "$APP/Contents/MacOS/PGM" | awk 'NR>1 {print $1}' \
		| grep -E "/$gb\$" || true)
	[ -n "$old" ] && install_name_tool -change "$old" \
		"@executable_path/../Frameworks/$gb" "$APP/Contents/MacOS/PGM" || true
done

# ---- 4. Info.plist ------------------------------------------------------
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>            <string>PGM</string>
	<key>CFBundleDisplayName</key>     <string>PGM-Mac</string>
	<key>CFBundleIdentifier</key>       <string>io.github.pgm-mac</string>
	<key>CFBundleVersion</key>          <string>0.1</string>
	<key>CFBundleShortVersionString</key><string>0.1</string>
	<key>CFBundlePackageType</key>      <string>APPL</string>
	<key>CFBundleExecutable</key>       <string>PGM</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>LSMinimumSystemVersion</key>   <string>11.0</string>
	<key>NSHighResolutionCapable</key>  <true/>
	<key>LSApplicationCategoryType</key><string>public.app-category.games</string>
	<key>CFBundleDocumentTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeName</key><string>PGM 游戏目录</string>
			<key>CFBundleTypeRole</key><string>Viewer</string>
			<key>LSItemContentTypes</key><array><string>public.folder</string></array>
		</dict>
	</array>
</dict>
</plist>
PLIST

# ---- 5. 可选：把指定游戏一起打进去 ---------------------------------------
if [ -n "$GAME_DIR" ]; then
	if [ ! -d "$GAME_DIR/bin" ]; then
		echo "!! $GAME_DIR 里没有 bin/，不是 PGM 游戏目录"
		exit 1
	fi
	echo ">> 打包游戏: $GAME_DIR"
	mkdir -p "$APP/Contents/Resources/game"
	cp -R "$GAME_DIR/bin" "$APP/Contents/Resources/game/bin"
	[ -d "$GAME_DIR/src" ] && cp -R "$GAME_DIR/src" \
		"$APP/Contents/Resources/game/src" || true
fi

# ---- 6. 签名 -----------------------------------------------------------
echo ">> ad-hoc 签名"
codesign --force --deep --sign - "$APP" 2>&1 | grep -v replacing || true

echo
echo "完成: $APP"
echo "运行: open \"$APP\"                # 双击"
echo "带游戏: open -a \"$APP\" --args /path/to/game"

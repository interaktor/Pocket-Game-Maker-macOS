#!/bin/sh
# export-app.sh — 把工程导成可双击运行的 .app
#
# 用法: export-app.sh <引擎二进制> <工程目录> <输出.app> [显示名]
set -e
ENGINE="$1"
GAME="$2"
APP="$3"
NAME="${4:-PGM Game}"

[ -x "$ENGINE" ] || { echo "找不到引擎: $ENGINE"; exit 1; }
[ -d "$GAME/bin" ] || { echo "$GAME 不是 PGM 工程"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$ENGINE" "$APP/Contents/MacOS/PGM"
chmod +x "$APP/Contents/MacOS/PGM"

# 收集第三方 dylib
DEPS=$(otool -L "$ENGINE" | awk 'NR>1 {print $1}' | grep -E '^/(opt|usr/local)/' || true)
for d in $DEPS; do
	base=$(basename "$d")
	real=$(readlink -f "$d" 2>/dev/null || echo "$d")
	cp "$real" "$APP/Contents/Frameworks/$base"
	chmod u+w "$APP/Contents/Frameworks/$base"
done

# 改写依赖
for f in "$APP/Contents/Frameworks/"*.dylib; do
	[ -e "$f" ] || continue
	base=$(basename "$f")
	install_name_tool -id "@executable_path/../Frameworks/$base" "$f" 2>/dev/null || true
	for g in "$APP/Contents/Frameworks/"*.dylib; do
		[ -e "$g" ] || continue
		gb=$(basename "$g")
		old=$(otool -L "$f" | awk 'NR>1 {print $1}' | grep -E "/$gb\$" || true)
		[ -n "$old" ] && install_name_tool -change "$old" "@executable_path/../Frameworks/$gb" "$f" 2>/dev/null || true
	done
done
for g in "$APP/Contents/Frameworks/"*.dylib; do
	[ -e "$g" ] || continue
	gb=$(basename "$g")
	old=$(otool -L "$APP/Contents/MacOS/PGM" | awk 'NR>1 {print $1}' | grep -E "/$gb\$" || true)
	[ -n "$old" ] && install_name_tool -change "$old" "@executable_path/../Frameworks/$gb" "$APP/Contents/MacOS/PGM" || true
done

# 打游戏
mkdir -p "$APP/Contents/Resources/game"
cp -R "$GAME/bin" "$APP/Contents/Resources/game/bin"
[ -d "$GAME/src" ] && cp -R "$GAME/src" "$APP/Contents/Resources/game/src"
rm -rf "$APP/Contents/Resources/game/PGMSAVEDATA"
find "$APP/Contents/Resources/game" -name '.DS_Store' -delete 2>/dev/null || true

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>CFBundleName</key><string>$NAME</string>
	<key>CFBundleDisplayName</key><string>$NAME</string>
	<key>CFBundleIdentifier</key><string>io.github.pgm-mac.game</string>
	<key>CFBundleVersion</key><string>1.0</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleExecutable</key><string>PGM</string>
	<key>LSMinimumSystemVersion</key><string>11.0</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>LSApplicationCategoryType</key><string>public.app-category.games</string>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP" 2>&1 | grep -v replacing || true
echo "完成: $APP"

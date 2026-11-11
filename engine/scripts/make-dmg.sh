#!/bin/sh
# 打包 PGM Studio.app 并做成 DMG 安装包
#
# 用法: ./engine/scripts/make-dmg.sh [输出路径.dmg]
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REL="$ROOT/build/Release"
APP="$REL/PGM Studio.app"
OUT="${1:-$ROOT/build/PGM-Studio.dmg}"

[ -x "$REL/pgm-studio" ] || { echo "!! 先编译: ./engine/scripts/build-studio.sh"; exit 1; }

echo ">> 组装 PGM Studio.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$REL/pgm-studio" "$APP/Contents/MacOS/PGM Studio"
cp "$REL/pgm-mac"    "$APP/Contents/MacOS/pgm-mac"     # 运行按钮要用

# 引擎依赖 libpng/libjpeg/libgif/libfreetype/libz（MacPorts 装在最前面），
# 一并打包并改写加载路径，否则到了没装 MacPorts 的机器上「运行」按钮起不来。
# 注意依赖是传递的（如 freetype → libbz2），要递归收集。
echo ">> 内置引擎依赖"
mkdir -p "$APP/Contents/Frameworks"
QUEUE=$(otool -L "$APP/Contents/MacOS/pgm-mac" | awk 'NR>1 {print $1}' \
	| grep -E '^/(opt|usr/local)/' || true)
while [ -n "$QUEUE" ]; do
	NEXT=""
	for d in $QUEUE; do
		base=$(basename "$d")
		[ -e "$APP/Contents/Frameworks/$base" ] && continue
		cp "$d" "$APP/Contents/Frameworks/$base"
		chmod u+w "$APP/Contents/Frameworks/$base"
		install_name_tool -id "@executable_path/../Frameworks/$base" \
			"$APP/Contents/Frameworks/$base" 2>/dev/null || true
		NEXT="$NEXT $(otool -L "$d" | awk 'NR>1 {print $1}' \
			| grep -E '^/(opt|usr/local)/' || true)"
	done
	QUEUE="$NEXT"
done
# 库与引擎里所有指向 /opt、/usr/local 的引用一律改写
for f in "$APP/Contents/Frameworks/"*.dylib "$APP/Contents/MacOS/pgm-mac"; do
	[ -e "$f" ] || continue
	otool -L "$f" | awk 'NR>1 {print $1}' | grep -E '^/(opt|usr/local)/' \
		| while read -r old; do
			install_name_tool -change "$old" \
				"@executable_path/../Frameworks/$(basename "$old")" "$f" \
				2>/dev/null || true
		done
done

cp "$ROOT/engine/scripts/export-iso.sh" "$APP/Contents/Resources/" 2>/dev/null || true
cp "$ROOT/engine/scripts/mkiso.py" "$APP/Contents/Resources/" 2>/dev/null || true
chmod +x "$APP/Contents/Resources/mkiso.py" 2>/dev/null || true
cp "$ROOT/engine/scripts/export-app.sh" "$APP/Contents/Resources/" 2>/dev/null || true
cp "$ROOT/engine/studio/Info.plist" "$APP/Contents/" 2>/dev/null || \
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>PGM Studio</string>
  <key>CFBundleDisplayName</key><string>PGM Studio</string>
  <key>CFBundleIdentifier</key><string>io.github.pgm-mac.studio</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>PGM Studio</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
</dict></plist>
PLIST

echo ">> 打包默认工程"
rm -rf "$APP/Contents/Resources/game"
mkdir -p "$APP/Contents/Resources/game"
cp -R "$ROOT/bin" "$ROOT/src" "$APP/Contents/Resources/game/"
rm -rf "$APP/Contents/Resources/game/PGMSAVEDATA"
find "$APP/Contents/Resources/game" -name '.DS_Store' -delete 2>/dev/null || true

# PSP ISO 模板（内置，用户不需要另下 CE）
TPL_SRC="$ROOT/engine/psp-template"
if [ -d "$TPL_SRC/PSP_GAME" ]; then
	echo ">> 内置 PSP 模板"
	rm -rf "$APP/Contents/Resources/psp-template"
	mkdir -p "$APP/Contents/Resources/psp-template"
	cp -R "$TPL_SRC/PSP_GAME" "$APP/Contents/Resources/psp-template/"
else
	echo "!! 没找到 PSP 模板，跳过（$TPL_SRC）"
fi

echo ">> 签名（ad-hoc）"
codesign --force --deep -s - "$APP" 2>/dev/null || true

echo ">> 生成分发包"
# 暂存目录：放 App + 指向 /Applications 的快捷方式，方便拖拽安装
STAGE="$ROOT/build/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -rf "$OUT"
if hdiutil create -volname "PGM Studio" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUT" >/dev/null 2>&1; then
	echo "完成: $OUT ($(du -h "$OUT" | cut -f1))"
else
	# 沙箱或权限环境下 hdiutil 不可用，退回 zip
	OUT="${OUT%.dmg}.zip"
	rm -f "$OUT"
	ditto -c -k --keepParent "$APP" "$OUT"
	echo "完成: $OUT ($(du -h "$OUT" | cut -f1))"
	echo "（hdiutil 不可用，已改为 zip；解压后把 PGM Studio.app 拖进「应用程序」）"
fi
rm -rf "$STAGE"

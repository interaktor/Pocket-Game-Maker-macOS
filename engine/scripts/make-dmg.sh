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
cp "$ROOT/engine/scripts/export-iso.sh" "$APP/Contents/Resources/" 2>/dev/null || true
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

echo ">> 签名（ad-hoc）"
codesign --force --deep -s - "$APP" 2>/dev/null || true

echo ">> 生成分发包"
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

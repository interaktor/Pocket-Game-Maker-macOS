#!/bin/sh
# 构建 PGM Studio（素材浏览器）
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/build/Release"
mkdir -p "$OUT"
clang -fobjc-arc -O2 \
	-framework Cocoa -framework ImageIO \
	-o "$OUT/pgm-studio" "$ROOT/engine/studio/main.m"
echo "完成: $OUT/pgm-studio"

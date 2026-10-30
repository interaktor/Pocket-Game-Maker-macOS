#!/bin/sh
# 双击运行游戏（或终端里 ./run.sh）
cd "$(dirname "$0")" || exit 1
for c in "$PGM_MAC_BIN" ./build/Release/pgm-mac ./build/Debug/pgm-mac; do
	[ -n "$c" ] && [ -x "$c" ] && exec "$c" .
done
echo "还没编译引擎。先运行一次："
echo "    ./scripts/build.sh Release"
echo
echo "或者双击「运行游戏.command」，它会自动编译。"
exit 1

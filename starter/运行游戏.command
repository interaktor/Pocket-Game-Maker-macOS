#!/bin/sh
#
# 双击运行（或在终端里 ./run.sh）。
#
# 会自动找到 pgm-mac 可执行文件。找不到就往下看提示。
#
cd "$(dirname "$0")" || exit 1

for c in \
	"$PGM_MAC_BIN" \
	../build/Release/pgm-mac \
	../build/Debug/pgm-mac \
	../pgm-mac/build/Release/pgm-mac
do
	[ -n "$c" ] && [ -x "$c" ] && exec "$c" .
done

echo "找不到 pgm-mac 可执行文件。"
echo
echo "请先到 pgm-mac 目录里构建一次："
echo "    cd pgm-mac && ./scripts/build.sh Release"
echo
echo "或者设置环境变量指向它："
echo "    PGM_MAC_BIN=/path/to/pgm-mac ./run.sh"
exit 1

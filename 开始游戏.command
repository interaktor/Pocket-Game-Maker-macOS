#!/bin/sh
# ←←← 双击这一个文件就够了 ←←←
#
# 它会自己检查引擎编没编译，没编译就先编译，然后直接开游戏。
cd "$(dirname "$0")" || exit 1

if [ ! -x build/Release/pgm-mac ]; then
	echo "======================================================"
	echo "  第一次运行，需要先编译引擎。请耐心等 1~2 分钟。"
	echo "  只需要这一次，以后都是秒开。"
	echo "======================================================"
	echo
	./engine/scripts/build.sh Release
	if [ ! -x build/Release/pgm-mac ]; then
		echo
		echo "编译失败了。把上面的报错截图发出来。"
		printf "按回车关闭..."; read -r _
		exit 1
	fi
	echo
	echo "编译完成，启动游戏。"
fi

exec ./build/Release/pgm-mac .

#!/bin/sh
# 双击：编译（如需要）并运行
cd "$(dirname "$0")" || exit 1
if [ ! -x build/Release/pgm-mac ]; then
	echo ">> 第一次运行，先编译引擎（需要一两分钟）"
	./scripts/build.sh Release || { echo; echo "编译失败，看上面的报错。按回车关闭。"; read -r _; exit 1; }
fi
exec ./build/Release/pgm-mac .

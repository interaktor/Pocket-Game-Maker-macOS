#!/bin/sh
# 双击：从骨架生成一个新工程
cd "$(dirname "$0")" || exit 1
printf "新游戏叫什么名字？ "
read -r NAME
[ -z "$NAME" ] && { echo "没输入名字，退出"; read -r _; exit 1; }
if [ ! -x build/Release/pgm-mac ]; then
	echo ">> 先编译引擎（需要一两分钟）"
	./scripts/build.sh Release || { echo "编译失败"; read -r _; exit 1; }
fi
./scripts/new-project.sh "$NAME" || exit 1
echo
echo "按回车关闭这个窗口。"
read -r _

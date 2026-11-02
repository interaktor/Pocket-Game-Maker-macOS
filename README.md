# PGM for Mac

Pocket Game Maker 是白枫（掌机开发者之家）做的 PSP 文字游戏引擎，最初是为了做类似
逆转裁判的游戏。原版只支持 PSP / Windows / Android。

这个项目把引擎移植到 macOS，让 PGM 做的游戏能在 Mac 上直接运行。

## 运行

双击 `开始游戏.command`。

第一次会先编译引擎，需要一两分钟，之后直接开。

## 目录

```
bin/data/bgm/        背景音乐（mp3 / wav）
bin/data/sound/      音效
bin/data/voice/      语音
src/user/main.ev     剧本
src/files/bg/        背景图
src/files/fg/        立绘
src/system/          框架脚本，不要动
engine/              引擎源码
```

图片 480x272，立绘可带透明通道。文件名写进剧本就行，放在哪个子目录都能找到。

## 写台词

一句台词两行：

```
text("你好。")
textcl()
```

带人名：

```
text("旁白","这样写就是带名字的。")
textcl()
```

`textcl()` 不能漏，漏了下一句会接在同一行。

选项：

```
drawramus("选项一",*a,"选项二",*b)
```

对话框位置、每行字数在 `src/user/config.lua` 里调，有中文注释。

## 运行其他 PGM 游戏

```sh
./build/Release/pgm-mac /path/to/游戏目录
```

带 `gmcode.bin` / `gmdata.bin` 封包的原版游戏可以直接读；没有封包时读散装 `src/` 目录。

## 编译

```sh
brew install libpng jpeg-turbo giflib freetype
./scripts/build.sh Release
```

## 许可

BSD 3-Clause。代码里原有的 GPL v2+ 文件头是 libnge2 当年的模板残留，作者已确认按 BSD 处理。

`src/system/` 下的框架脚本版权归白枫，授权情况见 `docs/LICENSING.md`。

## 致谢

白枫（掌机开发者之家）、Kun Wang（libnge2）、History-exe（PGM 原版与 CE 的维护）

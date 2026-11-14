# PGM for Mac

把 Pocket Game Maker（白枫 / 掌机开发者之家 的 PSP 视觉小说引擎）移植到 **macOS 原生**。

配套一个图形化工作台 **PGM Studio**：不用命令行，不用改配置文件，双击就能做游戏。

## 两种用法

**只想玩 / 只想做游戏** → 下载 Releases 里的 `PGM-Studio.zip`，解压后把 App 拖进「应用程序」，双击打开。

**想要源码 / 想自己编译** → 继续往下看。

## 从源码编译

```sh
brew install libpng jpeg-turbo giflib freetype
./engine/scripts/build.sh Release        # 引擎
./engine/scripts/build-studio.sh         # 工作台
./engine/scripts/make-dmg.sh             # 打成可分发的包
```

## 目录

```
bin/       运行时：音乐、音效、语音、字体
src/       你的游戏：剧本、图片、框架脚本
engine/    引擎与工具源码（不用改）
教程.md     怎么用
```

## 许可

MIT。PGM 作者白枫、libnge2 作者 Kun Wang 均已同意。


## 致谢

白枫（掌机开发者之家）、Kun Wang（libnge2）、History-exe（PGM 原版与 CE）

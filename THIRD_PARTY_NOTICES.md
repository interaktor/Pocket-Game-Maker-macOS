# 第三方组件

本项目自身按 MIT 发布（见 `LICENSE`）。运行时与构建时用到的第三方组件如下，
各自保留其原始许可。

## 随程序分发

`export-app.sh` / `make-dmg.sh` 会把引擎依赖的动态库复制进 `.app/Contents/Frameworks/`：

| 组件 | 版本 | 许可 |
|---|---|---|
| [Lua](https://www.lua.org/) | 5.1.4 | MIT |
| [libnge2](https://github.com/NomadaLex/libnge2) | — | BSD（Kun Wang） |
| [libpng](http://www.libpng.org/) | 1.6.x | libpng License |
| [libjpeg-turbo](https://libjpeg-turbo.org/) | 3.x | IJG / BSD-3 / zlib |
| [giflib](https://sourceforge.net/projects/giflib/) | 5.x | MIT |
| [FreeType](https://freetype.org/) | 2.x | FTL 或 GPLv2（本项目按 FTL） |
| [zlib](https://zlib.net/) | 1.3.x | zlib License |

## 仅构建时需要

CMake、clang（Xcode Command Line Tools）、Python 3。

## 游戏内容

`bin/data/font/fz.ttf` 与 `bin/data/system/` 下的示例音效来自 Pocket Game Maker
原版发行包；`src/system/` 下的 Lua 框架脚本是 PGM 引擎本体的一部分。
版权归 白枫 / 掌机开发者之家，按 MIT 处理，详见 `NOTICE.md`。

`bin/data/bgm/` 与 `bin/data/sound/` 的音效为本项目自制，随 MIT 授权。

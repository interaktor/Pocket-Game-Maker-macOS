# 署名

这个项目不是从零开始的，建立在三个前人成果上：

## Pocket Game Maker
白枫 / 掌机开发者之家。PSP 上的 AVG 引擎，基于 NGE2 + Lua 5.1。

- https://github.com/History-exe/Pocket-Game-Maker-v0.83
- https://github.com/History-exe/PGM_CE

宿主层源码从未公开，本项目按行为重新实现了封包解码、Lua API 绑定和 `.ev` 解释器。

## libnge2
Kun Wang <ifreedom.cn@gmail.com>，BSD 许可。本项目为它新增了 macOS 后端。

- https://github.com/NomadaLex/libnge2

## History-exe
维护 PGM 原版与 CE 版本，写了中文教程。

---

`src/system/` 下的框架脚本版权归白枫。

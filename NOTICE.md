# 署名与版权声明 / Attribution Notice

本项目（**PGM-Mac**）是把 PSP 时代的自制文字游戏引擎 **Pocket Game Maker (PGM)**
移植到 macOS 的工作。它不是从零开始的原创项目，而是站在三个前人的成果之上。

This project is a macOS port of Pocket Game Maker (PGM) and derives from the
work of the people listed below.

---

## 1. Pocket Game Maker (PGM) —— 引擎与游戏框架

* **作者**：白枫 / 掌机开发者之家
* **原始形态**：PSP 上的 AVG / 视觉小说引擎，基于 NGE2 + Lua 5.1
* **来源**：
  * <https://github.com/History-exe/Pocket-Game-Maker-v0.83>（原始 v0.83）
  * <https://github.com/History-exe/PGM_CE>（PGM_CE 魔改版）

PGM 的**引擎宿主层**（`LuaLibs.cpp` / `MyGame.cpp` / `PGMap.cpp` /
`amp_package.cpp`）从未公开发布源码，磁盘上只有 Windows / PSP / Android 的
二进制。因此本项目的宿主层（Lua C API 绑定、封包读写、场景系统）是**依据
PGM 自带的 Lua 框架与公开的 `PGM指令表v0.7.txt` 重新实现**的，属于独立实现，
不是对原二进制的反编译或复制。

所有 PGM 游戏的内容（脚本、图片、字体）版权归各自游戏的原作者所有，
本项目既不包含也不分发任何游戏资源。

## 2. NGE2 —— 底层多媒体引擎

* **作者**：Kun Wang \<ifreedom.cn@gmail.com\>
* **来源**：<https://github.com/yydaor/libnge2>
* **许可证**：见 `docs/LICENSING.md`（上游自述为 BSD，源文件头却多为 GPL v2+，
  本项目按两者中更严格的 GPL-2.0-or-later 处理）

本项目的 `third_party/libnge2/` 是对其源码的**修改版**，修改内容包括新增
macOS (NGE_MAC) 平台后端以及若干移植性修复，逐条记录在
`docs/PORTING-NOTES.md`。

## 3. PGM_CE —— Lua 侧的魔改框架

* **作者**：History_exe
* **来源**：<https://github.com/History-exe/PGM_CE>
* **作用**：提供了更完整的 Lua 场景框架（存档、历史回顾、CG 模式、设置菜单等），
  本项目把它作为开发与回归测试的基线内容。

---

## 4. 本项目

* **PGM-Mac 移植**：见 `README.md` 中的作者信息。
* **许可证**：GPL-2.0-or-later（见 `LICENSE`），原因见 `docs/LICENSING.md`。

## 商标与产品名

PSP、PlayStation Portable 是 Sony Interactive Entertainment 的商标。
本项目与 Sony 无任何关联。文件名中出现 "PSP" 仅用于说明来源平台。

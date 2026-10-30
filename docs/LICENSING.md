# 许可证分析 / Licensing analysis

> **TL;DR** — 上游 `libnge2` 的许可证自相矛盾：README 写 BSD，但 43 个源文件头
> 写的是 GPL v2+。本项目采用 **GPL-2.0-or-later**，因为这是**在两种解释下都成立**
> 的唯一选择。发布前请阅读第 3 节的选项。

## 1. 事实

对 `third_party/libnge2/` 的全部 `*.c` / `*.h` / `*.cpp` 做了逐个扫描：

| 文件头声明 | 数量 |
|---|---|
| GNU General Public License v2 or later | **43** |
| BSD（"Redistribution and use in source and binary forms"） | 10（多为 `net/`，源自 libevent） |
| 无任何许可证声明 | 117 |

而 `README.md` 第 10 行明确写着：

> NGE2 v2.1采用BSD许可证。

冲突点是具体的：`src/nge_graphics.c`、`include/nge_input.h`、`include/libnge2.h`
等**核心文件**都带完整的 GPL v2+ 段落（"either version 2 of the License, or
(at your option) any later version"），而 `README.md` 说 BSD。

## 2. 为什么选 GPL-2.0-or-later

设两种可能的世界：

* **若 BSD 才是作者真意**：BSD 允许再许可（sublicense）为 GPL。把 BSD 代码
  放进 GPL 工程是完全合规的。
* **若 GPL v2+ 才是有效条款**：那么衍生作品必须整体以 GPL v2+ 分发。

也就是说，**GPL-2.0-or-later 在两种解释下都站得住，BSD 只在第一种下站得住。**
对一个要公开发布的移植工程，这是唯一不需要赌的选择。

## 3. 如果你想改成 BSD / MIT

可以，但需要先解决第 1 节的冲突，二选一：

1. **联系作者确认**（最干净）。NGE2 作者 Kun Wang 的邮箱在几乎所有源文件头里：
   `<ifreedom.cn@gmail.com>`。请他书面确认「NGE2 v2.1 以 BSD 授权，源文件里的
   GPL 段落是模板遗留」。拿到确认后，把 `LICENSE` 换成 BSD-3-Clause，并在
   `NOTICE.md` 里记录这次确认。
2. **只保留 `net/` 的 BSD 部分，其余按 GPL**。这种做法在法律上很别扭，
   不推荐。

在拿到作者确认之前，请**不要**把 `LICENSE` 改成 BSD —— 那会让仓库处在一个
自相矛盾的状态，别人 fork 也会有同样的疑问。

## 4. 完全没有争议的部分

以下文件是**本项目原创**的，版权归本项目作者，可以按任何许可证发布
（目前为了整体一致性也放在 GPL-2.0-or-later 下）：

* `src/mac/nge_mac_window.m`、`src/mac/nge_mac.h`（macOS 后端）
* `src/mac/nge_mac_audio.c`（CoreAudio 后端，P4 阶段）
* `scripts/apply_mac_patches.py`
* `tests/`
* 以及后续 P2–P5 的 PGM 宿主层（`src/pgm_*.c`）

## 5. 游戏内容

PGM 游戏（例如用 PGM_CE 移植的《逆熵 Anti-Entropy》）的**内容**版权归原作者。
本仓库**不包含任何游戏资源**，`examples/` 下只放用于自动化测试的合成素材。

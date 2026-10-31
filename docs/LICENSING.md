# 许可说明

## 结论

本项目按 **BSD 3-Clause** 发布。

## 依据：作者本人的明确答复

2026-10-30，libnge2 作者 **Kun Wang \<ifreedom.cn@gmail.com\>** 回信确认：

> 嗯，那的确可能是当时文件模板的问题。你按 BSD 许可证处理就行。
>
> 时间真的很久远了，有很多记忆已经模糊，也很感谢你愿意继续改进它。
>
> 因为我的 GitHub 改过一次名字，现在的代码库地址是
> https://github.com/NomadaLex/libnge2 ，如果你希望的话，我也可以解除库的
> 归档状态并把你加进来，你可以直接修改。

也就是说：

- **BSD 是作者本人的意愿**，源码里那些 GPL v2+ 文件头是当年的模板残留
- libnge2 原始仓库在 `https://github.com/NomadaLex/libnge2`（不是之前以为的 `yydaor/libnge2`）
- 作者愿意解除归档并把贡献者加成 collaborator

## 之前为什么选了 GPL

在拿到答复之前，仓库内容有两种互相矛盾的信号：

| 来源 | 说法 |
|---|---|
| `README.md` | BSD |
| 43 个源文件的文件头 | GPL v2 or later |

在不知道哪个是真的情况下，GPL-2.0-or-later 是唯一在两种读法下都成立的选项
（GPL v2+ 项目可以按 BSD 授权，反过来不行）。现在作者确认了，就不需要这种
保守选择了。

## 各部分的版权归属

| 部分 | 版权 | 许可 |
|---|---|---|
| `engine/host/` — PGM 宿主层（自写，约 3800 行） | 本项目贡献者 | BSD-3-Clause |
| `engine/third_party/libnge2/` — 引擎 | Kun Wang | BSD（作者确认） |
| `engine/third_party/lua-5.1.4/` — Lua | Lua.org / PUC-Rio | MIT |
| `src/system/`、`bin/engine.sys` 等 PGM 框架脚本 | 白枫 / 掌机开发者之家 | **未确认**，见下 |

## 仍未确认的一项

`src/system/` 下的 40 个 Lua 脚本、`bin/engine.sys`、`src/pubdata.ev` 属于
**PGM 本体**，作者是白枫（掌机开发者之家），不是 Kun Wang。这部分是运行任何
PGM 游戏都必需的框架，随引擎一起分发。

目前没有白枫本人对这部分代码的许可声明。Kun Wang 在回信里提到他有白枫的微信、
可以帮忙联系。如果你能通过掌机开发者之家的群或者 Kun Wang 联系上白枫，
建议照同样的方式问一句。

在此之前，这些文件保持原样分发并保留原作者署名（见 `NOTICE.md`），与 GitHub 上
其他 PGM 移植项目的做法一致。

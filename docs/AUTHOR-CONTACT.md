# 联系 NGE2 作者 / Contacting the NGE2 author

**目的**：确认 NGE2 的授权到底是 BSD 还是 GPL v2+，以便决定 PGM-Mac 能否改用
BSD-3-Clause 发布。**这件事不阻塞发布** —— 在收到回复之前，本项目按
GPL-2.0-or-later 发布，这在两种解释下都合规（见 `LICENSING.md` 第 2 节）。

**状态**：待发送 / 待回复

---

## 联系方式

| 渠道 | 地址 | 说明 |
|---|---|---|
| 邮箱 | `ifreedom.cn@gmail.com` | 几乎每个源文件头里都有。2011–2012 年的地址，**可能已失效** |
| GitHub Issue | <https://github.com/yydaor/libnge2/issues> | 目前仍在的 libnge2 镜像仓库，公开提问，回复可见 |
| GitHub 用户 | <https://github.com/ifreedom> | 作者原始账号名 |

> 建议**两条都发**：GitHub 公开 issue 更容易被搜到，也不依赖旧邮箱还活着。

---

## 邮件草稿（中文）

**主题**：关于 libnge2 (NGE2) 许可证的确认请求 —— 从 PSP 移植到 macOS

```
Kun Wang 老师，您好：

我是一名开发者，正在做一个开源项目：把 PGM（Pocket Game Maker，白枫开发的
PSP AVG 引擎）移植到 macOS 上，让 Mac 用户能直接运行现成的 PGM 游戏。

PGM 的底层引擎是您的 NGE2。我在 github.com/yydaor/libnge2 上找到了源码，
它可以在 macOS 上编译（我在 include/nge_platform.h 里发现您已经预留了
NGE_MAC 宏，只是从未实现；我补上了 Cocoa + NSOpenGL 后端）。

我想向您确认一个许可证问题。我看到的情况是：

  1. README.md 第 10 行写着：「NGE2 v2.1采用BSD许可证。」
  2. 但 src/ 和 include/ 下有 43 个源文件的文件头写的是：
     "This program is free software; you can redistribute it and/or modify
      it under the terms of the GNU General Public License as published by
      the Free Software Foundation; either version 2 of the License, or
      (at your option) any later version."
  3. net/ 下有 10 个文件是 BSD（源自 libevent）。

两者有冲突。为了稳妥，我目前把项目整体按 GPL-2.0-or-later 发布——因为在
"BSD 为真" 的解释下，BSD 允许再许可为 GPL，所以 GPL 两种情况下都成立。

不过如果 NGE2 的本意确实是 BSD（就像 README 说的那样），我希望能在项目里
正确地以 BSD-3-Clause 发布，这样对使用者的限制更少。所以想请您确认一句：

  NGE2 v2.1（以及 libnge2 仓库里的代码）是以 BSD 许可证授权的吗？
  源文件头里的 GPL 段落，是早期模板遗留下来的吗？

如果确实是 BSD，回复一句确认即可，我会把您的确认记录在项目的 NOTICE 里。

另外，如果您不希望我分发修改版，或者有其它要求，也请告诉我，我会照办。

非常感谢您当年写下 NGE2 —— 十几年后它仍然是这些 PSP 视觉小说能跑起来的
基础。期待您的回复。

此致
<你的名字>
<你的 GitHub 地址>
```

---

## GitHub Issue 草稿（英文，发到 yydaor/libnge2）

**标题**：License clarification: BSD (per README) vs GPL-2.0-or-later (per file headers)

```
Hello,

I'm porting Pocket Game Maker (PGM, the PSP AVG engine by 白枫) to macOS, and
PGM sits on top of NGE2. I found this repo, and to my surprise
`include/nge_platform.h` already reserves a `NGE_MAC` macro — it was declared
but never implemented. I've added a Cocoa + NSOpenGL backend and got the
engine rendering correctly on Apple Silicon.

Before publishing, I need to clarify the license, because I see a conflict:

1. `README.md` says: "NGE2 v2.1采用BSD许可证" (NGE2 v2.1 uses the BSD license).
2. But 43 files under `src/` and `include/` carry the full GNU GPL v2-or-later
   header ("either version 2 of the License, or (at your option) any later
   version").
3. 10 files under `net/` are BSD (libevent-derived).

Right now I'm publishing under GPL-2.0-or-later, which is compliant under both
readings (BSD permits sublicensing under GPL). But if BSD was the intent, I'd
prefer to ship BSD-3-Clause to place fewer restrictions on users.

Could you confirm: is NGE2 v2.1 / libnge2 licensed under BSD, with the GPL
headers being leftover boilerplate?

If BSD is confirmed, I'll record your confirmation in the project's NOTICE file.
And if you'd rather I not distribute a modified version at all, please say so
and I'll respect that.

Thanks for writing NGE2 — fifteen years on, it's still what makes these PSP
visual novels run.

<your name> / <your GitHub handle>
```

---

## 收到回复后怎么做

**情况 A —— 作者确认 BSD**

1. `LICENSE` 换成 BSD-3-Clause 全文
2. `NOTICE.md` 第 2 节改为「BSD-3-Clause，已获作者 `<日期>` 邮件确认」
3. `docs/LICENSING.md` 第 3 节标记为已解决，附上回复原文摘要
4. 提交信息：`license: switch to BSD-3-Clause (confirmed by NGE2 author)`

要改的就是这 3 个文件，10 分钟的事。

**情况 B —— 作者说其实是 GPL / 没回复 / 邮箱退信**

什么都不做。GPL-2.0-or-later 本来就是当前状态，继续发布。

**情况 C —— 作者说「不要分发修改版」**

这需要认真对待。届时的选项：
- 不做 macOS 移植的分发（但你已经投入了很多）
- 或者把移植层做成「运行时打补丁」，不直接分发 libnge2 的修改源码
  （法律上更绕，需要单独评估）

如果真走到 C，再来告诉我，我们重新设计分发方式。

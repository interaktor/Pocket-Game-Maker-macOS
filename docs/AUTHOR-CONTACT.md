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

---

# 第二封：回复 Kun Wang（2026-10-30 收到回信后）

他的回信里给了三件事：BSD 可以直接用、仓库实际地址是 `NomadaLex/libnge2`、
愿意解除归档并把贡献者加成 collaborator。

## 回信草稿

> Kun Wang 老师，您好：
>
> 收到回信，太感谢了 —— 十几年后还能得到作者本人的确认，对我来说挺不寻常的。
>
> 我按您说的把项目许可证改成了 BSD 3-Clause，并在 `docs/LICENSING.md` 里记下了
> 您的答复作为依据。之前之所以选了 GPL，是因为 README 写 BSD、但 43 个源文件的
> 文件头写 GPL v2+，在不知道哪个是真实意图的情况下 GPL-2.0-or-later 是唯一
> 两种读法都成立的选项。现在清楚了，那些文件头是模板残留。
>
> 关于您提到解除归档、把我加进来 —— 我很愿意，但想先说清楚我打算做什么，
> 免得帮倒忙：
>
> 我做的是给 libnge2 新增一个 macOS 后端（`NGE_MAC`）。`nge_platform.h` 里其实
> 早就声明了这个平台宏，但一直没有实现。我补的部分是：
>
> - `src/mac/nge_mac_window.m` — Cocoa + NSOpenGLView 窗口与上下文
> - `coolaudio/nge_audio_mac.m` — AVFoundation 音频后端（mp3 / wav / aac）
> - 若干平台判断和 `nge_sleep` 单位问题的修正
>
> 除此之外的东西（PGM 的宿主层、封包解码、脚本解释器）是 PGM 特有的，不适合
> 放进 libnge2，所以那些我留在自己的项目里。
>
> 想请教您希望我以什么方式提交：
>
> 1. 开一个分支 + PR，您 review 后合并
> 2. 还是直接推到一个新分支，您自己看着办
>
> 我倾向第一种，稳妥一些。
>
> 另外还有一件小事想麻烦您：这个移植还需要 PGM 的框架脚本（`src/system/` 下
> 40 个 Lua、`engine.sys`），那部分是白枫老师的，我有原版的代码但这个仓库里
> 没有明确的许可声明。您提到有他的微信 —— 如果不麻烦的话，能不能帮我把这个
> 问题转达一下？如果他有微信或者群里的联系方式愿意给我，我直接问也可以。
>
> 再次感谢。
>
> Best Regards,
> コトヱ

## 他解除归档之后，具体要做什么

1. **接受邀请** —— 会收到 GitHub 邮件，或者在
   <https://github.com/NomadaLex/libnge2/invitations> 点 Accept。
   没看到邮件就去通知页看。

2. **克隆原始仓库**，不要把自己的整个项目推上去：

   ```sh
   git clone git@github.com:NomadaLex/libnge2.git
   cd libnge2
   git checkout -b macos-backend
   ```

3. **只放 macOS 后端相关的文件进去**：

   | 文件 | 动作 |
   |---|---|
   | `src/mac/nge_mac_window.m` | 新增 |
   | `src/mac/nge_mac.h` | 新增 |
   | `coolaudio/nge_audio_mac.m` | 新增 |
   | `include/nge_platform.h` | 改：`__APPLE__` → `NGE_MAC` 判断（注意 `TARGET_OS_IPHONE` 在 macOS 上是 0，不能只写 `defined`） |
   | `include/nge_misc.h` | 改：`nge_sleep` 毫秒 → 微秒 |
   | `include/nge_common.h` | 改：`__OBJC__` 下别重复 typedef `BOOL` |
   | `include/nge_input.h` | 改：`NGE_MAC` 的 `PSP_BUTTON_*` 定义 |
   | `src/nge_graphics.c` | 改：`ScreenToImage` 的 `GL_PACK_ROW_LENGTH`；macOS 分支 |
   | `CMakeLists.txt` | 改：`if(APPLE)` 块，`enable_language(OBJC)` + 三个 framework |

4. **别碰** `src/mac/` 之外跟 PGM 有关的东西。上游仓库不需要它们。

## 几个容易踩的点（写进 PR 说明里会显得专业）

- `TARGET_OS_IPHONE` 在 macOS 上定义为 **0**，所以 `#if defined TARGET_OS_IPHONE`
  会把 macOS 误判成 iOS。必须写成 `#if defined TARGET_OS_IPHONE && TARGET_OS_IPHONE`。
- `nge_sleep(tick)` 上游实现是 `usleep(tick)`，但调用方传的是毫秒 —— 实际会让引擎
  跑成 300fps 而不是 60fps。改成 `usleep((tick)*1000)` 后实测 300 帧耗时 5.01 秒。
- macOS 10.14+ 强制 layer-backing，`NSOpenGLContext setView:` 挂在普通 `NSView`
  上只会得到一个透明壳子，必须用 `NSOpenGLView` 子类。
- 不要调 `-[NSApplication run]`，改成每帧
  `nextEventMatchingMask:` + `sendEvent:` + `CFRunLoopRunInMode` 泵一次。

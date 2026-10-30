# 宿主层实现进度

记录 `src/` 下 PGM 宿主层的现状，便于继续开发。

## 已实现（真实逻辑）

| 文件 | 内容 |
|---|---|
| `pgm_main.c` | 启动链、主循环（PGLoop 驱动）、帧率限制、截图 |
| `pgm_lua.c` | Lua 5.1 状态、脚本加载、错误报告 |
| `pgm_pack.c` | **两种封包读取**：gmcode.bin（脚本，按行 + XOR + anti-NUL）、gmdata.bin（资源，原样）；以及明文 src/ 目录回退 |
| `pgm_gfx.c` | 视频初始化、image/font/timer 的 userdata 包装与 API、屏幕截图 |
| `pgm_escript.c` | **.ev 事件脚本解释器**（按行当作 Lua 执行，goto/gotoif 用物理行号） |
| `pgm_api.c` | 系统类 API、常量、场景合成层 `am_scene_render`/`am_scene_update` |

## 关键实现要点

* **.ev 就是文本**，一行一条语句，且每行本身合法 Lua 5.1 代码。解释器只需
  `luaL_loadbuffer(line)` + `pcall`。物理行号必须与 `goto` 的目标一致，空行/注释行占位。
* **`EScriptJump(s, label)` 要设成 `label - 1`**：Lua 侧在 `EScriptDoline` 之后
  总会再调一次 `EScriptNext`，直接设成 `label` 会落到 `label+1`。
* **`am_scene_render()`**：`am_scene` 里 `bg`/`texfg`/`fg`/`ani` 四组对象各自实现了
  `render()`/`update()`，按这个层序依次调用即可。
* image / font / timer 都用 Lua userdata + `__gc` 包装，避免泄漏。

## 当前状态：对话文本已在屏幕上渲染

```
视频: 480x272 full=0 "PocketGameMaker-ConvertedEdition-"
Init Graphics Ok
进入主循环 (PGLoop)，帧数上限=150
主循环结束，共 150 帧          <- 0 个 Lua 错误
```

跑 `first.ev` 的 `text("Hello, PGM.")`，屏幕左下角正确显示出 **Hello, PGM.**
（见 `docs/images/p3-dialog-render.png`）。整条链路已经打通：

```
gmcode.bin 解包 -> .ev 逐行执行 -> text() -> DialogCreate 解析
   -> SpeakScene 状态机 -> FontDraw -> freetype 光栅化 -> OpenGL 上屏
```

300 帧、0 错误。此时只剩 2 个未实现的桩（`CacheImageLoad` / `CacheClear`），
且都已用别名实现。

## 重要澄清：场景合成层是 Lua 实现的

`globals.lua:81` 自己定义了 `am_scene_render()`，会覆盖宿主注册的原生同名函数。
它的实现是逐层调用 `am_scene.bg[i]:render()` / `fg[i]:render()` / `ani[i]:render()`
/ `texfg[i]:render()`，最后 `text_layer_render()` 与 `am_ramus_render()`。

**所以 `src/pgm_api.c` 里那个 C 版 `am_scene_render` 实际上是死代码**
（注册了但立刻被 Lua 定义覆盖）。调试时用 `PGM_TRACE_SCENE=1` 看不到任何输出，
不是 bug。若要保留 C 版，需要改名或不注册。

## 消息框不显示的排查进展

`msgboxon()`（cefunctions.lua:47）把消息框当作 **FG 精灵 #10**：

```lua
textlen(MSGTEXT_LINELEN); textline(MSGTEXT_LINEMAX); textxy(MSGTEXT_DX,MSGTEXT_DY)
fgnull(MSGBOX_NUM)
_fg(MSGBOX_NUM, MSGBOX, 1, time, IMG_8888)   -- 加载 msgbox01.png
fgxy(MSGBOX_NUM, MSGBOX_DX, MSGBOX_DY)
fgon(MSGBOX_NUM)                             -- display = true
```

`FGBase:render()` 的两个提前返回条件：

```lua
if not self.display then return end
if not self.image_p[self.image_index+1] then return end
```

已确认 `msgbox01.png` 确实在 `gmdata.bin` 里（off=0x1e3fbc, size=2771, 合法 PNG），
也确认 `fgon()` 会设 `display=true`。

**关键线索**：给 `ImageLoad` 加上 `PGM_TRACE_IMG=1` 追踪后，跑 30 帧**一次都没有
被调用**。也就是说 `FGBase:load()` 根本没走到 `CacheImageLoad`。
下一步应该顺着 `FGBase:load` 的 `fadein` 分支查：

```lua
elseif num==am_effect.fadein then
    if self.image_p[self.image_index+1] then   -- 首次加载时这里是 false
        ...
```
即确认走的是哪个分支、`self.image_index` 初值、以及 `event[255]` 的取值。
注意 `globals.lua` 里 `event = {}`，`event[255]` 是 nil，而代码写的是
`if event[255] == 0 then ... elseif event[255] == 1 then ... end` ——
**两者都不匹配时 `image_p` 不会被赋值**，这很可能就是根因。

## 下一步

1. **消息框与背景图没有绘制** —— 目前只有文字，没有 `msgbox01.png` 底板和背景。
   需要在场景合成里补上 msgbox 的绘制（`SpeakScene` 里靠原生层画）。
2. **对话推进验证** —— 文本显示后停在等按键状态（这是对的）。已加
   `PGM_MAC_AUTOKEY=N` 每 N 帧模拟一次确认键用于自动化推进，但按键到推进的
   状态机还没完全验证。
3. **中文字形** —— `first.ev` 第 10 行 `text("[c=FF0000]红[/c][c=00FF00]绿[/c]...")`
   用的 GBK 双字节，尚未在画面上确认。
4. 存档读写（`PGMSAVEDATA` + `amp_pubsave`/`amp_pubload`）、音频（CoreAudio）。

## 调试开关

| 环境变量 | 作用 |
|---|---|
| `PGM_MAC_FRAMES=N` | 只跑 N 帧后退出（0/缺省 = 一直跑） |
| `PGM_MAC_SHOT=path.png` | 退出前抓一帧存 PNG |
| `PGM_MAC_DEBUG_WINDOW=1` | 每秒打印一次 AppKit 窗口状态（P1 遗留） |
| `PGM_MAC_AUTOKEY=N` | 每 N 帧模拟一次确认键（推进对话） |
| `PGM_TRACE_IMG=1` | 打印每次 ImageLoad 的名字与结果 |
| `PGM_TRACE_ES=1` | 打印每次 EScriptJump 的参数 |
| `PGM_TRACE_SCENE=1` | 场景合成层追踪（注意 C 版已被 Lua 覆盖） |

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

## 当前状态：完整对话画面（消息框 + 文字 + 等待图标）已渲染

```
视频: 480x272 full=0 "PocketGameMaker-ConvertedEdition-"
Init Graphics Ok
进入主循环 (PGLoop)，帧数上限=150
主循环结束，共 150 帧          <- 0 个 Lua 错误
```

跑 `first.ev`，屏幕上正确显示出 **圆角消息框 + "Hello, PGM." + 右侧闪烁的等待图标**
（见 `docs/images/p3-msgbox.png`）。整条链路已经打通：

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

## 消息框不显示 —— 已解决

根因是 **`EScriptBack()` 的语义**。`run()` 创建脚本后会立刻调用它：

```lua
function run(file)
    am_script.stackCount = am_script.stackCount + 1
    am_script[am_script.stackCount] = CacheEScriptCreate(am_pack.script, file)
    EScriptBack( am_script[am_script.stackCount] )
end
```

而 `FrameEvScriptUpdate` 在 `EScriptDoline` 之后**总会**再调一次 `EScriptNext`。
所以 `EScriptBack` 必须允许 `cur` 减到 **0**：

```
cur: 1 --Back--> 0 --Next--> 1     => 下一帧从第 1 行开始
```

如果像原来那样把 `cur` 卡在 1，Next 会把它推到 2，**每个脚本的第 1 行都会被静默跳过**。
`first.ev` 恰好第 1 行就是 `msgboxon()`，于是消息框永远不加载。这个 bug 很隐蔽：
没有报错、没有 stub 日志，只是第一行不见了。

修好之后 `msgbox01.png` 正常从 `gmdata.bin` 加载并绘制。

### 之前的排查记录（已排除）



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

曾经怀疑过 `event[255]`，但 `globals.lua` 的初始化循环
`for i=1,TABLE_EVENT_MAX do event[i] = v end` 已把它置 0，不是问题。
`FGBase:load` 的 `fadein` 分支确实会调 `CacheImageLoad`，路径本身没问题 ——
问题在更上游：那个 `load()` 根本没被调用。

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

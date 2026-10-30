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

**所以 `engine/host/pgm_api.c` 里那个 C 版 `am_scene_render` 实际上是死代码**
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

## 彩色中文与文本层清空（已解决）

`first.ev` 第 10 行 `text("[c=FF0000]红[/c][c=00FF00]绿[/c][c=0000FF]蓝[/c]")`
现在能正确渲染成**红/绿/蓝三色中文**（见 `docs/images/p3-colored-text.png`）。

踩到的两个坑：

1. **推进对话的是 CIRCLE 键，不是 CROSS**。`SpeakScene:KeyDown` 里
   `PSP_BUTTON_CIRCLE` 才是"下一句"，`PSP_BUTTON_CROSS` 映射到 `drawhide()`
   （隐藏对话框）。自动化按键要用 CIRCLE。
2. **`ImageClear`（大写 C）没实现**。`DialogLayer:clear()` 调的是
   `ImageClear(self.quad[i])`，而我们只注册了 `ImageCreate/ImageLoad/ImageFree/
   ImageGetW/ImageGetH/ImageClone/ImageSetMask`。缺了它文本层永远不清空，
   上一句会和下一句叠在一起（截图上表现为 `红绿蓝` 后面残留 `lo, PGM.`）。

另外确认：`textclear` 也是 **Lua 定义**的（`SpeakScene.lua:880`），会覆盖原生同名
函数 —— 和 `am_scene_render` 是同一类情况。判断某个 API 到底是原生还是 Lua 的，
用 `grep 'function <名字>'` 最可靠。

## 完整场景合成已验证

用一个自定义测试脚本（`build/spritetest/src/first.ev`）验证精灵绘制链路：

```
msgboxon()                          <- 消息框
bg("sv005b.png")                    <- 背景 CG
wait(300)
text("背景和立绘测试")
textcl()
fg("cgmode_next.png",1)             <- 前景精灵
fgxy(1,150,20)
fgon(1)
text("精灵已显示")
textcl()
```

结果（见 `docs/images/p3-bg-scene.png` 与 `p3-sprite-layer.png`）：

* 背景 CG 正确铺满 480×272
* 前景精灵（CG 画廊 UI）正确叠加在背景之上
* 消息框在最上层，半透明（4444 alpha 混合生效）
* 三张图层面序完全符合 `am_scene_render` 的 bg -> fg -> text_layer 顺序

也就是说 **PGM 的完整渲染管线已经跑通**：背景、立绘、UI 精灵、对话框、彩色中文文本、
文本层清空、alpha 混合全部正常。

### 新增调试开关 `PGM_MAC_SRC=1`

强制脚本包走明文 `src/` 目录（资源包仍读 `gmdata.bin`），这样改 `.ev` 脚本不用重新打包
就能验证。上面的测试场景就是用它跑的。

## 真实输入链路（已打通）

`ControlInit("press_down","press_up","analog")` / `TouchInit(...)` 传的是
**Lua 全局函数名**。宿主必须把它们注册成 nge2 的 C 回调才能真正收到按键：

```
nge_mac 事件队列 -> nge_input.c InputProc -> btn_down()
    -> pgm_input.c 的 C 跳板 -> Lua press_down(key) -> scene:key_down(key)
```

之前只是把名字打日志，键盘完全没反应。现在 `engine/host/pgm_input.c` 负责桥接。

配套加了 `nge_mac_inject_key(code, down)`，可以把按键压进 nge_mac 的事件队列，
从而**走完整条链路**做自动化验证（而不是绕开输入层直接调 Lua 回调）。
实测对话能从 `first.ev` 第 5 行一路推进到第 12 行（脚本结束）。

## 存档读写（已验证）

`amp_pubsave` 写出的文件与代码精确对应：

| 文件 | 大小 | 头部 | 对应代码 |
|---|---|---|---|
| `DATA.SFO` | 8192 | `"PGMCE"` | `PGBufferCreate(1024*8)` + `MEMSTRCPY(buf,GAME_NAME,MEM_UINT8_64)` |
| `DATA.BIN` | 65536 | `ff ff 00 00` (65535) | `PGBufferCreate(1024*64)` + `MEMNUMCPY(buf,65535,MEM_SINT32)` |

文件大小、头部内容、字段宽度全部吻合，说明 `MEM*` 系列与 `WriteBuffer` 是对的。
存档目录是 `<游戏根目录>/PGMSAVEDATA/<GAME_NAME>SYS/`。

## 音频：崩溃已修，播放尚未验证

`engine/third_party/libnge2/coolaudio/nge_audio_mac.m` 用 **AVAudioPlayer** 实现了
`audio_play_t` 虚表（mp3/wav/aac；不支持 ogg），`engine/host/pgm_audio.c` 把 PGM 的
`mp3load/mp3play/SoundCreate/SoundLoad/...` 接到虚表上。两者均已纳入构建，
`NGE_Init` 传 `INIT_ALL`。

### 崩溃的根因（已修）

之前 `api_SoundVolume` 会调到空函数指针：

```
frame #0: 0x0
frame #1: pgm-mac`api_SoundVolume + 108
```

不是虚表没填，而是 **use-after-free**：`SoundUnload` 直接把对象 `free` 掉了，但
`base.lua` 的 `SoundBase:unload()` **不会**把 `voice_p` 置空，Lua 侧后续还会拿这个
句柄去调 `SoundVolume` 等，于是读到的是一块已释放内存，`volume` 成员可能是任何值
（包括 NULL）。

修法（`engine/host/pgm_audio.c`）：
1. 所有音效对象登记在 `g_snd[]` 里；
2. `SoundUnload` 只 `stop()` + 从登记表摘除，**不 free**；
3. `to_sound()` 每次都查表，查不到就返回 NULL，调用方安全返回。

修复后 `PGM-CE`、原版 v0.83、音频测试游戏全部 `exit=0`。

### 之前的"音频没初始化"是误判 —— 日志在 Release 里被裁掉了

`include/nge_debug_log.h` 里有：

```c
#ifdef NDEBUG
#define nge_log()          // ← Release 构建下编译成空
#else
NGE_API void nge_log(const char* pMessage, ...);
#endif
```

所以 **Release 构建里 libnge2 的所有 `nge_log` 都是空操作**，包括
`Init Graphics Ok`。我在 Release 里追日志，当然什么都看不到，才误以为
`CoolAudioDefaultInit` 没被调用。

用 **Debug** 构建跑同一个音频测试，日志一切正常：

```
CoolAudio: macOS 后端已就绪（AVAudioPlayer）
mac audio: loaded .../bin/data/sound/test.wav (2.0s)
```

也就是说音频链路是通的：`NGE_Init(INIT_ALL)` → `CoolAudioDefaultInit()` →
`SoundCreate` → `SoundLoad` → `AVAudioPlayer initWithContentsOfURL` 成功，
并且正确读出了 2.0 秒的时长。

> **调试提示**：要在 Release 里也能看日志，需要在 CMake 里额外定义
> `_DEBUG_STDOUT`，或者直接用 Debug 构建（`./scripts/build.sh Debug`）。

### 音频 API 的真实调用链（重要）

PGM 的音频 API 有**两层**，很多名字在 Lua 里已经被包装过：

```
mp3isfinish(i)          <- Lua (ampfunctions.lua:338)
  -> am_sound.mp3[i]:IsFinish()      <- Lua (base.lua:555)
    -> SoundEos(voice_p)             <- 原生，必须由宿主实现
```

所以只实现 `mp3isfinish` 是没用的（会被 Lua 定义覆盖）。真正需要实现的原生函数就是
`base.lua` 里直接调的那 10 个：

```
SoundCreate  SoundDelete  SoundEos   SoundLoad   SoundPlay
SoundPause   SoundResume  SoundRewind SoundUnload SoundVolume
```

`engine/host/pgm_audio.c` 已全部实现（`SoundDelete` 复用 `SoundUnload` 的语义）。

### 播放状态机验证（直接调用原生 API）

用 `.ev` + Lua 的 `print`（走 stdout，不受 Release 裁日志影响）观察到：

```
A 刚开播      eos = false
B 约 3.3 秒后 eos = false     <- 2 秒的音应该已经播完，这里仍是 false
C rewind 后   eos = false
D unload 后   eos = true      <- 句柄失效，符合预期
```

`A` 和 `D` 都正确，说明对象生命周期与 `SoundEos` 的判断逻辑是通的。
`B` 不符合预期，最可能的原因是**本环境没有可用的音频输出设备** ——
AVAudioPlayer 加载成功（时长都读出来了 2.0s），但没有输出设备时
`currentTime` 不会推进，所以「播完」永远检测不到。

### 音频部分仍未验证的

* 实际**出声**：需要有音频输出的机器上手动确认（本环境无输出设备，
  `currentTime` 不推进）。
* 不支持 **OGG**（AVFoundation 不解 OGG），`CreateOggPlayer` 返回 NULL。
* `mp3playtime()` 固定返回 0（`audio_play_t` 虚表没暴露 currentTime）。

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

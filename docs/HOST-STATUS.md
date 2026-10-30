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

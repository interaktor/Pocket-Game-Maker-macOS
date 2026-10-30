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

## 当前卡点

跑 `PGM_MAC_FRAMES=N ./build/Debug/pgm-mac ../PGM-CE` 能进入主循环、执行 .ev，
但停在 `pubdata.ev` 第 11 行：

```
!! pubdata.ev 第 11 行运行错: savefunctions.lua:786:
   attempt to perform arithmetic on local 'buffer' (a nil value)   内容: amp_pubload()
```

两个问题，按顺序解决：

1. **`goto` / `gotoif` 没有生效**。`pubdata.ev` 第 6 行的 `goto(14)` 没有跳过第 11 行，
   说明 `EScriptJump` 没被调用或没起作用。`goto()` 的实现是：
   ```lua
   function goto(label)
       if am_script.stackCount==0 then return end
       EScriptJump(am_script[am_script.stackCount], label)
   end
   ```
   下一步：打印 `am_script.stackCount` 与该表内容，确认传给 `EScriptJump` 的确实是
   我的 escript userdata（`to_es()` 只认 `LUA_TUSERDATA`）。

2. **存档缓冲区 API 缺实现**：`PGBufferCreate` / `PGBufferDelete` / `MEMSET` /
   `MEMCPY` / `MEMGETNUM` / `MEMGETSTR` / `MEMMODESIZE` 等（见《PGM指令表v0.7.txt》
   的"系统状态"段）。`amp_pubload` / `amp_pubsave` 依赖它们。

解决后继续往下的顺序大致是：消息框与文本渲染（`SpeakScene`）→ 字体真实绘制
→ `EventScene` 的对话推进 → 存档。

## 调试开关

| 环境变量 | 作用 |
|---|---|
| `PGM_MAC_FRAMES=N` | 只跑 N 帧后退出（0/缺省 = 一直跑） |
| `PGM_MAC_SHOT=path.png` | 退出前抓一帧存 PNG |
| `PGM_MAC_DEBUG_WINDOW=1` | 每秒打印一次 AppKit 窗口状态（P1 遗留） |

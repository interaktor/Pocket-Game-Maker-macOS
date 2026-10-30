# 移植笔记 / Porting notes

记录 `third_party/libnge2/` 相对上游 <https://github.com/yydaor/libnge2>
（`master`，commit 时间 2012 年前后）的**全部**改动。所有改动都可以由
`scripts/apply_mac_patches.py` 幂等地复现 —— 该脚本用字节级精确替换，并带
`expected-count` 断言，所以上游一旦变动会立刻失败而不是静默改坏源码。

如果你只是想复现构建，直接跑：

```sh
python3 scripts/apply_mac_patches.py
```

---

## 背景：上游的平台矩阵

`include/nge_platform.h` 里其实**已经声明了 `NGE_MAC`**：

```c
#elif defined __APPLE__
#define NGE_MAC
```

但整个代码库里 `NGE_MAC` 一次都没被使用过 —— 也就是说 macOS 只是留了个门，
门后什么都没有。真正有后端的是：

| 平台 | 宏 | 窗口/上下文 | 渲染 |
|---|---|---|---|
| PSP | `NGE_PSP` | `sceDisplay` | GU |
| Windows | `NGE_WIN` | Win32 + WGL | 桌面 GL |
| Linux | `NGE_LINUX` | X11 + GLX | 桌面 GL |
| Android | `NGE_ANDROID` | JNI | GLES1 |
| iOS | `NGE_IPHONE` | Cocoa | GLES1 |

macOS 的移植策略：**渲染走和 Linux/Windows 相同的桌面 GL 路径（固定管线
GL 1.x/2.1 + `GL_EXT_framebuffer_object`），窗口/输入/音频另写 Cocoa 后端。**

## A. 新增文件

| 文件 | 说明 |
|---|---|
| `src/mac/nge_mac.h` | macOS 后端对 C 侧的接口（事件结构体、窗口/交换/轮询） |
| `src/mac/nge_mac_window.m` | Cocoa + NSOpenGL 实现：窗口、GL 上下文、事件队列、键位映射 |
| `coolaudio/nge_audio_mac.c` | 音频后端**占位**（P1 只保证链接；CoreAudio 实现在 P4） |

## B. 平台分支接入（机械改动）

把 `NGE_MAC` 加进原本只认 `NGE_LINUX` / `NGE_WIN` 的条件编译里。这些地方
逻辑都是 POSIX 通用的，不需要新实现：

| 文件 | 改了什么 |
|---|---|
| `src/nge_timer.c` | 归入 `NGE_UNIX` 分支，用 `gettimeofday` 计 tick |
| `src/nge_io_dir.c` | 归入 POSIX `dirent` 分支 |
| `src/nge_debug_log.c` | `_vsnprintf` → `vsnprintf` 的别名 |
| `include/nge_misc.h` | `nge_sleep()` 宏（原来用编译器宏 `__linux__` 判断，macOS 漏掉了） |
| `src/nge_image_effect.c` | `NGE_NORMAL_GL_API` + 桌面 GL 头文件 |
| `include/nge_input.h` | 按键支持宏 + `PSP_BUTTON_*` 常量（值同 Windows） |
| `src/nge_input.c` | 摇杆模拟、`SetAnalog` 方向键 case、`InputProc` 的 macOS 事件循环 |
| `src/nge_graphics.c` | `<OpenGL/gl.h>`、`makeWindow()`、`InitGraphics`/`FiniGraphics`/`EndScene`、FBO |

### 键位

`PSP_BUTTON_*` 的值与 Windows 版**完全一致**（`'W' 'S' 'A' 'D' 'I' 'L' 'K' 'J'
'E' 'U' 'V' 'B' 'N' 'M'`）。这点很重要：这些常量是由原生层注册进 Lua 的全局
变量，PGM 的 Lua 框架（`KeySetting.lua`、`FindScene.lua`、`HistoryScene.lua` …）
直接拿它们做比较。值一变，所有游戏的手感就全乱了。

macOS 的虚拟键码到这套值的映射在 `nge_mac_window.m: map_keycode()`，另外
额外接受方向键（当十字键）、Return/Space/`'`（当确认）、Esc（当 HOME）、
Tab（当 SELECT）、Q/R（当 L/R 扳机）。

### 事件传递

libnge2 是轮询式引擎（`nge_main.c` 里 `while(1) { app->mainloop(); }`，输入靠
`InputProc()` 拉取），而 Cocoa 想自己掌控 run loop。桥接方式是经典做法：
**不调用 `-[NSApplication run]`**，而是每帧用 `nextEventMatchingMask:` 主动
抽事件、`sendEvent:` 派发，再 `CFRunLoopRunInMode(..., 0, true)` 让窗口服务器
提交一帧。抽到的事件进一个小环形队列，`nge_input.c` 再从队列里取。

按键重复（`isARepeat`）被主动忽略 —— PSP 是轮询按键状态，语义上等于
「按下一次 = 一次 keydown」，而 macOS 的重复速率和 Windows 完全不同，
放进来会让游戏逻辑抖。

## C. 移植性修复（上游在现代工具链上编不过）

| 文件 | 问题 | 处理 |
|---|---|---|
| `src/nge_input.c` | `static touch_mode = 0;` 缺 `int`，C99 起非法 | 补 `int` |
| `src/nge_png.c` | 直接访问 `png_ptr->io_ptr`，libpng 1.4+ 已是不透明类型 | 改用 `png_get_io_ptr()` |
| `src/nge_png.c` | 把 `int` fd 强转成 `void*` 再转回来，64 位下有损 | 走 `intptr_t` 往返 |
| `src/nge_png.c` | 缺 `<string.h>` / `<stdint.h>` | 补 include |
| `src/nge_debug_log.c` | `inline void nge_printf(...)` 在 C99 语义下不产生外部定义，链接时未定义 | 改 `static` |
| `CMakeLists.txt` | `src/charsets/*.h` 里写的是 `#include "charsets/gb2312.h"` | 把 `src/` 加进头文件搜索路径 |
| `CMakeLists.txt` | 无条件链接 `g` / `c` / `stdc++`，macOS 上没有这些 | APPLE 分支跳过 |
| `CMakeLists.txt` | `src/nge_package_zip.c` 依赖 minizip 的 `unzip.h` | macOS 不编译该模块（PGM 用自己的封包格式） |

## D. 上游 bug 修复

### `nge_sleep` 单位错 1000 倍（影响所有类 UNIX 平台）

```c
/* include/nge_misc.h，Unix 分支 */
#define nge_sleep(tick) usleep(tick)          // 错
```

`usleep()` 的参数是**微秒**，但调用方传的是**毫秒** —— `LimitFps` 里写的是
`nge_sleep(1000/fps)`。对比一下同文件里的 PSP 分支：

```c
#define nge_sleep(tick) sceKernelDelayThread((tick)*1000)   // ms -> us
```

PSP 分支自己乘了 1000，说明语义就是毫秒。Linux/macOS 分支漏了这一乘，
导致引擎实际以 **~300fps** 跑而不是 60fps（白白烧 CPU，也让人误以为
垂直同步失效）。修成 `usleep((tick)*1000)` 后实测正好 60fps。


### `ScreenToImage()` 的行跨距错误

这是**在所有平台上都存在**的 bug，但在 macOS 上先撞上了，因为需要用
`ScreenToImage()` 抓帧来做自动化验证。

```c
image_p ScreenToImage() {
    image_p pimage = image_create(nge_screen.width, nge_screen.height, 8888);
    ...
    glReadPixels(0, 0, nge_screen.width, nge_screen.height, GL_RGBA, ..., pimage->data);
```

问题在 `image_create()`：它把**纹理**尺寸向上取整到 2 的幂（`texw`/`texh`），
所以 480×272 的图实际分配的是 512×512×4 字节，每行真实 pitch 是
`512*4 = 2048` 字节。而 `glReadPixels` 是**紧凑**写 480×4 = 1920 字节每行。
于是第 N 行就错位 `N*128` 字节（32 像素），逐行累积 —— 表现出来就是画面被
斜着切碎的条纹。

修法：读之前告诉 GL 真实行跨距。

```c
glPixelStorei(GL_PACK_ALIGNMENT, 1);
glPixelStorei(GL_PACK_ROW_LENGTH, pimage->texw);
glReadPixels(0, 0, pimage->w, pimage->h, GL_RGBA, GL_UNSIGNED_BYTE, pimage->data);
glPixelStorei(GL_PACK_ROW_LENGTH, 0);
```

## E. 一个 macOS 特有的坑：窗口透明

最初用普通 `NSView` + `[NSOpenGLContext setView:]`。结果很迷惑：

* `glReadPixels` 能读回完全正确的画面；
* AppKit 报告 `isVisible=1, isKeyWindow=1, isMainWindow=1, NSApp.isActive=1`；
* CoreGraphics 的 `CGWindowListCopyWindowInfo` 里也能看到窗口
  （`layer=0, bounds=480x300`）；
* **但屏幕上那块区域是壁纸。**

原因：macOS 10.14 起 AppKit 强制 layer-backing，老式的 `setView:` surface 不会
被合成到窗口的 backing store 上，窗口就成了一张全透明的空壳。

修法：把视图基类从 `NSView` 换成 **`NSOpenGLView`**，用
`initWithFrame:pixelFormat:` 创建，并让它自己持有 context。同时在
`prepareOpenGL` 里把 swap interval 设为 1。

## F. 验证方法

`tests/p1_smoke.c` 是 P1 的验收测试。它不依赖任何外部素材（demo1 需要的
`res.7z` 下载链接早已失效），只画几何图元，渲染完后用 `ScreenToImage()` 回读
并写成 PNG，所以可以完全自动化地判断「窗口建好了、GL 上下文是当前的、
画得对、回读对」。

```sh
./build/tests/p1_smoke 20 /tmp/p1_smoke.png
```

期望看到：四色分区、白色边框、位于 (40,40) 的白色方块、左上到右下的黄色对角线、
y=200 处移动的洋红方块。

## src/ 目录是过时的，封包才是真框架

这一条卡了很久。

`PGM-CE` 仓库里同时有 `bin/data/gmcode.bin` 和 `src/`，直觉上会以为 `src/` 是
封包的源文件、两者内容一致。**不是。** 用 `PGM_MAC_DUMP_PACK` 把封包导出来对比：

| | `src/` 目录 | `gmcode.bin` |
|---|---|---|
| 文件数 | 22 个 lua | 43 个 |
| `lg_init.lua` | 只 include 27 个 | include **39** 个 |

封包版的 `lg_init.lua` 多 include 了 `ce_init.lua`、`cefunctions.lua`、
`ScrollBar.lua`、`SomeEffect.lua`、`WaitScene.lua`、`AnalogScene.lua`、
`HideScene.lua`、`HelpScene.lua`、`ConfigScene.lua`、`HistoryScene.lua`、
`CGlist.lua`、`CGmode.lua` 这 12 个。

后果：如果拿 `src/` 当工程底子（我就是这么起手的），`font()`、`msgboxon()`、
`historybegin()` 全是 nil，因为定义它们的 `cefunctions.lua` 从来没被加载。
而 `am_start.ev` 一跑就报 nil，看不出根因。

**结论：做骨架工程必须从封包导出，不能从 `src/` 拼。**

导出方法（`src/pgm_pack.c`）：

```sh
PGM_MAC_DUMP_PACK=/tmp/dump ./build/Release/pgm-mac /path/to/game
```

脚本包按行记录解出明文，资源包直接按偏移量拷原始字节，两种都支持。

## .ev 的 *标签必须先替换成行号

`.ev` 里写 `goto(*sel1)`、`gotoif(cond,*savedata)`、`drawramus("文字",*label)`。
这些**不是合法 Lua** —— `*` 不能做前缀运算符，直接编译会报
`unexpected symbol near '*'`。

原版引擎的做法是执行前做文本替换：把 `*标签` 换成它所在的物理行号，于是变成
`goto(14)`。Lua 5.1 里 `goto` 不是关键字，所以 `goto(14)` 就是一次普通函数调用，
而 `EScriptJump(script, 14)` 也确实接收行号。

移植时漏了这层预处理，表现是：

- `pubdata.ev` 里 `goto(*savedata)` 全部语法错被跳过 → 存档初始化不执行
- `drawramus("A",*a,"B",*b)` 语法错 → 选项界面根本不出现，脚本直接往下跑

修法（`src/pgm_escript.c`）：`EScriptCreate` 时扫一遍所有行建标签表（`*名字` 在行首
即为定义），`EScriptDoline` 里：标签定义行直接跳过不执行，其余行先把 `*名字` 替换
成行号再编译。替换时要跳过字符串字面量和 `--` 注释，否则 `say("*星号*")` 会被破坏。

调试开关 `PGM_TRACE_REWRITE=1` 会打印替换前后的对比：

```
[rw] main.ev:4 labels=3  drawramus("选项甲",*a,"选项乙",*b) -> drawramus("选项甲",5,"选项乙",7)
```

## 存档目录：FolderCreate 和 WriteBuffer

两个独立 bug 叠加，表现是 `!! WriteBuffer 打不开: PGMSAVEDATA/PGMCESYS/DATA.BIN`。

1. `FolderCreate()` 是空实现，只打日志不建目录 —— 补上 `pgm_mkdir_p()`。
2. `WriteBuffer()` 用 `pgm_resolve()` 求路径，但那个函数只找**已存在的普通文件**，
   写目标当然还不存在，于是退回相对路径，而相对路径是相对进程 CWD 的，不是游戏根目录。

修法：新增 `pgm_write_path()`，把相对名拼到游戏根目录下并顺手建好父目录。

注意存档路径不能跟着 CWD 走，否则从 Finder 双击和从终端运行会存到两个地方。

## 资源路径的 data/ 前缀

框架拼资源名用的是 `PGM_RES_FOLDER`（`"data/"`）+ 名字，于是字体请求的是
`data/fz.ttf`，而文件实际在 `data/font/fz.ttf`。`pgm_resolve()` 里加一段：
relpath 以 `data/` 开头时，剥掉前缀再按 `font/` `bgm/` `sound/` `voice/` `video/`
`system/` 依次试。

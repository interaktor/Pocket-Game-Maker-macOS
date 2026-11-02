#!/usr/bin/env python3
"""
apply_mac_patches.py — 为 libnge2 打上 NGE_MAC (macOS) 平台补丁。

libnge2 上游的源文件是 GBK 编码，且 NGE_MAC 宏在 nge_platform.h 里
声明了却从未实现。本脚本以**纯 ASCII 子串**做字节级精确替换，因此不会
破坏文件里原有的 GBK 中文注释。

每个替换都带 expected-count 断言：上游若变动，脚本会立刻失败而不是
静默改坏源码。

用法：
    python3 scripts/apply_mac_patches.py            # 打补丁（幂等）
    python3 scripts/apply_mac_patches.py --check    # 只检查，不写盘
"""

import sys
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    "..", "third_party", "libnge2")

CHECK_ONLY = "--check" in sys.argv

# (相对路径, 旧子串, 新子串, 期望出现次数)
PATCHES = [
    # ---------------------------------------------------------------
    # nge_timer.c — 走 POSIX gettimeofday 分支
    # ---------------------------------------------------------------
    ("src/nge_timer.c",
     b"#if defined NGE_LINUX || defined NGE_IPHONE || defined NGE_ANDROID\n#define NGE_UNIX",
     b"#if defined NGE_LINUX || defined NGE_IPHONE || defined NGE_ANDROID || defined NGE_MAC\n#define NGE_UNIX",
     1),

    # ---------------------------------------------------------------
    # nge_io_dir.c — 走 POSIX dirent 分支
    # ---------------------------------------------------------------
    ("src/nge_io_dir.c",
     b"#elif defined NGE_PSP || defined NGE_LINUX || defined NGE_IPHONE || defined NGE_ANDROID\n",
     b"#elif defined NGE_PSP || defined NGE_LINUX || defined NGE_IPHONE || defined NGE_ANDROID || defined NGE_MAC\n",
     1),
    ("src/nge_io_dir.c",
     b"#if defined NGE_LINUX || defined NGE_IPHONE || defined NGE_ANDROID\n#include <unistd.h>",
     b"#if defined NGE_LINUX || defined NGE_IPHONE || defined NGE_ANDROID || defined NGE_MAC\n#include <unistd.h>",
     1),

    # ---------------------------------------------------------------
    # nge_debug_log.c — _vsnprintf 是 MSVC 专有名字
    # ---------------------------------------------------------------
    ("src/nge_debug_log.c",
     b"#if defined NGE_LINUX || defined NGE_PSP\n#define _vsnprintf  vsnprintf",
     b"#if defined NGE_LINUX || defined NGE_PSP || defined NGE_MAC\n#define _vsnprintf  vsnprintf",
     1),

    # ---------------------------------------------------------------
    # nge_image_effect.c — 桌面 OpenGL 分支
    # ---------------------------------------------------------------
    ("src/nge_image_effect.c",
     b"#if defined NGE_WIN || defined NGE_IPHONE || defined NGE_LINUX || defined NGE_ANDROID\n#define NGE_NORMAL_GL_API",
     b"#if defined NGE_WIN || defined NGE_IPHONE || defined NGE_LINUX || defined NGE_ANDROID || defined NGE_MAC\n#define NGE_NORMAL_GL_API",
     1),
    ("src/nge_image_effect.c",
     b"#elif defined NGE_WIN || defined NGE_LINUX\n\n#include <GL/gl.h>\n\n#if defined NGE_LINUX\n#include <X11/Xlib.h>",
     b"#elif defined NGE_MAC\n\n#include <OpenGL/gl.h>\n\n#elif defined NGE_WIN || defined NGE_LINUX\n\n#include <GL/gl.h>\n\n#if defined NGE_LINUX\n#include <X11/Xlib.h>",
     1),

    # ---------------------------------------------------------------
    # nge_input.h — 键位支持宏 + PSP_BUTTON_* 常量
    # ---------------------------------------------------------------
    ("include/nge_input.h",
     b"#if defined NGE_PSP || defined NGE_LINUX || defined NGE_WIN || defined NGE_IPHONE\n#define NGE_INPUT_BUTTON_SUPPORT",
     b"#if defined NGE_PSP || defined NGE_LINUX || defined NGE_WIN || defined NGE_IPHONE || defined NGE_MAC\n#define NGE_INPUT_BUTTON_SUPPORT",
     1),
    # macOS 的 PSP_BUTTON_* 与 Windows 完全一致（纯 ASCII 字母），
    # 这样 PGM 的 Lua 框架（KeySetting.lua / FindScene.lua …）无需改动。
    ("include/nge_input.h",
     b"#elif defined NGE_PSP\n#define PSP_BUTTON_UP            8",
     b"""#elif defined NGE_MAC
/* PGM-Mac: identical values to the Windows build ('W','S','A',... 'M')
   so PGM's Lua framework works unchanged. nge_mac_window.m translates
   macOS virtual keycodes into these codes (and also accepts arrows). */
#define PSP_BUTTON_UP            'W'
#define PSP_BUTTON_DOWN          'S'
#define PSP_BUTTON_LEFT          'A'
#define PSP_BUTTON_RIGHT         'D'
#define PSP_BUTTON_TRIANGLE      'I'
#define PSP_BUTTON_CIRCLE        'L'
#define PSP_BUTTON_CROSS         'K'
#define PSP_BUTTON_SQUARE        'J'
#define PSP_BUTTON_LEFT_TRIGGER  'E'
#define PSP_BUTTON_RIGHT_TRIGGER 'U'
#define PSP_BUTTON_SELECT        'V'
#define PSP_BUTTON_START         'B'
#define PSP_BUTTON_HOME          'N'
#define PSP_BUTTON_HOLD          'M'
#elif defined NGE_PSP
#define PSP_BUTTON_UP            8""",
     1),
    ("include/nge_input.h",
     b"#if defined NGE_WIN || defined NGE_LINUX\n#define NGE_INPUT_MOUSE_FULL_SUPPORT",
     b"#if defined NGE_WIN || defined NGE_LINUX || defined NGE_MAC\n#define NGE_INPUT_MOUSE_FULL_SUPPORT",
     1),

    # ---------------------------------------------------------------
    # nge_input.c — 引入 macOS 后端、摇杆模拟、事件轮询
    # ---------------------------------------------------------------
    # (a) 引入后端头文件
    ("src/nge_input.c",
     b"extern Window   g_win;\n#endif",
     b"extern Window   g_win;\n#elif defined NGE_MAC\n#include \"mac/nge_mac.h\"\n#endif",
     1),
    # (b) InitInput：Cocoa 侧已就绪，无需额外初始化
    ("src/nge_input.c",
     b"\tXSelectInput(g_dpy, g_win, mask);\n#endif",
     b"\tXSelectInput(g_dpy, g_win, mask);\n#elif defined NGE_MAC\n\t/* Cocoa events arrive through nge_mac_poll_event(); nothing to do here. */\n\t(void)doneflag;\n#endif",
     1),
    # (c) 摇杆模拟块（把方向键当摇杆）也适用于 macOS
    ("src/nge_input.c",
     b"#if defined NGE_WIN || defined NGE_LINUX\n#define ANALOG_LEFT  0",
     b"#if defined NGE_WIN || defined NGE_LINUX || defined NGE_MAC\n#define ANALOG_LEFT  0",
     1),
    # (d) SetAnalog 的 4 个方向键 case
    ("src/nge_input.c",
     b"#if defined NGE_WIN\n\tcase VK_UP:\n#elif defined(NGE_LINUX)\n\tcase XK_Up:\n#endif",
     b"#if defined NGE_WIN\n\tcase VK_UP:\n#elif defined(NGE_LINUX)\n\tcase XK_Up:\n#elif defined(NGE_MAC)\n\tcase 'W':\n#endif",
     1),
    ("src/nge_input.c",
     b"#if defined(NGE_WIN)\n\tcase VK_DOWN:\n#elif defined(NGE_LINUX)\n\tcase XK_Down:\n#endif",
     b"#if defined(NGE_WIN)\n\tcase VK_DOWN:\n#elif defined(NGE_LINUX)\n\tcase XK_Down:\n#elif defined(NGE_MAC)\n\tcase 'S':\n#endif",
     1),
    ("src/nge_input.c",
     b"#if defined(NGE_WIN)\n\tcase VK_LEFT:\n#elif defined(NGE_LINUX)\n\tcase XK_Left:\n#endif",
     b"#if defined(NGE_WIN)\n\tcase VK_LEFT:\n#elif defined(NGE_LINUX)\n\tcase XK_Left:\n#elif defined(NGE_MAC)\n\tcase 'A':\n#endif",
     1),
    ("src/nge_input.c",
     b"#if defined(NGE_WIN)\n\tcase VK_RIGHT:\n#elif defined(NGE_LINUX)\n\tcase XK_Right:\n#endif",
     b"#if defined(NGE_WIN)\n\tcase VK_RIGHT:\n#elif defined(NGE_LINUX)\n\tcase XK_Right:\n#elif defined(NGE_MAC)\n\tcase 'D':\n#endif",
     1),
    # (e) ana_ret
    ("src/nge_input.c",
     b"#if defined NGE_WIN || defined NGE_LINUX\nstatic int ana_ret = 0;",
     b"#if defined NGE_WIN || defined NGE_LINUX || defined NGE_MAC\nstatic int ana_ret = 0;",
     1),
    # (f) InputProc 的局部变量
    ("src/nge_input.c",
     b"#elif defined NGE_WIN\n\tMSG msg;\n#endif",
     b"#elif defined NGE_WIN\n\tMSG msg;\n#elif defined(NGE_MAC)\n\tnge_mac_event mev;\n#endif",
     1),
    # (g) InputProc 的 ana_ret 复位
    ("src/nge_input.c",
     b"#if defined NGE_WIN || defined NGE_LINUX\n\tana_ret = 0;\n#endif",
     b"#if defined NGE_WIN || defined NGE_LINUX || defined NGE_MAC\n\tana_ret = 0;\n#endif",
     1),
    # (h) InputProc 的事件循环 —— 插入 macOS 分支
    ("src/nge_input.c",
     b"#elif defined(NGE_WIN)\n\tif (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE))",
     b"""#elif defined(NGE_MAC)
	while (nge_mac_poll_event(&mev)) {
		switch (mev.type) {
		case NGE_MAC_EV_QUIT:
			FiniGraphics();
			exit(0);
			break;
		case NGE_MAC_EV_MOUSEMOVE:
			if ((mouse_move_proc != NULL) &&
				((istouched && touch_mode == 1) || (touch_mode == 0)))
				mouse_move_proc(1.0f * mev.x * screen->ori_width / screen->width,
								1.0f * mev.y * screen->ori_height / screen->height);
			break;
		case NGE_MAC_EV_MOUSEDOWN:
		case NGE_MAC_EV_MOUSEUP: {
			/* NGE_MAC_MOUSE_LEFT/RIGHT/MIDDLE 1/2/3 ->
			   MOUSE_LBUTTON_/RBUTTON_/MBUTTON_ 1/3/5 */
			int type = (mev.code - 1) * 2 +
				(mev.type == NGE_MAC_EV_MOUSEDOWN ? 1 : 2);
			if (mev.type == NGE_MAC_EV_MOUSEDOWN) {
				istouched = 1;
			} else {
				istouched = 0;
			}
			if (mouse_btn_proc != NULL)
				mouse_btn_proc(type,
							   1.0f * mev.x * screen->ori_width / screen->width,
							   1.0f * mev.y * screen->ori_height / screen->height);
			break;
		}
		case NGE_MAC_EV_KEYDOWN:
			btn_down(mev.code);
			ana_ret = SetAnalog(mev.code, 1);
			break;
		case NGE_MAC_EV_KEYUP:
			btn_up(mev.code);
			ana_ret = SetAnalog(mev.code, 0);
			break;
		default:
			break;
		}
	}
#elif defined(NGE_WIN)
	if (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE))""",
     1),
    # (i) 事件循环之后的摇杆派发
    ("src/nge_input.c",
     b"#if defined NGE_WIN || defined NGE_LINUX\n\tif(analog_proc!=NULL&&ana_ret){",
     b"#if defined NGE_WIN || defined NGE_LINUX || defined NGE_MAC\n\tif(analog_proc!=NULL&&ana_ret){",
     1),

    # ---------------------------------------------------------------
    # nge_graphics.c — 桌面 GL 分支 + 窗口/上下文创建
    # ---------------------------------------------------------------
    ("src/nge_graphics.c",
     b"#elif defined NGE_WIN || defined NGE_LINUX\n#include <GL/glew.h>\n#include <GL/gl.h>",
     b"""#elif defined NGE_MAC
/* Apple's <OpenGL/gl.h> already includes <OpenGL/glext.h>, which declares
   the *EXT framebuffer entry points directly (no GLEW needed). We request
   the legacy 2.1 profile, which still exposes fixed-function GL. */
#include <OpenGL/gl.h>

#elif defined NGE_WIN || defined NGE_LINUX
#include <GL/glew.h>
#include <GL/gl.h>""",
     1),
    # macOS 窗口创建：转交给 Cocoa 后端
    ("src/nge_graphics.c",
     b"void InitGraphics()\n{",
     b"""#if defined NGE_MAC
/* macOS: the window + legacy GL context live in src/mac/nge_mac_window.m.
   nge2 only needs a makeWindow() of the same shape as the X11/Win32 ones. */
void makeWindow(const char *name, int x, int y, int width, int height)
{
	(void)x;
	(void)y;
	if (nge_mac_window_create(name, width, height, 0) != 0)
		nge_error("nge_mac_window_create failed\\n");
}
#endif

void InitGraphics()
{""",
     1),
    ("src/nge_graphics.c",
     b"\tXMapWindow(g_dpy, g_win);\n\tglXMakeCurrent(g_dpy, g_win, g_ctx);",
     b"""\tXMapWindow(g_dpy, g_win);
\tglXMakeCurrent(g_dpy, g_win, g_ctx);
#elif defined NGE_MAC
\tmakeWindow(nge_screen.name, 0, 0, nge_screen.width, nge_screen.height);
\tglGenFramebuffersEXT(1, &fbo);""",
     1),
    ("src/nge_graphics.c",
     b"\tXCloseDisplay(g_dpy);\n#endif",
     b"\tXCloseDisplay(g_dpy);\n#endif\n\n#if defined NGE_MAC\n\tglDeleteFramebuffersEXT(1, &fbo);\n\tnge_mac_window_destroy();\n#endif",
     1),
    # EndScene：交换缓冲
    ("src/nge_graphics.c",
     b"#elif defined NGE_WIN\n\tSwapBuffers( hDC );",
     b"#elif defined NGE_MAC\n\tnge_mac_swap_buffers();\n#elif defined NGE_WIN\n\tSwapBuffers( hDC );",
     1),
    # 离屏渲染目标（FBO）
    ("src/nge_graphics.c",
     b"#if defined NGE_WIN || defined NGE_LINUX\t\n\tstatic int cacheid = 0;",
     b"#if defined NGE_WIN || defined NGE_LINUX || defined NGE_MAC\t\n\tstatic int cacheid = 0;",
     1),
    ("src/nge_graphics.c",
     b"void EndTarget(){\n#if defined NGE_WIN || defined NGE_LINUX",
     b"void EndTarget(){\n#if defined NGE_WIN || defined NGE_LINUX || defined NGE_MAC",
     1),
]

# =====================================================================
# CMake 构建系统补丁（CMakeLists.txt 是 CRLF 行尾）
# =====================================================================
CRLF = b"\r\n"

CMAKE_PATCHES = [
    # 说明：CMakeLists.txt 的 macOS 改动（OBJC 源文件、Cocoa/OpenGL/AVFoundation
    # 框架、跳过 nge_package_zip）已直接固化在 vendored 的三方树里，不再由脚本
    # 用字符串替换施加 —— 因为多个补丁作用于同一段文本时，彼此的幂等判定会互相
    # 破坏，导致每次运行都重复插入一整块。这里保持空表。
]


PATCHES.extend(CMAKE_PATCHES)

# =====================================================================
# 移植性 bug 修复（上游代码用了 32 位/旧库的写法，在 macOS+新 libpng 上失败）
# =====================================================================
PORT_PATCHES = [
    # 隐式 int：C99 起不再允许，clang 16 直接报错
    ("src/nge_input.c",
     b"static touch_mode = 0;\nstatic istouched  = 0;",
     b"static int touch_mode = 0;\nstatic int istouched  = 0;",
     1),

    # libpng 1.4+ 起 png_struct 是不透明类型，不能再直接读 io_ptr
    ("src/nge_png.c",
     b"\tuint8_t* handle = (uint8_t*)png_ptr->io_ptr;",
     b"\tuint8_t* handle = (uint8_t*)png_get_io_ptr(png_ptr);",
     1),
    # 原写法把 int fd 强转成指针再转回来；64 位下是有损的。改用 intptr_t 往返。
    ("src/nge_png.c",
     b"\tint handle = (int)(png_ptr->io_ptr);",
     b"\tint handle = (int)(intptr_t)png_get_io_ptr(png_ptr);",
     1),
    ("src/nge_png.c",
     b"\tpng_set_write_fn(png_ptr, (png_voidp)handle, png_custom_fwrite_fn,NULL);",
     b"\tpng_set_write_fn(png_ptr, (png_voidp)(intptr_t)handle, png_custom_fwrite_fn,NULL);",
     1),
    # 需要 intptr_t / memset
    ("src/nge_png.c",
     b"#include \"nge_io_file.h\"\n#include <stdlib.h>",
     b"#include \"nge_io_file.h\"\n#include <stdlib.h>\n#include <stdint.h>\n#include <string.h>",
     1),
]

PATCHES.extend(PORT_PATCHES)

# =====================================================================
# 收尾：缺失的声明 / 不适用模块
# =====================================================================
FIXUP_PATCHES = [
    # nge_misc.h 用编译器宏 __linux__ 判断，macOS 上会漏掉 nge_sleep
    ("include/nge_misc.h",
     b"#elif defined __linux__ || defined NGE_IPHONE\n#include <unistd.h>",
     b"#elif defined __linux__ || defined NGE_IPHONE || defined __APPLE__\n#include <unistd.h>",
     1),

    # nge_package_zip.c 依赖 minizip 的 unzip.h；PGM 用的是自己的封包格式，
    # macOS 构建里直接排除该模块（CMake 侧处理），此处无需改源码。
]

PATCHES.extend(FIXUP_PATCHES)

CMAKE_EXTRA = [
    # macOS 不编译 zip 封包模块
    ("CMakeLists.txt",
     b"  src/nge_package.c" + CRLF +
     b"  src/nge_package_zip.c" + CRLF +
     b"  )" + CRLF,
     b"  src/nge_package.c" + CRLF +
     b"  )" + CRLF + CRLF +
     b"if(NOT APPLE)" + CRLF +
     b"  # nge_package_zip.c needs minizip's unzip.h. PGM uses its own pack" + CRLF +
     b"  # format (see include/helper/package.h), so macOS skips this module." + CRLF +
     b"  list(APPEND NGE2_SRCS" + CRLF +
     b"\\tsrc/nge_package_zip.c" + CRLF +
     b"\\t)" + CRLF +
     b"endif()" + CRLF,
     1),
]

PATCHES.extend(CMAKE_EXTRA)

# C99 语义下裸 inline 不产生外部定义，链接时 nge_printf 未定义
INLINE_FIX = [
    ("src/nge_debug_log.c",
     b"inline void nge_printf (FILE** pFile,",
     b"static void nge_printf (FILE** pFile,",
     1),
]
PATCHES.extend(INLINE_FIX)

# =====================================================================
# 上游 bug 修复（不只是 macOS 问题，但在 macOS 上必须先修才能验证渲染）
# =====================================================================
UPSTREAM_BUGS = [
    # image_create() 把纹理尺寸向上取整到 2 的幂（480x272 -> 512x512），
    # 所以 pimage->data 的每行 pitch 是 texw*bpb 而不是 w*bpb。
    # ScreenToImage() 里裸的 glReadPixels 会按 w 连续写，逐行错位累积。
    ("src/nge_graphics.c",
     b"\tglPixelStorei(GL_UNPACK_ALIGNMENT, 1);\n"
     b"\tglReadPixels( 0, 0, nge_screen.width, nge_screen.height, GL_RGBA, GL_UNSIGNED_BYTE, pimage->data );\n",
     b"\t/* PGM-Mac fix: image_create() rounds the texture size up to a power of\n"
     b"\t   two, so a 480x272 image really has a 512-pixel pitch. A plain\n"
     b"\t   glReadPixels writes 480-pixel rows back to back and every row after\n"
     b"\t   the first lands 128 bytes (32 px) off. GL_PACK_ROW_LENGTH tells GL\n"
     b"\t   the real stride so the buffer matches image_flipv()/image_save_png(). */\n"
     b"\tglPixelStorei(GL_PACK_ALIGNMENT, 1);\n"
     b"\tglPixelStorei(GL_PACK_ROW_LENGTH, pimage->texw);\n"
     b"\tglReadPixels( 0, 0, pimage->w, pimage->h, GL_RGBA, GL_UNSIGNED_BYTE, pimage->data );\n"
     b"\tglPixelStorei(GL_PACK_ROW_LENGTH, 0);\n",
     1),
]
PATCHES.extend(UPSTREAM_BUGS)

# =====================================================================
# 平台检测修复（已直接写入 include/nge_platform.h，不再由脚本应用）
#
# macOS 上 <TargetConditionals.h> 会把 TARGET_OS_IPHONE 定义成 0，而
# nge_platform.h 原来写的是 "defined TARGET_OS_IPHONE"（判断有没有定义），
# 于是 macOS 被误判成 NGE_IPHONE。已改为先判 __APPLE__ 再用真值区分。
# 因为这段是带中文注释的多行块，放进字节级替换表容易和已有内容错配，
# 所以直接固化在头文件里，脚本不再处理。
# =====================================================================

# Objective-C 的 .m 文件里 objc/objc.h 已定义 BOOL，libnge2 的 typedef 会冲突
OBJC_BOOL_FIX = [
    ("include/nge_common.h",
     b"\t#ifdef _MSC_VER\n\ttypedef int BOOL;\n\t#else\n\ttypedef uint8_t BOOL;\n\t#endif\n",
     b"\t#ifdef _MSC_VER\n\ttypedef int BOOL;\n"
     b"\t#elif defined(__OBJC__)\n"
     b"\t/* Objective-C: objc/objc.h already defines BOOL; redefining conflicts */\n"
     b"\t#else\n\ttypedef uint8_t BOOL;\n\t#endif\n",
     1),
]
PATCHES.extend(OBJC_BOOL_FIX)

# usleep 吃微秒，但 nge2 的调用方传的是毫秒（LimitFps 里 nge_sleep(1000/fps)）
SLEEP_FIX = [
    ("include/nge_misc.h",
     b"#define nge_sleep(tick) usleep(tick)",
     b"/* PGM-Mac: usleep() takes microseconds but callers pass milliseconds\n"
     b"   (LimitFps does nge_sleep(1000/fps)). Without the x1000 the engine\n"
     b"   slept 1000x too little and ran at ~300fps instead of 60. */\n"
     b"#define nge_sleep(tick) usleep((tick)*1000)",
     1),
]
PATCHES.extend(SLEEP_FIX)


def main():
    failures = []
    applied = 0
    unchanged = 0

    for rel, old, new, expect in PATCHES:
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path):
            failures.append("%s: 文件不存在" % rel)
            continue
        with open(path, "rb") as f:
            data = f.read()

        # 幂等：已经打过就直接跳过
        if new in data:
            unchanged += 1
            continue

        n = data.count(old)
        if n != expect:
            failures.append("%s: 期望 %d 处匹配，实际 %d 处 — %r"
                            % (rel, expect, n, old[:60]))
            continue

        data = data.replace(old, new)
        if not CHECK_ONLY:
            with open(path, "wb") as f:
                f.write(data)
        applied += 1

    print("补丁: %d 应用, %d 已存在, %d 失败"
          % (applied, unchanged, len(failures)))
    for f in failures:
        print("  ✗ " + f)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

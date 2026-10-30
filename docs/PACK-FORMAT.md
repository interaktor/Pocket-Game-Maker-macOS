# PGM 封包格式 / Pack format

记录 PGM 的 `gmcode.bin`（脚本）与 `gmdata.bin`（图片）两种封包的逆向结果。

**状态**

| 部分 | 状态 |
|---|---|
| `gmdata.bin` 容器结构 | ✅ 完全解出，可直接读 |
| `gmcode.bin` 容器结构（目录、文件名、偏移、大小） | ✅ 完全解出 |
| **两个封包的条目载荷编码** | ❌ **未解**，当前阻塞点 |

正是这个阻塞点让宿主暂时走"明文 `src/` 目录"模式（见 `src/pgm_pack.c`）。

---

## 1. 尾部结构（两个封包共有）

封包末尾是"目录 + 尾部信息"，且**文件名是明文**（不是加密的，这曾经让我
们走了弯路 —— 早期误以为整个文件都被加密）。

### gmdata.bin

```
[数据区 0 .. dir_start)        每个条目的内容按目录里的 offset/size 取
[目录区]                         N 条 × 124 字节
[尾部信息]                       88 字节
```

目录项（124 字节）：

| 偏移 | 类型 | 含义 |
|---|---|---|
| +0 | u32 | 数据在文件中的偏移 |
| +4 | u32 | 数据长度 |
| +8 | char[116] | 文件名，NUL 填充。**GBK 编码**，中文文件名原样存放 |

实测：62 条，目录起于 `0x34014e`，尾部 88 字节为
`{u32 dataEnd, u32 ?, u32 ver=1, u32 nums=63, u32 0, char info[]}`，
其中 `info` 是打包工具的参数字符串 —— 本例是 `"res files"`
（对应 `pack.bat` 里的 `pgrp -o ../src/files "res files"`）。

### gmcode.bin

同一套思路，但目录项是 **128 字节**：

| 偏移 | 类型 | 含义 |
|---|---|---|
| +0 | u32 | 保留（全 0） |
| +4 | u32 | 未知（疑似行数/块数） |
| +8 | u32 | 数据偏移 |
| +12 | u32 | 数据长度 |
| +16 | char[112] | 文件名，明文 GBK |

实测：43 条，目录起于 `0x43a3f`，43×128 + 96 = 5600 = 文件尾 - 0x43a3f ✓

偏移链首尾闭合（可以直接验证结构正确）：

```
条目 1  ce_init.lua    off=0        size=572     → 0 .. 572
条目 2  CGlist.lua     off=572      size=6496    → 572 .. 7068
条目 3  KeySetting.lua off=7068     size=212     → 7068 .. 7280
...
条目 42 first.ev       off=265680   size=11086   → 276766  ← 正好等于尾部的 dataEnd
```

43 个文件名也与 CE + 原版 v0.83 两套框架合起来完全对得上（`lg_init.lua`、
`ce_init.lua`、`TextLayer.lua`、`screen_rect.lua` … 都在）。

---

## 2. 条目载荷：未解的部分

假设目录给出的 `(offset, size)` 是对的，那么每个条目的载荷开头长这样：

```
ce_init.lua   (off=0,      size=572):
  0b 00 00 00 | 1f 77 7c 37 35 37 10 5f 14 5e 1e | 46 00 00 00 | 1f 77 7c 64 6d 7d ...

CGlist.lua    (off=572,    size=6496):
  0b 00 00 00 | 1f 77 7c 37 35 37 10 5f 14 5e 1e | 43 00 00 00 | 1f 77 7c 64 6d 7d ...

KeySetting.lua(off=7068,   size=212):
  0b 00 00 00 | 71 1d 03 15 19 13 64 13 40 10 7b | 09 00 00 00 | 3b 77 71 79 ...

lg_init.lua   (off=126578, size=13209):
  11 00 00 00 | 1f 77 7c 76 7f 6f 1f 1c 52 1f 54 57 51 4b 1f 1c 52 | 0f 00 00 00 | ...
```

### 已排除的假设

* **不是整体 XOR 加密**：长度字段是干净的 `u32`，如果整文件加密它们不会是 11/70 这种值。
* **不是单纯压缩**：`ce_init.lua` 明文 5931 字节、载荷 572 字节（约 10×），
  但 `CGlist.lua` 明文 186 字节、载荷却有 6496 字节（35× 膨胀）。压缩不可能既压又涨。
* **`[u32 len][len 字节]` 的 len 不是文件名长度**：`0b 00 00 00`（11）后面
  11 字节，在 `ce_init.lua` 和 `CGlist.lua` 两个不同文件的载荷里**完全相同**。
  同一个"名字"不可能是两个不同文件。
* **不是 Lua 5.1 字节码**：Lua 字节码头是 `1b 4c 75 61`（`\x1bLua`），这里没有。
* **不是 zlib/deflate**：`0x1f` 作为 deflate 首字节是 `BFINAL=1, BTYPE=11`（非法）。

### 下一步的确定路径

不再靠猜，直接读 `pgsp.exe` / `pgrp.exe` 的实现。两条可行路线：

1. **反汇编 ARM 版** —— `tools/PGMv0.83主引擎文件/ANDROID/PGMv0.8beta5.apk`
   里的 `libnge2app-jni.so` 含封包读取代码，ELF/ARM 比 x86 好读，符号表部分保留
   （已确认能 `nm -D` 出 `NGE2_GetTicks` 等符号）。
2. **差分实验** —— 用同一份明文源，构造不同内容再打包，比对输出。但没有可用的
   `pgsp.exe` 运行环境（本机无 Wine，Homebrew 又因 `/opt/homebrew` 属 root 装不了）。
   若之后修好 Homebrew，`brew install --cask wine-stable` 后即可做差分，
   这是最快能确定算法的方法。

### 另一个线索：`PGD_*` 操作码

《PGM指令表v0.7.md》里有一组 `PGD_*` 常量：

```
PGD_UNKNOWN, PGD_SINT8, PGD_UINT8, PGD_CODE, PGD_NEWLINE,
PGD_TABLE, PGD_COLOR, PGD_DCOLOR, PGD_DELAY, PGD_WAITKEY
```

这是**事件脚本（.ev）的二进制操作码**。所以 `.ev` 文件在打包时会被编译成操作码
序列 —— 这解释了为什么载荷不是明文 Lua。而 `.lua` 是否同样被编译，还需要验证。

---

## 3. 当前替代方案

在载荷解码完成之前，宿主用明文目录模式（`PGM_PACK_DIR`）：
`PackCreate("data/gmcode.bin")` 检测到是二进制封包后，转而从游戏的 `src/`
目录按文件名查找脚本。这样可以在不碰封包的前提下继续验证 Lua 宿主与 API。

`pgm_pack_open()` 里有一个 `looks_binary_pack()` 负责识别，将来补上解码后
只需在 `pgm_pack_read()` 里加 `PGM_PACK_BIN` 分支即可，上层无需改动。

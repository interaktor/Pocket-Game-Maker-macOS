# 骨架工程（starter/）

目标是让没接触过 PGM 的人，**十分钟内看到自己写的台词出现在屏幕上**。

## 三步

```sh
./scripts/build.sh Release          # 构建引擎（一次）
./scripts/new-project.sh 我的游戏    # 生成工程
cd 我的游戏 && ./run.sh             # 跑起来
```

然后编辑 `src/user/main.ev`，保存，重新运行。

## 为什么原版做不到这一点

原版的动手门槛有四道，全部拆掉了：

| 原版要求 | 这个移植版 |
|---|---|
| 先跑 `pgsp.exe` 打 `gmcode.bin` | **不需要打包**，直接读 `src/` |
| 再跑 `pgrp.exe` 打 `gmdata.bin` | 直接读 `src/files/` |
| 这两个是 Windows 程序 | 已在 macOS 原生跑，完全用不到 |
| 剧本必须存成 GBK，否则中文乱码 | 写 UTF-8 就行，加载时自动转 GBK |

后两条是关键。`pgsp.exe` / `pgrp.exe` 是 Windows 二进制，Mac 上根本跑不了；
而所有现代编辑器默认存 UTF-8，作者写完一看是乱码，得先研究编码问题。

### 实现方式

**零打包**（`src/pgm_pack.c`）：`pgm_pack_open()` 在封包文件不存在时自动切到
`PGM_PACK_DIR` 模式 —— 脚本包指向 `src/`，资源包指向 `src/files/`。目录读取先
按 `""`/`system/`/`user/`/`files/` 拼路径，找不到再按 basename 递归搜索，所以
图片可以随手丢进任意子目录。

**编码自动转换**（`text_normalize()`）：读 `.lua` / `.ev` 时先做 UTF-8 合法性校验。
合法且有非 ASCII 字符就调引擎自带的 `nge_charsets_utf8_to_gbk()` 转成 GBK 再交给
Lua；否则原样返回。转换不增删换行，所以 `.ev` 的物理行号不变（`goto` 依赖行号）。

想关掉：`PGM_MAC_NO_UTF8_FIX=1`。想看转换了什么：`PGM_TRACE_ENC=1`。

## 骨架里有什么

```
starter/
├── run.sh / 运行游戏.command   ← 双击就跑
├── README.md                  ← 给作者看的，讲怎么写台词
├── bin/
│   ├── engine.sys             ← 框架引导脚本（必需）
│   ├── pgm.ini                ← 窗口与路径配置
│   └── data/
│       ├── font/fz.ttf
│       ├── system/            ← 系统音效 + test.pmp
│       └── bgm/ sound/ voice/ video/   ← 空的，放你自己的东西
└── src/
    ├── am_start.ev            ← 入口，末尾 jump("main.ev")
    ├── pubdata.ev             ← 存档系统脚本
    ├── system/                ← 框架 40 个 .lua（别动）
    ├── user/main.ev           ← ★ 你唯一要改的文件
    └── files/
        ├── bg/                ← 背景（带一张占位图）
        ├── fg/                ← 立绘
        ├── system/ title/ gallery/ rule/   ← 系统 UI
```

## 编排上的两个决定

**入口改名。** 原版 `am_start.ev` 末尾是 `jump("first.ev")`，那个 `first.ev` 是
12 行的示例。骨架改成 `jump("main.ev")` —— "main" 比 "first" 更能让人明白该改哪个。

**框架放在 `src/system/`。** 包里的框架是平铺的（`pgsp` 打包时会拍平目录），但
散装模式下按子目录查找，所以放 `system/` 一样能加载，而且能让 `src/user/` 干净地
只剩作者自己的东西。

## 示例剧本用的写法

CE 框架推荐的组合是 `text(...)` + `textcl()` 配对：

```
text("旁白","中文直接写就行。")
textcl()
```

**`textcl()` 不能漏。** 它是"这句说完了，清屏"的意思；漏了下一句会接在同一行上。
CE 的 `say()` 里那句 `textclear()` 是被注释掉的（`SpeakScene.lua:850`），所以直接
连写多个 `say()` 会导致文字叠在一行 —— 这是原版行为，不是移植 bug。

选项用 `drawramus`，成对写"文字, 标签"：

```
drawramus("选项甲",*a,"选项乙",*b)
```

## 验证

```
$ ./run.sh
pack: data/gmcode.bin -> 目录模式 .../starter/src
pack: data/gmdata.bin -> 目录模式 .../starter/src/files
```

无 `!!` 报错，背景、消息框、中文、颜色、选项、跳转全部正常。
`PGM_MAC_FRAMES=420 PGM_MAC_AUTOKEY=20` 可自动跑完全部台词。

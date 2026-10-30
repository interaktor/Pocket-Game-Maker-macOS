# 你的第一个 PGM 游戏

这是一个可以直接跑起来的最小工程。**只需要改一个文件。**

---

## 先跑起来

双击 `运行游戏.command`（或终端里 `./run.sh`）。

跑不动的话，说明引擎还没编译过：

```bash
cd ../pgm-mac && ./scripts/build.sh Release
```

---

## 你只需要知道这一件事

**所有剧情都写在 `src/user/main.ev` 里。** 打开它，改里面的文字，保存，重新运行。

不用打包，不用编译，不用装任何工具。

---

## 写台词的固定套路

一句台词两行，`text(...)` 加 `textcl()`：

```
text("你好，世界。")
textcl()
```

带人名的：

```
text("旁白","中文直接写就行，不用管编码。")
textcl()
```

`textcl()` 是"这句话说完了，清屏"的意思。**漏了它，下一句会接在同一行上。**

---

## 放图片

把图片文件（png）丢进 `src/files/` 下的任意文件夹，剧本里写文件名：

```
bg("我的背景.png")              -- 换背景（自带淡入）
fg("我的立绘.png")              -- 放立绘，默认居中
fg("我的立绘.png",LEFT)         -- 靠左（还有 RIGHT）
fgcl()                          -- 清掉立绘
```

建议放的位置：

| 文件夹 | 放什么 |
|---|---|
| `src/files/bg/` | 背景图 |
| `src/files/fg/` | 立绘 |
| `src/files/title/` | 标题画面按钮 |
| `src/files/gallery/` | 画廊 CG |

其实位置无所谓 —— 引擎会按文件名去找，随便放哪个子目录都行。

图片建议 **480×272**，这是游戏分辨率。

---

## 放音乐

把 mp3 丢进 `bin/data/bgm/`，剧本里写文件名：

```
bgm("我的音乐.mp3")
bgmstop()
```

音效放 `bin/data/sound/`，语音放 `bin/data/voice/`。

> 注意：音频文件**不打包**，就是原样放在这几个文件夹里。

---

## 做选项

`drawramus` 后面成对写「选项文字, 跳转标签」，标签以 `*` 开头：

```
drawramus("再讲一遍",*again,"结束",*quit)

*again
text("好，那我们从头再来。")
textcl()
goto(*start)

*quit
...
```

`goto(*标签)` 跳到任意标签，`gotoif(条件,*标签)` 条件成立才跳。

---

## 换颜色

```
text("[c=FFD700]这句话是金色的。[/c]")
textcl()
```

`FFD700` 是 RGB 十六进制。可以混着用：

```
text("[c=FF0000]红[/c] [c=00FF00]绿[/c] [c=0000FF]蓝[/c]")
textcl()
```

---

## 这些文件夹别动

| 路径 | 是什么 |
|---|---|
| `bin/engine.sys` | 引擎引导脚本 |
| `bin/pgm.ini` | 窗口大小、路径配置 |
| `bin/data/system/` | 系统音效 |
| `bin/data/font/` | 字体（`fz.ttf`） |
| `src/system/` | 游戏框架的 40 个脚本 |
| `src/am_start.ev` | 启动入口，末尾 `jump("main.ev")` 指向你的剧本 |
| `src/pubdata.ev` | 存档系统的脚本 |

想改入口的话，改 `src/am_start.ev` 最后那行就行。

---

## 已实现 / 未实现

能用的：背景、立绘、台词、人名、颜色、选项、跳转、音乐、音效、存档、画廊、菜单。

**不支持 OGG 音频**（只能用 mp3 / wav）。

---

## 从哪来

PGM（Pocket Game Maker）是「掌机开发者之家」的白枫做的 PSP 文字游戏引擎。
这个工程是它在 macOS 上的移植版骨架。

许可：GPL-2.0-or-later。

# PGM for Mac

把 [Pocket Game Maker](https://github.com/History-exe/PGM_CE)（白枫 / 掌机开发者之家 的 PSP 文字游戏引擎）移植到 macOS。

**这个仓库本身就是一个能直接开工的工程**：下载下来改 `src/user/main.ev`，运行就看到效果。

---

## 双击就能跑

| 文件 | 干什么 |
|---|---|
| **`运行游戏.command`** | 双击：编译（第一次需要）/ 运行 |
| **`做新游戏.command`** | 双击：生成一个新的空工程 |

---

## 哪个文件夹放什么东西

```
bin/                        ← 运行时，一般不用动
├── engine.sys              框架引导脚本
├── pgm.ini                 窗口大小、路径配置
└── data/                   ★ 音频都放这里（不用打包，原样放）
    ├── bgm/                ★ 背景音乐（mp3）
    ├── sound/              ★ 音效（mp3 / wav）
    ├── voice/              ★ 语音（mp3）
    ├── video/              视频（pmp）
    ├── font/               字体 fz.ttf
    └── system/             系统音效，别删

src/                        ← 你的游戏内容
├── user/
│   └── main.ev             ★★★ 台词剧本，你主要改这个
├── files/                  ★ 图片都放这里
│   ├── bg/                 ★ 背景图
│   ├── fg/                 ★ 立绘
│   ├── title/              标题画面按钮
│   ├── gallery/            画廊 CG
│   ├── rule/               遮片
│   └── system/             系统 UI，别删
├── am_start.ev             入口，末尾 jump("main.ev")
├── pubdata.ev              存档系统，别动
└── system/                 框架 40 个 .lua，别动

engine/                     ← 引擎源码（不用看）
scripts/                    ← 构建、打包、生成工程
docs/                       ← 文档
```

图片位置其实**无所谓** —— 引擎按文件名递归查找，丢哪个子目录都能用，上面只是建议。

图片尺寸建议 **480×272**。

---

## 写台词

打开 `src/user/main.ev`。一句台词两行：

```
text("你好，世界。")
textcl()
```

带人名的：

```
text("旁白","中文直接写，UTF-8 就行，引擎会自动转 GBK。")
textcl()
```

**`textcl()` 不能漏。** 它是"这句说完了，清屏"的意思，漏了下一句会接在同一行。

变颜色：

```
text("[c=FFD700]金色[/c]  [c=00FF88]绿色[/c]")
textcl()
```

选项：

```
drawramus("再看一遍",*again,"我知道了",*quit)

*again
goto(*start)
```

`goto(*标签)` 跳转，`gotoif(条件,*标签)` 条件成立才跳。

---

## 放图片和音乐

把文件丢进对应文件夹，剧本里写文件名：

```
bg("我的背景.png")          -- 换背景（自带淡入）
fg("我的立绘.png")          -- 放立绘，默认居中
fg("我的立绘.png",LEFT)     -- 靠左（还有 RIGHT）
fgcl()                      -- 清掉立绘

bgm("我的音乐.mp3")         -- 放音乐
bgmstop()                   -- 停止
```

**都不需要打包。** 改完保存、重新运行就生效。

---

## 跑现成的 PGM 游戏

```sh
./build/Release/pgm-mac /path/to/游戏目录
```

做成双击就能开的 `.app`（游戏和依赖全打进去，拷到别的 Mac 也能跑）：

```sh
./scripts/make-app.sh Release /path/to/游戏目录
```

也可以把游戏文件夹**直接拖到 `PGM.app` 图标上**。

原版 PGM 游戏同时带 `gmcode.bin` / `gmdata.bin` 封包，这个版本能直接读；缺封包时自动改读散装目录（开发期用）。

---

## 首次编译

```sh
brew install libpng jpeg-turbo giflib freetype
# 或
sudo port install libpng libjpeg-turbo giflib freetype

./scripts/build.sh Release
```

`运行游戏.command` 会自动帮你跑这一步。

---

## 已知限制

- **不支持 OGG 音频**（只能用 mp3 / wav），AVFoundation 不解 OGG
- `mp3playtime()` 固定返回 0
- 实际出声需在有音频输出的机器上确认
- Intel Mac 未测试

---

## 许可

**BSD 3-Clause**。libnge2 作者 Kun Wang 于 2026-10-30 回信确认「按 BSD 许可证处理就行」
—— 源码里那些 GPL v2+ 文件头是当年的模板残留。

PGM 框架脚本（`src/system/` 等）版权归白枫 / 掌机开发者之家，许可尚未确认。
详见 `LICENSE`、`NOTICE.md`、`docs/LICENSING.md`。

## 致谢

- **白枫 / 掌机开发者之家** — Pocket Game Maker 原作者
- **Kun Wang** — libnge2 引擎作者
- **History-exe** — PGM 原版与社区版（CE）的维护

# PGM macOS v1.0.0

> 这份文件的内容可以直接粘到 GitHub 的 Releases 页面（选 tag `v1.0.0`）。

把 Pocket Game Maker（白枫 / 掌机开发者之家 的 PSP 文字游戏引擎）移植到 macOS。

## 这是什么

PGM 是 PSP 上的 AVG / 视觉小说引擎，游戏内容用 Lua 5.1 + `.ev` 事件脚本编写，
打包进 `gmcode.bin` / `gmdata.bin`。原版只有 PSP 和 Windows 版本。这个项目给底层的
libnge2 引擎新增了 macOS 后端，并重写了闭源的 PGM 宿主层，让现成的 PGM 游戏能在
Mac 上原生运行。

**同时兼容**原版 v0.83 和 PGM_CE 两个 Lua 框架 —— 两者的引擎二进制字节相同，
所以一套移植通吃。

## 能跑起来的部分

- 封包解码（`gmcode.bin` 的 `[u32 len][len bytes]` 记录 + 128 字节目录 + XOR 混淆 + 反 NUL 规则）
- 102 个 Lua API 绑定
- `.ev` 事件脚本解释器（`goto` / `gotoif` / 标签，行号与物理行 1:1 对应）
- 图形：图片、字体、精灵层、背景、场景合成、截图
- 对话系统、存档、特效（淡入淡出 / 抖动 / 转场）
- 键鼠输入（完整走 nge2 输入链路）
- 音频（AVFoundation / mp3 + wav + aac）

## 构建

```bash
# 依赖（二选一）
brew install libpng jpeg-turbo giflib freetype
sudo port install libpng libjpeg-turbo giflib freetype

# 一键构建（会自动检测 Homebrew / MacPorts 前缀）
./scripts/build.sh Release
```

产物在 `build/Release/pgm-mac`。跑起来：

```bash
PGM_MAC_FRAMES=60 PGM_MAC_SHOT=/tmp/shot.png ./build/Release/pgm-mac /path/to/game
```

打包成可双击的 `.app`（把游戏一起塞进去）：

```bash
./scripts/make-app.sh ./MyGame.app /path/to/game
```

三方库会被改写成 `@executable_path/../Frameworks/...` 并 ad-hoc 签名，
拷到别的 Mac 上不用装依赖。

## 已知限制

- **OGG 音频不支持**（AVFoundation 不解 OGG）
- `mp3playtime()` 固定返回 0
- 实际出声需要在有音频输出的机器上确认（开发环境无输出设备）
- Intel Mac 未测试
- 存档菜单交互未做完整回归测试

## 许可

PGM 宿主层代码为 GPL-2.0-or-later（依据 NGE2 源码中 43 个文件的 GPL v2+ 声明；
上游 README 写的是 BSD，GPL-2.0-or-later 是唯一在两种读法下都成立的选项）。
libnge2 保留其原始的 BSD 声明。原作者署名见 `NOTICE.md`。

## 致谢

- **白枫 / 掌机开发者之家** — Pocket Game Maker 原作者
- **Kun Wang \<ifreedom.cn@gmail.com\>** — libnge2 引擎作者
- **History-exe** — PGM 原版与社区版（CE）的存档与维护

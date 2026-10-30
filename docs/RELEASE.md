# 发布检查清单

记录发布到 GitHub 前需要确认的事项，以及已经验证过的内容。

## 已验证（从干净克隆复现）

```sh
git clone <repo> pgm-mac && cd pgm-mac
./scripts/build.sh Release          # 0 错误
./scripts/make-app.sh Release <游戏目录>
open build/PGM.app                  # 双击可运行
```

* 仓库 345 个文件 / 7.1 MB（不含 `build/`）
* 干净克隆构建：**0 错误**
* `PGM-CE`、原版 v0.83、`p1_smoke` 全部 `exit=0`
* `.app` 17 MB，5 个第三方 dylib 全部内嵌并改写成 `@executable_path`

## 仓库内容

| 部分 | 说明 |
|---|---|
| `src/` | PGM 宿主层（本项目原创，10 个 .c） |
| `scripts/` | 构建/打包/补丁/解包工具（本项目原创） |
| `tests/` | 渲染验收测试 |
| `docs/` | 逆向记录、移植笔记、许可证分析、致作者邮件 |
| `engine/third_party/libnge2/` | NGE2 源码（BSD/GPL，已打 macOS 补丁） |
| `engine/third_party/lua-5.1.4/` | Lua 源码（MIT） |

## 发布前还需确认

- [ ] `LICENSE` 用 GPL-2.0-or-later（原因见 `docs/LICENSING.md`）；
      **若 NGE2 作者回信确认 BSD，再改成 BSD-3-Clause**（见 `docs/AUTHOR-CONTACT.md`）
- [ ] `NOTICE.md` 里的署名与实际一致（白枫 / Kun Wang / History_exe）
- [ ] 确认**没有**把任何游戏资源打进仓库（本仓库不含游戏内容）
- [ ] README 顶部的"已知限制"是否如实（目前：无声音验证、仅 arm64）
- [ ] 决定是否提交 `docs/images/` 里的截图（目前 6 张，共约 350 KB）

## 推送

```sh
cd pgm-mac
git remote add origin git@github.com:<你的账号>/pgm-mac.git
git branch -M main
git push -u origin main
```

## 已知限制（发布时应在 README 里写明）

| 项 | 状态 |
|---|---|
| 音频 | 后端已实现（AVAudioPlayer），加载验证通过；**实际出声未在开发环境确认**；不支持 OGG |
| 平台 | 只在 macOS 14 / Apple Silicon 验证；Intel 与更早系统未测试 |
| 存档界面/菜单 | 未做完整交互回归 |
| CrystalTile2 等 Windows 原生工具 | 本项目不复刻，作者仍需 Wine 或 Windows |

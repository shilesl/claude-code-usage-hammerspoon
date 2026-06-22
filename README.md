# Claude Code 用量悬浮组件（Hammerspoon）

一个常驻 macOS 桌面右下角的悬浮卡片，实时显示 **Claude Code** 的用量：

- ⏳ **5 小时限额**：已用百分比 + 剩余时间 + 进度条
- 📅 **周限额**：已用百分比 + 剩余时间 + 进度条
- 今日 token 用量
- 两个窗口的重置时间，**同时显示两个时区**（默认 LA + 北京，24 小时制）

卡片始终置顶、跨所有桌面（Space）可见，可拖动，位置会被记住。进度条颜色随用量变化：绿 → 黄（≥50%）→ 红（≥80%）。

点右上角的 **－/＋** 可把卡片**收起 / 展开**：收起后只剩一行摘要（`🤖 5h xx%  周 xx%`），不占地方；展开恢复完整卡片。收起状态会被记住，重启后保持。

> 截图：把效果图放到这里 `docs/screenshot.png` 后取消下一行注释
> <!-- ![screenshot](docs/screenshot.png) -->

## 工作原理

```
ccusage ─┐
         ├─► claude-usage-data.sh ──(一行 JSON)──► init.lua（Hammerspoon 画卡片）
官方限额 ─┘
~/.claude-rate-limits.json
```

- **token 数据**来自 [`ccusage`](https://github.com/ryoppippi/ccusage)（`--offline` 模式，免联网）。
- **官方 5h / 周限额百分比与重置时间**来自 `~/.claude-rate-limits.json`，该文件由
  [claude-hud](https://github.com/) statusline 插件在每次刷新状态栏时写入。
  没有它也能跑，只是两条限额会显示「(无官方数据)」，只剩 token 一行有效。

## 依赖

| 依赖 | 用途 | 安装 |
|------|------|------|
| [Hammerspoon](https://www.hammerspoon.org/) | 渲染悬浮卡片 | `brew install --cask hammerspoon` |
| [ccusage](https://github.com/ryoppippi/ccusage) | token 用量 | `npm i -g ccusage` 或 `bun add -g ccusage` |
| python3 | 数据脚本里做时间/JSON 处理 | macOS 自带 / `brew install python` |
| claude-hud 插件（可选） | 提供官方限额百分比 | 见其仓库说明 |

## 安装

### 一键安装（推荐）

不用先 clone，一行搞定：

```bash
curl -fsSL https://raw.githubusercontent.com/shilesl/claude-code-usage-hammerspoon/main/install.sh | bash
```

或者 clone 之后在仓库目录里跑：

```bash
git clone https://github.com/shilesl/claude-code-usage-hammerspoon.git
cd claude-code-usage-hammerspoon
./install.sh
```

`install.sh` 会：检查并尝试装依赖 → 把数据脚本放到 `~/.claude-usage-data.sh` → 把组件作为模块放到
`~/.hammerspoon/claude_usage_hud.lua` → 在你的 `~/.hammerspoon/init.lua` **幂等地**注入一行
`require("claude_usage_hud")`（带标记，不动你原有配置，可反复运行）→ 自动 Reload Hammerspoon。

卸载：`./install.sh --uninstall`。

> 首次拖不动卡片，是因为缺辅助功能权限：**系统设置 → 隐私与安全性 → 辅助功能 → 勾选 Hammerspoon**。

### 手动安装

1. 装好上面的依赖。

2. 复制两个文件到对应位置：

   ```bash
   # 数据脚本（init.lua 里写死的路径就是这个）
   cp claude-usage-data.sh ~/.claude-usage-data.sh
   chmod +x ~/.claude-usage-data.sh

   # Hammerspoon 配置
   cp init.lua ~/.hammerspoon/init.lua
   ```

   > 已经有自己的 `~/.hammerspoon/init.lua`？把本仓库 `init.lua` 内容粘进去即可，它是自包含的；
   > 或把它存成 `~/.hammerspoon/claude_usage_hud.lua`，在自己的 init.lua 里加 `require("claude_usage_hud")`。

3. 在 Hammerspoon 菜单里点 **Reload Config**（或首次启动 Hammerspoon 并授予辅助功能权限）。

   加载成功会弹出「Claude 用量组件已加载(右上角 －/＋ 可收起)」。

## 配置

- **时区**：编辑 `claude-usage-data.sh` 顶部的：
  - `DISPLAY_TZ` / `TZ_LABEL`：第一个时区（默认 `America/Los_Angeles` / `LA`）。
  - `BJ_TZ` / `BJ_LABEL`：第二个时区（默认 `Asia/Shanghai` / `北京`）。

  重置时间使用 24 小时制（`%H:%M`）显示，两个时区各占一行。
- **卡片尺寸 / 边距 / 刷新频率**：编辑 `init.lua` 顶部的 `W, H`（展开尺寸）、`CW, CH`（收起尺寸）、`MARGIN`、以及 `hs.timer.doEvery(30, ...)`（默认 30 秒刷新一次）。
- **位置 / 收起状态**：直接拖动卡片即可，坐标与收起状态（`collapsed`）自动存到 `~/.hammerspoon/claude-hud-pos.json`。点右上角 `－/＋` 收起或展开。

> ⚠️ 本仓库里的文件只是源码，实际运行的是 `~/.claude-usage-data.sh` 和 Hammerspoon 里的副本
> （一键安装为 `~/.hammerspoon/claude_usage_hud.lua`，手动安装可能是 `~/.hammerspoon/init.lua`）。
> 改完仓库后重新跑 `./install.sh`（或重新 `cp`），再 Reload Config 才会生效。

## 调试

```bash
# 单独跑数据脚本，看输出的 JSON 是否正常
~/.claude-usage-data.sh

# 在 Hammerspoon 控制台里手动刷新
hs -c "refresh()"
```

显示「⚠️ 无数据」通常表示 `ccusage` 未安装或不在 PATH 里。

## License

[MIT](LICENSE)

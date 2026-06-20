# Claude Code 用量悬浮组件（Hammerspoon）

一个常驻 macOS 桌面右下角的悬浮卡片，实时显示 **Claude Code** 的用量：

- ⏳ **5 小时限额**：已用百分比 + 剩余时间 + 进度条
- 📅 **周限额**：已用百分比 + 剩余时间 + 进度条
- 今日 token 用量
- 两个窗口的重置时间（可配置时区）

卡片始终置顶、跨所有桌面（Space）可见，可拖动，位置会被记住。进度条颜色随用量变化：绿 → 黄（≥50%）→ 红（≥80%）。

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

1. 装好上面的依赖。

2. 复制两个文件到对应位置：

   ```bash
   # 数据脚本（init.lua 里写死的路径就是这个）
   cp claude-usage-data.sh ~/.claude-usage-data.sh
   chmod +x ~/.claude-usage-data.sh

   # Hammerspoon 配置
   cp init.lua ~/.hammerspoon/init.lua
   ```

   > 已经有自己的 `~/.hammerspoon/init.lua`？把本仓库 `init.lua` 的内容粘到你现有配置里即可，它是自包含的。

3. 在 Hammerspoon 菜单里点 **Reload Config**（或首次启动 Hammerspoon 并授予辅助功能权限）。

   加载成功会弹出「Claude 用量组件已加载(可拖动)」。

## 配置

- **时区**：编辑 `claude-usage-data.sh` 顶部的 `DISPLAY_TZ` / `TZ_LABEL`（默认 `America/Los_Angeles`）。
- **卡片尺寸 / 边距 / 刷新频率**：编辑 `init.lua` 顶部的 `W, H`、`MARGIN`、以及 `hs.timer.doEvery(30, ...)`（默认 30 秒刷新一次）。
- **位置**：直接拖动卡片即可，坐标自动存到 `~/.hammerspoon/claude-hud-pos.json`。

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

#!/usr/bin/env bash
#
# Claude Code 用量悬浮组件 —— 一键安装脚本
# ----------------------------------------------------------------------------
# 用法:
#   # 在克隆好的仓库目录里:
#   ./install.sh
#
#   # 或者一行远程安装(不需先 clone):
#   curl -fsSL https://raw.githubusercontent.com/shilesl/claude-code-usage-hammerspoon/main/install.sh | bash
#
#   ./install.sh --uninstall   # 卸载
#
# 做的事:
#   1) 检查依赖(Hammerspoon / ccusage / python3),缺失时尝试用 brew / npm 安装
#   2) claude-usage-data.sh → ~/.claude-usage-data.sh
#   3) init.lua            → ~/.hammerspoon/claude_usage_hud.lua(作为模块)
#   4) 在 ~/.hammerspoon/init.lua 注入一行 require(带标记,幂等,不动你原有配置)
#   5) 自动 Reload Hammerspoon
# ----------------------------------------------------------------------------
set -uo pipefail

REPO_RAW="https://raw.githubusercontent.com/shilesl/claude-code-usage-hammerspoon/main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"

HS_DIR="$HOME/.hammerspoon"
INIT_LUA="$HS_DIR/init.lua"
MODULE_LUA="$HS_DIR/claude_usage_hud.lua"
DATA_SCRIPT="$HOME/.claude-usage-data.sh"
RATE_FILE="$HOME/.claude-rate-limits.json"

MARKER_BEGIN="-- >>> claude-usage-hud (installer-managed) >>>"
MARKER_END="-- <<< claude-usage-hud <<<"
REQUIRE_LINE='require("claude_usage_hud")'

DO_UNINSTALL=0
for arg in "$@"; do
  case "$arg" in
    --uninstall) DO_UNINSTALL=1 ;;
    -h|--help)   sed -n '2,22p' "${BASH_SOURCE[0]:-$0}"; exit 0 ;;
    *) echo "未知参数: $arg" >&2; exit 2 ;;
  esac
done

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_dim="\033[2m"; c_off="\033[0m"
say()  { printf "${c_ok}✔${c_off} %s\n" "$*"; }
info() { printf "${c_dim}·${c_off} %s\n" "$*"; }
warn() { printf "${c_warn}!${c_off} %s\n" "$*"; }
err()  { printf "${c_err}✗${c_off} %s\n" "$*" >&2; }

backup() {  # 备份单个文件(若存在)
  local f="$1"; [[ -e "$f" ]] || return 0
  local b="$f.bak.$(date +%Y%m%d%H%M%S)"
  cp -p "$f" "$b" && info "已备份 $(basename "$f") → $(basename "$b")"
}

# 取仓库里的一个文件:优先用本地副本(已 clone),否则从 GitHub raw 下载
fetch() {  # fetch <仓库内文件名> <目标路径>
  local name="$1" dest="$2"
  if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/$name" ]]; then
    cp "$SCRIPT_DIR/$name" "$dest"
  else
    curl -fsSL "$REPO_RAW/$name" -o "$dest" \
      || { err "下载失败: $REPO_RAW/$name"; return 1; }
  fi
}

# ---------------------------------------------------------------------------
# 卸载
# ---------------------------------------------------------------------------
if [[ "$DO_UNINSTALL" == 1 ]]; then
  echo "== 卸载 Claude 用量 HUD =="
  if [[ -f "$INIT_LUA" ]]; then
    backup "$INIT_LUA"
    esc() { printf '%s' "$1" | sed 's/[][\.*^$/]/\\&/g'; }
    sed -i '' "/$(esc "$MARKER_BEGIN")/,/$(esc "$MARKER_END")/d" "$INIT_LUA" 2>/dev/null \
      && say "已从 init.lua 移除 require 标记块"
  fi
  rm -f "$MODULE_LUA"  && say "已删除 $MODULE_LUA"
  rm -f "$DATA_SCRIPT" && say "已删除 $DATA_SCRIPT"
  info "保留:$RATE_FILE、位置记忆 claude-hud-pos.json(如需可手动删)"
  command -v hs >/dev/null 2>&1 && hs -c "hs.reload()" >/dev/null 2>&1 && say "已重载 Hammerspoon"
  exit 0
fi

echo "== 安装 Claude Code 用量 HUD =="

# ---------------------------------------------------------------------------
# 1. 依赖
# ---------------------------------------------------------------------------
HAS_BREW=0; command -v brew >/dev/null 2>&1 && HAS_BREW=1

if command -v python3 >/dev/null 2>&1; then
  say "python3 OK"
else
  warn "缺少 python3"
  [[ "$HAS_BREW" == 1 ]] && { info "brew install python"; brew install python; }
  command -v python3 >/dev/null 2>&1 || err "python3 仍缺失,数据脚本无法运行"
fi

if [[ -d "/Applications/Hammerspoon.app" ]]; then
  say "Hammerspoon OK"
elif [[ "$HAS_BREW" == 1 ]]; then
  info "brew install --cask hammerspoon"; brew install --cask hammerspoon
else
  err "请先装 Hammerspoon: https://www.hammerspoon.org/ (或 brew install --cask hammerspoon)"
fi

if command -v ccusage >/dev/null 2>&1; then
  say "ccusage OK"
else
  warn "缺少 ccusage(token 会显示为 -)"
  if command -v npm >/dev/null 2>&1; then
    info "npm install -g ccusage"; npm install -g ccusage 2>/dev/null \
      && say "ccusage 安装成功" || warn "自动安装失败,可手动: npm i -g ccusage"
  else
    warn "请手动安装: npm i -g ccusage  或  bun add -g ccusage"
  fi
fi

mkdir -p "$HS_DIR"

# ---------------------------------------------------------------------------
# 2. 数据脚本
# ---------------------------------------------------------------------------
backup "$DATA_SCRIPT"
fetch "claude-usage-data.sh" "$DATA_SCRIPT" && chmod +x "$DATA_SCRIPT" \
  && say "已安装 $DATA_SCRIPT"

# ---------------------------------------------------------------------------
# 3. Hammerspoon 模块
# ---------------------------------------------------------------------------
backup "$MODULE_LUA"
fetch "init.lua" "$MODULE_LUA" && say "已安装 $MODULE_LUA"

# ---------------------------------------------------------------------------
# 4. 在 init.lua 注入 require(幂等)
# ---------------------------------------------------------------------------
if [[ ! -f "$INIT_LUA" ]]; then
  printf '%s\n%s\n%s\n' "$MARKER_BEGIN" "$REQUIRE_LINE" "$MARKER_END" > "$INIT_LUA"
  say "已创建 init.lua 并注入 require"
elif grep -qF "$MARKER_BEGIN" "$INIT_LUA"; then
  say "init.lua 已含 require 标记块(跳过)"
else
  backup "$INIT_LUA"
  if grep -qF "__claudeHud" "$INIT_LUA" && ! grep -qF "$REQUIRE_LINE" "$INIT_LUA"; then
    # 旧版:整份 init.lua 就是这套组件 → 换成模块 require
    printf '%s\n%s\n%s\n' "$MARKER_BEGIN" "$REQUIRE_LINE" "$MARKER_END" > "$INIT_LUA"
    say "检测到旧版内联组件,已替换为模块 require(原文件已备份)"
  else
    printf '\n%s\n%s\n%s\n' "$MARKER_BEGIN" "$REQUIRE_LINE" "$MARKER_END" >> "$INIT_LUA"
    say "已在 init.lua 末尾追加 require(保留原有配置)"
  fi
fi

# ---------------------------------------------------------------------------
# 5. 收尾
# ---------------------------------------------------------------------------
if [[ -f "$RATE_FILE" ]]; then
  say "检测到 $(basename "$RATE_FILE"),官方 5h/周百分比可显示"
else
  warn "暂无 $RATE_FILE —— 5h/周会显示「无官方数据」,只显示 token"
  info "官方百分比来源:安装 claude-hud statusline 插件后会自动写入该文件"
fi

if command -v hs >/dev/null 2>&1; then
  hs -c "hs.reload()" >/dev/null 2>&1 && say "已重载 Hammerspoon 配置" \
    || warn "hs CLI 调用失败,请在 Hammerspoon 菜单手动 Reload Config"
else
  warn "未找到 hs 命令行,请打开 Hammerspoon → 菜单 Reload Config"
  info "(如需 hs 命令:Hammerspoon 控制台执行 hs.ipc.cliInstall())"
  open -a Hammerspoon 2>/dev/null || true
fi

echo
say "完成 ✅  组件应已出现在屏幕右下角(可拖动,右上角 －/＋ 收起)"
info "首次拖不动:系统设置 → 隐私与安全性 → 辅助功能 → 勾选 Hammerspoon"

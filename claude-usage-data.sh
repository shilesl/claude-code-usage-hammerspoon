#!/usr/bin/env bash
#
# 共享数据脚本:输出一行 JSON,供 Hammerspoon / SwiftBar 复用。
# 数据源:
#   - token 数量          → ccusage(--offline)
#   - 5h/周限额百分比+重置 → ~/.claude-rate-limits.json(由 statusLine 包装脚本写入的官方数据)
#
DISPLAY_TZ="America/Los_Angeles"
TZ_LABEL="LA"                       # 显示给人看的时区名(可改 洛杉矶 / America/Los_Angeles 等)
BJ_TZ="Asia/Shanghai"              # 第二个时区:北京时间
BJ_LABEL="北京"
RATE_FILE="$HOME/.claude-rate-limits.json"

export PATH="/opt/homebrew/bin:$HOME/.local/bin:/usr/local/bin:$PATH"

CCUSAGE="$(command -v ccusage)"
if [[ -z "$CCUSAGE" ]]; then
  echo '{"error":"ccusage not found"}'
  exit 0
fi

# --offline:跳过联网拉价格,避免每次卡 ~10 秒
DAILY_JSON="$("$CCUSAGE" --json --offline 2>/dev/null)"
BLOCK_JSON="$("$CCUSAGE" blocks --active --json --offline 2>/dev/null)"

python3 - "$DAILY_JSON" "$BLOCK_JSON" "$DISPLAY_TZ" "$TZ_LABEL" "$RATE_FILE" "$BJ_TZ" "$BJ_LABEL" <<'PY'
import sys, json, os
from datetime import datetime, timedelta, timezone
try:
    from zoneinfo import ZoneInfo
except Exception:
    ZoneInfo = None

daily_raw, block_raw, disp_tz_name, tz_label, rate_file, bj_tz_name, bj_label = (sys.argv + [""]*7)[1:8]

def mk_tz(name):
    if ZoneInfo and name:
        try: return ZoneInfo(name)
        except Exception: return None
    return None

DISP_TZ = mk_tz(disp_tz_name)
BJ_TZ   = mk_tz(bj_tz_name)

def to_disp(dt):
    return dt.astimezone(DISP_TZ) if DISP_TZ else dt.astimezone()

def to_bj(dt):
    return dt.astimezone(BJ_TZ) if BJ_TZ else dt.astimezone()

def fmt_tokens(n):
    n = int(n or 0)
    if n >= 1_000_000: return f"{n/1_000_000:.2f}M"
    if n >= 1_000:     return f"{n/1_000:.1f}K"
    return str(n)

def fmt_dur(minutes):
    minutes = max(0, int(minutes))
    h, m = divmod(minutes, 60)
    if h >= 24:
        d, h = divmod(h, 24)
        return f"{d}d {h}h {m}m"
    return f"{h}h {m}m" if h else f"{m}m"

def fmt_dur_cn(minutes):
    minutes = max(0, int(minutes))
    h, m = divmod(minutes, 60)
    if h >= 24:
        d, h = divmod(h, 24)
        return f"{d}天{h}小时"
    if h:
        return f"{h}小时{m}分"
    return f"{m}分"

# ---- token(来自 ccusage)----
# daily.totals.totalTokens 是「所有天累计」,不是今天 —— 必须按 period 取当天那条。
today_tok = 0
week_tok = 0
month_tok = 0
try:
    days = json.loads(daily_raw).get("daily", []) or []
    today = to_disp(datetime.now(timezone.utc)).date()
    week_start = today - timedelta(days=6)          # 近 7 天(含今天)
    for e in days:
        p = e.get("period") or ""
        try:    d = datetime.strptime(p[:10], "%Y-%m-%d").date()
        except Exception: continue
        tok = int(e.get("totalTokens", 0) or 0)
        if d == today:               today_tok = tok
        if week_start <= d <= today: week_tok += tok
        if d.year == today.year and d.month == today.month: month_tok += tok  # 本月
except Exception:
    pass
try:    block_tok = json.loads(block_raw)["blocks"][0].get("totalTokens", 0) or 0
except Exception: block_tok = 0

# ---- 官方限额(来自 statusLine 写的文件)----
def read_window(w, with_date=False):
    """返回 (pct:int|None, reset:str, reset_bj:str, remain:str)
    with_date=True 时,reset 带日期(MM-DD HH:MM),用于跨天的周限额。"""
    w = w or {}
    pct = w.get("used_percentage")
    pct = int(pct) if isinstance(pct, (int, float)) else None
    ra = w.get("resets_at")
    reset, reset_bj, remain = "", "", ""
    dt = None
    if isinstance(ra, (int, float)) and ra > 0:                 # unix 秒(我们的 wrapper)
        dt = datetime.fromtimestamp(ra, tz=timezone.utc)
    elif isinstance(ra, str) and ra.strip():                   # ISO 字符串(claude-hud)
        try:
            dt = datetime.fromisoformat(ra.replace("Z", "+00:00"))
            if dt.tzinfo is None: dt = dt.replace(tzinfo=timezone.utc)
        except Exception:
            dt = None
    if dt:
        fmt = "%m-%d %H:%M" if with_date else "%H:%M"
        reset    = to_disp(dt).strftime(fmt)
        reset_bj = to_bj(dt).strftime(fmt)
        remain = fmt_dur((dt - datetime.now(timezone.utc)).total_seconds()/60)
    return pct, reset, reset_bj, remain, dt

five_pct=seven_pct=None
five_reset=five_reset_bj=five_remain=seven_reset=seven_reset_bj=seven_remain=""; rate_ok=False
seven_dt=None
try:
    with open(os.path.expanduser(rate_file)) as f:
        rl = json.load(f)
    five_pct,  five_reset,  five_reset_bj,  five_remain,  _        = read_window(rl.get("five_hour"))
    seven_pct, seven_reset, seven_reset_bj, seven_remain, seven_dt = read_window(rl.get("seven_day"), with_date=True)
    rate_ok = (five_pct is not None or seven_pct is not None)
except Exception:
    pass

# ---- 周重置周期已过去多少(7 天窗口里走了多远)----
seven_cycle_pct = None
seven_elapsed = ""
if seven_dt:
    total_min   = 7 * 24 * 60
    remain_min  = (seven_dt - datetime.now(timezone.utc)).total_seconds() / 60
    elapsed_min = max(0, min(total_min, total_min - remain_min))
    seven_cycle_pct = int(round(elapsed_min / total_min * 100))
    seven_elapsed   = fmt_dur_cn(elapsed_min)

print(json.dumps({
    "today_tokens": int(today_tok),
    "today_tokens_h": fmt_tokens(today_tok),
    "week_tokens": int(week_tok),
    "week_tokens_h": fmt_tokens(week_tok),
    "month_tokens": int(month_tok),
    "month_tokens_h": fmt_tokens(month_tok),
    "block_tokens": int(block_tok),
    "block_tokens_h": fmt_tokens(block_tok),
    "rate_ok": rate_ok,
    "five_pct": five_pct,
    "five_reset": five_reset,
    "five_reset_bj": five_reset_bj,
    "five_remain": five_remain,
    "seven_pct": seven_pct,
    "seven_reset": seven_reset,
    "seven_reset_bj": seven_reset_bj,
    "seven_remain": seven_remain,
    "seven_cycle_pct": seven_cycle_pct,
    "seven_elapsed": seven_elapsed,
    "tz_label": tz_label,
    "bj_label": bj_label,
}, ensure_ascii=False))
PY

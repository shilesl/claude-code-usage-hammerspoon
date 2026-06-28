-- Claude Code 用量 —— Hammerspoon 置顶悬浮组件(右下角,可拖动,始终可见)
-- 数据来自共享脚本 ~/.claude-usage-data.sh(含官方 5h/周限额百分比)
-- 右上角 －/＋ 可收起/展开;收起后只显示一行摘要,状态会被记住

require("hs.ipc")   -- 允许命令行 hs -c 调试

local DATA_SCRIPT = os.getenv("HOME") .. "/.claude-usage-data.sh"
local POS_FILE    = os.getenv("HOME") .. "/.hammerspoon/claude-hud-pos.json"
local W, H   = 250, 222   -- 展开尺寸
local CW, CH = 178, 34    -- 收起尺寸
local MARGIN = 24
local PAD = 16
local BAR_W = W - PAD * 2
local canvas = nil
local dragTap = nil
local dragOffset = { x = 0, y = 0 }
local state = { collapsed = false }

-- ---- 位置 / 收起状态记忆 ----
local function loadPos()
  local f = io.open(POS_FILE, "r"); if not f then return nil end
  local c = f:read("*a"); f:close()
  local ok, p = pcall(function() return hs.json.decode(c) end)
  if ok and p and type(p.x) == "number" and type(p.y) == "number" then return p end
  return nil
end
local function savePos(p)
  local f = io.open(POS_FILE, "w")
  if f then f:write(hs.json.encode({ x = p.x, y = p.y, collapsed = state.collapsed })); f:close() end
end

local function barColor(pct)
  if pct >= 80 then return { red = 0.95, green = 0.35, blue = 0.35, alpha = 0.95 } end
  if pct >= 50 then return { red = 0.96, green = 0.75, blue = 0.30, alpha = 0.95 } end
  return { red = 0.40, green = 0.80, blue = 0.55, alpha = 0.95 }
end

-- 周期进度条用中性蓝(它表示「时间走了多远」,高了不是坏事,不该变红报警)
local function cycColor(_)
  return { red = 0.45, green = 0.62, blue = 0.95, alpha = 0.95 }
end

-- 把坐标限制在屏幕内(防止拖出界或换分辨率后看不到)
local function clampToScreen(x, y, w, h)
  local f = hs.screen.primaryScreen():frame()
  x = math.max(f.x, math.min(x, f.x + f.w - w))
  y = math.max(f.y, math.min(y, f.y + f.h - h))
  return x, y
end

local toggleCollapse  -- 前置声明(供 mouseCallback 使用)

local function buildCanvas(collapsed)
  local w = collapsed and CW or W
  local h = collapsed and CH or H
  local f = hs.screen.primaryScreen():frame()
  local pos = loadPos()
  local x = pos and pos.x or (f.x + f.w - w - MARGIN)
  local y = pos and pos.y or (f.y + f.h - h - MARGIN)
  x, y = clampToScreen(x, y, w, h)

  local c = hs.canvas.new({ x = x, y = y, w = w, h = h })
  c:level(hs.canvas.windowLevels.floating)
  c:behavior({ "canJoinAllSpaces", "stationary" })
  c:clickActivating(false)

  -- 背景(可点按拖动,自动铺满整张画布)
  c:appendElements({ type = "rectangle", action = "fill", id = "bg",
    roundedRectRadii = { xRadius = 14, yRadius = 14 },
    fillColor = { red = 0.08, green = 0.09, blue = 0.11, alpha = 0.85 },
    strokeColor = { white = 1, alpha = 0.08 }, strokeWidth = 1,
    trackMouseDown = true })

  -- 右上角收起/展开按钮
  c:appendElements({ type = "text", id = "toggle",
    text = collapsed and "＋" or "－",
    textColor = { white = 1, alpha = 0.7 }, textSize = 14,
    textAlignment = "center",
    frame = { x = w - 26, y = collapsed and 7 or 7, w = 20, h = 20 },
    trackMouseDown = true })

  if collapsed then
    c:appendElements({ type = "text", text = "", id = "mini",
      textColor = { white = 1, alpha = 0.9 }, textSize = 12,
      frame = { x = PAD - 4, y = 8, w = w - PAD - 24, h = 18 } })
  else
    c:appendElements({ type = "text", text = "🤖 CLAUDE CODE 用量  ⠿",
      textColor = { white = 1, alpha = 0.6 }, textSize = 11,
      frame = { x = PAD, y = 9, w = W - PAD - 24, h = 16 } })

    -- 5h 行
    c:appendElements({ type = "text", text = "", id = "h5txt",
      textColor = { white = 1, alpha = 0.9 }, textSize = 12,
      frame = { x = PAD, y = 28, w = BAR_W, h = 16 } })
    c:appendElements({ type = "rectangle", action = "fill",
      roundedRectRadii = { xRadius = 3, yRadius = 3 },
      fillColor = { white = 1, alpha = 0.12 },
      frame = { x = PAD, y = 46, w = BAR_W, h = 6 } })
    c:appendElements({ type = "rectangle", action = "fill", id = "h5bar",
      roundedRectRadii = { xRadius = 3, yRadius = 3 },
      fillColor = barColor(0), frame = { x = PAD, y = 46, w = 0, h = 6 } })

    -- 周 行
    c:appendElements({ type = "text", text = "", id = "wktxt",
      textColor = { white = 1, alpha = 0.9 }, textSize = 12,
      frame = { x = PAD, y = 60, w = BAR_W, h = 16 } })
    c:appendElements({ type = "rectangle", action = "fill",
      roundedRectRadii = { xRadius = 3, yRadius = 3 },
      fillColor = { white = 1, alpha = 0.12 },
      frame = { x = PAD, y = 78, w = BAR_W, h = 6 } })
    c:appendElements({ type = "rectangle", action = "fill", id = "wkbar",
      roundedRectRadii = { xRadius = 3, yRadius = 3 },
      fillColor = barColor(0), frame = { x = PAD, y = 78, w = 0, h = 6 } })

    -- 周期 行(本周 7 天窗口已过去多久)
    c:appendElements({ type = "text", text = "", id = "cyctxt",
      textColor = { white = 1, alpha = 0.9 }, textSize = 12,
      frame = { x = PAD, y = 92, w = BAR_W, h = 16 } })
    c:appendElements({ type = "rectangle", action = "fill",
      roundedRectRadii = { xRadius = 3, yRadius = 3 },
      fillColor = { white = 1, alpha = 0.12 },
      frame = { x = PAD, y = 110, w = BAR_W, h = 6 } })
    c:appendElements({ type = "rectangle", action = "fill", id = "cycbar",
      roundedRectRadii = { xRadius = 3, yRadius = 3 },
      fillColor = cycColor(0), frame = { x = PAD, y = 110, w = 0, h = 6 } })

    c:appendElements({ type = "text", text = "", id = "tok",
      textColor = { white = 1, alpha = 0.55 }, textSize = 11,
      frame = { x = PAD, y = 124, w = BAR_W, h = 16 } })
    c:appendElements({ type = "text", text = "", id = "tokw",
      textColor = { white = 1, alpha = 0.55 }, textSize = 11,
      frame = { x = PAD, y = 140, w = BAR_W, h = 16 } })
    c:appendElements({ type = "text", text = "", id = "tokm",
      textColor = { white = 1, alpha = 0.55 }, textSize = 11,
      frame = { x = PAD, y = 156, w = BAR_W, h = 16 } })
    c:appendElements({ type = "text", text = "", id = "rst",
      textColor = { white = 1, alpha = 0.4 }, textSize = 10,
      frame = { x = PAD, y = 174, w = BAR_W, h = 14 } })
    c:appendElements({ type = "text", text = "", id = "rst2",
      textColor = { white = 1, alpha = 0.4 }, textSize = 10,
      frame = { x = PAD, y = 188, w = BAR_W, h = 14 } })
  end

  -- 鼠标:点 toggle 收起/展开;点背景拖动整张卡片
  c:mouseCallback(function(cv, ev, id, mx, my)
    if ev ~= "mouseDown" then return end
    if id == "toggle" then toggleCollapse(); return end
    local mp = hs.mouse.absolutePosition()
    local tl = cv:topLeft()
    dragOffset = { x = mp.x - tl.x, y = mp.y - tl.y }
    local cw = state.collapsed and CW or W
    local ch = state.collapsed and CH or H
    if dragTap then dragTap:stop() end
    dragTap = hs.eventtap.new({
      hs.eventtap.event.types.leftMouseDragged,
      hs.eventtap.event.types.leftMouseUp,
    }, function(e)
      local t = e:getType()
      if t == hs.eventtap.event.types.leftMouseDragged then
        local p = hs.mouse.absolutePosition()
        local nx, ny = clampToScreen(p.x - dragOffset.x, p.y - dragOffset.y, cw, ch)
        cv:topLeft({ x = nx, y = ny })
      else -- mouseUp
        if dragTap then dragTap:stop() end
        savePos(cv:topLeft())
      end
      return false
    end)
    dragTap:start()
  end)

  return c
end

local function el(id)
  for i = 1, #canvas do if canvas[i].id == id then return i end end
end
local function setText(id, txt) local i = el(id); if i then canvas[i].text = txt end end
local function setBar(id, pct, colorFn)
  local i = el(id); if not i then return end
  pct = math.max(0, math.min(100, pct or 0))
  canvas[i].frame = { x = PAD, y = canvas[i].frame.y, w = BAR_W * pct / 100, h = 6 }
  canvas[i].fillColor = (colorFn or barColor)(pct)
end

local function refresh()
  local out = hs.execute(DATA_SCRIPT)
  local ok, d = pcall(function() return hs.json.decode(out) end)
  if not ok or not d or d.error then
    setText("h5txt", "⚠️ 无数据"); setText("mini", "⚠️ 无数据"); return
  end
  local fp, sp = d.five_pct, d.seven_pct
  -- 收起态摘要
  setText("mini", "🤖 5h " .. (fp ~= nil and fp .. "%" or "-") ..
                  "  周 " .. (sp ~= nil and sp .. "%" or "-"))
  -- 展开态详情
  if fp ~= nil then
    setText("h5txt", "⏳ 5小时   " .. fp .. "%   剩 " .. (d.five_remain or "-")); setBar("h5bar", fp)
  else setText("h5txt", "⏳ 5小时   (无官方数据)") end
  if sp ~= nil then
    setText("wktxt", "📅 周限额  " .. sp .. "%   剩 " .. (d.seven_remain or "-")); setBar("wkbar", sp)
  else setText("wktxt", "📅 周限额  (无官方数据)") end
  local cp = d.seven_cycle_pct
  if cp ~= nil then
    setText("cyctxt", "🔄 周期    " .. cp .. "%   已过 " .. (d.seven_elapsed or "-")); setBar("cycbar", cp, cycColor)
  else setText("cyctxt", "🔄 周期    (无官方数据)") end
  setText("tok",  "今日 token  " .. (d.today_tokens_h or "-"))
  setText("tokw", "本周 token  " .. (d.week_tokens_h or "-"))
  setText("tokm", "本月 token  " .. (d.month_tokens_h or "-"))
  setText("rst",  "重置·" .. (d.tz_label or "LA") .. "   5h:" .. (d.five_reset or "-") .. "  周:" .. (d.seven_reset or "-"))
  setText("rst2", "重置·" .. (d.bj_label or "北京") .. "  5h:" .. (d.five_reset_bj or "-") .. "  周:" .. (d.seven_reset_bj or "-"))
end

local function rebuild()
  if canvas then canvas:delete() end
  canvas = buildCanvas(state.collapsed)
  canvas:show(); refresh()
  savePos(canvas:topLeft())  -- 记住(可能被 clamp 修正的)位置 + 收起状态
  if _G.__claudeHud then _G.__claudeHud.canvas = canvas end
end

-- 收起 ↔ 展开:保留当前左上角位置
toggleCollapse = function()
  local tl = canvas:topLeft()
  savePos(tl)                 -- 先把当前位置写回,buildCanvas 会读它
  state.collapsed = not state.collapsed
  rebuild()
end

-- ---- 启动 ----
local startPos = loadPos()
state.collapsed = (startPos and startPos.collapsed) == true
canvas = buildCanvas(state.collapsed); canvas:show(); refresh()

-- ⚠️ 定时器/监听器必须存进变量,否则会被 Lua GC 回收导致停止刷新
local refreshTimer = hs.timer.doEvery(30, refresh); refreshTimer:start()
local screenWatcher = hs.screen.watcher.new(function()
  rebuild()
end); screenWatcher:start()
local caffeineWatcher = hs.caffeinate.watcher.new(function(ev)
  if ev == hs.caffeinate.watcher.systemDidWake or ev == hs.caffeinate.watcher.screensDidUnlock then
    refresh()
  end
end); caffeineWatcher:start()

-- 防 GC
_G.__claudeHud = { canvas = canvas, refreshTimer = refreshTimer,
                   screenWatcher = screenWatcher, caffeineWatcher = caffeineWatcher }

hs.alert.show("Claude 用量组件已加载(右上角 －/＋ 可收起)")

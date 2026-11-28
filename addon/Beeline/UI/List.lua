-- The Route view of the Beeline window (UI/Window.lua): which path you follow, then your steps grouped under their
-- hub/section headers, the current one highlighted; mouse wheel scrolls; click a step to jump to it. "Show done" (a
-- toggle at the right of the line under the title) lists the whole plan, done steps dimmed with a tick.
local _, ns = ...
local Style = ns.Style
local C = Style.C
local List = {}
ns.List = List

local f
-- a row is ROW tall for one line of text; a long step wraps to a second line (the row a line taller), "..." only past
-- that. The rows are laid out from the top entry (f.offset) down, as many as fit the panel (List.DrawRows).
local ROW = 18
local vis = 20 -- the entries on screen at the last draw (List.DrawRows)
local rows = {} -- the pool: grows to the most rows that ever fit (all one line), reused after
local room = 0  -- the panel's height under the header, for rows (List.DrawHeader)
local entries = {} -- { header = text } or { index = i }
local scrollToCurrentSoon = function() end -- set once scrollToCurrent exists (below)
local builtFor, builtN   -- the step list (and its length) the entries were made from

local function rebuild()
  wipe(entries)
  List.rebuilds = (List.rebuilds or 0) + 1 -- (counted: the list must not be rebuilt on every engine refresh - tests)
  local data = BeelineData
  builtFor, builtN = data and data.steps, data and data.steps and #data.steps
  if not data then return end
  -- the list follows you, not the plan's history: done steps hidden (unless "Show done" - ns.db.hideDone == false), and
  -- the list starts where you are on the plan (steps before it are done or waiting on a level / a quest, and the card
  -- brings each up when it can be done). When the card is on a step out of plan order (a hand-in at the NPC you're at,
  -- loot counting for a later quest), that step comes first, as "Now", then "Next on your plan".
  local hide = ns.db.hideDone ~= false
  -- (not the step you clicked to look at)
  local cur, planned = (ns.Engine.view and ns.Engine.CardAt()) or ns.Engine.Shown(), ns.Engine.planned or ns.Engine.CardAt()
  local lastSec
  local function add(i)
    local st = data.steps[i]
    if st.sec ~= lastSec then
      lastSec = st.sec
      local sec = data.sections and data.sections[st.sec]
      -- (the zone once, not after a section titled by it)
      local named = sec and sec.zone and sec.title:lower():find(sec.zone:lower(), 1, true)
      entries[#entries + 1] = { header = sec and (sec.title .. ((sec.zone and not named) and ("  |cff8a93a6" .. sec.zone .. "|r") or "")) or "" }
    end
    entries[#entries + 1] = { index = i }
  end
  local from = 1
  if hide and cur and planned then
    if cur ~= planned then
      entries[#entries + 1] = { header = "|cff5cdc7aNow|r  |cff8a93a6out of plan order: " .. (ns.Engine.focusWhy == "progress" and "your kills / loot count for it" or ns.Engine.focusWhy == "ready" and "ready to hand in, right here" or "you're at it") .. "|r" }
      entries[#entries + 1] = { index = cur }
      entries[#entries + 1] = { header = "|cffb4bccaNext on your plan|r" }
      lastSec = nil
    end
    from = planned
  end
  for i = from, #data.steps do
    local pinned = hide and i == cur and cur ~= planned -- already shown as "Now"
    if not pinned and not (hide and i ~= cur and ns.Engine.IsDone(i)) then add(i) end
  end
end

-- the Route view of the Beeline window (UI/Window.lua): its panel is handed over the first time it is shown, and the
-- rows are made then (never at login)
local function build(panel)
  f = panel
  local IW = ns.Window.INNER
  -- which path you're following: name + badges, the zones in order, level/hours
  f.paths = CreateFrame("Frame", nil, f); f.paths:SetPoint("TOPLEFT", 0, 0); f.paths:SetPoint("TOPRIGHT", -8, 0); f.paths:SetHeight(60)
  f.paths.bg = Style.RowBg(f.paths, 10, 0.06, C.gold)
  f.pathLabel = Style.Text(f.paths, 9, C.dim, "OUTLINE"); f.pathLabel:SetPoint("TOPLEFT", 10, -8); f.pathLabel:SetText("FOLLOWING")
  f.pathName = Style.Text(f.paths, 12, C.text, "OUTLINE"); f.pathName:SetPoint("LEFT", f.pathLabel, "RIGHT", 6, 0); f.pathName:SetWordWrap(false)
  f.pathFast = Style.Pill(f.paths, "MOST ENJOYABLE", C.good)
  -- "Show done": a small toggle at the right of the line under the title (the view's own, not the window's)
  f.showDone = CreateFrame("Button", nil, f); f.showDone:SetSize(ns.Window.ACTION_W, 22)
  f.showDone:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, ns.Window.TOP - 46)
  Style.Check(f.showDone)
  f.showDone.text = Style.Text(f.showDone, 10, C.sub); f.showDone.text:SetPoint("LEFT", f.showDone.box, "RIGHT", 4, 0); f.showDone.text:SetText("Show done")
  f.showDone.sync = function(self)
    local on = ns.db.hideDone == false
    local c = on and C.text or C.sub
    self.text:SetTextColor(c[1], c[2], c[3]); Style.PaintCheck(self, on)
  end
  f.showDone:SetScript("OnClick", function(self)
    ns.db.hideDone = (ns.db.hideDone == false); List.Intro()
    rebuild(); scrollToCurrentSoon(); List.Draw(true)
  end)
  f.showDone:HookScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText("Show done", 1, 1, 1); GameTooltip:AddLine("Off: done steps hidden, the list starting where you are. On: the whole plan, with what you've done.", 0.72, 0.76, 0.84, true); GameTooltip:Show() end)
  f.showDone:HookScript("OnLeave", GameTooltip_Hide)
  f.showDone:sync()
  f.pathChips = CreateFrame("Frame", nil, f.paths); f.pathChips:SetPoint("TOPLEFT", 10, -26); f.pathChips:SetSize(IW - 28, 18)
  -- the plan's details (when and from what it was planned, which build) on hovering its name. There is no line of
  -- level, hours or quests left under the zones: "15 h left", "about 160 quests" and "To level 60" each read as wrong or
  -- said nothing (a built-in plan always goes to 60)
  f.metaHit = CreateFrame("Frame", nil, f.paths); f.metaHit:EnableMouse(true)
  f.metaHit:RegisterForDrag("LeftButton") -- (the window still drags from here)
  local win = ns.Window.Frame()
  f.metaHit:SetScript("OnDragStart", function() win:StartMoving() end); f.metaHit:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)
  f.metaHit:SetScript("OnEnter", function(self)
    local lines = List.MetaTip()
    if #lines == 0 then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText(lines[1], 1, 1, 1, 1, true)
    for k = 2, #lines do GameTooltip:AddLine(lines[k], 0.75, 0.8, 0.88, true) end
    GameTooltip:Show()
  end)
  f.metaHit:SetScript("OnLeave", GameTooltip_Hide)
  -- (the rows are made as they're needed: row() below)
  -- the text measured off screen, once per text (a header's font and a step's): List.TextHeight
  f.measure = { h = Style.Text(f, 11, C.text, "OUTLINE"), s = Style.Text(f, 11, C.text) }
  for _, m in pairs(f.measure) do m:SetWordWrap(true); if m.SetMaxLines then m:SetMaxLines(2) end; m:SetPoint("TOPLEFT", 0, 0); m:SetAlpha(0) end
  -- scrollbar: the wheel, or drag / click it (Style.ScrollGrip)
  f.track, f.thumb = Style.ScrollTrack(f, 3, 0.04)
  f.track:SetPoint("BOTTOMRIGHT", 2, 4)
  f.offset = 0
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, d) List.Scroll(-d * 3) end)
  -- drag it, or click to jump (a drag calls this every frame: drawn only when the top entry moved)
  f.grip = Style.ScrollGrip(f, f.track, f.thumb, function(fr)
    local o = math.floor(fr * math.max(0, #entries - vis) + 0.5)
    if o ~= f.offset then f.offset = o; List.Draw("rows") end
  end)
end

-- a row of the pool (made the first time a draw needs it, kept after: the pool grows to the most that ever fit)
local function row(k)
  if rows[k] then return rows[k] end
  local r = CreateFrame("Button", nil, f); r:SetHeight(ROW)
  r.hl = Style.Fill(r, "BACKGROUND"); r.hl:SetAllPoints()
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(12, 12); r.icon:SetPoint("LEFT", 14, 0)
  r.text = Style.Text(r, 11, C.text); r.text:SetWordWrap(true); r.text:SetJustifyV("MIDDLE"); r.text:SetJustifyH("LEFT")
  if r.text.SetMaxLines then r.text:SetMaxLines(2) end
  Style.Highlight(r, 0.05)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetScript("OnClick", function(self, btn) ns.Engine.Look(self.index, btn) end)
  r:SetScript("OnEnter", function(self)
    if not self.index then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Click to look · Right-click: map · Shift-click to jump here", 1, 1, 1)
    -- why not this one next? what the live solver says doing it first would cost
    local why = ns.Next and ns.Next.WhyNot and ns.Next.WhyNot(self.index)
    if why then GameTooltip:AddLine(why, 0.56, 0.6, 0.68, true) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", GameTooltip_Hide)
  rows[k] = r
  return r
end
function List.Rows() return rows end -- for tests

-- a row's height for a text: ROW for one line, a line more for two (the game puts "..." past the second). Each text
-- measured once for the panel's width, on a font string of its own (the text layout is the dear part of a redraw),
-- and only for the entries a draw shows.
local INSET = { h = 2, s = 14 + 12 + 7 } -- (where the text starts in a row: a header at its left, a step after its icon)
local textW, lineH, heights = nil, {}, { h = {}, s = {} }
local function setWidth(w)
  if w == textW then return end
  textW = w
  for kind, m in pairs(f.measure) do
    m:SetWidth(w - INSET[kind]); m:SetText("Ag"); lineH[kind] = m:GetStringHeight() or 12
    wipe(heights[kind])
  end
end
function List.TextHeight(text, kind)
  local h = heights[kind][text]
  if h then return h end
  local m = f.measure[kind]
  m:SetText(text)
  local sh, one = m:GetStringHeight() or 0, lineH[kind] or 12
  h = (one > 0 and sh > one * 1.5) and (ROW + math.floor(one + 0.5)) or ROW -- (two lines at most)
  heights[kind][text] = h
  return h
end

-- what an entry says: its text, its font (h: header, s: step), whether it is done
local function entryText(e, data)
  if e.header then return e.header, "h" end
  local isDone = ns.Engine.IsDone(e.index)
  local title = ns.Card.Describe(data.steps[e.index])
  local ch = ns.ChoiceFor and ns.ChoiceFor(e.index)
  if ch and not isDone then
    local names = {}
    for _, o in ipairs(ch.options) do names[#names + 1] = Style.ShortZone(o.zone) end
    title = title .. "  |cffffd25a(choose: " .. table.concat(names, " / ") .. ")|r"
  end
  if isDone then title = ns.Card.Plain(title) end
  return title, "s", isDone
end

-- the top entry within the list (the draw pulls it up when the last page has room left: List.DrawRows)
local function clampOffset() f.offset = math.max(0, math.min(#entries - 1, f.offset)) end

function List.Scroll(d)
  if d > 0 and f.offset + vis >= #entries then return end -- (the last entry on screen already)
  f.offset = f.offset + d; clampOffset()
  List.Draw("rows")
end

-- (the engine says "step" on every refresh, constantly on a flight: rebuilding the whole list and every step's status
-- each time stutters. So only when what it shows changed, or every few seconds for live counts; scrolling only
-- redraws the rows.)
--   List.Draw()        from the engine: nothing unless something changed
--   List.Draw("rows")  scrolled: the visible rows only
--   List.Draw(true)    opened, switched route: all of it
List.REDRAW_SECS = 5
local lastSig, lastAt = nil, 0
local passData, passFull
local function drawPass()
  local data, full = passData, passFull
  -- stops get added while the list is open (finished quests' hand-ins, side trips on the way, flight paths): those
  -- only redraw, so a stale list would put every header after the new stop one row off and lose the last step
  -- (with done steps hidden, the list changes as you play: rebuilt when it changed)
  if (full and ns.db.hideDone ~= false) or (data and data.steps) ~= builtFor or (data and data.steps and #data.steps) ~= builtN then
    rebuild(); clampOffset()
  end
  if full then List.DrawHeader(data) end
  List.DrawRows(data)
end
function List.Draw(mode)
  if not (f and ns.Window.IsShown("route")) then return end
  local data = BeelineData
  local E = ns.Engine
  local sig = table.concat({ tostring(data), tostring(data and data.steps), tostring(data and data.steps and #data.steps), tostring(E.Shown and E.Shown()),
    tostring(E.CardAt()), tostring(E.planned), tostring(E.view), tostring(E.focus), tostring(ns.db.hideDone) }, ":")
  local now = GetTime and GetTime() or 0
  local changed = sig ~= lastSig or now - lastAt >= List.REDRAW_SECS
  if mode == nil and not changed then return end
  local full = changed or mode == true
  if full then lastSig, lastAt = sig, now end
  passData, passFull = data, full
  -- (each step's status once for the whole draw: Engine.ReadPass)
  E.ReadPass(drawPass)
end
function List.DrawHeader(data)
  local list = ns.MainRoutes()
  local main = data and data.branch and ns.RouteById(data.parent) or data
  local idx = 1; for i, r in ipairs(list) do if r == main then idx = i end end
  local m = data and data.meta or {}
  if data then
    f.pathName:SetText(data.special and ("Side trip: " .. (data.dungeonName or data.title)) or data.dungeon and ("Dungeon route: " .. (data.dungeonName or data.title)) or data.zoneRoute and ("Home base: " .. Style.ShortZone(data.zoneName or "")) or data.branch and ("Path " .. idx .. ": " .. (data.title or "")) or (#list <= 1 and "Your plan") or ("Path " .. idx .. " of " .. #list))
    f.pathName:SetWidth(math.min(300, f.pathName:GetStringWidth() + 2))
    f.pathFast:ClearAllPoints(); f.pathFast:SetPoint("LEFT", f.pathName, "RIGHT", 6, 0)
    f.pathFast:SetShown(((data.best or m.best) and #list > 1) and true or false)
    -- the zones ahead from where you are on the route (not from level 1), with the hand-ins in each; the plan's own
    -- list for a route with nothing left to tell from
    local legs = {}
    -- (names only: the zones panel says how many)
    for _, z in ipairs(ns.Engine.ZonesAhead and ns.Engine.ZonesAhead(nil, 5) or {}) do
      local name = Style.ShortZone(z.zone)
      if legs[#legs] ~= name then legs[#legs + 1] = name end -- (two spellings of one zone side by side read as one)
    end
    if #legs == 0 then
      for z in (m.legs or data.title or ""):gmatch("[^>·]+") do z = z:gsub("^%s+", ""):gsub("%s+$", ""); if z ~= "" and legs[#legs] ~= z then legs[#legs + 1] = z end end
    end
    -- (a stop in a capital on the way is not a zone you go to)
    do local kept = {}; for _, z in ipairs(legs) do if not (ns.IsCapital and ns.IsCapital(z)) and kept[#kept] ~= z then kept[#kept + 1] = z end end; if #kept > 0 then legs = kept end end
    local hc = Style.Chips(f.pathChips, legs, ns.Window.INNER - 32, 5)
    f.pathChips:SetHeight(hc)
    f.metaHit:ClearAllPoints(); f.metaHit:SetPoint("TOPLEFT", f.pathLabel, "TOPLEFT", -2, 2); f.metaHit:SetPoint("BOTTOMRIGHT", f.pathName, "BOTTOMRIGHT", 2, -2); f.metaHit:Show()
    f.paths:SetHeight(26 + hc + 10)
  else
    f.pathName:SetText("No route loaded"); f.pathFast:Hide(); Style.Chips(f.pathChips, {}, ns.Window.INNER - 32); f.metaHit:Hide(); f.paths:SetHeight(30)
  end
  -- the step rows sit under the header, whatever its height
  -- (as many as fit in the panel under it: the window keeps its size)
  local top = f.paths:GetHeight() + 8
  f.top, room = top, math.max(ROW, (f:GetHeight() or 0) - top - 4)
  setWidth(math.floor((f:GetWidth() or 0) - 12 + 0.5))
  f.track:ClearAllPoints(); f.track:SetPoint("TOPRIGHT", 2, -top); f.track:SetPoint("BOTTOMRIGHT", 2, 4)
  clampOffset()
end
-- the rows from the top entry down, each as tall as its text (one line or two), as many as fit the room under the
-- header. At the end of the list with room left, the top entry moves up until the room is full: the last page always
-- ends on the last entry, and scrolling stops there.
local shown = {} -- (this draw's entries, first count of them: { text, kind, done, h, e }, the tables reused)
local function fill(data)
  local count, used = 0, 0
  for j = f.offset + 1, #entries do
    local text, kind, isDone = entryText(entries[j], data)
    local h = List.TextHeight(text, kind)
    if count > 0 and used + h > room then break end
    count = count + 1; used = used + h
    local s = shown[count] or {}; shown[count] = s
    s.text, s.kind, s.done, s.h, s.e = text, kind, isDone, h, entries[j]
  end
  return count, used
end
function List.DrawRows(data)
  if not textW then setWidth(math.floor((f:GetWidth() or 0) - 12 + 0.5)) end
  local cur = ns.Engine.Shown()
  local n = #entries
  local count, used = fill(data)
  if f.offset + count >= n and f.offset > 0 then
    local o = f.offset
    while o > 0 do
      local text, kind = entryText(entries[o], data)
      local h = List.TextHeight(text, kind)
      if used + h > room then break end
      used = used + h; o = o - 1
    end
    if o ~= f.offset then f.offset = o; count = fill(data) end
  end
  vis = math.max(1, count)
  local y = f.top or 0
  for k = 1, count do
    local s, r = shown[k], row(k)
    local e = s.e
    r.index = nil
    -- (anchored again only when it moved or changed height: an anchor set is a layout pass for the game)
    if r._y ~= y then r._y = y; r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("RIGHT", -12, 0) end
    if r._h ~= s.h then r._h = s.h; r:SetHeight(s.h) end
    y = y + s.h
    r:Show()
    if r._kind ~= s.kind then
      r._kind = s.kind
      r.text:ClearAllPoints()
      if s.kind == "h" then r.text:SetPoint("LEFT", 2, 0); r.text:SetFontObject(Style.Font(11, "OUTLINE"))
      else r.text:SetPoint("LEFT", r.icon, "RIGHT", 7, 0); r.text:SetFontObject(Style.Font(11)) end
      r.text:SetJustifyH("LEFT"); r.text:SetJustifyV("MIDDLE") -- (a font object brings its own)
      r._w = nil
    end
    local w = textW - INSET[s.kind]
    if r._w ~= w then r._w = w; r.text:SetWidth(w) end
    if r._t ~= s.text then r._t = s.text; r.text:SetText(s.text) end
    if s.kind == "h" then
      r.icon:Hide(); r.text:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
      Style.Paint(r.hl, C.white, 0.03)
    else
      r.index = e.index; r.icon:Show()
      Style.ListMark(r.icon, Style.Kind(data.steps[e.index]), s.done)
      local c = s.done and C.dim or C.white
      r.text:SetTextColor(c[1], c[2], c[3])
      if e.index == cur then Style.Paint(r.hl, C.gold, 0.16) else Style.Paint(r.hl, C.black, 0) end
    end
  end
  for k = count + 1, #rows do rows[k].index = nil; rows[k]:Hide() end
  n = math.max(1, n)
  local h = f.track:GetHeight()
  f.thumb:SetHeight(math.max(16, h * math.min(1, vis / n)))
  f.thumb:ClearAllPoints(); f.thumb:SetPoint("TOPRIGHT", f.track, "TOPRIGHT", 0, -(h - f.thumb:GetHeight()) * (f.offset / math.max(1, n - vis)))
end

-- the tooltip on the plan's name: how fresh the plan is (the companion replans after every save), or which build of a
-- built-in plan it is (CLAUDE.md, Versioning: what a bug report needs)
function List.MetaTip()
  local lines = {}
  local sk = ns.planKey and ns.planKey.starter
  if sk then
    local stamp = type(BeelineStarterStamp) == "table" and BeelineStarterStamp[sk]
    lines[1] = "Built-in plan"
    if stamp then lines[2] = stamp end
    return lines
  end
  local plan = BeelinePlan
  if plan and plan.generated and time then
    local ago = math.max(0, time() - plan.generated)
    local agoText = ago < 120 and "just now" or ago < 7200 and (math.floor(ago / 60) .. " min ago") or (math.floor(ago / 3600) .. " h ago")
    lines[1] = "Planned " .. agoText
    if plan.fromSave and plan.fromSave > 0 and date then lines[2] = "From your game as it was at " .. date("%H:%M", plan.fromSave) .. ", when it last saved (a reload or logging out saves it)." end
  end
  return lines
end

function List.Entries() return entries end   -- for tests

-- scroll so the current step sits in view
local function scrollToCurrent()
  if not f then return end
  local cur = ns.Engine.Shown()
  f.offset = 0
  -- (three entries above it: even all two lines tall, it is on screen; the draw pulls the last page up)
  for k, e in ipairs(entries) do if e.index == cur then f.offset = math.max(0, k - 4); break end end
end

scrollToCurrentSoon = function() scrollToCurrent() end
-- the line under the title says which list it is
function List.Intro()
  f.showDone:sync()
  ns.Window.SetIntro(ns.db.hideDone ~= false and "Your steps from where you are, under the zones they're in" or "Your whole plan, with what you've done")
end
local function open()
  List.Intro()
  rebuild()
  scrollToCurrent()
  List.Draw(true)
end
-- the Beeline window on the Route view; closed when it is on it already
function List.Toggle() ns.Window.Toggle("route") end
function List.Frame() return f end

ns.Window.Register("route", { label = "Route", icon = "btn-list", color = C.gold, title = "Route", group = 1, order = 1,
  tip = "Your steps from where you are, under the zones they're in",
  build = build,
  -- (the list, the done count and the zones ahead ask each step's status once between them)
  show = function() ns.Engine.ReadPass(open) end })
ns.On("FR_TOGGLE_LIST", function() List.Toggle() end)
ns.On("FR_STEP", function() List.Draw() end)
-- another path or "Back to my path": show where you are on it, not its first step
ns.On("FR_ROUTE_CHANGED", function() if f and ns.Window.IsShown("route") then rebuild(); scrollToCurrent(); List.Draw(true) end end)

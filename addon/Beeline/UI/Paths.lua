-- "Home base" (Paths internally): the Zones view of the Beeline window (UI/Window.lua).
--   The zones you could go to now (ns.ZoneChoices): the XP left there for you (and what share of your level that is),
--   quests left, hand-ins waiting, your plan's next zone marked PLANNED NEXT. Picking one takes you there. A companion's
--   other full plans fold under them.
-- The list scrolls in a window that keeps its size. Paths.Draw builds one state (Paths.State) and lays it out; each
-- kind of row has one paint function for its looks (selected, hover, kind), so they never stack oddly. Opened from the
-- card's side rail (Where to?) and its level-up line, /bee home (or /bee paths), FR_TOGGLE_PATHS.
local _, ns = ...
local Style = ns.Style
local C = Style.C
local Paths = {}
ns.Paths = Paths

local f -- the Zones view's panel (made the first time it is shown)
local W, PAD = ns.Window.W, ns.Window.PAD -- the panel's width with its padding
local ROW_H, ROW_GAP = 40, 4        -- a zone row
local CARD_H = 96                   -- a path card
local RIGHT_W = 120                 -- the numbers at a row's right

-- ---------------------------------------------------------------- looks

-- a zone row: its edge says what it is (best next gold, where you are green), hover lights it up
local function paintRow(b)
  local z = b.row or {}
  local col = z.best and C.gold or (z.here and C.good or C.dim)
  b.edge:SetVertexColor(col[1], col[2], col[3], (z.best or z.here) and 0.95 or 0.45)
  Style.SetRowBg(b.bg, b.hover and 0.09 or 0.04)
  local nc = (z.best and C.gold) or C.text
  b.name:SetTextColor(nc[1], nc[2], nc[3])
end

local function paintCard(c)
  local col = c.isCur and C.gold or (c.isBest and C.good or C.dim)
  c.edge:SetVertexColor(col[1], col[2], col[3], c.isCur and 0.95 or 0.5)
  Style.SetRowBg(c.bg, (c.hover or c.isCur) and 0.07 or 0.035)
end

local function hover(b, on, paint)
  b.hover = on; paint(b)
end

-- ---------------------------------------------------------------- widgets

local function setScroll(v) f.setScroll(v) end

-- rows and cards are kept by identity (a zone, a path id), so one keeps its look from one draw to the next
local rows, cards = {}, {}
Paths._rows = rows -- (the perf battery hovers one)

local function zoneRow(key)
  if rows[key] then return rows[key] end
  local b = CreateFrame("Button", nil, f.content)
  b:SetSize(W - 2 * PAD - 8, ROW_H)
  b.bg = Style.RowBg(b, 8, 0.04)
  b.edge = Style.RowEdge(b, 3, 1, 5)
  -- line 1: the zone's name, bounded by the numbers at the right (they never run into each other)
  b.right = Style.Text(b, 10, C.sub); b.right:SetPoint("TOPRIGHT", -10, -7); b.right:SetWidth(RIGHT_W); b.right:SetJustifyH("RIGHT"); b.right:SetWordWrap(false)
  b.name = Style.Text(b, 12, C.text, "OUTLINE"); b.name:SetPoint("TOPLEFT", 12, -6); b.name:SetPoint("RIGHT", b.right, "LEFT", -8, 0)
  b.name:SetJustifyH("LEFT"); b.name:SetWordWrap(false)
  -- line 2: what it is (a pill), then why, both bounded by the row's right edge
  b.pill = Style.Pill(b, "", C.gold); b.pill:SetPoint("TOPLEFT", 12, -22)
  b.why = Style.Text(b, 10, C.sub); b.why:SetJustifyH("LEFT"); b.why:SetWordWrap(false)
  b:SetScript("OnClick", function(self) if self.row then Paths.Pick(self.row) end end)
  b:SetScript("OnEnter", function(self)
    hover(self, true, paintRow)
    local z = self.row; if not z then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(z.zone, 1, 1, 1)
    if z.planned then GameTooltip:AddLine("Next on your plan. The plan weighs more than one zone's XP: the trip there, chains that carry on, what comes after it, and coming back to zones you've done. Picking it keeps you on your path.", 0.72, 0.76, 0.84, true)
    elseif z.route and z.xpLeft and z.xpLeft > 0 then GameTooltip:AddLine(string.format("About %s XP left there for you. Click to make it your home base: the route takes you there with the pick-ups on the way%s.", Paths.Short(z.xpLeft), (ns.HasCompanion and ns.HasCompanion()) and ", and your next plan is built from there" or ""), 0.72, 0.76, 0.84, true)
    elseif z.route then GameTooltip:AddLine("Click to make it your home base: the route takes you there with the pick-ups on the way, and your plan carries on from it.", 0.72, 0.76, 0.84, true)
    else GameTooltip:AddLine("No ready route at your level yet." .. ((ns.HasCompanion and ns.HasCompanion()) and " Click to ask the planner for one." or ""), 0.72, 0.76, 0.84, true) end
    -- the chain behind the row's reason (Chains.lua ns.ChainLine): how far you are, what's left, where it goes on
    local cq = z.contQ or (z.needs and z.needs.q)
    local cl = cq and ns.ChainLine and ns.ChainLine(cq)
    if cl then GameTooltip:AddLine(cl, 1, 0.82, 0.35, true) end
    if z.needs and (z.needs.xpMore or 0) > 0 then GameTooltip:AddLine("Doing " .. z.needs.name .. " first opens ~" .. Paths.Short(z.needs.xpMore) .. " more XP here.", 0.72, 0.76, 0.84, true) end
    -- going elsewhere: a chain you carry here that turns gray soon (ns.ChainsAtRisk)
    if not z.here and ns.ChainsAtRisk then local r = ns.ChainsAtRisk()[1]; if r and r.line then GameTooltip:AddLine("Leaving now: " .. r.line, 1, 0.45, 0.35, true) end end
    if z.questsLeft and z.questsLeft > 0 then GameTooltip:AddLine(z.questsLeft .. (z.questsLeft == 1 and " quest" or " quests") .. " you can do there now.", 0.72, 0.76, 0.84, true) end
    if z.handIns > 0 then GameTooltip:AddLine(z.handIns .. " quest" .. (z.handIns == 1 and " you finished is" or "s you finished are") .. " handed in there.", 0.36, 0.86, 0.48, true) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self) hover(self, false, paintRow); GameTooltip:Hide() end)
  rows[key] = b
  return b
end

local function legsOf(r)
  local out = {}
  for z in ((r.meta and r.meta.legs) or r.title or ""):gmatch("[^>·]+") do
    z = Style.ShortZone((z:gsub("^%s+", ""):gsub("%s+$", "")))
    if z ~= "" and out[#out] ~= z then out[#out + 1] = z end
  end
  -- (a stop in a capital on the way is not a zone you go to)
  do local kept = {}; for _, z in ipairs(out) do if not (ns.IsCapital and ns.IsCapital(z)) and kept[#kept] ~= z then kept[#kept + 1] = z end end; if #kept > 0 then out = kept end end
  return out
end

local function follow(r) if r then ns.SelectRoute(r.id); ns.char.pinnedPath = r.id; Paths.Draw() end end

local function pathCard(id)
  if cards[id] then return cards[id] end
  local c = CreateFrame("Button", nil, f.content)
  c:SetSize(W - 2 * PAD - 8, CARD_H)
  c.bg = Style.RowBg(c, 10, 0.035)
  c.edge = Style.RowEdge(c, 3, 1, 8)
  c.hours = Style.Text(c, 12, C.gold); c.hours:SetPoint("TOPRIGHT", -12, -10); c.hours:SetWidth(RIGHT_W); c.hours:SetJustifyH("RIGHT"); c.hours:SetWordWrap(false)
  c.name = Style.Text(c, 13, C.text, "OUTLINE"); c.name:SetPoint("TOPLEFT", 14, -10); c.name:SetWordWrap(false)
  c.pill = Style.Pill(c, "", C.gold); c.pill:SetPoint("LEFT", c.name, "RIGHT", 8, 0)
  c.chips = CreateFrame("Frame", nil, c); c.chips:SetPoint("TOPLEFT", 14, -32); c.chips:SetSize(W - 2 * PAD - 36, 20)
  c.go = Style.Button(c, "Follow", 80, 20, function(self) follow(self:GetParent().route) end)
  c.go:SetPoint("BOTTOMRIGHT", -12, 10)
  c.stats = Style.Text(c, 10, C.sub); c.stats:SetPoint("BOTTOMLEFT", 14, 14); c.stats:SetPoint("RIGHT", c.go, "LEFT", -8, 0)
  c.stats:SetJustifyH("LEFT"); c.stats:SetWordWrap(false)
  c:SetScript("OnClick", function(self) follow(self.route) end)
  c:SetScript("OnEnter", function(self)
    hover(self, true, paintCard)
    local r = self.route; if not r then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.name:GetText() or "Path", 1, 1, 1)
    GameTooltip:AddLine(table.concat(legsOf(r), " > "), 0.72, 0.76, 0.84, true)
    if r.rewards then GameTooltip:AddLine(r.rewards .. " good rewards", 0.72, 0.76, 0.84) end
    if r.dungeons and r.dungeons > 0 then GameTooltip:AddLine(r.dungeons .. (r.dungeons == 1 and " dungeon" or " dungeons"), 0.72, 0.76, 0.84) end
    GameTooltip:Show()
  end)
  c:SetScript("OnLeave", function(self) hover(self, false, paintCard); GameTooltip:Hide() end)
  cards[id] = c
  return c
end

-- ---------------------------------------------------------------- the window

local function build(panel)
  f = panel
  -- the list: scrolls inside a window that keeps its size
  Style.ScrollList(f, W - 2 * PAD, 60)
  f.scroll:SetPoint("TOPLEFT", 0, 0); f.scroll:SetPoint("BOTTOMRIGHT", -8, 24)
  f.track:SetPoint("TOPRIGHT", 2, 0); f.track:SetPoint("BOTTOMRIGHT", 2, 24)
  -- the bottom: one line (a zone you asked for, or how many more zones there are)
  f.foot = Style.Text(f, 10, C.sub); f.foot:SetPoint("BOTTOMLEFT", 0, 2); f.foot:SetPoint("RIGHT", f, "RIGHT", 0, 0); f.foot:SetWordWrap(false)
end

-- ---------------------------------------------------------------- state

Paths.PLANNED = "\1planned" -- (the planned route's row, picked from a zone you chose)
-- how many levels xp is from where you are now (your XP into this level counts: 40k to go at 35, 71k is about 1.4)
function Paths.Levels(xp)
  local T = ns.XP_TO_LEVEL or {}
  local L = (UnitLevel and UnitLevel("player")) or 1
  local have = (UnitXP and UnitXP("player")) or 0
  local out = 0
  xp = tonumber(xp) or 0
  while xp > 0 and L < 60 do
    local size = (L == ((UnitLevel and UnitLevel("player")) or 1) and UnitXPMax and UnitXPMax("player")) or T[L] or 0
    if size <= 0 then break end
    local need = size - have
    if xp < need then out = out + xp / size; break end
    out = out + need / size; xp = xp - need; have = 0; L = L + 1
  end
  return out
end
-- the level xp more takes you to ("to 36.4"), or nil when that is under a twentieth of a level
function Paths.ReachText(xp)
  local lv = Paths.Levels(xp)
  if lv < 0.05 then return nil end
  local L, m = (UnitLevel and UnitLevel("player")) or 1, (UnitXPMax and UnitXPMax("player")) or 0
  local at = L + (m > 0 and ((UnitXP and UnitXP("player")) or 0) / m or 0) + lv
  return string.format("to %.1f", math.min(60, math.floor(at * 10) / 10))
end
-- seconds -> "here", "2 min away", "1 h 10 away"
function Paths.Away(secs)
  local m = math.floor((secs or 0) / 60 + 0.5)
  if m < 1 then return "here" end
  if m < 60 then return m .. " min away" end
  return string.format("%d h %02d away", math.floor(m / 60), m % 60)
end
-- 14200 -> "14k", 1500 -> "1.5k", 950 -> "950"
function Paths.Short(n)
  n = tonumber(n) or 0
  if n >= 10000 then return string.format("%.0fk", n / 1000) elseif n >= 1000 then return string.format("%.1fk", n / 1000) end
  return tostring(math.floor(n))
end
-- a row picked: the zone you're on stays; your planned route's row on a zone you chose goes back to the route;
-- anything else is that zone's route, or a request for one (Paths.Request)
function Paths.Pick(row)
  local onZone = BeelineData and BeelineData.zoneRoute
  if row.planned then
    if onZone or (BeelineData and BeelineData.dungeon) then return Paths.Request(Paths.PLANNED) end
    ns.Window.Hide(); return -- (on your planned route already)
  end
  -- (the zone you stand in, not the route you are on: pick it to stay)
  if row.here and (not row.route or row.route == BeelineData) then ns.Window.Hide(); return end
  -- (no ready route: without the companion nothing can plan one - the row says "no route yet" and does nothing)
  if not row.route and not (ns.HasCompanion and ns.HasCompanion()) then return end
  return Paths.Request(row.zone, row.route)
end
-- route: the row's own route (a row is keyed by the zone its route works in, so the zone's name can find another
-- route than the one the row counted)
function Paths.Request(zone, route)
  ns.char.requestZone = zone; ns.char.requestHandled = nil
  -- a ready-made route into that zone: go now (the next replan builds your whole path from there, and the addon moves
  -- you onto it); without one, the planner makes it after your next save
  local zr = (route and route.zoneRoute and route) or (zone and ns.ZoneRouteFor and ns.ZoneRouteFor(zone))
  if zone == Paths.PLANNED then
    ns.char.requestZone = nil
    ns.Engine.Switch(function() ns.LeaveDungeonRoute(); ns.Fire("FR_ROUTE_CHANGED") end)
    Paths.Draw(); return
  end
  if zr then
    ns.Engine.Switch(function() ns.EnterZoneRoute(zr.id); ns.Fire("FR_ROUTE_CHANGED") end)
    if ns.Why then ns.Why("path", "home base: " .. zone .. " - on its ready-made route now, with the quests you carry there; your next plan starts there") end
    ns.Print("Home base: " .. zone .. ". Your plan's next zone is first in Where to? (on the card's side rail): it takes you back to your plan.")
  else
    ns.Print(zone and ("Asked for a path starting in " .. zone .. ". /reload to send it to the planner, then /reload once more to get it.") or "Cleared your zone request.")
  end
  Paths.Draw()
end

-- one line about a zone you asked for (nil: nothing asked)
function Paths.HelpText(list)
  local req = ns.char.requestZone
  if not req then return nil end
  for _, r in ipairs(list or {}) do if r.requested == req then return "|cff5cdc7aA path starting in " .. req .. " is ready under Paths.|r" end end
  local companion = ns.HasCompanion and ns.HasCompanion()
  if ns.ZoneRouteFor and ns.ZoneRouteFor(req) then return "|cff5cdc7aOn your way to " .. req .. ".|r" .. (companion and " Your next plan builds on from there." or "") end
  return companion and ("|cffffd25aAsked for " .. req .. ".|r /reload to send it to the planner, then /reload again.") or ("|cffffd25aNo ready route into " .. req .. " at your level.|r")
end

-- everything the window shows, worked out once per draw
local MAX_NO_ROUTE = 3
function Paths.State()
  local list = ns.MainRoutes()
  local st = { list = list, rows = {}, more = 0, moreNames = {}, level = 0 }
  local zc = ns.ZoneChoices and ns.ZoneChoices() or { rows = {} }
  st.level = zc.level or 0
  local noRoute = 0
  for _, z in ipairs(zc.rows) do
    if z.route or z.planned or z.handIns > 0 then st.rows[#st.rows + 1] = z
    elseif not (ns.HasCompanion and ns.HasCompanion()) then -- (nothing to click without the companion)
    else noRoute = noRoute + 1; if noRoute <= MAX_NO_ROUTE then st.rows[#st.rows + 1] = z else st.more = st.more + 1; st.moreNames[#st.moreNames + 1] = Style.ShortZone(z.zone) end end
  end
  -- the zone that pays most per hour, when it is not the planned one (a ready route: XP/h is that route's)
  st.help = Paths.HelpText(list)
  st.here = BeelineData and BeelineData.branch and ns.RouteById(BeelineData.parent) or BeelineData
  for _, r in ipairs(list) do if r.best or (r.meta and r.meta.best) then st.best = r end end
  return st
end

-- ---------------------------------------------------------------- layout

-- a zone route's kept trip out of its zone (tools/zone-confine.js marks it: Stranglethorn's flight to the Badlands for
-- Pearl Diving), said on its row in a few words - "+ Badlands pick-up" - so the trip isn't a surprise. Read once per
-- route table (the route's steps don't change while it is loaded)
local detourMemo = setmetatable({}, { __mode = "k" })
function Paths.DetourHint(route)
  if not (route and route.zoneRoute and type(route.steps) == "table") then return nil end
  local m = detourMemo[route]
  if m ~= nil then return m or nil end
  local v
  for _, s in ipairs(route.steps) do
    if s.detour and s.detourZone and s.k ~= "fly" then
      v = "+ " .. Style.ShortZone(s.detourZone) .. (s.detour == "giver" and " pick-up" or s.detour == "hand-in" and " hand-in" or " trip")
      break
    end
  end
  detourMemo[route] = v or false
  return v
end

local function layoutZones(st)
  local y = 0
  local onZone = BeelineData and BeelineData.zoneRoute
  for _, z in ipairs(st.rows) do
    local b = zoneRow(z.key)
    b.row = z
    b.name:SetText(Style.ShortZone(z.zone) .. (z.also and (" + " .. Style.ShortZone(z.also)) or ""))
    -- the XP left there for you, and how many levels that is from where you are: finish this zone, or go where there is
    -- more (levels, not a percent of one; the quest count is in the tooltip)
    local right = ""
    if z.xpLeft and z.xpLeft > 0 then
      -- (and the level that gets you to: "to 36.4" says at once whether the zone gets you your next level)
      local reach = Paths.ReachText(z.xpLeft)
      right = "~" .. Paths.Short(z.xpLeft) .. " XP" .. (reach and ("  ·  " .. reach) or "")
      -- (and how far: the trip there, once the background has priced it)
      if z.tripSecs and not z.here then right = right .. "  ·  " .. Paths.Away(z.tripSecs) end
    end
    b.right:SetText(right)
    -- the pill says what it is; the reason follows it
    -- PLANNED NEXT is what your plan does; the XP at the right says what each zone holds for you
    local picked = BeelineData and BeelineData.zoneRoute and z.route == BeelineData
    local onZoneRoute = BeelineData and BeelineData.zoneRoute
    local pill = (z.best and (onZoneRoute and "BACK TO PLAN" or "PLANNED NEXT")) or (picked and "HOME BASE") or (z.here and "YOU'RE HERE") or nil
    b.pill:SetShown(pill ~= nil)
    if pill then b.pill:Set(pill, z.best and C.gold or C.good) end
    local why = {}
    if z.best and z.here then why[#why + 1] = "you're here" end
    if z.planned then why[#why + 1] = z.via and ("pick up " .. (z.via.name or "a quest") .. " in " .. Style.ShortZone(z.via.zone) .. " first") or (onZone and "where your planned route picks up" or "next on your planned route") end
    -- one chain reason: hand-ins waiting, else a quest you carry there, else what it needs first
    if z.handIns > 0 then why[#why + 1] = z.handIns .. (z.handIns == 1 and " hand-in waiting" or " hand-ins waiting")
    elseif z.continues then why[#why + 1] = "continues " .. z.continues
    elseif z.needs then why[#why + 1] = "starts with " .. z.needs.name .. (z.needs.zone and (" (" .. Style.ShortZone(z.needs.zone) .. ")") or "") end
    if not z.route and not z.planned then why[#why + 1] = "no route yet" end
    -- (the route's trip out, last: it gives way when the row has two reasons already)
    local hint = #why < 2 and Paths.DetourHint(z.route)
    if hint then why[#why + 1] = hint end
    b.why:ClearAllPoints()
    if pill then b.why:SetPoint("LEFT", b.pill, "RIGHT", 8, 0) else b.why:SetPoint("TOPLEFT", 12, -23) end
    b.why:SetPoint("RIGHT", b, "RIGHT", -10, 0)
    while #why > 2 do table.remove(why) end -- (a third was cut off at the row's edge)
    b.why:SetText(table.concat(why, "  ·  "))
    paintRow(b)
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y); b:Show()
    y = y + ROW_H + ROW_GAP
  end
  return y
end

local function layoutPaths(st, y0)
  local y = y0 or 0
  for k, r in ipairs(st.list) do
    local c = pathCard(r.id)
    c.route, c.isCur, c.isBest = r, (r == st.here), (r == st.best)
    local m = r.meta or {}
    c.name:SetText("Path " .. k)
    -- one pill at most: FOLLOWING, else MOST ENJOYABLE
    local pill = (c.isCur and "FOLLOWING") or (c.isBest and "MOST ENJOYABLE") or nil
    c.pill:SetShown(pill ~= nil)
    if pill then c.pill:Set(pill, c.isCur and C.gold or C.good) end
    c.hours:SetText(m.hoursTo and string.format("~%s h to %s", m.hoursTo, m.target or 60) or (m.hours and ("~" .. m.hours .. " h")) or "")
    Style.Chips(c.chips, legsOf(r), W - 2 * PAD - 36, 4)
    local stats = {}
    local endLevel = tostring(m.endLevel or "?"):match("^(%d+)") or m.endLevel or "?"
    stats[#stats + 1] = string.format("Level %s to %s", m.startLevel or "?", endLevel)
    if r.story then stats[#stats + 1] = r.story .. " story quests" end
    if r.revisits then stats[#stats + 1] = r.revisits == 0 and "no backtracking" or (r.revisits .. " revisit" .. (r.revisits == 1 and "" or "s")) end
    if r.requested then stats[#stats + 1] = "starts in " .. Style.ShortZone(r.requested) end
    c.stats:SetText(table.concat(stats, "  ·  "))
    c.go.label:SetText(c.isCur and "Following" or "Follow"); c.go:SetEnabled(not c.isCur)
    paintCard(c)
    c:ClearAllPoints(); c:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y); c:Show()
    y = y + CARD_H + 8
  end
  return y - (y0 or 0)
end

-- a companion's other full plans, folded under the zones (picking one follows it)
Paths.showOthers = false
local function layoutOthers(st, y)
  if #st.list > 1 then
    f.others = f.others or Style.Button(f.content, "", 160, 20, function() Paths.showOthers = not Paths.showOthers; Paths.Draw() end, "Your companion's other full plans")
    f.others.label:SetText((Paths.showOthers and "Hide" or "Other plans") .. " (" .. #st.list .. ")")
    f.others:ClearAllPoints(); f.others:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -(y + 8)); f.others:Show()
    y = y + 36
    if Paths.showOthers then y = y + layoutPaths(st, y) end
  elseif f.others then f.others:Hide() end
  return y
end

function Paths.Draw()
  if not (f and ns.Window.IsShown("zones")) then return end
  local st = Paths.State()
  ns.Window.SetIntro(string.format("Level %d", st.level) .. (function() local m, h = UnitXPMax and UnitXPMax("player") or 0, UnitXP and UnitXP("player") or 0; return m > 0 and ("  ·  " .. Paths.Short(m - h) .. " XP to " .. (st.level + 1)) or "" end)() .. "  ·  pick a zone as your home base")
  for _, b in pairs(rows) do b:Hide() end
  for _, c in pairs(cards) do c:Hide() end
  if f.others then f.others:Hide() end
  local h = layoutOthers(st, layoutZones(st))
  f.content:SetHeight(math.max(h, 1))
  -- (by name, not just "+3 more zones")
  -- (a chain you carry here turning gray soon: said here, not only in a row's tooltip)
  local risk = ns.ChainsAtRisk and ns.ChainsAtRisk()[1]
  local foot = st.help or (risk and risk.line and ("|cffff7359Leaving now: " .. risk.line .. "|r")) or (st.more > 0 and ("Also at your level, no route yet: " .. table.concat(st.moreNames, ", "))) or nil
  f.foot:SetText(foot or ""); f.foot:SetShown(foot ~= nil)
  setScroll(f.scroll:GetVerticalScroll())
end

-- the Beeline window on Zones (the window is one: Show, Hide and IsShown speak for it)
function Paths.Show() ns.Window.Show("zones") end
function Paths.Hide() ns.Window.Hide() end
function Paths.IsShown() return ns.Window.IsShown("zones") end
-- open on Zones; closed when it is on Zones already
function Paths.Toggle() ns.Window.Toggle("zones") end

ns.Window.Register("zones", { label = "Zones", icon = "icon-where", color = C.good, title = "Home base", group = 1, order = 2,
  tip = "The zones you could go to now: pick one as your home base - you work from it until it runs out",
  build = build, show = function() setScroll(0); Paths.Draw() end })
ns.On("FR_TOGGLE_PATHS", function() Paths.Toggle() end)
ns.On("FR_ROUTE_CHANGED", function() Paths.Draw() end)
ns.On("FR_ZONETRIPS", function() Paths.Draw() end)

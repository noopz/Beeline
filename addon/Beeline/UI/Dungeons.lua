-- The side trips, four views of the Beeline window (UI/Window.lua), one per kind of trip: Class quests, Dungeons (a
-- group's going - pick its dungeon and get a route that picks up every quest for it, does the chain that unlocks them,
-- takes you there, then hands everything in; dungeon keys under them), Attunements and Special items (the Cozy Sleeping
-- Bag and other items worth a trip). Every party dungeon with a quest for your race and class is listed
-- (tools/dungeon-routes.js), the ones for your level first; what you've done drops out, and a kind with nothing left
-- for you has no sidebar item. Your leveling path is kept as it was; the card shows "Back to plan" while you're on one.
-- The four views share one panel. Opened from the sidebar, /bee dungeons (FR_TOGGLE_DUNGEONS), /bee class, /bee
-- attune, /bee items.
local _, ns = ...
local Style = ns.Style
local C = Style.C
local Dungeons = {}
ns.Dungeons = Dungeons

-- quest progress for a route, from the quest log; kept until a quest is picked up, handed in or dropped (a kill or a
-- loot redraws the window and changes none of it; asking the game each time is most of a redraw)
local progCache = {}
function Dungeons.Forget() progCache = {} end
-- the name players know a dungeon by, first (the list said only "The Temple of Atal'Hakkar": looking for the Sunken
-- Temple, you didn't see it - tester)
Dungeons.KNOWN_AS = { ["The Temple of Atal'Hakkar"] = "Sunken Temple (Temple of Atal'Hakkar)" }
function Dungeons.DisplayName(r) local n = r.dungeonName or r.title; return Dungeons.KNOWN_AS[n] or n end
for _, e in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED" }) do ns.On(e, function() progCache = {} end) end
local function progressOf(r)
  local c = progCache[r]
  if c then return c[1], c[2], c[3] end
  local total, done, inLog = 0, 0, 0
  for q in pairs(ns.QuestIds(r)) do
    if q > 0 then
      total = total + 1
      if ns.State.IsCompleted(q) then done = done + 1 elseif ns.State.OnQuest(q) then inLog = inLog + 1 end
    end
  end
  progCache[r] = { done, total, inLog }
  return done, total, inLog
end

local panel, host, W -- the side trips' panel, the frame in its scrolling list the cards go in, and its width
local cards = {}
-- the views: which trips each lists (a special trip by its group, Dungeons.GROUPS; "dungeon" a dungeon route)
Dungeons.VIEWS = {
  class = { kinds = { class = true }, label = "Class quests", title = "Class quests", icon = "icon-train", order = 10,
    intro = "Quests for your class: each a side trip that keeps your plan", empty = "No class quests left for you in this plan." },
  dungeons = { kinds = { dungeon = true, key = true }, label = "Dungeons", title = "Dungeons", icon = "icon-kill", order = 11,
    intro = "A group's going? Pick its dungeon: its quests, the run, the hand-ins. Your plan waits.", empty = "No dungeons in this plan." },
  attune = { kinds = { attune = true }, label = "Attunements", title = "Raids & attunements", icon = "icon-accept", order = 12,
    intro = "Attunements for raids and dungeons: each a side trip that keeps your plan", empty = "No attunements left for you in this plan." },
  reward = { kinds = { reward = true }, label = "Special items", title = "Special items", icon = "icon-loot", order = 13,
    intro = "Items worth a trip, like the Cozy Sleeping Bag: each a side trip that keeps your plan", empty = "No special items left for you in this plan." },
}
Dungeons.view = "dungeons" -- the side trips view on screen (or shown last)
-- a trip's kind: its group (class, attune, key, reward) or "dungeon"
function Dungeons.Kind(r) return r.special and Dungeons.Group(r).key or "dungeon" end

local function card(k)
  if cards[k] then return cards[k] end
  local c = CreateFrame("Frame", nil, host)
  c:SetWidth(W)
  c.bg = Style.RowBg(c, 10, 0.035)
  c.edge = Style.RowEdge(c, 3, 1, 8)
  c.name = Style.Text(c, 13, C.text, "OUTLINE"); c.name:SetPoint("TOPLEFT", 14, -10); c.name:SetWordWrap(false)
  c.cur = Style.Pill(c, "FOLLOWING", C.gold)
  c.quick = Style.Pill(c, "QUICK", C.good)
  c.special = Style.Pill(c, "SPECIAL REWARD", C.gold) -- (its text: the trip's group, Dungeons.GROUPS)
  c.time = Style.Text(c, 12, C.gold); c.time:SetPoint("TOPRIGHT", -14, -11); c.time:SetJustifyH("RIGHT")
  c.lvl = Style.Text(c, 10, C.sub); c.lvl:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -5); c.lvl:SetWordWrap(true); c.lvl:SetWidth(W - 150) -- clear of the button
  c.quests = Style.Text(c, 10, C.dim); c.quests:SetPoint("TOPLEFT", c.lvl, "BOTTOMLEFT", 0, -4); c.quests:SetWidth(W - 160)
  c.go = Style.Button(c, "Route me", 110, 22, function(self) local r = self:GetParent().route; if r then ns.EnterDungeonRoute(r.id); Dungeons.Redraw() end end)
  c.go:SetPoint("RIGHT", c, "RIGHT", -12, -6)
  cards[k] = c
  return c
end

-- the dungeons for your level are listed; the rest behind a button (each one listed is a card to draw and its quests to
-- ask the game about: all of them at once is several times dearer)
Dungeons.all = false
function Dungeons.Reset() Dungeons.all = false end
-- the side trips view on screen, or nil
local function shownView() local v = ns.Window.view; return Dungeons.VIEWS[v] and ns.Window.IsShown(v) and v or nil end
-- redraws the view on screen (none: nothing)
function Dungeons.Redraw()
  local v = shownView()
  if not (v and panel) then return end
  ns.Window.SetIntro(Dungeons.VIEWS[v].intro)
  local h = Dungeons.Draw(v)
  host:SetHeight(math.max(h, 1)); panel.content:SetHeight(math.max(h, 1))
  panel.setScroll(panel.scroll:GetVerticalScroll())
end

-- the panel (made the first time a side trips view is shown): a scrolling list the cards go in
local function build(p)
  panel = p
  W = ns.Window.INNER - 8
  Style.ScrollList(p, ns.Window.INNER, 60)
  p.scroll:SetPoint("TOPLEFT", 0, 0); p.scroll:SetPoint("BOTTOMRIGHT", -8, 4)
  p.track:SetPoint("TOPRIGHT", 2, 0); p.track:SetPoint("BOTTOMRIGHT", 2, 4)
  host = CreateFrame("Frame", nil, p.content); host:SetPoint("TOPLEFT", 0, 0); host:SetSize(W, 10)
  host.back = Style.Button(host, "Back to plan", 130, 20, function() ns.LeaveDungeonRoute(); Dungeons.Redraw() end)
  host.empty = Style.Text(host, 11, C.dim)
  host.heads = {}
end
function Dungeons.Host() return host end
function Dungeons.Cards() return cards end -- (tests)
-- draws view's list (default: the one shown last) into the frame from its top; returns its height
function Dungeons.Draw(view)
  local f = host
  if not f then return 0 end
  view = view or Dungeons.view
  local V = Dungeons.VIEWS[view] or Dungeons.VIEWS.dungeons
  local list, finished, more, prog = Dungeons.List(nil, Dungeons.all, view)
  local yc = 0
  local onDungeon = BeelineData and BeelineData.dungeon
  f.back:ClearAllPoints(); f.back:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0); f.back:SetShown(onDungeon and true or false)
  if onDungeon then yc = yc + 28 end
  for k, c in ipairs(cards) do if k > #list then c:Hide() end end
  f.empty:SetShown(#list == 0)
  if #list == 0 then f.empty:ClearAllPoints(); f.empty:SetPoint("TOPLEFT", 0, -yc); f.empty:SetText(finished > 0 and "You've done every one of these in this plan." or V.empty); yc = yc + 24 end
  local myLevel = UnitLevel("player") or 1
  for _, h in pairs(f.heads) do h:Hide() end
  local function head(key, text)
    local h = f.heads[key] or Style.Text(f, 12, C.gold, "OUTLINE"); f.heads[key] = h
    h:ClearAllPoints(); h:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -yc); h:SetText(text); h:Show()
    yc = yc + 20
  end
  -- (headings only when the view lists more than one kind: Dungeons with its keys)
  local kinds = 0; do local seen = {}; for _, r in ipairs(list) do local kd = Dungeons.Kind(r); if not seen[kd] then seen[kd] = true; kinds = kinds + 1 end end end
  local lastKind
  for k, r in ipairs(list) do
    local g = r.special and Dungeons.Group(r) or nil
    local kind = g and g.key or "dungeon"
    if kind ~= lastKind then if kinds > 1 then head(kind, g and g.head or "Dungeons") end; lastKind = kind end
    local c = card(k)
    if g then c.special:Set(g.pill) end
    c.route = r
    local isCur = (BeelineData == r)
    local zc = Style.ZoneColor(r.dungeonName or r.title)
    c.name:SetText(Dungeons.DisplayName(r)); c.name:SetTextColor(zc[1], zc[2], zc[3])
    c.quick:ClearAllPoints(); c.quick:SetPoint("LEFT", c.name, "RIGHT", 8, 0); c.quick:SetShown(r.variant == "quick")
    c.special:ClearAllPoints(); c.special:SetPoint("LEFT", c.name, "RIGHT", 8, 0); c.special:SetShown(r.special and true or false)
    local tag = (r.variant == "quick" and c.quick) or (r.special and c.special) or nil
    c.cur:ClearAllPoints(); c.cur:SetPoint("LEFT", tag or c.name, "RIGHT", tag and 4 or 8, 0); c.cur:SetShown(isCur)
    local pr = prog[r] or { 0, 0, 0 }
    local done, total, inLog = pr[1], pr[2], pr[3]
    local mins = r.meta and r.meta.hours and math.floor(tonumber(r.meta.hours) * 60 + 0.5)
    -- (planned with nothing done: with some done it's quicker, so "up to")
    c.time:SetText(mins and ((done > 0 and "up to " or "~") .. mins .. " min") or "")
    -- the name, its pills and the time on one line: a long name gives way ("...") - "Seal of Ascension (Upper Blackrock
    -- Spire key)" ran its DUNGEON KEY pill under the minutes (tester)
    local pills = 0
    for _, p in ipairs({ c.quick, c.special, c.cur }) do if p:IsShown() then pills = pills + (p:GetWidth() or 0) + 8 end end
    c.name:SetWidth(0)
    local room = W - 28 - (c.time:GetStringWidth() or 0) - 12 - pills
    c.name:SetWidth(math.max(40, math.min(c.name:GetStringWidth() or 0, room)))
    local need = tonumber(r.needsLevel) or 0
    local lvlText = string.format("Quests around level %s", r.questLevel or "?")
    if need > myLevel then lvlText = lvlText .. "  ·  |cffff8c4dsome need level " .. need .. "|r" end
    c.lvl:SetText(lvlText .. string.format("  ·  %d of %d quest%s left", total - done, total, total == 1 and "" or "s") .. (inLog > 0 and string.format(", %d in your log", inLog) or "") .. ((tonumber(r.xp) or 0) > 0 and string.format("  ·  |cffffd25a%.1fk XP|r", r.xp / 1000) or ""))
    if r.special then
      c.lvl:SetText(string.format("Can start at level %s  ·  %d quest%s", r.needsLevel or "?", total, total == 1 and "" or "s") .. (done > 0 and string.format(" (%d done)", done) or "") .. (inLog > 0 and string.format(", %d in your log", inLog) or ""))
      c.quests:SetText((r.why or "") .. "\n|cff8a93a6" .. ((r.meta and r.meta.legs) or "") .. "|r")
    else
    c.quests:SetText("For the dungeon: " .. (r.quests or "") .. ((r.chainCount or 0) > 0 and string.format("  |cff8a93a6+ %d chain quest%s that unlock them|r", r.chainCount, r.chainCount == 1 and "" or "s") or "")
      .. (r.cut and ("\n|cffffb36bSkips: " .. r.cut .. "|r") or ""))
    end
    -- the trip you are on: what it leaves for later at your level (ns.Dungeon.Later: can't take yet, red to you, put
    -- off), each by the level it comes back at, a chain as one entry - none of it is off the trip
    local later = isCur and ns.Dungeon and ns.Dungeon.Later and ns.Dungeon.Later(r, myLevel)
    if later and #later > 0 then
      local rows = {}
      for _, g in ipairs(later) do
        local names = {}
        for _, e in ipairs(g.quests) do names[#names + 1] = ns.Dungeon.LaterText(e) end
        if g.item then
          for n, e in ipairs(g.quests) do names[n] = names[n] .. " (" .. e.reason .. ")" end
          rows[#rows + 1] = "Once you have its item: " .. table.concat(names, ", ")
        else rows[#rows + 1] = "At level " .. g.at .. ": " .. table.concat(names, ", ") end
      end
      c.quests:SetText((c.quests:GetText() or "") .. "\n\n|cffffb36bLater on this trip|r |cff8a93a6(back by itself at its level)|r\n" .. table.concat(rows, "\n"))
    end
    c.go.label:SetText(isCur and "Following" or "Route me"); c.go:SetEnabled(not isCur)
    local col = isCur and C.gold or zc
    c.edge:SetVertexColor(col[1], col[2], col[3], isCur and 0.95 or 0.5)
    c.quests:ClearAllPoints(); c.quests:SetPoint("TOPLEFT", c.lvl, "BOTTOMLEFT", 0, -4)
    local h = 10 + 16 + 5 + c.lvl:GetStringHeight() + 4 + c.quests:GetStringHeight() + 12
    c:SetHeight(math.max(64, h))
    c:ClearAllPoints(); c:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -yc); c:Show()
    yc = yc + c:GetHeight() + 8
  end
  if finished > 0 and #list > 0 then head("finished", string.format("|cff8a93a6%d more with nothing left for you|r", finished)) end
  -- the other dungeons: a group going to one not at your level
  f.more = f.more or Style.Button(f, "", 200, 22, function() Dungeons.all = not Dungeons.all; Dungeons.Redraw() end)
  f.more:SetShown(Dungeons.all or more > 0)
  if Dungeons.all or more > 0 then
    f.more.label:SetText(Dungeons.all and "Only the ones for my level" or string.format("All dungeons (%d more)", more))
    f.more:ClearAllPoints(); f.more:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -yc); yc = yc + 30
  end
  return yc
end

-- what the window lists, in order: the dungeons, those for your level first (quests around your level, then the ones
-- above it, then the ones below), then the special rewards; a route with nothing left for you (every quest done) is
-- left out and counted. Without all: only the dungeons around your level (at most 6; the 3 nearest when none is).
-- Returns the list, how many were left out as done, how many dungeons more "all" would list, and each listed route's
-- progress ({ done, total, in your log }). view (a key of Dungeons.VIEWS): only that view's kinds; nil: every kind.
local SHOWN = 6
-- the side trips that aren't dungeons, by what they get you (the plan's group = ..., tools/reviewed-<faction>.json), in
-- the window's order: a heading and a tag each
Dungeons.GROUPS = {
  { key = "class", head = "Class quests", pill = "CLASS QUEST" },
  { key = "attune", head = "Attunements", pill = "ATTUNEMENT" },
  { key = "key", head = "Dungeon keys", pill = "DUNGEON KEY" },
  { key = "reward", head = "Special rewards", pill = "SPECIAL REWARD" },
}
local groupBy = {}; for i, g in ipairs(Dungeons.GROUPS) do g.order = i; groupBy[g.key] = g end
-- (a plan from before trips had a group: special rewards, as they all were)
function Dungeons.Group(r) return groupBy[r.group] or groupBy.reward end
function Dungeons.List(level, all, view)
  local kinds = view and Dungeons.VIEWS[view] and Dungeons.VIEWS[view].kinds
  level = level or (UnitLevel and UnitLevel("player")) or 1
  -- 0: around your level (from 4 below to 4 above), 1: above it, 2: below it (gray to you: little XP)
  local function band(r) local q = tonumber(r.questLevel) or 0; return (q > level + 4 and 1) or (q < level - 4 and 2) or 0 end
  local function dist(r) return math.abs((tonumber(r.questLevel) or 0) - level) end
  local dung, spec, finished, prog = {}, {}, 0, {}
  local function keep(r, into)
    local done, total, inLog = progressOf(r)
    if total > 0 and done >= total then finished = finished + 1; return end
    prog[r] = { done, total, inLog }; into[#into + 1] = r
  end
  local cand = {}
  for _, r in ipairs(ns.DungeonRoutes()) do
    if not kinds or kinds[Dungeons.Kind(r)] then if r.special then keep(r, spec) else cand[#cand + 1] = r end end
  end
  local more = 0
  if all then for _, r in ipairs(cand) do keep(r, dung) end
  else
    -- the nearest first (no game calls for the ones left out)
    table.sort(cand, function(a, b) local da, db = dist(a), dist(b); if da ~= db then return da < db end return (a.dungeonName or "") < (b.dungeonName or "") end)
    local inBand = 0; for _, r in ipairs(cand) do if band(r) == 0 then inBand = inBand + 1 end end
    local take = inBand > 0 and math.min(SHOWN, inBand) or math.min(3, #cand)
    for i, r in ipairs(cand) do if i <= take then keep(r, dung) else more = more + 1 end end
  end
  table.sort(dung, function(a, b)
    local ba, bb = band(a), band(b)
    if ba ~= bb then return ba < bb end
    local qa, qb = tonumber(a.questLevel) or 0, tonumber(b.questLevel) or 0
    if qa ~= qb then if ba == 2 then return qa > qb end return qa < qb end
    return (a.dungeonName or a.title or "") < (b.dungeonName or b.title or "")
  end)
  -- (by group, each in the plan's own order)
  local at = {}; for i, r in ipairs(spec) do at[r] = i end
  table.sort(spec, function(a, b) local ga, gb = Dungeons.Group(a).order, Dungeons.Group(b).order; if ga ~= gb then return ga < gb end return at[a] < at[b] end)
  for _, r in ipairs(spec) do dung[#dung + 1] = r end
  return dung, finished, more, prog
end

-- which views have something for you: { dungeons = true, class = false, ... } - worked out once per change to your
-- quests (a hand-in, a pick-up) or the routes loaded; the sidebar asks each time the window opens
local availMemo, availFor, availProg
function Dungeons.Available()
  local routes = ns.Routes and ns.Routes()
  if availMemo and availFor == routes and availProg == progCache then return availMemo end
  local out = { dungeons = false, class = false, attune = false, reward = false }
  for _, r in ipairs(ns.DungeonRoutes()) do
    local kd = Dungeons.Kind(r)
    local v = (kd == "dungeon" or kd == "key") and "dungeons" or kd
    if not out[v] then
      -- (a dungeon is listed even with its quests done - "All dungeons"; a trip only while it has something left)
      if kd == "dungeon" then out[v] = true
      else
        -- (anything left: the first quest not done says so - no counting, no quest log asked)
        local any, left = false, false
        for q in pairs(ns.QuestIds(r)) do if q > 0 then any = true; if not ns.State.IsCompleted(q) then left = true; break end end end
        out[v] = left or not any
      end
    end
  end
  availMemo, availFor, availProg = out, routes, progCache
  return out
end

-- how many trips each side trips view lists for you now (as Dungeons.List lists them) and their sum: the card's rail
-- shows them (UI/Card/Rail.lua), asking each time the card is laid out. A trip counts while a quest of it is not done:
-- only a hand-in, a level or other routes change that, so the counts are worked out again only then (a pick-up, a kill
-- or a log update ask nothing), and each trip is asked about up to its first quest not done
local countMemo, countTotal, countFor, countLvl, countGen
local turnIns = 0
ns.On("QUEST_TURNED_IN", function() turnIns = turnIns + 1 end)
local function left(r) -- (as the list: a trip with no quests of its own is never finished)
  local any = false
  for q in pairs(ns.QuestIds(r)) do if q > 0 then any = true; if not ns.State.IsCompleted(q) then return true end end end
  return not any
end
local byDist = {}
function Dungeons.Counts()
  local routes = ns.Routes and ns.Routes()
  local lvl = (UnitLevel and UnitLevel("player")) or 1
  if countMemo and countFor == routes and countLvl == lvl and countGen == turnIns then return countMemo, countTotal end
  local out = { dungeons = 0, class = 0, attune = 0, reward = 0 }
  -- (dungeons: the nearest for your level as the list takes them - Dungeons.List - less the ones you finished; a dungeon
  -- key is listed with them)
  wipe(byDist)
  local inBand = 0
  for _, r in ipairs(ns.DungeonRoutes()) do
    if r.special then
      local v = Dungeons.Kind(r)
      if v == "key" then v = "dungeons" end
      if out[v] and left(r) then out[v] = out[v] + 1 end
    else
      byDist[#byDist + 1] = r
      local q = tonumber(r.questLevel) or 0
      if q <= lvl + 4 and q >= lvl - 4 then inBand = inBand + 1 end
    end
  end
  local function dist(r) return math.abs((tonumber(r.questLevel) or 0) - lvl) end
  table.sort(byDist, function(x, y) local dx, dy = dist(x), dist(y); if dx ~= dy then return dx < dy end return (x.dungeonName or "") < (y.dungeonName or "") end)
  local take = inBand > 0 and math.min(SHOWN, inBand) or math.min(3, #byDist)
  for i = 1, take do if left(byDist[i]) then out.dungeons = out.dungeons + 1 end end
  wipe(byDist)
  local total = out.dungeons + out.class + out.attune + out.reward
  countMemo, countTotal, countFor, countLvl, countGen = out, total, routes, lvl, turnIns
  return out, total
end
-- the Beeline window on a side trips view (default Dungeons), or closed when it is on it already
function Dungeons.Toggle(view)
  view = Dungeons.VIEWS[view] and view or "dungeons"
  if ns.Window.IsShown(view) then ns.Window.Hide(); return end
  Dungeons.Show(view)
end
function Dungeons.Show(view)
  view = Dungeons.VIEWS[view] and view or "dungeons"
  if not ns.Window.IsShown() then Dungeons.Reset() end -- (opened again: the ones for your level)
  ns.Window.Show(view)
end
for key, V in pairs(Dungeons.VIEWS) do
  ns.Window.Register(key, { label = V.label, icon = V.icon, color = C.gold, title = V.title, tip = V.intro, group = 2, order = V.order, panel = "trips",
    build = build, avail = function() return Dungeons.Available()[key] end,
    show = function(k)
      if Dungeons.view ~= k then Dungeons.Reset(); if panel then panel.setScroll(0) end end -- (another view: the ones for your level, from the top)
      Dungeons.view = k
      Dungeons.Redraw()
    end })
end

ns.On("FR_TOGGLE_DUNGEONS", function() Dungeons.Toggle() end)
-- (open, it follows your log: once for a burst of log updates - a kill or a loot sends two or three - not for each)
-- and your route: a trip picked or left anywhere else (the card's "Back to plan") - the list kept FOLLOWING and its own
-- "Back to plan" on a trip you had left (tester)
local redrawDue = false
local function redrawSoon()
  if redrawDue or not shownView() then return end
  redrawDue = true
  C_Timer.After(0.2, function() redrawDue = false; Dungeons.Redraw() end)
end
ns.On("QUEST_LOG_UPDATE", redrawSoon)
ns.On("FR_ROUTE_CHANGED", function() if shownView() then Dungeons.Redraw() end end) -- (rare: at once)

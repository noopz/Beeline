-- The card's side rail: the places to go, on the card's left edge, apart from the step's own controls in the hover bar.
-- Top to bottom: Back to plan (on a side trip), Route, Where to?, Side trips (a count: the trips left for you),
-- Log check (a count: the quests in your log no route of yours uses); Options at its foot. Each button's tooltip
-- names it, says what it opens and gives its count. The rail is quiet: flat glyphs in a dim colour on a faint tint (no
-- discs, no edge line), brighter under the mouse, gold while their view is on screen; a count is a small number under its
-- glyph, in the rail's own column; Back to plan alone is gold with a wash. A tab on the card's left edge, beside the rail, hides and shows it
-- (ns.db.rail, shown by default); a collapsed card has no rail but keeps the tab, which opens the whole card with the rail
-- (and closing the rail with it folds the card back: Rail.Toggle). The counts are worked out when the card is laid out
-- (Card.Layout: the events that already redraw it), never per frame: the side trips' from Dungeons.Counts (kept until
-- your quests, level or routes change), the log check's from LogCheck.dropCount. Tooltips are worked out on hover.
local _, ns = ...
local Style = ns.Style
local C = Style.C
local Card = ns.Card
local Rail = {}
ns.Rail = Rail

Rail.W = 38                    -- its width, added to the card's (the step keeps its room)
Rail.GAP = 5                   -- the room between the rail's tint and the step's accent strip (part of Rail.W)
Rail.BTN, Rail.ICON = 20, 16   -- a button's height (a counted one: + Rail.NUM, its number under the glyph), its glyph
Rail.NUM, Rail.SPACE = 11, 6   -- the count's line under a glyph; the space between one button and the next
Rail.TOP_Y, Rail.FOOT_Y = 6, 6 -- the first button under the rail's top, Options over its foot

-- shown: not hidden with its tab, and the card not collapsed
function Rail.On() return ns.db.rail ~= false and not ns.db.collapsed end
function Rail.Width() return Rail.On() and Rail.W or 0 end
-- the rail's top under the card's top: under the skin's title strip (the Blizzard frame's), else just inside the edge
local function railTop() return 3 + (Style.M.chromeTop or 0) end

local TRIP_VIEWS = { "dungeons", "attune", "class", "reward" }
Rail.TRIP_WORDS = { dungeons = { "dungeon", "dungeons" }, attune = { "attunement", "attunements" },
  class = { "class quest", "class quests" }, reward = { "special reward", "special rewards" } }
-- "8 dungeons, 3 attunements, 1 class quest, 1 special reward" (only the kinds with something)
function Rail.TripText(counts)
  local parts = {}
  for _, v in ipairs(TRIP_VIEWS) do
    local n = counts[v] or 0
    if n > 0 then parts[#parts + 1] = n .. " " .. Rail.TRIP_WORDS[v][n == 1 and 1 or 2] end
  end
  return table.concat(parts, ", ")
end

local f, rail, tab
local NONE = {}
local counts, total = NONE, 0 -- the side trips' counts at the last layout (Rail.Update)

-- Side trips: the window on the first kind with something for you (dungeons first); closed when it shows a trip view
local function openTrips()
  local W = ns.Window
  for _, v in ipairs(TRIP_VIEWS) do if W.IsShown(v) then W.Hide(); return end end
  local pick = "dungeons"
  for _, v in ipairs(TRIP_VIEWS) do if (counts[v] or 0) > 0 then pick = v; break end end
  ns.Dungeons.Show(pick)
end

-- the buttons, top to bottom (foot: at the rail's foot; trip: only on a side trip). views: the window's views it opens
-- (lit while one is on screen); color: its glyph's Style.C token (else dim), num: its count's; count() -> the number
-- under its glyph (none at 0); tip() -> its tooltip now
local ENTRIES = {
  { key = "back", icon = "btn-back", color = "gold", trip = true, run = function() ns.LeaveDungeonRoute() end,
    tip = function()
      local d = BeelineData
      local name = d and d.dungeon and ns.Dungeons and ns.Dungeons.DisplayName(d) or "this side trip"
      return { "Back to plan", "Leaves " .. name .. " and carries on with your plan. Progress on the trip is kept." }
    end },
  { key = "route", icon = "btn-list", views = { route = true }, run = function() ns.Fire("FR_TOGGLE_LIST") end,
    tip = function() return { "Route", "Opens your steps from where you are, with your plan's zones  (/bee list)" } end },
  { key = "zones", icon = "icon-where", views = { zones = true }, run = function() ns.Fire("FR_TOGGLE_PATHS") end,
    tip = function() return { "Where to?", "Opens the zones you could go to now (Home base). Nothing changes unless you pick one." } end },
  { key = "trips", icon = "icon-kill", views = { dungeons = true, attune = true, class = true, reward = true }, run = openTrips,
    num = "gold", count = function() return total end,
    tip = function()
      return { total > 0 and ("Side trips: " .. Rail.TripText(counts)) or "Side trips: none left for you now",
        "Opens the side trips: dungeons, attunements, class quests and special rewards, each a trip that keeps your plan." }
    end },
  { key = "log", icon = "icon-check", views = { logcheck = true }, num = "warn", run = function() ns.Fire("FR_TOGGLE_LOGCHECK") end,
    count = function() return ns.LogCheck and ns.LogCheck.dropCount or 0 end,
    tip = function()
      local n = ns.LogCheck and ns.LogCheck.dropCount or 0
      return { n > 0 and string.format("Log check: %d quest%s in your log no route of yours uses", n, n == 1 and "" or "s") or "Log check: every quest in your log is on a route",
        "Opens the log check, to look them over and drop what you won't do." }
    end },
  { key = "opt", icon = "btn-gear", foot = true, run = function() ns.Fire("FR_OPEN_OPTIONS") end,
    tip = function() return { "Options", "Opens Beeline's options." } end },
}

-- a button's glyph painted for its state: gold on a trip's Back to plan and while its view is on screen, bright under
-- the mouse, else dim
local function paintButton(b)
  local e = b.entry
  local c = e.color and C[e.color] or (b.lit and C.gold) or (b.over and C.text) or C.dim
  Style.Paint(b.icon, c, (b.over or b.lit or e.color) and 1 or 0.85)
end

-- a flat button: the glyph (no disc behind it), and a counted one's number under it - both inside the button, so
-- nothing hangs over its neighbours
local function makeButton(e)
  local b = CreateFrame("Button", nil, rail)
  b:SetSize(Rail.W - 3 - Rail.GAP, Rail.BTN + (e.count and Rail.NUM or 0))
  b.entry = e
  b.icon = b:CreateTexture(nil, "ARTWORK"); Style.Glyph(b.icon, e.icon)
  b.icon:SetSize(Rail.ICON, Rail.ICON); b.icon:SetPoint("CENTER", b, "TOP", 0, -Rail.BTN / 2)
  b.wash = Style.Fill(b, "BACKGROUND"); b.wash:SetPoint("TOPLEFT", 2, 0); b.wash:SetPoint("BOTTOMRIGHT", -2, 0); b.wash:Hide()
  if e.count then
    b.count = Style.Text(b, Style.MIN_FONT, C[e.num or "gold"]); b.count:SetJustifyH("CENTER")
    b.count:SetPoint("TOP", b, "TOP", 0, -Rail.BTN + 1); b.count:Hide()
  end
  b:SetScript("OnClick", function() e.run() end)
  -- (its tooltip worked out as the mouse comes, from the counts of the last layout)
  b:SetScript("OnEnter", function(self)
    self.over = true; paintButton(self); self.tip = e.tip(); Style.ShowTip(self, self.tip); Card.Hover(true)
  end)
  b:SetScript("OnLeave", function(self) self.over = nil; paintButton(self); GameTooltip:Hide(); Card.Hover(false) end)
  paintButton(b)
  return b
end

function Rail.Build(frame)
  f = frame
  rail = CreateFrame("Frame", nil, f); f.rail = rail
  rail:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -railTop()); rail:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 3, 3)
  rail:SetWidth(Rail.W - 3 - Rail.GAP)
  rail.bg = Style.RailBg(rail, 0.16, true) -- (a faint tint, no edge line: the step's accent strip is the only line)
  rail:EnableMouse(true)
  rail:SetScript("OnEnter", function() Card.Hover(true) end)
  rail:SetScript("OnLeave", function() Card.Hover(false) end)
  rail.btn = {}
  for _, e in ipairs(ENTRIES) do rail.btn[e.key] = makeButton(e) end
  rail.sep = Style.Divider(rail, 0.12); rail.sep:SetHeight(1); rail.sep:Hide()
  -- the tab: "<" hides the rail, ">" shows it (just outside the card's left edge; the card keeps it on the screen)
  tab = CreateFrame("Button", nil, f); f.railTab = tab
  tab:SetSize(14, 40); tab:SetPoint("TOPRIGHT", f, "TOPLEFT", -1, -12 - (Style.M.chromeTop or 0))
  Style.RowBg(tab, 6, 0.95, C.tab)
  tab.label = Style.Text(tab, 11, C.gold); tab.label:SetPoint("CENTER")
  tab:SetScript("OnClick", function() Rail.Toggle() end)
  tab:SetScript("OnEnter", function(self) Style.ShowTip(self, Rail.TabTip()); Card.Hover(true) end)
  tab:SetScript("OnLeave", function() GameTooltip:Hide(); Card.Hover(false) end)
  f:SetClampRectInsets(-16, 0, 0, 0)
end

function Rail.TabTip()
  if Rail.On() then return { "Hide the side rail", "Route, Where to?, Side trips, Log check and Options fold away. This tab brings them back." } end
  return { "Show the side rail", "Route, Where to?, Side trips, Log check and Options, on the card's left." }
end
-- the tab's click: the rail shown or hidden, kept for next time. On a collapsed card: the card expanded with the rail
-- shown - and closing the rail with the tab then collapses it again, the rail as you had it (Rail.opened: the rail's
-- setting before; the collapse button clears it, Rail.Manual - expanded by hand, the card stays so)
function Rail.Toggle()
  local was = ns.db.collapsed
  if ns.db.collapsed then
    Rail.opened = { rail = ns.db.rail }
    ns.db.collapsed = false; ns.db.rail = true
  elseif Rail.opened and ns.db.rail ~= false then
    ns.db.collapsed = true; ns.db.rail = Rail.opened.rail
    Rail.opened = nil
  else
    ns.db.rail = ns.db.rail == false
  end
  -- (the card collapsed or expanded: redrawn as its own button does; the layout always - a redraw can skip it)
  if was ~= ns.db.collapsed and Card.Update then Card.Update() end
  if Card.Layout then Card.Layout() end
end
-- the card collapsed or expanded with its own button: no fold back with the tab
function Rail.Manual() Rail.opened = nil end

-- the buttons lit for the window's view on screen (the window calls it when it opens, closes or changes view)
function Rail.Lit()
  if not (rail and rail:IsShown()) then return end
  local W = ns.Window
  local view = W and W.IsShown() and W.view or nil
  for _, b in pairs(rail.btn) do
    local e = b.entry
    b.lit = (view and e.views and e.views[view] or e.trip and b:IsShown()) and true or false
    -- (gold glyphs; Back to plan, the way out, alone has a wash too)
    if e.trip then Style.Paint(b.wash, C[e.color], 0.16) end
    b.wash:SetShown(b.lit and e.trip and true or false)
    paintButton(b)
  end
end

-- the rail's height for what it shows: the card is at least this tall while it is shown (Card.LayoutFooter)
local need = 0
function Rail.MinHeight() return Rail.On() and need or 0 end

-- what it shows now: the buttons for this route, their counts (Card.Layout, once per layout)
function Rail.Update()
  if not rail then return end
  local on = Rail.On()
  rail:SetShown(on)
  tab:Show() -- (a collapsed card too: it opens the card with the rail)
  tab.label:SetText(on and "<" or ">")
  if not on then return end
  counts, total = NONE, 0
  if ns.Dungeons and ns.Dungeons.Counts then counts, total = ns.Dungeons.Counts() end
  local trip = BeelineData and BeelineData.dungeon and true or false
  local y, sepAt, footH = Rail.TOP_Y, nil, 0
  for _, e in ipairs(ENTRIES) do
    local b = rail.btn[e.key]
    local show = not e.trip or trip
    b:SetShown(show)
    if show then
      b:ClearAllPoints()
      if e.foot then b:SetPoint("BOTTOM", rail, "BOTTOM", 0, Rail.FOOT_Y); footH = b:GetHeight()
      else
        b:SetPoint("TOP", rail, "TOP", 0, -y); y = y + b:GetHeight() + Rail.SPACE
        -- (a line under "Back to plan": the way out, apart from the places to go)
        if e.trip then sepAt = y - Rail.SPACE / 2; y = y + 4 end
      end
      if b.count then
        local n = e.count()
        b.count:SetShown(n > 0)
        if n > 0 then b.count:SetText(tostring(n)) end
      end
    end
  end
  rail.sep:SetShown(sepAt and true or false)
  if sepAt then rail.sep:ClearAllPoints(); rail.sep:SetPoint("TOPLEFT", rail, "TOPLEFT", 6, -sepAt); rail.sep:SetPoint("RIGHT", rail, "RIGHT", -6, 0) end
  -- (the last top button, a gap, Options and the margins)
  need = railTop() + y - Rail.SPACE + 8 + footH + Rail.FOOT_Y + 3
  Rail.Lit()
end

-- the card's top line: the route you are on - "Leveling · Azshara" in gold (a zone you picked: "Home base · Westfall"),
-- on a side trip the trip's name in its kind's colour
Rail.KIND_COLOR = { dungeon = "mob", key = "mob", class = "good", attune = "gold", reward = "lilac" } -- (Style.C tokens)
function Rail.HeaderText(zone)
  local d = BeelineData
  if not d then return "Beeline" end
  if d.dungeon then
    local D = ns.Dungeons
    local kind = D and D.Kind(d) or "dungeon"
    local name = D and D.DisplayName(d) or d.dungeonName or d.title or "Side trip"
    return Style.Hex(C[Rail.KIND_COLOR[kind] or "gold"] or C.gold) .. name .. "|r"
  end
  local what = d.zoneRoute and "Home base" or "Leveling"
  return Style.Hex(C.gold) .. what .. (zone and (" · " .. Style.ShortZone(zone)) or "") .. "|r"
end

-- The Beeline window: one window with a sidebar on its left and one view at a time on its right.
--   Route        - your steps from where you are (UI/List.lua)
--   Zones        - Home base: the zones you could go to now, and a companion's other plans (UI/Paths.lua)
--   side trips   - Class quests, Dungeons (with dungeon keys), Attunements, Special items (UI/Dungeons.lua)
--   Log check    - which quests in your log to keep (UI/LogCheck.lua)
-- A view registers itself (Window.Register); its panel - the frame it draws in, right of the sidebar and under the
-- title - is made the first time the view is shown, never before, and only the view on screen is drawn. A view with
-- nothing for this character (no class quests left) has no sidebar item. Opened on a view by the card's buttons, /bee
-- commands, the key bindings and the FR_TOGGLE_* events; a toggle for the view on screen closes the window.
local _, ns = ...
local Style = ns.Style
local C = Style.C
local Window = {}
ns.Window = Window

local f
-- the sidebar's width, the right side's width (its padding included), the window's height
local RAIL, W, H, PAD = 76, 500, 540, 14
Window.RAIL, Window.W, Window.H, Window.PAD = RAIL, W, H, PAD
Window.LEFT = RAIL + PAD        -- where a view's panel starts
Window.TOP = 58                 -- and how far under the window's top
Window.INNER = W - 2 * PAD      -- a panel's width
Window.ACTION_W = 110           -- the room a view's action takes at the right of the line under the title
local TAB_H, GROUP_GAP = 50, 14 -- a sidebar item's step, the gap between groups

local views, order = {}, {}
Window.views = views
Window.view = "route" -- the view on screen (or shown last)
local panels = {}     -- panel key -> frame (made on first show)

-- def = { label, icon, color, title, tip, group (1 your route, 2 side trips, 3 tools), order, panel = the panel key
-- (views drawn by one module share it; default the view's key), build(panel) once for the panel, show(key) each time
-- the view comes up (draw it), avail() -> false: nothing for this character, no sidebar item }
function Window.Register(key, def)
  def.key = key; def.panel = def.panel or key
  views[key] = def; order[#order + 1] = key
  table.sort(order, function(a, b) return (views[a].order or 99) < (views[b].order or 99) end)
end
function Window.Order() return order end

local function panelFor(def)
  local p = panels[def.panel]
  if p then return p end
  p = CreateFrame("Frame", nil, f)
  p:SetPoint("TOPLEFT", f, "TOPLEFT", Window.LEFT, -Window.TOP); p:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 10)
  p:SetSize(Window.INNER, H - Window.TOP - 10) -- (its size before the first layout pass)
  p:Hide()
  panels[def.panel] = p
  -- (every view sharing the panel: built once)
  if def.build then def.build(p) end
  return p
end
function Window.Panels() return panels end

-- the sidebar: the items with something for you, in their groups (a divider between), the one on screen lit
function Window.RefreshRail()
  if not f then return end
  local y, lastGroup = 8, nil
  for _, key in ipairs(order) do
    local def, b = views[key], f.items[key]
    local show = key == Window.view or not def.avail or def.avail() ~= false
    b:SetShown(show)
    if show then
      if lastGroup and def.group ~= lastGroup then
        local d = f.dividers[lastGroup]
        d:ClearAllPoints(); d:SetPoint("TOPLEFT", f.rail, "TOPLEFT", 10, -(y + GROUP_GAP / 2 - 2)); d:SetPoint("RIGHT", f.rail, "RIGHT", -10, 0); d:Show()
        y = y + GROUP_GAP
      end
      lastGroup = def.group
      b:ClearAllPoints(); b:SetPoint("TOP", f.rail, "TOP", 0, -y)
      y = y + TAB_H
      b.on = key == Window.view; Style.PaintTab(b)
    end
  end
  -- (a divider after a group nothing follows: hidden)
  for g, d in pairs(f.dividers) do
    local used = false
    for _, key in ipairs(order) do if f.items[key]:IsShown() and views[key].group > g then used = true end end
    if not used then d:Hide() end
  end
end

local function build()
  f = CreateFrame("Frame", "BeelineWindow", UIParent)
  f:SetSize(RAIL + W, H); f:SetPoint("CENTER", 0, 40)
  Style.Window(f, "BeelineWindow")
  f.rail = CreateFrame("Frame", nil, f)
  f.rail:SetPoint("TOPLEFT", 4, -4); f.rail:SetPoint("BOTTOMLEFT", 4, 4); f.rail:SetWidth(RAIL - 6)
  f.rail.bg = Style.RailBg(f.rail, 0.28)
  f.items, f.dividers = {}, {}
  for _, key in ipairs(order) do
    local def = views[key]
    local b = Style.RailTab(f.rail, def, 0, function() Window.Show(key) end, RAIL - 6)
    b.key = key
    f.items[key] = b
    if not f.dividers[def.group] then
      local d = Style.Divider(f.rail, 0.12); d:SetHeight(1); d:Hide()
      f.dividers[def.group] = d
    end
  end
  -- the top: the view's title, one line under it (an action at its right is the view's), close
  f.title = Style.WindowTitle(f, 15, Window.LEFT, -12)
  f.close = Style.CloseButton(f)
  f.intro = Style.Text(f, 10, C.sub); f.intro:SetPoint("TOPLEFT", Window.LEFT, -34); f.intro:SetPoint("RIGHT", f, "RIGHT", -PAD - Window.ACTION_W, 0); f.intro:SetWordWrap(false)
  f:Hide()
  f:HookScript("OnHide", function() if ns.Rail then ns.Rail.Lit() end end)
end

function Window.Frame() return f end
function Window.SetIntro(text) if f then f.intro:SetText(text or "") end end
-- the view on screen; key nil: any
function Window.IsShown(key) return (f and f:IsShown() and (key == nil or Window.view == key)) and true or false end
function Window.Hide() if f then f:Hide() end end
-- the window on view key (its panel made on first show; the other panels hidden, never drawn)
function Window.Show(key)
  if not f then return end -- (a key pressed while loading)
  local def = views[key] or views[Window.view]
  key = def.key
  Window.view = key
  local p = panelFor(def)
  for pk, other in pairs(panels) do if pk ~= def.panel then other:Hide() end end
  f.title:SetText(def.title or def.label)
  f.intro:SetText("")
  if not f:IsShown() then f:Show() end
  p:Show()
  Window.RefreshRail()
  if def.show then def.show(key) end
  if ns.Rail then ns.Rail.Lit() end -- (the card's side rail lights the button for this view)
end
-- open on view key; closed when it is on that view already
function Window.Toggle(key)
  if not f then return end
  if Window.IsShown(key) then f:Hide(); return end
  Window.Show(key)
end

ns.On("FR_LOADED", build)
-- (a trip done or a route changed: an item may come or go)
local railDue = false
local function railSoon()
  if railDue or not Window.IsShown() then return end
  railDue = true
  C_Timer.After(0.3, function() railDue = false; Window.RefreshRail() end)
end
for _, e in ipairs({ "FR_ROUTE_CHANGED", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "PLAYER_LEVEL_UP" }) do ns.On(e, railSoon) end

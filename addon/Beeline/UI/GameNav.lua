-- The game's own navigation marker (in-game navigation: the diamond in the 3D world over where you are going, with the
-- yards to it, sliding to the edge of the screen with an arrow when it is behind you) put where the route's arrow
-- points: the step, or the trip's next waypoint - the flight master, the pier, the zone crossing, a corpse run aside.
--
-- How: the game draws that marker for whatever is super-tracked (C_SuperTrack). On a step of a quest in your log, at
-- the step itself (not a trip's waypoint on the way there): the quest is focused (SetSuperTrackedQuestID, as a click on
-- it in the quest tracker does) and the game draws its own marker for it - when the game has one: its quest data lacks
-- many of Forever's quests (C_QuestLog.GetNextWaypoint, the quest markers on the map). Anything else - a pick-up, a
-- flight path, a trip's flight master, pier or zone crossing, a quest the game marks nowhere - gets a user waypoint
-- (C_Map.SetUserWaypoint, the pin a shift-click on the world map sets) at the arrow's spot, super-tracked.
--
-- The game hides the marker unless the showInGameNavigation setting is on, and Forever's options have no box for it:
-- turning this option on turns that on (once - set it off yourself and it stays off until you turn this option on again).
-- A waypoint of your own (you set a pin on the world map) is yours: the marker leaves it alone until you clear it.
-- Only on a change of the arrow's target: nothing per frame.
-- Routing through Shortest Path Forever (UI/ShortestPath.lua): the waypoint and the quest focus are its own, so this
-- sets neither, and takes its pins for no one's.
local _, ns = ...
local pcall = ns.PCall or pcall -- (a job never pauses under it: Core.lua)
local GameNav = {}
ns.GameNav = GameNav
local HBD = LibStub("HereBeDragons-2.0")

local mine = nil   -- the waypoint the route set: { m, x, y }
local yours = false -- a waypoint of the player's own is up: hands off

local function api()
  return C_Map and C_Map.SetUserWaypoint and C_Map.GetUserWaypoint and C_Map.ClearUserWaypoint and C_SuperTrack
    and C_SuperTrack.SetSuperTrackedUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates and true or false
end
function GameNav.Enabled() return (ns.db and ns.db.gameNav and api()) and true or false end

local function setCVar(name, v)
  if C_CVar and C_CVar.SetCVar then return pcall(C_CVar.SetCVar, name, v) end
  if SetCVar then return pcall(SetCVar, name, v) end
end
local function getCVar(name)
  if C_CVar and C_CVar.GetCVar then local ok, v = pcall(C_CVar.GetCVar, name); return ok and v or nil end
  if GetCVar then local ok, v = pcall(GetCVar, name); return ok and v or nil end
end

-- the waypoint up now is the one the route set
local function isMine(p)
  return p and mine and p.uiMapID == mine.m and p.position and math.abs(p.position.x - mine.x) < 1e-3 and math.abs(p.position.y - mine.y) < 1e-3
end
local function current() local ok, p = pcall(C_Map.GetUserWaypoint); return ok and p or nil end

-- a map that takes a waypoint for the spot: its own, or the one it lies in (a city inside a zone, a zone in a continent)
local function placeable(m, x, y)
  local function can(map) if not C_Map.CanSetUserWaypointOnMap then return true end local ok, v = pcall(C_Map.CanSetUserWaypointOnMap, map); return ok and v end
  for _ = 1, 4 do
    if not m then return nil end
    if can(m) then return m, x, y end
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(m)
    local parent = info and info.parentMapID
    if not parent or parent == 0 then return nil end
    local px, py = HBD:TranslateZoneCoordinates(x, y, m, parent)
    if not px then return nil end
    m, x, y = parent, px, py
  end
end

-- the game has a marker of its own for the quest: its next waypoint, or a marker on the map you are on
local function gameMarks(q)
  if not C_QuestLog then return false end
  if C_QuestLog.GetNextWaypoint then
    local ok, m, x = pcall(C_QuestLog.GetNextWaypoint, q)
    if ok and type(m) == "number" and m > 0 and type(x) == "number" then return true end
  end
  local here = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  if type(here) == "number" and C_QuestLog.GetQuestsOnMap then
    local ok, list = pcall(C_QuestLog.GetQuestsOnMap, here)
    if ok and type(list) == "table" then for _, e in ipairs(list) do if e.questID == q then return true end end end
  end
  return false
end
-- the quest to focus for the arrow's target: a step of a quest in your log, at the step itself (a trip's waypoint on
-- the way there is the route's: the flight master, the pier)
local function questOf(t)
  local s = t and t.step
  local q = s and s.q
  if not (q and q > 0) or t.leg or not (C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID) then return nil end
  if not (ns.State and ns.State.OnQuest and ns.State.OnQuest(q)) then return nil end
  return gameMarks(q) and q or nil
end
local focused = nil -- the quest the route focused

local function routed() return ns.ShortestPath and ns.ShortestPath.Routing() end
-- the route's waypoint and quest focus taken away (the option off, or Shortest Path leading)
local function release()
  if mine and api() and isMine(current()) then pcall(C_Map.ClearUserWaypoint) end
  if focused and C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
    local ok, now = pcall(C_SuperTrack.GetSuperTrackedQuestID)
    if ok and now == focused then pcall(C_SuperTrack.SetSuperTrackedQuestID, 0) end
  end
  mine, focused = nil, nil
end

-- put the marker on the arrow's target (nil: nothing to point at - the route's waypoint goes)
function GameNav.Follow(t)
  if not GameNav.Enabled() or yours then return end
  if routed() then release(); return end
  local q = questOf(t)
  if q then
    -- the game's own marker for the quest: the route's waypoint goes
    if mine and isMine(current()) then pcall(C_Map.ClearUserWaypoint) end
    mine = nil
    local ok, now = pcall(C_SuperTrack.GetSuperTrackedQuestID)
    if focused ~= q or not (ok and now == q) then focused = q; pcall(C_SuperTrack.SetSuperTrackedQuestID, q) end
    return
  end
  focused = nil
  local m, x, y = nil, nil, nil
  if t and t.m and t.x and t.y then m, x, y = placeable(t.m, t.x, t.y) end
  if not m then
    if mine and isMine(current()) then pcall(C_Map.ClearUserWaypoint) end
    mine = nil
    return
  end
  if mine and mine.m == m and math.abs(mine.x - x) < 1e-4 and math.abs(mine.y - y) < 1e-4 and isMine(current()) then return end
  mine = { m = m, x = x, y = y }
  pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(m, x, y))
  pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
end

-- the option turned on (or on at login for the first time): the game's marker turned on too
function GameNav.Setup()
  if not GameNav.Enabled() then return end
  if not ns.db.gameNavCVar then
    if getCVar("showInGameNavigation") ~= "1" then setCVar("showInGameNavigation", "1") end
    ns.db.gameNavCVar = true
  end
  GameNav.Follow(ns.Arrow and ns.Arrow.Current())
end

ns.On("FR_LOADED", function() GameNav.Setup() end)
ns.On("FR_SETTINGS", function(key)
  if key == "shortestPathRouting" and not routed() then
    -- routing turned off: Shortest Path ends its journey and puts back the waypoint it borrowed first; one up then
    -- is the player's
    C_Timer.After(0.5, function()
      if routed() or not api() then return end
      local p = current()
      yours = p and not isMine(p) and true or false
      GameNav.Setup()
    end)
  elseif GameNav.Enabled() then GameNav.Setup()
  else
    -- off: the route's waypoint goes; turning it on again turns the game's marker on again
    release()
    if ns.db then ns.db.gameNavCVar = nil end
  end
end)
-- the game's quest markers changed (it marks a quest once you are in its zone): a quest it marks now gets the focus
ns.On("QUEST_POI_UPDATE", function() if GameNav.Enabled() and ns.Arrow then GameNav.Follow(ns.Arrow.Current()) end end)
-- a waypoint set or cleared: one that isn't the route's is the player's own, until it is gone
ns.On("USER_WAYPOINT_UPDATED", function()
  if not api() or routed() then return end
  local p = current()
  if p and not isMine(p) then yours = true; mine = nil
  elseif not p and yours then yours = false; GameNav.Follow(ns.Arrow and ns.Arrow.Current())
  elseif not p then mine = nil end
end)

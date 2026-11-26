-- Shortest Path Forever (optional addon): the card's step sent to it as a journey, so its planner (flights, boats,
-- portals) and its tracker lead the way there. Its API: ShortestPathForever.API (version 2).
--
-- A journey someone else started there (the player's own, another addon's) comes first: Beeline waits for it to end,
-- then sends the step again. A journey of Beeline's the player cleared stays cleared until the step changes.
--
-- While routing is on, the game's waypoint and quest focus are Shortest Path's: GameNav keeps its hands off them
-- (GameNav.lua). Shortest Path keeps no journey of another addon over a /reload, so the step is sent again once the
-- world is up - after Shortest Path's own resume (2 s), so a journey the player kept wins.
local ADDON, ns = ...
local SP = {}
ns.ShortestPath = SP

local NAME = "ShortestPathForever"
local SETTLE = 3     -- seconds after the first loading screen before the first send
local RETRIES = 10   -- sends refused in a row (no position yet, say) before giving up on that step

local function api()
  local a = _G.ShortestPathForever and _G.ShortestPathForever.API
  if a and a.version == 2 and a.NavigateRoute and a.CurrentStop and a.Cancel and a.Ended and a.Active
    and a.JourneyState and a.Subscribe then return a end
end

-- installed and enabled: known at Beeline's own load, before Shortest Path has loaded and published its API
local function installed()
  local f = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
  if not f then return false end
  local ok, _, _, _, loadable = pcall(f, NAME)
  return ok and loadable and true or false
end

-- Beeline routes through Shortest Path (the option on, the addon there)
function SP.Routing()
  return (ns.db and ns.db.shortestPathRouting and (api() or installed())) and true or false
end
-- Shortest Path is guiding now, whoever's journey it is
function SP.Active()
  local a = api()
  return a and a.Active() and true or false
end

local ready = false -- the world is up and Shortest Path has had its turn
local sent          -- the step last sent: { step, m, x, y }
local refused, failed = nil, 0 -- the step whose sends were refused, and how many times in a row

-- the card's step and the spot to send for it (the step's own, or the next one with a place on the map)
local function target()
  local i = ns.Engine.CardAt()
  local list = BeelineData and BeelineData.steps
  local s = i and list and list[i]
  if not s or s.k == "hearth" then return end
  local _, pin = ns.MapSpot(i)
  local spot = pin and list[pin]
  if not spot and s.unknown and ns.Arrow then spot = ns.Arrow.GameSpot(s) end
  if spot and spot.m and spot.x and spot.y then return s, spot end
end

local request
local function update()
  local a = api()
  if not (a and ready and ns.db) then return end
  local owned = a.CurrentStop(ADDON)
  local s, spot
  if ns.db.shortestPathRouting then s, spot = target() end
  if not s then
    sent = nil
    if owned then a.Cancel(ADDON) end
    return
  end
  local same = sent and sent.step == s and sent.m == spot.m and sent.x == spot.x and sent.y == spot.y
  if same and owned then return end
  if not owned then
    -- cleared by the player: left so until the step changes
    if same and a.Ended(ADDON) ~= "replaced" then return end
    -- another journey under way: the subscription below sends again when it ends
    local state = a.JourneyState()
    if not state or state.busy then return end
  end
  if InCombatLockdown() then return end -- (PLAYER_REGEN_ENABLED sends again)
  local title = ns.Card.Plain((ns.Card.Describe(s)))
  if a.NavigateRoute(ADDON, { { map = spot.m, x = spot.x, y = spot.y, z = spot.z, title = title, hold = true, radius = spot.r or 12 } }) then
    sent, refused = { step = s, m = spot.m, x = spot.x, y = spot.y }, nil
  else
    -- refused: no player position yet (just after a loading screen), most often - tried again a few times
    sent = nil
    if refused ~= s then refused, failed = s, 0 end
    failed = failed + 1
    if failed <= RETRIES then C_Timer.After(1, request) end
  end
end
request = ns.Debounce(0, ns.Guard("shortest path", update))

local subscribed = false
local function subscribe()
  local a = not subscribed and api()
  if not a then return end
  subscribed = true
  a.Subscribe(function(changes)
    if not changes or changes.active then ns.Fire("FR_SHORTEST_PATH_GUIDANCE") end
    if not changes or changes.ended or changes.stop then request() end
  end)
end

ns.On("PLAYER_ENTERING_WORLD", function()
  subscribe()
  if ready then request(); return end
  C_Timer.After(SETTLE, function() ready = true; subscribe(); request() end)
end)
ns.On("FR_SETTINGS", function(key) if key == nil or key == "shortestPathRouting" then request() end end)
for _, e in ipairs({ "FR_STEP", "QUEST_POI_UPDATE", "PLAYER_REGEN_ENABLED", "ZONE_CHANGED_NEW_AREA" }) do ns.On(e, request) end

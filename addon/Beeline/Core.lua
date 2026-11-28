-- Beeline: core namespace, saved settings, events and slash commands.
local ADDON, ns = ...
Beeline = ns
ns.name = ADDON

ns.DEFAULTS = {
  scale = 1.0,
  cardWidth = 360,
  showNext = 3,          -- upcoming steps under the current one
  arrow = true,
  arrowScale = 1.0,
  gameNav = true,        -- the game's own navigation marker (in-game navigation) on where the arrow points (UI/GameNav.lua)
  pins = true,
  pinCount = 4,          -- current + next N-1 on the maps
  miniPin = true,        -- the card step's pin on the minimap (off: the game's own marker, with its above/below arrow, shows alone)
  miniPinScale = 0.5,    -- its size (small: the game's own marker and its above/below arrow show)
  pathLine = true,       -- dotted walking path on the world map and minimap
  meshLine = false,      -- "Detailed map line": the line along the ground, round walls and cliffs, in the zones with a mesh (NavMesh.lua); off: none of it loads
  trails = true,         -- record where you walk in the capital cities (improves city paths)
  locked = false,
  rewardHint = true,     -- highlight the best quest reward
  combatFade = false,    -- fade the card while in combat
  smartNext = true,      -- the live solver picks what to do next from where you are (Next.lua); off: the plan order
  autoFly = false,       -- at a flight master, take the flight the card's trip needs
  autoQuest = false,     -- accept route quests and hand in finished ones (no reward choice) by themselves
  markTarget = true,     -- the Target button (and its key) also puts a star on the NPC
  -- what the card shows (the options' Card tab; its presets set these)
  cardNotes = true,      -- the small hint line under a step (warnings always show)
  cardZones = true,      -- the footer: "Next zone: Arathi, after 2 quests here"
  cardOffers = true,     -- "another zone is worth a look" (Zones)
  cardItemQuests = true, -- an item in your bags that starts a quest
  remindBags = true,     -- bags nearly full: the nearest vendor
  remindFood = true,     -- eat for Well Fed
  remindGrimoire = true, -- warlocks: a grimoire at the demon trainer
  newsBar = true,        -- the "updated to ..." bar under the card after an update
  rail = true,           -- the card's side rail (UI/Card/Rail.lua): Route, Where to?, Side trips, Log check, Options; its tab hides it
  keepMoments = true,    -- keep notes of odd moments on the card for the next /bee report (Moments.lua; on your PC only)
  skin = "beeline",      -- the look (UI/Skins): read once at login; changing it reloads the UI (Options)
}

-- ns.Is(fn, ...): a yes/no question to the game (UnitOnTaxi, UnitIsAFK, IsFlying, IsIndoors...). Forever hides some
-- answers from addons (secret values: in dungeons and in combat); testing one is an error, so a hidden or missing
-- answer counts as "no". Every such question goes through here (install.sh refuses raw calls).
function ns.Is(fn, ...)
  if not fn then return false end
  local ok, v = pcall(fn, ...)
  if not ok or v == nil or (issecretvalue and issecretvalue(v)) then return false end
  return v and true or false
end
local listeners = {}
ns._listeners = listeners -- (the simulator's perf battery times each one: tests/_perf.lua)
-- every repeating timer the addon runs, kept so the perf battery can price what the addon costs per second standing or
-- walking (tests/_perf.lua): { period, fn }
ns._tickers = {}
-- Work spread over frames (Next.PickAsync): a job runs as a coroutine, ns.sliceCo, for up to ns.sliceBudget ms a frame.
-- Its long loops call ns.MaybeYield(), which pauses it there when the frame's slice is used up - and does nothing
-- anywhere else (a call outside the job, a test). ns.Call(f, ...) is pcall outside the job; inside it, a plain call (a
-- pause can't cross a pcall in Lua 5.1; an error ends the job, which says so)
-- A pause is only made where it can be resumed: never from under a pcall. In the game's Lua 5.1 a yield under one fails
-- ("attempt to yield across metamethod/C-call boundary") and the pcall takes that for the work's error - a join's trips
-- priced under FindPlace's pcall(ChooseStart), in the login's catch-up job, did. The addon's files call ns.PCall for
-- pcall (each has local pcall = ns.PCall): inside a job's slice it counts how deep in pcalls the job is (ns.noYield),
-- and ns.MaybeYield holds its pause until the job is out of them; outside a slice it is pcall. (A table.sort comparator
-- or a gsub callback is the same kind of boundary: no pause from inside one)
ns.sliceCo, ns.sliceT0, ns.sliceBudget, ns.noYield = nil, 0, 1, 0
function ns.MaybeYield()
  if ns.sliceCo and ns.noYield == 0 and debugprofilestop() - ns.sliceT0 >= ns.sliceBudget and coroutine.running() == ns.sliceCo then coroutine.yield() end
end
local rawPcall = pcall
local function outOf(d, ...) ns.noYield = d; return ... end
function ns.PCall(f, ...)
  if not ns.sliceCo then return rawPcall(f, ...) end
  local d = ns.noYield
  ns.noYield = d + 1
  return outOf(d, rawPcall(f, ...))
end
function ns.Call(f, ...)
  if ns.sliceCo and coroutine.running() == ns.sliceCo then return true, f(...) end
  return pcall(f, ...)
end
function ns.NewTicker(period, fn)
  ns._tickers[#ns._tickers + 1] = { period = period, fn = fn }
  return C_Timer.NewTicker(period, fn)
end
-- ns.Debounce(secs, fn) -> a function: a burst of calls runs fn once, secs after the first (fn reads the state then)
-- (the pending run is known by the C_Timer.After that holds it: a test world swaps that one and drops its timers)
function ns.Debounce(secs, fn)
  local via
  return function()
    local after = C_Timer.After
    if via == after then return end
    via = after
    after(secs, function() if via == after then via = nil end; fn() end)
  end
end
local function isGameEvent(event)
  if event:find("^FR_") then return false end -- our own messages
  if C_EventUtils and C_EventUtils.IsEventValid then return C_EventUtils.IsEventValid(event) end
  return true
end
-- ns.On("EVENT", fn, first): pub/sub for our FR_* messages; game events are registered on demand. first: run before
-- the listeners already registered (a reader that must see the event before anything acts on it)
function ns.On(event, fn, first)
  if not listeners[event] then
    listeners[event] = {}
    if isGameEvent(event) then pcall(ns.frame.RegisterEvent, ns.frame, event) end
  end
  if first then table.insert(listeners[event], 1, fn) else table.insert(listeners[event], fn) end
end
-- Error log: every error in our code is kept (deduplicated, with a count) in BeelineDB.log with what we were doing
-- at the time (route, step, zone, level, build), so it can be read from SavedVariables after a /reload. It also goes to
-- the normal error handler (BugSack), but only the first few times per message, so one bug can't flood the screen.
ns.VERSION = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version") or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or "?"
local logged = {}
function ns.LogError(where, err)
  local msg = tostring(err)
  local key = where .. "|" .. msg
  local n = (logged[key] or 0) + 1
  logged[key] = n
  if BeelineDB then
    BeelineDB.log = BeelineDB.log or {}
    local log = BeelineDB.log
    local e
    for _, x in ipairs(log) do if x.key == key then e = x; break end end
    if not e then
      local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
      e = { key = key, where = where, msg = msg, stack = debugstack and debugstack(2, 12, 0) or nil, count = 0,
        first = time and time() or 0, version = ns.VERSION, route = ns.char and ns.char.routeId, step = ns.Engine and ns.Engine.current,
        map = mapID, level = UnitLevel and UnitLevel("player") }
      -- what you were doing: the step on the card, the plan, and the addon's last few decisions (enough to fix most
      -- bugs from the save alone). Gathered under pcall: this runs inside an error already.
      pcall(function()
        local i = ns.Engine and ns.Engine.Shown and ns.Engine.Shown()
        local s = i and BeelineData and BeelineData.steps and BeelineData.steps[i]
        if s then e.shown = string.format("%d %s q%s %s", i, tostring(s.k), tostring(s.q or "-"), tostring(s.text or s.name or ""):sub(1, 60)) end
        e.routeId = BeelineData and BeelineData.id
        e.plan = BeelinePlan and BeelinePlan.generated
        e.combat = InCombatLockdown and InCombatLockdown() or nil
        e.taxi = ns.Is(UnitOnTaxi, "player") or nil
        local w, recent = BeelineDB.why, {}
        if type(w) == "table" then for j = math.max(1, #w - 5), #w do local x = w[j]; if x then recent[#recent + 1] = tostring(x.k) .. ": " .. tostring(x.x):sub(1, 90) end end end
        e.recent = recent
      end)
      table.insert(log, 1, e)
      while #log > 40 do table.remove(log) end
    end
    e.count = e.count + 1; e.last = time and time() or 0
  end
  if n <= 3 then geterrorhandler()(msg) end
end
-- wrap a function so its errors are logged instead of thrown (for OnUpdate scripts and timers)
ns.stats = {} -- name -> { n, total, max } (ms), since the last perf sample
local clock = debugprofilestop
ns.loadedAt = GetTime and GetTime() or 0
-- the slow moments, with what set them off: a timing of SLOW_MS or more is kept (the last 30, per character) with the
-- game event being handled (nil: a timer or a frame), the seconds since the UI loaded and your level (/bee report perf)
ns.SLOW_MS = 30
-- ns.Mark() at the start of a timed moment, passed to ns.Time: a slow one then also keeps what it did - the trip
-- searches (Travel.searches) and the step statuses worked out (Engine.statusN) - so a report says why, not only that.
function ns.MarkInto(t)
  local E = ns.Engine
  t.trips, t.status, t.walks, t.fromStart = ns.Travel and ns.Travel.searches or 0, E and E.statusN or 0, E and E.computeN or 0, E and E.walkN or 0
  return t
end
function ns.Mark() return ns.MarkInto({}) end -- (a slice reuses its own: ns.MarkInto, Jobs.lua)
function ns.Time(name, ms, mark)
  local st = ns.stats[name]; if not st then st = { n = 0, total = 0, max = 0 }; ns.stats[name] = st end
  st.n = st.n + 1; st.total = st.total + ms; if ms > st.max then st.max = ms end
  if ms >= ns.SLOW_MS and ns.char then
    local L = ns.char.slow; if not L then L = {}; ns.char.slow = L end
    local e = { n = name, ms = math.floor(ms * 10 + 0.5) / 10, at = time and time() or 0, up = GetTime and math.floor(GetTime() - ns.loadedAt) or nil, ev = ns.event, lvl = UnitLevel and UnitLevel("player") or nil }
    if mark then local now = ns.Mark(); e.trips, e.status, e.walks, e.fromStart = now.trips - mark.trips, now.status - mark.status, now.walks - mark.walks, now.fromStart - mark.fromStart
      -- (where: the code lines it was at, short - "Next.lua:870 < Next.lua:1050")
      if mark.where then local w = {}; for f, l in tostring(mark.where):gmatch("([%w_]+%.lua)\"?%]?:(%d+)") do if f ~= "Core.lua" then w[#w + 1] = f .. ":" .. l end; if #w >= 3 then break end end; e.where = table.concat(w, " < ") end
    end
    L[#L + 1] = e
    while #L > 30 do table.remove(L, 1) end
  end
end
function ns.Guard(where, fn)
  return function(...)
    local t0 = clock and clock()
    local ok, err = pcall(fn, ...)
    if t0 then ns.Time(where, clock() - t0) end
    if not ok then ns.LogError(where, err) end
    return err
  end
end
-- (a listener runs under pcall, so it may never pause a job: the job's slice is off while listeners run - inside a
-- route pass, FR_STEP_DONE's listeners run in the pass's coroutine, and a pause in one would be lost with its work)
local function dispatch(event, ...)
  for _, fn in ipairs(listeners[event] or {}) do
    local ok, err = pcall(fn, ...)
    if not ok then ns.LogError(event, err) end
  end
end
-- an event whose listeners are one change: ns.Around(event, wrap), and wrap(dispatch, event, ...) runs them (Engine.lua
-- holds the route's refreshes over FR_STATE's listeners - the plan's own, a hand-in added, a side quest's stop - and
-- runs one after them)
local around = {}
function ns.Around(event, wrap) around[event] = wrap end
function ns.Fire(event, ...)
  local co = ns.sliceCo
  ns.sliceCo = nil
  local wrap = around[event]
  if wrap then
    local ok, err = pcall(wrap, dispatch, event, ...)
    if not ok then ns.LogError(event, err) end
  else
    dispatch(event, ...)
  end
  ns.sliceCo = co
end

-- item API: Forever moved these into C_Item (the old globals are gone)
ns.GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
ns.GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
ns.GetItemIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
ns.GetItemStats = (C_Item and C_Item.GetItemStats) or GetItemStats

ns.frame = CreateFrame("Frame")
-- (ns.event: the game event being handled, for the slow moments above)
ns.frame:SetScript("OnEvent", function(_, event, ...) local was = ns.event; ns.event = event; ns.Fire(event, ...); ns.event = was end)
ns.frame:RegisterEvent("ADDON_LOADED")

local function copyDefaults(dst, src)
  for k, v in pairs(src) do
    if dst[k] == nil then dst[k] = type(v) == "table" and CopyTable(v) or v end
  end
end

-- one plan file (Route.lua) for all your characters: each has its own block (BeelineByChar["Name-Realm"]), written
-- by that character's companion; only yours is loaded. An older file with a single plan is used as it is.
-- On a fresh login the name can still read "Unknown" when the addon loads; then the key saved last time is used, and the
-- plan is looked up again at PLAYER_LOGIN.
local function normName(s) return (tostring(s or ""):lower():gsub("[^%w]", "")) end
function ns.CharKey()
  local okN, name = pcall(UnitName, "player")
  local okR, realm = pcall(GetRealmName)
  name = okN and type(name) == "string" and not (issecretvalue and issecretvalue(name)) and name or nil
  realm = okR and type(realm) == "string" and not (issecretvalue and issecretvalue(realm)) and realm or nil
  if not name or name == "" or name == UNKNOWNOBJECT or name == "Unknown" or not realm or realm == "" then
    return BeelineChar and BeelineChar.charKey or nil
  end
  return (name .. "-" .. realm):gsub("%s", "") .. ""
end
-- your block: the exact key, else the same key ignoring case, spaces and punctuation (the planner names blocks after
-- the WTF folder, which can spell the realm differently), else the one block with your name. Never another character's.
function ns.FindMyPlan(key)
  if not key then return nil end
  if BeelineByChar[key] then return BeelineByChar[key], key end
  -- the block this character matched before (the game's realm name can differ from the folder the planner names it after)
  local before = BeelineChar and BeelineChar.planBlock
  if before and BeelineByChar[before] and normName(before:match("^([^-]+)")) == normName(key:match("^([^-]+)")) then return BeelineByChar[before], before end
  local want, wantName = normName(key), normName(key:match("^([^-]+)"))
  local byName, nByName
  for k, f in pairs(BeelineByChar) do
    if normName(k) == want then return f, k end
    if normName(k:match("^([^-]+)")) == wantName then byName, nByName = { f, k }, (nByName or 0) + 1 end
  end
  if nByName == 1 then return byName[1], byName[2] end
end
-- the built-in plan for your race and class (Starter.lua, made by tools/starter.js): followed when there is no plan of
-- your own (an addon-only install, or before the companion has planned for a new character)
-- does this install have the companion? It writes the plan file (Route.lua: BeelineByChar); an addon-site install
-- never has one. What only the companion reads (walking trails, learning) is recorded only then.
function ns.HasCompanion() return type(BeelineByChar) == "table" and next(BeelineByChar) ~= nil end
function ns.StarterKey()
  local okR, _, race = pcall(UnitRace, "player")
  local okC, _, class = pcall(UnitClass, "player")
  if not (okR and okC) or type(race) ~= "string" or type(class) ~= "string" then return nil end
  race = normName(race)
  if race == "scourge" then race = "undead" end -- the game's token for undead; the plans are named undead_<class>
  -- the Horde's Skyborne (Windshaper Skyborne): skybornehorde, told apart by the faction
  if race:find("skyborne", 1, true) then
    race = (race:find("windshaper", 1, true) or ns.State.MyFaction() == "H") and "skybornehorde" or "skyborne"
  end
  return race .. "-" .. normName(class)
end
-- The built-in plan for your race and class. The plans come as one load-on-demand addon per faction
-- (Beeline_Plans_Alliance / _Horde, tools/bundle-plans.js), each plan as text: only yours is made into code and
-- the rest is let go. An older install's per-plan addon (Beeline_Starter_<race>_<class>) still works.
function ns.LoadStarter(sk)
  local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
  if not load then return false end
  local sides = ns.State.MyFaction() == "H" and { "Horde", "Alliance" } or { "Alliance", "Horde" }
  for _, side in ipairs(sides) do
    if not (type(BeelinePlanSources) == "table" and BeelinePlanSources[sk]) then pcall(load, "Beeline_Plans_" .. side) end
  end
  local src = type(BeelinePlanSources) == "table" and BeelinePlanSources[sk]
  -- the zone routes every plan of the faction shares are kept once (tools/bundle-plans.js): back into yours only
  if src and type(BeelinePlanShared) == "table" then
    local shared = BeelinePlanShared
    src = src:gsub("\n%-%-@zr ([^@\n]+)@", function(id) return shared[id] end)
    -- and the step lines: "--@sl i:sec:id,..." is your plan's step list, each step the faction's line i
    -- with its section and id put back
    if type(shared.lines) == "string" and src:find("\n--@sl ", 1, true) then
      local lines = {}
      for l in (shared.lines .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
      src = src:gsub("\n%-%-@sl ([^@\n]*)@", function(list)
        local out = {}
        for e in list:gmatch("[^,]+") do
          local i, sec, id = e:match("^(%d+):(%d*):(%d*)$")
          local body = i and lines[tonumber(i)]
          if not body then return nil end -- (a marker this can't read stays a comment: no steps, the plan still loads)
          out[#out + 1] = "      " .. body:sub(1, -3) .. (sec ~= "" and (", sec = " .. sec) or "") .. (id ~= "" and (", id = " .. id) or "") .. " },"
        end
        return "\n" .. table.concat(out, "\n")
      end)
    end
  end
  BeelinePlanSources, BeelinePlanShared = nil, nil -- every other plan's text goes
  if src then
    local chunk, err = loadstring(src, "plan " .. sk)
    if chunk then
      local ok, e = pcall(chunk)
      if not ok and ns.LogError then ns.LogError("plan", e) end
    elseif ns.LogError then ns.LogError("plan", err) end
    collectgarbage("collect")
  else
    pcall(load, "Beeline_Starter_" .. sk:gsub("%-", "_"))
  end
  return type(BeelineStarter) == "table" and BeelineStarter[sk] ~= nil
end
function ns.LoadMyPlan()
  local key, f, found
  if type(BeelineByChar) == "table" then
    key = ns.CharKey()
    f, found = ns.FindMyPlan(key)
  elseif BeelineRoutes or BeelineData then
    return true -- an older single-plan file
  end
  ns.planKey = { tried = key, found = found }
  if type(f) == "function" then
    if BeelineChar then BeelineChar.charKey = key; BeelineChar.planBlock = found end
  else
    local sk = ns.StarterKey()
    if sk and not (type(BeelineStarter) == "table" and BeelineStarter[sk]) then ns.LoadStarter(sk) end
    f = type(BeelineStarter) == "table" and sk and BeelineStarter[sk]
    if type(f) ~= "function" then return false end
    ns.planKey.starter = sk
  end
  local ok, err = pcall(f)
  if not ok and ns.LogError then ns.LogError("plan", err) end
  return ok
end
local starterSaid
function ns.StarterNote()
  if starterSaid or not (ns.planKey and ns.planKey.starter) then return end
  starterSaid = true
  C_Timer.After(5, function() ns.Print("Following the plan for your race and class (steps you've already done are skipped). Bored of a zone? Where to? on the card's side rail (/bee home) shows where else you could go.") end)
end

-- flight masters and vendors come for both factions (FlightMasters.lua, Vendors.lua: ns.FLIGHT_BY, ns.VENDORS_BY);
-- yours are ns.FLIGHT and ns.VENDORS. Picked when the addon loads and again at login (the faction is surely known then)
-- (these run from ADDON_LOADED on, once every file - State.lua too - has loaded)
function ns.UseFaction()
  local side = ns.State.MyFaction() == "H" and "Horde" or "Alliance"
  if ns.FLIGHT_BY and ns.FLIGHT_BY[side] then ns.FLIGHT = ns.FLIGHT_BY[side] end
  if ns.VENDORS_BY and ns.VENDORS_BY[side] then ns.VENDORS = ns.VENDORS_BY[side] end
  return side
end
-- what you do to the route (the card's buttons, the slash commands): FR_USER_ACTION(name, ...) fires just before the
-- Engine function runs, its arguments after the name. Wrapped once, here, when every Engine file has loaded.
ns.USER_ACTIONS = { "Skip", "MarkDone", "Undo", "Back", "Forward", "FocusOn", "Nope", "NotOffered", "Jump", "Later" }
local actionsWrapped
function ns.WrapUserActions()
  local E = ns.Engine
  if actionsWrapped or not E then return end
  actionsWrapped = true
  for _, name in ipairs(ns.USER_ACTIONS) do
    local fn = E[name]
    if type(fn) == "function" then E[name] = function(...) ns.Fire("FR_USER_ACTION", name, ...); return fn(...) end end
  end
end
ns.On("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  ns.WrapUserActions()
  ns.migrated = { ns.Migrate.Run() } -- ForeverRoute's saves, once (Migrate.lua)
  ns.UseFaction()
  ns.hasPlan = ns.LoadMyPlan()
  BeelineDB = BeelineDB or {}
  BeelineChar = BeelineChar or {}
  -- the option once shared BeelineDB.moments with the moments queue: an off saved that way stays off
  if BeelineDB.moments == false then BeelineDB.keepMoments, BeelineDB.moments = false, nil end
  BeelineDB.zonesPanel = nil -- (the zones-ahead panel beside the card is gone, and its setting with it: the side rail took its tab)
  copyDefaults(BeelineDB, ns.DEFAULTS)
  ns.db = BeelineDB
  ns.Style.UseSkin(ns.db.skin) -- (before any frame is built: FR_LOADED builds the card)
  -- combat fade used to default on: off once for everyone (anyone can turn it back on)
  if not ns.db.combatFadeReset then ns.db.combatFade = false; ns.db.combatFadeReset = true end
  -- the minimap marker's size used to default to 1.0: still on that old default, moved to the new one once
  if not ns.db.miniPinReset then if ns.db.miniPinScale == 1 then ns.db.miniPinScale = ns.DEFAULTS.miniPinScale end; ns.db.miniPinReset = true end
  ns.char = BeelineChar
  ns.char.perf = nil -- (a logout record nothing read: out of the save)
  -- stay on the path you were on; nothing switches unless you choose (the zone you asked for is the one exception)
  ns.SelectRoute(ns.SavedRoute(), true)
  -- a path you asked for has arrived: switch to it once (you can switch away; it won't pull you back)
  if ns.char.requestZone and ns.char.requestHandled ~= ns.char.requestZone then
    for _, r in ipairs(ns.MainRoutes()) do
      if r.requested == ns.char.requestZone then ns.SelectRoute(r.id, true); ns.char.requestHandled = ns.char.requestZone; C_Timer.After(5, function() ns.Print("Now on the path you asked for, starting in " .. r.requested .. ".") end); break end
    end
  end
  ns.Fire("FR_LOADED")
end)
-- the name wasn't known yet when the addon loaded: look again now, and show the plan if it's found
-- maps the planner has no world bounds for (Forever's new zones): the client knows them for any map, wherever you
-- are - recorded at login for the planner (tools/learn.js -> map-extras.json)
ns.MAPS_TO_MEASURE = { 2521, 2665, 2548, 2652, 2482 }
function ns.RecordMapBounds()
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) or not BeelineDB then return 0 end
  ns.Util.Sub(BeelineDB, "mapBounds")
  local n = 0
  for _, id in ipairs(ns.MAPS_TO_MEASURE) do
    local ok, inst, tl = pcall(C_Map.GetWorldPosFromMapPos, id, CreateVector2D(0, 0))
    local ok2, _, br = pcall(C_Map.GetWorldPosFromMapPos, id, CreateVector2D(1, 1))
    if ok and ok2 and tl and br and tl.GetXY then
      local top, left = tl:GetXY()
      local bottom, right = br:GetXY()
      if left and right and top and bottom and not (issecretvalue and (issecretvalue(left) or issecretvalue(top))) then
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(id)
        BeelineDB.mapBounds[id] = { left = left, right = right, top = top, bottom = bottom, inst = inst, name = info and info.name }
        n = n + 1
      end
    end
  end
  return n
end
ns.On("PLAYER_LOGIN", function()
  ns.UseFaction()
  pcall(ns.RecordMapBounds)
  local key = ns.CharKey()
  if BeelineChar and key then BeelineChar.charKey = key end
  -- on the built-in plan: your own may be findable now that the name is known
  local onStarter = ns.planKey and ns.planKey.starter
  if ns.hasPlan and ns.Routes()[1] and not onStarter then return end
  if onStarter and ns.Routes()[1] and not (type(BeelineByChar) == "table" and ns.FindMyPlan(key)) then ns.StarterNote(); return end
  ns.hasPlan = ns.LoadMyPlan()
  if ns.Routes()[1] then
    ns.SelectRoute(ns.SavedRoute(), false)
    ns.StarterNote()
  else
    C_Timer.After(5, function()
      ns.Print("No plan for " .. tostring(key) .. " in Route.lua" .. (type(BeelineByChar) == "table" and " (plans there: " .. (function() local t = {} for k in pairs(BeelineByChar) do t[#t + 1] = k end return table.concat(t, ", ") end)() .. ")" or "") .. ". /reload to load the plan for your race and class.")
    end)
  end
end)

-- Where the Map button takes you for step i: the map to open and the step whose pin to flash there.
--   a step with a spot of its own: its map, its pin
--   a trip (a fly step with no spot): the zone it goes to, and the pin of the first stop there (not the arrow's
--     target, which for a trip is the flight master where you stand)
--   a spot nobody knows (s.unknown): its zone, no pin
-- -> uiMapID, step index (or nil); nil when the step has no place on a map
function ns.MapSpot(i)
  local list = BeelineData and BeelineData.steps
  local s = i and list and list[i]
  if not s then return nil end
  if s.m and s.x and not s.unknown then return s.m, i end
  if s.to and s.k == "fly" then
    for j = i + 1, #list do
      local t = list[j]
      if ns.Engine.IsTrip(t) then break end
      if t.m == s.to and t.x and not t.unknown and not ns.Engine.IsDone(j) then return s.to, j end
    end
    return s.to, nil
  end
  return s.m, nil
end

function ns.ShowOnMap(i)
  local s = i and BeelineData and BeelineData.steps[i]
  if not s then return end
  local m, pin = ns.MapSpot(i)
  if not m then ns.Print("That step has no map spot (it's inside a dungeon, or a note)."); return end
  if InCombatLockdown() then ns.Print("Can't open the map in combat."); return end
  if i ~= ns.Engine.CardAt() then ns.Engine.view = i end
  ns.Fire("FR_STEP", ns.Engine.Shown()) -- pins follow the step being looked at
  local function setMap()
    if WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame.SetMapID and WorldMapFrame:GetMapID() ~= m then WorldMapFrame:SetMapID(m) end
  end
  local ok, err = pcall(function()
    if WorldMapFrame and not WorldMapFrame:IsShown() then
      if OpenWorldMap then OpenWorldMap(m) elseif ToggleWorldMap then ToggleWorldMap() end
    end
    setMap()
  end)
  if not ok then ns.LogError("map", err) end
  -- again a moment later: an opening map goes to the zone you're in (the game's map does that as it opens, map addons
  -- can do it a frame later), which undid the step's map
  C_Timer.After(0, function() pcall(setMap) end)
  C_Timer.After(0.2, function() pcall(setMap) end)
  -- and make its pin flash, so the eye finds it among the map's own markers
  if pin and ns.Pins and ns.Pins.Blink then ns.Pins.Blink(pin) end
end

function ns.Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffffd25aBeeline|r " .. tostring(msg))
  -- everything the addon tells you is also kept (last 200) in BeelineDB.chat, so it can be read from your saves
  if BeelineDB then
    if type(BeelineDB.chat) ~= "table" then BeelineDB.chat = {} end
    local t = BeelineDB.chat
    t[#t + 1] = { t = time(), x = tostring(msg):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") }
    while #t > 200 do table.remove(t, 1) end
  end
end

-- keybinding labels (Bindings.xml)
BINDING_HEADER_BEELINE = "Beeline"
BINDING_NAME_BEELINE_SKIP = "Skip current step"
BINDING_NAME_BEELINE_BACK = "Look at previous step"
BINDING_NAME_BEELINE_UNDO = "Undo last skip / done"
BINDING_NAME_BEELINE_TOGGLE = "Show / hide the card"
BINDING_NAME_BEELINE_LIST = "Show your route (the Beeline window)"
_G["BINDING_NAME_CLICK BeelineTargetButton:LeftButton"] = "Beeline Targeting"

SLASH_BEELINE1 = "/bee"
SLASH_BEELINE2 = "/beeline"
SlashCmdList.BEELINE = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if msg == "" or msg == "toggle" then ns.Fire("FR_TOGGLE")
  elseif msg == "list" then ns.Fire("FR_TOGGLE_LIST")
  elseif msg == "home" or msg == "paths" then ns.Fire("FR_TOGGLE_PATHS")
  elseif msg == "why" then ns.WhyPrint(15)
  elseif msg == "save" then if ns.Card and ns.Card.Save then ns.Card.Save() else ReloadUI() end
  elseif msg == "dungeons" or msg == "dungeon" or msg == "trips" then ns.Fire("FR_TOGGLE_DUNGEONS")
  -- (the other side trips: the Beeline window on their view)
  elseif msg == "class" then ns.Dungeons.Toggle("class")
  elseif msg == "attune" or msg == "raids" then ns.Dungeons.Toggle("attune")
  elseif msg == "items" or msg == "bag" then ns.Dungeons.Toggle("reward")
  elseif msg == "card reset" then ns.db.uiScale, ns.db.scale = nil, 1; ns.Fire("FR_SETTINGS"); ns.db.hidden = nil; if ns.Card and ns.Card.ResetPos then ns.Card.ResetPos() end
  elseif msg == "target reset" then if ns.Card and ns.Card.ResetTarget then ns.Card.ResetTarget() else ns.db.targetPos = nil end
  elseif msg == "storage" then ns.Storage.Print()
  elseif msg == "scale" or msg:find("^scale ") then ns.Style.SlashScale(msg:sub(7))
  elseif msg == "skin" or msg:find("^skin ") then ns.SlashSkin(msg:sub(6))
  elseif msg == "news" then ns.Fire("FR_NEWS")
  elseif msg == "report" then ns.Fire("FR_REPORT", false)
  elseif msg == "report full" then ns.Fire("FR_REPORT", true)
  -- (the dev tools addon, Beeline_Dev, never in a release: times the hot paths where you stand)
  elseif msg == "report perf" then if ns.DevReportPerf then ns.DevReportPerf() else ns.Print("/bee report perf needs the Beeline dev tools (not part of a release)") end
  elseif msg == "logcheck" or msg == "cleanup" then ns.Fire("FR_TOGGLE_LOGCHECK")
  elseif msg == "nope" then ns.Engine.Nope()
  elseif msg == "rejoin" then ns.Engine.Rejoin()
  elseif msg == "nav" or msg == "pins" then for _, l in ipairs(ns.Nav.Report()) do ns.Print(l) end
  elseif msg == "perf" then
    local p = ns.Perf()
    ns.Print(string.format("memory %s  ·  refresh %.2f ms  ·  progress %.2f ms  ·  %d routes, %d unpacked", p.memoryKB and string.format("%.1f MB", p.memoryKB / 1024) or "?", p.refreshMs or 0, p.progressMs or 0, p.routes, p.unpacked))
  elseif msg == "trails" then
    local n, per = ns.Trails.Count(); local bits = {}
    for k, v in pairs(per) do bits[#bits + 1] = k .. " " .. v end
    ns.Print(string.format("city walking recorded: %d points%s. Saved on /reload or logout; the planner uses it next run.", n, #bits > 0 and (" (" .. table.concat(bits, ", ") .. ")") or ""))
  elseif msg == "log" then
    local log = BeelineDB.log or {}
    if #log == 0 then ns.Print("no errors logged.") end
    for k = 1, math.min(5, #log) do local e = log[k]; ns.Print(string.format("%dx [%s] %s", e.count or 1, e.where or "?", e.msg or "?")) end
  elseif msg == "log clear" then BeelineDB.log = {}; ns.Print("error log cleared.")
  elseif msg == "skip" then ns.Engine.Skip()
  elseif msg == "back" then ns.Engine.Back()
  elseif msg == "undo" then ns.Engine.Undo()
  elseif msg == "reset" then ns.char.skipped, ns.char.manualDone, ns.char.history = {}, {}, {}; ns.Engine.Refresh(); ns.Print("skips and manual ticks cleared.")
  elseif msg == "lock" then ns.db.locked = not ns.db.locked; ns.Fire("FR_SETTINGS", "locked"); ns.Print(ns.db.locked and "locked." or "unlocked.")
  elseif msg == "arrow" then ns.db.arrow = not ns.db.arrow; ns.Fire("FR_SETTINGS", "arrow")
  elseif msg == "demo" then ns.Demo.Start()
  elseif msg == "snapshot" then ns.State.Snapshot("manual"); ns.Print("snapshot saved - written to disk on /reload or logout.")
  elseif msg == "options" or msg == "config" then ns.Fire("FR_OPEN_OPTIONS")
  else
    ns.Print("/bee - card · /bee list - your route · /bee home - home base (pick a zone) · /bee dungeons · /bee class · /bee attune · /bee items - side trips · /bee logcheck - what to abandon · /bee rejoin - pick the built-in plan up at your level · /bee report - copy a bug report · /bee news - what changed · /bee log - recent errors · /bee nav - where the game says you, the step and the minimap are · /bee skip · /bee back · /bee undo · /bee lock · /bee arrow · /bee demo · /bee skin · /bee options")
  end
end
-- /fr (ForeverRoute's old command) still works, with a one-time note, unless another addon has it: then it's theirs.
-- /bl and /bline as well, only when free (other addons use /bl): checked at login, when every addon has registered its own.
local function slashTaken(cmd)
  for key in pairs(SlashCmdList) do
    for i = 1, 9 do
      local c = _G["SLASH_" .. key .. i]
      if c == nil then break end
      if type(c) == "string" and c:lower() == cmd then return key end
    end
  end
end
function ns.OldSlash()
  if slashTaken("/fr") then return false end
  local said
  SLASH_BEELINEOLD1 = "/fr"
  SlashCmdList.BEELINEOLD = function(msg)
    if not said then said = true; ns.Print("/fr is now /bee - ForeverRoute is now called Beeline.") end
    SlashCmdList.BEELINE(msg)
  end
  return true
end
function ns.ShortSlash()
  local got = {}
  for i, cmd in ipairs({ "/bl", "/bline" }) do
    if not slashTaken(cmd) then got[#got + 1] = cmd end
  end
  for i = 1, 2 do _G["SLASH_BEELINESHORT" .. i] = got[i] end
  if #got > 0 then SlashCmdList.BEELINESHORT = function(msg) SlashCmdList.BEELINE(msg) end end
  return got
end
ns.On("PLAYER_LOGIN", function() ns.OldSlash(); ns.ShortSlash() end)

-- /bee perf: what the addon costs in your game (memory, time per refresh); nothing saved (memOnly: a no-op)
function ns.Perf(memOnly)
  if memOnly then return nil end
  if UpdateAddOnMemoryUsage then pcall(UpdateAddOnMemoryUsage) end
  local mem = GetAddOnMemoryUsage and select(2, pcall(GetAddOnMemoryUsage, ADDON)) or nil
  local t = debugprofilestop
  local refresh, progress
  if t then
    local a = t(); for _ = 1, 10 do ns.Engine.Refresh() end; local b = t(); for _ = 1, 10 do ns.Engine.Progress() end; local c = t()
    refresh, progress = (b - a) / 10, (c - b) / 10
  end
  local unpacked = 0; for _, r in ipairs(ns.Routes()) do if r.steps then unpacked = unpacked + 1 end end
  return { memoryKB = type(mem) == "number" and math.floor(mem) or nil, refreshMs = refresh, progressMs = progress, routes = #ns.Routes(), unpacked = unpacked, at = time and time() }
end

-- (the addon's memory is read only at logout: UpdateAddOnMemoryUsage walks every loaded addon's memory, tens of ms)
local function perfSample(atLogout)
  if atLogout == true and UpdateAddOnMemoryUsage then pcall(UpdateAddOnMemoryUsage) end
  local okm, mem = pcall(GetAddOnMemoryUsage or error, ADDON)
  local e = { at = time and time() or 0, memoryKB = okm and type(mem) == "number" and math.floor(mem) or nil, level = UnitLevel("player"), route = ns.char and ns.char.routeId } -- no map id: Forever may hand it out as a protected value that can't be saved
  for name, st in pairs(ns.stats) do e[name] = string.format("%d calls, avg %.2f ms, max %.2f ms", st.n, st.n > 0 and st.total / st.n or 0, st.max) end
  wipe(ns.stats)
  ns.char.perfLog = ns.char.perfLog or {}
  table.insert(ns.char.perfLog, e)
  while #ns.char.perfLog > 20 do table.remove(ns.char.perfLog, 1) end
end
-- failures go to the error log
local guardedSample = ns.Guard("perf", perfSample)
ns.On("FR_LOADED", function() C_Timer.After(60, guardedSample); ns.NewTicker(300, guardedSample) end)
ns.On("PLAYER_LOGOUT", function() guardedSample(true) end)
ns._perfSample = perfSample -- for tests


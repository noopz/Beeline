-- Trip planning for a step (Engine.TravelFor, TravelPlan, TravelTarget): how to get to it when it is more than a walk.
-- Part of the route engine; loaded right after Engine.lua (it registers no events).
local _, ns = ...
local pcall = ns.PCall or pcall -- (a job never pauses under it: Core.lua)
local Engine = ns.Engine
local State = ns.State
local function steps() return BeelineData and BeelineData.steps or {} end
local isTrip = Engine.IsTrip
local planIndex = Engine._planIndex

-- where a travel step without coordinates should point: the flight master in the zone you're in
function Engine.TravelTarget(s)
  if not s or s.x or s.k ~= "fly" then return nil end
  -- the live trip the card leads with, when there is one: its leg's waypoint (the crossing a ride heads for, the
  -- flight master or pier of the trip) - one answer for card, arrow and map pin. TravelPlan's own guess below ("fly to
  -- Feralas, then ride") is only for when no trip is planned. Aboard, or a hearth / teleport first: nowhere to walk.
  local trip = Engine.TravelFor and Engine.TravelFor(s)
  if trip then
    if not (trip.m and trip.x) then return nil end
    local l1 = trip.legs and trip.legs[1]
    return trip.m, trip.x, trip.y, (l1 and l1.how == "fly" and l1.npc) or trip.fm or nil
  end
  local m, px, py = ns.State.Position()
  local plan = Engine.TravelPlan(s)
  if plan and (plan.ride or not plan.via or plan.via == m) then return plan.m, plan.x, plan.y, nil end
  local list = m and ns.FLIGHT and ns.FLIGHT[m]
  if not list then return nil end
  local best, bd
  for _, fm in ipairs(list) do
    local d = (px and py) and ((fm[1] - px) ^ 2 + (fm[2] - py) ^ 2) or 0
    if not bd or d < bd then best, bd = fm, d end
  end
  return m, best[1], best[2], best[3]
end
-- how to get to a travel step's destination, from the flight paths you actually have. Aims at the first stop there
-- (where you're really going), and compares riding straight there with flying: walk to a flight master on your map,
-- the flight, then walk from where you land. nil = just fly as usual.
-- -> { ride = true (ride straight there) | via = uiMap to fly to first, viaName, m, x, y = where to go, stop = step }
Engine.FLIGHT_YARDS = 700 -- a flight costs about this much walking (take-off, the flight, landing)
local function stepIndex(s) if not s then return nil end return planIndex().idx[s] end
local function firstStop(s)
  if s._stop then return s._stop end
  local i = stepIndex(s); if not i then return nil end
  local list = steps()
  for j = i + 1, #list do
    local t = list[j]
    if isTrip(t) then return nil end
    if t.m and t.x and not t.unknown and t.m == s.to then return t end
  end
end
function Engine.TravelPlan(s)
  local HBD = LibStub("HereBeDragons-2.0")
  if not (s and s.k == "fly" and s.to and not s.boat and ns.FLIGHT and HBD) then return nil end
  local destName = s.dest or s.text
  if not destName then return nil end
  -- (a flight point of that zone you know, by its flight master - Travel.KnowsFlightPoint: of a zone with two, only
  -- the one you took; without one known, the zone's first for where a flight would land)
  local knows = function(m, f) return ns.Travel.KnowsFlightPoint(m, f[3]) and true or false end
  local fm, fmKnown
  for _, f in ipairs(ns.FLIGHT[s.to] or {}) do if knows(s.to, f) then fm, fmKnown = f, true; break end end
  fm = fm or (ns.FLIGHT[s.to] and ns.FLIGHT[s.to][1])
  local stop = firstStop(s)
  local tx, ty = (stop and stop.x) or (fm and fm[1]) or 0.5, (stop and stop.y) or (fm and fm[2]) or 0.5
  local wx, wy, inst = HBD:GetWorldCoordinatesFromZone(tx, ty, s.to)
  if not wx then return nil end
  local d = function(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end
  local pm, px, py = ns.State.Position()
  local hx, hy, hinst
  if pm and px then hx, hy, hinst = HBD:GetWorldCoordinatesFromZone(px, py, pm) end
  local rideYd = (hx and hinst == inst) and d(hx, hy, wx, wy) or nil
  -- the nearest flight master on your map (where a flight would start)
  local startYd
  for _, f in ipairs((pm and ns.FLIGHT[pm]) or {}) do
    local fx, fy, finst = HBD:GetWorldCoordinatesFromZone(f[1], f[2], pm)
    if fx and hx and finst == hinst then local dd = d(hx, hy, fx, fy); if not startYd or dd < startYd then startYd = dd end end
  end
  local plan = { m = s.to, x = tx, y = ty, stop = stop }
  if fmKnown then
    -- you can fly right there: only worth riding if the first stop is closer than the flight would make it
    if not (rideYd and fm) then return nil end
    local lx, ly = HBD:GetWorldCoordinatesFromZone(fm[1], fm[2], s.to)
    local flyYd = (startYd or 0) + Engine.FLIGHT_YARDS + (lx and d(lx, ly, wx, wy) or 0)
    if rideYd < flyYd then plan.ride = true; plan.yards = rideYd; return plan end
    return nil
  end
  -- no flight path there: fly to the one you have that lands closest to the first stop, unless riding is shorter
  local best
  for m, list in pairs(ns.FLIGHT) do
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(m)
    if info and info.name and m ~= s.to then
      for _, f in ipairs(list) do
        if knows(m, f) then
          local fx, fy, finst = HBD:GetWorldCoordinatesFromZone(f[1], f[2], m)
          if fx and finst == inst then
            local dd = d(fx, fy, wx, wy)
            if not best or dd < best.d then best = { d = dd, m = m, name = info.name } end
          end
        end
      end
    end
  end
  if best and best.m ~= pm and not (rideYd and rideYd <= (startYd or 0) + Engine.FLIGHT_YARDS + best.d) then plan.via, plan.viaName = best.m, best.name
  else plan.ride = true; plan.yards = rideYd end
  return plan
end

-- any step: how to get there, when it is more than a walk.
-- -> nil (a walk in the zone you are in, or unknown), or { how = "fly" | "via" | "ride", m, x, y = where the arrow
--    points now, text = what to do, fm = flight master name when the arrow points at one }
-- One trip planner for every trip (ns.Travel): another zone or continent is always planned; a step in your own zone
-- comes back as a trip only when a known flight is clearly quicker than the long walk (ns.Travel.Shortcut).
-- Memoized per step and situation (position to a few yards, level, known flight paths, flying/sailing, hearthstone,
-- current trip): card, arrow and pins ask on every refresh and a trip costs ~15 ms.
local tripMemo = {}
-- (the situation, as values compared in place: no key string per ask)
local function tripSame(m, pm, fx, fy, L, n, onTaxi, aboard, bind, last, bm, rejoin)
  return m[2] == pm and m[3] == fx and m[4] == fy and m[5] == L and m[6] == n and m[7] == onTaxi and m[8] == aboard and m[9] == bind
    and m[10] == last and m[11] == bm and m[12] == rejoin
end
function Engine.TravelFor(s)
  if not s then return nil end
  local pm, px, py = ns.State.Position()
  local n = State.KnownTaxiCount()
  local okB, b = pcall(GetBindLocation)
  local fx, fy = px and math.floor(px * 400) or "-", py and math.floor(py * 400) or "-"
  local L, onTaxi, aboard = UnitLevel("player") or 0, ns.Is(UnitOnTaxi, "player"), ns.Arrow and ns.Arrow.aboard
  local bind, last = okB and b, Engine.lastTripStep == s
  local bm = (ns.char and ns.char.boundAt and ns.char.boundAt.m) or "-"
  local rejoin = ns.Next and ns.Next.rejoin and ns.Next.rejoin.trip ~= nil
  local m = tripMemo[s]
  if m and tripSame(m, pm, fx, fy, L, n, onTaxi, aboard, bind, last, bm, rejoin) then return m[1] end
  local v = Engine.TravelForUncached(s)
  tripMemo[s] = { v, pm, fx, fy, L, n, onTaxi, aboard, bind, last, bm, rejoin }
  -- (a fresh answer: the arrow follows when its first leg is not the one it points along - UI/Arrow.lua)
  if ns.Arrow and ns.Arrow.TripChanged then ns.Arrow.TripChanged(s, v) end
  return v
end
function Engine.TravelForUncached(s)
  if not s or s.k == "hearth" or s.unknown then return nil end -- (no known place: no trip to plan)
  -- on a taxi flight: nothing to plan from the sky (crossing a zone mid-air planned a ride from the ground below);
  -- the way on is planned when you land.
  if ns.Is(UnitOnTaxi, "player") then
    local l = { how = "onflight", text = "On the flight - sit tight, the way on is planned when you land" }
    return { how = "aboard", text = l.text, legs = { l } }
  end
  if s.boat then
    -- the route's own "Boat to X" step, once the ship has sailed: the pier is behind you, nothing to point at
    -- until you land (the step ticks on arrival)
    if ns.Arrow and ns.Arrow.aboard then
      local l = { how = "aboard", text = "On the boat to " .. ((s.text or ""):match("^Boat to (.+)$") or s.dest or "the other side") .. " - sit tight" }
      return { how = "aboard", text = l.text, legs = { l } }
    end
    -- not sailing yet: in the pier's zone the step's own pier is the target (nil below); from anywhere else, the
    -- way to that pier is planned like any other stop (not a straight line from Goldshire or the tram)
    if not (s.m and s.x) then return nil end
  end
  local pm, px, py = ns.State.Position()
  -- another continent: boats, flights you know and rides, as one planned trip (ns.Travel)
  local HBD = LibStub("HereBeDragons-2.0")
  if pm and px and ns.Travel then
    local tm, tx, ty, tname, tstop -- (tstop: who the trip ends at, the last leg in their zone names them)
    if s.k == "fly" and s.to and not s.boat then
      local st = firstStop(s); local fm = ns.FLIGHT and ns.FLIGHT[s.to] and ns.FLIGHT[s.to][1]
      tm, tx, ty, tname = s.to, (st and st.x) or (fm and fm[1]) or 0.5, (st and st.y) or (fm and fm[2]) or 0.5, s.dest or s.text
      tstop = st and st.npc
    elseif s.m and s.x then tm, tx, ty, tname, tstop = s.m, s.x, s.y, s.zone, s.npc end
    -- (a stop added to the route has no zone name: its map's - the why read "to another continent" for a hand-in in Ironforge)
    if tm and not tname then local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(tm); tname = info and info.name or nil end
    if tm then
      local a1, a2, ai = HBD:GetWorldCoordinatesFromZone(px, py, pm)
      local b1, b2, bi = HBD:GetWorldCoordinatesFromZone(tx, ty, tm)
      -- somewhere no trip can start from (Deeprun Tram, a dungeon) and the step is out in the world: the current trip
      -- carries on; with none, it is planned when you come out (coordinates here mean nothing outside).
      if pm ~= tm and ns.Travel.OnNetwork and not ns.Travel.OnNetwork(pm, px, py) and not (a1 and b1 and ai == bi) then
        local last = Engine.lastTripStep == s and Engine.lastTrip
        if last and last[1] then
          local legs = {}
          for k, l in ipairs(last) do legs[k] = l end
          if ns.Travel.IsTram(legs[1]) then legs[1] = { how = "aboard", text = (legs[1].text:gsub("^Take the", "On the")) .. " - sit tight" } end
          return { how = "aboard", text = ns.Travel.Describe(legs), legs = legs }
        end
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(pm)
        local l = { how = "aboard", text = "In " .. ((info and info.name) or "here") .. ": the way on is planned when you come out" }
        return { how = "aboard", text = l.text, legs = { l } }
      end
      -- any other zone (or continent): the trip planner weighs riding, your flight paths and boats together.
      -- Your own zone: the same planner, asked only whether something beats the walk by a margin (nil: walk)
      if a1 and b1 then
        local legs
        local shortcut = ai == bi and pm == tm
        if not shortcut then legs = ns.Travel.Plan({ m = pm, x = px, y = py }, { m = tm, x = tx, y = ty, name = tname, stop = tstop })
        elseif s.k ~= "fly" and ns.Travel.Shortcut then
          legs = ns.Travel.Shortcut({ m = pm, x = px, y = py }, { m = tm, x = tx, y = ty, name = s.npc or tname })
          -- (not out of the zone while its quests come before the plan's trip - Next.rejoin: they only come first
          -- while you are in it, so leaving would drop them)
          if legs and ns.Next and ns.Next.rejoin and ns.Next.rejoin.trip then
            for _, l in ipairs(legs) do if l.m and l.m ~= tm then legs = nil; break end end
          end
        end
        if legs and legs[1] then
          -- already on the boat of the first leg: that leg is done, sit tight
          if legs[1].how == "boat" and ns.Arrow and ns.Arrow.aboard then
            local dest = legs[1].text:match(".* to (.+)$") or "the other side" -- the last "to": the boat's destination
            -- (a new list: the one given may be Travel.Shortcut's memo)
            local own = { { how = "aboard", text = "On the boat to " .. dest .. " - sit tight" } }
            for k = 2, #legs do own[k] = legs[k] end
            legs = own
            return { how = "aboard", text = ns.Travel.Describe(legs), legs = legs }
          end
          -- which step it is for: a trip worked out for a step you only looked at must not teach the boat's pier
          Engine.lastTrip, Engine.lastTripStep = legs, s
          local text = ns.Travel.Describe(legs)
          if ns.Why then ns.Why("travel", "to " .. (tname or "another continent") .. ": " .. text) end
          return { how = legs[1].how, m = legs[1].m, x = legs[1].x, y = legs[1].y, text = text, legs = legs, shortcut = shortcut or nil }
        end
      end
    end
  end
  if not (s.m and s.x) or s.k == "fly" then return nil end
  if not pm or pm == s.m then return nil end
  local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(s.m)
  local destName = (info and info.name) or s.zone or "there"
  local plan = Engine.TravelPlan({ k = "fly", to = s.m, dest = destName, text = destName, _stop = s })
  local function atFlightMaster(goal)
    local list = ns.FLIGHT and ns.FLIGHT[pm]; if not list then return nil end
    local best, bd; for _, f in ipairs(list) do local dd = (f[1] - px) ^ 2 + (f[2] - py) ^ 2; if not bd or dd < bd then best, bd = f, dd end end
    local m, x, y, fm = pm, best[1], best[2], best[3]
    return { how = "fly", m = m, x = x, y = y, fm = fm, text = "Fly to " .. goal .. (fm and (" - flight master " .. fm) or "") }
  end
  if not plan then return atFlightMaster(destName) end -- you have its flight path and flying is quicker
  if plan.ride then return { how = "ride", m = s.m, x = s.x, y = s.y, text = ns.RideWord() .. " to " .. destName .. (plan.yards and (" - " .. ns.Style.Distance(plan.yards)) or "") } end
  if plan.via and plan.via ~= pm then
    local t = atFlightMaster(plan.viaName); if t then t.how = "via"; t.text = "No " .. destName .. " flight path yet: fly " .. (t.fm and ("from " .. t.fm .. " ") or "") .. "to " .. plan.viaName .. ", then ride" end
    return t
  end
  return { how = "ride", m = s.m, x = s.x, y = s.y, text = ns.RideWord() .. " to " .. destName }
end

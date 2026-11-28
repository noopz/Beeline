-- Getting anywhere, as a small graph: you, the target, the ride network (towns, flight masters, docks and zone
-- crossings found in the walk maps, with walking yards between key points of a zone), the flight paths you know and
-- the boats. Rides go along the network - through the real crossings, never straight over a mountain or through a
-- wall - and never through a zone far above your level. Shortest trip by time (Dijkstra). The planner routes over
-- the same data with the same rules (tools/travel.js), so the plan and the arrow agree.
local _, ns = ...
local pcall = ns.PCall or pcall -- (a job never pauses under it: Core.lua)
local Travel = {}
ns.Travel = Travel
local HBD = LibStub("HereBeDragons-2.0")

-- the facts (speeds, docks, zone levels, boats, gates, the network) live in TravelData.lua, generated from
-- tools/travel-facts.json and tools/travel-net.json
local TD = ns.TravelData
Travel.RIDE, Travel.FLY, Travel.FLY_EXTRA, Travel.BOAT, Travel.FP_NEAR = TD.RIDE, TD.FLY, TD.FLY_EXTRA, TD.BOAT, TD.FP_NEAR
Travel.MOUNT = TD.MOUNT
-- how fast you ride: running, mounted from level 40 (TravelData MOUNT)
function Travel.Speed()
  local M, L = Travel.MOUNT, (UnitLevel and UnitLevel("player")) or 1
  return (M and L >= M.level) and M.speed or Travel.RIDE
end
Travel.DANGER_ABOVE, Travel.TOWN_WALK = TD.DANGER_ABOVE, TD.TOWN_WALK
-- the dangerous zone you stand in (Travel.DangerHere): a ride in it of up to DANGER_HERE_YD yards is a way out, counted
-- DANGER_HERE times its time; a longer one is kept out of as in any such zone
Travel.DANGER_HERE, Travel.DANGER_HERE_YD = 3, 400
-- a ride leg points at the first waypoint at least this far ahead (yards): nearer ones are under your feet
Travel.AHEAD_YD = 40
-- a waypoint of a ride you are already past: within PAST_YD of it and nearer the point after it than it is. A zone
-- crossing's point can sit short of where the zone really changes (Western Plaguelands / Eastern Plaguelands: on the
-- Thondroril River, ~150 yd before the road enters Eastern Plaguelands), so "the zone changed" comes too late: a
-- gnome warlock 55 rode past it on the road and the arrow turned back to it (user)
Travel.PAST_YD = 120
-- (pw: where you are, xw: the waypoint, nw: the point after it on the way; world coords { x, y, instance })
function Travel.Past(pw, xw, nw)
  if not (pw and xw and nw and pw[3] == xw[3] and nw[3] == xw[3]) then return false end
  local function dd(a, b) return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2) end
  return dd(pw, xw) <= Travel.PAST_YD and dd(pw, nw) + 5 < dd(xw, nw)
end
Travel.DOCKS, Travel.ZONE_MIN, Travel.BOATS, Travel.GATES = TD.DOCKS, TD.ZONE_MIN, TD.BOATS, TD.GATES
Travel.SPELLS = TD.SPELLS or {}
Travel.ZONE_MIN_HORDE = TD.ZONE_MIN_HORDE or {}
Travel.CROSS_CLEAR = 150 -- yards beyond a hostile town's radius where a border crossing is no way for you
Travel.NET = TD.NET
-- your faction, as the travel facts name it: crossings, spells and gates with a faction are only there for that one
function Travel.Side() return ns.State.MySide() end
local function forSide(only, side) return not only or only == side end
Travel.OFFNET = 1.25 -- straight-line yards to the network's key points count this much longer (roads bend)
-- seconds to walk (or ride) a straight line of this many yards: OFFNET longer, at your speed
function Travel.WalkSecs(yards) return yards * Travel.OFFNET / (Travel.Speed() or 7) end

local function world(m, x, y)
  local wx, wy, inst = HBD:GetWorldCoordinatesFromZone(x, y, m)
  if wx then return { wx, wy, inst } end
end
local mapName = ns.Util.MapName
local function d(a, b) return math.sqrt((a.w[1] - b.w[1]) ^ 2 + (a.w[2] - b.w[2]) ^ 2) end
-- the walk to a key point of your map beyond its straight line x OFFNET, from the cell of the map you stand in
-- (Travel.NET.walkEx, tools/offnet.js: per map a G x G grid, per key point the least excess of any walkable spot in the
-- cell; only big ones kept). Across a mountain the line is far too short: in Blasted Lands by Nethergarde the crossing
-- on the ridge (x4-8-45) is 394 yd away in a line and 850 on foot (round through the Swamp of Sorrows), and the trip
-- went that way instead of up the pass (x4-8-44, 379 yd). Decoded per key point on first use.
local exNet, exMaps
local B64 = {}
do local A = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"; for i = 1, 64 do B64[A:byte(i)] = i - 1 end end
local function walkEx(m, x, y, id)
  local X = Travel.NET and Travel.NET.walkEx
  if not (X and x and y) then return 0 end
  if exNet ~= Travel.NET then exNet, exMaps = Travel.NET, {} end
  local byId = exMaps[m]
  if byId == nil then byId = (X.maps and X.maps[m]) and {} or false; exMaps[m] = byId end
  if not byId then return 0 end
  local cells = byId[id]
  if cells == nil then
    local s = X.maps[m][id]
    cells = false
    if s then
      cells = {}
      local unit = X.UNIT or 32
      for i = 1, #s - 2, 3 do cells[B64[s:byte(i)] * 64 + B64[s:byte(i + 1)]] = B64[s:byte(i + 2)] * unit end
    end
    byId[id] = cells
  end
  if not cells then return 0 end
  local G = X.G or 32
  local cx, cy = math.floor(x * G), math.floor(y * G)
  if cx < 0 or cy < 0 or cx >= G or cy >= G then return 0 end
  return cells[cy * G + cx] or 0
end
-- yards to walk from p (on its own map) to key point n of that map: the straight line x OFFNET, plus the excess above
local function joinYd(p, n) return d(p, n) * Travel.OFFNET + walkEx(p.m, p.x, p.y, n.id) end
-- the other faction's towns and camps (TravelData HOSTILE, from tools/hostile-towns.json): a ride through one costs
-- HOSTILE_SEC more - guards, players, a detour. Possible (fine for PvP), just trouble.
Travel.HOSTILE, Travel.HOSTILE_SEC = TD.HOSTILE or {}, TD.HOSTILE_SEC or 0
local hostileW, hostileFor, hostileConv
function Travel.HostileTowns()
  local side = ns.State.MySide()
  -- (made again when the map conversion changes: tests swap the coordinates in)
  local conv = HBD.GetWorldCoordinatesFromZone
  if hostileFor ~= side or not hostileW or hostileConv ~= conv then
    hostileW, hostileFor, hostileConv = {}, side, conv
    for _, h in ipairs(Travel.HOSTILE[side] or {}) do local w = world(h.m, h.x, h.y); if w then hostileW[#hostileW + 1] = { w = w, r = h.r, name = h.name } end end
  end
  return hostileW
end
-- the distance from point (px, py) to the segment a-b ({ x, y }), and where on it the nearest point is (0 to 1)
function Travel.SegDist(px, py, a, b)
  local dx, dy = b[1] - a[1], b[2] - a[2]
  local L = dx * dx + dy * dy
  local t = L > 0 and math.max(0, math.min(1, ((px - a[1]) * dx + (py - a[2]) * dy) / L)) or 0
  return math.sqrt((a[1] + t * dx - px) ^ 2 + (a[2] + t * dy - py) ^ 2), t
end
local segDist = Travel.SegDist
-- the other faction's town a ride from a to b passes through (its entry: name, radius), or nil. A quick box test first:
-- this runs for every road of every trip the card, arrow and pins ask for
-- (the towns of each world apart, in their order: a trip joins you and the target to dozens of roads, each checked)
local byInstOf = setmetatable({}, { __mode = "k" })
local function hostileIn(list, inst)
  local by = byInstOf[list]
  if not by then
    by = {}
    for _, h in ipairs(list) do local i = h.w[3]; local l = by[i]; if not l then l = {}; by[i] = l end; l[#l + 1] = h end
    byInstOf[list] = by
  end
  return by[inst] or {}
end
function Travel.Through(a, b)
  local x0, x1 = math.min(a[1], b[1]), math.max(a[1], b[1])
  local y0, y1 = math.min(a[2], b[2]), math.max(a[2], b[2])
  for _, h in ipairs(hostileIn(Travel.HostileTowns(), a[3])) do
    local p, r = h.w, h.r
    if p[3] == a[3] and p[1] + r >= x0 and p[1] - r <= x1 and p[2] + r >= y0 and p[2] - r <= y1 and segDist(p[1], p[2], a, b) < r then return h end
  end
  return nil
end
-- roads of the network never move: whether one passes a hostile town is worked out once per road (and faction)
local roadHostile, roadFor, roadConv = {}, nil, nil
local function throughCached(u, v)
  local side = hostileFor
  -- (and the map positions they were worked out with: tests swap them in - see Travel.HostileTowns)
  if roadFor ~= side or roadConv ~= HBD.GetWorldCoordinatesFromZone then roadHostile, roadFor, roadConv = {}, side, HBD.GetWorldCoordinatesFromZone end
  if not (u.id and v.id) or u.id == "you" or u.id == "target" or v.id == "you" or v.id == "target" then return Travel.Through(u.w, v.w) end
  -- (by the two ids, the lower first - no key string per road: ~9,000 roads, perf)
  local a, b = u.id, v.id
  if b < a then a, b = b, a end
  local row = roadHostile[a]
  if not row then row = {}; roadHostile[a] = row end
  local c = row[b]
  if c == nil then c = Travel.Through(u.w, v.w) or false; row[b] = c end
  return c or nil
end

-- the network's nodes with world coords, once (the map data doesn't change)
local netNodes, netById, netMaps, netInst, netSrc, netConv
local function net()
  -- rebuilt only if the data or the map conversion changes (tests swap both)
  if netNodes and netSrc == Travel.NET and netConv == HBD.GetWorldCoordinatesFromZone then return netNodes end
  netSrc, netConv = Travel.NET, HBD.GetWorldCoordinatesFromZone
  netNodes, netById, netMaps, netInst = {}, {}, {}, {}
  for _, n in ipairs((Travel.NET and Travel.NET.nodes) or {}) do
    local w = world(n.m, n.x, n.y)
    if w then
      local c = { id = n.id, kind = n.kind, m = n.m, x = n.x, y = n.y, name = n.name, dock = n.dock, m2 = n.m2, x2 = n.x2, y2 = n.y2, side = n.side, w = w }
      local D = n.dock and Travel.DOCKS[n.dock]
      if D then c.town, c.zone, c.pier, c.name, c.say = D.town, D.zone, D.pier, D.name, D.say end
      netNodes[#netNodes + 1] = c; netById[n.id] = c; netInst[w[3]] = true
      netMaps[n.m] = true; if n.m2 then netMaps[n.m2] = true end
    end
  end
  return netNodes
end
-- where a trip can leave the walk on map m: your side's flight masters (known or not) and the piers - the places a
-- trip between two far stops starts or lands at (Next indexes the plan's far gaps by the walks to them before it
-- knows which one the trip takes) -> { world positions }
-- a flight master of your side (ns.FLIGHT, your faction's list): the network's nodes carry no faction, and where both
-- sides have one under the same name (Booty Bay) the name alone doesn't tell them apart
local function ourFP(m, npc)
  local list = ns.FLIGHT and ns.FLIGHT[m]
  if not list then return false end
  for _, f in ipairs(list) do if f[3] == npc then return true end end
  return false
end
local portsOf, portsKey = {}, nil
function Travel.Ports(m)
  net()
  local letter = ns.State.MyFaction() or "A"
  local key = tostring(netNodes) .. letter .. tostring(ns.FLIGHT)
  if portsKey ~= key then portsOf, portsKey = {}, key end
  local out = portsOf[m]
  if out then return out end
  out = {}
  for _, n in ipairs(netNodes or {}) do
    if (n.m == m or n.m2 == m) and ((n.kind == "fp" and (not n.side or n.side:find(letter, 1, true)) and ourFP(n.m, n.name)) or n.kind == "dock") then out[#out + 1] = n.w end
  end
  if #out == 0 then
    -- (no network here: the flight masters of your side alone)
    for _, f in ipairs((ns.FLIGHT and ns.FLIGHT[m]) or {}) do local w = world(m, f[1], f[2]); if w then out[#out + 1] = w end end
  end
  portsOf[m] = out
  return out
end
-- can a trip start here? Not from a place the network has no stop in: the Deeprun Tram is its own little world
-- (between the Ironforge and Stormwind stops), and so is a dungeon
-- (a map the network names is always on it; any other map is on it only if it lies in a world the network has stops in)
local rawMaps
function Travel.OnNetwork(m, x, y)
  if not Travel.NET or not m then return true end -- no network: plain straight lines from anywhere
  if not rawMaps or rawMaps.src ~= Travel.NET then
    rawMaps = { src = Travel.NET }
    for _, n in ipairs(Travel.NET.nodes or {}) do rawMaps[n.m] = true; if n.m2 then rawMaps[n.m2] = true end end
  end
  if rawMaps[m] then return true end
  net()
  local w = world(m, x, y)
  return w ~= nil and netInst[w[3]] == true
end
function Travel.IsTram(leg) return leg ~= nil and type(leg.dock) == "string" and leg.dock:find("^tram") ~= nil end

-- do you have this flight point? FlightMasters.lua names each flight master's point as the flight map does
-- ("Sentinel Hill, Westfall": the client's TaxiNodes table), so a zone with two points for your faction doesn't count
-- both as yours when you have one. Having the point by that name: yes. Not having it while your list is in the flight
-- map's names (one of them is ours: an English client): no - the list is the flight master's map, and only a point on
-- it is a place a trip may fly to. Otherwise (no name, a client in another language) the zone's name decides.
-- (3.3.0: a gnome 55 with 32 flight paths, none in Mount Hyjal, was sent to fly to Tainted Foothills - the zone's
-- name decided, and read "Mount Hyjal" in "Stonetalon Mountains")
local taxiOf, taxiSrc, taxiAll
local function taxiNames()
  if taxiOf and taxiSrc == ns.FLIGHT_BY then return taxiOf end
  taxiOf, taxiSrc, taxiAll = {}, ns.FLIGHT_BY, {}
  for _, byMap in pairs(ns.FLIGHT_BY or {}) do
    for m, list in pairs(byMap) do
      for _, f in ipairs(list) do if f[4] then taxiOf[m .. ":" .. tostring(f[3])] = f[4]; taxiAll[f[4]] = true end end
    end
  end
  return taxiOf
end
-- is your known list in our names? (kept per list and its size: flight paths are only ever gained, so a yes stays one)
local namedFor, namedN, namedV
local function listInOurNames(known)
  if namedV and namedFor == known and taxiSrc == ns.FLIGHT_BY then return true end
  local n = 0; for _ in pairs(known) do n = n + 1 end
  if namedFor == known and namedN == n and taxiSrc == ns.FLIGHT_BY then return namedV end
  taxiNames()
  local v = false
  for name in pairs(known) do if taxiAll[name] then v = true; break end end
  namedFor, namedN, namedV = known, n, v
  return v
end
local function knowsFP(m, npc)
  local known = (ns.State and ns.State.knownTaxi) or {}
  -- the other faction's flight master is never yours, even where both sides' share a point name (Booty Bay)
  if npc and not ourFP(m, npc) then return false end
  local mine = npc and taxiNames()[m .. ":" .. npc]
  if mine then
    if known[mine] then return true end
    if listInOurNames(known) then return false end
  end
  return ns.Engine and ns.Engine.KnowsFlightIn and ns.Engine.KnowsFlightIn(mapName(m))
end
Travel.KnowsFlightPoint = knowsFP

-- the hearthstone: casting takes 10 s; the hour of cooldown it uses is worth about 3 minutes of travel
Travel.HEARTH_CAST, Travel.HEARTH_VALUE = 10, 180
-- where your hearthstone takes you, if it is in your bags and ready: the innkeeper of the map you bound on (or the map
-- named like your bind location). nil when unknown - never guess a hearth
-- (the innkeeper found for a bind is kept until the bind, boundAt, the vendor data or the map names change)
local innMemo = {}
local function findInn(bind, b)
  local maps = {}
  if b and b.m and b.name == bind then maps[#maps + 1] = b.m end
  for m in pairs(ns.VENDORS or {}) do
    local n = mapName(m)
    if n == bind or bind:find(n, 1, true) or n:find(bind, 1, true) then maps[#maps + 1] = m end
  end
  for _, m in ipairs(maps) do
    for _, v in ipairs(ns.VENDORS[m] or {}) do
      if v[4] == "Innkeeper" then return { m = m, x = v[1], y = v[2], name = v[3] } end
    end
  end
  return false
end
local function hearthInn()
  if not GetBindLocation then return nil end
  local count = GetItemCount and GetItemCount(6948)
  if not (type(count) == "number" and count > 0) then return nil end
  if not (ns.HearthCooldown and ns.HearthCooldown() == 0) then return nil end
  local bind = GetBindLocation()
  if type(bind) ~= "string" or bind == "" then return nil end
  local b = ns.char and ns.char.boundAt
  local bm, bn, M = b and b.m, b and b.name, innMemo
  local fn = C_Map and C_Map.GetMapInfo
  if not (M.bind == bind and M.bm == bm and M.bn == bn and M.vendors == ns.VENDORS and M.fn == fn) then
    innMemo = { bind = bind, bm = bm, bn = bn, vendors = ns.VENDORS, fn = fn, inn = findInn(bind, b) }
    M = innMemo
  end
  local inn = M.inn
  return inn and { m = inn.m, x = inn.x, y = inn.y, name = inn.name, bind = bind } or nil
end
function Travel.HearthInn()
  local ok, inn = pcall(hearthInn)
  return ok and inn or nil
end

-- The graph a trip is searched on, without you and the target: the network's places, its roads, the gates, the
-- flights between the flight paths you know and the boats. Building it is most of a trip's ~35 ms, and the card asks
-- for trips many times a minute (perf), so it is kept until an input changes: known flight paths, level, speed,
-- faction, race, class, learned piers, or the data (tests swap all of these). You and the target are joined on each
-- trip; those roads are kept apart from the graph's own (ext), so the kept graph is never changed by a trip.
-- (kept graphs: { ground, lvl, side, race, class, speed, here, G }, all of the same envGen. What the graphs are made of
-- besides those is compared with the last call's values in place - no key strings: Travel.Plan asks this on every trip)
local graphs, graphCount = {}, 0
local envGen, envLast, envN = 0, {}, 0
local taxiSeen, taxiSeenN = {}, 0
local docksSeen, docksSeenN = {}, 0
-- the flight paths you know and the piers you learned, by content: true when they differ from the last seen (and
-- remembered then)
local function taxiMoved(T)
  local n = 0
  for k, v in pairs(T) do if taxiSeen[k] ~= v then n = -1; break end; n = n + 1 end
  if n == taxiSeenN then return false end
  taxiSeen, taxiSeenN = {}, 0
  for k, v in pairs(T) do taxiSeen[k] = v; taxiSeenN = taxiSeenN + 1 end
  return true
end
local function dockSame(was, L)
  if type(L) == "table" then return type(was) == "table" and was.m == L.m and was.x == L.x and was.y == L.y end
  return was == L
end
local function docksMoved(learned)
  local n = 0
  for k, L in pairs(learned) do if not dockSame(docksSeen[k], L) then n = -1; break end; n = n + 1 end
  if n == docksSeenN then return false end
  docksSeen, docksSeenN = {}, 0
  for k, L in pairs(learned) do docksSeen[k] = type(L) == "table" and { m = L.m, x = L.x, y = L.y } or L; docksSeenN = docksSeenN + 1 end
  return true
end
local function envSet(v)
  envN = envN + 1
  if envLast[envN] ~= v then envLast[envN] = v; return true end
  return false
end
-- -> the generation of everything a graph is made of but the per-call values (bumped when any of it changed)
local function envNow(nodes, learned)
  envN = 0
  local c = taxiMoved((ns.State and ns.State.knownTaxi) or {})
  c = docksMoved(learned) or c
  c = envSet(nodes) or c; c = envSet(Travel.NET) or c; c = envSet(ns.FLIGHT) or c; c = envSet(ns.FLIGHT_BY) or c
  c = envSet(C_Map and C_Map.GetMapInfo) or c; c = envSet(ns.Engine and ns.Engine.KnowsFlightIn) or c; c = envSet(HBD.GetWorldCoordinatesFromZone) or c
  c = envSet(Travel.DOCKS) or c; c = envSet(Travel.GATES) or c; c = envSet(Travel.BOATS) or c; c = envSet(Travel.ZONE_MIN) or c
  c = envSet(Travel.ZONE_MIN_HORDE) or c; c = envSet(Travel.HOSTILE) or c
  c = envSet(Travel.DANGER_ABOVE) or c; c = envSet(Travel.TOWN_WALK) or c; c = envSet(Travel.OFFNET) or c; c = envSet(Travel.FLY) or c
  c = envSet(Travel.FLY_EXTRA) or c; c = envSet(Travel.BOAT) or c; c = envSet(TD.TRANSFER) or c; c = envSet(Travel.HOSTILE_SEC) or c
  c = envSet(Travel.CROSS_CLEAR) or c
  if c then envGen = envGen + 1 end
  return envGen
end
-- what knowsFP says of each flight master: asked again for every leg of every trip, and it only changes with things the
-- graph's own inputs hold (whichever kind of trip asks: all of them but ground)
local fpKnown, fpAt = {}, {}
local NILK = {}
local function fpSync(lvl, side, myRace, myClass, speed, here, gen)
  local a = fpAt
  if a[1] == lvl and a[2] == side and a[3] == myRace and a[4] == myClass and a[5] == speed and a[6] == here and a[7] == gen then return end
  fpKnown, fpAt = {}, { lvl, side, myRace, myClass, speed, here, gen }
end
local function knowsFPKept(m, npc)
  local mk = m == nil and NILK or m
  local row = fpKnown[mk]
  if not row then row = {}; fpKnown[mk] = row end
  local k = npc == nil and NILK or npc
  local v = row[k]
  if v == nil then v = knowsFP(m, npc) and true or false; row[k] = v end
  return v
end
-- a Horde player's own lands are not the 60 that keeps the Alliance out (ZONE_MIN_HORDE)
-- (the zone you stand in gets a short way out: Travel.DANGER_HERE_YD)
local function riskyFor(side, lvl)
  return function(m)
    local z = Travel.ZONE_MIN[m]
    if side == "horde" and Travel.ZONE_MIN_HORDE[m] ~= nil then z = Travel.ZONE_MIN_HORDE[m] end
    return z and z > lvl + Travel.DANGER_ABOVE
  end
end
-- the zone of a trip's start when it is one the danger rule would keep you out of (nil otherwise: the usual graph)
function Travel.DangerHere(m, side, lvl)
  return (m and riskyFor(side, lvl)(m)) and m or nil
end
local function gatesFor(side)
  local gates = {}
  for _, g in ipairs(Travel.GATES) do if forSide(g.faction, side) then gates[#gates + 1] = g end end
  return gates
end
local function gatedBy(gates)
  return function(a, b)
    if a.gate or b.gate then return false end
    for _, g in ipairs(gates) do if (a.m == g.a and b.m == g.b) or (a.m == g.b and b.m == g.a) then return true end end
    return false
  end
end
-- a crossing limited to some races (5th entry: the Skyborne-only portal) is not there for anyone else
-- (or classes: the druids' hippogryph out of Moonglade)
local function myRaceClass()
  local myRace = ns.StarterKey and ns.StarterKey()
  local myClass = myRace and myRace:match("%-(.+)$")
  myRace = myRace and myRace:match("^(.-)%-")
  if not myClass then local c = ns.State.MyClass(); myClass = c and c:lower() end
  return myRace, myClass
end
local campMemo = setmetatable({}, { __mode = "k" })
local function buildGraph(ground, lvl, side, myRace, myClass, learned, here)
  local risky, gates = riskyFor(side, lvl), gatesFor(side)
  local gated = gatedBy(gates)
  local myLetter = side == "horde" and "H" or "A"
  local N = { false, false } -- (you and the target: each trip's own)
  local adj = { {}, {} }
  local idx = {}
  local function add(n) N[#N + 1] = n; adj[#N] = {}; return #N end
  local function edge(u, v, c, how)
    -- (the towns are looked up once for the whole build, below: not for each of 9,000 roads)
    -- (e[5]: the hostile town's toll in c - a cost of the route's choice, not seconds: Travel.Plan's 5th result)
    local pen
    if how == "ride" and N[u].w and N[v].w and throughCached(N[u], N[v]) then c = c + Travel.HOSTILE_SEC; pen = Travel.HOSTILE_SEC end
    local au, av = adj[u], adj[v]; au[#au + 1] = { v, c, how, nil, pen }; av[#av + 1] = { u, c, how, nil, pen }
  end
  local hostile = Travel.HostileTowns()
  -- (whether a crossing is in a camp only changes with your faction's list of camps: memoized across graph rebuilds, perf)
  local camps = campMemo[hostile]
  if not camps or camps.clear ~= Travel.CROSS_CLEAR then camps = { clear = Travel.CROSS_CLEAR, of = setmetatable({}, { __mode = "k" }) }; campMemo[hostile] = camps end
  local function inCamp(n)
    local v = camps.of[n]
    if v ~= nil then return v end
    v = false
    for _, h in ipairs(hostile) do
      if n.w and h.w[3] == n.w[3] and math.sqrt((h.w[1] - n.w[1]) ^ 2 + (h.w[2] - n.w[2]) ^ 2) < h.r + Travel.CROSS_CLEAR then v = true; break end
    end
    camps.of[n] = v
    return v
  end
  -- ... when its border has a crossing clear of every camp (both Blasted Lands / Swamp of Sorrows crossings are by the
  -- Nethergarde miners' camps: without them a Horde player there had no way out). Once per list of camps and network
  local function border(n) if n.m < (n.m2 or 0) then return n.m .. "/" .. n.m2 end return (n.m2 or 0) .. "/" .. n.m end
  local nodes = net()
  if camps.borderNet ~= nodes then
    local cb = {}
    -- (a crossing whose walk from its zone's town goes by another one and through the other zone - NET.walkEx.via,
    -- tools/offnet.js - is no way clear of that one's camp: Blasted Lands' ridge crossing into the Swamp of Sorrows is
    -- reached up the pass by Stonard, and an Alliance player by Nethergarde was sent over the ridge to it)
    local V = Travel.NET and Travel.NET.walkEx and Travel.NET.walkEx.via
    local function byAnother(n) return V and ((V[n.m] and V[n.m][n.id]) or (n.m2 and V[n.m2] and V[n.m2][n.id])) end
    for _, n in ipairs(nodes) do if n.kind == "cross" and not inCamp(n) and not byAnother(n) then cb[border(n)] = true end end
    for _, g in ipairs(gates) do cb[border({ m = g.a, m2 = g.b })] = true end -- (a gate of your side: the breach past Mor'shan Rampart)
    camps.clearBorder, camps.borderNet = cb, nodes
  end
  local clearBorder = camps.clearBorder
  -- (built inside the solve's slices too, so it yields (perf: up to ~55 ms); all it makes is its own until it returns)
  local tick = 0
  local function pause() tick = tick + 1; if tick % 64 == 0 then ns.MaybeYield() end end
  for _, n in ipairs(net()) do
    pause()
    local c = n
    if n.dock then
      -- a pier you learned moves the dock (its walking yards stay)
      local D = Travel.DOCKS[n.dock]; local L = D and learned[D.learned or n.dock]
      if L and L.m == n.m and L.x then
        local w = world(n.m, L.x, L.y)
        if w then c = setmetatable({ x = L.x, y = L.y, w = w }, { __index = n }) end
      end
    end
    -- a flight master of the other faction is only a spot on the road for you
    if n.kind == "fp" and not ground and (not n.side or n.side:find(myLetter, 1, true)) and knowsFPKept(n.m, n.name) then c = setmetatable({ fp = true }, { __index = c }) end
    -- a border crossing inside the other faction's town or camp is no way for you: a crossing
    -- is a chokepoint, and the border has another one clear of it (tools/travel.js does the same) - when it has
    if not (n.kind == "cross" and inCamp(n) and clearBorder[border(n)]) then idx[n.id] = add(c) end
  end
  for _, e in ipairs((Travel.NET and Travel.NET.edges) or {}) do
    pause()
    local u, v = idx[e[1]], idx[e[2]]
    if u and v and not (risky(e[3]) and e[4] > Travel.TOWN_WALK and not (here == e[3] and e[4] <= Travel.DANGER_HERE_YD)) then edge(u, v, e[4] / Travel.Speed() * ((here and e[3] == here) and Travel.DANGER_HERE or 1), "ride") end
  end
  if not Travel.NET then
    -- no network: flight paths you know and the docks as plain nodes, straight rides
    for m, list in pairs(ns.FLIGHT or {}) do
      local f = list[1]
      if not ground and knowsFPKept(m, f[3]) then local w = world(m, f[1], f[2]); if w then add({ id = "fp" .. m, kind = "fp", fp = true, w = w, m = m, x = f[1], y = f[2], name = f[3] }) end end
    end
    for key, D in pairs(Travel.DOCKS) do
      local L = learned[D.learned or key]
      local x, y = (L and L.m == D.m and L.x) or D.x, (L and L.m == D.m and L.y) or D.y
      local w = world(D.m, x, y)
      if w then idx["dock-" .. key] = add({ id = "dock-" .. key, kind = "dock", dock = key, w = w, m = D.m, x = x, y = y, name = D.name, town = D.town, zone = D.zone, pier = D.pier, say = D.say }) end
    end
  end
  if Travel.NET then
    -- docks the network doesn't have (a map without a walk map: Zephras Isle's skyship): plain nodes joined in straight
    -- rides to the key points of their own map, like the gates (tools/travel.js does the same)
    for key, D in pairs(Travel.DOCKS) do
      if not idx["dock-" .. key] then
        local w = world(D.m, D.x, D.y)
        if w then
          local u = add({ id = "dock-" .. key, kind = "dock", dock = key, w = w, m = D.m, x = D.x, y = D.y, name = D.name, town = D.town, zone = D.zone, pier = D.pier, say = D.say })
          idx["dock-" .. key] = u
          for v = 3, u - 1 do local n = N[v]; if n.m == D.m or n.m2 == D.m then edge(u, v, d(N[u], n) * Travel.OFFNET / Travel.Speed(), "ride") end end
        end
      end
    end
  end
  -- gates (the breach past Mor'shan Rampart): the only way across their border when riding in straight lines
  local firstGate = #N + 1
  for k, g in ipairs(gates) do
    local w = world(g.via.m, g.via.x, g.via.y)
    if w then add({ id = "gate" .. k, kind = "gate", gate = true, w = w, m = g.via.m, x = g.via.x, y = g.via.y, name = g.via.name }) end
  end
  if not Travel.NET then
    for u = 3, #N do pause(); for v = u + 1, #N do
      local a, b = N[u], N[v]
      if a.w[3] == b.w[3] and not gated(a, b) and (d(a, b) <= Travel.TOWN_WALK or not ((risky(a.m) and a.m ~= here) or (risky(b.m) and b.m ~= here)) and ((a.m ~= here and b.m ~= here) or d(a, b) <= Travel.DANGER_HERE_YD)) then edge(u, v, d(a, b) / Travel.Speed() * ((here and (a.m == here or b.m == here)) and Travel.DANGER_HERE or 1), "ride") end
    end end
  else
    -- with the network, a gate joins the key points of its own map
    for g = firstGate, #N do pause(); for v = 3, firstGate - 1 do
      local n = N[v]
      if n.m == N[g].m or n.m2 == N[g].m then edge(g, v, d(N[g], n) * Travel.OFFNET / Travel.Speed(), "ride") end
    end end
  end
  -- flights between the flight paths you know (same continent)
  local fps = {}
  for v = 3, #N do if N[v].fp then fps[#fps + 1] = v end end
  for i = 1, #fps do pause(); for j = i + 1, #fps do
    local u, v = fps[i], fps[j]
    if N[u].w[3] == N[v].w[3] then edge(u, v, Travel.FLY_EXTRA + d(N[u], N[v]) / Travel.FLY, "fly") end
  end end
  for _, bt in ipairs(Travel.BOATS) do
    local u, v = idx["dock-" .. bt[1]], idx["dock-" .. bt[2]]
    local allowed = not bt[5]
    if bt[5] then for _, r in ipairs(bt[5]) do if r == myRace or r == myClass then allowed = true end end end
    -- (6th entry: a faction's own crossings - the zeppelins, the Stormwind boat)
    if not forSide(bt[6], side) then allowed = false end
    if u and v and allowed and not ground then
      -- the kind rides along (a portal reads "take the portal"); a 7th entry true: one way (no portal back)
      -- (plus a change of transport: a near tie goes to the trip with fewer legs)
      local c = (bt[3] or Travel.BOAT) + (TD.TRANSFER or 0)
      if bt[7] then adj[u][#adj[u] + 1] = { v, c, "boat", bt[4] }
      else edge(u, v, c, "boat"); adj[u][#adj[u]][4] = bt[4]; adj[v][#adj[v]][4] = bt[4] end
    end
  end
  return { N = N, adj = adj, idx = idx, risky = risky, gated = gated, here = here }
end
local function graphFor(ground, lvl, side, myRace, myClass, here)
  local learned = (BeelineDB and BeelineDB.docks) or {}
  local gen = envNow(net(), learned)
  local speed = Travel.Speed()
  fpSync(lvl, side, myRace, myClass, speed, here, gen)
  local g = ground and true or false
  for i = 1, graphCount do
    local e = graphs[i]
    if e[9] == gen and e[1] == g and e[2] == lvl and e[3] == side and e[4] == myRace and e[5] == myClass and e[6] == speed and e[7] == here then return e[8] end
  end
  -- (a few kept: the card's shortcut check asks with and without flights in turn)
  if graphCount >= 4 then graphs, graphCount = {}, 0 end
  local G = buildGraph(ground, lvl, side, myRace, myClass, learned, here)
  graphCount = graphCount + 1
  graphs[graphCount] = { g, lvl, side, myRace, myClass, speed, here, G, gen }
  return G
end

local flightW, flightWConv = {}, nil
local function flightWorld(m, f)
  local w = flightW[f]
  if w == nil then w = world(m, f[1], f[2]) or false; flightW[f] = w end
  return w or nil
end

-- from = { m, x, y }, to = { m, x, y, name } -> legs { { how = "ride"|"fly"|"boat", m, x, y (where to go), text } }, seconds
-- opts.ground: on foot only (no flights, boats, spells or hearthstone) - what the same trip takes without them
-- opts.hearth = false: without your hearthstone
-- (G: the graph Travel.Plan already looked up for the same call)
local function planTrip(from, to, opts, G)
  local ground = opts and opts.ground
  from.w = from.w or world(from.m, from.x, from.y); to.w = to.w or world(to.m, to.x, to.y)
  if not (from.w and to.w) then return nil end
  local lvl = UnitLevel and UnitLevel("player") or 60
  local side = Travel.Side()
  local myRace, myClass = myRaceClass()
  G = G or graphFor(ground, lvl, side, myRace, myClass, Travel.DangerHere(from.m, side, lvl))
  local risky, gated, idx = G.risky, G.gated, G.idx
  -- this trip's nodes: you, the target, the kept graph's, and your inn; the roads that join them are this trip's own
  -- (ext), searched along with the graph's
  local N = { { id = "you", w = from.w, m = from.m, x = from.x, y = from.y, name = "you" }, { id = "target", w = to.w, m = to.m, x = to.x, y = to.y, name = to.name or "there" } }
  local GN, Gadj = G.N, G.adj
  for v = 3, #GN do N[v] = GN[v] end
  local ext = {}
  local function push(u, e) local l = ext[u]; if not l then l = {}; ext[u] = l end; l[#l + 1] = e end
  local function edge(u, v, c, how)
    local pen
    if how == "ride" and N[u].w and N[v].w then Travel.HostileTowns(); if throughCached(N[u], N[v]) then c = c + Travel.HOSTILE_SEC; pen = Travel.HOSTILE_SEC end end
    push(u, { v, c, how, nil, pen }); push(v, { u, c, how, nil, pen })
  end
  -- you and the target join the network at the key points of their own map (anywhere on the continent if the map
  -- has none - a dungeon map, a map the walk maps don't cover)
  net()
  for e = 1, 2 do
    local p = N[e]; local onNet = netMaps[p.m]
    for v = 3, #N do
      if v % 32 == 0 then ns.MaybeYield() end
      local n = N[v]
      if n.w[3] == p.w[3] then
        local ok
        if onNet then ok = n.m == p.m or n.m2 == p.m else ok = not gated(p, n) end
        -- the danger rule holds where you join and leave the network too (a town walk is fine anywhere)
        local H = G.here
        if ok and d(p, n) > Travel.TOWN_WALK and ((risky(n.m) and n.m ~= H) or (risky(p.m) and p.m ~= H) or ((n.m == H or p.m == H) and d(p, n) > Travel.DANGER_HERE_YD)) then ok = false end
        if ok then edge(e, v, joinYd(p, n) / Travel.Speed() * ((G.here and (n.m == G.here or p.m == G.here)) and Travel.DANGER_HERE or 1), "ride") end
      end
    end
  end
  local a, b = N[1], N[2]
  if a.w[3] == b.w[3] and (a.m == b.m or not netMaps[a.m] or not netMaps[b.m]) and not gated(a, b) and (a.m == b.m or not (risky(a.m) or risky(b.m))) then
    edge(1, 2, d(a, b) * Travel.OFFNET / Travel.Speed(), "ride")
  end
  -- a class spell that takes you somewhere from anywhere (Teleport: Moonglade): one way, from where you stand
  local myLevel = (UnitLevel and UnitLevel("player")) or 1
  for _, sp in ipairs(Travel.SPELLS) do
    local v = idx["dock-" .. sp.dock]
    if v and not ground and sp.class == myClass and myLevel >= (sp.level or 1) and forSide(sp.faction, side) and N[v].m ~= from.m then push(1, { v, sp.cast or 10, "spell" }); N[v].spellSay = sp.say end
  end
  -- your hearthstone, when it is ready: from wherever you are to your inn. It costs an hour's cooldown, so it only
  -- wins when it saves a few minutes (HEARTH_VALUE)
  local inn = not ground and not (opts and opts.hearth == false) and Travel.HearthInn()
  if inn then
    local w = world(inn.m, inn.x, inn.y)
    if w then
      N[#N + 1] = { id = "inn", kind = "inn", w = w, m = inn.m, x = inn.x, y = inn.y, name = inn.name, town = inn.bind }
      local h = #N
      push(1, { h, Travel.HEARTH_CAST + Travel.HEARTH_VALUE, "hearth" }) -- one way: you can't hearth back
      for v = 3, #N - 1 do
        if v % 32 == 0 then ns.MaybeYield() end
        local n = N[v]
        if n.w[3] == w[3] and (n.m == inn.m or n.m2 == inn.m) then edge(h, v, joinYd(N[h], n) / Travel.Speed(), "ride") end
      end
      if N[2].w[3] == w[3] and N[2].m == inn.m then edge(h, 2, d(N[h], N[2]) * Travel.OFFNET / Travel.Speed(), "ride") end
    end
  end
  -- Dijkstra, on the time you spend playing: a flight or a boat is time you can look away, so its seconds count at
  -- Travel.AFK_WEIGHT. secs: the real time, for the plan's clock; afk: the seconds of it on a flight or boat
  -- (heap ordered by distance, then node number: ties break as a plain linear scan would, deterministically)
  local dist, prev, how, done, kindOf, secs, afk, toll = {}, {}, {}, {}, {}, {}, {}, {}
  for i = 1, #N do dist[i] = math.huge end
  dist[1], secs[1], afk[1], toll[1] = 0, 0, 0, 0
  local hd, hi, hn = {}, {}, 0
  local function less(p, q) return hd[p] < hd[q] or (hd[p] == hd[q] and hi[p] < hi[q]) end
  local function hpush(dv, iv)
    hn = hn + 1; local k = hn; hd[k], hi[k] = dv, iv
    while k > 1 do
      local p = math.floor(k / 2)
      if less(k, p) then hd[k], hd[p], hi[k], hi[p] = hd[p], hd[k], hi[p], hi[k]; k = p else break end
    end
  end
  local function hpop()
    local dv, iv = hd[1], hi[1]
    hd[1], hi[1] = hd[hn], hi[hn]; hd[hn], hi[hn] = nil, nil; hn = hn - 1
    local k = 1
    while true do
      local l, r, m = 2 * k, 2 * k + 1, k
      if l <= hn and less(l, m) then m = l end
      if r <= hn and less(r, m) then m = r end
      if m == k then break end
      hd[k], hd[m], hi[k], hi[m] = hd[m], hd[k], hi[m], hi[k]; k = m
    end
    return dv, iv
  end
  hpush(0, 1)
  local AFK = Travel.AFK_WEIGHT
  local pops = 0
  while hn > 0 do
    local du, u = hpop()
    pops = pops + 1; if pops % 32 == 0 then ns.MaybeYield() end -- (a solve spread over frames may pause here: Next.PickAsync)
    if not done[u] and du == dist[u] then
      if u == 2 then break end
      done[u] = true
      for pass = 1, 2 do
        local list
        if pass == 1 then list = Gadj[u] else list = ext[u] end
        if list then
          for _, e in ipairs(list) do
            local v, c = e[1], e[2]
            local away = (e[3] == "fly" or e[3] == "boat") and c or 0
            local cost = c - away + away * AFK
            if not done[v] and dist[u] + cost < dist[v] then
              dist[v], prev[v], how[v], kindOf[v], secs[v], afk[v], toll[v] = dist[u] + cost, u, e[3], e[4], secs[u] + c, afk[u] + away, toll[u] + (e[5] or 0)
              hpush(dist[v], v)
            end
          end
        end
      end
    end
  end
  if dist[2] == math.huge then return nil end
  -- walk back from the target: the hops in order; consecutive rides are one ride (through the crossings)
  local chain = {}
  local v = 2
  while v and v ~= 1 do table.insert(chain, 1, { node = N[v], how = how[v], kind = kindOf[v], from = N[prev[v]] }); v = prev[v] end
  local hops = {}
  for _, c in ipairs(chain) do
    local last = hops[#hops]
    if last and last.how == "ride" and c.how == "ride" then last.via[#last.via + 1] = c.from; last.node = c.node
    else hops[#hops + 1] = { node = c.node, from = c.from, how = c.how, kind = c.kind, via = {} } end
  end
  -- what you do, leg by leg; "ride to the flight master, fly to X" reads as one "Fly to X" leg
  local function placeName(n) return n.id == "target" and (to.name or mapName(n.m)) or (n.kind == "cross" and ((("the " .. n.name:gsub(" / ", " - ") .. " border"):gsub("^the The ", "the ")))) or n.town or n.name or mapName(n.m) end
  local legs = {}
  for k, c in ipairs(hops) do
    ns.MaybeYield()
    local n, f = c.node, c.from
    if c.how == "ride" then
      local nxt = hops[k + 1]
      -- a short walk to the flight master or pier reads as part of the next leg; a real ride (across a border, or
      -- more than a town walk) is its own leg, so the trip never skips twenty minutes of riding
      local short = #c.via == 0 and d(f, n) <= 2 * Travel.TOWN_WALK
      if not (nxt and (nxt.how == "fly" or nxt.how == "boat") and short) then
        -- point at the first crossing on the way: the arrow follows the road, not a line over the hills
        -- - the first one beyond Travel.AHEAD_YD (a nearer one points at your feet)
        local first
        -- (preferably a border crossing or a gate, not a flight master or pier the road passes: that reads as "fly")
        -- (and not one you are already past: Travel.Past, toward the point after it)
        local function after(j) local y = c.via[j + 1] or n; return y.w end
        local function ahead(j, x) return x.w and f.w and d(f, x) > Travel.AHEAD_YD and not Travel.Past(f.w, x.w, after(j)) end
        local fi
        for j, x in ipairs(c.via) do if (x.kind == "cross" or x.gate) and ahead(j, x) then first, fi = x, j; break end end
        if not first then for j, x in ipairs(c.via) do if ahead(j, x) then first, fi = x, j; break end end end
        -- the zones the ride passes through (a border crossing joins two: the ones neither where you start nor where you
        -- go), and a gate by its name - not every border spelled out
        local via, seenZ = {}, {}
        -- (never the place you go to, even when the road dips into it and out again)
        seenZ[placeName(n) or ""] = true; seenZ[to.name or ""] = true; seenZ[mapName(n.m)] = true; if to.m then seenZ[mapName(to.m)] = true end
        -- (a zone you ride through is the one two crossings in a row share: "A / B" then "B / C" pass B)
        local prevSides
        for _, x in ipairs(c.via) do
          if x.gate then
            local g = x.name or placeName(x)
            if g and not seenZ[g] then seenZ[g] = true; via[#via + 1] = g end
          elseif x.kind == "cross" and x.name then
            local sides = {}
            for z in (x.name .. " / "):gmatch("(.-) / ") do if z ~= "" then sides[z] = true end end
            if prevSides then for z in pairs(sides) do if prevSides[z] and not seenZ[z] then seenZ[z] = true; via[#via + 1] = z end end end
            prevSides = sides
          end
        end
        -- the last leg inside the place you go to names who you go to (to.stop: the step's NPC), "Walk" for a town walk
        local inDest = n.id == "target" and to.stop and f.m == to.m
        local text
        -- (to a flight master: the flight path's name, as the flight map has it; the NPC goes under it: leg.npc)
        local fm = not inDest and nxt and nxt.how == "fly" and n.name and taxiNames()[n.m .. ":" .. n.name] or nil
        local npc = fm and n.name or nil
        if inDest then text = ((#c.via == 0 and d(f, n) <= Travel.TOWN_WALK) and "Walk" or ns.RideWord()) .. " to " .. to.stop .. (#via > 0 and (" via " .. table.concat(via, ", ")) or "")
        else local where = (fm and (fm:match("^([^,]+)") or fm)) or placeName(n); text = ns.RideWord() .. " " .. ((f.town and f.town ~= where and f.town ~= placeName(n)) and ("from " .. f.town .. " ") or "") .. "to " .. where .. (#via > 0 and (" via " .. table.concat(via, ", ")) or "") end
        local tgt = first or n
        local tm, tx, ty = tgt.m, tgt.x, tgt.y
        if first and first.m2 == f.m then tm, tx, ty = first.m2, first.x2, first.y2 end
        -- a town of the other faction on the way: still the way (a quest, a class trainer, the sleeping bag chain may
        -- lead there), said on the card so it's no surprise
        local passes, seen = {}, {}
        local pts = { f }; for _, x in ipairs(c.via) do pts[#pts + 1] = x end; pts[#pts + 1] = n
        for j = 1, #pts - 1 do
          ns.MaybeYield()
          local a, b = pts[j].w, pts[j + 1].w
          local h = a and b and Travel.Through(a, b)
          if h and not seen[h] then seen[h] = true; passes[#passes + 1] = h.name or "a town of the other faction" end
        end
        local say, warn = text, nil
        if #passes > 0 then warn = "passes " .. table.concat(passes, ", ") .. " (the other faction: guards will attack)"; text = text .. " - " .. warn end
        -- (em, ex, ey: where the ride ends - the arrow carries on there once past the crossing it points at)
        -- (nw: the point after that crossing on the way, in world coords - past the crossing toward it, it is passed: Arrow)
        legs[#legs + 1] = { sm = f.m, sx = f.x, sy = f.y, how = "ride", m = tm, x = tx, y = ty, em = n.m, ex = n.x, ey = n.y, nw = first and after(fi) or nil, text = text, say = say, warn = warn, hostile = #passes > 0 or nil, toId = n.id, npc = npc, zone = fm and fm:match(", (.+)$") or nil }
      end
    elseif c.how == "hearth" then
      -- nothing to point at: use the hearthstone (sm/sx/sy: where you land, for the flight-path note)
      legs[#legs + 1] = { sm = n.m, sx = n.x, sy = n.y, how = "hearth", text = "Hearth to " .. (n.town or n.name) .. " (your hearthstone is ready)", say = "Hearth to " .. (n.town or n.name) }
    elseif c.how == "spell" then
      -- nothing to point at either: cast it (Teleport: Moonglade)
      local t = (n.spellSay or "Cast your teleport") .. " (to " .. (n.zone or mapName(n.m)) .. ")"
      legs[#legs + 1] = { sm = n.m, sx = n.x, sy = n.y, how = "spell", text = t, say = t }
    elseif c.how == "fly" then
      -- who you fly from, unless the leg before is the ride to them (else it reads as if they stood at the destination)
      local prevLeg = legs[#legs]
      local named = f.name and not (prevLeg and prevLeg.how == "ride" and prevLeg.toId == f.id)
      -- (where you land: the flight path's own town as the flight map lists it, not the zone (a zone may have two);
      -- the zone only when the flight path has no name we know)
      local toTaxi = n.name and taxiNames()[n.m .. ":" .. n.name] or nil
      local dest = mapName(n.m)
      if toTaxi then dest = toTaxi:match("^([^,]+)") or toTaxi end
      local toZone = toTaxi and toTaxi:match(", (.+)$") or nil
      local fromTaxi = f.name and taxiNames()[f.m .. ":" .. f.name] or nil
      local fromTown = fromTaxi and (fromTaxi:match("^([^,]+)") or fromTaxi) or f.name
      legs[#legs + 1] = { sm = f.m, sx = f.x, sy = f.y, how = "fly", m = f.m, x = f.x, y = f.y, toTaxi = toTaxi, npc = named and fromTaxi and f.name or nil,
        zone = toZone, from = named and fromTown or nil,
        text = named and ("Fly from " .. fromTown .. " to " .. dest) or ("Fly to " .. dest) }
      -- (the card's headline: the town you land in; under it, small, its zone and who you fly from)
      legs[#legs].say = "Fly to " .. dest
    elseif c.how == "boat" then
      -- what you actually do: which town and zone you sail to; in a town with two piers, which one
      local prevLeg = legs[#legs]
      local sameTown = prevLeg and prevLeg.how == "boat" and prevLeg.toTown == f.town
      local tram = f.dock and f.dock:find("^tram")
      -- a crossing that is more than a boat (the skyship and portal off Zephras Isle) says what you do
      local say = type(f.say) == "table" and n.dock and f.say[n.dock]
      -- a dock portal (beside the boats and zeppelins): the dock's text may name the boat
      if c.kind == "portal" and not (say and say:lower():find("portal", 1, true)) then say = "Take the portal to " .. (n.town or n.name) .. " (" .. (n.zone or mapName(n.m)) .. ")" end
      local text = say or tram and ("Take the Deeprun Tram to " .. (n.town or n.name)) or ((sameTown and ("In " .. f.town .. ", walk to " .. (f.pier or "the other pier") .. " and take the boat to ") or "Boat to ") .. (n.town or n.name) .. " (" .. (n.zone or mapName(n.m)) .. ")")
      -- (the card's headline says what you do: "Take the boat to Menethil Harbor (Wetlands)")
      legs[#legs + 1] = { sm = f.m, sx = f.x, sy = f.y, how = "boat", m = f.m, x = f.x, y = f.y, toTown = n.town, text = text, say = (text:gsub("^Boat to ", "Take the boat to ")), dock = (f.dock and Travel.DOCKS[f.dock] and Travel.DOCKS[f.dock].learned) or f.dock }
    end
  end
  -- (where each flight master is in the world: the same every trip)
  if flightWConv ~= HBD.GetWorldCoordinatesFromZone then flightW, flightWConv = setmetatable({}, { __mode = "k" }), HBD.GetWorldCoordinatesFromZone end
  -- (knowsFPKept's answers are checked against the state now: the search may have paused over frames)
  do
    local L2, sd = UnitLevel and UnitLevel("player") or 60, Travel.Side()
    local r2, c2 = myRaceClass()
    local gen = envNow(net(), (BeelineDB and BeelineDB.docks) or {})
    fpSync(L2, sd, r2, c2, Travel.Speed(), Travel.DangerHere(from.m, sd, L2), gen)
  end
  -- flight paths you do not have yet, right where a leg starts (the dock you land at, a town you ride through): grab
  -- them on the way - a minute now, flights later (the first one found per leg)
  for li, l in ipairs(legs) do
    local lw = world(l.sm or l.m, l.sx or l.x, l.sy or l.y) -- where the leg starts (the dock you step off at)
    if lw then
      for m, list in pairs(ns.FLIGHT or {}) do
        if l.fp then break end
        for _, f in ipairs(list) do
          if not knowsFPKept(m, f[3]) then
            local fw = flightWorld(m, f)
            if fw and fw[3] == lw[3] then
              local dd = math.sqrt((fw[1] - lw[1]) ^ 2 + (fw[2] - lw[2]) ^ 2)
              if dd <= Travel.FP_NEAR then
                local zn = mapName(m)
                l.fp = { m = m, x = f[1], y = f[2], npc = f[3], zone = zn, yd = dd, here = li == 1 or nil }; l.say = l.say or l.text; l.text = l.text .. Travel.FPNote(f[4] or zn, f[3], li == 1, ns.char and ns.char.taxiSeen)
                break
              end
            end
          end
        end
      end
    end
  end
  -- the trip's seconds, its seconds on a flight or boat, what it costs you in time spent playing, and the hostile
  -- towns' toll in those seconds (HOSTILE_SEC a town ridden through: a cost of choosing the route, not time - the pick
  -- audit's judge takes it out)
  return legs, secs[2], afk[2], dist[2], toll[2]
end

-- the note on a leg for a flight path you don't have where it starts (first leg: "before you go", it starts where you
-- stand). Until a flight master's map was opened on this character the addon doesn't know your flight paths (the
-- world map marks none undiscovered: State.ScanTaxi); talking to him tells it, and the trip is planned again
function Travel.FPNote(node, npc, here, seen)
  local name = tostring(node or ""):match("^([^,]+)") or tostring(node)
  npc = npc or "the flight master"
  local s = here and (" - before you go, get the " .. name .. " flight path from " .. npc .. " nearby") or (" - get the " .. name .. " flight path from " .. npc .. " where this leg starts")
  if not seen then s = s .. " (his flight map also shows the addon the flight paths you already have)" end
  return s
end

-- The same trip asked again in the same frame is answered from that frame's first search (perf: hundreds of trips a
-- frame, many repeated). Nothing a trip depends on changes within a frame but what the key holds (the graph stands for
-- level, faction, race, class, speed, flight paths and piers; the hearthstone's state is its own part). Callers
-- change the legs they get (the card appends to the first leg's text): each gets a copy.
local frameMemo, frameAt, frameInn = {}, nil, nil
local planEnv = {}
local function copyLegs(legs)
  if type(legs) ~= "table" then return legs end
  local out = {}
  for k, l in ipairs(legs) do if type(l) == "table" then local c = {}; for f, v in pairs(l) do c[f] = v end; out[k] = c else out[k] = l end end
  return out
end
-- While a route change's passes run over frames (Engine.After) the memo is kept from frame to frame, as if they ran in
-- one: the key already holds everything a trip depends on (Travel.PinMemo by the run, UnpinMemo when it ends)
local pinned
Travel.searches = 0 -- (searches made, not answered from the memo: tests and the perf battery)
function Travel.PinMemo(token)
  local now = GetTime and GetTime()
  if now ~= frameAt then frameMemo, frameAt, frameInn = {}, now, nil end
  pinned = token
end
function Travel.UnpinMemo(token) if pinned == token then pinned = nil end end
function Travel.Plan(from, to, opts)
  local now = GetTime and GetTime()
  if not now then return planTrip(from, to, opts) end
  if now ~= frameAt and not pinned then frameMemo, frameAt, frameInn = {}, now, nil end
  local ground = opts and opts.ground
  local noHearth = opts and opts.hearth == false
  local lvlNow, sideNow = UnitLevel and UnitLevel("player") or 60, Travel.Side()
  local rNow, cNow = myRaceClass()
  local G = graphFor(ground, lvlNow, sideNow, rNow, cNow, Travel.DangerHere(from.m, sideNow, lvlNow))
  local inn = "-"
  if not ground and not noHearth then
    -- (the hearthstone's state, once a frame)
    if not frameInn then
      local count = GetItemCount and GetItemCount(6948)
      local b = ns.char and ns.char.boundAt
      frameInn = table.concat({ tostring(count), tostring(ns.HearthCooldown and ns.HearthCooldown()), tostring(GetBindLocation and GetBindLocation()), tostring(b and b.m), tostring(b and b.name) }, ",")
    end
    inn = frameInn
  end
  -- (the part of the key the same for every trip of the moment: made again only when one of its values changed)
  local P = planEnv
  local lv = UnitLevel and UnitLevel("player")
  if not (P[1] == ground and P[2] == noHearth and P[3] == G and P[4] == inn and P[5] == lv and P[6] == Travel.SPELLS and P[7] == ns.VENDORS
    and P[8] == Travel.HEARTH_CAST and P[9] == Travel.HEARTH_VALUE and P[10] == Travel.AFK_WEIGHT and P[11] == Travel.OFFNET) then
    P = { ground, noHearth, G, inn, lv, Travel.SPELLS, ns.VENDORS, Travel.HEARTH_CAST, Travel.HEARTH_VALUE, Travel.AFK_WEIGHT, Travel.OFFNET }
    P.key = table.concat({ tostring(ground), tostring(noHearth), tostring(G), inn, tostring(lv), tostring(Travel.SPELLS), tostring(ns.VENDORS),
      tostring(Travel.HEARTH_CAST), tostring(Travel.HEARTH_VALUE), tostring(Travel.AFK_WEIGHT), tostring(Travel.OFFNET) }, "|")
    planEnv = P
  end
  local key = P.key .. "|" .. tostring(from.m) .. "|" .. tostring(from.x) .. "|" .. tostring(from.y) .. "|" .. tostring(to.m) .. "|" .. tostring(to.x)
    .. "|" .. tostring(to.y) .. "|" .. tostring(to.name) .. "|" .. tostring(to.stop)
  local hit = frameMemo[key]
  if hit then
    from.w = from.w or world(from.m, from.x, from.y); to.w = to.w or world(to.m, to.x, to.y) -- (as the search leaves them)
    return copyLegs(hit[1]), hit[2], hit[3], hit[4], hit[5]
  end
  Travel.searches = Travel.searches + 1
  local legs, secs, afk, dist, toll = planTrip(from, to, opts, G)
  frameMemo[key] = { copyLegs(legs), secs, afk, dist, toll }
  return legs, secs, afk, dist, toll
end

-- A trip inside one zone is a walk - unless a flight you know lands so much nearer the spot that flying is clearly
-- quicker. The trip planner decides against the same trip on foot, and the flight is offered only when it wins by a
-- margin (the times are estimates). No hearthstone: the plan has its own hearth steps.
-- -> legs, seconds, seconds on foot; nil = walk
-- Cheap (perf: the card asks every refresh): a short walk plans nothing; neither does a walk no flight could beat
-- (nearest flight point too far, or fewer than two known); a result holds within SHORTCUT_CELL yards until inputs change.
Travel.AFK_WEIGHT = 0.35     -- a second on a flight or a boat, as time spent playing (taking off and landing need you)
Travel.SHORTCUT_SLOWER = 0.2 -- a flight that means less time on foot may take this share longer than the walk
Travel.SHORTCUT_MIN = 120    -- a walk shorter than this (seconds) is never worth a flight: nothing is planned at all
Travel.SHORTCUT_SAVES = 45   -- the flight must save at least this many seconds...
Travel.SHORTCUT_SHARE = 0.15 -- ...and this share of the walk
Travel.SHORTCUT_CELL = 40
local shortcutMemo, shortcutCount = {}, 0
function Travel.Shortcut(from, to)
  from.w = from.w or world(from.m, from.x, from.y); to.w = to.w or world(to.m, to.x, to.y)
  if not (from.w and to.w and from.w[3] == to.w[3]) then return nil end
  local speed = Travel.Speed()
  local walk = d(from, to) * Travel.OFFNET / speed
  if walk < Travel.SHORTCUT_MIN then return nil end
  local function margin(w) return math.max(Travel.SHORTCUT_SAVES, Travel.SHORTCUT_SHARE * w) end
  local taxi = (ns.State and ns.State.knownTaxi) or {}
  local known = 0; for _ in pairs(taxi) do known = known + 1 end -- (flight paths are only ever gained: their number says which)
  local C = Travel.SHORTCUT_CELL
  local tk = to.m .. ":" .. to.x .. ":" .. to.y
  local key = table.concat({ from.m, math.floor(from.w[1] / C), math.floor(from.w[2] / C), tostring(taxi), known, speed, Travel.Side(), tostring(Travel.NET), tostring(ns.FLIGHT) }, "|")
  local memo = shortcutMemo[tk]
  if memo and memo.key == key then return memo.legs, memo.secs, memo.walk end
  if not memo then
    if shortcutCount >= 64 then shortcutMemo, shortcutCount = {}, 0 end
    memo = {}; shortcutMemo[tk] = memo; shortcutCount = shortcutCount + 1
  end
  memo.key, memo.legs, memo.secs, memo.walk = key, nil, nil, nil
  -- the quickest a flight could be: the walk to your nearest flight point, the take-off, and a landing right on the spot
  local letter = ns.State.MyFaction() or "A"
  local near, count = nil, 0
  local function point(w) count = count + 1; local dd = math.sqrt((w[1] - from.w[1]) ^ 2 + (w[2] - from.w[2]) ^ 2); if not near or dd < near then near = dd end end
  if Travel.NET then
    for _, n in ipairs(net()) do
      if n.kind == "fp" and n.w[3] == from.w[3] and (not n.side or n.side:find(letter, 1, true)) and knowsFP(n.m, n.name) then point(n.w) end
    end
  else
    for m, list in pairs(ns.FLIGHT or {}) do
      local f = list[1]; local w = world(m, f[1], f[2])
      if w and w[3] == from.w[3] and knowsFP(m, f[3]) then point(w) end
    end
  end
  -- (the quickest a flight could be, in time on foot: the walk to the flight point and the take-off)
  if not (count >= 2 and near * Travel.OFFNET / speed + Travel.FLY_EXTRA <= walk - margin(walk) * Travel.AFK_WEIGHT) then return nil end
  local legs, secs, afk = Travel.Plan(from, to, { hearth = false })
  if not (legs and legs[1] and secs) then return nil end
  local rides = true
  for _, l in ipairs(legs) do if l.how ~= "ride" then rides = false; break end end
  if rides then return nil end
  -- on foot along the roads may beat the straight-line guess: the flight has to beat the better of the two
  local _, foot = Travel.Plan({ m = from.m, x = from.x, y = from.y, w = from.w }, { m = to.m, x = to.x, y = to.y, name = to.name, w = to.w }, { ground = true })
  if foot and foot < walk then walk = foot end
  -- the flight wins on time spent playing: its time on foot plus a share of its time in the air, by a margin, and not
  -- much slower on the clock
  local onFoot = secs - (afk or 0)
  local playing = onFoot + (afk or 0) * Travel.AFK_WEIGHT
  if playing > walk - margin(walk) or secs > walk * (1 + Travel.SHORTCUT_SLOWER) then return nil end
  -- said on the card and the arrow: why you are sent to a flight master for a step in your own zone
  local saved = math.max(1, math.floor((walk - onFoot) / 60 + 0.5))
  legs[1].say = legs[1].say or legs[1].text
  -- ("riding" once mounted)
  local going = Travel.Speed() > (Travel.RIDE or 0) and "riding" or "walking"
  legs[1].gain = secs <= walk - margin(walk) and ("about " .. math.max(1, math.floor((walk - secs) / 60 + 0.5)) .. " min quicker than " .. going .. " there")
    or ("about as quick as " .. going .. " there, with " .. saved .. " min less " .. going)
  legs[1].text = legs[1].text .. " - " .. legs[1].gain
  memo.legs, memo.secs, memo.walk = legs, secs, walk
  return legs, secs, walk
end

-- A leg in a few words, for the card's headline: what you do now ("Fly to Westfall"), without the notes the leg's
-- full text carries (Travel.LegExtra). A leg built elsewhere (Engine.TravelFor) has no say: its text up to the first
-- " - " outside brackets (a "(... - ... border)" is part of the leg)
local function dash(t)
  local depth = 0
  for k = 1, #t - 2 do
    local ch = t:sub(k, k)
    if ch == "(" then depth = depth + 1 elseif ch == ")" then depth = math.max(0, depth - 1)
    elseif depth == 0 and ch == " " and t:sub(k, k + 2) == " - " then return k end
  end
end
function Travel.LegSay(l)
  if type(l) ~= "table" then return "" end
  if l.say then return l.say end
  local t = l.text or ""
  local a = dash(t)
  return a and t:sub(1, a - 1) or t
end
-- what the leg's full text says past its headline, apart from a flight path to pick up (the card gives that its own
-- line: l.fp): the other faction's town on the way, the minutes a shortcut saves, "sit tight". nil: nothing
function Travel.LegExtra(l)
  if type(l) ~= "table" then return nil end
  if l.say then
    local parts = {}
    if l.warn then parts[#parts + 1] = l.warn end
    if l.gain then parts[#parts + 1] = l.gain end
    return #parts > 0 and table.concat(parts, "; ") or nil
  end
  local t = l.text or ""
  local a = dash(t)
  local rest = a and t:sub(a + 3) or nil
  -- ("Ride to Duskwood - 300 yd": the card's distance already says it)
  if not rest or rest == "" or rest:find("^%d[%d.]*k? yd$") then return nil end
  return rest
end

-- one line for the card: "Fly to Wetlands -> Boat from Menethil Harbor to Theramore -> Ride to The Barrens"
function Travel.Describe(legs)
  local parts = {}
  for _, l in ipairs(legs or {}) do parts[#parts + 1] = l.text end
  return table.concat(parts, "  >  ")
end

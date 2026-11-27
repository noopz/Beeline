-- What to do next, decided by the live solver (Horizon.lua) over the stops that could come next. The plan scan
-- (Engine.Compute) says which steps are done, waiting or out; this picks, among the next ones you can do and the
-- finished quests whose hand-in is near, the one that makes the whole way from here shortest - and says why when it
-- isn't the plan's next step. Detours (a dungeon group, a trip to town) need no rules: the solve starts from where you
-- are. Design: docs/research/live-routing.md.
local _, ns = ...
local pcall = ns.PCall or pcall -- (a job never pauses under it: Core.lua)
local Next = {}
ns.Next = Next
local HBD = LibStub("HereBeDragons-2.0")

Next.WINDOW = 14        -- planned stops the solve looks at
Next.SCAN = 90          -- steps scanned for them
Next.HERE_YD = 250      -- the plan's own later steps this close to you (Next.HereBlock)...
Next.HERE_FAR = 600     -- ...while its next step is this far: you are where the plan goes later - start there
Next.NEAR_READY = 500   -- yards: finished quests further than this are left to the plan (a bound on the candidates: Next.Prize decides)
Next.MARGIN = 40        -- seconds: a new pick must beat keeping the current one by this much (no flip-flopping)
Next.PASS_NEAR = 40     -- yards: a stop this close is an interrupt (said at once, no margin) - you are at its NPC
Next.SAME_PLACE = 200   -- yards: the card's stop and a new pick this close together: the order is yours, the card stays
Next.CARRY = 30         -- seconds: what carrying a finished quest costs (a log slot, the risk it goes gray)
Next.BEHIND_YD = 2000   -- yards: a pick-up the built-in plan passed as behind you, this close, is a candidate (Next.Prize decides)
Next.BEHIND_MAX = 6     -- ...the nearest this many
Next.BEHIND_KEEP = 2    -- ...and the one on the card stays one out to this many times BEHIND_YD (no flipping as you walk)
Next.HOLD_NEAR = 400    -- yards: a prize this close can come before the plan's trip or grind step
Next.BEHIND_WORK = 150  -- seconds: an objective's work and the way to it, for a step that doesn't carry the planner's (s.work)
Next.DISMISS_SECS = 900 -- "not now" on a while-you're-here stop: it stays off for this long...
Next.DISMISS_YD = 500    -- ...or until you are this far from where you said it
Next.dismissed = {}      -- step (the table: an inserted stop moves the numbers on) -> { t, x, y, inst }: where and when
Next.RESOLVE = 2        -- seconds: re-solve at least this often while things change
Next.SERVICE = { accept = 8, turnin = 10, obj = 90, fp = 15, train = 40, bind = 15, ["goto"] = 5 }
-- (a "go to" step - a dungeon run, a place to be - is a commitment, not a stop to fit in: it stays where the plan has it)
Next.KIND = { accept = true, turnin = true, obj = true, fp = true, train = true, bind = true }
-- what a vendor visit is worth by free bag slots (seconds): at 0 every kill's loot is lost
Next.BAG_PRIZE = { [0] = 900, [1] = 500, [2] = 300, [3] = 200, [4] = 120, [5] = 80, [6] = 50 }

function Next.Enabled() return ns.db and ns.db.smartNext ~= false end
-- the special rules on top of the solve, each one switch (measured with the pick audit: tools/pick-audit.js --addon)
Next.rules = { behindTravel = true, behindAhead = true, localBlock = true, hereBlock = true, visitHere = true, pickupFirst = true, behind = true, belowFloor = true, ownAtFrom = true }

local wpos = ns.Util.WPos
local isTrip = ns.Engine.IsTrip
Next._wpos = wpos

-- seconds from place a to place b ({ w = {x, y, inst}, m, x, y }): a straight line at your speed (OFFNET for the way
-- round things); far or across the sea, the trip planner's estimate (~30 ms a search), asked once per place you set out
-- from and zone you go to - other stops in that zone add their straight line from the first. "From" is a plan step or
-- your spot to the nearest 250 yd. Remembered until you learn a flight path, mount up or level (priceSig).
local function speedNow() return (ns.Travel and ns.Travel.Speed and ns.Travel.Speed()) or 7 end
local OFFNET = ns.Travel.OFFNET -- (a straight line's yards count this much longer: Travel.WalkSecs)
local function knownTaxiCount() return ns.State.KnownTaxiCount() end
-- what a remembered trip or price depends on besides the plan: known flight paths, speed, level (the trip planner
-- avoids zones far above you). Taken once per solve (Next.Pick); outside a solve, each call.
local sigNow
local function priceSig()
  return sigNow or (knownTaxiCount() .. ":" .. speedNow() .. ":" .. ((UnitLevel and UnitLevel("player")) or 1))
end
local zoneMemo, zoneTaxi, startKeys = setmetatable({}, { __mode = "k" }), nil, 0
local function travelSecs(a, b)
  local wa, wb = a.w, b.w
  if not (wa and wb) then return 600 end
  local speed = (ns.Travel and ns.Travel.Speed and ns.Travel.Speed()) or 7
  local function straight(p, q) return math.sqrt((p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2) * OFFNET / speed end
  -- (the same zone, or near: the walk. Within a zone the trip planner nearly always says "walk" too - asked for every
  -- far stop in a big zone it was 1,500 of 1,650 searches in a simulated 600 steps; a flight across one zone is the
  -- card's own shortcut check, Travel.Shortcut)
  if wa[3] == wb[3] then
    local yd = math.sqrt((wa[1] - wb[1]) ^ 2 + (wa[2] - wb[2]) ^ 2)
    if yd < 900 or (a.m and a.m == b.m) or not (ns.Travel and ns.Travel.Plan) then return yd * OFFNET / speed end
  end
  local n = priceSig()
  if zoneTaxi ~= n then zoneMemo = setmetatable({}, { __mode = "k" }); zoneTaxi, startKeys = n, 0 end
  local from = a.st or ("at:" .. math.floor(wa[1] / 250) .. ":" .. math.floor(wa[2] / 250) .. ":" .. tostring(wa[3]))
  -- (another zone: one trip per zone, plus the walk from its first stop; the same zone: each far stop on its own - a
  -- remembered stop on the far side of a big zone would make a nearer one look as far as that, and then some)
  local to = (a.m and b.m and a.m ~= b.m) and b.m or b.st or b
  local row = zoneMemo[from]
  local e = row and row[to]
  if e then return e.secs + ((to == b.m and e.w[3] == wb[3]) and straight(e.w, wb) or 0) end
  local v = 1800 -- (no way known: as good as unreachable for a window)
  if ns.Travel and ns.Travel.Plan and a.m and b.m then
    local ok, legs, secs = ns.Call(ns.Travel.Plan, { m = a.m, x = a.x, y = a.y }, { m = b.m, x = b.x, y = b.y })
    if ok and legs and secs then v = secs end
  end
  do
    if not row then
      -- (places you stood at are kept up to 400, then forgotten: steps are kept as long as the plan is)
      if not a.st then startKeys = startKeys + 1; if startKeys > 400 then zoneMemo = setmetatable({}, { __mode = "k" }); startKeys = 0 end end
      row = {}; zoneMemo[from] = row
    end
    row[to] = { secs = v, w = wb }
  end
  return v
end

-- your XP per second at your level (Engine.XpPerSec; fallback a level per 1.5 h)
local function rate()
  if ns.Engine and ns.Engine.XpPerSec then return ns.Engine.XpPerSec() end
  local need = (UnitXPMax and UnitXPMax("player")) or 10000
  return math.max(1, need / 5400)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Now or later: one price for every stop the solve may take out of the plan's order (a finished quest's hand-in the
-- plan has further on, a stop the route took in, a quest behind you, a later visit to where you are):
--   prize = the least of what it pays (its quest's XP at your rate, less the work still between you and that XP) and
--           what leaving it for later costs (Next.DeferCost: the plan comes back for it - the stop itself, carrying the
--           quest, and the detour from the plan's own way to it there).
-- A stop the plan comes back to is worth that detour and no more; one it never comes back to is worth its XP. A gray
-- quest pays a little either way (Engine.QuestXP).
-- The detour follows the plan's real way, not a straight line between neighbours: within a zone the walk; across
-- zones (Travel.Plan, no hearthstone) the walks at each end of the trip (to the flight master or pier, from where you
-- land); across a plan hearth, the walk before it and the walk from the bound inn.
-- A later pass counts only where the solve would offer the stop then: a hand-in at a hub or where its chain goes on,
-- within Next.NEAR_READY of the way (Next.Pick's rule). Any other stop is done at its own place in the plan or not at all.
-- Independent of where you stand (only plan, flight paths, speed, level): prizes skip the hysteresis (Next.MARGIN), so
-- a prize that moved as you walked would flip the card.
-- ---------------------------------------------------------------------------------------------------------------
Next.DEFER_CELL = 400   -- yards: the grid the plan's way is indexed by
Next.DEFER_ENOUGH = 60  -- seconds: a gap this cheap found among the walks - the far trips needn't be asked
Next.DEFER_FAR = 3      -- trip-planner searches one stop's price may start (the soonest far gaps; remembered ones are free)
-- trip-planner searches (~30 ms each) all the prices of one solve may start (perf: a new flight path forgets every
-- remembered trip). A price still missing a search is asked again next solve, meanwhile taken as "the plan comes by" -
-- a stop is never sent for on a guess.
Next.ASK_PER_PICK = 4
local huge = math.huge
local function yd(p, q) return math.sqrt((p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2) end
-- the detour (seconds) of stopping at p on the walk x -> y, and how near that walk comes to p (yards); nil when they
-- aren't in one world
local function segDetour(x, y, p)
  if not (x and y and p) or x[3] ~= p[3] or y[3] ~= p[3] then return nil end
  return math.max(0, yd(x, p) + yd(p, y) - yd(x, y)) * OFFNET / speedNow(), (ns.Travel.SegDist(p[1], p[2], x, y))
end
-- the searches left in this solve (nil: no bound - outside a solve): true takes one
local askLeft
local function mayAsk()
  if askLeft == nil then return true end
  if askLeft <= 0 then return false end
  askLeft = askLeft - 1
  return true
end
Next._askLeft = function(n) askLeft = n end -- (tests: a solve's bound, outside one)
-- The plan's trip between two of its stops (step tables) that are far apart: its seconds, and the walk at each end -
-- D, where it leaves the walk (the flight master, the pier), and P, where it comes back to it (where you land); or
-- ride = true for one long ride. false: no way known. Remembered per pair of steps until the flight paths you know,
-- your speed or your level change (priceSig). ask = false: only what is remembered (nil: not priced yet).
local tripMemo, tripSig = setmetatable({}, { __mode = "k" }), nil
local function farTrip(a, b, ask)
  local sig = priceSig()
  if tripSig ~= sig then tripMemo = setmetatable({}, { __mode = "k" }); tripSig = sig end
  local row = tripMemo[a]
  local e = row and row[b]
  if e ~= nil or not ask then return e end
  e = false
  if ns.Travel and ns.Travel.Plan then
    local ok, legs, secs = ns.Call(ns.Travel.Plan, { m = a.m, x = a.x, y = a.y }, { m = b.m, x = b.x, y = b.y }, { hearth = false })
    if ok and legs and secs then
      e = { secs = secs }
      local function w(m, x, y) if not (m and x and y) then return nil end local wx, wy, wi = HBD:GetWorldCoordinatesFromZone(x, y, m); return wx and { wx, wy, wi } or nil end
      local allRide = true
      for _, l in ipairs(legs) do if l.how ~= "ride" then allRide = false end end
      if allRide then e.ride = true
      else
        -- (the first leg that isn't a ride starts where the walk ends: a flight master or a pier; a teleport has no walk)
        for _, l in ipairs(legs) do if l.how ~= "ride" then if l.how == "fly" or l.how == "boat" then e.D = w(l.sm, l.sx, l.sy) end break end end
        local L = legs[#legs]
        if #legs > 1 and L.how == "ride" then e.P = w(L.sm, L.sx, L.sy) end
      end
    end
  end
  -- (no trip found, in one world: the plan gets there somehow - priced as the ride, not as unreachable; the plan's own
  -- order says it goes)
  local A, B = not e and wpos(a), not e and wpos(b)
  if A and B and A[3] == B[3] then e = { secs = yd(A, B) * OFFNET / speedNow(), ride = true } end
  if not row then row = {}; tripMemo[a] = row end
  row[b] = e
  return e
end
-- seconds the plan takes from its stop a to its stop b (step tables): the walk, or the trip when they are far apart.
-- ask = false: a far trip not priced yet is nil, and true second
local function planSecs(a, b, ask)
  local A, B = wpos(a), wpos(b)
  if not (A and B) then return nil end
  if A[3] == B[3] and (a.m == b.m or yd(A, B) < 900) then return yd(A, B) * OFFNET / speedNow() end
  local e = farTrip(a, b, ask ~= false)
  if e == nil then return nil, true end
  return e and e.secs or nil
end

-- The plan's way, indexed: its located stops in order (travel steps are no stops), the gaps between them (with a
-- hearth: walk before it, then from the bound inn; with a boat: its pier ends the walk), and a grid of gaps by the
-- cells their walks pass. A far gap is indexed along the walks to every port of its two maps (Travel.Ports) until its
-- trip is priced, then along its own. Built once per list generation; stops are step tables, so a price survives
-- the plan moving on.
local wayMemo = setmetatable({}, { __mode = "k" })
-- a grid cell's key: a number (a string made for every cell a walk passes was the index's dearest part)
local function cellKey(cx, cy, inst) return ((tonumber(inst) or -1) * 4096 + cx + 2048) * 4096 + cy + 2048 end
local function walkable(a, b) return a.w[3] == b.w[3] and (a.st.m == b.st.m or yd(a.w, b.w) < 900) end
local function way(list)
  local W = wayMemo[list]
  if W and W.gen == (list._gen or 0) then return W end
  W = { gen = list._gen or 0, stops = {}, at = {}, gaps = {}, grid = {}, ver = 0 }
  local trips, bind = {}, nil
  -- (built in the solve's slices: a level-50's plan is ~3,500 steps, and the first price after the plan changed - a
  -- login, a stop added - indexed all of it in one slice of 20-40 ms. A pause here is safe: W is kept only once it is
  -- whole, and only for the list generation it started on)
  for j, s in ipairs(list) do
    if j % 64 == 0 then ns.MaybeYield() end
    if isTrip(s) then trips[#trips + 1] = s
    else
      local w = wpos(s)
      if w then
        local e = { j = j, st = s, w = w }
        local k = #W.stops
        if k > 0 then
          local g = { a = W.stops[k], b = e }
          for _, t in ipairs(trips) do if t.k == "hearth" then g.hearth = bind end end
          -- (a hearth to an inn the plan never bound you at: where it lands isn't known - the trip planner's way)
          if not g.hearth and trips[1] and trips[1].boat then g.pier = wpos(trips[1]) end
          W.gaps[k] = g
        end
        W.stops[k + 1] = e
        if not W.at[s] then W.at[s] = k + 1 end
        if s.k == "bind" then bind = e end
        trips = {}
      end
    end
  end
  local C = Next.DEFER_CELL
  local grid = W.grid
  local function putXY(x, y, inst, k)
    local key = cellKey(math.floor(x / C), math.floor(y / C), inst)
    local c = grid[key]
    if not c then c = {}; grid[key] = c end
    if c[#c] ~= k then c[#c + 1] = k end
  end
  local function put(w, k) putXY(w[1], w[2], w[3], k) end
  -- (a walk across a zone passes the cells between its ends: a stop half way along is on the way)
  local function line(x, y, k)
    put(x, k); put(y, k)
    if x[3] ~= y[3] then return end
    local n = math.floor(yd(x, y) / (C / 2))
    for t = 1, n do putXY(x[1] + (y[1] - x[1]) * t / (n + 1), x[2] + (y[2] - x[2]) * t / (n + 1), x[3], k) end
  end
  W.line = line
  local ports = (ns.Travel and ns.Travel.Ports) or function() return {} end
  local function leg(x, y, k, pier)
    if walkable(x, y) then line(x.w, y.w, k); return end
    put(x.w, k); put(y.w, k)
    if pier then line(x.w, pier, k) else for _, p in ipairs(ports(x.st.m)) do if p[3] == x.w[3] then line(x.w, p, k) end end end
    for _, p in ipairs(ports(y.st.m)) do if p[3] == y.w[3] then line(p, y.w, k) end end
  end
  for k, g in ipairs(W.gaps) do
    if k % 8 == 0 then ns.MaybeYield() end
    if g.hearth then put(g.a.w, k); leg(g.hearth, g.b, k)
    else leg(g.a, g.b, k, g.pier) end
  end
  wayMemo[list] = W
  return W
end

local function serviceOf(s) return (s.k == "obj" and tonumber(s.work)) or Next.SERVICE[s.k] or 15 end
-- the cheaper of two (detour, how near) pairs
local function better(d1, n1, d2, n2) if d1 and (not d2 or d1 <= d2) then return d1, n1 end return d2, n2 end
-- the detour (seconds) of fitting a stop at p into the plan's way from stop x to stop y, and how near that way comes
-- to p (yards); ask: the trip planner may be asked. k: the gap, whose trip's walks are indexed once known.
-- -> seconds, yards; or nil (no fit), and true when the trip wasn't priced yet
local function legDetour(W, k, x, y, p, ask, pier)
  if walkable(x, y) then return segDetour(x.w, y.w, p) end
  local e = farTrip(x.st, y.st, false)
  if e == nil and ask and mayAsk() then e = farTrip(x.st, y.st, true) end
  if e == nil then return nil, nil, true end
  if not e then return nil end
  if e.ride then return segDetour(x.w, y.w, p) end
  local D = pier or e.D
  local g = k and W.gaps[k]
  if g and not g.indexed then
    -- (the trip's own walks, along their length: one may start or end off the two maps - a ride to a flight master)
    g.indexed = true
    if D and D[3] == x.w[3] then W.line(x.w, D, k) end
    if e.P and e.P[3] == y.w[3] then W.line(e.P, y.w, k) end
    W.ver = W.ver + 1
  end
  local d1, n1 = segDetour(x.w, D, p)
  local d2, n2 = segDetour(e.P, y.w, p)
  return better(d1, n1, d2, n2)
end
-- the same for a gap of the way (g: { a, b, hearth = the inn's stop, pier })
local function gapDetour(W, k, g, p, ask)
  if not g.hearth then return legDetour(W, k, g.a, g.b, p, ask, g.pier) end
  -- (before the hearth: the walk to it, and you hearth from there - no way back; after it, the way on from the inn)
  local d1, n1
  if g.a.w[3] == p[3] then n1 = yd(g.a.w, p); d1 = n1 * OFFNET / speedNow() end
  local d2, n2, unpriced = legDetour(W, k, g.hearth, g.b, p, ask)
  local d, n = better(d1, n1, d2, n2)
  return d, n, unpriced
end

-- would the solve offer stop s on a later pass of the plan, off its own place? Only a finished quest's hand-in at a
-- hub or where its chain goes on - within this many yards of you (Next.Pick). nil: only its own place counts.
local isHub, chainsOnHere
local function passReach(list, s)
  if s.k == "turnin" and s.q and (isHub(list, s) or chainsOnHere(list, s)) then return Next.NEAR_READY end
  return nil
end

-- What leaving stop s for later costs, in seconds, when the plan goes on from its step `from`: the stop itself, carrying
-- the quest (Next.CARRY), and the cheapest detour from the plan's own way from there on - at its own place in the plan,
-- or at another pass the plan makes by it where the solve would offer it (passReach). math.huge: the plan never comes
-- by again. behind: a stop the plan has passed for good (a quest behind you) - its own place doesn't count.
local deferMemo = setmetatable({}, { __mode = "k" })
function Next.DeferCost(list, s, from, behind)
  local p = wpos(s)
  if not p then return huge end
  local W = way(list)
  local key = from .. ":" .. priceSig() .. ":" .. tostring(behind)
  local m = deferMemo[s]
  if m and m.key == key and m.W == W and m.ver == W.ver then return m.v end
  local best, whole = huge, true -- (whole: every trip it looked at was priced)
  -- (the first stop of the way at or after `from`)
  local lo, hi = 1, #W.stops + 1
  while lo < hi do local mid = math.floor((lo + hi) / 2); if W.stops[mid].j < from then lo = mid + 1 else hi = mid end end
  local first = lo
  -- its own place in the plan: the gap between its neighbours, with the plan's trips on either side of it (a few
  -- hand-ins at one NPC are each other's neighbours)
  local own = not behind and W.at[s]
  if own and (W.stops[own].j > from or (Next.rules.ownAtFrom and W.stops[own].j == from)) then
    local a, b = W.stops[own - 1], W.stops[own + 1]
    local d, unpriced, _n
    if tonumber(s.dt) and Next.useClock then
      -- (the plan's own detour there, from its clock: tools/plan-clock.js - no trip to price)
      d = tonumber(s.dd) or 0
    elseif a and b then
      local g1, g2 = W.gaps[own - 1], W.gaps[own]
      d, _n, unpriced = gapDetour(W, nil, { a = a, b = b, hearth = g1.hearth or g2.hearth, pier = g1.pier or g2.pier }, p, true)
    elseif a or b then
      -- (the plan ends there, or starts: the way to it)
      d, unpriced = planSecs(a and a.st or s, b and b.st or s, false)
      if d == nil and unpriced and mayAsk() then d, unpriced = planSecs(a and a.st or s, b and b.st or s, true) end
    end
    if unpriced then whole = false end
    if d and d < best then best = d end
  end
  -- another pass of the way from `from` on where it would be offered: the walks first (cheap), then the soonest far trips
  local reach = passReach(list, s)
  if reach then
    local C = Next.DEFER_CELL
    -- (the walks are indexed every half cell: one passing within reach of p has a point in these cells)
    local r = math.floor((reach + C / 4) / C) + 1
    local cx, cy = math.floor(p[1] / C), math.floor(p[2] / C)
    local seen, far = {}, {}
    for dx = -r, r do
      for dy = -r, r do
        for _, k in ipairs(W.grid[cellKey(cx + dx, cy + dy, p[3])] or {}) do
          if not seen[k] and k >= first then
            seen[k] = true
            local g = W.gaps[k]
            if g.a.st ~= s and g.b.st ~= s then
              local d, near, unpriced = gapDetour(W, k, g, p, false)
              if d and near <= reach then if d < best then best = d end elseif unpriced then far[#far + 1] = k end
            end
          end
        end
      end
    end
    if best > Next.DEFER_ENOUGH and #far > 0 then
      table.sort(far)
      for q = 1, math.min(Next.DEFER_FAR, #far) do
        local d, near, unpriced = gapDetour(W, far[q], W.gaps[far[q]], p, true)
        if unpriced then whole = false elseif d and near <= reach and d < best then best = d end
      end
    end
  end
  -- (a price still missing a trip: taken as "the plan comes by" until the next solve prices it, and not remembered)
  local v = best < huge and (serviceOf(s) + Next.CARRY + best) or huge
  if not whole then v = serviceOf(s) + Next.CARRY
  else deferMemo[s] = { key = key, W = W, ver = W.ver, v = v } end
  return v
end

-- the work still between you and a quest's XP, in seconds: its unfinished objective steps (the planner's s.work) and
-- the plan's walks for them, to each and on to the hand-in (s.walk, yards; the walk on only when the work before it
-- is known). Next.BEHIND_WORK per objective when a step has no s.work or the quest has no objective step. except: an
-- objective that is the stop itself (the solve charges its work as the stop's own time).
local objWork = setmetatable({}, { __mode = "k" })
local function workOf(list, q, except)
  local c = objWork[list]
  if not c or c.gen ~= (list._gen or 0) then
    c = { gen = list._gen or 0, by = {}, back = {}, turn = {} }
    for _, t in ipairs(list) do
      if t.k == "obj" and t.q then
        local e = c.by[t.q]; if not e then e = {}; c.by[t.q] = e end
        local known = tonumber(t.work) ~= nil
        e[#e + 1] = { st = t, secs = tonumber(t.work) or Next.BEHIND_WORK, yd = known and tonumber(t.walk) or 0, known = known }
      elseif t.k == "turnin" and t.q then
        if tonumber(t.walk) and not c.back[t.q] then c.back[t.q] = tonumber(t.walk) end
        if not c.turn[t.q] then c.turn[t.q] = t end
      end
    end
    objWork[list] = c
  end
  local objs = c.by[q]
  if not objs then return Next.BEHIND_WORK end
  local E, St = ns.Engine, ns.State
  if St and St.QuestReady and St.QuestReady(q) then return 0 end -- (all done: the way to the hand-in is the solve's)
  local secs, yards, known = 0, 0, false
  for _, o in ipairs(objs) do
    local ob = o.st ~= except and E.ObjectiveFor and E.ObjectiveFor(o.st)
    if o.st ~= except and not (ob and ob.finished) then
      secs = secs + o.secs; yards = yards + o.yd; known = known or o.known
    end
  end
  if known then yards = yards + (c.back[q] or 0) end
  return secs + yards * OFFNET / speedNow()
end

-- A hub: a place the plan stops at a lot (a town) - Next.HUB_STEPS steps within Next.HUB_YD of it. Hand-ins there are
-- welcome any time; out in the field one is only taken early when its chain goes on right there. The rest wait for the
-- plan's visit to the hub (handing in a pile at once is intended, not chipped away).
Next.HUB_YD, Next.HUB_STEPS, Next.CHAIN_YD = 70, 4, 150
-- A later visit to where you are now (Next.VisitHere): the plan leaves, and comes back here for more - hand-ins, a
-- chain's next part, a trainer. When all of that visit can be done now, doing it now saves the whole trip back.
Next.VISIT_SCAN = 250   -- steps ahead looked through for a later visit here
Next.TRIP_MIN = 120     -- a trip back is never valued at less than this (a hearth back costs its hour of cooldown)
-- -> { now = { step indices you can do this moment }, saves = seconds } or nil
function Next.VisitHere(list, planned, from, pm, px, py, pinst)
  if not pm then return nil end
  local E, St = ns.Engine, ns.State
  local Lv = (UnitLevel and UnitLevel("player")) or 1
  local function preMet(q, handed)
    if not St.PrereqsMet(q, handed) then return false end
    for _, x in ipairs(E.PrereqsOf and E.PrereqsOf(q) or {}) do if not (St.IsCompleted(x) or handed[x]) then return false end end
    return true
  end
  -- quests that have work somewhere ahead (an objective step): their hand-in can't follow a pick-up made now
  local work = {}
  for j = from, math.min(#list, from + Next.VISIT_SCAN) do local s = list[j]; if s.k == "obj" and s.q then work[s.q] = true end end
  -- the visits: runs of steps between trips (or map changes); the first one on your map, past the window
  -- (only once the plan has left here - a trip, or steps somewhere else: until then it is still this visit)
  local left = false
  for x = planned, from - 1 do local t = list[x]; if E.Status(x) ~= "done" and (isTrip(t) or (t.m and t.m ~= pm)) then left = true; break end end
  -- (a hearth or another bind of the plan's before the visit: a bind in it can't come now - the plan's hearths before it
  -- go to the inn the plan bound you at, and a bind between overwrites it)
  local hearthBefore = false
  for x = planned, from - 1 do local k = list[x].k; if k == "hearth" or k == "bind" then hearthBefore = true; break end end
  local j, last = from, math.min(#list, from + Next.VISIT_SCAN)
  local prevPos -- the last place the plan is at before the visit (for the trip's length)
  while j <= last do
    ns.MaybeYield() -- (in the background solve: a slice a frame)
    local s = list[j]
    if isTrip(s) or not s.m or s.m ~= pm or not left then
      if E.Status(j) ~= "done" and (isTrip(s) or (s.m and s.m ~= pm)) then left = true end
      if s.k == "hearth" or s.k == "bind" then hearthBefore = true end
      if s.m and not isTrip(s) and E.Status(j) ~= "done" then prevPos = s end
      j = j + 1
    else
      -- a run on your map: j .. k
      local k = j
      while k + 1 <= last and not isTrip(list[k + 1]) and (not list[k + 1].m or list[k + 1].m == pm) do k = k + 1 end
      local handed, accepted, ok, now, any = {}, {}, true, {}, false
      local load = (St.LogCount and St.LogCount()) or 0
      local cap = (St.MaxLog and St.MaxLog()) or 25
      for x = j, k do
        if x % 8 == 0 then ns.MaybeYield() end
        local t = list[x]
        local stx = E.Status(x)
        if stx ~= "done" then
          any = true
          local can = true
          -- (a step the engine has as "wait" is not doable now, whatever its kind - except a pick-up waiting on a hand-in
          -- (Engine.WaitsForHandIn): preMet below says whether this visit hands that quest in first)
          if (stx == "wait" and not E.WaitsForHandIn(t)) or (t.minLevel and t.minLevel > Lv) or (E.TooHigh and E.TooHigh(t, Lv)) then can = false
          elseif t.k == "obj" or t.k == "grind" or t.unknown then can = false -- work, not a stop: the visit is still needed
          elseif t.k == "bind" and hearthBefore then can = false
          elseif t.k == "accept" then
            can = t.q and preMet(t.q, handed) and load < cap
            if can then accepted[t.q] = true; load = load + 1 end
          elseif t.k == "turnin" then
            can = t.q and (St.QuestReady(t.q) or (accepted[t.q] and not work[t.q]))
            if can then handed[t.q] = true; load = load - 1 end
          end
          if not can then ok = false; break end
          -- doable this moment (not after another step of the visit): a stop the solve can take now
          local nowOk = (t.k ~= "accept" or (E.Available and E.Available(x))) and (t.k ~= "turnin" or St.QuestReady(t.q))
          if nowOk and t.m and t.x then now[#now + 1] = x end
        end
      end
      if ok and any and #now > 0 then
        -- the trip it saves: the plan's way into the visit and out again, against its way past it (planSecs: real trips)
        local first, lastIn, after
        for x = j, k do local t = list[x]; if wpos(t) and E.Status(x) ~= "done" then first = first or t; lastIn = t end end
        for x = k + 1, math.min(#list, k + Next.VISIT_SCAN) do local t = list[x]; if not isTrip(t) and wpos(t) and E.Status(x) ~= "done" then after = t; break end end
        local tin = prevPos and first and planSecs(prevPos, first)
        local saves = tin
        if tin and after and lastIn then
          local tout, past = planSecs(lastIn, after), planSecs(prevPos, after)
          if tout and past then saves = tin + tout - past end
        end
        saves = math.max(Next.TRIP_MIN, saves or Next.TRIP_MIN)
        return { now = now, saves = saves, from = j, to = k }
      end
      if any then return nil end -- the next visit here isn't all doable now: it happens anyway, its stops wait for it
      j = k + 1
    end
  end
  return nil
end
-- (kept per step and list generation, like the memos below)
local hubMemo = setmetatable({}, { __mode = "k" })
-- (the plan's spots by cells of Next.HUB_YD, once per list generation and in the solve's slices: each hand-in looked at
-- walked the whole plan, ~3,500 steps, for its neighbours - a ms or two apiece, none of it able to pause)
local hubIdx = setmetatable({}, { __mode = "k" })
local NOSPOTS = {}
local function hubCells(list)
  local R, gen = Next.HUB_YD, list._gen or 0
  local H = hubIdx[list]
  if H and H.gen == gen and H.R == R then return H end
  local cells = {}
  for j, t in ipairs(list) do
    if j % 128 == 0 then ns.MaybeYield() end
    local tw = wpos(t)
    if tw then
      local key = cellKey(math.floor(tw[1] / R), math.floor(tw[2] / R), tw[3])
      local c = cells[key]
      if not c then c = {}; cells[key] = c end
      c[#c + 1] = tw
    end
  end
  H = { gen = gen, R = R, cells = cells }
  hubIdx[list] = H
  return H
end
function isHub(list, s) -- (declared above: passReach)
  local m = hubMemo[s]
  if m ~= nil and m.list == list and m.gen == (list._gen or 0) then return m.hub end
  local w, n = wpos(s), 0
  if w then
    local H = hubCells(list)
    local R = H.R
    local cx, cy = math.floor(w[1] / R), math.floor(w[2] / R)
    for dx = -1, 1 do
      for dy = -1, 1 do
        for _, tw in ipairs(H.cells[cellKey(cx + dx, cy + dy, w[3])] or NOSPOTS) do
          if (tw[1] - w[1]) ^ 2 + (tw[2] - w[2]) ^ 2 <= R ^ 2 then n = n + 1 end
        end
      end
    end
  end
  hubMemo[s] = { list = list, gen = list._gen or 0, hub = n >= Next.HUB_STEPS }
  return n >= Next.HUB_STEPS
end
Next._isHub = isHub
-- does handing this in open a quest whose pick-up is right there (the chain goes on: hand in, take the next)?
local acceptIdx = setmetatable({}, { __mode = "k" })
function chainsOnHere(list, s) -- (declared above: passReach)
  local deps = s.q and BeelineUnlocks and BeelineUnlocks[s.q]
  local w = wpos(s)
  if not (deps and w) then return false end
  -- (per list generation: a pick-up Stitch.Splice inserts counts)
  local idx = acceptIdx[list]
  if not (idx and idx._gen == (list._gen or 0)) then
    idx = { _gen = list._gen or 0 }
    for _, t in ipairs(list) do if t.k == "accept" and t.q and not idx[t.q] then idx[t.q] = t end end
    acceptIdx[list] = idx
  end
  for _, d in ipairs(deps) do
    local a = idx[d]
    local aw = a and wpos(a)
    if aw and aw[3] == w[3] and (aw[1] - w[1]) ^ 2 + (aw[2] - w[2]) ^ 2 <= Next.CHAIN_YD ^ 2 then return true end
  end
  return false
end

-- is a pick-up the plan passed as behind you a candidate at your level L? Not more than 2 levels above you, nor
-- BEHIND_BELOW or more below (gray quests still pay a little, so the price alone would let them in).
-- Shared with tools/replay.js's "behind you" count.
Next.BEHIND_BELOW = 6
function Next.BehindLevelOk(level, L) return tonumber(level) ~= nil and level <= L + 2 and level > L - Next.BEHIND_BELOW end
-- what a quest you'd take up again is worth, in seconds: its XP at your rate, less the work still to do for it (its
-- objective steps: workOf). The plan never comes back for it (it is behind you), so this is its whole prize
-- (Next.Prize). Shared with tools/replay.js's "leaves work" check, so the check and the pick can't disagree.
-- (Engine.QuestXP applies the game's cut for low quests: 80% at 6 levels below down to 10% at 10+.)
-- the cheapest detour (seconds) of fitting place p into the plan's way from its stop `first` on, among the gaps whose
-- walks pass within reach yards of it - walks, and trips already priced (none asked: a guess never sends you) -> or nil
local function wayFit(W, p, first, reach)
  local C = Next.DEFER_CELL
  local r = math.floor((reach + C / 4) / C) + 1
  local cx, cy = math.floor(p[1] / C), math.floor(p[2] / C)
  local best, seen = nil, {}
  for dx = -r, r do
    for dy = -r, r do
      for _, k in ipairs(W.grid[cellKey(cx + dx, cy + dy, p[3])] or {}) do
        if not seen[k] and k >= first then
          seen[k] = true
          local d, near = gapDetour(W, k, W.gaps[k], p, false)
          if d and near <= reach and (not best or d < best) then best = d end
        end
      end
    end
  end
  return best
end
-- The way to a quest's remaining stops from behind you (seconds): its objectives not finished, then its hand-in, from its
-- pick-up s - the cheaper of a tour out from there and back, or each stop fitted into the plan's way from its step
-- `from` on (wayFit). math.huge: neither (a stop off this continent and off the plan's way). Remembered per solve's
-- prices (priceSig) and list generation.
local travelMemo = setmetatable({}, { __mode = "k" })
Next.BEHIND_RISK = 1.5 -- a quest from behind you must pay this many times its estimated work and way (BehindPrize)
Next.BEHIND_FIT_YD = 500 -- yards: a stop of the quest this close to the plan's way is done on the way
local function behindTravel(list, s, from)
  local p0 = wpos(s)
  if not p0 then return nil end
  local W = way(list)
  local key = from .. ":" .. priceSig()
  local m = travelMemo[s]
  if m and m.key == key and m.W == W and m.ver == W.ver then return m.v end
  local c = objWork[list]
  local E = ns.Engine
  local stops = {}
  for _, o in ipairs((c and c.by[s.q]) or {}) do
    local ob = E.ObjectiveFor and E.ObjectiveFor(o.st)
    if not (ob and ob.finished) and wpos(o.st) and not o.st.unknown then stops[#stops + 1] = wpos(o.st) end
  end
  local t = c and c.turn[s.q]
  if t and wpos(t) then stops[#stops + 1] = wpos(t) end
  local lo, hi = 1, #W.stops + 1
  while lo < hi do local mid = math.floor((lo + hi) / 2); if W.stops[mid].j < from then lo = mid + 1 else hi = mid end end
  local tour, at, fit = 0, p0, 0
  for _, w in ipairs(stops) do
    if tour and w[3] == at[3] then tour = tour + yd(at, w) else tour = nil end
    at = w
    if fit then local d = wayFit(W, w, lo, Next.BEHIND_FIT_YD); fit = d and (fit + d) or nil end
  end
  if tour and at[3] == p0[3] then tour = tour + yd(at, p0) else tour = nil end
  local v = math.min(tour and (tour * OFFNET / speedNow()) or huge, fit or huge)
  travelMemo[s] = { key = key, W = W, ver = W.ver, v = v }
  return v
end
function Next.BehindPrize(list, s, L, from)
  local E = ns.Engine
  if not (E.QuestXP and s and s.q and tonumber(s.level)) then return 0 end
  -- (a pick-up the plan's clock prices: the quest's whole bundle there - its stops, work and the way to them, qt - when
  -- that is more than its objectives' work and walks: the plan's bundle is its cost on the plan's way, and a quest
  -- behind you is off it)
  local work = workOf(list, s.q)
  if Next.useClock and s.k == "accept" and tonumber(s.qt) and tonumber(s.qt) > work then work = tonumber(s.qt) end
  -- (and the way to its stops from here, not the plan's walks of long ago: Screecher Spirits, taken up in Tanaris, is
  -- worked in Feralas - priced at its 8 min of planner work and walks, it cost the route 25 min for 17 min of XP)
  if from and s.k == "accept" and Next.rules.behindTravel then
    local tr = behindTravel(list, s, from)
    if tr then
      local secs = 0
      local c = objWork[list]
      for _, o in ipairs((c and c.by[s.q]) or {}) do local ob = E.ObjectiveFor and E.ObjectiveFor(o.st); if not (ob and ob.finished) then secs = secs + o.secs end end
      if secs + tr > work then work = secs + tr end
    end
    -- (and its risk: the work of a quest off the plan's way is the least certain part of a route - an escort that fails, a
    -- drop that won't come, a walk the estimate missed. The pick audit: Get Me
    -- Out of Here!, an escort, 455 s estimated against 666 s of XP, cost the route 23 min)
    work = work * Next.BEHIND_RISK
  end
  return E.QuestXP(s.level, L) / rate() - work
end

-- What doing stop s now is worth, in seconds (see "Now or later" above): the least of what its quest pays and what
-- leaving it costs. from: the plan's step the solve starts at; behind: the plan has passed it for good.
-- What it pays: a hand-in, its XP at your level (a gray one a tenth or so); a pick-up, that less the work of its
-- objectives (Next.BehindPrize); an objective, that less the quest's other objectives. A stop of no quest (a flight
-- path) pays no XP: it is worth the trip back for it, or, when the plan never comes back, the stop and carrying alone.
function Next.Prize(list, s, from, behind)
  -- (one from behind you - a quest you passed, a step below your place for a quest in your log - is left for good at
  -- its own place, but not where the plan's way passes it again and the solve offers it then: a hand-in at a hub the
  -- plan comes back to (DeferCost's behind: its later passes only). Priced as never coming back, three finished
  -- hand-ins at Tarren Mill sent an undead priest across Hillsbrad and back before the plan's own Tarren Mill visit:
  -- 11 min more of the way for 8 min of XP)
  local defer = behind and Next.DeferCost(list, s, from, true) or Next.DeferCost(list, s, from)
  -- (a quest from behind you whose own place is still ahead in the plan - you are ahead of the plan's levels, so it
  -- reads "behind you": the card offers it again as the way passes it, so leaving it costs what DeferCost says, not its
  -- XP. Priced as never coming back, Hemet Nesingwary's pick-up in Thousand Needles came before the plan's hand-in
  -- across the zone: 3.4 min lost on four plans, Premiere Parts in Hyjal 5.2)
  if behind and Next.rules.behindAhead then
    local W = way(list)
    local k = W.at[s]
    if k and W.stops[k].j > from then defer = Next.DeferCost(list, s, from) end
  end
  local E = ns.Engine
  local L = (UnitLevel and UnitLevel("player")) or 1
  local pays
  if s.q then
    if s.k == "accept" then pays = Next.BehindPrize(list, s, L, behind and from or nil)
    else
      local xp = (E.QuestXP and tonumber(s.level)) and E.QuestXP(s.level, L) or tonumber(s.xp) or ((UnitXPMax and UnitXPMax("player") or 10000) * 0.04)
      pays = xp / rate() - (s.k == "obj" and workOf(list, s.q, s) or 0)
    end
  elseif defer == huge then return serviceOf(s) + Next.CARRY
  else return defer end
  return math.min(pays, defer)
end

-- the plan's pick-ups and hand-ins, in order: whole-plan scans use these, not all ~2,500 steps every refresh.
-- Kept per list generation.
local kindsMemo = setmetatable({}, { __mode = "k" })
local function stepsOfKind(list)
  local c = kindsMemo[list]
  if c and c.gen == (list._gen or 0) then return c end
  c = { gen = list._gen or 0, accept = {}, turnin = {} }
  for j, s in ipairs(list) do
    if s.k == "accept" then c.accept[#c.accept + 1] = j elseif s.k == "turnin" then c.turnin[#c.turnin + 1] = j end
  end
  kindsMemo[list] = c
  return c
end
-- the plan's pick-ups with a quest and a level, by where they are: world squares BEHIND_YD on a side, so the scan for
-- pick-ups behind you (gatherExtras) visits the 3 x 3 squares around you - everything within BEHIND_YD - not every
-- pick-up of the plan each solve (~120 of ~950 at level 50). Kept per list generation. also: the card's own pick, which
-- reaches further (BEHIND_KEEP). -> those step numbers, ascending (the order the whole scan had)
local nearMemo = setmetatable({}, { __mode = "k" })
local function acceptsNear(list, px, py, pinst, also)
  local side = Next.BEHIND_YD
  local g = nearMemo[list]
  if not (g and g.gen == (list._gen or 0) and g.side == side) then
    g = { gen = list._gen or 0, side = side, cells = {} }
    for _, j in ipairs(stepsOfKind(list).accept) do
      local s = list[j]
      local w = s.q and tonumber(s.level) and wpos(s)
      if w then
        local key = w[3] .. ":" .. math.floor(w[1] / side) .. ":" .. math.floor(w[2] / side)
        local cell = g.cells[key]; if not cell then cell = {}; g.cells[key] = cell end
        cell[#cell + 1] = j
      end
    end
    nearMemo[list] = g
  end
  local out = {}
  local cx, cy = math.floor(px / side), math.floor(py / side)
  for dx = -1, 1 do
    for dy = -1, 1 do
      local cell = g.cells[pinst .. ":" .. (cx + dx) .. ":" .. (cy + dy)]
      if cell then for k = 1, #cell do out[#out + 1] = cell[k] end end
    end
  end
  local a = also and list[also]
  if a and a.k == "accept" and a.q and tonumber(a.level) then
    local w = wpos(a)
    if w and w[3] == pinst and (math.abs(math.floor(w[1] / side) - cx) > 1 or math.abs(math.floor(w[2] / side) - cy) > 1) then out[#out + 1] = also end
  end
  table.sort(out)
  return out
end
Next._acceptsNear = acceptsNear -- (tests)
-- the first position in idx (ascending step indices) past step j
local function after(idx, j)
  local lo, hi = 1, #idx + 1
  while lo < hi do local mid = math.floor((lo + hi) / 2); if idx[mid] <= j then lo = mid + 1 else hi = mid end end
  return lo
end

local last -- { sig, at, pick, res }
-- the next pick solves afresh, whatever the last one was (/bee report perf times a solve: the dev tools)
function Next.Forget() last = nil end
-- a stop you said "not now" to, while it holds: you are still about where you said it, and not long after
-- (keyed by the step table, not its index: an inserted stop shifts the indices)
local function holds(key, px, py, pinst)
  local d = Next.dismissed[key]
  if not d then return false end
  local now = GetTime and GetTime() or 0
  if now - d.t > Next.DISMISS_SECS or d.inst ~= pinst or (d.x - px) ^ 2 + (d.y - py) ^ 2 > Next.DISMISS_YD ^ 2 then Next.dismissed[key] = nil; return false end
  return true
end
local function isDismissed(j, px, py, pinst)
  local list = BeelineData and BeelineData.steps
  local s = list and list[j]
  return s ~= nil and holds(s, px, py, pinst)
end
Next.IsDismissed = isDismissed
-- -> the step index to show, or nil (the plan's own next step stands)
-- Already where the plan goes after its next trip (you flew on ahead, or rode somewhere yourself): the plan's steps
-- in the zone you're in come first, the trip and what it was for wait (the card comes back to them after).
-- Only past an errand: what the plan does elsewhere before it comes here is at most Next.REJOIN_ERRAND seconds of
-- work. Past a whole zone it is the plan's later visit, not its next (taking it early causes zone ping-pong).
-- -> the first of Next.REJOIN_MIN or more plan steps in a row on your map, within Next.REJOIN_SCAN steps; or nil
Next.REJOIN_SCAN, Next.REJOIN_MIN, Next.REJOIN_ERRAND = 250, 4, 600
function Next.LocalBlock(list, planned, pm)
  local trip = list[planned]
  if not (pm and trip and trip.to and trip.to ~= pm) then return nil end
  local E = ns.Engine
  local j0, n, away = nil, 0, 0
  for j = planned + 1, math.min(#list, planned + Next.REJOIN_SCAN) do
    local s = list[j]
    if Next.KIND[s.k] and s.m then
      local st = E.Status(j)
      if s.m == pm then
        if st == "todo" then
          j0 = j0 or j; n = n + 1
          if n >= Next.REJOIN_MIN then return j0 end
        end
      elseif st ~= "done" then
        if st == "todo" and j0 then j0, n = nil, 0 end -- (a few steps here, then away again: not worth leaving the plan for)
        -- (the plan's own work elsewhere first - waiting ones too, the plan does them on that visit; a stop the route only
        -- took in is a prize, not the plan's way)
        if not s.inserted then
          away = away + ((s.k == "obj" and tonumber(s.work)) or Next.SERVICE[s.k] or 15)
          if away > Next.REJOIN_ERRAND then return nil end
        end
      end
    end
  end
  return nil
end

-- you came into the plan's zone at another spot than its own (the flight path you know, a road from the next zone):
-- its next step is far off, and Next.REJOIN_MIN or more of its own later steps, before its next trip, are right around
-- you (the solve alone won't jump there: each step a pick passes over costs Horizon.STABILITY).
-- -> the first of them, or nil
function Next.HereBlock(list, planned, px, py, pinst)
  local s0 = list[planned]
  if not (px and s0 and s0.m) then return nil end
  local function near(s, yd) local w = wpos(s); return w and w[3] == pinst and (w[1] - px) ^ 2 + (w[2] - py) ^ 2 <= yd ^ 2 end
  if near(s0, Next.HERE_FAR) then return nil end
  -- (only when you just came in: the plan's next step is the first of a visit, right after its trip there - not when you
  -- walk back to a town mid-visit, with full bags: its later steps there wait for the plan)
  local arrived = false
  for j = planned - 1, math.max(1, planned - 3), -1 do
    local t = list[j]
    if isTrip(t) then arrived = true; break end
    if t.q and t.q > 0 then break end
  end
  if not arrived then return nil end
  local E = ns.Engine
  local j0, n = nil, 0
  for j = planned + 1, math.min(#list, planned + Next.REJOIN_SCAN) do
    local s = list[j]
    if isTrip(s) then break end
    if Next.KIND[s.k] and s.m and E.Status(j) == "todo" and near(s, Next.HERE_YD) then
      j0 = j0 or j; n = n + 1
      if n >= Next.REJOIN_MIN then return j0 end
    end
  end
  return nil
end

-- Does quest q start a chain for this zone: does it open (BeelineUnlocks) a quest with steps on your route in the
-- map or zone given? (a pick-up just over the border whose follow-ups are here may take you out of the zone - Next's
-- leavesZone). The quests per map are indexed once per route, not walked per solve.
local zoneIdx = { list = nil, gen = 0, byQ = nil }
function Next.ChainsInto(q, map, zone)
  local deps = q and BeelineUnlocks and BeelineUnlocks[q]
  if not deps or #deps == 0 or not (map or zone) then return false end
  local list = BeelineData and BeelineData.steps
  if not list then return false end
  if zoneIdx.list ~= list or zoneIdx.gen ~= (list._gen or 0) then
    local byQ = {}
    for _, t in ipairs(list) do
      if t.q and t.q > 0 and (t.m or t.zone) then
        local e = byQ[t.q]; if not e then e = {}; byQ[t.q] = e end
        if t.m then e[t.m] = true end
        if t.zone then e[t.zone] = true end
      end
    end
    zoneIdx.list, zoneIdx.gen, zoneIdx.byQ = list, list._gen or 0, byQ
  end
  for _, d in ipairs(deps) do
    local e = zoneIdx.byQ[d]
    if e and ((map and e[map]) or (zone and e[zone])) and not (ns.State.IsCompleted and ns.State.IsCompleted(d)) then return true end
  end
  return false
end

-- A pick-up of this town (step j) left behind as the card's step i takes you out: does a player feel it? -> needed, why
--   on your way out: its giver within Next.PF_WALK_YD of the straight way from you to step i - you walk past it (as
--   tools/feel.js's walk-past);
--   a return: no later step of this visit (until the plan's next flight, hearth or boat) comes within Next.HERE_YD of
--   it - the plan would send you back here for it.
-- Otherwise it is picked up later, passing back through town: no need to stop now. Shared with replay.js's HEADS-OUT
-- (Moments.HeadsOutKind), so the card's rule and the check agree.
Next.PF_WALK_YD = 40
function Next.TownPickupNeeded(i, j, planned)
  local E = ns.Engine
  local list = BeelineData and BeelineData.steps
  local s, t = i and list and list[i], j and list and list[j]
  if not (s and t) then return true, "no step" end
  local tw = wpos(t)
  if not tw then return true, "no place for the pick-up" end
  local px, py, pinst = HBD:GetPlayerWorldPosition()
  local sw = not s.unknown and wpos(s)
  if px and sw and sw[3] == pinst and tw[3] == pinst and ns.Travel and ns.Travel.SegDist
    and ns.Travel.SegDist(tw[1], tw[2], { px, py, pinst }, sw) <= Next.PF_WALK_YD then
    return true, "its giver is on your way out"
  end
  -- (a pick-up taken later needs a log slot then: with one left, the plan's next pick-up takes it first)
  local St = ns.State
  if St.LogCount and St.MaxLog and St.LogCount() >= St.MaxLog() - 1 then return true, "one log slot left: it is this pick-up's now" end
  local from = planned or E.planned or i
  for k = from, math.min(#list, from + 60) do
    local u = list[k]
    if isTrip(u) then break end
    if k ~= j and k ~= i and E.Status(k) ~= "done" and not u.unknown then
      local uw = wpos(u)
      if uw and uw[3] == tw[3] and (uw[1] - tw[1]) ^ 2 + (uw[2] - tw[2]) ^ 2 <= Next.HERE_YD ^ 2 then
        return false, "picked up later on the way: no return (the plan is back here for step " .. k .. ")"
      end
    end
  end
  return true, "the plan sends you back here for it"
end

-- Pick-ups before heading out: a quest taken now is worked on the same trip out. When the card's pick takes you away
-- (beyond Next.HERE_YD, or to work with no known spot), the quests the plan picks up in this town before its next trip -
-- offered now, givers within Next.HERE_YD of you - come first, nearest first. -> that pick-up, or nil
-- fits(j) (optional): the pick-up has a log slot - the solve's window holds it, or room is left past the window's own
-- (a giver with no slot is no must-stop).
function Next.PickupFirst(list, planned, pick, px, py, pinst, fits)
  if not (px and list and planned and list[planned]) then return nil end
  local E = ns.Engine
  local function d2(s) local w = wpos(s); return w and w[3] == pinst and (w[1] - px) ^ 2 + (w[2] - py) ^ 2 or nil end
  local p = pick and list[pick]
  if p and p.k == "accept" then return nil end
  local pd = p and d2(p)
  if p and pd and pd <= Next.HERE_YD ^ 2 then return nil end -- (the card's stop is right here: no heading out yet)
  local best, bd
  for j = planned, math.min(#list, planned + Next.REJOIN_SCAN) do
    local s = list[j]
    if isTrip(s) then break end
    -- (this visit only: a step with a known spot beyond Next.HERE_FAR ends it; a later visit here waits)
    if j > planned and s.m and not s.unknown then local dd = d2(s); if not dd or dd > Next.HERE_FAR ^ 2 then break end end
    if s.k == "accept" and s.q and E.Status(j) == "todo" and (not E.Available or E.Available(j)) and not (ns.Nope and ns.Nope(s.q))
      and not (E.Outlevelled and E.Outlevelled(s)) and (not fits or fits(j)) and not Next.GiverOff(s)
      -- (only one you'd walk past or come back for: picked up later passing back through town, it needn't come first -
      -- the pick audit found the town pick-up first lost time, kept for these it finds what a player feels)
      and Next.TownPickupNeeded(pick or planned, j, planned) then
      local dd = d2(s)
      if dd and dd <= Next.HERE_YD ^ 2 and (not bd or dd < bd) then best, bd = j, dd end
    end
  end
  return best
end

-- The solve's pick, in phases over one solve's state c: candidates (the stop list and add), gatherWindow (the plan's
-- next stops), gatherExtras (quests behind you, below the floor, early hand-ins, a later visit, vendors), setNeeds,
-- trimStops, solveStops (the order) and choosePick (what goes on the card). c: { E, St, list, planned, px, py, pinst,
-- here, load, cap, roomInLog, sig, now, holdPlanned, holdAt, stops, byStep, add, leavesZone, count, scanEnd, wload, ... }

-- the stops and the one way into them, add(j, extra) -> the stop, or nil (not one now)
-- a pick-up from a giver the card must not send you to now (Avail.GiverOff: unfriendly to you, or you said they have
-- nothing for you at this level): never an extra, nor taken before the plan's own step
local function giverOff(s) return s.k == "accept" and s.npc ~= nil and ns.Avail ~= nil and ns.Avail.GiverOff ~= nil and ns.Avail.GiverOff(s.npc) end
Next.GiverOff = giverOff
local function candidates(c)
  local E, list, planned, px, py, pinst = c.E, c.list, c.planned, c.px, c.py, c.pinst
  local byStep = {}
  -- Staying in your zone: an extra - a quest behind you, an early hand-in, a stop added to the route - never takes you
  -- out of the zone you are in while your path still has steps here, unless its quest starts a chain for this zone.
  -- The plan's own trips to its next zone are not extras: they go as planned.
  local myMap = c.here[1]
  local myZone = myMap and ns.Util and ns.Util.MapName and ns.Util.MapName(myMap)
  local function inMyZone(s)
    if not myMap or not s.m then return true end
    return s.m == myMap or (s.zone ~= nil and s.zone == myZone)
  end
  local moreHere -- (lazy) your path has a step to do in this zone, from the plan's step on
  local function pathHasMoreHere()
    if moreHere == nil then
      moreHere = false
      for j = planned, math.min(#list, planned + Next.SCAN) do
        local t = list[j]
        if t.m and inMyZone(t) and E.Status(j) == "todo" then moreHere = true; break end
      end
    end
    return moreHere
  end
  -- (the map the plan goes on in: its next own step to do with a place - where its trip takes you, when its next step
  -- is one)
  local nextMap
  local function planMap()
    if nextMap == nil then
      nextMap = false
      for j = planned, math.min(#list, planned + Next.SCAN) do
        local t = list[j]
        if t.m and not t.inserted and not t.unknown and E.Status(j) == "todo" then nextMap = t.m; break end
      end
    end
    return nextMap
  end
  local function leavesZone(s)
    if inMyZone(s) or not pathHasMoreHere() then return false end
    -- (where the plan itself goes next is no leaving: from Stormwind, the flight path at Sentinel Hill the route took in
    -- for the plan's trip to Westfall was never weighed, and the card rode past it to Agent Kearnen in the far corner)
    if s.m and s.m == planMap() then return false end
    return not Next.ChainsInto(s.q, myMap, myZone)
  end
  local function add(j, extra)
    -- (a stop you said "not now" to stays out while you're still here: a plan step waits for its own place in the plan)
    if extra and extra.opt and isDismissed(j, px, py, pinst) then return nil end
    if extra and extra.opt and leavesZone(list[j]) then return nil end
    local s = list[j]
    local w = wpos(s)
    -- (an objective takes the planner's expected s.work; the flat guess only when a step lacks it)
    local service = (s.k == "obj" and tonumber(s.work)) or Next.SERVICE[s.k] or 15
    local stop = { id = j, step = j, st = s, w = w, m = s.m, x = s.x, y = s.y, service = service,
      load = (s.k == "accept" and 1) or (s.k == "turnin" and -1) or 0 }
    for k, v in pairs(extra or {}) do stop[k] = v end
    local stops = c.stops -- (the list trimStops left: what is added later goes there)
    stops[#stops + 1] = stop; byStep[j] = stop
    return stop
  end
  c.stops, c.byStep, c.add, c.leavesZone = {}, byStep, add, leavesZone
end

-- the plan's next stops you can do now (a step that isn't a place - grind to a level, a note - ends the window there:
-- it is done where it stands in the plan)
local function gatherWindow(c)
  local E, list, planned, px, py, pinst, add, cap = c.E, c.list, c.planned, c.px, c.py, c.pinst, c.add, c.cap
  local holdPlanned, holdAt, count, scanEnd = c.holdPlanned, c.holdAt, 0, planned
  -- (you're already where the plan goes after this trip: start from there - see Next.LocalBlock)
  local from = planned
  Next.rejoin = nil
  if c.onTrip then
    local j0 = Next.rules.localBlock and Next.LocalBlock(list, planned, c.here[1])
    if j0 and Next.useClock and Next.RejoinLoses(list, planned, j0, { w = { px, py, pinst }, m = c.here[1], x = c.here[2], y = c.here[3] }) then j0 = nil end
    if j0 then from = j0; holdPlanned, holdAt = false, nil; Next.rejoin = { at = j0, trip = planned } end
  elseif px then
    local j0 = Next.rules.hereBlock and Next.HereBlock(list, planned, px, py, pinst)
    if j0 then from = j0; Next.rejoin = { at = j0, wait = planned } end
  end
  -- (the log as the window fills it, in plan order: a pick-up past the room left ends the window like a full log, so
  -- the window always has one feasible order - the plan's own; otherwise the solve can be infeasible)
  -- (and one slot reserved for a pick-up of this town before you head out, Next.PickupFirst - until the window takes
  -- a pick-up here itself: then that one goes first, below)
  local pfAny = c.roomInLog and Next.rules.pickupFirst and Next.PickupFirst(list, planned, planned, px, py, pinst)
  local reserve = pfAny and 1 or 0
  local hereYd2 = Next.HERE_YD ^ 2
  local wload = c.load
  local inWin, byStep = {}, c.byStep -- (quests the window picks up: their work and hand-in come in too, below)
  local function allObjsIn(q, before)
    for _, o in ipairs(E.ObjStepsOf(q)) do
      if o < before and not byStep[o] and E.Status(o) ~= "done" then return false end
    end
    return true
  end
  for j = from, math.min(#list, from + Next.SCAN) do
    if j % 8 == 0 then ns.MaybeYield() end
    local s = list[j]
    -- (the trip the plan holds at, Engine.Compute - quests here wait for your level or log room: the window ends there
    -- so the solve can't fly you past the hold)
    if s == E.levelHold then break end
    local st = E.Status(j)
    scanEnd = j
    -- the work and the hand-in of a quest the window picks up: not doable yet ("blocked": not in your log), but the
    -- plan's stops all the same, after their pick-up (setNeeds). Left out, the window
    -- saw only pick-ups, and flying away from them looked free: from Searing Gorge the Blasted Lands' pick-ups came
    -- before the Hinterlands' (the plan's next zone), then the Hinterlands, then back to the Blasted Lands for the work.
    -- (a hand-in only once every objective of its quest left to do is in the window: never one that can't be done)
    if st == "blocked" and s.q and inWin[s.q] and not s.inserted and wpos(s) and not s.unknown
      and ((s.k == "obj" and not E.InsideOf(s)) or (s.k == "turnin" and allObjsIn(s.q, j))) then
      add(j, { plan = j })
      if s.k == "turnin" then wload = wload - 1 end
      count = count + 1
      if count >= Next.WINDOW then break end
    elseif st == "todo" and j ~= planned and giverOff(s) then
      -- (a pick-up from a giver who won't talk to you, or has nothing for you now: passed over, never taken early - the plan's
      -- own step there still shows, and its "nothing for you" then judges the rest)
    elseif st == "todo" then
      -- (a pick-up whose earlier chain quest isn't handed in is not offered yet: it waits where the plan has it)
      if Next.KIND[s.k] and wpos(s) and (s.k ~= "accept" or ((not E.Available or E.Available(j)) and wload + ((j == pfAny) and 0 or reserve) < cap)) then
        -- (a slot is freed only by a plan hand-in: an inserted one is a prize the solve may leave)
        if s.k == "accept" and reserve > 0 then
          local w = wpos(s)
          if j == pfAny or (w[3] == pinst and (w[1] - px) ^ 2 + (w[2] - py) ^ 2 <= hereYd2) then reserve = 0 end
        end
        if s.k == "accept" then wload = wload + 1 elseif s.k == "turnin" and not s.inserted then wload = wload - 1 end
        -- an off-plan stop the route only took in (a finished quest's hand-in, a side quest's objective): a prize, not a
        -- must (Next.Prize: worth the trip back it saves, or its XP when the plan never passes again).
        if s.inserted then
          add(j, { prize = Next.Prize(list, s, planned), opt = true })
        elseif Next.taken == s and not (E.BehindYou and E.BehindYou(s)) then
          -- the quest from behind you the card shows (Next.taken): it is "to do" only because the card took it - still a
          -- prize, as it was before the card took it. As a must here it lost its prize while every other quest from behind
          -- kept theirs: whichever wasn't on the card looked better, and the card flipped between two of them at every
          -- step you walked (Anything of Value <-> The Cook in the Cage, Stranglethorn)
          add(j, { prize = Next.Prize(list, s, planned, true), opt = true, behind = true })
        else
          add(j, { plan = j })
          if s.q and s.k == "accept" then inWin[s.q] = true end
          count = count + 1
        end
        if count >= Next.WINDOW then break end
      elseif isTrip(s) then
        if count == 0 and not holdAt then holdAt = j end -- (the trip comes before any stop: it's what's next)
      else
        -- (a grind, a note, a dungeon run - a step with no place first: it stays the plan's step, unless a prize close by
        -- is worth doing before it - a quest worth XP right here beats grinding)
        if count == 0 then holdPlanned = true; holdAt = holdAt or j end
        break
      end
    elseif st == "wait" and E.WaitsForHandIn(s) then
      -- (a pick-up waiting for a quest in your log to be handed in: not offered yet, it ends the window)
      if count == 0 then holdPlanned = true; holdAt = holdAt or j end
      break
    end
  end
  c.holdPlanned, c.holdAt, c.count, c.scanEnd, c.wload, c.from = holdPlanned, holdAt, count, scanEnd, wload, from
end

-- the extras: prizes the solve may take on the way
local function gatherExtras(c)
  local E, St, list, planned, px, py, pinst, add, byStep, leavesZone = c.E, c.St, c.list, c.planned, c.px, c.py, c.pinst, c.add, c.byStep, c.leavesZone
  -- quests the built-in plan passed as behind you (you joined it further on) that are right here and still worth XP at
  -- your level: the plan never comes back for them, so a pick-up is worth its XP at your rate, less the work still to
  -- do for it (Next.Prize, Next.BehindPrize). Once taken, its objectives and hand-in come back to the route by
  -- themselves (a quest in your log is never behind you). In your zone only (leavesZone).
  if E.BehindYou and E.QuestXP and Next.rules.behind then
    local L = (UnitLevel and UnitLevel("player")) or 1
    -- (the nearest Next.BEHIND_MAX within Next.BEHIND_YD; level bounds: Next.BehindLevelOk, the price decides the rest)
    local found = {}
    -- (only those near enough to be one: acceptsNear)
    local accepts = c.roomInLog and pinst and acceptsNear(list, px, py, pinst, last and last.pick) or {}
    for x = 1, #accepts do
      ns.MaybeYield()
      local j = accepts[x]
      local s = list[j]
      if s.q and tonumber(s.level) and Next.BehindLevelOk(s.level, L) and not byStep[j] then
        local w = wpos(s)
        local d2 = w and w[3] == pinst and (w[1] - px) ^ 2 + (w[2] - py) ^ 2
        -- (the one on the card reaches further, Next.BEHIND_KEEP: no flipping at the edge)
        local reach = (last and last.pick == j) and Next.BEHIND_YD * Next.BEHIND_KEEP or Next.BEHIND_YD
        -- (and not outlevelled, Engine.Outlevelled: a gray pick-up that leads nowhere is no extra)
        if d2 and d2 <= reach ^ 2 and not leavesZone(s) and not St.OnQuest(s.q) and not St.IsCompleted(s.q) and not (E.Outlevelled and E.Outlevelled(s)) then
          local prize = Next.Prize(list, s, planned, true)
          -- (or the one the card took, Next.taken: taking it makes BehindYou false, which would drop it from its own
          -- candidates; and only one that taking makes a step to do, Engine.TodoIfTaken - e.g. not a spent breadcrumb)
          if prize > 0 and (E.BehindYou(s) or Next.taken == s) and (not E.Available or E.Available(j)) and not (ns.Nope(s.q)) and not giverOff(s)
            and (not E.TodoIfTaken or E.TodoIfTaken(j)) then
            found[#found + 1] = { j = j, d2 = d2, prize = prize }
          end
        end
      end
    end
    table.sort(found, function(a, b) return a.d2 < b.d2 end)
    for k = 1, math.min(Next.BEHIND_MAX, #found) do add(found[k].j, { prize = found[k].prize, opt = true, behind = true }) end
    -- (and the one on the card while it still qualifies, even if no longer among the nearest: the margin needs it)
    if last and last.pick and not byStep[last.pick] then
      for _, fd in ipairs(found) do if fd.j == last.pick then add(fd.j, { prize = fd.prize, opt = true, behind = true }); break end end
    end
  end
  -- the steps below your place in the plan for quests in your log (Engine.BelowFloor: one you took up again from the
  -- part you passed): extras, close by and worth it - they don't pull your place back
  if E.BelowFloor and Next.rules.belowFloor then
    for _, j in ipairs(E.BelowFloor(planned, 12)) do
      local s = list[j]
      if not byStep[j] then
        local w = wpos(s)
        local reach = (last and last.pick == j) and Next.BEHIND_YD * Next.BEHIND_KEEP or Next.BEHIND_YD
        if w and w[3] == pinst and (w[1] - px) ^ 2 + (w[2] - py) ^ 2 <= reach ^ 2 and not leavesZone(s) then
          local prize = Next.Prize(list, s, planned, true)
          if prize > 0 then add(j, { prize = prize, opt = true, behind = true }) end
        end
      end
    end
  end
  -- finished quests whose hand-in is further on in the plan but near you now: a prize worth the trip back it saves
  -- (Next.Prize). Next.NEAR_READY only bounds the candidates: the price decides.
  local turnins = stepsOfKind(list).turnin
  for x = after(turnins, c.scanEnd), #turnins do
    ns.MaybeYield()
    local j = turnins[x]
    local s = list[j]
    if s.q and St.QuestReady(s.q) and not byStep[j] then
      local w = wpos(s)
      if w and w[3] == pinst and (w[1] - px) ^ 2 + (w[2] - py) ^ 2 <= Next.NEAR_READY ^ 2 and E.Status(j) == "todo"
        and (isHub(list, s) or chainsOnHere(list, s)) then
        add(j, { prize = Next.Prize(list, s, planned), opt = true, early = true, chain = not isHub(list, s) or nil })
      end
    end
  end
  -- a later visit the plan makes to where you are now, all of which you can do now: done now, the trip back for it
  -- goes (a trip to steps that are all done is passed - Engine statusRaw). Worth that trip (Next.VisitHere)
  local visit = Next.rules.visitHere and Next.VisitHere(list, planned, planned + 1, c.here[1], px, py, pinst)
  if visit then
    local share = visit.saves / #visit.now
    for _, j in ipairs(visit.now) do
      -- (one of the plan's own next stops already: it may now come before the trip - not one you said "not now" to)
      if byStep[j] then if not isDismissed(j, px, py, pinst) then byStep[j].visit, byStep[j].early = true, true end
      else
        -- (left for the plan's visit it costs the stop, carrying it, and its share of the trip there - the visit's way in
        -- and out is the trip, so it isn't priced again as a detour of its own; its XP isn't at stake: the visit does it)
        add(j, { prize = serviceOf(list[j]) + Next.CARRY + share, opt = true, early = true, visit = true })
      end
    end
  end
  -- your bags filling up: the vendors of this map as prizes, worth more the closer you are to
  -- looting nothing - the solve fits the visit in where it costs least (a town you pass anyway), and the card's errand
  -- line says which vendor and when (Errands.lua)
  Next.vendor = nil
  local stops = c.stops
  local E2 = ns.Errands
  local free = E2 and E2.FreeSlots and E2.FreeSlots()
  local bagPrize = free and Next.BAG_PRIZE[math.max(0, free)] or 0
  local vm = c.here and c.here[1]
  if bagPrize > 0 and vm and ns.VENDORS and ns.VENDORS[vm] then
    local near = {}
    for vi, v in ipairs(ns.VENDORS[vm]) do
      local vx, vy, vinst = HBD:GetWorldCoordinatesFromZone(v[1], v[2], vm)
      if vx and vinst == pinst then near[#near + 1] = { vi = vi, v = v, d = (vx - px) ^ 2 + (vy - py) ^ 2, w = { vx, vy, vinst } } end
    end
    table.sort(near, function(a, b) return a.d < b.d end)
    for k = 1, math.min(3, #near) do
      local n = near[k]
      stops[#stops + 1] = { id = "vendor" .. n.vi, vendor = n.v, w = n.w, m = vm, x = n.v[1], y = n.v[2], service = 25, load = 0, prize = bagPrize, opt = true }
    end
  end
end

-- pick-up before objectives before hand-in, among the stops in the window
local function setNeeds(stops, list)
  local acceptOf, objsOf = {}, {}
  for _, st in ipairs(stops) do
    local s = st.step and list[st.step] -- (a vendor is no step of the plan)
    if s and s.q then
      if s.k == "accept" then acceptOf[s.q] = st.id
      elseif s.k == "obj" then objsOf[s.q] = objsOf[s.q] or {}; table.insert(objsOf[s.q], st.id) end
    end
  end
  for _, st in ipairs(stops) do
    local s = st.step and list[st.step]
    if s and s.q and (s.k == "obj" or s.k == "turnin") then
      local needs = {}
      if acceptOf[s.q] then needs[#needs + 1] = acceptOf[s.q] end
      if s.k == "turnin" then for _, o in ipairs(objsOf[s.q] or {}) do needs[#needs + 1] = o end end
      st.needs = needs
    end
  end
end

-- (at most Horizon.MAX_CANDIDATES: the planned stops and the card's pick, then the highest prizes - Horizon.Trim)
local function trimStops(c)
  if #c.stops > ns.Horizon.MAX_CANDIDATES then
    c.stops = ns.Horizon.Trim(c.stops, ns.Horizon.MAX_CANDIDATES, last and last.pick)
    local kept = {}
    for _, st in ipairs(c.stops) do kept[st] = true end
    for j, st in pairs(c.byStep) do if not kept[st] then c.byStep[j] = nil end end
  end
end

-- the plan's own step stands - unless it's a stop the route only took in (the solve didn't think it worth it) or isn't
-- one you can do now (a hand-in not finished yet): then the step that holds (the trip, the grind), or the plan's next
-- one you can do
local function keepPlanned(c)
  local list, planned, E = c.list, c.planned, c.E
  Next.taken = nil -- (back on the plan's step: no quest from behind you on the card)
  -- (a hand-in you can't do yet stays: the card says what it needs - "Not finished" with the objective bars)
  if list[planned].inserted then
    local alt = c.holdAt
    if not alt then for j = planned + 1, math.min(#list, planned + Next.SCAN) do if not list[j].inserted and E.Status(j) == "todo" then alt = j; break end end end
    return alt
  end
  return nil
end
-- (a vendor isn't a step of the plan: the card shows the plan's next step and its errand line says the vendor - now,
-- or after the stops before it)
local function firstStep(r)
  local first, fs
  -- (the plan's way goes on at a step the window left out: its own step stands - Horizon's hold)
  if r.hold then return nil end
  for k, s in ipairs(r.seq or {}) do
    if s.vendor and not Next.vendor then Next.vendor = { v = s.vendor, before = k - 1 } end
    if s.step and not first then first, fs = s.step, s end
  end
  return first, fs
end

-- The plan's clock (tools/plan-clock.js writes dt, dd and qt into a built-in plan's steps): the plan's time from any of
-- its steps to any later one, summed per list generation (an inserted stop has none: it is no part of the plan's time).
-- Next.useClock = false: the window's own plan-order tail, as before (and for a plan without the clock).
Next.useClock = true
local clockMemo = setmetatable({}, { __mode = "k" })
local function clockSums(list)
  local m = clockMemo[list]
  if m and m.gen == (list._gen or 0) then return m.S end
  local S = { [0] = 0 }
  for j = 1, #list do S[j] = S[j - 1] + (tonumber(list[j].dt) or 0) end
  clockMemo[list] = { gen = list._gen or 0, S = S }
  return S
end
-- what taking step s out of the plan saves: its detour there (dd) and the stop itself; a step with no place, its work
local function saveOf(s)
  if not tonumber(s.dt) or isTrip(s) then return 0 end
  if s.unknown or not wpos(s) then return tonumber(s.dt) or 0 end
  return (tonumber(s.dd) or 0) + serviceOf(s)
end
-- Already where the plan comes back to after its next trip (Next.LocalBlock: its next step is a trip, then an errand
-- elsewhere, then steps right here): is doing the steps here first, then the trip and the errand, really shorter by
-- the plan's clock? Both ways end where the plan goes on after the steps here (jn):
--   the plan's:  to the trip's first stop (k1), then the plan's own time from there to jn (the errand, the way back here,
--                the steps here, on to jn)
--   here first:  the steps here (j0 .. jend), the way to k1, the errand (k1 .. ep), and from its end straight on to jn
-- A step of this visit that waits on the errand (its quest is picked up, worked or handed in there, or a pick-up whose
-- earlier quest is handed in there) can't come first: the plan comes back here for it anyway, so the trip back stays,
-- and doing the rest now saves only what each of those stops costs the plan where it has them (dd and the stop):
--   here first:  the steps here that don't wait (A), the way to k1, then the plan's own time from k1 to jn less A's saves
-- So does a step of the visit you can't do now (it waits for your level, a log slot or its quest, which isn't picked
-- up here): the plan comes back for it, and the visit's steps before the one you'd start at are in the plan's way too.
-- (Troll shaman at 21, two levels behind: Jin'Zil's and the Bloodfury quests, red to you, wait in Stonetalon; Cenarius'
-- Legacy before the trip to Ashenvale was priced as the whole visit done now, and those red steps' 22 min of work as
-- gone from the trip back - here first looked 13 min shorter and lost 8.5.)
-- A step already done is in neither: the visit here ends at its last step not done, and the plan's time between two
-- steps leaves out what each done step between them took (its detour and the stop: saveOf), as the solve's clock does.
-- (Orc warrior at 10: The New Horde, handed in, ended the Sen'jin visit in the Valley of Trials - its walk and the trip
-- on from there were counted, and the hand-ins before the Far Watch errand looked 55 s shorter; they lost 180.)
-- (Shen'dralas > Desolace > Shen'dralas: Fragments of the Pylons is picked up in Shen'dralas and worked in Desolace;
-- priced as done before the trip, the Desolace block first looked 6 min shorter and lost 31.)
-- -> true when here-first is no shorter (the plan's trip stands); false when it is, or the plan has no clock there
function Next.RejoinLoses(list, planned, j0, here)
  local E = ns.Engine
  local function located(j) local s = list[j]; return s and not isTrip(s) and not s.unknown and wpos(s) ~= nil end
  local function nextLoc(a, b) for j = a, math.min(#list, b) do if located(j) and E.Status(j) ~= "done" then return j end end end
  local k1 = nextLoc(planned + 1, j0 - 1)
  if not k1 then return false end
  local m, jend = list[j0].m, j0
  for j = j0 + 1, math.min(#list, j0 + Next.REJOIN_SCAN) do local s = list[j]; if isTrip(s) or (s.m and s.m ~= m) then break end; if E.Status(j) ~= "done" then jend = j end end
  local jn = nextLoc(jend + 1, jend + 40)
  local ep
  -- (the errand's end: the plan's last stop elsewhere before it comes back here - not one of this visit's done steps)
  for j = j0 - 1, k1, -1 do if located(j) and list[j].m ~= m then ep = j; break end end
  if not (jn and ep) then return false end
  -- (quests the errand moves on: a step of theirs from the trip to the errand's end, not done)
  local errandQ = {}
  for j = planned + 1, ep do local s = list[j]; if s.q and Next.KIND[s.k] and E.Status(j) ~= "done" then errandQ[s.q] = true end end
  -- (pick-ups of this visit you can take now: a quest not in your log is worked here once one of them takes it)
  local takeHere = {}
  for j = ep + 1, jend do local s = list[j]; if s.k == "accept" and s.q and E.Status(j) == "todo" then takeHere[s.q] = true end end
  local function waits(j)
    local s = list[j]
    if not (s.q and Next.KIND[s.k]) then return false end
    local st = E.Status(j)
    if st == "done" then return false end
    -- (a step you can't do now - red to you or below its level, a full log, a dungeon left for later, a quest not
    -- taken here - waits for the plan's own visit: it comes back here for it)
    if st == "wait" or st == "full" or st == "later" or (st == "blocked" and not takeHere[s.q]) then return true end
    if errandQ[s.q] then return true end
    if s.k == "accept" and E.PrereqsOf then for _, x in ipairs(E.PrereqsOf(s.q) or {}) do if errandQ[x] then return true end end end
    return false
  end
  local back = false -- (a step of this visit waits on the errand: the plan comes back here anyway)
  for j = ep + 1, jend do if waits(j) then back = true; break end end
  for _, j in ipairs({ k1, j0, jend, ep, jn }) do if not tonumber(list[j].dt) then return false end end
  local S = clockSums(list)
  local function at(j) local s = list[j]; return { w = wpos(s), st = s, m = s.m, x = s.x, y = s.y } end
  local function span(a, b) -- (the plan's time from step a to step b, less the done steps between)
    local t = S[b] - S[a]
    for j = a + 1, b - 1 do if E.Status(j) == "done" then t = t - saveOf(list[j]) end end
    return t
  end
  local plan = travelSecs(here, at(k1)) + serviceOf(list[k1]) + span(k1, jn)
  local first
  if back then
    -- (the steps here first: j0, then each of the others at its own detour from the way on to k1; the plan from k1 on
    -- without them)
    local saved, walk = saveOf(list[j0]), 0
    for j = j0 + 1, jend do
      if located(j) and E.Status(j) == "todo" and not waits(j) then local v = saveOf(list[j]); saved = saved + v; walk = walk + v end
    end
    first = travelSecs(here, at(j0)) + serviceOf(list[j0]) + walk + travelSecs(at(j0), at(k1)) + serviceOf(list[k1]) + span(k1, jn) - saved
  else
    first = travelSecs(here, at(j0)) + serviceOf(list[j0]) + span(j0, jend) + travelSecs(at(jend), at(k1)) + serviceOf(list[k1])
      + span(k1, ep) + travelSecs(at(ep), at(jn)) + serviceOf(list[jn])
  end
  if ns.Why then ns.Why("next", string.format("rejoin at step %d before the trip: %.0f s here first, %.0f s the plan's way%s", j0, first, plan, back and " (a step here waits on the trip: the plan comes back)" or "")) end
  return first >= plan
end

-- The solve's view of the plan past the window (Horizon's P.clock): for each planned stop of the window, the plan's
-- time from it to the anchor (R) less what the plan won't do in between (steps done, a quest's work whose pick-up isn't
-- coming), and what doing it out of order saves the plan (save); and the first step from the window's start on that the
-- window left out and the plan will do (ex: the plan rejoins there when it comes first). nil: no clock (a plan without
-- one, an inserted planned stop, no anchor).
local function clockFor(c, anchor)
  if not anchor then return nil end
  local E, list, byStep = c.E, c.list, c.byStep
  local A = anchor.j
  if not tonumber(list[A].dt) then return nil end
  local lo = c.from or c.planned
  for _, st in ipairs(c.stops) do
    if st.plan then
      if not tonumber(list[st.plan].dt) or st.plan >= A then return nil end
      if st.plan < lo then lo = st.plan end
    end
  end
  local S = clockSums(list)
  -- forward: which steps the plan will do (their pick-up is coming, their objectives are) and which it won't
  local dead, acceptAhead, objAhead, ex = {}, {}, {}, nil
  for j = lo, A - 1 do
    local s = list[j]
    local st = byStep[j]
    if st and st.plan then
      if s.q and s.k == "accept" then acceptAhead[s.q] = true elseif s.q and s.k == "obj" then objAhead[s.q] = true end
    elseif s.inserted then dead[j] = true -- (a stop the route took in: a prize, never the plan's time)
    elseif st then -- (a plan step the solve may take early as a prize: its price is what it saves here - no rejoin point)
    elseif not isTrip(s) then -- (a trip's time is on the stop it leads to)
      local stat = E.Status(j)
      local will
      if stat == "done" or stat == "later" then will = false
      elseif stat == "blocked" then will = (s.q and acceptAhead[s.q]) or false
      elseif stat == "notready" then will = (s.q and objAhead[s.q]) or false
      else will = true end
      if not will then dead[j] = true
      else
        if s.q and s.k == "accept" then acceptAhead[s.q] = true elseif s.q and s.k == "obj" then objAhead[s.q] = true end
        if not ex and not s.unknown and wpos(s) then ex = j end
      end
    end
  end
  -- backward: the plan's time from each step to the anchor, less the steps it won't do in between
  local R, D = {}, 0
  for j = A - 1, lo, -1 do
    R[j] = S[A] - S[j] - D
    if dead[j] then D = D + saveOf(list[j]) end
  end
  for _, st in ipairs(c.stops) do
    if st.plan then st.R = R[st.plan]; st.save = (tonumber(list[st.plan].dd) or 0) + (st.service or 0) end
  end
  local out = { anchorService = serviceOf(list[A]) }
  if ex then
    local s = list[ex]
    out.ex = { w = wpos(s), st = s, m = s.m, x = s.x, y = s.y, plan = ex, R = R[ex], service = serviceOf(s) }
  end
  return out
end

-- the order of the stops -> true when there is one to solve (c.P, c.res, c.pick, c.pst)
local function solveStops(c)
  local E, list, scanEnd, px, py, pinst = c.E, c.list, c.scanEnd, c.px, c.py, c.pinst
  -- the plan's first stop past the window: where the window leads on to
  local anchor
  for j = scanEnd + 1, math.min(#list, scanEnd + 40) do
    ns.MaybeYield()
    local w = wpos(list[j])
    if w and E.Status(j) ~= "done" then local s = list[j]; anchor = { w = w, st = s, m = s.m, x = s.x, y = s.y, j = j }; break end
  end
  local here = c.here
  local start = { w = { px, py, pinst }, m = here[1], x = here[2], y = here[3] }
  -- (a pick-up in this town to take before heading out - Next.PickupFirst - is a stop even when the window stopped at
  -- the plan's step; a must stop only with a slot left after the window's own, or no order fits)
  local byStep, cap = c.byStep, c.cap
  c.fits = function(j) return byStep[j] ~= nil or c.wload < cap end
  local pf = c.roomInLog and Next.rules.pickupFirst and Next.PickupFirst(list, c.planned, c.planned, px, py, pinst, c.fits)
  if pf and not byStep[pf] then c.add(pf, { plan = pf }); c.wload = c.wload + 1 end
  c.pf = pf
  if #c.stops == 0 then return false end
  local P = { start = start, stops = c.stops, anchor = anchor, travel = travelSecs, load = c.load, cap = cap }
  P.clock = Next.useClock and clockFor(c, anchor) or nil
  Next.lastP, Next.lastBy, Next.whyNotMemo = P, byStep, {} -- (for Next.WhyNot: "why not that step?")
  local res = ns.Horizon.Solve(P)
  local pick, pst = firstStep(res)
  if pst then res.first = pst end
  c.P, c.res, c.pick, c.pst = P, res, pick, pst
  return true
end

-- the plan's step stands (keepPlanned), and the step the card then really shows is what is remembered as its pick. It
-- remembered the plan's step while keepPlanned passed an added stop for the plan's next own step: the card held "the
-- last pick" while each solve ran, then took the solve's answer - back and forth between the two (A Little Slime Goes a
-- Long Way, a hand-in added in Ironforge, and The Sunken Temple in Feralas). stand: the plan's step itself stands, an
-- added stop too - kept over a pick on another continent, or over one under its confusion price: passing it for the
-- plan's next own step would put that very pick (Feralas) on the card after all.
local function holdPlan(c, res, stand)
  local list, planned = c.list, c.planned
  local alt
  if stand then Next.taken = nil else alt = keepPlanned(c) end
  local shown = alt or planned
  Next.res = res; last = { sig = c.sig, at = c.now, res = res, pick = shown, pickStep = list[shown] }
  return alt
end

-- what goes on the card: the plan's step held, the pick on the card kept by a margin, a pick-up of this town first
local function choosePick(c)
  local E, list, planned, px, py, pinst, byStep, P = c.E, c.list, c.planned, c.px, c.py, c.pinst, c.byStep, c.P
  local res, pick, pst, sig, now = c.res, c.pick, c.pst, c.sig, c.now
  do
    local pw = wpos(list[planned])
    if pst and pst.w and pw and pst.w[3] ~= pinst and pw[3] == pinst then
      if ns.Why then ns.Why("next", "kept the plan's step " .. planned .. ": the solve put " .. tostring(pst.st and pst.st.name or pick) .. " on another continent first") end
      return holdPlan(c, res, true)
    end
  end
  -- the plan's next step is a trip: it stays on the card unless the pick is a prize close by (worth doing before you go)
  -- (only within Next.HOLD_NEAR of you; the prize already on the card gets 1.5x that, so it doesn't flip at the edge)
  local holdR = (last and last.pick and last.pick == pick) and Next.HOLD_NEAR * 1.5 or Next.HOLD_NEAR
  local closePrize = pst and pst.w and pst.w[3] == pinst and (pst.visit or (pst.opt and (pst.w[1] - px) ^ 2 + (pst.w[2] - py) ^ 2 <= holdR ^ 2))
  if (c.holdPlanned or c.count == 0) and not closePrize and not c.pf then
    local opts = 0
    for _, st in ipairs(c.stops) do if st.opt then opts = opts + 1 end end
    if opts > 0 and ns.Why then ns.Why("next", "kept the plan's step " .. planned .. ": " .. opts .. " stop(s) close by weighed, none worth doing before it") end
    return holdPlan(c, res)
  end
  -- hysteresis: the step on the card stays unless the new pick beats keeping it by Next.MARGIN seconds
  -- (except an interrupt: an extra at its NPC, within Next.PASS_NEAR - said at once. A quest behind you is a choice,
  -- not an interrupt: it keeps the margin)
  local fw = res.first and res.first.w
  local passing = res.first and res.first.opt and not res.first.behind and fw and fw[3] == pinst and (fw[1] - px) ^ 2 + (fw[2] - py) ^ 2 <= Next.PASS_NEAR ^ 2
  local keep = not passing and last and last.pick and byStep[last.pick] and last.pick ~= pick and list[last.pick]
  -- (the card's stop and the new pick in the same place, Next.SAME_PLACE: the card stays on its stop until it is done)
  local samePlace = false
  if keep then
    local kw, nw = byStep[last.pick].w, fw
    samePlace = kw and nw and kw[3] == nw[3] and (kw[1] - nw[1]) ^ 2 + (kw[2] - nw[2]) ^ 2 <= Next.SAME_PLACE ^ 2
  end
  if keep then
    P.first = last.pick
    local kept = ns.Horizon.Solve(P)
    if kept.first and (samePlace or res.score - kept.score < Next.MARGIN) then Next.vendor = nil; local kp, kst = firstStep(kept); if kst then kept.first = kst end; res, pick = kept, kp or last.pick end
  end
  -- before you head out, the quests this town gives you (Next.PickupFirst): their work can be done on the same trip out.
  -- from: the step the card would show -> true when that pick-up is the pick now
  local function pickupFirst(from)
    local j = c.roomInLog and Next.rules.pickupFirst and Next.PickupFirst(list, planned, from, px, py, pinst, c.fits)
    if not j then return false end
    if not byStep[j] then c.add(j, {}) end
    local stop = byStep[j]
    if not stop then return false end
    stop.pickupFirst = true
    local was = P.first
    P.first = j
    local forced = ns.Horizon.Solve(P)
    P.first = was
    if not forced.first then return false end
    Next.vendor = nil; local kp, kst = firstStep(forced); if kst then forced.first = kst end; res, pick = forced, kp or j
    return true
  end
  local pf = pickupFirst(pick)
  -- what the pick saves over doing the plan's step first: the window solved with that step first, against this one
  -- (the card shows it: "saves ~3 min"). Once per pick: the same pick against the same plan step keeps its figure
  local function savings()
    if not (pick and pick ~= planned and byStep[planned]) then return end
    if last and last.pick == pick and last.planned == planned and last.saves ~= nil then res.saves = last.saves; return end
    local was = P.first
    P.first = planned
    local alt = ns.Horizon.Solve(P)
    P.first = was
    res.saves = (alt.first and alt.score > -math.huge) and math.max(0, res.score - alt.score) or false
  end
  savings()
  -- the confusion price (Next.CONFUSION; 0 = off): leaving the plan's step must save more than it costs a person to follow
  -- - more the further it sends you from what you'd expect, more again when the card can't name what it pays
  -- (docs/research/route-feel.md). Not for an interrupt at its NPC (passing), nor when the plan's step can't come first
  -- (a pick already on the card has paid its price: priced again as you walk, it would flip on and off).
  -- Nor for a pick-up of this town before you head out (Next.PickupFirst): that rule is about what a player feels left
  -- behind (walked past, or come back for), not time - the price kept the plan's step and sent you out past it. And
  -- when the price does keep the plan's step, which heads out, that step asks for its town pick-up first too (a pick
  -- that was itself a pick-up asked for none)
  if not pf and Next.CONFUSION > 0 and pick and pick ~= planned and byStep[planned] and not passing and type(res.saves) == "number"
    and not (last and last.pickStep and last.pickStep == list[pick]) then
    local price, why = Next.ConfusionPrice(pick, c)
    if price > 0 and res.saves < price then
      if ns.Why then ns.Why("next", string.format("kept the plan's step %d: %s saves %.0f s, under its confusion price %.0f s (%s)", planned, tostring(list[pick] and list[pick].name or pick), res.saves, price, why)) end
      Next.confused = (Next.confused or 0) + 1
      if pickupFirst(planned) then savings()
      else
        return holdPlan(c, res, true)
      end
    end
  end
  Next.res = res
  last = { sig = sig, at = now, pick = pick, pickStep = pick and list[pick], res = res, planned = planned, saves = res.saves }
  if pick and pick ~= planned and ns.Why then
    local s = list[pick]
    ns.Why("next", "step " .. pick .. " (" .. tostring(s.name or s.k) .. ") before the plan's step " .. planned .. ": " .. Next.Reason(pick))
  end
  -- a quest the plan passed as behind you, picked up again here: it's on your route now (Engine.BehindYou) - however it
  -- came into the stops (also via the window, where it is todo only because it was taken)
  local ps = pick and list[pick]
  Next.taken = ps and ((byStep[pick] and byStep[pick].behind) or (E.BehindYou and E.BehindYou(ps, true))) and ps or nil
  return pick
end

local function pick(planned)
  local E, St = ns.Engine, ns.State
  local list = BeelineData and BeelineData.steps
  if not (Next.Enabled() and planned and list and list[planned] and ns.Horizon) then Next.res = nil; return nil end
  local d = BeelineData
  if d.dungeon or d.special then Next.res = nil; return nil end
  -- on the way somewhere (the plan's next step is the trip: Fly to Wetlands), the trip is the step - the card says where
  -- you're going - unless something close by is worth doing first (a quest still worth XP right here, a hand-in in
  -- this town): the solve runs over the stops past the trip and those, and only such a prize takes the card
  local onTrip = isTrip(list[planned])
  -- where you are: the position the once-a-second check measured, when it's fresh; else ask
  local px, py, pinst
  local ep = E.pos
  if ep and GetTime and GetTime() - (ep[4] or 0) < 3 then px, py, pinst = ep[1], ep[2], ep[3] else px, py, pinst = HBD:GetPlayerWorldPosition() end
  if not px then return nil end
  local load = (St.LogCount and St.LogCount()) or 0
  local cap = (St.MaxLog and St.MaxLog()) or 25
  local here = ns.State.Position and { ns.State.Position() } or {}
  local bags = ns.Errands and ns.Errands.FreeSlots and ns.Errands.FreeSlots() or -1
  -- (your level too: a level-up wakes the pick-ups that waited for it)
  local sig = table.concat({ planned, #list, load, math.floor(px / 15), math.floor(py / 15), pinst or 0, tostring(d), math.min(bags, 7), (UnitLevel and UnitLevel("player")) or 0 }, ":")
  local now = GetTime and GetTime() or 0
  -- the pick on the card, by the step table: a stop inserted before it shifts its index
  if last and last.pickStep then
    local j = last.pick
    if not (j and list[j] == last.pickStep) then j = nil; for k = 1, #list do if list[k] == last.pickStep then j = k; break end end end
    last.pick = j
  end
  if last and last.sig == sig and now - last.at < Next.RESOLVE and last.pick and list[last.pick] and E.Status(last.pick) == "todo" then return last.pick end
  -- (dead or a ghost: no solve from where your ghost is - a zone crossed on the run back re-plans too - the card keeps
  -- its pick until you're alive; see Engine.UpdateFocus)
  if ns.Is(UnitIsDeadOrGhost, "player") and last and last.pick and list[last.pick] and E.Status(last.pick) == "todo" then return last.pick end

  -- (a "not now" ends when you move on: checked every solve, not only when that stop is a candidate again)
  for key in pairs(Next.dismissed) do holds(key, px, py, pinst) end
  local c = { E = E, St = St, list = list, planned = planned, px = px, py = py, pinst = pinst, here = here, load = load, cap = cap,
    roomInLog = load < cap, -- (a full log: no pick-up is a candidate at all)
    sig = sig, now = now, onTrip = onTrip,
    holdPlanned = onTrip, -- (the plan's step stays on the card unless a prize close by comes first)
    holdAt = onTrip and planned or nil } -- (the step that stays: the trip, or a grind / note the window stopped at)
  candidates(c)
  gatherWindow(c)
  gatherExtras(c)
  setNeeds(c.stops, list)
  trimStops(c)
  if not solveStops(c) then Next.res = nil; return keepPlanned(c) end
  return choosePick(c)
end

-- a solve: what its prices depend on is taken once, and the trip-planner searches they may start are bounded
-- (Next.ASK_PER_PICK) - whatever way it ends
function Next.Pick(planned)
  Next.Cancel() -- (a solve running in the background is for a state this one replaces)
  sigNow, askLeft = nil, nil
  sigNow, askLeft = priceSig(), Next.ASK_PER_PICK
  local ok, r = ns.Call(pick, planned) -- (inside a route job: no pcall - a pause can't cross one)
  sigNow, askLeft = nil, nil
  if not ok then error(r, 0) end
  return r
end

-- The same solve spread over frames: at most Next.BUDGET_MS of each frame (ns.MaybeYield pauses it inside the search
-- and the trip planner), done(pick) when it ends - nil when it failed (logged). Walking re-solves this way (perf: a
-- whole solve is 20-40 ms). A newer request, or a solve run at once (Next.Pick), cancels the one running.
Next.BUDGET_MS = 1
local pendingDone -- (a finished solve's pick, for the next frame; a newer solve drops it)
-- (the solve is a job of ns.Jobs, kind "solve": its price signature and its bound on trip searches are its own, swapped
-- in for each slice and out after it)
function Next.Busy() return ns.Jobs.Busy("solve") end
function Next.Cancel() pendingDone = nil; ns.Jobs.Cancel("solve") end
local function enter(j) sigNow, askLeft = j.sig, j.ask end
local function leave(j) j.ask = askLeft; sigNow, askLeft = nil, nil end
Next._driver = ns.Jobs._driver -- (the perf battery ticks it)
function Next._Reset() sigNow, askLeft = nil, nil end -- (a route job dropped inside a solve: Engine.Post)
function Next.PickAsync(planned, done)
  -- (while a route change's passes run, no background solve: it would be for a state they are changing - their own
  -- refreshes solve, and one more runs when they end)
  if ns.Engine and ns.Engine.Busy and ns.Engine.Busy() then ns.Engine.Due(); return end
  Next.Cancel()
  sigNow, askLeft = nil, nil
  -- (and the trip to its pick, worked out here too, sliced like the rest: planning it in the card's frame costs 8-10 ms)
  local j = ns.Jobs.Post("solve", function(p)
    local r = pick(p)
    local L = BeelineData and BeelineData.steps
    local st = L and L[r or p]
    if st and ns.Engine and ns.Engine.TravelFor then ns.Call(ns.Engine.TravelFor, st) end
    return r
  end, { arg = planned, budget = Next.BUDGET_MS, enter = enter, leave = leave, logAs = "next", timeAs = "solve slice",
    fail = function() done(nil) end,
    -- (its pick goes on the card in the next frame: the card and the arrow's trip are a frame's work of their own)
    done = function(r)
      local mine = function() done(r) end
      pendingDone = mine
      if C_Timer and C_Timer.After then C_Timer.After(0, function() if pendingDone == mine then pendingDone = nil; local t0 = debugprofilestop(); mine(); if ns.Time then ns.Time("pick on card", debugprofilestop() - t0) end end end) end
    end })
  j.sig, j.ask = priceSig(), Next.ASK_PER_PICK
end
-- (tests: run the one in the background to its end now)
function Next.Settle() ns.Jobs.Settle("solve"); local f = pendingDone; pendingDone = nil; if f then f() end end

-- the last solve's pick, by the step itself, while it is still to do (the card keeps it while the next solve runs)
function Next.LastPick()
  local list = BeelineData and BeelineData.steps
  if not (last and last.pickStep and list) then return nil end
  local j = last.pick
  if not (j and list[j] == last.pickStep) then j = nil; for k = 1, #list do if list[k] == last.pickStep then j = k; break end end end
  if j and ns.Engine.Status(j) == "todo" then return j end
end

-- the last solve's stop for step i (nil: not in it)
local function seqStop(i)
  local seq = Next.res and Next.res.seq
  if not seq then return nil end
  for n = 1, #seq do local s = seq[n]; if s.step == i then return s end end
end
-- why the solve took stop st out of plan order: "here"/"nearby" (behind you), "rejoin" (a block near you before the
-- plan's step: Next.rejoin), "pickupFirst", "chain", "visit", "early", "opt", "way". skipRejoin: the kind below it
local function kindOf(st, skipRejoin)
  if st.behind then
    -- "nearby" only within twice HOLD_NEAR: across the zone it is "in this zone" (a report: Gizzix Grimegurgle, 1.6k yd
    -- off on the far side of Dustwallow, was "nearby")
    local ep = ns.Engine and ns.Engine.pos
    local d2 = ep and st.w and st.w[3] == ep[3] and (st.w[1] - ep[1]) ^ 2 + (st.w[2] - ep[2]) ^ 2
    if d2 and d2 <= Next.HOLD_NEAR ^ 2 then return "here" end
    if d2 and d2 <= (2 * Next.HOLD_NEAR) ^ 2 then return "nearby" end
    -- "in this zone" only when you are in its zone: riding in from Shen'dralas, a Feralas quest read "in this zone"
    local s = st.step and BeelineData and BeelineData.steps and BeelineData.steps[st.step]
    local m = ns.State and ns.State.Position and ns.State.Position()
    return (s and m and s.m == m) and "zone" or "way"
  end
  local rj = Next.rejoin
  if not skipRejoin and rj and st.step and st.step >= rj.at then return "rejoin" end
  if st.pickupFirst then return "pickupFirst" end
  if st.early then return st.chain and "chain" or st.visit and "visit" or "early" end
  if st.opt then return "opt" end
  return "way"
end
local REASON = {
  here = "right here and still worth XP at your level (the plan has it earlier)",
  nearby = "nearby and still worth XP at your level (the plan has it earlier)",
  zone = "in this zone and still worth XP at your level (the plan has it earlier): done before you leave",
  pickupFirst = "pick it up before you head out - its work can be done on the same trip",
  chain = "the chain goes on right here - hand it in and take the next",
  visit = "the plan comes back here for this later - done now, that trip back goes",
  early = "while you're here - it saves coming back for it later",
  opt = "a quest you picked up on the way, handed in where it costs least",
  way = "on the way - the whole route from here is shorter this way",
}
local TAG = { here = "right here", nearby = "nearby", zone = "in this zone", pickupFirst = "before you head out", chain = "chain continues",
  visit = "saves a trip back", early = "while you're here", opt = "on the way", way = "on the way" }

-- why a step picked out of plan order, in words
function Next.Reason(i)
  local st = seqStop(i)
  if not st then return "" end
  local kind = kindOf(st)
  if kind == "rejoin" then
    local rj, L = Next.rejoin, BeelineData and BeelineData.steps
    if rj.wait and L and L[rj.wait] then
      local t = L[rj.wait]
      return "the plan's next step, " .. (t.name or t.text or "its next step") .. ", is across the zone; these later ones are right around you, so they come first"
    end
    if rj.trip and L and L[rj.trip] then
      local t = L[rj.trip]
      return "the plan's next step is a trip to " .. (t.dest or t.text or "another zone") .. ", then it quests here; these come first, the trip waits"
    end
    kind = kindOf(st, true)
  end
  return REASON[kind]
end

-- the card's short tag for a step picked out of plan order, and what it saves: "while you're here · saves ~3 min"
-- (the whole reason is its tooltip: Next.Reason)
function Next.Tag(i)
  local st = seqStop(i)
  if not st then return nil end
  local res = Next.res
  local kind = kindOf(st)
  local tag
  if kind == "rejoin" then tag = Next.rejoin.trip and "before the trip" or "close by first" else tag = TAG[kind] end
  -- a quest behind you saves no time, it adds XP (the score counts XP as time): show what it pays, else what it saves
  if st.behind then
    local s = BeelineData and BeelineData.steps and BeelineData.steps[i]
    local L = (UnitLevel and UnitLevel("player")) or 1
    local xp = s and s.q and ns.QuestXp and ns.QuestXp(s.q, L)
    if not xp and s and tonumber(s.level) and ns.Engine and ns.Engine.QuestXP then xp = ns.Engine.QuestXP(tonumber(s.level), L) end
    if xp and xp >= 100 then tag = tag .. " · +" .. (xp >= 1000 and string.format("%.1fk", xp / 1000) or tostring(math.floor(xp))) .. " XP" end
    return tag
  end
  local saves = res.saves
  local min = saves and math.floor(saves / 60 + 0.5) or 0
  if res.first and res.first.step == i and min >= 1 then tag = tag .. " · saves ~" .. min .. " min" end
  return tag
end

-- The facts behind the card's step when it is not the plan's own (UI/Explain.lua Explain.Ground turns them into the
-- card's one line and the "?"): why it comes first, what it connects to later and what it saves. Read only - it decides
-- nothing. -> nil when step i is the plan's step, else
--   { k = the reason's kind (Next.Reason's: here, nearby, zone, pickupFirst, chain, visit, early, opt, way; rejoin-trip,
--         rejoin-near; waits: the plan's step can't be done yet; insert: a stop added to the route; focus: one you're on),
--     at = step i, plan = the plan's step, later = the level the plan does step i at (its own place in the plan),
--     ahead = plan steps between, saves = seconds (Next.res.saves), pickSecs / planSecs = the window both ways when no
--     prize is in it, behind = a quest behind you, xp, away = its map is not yours, trip = seconds to get there,
--     work = seconds of its work left, why / lv (waits: Engine.NotYet's reason and level), dest (rejoin: the trip) }
local groundMemo = setmetatable({}, { __mode = "k" })
function Next.Ground(i)
  local E = ns.Engine
  local list = BeelineData and BeelineData.steps
  local planned = E and E.planned
  local s = list and i and list[i]
  if not (s and planned and i ~= planned and list[planned]) then return nil end
  local g = { at = i, plan = planned, later = tonumber(s.lvl), ahead = (i > planned) and (i - planned) or nil }
  local st = seqStop(i)
  if s.inserted then g.k = "insert"
  elseif E.focus == i and not st then g.k = "focus"
  elseif st then
    g.k = kindOf(st)
    if g.k == "rejoin" then
      local rj = Next.rejoin
      local t = rj and ((rj.trip and list[rj.trip]) or (rj.wait and list[rj.wait]))
      g.k = (rj and rj.trip) and "rejoin-trip" or "rejoin-near"
      g.dest = t and (t.dest or t.text or t.name) or nil
    end
    g.behind = st.behind and true or nil
  elseif list[planned].inserted then
    -- the plan's step is a stop added to the route (a quest the plan can't hold, a hand-in on the way) that the card
    -- passes for now: the card is on the plan's own next step
    g.k = "extra"
  else
    -- the plan's step can't be done now (a level it opens at, an earlier quest, room in the log): the card is on the
    -- next one it can do
    local why, lv
    if E.NotYet then local w, _, l = E.NotYet(planned); why, lv = w, l end -- (all three: an "and" would keep only the first)
    if why then g.k, g.why, g.lv = "waits", why, lv end
  end
  if not g.k then return nil end
  local res = Next.res
  if res and res.first and res.first.step == i and type(res.saves) == "number" then
    g.saves = res.saves
    -- (the window both ways, in seconds, when nothing in it is a prize: then its score is minus its time)
    local prize = false
    for _, x in ipairs(res.seq or {}) do if (x.prize or 0) > 0 then prize = true; break end end
    if not prize and res.score and res.score < 0 then g.pickSecs, g.planSecs = -res.score, -res.score + res.saves end
  end
  if g.behind or g.k == "here" or g.k == "nearby" or g.k == "zone" then
    local L = (UnitLevel and UnitLevel("player")) or 1
    g.xp = (s.q and ns.QuestXp and ns.QuestXp(s.q, L)) or ((tonumber(s.level) and E.QuestXP) and E.QuestXP(tonumber(s.level), L)) or nil
    local work = 0
    for k = 1, #list do local t = list[k]; if t.q == s.q and E.Status(k) == "todo" then work = work + 60 + ((t.k == "obj" and tonumber(t.work)) or 0) end end
    g.work = work
    -- on another map than yours: the trip there, by the trip planner (remembered for the step and your map)
    local pm, px, py = ns.State.Position()
    if pm and s.m and s.m ~= pm then
      g.away = true
      local key = pm .. ":" .. ((ns.State.KnownTaxiCount and ns.State.KnownTaxiCount()) or 0)
      local m = groundMemo[s]
      if not (m and m.key == key) then
        local ok, _, secs = pcall(ns.Travel.Plan, { m = pm, x = px, y = py }, { m = s.m, x = s.x, y = s.y })
        m = { key = key, secs = ok and tonumber(secs) or nil }
        groundMemo[s] = m
      end
      g.trip = m.secs
    end
  end
  return g
end

-- The confusion price of putting step i on the card in place of the plan's step (seconds; Next.CONFUSION scales it, 0 =
-- off). A person expects the plan's step (for a trip, the next leg's first stop) or something right around them; the
-- price is the walk from the nearer of those to the pick (less PASS_NEAR: at its NPC it is free), CONFUSION_AWAY on
-- another map than both, at most CONFUSION_CAP - times CONFUSION_GENERIC when the reason the card can give names no
-- payoff ("on the way - the whole route from here is shorter"). -> price, a few words on why
Next.CONFUSION = 1
Next.CONFUSION_WAY_YD = 40 -- yards: a pick this close to the straight way from you to the plan's target is on the way: no price
Next.CONFUSION_AWAY = 300
Next.CONFUSION_CAP = 300
Next.CONFUSION_GENERIC = 2
Next.CONFUSION_EXPLAINED = 1 -- (x this for a pick that names its payoff: 0 prices only the unexplained ones)
local GENERIC_KIND = { way = true }
function Next.ConfusionPrice(i, c)
  local list, planned = c.list, c.planned
  local st, s = c.byStep[i], list[i]
  local sw = (st and st.w) or wpos(s)
  if not sw then return 0, "no place" end
  local pw, pm
  for j = planned, math.min(#list, planned + 30) do
    local t = list[j]
    if t.k ~= "fly" and t.k ~= "hearth" and wpos(t) and ns.Engine.Status(j) ~= "done" then pw, pm = wpos(t), t.m; break end
  end
  -- (on the way in the literal sense - within CONFUSION_WAY_YD of the straight way from you to the plan's target: no
  -- price. Kept off the card, such a stop was walked past and come back for: card walk-pasts 31 -> 37 at scale 1)
  if pw and c.pinst == pw[3] and pw[3] == sw[3] and ns.Travel and ns.Travel.SegDist
    and ns.Travel.SegDist(sw[1], sw[2], { c.px, c.py, c.pinst }, pw) <= Next.CONFUSION_WAY_YD then return 0, "on the straight way" end
  local d = math.huge
  if pw and pw[3] == sw[3] and pm == s.m then d = math.sqrt((pw[1] - sw[1]) ^ 2 + (pw[2] - sw[2]) ^ 2) end
  local hm = c.here and c.here[1]
  if c.pinst == sw[3] and (not hm or hm == s.m) then d = math.min(d, math.sqrt((c.px - sw[1]) ^ 2 + (c.py - sw[2]) ^ 2)) end
  local secs, jump
  if d == math.huge then secs, jump = Next.CONFUSION_AWAY, "another zone"
  else
    local sp = (ns.Travel and ns.Travel.Speed and ns.Travel.Speed()) or 7
    secs, jump = math.max(0, d - Next.PASS_NEAR) * ((ns.Travel and ns.Travel.OFFNET) or 1.25) / sp, string.format("%d yd off", d)
  end
  secs = math.min(secs, Next.CONFUSION_CAP)
  local kind = st and kindOf(st) or "way"
  local generic = GENERIC_KIND[kind] and true or false
  return Next.CONFUSION * secs * (generic and Next.CONFUSION_GENERIC or Next.CONFUSION_EXPLAINED), jump .. (generic and ", no payoff to name" or "")
end

-- can the card's step be put off ("not now")? Only a stop the solver took in from where you are - a hand-in while
-- you're here, a quest right behind you, one you picked up on the way - never the plan's own next step.
function Next.CanDismiss(i)
  for _, s in ipairs((Next.res and Next.res.seq) or {}) do if s.step == i then return ((s.opt or s.behind) and true) or false end end
  return false
end
-- a quest the plan has earlier, taken up again because it is still worth XP here (the solve's "behind" stop): the card
-- says it is a side quest first - nil when step i is not one
function Next.IsBehind(i)
  local st = seqStop(i)
  return (st and st.behind) and true or false
end
-- "not now": the stop leaves the card until you move on or a while passes, and the plan's order stands
function Next.Dismiss(i)
  if not Next.CanDismiss(i) then return false end
  -- (where you are: the position the once-a-second check measured, as the solve uses it)
  local ep = ns.Engine and ns.Engine.pos
  local px, py, pinst
  if ep then px, py, pinst = ep[1], ep[2], ep[3] else px, py, pinst = HBD:GetPlayerWorldPosition() end
  if not px then return false end
  local list = BeelineData and BeelineData.steps
  if not (list and list[i]) then return false end
  Next.dismissed[list[i]] = { t = GetTime and GetTime() or 0, x = px, y = py, inst = pinst }
  last = nil
  if ns.Engine and ns.Engine.focus == i then ns.Engine.focus, ns.Engine.focusWhy = nil, nil end
  if ns.Engine and ns.Engine.Refresh then ns.Engine.Refresh() end
  return true
end

-- the finished quests left for later (the card's "later" line): their names
function Next.Deferred()
  local out = {}
  for _, s in ipairs((Next.res and Next.res.skipped) or {}) do
    local st = BeelineData and BeelineData.steps and BeelineData.steps[s.step]
    if st and st.k == "turnin" and st.name then out[#out + 1] = st.name end
  end
  return out
end

-- the hand-in run at a hub: the finished quests you can hand in where this step is (Next.HUB_YD) - how many, and about
-- how much XP. The card names it when there are 3 or more.
-- -> { n, xp } or nil
function Next.Batch(i)
  local list = BeelineData and BeelineData.steps
  local s = list and list[i]
  local w = s and wpos(s)
  if not (w and s.k == "turnin") then return nil end
  local E, St = ns.Engine, ns.State
  local L = (UnitLevel and UnitLevel("player")) or 1
  local n, xp, seen = 0, 0, {}
  for _, j in ipairs(stepsOfKind(list).turnin) do
    local t = list[j]
    if t.q and not seen[t.q] and St.QuestReady(t.q) then
      local tw = wpos(t)
      if tw and tw[3] == w[3] and (tw[1] - w[1]) ^ 2 + (tw[2] - w[2]) ^ 2 <= Next.HUB_YD ^ 2 and E.Status(j) == "todo" then
        seen[t.q] = true
        n = n + 1
        xp = xp + ((E.QuestXP and tonumber(t.level)) and E.QuestXP(t.level, L) or 0)
      end
    end
  end
  if n < 3 then return nil end
  return { n = n, xp = math.floor(xp / 50 + 0.5) * 50 }
end

-- "Why not that step next?" - contrastive, the way people ask: the last solve's window scored again with that step
-- forced first, against the best. -> a line for the route list's tooltip, or nil (not in the window the solve looked at)
function Next.WhyNot(i)
  local P, by, res = Next.lastP, Next.lastBy, Next.res
  if not (P and by and res and by[i] and ns.Horizon) then return nil end
  if res.first and res.first.step == i then return "The best next step from where you are." end
  local memo = Next.whyNotMemo or {}
  local v = memo[i]
  if v == nil then
    local was = P.first
    P.first = i
    local forced = ns.Horizon.Solve(P)
    P.first = was
    v = (forced.first and forced.score > -math.huge) and math.max(0, res.score - forced.score) or false
    memo[i] = v
  end
  if v == false then return "Can't come next: something before it has to be done first (or your log is full)." end
  local min = math.floor(v / 60 + 0.5)
  if min < 1 then return "Next instead: about the same - less than a minute in it." end
  return string.format("Next instead: about %d min longer on the way from here.", min)
end

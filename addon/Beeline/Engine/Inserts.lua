-- The route engine, adding a stop where it costs least, and side trips merged into your route. Loaded right after
-- Engine.lua, so its event handlers run in the same order as before the split.
local _, ns = ...
local pcall = ns.PCall or pcall -- (a job never pauses under it: Core.lua)
local Engine = ns.Engine
local State = ns.State
local function steps() return BeelineData and BeelineData.steps or {} end
local HBD = LibStub("HereBeDragons-2.0")
local wpos = ns.Util.WPos
local isTrip = Engine.IsTrip

----------------------------------------------------------------------------------------------------------------
-- Adding a stop (like adding a stop in a maps app): a quest you finished that the route has no hand-in for gets one,
-- slotted into the cheapest gap between two neighbouring stops - cost d(a,X) + d(X,b) - d(a,b) - or made the very next
-- step if "from where you are" is the cheapest gap. One pass over the stops; no replan. Only after the current step,
-- and only on the stop's continent. Hand-in spots: BeelineEnders from the plan.
-- A gap is priced as a walk only when it is one: the straight-line detour means something when you cover a -> b on
-- the ground; when a -> b is a flight, a boat or your hearthstone, nothing between the ends is "on the way" (a stop
-- under the line would be sent to as the very next step). Such a gap takes a stop only at one of its ends: there and
-- back from where you leave or where you arrive, if the stop is ground travel from that end.
----------------------------------------------------------------------------------------------------------------
local function wd(a, b) return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2) end
-- do you cover a -> b on the ground? The same zone: yes. Another zone: what the trip planner says (ns.Travel.Plan, the
-- one the card's travel line comes from) - rides only. A place whose zone is unknown: no.
local groundMemo = {}
Engine._groundMemo = groundMemo -- (tests: the same answers whether the passes run at once or over frames)
-- The answers kept from one login to the next (per character): a login's catch-up asked the trip planner the same
-- gaps every time (most of an 80 ms refresh). Keyed by level (in every key), addon version and travel data; any
-- change starts over. ONFOOT_KEEP of them at most.
Engine.ONFOOT_KEEP = 2000
local function memoStamp()
  local n = 0
  for _, t in pairs(ns.TravelData or {}) do if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end end
  return tostring(ns.VERSION) .. ":" .. n
end
function Engine.OnFootLoad()
  local s = ns.char and ns.char.onFoot
  if not (type(s) == "table" and type(s.memo) == "table" and s.lvl == (UnitLevel and UnitLevel("player")) and s.v == memoStamp()) then return end
  for k, v in pairs(s.memo) do if groundMemo[k] == nil then groundMemo[k] = v end end
end
function Engine.OnFootSave()
  if not ns.char then return end
  local lvl = UnitLevel and UnitLevel("player")
  local keep, n, want = {}, 0, tostring(lvl)
  for k, v in pairs(groundMemo) do
    -- (only this level's: the key is am:ax:ay:bm:bx:by:taxis:level:bind)
    if n < Engine.ONFOOT_KEEP and k:match("^[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:([^:]*)") == want then keep[k] = v; n = n + 1 end
  end
  ns.char.onFoot = n > 0 and { v = memoStamp(), lvl = lvl, memo = keep } or nil
end
ns.On("FR_LOADED", function() pcall(Engine.OnFootLoad) end)
ns.On("PLAYER_LOGOUT", function() pcall(Engine.OnFootSave) end)
-- -> the answer without a search, or nil
local function footQuick(am, ax, ay, bm, bx, by)
  if not (am and bm) then return false end
  if am == bm then return true end
  if not (ax and ay and bx and by and ns.Travel and ns.Travel.Plan) then return false end
  return nil
end
-- the key's tail: your flight paths, level and bind (taken once per InsertStop pass and frame)
local function footTail()
  local n = State.KnownTaxiCount()
  local okB, bind = pcall(GetBindLocation)
  return n .. ":" .. (UnitLevel("player") or 0) .. ":" .. tostring(okB and bind)
end
local function footBy(tail, am, ax, ay, bm, bx, by)
  local k = am .. ":" .. math.floor(ax * 400) .. ":" .. math.floor(ay * 400) .. ":" .. bm .. ":" .. math.floor(bx * 400) .. ":" .. math.floor(by * 400) .. ":" .. tail
  local v = groundMemo[k]
  if v == nil then
    -- (ns.Call, not pcall: inside a route job the search may pause, and a pause inside a pcall is an error the pcall
    -- swallows - a wrong "not on foot" was remembered)
    local ok, legs = ns.Call(ns.Travel.Plan, { m = am, x = ax, y = ay }, { m = bm, x = bx, y = by })
    v = ok and type(legs) == "table" and legs[1] ~= nil or false
    if v then for _, l in ipairs(legs) do if l.how ~= "ride" then v = false; break end end end
    groundMemo[k] = v
  end
  return v
end
function Engine.OnFoot(am, ax, ay, bm, bx, by)
  local q = footQuick(am, ax, ay, bm, bx, by)
  if q ~= nil then return q end
  return footBy(footTail(), am, ax, ay, bm, bx, by)
end

-- opts.rough: priced by straight-line detours alone (never more than the real price: it can only rule a far stop out)
-- opts.at: at this step, no search (a quest giver you stand next to: now). opts.dry: nothing is added; -> where, cost
-- opts.maxIndex: only before this step (a side quest's objective: while the quest still gives XP)
function Engine.InsertStop(new, px, py, pinst, opts)
  opts = opts or {}
  local list = steps()
  local cur = Engine.current
  if not cur then return nil end
  -- (from your place in the plan, not the card's step when that is behind it: a quest from the part you passed, the
  -- floor's step of a quest you hold. A stop put in the stretch between them became the card from wherever you were -
  -- the plan never goes back for it, and nothing there reads "behind you" for a stop added)
  local p = Engine.planned
  local base = (p and p > cur and list[p]) and p or cur
  local from = math.max(base, opts.minIndex or base)
  Engine.lastInsertCost = nil -- (a stop that can't go anywhere leaves no price behind: the merge's "left for later" read the last one)
  local X = wpos(new); if not X then return nil end
  -- gaps: (you -> current step) when you're on the same map, then each pair of neighbouring stops after it
  local best, bestCost = opts.at, nil
  local prev = nil -- the near end of the gap: { w = world position, m, x, y = its zone position }
  if px and pinst == X[3] and from == base then local pm, zx, zy = Engine.Pos(); prev = { w = { px, py, pinst }, m = pm, x = zx, y = zy } end
  -- chained stops start after a given step: the gap right after it counts too
  if from > base and list[from - 1] then local t = list[from - 1]; local w = wpos(t); if w and w[3] == X[3] then prev = { w = w, m = t.m, x = t.x, y = t.y } end end
  -- opts.onMap: only a gap with an end in that zone (straight lines say nothing across a zone border: mountains)
  local function touches(a, bm) return not opts.onMap or (a and a.m == opts.onMap) or bm == opts.onMap end
  local tail, tailAt
  local function onFoot(am, ax, ay, bm, bx, by)
    local q = footQuick(am, ax, ay, bm, bx, by)
    if q ~= nil then return q end
    local now = GetTime and GetTime()
    if not tail or tailAt ~= now then tail, tailAt = footTail(), now end
    return footBy(tail, am, ax, ay, bm, bx, by)
  end
  -- what the stop costs in the gap a -> s (nil: this gap can't take it)
  local function gapCost(a, s, w)
    if not touches(a, s.m) then return nil end
    if opts.rough then return wd(a.w, X) + wd(X, w) - wd(a.w, w) end -- straight lines only: a lower bound, no trip searches
    if onFoot(a.m, a.x, a.y, s.m, s.x, s.y) then return wd(a.w, X) + wd(X, w) - wd(a.w, w) end
    local c
    if onFoot(a.m, a.x, a.y, new.m, new.x, new.y) then c = 2 * wd(a.w, X) end
    if onFoot(new.m, new.x, new.y, s.m, s.x, s.y) then local c2 = 2 * wd(X, w); if not c or c2 < c then c = c2 end end
    return c
  end
  -- riding the current travel step (no flight path there yet): the road from you to the first stop at the other end
  -- is a real stretch - a stop on it goes before the travel step, i.e. you do it on the way
  local ride = nil
  if prev and from == base and list[base] and list[base].k == "fly" and Engine.TravelPlan then -- not for stops that must come after an earlier one
    local plan = Engine.TravelPlan(list[base])
    local m = ns.State.Position()
    -- only a real ride: if the trip there involves boats or flights, stops at the other end go after the travel step
    local trip = Engine.TravelFor and Engine.TravelFor(list[base])
    local riding = not trip or (trip.how == "ride" and not (trip.legs and #trip.legs > 1))
    if riding and plan and (plan.ride or not plan.via or plan.via == m) then ride = prev end
  end
  -- (the passed part by place alone: a completed quest's steps there are done, not behind you - Engine.PassedFn)
  local passed = Engine.PassedFn and Engine.PassedFn()
  local bm = Engine.BehindMemo and Engine.BehindMemo("gaps")
  for i = from, opts.at and from - 1 or math.min(#list, opts.maxIndex or #list) do
    if (i - from) % 8 == 7 then ns.MaybeYield() end -- (a route job: every 8 gaps a pause - never after the insert below)
    local s = list[i]
    -- (never into the part of the plan behind you: the stop would become the plan's next step and pull the card back;
    -- nor between two steps of quests you completed there, nor the pick-up of a quest you carry: the route doesn't
    -- pass by them, and a zero-cost gap there sent players far away for one stop)
    if (Engine.BehindYou and (bm and Engine.BehindYouIn(bm, s) or not bm and Engine.BehindYou(s)))
      or (passed and s.q and s.q > 0 and passed(i) and (State.IsCompleted(s.q) or (s.k == "accept" and State.OnQuest(s.q)))) then prev = nil
    elseif isTrip(s) then prev = nil -- a trip in between: the gap doesn't count
    else
      local w = wpos(s)
      if w and w[3] == X[3] then
        if ride then
          if touches(ride, s.m) then
            local c = wd(ride.w, X) + wd(X, w) - wd(ride.w, w)
            if not bestCost or c < bestCost then bestCost, best = c, base end -- before the travel step: on the way
          end
          ride = nil
        end
        -- never between two steps at the same NPC (turn in to Takar, accept from Takar): do both while you are there
        local split = list[i - 1] and list[i - 1].npc and list[i - 1].npc == s.npc
        -- (a gap whose straight-line detour is no better than the best so far can't win: every gapCost price is at
        -- least that detour (triangle inequality), so it is not priced - pricing asks the trip planner, hundreds of
        -- searches for far gaps otherwise)
        local hopeless = Engine.INSERT_PRUNE ~= false and prev and bestCost and wd(prev.w, X) + wd(X, w) - wd(prev.w, w) - 1e-6 >= bestCost
        if prev and not split and not hopeless then
          local c = gapCost(prev, s, w)
          if c and (not bestCost or c < bestCost) then bestCost, best = c, i end -- insert before step i
        end
        prev = { w = w, m = s.m, x = s.x, y = s.y }
      end
    end
  end
  -- after the last stop on that map, as the next one (if there was a stretch there at all)
  if not best and prev and not opts.maxIndex then best = #list + 1 end
  if not best then return nil end
  Engine.lastInsertCost = bestCost
  if opts.maxCost and (bestCost or math.huge) > opts.maxCost then return nil end
  if opts.dry then return best, bestCost end
  -- the current step stays current: a stop that goes "before the current step" becomes the step right after it,
  -- unless it's cheapest to do first, in which case it's inserted at the current position (shown next)
  -- the stop belongs to the stretch it lands in: the hub of the step it goes before (or the one before it, at the end).
  -- A sec copied from another side trip would put the wrong hub on the card and a stray header in the list.
  local around = list[best] or list[best - 1]
  if around then new.sec = around.sec end
  new.added = true -- (a stop put in here belongs where it went: the plan's floor leaves it alone, Engine.Compute)
  table.insert(list, best, new)
  -- everything after it moved down one: step numbers, and the "where next?" choices (they are kept by position)
  for i = best, #list do list[i].id = i end
  local d = BeelineData
  if d and list == d.steps then for _, c in ipairs(d.choices or {}) do if c.at and c.at >= best then c.at = c.at + 1 end end end
  if ns.Why then ns.Why("insert", "added " .. (new.k or "") .. " " .. (new.name or (new.k == "fp" and ((new.zone or "?") .. " (" .. tostring(new.npc) .. ")")) or new.npc or "") .. " as step " .. best .. " (" .. (opts.why or "you finished it; this is where it costs least") .. ")") end
  Engine.StepsChanged(list)
  if Engine.focus and Engine.focus >= best then Engine.focus = Engine.focus + 1 end
  if Engine.view and Engine.view >= best then Engine.view = Engine.view + 1 end
  -- (the plan's place moves down with its step: the next stop of the same pass is placed from it, not one before it)
  if Engine.planned and Engine.planned > best then Engine.planned = Engine.planned + 1 end
  Engine.RunShift(best)
  return best
end

-- side trips merge: the next stops of unfinished side trips (class quests, the sleeping bag), where they cost least,
-- if the detour is small. On a side trip, the other side trips join it; on your leveling path they join it too, but
-- only where the path really passes by (fold them in, and keep them as side trips)
Engine.MERGE_MAX_YARDS = 3000
Engine.MERGE_PATH_YARDS = 600
Engine.FP_DETOUR_YARDS = 600
-- a side trip that takes a group: an attunement or a dungeon key - a "Run <dungeon>" step or work done inside one, as
-- a dungeon trip's (tools/special-routes.js). Its quests are the trip's alone: never folded into your path or another
-- trip, and on your plan's card only once you pick it (Blackhand's Command and Attunement to the Core were added on
-- the way through Searing Gorge at 55, Dragonkin Menace and Dark Iron Legacy through the Burning Steppes - gate sweep)
function Engine.GroupTrip(r)
  if not r then return false end
  if r.dungeon and not r.special then return true end
  if r.group == "attune" or r.group == "key" then return true end
  if r._groupTrip == nil then
    local g = false
    for _, s in ipairs(ns.Steps(r) or {}) do if Engine.RunDungeon(s) or Engine.InsideOf(s) then g = true; break end end
    r._groupTrip = g
  end
  return r._groupTrip
end
function Engine.MergeSideTrips()
  local d = BeelineData
  -- the flag lives on the step list: switching to the trip again unpacks a fresh list, which needs merging again
  if not (d and d.steps) or d.steps._merged or not ns.DungeonRoutes then return false end
  if d.branch or (d.dungeon and not d.special) then return false end -- a dungeon route stays about its dungeon
  local maxCost = d.special and Engine.MERGE_MAX_YARDS or Engine.MERGE_PATH_YARDS
  local px, py, pinst = HBD:GetPlayerWorldPosition()
  local added = 0
  -- what the route already does (the planner puts some of these quests in your path itself): never twice
  local onRoute
  local function index() -- rebuilt after each insert: later steps move down one
    onRoute = {}
    for i, s in ipairs(d.steps) do if s.q and s.q > 0 and not onRoute[s.k .. ":" .. s.q] then onRoute[s.k .. ":" .. s.q] = i end end
  end
  index()
  for _, r in ipairs(ns.DungeonRoutes()) do
    if r.special and r.id ~= d.id and (UnitLevel("player") or 1) >= (tonumber(r.needsLevel) or 1) and not Engine.GroupTrip(r) then
      local minI = Engine.current or 1
      local rsteps = ns.Steps(r)
      for _, s in ipairs(rsteps) do
        ns.MaybeYield()
        local skip = isTrip(s) or s.unknown or not (s.q and s.q > 0 and s.m and s.x)
          or State.IsCompleted(s.q) or (s.k == "accept" and State.OnQuest(s.q)) or onRoute[s.k .. ":" .. s.q]
        -- a chain step the route already has: the rest of the chain goes after it
        local there = s.q and onRoute[s.k .. ":" .. s.q]
        if there then minI = math.max(minI, there + 1) end
        if not skip then
          local copy = {}; for k, v in pairs(s) do copy[k] = v end
          copy.inserted, copy.id, copy.wp = true, nil, nil
          copy.note = "On the way: " .. (r.dungeonName or r.title) .. "."
          -- a quest is picked up only if its hand-in joins this trip too (else the card ran you far for a quest to carry)
          local handIn
          if s.k == "accept" then
            for _, t in ipairs(rsteps) do if t.k == "turnin" and t.q == s.q and t.m and t.x then handIn = t; break end end
            if handIn and onRoute["turnin:" .. s.q] then handIn = nil end -- the route hands it in itself
          end
          -- (the pick-up is priced first: most are too far anyway, and pricing the hand-in only for one that fits keeps
          -- login trip searches down)
          local at, why
          local opts = { minIndex = minI, maxCost = maxCost, why = "on the way for " .. (r.dungeonName or r.title), dry = handIn and true or nil }
          local fits = Engine.InsertStop(copy, px, py, pinst, opts)
          if not fits then
            why = Engine.lastInsertCost and string.format("a %d yd detour, over the %d yd limit", Engine.lastInsertCost, maxCost) or "another continent or nowhere near this trip"
          elseif not handIn then
            at = fits
          elseif not Engine.InsertStop(handIn, px, py, pinst, { minIndex = minI, maxCost = maxCost, dry = true, rough = true }) then
            why = "its hand-in (" .. (handIn.zone or "?") .. ") is " .. (Engine.lastInsertCost and string.format("a %d yd detour, over the %d yd limit", Engine.lastInsertCost, maxCost) or "on another continent or nowhere near this trip")
          else
            -- where the pick-up's pricing put it (no second search; nothing was added in between)
            at = Engine.InsertStop(copy, px, py, pinst, { at = fits, why = opts.why })
          end
          if not at then
            if ns.Why then ns.Why("merge", "left " .. (copy.k or "") .. " " .. (copy.name or "") .. " (" .. (r.dungeonName or r.title) .. ") for later: " .. why) end
            break -- the rest of that chain waits
          end
          minI = at + 1; added = added + 1; index()
        end
      end
    end
  end
  -- flight paths you do not have, close to the trip (a small detour now saves trips later): only where the trip has
  -- you in the flight master's own zone, on a stretch you cover on the ground
  -- (each flight point of a zone on its own: of Mount Hyjal's two, the one by the trip - Tainted Foothills by Ketharas -
  -- whether you have the other or not; a route's "fp" step without a flight master stands for its zone's)
  local have = {}; for _, s in ipairs(steps()) do if s.k == "fp" and s.m then have[s.npc and (s.m .. ":" .. s.npc) or s.m] = true end end
  for m, list in pairs(ns.FLIGHT or {}) do
    ns.MaybeYield()
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(m)
    local zn = info and info.name
    if zn and not have[m] then
      for _, f in ipairs(list) do
        if not have[m .. ":" .. tostring(f[3])] and not ns.Travel.KnowsFlightPoint(m, f[3]) then
          local at = Engine.InsertStop({ k = "fp", npc = f[3], m = m, x = f[1], y = f[2], zone = zn, r = 8, inserted = true, note = "A flight path you do not have yet - saves trips later." }, px, py, pinst, { maxCost = Engine.FP_DETOUR_YARDS, onMap = m, why = "a flight path close to this trip" })
          if at then added = added + 1 end
        end
      end
    end
  end
  if added > 0 then ns.Print(added .. " stop" .. (added == 1 and "" or "s") .. " added on the way: other side trips and flight paths you do not have (see the list).") end
  -- (merged once it is done: a merge dropped half way - a newer route change, an error - runs again)
  d.steps._merged = true
  return added > 0
end
-- (after a login or a route change: Engine.PASSES)

-- the hand-in spots (BeelineEnders) of the quests in your log: the list covers every quest you could take
-- (~1000), so walk your log (at most 40) and look each one up instead of asking the game about all of them
function Engine.LogEnders()
  local enders = BeelineEnders
  if not enders then return {} end
  local inLog = {}
  Engine.logLevels = {} -- quest level by id, for the gray check below
  local n = C_QuestLog and C_QuestLog.GetNumQuestLogEntries and select(2, pcall(C_QuestLog.GetNumQuestLogEntries))
  if type(n) == "number" and n > 0 and C_QuestLog.GetInfo then
    for _, q, level in State.LogQuests(n) do
      if enders[q] then inLog[q] = enders[q]; Engine.logLevels[q] = level end
    end
    return inLog
  end
  return enders -- no quest log to read (tests): every spot, each checked with QuestReady
end
-- finished quests in your log with no hand-in on the route: add one where it costs least
-- Where it costs least by the walk can be where the plan next passes the hand-in, levels later, when the quest is gray
-- and pays a tenth. The XP it would lose by waiting is weighed against going now, there and back, at your pace
-- (Engine.XpPerSec); worth more than that trip, the hand-in is your next stop.
-- -> the step the hand-in goes before now (nil: where the walk says), the XP it would lose, the trip's seconds
function Engine.HandInNow(step, ql, at)
  local list = steps()
  local me = UnitLevel and UnitLevel("player") or 1
  if type(ql) ~= "number" or not at or not Engine.current then return nil end
  local t = list[at] or list[at - 1] or list[#list]
  -- (the plan's level there, PlanLevel: travel, binds and added stops carry no lvl of their own)
  local then_ = math.max(me, tonumber(Engine.PlanLevel and Engine.PlanLevel(at)) or tonumber(t and t.lvl) or me)
  local lost = Engine.QuestXP(ql, me) - Engine.QuestXP(ql, then_)
  if lost <= 0 then return nil end
  local pm, px, py = Engine.Pos()
  if not (pm and step.m and step.x) or not (ns.Travel and ns.Travel.Plan) then return nil end
  local _, secs = ns.Travel.Plan({ m = pm, x = px, y = py }, { m = step.m, x = step.x, y = step.y, name = step.npc }, { hearth = false })
  if not secs then return nil end
  local tripCost = Engine.XpPerSec(me) * (2 * secs) -- there and back, at your pace (Engine.XpPerSec)
  if lost <= tripCost then return nil end
  -- (before the plan's own step, not the card's: the card can show a quest from the part behind you)
  return Engine.planned or Engine.current, lost, secs
end
local function applyInserts()
  local list = steps()
  if not (BeelineEnders and BeelineData and #list > 0) then return false end
  -- side trips (special rewards, dungeon routes) are their own short list: your leveling path handles the extras
  if BeelineData.dungeon or BeelineData.special then return false end
  local have = {}
  -- (a hand-in behind you in the built-in plan is not on the route: Engine.BehindYou)
  local behind = {}
  local bm = Engine.BehindMemo("hand-ins")
  for _, s in ipairs(list) do if s.k == "turnin" and s.q then if Engine.BehindYouIn(bm, s) then behind[s.q] = true else have[s.q] = true end end end
  local px, py, pinst = HBD:GetPlayerWorldPosition()
  local added = false
  -- (on a zone you picked: only the hand-ins in that zone - the rest wait for your way back to the plan, as a side
  -- quest's stops do (Side.lua); a short zone route's end was otherwise the cheapest spot for every finished quest)
  local zoneMaps; if not BeelineData.zoneRoute then zoneMaps = false end
  for q, e in pairs(Engine.LogEnders()) do
    ns.MaybeYield() -- (a route job: a quest a pause)
    if zoneMaps == nil and not have[q] and ns.State.QuestReady(q) then zoneMaps = (ns.Stitch and ns.Stitch.ZoneMaps and ns.Stitch.ZoneMaps(BeelineData)) or false end
    if not have[q] and not (ns.Nope(q)) and ns.State.QuestReady(q) and not ns.State.IsCompleted(q) and not (zoneMaps and not zoneMaps[e.m]) then
      local step = { k = "turnin", q = q, name = e.name, npc = e.npc, m = e.m, x = e.x, y = e.y, r = 6, inserted = true,
        note = "Added: you finished this one on the way." }   -- its sec comes from where InsertStop puts it
      local ql, me = Engine.logLevels and Engine.logLevels[q], UnitLevel and UnitLevel("player")
      if type(ql) == "number" then step.level = ql end -- (the solve prices a hand-in by its quest's level: without it, a flat guess)
      -- a gray quest that leads to nothing worth XP gets no stop at all: the one gray rule (Engine.GrayDrop)
      local gray = type(me) == "number" and Engine.GrayDrop(q, me, ql) == true
      local opts = (behind[q] and { maxCost = Engine.MERGE_PATH_YARDS, why = "its hand-in is behind you in the plan, and the route passes by" }) or nil
      -- (not gray, not behind you: would waiting for the cheapest spot cost more XP than going now?)
      local dryAt, dried
      if not opts and not gray and type(ql) == "number" then
        local at = Engine.InsertStop(step, px, py, pinst, { dry = true })
        dryAt, dried = at, true
        local now, lost, secs = Engine.HandInNow(step, ql, at)
        if now then opts = { at = now, why = string.format("worth going now: waiting would lose ~%d XP, ~%d min there and back", lost, math.floor(2 * secs / 60 + 0.5)) } end
      end
      -- (not going now: where the dry run found is where the search would put it again - nothing has changed since)
      if dried and not opts then opts = dryAt and { at = dryAt } or false end
      if opts ~= false and not gray and Engine.InsertStop(step, px, py, pinst, opts or nil) then added = true; have[q] = true end
    end
  end
  return added
end
-- The hand-ins are fitted to the log as State last read it (State.logGen): insGen is the generation they were fitted
-- to (nil until the login's or a route change's pass has run them on this route). A refresh that comes before the
-- log's FR_STATE - a quest with nothing to do, taken this moment, is finished at once - fits them first (Engine.Refresh-
-- Inner: Engine.InsertsDue), so the solve never picks with a finished quest's hand-in missing; FR_STATE then skips
-- that change. (Wine Shop Advert, taken in Stormwind at level 5: the next solve ran before its hand-in was in and the
-- card sent a night elf to Teldrassil, then back a moment later.)
local insGen, early = nil, false
Engine.ApplyInserts = function() insGen, early = ns.State.logGen, false; return applyInserts() end
function Engine.InsertsDue() return insGen ~= nil and insGen ~= ns.State.logGen end
function Engine.InsertsNow() insGen, early = ns.State.logGen, true; return applyInserts() end
ns.On("FR_ROUTE_CHANGED", function() insGen, early = nil, false end)
ns.On("FR_STATE", function()
  if early and insGen == ns.State.logGen then early = false; return end -- (this change: fitted by the refresh before)
  insGen, early = ns.State.logGen, false
  if applyInserts() then Engine.Refresh() end
end)
-- (and after a login or a route change: Engine.PASSES)

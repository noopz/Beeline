-- Step engine: decides which step is current from live quest state, like a hand-written guide's conditions.
-- Steps (from Route.lua): { id, k = kind, q = questID, name, npc, m = uiMapID, x, y (0-1), r = arrive radius, match = objective
--   text, text, note, warn, minLevel, level, lvl (planned level here), xp, to (destination map), bind, fp, item, target, sec }
local _, ns = ...
local pcall = ns.PCall or pcall -- (a job never pauses under it: Core.lua)
local Engine = {}
ns.Engine = Engine
local State = ns.State -- (State.lua loads first: the .toc)

Engine.current = nil  -- index of the first step that still needs doing
Engine.view = nil     -- an earlier/later step being looked at (Back, list); never changes progress
local quiet = true    -- no completion animation for the catch-up refresh at login

local function steps() return BeelineData and BeelineData.steps or {} end
-- One generation per step list (list._gen): Engine.StepsChanged(list) after a stop is inserted or removed. Every cache
-- built from a list keeps the generation it was built at (c.gen) and is built again when it differs.
function Engine.StepsChanged(list) if list then list._gen = (list._gen or 0) + 1 end end
-- (tools/replay.js edits a list in place and clears its key cache: that is a change of the list)
Engine._keyCache = setmetatable({}, { __newindex = function(_, list) Engine.StepsChanged(list) end })
-- Ticks and skips are stored against the step itself, not its number: kind + quest + what it targets, plus which
-- occurrence it is. Regenerating the route shifts step numbers; these keys stay on the same step.
local keyCache = setmetatable({}, { __mode = "k" })
function Engine.Key(i)
  local list = steps()
  local c = keyCache[list]
  if not c or c.gen ~= (list._gen or 0) then
    c = { gen = list._gen or 0 }; local seen = {}
    for j, s in ipairs(list) do
      local base = (s.k or "?") .. ":" .. tostring(s.q or "") .. ":" .. tostring(s.match or s.text or s.dest or s.name or s.npc or s.fp or s.bind or "")
      seen[base] = (seen[base] or 0) + 1
      c[j] = base .. "#" .. seen[base]
    end
    keyCache[list] = c
  end
  return c[i]
end
local function key(i) return Engine.Key(i) end

local wordsOf, wordsCache, wordsN -- (below Engine.Words)
-- noElim: without the elimination pass (it asks about the quest's other steps, which would ask about this one)
function Engine.ObjectiveFor(step, noElim)
  local q = State.Quest(step.q)
  if not q or not q.on then return nil end
  if step.unknown then return nil end -- (the quest's own words, no objective's: the card shows all of the quest's lines)
  if step.match then
    -- the exact name first ("Murloc slain" for "Murloc"), then any objective containing it: a loose-only match
    -- could pick "Murloc Streamrunner slain"
    local m = step.match:lower()
    local loose
    for _, o in ipairs(q.objectives) do
      local t = o.text:lower()
      if t:sub(1, #m) == m and (t:sub(#m + 1, #m + 1) == ":" or t:sub(#m + 1, #m + 6) == " slain") then return o end
      if not loose and t:find(m, 1, true) then loose = o end
    end
    if loose then return loose end
  end
  if step.o and q.objectives[step.o] then return q.objectives[step.o] end
  -- no match word from the planner (objects to use, places to explore): the objective sharing the most distinctive
  -- words with the step ("Read the Lay of Ameth'Aran" -> "Lay of Ameth'Aran read"), when exactly one does best
  if not step.match and step.text then
    local want = wordsOf(step.text)
    local best, bestN, tie = nil, 0, false
    for _, o in ipairs(q.objectives) do
      local n = 0
      for w in pairs(wordsOf(o.text)) do if want[w] then n = n + 1 end end
      if n > bestN then best, bestN, tie = o, n, false elseif n == bestN and n > 0 then tie = true end
    end
    if best and not tie then return best end
  end
  if not noElim and not step.match and step.text then
    -- by elimination: every other objective of the quest belongs to another step of the route: the one left is
    -- this step's
    local claimed, list = {}, steps()
    for _, j in ipairs(Engine.ObjStepsOf(step.q)) do
      local t = list[j]
      if t ~= step then local o2 = (t.match or next(wordsOf(t.text))) and Engine.ObjectiveFor(t, true) or nil; if o2 then claimed[o2] = true end end
    end
    local left
    for _, o in ipairs(q.objectives) do if not claimed[o] then if left then return nil end; left = o end end
    return left
  end
end
-- the words that tell objectives apart (not "the", "of", the verb, or counts)
local COMMON = { the = 1, ["and"] = 1, ["for"] = 1, ["from"] = 1, ["with"] = 1, ["into"] = 1, ["your"] = 1, use = 1, read = 1, free = 1, locate = 1,
  collect = 1, kill = 1, investigate = 1, explore = 1, find = 1, slain = 1, ["get"] = 1, bring = 1, place = 1, open = 1 }
function Engine.Words(t)
  local out = {}
  if type(t) ~= "string" then return out end
  for w in t:lower():gmatch("[%a'][%a']+") do if #w > 2 and not COMMON[w] then out[w] = true end end
  return out
end
-- (ObjectiveFor's: kept per text, read only; emptied past WORDS_KEEP texts - objective texts carry counts)
local WORDS_KEEP, NOWORDS = 2000, {}
wordsCache, wordsN = {}, 0
function wordsOf(t)
  if type(t) ~= "string" then return NOWORDS end
  local w = wordsCache[t]
  if w then return w end
  if wordsN >= WORDS_KEEP then wordsCache, wordsN = {}, 0 end
  w = Engine.Words(t)
  wordsCache[t], wordsN = w, wordsN + 1
  return w
end

-- dungeons: a "Run <X> with a group" step and the objective steps done inside ("Collect 10 Twilight Pendant (in
-- Blackfathom Deeps)"). Once you've been inside (any visit is your run - ns.char.dungeonsVisited) or skipped the run,
-- what's left inside waits ("later") instead of holding up the card. Back inside, it's current again.
function Engine.RunDungeon(s) return s and s.k == "goto" and (s.dungeon or tostring(s.text or ""):match("^Run (.-) with a group") or tostring(s.text or ""):match("^Run (.+)$")) or nil end
function Engine.InsideOf(s) return s and s.k == "obj" and tostring(s.text or ""):match("%(in (.-)%)$") or nil end
-- each quest's objective steps, by index - built once per step list (scanning the plan per hand-in was most of a
-- refresh on a long plan)
local objIndex, objIndexFor, objIndexGen = nil, nil, 0
function Engine.ObjStepsOf(q)
  local list = steps()
  if objIndexFor ~= list or objIndexGen ~= (list._gen or 0) then
    objIndex, objIndexFor, objIndexGen = {}, list, list._gen or 0
    for j, t in ipairs(list) do if t.k == "obj" and t.q then local l = objIndex[t.q]; if not l then l = {}; objIndex[t.q] = l end; l[#l + 1] = j end end
  end
  return objIndex[q] or {}
end
-- a visit marks one Run step (ns.char.ranRun[key]): the first one of that dungeon not run or skipped yet - a second
-- planned run of the same dungeon later stays to do. The mark carries the plan's stamp: a new plan made after the
-- run (drops still missing) has a run of its own to do
local function planStamp() return (BeelinePlan and BeelinePlan.generated) or (BeelineData and BeelineData.id) or 0 end
local function ran(i) local v = ns.char.ranRun and ns.char.ranRun[key(i)]; return v ~= nil and v == planStamp() end
-- the Run step an inside objective belongs to: the nearest one before it for that dungeon
local function runFor(j, name)
  local list = steps()
  for i = j - 1, 1, -1 do local d = Engine.RunDungeon(list[i]); if d and Engine.SamePlace(d, name) then return i end end
end
-- an inside objective (step j) waits for now: its run is done or skipped, and you're not in that dungeon
function Engine.DungeonLater(name, j)
  if not name or Engine.InDungeon(name) then return false end
  local r = j and runFor(j, name)
  return r and (ran(r) or ns.char.skipped[key(r)] or false) or false
end
local function recordDungeon()
  local name = ns.Dungeon.Here() -- which dungeon, by its instance id or the game's name for it (Dungeon.lua)
  if not name then return end
  -- the run the card shows, if it's this dungeon's; else the first of its runs not done yet (one you went ahead of
  -- is not the run you're starting)
  ns.char.ranRun = ns.char.ranRun or {}
  local shown = Engine.Shown and Engine.Shown()
  local list = steps()
  local s0 = shown and list[shown]
  local d0 = s0 and Engine.RunDungeon(s0)
  if d0 and Engine.SamePlace(d0, name) and not ran(shown) then ns.char.ranRun[key(shown)] = planStamp(); return end
  for i, s in ipairs(list) do
    local d = Engine.RunDungeon(s)
    if d and Engine.SamePlace(d, name) and not ran(i) and not ns.char.skipped[key(i)] and Engine.Status(i) ~= "done" then
      ns.char.ranRun[key(i)] = planStamp()
      return
    end
  end
end
local function dungeonSeen() pcall(recordDungeon) end -- (PLAYER_ENTERING_WORLD, ZONE_CHANGED_NEW_AREA: the end of this file)

-- status: "done", "todo", "blocked" (quest not in log), "wait" (level too low), "full" (a pick-up with your quest log
-- full: passed over like "wait", so the card goes to hand-ins and objectives first), "notready" (turn-in with objectives left),
-- "later" (left for your next run of a dungeon you've been in or skipped: passed over, like "wait")
-- a quest more than this many levels below you is left out: tools/campaign.js plans each zone with
-- minQuestLevel = level - 6 (it never sends you to one), and the route in game drops the same ones
Engine.OUTLEVEL = 6
-- the game's gray line: a quest this level or lower gives (next to) no XP at level L - 5 below you early on, 6-12
-- below later (the client's GetQuestGreenRange table)
local grayMemo = {}
function Engine.GrayAt(L)
  -- (your own level: the game's GetQuestGreenRange, so the gray line matches the quest log's colours; the table below
  -- for other levels. Memoized per level until you level: GrayAt runs for most steps on every look at the route)
  local v = grayMemo[L]
  if v then return v end
  v = L - (L < 6 and L or L < 40 and (math.floor(L / 10) + 5) or (math.floor(L / 5) + 1))
  if GetQuestGreenRange and UnitLevel and L == UnitLevel("player") then
    local ok, g = pcall(GetQuestGreenRange)
    if ok and tonumber(g) and g > 0 then v = L - g - 1 end
  end
  grayMemo[L] = v
  return v
end
ns.On("PLAYER_LEVEL_UP", function() Engine.GrayForget() end)
-- The game's red line: a quest 5 or more levels above you is red. Its work waits until you are within 4 levels of
-- it - and so do its pick-up and unfinished hand-in, as the planner's own gate keeps it out of reach until then. A
-- pick-up with nothing to fight (a delivery: no objective on the route) is still taken when the plan has it, unless
-- the step has no minLevel - then red is all we know. Only a player behind the plan's levels meets it.
-- -> the level it comes back at, or nil
function Engine.TooHigh(s, L)
  local ql = s and s.q and tonumber(s.level)
  if not ql then return nil end
  L = L or (UnitLevel and UnitLevel("player")) or 1
  if ql < L + 5 then return nil end
  local k = s.k
  if k == "obj" or (k == "turnin" and not State.QuestReady(s.q)) or (k == "accept" and (not s.minLevel or #Engine.ObjStepsOf(s.q) > 0)) then
    return ql - 4
  end
  return nil
end
-- are you bound at this bind step's place? (the bind's own name, the zone, or the map you were on when you bound)
function Engine.BoundAt(s, b)
  if not b then return false end
  if (s.bind and b == s.bind) or Engine.SamePlace(b, s.zone) then return true end
  local at = ns.char and ns.char.boundAt
  return at and at.name == b and at.m == s.m or false
end
-- Is your hearthstone set on map m, going by the name the game gives your bind (b)? The game names the town, inn or
-- capital, never the map, so: where you set it while the addon watched (ns.char.boundAt: that name on that map, and
-- then no other map), else the names this map's inn goes by: the step's own, the zone's, a bind stop of the plan
-- there, the flight point's town. No match is "not there": a hearth that isn't yours is never offered.
function Engine.BoundOn(m, b, s)
  if not (m and type(b) == "string" and b ~= "") then return false end
  local at = ns.char and ns.char.boundAt
  if at and at.m and at.name == b then return at.m == m end
  if s and (s.dest == b or s.text == b) then return true end
  local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(m)
  if info and info.name and Engine.SamePlace(b, info.name) then return true end
  for _, t in ipairs(steps()) do if t.k == "bind" and t.m == m and Engine.BoundAt(t, b) then return true end end
  for _, byMap in pairs(ns.FLIGHT_BY or {}) do
    for _, f in ipairs(byMap[m] or {}) do if f[4] and f[4]:match("^(.-),") == b then return true end end
  end
  return false
end
-- Can you take this hearth step? Only when the game says so: your hearthstone is set where the step goes (the plan
-- only assumed you set it at its bind stop) and it is off cooldown. Otherwise the step is passed and the way to the
-- stops after it is planned like any other trip (Engine.TravelFor). -> true, or false and why
local hearthMemo = setmetatable({}, { __mode = "k" })
function Engine.HearthUsable(i)
  local list = steps()
  local s = list[i]
  if not s then return false, "no such step" end
  local okB, b = pcall(GetBindLocation)
  if not okB or type(b) ~= "string" or b == "" then return false, "the game does not say where your hearthstone is set" end
  -- whether the step goes where the stone is set: worked out once per step and bind location (the route list asks
  -- about every hearth step on every refresh, and this walks the steps and the flight tables)
  local memo = hearthMemo[s]
  local there
  local at = ns.char and ns.char.boundAt -- (what the addon has learned about where the stone is set counts too)
  if memo and memo.b == b and memo.list == list and memo.at == at then there = memo.there else
    -- where the step goes: the plan says (bindMap), else the bind stop before it (plans from before that field)
    local m = s.bindMap
    if not m then for j = i - 1, 1, -1 do if list[j].k == "bind" then m = list[j].m; break end end end
    if m then there = Engine.BoundOn(m, b, s) else there = s.dest == b or Engine.SamePlace(b, s.dest or s.text) end
    hearthMemo[s] = { b = b, list = list, at = at, there = there }
  end
  if not there then return false, "your hearthstone is set in " .. b .. ", not there" end
  local cd = ns.HearthCooldown and ns.HearthCooldown()
  if type(cd) == "number" and cd > 0 then return false, "your hearthstone is on cooldown (" .. math.ceil(cd / 60) .. " min)" end
  return true
end
-- (said once per step and reason, and only for a step the card is about to reach: the list asks about every step)
local hearthSaid = setmetatable({}, { __mode = "k" })
local function hearthPassed(i, s, why)
  local c = Engine.current
  if hearthSaid[s] == why or not (c and i >= c and i <= c + 3) then return end
  hearthSaid[s] = why
  if ns.Why then ns.Why("hearth", "passed \"Hearth to " .. tostring(s.dest or s.text or "your inn") .. "\": " .. why .. "; the way there is planned like any other trip") end
end
-- the level a training stop is for: "level 8/10 spells" -> 10
function Engine.TrainLevel(s)
  if s.until_ then return tonumber(s.until_) end
  local best
  for n in tostring(s.text or ""):gmatch("%d+") do n = tonumber(n); if not best or n > best then best = n end end
  return best
end
-- Your XP per second at a level: Forever's pace, as the planner measured it - the median XP an hour of the plan's zone
-- routes for that level (ns.ZoneRoutesAt). Every price of time against XP goes through this (the solve's stops, a
-- leftover's trip, a hand-in now or later). Without zone routes (an old plan): a level every 1.5 h.
local paceMemo = {}
function Engine.XpPerSec(L)
  L = L or (UnitLevel and UnitLevel("player")) or 1
  local src = ns.Routes and ns.Routes()
  local m = paceMemo
  if m.src ~= src then paceMemo = { src = src }; m = paceMemo end
  if m[L] then return m[L] end
  local xs = {}
  for _, r in ipairs((ns.ZoneRoutesAt and ns.ZoneRoutesAt(L)) or {}) do if tonumber(r.xph) and r.xph > 0 then xs[#xs + 1] = r.xph end end
  local v
  if #xs > 0 then table.sort(xs); v = xs[math.floor((#xs + 1) / 2)] / 3600
  else v = ((UnitXPMax and UnitXPMax("player")) or 10000) / 5400 end
  m[L] = math.max(1, v)
  return m[L]
end
-- The one gray rule (Engine.GrayDrop): a quest gray to you - in your log or not - is off the route (no pick-up, no
-- objectives, no hand-in stop, and the quest log check says drop it) unless its chain leads to a quest that isn't gray
-- to you. "Leads to": the quests that need it, as far down as the chain goes (BeelineUnlocks - the plan's
-- chains - and the quest data's prerequisites, ns.QUEST_PRE, turned around), through gray links too. Only follow-ups
-- you can still take count: not done, not refused, not the other faction's or another class's (ns.QUEST_FOR), not
-- shut by an exclusive quest you have or did (ns.QUEST_EX), and not one another way in already opened. The
-- follow-up's own level decides: the plan's level for it, else the quest data's. One the plan has with no level
-- anywhere counts (the chain goes on past what we know); one only the quest data has, with no level, does not.
-- What a follow-up must be to keep its chain: the game's yellow and up (2 or fewer levels below you). The same line
-- decides what a chain is worth on Where to? (Engine.LeadsToWorth).
local function worthAt(L, lvl) return L >= lvl - 2 end
local levelOfQ, levelSrc, levelGen = {}, nil, 0
local function planLevel(q)
  local list = steps()
  if levelSrc ~= list or levelGen ~= (list._gen or 0) then
    levelOfQ, levelSrc, levelGen = {}, list, list._gen or 0
    for _, t in ipairs(list) do if t.q and tonumber(t.level) and t.level > 0 and not levelOfQ[t.q] then levelOfQ[t.q] = t.level end end
  end
  return levelOfQ[q]
end
local needersOf = State.NeedersOf
-- can you take follow-up d (reached from quest from), whatever its level?
local function takeable(d, from)
  if State.IsCompleted(d) or ns.Nope(d) then return false end
  local who = ns.QUEST_FOR and ns.QUEST_FOR[d]
  if who then
    local sd, cl = who:match("^(%a?):?(.*)$")
    if not State.ForMe(sd ~= "" and sd or nil, cl ~= "" and cl or nil) then return false end
  end
  for _, x in ipairs((ns.QUEST_EX and ns.QUEST_EX[d]) or {}) do if State.IsCompleted(x) or State.InLog(x) then return false end end
  -- (one of several ways in, and another one is done: it is open without from - from leads nowhere new)
  local pre = from and ns.QUEST_PRE and ns.QUEST_PRE[d]
  if pre and pre.s and #pre.s > 1 then
    local viaS = false
    for _, p in ipairs(pre.s) do if p == from then viaS = true end end
    if viaS then for _, p in ipairs(pre.s) do if p ~= from and State.IsCompleted(p) then return false end end end
  end
  return true
end
-- the highest level anything down q's chain has, whoever can take it (math.huge: a quest the plan has with no level):
-- fixed for a plan, so memoized per quest. A chain whose best is gray to you leads nowhere, and the costlier walk
-- below (your quests, your faction) is skipped
local bestMemo = {}
local function chainBest(q)
  local list, unl = steps(), BeelineUnlocks
  if bestMemo.list ~= list or bestMemo.gen ~= (list._gen or 0) or bestMemo.unl ~= unl or bestMemo.pre ~= ns.QUEST_PRE then bestMemo = { list = list, gen = list._gen or 0, unl = unl, pre = ns.QUEST_PRE } end
  local b = bestMemo[q]
  if b then return b end
  b = 0
  local seen, queue, head = { [q] = true }, { q }, 1
  while head <= #queue and head <= 400 do
    local x = queue[head]; head = head + 1
    for pass = 1, 2 do
      local ds = pass == 1 and unl and unl[x] or pass == 2 and needersOf(x) or nil
      for _, d in ipairs(ds or {}) do
        if not seen[d] then
          seen[d] = true; queue[#queue + 1] = d
          local L = planLevel(d) or (ns.QuestLevel and ns.QuestLevel(d))
          if not L and pass == 1 then L = math.huge end
          if L and L > b then b = L end
        end
      end
    end
  end
  bestMemo[q] = b
  return b
end
-- remembered per level, per plan and per look at your quests (Engine.GrayForget: each refresh, each full look at the
-- log): the route asks about every gray step on every refresh
local leadsMemo = { lvl = -1, gen = -1 }
Engine.grayGen = 0
-- (also drops each level's gray line: Engine.GrayAt)
function Engine.GrayForget() Engine.grayGen = Engine.grayGen + 1; wipe(grayMemo) end
-- -> the quest q's chain leads to that is still worth XP to you at level lvl (the nearest such), or nil
function Engine.LeadsTo(q, lvl)
  if not q then return nil end
  lvl = lvl or (UnitLevel and UnitLevel("player")) or 1
  local list = steps()
  local m = leadsMemo
  if m.lvl ~= lvl or m.gen ~= Engine.grayGen or m.list ~= list or m.listGen ~= (list._gen or 0) then
    m = { lvl = lvl, gen = Engine.grayGen, list = list, listGen = list._gen or 0 }; leadsMemo = m
  end
  local hit = m[q]
  if hit ~= nil then return hit or nil end
  local best = chainBest(q)
  if best == 0 or (best ~= math.huge and not worthAt(best, lvl)) then m[q] = false; return nil end
  Engine.grayWalks = (Engine.grayWalks or 0) + 1 -- (counted: the perf battery)
  local seen, queue, head, found = { [q] = true }, { q }, 1, false
  local x
  local function visit(d, plan)
    if found or seen[d] then return end
    seen[d] = true
    if not takeable(d, x) then return end
    local L = planLevel(d) or (ns.QuestLevel and ns.QuestLevel(d))
    if (not L and plan) or (L and worthAt(L, lvl)) then found = d; return end
    queue[#queue + 1] = d -- (gray itself: on down its chain)
  end
  while head <= #queue and head <= 200 and not found do
    x = queue[head]; head = head + 1
    for _, d in ipairs((BeelineUnlocks and BeelineUnlocks[x]) or {}) do visit(d, true) end
    for _, d in ipairs(needersOf(x) or {}) do visit(d, false) end
  end
  m[q] = found
  return found or nil
end
function Engine.LeadsToWorth(q, lvl) return Engine.LeadsTo(q, lvl) ~= nil end
-- The rule itself. Quest q (level ql: the step's or your log's; else the plan's, else the quest data's) at your level
-- lvl -> true: off the route, drop it; false, d: gray but kept - it leads to d; false: not gray (or no level known)
function Engine.GrayDrop(q, lvl, ql)
  if not q or q <= 0 then return false end
  lvl = lvl or (UnitLevel and UnitLevel("player")) or 1
  ql = tonumber(ql) or planLevel(q) or (ns.QuestLevel and ns.QuestLevel(q))
  if not ql or ql <= 0 or ql > Engine.GrayAt(lvl) then return false end
  local d = Engine.LeadsTo(q, lvl)
  if d then return false, d end
  return true
end
-- a step of a quest the gray rule takes off the route: its pick-up, objectives and hand-in, in your log or not
function Engine.Outlevelled(s)
  if not (s and s.q and tonumber(s.level) and s.level > 0) then return false end
  local lvl = UnitLevel("player") or 1
  if s.level > Engine.GrayAt(lvl) or State.IsCompleted(s.q) then return false end
  -- a gray quest is never picked up, not even for the chain it opens; and when it isn't in your log, none of its
  -- steps count either. One already in your log keeps its objectives and hand-in while its chain is worth it (GrayDrop)
  if not State.OnQuest(s.q) then return true end
  return Engine.GrayDrop(s.q, lvl, s.level) == true
end
-- a finished hand-in the gray rule took off: Outlevelled, said apart in reports (only true where Outlevelled is:
-- statusRaw asks Outlevelled alone)
function Engine.GrayHandIn(s)
  if not (s and s.k == "turnin" and s.q and tonumber(s.level) and s.level > 0) then return false end
  if not State.QuestReady(s.q) then return false end
  return Engine.Outlevelled(s)
end
-- Your place in the built-in plan. It is one path from level 1 to 60, and every step has a level: the level the plan
-- has you at when you get there (lvl; a step without one - a flight, a flight path, a hearth - takes the level of the
-- next step that has one: travel belongs to what it leads to). What the plan does below your place is behind you:
-- passed, whatever kind of step it is. Your place is the higher of two things:
--   where you joined: someone who meets the plan at 30 (installed the addon then, or came back to it) joins at the
--     trip during which the plan reaches 30. Everything before that trip is behind them for good, quests in their log
--     included - those are theirs to finish or drop, like any quest that is not on the route (a finished one gets a
--     hand-in stop where the route passes its NPC, and the quest log check lists them all). Kept in ns.char.join.
--   JOIN_GAP levels below you: rested XP and dungeons put you ahead of the plan, and up to 3 levels ahead you are
--     still doing what it says. Further ahead than that, what it does down there is passed - but a quest in your log
--     stays, here: you picked it up on the plan.
-- A quest goes as a whole: with its pick-up behind you (and the quest not yours), its other steps are too; a pick-up
-- that needs a quest whose hand-in is behind you is not offered; and a quest in your log goes when something still to
-- do for it lies before the trip you joined at. Your own plan (the companion's) is made from your save: none of this.
Engine.JOIN_GAP = 3
local planCache = setmetatable({}, { __mode = "k" })
-- is this step a trip (a flight - boats are k="fly", boat=true - or a hearth)? It ends a stretch of the plan
function Engine.IsTrip(s) return s.k == "fly" or s.k == "hearth" end
local isTrip = Engine.IsTrip
local function planIndex()
  local list = steps()
  local c = planCache[list]
  if c and c.gen == (list._gen or 0) then return c, list end
  -- (binds: the bind stops in order; trainAfter[i]: the lowest level a training stop after step i is for;
  -- trainLo[i]: the lowest level training stop i names ("level 34/36" is 34) - read once, not on every status)
  c = { gen = list._gen or 0, idx = {}, eff = {}, accept = {}, acceptMore = {}, turnin = {}, at = {}, binds = {}, trainAfter = {}, trainLo = {} }
  local nxt, train
  for i = #list, 1, -1 do
    local s = list[i]
    c.trainAfter[i] = train
    if s.k == "train" then
      local L = Engine.TrainLevel(s); if L and (not train or L < train) then train = L end
      local lo; for n in tostring(s.text or ""):gmatch("%d+") do n = tonumber(n); if not lo or n < lo then lo = n end end
      c.trainLo[i] = lo
    end
    if s.k == "bind" then table.insert(c.binds, 1, i) end
    c.idx[s] = i
    if tonumber(s.lvl) then nxt = s.lvl end
    c.eff[i] = nxt
    if s.q and s.q > 0 then
      if s.k == "accept" then
        -- (a quest picked up at more than one step - a stop added for its giver: the others, Engine.PreReachable)
        if c.accept[s.q] then local m = c.acceptMore[s.q]; if not m then m = {}; c.acceptMore[s.q] = m end; m[#m + 1] = c.accept[s.q] end
        c.accept[s.q] = i
      elseif s.k == "turnin" and not s.inserted then c.turnin[s.q] = i end -- (the first of each: this runs backwards)
    end
  end
  local last -- the last steps of a plan, with no stamped step after them: the level before
  for i = 1, #list do if c.eff[i] then last = c.eff[i] else c.eff[i] = last end end
  planCache[list] = c
  return c, list
end
Engine._planIndex = planIndex -- (Engine/Trips.lua)
-- you skipped the plan's own trip into step s's zone (the flight to the Hinterlands, then its quests one by one - tester):
-- the card heads the step itself, not that trip again ("Fly to Aerie Peak" stayed the headline at every skip, as if the
-- skip did nothing). Back from s through its visit (steps with no zone go with it) to the trip that starts it.
local TRIP_INTO = { fly = true, hearth = true, boat = true }
function Engine.SkippedTripInto(s)
  if not (s and s.zone and ns.char and ns.char.skipped) then return false end
  local c, list = planIndex(); local i = c.idx[s]; if not i then return false end
  for j = i - 1, math.max(1, i - 200), -1 do
    local t = list[j]
    if TRIP_INTO[t.k] and t.dest then return t.dest == s.zone and ns.char.skipped[key(j)] == true end
    if t.zone and t.zone ~= s.zone then return false end
  end
  return false
end
-- the level the plan has you at, at step i (nil on a plan without levels)
function Engine.PlanLevel(i) return (planIndex()).eff[i] end
-- the level training stop i is for: the lowest its text names ("Train level 34/36 spells": 34), or its until_ when higher -
-- below it the trainer has nothing for you (nil: no level known)
function Engine.TrainFrom(i)
  local s = steps()[i]
  if not (s and s.k == "train") then return nil end
  local lo, u = (planIndex()).trainLo[i], tonumber(s.until_)
  if u and (not lo or u > lo) then return u end
  return lo
end
-- the step you joined at: the trip (flight, hearth, boat) into the stretch where the plan first reaches that level,
-- so you start a stretch from its beginning - its pick-ups before the things they are for. nil: nothing to pass
local function joinStep(level)
  local c, list = planIndex()
  local at = c.at[level]
  if at == nil then
    at = false
    for i = 1, #list do
      if tonumber(list[i].lvl) and list[i].lvl >= level then
        at = 1
        for j = i, 1, -1 do if isTrip(list[j]) then at = j; break end end
        break
      end
    end
    c.at[level] = at
  end
  return at or nil
end
-- the level you joined the built-in plan at, and the step that goes with it (nil, nil: you follow it from the start,
-- or it isn't known yet - Engine.FindPlace)
function Engine.Place()
  local key = ns.planKey and ns.planKey.starter
  local j = key and ns.char and ns.char.join
  if Engine.noPlace or not (j and j.plan == key and tonumber(j.level) and j.level > 1) then return nil end
  return j.level, joinStep(j.level)
end
-- Where you start. The trip you join at is the plan at your level, but the plan's stretches of the JOIN_GAP levels
-- before it are still good for you, and one may be worth more from where you stand. So when you join, each of those
-- stretches (the steps between two trips) is priced like the planner prices a zone - the XP of the quests you can
-- still do in it, over the time they take plus the trip there - and the best one is where you start
-- (ns.char.join.first), before the trip you joined at. Value decides, not distance.
-- Rough numbers: quest XP from the quest's level (less far below you), a pick-up or hand-in 10 s, an objective 2 min,
-- the walk between steps at running or riding speed, the trip from Travel.Plan.
Engine.START_HORIZON = 3600 -- stretches are compared by the XP they bring in this many seconds (a short one, then the plan)
Engine.START_MIN_TURNINS = 5 -- a stretch with fewer hand-ins is no place to start (the planner's own floor for a zone)
local function firstTrip(c, list)
  if not c.trip1 then c.trip1 = #list + 1; for j = 1, #list do if isTrip(list[j]) then c.trip1 = j; break end end end
  return c.trip1
end
local function stretchEnd(list, from) for j = from + 1, #list do if isTrip(list[j]) then return j - 1 end end return #list end
local function questXP(ql, L)
  local xp = 100 + 60 * ql + 0.9 * ql * ql
  local d = L - ql
  return xp * (d <= 5 and 1 or d == 6 and 0.8 or d == 7 and 0.6 or d == 8 and 0.4 or d == 9 and 0.2 or 0.1)
end
Engine.QuestXP = questXP
-- the next thing to do for a quest in your log: its first unfinished objective on the route, else its hand-in
local function nextStep(q, c, list)
  if not State.QuestReady(q) then
    for _, j in ipairs(Engine.ObjStepsOf(q)) do
      local o = Engine.ObjectiveFor(list[j])
      if not (o and o.finished) then return j end
    end
    return nil
  end
  return c.turnin[q]
end
-- what a stretch is worth to you now: XP, seconds of work, hand-ins, the first step with a place
function Engine.StretchWorth(from, to)
  local c, list = planIndex()
  local L = UnitLevel("player") or 1
  local speed = (ns.Travel and ns.Travel.Speed and ns.Travel.Speed()) or 7
  local xp, secs, n, spot = 0, 0, 0, nil
  -- a quest you can do there: in your log with its next step there, or picked up in this stretch with every quest it
  -- needs handed in by then
  local can = {}
  local function doable(q)
    if can[q] == nil then
      local a = c.accept[q]
      if State.OnQuest(q) then
        local n = nextStep(q, c, list)
        can[q] = n ~= nil and n >= from and n <= to
      else
        can[q] = a ~= nil and a >= from and a <= to
      end
      if can[q] and not State.OnQuest(q) then
        for _, p in ipairs(Engine.PrereqsOf(q)) do
          local t = c.turnin[p]
          if not State.IsCompleted(p) and not (t and t >= from and t <= to and (State.OnQuest(p) or (c.accept[p] or 0) >= from)) then can[q] = false; break end
        end
      end
    end
    return can[q]
  end
  for j = from, to do
    local s = list[j]
    local q = s.q and s.q > 0 and s.q or nil
    if q and not State.IsCompleted(q) and not Engine.Outlevelled(s) and not Engine.TooHigh(s, L) then
      if doable(q) then
        if not (s.k == "accept" and State.OnQuest(q)) then
          spot = spot or (s.m and s.x and not s.unknown and s) or nil
          secs = secs + (tonumber(s.walk) or 80) / speed + (s.k == "obj" and 120 or 10)
          if s.k == "turnin" and tonumber(s.level) and s.level > 0 then xp = xp + questXP(s.level, L); n = n + 1
          -- (a quest picked up here and handed in after the stretch: its XP counts here too, else a zone whose quests
          -- end in town after a trip read as all work and no XP)
          elseif s.k == "accept" and tonumber(s.level) and s.level > 0 and (c.turnin[q] or 0) > to then xp = xp + questXP(s.level, L); n = n + 1 end
        end
      end
    end
  end
  return xp, secs, n, spot
end
-- the stretch to start in, for someone joining at this level: its first step's key (nil: the trip you joined at), and
-- the stretches priced { from, to, zone, xph, extra (s of travel it adds), work (s), turnins, plan }, best first.
-- Priced: the plan's trip at your level (its XP over its work and the trip there), and every other stretch within
-- reach of your level (OUTLEVEL below you up to your level) with START_MIN_TURNINS hand-ins you can still do: its XP
-- over its work and the travel it ADDS (there, then on to the plan's trip, less the trip you'd make anyway).
function Engine.ChooseStart(level)
  local c, list = planIndex()
  local at = joinStep(level)
  local m, x, y = State.Position()
  if not (at and at > 1 and m and x and ns.Travel and ns.Travel.Plan) then return nil, {} end
  local L = UnitLevel("player") or 1
  local function trip(a, b)
    local ok, _, secs = ns.Call(ns.Travel.Plan, { m = a.m, x = a.x, y = a.y }, { m = b.m, x = b.x, y = b.y, name = b.zone })
    return ok and tonumber(secs) or nil
  end
  local me = { m = m, x = x, y = y }
  local priced = {}
  -- what the plan's stretches in the zone you stand in hold for you, from step 'from' on: the plan comes back to a zone
  -- after a trip (training, a hand-in in town), and one stretch alone undersold staying. Only stretches up to JOIN_GAP
  -- levels above you, while their work fits START_HORIZON
  local function worth(from, last)
    local xp, work, n, spot = Engine.StretchWorth(from, last)
    if not (spot and spot.m == m) then return xp, work, n, spot end
    for j = last + 1, #list do
      if work >= Engine.START_HORIZON or (c.eff[j] or 0) > L + Engine.JOIN_GAP then break end
      if isTrip(list[j]) and Engine.StretchOn(j, m) then
        local e2 = stretchEnd(list, j)
        local x2, w2, n2 = Engine.StretchWorth(j, e2)
        xp, work, n = xp + x2, work + w2, n + n2
      end
    end
    return xp, work, n, spot
  end
  -- the plan's trip at your level
  local to = stretchEnd(list, at)
  local xpD, workD, nD, spotD = worth(at, to)
  -- (nothing left for you in that stretch - its quests done, gray, or picked up before it: the plan goes on to the
  -- next one with something, and that is what the stretches around you are weighed against)
  for _ = 1, 8 do
    if spotD or to >= #list or (c.eff[to + 1] or 0) > L + Engine.JOIN_GAP then break end
    local nx = to + 1
    to = stretchEnd(list, nx)
    xpD, workD, nD, spotD = worth(nx, to)
  end
  local tripD = spotD and trip(me, spotD)
  if not tripD then return nil, {} end -- no way there from here (or nothing to do there): nothing to compare with
  priced[1] = { from = at, to = to, zone = spotD.zone or list[at].dest or "?", xph = math.floor(xpD / (workD + tripD) * 3600), extra = math.floor(tripD), work = math.floor(workD), turnins = nD, plan = true }
  local function price(from)
    local last = stretchEnd(list, from)
    local xp, work, n, spot = worth(from, last)
    if not spot or n < Engine.START_MIN_TURNINS then return end
    local there, on = trip(me, spot), trip(spot, spotD)
    if not (there and on) then return end
    local extra = math.max(0, there + on - tripD)
    priced[#priced + 1] = { from = from, to = last, zone = spot.zone or list[from].dest or "?", xph = math.floor(xp / (work + extra) * 3600), extra = math.floor(extra), work = math.floor(work), turnins = n }
  end
  -- (and a stretch in the zone you stand in that the plan does up to JOIN_GAP levels above you: its quests are at your
  -- level too)
  for j = 1, #list do
    local e = c.eff[j] or 0
    if j > at and e > L + Engine.JOIN_GAP then break end
    if j ~= at and (j == 1 or isTrip(list[j])) and e >= L - Engine.OUTLEVEL and (e <= L or Engine.StretchOn(j, m)) then price(j) end
  end
  -- compared over the same time (START_HORIZON): a stretch shorter than that is followed by the plan at the plan's own
  -- rate. Rates alone over-praised tiny stretches that are over before the hour is
  local planRate = priced[1].xph / 3600
  local H = Engine.START_HORIZON
  for _, p in ipairs(priced) do
    local t = p.work + p.extra
    local xp = p.xph / 3600 * t
    p.score = t >= H and p.xph or math.floor((xp + (H - t) * planRate) / H * 3600)
  end
  table.sort(priced, function(a, b) if a.score ~= b.score then return a.score > b.score end return (a.plan and 1 or 0) > (b.plan and 1 or 0) end)
  local best = priced[1]
  if best.plan then return nil, priced end
  return Engine.Key(best.from), priced
end
-- does the stretch from step i (a trip, or the plan's first step) work on map m? its trip goes there, or its first
-- steps with a place are there
function Engine.StretchOn(i, m)
  local list = steps()
  local s = list[i]
  if not (s and m) then return false end
  if isTrip(s) and s.to then return s.to == m end
  for j = i, math.min(#list, i + 6) do
    local t = list[j]
    if j > i and isTrip(t) then break end
    if t.m then return t.m == m end
  end
  return false
end
-- the stretch you start in (nil: none chosen, or it is not on this plan any more): its first and last step
function Engine.FirstStretch()
  local j = ns.char and ns.char.join
  local k = j and ns.planKey and j.plan == ns.planKey.starter and j.first
  if not k or Engine.noPlace then return nil end
  local c, list = planIndex()
  if c.firstKey ~= k then
    c.firstKey, c.firstFrom, c.firstTo = k, false, false
    for i = 1, #list do if Engine.Key(i) == k then c.firstFrom, c.firstTo = i, stretchEnd(list, i); break end end
  end
  return c.firstFrom or nil, c.firstTo or nil
end
-- the zone you are in (nil on a flight, or where the game gives no position): taken once per refresh (Engine.here)
function Engine.HereMap()
  if ns.Is and UnitOnTaxi and ns.Is(UnitOnTaxi, "player") then return nil end
  local ok, m = pcall(State.Position)
  return ok and m or nil
end
-- The part of the built-in plan behind you, by the place of a step alone: -> before(j), low(j) for this moment, and
-- the step you joined at
local passedPartFresh
-- (memoized on the plan's index: Engine.BehindYou asks for every step on every refresh, and the answer only moves
-- with your level, where you joined and the stretch you start in. The functions themselves are in the key: tests
-- stub them)
local function passedPart(c, list)
  local L = UnitLevel("player") or 1
  local j = ns.char and ns.char.join
  local m = c.pp
  if m and m.L == L and m.place == Engine.Place and m.first == Engine.FirstStretch and m.noPlace == Engine.noPlace
    and m.key == (ns.planKey and ns.planKey.starter) and m.jl == (j and j.level) and m.jp == (j and j.plan) and m.jf == (j and j.first) then
    return m.before, m.low, m.at
  end
  local before, low, at = passedPartFresh(c, list, L)
  c.pp = { L = L, place = Engine.Place, first = Engine.FirstStretch, noPlace = Engine.noPlace, key = ns.planKey and ns.planKey.starter,
    jl = j and j.level, jp = j and j.plan, jf = j and j.first, before = before, low = low, at = at }
  return before, low, at
end
function passedPartFresh(c, list, L)
  local _, at = Engine.Place()
  local f1, f2 = nil, nil
  if at then f1, f2 = Engine.FirstStretch() end
  -- before the trip you joined at, and not in the stretch you start in - nor a quest in the zone you joined in, at
  -- your level (else that zone's quests sat behind you and came back one by one as extras, the card jumping between them)
  -- (the zone of your place: the first step there with one - you join at a trip, and a trip has none. A stretch
  -- chosen after the trip you joined at is where you joined, not the trip's zone, which you skip for now; a stretch
  -- chosen before the trip keeps the trip's zone: the plan goes there next)
  local atZone
  local z0 = (f1 and at and f1 > at) and f1 or at
  if z0 then for k = z0, math.min(#list, z0 + 40) do if list[k].zone then atZone = list[k].zone; break end end end
  local function before(j)
    if not (at ~= nil and j < at and not (f1 and j >= f1 and j <= f2)) then return false end
    -- (the quest's own level: one far below you stays behind, wherever the plan put it)
    local t = list[j]
    local ql = tonumber(t.level) or c.eff[j]
    if atZone and t.q and t.q > 0 and t.zone == atZone and (ql == nil or ql >= L - Engine.JOIN_GAP) then return false end
    return true
  end
  -- below your place: that, or more than JOIN_GAP levels below you (not while you are still in the plan's first
  -- stretch, the start zone: its chains lead out of it, and at 5 nothing of it is behind you)
  local start = at == nil and joinStep(L) == 1
  local function low(j)
    if before(j) then return true end
    local e = c.eff[j]
    return (e and e < L - Engine.JOIN_GAP and not (start and j < firstTrip(c, list))) or false
  end
  return before, low, at
end
-- Is step j in the part of the plan behind you by its place alone, whatever its quest's state? Engine.BehindYou says
-- no for a quest you completed (its steps are done anyway), so InsertStop needs this to not price the gap between two
-- such done steps as "the route passes by". -> a function of j for this moment, or nil
function Engine.PassedFn()
  if Engine.noPlace or not (ns.planKey and ns.planKey.starter) then return nil end
  if BeelineData and BeelineData.zoneRoute then return nil end
  local c, list = planIndex()
  local _, low = passedPart(c, list)
  return low
end
-- planOnly: as the plan sees it, without the live solve's pick-up from behind you (Next.taken) - Engine.Compute
-- (each answer is kept for the rest of the outermost call: a step asks its pick-up, which asks the hand-in of every
-- earlier quest of its chain, and so on - millions of calls over a long play otherwise. Nothing it reads changes
-- during one call.) Inside a refresh (or a route job's pass) the answers are kept as long as Engine.Status's batch
-- is, for the same live pick-up, zone and place. The memos are kept tables, wiped for reuse: no garbage per call.
local behindYouRaw, bmemo
local batch -- (Engine.Status's, below)
local CALL = { p = {}, n = {} }
local BATCH = { p = {}, n = {} }
local function clear(m) if m.used then wipe(m.p); wipe(m.n); m.used = nil end end
function Engine.BehindYou(s, planOnly)
  if s == nil then return false end
  if batch and not bmemo then
    local m = BATCH
    local taken, L = ns.Next and ns.Next.taken, UnitLevel("player")
    if not (batch.by and m.owner == batch and m.taken == taken and m.L == L and m.here == Engine.here and m.noPlace == Engine.noPlace) then
      clear(m)
      m.owner, m.taken, m.L, m.here, m.noPlace = batch, taken, L, Engine.here, Engine.noPlace
      batch.by = true -- (gone when the batch is wiped: the memo goes with it)
    end
    local hit = (planOnly and m.p or m.n)[s]
    if hit ~= nil then return hit end
    bmemo = m
    local ok, v = pcall(Engine.BehindYou, s, planOnly)
    bmemo = nil
    if not ok then error(v, 0) end
    return v
  end
  if bmemo then
    local t = planOnly and bmemo.p or bmemo.n
    local v = t[s]
    if v == nil then v = behindYouRaw(s, planOnly); t[s] = v; bmemo.used = true end
    return v
  end
  bmemo = CALL
  local ok, v = pcall(behindYouRaw, s, planOnly)
  bmemo = nil
  clear(CALL)
  if not ok then error(v, 0) end
  return v
end
-- a pass over many steps that changes nothing between them (Engine.InsertStop's gaps, the hand-ins applyInserts looks
-- at): its own memo, m = Engine.BehindMemo(name), so each chain is walked once for the pass, not once a step. Set only
-- for each call - a route job's pass pauses between them, and nothing else may read it then (in a route job's pass: a
-- memo of its own; otherwise the kept one of that name, wiped)
local PASS = {}
function Engine.BehindMemo(name)
  if ns.sliceCo and coroutine.running() == ns.sliceCo then return { p = {}, n = {} } end
  local m = PASS[name or ""]
  if not m then m = { p = {}, n = {} }; PASS[name or ""] = m end
  clear(m)
  return m
end
function Engine.BehindYouIn(m, s, planOnly)
  if bmemo or batch or s == nil then return Engine.BehindYou(s, planOnly) end
  bmemo = m
  local ok, v = pcall(Engine.BehindYou, s, planOnly)
  bmemo = nil
  if not ok then error(v, 0) end
  return v
end
function behindYouRaw(s, planOnly)
  if Engine.noPlace or not (s and ns.planKey and ns.planKey.starter) then return false end
  -- (a zone you picked has nothing behind you: you chose to go there - its steps all read "done" when you came back to it)
  if BeelineData and BeelineData.zoneRoute then return false end
  if not planOnly and ns.Next and ns.Next.taken == s then return false end -- (picked up again by the live solve: right here and worth it)
  if s.side then return false end -- (a stop added for a quest giver next to you is where you are, wherever it lands in the plan)
  local c, list = planIndex()
  local i = c.idx[s]
  if not i then return false end
  local before, low, at = passedPart(c, list)
  local q = s.q and s.q > 0 and s.q or nil
  if not q then
    if low(i) then return true end
    if s.k == "hearth" then
      -- a hearth to an inn the plan bound you at in a part that is behind you: you are not bound there
      for j = i - 1, 1, -1 do
        local t = list[j]
        if t.k == "bind" then return Engine.BehindYou(t, planOnly) and not Engine.BoundAt(t, GetBindLocation and GetBindLocation()) end
      end
    end
    return false
  end
  if State.IsCompleted(q) then return false end
  if State.OnQuest(q) then
    -- in your log. Following the plan, or picked up since you joined it: the plan's, wherever it leads
    local had = at and ns.char.join and ns.char.join.had
    if s.k == "accept" or s.inserted or not (had and had[q]) then return false end -- (a stop added for it is on your way)
    -- yours from before you joined: on the plan if what is left of it is ahead of you - or it is finished and its
    -- hand-in is in the zone you are in (handed in first)
    local n = nextStep(q, c, list)
    if not n then return before(i) end
    if not before(n) then return false end
    return not (Engine.here ~= nil and list[n].k == "turnin" and list[n].m == Engine.here)
  end
  if s.k ~= "accept" then
    -- a quest goes as a whole: with its pick-up behind you, its other steps are too
    local a = c.accept[q]
    if a and a ~= i then return Engine.BehindYou(list[a], planOnly) end
    return low(i)
  end
  if low(i) then return true end
  -- it needs a quest whose hand-in is behind you: not offered. (BeelineUnlocks is the whole chain before it; it
  -- lists "any one of" with "all of", so a quest with two ways in can be passed here though one of them is done)
  for _, p in ipairs(Engine.PrereqsOf(q)) do
    if not State.IsCompleted(p) then
      local t = c.turnin[p]
      if t and t < i and Engine.BehindYou(list[t], planOnly) then return true end
    end
  end
  return false
end
-- a breadcrumb whose quest is already yours (in your log or done): the game no longer offers it (ns.BREADCRUMBS)
-- a quest some other quest you took or did shuts (its breadcrumb's target, or an exclusive alternative): passed over
local function shutBy(tbl, s)
  local others = s and s.q and tbl and tbl[s.q]
  if not others or State.OnQuest(s.q) or State.IsCompleted(s.q) then return false end
  for _, t in ipairs(others) do if State.OnQuest(t) or State.IsCompleted(t) then return true end end
  return false
end
function Engine.Breadcrumbed(s) return shutBy(ns.BREADCRUMBS, s) end
-- a quest one of whose alternatives is yours (in your log or done): one quest given in several towns, and you took it
-- in another - the game no longer offers this one, so none of its steps is left to do (ns.QUEST_EX, QuestData.lua)
function Engine.Excluded(s) return shutBy(ns.QUEST_EX, s) end
-- a quest whose earlier chain quest you skipped (Skip on its pick-up), or said you're not doing, or that is itself cut
-- so: the game will never offer it. By the quest data's prerequisites (ns.QUEST_PRE: all of g, one of s - every one of
-- s cut), not BeelineUnlocks (it mixes "any one of" with "all of"). Deep: chains run to eight quests and more.
local function cutQuest(q, depth)
  if State.IsCompleted(q) then return false end
  -- (the other faction's copy of a quest - ns.QUEST_SIDE - is never yours, so it cuts what needs it)
  local side = ns.QUEST_SIDE and ns.QUEST_SIDE[q]
  if side and side ~= (State.MyFaction() or "A") then return true end
  -- (a gray quest the gray rule drops, in your log or not, cuts what needs it: the chain goes as a whole, kept only
  -- when a follow-up is yellow to you, Engine.LeadsTo. Only a quest your plan has, at its level there: one the plan
  -- doesn't have is left to the rules below)
  local L = planLevel(q)
  if L and Engine.GrayDrop(q, nil, L) == true then return true end
  if State.OnQuest(q) then return false end
  -- (and a gray quest not in your log is never picked up, whatever it leads to - Engine.Outlevelled - so what needs it
  -- can't be had either)
  if L and L <= Engine.GrayAt((UnitLevel and UnitLevel("player")) or 1) then return true end
  if ns.Nope(q) then return true end
  -- (an exclusive alternative of it you have or did shuts it, so what needs it goes too)
  local ex = ns.QUEST_EX and ns.QUEST_EX[q]
  if ex then for k = 1, #ex do if State.IsCompleted(ex[k]) or State.OnQuest(ex[k]) then return true end end end
  local a = (planIndex()).accept[q]
  if a and ns.char.skipped[key(a)] then return true end
  if ns.char.skipQ and ns.char.skipQ[q] then return true end
  return depth < 12 and Engine.ChainCut(q, depth + 1) or false
end
-- (a quest the game showed you on offer - a giver listed it, or the map's "!" - is offered whatever the quest data says
-- it needs.) Counted loops, no "pre.g or {}": statusRaw asks this of most steps on every look at the route, and a
-- table or ipairs iterator per ask was half its garbage.
function Engine.ChainCut(q, depth)
  local pre = q and ns.QUEST_PRE and ns.QUEST_PRE[q]
  if not pre then return false end
  local av = ns.char and ns.char.avail
  if av and av.seen and av.seen[q] then return false end
  depth = depth or 0
  -- (kept with the batch's statuses, by quest and depth: a shared prerequisite is walked once per batch)
  local memo = batch and batch.cut
  if batch and not memo then memo = {}; batch.cut = memo end
  local mk = q * 16 + depth
  if memo then local v = memo[mk]; if v ~= nil then return v end end
  local v = false
  local g, s = pre.g, pre.s
  if g then for k = 1, #g do if cutQuest(g[k], depth) then v = true; break end end end
  if not v and s and #s > 0 then
    v = true
    for k = 1, #s do if not cutQuest(s[k], depth) then v = false; break end end
  end
  if memo and batch and batch.cut == memo then memo[mk] = v end
  return v
end
-- a quest whose prerequisites are not handed in, one of them (or one of theirs, up the chain) in your log unfinished:
-- the game offers it after that hand-in (ns.QUEST_PRE). Counted loops, no table per ask: statusRaw asks it of every
-- pick-up with a prerequisite
local function pendingPre(p, depth)
  return not State.IsCompleted(p) and (State.OnQuest(p) or (depth < 6 and Engine.WaitsOnLog(p, depth + 1)))
end
-- the prerequisites q still needs (ns.QUEST_PRE: all of g, one of s), each one you can still get on this route: in
-- your log, or with a hand-in on the route. On a zone you picked, a hand-in on it is enough (its pick-up may be on the
-- main route). On any other plan the quest's pick-up must still be ahead: one with every pick-up step passed over -
-- behind you, cut by its own chain - is never taken, so it is never handed in either (They Call Him Smiling Jim
-- skipped and James Hyal's pick-up behind you: Suspicious Hoofprints, which needs one of them, stayed on the card -
-- mutate --play 7). One the giver didn't offer you is off the route only until your next level (Availability): its
-- chain stays. A quest the plan has no pick-up step for (an item starts it, or the plan never has it) is taken as
-- gettable, as before. (reachDepth: a loop in the quest data can't recurse for ever - past it, gettable)
local reachDepth = 0
local function pickUpAhead(c, p)
  local a = c.accept[p]
  if not a then return true end
  if ns.Avail and ns.Avail.Unavailable(p) then return true end
  if Engine.Status(a) ~= "done" then return true end
  local more = c.acceptMore[p]
  if more then for n = 1, #more do if Engine.Status(more[n]) ~= "done" then return true end end end
  return false
end
local function preGettable(p)
  if State.IsCompleted(p) or State.OnQuest(p) then return true end
  local c = planIndex()
  if BeelineData and BeelineData.zoneRoute then return c.turnin[p] ~= nil end
  if reachDepth > 12 then return true end
  reachDepth = reachDepth + 1
  local ok, v = pcall(pickUpAhead, c, p)
  reachDepth = reachDepth - 1
  if not ok then error(v, 0) end
  return v
end
function Engine.PreReachable(q)
  local pre = ns.QUEST_PRE and ns.QUEST_PRE[q]
  if not pre then return true end
  local g, s = pre.g, pre.s
  if g then for n = 1, #g do if not preGettable(g[n]) then return false end end end
  if s and #s > 0 then
    for n = 1, #s do if preGettable(s[n]) then return true end end
    return false
  end
  return true
end
-- a quest not in your log whose prerequisites are not met and can't be got on this route (none in your log, none still
-- to be picked up and handed in on it - Engine.PreReachable): the giver never has it for you, so none of its steps is
-- left - its pick-up, its objectives, its hand-in, and the trips to them (cutting only the pick-up left trips to its
-- objectives). A zone you picked first (its prerequisites on the level 32 route), then the built-in plan too (an
-- earlier quest skipped, the other way in behind you).
-- (A quest the game showed on offer anyway - Availability - is taken as offered.)
function Engine.Unreachable(q)
  if not (BeelineData and ns.QUEST_PRE and ns.QUEST_PRE[q]) then return false end
  if ns.char and ns.char.avail and ns.char.avail.seen and ns.char.avail.seen[q] then return false end
  return not State.PrereqsMet(q) and not Engine.PreReachable(q)
end
function Engine.WaitsOnLog(q, depth)
  local pre = ns.QUEST_PRE and ns.QUEST_PRE[q]
  if not pre then return false end
  depth = depth or 0
  local g, s = pre.g, pre.s
  if g then for n = 1, #g do if pendingPre(g[n], depth) then return true end end end
  if s and #s > 0 then
    for n = 1, #s do if State.IsCompleted(s[n]) then return false end end -- (one of them is in: met)
    for n = 1, #s do if pendingPre(s[n], depth) then return true end end
  end
  return false
end
-- a pick-up that reads "wait" (statusRaw) for a quest in your log, not for your level: statusRaw's own order - the
-- level checks come first, and on a zone you picked the wait is State.PrereqsMet's. For the live solve, which takes it
-- as a not-offered pick-up: its window ends there (Next.Pick), and a visit that hands that quest in takes it after
-- (Next.VisitHere). Skipped as a level wait, the window ran past every chain's next pick-up (2x solve time). Asked
-- only of a "wait"
function Engine.WaitsForHandIn(s)
  if not (s and s.k == "accept") or (BeelineData and BeelineData.zoneRoute) then return false end
  if s.minLevel and UnitLevel("player") < s.minLevel then return false end
  return not Engine.TooHigh(s)
end
local PVP = ns.PVP_QUESTS -- (PvpQuests.lua loads before this file: one table, read per step)
-- steps whose status was worked out, ever (the perf battery counts them per moment, tests/_perf.lua "status")
Engine.statusN = 0
local function statusRaw(i)
  Engine.statusN = Engine.statusN + 1
  local s = steps()[i]
  if not s then return "done" end
  local id = key(i)
  if ns.char.manualDone[id] or ns.char.skipped[id] then return "done" end
  -- (a pick-up you skipped on another route: the quest is skipped, whichever route shows it - Engine.Skip)
  if s.k == "accept" and s.q and ns.char.skipQ and ns.char.skipQ[s.q] and not State.OnQuest(s.q) then return "done" end
  if s.q and ns.Nope(s.q) then return "done" end -- you said you're not doing this quest
  if s.side and s.away and s.k == "accept" then return "done" end -- a side quest offered at its giver, and you walked on (Engine.SideOffer)
  -- the game did not offer it to you (Availability.lua): off the route until you level up or it is offered
  if s.q and ns.Avail and ns.Avail.Unavailable(s.q) and not State.OnQuest(s.q) and not State.IsCompleted(s.q) then return "done" end
  -- the NPC is unfriendly or hostile to you (Avail.ReadUnit, the game's own reaction): no pick-up from them and no hand-in
  -- to them can be done, whatever the quest data knows of reputations (an empty table when none: one look)
  if s.npc then
    local av = BeelineChar and BeelineChar.avail -- (Availability's record)
    local G = av and av.giver
    local g = G and G[s.npc]
    if g and g.hostile and (s.k == "accept" or s.k == "turnin") then return "done" end
  end
  -- (one in your log that needs a profession you don't have - ore to mine, a herb to pick: its work and its hand-in
  -- are off your route until it's finished, e.g. you bought the ore)
  if s.q and (s.k == "obj" or s.k == "turnin") and ns.Avail and ns.Avail.Needs and State.OnQuest(s.q) and not State.QuestReady(s.q)
    and ns.Avail.Needs(s.q) then return "done" end
  -- a battleground quest (Avail.Pvp: its marks come from PvP matches): not its pick-up, its objectives or a trip to its
  -- hand-in - only that hand-in, once the quest is finished in your log (you played the matches)
  if s.q and PVP and PVP[s.q] and not (s.k == "turnin" and State.OnQuest(s.q) and (State.Quest(s.q) or {}).complete) then return "done" end
  -- far below you and not in your log: off the route (all its steps), the same cut the planner makes - so a plan made
  -- for someone lower (the built-in plan from level 1, or yours after a dungeon run) passes over what you've outgrown,
  -- and a trip to a zone with nothing left for you is passed too (the "went ahead" rule below)
  if Engine.finishNow then
    -- (finishing your quests at 60: the objectives and hand-ins of the quests you hold, gray or behind you, nothing else)
    if not (s.q and s.q > 0 and s.k ~= "accept" and State.OnQuest(s.q)) then return "done" end
  elseif Engine.Outlevelled(s) or Engine.Breadcrumbed(s) or Engine.Excluded(s) or (Engine.asTaken ~= s and Engine.BehindYou(s)) then return "done" end
  -- its earlier chain quest you skipped or said you're not doing: the game never offers it, so none of its steps is
  -- left (the ones of a quest you have are yours to do)
  if s.q and s.q > 0 and not State.OnQuest(s.q) and not State.IsCompleted(s.q) and (Engine.ChainCut(s.q) or Engine.Unreachable(s.q)) then return "done" end
  local k = s.k
  if k == "hearth" then
    local can, why = Engine.HearthUsable(i)
    if not can then hearthPassed(i, s, why); return "done" end
  end
  if k == "accept" then
    if State.OnQuest(s.q) or State.IsCompleted(s.q) then return "done" end
    if s.minLevel and UnitLevel("player") < s.minLevel then return "wait" end
    if Engine.TooHigh(s) then return "wait" end -- (red: the game's own colour, Engine.TooHigh)
    -- on a zone you picked, its prerequisites not handed in (ns.QUEST_PRE): it waits, like a level - the giver would
    -- have nothing for you (a zone route is planned from the main route's progress, which a zone hopper may not have).
    -- Your own plan has its prerequisites earlier in it. A quest the game showed on offer anyway (Availability) is
    -- taken as offered.
    -- On any plan, one whose prerequisite is in your log, not handed in, waits for that hand-in: the plan has the
    -- hand-in before it, but a hand-in can wait (its objective in the part your place skips, Engine.Compute). Up the
    -- chain: Engine.WaitsOnLog
    local pre = ns.QUEST_PRE and ns.QUEST_PRE[s.q]
    if pre and not (ns.char and ns.char.avail and ns.char.avail.seen and ns.char.avail.seen[s.q]) then
      if BeelineData and BeelineData.zoneRoute then
        -- (one whose prerequisites can't be got here at all is cut above, every step of it: Engine.Unreachable)
        if not State.PrereqsMet(s.q) then return "wait" end
      elseif Engine.WaitsOnLog(s.q) then return "wait" end
    end
    if State.LogFull and State.LogFull() then return "full" end
    return "todo"
  elseif k == "turnin" then
    if State.IsCompleted(s.q) then return "done" end
    if not State.OnQuest(s.q) then return "blocked" end
    if not State.QuestReady(s.q) then
      -- all that's unfinished is inside a dungeon you've run or skipped: it waits, the card moves on
      -- and so does one whose work the quest data has no place for (an unknown step) once you skipped that step: it
      -- comes back when the quest is ready
      local list, inside, outside, unknown = steps(), false, false, false
      for _, j in ipairs(Engine.ObjStepsOf(s.q)) do
        local t = list[j]
        if t.unknown then
          if ns.char.skipped[key(j)] or ns.char.manualDone[key(j)] then unknown = true elseif j ~= i and Engine.Status(j) ~= "done" then outside = true end
        elseif j ~= i and Engine.Status(j) ~= "done" then
          if Engine.DungeonLater(Engine.InsideOf(t), j) then inside = true else outside = true end
        end
      end
      if (inside or unknown) and not outside then return "later" end
      if Engine.TooHigh(s) then return "wait" end -- (its work is red to you: it waits with it)
      return "notready"
    end
    return "todo"
  elseif k == "obj" then
    if State.IsCompleted(s.q) then return "done" end
    if not State.OnQuest(s.q) then return "blocked" end
    if State.QuestReady(s.q) then return "done" end
    -- work the quest data has no place for (s.unknown): done only when the quest is ready - no live objective is
    -- matched to it (its words are the quest text's, not an objective's). Skip passes it: the hand-in then waits
    if s.unknown then return "todo" end
    local o = Engine.ObjectiveFor(s)
    if o and o.finished then return "done" end
    if Engine.DungeonLater(Engine.InsideOf(s), i) then return "later" end
    if Engine.TooHigh(s) then return "wait" end
    return "todo"
  elseif k == "grind" then
    local lvl = UnitLevel("player")
    if lvl > (s.level or 0) or (lvl == (s.level or 0) and UnitXP("player") >= (s.xp or 0)) then return "done" end
    return "todo"
  elseif k == "fp" then
    if s.fp and State.knownTaxi[s.fp] then return "done" end
    -- (this flight master's own point, by its flight-map name - not a name match on the zone: a zone can have two)
    if Engine.KnowsThisFlightPoint(s) then return "done" end
  elseif k == "bind" then
    local b = GetBindLocation and GetBindLocation()
    if Engine.BoundAt(s, b) then return "done" end
    -- bound at a later bind stop of the route: that one replaced this one - never back to rebind here
    local c, list = planIndex()
    for _, j in ipairs(c.binds) do if j > i and Engine.BoundAt(list[j], b) then return "done" end end
  elseif k == "bonus" then
    -- a book / collectible: done once it's in your bags or the books addon has it as found
    if s.item and ns.GetItemCount and (ns.GetItemCount(s.item, true) or 0) > 0 then return "done" end
    local found = HandyNotes_ForeverBooksCharDB and HandyNotes_ForeverBooksCharDB.collected
    if s.book and type(found) == "table" and found[s.book] then return "done" end
  elseif k == "train" then
    -- training is the player's call: the plans' training stops are never shown or travelled to (they stay in the plan
    -- files so step numbers - and your saved progress - don't move)
    return "done"
  end
  -- "Run <dungeon>": done while you're inside that dungeon (the entrance check can't see you once you're in, and a
  -- reload inside would otherwise leave it stuck). Leave early and it comes back.
  if k == "goto" and s.text then
    local dname = Engine.RunDungeon(s)
    -- inside: the run you're on is done - the first of that dungeon's runs not run yet; a second and third XP run
    -- stay to do (else all read done inside and the card ran ahead mid-run)
    if dname and Engine.InDungeon(dname) then
      -- the run you're on is the one going in marked (recordDungeon); none marked yet (you were inside when the plan
      -- loaded): the first of that dungeon's runs not run yet
      if ran(i) then return "done" end
      local list, marked, first = steps(), false, nil
      for j = 1, #list do
        local d2 = Engine.RunDungeon(list[j])
        if d2 and Engine.SamePlace(d2, dname) then
          if ran(j) then marked = true elseif not first and not ns.char.skipped[key(j)] then first = j end
        end
      end
      if not marked and first == i then return "done" end
      -- any other run of it: the usual rules (one passed by "you went ahead" stays passed)
    end
    -- been in it (this run, or one before): done; or nothing you're on is left inside: done
    if dname and ran(i) then return "done" end
    -- (a run for its XP - s.xpRun - has nothing to do inside: only going in, or skipping it, passes it)
    if dname and not s.xpRun then
      local list, left = steps(), false
      for j = i + 1, #list do local t = list[j]; local x = Engine.InsideOf(t); if x and Engine.SamePlace(x, dname) and State.OnQuest(t.q) and Engine.Status(j) ~= "done" then left = true; break end end
      if not left then return "done" end
    end
  end
  -- goto / fly / hearth / note: completed by events, arrival or a click, or passed: if the next few quest steps
  -- after it are already done (you went ahead, or did things in another order), the travel was clearly made
  -- (a step that reads to do only through the live solve's pick-up from behind you, Next.taken, is passed as the
  -- plan sees it: otherwise the travel before it stopped being passed and the card flipped while you stood still)
  local tk = ns.Next and ns.Next.taken
  local function passed(j, t)
    if Engine.Status(j) == "done" then return true end
    return tk ~= nil and t.q ~= nil and t.q > 0 and Engine.BehindYou(t, true)
  end
  if (k == "goto" or k == "fly" or k == "hearth" or k == "note" or k == "fp" or k == "bind" or k == "train" or k == "bonus") and not (k == "fly" and ns.ChoiceFor and ns.ChoiceFor(i)) then
    local list, seen, done = steps(), 0, 0
    for j = i + 1, math.min(#list, i + 15) do
      local t = list[j]
      if t.k == "turnin" or t.k == "obj" then -- real progress only: accepts can be done long before you get there
        seen = seen + 1
        if passed(j, t) then done = done + 1 else break end
        if seen >= 2 then break end
      end
    end
    if seen >= 2 and done == seen then return "done" end
  end
  -- a flight (or hearth) to nothing: every step from it to the next travel is already done (else a stray safety-net
  -- pick-up between two trips made a pointless there-and-back)
  if isTrip(s) and not (ns.ChoiceFor and ns.ChoiceFor(i)) then
    local list, any = steps(), false
    for j = i + 1, math.min(#list, i + 40) do
      local t = list[j]
      if isTrip(t) then break end
      any = true
      if not passed(j, t) then any = nil; break end
    end
    if any then return "done" end
  end
  return "todo"
end
-- during a refresh (and the card / list redraw it triggers) each step's status is worked out once and reused
batch = nil -- (declared above Engine.BehindYou, which keeps its answers with it)
function Engine.Status(i)
  if batch then local c = batch[i]; if c then return c end end
  local st = statusRaw(i)
  if batch then batch[i] = st end
  return st
end
-- a look over the route that changes nothing (the route window drawn): each step's status worked out once for it, as
-- in a refresh (the route window asked most statuses three times: ~2x slower). Inside a refresh, or a route job's
-- slice (its statuses are the job's), fn just runs.
function Engine.ReadPass(fn)
  if batch or (ns.sliceCo and coroutine.running() == ns.sliceCo) then return fn() end
  batch = {}
  local ok, err = pcall(fn)
  batch = nil
  if not ok then error(err, 0) end
end
function Engine.IsDone(i) return Engine.Status(i) == "done" end
-- would step i be to do if the live solve took it up from behind you (Next.taken)? Behind you is the only thing taking
-- it lifts: a breadcrumb whose quest is yours, a quest not offered, one you said you're not doing stay done
function Engine.TodoIfTaken(i)
  local s = steps()[i]
  if not s then return false end
  Engine.asTaken = s
  local ok, st = pcall(statusRaw, i)
  Engine.asTaken = nil
  return ok and st == "todo"
end

-- Finding your place in the built-in plan (see Engine.BehindYou): the first time this character meets it, and again
-- when you come back to it more than JOIN_GAP levels on (the addon was off, or you were on a plan of your own).
-- Where the plan stands for you without any of that - the first step still to do - tells which you are: within
-- JOIN_GAP levels of you, you are following it, and nothing changes; further back, you join at your level.
-- force (/bee rejoin): join at your level whatever the plan says.
function Engine.PlaceDue()
  local key = ns.planKey and ns.planKey.starter
  if not (key and ns.char) then return false end
  -- (on the plan's path only: a side trip or a dungeon route has no levels to tell by)
  local d = BeelineData
  if not d or d.branch or d.dungeon or d.zoneRoute or d.special then return false end
  -- not before the game has told us the quests you've done: on a cold login it may not have yet, and a player
  -- following the plan would read as one joining it (and lose up to JOIN_GAP levels of it, quests in the log too)
  if (UnitLevel("player") or 1) > 5 then
    if not next(State.completed or {}) and State.RefreshCompleted then State.RefreshCompleted() end
    if not next(State.completed or {}) then return false end
  end
  local j = ns.char.join
  if not (j and j.plan == key) then return true end
  return (UnitLevel("player") or 1) - (tonumber(j.seen) or 0) > Engine.JOIN_GAP
end
-- the quests of the plan that were in your log when you joined it (a join made before this was kept: as of now)
function Engine.JoinHad()
  local j = ns.char and ns.char.join
  if not (j and ns.planKey and j.plan == ns.planKey.starter and tonumber(j.level) and j.level > 1) or j.had then return end
  local had = {}
  for _, s in ipairs(steps()) do if s.q and s.q > 0 and not had[s.q] and State.OnQuest(s.q) then had[s.q] = true end end
  j.had = had
end
function Engine.FindPlace(force)
  Engine.StateChanged()
  if force then Engine.ResetFloor() end -- (a rejoin: your place in the plan starts again from where you join)
  local key = ns.planKey and ns.planKey.starter
  if not (key and ns.char) then return nil end
  local L = UnitLevel("player") or 1
  local old = ns.char.join and ns.char.join.plan == key and ns.char.join or nil
  local level, fresh = L, true
  if not force then
    local saved = batch
    batch, Engine.noPlace = nil, true -- (no reuse: these are the statuses without a place)
    local ok, first = pcall(Engine.Compute)
    batch, Engine.noPlace = saved, nil
    local e = ok and first and Engine.PlanLevel(first)
    -- within JOIN_GAP levels of where the plan stands for you, or the plan reaches your level in its first stretch
    -- (you are still in the start zone): you are following it
    local at = joinStep(L)
    -- (the first time you meet the plan, its first step left to do must also be on your continent: the quests before
    -- it may be gray only because you levelled elsewhere; joining, the stretch around you is priced against it -
    -- Engine.ChooseStart)
    local away = false
    local here = not old and first and L > 5 and Engine.HereMap() or nil
    if here then
      local _, px, py = State.Position()
      local mine = px and select(3, LibStub("HereBeDragons-2.0"):GetWorldCoordinatesFromZone(px, py, here))
      local list = steps()
      for j = first, math.min(#list, first + 8) do
        local w = ns.Util.WPos(list[j])
        if w then away = mine ~= nil and w[3] ~= mine; break end
      end
    end
    if not e or at == 1 or (e >= L - Engine.JOIN_GAP and not away) then level, fresh = old and old.level or 0, false end
  end
  if not fresh then
    ns.char.join = { plan = key, level = level, seen = L, first = old and old.first, had = old and old.had }
    if batch then wipe(batch) end
    return level
  end
  -- joining: where to start (Engine.ChooseStart), and the quests you bring along
  local first, priced = nil, {}
  if L > 1 then
    local ok, a, b = pcall(Engine.ChooseStart, L)
    if ok then first, priced = a, b or {} elseif ns.LogError then ns.LogError("join", a) end
  end
  ns.char.join = { plan = key, level = level, seen = L, first = first }
  Engine.JoinHad()
  if batch then wipe(batch) end
  if L > 1 and not (old and old.level == L and old.first == first and not force) then
    local _, at = Engine.Place()
    local function k(n) return string.format("%.1fk", n / 1000) end
    local function one(p) return p.zone .. " (step " .. p.from .. (p.plan and ", the plan's trip at your level" or "") .. "): about " .. k(p.score or p.xph) .. " XP in the next hour - " .. p.turnins .. " hand-ins, " .. math.floor(p.work / 60 + 0.5) .. " min of work, " .. math.floor(p.extra / 60 + 0.5) .. (p.plan and " min to get there" or " min of travel added") end
    local won = priced[1] and ("start in " .. one(priced[1]) .. (priced[2] and ("; next best " .. one(priced[2])) or "; nothing else priced")) or "nothing to price (no position, or no stretch near your level): the plan's trip at your level"
    if ns.Why then ns.Why("join", "joined the built-in plan at level " .. L .. (at and (", its step " .. at) or "") .. ": " .. won) end
    local say = function()
      ns.Print("You join the built-in plan at level " .. L .. ": what it does before that is behind you" .. (at and at > 1 and (" (" .. (at - 1) .. " steps)") or "") .. "."
        .. (first and priced[1] and (" You start in " .. priced[1].zone .. ": worth more from where you stand (about " .. k(priced[1].score or priced[1].xph) .. " XP in the next hour" .. (priced[2] and (" against " .. k(priced[2].score or priced[2].xph) .. " in " .. priced[2].zone) or "") .. ").") or "")
        .. " Quests in your log from the parts behind you are yours to finish or drop - /bee logcheck lists them. (/bee rejoin does this again at your level.)")
    end
    if force then say() else C_Timer.After(7, say) end
  end
  return level
end
-- Ahead of the plan on a trip out: the plan's next step is in another zone, and the plan gets there AHEAD_GAP or more
-- levels below you - you levelled past it (rested XP, a dungeon, a zone you liked). Within JOIN_GAP levels the plan's
-- place held (Engine.PlaceDue), and the trip out is where that costs: your place is weighed again as joining weighs it
-- (Engine.FindPlace: the stretches near your level priced by XP an hour from where you stand), once a step.
-- -> true when your place moved
Engine.AHEAD_GAP = 2
Engine.AHEAD_QUEST = 6
local aheadSeen = setmetatable({}, { __mode = "k" })
function Engine.AheadCheck(i)
  local key = ns.planKey and ns.planKey.starter
  local d = BeelineData
  if not (key and ns.char and d) or d.branch or d.dungeon or d.zoneRoute or d.special or Engine.noPlace then return false end
  local s = steps()[i]
  if not s or aheadSeen[s] then return false end
  aheadSeen[s] = true
  local L = UnitLevel("player") or 1
  local e = Engine.PlanLevel(i)
  if not (e and e <= L - Engine.AHEAD_GAP) then return false end
  local here = Engine.HereMap()
  local to = (s.k == "fly" and s.to) or s.m
  if not (here and to and to ~= here) then return false end
  if ns.Dungeon and ns.Dungeon.Inside and ns.Dungeon.Inside() then return false end
  -- (and what it goes out for is far below you: the first quest of that trip AHEAD_QUEST levels or more under your
  -- level. Up to JOIN_GAP levels ahead you follow the plan as before: only a trip out for low quests is weighed)
  local list, ql = steps(), nil
  for j = i, math.min(#list, i + 12) do
    local t = list[j]
    if t.q and t.q > 0 and tonumber(t.level) and t.level > 0 then ql = t.level; break end
  end
  if not (ql and ql <= L - Engine.AHEAD_QUEST) then return false end
  local old = ns.char.join
  local ok = pcall(Engine.FindPlace, true)
  if not ok then return false end
  local now = ns.char.join
  if ns.Why then ns.Why("join", string.format("ahead of the plan: its next step (%s, plan level %d) is out of your zone at level %d - your place weighed again", tostring(s.name or s.text or s.dest or s.k), e, L)) end
  return not (old and now and old.first == now.first and old.level == now.level)
end
function Engine.Rejoin()
  if not (ns.planKey and ns.planKey.starter) then ns.Print("Only on the built-in plan: a plan of your own is made from your save and starts where you are."); return end
  Engine.FindPlace(true)
  Engine.Refresh()
end
-- your level, each time the addon sees you level on the built-in plan: a gap in it is time spent away from the plan
ns.On("PLAYER_LEVEL_UP", function(level)
  local j = ns.char and ns.char.join
  if j and ns.planKey and j.plan == ns.planKey.starter then j.seen = tonumber(level) or UnitLevel("player") or j.seen end
end)
-- not before you are in the world: the quest log and the quests you have done are known from then on
local function worldReady() Engine.placeReady = true end -- (PLAYER_ENTERING_WORLD)

-- The run of done steps from the plan's start, remembered (Engine.Compute): ~2000 steps at level 50, otherwise worked
-- out again on every refresh (7-8 ms). A done step comes back only through what resets it here (Engine.StateChanged:
-- undo, back, a skip or jump, a quest dropped, a level, a bind, a dungeon, another route or place in the plan) - and
-- for anything else, the run is checked again in the background after each refresh that used it (a slice a frame); a
-- step found not done there ends the run just before it (the steps before it were found done on the way) and refreshes.
local doneRun = { list = nil, k = 0, step = nil, key = nil }
Engine.doneRunMiss = 0 -- (the simulator: times the check found the run wrong)
-- One generation for your route state (Engine.stateGen): Engine.StateChanged() after anything that can make a done step
-- not done (a skip or tick taken back, a quest back from "not doing", a route or place change). The done run is kept
-- for one generation (doneKey).
Engine.stateGen = 0
function Engine.StateChanged() Engine.stateGen = Engine.stateGen + 1; doneRun.list = nil; doneRun.k = 0 end
Engine.ForgetDone = Engine.StateChanged -- (callers outside the engine, tests and tools)
-- quests gone from your log since the last look (QUEST_REMOVED, further down): one not handed in forgets the run
local removed = {}
local function settleRemoved()
  for id in pairs(removed) do
    if not State.IsCompleted(id) then Engine.StateChanged(); break end
  end
  wipe(removed)
end
-- The live solve's pick-up from behind you (Next.taken) reads "todo" only while it is the solve's pick: an extra, never
-- the plan's own step - nor what reads "todo" only through it: the rest of its quest, a pick-up it unlocks. Inside the
-- run of done steps it doesn't break the run (a pick from behind you made the next refresh look at the whole plan from
-- its start: 2,000 statuses): Engine.Compute passes over an extra as it passes over a done step
local function takenNow()
  local taken = ns.Next and ns.Next.taken
  if taken ~= nil and not Engine.BehindYou(taken, true) then taken = nil end
  return taken
end
local function isExtra(list, i, taken) return taken ~= nil and (list[i] == taken or Engine.BehindYou(list[i], true)) end
-- the run, now only up to just before step j (a step in it found not done: the ones before it were found done)
local function cutRun(j)
  if not (doneRun.list and j and j - 1 < doneRun.k) then return end
  doneRun.k = math.max(0, j - 1)
  doneRun.step = doneRun.list[doneRun.k]
end
local function doneKey(skipFrom, skipTo)
  local c = ns.char or {}
  local j = c.join
  return table.concat({ Engine.stateGen, tostring(c.manualDone), tostring(c.skipped), tostring(c.nope), tostring(j), j and tostring(j.level) or "", j and tostring(j.first) or "",
    tostring(UnitLevel and UnitLevel("player")), tostring(skipFrom), tostring(skipTo), tostring(BeelineData) }, "|")
end
-- the background check: a job of ns.Jobs (kind "verify": after route changes and solves), one at a time
local verify -- the job, while it runs
local settling -- (Engine.SettleDone: a step not done forgets the run, without a refresh)
local function verifyDone(wrong)
  verify = nil
  if not wrong then return end
  Engine.doneRunMiss = Engine.doneRunMiss + 1
  if not settling and ns.Why then ns.Why("donerun", "step " .. wrong .. " is not done after all: the plan is looked at again from there") end
  cutRun(wrong)
  if not settling then Engine.RefreshBg() end
end
local function verifyFail() verify = nil; if settling then Engine.doneRunMiss = Engine.doneRunMiss + 1 end; Engine.StateChanged() end
local function verifyAbort(job) if verify == job then verify = nil end end
local function checkRun(list, k)
  local key = doneRun.key
  if verify then ns.Jobs.Cancel("verify") end
  verify = ns.Jobs.Post("verify", function()
    for j = 1, k do
      if j % 16 == 0 then ns.MaybeYield() end
      if doneRun.list ~= list or doneRun.key ~= key then return nil end -- (reset meanwhile)
      if j > doneRun.skipFrom0 and j <= doneRun.skipTo0 then -- (the part of the plan your place in it passes)
      elseif Engine.Status(j) ~= "done" and not isExtra(list, j, takenNow()) then return j end
    end
    return nil
  end, { budget = 0.5, logAs = "donerun", done = verifyDone, fail = verifyFail, abort = verifyAbort })
end
-- The run is kept from one login to the next (ns.char.doneRun: its last step, at the level, plan and addon version it
-- was found at): otherwise a login looked at the whole plan from its start again (most of a 300 ms refresh). Counted
-- in the plan's own steps: the stops added as you played (hand-ins, side quests, flight paths: added) are not in
-- the plan the next login reads - they come back only after its first refresh - and counted with them, the run kept
-- never matched the plan at the next login. Taken back only where its last step still stands in the plan, and then
-- checked in the background like any other run (checkRun)
local function own(t) return not (t.inserted or t.added) end
local function ownSteps(list) local n = 0; for j = 1, #list do if own(list[j]) then n = n + 1 end end; return n end
local function runStamp(list) return tostring(ns.VERSION) .. ":" .. tostring(BeelineData and (BeelineData.id or BeelineData.title)) .. ":" .. ownSteps(list) end
-- step j's key among the plan's own steps (Engine.Key with the added stops left out): what it is, and which of its kind
local function stepBase(t) return (t.k or "?") .. ":" .. tostring(t.q or "") .. ":" .. tostring(t.match or t.text or t.dest or t.name or t.npc or t.fp or t.bind or "") end
local function ownKey(list, j)
  local s = list[j]
  local b, n = stepBase(s), 0
  for i = 1, j do local t = list[i]; if own(t) and t.k == s.k and t.q == s.q and stepBase(t) == b then n = n + 1 end end
  return b .. "#" .. n
end
function Engine.DoneRunSave()
  if not ns.char then return end
  local list = steps()
  if doneRun.list ~= list or doneRun.k <= 0 or list[doneRun.k] ~= doneRun.step then ns.char.doneRun = nil; return end
  -- (up to its last own step: an added stop is not in the next login's plan)
  local k = doneRun.k
  while k > 0 and not own(list[k]) do k = k - 1 end
  local n = 0
  for j = 1, k do if own(list[j]) then n = n + 1 end end
  if n <= 0 then ns.char.doneRun = nil; return end
  ns.char.doneRun = { v = runStamp(list), lvl = UnitLevel and UnitLevel("player"), k = n, step = ownKey(list, k) }
end
local function doneRunLoad(list, runKey)
  local s = ns.char and ns.char.doneRun
  if ns.char then ns.char.doneRun = nil end -- (once: the run found from here on is this login's own)
  if not (type(s) == "table" and type(s.k) == "number" and type(s.step) == "string" and s.v == runStamp(list) and s.lvl == (UnitLevel and UnitLevel("player"))) then return end
  -- (the s.k-th own step: step s.k, unless stops were added before it already)
  local j, n = 0, 0
  while n < s.k and j < #list do j = j + 1; if own(list[j]) then n = n + 1 end end
  if n ~= s.k or j < 1 or ownKey(list, j) ~= s.step then return end
  doneRun.list, doneRun.key, doneRun.k, doneRun.step = list, runKey, j, list[j]
  doneRun.skipFrom0, doneRun.skipTo0 = 0, -1
  return true
end
ns.On("PLAYER_LOGOUT", function() pcall(Engine.DoneRunSave) end)
-- (tests and the simulator: the run checked at once, every time it is used)
Engine.CHECK_RUN_NOW = false
function Engine.SettleDone() settling = true; local ok, e = pcall(ns.Jobs.Settle, "verify"); settling = nil; if not ok then error(e, 0) end end
-- Your place in the plan only moves forward: the floor, the furthest step of the plan the card has had as yours
-- (kept per route by step key in ns.char.floor). A quest from the part of the plan you passed - one you took up again
-- there, a pick-up that came back - no longer pulls your place (Base, zones ahead, the solve's window) back: Next offers
-- its steps as extras when they are near and worth it (Engine.BelowFloor). /bee undo, a rejoin or another place in
-- the plan reset it.
local function floorIndex(list)
  local d = BeelineData
  if not d or d.dungeon or d.special or Engine.noPlace or not ns.char then return nil end
  local fl = Engine._floor
  if not (fl and fl.list == list and fl.char == ns.char) then
    fl = { list = list, char = ns.char }
    local k = ns.char.floor and ns.char.floor[d.id]
    if k then for i = 1, #list do if Engine.Key(i) == k then fl.step = list[i]; break end end end
    Engine._floor = fl
  end
  return fl.step and planIndex().idx[fl.step] or nil
end
local function raiseFloor(list, i)
  local d = BeelineData
  if not d or d.dungeon or d.special or Engine.noPlace or not ns.char then return end
  local cur = floorIndex(list)
  if cur and cur >= i then return end
  Engine._floor = { list = list, char = ns.char, step = list[i] }
  ns.char.floor = ns.char.floor or {}
  ns.char.floor[d.id] = Engine.Key(i)
end
Engine.FloorIndex = function() return floorIndex(steps()) end
function Engine.ResetFloor()
  local d = BeelineData
  Engine._floor = nil
  if d and ns.char and ns.char.floor then ns.char.floor[d.id] = nil end
end
-- the plan's steps below your place still to do for quests in your log (Next.lua offers them as extras): at most n
function Engine.BelowFloor(planned, n)
  local out, list = {}, steps()
  if not planned then return out end
  for j = planned - 1, math.max(1, planned - 400), -1 do
    local t = list[j]
    if t.q and t.q > 0 and State.OnQuest(t.q) and Engine.Status(j) == "todo" then out[#out + 1] = j; if #out >= (n or 12) then break end end
  end
  return out
end
-- Level 60 on the plan: no more questing, the route is done whatever plan steps are left - the card celebrates. Not
-- a zone, dungeon, special or branch route: those you picked are yours to finish. One level check - nothing is worked
-- out per refresh for a 60 (no scan, no solve, no trips). Unless you ask to finish the quests you hold ("Finish my
-- quests" on the card, ns.char.finish60, per character): then the plan is only their objectives and hand-ins
-- (Engine.finishNow, statusRaw) - nothing new picked up, no travel steps (the card's live trip gets you there), no
-- place or floor in the plan (the quests you hold are wherever the plan passed them)
Engine.MAX_LEVEL = 60
local function atCap()
  local d = BeelineData
  return d ~= nil and not (d.zoneRoute or d.dungeon or d.special or d.branch) and ((UnitLevel and UnitLevel("player")) or 1) >= Engine.MAX_LEVEL
end
function Engine.Capped() return atCap() and not (ns.char and ns.char.finish60) end
function Engine.Finishing() return atCap() and (ns.char and ns.char.finish60) and true or false end
-- "Finish my quests" on (true) or off (back to the level 60 card)
function Engine.SetFinishing(on)
  if not ns.char then return end
  ns.char.finish60 = on and true or nil
  Engine.finishNow = Engine.Finishing()
  Engine.view = nil
  Engine.StateChanged()
  Engine.Refresh()
end
-- (how many times the plan was worked out, and how many of those from its first step: ns.Mark keeps them for a slow moment)
Engine.computeN, Engine.walkN = 0, 0
function Engine.Compute()
  if next(removed) then settleRemoved() end
  Engine.cappedNow = Engine.Capped() -- (Engine.CardAt reads it: no step on the card for a 60)
  Engine.finishNow = not Engine.cappedNow and Engine.Finishing() -- (statusRaw reads it)
  if Engine.cappedNow then Engine.forNow, Engine.planDone, Engine.levelHold = false, true, nil; return nil end
  local finishing = Engine.finishNow
  -- the first step you can act on now. A step that needs a higher level ("wait") or a quest that isn't in your log
  -- ("blocked") doesn't hold up the route: it is passed over and comes back as soon as it can be done.
  local list, fallback = steps(), nil
  -- (firstFull: the first pick-up waiting for room in your log; the guard below holds the plan on it)
  local firstFull
  local lvlNow = (UnitLevel and UnitLevel("player")) or 1
  local function passedOver(i, st)
    fallback = fallback or i
    if st == "full" then firstFull = firstFull or i end
  end
  local skipFrom, skipTo = nil, nil
  if not finishing then
    local _, at = Engine.Place()
    local f1, f2 = Engine.FirstStretch()
    if at and f1 and f1 > at then
      -- (a hand-in not ready whose objective step is in the part skipped is no work of the stretch: it waits, as look()
      -- reads it below - "later". Counted as work, it kept the skip on with nothing else to do in the stretch, hiding
      -- the skipped part's quests nearby. Only while the part skipped has work in the zone you stand in: otherwise
      -- "done for now", not a trip back for it)
      local workHere
      local function skippedWorkHere()
        if workHere == nil then
          workHere = false
          local pm = State.Position and State.Position()
          if pm then for j = at, f1 - 1 do local t = list[j]; if t.m == pm and t.q and Engine.Status(j) == "todo" then workHere = true; break end end end
        end
        return workHere
      end
      local function objSkipped(i)
        local objs = list[i].q and Engine.ObjStepsOf(list[i].q) or {}
        for n = 1, #objs do local j = objs[n]; if j >= at and j < f1 and Engine.Status(j) == "todo" then return skippedWorkHere() end end
        return false
      end
      for i = f1, f2 do
        local st = Engine.Status(i)
        if st ~= "done" and st ~= "wait" and st ~= "blocked" and st ~= "later" and not (st == "notready" and objSkipped(i)) then skipFrom, skipTo = at, f1 - 1; break end
      end
    end
  end
  -- where to start: past the remembered run of done steps, when it is still this plan, place and state
  local key = doneKey(skipFrom, skipTo)
  local start = 1
  if doneRun.list == nil and not Engine.noPlace and ns.char and ns.char.doneRun then doneRunLoad(list, key) end -- (the last login's: checked below like any)
  local use = not Engine.noPlace and doneRun.list == list and doneRun.key == key and doneRun.k > 0 and list[doneRun.k] == doneRun.step
  if use then start = doneRun.k + 1 end
  -- (the live solve's pick-up from behind you: an extra - takenNow, above. Inside the run, the run ends before it: the
  -- look sees it, and the rest of its quest as they read now - as the look from the plan's start saw them, not a walk
  -- from the start for it)
  local taken = takenNow()
  local function extra(i) return isExtra(list, i, taken) end
  if use and taken ~= nil then
    local ti = planIndex().idx[taken]
    if ti and ti < start then start = ti end
  end
  -- (Engine.CHECK_RUN_EVERY: every n-th use only - the sim's whole-plan runs: checking ~2,000 done steps every refresh
  -- was a third of its time, and a run that stays wrong is still caught)
  Engine.checkRunN = (Engine.checkRunN or 0) + 1
  if use and Engine.CHECK_RUN_NOW and Engine.checkRunN % (Engine.CHECK_RUN_EVERY or 1) == 0 then
    for j = 1, start - 1 do
      local st = (skipFrom and j >= skipFrom and j <= skipTo) and "done" or Engine.Status(j)
      if st ~= "done" and not extra(j) then
        -- (looked at again from that step: the ones before it were just found done)
        Engine.doneRunMiss = Engine.doneRunMiss + 1; start = j; use = false
        local t = list[j]; Engine.doneRunWhy = Engine.doneRunWhy or {}
        if #Engine.doneRunWhy < 12 then Engine.doneRunWhy[#Engine.doneRunWhy + 1] = string.format("#%d %s %s now %s", j, tostring(t.k), tostring(t.name or t.text or t.dest or ""):sub(1, 30), st) end
        break
      end
    end
  end
  Engine.computeN = Engine.computeN + 1; if start == 1 then Engine.walkN = Engine.walkN + 1 end -- (ns.Mark: a slow moment's walks of the plan)
  local runLen = start - 1
  local found, sawExtra
  -- (the live solve's pick-up from behind you, Next.taken, reads "todo" only while it is the solve's pick: it is an
  -- extra, never the plan's own step - as that, once the solve moved on it read "done" again and the card showed a done
  -- step. Nor what reads "todo" only through it: the rest of its quest, and a pick-up it unlocks: takenNow, above)
  -- a step as the plan's look reads it: the part of the plan your place skips (the plan before the stretch you joined
  -- at) done - and a hand-in whose objective step is there, still to do, waits with it ("later": passed over, like a
  -- dungeon's). You start in that stretch, and the work you skip is not where you are. The hand-in comes back once the
  -- quest is ready; the objective is the live solve's to offer, as any step of a quest in your log behind your place
  -- (Engine.BelowFloor)
  local function look(i)
    if skipFrom and i >= skipFrom and i <= skipTo then return "done" end
    local st = Engine.Status(i)
    if st == "notready" and skipFrom then
      local objs = Engine.ObjStepsOf(list[i].q)
      for n = 1, #objs do
        local j = objs[n]
        if j > skipTo then break end
        if j >= skipFrom and Engine.Status(j) == "todo" then return "later" end
      end
    end
    return st
  end
  -- (a flight path the addon put in close to a trip is the card's step only when the plan's own next step after it
  -- can be done: it rides along with that trip. With every step there waiting, it alone was a long detour)
  local function waits(st) return st == "wait" or st == "full" or st == "blocked" or st == "later" end
  local function ridesAlong(i)
    for j = i + 1, #list do
      local s = look(j)
      if s ~= "done" and not extra(j) and not list[j].added then return not waits(s) end
    end
    return false
  end
  for i = start, #list do
    local st = look(i)
    if st ~= "done" and extra(i) then st = "extra" end
    if st == "extra" then sawExtra = true
    elseif st ~= "done" then
      if waits(st) then passedOver(i, st)
      elseif list[i].added and list[i].k == "fp" and not ridesAlong(i) then -- (left for its trip: see above)
      else found = i; break end
    elseif runLen == i - 1 then runLen = i end
  end
  -- (not below your place in the plan: the floor. Only a step of a quest in your log is kept out down there - one you
  -- took up again from the part you passed. A pick-up waiting for a level or room in your log, a hand-in waiting for
  -- its quest, a quest you abandoned come back as before, and hold the floor)
  local F = not finishing and floorIndex(list) or nil
  local function below(i) local t = list[i]; return F and i < F and t.q and t.q > 0 and not t.added and State.OnQuest(t.q) end
  -- (but not a step of the quest the plan lands on: its hand-in or later objective above the floor keeps the quest's
  -- steps passed below it on the card)
  if found and below(found) then
    local f2
    for i = found + 1, #list do
      local st = look(i)
      if st ~= "done" and not extra(i) then
        if st == "todo" and below(i) then -- (passed below the floor)
        elseif st == "wait" or st == "full" or st == "blocked" or st == "later" then passedOver(i, st) else f2 = i; break end
      end
    end
    -- (nothing left to do above the floor: the quests you hold below it are the plan's work now, not a finished
    -- plan - the live solve offers those only near you)
    found = f2 or found
  end
  -- A hand-in not ready, with an objective step of its quest still to do before it (passed below the floor, above, or
  -- however else the look came past it): that objective is the step, not the hand-in "Not finished" in red.
  -- (Only for a hand-in: a later objective of the same quest is work to do as it is; going back for the passed one
  -- moved the card and its pins on every objective done - 2x the time)
  if found and list[found].k == "turnin" and list[found].q and Engine.Status(found) == "notready" then
    local objs = Engine.ObjStepsOf(list[found].q)
    for n = 1, #objs do
      local j = objs[n]
      if j >= found then break end
      if Engine.Status(j) == "todo" and not extra(j) then found = j; break end
    end
  end
  -- (a full log: the plan's pick-ups wait for room, but the plan does not run on without them through the trips and
  -- training meant for levels above you. The pick-up stays on the card: "Quest log full - hand in or abandon". The
  -- first full pick-up, not the first wait of any kind: a red pick-up, a hand-in not in your log or a dungeon's
  -- "later" before it lets the plan run on as before)
  local hold
  if found and not list[found].q and firstFull then
    local pl = Engine.PlanLevel(found)
    if pl and pl > lvlNow + 2 then
      if firstFull < found then hold = firstFull end
      if hold then Engine.levelHold = list[found]; found = nil end
    end
  end
  if not hold then Engine.levelHold = nil end
  -- (the floor rises to the first step not done - waiting ones too: they come back from there)
  local first = (found and fallback) and math.min(found, fallback) or found or fallback
  if first and not finishing and not below(first) then raiseFloor(list, first) end
  if not Engine.noPlace then
    doneRun.list, doneRun.key, doneRun.k, doneRun.step = list, key, runLen, list[runLen]
    doneRun.skipFrom0, doneRun.skipTo0 = skipFrom or 0, skipTo or -1
    if use and runLen > 0 and not Engine.CHECK_RUN_NOW then checkRun(list, start - 1) end
  end
  -- (nothing on the route to do now, only steps that wait - for your level, an earlier quest: done for now. The card
  -- says so and offers your next home bases, rather than a step you can't do)
  Engine.forNow = not found and not hold and fallback ~= nil
  -- (and nothing left at all: every step done, none waiting, none held back as the live solve's pick-up - the plan is
  -- finished. The card says so - your next home bases - not a bare "Route complete" with no next step. At 60: Capped)
  Engine.planDone = not found and not hold and fallback == nil and not sawExtra
  return found or hold or fallback
end
function Engine.InDungeon(name)
  local here = ns.Dungeon.Here() -- by the instance id, or the game's name for it (Dungeon.lua)
  return here and Engine.SamePlace(here, name) or false
end
-- "Stormwind City" vs "Stormwind", "Lakeshire" vs "Redridge Mountains": loose place-name match
local function norm(x) return (x or ""):lower():gsub(" city$", ""):gsub("^the ", "") end
function Engine.SamePlace(a, b)
  if not a or not b then return false end
  local A, B = norm(a), norm(b)
  return A == B or A:find(B, 1, true) ~= nil or B:find(A, 1, true) ~= nil
end
-- the flight point of an "fp" step: by the flight master (Travel.KnowsFlightPoint: the flight map's own names); a step
-- without one, by its zone's name as before
function Engine.KnowsThisFlightPoint(s)
  if s.m and s.npc and ns.Travel and ns.Travel.KnowsFlightPoint then return ns.Travel.KnowsFlightPoint(s.m, s.npc) and true or false end
  return s.zone and Engine.KnowsFlightIn(s.zone) or false
end
-- a known flight path in this zone: node names look like "Sentinel Hill, Westfall" / "Lakeshire, Redridge"
function Engine.KnowsFlightIn(zone)
  local z = norm(zone); local first = z:match("^(%S+)")
  for name in pairs(State.knownTaxi or {}) do
    local n = name:lower()
    if n:find(z, 1, true) or (first and #first >= 5 and n:find(first, 1, true)) then return true end
  end
  return false
end

function Engine.Upcoming(from, n)
  local out, list = {}, steps()
  for i = (from or 0) + 1, #list do
    if #out >= n then break end
    if not Engine.IsDone(i) then out[#out + 1] = i end
  end
  return out
end

function Engine.Progress()
  local list = steps(); local done = 0
  for i = 1, #list do if Engine.IsDone(i) then done = done + 1 end end
  return done, #list
end

-- the step on the card, or the one you look at (Engine.view). While a route change's passes run over frames, the
-- card's step is the one it showed when they began (Engine.CardAt)
function Engine.Shown() return Engine.view or Engine.CardAt() end
-- progress through the zone you're in: the stretch between the travel steps around the shown step
-- where you are on your plan: its own step, not a stop shown ahead of it (a hand-in you chose with "Do it now", the
-- solve's pick) - else the card's "Base:" count and the zones ahead followed that stop's zone
function Engine.PlanAt()
  local p, list = Engine.planned, steps()
  if p and list[p] and not Engine.view then return p end
  return Engine.Shown()
end
function Engine.LegProgress(i)
  local list = steps(); i = i or Engine.PlanAt()
  if not i or not list[i] then return 0, 0, nil end
  local a, b = i, i
  -- (flights only bound the stretch here, not hearths: not Engine.IsTrip)
  while a > 1 and list[a].k ~= "fly" do a = a - 1 end
  if list[a].k == "fly" and a < i then a = a + 1 end
  while b < #list and list[b + 1].k ~= "fly" do b = b + 1 end
  local done = 0
  for j = a, b do if Engine.IsDone(j) then done = done + 1 end end
  local zone = list[i].zone or (list[a] and list[a].zone)
  return done, b - a + 1, zone
end

-- The zones ahead, from step i (default: where you are on the route) on, in order: { zone, quests = quests with
-- something still to do there on this visit (pick up, work or hand in), names = their quest names, first = its first
-- step }. A zone you only pass through (no hand-in, a flight path or two) is left out; travel steps belong to no
-- zone. Up to n visits (default 8). (The card's "why go there" line, the zones panel, the route list's chips)
local NO_ZONE_WORK = { fly = true, hearth = true, fp = true, bind = true } -- (trips, and steps of no zone's quests)
function Engine.ZonesAhead(i, n)
  local list, out = steps(), {}
  n = n or 8
  if not i then i = Engine.PlanAt() or Engine.current or 1 end
  local cur
  local function close()
    if cur and (cur.quests > 0 or cur.grind) then
      -- (a zone only passed through between two visits to one zone is left out: one visit then, not the same zone
      -- twice in a row)
      local last = out[#out]
      if last and last.zone == cur.zone then
        for k, q in pairs(cur.seen) do if not last.seen[k] then last.seen[k] = true; last.quests = last.quests + 1; if type(q) == "string" then last.names[#last.names + 1] = q end end end
        last.grind = last.grind or cur.grind
      else out[#out + 1] = cur end
    end
    cur = nil
  end
  for j = i, #list do
    local s = list[j]
    if not NO_ZONE_WORK[s.k] and s.zone and not Engine.IsDone(j) then
      if not cur or cur.zone ~= s.zone then
        close()
        if #out >= n then break end
        cur = { zone = s.zone, quests = 0, names = {}, seen = {}, first = j }
      end
      if s.q and s.q > 0 and not cur.seen[s.q] then cur.seen[s.q] = s.name or true; cur.quests = cur.quests + 1; cur.names[#cur.names + 1] = s.name end
      if s.k == "grind" then cur.grind = true end
    end
  end
  if #out < n then close() end
  return out
end

-- objective steps done in the same spot right after this one: shown together on the card
function Engine.Group(i)
  local list, out = steps(), {}
  local s = list[i]
  if not s or s.k ~= "obj" or s.unknown then return out end -- (work with no known place is not "here")
  for j = i + 1, math.min(#list, i + 8) do
    local t = list[j]
    if t.k ~= "obj" or t.unknown or t.m ~= s.m or math.abs((t.x or 0) - (s.x or 0)) > 0.02 or math.abs((t.y or 0) - (s.y or 0)) > 0.02 then break end
    if not Engine.IsDone(j) then out[#out + 1] = j end
  end
  return out
end

-- The engine's lock while a route change's passes run over frames (route jobs, ns.Jobs: Engine.Post, Engine.After).
-- A pass leaves Engine.current a number while it inserts stops (the passes after it depend on it), and the solve after
-- it takes many frames. Until the run ends:
-- - the card holds the step it showed when the run began, by its table (Engine.CardAt, Engine.Shown);
-- - a refresh asked for from outside waits for the end (Engine.Refresh), as do the full look and a count moving
--   (Engine.Announce: the strongest of them, once) and what acts on a step by its number (Engine.WhenIdle, Engine.Idle:
--   landing, arriving, a hearth cast, a jump), and no background solve starts (Next.PickAsync);
-- - a newer route change wins: the run's jobs are dropped, and until the next route job the refreshes run (lock.free).
-- It ends when no route job is queued and no stage of the newest route change is to come: a refresh asked for meanwhile
-- runs then as a route job of its own, then the actors run, the state is announced, and the card moves once.
-- The run's own jobs work as they always did (none of this applies inside them). Under ns.Jobs.SYNC (tests, the
-- simulated players, tools/replay.js) a route job runs to its end inside Post, and there is no run at all.
Engine.routeGen = 0 -- (one more each route change: a job or a stage of an older one is dropped)
local lock -- nil, or { shown = the card's step (table), shownAt = its number, due, free, idle = { fn }, state }
local pend = {} -- route change -> its stages (Engine.After) still to come
local cancelling = false
local switching -- (Engine.Switch: the refreshes its switch asks for are its own)
local function insideRoute() return ns.Jobs.Inside("route") end
function Engine.Busy() return lock ~= nil and not lock.free and not insideRoute() end
Engine._Run = function() return lock end -- (tests)
-- the card's step (not the one you look at): Engine.current, or the run's hold
function Engine.CardAt()
  if Engine.cappedNow and Engine.Capped() then return nil end -- (a 60 on the plan: done, Engine.Capped - not a late solve's pick)
  local r = lock
  if not (r and r.shown) or insideRoute() then return Engine.current end
  local list = steps()
  if list[r.shownAt or 0] ~= r.shown then
    r.shownAt = nil
    for j = 1, #list do if list[j] == r.shown then r.shownAt = j; break end end
    if not r.shownAt then r.shown = nil; return Engine.current end
  end
  return r.shownAt
end
-- a stop inserted at number at (Engine.InsertStop): the hold's number moves with it
function Engine.RunShift(at)
  local r = lock; if r and r.shownAt and r.shownAt >= at then r.shownAt = r.shownAt + 1 end
  -- (a stop put in inside the run of done steps: the run ends before it - before, its last step no longer stood at its
  -- place and the next refresh looked at the whole plan from its start)
  if doneRun.list == steps() and doneRun.k >= at then cutRun(at) end
end
-- fn now, or when the run ends
function Engine.WhenIdle(fn) if Engine.Busy() then lock.idle[#lock.idle + 1] = fn; return true end; fn(); return false end
-- a handler that acts on a step by its number: while a run is on, it runs when the run ends (with its arguments)
function Engine.Idle(fn)
  return function(...)
    if not Engine.Busy() then return fn(...) end
    local n, a = select("#", ...), { ... }
    lock.idle[#lock.idle + 1] = function() fn(unpack(a, 1, n)) end
  end
end
-- State's FR_STATE / FR_PROGRESS while a run is on: kept (the full look over a count), fired once when it ends -> true
function Engine.Announce(ev)
  if not Engine.Busy() then return false end
  if ev == "FR_STATE" or not lock.state then lock.state = ev end
  return true
end
-- a refresh asked for meanwhile (a background solve that did not start, ...): when the run ends
function Engine.Due() if Engine.Busy() then lock.due = true end end
-- a route job's state of its own: the statuses its refresh reuses (Engine.Status), swapped out while it waits for its
-- next frame - a status asked from outside meanwhile is neither served from it nor put in it
-- where you are, for a route job: taken once when it starts (a pass spread over frames prices every gap from the same
-- spot, as it did in one frame)
local jobPos
function Engine.Pos() if jobPos then return jobPos[1], jobPos[2], jobPos[3] end return State.Position() end
local function jobEnter(job)
  batch = job.batch
  if not job.pos then job.pos = { State.Position() } end
  jobPos = job.pos
end
local function jobLeave(job) job.batch = batch; batch = nil; jobPos = nil end
Engine._Batch = function() return batch end -- (tests)
local function jobAbort(job)
  batch, job.batch = nil, nil
  if ns.Next and ns.Next._Reset then ns.Next._Reset() end
  if job.onAbort then job.onAbort() end
end
-- a route job: fn spread over frames, for the newest route change (abort: what to put back if it is dropped)
function Engine.Post(name, fn, abort)
  return ns.Jobs.Post("route", fn, { gen = (not ns.Jobs.SYNC) and Engine.routeGen or nil, logAs = "route " .. name,
    enter = jobEnter, leave = jobLeave, abort = function(job) jobAbort(job); if abort then abort() end end })
end
-- a route change's stage: fn at its time after the change, as a route job (not C_Timer.After: the whole pass and its
-- refresh in one frame was ~1 s). The stages queue in the order of their times, so each reads the step the one before
-- it settled on; a newer route change drops the ones still to come.
function Engine.After(delay, name, fn)
  local gen, async = Engine.routeGen, not ns.Jobs.SYNC
  if async then pend[gen] = (pend[gen] or 0) + 1 end
  C_Timer.After(delay, function()
    if async then pend[gen] = (pend[gen] or 1) - 1; if pend[gen] <= 0 then pend[gen] = nil end end
    if async and gen ~= Engine.routeGen then Engine.CheckIdle(); return end
    Engine.Post(name, fn)
  end)
end
-- A route switch you asked for (a zone picked in Where to?, back to your plan): fn switches; the card shows the new
-- route's plan step at once (no solve: Engine.noSolve), and the refresh with its solve is the first route job, spread
-- over frames before the switch's other stages - the card then moves once, when they are all done (not two full
-- refreshes in the click's frame). Under ns.Jobs.SYNC: fn, then the refresh, as always.
function Engine.Switch(fn)
  if ns.Jobs.SYNC then fn(); Engine.Refresh(); return end
  switching = true
  local ok, err = pcall(fn)
  switching = nil
  Engine.noSolve = true
  local ok2, err2 = pcall(Engine.Refresh)
  Engine.noSolve = nil
  -- (the card shows that step from the first job's first frames: its trip - a world-wide search, ~70 ms - is worked
  -- out there, paused like the rest, and the card's fill finds it done)
  local s = steps()[Engine.current or 0]
  Engine.Post("refresh", function()
    if s and steps()[Engine.current or 0] == s then ns.Call(Engine.TravelFor, s); ns.Fire("FR_STEP", Engine.current) end
    Engine.Refresh()
  end)
  if not ok then error(err, 0) end
  if not ok2 then error(err2, 0) end
end
local function startRun()
  if lock and not lock.free then return end
  lock = lock or { idle = {} }
  lock.free = nil
  lock.shown, lock.shownAt = steps()[Engine.current or 0], Engine.current
  Engine.holdShow = lock
  -- (a trip asked again during the run is answered from its first search, as within one frame: Travel.Plan)
  if ns.Travel and ns.Travel.PinMemo then ns.Travel.PinMemo(lock) end
  if ns.Next and ns.Next.Cancel then ns.Next.Cancel() end
end
function Engine.CheckIdle()
  local r = lock
  if not r or cancelling or ns.Jobs.Busy("route") or (pend[Engine.routeGen] or 0) > 0 then return end
  if r.due and not r.free then r.due = nil; Engine.Post("refresh", function() Engine.Refresh() end); return end
  -- (the card's step at the end: its trip worked out in a job of its own, paused like the rest - the card's fill
  -- below finds it done)
  local s = not r.free and steps()[Engine.current or 0]
  if s and r.warmed ~= s then r.warmed = s; Engine.Post("trip", function() ns.Call(Engine.TravelFor, s) end); return end
  lock = nil
  if Engine.holdShow == r then Engine.holdShow = nil end
  if ns.Travel and ns.Travel.UnpinMemo then ns.Travel.UnpinMemo(r) end
  for _, fn in ipairs(r.idle) do local ok, e = pcall(fn); if not ok and ns.LogError then ns.LogError("idle", e) end end
  if r.state then if ns.State and ns.State.Announce then ns.State.Announce(r.state) else ns.Fire(r.state) end end
  ns.Fire("FR_STEP", Engine.Shown())
end
ns.Jobs.posted = function(job) if job.kind == "route" and not ns.Jobs.SYNC then startRun() end end
ns.Jobs.ended = function(job) if job.kind == "route" then Engine.CheckIdle() end end
-- a newer route change: the run's jobs go (each puts back what it half did), and until its own first job the card is
-- not held - the switch's refresh shows the new route's step
ns.On("FR_ROUTE_CHANGED", function()
  Engine.routeGen = Engine.routeGen + 1
  -- the step numbers of the route before: one the new route doesn't have is gone now, not after the refresh that
  -- follows (Routes.lua fires this first): the windows and the map listen too, and step 1754 of the plan read on a
  -- 20-step dungeon route was no step (a player's report: Style.lua "attempt to index local 'step'")
  local list = steps()
  if Engine.current and not list[Engine.current] then Engine.current = nil end
  if Engine.view and not list[Engine.view] then Engine.view = nil end
  if Engine.planned and not list[Engine.planned] then Engine.planned = nil end
  if lock then
    cancelling = true
    ns.Jobs.Cancel("route")
    cancelling = false
    lock.free, lock.shown, lock.shownAt = true, nil, nil
    if Engine.holdShow == lock then Engine.holdShow = nil end
    -- (it ends once the new change's stages are done - or next frame, if it has none)
    if C_Timer and C_Timer.After then C_Timer.After(0, Engine.CheckIdle) end
  end
end)

-- One refresh for one change: while the addon takes in a change (Engine.Coalesce: the log's full look, FR_STATE), the
-- refreshes its parts ask for - the plan's own, a hand-in added, a side trip's stop, a focus - are one, run when
-- they are all done (an objective finished ran three back to back otherwise).
-- Its solve runs in the background (a change the game told of), or with fg in that refresh (as an Engine.Refresh would);
-- a change taken in inside another is part of it, and its refresh is the outer one's
local coalescing -- nil, or true while a change is taken in; "due" once a refresh was asked for
function Engine.Coalesce(fn, fg, ...)
  if coalescing then return fn(...) end
  coalescing = true
  local ok, err = pcall(fn, ...)
  local due = coalescing == "due"
  coalescing = nil
  if due then Engine.bgSolve = not fg or nil; local ok2, e2 = pcall(Engine.Refresh); Engine.bgSolve = nil; if not ok2 then error(e2, 0) end end
  if not ok then error(err, 0) end
end
-- FR_STATE (the full look) is one change whoever fires it: its listeners - the plan's refresh, a hand-in added
-- (Inserts.lua), a side quest's stop (Side.lua), a count that moved (Focus.lua), a quest back from "not doing" - ask
-- for one refresh, run after them all (also for State.Announce without the log's coalescing)
ns.Around("FR_STATE", function(dispatch, ...) Engine.Coalesce(dispatch, true, ...) end)
for _, e in ipairs({ "HEARTHSTONE_BOUND", "FR_ROUTE_CHANGED", "FR_NOPE" }) do
  ns.On(e, function() Engine.StateChanged() end)
end
-- A quest gone from your log: dropped, its steps come back (forget the run) - or handed in, which only makes steps
-- done. The game fires QUEST_REMOVED for a hand-in too, and forgetting there made every hand-in look at the plan from
-- its start (~2000 statuses). Which it was is settled at the next refresh, after both events, whatever their order
ns.On("QUEST_REMOVED", function(id) if id then removed[id] = true else Engine.StateChanged() end end)
-- (a new zone matters only going into or out of a dungeon: a run there is done while you are inside)
local wasInside
local function insideChanged() local inside = ns.Is(IsInInstance); if inside ~= wasInside then wasInside = inside; Engine.StateChanged() end end -- (ZONE_CHANGED_NEW_AREA)
-- what you're plainly doing holds the card: a step you chose (Do it now), or one your kills count for (for
-- PROGRESS_HOLD seconds after the last one). anyStatus: the hold whatever the step's status (the refresh checks it itself)
function Engine.Holding(anyStatus)
  local fi, why = Engine.focus, Engine.focusWhy
  -- (a progress hold counts from your last kill or loot for it, Engine.RecentProgress - not from the first, which set the
  -- focus: farming 12 Eldarath Relics, the card went to a hand-in 90 s after the first relic, drops still coming)
  if not (fi and (why == "chosen" or (why == "progress" and (GetTime() - (Engine.focusAt or 0) < Engine.PROGRESS_HOLD or Engine.RecentProgress(fi))))) then return false end
  return anyStatus or Engine.Status(fi) == "todo"
end
-- the card lets go of a step your kills held (the hold ended, the step still to do): the why log says so - the card
-- moving off what you were farming is never silent
function Engine.LetGoFocus()
  local fi = Engine.focus
  if fi and Engine.focusWhy == "progress" and ns.Why and Engine.Status(fi) == "todo" then
    local s = steps()[fi]
    ns.Why("reorder", "off step " .. fi .. " (" .. tostring(s and (s.name or s.text or s.k)) .. "): " .. Engine.ProgressEnded(fi))
  end
  Engine.focus, Engine.focusWhy = nil, nil
end
-- a refresh for something the game said (a new zone, logging in): its solve in the background, like the log's
function Engine.RefreshBg() Engine.Coalesce(Engine.Refresh) end
-- remove the steps pred says from the route (inserted stops only): numbers, keys and the remembered run follow
function Engine.RemoveSteps(pred)
  local list = steps()
  local d = BeelineData
  local choices = d and list == d.steps and d.choices -- (kept by position: InsertStop shifts them on)
  local n = 0
  for j = #list, 1, -1 do
    if list[j].inserted and pred(list[j]) then
      table.remove(list, j); n = n + 1
      if choices then for _, c in ipairs(choices) do if c.at and c.at > j then c.at = c.at - 1 end end end
      if Engine.current and Engine.current > j then Engine.current = Engine.current - 1 end
      if Engine.planned and Engine.planned > j then Engine.planned = Engine.planned - 1 end
    end
  end
  if n == 0 then return 0 end
  for j = 1, #list do list[j].id = j end
  Engine.StepsChanged(list)
  Engine.focus, Engine.focusWhy, Engine.view = nil, nil, nil
  Engine.StateChanged()
  return n
end
-- a background solve's pick on the card (no rescan of the plan: nothing but the order changed)
-- (a pick not to do is not shown - skipped, ticked, not offered meanwhile - except the plan's own step when the card's
-- is no longer to do either: a solve that let go the quest it had taken from behind you (Next.taken) gives back the
-- plan's step, which may be a hand-in not finished yet)
function Engine.ShowPick(pick)
  if not pick or pick == Engine.current then return end
  if Engine.Status(pick) ~= "todo" and not (pick == Engine.planned and not (Engine.current and Engine.Status(Engine.current) == "todo")) then return end
  if Engine.Holding() then return end
  Engine.LetGoFocus()
  Engine.current = pick
  if Engine.view and Engine.view == Engine.current then Engine.view = nil end
  ns.Fire("FR_STEP", Engine.Shown())
end
function Engine.Refresh()
  if coalescing then coalescing = "due"; return end
  if switching then return end -- (a route switch's own refreshes: Engine.Switch does them)
  if Engine.Busy() then lock.due = true; return end -- (while a route change's passes run: when they end)
  local outer = batch == nil
  if outer then batch = {} else wipe(batch) end -- a nested refresh follows a change: start the reuse over
  if Engine.CHECK_RUN_NOW then Engine.GrayForget() end -- (tests change quests without the game's events)
  local t0 = outer and debugprofilestop and debugprofilestop()
  local mark = t0 and ns.Mark and ns.Mark()
  local ok, err = ns.Call(Engine.RefreshInner) -- (inside a route job: no pcall - a pause can't cross one)
  if outer then batch = nil end
  if t0 then ns.Time("refresh", debugprofilestop() - t0, mark) end
  if not ok then error(err, 0) end
end
-- the login catch-up stays quiet; tests switch it to see the completion cue
function Engine.SetQuiet(q) local was = quiet; quiet = q and true or false; return was end
function Engine.RefreshInner()
  -- (a 60 on the plan: done - no place, no solve, no trips; the card shows "Route done - level 60")
  if Engine.Capped() then
    Engine.Compute()
    Engine.current, Engine.planned, Engine.focus, Engine.taxiHold = nil, nil, nil, nil
    if not Engine.holdShow and not Engine.noSolve then ns.Fire("FR_STEP", Engine.Shown()) end
    return
  end
  Engine.here = Engine.HereMap() -- the zone you are in, for this refresh (Engine.BehindYou)
  if Engine.placeReady and Engine.PlaceDue() then Engine.FindPlace() end
  if Engine.placeReady then Engine.JoinHad() end
  local before = Engine.current
  local beforeStep = before and steps()[before]
  -- (a refresh you asked for shows at once: no hold from a solve before it - but a route change's run holds the card)
  if not Engine.bgSolve and not (lock and Engine.holdShow == lock) then Engine.holdShow = nil end
  local tc = debugprofilestop and debugprofilestop()
  Engine.current = Engine.Compute()
  if tc and ns.Time then ns.Time("compute", debugprofilestop() - tc) end
  -- already standing in a travel step's destination (switched routes there, logged in there, rode in): it's done
  for _ = 1, 5 do
    local s = Engine.current and steps()[Engine.current]
    if not (s and s.k == "fly" and s.to and Engine.InZone and Engine.InZone(s.to)) then break end
    ns.char.manualDone[key(Engine.current)] = true
    if batch then wipe(batch) end
    Engine.current = Engine.Compute()
  end
  -- ahead of the plan, and it would send you out of your zone for what it does below your level: weigh your place again
  -- as joining does (Engine.AheadCheck)
  if Engine.current and Engine.AheadCheck(Engine.current) then
    if batch then wipe(batch) end
    Engine.current = Engine.Compute()
  end
  -- a quest finished since the hand-ins were fitted (one with nothing to do, taken this moment): its hand-in goes on the
  -- route before the solve picks (Inserts.lua: Engine.InsertsDue) - not once FR_STATE comes, a card flip later
  if Engine.InsertsDue and Engine.InsertsDue() and Engine.current and not Engine.Busy() then
    if Engine.InsertsNow() then if batch then wipe(batch) end; Engine.current = Engine.Compute() end
  end
  -- what to do next: the live solver's pick among the next stops you can do and finished quests near you (Next.lua),
  -- or, with it off, the old reordering - a later step you're working on or standing at (Engine.UpdateFocus)
  Engine.planned = Engine.current
  -- On a flight nothing on the ground is in reach: the step you took off with holds until you land, instead of the
  -- card re-picking as you pass over zones. Kept by the step itself (a stop inserted meanwhile moves its number).
  -- Landing plans again from where you are
  local aloft = ns.Is and UnitOnTaxi and ns.Is(UnitOnTaxi, "player")
  local holdAt
  -- (only a step the card chose: logged in or reloaded on a flight, no solve has run yet and the card's step is the
  -- plan's, which may be a stale trip out. Until a solve has picked, the card picks as on the ground; then it holds)
  if aloft then
    if Engine.taxiHold and not planIndex().idx[Engine.taxiHold] then Engine.taxiHold = nil end -- (another route since)
    if not Engine.taxiHold and before and (Engine.picked == steps() or not (ns.Next and ns.Next.Enabled())) then Engine.taxiHold = steps()[before] end
    holdAt = Engine.taxiHold and planIndex().idx[Engine.taxiHold]
    if holdAt and Engine.Status(holdAt) ~= "done" then Engine.current = holdAt else holdAt = nil end
  else
    Engine.taxiHold = nil
  end
  if holdAt then
    -- (held for the flight: no solve, no reordering)
  elseif Engine.noSolve then
    -- (a route switch's first look: the plan's step - its solve is a route job of its own, Engine.Switch)
  elseif ns.Next and ns.Next.Enabled() then
    -- what you're plainly doing wins over any solve: a step your kills count for (for Engine.PROGRESS_HOLD seconds
    -- after the last one), or one you chose (Do it now)
    local fi = Engine.focus
    local holding = Engine.Holding(true)
    if holding and Engine.Status(fi) == "todo" then
      Engine.current = fi
    elseif Engine.RecentProgress(Engine.current) then
      Engine.LetGoFocus() -- (farming the plan's own step: your kills count for it - it stays, whatever circle you wander into)
    else
      Engine.LetGoFocus()
      if Engine.bgSolve and ns.Next.PickAsync then
        -- taking in a change from the game (Engine.Coalesce): the solve runs in the background (20-40 ms of a 50 ms
        -- refresh); meanwhile the card keeps the last pick while it is still to do, else the plan's step, and moves
        -- only if the solve picks another (Engine.ShowPick)
        local keep = ns.Next.LastPick()
        local planned, list = Engine.current, steps()
        if keep then Engine.current = keep end
        -- the card holds while the solve settles (at most Engine.HOLD_SECS): else it showed the plan's step, then a
        -- moment later the solve's pick - two slides for one hand-in. Only when the card would change at all
        local token = {}
        if beforeStep and steps()[Engine.current] ~= beforeStep then
          Engine.holdShow = token
          if C_Timer and C_Timer.After then C_Timer.After(Engine.HOLD_SECS, function() if Engine.holdShow == token then Engine.holdShow = nil; ns.Fire("FR_STEP", Engine.Shown()) end end) end
        end
        ns.Next.PickAsync(planned, function(pick)
          local wasHeld = Engine.holdShow == token
          if wasHeld then Engine.holdShow = nil end
          if Engine.planned ~= planned or steps() ~= list then if wasHeld then ns.Fire("FR_STEP", Engine.Shown()) end return end
          local was = Engine.current
          if pick then Engine.picked = list end -- (a solve has chosen the card's step on this route: a flight may hold it)
          Engine.ShowPick(pick or planned)
          if wasHeld and Engine.current == was then ns.Fire("FR_STEP", Engine.Shown()) end
        end)
      else
        local ok, pick = ns.Call(ns.Next.Pick, Engine.current)
        if ok and pick then Engine.picked = steps() end
        -- (a pick is shown only while it is still to do - skipped, ticked or not offered: not again; as Engine.ShowPick)
        -- (or the quest from behind you it just took: its status was worked out a moment before it was taken)
        if ok and pick and (Engine.Status(pick) == "todo" or (ns.Next.taken and ns.Next.taken == steps()[pick])) then Engine.current = pick elseif not ok and ns.LogError then ns.LogError("next", pick) end
      end
    end
  else
    local fi = Engine.focus
    if fi and fi ~= Engine.current then
      local st = Engine.Status(fi)
      if st == "todo" and fi > (Engine.current or 0) then Engine.current = fi else Engine.focus = nil end
    end
  end
  if Engine.view and Engine.view == Engine.current then Engine.view = nil end
  -- the "done" cue only when the step you were on really got done: the current step also moves when live reordering
  -- picks another step, when you abandon a quest, when a level-up opens an earlier step, or after a jump
  if before and Engine.current ~= before and not quiet and beforeStep then
    local list, at = steps(), before
    if list[at] ~= beforeStep then at = planIndex().idx[beforeStep] end -- a stop was inserted before it, or another route
    -- skipped or "not doing" isn't done: no tick for those either
    local dropped = ns.char.skipped[key(at or 0) or ""] or (beforeStep.q and ns.Nope(beforeStep.q))
    if at and Engine.Status(at) == "done" and not dropped then ns.Fire("FR_STEP_DONE", at) end
  end
  if not Engine.holdShow and not Engine.noSolve then ns.Fire("FR_STEP", Engine.Shown()) end
end
Engine.HOLD_SECS = 0.3

-- Look at step i (a click on its row in the card, the route window, a map pin or the zones tab): right-click shows it
-- on the map, shift-click jumps there (noJump: not from here), a click looks at it - the step you are on ends looking.
-- One rule for every row
function Engine.Look(i, btn, noJump)
  if not i then return end
  if btn == "RightButton" then ns.ShowOnMap(i) return end
  if IsShiftKeyDown() and not noJump then Engine.Jump(i) return end
  Engine.view = (i ~= Engine.CardAt()) and i or nil
  ns.Fire("FR_STEP", Engine.Shown())
end
-- history entries let Undo restore accidental skips/dones; one entry may cover several steps
local function remember(kind, ids) table.insert(ns.char.history, { kind = kind, ids = ids }); if #ns.char.history > 50 then table.remove(ns.char.history, 1) end end
Engine._remember = remember -- (Engine/Worth.lua)
-- the writers of your route state: a skip, a tick or a skip taken back, a quest back from "not doing" (a tick only
-- adds a done step: no new generation)
function Engine.SetSkipped(id) ns.char.skipped[id] = true; Engine.StateChanged() end
function Engine.Untick(id) ns.char.skipped[id] = nil; ns.char.manualDone[id] = nil; Engine.StateChanged() end
function Engine.BringBack(q) if ns.char.nope then ns.char.nope[q] = nil end; Engine.GrayForget(); Engine.StateChanged() end

local function markDone(i)
  i = i or Engine.Shown(); local id = key(i); if not id then return end
  ns.char.manualDone[id] = true
  remember("done", { id })
  Engine.view = nil
  Engine.Refresh()
end
-- you clicked done (the card's check, a slash command): Learn.lua records it as "ticked by hand"
function Engine.MarkDone(i) return markDone(i) end
-- the game told us (you arrived, landed, set your hearth, took the flight, trained): the same tick, not a hand tick -
-- through MarkDone these would go into the learning data as things the route got wrong
function Engine.AutoDone(i) return markDone(i) end
function Engine.Skip(i)
  i = i or Engine.Shown(); local s = steps()[i]; if not s then return end
  local ids = { key(i) }
  Engine.SetSkipped(key(i))
  -- skipping a quest you don't have: its later objective / turn-in steps go too
  local skipQ
  if s.q and (s.k == "accept" or not State.OnQuest(s.q)) and not State.IsCompleted(s.q) then
    for j = i + 1, #steps() do local t = steps()[j]; if t.q == s.q and not ns.char.skipped[key(j)] then Engine.SetSkipped(key(j)); ids[#ids + 1] = key(j) end end
    -- (and its pick-up on every route, not this one only: a zone you pick, its own route, had it back on the card -
    -- ns.char.skipQ, per character, until undone or you take the quest)
    if s.k == "accept" and s.q > 0 and not State.OnQuest(s.q) then ns.char.skipQ = ns.char.skipQ or {}; ns.char.skipQ[s.q] = true; skipQ = s.q end
  end
  remember("skip", ids)
  if skipQ then ns.char.history[#ns.char.history].skipQ = skipQ end
  Engine.view = nil
  if ns.ZoneCountsChanged then ns.ZoneCountsChanged() end -- (Where to?'s counts: a skipped pick-up cuts its chain)
  Engine.Refresh()
end
function Engine.Undo()
  local h = table.remove(ns.char.history)
  if not h then ns.Print("nothing to undo."); return end
  for _, id in ipairs(h.ids) do Engine.Untick(id) end
  if h.skipQ and ns.char.skipQ then ns.char.skipQ[h.skipQ] = nil; Engine.StateChanged() end
  Engine.ResetFloor() -- (what you undid may be behind your place in the plan: it is yours again)
  for _, q in ipairs(h.nope or {}) do Engine.BringBack(q) end
  Engine.view = nil
  -- (the giver had nothing for you, undone: those quests are offered as far as the route knows, that giver too)
  if h.avail and ns.Avail and ns.Avail.Unjudge then
    ns.Avail.Unjudge(h.avail, h.npc)
    if ns.Why then ns.Why("avail", tostring(h.npc) .. ": \"nothing for you\" undone - " .. #h.avail .. " quest(s) back on your route") end
  end
  if ns.ZoneCountsChanged then ns.ZoneCountsChanged() end -- (Where to?'s counts: what you undid counts again)
  Engine.Refresh()
  ns.Print(h.kind == "skip" and "skip undone." or (h.kind == "nope" or h.kind == "notoffered") and "back on your route." or "undone.")
end
-- look at the previous step (view only; progress is unchanged)
function Engine.Back()
  Engine.StateChanged()
  local cur = Engine.Shown() or (#steps() + 1)
  if cur <= 1 then return end
  Engine.view = cur - 1
  ns.Fire("FR_STEP", Engine.view)
end
function Engine.Forward()
  if not Engine.view then return end
  local nxt = Engine.view + 1
  Engine.view = (Engine.current and nxt < Engine.current) and nxt or nil
  ns.Fire("FR_STEP", Engine.Shown())
end
-- jump: backwards = view it; forwards = skip what's in between (undoable)
function Engine.Jump(i)
  -- (while a route change's passes run, the plan's numbers move: the jump waits, by the step itself)
  if Engine.Busy() then
    local s = steps()[i]
    return Engine.WhenIdle(function() local j = s and planIndex().idx[s]; if j then Engine.Jump(j) end end)
  end
  local list = steps()
  if not list[i] then return end
  if not Engine.current or i <= Engine.current then
    Engine.view = (i ~= Engine.current) and i or nil
    ns.Fire("FR_STEP", Engine.Shown())
    return
  end
  local ids = {}
  for j = Engine.current, i - 1 do if not Engine.IsDone(j) then local id = key(j); Engine.SetSkipped(id); ids[#ids + 1] = id end end
  remember("skip", ids)
  Engine.view = nil
  if ns.ZoneCountsChanged then ns.ZoneCountsChanged() end -- (Where to?'s counts: a skipped pick-up cuts its chain)
  Engine.Refresh()
end

function Engine.Arrived(i)
  if Engine.Busy() then return end -- (the arrow says it again once the route change's passes are done)
  local s = steps()[i]
  if s and s.k == "goto" and i == Engine.current then Engine.AutoDone(i) end
end

local function currentStep() local i = Engine.current; return i, i and steps()[i] end
local function nearCurrent(kind, within)
  -- the first not-done step of this kind among the next few (lets you do things a little early) - counted from the
  -- plan's place, not the card's (a quest from elsewhere on the card must not stop the plan's step ticking)
  -- (but the card's own step first, when it is of this kind: what you did is what it showed - else, with the plan's
  -- place on a stop the solve passed, the card's step never ticked and kept coming back)
  local c = Engine.CardAt and Engine.CardAt()
  local cs = c and steps()[c]
  if cs and cs.k == kind and not Engine.IsDone(c) then return c end
  local i = Engine.planned or Engine.current -- (not PlanAt: that is the step you look at while you browse the route)
  if not i then return nil end
  for j = i, math.min(#steps(), i + (within or 0)) do
    local s = steps()[j]
    if s.k == kind and not Engine.IsDone(j) then return j end
  end
end

ns.On("FR_STATE", function() Engine.Refresh() end)
-- The passes that fit stops into the route after a login or a route change, in this order: the hand-ins of quests you
-- finished (Inserts.lua), your side quests' objectives (Side.lua), side trips and flight paths on the way (Inserts.lua).
-- Each says whether it added a stop; the route is refreshed once after them all (a refresh after each was the same
-- work again, on a route the next pass was about to change)
Engine.PASSES = { { "inserts", "ApplyInserts" }, { "side", "SideStops" }, { "merge", "MergeSideTrips" } }
local function pass(p) local fn = Engine[p[2]]; return fn and fn() end
-- A login's (or a /reload's) catch-up: a look 1 s after the world is there, and at 3 s the flight paths you know
-- (State.ScanTaxi) and the passes, with one refresh (not a timer and refresh each). A loading screen later (an
-- instance, a boat) has the looks only
local loginDue
function Engine.LoginDue() loginDue = true end -- (FR_LOADED: the next PLAYER_ENTERING_WORLD is a login)
ns.On("FR_LOADED", Engine.LoginDue)
local function loginCatchUp() -- (PLAYER_ENTERING_WORLD)
  quiet = true
  local login = loginDue
  loginDue = nil
  C_Timer.After(1, function() Engine.RefreshBg() end)
  C_Timer.After(3, function()
    -- (in the game: the passes as route jobs, as a route change's, and the refresh after them a job too - a slice a
    -- frame, the card holding its step meanwhile. All of it in this frame was 20-40 ms in the simulator and up to
    -- 470 ms on a player's PC at level 50, the game's caches cold. Under ns.Jobs.SYNC - tests, simulated players,
    -- replays - one frame, as it was)
    if login and not ns.Jobs.SYNC then
      Engine.Coalesce(function()
        local ok, e = pcall(ns.State.ScanTaxi); if not ok then ns.LogError("taxi", e) end
        for _, p in ipairs(Engine.PASSES) do Engine.Post(p[1], function() pass(p) end) end
        Engine.Post("refresh", function() Engine.Refresh(); quiet = false end, function() quiet = false end)
      end)
      return
    end
    Engine.Coalesce(function()
      if login then
        local ok, e = pcall(ns.State.ScanTaxi); if not ok then ns.LogError("taxi", e) end
        for _, p in ipairs(Engine.PASSES) do local ok2, e2 = pcall(pass, p); if not ok2 then ns.LogError(p[1], e2) end end
      end
      Engine.Refresh()
    end)
    quiet = false
  end)
end
-- a route change's passes: each a route job of its own at its time (one that fails doesn't stop the rest), and the
-- refresh after the last when any added
ns.On("FR_ROUTE_CHANGED", function()
  local added = false
  for k, p in ipairs(Engine.PASSES) do Engine.After(0.45 + 0.05 * k, p[1], function() if pass(p) then added = true end end) end
  Engine.After(0.65, "refresh", function() if added then Engine.Refresh() end end)
end)
ns.On("PLAYER_XP_UPDATE", function() local _, s = currentStep(); if s and s.k == "grind" then Engine.Refresh() end end)
-- fly steps carry no coordinates, so the arrow and pins point at the nearest flight master in your zone (FlightMasters.lua)
local function inZone(to)
  local m = ns.State.Position()
  local guard = 0
  while m and guard < 6 do
    if m == to then return true end
    local info = C_Map.GetMapInfo(m); m = info and info.parentMapID; guard = guard + 1
  end
  return false
end
-- arriving in the destination zone completes a fly step, however you got there (flew, rode, or were already there)
Engine.InZone = inZone
local function travelDone()
  local i, s = currentStep()
  if s and s.k == "fly" and s.to and inZone(s.to) then Engine.AutoDone(i) end
end
-- (what acts on the card's or the plan's step by its number waits while a route change's passes move the numbers:
-- Engine.Idle)
travelDone = Engine.Idle(travelDone)
local function zoneArrived() C_Timer.After(1, function() travelDone(); Engine.RefreshBg() end) end -- (ZONE_CHANGED_NEW_AREA)
local function travelDoneLater() C_Timer.After(4, travelDone) end -- (PLAYER_ENTERING_WORLD)
ns.On("HEARTHSTONE_BOUND", function()
  -- remember where you bound (the map you were on and the name the game gives it); every hearth step on that map
  -- counts as done while you stay bound there
  local m = ns.State.Position()
  -- (bound at one of the plan's bind stops - its innkeeper within 100 yd: that stop's own map, so the bind step and
  -- every hearth to it match whatever map id the game hands out indoors)
  local HBDx = LibStub("HereBeDragons-2.0")
  local px, py, pinst = HBDx:GetPlayerWorldPosition()
  if px then
    for _, t in ipairs(steps()) do
      if t.k == "bind" and t.m and t.x then
        local x, y, inst = HBDx:GetWorldCoordinatesFromZone(t.x, t.y, t.m)
        if x and inst == pinst and (x - px) ^ 2 + (y - py) ^ 2 <= 100 * 100 then m = t.m; break end
      end
    end
  end
  ns.char.boundAt = { m = m, name = GetBindLocation and GetBindLocation() or nil }
  C_Timer.After(0.5, function() ns.char.boundAt.name = GetBindLocation and GetBindLocation() or ns.char.boundAt.name; Engine.Refresh() end)
  Engine.Refresh()
end)
-- standing in the place your hearthstone is set (the game's name for it is the name of where you are): that is the
-- map it is on, whenever you set it - before the addon, or while it was off
local function learnBind()
  local okB, b = pcall(GetBindLocation)
  if not okB or type(b) ~= "string" or b == "" or not ns.char then return end
  local at = ns.char.boundAt
  if at and at.name == b and at.m then return end
  local okS, sub = pcall(GetSubZoneText); local okZ, zone = pcall(GetRealZoneText)
  if not ((okS and sub == b) or (okZ and zone == b)) then return end
  local m = ns.State.Position()
  if not m then return end
  ns.char.boundAt = { m = m, name = b }
  if ns.Why then ns.Why("hearth", "your hearthstone is set here (" .. b .. "): noted") end
end
Engine.LearnBind = learnBind
local function bindSeen() pcall(learnBind) end
for _, ev in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }) do ns.On(ev, bindSeen) end
local function bindLater() C_Timer.After(2, bindSeen) end -- (PLAYER_ENTERING_WORLD)
-- opening a flight map ticks a "get the flight path" step only at that flight master (same map) - not when you
-- open the map somewhere else to fly toward it (the zone check in the step status covers learning it normally)
ns.On("FR_TAXI_OPENED", Engine.Idle(function()
  local j = nearCurrent("fp", 3); if not j then return end
  local s = steps()[j]; local m = ns.State.Position()
  if s and (not s.m or s.m == m) then Engine.AutoDone(j) end
end))
-- hearthstone cast: complete a hearth step
ns.On("UNIT_SPELLCAST_SUCCEEDED", Engine.Idle(function(unit, _, spellID)
  if unit ~= "player" then return end
  if spellID == 8690 then local j = nearCurrent("hearth", 1); if j then Engine.AutoDone(j) end end
end))
-- landing from a flight: complete a fly step (if it names a destination map, be in it)
local onTaxi = false
ns.On("PLAYER_CONTROL_LOST", function() C_Timer.After(0.5, function() onTaxi = ns.Is(UnitOnTaxi, "player") end) end)
ns.On("PLAYER_CONTROL_GAINED", Engine.Idle(function()
  if not onTaxi then return end
  onTaxi = false
  local j = nearCurrent("fly", 1)
  if j then
    local s = steps()[j]
    local m = ns.State.Position()
    -- (no position yet, as at a loading screen: an unnamed flight still counts, a named one waits for the zone change)
    local info = m and C_Map.GetMapInfo(m)
    if not s.to or s.to == m or (info and info.parentMapID == s.to) then Engine.AutoDone(j) end
  end
end))
-- class trainer visits complete a train step (profession trainers don't)
local atClassTrainer = false
ns.On("TRAINER_SHOW", function() atClassTrainer = not (IsTradeskillTrainer and IsTradeskillTrainer()) end)
ns.On("TRAINER_CLOSED", function()
  if not atClassTrainer then return end
  atClassTrainer = false
  -- (not a stop that waits for your level - "Nothing to learn until level N": you learned nothing there, and once
  -- ticked it never came back)
  Engine.WhenIdle(function() local j = nearCurrent("train", 4); if j and Engine.Status(j) ~= "wait" then Engine.AutoDone(j) end end)
end)

-- The engine's handlers of entering the world and of a new zone: one per event, its steps in this order (each on its
-- own: one that fails doesn't stop the rest). Dungeon.lua's handlers run before these, Boats.lua's and the UI's after.
local function inOrder(ev, fns)
  return function(...)
    for _, fn in ipairs(fns) do local ok, err = pcall(fn, ...); if not ok and ns.LogError then ns.LogError(ev, err) end end
  end
end
ns.On("PLAYER_ENTERING_WORLD", inOrder("PLAYER_ENTERING_WORLD",
  { dungeonSeen, worldReady, function() Engine.StateChanged() end, loginCatchUp, travelDoneLater, bindLater }))
ns.On("ZONE_CHANGED_NEW_AREA", inOrder("ZONE_CHANGED_NEW_AREA", { dungeonSeen, insideChanged, zoneArrived, bindSeen }))

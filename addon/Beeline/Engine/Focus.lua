-- The route engine, live reordering: what you are plainly doing, the solve as you move (Engine.UpdateFocus, Repick).
-- Loaded right after Engine.lua, so its event handlers run in the same order as before the split.
local _, ns = ...
local Engine = ns.Engine
local State = ns.State
local function steps() return BeelineData and BeelineData.steps or {} end
local function key(i) return Engine.Key(i) end
local wpos = ns.Util.WPos

----------------------------------------------------------------------------------------------------------------
-- Live reordering: follow what you're actually doing. Among the next few steps (same map), a later one is shown
-- first when your kills / loot count for it, when you're standing in its area, or when the planned step is far and
-- it's right here. Nothing is skipped: once it's done, the planned order comes back. It holds until done or until
-- you walk well away, so it doesn't flicker.
----------------------------------------------------------------------------------------------------------------
local function distTo(s, px, py, pinst) local w = wpos(s); if not w or w[3] ~= pinst then return nil end return math.sqrt((w[1] - px) ^ 2 + (w[2] - py) ^ 2) end
local WINDOW = 10
Engine.READY_NEAR = 300  -- yards: near enough that the card takes you there now (the town you are in), when clearly nearer than the plan
local lastHave = {}   -- [step key] = objective count last seen
local progressAt = {} -- [step key] = GetTime() when that count last went up
local progressWhere = {} -- [step key] = { x, y, inst }: where you stood when it did (world yards)
Engine.PROGRESS_HOLD = 90 -- a focus your kills made holds this long after the last one, wherever you are
-- and while you stay where they counted (within PROGRESS_YD of the last one), up to PROGRESS_STAY after it: a rare drop
-- (12 Eldarath Relics off naga) can take longer than PROGRESS_HOLD between counts, and the card went off to a hand-in
-- 300 yd away mid-farm
Engine.PROGRESS_YD = 200
Engine.PROGRESS_STAY = 600

-- kind: "area" (you're standing at it / it's right next to you) or "progress" (your kills / loot count for it).
-- They're held differently in UpdateFocus: kill spots are often wider than the one marker the planner picks.
local function setFocus(i, why, kind)
  if Engine.focus == i then return end
  Engine.focus, Engine.focusWhy, Engine.focusAt = i, kind or "area", GetTime()
  local s = steps()[i]
  if ns.Why and s then ns.Why("reorder", "now on step " .. i .. " (" .. (s.name or s.text or s.k) .. "): " .. (why or "")) end
  Engine.Refresh()
end
-- a finished quest whose hand-in is close by, wherever the plan has it: the card's "ready nearby" line. Its own
-- check, not the live reordering's: one line you choose from, nothing moves by itself. -> { i, q, name, npc, d } or nil
Engine.READY_LINE_YD = 300 -- within the hold of a chosen hand-in (READY_NEAR + 40)
function Engine.ReadyNearby(px, py, pinst)
  if not px then return nil end
  local list, shown, best = steps(), Engine.Shown(), nil
  for j, s in ipairs(list) do
    if s.k == "turnin" and s.q and s.q > 0 and j ~= shown and State.QuestReady(s.q) then
      local d = distTo(s, px, py, pinst)
      if d and d <= Engine.READY_LINE_YD and (not best or d < best.d) and Engine.Status(j) == "todo" then best = { i = j, q = s.q, name = s.name, npc = s.npc, d = d } end
    end
  end
  return best
end
-- you picked it ("Do it now"): the card shows it until it's handed in (held like a ready hand-in the card picked)
function Engine.FocusOn(i, why) if i then setFocus(i, why or "you chose it", "chosen") end end

-- can you do this step right now? A pick-up whose earlier chain quest isn't handed in yet isn't offered, and a
-- hand-in needs the quest in your log
local prereqOf
-- the quests that must be handed in before this one is offered (the plan's BeelineUnlocks, turned around)
function Engine.PrereqsOf(q)
  if prereqOf == nil or prereqOf.src ~= BeelineUnlocks then
    prereqOf = { src = BeelineUnlocks }
    for p, list in pairs(BeelineUnlocks or {}) do for _, d in ipairs(list) do prereqOf[d] = prereqOf[d] or {}; table.insert(prereqOf[d], p) end end
  end
  return prereqOf[q] or {}
end
function Engine.Available(j)
  local s = steps()[j]
  if not s or not s.q or s.q <= 0 then return true end
  if s.k == "turnin" then return State.OnQuest(s.q) and true or false end
  if s.k ~= "accept" then return true end
  for _, p in ipairs(Engine.PrereqsOf(s.q)) do if not State.IsCompleted(p) then return false end end
  -- (nor once you took one of its alternatives elsewhere: Engine.Excluded)
  if Engine.Excluded(s) then return false end
  -- and the quest data's own prerequisites, whatever the plan carries (QuestData.lua ns.QUEST_PRE): all of g, one of s
  return State.PrereqsMet(s.q)
end
-- why a step can't be done at this moment, or nil when it can. For the pins: a step you can't act on yet must not
-- look like an instruction. Returns a reason and, where the route has it, the step that opens this one:
--   "level", nil, N        waits for level N
--   "pickup", j            its quest isn't in your log; step j picks it up
--   "handin", j            a pick-up whose earlier chain quest isn't handed in; step j hands it in
--   "objectives", j        a hand-in with objectives left; step j is the first of them
--   "dungeon", nil, name   left for your next run of that dungeon
--   "full"                 a pick-up while your quest log is full
local questSteps = setmetatable({}, { __mode = "k" })
-- kind -> quest -> the plan's step indices of that kind for that quest, in order (kept per list generation)
local function stepsOfQuest(list)
  local c = questSteps[list]
  if c and c.gen == (list._gen or 0) then return c.by end
  c = { gen = list._gen or 0, by = {} }
  for j, t in ipairs(list) do
    if t.k and t.q ~= nil then
      local byK = c.by[t.k]; if not byK then byK = {}; c.by[t.k] = byK end
      local l = byK[t.q]; if not l then l = {}; byK[t.q] = l end
      l[#l + 1] = j
    end
  end
  questSteps[list] = c
  return c.by
end
function Engine.NotYet(i)
  local list = steps()
  local s = list[i]
  if not s then return nil end
  local st = Engine.Status(i)
  if st == "done" then return nil end
  if st == "wait" then
    -- (training: the lowest level it names - Engine.TrainFrom; no level at all is nil, never "at level 0" on the pin)
    local lv = math.max(s.minLevel or s.until_ or 0, Engine.TooHigh(s) or 0, Engine.TrainFrom(i) or 0)
    if lv > 0 then return "level", nil, lv end
    -- (a pick-up whose earlier quest is not handed in: falls through to "handin" below with that hand-in's step)
    if not (s.q and not State.PrereqsMet(s.q)) then return "level" end
  end
  if st == "full" then return "full" end
  if st == "later" then
    local name = Engine.InsideOf(s)
    if not name then for _, j in ipairs(Engine.ObjStepsOf(s.q)) do name = name or Engine.InsideOf(list[j]) end end
    -- (no dungeon: a hand-in waiting on work the quest data has no place for, whose step you skipped)
    if not name then for _, j in ipairs(Engine.ObjStepsOf(s.q)) do if list[j].unknown then return "objectives", j end end end
    return "dungeon", nil, name
  end
  if st == "notready" then
    for _, j in ipairs(Engine.ObjStepsOf(s.q)) do if j ~= i and not Engine.IsDone(j) then return "objectives", j end end
    return "objectives"
  end
  -- the step of that kind for that quest still to do: the last one before this step, else the first one after it
  -- (from an index kept per plan list: the map pins ask this for every pin, every refresh)
  local function opener(kind, q)
    local found
    local idx = q ~= nil and stepsOfQuest(list)
    for _, j in ipairs(idx and (idx[kind] and idx[kind][q] or {}) or {}) do
      if not Engine.IsDone(j) then
        if j < i then found = j elseif not found then return j end
      end
    end
    if not idx then
      for j, t in ipairs(list) do
        if t.k == kind and t.q == q and not Engine.IsDone(j) then
          if j < i then found = j elseif not found then return j end
        end
      end
    end
    return found
  end
  if st == "blocked" then return "pickup", opener("accept", s.q) end
  if s.k == "accept" and s.q and s.q > 0 then
    for _, p in ipairs(Engine.PrereqsOf(s.q)) do if not State.IsCompleted(p) then return "handin", opener("turnin", p) end end
  end
  if st == "wait" then return "handin" end
  return nil
end
-- the way to the shown step can change while the step stays the same: a flight that beats the walk stops doing so
-- halfway (and starts again if you wander back). The arrow only re-targets when the step or zone changes, so this
-- is watched here once a second with the focus, and card and arrow are told. Only a step in your current zone.
local shortcutSeen
-- (a fresh trip plan costs up to 3 ms; asked again only after moving WATCH_MOVE of the map (~20-50 yd) or a step
-- change: whether a flight beats the walk doesn't flip in less)
local watchAt = {}
Engine.WATCH_MOVE = 0.01
function Engine.WatchShortcut()
  local i = Engine.Shown()
  local s = i and steps()[i]
  local pm, px, py = State.Position()
  if s and px and watchAt.s == s and watchAt.m == pm and math.abs(px - watchAt.x) < Engine.WATCH_MOVE
    and math.abs(py - watchAt.y) < Engine.WATCH_MOVE and watchAt.i == i and watchAt.n == State.KnownTaxiCount() then return false end
  watchAt.s, watchAt.m, watchAt.x, watchAt.y, watchAt.i, watchAt.n = s, pm, px, py, i, px and State.KnownTaxiCount()
  local t = s and s.k ~= "fly" and s.m and s.x and s.m == pm and Engine.TravelFor(s)
  local sig = (i or 0) .. ":" .. ((t and t.shortcut) and (tostring(t.how) .. ":" .. tostring(t.m) .. ":" .. tostring(t.x) .. ":" .. tostring(t.y)) or "-")
  local was = shortcutSeen
  shortcutSeen = sig
  if was == nil or was == sig or was:match("^(%d+):") ~= tostring(i or 0) then return false end
  if ns.Arrow and ns.Arrow.SetTarget then ns.Arrow.SetTarget(i, true) end
  ns.Fire("FR_STEP", i)
  return true
end
local nextFrom -- { x, y, inst, t }: where the live solver last ran from
-- You moved on (30 yd, or 5 s): only the next stop's solve can change - the plan's statuses don't move with you. It
-- runs in the background, a slice a frame (Next.PickAsync); the card changes (full refresh, which finds that solve
-- remembered) only when it picks another step. A full refresh each time was 20-50 ms in one frame.
function Engine.Repick()
  local planned = Engine.planned
  if not (planned and ns.Next and ns.Next.PickAsync) then return Engine.Refresh() end
  -- (what the full refresh would keep without a solve: a flight, a step you chose or are farming)
  if ns.Is and UnitOnTaxi and ns.Is(UnitOnTaxi, "player") then return end
  local why = Engine.focusWhy
  if Engine.Holding() then return end
  if Engine.focus and why == "progress" then return Engine.Refresh() end -- (its hold just ended: the full look lets it go)
  if Engine.RecentProgress(planned) then return end
  local list = steps()
  ns.Next.PickAsync(planned, function(pick)
    if Engine.planned ~= planned or steps() ~= list then return end -- (the route moved on meanwhile: that refresh solved again)
    Engine.ShowPick(pick or planned)
  end)
end
-- called by the arrow driver about once a second with your position
function Engine.UpdateFocus(px, py, pinst)
  if Engine.Busy() then return end -- (a route change's passes are moving the steps: the next look, after them)
  Engine.WatchShortcut()
  Engine.SideOffer(px, py, pinst)
  if Engine.view or not px then return end
  -- dead or a ghost: you can't take or hand in anything, so the ghost's position doesn't count - the card keeps its
  -- step (the arrow points to your corpse) and solves again once you're alive
  if ns.Is(UnitIsDeadOrGhost, "player") then nextFrom = nil; return end
  -- the live solver decides the order: it runs again as you move (30 yd, or every 5 s), the focus rules don't
  if ns.Next and ns.Next.Enabled() then
    local now = GetTime()
    Engine.pos = { px, py, pinst, now } -- (the solve starts from here: the position this check measured)
    if not nextFrom or nextFrom.inst ~= pinst or (px - nextFrom.x) ^ 2 + (py - nextFrom.y) ^ 2 > 900 or now - nextFrom.t > 5 then
      nextFrom = { x = px, y = py, inst = pinst, t = now }
      Engine.Repick()
    end
    return
  end
  Engine.pos = { px, py, pinst, GetTime() } -- (where you are, for a hold your kills made: Engine.RecentProgress)
  local planned = Engine.planned or Engine.current
  if not planned then return end
  local list = steps()
  -- standing at an NPC you can hand a finished quest to: that hand-in, now - wherever the plan has it, over any other
  -- step the card holds. Not the planned step itself: that one is shown anyway
  do
    local best, bestD
    for j, s in ipairs(list) do
      if s.k == "turnin" and s.q and s.q > 0 and j ~= planned and State.QuestReady(s.q) and not (ns.Next and ns.Next.IsDismissed and ns.Next.IsDismissed(j, px, py, pinst)) then
        local d = distTo(s, px, py, pinst)
        if d and d <= (s.r or 6) + 12 and (not bestD or d < bestD) and Engine.Status(j) == "todo" then best, bestD = j, d end
      end
    end
    if best then
      if Engine.focus ~= best then setFocus(best, "it is ready to hand in and you are at the NPC", "ready") end
      return
    end
  end
  -- hold the current focus while it's open and you're still near it - or, when your kills / loot made it, while they
  -- keep counting (however far from its marker you farm)
  if Engine.focus then
    local s = list[Engine.focus]
    local d = s and distTo(s, px, py, pinst)
    if s and Engine.Status(Engine.focus) == "todo" then
      if not d or d <= (s.r or 40) + 80 then return end
      -- a finished quest's hand-in the card is taking you to: held while you head there (it was picked from up to
      -- READY_NEAR away), until it's handed in
      if (Engine.focusWhy == "ready" or Engine.focusWhy == "chosen") and d <= Engine.READY_NEAR + 40 and State.QuestReady(s.q) then return end
      if Engine.focusWhy == "progress" and Engine.RecentProgress(Engine.focus) then return end
    end
    Engine.LetGoFocus()
  end
  local ps = list[planned]
  local dP = ps and distTo(ps, px, py, pinst)
  if dP and dP <= (ps.r or 40) + 10 then return end -- you're at the planned step: nothing to do
  -- farming the planned kill / loot step: its mobs roam well past the one marker the planner picked
  if ps and ps.k == "obj" and dP and dP <= 2 * (ps.r or 40) + 80 then return end
  -- never past a step you are making progress on (its kills / loot counted in the last PROGRESS_HOLD seconds)
  local function busyBefore(j)
    for i = planned, j - 1 do local t = progressAt[key(i)]; if t and GetTime() - t <= Engine.PROGRESS_HOLD then return true end end
    return false
  end
  local inArea, near, nearD
  for _, j in ipairs(Engine.Upcoming(planned, WINDOW)) do
    local s = list[j]
    -- an NPC stop you're standing at (pick-up, hand-in, flight path) - not a kill / loot step: walking through a
    -- quest's circle doesn't mean you're doing it (circles overlap); those take over when your kills or loot count
    -- for them (FR_STATE below)
    if Engine.Status(j) == "todo" and (s.k == "accept" or s.k == "turnin" or s.k == "fp") and Engine.Available(j) then
      local d = distTo(s, px, py, pinst)
      if d then
        if d <= (s.r or 40) and not inArea then inArea = j end
        if d < 120 and (not nearD or d < nearD) then near, nearD = j, d end
      end
    end
  end
  local pick = inArea
  if not pick and near and dP and dP > 200 and nearD < dP * 0.4 then pick = near end
  if pick and busyBefore(pick) then pick = nil end
  local why = inArea and "you are standing at it" or "it is right next to you and your planned step is far away"
  -- a quest already done (or a delivery) whose hand-in is right here though the plan hands it in much later: hand it
  -- in while you're here, not on a trip back
  if not pick then
    local best, bestD
    -- (cheap checks first - this runs every second: a hand-in, its quest ready in your log, near you - then its status)
    for j = planned + 1, #list do
      local s = list[j]
      if s.k == "turnin" and s.q and s.q > 0 and State.QuestReady(s.q) then
        local d = distTo(s, px, py, pinst)
        if d and d <= Engine.READY_NEAR and (not dP or d < dP * 0.8) and (not bestD or d < bestD) and Engine.Status(j) == "todo" then best, bestD = j, d end
      end
    end
    if best then setFocus(best, "it is ready to hand in and it is close by (the plan has it later)", "ready"); return end
  end
  if pick then setFocus(pick, why) end
end

-- where you stand as a count moves: the arrow's last measure when fresh, else asked once (a count, not every frame)
local HBD = LibStub and LibStub("HereBeDragons-2.0", true)
local function whereNow()
  local p = Engine.pos
  if p and GetTime() - (p[4] or 0) < 3 then return { p[1], p[2], p[3] } end
  local x, y, inst
  if HBD then x, y, inst = HBD:GetPlayerWorldPosition() end
  if x then return { x, y, inst } end
  return p and { p[1], p[2], p[3] } or nil
end
-- kills / loot counting for a later objective: that's what you're doing (FR_PROGRESS: only a count moved)
local function countsMoved()
  local planned = Engine.planned or Engine.current
  if not planned or Engine.view then return end
  local list = steps()
  -- the planned step too: its loot counting means you're on it (UpdateFocus never jumps past it then), and if the card
  -- had moved on to another step, it comes back
  local js = Engine.Upcoming(planned, WINDOW); table.insert(js, 1, planned)
  -- (and the card's step when the solve picked another: otherwise farming it set no hold and the card could leave)
  local cur = Engine.current
  if cur and cur ~= planned then local seen = false; for _, j in ipairs(js) do if j == cur then seen = true end end; if not seen then js[#js + 1] = cur end end
  for _, j in ipairs(js) do
    local s = list[j]
    if s and s.k == "obj" and not Engine.IsDone(j) then
      local o = Engine.ObjectiveFor(s)
      local k = key(j)
      if o and o.have then
        if lastHave[k] and o.have > lastHave[k] and not o.finished then
          progressAt[k] = GetTime()
          progressWhere[k] = whereNow()
          if j == planned then
            if (Engine.focus and Engine.focus ~= planned) or Engine.current ~= planned then Engine.focus, Engine.focusWhy = nil, nil; Engine.Refresh() end
          elseif Engine.focus == j then Engine.focusWhy = "progress" -- shown for being here, now also counting: hold it as such
          else setFocus(j, "you are making progress on it", "progress") end -- (the card's own pick too: held while you farm it)
        end
        lastHave[k] = o.have
      end
    end
  end
end
ns.On("FR_STATE", countsMoved)
ns.On("FR_PROGRESS", countsMoved)
ns.On("FR_ROUTE_CHANGED", function() Engine.focus = nil; wipe(lastHave); wipe(progressAt); wipe(progressWhere) end)
-- did your kills or loot count for this step lately (Engine.PROGRESS_HOLD), or are you still where they counted
-- (Engine.PROGRESS_YD, Engine.PROGRESS_STAY)? You're plainly on it, then. Your place is the one the arrow's check
-- measured last (Engine.pos, once a second): no position read here
function Engine.RecentProgress(i)
  local k = i and key(i)
  local t = k and progressAt[k]
  if not t then return false end
  local age = GetTime() - t
  if age <= Engine.PROGRESS_HOLD then return true end
  if age > Engine.PROGRESS_STAY then return false end
  local at, p = progressWhere[k], Engine.pos
  return at ~= nil and p ~= nil and p[3] == at[3] and (p[1] - at[1]) ^ 2 + (p[2] - at[2]) ^ 2 <= Engine.PROGRESS_YD ^ 2
end
-- why a hold your kills made ended (for the why line): "no kill or loot counted for it in N s, and you moved away"
function Engine.ProgressEnded(i)
  local t = i and progressAt[key(i)]
  if not t then return "nothing counted for it" end
  return "no kill or loot counted for it in " .. math.floor(GetTime() - t) .. " s" .. (GetTime() - t > Engine.PROGRESS_STAY and "" or ", and you moved away from where it counted")
end

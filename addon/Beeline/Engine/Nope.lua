-- The route engine, "not doing this quest" and quests you abandoned. Loaded right after Engine.lua, so its event
-- handlers run in the same order as before the split.
local _, ns = ...
local Engine = ns.Engine
local State = ns.State
local function steps() return BeelineData and BeelineData.steps or {} end

----------------------------------------------------------------------------------------------------------------
-- "Not doing this quest": drops it from the route (all its steps), from future plans (the planner reads the list),
-- and from stop insertion. If later quests on the route need it (BeelineUnlocks from the plan), you're warned
-- first and they go too. Undo brings everything back.
----------------------------------------------------------------------------------------------------------------
local function questName(q)
  for _, s in ipairs(steps()) do if s.q == q and s.name then return s.name end end
  local e = BeelineEnders and BeelineEnders[q]
  if e and e.name then return e.name end
  local t = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(q)
  return t or ("quest " .. q)
end
Engine.QuestName = questName
-- the quests you said you won't do: { q, name, ready }, by name (the quest log check lists them, each with Bring back)
function Engine.Noped()
  local out = {}
  for q, how in pairs((ns.char and ns.char.nope) or {}) do out[#out + 1] = { q = q, name = questName(q), ready = how == "ready" } end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end
-- changed your mind: the quest is back on your route (its steps show again; the next replan plans it)
function Engine.Unnope(q)
  if not (q and ns.Nope(q)) then return end
  Engine.BringBack(q)
  if ns.Why then ns.Why("abandon", questName(q) .. ": you brought it back; on your route again") end
  if ns.ZoneCountsChanged then ns.ZoneCountsChanged() end -- (Where to? counts it again)
  Engine.Refresh()
end
-- the quests on the route that come after this one in its chain (and aren't done yet)
function Engine.Dependents(q)
  local out = {}
  for _, d in ipairs((BeelineUnlocks and BeelineUnlocks[q]) or {}) do
    if not ns.State.IsCompleted(d) and not (ns.Nope(d)) then out[#out + 1] = d end
  end
  return out
end
function Engine.NopeNow(qs)
  ns.char.nope = ns.char.nope or {}
  -- "ready": it was already finished when you dropped it (a hand-in you chose to skip) - it stays dropped (FR_STATE below)
  for _, q in ipairs(qs) do ns.char.nope[q] = State.QuestReady(q) and "ready" or true end
  table.insert(ns.char.history, { kind = "nope", ids = {}, nope = qs })
  Engine.GrayForget() -- (a refused quest is no follow-up: Engine.LeadsTo)
  Engine.view = nil
  Engine.Refresh()
  ns.Fire("FR_NOPE", qs) -- (the quest log check says which of their items you still carry)
  ns.Print(questName(qs[1]) .. (#qs > 1 and (" and " .. (#qs - 1) .. " quest" .. (#qs > 2 and "s" or "") .. " after it") or "") .. ": not doing. Dropped from your route and future plans. Undo brings it back.")
end
-- you abandoned these on the quest log check's advice (not on your route, or gray by then): the route stops sending
-- you back to pick them up, and the planner leaves them out. Undo brings them back; so does taking the quest again.
-- (A plain abandon in the game's quest log still sends you back: that's how a failed escort is taken again.)
function Engine.Abandoned(qs, why)
  ns.char.nope = ns.char.nope or {}
  for _, q in ipairs(qs) do ns.char.nope[q] = State.QuestReady(q) and "ready" or true; if ns.Why then ns.Why("abandon", questName(q) .. ": abandoned from the quest log check (" .. (why or "not worth doing") .. "); dropped from the route") end end
  table.insert(ns.char.history, { kind = "nope", ids = {}, nope = qs })
  if #ns.char.history > 50 then table.remove(ns.char.history, 1) end
  Engine.GrayForget()
  Engine.Refresh()
  ns.Fire("FR_NOPE", qs)
end
-- taking a quest you had dropped means you want it after all
ns.On("QUEST_ACCEPTED", function(a, b)
  local q = type(b) == "number" and b or a -- (questID) on this client, (logIndex, questID) on older ones
  if q and ns.char and ns.char.skipQ and ns.char.skipQ[q] then ns.char.skipQ[q] = nil end -- (taken: not skipped any more)
  if q and ns.Nope(q) then
    Engine.BringBack(q)
    if ns.Why then ns.Why("abandon", questName(q) .. ": you took it again; back on your route") end
  end
end)
-- and so does finishing one you said you wouldn't do while it was in your log (no pick-up to notice, and its
-- hand-in stayed off the route)
ns.On("FR_STATE", function()
  if not (ns.char and ns.char.nope and next(ns.char.nope)) then return end
  local back = false
  for q, how in pairs(ns.char.nope) do
    if how == true and State.OnQuest(q) and State.QuestReady(q) then
      Engine.BringBack(q); back = true
      if ns.Why then ns.Why("abandon", questName(q) .. ": you finished it after all; its hand-in is back on your route") end
    end
  end
  if back then Engine.Refresh() end
end)
-- the quest giver has nothing for you (no window opens, so the addon can't see it): this quest leaves your route
-- until your next level, then it's tried again - its chain stays (Availability.lua; the planner reads the same record)
function Engine.NotOffered(q)
  local s = steps()[Engine.Shown() or 0]
  if not q then q = s and s.q end
  if not q or q <= 0 or not ns.Avail then return end
  local mine = s and s.q == q and s or nil
  -- (the giver has nothing for you: their other pick-ups you could take now too - Avail.NothingFrom; undo brings back
  -- what this click left off)
  local npc = (mine and mine.npc) or "the quest giver"
  local qs = ns.Avail.NothingFrom and ns.Avail.NothingFrom(npc, q, mine and mine.name, mine) or { ns.Avail.NotOffered(q, npc, mine and mine.name, mine) and q or nil }
  if ns.char.history and #qs > 0 then
    table.insert(ns.char.history, { kind = "notoffered", ids = {}, avail = qs, npc = npc })
    if #ns.char.history > 50 then table.remove(ns.char.history, 1) end
  end
  Engine.Refresh()
end
function Engine.Nope(q)
  if not q then local s = steps()[Engine.Shown() or 0]; q = s and s.q end
  if not q or q <= 0 then ns.Print("no quest on this step."); return end
  local deps = Engine.Dependents(q)
  if #deps == 0 then Engine.NopeNow({ q }); return end
  local names = {}
  for k, d in ipairs(deps) do if k <= 8 then names[#names + 1] = questName(d) end end
  if #deps > 8 then names[#names + 1] = "... and " .. (#deps - 8) .. " more" end
  local dlg = StaticPopup_Show("BEELINE_NOPE", questName(q), table.concat(names, "\n"))
  if dlg then local all = { q }; for _, d in ipairs(deps) do all[#all + 1] = d end; dlg.data = all end
end
StaticPopupDialogs["BEELINE_NOPE"] = {
  text = "Not doing %s?\n\nIt is part of a chain. These come after it on your route and would be dropped too:\n\n%s",
  button1 = "Drop them all", button2 = "Keep", timeout = 0, whileDead = true, hideOnEscape = true,
  OnAccept = function(self, data) if data then Engine.NopeNow(data) end end,
}

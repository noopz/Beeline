-- What the game really offers you. The quest database comes from several game versions, so it can list a quest
-- Forever doesn't give you. The game knows: the quest givers you talk to list what they offer, and the world map's
-- "!" list shows what's available on a
-- map. Both are recorded per character in BeelineChar.avail:
--   seen[q] = { t, lvl }       the game offered it (a giver listed it, or the map showed it)
--   no[q]   = { t, lvl, npc }  you talked to its giver and it wasn't among the offers, at that level
--   giver[npc] = { t, lvl, none } "the giver has nothing for you" clicked at that level: all of that giver's pick-ups
--                                    are judged not offered (no[q]), and no stop added or taken early sends you back
--                                    to them at that level (Avail.GiverOff)
--   giver[npc] = { t, lvl, hostile }  unfriendly or hostile to you (UnitReaction <= 3, read as you target it, mouse
--                                    over it or its nameplate shows): you can't talk to them, so every quest from or to
--                                    them is off the route until they read friendlier, or their window opens. No
--                                    reputation data needed: the game's own reaction is the gate
-- A quest the game didn't offer is left off your route (and every plan, tools/snapshot.js) until you level up - a
-- level can be the reason - or the game offers it after all. The planner reads the same record.
local _, ns = ...
local Avail = {}
ns.Avail = Avail

local call, plain, Sub = ns.Util.Call, ns.Util.Plain, ns.Util.Sub
local function store()
  local c = BeelineChar
  if not c then return { seen = {}, no = {}, giver = {} } end
  local a = Sub(c, "avail"); Sub(a, "seen"); Sub(a, "no"); Sub(a, "giver")
  return a
end
local function level() return (UnitLevel and UnitLevel("player")) or 0 end

-- fromMap: the world map's "!" list, which says the quest is offered somewhere on the map, not by whom. After the
-- giver the plan sends you to turned it down at this level, that is no reason to send you back to the same giver
-- (the two would take turns, the step going off and on your route without end). A giver offering it, or a level up,
-- still brings it back.
function Avail.Seen(q, fromMap)
  if not q then return end
  local A = store()
  A.seen[q] = { t = time(), lvl = level() }
  local no = A.no[q]
  if not no then return end
  -- (nor once turned down at two levels, its quests before it done - no.stay: a level isn't the reason, and the map
  -- doesn't say this giver has it. Only the giver listing it, or you undoing it, brings it back)
  if fromMap and (no.lvl == level() or no.stay) then
    if not no.mapSaid then
      no.mapSaid = true
      if ns.Why then ns.Why("avail", "quest " .. q .. ": " .. tostring(no.npc) .. " didn't offer it, though the map shows it on offer here - someone else may give it") end
    end
    return
  end
  A.no[q] = nil
  if ns.Why then ns.Why("avail", "quest " .. q .. " is offered after all: back on your route") end
  return true -- (changed: back on the route)
end
-- the game did not offer this quest at its giver (q: quest id, npc: who you talked to, step: the route's pick-up, if
-- known). The first time, a level up brings it back. Turned down again at a higher level, with every quest before it
-- done, a level clearly isn't the reason: it stays off until the game offers it (a giver lists it, or the map's "!"
-- shows it). (Not after one refusal, even at the level the data says it needs: Forever asks a higher level for some.)
function Avail.NotOffered(q, npc, name, step)
  local A = store()
  local old, lvl = A.no[q], level()
  if old and old.lvl == lvl then return false end
  local waits = {}
  for _, p in ipairs((ns.Engine and ns.Engine.PrereqsOf and ns.Engine.PrereqsOf(q)) or {}) do
    if not (ns.State and ns.State.IsCompleted(p)) then waits[#waits + 1] = p end
  end
  local req = step and step.minLevel
  local tries = ((old and (old.tries or 1)) or 0) + 1
  local stay = (#waits == 0 and tries >= 2) or nil
  A.no[q] = { t = time(), lvl = lvl, npc = npc, tries = tries, stay = stay, req = req, waits = #waits > 0 and waits or nil }
  local what = stay and "left off your route until the game offers it" or "left off your route until you level up"
  if ns.Why then ns.Why("avail", (name or ("quest " .. q)) .. ": " .. tostring(npc) .. " doesn't offer it to you - " .. what) end
  ns.Print((name or ("Quest " .. q)) .. ": " .. tostring(npc) .. " doesn't offer it to you, so it's off your route" .. (stay and "." or " for now."))
  return true
end
-- what this quest needs that you don't have: "needs Engineering 200", or nil (ns.QUEST_NEEDS in QuestData.lua; older
-- plans don't check it). Your skills are read at most every 10 s.
local skillsAt, skills = -100, {}
local told = {}
function Avail.ForgetSkills() skillsAt = -100 end -- (read again on the next ask: tests; a profession just learned)
function Avail.Needs(q)
  local need = q and ns.QUEST_NEEDS and ns.QUEST_NEEDS[q]
  if not need then return nil end
  local why
  if need.s then
    local now = (GetTime and GetTime()) or 0
    if now - skillsAt >= 10 then skillsAt, skills = now, (ns.State and ns.State.Skills and ns.State.Skills()) or {} end
    local have = skills[need.s]
    if not have or (tonumber(have[1]) or 0) < (need.r or 1) then why = "needs " .. need.s .. " " .. (need.r or 1) end
  end
  if not why and need.sp then
    local known = (IsPlayerSpell and call(IsPlayerSpell, need.sp)) or (IsSpellKnown and call(IsSpellKnown, need.sp))
    if known == false then why = "needs a spell you haven't learned" end
  end
  -- a reputation: { faction, at least this much } (the game's bar value; a client that won't say keeps the step)
  if not why and need.rp and GetFactionInfoByID then
    local name, _, _, _, _, value = call(GetFactionInfoByID, need.rp[1])
    if name and plain(value) and type(value) == "number" and value < need.rp[2] then why = "needs more reputation with " .. name end
  end
  if why and not told[q] and ns.Why then
    told[q] = true
    ns.Why("avail", "quest " .. q .. " " .. why .. ": left off your route")
  end
  return why
end

-- a battleground quest (ns.PVP_QUESTS, PvpQuests.lua from the quest data): its work is a PvP match - Marks of Honor
-- from a battleground, or the match itself - so no route does it: the battleground's name, or nil (older plans carry
-- them). One already in your log is yours: the card does its hand-in once it is finished
function Avail.Pvp(q) local P = ns.PVP_QUESTS; return P and q and P[q] or nil end

-- left off the route: the game didn't offer it (and hasn't since), and nothing that could change that has happened -
-- a level, where a level could be the reason, or a quest before it handed in, or it needs a profession you don't have.
-- A quest you have or did is never this.
function Avail.Unavailable(q)
  if Avail.Pvp(q) then return true end -- (a battleground quest: never offered to a leveling route)
  local need = Avail.Needs(q)
  local n = q and BeelineChar and BeelineChar.avail and BeelineChar.avail.no and BeelineChar.avail.no[q]
  if not (need or n) then return false end
  -- (in your log or done: it was offered - whatever the data says it needs, or a "not offered" from before:
  -- Preserving Eldarath taken a moment after its giver's window was read; a reputation or skill the data asks that
  -- Forever doesn't. Asked only for a quest that would be left off, so it costs nothing else)
  if ns.State and (ns.State.OnQuest(q) or ns.State.IsCompleted(q)) then return false end
  if need then return true end
  if n.stay then return true end
  for _, p in ipairs(n.waits or {}) do if ns.State and ns.State.IsCompleted(p) then return false end end
  if n.waits and n.req and (n.lvl or 0) >= n.req then return true end -- it waits on that quest, not on a level
  return level() <= (n.lvl or 0)
end

-- a giver the card must not send you to: one unfriendly or hostile to you (no talking), or one you said has nothing for
-- you at this level. Opportunistic stops - a side quest added, a stop taken before the plan's step - leave them out;
-- their own steps are off the route through no[q] (none) or Avail.Hostile (statusRaw). A table look: asked per stop
function Avail.GiverOff(npc)
  local G = npc and BeelineChar and BeelineChar.avail and BeelineChar.avail.giver
  local g = G and G[npc]
  if not g then return false end
  return g.hostile or (g.none and level() <= (g.lvl or 0)) or false
end
-- unfriendly or hostile to you, as the game last said (UnitReaction <= 3): every quest from or to them is off the route
function Avail.Hostile(npc)
  local G = npc and BeelineChar and BeelineChar.avail and BeelineChar.avail.giver
  local g = G and G[npc]
  return g ~= nil and g.hostile == true
end
-- the npc names of the route's pick-ups and hand-ins (kept per list generation: a nameplate asks for every mob in view)
local npcsMemo = setmetatable({}, { __mode = "k" })
local function routeNpcs()
  local list = BeelineData and BeelineData.steps
  if not list then return {} end
  local c = npcsMemo[list]
  if c and c.gen == (list._gen or 0) then return c.set end
  c = { gen = list._gen or 0, set = {} }
  for _, s in ipairs(list) do if s.npc and (s.k == "accept" or s.k == "turnin") then c.set[s.npc] = true end end
  npcsMemo[list] = c
  return c.set
end
-- the game's reaction of a unit you target, mouse over or see the nameplate of: a route giver unfriendly or hostile to
-- you (UnitReaction(unit, "player") <= 3) can't be talked to - its quests leave the route at once, with a why line;
-- read friendly again (your reputation went up), they come back. Cheap: a name look-up first, the reaction only for a
-- route giver, and nothing changes unless the reading does
function Avail.ReadUnit(unit)
  if not (unit and UnitReaction and UnitName) then return end
  local name = call(UnitName, unit)
  if not (plain(name) and type(name) == "string" and routeNpcs()[name]) then return end
  if UnitIsPlayer and call(UnitIsPlayer, unit) then return end
  local r = call(UnitReaction, unit, "player")
  if not (plain(r) and type(r) == "number") then return end
  local A = store()
  local g = A.giver[name]
  if r <= 3 then
    if g and g.hostile then return end
    A.giver[name] = { t = time(), lvl = level(), hostile = true }
    if ns.Why then ns.Why("avail", name .. " is " .. (r <= 2 and "hostile" or "unfriendly") .. " to you and won't talk to you: its quests are off your route until that changes") end
    ns.Print(name .. " won't talk to you (" .. (r <= 2 and "hostile" or "unfriendly") .. "): its quests are off your route for now.")
    if ns.Engine then ns.Engine.Refresh() end
  elseif g and g.hostile then
    A.giver[name] = nil
    if ns.Why then ns.Why("avail", name .. " is no longer unfriendly to you: its quests are back on your route") end
    if ns.Engine then ns.Engine.StateChanged(); ns.Engine.Refresh() end
  end
end
ns.On("PLAYER_TARGET_CHANGED", ns.Guard("avail", function() Avail.ReadUnit("target") end))
ns.On("UPDATE_MOUSEOVER_UNIT", ns.Guard("avail", function() Avail.ReadUnit("mouseover") end))
ns.On("NAME_PLATE_UNIT_ADDED", ns.Guard("avail", function(unit) Avail.ReadUnit(unit) end))

-- the quests a giver you're talking to offers: ids, or nil when the game didn't say
local function offeredHere(event)
  local ids = {}
  if event == "GOSSIP_SHOW" and C_GossipInfo and C_GossipInfo.GetAvailableQuests then
    local list = call(C_GossipInfo.GetAvailableQuests)
    if type(list) ~= "table" then return nil end
    for _, x in ipairs(list) do if type(x) == "table" and plain(x.questID) and x.questID then ids[#ids + 1] = x.questID end end
    return ids
  elseif event == "QUEST_GREETING" and GetNumAvailableQuests and GetAvailableQuestInfo then
    local n = call(GetNumAvailableQuests)
    if type(n) ~= "number" then return nil end
    for i = 1, n do local _, _, _, _, id = call(GetAvailableQuestInfo, i); if plain(id) and id then ids[#ids + 1] = id end end
    return ids
  elseif event == "QUEST_DETAIL" and GetQuestID then
    local id = call(GetQuestID)
    if plain(id) and id and id > 0 then ids[1] = id end
    return ids, true -- one quest straight to its page: says nothing about the others
  end
end
-- the route's pick-ups from this giver that you could take now (not had, not done, level reached)
local function expectedFrom(npc)
  local out = {}
  local list = BeelineData and BeelineData.steps
  if not (list and npc) then return out end
  for _, s in ipairs(list) do
    if s.k == "accept" and s.q and s.npc == npc and not (s.minLevel and level() < s.minLevel)
      and not ns.State.OnQuest(s.q) and not ns.State.IsCompleted(s.q) then out[s.q] = s end
  end
  return out
end
-- what the giver offers, read at the event itself (before auto-quest picks one: the window then lists the others no
-- more); nil when the game didn't say
function Avail.Read(event)
  local ids, partial = offeredHere(event)
  if not ids then return nil end
  local npc = call(UnitName, "npc")
  return { ids = ids, partial = partial, npc = plain(npc) and type(npc) == "string" and npc or nil }
end
-- quests you took in the last few seconds: offered, whatever the log says yet. Taking one at a giver with several
-- reopens its window without it, before the log is read again (State: 0.5 s after) - Commander Truesong "didn't
-- offer" Preserving Eldarath, taken the moment before, and it was left off the route with its steps
local justTaken = {}
Avail.TAKEN_FOR = 10
local function takenRecently(q)
  local t = justTaken[q]
  return t and ((GetTime and GetTime()) or 0) - t < Avail.TAKEN_FOR
end
function Avail.Taken(q)
  if not q then return end
  justTaken[q] = (GetTime and GetTime()) or 0
  if Avail.Seen(q) and ns.Engine then ns.Engine.Refresh() end -- (taken: offered - a "not offered" goes)
end
ns.On("QUEST_ACCEPTED", function(a, b) Avail.Taken(type(b) == "number" and b or a) end) -- ((questID), or (logIndex, questID) on older clients)
-- a quest the giver can't offer yet for a reason we know: a quest before it not handed in (the window you open to hand
-- that one in lists none of what follows - Commander Truesong's four after Slay the Spitelash's hand-in, all four
-- "not offered" and then "offered after all"), or a reputation you don't have. Not judged: no "not offered" for it
-- the breadcrumbs that lead to each quest (ns.BREADCRUMBS turned around: breadcrumb -> its targets), built once per
-- table
local crumbsOf, crumbsFrom = {}, nil
local function crumbsTo(q)
  local B = ns.BREADCRUMBS
  if crumbsFrom ~= B then
    crumbsOf, crumbsFrom = {}, B
    for b, ts in pairs(B or {}) do
      for _, t in ipairs(ts) do local l = crumbsOf[t]; if not l then l = {}; crumbsOf[t] = l end; l[#l + 1] = b end
    end
  end
  return crumbsOf[q]
end
-- a breadcrumb leading to q is in your log (taken, not handed in): its giver doesn't list q until you hand that in
function Avail.CrumbInLog(q)
  local l = q and crumbsTo(q)
  if not (l and ns.State and ns.State.OnQuest) then return false end
  for _, b in ipairs(l) do if ns.State.OnQuest(b) and not ns.State.IsCompleted(b) then return true end end
  return false
end
-- (or its breadcrumb is in your log: the giver lists the quest it leads to only once that one is handed in - Enraged
-- Wildkin at Jaron Stoneshaper, Threat of the Winterfall at Donova Snowden, "not offered" and "offered after all" a
-- moment later, the step off the route and a chat line meanwhile)
function Avail.Waits(q)
  for _, p in ipairs((ns.Engine and ns.Engine.PrereqsOf and ns.Engine.PrereqsOf(q)) or {}) do
    if not (ns.State and ns.State.IsCompleted(p)) then return true end
  end
  if Avail.CrumbInLog(q) then return true end
  return Avail.Needs(q) ~= nil
end
-- the route is refreshed only when the offers changed what is on it
function Avail.Judge(r)
  if not r then return end
  local offered, changed = {}, false
  for _, id in ipairs(r.ids) do offered[id] = true; if Avail.Seen(id) then changed = true end end
  -- (their window opened: they talk to you - not hostile; and offering something, they don't have "nothing for you")
  local G = r.npc and BeelineChar and BeelineChar.avail and BeelineChar.avail.giver
  local g = G and G[r.npc]
  if g and (g.hostile or (g.none and #r.ids > 0)) then
    G[r.npc] = nil; changed = true
    if g.hostile and ns.Engine then ns.Engine.StateChanged() end
  end
  if not r.partial and r.npc then
    for q, s in pairs(expectedFrom(r.npc)) do
      if not offered[q] and not takenRecently(q) and not Avail.Waits(q) and Avail.NotOffered(q, r.npc, s.name, s) then changed = true end
    end
  end
  if changed and ns.Engine then ns.Engine.Refresh() end
end
function Avail.OnGiver(event) Avail.Judge(Avail.Read(event)) end
for _, ev in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL" }) do
  ns.On(ev, ns.Guard("avail", function()
    local r = Avail.Read(ev)
    if r then C_Timer.After(0.2, ns.Guard("avail", function() Avail.Judge(r) end)) end
  end), true)
end

-- you said the giver has nothing for you (the card's button on its pick-up q): none of the route's pick-ups from that
-- giver you could take now is offered either - one click, not one per quest walking you back to the same NPC (an
-- Azshara tester clicked it three times at the Legashi Cauldron, twice at Korsa, twice at Elder Bramblesnap). Each is
-- off until you level up, as one refusal is (Avail.NotOffered). -> the quests judged
function Avail.NothingFrom(npc, q, name, step)
  local judged = {}
  if Avail.NotOffered(q, npc, name, step) ~= false then judged[1] = q end
  if not npc or npc == "the quest giver" then return judged end
  local A = store()
  A.giver[npc] = { t = time(), lvl = level(), none = true, hostile = A.giver[npc] and A.giver[npc].hostile or nil }
  for oq, s in pairs(expectedFrom(npc)) do
    if oq ~= q and not takenRecently(oq) and not Avail.Waits(oq) and Avail.NotOffered(oq, npc, s.name, s) then judged[#judged + 1] = oq end
  end
  return judged
end
-- undone (the card's undo after "the giver has nothing for you"): those quests and that giver as before
function Avail.Unjudge(qs, npc)
  local A = store()
  for _, q in ipairs(qs or {}) do A.no[q] = nil end
  if npc and A.giver[npc] and A.giver[npc].none then A.giver[npc] = nil end
end
-- the world map's available quests on the map you're on (the "!" icons): what the game says you can pick up there
function Avail.ScanMap(m)
  if not (m and C_QuestLine and C_QuestLine.GetAvailableQuestLines) then return 0 end
  if C_QuestLine.RequestQuestLinesForMap then call(C_QuestLine.RequestQuestLinesForMap, m) end
  local list = call(C_QuestLine.GetAvailableQuestLines, m)
  local n = 0
  for _, x in ipairs(type(list) == "table" and list or {}) do
    if type(x) == "table" and plain(x.questID) and x.questID then Avail.Seen(x.questID, true); n = n + 1 end
  end
  return n
end
local function scanHere() local m = ns.State and ns.State.Position and ns.State.Position(); if m then Avail.ScanMap(m) end end
ns.On("ZONE_CHANGED_NEW_AREA", function() C_Timer.After(3, ns.Guard("avail", scanHere)) end)
ns.On("QUESTLINE_UPDATE", function() C_Timer.After(0.5, ns.Guard("avail", scanHere)) end)
ns.On("FR_LOADED", function() C_Timer.After(8, ns.Guard("avail", scanHere)); ns.NewTicker(120, ns.Guard("avail", scanHere)) end)

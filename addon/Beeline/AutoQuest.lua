-- Quest automation, on a toggle (ns.db.autoQuest, off by default; Options: "Accept and hand in quests automatically"):
--   accept   a quest a quest-giver offers that your route picks up (not one you marked "won't do"): never random ones
--   hand in  a quest in your log that's finished, and take the reward when there is no choice to make (a choice of
--            rewards always waits for you)
--   gossip   at an NPC with several quests, the finished one first, then one your route picks up
-- Hold Shift while talking to an NPC to do it yourself that time. Quests not in your log (repeatable turn-ins like
-- runecloth) are never handed in for you.
local _, ns = ...
local Auto = {}
ns.AutoQuest = Auto

function Auto.Enabled() return ns.db and ns.db.autoQuest == true and not (IsShiftKeyDown and IsShiftKeyDown()) end

-- the quests your route picks up: an accept step for it, on any of your routes; cached per plan. Escort quests too
-- (the plan's pick-up says "Escort: <NPC> leaves with whoever takes this", or an objective "Escort <NPC>"): those are
-- never accepted for you - the escort starts at once and fails if you aren't ready
local wantCache, wantFor, escortCache
local function build()
  local routes = {}
  -- (not the dungeon routes: unpacking them here would keep them unpacked and slow every later look over your routes'
  -- steps - the one you picked is BeelineData, below)
  for _, r in ipairs(ns.Routes and ns.Routes() or {}) do if not (r.dungeon and not r.special) then routes[#routes + 1] = r end end
  if BeelineData then routes[#routes + 1] = BeelineData end -- (the plan you are on)
  if wantFor ~= routes[1] or not wantCache then
    wantCache, escortCache, wantFor = {}, {}, routes[1]
    for _, r in ipairs(routes) do
      for _, s in ipairs((ns.Steps and ns.Steps(r)) or r.steps or {}) do
        if s.q then
          if s.k == "accept" then wantCache[s.q] = tonumber(s.level) or true end
          if (s.k == "accept" and type(s.note) == "string" and s.note:find("Escort:", 1, true))
            or (s.k == "obj" and type(s.text) == "string" and s.text:find("^Escort ")) then escortCache[s.q] = true end
        end
      end
    end
  end
end
function Auto.Wanted(q)
  q = tonumber(q)
  if not q or (ns.Nope(q)) then return false end
  build()
  local w = wantCache[q]
  if not w then return false end
  -- (never a gray quest, whatever route has it)
  if type(w) == "number" and w > 0 and ns.Engine and ns.Engine.GrayAt and w <= ns.Engine.GrayAt((UnitLevel and UnitLevel("player")) or 1) then return false end
  return true
end
-- an escort quest: by the plan's own marks, or the quest's objective text as the game shows it ("Escort ...")
function Auto.IsEscort(q)
  q = tonumber(q)
  if q then build(); if escortCache[q] then return true end end
  local obj = GetObjectiveText and GetObjectiveText()
  return type(obj) == "string" and obj:lower():find("escort", 1, true) ~= nil
end
ns.On("FR_ROUTE_CHANGED", function() wantCache = nil end)

local function inLog(q)
  if not q then return false end
  local idx = C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(q)
  return idx ~= nil and idx > 0
end
local function did(what, q, name)
  if ns.Why then ns.Why("auto", what .. " " .. tostring(name or q) .. (q and (" (" .. q .. ")") or "")) end
end

-- a quest's details (offered): accept it if the route picks it up
function Auto.Detail()
  if not Auto.Enabled() then return false end
  local q = GetQuestID and GetQuestID()
  if QuestGetAutoAccept and QuestGetAutoAccept() then return false end -- the game accepts those itself
  if q and q > 0 and Auto.Wanted(q) and not inLog(q) then
    -- (an escort: yours to start when you're ready - the quest window stays open)
    if Auto.IsEscort(q) then did("left for you (escort)", q, GetTitleText and GetTitleText()); return false end
    AcceptQuest(); did("accepted", q, GetTitleText and GetTitleText()); return true
  end
  return false
end
-- "do you have the items?": go on when it's finished and in your log
function Auto.Progress()
  if not Auto.Enabled() then return false end
  local q = GetQuestID and GetQuestID()
  if q and inLog(q) and IsQuestCompletable and IsQuestCompletable() then CompleteQuest(); return true end
  return false
end
-- the reward: take it when there's nothing to choose (only for a quest in your log)
function Auto.Complete()
  if not Auto.Enabled() then return false end
  local q = GetQuestID and GetQuestID()
  if not inLog(q) then return false end
  local n = GetNumQuestChoices and GetNumQuestChoices() or 0
  if n > 1 then return false end
  GetQuestReward(n == 1 and 1 or 0); did("handed in", q, GetTitleText and GetTitleText())
  return true
end
-- an NPC with several quests (gossip window): a finished one first, then one the route picks up
function Auto.Gossip()
  if not Auto.Enabled() or not C_GossipInfo then return false end
  for _, a in ipairs(C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests() or {}) do
    if a.isComplete and a.questID then C_GossipInfo.SelectActiveQuest(a.questID); return true end
  end
  for _, a in ipairs(C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetAvailableQuests() or {}) do
    if a.questID and Auto.Wanted(a.questID) then C_GossipInfo.SelectAvailableQuest(a.questID); return true end
  end
  return false
end
-- the older quest-greeting window (an NPC with only quests to offer)
function Auto.Greeting()
  if not Auto.Enabled() then return false end
  for i = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
    local _, complete = GetActiveTitle(i)
    if complete then SelectActiveQuest(i); return true end
  end
  for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
    local q = select(5, GetAvailableQuestInfo(i))
    if q and Auto.Wanted(q) then SelectAvailableQuest(i); return true end
  end
  return false
end

ns.On("QUEST_DETAIL", ns.Guard("auto", Auto.Detail))
ns.On("QUEST_PROGRESS", ns.Guard("auto", Auto.Progress))
ns.On("QUEST_COMPLETE", ns.Guard("auto", Auto.Complete))
ns.On("QUEST_GREETING", ns.Guard("auto", Auto.Greeting))

-- Auto-fly, on its own toggle (ns.db.autoFly, off by default; Options: "Take the flight my route needs"): open a flight
-- master's map while the card's trip flies from here, and it takes that flight. Only a flight path you have (the map
-- lists it as reachable), only the trip of the step the card shows, and Shift held opens the map for you to choose.
-- (the card's step's own trip, Engine.TravelFor - kept, so no search. Not Engine.lastTrip: that is the last trip
-- worked out for any step, which the solve or the "?" may have set for another)
function Auto.FlightFor()
  local E = ns.Engine
  local shown = E and E.Shown and E.Shown()
  local list = BeelineData and BeelineData.steps
  local step = shown and list and list[shown]
  if not step then return nil end
  local trip = E.TravelFor and E.TravelFor(step)
  local legs = trip and (trip.legs or { trip })
  if not legs and E.lastTripStep == step then legs = E.lastTrip end
  if not legs then return nil end
  for _, leg in ipairs(legs) do
    if leg.how == "fly" then return leg.toTaxi end
    if leg.how ~= "ride" then return nil end -- (a boat or a hearth first: this flight is not the one from here)
  end
end
-- the flight map's node for a flight path's name: as the map names it, else by its town (the part before the comma) -
-- our names come from the flight data, the map's from the game, and they can differ by a word
local function townOf(n) return (n or ""):match("^%s*([^,]+)") end
function Auto.TaxiSlot(want)
  if not (want and NumTaxiNodes and TaxiNodeName) then return nil end
  local byTown
  for i = 1, NumTaxiNodes() do
    local name, typ = TaxiNodeName(i), TaxiNodeGetType and TaxiNodeGetType(i) or "REACHABLE"
    if typ == "REACHABLE" then
      if name == want then return i end
      if not byTown and townOf(name) == townOf(want) then byTown = i end
    end
  end
  return byTown
end
local function wantsFlight() return ns.db and ns.db.autoFly == true and not (IsShiftKeyDown and IsShiftKeyDown()) end
ns.On("TAXIMAP_OPENED", function()
  if not wantsFlight() then return end
  C_Timer.After(0.1, ns.Guard("autofly", function()
    local want = Auto.FlightFor()
    local i = want and TakeTaxiNode and Auto.TaxiSlot(want)
    if not i then return end
    -- the game works out a flight's hops when the map is asked for its routes (the stock map does it when you hover a
    -- town): TakeTaxiNode without it says there's no path for a flight of more than one hop (Rut'theran Village to
    -- Talrendis Point). No route the game knows: the map stays open for you
    if GetNumRoutes and (GetNumRoutes(i) or 0) < 1 then
      if ns.Why then ns.Why("auto", "no flight route to " .. want .. " the game knows from here: the map is left to you") end
      return
    end
    if ns.Why then ns.Why("auto", "flying to " .. want .. " (auto-fly)") end
    ns.Print("Flying to " .. (townOf(want) or want) .. ". (Auto-fly: hold Shift when you talk to the flight master to choose yourself.)")
    TakeTaxiNode(i)
  end))
end)
-- A flight master with quests or more to say opens a chat first: the flight map waits for "Show me where I can fly".
-- With auto-fly on and the card's trip flying from here, that
-- option is chosen for you - after auto-quest's hand-ins and pick-ups at the same NPC, which come first. The option is
-- known by its icon (the game's taxi gossip icon; the type field the older API had). Shift: choose yourself.
Auto.TAXI_ICON = 132057
function Auto.TaxiGossip()
  if not (wantsFlight() and C_GossipInfo and C_GossipInfo.GetOptions and Auto.FlightFor()) then return false end
  for _, o in ipairs(C_GossipInfo.GetOptions() or {}) do
    if (o.icon == Auto.TAXI_ICON or o.type == "taxi") and o.gossipOptionID then C_GossipInfo.SelectOption(o.gossipOptionID); return true end
  end
  return false
end
-- a gossip window: auto-quest's hand-in or pick-up first; only when it took none, the flight option (the gossip it
-- acted on closes or changes, and the flight waits for the next look)
local gossipQuest = ns.Guard("auto", function() return Auto.Gossip() end)
local gossipTaxi = ns.Guard("autofly", function() return Auto.TaxiGossip() end)
ns.On("GOSSIP_SHOW", function() if not gossipQuest() then gossipTaxi() end end)

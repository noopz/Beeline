-- Quest items: the items your quests ask for, and where yours are - in your bags, in your bank, worn. The game shows
-- the bank only while it is open, so what quests need from it is remembered per character when you open it (and as
-- it changes while open): ns.char.bank = { t = when, items = { [item] = count } }, only quest items, never a copy of
-- the whole bank. /bee report's quest-items section (UI/Report.lua) reads it: a step that needs an item sitting in
-- your bank (the Chained Essence of Eranikus, for The Essence of Eranikus's second part) says so in the report.
-- Events only, nothing per frame. Only the game's own API and the quest data: never another addon's saved data.
local _, ns = ...
local QI = {}
ns.QuestItems = QI

local plain, call = ns.Util.Plain, ns.Util.PlainCall
local CC = function() return C_Container or {} end

---------------------------------------------------------------------------------------------------------------
-- which items quests ask for
-- item -> { quests }, quest -> { items }: QuestData's quest items (objectives, handed to you, needed along the way,
-- starting it), the ones a quest gives you for another (QUEST_ITEMS_HANDED), and the items that start a quest
-- (ITEM_QUESTS). Built once, on the first look.
local byItem, byQuest, startsQ, nameOf
local function index()
  if byItem then return end
  byItem, byQuest, startsQ, nameOf = {}, {}, {}, {}
  local seen = {}
  local function add(item, q)
    if not (item and q) or seen[item .. ":" .. q] then return end
    seen[item .. ":" .. q] = true
    local qs = byItem[item]; if not qs then qs = {}; byItem[item] = qs end; qs[#qs + 1] = q
    local its = byQuest[q]; if not its then its = {}; byQuest[q] = its end; its[#its + 1] = item
  end
  for _, t in ipairs({ ns.QUEST_ITEMS or {}, ns.QUEST_ITEMS_HANDED or {} }) do
    for item, e in pairs(t) do
      nameOf[item] = e[1]
      for k = 2, #e do add(item, e[k]) end
    end
  end
  for q, d in pairs(ns.ITEM_QUESTS or {}) do
    for item, name in pairs(d.it or {}) do add(item, q); startsQ[item] = q; nameOf[item] = nameOf[item] or name end
  end
end
-- the items quest q asks for (its objectives, the item that starts it): a list, maybe empty
function QI.ForQuest(q) index(); return (q and byQuest[q]) or {} end
-- the quest an item starts (nil: none the quest data knows)
function QI.Starts(item) index(); return item and startsQ[item] end
function QI.Name(item) index(); return item and nameOf[item] end

-- the items the steps of a route name (step.item: a loot, a use, the item that starts a pick-up). A packed route (a
-- branch, a trip) is read as its text, not unpacked; kept per route (the plan's routes don't change while you play)
local packedItems = setmetatable({}, { __mode = "k" })
local function stepItems(r, into)
  if r.steps then
    for _, s in ipairs(r.steps) do if s.item then into[s.item] = true end end
    return
  end
  local got = packedItems[r]
  if not got then
    got = {}
    if type(r.packed) == "string" then
      for key, id in r.packed:gmatch("([%w_]+)%s*=%s*(%d+)") do if key == "item" then got[#got + 1] = tonumber(id) end end
    end
    packedItems[r] = got
  end
  for _, id in ipairs(got) do into[id] = true end
end
-- every item a quest, a step on the route you are on or one on a side trip asks for: { [item] = true }. (Not every
-- zone route's: their text is most of the plan, and their items are the quest data's, above. The base is kept; the
-- route you are on is looked at each time - a few thousand steps, on a bank event.)
local wantedBase
function QI.Wanted()
  index()
  if not wantedBase or wantedBase.src ~= (ns.Routes and ns.Routes()) then
    local base = {}
    for item in pairs(byItem) do base[item] = true end
    for _, r in ipairs(ns.Routes and ns.Routes() or {}) do if r.dungeon or r.special then stepItems(r, base) end end
    wantedBase = { src = ns.Routes and ns.Routes(), items = base }
  end
  local out = setmetatable({}, { __index = wantedBase.items })
  if BeelineData and BeelineData.steps then for _, s in ipairs(BeelineData.steps) do if s.item then out[s.item] = true end end end
  return out
end

---------------------------------------------------------------------------------------------------------------
-- where they are
local function bagList()
  local out = {}
  for b = 0, (NUM_BAG_SLOTS or 4) do out[#out + 1] = b end
  return out
end
local function bankList()
  local out = { BANK_CONTAINER or -1 }
  local first = (NUM_BAG_SLOTS or 4) + 1
  for b = first, first + (NUM_BANKBAGSLOTS or 6) - 1 do out[#out + 1] = b end
  return out
end
QI.BankBags = bankList
-- every slot with an item in these containers: fn(item, count, bag, slot)
local function eachSlot(bags, fn)
  local numSlots = CC().GetContainerNumSlots or GetContainerNumSlots
  local itemID = CC().GetContainerItemID or GetContainerItemID
  if type(numSlots) ~= "function" then return end
  for _, bag in ipairs(bags) do
    for slot = 1, call(numSlots, bag) or 0 do
      local item = call(itemID, bag, slot)
      local n
      -- (a table on newer clients - { itemID, stackCount, ... } - values on older ones: texture, count, ..., the 10th the id)
      if CC().GetContainerItemInfo then
        local t = call(CC().GetContainerItemInfo, bag, slot)
        if type(t) == "table" then item = item or plain(t.itemID); n = plain(t.stackCount) end
      elseif GetContainerItemInfo then
        local _, c, _, _, _, _, _, _, _, id = call(GetContainerItemInfo, bag, slot)
        n = c; item = item or id
      end
      if item then fn(item, tonumber(n) or 1, bag, slot) end
    end
  end
end

-- what your bags hold: { [item] = count }, and the items in them that start a quest { { item, q } } (the game's word
-- per slot, else the quest data's)
function QI.Bags()
  index()
  local counts, starts, had = {}, {}, {}
  local questInfo = CC().GetContainerItemQuestInfo or GetContainerItemQuestInfo
  eachSlot(bagList(), function(item, n, bag, slot)
    counts[item] = (counts[item] or 0) + n
    if had[item] then return end
    local q
    if type(questInfo) == "function" then
      local a, b = call(questInfo, bag, slot)
      if type(a) == "table" then q = plain(a.questID) else q = b end
      q = tonumber(q); if q and q <= 0 then q = nil end
    end
    q = q or startsQ[item]
    if q then had[item] = true; starts[#starts + 1] = { item = item, q = q } end
  end)
  return counts, starts
end
-- what you wear: { [item] = count }
function QI.Worn()
  local out = {}
  if type(GetInventoryItemID) ~= "function" then return out end
  for slot = 0, 19 do
    local item = call(GetInventoryItemID, "player", slot)
    if item then out[item] = (out[item] or 0) + 1 end
  end
  return out
end

-- the bank, read while it is open: the quest items in it are remembered (ns.char.bank)
function QI.ReadBank()
  if not ns.char then return end
  local wanted, items = QI.Wanted(), {}
  eachSlot(bankList(), function(item, n) if wanted[item] then items[item] = (items[item] or 0) + n end end)
  ns.char.bank = { t = time(), items = items }
  return ns.char.bank
end
-- the remembered bank: count of item (0: not there, or the bank never seen), and when it was seen (nil: never)
function QI.InBank(item)
  local b = ns.char and ns.char.bank
  if type(b) ~= "table" or type(b.items) ~= "table" then return 0, nil end
  return b.items[item] or 0, b.t
end
-- "it's in your bank" when the item isn't in your bags but the remembered bank has it, else nil (the game's own count
-- of what you carry, no bag scan; called only when a card or list line is written)
function QI.BankNote(item)
  item = tonumber(item)
  if not item then return nil end
  if ((GetItemCount and GetItemCount(item)) or 0) > 0 then return nil end
  if QI.InBank(item) > 0 then return "it's in your bank" end
end

QI.bankOpen = false
local pending = false
local function readSoon()
  if pending then return end
  pending = true
  -- (one read for a burst of slot changes: a stack moved fires several)
  C_Timer.After(0.2, ns.Guard("bank", function() pending = false; if QI.bankOpen then QI.ReadBank() end end))
end
ns.On("BANKFRAME_OPENED", ns.Guard("bank", function() QI.bankOpen = true; QI.ReadBank() end))
ns.On("BANKFRAME_CLOSED", function() QI.bankOpen = false end)
ns.On("PLAYERBANKSLOTS_CHANGED", function() if QI.bankOpen then readSoon() end end)
ns.On("BAG_UPDATE", function(bag)
  bag = tonumber(bag)
  if QI.bankOpen and bag and (bag == (BANK_CONTAINER or -1) or bag > (NUM_BAG_SLOTS or 4)) then readSoon() end
end)

---------------------------------------------------------------------------------------------------------------
-- for /bee report: the quest items around the shown step
-- quest q's chain: the quests before it (its chain's earlier parts, its prerequisites and theirs) and after it (the
-- chain's later parts) -> { { q, role } }, role 1 before, 2 the quest, 3 after; at most max
function QI.Chain(q, max)
  max = max or 10
  local out, seen = {}, {}
  local function put(x, role) if x and not seen[x] and #out < max then seen[x] = true; out[#out + 1] = { q = x, role = role } end end
  put(q, 2)
  local frontier = { q }
  for _ = 1, 3 do
    local nextF = {}
    for _, x in ipairs(frontier) do
      local pre = ns.QUEST_PRE and ns.QUEST_PRE[x]
      for _, list in ipairs({ pre and pre.g or {}, pre and pre.s or {} }) do
        for _, p in ipairs(list) do if not seen[p] then put(p, 1); nextF[#nextF + 1] = p end end
      end
    end
    frontier = nextF
  end
  local ch = ns.ChainOf and ns.ChainOf(q)
  if ch then for n, x in ipairs(ch.q) do put(x, n < ch.at and 1 or 3) end end
  return out
end
-- a quest's state: 0 not taken, 1 in your log, 2 in your log and finished, 3 done
function QI.QuestState(q)
  local St = ns.State
  if not St then return 0 end
  if St.IsCompleted(q) then return 3 end
  if St.OnQuest(q) then local c = St.Quest(q); return (c and c.complete) and 2 or 1 end
  return 0
end

QI.STEPS_AHEAD = 5
QI.MAX_NEED = 12
-- the report's quest items: { bankT, starts = { { item, q } } (starting items in your bags), need = { { item, bags,
-- bank, worn, why } } (why 1: a step from the shown one to STEPS_AHEAD after it, 2: the shown quest's chain), chain =
-- { { q, role, st } } }
function QI.Gather(cur)
  index()
  local bags, starts = QI.Bags()
  local worn = QI.Worn()
  local b = ns.char and ns.char.bank
  local d = { bankT = type(b) == "table" and b.t or 0, starts = {}, need = {}, chain = {} }
  for k = 1, math.min(#starts, 8) do d.starts[k] = starts[k] end
  local seen = {}
  local function need(item, why)
    if not item or seen[item] or #d.need >= QI.MAX_NEED then return end
    seen[item] = true
    d.need[#d.need + 1] = { item = item, bags = bags[item] or 0, bank = (QI.InBank(item)), worn = worn[item] or 0, why = why }
  end
  local steps = BeelineData and BeelineData.steps
  local s = cur and steps and steps[cur]
  if steps and cur then
    for i = cur, math.min(#steps, cur + QI.STEPS_AHEAD) do
      local t = steps[i]
      if t then
        need(t.item, 1)
        if t.q then for _, it in ipairs(byQuest[t.q] or {}) do need(it, 1) end end
      end
    end
  end
  if s and s.q then
    for _, c in ipairs(QI.Chain(s.q)) do
      d.chain[#d.chain + 1] = { q = c.q, role = c.role, st = QI.QuestState(c.q) }
      for _, it in ipairs(byQuest[c.q] or {}) do need(it, 2) end
    end
  end
  return d
end

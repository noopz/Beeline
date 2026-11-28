-- The step card's words (no frames): what a step says, a trip's headline and lines, the step's note, the footer line.
-- The card itself: UI/Card.lua; its secure buttons: UI/Card/Secure.lua; its footer: UI/Card/Footer.lua.
-- Dead simple: the headline is the current action, at most one sub-line, the reasons behind the "?" button.
local _, ns = ...
local pcall = ns.PCall or pcall -- (a job never pauses under it: Core.lua)
local Style = ns.Style
local C = Style.C
local Card = {}
ns.Card = Card

-- the card's layout sizes, shared by its files
Card.PAD, Card.DIST_W = 14, 64

local function steps() return BeelineData and BeelineData.steps or {} end

-- quests numbered from 10000 up came after the original game (all of its quests are below that): Forever's own and
-- other later additions, whose quest data is younger and can miss what unlocks them
Card.NEW_QUEST_MIN = 10000
function Card.IsNewQuest(q) return type(q) == "number" and q >= Card.NEW_QUEST_MIN end
function Card.Describe(s)
  local kind = Style.Kind(s)
  local verb = Style.Hex(kind.color) .. (kind.verb or "") .. "|r"
  local qc = Style.Hex(Style.QuestColor(s.level))
  local title, detail
  if s.k == "accept" or s.k == "turnin" then
    title = verb .. " " .. qc .. (s.name or ("quest " .. tostring(s.q))) .. "|r"
    detail = s.npc and ((s.k == "accept" and "from " or "to ") .. s.npc) or nil
    -- (a pick-up an item starts, on a trip: its use button is above the card)
    if s.k == "accept" and s.item and not s.npc then detail = "use the " .. (s.itemName or "item") .. " (the icon above the card)" end
    -- one who walks a route (Patrol.lua): not at the pin, somewhere along the route the map draws
    if detail and ns.Patrol and ns.Patrol.For(s) then detail = detail .. " · walks a route, see the map" end
  elseif s.k == "obj" then
    -- who the item comes from (the plan's from: "Shadowforge mobs", a vendor, the pack it comes in) goes beside the quest:
    -- "A Dwarf and His Tools · from Shadowforge mobs". The title then drops the mobs the planner listed in its words
    -- ("Collect 8 Tough Wolf Meat (Ragged Timber Wolf, Ragged Young Wolf)"), not where it is done ("(in Uldaman)")
    local text = s.text or "Objective"
    if s.from then text = text:gsub(" %((.-)%)$", function(inner) if not inner:find("^in ") then return "" end end) end
    title = Style.Hex(kind.color) .. text .. "|r"
    detail = s.name and (qc .. s.name .. "|r") or nil
    if s.from then detail = (detail and (detail .. "  ·  ") or "") .. "from " .. s.from end
  elseif s.k == "fly" and s.boat then
    -- the planner names the town the boat docks at ("Boat to Auberdine"); dest is only the zone
    title = Style.Hex(kind.color) .. (s.text or ((kind.verb or "") .. " " .. (s.dest or ""))) .. "|r"
    detail = s.npc
  elseif s.k == "fly" or s.k == "hearth" then
    -- (to a zone with no flight master of your side: "Travel to", not "Fly to" - "Fly to" reads as a flight path that
    -- isn't there)
    if s.k == "fly" and s.to and ns.FLIGHT and not ns.FLIGHT[s.to] then verb = Style.Hex(kind.color) .. "Travel to|r" end
    title = verb .. " " .. (s.dest or s.text or "")
    detail = s.npc
  elseif s.k == "fp" then
    title = verb .. (s.fp and (" - " .. s.fp) or "")
    detail = s.npc and ("talk to " .. s.npc) or nil
  elseif s.k == "bind" then
    title = verb .. (s.bind and (" in " .. s.bind) or "")
    detail = s.npc and ("talk to " .. s.npc) or nil
  elseif s.k == "train" then
    title = verb .. " " .. (s.text or "your new spells")
    detail = s.npc
  elseif s.k == "bonus" then
    title = verb .. " " .. Style.Hex(kind.color) .. (s.text or "") .. "|r"
    detail = nil
  elseif s.k == "grind" then
    title = verb .. string.format(" to level %d%s", s.level or 0, (s.xp and s.xp > 0) and string.format(" + %d xp", s.xp) or "")
    detail = s.text
  else
    title = s.text or ""
  end
  return title, detail
end
-- the next home bases in one order (the card's rows and the base nudge): the plan's pick first, then the zone's XP an
-- hour (ns.ZoneRate, as Where to? ranks them), then the XP left there
function Card.BaseOrder(a, b)
  if (a.best and 1 or 0) ~= (b.best and 1 or 0) then return a.best and true or false end
  local ra, rb = ns.ZoneRate and ns.ZoneRate(a), ns.ZoneRate and ns.ZoneRate(b)
  if ra and rb and ra ~= rb then return ra > rb end
  return (a.xpLeft or 0) > (b.xpLeft or 0)
end
local function plain(t) return ((t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
Card.Plain = plain

-- a travel step's note minus the planner's generic travel advice ("Fly, or ride if there is no flight path yet."):
-- once the addon has a live trip from the flight paths you know, that sentence only contradicts it. What follows
-- it ("Next leg: Ashenvale 22+") and any hand-written instruction stay. nil when nothing is left.
-- the step's note, with what the game says about its gear reward (Quests.lua RewardNote)
function Card.Note(s) return s and (ns.Quests and ns.Quests.RewardNote and ns.Quests.RewardNote(s) or s.note) end
function Card.OwnNote(s)
  local n = Card.Note(s)
  if not n then return nil end
  n = n:gsub("^Fly, or ride[^.]*%.%s*", "")
  return n ~= "" and n or nil
end

-- The trip the card leads with, when reaching step s means more than a walk: a travel step's live trip, any trip of
-- several legs, one that starts with a flight, a boat, a portal or the hearthstone, and "sit tight" on a flight or a boat.
-- The card's title is then the leg you're on ("Fly to Westfall", not a numbered list of every leg), its detail where
-- it ends ("then on to Stranglethorn Vale"), and the other legs are in the "?" (UI/Explain.lua). A ride straight to
-- the step keeps the step's own title.
-- -> trip, legs; nil
local LEG_KIND = { fly = "fly", via = "fly", onflight = "fly", ride = "ride", boat = "boat", aboard = "boat", hearth = "hearth" }
local TRIP_LONG = { fly = true, boat = true, hearth = true, spell = true, via = true }
function Card.TripHead(s)
  if not (s and s.k ~= "hearth" and ns.Engine.TravelFor) then return nil end
  if ns.Engine.view and s.k ~= "fly" then return nil end
  local trip = ns.Engine.TravelFor(s)
  local legs = trip and (trip.legs or { trip })
  if not (legs and legs[1]) then return nil end
  -- (the trip there you skipped: the step heads the card, the trip is a line under it)
  if s.k ~= "fly" and ns.Engine.SkippedTripInto and ns.Engine.SkippedTripInto(s) then return nil end
  if s.k == "fly" or #legs > 1 or trip.how == "aboard" or TRIP_LONG[legs[1].how] then return trip, legs end
  return nil
end
-- a leg's kind (its colour), and its words with the verb in that colour (all of them, whole, when there is no verb
-- after which more follows) -> text, plain words
local function legKind(l) return Style.KIND[LEG_KIND[l.how] or "travel"] or Style.KIND.travel end
local function legText(l, kind, whole)
  local say = (ns.Travel and ns.Travel.LegSay(l)) or l.text or ""
  local verb, rest = say:match("^(%S+)%s+(.+)$")
  if verb then return Style.Hex(kind.color) .. verb .. "|r " .. rest, say end
  return whole and (Style.Hex(kind.color) .. say .. "|r") or say, say
end
Card.LegKind, Card.LegText = legKind, legText
-- the headline: the leg you're on, its verb in the leg's colour -> kind, title, plain headline
function Card.TripTitle(legs)
  local kind = legKind(legs[1])
  local title, head = legText(legs[1], kind, true)
  return kind, title, head
end
-- the line under it: where the trip ends. A travel step: "then on to Stranglethorn Vale" (nothing when the headline
-- already goes there); a quest step: "then Accept Hearts of the Lost in Wetlands"
function Card.TripGoal(s, legs, head)
  if s.k == "fly" then
    local place = s.boat and ((s.text or ""):match("^Boat to (.+)$") or s.dest) or s.dest or s.text
    if not place or (#legs == 1 and (head or ""):find(place, 1, true)) then return nil end
    return "then on to " .. place
  end
  local what = plain((Card.Describe(s)))
  local pm = ns.State.Position()
  local zone = (s.zone and s.m and pm ~= s.m and not what:find(s.zone, 1, true)) and (" in " .. Style.ShortZone(s.zone)) or ""
  return "then " .. what .. zone
end
-- the card's lines for the trip under its headline, one short line each: a flight path to pick up first, what the leg
-- you're on warns of, why you go (Explain.CardLine) and, on a long trip, the leg after it, dimmed. headed = the title is
-- the leg (Card.TripHead); not headed (a ride straight to the step), the leg leads the lines.
function Card.TripLines(i, trip, headed)
  local legs = trip.legs or { trip }
  local l1 = legs[1]
  local lines = {}
  if not headed then lines[#lines + 1] = ns.Travel.LegSay(l1) .. "." end
  if l1.fp and l1.fp.npc then
    lines[#lines + 1] = "|cffffd25aGet the flight path from " .. l1.fp.npc .. " first" .. ((l1.fp.here and l1.fp.yd) and (" (" .. Style.Distance(l1.fp.yd) .. ")") or " (on the way)") .. "|r"
  end
  local extra = ns.Travel.LegExtra(l1)
  if extra then lines[#lines + 1] = (l1.hostile and Style.Hex(C.warn) or "|cff8e99ad") .. extra:sub(1, 1):upper() .. extra:sub(2) .. ".|r" end
  -- why you go, grounded (Explain.Ground: why the card left the plan, the plan's odd step, or what the trip is for):
  -- the card's one line of it (Card.Fill adds none of its own when a trip's lines have it)
  local why = ns.Explain and ns.Explain.Ground(i)
  if why then lines[#lines + 1] = "|cffffd25a" .. why .. "|r"; Card.groundShown = i end
  -- (the legs after this one are the timeline's first rows (Card.Layout); with no rows under the card - Minimal - the
  -- one after it here)
  if headed and legs[3] and (ns.db.showNext or 3) == 0 then lines[#lines + 1] = "|cff8a93a6Next: " .. ns.Travel.LegSay(legs[2]) .. "|r" end
  return lines
end

-- the step's own note: its status, a full quest log, its warnings, or how to get there -> text, color
function Card.StepNote(s, i, status, headTrip)
  -- the thing to collect is in your bank: the quest only counts what's in your bags (the bank, a rested-XP stash) -
  -- take it out rather than farm it again
  if s.k == "obj" and s.item and ns.GetItemCount then
    local okA, all = pcall(ns.GetItemCount, s.item, true)
    local okB, bags = pcall(ns.GetItemCount, s.item, false)
    local banked = (okA and okB and tonumber(all) and tonumber(bags)) and (all - bags) or 0
    if banked > 0 then return string.format("You have %d in your bank: take %s out - the quest only counts what's in your bags.", banked, banked == 1 and "it" or "them"), C.gold end
  end
  if status == "blocked" then
    return "This quest isn't in your log. Accept it first, or skip - its later steps go too.", C.bad
  elseif status == "notready" then
    local left = {}
    local q = ns.State.Quest(s.q)
    for _, o in ipairs(q and q.objectives or {}) do if not o.finished then left[#left + 1] = o.text end end
    return "Not finished: " .. (#left > 0 and table.concat(left, ", ") or "objectives left"), C.warn
  elseif status == "later" and ns.Engine.NotYet(i) == "objectives" then
    -- a hand-in whose work (no place in the quest data) you skipped: it comes back when the quest is ready
    return "Finish this one as you go. It comes back when it's ready.", C.sub
  elseif status == "later" then
    return "Finish it inside the dungeon next time you run it.", C.sub
  elseif status == "wait" then
    -- (training: the trainer has nothing for you below the stop's level - not "not offered", a quest's words)
    local tl = s.k == "train" and ns.Engine.TrainFrom and ns.Engine.TrainFrom(i)
    if tl then return string.format("Nothing to learn until level %d.", tl) .. ((Card.Note(s) and ("  " .. Card.Note(s))) or ""), C.warn end
    -- the level it opens at, as the engine reads it (its level, red to you, a training level: Engine.NotYet)
    local why, _, lv = ns.Engine.NotYet(i)
    if why ~= "level" then lv = nil end
    if not lv and s.q and ns.QUEST_PRE and ns.QUEST_PRE[s.q] then
      local pre = ns.QUEST_PRE[s.q]
      for _, p in ipairs(pre.g or pre.s or {}) do
        if not ns.State.IsCompleted(p) then
          local n = ns.Engine.QuestName and ns.Engine.QuestName(p) or ("quest " .. p)
          return "Needs " .. n .. " handed in first. It comes back then.", C.warn
        end
      end
    end
    return (lv and string.format("Needs level %d.", lv) or "Not offered yet.") .. ((Card.Note(s) and ("  " .. Card.Note(s))) or ""), C.warn
  elseif s.k == "accept" and (status == "full" or ns.State.LogCount() >= ns.State.MaxLog()) then
    -- a warning on the quest itself (elites, an escort) still matters once there is room
    return string.format("Quest log full (%d/%d) - hand in or abandon something first.", ns.State.LogCount(), ns.State.MaxLog())
      .. ((s.warn and s.note) and ("\n" .. Style.Hex(C.warn) .. Card.Note(s) .. "|r") or ""), C.bad
  elseif s.k == "bonus" then
    return (s.where or "") .. (s.note and ("  |cff8e99ad" .. Card.Note(s) .. "|r") or ""), C.sub
  elseif ns.Drops and ns.Drops.Note(s) then
    -- the quest item drops far less than the plan assumed (Forever changed some rates)
    return ns.Drops.Note(s), C.warn
  elseif ns.Engine.TravelFor and ns.Engine.TravelFor(s) then
    -- the step is in another zone: how to get there from where you are
    local trip = ns.Engine.TravelFor(s)
    -- the step's own words (a hand-written "climb up onto Thoradin's Wall", "Next leg: ..."), without the
    -- planner's guess at how to travel, which the live trip replaces
    local own = Card.OwnNote(s)
    if trip.how == "aboard" and s.boat then own = nil end -- "Board the boat at the pier": done, you are on it
    own = own and ((s.warn and Style.Hex(C.warn) or "|cff8e99ad") .. own .. "|r")
    -- why go: what there is to do there, and where the route goes after
    -- what to do now and why go, a short line each (Card.TripLines); every leg in full is in the "?"
    local lines = Card.TripLines(i, trip, headTrip ~= nil)
    if own then lines[#lines + 1] = own end
    return table.concat(lines, "\n"), C.sub
  elseif s.k == "fly" and s.to and not s.boat and ns.Engine.TravelPlan then
    -- from the flight paths you actually have, not the planner's guess
    local plan = ns.Engine.TravelPlan(s)
    local dest = s.dest or s.text or "there"
    local where = plan and plan.stop and (plan.stop.npc or plan.stop.name) or nil
    if not plan then return "You have the " .. dest .. " flight path - fly there.", C.sub
    elseif plan.ride and ns.Engine.KnowsFlightIn(dest) then return "Ride there - " .. (where or "your first stop") .. " is " .. (plan.yards and Style.Distance(plan.yards) or "close") .. " away, quicker than flying.", C.sub
    elseif plan.via then return "No " .. dest .. " flight path yet: fly to " .. plan.viaName .. ", then ride the rest (the arrow takes over when you land).", C.warn
    else return "Ride there" .. (where and (" - " .. where .. " is the first stop") or "") .. " (no closer flight path you know).", C.sub end
  end
  return Card.Note(s), s.warn and C.warn or C.sub
end

-- A quest the plan has earlier, taken up again because it still pays here (Next.IsBehind): a bare "Accept Active
-- Ingredient" read as the plan jumping back (a report: on the way out of Dustwallow to Searing Gorge). Say it is a side
-- quest, what the whole quest takes, and what comes after: "Side quest first: ~12 min, +2.8k XP. Then: To Searing Gorge"
function Card.SideQuestNote(i)
  local planned = ns.Engine.planned
  if not (planned and i ~= planned and ns.Next and ns.Next.IsBehind and ns.Next.IsBehind(i)) then return nil end
  local list = BeelineData and BeelineData.steps
  local s, p = list and list[i], list and list[planned]
  if not (s and s.q and p) then return nil end
  -- its work still to do (the planner's seconds), a minute a stop
  local sec = 0
  for k = 1, #list do
    local t = list[k]
    if t.q == s.q and ns.Engine.Status(k) == "todo" then sec = sec + 60 + ((t.k == "obj" and tonumber(t.work)) or 0) end
  end
  local L = (UnitLevel and UnitLevel("player")) or 1
  local xp = ns.QuestXp and ns.QuestXp(s.q, L)
  if not xp and tonumber(s.level) and ns.Engine.QuestXP then xp = ns.Engine.QuestXP(tonumber(s.level), L) end
  local bits = { string.format("~%d min", math.max(1, math.floor(sec / 60 + 0.5))) }
  if xp and xp >= 100 then bits[#bits + 1] = "+" .. (xp >= 1000 and string.format("%.1fk", xp / 1000) or tostring(math.floor(xp))) .. " XP" end
  return "|cffffd100Side quest first: " .. table.concat(bits, ", ") .. ".|r Then: " .. plain((Card.Describe(p)))
end

-- "A few in Hillsbrad Foothills too (16 there) - the plan farms the bigger group here" for an objective step whose
-- mobs also stand, fewer of them, where the quest is given or handed in
function Card.AlsoNote(s)
  if not (s and s.k == "obj" and type(s.also) == "string") then return nil end
  local zone, n = s.also:match("^(.-):(%d+)$")
  if not zone or zone == s.zone then return nil end
  return string.format("|cff8e99adA few in %s too (%s there) - the plan farms the bigger group%s|r", zone, n, s.zone and (" in " .. s.zone) or " here")
end

-- The footer line: when you leave this zone and for where - "Next zone: Duskwood, after 4 quests here" (not plan
-- levels, which a player can't act on). Empty on a travel step (the card's own lines say where it goes and why) and
-- on a dungeon route; "Last zone on this plan" when nothing comes after.
-- on a dungeon route: which of its three parts you're in - "Pick up 3/4 > Run > Hand in", the part you're on lit
function Card.DungeonPhase(i)
  local list = steps()
  local run
  for k, s in ipairs(list) do if ns.Engine.RunDungeon(s) then run = k; break end end
  if not run then return "" end
  -- the dungeon's own quests: the ones handed in after the run
  local main, have = 0, 0
  for k = run + 1, #list do
    local s = list[k]
    if s.k == "turnin" and s.q and s.q > 0 then
      main = main + 1
      if ns.State.OnQuest(s.q) or ns.State.IsCompleted(s.q) then have = have + 1 end
    end
  end
  local part = (not i or i < run) and 1 or (i == run and 2) or 3
  local gold, dim = "|cffffd25a", "|cff8a93a6"
  local function lit(n, text) return (n == part and gold or dim) .. text .. "|r" end
  local left = 0
  if part == 3 then for k = run + 1, #list do local s = list[k]; if s.k == "turnin" and s.q and not ns.State.IsCompleted(s.q) then left = left + 1 end end end
  return lit(1, string.format("1 Pick up %d/%d", have, main)) .. dim .. "  >  |r" .. lit(2, "2 Run") .. dim .. "  >  |r" .. lit(3, part == 3 and string.format("3 Hand in (%d left)", left) or "3 Hand in")
end

function Card.FooterText(i)
  local data = BeelineData
  if data and data.dungeon and not data.special then return Card.DungeonPhase(i) end
  local s = i and steps()[i]
  if not (s and s.zone and data and not data.dungeon and ns.Engine.ZonesAhead) then return "" end
  -- (the card showing a stop pulled forward out of the plan's order: count from the plan's own next step, so the
  -- footer agrees with Where to?)
  local base = (i == ns.Engine.Shown() and ns.Engine.planned) or i
  local bs = steps()[base] or s
  local z = ns.Engine.ZonesAhead(base, 2)
  local here, nxt = z[1], z[2]
  if not (here and here.zone == bs.zone) then return "" end
  if not nxt and data.zoneRoute then
    local nz = ns.PlannedNextZone and ns.PlannedNextZone()
    if nz then local n = here.quests or 0; return "Then " .. Style.ShortZone(nz) .. " (your plan)" .. (n > 0 and string.format(", after %d quest%s here", n, n == 1 and "" or "s") or "") end
  end
  if not nxt then return "Last zone on this plan" end
  local n = here.quests or 0
  return "Next zone: " .. Style.ShortZone(nxt.zone) .. (n > 0 and string.format(", after %d quest%s here", n, n == 1 and "" or "s") or "")
end

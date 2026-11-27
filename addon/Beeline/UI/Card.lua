-- The step card. Rule: dead simple - the headline is the current action ("Fly to Westfall"), at most one sub-line
-- under it, and the reasons behind the "?" button.
--   header:   section (hub) + zone, route progress % and a hairline progress bar
--   current:  coloured accent strip, icon disc, title, details, distance; live objective bars for everything done
--             at this spot; target / use-item buttons; note or warning
--   timeline: the next few steps on a vertical line with coloured nodes
--   controls: icon buttons that fade in while the mouse is over the card
--   inside a dungeon (no coordinates in there): the dungeon's name and what your quest log has for it, with live
--             bars - Card.FillDungeon; the plan's step waits in the timeline below
-- its words: UI/Card/Text.lua; its secure buttons: UI/Card/Secure.lua; its footer: UI/Card/Footer.lua
local _, ns = ...
local pcall = ns.PCall or pcall -- (a job never pauses under it: Core.lua)
local Style = ns.Style
local C = Style.C
local Card = ns.Card

local PAD, DIST_W = Card.PAD, Card.DIST_W
local f
-- the step's tool row (right-aligned under the distance): Map, and the quest icon buttons left of it
Card.TOOL, Card.TOOL_GAP, Card.MAP_W = 16, 4, 38

local function steps() return BeelineData and BeelineData.steps or {} end
local function section(i) local s = steps()[i]; local secs = BeelineData and BeelineData.sections; return s and secs and secs[s.sec] end
local plain, legKind, legText = Card.Plain, Card.LegKind, Card.LegText

local function build()
  PAD = Style.M.cardPad; Card.PAD = PAD -- (the skin's margin: Style.UseSkin ran before this)
  f = CreateFrame("Frame", "BeelineCard", UIParent)
  f:SetSize(ns.db.cardWidth, 160)
  f:SetPoint("TOPRIGHT", UIParent, "RIGHT", -60, 230) -- (Card.DEFAULT_POS; Card.ApplyPos sets the real place)
  f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  -- movable in combat too: the card itself is not protected (its secure target / item buttons are their own frames
  -- on UIParent; moved in combat, they catch up when combat ends - Card.PlaceSecure). Out of combat they follow the
  -- card while it is dragged, from an OnUpdate set only while dragging.
  local function follow() if not InCombatLockdown() then Card.PlaceSecure() end end
  f:SetScript("OnDragStart", function(self) if not ns.db.locked then self:StartMoving(); self.dragging = true; self:SetScript("OnUpdate", follow) end end)
  f:SetScript("OnDragStop", function(self) self.dragging = nil; self:SetScript("OnUpdate", nil); self:StopMovingOrSizing(); Card.AnchorTop(); Card.PlaceSecure() end)
  Style.CardPanel(f)
  local HY = Style.M.cardHeadY -- (the skin can lift the header onto its title strip)

  -- header
  f.title = Style.Text(f, 11, C.gold, "OUTLINE"); f.title:SetPoint("TOPLEFT", PAD, -11 + HY); f.title:SetWordWrap(false)
  -- "?": why the card sends you here, in a line or two (UI/Explain.lua, worked out on the click). Always on the header,
  -- not in the hover bar: the moment you wonder is the moment you look at the card
  f.help = Style.Button(f, "?", 16, 16, function(self) if ns.Explain then ns.Explain.Show(self, ns.Engine.Shown and ns.Engine.Shown()) end end, "Why this step? Click to see.", C.gold)
  f.help:SetPoint("TOPRIGHT", -PAD + 4, -8 + HY)
  f.count = Style.Text(f, 10, C.dim); f.count:SetPoint("RIGHT", f.help, "LEFT", -6, 0); f.count:SetJustifyH("RIGHT")
  f.title:SetPoint("RIGHT", f.count, "LEFT", -8, 0)
  f.prog = CreateFrame("Frame", nil, f); f.prog:SetPoint("TOPLEFT", PAD, -28); f.prog:SetPoint("TOPRIGHT", -PAD, -28); f.prog:SetHeight(Style.M.progH)
  f.progFill = Style.Progress(f.prog)
  f.prog:SetScript("OnSizeChanged", function() Card.UpdateProgress() end)

  -- current step
  local cur = CreateFrame("Frame", nil, f); f.cur = cur
  cur:SetPoint("TOPLEFT", PAD, -40); cur:SetPoint("RIGHT", -PAD, 0); cur:SetHeight(60)
  Style.StepMark(f, cur, PAD) -- cur.accent, halo, disc, icon, check
  cur.dist = Style.Text(cur, 11, C.gold); cur.dist:SetPoint("TOPRIGHT", 0, -1); cur.dist:SetWidth(DIST_W); cur.dist:SetJustifyH("RIGHT"); cur.dist:SetWordWrap(false)
  cur.titleText = Style.Text(cur, 15, C.text); cur.titleText:SetPoint("TOPLEFT", cur.disc, "TOPRIGHT", 12, 1)
  cur.detail = Style.Text(cur, 11, C.sub); cur.detail:SetPoint("TOPLEFT", cur.titleText, "BOTTOMLEFT", 0, -4)
  cur.map = Style.Button(cur, "Map", Card.MAP_W, Card.TOOL, function() ns.ShowOnMap(ns.Engine.Shown()) end, "Open the world map where this step is (for a trip: where it takes you), its pin flashing", C.gold)
  cur.map:SetPoint("TOPRIGHT", cur, "TOPRIGHT", 0, -18)
  -- the step's quest buttons: small icons in a row left of Map (Card.Layout), with what they do in their tooltips.
  -- a red X, "not doing this quest": drops it from the route and future plans (warns first if later quests need it)
  cur.nope = Style.IconButton(cur, "btn-x", Card.TOOL, function() ns.Engine.Nope() end,
    { "Not doing this quest", "Drops it from your route and from future plans. If later quests need it, you're asked first. Undo brings it back." }, C.bad)
  -- a struck-through "!", "the giver doesn't offer it": the giver has nothing for you (no window opens, so the addon
  -- can't tell by itself). Off your route until you level up, like a giver who lists other quests but not this one
  cur.notOffered = Style.IconButton(cur, "btn-no-offer", Card.TOOL, function() ns.Engine.NotOffered() end,
    { "The giver doesn't offer it", "Click if the quest giver has nothing for you. This quest and the giver's others you could take now leave your route until your next level (a level or a quest you haven't done can be the reason), then they're tried again. Turned down a second time, a quest stays off until the game offers it. Its chain stays; Undo brings them back." })
  -- (a bigger glyph than the footer's buttons: smaller, the "!" under its stroke is a smudge)
  for _, b in ipairs({ cur.nope, cur.notOffered }) do b.icon:SetSize(Card.TOOL * 0.75, Card.TOOL * 0.75) end
  -- "not now": a stop the route took in from where you are (a hand-in while you're here) leaves the card until you move
  -- on; the plan's own next step comes back
  cur.notNow = Style.Button(cur, "not now", 60, 14, function() if ns.Next and ns.Next.Dismiss then ns.Next.Dismiss(ns.Engine.Shown and ns.Engine.Shown()) end end, "Skip this stop for now: the route goes back to its planned next step. It's offered again once you've moved on, or in 15 minutes.", C.dim, 10)
  -- a quest newer than the original game: a short tag, its meaning on hover
  cur.fq = Style.Button(cur, "Forever Quest", 84, 14, function() end, "Added by WoW Forever. If the giver has nothing for you, it drops off your route by itself.", C.forever, 10)
  cur.fq:SetWidth(cur.fq.label:GetStringWidth() + 12)
  cur.fq:Hide()
  -- a chain-start step spliced in for a zone you picked: you can say no (Stitch.Refuse)
  cur.noChain = Style.Button(cur, "skip chain start", 90, 14, function() local s = steps()[ns.Engine.Shown() or 0]; if s and s.chainStart and ns.Stitch then ns.Stitch.Refuse(s.chainStart) end end, "Take this chain start off your route. It won't be added again.", C.dim, 10)
  cur.noChain:SetWidth(cur.noChain.label:GetStringWidth() + 10)
  cur.noChain:Hide()
  cur.bars = {}
  cur.heads = {} -- the dungeon state's quest names, one above each quest's bars
  cur.note = Style.Text(cur, 11, C.sub)
  -- target / use-item and the other mobs' Targets: secure buttons above the card (UI/Card/Secure.lua)
  Card.BuildSecure(f, cur)

  -- animations
  local out = cur:CreateAnimationGroup()
  local a1 = out:CreateAnimation("Alpha"); a1:SetFromAlpha(1); a1:SetToAlpha(0); a1:SetDuration(0.18); a1:SetStartDelay(0.32)
  local t1 = out:CreateAnimation("Translation"); t1:SetOffset(-16, 0); t1:SetDuration(0.18); t1:SetStartDelay(0.32)
  out:SetScript("OnFinished", function() cur:SetAlpha(0); Card.Fill(); Card.Layout(); cur.animIn:Play() end)
  cur.animOut = out
  local inn = cur:CreateAnimationGroup()
  local a2 = inn:CreateAnimation("Alpha"); a2:SetFromAlpha(0); a2:SetToAlpha(1); a2:SetDuration(0.22)
  local t2 = inn:CreateAnimation("Translation"); t2:SetOffset(16, 0); t2:SetDuration(0)
  local t3 = inn:CreateAnimation("Translation"); t3:SetOffset(-16, 0); t3:SetDuration(0.22); t3:SetSmoothing("OUT")
  inn:SetScript("OnPlay", function() cur:SetAlpha(1) end)
  inn:SetScript("OnFinished", function() cur:SetAlpha(1) end)
  cur.animIn = inn
  local pop = cur.check:CreateAnimationGroup()
  local p1 = pop:CreateAnimation("Alpha"); p1:SetFromAlpha(0); p1:SetToAlpha(1); p1:SetDuration(0.12)
  local p2 = pop:CreateAnimation("Scale"); p2:SetScaleFrom(0.4, 0.4); p2:SetScaleTo(1, 1); p2:SetDuration(0.2); p2:SetSmoothing("OUT")
  local p3 = pop:CreateAnimation("Alpha"); p3:SetFromAlpha(1); p3:SetToAlpha(0); p3:SetDuration(0.2); p3:SetStartDelay(0.32)
  cur.pop = pop

  -- timeline of the next steps
  f.line = Style.Divider(f, 0.09); f.line:SetWidth(1)
  f.rows = {}
  for i = 1, 5 do
    local r = CreateFrame("Button", nil, f); r:SetHeight(20)
    r.dot = Style.Dot(r, 9); r.dot:SetPoint("LEFT", 18.5, 0) -- centre lines up with the icon disc above
    r.text = Style.Text(r, 11, C.sub); r.text:SetPoint("LEFT", r.dot, "RIGHT", 16, 0); r.text:SetPoint("RIGHT"); r.text:SetWordWrap(false); r.text:SetJustifyV("MIDDLE")
    Style.Highlight(r, 0.035)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", function(self, btn) if self.index then ns.Engine.Look(self.index, btn) end end) -- (a trip's leg row: no step)
    r:SetScript("OnEnter", function(self) Card.Hover(true); GameTooltip:SetOwner(self, "ANCHOR_LEFT"); if not self.index then GameTooltip:SetText("Part of the trip on the card", 1, 1, 1); GameTooltip:AddLine("It moves up to the card when you get there.", 0.6, 0.65, 0.72, true); GameTooltip:Show(); return end GameTooltip:SetText("Click to look at this step", 1, 1, 1); GameTooltip:AddLine("Right-click: show it on the map", 0.6, 0.65, 0.72); GameTooltip:AddLine("Shift-click to jump here (skips what's before it - Undo brings it back)", 0.6, 0.65, 0.72, true); GameTooltip:Show() end)
    r:SetScript("OnLeave", function() GameTooltip:Hide(); Card.Hover(false) end)
    f.rows[i] = r
  end

  -- footer: the next zone on the left (Card.FooterText), controls on the right (UI/Card/Footer.lua)
  Card.BuildFooter(f)

  f:SetScript("OnEnter", function() Card.Hover(true) end)
  f:SetScript("OnLeave", function() Card.Hover(false) end)
  f:SetScript("OnHide", function() if InCombatLockdown() then Card.needPlace = true else cur.target:Hide(); cur.item:Hide(); for _, b in ipairs(cur.targets) do b:Hide() end end end)
  f:SetScript("OnShow", function() C_Timer.After(0, function() Card.PlaceSecure() end) end)

  Style.Scaled(f, "scale") -- the Beeline scale x the card's own
  Card.ApplyPos() -- at its saved place for this scale, or the default place if that's off the screen
  C_Timer.After(0, function() Card.ApplyPos() end)
end

-- next home base rows: zone, XP left and the level it reaches; the plan's pick gets a PLAN pill
local function choiceRow(k)
  local cur = f.cur
  cur.optRows = cur.optRows or {}
  local r = cur.optRows[k]
  if r then return r end
  r = CreateFrame("Button", nil, cur); r:SetHeight(40)
  r.bgParts = Style.RowBg(r, 8, 0.05)
  r.edge = Style.RowEdge(r, 2, 2, 5)
  Style.Highlight(r, 0.08, C.gold, 2)
  r.name = Style.Text(r, 13, C.text, "OUTLINE"); r.name:SetPoint("TOPLEFT", 12, -6); r.name:SetWordWrap(false)
  r.fast = Style.Pill(r, "PLAN", C.good)
  r.rate = Style.Text(r, 11, C.gold); r.rate:SetPoint("TOPRIGHT", -10, -7); r.rate:SetJustifyH("RIGHT")
  r.lvl = Style.Text(r, 10, C.dim); r.lvl:SetPoint("TOPRIGHT", r.rate, "BOTTOMRIGHT", 0, -3); r.lvl:SetJustifyH("RIGHT")
  r.next = Style.Text(r, 10, C.dim); r.next:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3); r.next:SetPoint("RIGHT", r.lvl, "LEFT", -6, 0); r.next:SetWordWrap(false)
  r:SetScript("OnClick", function(self) if self.zrow and ns.Paths and ns.Paths.Pick then ns.Paths.Pick(self.zrow) end end)
  r:SetScript("OnEnter", function(self)
    Card.Hover(true)
    local z = self.zrow
    if not z then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(z.zone, 1, 1, 1)
    GameTooltip:AddLine(z.best and "Back to plan: where your plan goes next" or "Make it your home base", 0.5, 0.55, 0.62, true)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide(); Card.Hover(false) end)
  cur.optRows[k] = r
  return r
end

local function fillChoice()
  local cur = f.cur
  for _, r in ipairs(cur.optRows or {}) do r:Hide() end
  local ch = cur.choice
  if not (ch and ch.rows) then return end
  -- next home bases (a home base done for now): zone, XP left, the level it gets you to, a chain it continues
  for k, z in ipairs(ch.rows) do
    local r = choiceRow(k)
    r.zrow = z
    local zc = Style.ZoneColor(z.zone)
    r.name:SetText(Style.ShortZone(z.zone)); r.name:SetTextColor(zc[1], zc[2], zc[3])
    r.fast:ClearAllPoints(); r.fast:SetPoint("LEFT", r.name, "RIGHT", 7, 0); r.fast:SetShown(z.best and true or false)
    local P = ns.Paths
    r.rate:SetText(z.xpLeft and z.xpLeft > 0 and P and P.Short and ("~" .. P.Short(z.xpLeft) .. " XP") or "")
    r.lvl:SetText(z.xpLeft and z.xpLeft > 0 and P and P.ReachText and P.ReachText(z.xpLeft) or "")
    local away = z.tripSecs and P and P.Away and P.Away(z.tripSecs) or nil
    local reason = z.continues and ("continues " .. z.continues) or (z.handIns and z.handIns > 0 and (z.handIns .. " hand-in" .. (z.handIns == 1 and "" or "s") .. " waiting")) or nil
    r.next:SetText((away and reason) and (away .. " · " .. reason) or away or reason or "")
    local c = z.best and C.good or C.dim
    r.edge:SetVertexColor(c[1], c[2], c[3], z.best and 0.9 or 0.3)
    Style.SetRowBg(r.bgParts, 0.04)
    r:Show()
  end
end

local function setNote(text, color)
  local c = color or C.sub
  f.cur.note:SetText(text or ""); f.cur.note:SetTextColor(c[1], c[2], c[3])
end

-- an objective's words without its count (the bar shows that on the right), first ("0/1 Thing") or last ("Thing: 0/1")
local function countless(text) return (text:gsub(":%s*%d+%s*/%s*%d+%s*$", ""):gsub("^%s*%d+%s*/%s*%d+%s*", "")) end
local function objectiveBar(bar, s, o, kind, idx)
  bar.live = { s = s, kind = kind, idx = idx } -- (Card.Counts redraws it from this)
  if o and o.need and o.need > 0 then
    bar:Set(o.have / o.need, kind.color, countless(o.text), string.format("%d/%d", o.have, o.need))
  else
    bar:Set(o and o.finished and 1 or 0, kind.color, plain((Card.Describe(s))), "")
  end
  bar:Show()
end

-- Inside a dungeon: the game gives no coordinates in there, so no plan step can be pointed at. The card shows the
-- dungeon and what your quest log has for it instead (Dungeon.lua): each quest with a live bar per objective, the
-- finished ones ticked; quests picked up inside; and the ones you could have brought but didn't. The plan's own step
-- is the first line of the timeline below. Walking out brings the normal card back.
Card.DUNGEON_BARS = 12 -- bars at most; quests past that are one line each in the note
-- with more than this many quests to do in there, the card is compact: one bar a quest and no names above them - a
-- quest of one objective is what to get and its count, one of several is its name and the parts done ("Legends of
-- Maraudon 1/4") - and at most DUNGEON_BARS_COMPACT bars, the rest on the "Also:" line. (A bar an objective and a name
-- above each quest, with 6 quests in Maraudon, filled half the screen: a player)
Card.DUNGEON_COMPACT = 2
Card.DUNGEON_BARS_COMPACT = 5
local TICK = Style.GlyphTag("icon-check", 12) .. " "
local function namesOf(list, max)
  local t, seen, u = {}, {}, {}
  for _, e in ipairs(list) do if not seen[e.name] then seen[e.name] = true; u[#u + 1] = e end end
  list = u
  for k, e in ipairs(list) do
    if k > max then t[#t + 1] = string.format("+%d more", #list - max); break end
    t[#t + 1] = e.name .. (e.from and (" |cff8e99ad(" .. e.from .. ")|r") or "")
  end
  return table.concat(t, ", ")
end
function Card.FillDungeon(name, id, bar, look)
  local cur = f.cur
  local st = ns.Dungeon.State(id)
  local kind = Style.KIND.obj
  look(kind.color, "icon-kill")
  cur.dungeon = { name = name, id = id, done = st.done, total = st.total }
  cur.titleText:SetText(Style.Hex(Style.ZoneColor(name)) .. name .. "|r")
  local left = 0
  for _, q in ipairs(st.quests) do if not q.ready then left = left + 1 end end
  if #st.quests == 0 then cur.detail:SetText("Nothing in your quest log is done in here")
  elseif left == 0 then cur.detail:SetText(string.format("All %d quest%s for here done", #st.quests, #st.quests == 1 and "" or "s"))
  else cur.detail:SetText(string.format("%d quest%s to do in here%s", left, left == 1 and "" or "s", #st.quests > left and string.format("  ·  %d done", #st.quests - left) or "")) end
  cur.dist:SetText("")
  local lines, over = {}, {}
  local function head(text)
    local n = cur.nbars + 1 -- sits above the next bar
    local h = cur.heads[n]
    if not h then h = Style.Text(cur, 11, C.text); h:SetWordWrap(false); h:SetJustifyH("LEFT"); cur.heads[n] = h end
    h:SetText(text); cur.headAt[n] = h
  end
  local compact = left > Card.DUNGEON_COMPACT
  local maxBars = compact and Card.DUNGEON_BARS_COMPACT or Card.DUNGEON_BARS
  for _, q in ipairs(st.quests) do
    local title = Style.Hex(C.gold) .. q.name .. "|r"
    if q.ready then
      lines[#lines + 1] = TICK .. "|cff5cdc7a" .. q.name .. "|r |cff8e99ad- done|r"
    elseif cur.nbars + (compact and 1 or math.max(1, #q.objectives)) > maxBars then
      local n = 0
      for _, o in ipairs(q.objectives) do if not o.finished then n = n + 1 end end
      over[#over + 1] = q.name .. (n > 0 and string.format(" |cff8e99ad(%d left)|r", n) or "")
    elseif compact and #q.objectives > 1 then
      -- one bar for the quest: its name and how many of its parts are done (each part's share of the bar as far as it got)
      local fin, frac = 0, 0
      for _, o in ipairs(q.objectives) do
        if o.finished then fin = fin + 1; frac = frac + 1 elseif o.need > 0 then frac = frac + o.have / o.need end
      end
      local b = bar(); b:Set(frac / #q.objectives, kind.color, q.name, string.format("%d/%d", fin, #q.objectives)); b:Show()
    else
      if not (compact and #q.objectives <= 1) then head(title) end
      if #q.objectives == 0 then local b = bar(); b:Set(0, kind.color, compact and (q.name .. " - see your quest log") or "See your quest log", ""); b:Show() end
      for _, o in ipairs(q.objectives) do
        local b = bar()
        if o.need > 0 then
          b:Set(o.finished and 1 or o.have / o.need, kind.color, countless(o.text), string.format("%d/%d", o.have, o.need))
        else
          b:Set(o.finished and 1 or 0, kind.color, o.text, "")
        end
        b:Show()
      end
    end
  end
  if #over > 0 then table.insert(lines, 1, "Also: " .. table.concat(over, ", ")) end
  if #st.inside > 0 then lines[#lines + 1] = Style.Hex(C.gold) .. "Picked up in here:|r " .. namesOf(st.inside, 4) end
  if #st.missed > 0 then lines[#lines + 1] = "|cff8a93a6Not picked up:|r " .. namesOf(st.missed, 4) end
  setNote(table.concat(lines, "\n"), C.sub)
  f.title:SetText("|cffff7a6b" .. name:upper() .. "|r  |cff8a93a6DUNGEON|r")
  Card.UpdateProgress()
  Card.SetButtons(nil)
end

function Card.Fill()
  if not f then return end
  local cur = f.cur
  local i = ns.Engine.Shown()
  for _, b in ipairs(cur.bars) do b:Hide(); b.live = nil end
  -- (pairs: the quest titles are kept by the number of the bar they sit over - 1, 4, 7 - with gaps ipairs stops at)
  for _, h in pairs(cur.heads) do h:Hide() end
  cur.headAt = {}
  local wasDungeon = cur.dungeon
  cur.dungeon = nil
  cur.doneData, cur.doneLvl, cur.celebrate = nil, nil, nil -- (set again below while the plan stays finished: Card.UpdateInner)
  cur.nbars = 0
  cur.choice = nil; for _, r in ipairs(cur.optRows or {}) do r:Hide() end
  cur.map:Hide(); cur.nope:Hide(); cur.notOffered:Hide(); cur.notNow:Hide(); cur.fq:Hide(); cur.noChain:Hide()
  local function bar() cur.nbars = cur.nbars + 1; local b = cur.bars[cur.nbars]; if not b then b = Style.Bar(cur); cur.bars[cur.nbars] = b end; return b end
  -- (kind: the step kind whose own mark this is, for a skin with the game's marks)
  local function look(color, glyph, kind) Style.PaintMark(cur, color, glyph, kind) end
  local data = BeelineData -- (the demo swaps in its own)
  -- inside a dungeon the card is about the dungeon (not while you look at another step, or in the demo)
  if not ns.Engine.view and not (ns.Demo and ns.Demo.active) and ns.Dungeon then
    local dname, did = ns.Dungeon.Inside()
    if did then Card.FillDungeon(dname, did, bar, look); return end
  end
  if wasDungeon then Card.Header(); Card.UpdateProgress() end -- back out: the plan's own header again
  if not data then
    look(C.dim, "icon-note"); cur.titleText:SetText("No route loaded"); cur.detail:SetText("/reload to load the plan for your race and class."); setNote("")
    Card.SetButtons(nil); return
  end
  -- a zone you picked with only quests left that wait (a level, an earlier quest): done for now
  local WAITING = { wait = true, blocked = true, later = true }
  -- (waiting as the engine's pick read it: with nothing to do now it falls back on the first step that waits, and a
  -- hand-in whose objective is in the stretch your place skips waits there ("later") while its own status reads
  -- "notready")
  local function waiting(j) return WAITING[ns.Engine.Status(j)] or (ns.Engine.forNow and j == ns.Engine.planned) end
  local forNow = data.zoneRoute and i and not ns.Engine.view and waiting(i) or false
  -- (the plan the same, when nothing on it is to do now - Engine.forNow)
  local planForNow = not forNow and i and not ns.Engine.view and ns.Engine.forNow and not (data.zoneRoute or data.dungeon or data.special or data.branch)
    and waiting(i) or false
  -- your best few zones now, to pick the next home base from (here: the zone you stand in too)
  local function nextBases(here)
    local opts = {}
    local zc = ns.ZoneChoices and ns.ZoneChoices()
    if zc then
      local rows = {}
      for _, r in ipairs(zc.rows or {}) do if (r.route or r.planned) and (here or not r.here) then rows[#rows + 1] = r end end
      table.sort(rows, Card.BaseOrder)
      for k = 1, math.min(3, #rows) do opts[#opts + 1] = rows[k] end
    end
    return opts
  end
  -- (at level 60 the plan is done, whatever steps are left - Engine.Capped: no more questing, no next home base to level in)
  local maxed = ((UnitLevel and UnitLevel("player")) or 1) >= ns.Engine.MAX_LEVEL
  local POINTER = " Dungeons and quests you skipped are on the route window."
  if planForNow then
    look(C.good, "icon-check")
    -- (the step waiting stays the plan's: it comes back as the card's step once it opens)
    local why, _, lv = ns.Engine.NotYet(i)
    -- (zone rows only: the plan's own row is where you are)
    local opts = {}
    for _, r in ipairs(nextBases(true)) do if r.route and (r.questsLeft or 0) > 0 then opts[#opts + 1] = r end end
    cur.titleText:SetText("Route done for now")
    cur.detail:SetText(((why == "level" and lv) and ("Its next step opens at level " .. lv .. ". ") or "Its next steps wait for earlier quests. ")
      .. (#opts > 0 and "Pick your next home base:" or "Other zones: the house below."))
    if #opts > 0 then cur.choice = { rows = opts }; fillChoice() end
    setNote("")
    Card.SetButtons(nil); return
  end
  if not i or forNow then
    look(C.good, "icon-check")
    if data.dungeon then cur.titleText:SetText((data.dungeonName or "Dungeon") .. " route done"); cur.detail:SetText("Everything for it is handed in. \"Back to plan\" carries on leveling.")
    elseif data.zoneRoute then
      -- a zone you picked, done: "Carry on" goes where your planned route picks up; the route list has the other zones.
      -- Only once it has stayed done a few seconds: stops are added just after a login or a route change (a hand-in
      -- you finished, a side quest), and "done" can be true for a moment before they are
      Card.zoneDoneSince = Card.zoneDoneSince or (GetTime and GetTime()) or 0
      -- (and where to go next: your best few zones now - the zone you work from is yours to pick, the card says when it's
      -- time to pick again)
      local later, openAt, byLevel = 0, nil, true
      if forNow then
        for j, t in ipairs(steps()) do
          if t.k == "accept" and WAITING[ns.Engine.Status(j)] then
            later = later + 1
            if t.minLevel and t.minLevel > ((UnitLevel and UnitLevel("player")) or 1) then openAt = math.min(openAt or 99, t.minLevel) else byLevel = false end
          end
        end
      end
      local opts = nextBases(false)
      cur.titleText:SetText((Style.ShortZone(data.zoneName or "Zone")) .. (forNow and " done for now" or " done"))
      local wait = ""
      if forNow and later > 0 then
        wait = later .. (later == 1 and " quest here opens " or " quests here open ") .. ((byLevel and openAt) and ("at " .. openAt) or "later") .. ". "
      end
      cur.detail:SetText(wait .. (#opts > 0 and "Pick your next home base:" or "Other zones: the house below."))
      -- (clickable, so a zone can be picked from here)
      if #opts > 0 then cur.choice = { rows = opts }; fillChoice() end
      if C_Timer and not Card.zoneDoneTick then Card.zoneDoneTick = true; C_Timer.After(3.5, function() Card.zoneDoneTick = nil; if ns.Card.Layout then ns.Card.Layout() end end) end
    elseif not i and ns.Engine.planDone and not (data.special or data.branch) then
      -- the plan finished: at 60, done (no rows - nothing left to level); below it, your next home bases
      -- (Card.UpdateInner fills it once: refreshes standing here change nothing on it)
      cur.doneData, cur.doneLvl, cur.doneFin = data, (UnitLevel and UnitLevel("player")) or 1, ns.Engine.Finishing()
      if maxed then
        -- (level 60: celebrate - the route is done. "Finish my quests" below, Card.Layout)
        cur.celebrate = true
        cur.titleText:SetText(Style.Hex(C.gold) .. "Level 60 - you made it!|r")
        cur.detail:SetText(cur.doneFin and "Congratulations! The quests you held are done too." or "Congratulations! Your leveling route is done." .. POINTER)
      else
        local opts = {}
        for _, r in ipairs(nextBases(true)) do if r.route and (r.questsLeft or 0) > 0 then opts[#opts + 1] = r end end
        cur.titleText:SetText("Route complete")
        cur.detail:SetText("You've finished your plan. " .. (#opts > 0 and "Pick your next home base:" or "Other zones: the house below."))
        if #opts > 0 then cur.choice = { rows = opts }; fillChoice() end
      end
    else cur.titleText:SetText("Route complete"); cur.detail:SetText("That's the end of the plan.") end
    setNote("")
    Card.SetButtons(nil); return
  end
  Card.zoneDoneSince = nil -- (a step to show: the zone you picked is not done)
  local s = steps()[i]
  local kind = Style.Kind(s)
  local title, detail = Card.Describe(s)
  -- a trip: the leg you are on is the step you're on ("Fly to Westfall", then where it ends under it), not the far
  -- step it leads to or a list of legs
  local headTrip, headLegs = Card.TripHead(s)
  if headTrip then
    local head
    kind, title, head = Card.TripTitle(headLegs)
    detail = Card.TripGoal(s, headLegs, head)
    -- (to a flight master or flying from one: the headline names the flight path, who stands there goes under it, small)
    -- the headline is the town, the flight map's name ("Fly to Aerie Peak"); under it, small, its zone and who:
    -- "The Hinterlands · from Stormwind (Dungar Longdrink)"
    local l1 = headLegs[1]
    local sub = {}
    if l1.zone then sub[#sub + 1] = l1.zone end
    if l1.npc then sub[#sub + 1] = (l1.how == "fly" and l1.from) and ("from " .. l1.from .. " (" .. l1.npc .. ")") or (l1.npc .. ", flight master") end
    if #sub > 0 then detail = "|cff8e99ad" .. table.concat(sub, " · ") .. "|r" .. (detail and ("\n" .. detail) or "") end
  end
  look(kind.color, kind.icon, kind)
  local status = ns.Engine.Status(i)
  local group = ns.Engine.Group(i)
  -- ("Do these here" only once you're there: on the way, the headline is the leg)
  local multi = s.k == "obj" and #group > 0 and not headTrip
  if multi then title = Style.Hex(kind.color) .. "Do these here|r" end
  cur.titleText:SetText(title)
  local bits = {}
  if detail and not multi then bits[#bits + 1] = detail end
  -- (the zone only when the header names another: repeating it wraps the coordinates)
  -- (a trip: not the far step's zone and coordinates - the detail says where it ends)
  do local sc = section(i); if s.zone and not headTrip and not (sc and sc.zone == s.zone) then bits[#bits + 1] = Style.ShortZone(s.zone) end end
  -- (an unknown step's spot is only its place in the order: no coordinates, no map button)
  if s.x and s.y and not s.unknown and not headTrip then bits[#bits + 1] = string.format("|cff8e99ad%.0f, %.0f|r", s.x * 100, s.y * 100) end
  -- the walking path knows the floor heights: say when the stop is upstairs (a tower top) or below (a cellar, a cave)
  -- (only indoors - outdoors a height difference is a hill, the same rule as the arrow)
  if s.z and s.z0 and math.abs(s.z - s.z0) >= 6 and ns.Arrow and ns.Arrow.Indoors and ns.Arrow.Indoors() then
    bits[#bits + 1] = string.format("|cff8fd3ff%s %d yd|r", s.z > s.z0 and "up" or "down", math.floor(math.abs(s.z - s.z0) + 0.5))
  end
  cur.detail:SetText(table.concat(bits, "  ·  "))
  cur.map:SetShown((s.m and s.x and not s.unknown) or s.k == "fly" or false)
  cur.nope:SetShown((s.q and s.q > 0 and not ns.Engine.view) and true or false)
  cur.notNow:SetShown((not ns.Engine.view and ns.Engine.planned and i ~= ns.Engine.planned and ns.Next and ns.Next.CanDismiss and ns.Next.CanDismiss(i)) and true or false)
  cur.notOffered:SetShown((s.k == "accept" and s.q and s.q > 0 and not ns.Engine.view and not ns.State.OnQuest(s.q)) and true or false)
  if s.k == "obj" and s.unknown then
    -- work the quest data lists none of: the game's own lines for the quest, as the quest log has them (none: one bar
    -- that says to look there)
    local q = ns.State.Quest(s.q)
    local objs = q and q.on and q.objectives or {}
    if #objs == 0 then local b = bar(); b:Set(0, kind.color, "See your quest log", ""); b:Show() end
    for n, o in ipairs(objs) do
      if o.need and o.need > 0 then objectiveBar(bar(), s, o, kind, n)
      else local b = bar(); b:Set(o.finished and 1 or 0, kind.color, o.text, ""); b:Show() end
    end
  elseif s.k == "obj" then
    objectiveBar(bar(), s, ns.Engine.ObjectiveFor(s), kind)
    for _, j in ipairs(group) do local g = steps()[j]; objectiveBar(bar(), g, ns.Engine.ObjectiveFor(g), Style.Kind(g)) end
  elseif s.k == "grind" then
    local need = UnitXPMax("player"); local b = bar(); b:Set(UnitXP("player") / need, kind.color, "Level " .. UnitLevel("player"), string.format("%d/%d", UnitXP("player"), need)); b:Show()
  end
  if ns.Engine.view then
    setNote("Just looking - your progress isn't changed.", C.sub)
  else
    Card.groundShown = nil
    local text, color = Card.StepNote(s, i, status, headTrip)
    -- a quest newer than the original game: the quest data for those is younger and can miss what unlocks them
    if s.k == "accept" and Card.IsNewQuest(s.q) then cur.fq:Show() end
    if s.chainStart and ns.Stitch and ns.Stitch.Refuse then cur.noChain:Show() end
    -- the same mobs nearer the quest giver, in fewer numbers (s.also = "Hillsbrad Foothills:16", route2.js): why the
    -- plan farms them further away
    local also = Card.AlsoNote(s)
    if also then text = (text and text ~= "") and (text .. "\n" .. also) or also end
    -- (a quest the plan has earlier, taken up again here, says so in it: "Skipped earlier: +2.8k XP for ~12 min")
    -- the one grounded line (Explain.Ground) in its place: why the card left the plan's step (a quest from behind you:
    -- where, what it pays, how long), or what the plan's own odd step connects to later. A trip's lines have it already
    local ground = Card.groundShown ~= i and ns.Explain and ns.Explain.Ground(i)
    local side = ground and ("|cffffd25a" .. ground .. "|r") or nil
    if side then text = (text and text ~= "") and (side .. "\n" .. text) or side end
    -- live reordering picked this step because you are at it: that is exactly when its warnings and the full-log
    -- alert matter, so they stay, and the plan's own next step is a dim line under them
    -- a hand-in run here: say it - the moment the questing was for
    local run = ns.Next and ns.Next.Batch and ns.Next.Batch(i)
    if run then
      local rl = string.format("|cffffd100Hand-in run here: %d quests, about %s XP|r", run.n, BreakUpLargeNumbers and BreakUpLargeNumbers(run.xp) or tostring(run.xp))
      text = (text and text ~= "") and (rl .. "\n" .. text) or rl
    end
    -- (the options' "Step notes" off: hints go, warnings stay)
    if ns.db.cardNotes == false and color ~= C.warn and color ~= C.bad then text = "" end
    setNote(text, color)
  end
  cur.choice = nil
  fillChoice()
  Card.SetButtons(s)
end


-- The card hangs from its top: anchored elsewhere (as a drag can leave it), every change of height moves its top -
-- and the Target button, which sits above that top and can't move in combat, is left out of place. Out of combat only
-- (the card's anchor is ours, but it carries the secure buttons' place with it). A card never dragged hangs from its
-- top too (Card.DEFAULT_POS), and a place saved by an older version is made one.
-- Its place is kept in the game's own units (what it measures at scale 1), never in the card's scaled ones: the game
-- multiplies a frame's offsets by its scale, so a place saved at one scale would be off the screen at a bigger one.
-- { "ABS", left, top } in UIParent units.
function Card.AnchorTop()
  if not f or InCombatLockdown() then return end
  if Style.SavePos(f, "cardPos", "TOPLEFT") then Card.ApplyPos() end
end
-- set the card at its saved place for its current scale; off the screen (or no place yet), the default place
Card.DEFAULT_POS = { "TOPRIGHT", "RIGHT", -60, 230 }
function Card.ApplyPos()
  if not f or InCombatLockdown() then return end
  local p = ns.db.cardPos
  f:ClearAllPoints()
  if Style.PlaceSaved(f, "cardPos", "TOPLEFT") then -- (kept: Style.SavePos)
  elseif type(p) == "table" and p[1] and p[2] then
    f:SetPoint(p[1], UIParent, p[2], tonumber(p[3]) or 0, tonumber(p[4]) or 0) -- an older save: where it was...
    if f:GetLeft() and f:GetTop() then return Card.AnchorTop() end -- ...hung from its top from now on
  else
    local d = Card.DEFAULT_POS; f:SetPoint(d[1], UIParent, d[2], d[3], d[4])
  end
  if not Card.OnScreen() then Card.ResetPos(true) end
end
-- is enough of the card on the screen to grab? (a corner of it, in screen units)
function Card.OnScreen()
  local l, t, r, b = f:GetLeft(), f:GetTop(), f:GetRight(), f:GetBottom()
  if not (l and t and r and b) then return true end
  local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
  local W, H = UIParent:GetWidth(), UIParent:GetHeight()
  return r * s > 40 and l * s < W - 40 and t * s > 40 and b * s < H - 20
end
-- back to the default place (/bee card reset; or by itself when it was off the screen)
function Card.ResetPos(quiet)
  if not f or InCombatLockdown() then return end
  ns.db.cardPos = nil
  f:ClearAllPoints(); local d = Card.DEFAULT_POS; f:SetPoint(d[1], UIParent, d[2], d[3], d[4])
  if not quiet then f:Show(); ns.Print("Card back at its place, at the normal size.") elseif ns.Why then ns.Why("card", "the card was off the screen: put back at its place") end
  C_Timer.After(0, Card.PlaceSecure)
end


local LINK_H = 14 -- the height of the small "not now" link
function Card.Layout()
  if not f then return end
  local cur = f.cur
  local x0 = 50
  -- give text explicit widths so wrapped heights are measured correctly
  local inner = (f:GetWidth() or ns.db.cardWidth) - 2 * PAD
  -- the tool row under the distance, from the right: Map, then the quest icons. The title and the detail line keep
  -- clear of it (the title runs beside it when it takes two lines).
  local toolW, tx = 0, 0
  if cur.map:IsShown() then toolW = Card.MAP_W; tx = Card.MAP_W + Card.TOOL_GAP end
  for _, b in ipairs({ cur.notOffered, cur.nope }) do
    if b:IsShown() then
      b:ClearAllPoints(); b:SetPoint("TOPRIGHT", cur, "TOPRIGHT", -tx, -18)
      toolW = tx + Card.TOOL; tx = toolW + Card.TOOL_GAP
    end
  end
  cur.titleText:SetWidth(inner - x0 - math.max(DIST_W, toolW) - 4); cur.detail:SetWidth(inner - x0 - math.max(44, toolW + 6)); cur.note:SetWidth(inner - x0)
  local y = cur.titleText:GetStringHeight() + 4 + ((cur.detail:GetText() or "") ~= "" and cur.detail:GetStringHeight() or 0)
  y = math.max(y, 38)
  for k = 1, cur.nbars or 0 do
    local b = cur.bars[k]
    local h = cur.headAt and cur.headAt[k]
    if h then h:ClearAllPoints(); h:SetPoint("TOPLEFT", cur, "TOPLEFT", x0, -(y + 9)); h:SetPoint("RIGHT"); h:Show(); y = y + 9 + 11 end
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", cur, "TOPLEFT", x0, -(y + 8)); b:SetPoint("RIGHT")
    y = y + 8 + 18
  end
  -- "not now": a row of its own under the title, detail and bars, from the text's left edge, as wide as its words.
  -- (Nothing of the Target / use-item buttons here: they float above the card - Card.PlaceSecure.)
  local nn = cur.notNow
  if nn:IsShown() then
    local sw = nn.label:GetStringWidth() or 0
    nn:SetWidth(math.min(inner - x0, sw > 0 and math.ceil(sw) + 14 or 60))
    y = y + 7
    nn:ClearAllPoints(); nn:SetPoint("TOPLEFT", cur, "TOPLEFT", x0, -y)
    y = y + LINK_H
  end
  local prevLink = nn:IsShown() and nn or nil
  for _, tagBtn in ipairs({ cur.fq, cur.noChain }) do
    if tagBtn:IsShown() then
      tagBtn:ClearAllPoints()
      if prevLink then tagBtn:SetPoint("LEFT", prevLink, "RIGHT", 8, 0)
      else
        y = y + 7
        tagBtn:SetPoint("TOPLEFT", cur, "TOPLEFT", x0, -y)
        y = y + LINK_H
      end
      prevLink = tagBtn
    end
  end
  if (cur.note:GetText() or "") ~= "" then
    cur.note:ClearAllPoints(); cur.note:SetPoint("TOPLEFT", cur, "TOPLEFT", x0, -(y + 7))
    y = y + 7 + cur.note:GetStringHeight()
  end
  if cur.choice then
    for k = 1, #cur.choice.rows do
      local r = cur.optRows[k]
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", cur, "TOPLEFT", x0 - 6, -(y + (k == 1 and 10 or 5))); r:SetPoint("RIGHT", cur, "RIGHT", 0, 0)
      y = y + (k == 1 and 10 or 5) + 40
    end
  end
  cur:SetHeight(y)
  local top = 40 + y + 14
  f.line:Hide()
  if ns.db.collapsed then
    for _, r in ipairs(f.rows) do r:Hide() end
    f.eta:Hide(); f.ret:Hide(); f.leave:Hide(); f.drop:Hide(); f.dropWanted = nil
    for _, b in pairs(f.btn) do b:Hide() end
    -- (and every row under the card: the reminders, offers, the house and Undo)
    for _, row in pairs(Card.ExtraRows()) do row:Hide() end
    f.ctl:ClearAllPoints(); f.ctl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD + 4, -top + 6)
    f.btn.min:Show(); f.btn.min:ClearAllPoints(); f.btn.min:SetPoint("RIGHT", f.ctl, "RIGHT")
    f:SetHeight(top + 8)
    C_Timer.After(0, Card.PlaceSecure)
    return
  end
  -- (the plan from its own place, not from the step on the card, which can be filed far ahead. The card's step
  -- itself isn't listed again)
  local shownI = ns.Engine.Shown()
  local base = ns.Engine.PlanAt and ns.Engine.PlanAt() or shownI
  local up = {}
  for _, j in ipairs(ns.Engine.Upcoming(base and base ~= shownI and base - 1 or shownI, 9)) do if j ~= shownI and #up < 8 then up[#up + 1] = j end end
  local grouped = {}; for _, j in ipairs(ns.Engine.Group(ns.Engine.Shown() or 0)) do grouped[j] = true end
  local rows = {}
  if cur.dungeon and ns.Engine.Shown() then rows[1] = ns.Engine.Shown() end -- the plan's step, for when you're out again
  -- a trip of several legs: the legs after the one on the card come first, one row each - you land, and the next one
  -- moves up to the card. Not a numbered list on the card itself: the headline stays the leg you're on
  local nShow = ns.db.showNext or 3
  if nShow > 0 and not cur.dungeon and shownI then
    local _, legs = Card.TripHead(steps()[shownI])
    if legs and legs[2] then
      for n = 2, math.min(#legs, 4) do rows[#rows + 1] = { leg = legs[n] } end
    end
  end
  local cap = math.min(#f.rows, nShow + #rows)
  for _, j in ipairs(up) do if not grouped[j] and #rows < cap then rows[#rows + 1] = j end end
  for k, r in ipairs(f.rows) do
    local i = rows[k]
    if type(i) == "table" then
      local l = i.leg
      local kind = legKind(l)
      r.index, r.base, r.cnt = nil, nil, nil
      r.dot:SetVertexColor(kind.color[1], kind.color[2], kind.color[3], 0.9)
      r.text:SetText((legText(l, kind))); r.text:SetAlpha(1 - (k - 1) * 0.15)
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 4, -top); r:SetPoint("RIGHT", -PAD, 0); r:Show()
      top = top + 20
    elseif i then
      local s = steps()[i]; local kind = Style.Kind(s)
      r.index = i
      r.dot:SetVertexColor(kind.color[1], kind.color[2], kind.color[3], 0.9)
      -- objectives coming up show your live count, so half-done ones are obvious
      local o = s.k == "obj" and ns.Engine.ObjectiveFor(s)
      local cnt = o and o.need and o.need > 0 and string.format("  |cff8a93a6%d/%d|r", o.have or 0, o.need) or ""
      r.base, r.cnt = (Card.Describe(s)), cnt
      r.text:SetText(r.base .. cnt); r.text:SetAlpha(1 - (k - 1) * 0.2)
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 4, -top); r:SetPoint("RIGHT", -PAD, 0); r:Show()
      top = top + 20
    else r:Hide() end
  end
  if #rows > 0 then
    -- vertical line from under the icon disc down to the last timeline dot
    local lastCentre = top - 10 -- top already moved past the last row
    f.line:Show(); f.line:ClearAllPoints()
    f.line:SetPoint("TOP", cur.disc, "BOTTOM", 0, -4)
    f.line:SetHeight(math.max(1, lastCentre - (40 + 38 + 4)))
  end
  top = top + 8
  Card.LayoutFooter(top)
end

function Card.UpdateProgress()
  if not f then return end
  -- inside a dungeon: its quests' objectives, done of all
  local dg = f.cur and f.cur.dungeon
  if dg then
    f.count:SetText(dg.total > 0 and string.format("%d/%d", dg.done, dg.total) or "")
    f.progFill:SetWidth(math.max(0.001, (f.prog:GetWidth() or 0) * (dg.total > 0 and dg.done / dg.total or 0)))
    return
  end
  -- progress through this zone (a fresh plan doesn't reset it to nothing; the whole plan is in /bee list)
  local done, total, zone = ns.Engine.LegProgress()
  -- (who picked this zone: you - your home base - or your plan)
  local d = BeelineData
  local who = d and not d.dungeon and not d.special and "Base: " or "" -- (your plan's zone is your home base too)
  f.count:SetText(total > 0 and string.format("%s%d/%d", zone and (who .. Style.ShortZone(zone) .. "  ") or "", done, total) or "")
  f.progFill:SetWidth(math.max(0.001, (f.prog:GetWidth() or 0) * (total > 0 and done / total or 0)))
end


function Card.Header()
  local i = ns.Engine.Shown()
  local sec = i and section(i)
  local dname = BeelineData and BeelineData.dungeon and (BeelineData.dungeonName or BeelineData.title)
  -- (the zone once: a title that names it - "Out in Redridge Mountains" - with its short name, and no zone after it)
  local t, z = sec and sec.title, sec and sec.zone
  -- (a stop in another zone than its stretch - a hand-in pulled in on the way: that zone, not the stretch's)
  local st = i and steps()[i]
  if st and st.zone and z and st.zone ~= z and not dname then t, z = "On the way: " .. st.zone, st.zone end
  local named = t and z and t:lower():find(z:lower(), 1, true)
  if named then
    local a2 = t:lower():find(z:lower(), 1, true)
    -- (a hub's "Zone: NPC, NPC": the progress on the right names the zone, so just the people)
    if a2 == 1 and t:sub(#z + 1, #z + 1) == ":" then t = t:sub(#z + 2):gsub("^%s+", "")
    else t = t:sub(1, a2 - 1) .. Style.ShortZone(z) .. t:sub(a2 + #z) end
  end
  -- (a side trip's section that only repeats its name - "VOIDWALKER (WARLOCK 10)  Special: Voidwalker (warlock 10)")
  if dname and t and t:lower():find(dname:lower(), 1, true) then t = "" end
  f.title:SetText((dname and ("|cffff7a6b" .. dname:upper() .. "|r  ") or "") .. (sec and (t:upper() .. (not dname and not named and z and z ~= sec.title and ("  |cff8a93a6" .. Style.ShortZone(z) .. "|r") or "")) or (BeelineData and BeelineData.title or "Beeline")))
end
-- A count moved ("Gnoll Paws: 3/8", State.lua FR_PROGRESS): only the bars and counts on the card change - its text,
-- height and buttons stay (a full redraw on every kill costs ms; this is a few bars).
function Card.Counts()
  if not f then return end
  local cur = f.cur
  if cur.dungeon or (cur.animOut and cur.animOut:IsPlaying()) then return Card.Update(false) end
  for n = 1, cur.nbars or 0 do
    local b = cur.bars[n]
    local L = b and b.live
    if L then
      local o
      if L.idx then local q = ns.State.Quest(L.s.q); o = q and q.on and q.objectives[L.idx] else o = ns.Engine.ObjectiveFor(L.s) end
      local sig = o and ((o.have or 0) .. "/" .. (o.need or 0) .. (o.finished and "f" or "") .. (o.text or "")) or ""
      if sig ~= b.liveSig then b.liveSig = sig; objectiveBar(b, L.s, o, L.kind, L.idx) end
    end
  end
  for _, r in ipairs(f.rows or {}) do
    local s = r:IsShown() and r.index and r.base and steps()[r.index]
    if s and s.k == "obj" then
      local o = ns.Engine.ObjectiveFor(s)
      local cnt = o and o.need and o.need > 0 and string.format("  |cff8a93a6%d/%d|r", o.have or 0, o.need) or ""
      if cnt ~= r.cnt then r.cnt = cnt; r.text:SetText(r.base .. cnt) end
    end
  end
end

function Card.Update(animate)
  if not f then return end
  local t0 = debugprofilestop and debugprofilestop()
  Card.UpdateInner(animate)
  if t0 and ns.Time then ns.Time("card", debugprofilestop() - t0) end
end
-- (timed: what a card redraw costs in your game shows in /bee report)
function Card.UpdateInner(animate)
  local i = ns.Engine.Shown()
  -- (inside a dungeon the header is the dungeon's: Card.FillDungeon)
  if not (f.cur.dungeon and ns.Dungeon and ns.Dungeon.Inside()) then Card.Header() end
  Card.UpdateProgress()
  f.eta:SetText((ns.db.cardZones ~= false or (BeelineData and BeelineData.dungeon)) and Card.FooterText(i) or "") -- (a dungeon route's parts show whatever the zones option)
  local cur = f.cur
  if animate then
    cur.animOut:Stop(); cur.animIn:Stop(); cur.pop:Stop()
    cur.pop:Play(); cur.animOut:Play()
  elseif not cur.animOut:IsPlaying() then
    -- (the plan finished and still is - same plan, same level, no step looked at, not in a dungeon or the demo: the card
    -- already says so; no FR_STEP redraw)
    local data = BeelineData
    local same = not i and cur.doneData and cur.doneData == data and ns.Engine.planDone and not ns.Engine.view
      and not (ns.Demo and ns.Demo.active) and cur.doneLvl == ((UnitLevel and UnitLevel("player")) or 1)
      and not (ns.Dungeon and select(2, ns.Dungeon.Inside())) and cur.doneFin == ns.Engine.Finishing()
    if not same then Card.Fill(); Card.Layout() end
  end
end
-- a footer row's data changed (reminder, offer, "also hand in", drop count): lay the card out again, once a frame.
-- Not FR_STEP: that re-runs the engine's step listeners, the pins, the list and the zones panel.
local repaint = ns.Debounce(0, function()
  if f and not f.cur.animOut:IsPlaying() then Card.Layout() end -- (the animation lays it out when it ends)
end)
function Card.Repaint() if f then repaint() end end

ns.On("FR_LOADED", function() build(); f:SetShown(not ns.db.hidden); Card.Update() end)
ns.On("FR_STEP_DONE", function() if f then Card.Update(true) end end)
ns.On("FR_STEP", function() Card.Update(false) end)
ns.On("FR_ZONETRIPS", function() if f and Card.zoneDoneSince then Card.Update(false) end end) -- (the next bases' trips are in)
ns.On("FR_PROGRESS", function() Card.Counts() end) -- (a count moved: "Gnoll Paws: 3/8")
ns.On("FR_DUNGEON", function() if f then Card.Update(false) end end) -- walked into or out of a dungeon
ns.On("FR_XP", function() local s = ns.Engine.CardAt() and steps()[ns.Engine.CardAt()]; if f and s and s.k == "grind" and not f.cur.animOut:IsPlaying() then Card.Fill(); Card.Layout() end end)
ns.On("FR_TOGGLE", function() if not f then return end; ns.db.hidden = not ns.db.hidden; f:SetShown(not ns.db.hidden) end)
-- a setting changed (Style applied the scale): the card's width and contents, the Target macro (out of combat; the
-- card refills the button then), and next frame the same place on the screen at the new scale. Not for the settings
-- of the arrow and the map pins
Card.OTHERS_KEYS = { arrow = true, arrowScale = true, gameNav = true, pins = true, pinCount = true, pathLine = true, meshLine = true,
  miniPin = true, miniPinScale = true, miniPath = true }
ns.On("FR_SETTINGS", function(key)
  if not f or Card.OTHERS_KEYS[key] then return end
  local i = ns.Engine.Shown and ns.Engine.Shown()
  if i and BeelineData then pcall(Card.SetButtons, BeelineData.steps[i]) end
  f:SetWidth(ns.db.cardWidth); Card.Update()
  C_Timer.After(0, function() if f then Card.ApplyPos(); Card.PlaceSecure() end end)
end)
-- leg = the arrow points at a waypoint on the way (the flight master, the pier), not the step: say which, so
-- "40 yd" next to a step a zone away is not read as the distance to the step
-- (a ride points at the first place on the road there - a zone crossing, or a town on the way: "via")
local LEG_WORD = { fly = "FM ", via = "FM ", boat = "dock ", ride = "via " }
ns.On("FR_DISTANCE", function(yards, arrived, leg)
  if not f then return end
  local prefix = leg and LEG_WORD[leg] and ("|cff8a93a6" .. LEG_WORD[leg] .. "|r") or ""
  f.cur.dist:SetText(arrived and "|cff5cdc7ain the area|r" or (yards and (prefix .. Style.Distance(yards)) or ""))
end)
ns.On("PLAYER_REGEN_DISABLED", function() if f and ns.db.combatFade and f:IsShown() then UIFrameFadeOut(f, 0.25, f:GetAlpha(), 0.35) end end)
ns.On("PLAYER_REGEN_ENABLED", function() if f and f:GetAlpha() < 1 then UIFrameFadeIn(f, 0.25, f:GetAlpha(), 1) end end)


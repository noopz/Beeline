-- The card's footer: the rows under the step (FOOT), the hover controls, Undo at the bottom line's right, the drop
-- link (with the side rail hidden), Back / Finish / Leave, and what feeds the rows (the companion's ready signal and change note, special
-- side trips, a hand-in ready nearby).
local _, ns = ...
local pcall = ns.PCall or pcall -- (a job never pauses under it: Core.lua)
local Style = ns.Style
local C = Style.C
local Card = ns.Card
local PAD -- (Card.PAD: the skin's margin, set when the card is built)
local f

-- the footer's flag: "this looks wrong" keeps what the card showed for the next /bee report (Moments.lua) - no chat
-- line; a brief green tick on the icon says it was kept
Card.FLAG_TIP = { "Looks wrong? Click, then send /bee report." }
function Card.FlagMoment(b)
  local m = ns.Moments and ns.Moments.Flag()
  if not (b and b.icon) then return m end
  if m then Style.Glyph(b.icon, "icon-check"); Style.Paint(b.icon, C.good) end
  if C_Timer and C_Timer.After then
    C_Timer.After(2, function() Style.Glyph(b.icon, "btn-flag"); Style.Paint(b.icon, b.rest or C.sub) end)
  end
  return m
end

-- the footer's frames, made with the card (build, UI/Card.lua)
function Card.BuildFooter(frame)
  f, PAD = frame, Card.PAD
  -- footer: the next zone on the left (Card.FooterText), Undo at the right, controls left of it (shown on hover). The
  -- places to go (the route, Where to?, side trips, the log check, options) are on the side rail (UI/Card/Rail.lua)
  f.eta = Style.Text(f, 10, C.dim); f.eta:SetWordWrap(false)
  f.ctl = CreateFrame("Frame", nil, f); f.ctl:SetSize(184, 20); f.ctl:SetAlpha(0)
  f.ctl.OnChildEnter = function() Card.Hover(true) end
  f.btn = {
    back = Style.IconButton(f.ctl, "btn-back", 20, function() ns.Engine.Back() end, "Look at the previous step"),
    fwd = Style.IconButton(f.ctl, "btn-next", 20, function() ns.Engine.Forward() end, "Next step"),
    done = Style.IconButton(f.ctl, "icon-check", 20, function() ns.Engine.MarkDone() end, "Mark this step done"),
    skip = Style.IconButton(f.ctl, "btn-skip", 20, function() ns.Engine.Skip() end, "Skip this step (a skipped quest's later steps go too)"),
    min = Style.IconButton(f.ctl, "btn-min", 20, function() ns.db.collapsed = not ns.db.collapsed; if ns.Rail then ns.Rail.Manual() end; Card.Update() end, "Collapse / expand"),
    -- "this looks wrong": the moment kept for a bug report (Moments.lua), the flag turning green a moment to say so
    flag = Style.IconButton(f.ctl, "btn-flag", 20, function(self) Card.FlagMoment(self) end, Card.FLAG_TIP),
  }
  for _, b in pairs(f.btn) do b:HookScript("OnLeave", function() Card.Hover(false) end) end
  -- Undo: at the bottom line's right for Card.UNDO_SECS after something you can undo (Card.UndoShown); /bee undo any time
  f.undo = Style.IconButton(f, "btn-undo", 20, function() ns.Engine.Undo() end, "Undo the last skip / done")
  f.undo:HookScript("OnEnter", function() Card.Hover(true) end); f.undo:HookScript("OnLeave", function() Card.Hover(false) end); f.undo:Hide()
  f.ret = Style.Button(f, "Back to current step", 140, 18, function() ns.Engine.view = nil; ns.Fire("FR_STEP", ns.Engine.Shown()) end)
  -- level 60: the route is done (Engine.Capped). This finishes the quests you hold - their objectives and hand-ins, nothing
  -- new - and a second click ("Back to level 60") goes back to the level 60 card (Engine.SetFinishing)
  f.finish = Style.Button(f, "Finish my quests", 130, 18, function() ns.Engine.SetFinishing(not ns.Engine.Finishing()) end,
    "Finish the quests in your log: their objectives and hand-ins, nothing new picked up. Click again to stop.")
  f.finish:Hide()
  -- on a dungeon route or side trip: the way back to your plan, always on the card (the side rail's top button too)
  f.leave = Style.Button(f, "Back to plan", 100, 18, function() ns.LeaveDungeonRoute() end,
    "Leave this dungeon route or side trip and carry on with your plan. Progress here is kept.")
  f.leave:Hide()
  -- quests in your log you won't do (not on the route, or gray by then): a nudge that opens the log check (with the side
  -- rail hidden: the rail's Log check has the count)
  f.drop = Style.Button(f, "", 90, 14, function() ns.Fire("FR_TOGGLE_LOGCHECK") end, "Quests in your log no route of yours uses. Click to look them over.", C.warn, 10)
  f.drop:Hide()
  -- the rows under the step (laid out by Card.Layout from FOOT): a line of text, at the right an optional button
  -- (go = { label, width, onClick, tip, field, icon = glyph: an icon, not a label }) and an optional "x" (x = { onClick,
  -- tip }); wrap: a text of two lines
  local function footRow(key, color, go, x, wrap)
    local r = CreateFrame("Frame", nil, f); r:SetHeight(wrap and 28 or 20)
    r.text = Style.Text(r, 10, color); r.text:SetPoint("LEFT", 0, 0); r.text:SetWordWrap(wrap or false)
    local right
    if go then
      right = go.icon and Style.IconButton(r, go.icon, go[2], go[3], go[4]) or Style.Button(r, go[1], go[2], 18, go[3], go[4])
      right:SetPoint("RIGHT", r, "RIGHT", x and -20 or 0, 0)
      r[go[5] or "go"] = right
    end
    if x then r.x = Style.XButton(r, 16, x[1], x[2]); r.x:SetPoint("RIGHT", r, "RIGHT", 0, 0); right = right or r.x end
    if not wrap then if right then r.text:SetPoint("RIGHT", right, "LEFT", -6, 0) else r.text:SetPoint("RIGHT", 0, 0) end end
    r:Hide()
    f[key] = r
    return r
  end
  -- options that just opened up (a level-up brought new zones): one line, Where to? (the Home base view), dismiss
  footRow("offer", C.gold, { nil, 18, function() if ns.Paths and ns.Paths.Show then ns.Paths.Show("zones") end end,
    { "Where to?", "Opens the zones you could go to now. Nothing changes unless you pick one." }, icon = "icon-where" },
    { function() ns.Offers.Dismiss(f.offer.base or false) end, "Hide this until your next level" })
  -- a newer plan from the companion: reload to load it (Card.SaveNudge)
  footRow("save", C.info, { "Reload", 64, function() Card.Save() end, "Reload (a few seconds) to load the new route." },
    { function() if Card.planReady then Card.readyDismissed = true end; Card.Layout() end, "Not now" })
  -- after a reload into a new plan: what changed on your path and why (once per plan; the companion writes it)
  footRow("change", C.lilac, { "OK", 34, function() ns.char.changeSeen = BeelinePlan and BeelinePlan.generated; Card.Layout() end, "Got it", "ok" })
  f.change:EnableMouse(true)
  f.change:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine("Your plan was updated", 1, 0.82, 0.3)
    GameTooltip:AddLine(Card.ChangeNote() or "", 1, 1, 1, true); GameTooltip:Show()
  end)
  f.change:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- a special reward not done yet (the Cozy Sleeping Bag): one line, Do it now, dismiss
  footRow("special", C.gold, { "Do it now", 70, function() local r = f.special.route; if r then ns.EnterDungeonRoute(r.id) end end, "Switch to this side trip now. \"Back to plan\" on the card returns you." },
    { function() Card.HideSpecial(f.special) end, "Hide this (it stays in the Beeline window, under side trips). A stop for it in another zone shows it there." })
  -- errands: bags nearly full, with the nearest vendor that can help
  footRow("errand", C.info, nil, { function() ns.Errands.Dismiss() end, "Hide until it changes" })
  -- a finished quest whose hand-in is close by (Engine.ReadyNearby): one line, Do it now
  footRow("ready", C.blue, { "Do it now", 70, function() local r = Card.readyNear; if r then ns.Engine.FocusOn(r.i, "you chose it: ready to hand in nearby") end end, "Show this hand-in on the card now. Your plan is kept - it comes back after." })
  -- a quest an item in your bags starts (ns.ItemQuests): a line (two when it needs them) and "x". The use button is
  -- the card's use-item button above it: a secure button can't sit on a row, and rows move in combat
  footRow("itemq", C.gold, nil, { function() ns.ItemQuests.Dismiss() end, "Not doing it: this quest isn't offered again (the item stays in your bags)" }, true)
  f.itemq:EnableMouse(true)
  f.itemq:SetScript("OnEnter", function(self)
    local o = ns.ItemQuests and ns.ItemQuests.Current()
    if not o then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(o.name, 1, 0.82, 0.3)
    GameTooltip:AddLine(f.cur.offerItem and "Click the item's icon above the card to start it." or "Use it from your bags to start it (the button above the card is this step's own item).", 1, 1, 1, true)
    GameTooltip:AddLine("Once you have it, its objectives and hand-in are added to your route where they cost least. " .. o.xp .. " xp.", 0.75, 0.8, 0.88, true)
    GameTooltip:Show()
  end)
  f.itemq:SetScript("OnLeave", GameTooltip_Hide)
  -- "Also hand in": a finished quest the route doesn't cover, with its NPC nearby
  footRow("extra", C.blue)
end

-- the rows under the card's step, in their order: get() -> what the row says (nil or false: hidden); set(row, v)
-- fills it -> its height (nil: 22). log: kept in the decision log; extra: hidden on a collapsed card (Card.ExtraRows)
local saveBtn
local FOOT = {
  { key = "offer", log = true, extra = true,
    get = function() if ns.Offers and not ns.Engine.view and ns.db.cardOffers ~= false then return (select(2, ns.Offers.Current())) end end,
    set = function(row, offer) row.text:SetText(offer.text); row.base = offer.base; row.go:SetShown(true) end }, -- (base: what its x dismisses)
  { key = "extra", log = true, extra = true,
    get = function() return ns.Extras and not ns.Engine.view and ns.Extras.Line() end,
    set = function(row, t) row.text:SetText(t) end },
  { key = "change",
    get = function() return Card.ChangeNote() end,
    set = function(row, cn) row.text:SetText("Plan updated: " .. cn) end },
  { key = "save", log = true, extra = true,
    get = function() local sv, b = Card.SaveNudge(); saveBtn = b; return sv end,
    set = function(row, sv) row.text:SetText(sv); row.go.label:SetText(saveBtn or "Reload") end },
  { key = "special", log = true, extra = true,
    get = function()
      local inside = ns.Dungeon and ns.Dungeon.Inside and select(2, ns.Dungeon.Inside())
      return (not ns.Engine.view and not inside and not (BeelineData and BeelineData.dungeon)) and Card.SpecialOffer() or nil
    end,
    set = function(row, sp) row.route = sp.route; row.near = sp.near; row.text:SetText(sp.text) end },
  { key = "errand", log = true, extra = true,
    get = function() return ns.Errands and not ns.Engine.view and ns.Errands.Current() end,
    set = function(row, t) row.text:SetText(t) end },
  { key = "ready", extra = true,
    get = function() return not ns.Engine.view and Card.readyNear end,
    set = function(row, rd) row.text:SetText(string.format("Ready nearby: %s%s, %d yd", rd.name or "a quest", rd.npc and (" to " .. rd.npc) or "", math.floor(rd.d + 0.5))) end },
  { key = "itemq", log = true, extra = true,
    get = function() return not ns.Engine.view and ns.db.cardItemQuests ~= false and ns.ItemQuests and ns.ItemQuests.Current() end,
    set = function(row, iq)
      -- (an explicit width, so the wrapped height is measured right: the "x" takes the last 22)
      row.text:SetWidth((f:GetWidth() or ns.db.cardWidth) - PAD - Card.LPAD - 22)
      row.text:SetText(ns.ItemQuests.Text(iq, not f.cur.offerItem))
      local h = math.max(20, math.ceil((row.text:GetStringHeight() or 0) + 4))
      row:SetHeight(h)
      return h + 2
    end },
}
-- the rows hidden on a collapsed card: the footer rows above and Undo (no bottom line to sit on)
local extraRows
function Card.ExtraRows()
  if not extraRows then
    extraRows = { undo = f.undo }
    for _, sp in ipairs(FOOT) do if sp.extra then extraRows[sp.key] = f[sp.key] end end
  end
  return extraRows
end
-- the "N off-route" link (the side rail hidden): at the right of the footer (left of Undo), or - while you hover the card and its controls
-- take that spot - at the left, where the footer line fades out. Never hidden on hover: the mouse on its way to click it
-- would make it vanish
function Card.PlaceDrop(hover)
  if not f or not f.drop then return end
  f.drop:ClearAllPoints()
  -- (after "Back to my path" / "Change zone" when it is there, not on top of it)
  local full, short = f.dropText or "", f.dropCount and tostring(f.dropCount) or ""
  f.drop.label:SetText(full); f.drop:SetWidth(f.drop.label:GetStringWidth() + 12)
  local show = f.dropWanted and true or false
  if hover then
    f.drop:SetPoint("LEFT", f.eta, "LEFT", -6, 0)
    -- the room before the controls, so it doesn't run under them. Too narrow: the count alone (its tooltip says what
    -- it is), against the controls' left edge - always there to click, never hidden for want of room
    local ctlLeft, ctlBtn
    for _, b in pairs(f.btn) do if b:IsShown() and b:GetLeft() and (not ctlLeft or b:GetLeft() < ctlLeft) then ctlLeft, ctlBtn = b:GetLeft(), b end end
    local etaLeft = f.eta:GetLeft()
    if ctlLeft and etaLeft and f.drop:GetWidth() > ctlLeft - (etaLeft - 6) - 4 then
      f.drop.label:SetText(short); f.drop:SetWidth(f.drop.label:GetStringWidth() + 12)
      f.drop:ClearAllPoints(); f.drop:SetPoint("RIGHT", ctlBtn, "LEFT", -4, 0)
      f.drop:SetFrameLevel(math.max(f.drop:GetFrameLevel(), f.ctl:GetFrameLevel() + 2))
    end
  elseif f.rightEdge then f.drop:SetPoint("RIGHT", f.rightEdge, "LEFT", -4, 0)
  else f.drop:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD + 6, f.dropY or 0) end
  f.drop:SetShown(show)
end
function Card.Hover(on)
  if not f then return end
  if not on then
    C_Timer.After(0.2, function() if f and not f:IsMouseOver() and f.ctl:GetAlpha() > 0 then Card.hovering = false; UIFrameFadeOut(f.ctl, 0.2, f.ctl:GetAlpha(), 0); UIFrameFadeIn(f.eta, 0.2, f.eta:GetAlpha(), 1); Card.PlaceDrop(false) end end)
    return
  end
  -- (the link moves left whenever the controls are up, even while they are still fading)
  Card.hovering = true
  if f.ctl:GetAlpha() < 1 then UIFrameFadeIn(f.ctl, 0.12, f.ctl:GetAlpha(), 1); UIFrameFadeOut(f.eta, 0.12, f.eta:GetAlpha(), 0) end
  Card.PlaceDrop(true)
end

-- Undo shows for UNDO_SECS once something you did (FR_USER_ACTION: a skip, a tick, a jump, not doing a quest) adds to
-- your history; kept: the history the action began on (a route switch swaps it) and its last entry, to see that it did
Card.UNDO_SECS = 10
local undoArm, undoUntil
ns.On("FR_USER_ACTION", function(name)
  if name == "Undo" or name == "Back" or name == "Forward" then return end
  local h = ns.char and ns.char.history
  if h then undoArm = { h = h, n = #h, top = h[#h] } end
end)
function Card.UndoShown()
  local h = ns.char and ns.char.history
  if not h then return false end
  local now = GetTime()
  if undoArm and undoArm.h ~= h then undoArm = nil end
  if undoArm and (#h > undoArm.n or (#h > 0 and h[#h] ~= undoArm.top)) then
    undoArm, undoUntil = nil, now + Card.UNDO_SECS
    C_Timer.After(Card.UNDO_SECS + 0.1, function() if f then Card.Layout() end end)
  end
  return #h > 0 and undoUntil ~= nil and now < undoUntil
end

-- the footer's part of Card.Layout, from top: the rows, the drop link, Back / Finish / Leave, the footer line, Undo at
-- its right, and the controls left of it
function Card.LayoutFooter(top)
  local cur = f.cur
  for _, sp in ipairs(FOOT) do
    local row, v = f[sp.key], sp.get()
    row:SetShown(v and true or false)
    if v then
      local h = sp.set(row, v) or 22
      row:ClearAllPoints(); row:SetPoint("TOPLEFT", f, "TOPLEFT", Card.LPAD, -top); row:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
      top = top + h
    end
  end
  local nd = ns.LogCheck and ns.LogCheck.dropCount or 0
  -- (a small link at the right of the footer, not a row of its own: saves room. With the side rail shown, its Log check
  -- has the count)
  f.dropWanted = nd > 0 and not ns.Engine.view and Card.RAILW == 0
  f.drop:SetShown(f.dropWanted)
  if f.dropWanted then
    f.dropText, f.dropCount = string.format("%d off-route", nd), nd
    f.drop.label:SetText(f.dropText)
    f.drop:SetWidth(f.drop.label:GetStringWidth() + 12)
  end
  local viewing = ns.Engine.view ~= nil
  f.ret:SetShown(viewing)
  if viewing then f.ret:ClearAllPoints(); f.ret:SetPoint("TOPLEFT", Card.LPAD, -top); top = top + 24 end
  -- level 60: "Finish my quests" on the celebration, "Stop finishing quests" while you finish them (Engine.SetFinishing)
  local fin = ns.Engine.Finishing()
  local showFin = not viewing and (cur.celebrate or fin) and true or false
  f.finish:SetShown(showFin)
  if showFin then
    f.finish.label:SetText(fin and "Back to level 60" or "Finish my quests")
    f.finish:ClearAllPoints(); f.finish:SetPoint("TOPLEFT", Card.LPAD, -top); top = top + 24
  end
  local trip = BeelineData and BeelineData.dungeon and not viewing and not showFin
  f.leave:SetShown(trip and true or false)
  if trip then f.leave:ClearAllPoints(); f.leave:SetPoint("TOPLEFT", Card.LPAD, -top); top = top + 24 end
  f.dropY = -top - 2
  local undo = Card.UndoShown()
  f.undo:SetShown(undo)
  if undo then f.undo:ClearAllPoints(); f.undo:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD + 4, -top + 1) end
  -- (the line, the drop link and the hover bar end left of it)
  local fixedW = undo and 23 or 0
  f.rightEdge = undo and f.undo or nil
  f.eta:Show(); f.eta:ClearAllPoints(); f.eta:SetPoint("TOPLEFT", Card.LPAD, -top - 4); f.eta:SetPoint("RIGHT", f, "RIGHT", -PAD - fixedW - (f.dropWanted and f.drop:GetWidth() + 4 or 0), 0)
  Card.PlaceDrop(Card.hovering or f.ctl:GetAlpha() > 0.5) -- (hovering: at the left, the controls have the right; after Undo is set)
  f.ctl:ClearAllPoints(); f.ctl:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD + 4 - fixedW, -top + 1)
  local x = 0
  for _, name in ipairs({ "min", "skip", "done", "fwd", "back", "flag" }) do
    local b = f.btn[name]
    local show = true
    if name == "fwd" then show = viewing end
    if name == "flag" then show = not viewing end -- (the card looked at, not the route's answer: nothing to flag)
    if (name == "done" or name == "skip") and (viewing or cur.dungeon) then show = false end -- (in a dungeon the card's step isn't the one on show)
    b:SetShown(show)
    if show then b:ClearAllPoints(); b:SetPoint("RIGHT", f.ctl, "RIGHT", -x, 0); x = x + 23 end
  end
  -- the decision log: each card row the moment it appears or changes, with its text
  Card.lastRow = Card.lastRow or {}
  for _, sp in ipairs(FOOT) do
    if sp.log then
      local name, row = sp.key, f[sp.key]
      local txt = row:IsShown() and row.text and row.text:GetText() or nil
      -- compare without numbers, so a distance or count ticking down is not a new entry
      local sig = txt and txt:gsub("%d", "")
      if sig and sig ~= Card.lastRow[name] and ns.Why then ns.Why("card", name .. ": " .. txt:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
      Card.lastRow[name] = sig
    end
  end
  -- (at least as tall as the side rail's buttons: a short card - a hand-in, one step under it - grows to fit them)
  f:SetHeight(math.max(top + 26, ns.Rail.MinHeight()))
  C_Timer.After(0, Card.PlaceSecure)
end

-- saving = reloading the UI: the only time the game writes addon data, which the planner reads
local loadedAt = GetTime()
function Card.Save()
  if InCombatLockdown and InCombatLockdown() then ns.Print("Not in combat - save once it's over."); return end
  ReloadUI()
end
-- the companion's signal: a valid (silent) sound file means a new plan is installed and waiting for a reload
Card.READY_FILE = "Interface\\AddOns\\Beeline\\signal\\ready.wav"
Card.READY_GRACE = 60 -- right after a reload the companion hasn't cleared the old signal yet
function Card.CheckReady()
  if GetTime() - loadedAt < Card.READY_GRACE then return end
  if InCombatLockdown and InCombatLockdown() then return end
  -- "a plan newer than yours": a file named after the stamp of the plan you have loaded
  local g = BeelinePlan and BeelinePlan.generated
  if not g then return end
  local file = Card.READY_FILE:gsub("ready%.wav$", "newer-" .. g .. ".wav")
  local ok, will, handle = pcall(PlaySoundFile, file, "Master")
  if ok and handle and StopSound then pcall(StopSound, handle) end
  local ready = (ok and will) and true or false
  if ready ~= Card.planReady then
    Card.planReady = ready
    if ready then Card.readyDismissed = nil; ns.Print("A new route is ready - reload when it suits you (the card has a button)."); if ns.Why then ns.Why("ready", "the companion marked your plan (" .. tostring(BeelinePlan and BeelinePlan.generated) .. ") as out of date: a newer plan changes what is ahead of you") end end
    if f then Card.Layout() end
  end
end
ns.On("FR_LOADED", function() ns.NewTicker(10, ns.Guard("ready", Card.CheckReady)) end)
-- the companion's note on what changed in this plan (once per plan, until you press OK)
function Card.ChangeNote()
  local p = BeelinePlan
  if not (p and type(p.changeNote) == "string" and p.changeNote ~= "") then return nil end
  if ns.char and ns.char.changeSeen == p.generated then return nil end
  return p.changeNote
end
function Card.SaveNudge()
  if Card.planReady and not Card.readyDismissed then return "New route ready - reload to get it", "Reload" end
  -- (no "save and replan on a flight": the companion only collects now - nothing replans from a save)
  return nil
end
ns.On("PLAYER_CONTROL_LOST", function() C_Timer.After(1, function() if f then Card.Layout() end end) end)
ns.On("PLAYER_CONTROL_GAINED", function() C_Timer.After(0.5, function() if f then Card.Layout() end end) end)

-- the next stop of a special route you can do now: an accept you don't have yet, an objective of one in your log that
-- isn't finished (where the work is, not the quest giver who won't take it yet), or the hand-in once it is ready
function Card.SpecialNext(r)
  for _, s in ipairs(ns.Steps(r)) do
    if s.q and s.q > 0 and s.m and s.x and not s.unknown and not ns.State.IsCompleted(s.q) then
      if s.k == "accept" and not ns.State.OnQuest(s.q) then return s end
      if ns.State.OnQuest(s.q) then
        local ready = ns.State.QuestReady(s.q)
        if s.k == "turnin" then
          if ready then return s end
          -- not ready and no objective stop we could point at: nothing to do here yet (and the steps after it are
          -- likely its follow-ups, whose givers won't offer them yet either)
          return nil
        end
        if s.k == "obj" and not ready then
          local o = ns.Engine.ObjectiveFor(s)
          if not (o and o.finished) then return s end
        end
      end
    end
  end
end
local HBDc = LibStub("HereBeDragons-2.0")
-- the first special-reward side trip you haven't finished or hidden: { route, text }
function Card.SpecialOffer()
  local m = ns.State.Position()
  -- a stop near you first (worth the detour now), then the rest in plan order (class quests before the bag)
  local list, near, nextOf = {}, {}, {} -- (nextOf: each route's next stop, walked once)
  for _, r in ipairs(ns.DungeonRoutes and ns.DungeonRoutes() or {}) do if r.special then local nx = Card.SpecialNext(r); nextOf[r] = nx or false; if nx and m and nx.m == m and not ns.Engine.GroupTrip(r) then near[#near + 1] = r else list[#list + 1] = r end end end
  for _, r in ipairs(list) do near[#near + 1] = r end
  for _, r in ipairs(near) do
    if r.special and (UnitLevel("player") or 1) >= (tonumber(r.needsLevel) or 1) then
      local total, done = 0, 0
      for q in pairs(ns.QuestIds(r)) do if q > 0 then total = total + 1; if ns.State.IsCompleted(q) then done = done + 1 end end end
      if total > 0 and done < total then
        local name = r.dungeonName or r.title
        local nx = nextOf[r]
        -- its next stop is on this map: worth a detour, shown even if the row was hidden - unless you hid it on this map
        -- (not a trip that takes a group - an attunement, a dungeon key: its stops are no detour on your way, Engine.GroupTrip)
        if nx and m and nx.m == m and not ns.Engine.GroupTrip(r) and not (ns.char.hideSpecialNear and ns.char.hideSpecialNear[r.id] == m) then
          local px, py, pinst = HBDc:GetPlayerWorldPosition()
          local wx, wy, winst = HBDc:GetWorldCoordinatesFromZone(nx.x, nx.y, nx.m)
          local d = (px and wx and pinst == winst) and math.sqrt((px - wx) ^ 2 + (py - wy) ^ 2) or nil
          return { route = r, near = true, text = name .. ": next stop here" .. (d and (", " .. ns.Style.Distance(d)) or "") .. " - worth a detour" }
        end
        if not (ns.char.hideSpecial and ns.char.hideSpecial[r.id]) then
          return { route = r, text = name .. "  |cff8a93a6" .. (done > 0 and string.format("%d/%d done", done, total) or (r.tag or "side trip")) .. "|r" }
        end
      end
    end
  end
end
-- the row's "x" (row: { route, near }): hides the row; a detour offered here is hidden on this map too
function Card.HideSpecial(row)
  local r = row and row.route
  if not r then return end
  ns.char.hideSpecial = ns.char.hideSpecial or {}; ns.char.hideSpecial[r.id] = true
  if row.near then ns.char.hideSpecialNear = ns.char.hideSpecialNear or {}; ns.char.hideSpecialNear[r.id] = ns.State.Position() end
  Card.Layout()
end
-- arriving in a zone with the next stop: one chat line
local lastSpecialMap
function Card.SpecialArrive()
  local m = ns.State.Position()
  if not m or m == lastSpecialMap then return end
  lastSpecialMap = m
  local o = Card.SpecialOffer()
  if o and o.near then ns.Print((o.route.dungeonName or o.route.title) .. ": a stop for it is in this zone. \"Do it now\" is on the card.") end
end
ns.On("ZONE_CHANGED_NEW_AREA", function() C_Timer.After(2, function() pcall(Card.SpecialArrive); if f then Card.Fill(); Card.Layout() end end) end)

-- the "ready nearby" line: looked at every two seconds where you stand (its own check, apart from the live reordering);
-- the card redraws only when what it would say changes
Card.readyNear = nil
function Card.CheckReadyNearby()
  if not (f and f:IsShown()) then return end
  local px, py, pinst = HBDc:GetPlayerWorldPosition()
  local r = ns.Engine.ReadyNearby and ns.Engine.ReadyNearby(px, py, pinst) or nil
  if r and r.i == ns.Engine.Shown() then r = nil end
  local was = Card.readyNear
  Card.readyNear = r
  -- (the distance shown moves with you: redraw when it changed by 10 yd, or another quest or none)
  if (was and was.i) ~= (r and r.i) or (was and r and math.abs(was.d - r.d) >= 10) then Card.Layout() end
end
if C_Timer and C_Timer.NewTicker then ns.NewTicker(2, function() pcall(Card.CheckReadyNearby) end) end

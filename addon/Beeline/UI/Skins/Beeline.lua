-- The Beeline skin: our own look (dark rounded panels, flat buttons, tinted glyphs). The default, and the base every
-- other skin inherits from. Builders that place art read the active skin (Style.skin), so a skin that overrides only
-- art keeps these builders. Style.Bee is this skin itself: the arrow and the map pins always draw with it.
local _, ns = ...
local Style = ns.Style
local MEDIA, WHITE = Style.MEDIA, Style.WHITE
local S = { name = "beeline" }
Style.Skins.beeline = S
Style.Bee = S

S.C = {
  bg = { 0.025, 0.028, 0.036, 0.94 },
  bg2 = { 0.035, 0.038, 0.05, 0.96 },
  edge = { 1, 1, 1, 0.07 },
  gold = { 1.0, 0.82, 0.36 },
  text = { 0.95, 0.95, 0.97 },
  -- secondary text. On the panel fill (bg) sub is about 10:1 and dim about 7:1 (small text needs at least 4.5:1)
  sub = { 0.72, 0.76, 0.84 },
  dim = { 0.56, 0.60, 0.68 },
  good = { 0.36, 0.86, 0.48 },
  warn = { 1.0, 0.55, 0.30 },
  bad = { 1.0, 0.36, 0.36 },
  white = { 1, 1, 1 },
  black = { 0, 0, 0 },
  glyphOnDisc = { 0.07, 0.07, 0.09 }, -- the step's glyph on its coloured disc
  mob = { 1, 0.55, 0.5 },             -- the Target button's sword
  muted = { 0.55, 0.58, 0.66 },       -- an edge for a row that is off your route
  tab = { 0.1, 0.11, 0.14 },          -- the zones panel's pull tab
  info = { 0.55, 0.85, 1 },           -- a new plan, an errand
  lilac = { 0.85, 0.8, 1 },           -- what changed on your plan
  blue = { 0.45, 0.78, 1.0 },         -- a hand-in ready nearby
  forever = { 0.56, 0.83, 1 },        -- the "Forever Quest" tag
}
S.M = {
  cardPad = 14,  -- the card's margin
  progH = 2,     -- the card's progress hairline
  barTrack = 4,  -- an objective bar's track
  chromeOut = 0, -- how far a window's frame art reaches past the window
  chromeTop = 0, -- and above it
  cardHeadY = 0, -- how far the card's header sits above its usual place
}
S.FLAT = WHITE -- the texture a plain fill is drawn with

local C = Style.C -- (the active skin's, filled by Style.UseSkin)
local function paint(t, c, a) t:SetVertexColor(c[1], c[2], c[3], a or c[4] or 1) end
S.Paint = paint
-- a plain fill (a wash, a stripe, a line): placed and painted by the caller (Style.Paint)
function S.Fill(parent, layer, sub)
  local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
  t:SetTexture(Style.skin.FLAT)
  return t
end

local fontPath = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local fonts = {}
function S.Font(size, flags, tiny)
  if not tiny and size < Style.MIN_FONT then size = Style.MIN_FONT end
  local key = size .. (flags or "")
  if not fonts[key] then
    local f = CreateFont("BeelineFont" .. key:gsub("%W", ""))
    f:SetFont(fontPath, size, flags or "")
    f:SetShadowOffset(1, -1); f:SetShadowColor(0, 0, 0, 0.8)
    fonts[key] = f
  end
  return fonts[key]
end
function S.Text(parent, size, color, flags, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  fs:SetFontObject(S.Font(size, flags))
  local c = color or S.C.text
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
  fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
  fs:SetWordWrap(true)
  return fs
end

-- 9-slice from a 64px rounded-rect texture: corners keep their curve at any size
function S.Nine(frame, tex, layer, sub, corner, inset, r, g, b, a)
  local parts = {}
  local c, t = corner or 12, 0.25
  local spec = {
    { "TOPLEFT", 0, t, 0, t }, { "TOP", t, 1 - t, 0, t }, { "TOPRIGHT", 1 - t, 1, 0, t },
    { "LEFT", 0, t, t, 1 - t }, { "CENTER", t, 1 - t, t, 1 - t }, { "RIGHT", 1 - t, 1, t, 1 - t },
    { "BOTTOMLEFT", 0, t, 1 - t, 1 }, { "BOTTOM", t, 1 - t, 1 - t, 1 }, { "BOTTOMRIGHT", 1 - t, 1, 1 - t, 1 },
  }
  local i = inset or 0
  for k, sp in ipairs(spec) do
    local x = frame:CreateTexture(nil, layer, nil, sub)
    x:SetTexture(MEDIA .. tex); x:SetTexCoord(sp[2], sp[3], sp[4], sp[5]); x:SetVertexColor(r, g, b, a)
    parts[k] = x
  end
  local TL, T, TR, L, C2, R, BL, B, BR = unpack(parts)
  TL:SetSize(c, c); TL:SetPoint("TOPLEFT", -i, i)
  TR:SetSize(c, c); TR:SetPoint("TOPRIGHT", i, i)
  BL:SetSize(c, c); BL:SetPoint("BOTTOMLEFT", -i, -i)
  BR:SetSize(c, c); BR:SetPoint("BOTTOMRIGHT", i, -i)
  T:SetPoint("TOPLEFT", TL, "TOPRIGHT"); T:SetPoint("BOTTOMRIGHT", TR, "BOTTOMLEFT")
  B:SetPoint("TOPLEFT", BL, "TOPRIGHT"); B:SetPoint("BOTTOMRIGHT", BR, "BOTTOMLEFT")
  L:SetPoint("TOPLEFT", TL, "BOTTOMLEFT"); L:SetPoint("BOTTOMRIGHT", BL, "TOPRIGHT")
  R:SetPoint("TOPLEFT", TR, "BOTTOMLEFT"); R:SetPoint("BOTTOMRIGHT", BR, "TOPRIGHT")
  C2:SetPoint("TOPLEFT", TL, "BOTTOMRIGHT"); C2:SetPoint("BOTTOMRIGHT", BR, "TOPLEFT")
  return parts
end

-- rounded panel: soft shadow, fill, hairline edge, faint top sheen
-- the card's own panel (a skin can give it a frame of its own)
function S.CardPanel(frame) S.Panel(frame) end
function S.Panel(frame, fill)
  local c = fill or C.bg
  Style.Nine(frame, "shadow", "BACKGROUND", -8, 22, 12, 0, 0, 0, 0.6)
  frame.fill = Style.Nine(frame, "panel", "BACKGROUND", -7, 12, 0, c[1], c[2], c[3], c[4])
  Style.Nine(frame, "panel-edge", "BORDER", 0, 12, 0, 1, 1, 1, 0.09)
  -- header band: a slightly lighter strip behind the title row
  local band = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
  band:SetTexture(WHITE); band:SetPoint("TOPLEFT", 4, -4); band:SetPoint("TOPRIGHT", -4, -4); band:SetHeight(26)
  band:SetVertexColor(1, 1, 1, 0.025)
end

-- a row's soft rounded fill (corner: its radius), c (default white) at alpha a; Style.SetRowBg repaints it
function S.RowBg(frame, corner, a, c)
  c = c or C.white
  return Style.Nine(frame, "panel", "BACKGROUND", 0, corner, 0, c[1], c[2], c[3], a)
end
function S.SetRowBg(parts, a, c)
  c = c or C.white
  for _, part in ipairs(parts) do part:SetVertexColor(c[1], c[2], c[3], a) end
end
-- a row's coloured stripe down its left side (w wide, x in, y from the top and bottom); the caller paints it
function S.RowEdge(parent, w, x, y)
  local e = Style.Fill(parent, "ARTWORK")
  e:SetWidth(w); e:SetPoint("TOPLEFT", x, -y); e:SetPoint("BOTTOMLEFT", x, y)
  return e
end
-- the wash under the mouse: c (default white) at alpha a, inset px in from the edges
function S.Highlight(parent, a, c, inset)
  local hl = Style.Fill(parent, "HIGHLIGHT")
  if inset then hl:SetPoint("TOPLEFT", inset, -inset); hl:SetPoint("BOTTOMRIGHT", -inset, inset) else hl:SetAllPoints() end
  paint(hl, c or C.white, a)
  return hl
end
-- a thin line (the caller sizes and places it): c (default white) at alpha a
function S.Divider(parent, a, c, layer)
  local t = Style.Fill(parent, layer or "ARTWORK")
  paint(t, c or C.white, a)
  return t
end
-- a small round dot
function S.Dot(parent, size, layer)
  local d = parent:CreateTexture(nil, layer or "OVERLAY")
  d:SetTexture(MEDIA .. "dot"); d:SetSize(size, size)
  return d
end
-- one of our glyphs on a texture; Style.GlyphTag: the same inline in text
function S.Glyph(tex, name) tex:SetTexture(MEDIA .. name) end
function S.GlyphTag(name, size) return "|T" .. MEDIA .. name .. ":" .. size .. "|t" end
-- a tab rail's backing (alpha a; flat: no edge line, where a skin draws one)
function S.RailBg(rail, a, flat)
  local t = Style.Fill(rail, "BACKGROUND"); t:SetAllPoints()
  paint(t, C.black, a)
  return t
end
-- the card's progress line: on frame prog (Style.M.progH tall), a track and a gold fill; returns the fill
function S.Progress(prog)
  local bg = Style.Fill(prog, "BACKGROUND"); bg:SetAllPoints(); paint(bg, C.white, 0.06)
  local fill = Style.Fill(prog, "ARTWORK"); fill:SetPoint("TOPLEFT"); fill:SetPoint("BOTTOMLEFT")
  paint(fill, C.gold, 0.9)
  return fill
end
-- a slim scrollbar drawn beside a list: track and thumb, w wide (the track at alpha a)
function S.ScrollTrack(parent, w, a)
  local track = Style.Fill(parent, "ARTWORK"); paint(track, C.white, a); track:SetWidth(w)
  local thumb = Style.Fill(parent, "OVERLAY"); paint(thumb, C.gold, 0.6); thumb:SetWidth(w)
  return track, thumb
end
-- the item button's slot: a dark square and a light wash under the mouse
function S.ItemSlot(b)
  local bg = Style.Fill(b, "BACKGROUND"); bg:SetAllPoints(); paint(bg, C.black, 0.8)
  Style.Highlight(b, 0.15)
end
-- the Options toggle's box on row b (wash on hover, ring, tick); Style.PaintCheck(b, on) shows the state
function S.Check(b)
  b.wash = Style.Fill(b, "BACKGROUND"); b.wash:SetAllPoints(); paint(b.wash, C.white, 0.06); b.wash:Hide()
  b.box = b:CreateTexture(nil, "ARTWORK"); b.box:SetTexture(MEDIA .. "ring"); b.box:SetSize(16, 16); b.box:SetPoint("LEFT", 4, 0)
  b.tick = b:CreateTexture(nil, "OVERLAY"); b.tick:SetTexture(MEDIA .. "icon-check"); b.tick:SetSize(14, 14); b.tick:SetPoint("CENTER", b.box, "CENTER", 0, 0)
  paint(b.tick, C.good)
  b:SetScript("OnEnter", function(self) self.wash:Show() end)
  b:SetScript("OnLeave", function(self) self.wash:Hide() end)
end
function S.PaintCheck(b, on)
  b.tick:SetShown(on)
  paint(b.box, on and C.good or C.dim)
end

-- The card's step mark: cur.accent (a stripe at the card's left, pad = the card's margin), cur.halo, cur.disc,
-- cur.icon (the kind's glyph on the disc), cur.check (the step-done pop). Style.PaintMark colours it.
function S.StepMark(f, cur, pad)
  cur.accent = Style.Fill(f, "ARTWORK"); cur.accent:SetWidth(3)
  cur.accent:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -40); cur.accent:SetPoint("BOTTOMLEFT", cur, "BOTTOMLEFT", -pad, 0)
  cur.halo = cur:CreateTexture(nil, "ARTWORK", nil, 0); cur.halo:SetTexture(MEDIA .. "glow"); cur.halo:SetSize(66, 66)
  cur.disc = cur:CreateTexture(nil, "ARTWORK", nil, 1); cur.disc:SetTexture(MEDIA .. "disc"); cur.disc:SetSize(38, 38); cur.disc:SetPoint("TOPLEFT", 0, 0)
  cur.halo:SetPoint("CENTER", cur.disc)
  cur.icon = cur:CreateTexture(nil, "ARTWORK", nil, 2); cur.icon:SetSize(22, 22); cur.icon:SetPoint("CENTER", cur.disc); paint(cur.icon, C.glyphOnDisc)
  cur.check = cur:CreateTexture(nil, "OVERLAY"); cur.check:SetTexture(MEDIA .. "icon-check"); cur.check:SetSize(30, 30); cur.check:SetPoint("CENTER", cur.disc)
  paint(cur.check, C.good); cur.check:SetAlpha(0)
end
-- color: the step's colour; glyph: our glyph's name; kind: its Style.KIND entry when it is a step's own mark
function S.PaintMark(cur, color, glyph)
  cur.disc:SetVertexColor(color[1], color[2], color[3]); cur.halo:SetVertexColor(color[1], color[2], color[3], 0.35)
  cur.accent:SetVertexColor(color[1], color[2], color[3], 0.9); cur.icon:SetTexture(MEDIA .. glyph)
end
-- a route list row's mark: the kind's glyph in its colour, or a faded tick when done
function S.ListMark(tex, kind, done)
  tex:SetTexture(MEDIA .. (done and "icon-check" or kind.icon))
  if done then paint(tex, C.good, 0.6) else paint(tex, kind.color) end
end

-- square icon button (tinted glyph, hover glow, tooltip)
-- tip: one line, or { title, line, line... }: a white title with what the button does under it
-- color: the glyph's colour at rest (default: the secondary text colour) - a red X reads as "no" before any tooltip
function S.IconButton(parent, glyph, size, onClick, tip, color)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetTexture(MEDIA .. "disc"); b.bg:SetAllPoints(); b.bg:SetVertexColor(1, 1, 1, 0.06)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetTexture(MEDIA .. glyph); b.icon:SetPoint("CENTER"); b.icon:SetSize(size * 0.55, size * 0.55)
  local rest = color or C.sub
  b.rest = rest
  b.icon:SetVertexColor(rest[1], rest[2], rest[3])
  b.tip = tip
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(self)
    self.bg:SetVertexColor(1, 0.82, 0.36, 0.22); self.icon:SetVertexColor(1, 0.9, 0.6)
    Style.ShowTip(self, self.tip)
    if parent.OnChildEnter then parent:OnChildEnter() end
  end)
  b:SetScript("OnLeave", function(self) self.bg:SetVertexColor(1, 1, 1, 0.06); self.icon:SetVertexColor(rest[1], rest[2], rest[3]); GameTooltip:Hide() end)
  return b
end
-- a tooltip above owner: one line, or { title, line, line... }
function S.ShowTip(owner, t)
  if type(t) == "table" then
    GameTooltip:SetOwner(owner, "ANCHOR_TOP"); GameTooltip:SetText(t[1], 1, 1, 1, 1, true)
    for k = 2, #t do GameTooltip:AddLine(t[k], 0.75, 0.8, 0.88, true) end
    GameTooltip:Show()
  elseif t then GameTooltip:SetOwner(owner, "ANCHOR_TOP"); GameTooltip:SetText(t, 1, 1, 1, 1, true); GameTooltip:Show() end
end

-- small flat button with hover highlight; rest: the label's colour off hover (default sub), size: its font size
function S.Button(parent, label, w, h, onClick, tip, rest, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetTexture(WHITE); bg:SetAllPoints(); bg:SetVertexColor(1, 1, 1, 0.05)
  local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetTexture(WHITE); hl:SetAllPoints(); hl:SetVertexColor(1, 0.82, 0.36, 0.14)
  b.label = Style.Text(b, 11, C.sub); b.label:SetPoint("CENTER"); b.label:SetJustifyH("CENTER"); b.label:SetText(label)
  if size then b.label:SetFontObject(Style.Font(size)) end
  b.rest = rest or C.sub
  if rest then b.label:SetTextColor(rest[1], rest[2], rest[3]) end
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 0.86, 0.5); if tip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(tip, 1, 1, 1, 1, true); GameTooltip:Show() end end)
  b:SetScript("OnLeave", function(self) local c = self.rest; self.label:SetTextColor(c[1], c[2], c[3]); GameTooltip:Hide() end)
  return b
end
-- the "x" that closes or dismisses (size: its side)
function S.XButton(parent, size, onClick, tip)
  return Style.Button(parent, "x", size, size, onClick, tip)
end

-- the slim bars under the card (what's new, a hint, a scale offer): a line of text and "x"; Style.CardBarButton adds
-- a button left of the "x". Style.StackCardBars stacks them
function S.CardBar(name, order, color, onX, xTip)
  local card = BeelineCard
  if not card then return nil end
  local b = CreateFrame("Frame", name, card)
  b:SetHeight(22)
  Style.Panel(b, C.bg2)
  b.text = Style.Text(b, 11, color); b.text:SetPoint("LEFT", 10, 0); b.text:SetWordWrap(false)
  b.x = Style.XButton(b, 18, onX, xTip); b.x:SetPoint("RIGHT", -3, 0)
  b.text:SetPoint("RIGHT", b.x, "LEFT", -6, 0)
  Style.cardBars[order] = b
  return b
end
function S.CardBarButton(b, label, w, onClick, tip)
  local go = Style.Button(b, label, w, 18, onClick, tip)
  go:SetPoint("RIGHT", b.x, "LEFT", -4, 0)
  b.text:SetPoint("RIGHT", go, "LEFT", -6, 0)
  return go
end

-- a window's tab rail: a tab button (t = { label, icon, color, tip? }), w wide, at y under the rail's top; b.on marks
-- the open one (then Style.PaintTab(b))
function S.PaintTab(b)
  local t = b.t
  local lit = b.on or b.hover
  local col = lit and t.color or C.sub
  b.icon:SetVertexColor(col[1], col[2], col[3]); b.icon:SetAlpha(lit and 1 or 0.65)
  b.label:SetTextColor(col[1], col[2], col[3])
  b.wash:SetVertexColor(t.color[1], t.color[2], t.color[3], 0.12); b.wash:SetShown(b.on)
  b.bar:SetVertexColor(t.color[1], t.color[2], t.color[3]); b.bar:SetShown(b.on)
end
function S.RailTab(rail, t, y, onClick, w)
  local b = CreateFrame("Button", nil, rail)
  b:SetSize(w, 48); b:SetPoint("TOP", rail, "TOP", 0, -y); b.t = t
  b.wash = Style.Fill(b, "BACKGROUND"); b.wash:SetAllPoints()
  b.bar = Style.Fill(b, "ARTWORK"); b.bar:SetWidth(3); b.bar:SetPoint("TOPLEFT", 0, -6); b.bar:SetPoint("BOTTOMLEFT", 0, 6)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetTexture(MEDIA .. t.icon); b.icon:SetSize(18, 18); b.icon:SetPoint("TOP", 0, -8)
  b.label = Style.Text(b, 10, C.sub); b.label:SetPoint("TOP", b.icon, "BOTTOM", 0, -4); b.label:SetJustifyH("CENTER"); b.label:SetText(t.label)
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(self)
    self.hover = true; Style.PaintTab(self)
    if t.tip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(t.tip, 1, 1, 1, 1, true); GameTooltip:Show() end
  end)
  b:SetScript("OnLeave", function(self) self.hover = false; Style.PaintTab(self); if t.tip then GameTooltip:Hide() end end)
  return b
end

-- A window's scrolling list: f.scroll (place it), f.content (contentW wide; set its height), a track and thumb (place
-- f.track beside the list) with a grip to drag, the mouse wheel (step: px a notch). Returns f.setScroll(v), which
-- clamps v and redraws the thumb; call it after a layout.
function S.ScrollList(f, contentW, step)
  f.scroll = CreateFrame("ScrollFrame", nil, f); f.scroll:EnableMouseWheel(true)
  f.content = CreateFrame("Frame", nil, f.scroll); f.content:SetSize(contentW, 10); f.scroll:SetScrollChild(f.content)
  f.track, f.thumb = Style.ScrollTrack(f, 4, 0.05)
  local function setScroll(v)
    local max = math.max(0, f.content:GetHeight() - f.scroll:GetHeight())
    v = math.max(0, math.min(max, v)); f.scroll:SetVerticalScroll(v)
    local th = f.track:GetHeight() or 0
    f.thumb:SetShown(max > 0); f.track:SetShown(max > 0); f.grip:SetShown(max > 0)
    if max > 0 and th > 0 then
      local h = math.max(20, th * f.scroll:GetHeight() / f.content:GetHeight())
      f.thumb:SetHeight(h); f.thumb:ClearAllPoints(); f.thumb:SetPoint("TOP", f.track, "TOP", 0, -(th - h) * v / max)
    end
  end
  f.setScroll = setScroll
  f.scroll:SetScript("OnMouseWheel", function(self, d) setScroll(self:GetVerticalScroll() - d * (step or 60)) end)
  f.grip = Style.ScrollGrip(f, f.track, f.thumb, function(fr) setScroll(fr * math.max(0, f.content:GetHeight() - f.scroll:GetHeight())) end)
  return setScroll
end

-- progress bar with label
S.BAR_TRACK = { tex = WHITE, a = 0.07 } -- the track's look (a skin with a stock bar overrides it)
S.BAR_FILL = WHITE
function S.Bar(parent, h)
  local A = Style.skin
  local f = CreateFrame("Frame", nil, parent); f:SetHeight(18)
  f.label = Style.Text(f, 10, C.text); f.label:SetPoint("TOPLEFT"); f.label:SetWordWrap(false); f.label:SetPoint("RIGHT", -48, 0)
  f.value = Style.Text(f, 10, C.sub); f.value:SetPoint("TOPRIGHT"); f.value:SetJustifyH("RIGHT")
  local track = CreateFrame("Frame", nil, f); track:SetPoint("BOTTOMLEFT"); track:SetPoint("BOTTOMRIGHT"); track:SetHeight(Style.M.barTrack)
  local bg = track:CreateTexture(nil, "BACKGROUND"); bg:SetTexture(A.BAR_TRACK.tex); bg:SetAllPoints(); paint(bg, A.BAR_TRACK.c or C.white, A.BAR_TRACK.a)
  local fill = track:CreateTexture(nil, "ARTWORK"); fill:SetTexture(A.BAR_FILL); fill:SetPoint("TOPLEFT"); fill:SetPoint("BOTTOMLEFT")
  fill:SetWidth(0.001); fill:Hide() -- empty until there is progress (a texture with no width would draw a default sliver)
  f.fill, f.track = fill, track
  if A.BarDress then A.BarDress(track) end
  function f:Set(p, color, label, value)
    p = math.max(0, math.min(1, p or 0))
    self.target = p
    if p <= 0 and (self.cur or 0) <= 0.004 then self.fill:Hide() end
    local done = p >= 1
    local c = done and C.good or color
    self.fill:SetVertexColor(c[1], c[2], c[3], 0.95)
    self.label:SetText(label or ""); self.value:SetText(done and "|cff5cdc7adone|r" or (value or ""))
    self.label:SetTextColor(done and 0.6 or 0.92, done and 0.65 or 0.93, done and 0.7 or 0.96)
    self:SetScript("OnUpdate", self.step) -- (it runs only while the fill moves toward its target)
  end
  function f.step(self, el)
    local w = self.track:GetWidth(); if w <= 0 then return end
    self.cur = self.cur or 0
    local t = self.target or 0
    if math.abs(t - self.cur) < 0.001 then self:SetScript("OnUpdate", nil); return end
    self.cur = self.cur + (t - self.cur) * math.min(1, el * 8)
    self.fill:SetWidth(math.max(0.001, w * self.cur))
    self.fill:SetShown(self.cur > 0.004)
  end
  return f
end

-- small rounded label ("FASTEST", "CURRENT")
function S.Pill(parent, text, color)
  local p = CreateFrame("Frame", nil, parent)
  p.bg = Style.Nine(p, "panel", "BACKGROUND", 0, 6, 0, color[1], color[2], color[3], 0.18)
  p.text = Style.Text(p, 9, color, "OUTLINE"); p.text:SetPoint("CENTER", 0, 0); p.text:SetJustifyH("CENTER"); p.text:SetWordWrap(false)
  function p:Set(t, c)
    c = c or color
    self.text:SetText(t); self.text:SetTextColor(c[1], c[2], c[3])
    for _, part in ipairs(self.bg or {}) do part:SetVertexColor(c[1], c[2], c[3], 0.18) end
    self:SetSize(self.text:GetStringWidth() + 12, 15)
  end
  p:Set(text, color)
  return p
end
-- zone chips flowing left to right with ">" between, wrapping at width; returns the height used
-- max (optional): only the first max zones, then "+N more zones" - the next few give the sense of a path; the ones
-- beyond are hours away, and the plan is rebuilt long before you get there
function S.Chips(holder, zones, width, max)
  holder.chips = holder.chips or {}
  for _, c in ipairs(holder.chips) do c:Hide(); c.sep:Hide() end
  if holder.more then holder.more:Hide() end
  local x, y, lineH, gap = 0, 0, 18, 4
  local more = (max and #zones > max) and (#zones - max) or 0
  for i, z in ipairs(zones) do
    if more > 0 and i > max then break end
    local c = holder.chips[i]
    if not c then
      c = CreateFrame("Frame", nil, holder)
      c.bg = Style.Nine(c, "panel", "BACKGROUND", 0, 6, 0, 1, 1, 1, 0.08)
      c.text = Style.Text(c, 10, C.text); c.text:SetPoint("CENTER", 0, 0); c.text:SetWordWrap(false)
      c.sep = Style.Text(holder, 10, C.dim); c.sep:SetText(">")
      holder.chips[i] = c
    end
    local col = Style.ZoneColor(z)
    c.text:SetText(Style.ShortZone(z)); c.text:SetTextColor(col[1], col[2], col[3])
    for _, part in ipairs(c.bg or {}) do part:SetVertexColor(col[1], col[2], col[3], 0.13) end
    local w = c.text:GetStringWidth() + 12
    c:SetSize(w, 16)
    local sepW = i > 1 and 12 or 0
    if x > 0 and x + sepW + w > width then x = 0; y = y + lineH + 2; sepW = 0 end
    if sepW > 0 then c.sep:ClearAllPoints(); c.sep:SetPoint("TOPLEFT", holder, "TOPLEFT", x + 2, -y - 2); c.sep:Show() end
    x = x + sepW
    c:ClearAllPoints(); c:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -y); c:Show()
    x = x + w + gap
  end
  if more > 0 then
    holder.more = holder.more or Style.Text(holder, 10, C.dim)
    holder.more:SetText("> +" .. more .. " more zone" .. (more == 1 and "" or "s"))
    local w = holder.more:GetStringWidth() + 4
    if x > 0 and x + w > width then x = 0; y = y + lineH + 2 end
    holder.more:ClearAllPoints(); holder.more:SetPoint("TOPLEFT", holder, "TOPLEFT", x + 2, -y - 2); holder.more:Show()
  end
  return y + lineH
end

-- The addon's windows (the Beeline window with its sidebar of views, news, options, the bug
-- report) share one shell: on the dialog layer, kept on screen, dragged anywhere, the skin's panel and the scale,
-- Escape closes it. Style.Window(f, name) gives frame f that shell; name is its global name (Escape closes it through
-- UISpecialFrames). Style.WindowTitle: its title; Style.CloseButton(f): the close button at the top right.
function S.Window(f, name)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  Style.Panel(f, C.bg2); Style.Scaled(f, nil, true)
  if name then table.insert(UISpecialFrames, name) end -- Escape closes it
  return f
end
-- the window's title (size: its font size), at x, y from its top left
function S.WindowTitle(f, size, x, y)
  local t = Style.Text(f, size, C.gold, "OUTLINE"); t:SetPoint("TOPLEFT", x, y)
  return t
end
function S.CloseButton(f)
  local close = Style.XButton(f, 18, function() f:Hide() end, "Close")
  close:SetPoint("TOPRIGHT", -8, -8)
  return close
end
-- a corner grip to resize a window from (the game's own chat grip art, in every skin)
function S.SizeGrip(parent, name)
  local grip = CreateFrame("Button", name, parent)
  grip:SetSize(14, 14); grip:SetPoint("BOTTOMRIGHT", -3, 3)
  local g = grip:CreateTexture(nil, "OVERLAY"); g:SetAllPoints(); g:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  return grip
end

-- (everything exists from load on; ADDON_LOADED picks the saved skin before any frame is built: Core.lua)
Style.UseSkin("beeline")

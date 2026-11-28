-- The Blizzard skin: the stock game look. The game's metal frame with its title strip (the bags' and settings' look)
-- for the card and the windows, with the red close button; tooltip backdrops for the card's bars, red panel buttons, check boxes, the game's fonts and their gold and white,
-- a stock status bar, and the game's quest marks on the card. What it leaves out comes from the Beeline skin.
-- Every texture and template named here is the client's own (Interface files, FrameXML templates).
local _, ns = ...
local Style = ns.Style
local Bee = Style.Skins.beeline
local MEDIA = Style.MEDIA
local B = setmetatable({ name = "blizzard" }, { __index = Bee })
Style.Skins.blizzard = B

B.C = {
  gold = { 1, 0.82, 0 }, text = { 1, 1, 1 }, sub = { 1, 0.82, 0 }, dim = { 0.62, 0.62, 0.62 },
  good = { 0.1, 1, 0.1 }, warn = { 1, 0.5, 0.25 }, bad = { 1, 0.1, 0.1 },
  line = { 0.42, 0.32, 0.13 }, -- the dialog border's bronze, for dividers
}
B.M = {
  progH = 6,      -- the card's progress bar
  barTrack = 6,   -- an objective bar
  chromeOut = 2,  -- the stock frame's border, just past a window's sides and bottom
  chromeTop = 21, -- and its title strip, above the window
  cardHeadY = 6,  -- the card's header, up on the strip
  btnMinH = 18,   -- under this a button is a flat text link (the panel button's art needs the height)
}
B.FLAT = "Interface\\Buttons\\WHITE8X8"
B.BAR_TRACK = { tex = B.FLAT, c = { 0, 0, 0 }, a = 0.6 }
B.BAR_FILL = "Interface\\TargetingFrame\\UI-StatusBar"
local FULL = { 0, 1, 0, 1 }
local ICON = { 0.08, 0.92, 0.08, 0.92 } -- (an item icon without its border)
-- the step marks the game has art for; the other kinds keep our glyph, in gold
B.MARK = {
  accept = { tex = "Interface\\GossipFrame\\AvailableQuestIcon", coords = FULL },
  turnin = { tex = "Interface\\GossipFrame\\ActiveQuestIcon", coords = FULL },
  fly = { tex = "Interface\\Minimap\\Tracking\\FlightMaster", coords = FULL },
  fp = { tex = "Interface\\Minimap\\Tracking\\FlightMaster", coords = FULL },
  hearth = { tex = "Interface\\Icons\\INV_Misc_Rune_01", coords = ICON },
  bind = { tex = "Interface\\Icons\\INV_Misc_Rune_01", coords = ICON },
  train = { tex = "Interface\\Minimap\\Tracking\\Class", coords = FULL },
}
local TIP_BACKDROP = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local C = Style.C
local paint = Bee.Paint
local function rgb(c, d) if type(c) == "table" and c.r then return { c.r, c.g, c.b } end return d end
local function fontRGB(obj, d)
  if obj and obj.GetTextColor then local r, g, b = obj:GetTextColor(); if r then return { r, g, b } end end
  return d
end
-- the game's own colours, read once the game's fonts exist (Style.UseSkin)
function B.Prepare()
  B.C.gold = fontRGB(GameFontNormal, B.C.gold); B.C.sub = B.C.gold
  B.C.text = fontRGB(GameFontHighlight, B.C.text)
  B.C.good = fontRGB(GameFontGreen, B.C.good); B.C.bad = fontRGB(GameFontRed, B.C.bad)
  B.tipBg = rgb(TOOLTIP_DEFAULT_BACKGROUND_COLOR, { 0.09, 0.09, 0.19 })
  B.tipEdge = rgb(TOOLTIP_DEFAULT_COLOR, { 1, 1, 1 })
end

-- fonts: the game's GameFontNormal at our sizes (its face and shadow)
local fonts = {}
function B.Font(size, flags, tiny)
  if not tiny and size < Style.MIN_FONT then size = Style.MIN_FONT end
  local key = size .. (flags or "")
  if not fonts[key] then
    local f = CreateFont("BeelineBzFont" .. key:gsub("%W", ""))
    local base = GameFontNormal
    if base and f.CopyFontObject then f:CopyFontObject(base) end
    local path = base and base:GetFont() or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    f:SetFont(path, size, flags or "")
    if not (base and f.CopyFontObject) then f:SetShadowOffset(1, -1); f:SetShadowColor(0, 0, 0, 1) end
    fonts[key] = f
  end
  return fonts[key]
end
function B.Text(parent, size, color, flags, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  fs:SetFontObject(B.Font(size, flags))
  local c = color or C.text
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
  fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
  fs:SetWordWrap(true)
  return fs
end

local function backdrop(frame, info)
  if not frame.SetBackdrop then
    Mixin(frame, BackdropTemplateMixin)
    frame:HookScript("OnSizeChanged", frame.OnBackdropSizeChanged)
  end
  frame:SetBackdrop(info)
end
-- the card, its bars, the zones panel, a toast: a tooltip's backdrop
function B.Panel(frame)
  backdrop(frame, TIP_BACKDROP)
  local bg, e = B.tipBg or { 0.09, 0.09, 0.19 }, B.tipEdge or { 1, 1, 1 }
  frame:SetBackdropColor(bg[1], bg[2], bg[3], 0.92); frame:SetBackdropBorderColor(e[1], e[2], e[3], 1)
end

-- The stock frame (the bags', the settings', the add-on list's: FrameXML's DefaultPanelFlatTemplate). The game builds it
-- from NineSliceUtil's "ButtonFrameTemplateNoPortrait" layout (the metal border; the top edge is the title strip) over
-- FlatPanelBackgroundTemplate's fill. Here both are drawn on the frame itself, on its lowest layers: the fill on
-- BACKGROUND, the border on BORDER (NineSliceUtil's layoutTextureLayer). Everything the frame draws (its ARTWORK and
-- OVERLAY, every child frame) is then above them, and they hide, fade and scale with it. (Frames of their own would not
-- do: the client keeps a child frame above its parent, so a fill frame lands over the window's content.)
-- top: how far the strip reaches above f (0: the strip is f's own top); side: how far the border reaches past f's sides
local function stockLayout(top, side)
  local src, t = NineSliceUtil.GetLayout("ButtonFrameTemplateNoPortrait"), {}
  for k, v in pairs(src) do
    if type(v) == "table" then local p = {}; for a, b in pairs(v) do p[a] = b end; t[k] = p else t[k] = v end
  end
  local function move(k, dx, dy) t[k].x = (t[k].x or 0) + dx; t[k].y = (t[k].y or 0) + dy end
  move("TopLeftCorner", -side, top); move("TopRightCorner", side, top)
  move("BottomLeftCorner", -side, -side); move("BottomRightCorner", side, -side)
  return t
end
local function stockFrame(f, top, side)
  -- the fill (FlatPanelBackgroundTemplate's pieces, from 20 under the strip's top to the border's inside)
  local c = PANEL_BACKGROUND_COLOR
  local r, g, b, a = 0.15, 0.15, 0.15, 1
  if c and c.GetRGBA then r, g, b, a = c:GetRGBA() end
  local bl = f:CreateTexture(nil, "BACKGROUND", nil, -8); bl:SetAtlas("uiframebackground-nineslice-cornerbottomleft", true)
  bl:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -side + 2, -side + 3); bl:SetVertexColor(r, g, b, a)
  local br = f:CreateTexture(nil, "BACKGROUND", nil, -8); br:SetAtlas("uiframebackground-nineslice-cornerbottomright", true)
  br:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", side - 2, -side + 3); br:SetVertexColor(r, g, b, a)
  local be = f:CreateTexture(nil, "BACKGROUND", nil, -8); be:SetColorTexture(r, g, b, a)
  be:SetPoint("TOPLEFT", bl, "TOPRIGHT"); be:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
  local ts = f:CreateTexture(nil, "BACKGROUND", nil, -8); ts:SetColorTexture(r, g, b, a)
  ts:SetPoint("TOPLEFT", f, "TOPLEFT", -side + 2, top - 20); ts:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
  f.stockFill = ts
  -- the border, NineSliceUtil's own pieces on f
  f.layoutTextureLayer = "BORDER"
  NineSliceUtil.ApplyLayout(f, stockLayout(top, side))
end

-- the card: the stock frame, its header on the strip (Style.M.cardHeadY lifts it there)
function B.CardPanel(f)
  stockFrame(f, 0, 0)
end

-- a window: the stock frame, its title strip above the window (Style.M.chromeTop) so what the window lays out keeps
-- clear of it, the border just past its sides (Style.M.chromeOut)
function B.Window(f, name)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  local o, top = Style.M.chromeOut, Style.M.chromeTop
  stockFrame(f, top, o)
  -- the strip drags the window too (it is outside the window's own area)
  local grab = CreateFrame("Frame", nil, f)
  grab:SetPoint("TOPLEFT", f, "TOPLEFT", -o, top); grab:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", o - 26, 0)
  grab:EnableMouse(true); grab:RegisterForDrag("LeftButton")
  grab:SetScript("OnDragStart", function() f:StartMoving() end); grab:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
  f:SetClampRectInsets(-o, o, top, -o)
  Style.Scaled(f, nil, true)
  if name then table.insert(UISpecialFrames, name) end
  return f
end
-- the title, centred on the strip in the game's gold, as the template's TitleText (GameFontNormal, 5 under the top)
function B.WindowTitle(f)
  local o, top = Style.M.chromeOut, Style.M.chromeTop
  local t = f:CreateFontString(nil, "OVERLAY")
  t:SetFontObject(GameFontNormal or B.Font(12)); t:SetWordWrap(false)
  t:SetPoint("TOP", f, "TOP", 0, top - 5)
  t:SetPoint("LEFT", f, "LEFT", 30 - o, 0); t:SetPoint("RIGHT", f, "RIGHT", o - 30, 0)
  return t
end
-- the red close button in the strip's corner, where UIPanelCloseButtonDefaultAnchors puts it
function B.CloseButton(f)
  local o, top = Style.M.chromeOut, Style.M.chromeTop
  local close = Style.XButton(f, 20, function() f:Hide() end, "Close")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", o + 1, top)
  return close
end
function B.XButton(parent, size, onClick, tip)
  local b = CreateFrame("Button", nil, parent, "UIPanelCloseButton")
  b:SetSize(size + 4, size + 4)
  b:SetScript("OnClick", onClick)
  if tip then
    b:SetScript("OnEnter", function(self) Style.ShowTip(self, tip) end)
    b:SetScript("OnLeave", GameTooltip_Hide)
  end
  return b
end

-- the red panel button; under Style.M.btnMinH tall, a flat link (the panel art needs the height)
function B.Button(parent, label, w, h, onClick, tip, rest, size)
  if h < Style.M.btnMinH then return Bee.Button(parent, label, w, h, onClick, tip, rest, size) end
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetText(label); b:SetSize(w, h)
  b.label = b:GetFontString()
  b.rest = rest or C.sub
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(self) if tip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(tip, 1, 1, 1, 1, true); GameTooltip:Show() end end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

-- a square action-slot button: the slot art, our glyph in gold, the square highlight
function B.IconButton(parent, glyph, size, onClick, tip, color)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetTexture("Interface\\Buttons\\UI-Quickslot2"); b.bg:SetPoint("CENTER"); b.bg:SetSize(size * 1.8, size * 1.8)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetTexture(MEDIA .. glyph); b.icon:SetPoint("CENTER"); b.icon:SetSize(size * 0.55, size * 0.55)
  local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square"); hl:SetBlendMode("ADD"); hl:SetAllPoints()
  local rest = color or C.sub
  b.rest = rest
  paint(b.icon, rest)
  b.tip = tip
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(self)
    paint(self.icon, C.text)
    Style.ShowTip(self, self.tip)
    if parent.OnChildEnter then parent:OnChildEnter() end
  end)
  b:SetScript("OnLeave", function(self) paint(self.icon, rest); GameTooltip:Hide() end)
  return b
end
function B.ItemSlot(b)
  local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetTexture("Interface\\Buttons\\UI-Quickslot2"); bg:SetPoint("CENTER"); bg:SetSize(b:GetWidth() * 1.8, b:GetHeight() * 1.8)
  local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square"); hl:SetBlendMode("ADD"); hl:SetAllPoints()
end

-- a row stripe: the stock look has none (kept, unseen, for the code that paints it)
function B.RowEdge(parent, w, x, y)
  local e = Bee.RowEdge(parent, w, x, y)
  e:SetAlpha(0)
  return e
end
-- the quest log's title highlight under the mouse
function B.Highlight(parent, a, c, inset)
  local hl = parent:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight"); hl:SetBlendMode("ADD")
  if inset then hl:SetPoint("TOPLEFT", inset, -inset); hl:SetPoint("BOTTOMRIGHT", -inset, inset) else hl:SetAllPoints() end
  paint(hl, c or C.gold, 0.5)
  return hl
end
function B.Divider(parent, a, c, layer)
  local t = Style.Fill(parent, layer or "ARTWORK")
  paint(t, C.line, 0.9)
  return t
end
-- a small square dot (the stock lists' bullet look)
function B.Dot(parent, size, layer)
  local d = Style.Fill(parent, layer or "OVERLAY")
  d:SetSize(math.max(4, size - 3), math.max(4, size - 3))
  return d
end
-- (flat: a tint at alpha a and no edge line, as the card's side rail has)
function B.RailBg(rail, a, flat)
  local t = Style.Fill(rail, "BACKGROUND"); t:SetAllPoints(); paint(t, C.black, flat and a or 0.35)
  if flat then return t end
  local e = Style.Fill(rail, "BORDER"); e:SetWidth(1); e:SetPoint("TOPRIGHT"); e:SetPoint("BOTTOMRIGHT"); paint(e, C.line, 0.9)
  return t
end
function B.Progress(prog)
  local bg = Style.Fill(prog, "BACKGROUND"); bg:SetAllPoints(); paint(bg, C.black, 0.6)
  local fill = prog:CreateTexture(nil, "ARTWORK"); fill:SetTexture(B.BAR_FILL); fill:SetPoint("TOPLEFT"); fill:SetPoint("BOTTOMLEFT")
  paint(fill, C.good, 0.95)
  return fill
end
function B.ScrollTrack(parent, w, a)
  local track = Style.Fill(parent, "ARTWORK"); paint(track, C.black, 0.4); track:SetWidth(w)
  local thumb = Style.Fill(parent, "OVERLAY"); paint(thumb, C.gold, 0.8); thumb:SetWidth(w)
  return track, thumb
end

-- the Options toggle: the game's check box (the whole row stays the button)
function B.Check(b)
  b.box = CreateFrame("CheckButton", nil, b, "UICheckButtonTemplate")
  b.box:SetSize(24, 24); b.box:SetPoint("LEFT", 0, 0); b.box:EnableMouse(false)
  Style.Highlight(b)
end
function B.PaintCheck(b, on) b.box:SetChecked(on) end

-- the card's mark: no disc, stripe or halo; the game's quest mark (or our glyph in gold), bigger
function B.StepMark(f, cur, pad)
  Bee.StepMark(f, cur, pad)
  cur.accent:SetAlpha(0); cur.halo:SetAlpha(0); cur.disc:SetAlpha(0)
  cur.icon:SetSize(30, 30)
end
local function mark(tex, m, glyph, c, a)
  if m then tex:SetTexture(m.tex); tex:SetTexCoord(m.coords[1], m.coords[2], m.coords[3], m.coords[4]); tex:SetVertexColor(1, 1, 1)
  else tex:SetTexture(MEDIA .. glyph); tex:SetTexCoord(0, 1, 0, 1); paint(tex, c, a) end
end
-- (a done mark stays green)
function B.PaintMark(cur, color, glyph, kind)
  mark(cur.icon, kind and kind.mark, glyph, color == C.good and C.good or C.gold)
end
function B.ListMark(tex, kind, done)
  if done then mark(tex, nil, "icon-check", C.good, 0.6) else mark(tex, kind.mark, kind.icon, C.gold) end
end

-- rail tabs: gold, the open one white
function B.PaintTab(b)
  local lit = b.on or b.hover
  local col = b.on and C.text or C.gold
  b.icon:SetVertexColor(col[1], col[2], col[3]); b.icon:SetAlpha(lit and 1 or 0.8)
  b.label:SetTextColor(col[1], col[2], col[3])
  paint(b.wash, C.gold, 0.1); b.wash:SetShown(b.on)
  b.bar:SetShown(false)
end

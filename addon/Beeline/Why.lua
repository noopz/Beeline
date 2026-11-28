-- The decision log: every time the card shows something new or the route changes on its own, why. Kept in
-- BeelineDB.why (the last 300, shared by your characters) so the planner side can read it from your saves too.
-- /bee why prints the last few in chat.
local _, ns = ...
local MAX = 300

local function store()
  if type(BeelineDB.why) ~= "table" then BeelineDB.why = {} end
  return BeelineDB.why
end

-- How long the same line is not logged again, by kind (seconds; default 120). The checks that come back every two
-- minutes - a side quest not offered, a quest your skills keep from you, the flight points, an insert - say nothing new
-- until the route changes (FR_ROUTE_CHANGED) or WHY_ROUTE_FOR passes: 58% of a report's last 30 lines were repeats of an
-- earlier line (3.3.0 reports), and the report only carries the last 30. A repeat is not a new line but counted on
-- the one logged (n, t2: shown as "(xN)" in /bee why and /bee report). The same line as the last of its kind is
-- always counted, never logged again (a "next" decision re-made every two minutes is one line). Either only while
-- that line is among the last WHY_RECENT (a report's full count): older, the repeat is a line again, so a report shows it.
ns.WHY_RECENT = 30
ns.WHY_ROUTE_FOR = 6 * 3600
local ROUTE = "route"
ns.WHY_WINDOW = { side = ROUTE, avail = ROUTE, taxi = ROUTE, insert = ROUTE, merge = ROUTE }
-- what makes two lines the same, by kind: an insert is keyed on what was added, not on where (its step number shifts
-- with every change before it, and at login the same inserts came back at other numbers)
local NORM = { insert = function(x) return (x:gsub(" as step %d+", "")) end }
local function keyOf(kind, text) local f = NORM[kind]; return kind .. ":" .. (f and f(text) or text) end

local last, lastOf, seeded, count = {}, {}, nil, 0 -- [key] = { t =, e = the entry, k = kind, s = its number }; [kind] = its last entry
-- (from the log as saved: a login or /reload does not log the same lines again)
local function seed(w)
  if seeded == w then return end
  seeded, last, lastOf, count = w, {}, {}, #w
  for i, e in ipairs(w) do
    if type(e) == "table" and e.k and e.x then
      last[keyOf(e.k, e.x)] = { t = e.t2 or e.t or 0, e = e, k = e.k, s = i }
      lastOf[e.k] = e
    end
  end
end
local function windowOf(kind) local v = ns.WHY_WINDOW[kind]; if v == ROUTE then return ns.WHY_ROUTE_FOR end; return v or 120 end
function ns.WhyRouteChanged()
  for key, r in pairs(last) do if ns.WHY_WINDOW[r.k] == ROUTE then last[key] = nil end end
end
ns.On("FR_ROUTE_CHANGED", ns.WhyRouteChanged)
-- kind: short category ("card", "reorder", "insert", "path", "ready", ...); text: what and why
function ns.Why(kind, text)
  if not text then return end
  local w = store()
  seed(w)
  local key = keyOf(kind, text)
  local now = time()
  local r = last[key]
  local prev = lastOf[kind]
  -- the same again: counted on the line already logged (while it is still in the log)
  if r and not r.e.gone and count - r.s < ns.WHY_RECENT and (prev == r.e and prev.x == text or now - r.t < windowOf(kind)) then
    r.e.n = (r.e.n or 1) + 1; r.e.t2 = now; r.t = now
    return
  end
  local m = ns.State and ns.State.Position and ns.State.Position()
  local e = { t = now, k = kind, x = text, lv = UnitLevel and UnitLevel("player") or nil, m = m }
  w[#w + 1] = e
  count = count + 1
  last[key] = { t = now, e = e, k = kind, s = count }
  lastOf[kind] = e
  while #w > MAX do local gone = table.remove(w, 1); if type(gone) == "table" then gone.gone = true end end
end
-- a line's text with how many times it was seen, when more than once
function ns.WhyText(e, max)
  local x = tostring(e.x or "")
  local n = tonumber(e.n)
  local tail = n and n > 1 and (" (x" .. n .. ")") or ""
  if max and #x + #tail > max then x = x:sub(1, math.max(0, max - #tail)) end
  return x .. tail
end

function ns.WhyPrint(n)
  local w = store()
  n = n or 10
  if #w == 0 then ns.Print("Nothing logged yet."); return end
  ns.Print("Last " .. math.min(n, #w) .. " decisions (newest last):")
  for k = math.max(1, #w - n + 1), #w do
    local e = w[k]
    print(string.format("  |cff8a93a6%s|r  |cffffd25a%s|r  %s", date("%H:%M", e.t), e.k, ns.WhyText(e)))
  end
end

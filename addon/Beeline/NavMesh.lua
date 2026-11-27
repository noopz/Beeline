-- The map line on a navigation mesh (the "Detailed map line" option, off by default: Nav.MeshOn in Nav.lua). Instead
-- of one byte per 8-yard square, a zone is convex polygons baked from the planner's 2-yard walk map (tools/navmesh.js):
-- walls and cliffs are polygon edges, so the line can't cut through them. A* runs over the polygons from the target back
-- to you (as Nav.Search does over squares, so straying reads the way off the same search), then the funnel pulls the line
-- tight through the portals between them: straight runs that turn only at the corners they must go round.
-- Same calls as the grid's (Nav.Grid / Nav.Search / Nav.Run / Nav.Path dispatch here for a mesh), same line out.
-- Data: BeelineNavMesh[uiMap], one file a zone in its continent's load-on-demand addon (Beeline_MeshEK,
-- Beeline_MeshKalimdor), only for the zones that pass the audit (Nav/MeshIndex.lua, written by tools/navmesh.js ship).
-- Unpacked, a zone is strings, not tables of numbers: a polygon is 9 bytes, an edge 9 (its first corner and the polygon
-- across it), read with string.byte - about a fifth of the memory Lua tables of numbers would take.
-- Design and numbers: docs/research/navigation-mesh.md.
local _, ns = ...
local Mesh = {}
ns.NavMesh = Mesh
local byte, sub, char, concat = string.byte, string.sub, string.char, table.concat
local floor, sqrt, abs, huge = math.floor, math.sqrt, math.abs, math.huge

Mesh.MAPS = BeelineMeshIndex or {} -- uiMap -> the addon with its mesh: the zones that pass the audit (Nav/MeshIndex.lua)
Mesh.COST = { [0] = 1, [1] = 1.5, [2] = 0.9 } -- a yard of ground / water / road (tools/navmesh.js AREA_COST)
Mesh.BUCKET = 64  -- yards: the grid that finds the polygons at a point
Mesh.SNAP = 24    -- you (or the target) may be this far from the nearest polygon
Mesh.LEVEL = 8    -- with no height: other levels (polygons of another height) within this many yards count too
Mesh.Z_SNAP = 4   -- heights within this many yards are one level
local RP = 128    -- polygons a chunk: their records in one string, their edges in another (short strings: the
                  -- simulator's string.byte costs by the string's length)
Mesh.RP = RP

local clock = debugprofilestop or function() return GetTime() * 1000 end

-- the 85 characters of the packed text -> 0..84 (tools/navgrid.js ALPHA)
local V = {}
do
  local A = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$&()*+,-./:;<=>?@_{}~"
  for i = 1, #A do V[byte(A, i)] = i - 1 end
end
-- a reader over a packed string: a number is digits, low first; a digit under t ends it, one of t or more (85 - t
-- values) has more to come (tools/navmesh.js enc)
local function reader(s, t)
  t = t or 42
  local p, c = 1, 85 - t
  local function num()
    local n, m = 0, 1
    while true do
      local d = V[byte(s, p)]; p = p + 1
      if d >= t then n = n + (d - t) * m; m = m * c else return n + d * m end
    end
  end
  local function more() return p <= #s end
  return num, more
end
local function unzz(n) if n % 2 == 0 then return n / 2 end return -(n + 1) / 2 end
-- a number under 65536 as two bytes, low first
local function u16(n) return n % 256, floor(n / 256) end
-- The off-mesh links in a packed string (tools/navmesh.js pack: from polygon, to polygon as a step from it, kind - 1
-- both ways, 2 both ends at one spot - the from point and its height, the to point unless at the same spot, its height,
-- yards), each given to into(polygon it comes into, { from, fx, fy, fz, to, tx, ty, tz, cost }) - the search runs
-- backwards. -> how many
local function readLinks(N, text, into)
  local num, more = reader(text or "")
  local left, top, unit, zmin = N.left, N.top, N.unit, N.zmin
  local n = 0
  while more() do
    local a = num() + 1; local b = a + unzz(num()); local kind = num()
    local ax, ay = num(), num(); local az = num() / 2 + zmin
    local bx, by = ax, ay
    if kind % 4 < 2 then bx, by = num(), num() end
    local bz = num() / 2 + zmin; local cost = num()
    local wax, way, wbx, wby = left - ax * unit, top - ay * unit, left - bx * unit, top - by * unit
    into(b, { a, wax, way, az, b, wbx, wby, bz, cost })
    if kind % 2 == 1 then into(a, { b, wbx, wby, bz, a, wax, way, az, cost }) end
    n = n + 1
  end
  return n
end

-- Unpack a zone's mesh. Corners in half-floor units (tools/navmesh.js), heights in half yards above zmin. What stays:
--   PC[c]    the records of polygons c*RP+1 .. (c+1)*RP, 9 bytes each: where its edges start in EC[c] (2), corner count
--            * 4 + ground type (1), its lowest, middle and highest height (2 each)
--   EC[c]    their edges in order, 9 bytes each: the edge's first corner x, y, z (2 each), the polygon across it (3; 0 a wall)
--   buckets  polygon numbers (3 bytes each) by Mesh.BUCKET-yard square of their box
--   inc      the off-mesh links into each polygon (the search runs backwards)
-- pause (optional) spreads the work over frames.
function Mesh.Unpack(D, pause)
  local T0 = clock()
  -- (cell: what the arrow reads off a line - a city's 4-yd squares, open country's 8: UI/Arrow.lua lookFor, openCountry)
  local N = { mesh = true, left = D.left, top = D.top, right = D.right, bottom = D.bottom, inst = D.inst, cell = D.city and 4 or 8,
    unit = D.unit, zmin = D.zmin }
  local unit, left, top = D.unit, D.left, D.top
  local tv, tz, th, tr = D.tv or 42, D.tz or 42, D.th or 42, D.tr or 42
  local cv, cz, ch, cr = 85 - tv, 85 - tz, 85 - th, 85 - tr
  -- corners (decoded inline, not by a call each: this loop is most of the unpacking); kept only while unpacking
  local vx, vy, vz = {}, {}, {}
  -- (string.byte on a long string costs by its length in the simulator: read a 4 KB window of it at a time; a record
  -- never runs past the window's 64 spare characters)
  local S0, P0 = D.verts, 1
  local s, p = sub(S0, 1, 4096 + 64), 1
  local x, y, zq = 0, 0, 0
  for i = 1, D.nv do
    if p > 4096 then P0 = P0 + p - 1; s = sub(S0, P0, P0 + 4096 + 63); p = 1 end
    local d = V[byte(s, p)]; p = p + 1
    local n, m = 0, 1
    while d >= tv do n = n + (d - tv) * m; m = m * cv; d = V[byte(s, p)]; p = p + 1 end
    n = n + d * m
    if n % 2 == 0 then x = x + n / 2 else x = x - (n + 1) / 2 end
    d = V[byte(s, p)]; p = p + 1; n, m = 0, 1
    while d >= tv do n = n + (d - tv) * m; m = m * cv; d = V[byte(s, p)]; p = p + 1 end
    n = n + d * m
    if n % 2 == 0 then y = y + n / 2 else y = y - (n + 1) / 2 end
    d = V[byte(s, p)]; p = p + 1; n, m = 0, 1
    while d >= tz do n = n + (d - tz) * m; m = m * cz; d = V[byte(s, p)]; p = p + 1 end
    n = n + d * m
    if n % 2 == 0 then zq = zq + n / 2 else zq = zq - (n + 1) / 2 end
    vx[i], vy[i], vz[i] = x, y, zq
    if pause and i % 512 == 0 then pause() end
  end
  local T1 = clock()
  -- polygons: pstart[q] .. pstart[q] + pn[q] - 1 index pv (corners) and pe (the polygon across each edge); kept only
  -- while unpacking
  local pstart, pn, parea, zlo, zmid, zhi, pv = {}, {}, {}, {}, {}, {}, {}
  S0, P0 = D.polys, 1
  s, p = sub(S0, 1, 4096 + 64), 1
  local nextV, k, lo0 = 1, 0, 0
  for q = 1, D.np do
    if p > 4096 then P0 = P0 + p - 1; s = sub(S0, P0, P0 + 4096 + 63); p = 1 end
    -- (a polygon: its corner count and ground, its three heights, its corners)
    local d = V[byte(s, p)]; p = p + 1
    local h, m = 0, 1
    while d >= th do h = h + (d - th) * m; m = m * ch; d = V[byte(s, p)]; p = p + 1 end
    h = h + d * m
    local cnt = floor(h / 3)
    parea[q] = h % 3
    -- (the lowest height from the polygon before's, the middle and the highest up from it)
    local z3
    for j = 1, 3 do
      d = V[byte(s, p)]; p = p + 1
      local n; n, m = 0, 1
      while d >= tz do n = n + (d - tz) * m; m = m * cz; d = V[byte(s, p)]; p = p + 1 end
      n = n + d * m
      if j == 1 then
        if n % 2 == 0 then z3 = lo0 + n / 2 else z3 = lo0 - (n + 1) / 2 end
        lo0 = z3; zlo[q] = z3
      elseif j == 2 then z3 = z3 + n; zmid[q] = z3
      else z3 = z3 + n; zhi[q] = z3 end
    end
    pstart[q], pn[q] = k + 1, cnt
    for _ = 1, cnt do
      d = V[byte(s, p)]; p = p + 1
      local r; r, m = 0, 1
      while d >= tr do r = r + (d - tr) * m; m = m * cr; d = V[byte(s, p)]; p = p + 1 end
      r = r + d * m
      k = k + 1
      if r == 0 then pv[k] = nextV; nextV = nextV + 1 else pv[k] = nextV - r end
    end
    if pause and q % 256 == 0 then pause() end
  end
  local T2 = clock()
  -- the polygon across each edge: the one with the same two corners the other way round (tools/navmesh.js deriveNei)
  local first, nxt, eP = {}, {}, {}
  for q = 1, D.np do
    for e = pstart[q], pstart[q] + pn[q] - 1 do
      local a = pv[e]
      nxt[e] = first[a]; first[a] = e; eP[e] = q
    end
    if pause and q % 512 == 0 then pause() end
  end
  local pe = {}
  for q = 1, D.np do
    local s0, n = pstart[q], pn[q]
    for e = s0, s0 + n - 1 do
      local a, b = pv[e], pv[e + 1 <= s0 + n - 1 and e + 1 or s0]
      local o = 0
      local x2 = first[b]
      while x2 do
        local w = eP[x2]
        if w ~= q then
          local os, on = pstart[w], pn[w]
          if pv[x2 + 1 <= os + on - 1 and x2 + 1 or os] == a then o = w; break end
        end
        x2 = nxt[x2]
      end
      pe[e] = o
    end
    if pause and q % 256 == 0 then pause() end
  end
  first, nxt, eP = nil, nil, nil
  -- ...and where that guess is wrong, what is there (0-based polygon numbers in the file)
  if D.nei and D.nei ~= "" then
    local num, more = reader(D.nei)
    local last = 0
    while more() do
      local i = last + num(); local e = num(); local r = num()
      pe[pstart[i + 1] + e] = (r == 0) and 0 or (i + unzz(r - 1) + 1)
      last = i
    end
  end
  local T3 = clock()
  -- the strings the search reads: a chunk of RP polygons' records, and their edges
  local PC, EC = {}, {}
  local bytes = 0
  local nc = floor((D.np - 1) / RP) + 1
  for c = 0, nc - 1 do
    local pr, er, ne = {}, {}, 0
    for q = c * RP + 1, math.min(D.np, (c + 1) * RP) do
      local a1, a2 = u16(ne)
      local l1, l2 = u16(zlo[q]); local m1, m2 = u16(zmid[q]); local h1, h2 = u16(zhi[q])
      pr[#pr + 1] = char(a1, a2, pn[q] * 4 + parea[q], l1, l2, m1, m2, h1, h2)
      for e = pstart[q], pstart[q] + pn[q] - 1 do
        local v = pv[e]
        local x1, x2 = u16(vx[v]); local y1, y2 = u16(vy[v]); local z1, z2 = u16(vz[v])
        local o = pe[e]
        er[#er + 1] = char(x1, x2, y1, y2, z1, z2, o % 256, floor(o / 256) % 256, floor(o / 65536))
        ne = ne + 1
      end
    end
    PC[c + 1], EC[c + 1] = concat(pr), concat(er)
    -- (a string: about 25 bytes of header and its characters)
    bytes = bytes + #PC[c + 1] + #EC[c + 1] + 2 * 25
    if pause then pause() end
  end
  N.PC, N.EC = PC, EC
  -- off-mesh links, as the polygons they come into (the search runs backwards): { from, fx, fy, fz, to, tx, ty, tz, cost }
  local inc = {}
  -- (a link: a table of 9 numbers, ~200 bytes; a polygon's list of them ~72 more)
  local function into(q, l) local t = inc[q]; if not t then t = {}; inc[q] = t; bytes = bytes + 72 + 40 end; t[#t + 1] = l; bytes = bytes + 16 + 200 end
  local nl = readLinks(N, D.links, into)
  -- (the falls only a ghost takes stay packed until a corpse run asks for them: Mesh.Falls)
  N.fallText = D.falls
  local T4 = clock()
  -- the buckets: polygon numbers by their box (columns grow westwards, rows southwards, as the walk map's)
  local B = Mesh.BUCKET
  local lists = {}
  local W = floor((D.left - D.right) / B) + 1
  for q = 1, D.np do
    local minx, maxx, miny, maxy = huge, -huge, huge, -huge
    for e = pstart[q], pstart[q] + pn[q] - 1 do
      local v = pv[e]
      local X, Y = left - vx[v] * unit, top - vy[v] * unit
      if X < minx then minx = X end; if X > maxx then maxx = X end
      if Y < miny then miny = Y end; if Y > maxy then maxy = Y end
    end
    local id = char(q % 256, floor(q / 256) % 256, floor(q / 65536))
    for r = floor((top - maxy) / B), floor((top - miny) / B) do
      for c = floor((left - maxx) / B), floor((left - minx) / B) do
        local key = r * W + c
        local t = lists[key]; if not t then t = {}; lists[key] = t end
        t[#t + 1] = id
      end
    end
    if pause and q % 512 == 0 then pause() end
  end
  local buckets = {}
  for key, t in pairs(lists) do buckets[key] = concat(t); bytes = bytes + 40 + 25 + 3 * #t end
  lists = nil
  N.inc, N.nlinks, N.buckets, N.bw, N.np, N.nv, N.ne = inc, nl, buckets, W, D.np, D.nv, k
  -- (the memory it holds, about: the strings and the tables round them, as the game's Lua counts them)
  N.bytes = bytes + 2 * (nc * 16 + 56)
  N.phaseMs = { T1 - T0, T2 - T1, T3 - T2, T4 - T3, clock() - T4 }
  return N
end

-- A ghost can't die of a fall: the run back to your corpse may drop off any ledge, and slide down a slope too steep to
-- stand on. The walk maps' drops stop at 10 yd (tools/voxnav.js P.maxDrop), the most a living body takes; the falls
-- past that are a zone's `falls` (packed as its links), for ghosts only, and read the first time a corpse run asks for
-- them, not with the zone. -> the falls into each polygon, as Unpack's N.inc (empty when the zone has none)
function Mesh.Falls(N)
  if N.fallInc then return N.fallInc end
  local inc, n = {}, 0
  if N.fallText and N.fallText ~= "" then
    readLinks(N, N.fallText, function(q, l)
      local t = inc[q]; if not t then t = {}; inc[q] = t; N.bytes = N.bytes + 72 + 40 end
      t[#t + 1] = l; N.bytes = N.bytes + 16 + 200; n = n + 1
    end)
  end
  N.fallInc, N.nfalls = inc, n
  return inc
end

-- polygon p: its edges' string and where its first edge's record starts, its corner count and ground type
local function poly(N, p)
  local c = floor((p - 1) / RP)
  local o = (p - 1 - c * RP) * 9 + 1
  local e1, e2, ca = byte(N.PC[c + 1], o, o + 2)
  return N.EC[c + 1], (e1 + e2 * 256) * 9 + 1, floor(ca / 4), ca % 4
end
Mesh.Poly = poly
-- polygon p's lowest, middle and highest height (world yards)
local function heights(N, p)
  local c = floor((p - 1) / RP)
  local o = (p - 1 - c * RP) * 9 + 4
  local l1, l2, m1, m2, h1, h2 = byte(N.PC[c + 1], o, o + 5)
  local z0 = N.zmin
  return (l1 + l2 * 256) / 2 + z0, (m1 + m2 * 256) / 2 + z0, (h1 + h2 * 256) / 2 + z0
end
Mesh.Heights = heights
-- the corners of polygon p in world yards: xs, ys, zs, count (new tables; not for the search's loop)
local function corners(N, p)
  local E, o, n = poly(N, p)
  local xs, ys, zs = {}, {}, {}
  local left, top, unit, z0 = N.left, N.top, N.unit, N.zmin
  for k = 1, n do
    local x1, x2, y1, y2, z1, z2 = byte(E, o, o + 5)
    xs[k], ys[k], zs[k] = left - (x1 + x2 * 256) * unit, top - (y1 + y2 * 256) * unit, (z1 + z2 * 256) / 2 + z0
    o = o + 9
  end
  return xs, ys, zs, n
end
Mesh.Corners = corners
-- the polygon across edge k (1-based) of polygon p (0: a wall)
function Mesh.Across(N, p, k)
  local E, o = poly(N, p)
  local n1, n2, n3 = byte(E, o + (k - 1) * 9 + 6, o + (k - 1) * 9 + 8)
  return n1 + n2 * 256 + n3 * 65536
end

local function area2(ax, ay, bx, by, cx, cy) return (bx - ax) * (cy - ay) - (cx - ax) * (by - ay) end
Mesh.area2 = area2
-- is (x, y) in polygon p (edges included)?
local function inside(N, p, x, y)
  local xs, ys, _, n = corners(N, p)
  for k = 1, n do
    local j = k < n and k + 1 or 1
    if area2(xs[k], ys[k], xs[j], ys[j], x, y) < -1e-6 then return false end
  end
  return true
end
Mesh.Inside = inside
-- the point of polygon p nearest (x, y), and how far
local function nearestIn(N, p, x, y)
  if inside(N, p, x, y) then return x, y, 0 end
  local xs, ys, _, n = corners(N, p)
  local bd, bx, by = huge, x, y
  for k = 1, n do
    local j = k < n and k + 1 or 1
    local ax, ay = xs[k], ys[k]
    local dx, dy = xs[j] - ax, ys[j] - ay
    local L2 = dx * dx + dy * dy
    local t = L2 > 0 and ((x - ax) * dx + (y - ay) * dy) / L2 or 0
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local qx, qy = ax + t * dx, ay + t * dy
    local d = sqrt((x - qx) ^ 2 + (y - qy) ^ 2)
    if d < bd then bd, bx, by = d, qx, qy end
  end
  -- (a hair inside, towards the middle: the funnel starts in the polygon)
  local cx, cy = 0, 0
  for k = 1, n do cx = cx + xs[k]; cy = cy + ys[k] end
  cx, cy = cx / n, cy / n
  return bx + (cx - bx) * 0.01, by + (cy - by) * 0.01, bd
end
Mesh.NearestIn = nearestIn
-- the polygons whose box takes in the buckets within rad yards of (x, y)
local function around(N, x, y, rad, seen, out)
  local B = Mesh.BUCKET
  local r0, r1 = floor((N.top - y - rad) / B), floor((N.top - y + rad) / B)
  local c0, c1 = floor((N.left - x - rad) / B), floor((N.left - x + rad) / B)
  for r = r0, r1 do
    for c = c0, c1 do
      local t = N.buckets[r * N.bw + c]
      if t then
        for i = 1, #t, 3 do
          local a, b, d = byte(t, i, i + 2)
          local p = a + b * 256 + d * 65536
          if not seen[p] then seen[p] = true; out[#out + 1] = p end
        end
      end
    end
  end
  return out
end
-- The polygons at a world point: those holding it; with none, the nearest within Mesh.SNAP. With a height z: the nearest
-- in height (by the polygons' heights; the narrowest first - under a bridge the ground, not the deck with its ramps).
-- Without: every level there, and the nearest polygon of each other height within Mesh.LEVEL (as the grid's nodesNear).
function Mesh.Near(N, x, y, z)
  local cand, seen = {}, {}
  local all = around(N, x, y, 0, seen, {})
  for i = 1, #all do if inside(N, all[i], x, y) then cand[#cand + 1] = all[i] end end
  if #cand == 0 then
    local near, dmin = {}, huge
    for _, p in ipairs(around(N, x, y, Mesh.SNAP, {}, {})) do
      local _, _, d = nearestIn(N, p, x, y)
      if d <= Mesh.SNAP then near[#near + 1] = { p, d }; if d < dmin then dmin = d end end
    end
    for _, e in ipairs(near) do if e[2] <= dmin + 4 then cand[#cand + 1] = e[1] end end
    if #cand == 0 then return cand end
  end
  local zlo, zmid, zhi = {}, {}, {}
  local function hz(p) if not zmid[p] then zlo[p], zmid[p], zhi[p] = heights(N, p) end end
  for i = 1, #cand do hz(cand[i]) end
  if not z then
    local zs, mine = {}, {}
    for i = 1, #cand do zs[i] = zmid[cand[i]]; mine[cand[i]] = true end
    local more = {}
    for _, p in ipairs(around(N, x, y, Mesh.LEVEL, mine, {})) do
      local _, _, d = nearestIn(N, p, x, y)
      if d <= Mesh.LEVEL then more[#more + 1] = { p, d } end
    end
    table.sort(more, function(a, b) if a[2] ~= b[2] then return a[2] < b[2] end return a[1] < b[1] end)
    for _, e in ipairs(more) do
      hz(e[1])
      local zm, new = zmid[e[1]], true
      for i = 1, #zs do if abs(zs[i] - zm) <= Mesh.Z_SNAP then new = false; break end end
      if new then cand[#cand + 1] = e[1]; zs[#zs + 1] = zm end
    end
    return cand
  end
  local function off(p) if z < zlo[p] then return zlo[p] - z elseif z > zhi[p] then return z - zhi[p] end return 0 end
  local best = huge
  for i = 1, #cand do local d = off(cand[i]); if d < best then best = d end end
  local close = {}
  for i = 1, #cand do if off(cand[i]) <= best + (best > 0 and Mesh.Z_SNAP or 0) then close[#close + 1] = cand[i] end end
  table.sort(close, function(a, b)
    local da, db = off(a), off(b)
    if da ~= db then return da < db end
    local wa, wb = zhi[a] - zlo[a], zhi[b] - zlo[b]
    if wa ~= wb then return wa < wb end
    return a < b
  end)
  local narrow = zhi[close[1]] - zlo[close[1]] + 3
  local out = {}
  for i = 1, #close do if zhi[close[i]] - zlo[close[i]] <= narrow then out[#out + 1] = close[i] end end
  return out
end

-- the point of portal (ax, ay)-(bx, by) where the straight line from (px, py) to (sx, sy) crosses it, else its nearer end
-- (kept a little inside the ends: a line through the very corner of a portal is the next wall's)
local function portalPoint(ax, ay, bx, by, px, py, sx, sy)
  local dx, dy, ex, ey = bx - ax, by - ay, sx - px, sy - py
  local den = dx * ey - dy * ex
  local t
  if den ~= 0 then t = ((px - ax) * ey - (py - ay) * ex) / den
  else local L2 = dx * dx + dy * dy; t = L2 > 0 and ((sx - ax) * dx + (sy - ay) * dy) / L2 or 0.5 end
  if t < 0.02 then t = 0.02 elseif t > 0.98 then t = 0.98 end
  return ax + dx * t, ay + dy * t
end
Mesh.PortalPoint = portalPoint

-- Start a search on mesh N from the target (tx, ty, tz) back to you (sx, sy, sz). Mesh.Run works on it a slice at a time;
-- then S.found is the polygon you are in (nil: no way). A polygon's place is where the way enters it (the point of the
-- portal nearest the straight line on to you), so what it costs is the length of a line that can really be walked.
-- ghost: the run back to your corpse - it may take the falls (Mesh.Falls) too.
function Mesh.Search(N, sx, sy, sz, tx, ty, tz, ghost)
  local S = { N = N, mesh = true, g = {}, nxt = {}, via = {}, viaL = {}, px = {}, py = {}, closed = {}, hk = {}, hv = {}, hn = 0, starts = {},
    sx = sx, sy = sy, sz = sz, tx = tx, ty = ty, tz = tz, expansions = 0, done = false, ms = 0 }
  if ghost then local F = Mesh.Falls(N); if next(F) then S.falls = F end end
  local goals = Mesh.Near(N, tx, ty, tz)
  local starts = Mesh.Near(N, sx, sy, sz)
  if #goals == 0 or #starts == 0 then S.done = true; return S end
  for _, p in ipairs(starts) do S.starts[p] = true end
  -- (the target's point in its polygon; the estimate counts every yard at the cheapest ground's price)
  local gx, gy = nearestIn(N, goals[1], tx, ty)
  local hmin = huge; for _, c in pairs(Mesh.COST) do if c < hmin then hmin = c end end
  S.hw = hmin
  for _, p in ipairs(goals) do
    S.g[p] = 0; S.px[p], S.py[p] = gx, gy
    local k = sqrt((gx - sx) ^ 2 + (gy - sy) ^ 2) * hmin
    local hk, hv = S.hk, S.hv
    local i = S.hn + 1; S.hn = i
    while i > 1 do local q = floor(i / 2); if hk[q] <= k then break end; hk[i], hv[i] = hk[q], hv[q]; i = q end
    hk[i], hv[i] = k, p
  end
  return S
end

-- work on a search for up to budgetMs (nil: to the end); true when it is finished
function Mesh.Run(S, budgetMs)
  if S.done then return true end
  local N = S.N
  local g, nxt, via, viaL, px, py, closed, starts, hk, hv = S.g, S.nxt, S.via, S.viaL, S.px, S.py, S.closed, S.starts, S.hk, S.hv
  local PC, EC, inc, COST = N.PC, N.EC, N.inc, Mesh.COST
  local falls = S.falls
  local left, top, unit = N.left, N.top, N.unit
  local sx, sy, hw = S.sx, S.sy, S.hw
  local hn = S.hn
  local t0 = clock()
  local count = 0
  local function push(k, v)
    hn = hn + 1
    local j = hn
    while j > 1 do local q = floor(j / 2); if hk[q] <= k then break end; hk[j], hv[j] = hk[q], hv[q]; j = q end
    hk[j], hv[j] = k, v
  end
  -- off-mesh links l into polygon u (reached at cost gu, at ux, uy, on ground costing cu a yard)
  local function linksInto(u, l, gu, ux, uy, cu)
    for i = 1, #l do
      local L = l[i]
      local v = L[1]
      if not closed[v] then
        -- (walking: v -> its end of the link -> u's end -> on)
        local nv = gu + sqrt((L[6] - ux) ^ 2 + (L[7] - uy) ^ 2) * cu + L[9]
        local old = g[v]
        if not old or nv < old then
          g[v] = nv; nxt[v] = u; via[v] = nil; viaL[v] = L; px[v], py[v] = L[2], L[3]
          push(nv + sqrt((L[2] - sx) ^ 2 + (L[3] - sy) ^ 2) * hw, v)
        end
      end
    end
  end
  while hn > 0 do
    local u = hv[1]
    local lk, lv = hk[hn], hv[hn]
    hk[hn], hv[hn] = nil, nil
    hn = hn - 1
    if hn > 0 then
      local i = 1
      while true do
        local l = i * 2; local r = l + 1; local m = i; local mk = lk
        if l <= hn and hk[l] < mk then m = l; mk = hk[l] end
        if r <= hn and hk[r] < mk then m = r; mk = hk[r] end
        if m == i then break end
        hk[i], hv[i] = hk[m], hv[m]; i = m
      end
      hk[i], hv[i] = lk, lv
    end
    if not closed[u] then
      closed[u] = true
      count = count + 1
      if starts[u] then S.hn = hn; S.found = u; S.done = true; S.expansions = S.expansions + count; S.ms = S.ms + (clock() - t0); return true end
      local gu, ux, uy = g[u], px[u], py[u]
      -- (polygon u's record, inline: its edges' string, where they start, how many, its ground)
      local c = floor((u - 1) / RP)
      local o = (u - 1 - c * RP) * 9 + 1
      local e1, e2, ca = byte(PC[c + 1], o, o + 2)
      local E = EC[c + 1]
      local eo = (e1 + e2 * 256) * 9 + 1
      local n = floor(ca / 4)
      local cu = COST[ca % 4]
      local x1, x2, y1, y2 = byte(E, eo, eo + 3)
      local fx, fy = left - (x1 + x2 * 256) * unit, top - (y1 + y2 * 256) * unit
      local ax, ay = fx, fy
      for k = 0, n - 1 do
        local q = eo + k * 9
        local n1, n2, n3 = byte(E, q + 6, q + 8)
        local bx, by
        if k == n - 1 then bx, by = fx, fy
        else x1, x2, y1, y2 = byte(E, q + 9, q + 12); bx, by = left - (x1 + x2 * 256) * unit, top - (y1 + y2 * 256) * unit end
        local v = n1 + n2 * 256 + n3 * 65536
        if v > 0 and not closed[v] then
          local qx, qy = portalPoint(ax, ay, bx, by, ux, uy, sx, sy)
          local nv = gu + sqrt((qx - ux) ^ 2 + (qy - uy) ^ 2) * cu
          local old = g[v]
          if not old or nv < old then
            g[v] = nv; nxt[v] = u; via[v] = k; viaL[v] = nil; px[v], py[v] = qx, qy
            push(nv + sqrt((qx - sx) ^ 2 + (qy - sy) ^ 2) * hw, v)
          end
        end
        ax, ay = bx, by
      end
      -- (the links into u, and on a ghost's search the falls into it)
      local l = inc[u]
      if l then linksInto(u, l, gu, ux, uy, cu) end
      if falls then l = falls[u]; if l then linksInto(u, l, gu, ux, uy, cu) end end
      if budgetMs and count % 32 == 0 and clock() - t0 > budgetMs then
        S.hn = hn; S.expansions = S.expansions + count; S.ms = S.ms + (clock() - t0)
        return false
      end
    end
  end
  S.hn = hn; S.done = true; S.expansions = S.expansions + count; S.ms = S.ms + (clock() - t0)
  return true
end

-- the funnel (simple stupid funnel, Mononen) over portals { lx, ly, rx, ry, left z, right z } from the start to the end
-- -> the points { x, y, z } it turns at (the first is the start; the last the end). Left = a positive area2.
local function funnel(portals, out)
  local P0 = portals[1]
  local ax, ay = P0[1], P0[2]
  local lx, ly, rx, ry, lz, rz = ax, ay, P0[3], P0[4], P0[5], P0[6]
  local li, ri = 1, 1
  local i = 2
  local n = #portals
  out[#out + 1] = { ax, ay, P0[5] }
  while i <= n do
    local P = portals[i]
    local Lx, Ly, Rx, Ry = P[1], P[2], P[3], P[4]
    local restart = false
    if area2(ax, ay, rx, ry, Rx, Ry) >= 0 then
      if (ax == rx and ay == ry) or area2(ax, ay, lx, ly, Rx, Ry) < 0 then rx, ry, rz, ri = Rx, Ry, P[6], i
      else
        out[#out + 1] = { lx, ly, lz }
        ax, ay = lx, ly
        local k = li
        rx, ry, lx, ly, rz = ax, ay, ax, ay, lz
        li, ri = k, k
        i = k + 1; restart = true
      end
    end
    if not restart then
      if area2(ax, ay, lx, ly, Lx, Ly) <= 0 then
        if (ax == lx and ay == ly) or area2(ax, ay, rx, ry, Lx, Ly) > 0 then lx, ly, lz, li = Lx, Ly, P[5], i
        else
          out[#out + 1] = { rx, ry, rz }
          ax, ay = rx, ry
          local k = ri
          rx, ry, lx, ly, lz = ax, ay, ax, ay, rz
          li, ri = k, k
          i = k + 1; restart = true
        end
      end
      if not restart then i = i + 1 end
    end
  end
  local last = portals[n]
  local e = out[#out]
  if not e or e[1] ~= last[1] or e[2] ~= last[2] then out[#out + 1] = { last[1], last[2], last[5] } end
  return out
end
Mesh.Funnel = funnel

-- The line for a finished search, from polygon `from` (default: where the search found you), where you stand at (sx, sy)
-- (default: where the search started): the portals along the polygons the search left, pulled tight; an off-mesh link
-- (a door step, a corner two pieces touch at, a drop) is a point the line goes through. Points are { wx, wy, z or nil }:
-- first where you stand, last the target. The same table as Nav.Path's.
function Mesh.Path(S, from, sx, sy, pause)
  from = from or S.found
  if not (S.done and from and S.g[from]) then return nil end
  local N = S.N
  sx, sy = sx or S.sx, sy or S.sy
  local fx, fy = nearestIn(N, from, sx, sy)
  local _, zm = heights(N, from)
  local zHere = S.sz or zm
  local out = { { fx, fy, zHere } }
  local portals = { { fx, fy, fx, fy, zHere, zHere } }
  local p, guard, nodes = from, 0, { from }
  local function flush(ex, ey, ez)
    portals[#portals + 1] = { ex, ey, ex, ey, ez, ez }
    local pts = funnel(portals, {})
    for i = 2, #pts do out[#out + 1] = pts[i] end
  end
  while S.nxt[p] and guard < 100000 do
    local q = S.nxt[p]
    local L = S.viaL[p]
    if L then
      -- (out of p at the link's far end from q, into q at its own)
      flush(L[2], L[3], L[4])
      out[#out + 1] = { L[6], L[7], L[8] }
      portals = { { L[6], L[7], L[6], L[7], L[8], L[8] } }
    else
      -- walking p -> q across q's edge k (corner k+1 -> the next): left that one, right the next
      local k = S.via[p]
      local xs, ys, zs, n = corners(N, q)
      local a, b = k + 1, (k + 1 < n) and k + 2 or 1
      portals[#portals + 1] = { xs[a], ys[a], xs[b], ys[b], zs[a], zs[b] }
    end
    p = q
    nodes[#nodes + 1] = p
    guard = guard + 1
    if pause and guard % 64 == 0 then pause() end
  end
  local gx, gy = nearestIn(N, p, S.tx, S.ty)
  local _, zt = heights(N, p)
  flush(gx, gy, S.tz or zt)
  -- you and the target as they are, not as snapped into their polygons
  out[1][1], out[1][2] = sx, sy
  local last = out[#out]
  last[1], last[2] = S.tx, S.ty
  if S.tz then last[3] = S.tz end
  -- (a point on top of the one before it - a link's two ends at one spot - says nothing)
  local pts = { out[1] }
  for i = 2, #out do
    local a, b = pts[#pts], out[i]
    if i == #out or abs(a[1] - b[1]) > 0.05 or abs(a[2] - b[2]) > 0.05 then pts[#pts + 1] = b end
  end
  local rem = {}; rem[#pts] = 0
  for k = #pts - 1, 1, -1 do rem[k] = rem[k + 1] + sqrt((pts[k + 1][1] - pts[k][1]) ^ 2 + (pts[k + 1][2] - pts[k][2]) ^ 2) end
  return { pts = pts, rem = rem, len = rem[1], cursor = 1, z0 = pts[1][3], z1 = pts[#pts][3], nodes = nodes, inst = N.inst, m = N.m, mapYd = N.left - N.right, cell = N.cell, nav = true, mesh = true }
end

-- one go (tests, tools): -> path (or nil), the search, total ms
function Mesh.Find(N, sx, sy, sz, tx, ty, tz, ghost)
  local t0 = clock()
  local S = Mesh.Search(N, sx, sy, sz, tx, ty, tz, ghost)
  Mesh.Run(S)
  return Mesh.Path(S), S, clock() - t0
end

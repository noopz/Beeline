// The built-in plans as two load-on-demand addons, one per faction (Beeline_Plans_Alliance / _Horde), instead of
// one addon per race and class: 51 entries filled the game's addon list. Each plan's Lua (addon/Beeline_Starter_*/
// Plan.lua, written by tools/starter.js) goes in as a string; the addon turns only yours into code (Core.lua
// LoadMyPlan) and drops the rest, so memory ends up as before - just your plan.
// The per-plan folders stay the build's output in the repo; tools/package.sh and tools/install.sh call this.
// usage: node tools/bundle-plans.js <out dir>   (writes <out>/Beeline_Plans_Alliance and _Horde)
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..');
const out = process.argv[2];
if (!out) { console.log('usage: node tools/bundle-plans.js <out dir>'); process.exit(2); }
const HORDE = new Set(['orc', 'undead', 'tauren', 'troll', 'skybornehorde']);
const mainToc = fs.readFileSync(path.join(ROOT, 'addon', 'Beeline', 'Beeline.toc'), 'utf8');
const iface = (/## Interface: (\S+)/.exec(mainToc) || [, '16001'])[1];
const sides = { Alliance: [], Horde: [] };
for (const d of fs.readdirSync(path.join(ROOT, 'addon')).sort()) {
  const m = /^Beeline_Starter_([a-z]+)_([a-z]+)$/.exec(d);
  if (!m) continue;
  const file = path.join(ROOT, 'addon', d, 'Plan.lua');
  if (!fs.existsSync(file)) continue;
  const key = `${m[1]}-${m[2]}`;
  // (line endings as LF: a checkout with CRLF matched no zone route, and every plan kept its own copy)
  sides[HORDE.has(m[1]) ? 'Horde' : 'Alliance'].push({ key, src: fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n') });
}
// Zone routes (a tree's ready-made route per zone and level band) are the same in every plan of a faction: 45 of them,
// copied into 28 plans, took the faction's file from about 30 MB to 53. Each is kept once (BeelinePlanShared) and
// each plan has a one-line marker where it was; the addon puts the text back into your plan only (Core.lua LoadStarter).
// A marker whose route is missing is a Lua comment: that plan still loads, without that one zone route.
// The dungeon routes (tools/dungeon-routes.js) too: a dungeon's route is the same for most races and classes of a
// faction (a class quest for it is what makes one differ: that plan keeps its own) - 7 MB a faction, kept once.
const ZR_BLOCK = /\n  \{\n    id = "((?:zone|dungeon):[^"\n]+)",[\s\S]*?\n  \},?(?=\n)/g;
// the trunk's visits (paths.js BeelineVisits) are the same in every plan of a faction too: kept once, as "visits"
const VISITS_BLOCK = /\nBeelineVisits = \{\n[\s\S]*?\n\}(?=\n)/g;
// every block kept once: [text, id]
const blocksOf = (src) => [...[...src.matchAll(ZR_BLOCK)].map((m) => [m[0], m[1]]), ...[...src.matchAll(VISITS_BLOCK)].map((m) => [m[0], 'visits'])];
const packBlocks = (src, shared) => src.replace(ZR_BLOCK, (m, id) => (shared[id] === m ? marker(id) : m)).replace(VISITS_BLOCK, (m) => (shared.visits === m ? marker('visits') : m));
const marker = (id) => `\n--@zr ${id}@`;
// a block without the per-class timing fields (a step's dt, dd, qt; s in its g = { ... }): what makes it the same route
const TIMING = /, (?:s|dt|dd|qt) = -?[0-9.]+(?=[ ,}])/g;
const untimed = (text) => text.replace(TIMING, '');
const unpack = (src, shared) => src.replace(/\n--@zr ([^@\n]+)@/g, (m, id) => (id in shared ? shared[id] : m));
// Steps (the design for zones and chains, 3.4 part 1): a faction's plans walk the same trunk, so most of their step
// lines are word for word the same - 25 MB of main-path steps per faction held 1.4 MB of distinct lines. Each distinct
// step line (without its position fields sec and id) is kept once per faction (BeelinePlanShared.lines, one per
// line), and a plan's step list becomes "--@sl i:sec:id,...@" (i: the line's number there); the addon puts the lines
// back for your plan only (Core.lua LoadStarter). A block with a line this can't read stays as it was.
const STEPS_BLOCK = /\n    steps = \{\n([\s\S]*?)\n    \},?(?=\n)/g;
// the position of `token` in a step line outside quoted text, or -1
function outside(line, token) {
  let q = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === '\\' && q) { i++; continue; }
    if (c === '"') q = !q;
    else if (!q && line.startsWith(token, i)) return i;
  }
  return -1;
}
// a step line as { body (ending ' }', no sec/id), sec, id } or null
function stepOf(line) {
  const m = /^      (\{ .*\}),?$/.exec(line);
  if (!m) return null;
  let body = m[1], sec = '', id = '';
  for (const f of ['sec', 'id']) {
    const tok = ', ' + f + ' = ';
    const at = outside(body, tok);
    if (at < 0) continue;
    const v = /^\d+/.exec(body.slice(at + tok.length));
    if (!v) return null;
    if (f === 'sec') sec = v[0]; else id = v[0];
    body = body.slice(0, at) + body.slice(at + tok.length + v[0].length);
  }
  return body.endsWith(' }') ? { body, sec, id } : null;
}
const stepLine = (body, sec, id) => '      ' + body.slice(0, -2) + (sec ? ', sec = ' + sec : '') + (id ? ', id = ' + id : '') + ' },';
function packSteps(src, dict) {
  return src.replace(STEPS_BLOCK, (all, inner) => {
    const parts = [];
    for (const l of inner.split('\n')) {
      const s = stepOf(l); if (!s) return all;
      let n = dict.idx.get(s.body); if (n === undefined) { n = dict.list.length + 1; dict.list.push(s.body); dict.idx.set(s.body, n); }
      parts.push(n + ':' + s.sec + ':' + s.id);
    }
    return '\n    steps = {\n--@sl ' + parts.join(',') + '@\n    },';
  });
}
const unpackSteps = (src, list) => src.replace(/\n--@sl ([^@\n]*)@/g, (m, s) => '\n' + s.split(',').map((e) => { const [i, sec, id] = e.split(':'); return stepLine(list[+i - 1], sec, id); }).join('\n'));
// the same plan, step for step: every line equal, a step line equal as a step (its fields; the trailing comma aside)
function samePlan(a, b) {
  const A = a.split('\n'), B = b.split('\n');
  if (A.length !== B.length) return 'line count ' + A.length + ' vs ' + B.length;
  for (let i = 0; i < A.length; i++) {
    if (A[i] === B[i]) continue;
    const x = stepOf(A[i]), y = stepOf(B[i]);
    if (!(x && y && x.body === y.body && x.sec === y.sec && x.id === y.id)) return 'line ' + (i + 1) + ': ' + A[i].slice(0, 80) + ' | ' + B[i].slice(0, 80);
  }
  return null;
}
// a long bracket that the text never closes by accident
const longString = (s) => { let n = 1; while (s.includes(']' + '='.repeat(n) + ']')) n++; const eq = '='.repeat(n); return `[${eq}[\n${s}]${eq}]`; };
for (const [side, plans] of Object.entries(sides)) {
  if (!plans.length) continue;
  const name = `Beeline_Plans_${side}`;
  const dir = path.join(out, name);
  fs.mkdirSync(dir, { recursive: true });
  const stamps = [...new Set(plans.map((p) => (/-- (plans \d{4}-\d\d-\d\d[^\n]*)/.exec(p.src) || [])[1]).filter(Boolean))];
  fs.writeFileSync(path.join(dir, name + '.toc'), [
    '## Interface: ' + iface,
    `## Title: Beeline - ${side} plans`,
    `## IconTexture: Interface\\AddOns\\Beeline\\Media\\logo`,
    `## Notes: The built-in plans for every ${side} race and class. Loaded by Beeline only for a character with no plan of its own; only that character's plan is kept.`,
    '## Dependencies: Beeline',
    '## Group: Beeline',
    '## LoadOnDemand: 1',
    '## Version: ' + (stamps[0] ? stamps[0].split(' · ')[0] : 'plans'),
    // (when this build was made: the addon's /bee report keeps only the errors seen since - UI/Report.lua BuiltAt)
    '## X-Built: ' + (+process.env.FR_BUILT || Math.floor(Date.now() / 1000)),
    '', 'Plans.lua', ''].join('\n'));
  // the zone routes every plan here has word for word: kept once
  const seen = {}, shared = {};
  for (const p of plans) for (const [text, id] of blocksOf(p.src)) (seen[id] = seen[id] || new Map()).set(text, ((seen[id].get(text)) || 0) + 1);
  for (const [id, texts] of Object.entries(seen)) { const [text, n] = [...texts.entries()].sort((a, b) => b[1] - a[1])[0]; if (n > 1) shared[id] = text; }
  // a zone route that differs between plans of one faction is kept in each of them: say so when its steps differ
  // (something class-dependent got into it, and the file grows by a copy per plan). Only the per-class timings told
  // apart (TIMING: a step's dt, dd, qt and its g's s, from each plan's own clock) is how a tree's plans are: not said.
  // (Those copies stay whole: sharing them would lose each class's timings, and their step lines already go through
  // the shared step lines below.) A dungeon route may differ by design (a class quest for it, above).
  const split = Object.entries(seen).filter(([id, texts]) => id.startsWith('zone:') && new Set([...texts.keys()].map(untimed)).size > 1).map(([id, texts]) => id + ' (' + new Set([...texts.keys()].map(untimed)).size + ' versions)');
  if (split.length) console.error(`${side}: zone route(s) not the same in every plan: ${split.slice(0, 8).join(', ')}${split.length > 8 ? ' ...' : ''}`);
  for (const p of plans) {
    p.packed = packBlocks(p.src, shared);
    if (unpack(p.packed, shared) !== p.src) throw new Error('bundle: ' + p.key + ' does not come back whole from its zone route markers');
  }
  // the step lines, kept once (3.4 part 1): every plan must come back step for step
  const dict = { list: [], idx: new Map() };
  for (const p of plans) {
    const zp = p.packed;
    p.packed = packSteps(zp, dict);
    const why = samePlan(unpack(unpackSteps(p.packed, dict.list), shared), p.src);
    if (why) throw new Error('bundle: ' + p.key + ' does not come back step for step from its step lines (' + why + ')');
  }
  if (dict.list.length) shared.lines = dict.list.join('\n');
  const L = [`-- The built-in ${side} plans (tools/bundle-plans.js from addon/Beeline_Starter_*): each as text, made into code`,
    '-- only for your race and class (Core.lua LoadMyPlan). Regenerate rather than edit.',
    'BeelinePlanSources = BeelinePlanSources or {}', 'BeelinePlanShared = BeelinePlanShared or {}'];
  for (const [id, text] of Object.entries(shared)) L.push(`BeelinePlanShared[${JSON.stringify(id)}] = ${longString(text)}`);
  for (const p of plans) L.push(`BeelinePlanSources[${JSON.stringify(p.key)}] = ${longString(p.packed)}`);
  fs.writeFileSync(path.join(dir, 'Plans.lua'), L.join('\n') + '\n');
  // read back: every plan comes out exactly as it went in (the long brackets hold)
  const back = fs.readFileSync(path.join(dir, "Plans.lua"), "utf8");
  for (const p of plans) {
    const head = `BeelinePlanSources[${JSON.stringify(p.key)}] = [`;
    const at = back.indexOf(head); if (at < 0) throw new Error("bundle: " + p.key + " missing");
    let k = at + head.length, eq = 0; while (back[k] === "=") { eq++; k++; }
    const open = k + 2, close = back.indexOf("]" + "=".repeat(eq) + "]", open);
    if (back.slice(open, close) !== p.packed) throw new Error("bundle: " + p.key + " does not read back as written");
  }
  console.log(`${name}: ${plans.length} plans, ${Object.keys(shared).length - (shared.lines ? 1 : 0)} shared zone routes, ${dict.list.length} shared step lines, ${(fs.statSync(path.join(dir, 'Plans.lua')).size / 1e6).toFixed(1)} MB`);
}

// The dashboard page, run in jsdom against its real host (dashboard_serve.py). The owner keeps one layout across
// every open page, so a page that has fallen behind must never write its old layout over a newer one.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const { JSDOM, VirtualConsole } = createRequire(path.join(process.env.COMMANDECK_TEST_NODE_MODULES, '..', 'x.js'))('jsdom');
const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const html = fs.readFileSync(path.join(ROOT, 'dashboard', 'index.html'), 'utf8');
const appSrc = fs.readFileSync(path.join(ROOT, 'dashboard', 'app.js'), 'utf8');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let dir, port, host;
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dash-view-'));
  port = await new Promise((r) => { const s = net.createServer().listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => r(p)); }); });
  host = spawn('python3', [path.join(ROOT, 'scripts', 'dashboard_serve.py'), String(port), '127.0.0.1', dir], { stdio: 'ignore' });
  for (let i = 0; i < 50; i += 1) { try { await fetch(`http://127.0.0.1:${port}/`); break; } catch { await sleep(100); } }
});
after(() => { host.kill(); fs.rmSync(dir, { recursive: true, force: true }); });

const onDisk = () => JSON.parse(fs.readFileSync(path.join(dir, 'layout.js'), 'utf8').replace(/^window\.DASH_LAYOUT = /, '').replace(/;\s*$/, ''));

// One page, as the browser opens it: layout.js read from the host's folder, then app.js. `store` is the
// localStorage a page before it left (a reload). Every save goes to the real host; w.puts counts them and
// w.reloads counts the page asking to reload itself (jsdom reports that as navigation it cannot do).
function boot(store = {}, project = 'demo', clock = Date, at = '127.0.0.1') {
  const virtualConsole = new VirtualConsole();
  const dom = new JSDOM(html, { url: `http://${at}:${port}/index.html?project=${project}`, virtualConsole });
  const w = dom.window;
  w.reloads = 0;
  w.puts = 0;
  virtualConsole.on('jsdomError', (e) => { if (/navigation/.test(e.message)) w.reloads += 1; else console.error(e); });
  for (const [k, v] of Object.entries(store)) w.localStorage.setItem(k, v);
  w.DASH_LAYOUT = onDisk();
  w.fetch = (url, opt) => { w.puts += 1; return fetch(`http://127.0.0.1:${port}/${url}`, opt); };
  const none = () => 0;
  // w.refresh() runs the page's timers once, as the next refresh would: it asks for data.js again.
  const timers = [];
  w.refresh = () => timers.forEach((f) => f());
  vm.runInNewContext(appSrc, { window: w, document: w.document, setInterval: (f) => timers.push(f), clearInterval: none, setTimeout, clearTimeout, Date: clock, console });
  return w;
}
// Saves and their answers are real requests: wait until a page has sent nothing new for a while.
async function settled(...pages) {
  let n = -1;
  while (n !== pages.reduce((a, w) => a + w.puts, 0)) { n = pages.reduce((a, w) => a + w.puts, 0); await sleep(250); }
}
const storeOf = (w) => Object.fromEntries(Object.keys(w.localStorage).map((k) => [k, w.localStorage.getItem(k)]));
// A refused page asks for layout.js again; jsdom loads no script, so the host's file is handed over here.
const relayout = (w) => { w.DASH_LAYOUT = onDisk(); w.document.querySelector('script[src^="layout.js?"]').dispatchEvent(new w.Event('load')); };

test('a page behind a reset does not write its old widths back over it', async () => {
  fs.writeFileSync(path.join(dir, 'layout.js'), 'window.DASH_LAYOUT = {"projects": {"demo": {"rev": 5, "sizes": {"alerts": 2}}}};\n');
  const a = boot(), b = boot();
  assert.equal(a.document.getElementById('alerts').dataset.size, '2', 'both pages open on the saved width');
  // The owner resets the layout on one page...
  b.document.getElementById('reset-layout').click();
  await settled(b);
  assert.deepEqual(onDisk().projects.demo, { rev: 6 }, 'the reset is saved');
  // ...then changes a width on the other, which still holds the old layout.
  a.document.querySelector('#builds .sz button[data-s="3"]').click();
  await settled(a);
  assert.deepEqual(onDisk().projects.demo, { rev: 6 }, 'refused: the older page wrote nothing over the reset');
  assert.equal(a.puts, 1, 'and holds its change until it has read the host\'s layout');
  // issue 211: the refused page re-reads layout.js and sends only its own change again, over the reset.
  relayout(a);
  await settled(a);
  assert.deepEqual(onDisk().projects.demo, { rev: 7, sizes: { builds: 3 } }, 'the reset still stands, with the one width the older page changed');
  assert.equal(a.reloads, 0);
  assert.equal(a.document.getElementById('alerts').dataset.size, '4', 'the older page shows the reset width');
  // A reload shows the host's layout and sends nothing of its own.
  const again = boot(storeOf(a));
  await settled(again);
  assert.equal(again.document.getElementById('alerts').dataset.size, '4', 'the reloaded page shows the reset width');
  assert.equal(again.puts, 0);
  assert.equal(onDisk().projects.demo.rev, 7);
});

// Each project's page saves only that project's slot, so a save on one project's page leaves another's
// layout as its page loaded it: the other page's next change must still be saved, not dropped by a reload.
test("a save on one project's page refuses no change on another project's page", async () => {
  fs.writeFileSync(path.join(dir, 'layout.js'), 'window.DASH_LAYOUT = {"projects": {"demo": {}, "other": {}}, "rev": 1};\n');
  const a = boot({}, 'demo'), b = boot({}, 'other');
  a.document.querySelector('#alerts .sz button[data-s="2"]').click();
  await settled(a);
  b.document.querySelector('#builds .sz button[data-s="3"]').click();
  await settled(b);
  assert.equal(b.reloads, 0, 'the other project\'s page keeps its change');
  assert.equal(onDisk().projects.other.sizes.builds, 3, 'and the host saved it');
  assert.equal(onDisk().projects.demo.sizes.alerts, 2, 'the first project\'s change still stands');
});

// A snapshot as the collector writes it, one project named demo; `p` is that project's part.
const NOW = Date.now();
const iso = (ms) => new Date(ms).toISOString();
const REPO = 'https://github.com/example/demo';
function show(w, p, sources = {}) {
  const s = w.document.querySelector('script[src^="data.js"]');
  w.DASH = { updatedAt: iso(NOW), home: 'demo', sources, projects: { demo: p } };
  s.dispatchEvent(new w.Event('load'));
}
const fresh = (clock) => { fs.writeFileSync(path.join(dir, 'layout.js'), 'window.DASH_LAYOUT = {"projects": {"demo": {}}, "rev": 1};\n'); return boot({}, 'demo', clock); };
const builder = (over = {}) => ({
  unit: 'batch-g', branch: 'work/batch-g', dirty: 17, diffStat: '13 files changed, 231 insertions(+), 56 deletions(-)', agents: 'claude:working',
  stage: 'building', stageSince: iso(NOW - 24 * 60000), ageSec: 9, seat: { model: 'claude-opus-5-5', effort: 'medium' },
  builder: { steps: [], signals: [], issues: [12, 'write the docs'], built: [], verdict: null, verdictRound: null, waiting: [] }, ...over,
});
const text = (el) => el.textContent.replace(/\s+/g, ' ').trim();

test('an issue number in Issue by issue opens that issue on GitHub in a new tab; text items stay text', () => {
  const w = fresh();
  show(w, { units: { inFlight: [builder()] }, github: { repo: REPO, issues: [{ number: 12, title: 'Export times out' }] } });
  const a = w.document.querySelector('#builds .iss a');
  assert.equal(a.href, `${REPO}/issues/12`);
  assert.equal(a.target, '_blank');
  assert.equal(a.rel, 'noopener');
  assert.equal(a.textContent, '#12');
  assert.equal(a.title, 'Export times out');
  assert.equal(w.document.querySelector('#builds .iss .item').localName, 'span', 'an item with no issue number is not a link');
  // No GitHub address known (no origin, or one that is not github.com): the number is plain text.
  const v = fresh();
  show(v, { units: { inFlight: [builder()] }, github: { repo: 'https://evil.example/x/y', issues: null } });
  assert.equal(v.document.querySelector('#builds .iss a'), null);
  assert.equal(v.document.querySelector('#builds .iss span').textContent, '#12');
});

test('the unit card is a run trace: state in words, the diff once, a quiet gap, one row per helper run', () => {
  const w = fresh();
  const at = (min) => iso(NOW - min * 60000);
  show(w, { units: { inFlight: [builder({ ageSec: 840, builder: { ...builder().builder, signals: [{ kind: 'quiet', since: 0 }], steps: [
    { kind: 'codex', pass: 'adversarial', round: 1, start: at(5), end: null, rc: null },
    { kind: 'subagent', type: 'Explore', model: 'claude-haiku-5-5', tokens: { input: 61402, output: 4910 }, start: at(20), stop: at(18) },
    { kind: 'subagent', type: 'Plan', model: 'claude-sonnet-5-5', tokens: { input: 1, output: 1 }, start: at(70), stop: at(65) },
  ] } })] } });
  const card = w.document.querySelector('#units li.unit');
  assert.ok(card.classList.contains('quiet'));
  assert.equal(text(card.querySelector('.state')), 'Quiet for 14 min');
  assert.equal(text(card.querySelector('.seat')), 'Builder, Opus 5.5, medium effort');
  assert.deepEqual([...card.querySelectorAll('.ufacts > div')].map((d) => [text(d.firstChild), text(d.lastChild)]),
    [['Building', '24 min'], ['Last sign', '14 min ago'], ['13 files', '+231 −56'], ['Not committed', '17']]);
  assert.ok(!text(card).includes('insertions'), 'the diff stat is shown once, as the files fact');
  assert.ok(card.querySelector('.ufacts .hot'), 'a quiet Builder\'s last sign stands out');
  assert.ok(card.querySelector('.lane.pulse .gap'), 'the silence since the last sign is drawn');
  const rows = [...card.querySelectorAll('.trace .lab')].map(text);
  assert.deepEqual(rows, ['Stage', 'Last sign', 'Codex adversarial, round 1', 'Explore Haiku 5.5', 'Plan Sonnet 5.5'], 'a run 70 minutes old is drawn');
  assert.deepEqual([...card.querySelectorAll('.trace .num:not(.headnums)')].map((n) => [...n.children].map((c) => c.textContent)),
    [['', '', 'running'], ['61,402', '4,910', '2:00'], ['1', '1', '5:00']]);
  assert.ok(card.querySelector('.lane .h.codex.live'), 'a pass still running reaches now');
  assert.equal(card.querySelector('.tmore'), null, 'no "earlier runs" note: no run is left off the clock');
  assert.equal(text(card.querySelector('.branch')), 'Branch work/batch-g, agents claude:working');
});

// #95: the clock runs from the build's own start to now. A fixed clock keeps the tick labels off a minute's edge.
class Fixed extends Date { constructor(...a) { super(...(a.length ? a : [NOW])); } static now() { return NOW; } }
const pad2 = (n) => String(n).padStart(2, '0');
const hm = (ms) => { const d = new Date(ms); return `${d.getHours() % 12 || 12}:${pad2(d.getMinutes())} ${d.getHours() < 12 ? 'AM' : 'PM'}`; };
const ago = (min) => NOW - min * 60000;
// trace <unit> -> [axis labels, the stage band's left, each helper bar's left]
function trace(u) {
  const w = fresh(Fixed);
  show(w, { units: { inFlight: [u] } });
  const card = w.document.querySelector('#units li.unit');
  assert.ok(!card.innerHTML.includes('NaN'), 'every position is a number');
  return [[...card.querySelectorAll('.trace .axis span')].map(text), card.querySelector('.lane.stages i')?.style.left ?? null,
    [...card.querySelectorAll('.lane .h')].map((b) => b.style.left)];
}
const run = (startMin, stopMin) => ({ kind: 'subagent', type: 'Explore', model: 'claude-haiku-5-5', tokens: { input: 1, output: 1 }, start: iso(ago(startMin)), stop: iso(ago(stopMin)) });

test('the build timeline starts when the build started and ends now, in four equal parts', () => {
  const old = trace(builder({ stageSince: iso(ago(30)), builder: { ...builder().builder, startedAt: iso(ago(90)), steps: [run(45, 40)] } }));
  assert.deepEqual(old[0], [hm(ago(90)), hm(ago(67.5)), hm(ago(45)), hm(ago(22.5)), `now ${hm(NOW)}`], 'a 90-minute build: its start, then equal quarters to now');
  assert.equal(old[1], '66.7%', 'the stage band starts 60 of the 90 minutes in');
  assert.deepEqual(old[2], ['50%'], 'a run 45 minutes back sits halfway');
  const young = trace(builder({ stageSince: iso(ago(10)), builder: { ...builder().builder, startedAt: iso(ago(20)) } }));
  assert.equal(young[0][0], hm(ago(20)), 'a 20-minute build starts at its start, not 40 minutes back');
  assert.equal(young[1], '50%');
});

test('the timeline reaches back to a run older than the build start; no start keeps 40 minutes; a new build spans a second', () => {
  assert.equal(trace(builder({ builder: { ...builder().builder, startedAt: iso(ago(20)), steps: [run(70, 65)] } }))[0][0], hm(ago(70)),
    'a helper run that began before the build start is not hidden');
  assert.equal(trace(builder({ stageSince: iso(ago(24)) }))[0][0], hm(ago(24)), 'with no build start, the stage start');
  assert.equal(trace(builder({ stageSince: null }))[0][0], hm(ago(40)), 'with no start at all, the last 40 minutes');
  const now = trace(builder({ stageSince: iso(NOW), builder: { ...builder().builder, startedAt: iso(NOW) } }));
  assert.equal(now[0].at(-1), `now ${hm(NOW)}`, 'a build started this instant still draws, on a one-second span');
});

// #97: a machine on an API base URL (a proxy) has no usage windows: no 5-hour or 7-day figure, one note saying so.
test('API billing leaves out the usage-window tiles and says why; a subscription keeps them', () => {
  const w = fresh();
  // Codex's tile follows Codex's own sign-in (the next test): none here.
  show(w, { limit: { billing: 'api', codexBilling: 'none', api: { spentUsd: 12, complete: true } } });
  const doc = w.document;
  assert.ok(!/7-day/.test(text(doc.getElementById('summary'))), 'no 7-day tile in the top strip');
  // The chart legend's 5-hour key is .sub-only, which the card's api class hides.
  assert.ok(doc.getElementById('limit').classList.contains('api'));
  assert.ok(!/5-hour/.test(text(doc.getElementById('limit-facts')) + text(doc.getElementById('limit-tiles'))), 'no 5-hour figure in the limit card');
  assert.match(text(doc.getElementById('limit-note')), /^API billing: no usage windows\. /);
  const v = fresh();
  show(v, { limit: { billing: 'subscription', usedPct: 40, fiveHour: { usedPct: 10 } } });
  assert.match(text(v.document.getElementById('summary')), /Claude 7-day/);
  assert.match(text(v.document.getElementById('limit-facts')), /5-hour/);
});

// Issue 226: the panel names the account its figure is for, so a switched login cannot pass for the old one.
test('the limit panel names the signed-in account, masked, in either billing mode', () => {
  const w = fresh();
  show(w, { limit: { billing: 'subscription', usedPct: 40, accountLabel: 'b…@example.org' } });
  assert.match(text(w.document.getElementById('limit-who')), /b…@example\.org/);
  const v = fresh();
  show(v, { limit: { billing: 'api', codexBilling: 'none', api: { spentUsd: 12, complete: true }, accountLabel: 'b…@example.org' } });
  assert.match(text(v.document.getElementById('limit-who')), /b…@example\.org/);
  const u = fresh();
  show(u, { limit: { billing: 'subscription', usedPct: 40, accountLabel: null } });
  assert.equal(text(u.document.getElementById('limit-who')), 'Claude and Codex', 'no label read: the plain title');
});

// A 7-day tile is for a provider used through a subscription, the only case with a 7-day window: elsewhere it
// was a dead "not measured" box. Claude's follows its billing, Codex's its sign-in; a failed read on a
// subscription, or a sign-in that could not be read, still shows the tile as not measured, never hides it.
test('each 7-day tile shows only on a subscription; a failed read there still shows it, not measured', () => {
  const strip = (limit) => { const w = fresh(); show(w, { limit }); return w.document.getElementById('summary'); };
  const tile = (el, name) => [...el.querySelectorAll('.measure')].find((m) => text(m).startsWith(name)) || null;
  let s = strip({ billing: 'api', codexBilling: 'api', api: { spentUsd: 12, complete: true } });
  assert.equal(tile(s, 'Claude 7-day'), null, 'API-billed Claude: no Claude tile');
  assert.equal(tile(s, 'Codex 7-day'), null, 'Codex on an API key: no Codex tile');
  s = strip({ billing: 'api', codexBilling: 'none' });
  assert.equal(tile(s, 'Claude 7-day'), null, 'API billing with no API figures yet: still no Claude tile');
  assert.equal(tile(s, 'Codex 7-day'), null, 'no Codex sign-in: no Codex tile');
  s = strip({ billing: 'subscription', usedPct: 40, codexBilling: 'subscription', codex: { usedPct: 20 } });
  assert.match(text(tile(s, 'Claude 7-day')), /40%/, 'subscription with a reading: unchanged');
  assert.match(text(tile(s, 'Codex 7-day')), /20%/);
  s = strip({ billing: 'subscription', usedPct: null, codexBilling: 'subscription', codex: { usedPct: null } });
  assert.ok(tile(s, 'Claude 7-day').classList.contains('nm'), 'a failed Claude read on a subscription: shown, not measured');
  assert.ok(tile(s, 'Codex 7-day').classList.contains('nm'), 'a failed Codex read on a subscription: shown, not measured');
  s = strip({ billing: 'api', codexBilling: null, api: { spentUsd: 12, complete: true } });
  assert.ok(tile(s, 'Codex 7-day').classList.contains('nm'), 'a Codex sign-in that could not be read: shown, not measured');
});

const pr = (n, over) => ({ number: n, title: `PR ${n}`, url: `${REPO}/pull/${n}`, draft: false, branch: `work/b${n}`, review: 'APPROVED', mergeable: 'MERGEABLE', mergeState: 'CLEAN',
  additions: 3, deletions: 1, closes: [], checks: [{ name: 'lint', state: 'pass' }, { name: 'test', state: 'pass' }], ...over });
const GH = {
  repo: REPO,
  prs: [pr(7, { closes: [12], branch: 'work/batch-g', checks: [{ name: 'lint', state: 'pass' }, { name: 'test', state: 'fail' }] }), pr(8), pr(9, { draft: true })],
  issues: [{ number: 12, title: 'Export times out', url: `${REPO}/issues/12`, priority: 'P1', milestone: '2.4' },
    { number: 13, title: 'Login loops', url: `${REPO}/issues/13`, priority: 'P1', milestone: '2.4' },
    { number: 14, title: 'Dark mode', url: `${REPO}/issues/14`, priority: 'P3', milestone: null }],
  milestones: [{ title: '2.4', due: '2026-10-17T07:00:00Z', open: 2, closed: 6 }],
  runs: [{ conclusion: 'success', status: 'completed', createdAt: iso(NOW - 38 * 60000), workflow: 'ci' }],
};
const PUSH = { upstream: 'origin/main', ahead: 2, behind: 0, commits: [
  { sha: 'a41c9e2', at: (NOW - 600000) / 1000, subject: 'Stream audit rows', refs: [12], added: 188, deleted: 61 },
  { sha: 'b7710ce', at: (NOW - 3600000) / 1000, subject: 'Bump the lint config', refs: [], added: 31, deleted: 28 }] };

test('Merge line: ready pull requests first, each blocked one names what blocks it, each links to GitHub', () => {
  const w = fresh();
  show(w, { units: { inFlight: [builder()] }, github: GH });
  const rows = [...w.document.querySelectorAll('#merge-line-list > li')].map((li) => (li.classList.contains('group') ? text(li) : `#${text(li.querySelector('.num')).slice(1)} ${text(li.querySelector('.block'))}`));
  assert.deepEqual(rows, ['Ready to merge', '#8 Approved, merges cleanly', 'Blocked', '#7 test failed', '#9 Still a draft']);
  const a = w.document.querySelector('#merge-line-list a.pr');
  assert.equal(a.href, `${REPO}/pull/8`);
  assert.equal(a.rel, 'noopener');
  assert.deepEqual([...w.document.querySelectorAll('#merge-line-list a.pr')[1].querySelectorAll('.checks i')].map((i) => i.className), ['g', 'r']);
  assert.match(text(w.document.querySelectorAll('#merge-line-list a.pr')[1].querySelector('.by')), /^batch-g, closes #12, work\/batch-g/);
  assert.equal(text(w.document.getElementById('merge-line-sub')), '1 ready · 1 failing · 1 waiting');
});

test("Merge line: approved and conflict-free is not ready while the branch's rules block the merge", () => {
  const w = fresh();
  show(w, { github: { ...GH, prs: [pr(8, { mergeState: 'BLOCKED', checks: [] }), pr(10, { mergeState: 'BEHIND' })] } });
  const rows = [...w.document.querySelectorAll('#merge-line-list > li')].map((li) => (li.classList.contains('group') ? text(li) : `#${text(li.querySelector('.num')).slice(1)} ${text(li.querySelector('.block'))}`));
  assert.deepEqual(rows, ['Blocked', "#8 Blocked by the branch's rules", '#10 Behind its base branch']);
});

test('Who holds what: issues by milestone, most urgent first, with the Builder holding each and the urgent ones nobody holds', () => {
  const w = fresh();
  show(w, { units: { inFlight: [builder()] }, github: GH });
  assert.equal(text(w.document.getElementById('held-alarm')), '1 urgent issue nobody holds');
  const miles = [...w.document.querySelectorAll('#held-list .mile')];
  assert.deepEqual(miles.map((m) => text(m.querySelector('h3'))), ['2.4due Oct 17', 'No milestone1 open']);
  assert.equal(text(miles[0].querySelector('.prog-note')), '6 of 8 closed, 1 held, 1 free');
  assert.deepEqual([...miles[0].querySelectorAll('.issue')].map((li) => [text(li.querySelector('.pri')), li.querySelector('.inum').textContent, text(li.querySelector('.holder'))]),
    [['P1', '#12', 'batch-g'], ['P1', '#13', 'Nobody']]);
  assert.match(text(miles[0].querySelector('.issue small')), /^PR #7: test failed$/);
  assert.equal(text(miles[1].querySelector('.holder')), 'Free');
});

// Issue 273: how fast issues come and go, without opening GitHub.
test("issue 273: the Issues card's 24-hour line and the 7-day opened and closed sparkline", () => {
  const w = fresh();
  const daily = [0, 1, 2, 3, 4, 5, 6].map((i) => ({ day: `2026-10-${String(15 + i)}`, opened: i, closed: 6 - i }));
  show(w, { github: { ...GH, flow: { opened24h: 3, closed24h: 2, daily, incomplete: false } } });
  assert.equal(text(w.document.getElementById('held-flow')), '3 opened, 2 closed in 24 h');
  const lines = [...w.document.querySelectorAll('#held-spark svg polyline')];
  assert.deepEqual(lines.map((l) => [l.getAttribute('class'), l.getAttribute('points').split(' ').length]), [['spark-opened', 7], ['spark-closed', 7]]);
  for (const l of lines) assert.match(l.getAttribute('points'), /^[-0-9., ]*$/, 'only numbers reach the drawing');
  const full = fresh();
  show(full, { github: { ...GH, flow: { opened24h: 1000, closed24h: 0, daily, incomplete: true } } });
  assert.match(text(full.document.getElementById('held-flow')), /^1000 opened, 0 closed in 24 h\. A read hit its 1000-issue limit/);
  const none = fresh();
  show(none, { github: { ...GH, flow: null } });
  assert.equal(text(none.document.getElementById('held-flow')), 'Issues opened and closed not measured');
  assert.equal(none.document.querySelector('#held-spark svg'), null, 'no drawing from nothing');
});

test('Who holds what: a long Builder name never squeezes the issue number and title', () => {
  const w = fresh();
  show(w, { units: { inFlight: [builder({ unit: 'help-email-batch-2026-10-16' })] }, github: GH });
  const li = w.document.querySelector('#held-list .issue');
  const holder = li.querySelector('.holder');
  assert.equal(holder.title, 'help-email-batch-2026-10-16', 'the whole name shows on hover');
  const css = fs.readFileSync(path.join(ROOT, 'dashboard', 'app.css'), 'utf8');
  // jsdom lays nothing out, so the rules that keep the row whole are read from the sheet.
  assert.match(css, /\.issues li \{[^}]*grid-template-columns: 28px minmax\(10em, 1fr\) minmax\(0, max-content\)/, 'the title column keeps its width; the holder column gives way');
  assert.doesNotMatch(css, /\.issues \.t \{[^}]*overflow-wrap: anywhere/, 'a title never breaks between any two letters');
  assert.match(css, /\.holder \{[^}]*white-space: nowrap; overflow: hidden; text-overflow: ellipsis/, 'a long name is cut short on one line');
});

test('Next push: the commits under the issue each names, and what should stop the push first', () => {
  const w = fresh();
  show(w, { units: { inFlight: [] }, github: GH, nextPush: PUSH });
  assert.equal(text(w.document.getElementById('next-push-verdict')),
    "2commitsCheck before pushing: 1 commit names no issue; #12's pull request #7 is blocked: test failed.Names #12. Last CI on origin/main: success, 38 min ago.");
  const groups = [...w.document.querySelectorAll('#next-push-list .push-issue')];
  assert.deepEqual(groups.map((g) => text(g.querySelector('h3'))), ['#12 Export times out', 'No issue named']);
  assert.equal(groups[0].querySelector('h3 a').href, `${REPO}/issues/12`);
  assert.deepEqual([...groups[1].querySelectorAll('.commit')].map((li) => [...li.children].map((c) => c.textContent)), [['b7710ce', 'Bump the lint config', '+31', '−28', '60 min']]);
});

test('with gh not signed in each GitHub pane says so, and the rest of the page is still drawn', () => {
  const w = fresh();
  const why = { sampledAt: null, status: 'not-measured', staleSince: null, error: 'gh is not signed in: run gh auth login; nothing was cached' };
  show(w, { units: { inFlight: [builder()] }, github: { repo: REPO, prs: null, issues: null, milestones: null, runs: null }, nextPush: PUSH },
    { 'github-prs': why, 'github-issues': why, 'github-milestones': why, 'github-runs': why });
  assert.equal(text(w.document.querySelector('#merge-line .card-note')), 'Pull requests not read: gh is not signed in: run gh auth login; nothing was cached');
  assert.equal(text(w.document.querySelector('#held .card-note')), 'Issues not read: gh is not signed in: run gh auth login; nothing was cached');
  assert.equal(w.document.getElementById('merge-line').dataset.state, 'not-measured');
  assert.match(text(w.document.getElementById('next-push-verdict')), /Last CI run not read\.$/);
  assert.equal(w.document.querySelectorAll('#units li.unit').length, 1, 'the units are still drawn');
});

test('the GitHub panes are panels like the others: hidden through the same layout the host keeps', async () => {
  const w = fresh();
  for (const id of ['merge-line', 'held', 'next-push']) assert.ok(w.document.querySelector(`#${id} .card-head button[data-hide]`), `${id} has the panel controls`);
  w.document.querySelector('#held .card-head button[data-hide]').click();
  await settled(w);
  assert.deepEqual(onDisk().projects.demo.hidden, ['held']);
});

// A Builder's question to main is in the decisions ledger (waitsOn "main") so it is answered and closed like an
// owner's ask, but the owner's card must never ask the owner to answer it: listed apart, never counted.
test("a Builder's question waiting on main is listed apart on the owner's card and never counted as the owner's", () => {
  const owner = { id: 'deploy-2026-10-15', question: 'Deploy now?', proposedDefault: 'wait', source: 'main', askedAt: iso(NOW - 60000), answeredAt: null, answer: null };
  const builder = { id: 'u1-msg_q1', question: 'question (u1): which option?', proposedDefault: 'none', source: 'u1 asks', waitsOn: 'main', askedAt: iso(NOW - 60000), answeredAt: null, answer: null };
  const w = fresh();
  show(w, { needsOwner: { decisions: [owner, builder] } });
  assert.equal(w.document.querySelector('[data-count="decisions"]').textContent, '1', 'only the owner\'s question is counted');
  const items = [...w.document.querySelectorAll('#decisions li')].map((li) => `${li.className}: ${text(li).slice(0, 40)}`);
  assert.deepEqual(items, ['decision: Deploy now?If no answer: waitdeploy-2026', 'waiting-main-label: Waiting on main',
    'decision waiting-main: question (u1): which option?u1-msg_q1, f'], 'the Builder\'s question sits under its own label, with no default for the owner');
  const v = fresh();
  show(v, { needsOwner: { decisions: [builder] } });
  assert.equal(v.document.querySelector('[data-count="decisions"]').textContent, '0');
  assert.equal(text(v.document.querySelector('#decisions li')), 'No open decisions', 'nothing waits on the owner');
  assert.match(text(v.document.getElementById('summary')), /Waiting on the owner00 open decisions/, 'and the summary tile counts nothing for the owner');
});

// #94: a Builder's time and cost, per stage, from the collect's stageHistory and its unit cost.
const tally = (usd, over = {}) => ({ sec: 1800, calls: 4, input: 200000, cached: 150000, output: 3000, usd, partial: false, unpriced: [], ...over });
const UNPRICED = { partial: true, unpriced: ['claude-mystery-9-9'] };
const stage = (s, fromMin, toMin) => ({ stage: s, from: iso(ago(fromMin)), to: toMin === null ? null : iso(ago(toMin)) });
function costed(hist, costs, total) {
  return builder({ builder: { ...builder().builder, startedAt: hist[0].from, stageHistory: hist,
    cost: { stages: hist.map((g, i) => ({ ...g, ...costs[i] })), total } } });
}

test("a Builder's card gives its time and cost so far, and each stage's time and cost under the stage, an unpriced model named", () => {
  const w = fresh(Fixed);
  const hist = [stage('building', 90, 60), stage('review', 60, 30), stage('fixing', 30, null)];
  show(w, { units: { inFlight: [costed(hist, [tally(1.5), tally(0.25, UNPRICED), tally(0.4)], tally(2.15, { sec: 5400, ...UNPRICED }))] } });
  const card = w.document.querySelector('#units li.unit');
  assert.equal(text(card.querySelector('.ucost')),
    "Total time 1h 30m · Cost so far $2.15+ partial, claude-mystery-9-9 not priced (Claude not measured, Codex not measured) · main's own tokens not counted",
    'a total with an unpriced request is a floor and names the model, never a whole figure');
  assert.deepEqual([...card.querySelectorAll('.lane.stages i')].map((b) => [b.textContent, b.style.left]),
    [['Building', '0%'], ['In review', '33.3%'], ['Fixing', '66.7%']], 'one band per stage, where it ran');
  assert.deepEqual([...card.querySelectorAll('.lane.figs')].map((l) => [...l.children].map((i) => i.textContent)),
    [['30:00', '30:00', '30:00 so far'], ['$1.50', '$0.25+ partial, claude-mystery-9-9 not priced', '$0.40']], 'every stage is wide enough: its figures sit under it');
  assert.equal(card.querySelector('.stagelist'), null);
  // The Builds panel keeps the table: each stage, then the unit total.
  const rows = [...w.document.querySelectorAll('#builds table.costs tr')].map((r) => [...r.children].map(text));
  assert.deepEqual(rows.map((r) => [r[0], r[5]]), [['Stage', 'Cost'], ['Building', '$1.50'], ['In review', '$0.25+ partial, claude-mystery-9-9 not priced'],
    ['Fixing', '$0.40'], ['Unit total', '$2.15+ partial, claude-mystery-9-9 not priced']]);
  assert.deepEqual(rows[1].slice(1, 5), ['30:00', '4', '200,000 (75% cached)', '3,000']);
  assert.match(text(w.document.querySelector('#builds')), /Cost so far\$2\.15\+ partial/);
  assert.match(text(w.document.querySelector('#builds')), /main's own tokens are not counted/);
});

test("a Builder's cost splits between Claude and Codex, and the parts add up to the total", () => {
  const hist = [stage('building', 90, 60), stage('review', 60, 30), stage('fixing', 30, null)];
  const cost = (total) => {
    const w = fresh(Fixed);
    show(w, { units: { inFlight: [costed(hist, [tally(1), tally(1), tally(1)], total)] } });
    return [text(w.document.querySelector('#units li.unit .ucost')).replace(/^Total time \S+ \S+ · /, '').replace(/ · main's own.*/, ''),
      text(w.document.querySelector('#builds')).match(/Cost so far(.*?)Waiting on/)[1]];
  };
  const mixed = 'Cost so far $15.86 (Claude $12.10, Codex $3.76)';
  assert.deepEqual(cost(tally(15.86, { byAgent: { claude: 12.1, codex: 3.76 } })), [mixed, mixed.slice(12)], 'a mixed build, on the card and in the Builds panel');
  assert.equal(cost(tally(2, { byAgent: { claude: 2, codex: 0 } }))[0], 'Cost so far $2.00 (Claude $2.00, Codex $0.00)', 'Codex $0.00 only when no Codex call was made');
  assert.equal(cost(tally(1.5, { partial: true, unpriced: ['gpt-9-codex'], byAgent: { claude: 1.5, codex: null } }))[0],
    'Cost so far $1.50+ partial, gpt-9-codex not priced (Claude $1.50, Codex not priced)', 'an unpriced Codex call: that part is not priced, never $0, and the total stays partial');
  assert.equal(cost(tally(1))[0], 'Cost so far $1.00 (Claude not measured, Codex not measured)', 'a total collected before the split says so');
});

test('a stage too narrow for its figures moves every stage to a list under the bar; a wide band keeps its own and hovering marks its line', () => {
  const w = fresh(Fixed);
  const hist = [stage('building', 100, 20), stage('review', 20, 3), stage('fixing', 3, null)];
  show(w, { units: { inFlight: [costed(hist, [tally(3), tally(0.5), tally(0.05)], tally(3.55, { sec: 6000 }))] } });
  const card = w.document.querySelector('#units li.unit');
  assert.equal(card.querySelector('.lane.figs'), null, 'a 3-minute fix in a 100-minute build cannot hold its figures');
  // The list spans the card under the bar, one stage per line, then a Total row: in the bar's own column, two
  // to a line, a stage name wrapped one letter per line.
  const list = card.querySelector('.trace > .stagelist');
  assert.ok(list, 'the list is a row of the trace grid of its own, not inside the bar column');
  const lines = [...list.querySelectorAll('li:not(.total)')];
  assert.deepEqual(lines.map((l) => [...l.children].slice(1).map(text)),
    [['Building', '80:00', '$3.00'], ['In review', '17:00', '$0.50'], ['Fixing', '3:00 so far', '$0.05']], 'one line per stage, in the order they ran');
  assert.deepEqual([...list.lastChild.children].slice(1).map(text), ['Total', '1h 40m', '$3.55'], "a Total row closes the list: the build's time and cost");
  assert.ok(list.lastChild.classList.contains('total'));
  const css = fs.readFileSync(path.join(ROOT, 'dashboard', 'app.css'), 'utf8');
  assert.match(css, /\.trace \.stagelist \{[^}]*grid-column: 1 \/ -1/, 'the list spans the whole card');
  assert.match(css, /\.stagelist li \{[^}]*white-space: nowrap/, 'a stage name never wraps');
  const bands = [...card.querySelectorAll('.lane.stages i')];
  assert.equal(bands[0].textContent, 'Building 80:00 · $3.00', 'the wide band still says its own figures');
  assert.equal(bands[2].textContent, 'Fixing', 'the narrow band holds its name only');
  bands[2].dispatchEvent(new w.Event('mouseenter'));
  assert.deepEqual(lines.map((l) => l.classList.contains('hi')), [false, false, true]);
  bands[2].dispatchEvent(new w.Event('mouseleave'));
  assert.ok(!lines[2].classList.contains('hi'));
});

// a unit's planning is its Planning stage, seat by seat; what no seat claims is one row, so the rows sum to the stage.
const seats = [
  { role: 'plan-author', model: 'claude-opus-5-5', effort: 'high', from: iso(ago(120)), to: iso(ago(100)), ...tally(0.3, { sec: 1200, calls: 3 }) },
  { role: 'plan-judge-sol', model: 'gpt-6.1-sol', effort: 'high', from: iso(ago(110)), to: null, ...tally(0, { sec: 600, calls: 1, input: 1000, output: 10 }) },
  { role: null, model: null, effort: null, from: null, to: null, ...tally(0.1, { sec: 0, calls: 1 }) }];
const seatRows = (card) => [...card.querySelectorAll('.stagelist.seats li')].map((l) => [...l.children].slice(1).map(text));
const SEAT_ROWS = [['plan-author', 'claude-opus-5-5 high', '3 calls', '200,000 in / 3,000 out', '$0.30', '20:00'],
  ['plan-judge-sol, running', 'gpt-6.1-sol high', '1 calls', '1,000 in / 10 out', '$0.00', '10:00 so far'],
  ['Not tied to a seat', '', '1 calls', '200,000 in / 3,000 out', '$0.10', '']];
test("a unit's planning card is its Planning stage: its time and cost, its cost by stage and one row per seat", () => {
  const w = fresh(Fixed);
  const cost = { stages: [{ ...stage('planning', 120, null), ...tally(0.4, { calls: 5 }) }], total: tally(0.4, { sec: 7200, calls: 5 }), seats };
  show(w, { units: { inFlight: [{ unit: 'pw-plan', stage: 'planning', stageSince: iso(ago(120)), ageSec: 60, agents: 'claude:idle', builder: null,
    plan: { worktree: '/ws/pw-plan', from: iso(ago(120)), seats: [], cost } }] } });
  const card = w.document.querySelector('#units li.unit');
  assert.equal(text(card.querySelector('.unit-head .state')), 'Planning');
  assert.equal(text(card.querySelector('.ucost')), "Total time 2h 00m · Cost so far $0.40 (Claude not measured, Codex not measured) · main's own tokens not counted");
  assert.deepEqual([...card.querySelectorAll('table.costs tr')].map((r) => [...r.children].map(text)).map((r) => [r[0], r[2], r[5]]),
    [['Stage', 'Model calls', 'Cost'], ['Planning', '5', '$0.40'], ['Unit total', '5', '$0.40']], 'its cost by stage, the planning stage alone');
  assert.deepEqual(seatRows(card), SEAT_ROWS, 'one row per seat, and what no seat claims in one row');
});

// Two plan seats at once: the collector's `seat` is only the newest, so a card drawn from it hides the other (issue 168).
test('a planning card names every plan seat with its model, effort and state, and its Planning figures while they run', () => {
  const w = fresh(Fixed);
  const cost = { stages: [{ ...stage('planning', 120, null), ...tally(0.4, { calls: 5 }) }], total: tally(0.4, { sec: 7200, calls: 5 }), seats };
  const planSeats = [
    { role: 'plan-author', task: 't1', from: iso(ago(120)), model: 'claude-opus-5-5', effort: 'high', session: 's1', completedAt: iso(ago(100)) },
    { role: 'plan-judge-sol', task: 't2', from: iso(ago(110)), model: 'gpt-6.1-sol', effort: null, session: null, completedAt: null }];
  show(w, { units: { inFlight: [{ unit: 'pw-plan', stage: 'planning', stageSince: iso(ago(5)), ageSec: 60, agents: 'codex:working', builder: null,
    seat: { model: 'gpt-6.1-sol', effort: 'high' }, plan: { worktree: '/ws/pw-plan', from: iso(ago(120)), seats: planSeats, cost } }] } });
  const card = w.document.querySelector('#units li.unit');
  assert.equal(text(card.querySelector('.unit-head .seat')),
    'plan-author, Opus 5.5, high effort, done · plan-judge-sol, gpt-6.1-sol, effort not recorded, running', 'every seat, not only the newest');
  assert.deepEqual([...card.querySelectorAll('.lane.figs')].map((l) => [...l.querySelectorAll('i')].map(text)), [['120:00 so far'], ['$0.40']],
    'the Planning stage carries its time and cost from the first launch');
});

test("a Builder's card draws its planning first, and lists the planning's seats", () => {
  const w = fresh(Fixed);
  const hist = [stage('planning', 120, 90), stage('building', 90, 30), stage('review', 30, null)];
  const u = costed(hist, [tally(0.4, { calls: 5 }), tally(1), tally(0.5)], tally(1.9, { sec: 7200 }));
  u.builder.cost.seats = seats;
  show(w, { units: { inFlight: [u] } });
  const card = w.document.querySelector('#units li.unit');
  assert.deepEqual([...card.querySelectorAll('.lane.stages i')].map((b) => [b.textContent.split(' ')[0], b.style.left]),
    [['Planning', '0%'], ['Building', '25%'], ['In', '75%']], 'the planning segment first, from the build clock start');
  assert.deepEqual(seatRows(card), SEAT_ROWS);
});

test("a finished build keeps the cost it had at its merge; one with none kept says so, never $0", () => {
  const w = fresh(Fixed);
  const fin = (unit, sha, cost) => ({ unit, sha, at: iso(ago(5)), how: 'merged', open: { P1: 0, P2: 0, P3: 0 }, cost });
  const cost = { stages: [{ ...stage('building', 120, 60), ...tally(4) }, { ...stage('review', 60, null), ...tally(1.25) }], total: tally(5.25, { sec: 7200 }) };
  show(w, { units: { inFlight: [], finishedBuilds: [fin('done-a', 'aaaaaaaa1', cost), fin('done-b', 'bbbbbbbb2', null)] } });
  const [a, b] = [...w.document.querySelectorAll('#builds .build')];
  assert.match(text(a), /Cost\$5\.25 in 2h 00m/);
  assert.deepEqual([...a.querySelectorAll('table.costs tr')].map((r) => text(r.children[5])), ['Cost', '$4.00', '$1.25', '$5.25']);
  assert.match(text(b), /Costnot recorded/);
  assert.match(text(b), /Cost by stage not recorded/);
  assert.equal(b.querySelector('table.costs'), null);
});

// Issue 322: every finding blocks the merge, so nothing is open at a merge and the merge records no open counts.
// A finished build names no open findings, not even "not recorded", and an older record's counts are not shown.
test('a finished build names no findings open at its merge, from a record with counts or without', () => {
  const w = fresh(Fixed);
  const fin = (unit, sha, open) => ({ unit, sha, at: iso(ago(5)), how: 'merged', ...(open && { open }), cost: null });
  show(w, { units: { inFlight: [], finishedBuilds: [fin('done-a', 'aaaaaaaa1'), fin('done-b', 'bbbbbbbb2', { P1: 1, P2: 2, P3: 0 })] } });
  for (const b of w.document.querySelectorAll('#builds .build')) {
    assert.doesNotMatch(text(b), /open at merge|open findings|nothing open|P2 2/i, `${b.dataset.unit} names no open findings`);
    assert.equal(b.querySelector('.warn'), null, `${b.dataset.unit}: its Merge step is not amber`);
  }
  assert.doesNotMatch(text(w.document.getElementById('needs-facts')), /on finished builds/, 'no open P1 count from finished builds');
});

// The helper rows took most of a card. The card keeps its Stage band and the stages'
// time and cost in view, and a closed Details holds the activity: the last sign, each helper run and the clock.
test('a unit card keeps Stage and its figures in view and folds the activity rows behind a closed Details', () => {
  const w = fresh(Fixed);
  const hist = [stage('building', 90, 60), stage('review', 60, 30), stage('fixing', 30, null)];
  const u = costed(hist, [tally(1.5), tally(0.25), tally(0.4)], tally(2.15, { sec: 5400 }));
  u.builder.steps = [{ kind: 'codex', pass: 'adversarial', round: 1, start: iso(ago(60)), end: iso(ago(30)), rc: 0 },
    { kind: 'subagent', type: 'Explore', model: 'claude-haiku-5-5', tokens: { input: 1, output: 1 }, start: iso(ago(80)), stop: iso(ago(75)) }];
  show(w, { units: { inFlight: [u] } });
  const card = w.document.querySelector('#units li.unit');
  const shown = card.querySelector(':scope > .trace');
  assert.ok(shown.querySelector('.lane.stages'), 'the Stage band stays in view');
  assert.equal(shown.querySelectorAll('.lane.figs').length, 2, 'with its time and cost');
  assert.doesNotMatch(text(shown), /Last sign|Explore|Codex adversarial/, 'no activity row outside Details');
  const more = card.querySelector(':scope > details.unit-more');
  assert.ok(more && !more.open, 'Details is closed');
  assert.equal(text(more.querySelector('summary')), 'Details');
  assert.deepEqual([...more.querySelectorAll('.trace .lab')].map(text), ['Last sign', 'Codex adversarial, round 1', 'Explore Haiku 5.5']);
  assert.ok(more.querySelector('.trace .axis'), 'the clock goes with the rows it times');
});

// Every finished Codex pass names its own verdict in the stage list, read from its own
// round file (builder.verdicts, by round); a pass still running says so, and one with no round file names none.
const judged = (hist, verdicts) => { const u = costed(hist, hist.map(() => tally(0.5)), tally(3, { sec: 6000 })); u.builder.verdicts = verdicts; return u; };
test("a Builder's card shows its live context against its clear line; past it, off and not measured each say so", () => {
  const ctx = (over) => { const w = fresh(); show(w, { units: { inFlight: [builder({ builder: { ...builder().builder, ...over } })] } });
    const el = w.document.querySelector('#units li.unit .uctx'); return [text(el), el.classList.contains('hot')]; };
  assert.deepEqual(ctx({ context: 150000, clearLine: '180000' }), ['Context 150K of the 180K clear line', false]);
  assert.deepEqual(ctx({ context: 191000, clearLine: '180000' }), ['Context 191K, past the 180K clear line', true]);
  assert.deepEqual(ctx({ context: 150000, clearLine: 'off' }), ['Context 150K, clear line off', false]);
  assert.deepEqual(ctx({}), ['Context not measured', false]);
});

test('every finished Codex pass in the stage list reads its own round\'s verdict; a running one reads running', () => {
  const w = fresh(Fixed);
  const hist = [stage('building', 100, 12), { ...stage('review', 12, 10), round: 1 }, stage('fixing', 10, 8), { ...stage('review', 8, 6), round: 2 },
    stage('fixing', 6, 5), { ...stage('review', 5, 4), round: 3 }, stage('fixing', 4, 2), { ...stage('review', 2, null), round: 4 }];
  show(w, { units: { inFlight: [judged(hist, { 1: 'VERDICT: NO-GO', 2: 'VERDICT: GO', 4: 'VERDICT: GO' })] } });
  const names = [...w.document.querySelectorAll('#units li.unit .trace > .stagelist li:not(.total)')].map((l) => text(l.children[1]));
  assert.deepEqual(names, ['Building', 'Codex pass 1 · NO-GO', 'Fixing', 'Codex pass 2 · GO', 'Fixing', 'Codex pass 3', 'Fixing', 'Codex pass 4 running'],
    'pass 3 has no round file, and pass 4 is still running: an older file of its number is not its verdict');
});

test('a finished pass shows its verdict when every stage is wide: the verdict takes the stage list', () => {
  const w = fresh(Fixed);
  const hist = [stage('building', 100, 60), { ...stage('review', 60, 30), round: 1 }, stage('fixing', 30, null)];
  show(w, { units: { inFlight: [judged(hist, { 1: 'VERDICT: NO-GO' })] } });
  const list = w.document.querySelector('#units li.unit .trace > .stagelist');
  assert.ok(list, 'a named verdict shows only in the list');
  assert.match(text(list), /Codex pass 1 · NO-GO/);
});

// Builds in progress ran a screen tall with two or three builds, and a finished build took a running one's space.
// Each build folds to one line on its own toggle, a finished one folds by itself, and the owner's choice is kept
// with the panel layout, so neither a refresh nor a reload undoes it.
test('each build folds to one line on its own toggle; a finished one folds itself; the choice outlives a refresh and a reload', async () => {
  const w = fresh(Fixed);
  const fin = (unit, sha) => ({ unit, sha, at: iso(ago(5)), how: 'merged', open: { P1: 0, P2: 0, P3: 0 }, cost: { stages: [], total: tally(5.25, { sec: 7200 }) } });
  const raised = builder({ unit: 'batch-h', builder: { ...builder().builder, built: [12], raised: { effort: 'high', reason: 'touches billing' } }, seat: { model: 'claude-opus-5-5', effort: 'high' } });
  const running = { units: { inFlight: [builder(), raised], finishedBuilds: [fin('done-a', 'aaaaaaaa1')] } };
  show(w, running);
  const builds = () => Object.fromEntries([...w.document.querySelectorAll('#builds .build')].map((b) => [b.dataset.unit, b]));
  const shut = () => Object.fromEntries(Object.entries(builds()).map(([u, b]) => [u, b.classList.contains('shut')]));
  assert.deepEqual(shut(), { 'batch-g': false, 'batch-h': false, 'done-a': true }, 'running builds open; a finished one folded by itself');
  const line = (u) => text(builds()[u].querySelector('.line'));
  assert.equal(line('batch-h'), 'batch-h · Opus 5.5, high effort, raised by main · Building · 1 of 2 built · cost not recorded · last sign 9 s ago',
    'the one line: name, seat, stage, issues built, cost so far, last sign');
  assert.equal(line('done-a'), 'done-a · seat not recorded · merged · issues not recorded · cost $5.25 · merged 5 min ago');
  const css = fs.readFileSync(path.join(ROOT, 'dashboard', 'app.css'), 'utf8');
  assert.match(css, /\.build\.shut > :not\(\.uline\):not\(\.line\) \{[^}]*display: none/, 'folded, a build shows its header row and its one line only');
  assert.match(css, /\.build:not\(\.shut\) > \.line \{[^}]*display: none/, 'open, the one line is not repeated');
  const toggle = (u) => builds()[u].querySelector('.uline button[data-fold]');
  assert.equal(toggle('batch-g').getAttribute('aria-expanded'), 'true');
  toggle('batch-g').click();
  assert.deepEqual(shut(), { 'batch-g': true, 'batch-h': false, 'done-a': true }, 'the toggle folds its own build and no other');
  assert.equal(toggle('batch-g').getAttribute('aria-expanded'), 'false');
  toggle('done-a').click();
  assert.ok(builds()['done-a'].querySelector('button[data-close]'), 'Close stays on a finished build');
  // A refresh: batch-h has finished since, and batch-g is still running.
  w.refresh();
  show(w, { units: { inFlight: [builder()], finishedBuilds: [fin('done-a', 'aaaaaaaa1'), fin('batch-h', 'hhhhhhhh2')] } });
  assert.deepEqual(shut(), { 'batch-g': true, 'batch-h': true, 'done-a': false },
    'a build that finished while the page was open folds itself; the owner\'s fold and unfold stand');
  await settled(w);
  assert.deepEqual(onDisk().projects.demo.builds, { 'batch-g': true, aaaaaaaa1: false }, 'the choice is saved with the panel layout');
  const again = boot(storeOf(w), 'demo', Fixed);
  show(again, { units: { inFlight: [builder()], finishedBuilds: [fin('done-a', 'aaaaaaaa1'), fin('batch-h', 'hhhhhhhh2')] } });
  assert.deepEqual(Object.fromEntries([...again.document.querySelectorAll('#builds .build')].map((b) => [b.dataset.unit, b.classList.contains('shut')])),
    { 'batch-g': true, 'batch-h': true, 'done-a': false }, 'a reload keeps every choice');
  // Close on a finished build is unchanged: it clears the build.
  again.document.querySelector('#builds .build[data-unit="done-a"] button[data-close]').click();
  assert.equal(again.document.querySelector('#builds .build[data-unit="done-a"]'), null);
});

test("a raised Builder's unit card says main raised its effort, with the reason on hover", () => {
  const w = fresh();
  show(w, { units: { inFlight: [builder({ seat: { model: 'claude-opus-5-5', effort: 'high' }, builder: { ...builder().builder, raised: { effort: 'high', reason: 'touches billing' } } })] } });
  const seat = w.document.querySelector('#units li.unit .seat');
  assert.equal(text(seat), 'Builder, Opus 5.5, high effort, raised by main');
  assert.equal(seat.title, 'effort raised by main: touches billing');
  const chip = w.document.querySelector('#builds .mdl.e');
  assert.equal(text(chip), 'effort high, raised by main');
  assert.equal(chip.title, 'effort raised by main: touches billing');
});

// issue 211: on a phone every panel was one long column. A bottom tab bar picks what shows; More reaches the rest.
// jsdom lays nothing out, so where the page's look is the point the phone rules are read from app.css.
const CSS = fs.readFileSync(path.join(ROOT, 'dashboard', 'app.css'), 'utf8');
const PHONE = (() => {
  const at = CSS.indexOf('@media (max-width: 760px) {');
  let i = CSS.indexOf('{', at), depth = 0;
  do { depth += { '{': 1, '}': -1 }[CSS[i]] || 0; i += 1; } while (depth);
  return CSS.slice(at, i);
})();
const tabOn = (w) => [...w.document.querySelectorAll('.card.tab-on')].map((c) => c.id);
const tabBtn = (w, t) => w.document.querySelector(`#tabs button[data-tab="${t}"]`);
const reshow = (w) => { w.refresh(); w.document.querySelector('script[src^="data.js"]').dispatchEvent(new w.Event('load')); };
// Two units in flight, one Builder working, two alerts (one about the 7-day limit), one decision waiting.
function phone() {
  const w = fresh();
  w.DASH = { updatedAt: iso(NOW), home: 'demo', sources: {},
    alerts: [{ id: 'limit-claude', severity: 'crit', text: 'over pace', since: iso(NOW) }, { id: 'host-load', severity: 'warn', text: 'busy', since: iso(NOW) }],
    projects: { demo: { units: { inFlight: [builder(), builder({ unit: 'batch-r', stage: 'review', agents: 'claude:idle' })] },
      needsOwner: { decisions: [{ id: 'd1', question: 'Ship?', proposedDefault: 'wait', askedAt: iso(NOW), answeredAt: null }] } } } };
  w.document.querySelector('script[src^="data.js"]').dispatchEvent(new w.Event('load'));
  return w;
}

test('issue 211: a phone has a bottom tab bar, each tab shows only its own panels, the current one marked', () => {
  const w = phone();
  assert.deepEqual([...w.document.querySelectorAll('#tabs .tab-label')].map((l) => l.textContent), ['Units', 'Builds', 'Alerts', 'You', 'More']);
  assert.deepEqual(tabOn(w), ['units'], 'the page opens on Units');
  for (const [t, want] of [['builds', ['builds']], ['alerts', ['alerts']], ['you', ['needs']], ['units', ['units']]]) {
    tabBtn(w, t).click();
    assert.deepEqual(tabOn(w), want, `${t} shows its own panels`);
    assert.equal(tabBtn(w, t).getAttribute('aria-current'), 'page');
    assert.equal(w.document.querySelectorAll('#tabs [aria-current]').length, 1, 'one tab is current');
  }
  tabBtn(w, 'alerts').click();
  reshow(w);
  assert.deepEqual(tabOn(w), ['alerts'], 'a refresh keeps the tab');
  assert.match(PHONE, /\.card:not\(\.tab-on\) \{ display: none; \}/, 'every panel off the tab is hidden');
  assert.match(PHONE, /#tabs \{[^}]*position: fixed;[^}]*bottom: 0;/, 'the bar is fixed to the bottom edge');
  assert.match(PHONE, /body \{ margin: [^;]*calc\(/, 'the page scrolls as a whole above a pad the bar\'s height');
  assert.match(PHONE, /#tabs button \{[^}]*min-height: 44px/, 'a tab is a 44 px touch target');
  assert.match(PHONE, /\.card \{ height: auto !important;[^}]*resize: none;/, 'a height dragged on a desktop is ignored on a phone');
  assert.doesNotMatch(CSS, /(html|body)[^{]*\{[^}]*overflow-x: hidden/, 'nothing hides a sideways overflow');
});

test('issue 211: More lists every other panel not hidden, shows the one picked alone, and closes on Escape', async () => {
  const w = phone();
  const sheet = w.document.getElementById('more-sheet');
  const tiles = () => [...w.document.querySelectorAll('#more-tiles button')];
  w.document.querySelector('#held .card-head button[data-hide]').click();
  await settled(w);
  assert.equal(sheet.hidden, true);
  tabBtn(w, 'more').click();
  assert.equal(sheet.hidden, false);
  assert.ok(sheet.contains(w.document.activeElement), 'the sheet takes focus');
  assert.deepEqual(tiles().map((b) => b.dataset.card), ['main-chain', 'merge-line', 'next-push', 'limit', 'todos', 'host', 'cost-role', 'cost-unit', 'review', 'guard-blocks',
    'chief-of-staff', 'main-seat', 'agents'], 'every panel on no tab, less the one the owner hid and the relay seat this project has not');
  assert.equal(tiles()[0].textContent, 'Main', 'a tile is its panel\'s title');
  w.document.dispatchEvent(new w.KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
  assert.equal(sheet.hidden, true, 'Escape closes it');
  assert.equal(w.document.activeElement, tabBtn(w, 'more'), 'and gives focus back to More');
  tabBtn(w, 'more').click();
  w.document.querySelector('#more-sheet [data-scrim]').click();
  assert.equal(sheet.hidden, true, 'a tap beside the sheet closes it');
  tabBtn(w, 'more').click();
  tiles().find((b) => b.dataset.card === 'limit').click();
  assert.equal(sheet.hidden, true);
  assert.deepEqual(tabOn(w), ['limit'], 'a tile shows its panel alone');
  assert.equal(tabBtn(w, 'more').getAttribute('aria-current'), 'page');
});

test('issue 211: on the units board a step chip leaves one stage; All shows every stage again', () => {
  const w = phone();
  const chips = () => [...w.document.querySelectorAll('#unit-steps button')];
  const on = () => [...w.document.querySelectorAll('#stages .step-on')].map((s) => s.dataset.stage);
  assert.deepEqual(chips().map((c) => c.textContent), ['Planning 0', 'Building 1', 'Review 1', 'Fixing 0', 'On main 0', 'All 2'], 'each chip counts its column');
  assert.equal(w.document.body.dataset.step, 'all');
  chips()[1].click();
  assert.deepEqual(on(), ['building']);
  assert.equal(chips()[1].getAttribute('aria-pressed'), 'true');
  reshow(w);
  assert.deepEqual(on(), ['building'], 'a refresh keeps the chip');
  chips()[5].click();
  assert.equal(w.document.body.dataset.step, 'all');
  assert.match(PHONE, /body:not\(\[data-step="all"\]\) #stages > \.stage:not\(\.step-on\)[^{]*\{ display: none; \}/, 'the CSS hides every other stage');
  assert.match(PHONE, /#stages \{ grid-template-columns: minmax\(0, 1fr\); \}/, 'the stages stack, never a sideways scroll');
  assert.match(PHONE, /#unit-steps \{[^}]*flex-wrap: wrap/, 'and the chips wrap');
});

test('issue 211: each tab badge is the count its summary tile shows, and empty when that is not measured', () => {
  const w = phone();
  const badge = (t) => w.document.querySelector(`#tabs [data-badge="${t}"]`).textContent;
  const tile = (panel) => w.document.querySelector(`#summary a[href="#${panel}"] .measure-value`).textContent;
  assert.deepEqual(['units', 'builds', 'alerts', 'you'].map(badge), ['2', '1', '2', '1']);
  for (const [t, panel] of [['units', 'units'], ['builds', 'builds'], ['alerts', 'alerts'], ['you', 'needs']]) assert.equal(badge(t), tile(panel), `${t} counts what its tile counts`);
  const v = fresh();
  show(v, {});
  assert.equal(v.document.querySelector('#tabs [data-badge="units"]').textContent, '', 'no number where the tile reads not measured');
});

test('issue 211: a summary tile or an alert link switches to the tab that holds its panel', () => {
  const w = phone();
  w.document.querySelector('#summary a[href="#needs"]').click();
  assert.deepEqual(tabOn(w), ['needs'], 'Waiting on the owner opens You');
  assert.equal(tabBtn(w, 'you').getAttribute('aria-current'), 'page');
  tabBtn(w, 'alerts').click();
  w.document.querySelector('#alerts-list a[href="#limit"]').click();
  assert.deepEqual(tabOn(w), ['limit'], 'a panel on no tab shows alone, as its More tile shows it');
  assert.equal(tabBtn(w, 'more').getAttribute('aria-current'), 'page');
});

test('issue 211: at desktop width no tab bar and no step chip show; only the phone rules show them', () => {
  const desk = CSS.replace(PHONE, '');
  assert.match(desk, /\n#tabs, #unit-steps \{ display: none; \}/);
  assert.doesNotMatch(desk, /#(tabs|unit-steps)[^{,]*\{[^}]*display: (?!none)/, 'no rule outside the phone block shows them');
  assert.match(PHONE, /#tabs \{ display: grid;/);
  assert.match(PHONE, /#unit-steps \{ display: flex;/);
});

// issue 211: a phone beside a PC. A save refused as out of date re-reads the host's layout, keeps this page's own
// change and the other page's, and goes again; the page used to reload and lose a build it had just cleared.
test('issue 211: a refused save re-reads the layout and merges it, keeping the other page\'s cleared build', async () => {
  fs.writeFileSync(path.join(dir, 'layout.js'), 'window.DASH_LAYOUT = {"projects": {"demo": {"rev": 3}}};\n');
  const fin = (unit, sha) => ({ unit, sha, at: iso(ago(5)), how: 'merged' });
  const snap = { units: { inFlight: [], finishedBuilds: [fin('done-a', 'aaaaaaaa1'), fin('done-b', 'bbbbbbbb2')] } };
  const a = boot(), b = boot();
  show(a, snap); show(b, snap);
  a.document.querySelector('#builds button[data-close="aaaaaaaa1"]').click();
  a.document.querySelector('#host .sz button[data-s="2"]').click();
  await settled(a);
  b.document.querySelector('#builds button[data-close="bbbbbbbb2"]').click();
  b.document.querySelector('#alerts .sz button[data-s="2"]').click();
  await settled(b);
  assert.equal(b.puts, 1, 'refused, and held until the host\'s layout is read');
  relayout(b);
  await settled(b);
  assert.equal(b.reloads, 0);
  const held = onDisk().projects.demo;
  assert.deepEqual(held.closed, ['aaaaaaaa1', 'bbbbbbbb2'], 'both pages\' cleared builds stand');
  assert.deepEqual([held.sizes.host, held.sizes.alerts], [2, 2], 'and both pages\' widths');
  assert.equal(b.document.querySelectorAll('#builds .build.finished').length, 0, 'the refused page shows the other\'s clear');
  assert.equal(b.document.getElementById('host').dataset.size, '2', 'and its width');
});

// r1 finding: a merge took the other page's folds into the saved layout but left this page's sections as they were,
// so this page's next fold, read off its own sections, sent the other page's fold back as open.
test('issue 211: a refused save shows the other page\'s folded sections, and a later fold keeps them', async () => {
  fs.writeFileSync(path.join(dir, 'layout.js'), 'window.DASH_LAYOUT = {"projects": {"demo": {"rev": 3}}};\n');
  const fold = (w, id) => { const d = w.document.getElementById(id); d.open = false; d.dispatchEvent(new w.Event('toggle')); };
  const a = boot(), b = boot();
  fold(a, 'limit-body');
  await settled(a);
  b.document.querySelector('#alerts .sz button[data-s="2"]').click();
  await settled(b);
  assert.equal(b.puts, 1, 'refused, and held until the host\'s layout is read');
  relayout(b);
  await settled(b);
  assert.equal(b.document.getElementById('limit-body').open, false, 'the refused page shows the other\'s fold');
  fold(b, 'permanent');
  await settled(b);
  assert.deepEqual([...onDisk().projects.demo.collapsed].sort(), ['limit-body', 'permanent'], 'both pages\' folds stand');
});

// Issue 217: the fold lists merged whole, so the page that saved last replaced the other page's folds. A fold list is
// merged as a set: the host's list, plus this page's additions, less its removals. `hidden` shares the cause.
test('issue 217: two pages folding at once keep both folds, and an unfold removes only that one', async () => {
  const fold = (w, id, open = false) => { const d = w.document.getElementById(id); d.open = open; d.dispatchEvent(new w.Event('toggle')); };
  fs.writeFileSync(path.join(dir, 'layout.js'), 'window.DASH_LAYOUT = {"projects": {"demo": {"rev": 3}}};\n');
  const a = boot(), b = boot();
  fold(a, 'limit-body');
  await settled(a);
  fold(b, 'permanent');
  await settled(b);
  assert.equal(b.puts, 1, 'refused: page A saved first');
  relayout(b);
  await settled(b);
  assert.deepEqual([...onDisk().projects.demo.collapsed].sort(), ['limit-body', 'permanent'], 'both pages\' folds stand');
  // Page D unfolds the section folded before both pages read the layout; page C's new fold stays.
  fs.writeFileSync(path.join(dir, 'layout.js'), 'window.DASH_LAYOUT = {"projects": {"demo": {"rev": 3, "collapsed": ["permanent"]}}};\n');
  const c = boot(), d = boot();
  fold(c, 'limit-body');
  await settled(c);
  fold(d, 'permanent', true);
  await settled(d);
  relayout(d);
  await settled(d);
  assert.deepEqual(onDisk().projects.demo.collapsed, ['limit-body'], 'the unfold removes only its own section');
});

// Issue 224: main's and the relay's own cards, in the card style. The relay's shows only with a relay configured
// (the collector then sends a relay key); main's shows its context against its clear line, the relay's has none.
test("issue 224: main's and the relay's cards show their figures, and the relay's is absent with no relay", () => {
  const seat = (over) => ({ context: 150000, line: 200000, today: { tokens: 2500000, usd: 12.5, partial: false }, avg7: { tokens: 1000000, usd: 4.25, partial: false },
    restarts: 2, restartGapSec: 3600, restartTimes: [iso(NOW - 7200000), iso(NOW - 3600000)], ...over });
  const w = fresh();
  show(w, { seats: { main: seat(), relay: seat({ context: 40000, line: null, restarts: 0, restartGapSec: null, restartTimes: [] }) } });
  const facts = (id) => text(w.document.getElementById(`${id}-facts`));
  assert.match(facts('main-seat'), /Context150\.0k of 200\.0k/, 'main: context against its line');
  assert.match(facts('main-seat'), /Today2\.5M tokens · \$12\.50/, 'main: tokens and list cost today');
  assert.match(facts('main-seat'), /7-day daily average1\.0M tokens · \$4\.25/, 'main: the 7-day daily average');
  assert.match(facts('main-seat'), /Restarts today2, every 60 min on average/, 'main: restarts today with the average gap');
  assert.equal(w.document.getElementById('relay-seat').dataset.absent, undefined, 'a configured relay has its card');
  assert.match(facts('relay-seat'), /Context40\.0k.*Restarts today0/, 'the relay: its context, no line, no restarts');
  const v = fresh();
  show(v, { seats: { main: seat() } });
  assert.equal(v.document.getElementById('relay-seat').dataset.absent, '', 'no relay configured: no relay card');
  assert.equal(v.document.getElementById('main-seat').dataset.absent, undefined, "main's card stays");
});

// Issue 240: the owner answers a decision from the "Needs me" panel, on this machine's own page only: the host
// takes an answer from a loopback client alone, so another host's page (the phone) shows the question read-only.
// An answer whose send failed is listed until the host has sent it again.
test('issue 240: answer buttons, the default marked, and an Other box show on a loopback page and not on another host', async () => {
  const d = { id: 'ship-1999-01-01', question: 'Ship it?', proposedDefault: 'yes', options: ['yes', 'no'], source: 'AskUserQuestion',
    askedAt: iso(NOW - 60000), answeredAt: null, answer: null };
  const w = fresh();
  show(w, { needsOwner: { decisions: [d], unsent: [{ id: 'keys-1999-01-01', to: 'relay' }] } });
  const buttons = [...w.document.querySelectorAll('#decisions .answer button')].map((b) => `${b.className}:${text(b)}`);
  assert.deepEqual(buttons, ['opt default-opt:yes (default)', 'opt:no', 'opt:Send'], 'one button per option, the default marked');
  assert.ok(w.document.querySelector('#decisions .answer input.other'), 'and an Other box');
  assert.match(text(w.document.getElementById('decisions')), /The answer to keys-1999-01-01 is not sent to the relay/, 'a failed send is shown');
  // This test host has no data.js, so it takes no answer: the page says so and the question stays answerable.
  w.document.querySelector('#decisions .answer button').click();
  await settled(w);
  assert.equal(w.puts, 1, 'one answer was sent');
  assert.match(text(w.document.querySelector('#decisions .answer')), /Not answered/, 'a refused answer is said, not shown as answered');
  const far = boot({}, 'demo', Date, '192.0.2.7');
  show(far, { needsOwner: { decisions: [d] } });
  assert.equal(far.document.querySelectorAll('#decisions .answer').length, 0, 'another host: no answer controls');
  assert.match(text(far.document.getElementById('decisions')), /Ship it\?/, 'the question still shows');
});

// A decision reopened (decision.sh reopen: the same id, a newer askedAt) is a new question: the page's word on the
// old answer must not stand in for its controls. And main's native picker for a question blocks it from reading the
// answer sent to its inbox, so when the host saw that picker open the page says so, and keeps saying it after the
// answered row leaves the list: the owner has to pick or press Esc in main's pane.
test('issue 240: a reopened decision is answerable again in the same tab; an open picker in main is named', async () => {
  const d = { id: 'ship-1999-01-01', question: 'Ship it?', proposedDefault: 'yes', options: ['yes', 'no'], source: 'AskUserQuestion',
    askedAt: iso(NOW - 60000), answeredAt: null, answer: null };
  const w = fresh();
  let reply = { ruling: 'r-19990101-000000-d-abcdef', unsent: 0, picker: false };
  w.fetch = () => { w.puts += 1; return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(reply) }); };
  show(w, { needsOwner: { decisions: [d] } });
  w.document.querySelector('#decisions .answer button').click();
  await settled(w);
  assert.match(text(w.document.querySelector('#decisions .answer')), /^Answered: yes/, 'the answer is shown as taken');
  assert.doesNotMatch(text(w.document.getElementById('decisions')), /picker/, 'no picker open: none named');
  w.refresh();
  show(w, { needsOwner: { decisions: [{ ...d, askedAt: iso(NOW - 1000) }] } });
  assert.equal(w.document.querySelectorAll('#decisions .answer button').length, 3, 'reopened: its buttons are back');
  reply = { ...reply, picker: true };
  w.document.querySelector('#decisions .answer button').click();
  await settled(w);
  assert.match(text(w.document.querySelector('#decisions .answer')), /main's picker for it was open: pick or press Esc in main's pane/, 'the reply names the open picker');
  w.refresh();
  show(w, { needsOwner: { decisions: [{ ...d, answeredAt: iso(NOW), answer: 'yes' }] } });
  assert.match(text(w.document.getElementById('decisions')), /ship-1999-01-01.*main's picker for it was open: pick or press Esc in main's pane/,
    'and the list keeps naming it after the answered row is gone');
});

// The reply is lost when only a later refresh delivers the answer, and on a reload: the host keeps the word, and the
// page names each answer the snapshot says waits on main's picker, once even when this tab's reply named it too.
test("issue 240: the snapshot's answers waiting on main's picker are named", async () => {
  const w = fresh();
  show(w, { needsOwner: { decisions: [], picker: ['ship-1999-01-01'] } });
  assert.match(text(w.document.getElementById('decisions')), /ship-1999-01-01.*main's picker for it was open: pick or press Esc in main's pane/);
  const d = { id: 'keys-1999-01-01', question: 'Rotate?', proposedDefault: 'yes', options: ['yes', 'no'], source: 'AskUserQuestion',
    askedAt: iso(NOW - 60000), answeredAt: null, answer: null };
  w.fetch = () => Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve({ ruling: null, unsent: 0, picker: true }) });
  w.refresh();
  show(w, { needsOwner: { decisions: [d] } });
  w.document.querySelector('#decisions .answer button').click();
  await settled(w);
  w.refresh();
  show(w, { needsOwner: { decisions: [], picker: ['keys-1999-01-01'] } });
  assert.equal((text(w.document.getElementById('decisions')).match(/keys-1999-01-01/g) || []).length, 1, 'named once');
});

// Issue 295: an answer the host could not send must say why and how long it has failed, not "sent again on each
// refresh" forever, and on this machine's page the owner settles it: retry, main got it another way (confirmed), or
// drop (confirmed). Another host's page, the phone's, shows the note with no buttons.
test('issue 295: an unsent answer shows its reason, tries and first try; the buttons show on a loopback page only', async () => {
  const unsent = [{ id: 'ship-1999-01-01', to: 'main', key: 'k1', state: 'gave-up', reason: 'its main folder /gone is gone', tries: 0, firstAt: iso(NOW - 3600000), lastError: null },
    { id: 'keys-1999-01-01', to: 'relay', key: 'k2', state: 'pending', reason: null, tries: 3, firstAt: iso(NOW - 600000), lastError: 'cos-tell: no relay pane' }];
  const w = fresh();
  const sent = [];
  w.fetch = (url, opt) => { sent.push([url, JSON.parse(opt.body)]); return Promise.resolve({ ok: true, status: 200 }); };
  let asked = 0;
  w.confirm = () => { asked += 1; return asked > 1; };
  show(w, { needsOwner: { decisions: [], unsent } });
  const rows = [...w.document.querySelectorAll('#decisions li.unsent')];
  assert.match(text(rows[0]), /^The answer to ship-1999-01-01 is not sent to main: its main folder \/gone is gone, 0 tries since .*The host gave up on it\./);
  assert.match(text(rows[1]), /^The answer to keys-1999-01-01 is not sent to the relay: cos-tell: no relay pane, 3 tries since .*The host tries again on each refresh\./);
  assert.deepEqual([...rows[0].querySelectorAll('button')].map(text), ['Retry', 'Main got it', 'Drop']);
  const [retry, got, drop] = rows[0].querySelectorAll('button');
  retry.click();
  got.click(); // the owner says no to the confirm: nothing is sent
  drop.click();
  await sleep(50);
  assert.deepEqual(sent, [['unsent', { key: 'k1', action: 'retry' }], ['unsent', { key: 'k1', action: 'drop' }]], 'retry at once; delivered and drop only once confirmed');
  assert.equal(asked, 2, 'delivered and drop each asked the owner first');
  const far = boot({}, 'demo', Date, '192.0.2.7');
  show(far, { needsOwner: { decisions: [], unsent } });
  assert.equal(far.document.querySelectorAll('#decisions li.unsent').length, 2, 'another host: the notes show');
  assert.equal(far.document.querySelectorAll('#decisions li.unsent button').length, 0, 'and no buttons');
});

// Issue 294: a stuck or dead collector meant a terminal and a launchctl line. The page's own button restarts it, and
// says where the restart is by the host's own stamps: "restarting..." until a new cycle starts, then "waiting for first
// cycle" until new data lands.
test('issue 294: Restart collector asks first, shows its progress by the host stamps and the last cycle; a LAN page has none', async () => {
  const w = fresh();
  const sent = [];
  w.fetch = (url, opt) => { sent.push([url, opt.method]); return Promise.resolve({ ok: true, status: 202 }); };
  const beat = (cycle) => { w.refresh(); w.DASH_ALIVE = { at: iso(Date.now()), cycleStartedAt: cycle, lastCycleSec: 12 }; w.document.querySelector('script[src^="alive.js"]').dispatchEvent(new w.Event('load')); };
  const data = (at) => { w.refresh(); w.DASH = { updatedAt: at, home: 'demo', sources: {}, projects: { demo: {} } }; w.document.querySelector('script[src^="data.js"]').dispatchEvent(new w.Event('load')); };
  data(iso(NOW - 5000)); beat(iso(NOW - 9000));
  const btn = w.document.getElementById('restart');
  assert.equal(text(w.document.getElementById('last-cycle')), 'last cycle 12 s');
  assert.equal(btn.hidden, false, 'a loopback page has the button');
  w.confirm = () => false; btn.click();
  assert.deepEqual(sent, [], 'a restart the owner does not confirm sends nothing');
  w.confirm = () => true; btn.click();
  await sleep(20);
  assert.deepEqual(sent, [['restart', 'POST']]);
  assert.deepEqual([text(btn), btn.disabled], ['restarting...', true]);
  beat(iso(NOW - 9000));
  assert.equal(text(btn), 'restarting...', 'the old cycle is no restart');
  beat(iso(NOW - 1000));
  assert.equal(text(btn), 'waiting for first cycle');
  data(iso(NOW - 4000));
  assert.deepEqual([text(btn), btn.disabled], ['Restart collector', false], 'new data ends the progress');
  const far = boot({}, 'demo', Date, '192.0.2.7');
  assert.equal(far.document.getElementById('restart').hidden, true, 'another host: no button');
});

// Issue 270: which units cost the most this week, Claude and Codex apart, each one's stages a click away.
test('issue 270: Tokens per unit ranks the units by cost, splits Claude and Codex, and folds each one\'s stages', () => {
  const w = fresh();
  const t = (usd, claude) => ({ usd, input: 1000, cached: 500, output: 200, partial: false, unpriced: [], byAgent: { claude, codex: usd - claude } });
  show(w, { units: { inFlight: [], costPerUnit: [
    { unit: 'big-1999-01-01', inFlight: false, total: t(3, 2), stages: [{ stage: 'building', ...t(2, 2) }, { stage: 'review', ...t(1, 0) }] },
    { unit: 'small-1999-01-01', inFlight: true, total: t(1, 1), stages: [] }] } });
  const rows = [...w.document.querySelectorAll('#cost-unit-list > li')];
  assert.deepEqual(rows.map((r) => [...r.querySelector('.uline').children].map(text)),
    [['big-1999-01-01', '$3.00 (Claude $2.00, Codex $1.00) · 1.2k tokens'], ['small-1999-01-01 (in flight)', '$1.00 (Claude $1.00, Codex $0.00) · 1.2k tokens']]);
  const fold = rows[0].querySelector('details');
  assert.equal(fold.open, false, 'stages folded');
  assert.deepEqual([...fold.querySelectorAll('li')].map(text), ['building: $2.00', 'review: $1.00']);
  assert.equal(rows[1].querySelector('details'), null, 'no stages: no fold');
});

// Issues 271 and 272: which units' review loops ran long this week, and which merged units let a defect through.
test('issues 271 and 272: the review card lists the unit with repeated NO-GOs first, and its escapes', () => {
  const w = fresh();
  const row = (unit, rounds, noGo) => ({ unit, rounds, goRounds: 1, noGoRounds: noGo, fixRounds: null, verdict: 'CONVERGED-GO', gaps: ['fixRounds', 'findings'] });
  show(w, { reviewLoop: [row('quick-1999-01-01', 1, 0), row('loopy-1999-01-01', 5, 4)], escapes: [{ unit: 'loopy-1999-01-01', escaped: [41, 43] }] });
  assert.deepEqual([...w.document.querySelectorAll('#review-list > li .uline')].map((u) => [...u.children].map(text)),
    [['loopy-1999-01-01', '5 rounds, 4 NO-GO · not measured: fixRounds, findings'], ['quick-1999-01-01', '1 round, 0 NO-GO · not measured: fixRounds, findings']]);
  assert.deepEqual([...w.document.querySelectorAll('#escapes-list > li')].map(text), ['loopy-1999-01-01 escaped #41, #43']);
  const none = fresh();
  show(none, { reviewLoop: [], escapes: [] });
  assert.equal(text(none.document.querySelector('#review .card-note')), 'No unit merged in the last 7 days');
  assert.deepEqual([...none.document.querySelectorAll('#escapes-list > li')].map(text), ['No escaped issue tagged']);
  const nothing = fresh();
  show(nothing, { reviewLoop: null, escapes: null });
  assert.equal(text(nothing.document.querySelector('#review .card-note')), 'Unit ledger not measured');
  assert.deepEqual([...nothing.document.querySelectorAll('#escapes-list > li')].map(text), []);
});

// Issue 274: an alert that cleared left no trace on the card. The last 24 h of them sit in a closed list under it.
test("issue 274: a resolved alert shows in a folded list with its start and clear times; another project's does not", () => {
  const w = fresh();
  const s = w.document.querySelector('script[src^="data.js"]');
  w.DASH = { updatedAt: iso(NOW), home: 'demo', sources: {}, projects: { demo: {}, other: {} }, alerts: [],
    alertsResolved: [{ key: 'host-swap', since: iso(NOW - 7200000), resolvedAt: iso(NOW - 3600000), severity: 'warn', text: 'Host swap 90% used. Action: hold launches' },
      { key: 'x', since: iso(NOW - 7200000), resolvedAt: iso(NOW - 60000), severity: 'warn', text: 'Theirs. Action: none', project: 'other' }] };
  s.dispatchEvent(new w.Event('load'));
  const fold = w.document.getElementById('alerts-resolved');
  assert.deepEqual([fold.hidden, fold.open, text(fold.querySelector('summary'))], [false, false, 'Resolved in the last 24 h (1)']);
  const row = text(fold.querySelector('li'));
  assert.match(row, /^Host swap 90% used\. Action: hold launches from \d+:\d\d [AP]M to \d+:\d\d [AP]M$/);
  w.DASH = { ...w.DASH, alertsResolved: [] };
  w.refresh(); w.document.querySelector('script[src^="data.js"]').dispatchEvent(new w.Event('load'));
  assert.equal(fold.hidden, true, 'none resolved: no list');
});

// Issue 276: while the owner typed in one answer box, a refresh skipped the whole list, so a new decision, an unsent
// note or a picker note stayed hidden until the box lost focus. Now the list is rebuilt around the row being typed in,
// which is kept as the same node: the typing and the focus stay, and everything new shows.
test('issue 276: a focused answer box keeps its text and focus while a refresh adds a decision and an unsent note', async () => {
  const dec = (id, q) => ({ id, question: q, proposedDefault: 'yes', options: ['yes', 'no'], source: 'AskUserQuestion', askedAt: iso(NOW - 60000), answeredAt: null, answer: null });
  const a = dec('a-1999-01-01', 'First?'), b = dec('b-1999-01-01', 'Second?');
  const w = fresh();
  show(w, { needsOwner: { decisions: [a] } });
  const box = w.document.querySelector('#decisions .answer input.other');
  box.focus();
  box.value = 'half typed';
  w.refresh();
  show(w, { needsOwner: { decisions: [a, b], unsent: [{ id: 'old-1999-01-01', to: 'main', key: 'k', state: 'pending', tries: 1, firstAt: iso(NOW), lastError: 'x' }] } });
  const all = text(w.document.getElementById('decisions'));
  assert.match(all, /Second\?/, 'the new decision shows');
  assert.match(all, /The answer to old-1999-01-01 is not sent to main/, 'and the unsent note');
  assert.equal(w.document.querySelector('#decisions .answer input.other'), box, 'the box is the same node');
  assert.equal(box.value, 'half typed', 'its text stays');
  assert.equal(w.document.activeElement, box, 'and its focus');
  w.refresh();
  show(w, { needsOwner: { decisions: [b] } });
  assert.doesNotMatch(text(w.document.getElementById('decisions')), /First\?/, 'its decision gone from the open list, the row goes too');
});

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
function boot(store = {}, project = 'demo', clock = Date) {
  const virtualConsole = new VirtualConsole();
  const dom = new JSDOM(html, { url: `http://127.0.0.1:${port}/index.html?project=${project}`, virtualConsole });
  const w = dom.window;
  w.reloads = 0;
  w.puts = 0;
  virtualConsole.on('jsdomError', (e) => { if (/navigation/.test(e.message)) w.reloads += 1; else console.error(e); });
  for (const [k, v] of Object.entries(store)) w.localStorage.setItem(k, v);
  w.DASH_LAYOUT = onDisk();
  w.fetch = (url, opt) => { w.puts += 1; return fetch(`http://127.0.0.1:${port}/${url}`, opt); };
  const none = () => 0;
  vm.runInNewContext(appSrc, { window: w, document: w.document, setInterval: none, clearInterval: none, setTimeout, clearTimeout, Date: clock, console });
  return w;
}
// Saves and their answers are real requests: wait until a page has sent nothing new for a while.
async function settled(...pages) {
  let n = -1;
  while (n !== pages.reduce((a, w) => a + w.puts, 0)) { n = pages.reduce((a, w) => a + w.puts, 0); await sleep(250); }
}
const storeOf = (w) => Object.fromEntries(Object.keys(w.localStorage).map((k) => [k, w.localStorage.getItem(k)]));

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
  assert.deepEqual(onDisk().projects.demo, { rev: 6 }, 'the reset still stands: the older page wrote nothing over it');
  assert.equal(a.puts, 1, 'the refused save is not sent again');
  assert.equal(a.reloads, 1, 'the page that fell behind reloads onto the newer layout');
  // The reload shows the host's layout and sends nothing of its own.
  const again = boot(storeOf(a));
  await settled(again);
  assert.equal(again.document.getElementById('alerts').dataset.size, '4', 'the reloaded page shows the reset width');
  assert.equal(again.puts, 0);
  assert.equal(onDisk().projects.demo.rev, 6);
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
  show(w, { limit: { billing: 'api', api: { spentUsd: 12, complete: true } } });
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

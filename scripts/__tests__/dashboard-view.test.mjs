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
function boot(store = {}, project = 'demo') {
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
  vm.runInNewContext(appSrc, { window: w, document: w.document, setInterval: none, clearInterval: none, setTimeout, clearTimeout, Date, console });
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
const fresh = () => { fs.writeFileSync(path.join(dir, 'layout.js'), 'window.DASH_LAYOUT = {"projects": {"demo": {}}, "rev": 1};\n'); return boot(); };
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
  assert.deepEqual(rows, ['Stage', 'Last sign', 'Codex adversarial, round 1', 'Explore Haiku 5.5']);
  assert.deepEqual([...card.querySelectorAll('.trace .num:not(.headnums)')].map((n) => [...n.children].map((c) => c.textContent)), [['', '', 'running'], ['61,402', '4,910', '2:00']]);
  assert.ok(card.querySelector('.lane .h.codex.live'), 'a pass still running reaches now');
  assert.match(text(card.querySelector('.tmore')), /^1 earlier helper run before /);
  assert.equal(text(card.querySelector('.branch')), 'Branch work/batch-g, agents claude:working');
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

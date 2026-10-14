// The dashboard view is what the owner trusts instead of asking main. It must never
// pass a ticking clock off as live data, never let a source field become
// markup, keep what he opened or focused across the 15 s refresh, and show the
// machine's readings once whatever project is picked. Timers and Date are mocked: no
// assertion here depends on elapsed wall time.
import { test, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

// The owner reads the board in Eastern time; the view formats in the process's local zone.
process.env.TZ = 'America/New_York';
// jsdom is lent, never shipped: COMMANDECK_TEST_NODE_MODULES names a node_modules folder that has it
// (dashboard-view.test.sh skips this file, saying so, without one).
const { JSDOM, VirtualConsole } = createRequire(path.join(process.env.COMMANDECK_TEST_NODE_MODULES, '..', 'x.js'))('jsdom');
const VIEW = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'dashboard');
const html = fs.readFileSync(path.join(VIEW, 'index.html'), 'utf8');
const appSrc = fs.readFileSync(path.join(VIEW, 'app.js'), 'utf8');
const T0 = Date.parse('2026-10-01T12:00:00Z');
const ORDER_KEY = 'commandeck-dashboard-order:demo';
const COLLAPSED_KEY = 'commandeck-dashboard-collapsed:demo';
const SIZES_KEY = 'commandeck-dashboard-sizes:demo';
const HEIGHTS_KEY = 'commandeck-dashboard-heights:demo';
const HIDDEN_KEY = 'commandeck-dashboard-hidden:demo';
// The default order and widths: a reorder in the markup is a change the owner must see.
const DEFAULT_ORDER = ['alerts', 'builds', 'needs', 'main-chain', 'units', 'limit', 'todos', 'host', 'cost-role', 'guard-blocks', 'chief-of-staff', 'agents'];
const DEFAULT_SIZES = { alerts: 4, builds: 2, units: 4, limit: 2, todos: 2, 'guard-blocks': 2 };
const iso = (ms) => new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z');

beforeEach(() => mock.timers.enable({ apis: ['setInterval', 'setTimeout', 'Date'], now: T0 }));
afterEach(() => mock.timers.reset());

// An http origin: jsdom gives a file: page no localStorage. `saved`,
// `collapsed` and `store` (any other key) are what a previous visit left behind.
function boot({ saved, collapsed, store = {}, layout, file, url = 'http://dash.test/index.html?project=demo' } = {}) {
  // jsdom cannot navigate: a page that reloads itself is seen as this report, counted in w.reloads.
  const virtualConsole = new VirtualConsole();
  const dom = new JSDOM(html, { url, virtualConsole });
  const w = dom.window;
  w.reloads = 0;
  virtualConsole.on('jsdomError', (e) => { if (/navigation/.test(e.message)) w.reloads += 1; else console.error(e); });
  if (saved !== undefined) w.localStorage.setItem(ORDER_KEY, saved);
  if (collapsed !== undefined && collapsed !== null) w.localStorage.setItem(COLLAPSED_KEY, collapsed);
  w.fetch = () => assert.fail('the view must never fetch');
  for (const [k, v] of Object.entries(store)) w.localStorage.setItem(k, v);
  // The tests write one project's layout; the host's file keeps each project's in its own slot, under one number.
  // `file` is the host's layout file as it is, for a test about the file's own shape.
  if (file !== undefined) w.DASH_LAYOUT = file;
  else if (layout !== undefined) {
    const { rev, ...own } = layout && typeof layout === 'object' && !Array.isArray(layout) ? layout : {};
    w.DASH_LAYOUT = !layout || typeof layout !== 'object' || Array.isArray(layout) || layout.projects ? layout
      : { ...(rev === undefined ? {} : { rev }), projects: { demo: own } };
  }
  // The one request the view may make is saving the layout to its own host.
  w.puts = [];
  w.sentFor = [];
  w.fetch = (url, opt) => {
    assert.equal(url, 'layout', 'the view fetches nothing but its own layout file');
    assert.equal(opt.method, 'PUT');
    assert.equal(opt.headers['Content-Type'], 'application/json');
    // Every save names its project; w.puts keeps the layout, w.sentFor the name each went under.
    const { project, ...sent } = JSON.parse(opt.body);
    w.sentFor.push(project);
    w.puts.push(sent);
    // A test that sets w.slowHost answers each save itself, through w.answers.
    return w.slowHost ? new Promise((answer) => w.answers.push(answer)) : Promise.resolve({ ok: true, status: 204 });
  };
  w.answers = [];
  w.XMLHttpRequest = function () { assert.fail('the view must never open a request'); };
  vm.runInNewContext(appSrc, {
    window: w, document: w.document, setInterval, clearInterval, setTimeout, clearTimeout, Date, console,
  });
  return dom;
}
const loaders = (dom) => [...dom.window.document.querySelectorAll('script[src^="data.js"]')];
function pending(dom) {
  const s = loaders(dom);
  assert.equal(s.length, 1, 'exactly one data.js load in flight');
  return s[0];
}
// The tests build one flat snapshot; the collector keeps a project's parts under
// .projects[<name>] and the machine's own readings at the top.
const MACHINE = ['updatedAt', 'sources', 'host', 'limit', 'alerts', 'name', 'projects', 'home'];
function wrap(s) {
  if (!s || typeof s !== 'object' || s.projects) return s;
  const top = {}, p = {};
  for (const [k, v] of Object.entries(s)) (MACHINE.includes(k) ? top : p)[k] = v;
  return { ...top, projects: { demo: p } };
}
function deliver(dom, snapshot) {
  const s = pending(dom);
  dom.window.DASH = wrap(snapshot);
  s.dispatchEvent(new dom.window.Event('load'));
}
const failLoad = (dom) => pending(dom).dispatchEvent(new dom.window.Event('error'));
const $ = (dom, sel) => dom.window.document.querySelector(sel);
const $$ = (dom, sel) => [...dom.window.document.querySelectorAll(sel)];

const fresh = (at) => ({ sampledAt: at, status: 'fresh', staleSince: null, error: null });
function snap(over = {}) {
  const at = over.updatedAt ?? iso(Date.now());
  const ids = ['decisions', 'seat-events', 'git-main', 'orca', 'worktrees', 'builder-logs', 'host', 'todos', 'orca-tasks', 'agents',
    'hook-fire-log', 'chief-of-staff', 'alerts'];
  return {
    updatedAt: at,
    sources: Object.fromEntries(ids.map((id) => [id, fresh(at)])),
    needsOwner: {
      decisions: [{ id: 'd1', askedAt: at, question: 'Ship it?', proposedDefault: 'wait a day', source: 'unit-a', answeredAt: null, answer: null }],
    },
    units: { inFlight: [{ unit: 'unit-a', branch: 'work/unit-a', dirty: 2, agents: 'claude:working', stage: 'review', ageSec: 120 }] },
    mainChain: { commits: [{ sha: 'abc12345', subject: 'feat: x' }], unpushed: 3 },
    costPerRole: [{ role: 'sol', seats: 3, unmeasuredSeats: 1, input: 10, cachedInput: 20, output: 30 }],
    host: { cpus: 8, load: [2, 1.5, 1], swap: { totalMb: 2048, usedMb: 512 }, claudeProcs: 4, codexProcs: null },
    todos: { sessionId: 'sess-1', items: [{ id: '1', subject: 'ship it', status: 'pending', activeForm: 'Shipping it' }] },
    agents: { sessionId: 'sess-1', items: [{ id: 'a1', description: 'Find it', model: 'opus', running: true, startedAt: at, ageSec: 30 }] },
    guardBlocks: { blocks: 1, items: [{ at, hook: 'push-guard.sh', event: 'PreToolUse', tool: 'Bash', worktree: 'unit-a', summary: 'git push', retry: null }] },
    alerts: [{ id: 'host-load-1', severity: 'crit', text: 'Host overloaded: load 20 on 8 cores', since: at }],
    chiefOfStaff: { unread: 2, oldestUnreadAgeSec: 7200 },
    ...over,
  };
}

test('the collector-dead banner follows the write time, never the page clock', () => {
  const dom = boot();
  deliver(dom, snap({ updatedAt: iso(T0) }));
  const banner = $(dom, '#banner');
  const status = $(dom, '#status');
  assert.equal(status.dataset.state, 'live');
  const updated = $(dom, '#updated').textContent;
  mock.timers.tick(180000);
  assert.equal(banner.hidden, true, 'a 180 s old write is still live');
  mock.timers.tick(1000);
  assert.equal(banner.hidden, false, 'a 181 s old write must raise the banner');
  assert.match(banner.textContent, /collector dead/i, 'with no heartbeat at all, an old write is a dead collector');
  assert.equal(status.dataset.state, 'dead');
  assert.doesNotMatch(status.textContent, /^live$/i);
  deliver(dom, snap({ updatedAt: iso(T0) }));
  mock.timers.tick(1000);
  assert.equal(banner.hidden, false, 'an unchanged reload must not reset Updated');
  assert.equal($(dom, '#updated').textContent, updated);
  mock.timers.tick(14000);
  deliver(dom, snap({ updatedAt: iso(Date.now()) }));
  assert.equal(banner.hidden, true, 'a new collector write clears the banner');
  assert.equal(status.dataset.state, 'live');
  assert.notEqual($(dom, '#updated').textContent, updated);
});

// The owner's banner said "stopped" while the collector was alive and only slow on a
// loaded host. The loop's heartbeat (alive.js) tells the two apart: a fresh
// heartbeat with old numbers is slow, no heartbeat for 45 s is dead.
const beat = (dom, alive) => {
  const s = $$(dom, 'script[src^="alive.js"]');
  assert.equal(s.length, 1, 'exactly one alive.js load in flight');
  dom.window.DASH_ALIVE = alive;
  s[0].dispatchEvent(new dom.window.Event('load'));
};
test('an old snapshot reads slow while the heartbeat is fresh, dead once it stops, live on a new write', () => {
  const dom = boot();
  deliver(dom, snap({ updatedAt: iso(T0) }));
  const banner = $(dom, '#banner');
  const status = $(dom, '#status');
  mock.timers.tick(181000);
  assert.equal(status.dataset.state, 'dead', 'never a heartbeat: dead');
  assert.match(banner.textContent, /^Collector dead: no heartbeat .*restart the dashboard service/);
  beat(dom, { at: iso(Date.now() - 5000), cycleStartedAt: iso(T0 - 20000), lastCycleSec: 75 });
  assert.equal(status.dataset.state, 'slow', 'a heartbeat 5 s old with numbers 181 s old is a slow cycle');
  assert.equal(banner.hidden, false);
  assert.equal(banner.dataset.state, 'slow', 'the banner says slow in its own colour');
  assert.match(banner.textContent, /^Collector slow: still running, this cycle started 3 min ago \(last took 75 s\); numbers are from \d{1,2}:\d\d:\d\d [AP]M/);
  mock.timers.tick(46000);
  assert.equal(status.dataset.state, 'dead', 'a heartbeat 51 s old is a dead collector');
  assert.match(banner.textContent, /^Collector dead: no heartbeat since \d{1,2}:\d\d:\d\d [AP]M.*restart the dashboard service/);
  deliver(dom, snap({ updatedAt: iso(Date.now()) }));
  assert.equal(status.dataset.state, 'live', 'a new write is live whatever the heartbeat says');
  assert.equal(banner.hidden, true);
});

// A hung read keeps the heartbeat ticking: a cycle running past 15 minutes is
// stuck, never "slow" forever.
test('a fresh heartbeat on a cycle started 20 minutes ago reads stuck, in red, with the restart step', () => {
  const dom = boot();
  deliver(dom, snap({ updatedAt: iso(T0) }));
  mock.timers.tick(1260000);
  beat(dom, { at: iso(Date.now() - 5000), cycleStartedAt: iso(Date.now() - 1200000), lastCycleSec: 40 });
  assert.equal($(dom, '#status').dataset.state, 'stuck');
  const banner = $(dom, '#banner');
  assert.equal(banner.dataset.state, 'stuck', 'not the amber slow banner');
  assert.match(banner.textContent, /^Collector stuck: the cycle started at \d{1,2}:\d\d:\d\d [AP]M \(20 min ago\) is still running; restart the dashboard service/);
});

test('missing, invalid or future write times are unavailable, never live', () => {
  const none = boot();
  failLoad(none);
  assert.equal($(none, '#status').dataset.state, 'unavailable', 'no data.js at all');
  assert.equal($(none, '#banner').hidden, false);
  for (const updatedAt of ['garbage', null, iso(T0 + 600000)]) {
    const dom = boot();
    deliver(dom, snap({ updatedAt }));
    assert.equal($(dom, '#status').dataset.state, 'unavailable', `updatedAt ${updatedAt}`);
    assert.doesNotMatch($(dom, '#status').textContent, /live/i);
  }
});

test('Needs the owner lists only open decisions, each with its default and how long it has waited', () => {
  const dom = boot();
  const s = snap();
  s.needsOwner.decisions.push({ id: 'd2', askedAt: s.updatedAt, question: 'answered one', proposedDefault: 'x', source: 's',
    answeredAt: s.updatedAt, answer: 'yes' });
  deliver(dom, s);
  assert.equal($$(dom, '#decisions li').length, 1, 'answered decisions are hidden');
  assert.match($(dom, '#decisions').textContent, /wait a day/, 'a decision shows its proposed default');
  assert.match($(dom, '#decisions').closest('.group').querySelector('h3').textContent, /^Waiting on the owner/);
  assert.match($(dom, '#decisions').textContent, /0 s ago/, 'each row shows how long it has waited');
  assert.doesNotMatch($(dom, '#needs').textContent, /Open questions|Decisions|issues/, 'one list, with one name for the ledger');
});

test('every data value renders as text; numbers alone reach SVG attributes', () => {
  const dom = boot();
  const P = '<img src=x onerror="window.__pwned=1">"\'&';
  const s = snap();
  s.needsOwner.decisions[0] = { ...s.needsOwner.decisions[0], id: P, question: P, proposedDefault: P, source: P };
  Object.assign(s.units.inFlight[0], { unit: P, branch: P, agents: P, stage: P, diffStat: P });
  s.mainChain.commits[0].subject = P;
  s.costPerRole[0].role = P;
  s.alerts[0].text = P;
  s.limit = { ...limitSnap(), history: [{ at: P, pct: P }, { at: iso(T0 - 3600000), pct: 10 }, { at: iso(T0), pct: 12 }] };
  s.units.inFlight.push({ unit: 'seat-unit', stage: 'building', seatRole: P, ageSec: 5 });
  s.agents.items[0] = { id: P, description: P, model: P, running: true, startedAt: P, ageSec: 1 };
  deliver(dom, s);
  const d = dom.window.document;
  assert.equal(d.querySelector('img'), null, 'no injected element');
  assert.equal(d.querySelectorAll('script:not([src])').length, 0, 'no injected script');
  assert.equal(dom.window.__pwned, undefined);
  assert.ok(d.body.textContent.includes(P), 'the payload appears literally');
  const svg = d.querySelector('#limit-chart svg');
  assert.ok(svg, 'the limit chart is drawn');
  for (const node of svg.querySelectorAll('*')) {
    assert.ok(['path', 'rect', 'line', 'title', 'text', 'circle'].includes(node.localName), `fixed SVG tag, saw ${node.localName}`);
    for (const a of node.attributes) {
      if (['d', 'x', 'y', 'x1', 'x2', 'y1', 'y2', 'width', 'height', 'cx', 'cy', 'r'].includes(a.name)) {
        assert.match(a.value, /^[-0-9., MHVZ]*$/, `${a.name} must be numbers and path letters, saw ${a.value}`);
      }
    }
  }
});

test("Main's to-do list counts like the terminal, puts open before done, and shows subjects as text", () => {
  const dom = boot();
  const P = '<img src=x>';
  deliver(dom, snap({ todos: { sessionId: 'sess-1', items: [
    { id: '1', subject: 'finished', status: 'completed', activeForm: 'Finishing' },
    { id: '2', subject: P, status: 'pending', activeForm: 'Waiting' },
    { id: '3', subject: 'busy', status: 'in_progress', activeForm: 'Being busy' },
  ] } }));
  assert.match($(dom, '#todos-count').textContent, /^3 tasks \(1 done, 2 open\)/);
  const items = $$(dom, '#todos-list li');
  assert.deepEqual(items.map((li) => li.dataset.status), ['in_progress', 'pending', 'completed'], 'in progress, then pending, then done');
  assert.match(items[0].textContent, /Being busy/, 'the item in progress reads as the terminal shows it');
  assert.equal(items[1].querySelector('.todo-text').textContent, P, 'a subject is text, never markup');
  assert.deepEqual(items.map((li) => li.querySelector('.badge').textContent), ['now', 'waiting', 'done'], 'each item says its state in a word');
  assert.match($(dom, '#todos-bar').textContent, /1 of 3 done.*1 in progress/s, 'the compact bar counts done and in progress');
  assert.equal($(dom, '#todos img'), null);
  assert.ok(items[2].classList.contains('done') && !items[1].classList.contains('done'), 'only completed items are struck through');
  mock.timers.tick(15000);
  deliver(dom, snap({ todos: null }));
  assert.equal($$(dom, '#todos-list li').length, 0, 'no main session is not an empty to-do list');
  assert.match($(dom, '#todos').textContent, /not measured/i);
});

// A seat launched by seat.sh is a unit in flight: its card names the role it runs under.
test('a seat is counted in its stage and badged by its role', () => {
  const dom = boot();
  const s = snap();
  s.units.inFlight = [row('unit-seat', 'building', { seatRole: 'implementer' }), row('unit-rev', 'review', { seatRole: 'brief-reviewer' }),
    row('unit-plain', 'building', { seatRole: null })];
  deliver(dom, s);
  const badges = (n) => [...card(dom, n).querySelectorAll('.badge')].map((b) => b.textContent);
  assert.deepEqual(badges('unit-seat'), ['Implementer seat']);
  assert.deepEqual(badges('unit-rev'), ['Brief-reviewer seat']);
  assert.deepEqual(badges('unit-plain'), [], 'a unit with no live seat has no role badge');
  assert.equal(inFlightValue(dom), '3', 'seats count as units in flight');
  assert.ok(card(dom, 'unit-seat').closest('[data-list="building"]'));
  assert.ok(card(dom, 'unit-rev').closest('[data-list="review"]'));
});

test('a Builder card shows a Builder badge, its signals, and its steps', () => {
  const dom = boot();
  const s = snap();
  s.units.inFlight = [
    row('unit-bld', 'review', { round: 2, builder: {
      verdict: 'VERDICT: GO', verdictRound: 1,
      signals: [{ kind: 'stuck', since: 1, limitSec: 180 }, { kind: 'loop', since: 2, limitSec: null }],
      steps: [
        { kind: 'codex', pass: 'adversarial', round: 2, start: iso(T0 - 300000), end: null, rc: null },
        { kind: 'codex', pass: 'review', round: 1, start: iso(T0 - 500000), end: iso(T0 - 450000), rc: 0 },
        { kind: 'codex', pass: 'adversarial', round: 1, start: iso(T0 - 560000), end: iso(T0 - 520000), rc: 0 },
        { kind: 'subagent', agentId: 'a1', type: 'Explore', modelAsked: 'haiku', model: null, tokens: null, start: iso(T0 - 600000), stop: iso(T0 - 590000), reason: 'no usage' },
      ] } }),
    row('unit-bld-nm', 'building', { ageSec: null, builder: { steps: null, signals: null, verdict: null } }),
    row('unit-bld-run', 'review', { round: 2, builder: { verdict: 'VERDICT: GO', verdictRound: 2, signals: [],
      steps: [{ kind: 'codex', pass: 'review', round: 2, start: iso(T0 - 300000), end: null, rc: null }] } }),
  ];
  deliver(dom, s);
  const badges = (n) => [...card(dom, n).querySelectorAll('.badge')].map((b) => b.textContent);
  assert.deepEqual(badges('unit-bld'), ['Builder', 'Stuck', 'Loop']);
  const more = card(dom, 'unit-bld').querySelector('details.unit-more').textContent;
  // A verdict read beside the wrong round tells the owner a round passed that is still running.
  const codexLines = [...card(dom, 'unit-bld').querySelector('details.unit-more').querySelectorAll('p')]
    .map((p) => p.textContent).filter((t) => t.startsWith('Codex'));
  assert.deepEqual(codexLines.map((t) => [/round (\d+)/.exec(t)[1], / running /.test(t), t.includes('VERDICT: GO')]),
    [['2', true, false], ['1', false, true], ['1', false, false]],
    "the verdict sits once, beside its own round's newest finished step, never beside a running one");
  assert.ok(!card(dom, 'unit-bld-run').querySelector('details.unit-more').textContent.includes('VERDICT: GO'),
    'a report for a round whose step is still running is not shown as that step\'s verdict');
  assert.match(more, /Explore.*asked haiku.*ran not measured.*tokens not measured.*no usage/s, 'a field the log lacks reads not measured');
  assert.ok(more.indexOf('Codex') < more.indexOf('Explore'), 'steps are listed newest first');
  assert.deepEqual(badges('unit-bld-nm'), ['Builder', 'Signals not measured'], 'an unreadable log is not a healthy Builder');
  assert.match(card(dom, 'unit-bld-nm').textContent, /Steps not measured/);
  assert.match(card(dom, 'unit-bld-nm').textContent, /Last sign not measured/);
});

test("Main's background agents list running first, as text, and null reads not measured", () => {
  const dom = boot();
  const at = iso(Date.now() - 600000);
  deliver(dom, snap({ agents: { sessionId: 'sess-1234567890', items: [
    { id: 'f1', description: '<img src=x>', model: 'opus', running: false, startedAt: at, ageSec: 400 },
    { id: 'r1', description: 'Busy one', model: null, running: true, startedAt: at, ageSec: 20 },
  ] } }));
  assert.match($(dom, '#agents-count').textContent, /^2 agents \(1 running\), session sess-123/);
  const items = $$(dom, '#agents-list li');
  assert.deepEqual(items.map((li) => li.dataset.id), ['r1', 'f1'], 'running before finished');
  assert.match(items[0].textContent, /Busy one.*Running.*model not measured.*20 s ago/s);
  assert.match(items[1].textContent, /Finished.*opus.*7 min ago/s);
  assert.ok(items[1].textContent.includes('<img src=x>'));
  assert.equal($(dom, '#agents img'), null);
  mock.timers.tick(15000);
  deliver(dom, snap({ agents: { sessionId: 's', items: [] } }));
  assert.equal($(dom, '#agents-list').textContent, 'No background agents');
  mock.timers.tick(15000);
  deliver(dom, snap({ agents: null }));
  assert.equal($$(dom, '#agents-list li').length, 0, 'no main session is not an empty agent list');
  assert.match($(dom, '#agents').textContent, /not measured/i);
});

test('Recent guard blocks list each stored field as text, keep the collector order, and an empty or missing log reads no blocks recorded', () => {
  const dom = boot();
  const at = iso(Date.now() - 600000);
  deliver(dom, snap({ guardBlocks: { blocks: 45, items: [
    { at, hook: '<b>push-guard.sh</b>', event: 'PreToolUse', tool: 'Bash', worktree: 'unit-a', summary: 'git push', retry: 'identical' },
    { at, hook: 'edit-guard.sh', event: 'PreToolUse', tool: 'Edit', worktree: 'unit-b', summary: 'a/b.ts', retry: 'worked-around' },
    { at, hook: 'old-guard.sh', event: null, tool: null, worktree: null, summary: null, retry: null },
  ] } }));
  assert.equal($(dom, '#guard-blocks-count').textContent, 'Latest 3 of 45 blocks');
  const items = $$(dom, '#guard-blocks-list tr');
  assert.equal(items.length, 3);
  const cells = (r) => [...r.children].map((c) => c.textContent);
  assert.deepEqual(cells(items[0]).slice(1), ['<b>push-guard.sh</b>Bash · PreToolUse · git push', 'unit-a', 'retried the identical call'],
    'When, Guard, Where, After: every stored field, each in its column');
  assert.equal($(dom, '#guard-blocks-list b'), null, 'a hook name is text, never markup');
  assert.match(items[1].textContent, /edit-guard\.sh.*Edit.*worked around it/s);
  assert.doesNotMatch(items[2].textContent, /retried|worked around|null|undefined|Claude|Codex/, 'an unknown retry and missing fields print nothing');
  mock.timers.tick(15000);
  // Which agent met the guard, per block and in total: a guard that only
  // blocks Codex points at a Codex-side gap, not a Claude habit.
  deliver(dom, snap({ guardBlocks: { blocks: 45, byAgent: { claude: 40, codex: 5 }, items: [
    { at, hook: 'push-guard.sh', event: 'PreToolUse', tool: 'Bash', agent: 'codex', worktree: 'unit-a', summary: 'git push', retry: null },
    { at, hook: 'edit-guard.sh', event: 'PreToolUse', tool: 'Edit', agent: 'claude', worktree: 'unit-b', summary: 'a/b.ts', retry: null },
    { at, hook: 'odd-guard.sh', event: 'PreToolUse', tool: 'Edit', agent: 'toString', worktree: null, summary: null, retry: 'constructor' },
  ] } }));
  assert.equal($(dom, '#guard-blocks-count').textContent, 'Latest 3 of 45 blocks (40 Claude, 5 Codex)');
  const byAgent = $$(dom, '#guard-blocks-list tr').map((r) => r.children[1]);
  assert.ok(byAgent[0].textContent.startsWith('push-guard.shBash · Codex'));
  assert.ok(byAgent[1].textContent.startsWith('edit-guard.shEdit · Claude'));
  assert.match($(dom, '#guard-facts').textContent, /45 blocks · Claude 40 · Codex 5/, 'the 7-day total names each agent');
  assert.doesNotMatch(byAgent[2].textContent, /function|native|toString|constructor|undefined/, 'an agent or retry the page does not know prints nothing');
  mock.timers.tick(15000);
  deliver(dom, snap({ guardBlocks: { blocks: 0, items: [] } }));
  assert.equal($(dom, '#guard-blocks-list').textContent, 'No blocks recorded');
  assert.equal($(dom, '#guard-blocks-count').textContent, '');
  mock.timers.tick(15000);
  const s = snap({ guardBlocks: { blocks: 0, items: [] } });
  s.sources['hook-fire-log'] = { sampledAt: null, status: 'not-measured', staleSince: null, error: 'missing' };
  deliver(dom, s);
  assert.equal($(dom, '#guard-blocks-list').textContent, 'No blocks recorded', 'a missing log shows the plain empty state');
  assert.equal($(dom, '#guard-blocks').dataset.state, 'not-measured');
  assert.ok($(dom, '#agents-list li'), 'the other panels still render');
});

test('app.js uses no HTML sink, eval or network API', () => {
  const sinks = /\.innerHTML|\.outerHTML|insertAdjacentHTML|document\.write|\beval\s*\(|\bnew\s+Function\b|\bFunction\s*\(|setAttribute\(\s*['"](on|style)|XMLHttpRequest|WebSocket|EventSource/;
  assert.doesNotMatch(appSrc, sinks);
  // The one request is the layout save to the page's own host.
  assert.deepEqual(appSrc.match(/\bfetch\b[^;]*/g), ["fetch('layout', { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }).then(answer).catch(() => done(false))"]);
  // The page reads its own address for the project, reloads onto new view files, and goes nowhere but to itself:
  // its bare address, or that with the home project's name from the snapshot, encoded. Never text from the URL.
  assert.deepEqual(appSrc.match(/[^\n;]*\blocation\.(?!protocol)[^;]*/g), [
    ' else if (a.view !== viewStamp && !sending) window.location.reload()',
    "  const asked = new window.URLSearchParams(window.location.search).get('project')",
    "    if (stray) window.location.replace(asked === null ? `index.html?project=${encodeURIComponent(home)}` : 'index.html')"]);
  const csp = html.match(/http-equiv="Content-Security-Policy" content="([^"]+)"/);
  assert.ok(csp, 'index.html carries a CSP meta tag');
  for (const d of ["default-src 'none'", "script-src 'self'", "style-src 'self'", "connect-src 'self'"]) assert.ok(csp[1].includes(d), d);
  assert.doesNotMatch(html, /https?:\/\/|<script>|<style|style="/, 'no remote resource, inline script or inline style');
});

test('the 15 s refresh reloads only data.js and keeps disclosure, focus and card nodes', () => {
  const dom = boot();
  deliver(dom, snap());
  const d = dom.window.document;
  const units = $(dom, '#units');
  const details = $(dom, '#cost-role-all');
  const summary = details.querySelector('summary');
  details.open = true;
  summary.focus();
  assert.equal(d.activeElement, summary, 'the summary takes keyboard focus');
  assert.equal(loaders(dom).length, 0, 'a finished loader is removed');
  mock.timers.tick(14999);
  assert.equal(loaders(dom).length, 0, 'no reload before 15 s');
  mock.timers.tick(1);
  assert.match(pending(dom).getAttribute('src'), /^data\.js\?\d+$/, 'a cache-busting local data.js');
  mock.timers.tick(15000);
  assert.equal(loaders(dom).length, 1, 'no overlapping load');
  const next = snap();
  next.needsOwner.decisions.push({ ...next.needsOwner.decisions[0], id: 'd2' });
  deliver(dom, next);
  assert.equal($(dom, '[data-count="decisions"]').textContent, '2', 'the new snapshot rendered');
  assert.equal($(dom, '#units'), units, 'cards are patched, not replaced');
  assert.equal(details.isConnected && details.open, true, 'an opened section stays open');
  assert.equal(d.activeElement, summary, 'focus survives the refresh');
  mock.timers.tick(15000);
  failLoad(dom);
  assert.equal($(dom, '[data-count="decisions"]').textContent, '2', 'a failed load keeps the last snapshot');
  assert.equal($(dom, '#refresh-note').hidden, false, 'a failed load is reported');
  assert.equal(loaders(dom).length, 0, 'a failed loader is removed');
});

test('null groups read not measured and stale sources are marked per card', () => {
  const dom = boot();
  const s = snap({ costPerRole: null, host: { cpus: null, load: null, swap: null, claudeProcs: null, codexProcs: null } });
  s.sources['git-main'] = { sampledAt: s.updatedAt, status: 'stale', staleSince: s.updatedAt, error: 'read failed' };
  s.sources['seat-events'] = { sampledAt: null, status: 'not-measured', staleSince: null, error: 'missing' };
  s.units = { inFlight: null };
  deliver(dom, s);
  assert.equal($(dom, '[data-count="building"]').textContent, 'not measured', 'an unknown unit list is not zero units');
  assert.match($(dom, '#cost-role').textContent, /not measured/i);
  assert.equal($(dom, '#cost-role').dataset.state, 'not-measured');
  assert.equal($(dom, '#main-chain').dataset.state, 'stale');
  assert.match($(dom, '#main-chain .age').textContent, /stale since/i);
  assert.match($(dom, '#host').textContent, /not measured/i);
  assert.doesNotMatch($(dom, '#summary').textContent, /\b0 processes\b/, 'a null count never reads as 0');
});

const row = (unit, stage, over = {}) => ({ unit, branch: `work/${unit}`, dirty: 1, agents: '',
  stage, ageSec: 60, diffStat: '1 file changed, 2 insertions(+)', ...over });
const card = (dom, name) => $$(dom, 'li.unit').find((li) => li.querySelector('.unit-name').textContent === name);
const inFlightValue = (dom) => $$(dom, '#summary > *').find((m) => /Units in flight/.test(m.textContent)).querySelector('.measure-value').textContent;

test('the page is named Commandeck Dashboard until the collector carries the name setup was given', () => {
  const dom = boot();
  assert.equal(dom.window.document.title, 'Commandeck Dashboard');
  assert.equal($(dom, 'h1').textContent, 'Commandeck Dashboard');
  deliver(dom, snap({ name: 'Atlas desk' }));
  assert.equal(dom.window.document.title, 'Atlas desk');
  assert.equal($(dom, 'h1').textContent, 'Atlas desk');
});

test('unknown stages sit in a closed group, the long-lived seat in its own, and only active stages count', () => {
  const dom = boot();
  const s = snap();
  s.units.inFlight = [row('unit-b', 'building'), row('unit-r', 'review'), row('unit-null', null), row('unit-odd', 'mystery'),
    row('unit-proto', 'constructor'), row('Chief-of-Staff', 'chief-of-staff')];
  deliver(dom, s);
  assert.equal(inFlightValue(dom), '2', 'only building, review, fixing and waiting-main count');
  const group = $(dom, '#unclassified');
  assert.equal(group.localName, 'details', 'the unknown group is a native toggle');
  assert.equal(group.open, false, 'it starts closed');
  assert.equal(group.hidden, false);
  assert.equal($(dom, '[data-count="unclassified"]').textContent, '3');
  const names = (list) => $$(dom, `[data-list="${list}"] li.unit`).map((li) => li.querySelector('.unit-name').textContent);
  assert.deepEqual(names('unclassified'), ['unit-null', 'unit-odd', 'unit-proto']);
  assert.deepEqual(names('permanent'), ['Chief-of-Staff'], 'the long-lived seat has its own group');
  assert.equal($(dom, '[data-count="permanent"]').textContent, '1');
  assert.equal($(dom, '#permanent').hidden, false);
  assert.match(card(dom, 'Chief-of-Staff').textContent, /Chief-of-Staff seat/);
  group.open = true;
  assert.equal(inFlightValue(dom), '2', 'opening the group changes no total');
  group.open = false;
  assert.equal(names('unclassified').length, 3, 'closing it keeps its cards');
  const allUnknown = boot();
  const u = snap();
  u.units.inFlight = [row('unit-null', null)];
  deliver(allUnknown, u);
  assert.equal(inFlightValue(allUnknown), '0', 'a measured list of unknowns is zero in flight');
  assert.equal($(allUnknown, '#permanent').hidden, true, 'an empty seat group is hidden');
  const blind = boot();
  u.units.inFlight = null;
  deliver(blind, u);
  assert.equal(inFlightValue(blind), '–', 'an unreadable list stays not measured');
});

test('a planning unit read as stage not known: it has its own Planning column and counts in flight', () => {
  const dom = boot();
  const s = snap();
  s.units.inFlight = [row('unit-p', 'planning')];
  deliver(dom, s);
  assert.ok($$(dom, '[data-list="planning"] li.unit').includes(card(dom, 'unit-p')), 'the unit sits in Planning');
  assert.match($(dom, '[data-stage="planning"] h3').textContent, /^Planning/);
  assert.equal(inFlightValue(dom), '1', 'planning is active work');
  // jsdom has no layout: a grid narrower than the column count wraps a stage under another.
  const columns = [...fs.readFileSync(path.join(VIEW, 'app.css'), 'utf8').matchAll(/\.stages \{[^}]*repeat\((\d+),/g)].map((m) => Number(m[1]));
  const stages = html.match(/class="stage" data-stage=/g).length;
  assert.deepEqual(columns, [stages, stages],'desktop and mobile boards keep every stage in one row');
});

test('every unit card keeps its last sign and change size in view and folds its detail behind a closed toggle', () => {
  const dom = boot();
  const s = snap();
  s.units.inFlight = [row('unit-b', 'building'), row('unit-r', 'review'), row('unit-f', 'fixing'),
    row('unit-w', 'waiting-main'), row('unit-u', null), row('Chief-of-Staff', 'chief-of-staff')];
  deliver(dom, s);
  const check = (li) => {
    const more = li.querySelectorAll(':scope > details');
    assert.equal(more.length, 1, 'one detail toggle per card');
    const d = more[0];
    assert.equal(d.open, false, 'detail starts closed');
    assert.equal(d.firstElementChild.localName, 'summary');
    const outside = [...li.children].filter((c) => c !== d).map((c) => c.textContent).join(' ');
    return { d, outside };
  };
  const cards = $$(dom, 'li.unit');
  assert.equal(cards.length, 6);
  for (const li of cards) {
    const { d, outside } = check(li);
    assert.match(outside, /Last sign 60 s ago/, 'the last sign stays in view');
    assert.match(outside, /1 files changed, not committed.*1 file changed, 2 insertions/s, 'so do the uncommitted files and the change size');
    assert.doesNotMatch(outside, /marker|Changed paths/, 'detail is not outside the toggle');
    assert.match(d.textContent, /1 file changed, 2 insertions/);
    assert.match(d.textContent, /Changed paths: 1/);
  }
});

test('a refresh keeps the cards the owner opened, and his focus, by unit wherever they move', () => {
  const dom = boot();
  const d = dom.window.document;
  const s = snap();
  s.units.inFlight = [row('unit-a', 'review'), row('unit-b', 'building'), row('unit-u', null)];
  deliver(dom, s);
  const more = (n) => card(dom, n).querySelector('details');
  more('unit-a').open = true;
  $(dom, '#unclassified').open = true;
  more('unit-a').querySelector('summary').focus();
  assert.equal(d.activeElement, more('unit-a').querySelector('summary'));
  mock.timers.tick(15000);
  const next = snap();
  next.units.inFlight = [row('unit-new', 'building'), row('unit-b', 'building'),
    row('unit-a', 'fixing', { diffStat: '9 files changed' }), row('unit-u', null)];
  deliver(dom, next);
  assert.ok($$(dom, '[data-list="fixing"] li.unit').includes(card(dom, 'unit-a')), 'unit-a moved stage');
  assert.equal(more('unit-a').open, true, 'an opened card stays open across a stage move');
  assert.match(more('unit-a').textContent, /9 files changed/, 'its detail is the new snapshot');
  assert.equal(d.activeElement, more('unit-a').querySelector('summary'), 'focus follows the unit');
  assert.equal(more('unit-b').open, false, 'another card stays closed');
  assert.equal(more('unit-new').open, false, 'a new card starts closed');
  assert.equal($(dom, '#unclassified').open, true, 'the opened unknown group stays open');
  more('unit-a').open = false;
  mock.timers.tick(15000);
  deliver(dom, next);
  assert.equal(more('unit-a').open, false, 'a card closed again stays closed');
});

// The owner folds the long-lived seat away when it is not needed; the fold is
// The owner's choice and must outlast the 15 s refresh and a reload. Open by default.
test('the Standing worktrees section folds behind its counted heading and stays folded across a refresh and a reload', () => {
  const seats = () => { const s = snap(); s.units.inFlight = [row('Chief-of-Staff', 'chief-of-staff')]; return s; };
  const dom = boot();
  deliver(dom, seats());
  const sec = $(dom, '#permanent');
  assert.equal(sec.localName, 'details', 'a native toggle');
  assert.equal(sec.open, true, 'open by default');
  const sum = sec.querySelector(':scope > summary');
  assert.match(sum.textContent, /Standing worktrees\s*1/, 'the heading carries the count');
  click(dom, sum);
  assert.equal(sec.open, false);
  mock.timers.tick(1);
  assert.deepEqual(JSON.parse(dom.window.localStorage.getItem(COLLAPSED_KEY)), ['permanent'], 'the fold is saved');
  mock.timers.tick(14999);
  deliver(dom, seats());
  assert.equal(sec.open, false, 'a refresh keeps it folded');
  assert.equal(sum.textContent.includes('1'), true, 'the folded heading still shows the count');
  const again = boot({ collapsed: dom.window.localStorage.getItem(COLLAPSED_KEY) });
  deliver(again, seats());
  assert.equal($(again, '#permanent').open, false, 'a reload keeps it folded');
  click(again, $(again, '#permanent > summary'));
  assert.equal($(again, '#permanent').open, true);
  mock.timers.tick(1); // toggle is a queued event, as in a browser
  assert.equal(boot({ collapsed: again.window.localStorage.getItem(COLLAPSED_KEY) }).window.document.querySelector('#permanent').open, true,
    'reopening is remembered too');
});

// The owner arranges the panels to suit how he reads them. The order is his and
// outlives the 15 s refresh and a page reload; every panel moves, Units and
// Needs the owner included; the DOM order is the layout, so a narrow grid follows it.
const order = (dom) => [...$(dom, 'main.grid').children].map((c) => c.id);
const saved = (dom) => JSON.parse(dom.window.localStorage.getItem(ORDER_KEY));
const stored = (dom, key) => JSON.parse(dom.window.localStorage.getItem(key));
const click = (dom, el) => el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true }));
const moveBtn = (dom, id, dir) => $(dom, `#${id} .card-head button[data-move="${dir}"]`);
const sizeBtn = (dom, id, n) => $(dom, `#${id} .card-head .sz button[data-s="${n}"]`);

test('a saved card order applies on load and survives the refresh; unknown ids are ignored and new cards go last', () => {
  const dom = boot({ saved: JSON.stringify(['agents', 'ghost', 'todos', 'host', 'agents']) });
  const want = ['agents', 'todos', 'host', ...DEFAULT_ORDER.filter((id) => !['agents', 'todos', 'host'].includes(id))];
  assert.deepEqual(order(dom), want);
  const agents = $(dom, '#agents');
  deliver(dom, snap());
  mock.timers.tick(15000);
  deliver(dom, snap());
  assert.deepEqual(order(dom), want, 'a re-render keeps the order');
  assert.equal($(dom, '#agents'), agents, 'the card is the same node, patched in place');
  assert.match($(dom, '#agents-list').textContent, /Find it/, 'the moved card still renders its data');
  for (const bad of ['not json', '{"a":1}', '[1,null]']) {
    assert.deepEqual(order(boot({ saved: bad })), DEFAULT_ORDER, `an unreadable saved order (${bad}) is the default`);
  }
});

// The panel frame: the owner sets each panel's width, 1 to 4. Width 1 is the
// compact view; 2 to 4 also show the detail. The choice is his and is remembered.
test('each panel has four width buttons; a width is applied, marked, saved and restored, and width 1 is the compact view', () => {
  const dom = boot();
  const sizes = (d) => Object.fromEntries($$(d, 'main.grid > .card').map((c) => [c.id, Number(c.dataset.size)]));
  assert.deepEqual(sizes(dom), Object.fromEntries(DEFAULT_ORDER.map((id) => [id, DEFAULT_SIZES[id] || 1])), "the default widths are the mockup's");
  for (const id of DEFAULT_ORDER) {
    const on = $$(dom, `#${id} .sz button`).filter((b) => b.classList.contains('on'));
    assert.equal($$(dom, `#${id} .sz button`).length, 4, `${id} has four width buttons`);
    assert.deepEqual(on.map((b) => b.dataset.s), [String(DEFAULT_SIZES[id] || 1)], `${id} marks its current width`);
    assert.equal(on[0].getAttribute('aria-pressed'), 'true');
  }
  click(dom, sizeBtn(dom, 'host', 3));
  assert.equal($(dom, '#host').dataset.size, '3');
  assert.equal(sizeBtn(dom, 'host', 3).getAttribute('aria-pressed'), 'true');
  assert.equal(sizeBtn(dom, 'host', 1).getAttribute('aria-pressed'), 'false');
  assert.equal(stored(dom, SIZES_KEY).host, 3, 'the width is saved');
  deliver(dom, snap());
  assert.equal($(dom, '#host').dataset.size, '3', 'a refresh keeps it');
  const again = boot({ store: { [SIZES_KEY]: dom.window.localStorage.getItem(SIZES_KEY) } });
  assert.equal($(again, '#host').dataset.size, '3', 'a reload restores it');
  assert.equal(sizeBtn(again, 'host', 3).classList.contains('on'), true);
  // jsdom has no layout: the compact rule is read from the stylesheet itself.
  const css = fs.readFileSync(path.join(VIEW, 'app.css'), 'utf8');
  assert.match(css, /\.card\[data-size="1"\] \.more\s*\{[^}]*display:\s*none/, 'width 1 hides the detail parts');
  for (const n of [2, 3]) assert.ok(new RegExp(`\\.card\\[data-size="${n}"\\]\\s*\\{[^}]*grid-column:\\s*span ${n}`).test(css), `width ${n} spans ${n} columns`);
  assert.match(css, /\.card\[data-size="4"\]\s*\{[^}]*grid-column:\s*1 \/ -1/, 'width 4 is the whole row');
  assert.ok($(dom, '#host .more'), 'a panel carries its detail in .more parts');
});

test('a saved layout that is not valid falls back to the default, value by value', () => {
  for (const bad of ['not json', '[]', 'null', '{"host":9,"cost-role":"2","alerts":0,"ghost":3,"__proto__":{"x":1}}']) {
    const dom = boot({ store: { [SIZES_KEY]: bad, [HEIGHTS_KEY]: bad, [HIDDEN_KEY]: bad } });
    for (const id of DEFAULT_ORDER) {
      assert.equal($(dom, `#${id}`).dataset.size, String(DEFAULT_SIZES[id] || 1), `${id} keeps its default width for ${bad}`);
      assert.equal($(dom, `#${id}`).hasAttribute('data-height'), false);
      assert.equal($(dom, `#${id}`).hidden, false);
    }
  }
  const mixed = boot({ store: { [SIZES_KEY]: '{"host":2,"cost-role":7}', [HIDDEN_KEY]: '["alerts","ghost",5,"host"]' } });
  assert.equal($(mixed, '#host').dataset.size, '2', 'a good value beside a bad one still applies');
  assert.equal($(mixed, '#cost-role').dataset.size, '1');
  assert.equal($(mixed, '#host').hidden, true);
  assert.equal($(mixed, '#alerts').hidden, true, 'Alerts hides like any other panel');
});

// The Alerts card, the cache tile and the hit rate.
test('the Alerts card lists each active alert as text with its severity, and a missing input reads not measured, never no alerts', () => {
  const dom = boot();
  deliver(dom, snap({ alerts: [
    { id: 'host-load-1', severity: 'warn', text: 'Host overloaded: <b>load</b> 9 on 4 cores', since: iso(Date.now() - 600000) },
    { id: 'deploy-prod-1', severity: 'crit', text: 'prod deploy failed', since: iso(Date.now()) },
  ] }));
  const li = $$(dom, '#alerts-list li');
  assert.equal(li.length, 2);
  assert.match(li[0].textContent, /Host overloaded: <b>load<\/b> 9 on 4 cores/);
  assert.deepEqual(li.map((l) => l.querySelector('.badge').textContent), ['warning', 'critical'], 'the severity is a word, never colour alone');
  assert.match(li[0].textContent, /since 10 min ago/);
  assert.match(li[1].textContent, /since 0 s ago/);
  assert.equal($(dom, '#alerts b'), null, 'alert text is text, never markup');
  assert.equal($(dom, '#alerts-sub').textContent, '2 open');
  mock.timers.tick(15000);
  deliver(dom, snap({ alerts: [] }));
  assert.equal($(dom, '#alerts-list').textContent, 'No alerts');
  mock.timers.tick(15000);
  const s = snap({ alerts: [] });
  s.sources.alerts = { sampledAt: null, status: 'not-measured', staleSince: null, error: 'host load, questions for the owner' };
  deliver(dom, s);
  assert.match($(dom, '#alerts .card-note').textContent, /Not measured: host load, questions for the owner/);
  assert.doesNotMatch($(dom, '#alerts-list').textContent, /No alerts/, 'an unmeasured input is not "no alerts"');
  mock.timers.tick(15000);
  deliver(dom, snap({ alerts: null }));
  assert.match($(dom, '#alerts').textContent, /Alerts not measured/);
  assert.doesNotMatch($(dom, '#alerts-list').textContent, /No alerts/);
  assert.equal($(dom, '#alerts').dataset.sources, 'alerts', 'the card reads the collector, not main-watch');
});

// One alert input unread marked the whole source unmeasured, so the header said "alerts not measured" above the open alerts.
test('alerts_header_names_a_part_not_the_whole: with alerts listed and one input unread, the header does not say alerts are not measured', () => {
  const dom = boot();
  const s = snap({ alerts: [{ id: 'deploy-prod-1', severity: 'crit', text: 'prod deploy failed', since: iso(Date.now()) }] });
  s.sources.alerts = { sampledAt: null, status: 'not-measured', staleSince: null, error: 'host load' };
  deliver(dom, s);
  assert.equal($(dom, '#alerts-sub').textContent, '1 open');
  assert.equal($(dom, '#alerts .age').textContent, 'part not measured', 'the note below names the part');
  assert.match($(dom, '#alerts .card-note').textContent, /Not measured: host load/);
  mock.timers.tick(15000);
  const none = snap({ alerts: null });
  none.sources.alerts = { sampledAt: null, status: 'not-measured', staleSince: null, error: 'the rules failed' };
  deliver(dom, none);
  assert.equal($(dom, '#alerts .age').textContent, 'alerts not measured', 'no list at all is still the whole');
});
// A brief whose items carry no issue numbers gave an empty list, drawn as "0 of 0 issues recorded as built".
test('build_with_no_issue_numbers_shows_no_count: a brief that lists no issue numbers says so instead of 0 of 0', () => {
  const dom = boot();
  const s = snap();
  s.units.inFlight = [builderRow('batch-plain', 'building', { issues: [], built: [] })];
  deliver(dom, s);
  const cap = build(dom, 'batch-plain').querySelector('.cap').textContent;
  assert.match(cap, /The brief lists no issue numbers/);
  assert.doesNotMatch(cap, /0 of 0/);
});

test('a stopped collector adds its alert between collects, and the Alerts panel then needs a look', () => {
  const dom = boot();
  deliver(dom, snap({ alerts: [] }));
  assert.equal($(dom, '#alerts').hasAttribute('data-look'), false);
  mock.timers.tick(181000);
  assert.match($(dom, '#alerts-list').textContent, /Collector dead/);
  assert.equal($(dom, '#alerts').hasAttribute('data-look'), true, 'the alert lands without waiting for the next collect');
});

test('the cache tile and the per-role hit rate are cachedInput over input, and not measured when input is null', () => {
  const dom = boot();
  deliver(dom, snap({ costPerRole: [
    { role: 'sol', seats: 2, unmeasuredSeats: 0, input: 1000, cachedInput: 900, output: 5 },
    { role: 'bob', seats: 1, unmeasuredSeats: 0, input: 1000, cachedInput: 500, output: 5 },
  ] }));
  assert.match($(dom, '#cache-tile').textContent, /70%/, '1400 of 2000 input tokens were cached');
  const rows = $$(dom, '#cost-role-rows tr');
  assert.match(rows[0].textContent, /90%/);
  assert.match(rows[1].textContent, /50%/);
  // The audit's F24: one seat read "1 seats".
  assert.doesNotMatch($(dom, '#cost-role').textContent, /\b1 seats/, 'one_seat_is_singular');
  assert.match($(dom, '#cost-role').textContent, /\b1 seat\b/);
  mock.timers.tick(15000);
  deliver(dom, snap({ costPerRole: [{ role: 'sol', seats: 2, unmeasuredSeats: 1, input: null, cachedInput: null, output: null }] }));
  assert.match($(dom, '#cache-tile').textContent, /not measured/i, 'an unmeasured input is not a 0% hit rate');
  assert.doesNotMatch($(dom, '#cache-tile').textContent, /0%/);
  assert.match($$(dom, '#cost-role-rows tr')[0].textContent, /not measured/i);
});

test('Move earlier and Move later are real buttons that reorder, save, keep focus and stop at the ends', () => {
  const dom = boot();
  assert.deepEqual(order(dom), DEFAULT_ORDER);
  for (const id of DEFAULT_ORDER) {
    for (const dir of ['earlier', 'later']) {
      const b = moveBtn(dom, id, dir);
      assert.ok(b && b.localName === 'button' && b.type === 'button', `${id} has a ${dir} button`);
      assert.match(b.getAttribute('aria-label'), new RegExp(`^Move .+ ${dir}$`));
    }
  }
  const later = moveBtn(dom, 'host', 'later');
  later.focus();
  click(dom, later);
  const at = DEFAULT_ORDER.indexOf('host');
  assert.deepEqual(order(dom).slice(at, at + 2), ['cost-role', 'host']);
  assert.deepEqual(saved(dom), order(dom), 'the new order is saved');
  assert.equal(dom.window.document.activeElement, later, 'focus stays on the button that moved');
  click(dom, moveBtn(dom, 'alerts', 'earlier'));
  assert.equal(order(dom)[0], 'alerts', 'the first card stays first');
  click(dom, moveBtn(dom, 'agents', 'later'));
  assert.equal(order(dom).at(-1), 'agents', 'the last card stays last');
  click(dom, moveBtn(dom, 'agents', 'earlier'));
  assert.deepEqual(order(dom).slice(-2), ['agents', 'chief-of-staff']);
  assert.deepEqual(saved(dom), order(dom));
  assert.deepEqual(order(boot({ saved: JSON.stringify(saved(dom)) })), order(dom), 'a reload restores it');
});

// A small panel can be made shorter or taller so the grid packs tighter; the
// choice is the owner's per panel and must survive a refresh and a reload like the width.
test('the height button steps auto, half, tall and back; the height is applied, saved per panel and restored', () => {
  const dom = boot();
  const tall = (d) => $(d, '#chief-of-staff button[data-tall]');
  assert.equal(tall(dom).textContent, 'Height: auto');
  assert.equal($(dom, '#chief-of-staff').hasAttribute('data-height'), false);
  click(dom, tall(dom));
  assert.equal($(dom, '#chief-of-staff').dataset.height, 'half');
  assert.equal(tall(dom).textContent, 'Height: half');
  assert.equal(stored(dom, HEIGHTS_KEY)['chief-of-staff'], 'half', 'the height is saved under its panel');
  assert.equal(stored(dom, HEIGHTS_KEY).host, 'auto', 'another panel keeps its own');
  deliver(dom, snap());
  assert.equal($(dom, '#chief-of-staff').dataset.height, 'half', 'a refresh keeps it');
  const again = boot({ store: { [HEIGHTS_KEY]: dom.window.localStorage.getItem(HEIGHTS_KEY) } });
  assert.equal($(again, '#chief-of-staff').dataset.height, 'half', 'a reload restores it');
  click(dom, tall(dom));
  assert.equal($(dom, '#chief-of-staff').dataset.height, 'tall');
  click(dom, tall(dom));
  assert.equal($(dom, '#chief-of-staff').hasAttribute('data-height'), false, 'the third press is back to the panel\'s own height');
  const css = fs.readFileSync(path.join(VIEW, 'app.css'), 'utf8');
  assert.match(css, /\.card\[data-height="half"\]:not\(\[style\*="height"\]\)\s*\{[^}]*max-height:[^}]*overflow-y:\s*auto/, 'half is a capped panel that scrolls');
  assert.doesNotMatch(css, /\.card\[data-height="half"\]\s*\{[^}]*max-height/, 'the cap lets go once a drag has written a height, or half could not be dragged taller');
  assert.match(css, /\.card\[data-height="tall"\]\s*\{[^}]*grid-row:\s*span 4/, 'tall takes four rows of the grid');
});

// A panel can be dragged to any height, not only auto, half and tall. The browser's own resize handle writes
// the dragged height to the panel's style; the page saves that number with the layout, so the size the owner
// dragged to is still there after a reload and in another browser.
test('custom_height_survives_reload_and_a_preset_replaces_it: a dragged panel height is saved as a number, restored, sent to the host, and dropped by a preset', async () => {
  const dom = boot();
  deliver(dom, snap());
  mock.timers.tick(15000);
  const card = (d) => $(d, '#chief-of-staff');
  const drag = (d, px) => { card(d).style.height = px; d.window.document.dispatchEvent(new d.window.MouseEvent('mouseup', { bubbles: true })); };
  drag(dom, '333.4px');
  assert.equal(stored(dom, HEIGHTS_KEY)["chief-of-staff"], 333, 'the dragged height is saved under its panel, in whole pixels');
  assert.equal(stored(dom, HEIGHTS_KEY).host, 'auto', 'a panel that was not dragged keeps its own');
  assert.equal($(dom, '#chief-of-staff button[data-tall]').textContent, 'Height: 333 px');
  await settle();
  assert.equal(dom.window.puts.at(-1).heights["chief-of-staff"], 333, 'the host is sent it, as it is sent a preset');
  deliver(dom, snap());
  assert.equal(card(dom).style.height, '333px', 'a refresh keeps it');
  const again = boot({ store: { [HEIGHTS_KEY]: dom.window.localStorage.getItem(HEIGHTS_KEY) } });
  assert.equal(card(again).style.height, '333px', 'a reload restores it');
  assert.equal($(again, '#chief-of-staff button[data-tall]').textContent, 'Height: 333 px');
  assert.equal(card(boot({ layout: { heights: { "chief-of-staff": 333 } } })).style.height, '333px', 'a fresh browser session gets it from the host');
  click(dom, $(dom, '#chief-of-staff button[data-tall]'));
  assert.deepEqual([card(dom).dataset.height, card(dom).style.height, stored(dom, HEIGHTS_KEY)["chief-of-staff"]], ['half', '', 'half'], 'a preset replaces the custom height');
  drag(dom, '250px');
  assert.deepEqual([card(dom).hasAttribute('data-height'), stored(dom, HEIGHTS_KEY)["chief-of-staff"]], [false, 250], 'and a drag replaces the preset');
  click(dom, $(dom, '#reset-layout'));
  assert.equal(card(dom).style.height, '', 'Reset layout clears it');
  drag(dom, '5px');
  assert.equal(stored(dom, HEIGHTS_KEY)["chief-of-staff"], 60, 'a panel cannot be saved too short to grab again');
  for (const bad of [59, 4001, 333.5, '333', true, null]) assert.equal(card(boot({ layout: { heights: { "chief-of-staff": bad } } })).style.height, '', `a saved height of ${JSON.stringify(bad)} falls back to the panel's own`);
  const css = fs.readFileSync(path.join(VIEW, 'app.css'), 'utf8');
  assert.match(css, /\n\.card \{[^}]*resize:\s*vertical;[^}]*overflow:\s*auto/, 'every panel has the browser\'s own resize handle');
});

// The owner can put a panel away and get it back; an alert's link unhides its panel. Alerts hides too
// (the owner's ruling): while it is hidden the top tile still counts the alerts.
test('a panel can be hidden and comes back with Show hidden; hidden panels are remembered', () => {
  const dom = boot();
  const unhide = $(dom, '#unhide');
  assert.equal(unhide.hidden, true, 'nothing hidden, no unhide button');
  for (const id of DEFAULT_ORDER) assert.ok($(dom, `#${id} button[data-hide]`), `${id} can be hidden`);
  click(dom, $(dom, '#cost-role button[data-hide]'));
  click(dom, $(dom, '#host button[data-hide]'));
  assert.equal($(dom, '#cost-role').hidden && $(dom, '#host').hidden, true);
  assert.equal(unhide.hidden, false);
  assert.equal(unhide.textContent, 'Show hidden (2)');
  assert.deepEqual(stored(dom, HIDDEN_KEY).sort(), ['cost-role', 'host']);
  deliver(dom, snap({ alerts: [{ id: 'host-load-1', severity: 'warn', text: 'Host overloaded', since: iso(Date.now()) }] }));
  assert.equal($(dom, '#host').hidden, true, 'a refresh keeps it hidden');
  assert.match($(dom, '#alerts-list').textContent, /Host overloaded/, 'the hidden panel\'s alert still shows in Alerts');
  const again = boot({ store: { [HIDDEN_KEY]: dom.window.localStorage.getItem(HIDDEN_KEY) } });
  assert.equal($(again, '#cost-role').hidden, true, 'a reload keeps it hidden');
  assert.equal($(again, '#unhide').textContent, 'Show hidden (2)');
  click(dom, $(dom, '#alerts-list a[href="#host"]'));
  assert.equal($(dom, '#host').hidden, false, 'following an alert to a hidden panel brings that panel back');
  assert.equal($(dom, '#cost-role').hidden, true, 'and only that one');
  assert.deepEqual(stored(dom, HIDDEN_KEY), ['cost-role']);
  click(dom, unhide);
  assert.equal($(dom, '#cost-role').hidden, false, 'Show hidden restores every hidden panel at once');
  assert.equal(unhide.hidden, true);
  assert.deepEqual(stored(dom, HIDDEN_KEY), []);
});
test('alerts_hide_survives_reload: hiding Alerts survives a reload and Show hidden brings it back', () => {
  const dom = boot();
  click(dom, $(dom, '#alerts button[data-hide]'));
  assert.equal($(dom, '#alerts').hidden, true);
  assert.deepEqual(stored(dom, HIDDEN_KEY), ['alerts']);
  const again = boot({ store: { [HIDDEN_KEY]: dom.window.localStorage.getItem(HIDDEN_KEY) } });
  assert.equal($(again, '#alerts').hidden, true, 'a reload keeps Alerts hidden');
  assert.equal($(again, '#unhide').textContent, 'Show hidden (1)');
  click(again, $(again, '#unhide'));
  assert.equal($(again, '#alerts').hidden, false, 'Show hidden brings Alerts back');
});

// One switch leaves only what needs the owner. A panel with nothing wrong that
// stayed would make the filter useless; one with a problem that went would hide the problem.
test('the needs-a-look switch leaves only panels with an alert, a warning, something waiting or a source that is not fresh', () => {
  const dom = boot();
  const s = snap({ alerts: [] });
  for (const c of $$(dom, 'main.grid > .card')) for (const id of c.dataset.sources.split(' ')) s.sources[id] = fresh(s.updatedAt);
  s.units.inFlight = [];
  s.needsOwner.decisions = [];
  s.host.swap = { totalMb: 2048, usedMb: 100 };
  deliver(dom, s);
  const marked =() => $$(dom, 'main.grid > .card[data-look]').map((c) => c.id);
  assert.deepEqual(marked(), ['main-chain', 'cost-role', 'chief-of-staff'],
    'with every source fresh, only what shows a problem is marked: unpushed commits, a seat with no token count, the Chief of Staff\'s old unread message');
  mock.timers.tick(15000);
  const t = snap({ alerts: [{ id: 'host-load-1', severity: 'warn', text: 'Host overloaded', since: iso(Date.now()) }] });
  Object.assign(t.sources, s.sources);
  for (const k of Object.keys(t.sources)) t.sources[k] = fresh(t.updatedAt);
  t.sources.todos = { sampledAt: t.updatedAt, status: 'stale', staleSince: t.updatedAt, error: 'gh failed' };
  t.units.inFlight = [];
  deliver(dom, t);
  assert.ok(marked().includes('alerts'), 'open alerts');
  assert.ok(marked().includes('needs'), 'a decision waiting on the owner');
  assert.ok(marked().includes('todos'), 'a stale source');
  assert.ok(!marked().includes('units') && !marked().includes('agents'), 'panels with nothing wrong are not marked');
  const sw = $(dom, '#needs-look');
  assert.equal(sw.type, 'checkbox');
  assert.equal(dom.window.document.body.classList.contains('look-only'), false);
  sw.checked = true;
  sw.dispatchEvent(new dom.window.Event('change', { bubbles: true }));
  assert.equal(dom.window.document.body.classList.contains('look-only'), true);
  const css = fs.readFileSync(path.join(VIEW, 'app.css'), 'utf8');
  assert.match(css, /body\.look-only \.card:not\(\[data-look\]\)\s*\{[^}]*display:\s*none/, 'the switch hides every unmarked panel');
  // A summary tile to a filtered-out panel switches the filter off rather than jumping to nothing.
  click(dom, $(dom, '#summary a[href="#units"]'));
  assert.equal(sw.checked, false);
  assert.equal(dom.window.document.body.classList.contains('look-only'), false);
  const again = boot();
  assert.equal($(again, '#needs-look').checked, false, 'the switch is not remembered: a reload shows every panel');
});

// The strip is the page's index: each tile and each alert is a link to the panel that holds its detail.
test('the summary strip has nine tiles, each a link to its panel, and an alert links to the panel it is about', () => {
  const dom = boot();
  deliver(dom, snap({ alerts: [{ id: 'limit-claude-1', severity: 'crit', text: 'limit', since: iso(Date.now()) },
    { id: 'builder-unit-x-stuck-1', severity: 'warn', text: 'stuck', since: iso(Date.now()) },
    { id: 'mystery-1', severity: 'warn', text: 'unknown kind', since: iso(Date.now()) }] }));
  assert.deepEqual($$(dom, '#summary a.measure').map((m) => [text(m, '.measure-label'), m.getAttribute('href')]), [
    ['Alerts', '#alerts'], ['Waiting on the owner', '#needs'], ['Builds running', '#builds'], ['Claude 7-day', '#limit'], ['Codex 7-day', '#limit'], ['Cost today', '#limit'],
    ['Unpushed', '#main-chain'], ['Units in flight', '#units'], ['Host load', '#host']]);
  for (const m of $$(dom, '#summary a.measure')) assert.ok($(dom, `main.grid > .card${m.getAttribute('href')}`), `${m.getAttribute('href')} is a panel`);
  const li = $$(dom, '#alerts-list li');
  assert.deepEqual(li.map((l) => (l.querySelector('a') ? l.querySelector('a').getAttribute('href') : null)), ['#limit', '#builds', null],
    'an alert of a known kind links to its panel; an unknown kind has no link, never a wrong one');
});

// The day's combined token cost sits in the top strip, the picked project's own. It is the collector's one priced
// sum, so a part that is missing, estimated or unpriced is said on the tile, never folded into a clean figure.
test('cost_today_tile: the strip shows the project\'s Claude and Codex cost for the day, and marks a total that is not whole', () => {
  const tile = (today) => { const dom = boot(); deliver(dom, snap({ limit: { ...limitSnap(), today } })); return strip(dom)['Cost today']; };
  const whole = tile({ demo: { spentUsd: 32.4, claudeUsd: 30.4, codexUsd: 2, estimatedUsd: 0, unpricedRequests: 0, unpricedModels: [], complete: true } });
  assert.equal(text(whole, '.measure-value'), '$32.40');
  assert.equal(text(whole, '.measure-detail'), 'Claude $30.40 + Codex $2.00, list price');
  assert.equal(whole.className, 'measure');
  const part = tile({ demo: { spentUsd: 1234.5, claudeUsd: 1234.5, codexUsd: null, estimatedUsd: 4, unpricedRequests: 2, unpricedModels: ['gpt-9-nova'], complete: false } });
  assert.equal(text(part, '.measure-value'), 'at least $1.2k', 'a total with a part missing is a floor');
  assert.equal(text(part, '.measure-detail'), 'Claude $1.2k + Codex not measured, list price · $4.00 estimated · 2 requests unpriced');
  assert.ok(part.classList.contains('warn'));
  // #36: a Codex price taken from its tier, not its exact version, says so.
  const tier = tile({ demo: { spentUsd: 2, claudeUsd: 0, codexUsd: 2, estimatedUsd: 0, tierUsd: 1.5, unpricedRequests: 0, unpricedModels: [], complete: true } });
  assert.equal(text(tier, '.measure-detail'), 'Claude $0.00 + Codex $2.00, list price · $1.50 priced by tier, not exact version');
  // Another project's day is never this one's: a project with no figure of its own is not measured.
  for (const none of [undefined, null, {}, { other: { spentUsd: 9, claudeUsd: 9, codexUsd: 0, complete: true } }, { demo: { spentUsd: null, claudeUsd: null, codexUsd: null, complete: false } }]) {
    const t = tile(none);
    assert.equal(text(t, '.measure-value'), '–', 'no day figure is not measured, never $0');
    assert.ok(t.classList.contains('nm'));
  }
});

// Units that have waited on main a day or more would each be a red card; they
// fold into one counted line so the live ones stay readable, and still count as waiting.
test('units waiting on main a day or more fold into one counted line that opens to show them', () => {
  const dom = boot();
  const s = snap();
  s.units.inFlight = [row('unit-old1', 'waiting-main', { ageSec: 86400 }), row('unit-old2', 'waiting-main', { ageSec: 400000 }),
    row('unit-new', 'waiting-main', { ageSec: 86399 }), row('unit-b', 'building', { ageSec: 400000 })];
  deliver(dom, s);
  const names = (list) => $$(dom, `[data-list="${list}"] li.unit`).map((li) => li.querySelector('.unit-name').textContent);
  const fold = $(dom, '#stale-units');
  assert.equal(fold.localName, 'details');
  assert.equal(fold.hidden, false);
  assert.equal(fold.open, false, 'folded until the owner opens it');
  assert.match(fold.querySelector('summary').textContent, /^2 waiting on main a day or more$/);
  assert.deepEqual(names('stale').sort(), ['unit-old1', 'unit-old2']);
  assert.deepEqual($$(dom, '[data-stage="waiting-main"] > [data-list="waiting-main"] li.unit .unit-name').map((e) => e.textContent), ['unit-new'], 'a unit one second short of a day keeps its own card');
  assert.deepEqual(names('building'), ['unit-b'], 'only a unit waiting on main folds, however old');
  assert.equal($(dom, '[data-count="waiting-main"]').textContent, '3', 'the folded units still count as waiting on main');
  mock.timers.tick(15000);
  const t = snap();
  t.units.inFlight = [row('unit-new', 'waiting-main', { ageSec: 10 })];
  deliver(dom, t);
  assert.equal($(dom, '#stale-units').hidden, true, 'no line with none');
});

// Codex's readings are now stored over time, so the graph draws its line beside Claude's in its own colour.
test('the limit graph draws a Codex line from its stored readings, and none from fewer than two', () => {
  const dom = boot();
  const codex = { usedPct: 20, goalPct: 56.2, underPts: 36.2, paceSec: 1, timeLeftSec: 264600, windowStart: iso(T0 - 94.5 * HOUR), resetsAt: iso(T0 + 73.5 * HOUR), readAt: iso(T0 - 60000),
    history: [{ at: iso(T0 - 80 * HOUR), pct: 5 }, { at: iso(T0 - 30 * HOUR), pct: 12 }, { at: iso(T0 - 60000), pct: 20 }] };
  deliver(dom, snap({ limit: limitSnap({ codex }) }));
  const d = $(dom, '#limit-chart svg .codex-line').getAttribute('d');
  assert.equal((d.match(/H/g) || []).length, 2, 'one step per later Codex reading');
  assert.ok($(dom, '#limit-chart svg .actual-line'), 'Claude\'s line is still drawn');
  assert.match($(dom, '#limit-graph-title').textContent, /Claude 3 samples, Codex 3 samples/);
  mock.timers.tick(15000);
  deliver(dom, snap({ limit: limitSnap({ codex: { ...codex, history: codex.history.slice(0, 1) } }) }));
  assert.equal($(dom, '#limit-chart svg .codex-line'), null, 'one reading is no line');
  assert.match($(dom, '#limit-graph-title').textContent, /Codex no history yet/);
  mock.timers.tick(15000);
  deliver(dom, snap({ limit: limitSnap({ codex: { ...codex, history: null } }) }));
  assert.equal($(dom, '#limit-chart svg .codex-line'), null, 'no stored history draws nothing, never a flat line');
});

// The footer says how much of the page is fresh, and names what is not.
test('the footer counts the fresh data sources and names the stale and unmeasured ones', () => {
  const dom = boot();
  const s = snap();
  const n = Object.keys(s.sources).length;
  deliver(dom, s);
  assert.match($(dom, '#sources-foot').textContent, new RegExp(`^${n} of ${n} data sources fresh · sampled `));
  mock.timers.tick(15000);
  const t = snap();
  t.sources['git-main'] = { sampledAt: t.updatedAt, status: 'stale', staleSince: t.updatedAt, error: 'x' };
  t.sources.host = { sampledAt: null, status: 'not-measured', staleSince: null, error: 'x' };
  deliver(dom, t);
  assert.match($(dom, '#sources-foot').textContent, new RegExp(`^${n - 2} of ${n} data sources fresh · stale: git-main · not measured: host · sampled `));
  mock.timers.tick(15000);
  deliver(dom, { ...snap(), sources: null });
  assert.equal($(dom, '#sources-foot').textContent, 'Data sources not measured', 'no source list is not measured, never "all fresh"');
});

// The owner's order "it should remember the pane settings no matter what PC theyre accessed from".
test('layout_follows_the_host: the layout the host serves wins over this browser\'s own, and an invalid value falls back', () => {
  const dom = boot({ store: { [SIZES_KEY]: '{"host":2}', [HIDDEN_KEY]: '["cost-role"]' },
    layout: { order: ['agents', 'todos'], sizes: { host: 3, 'cost-role': 9 }, heights: { 'chief-of-staff': 'half' }, hidden: ['guard-blocks'], closed: ['unit-x'] } });
  assert.equal(order(dom)[0], 'agents');
  assert.equal($(dom, '#host').dataset.size, '3', 'the host\'s width, not this browser\'s');
  assert.equal($(dom, '#cost-role').dataset.size, '1', 'a width out of range falls back to the default');
  assert.equal($(dom, '#chief-of-staff').dataset.height, 'half');
  assert.equal($(dom, '#guard-blocks').hidden, true);
  assert.equal($(dom, '#cost-role').hidden, false, 'this browser\'s older hidden list is replaced, not merged');
  for (const bad of [null, 'x', 7, []]) assert.deepEqual(order(boot({ layout: bad })), DEFAULT_ORDER, `a layout of ${JSON.stringify(bad)} is no layout`);
});
const settle = async () => { for (let i = 0; i < 8; i += 1) await Promise.resolve(); };
test('layout_change_is_saved_to_the_host: every layout change sends the whole layout, and Reset layout sends an empty one', async () => {
  const dom = boot({ layout: {} });
  assert.deepEqual(dom.window.puts, [], 'reading the layout sends nothing');
  click(dom, sizeBtn(dom, 'host', 3));
  await settle();
  click(dom, $(dom, '#cost-role button[data-hide]'));
  await settle();
  assert.equal(dom.window.puts.length, 2);
  assert.equal(dom.window.puts[1].sizes.host, 3);
  assert.deepEqual(dom.window.puts[1].hidden, ['cost-role'], 'each save carries every setting, so the host file is always whole');
  click(dom, $(dom, '#reset-layout'));
  await settle();
  assert.deepEqual(dom.window.puts[2], { rev: 2 }, 'a reset clears the host\'s copy too');
  const next = boot({ layout: dom.window.puts[1] });
  assert.equal($(next, '#host').dataset.size, '3', 'another browser given that layout shows it');
  assert.equal($(next, '#cost-role').hidden, true);
});
// Two saves in flight could land in either order, so an older one could undo Reset layout on the host.
test('older_save_never_lands_after_a_newer_one: one save is in flight at a time, and the next one carries the newest layout', async () => {
  const dom = boot({ layout: {} }); const w = dom.window;
  w.slowHost = true;
  click(dom, sizeBtn(dom, 'host', 3));
  click(dom, $(dom, '#cost-role button[data-hide]'));
  click(dom, $(dom, '#reset-layout'));
  await settle();
  assert.equal(w.puts.length, 1, 'nothing more is sent while the first save is unanswered');
  w.answers.shift()({ ok: true, status: 204 });
  await settle();
  assert.deepEqual(w.puts.slice(1), [{ rev: 1 }], 'then one save with the layout as it is now: the reset');
  click(dom, sizeBtn(dom, 'host', 2));
  await settle();
  assert.equal(w.puts.length, 2, 'still one at a time');
  w.answers.shift()(Promise.reject(new Error('host down')));
  await settle();
  assert.equal(w.puts[2].sizes.host, 2, 'a save that failed does not stop the next one');
});

// The layout stays as the owner left it, session to session. Three ways a change was lost.
const UNSAVED_KEY = 'commandeck-dashboard-unsaved:demo';
const kept = (w) => Object.fromEntries(Array.from({ length: w.localStorage.length }, (_, i) => w.localStorage.key(i)).map((k) => [k, w.localStorage.getItem(k)]));
// A page left open kept running the old app.js after an update, which saved nothing to the host.
test('open_page_reloads_onto_new_code: a page left open reloads once the host serves new view files, and never while a save is unanswered', async () => {
  const dom = boot({ layout: {} }); const w = dom.window;
  const next = (d, alive) => { mock.timers.tick(15000); beat(d, { at: iso(Date.now()), ...alive }); };
  beat(dom, { at: iso(T0), view: '111' });
  next(dom, { view: '111' });
  assert.equal(w.reloads, 0, 'the same view files: no reload');
  w.slowHost = true;
  click(dom, sizeBtn(dom, 'host', 3));
  next(dom, { view: '222' });
  assert.equal(w.reloads, 0, 'a reload while a save is unanswered waits for the answer');
  w.answers.shift()({ ok: true, status: 204 });
  await settle();
  next(dom, { view: '222' });
  assert.equal(w.reloads, 1, 'new view files on the host: the page reloads itself');
  const old = boot();
  beat(old, { at: iso(Date.now()), view: '111' });
  next(old, {});
  next(old, { view: 7 });
  assert.equal(old.window.reloads, 0, 'a heartbeat with no stamp is not a change');
});
// A host that held no layout made the page ignore what this browser had saved.
test('browser_layout_goes_up_to_a_host_that_holds_none: this browser\'s saved layout is used and sent up', async () => {
  const store = { [SIZES_KEY]: '{"host":3}' };
  for (const layout of [{}, null, undefined]) {
    const dom = boot({ store, layout });
    deliver(dom, snap()); // a project the file holds no slot for is saved once the snapshot lists it
    await settle();
    assert.equal($(dom, '#host').dataset.size, '3', `host layout ${JSON.stringify(layout)}: this browser's width is used`);
    assert.deepEqual(dom.window.puts, [{ rev: 0, sizes: { host: 3 } }], 'and the whole of it is sent up once');
    assert.equal(dom.window.localStorage.getItem(UNSAVED_KEY), null, 'the host confirmed it');
  }
  const reset = boot({ store, layout: { rev: 4 } });
  await settle();
  assert.equal($(reset, '#host').dataset.size, '1', 'a numbered empty layout is a Reset layout from another PC: it wins');
  assert.deepEqual(reset.window.puts, []);
  const held = boot({ store, layout: { hidden: ['cost-role'] } });
  await settle();
  assert.equal($(held, '#host').dataset.size, '1', 'a layout the host already holds is not overwritten by another browser\'s copy');
  assert.deepEqual(held.window.puts, []);
});
// A browser fires `toggle` for every fold the markup opens, at load. Saved as a change, that made each page load
// send a layout: a PC with nothing saved would give an empty host its first layout, and the owner's own would then lose.
test('page_load_saves_nothing: a fold the page itself opens at load is not a change to send', async () => {
  const dom = boot({ layout: {} });
  for (const d of $$(dom, 'details[data-fold]')) d.dispatchEvent(new dom.window.Event('toggle'));
  mock.timers.tick(15000);
  await settle();
  assert.deepEqual(dom.window.puts, [], 'loading the page sends nothing');
  assert.equal(dom.window.localStorage.getItem(UNSAVED_KEY), null);
  $(dom, '#limit-body').open = false;
  $(dom, '#limit-body').dispatchEvent(new dom.window.Event('toggle'));
  await settle();
  assert.deepEqual(dom.window.puts, [{ rev: 0, collapsed: ['limit-body'] }], 'a fold the owner closes is');
});
// A reload while a save was unanswered loaded the host's older layout, and the change was gone.
test('reload_mid_save_keeps_the_change: a change the host has not confirmed survives a reload and is sent again', async () => {
  const hostLayout = { rev: 5, sizes: { host: 2 } };
  const dom = boot({ store: { [HIDDEN_KEY]: '["guard-blocks"]' }, layout: hostLayout }); const w = dom.window;
  w.slowHost = true;
  click(dom, sizeBtn(dom, 'host', 3));
  click(dom, $(dom, '#cost-role button[data-hide]'));
  await settle();
  assert.equal(w.puts.length, 1, 'the hide waits behind the unanswered width save');
  assert.equal(w.puts[0].rev, 5, 'a save names the host layout it was made over');
  const again = boot({ store: kept(w), layout: hostLayout });
  assert.equal($(again, '#host').dataset.size, '3', 'the width whose save was unanswered');
  assert.equal($(again, '#cost-role').hidden, true, 'the hide that was never sent');
  assert.equal($(again, '#guard-blocks').hidden, false, 'and nothing older than the host\'s layout comes back with them');
  await settle();
  assert.equal(again.window.puts.length, 1);
  assert.deepEqual([again.window.puts[0].rev, again.window.puts[0].sizes.host, again.window.puts[0].hidden], [5, 3, ['cost-role']], 'the unconfirmed layout is sent again, whole');
  assert.equal(again.window.localStorage.getItem(UNSAVED_KEY), null, 'once the host answers, its copy is the one to load');
});
// The mark of an unconfirmed change outlived the change. A browser closed before its save was answered
// kept the mark; days later its next load put its old copy over everything saved from other PCs since.
test('old_unconfirmed_mark_never_undoes_a_newer_host_layout: a reload shows what the host holds once the host has moved on', async () => {
  const dom = boot({ layout: { rev: 5, sizes: { host: 2 } } }); const w = dom.window;
  w.slowHost = true;
  click(dom, sizeBtn(dom, 'host', 3));
  await settle();
  const left = kept(w);
  const later = boot({ store: left, layout: { rev: 8, sizes: { host: 4 }, hidden: ['todos'] } });
  await settle();
  assert.equal($(later, '#host').dataset.size, '4', 'the width saved from another PC since');
  assert.equal($(later, '#todos').hidden, true, 'and the panel hidden there');
  assert.deepEqual(later.window.puts, [], 'this browser\'s old copy is not sent over it');
  assert.equal(later.window.localStorage.getItem(UNSAVED_KEY), null, 'and the old mark is gone');
  // One save further can be this browser's own save that landed unanswered: its copy is still the one to keep.
  const own = boot({ store: left, layout: { rev: 6, sizes: { host: 3 } } });
  await settle();
  assert.equal($(own, '#host').dataset.size, '3');
  assert.deepEqual(own.window.puts.map((p) => [p.rev, p.sizes.host]), [[6, 3]], 'sent again over the layout the host holds');
});
// The other order: the old page's save lands after the replay, or before it. The host refuses whichever
// was not made over the layout it holds; the page then sends its layout again over that one.
test('refused_save_is_sent_again: a save the host refuses as out of date is sent again over the layout the host holds', async () => {
  const dom = boot({ layout: { rev: 5 } }); const w = dom.window;
  w.slowHost = true;
  click(dom, sizeBtn(dom, 'host', 3));
  await settle();
  w.answers.shift()({ ok: false, status: 409, json: async () => ({ rev: 6 }) });
  await settle();
  assert.equal(w.puts.length, 2, 'refused: sent again');
  assert.deepEqual([w.puts[1].rev, w.puts[1].sizes.host], [6, 3], 'over the number the host answered with');
  assert.equal(w.localStorage.getItem(UNSAVED_KEY), '6', 'not confirmed yet, and marked with the layout it now goes over');
  w.answers.shift()({ ok: true, status: 204 });
  await settle();
  assert.equal(w.localStorage.getItem(UNSAVED_KEY), null);
  click(dom, sizeBtn(dom, 'host', 2));
  await settle();
  assert.equal(w.puts[2].rev, 7, 'a confirmed save moves this page to the host\'s next number');
  w.answers.shift()({ ok: false, status: 409, json: async () => ({ rev: 'x' }) });
  await settle();
  assert.equal(w.puts.length, 3, 'a refusal with no usable number is not retried in a loop');
  assert.equal(w.localStorage.getItem(UNSAVED_KEY), '7', 'and stays unconfirmed for the next load');
});

// By the layout rule the page uses (jsdom lays nothing out).
test('controls_stay_inside_a_narrow_panel: the control row wraps and is never wider than its panel', () => {
  const css = fs.readFileSync(path.join(VIEW, 'app.css'), 'utf8');
  assert.match(css, /\n\.card-head \.tools \{[^}]*flex-wrap: wrap;[^}]*max-width: 100%;/, 'Earlier, Later, the widths, Height and Hide wrap inside the panel');
  assert.match(css, /\n\.card-head h2 \{ flex: 1 1 auto;/, 'the title gives way before a control leaves the border');
});
test('ultrawide_uses_the_whole_window: no fixed page width, and more columns as the window grows', () => {
  const css = fs.readFileSync(path.join(VIEW, 'app.css'), 'utf8');
  assert.doesNotMatch(css, /max-width: 1500px/, 'the page is not capped at 1500 px');
  assert.match(css, /@media \(min-width: 2200px\) \{[^@]*\.grid \{ grid-template-columns: repeat\(6,/);
  assert.match(css, /@media \(min-width: 3200px\) \{[^@]*\.grid \{ grid-template-columns: repeat\(8,/);
});

test('Reset layout restores the default order, widths and heights, unhides every panel and forgets what was saved', () => {
  const dom = boot({ saved: JSON.stringify(['agents', 'todos']), store: { [SIZES_KEY]: '{"host":3}', [HEIGHTS_KEY]: '{"chief-of-staff":"half"}', [HIDDEN_KEY]: '["cost-role"]' } });
  assert.equal(order(dom)[0], 'agents');
  assert.equal($(dom, '#host').dataset.size, '3');
  assert.equal($(dom, '#chief-of-staff').dataset.height, 'half');
  assert.equal($(dom, '#cost-role').hidden, true);
  const reset = $(dom, '#reset-layout');
  assert.ok(reset, 'the header has a Reset layout control');
  assert.equal(reset.textContent, 'Reset layout');
  click(dom, reset);
  assert.deepEqual(order(dom), DEFAULT_ORDER);
  assert.equal($(dom, '#host').dataset.size, '1');
  assert.equal(sizeBtn(dom, 'host', 1).classList.contains('on'), true, 'the width buttons follow the reset');
  assert.equal($(dom, '#chief-of-staff').hasAttribute('data-height'), false);
  assert.equal($(dom, '#cost-role').hidden, false);
  for (const k of [ORDER_KEY, SIZES_KEY, HEIGHTS_KEY, HIDDEN_KEY]) assert.equal(dom.window.localStorage.getItem(k), null, `${k} is forgotten`);
});

test('dragging a panel by its title onto another panel moves it there, reflows and saves; every panel is a target', () => {
  const dom = boot();
  const fire = (el, type) => el.dispatchEvent(new dom.window.Event(type, { bubbles: true, cancelable: true }));
  for (const id of DEFAULT_ORDER) assert.equal($(dom, `#${id} .card-head h2`).getAttribute('draggable'), 'true', `${id}: the title is the drag handle`);
  const handle = $(dom, '#agents .card-head h2');
  fire(handle, 'dragstart');
  assert.equal(fire($(dom, '#agents .age'), 'dragover'), true, 'a panel is no target for itself');
  assert.equal(fire($(dom, '#units .card-head'), 'dragover'), false, 'Units accepts a drop like any other panel');
  assert.equal(fire($(dom, '#host .age'), 'dragover'), false);
  fire($(dom, '#host .age'), 'drop');
  fire(handle, 'dragend');
  const at = DEFAULT_ORDER.indexOf('host');
  assert.deepEqual(order(dom).slice(at - 1, at + 2), ['todos', 'agents', 'host'], 'dragged up, it lands before the target');
  assert.deepEqual(saved(dom), order(dom));
  fire($(dom, '#todos h2'), 'dragstart');
  fire($(dom, '#host'), 'drop');
  assert.deepEqual(order(dom).slice(at - 1, at + 2), ['agents', 'host', 'todos'], 'dragged down, it lands after the target');
  fire($(dom, '#todos h2'), 'dragend');
  fire($(dom, '#units'), 'drop');
  assert.deepEqual(saved(dom), order(dom), 'a drop with no drag in progress changes nothing');
  // jsdom has no layout: the reflow is the grid's, read from the stylesheet.
  assert.match(fs.readFileSync(path.join(VIEW, 'app.css'), 'utf8'), /\.grid\s*\{[^}]*grid-auto-flow:\s*dense/, 'the grid repacks around a moved or resized panel');
  const summary = $(dom, '#cost-role-all summary');
  const was = $(dom, '#cost-role-all').open;
  click(dom, summary);
  assert.equal($(dom, '#cost-role-all').open, !was, 'a click inside a card still reaches its controls');
});

// The 7-day limit panel is how the owner paces his week: each tile must say what the
// collector measured, in the design's units, and a figure with no source must
// read "no data" -- a 0% or $0.00 would tell him he has the week to spare.
const HOUR = 3600000;
const limitSnap = (over = {}) => ({
  usedPct: 44, goalPct: 56.2, underPts: 12.2, paceSec: 73786, timeLeftSec: 264600,
  windowStart: iso(T0 - 94.5 * HOUR), resetsAt: iso(T0 + 73.5 * HOUR),
  fiveHour: { start: iso(T0 - 3 * HOUR), end: iso(T0 + 2 * HOUR), usedPct: 15 },
  history: [{ at: iso(T0 - 90 * HOUR), pct: 2 }, { at: iso(T0 - 40 * HOUR), pct: 30 }, { at: iso(T0 - 60000), pct: 44 }],
  requests: 7876, cost: null, ...over,
});
const text = (el, sel) => el.querySelector(sel).textContent;
const tiles = (dom) => Object.fromEntries($$(dom, '#limit-tiles .tile').map((t) => [text(t, '.tile-label'), t]));

test('the limit tiles show the measured week in the design units, green under pace and red over', () => {
  const dom = boot();
  deliver(dom, snap({ limit: limitSnap() }));
  const t = tiles(dom);
  assert.deepEqual(Object.keys(t), ['Used this week', 'Goal now', 'Under pace by', 'Time left',
    'Cost this week', 'Cost today', 'Projected cost at 100%', 'Value per point', 'Requests', 'Cache write share, 24 h']);
  assert.equal(text(t['Cache write share, 24 h'], '.tile-value'), 'no data', 'a share the collector did not measure is never 0%');
  assert.equal(text(t['Used this week'], '.tile-value'), '44%');
  assert.equal(text(t['Goal now'], '.tile-value'), '56.2%');
  assert.equal(text(t['Under pace by'], '.tile-value'), '12 pts · 20h 30m', '12.2 points of a 168 h week is 20 h 30 m');
  assert.ok(t['Under pace by'].classList.contains('ok'), 'under pace is good news');
  assert.equal(text(t['Time left'], '.tile-value'), '3d 01h');
  assert.equal(text(t.Requests, '.tile-value'), '7,876this host');
  assert.match($(dom, '#limit-week').textContent, /^Sep 27 – Oct 4 · In progress$/);
  for (const k of ['Cost this week', 'Cost today', 'Projected cost at 100%', 'Value per point']) {
    assert.equal(text(t[k], '.tile-value'), 'no data', `${k} with no cost figure`);
  }
  assert.equal($(dom, '#limit-note').textContent, '', 'no dollars, no list-price note');
  mock.timers.tick(15000);
  deliver(dom, snap({ limit: limitSnap({ cost: { week: 506.09, today: 12.5, projected: 1150.2, perHour: 6.85, perPoint: 11.5, unpricedRequests: 12 } }) }));
  const priced = tiles(dom);
  assert.equal(text(priced['Cost this week'], '.tile-value'), '$506.09');
  assert.equal(text(priced['Cost today'], '.tile-value'), '$12.50');
  assert.equal(text(priced['Projected cost at 100%'], '.tile-value'), '$1.2k$6.85/hr');
  assert.equal(text(priced['Value per point'], '.tile-value'), '$11.50');
  assert.match($(dom, '#limit-note').textContent, /list-price equivalents.*12 requests on unpriced models are left out/,
    'the owner must see the dollars are list price, and what they leave out');
  mock.timers.tick(15000);
  deliver(dom, snap({ limit: limitSnap({ cost: { week: 506.09, today: null, projected: 1150.2, perHour: 6.85, perPoint: 11.5, unpricedRequests: 0 } }) }));
  assert.equal(text(tiles(dom)['Cost today'], '.tile-value'), 'no data', 'a day with no priced total reads no data, never $0.00');
  mock.timers.tick(15000);
  deliver(dom, snap({ limit: limitSnap({ underPts: -5, paceSec: -30240 }) }));
  // The write share is the cost the owner asked to see: over 5% is the collector's alert line.
  mock.timers.tick(15000);
  deliver(dom, snap({ limit: limitSnap({ cacheWritePct24h: 3.26 }) }));
  assert.equal(text(tiles(dom)['Cache write share, 24 h'], '.tile-value'), '3.3%of input tokens');
  assert.ok(!tiles(dom)['Cache write share, 24 h'].classList.contains('crit'));
  mock.timers.tick(15000);
  deliver(dom, snap({ limit: limitSnap({ cacheWritePct24h: 7.5, underPts: -5, paceSec: -30240 }) }));
  assert.ok(tiles(dom)['Cache write share, 24 h'].classList.contains('crit'), 'a share over 5% is red');
  const over = tiles(dom)['Over pace by'];
  assert.ok(over, 'a negative gap relabels the tile');
  assert.equal(text(over, '.tile-value'), '5 pts · 8h 24m');
  assert.ok(over.classList.contains('crit'), 'over pace is bad news');
});

// Codex is a second account with its own week: its tiles sit apart from Claude's,
// carry the time of the reading, and a Codex figure is never folded into Claude's.
test("the Codex 7-day tiles render apart from Claude's and read no data without a reading", () => {
  const dom = boot();
  const codex = { usedPct: 5, goalPct: 57.1, underPts: 52.1, paceSec: 314000, timeLeftSec: 259200,
    windowStart: iso(T0 - 4 * 24 * HOUR), resetsAt: iso(T0 + 3 * 24 * HOUR), readAt: iso(T0 - 90000) };
  deliver(dom, snap({ limit: limitSnap({ codex }) }));
  const claude = tiles(dom);
  assert.equal(text(claude['Used this week'], '.tile-value'), '44%', "Claude's tile is Claude's alone, never summed with Codex");
  const cx = Object.fromEntries($$(dom, '#limit-codex-tiles .tile').map((t) => [text(t, '.tile-label'), t]));
  assert.deepEqual(Object.keys(cx), ['Used this week', 'Goal now', 'Under pace by', 'Time left']);
  assert.equal(text(cx['Used this week'], '.tile-value'), '5%');
  assert.equal(text(cx['Goal now'], '.tile-value'), '57.1%');
  assert.match($(dom, '#limit-codex-note').textContent, /% used.*as of Oct 1, 2026, \d+:\d\d (AM|PM)/, 'the reading shows its own time');
  mock.timers.tick(15000);
  deliver(dom, snap({ limit: limitSnap({ codex: { usedPct: null, goalPct: null, underPts: null, paceSec: null, timeLeftSec: null,
    windowStart: null, resetsAt: null, readAt: null } }) }));
  assert.ok($$(dom, '#limit-codex-tiles .tile').every((t) => text(t, '.tile-value') === 'no data'), 'no Codex reading is no data, never 0%');
  assert.equal($(dom, '#limit-codex-note').textContent, 'Codex: no data');
  mock.timers.tick(15000);
  deliver(dom, snap({ limit: limitSnap() }));
  assert.ok($$(dom, '#limit-codex-tiles .tile').every((t) => text(t, '.tile-value') === 'no data'), 'a snapshot with no codex block is no data');
});

test('the limit chart steps through the recorded readings toward a linear goal, with the 5-hour window shaded', () => {
  const dom = boot();
  deliver(dom, snap({ limit: limitSnap() }));
  const svg = $(dom, '#limit-chart svg');
  assert.ok(svg, 'a chart for a measured week');
  const d = svg.querySelector('.actual-line').getAttribute('d');
  assert.equal((d.match(/H/g) || []).length, 2, 'each later reading is one step: across, then up');
  assert.ok(svg.querySelector('.goal-line') && svg.querySelector('.five-hour'));
  assert.deepEqual([...svg.querySelectorAll('.end-label')].map((e) => e.textContent).sort(), ['44% used', '56% goal']);
  assert.equal(svg.querySelectorAll('.axis-x').length, 8, 'one label per day boundary, start to reset');
  mock.timers.tick(15000);
  deliver(dom, snap({ limit: limitSnap({ history: [] }) }));
  assert.equal($(dom, '#limit-chart svg .actual-line'), null, 'no recorded reading draws no line, never a flat 0');
});

// A machine that pays by API has no percent to pace by. the owner sets a weekly
// dollar limit and the same panel paces dollars against it; a percent left on
// screen there would be a reading nobody measured.
const apiSnap = (over = {}) => ({
  ...limitSnap({ usedPct: null, goalPct: null, underPts: null, paceSec: null, history: [], fiveHour: null }), billing: 'api',
  api: { limitUsd: 1000, spentUsd: 412.4, goalUsd: 562.5, underUsd: 150.1, paceSec: 73786, timeLeftSec: 264600,
    windowStart: iso(T0 - 94.5 * HOUR), resetsAt: iso(T0 + 73.5 * HOUR), requests: 7876, unpricedRequests: 0,
    claudeUsd: 300.4, codexUsd: 112, estimatedUsd: 0, unpricedModels: [], complete: true,
    history: [{ at: iso(T0 - 90 * HOUR), usd: 20 }, { at: iso(T0 - 40 * HOUR), usd: 300 }, { at: iso(T0 - 60000), usd: 412.4 }], ...over },
});
// With the panel's own sources fresh, only its figures can mark it as needing a look.
const apiDeliver = (dom, limit) => {
  const s = snap({ limit });
  for (const id of ['claude-usage', 'claude-logs', 'codex-usage']) s.sources[id] = fresh(s.updatedAt);
  deliver(dom, s);
};
const strip = (dom) =>Object.fromEntries($$(dom, '#summary .measure').map((m) => [text(m, '.measure-label'), m]));

test('API billing with a weekly limit: bar, tiles, graph and summary tiles are dollars against the limit', () => {
  const dom = boot();
  apiDeliver(dom, apiSnap());
  const t = tiles(dom);
  assert.deepEqual(Object.keys(t), ['Spent this week', 'Goal now', 'Under pace by', 'Time left', 'Weekly limit', 'Requests']);
  assert.equal(text(t['Spent this week'], '.tile-value'), '$412.40');
  assert.equal(text(t['Goal now'], '.tile-value'), '$562.50');
  assert.equal(text(t['Under pace by'], '.tile-value'), '$150 · 20h 30m');
  assert.ok(t['Under pace by'].classList.contains('ok'));
  assert.equal(text(t['Weekly limit'], '.tile-value'), '$1,000');
  assert.match($(dom, '#limit-bars').textContent, /\$412 of \$1,000.*\$150 under pace/);
  assert.doesNotMatch($(dom, '#limit').textContent, /\d%/, 'no percent anywhere in the API panel');
  const svg = $(dom, '#limit-chart svg');
  assert.ok(svg.querySelector('.goal-line'), 'the even-pace line is drawn to the limit');
  assert.deepEqual([...svg.querySelectorAll('.end-label')].map((e) => e.textContent).sort(), ['$412 spent', '$563 goal']);
  assert.deepEqual([...svg.querySelectorAll('.axis-y')].map((e) => e.textContent), ['$0', '$250', '$500', '$750', '$1,000'], 'the limit is the top of the graph');
  assert.equal($(dom, '#limit-summary').textContent, '$412 spent · goal $563 · under pace $150');
  const s = strip(dom);
  assert.equal(Object.keys(s).length, 9, 'still nine summary tiles');
  assert.ok(!('Claude 7-day' in s) && !('Codex 7-day' in s), 'the two percent tiles give way');
  assert.ok($(dom, '#limit').classList.contains('api'), 'the stylesheet swaps the legend and drops the Codex percent heading');
  assert.equal(text(s['API spend, week'], '.measure-value'), '$412');
  assert.equal(text(s['API spend, week'], '.measure-detail'), 'of $1,000');
  assert.equal(text(s['Week pace'], '.measure-value'), '$150 under');
  assert.equal($(dom, '#limit').hasAttribute('data-look'), false, 'under pace needs no look');
  mock.timers.tick(15000);
  apiDeliver(dom, apiSnap({ underUsd: -50, paceSec: -30240, goalUsd: 362.4 }));
  assert.ok(tiles(dom)['Over pace by'].classList.contains('crit'), 'spend ahead of the even pace is red');
  assert.equal(text(tiles(dom)['Over pace by'], '.tile-value'), '$50 · 8h 24m');
  assert.ok(strip(dom)['Week pace'].classList.contains('crit'));
  assert.equal($(dom, '#limit').hasAttribute('data-look'), true, 'over pace is something to look at');
});

test('API billing with no weekly limit: the week\'s spend, no guide line, no pace, and a plain line to set one', () => {
  const dom = boot();
  apiDeliver(dom, apiSnap({ limitUsd: null, goalUsd: null, underUsd: null, paceSec: null }));
  const t = tiles(dom);
  assert.equal(text(t['Spent this week'], '.tile-value'), '$412.40');
  assert.equal(text(t['Weekly limit'], '.tile-value'), 'not set');
  assert.equal(text(t['Goal now'], '.tile-value'), 'no data');
  assert.equal(text(t['Under pace by'], '.tile-value'), 'no data', 'no limit, no pace');
  assert.match($(dom, '#limit-note').textContent, /^Set a weekly limit/);
  assert.match($(dom, '#limit-bars').textContent, /\$412 spent this week/);
  assert.equal($(dom, '#limit-bars .badge'), null, 'no pace badge');
  const svg = $(dom, '#limit-chart svg');
  assert.ok(svg.querySelector('.actual-line'), 'the spend line is still drawn');
  assert.equal(svg.querySelector('.goal-line'), null, 'no guide line without a limit');
  assert.deepEqual([...svg.querySelectorAll('.end-label')].map((e) => e.textContent), ['$412 spent']);
  assert.equal(text(strip(dom)['API spend, week'], '.measure-detail'), 'no weekly limit set');
  assert.equal(text(strip(dom)['Week pace'], '.measure-value'), '–');
  assert.equal($(dom, '#limit').hasAttribute('data-look'), false);
  mock.timers.tick(15000);
  apiDeliver(dom, apiSnap({ spentUsd: null, history: null, requests: null }));
  assert.equal(text(tiles(dom)['Spent this week'], '.tile-value'), 'no data', 'spend with no source is no data, never $0');
});

// Rulings 10 and 11: the one weekly limit covers Claude and Codex spend together. An estimated price is
// shown as an estimate and a model with no price is named, so a gap in the total is never read as $0.
test('API billing shows Claude and Codex spend in the total, estimated dollars as estimated, and unpriced models by name', () => {
  const dom = boot();
  apiDeliver(dom, apiSnap());
  const f = facts($(dom, '#limit-facts'));
  assert.equal(f['Claude spend'], '$300');
  assert.equal(f['Codex spend'], '$112');
  assert.doesNotMatch($(dom, '#limit').textContent, /not measured|estimated|left out/i, 'nothing is missing, so nothing says so');
  mock.timers.tick(15000);
  apiDeliver(dom, apiSnap({ estimatedUsd: 25.5, unpricedRequests: 3, unpricedModels: ['gpt-9-nova', '<synthetic>'] }));
  const note = $(dom, '#limit-note').textContent;
  assert.match(note, /\$25\.50 of the total is estimated from the nearest published price/);
  assert.match(note, /3 requests on unpriced models are left out \(gpt-9-nova, <synthetic>\)/);
  mock.timers.tick(15000);
  apiDeliver(dom, apiSnap({ tierUsd: 7.25 }));
  assert.match($(dom, '#limit-note').textContent, /\$7\.25 of the total is priced by Codex tier, not by exact version/);
  mock.timers.tick(15000);
  apiDeliver(dom, apiSnap({ codexUsd: null }));
  assert.equal(facts($(dom, '#limit-facts'))['Codex spend'], 'Not measured', 'no Codex sessions is not measured, never $0');
  assert.match($(dom, '#limit-note').textContent, /Codex spend is not measured/);
});

test('subscription billing is the panel it was: the API keys change nothing unless the setting says api', () => {
  const plain = boot();
  deliver(plain, snap({ limit: limitSnap() }));
  const marked = boot();
  deliver(marked, snap({ limit: { ...limitSnap(), billing: 'subscription', api: null } }));
  assert.equal($(marked, '#limit').innerHTML, $(plain, '#limit').innerHTML);
  assert.equal($(marked, '#summary').innerHTML, $(plain, '#summary').innerHTML);
  assert.ok('Claude 7-day' in strip(marked) && 'Codex 7-day' in strip(marked));
  assert.equal($(marked, '#limit').classList.contains('api'), false);
  // The setting, not the presence of API figures, picks the version.
  const stray = boot();
  deliver(stray, snap({ limit: { ...limitSnap(), billing: 'subscription', api: apiSnap().api } }));
  assert.equal($(stray, '#limit').innerHTML, $(plain, '#limit').innerHTML);
});

// The 7-day card moves like the others and its tiles fold to one
// line that still answers "will the week last"; the graph is the mockup's size.
test('the 7-day card moves like any other, and its tiles fold to a one-line summary that is remembered', () => {
  const dom = boot();
  const at = DEFAULT_ORDER.indexOf('limit');
  click(dom, moveBtn(dom, 'limit', 'earlier'));
  assert.deepEqual(order(dom).slice(at - 1, at + 1), ['limit', 'units'], 'it moves like any other card');
  deliver(dom, snap({ limit: limitSnap() }));
  const body = $(dom, '#limit-body');
  assert.equal(body.localName, 'details');
  assert.equal(body.open, true, 'open by default');
  const sum = body.querySelector(':scope > summary');
  assert.equal(sum.textContent, '44% used · goal 56.2% · under pace 12 pts · at this pace the limit lasts to the reset',
    '44% in 94.5 h runs out after the reset');
  assert.equal($(dom, '#limit-chart svg').getAttribute('viewBox'), '0 0 900 220', 'the graph is the size the owner approved');
  click(dom, $(dom, '#permanent > summary'));
  click(dom, sum);
  mock.timers.tick(1);
  assert.deepEqual(JSON.parse(dom.window.localStorage.getItem(COLLAPSED_KEY)).sort(), ['limit-body', 'permanent'],
    'folding a second section keeps the first fold');
  const again = boot({ collapsed: dom.window.localStorage.getItem(COLLAPSED_KEY) });
  assert.equal($(again, '#limit-body').open, false, 'a reload keeps the 7-day card folded');
  assert.equal($(again, '#permanent').open, false);
  mock.timers.tick(14999);
  deliver(dom, snap({ limit: limitSnap({ usedPct: 90, underPts: -33.8, paceSec: -204000 }) }));
  assert.equal(body.open, false, 'a refresh keeps it folded');
  // 10 points left at 90 per 94.5 h is 10.5 h from now.
  const out = new Date(T0 + 15000 + 10.5 * HOUR);
  assert.equal(out.toLocaleString('en-US', { timeZone: 'America/New_York', weekday: 'short', hour: 'numeric', minute: '2-digit' }).replace(/\u202f/g, ' '), 'Thu 6:30 PM', 'the fixture lands on a known Eastern time');
  assert.equal(sum.textContent, '90% used · goal 56.2% · over pace 34 pts · at this pace the limit runs out ~Thu 6:30 PM');
});

test('a chart with under two readings says when history starts instead of drawing a line', () => {
  const dom = boot();
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const day = (ms) => { const d = new Date(ms); return `${MONTHS[d.getMonth()]} ${d.getDate()}`; };
  deliver(dom, snap({ limit: limitSnap({ history: [{ at: iso(T0 - 30 * HOUR), pct: 40 }] }) }));
  const svg = $(dom, '#limit-chart svg');
  assert.equal(svg.querySelector('.actual-line'), null, 'one reading draws no line');
  assert.equal(svg.querySelector('.end-label.used'), null, 'and no end label');
  assert.equal(svg.querySelector('.history-note').textContent, `history starts ${day(T0 - 30 * HOUR)}`, 'the day of the first reading');
  mock.timers.tick(15000);
  deliver(dom, snap({ limit: limitSnap({ history: [] }) }));
  assert.equal($(dom, '#limit-chart svg .history-note').textContent, `history starts ${day(T0 + 15000)}`, 'no reading: the day of the snapshot');
  mock.timers.tick(15000);
  deliver(dom, snap({ limit: limitSnap() }));
  assert.equal($(dom, '#limit-chart svg .history-note'), null, 'two readings or more draw the line');
});

test('a missing limit source reads "no data" in every tile and the chart, never a number', () => {
  const dom = boot();
  deliver(dom, snap({ limit: limitSnap({ usedPct: null, goalPct: null, underPts: null, paceSec: null, timeLeftSec: null,
    windowStart: null, resetsAt: null, fiveHour: null, history: [], requests: null }) }));
  const values = $$(dom, '#limit-tiles .tile-value').map((e) => e.textContent);
  assert.equal(values.length, 10);
  assert.deepEqual([...new Set(values)], ['no data']);
  assert.equal($(dom, '#limit-week').textContent, 'no data');
  assert.equal($(dom, '#limit-chart').textContent, 'no data');
  mock.timers.tick(15000);
  deliver(dom, snap());
  assert.deepEqual([...new Set($$(dom, '#limit-tiles .tile-value').map((e) => e.textContent))], ['no data'],
    'a collector that has not shipped the limit key yet is not measured either');
});

// The owner reads the page instead of asking main what is waiting, stuck or
// blocked. Two hours is the line: a decision or a unit stage older than that
// turns red, and a figure the collector could not read says so.
test('a decision waiting past 2 h shows its age in red; one under 2 h shows its age only', () => {
  const dom = boot();
  const s = snap();
  s.needsOwner.decisions = [
    { id: 'd-old', askedAt: iso(T0 - 3 * HOUR), question: 'old?', proposedDefault: 'x', source: 's', answeredAt: null, answer: null },
    { id: 'd-new', askedAt: iso(T0 - HOUR), question: 'new?', proposedDefault: 'x', source: 's', answeredAt: null, answer: null },
  ];
  deliver(dom, s);
  const [old, young] = $$(dom, '#decisions li');
  assert.match(old.textContent, /3 h ago/);
  assert.ok(old.classList.contains('crit'), 'past 2 h is red');
  assert.match(young.textContent, /60 min ago/);
  assert.ok(!young.classList.contains('crit'), 'under 2 h is not');
});

test('a unit card shows its round and time in stage, red past 2 h, "at least" when first seen mid-stage', () => {
  const dom = boot();
  const s = snap();
  s.units.inFlight = [row('unit-f', 'fixing', { round: 2, stageSince: iso(T0 - 3 * HOUR), stageExact: true }),
    row('unit-r', 'review', { round: 1, stageSince: iso(T0 - 30 * 60000), stageExact: false }),
    row('unit-b', 'building', { round: null }), row('Chief-of-Staff', 'chief-of-staff')];
  deliver(dom, s);
  const line = (n) => card(dom, n).querySelector(':scope > .stage-time');
  assert.equal(line('unit-f').textContent, 'fix 2 · in stage 3 h');
  assert.ok(line('unit-f').classList.contains('crit'), 'stuck past 2 h is red');
  assert.equal(line('unit-r').textContent, 'review 1 · in stage at least 30 min');
  assert.ok(!line('unit-r').classList.contains('crit'));
  assert.equal(line('unit-b').textContent, 'Time in stage not measured', 'no recorded start is not measured, never 0 s');
  assert.equal(line('Chief-of-Staff'), null, 'the long-lived seat has no stage clock');
});

test('the host card head turns red when load or swap is past its red line', () => {
  const dom = boot();
  const host = (load, usedMb) => ({ cpus: 8, load: [load, 1, 1], swap: { totalMb: 2048, usedMb }, claudeProcs: 1, codexProcs: 1 });
  deliver(dom, snap({ host: host(16, 100) }));
  assert.equal($(dom, '#host').dataset.alert, 'crit', 'two jobs per core is red');
  mock.timers.tick(15000);
  deliver(dom, snap({ host: host(2, 1536) }));
  assert.equal($(dom, '#host').dataset.alert, 'crit', '75% swap is red');
  mock.timers.tick(15000);
  deliver(dom, snap({ host: host(15, 1535) }));
  assert.equal($(dom, '#host').hasAttribute('data-alert'), false, 'under both lines is no alert');
});
// A capped read is a floor, never the total.
test("the Chief of Staff's inbox and the main checkout's facts render as text; null reads not measured", () => {
  const dom = boot();
  deliver(dom, snap());
  const facts = (id) => Object.fromEntries($$(dom, `#${id} dt`).map((dt) => [dt.textContent, dt.nextElementSibling.textContent]));
  assert.deepEqual(facts('cos-facts'), { 'Not marked read': '2 not marked read oldest 2 h', 'Oldest of them': '2 h old' });
  assert.deepEqual(facts('chain-facts'), { Unpushed: '3 commits not pushed' });
  mock.timers.tick(15000);
  const n = snap({ chiefOfStaff: null });
  n.mainChain.unpushed = null;
  deliver(dom, n);
  assert.deepEqual(facts('cos-facts'), { Inbox: 'Not measured' });
  assert.deepEqual(facts('chain-facts'), { Unpushed: 'Not measured' });
  mock.timers.tick(15000);
  deliver(dom, snap({ chiefOfStaff: { unread: 1000, oldestUnreadAgeSec: 7200, incomplete: true } }));
  assert.deepEqual(facts('cos-facts'), { 'Not marked read': 'at least 1000 not marked read oldest 2 h', 'Oldest of them': 'at least 2 h old' },
    'a capped inbox read is a floor, never the total');
});

// Chief-of-Staff is the long-lived relay worktree, never a unit with no stage.
test('Chief-of-Staff sits with the long-lived worktrees and its agent, and never in Stage not known yet', () => {
  const dom = boot();
  const s = snap();
  s.units.inFlight = [row('Chief-of-Staff', 'chief-of-staff', { agents: 'claude:working' })];
  deliver(dom, s);
  const names = (list) => $$(dom, `[data-list="${list}"] li.unit`).map((li) => li.querySelector('.unit-name').textContent);
  assert.deepEqual(names('permanent'), ['Chief-of-Staff']);
  assert.deepEqual(names('unclassified'), []);
  assert.equal($(dom, '#unclassified').hidden, true, 'the unknown-stage group stays hidden');
  assert.match(card(dom, 'Chief-of-Staff').textContent, /Agents claude:working/);
  assert.equal(inFlightValue(dom), '0', 'a seat is not a unit in flight');
});

// Every absolute time is US 12-hour in the viewer's zone (Eastern here), never UTC, ISO or 24-hour.
test('absolute times render as US 12-hour Eastern, from UTC inputs, and none reads UTC, ISO or 24-hour', () => {
  const dom = boot();
  const at = '2026-09-30T16:52:27Z';
  const s = snap({ updatedAt: at });
  s.guardBlocks.items[0].at = '2026-09-30T16:51:18Z';
  s.agents.items[0].startedAt = '2026-09-30T21:05:00Z';
  s.needsOwner.decisions[0].askedAt = '2026-09-30T13:00:00Z';
  deliver(dom, s);
  assert.equal($(dom, '#updated').textContent, '12:52:27 PM');
  assert.equal($(dom, '#clock').textContent, '8:00:00 AM', 'the live clock is Eastern too (12:00 UTC)');
  assert.match($(dom, '#guard-blocks-list').textContent, /Sep 30, 2026, 12:51 PM/);
  assert.equal($(dom, '#alerts-list small').title, 'Sep 30, 2026, 12:52 PM', 'an alert keeps its exact start time on hover');
  assert.match($(dom, '#agents-list').textContent, /started Sep 30, 2026, 5:05 PM/);
  assert.match($(dom, '#decisions').textContent, /asked Sep 30, 2026, 9:00 AM/);
  assert.match($(dom, '#banner').textContent, /Every number below is from 12:52:27 PM/);
  const page = $(dom, 'body').textContent;
  assert.doesNotMatch(page, /\d{4}-\d{2}-\d{2}/, 'no ISO date');
  assert.doesNotMatch(page, /\bUTC\b/, 'no UTC');
  assert.doesNotMatch(page, /\b(1[3-9]|2[0-3]):\d{2}\b/, 'no 24-hour time');
  const stale = snap({ updatedAt: iso(Date.now()) });
  stale.sources.host = { sampledAt: iso(Date.now()), status: 'stale', staleSince: '2026-09-30T20:30:00Z', error: 'x' };
  mock.timers.tick(15000);
  deliver(dom, stale);
  assert.match($(dom, '#host .age').textContent, /stale since Sep 30, 2026, 4:30 PM/);
});

// The bug-hunt count depends on the closed-issue read; its failure must reach the card.

// The page disagreed with Orca. Each case below is one of the places it did.
// The plan progress panel is gone for good; none comes back for another plan.
test('no_plan_progress_panel: the page has 12 panels and none reads plan progress, even when a snapshot carries one', () => {
  const dom = boot();
  deliver(dom, snap({ planProgress: { total: 61, merged: 61, ratePerHour: 0, etaSec: null } }));
  assert.equal($$(dom, 'main.grid > .card').length, 12);
  assert.equal($(dom, '#progress'), null);
  assert.doesNotMatch($(dom, 'main.grid').textContent, /Bug-hunt|plan progress/i);
  assert.doesNotMatch(appSrc + html, /planProgress|progress-facts|plan-units|gh-closed-plan/);
});

test('the header names the oldest sample beside the write time', () => {
  const dom = boot();
  const s = snap();
  s.sources['gh-open'] = fresh(iso(Date.now() - 360000));
  s.sources.orca = { sampledAt: null, status: 'not-measured', staleSince: null, error: 'x' };
  deliver(dom, s);
  assert.match($(dom, '#status').textContent, /^Live, written .* ago; oldest sample 6 min ago$/, 'a write 0 s old must not hide a section sampled 6 min ago');
});

test('a subagent launched with no model reads as the agent default, an unmatched launch as not measured', () => {
  const dom = boot();
  const s = snap();
  const step = (modelAsked) => ({ kind: 'subagent', agentId: 'a', type: 'Explore', modelAsked, model: 'claude-haiku-5-5', tokens: null, start: iso(T0 - 9000), stop: null, reason: null });
  s.units.inFlight = [row('b-def', 'building', { builder: { steps: [step('')], signals: [], verdict: null } }),
    row('b-nm', 'building', { builder: { steps: [step(null)], signals: [], verdict: null } })];
  deliver(dom, s);
  assert.match(card(dom, 'b-def').textContent, /asked agent default · ran claude-haiku-5-5/);
  assert.match(card(dom, 'b-nm').textContent, /asked not measured/);
});

// "Builds in progress" answers "how far along is each build" without
// asking main. Every value is the collector's read of the unit's own brief,
// evidence file, round files and event log; a guessed one would send the owner after
// a build that is not where the page says.
const builderRow = (unit, stage, builder = {}, over = {}) => row(unit, stage, { driver: null, agents: 'claude:working', builder: {
  steps: [], signals: [], verdict: null, verdictRound: null, startedAt: iso(T0 - 2 * HOUR), reviewSec: 0, waiting: [],
  issues: [11, 12, 13, 14], built: [11, 13], findings: null, reviewedTree: true, ...builder }, ...over });
const build = (dom, unit) => $$(dom, '#builds-list .build').find((b) => b.dataset.unit === unit);
const facts = (el) => Object.fromEntries([...el.querySelectorAll('dt')].map((dt) => [dt.textContent, dt.nextElementSibling.textContent]));
const stepNow = (el) => [...el.querySelectorAll('.step')].map((s) => `${s.textContent}${s.classList.contains('now') ? '*' : s.classList.contains('done') ? '+' : ''}`);

test('a build block shows its step, built-of-brief bar, review line, last sign, what it waits on and its issue tags', () => {
  const dom = boot();
  const s = snap();
  s.units.inFlight = [builderRow('batch-a', 'review', {
    steps: [{ kind: 'codex', pass: 'review', round: 3, start: iso(T0 - 240000), end: null, rc: null },
      { kind: 'codex', pass: 'adversarial', round: 2, start: iso(T0 - 900000), end: iso(T0 - 600000), rc: 0 }],
    verdict: 'VERDICT: NO-GO', verdictRound: 2, findings: { P0: 0, P1: 1, P2: 4, P3: 0 }, reviewSec: 1500,
    waiting: [{ kind: 'codex', what: 'review', round: 3, since: iso(T0 - 240000) }] })];
  deliver(dom, s);
  assert.equal($(dom, '#builds-sub').textContent, '1 of 1 working');
  const b = build(dom, 'batch-a');
  assert.deepEqual(stepNow(b), ['Build+', 'Review*', 'Fix', 'Closing pass', 'Merge'], 'an open review pass is the Review step');
  assert.equal(b.querySelector('.mbar i').style.width, '50%', 'two of the four brief issues are recorded as built');
  assert.match(b.querySelector('.cap').textContent, /2 of 4 issues recorded as built\s*2 left/);
  const f = facts(b);
  assert.match(f.Started, /^Oct 1, 2026, 6:00 AM · 2h 00m so far$/);
  assert.equal(f.Review, 'pass 3 · P1 1 · P2 4 in pass 2 · 25 min in review · VERDICT: NO-GO', 'the findings name the pass they were counted in');
  assert.equal(f['Last sign'], 'written 60 s ago working');
  assert.equal(f['Waiting on'], 'Codex review pass, round 3, for 4 min');
  assert.deepEqual([...b.querySelectorAll('.iss span')].map((t) => `${t.textContent}${t.classList.contains('y') ? ' built' : ''}`),
    ['#11 built', '#12', '#13 built', '#14']);
  // The step follows the build: a closing pass, a fix round, and merge only after a closing pass that ended GO.
  const at = (stage, builder) => { const d = boot(); const n = snap(); n.units.inFlight = [builderRow('x', stage, builder)]; deliver(d, n); return stepNow(build(d, 'x')).findIndex((t) => t.endsWith('*')); };
  const done = (pass, round) => ({ kind: 'codex', pass, round, start: iso(T0 - 9000), end: iso(T0 - 1000), rc: 0 });
  assert.equal(at('building', {}), 0);
  assert.equal(at('fixing', { steps: [done('review', 2)] }), 2);
  assert.equal(at('review', { steps: [{ ...done('final', 4), end: null }] }), 3);
  assert.equal(at('waiting-main', { steps: [done('final', 4)], verdict: 'VERDICT: GO', verdictRound: 4 }), 4);
  assert.equal(at('waiting-main', { steps: [done('final', 4)], verdict: 'VERDICT: NO-GO', verdictRound: 4 }), 3, 'a closing pass that did not end GO is at Closing pass, not at Merge');
  assert.equal(at('waiting-main', { steps: [done('review', 4)], verdict: 'VERDICT: GO', verdictRound: 4 }), 3, 'a GO before the closing pass is not at Merge: it stopped for main before the closing pass');
});

test('a build value with no source reads not recorded, never a guess', () => {
  const dom = boot();
  const s = snap();
  s.units.inFlight = [builderRow('batch-nm', 'building', { steps: null, signals: null, startedAt: null, reviewSec: null, waiting: null, issues: null, built: null },
    { ageSec: null, agents: null }),
  builderRow('batch-half', 'building', { built: null }), builderRow('batch-unread', 'building', { built: false }), builderRow('batch-empty', 'building', { built: [] })];
  deliver(dom, s);
  const b = build(dom, 'batch-nm');
  assert.deepEqual(facts(b), { Started: 'not recorded', Review: 'not recorded', 'Last sign': 'not recorded', 'Waiting on': 'not recorded' });
  assert.match(b.querySelector('.cap').textContent, /issue list not recorded/);
  assert.equal(b.querySelector('.mbar i').style.width, '0%', 'an unread list draws no progress');
  assert.equal(b.querySelector('.iss'), null, 'and no issue tags');
  assert.match(b.querySelector('.mdls').textContent, /model and effort not recorded/);
  assert.equal(stepNow(b).some((t) => /[*+]$/.test(t)), true, 'the stage is still the collector\'s own read');
  const half = build(dom, 'batch-half');
  assert.match(half.querySelector('.cap').textContent, /4 issues in the brief\s*nothing built yet/, 'a running build with no evidence file yet is the normal start, not a fault');
  assert.match(half.querySelector('.legend').textContent, /nothing built yet/);
  assert.doesNotMatch(half.textContent, /\d+ of \d+|built count not recorded/, 'and it is not zero of 4 as a recorded count');
  assert.equal(half.querySelectorAll('.iss span.y').length, 0);
  // An evidence file that cannot be read (false) is neither the normal start nor a recorded zero.
  const unread = build(dom, 'batch-unread');
  assert.match(unread.querySelector('.cap').textContent, /4 issues in the brief\s*built count not recorded/);
  assert.match(unread.querySelector('.legend').textContent, /built count not recorded/);
  assert.doesNotMatch(unread.textContent, /\d+ of \d+|nothing built yet/, 'an unread file is not zero of 4, and not a build that has yet to start');
  assert.equal(unread.querySelector('.mbar i').style.width, '0%');
  const empty = build(dom, 'batch-empty');
  assert.match(empty.querySelector('.cap').textContent, /0 of 4 issues recorded as built\s*4 left/, 'an evidence file with nothing in it is a recorded zero');
  assert.match(empty.querySelector('.legend').textContent, /not yet recorded/);
  assert.equal($(dom, '#builds-sub').textContent, 'working Builders not measured', 'an unread agent state is not a count');
  mock.timers.tick(15000);
  deliver(dom, snap({ units: null }));
  assert.match($(dom, '#builds .card-note').textContent, /Builders not measured/);
  assert.equal($$(dom, '#builds-list .build').length, 0);
});

// More than one build runs at a time.
test('Builds in progress shows every running build, each with its own full block, for two and for three', () => {
  for (const n of [2, 3]) {
    const dom = boot();
    const s = snap();
    const names = ['batch-a', 'batch-b', 'batch-c'].slice(0, n);
    s.units.inFlight = [...names.map((u, i) => builderRow(u, ['building', 'review', 'fixing'][i], { issues: [100 + i], built: [] })),
      row('loop-unit', 'building', { agents: 'claude:working' })];
    deliver(dom, s);
    const blocks = $$(dom, '#builds-list > .build');
    assert.deepEqual(blocks.map((b) => b.dataset.unit), names, `${n} builds, in the collector's order; a loop unit is no build`);
    for (const [i, b] of blocks.entries()) {
      assert.equal(b.querySelectorAll('.step').length, 5, `${names[i]} has its own step strip`);
      assert.ok(b.querySelector('.mbar') && b.querySelector('.cap'), 'its own issue bar');
      assert.deepEqual(Object.keys(facts(b)), ['Started', 'Review', 'Last sign', 'Waiting on'], 'its own facts');
      assert.equal(b.querySelector('.iss span').textContent, `#${100 + i}`, 'its own issue tags');
    }
    assert.equal($(dom, '#builds-sub').textContent, `${n} of ${n} working`);
    const slotsTile = $$(dom, '#summary > *').find((m) => /Builds running/.test(m.textContent));
    assert.equal(slotsTile.querySelector('.measure-value').textContent, String(n));
  }
});

// The tags on a unit are what its seat is running, read from the
// seat's own session; the routing table by role is only what was asked for.
test('a unit shows the model and effort its seat is running, and says so when there is no record', () => {
  const dom = boot();
  const s = snap();
  s.units.inFlight = [
    builderRow('u-bld', 'building', {}, { seat: { model: 'claude-opus-5-5', effort: 'medium', advisor: 'claude-fable-5-1', at: iso(T0) },
      seats: [{ role: 'builder', model: 'claude-sonnet-5-5', effort: 'high' }] }),
    row('u-odd', 'review', { agents: 'claude:working', seat: { model: 'some-other-model', effort: null, advisor: null, at: iso(T0) } }),
    row('u-none', 'review', { agents: 'claude:working', seat: null }),
    row('u-idle', 'waiting-main', { agents: '', seat: null }),
  ];
  deliver(dom, s);
  const tags = (root) => [...root.querySelectorAll(':scope > .mdls .mdl')].map((t) => t.textContent);
  assert.deepEqual(tags(card(dom, 'u-bld')), ['Builder', 'Opus 5.5', 'effort medium', 'advisor Fable 5.1'], 'the running model, not the launch row');
  assert.deepEqual(tags(build(dom, 'u-bld')), ['Builder', 'Opus 5.5', 'effort medium', 'advisor Fable 5.1'], 'the Builds block shows the same');
  assert.deepEqual(tags(card(dom, 'u-odd')), ['some-other-model', 'effort not recorded'], 'an unknown id is shown as it is');
  assert.deepEqual(tags(card(dom, 'u-none')), ['model and effort not recorded'], 'no session record is never a routing-table guess');
  assert.deepEqual(tags(card(dom, 'u-idle')), ['no seat running']);
});

// First review pass: each of these showed a healthy reading the data did not support.
test('Merge lights only when the closing pass itself succeeded and the GO is that pass\'s own', () => {
  const at = (builder) => { const d = boot(); const n = snap(); n.units.inFlight = [builderRow('x', 'waiting-main', builder)]; deliver(d, n); return stepNow(build(d, 'x')).findIndex((t) => t.endsWith('*')); };
  const fin = (rc) => ({ kind: 'codex', pass: 'final', round: 4, start: iso(T0 - 9000), end: iso(T0 - 1000), rc });
  assert.equal(at({ steps: [fin(0)], verdict: 'VERDICT: GO', verdictRound: 4 }), 4);
  // Not ready to merge leaves the build at Closing pass (3), the pass it reached, never at Merge (4).
  assert.equal(at({ steps: [fin(1)], verdict: 'VERDICT: GO', verdictRound: 3 }), 3, 'a failed closing pass beside an earlier round\'s GO is not ready to merge');
  assert.equal(at({ steps: [fin(0)], verdict: 'VERDICT: GO', verdictRound: 3 }), 3, 'a GO from another round is not this pass\'s verdict');
  assert.equal(at({ steps: [fin(1)], verdict: 'VERDICT: GO', verdictRound: 4 }), 3, 'a closing pass that exited with an error did not succeed');
  // Main merges the tip, so a GO on a commit that is no longer the tip, or beside uncommitted work, is not ready.
  assert.equal(at({ steps: [fin(0)], verdict: 'VERDICT: GO', verdictRound: 4, reviewedTree: false }), 3, 'a tree changed since the closing pass is not ready to merge');
  assert.equal(at({ steps: [fin(0)], verdict: 'VERDICT: GO', verdictRound: 4, reviewedTree: null }), 3, 'a tree nobody could compare is not ready to merge');
});

// Batch E's pass 5 was its closing pass and ended NO-GO; the strip read "Fix" with Closing pass not reached.
test('closing_nogo_is_a_reached_step: a closing pass that ended NO-GO shows with its verdict, and a later fix is a step after it', () => {
  const strip = (stage, builder) => { const d = boot(); const n = snap(); n.units.inFlight = [builderRow('x', stage, builder)]; deliver(d, n); return stepNow(build(d, 'x')); };
  const fin = { kind: 'codex', pass: 'final', round: 5, start: iso(T0 - 9000), end: iso(T0 - 1000), rc: 0 };
  assert.deepEqual(strip('waiting-main', { steps: [fin], verdict: 'VERDICT: NO-GO', verdictRound: 5 }),
    ['Build+', 'Review+', 'Fix+', 'Closing passpass 5 ended NO-GO*', 'Merge']);
  assert.deepEqual(strip('fixing', { steps: [fin], verdict: 'VERDICT: NO-GO', verdictRound: 5 }),
    ['Build+', 'Review+', 'Fix+', 'Closing passpass 5 ended NO-GO+', 'Fix*', 'Merge']);
  const later = { kind: 'codex', pass: 'review', round: 6, start: iso(T0 - 900), end: null, rc: null };
  assert.deepEqual(strip('review', { steps: [later, fin], verdict: 'VERDICT: NO-GO', verdictRound: 5 }),
    ['Build+', 'Review+', 'Fix+', 'Closing passpass 5 ended NO-GO+', 'Fix*', 'Merge'], 'the narrowed pass on that fix is part of the later step');
  assert.deepEqual(strip('waiting-main', { steps: [{ ...later, end: iso(T0 - 100), rc: 0 }, fin], verdict: 'VERDICT: GO', verdictRound: 6 }),
    ['Build+', 'Review+', 'Fix+', 'Closing passpass 5+', 'Fixwaiting on main*', 'Merge'], 'a newer round\'s verdict is not the closing pass\'s');
  assert.deepEqual(strip('fixing', { steps: [{ ...fin, pass: 'review' }], verdict: 'VERDICT: NO-GO', verdictRound: 5 }),
    ['Build+', 'Review+', 'Fix*', 'Closing pass', 'Merge'], 'a fix before any closing pass is the first Fix step');
});
test('change_size_says_what_it_measures: the figure on a build is labelled as not committed', () => {
  const dom = boot(); const n = snap();
  n.units.inFlight = [builderRow('x', 'building', {}, { diffStat: '6 files changed, 68 insertions(+), 8 deletions(-)' }), builderRow('y', 'building', {}, { diffStat: '' })];
  deliver(dom, n);
  assert.equal(build(dom, 'x').querySelector('.uline small').textContent, 'not committed, new files not counted: 6 files changed, 68 insertions(+), 8 deletions(-)',
    'the unit card counts new files too, so the two figures differ and this one says why');
  assert.equal(build(dom, 'y').querySelector('.uline small').textContent, '');
  // Measured at a 480 px window: the labelled figure on one line pushed the page 7 px sideways.
  assert.doesNotMatch(fs.readFileSync(path.join(VIEW, 'app.css'), 'utf8').match(/\n\.uline small \{[^}]*\}/)[0], /nowrap/, 'the labelled figure wraps inside its panel');
});

// A first pass that ends GO merges with no closing pass. The strip must say so: a "Closing pass" step
// left blank reads as a build still waiting for a pass that will never run.
test('a closing pass that was skipped says so and the build moves on to Merge', () => {
  const strip = (builder) => { const d = boot(); const n = snap(); n.units.inFlight = [builderRow('x', 'waiting-main', builder)]; deliver(d, n); return stepNow(build(d, 'x')); };
  const first = (pass, rc) => ({ kind: 'codex', pass, round: 1, start: iso(T0 - 9000), end: iso(T0 - 1000), rc });
  assert.deepEqual(strip({ steps: [first('adversarial', 0)], verdict: 'VERDICT: GO', verdictRound: 1 }),
    ['Build+', 'Review+', 'Fix+', 'Closing passskipped, unchanged since pass 1+', 'Mergewaiting on main*']);
  assert.deepEqual(strip({ steps: [first('adversarial', 0)], verdict: 'VERDICT: NO-GO', verdictRound: 1 }),
    ['Build+', 'Review+', 'Fixwaiting on main*', 'Closing pass', 'Merge'], 'a first pass that did not end GO skips nothing: it stopped for main at the fix');
  assert.deepEqual(strip({ steps: [first('review', 0)], verdict: 'VERDICT: GO', verdictRound: 1 }),
    ['Build+', 'Review+', 'Fix+', 'Closing passwaiting on main*', 'Merge'], 'a narrowed pass\'s GO does not stand in for the closing pass');
  assert.deepEqual(strip({ steps: [first('adversarial', 0)], verdict: 'VERDICT: GO', verdictRound: 1, reviewedTree: false }),
    ['Build+', 'Review+', 'Fixwaiting on main*', 'Closing pass', 'Merge'], 'a tree changed since the first pass skipped nothing: it owes a closing pass');
});

// Each panel's own rule, with nothing open, drops the panel; the same panel is kept once its one thing is open.
test('needs_a_look_drops_every_panel_with_nothing_open: no panel rule keeps a panel that has nothing to act on', () => {
  const dom = boot();
  const show = (change) => {
    mock.timers.tick(15000);
    const s = snap({ alerts: [], chiefOfStaff: { unread: 0, oldestUnreadAgeSec: null } });
    for (const c of $$(dom, 'main.grid > .card')) for (const id of c.dataset.sources.split(' ')) s.sources[id] = fresh(s.updatedAt);
    s.units.inFlight = []; s.needsOwner.decisions = [];
    s.host.swap = { totalMb: 2048, usedMb: 100 }; s.mainChain.unpushed = 0;
    change(s); deliver(dom, s);
    return $$(dom, 'main.grid > .card[data-look]').map((c) => c.id);
  };
  const calm = show(() => {});
  for (const id of ['alerts', 'builds', 'needs', 'main-chain', 'units', 'limit', 'host', 'guard-blocks', 'chief-of-staff', 'todos'])
    assert.ok(!calm.includes(id), `${id} has nothing open and is dropped (kept: ${calm.join(' ')})`);
  assert.ok(show((s) => { s.mainChain.unpushed = 2; }).includes('main-chain'), 'unpushed commits keep the main chain');
  assert.ok(show((s) => { s.chiefOfStaff = { unread: 1, oldestUnreadAgeSec: 7200 }; }).includes('chief-of-staff'), 'an old message not marked read keeps the Chief of Staff\'s inbox');
  const waiting = show((s) => { s.units.inFlight = [builderRow('x', 'waiting-main', {})]; });
  assert.ok(waiting.includes('units') && waiting.includes('builds'), 'a build waiting on main keeps Units and Builds');
  assert.ok(show((s) => { s.needsOwner.decisions = [{ id: 'd1', question: 'q', askedAt: s.updatedAt }]; }).includes('needs'), 'an open decision keeps Needs the owner');
  assert.deepEqual(show(() => {}), calm, 'and each mark clears when its cause does');
});

// The filter must never hide a panel that is showing a problem: the mark follows the amber or red on the
// panel's own face, so a panel with no marking code of its own (a role with an unmeasured seat) is covered too.
test('a panel showing amber or red on its own face is in the needs-a-look view', () => {
  const dom = boot();
  const show = (unmeasuredSeats, usedMb) => {
    mock.timers.tick(15000);
    const s = snap({ alerts: [], costPerRole: [{ role: 'sol', seats: 3, unmeasuredSeats, input: 10, cachedInput: 5, output: 30 }],
      host: { cpus: 8, load: [2, 1.5, 1], swap: { totalMb: 2048, usedMb }, claudeProcs: 4, codexProcs: 4 } });
    for (const c of $$(dom, 'main.grid > .card')) for (const id of c.dataset.sources.split(' ')) s.sources[id] = fresh(s.updatedAt);
    deliver(dom, s);
    return (id) => $(dom, `#${id}`).hasAttribute('data-look');
  };
  let look = show(0, 100);
  assert.equal(look('cost-role'), false, 'every seat measured is nothing to look at');
  assert.equal(look('host'), false);
  look = show(1, 100);
  assert.ok($(dom, '#cost-role .warn'), 'the unmeasured seat is drawn amber');
  assert.equal(look('cost-role'), true, 'an amber bar alone marks its panel');
  look = show(0, 512);
  assert.equal(look('host'), true, 'an amber swap bar marks Host');
  assert.equal(look('cost-role'), false, 'and the mark clears when the problem does');
});

test('a capped inbox read with no unread message in it is not "clear"', () => {
  const dom = boot();
  deliver(dom, snap({ chiefOfStaff: { unread: 0, oldestUnreadAgeSec: null, incomplete: true } }));
  assert.equal($(dom, '#cos-facts .badge'), null, 'older unread messages may sit past the read limit');
  assert.equal($(dom, '#chief-of-staff').hasAttribute('data-look'), true, 'a read that could not see the whole inbox is something to look at');
  assert.match($(dom, '#cos-facts').textContent, /at least 0 not marked read/);
  mock.timers.tick(15000);
  deliver(dom, snap({ chiefOfStaff: { unread: 0, oldestUnreadAgeSec: null } }));
  assert.equal($(dom, '#cos-facts .badge').textContent, 'clear', 'a whole read with nothing unread is clear');
});

test('API billing: a provider whose spend could not be read or priced says so, and the other still counts', () => {
  const dom = boot();
  apiDeliver(dom, apiSnap({ claudeUsd: null, codexUsd: 412.4 }));
  assert.equal(facts($(dom, '#limit-facts'))['Claude spend'], 'Not measured');
  assert.equal(facts($(dom, '#limit-facts'))['Codex spend'], '$412');
  assert.match($(dom, '#limit-note').textContent, /Claude spend is not measured/);
  assert.equal(text(tiles(dom)['Spent this week'], '.tile-value'), '$412.40', 'the measured provider still paces against the limit');
});

// Ruling 12: an under-pace reading is only reassuring when the total is complete. The unread provider's
// spend could already be past the limit, so a partial total shows what was measured and no all-clear.
test('API billing with an incomplete total: at least what was measured, no under-pace badge or green tile, over-pace still shown', () => {
  const dom = boot();
  apiDeliver(dom, apiSnap({ claudeUsd: null, codexUsd: 412.4, complete: false }));
  assert.match($(dom, '#limit-bars').textContent, /at least \$412 of \$1,000.*accounting incomplete/);
  assert.equal($(dom, '#limit-bars .badge.ok'), null, 'no under-pace badge');
  assert.equal(text(tiles(dom)['Pace'], '.tile-value'), 'accounting incomplete');
  assert.equal(tiles(dom)['Pace'].classList.contains('ok'), false, 'no green tile');
  assert.match($(dom, '#limit-summary').textContent, /^at least \$412 spent · accounting incomplete/);
  assert.equal(text(strip(dom)['Week pace'], '.measure-value'), 'incomplete');
  assert.equal(strip(dom)['Week pace'].classList.contains('ok'), false);
  assert.equal($(dom, '#limit').hasAttribute('data-look'), true, 'an incomplete total is something to look at');
  mock.timers.tick(15000);
  apiDeliver(dom, apiSnap({ claudeUsd: null, codexUsd: 412.4, complete: false, underUsd: -50, paceSec: -30240, goalUsd: 362.4 }));
  assert.equal(text(tiles(dom)['Over pace by'], '.tile-value'), '$50 · 8h 24m', 'what was measured is already over pace');
  assert.ok(tiles(dom)['Over pace by'].classList.contains('crit'));
  assert.match($(dom, '#limit-bars .badge.crit').textContent, /\$50 over pace/);
});

test('the oldest sample counts the picked project\'s sources, not the machine\'s alone', () => {
  const dom = boot();
  const w = wrap(snap());
  // As the collector writes it: a project's own sources sit under the project.
  w.projects.demo.sources = { 'git-main': fresh(iso(Date.now() - 360000)) };
  deliver(dom, w);
  assert.match($(dom, '#status').textContent, /; oldest sample 6 min ago$/, 'a project section sampled 6 min ago must not read as 0 s');
});

// The plugin's page links to no meeting page of anyone's: the owner ruled that link out of the plugin.
test('no_standup_link: neither the page nor its script names a standup', () => {
  assert.doesNotMatch(html, /stand-?up/i);
  assert.doesNotMatch(appSrc, /stand-?up/i);
});

// One dashboard serves every listed repo, one project a page. The project is the URL's (`?project=<name>`); the
// bare address is the home project. The top bar's links are the only way between them.
const two = (over = {}) => {
  const a = wrap(snap());
  const s = snap();
  s.units.inFlight = [row('unit-z', 'building')];
  s.mainChain.unpushed = 9;
  const b = wrap(s).projects.demo;
  b.sources = { 'git-main': { sampledAt: null, status: 'not-measured', staleSince: null, error: 'x' } };
  return { ...a, limit: limitSnap(), home: 'beta', projects: { alpha: a.projects.demo, beta: b }, ...over };
};
const at = (name) => `http://dash.test/index.html?project=${name}`;
const bar = (dom) => $$(dom, '#projects a').map((a) => [a.textContent, a.getAttribute('href'), a.getAttribute('aria-current')]);
test('top_bar: every listed project is a link to its own address; the bare address goes on to the home project', () => {
  const dom = boot({ url: at('beta') });
  deliver(dom, two());
  assert.equal($(dom, '#project'), null, 'no picker kept in the browser: the address is the choice');
  assert.deepEqual(bar(dom), [['alpha', 'index.html?project=alpha', null], ['beta', 'index.html?project=beta', 'page']]);
  assert.ok(card(dom, 'unit-z') && !card(dom, 'unit-a'), "the address's project is the one shown");
  assert.equal(dom.window.reloads, 0);
  // Home is whichever checkout the collector runs for, and can change: a page, its links and its layout do not.
  mock.timers.tick(15000);
  deliver(dom, two({ home: 'alpha' }));
  assert.deepEqual(bar(dom), [['alpha', 'index.html?project=alpha', null], ['beta', 'index.html?project=beta', 'page']]);
  assert.ok(card(dom, 'unit-z'), 'a refresh, and a new home, keep the project shown');
  assert.equal(dom.window.reloads, 0);
  // A name with a character an address cannot carry bare is encoded in its link.
  const odd = boot({ url: at('beta') });
  deliver(odd, two({ projects: { 'a&b=c': {}, beta: {} } }));
  assert.equal(bar(odd)[0][1], 'index.html?project=a%26b%3Dc');
});

test('bare_address_goes_to_the_home_project: it shows home, leaves for home\'s own address, and reads and saves no layout', async () => {
  const dom = boot({ url: 'http://dash.test/index.html', layout: { rev: 4, hidden: ['host'], projects: { beta: { hidden: ['limit'] } } }, store: { 'commandeck-dashboard-hidden': '["units"]' } });
  const w = dom.window;
  assert.deepEqual($$(dom, 'main.grid > .card').filter((c) => c.hidden).map((c) => c.id), [], 'no layout is read at the bare address');
  click(dom, $(dom, '#cost-role button[data-hide]'));
  await settle();
  assert.equal(w.reloads, 0, 'with no snapshot there is nowhere to go yet');
  deliver(dom, two());
  await settle();
  assert.ok(w.reloads >= 1, 'the page leaves for the home project\'s address');
  assert.ok(card(dom, 'unit-z') && !card(dom, 'unit-a'), 'and shows home, not the first by name, until it has');
  assert.deepEqual(w.puts, [], 'nothing is saved from an address that names no project');
  const none = boot({ url: 'http://dash.test/index.html' });
  deliver(none, { ...two(), projects: {} });
  assert.equal(none.window.reloads, 0, 'a snapshot with no project: nowhere to go');
  const first = boot({ url: 'http://dash.test/index.html' });
  deliver(first, two({ home: undefined }));
  assert.ok(first.window.reloads >= 1 && card(first, 'unit-a'), 'a snapshot that names no home goes to its first project');
});

test('alerts_stay_the_projects_when_the_collector_stops: the stopped-collector redraw shows no other project\'s alert', () => {
  const alerts = [{ id: 'question-alpha-d1', project: 'alpha', severity: 'warn', text: 'Alpha waits on its owner', since: iso(Date.now()) }];
  const dom = boot({ url: at('beta') });
  deliver(dom, two({ alerts }));
  beat(dom, { at: iso(Date.now()) });
  assert.doesNotMatch($(dom, '#alerts-list').textContent, /Alpha waits/);
  for (let i = 0; i < 20; i += 1) { mock.timers.tick(15000); failLoad(dom); }
  assert.match($(dom, '#alerts-list').textContent, /no new data|collector|stopped/i, 'the collector alert is drawn');
  assert.doesNotMatch($(dom, '#alerts-list').textContent, /Alpha waits/);
});

test('seven_day_limit_on_every_project: the machine readings are the same under each project', () => {
  const read = (dom) => [$(dom, '#limit-tiles').textContent, $(dom, '#host-gauges').textContent];
  const home = boot({ url: at('beta') }); deliver(home, two());
  const other = boot({ url: at('alpha') }); deliver(other, two());
  assert.match(read(home)[0], /44%/, 'the limit is on the page');
  assert.deepEqual(read(other), read(home));
  assert.equal($(other, '#limit').hidden, false);
});

test('projects_are_isolated: one project\'s units, sources, alerts and day cost never show under another', () => {
  const alerts = [{ id: 'host-load-1', severity: 'crit', text: 'Host overloaded', since: iso(Date.now()) },
    { id: 'question-alpha-d1', project: 'alpha', severity: 'warn', text: 'Alpha waits on its owner', since: iso(Date.now()) },
    { id: 'stage-beta/u1', project: 'beta', severity: 'warn', text: 'Beta unit stuck', since: iso(Date.now()) }];
  const limit = limitSnap({ today: { alpha: { spentUsd: 11, claudeUsd: 11, codexUsd: 0, estimatedUsd: 0, unpricedRequests: 0, complete: true } } });
  const home = boot({ url: at('beta') }); deliver(home, two({ alerts, limit }));
  const other = boot({ url: at('alpha') }); deliver(other, two({ alerts, limit }));
  const texts = (dom) => $(dom, '#alerts-list').textContent;
  assert.match(texts(home), /Host overloaded/); assert.match(texts(other), /Host overloaded/, "the machine's alert is on every project");
  assert.match(texts(home), /Beta unit stuck/); assert.doesNotMatch(texts(home), /Alpha waits/);
  assert.match(texts(other), /Alpha waits/); assert.doesNotMatch(texts(other), /Beta unit stuck/);
  const cost = (dom) => $$(dom, '#summary .measure').find((m) => /Cost today/.test(m.textContent)).textContent;
  assert.match(cost(other), /\$11/); assert.doesNotMatch(cost(home), /\$11/, "alpha's day is not beta's");
  assert.equal($(home, '#main-chain').dataset.state, 'not-measured', "a card's freshness is its own project's source record");
  assert.match($(home, '#chain-facts').textContent, /9 commits/);
  // A listed project with nothing collected shows its panels empty, never the other's rows.
  const bare = boot({ url: at('empty') }); deliver(bare, two({ projects: { ...two().projects, empty: {} } }));
  assert.equal(bare.window.reloads, 0);
  assert.equal($$(bare, 'li.unit').length, 0);
  assert.doesNotMatch($(bare, '#chain-facts').textContent, /9 commits/);
});

test('address_names_no_listed_project: a made-up name or a path goes back to the bare address and saves nothing', async () => {
  for (const name of ['nope', '..', '../../data', '%2Fetc%2Fpasswd', '/etc/passwd', 'a%2Fb', '__proto__', 'constructor', '']) {
    const dom = boot({ url: at(name), layout: { rev: 3, hidden: ['host'], projects: { alpha: { hidden: ['limit'] } } } }); const w = dom.window;
    click(dom, $(dom, '#cost-role button[data-hide]'));
    await settle();
    deliver(dom, two());
    await settle();
    assert.ok(w.reloads >= 1, `${name}: the page leaves for the bare address`);
    assert.deepEqual(w.puts, [], `${name}: no save is sent under a name the snapshot does not list`);
    assert.equal($(dom, '#limit').hidden, false, `${name}: and it reads no other project's layout`);
  }
});

test('layout_is_kept_per_project: a project page restores and saves its own slot of the one layout file', async () => {
  const layout = () => ({ rev: 5, hidden: ['host'], order: ['units', 'alerts'], projects: { alpha: { hidden: ['limit'] }, beta: { hidden: ['host'] } } });
  const dom = boot({ url: at('alpha'), layout: layout() }); const w = dom.window;
  assert.deepEqual([$(dom, '#host').hidden, $(dom, '#limit').hidden], [false, true], 'a project reads its own slot');
  assert.deepEqual($$(dom, 'main.grid > .card').map((c) => c.id), DEFAULT_ORDER, 'and nothing kept outside the slots');
  click(dom, $(dom, '#cost-role button[data-hide]'));
  await settle();
  assert.deepEqual([w.puts, w.sentFor], [[{ rev: 5, hidden: ['limit', 'cost-role'] }], ['alpha']], 'a change goes up named for its project');
  assert.equal(w.localStorage.getItem('commandeck-dashboard-hidden:beta'), null, "another project's browser copy is not touched");
  assert.deepEqual(JSON.parse(w.localStorage.getItem('commandeck-dashboard-hidden:alpha')), ['limit', 'cost-role']);
  assert.equal(w.localStorage.getItem('commandeck-dashboard-unsaved:alpha'), null, 'confirmed');
  // Home changing hands moves no layout: beta's page reads beta's slot whether beta is home or not.
  for (const home of ['alpha', 'beta']) {
    const b = boot({ url: at('beta'), layout: layout() }); deliver(b, two({ home }));
    assert.deepEqual([$(b, '#host').hidden, $(b, '#limit').hidden], [true, false], `home ${home}: beta keeps its own layout`);
  }
  // A project the file holds no slot for starts from the defaults, and saves nothing until the snapshot lists it.
  const fresh2 = boot({ url: at('alpha'), layout: { rev: 5, projects: { beta: { hidden: ['limit'] } } }, store: { 'commandeck-dashboard-hidden:beta': '["units"]' } });
  assert.deepEqual($$(fresh2, 'main.grid > .card').filter((c) => c.hidden).map((c) => c.id), []);
  click(fresh2, $(fresh2, '#cost-role button[data-hide]'));
  await settle();
  assert.deepEqual(fresh2.window.puts, [], 'nothing is sent before the snapshot lists the project');
  deliver(fresh2, two());
  await settle();
  assert.deepEqual([fresh2.window.puts, fresh2.window.sentFor], [[{ rev: 5, hidden: ['cost-role'] }], ['alpha']], 'then the change goes up');
  // Limit: a layout saved before projects had layouts of their own (unnamed, at the top of the file) is not
  // carried over. It is no error, and every project starts from the default layout, so nothing crosses projects.
  for (const name of ['alpha', 'beta']) {
    const old = boot({ url: at(name), file: { rev: 5, hidden: ['host'], sizes: { limit: 3 }, order: ['units', 'alerts'] } });
    deliver(old, two());
    assert.deepEqual($$(old, 'main.grid > .card').map((c) => c.id), DEFAULT_ORDER, `${name}: the default order`);
    assert.deepEqual([$(old, '#host').hidden, $(old, '#limit').dataset.size], [false, String(DEFAULT_SIZES.limit)], `${name}: nothing hidden, the default width`);
    assert.ok(card(old, name === 'alpha' ? 'unit-a' : 'unit-z'), `${name}: and the page draws`);
  }
});

// A finished build is how the owner checks what landed: it is drawn as the running block is, so what landed reads
// the same way as what is in flight, and it stays until cleared. Cleared is kept with the layout, on the host, so it
// stays cleared in a browser that never saw the click.
const CLOSED_KEY = 'commandeck-dashboard-closed:demo';
// A build is told from another by its merge commit, which is also what a clear remembers.
const SHA_NEW = `abcdef12${'0'.repeat(32)}`, SHA_OLD = 'b'.repeat(40);
const finishedBuilds = () => [
  { unit: 'batch-new', how: 'merged', at: iso(T0 - HOUR), sha: SHA_NEW, open: { P1: 0, P2: 2, P3: 0 } },
  { unit: 'batch-old', how: 'merged', at: null, sha: SHA_OLD, open: null },
];
const withFinished = (fin = finishedBuilds()) => { const s = snap(); s.units.inFlight = [builderRow('batch-run', 'building')]; s.units.finishedBuilds = fin; return s; };
test('same_block_for_finished_build: a finished build is drawn with the running block; closing removes it, and it stays closed after a reload, a Reset layout and in a new browser', () => {
  const dom = boot();
  deliver(dom, withFinished());
  assert.deepEqual($$(dom, '#builds-list > .build').map((b) => b.dataset.unit), ['batch-run', 'batch-new', 'batch-old'], 'running first, then finished, newest first');
  assert.equal($(dom, '#builds-sub').textContent, '1 of 1 working · 2 finished', 'a finished build is not a working Builder');
  const parts = (el) => [...el.children].map((c) => c.className);
  const done = build(dom, 'batch-new');
  assert.deepEqual(parts(done), parts(build(dom, 'batch-run')), 'the same parts in the same order as a running build');
  assert.deepEqual(parts(done), ['uline', 'mdls', 'steps', 'mbar h14', 'cap', 'more']);
  assert.ok(done.classList.contains('finished') && !build(dom, 'batch-run').classList.contains('finished'), 'only the finished one is marked finished');
  assert.equal(done.querySelector('.uline small').textContent, 'merged 60 min ago');
  assert.deepEqual([...done.querySelectorAll('.mdl')].map((t) => t.textContent), ['Builder', 'merged']);
  assert.deepEqual(stepNow(done), ['Build+', 'Review+', 'Fix+', 'Closing pass+', 'MergeP2 2 open at merge+'], 'a merged build has every step behind it');
  assert.equal(done.querySelector('.mbar i').style.width, '100%');
  assert.deepEqual(facts(done), { Ended: 'merged Oct 1, 2026, 7:00 AM', 'Open at merge': 'P2 2', 'Merge commit': 'abcdef12' });
  assert.deepEqual(facts(build(dom, 'batch-old')), { Ended: 'merged at a time not recorded', 'Open at merge': 'not recorded', 'Merge commit': 'bbbbbbbb' });
  const close = done.querySelector('button[data-close]');
  assert.equal(close.getAttribute('aria-label'), 'Close batch-new');
  assert.equal(build(dom, 'batch-run').querySelector('button[data-close]'), null, 'a running build has no close control');
  click(dom, close);
  assert.equal(build(dom, 'batch-new'), undefined, 'closing removes it at once');
  assert.deepEqual(stored(dom, CLOSED_KEY), [SHA_NEW], 'a clear remembers the commit, not the name');
  assert.deepEqual([dom.window.sentFor.at(-1), dom.window.puts.at(-1).closed], ['demo', [SHA_NEW]], 'and it is saved to the host, under this project');
  mock.timers.tick(15000);
  deliver(dom, withFinished());
  assert.equal(build(dom, 'batch-new'), undefined, 'a refresh does not bring it back');
  assert.equal($(dom, '#builds-sub').textContent, '1 of 1 working · 1 finished');
  click(dom, $(dom, '#reset-layout'));
  assert.deepEqual(dom.window.puts.at(-1).closed, [SHA_NEW], 'Reset layout is about panels: what was cleared stays cleared');
  const again = boot({ store: { [CLOSED_KEY]: dom.window.localStorage.getItem(CLOSED_KEY) } });
  deliver(again, withFinished());
  assert.deepEqual($$(again, '#builds-list > .build').map((b) => b.dataset.unit), ['batch-run', 'batch-old'], 'closed stays closed after Reset layout and a reload');
  const other = boot({ layout: { rev: 4, closed: [SHA_NEW] } });
  deliver(other, withFinished());
  assert.deepEqual($$(other, '#builds-list > .build').map((b) => b.dataset.unit), ['batch-run', 'batch-old'], 'a browser with nothing of its own reads it from the host');
  // The unit name is used again for new work: that is another build, and it is listed.
  const reused = finishedBuilds();
  reused[0] = { ...reused[0], sha: 'c'.repeat(40), at: iso(T0) };
  mock.timers.tick(15000);
  deliver(other, withFinished(reused));
  assert.deepEqual($$(other, '#builds-list > .build').map((b) => b.dataset.unit), ['batch-run', 'batch-new', 'batch-old'], 'a later build under a cleared build\'s name is not hidden');
  // The finished list has its own source: it is drawn when the running builds could not be read.
  const half = boot();
  const h = withFinished();
  h.units.inFlight = null;
  deliver(half, h);
  assert.deepEqual($$(half, '#builds-list > .build').map((b) => b.dataset.unit), ['batch-new', 'batch-old'], 'unread worktrees do not hide what was merged');
  assert.equal($(half, '#builds-sub').textContent, '2 finished');
  const blind = boot();
  const s = withFinished(null);
  deliver(blind, s);
  assert.match($(blind, '#builds-list').textContent, /Finished builds not measured/, 'a list that was not read is not "none finished"');
  const none = boot();
  deliver(none, withFinished([]));
  assert.deepEqual($$(none, '#builds-list > .build').map((b) => b.dataset.unit), ['batch-run'], 'no finished build: the running ones alone, and no warning');
  assert.doesNotMatch($(none, '#builds-list').textContent, /not measured/);
});

// A pass that ends NO-GO is never green. Green is only for a step that is done and whose last word stands;
// red is a step or fact that ended badly; amber is one that needs someone or is no longer current. A green
// NO-GO told the owner a failed review had passed.
const colours = (el) => [...el.querySelectorAll('.step')].map((s) => `${s.firstChild.textContent}:${s.classList.contains('crit') ? 'red'
  : s.classList.contains('warn') ? 'amber' : s.classList.contains('done') ? 'green' : s.classList.contains('now') ? 'blue' : 'gray'}`);
const stepNote = (el, label) => { const b = [...el.querySelectorAll('.step')].find((s) => s.firstChild.textContent === label).querySelector('b'); return b ? b.textContent : null; };
const ended = (pass, round, rc = 0) => ({ kind: 'codex', pass, round, start: iso(T0 - 9000), end: iso(T0 - 1000), rc });
const running = (pass, round) => ({ ...ended(pass, round, null), end: null });
const one = (stage, builder = {}, over = {}) => { const d = boot(); const n = snap(); n.units.inFlight = [builderRow('x', stage, { built: [11, 12, 13, 14], ...builder }, over)]; deliver(d, n); return build(d, 'x'); };
const nogo = (round, findings) => ({ verdict: 'VERDICT: NO-GO', verdictRound: round, findings: { P0: 0, P1: 0, P2: 0, P3: 0, ...findings } });
const dd = (el, term) => [...el.querySelectorAll('dt')].find((dt) => dt.textContent === term).nextElementSibling;
const marked = (el, term, cls) => [...dd(el, term).querySelectorAll(`.${cls}`)].map((x) => x.textContent);

test('healthy_running_build_keeps_its_colours: a build with nothing wrong is green behind, blue at its step and gray ahead', () => {
  assert.deepEqual(colours(one('building')), ['Build:blue', 'Review:gray', 'Fix:gray', 'Closing pass:gray', 'Merge:gray']);
  assert.deepEqual(colours(one('review', { steps: [running('adversarial', 1)] })), ['Build:green', 'Review:blue', 'Fix:gray', 'Closing pass:gray', 'Merge:gray']);
  assert.deepEqual(colours(one('review', { steps: [running('final', 3), ended('review', 2)], verdict: 'VERDICT: GO', verdictRound: 2 })),
    ['Build:green', 'Review:green', 'Fix:green', 'Closing pass:blue', 'Merge:gray'], 'a GO on the tree the closing pass is now reading still stands');
});

test('f29_closing_pass_that_ended_nogo_is_never_green: red with a P0 or P1 open, amber on P2 or P3 only, with or without work after it', () => {
  const p1 = one('waiting-main', { steps: [ended('final', 6)], ...nogo(6, { P1: 1, P2: 2 }) });
  assert.deepEqual(colours(p1), ['Build:green', 'Review:green', 'Fix:green', 'Closing pass:red', 'Merge:gray']);
  assert.equal(stepNote(p1, 'Closing pass'), 'pass 6 ended NO-GO');
  assert.deepEqual(colours(one('waiting-main', { steps: [ended('final', 6)], ...nogo(6, { P2: 2 }) })), ['Build:green', 'Review:green', 'Fix:green', 'Closing pass:amber', 'Merge:gray']);
  assert.deepEqual(colours(one('fixing', { steps: [ended('final', 6)], ...nogo(6, { P3: 1 }) })), ['Build:green', 'Review:green', 'Fix:green', 'Closing pass:amber', 'Fix:blue', 'Merge:gray'],
    'the fix under way does not turn the closing pass green');
  assert.deepEqual(colours(one('fixing', { steps: [ended('final', 6, 1)] }))[3], 'Closing pass:red', 'a closing pass that exited with an error');
});

test('f30_nogo_with_a_p1_is_red: the Review step behind a pass that ended NO-GO with a P0 or P1 open is red, fix under way or not', () => {
  assert.deepEqual(colours(one('fixing', { steps: [ended('review', 2)], ...nogo(2, { P1: 1, P2: 3 }) })), ['Build:green', 'Review:red', 'Fix:blue', 'Closing pass:gray', 'Merge:gray']);
  assert.equal(colours(one('fixing', { steps: [ended('adversarial', 1)], ...nogo(1, { P0: 1 }) }))[1], 'Review:red');
  assert.equal(colours(one('review', { steps: [running('review', 3), ended('review', 2)], ...nogo(2, { P1: 1 }) }))[1], 'Review:red', 'the next pass running does not clear it');
  assert.equal(colours(one('fixing', { steps: [ended('review', 2)], verdict: 'VERDICT: NO-GO', verdictRound: 2, findings: null }))[1], 'Review:red', 'a NO-GO whose findings were not read is not shown as the milder one');
});

test('f30_nogo_with_p2_only_is_amber: the Review step behind a NO-GO on P2 or P3 only is amber, and green again once a later pass ended GO', () => {
  assert.deepEqual(colours(one('fixing', { steps: [ended('review', 2)], ...nogo(2, { P2: 2, P3: 1 }) })), ['Build:green', 'Review:amber', 'Fix:blue', 'Closing pass:gray', 'Merge:gray']);
  assert.equal(colours(one('fixing', { steps: [ended('review', 3), ended('review', 2)], verdict: 'VERDICT: GO', verdictRound: 3 }))[1], 'Review:green', 'a later GO that stands');
});

test('f30_errored_pass_is_red: the Review step behind a pass that exited with an error, or left no verdict that can be read, is red', () => {
  assert.equal(colours(one('fixing', { steps: [ended('review', 2, 1)], verdict: 'VERDICT: GO', verdictRound: 2 }))[1], 'Review:red', 'an error exit, whatever the round file says');
  assert.equal(colours(one('fixing', { steps: [ended('review', 2)], verdict: null, verdictRound: null }))[1], 'Review:red', 'no verdict');
  assert.equal(colours(one('fixing', { steps: [ended('review', 3)], verdict: 'VERDICT: GO', verdictRound: 2 }))[1], 'Review:red', 'the verdict on record is an older pass\'s');
});

test('f31_waiting_on_main_marks_its_step: a build that stopped for main shows where it stopped, in amber, and says it waits on main', () => {
  const after = one('waiting-main', { steps: [ended('review', 2)], ...nogo(2, { P2: 1 }) });
  assert.deepEqual(colours(after), ['Build:green', 'Review:amber', 'Fix:amber', 'Closing pass:gray', 'Merge:gray']);
  assert.equal(stepNote(after, 'Fix'), 'waiting on main');
  const before = one('waiting-main');
  assert.deepEqual(colours(before), ['Build:amber', 'Review:gray', 'Fix:gray', 'Closing pass:gray', 'Merge:gray'], 'no pass yet: it stopped while building');
  assert.equal(stepNote(before, 'Build'), 'waiting on main');
  const merge = one('waiting-main', { steps: [ended('final', 4)], verdict: 'VERDICT: GO', verdictRound: 4 });
  assert.deepEqual(colours(merge), ['Build:green', 'Review:green', 'Fix:green', 'Closing pass:green', 'Merge:amber'], 'a clean closing GO waits on main for the merge');
  assert.equal(stepNote(merge, 'Merge'), 'waiting on main');
});

test('f32_go_older_than_the_work_after_it_is_amber: a GO on a tree that has since changed is not drawn as reviewed', () => {
  const b = one('fixing', { steps: [ended('final', 6)], verdict: 'VERDICT: GO', verdictRound: 6, reviewedTree: false });
  assert.deepEqual(colours(b), ['Build:green', 'Review:green', 'Fix:green', 'Closing pass:amber', 'Fix:blue', 'Merge:gray']);
  assert.equal(stepNote(b, 'Closing pass'), 'pass 6 ended GO');
  assert.equal(colours(one('fixing', { steps: [ended('review', 3)], verdict: 'VERDICT: GO', verdictRound: 3, reviewedTree: false }))[1], 'Review:amber', 'a review GO too');
  assert.equal(colours(one('fixing', { steps: [ended('review', 3)], verdict: 'VERDICT: GO', verdictRound: 3, reviewedTree: null }))[1], 'Review:amber', 'a tree that could not be compared is not known to be the reviewed one');
  assert.equal(colours(one('review', { steps: [running('final', 4), ended('review', 3)], verdict: 'VERDICT: GO', verdictRound: 3, reviewedTree: false }))[1], 'Review:amber',
    'a pass started on the changed tree has given no verdict: starting it does not make the old GO stand');
});

test('f33_signal_colours_the_current_step: a stuck build\'s step is red, a quiet or looping one amber', () => {
  assert.equal(colours(one('building', { signals: [{ kind: 'stuck' }] }))[0], 'Build:red');
  assert.equal(colours(one('building', { signals: [{ kind: 'quiet' }] }))[0], 'Build:amber');
  assert.equal(colours(one('fixing', { steps: [ended('review', 2)], verdict: 'VERDICT: GO', verdictRound: 2, signals: [{ kind: 'loop' }] }))[2], 'Fix:amber');
  assert.equal(colours(one('building', { signals: [{ kind: 'quiet' }, { kind: 'stuck' }] }))[0], 'Build:red', 'the worse of two wins');
});

test('f34_wait_on_main_is_amber: only a wait on main is coloured; a wait on a pass, a subagent or a tool is plain at any age', () => {
  const w = [{ kind: 'subagent', what: 'Explore', since: iso(T0 - 5 * HOUR) }];
  assert.deepEqual(marked(one('waiting-main', { waiting: [] }), 'Waiting on', 'warn'), ['main']);
  const plain = one('building', { waiting: w });
  assert.deepEqual(marked(plain, 'Waiting on', 'warn'), []);
  assert.equal(facts(plain)['Waiting on'], 'Explore subagent, for 5 h');
});

test('f35_review_line_colours_a_nogo_and_p0_p1_counts: the verdict takes the pass\'s colour and a P0 or P1 count is red', () => {
  const bad = one('fixing', { steps: [ended('review', 2)], ...nogo(2, { P1: 1, P2: 4 }), reviewSec: 600 });
  assert.equal(facts(bad).Review, 'pass 2 · P1 1 · P2 4 · 10 min in review · VERDICT: NO-GO', 'the words do not change');
  assert.deepEqual(marked(bad, 'Review', 'crit'), ['P1 1', 'VERDICT: NO-GO']);
  const mild = one('fixing', { steps: [ended('review', 2)], ...nogo(2, { P2: 4 }) });
  assert.deepEqual([marked(mild, 'Review', 'crit'), marked(mild, 'Review', 'warn')], [[], ['VERDICT: NO-GO']]);
  const go = one('fixing', { steps: [ended('review', 2)], verdict: 'VERDICT: GO', verdictRound: 2, findings: { P0: 0, P1: 0, P2: 0, P3: 1 } });
  assert.deepEqual([marked(go, 'Review', 'crit'), marked(go, 'Review', 'warn')], [[], []], 'a GO is plain');
});

test('f36_build_step_that_disagrees_with_its_bar_is_amber: Build is not green while the bar says issues are not recorded as built', () => {
  assert.equal(colours(one('review', { built: [2366], steps: [running('adversarial', 1)] }))[0], 'Build:amber');
  assert.equal(colours(one('review', { built: null, steps: [running('adversarial', 1)] }))[0], 'Build:green', 'a count that was not read disagrees with nothing');
  assert.equal(colours(one('building', { built: [] }))[0], 'Build:blue', 'a build still building is expected to have issues left');
});

test('f37_old_builds_sample_is_marked: a Builds sample older than 120 s is amber in the panel header', () => {
  const at = (sec) => { const d = boot(); const s = snap(); s.sources['builder-logs'] = fresh(iso(Date.now())); s.sources.worktrees = fresh(iso(Date.now() - sec * 1000)); deliver(d, s); return d; };
  const old = at(240);
  assert.equal($(old, '#builds .age').textContent, 'sampled 4 min ago');
  assert.deepEqual($$(old, '.age.old').map((a) => a.closest('.card').id), ['builds'], 'only the panel that sets a limit is marked');
  assert.equal($(at(120), '#builds .age').classList.contains('old'), false, 'two collector turns are not old');
});

test('f38_finished_build_shows_how_it_ended: findings open at the merge make the Merge step amber, and a build that ended unmerged has a red one', () => {
  const dom = boot();
  const s = snap();
  const fin = (unit, how, open, i) => ({ unit, how, at: iso(T0 - HOUR), sha: String(i).repeat(40), open });
  s.units.finishedBuilds = [fin('open', 'merged', { P1: 0, P2: 2, P3: 0 }, 1), fin('clean', 'merged', { P1: 0, P2: 0, P3: 0 }, 2),
    fin('unread', 'merged', null, 3), fin('dropped', 'abandoned', undefined, 4)];
  deliver(dom, s);
  assert.deepEqual(colours(build(dom, 'open')), ['Build:green', 'Review:green', 'Fix:green', 'Closing pass:green', 'Merge:amber']);
  assert.equal(stepNote(build(dom, 'open'), 'Merge'), 'P2 2 open at merge');
  for (const u of ['clean', 'unread']) assert.deepEqual(colours(build(dom, u)), ['Build:green', 'Review:green', 'Fix:green', 'Closing pass:green', 'Merge:green'], u);
  assert.deepEqual(colours(build(dom, 'dropped')), ['Build:gray', 'Review:gray', 'Fix:gray', 'Closing pass:gray', 'Merge:red']);
  assert.equal(stepNote(build(dom, 'dropped'), 'Merge'), 'not merged');
});

test('a finished-builds list of the wrong shape draws what it can and breaks nothing', () => {
  const dom = boot();
  const P = '<img src=x onerror="window.__pwned=1">';
  deliver(dom, withFinished([null, 7, 'x', {}, { unit: 5 }, { unit: P, how: P, at: P, sha: P, open: { P1: P, P2: -1 } }, { unit: 'no-commit', sha: null },
    { unit: 'ok-one', how: 'merged', at: iso(T0), sha: 'ab', open: {} }, { unit: 'part', sha: 'cd', open: { P1: null, P2: 1, P3: 0 } },
    { unit: 'clean', sha: 'ef', open: { P1: 0, P2: 0, P3: 0 } }]));
  assert.deepEqual($$(dom, '#builds-list > .build.finished').map((b) => b.dataset.unit), [P, 'ok-one', 'part', 'clean'], 'a row with no unit name or no commit is not drawn');
  assert.equal($(dom, '#builds-list img'), null, 'a field is text, never markup');
  assert.equal(dom.window.__pwned, undefined);
  assert.equal(facts(build(dom, 'ok-one'))['Open at merge'], 'not recorded', 'no counts is unknown, never "nothing open"');
  assert.equal(facts(build(dom, 'part'))['Open at merge'], 'not recorded', 'one unknown count leaves the whole reading unknown');
  assert.equal(facts(build(dom, 'clean'))['Open at merge'], 'nothing open', 'three counted zeros are nothing open');
  assert.equal(facts($(dom, '#needs'))['Open P1'], '0 on finished builds · 3 not recorded', 'and the needs panel says how many builds it could not count');
});

// The panel is the owner's to act on while a build that landed still has a P1 open: clearing the build from the list
// is tidying, not an answer, so it does not drop the panel.
test('needs_kept_by_open_p1: a finished build with an open P1 keeps the needs panel in the needs-a-look view, cleared or not; none open drops it', () => {
  const quiet = (fin) => {
    const s = withFinished(fin);
    s.alerts = [];
    s.needsOwner.decisions = [];
    return s;
  };
  const p1 = finishedBuilds();
  p1[1].open = { P1: 2, P2: 0, P3: 0 };
  const dom = boot();
  deliver(dom, quiet(p1));
  assert.equal($(dom, '#needs').hasAttribute('data-look'), true, 'no open decision, two open P1: still shown');
  assert.equal(facts($(dom, '#needs'))['Open P1'], '2 on finished builds');
  click(dom, $(dom, '#needs-look'));
  assert.equal(dom.window.getComputedStyle($(dom, '#needs')).display !== 'none' && dom.window.document.body.classList.contains('look-only'), true);
  click(dom, build(dom, 'batch-old').querySelector('button[data-close]'));
  mock.timers.tick(15000);
  deliver(dom, quiet(p1));
  assert.equal(build(dom, 'batch-old'), undefined);
  assert.equal($(dom, '#needs').hasAttribute('data-look'), true, 'a cleared build with an open P1 still keeps the panel');
  mock.timers.tick(15000);
  deliver(dom, quiet(finishedBuilds()));
  assert.equal($(dom, '#needs').hasAttribute('data-look'), false, 'nothing open: dropped');
  assert.equal(facts($(dom, '#needs'))['Open P1'], '0 on finished builds · 1 not recorded');
  mock.timers.tick(15000);
  deliver(dom, quiet(null));
  assert.equal(facts($(dom, '#needs'))['Open P1'], 'Not measured', 'a list that was not read is not "none open"');
});

// The plugin's own merge never leaves a P1 open, so the count that can fire the rule is the project's GitHub issues
// labelled P1. A count the collector could not get is unknown: it is never drawn as 0.
test('needs_kept_by_github_p1: open GitHub P1 issues keep the needs panel and are counted on it; an unknown count is never 0', () => {
  const quiet = (over) => {
    const s = withFinished(finishedBuilds());
    s.alerts = [];
    s.needsOwner.decisions = [];
    return { ...s, ...over };
  };
  const needs = (dom) => [$(dom, '#needs').hasAttribute('data-look'), facts($(dom, '#needs'))['Open P1 on GitHub']];
  const dom = boot();
  deliver(dom, quiet({ githubP1: 3 }));
  assert.deepEqual(needs(dom), [true, '3'], 'no open decision, no P1 on a build, three P1 issues: still shown, and it says how many');
  click(dom, $(dom, '#needs-look'));
  assert.notEqual(dom.window.getComputedStyle($(dom, '#needs')).display, 'none');
  mock.timers.tick(15000);
  deliver(dom, quiet({ githubP1: 0 }));
  assert.deepEqual(needs(dom), [false, '0'], 'none open: dropped');
  for (const unknown of [null, undefined, '3', -1, 2.5, Infinity, [3], { P1: 3 }, '<b id="planted">3</b>']) {
    mock.timers.tick(15000);
    deliver(dom, quiet({ githubP1: unknown }));
    assert.deepEqual(needs(dom), [false, 'Not measured'], `${JSON.stringify(unknown)} is not a count`);
    assert.equal($(dom, '#planted'), null);
  }
  // One project's count is never another's: the page reads the count of the project it shows, by name.
  mock.timers.tick(15000);
  const two = wrap(quiet({}));
  two.projects.other = { githubP1: 7 };
  deliver(dom, two);
  assert.deepEqual(needs(dom), [false, 'Not measured'], "another project's seven are not this project's");
});

// The host keeps a bounded list of cleared builds. A tab that still holds names of builds long off the list must not
// send them again as if new: they would push newer clears out.
test('a save sends as cleared only the builds still listed', async () => {
  const gone = ['d'.repeat(40), 'e'.repeat(40)];
  const dom = boot({ layout: { rev: 2, closed: [...gone, SHA_NEW] } });
  // A save before any list was read (here a Reset layout) names no cleared build: the host keeps what it holds.
  click(dom, $(dom, '#reset-layout'));
  await settle();
  assert.equal(dom.window.puts.length, 1);
  assert.equal('closed' in dom.window.puts[0], false, 'no list read yet: nothing is sent as cleared');
  deliver(dom, withFinished());
  assert.deepEqual($$(dom, '#builds-list > .build.finished').map((b) => b.dataset.unit), ['batch-old'], 'and what the host held is still cleared here');
  assert.equal(dom.window.puts.length, 1, 'the list brings no save of its own: nothing was owed');
  click(dom, build(dom, 'batch-old').querySelector('button[data-close]'));
  assert.deepEqual(dom.window.puts.at(-1).closed, [SHA_NEW, SHA_OLD], 'the two listed builds, and neither name that is off the list');
});

// A clear the host never confirmed (a reload while its save was unanswered) is not lost to the rule above: the
// start-up save holds it back, the save the first list brings sends it, and only then is this browser's copy done.
test('a clear the host never confirmed is sent once the first list is read', async () => {
  const store = { [UNSAVED_KEY]: '1', 'commandeck-dashboard-closed:demo': JSON.stringify([SHA_NEW]) };
  const dom = boot({ layout: { rev: 2 }, store }); const w = dom.window;
  await settle();
  assert.equal(w.puts.length, 1, 'the start-up save');
  assert.equal('closed' in w.puts[0], false, 'which names no cleared build');
  assert.equal(w.localStorage.getItem(UNSAVED_KEY), '2', 'the clear is still owed: a reload now keeps this browser\'s copy');
  deliver(dom, withFinished());
  await settle();
  assert.deepEqual(w.puts.at(-1).closed, [SHA_NEW], 'the first list brings the clear to the host');
  assert.equal(w.localStorage.getItem(UNSAVED_KEY), null, 'and it is confirmed');
  assert.deepEqual($$(dom, '#builds-list > .build.finished').map((b) => b.dataset.unit), ['batch-old']);
  // A fresh browser session, nothing of its own, on the host's file as that save left it: still cleared.
  const fresh = boot({ layout: { rev: 4, closed: [SHA_NEW] } });
  deliver(fresh, withFinished());
  assert.deepEqual($$(fresh, '#builds-list > .build.finished').map((b) => b.dataset.unit), ['batch-old'], 'cleared in a fresh session');
  assert.deepEqual(fresh.window.puts, [], 'which saves nothing by reading');
});

// Where this browser's own copy wins (any change the host never confirmed, here none of them a clear), the builds
// another browser cleared on the host stay cleared: cleared builds are only ever added to.
test('an unsaved change in this browser does not bring back a build cleared from another', async () => {
  const store = { [UNSAVED_KEY]: '1', 'commandeck-dashboard-closed:demo': JSON.stringify([SHA_OLD]) };
  const dom = boot({ layout: { rev: 2, closed: [SHA_NEW] }, store });
  deliver(dom, withFinished());
  await settle();
  assert.deepEqual($$(dom, '#builds-list > .build.finished'), [], 'the host\'s clear and this browser\'s own');
  assert.deepEqual(dom.window.puts.at(-1).closed, [SHA_NEW, SHA_OLD], 'and this browser\'s reaches the host');
  const bare = boot({ layout: { rev: 2, closed: [SHA_NEW] }, store: { [UNSAVED_KEY]: '1' } });
  deliver(bare, withFinished());
  assert.deepEqual($$(bare, '#builds-list > .build.finished').map((b) => b.dataset.unit), ['batch-old'], 'with no copy of its own either');
});

// The panel is named after whoever runs the plugin: the collector reads the name, and it is text from outside.
test('the needs panel is named after the plugin\'s user, as text, and after "the owner" when no name was read', () => {
  const named = (name) => { const s = snap(); s.needsOwner.name = name; const dom = boot(); deliver(dom, s); return dom; };
  const dom = named('Ada Lovelace');
  assert.match($(dom, '#needs h2').textContent, /Needs Ada Lovelace$/);
  assert.match($(dom, '#decisions').closest('.group').querySelector('h3').textContent, /^Waiting on Ada Lovelace /);
  assert.ok(Object.keys(facts($(dom, '#needs'))).includes('Waiting on Ada Lovelace'));
  assert.ok($$(dom, '#summary .measure').some((m) => /Waiting on Ada Lovelace/.test(m.textContent)), 'the top strip names the same person');
  const P = '<img src=x onerror="window.__pwned=1">"\'&\n</h2><script>window.__pwned=1</script>';
  const bad = named(P);
  assert.equal($(bad, '#needs h2 [data-owner]').textContent, P, 'markup, quotes and a newline are shown as they are');
  assert.equal($(bad, '#needs img, #needs script, #summary img, #summary script'), null);
  assert.equal(bad.window.__pwned, undefined);
  const long = named('n'.repeat(500));
  assert.equal($$(long, 'main.grid > .card').length, DEFAULT_ORDER.length, 'a 500-character name leaves every panel in place');
  for (const empty of [undefined, null, '', '   ', 7, {}]) assert.match($(named(empty), '#needs h2').textContent, /Needs the owner$/, `no name (${JSON.stringify(empty)})`);
});

// The plugin is anyone's: nothing the user reads may carry the name of the person it was first written for.
test('no user-facing text names a person: the page, its script, its styles and the collector', () => {
  const scripts = path.join(VIEW, '..', 'scripts');
  const files = ['index.html', 'app.js', 'app.css'].map((f) => path.join(VIEW, f))
    .concat(fs.readdirSync(scripts).filter((f) => /^dashboard[._]/.test(f)).map((f) => path.join(scripts, f)));
  assert.ok(files.length >= 6, 'the page and the collector are both read');
  for (const f of files) assert.doesNotMatch(fs.readFileSync(f, 'utf8'), /\bMax\b|\bMax's\b|\bBob\b/, `${path.basename(f)} names a person`);
});

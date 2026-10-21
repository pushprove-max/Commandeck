// The dashboard collector reads what changed since the last 60 s cycle, and every value the page reads equals a
// cold read (issue 299). A week of transcripts and eight days of hook fire log were read again every cycle, so a
// cycle ran long and the page fell behind. Each case is labelled `red-first` (it failed on the collector before
// issue 299) or `pin` (it passed there and must keep passing). Reads are counted by running the Python module
// under `python3 -c` with open() wrapped; nothing in the product is there for the test.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPTS = fileURLToPath(new URL('../', import.meta.url));
const DASH = path.join(SCRIPTS, 'dashboard.sh');
const DAY = 86400;
const NOW = 1791633600; // 2026-10-10T12:00:00Z, a Saturday

const iso = (s) => new Date(s * 1000).toISOString();
const slug = (p) => p.replace(/[^a-zA-Z0-9]/g, '-');
const fn = (name) => fs.readFileSync(DASH, 'utf8').match(new RegExp(`^${name}\\(\\) \\{[\\s\\S]*?^\\}`, 'm'))[0];
// No test may read the caller's own Claude folder, Codex home or hook fire log.
const BASE_ENV = (() => {
  const e = { ...process.env, TZ: 'UTC' };
  for (const k of ['CLAUDE_CONFIG_DIR', 'CODEX_HOME', 'COMMANDECK_HOOK_FIRE_LOG', 'COMMANDECK_SCRATCH', 'COMMANDECK_MAIN', 'CLAUDE_PROJECT_DIR', 'CACHE']) delete e[k];
  return e;
})();

function makeCtx(t) {
  const d = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'dash-incr-')));
  t.after(() => fs.rmSync(d, { recursive: true, force: true }));
  const c = { d, home: path.join(d, 'home'), cache: path.join(d, 'cache'), now: NOW, seq: 0, cold: 0, runs: 0 };
  fs.mkdirSync(c.cache, { recursive: true });
  return c;
}

function putFile(c, p, text, mode, mtimeBase) {
  fs.mkdirSync(path.dirname(p), { recursive: true });
  (mode === 'a' ? fs.appendFileSync : fs.writeFileSync)(p, text);
  const m = mtimeBase + ++c.seq;
  fs.utimesSync(p, m, m);
}

function coldDir(c) {
  const d = path.join(c.d, `cold-${++c.cold}`);
  fs.mkdirSync(d, { recursive: true });
  return d;
}

// The Python module under `python3 -c` with open() wrapped to count, per .jsonl path, the opens, the reads line by
// line (ingestions) and the bytes they took. A tail read() (the Codex rate-limit reading) is an open, not an ingestion.
const PRELUDE = `
import builtins, collections, json, os, sys
sys.path.insert(0, ${JSON.stringify(SCRIPTS)})
_open = builtins.open
opens, reads, nbytes = collections.Counter(), collections.Counter(), collections.Counter()
class Counted:
    def __init__(self, f, p):
        self._f, self._p = f, p
    def __enter__(self):
        self._f.__enter__()
        return self
    def __exit__(self, *a):
        return self._f.__exit__(*a)
    def __iter__(self):
        reads[self._p] += 1
        for line in self._f:
            nbytes[self._p] += len(line)
            yield line
    def __getattr__(self, n):
        return getattr(self._f, n)
def counting(p, mode="r", *a, **k):
    f = _open(p, mode, *a, **k)
    if isinstance(p, str) and p.endswith(".jsonl") and "r" in mode and "+" not in mode:
        opens[p] += 1
        return Counted(f, p)
    return f
builtins.open = counting
import dashboard_limit as m
`;
const EPILOGUE = `
with _open(os.environ["COUNTS"], "w") as _f:
    json.dump({"opens": dict(opens), "reads": dict(reads), "bytes": dict(nbytes)}, _f)
`;

// cycle: the collect's stamp, as dashboard.sh sets DASH_CYCLE once per collect for every reader it runs.
function py(c, body, cycle = c.now) {
  const counts = path.join(c.d, `counts-${++c.runs}.json`);
  const r = spawnSync('python3', ['-c', PRELUDE + body + EPILOGUE], {
    encoding: 'utf8',
    env: { ...BASE_ENV, HOME: c.home, COUNTS: counts, COMMANDECK_CODEX_REVIEW_HOME: path.join(c.d, 'no-review'), DASH_CYCLE: String(cycle) },
  });
  assert.equal(r.status, 0, r.stderr);
  return { out: r.stdout, ...JSON.parse(fs.readFileSync(counts, 'utf8')) };
}

function bash(script, env, cwd) {
  const r = spawnSync('bash', ['-c', script], { encoding: 'utf8', env: { ...BASE_ENV, ...env }, cwd });
  return { out: r.stdout, err: r.stderr, status: r.status };
}

const stateText = (dir) => {
  let s = '';
  const walk = (d) => {
    if (!fs.existsSync(d)) return;
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      if (e.isDirectory()) walk(path.join(d, e.name));
      else s += fs.readFileSync(path.join(d, e.name), 'utf8');
    }
  };
  walk(dir);
  return s;
};

// ---- the four readers, one adapter each --------------------------------------------------------------------------
// line(id, out): one full record, newline included, whose visible effect is the id. ids(c, cold): the sorted ids a
// read shows; a warm read is a new cycle, a cold one reads the same files with no state.

const claudeReq = (c, cache, since = c.now - 7 * DAY, now = c.now) => `m.requests(${JSON.stringify(path.join(c.d, 'proj'))}, ${JSON.stringify(cache)}, ${since}, ${now})`;
const codexReq = (c, cache, since = c.now - 7 * DAY, now = c.now) => `m.codex_requests(${JSON.stringify(path.join(c.d, 'cx'))}, ${JSON.stringify(cache)}, ${since}, ${now})`;

function requestsAdapter(name, dir, cacheName, call, line) {
  return {
    name, keepsRows: true,
    setup(t) { const c = makeCtx(t); fs.mkdirSync(path.join(c.d, dir), { recursive: true }); return c; },
    path: (c, n) => path.join(c.d, dir, `${n}.jsonl`),
    put(c, n, text, mode = 'w') { putFile(c, this.path(c, n), text, mode, NOW - 3600); },
    rm(c, n) { fs.rmSync(this.path(c, n)); },
    line,
    stateDir: (c) => c.cache,
    // The rows a gone file gave stay (they are spend), and with them its name: the files with a place kept are the state.
    tracked(c) {
      const s = JSON.parse(fs.readFileSync(path.join(c.cache, cacheName), 'utf8'));
      return JSON.stringify(Object.keys(s.offsets ?? s.files));
    },
    ids(c, cold = false) {
      if (!cold) c.now += 60;
      const cache = path.join(cold ? coldDir(c) : c.cache, cacheName);
      const r = py(c, `rows = ${call(c, cache)}\nprint(json.dumps(sorted(x[6] for x in rows)))`);
      if (!cold) c.last = r;
      return JSON.parse(r.out);
    },
    bytesOf: (c, n) => c.last.bytes[path.join(c.d, dir, `${n}.jsonl`)] ?? 0,
  };
}

const claude = requestsAdapter('claude', 'proj/-w', 'limit-requests.json', claudeReq, (id, out = id) => JSON.stringify({
  type: 'assistant', requestId: `req_${id}`, timestamp: iso(NOW - 7200), cwd: '/w', sessionId: 's', isSidechain: false,
  message: { model: 'claude-opus-5-5', usage: { input_tokens: 1, output_tokens: out, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 } },
}) + '\n');

const codex = requestsAdapter('codex', 'cx/2026/10/10', 'codex-requests.json', codexReq, (id, out = id) => JSON.stringify({
  type: 'token_usage_record', timestamp: iso(NOW - 7200),
  payload: { response_id: `resp_${id}`, usage: { input_tokens: 1, cached_input_tokens: 0, output_tokens: out } },
}) + '\n');

const guard = (() => {
  const body = fn('guard_blocks');
  const dayOf = { f1: '15', f2: '16', f3: '17', f4: '18' };
  const run = (c, cold) => {
    // Empty, not deleted: run-shell-tests.sh exports the one-file override to its tests.
    const env = { HOME: c.home, CACHE: cold ? coldDir(c) : c.cache, COMMANDECK_HOOK_FIRE_LOG: '', PP_PROJECT: 'demo' };
    const r = bash(`ok() { :; }\nnm() { echo "nm $*" >&2; }\n${body}\nguard_blocks`, env);
    assert.equal(r.status, 0, r.err);
    return JSON.parse(r.out);
  };
  return {
    name: 'guard_blocks', keepsRows: false,
    setup(t) { const c = makeCtx(t); fs.mkdirSync(path.join(c.home, '.claude/hook-fire-log'), { recursive: true }); return c; },
    path: (c, n) => path.join(c.home, '.claude/hook-fire-log', `demo.2026-10-${dayOf[n]}.jsonl`),
    put(c, n, text, mode = 'w') { putFile(c, this.path(c, n), text, mode, NOW - 3600); },
    rm(c, n) { fs.rmSync(this.path(c, n)); },
    line: (id, out, extra = {}) => JSON.stringify({
      timestamp: `2026-10-19T10:00:${String(id).padStart(2, '0')}Z`, hook: 'h', decision: 'block', session_id: 's1',
      agent: 'claude', event: 'PreToolUse', tool: 'Bash', worktree: 'w', summary: String(id), use: `u${id}`, call: `c${id}`, ...extra,
    }) + '\n',
    stateDir: (c) => c.cache,
    items: (c, cold = false) => run(c, cold).items,
    ids(c, cold = false) { return run(c, cold).items.map((i) => Number(i.summary)).sort((a, b) => a - b); },
  };
})();

// The Builder's session record: background jobs started, notified and stopped, and the parent's prompt cache.
const builder = (() => {
  const wt = (c) => path.join(c.d, 'wt');
  const dir = (c) => path.join(c.home, '.claude/projects', slug(wt(c)));
  const call = (c, cold, fns) => {
    const main = path.join(c.d, 'main');
    if (!fs.existsSync(main)) spawnSync('git', ['init', '-q', main]);
    const r = bash(`. ${JSON.stringify(path.join(SCRIPTS, 'paths.sh'))} && ${fns}`, {
      HOME: c.home, COMMANDECK_MAIN: main, CACHE: cold ? coldDir(c) : c.cache,
    }, main);
    assert.equal(r.status, 0, r.err);
    return r.out.split('\n');
  };
  const w = (c) => JSON.stringify(wt(c));
  return {
    name: 'builder', keepsRows: false, norm: (ids) => ids.map(() => 0),
    setup(t) { const c = makeCtx(t); fs.mkdirSync(wt(c), { recursive: true }); return c; },
    path: (c, n) => path.join(dir(c), `${n}.jsonl`),
    put(c, n, text, mode = 'w') { putFile(c, this.path(c, n), text, mode, Math.floor(Date.now() / 1000) - 600); },
    rm(c, n) { fs.rmSync(this.path(c, n)); },
    line: (id) => JSON.stringify({ type: 'user', toolUseResult: { stdout: '', backgroundTaskId: `b${id}` } }) + '\n',
    note: (id) => JSON.stringify({ type: 'queue-operation', operation: 'enqueue', content: `<task-notification>\n<task-id>b${id}</task-id>\n<status>completed</status>\n</task-notification>` }) + '\n',
    stateDir: (c) => c.cache,
    summary: (c, cold = false) => call(c, cold, `pp_session_summary ${w(c)}; printf '%s\\n' "$PP_SESSION_LOG" "$PP_SESSION_AT" "$PP_SESSION_BG" "$PP_SESSION_CACHE"`).slice(0, 4),
    old: (c) => call(c, false, `printf '%s\\n' "$(pp_session_log ${w(c)})" "$(pp_session_log_at ${w(c)})" "$(pp_session_bg_open ${w(c)})" "$(pp_session_cache ${w(c)})"`).slice(0, 4),
    ids(c, cold = false) {
      const bg = this.summary(c, cold)[2];
      return Array.from({ length: Number(bg) }, () => 0);
    },
  };
})();

const ADAPTERS = [claude, codex, guard, builder];
const want = (A, ids) => (A.norm ? A.norm(ids) : ids);

// junk <file> <line> -- overwrite a line already read with x's of its length: only a read of the whole file sees it go.
function junk(file, text) {
  const buf = fs.readFileSync(file);
  const at = buf.indexOf(text.replace(/\n$/, ''));
  assert.ok(at >= 0, 'the junked line is in the file');
  fs.writeSync(fs.openSync(file, 'r+'), Buffer.from('x'.repeat(text.length - 1)), 0, text.length - 1, at);
}

// ---- the four cases every reader owes ----------------------------------------------------------------------------
for (const A of ADAPTERS) {
  // red-first: builder x4 (pp_session_summary is new), guard_blocks rotation_and_retention and
  // corrupt_state_is_cold_start (no state before). pin: claude and codex x4, guard_blocks partial_line_waits and
  // truncation_rereads_from_zero (a cold read already met them; they hold the state to the same answer).
  test(`${A.name}: partial_line_waits`, (t) => {
    const c = A.setup(t);
    const full = A.line(2);
    const cut = full.slice(0, full.length - 12);
    A.put(c, 'f1', A.line(1) + cut);
    assert.deepEqual(A.ids(c), want(A, [1]));
    assert.deepEqual(A.ids(c, true), want(A, [1]));
    A.put(c, 'f1', full.slice(cut.length), 'a');
    assert.deepEqual(A.ids(c), want(A, [1, 2]));
    if (A.bytesOf) assert.equal(A.bytesOf(c, 'f1'), full.length, 'only the once-partial line is read again');
    assert.deepEqual(A.ids(c, true), want(A, [1, 2]));
  });

  test(`${A.name}: rotation_and_retention`, (t) => {
    const c = A.setup(t);
    A.put(c, 'f1', A.line(1));
    A.ids(c);
    A.put(c, 'f2', A.line(2));
    A.ids(c);
    const tracked = () => (A.tracked ? A.tracked(c) : stateText(A.stateDir(c)));
    assert.ok(tracked().includes(A.path(c, 'f2')), 'the state is keyed by the file path');
    A.rm(c, 'f1');
    A.put(c, 'f3', A.line(3));
    const expected = A.name === 'guard_blocks' ? [2, 3] : A.name === 'builder' ? [3] : [1, 2, 3];
    assert.deepEqual(A.ids(c), want(A, expected));
    if (!A.keepsRows) assert.deepEqual(A.ids(c, true), want(A, expected));
    assert.ok(!tracked().includes(A.path(c, 'f1')), 'a file that is gone leaves no state');
  });

  test(`${A.name}: truncation_rereads_from_zero`, (t) => {
    const c = A.setup(t);
    A.put(c, 'f1', A.line(1) + A.line(2) + A.line(3));
    assert.deepEqual(A.ids(c), want(A, [1, 2, 3]));
    A.put(c, 'f1', A.line(4));
    assert.deepEqual(A.ids(c), want(A, A.keepsRows ? [1, 2, 3, 4] : [4]));
    if (A.bytesOf) assert.equal(A.bytesOf(c, 'f1'), A.line(4).length, 'the rewritten file is read from its start');
    assert.deepEqual(A.ids(c, true), want(A, [4]));
  });

  test(`${A.name}: corrupt_state_is_cold_start`, (t) => {
    for (const bad of ['{not json', '', '{"version":999}', 'FIRSTHALF']) {
      const c = A.setup(t);
      A.put(c, 'f1', A.line(1) + A.line(2));
      A.ids(c);
      assert.ok(stateText(A.stateDir(c)).length > 0, 'the reader keeps state between cycles');
      for (const f of fs.readdirSync(A.stateDir(c))) {
        const p = path.join(A.stateDir(c), f);
        const text = fs.readFileSync(p, 'utf8');
        fs.writeFileSync(p, bad === 'FIRSTHALF' ? text.slice(0, Math.floor(text.length / 2)) : bad);
      }
      A.put(c, 'f1', A.line(3), 'a');
      assert.deepEqual(A.ids(c), want(A, [1, 2, 3]), `state ${JSON.stringify(bad)} is a cold start`);
    }
  });
}

for (const A of [claude, codex]) {
  // pin: the cached rows and the request key dedupe a streamed request
  test(`${A.name}: duplicate_streamed_request_counted_once`, (t) => {
    const c = A.setup(t);
    A.put(c, 'f1', A.line(7, 5) + A.line(7, 6));
    assert.deepEqual(A.ids(c), [6]);
    A.put(c, 'f1', A.line(7, 9), 'a');
    assert.deepEqual(A.ids(c), [9], 'the last streamed line carries the final usage, and the request is one row');
    assert.deepEqual(A.ids(c, true), [9]);
  });
}

// ---- Claude and Codex: old files keep their offsets, one ingestion per cycle -------------------------------------
// Main's seat sessions are /w's, a unit's /u's; both are under the one transcript folder the limit card reads.
function cliCtx(t) {
  const c = makeCtx(t);
  const claudeFile = (n, ts, w = '-w') => ({ p: path.join(c.d, 'proj', w, `${n}.jsonl`), ts });
  c.files = [claudeFile('old', NOW - 2 * DAY), claudeFile('today', NOW - 3600), claudeFile('unit', NOW - 1800, '-u')];
  c.cxFiles = [
    { p: path.join(c.d, 'cx/2026/10/08/rollout-old.jsonl'), ts: NOW - 2 * DAY },
    { p: path.join(c.d, 'cx/2026/10/10/rollout-today.jsonl'), ts: NOW - 3600 },
  ];
  c.files.forEach((f, i) => putFile(c, f.p, [1, 2, 3].map((k) => claude.line(10 * i + k)).join('').replaceAll(iso(NOW - 7200), iso(f.ts - 60))
    .replaceAll('"cwd":"/w"', f.p.includes('/-u/') ? '"cwd":"/u"' : '"cwd":"/w"'), 'w', f.ts - 10));
  c.cxFiles.forEach((f, i) => putFile(c, f.p, [1, 2, 3].map((k) => codex.line(10 * i + k)).join('').replaceAll(iso(NOW - 7200), iso(f.ts - 60)), 'w', f.ts - 10));
  for (const f of [...c.files, ...c.cxFiles]) fs.utimesSync(f.p, f.ts, f.ts);
  fs.writeFileSync(path.join(c.d, 'usage.json'), JSON.stringify({ seven_day: { utilization: 10, resets_at: '2026-10-13T12:00:00+00:00' } }));
  fs.writeFileSync(path.join(c.d, 'billing.json'), JSON.stringify({ billing: 'api', weeklyLimitUsd: 1000 }));
  return c;
}

// One collect's three readers of the transcripts, as dashboard.sh calls them, each its own process with one `now`:
// the units card's costs and the seats (each project's child collect), then the limit card (the top level).
function cycle(c, now, cache = c.cache) {
  const j = JSON.stringify;
  fs.mkdirSync(cache, { recursive: true });
  const proj = j(path.join(c.d, 'proj')), cx = j(path.join(c.d, 'cx'));
  const units = [{ unit: 'u', worktree: '/u', stages: [{ stage: 'building', from: iso(NOW - DAY), to: null }], plan: null }];
  const runs = [
    py(c, `print(json.dumps(m.unit_costs(json.loads(${j(j(units))}), ${now}, ${j(cache)}, ${proj}, ${cx})))`, now),
    py(c, `print(json.dumps(m.seats(${now}, ${j(cache)}, ${proj}, ${j(path.join(c.home, 'clear-hook.log'))}, "/w")))`, now),
    py(c, `m.main(["x", "build", "fresh", ${j(path.join(c.d, 'usage.json'))}, "${now}", ${j(cache)}, ${proj}, ${cx}, ${j(JSON.stringify({ demo: ['/w', '/u'] }))}])`, now),
  ];
  const sum = (k) => { const o = {}; for (const r of runs) for (const [p, n] of Object.entries(r[k])) o[p] = (o[p] ?? 0) + n; return o; };
  const b = JSON.parse(runs[2].out);
  return { opens: sum('opens'), reads: sum('reads'), bytes: sum('bytes'),
    view: { units: JSON.parse(runs[0].out), seats: JSON.parse(runs[1].out), requests: b.requests, cost: b.cost, today: b.today, api: b.api, cw: b.cacheWritePct24h } };
}

// pin: a file skipped for age kept its offset already; the second cycle reads no byte of a file that did not change
test('claude_and_codex_old_files_keep_offsets', (t) => {
  const c = cliCtx(t);
  cycle(c, NOW);
  const second = cycle(c, NOW + 60);
  for (const f of [...c.files, ...c.cxFiles]) assert.equal(second.bytes[f.p] ?? 0, 0, `${path.basename(f.p)} is not read again`);
  assert.deepEqual(second.view, cycle(c, NOW + 60, path.join(c.d, 'cold-cache')).view, 'the warm cycle equals a cold read');
});

// red-first: the limit card's three windows and the seats each opened the file, and the units card read it too
test('one_ingestion_per_cycle', (t) => {
  const c = cliCtx(t);
  cycle(c, NOW);
  for (const f of [c.files[1], c.files[2]]) fs.appendFileSync(f.p, claude.line(99).replace(iso(NOW - 7200), iso(NOW - 600)).replace('"cwd":"/w"', f.p.includes('/-u/') ? '"cwd":"/u"' : '"cwd":"/w"'));
  fs.appendFileSync(c.cxFiles[1].p, codex.line(99).replace(iso(NOW - 7200), iso(NOW - 600)));
  const second = cycle(c, NOW + 60);
  for (const f of c.files) assert.ok((second.opens[f.p] ?? 0) <= 1, `${path.basename(f.p)} opened ${second.opens[f.p]} times across units, seats and the limit card`);
  // A Codex file is opened once more for the rate-limit reading, from its tail: it is read line by line once.
  for (const f of c.cxFiles) assert.ok((second.reads[f.p] ?? 0) <= 1, `${path.basename(f.p)} read ${second.reads[f.p]} times across the units and the limit card`);
  assert.deepEqual(second.view, cycle(c, NOW + 60, path.join(c.d, 'cold-cache')).view, 'the warm cycle equals a cold read');
  assert.equal(second.view.seats.main.today.tokens, (1 + 11) + (1 + 12) + (1 + 13) + (1 + 99), 'the appended request is counted: main read its three rows of today and the new one');
  const monday = NOW - 5 * DAY, midnight = NOW - 12 * 3600;
  const cxCache = JSON.stringify(path.join(c.cache, 'codex-requests.json'));
  fs.appendFileSync(c.cxFiles[1].p, codex.line(98).replace(iso(NOW - 7200), iso(NOW + 30)));
  const cx = py(c, `a = m.codex_requests(${JSON.stringify(path.join(c.d, 'cx'))}, ${cxCache}, ${midnight}, ${NOW + 120})
b = m.codex_requests(${JSON.stringify(path.join(c.d, 'cx'))}, ${cxCache}, ${monday}, ${NOW + 120})
print(json.dumps([len(a), len(b)]))`, NOW + 120);
  assert.ok((cx.opens[c.cxFiles[1].p] ?? 0) <= 1, `the Codex file is opened ${cx.opens[c.cxFiles[1].p]} times across two calls of one cycle`);
  assert.deepEqual(JSON.parse(cx.out), [5, 8], 'the later call from an earlier start still has every row');
});

// red-first for the hit (no cycle stamp before); the misses below are pins
test('cycle_snapshot_hit', (t) => {
  for (const [A, cacheName, call] of [[claude, 'limit-requests.json', claudeReq], [codex, 'codex-requests.json', codexReq]]) {
    const c = A.setup(t);
    A.put(c, 'f1', A.line(1) + A.line(2));
    A.ids(c);
    const cache = path.join(c.cache, cacheName);
    assert.equal(JSON.parse(fs.readFileSync(cache, 'utf8')).cycle, String(c.now), `${A.name}: the cache names its cycle`);
    const ino = fs.statSync(cache).ino;
    const again = py(c, `rows = ${call(c, cache)}\nprint(json.dumps(sorted(x[6] for x in rows)))`);
    assert.deepEqual(JSON.parse(again.out), [1, 2]);
    assert.deepEqual(again.opens, {}, `${A.name}: a second call in the same cycle opens no file`);
    assert.equal(fs.statSync(cache).ino, ino, `${A.name}: and writes no cache`);
  }
});

// pin: every guard of the hit. A walk writes its cache again (a new file, so a new inode); a hit writes nothing.
test('cycle_snapshot_misses_unless_whole', (t) => {
  for (const [A, cacheName, call] of [[claude, 'limit-requests.json', claudeReq], [codex, 'codex-requests.json', codexReq]]) {
    const c = A.setup(t);
    A.put(c, 'f1', A.line(1));
    A.ids(c);
    const cache = path.join(c.cache, cacheName);
    const saved = JSON.parse(fs.readFileSync(cache, 'utf8'));
    const walked = (since, now) => {
      const ino = fs.statSync(cache).ino;
      py(c, `rows = ${call(c, cache, since, now)}\nprint(json.dumps(len(rows)))`, now);
      return fs.statSync(cache).ino !== ino;
    };
    fs.writeFileSync(cache, JSON.stringify({ ...saved, complete: false }));
    assert.ok(walked(c.now - 7 * DAY, c.now), `${A.name}: an incomplete cache is walked`);
    fs.writeFileSync(cache, JSON.stringify(saved));
    assert.ok(walked(c.now - 8 * DAY, c.now), `${A.name}: a call starting before the cache's coverage is walked`);
    fs.writeFileSync(cache, JSON.stringify(saved));
    assert.ok(walked(c.now - 7 * DAY, c.now + 60), `${A.name}: another cycle is walked`);
  }
});

// ---- guard_blocks and the Builder summary --------------------------------------------------------------------------
// red-first: the whole file was read again every cycle
test('guard_blocks_reads_appended_bytes_only', (t) => {
  const c = guard.setup(t);
  guard.put(c, 'f1', guard.line(1) + guard.line(2));
  assert.deepEqual(guard.ids(c), [1, 2]);
  junk(guard.path(c, 'f1'), guard.line(1));
  guard.put(c, 'f1', guard.line(3), 'a');
  assert.deepEqual(guard.ids(c, true), [2, 3], 'the trick works: a cold read cannot see the overwritten block');
  assert.deepEqual(guard.ids(c), [1, 2, 3], 'the warm read kept block 1 and read only the appended bytes');
});

// pin: a cold read pairs a block with its retry in the next day file; the state must too
test('guard_block_retry_across_days', (t) => {
  const c = guard.setup(t);
  guard.put(c, 'f1', guard.line(1, 0, { call: 'X', use: 'u1' }) + guard.line(2, 0, { session_id: 's2', call: 'Y', use: 'u2' }));
  assert.deepEqual(guard.items(c).map((i) => i.retry), [null, null]);
  const next = (sid, use, call) => JSON.stringify({ timestamp: '2026-10-20T10:00:00Z', hook: 'h', decision: 'allow', session_id: sid, use, call }) + '\n';
  guard.put(c, 'f2', next('s1', 'u9', 'X') + next('s2', 'u9', 'Z'));
  const warm = guard.items(c);
  assert.deepEqual(warm, guard.items(c, true));
  assert.deepEqual(warm.map((i) => [i.summary, i.retry]).sort(), [['1', 'identical'], ['2', 'worked-around']].sort());
});

// pin: an earlier day file that grows is not an append
test('guard_blocks_earlier_file_grew_is_cold', (t) => {
  const c = guard.setup(t);
  guard.put(c, 'f1', guard.line(1));
  guard.put(c, 'f2', guard.line(2));
  guard.ids(c);
  junk(guard.path(c, 'f2'), guard.line(2));
  guard.put(c, 'f1', guard.line(3), 'a');
  assert.deepEqual(guard.ids(c), [1, 3]);
});

// pin: a cycle that could not open a file must save no state, or the recovered read counts its blocks twice
test('guard_blocks_unread_file_does_not_double_count', (t) => {
  const c = guard.setup(t);
  guard.put(c, 'f1', guard.line(1));
  guard.put(c, 'f2', guard.line(2));
  assert.deepEqual(guard.ids(c), [1, 2]);
  fs.chmodSync(guard.path(c, 'f2'), 0);
  guard.ids(c);
  fs.chmodSync(guard.path(c, 'f2'), 0o644);
  assert.deepEqual(guard.ids(c), [1, 2], 'the recovered read counts each block once');
});

// red-first: pp_session_summary is new. Open jobs are kept across cycles, so a job started hours ago still counts.
test('builder_summary_once_per_cycle_keeps_open_jobs', (t) => {
  const c = builder.setup(t);
  builder.put(c, 's1', builder.line(1) + builder.line(2));
  assert.deepEqual(builder.ids(c), [0, 0]);
  junk(builder.path(c, 's1'), builder.line(1));
  junk(builder.path(c, 's1'), builder.line(2));
  builder.put(c, 's1', builder.note(1), 'a');
  assert.deepEqual(builder.ids(c), [0], 'job 2 is still open though its start row is no longer read');
  builder.put(c, 's1', builder.line(3), 'a');
  assert.deepEqual(builder.ids(c), [0, 0]);
  builder.put(c, 's1', builder.note(2) + builder.note(3), 'a');
  assert.deepEqual(builder.ids(c), []);
});

// red-first: the summary gives what pp_session_log, pp_session_log_at, pp_session_bg_open and pp_session_cache gave,
// on their real row shapes: a quoted id, a TaskStop that worked and one that failed, the cache's writes and replies.
test('builder_summary_matches_the_old_functions', (t) => {
  const c = builder.setup(t);
  assert.deepEqual(builder.summary(c), ['', 'null', 'null', 'null'], 'no record: no path, then null three times');
  const user = (ts) => JSON.stringify({ type: 'user', isSidechain: false, timestamp: ts, message: {} }) + '\n';
  const reply = (ts, stop, input, read, write, w1h, w5m, side = false, id = undefined) => JSON.stringify({
    type: 'assistant', isSidechain: side, timestamp: ts,
    message: { ...(id ? { id } : {}), stop_reason: stop, usage: { input_tokens: input, cache_read_input_tokens: read, cache_creation_input_tokens: write,
      cache_creation: { ephemeral_1h_input_tokens: w1h, ephemeral_5m_input_tokens: w5m } } },
  }) + '\n';
  const stop = (id, ok) => JSON.stringify({ type: 'user', toolUseResult: { task_id: id },
    message: { content: ok ? [{ type: 'tool_result', content: `Successfully stopped task: ${id}` }] : `Error: no task ${id}` } }) + '\n';
  const steps = [
    builder.line(1) + builder.line(2) + builder.note(1),
    JSON.stringify({ type: 'user', toolUseResult: 'a result that quotes backgroundTaskId bZZZ9' }) + '\n',
    stop('b2', true),
    builder.line(3) + stop('b3', false),
    user('2026-10-18T09:59:58Z') + reply('2026-10-18T10:00:00Z', 'tool_use', 10, 90000, 5000, 0, 5000, false, 'm1'),
    reply('2026-10-18T10:00:01Z', 'tool_use', 10, 90000, 5000, 0, 5000, false, 'm1') + user('2026-10-18T10:00:30.123Z'),
    reply('2026-10-18T10:00:45Z', 'end_turn', 12, 95000, 0, 0, 0, false, 'm2'),
    reply('2026-10-18T10:01:00Z', 'tool_use', 10, 90000, 7000, 7000, 0, true, 'm3'),
    reply('2026-10-18T10:02:00Z', 'tool_use', 10, 90000, 7000, 7000, 0, false, 'm4'),
  ];
  for (const [i, s] of steps.entries()) {
    builder.put(c, 's1', s, i === 0 ? 'w' : 'a');
    const got = builder.summary(c);
    assert.deepEqual(got, builder.old(c), `after step ${i + 1}`);
    if (i === 3) assert.equal(got[2], '1', 'job 1 notified, job 2 stopped, job 3 open: its TaskStop failed');
    if (i === 6) assert.deepEqual(JSON.parse(got[3]), { ttl: 300, ctx: 95012, at: Date.parse('2026-10-18T10:00:30Z') / 1000, ended: true });
  }
});

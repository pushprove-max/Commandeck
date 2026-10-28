import { expect, test } from 'claude-code/testing'
import { closesOf, newestAttempt, paneLines, parseMergeLog, parseSnapshot, parseTestLive, seatFromGit, seenOf, summaryLine, todaySplit, todayUsd, toasts } from './units-sources'
import type { Seen } from './units-sources'

// The parsers read whole files and hold no state: whatever a log looks like at a poll, the counts come from that text
// alone. These pin the cases where a bounded tail, a byte offset or a half-written line would lose a total.

const STEP2 = 'STEP 2 tests: 3 node test file(s) the selector picks, 0 web, 0 shell test file(s) the unit touches\n'
const NOW = Date.UTC(2026, 9, 25, 15, 10, 0)

test('a half-written last line is dropped', () => {
  const m = parseMergeLog(`${STEP2}-- ok   a.test.ts 1s\n-- FAIL b.test.ts 2`)
  expect(m.done).toBe(1)
  expect(m.failed).toBe(0)
  expect(parseMergeLog('STEP 3 rec').step).toBe(null)
})

// Issue 422: run-shell-tests.sh --skip-passed prints a reused result in its own line grammar, with a 0s field.
test('a result reused at the same tree counts as a finished file', () => {
  const m = parseMergeLog(`${STEP2}-- ok   a.test.sh 0s (passed at this tree in an earlier run)\n`)
  expect([m.done, m.failed]).toEqual([1, 0])
})

test('a total and first failure survive 17,000 bytes of other output', () => {
  const noise = `${'.'.repeat(99)}\n`.repeat(170)
  const m = parseMergeLog(`${STEP2}-- FAIL a.test.ts 1s\n${noise}-- ok   b.test.ts 1s\n`)
  expect(m).toMatchObject({ step: '2 tests', total: 3, done: 2, failed: 1, firstFail: 'a.test.ts' })
})

test('a log rewritten by a rerun shows only the new run', () => {
  const first = parseMergeLog(`${STEP2}-- FAIL a.test.ts 1s\n-- ok   b.test.ts 1s\n`)
  const rerun = parseMergeLog(`${STEP2}-- ok   a.test.ts 1s\n`)
  expect([first.done, first.failed]).toEqual([2, 1])
  expect([rerun.done, rerun.failed, rerun.firstFail]).toEqual([1, 0, null])
})

test('a test path with a space or a relative name parses', () => {
  const m = parseMergeLog(`${STEP2}-- ok   a.test.ts 1s\n-- FAIL /ws/u/b c.test.ts 4s\n`)
  expect(m.firstFail).toBe('/ws/u/b c.test.ts')
  expect(m.done).toBe(2)
})

test('vitest per-file lines with colour codes count', () => {
  const m = parseMergeLog(`STEP 2 tests: 0 node, 3 web, 0 shell test file(s)\n\x1b[32m ✓\x1b[39m src/a.test.ts (22 tests) 25ms\n ❯ src/b.test.tsx (3 tests | 1 failed) 12ms\n ✓ src/c d.test.ts (1 test) 3ms\n`)
  expect(m).toMatchObject({ total: 3, done: 3, failed: 1, firstFail: 'src/b.test.tsx' })
})

test('a refusal keeps its step and the first 120 characters of the reason', () => {
  const m = parseMergeLog(`STEP 3 record: x\nFAILED step 3 record: ${'r'.repeat(200)}\n`)
  expect(m.refused?.step).toBe('step 3 record')
  expect(m.refused?.reason).toHaveLength(120)
})

test('a live test table counts ended files and the first failure', () => {
  const t = parseTestLive('run\t100\t4\nfile\ta.sh\nfile\tb.sh\nfile\tc.sh\nstart\ta.sh\t101\nend\ta.sh\tFAIL\t3\nstart\tb.sh\t102\nend\tb.sh\tok\t1\n')
  expect(t).toMatchObject({ total: 3, done: 2, failed: 1, firstFail: 'a.sh', startedAt: 100 })
})

// The producer joins fields with tabs, so a path may hold spaces; a record without its newline is not yet written.
test('a live test table keeps spaced paths and ignores a record still being written', () => {
  const t = parseTestLive('run\t100\t4\nfile\ta b.sh\nend\ta b.sh\tFAIL\t3\nend\tc.sh\tFA')
  expect(t).toMatchObject({ done: 1, failed: 1, firstFail: 'a b.sh' })
})

// run-shell-tests.sh prints `-- FAIL <name padded to 58> <secs>s rc=1` (or `HUNG past ...`): the file failed, and the name is the bare file.
test('a shell test that failed or hung counts as failed under its bare name', () => {
  const m = parseMergeLog(`${STEP2}-- ok   ${'a.test.sh'.padEnd(58)} 2s\n-- FAIL ${'b.test.sh'.padEnd(58)} 3s rc=1\n-- FAIL c.test.sh 900s HUNG past 900s, killed at its budget, not a failing assertion; host load 1.0\n`)
  expect(m).toMatchObject({ done: 3, failed: 2, firstFail: 'b.test.sh' })
})

test('the seat comes from the git dir, the common dir and the toplevel', () => {
  expect(seatFromGit('/m/.git\n/m/.git\n/m\n')).toEqual({ seat: 'main', main: '/m' })
  expect(seatFromGit('/m/.git/worktrees/x\n/m/.git\n/w/Chief-of-Staff\n')?.seat).toBe('chiefOfStaff')
  expect(seatFromGit('/m/.git/worktrees/x\n/m/.git\n/w/unit\n')?.seat).toBe('worker')
  expect(seatFromGit('')).toBe(null)
})

const dash = (units: object, extra: object = {}) => `window.DASH = ${JSON.stringify({ updatedAt: '2026-10-25T15:00:00Z', home: 'p', projects: { p: { path: '/repo', units } }, ...extra })};`

test('a snapshot parses its units and red marks; junk gives a note', () => {
  const row = (unit: string, extra: object) => ({ unit, stage: 'building', agents: 'claude:working', ageSec: 0, builder: { verdict: null, verdictRound: null, findings: null, cost: { stages: [{ usd: 1.5 }, { usd: 0.25 }] } }, ...extra })
  const s = parseSnapshot(dash({ inFlight: [row('a', {}), row('b', {}), row('c', { agents: 'claude:done' }), row('Chief-of-Staff', { stage: 'chief-of-staff' })], mergedSincePush: [{ unit: 'm' }] }), NOW, 'p')
  expect(s.rows.map(r => `${r.unit}:${r.red ? 'R' : ''}`)).toEqual(['a:', 'b:', 'c:R'])
  expect(s.rows[0].usd).toBe(1.75)
  expect(s.staleMin).toBe(10)
  const old = parseSnapshot(dash({ inFlight: [{ unit: 'u', stage: 'review', round: 2, builder: { verdict: 'VERDICT: GO', verdictRound: 1 } }] }), Date.UTC(2026, 9, 25, 15, 0, 0), 'p')
  expect(old.rows[0]).toMatchObject({ round: 2, verdictRound: 1 })
  expect(seenOf(old, []).verdicts.u).toBe('1:GO')
  expect(parseSnapshot('window.DASH = {nope', 0, 'p').note).toBe('units: snapshot unreadable')
})

// Issue 420: dashboard.sh gives a standing folder the stage of its lowercased name; the lanes are not units.
test('the standing lanes are never units: BUILDING 1, neither lane listed', () => {
  const snap = parseSnapshot(dash({ inFlight: [{ unit: 'u', stage: 'building' }, { unit: 'Fast-lane', stage: 'fast-lane' }, { unit: 'Research-lane', stage: 'research-lane' }] }), NOW, 'p')
  expect(snap.rows.map(r => r.unit)).toEqual(['u'])
  const lines = paneLines({ now: NOW, snap, merges: [], tests: [], notes: { merges: [], tests: [] } })
  expect(lines.some(l => /^BUILDING +1$/.test(l))).toBe(true)
  expect(lines.some(l => /lane/i.test(l))).toBe(false)
})

test("a plugin snapshot's project units, merge times and costs parse", () => {
  const text = 'window.DASH={"updatedAt":"2026-10-25T20:00:00Z","home":"p","projects":{"p":{"path":"/repo","units":{"inFlight":[{"unit":"u","stage":"building"}],"mergedSincePush":[],"finishedBuilds":[{"unit":"v","how":"merged","at":"2026-10-25T19:00:00Z","sha":"abc","cost":null}]}}}};'
  const s = parseSnapshot(text, Date.UTC(2026, 9, 25, 20, 1), 'p')
  expect(s.note).toBe(null)
  expect(s.rows.map(r => [r.unit, r.stage])).toEqual([['u', 'building']])
  expect(s.merged).toEqual(['v'])
  expect(s.mergedAt).toEqual([{ unit: 'v', at: Date.UTC(2026, 9, 25, 19) }])
  expect(s.chain).toBe(null)
  expect(s.finishedUsd).toEqual({})
  // A project with no upstream writes null lists and no cost total: they read as empty.
  const bare = parseSnapshot(dash({ inFlight: [], mergedSincePush: null, finishedBuilds: null }), NOW, 'p')
  expect([bare.merged, bare.finishedUsd]).toEqual([[], {}])
  expect(parseSnapshot(dash({ inFlight: [], finishedBuilds: [{ unit: 'v', cost: { total: { usd: 2.5 } } }] }), NOW, 'p').finishedUsd).toEqual({ v: 2.5 })
})

// r1 finding: a push takes a merge out of mergedSincePush; finishedBuilds keeps it, so today's merges and spend stay.
// Issue 390: an hour-old snapshot showed its rows as current; the pane names the data's age beside them.
test('a stale snapshot shows its age beside its rows', () => {
  const text = 'window.DASH={"updatedAt":"2026-10-26T14:00:00Z","projects":{"p":{"units":{"inFlight":[{"unit":"u","stage":"building"}]}}}};'
  const now = Date.UTC(2026, 9, 26, 15, 0, 0)
  const snap = parseSnapshot(text, now, 'p')
  expect(snap.staleMin).toBe(60)
  expect(snap.rows.map(r => r.stage)).toEqual(['building'])
  expect(paneLines({ now, snap, merges: [], tests: [], notes: { merges: [], tests: [] } }).some(l => l.includes('dashboard data is 60 min old'))).toBe(true)
})

test("a push keeps today's merged builds and their spend", () => {
  const now = Date.UTC(2026, 9, 25, 20)
  const done = { unit: 'merged-unit', how: 'merged', at: '2026-10-25T19:00:00Z', sha: 'abc', cost: { total: { usd: 12 } } }
  const seen = [false, true].map(pushed => {
    const snap = parseSnapshot(dash({ inFlight: [{ unit: 'still-building', stage: 'building' }], mergedSincePush: pushed ? [] : [done], finishedBuilds: [done] }), now, 'p')
    const s = { now, snap, merges: [], tests: [], notes: { merges: [], tests: [] } }
    return `${todayUsd(s)} ${paneLines(s).some(l => /^MERGED TODAY +1/.test(l))}`
  })
  expect(seen).toEqual(['12 true', '12 true'])
})

// Issue 421: the total is the dashboard's Cost today for the project, split by the folder each request ran in. A
// merged unit's lifetime cost (99 here) is not today's spend.
const dayOf = (today: object | null) => {
  const done = { unit: 'merged-unit', how: 'merged', at: '2026-10-25T14:00:00Z', cost: { total: { usd: 99 } } }
  const snap = parseSnapshot(dash({ inFlight: [{ unit: 'live-unit', stage: 'building', builder: { cost: { stages: [{ usd: 40 }] } } }], finishedBuilds: [done] }, today ? { limit: { today: { p: today } } } : {}), NOW, 'p')
  return { now: NOW, snap, merges: [], tests: [], notes: { merges: [], tests: [] } }
}
const byFolder = { 'merged-unit': 10, 'live-unit': 5, ':main': 8, 'Fast-lane': 4, ':other': 3 }
// The pane's money format; built here so no spend figure is written out in this public file (ci/leak-test.sh).
const d = (n: number) => '$' + n.toFixed(2)

test("today's total equals the dashboard's and splits by folder", () => {
  const s = dayOf({ spentUsd: 30, complete: true, byFolder })
  expect(todayUsd(s)).toBe(30)
  const parts = todaySplit(s)
  expect(parts.map(([, n]) => n)).toEqual([10, 5, 8, 4, 3])
  expect(parts.reduce((n, [, x]) => n + x, 0)).toBe(30)
  const lines = paneLines(s, 100)
  expect(lines[0]).toMatch(/^UNITS +today \$30\.00$/)
  expect(lines[1]).toBe(`  merged ${d(10)} · in flight ${d(5)} · main ${d(8)} · lanes ${d(4)} · other ${d(3)}`)
  // A part the folders do not name is still in the total: the rest is not attributed.
  expect(todaySplit(dayOf({ spentUsd: 30, complete: true, byFolder: { 'live-unit': 5 } }))).toEqual([['in flight', 5], ['other', 25]])
})

test('a partial day reads at least', () => {
  const s = dayOf({ spentUsd: 30, complete: false, byFolder })
  expect(paneLines(s, 100)[0]).toMatch(/^UNITS +today at least \$30\.00$/)
  expect(summaryLine(s)).toBe(`1 building · today at least ${d(30)}`)
})

test('with no dashboard day the total is the units\' own sum, marked units only', () => {
  // The old sum: the in-flight unit's 40 plus the merged unit's lifetime 99.
  const s = dayOf(null)
  expect(todayUsd(s)).toBe(139)
  expect(todaySplit(s)).toEqual([])
  const [head, mark] = paneLines(s, 100)
  expect(head).toMatch(/^UNITS +today /)
  expect(head.endsWith(` ${d(139)}`)).toBe(true)
  expect(mark).toBe('  units only')
})

// r2 finding: dashboard.sh writes a unit's cost to builder.cost once a Builder runs, and to plan.cost before that.
test("a planning unit's spend counts before the Builder starts", () => {
  const plan = { cost: { stages: [{ stage: 'planning', usd: 4 }] } }
  const snap = parseSnapshot(dash({ inFlight: [{ unit: 'u', stage: 'planning', builder: null, plan }] }), NOW, 'p')
  expect([snap.rows[0].costs.plan, snap.rows[0].usd]).toEqual([4, 4])
  expect(todayUsd({ now: NOW, snap, merges: [], tests: [], notes: { merges: [], tests: [] } })).toBe(4)
  // Once the Builder runs, its cost (which starts with the planning stage) is the one read, never both.
  const built = parseSnapshot(dash({ inFlight: [{ unit: 'u', stage: 'building', builder: { cost: { stages: [{ stage: 'planning', usd: 4 }, { stage: 'build', usd: 6 }] } }, plan }] }), NOW, 'p')
  expect(built.rows[0].costs.total).toBe(10)
})

// r7 finding: dashboard.sh counts every issue an evidence heading names, so `built` can hold an issue the brief does not
// list; counted whole, it outran `issues` and the bar's repeat() threw, taking the pane and /units down with it.
test("issues built count only the brief's issues, and the bar never overflows", () => {
  const lines = (builder: object) => {
    const snap = parseSnapshot(dash({ inFlight: [{ unit: 'u', stage: 'building', builder }] }), NOW, 'p')
    return paneLines({ now: NOW, snap, merges: [], tests: [], notes: { merges: [], tests: [] } }).join('\n')
  }
  expect(lines({ issues: [349], built: [349, 357] })).toContain('██████████  1 of 1 issues built')
  // An item with no number is its text in both lists; a repeat counts once.
  expect(lines({ issues: [349, 'Rule drift'], built: ['Rule drift', 357, 'Rule drift', 'other'] })).toContain('█████░░░░░  1 of 2 issues built')
})

test('a snapshot without this project, or with no unit list, draws nothing and says why', () => {
  const text = dash({ inFlight: [{ unit: 'u', stage: 'building' }] })
  expect(parseSnapshot(text, NOW, 'q')).toMatchObject({ note: 'units: this project is not in the dashboard snapshot', rows: [] })
  expect(parseSnapshot(dash({ inFlight: null }), NOW, 'p')).toMatchObject({ note: 'units: snapshot unreadable', rows: [] })
})

test("a plan's Closes line names its issues in the plugin's form and the host's", () => {
  expect(closesOf('Closes: issue 348, issue 349\n')).toEqual(['#348', '#349'])
  expect(closesOf('Closes: #12 #34\n')).toEqual(['#12', '#34'])
  expect(closesOf('Closes: issue 348\nCloses (only when G19 is built): issue 366\n')).toEqual(['#348'])
})

test('a merge log is read from its last ATTEMPT line, and a log with none has no attempt', () => {
  const log = 'ATTEMPT unit=u pid=7 started=1\nDONE unit=u merged=local\nATTEMPT unit=v pid=5 started=2\nATTEMPT unit=u pid=8 started=3\nSTEP 2 rebase: y\n'
  expect(newestAttempt(log, 'u')).toEqual({ text: 'ATTEMPT unit=u pid=8 started=3\nSTEP 2 rebase: y\n', pid: '8' })
  expect(newestAttempt(log, 'ux')).toBe(null)
  expect(newestAttempt('ATTEMPT unit=u pid=7 started=1\n', 'u')?.pid).toBe('7')
  expect(newestAttempt('STEP 1 preconditions: y\nDONE unit=u merged=local\n', 'u')).toBe(null)
})

// The merge log and the dashboard announce the same merge at different polls; whichever lands first speaks, once.
test('a merge seen by the live job and then the dashboard (or the reverse) toasts once', () => {
  const seen = (merged: string[], ended: string[]): Seen => ({ verdicts: {}, merged, ended })
  const said = (steps: Seen[]) => steps.slice(1).flatMap((s, i) => toasts(steps[i], s))
  expect(said([seen([], []), seen([], ['u']), seen(['u'], ['u'])])).toEqual(['u: merge finished'])
  expect(said([seen([], []), seen(['u'], []), seen(['u'], ['u'])])).toEqual(['u: merged'])
})

// A unit first seen after startup with its verdict already recorded is news; only the first poll is silent.
test('verdict toasts: initial, discovered, repeated, changed, delayed and after a reset', () => {
  const seen = (verdicts: Record<string, string>): Seen => ({ verdicts, merged: [], ended: [] })
  const a = seen({ u: '1:GO' })
  const b = seen({ u: '1:GO', w: '2:NO-GO' })
  const c = seen({ u: '3:GO', w: '2:NO-GO', x: '1:' })
  const d = seen({ ...c.verdicts, x: '1:GO' })
  const e = seen({ ...d.verdicts, w: '3:GO' })
  const f = seen({ ...e.verdicts, w: '4:NO-GO' })
  expect(toasts(null, a)).toEqual([])
  expect(toasts(a, a)).toEqual([])
  expect(toasts(a, b)).toEqual(['w: verdict 2 NO-GO'])
  expect(toasts(b, b)).toEqual([])
  expect(toasts(b, c)).toEqual(['u: verdict 3 GO'])
  expect(toasts(c, d)).toEqual(['x: verdict 1 GO'])
  expect(toasts(null, e)).toEqual([])
  expect(toasts(e, f)).toEqual(['w: verdict 4 NO-GO'])
})

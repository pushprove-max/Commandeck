import { expect, test } from 'claude-code/testing'
import { bandModel, closesOf, newestAttempt, paneLines, paneModel, parseMergeLog, parseSnapshot, parseTestLive, seatFromGit, seenOf, summaryLine, todaySplit, todayUsd, toasts } from './units-sources'
import type { Line, MergeView, Seen, State } from './units-sources'

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
  expect(lines[0]).toMatch(/^UNITS · 1 building +today \$30\.00$/)
  expect(lines[1]).toBe(`  merged ${d(10)} · in flight ${d(5)} · main ${d(8)} · lanes ${d(4)} · other ${d(3)}`)
  // A part the folders do not name is still in the total: the rest is not attributed.
  expect(todaySplit(dayOf({ spentUsd: 30, complete: true, byFolder: { 'live-unit': 5 } }))).toEqual([['in flight', 5], ['other', 25]])
})

test('a partial day reads at least', () => {
  const s = dayOf({ spentUsd: 30, complete: false, byFolder })
  expect(paneLines(s, 100)[0]).toMatch(/^UNITS · 1 building +today at least \$30\.00$/)
  // This snapshot names no decisions and its unit sits at its prompt, so trouble leads; the partial day still reads at least.
  expect(summaryLine(s)).toBe(`✗ decisions: not in the snapshot · ✗ live-unit at its prompt · ◐ 1 ✓ 1 · today at least ${d(30)}`)
})

test('with no dashboard day the total is the units\' own sum, marked units only', () => {
  // The old sum: the in-flight unit's 40 plus the merged unit's lifetime 99.
  const s = dayOf(null)
  expect(todayUsd(s)).toBe(139)
  expect(todaySplit(s)).toEqual([])
  const [head, mark] = paneLines(s, 100)
  expect(head).toMatch(/^UNITS · 1 building +today /)
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

// Host Part 1: the snapshot's own fields drawn in the pane, band and status line.
const T1 = Date.UTC(2026, 10, 1, 16, 0, 0)
const iso = (minAgo: number) => new Date(T1 - minAgo * 60_000).toISOString()
const RESET = T1 + (3 * 86400 + 4 * 3600 + 600) * 1000
const LIMIT = { usedPct: 58, resetsAt: new Date(RESET).toISOString(), today: { p: { spentUsd: 30, complete: true, byFolder: {} } } }
const u = (unit: string, extra: object = {}) => ({ unit, stage: 'building', agents: 'claude:working', ageSec: 360, stageSince: iso(4), builder: { cost: { stages: [{ stage: 'building', usd: 2 }] } }, ...extra })
const fin = (unit: string, minAgo: number) => ({ unit, how: 'merged', at: iso(minAgo), sha: `sha-${unit}`, cost: { total: { usd: 3 } } })
const ask = (id: string, minAgo: number | null) => ({ id, question: `Q ${id}?`, source: 'main', askedAt: minAgo === null ? undefined : iso(minAgo), answeredAt: null, answer: null })
const snapOf = (units: object = {}, project: object = {}, top: object = {}) =>
  `window.DASH = ${JSON.stringify({ updatedAt: iso(0), home: 'p', limit: LIMIT, ...top, projects: { p: { path: '/repo', units: { inFlight: [], mergedSincePush: [], finishedBuilds: [], ...units }, needsOwner: { decisions: [] }, ...project } } })};`
const st = (text: string, more: Partial<State> = {}): State => ({ now: T1, snap: parseSnapshot(text, T1, 'p'), merges: [], tests: [], notes: { merges: [], tests: [] }, ...more })
const txt = (l: Line) => l.map(x => x.t).join('')
const pane = (s: State, w: number) => paneModel(s, w).map(txt)
const refused: MergeView = { unit: 'mm', status: 'refused', m: parseMergeLog('FAILED step 1 proof: no GO\n'), elapsedSec: 0 }
// One snapshot holding every element: an ask blocking x, x and y working, z at its prompt, one planning, one merge today.
const busy = () => st(snapOf({
  inFlight: [u('x'), u('y', { builder: { cost: { stages: [{ stage: 'building', usd: 5 }] } } }), u('z', { agents: 'claude:done', builder: { cost: { stages: [{ usd: 9 }] } } }), u('p', { stage: 'planning', builder: null })],
  finishedBuilds: [fin('m', 30)],
}, { needsOwner: { decisions: [ask('plan-x', 30)] } }))

test('the header shows stage counts, spend and the 7-day gauge', () => {
  const s = busy()
  s.tests = [{ owner: 'u', kind: 'tests', p: { done: 1, failed: 0, firstFail: null }, total: 2, elapsedSec: 60 }]
  const [head, limit] = pane(s, 72)
  expect(head).toMatch(/^UNITS · 1 planning · 3 building · 1 waiting on owner +today \$30\.00$/)
  expect(limit).toMatch(/^7d ▰▰▰▰▰▰▱▱▱▱ 58% ↻ 3d 4h +tests 1 running$/)
})

test('waiting on the owner lists open decisions with age', () => {
  // Oldest first; an ask with no time comes last and carries no age.
  const s = st(snapOf({ inFlight: [u('x'), u('y')] }, { needsOwner: { decisions: [ask('b', 5), ask('a', 30), ask('no-time', null)] } }))
  const lines = pane(s, 72)
  const at = lines.findIndex(l => l.startsWith('WAITING ON OWNER'))
  expect(lines[at]).toBe('WAITING ON OWNER  3')
  expect(lines.slice(at + 1, lines.findIndex(l => l.startsWith('BUILDING'))).filter(l => /^│ (◆|  )/.test(l)).map(l => l.replace(/ +│$/, '').replace(/ {2,}/g, '  '))).toEqual([
    '│ ◆ a  30m', '│  Q a?', '│ ◆ b  5m', '│  Q b?', '│ ◆ no-time', '│  Q no-time?',
  ])
})

// holds' rule (scripts/decision.sh): the ledger has no unit field, so an id names a unit only as <unit>, plan-<unit> or
// review-stop-<unit>-r<n>, and only a unit in flight is blocked.
test('an ask whose id names a unit shows the unit it blocks', () => {
  const decisions = [ask('plan-gone', 40), ask('plan-y', 30), ask('review-stop-z-r2', 20), ask('x', 10), ask('q-x-note', 5)]
  const s = st(snapOf({ inFlight: [u('x'), u('y'), u('z')] }, { needsOwner: { decisions } }))
  expect(s.snap.asks.map(a => `${a.id}:${a.unit}`)).toEqual(['plan-gone:null', 'plan-y:y', 'review-stop-z-r2:z', 'x:x', 'q-x-note:null'])
  const lines = pane(s, 72)
  expect(lines.filter(l => l.includes('⏸ waits on owner'))).toHaveLength(3)
  expect(lines.filter(l => / · \w+ waits +│$/.test(l)).map(l => /· (\w+) waits/.exec(l)?.[1])).toEqual(['y', 'z', 'x'])
  // The band names the oldest ask; it names no unit when that ask's id names none.
  expect(txt(bandModel(s, 160)[0])).toContain('plan-gone 40m')
  expect(txt(bandModel(s, 160)[0])).not.toContain('blocks')
})

test('merged today reads finished builds, so a push does not empty it', () => {
  // Nothing is unpushed, yet today's merge stays; one from 30 hours back never counts.
  const s = st(snapOf({ mergedSincePush: [], finishedBuilds: [fin('m', 30), fin('gone', 60 * 30)] }))
  expect(pane(s, 72).filter(l => l.startsWith('✓ ') || l.startsWith('MERGED'))).toEqual([expect.stringMatching(/^MERGED TODAY  1 +\$3\.00$/), expect.stringMatching(/^✓ m /)])
  expect(s.snap.merged).toEqual(['m', 'gone'])
})

test('the band puts owner questions and the limit first, the busiest unit second', () => {
  const rows = bandModel(busy(), 160).map(txt)
  expect(rows).toHaveLength(3)
  expect(rows[0]).toMatch(/^◆ waiting on owner 1 · plan-x 30m · blocks x +7d ▰▰▰▰▰▰▱▱▱▱ 58% · today \$30\.00$/)
  // y is the working unit with the most spend; z spent more but sits at its prompt.
  expect(rows[1]).toMatch(/^◐ y Building  Plan ✓  Judges ✓  Build ◐  Review ○  Merge ○ · \$5\.00 · 4m$/)
  expect(rows[2]).toBe('◐ x Building 4m ⏸ owner   ○ z Building 4m ⚠   ◐ p Planning 4m   ✓ 1 merged today')
  expect(bandModel(st(snapOf()), 120).map(txt)).toEqual(['7d ▰▰▰▰▰▰▱▱▱▱ 58% · today ' + d(30)])
})

test('the status line leads with the worst state', () => {
  const s = busy()
  s.merges = [refused]
  expect(summaryLine(s)).toBe('✗ mm merge refused · ✗ z at its prompt 6m · ◆ 1 for owner · ◐ 1 ◐ 3 ✓ 1 · 58% · ' + d(30))
  // Without trouble the counts name their stage and the limit shows its reset.
  const calm = st(snapOf({ inFlight: [u('x'), u('p', { stage: 'planning', builder: null })], finishedBuilds: [fin('m', 30)] }, { needsOwner: { decisions: [ask('a', 30)] } }))
  expect(summaryLine(calm)).toBe('◆ 1 for owner · ◐ 1 planning · ◐ 1 building · ✓ 1 merged · 7d 58% ↻3d · today ' + d(30))
})

test('sections with nothing to show take no lines', () => {
  const s = st(snapOf({}, {}, { limit: undefined }))
  expect(pane(s, 56)).toEqual(['UNITS', '', 'CANNOT READ', '⚠ 7d limit: not in the snapshot'])
  expect([bandModel(s, 120), summaryLine(s)]).toEqual([[], undefined])
})

// Issue 581: the snapshot's seats.main.today and seats.relay.today ({usd, partial}) drawn under the 7-day gauge.
const seatsOf = (seats: unknown) => st(snapOf({}, { seats }))
const cost = (usd: unknown, partial?: boolean) => ({ today: { tokens: 1, usd, ...(partial === undefined ? {} : { partial }) } })

test('the header gives main and chief of staff each a line with today\'s cost', () => {
  const lines = pane(seatsOf({ main: cost(58.5, false), relay: cost(12.25, false) }), 72)
  expect(lines.slice(0, 4)).toEqual([expect.stringMatching(/^UNITS +today /), expect.stringMatching(/^7d /), `main ${d(58.5)} today`, `chief of staff ${d(12.25)} today`])
})

test('a figure with an unpriced call reads partial, never a bare dollar amount', () => {
  const lines = pane(seatsOf({ main: cost(58.5, true), relay: cost(12.25, false) }), 72)
  expect(lines[2]).toBe(`main ${d(58.5)} partial today`)
  expect(lines[3]).toBe(`chief of staff ${d(12.25)} today`)
})

test('a project with no chief of staff draws only the main line', () => {
  const s = seatsOf({ main: cost(1, false) })
  expect(pane(s, 72).filter(l => /today$/.test(l) && !l.startsWith('UNITS'))).toEqual([`main ${d(1)} today`])
  expect(s.snap.unread).toEqual([])
})

test('an absent or junk seat figure draws no line and the unread note names the junk one', () => {
  const lines = (seats: unknown) => pane(seatsOf(seats), 72).filter(l => /^(main|chief of staff) /.test(l))
  // Absent: no seats, null or a string, a null seat, no today. Nothing drawn and nothing said.
  for (const seats of [undefined, null, 'x', { main: null }, { main: {}, relay: { today: null } }]) {
    expect(lines(seats)).toEqual([])
    expect(seatsOf(seats).snap.unread.filter(n => /cost today/.test(n))).toEqual([])
  }
  // Junk: a figure that is not a non-negative number. The other seat's line stays.
  for (const usd of ['58', NaN, null, -1]) {
    const s = seatsOf({ main: cost(usd), relay: cost(2, false) })
    expect(lines({ main: cost(usd), relay: cost(2, false) })).toEqual([`chief of staff ${d(2)} today`])
    expect(s.snap.unread.filter(n => /cost today/.test(n))).toEqual([expect.stringMatching(/^main cost today: /)])
    // A figure gap is never a work-source problem: the band and status line stay clear of it.
    expect(bandModel(s, 160).map(txt).join('')).not.toContain('cost today')
    expect(pane(s, 72).join('\n')).toContain('⚠ main cost today: ')
  }
})

// Issue 582: CANNOT READ is the first section under the header, so a short pane never cuts it off.
test('the cannot-read section sits right under the header, above every section', () => {
  const s = busy()
  s.merges = [refused]
  s.notes.tests = ['tests: one table unreadable']
  const lines = pane(s, 72)
  const at = lines.indexOf('CANNOT READ')
  const first = (re: RegExp) => lines.findIndex(l => re.test(l))
  expect(at).toBeGreaterThan(-1)
  for (const title of [/^■ plan/, /^WAITING ON OWNER/, /^BUILDING/, /^MERGING/, /^MERGED TODAY/]) expect(at).toBeLessThan(first(title))
  expect(lines.slice(at + 1, at + 2)).toEqual(['⚠ tests: one table unreadable'])
})

test('an unreadable source is still in view when a short pane cuts the lower sections', () => {
  const s = busy()
  s.notes.merges = ['merges: log unreadable']
  expect(pane(s, 72).slice(0, 8)).toContain('⚠ merges: log unreadable')
})

// Issue 583: the page's clock (dashboard/app.js hm) is 12-hour; so is the merged-today row.
const mergedAt = (h: number, m: number) => {
  const at = new Date(2026, 10, 1, h, m).toISOString()
  const s = st(snapOf({ finishedBuilds: [{ unit: 'm', how: 'merged', at, cost: { total: { usd: 3 } } }] }), { now: new Date(2026, 10, 1, 23, 59).getTime() })
  return pane(s, 72).find(l => l.startsWith('✓ m'))
}

test('a time after noon reads h:mm PM in the merged-today row', () => {
  expect(mergedAt(15, 5)).toMatch(/^✓ m +3:05 PM +\$3\.00$/)
  expect(mergedAt(23, 59)).toMatch(/ 11:59 PM /)
})

test('midnight and noon read 12:07 AM and 12:00 PM', () => {
  expect(mergedAt(0, 7)).toMatch(/ 12:07 AM /)
  expect(mergedAt(12, 0)).toMatch(/ 12:00 PM /)
  expect(mergedAt(9, 4)).toMatch(/ 9:04 AM /)
})

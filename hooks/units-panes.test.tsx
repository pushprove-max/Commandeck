import { expect, test } from 'claude-code/testing'
import { WS, SCR, NOW, DATA, STATE, unit, snap, world, start, units, draw, quiet, state, DONE, band } from './units-world'
import { bandModel, paneModel, parseSnapshot } from './units-sources'
import type { Line, State } from './units-sources'

// The views over a snapshot: layout, toasts, placeholders and the order polls publish in.

// A poll that stalls must not publish after a newer one: its older snapshot would undo the newer state and repeat toasts.
test('overlapping polls publish in the order they started', async ($, on) => {
  const w = world(on, 'main', { [DATA]: snap([unit('u', { round: 1 }, { verdict: 'VERDICT: GO', verdictRound: 1 })]) })
  await start($, 'main')
  const set = (round: number, verdict: string, at: number, ageSec = 0) => w.files.set(DATA, { text: snap([unit('u', { round, ageSec }, { verdict, verdictRound: round })]), at })
  let release = () => {}
  let entered = () => {}
  const inRead = new Promise<void>(r => (entered = r))
  const gate = new Promise<void>(r => (release = r))
  set(1, 'VERDICT: GO', NOW + 1, 1)
  w.beforeRead = async path => { if (path === DATA) { w.beforeRead = undefined; entered(); await gate } }
  const slow = units($)
  await inRead
  set(2, 'VERDICT: NO-GO', NOW + 2)
  const fast = units($)
  await Promise.race([fast, w.clock.advance(1)])
  release()
  await Promise.all([slow, fast])
  expect((await draw($, 'AbovePrompt')).join('')).toContain('◐ u Building r2')
  expect(await units($)).toContain('r2 NO-GO')
  expect(w.toasts).toEqual(['u: verdict 2 NO-GO'])
})

test('a Builder pane at its prompt shows red, a working one does not', async ($, on) => {
  world(on, 'main', { [DATA]: snap([unit('idle', { agents: 'claude:done' }), unit('busy')]) })
  await start($, 'main')
  const text = await units($)
  expect(text).toMatch(/○ idle · model unknown +Building │\n.*\n.* +\$1\.00 │\n│   ⚠ at its prompt/)
  expect(text.match(/⚠ at its prompt/g)).toHaveLength(1)
})

// The approved layout: a step row per unit, the issue bar, the review result, costs right-aligned with a per-stage
// split, today's spend, and no line that says "none" or "unknown".
test('the pane shows steps, issues, review, costs and today\'s merges, and nothing unknown', async ($, on) => {
  const at = new Date(NOW - 600_000).toISOString()
  const stages = [{ stage: 'planning', usd: 1 }, { stage: 'building', usd: 2 }, { stage: 'review', usd: 0.5 }, { stage: 'fixing', usd: 0.25 }]
  const w = world(on, 'main', {
    [DATA]: snap([
      unit('b', { round: 2, stage: 'fixing' }, { issues: [1, 2, 3, 4, 5, 6], built: [1, 2, 3, 4], verdict: 'VERDICT: NO-GO', verdictRound: 1, findings: { P1: 0, P2: 2, P3: 0 }, cost: { stages }, startedAt: new Date(NOW - 2_880_000).toISOString() }),
      unit('p-2026-10-25', { stage: 'planning' }, null),
    ], { finishedBuilds: [{ unit: 'm', at, cost: { total: { usd: 19.21 } } }, { unit: 'old', at: '2026-10-20T10:00:00Z' }] }),
    [`${WS}/p-2026-10-25/.claude/plans/p-2026-10-25.md`]: '# Plan\n\nCloses: issue 12, issue 34\n',
    [`${SCR}/seat-p-2026-10-25-plan-author.txt`]: 'role=plan-author\nphase=dispatched\nverdict=PLAN-DONE\n',
    [`${SCR}/seat-p-2026-10-25-plan-judge-sol.txt`]: 'role=plan-judge\nphase=dispatched\n',
  })
  w.files.set(`${WS}/p-2026-10-25/.git`, { text: 'gitdir: x', at: NOW - 720_000 })
  await start($, 'main')
  const lines = (await units($)).split('\n')
  const at_ = (s: string) => lines.findIndex(l => l.includes(s))
  const b = at_('◐ b')
  const inner = (from: number, n: number) => lines.slice(from, from + n).map(l => l.replace(/ +│$/, ''))
  expect(lines[0]).toMatch(/^UNITS · 1 planning · 1 fixing +today \$22\.96$/)
  expect(lines[b]).toMatch(/^│ ◐ b · model unknown +Fixing r2 · 48m │$/)
  expect(inner(b + 1, 4)).toEqual([
    '│   Plan ✓  Judges ✓  Build ✓  Review ◐  Merge ○',
    '│   ██████████  6 of 6 issues built',
    expect.stringMatching(/^│   r1 NO-GO · 2 P2 +\$3\.75$/),
    '│   plan $1.00 · build $2.00 · review $0.50 · fix $0.25',
  ])
  const p = at_('◐ p')
  expect(lines[p]).toMatch(/^│ ◐ p · model unknown +Planning · 12m │$/)
  expect(inner(p + 1, 2)).toEqual(['│   Plan ✓  Judges ◐  Build ○  Review ○  Merge ○', '│   #12 #34'])
  expect(lines[at_('MERGED TODAY')]).toMatch(/^MERGED TODAY  1 +\$19\.21$/)
  expect(lines[at_('✓ m')]).toMatch(/^✓ m +\d\d?:\d\d [AP]M +\$19\.21$/)
  // `· model unknown` is the card's text for a unit with no live seat; nothing else may say unknown.
  expect(lines.join('\n').replace(/ · model unknown/g, '')).not.toMatch(/old|none|unknown|nothing|git -C|\/\?|MERGING/)
  expect(lines.every(l => l.length <= 100)).toBe(true)
})


// Builders write evidence by cut, not by issue, so a finished build that names no issue in its evidence still built them all.
test('issues built count the evidence while building and every issue once the build is done', async ($, on) => {
  world(on, 'main', { [DATA]: snap([
    unit('a', { stage: 'building' }, { issues: [1, 2, 3, 4], built: [1] }),
    unit('f', { round: 1, stage: 'fixing' }, { issues: [1, 2], built: [] }),
    unit('r', { round: 2, stage: 'review' }, { issues: [1, 2, 3], built: [] }),
  ]) })
  await start($, 'main')
  const lines = (await units($)).split('\n')
  const out = lines.join('\n')
  expect(out).toContain('1 of 4 issues built')
  expect(out).toContain('2 of 2 issues built')
  // The stage dashboard.sh writes for a review round is 'review'.
  const r = lines.findIndex(l => l.startsWith('│ ◐ r '))
  expect(lines[r]).toMatch(/Review r2 │$/)
  expect(lines.slice(r + 1, r + 3).map(l => l.replace(/ +│$/, ''))).toEqual(['│   Plan ✓  Judges ✓  Build ✓  Review ◐  Merge ○', '│   ██████████  3 of 3 issues built'])
})


test('a unit with an old worktree shows no stall mark and raises no toast', async ($, on) => {
  const w = world(on, 'main', { [DATA]: snap([unit('u', { ageSec: 999_999 })]) })
  w.files.set(`${WS}/u/.git`, { text: 'gitdir: x', at: NOW - 30 * 86_400_000 })
  await start($, 'main')
  await w.clock.advance(5000)
  expect(await units($)).not.toMatch(/stall|stuck|idle for/i)
  expect(await band($)).not.toMatch(/stall|stuck|idle for/i)
  expect(w.toasts).toEqual([])
})


test('toasts fire once per event, never on the first poll', async ($, on) => {
  const w = world(on, 'main', { [DATA]: snap([unit('u', { round: 1 }, { verdict: 'GO', verdictRound: 1 })]) })
  await start($, 'main')
  expect(w.toasts).toEqual([])
  w.files.set(DATA, { text: snap([unit('u', { round: 2 }, { verdict: 'NO-GO', verdictRound: 2 }), unit('v')], { finishedBuilds: [{ unit: 'm' }] }), at: NOW + 1 })
  await w.clock.advance(5000)
  expect(w.toasts.sort()).toEqual(['m: merged', 'u: verdict 2 NO-GO'])
  await w.clock.advance(5000)
  expect(w.toasts).toHaveLength(2)
})

test('no live units: no band row, no pane, no status line', quiet, async ($, on) => {
  const w = world(on, 'main', { [DATA]: snap([unit('Chief-of-Staff', { stage: 'chief-of-staff' }, null)]) })
  await start($, 'main')
  expect(await units($)).toBe('No live units.')
  expect(await draw($, 'AbovePrompt')).toEqual(['engine'])
  expect(await draw($, 'Pane')).toEqual(['No live units.'])
  expect(w.status.at(-1)).toBe(undefined)
  expect(w.opened).toEqual([])
})

// Issue 420: the two standing lanes beside the relay are no live units either.
test('only lanes and the relay: no live units', quiet, async ($, on) => {
  world(on, 'main', { [DATA]: snap([unit('Chief-of-Staff', { stage: 'chief-of-staff' }, null), unit('Fast-lane', { stage: 'fast-lane' }, null), unit('Research-lane', { stage: 'research-lane' }, null)]) })
  await start($, 'main')
  expect(await units($)).toBe('No live units.')
})

// r1 finding: the pane opened from config alone and stayed open once the last unit finished.
test('the pane opens when a unit goes live and closes when the last one finishes', async ($, on) => {
  const w = world(on, 'main', { [DATA]: snap([]) })
  await start($, 'main')
  expect(w.opened).toEqual([])
  w.files.set(DATA, { text: snap([unit('u')]), at: NOW + 1 })
  await w.clock.advance(5000)
  expect(w.opened).toEqual(['units'])
  w.files.set(DATA, { text: snap([]), at: NOW + 2 })
  await w.clock.advance(5000)
  expect(w.opened).toEqual([])
})

test('a missing snapshot shows its placeholder', async ($, on) => {
  world(on, 'main', {})
  await start($, 'main')
  expect(await units($)).toBe('UNITS\n\nCANNOT READ\n⚠ units: no dashboard snapshot (scripts/dashboard.sh --install)')
})

test('a missing, broken or oversize snapshot or log shows its placeholder', async ($, on) => {
  const w = world(on, 'main', { [DATA]: 'window.DASH = {oops', [`${SCR}/merge-a.log`]: 'x'.repeat(8_100_000), [STATE]: state(8, 'merge') })
  w.live.add(8)
  await start($, 'main')
  const text = await units($)
  expect(text).toContain('units: snapshot unreadable')
  expect(text).toContain('merge a: log too big (8 MB)')
  expect(text).toContain('◐ u  merge')
  w.files.set(DATA, { text: 'x'.repeat(4_100_000), at: NOW + 1 })
  await w.clock.advance(5000)
  expect(await units($)).toContain('units: snapshot too big')
})

// The snapshot's fields drawn as cards: stage colour, the live seat's model and effort, the working mark (host Part 1).
const T0 = Date.UTC(2026, 10, 1, 16, 0, 0)
const iso = (minAgo: number) => new Date(T0 - minAgo * 60_000).toISOString()
const card = (unit: string, extra: object = {}) => ({ unit, stage: 'building', agents: 'claude:working', ageSec: 360, stageSince: iso(4), builder: { cost: { stages: [{ stage: 'building', usd: 2 }] } }, ...extra })
const view = (inFlight: object[], project: object = {}, top: object = {}) =>
  `window.DASH = ${JSON.stringify({ updatedAt: iso(0), home: 'p', ...top, projects: { p: { path: '/repo', units: { inFlight, finishedBuilds: [] }, needsOwner: { decisions: [] }, ...project } } })};`
const stateOf = (text: string): State => ({ now: T0, snap: parseSnapshot(text, T0, 'p'), merges: [], tests: [], notes: { merges: [], tests: [] } })
const txt = (l: Line) => l.map(x => x.t).join('')

test('a unit card shows stage colour, model, effort and working mark', () => {
  const s = stateOf(view([
    card('x', { seatRole: 'builder', seats: [{ role: 'builder', model: 'claude-opus-5-5', effort: 'medium' }] }),
    card('p', { stage: 'planning', agents: '', builder: null }),
    card('r', { stage: 'review', seatRole: 'reviewer', seats: [{ role: 'reviewer', model: 'gpt-6.1-sol', effort: 'high' }] }),
  ]))
  const m = paneModel(s, 60)
  const x = m.findIndex(l => txt(l).includes(' x · '))
  // The frame, the card's first row and its right border take the stage colour; a planning unit is another colour.
  expect([m[x - 1][0].c, m[x][0].c, m[x].at(-1)?.c]).toEqual(['suggestion', 'suggestion', 'suggestion'])
  expect(txt(m[x])).toMatch(/^│ ◐ x · Opus 5\.5 · medium +Building · 4m │$/)
  const p = m.findIndex(l => txt(l).includes(' p · '))
  expect([m[p][0].c, txt(m[p]).slice(0, 4)]).toEqual(['planMode', '│ ○ '])
  // A unit with no live seat says so, dim, and a Codex seat's model is shown as recorded.
  const dim = m[p].find(seg => seg.t.includes('model unknown'))
  expect([txt(m[p]).includes('○ p · model unknown'), dim?.d]).toEqual([true, true])
  expect(txt(m.find(l => txt(l).includes(' r · '))!)).toContain('◐ r · gpt-6.1-sol · high ')
})

test('a missing or junk field joins the unread note naming it', () => {
  const junk = stateOf(view([card('x', { stageSince: 'junk' })], { needsOwner: { decisions: [{ id: 'q', question: 'one\n"two"' }] } }, { limit: { usedPct: '58', resetsAt: 'x' } }))
  expect([junk.snap.limit, junk.snap.asks[0].askedAt, junk.snap.asks[0].question, junk.snap.rows[0].stageSince]).toEqual([null, null, 'one "two"', null])
  expect(junk.snap.unread).toEqual(['7d limit: unreadable'])
  const shown = [...paneModel(junk, 72).map(txt), ...bandModel(junk, 120).map(txt)].join('\n')
  expect(shown).toContain('CANNOT READ\n⚠ 7d limit: unreadable')
  expect(shown).not.toMatch(/NaN|undefined|null/)
  const unread = (project: object, top: object = {}) => parseSnapshot(view([], project, top), T0, 'p').unread
  expect(unread({ needsOwner: undefined })).toEqual(['7d limit: not in the snapshot', 'decisions: not in the snapshot'])
  expect(unread({ needsOwner: { decisions: null }, sources: { decisions: { error: 'ledger malformed' } } })).toContain('decisions: ledger malformed')
  // A project that never kept a ledger has nothing waiting: that is no problem to name.
  expect(unread({ needsOwner: { decisions: null }, sources: { decisions: { error: 'no ledger at /r/decisions.jsonl' } } })).toEqual(['7d limit: not in the snapshot'])
  expect(unread({ units: { inFlight: [], finishedBuilds: 'x' } })).toContain('finished builds: unreadable')
  expect(parseSnapshot(view([], {}, { updatedAt: 'nope' }), T0, 'p').unread).toContain('updated at: unreadable')
})

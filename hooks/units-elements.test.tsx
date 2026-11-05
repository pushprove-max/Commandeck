import { expect, test } from 'claude-code/testing'
import { DATA, NOW, unit, world, start, units } from './units-world'
import { bandModel, paneModel, parseSnapshot, summaryLine } from './units-sources'
import type { Line, State } from './units-sources'
import * as E from './units-elements'

// #555: the units pane, band and status line elements. Each element is a pure function over the parsed snapshot, so
// it is drawn here at narrow and wide widths; the keys and the no-write rule run through the engine.

const iso = (ms: number) => new Date(ms).toISOString()
const dash = (inFlight: object[], units: object = {}, project: object = {}, top: object = {}) =>
  `window.DASH = ${JSON.stringify({ updatedAt: '2026-10-25T15:04:30Z', home: 'p', ...top, projects: { p: { path: '/repo', units: { inFlight, mergedSincePush: [], finishedBuilds: [], ...units }, needsOwner: { decisions: [] }, ...project } } })};`
const stateOf = (text: string, extra: object = {}): State => ({ now: NOW, snap: parseSnapshot(text, NOW, 'p'), merges: [], tests: [], notes: { merges: [], tests: [] }, ...extra })
const rowOf = (builder: object = {}, extra: object = {}) => stateOf(dash([unit('u', extra, builder)])).snap.rows[0]
const text = (ls: Line[]) => ls.map(E.plain).join('\n')
const colours = (ls: Line[], t: string) => ls.flat().filter(x => x.t.includes(t)).map(x => x.c)
const MIDNIGHT = new Date(NOW).setHours(0, 0, 0, 0)

test('header counts, cost, limit at both widths', () => {
  const top = { limit: { usedPct: 40, resetsAt: '2026-10-27T15:05:00Z', today: { p: { spentUsd: 12.5, complete: true, byFolder: {} } } } }
  const s = stateOf(dash([unit('a'), unit('b', { stage: 'review' })], {}, {}, top))
  for (const w of [40, 100]) {
    const lines = paneModel(s, w).map(E.plain)
    expect(lines[0]).toMatch(/^UNITS · 1 building/)
    expect(lines[0]).toContain('$12.50')
    expect(lines[1]).toMatch(/7d .* 40% ↻ 2d 0h/)
    expect(lines.every(l => E.cols(l) <= w)).toBe(true)
  }
})

test('waiting section amber first at both widths', () => {
  const s = stateOf(dash([unit('u')], {}, { needsOwner: { decisions: [{ id: 'plan-u', question: 'Ship it?', askedAt: iso(NOW - 3600_000) }] } }))
  for (const w of [40, 100]) {
    const out = paneModel(s, w)
    const lines = out.map(E.plain)
    const head = lines.findIndex(l => l.startsWith('WAITING ON OWNER'))
    expect(head).toBeGreaterThan(-1)
    expect(out[head][0].c).toBe(E.C.max)
    expect(lines.findIndex(l => l.includes('◆ plan-u'))).toBeLessThan(lines.findIndex(l => l.startsWith('BUILDING')))
    expect(out[head + 1][0].c).toBe(E.C.max)
  }
})

test('card shows model, effort, working mark', () => {
  const s = stateOf(dash([unit('u', { seatRole: 'builder', seats: [{ role: 'builder', model: 'claude-opus-4-7', effort: 'high' }] })]))
  const card = E.cardModel(s.snap.rows[0], s, 60, false, 1)
  expect(E.plain(card[1])).toContain('Opus 4.7 · high')
  expect(E.plain(card[1])).toContain('◓')
  // mini: one line per unit, no card frame
  const mini = paneModel(s, 40, 1).map(E.plain)
  expect(mini.some(l => l.includes('◓') && l.includes('u'))).toBe(true)
  expect(mini.join('\n')).not.toContain('╭')
})

test('context gauge turns red past restart line', () => {
  const under = E.ctxGauge(rowOf({ context: 310000, clearLine: 500000, compactions: 2 }), 60)
  expect(text(under)).toContain('62%')
  expect(text(under)).toContain('· 2 compactions')
  expect(colours(under, '▰')).not.toContain(E.C.bad)
  const past = E.ctxGauge(rowOf({ context: 510000, clearLine: 500000 }), 60)
  expect(colours(past, '▰')).toContain(E.C.bad)
  expect(text(E.ctxGauge(rowOf({ context: null, clearLine: 500000 }), 60))).toBe('context: not read')
  expect(E.ctxGauge(rowOf({}), 60)).toEqual([])
})

// pass 1: dashboard.sh writes clearLine as a JSON string (`--arg l`); read as a number only, every live Builder lost
// its line, so the gauge showed raw tokens and never turned red.
test('collector string clearLine keeps the restart line', () => {
  const past = rowOf({ context: 510000, clearLine: '500000' })
  expect(past.context).toEqual({ tokens: 510000, line: 500000 })
  expect(colours(E.ctxGauge(past, 60), '▰')).toContain(E.C.bad)
  expect(rowOf({ context: 510000, clearLine: '5e5' }).context).toEqual({ tokens: 510000, line: null })
})

test('round dots red for NO-GO', () => {
  const row = { ...rowOf({ verdicts: { 1: 'VERDICT: NO-GO', 2: 'VERDICT: GO' } }), judgeRounds: ['NO-GO', 'GO'] as ('GO' | 'NO-GO' | null)[] }
  const dots = E.roundDots(row)
  expect(dots.flat().filter(x => x.t === '●').map(x => x.c)).toEqual([E.C.bad, E.C.ok, E.C.bad, E.C.ok])
  const open = E.roundDots({ ...row, rounds: [...row.rounds!, null] })
  expect(open.flat().find(x => x.t === '○')?.c).toBe(E.C.dim)
  // the card's own verdict is not a round: with no rounds and no judge rounds nothing is drawn
  expect(E.roundDots({ ...rowOf({ verdict: 'VERDICT: GO' }), rounds: [], judgeRounds: [] })).toEqual([])
})

test('gate strip red refusal amber prompt', () => {
  const items = [{ timestamp: iso(NOW - 60_000), hook: 'bash-guard' }, { timestamp: iso(NOW - 120_000), hook: 'edit-guard' }]
  const s = stateOf(dash([unit('idle', { agents: 'claude:done' })], {}, { guardBlocks: { blocks: 2, items } }))
  const strip = E.gateStrip(s.snap, s.snap.rows)
  expect(strip).toHaveLength(1)
  expect(strip[0].find(x => x.t.includes('bash-guard'))?.c).toBe(E.C.bad)
  expect(strip[0].find(x => x.t.includes('idle'))?.c).toBe(E.C.max)
  expect(text(paneModel(s, 80))).toContain('GATES')
  const none = stateOf(dash([unit('u')], {}, { guardBlocks: null }))
  expect(text(E.gateStrip(none.snap, none.snap.rows))).toBe('gates: hook fire log not read')
})

test('receipt shows step, running tool, edits not recorded', () => {
  const tools = [{ tool: 'Edit', ts: iso(NOW - 90_000), running: false }, { tool: 'Bash', ts: iso(NOW - 30_000), running: true }]
  const steps = [{ kind: 'codex', pass: 'a', round: 1, start: iso(NOW - 600_000), end: iso(NOW - 300_000), rc: 1 }]
  const out = text(E.receiptLine(rowOf({ tools, steps })))
  expect(out).toContain('5m')
  expect(out).toContain('running Bash · command not recorded')
  expect(out).toContain('edits not recorded')
  expect(out).toContain('errors 1')
  expect(out).toContain('cost added not recorded')
})

test('timeline lane per unit on shared clock', () => {
  const hist = (from: number) => [{ stage: 'building', from: iso(from), to: iso(NOW - 3600_000) }, { stage: 'review', from: iso(NOW - 3600_000), to: null }]
  const s = stateOf(dash([unit('a', {}, { stageHistory: hist(MIDNIGHT) }), unit('b', {}, { stageHistory: hist(NOW - 4000_000) })]))
  const lanes = E.timelineLanes(s, 80)
  expect(lanes).toHaveLength(3)
  expect(E.plain(lanes[0])).toContain(E.clockOf(NOW))
  expect(lanes.every(l => E.cols(E.plain(l)) === 80)).toBe(true)
  expect(colours([lanes[1]], '█')).toEqual(expect.arrayContaining([E.stageColor('building'), E.stageColor('review')]))
  // b started late on the same clock: its early cells are empty, a's are not
  expect(E.plain(lanes[2])).toContain('·')
  expect(E.plain(lanes[1])).not.toContain('·')
})

test('merged today says deployed or pushed', () => {
  const at = iso(NOW - 3600_000)
  const s = stateOf(dash([], { finishedBuilds: [{ unit: 'a', at }, { unit: 'b', at }], mergedSincePush: [{ unit: 'b', at }] }))
  const merged = s.snap.mergedAt
  expect(text(E.whereLine(merged, s.snap))).toBe('pushed a · merged here b')
  expect(text(paneModel(s, 80))).toMatch(/MERGED TODAY[\s\S]*pushed a · merged here b/)
  const bad = stateOf(dash([], { finishedBuilds: [{ unit: 'a', at }], mergedSincePush: null }))
  expect(text(E.whereLine(bad.snap.mergedAt, bad.snap))).toBe('push state not read')
  expect(bad.snap.unread).toContain('unpushed: unreadable')
})

test('unit log shows clock times', () => {
  const events = Array.from({ length: 7 }, (_, i) => ({ at: NOW - (7 - i) * 60_000, unit: 'u', event: `e${i}` }))
  const s = stateOf(dash([unit('u')]), { events })
  const log = E.eventLog(s, 80).map(E.plain)
  expect(log).toHaveLength(5)
  expect(log[4]).toContain(E.clockOf(events[6].at))
  expect(log[4]).toMatch(/u .*e6/)
  expect(log.join('\n')).not.toContain('e1')
  expect(text(E.eventLog({ ...s, events: null }, 80))).toBe('unit log: not read (no unit-events file)')
})

test("keys expand a unit's last tool calls", async ($, on) => {
  const tools = [{ tool: 'Grep', ts: iso(NOW - 90_000), running: false }, { tool: 'Edit', ts: iso(NOW - 60_000), running: false }, { tool: 'Bash', ts: iso(NOW - 30_000), running: true }]
  world(on, 'main', { [DATA]: dash([unit('u', {}, { tools }), unit('v')]) })
  await start($, 'main')
  const ui = await $.ui.mount({ plugin: 'commandeck', surface: 'terminal', component: 'Pane', requestId: 'units', props: { title: 'Units', isFocused: false, bodyColumns: 100, placement: 'dock' } })
  const read = async () => ((await ui.findAll({ type: 'Text' })) as { text: string }[]).map(t => t.text)
  const labels = ((await ui.findAll({ type: 'Button' })) as { text?: string; label?: string }[]).map(b => b.text ?? b.label)
  expect(labels.join('|')).toMatch(/\[1\] u/)
  expect(labels.join('|')).toMatch(/\[d\].*\[t\].*\[l\]/)
  expect((await read()).join('')).not.toContain('Grep')
  await ui.press({ key: 'unit-1' })
  const open = (await read()).join('')
  expect(open).toContain('Grep')
  expect(open).toContain('Bash')
  await ui.press({ key: 'focus-l' })
  await ui.unmount()
})

test('band busiest row carries context and cost', () => {
  const mk = (tokens: number) => stateOf(dash([unit('u', { agents: 'claude:working' }, { context: tokens, clearLine: 500000, cost: { stages: [{ usd: 3 }] } }), unit('v', { agents: 'claude:done' })], {}, { needsOwner: { decisions: [{ id: 'plan-v', question: 'q', askedAt: iso(NOW - 60_000) }] } }))
  const calm = bandModel(mk(310000), 120)
  expect(calm).toHaveLength(3)
  expect(E.plain(calm[0])).toContain('waiting on owner')
  expect(E.plain(calm[1])).toContain('ctx 62%')
  expect(E.plain(calm[1])).toContain('$3.00')
  expect(colours([calm[1]], 'ctx')).not.toContain(E.C.bad)
  expect(colours([bandModel(mk(510000), 120)[1]], 'ctx')).toContain(E.C.bad)
  // mini keeps row 1 and row 2, cut to the width
  const mini = bandModel(mk(310000), 40)
  expect(mini).toHaveLength(2)
  expect(mini.every(l => E.cols(E.plain(l)) <= 40)).toBe(true)
})

test('status line leads with worst state', () => {
  const ask = { needsOwner: { decisions: [{ id: 'plan-u', question: 'q', askedAt: iso(NOW - 60_000) }] } }
  const prompt = stateOf(dash([unit('u', { agents: 'claude:done' })], {}, ask))
  expect(summaryLine(prompt)!.startsWith('✗ u at its prompt')).toBe(true)
  expect(summaryLine(prompt)!.indexOf('✗')).toBeLessThan(summaryLine(prompt)!.indexOf('◆'))
  expect(summaryLine(stateOf(dash([unit('u')], {}, ask)))!.startsWith('◆ 1 for owner')).toBe(true)
})

test('layout is mini, compact or wide by width', () => {
  expect([47, 48, 79, 80].map(E.layoutOf)).toEqual(['mini', 'compact', 'compact', 'wide'])
  const hist = [{ stage: 'building', from: iso(MIDNIGHT), to: null }]
  const stages = [{ stage: 'planning', usd: 1 }, { stage: 'building', usd: 2 }]
  const s = stateOf(dash([unit('u', {}, { stageHistory: hist, cost: { stages } })]))
  const at = (w: number) => text(paneModel(s, w))
  expect(at(100)).toContain('TIMELINE')
  expect(at(100)).toContain('plan $1.00 · build $2.00')
  expect(at(60)).not.toContain('TIMELINE')
  expect(at(60)).not.toContain('plan $1.00 · build $2.00')
  expect(at(60)).toContain('╭')
  expect(at(40)).not.toContain('╭')
})

test('unreadable element shows placeholder naming it', () => {
  const s = stateOf(dash([unit('u', {}, { context: null }), unit('w')], {}, { guardBlocks: null, seats: { main: { context: null, line: null }, relay: { context: 5000, line: null } } }), { events: null })
  const out = text(paneModel(s, 100))
  expect(out).toContain('context: not read')
  expect(out).toContain('gates: hook fire log not read')
  expect(out).toContain('unit log: not read (no unit-events file)')
  expect(out).toContain('main context: not read')
  expect(out).not.toContain('chief of staff context: not read')
  // junk is named under CANNOT READ, a missing key is no read at all
  const junk = stateOf(dash([unit('u', {}, { context: 'lots' })]))
  expect(junk.snap.unread).toContain('context u: unreadable')
  expect(text(paneModel(junk, 100))).toMatch(/CANNOT READ\n(⚠ .*\n)*⚠ context u: unreadable/)
})

test('views write no file', async ($, on) => {
  const tools = [{ tool: 'Bash', ts: iso(NOW - 30_000), running: true }]
  const w = world(on, 'main', { [DATA]: dash([unit('u', {}, { tools, context: 1, clearLine: 2 })], {}, { guardBlocks: { blocks: 0, items: [] } }) })
  await start($, 'main')
  await units($)
  const ui = await $.ui.mount({ plugin: 'commandeck', surface: 'terminal', component: 'Pane', requestId: 'units', props: { title: 'Units', isFocused: false, bodyColumns: 100, placement: 'dock' } })
  await ui.press({ key: 'unit-1' })
  await ui.unmount()
  expect(w.writes).toEqual([])
})

test('empty sections take no space', () => {
  const s = stateOf(dash([unit('u')]))
  const out = paneModel(s, 100).map(E.plain)
  for (const head of ['GATES', 'SEATS', 'TIMELINE', 'UNIT LOG', 'WAITING', 'MERGING', 'TESTS', 'MERGED TODAY']) expect(out.some(l => l.startsWith(head))).toBe(false)
  expect(out.some((l, i) => l === '' && out[i + 1] === '')).toBe(false)
  const r = s.snap.rows[0]
  expect([E.ctxGauge(r, 80), E.roundDots(r), E.receiptLine(r), E.gateStrip(s.snap, []), E.timelineLanes(s, 80), E.whereLine(s.snap.mergedAt, s.snap), E.eventLog(s, 80)]).toEqual([[], [], [], [], [], [], []])
})

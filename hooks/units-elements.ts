// The drawn elements of the units views: theme colours, widths, the card frame and each section's lines.
// Only types come from units-sources.ts (`import type`), so the two modules have no runtime cycle.
import type { Line, Merged, Row, Seg, State } from './units-sources'

// Claude Code theme keys, never raw colours, so a light or colour-blind theme recolours every view.
export const C = { plan: 'planMode', build: 'suggestion', review: 'autoAccept', max: 'warning', ok: 'success', bad: 'error', cost: 'claude', head: 'permission', dim: 'inactive', name: 'text' } as const
const STAGE_C: Record<string, string> = { planning: C.plan, building: C.build, fixing: C.build, review: C.review, merging: C.ok }
export const stageColor = (stage: string): string => STAGE_C[stage] ?? C.dim

export const plain = (l: Line) => l.map(x => x.t).join('')
export const usd = (n: number) => `$${n.toFixed(2)}`

// Width in terminal cells, as wcwidth counts them: per whole character (grapheme), 0 when every code point is
// zero-width or combining, 2 for emoji presentation or East Asian Wide/Fullwidth, else 1. `.length` is wrong for all three.
const GRAPHEMES = new Intl.Segmenter(undefined, { granularity: 'grapheme' })
const ZERO = /^[\p{Mn}\p{Me}\p{Cf}]+$/u
const WIDE = /[\p{Emoji_Presentation}\u{FE0F}\u{1100}-\u{115F}\u{2E80}-\u{A4CF}\u{AC00}-\u{D7A3}\u{F900}-\u{FAFF}\u{FE30}-\u{FE4F}\u{FF00}-\u{FF60}\u{FFE0}-\u{FFE6}\u{20000}-\u{3FFFD}]/u
const cell = (g: string) => (ZERO.test(g) ? 0 : WIDE.test(g) ? 2 : 1)
export const cols = (t: string) => {
  let n = 0
  for (const { segment } of GRAPHEMES.segment(t)) n += cell(segment)
  return n
}

// A line cut to `w` columns between whole characters, ending in `…`; a line that fits is returned as it is.
// Named fitWidth, not fit: the test-skip hook reads any call of `fit(` as a focused test.
export const fitWidth = (line: Line, w: number): Line => {
  if (cols(plain(line)) <= w) return line
  const out: Line = []
  let room = Math.max(0, w - 1)
  for (const s of line) {
    let t = ''
    for (const { segment } of GRAPHEMES.segment(s.t)) {
      const c = cell(segment)
      if (c > room) return [...out, { ...s, t }, { ...s, t: '…' }]
      room -= c
      t += segment
    }
    out.push({ ...s, t })
  }
  return out
}

// Text on the left, a value pushed to the right edge of `w` columns; the left is cut first, the right kept whole.
export const spread = (left: Line, right: Seg | Line | null, w: number): Line => {
  const r = right ? (Array.isArray(right) ? right : [right]) : []
  const rw = cols(plain(r))
  if (!r.length || rw + 3 > w) return fitWidth(left, w)
  const l = fitWidth(left, w - rw - 2)
  return [...l, { t: ' '.repeat(w - cols(plain(l)) - rw) }, ...r]
}

// The working mark turns only while the `motion` option is on; frame 0 is the still mark.
export const workMark = (frame: number) => '◐◓◑◒'[((frame % 4) + 4) % 4]

// Minutes and hours only: seconds churn every poll and say nothing a person acts on.
export const fmtSec = (s: number) => (s >= 3600 ? `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m` : `${Math.max(1, Math.floor(s / 60))}m`)
// The date suffix every unit name carries says nothing on a live board.
export const shortName = (u: string) => u.replace(/-\d{4}-\d{2}-\d{2}$/, '')
export const since = (t: number | null, now: number) => (t ? fmtSec(Math.max(0, Math.round((now - t) / 1000))) : '')
// h:mm AM/PM, as the page's hm (dashboard/app.js): midnight is 12:07 AM, noon 12:00 PM.
export const clockOf = (t: number) => { const d = new Date(t); const h = d.getHours(); return `${h % 12 || 12}:${String(d.getMinutes()).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}` }
const STAGES: Record<string, string> = { planning: 'Planning', building: 'Building', fixing: 'Fixing', review: 'Review', 'waiting-main': 'Waiting on main', merging: 'Merging' }
export const stageOf = (r: Row) => `${STAGES[r.stage] ?? r.stage.replace(/-/g, ' ').replace(/^./, c => c.toUpperCase())}${r.round ? ` r${r.round}` : ''}`
export const bar = (done: number, of: number) => { const n = Math.min(10, Math.max(0, Math.round((done / of) * 10))); return '█'.repeat(n) + '░'.repeat(10 - n) }
export const modelName = (id: string) => id.replace(/^claude-([a-z]+)-(\d+)-(\d+)$/, (_, f: string, a, b) => `${f[0].toUpperCase()}${f.slice(1)} ${a}.${b}`)

type Step = 'done' | 'running' | 'todo'
// The five steps a unit walks. Planning reads its seats' records; later stages imply the earlier steps finished.
export const stepsOf = (r: Row, merging: boolean): [string, Step][] => {
  const after = (n: number): Step[] => ['done', 'done', 'done', 'done', 'done'].map((x, i) => (i < n ? 'done' : i === n ? 'running' : 'todo')) as Step[]
  // dashboard.sh writes 'review', not 'reviewing'.
  const late: Record<string, number> = { building: 2, fixing: 3, review: 3 }
  let s: Step[]
  if (merging) s = after(4)
  else if (r.stage === 'planning') {
    const plan: Step = r.plan === 'done' ? 'done' : 'running'
    const judges: Step = r.judges === 'running' ? 'running' : r.judges === 'done' ? 'done' : 'todo'
    s = [judges === 'running' ? 'done' : plan, judges, 'todo', 'todo', 'todo']
  } else if (r.stage === 'waiting-main') s = r.verdict === 'GO' ? after(4).map((x, i) => (i === 4 ? 'todo' : x)) : after(3)
  else s = after(late[r.stage] ?? 2)
  return ['Plan', 'Judges', 'Build', 'Review', 'Merge'].map((n, i) => [n, s[i]])
}
// Builders record no per-issue status in their evidence, so a finished Build step is what says every issue is built.
export const builtOf = (r: Row, merging: boolean) => (stepsOf(r, merging)[2][1] === 'done' ? (r.issues ?? 0) : (r.built ?? 0))
const MARK: Record<Step, Seg> = { done: { t: '✓', c: C.ok }, running: { t: '◐', c: C.build }, todo: { t: '○', d: true } }
export const stepRow = (r: Row, merging: boolean): Line => stepsOf(r, merging).flatMap(([n, st], i): Seg[] => [...(i ? [{ t: '  ' }] : []), { t: `${n} `, d: st === 'todo' }, MARK[st]])

// An owner question blocks a unit when its id names that live unit (units-sources.ts unitOfAsk).
export const blocked = (r: Row, s: State) => s.snap.asks.some(a => a.unit === r.unit)

// A card: rows inside a frame in `color`, every row cut and padded so the right border stays in one column.
const card = (rows: Line[], color: string, w: number): Line[] => {
  const inner = w - 4
  const edge = '─'.repeat(w - 2)
  const body = rows.map((l): Line => {
    const f = fitWidth(l, inner)
    return [{ t: '│ ', c: color }, ...f, { t: `${' '.repeat(inner - cols(plain(f)))} │`, c: color }]
  })
  return [[{ t: `╭${edge}╮`, c: color }], ...body, [{ t: `╰${edge}╯`, c: color }]]
}

const ORDER = ['planning', 'building', 'fixing', 'review'] as const
// Units per stage in pipeline order, merging last; stages with nothing are left out.
export const stageCounts = (s: State): [string, number][] =>
  [...ORDER.map((st): [string, number] => [st, s.snap.rows.filter(r => r.stage === st).length]), ['merging', s.merges.filter(v => v.status === 'running').length] as [string, number]].filter(([, n]) => n > 0)

const gauge = (pct: number): Seg[] => {
  const k = Math.max(0, Math.min(10, Math.round(pct / 10)))
  return [{ t: '▰'.repeat(k), c: C.cost }, { t: '▱'.repeat(10 - k), c: C.dim }]
}
export const resetIn = (t: number, now: number, short = false) => {
  const s = Math.round((t - now) / 1000)
  if (s <= 0) return ''
  const d = Math.floor(s / 86400)
  return d ? (short ? `${d}d` : `${d}d ${Math.floor((s % 86400) / 3600)}h`) : short ? `${Math.max(1, Math.floor(s / 3600))}h` : fmtSec(s)
}
export const limitSegs = (s: State, reset: boolean): Line => {
  const l = s.snap.limit
  if (!l) return []
  const r = reset ? resetIn(l.resetsAt, s.now) : ''
  return [{ t: '7d ', c: C.dim }, ...gauge(l.pct), { t: ` ${Math.round(l.pct)}%` }, ...(r ? [{ t: ` ↻ ${r}`, c: C.dim }] : [])]
}

// `today` is the day's spend, already worded by the caller (units-sources.ts todayText), or null when there is none.
export const headerModel = (s: State, w: number, today: Seg | null): Line[] => {
  const parts = [...stageCounts(s).map(([st, n]) => `${n} ${st}`), ...(s.snap.asks.length ? [`${s.snap.asks.length} waiting on owner`] : [])]
  const out = [spread([{ t: 'UNITS', c: C.head, b: true }, ...(parts.length ? [{ t: ` · ${parts.join(' · ')}` }] : [])], today, w)]
  const tests: Line = s.tests.length ? [{ t: `tests ${s.tests.length} running`, c: C.dim }] : []
  if (s.snap.limit) out.push(spread(limitSegs(s, true), tests.length ? tests : null, w))
  // What each seat cost today; `partial` when a call had no price, so the amount reads as a floor.
  for (const [who, f] of [['main', s.snap.seatUsd.main], ['chief of staff', s.snap.seatUsd.chiefOfStaff]] as const)
    if (f) out.push(fitWidth([{ t: `${who} `, d: true }, { t: usd(f.usd), c: C.cost, b: true }, { t: `${f.partial ? ' partial' : ''} today`, d: true }], w))
  return out
}

export const legend = (w: number): Line =>
  fitWidth(([['plan', C.plan], ['build', C.build], ['review', C.review], ['waiting on owner', C.max], ['merged', C.ok]] as const).flatMap(([t, c], i): Seg[] => [{ t: i ? '  ■ ' : '■ ', c }, { t, d: true }]), w)

export const waitingModel = (s: State, w: number): Line[] => s.snap.asks.flatMap(a => {
  const iw = w - 4
  const age = since(a.askedAt, s.now)
  const holds = a.unit ? ` · ${shortName(a.unit)} waits` : ''
  const q = fitWidth([{ t: a.question }], Math.max(1, iw - 2 - cols(holds)))
  return card([spread([{ t: `◆ ${a.id}`, c: C.max, b: true }], age ? { t: age, c: C.max } : null, iw), [{ t: '  ' }, ...q, ...(holds ? [{ t: holds, d: true }] : [])]], C.max, w)
})

export const cardModel = (r: Row, s: State, w: number, merging: boolean, frame: number): Line[] => {
  const iw = w - 4
  const col = stageColor(merging ? 'merging' : r.stage)
  const time = since(r.stageSince ?? r.startedAt, s.now)
  // A card with no live seat says so, dim and without an effort, rather than show another seat's model.
  const who: Seg = r.model ? { t: ` · ${modelName(r.model)}${r.effort ? ` · ${r.effort}` : ''}`, d: true } : { t: ' · model unknown', c: C.dim, d: true }
  const out: Line[] = [spread([{ t: r.working ? workMark(frame) : '○', c: col }, { t: ' ' }, { t: shortName(r.unit), c: C.name, b: true }, who], { t: `${stageOf(r)}${time ? ` · ${time}` : ''}`, c: col }, iw)]
  out.push([{ t: '  ' }, ...stepRow(r, merging), ...(blocked(r, s) ? [{ t: '   ⏸ waits on owner', c: C.max }] : [])])
  const built = builtOf(r, merging)
  if (r.issues) out.push([{ t: '  ' }, { t: bar(built, r.issues), c: C.ok }, { t: `  ${built} of ${r.issues} issues built` }])
  else if (r.closes.length) out.push([{ t: `  ${r.closes.join(' ')}`, d: true }])
  const verdict: Line = r.verdict
    ? [{ t: `  r${r.verdictRound ?? r.round ?? ''} ` }, { t: r.verdict, c: r.verdict === 'GO' ? C.ok : C.bad, b: true }, ...(r.findings ? [{ t: ` · ${r.findings}` }] : [])]
    : [{ t: '' }]
  if (r.verdict || r.costs.total > 0) out.push(spread(verdict, r.costs.total > 0 ? { t: usd(r.costs.total), c: C.cost, b: true } : null, iw))
  const parts = (['plan', 'build', 'review', 'fix'] as const).filter(k => r.costs[k] > 0).map(k => `${k} ${usd(r.costs[k])}`)
  if (parts.length > 1) out.push([{ t: `  ${parts.join(' · ')}`, d: true }])
  if (r.red) out.push([{ t: '  ⚠ at its prompt', c: C.bad, b: true }])
  return card(out, col, w)
}

// A merged unit's row; `cost` is its finished cost (the snapshot's finishedUsd), when it has one.
export const mergedModel = (m: Merged, cost: number | undefined, w: number): Line =>
  spread([{ t: '✓ ', c: C.ok }, { t: `${shortName(m.unit).padEnd(22)} `, d: true }, { t: clockOf(m.at), d: true }], cost ? { t: usd(cost), d: true } : null, w)

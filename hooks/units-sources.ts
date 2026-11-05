// Pure parsers for the units mod. No `$` here: every function takes a whole file's text, so a log cut off mid-line, rewritten
// by a rerun, or noisy for 17,000 bytes gives the same counts as a clean one. Callers re-parse when size or mtime moves.
import {
  C, bar, blocked, builtOf, cardModel, ctxLine, ctxShort, eventLog, fitWidth, fmtSec, gateStrip, headerModel, layoutOf, legend, limitSegs, mergedModel, plain, resetIn,
  shortName, since, spread, stageColor, stageCounts, stageOf, stepRow, timelineLanes, toolLines, usd, waitingModel, whereLine, workMark,
} from './units-elements'

const ANSI = /\x1b\[[0-9;]*[A-Za-z]/g
// run-shell-tests.sh pads the name and may follow the seconds with `rc=1` or `HUNG past ...`.
const FILE = /^-- (ok  |FAIL) (\S.*?) +(\d+)s(?: .*)?$/
const VITEST = /^\s*([✓❯×↓]) (\S.*?) \(\d+ tests?(?: \| [^)]*)?\)(?: \d+ms)?$/

// Whole lines only: text after the last newline is a half-written line.
const linesOf = (text: string): string[] => {
  const s = text.replace(ANSI, '')
  const i = s.lastIndexOf('\n')
  return i < 0 ? [] : s.slice(0, i).split('\n')
}

export type Progress = { done: number; failed: number; firstFail: string | null }

// A file's last line wins: test-files.sh reruns a crashed file once.
const progress = (lines: string[]): Progress => {
  const seen = new Map<string, boolean>()
  for (const l of lines) {
    const a = FILE.exec(l)
    if (a) { seen.set(a[2], a[1] === 'ok  '); continue }
    const v = VITEST.exec(l)
    if (v) seen.set(v[2], v[1] !== '❯' && v[1] !== '×')
  }
  const bad = [...seen].filter(([, ok]) => !ok).map(([f]) => f)
  return { done: seen.size, failed: bad.length, firstFail: bad[0] ?? null }
}

export type Merge = Progress & { step: string | null; total: number | null; refused: { step: string; reason: string } | null; ended: boolean }

export const parseMergeLog = (text: string): Merge => {
  const lines = linesOf(text)
  let step: string | null = null
  let total: number | null = null
  let refused: Merge['refused'] = null
  let ended = false
  for (const l of lines) {
    const s = /^STEP (\d+) ([^:]+)/.exec(l)
    if (s) step = `${s[1]} ${s[2]}`
    const t = /^STEP 2 tests: (\d+) node\b.*?, (\d+) web, (\d+) shell/.exec(l)
    if (t) total = Number(t[1]) + Number(t[2]) + Number(t[3])
    const f = /^FAILED ([^:]+): (.*)$/.exec(l)
    if (f) refused = { step: f[1], reason: f[2].slice(0, 120) }
    if (l.startsWith('DONE unit=')) ended = true
  }
  return { ...progress(lines), step, total, refused, ended }
}

// A merge log can hold many attempts (merge-queue.sh appends). Each opens with `ATTEMPT unit=<unit> pid=<pid> started=<s>`;
// the newest attempt is the lines from the last such line to the end. A log with no such line has no attempt (null).
export type Attempt = { text: string; pid: string | null }

export const newestAttempt = (text: string, unit: string): Attempt | null => {
  const head = `ATTEMPT unit=${unit} `
  const i = text.lastIndexOf(`\n${head}`)
  const at = i >= 0 ? i + 1 : text.startsWith(head) ? 0 : -1
  if (at < 0) return null
  const slice = text.slice(at)
  return { text: slice, pid: /^ATTEMPT .*\bpid=(\d+)/.exec(slice)?.[1] ?? null }
}

export type TestLive = Progress & { total: number; startedAt: number }

// run-shell-tests.sh's live table: `run <epoch> <jobs>`, `file <rel>`, `start <rel> <epoch>`, `end <rel> <ok|FAIL|skip> <secs>`.
export const parseTestLive = (tsv: string): TestLive => {
  let total = 0
  let startedAt = 0
  const ended = new Map<string, boolean>()
  for (const l of linesOf(tsv)) {
    const [kind, a, b] = l.split('\t')
    if (kind === 'run') startedAt = Number(a)
    else if (kind === 'file') total++
    else if (kind === 'end' && (b === 'ok' || b === 'skip' || b === 'FAIL')) ended.set(a, b !== 'FAIL')
  }
  const bad = [...ended].filter(([, ok]) => !ok).map(([f]) => f)
  return { total, startedAt, done: ended.size, failed: bad.length, firstFail: bad[0] ?? null }
}

// Main = git dir equals the common dir; Chief of Staff = a worktree folder named Chief-of-Staff; anything else is a worker.
export const seatFromGit = (stdout: string): { seat: 'main' | 'chiefOfStaff' | 'worker'; main: string } | null => {
  const [gitDir, common, top] = stdout.trim().split('\n')
  if (!gitDir || !common || !top) return null
  const main = common.replace(/\/\.git$/, '')
  return { seat: top.split('/').pop() === 'Chief-of-Staff' ? 'chiefOfStaff' : gitDir === common ? 'main' : 'worker', main }
}

export type Row = {
  unit: string; stage: string; round: number | null; verdict: string | null; verdictRound: number | null; findings: string; usd: number
  ageSec: number | null; red: boolean; issues: number | null; built: number | null; startedAt: number | null
  closes: string[]; costs: Costs; plan: SeatState; judges: SeatState
  model: string | null; effort: string | null; working: boolean; stageSince: number | null
  // #555. undefined: the snapshot lacks the key (no read tried); null: the collector tried and failed (DH9).
  context?: Ctx | null; compactions?: number | null; rounds?: Dot[]; judgeRounds?: Dot[]
  history?: { stage: string; from: number; to: number | null }[]; tools?: { tool: string; ts: number; running: boolean }[]
  step?: { kind: string; start: number; end: number | null; errors: number }
}
export type Ctx = { tokens: number; line: number | null }
export type Dot = 'GO' | 'NO-GO' | null
export type UnitEvent = { at: number; unit: string; event: string }
export const dotOf = (v: string): Dot => (/NO-GO/.test(v) ? 'NO-GO' : /GO/.test(v) ? 'GO' : null)
export type Costs = { plan: number; build: number; review: number; fix: number; total: number }
export type SeatState = 'done' | 'running' | null
// A merged unit; its finished cost is the snapshot's `finishedUsd[unit]`.
export type Merged = { unit: string; at: number }
// `unit` is the live unit the ask's id names (holds' rule), else null.
export type Ask = { id: string; question: string; askedAt: number | null; unit: string | null }
// `chain` is always null: the plugin has no push-chain lane to show.
export type Snap = {
  note: string | null; staleMin: number | null; rows: Row[]; merged: string[]; mergedAt: Merged[]; chain: null
  finishedUsd: Record<string, number>
  // The dashboard's Cost today for this project (`limit.today[<project>]`), split by folder; null when it has none.
  day: Day | null
  // The 7-day limit, the owner's open questions, and the fields the snapshot lacks or carries as junk, each named.
  limit: { pct: number; resetsAt: number } | null; asks: Ask[]; unread: string[]
  // main's and the chief of staff's cost today (`seats.main.today`, `seats.relay.today`); null when the snapshot has none.
  seatUsd: { main: SeatUsd | null; chiefOfStaff: SeatUsd | null }
  // #555: guard refusals, the live seats' context, and the units merged here and not yet pushed.
  gates?: { blocks: number; lastHour: number; items: { at: number; hook: string }[] } | null
  seatCtx?: { main: Ctx | null | undefined; chiefOfStaff: Ctx | null | undefined; mainCompactions: number | null }
  unpushed?: string[] | null
}
export type SeatUsd = { usd: number; partial: boolean }
// `merged` holds the units of finishedBuilds and mergedSincePush, the folders the split counts as merged.
export type Day = { total: number; byFolder: Record<string, number>; complete: boolean; merged: string[] }

// pp_standing_wt's folders, lowercased as dashboard.sh writes their stage: standing panes, never units.
export const NOT_UNITS = new Set(['chief-of-staff', 'fast-lane', 'research-lane'])
export const emptySnap = (note: string | null): Snap => ({ note, staleMin: null, rows: [], merged: [], mergedAt: [], chain: null, finishedUsd: {}, day: null, limit: null, asks: [], unread: [], seatUsd: { main: null, chiefOfStaff: null } })
// scripts/codex-helpers.sh's ROLE_LANES: the stage each launch role works in; null is a seat that is never a unit's.
export const ROLE_LANES: Record<string, string | null> = {
  'plan-author': 'planning', 'brief-reviewer': 'planning', 'plan-author-arch': 'planning', 'brief-reviewer-arch': 'planning', 'plan-author-hard': 'planning',
  'brief-reviewer-hard': 'planning', 'plan-judge-sol': 'planning', 'plan-judge-opus': 'planning', investigator: 'planning', debugger: 'planning', 'debugger-pipeline': 'planning',
  implementer: 'building', 'implementer-light': 'building', 'race-implementer': 'building', escalation: 'building', builder: 'building',
  reviewer: 'review', 'codex-reviewer': 'review', 'codex-reviewer-risky': 'review', 'luna-reviewer': 'review', refuter: 'review', certifier: 'review',
  'judge-fable': 'review', 'judge-luna': 'review', 'judge-luna-high': 'review', 'judge-sol-high': 'review', 'judge-sol-xhigh': 'review',
  fixer: 'fixing', 'design-fixer': 'fixing',
  'e2e-driver': null, companion: null, 'automation-claude': null, 'main-session': null, 'release-captain': null,
}
const str = (v: unknown) => (typeof v === 'string' && v ? v : null)
const time = (v: unknown) => { const t = Date.parse(String(v ?? '')); return Number.isFinite(t) ? t : null }
const num = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : null)
// The live seat: a planning unit's running plan seat, else the record of the recorded role, else the records of the
// stage's lane when they agree. No such record leaves the model unknown, never another seat's.
const seatOf = (u: any): { model: string | null; effort: string | null } => {
  const recs: any[] = (Array.isArray(u.seats) ? u.seats : []).filter((x: any) => str(x?.model))
  let pick: any = null
  if (u.stage === 'planning') pick = (Array.isArray(u.plan?.seats) ? u.plan.seats : []).filter((x: any) => str(x?.model) && !x.completedAt).at(-1) ?? null
  else if (str(u.seatRole)) pick = recs.find(x => x.role === u.seatRole) ?? null
  else {
    const lane = recs.filter(x => Object.hasOwn(ROLE_LANES, x.role) && ROLE_LANES[x.role] === u.stage)
    if (lane.length && lane.every(x => x.model === lane[0].model && x.effort === lane[0].effort)) pick = lane[0]
  }
  return { model: str(pick?.model), effort: str(pick?.effort) }
}
// holds' rule (scripts/decision.sh): the ledger has no unit field, so an id names a unit only as <unit>, plan-<unit> or
// review-stop-<unit>-r<digits>, and only a unit in flight is named.
const unitOfAsk = (id: string, units: string[]): string | null =>
  units.find(u => id === u || id === `plan-${u}` || (id.startsWith(`review-stop-${u}-r`) && /^\d+$/.test(id.slice(`review-stop-${u}-r`.length)))) ?? null
const missing = (name: string, v: unknown) => `${name}: ${v === undefined || v === null ? 'not in the snapshot' : 'unreadable'}`
const STAGE_COST: Record<string, keyof Costs> = { planning: 'plan', building: 'build', review: 'review', fixing: 'fix' }
const costsOf = (stages: any[]): Costs => {
  const c: Costs = { plan: 0, build: 0, review: 0, fix: 0, total: 0 }
  for (const x of stages) { const usd = Number(x?.usd) || 0; c.total += usd; const k = STAGE_COST[String(x?.stage)]; if (k) c[k] += usd }
  return c
}
const len = (v: unknown) => (Array.isArray(v) ? v.length : null)
// dashboard.sh writes a Builder's clearLine as a JSON string of digits (`--arg l`, as deployed); a seat's line is a number.
const lineOf = (v: unknown) => (typeof v === 'string' && /^\d+$/.test(v) ? Number(v) : num(v))
const ctxOf = (tokens: unknown, line: unknown): Ctx | null => (num(tokens) !== null ? { tokens: tokens as number, line: lineOf(line) } : null)
// What the views read of a Builder beyond its stage: each key stays undefined when the snapshot lacks it.
const builderExtras = (b: any, junk: boolean, steps: any[]) => ({
  context: b.context === undefined ? undefined : junk ? null : ctxOf(b.context, b.clearLine),
  compactions: b.compactions === undefined ? undefined : num(b.compactions),
  rounds: b.verdicts && typeof b.verdicts === 'object' ? Object.entries(b.verdicts).sort((a, c) => Number(a[0]) - Number(c[0])).map(([, v]) => dotOf(String(v))) : undefined,
  history: Array.isArray(b.stageHistory) ? b.stageHistory.filter((h: any) => time(h?.from) !== null).map((h: any) => ({ stage: String(h.stage), from: time(h.from) as number, to: time(h.to) })) : undefined,
  tools: Array.isArray(b.tools) ? b.tools.map((t: any) => ({ tool: String(t?.tool), ts: time(t?.ts) ?? 0, running: t?.running === true })) : undefined,
  step: steps.length && time(steps[0]?.start) !== null
    ? { kind: String(steps[0].kind), start: time(steps[0].start) as number, end: time(steps[0].end ?? steps[0].stop), errors: steps.filter(x => x?.kind === 'codex' && num(x.rc) !== null && x.rc !== 0).length } : undefined,
})

// The dashboard's `data.js` holds `window.DASH = {updatedAt, projects: {<name>: {units: {...}}}}`; this project's units are read.
export const parseSnapshot = (text: string, now: number, project: string): Snap => {
  let j: any
  try { j = JSON.parse(text.replace(/^\s*window\.DASH\s*=\s*/, '').replace(/;\s*$/, '')) } catch { return emptySnap('units: snapshot unreadable') }
  if (!j || typeof j !== 'object') return emptySnap('units: snapshot unreadable')
  const p = j.projects?.[project]
  if (!p || typeof p !== 'object') return emptySnap('units: this project is not in the dashboard snapshot')
  const u = p.units
  if (!Array.isArray(u?.inFlight)) return emptySnap('units: snapshot unreadable')
  const at = Date.parse(j.updatedAt)
  const min = Math.round((now - at) / 60000)
  const rowNotes: string[] = []
  const rows: Row[] = u.inFlight.filter((x: any) => x && !NOT_UNITS.has(x.stage) && x.stage !== 'seat').map((x: any) => {
    const b = x.builder
    const f = b?.findings?.sol ?? b?.findings
    const started = Date.parse(b?.startedAt ?? '')
    // dashboard.sh writes the cost to builder.cost once a Builder runs (planning first), to plan.cost before that.
    const costs = costsOf((b?.cost ?? x.plan?.cost)?.stages ?? [])
    const junk = b && b.context !== undefined && b.context !== null && num(b.context) === null
    if (junk) rowNotes.push(`context ${x.unit}: unreadable`)
    const steps: any[] = Array.isArray(b?.steps) ? b.steps : []
    return {
      ...(b ? builderExtras(b, junk, steps) : {}),
      unit: String(x.unit),
      stage: String(x.stage ?? ''),
      round: x.round ?? null,
      verdict: b?.verdict ? String(b.verdict).replace(/^VERDICT:\s*/, '') : null,
      verdictRound: b?.verdictRound ?? null,
      findings: f ? (['P0', 'P1', 'P2', 'P3'] as const).filter(k => Number(f[k]) > 0).map(k => `${f[k]} ${k}`).join(' ') : '',
      usd: costs.total,
      costs,
      plan: null,
      judges: null,
      ageSec: typeof x.ageSec === 'number' ? x.ageSec : null,
      red: !!b && !/:working/.test(String(x.agents ?? '')),
      issues: len(b?.issues),
      // dashboard.sh counts every issue an evidence heading names; only the brief's own are built (as dashboard/app.js counts).
      built: Array.isArray(b?.built) && Array.isArray(b?.issues) ? b.issues.filter((i: unknown) => b.built.includes(i)).length : len(b?.built),
      startedAt: Number.isFinite(started) ? started : null,
      closes: [],
      ...seatOf(x),
      working: /:working/.test(String(x.agents ?? '')),
      stageSince: time(x.stageSince),
    }
  })
  const lim = j.limit
  const limit = num(lim?.usedPct) !== null && time(lim?.resetsAt) !== null ? { pct: lim.usedPct as number, resetsAt: time(lim.resetsAt) as number } : null
  const decisions = p.needsOwner?.decisions
  const decisionsError = str(p.sources?.decisions?.error)
  const names = rows.map((r: Row) => r.unit)
  const asks: Ask[] = (Array.isArray(decisions) ? decisions : []).filter((d: any) => str(d?.id)).map((d: any) => ({
    id: d.id as string, question: String(d.question ?? '').replace(/\s+/g, ' ').trim(), askedAt: time(d.askedAt), unit: unitOfAsk(d.id, names),
  })).sort((a: Ask, b: Ask) => (a.askedAt ?? Infinity) - (b.askedAt ?? Infinity))
  // A seat with no `seats` entry or no `today` has nothing to show; a `today` whose usd is not a non-negative number is junk, named.
  const seatNotes: string[] = []
  const seatToday = (key: string, name: string): SeatUsd | null => {
    const t = p.seats?.[key]?.today
    if (!t || typeof t !== 'object') return null
    if (num(t.usd) === null || t.usd < 0) { seatNotes.push(missing(name, t.usd)); return null }
    return { usd: t.usd, partial: t.partial === true }
  }
  const seatUsd = { main: seatToday('main', 'main cost today'), chiefOfStaff: seatToday('relay', 'chief of staff cost today') }
  // finishedBuilds cannot tell a pushed merge from one only here; mergedSincePush names the ones not pushed.
  const msp = u.mergedSincePush
  const unpushed: string[] | null | undefined = msp === undefined ? undefined : Array.isArray(msp) ? msp.map((m: any) => String(m?.unit)) : null
  // No decisions ledger yet, or no finished-builds record yet, is a project with nothing to show there, not a problem.
  const unread = [
    ...(limit ? [] : [missing('7d limit', lim?.usedPct ?? lim)]),
    ...(Array.isArray(decisions) || decisionsError?.startsWith('no ledger at ') ? [] : [`decisions: ${decisionsError ?? 'not in the snapshot'}`]),
    ...(Array.isArray(u.finishedBuilds) || u.finishedBuilds === null ? [] : [missing('finished builds', u.finishedBuilds)]),
    ...(Number.isFinite(at) ? [] : [missing('updated at', j.updatedAt)]),
    ...seatNotes,
    ...rowNotes,
    ...(unpushed === null ? ['unpushed: unreadable'] : []),
  ]
  const g = p.guardBlocks
  const gates: Snap['gates'] = g === undefined ? undefined : g && typeof g === 'object' && Array.isArray(g.items)
    ? { blocks: num(g.blocks) ?? g.items.length, lastHour: g.items.filter((i: any) => now - (time(i?.timestamp) ?? 0) < 3600_000).length,
      items: g.items.filter((i: any) => str(i?.hook)).map((i: any) => ({ at: time(i.timestamp) ?? 0, hook: i.hook as string })).sort((a: { at: number }, c: { at: number }) => c.at - a.at).slice(0, 6) }
    : null
  const ctxSeat = (key: string) => (p.seats?.[key]?.context === undefined ? undefined : ctxOf(p.seats[key].context, p.seats[key].line))
  const seatMain = ctxSeat('main')
  const seatRelay = ctxSeat('relay')
  const seatCtx: Snap['seatCtx'] = seatMain === undefined && seatRelay === undefined ? undefined
    : { main: seatMain, chiefOfStaff: seatRelay, mainCompactions: Array.isArray(p.mainEvents?.compactions) ? p.mainEvents.compactions.length : null }
  // Every merge this checkout made is in finishedBuilds; mergedSincePush drops one once it is pushed, so a push would
  // take today's merges, and their spend, off the pane.
  const finished: any[] = Array.isArray(u.finishedBuilds) ? u.finishedBuilds : []
  const merged = finished.map((m: any) => ({ unit: String(m.unit), at: Date.parse(m.at ?? '') }))
  const d = j.limit?.today?.[project]
  const day: Day | null = d && Number.isFinite(d.spentUsd) ? {
    total: Number(d.spentUsd),
    byFolder: Object.fromEntries(Object.entries(d.byFolder && typeof d.byFolder === 'object' ? d.byFolder : {}).filter(([, n]) => Number.isFinite(n)) as [string, number][]),
    complete: d.complete === true,
    merged: [...merged.map((m: { unit: string }) => m.unit), ...(u.mergedSincePush ?? []).map((m: any) => String(m?.unit))],
  } : null
  return {
    note: null,
    staleMin: Number.isFinite(min) && min > 5 ? min : null,
    rows,
    merged: merged.map((m: { unit: string }) => m.unit),
    mergedAt: merged.filter((m: { at: number }) => Number.isFinite(m.at)),
    chain: null,
    finishedUsd: Object.fromEntries(finished.filter((f: any) => Number.isFinite(f?.cost?.total?.usd)).map((f: any) => [String(f.unit), Number(f.cost.total.usd)])),
    day,
    limit,
    asks,
    unread,
    seatUsd,
    gates,
    seatCtx,
    unpushed,
  }
}

// A count is shown only when it is known: an unknown total gives "N files", never "N/?".
const counts = (p: Progress, total: number | null) => `${total ? `${p.done}/${total}` : `${p.done}`} files${p.failed ? ` · ${p.failed} failed (first ${p.firstFail})` : ''}`

export type MergeView = { unit: string; status: 'running' | 'stopped' | 'refused'; m: Merge; elapsedSec: number }
export type TestView = { owner: string; kind: string; p: Progress; total: number | null; elapsedSec: number }
export type Notes = { merges: string[]; tests: string[] }
// `events`: the unit-events.jsonl tail; null when the file could not be read, undefined before the mod read it.
export type State = { now: number; snap: Snap; merges: MergeView[]; tests: TestView[]; notes: Notes; events?: UnitEvent[] | null }

// One run of styled text; a line is a list of them. The plain text of every view is the same runs joined.
export type Seg = { t: string; c?: string; b?: boolean; d?: boolean }
export type Line = Seg[]

// A plan's `Closes: issue 1, issue 2` (or `Closes: #1 #2`) line names the unit's issues before any Builder log does.
export const closesOf = (plan: string): string[] => (/^Closes:\s*(.+)$/m.exec(plan)?.[1].match(/#\d+|\bissue\s+\d+/gi) ?? []).map(x => `#${x.replace(/\D/g, '')}`)

const mergeModel = (v: MergeView, w: number): Line =>
  v.status === 'refused' ? fitWidth([{ t: '✗ ', c: C.bad }, { t: shortName(v.unit), c: C.name, b: true }, { t: `  refused at ${v.m.refused?.step}: ${v.m.refused?.reason}`, c: C.bad }], w)
    : v.status === 'stopped' ? fitWidth([{ t: '✗ ', c: C.bad }, { t: shortName(v.unit), c: C.name, b: true }, { t: `  stopped${v.m.step ? ` at ${v.m.step}` : ''}, no result`, c: C.bad }], w)
      : spread([{ t: '◐ ', c: C.build }, { t: shortName(v.unit), c: C.name, b: true }, { t: `  ${v.m.step ? v.m.step.replace(/^\d+ /, '') : 'merging'}${v.m.done || v.m.total ? ` ${counts(v.m, v.m.total)}` : ''}` }], { t: fmtSec(v.elapsedSec), d: true }, w)

const testModel = (v: TestView, w: number): Line =>
  spread([{ t: '▸ ', c: C.build },{ t: shortName(v.owner), c: C.name, b: true }, { t: `  ${v.kind} ${counts(v.p, v.total)}`, c: v.p.failed ? C.bad : undefined }], { t: fmtSec(v.elapsedSec), d: true }, w)

const mergedToday = (s: State) => s.snap.mergedAt.filter(m => new Date(m.at).toDateString() === new Date(s.now).toDateString()).sort((a, b) => b.at - a.at)

// Issue 421: today's spend is the dashboard's Cost today for the project. A snapshot without it falls back to what
// the board can see, units merged today plus every unit still in flight, which the header marks `units only`.
export const todayUsd = (s: State) => s.snap.day ? s.snap.day.total
  : mergedToday(s).reduce((n, m) => n + (s.snap.finishedUsd[m.unit] ?? 0), 0) + s.snap.rows.reduce((n, r) => n + r.costs.total, 0)
const todayText = (s: State) => `today ${s.snap.day && !s.snap.day.complete ? 'at least ' : ''}${usd(todayUsd(s))}`

// The day split by where it was spent: merged units, units in flight, main, the standing panes and lanes, and the
// rest not attributed (`:other`, and any folder none of these names), so the parts always sum to the total.
export const todaySplit = (s: State): [string, number][] => {
  const d = s.snap.day
  if (!d) return []
  const merged = new Set(d.merged)
  const live = new Set(s.snap.rows.flatMap(r => [r.unit, `${r.unit}-plan`]))
  const kinds = [
    ['merged', (k: string) => merged.has(k)], ['in flight', (k: string) => live.has(k)], ['main', (k: string) => k === ':main'],
    ['lanes', (k: string) => NOT_UNITS.has(k.toLowerCase())],
  ] as const
  const sums = kinds.map(([name]): [string, number] => [name, 0])
  let named = 0
  for (const [k, n] of Object.entries(d.byFolder)) {
    const i = kinds.findIndex(([, is]) => is(k))
    if (i >= 0) { sums[i][1] += n; named += n }
  }
  return [...sums, ['other', d.total - named] as [string, number]].filter(([, n]) => Math.abs(n) >= 0.005)
}

// The one list of read problems: a work source could hide a unit, an ask, a merge or a test run, so it keeps every view
// up and is named in each; a figure gap (the 7-day limit, a seat's cost today) shows only under CANNOT READ. Every view reads problems
// through here, so a new source joins this list and nowhere else.
const FIGURE = /^(7d limit|main cost today|chief of staff cost today|unpushed|context [^:]+): /
export const readProblems = (s: State) => {
  const all = [s.snap.note, ...s.snap.unread, ...s.notes.merges, ...s.notes.tests].filter((n): n is string => !!n)
  return { all, work: all.filter(n => !FIGURE.test(n)) }
}
const workLine = (s: State) => {
  const w = readProblems(s).work
  return w.length ? `${w[0]}${w.length > 1 ? ` +${w.length - 1}` : ''}` : ''
}
const runningUnits = (s: State) => new Set(s.merges.filter(v => v.status === 'running').map(v => v.unit))
const todaySeg = (s: State): Seg | null => (todayUsd(s) > 0 ? { t: todayText(s), c: C.cost, b: true } : null)

// The pane and /units: a header, then sections drawn only when they hold something.
// `expanded` (a unit name) and `focus` are the pane keys' two in-memory atoms: the unit shows its last tool calls, the focused section goes first.
export type PaneUi = { expanded: string | null; focus: string | null }
const FOCUS: Record<string, string> = { decisions: 'decisions', timeline: 'timeline', log: 'log' }
export const paneModel = (s: State, w: number, frame = 0, ui: PaneUi = { expanded: null, focus: null }): Line[] => {
  const out: Line[] = headerModel(s, w, todaySeg(s))
  const lay = layoutOf(w)
  const merging = runningUnits(s)
  // Sections are built apart and joined in order, the focused one first; one with no lines is not drawn.
  const blocks = new Map<string, Line[]>()
  const head = (key: string, title: string, right: Seg | null, lines: Line[], color: string = C.head) => { if (lines.length) blocks.set(key, [[], spread([{ t: title, c: color, b: true }], right, w), ...lines]) }
  const split = todaySplit(s)
  if (split.length) out.push(fitWidth([{ t: `  ${split.map(([k, n]) => `${k} ${usd(n)}`).join(' · ')}`, d: true }], w))
  else if (todayUsd(s) > 0 && !s.snap.day) out.push([{ t: '  units only', d: true }])
  // First section under the header: a short pane cuts the lower ones, and an unreadable source must stay in view.
  const shown = [...(!s.snap.note && s.snap.staleMin ? [`dashboard data is ${s.snap.staleMin} min old`] : []), ...readProblems(s).all]
  head('cannot', 'CANNOT READ', null, shown.map((n): Line => fitWidth([{ t: `⚠ ${n}`, c: C.bad }], w)))
  const today = mergedToday(s)
  const sc = s.snap.seatCtx
  // WAITING first, then the live seats' gauges (drawn with or without unit rows), the units, gates, merges, tests, day.
  head('decisions', `WAITING ON OWNER  ${s.snap.asks.length}`, null, waitingModel(s, w), C.max)
  head('seats', 'SEATS', null, sc ? [...ctxLine('main context', sc.main, sc.mainCompactions, w), ...ctxLine('chief of staff context', sc.chiefOfStaff, null, w)] : [])
  const unitLines = (r: Row): Line[] => lay === 'mini'
    ? [spread([{ t: `${r.working ? workMark(frame) : '○'} `, c: stageColor(merging.has(r.unit) ? 'merging' : r.stage) }, { t: shortName(r.unit), c: C.name, b: true }], { t: stageOf(r), d: true }, w), ...(r.unit === ui.expanded ? toolLines(r) : [])]
    : cardModel(r, s, w, merging.has(r.unit), frame, r.unit === ui.expanded)
  head('units', `BUILDING  ${s.snap.rows.length}`, null, s.snap.rows.flatMap(unitLines))
  head('gates', 'GATES', null, gateStrip(s.snap, s.snap.rows))
  head('merging', `MERGING  ${s.merges.length}`, null, s.merges.map(v => mergeModel(v, w)))
  head('tests', 'TESTS', null, s.tests.map(v => testModel(v, w)))
  head('timeline', 'TIMELINE', null, lay === 'wide' || ui.focus === 'timeline' ? timelineLanes(s, w) : [])
  const sum = today.reduce((n, m) => n + (s.snap.finishedUsd[m.unit] ?? 0), 0)
  head('merged', `MERGED TODAY  ${today.length}`, sum > 0 ? { t: usd(sum), c: C.cost, b: true } : null, [...today.map(m => mergedModel(m, s.snap.finishedUsd[m.unit], w)), ...whereLine(today, s.snap)])
  head('log', 'UNIT LOG', null, (lay !== 'mini' || ui.focus === 'log') && s.snap.rows.length ? eventLog(s, w) : [])
  const order = ['decisions', 'seats', 'units', 'gates', 'merging', 'tests', 'timeline', 'merged', 'log']
  const first = ui.focus ? FOCUS[ui.focus] : undefined
  out.push(...(blocks.get('cannot') ?? []))
  if (s.snap.rows.length || s.snap.asks.length || today.length) out.push(legend(w))
  for (const k of [...(first ? [first] : []), ...order.filter(o => o !== first)]) out.push(...(blocks.get(k) ?? []))
  return out
}

export const paneLines = (s: State, w = 56): string[] => paneModel(s, w).map(plain)

const mark = (r: Row, frame: number) => (r.working ? workMark(frame) : '○')
// The unit row 2 shows whole: the working unit with the most spend, else the one with the most spend.
const busiest = (rows: Row[]) => [...rows].sort((a, b) => Number(b.working) - Number(a.working) || b.costs.total - a.costs.total)[0]

// The band: up to three rows, each cut to `w`. Row 1 waiting on owner and the limit, row 2 the busiest unit's step row,
// row 3 everything else short.
export const bandModel = (s: State, w: number, frame = 0): Line[] => {
  const merging = runningUnits(s)
  const a = s.snap.asks[0]
  const holds = a?.unit ? ` · blocks ${shortName(a.unit)}` : ''
  const right: Line = [...limitSegs(s, false), ...(todayUsd(s) > 0 ? [{ t: `${s.snap.limit ? ' · ' : ''}${todayText(s)}`, c: C.cost, b: true }] : [])]
  const row1: Line = a ? spread([{ t: `◆ waiting on owner ${s.snap.asks.length}`, c: C.max, b: true }, { t: ` · ${a.id}` }, { t: `${a.askedAt ? ` ${since(a.askedAt, s.now)}` : ''}${holds}`, d: true }], right.length ? right : null, w) : right
  const top = busiest(s.snap.rows)
  const row2: Line = top ? (() => {
    const m = merging.has(top.unit)
    const time = since(top.stageSince ?? top.startedAt, s.now)
    return [{ t: `${mark(top, frame)} `, c: stageColor(m ? 'merging' : top.stage) }, { t: shortName(top.unit), c: C.name, b: true }, { t: ` ${stageOf(top)}  `, d: true }, ...stepRow(top, m),
      ...(top.issues ? [{ t: `  ${bar(builtOf(top, m), top.issues)}`, c: C.ok }, { t: ` ${builtOf(top, m)}/${top.issues}` }] : []),
      ...(top.costs.total > 0 ? [{ t: ` · ${usd(top.costs.total)}`, c: C.cost }] : []), ...ctxShort(top.context), ...(time ? [{ t: ` · ${time}`, d: true }] : []),
      ...(blocked(top, s) ? [{ t: '  ⏸ owner', c: C.max }] : []), ...(top.red ? [{ t: '  ⚠ at its prompt', c: C.bad, b: true }] : [])]
  })() : []
  const merged = mergedToday(s).length
  const problems = workLine(s)
  // A read problem leads row 3, so the cut to `w` never drops it behind the other units.
  const rest: Line[] = [
    ...(problems ? [[{ t: `⚠ ${problems}`, c: C.bad }]] : []),
    ...s.snap.rows.filter(r => r !== top).map((r): Line => [{ t: `${mark(r, frame)} `, c: stageColor(r.stage) }, { t: shortName(r.unit), c: C.name, b: true },
      { t: ` ${stageOf(r)}${r.issues ? ` ${builtOf(r, merging.has(r.unit))}/${r.issues}` : ''}${(r.stageSince ?? r.startedAt) ? ` ${since(r.stageSince ?? r.startedAt, s.now)}` : ''}`, d: true },
      ...(blocked(r, s) ? [{ t: ' ⏸ owner', c: C.max }] : []), ...(r.red ? [{ t: ' ⚠', c: C.bad, b: true }] : [])]),
    ...(merged ? [[{ t: '✓ ', c: C.ok }, { t: `${merged} merged today` }]] : []),
    // A stopped or refused merge shows in the side pane only; the band lists live merges.
    ...s.merges.filter(v => v.status === 'running').map((v): Line =>
      [{ t: '◐ ', c: C.ok }, { t: shortName(v.unit), c: C.name, b: true }, { t: ` merging${v.m.step ? ` · ${v.m.step.replace(/^\d+ /, '')}` : ''}` }]),
    ...(s.tests.length ? [[{ t: '▸ ', c: C.build }, { t: `${s.tests.length} test run${s.tests.length > 1 ? 's' : ''}` }]] : []),
  ]
  const row3 = rest.flatMap((p, i) => [...(i ? [{ t: '   ' }] : []), ...p])
  // mini keeps row 1 and row 2 only.
  return (layoutOf(w) === 'mini' ? [row1, row2] : [row1, row2, row3]).filter(r => r.length).map(r => fitWidth(r, w))
}

// Open asks, today's merges and an unreadable work source keep every view up after the last unit finishes.
export const isIdle = (s: State) => !s.snap.rows.length && !s.merges.length && !s.tests.length && !readProblems(s).work.length
  && !s.snap.asks.length && !mergedToday(s).length

// /units prints into the transcript, so it takes the transcript's width rather than the pane's.
export const tableText = (s: State, w = 56) => (isIdle(s) ? 'No live units.' : paneLines(s, w).join('\n'))

// The status line, plain text (Claude Code draws no colour there): the worst open state leads.
export const summaryLine = (s: State, frame = 0): string | undefined => {
  if (isIdle(s)) return undefined
  const problems = workLine(s)
  const trouble = [
    ...(problems ? [`✗ ${problems}`] : []),
    ...s.merges.filter(v => v.status === 'refused').map(v => `✗ ${shortName(v.unit)} merge refused`),
    ...s.snap.rows.filter(r => r.red).map(r => `✗ ${shortName(r.unit)} at its prompt${r.ageSec !== null ? ` ${fmtSec(r.ageSec)}` : ''}`),
  ]
  const asks = s.snap.asks.length ? `◆ ${s.snap.asks.length} for owner` : ''
  const merged = mergedToday(s).length
  const counts = stageCounts(s)
  const lim = s.snap.limit
  const total = todayUsd(s)
  const tests = s.tests.length ? `▸ ${s.tests.length} testing` : ''
  const parts = trouble.length
    ? [...trouble, asks, [...counts.map(([, n]) => `${workMark(frame)} ${n}`), ...(merged ? [`✓ ${merged}`] : [])].join(' '), tests, lim ? `${Math.round(lim.pct)}%` : '', total > 0 ? (s.snap.day?.complete === false ? todayText(s) : usd(total)) : '']
    : [asks, ...counts.map(([st, n]) => `${workMark(frame)} ${n} ${st}`), merged ? `✓ ${merged} merged` : '', tests,
      lim ? `7d ${Math.round(lim.pct)}%${resetIn(lim.resetsAt, s.now, true) ? ` ↻${resetIn(lim.resetsAt, s.now, true)}` : ''}` : '', total > 0 ? todayText(s) : '']
  return parts.filter(Boolean).join(' · ') || undefined
}

// What to toast: a verdict that changed, or that a unit first seen since the last poll already holds; a unit that
// merged. The first poll (prev null) is silent; an unreadable snapshot never becomes prev (units.tsx collect).
export type Seen = { verdicts: Record<string, string>; merged: string[]; ended: string[] }

export const seenOf = (snap: Snap, endedMerges: string[]): Seen => ({
  verdicts: Object.fromEntries(snap.rows.map(r => [r.unit, `${r.verdictRound ?? r.round ?? ''}:${r.verdict ?? ''}`])),
  merged: snap.merged,
  ended: endedMerges,
})

export const toasts = (prev: Seen | null, cur: Seen): string[] => {
  if (!prev) return []
  const out: string[] = []
  for (const [u, v] of Object.entries(cur.verdicts)) if (v !== (prev.verdicts[u] ?? '') && v.split(':')[1]) out.push(`${u}: verdict ${v.replace(':', ' ')}`)
  // A finished merge reaches the mod twice, from its log and from the dashboard, at different polls: toast whichever comes first.
  const told = new Set([...prev.merged, ...prev.ended])
  for (const u of new Set([...cur.merged, ...cur.ended])) if (!told.has(u)) out.push(`${u}: ${cur.merged.includes(u) ? 'merged' : 'merge finished'}`)
  return out
}

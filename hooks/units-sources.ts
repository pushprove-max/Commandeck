// Pure parsers for the units mod. No `$` here: every function takes a whole file's text, so a log cut off mid-line, rewritten
// by a rerun, or noisy for 17,000 bytes gives the same counts as a clean one. Callers re-parse when size or mtime moves.

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
}
export type Costs = { plan: number; build: number; review: number; fix: number; total: number }
export type SeatState = 'done' | 'running' | null
// `chain` is always null: the plugin has no push-chain lane to show.
export type Snap = {
  note: string | null; staleMin: number | null; rows: Row[]; merged: string[]; mergedAt: { unit: string; at: number }[]; chain: null
  finishedUsd: Record<string, number>
  // The dashboard's Cost today for this project (`limit.today[<project>]`), split by folder; null when it has none.
  day: Day | null
}
// `merged` holds the units of finishedBuilds and mergedSincePush, the folders the split counts as merged.
export type Day = { total: number; byFolder: Record<string, number>; complete: boolean; merged: string[] }

// pp_standing_wt's folders, lowercased as dashboard.sh writes their stage: standing panes, never units.
export const NOT_UNITS = new Set(['chief-of-staff', 'fast-lane', 'research-lane'])
export const emptySnap = (note: string | null): Snap => ({ note, staleMin: null, rows: [], merged: [], mergedAt: [], chain: null, finishedUsd: {}, day: null })
const STAGE_COST: Record<string, keyof Costs> = { planning: 'plan', building: 'build', review: 'review', fixing: 'fix' }
const costsOf = (stages: any[]): Costs => {
  const c: Costs = { plan: 0, build: 0, review: 0, fix: 0, total: 0 }
  for (const x of stages) { const usd = Number(x?.usd) || 0; c.total += usd; const k = STAGE_COST[String(x?.stage)]; if (k) c[k] += usd }
  return c
}
const len = (v: unknown) => (Array.isArray(v) ? v.length : null)

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
  const rows: Row[] = u.inFlight.filter((x: any) => x && !NOT_UNITS.has(x.stage)).map((x: any) => {
    const b = x.builder
    const f = b?.findings?.sol ?? b?.findings
    const started = Date.parse(b?.startedAt ?? '')
    // dashboard.sh writes the cost to builder.cost once a Builder runs (planning first), to plan.cost before that.
    const costs = costsOf((b?.cost ?? x.plan?.cost)?.stages ?? [])
    return {
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
    }
  })
  // Every merge this checkout made is in finishedBuilds; mergedSincePush drops one once it is pushed, so a push would
  // take today's merges, and their spend, off the pane.
  const merged = (u.finishedBuilds ?? []).map((m: any) => ({ unit: String(m.unit), at: Date.parse(m.at ?? '') }))
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
    finishedUsd: Object.fromEntries((u.finishedBuilds ?? []).filter((f: any) => Number.isFinite(f?.cost?.total?.usd)).map((f: any) => [String(f.unit), Number(f.cost.total.usd)])),
    day,
  }
}

// Minutes and hours only: seconds churn every poll and say nothing a person acts on.
export const fmtSec = (s: number) => (s >= 3600 ? `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m` : `${Math.max(1, Math.floor(s / 60))}m`)
// A count is shown only when it is known: an unknown total gives "N files", never "N/?".
const counts = (p: Progress, total: number | null) => `${total ? `${p.done}/${total}` : `${p.done}`} files${p.failed ? ` · ${p.failed} failed (first ${p.firstFail})` : ''}`

export type MergeView = { unit: string; status: 'running' | 'stopped' | 'refused'; m: Merge; elapsedSec: number }
export type TestView = { owner: string; kind: string; p: Progress; total: number | null; elapsedSec: number }
export type Notes = { merges: string[]; tests: string[] }
export type State = { now: number; snap: Snap; merges: MergeView[]; tests: TestView[]; notes: Notes }

// One run of styled text; a line is a list of them. The plain text of every view is the same runs joined.
export type Seg = { t: string; c?: string; b?: boolean; d?: boolean }
export type Line = Seg[]
const C = { name: 'whiteBright', stage: 'cyan', ok: 'green', run: 'yellow', bad: 'red', head: 'blueBright' }
const plain = (l: Line) => l.map(x => x.t).join('')
const usd = (n: number) => `$${n.toFixed(2)}`

const STAGES: Record<string, string> = { planning: 'Planning', building: 'Building', fixing: 'Fixing', review: 'Review', 'waiting-main': 'Waiting on main', merging: 'Merging' }
const stageOf = (r: Row) => `${STAGES[r.stage] ?? r.stage.replace(/-/g, ' ').replace(/^./, c => c.toUpperCase())}${r.round ? ` r${r.round}` : ''}`
const bar = (done: number, of: number) => { const n = Math.min(10, Math.max(0, Math.round((done / of) * 10))); return '█'.repeat(n) + '░'.repeat(10 - n) }
const clockOf = (t: number) => new Date(t).toTimeString().slice(0, 5)
// The date suffix every unit name carries says nothing on a live board.
export const shortName = (u: string) => u.replace(/-\d{4}-\d{2}-\d{2}$/, '')
const since = (t: number | null, now: number) => (t ? fmtSec(Math.max(0, Math.round((now - t) / 1000))) : '')

// A plan's `Closes: issue 1, issue 2` (or `Closes: #1 #2`) line names the unit's issues before any Builder log does.
export const closesOf = (plan: string): string[] => (/^Closes:\s*(.+)$/m.exec(plan)?.[1].match(/#\d+|\bissue\s+\d+/gi) ?? []).map(x => `#${x.replace(/\D/g, '')}`)

// What is wrong with a unit, if anything, so a healthy unit carries no warning text.
const warnOf = (r: Row) => (r.red ? '⚠ at its prompt' : null)

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
const MARK: Record<Step, Seg> = { done: { t: '✓', c: C.ok }, running: { t: '◐', c: C.run }, todo: { t: '○', d: true } }

// Text on the left, a value pushed to the right edge of `w` columns.
const spread = (left: Line, right: Seg | null, w: number): Line => {
  if (!right) return left
  const gap = Math.max(2, w - plain(left).length - right.t.length)
  return [...left, { t: ' '.repeat(gap) }, right]
}

const unitModel = (r: Row, s: State, w: number, merging: boolean): Line[] => {
  const time = since(r.startedAt, s.now)
  const out: Line[] = [spread([{ t: '● ', c: C.stage }, { t: shortName(r.unit), c: C.name, b: true }], { t: `${stageOf(r)}${time ? ` · ${time}` : ''}`, c: C.stage }, w)]
  out.push([{ t: '  ' }, ...stepsOf(r, merging).flatMap(([n, st], i): Seg[] => [...(i ? [{ t: '  ' }] : []), { t: `${n} `, d: st === 'todo' }, MARK[st]])])
  const built = builtOf(r, merging)
  if (r.issues) out.push([{ t: '  ' }, { t: bar(built, r.issues), c: C.ok }, { t: `  ${built} of ${r.issues} issues built` }])
  else if (r.closes.length) out.push([{ t: `  ${r.closes.join(' ')}`, d: true }])
  const verdict: Line = r.verdict
    ? [{ t: `  r${r.verdictRound ?? r.round ?? ''} ` }, { t: r.verdict, c: r.verdict === 'GO' ? C.ok : C.bad, b: true }, ...(r.findings ? [{ t: ` · ${r.findings}` }] : [])]
    : [{ t: '' }]
  if (r.verdict || r.costs.total > 0) out.push(spread(verdict, r.costs.total > 0 ? { t: usd(r.costs.total), b: true } : null, w))
  const parts = (['plan', 'build', 'review', 'fix'] as const).filter(k => r.costs[k] > 0).map(k => `${k} ${usd(r.costs[k])}`)
  if (parts.length > 1) out.push([{ t: `  ${parts.join(' · ')}`, d: true }])
  const warn = warnOf(r)
  if (warn) out.push([{ t: `  ${warn}`, c: C.bad, b: true }])
  return out
}

const mergeModel = (v: MergeView, w: number): Line =>
  v.status === 'refused' ? [{ t: '✗ ', c: C.bad }, { t: shortName(v.unit), c: C.name, b: true }, { t: `  refused at ${v.m.refused?.step}: ${v.m.refused?.reason}`, c: C.bad }]
    : v.status === 'stopped' ? [{ t: '✗ ', c: C.bad }, { t: shortName(v.unit), c: C.name, b: true }, { t: `  stopped${v.m.step ? ` at ${v.m.step}` : ''}, no result`, c: C.bad }]
      : spread([{ t: '◐ ', c: C.run }, { t: shortName(v.unit), c: C.name, b: true }, { t: `  ${v.m.step ? v.m.step.replace(/^\d+ /, '') : 'merging'}${v.m.done || v.m.total ? ` ${counts(v.m, v.m.total)}` : ''}` }], { t: fmtSec(v.elapsedSec), d: true }, w)

const testModel = (v: TestView, w: number): Line =>
  spread([{ t: '▸ ', c: C.run }, { t: shortName(v.owner), c: C.name, b: true }, { t: `  ${v.kind} ${counts(v.p, v.total)}`, c: v.p.failed ? C.bad : undefined }], { t: fmtSec(v.elapsedSec), d: true }, w)

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

// The pane and /units: a header, then sections drawn only when they hold something.
export const paneModel = (s: State, w: number): Line[] => {
  const out: Line[] = []
  const merging = new Set(s.merges.filter(v => v.status === 'running').map(v => v.unit))
  const head = (title: string, right: Seg | null) => { if (out.length) out.push([]); out.push(spread([{ t: title, c: C.head, b: true }], right, w)) }
  const total = todayUsd(s)
  out.push(spread([{ t: 'UNITS', c: C.head, b: true }], total > 0 ? { t: todayText(s), b: true } : null, w))
  const split = todaySplit(s)
  if (split.length) out.push([{ t: `  ${split.map(([k, n]) => `${k} ${usd(n)}`).join(' · ')}`, d: true }])
  else if (total > 0 && !s.snap.day) out.push([{ t: '  units only', d: true }])
  if (s.snap.rows.length) { head(`BUILDING  ${s.snap.rows.length}`, null); for (const r of s.snap.rows) out.push(...unitModel(r, s, w, merging.has(r.unit))) }
  if (s.merges.length) { head(`MERGING  ${s.merges.length}`, null); out.push(...s.merges.map(v => mergeModel(v, w))) }
  if (s.tests.length) { head('TESTS', null); out.push(...s.tests.map(v => testModel(v, w))) }
  const today = mergedToday(s)
  if (today.length) {
    const sum = today.reduce((n, m) => n + (s.snap.finishedUsd[m.unit] ?? 0), 0)
    head(`MERGED TODAY  ${today.length}`, sum > 0 ? { t: usd(sum), b: true } : null)
    for (const m of today) {
      const cost = s.snap.finishedUsd[m.unit]
      out.push(spread([{ t: '✓ ', c: C.ok }, { t: shortName(m.unit).padEnd(22), d: true }, { t: clockOf(m.at), d: true }], cost ? { t: usd(cost), d: true } : null, w))
    }
  }
  const notes = [s.snap.note ?? (s.snap.staleMin ? `dashboard data is ${s.snap.staleMin} min old` : null), ...s.notes.merges, ...s.notes.tests]
  const shown = notes.filter((n): n is string => !!n)
  if (shown.length) { head('CANNOT READ', null); out.push(...shown.map((n): Line => [{ t: `⚠ ${n}`, c: C.bad }])) }
  return out
}

export const paneLines = (s: State, w = 56): string[] => paneModel(s, w).map(plain)

// The band: one row, one short segment per live thing.
export const bandModel = (s: State): Line => {
  const merging = new Set(s.merges.filter(v => v.status === 'running').map(v => v.unit))
  const parts: Line[] = [
    ...s.snap.rows.map((r): Line => {
      const warn = warnOf(r)
      return [{ t: '● ', c: C.stage }, { t: shortName(r.unit), c: C.name, b: true }, { t: ` ${stageOf(r)}`, c: C.stage },
        ...(r.issues ? [{ t: ` ${builtOf(r, merging.has(r.unit))}/${r.issues}` }] : []), ...(r.startedAt ? [{ t: ` ${since(r.startedAt, s.now)}`, d: true }] : []),
        ...(warn ? [{ t: ` ${warn}`, c: C.bad, b: true }] : [])]
    }),
    // A stopped or refused merge shows in the side pane only; the band lists live merges.
    ...s.merges.filter(v => v.status === 'running').map((v): Line =>
      [{ t: '◐ ', c: C.run }, { t: shortName(v.unit), c: C.name, b: true }, { t: ` merging${v.m.step ? ` · ${v.m.step.replace(/^\d+ /, '')}` : ''}` }]),
    ...(s.tests.length ? [[{ t: '▸ ', c: C.run }, { t: `${s.tests.length} test run${s.tests.length > 1 ? 's' : ''}` }]] : []),
    ...(s.snap.note ? [[{ t: `⚠ ${s.snap.note}`, c: C.bad }]] : []),
  ]
  return parts.flatMap((p, i) => [...(i ? [{ t: '   ' }] : []), ...p])
}
export const bandLine = (s: State) => plain(bandModel(s))

export const isIdle = (s: State) => !s.snap.rows.length && !s.merges.length && !s.tests.length && !s.snap.note && !s.notes.merges.length && !s.notes.tests.length

export const tableText = (s: State) => (isIdle(s) ? 'No live units.' : paneLines(s).join('\n'))

// The status line: counts and today's spend; the plugin's name already labels it.
export const summaryLine = (s: State): string | undefined => {
  if (isIdle(s)) return undefined
  const total = todayUsd(s)
  const parts = [
    s.snap.rows.length ? `${s.snap.rows.length} building` : '',
    s.merges.length ? `${s.merges.length} merging` : '',
    s.tests.length ? `${s.tests.length} testing` : '',
    s.snap.note ? 'dashboard unreadable' : '',
    total > 0 ? todayText(s) : '',
  ]
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

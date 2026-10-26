import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'
import {
  bandModel, closesOf, emptySnap, isIdle, newestAttempt, paneModel, parseMergeLog, parseSnapshot, parseTestLive, seatFromGit, seenOf,
  summaryLine, tableText, toasts,
} from './units-sources'
import type { Line, MergeView, Row, Seen, SeatState, Snap, State, TestView } from './units-sources'
import { setStatus } from './status-line'

// Live units, merges and test runs, read from files the scripts already write. The mod writes nothing: its only state is
// atoms (what the views draw) and in-memory caches.
const state = atom({ plugin: 'commandeck', key: 'unitsState' } as const, null)
const view = atom({ plugin: 'commandeck', key: 'unitsView' } as const, { band: false, pane: false, status: false })

type Paths = { main: string; scratch: string; workspaces: string; home: string; gitDir: string; project: string }
type Views = 'band' | 'pane' | 'status'
type Dir = Awaited<ReturnType<EngineInterface['fs']['list']>>

const POLL_MS = 5000
const MAX_SNAP = 4_000_000
const MAX_LOG = 8_000_000
const RECENT_S = 3 * 3600
const PLACEHOLDER = 'units: no dashboard snapshot (scripts/dashboard.sh --install)'
const PANE = 'units'

let paths: Paths | undefined
let stopPoll: (() => void) | undefined
let seatName: 'main' | 'chiefOfStaff' | 'worker' = 'worker'
let overrides: Partial<Record<Views, boolean>> = {}
let lastJson = ''
let paneUp = false
let prevSeen: Seen | null = null
const cache = new Map<string, { key: string; value: unknown }>()
let option: Record<Views, string> = { band: 'auto', pane: 'auto', status: 'auto' }

const wanted = (v: Views) => overrides[v] ?? (option[v] === 'on' ? true : option[v] === 'off' ? false : seatName !== 'worker')

// A log is parsed again only when its size or mtime moved; one over the cap shows a placeholder instead of being read.
async function parsed<T>($: EngineInterface, path: string, size: number, mtimeMs: number, parse: (text: string) => T): Promise<T | { big: number }> {
  if (size > MAX_LOG) return { big: Math.round(size / 1e6) }
  const key = `${size}:${mtimeMs}`
  const hit = cache.get(path)
  if (hit?.key === key) return hit.value as T
  const value = parse((await $.fs.read(path)) as string)
  cache.set(path, { key, value })
  return value
}
const isBig = (v: unknown): v is { big: number } => typeof v === 'object' && v !== null && 'big' in v

function listing($: EngineInterface, dir: string): Promise<Dir> {
  return $.fs.list(dir).catch(() => [])
}

// The plugin's own scripts/paths.sh names the project's folders, so the mod and the scripts agree on them. A hooks module
// may import only "claude-code" and its own files, so the root (this file's folder's parent) comes from the URL alone.
const PLUGIN_ROOT = decodeURIComponent(new URL('..', import.meta.url).pathname).replace(/\/+$/, '')
const LOAD = '. "$1/scripts/paths.sh" && . "$1/hooks/lib/project.sh" && pp_project "$PP_MAIN" && printf "%s\\n" "$PP_MAIN" "$PP_SCRATCH" "$PP_WORKSPACES" "$HOME" "$(git -C "$PP_MAIN" rev-parse --path-format=absolute --git-common-dir)" "$PP_PROJECT"'

async function loadPaths($: EngineInterface, main: string): Promise<Paths | undefined> {
  const r = await $.process.run(['bash', '-c', LOAD, '_', PLUGIN_ROOT], { cwd: main })
  const [m, scratch, workspaces, home, gitDir, project] = r.stdout.split('\n')
  return r.exitCode === 0 && m && scratch && workspaces && home && gitDir && project ? { main: m, scratch, workspaces, home, gitDir, project } : undefined
}

async function readSnapshot($: EngineInterface, p: Paths, now: number): Promise<Snap> {
  const file = `${p.home}/.commandeck/dashboard/data.js`
  const st = await $.fs.stat(file).catch(() => undefined)
  if (!st) return emptySnap(PLACEHOLDER)
  if (st.size > MAX_SNAP) return emptySnap('units: snapshot too big')
  const key = `${st.size}:${st.mtimeMs}`
  const hit = cache.get(file)
  const base = hit?.key === key ? (hit.value as { text: string }) : { text: (await $.fs.read(file)) as string }
  if (hit?.key !== key) cache.set(file, { key, value: base })
  return parseSnapshot(base.text, now, p.project)
}

// A planning seat leaves `$PP_SCRATCH/seat-<unit>-<role>.txt`. A record with a `verdict=` line is done; without one it
// runs until its last `phase=` is `failed`, and a seat whose launch failed says nothing. A seat whose pane died before
// collect reads running (its record keeps no live pid). Running wins over done.
async function seatState($: EngineInterface, p: Paths, scr: Dir, prefix: string): Promise<SeatState> {
  let found: SeatState = null
  for (const e of scr.filter(x => x.name.startsWith(prefix) && x.name.endsWith('.txt'))) {
    const rec = await parsed($, `${p.scratch}/${e.name}`, e.size, e.mtimeMs, text => ({ done: /^verdict=/m.test(text), failed: [...text.matchAll(/^phase=(.*)$/gm)].at(-1)?.[1] === 'failed' })).catch(() => undefined)
    if (!rec || isBig(rec)) continue
    if (rec.done) found = found ?? 'done'
    else if (!rec.failed) return 'running'
  }
  return found
}

// What the snapshot does not carry for a unit still planning: when its worktree was made (Orca writes `.git` then), the
// issues its plan closes and its seats. Each stays unset when its file is absent, so nothing unknown is drawn.
async function enrich($: EngineInterface, p: Paths, r: Row, scr: Dir): Promise<Row> {
  const wt = `${p.workspaces}/${r.unit}`
  const planning = r.stage === 'planning'
  const plan = planning ? await seatState($, p, scr, `seat-${r.unit}-plan-author`) : null
  const judges = planning ? await seatState($, p, scr, `seat-${r.unit}-plan-judge`) : null
  const startedAt = r.startedAt ?? (await $.fs.stat(`${wt}/.git`).then(st => st.mtimeMs, () => null))
  const planFile = `${wt}/.claude/plans/${r.unit}.md`
  const st = await $.fs.stat(planFile).catch(() => undefined)
  const closes = st ? await parsed($, planFile, st.size, st.mtimeMs, closesOf).catch(() => []) : []
  return { ...r, startedAt, closes: isBig(closes) ? [] : closes, plan, judges }
}

type Found<T> = { views: T[]; notes: string[] }
type Held = { unit: string; pid: string; stage: string; started: number; mtimeMs: number }

async function alive($: EngineInterface, pid: string): Promise<boolean> {
  return /^\d+$/.test(pid) && (await $.process.run(['kill', '-0', pid]).catch(() => undefined))?.exitCode === 0
}

// merge-unit-local.sh writes `<git dir>/merge-unit-local.state` while a merge holds main and removes it on every way out.
async function readHeld($: EngineInterface, p: Paths): Promise<Held | null> {
  const file = `${p.gitDir}/merge-unit-local.state`
  const st = await $.fs.stat(file).catch(() => undefined)
  const text = st ? await $.fs.read(file).catch(() => undefined) : undefined
  if (!st || typeof text !== 'string') return null
  const f = (k: string) => new RegExp(`^${k}=(.*)$`, 'm').exec(text)?.[1] ?? ''
  return { unit: f('unit'), pid: f('pid'), stage: f('stage'), started: Number(f('started')), mtimeMs: st.mtimeMs }
}

// A request waiting on the lock leaves `<git dir>/merge-unit-local.queue/<unit>@<sha>`, holding its pid.
async function readQueue($: EngineInterface, p: Paths): Promise<Map<string, string[]>> {
  const dir = `${p.gitDir}/merge-unit-local.queue`
  const by = new Map<string, string[]>()
  for (const e of await listing($, dir)) {
    if (!e.name.includes('@')) continue
    const pid = ((await $.fs.read(`${dir}/${e.name}`).catch(() => '')) as string).trim()
    by.set(e.name.slice(0, e.name.lastIndexOf('@')), [...(by.get(e.name.slice(0, e.name.lastIndexOf('@'))) ?? []), pid])
  }
  return by
}

// Per unit, the first rule that matches wins (docs/dashboard.md, "Units mod"): 1 a state naming the unit with a live pid is
// running; 2 a queue entry with a live pid is running (no step yet); 3 a recent state with a dead pid is stopped; 4-6 with no
// state, a recent log's newest attempt is ended (DONE), refused (FAILED) or stopped (neither); 7 otherwise nothing. The state
// decides first because the merge removes it on every way out; the log is read from its last ATTEMPT line only.
async function readMerges($: EngineInterface, p: Paths, now: number): Promise<Found<MergeView> & { ended: string[]; units: Set<string> }> {
  const out = { views: [] as MergeView[], notes: [] as string[], ended: [] as string[], units: new Set<string>() }
  const held = await readHeld($, p)
  const queue = await readQueue($, p)
  const logs = new Map((await listing($, p.scratch)).map(e => [/^merge-(.+)\.log$/.exec(e.name)?.[1], e] as const).filter((x): x is [string, Dir[number]] => !!x[0]))
  const recent = (mtimeMs: number) => (now - mtimeMs) / 1000 < 3600
  const none = parseMergeLog('')
  const names = new Set([...logs.keys(), ...(held?.unit ? [held.unit] : []), ...queue.keys()])
  for (const unit of names) {
    try {
      const st = held?.unit === unit ? held : null
      const log = logs.get(unit)
      const stLive = st ? await alive($, st.pid) : false
      const stOld = !!st && !stLive && !recent(st.mtimeMs)
      const attempt = async () => {
        if (!log || !recent(log.mtimeMs)) return null
        const a = await parsed($, `${p.scratch}/${log.name}`, log.size, log.mtimeMs, text => newestAttempt(text, unit))
        return isBig(a) ? a : a && { ...a, m: parseMergeLog(a.text) }
      }
      if (st && stLive) {
        const a = await attempt()
        if (a && isBig(a)) { out.notes.push(`merge ${unit}: log too big (${a.big} MB)`); continue }
        out.units.add(unit)
        out.views.push({ unit, status: 'running', m: { ...(a && a.pid === st.pid ? a.m : none), step: st.stage }, elapsedSec: Math.max(0, Math.round(now / 1000 - st.started)) })
        continue
      }
      let queued = false
      for (const pid of queue.get(unit) ?? []) if (await alive($, pid)) queued = true
      if (queued) { out.units.add(unit); out.views.push({ unit, status: 'running', m: none, elapsedSec: 0 }); continue }
      if (st && !stOld) { out.views.push({ unit, status: 'stopped', m: { ...none, step: st.stage }, elapsedSec: 0 }); continue }
      const a = await attempt()
      if (!a) continue
      if (isBig(a)) { out.notes.push(`merge ${unit}: log too big (${a.big} MB)`); continue }
      if (a.m.ended) out.ended.push(unit)
      else out.views.push({ unit, status: a.m.refused ? 'refused' : 'stopped', m: a.m, elapsedSec: 0 })
    } catch { out.notes.push(`merge ${unit}: log unreadable`) }
  }
  return out
}

const ownerOf = (root: string | null, p: Paths) => (root === p.main ? 'main' : root?.startsWith(`${p.workspaces}/`) ? root.slice(p.workspaces.length + 1).split('/')[0] : null)

// The runner's live tables: main's own, and each worktree's, owned by the unit whose folder the worktree is. A worktree
// outside the workspaces folder (the merge's copy of the merged tree) is skipped, so a merge's check draws no second row.
async function readTests($: EngineInterface, p: Paths, now: number, merging: Set<string>): Promise<Found<TestView>> {
  const out: Found<TestView> = { views: [], notes: [] }
  const tsvs: { dir: string; owner: string; name: string; size: number; mtimeMs: number }[] = []
  const gitDirs = [{ dir: p.gitDir, owner: 'main' }]
  for (const w of await listing($, `${p.gitDir}/worktrees`)) {
    const root = ((await $.fs.read(`${p.gitDir}/worktrees/${w.name}/gitdir`).catch(() => '')) as string).trim().replace(/\/\.git$/, '')
    const owner = ownerOf(root, p)
    if (owner) gitDirs.push({ dir: `${p.gitDir}/worktrees/${w.name}`, owner })
  }
  for (const g of gitDirs) {
    for (const e of await listing($, `${g.dir}/commandeck-test-live`)) {
      if (e.name.endsWith('.tsv') && (now - e.mtimeMs) / 1000 < RECENT_S) tsvs.push({ dir: `${g.dir}/commandeck-test-live`, owner: g.owner, name: e.name, size: e.size, mtimeMs: e.mtimeMs })
    }
  }
  const pids = tsvs.map(x => Number.parseInt(x.name, 10)).filter(n => Number.isFinite(n))
  if (!pids.length) return out
  const ps = await $.process.run(['ps', '-o', 'pid=', '-p', pids.join(',')]).catch(() => undefined)
  const live = new Set((ps?.stdout ?? '').split(/\s+/).filter(Boolean).map(Number))
  for (const x of tsvs) {
    if (!live.has(Number.parseInt(x.name, 10)) || merging.has(x.owner)) continue
    const run = await parsed($, `${x.dir}/${x.name}`, x.size, x.mtimeMs, parseTestLive).catch(() => null)
    if (!run) { out.notes.push(`tests ${x.name}: table unreadable`); continue }
    if (isBig(run)) continue
    out.views.push({ owner: x.owner, kind: 'shell', p: run, total: run.total, elapsedSec: Math.max(0, Math.round(now / 1000 - run.startedAt)) })
  }
  return out
}

// One poll. Every source fails soft: a log read that throws drops only its own row and leaves a note, never the prompt.
async function collect($: EngineInterface, p: Paths): Promise<State> {
  const now = await $.clock.now()
  const raw = await readSnapshot($, p, now).catch(() => emptySnap('units: snapshot unreadable'))
  const scr = await listing($, p.scratch)
  const snap = { ...raw, rows: await Promise.all(raw.rows.map(r => enrich($, p, r, scr))) }
  const m = await readMerges($, p, now).catch(() => ({ views: [], notes: [], ended: [], units: new Set<string>() }))
  const t = await readTests($, p, now, m.units).catch((): Found<TestView> => ({ views: [], notes: [] }))
  const st: State = { now, snap, merges: m.views, tests: t.views, notes: { merges: m.notes, tests: t.notes } }
  if (!snap.note) {
    const cur = seenOf(snap, m.ended)
    if (wanted('status')) for (const text of toasts(prevSeen, cur)) $.ui.toast(text)
    prevSeen = cur
  }
  return st
}

// Polls and /units calls run one after another: a slow collection must not publish after a newer one.
let queue: Promise<unknown> = Promise.resolve()
function tick($: EngineInterface): Promise<void> {
  const run = queue.catch(() => undefined).then(() => poll($))
  queue = run
  return run
}

async function poll($: EngineInterface) {
  if (!paths) return
  const st = await collect($, paths)
  const json = JSON.stringify(st)
  if (json !== lastJson) {
    lastJson = json
    await update($, state, () => st)
  }
  await showPane($, wanted('pane') && !isIdle(st))
  setStatus($, 'units', wanted('status') ? summaryLine(st) : undefined)
}

// The pane is open only while it is wanted and has something to show: with no live units every view draws nothing
// (Decision G10-2), so a poll that finds the last unit gone closes it.
async function showPane($: EngineInterface, up: boolean) {
  if (up === paneUp) return
  paneUp = up
  if (up) await $.ui.open({ id: PANE, title: 'Units' })
  else await $.ui.close({ id: PANE })
}

// A view turned off goes at once; one turned on comes with the next poll's content.
async function setViews($: EngineInterface) {
  const v = { band: wanted('band'), pane: wanted('pane'), status: wanted('status') }
  await update($, view, () => v)
  if (!v.pane) await showPane($, false)
  if (!v.status) setStatus($, 'units', undefined)
}

// The session start of the units views. The engine takes one hooks module per plugin and refuses a second
// session.start with no matcher, so autodecide.tsx's handler calls this one first. It registers nothing outside a
// Commandeck project: the plugin applies to every project on the profile, and setup writes .claude/commandeck.json in
// the ones it set up. A failure here never stops the next feature's start.
export async function startUnits($: EngineInterface): Promise<void> {
  try {
    const root = await $.session.root()
    const git = await $.process.run(['git', '-C', root, 'rev-parse', '--path-format=absolute', '--git-dir', '--git-common-dir', '--show-toplevel'])
    const seat = git.exitCode === 0 ? seatFromGit(git.stdout) : null
    if (!seat || !(await $.fs.stat(`${seat.main}/.claude/commandeck.json`).catch(() => undefined))) return
    seatName = seat.seat
    overrides = {}
    cache.clear()
    prevSeen = null
    lastJson = ''
    paneUp = false
    paths = await loadPaths($, seat.main).catch(() => undefined)
    await $.command.register({ name: 'units', description: 'Live units, merges and test runs: /units, or /units band|pane|status on|off' })
    await setViews($)
    if (!paths) {
      setStatus($, 'units', 'units: paths unreadable')
      return
    }
    stopPoll?.()
    stopPoll = $.clock.every(POLL_MS, () => void tick($).catch(() => undefined))
    await tick($).catch(() => undefined)
  } catch {
    return
  }
}

export function registerUnits(on: Parameters<Register>[0], options: Parameters<Register>[1]): void {
  option = { band: String(options.unitsBand ?? 'auto'), pane: String(options.unitsPane ?? 'auto'), status: String(options.unitsStatus ?? 'auto') }

  on('command.run', { command: 'units' }, async ($, e, next) => {
    if (!paths) return next(e)
    const [which, flip] = e.args.trim().toLowerCase().split(/\s+/)
    if (which === 'band' || which === 'pane' || which === 'status') {
      overrides[which] = flip !== 'off'
      await setViews($)
      await tick($)
      return { text: `units ${which}: ${overrides[which] ? 'on' : 'off'} for this session` }
    }
    await tick($)
    return { text: tableText(await read($, state) as State | null ?? emptyState()) }
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const v = await read($, view)
    const s = (await read($, state)) as State | null
    if (!v.band || !s || isIdle(s)) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    return <Box flexDirection="row">{draw(Text, bandModel(s), 'b')}</Box>
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e, next) => {
    const s = (await read($, state)) as State | null
    const { Box, Text } = $.ui.resolve(e)
    if (!s || isIdle(s)) return <Text dimColor>No live units.</Text>
    const w = Math.max(40, Math.min(72, Number(e.props.bodyColumns) || 56))
    return (
      <Box flexDirection="column">
        {paneModel(s, w).map((l, i) => <Box key={`p${i}`} flexDirection="row">{l.length ? draw(Text, l, `p${i}`) : <Text> </Text>}</Box>)}
      </Box>
    )
  }).catch(($, e, next) => next(e))
}

// Each styled run is its own Text, so one line carries several colours.
const draw = (Text: any, line: Line, key: string) => line.map((x, i) => <Text key={`${key}-${i}`} color={x.c} bold={x.b} dimColor={x.d}>{x.t}</Text>)

const emptyState = (): State => ({ now: 0, snap: emptySnap(null), merges: [], tests: [], notes: { merges: [], tests: [] } })

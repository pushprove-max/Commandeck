import { mock } from 'claude-code/testing'
import type { On } from 'claude-code'

// Fixtures shared by units.test.tsx and units-panes.test.tsx: each hook stands for the engine, over an in-memory disk and process table.

export const MAIN = '/r/main'
export const WS = '/r/ws'
export const SCR = '/r/scratch'
export const TMP = '/r/tmp'
export const HOME = '/r/home'
export const GIT = `${MAIN}/.git`
export const NOW = Date.UTC(2026, 9, 25, 15, 5, 0)
export const DATA = `${HOME}/.commandeck/dashboard/data.js`
export const STATE = `${GIT}/merge-unit-local.state`
export const QUEUE = `${GIT}/merge-unit-local.queue`
export const LOG = `${SCR}/merge-u.log`
export const ROOT = decodeURIComponent(new URL('..', import.meta.url).pathname).replace(/\/+$/, '')
export const SESSION = { surface: 'terminal', isInteractive: true } as const
export const SEATS = { main: [GIT, MAIN], cos: [`${GIT}/worktrees/c`, `${WS}/Chief-of-Staff`], worker: [`${GIT}/worktrees/u`, `${WS}/u`] }

export type World = { files: Map<string, { text: string; at: number }>; runs: string[][]; status: (string | undefined)[]; toasts: string[]; registered: string[]; opened: string[]; live: Set<number>; clock: ReturnType<typeof mock.clock>; beforeRead?: (path: string) => Promise<void> | void }

export const unit = (name: string, extra: object = {}, builder: object | null = {}) => ({
  unit: name, stage: 'building', agents: 'claude:working', ageSec: 0, round: null,
  builder: builder && { verdict: null, verdictRound: null, findings: null, cost: { stages: [{ usd: 1 }] }, ...builder }, ...extra,
})
// The dashboard's envelope: this project's units sit under projects.<name>.units.
export const snap = (inFlight: object[], units: object = {}) =>
  `window.DASH = ${JSON.stringify({ updatedAt: '2026-10-25T15:04:30Z', home: 'p', projects: { p: { path: '/repo', units: { inFlight, mergedSincePush: [], ...units } } } })};`

export const world = (on: On, seat: keyof typeof SEATS, files: Record<string, string> = {}, installed = true): World => {
  const clock = mock.clock(on, { now: NOW })
  const w: World = { files: new Map(), runs: [], status: [], toasts: [], registered: [], opened: [], live: new Set(), clock }
  for (const [p, text] of Object.entries(files)) w.files.set(p, { text, at: NOW - 1000 })
  if (installed) w.files.set(`${MAIN}/.claude/commandeck.json`, { text: '{"version": 1}', at: 0 })
  const [gitDir, top] = SEATS[seat]
  on('session.root', () => ({ value: top }))
  on('session.cwd', () => ({ value: top }))
  const out = (stdout: string, exitCode = 0) => ({ value: { exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } })
  on('process.run', (_, e) => {
    w.runs.push([...e.argv])
    const [cmd, ...rest] = e.argv
    if (cmd === 'git') return out(`${gitDir}\n${GIT}\n${top}\n`)
    if (cmd === 'bash') return out(`${MAIN}\n${SCR}\n${WS}\n${HOME}\n${GIT}\np\n`)
    if (cmd === 'kill') return out('', w.live.has(Number(rest[1])) ? 0 : 1)
    if (cmd === 'ps') return out([...w.live].join('\n'))
    return out('')
  })
  const dirOf = (dir: string) => {
    const names = new Map<string, { kind: 'file' | 'dir'; size: number; mtimeMs: number }>()
    for (const [p, f] of w.files) {
      if (!p.startsWith(`${dir}/`)) continue
      const rest = p.slice(dir.length + 1)
      const name = rest.split('/')[0]
      names.set(name, rest.includes('/') ? { kind: 'dir', size: 0, mtimeMs: 0 } : { kind: 'file', size: f.text.length, mtimeMs: f.at })
    }
    return [...names].map(([name, v]) => ({ name, ...v, isLink: false }))
  }
  on('fs.list', (_, e) => ({ value: dirOf(e.path ?? '') }))
  on('fs.read', async (_, e) => {
    const f = w.files.get(e.path)
    await w.beforeRead?.(e.path)
    if (!f) throw new Error(`ENOENT ${e.path}`)
    return { value: f.text }
  })
  on('fs.stat', (_, e) => {
    const f = w.files.get(e.path)
    if (!f) throw new Error(`ENOENT ${e.path}`)
    return { value: { kind: 'file', size: f.text.length, mtimeMs: f.at, isLink: false } }
  })
  on('ui.status', (_, e) => (w.status.push(e.text), { value: undefined }))
  on('ui.toast', (_, e) => (w.toasts.push(e.text), { value: undefined }))
  on('ui.open', (_, e) => (w.opened.push(e.id), { value: { isPlaced: true } }))
  on('ui.close', (_, e) => (w.opened.splice(w.opened.indexOf(e.id), 1), { value: undefined }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('command.register', (_, e) => (w.registered.push(e.name), { value: { command: e.name } }))
  on('ui.render', ($, e) => ({ ...$.ui.resolve(e).Text({ children: 'engine' }) }))
  on('command.run', () => ({ text: 'engine' }))
  return w
}

export const start = ($: any, seat: keyof typeof SEATS) => $.session.start({ cwd: SEATS[seat][1], ...SESSION })
export const units = ($: any, args = '') => $.command.run({ command: 'units', args, origin: { kind: 'composer' }, presentation: { layout: 'main', columns: 100 } }).then((r: any) => r.text as string)
export const draw = async ($: any, component: 'AbovePrompt' | 'Pane') => {
  const ui = await $.ui.mount({ plugin: 'commandeck', surface: 'terminal', component, requestId: component === 'Pane' ? 'units' : 'band', props: component === 'Pane' ? { title: 'Units', isFocused: false, bodyColumns: 80, placement: 'dock' } : { hasSurvey: false } })
  const texts = ((await ui.findAll({ type: 'Text' })) as { text: string }[]).map(t => t.text)
  await ui.unmount()
  return texts
}
export const quiet = { options: { unitsBand: 'on', unitsPane: 'on', unitsStatus: 'on' } }
export const table = (...lines: string[]) => `${lines.join('\n')}\n`

// The files a merge leaves: its state, a queue entry, and one log that may hold many attempts (each opens with ATTEMPT).
export const state = (pid: number, stage = 'rebase') => `unit=u\nsha=abc\ntip=abc\npid=${pid}\nstarted=${NOW / 1000 - 10}\nstage=${stage}\nmain=${MAIN}\nlog=${LOG}\n`
export const attempt = (pid: number) => `ATTEMPT unit=u pid=${pid} started=${NOW / 1000 - 20}\n`
export const DONE = 'DONE unit=u merged=local sha=abc\n'
export const REFUSED = 'FAILED step 3 record: review ledger has no GO\n'

// A merge case: the session starts with a bare dashboard, then the merge's files appear (ages in seconds, default 1), so
// the first poll is silent and a toast is a change the mod saw. Returns the world and /units after two polls.
export const merging = async ($: any, on: On, files: Record<string, string>, live: number[] = [], ages: Record<string, number> = {}) => {
  const w = world(on, 'main', { [DATA]: snap([]) })
  w.live = new Set(live)
  await start($, 'main')
  for (const [p, text] of Object.entries(files)) w.files.set(p, { text, at: NOW - (ages[p] ?? 1) * 1000 })
  await w.clock.advance(5000)
  return { w, text: await units($) }
}
export const band = async ($: any) => (await draw($, 'AbovePrompt')).join('')

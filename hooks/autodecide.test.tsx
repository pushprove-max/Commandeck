import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

// Auto-decide decides for the owner while they are away, so what these pin is the safety around it: only a listed
// seat reads the mode, it survives a restart and only `off` ends it, a visible band says so, the picker is blocked
// while it is on (and let through when the guard breaks), and every run leaves a log the owner can judge.
// Nothing sits beneath the plugin: each hook below stands for the engine, over an in-memory disk and store.

const MAIN = '/w/proj'
const RELAY = '/w/Chief-of-Staff'
const LOG = `${MAIN}/.claude/metrics/autodecide-2026-10-24-0930.md`
const ON = `${MAIN}/.claude/metrics/autodecide.on`
const SESSION = { surface: 'terminal', isInteractive: true } as const

type World = { files: Map<string, string>; store: Map<string, unknown>; runs: string[][]; status: string[]; registered: string[]; isStoreDown: boolean; isToolDown: boolean; executions: number; racing?: string; pending?: string }

// seat: the relay's worktree (its git dir is not the common dir), main's checkout (it is), or a Builder's worktree.
const world = (on: On, seat: 'relay' | 'main' | 'builder', files: Record<string, string> = {}): World & { root: string } => {
  const w: World = { files: new Map(Object.entries(files)), store: new Map(), runs: [], status: [], registered: [], isStoreDown: false, isToolDown: false, executions: 0 }
  const root = seat === 'relay' ? RELAY : seat === 'main' ? MAIN : '/w/unit-1'
  const gitDir = seat === 'main' ? `${MAIN}/.git` : `${MAIN}/.git/worktrees/x`
  on('session.root', () => ({ value: root }))
  on('session.cwd', () => ({ value: root }))
  // racing: a log entry relay-order.sh --auto appends once the mode file is removed, landing before the next
  // write to that log (or right after the next read of it): an --auto run that read the mode file before `off` did.
  const land = (path: string) => {
    if (w.pending === undefined || !w.files.has(path)) return
    w.files.set(path, `${w.files.get(path)}${w.pending}`)
    w.pending = undefined
  }
  on('process.run', (_, e) => {
    w.runs.push([...e.argv])
    const [cmd, ...rest] = e.argv
    if (cmd === 'rm' && w.racing !== undefined) [w.pending, w.racing] = [w.racing, undefined]
    if (cmd === 'tee' && rest[0] === '-a') {
      land(rest[1] as string)
      w.files.set(rest[1] as string, `${w.files.get(rest[1] as string) ?? ''}${e.init?.stdin ?? ''}`)
    }
    const value = (stdout: string) => ({ value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } })
    if (cmd === 'git') return value(`${gitDir}\n${MAIN}/.git\n${root}\n`)
    if (cmd === 'date') return value('2026-10-24|09:30|2026-10-24-0930\n')
    if (cmd === 'rm') w.files.delete(rest[rest.length - 1] as string)
    return value('')
  })
  on('fs.read', (_, e) => {
    if (!w.files.has(e.path)) throw new Error(`ENOENT ${e.path}`)
    const text = w.files.get(e.path) as string
    land(e.path)
    return { value: text }
  })
  on('fs.write', (_, e) => {
    land(e.path)
    w.files.set(e.path, e.text)
    return { value: undefined }
  })
  on('store.get', (_, e) => {
    if (w.isStoreDown) throw new Error('store down')
    return { value: w.store.get(e.key) }
  })
  on('store.set', (_, e) => {
    w.store.set(e.key, e.value)
    return { value: undefined }
  })
  on('store.delete', (_, e) => {
    w.store.delete(e.key)
    return { value: undefined }
  })
  on('ui.status', (_, e) => {
    w.status.push(String(e.text))
    return { value: undefined }
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('command.register', (_, e) => {
    w.registered.push(e.name)
    return { value: { command: e.name } }
  })
  // The tool itself: each run is counted, and it can fail.
  on('tool.call', () => {
    w.executions++
    if (w.isToolDown) throw new Error('tool failed')
    return { result: {} }
  })
  on('prompt.compose', () => ({ sections: [] }))
  // What draws, and runs a command, when this plugin leaves them to the engine.
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  on('command.run', () => ({ text: 'engine' }))
  return Object.assign(w, { root })
}

const run = ($: any, args: string) => $.command.run({ command: 'autodecide', args, origin: { kind: 'composer' }, presentation: { layout: 'main', columns: 100 } })
const compose = ($: any) => $.prompt.compose({ model: 'm', promptModel: 'm', surfaces: ['terminal'], tools: [], outputStyle: null, traits: [] })
const band = async ($: any) => {
  const ui = await $.ui.mount({ plugin: 'commandeck', surface: 'terminal', component: 'AbovePrompt', requestId: 'band', props: { hasSurvey: false } })
  const text = (await ui.find({ type: 'Text' }))?.text as string | undefined
  await ui.unmount()
  return text
}

test('on in the relay seat: the log, the mode file and the status; a new session in the same seat still reads ON', async ($, on) => {
  const w = world(on, 'relay')
  await $.session.start({ cwd: RELAY, ...SESSION })
  expect((await run($, 'status')).text).toContain('OFF')

  const out = await run($, 'on')
  expect(out.text).toContain(LOG)
  // The log has its three sections, Decisions last so the entries relay-order.sh --auto appends fall under it.
  const log = w.files.get(LOG) as string
  expect([...log.matchAll(/^## (.+)$/gm)].map(m => m[1])).toEqual(['Summary', 'Waiting for the owner', 'Decisions'])
  // The shell side finds the mode, and the log, through this file.
  expect(w.files.get(ON)).toBe(LOG)
  expect(w.runs.some(r => r[0] === 'orca-ide' && r.includes('tab') && r.includes(`file://${LOG}`))).toBe(true)
  expect((await run($, 'status')).text).toContain(`ON since 2026-10-24 09:30. Log: ${LOG}`)

  // A new session in the same seat (the store outlives the process) reads ON; the owner's typing is no `off`.
  await $.session.start({ cwd: RELAY, ...SESSION })
  expect(w.status[w.status.length - 1]).toBe('AUTO-DECIDE ON')
  expect((await run($, 'status')).text).toContain('ON since')
})

test('the band reads ON in the error colour with a live count, and off dim with the last run', async ($, on) => {
  const w = world(on, 'relay')
  await $.session.start({ cwd: RELAY, ...SESSION })
  expect(await band($)).toContain('auto-decide off · last run: 0 decisions')
  await run($, 'on')
  expect(await band($)).toContain('AUTO-DECIDE ON since 2026-10-24 09:30 · 0 decisions made')
  // A Write of one entry into the log: the band follows it.
  w.files.set(LOG, `${w.files.get(LOG)}\n### 09:41: id-1, a question (auto-decided)\n- **Picked**: x\n`)
  await $.tool.call({ tool: 'Write', file_path: LOG, content: 'x' })
  expect(await band($)).toContain('1 decision made')
  const off = await run($, 'off')
  expect(off.text).toContain('OFF after 1 decision')
  expect(await band($)).toContain('auto-decide off · last run: 1 decision')
  // off ends the run: the end time is in the log, the mode file is gone.
  expect(w.files.get(LOG)).toContain('turned off by the owner at 2026-10-24 09:30')
  expect(w.files.has(ON)).toBe(false)
  expect((await run($, 'status')).text).toContain('OFF')
})

test('while on, the composed prompt carries the rules, the never list and the --auto command; while off, none', async ($, on) => {
  const w = world(on, 'relay', { [`${MAIN}/.claude/commandeck.json`]: JSON.stringify({ autoDecideNever: ['touching the billing config'] }) })
  await $.session.start({ cwd: RELAY, ...SESSION })
  expect(JSON.stringify(await compose($))).not.toContain('autodecide:rules')
  await run($, 'on')
  const sections = (await compose($)).sections as { id: string; text: string }[]
  const rules = sections.find(s => s.id === 'autodecide:rules')?.text as string
  expect(rules).toContain('relay-order.sh --auto <id>')
  expect(rules).toContain('admin access to production')
  // An autoDecideNever entry in commandeck.json is the owner's own addition.
  expect(rules).toContain('touching the billing config')
  expect(rules).toContain('any push to any remote')
  await run($, 'off')
  expect(JSON.stringify(await compose($))).not.toContain('autodecide:rules')
  expect(w.files.has(ON)).toBe(false)
})

test('the picker is denied while on, allowed while off, and allowed when the mode read throws', async ($, on) => {
  const w = world(on, 'relay')
  const ask = () => $.tool.call({ tool: 'AskUserQuestion', questions: [] })
  await $.session.start({ cwd: RELAY, ...SESSION })
  expect(await ask()).not.toHaveProperty('deny')
  await run($, 'on')
  expect((await ask()).deny).toContain('auto-decide is on')
  // A broken guard asks the owner rather than stall the seat on a picker nobody answers.
  w.isStoreDown = true
  expect(await ask()).not.toHaveProperty('deny')
})

// r1 review: a hook that fails after next, with a .catch that calls next again, must not run the tool twice (a store
// hiccup after a Bash call would repeat the command). The engine's .catch replays what next settled to.
test('a tool runs once: a failed mode read or recount after it, or a failure of the tool itself, never runs it again', async ($, on) => {
  const w = world(on, 'relay')
  await $.session.start({ cwd: RELAY, ...SESSION })
  await run($, 'on')
  const once = async (call: object) => {
    w.executions = 0
    await $.tool.call(call).catch(() => undefined)
    return w.executions
  }
  const bash = { tool: 'Bash', command: 'echo mutation' }
  const ask = { tool: 'AskUserQuestion', questions: [] }
  w.files.set(LOG, `${w.files.get(LOG)}\n### 09:41: id-1, a question (auto-decided)\n`)
  w.isStoreDown = true
  expect(await once(bash)).toBe(1)
  // The mode read did fail inside the hook: no recount, the band still reads 0.
  expect(await band($)).toContain('0 decisions made')
  expect(await once(ask)).toBe(1)
  w.isToolDown = true
  expect(await once(bash)).toBe(1)
  expect(await once(ask)).toBe(1)
  w.isStoreDown = false
  w.isToolDown = false
  expect(await once(bash)).toBe(1)
  expect(await band($)).toContain('1 decision made')
})

// r1: the log name has minute precision (and DST repeats an hour), and `on` wrote the file whole.
test('a second run in the same minute gets its own log: the first keeps its decisions and its end stamp', async ($, on) => {
  const w = world(on, 'relay')
  await $.session.start({ cwd: RELAY, ...SESSION })
  await run($, 'on')
  w.files.set(LOG, `${w.files.get(LOG)}\n### 09:30: q1, a question (auto-decided)\noriginal reasoning\n`)
  await run($, 'off')
  const first = w.files.get(LOG)
  await run($, 'on')
  expect(w.files.get(LOG)).toBe(first)
  expect(first).toContain('original reasoning')
  expect(first).toContain('turned off by the owner')
  const second = w.files.get(ON) as string
  expect(second).not.toBe(LOG)
  expect(w.files.get(second)).toContain('## Decisions')
  expect((await run($, 'status')).text).toContain(second)
})

// r5: `off` wrote the log back whole from what it had read, so an entry --auto appended in between was lost.
test('off keeps a decision --auto appends while off runs: the entry and its reasoning stay, the end stamp after', async ($, on) => {
  const w = world(on, 'relay')
  await $.session.start({ cwd: RELAY, ...SESSION })
  await run($, 'on')
  w.racing = '\n### 09:30: q1, a question (auto-decided)\n- **Why**: in-flight reasoning\n'
  await run($, 'off')
  const log = w.files.get(LOG) as string
  expect(log).toContain('in-flight reasoning')
  expect(log).toContain('## Decisions')
  expect(log.indexOf('turned off by the owner')).toBeGreaterThan(log.indexOf('in-flight reasoning'))
})

// r4 review: both seats share one mode in the store, but each drew its band and status line from its own session's
// values, so a seat kept showing ON after the other seat turned it off (and off after the other turned it on).
test('the band and status line follow a mode another seat changed: at this seat\'s next hook, and within 5 s while idle', { options: { autoDecideSeats: 'chiefOfStaff,main' } }, async ($, on) => {
  const clock = mock.clock(on)
  const w = world(on, 'relay')
  await $.session.start({ cwd: RELAY, ...SESSION })
  await run($, 'on')
  expect(await band($)).toContain('AUTO-DECIDE ON')
  // Main's process ends the run: the shared mode is gone, its count kept.
  w.store.delete(`mode:${MAIN}`)
  w.store.set(`lastCount:${MAIN}`, 2)
  expect(await $.tool.call({ tool: 'AskUserQuestion', questions: [] })).not.toHaveProperty('deny')
  expect(await band($)).toContain('auto-decide off · last run: 2 decisions')
  expect(w.status[w.status.length - 1]).toBe('auto-decide off')
  // Main's process starts a run while this seat does nothing; its decisions land in the log.
  w.store.set(`mode:${MAIN}`, { log: LOG, since: '2026-10-24 10:00', how: '' })
  w.files.set(LOG, '## Decisions\n### 10:01: id-1, a question (auto-decided)\n')
  await clock.advance(5000)
  expect(await band($)).toContain('AUTO-DECIDE ON since 2026-10-24 10:00 · 1 decision made')
  expect(w.status[w.status.length - 1]).toBe('AUTO-DECIDE ON')
})

test('autoDecideSeats: chiefOfStaff leaves main out; chiefOfStaff,main gives main all four; off gives no seat the command', async ($, on) => {
  // The default: main has no command, no band, no rules and its picker is allowed.
  const w = world(on, 'main')
  await $.session.start({ cwd: MAIN, ...SESSION })
  expect(w.registered).toEqual([])
  expect(await band($)).toBe('engine')
  expect((await run($, 'on')).text).toBe('engine')
  expect(await $.tool.call({ tool: 'AskUserQuestion', questions: [] })).not.toHaveProperty('deny')
})

test('autoDecideSeats chiefOfStaff,main: main has the command and the band and its picker is blocked', { options: { autoDecideSeats: 'chiefOfStaff,main' } }, async ($, on) => {
  world(on, 'main')
  await $.session.start({ cwd: MAIN, ...SESSION })
  await run($, 'on')
  expect(await band($)).toContain('AUTO-DECIDE ON')
  expect(JSON.stringify(await compose($))).toContain('autodecide:rules')
  expect(await $.tool.call({ tool: 'AskUserQuestion', questions: [] })).toHaveProperty('deny')
})

test('autoDecideSeats off: not even the relay has the command', { options: { autoDecideSeats: 'off' } }, async ($, on) => {
  const w = world(on, 'relay')
  await $.session.start({ cwd: RELAY, ...SESSION })
  expect(w.registered).toEqual([])
  expect((await run($, 'on')).text).toBe('engine')
})

test('a Builder worktree has no seat, whatever the setting', { options: { autoDecideSeats: 'chiefOfStaff,main' } }, async ($, on) => {
  world(on, 'builder')
  await $.session.start({ cwd: '/w/unit-1', ...SESSION })
  expect(await band($)).toBe('engine')
  expect(await $.tool.call({ tool: 'AskUserQuestion', questions: [] })).not.toHaveProperty('deny')
})

test('how the owner decides: the newest 100 owner answers only, a ruling-id suffix is not a departure, worker and auto rows are left out', async ($, on) => {
  const rows: object[] = []
  // 105 owner answers: the 5 oldest depart from their default, the newest 100 take it (some with a ruling-id suffix).
  for (let i = 0; i < 105; i++) {
    const answeredAt = `2026-10-${String(1 + Math.floor(i / 24)).padStart(2, '0')}T${String(i % 24).padStart(2, '0')}:00:00Z`
    const old = i < 5
    rows.push({ id: `q${i}`, question: `Q${i}?`, proposedDefault: 'yes', answeredAt, answer: old ? 'no, never' : i % 2 ? 'yes (r-19991017-101010-p-abc123)' : 'yes' })
  }
  rows.push({ id: 'w1', question: 'worker?', proposedDefault: 'a', answeredAt: '2026-12-01T00:00:00Z', answer: 'b', waitsOn: 'main' })
  rows.push({ id: 'a1', question: 'auto?', proposedDefault: 'a', answeredAt: '2026-12-02T00:00:00Z', answer: 'b (auto-decided)' })
  rows.push({ id: 'r1', question: 're?', proposedDefault: 'a', answeredAt: '2026-12-03T00:00:00Z', answer: 're-asked as q-new' })
  // The ledger holds snapshots, the latest per id counts: answered, then reopened, is open, not an answer.
  rows.push({ id: 'q-reopened', question: 'reopened?', proposedDefault: 'yes', answeredAt: '2026-12-04T00:00:00Z', answer: 'no, never' })
  rows.push({ id: 'q-reopened', question: 'reopened?', proposedDefault: 'yes', answeredAt: null, answer: '' })
  world(on, 'relay', { [`${MAIN}/.claude/metrics/decisions.jsonl`]: rows.map(r => JSON.stringify(r)).join('\n') + '\n' })
  await $.session.start({ cwd: RELAY, ...SESSION })
  await run($, 'on')
  const rules = ((await compose($)).sections as { id: string; text: string }[]).find(s => s.id === 'autodecide:rules')?.text as string
  expect(rules).toContain('From the last 100 answers, the owner took the proposed default 100 times')
  // The 101st-newest owner answer (a departure) is not counted, and the left-out rows are not read as departures.
  expect(rules).not.toContain('no, never')
  expect(rules).not.toContain('worker?')
  expect(rules).not.toContain('auto?')
})

test('a ledger with too few owner answers shows the shipped examples instead', async ($, on) => {
  world(on, 'relay')
  await $.session.start({ cwd: RELAY, ...SESSION })
  await run($, 'on')
  const rules = ((await compose($)).sections as { id: string; text: string }[]).find(s => s.id === 'autodecide:rules')?.text as string
  expect(rules).toContain('Take the recommended option when it is well argued.')
  expect(rules).not.toContain('From the last')
})

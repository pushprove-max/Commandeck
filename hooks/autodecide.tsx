import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

// Auto-decide (issue 333): `/autodecide on` hands the owner's open decisions to the relay pane (or main) until `off`.
// What the band draws: the start time while on, null while off.
const since = atom({ plugin: 'commandeck', key: 'autoDecideSince' } as const, null)
// "### " entries in the current (or, while off, the last) run's log: one per decision.
const count = atom({ plugin: 'commandeck', key: 'autoDecideCount' } as const, 0)

type Mode = { log: string; since: string; how: string }
type Seat = { name: 'chiefOfStaff' | 'main'; main: string }

// One-off exceptions to standing rules: these are never decided for the owner. `autoDecideNever` in the project's
// .claude/commandeck.json adds the owner's own.
const NEVER = [
  'admin access to production',
  'copying production data',
  'the licence or consent of data used for training',
  'security thresholds and minimums',
  'network or write access for a seat',
  'the configured values of product settings',
]

// Examples of how an owner may decide, shown only when the decisions ledger has too few owner answers to learn from.
const EXAMPLES = [
  'Take the recommended option when it is well argued.',
  'Pick the complete fix over the narrow one.',
  'Security patches and dependency advisories: yes, at once.',
  'A review that finds the same class of deliberate bypass again and again: accept the gap, record it as a stated limit.',
  'Do not push half a feature: wait until the related issues are built.',
]

const RELAY_ORDER = '~/.commandeck/plugin/scripts/relay-order.sh'

const rules = (m: Mode, never: string[]) => `# AUTO-DECIDE IS ON (the owner turned it on at ${m.since} with /autodecide on)

The owner is away and has delegated their decisions to you. Pick what is best for the project's long-term health, not the fastest path.

- Do NOT ask the owner: the question picker is blocked while this is on. Decide each open dashboard decision and each question main sends yourself.
- Make every decision with one command: \`bash ${RELAY_ORDER} --auto <id> '<exact option label>' '<why>' '<trade-off weighed>' '<what would make you pick differently>' '<reversible: yes or no, and how>'\`. It writes the entry in the log, records the answer in the decisions ledger and tells main. Write no log entry yourself, and answer no decision any other way.
- How the owner decides:
${m.how}
- Never decide, even when the pattern seems clear, because each is a one-off exception to the owner's own standing rules: ${[...NEVER, ...never].join('; ')}. Put these under "## Waiting for the owner" in the log.
- Limits even now, which also go under "## Waiting for the owner" instead of being decided: any deploy to production or read of production data beyond counts, any push to any remote, any irreversible delete, any new unit or build the owner did not already name, and any policy call the owner reserved. Start no new work beyond what the owner already approved.
- Keep "## Summary" at the top of ${m.log} current: what ran, what was decided, what waits for the owner.
- When the owner next types to you, give them a short account of what you decided and point them at the log. The mode stays on until they run /autodecide off.`

// Decisions is the last section, so the entries relay-order.sh --auto appends land under it.
const logHead = (at: string) => `# Decisions made for the owner (auto-decide, from ${at})

The owner delegated their decisions with /autodecide on. Each entry gives the question, the pick, the why and whether it can be reversed.

## Summary

(nothing yet)

## Waiting for the owner

## Decisions
`

// The owner's own never-decide list, read at each prompt so an edit of the file counts at once.
const neverOf = async ($: EngineInterface, main: string) => {
  try {
    const v = JSON.parse((await $.fs.read(`${main}/.claude/commandeck.json`)) as string).autoDecideNever
    return Array.isArray(v) ? v.map(String) : []
  } catch {
    return []
  }
}

const recount = async ($: EngineInterface, log: string) => {
  const n = ((await $.fs.read(log).catch(() => '')) as string).split('\n').filter(l => l.startsWith('### ')).length
  await update($, count, () => n)
  return n
}

const clock = async ($: EngineInterface) => {
  const r = await $.process.run(['date', '+%F|%H:%M|%F-%H%M'])
  const [day, time, stamp] = r.stdout.trim().split('|')
  return { at: `${day} ${time}`, day, time, stamp }
}

// The owner's last 100 answers: how often the default was taken, and where they departed from it.
// Owner answers only: not a worker question main answers, not a re-ask, not the relay's own auto-decisions.
const ownerPattern = async ($: EngineInterface, main: string) => {
  const raw = (await $.fs.read(`${main}/.claude/metrics/decisions.jsonl`).catch(() => '')) as string
  const latest = new Map<string, any>()
  for (const line of raw.split('\n')) {
    try {
      const row = JSON.parse(line)
      if (row && typeof row.id === 'string') latest.set(row.id, row)
    } catch {}
  }
  const norm = (s: string) => s.replace(/ \(r-[^)]*\)$/, '').trim()
  const rows = [...latest.values()]
    .filter(r => r.answeredAt && !r.waitsOn && !String(r.answer).startsWith('re-asked as ') && !String(r.answer).endsWith('(auto-decided)'))
    .sort((a, b) => String(b.answeredAt).localeCompare(String(a.answeredAt)))
    .slice(0, 100)
  if (rows.length < 10) return EXAMPLES.map(e => `  - ${e}`).join('\n')
  const departures = rows.filter(r => norm(String(r.answer)) !== String(r.proposedDefault).trim())
  const lines = [
    `  - From the last ${rows.length} answers, the owner took the proposed default ${rows.length - departures.length} times. Take it when it is well argued.`,
    ...departures.slice(0, 10).map(r => `  - Departed from "${r.proposedDefault}" to "${norm(String(r.answer))}" on: ${String(r.question).slice(0, 80)}`),
    ...EXAMPLES.map(e => `  - ${e}`),
  ]
  return lines.join('\n')
}

const seats = new Map<string, Promise<Seat | undefined>>()

// The relay is the worktree named Chief-of-Staff; main is the checkout whose git dir is the common dir. A seat not
// in autoDecideSeats, or any other pane (a Builder's worktree), has no seat. shortcut: the basename alone names the
// relay (no check that it sits under the workspaces folder); upgrade if a second folder by that name ever matters.
const seatOf = ($: EngineInterface, gate: string[]): Promise<Seat | undefined> =>
  $.session.root().then(dir => {
    const root = dir, key = `${dir}|${gate.join(",")}`
    const hit = seats.get(key)
    if (hit) return hit
    const found = $.process
      .run(['git', '-C', root, 'rev-parse', '--path-format=absolute', '--git-dir', '--git-common-dir', '--show-toplevel'])
      .then(r => {
        const [gitDir, common, top] = r.stdout.trim().split('\n')
        if (r.exitCode !== 0 || !gitDir || !common || !top) return undefined
        const name = top.split('/').pop() === 'Chief-of-Staff' ? 'chiefOfStaff' : gitDir === common ? 'main' : undefined
        return name && gate.includes(name) ? { name, main: common.replace(/\/\.git$/, '') } : undefined
      })
      .catch(() => undefined)
    seats.set(key, found)
    return found
  })

// The mode is shared: any enabled seat's process may turn it on or off. So each read of it redraws this seat's band
// and status line from what it found, never from what this session last set.
const active = async ($: EngineInterface, gate: string[]) => {
  const seat = await seatOf($, gate)
  if (!seat) return undefined
  const mode = (await $.store.get(`mode:${seat.main}`)) as Mode | undefined
  await update($, since, () => mode?.since ?? null)
  if (mode) await recount($, mode.log)
  else {
    const last = Number((await $.store.get(`lastCount:${seat.main}`)) ?? 0)
    await update($, count, () => last)
  }
  $.ui.status(mode ? 'AUTO-DECIDE ON' : 'auto-decide off')
  return { seat, mode }
}

let stopPoll: (() => void) | undefined

export const register: Register = (on, options) => {
  const gate = String(options.autoDecideSeats ?? 'chiefOfStaff').split(',')

  on('session.start', async ($, e, next) => {
    const a = await active($, gate)
    if (!a) return next(e)
    await $.command.register({ name: 'autodecide', description: 'Decide for the owner while away: /autodecide on | off | status' })
    // An idle seat runs no hook, so it reads the shared mode again every 5 s to catch another seat's on or off.
    stopPoll?.()
    stopPoll = $.clock.every(5000, () => void active($, gate).catch(() => undefined))
    return next(e)
  })

  on('command.run', { command: 'autodecide' }, async ($, e, next) => {
    const a = await active($, gate)
    if (!a) return next(e)
    const { main } = a.seat
    const m = a.mode
    const arg = e.args.trim().toLowerCase()
    const onFile = `${main}/.claude/metrics/autodecide.on`

    if (arg === 'on') {
      if (m) return { text: `auto-decide is already on (since ${m.since}). Log: ${m.log}` }
      const t = await clock($)
      // The name has minute precision (and DST repeats an hour): a run started in a minute that already has a log
      // gets the next free -<n> name, so no run's log is ever written over.
      const base = `${main}/.claude/metrics/autodecide-${t.stamp}`
      let log = `${base}.md`
      for (let i = 2; await $.fs.read(log).then(() => true, () => false); i++) log = `${base}-${i}.md`
      const mode: Mode = { log, since: t.at, how: await ownerPattern($, main) }
      await $.process.run(['mkdir', '-p', `${main}/.claude/metrics`])
      await $.fs.write(mode.log, logHead(mode.since))
      // The shell side (relay-order.sh --auto) sees the mode, and the log, through this file.
      await $.fs.write(onFile, mode.log)
      await $.store.set(`mode:${main}`, mode)
      await update($, since, () => mode.since)
      await update($, count, () => 0)
      $.ui.status('AUTO-DECIDE ON')
      await $.process.run(['orca-ide', 'tab', 'create', '--url', `file://${mode.log}`, '--worktree', `path:${await $.session.root()}`]).catch(() => undefined)
      return {
        text: `auto-decide ON. Decisions are made for you until /autodecide off. Log (open in Orca): ${mode.log}`,
        context: ['The owner ran /autodecide on. You now decide for them under the AUTO-DECIDE rules in your system prompt. Check the dashboard for open decisions now and handle each one.'],
      }
    }

    if (arg === 'off') {
      if (!m) return { text: 'auto-decide is already off.' }
      const t = await clock($)
      const n = await recount($, m.log)
      await $.store.set(`lastCount:${main}`, n)
      await $.store.delete(`mode:${main}`)
      await $.process.run(['rm', '-f', onFile])
      await update($, since, () => null)
      $.ui.status('auto-decide off')
      // Appended, not written back whole: a relay-order.sh --auto that read the mode file before the rm above may
      // still be appending its entry (>>), and a write from an earlier read would drop it.
      if (await $.fs.read(m.log).then(() => true, () => false))
        await $.process.run(['tee', '-a', m.log], { stdin: `\n---\nauto-decide turned off by the owner at ${t.at}.\n` })
      return {
        text: `auto-decide OFF after ${n} decision${n === 1 ? '' : 's'}. Decisions go back to the owner by picker. Log: ${m.log}`,
        context: [`The owner ran /autodecide off. Delegation is over: put every decision to the owner by picker again. Give them a short account of the decisions you made while it was on (from ${m.log}).`],
      }
    }

    return { text: m ? `auto-decide is ON since ${m.since}. Log: ${m.log}` : 'auto-decide is OFF. Use /autodecide on or /autodecide off.' }
  })

  on('prompt.compose', async ($, e, next) => {
    const r = await next(e)
    const a = await active($, gate)
    if (!a?.mode) return r
    return { sections: [...r.sections, { id: 'autodecide:rules', text: rules(a.mode, await neverOf($, a.seat.main)), scope: 'session' }] }
  })

  // Recount (in the mode read) after any call that could write the live log, so the band follows each logged decision. Bash too: relay-order.sh --auto appends the entry.
  on('tool.call', async ($, e, next) => {
    const ran = await next(e)
    if (e.tool === 'Bash' || ((e.tool === 'Edit' || e.tool === 'Write') && e.file_path.endsWith('.md'))) await active($, gate)
    return ran
  }).catch(($, e, next) => next(e)) // a failed recount must not fail the tool call

  // A picker nobody answers would stall the seat; a failed guard lets it through: asking the owner is the safe side.
  on('tool.call', { tool: 'AskUserQuestion' }, async ($, e, next) =>
    (await active($, gate))?.mode ? { deny: 'auto-decide is on: the owner is away. Decide this yourself with relay-order.sh --auto, and do not ask.' } : next(e),
  ).catch(($, e, next) => next(e))

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey || !(await seatOf($, gate))) return next(e)
    const at = await read($, since)
    const n = await read($, count)
    const { Text } = $.ui.resolve(e)
    return at
      ? <Text color="error" weight="bold">● AUTO-DECIDE ON since {at} · {n} decision{n === 1 ? '' : 's'} made · /autodecide off</Text>
      : <Text dimColor>○ auto-decide off · last run: {n} decision{n === 1 ? '' : 's'} · /autodecide on</Text>
  })
}

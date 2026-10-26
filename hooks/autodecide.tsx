import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'
import { registerUnits, startUnits } from './units'
import { resetStatus, setStatus } from './status-line'

// Auto-decide (issue 333): `/autodecide on` hands the owner's open decisions to the relay pane (or main) until `off`.
// What the band draws: the start time while on, null while off.
const since = atom({ plugin: 'commandeck', key: 'autoDecideSince' } as const, null)
// "### " entries in the current (or, while off, the last) run's log: one per decision.
const count = atom({ plugin: 'commandeck', key: 'autoDecideCount' } as const, 0)

type Mode = { log: string; since: string }
type Seat = { name: 'chiefOfStaff' | 'main'; main: string }

// One-off exceptions to the owner's standing rules: these are never decided for them. The sentence ships fixed, as the
// owner wrote it. `autoDecideNever` in the project's .claude/commandeck.json adds the owner's own after it.
const NEVER =
  'using an admin PROD login, copying PROD images or personal data, the licence or consent of training data, verification or score lines, giving a seat network or write access, password or security minimums, accepting a rollout gap on a security change, and the configured values of product settings in DEV or PROD ("leave things as they are, i\'ll change them myself")'

const RELAY_ORDER = '~/.commandeck/plugin/scripts/relay-order.sh'

// How the owner decides, shipped fixed: the owner's own pattern, not a reading of the ledger.
const HOW = `  - Default: take the recommended option when it is well argued.
  - Pick the complete fix over the narrow one: "do both", "fix everything and re-review", one unit per part, the plugin follows the host project's rule and defaults.
  - Security patches and dependency advisories: yes, at once.
  - A review that finds the same class of deliberate bypass again and again: accept the gap, record it as a stated limit, stop the class.
  - Backward compatibility: none when the count of old data is zero ("we have zero customers on Stripe"); protect real users' existing data when it exists (extend old links first).
  - Cut wakes and work that only spend tokens; prefer the build that fixes a real bug, even if it costs a little more.
  - Do not push half a feature: wait until the related issues are built.`

const rules = (m: Mode, never: string[]) => `# AUTO-DECIDE IS ON (the owner turned it on at ${m.since} ET with /autodecide on)

The owner is away and has delegated their decisions to you. Their standing words (10-23): "make decisions for me on my behalf. pick the ones that are for the best long term health of the platform. keep track of the decisions you make for me in a markdown ... include the "why" you made the decision you did".

- Do NOT ask the owner: no AskUserQuestion picker (it is blocked while this is on). Decide each open dashboard decision and each question main sends yourself, picking what is best for the platform's long-term health, not the fastest path.
- Make every decision with one command: \`bash ${RELAY_ORDER} --auto <id> '<exact option label>' '<why>' '<trade-off weighed>' '<what would make you pick differently>' '<reversible: yes or no, and how>'\`. It writes the entry in the log, records the answer in the decisions ledger and tells main. Write no log entry yourself, and answer no decision any other way.
- How the owner decides (from their last 100 picks, 10-22 to 10-23; they took the recommended option at least 71 times):
${HOW}
- Never decide, even when the pattern seems clear, because the owner made each of these as a one-off exception to their own standing rules: ${NEVER}. These go under "## Waiting for the owner" in the log.${never.length ? ` The owner's own additions (\`autoDecideNever\`): ${never.join('; ')}.` : ''}
- Limits even now, which go under "## Waiting for the owner" in the log instead of being decided: any PROD deploy or PROD read beyond counts, any push to any repo, any irreversible delete, any new feature flag, any new unit or build the owner did not already name, and any policy call they reserved. Do not start new work beyond what the owner already approved.
- Keep a "## Summary" at the top of the log (${m.log}) current: what ran, what was decided, what waits for the owner.
- When the owner next types to you, give them a short account of what you decided (point them at the log). Mode stays on until they run /autodecide off.`

// Decisions is the last section, so the entries relay-order.sh --auto appends land under it.
const logHead = (at: string) => `# Decisions made for the owner (auto-decide, from ${at} ET)

The owner delegated their decisions with /autodecide on. Each entry gives the question, the pick, **why**, and whether it can be reversed.
Limits kept: no PROD deploy, no push, no irreversible delete, no new feature flag, no new unit.

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

// Every time is New York time, shown with " ET".
const clock = async ($: EngineInterface) => {
  const r = await $.process.run(['date', '+%F|%H:%M|%F-%H%M'], { env: { TZ: 'America/New_York' } })
  const [day, time, stamp] = r.stdout.trim().split('|')
  return { at: `${day} ${time}`, day, time, stamp }
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
  setStatus($, 'autodecide', mode ? 'AUTO-DECIDE ON' : 'auto-decide off')
  return { seat, mode }
}

let stopPoll: (() => void) | undefined

export const register: Register = (on, options) => {
  const gate = String(options.autoDecideSeats ?? 'chiefOfStaff').split(',')

  // This is the plugin's one hooks module (the engine takes one), so the units views register here too.
  registerUnits(on, options)

  on('session.start', async ($, e, next) => {
    resetStatus()
    await startUnits($)
    const a = await active($, gate)
    if (!a) return next(e)
    await $.command.register({ name: 'autodecide', description: 'Autonomous decisions for the owner: /autodecide on | off | status' })
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
      if (m) return { text: `auto-decide is already on (since ${m.since} ET). Log: ${m.log}` }
      const t = await clock($)
      // The name has minute precision (and DST repeats an hour): a run started in a minute that already has a log
      // gets the next free -<n> name, so no run's log is ever written over.
      const base = `${main}/.claude/metrics/autodecide-${t.stamp}`
      let log = `${base}.md`
      for (let i = 2; await $.fs.read(log).then(() => true, () => false); i++) log = `${base}-${i}.md`
      const mode: Mode = { log, since: t.at }
      await $.process.run(['mkdir', '-p', `${main}/.claude/metrics`])
      await $.fs.write(mode.log, logHead(mode.since))
      const index = `${main}/.claude/metrics/INDEX.md`
      await $.fs.write(index, `${await $.fs.read(index).catch(() => '')}- ${t.day} auto-decide decision log: ${mode.log.slice(index.length - 'INDEX.md'.length)}\n`)
      // The shell side (relay-order.sh --auto) sees the mode, and the log, through this file.
      await $.fs.write(onFile, mode.log)
      await $.store.set(`mode:${main}`, mode)
      await update($, since, () => mode.since)
      await update($, count, () => 0)
      setStatus($, 'autodecide', 'AUTO-DECIDE ON')
      await $.process.run(['orca-ide', 'tab', 'create', '--url', `file://${mode.log}`, '--worktree', `path:${await $.session.root()}`]).catch(() => undefined)
      return {
        text: `auto-decide ON. Decisions are mine until /autodecide off. Log (open in Orca): ${mode.log}`,
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
      setStatus($, 'autodecide', 'auto-decide off')
      // Appended, not written back whole: a relay-order.sh --auto that read the mode file before the rm above may
      // still be appending its entry (>>), and a write from an earlier read would drop it.
      if (await $.fs.read(m.log).then(() => true, () => false))
        await $.process.run(['tee', '-a', m.log], { stdin: `\n---\nauto-decide turned off by the owner at ${t.at} ET.\n` })
      return {
        text: `auto-decide OFF after ${n} decision(s). Decisions go back to the owner by picker. Log: ${m.log}`,
        context: [`The owner ran /autodecide off. Delegation is over: put every decision to the owner by picker again. Give them a short account of the decisions you made while it was on (from ${m.log}).`],
      }
    }

    return { text: m ? `auto-decide is ON since ${m.since} ET. Log: ${m.log}` : 'auto-decide is OFF. Use /autodecide on or /autodecide off.' }
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
    (await active($, gate))?.mode ? { deny: 'auto-decide is on: the owner is away. Decide this yourself, log it with its why, and do not ask.' } : next(e),
  ).catch(($, e, next) => next(e))

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey || !(await seatOf($, gate))) return next(e)
    const at = await read($, since)
    const n = await read($, count)
    const { Text } = $.ui.resolve(e)
    return at
      ? <Text color="error" weight="bold">● AUTO-DECIDE ON since {at} ET · {n} decision{n === 1 ? '' : 's'} made · /autodecide off</Text>
      : <Text dimColor>○ auto-decide off · last run: {n} decision{n === 1 ? '' : 's'} · /autodecide on</Text>
  })
}

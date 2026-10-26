import { expect, test } from 'claude-code/testing'
import { WS, SCR, TMP, GIT, NOW, DATA, STATE, QUEUE, LOG, ROOT, unit, snap, world, start, units, draw, quiet, table, state, attempt, DONE, REFUSED, merging, band } from './units-world'

// The views read files the scripts already write, so these cases feed sample files and check what the views say.

test('mid-run merge and test logs show step and counts in /units and the status line', async ($, on) => {
  const w = world(on, 'main', {
    [DATA]: snap([unit('u')]),
    [STATE]: state(8, 'check'), [LOG]: `${attempt(8)}STEP 4 check: x\n-- ok   a.test.sh 1s\n-- FAIL b.test.sh 2s\n`,
    [`${GIT}/commandeck-test-live/77.tsv`]: table('run\t100\t4', 'file\ta.sh', 'file\tb.sh', 'file\tc.sh', 'file\td.sh', 'start\ta.sh\t101', 'end\ta.sh\tok\t1'),
  })
  w.live.add(8).add(77)
  await start($, 'main')
  const text = await units($)
  expect(text).toContain('◐ u  check 2 files · 1 failed (first b.test.sh)')
  expect(text).toContain('▸ main  shell 1/4 files')
  expect(w.status.at(-1)).toBe('1 building · 1 merging · 1 testing · today $1.00')
  // The mod finds the plugin's own scripts through its folder's parent.
  expect(w.runs.some(r => r[0] === 'bash' && r.includes(ROOT))).toBe(true)
})

// The merge cases, one per row of the adapter's table.
test('a unit with no merge state, queue entry or log draws no merge row', async ($, on) => {
  expect((await merging($, on, {})).text).toBe('No live units.')
})

test('a queued merge reads as running', async ($, on) => {
  const { text } = await merging($, on, { [`${QUEUE}/u@abc`]: '5\n' }, [5])
  expect(text).toContain('◐ u  merging')
  expect(await band($)).toContain('u merging')
})

test('a live merge state names a running merge in the band and the pane', async ($, on) => {
  const { text } = await merging($, on, { [STATE]: state(8), [LOG]: `${attempt(8)}STEP 2 rebase: y\n` }, [8])
  expect(text).toContain('◐ u  rebase')
  expect(await band($)).toContain('u merging · rebase')
  expect((await draw($, 'Pane')).join('')).toContain('◐ u  rebase')
})

test('a live rerun beside an earlier refused log reads as running', async ($, on) => {
  const { text } = await merging($, on, { [STATE]: state(9, 'check'), [LOG]: `${attempt(8)}-- ok   a.test.sh 1s\n${REFUSED}` }, [9])
  expect(text).toContain('◐ u  check')
  expect(text).not.toMatch(/refused|files/)
})

test('a merge whose pid died shows stopped in the pane and /units, and nothing in the band', async ($, on) => {
  const { w, text } = await merging($, on, { [STATE]: state(8), [LOG]: `${attempt(8)}STEP 2 rebase: y\n` }, [], { [STATE]: 10 })
  expect(text).toContain('✗ u  stopped at rebase, no result')
  expect((await draw($, 'Pane')).join('')).toContain('stopped at rebase')
  expect(await band($)).not.toMatch(/✗|stopped/)
  expect(w.toasts).toEqual([])
})

test('a dead merge state beside a DONE log of the same second reads stopped, with no merge finished toast', async ($, on) => {
  const { w, text } = await merging($, on, { [STATE]: state(8), [LOG]: `${attempt(7)}${DONE}` })
  expect(text).toContain('✗ u  stopped at rebase, no result')
  expect(w.toasts).toEqual([])
})

test('a dead merge state over an hour old draws nothing, and a recent refusal in the log then shows', async ($, on) => {
  const files = { [STATE]: state(8), [LOG]: `${attempt(9)}FAILED step 1 preconditions: x\n` }
  const { text } = await merging($, on, files, [], { [STATE]: 3601, [LOG]: 10 })
  expect(text).toContain('✗ u  refused at step 1 preconditions: x')
  expect(text).not.toContain('stopped')
})

test('a merge whose log ends DONE toasts merge finished once and draws no row', async ($, on) => {
  const { w, text } = await merging($, on, { [LOG]: `${attempt(7)}STEP 1 preconditions: y\n${DONE}` })
  await w.clock.advance(5000)
  expect(text).toBe('No live units.')
  expect(w.toasts).toEqual(['u: merge finished'])
})

// A refused or stopped merge is shown in the side pane and /units, never in the band under the prompt.
test('a refusal shows its step and reason in the pane and /units, and nothing in the band', async ($, on) => {
  const { text } = await merging($, on, { [LOG]: `${attempt(7)}STEP 1 preconditions: y\n${REFUSED}` })
  const want = '✗ u  refused at step 3 record: review ledger has no GO'
  expect(text).toContain(want)
  expect(await band($)).not.toMatch(/✗|refused/)
  expect((await draw($, 'Pane')).join('')).toContain(want)
})

test('a log whose newest attempt has no DONE or FAILED line reads stopped', async ($, on) => {
  const { w, text } = await merging($, on, { [LOG]: `${attempt(7)}STEP 2 rebase: y\n` })
  expect(text).toContain('✗ u  stopped at 2 rebase, no result')
  expect(w.toasts).toEqual([])
})

test("an earlier attempt's DONE in an appended log does not hide the newest attempt's refusal, in the same second or not", async ($, on) => {
  const log = `${attempt(7)}${DONE}${attempt(8)}STEP 1 preconditions: retry\n${REFUSED}`
  const { w, text } = await merging($, on, { [LOG]: log })
  expect(text).toContain('✗ u  refused at step 3 record: review ledger has no GO')
  expect(w.toasts).toEqual([])
  // The reverse: an earlier refusal, then a merge that finished, is one finished merge.
  w.files.set(LOG, { text: `${attempt(7)}FAILED step 1 preconditions: x\n${attempt(8)}${DONE}`, at: NOW })
  expect(await units($)).toBe('No live units.')
  expect(w.toasts).toEqual(['u: merge finished'])
})

test("an earlier attempt's DONE followed by an unfinished attempt reads stopped, with no merge finished toast", async ($, on) => {
  const { w, text } = await merging($, on, { [LOG]: `${attempt(7)}${DONE}${attempt(8)}STEP 2 rebase: y\n` })
  expect(text).toContain('✗ u  stopped at 2 rebase, no result')
  expect(w.toasts).toEqual([])
})

test('a refused log over an hour old draws nothing', async ($, on) => {
  expect((await merging($, on, { [LOG]: `${attempt(7)}${REFUSED}` }, [], { [LOG]: 3601 })).text).toBe('No live units.')
})

test('a log with no ATTEMPT line draws nothing and toasts nothing', async ($, on) => {
  const { w, text } = await merging($, on, { [LOG]: `STEP 1 preconditions: y\n${DONE}` }, [], { [LOG]: 10 })
  expect(text).toBe('No live units.')
  expect(w.toasts).toEqual([])
})

test('one unreadable merge log leaves the other merge rows and names the unreadable one', async ($, on) => {
  const w = world(on, 'main', { [DATA]: snap([]), [STATE]: state(8), [LOG]: `${attempt(8)}STEP 2 rebase: y\n`, [`${QUEUE}/b@abc`]: '5\n' })
  w.live.add(8).add(5)
  w.beforeRead = path => { if (path === LOG) throw new Error('EACCES') }
  await start($, 'main')
  const text = await units($)
  expect(text).toContain('◐ b  merging')
  expect(text).toContain('⚠ merge u: log unreadable')
})

test('a standalone run-shell-tests run shows files done and first failure in the pane and /units, and one test run in the band', async ($, on) => {
  const w = world(on, 'main', {
    [DATA]: snap([]),
    [`${GIT}/worktrees/u/gitdir`]: `${WS}/u/.git\n`,
    [`${GIT}/worktrees/u/commandeck-test-live/88.tsv`]: table('run\t100\t2', 'file\ta.test.sh', 'file\tb.test.sh', 'start\ta.test.sh\t101', 'end\ta.test.sh\tok\t1', 'start\tb.test.sh\t102', 'end\tb.test.sh\tFAIL\t2'),
  })
  w.live.add(88)
  await start($, 'main')
  const want = '▸ u  shell 2/2 files · 1 failed (first b.test.sh)'
  expect(await units($)).toContain(want)
  expect((await draw($, 'Pane')).join('')).toContain(want)
  expect(await band($)).toContain('▸ 1 test run')
  expect(await band($)).not.toContain('2/2')
})

test("a merge check's test lines show files done and the first failure in its merge row, and its tmp copy's table draws no test row", async ($, on) => {
  const w = world(on, 'main', {
    [DATA]: snap([]), [STATE]: state(8, 'check'), [LOG]: `${attempt(8)}STEP 4 check: x\n-- ok   a.test.sh 1s\n-- FAIL b.test.sh 2s\n`,
    [`${GIT}/worktrees/t/gitdir`]: `${TMP}/abc/tree/.git\n`,
    [`${GIT}/worktrees/t/commandeck-test-live/66.tsv`]: table('run\t100\t2', 'file\ta.test.sh', 'file\tb.test.sh', 'end\ta.test.sh\tok\t1'),
  })
  w.live.add(8).add(66)
  await start($, 'main')
  const text = await units($)
  expect(text).toContain('◐ u  check 2 files · 1 failed (first b.test.sh)')
  expect(text).not.toContain('▸')
})

test('one unreadable test log or live table leaves the other test rows and names the unreadable ones', async ($, on) => {
  const bad = `${GIT}/commandeck-test-live/99.tsv`
  const w = world(on, 'main', {
    [DATA]: snap([]), [bad]: 'run\t1\t1\n', [`${GIT}/worktrees/u/gitdir`]: `${WS}/u/.git\n`,
    [`${GIT}/worktrees/u/commandeck-test-live/88.tsv`]: table('run\t100\t1', 'file\ta.test.sh'),
  })
  w.live.add(88).add(99)
  w.beforeRead = path => { if (path === bad) throw new Error('EACCES') }
  await start($, 'main')
  const text = await units($)
  expect(text).toContain('▸ u  shell 0/1 files')
  expect(text).toContain('tests 99.tsv: table unreadable')
})

test('a stopped merge does not hide the next standalone test run of that checkout', async ($, on) => {
  const w = world(on, 'main', {
    [DATA]: snap([]), [STATE]: state(8), [LOG]: `${attempt(8)}STEP 2 rebase: y\n`,
    [`${GIT}/worktrees/u/gitdir`]: `${WS}/u/.git\n`, [`${GIT}/worktrees/u/commandeck-test-live/88.tsv`]: table('run\t100\t1', 'file\ta.test.sh'),
  })
  w.live.add(88)
  await start($, 'main')
  const text = await units($)
  expect(text).toContain('✗ u  stopped at rebase')
  expect(text).toContain('▸ u  shell 0/1 files')
})

test('a table whose pid is dead draws nothing', async ($, on) => {
  world(on, 'main', { [DATA]: snap([]), [`${GIT}/commandeck-test-live/55.tsv`]: table('run\t100\t1', 'file\ta.test.sh') })
  await start($, 'main')
  expect(await units($)).toBe('No live units.')
})

test('a planning unit shows its plan author done and its judges running from the seat records', async ($, on) => {
  world(on, 'main', {
    [DATA]: snap([unit('p', { stage: 'planning' }, null)]),
    [`${SCR}/seat-p-plan-author.txt`]: 'role=plan-author\nunit=p\nphase=dispatched\nverdict=PLAN-DONE\ncollected=1\n',
    [`${SCR}/seat-p-plan-judge-sol.txt`]: 'role=plan-judge\nunit=p\nphase=dispatched\n',
  })
  await start($, 'main')
  expect(await units($)).toContain('Plan ✓  Judges ◐')
})

test('a seat whose launch failed shows nothing for it', async ($, on) => {
  world(on, 'main', {
    [DATA]: snap([unit('p', { stage: 'planning' }, null)]),
    [`${SCR}/seat-p-plan-author.txt`]: 'role=plan-author\nphase=dispatched\nverdict=PLAN-DONE\n',
    [`${SCR}/seat-p-plan-judge-sol.txt`]: 'role=plan-judge\nphase=launching\nphase=failed\n',
  })
  await start($, 'main')
  const text = await units($)
  expect(text).toContain('Plan ✓  Judges ○')
  expect(text).not.toContain('◐')
})


test('a unit merged today from a plugin snapshot shows in the pane\'s merged-today line', async ($, on) => {
  world(on, 'main', { [DATA]: snap([unit('u')], { finishedBuilds: [{ unit: 'v', at: new Date(NOW - 60_000).toISOString() }] }) })
  await start($, 'main')
  const lines = (await units($)).split('\n')
  expect(lines.some(l => /^MERGED TODAY +1/.test(l))).toBe(true)
  expect(lines.some(l => /^✓ v +\d\d:\d\d/.test(l))).toBe(true)
})


test('config and the command each toggle each view', quiet, async ($, on) => {
  const w = world(on, 'worker', { [DATA]: snap([unit('u')]) })
  await start($, 'worker')
  expect(w.opened).toEqual(['units'])
  expect((await draw($, 'AbovePrompt')).join('')).toContain('● u Building')
  expect(w.status.at(-1)).toBe('1 building · today $1.00')
  await units($, 'band off')
  expect(await draw($, 'AbovePrompt')).toEqual(['engine'])
  expect(w.opened).toEqual(['units'])
  await units($, 'pane off')
  expect(w.opened).toEqual([])
  await units($, 'status off')
  expect(w.status.at(-1)).toBe(undefined)
  await units($, 'band on')
  expect((await draw($, 'AbovePrompt')).join('')).toContain('● u Building')
  expect(w.status.at(-1)).toBe(undefined)
})

test('unitsBand, unitsPane and unitsStatus off in config show no band, no pane and no status line in main', { options: { unitsBand: 'off', unitsPane: 'off', unitsStatus: 'off' } }, async ($, on) => {
  const w = world(on, 'main', { [DATA]: snap([unit('u')]) })
  await start($, 'main')
  expect(await draw($, 'AbovePrompt')).toEqual(['engine'])
  expect(w.opened).toEqual([])
  expect(w.status.filter(s => s !== undefined)).toEqual([])
})

// A reviewer runs in a Builder-style worktree, so it is a worker seat too.
for (const [seat, isOn] of [['main', true], ['cos', true], ['worker', false]] as const) {
  test(`main and Chief of Staff default on, worker and reviewer default off: ${seat}`, async ($, on) => {
    const w = world(on, seat, { [DATA]: snap([unit('u')]) })
    await start($, seat)
    expect([w.opened.length === 1, w.status.at(-1) !== undefined, (await draw($, 'AbovePrompt')).join('').includes('● u Building')]).toEqual([isOn, isOn, isOn])
  })
}

// r1 finding: auto-decide wrote its mode over the units summary in the relay seat, and units never wrote it again.
test('the relay keeps its units summary beside the auto-decide mode, across polls', async ($, on) => {
  const w = world(on, 'cos', { [DATA]: snap([unit('u')]) })
  on('store.get', () => ({ value: undefined }))
  await start($, 'cos')
  expect(w.status.at(-1)).toBe('1 building · today $1.00 · auto-decide off')
  await w.clock.advance(5000)
  expect(w.status.at(-1)).toBe('1 building · today $1.00 · auto-decide off')
})

test('a checkout with no Commandeck setup registers nothing', async ($, on) => {
  const w = world(on, 'main', { [DATA]: snap([unit('u')]) }, false)
  await start($, 'main')
  expect(w.registered).toEqual([])
  expect(w.opened).toEqual([])
  expect(w.status).toEqual([])
  expect(w.runs.some(r => r[0] === 'bash')).toBe(false)
})

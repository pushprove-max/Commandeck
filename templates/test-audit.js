export const meta = {
  name: 'test-audit',
  description: 'Report-only audit of a test directory by Haiku agents, checked by a Sonnet validator: /test-audit <scope dir...> [basic|full|prune] [N agents]',
}

// The two facts the script cannot find out: it sees no disk and no environment.
// Set-up writes this machine's two paths over these two lines when it copies
// the script into a project's .claude/workflows (scripts/setup.sh).
// PROMPT holds everything else, and the agents read it by section.
// OUT_ROOT is the scratch root: the only folder the script lets agents write
// under is one plain name directly below this.
const PROMPT = 'templates/test-audit-prompt.md'
const OUT_ROOT = '/tmp/commandeck'
const MODEL = 'haiku'
const USAGE = 'Usage: /test-audit <scope dir...> [basic|full|prune] [N agents]  (N: a whole number from 1 to 16, default 4)'

// agent() takes no token or turn limit, so the 95,000-token ceiling rests on
// each agent keeping its brief: the packing charges for what the brief allows
// and nothing more. All figures are tokens, measured 2026-10-13 on Haiku agents
// in one repository; a project whose startup files and hooks are heavier has less margin.
const LIMIT = 95000
const BASELINE = 45000 // carried before the first instruction: 34,623 measured on a workflow agent, plus margin
const CALL = 2500 // added by each tool call before its output: 2,178 measured
const BYTES_PER_TOKEN = 1.75 // file content as the read tool returns it: 1.79 measured
const BATCH_FIXED = 17000 // heading list, the batch sections (about 12 KB in two reads), the list file, the reply
const WRITTEN = 4000 // the most a batch agent may write per file or part: one finding (3,500 with its quote re-read), five POSSIBLE lines and the closing note (about 80 each)
const FULL_EXTRA = 15500 // full mode per file: subject search and read, history read, 150 lines each
const STAGE_FIXED = 42000 // report stage: its sections and about twelve calls; 39,000 seen in the trial with no finding, before Checks was added
const MAX_LISTED = 200 // the listing stage sees every path twice; more would pass its room
const ROOM = LIMIT - BASELINE - BATCH_FIXED

// The validator stage runs on another model, so its work is packed with its
// own figures. All are tokens, measured 2026-10-13 on Sonnet workflow agents.
const VALIDATOR_MODEL = 'sonnet'
const V_BASELINE = 52000 // carried once its first file is read: 34,466 measured at start and 13,111 more loaded once at the first read, plus margin
const V_CALL = 500 // added by each tool call before its output: 305 measured
const V_BYTES_PER_TOKEN = 2.2 // file content as the read tool returns it: 2.43 measured
const V_RANGE = 600 // one cited range of 15 numbered lines, eight ranges to a command: 366 to 515 measured
const V_NOTE = 80 // one POSSIBLE line read
const V_FIXED = 20000 // its sections (about 14 KB in four reads), the brief, eight findings written to its file and returned (about 500 each time), the reply
const V_CHECKS = 5000 // the first agent only: the coverage, split and count commands, plus V_LIST twice for each list line: the line, and its batch file's row, each read and returned
const V_LIST = 80
const V_ROOM = LIMIT - V_BASELINE - V_FIXED

function parseArgs(raw) {
  let text = raw
  if (Array.isArray(raw)) text = raw.join(' ')
  else if (raw && typeof raw === 'object') {
    const agents = raw.agents == null ? [] : `${String(raw.agents).replace(/\s*agents?$/i, '')} agents`
    text = [].concat(raw.scope ?? [], raw.mode ?? [], agents).join(' ')
  }
  if (typeof text !== 'string') return null
  const words = text.trim().split(/\s+/).filter(Boolean)
  let agents = 4
  if (/^agents?$/i.test(words.at(-1) ?? '')) {
    words.pop()
    const n = words.pop() ?? ''
    if (!/^\d{1,2}$/.test(n) || +n < 1 || +n > 16) return null
    agents = +n
  }
  let mode = null
  if (/^(basic|full|prune)$/i.test(words.at(-1) ?? '')) mode = words.pop().toLowerCase()
  // The file list comes back as plain repository paths, so "./a//b/" must become "a/b" to match it.
  const scope = words.map((d) => d.split('/').filter((s, i) => (s && s !== '.') || (i === 0 && !s)).join('/'))
  // A bare number is a count that lost its "agents", not a directory.
  if (!scope.length || !scope.every((d) => safePath(d) && !d.startsWith('/') && !/^\d+$/.test(d))) return null
  return { scope, mode, agents }
}

// Scope, output folder and file paths are typed into shell commands by the
// agents, so only plain path characters pass and nothing may climb with "..".
function safePath(p) {
  return typeof p === 'string' && /^[A-Za-z0-9._/][A-Za-z0-9._/-]*$/.test(p) && /[A-Za-z0-9]/.test(p) && !p.split('/').includes('..')
}

// Every file is priced as read whole, in reads of at most 150 lines. The
// prompt's shorter range for a file past 600 lines is not used: in the trial
// an agent read such a file whole, and the limit may not rest on it obeying.
function cost(bytes, ranges, mode) {
  const reads = ranges.reduce((n, lines) => n + Math.ceil(lines / 150), 0)
  return Math.ceil(bytes / BYTES_PER_TOKEN) + (2 + reads) * CALL + WRITTEN + (mode === 'full' ? FULL_EXTRA : 0)
}

// A file at or under both sizes fits one agent whatever its shape; the file
// list returns block starts only for files past one of them. Derived from cost().
const longFile = (mode) => (mode === 'full' ? { lines: 150, bytes: 10000 } : { lines: 300, bytes: 20000 })
// Where a test block starts, at most one level inside a describe. Other shapes
// (a shell test, a deeper nest) give no start, and the block is then the file.
const BLOCK = '^ {0,2}(describe|suite|test|it)(\\.[A-Za-z]+)*\\('

// A file too large for one agent is cut between test blocks, one part per
// agent. Every part after the first re-reads the head (the lines before the
// first block: imports and shared set-up), and a part is charged its real
// bytes, head included, from the byte offset of each block start. A listing
// without usable offsets is priced at the file's bytes less one byte for every
// line outside the part: never below the real cost, so such a file is cut
// less finely or listed too large. The script names each range.
function split(f, mode) {
  const lines = Math.max(f.lines, 1)
  const given = Array.isArray(f.blocks) ? f.blocks.map((n, i) => [n, f.offsets?.[i]]).filter(([n]) => Number.isInteger(n) && n >= 1 && n <= lines) : []
  const starts = given.length ? [...new Set(given.map(([n]) => n))].sort((a, b) => a - b) : [1]
  const head = starts[0] - 1
  const at = new Map(given)
  // Every line is at least its newline, so an offset can sit no nearer than one byte per line.
  const slack = (n) => at.get(n) - (n - 1)
  const exact = given.length > 0 && starts.every((n, i) => Number.isInteger(at.get(n)) && slack(n) >= (i ? slack(starts[i - 1]) : 0)) && f.bytes - at.get(starts.at(-1)) >= lines - starts.at(-1) + 1
  const bytes = (from, to) => (exact ? at.get(starts[0]) + (to >= lines ? f.bytes : at.get(to + 1)) - at.get(from) : f.bytes - (lines - (head + to - from + 1)))
  const price = (from, to) => cost(bytes(from, to), [head, to - from + 1], mode)
  const parts = []
  const tooLarge = []
  let open = null
  starts.forEach((from, i) => {
    const to = i + 1 < starts.length ? starts[i + 1] - 1 : lines
    if (open && price(open.from, to) <= ROOM) {
      open.to = to
    } else if (price(from, to) <= ROOM) {
      open = { from, to }
      parts.push(open)
    } else {
      open = null
      tooLarge.push(`${from}-${to}`)
    }
  })
  const said = (p) => (p.from === head + 1 ? `lines 1-${p.to}` : `head lines 1-${head}, then lines ${p.from}-${p.to}`)
  return {
    parts: parts.map((p, i) => ({ entry: `${f.path} | part ${i + 1} of ${parts.length} | ${said(p)} of ${lines}`, tokens: price(p.from, p.to), bytes: bytes(p.from, p.to) })),
    tooLarge,
  }
}

// A part's bytes by its entry text, for the validator's price of opening it.
const partBytes = new Map()

function pack(files, scope, mode) {
  const batches = []
  const notAudited = []
  const splits = []
  const whole = (n) => Number.isInteger(n) && n >= 0
  const batch = (entries, tokens) => batches[batches.push({ id: String(batches.length + 1).padStart(3, '0'), files: entries, tokens, done: false }) - 1]
  let cur = null
  for (const f of files) {
    // In prune mode a path the script rejects is agent text, and is never printed.
    const skip = (reason, withhold) => notAudited.push({ path: withhold && prune ? '(withheld)' : String(f.path), reason: `not audited: ${reason}` })
    if (!safePath(f.path) || !scope.some((d) => f.path.startsWith(`${d}/`))) { skip('path not in scope', true); continue }
    if (!whole(f.lines) || !whole(f.bytes)) { skip('size unknown'); continue }
    const tokens = cost(f.bytes, [f.lines], mode)
    if (tokens > ROOM) {
      const { parts, tooLarge } = split(f, mode)
      tooLarge.forEach((range) => skip(`block too large (lines ${range})`))
      parts.forEach((p) => {
        partBytes.set(p.entry, p.bytes)
        batch([p.entry], p.tokens)
      })
      if (parts.length) splits.push({ path: f.path, parts: parts.length })
      cur = null
      continue
    }
    if (!cur || cur.tokens + tokens > ROOM) cur = batch([], 0)
    cur.files.push(f.path)
    cur.tokens += tokens
  }
  return { batches, notAudited, splits }
}

const request = parseArgs(args)
if (!request) return USAGE
// Both paths are typed into shell commands by the agents, like the scope.
if (!safePath(PROMPT) || !safePath(OUT_ROOT)) return 'test-audit cannot run here: the path of its prompt file or of its scratch folder has a character that is not plain (a space, a quote); run set-up from a plainly named folder'
const { scope, agents } = request
let mode = request.mode
// Prune mode proposes only deleting or merging tests, and its result carries no agent-written text.
const prune = mode === 'prune'
const isWhole = (n) => Number.isInteger(n) && n >= 0

const brief = (stage, sections, lines) => [
  `You are the ${stage} stage of a test-suite audit. It is report only: change nothing in the repository.`,
  `Your instructions are sections of the file ${PROMPT}. Run \`grep -n '^## ' ${PROMPT}\` for each section's line range, then read ONLY these sections and no other: ${(prune ? [...sections, 'Prune mode'] : sections).map((s) => `"${s}"`).join(', ')}.`,
  `SCOPE: ${scope.join(' ')}`,
  `MODE: ${mode ?? 'not given: use the default the Parameters section states'}`,
  'TIMING RUN: no',
  'Where a line below differs from those sections, the line below wins.',
  ...lines,
].join('\n')
// A rejected call is a dead agent like a null one: every stage below handles null.
const ask = async (label, phase, prompt, schema, model = MODEL) => {
  try {
    return await agent(prompt, { label, phase, model, ...(schema && { schema }) })
  } catch {
    return null
  }
}
const text = { type: 'string' }
const count = { type: 'integer', minimum: 0 }

const setup = await ask('phase 0', 'Setup', brief('set-up', ['Parameters', 'Hard rules', 'Reading files in this repository', 'Phase 0'], [
  `OUT is one new folder directly under ${OUT_ROOT}. Run \`mkdir -p ${OUT_ROOT}\`, then create OUT with a plain \`mkdir\` (no -p), which fails when the folder exists.`,
  'Never resume an earlier run: when that mkdir fails because OUT exists, add -2, -3 and so on to its name until it succeeds.',
  `Return: out, the path of OUT as you created it; mode, the MODE in force (${prune ? 'basic, full or prune' : 'basic or full'}); stop, the reply those sections tell you to stop with, or an empty string.`,
]), { type: 'object', required: ['out', 'mode', 'stop'], properties: { out: text, mode: { enum: ['basic', 'full', 'prune'] }, stop: text } })
const outName = typeof setup?.out === 'string' && setup.out.startsWith(`${OUT_ROOT}/`) ? setup.out.slice(OUT_ROOT.length + 1) : ''
if (!setup || setup.stop || !/^[A-Za-z0-9_-][A-Za-z0-9._-]*$/.test(outName)) {
  return `test-audit stopped in set-up: ${prune ? 'the set-up stage stopped or returned no usable folder (its reply is not shown in prune mode)' : setup?.stop || `no folder directly under ${OUT_ROOT} was returned`}`
}
const out = setup.out
mode ??= setup.mode

const listed = await ask('phase 1', 'Setup', brief('file-list', ['Hard rules', 'Reading files in this repository', 'Facts about this repository', 'Phase 1'], [
  `OUT is ${out}.`,
  `After step 1: if files.txt has more than ${MAX_LISTED} lines, stop with "SCOPE too large: <count> test files, the limit is ${MAX_LISTED}; name a narrower directory".`,
  'Skip step 3: the workflow packs the batches by size. In step 5 write batches.md with the counts only and no batch lines.',
  `Then run \`wc -lc $(cat ${out}/files.txt) > ${out}/sizes.txt\` and read sizes.txt.`,
  `For every file with more than ${longFile(mode).lines} lines or more than ${longFile(mode).bytes} bytes, also run \`grep -n -b -E '${BLOCK}' <file> | cut -d: -f1,2\`: for each line where a test block starts, its line number and its byte offset.`,
  'Return: stop, the reply you stopped with, or an empty string; count, the number of lines in files.txt; files, one entry for every line of files.txt, in the same order: path, the line exactly as files.txt has it (a repository path, never an absolute path, and never files.txt, sizes.txt or the total line), with its line count and byte count from sizes.txt, and for those larger files blocks, the first number of each grep line, and offsets, the second number of each grep line, in the same order.',
]), { type: 'object', required: ['stop', 'count', 'files'], properties: { stop: text, count, files: { type: 'array', items: { type: 'object', required: ['path', 'lines', 'bytes'], properties: { path: text, lines: count, bytes: count, blocks: { type: 'array', items: count }, offsets: { type: 'array', items: count } } } } } })
if (!listed || listed.stop || !listed.files.length) {
  return `test-audit stopped at the file list: ${prune ? 'the file-list stage stopped or returned no test file (its reply is not shown in prune mode)' : listed?.stop || 'no test file was returned'} (${out})`
}
// The list is an agent's transcription of files.txt: a short or mis-pathed one would audit less and look complete.
if (listed.files.length !== listed.count) {
  return `test-audit stopped at the file list: ${listed.files.length} entries came back for ${listed.count} test files (${out})`
}
const { batches, notAudited, splits } = pack(listed.files, scope, mode)
if (notAudited.length === listed.files.length && notAudited.every((n) => n.reason.endsWith('path not in scope'))) {
  return `test-audit stopped at the file list: no listed file is inside the scope ${scope.join(' ')} (${out})`
}

const records = await ask('phase 2', 'Setup', brief('records', ['Hard rules', 'Reading files in this repository', 'Facts about this repository', 'Phase 2'], [
  `OUT is ${out}.`,
  'Reply with one line: the path of records.md.',
]))
if (!records) log('test-audit: the records stage failed; timings will read "no timing record"')

// N workers each hold one batch agent at a time, so no more than N ever run.
let next = 0
const worker = async () => {
  while (next < batches.length) {
    const b = batches[next++]
    b.result = await ask(`batch ${b.id}`, 'Batches', brief(`batch ${b.id}`, ['Hard rules', 'Reading files in this repository', 'Facts about this repository', 'Phase 3', 'Checks', 'Finding format'], [
      `OUT is ${out}. This is batch ${b.id} only.`,
      `First write ${out}/batch-${b.id}.list with exactly the files listed at the end, one per line, in that order. Then do Phase 3 for them, writing ${out}/batch-${b.id}.md.`,
      'Read every file whole, in ranges of at most 150 lines: the first-300-lines rule for a file past 600 lines is not used.',
      'A list line that carries "| part k of M |" is one part of a file cut between its test blocks: read exactly the line ranges it names and no other line of that file, judge only the tests that start in its last range (the head range is imports and shared set-up; the part may begin inside a describe block), and write one row for it. Every line number you write is the file\'s own.',
      'Your context has room for this much writing per list line and no more: at most ONE finding in the finding format, the strongest; then at most FIVE one-line POSSIBLE lines, with no second read; then, if you saw more signs than that, one closing line "MORE SIGNS NOT LISTED | <path>" and nothing further for it.',
      ...(prune ? [
        'PRUNE MODE, subtraction only: propose only that a test be removed or merged into another test; never propose adding, rewriting or strengthening a test. Every finding\'s Proposal is exactly "remove" or "merge" and its Other test field is <path>:<name>, the one test that still protects the behaviour.',
        'Also return proposals: one entry for each finding you wrote, {id, proposal, otherTest}, copied from its ID, Proposal and Other test fields.',
      ] : []),
      'Do not read or edit batches.md or any other batch: the workflow records completion.',
      `Search what earlier stages wrote in ${out} with grep for the lines you need; never read those files whole.`,
      'Keep the output of every command to 150 lines at most.',
      'Return: complete, true only when the batch file ends with its "complete" line; rows, the rows written; findings and possible, the findings and POSSIBLE lines written; capped, each list line that got the closing line, exactly as given under Files.',
      'Files:',
      ...b.files.map((f) => `- ${f}`),
    ]), { type: 'object', required: ['complete', 'rows', 'findings', 'possible', 'capped', ...(prune ? ['proposals'] : [])], properties: { complete: { type: 'boolean' }, rows: count, findings: count, possible: count, capped: { type: 'array', items: text }, ...(prune && { proposals: { type: 'array', items: { type: 'object', required: ['id', 'proposal', 'otherTest'], properties: { id: text, proposal: text, otherTest: text } } } }) } })
    b.done = !!b.result && b.result.complete === true && b.result.rows === b.files.length
  }
}
await parallel(Array.from({ length: Math.min(agents, batches.length) }, () => worker))

// Only a finished batch gave counts, and the report agent's room is sized from
// them: a batch that failed is not checked, and its findings file is not read.
const done = batches.filter((b) => b.done)
const unchecked = [
  ...notAudited.map((f) => `${f.path} | ${f.reason}`),
  ...batches.filter((b) => !b.done).flatMap((b) => b.files.map((f) => `${f} | not checked: batch ${b.id} did not finish`)),
]
const sum = (key) => done.reduce((n, b) => n + b.result[key], 0)
const findings = sum('findings')
// The cap on what an agent writes must never hide that it bit: these are named in the result and the report.
const capped = done.flatMap((b) => b.files.filter((f) => Array.isArray(b.result.capped) && b.result.capped.includes(f)))
const summary = {
  out,
  mode,
  agents,
  findings,
  capped,
  cappedFiles: new Set(capped.map((f) => f.split(' | ')[0])).size,
  batches: batches.map((b) => ({ id: b.id, files: b.files.length, tokens: b.tokens, done: b.done })),
  notAudited,
  split: splits,
}
// The report stage reads about 300 tokens of fields per finding and 80 per POSSIBLE line.
// Past its room no report is written; the validator reads the batch files and still runs.
const tooMany = findings * 300 + sum('possible') * 80 > LIMIT - BASELINE - STAGE_FIXED
const report = tooMany ? null : await ask('report', 'Report', brief('report', ['Hard rules', 'Reading files in this repository', 'Checks', 'Finding format', 'Phase 4', 'Phase 5'], [
  `OUT is ${out}.`,
  `First append these lines to ${out}/batches.md, exactly as given:`,
  ...batches.map((b) => `batch-${b.id} | ${b.files.length} | ${b.done ? 'done' : 'NOT DONE'}`),
  'Do not write REPORT.md or SELF-CHECK.md: the runtime refuses a report file from an agent. Compose both and return them as text.',
  `Then write ${out}/not-audited.md with exactly the lines between the markers, and repeat them under "Not checked" in the report:`,
  '--- not audited ---',
  ...(unchecked.length ? unchecked : ['(none)']),
  '--- end ---',
  `Findings files to read, and no other: ${done.map((b) => `batch-${b.id}.md`).join(' ') || '(none)'}`,
  'A batch marked NOT DONE is not checked: never open its findings file.',
  'Under its own heading "Cut short by the per-file cap" list exactly these, each with the advice to run /test-audit on that file alone and read it by hand: more signs were seen there than one agent may write up.',
  ...(capped.length ? capped : ['(none)']),
  'A split file is ONE file in every count, whatever its number of parts; say its parts once. Split files:',
  ...(splits.length ? splits.map((s) => `${s.path} | ${s.parts} parts`) : ['(none)']),
  'Never read a findings file whole: pull the fields the tables need with grep -n on the field names, 150 lines of output at most per command.',
  'Return: report, the whole text REPORT.md would hold; selfCheck, the whole text SELF-CHECK.md would hold; findings, the number of findings in the report.',
]), { type: 'object', required: ['report', 'selfCheck', 'findings'], properties: { report: text, selfCheck: text, findings: count } })
// Batch findings stay in files under `out`; the report exists only as this text.
const reportText = tooMany
  ? `not written: ${findings} findings and ${sum('possible')} POSSIBLE lines pass one report agent's room; they are in ${out}/batch-*.md`
  : report?.report ?? `not written: the report agent failed; findings are in ${out}/batch-*.md`

// The validator's work is packed like a batch. A finished batch costs its
// POSSIBLE lines read and one cited range opened for each; the first agent also
// pays for the checks made once for the run. A batch that passes one agent's
// room alone is named not checked, and what an agent has left it may spend
// opening files, each priced here: the file, or the lines a part names.
const strings = (x) => (Array.isArray(x) ? x.filter((s) => typeof s === 'string') : [])
const pathOf = (entry) => entry.split(' | ')[0]
const sizes = new Map(listed.files.map((f) => [f.path, f]))
const openCost = (entry) => {
  const f = sizes.get(pathOf(entry))
  // A part names its head and its own range; both are read, each in its own reads.
  const named = [...entry.slice(f.path.length).matchAll(/lines (\d+)-(\d+)/g)].map((m) => m[2] - m[1] + 1)
  const ranges = named.length ? named : [f.lines]
  const lines = ranges.reduce((n, r) => n + r, 0)
  const bytes = partBytes.get(entry) ?? (f.bytes * lines) / Math.max(f.lines, 1)
  return Math.ceil((bytes + 6 * lines) / V_BYTES_PER_TOKEN) + ranges.reduce((n, r) => n + Math.ceil(r / 150), 0) * V_CALL
}
// The line ranges a list line asks for: the ones a part names, or the whole file.
const wanted = (entry) => {
  const f = sizes.get(pathOf(entry))
  const named = [...entry.slice(f.path.length).matchAll(/lines (\d+)-(\d+)/g)].map((m) => [+m[1], +m[2]])
  return named.length ? named : [[1, f.lines]]
}
// Whether the ranges a row's read= field names, joined up, hold every wanted line.
// The whole field must be ranges: a word in it ("not read: 101-150") would lend its numbers.
const covers = (read, want) => {
  if (!/^\s*\d+(?:-\d+)?(?:[\s,]+\d+(?:-\d+)?)*\s*$/.test(read)) return false
  const spans = [...read.matchAll(/(\d+)(?:-(\d+))?/g)].map((m) => [+m[1], +(m[2] ?? m[1])]).sort((a, b) => a[0] - b[0])
  return want.every(([from, to]) => spans.reduce((at, [a, z]) => (a <= at && z >= at ? z + 1 : at), from) > to)
}
const entries = batches.flatMap((b) => b.files)
const checksCost = V_CHECKS + 2 * V_LIST * entries.length
const checked = checksCost <= V_ROOM
const groups = [{ batches: [], tokens: checked ? checksCost : 0 }]
const over = []
for (const b of done) {
  const tokens = b.result.possible * (V_NOTE + V_RANGE)
  if (tokens > V_ROOM) { over.push(b); continue }
  let g = groups.at(-1)
  if (g.tokens + tokens > V_ROOM) groups.push((g = { batches: [], tokens: 0 }))
  g.batches.push(b)
  g.tokens += tokens
}
const ids = (g) => g.batches.map((b) => b.id)
const list = { type: 'array', items: text }
const answers = { findings: text, atCap: { type: 'array', items: { type: 'object', required: ['entry', 'cut'], properties: { entry: text, cut: { type: 'boolean' } } } }, opened: list, notChecked: list }
const onceAnswers = { missing: list, extra: list, lists: { type: 'array', items: { type: 'object', required: ['id', 'entries'], properties: { id: text, entries: list } } }, gaps: list, reports: { type: 'array', items: { type: 'object', required: ['id', 'rows', 'complete'], properties: { id: text, rows: { type: 'array', items: { type: 'object', required: ['path', 'read'], properties: { path: text, read: text } } }, complete: { type: 'boolean' } } } }, fileFindings: count, filePossible: count }
let nextGroup = 0
const validate = async () => {
  while (nextGroup < groups.length) {
    const k = nextGroup++
    const g = groups[k]
    const once = k === 0 && checked
    g.entries = g.batches.flatMap((b) => b.files)
    const properties = { ...answers, ...(once && onceAnswers) }
    g.result = await ask(`validator ${k + 1}`, 'Validator', brief('validator', ['Hard rules', 'Reading files in this repository', 'Checks', 'Finding format', 'Validator'], [
      `OUT is ${out}. You are validator agent ${k + 1} of ${groups.length}. You read test files and the files in OUT; the one file you write is ${out}/validator-${k + 1}.md.`,
      `Notes files to check, and no other: ${ids(g).map((id) => `batch-${id}.md`).join(' ') || '(none)'}`,
      'Your context has room for this much and no more: each POSSIBLE line of those files read once; ONE cited range of at most 15 lines opened for each, eight ranges to a command; at most EIGHT findings in the finding format, written once to your file and returned once; one line for each plain fact past the eighth.',
      `Room left for opening files: ${V_ROOM - g.tokens} tokens.`,
      'Files you may open to look for what the audit missed, each with what opening it costs in tokens. Take them in the order the section gives and stop before the costs of the ones you opened pass that room:',
      ...(g.entries.length ? g.entries.map((e) => `- ${e} | ${openCost(e)}`) : ['(none)']),
      ...(once ? [
        'You also make the checks done once for the run, coverage and counts, as the section\'s "Checks made once" part says.',
        'Read every batch-*.list in OUT, finished or not, for missing, extra and lists: a list no finished batch owns is a fault to return.',
        `Finished batches, the only ones whose rows and findings files those checks read: ${done.map((b) => b.id).join(' ') || '(none)'}`,
        `Split files, each to check for a gap: ${splits.map((s) => s.path).join(' ') || '(none)'}`,
        `Line ranges left out on purpose, not a gap: ${notAudited.filter((f) => f.reason.includes('block too large')).map((f) => `${f.path} ${f.reason.slice(f.reason.indexOf('('))}`).join('; ') || '(none)'}`,
        'Also return what those checks found, as that part names them: missing, extra, lists, gaps, reports, fileFindings, filePossible.',
      ] : []),
      ...(prune ? ['PRUNE MODE, subtraction only: every finding you write has a Proposal of exactly "remove" or "merge" and the field "Other test: <path>:<name>"; a finding that cannot have both is not written. Its ID keeps the V form.'] : []),
      'Keep the output of every command to 150 lines at most.',
      'Return: findings, the whole text of your file, or an empty string when you wrote no finding; atCap, each list line of your notes files that holds five POSSIBLE lines, as entry (the line exactly as given above, without its cost) and cut (true when a "MORE SIGNS NOT LISTED" line follows them); opened, each file line above that you opened, exactly as given, without its cost; notChecked, one line for each thing the section tells you to name as not checked.',
    ]), { type: 'object', required: Object.keys(properties), properties }, VALIDATOR_MODEL)
  }
}
await parallel(Array.from({ length: Math.min(agents, groups.length) }, () => validate))

// Every count and verdict below is worked out here from what the agents read
// on disk; only the findings text is an agent's own writing.
const ran = groups.filter((g) => g.result)
const once = checked ? groups[0].result : null
const found = ran.map((g) => g.result.findings).filter((s) => typeof s === 'string' && s.trim()).join('\n\n')
// Prune mode keeps a proposal only when its id, proposal and other test pass; what is kept is
// rebuilt from those fields, and nothing an agent wrote is published as it came.
const otherTestOk = (s) => {
  const at = typeof s === 'string' ? s.indexOf(':') : -1
  const name = at > 0 ? s.slice(at + 1) : ''
  return at > 0 && safePath(s.slice(0, at)) && name.length >= 1 && name.length <= 120 && !/[|`\r\n\u2028\u2029]/.test(name)
}
const judge = (id, proposal, otherTest, form) => {
  if (typeof id !== 'string' || !form.test(id)) return { drop: '(no valid id) | its id is not in the form its source uses' }
  if (proposal !== 'remove' && proposal !== 'merge') return { drop: `${id} | its proposal is not remove or merge` }
  if (!otherTestOk(otherTest)) return { drop: `${id} | it names no valid other test` }
  return { row: `| ${id} | ${proposal} | ${otherTest} |` }
}
const field = (block, name) => block.match(new RegExp(`^${name}:[ \\t]*(.*?)[ \\t]*$`, 'm'))?.[1]
const batchJudged = prune ? done.flatMap((b) => (Array.isArray(b.result.proposals) ? b.result.proposals : [])).map((p) => judge(p?.id, p?.proposal, p?.otherTest, /^B\d{3}-[A-Za-z0-9]+-\d+$/)) : []
const validatorJudged = prune ? found.split(/^(?=ID: )/m).filter((s) => s.startsWith('ID: ')).map((s) => judge(field(s, 'ID'), field(s, 'Proposal'), field(s, 'Other test'), /^V\d{3}-(CR|TC|T2)-\d+$/)) : []
const rows = [...batchJudged, ...validatorJudged].filter((j) => j.row).map((j) => j.row)
const dropped = [...batchJudged, ...validatorJudged].filter((j) => j.drop).map((j) => j.drop)
const validatorRows = validatorJudged.filter((j) => j.row).map((j) => j.row)
const validatorFindings = prune ? validatorRows.length : (found.match(/^ID: /gm) ?? []).length
const opened = new Set(ran.flatMap((g) => strings(g.result.opened).filter((e) => g.entries.includes(e))))
const atCap = new Map(ran.flatMap((g) => (Array.isArray(g.result.atCap) ? g.result.atCap : []).filter((c) => g.entries.includes(c?.entry)).map((c) => [c.entry, c.cut === true])))
const packed = new Set(entries.map(pathOf))
const finished = new Set(done.flatMap((b) => b.files.map(pathOf)))
const notRun = groups.flatMap((g, k) => {
  if (g.result) return []
  if (groups.length === 1) return ['the validator did not run: the report above is unchecked and no finding was added']
  return [`validator part ${k + 1} of ${groups.length} did not run: batches ${ids(g).join(' ') || '(none)'} were not checked by it${k === 0 && checked ? ', and coverage and counts were not checked' : ''}`]
})
const onceLines = []
if (once) {
  const sized = Array.isArray(once.lists) ? once.lists : []
  // The exactly-one lookup: an id given twice matches no list or report, so it reads as wrong, never as the first copy.
  const one = (all, b) => { const m = all.filter((l) => l?.id === b.id); return m.length === 1 ? m[0] : undefined }
  const coverage = [
    // A missing file of an unfinished batch, or one left out for its size, is already reported; one the workflow never packed is not.
    ...strings(once.missing).filter((p) => finished.has(p)).map((p) => `${p} | in files.txt and in a finished batch, in no list`),
    ...strings(once.missing).filter((p) => !packed.has(p) && !notAudited.some((f) => f.path === p)).map((p) => `${p} | in files.txt, never given to a batch`),
    ...strings(once.extra).map((p) => `${p} | in a list, not in files.txt`),
    // Each list is compared line for line with what was packed for it: sizes and membership alone pass two swapped lists.
    ...done.flatMap((b) => {
      const got = one(sized, b)?.entries
      return Array.isArray(got) && got.join('\n') === b.files.join('\n') ? [] : [`batch-${b.id}.list | ${Array.isArray(got) ? 'not the lines packed for it' : 'not returned'} | ${b.files.length} expected`]
    }),
    ...sized.filter((l) => !done.some((b) => b.id === l?.id)).map((l) => `batch-${l?.id}.list | not a finished batch's list`),
    // A batch's reply is its agent's word: its file must hold one row for each file packed for it, those and no other
    // (a count alone passes two rows for one file and none for the next), each row must say the lines packed for it
    // were read (a row is not a read: "read=none" is a file nobody audited), and the file must end with its complete line.
    ...done.flatMap((b) => {
      const got = one(Array.isArray(once.reports) ? once.reports : [], b)
      if (!got) return [`batch-${b.id}.md | rows not returned`]
      return [
        ...(Array.isArray(got.rows) && got.rows.map((r) => r?.path).sort().join('\n') === b.files.map(pathOf).sort().join('\n')
          ? b.files.flatMap((e) => {
            const read = String(got.rows.find((r) => r.path === pathOf(e)).read)
            const want = wanted(e)
            return covers(read, want) ? [] : [`${pathOf(e)} | its row in batch-${b.id}.md says read=${read.slice(0, 80)}, not lines ${want.map(([a, z]) => `${a}-${z}`).join(', ')}`]
          })
          : [`batch-${b.id}.md | its rows are not one for each file packed for it | ${b.files.length} expected`]),
        ...(got.complete === true ? [] : [`batch-${b.id}.md | does not end with its complete line`]),
      ]
    }),
  ]
  const gaps = strings(once.gaps)
  // The report agent's own count is not the report: its findings and notes are counted in its text,
  // a finding by a table row that opens with its ID (an ID named anywhere else lists nothing) and a
  // note by a line that starts as one (a quoted note inside a finding is not one).
  const said = String(report?.report)
  const stated = report && { findings: new Set([...said.matchAll(/^\s*\|\s*(B\d{3}-[A-Za-z0-9]+-\d+)\s*\|/gm)].map((m) => m[1])).size, possible: (said.match(/^(?:[-*|\s]|\[[^\]\n]*\])*POSSIBLE [^|\n]*\| [^|\n]*:\d+/gm) ?? []).length }
  // A count an agent returned prints only when it is a whole number.
  const shown = (n) => (prune && !isWhole(n) ? 'an unreadable number of' : n)
  const held = `${shown(once.fileFindings)} findings${stated ? ',' : ' and'} ${shown(once.filePossible)} possible`
  if (findings !== once.fileFindings) onceLines.push(`Counts: the batch replies add up to ${findings} findings, the batch files hold ${shown(once.fileFindings)}`)
  onceLines.push(
    coverage.length ? 'Coverage: NOT CLEAN' : `Coverage: clean (${done.length} finished batch lists, every file of theirs on its list and read whole by its row in its batch file)`,
    ...(prune ? (coverage.length ? [`Coverage faults: ${coverage.length}`] : []) : coverage),
    gaps.length ? 'Split files: NOT CLEAN' : `Split files: no gap (${splits.length} split files)`,
    ...(prune ? (gaps.length ? [`Split-file gaps: ${gaps.length}`] : []) : gaps),
    !stated
      ? `Counts: not compared: the report was not written; the batch files hold ${held}`
      : stated.findings === once.fileFindings && report.findings === once.fileFindings && stated.possible === once.filePossible
        ? `Counts: agree (${held})`
        : `Counts: DIFFER: the report lists ${stated.findings} findings (its reply says ${shown(report.findings)}) and ${stated.possible} possible, the batch files hold ${shown(once.fileFindings)} and ${shown(once.filePossible)}`,
  )
}
const agentNotes = ran.flatMap((g) => strings(g.result.notChecked))
const notChecked = [
  ...(checked ? [] : [`coverage and counts | ${batches.length} batch lists pass one validator agent's room`]),
  ...over.map((b) => `batch ${b.id} | its ${b.result.possible} notes pass one validator agent's room: none of them was checked`),
  ...(prune ? (agentNotes.length ? [`Validator notes not checked: ${agentNotes.length}`] : []) : agentNotes),
  ...entries.filter((e) => !opened.has(e)).map((e) => `${e} | not opened by the validator`),
  ...notAudited.filter((f) => !packed.has(f.path) && !f.reason.endsWith('path not in scope')).map((f) => `${f.path} | not opened by the validator`),
]
const validator = [
  `VALIDATOR STAGE (${VALIDATOR_MODEL}): everything below was checked or written by the validator, not by the audit above. Its findings are also in ${out}/validator-*.md.`,
  ...notRun,
  `Findings: ${findings} from the audit + ${validatorFindings} from the validator = ${findings + validatorFindings}`,
  ...onceLines,
  'At the five-note cap:',
  ...(atCap.size ? [...atCap].map(([e, cut]) => `${e} | five notes, ${cut ? 'cut short' : 'no more-signs line'}`) : ['(none)']),
  'Validator findings:',
  ...(prune ? (validatorRows.length ? validatorRows : ['(none)']) : [found || '(none)']),
  'Opened by the validator:',
  ...(opened.size ? opened : ['(none)']),
  'Not checked by the validator:',
  ...(notChecked.length ? notChecked : ['(none)']),
].join('\n')
return {
  ...summary,
  findings: findings + validatorFindings,
  auditFindings: findings,
  validatorFindings,
  validators: groups.map((g) => ({ batches: ids(g), tokens: V_BASELINE + V_FIXED + g.tokens, ran: !!g.result })),
  report: prune ? ['PRUNE REPORT: built by the workflow from validated fields only', `Kept: ${rows.length} of ${rows.length + dropped.length} proposals`, '| ID | Proposal | Other test |', '|---|---|---|', ...rows, 'Dropped:', ...(dropped.length ? dropped : ['(none)'])].join('\n') : reportText,
  selfCheck: prune ? 'not shown in prune mode: this report holds only fields the workflow checked' : report?.selfCheck ?? 'not written',
  ...(prune && { dropped }),
  validator,
}

// /test-audit promises three things a model cannot be trusted to hold: a bad
// call starts no agent, no more than N batch agents run at once, and no batch
// is packed past the room a 95,000-token context leaves. The workflow runtime
// evaluates the script as a function body, so Node cannot import it: the test
// loads its text and runs it with fake agents, through the real entry point.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const SCRIPT = new URL('../../templates/test-audit.js', import.meta.url);
const AsyncFunction = (async () => {}).constructor;
const OUT = '/tmp/commandeck/audit-1';

const filesOf = (prompt) =>
  prompt.slice(prompt.lastIndexOf('\nFiles:\n')).split('\n').filter((l) => l.startsWith('- ')).map((l) => l.slice(2));
// Offsets default to an evenly spread file's; pass null for a listing that returns none.
const file = (n, lines, bytes, blocks, offsets) => {
  const given = offsets === undefined && blocks ? blocks.map((b) => Math.round(((b - 1) * bytes) / lines)) : offsets;
  return { path: `shared/taxonomy/f${n}.test.ts`, lines, bytes, ...(blocks && { blocks }), ...(given && { offsets: given }) };
};
const every = (from, step, to) => Array.from({ length: Math.ceil((to - from + 1) / step) }, (_, i) => from + i * step);
const many = (count, lines, bytes) => Array.from({ length: count }, (_, i) => file(i, lines, bytes));

// What a validator agent returns when it found nothing; the first one also returns the disk checks.
const CLEAN = { findings: '', atCap: [], opened: [], notChecked: [], missing: [], extra: [], lists: [], gaps: [], fileFindings: 0, filePossible: 0 };
// A batch file's row as the validator returns it: the path it is for and what its read= field says.
const row = (path, read = '1-150') => ({ path, read });
const noted = (n) => (prompt) => ({ complete: true, rows: filesOf(prompt).length, findings: 1, possible: n });

async function run(args, o = {}) {
  const src = (o.src ?? ((s) => s))(readFileSync(SCRIPT, 'utf8').replace('export const meta', 'const meta'));
  const calls = [];
  let inFlight = 0;
  let peak = 0;
  const agent = async (prompt, opts = {}) => {
    calls.push({ prompt, opts });
    if (o.reject?.includes(opts.label)) throw new Error('agent stalled on all 6 attempts');
    if (opts.label === 'phase 0') return 'phase0' in o ? o.phase0 : { out: OUT, mode: 'basic', stop: '' };
    if (opts.label === 'phase 1') return { stop: o.stop ?? '', count: o.count ?? (o.files ?? []).length, files: o.files ?? [] };
    if (opts.label === 'phase 2') return 'records written';
    if (opts.label === 'report') return { report: o.reportText ?? 'the report text', selfCheck: 'the self-check text', findings: o.reportFindings ?? 0 };
    if (/^validator /.test(opts.label ?? '')) return o.validator ? o.validator(prompt, opts) : { ...CLEAN };
    inFlight += 1;
    peak = Math.max(peak, inFlight);
    await new Promise((resolve) => setImmediate(resolve));
    inFlight -= 1;
    if (o.batch) return o.batch(prompt, opts);
    return { complete: true, rows: filesOf(prompt).length, findings: 1, possible: 0 };
  };
  const parallel = (thunks) => Promise.all(thunks.map((t) => t().catch(() => null)));
  const body = new AsyncFunction('agent', 'parallel', 'pipeline', 'phase', 'log', 'args', src);
  const result = await body(agent, parallel, null, () => {}, () => {}, args);
  const batches = calls.filter((c) => /^batch /.test(c.opts.label ?? ''));
  return { result, calls, batches, peak, report: calls.find((c) => c.opts.label === 'report'), validators: calls.filter((c) => /^validator /.test(c.opts.label ?? '')) };
}

test('a call without a usable scope or agent count prints one usage line and starts no agent', async () => {
  const bad = [
    undefined, '', '   ', 'basic', '8 agents', 'full 8 agents',
    'shared/taxonomy 0 agents', 'shared/taxonomy abc agents', 'shared/taxonomy 17 agents',
    'shared/taxonomy 2.5 agents', 'shared/taxonomy -1 agents', 'shared/taxonomy agents',
    { scope: 'shared/taxonomy', agents: 0 }, { mode: 'full' }, 42,
  ];
  for (const args of bad) {
    const { result, calls } = await run(args, { files: many(3, 150, 7000) });
    assert.match(String(result), /^Usage: \/test-audit /, `not refused: ${JSON.stringify(args)}`);
    assert.equal(String(result).includes('\n'), false);
    assert.equal(calls.length, 0, `an agent started for ${JSON.stringify(args)}`);
  }
});

test('a scope that could reach outside the repository or into a shell command is refused', async () => {
  // The scope is typed into shell commands by the agents, so it is a trust boundary.
  for (const args of ['.', '..', '../other', 'src/../../etc', '/etc', '-rf', 'src;rm', 'src$(id)', 'src`id`', 'a|b', '12']) {
    const { result, calls } = await run(args);
    assert.match(String(result), /^Usage: /, `not refused: ${args}`);
    assert.equal(calls.length, 0);
  }
});

test('four batch agents run at once by default, and "8 agents" gives eight, never more', async () => {
  const files = many(20, 150, 30000); // each file fills a batch on its own
  for (const [args, n] of [['shared/taxonomy', 4], ['shared/taxonomy 8 agents', 8], ['shared/taxonomy 1 agent', 1], ['shared/taxonomy basic 16 agents', 16]]) {
    const { batches, peak, result } = await run(args, { files });
    assert.equal(batches.length, 20);
    assert.equal(peak, n, `${args}: ${peak} ran at once`);
    assert.equal(result.agents, n);
  }
});

test('the arguments are read the same as a string, a list or an object', async () => {
  const files = many(6, 150, 7000); // full mode: one file to a batch
  for (const args of ['src/utils shared/taxonomy full 2 agents', ['src/utils', 'shared/taxonomy', 'full', '2 agents'], ['src/utils', 'shared/taxonomy', 'full', '2', 'agents'], { scope: ['src/utils', 'shared/taxonomy'], mode: 'full', agents: 2 }, { scope: 'src/utils shared/taxonomy', mode: 'FULL', agents: '2 agents' }]) {
    const { calls, peak } = await run(args, { files, phase0: { out: OUT, mode: 'full', stop: '' } });
    assert.equal(peak, 2, JSON.stringify(args));
    assert.match(calls[0].prompt, /^SCOPE: src\/utils shared\/taxonomy$/m);
    assert.match(calls[0].prompt, /^MODE: full$/m);
  }
});

test('with no mode given the script does not choose one: the prompt default decides', async () => {
  const { calls, batches } = await run('shared/taxonomy', { files: many(1, 150, 7000), phase0: { out: OUT, mode: 'full', stop: '' } });
  assert.match(calls[0].prompt, /^MODE: not given/m);
  assert.match(batches[0].prompt, /^MODE: full$/m);
});

test('batches are packed by size against the room a 95,000-token context leaves', async () => {
  // Room is 95,000 - 45,000 carried at start - 17,000 batch overhead = 33,000 tokens.
  // A 150-line, 7,000-byte file costs 4,000 + 3 calls + 4,000 written = 15,500: two fit, three do not.
  const { result, batches } = await run('shared/taxonomy', { files: many(5, 150, 7000) });
  assert.deepEqual(batches.map((b) => filesOf(b.prompt).length), [2, 2, 1]);
  assert.deepEqual(result.batches.map((b) => b.tokens), [31000, 31000, 15500]);
  assert.equal(result.batches.every((b) => b.tokens <= 33000 && b.done), true);
  assert.equal(result.findings, 3);
});

// A file too large for one agent is cut between test blocks and each part goes
// to its own agent: nothing is skipped for size alone, nothing is read in part.
test('a file that needs two parts is cut between blocks, each part priced with the head it re-reads', async () => {
  // 600 lines of 70 bytes, a block every 50 lines from line 51: the head is lines 1-50.
  // Whole: 24,000 + 6 calls + 4,000 written = 43,000, past the 33,000.
  // Head + 300 lines: 14,000 + 5 calls + 4,000 = 30,500 fits; head + 350 lines needs a sixth call and does not.
  const long = file(1, 600, 42000, every(51, 50, 600));
  const { result, batches, validators } = await run('shared/taxonomy', { files: [file(0, 150, 7000), long, file(2, 150, 7000)] });
  // The validator re-reads the head too when it opens a part: 300 numbered lines of 70 bytes in three reads.
  assert.match(validators[0].prompt, new RegExp(`^- ${long.path} \\| part 1 of 2 \\| lines 1-350 of 600 \\| 13591$`, 'm'));
  assert.match(validators[0].prompt, new RegExp(`^- ${long.path} \\| part 2 of 2 \\| head lines 1-50, then lines 351-600 of 600 \\| 11864$`, 'm'));
  assert.deepEqual(batches.map((b) => filesOf(b.prompt)), [
    [file(0).path],
    [`${long.path} | part 1 of 2 | lines 1-350 of 600`],
    [`${long.path} | part 2 of 2 | head lines 1-50, then lines 351-600 of 600`],
    [file(2).path],
  ]);
  assert.deepEqual(result.batches.map((b) => b.tokens), [15500, 30500, 28500, 15500]);
  assert.deepEqual(result.split, [{ path: long.path, parts: 2 }]);
  assert.deepEqual(result.notAudited, []);
});

test('an evenly spread file with block offsets splits exactly as it does without them', async () => {
  const starts = every(51, 50, 600);
  const long = file(1, 600, 42000, starts, starts.map((n) => (n - 1) * 70));
  const { result, batches } = await run('shared/taxonomy', { files: [long] });
  assert.deepEqual(batches.map((b) => filesOf(b.prompt)), [
    [`${long.path} | part 1 of 2 | lines 1-350 of 600`],
    [`${long.path} | part 2 of 2 | head lines 1-50, then lines 351-600 of 600`],
  ]);
  assert.deepEqual(result.batches.map((b) => b.tokens), [30500, 28500]);
});

// Lines 1-350 hold 41,000 of the 42,000 bytes: by line share the part was priced
// at 30,500 and handed to an agent; its real cost is 39,929 against 33,000.
test('a part that holds the long lines is priced by its real bytes and listed too large', async () => {
  const long = file(1, 600, 42000, [51, 351], [7000, 41000]);
  const { result, batches } = await run('shared/taxonomy', { files: [long] });
  assert.deepEqual(result.notAudited, [{ path: long.path, reason: 'not audited: block too large (lines 51-350)' }]);
  assert.deepEqual(batches.map((b) => filesOf(b.prompt)), [[`${long.path} | part 1 of 1 | head lines 1-50, then lines 351-600 of 600`]]);
  assert.deepEqual(result.batches.map((b) => b.tokens), [21072]);
});

test('a listing without usable offsets prices every part at a bound no lower than its real cost', async () => {
  // Absent, short, falling, past the end, text, fractional, equal, too close for the lines between,
  // too early for the line, or too near the end for the lines left. Each part is then bounded by the
  // file's 42,000 bytes less one per outside line (over 33,000 tokens), so neither is dispatched.
  const bad = [null, [7000], [41000, 7000], [7000, 50000], ['7000', '41000'], [7000, 1.5], [7000, 7000], [7000, 7100], [10, 41000], [7000, 41900]];
  for (const offsets of bad) {
    const { result, batches } = await run('shared/taxonomy', { files: [file(1, 600, 42000, [51, 351], offsets)] });
    assert.deepEqual(batches, [], JSON.stringify(offsets));
    assert.deepEqual(result.notAudited.map((n) => n.reason), ['not audited: block too large (lines 51-350)', 'not audited: block too large (lines 351-600)'], JSON.stringify(offsets));
  }
});

test('the validator prices opening a part by its real bytes', async () => {
  // Lines 1-350 hold 28,000 bytes: 24,500 by line share, 28,000 real.
  const long = file(1, 600, 42000, [51, 351], [2000, 28000]);
  const { validators } = await run('shared/taxonomy', { files: [long] });
  assert.match(validators[0].prompt, new RegExp(`^- ${long.path} \\| part 1 of 2 \\| lines 1-350 of 600 \\| 15182$`, 'm'));
  assert.match(validators[0].prompt, new RegExp(`^- ${long.path} \\| part 2 of 2 \\| head lines 1-50, then lines 351-600 of 600 \\| 9591$`, 'm'));
});

test('a file that needs three or more parts is covered from its first line to its last, once', async () => {
  // The trial directory's largest file: 1,601 lines, 106,901 bytes, first block at line 190.
  const long = file(1, 1601, 106901, every(190, 30, 1601));
  const { result, batches, report } = await run('shared/taxonomy', { files: [long] });
  const parts = batches.map((b) => filesOf(b.prompt));
  assert.equal(parts.length >= 3, true);
  assert.equal(parts.every((p) => p.length === 1), true);
  const ranges = parts.map(([line]) => line.match(/lines (\d+)-(\d+) of 1601$/).slice(1).map(Number));
  assert.equal(ranges[0][0], 1);
  assert.equal(ranges.at(-1)[1], 1601);
  ranges.slice(1).forEach(([from], i) => assert.equal(from, ranges[i][1] + 1));
  assert.equal(parts.slice(1).every(([line]) => line.includes('| head lines 1-189, then lines ')), true);
  assert.equal(result.batches.every((b) => b.tokens <= 33000), true);
  assert.deepEqual(result.split, [{ path: long.path, parts: parts.length }]);
  assert.deepEqual(result.notAudited, []);
  assert.match(report.prompt, new RegExp(`^${long.path} \\| ${parts.length} parts$`, 'm'));
  assert.match(report.prompt, /split file is ONE file/);
});

test('a part is read and cited by the line numbers of the whole file', async () => {
  const long = file(1, 600, 42000, every(51, 50, 600));
  const { batches, calls } = await run('shared/taxonomy', { files: [long] });
  assert.match(batches[1].prompt, /lines 351-600 of 600/);
  assert.match(batches[1].prompt, /Every line number you write is the file's own/);
  assert.match(batches[1].prompt, /judge only the tests that start in its last range/);
  // The block starts come from the file-list stage: the script cannot read a file.
  const lister = calls.find((c) => c.opts.label === 'phase 1');
  assert.match(lister.prompt, /more than 300 lines or more than 20000 bytes/);
  assert.equal(Object.hasOwn(lister.opts.schema.properties.files.items.properties, 'blocks'), true);
});

test('a file under the size the lister reports block starts for always fits one agent', async () => {
  const basic = await run('shared/taxonomy', { files: [file(1, 300, 20000)] });
  assert.deepEqual(basic.result.split, []);
  assert.equal(basic.batches.length, 1);
  const full = await run('shared/taxonomy full', { files: [file(1, 150, 10000)], phase0: { out: OUT, mode: 'full', stop: '' } });
  assert.match(full.calls.find((c) => c.opts.label === 'phase 1').prompt, /more than 150 lines or more than 10000 bytes/);
  assert.deepEqual(full.result.split, []);
  assert.equal(full.batches.length, 1);
});

test('one block too large for an agent is the only thing listed not audited, by file and line range', async () => {
  // Lines 10-799 are one block of 790 lines; the block from line 800 fits with the head.
  const giant = file(1, 900, 90000, [10, 800]);
  const noBlocks = file(2, 150, 38502);
  const oneLine = file(3, 1, 1000000);
  const bad = file(4, 900, 90000, [0, 5000, 'x', 10, 10, 800]);
  // 150 lines cost 11,500 before content, so 37,625 bytes (21,500 tokens) is the last size that fits.
  const edge = file(6, 150, 37625);
  const over = file(7, 150, 37627);
  const { result, batches, report, validators } = await run('shared/taxonomy', { files: [giant, noBlocks, oneLine, bad, file(5, 150, 7000), edge, over] });
  assert.deepEqual(batches.map((b) => filesOf(b.prompt)), [
    [`${giant.path} | part 1 of 1 | head lines 1-9, then lines 800-900 of 900`],
    [`${bad.path} | part 1 of 1 | head lines 1-9, then lines 800-900 of 900`],
    [file(5).path],
    [edge.path],
  ]);
  assert.deepEqual(result.notAudited, [
    { path: giant.path, reason: 'not audited: block too large (lines 10-799)' },
    { path: noBlocks.path, reason: 'not audited: block too large (lines 1-150)' },
    { path: oneLine.path, reason: 'not audited: block too large (lines 1-1)' },
    { path: bad.path, reason: 'not audited: block too large (lines 10-799)' },
    { path: over.path, reason: 'not audited: block too large (lines 1-150)' },
  ]);
  assert.match(report.prompt, new RegExp(`^${giant.path} \\| not audited: block too large \\(lines 10-799\\)$`, 'm'));
  // A block left out for size is already reported, so the validator's gap check is told not to count it.
  assert.equal(validators[0].prompt.includes(`not a gap: ${giant.path} (lines 10-799); `), true);
});

// In the trial one agent read all 901 lines of a file the prompt told it to
// read 300 of, so the limit may not rest on an agent obeying a read range.
test('a long file is priced as read whole, never by the 300 lines the prompt allows', async () => {
  // 700 lines, 14,000 bytes: 8,000 content + 7 calls + 4,000 written = 29,500, inside the 33,000.
  const fits = await run('shared/taxonomy', { files: [file(1, 700, 14000)] });
  assert.deepEqual(fits.result.batches.map((b) => b.tokens), [29500]);
  assert.match(fits.batches[0].prompt, /Read every file whole/);
});

// The runtime refuses a report file written by a workflow agent, so the report
// and the self-check come back as text and only batch findings stay in files.
test('the report comes back as text with the output folder named, and no agent is told to write REPORT.md', async () => {
  const { result, report } = await run('shared/taxonomy', { files: many(2, 150, 7000) });
  assert.match(report.prompt, /Do not write REPORT\.md or SELF-CHECK\.md/);
  assert.equal(result.report, 'the report text');
  assert.equal(result.selfCheck, 'the self-check text');
  assert.equal(result.out, OUT);
});

test('full mode charges each file for the subject and history reads it adds', async () => {
  const { batches } = await run('shared/taxonomy full', { files: many(3, 150, 7000), phase0: { out: OUT, mode: 'full', stop: '' } });
  assert.deepEqual(batches.map((b) => filesOf(b.prompt).length), [1, 1, 1]);
});

test('every file lands in exactly one batch or in the not-audited list', async () => {
  const files = [...many(30, 90, 4000), file(98, 800, 60000), file(99, 10, 500000)];
  const { result, batches } = await run('shared/taxonomy 3 agents', { files });
  const seen = [...batches.flatMap((b) => filesOf(b.prompt)), ...result.notAudited.map((f) => f.path)];
  assert.deepEqual([...seen].sort(), files.map((f) => f.path).sort());
  assert.equal(new Set(seen).size, files.length);
});

test('a batch agent gets its own file list and named sections, never the whole prompt or another list', async () => {
  const files = many(6, 150, 7000);
  const { batches, calls } = await run('shared/taxonomy', { files });
  const headings = readFileSync(new URL('../../templates/test-audit-prompt.md', import.meta.url), 'utf8')
    .split('\n').filter((l) => l.startsWith('## ')).map((l) => l.slice(3));
  for (const b of batches) {
    const mine = filesOf(b.prompt);
    for (const f of files) assert.equal(b.prompt.includes(f.path), mine.includes(f.path));
    assert.match(b.prompt, /read ONLY these sections/);
    assert.doesNotMatch(b.prompt, /"Phase [0124]|"Parameters|"Phase 5/);
    assert.match(b.prompt, /"Checks", "Finding format"/);
  }
  // Cross-file contract: every section a stage is sent to must exist in the prompt file.
  for (const c of calls) {
    const named = c.prompt.match(/read ONLY these sections and no other: (.*)\.$/m)[1].match(/"[^"]+"/g).map((s) => s.slice(1, -1));
    for (const name of named) assert.equal(headings.filter((h) => h.startsWith(name)).length, 1, `section "${name}" for ${c.opts.label}`);
  }
});

// A Sonnet check of the Haiku audit was ordered: it must come last, after the
// report it checks, and no other stage may move to the dearer model.
test('the validator is the last stage and the only one on Sonnet; every other agent runs on Haiku', async () => {
  const { calls } = await run('shared/taxonomy', { files: many(3, 150, 7000) });
  assert.deepEqual(calls.map((c) => c.opts.label), ['phase 0', 'phase 1', 'phase 2', 'batch 001', 'batch 002', 'report', 'validator 1']);
  assert.deepEqual(calls.map((c) => c.opts.model), ['haiku', 'haiku', 'haiku', 'haiku', 'haiku', 'haiku', 'sonnet']);
  assert.match(calls.at(-1).prompt, /"Validator"/);
  assert.match(calls.at(-1).prompt, /validator-1\.md/);
});

// The reader must be able to tell the validator's findings from the audit's,
// and every count in the result must agree with the text beside it.
test('the validator findings come after the report under their own heading, and the total is the audit count plus the validator count', async () => {
  const text = 'ID: V001-CR-1\nSign: banned credit\n\nID: V002-TC-1\nSign: title contradicts body';
  const validator = () => ({ ...CLEAN, findings: text, opened: [file(0).path], atCap: [{ entry: file(1).path, cut: false }, { entry: file(2).path, cut: true }], lists: [{ id: '001', entries: [file(0).path, file(1).path] }, { id: '002', entries: [file(2).path] }], reports: [{ id: '001', rows: [row(file(0).path), row(file(1).path)], complete: true }, { id: '002', rows: [row(file(2).path)], complete: true }], fileFindings: 2, filePossible: 1 });
  // A quoted line that merely contains a note's text is not a note: only a line that starts as one counts.
  const reportText = 'x\n| B001-T2-1 | S2 | a |\n| B002-T2-1 | S6 | b |\n[batch-001] POSSIBLE T2 | shared/taxonomy/f0.test.ts:24 | check it\nQuote: a.test.mjs:265: POSSIBLE T2 | shared/taxonomy/f0.test.ts:24 | check it\n';
  const { result } = await run('shared/taxonomy', { files: many(3, 150, 7000), validator, reportFindings: 2, reportText });
  assert.equal(result.auditFindings, 2);
  assert.equal(result.validatorFindings, 2);
  assert.equal(result.findings, 4);
  assert.equal(result.report.startsWith('x\n'), true);
  const keys = Object.keys(result);
  assert.equal(keys.indexOf('validator') > keys.indexOf('report'), true);
  assert.match(result.validator, /^VALIDATOR STAGE \(sonnet\)/);
  assert.match(result.validator, /^Findings: 2 from the audit \+ 2 from the validator = 4$/m);
  assert.equal(result.validator.includes(text), true);
  assert.match(result.validator, /^Coverage: clean/m);
  assert.match(result.validator, /^Counts: agree \(2 findings, 1 possible\)$/m);
  assert.match(result.validator, new RegExp(`^${file(1).path} \\| five notes, no more-signs line$`, 'm'));
  assert.match(result.validator, new RegExp(`^${file(2).path} \\| five notes, cut short$`, 'm'));
  assert.doesNotMatch(result.validator, new RegExp(`^${file(0).path} \\| not opened by the validator$`, 'm'));
  assert.match(result.validator, new RegExp(`^${file(1).path} \\| not opened by the validator$`, 'm'));
  const differ = await run('shared/taxonomy', { files: many(3, 150, 7000), validator: () => ({ ...validator(), filePossible: 3 }), reportFindings: 2, reportText });
  assert.match(differ.result.validator, /^Counts: DIFFER: the report lists 2 findings \(its reply says 2\) and 1 possible, the batch files hold 2 and 3$/m);
  assert.match(differ.result.validator, /^Coverage: clean/m);
  // The report agent's own number is not the report: a text that lists no finding does not agree with two on disk.
  const omitted = await run('shared/taxonomy', { files: many(3, 150, 7000), validator: () => ({ ...validator(), filePossible: 0 }), reportFindings: 2, reportText: 'Confirmed: 0 findings\nConditional: 0 findings' });
  assert.match(omitted.result.validator, /^Counts: DIFFER: the report lists 0 findings \(its reply says 2\) and 0 possible, the batch files hold 2 and 0$/m);
  // Only a row of a findings table lists a finding: an ID named in prose or in a later cell does not, and a row given twice is one.
  for (const [text, listed] of [
    ['Confirmed: 0 findings\nNot checked: B001-T2-1 and B002-T2-1 were omitted from the tables.', 0],
    ['| note | see B001-T2-1 |\n| note | see B002-T2-1 |', 0],
    ['| B001-T2-1 | S2 | a |\n| B001-T2-1 | S2 | a |', 1],
  ]) {
    const r = await run('shared/taxonomy', { files: many(3, 150, 7000), validator: () => ({ ...validator(), filePossible: 0 }), reportFindings: 2, reportText: text });
    assert.match(r.result.validator, new RegExp(`^Counts: DIFFER: the report lists ${listed} findings \\(its reply says 2\\) and 0 possible, the batch files hold 2 and 0$`, 'm'), text);
  }
  // The audit's count in the total is the batch agents' own; the files may hold another.
  const replies = await run('shared/taxonomy', { files: many(3, 150, 7000), validator: () => ({ ...validator(), fileFindings: 5 }), reportFindings: 2, reportText });
  assert.match(replies.result.validator, /^Counts: the batch replies add up to 2 findings, the batch files hold 5$/m);
  const wrong = await run('shared/taxonomy', { files: many(3, 150, 7000), validator: () => ({ ...validator(), lists: [{ id: '001', entries: [file(0).path, file(1).path] }], extra: ['shared/taxonomy/stray.test.ts'] }) });
  assert.match(wrong.result.validator, /^Coverage: NOT CLEAN$/m);
  assert.match(wrong.result.validator, /^batch-002\.list \| not returned \| 1 expected$/m);
  assert.match(wrong.result.validator, /^shared\/taxonomy\/stray\.test\.ts \| in a list, not in files\.txt$/m);
  // A file of files.txt that the listing stage never handed over is on no list and in no batch: it is named, never dropped.
  // One the workflow already reports (its batch did not finish) is not named twice.
  const unfinished = await run('shared/taxonomy', { files: [file(0, 150, 20000), file(1, 150, 20000)], reject: ['batch 002'], validator: () => ({ ...validator(), lists: [{ id: '001', entries: [file(0).path] }], reports: [{ id: '001', rows: [row(file(0).path)], complete: true }], missing: ['shared/taxonomy/never-packed.test.ts', file(1).path] }) });
  assert.match(unfinished.result.validator, /^Coverage: NOT CLEAN$/m);
  assert.match(unfinished.result.validator, /^shared\/taxonomy\/never-packed\.test\.ts \| in files\.txt, never given to a batch$/m);
  assert.doesNotMatch(unfinished.result.validator, new RegExp(`^${file(1).path} \\| in files`, 'm'));
  // A list whose id is no finished batch's, and a finished batch's id given twice, are not clean either.
  const oneFile = [file(0, 150, 7000)];
  const goodLists = [{ id: '001', entries: [file(0).path] }];
  const goodReports = [{ id: '001', rows: [row(file(0).path)], complete: true }];
  const coverageOf = async (lists, reports = goodReports) => (await run('shared/taxonomy', { files: oneFile, validator: () => ({ ...CLEAN, lists, reports }) })).result.validator;
  assert.match(await coverageOf(goodLists), /^Coverage: clean/m);
  const extraList = await coverageOf([...goodLists, { id: '999', entries: [file(0).path] }]);
  assert.match(extraList, /^Coverage: NOT CLEAN$/m);
  assert.match(extraList, /^batch-999\.list \| not a finished batch's list$/m);
  assert.match(await coverageOf([...goodLists, ...goodLists]), /^batch-001\.list \| not returned \| 1 expected$/m);
  assert.match(await coverageOf(goodLists, [...goodReports, ...goodReports]), /^batch-001\.md \| rows not returned$/m);
  // A validator that obeys its brief returns only what the brief lets it read, so the brief must let it read every list.
  const asked = (await run('shared/taxonomy', { files: oneFile, validator: () => ({ ...CLEAN, lists: goodLists, reports: goodReports }) })).validators[0].prompt;
  assert.match(asked, /Read every batch-\*\.list in OUT, finished or not/);
  // A batch's reply is its agent's word: the batch file must hold one row for each file on its list, those files and no other,
  // and end with its complete line. A count alone passes two rows for one file and none for the next.
  const two = { id: '002', rows: [row(file(2).path)], complete: true };
  const both = [row(file(0).path), row(file(1).path)];
  const wrong1 = /^batch-001\.md \| its rows are not one for each file packed for it \| 2 expected$/m;
  for (const [reports, line] of [
    [[{ id: '001', rows: [row(file(0).path), row(file(0).path)], complete: true }, two], wrong1],
    [[{ id: '001', rows: [], complete: true }, two], wrong1],
    [[{ id: '001', rows: [...both, row(file(2).path)], complete: true }, two], wrong1],
    [[{ id: '001', rows: 2, complete: true }, two], wrong1],
    [[{ id: '001', rows: [file(0).path, file(1).path], complete: true }, two], wrong1],
    [[{ id: '001', rows: both, complete: true }, { ...two, complete: false }], /^batch-002\.md \| does not end with its complete line$/m],
    [[{ id: '001', rows: both, complete: true }], /^batch-002\.md \| rows not returned$/m],
    // A row is not a read: a file its row calls unread, or read in part, was not audited, whatever the row count says.
    [[{ id: '001', rows: [row(file(0).path, 'none'), row(file(1).path)], complete: true }, two], new RegExp(`^${file(0).path} \\| its row in batch-001\\.md says read=none, not lines 1-150$`, 'm')],
    [[{ id: '001', rows: [row(file(0).path), row(file(1).path, '1-100')], complete: true }, two], new RegExp(`^${file(1).path} \\| its row in batch-001\\.md says read=1-100, not lines 1-150$`, 'm')],
    [[{ id: '001', rows: [row(file(0).path, '1-75, 77-150'), row(file(1).path)], complete: true }, two], new RegExp(`^${file(0).path} \\| its row in batch-001\\.md says read=1-75, 77-150, not lines 1-150$`, 'm')],
  ]) {
    const r = await run('shared/taxonomy', { files: many(3, 150, 7000), validator: () => ({ ...validator(), reports }) });
    assert.match(r.result.validator, /^Coverage: NOT CLEAN$/m);
    assert.match(r.result.validator, line);
  }
  // Reads in several ranges that join up are the whole file.
  const joined = await run('shared/taxonomy', { files: many(3, 150, 7000), validator: () => ({ ...validator(), filePossible: 0, reports: [{ id: '001', rows: [row(file(0).path, '1-75,76-150'), row(file(1).path, '1-100 101-150')], complete: true }, two] }) });
  assert.match(joined.result.validator, /^Coverage: clean/m);
  // A part's row is for its file, and must have read the lines its list line names: the head and its own range.
  const long = file(1, 600, 42000, every(51, 50, 600));
  const parts = [`${long.path} | part 1 of 2 | lines 1-350 of 600`, `${long.path} | part 2 of 2 | head lines 1-50, then lines 351-600 of 600`];
  const splitRun = (reads) => run('shared/taxonomy', { files: [long], validator: () => ({ ...CLEAN, lists: parts.map((e, k) => ({ id: `00${k + 1}`, entries: [e] })), reports: reads.map((read, k) => ({ id: `00${k + 1}`, rows: [row(long.path, read)], complete: true })) }) });
  assert.match((await splitRun(['1-150, 151-300, 301-350', '1-50, 351-500, 501-600'])).result.validator, /^Coverage: clean/m);
  assert.match((await splitRun(['1-350', '351-600'])).result.validator, new RegExp(`^${long.path} \\| its row in batch-002\\.md says read=351-600, not lines 1-50, 351-600$`, 'm'));
  // Two lists with each other's files hold every path once and the right number of lines, and are still wrong.
  const swapped = await run('shared/taxonomy', { files: [file(0, 150, 20000), file(1, 150, 20000)], validator: () => ({ ...CLEAN, lists: [{ id: '001', entries: [file(1).path] }, { id: '002', entries: [file(0).path] }] }) });
  assert.match(swapped.result.validator, /^Coverage: NOT CLEAN$/m);
  assert.match(swapped.result.validator, /^batch-001\.list \| not the lines packed for it \| 1 expected$/m);
  assert.match(swapped.result.validator, /^batch-002\.list \| not the lines packed for it \| 1 expected$/m);
});

// agent() has no token limit, so the validator's work is packed like a batch:
// a run with more notes than one agent can open is split, never squeezed.
test('notes past one validator agent\'s room are split by batch across two agents, each within the limit', async () => {
  // Room is 95,000 - 52,000 carried - 20,000 fixed = 23,000; the first agent also pays 5,000 + 160 a list line for the disk checks.
  // A batch of 10 notes costs 10 x (80 + 600) = 6,800: the first agent takes two (19,880 of 23,000), a third would not fit.
  const { result, validators } = await run('shared/taxonomy 1 agent', { files: many(8, 150, 7000), batch: noted(10) });
  assert.deepEqual(validators.map((v) => v.opts.label), ['validator 1', 'validator 2']);
  assert.deepEqual(result.validators, [
    { batches: ['001', '002'], tokens: 52000 + 20000 + 6280 + 13600, ran: true },
    { batches: ['003', '004'], tokens: 52000 + 20000 + 13600, ran: true },
  ]);
  assert.equal(result.validators.every((v) => v.tokens <= 95000), true);
  assert.match(validators[0].prompt, /^Notes files to check, and no other: batch-001\.md batch-002\.md$/m);
  assert.match(validators[1].prompt, /^Notes files to check, and no other: batch-003\.md batch-004\.md$/m);
  assert.match(validators[0].prompt, /coverage and counts/);
  assert.doesNotMatch(validators[1].prompt, /coverage and counts/);
  // What is left of each agent's room is what it may spend opening files, and each file carries its price.
  assert.match(validators[0].prompt, /^Room left for opening files: 3120 tokens\.$/m);
  assert.match(validators[1].prompt, /^Room left for opening files: 9400 tokens\.$/m);
  assert.match(validators[1].prompt, new RegExp(`^- ${file(4).path} \\| 4091$`, 'm'));
  assert.doesNotMatch(validators[1].prompt, new RegExp(`^- ${file(0).path} `, 'm'));
  const one = await run('shared/taxonomy', { files: many(8, 150, 7000), batch: noted(5) });
  assert.equal(one.validators.length, 1);
});

// The validator may run short of room; what it left is then named, so a
// reader never takes an unopened file or an unread note for a clean one.
test('what no validator agent had room for, and every file it did not open, is listed as not checked', async () => {
  const batch = (prompt, opts) => ({ complete: true, rows: filesOf(prompt).length, findings: 0, possible: opts.label === 'batch 001' ? 40 : 2 });
  const validator = () => ({ ...CLEAN, opened: [file(3).path, 'shared/taxonomy/never-listed.test.ts'], notChecked: ['shared/taxonomy/f2.test.ts:10 | cited range not opened'] });
  const { result, validators } = await run('shared/taxonomy', { files: many(4, 150, 7000), batch, validator });
  assert.equal(validators.length, 1);
  assert.match(validators[0].prompt, /^Notes files to check, and no other: batch-002\.md$/m);
  assert.match(result.validator, /^Not checked by the validator:$/m);
  assert.match(result.validator, /^batch 001 \| its 40 notes pass one validator agent's room: none of them was checked$/m);
  assert.match(result.validator, /^shared\/taxonomy\/f2\.test\.ts:10 \| cited range not opened$/m);
  for (const n of [0, 1, 2]) assert.match(result.validator, new RegExp(`^${file(n).path} \\| not opened by the validator$`, 'm'));
  assert.doesNotMatch(result.validator, /f3\.test\.ts \| not opened/);
  assert.doesNotMatch(result.validator, /never-listed/);
  assert.equal(result.validators[0].ran, true);
});

// A dead validator must cost the reader nothing the Haiku audit produced.
test('a validator that fails or returns nothing leaves the report in place and says in one line that it did not run', async () => {
  for (const o of [{ reject: ['validator 1'] }, { validator: () => null }]) {
    const { result } = await run('shared/taxonomy', { files: many(3, 150, 7000), ...o });
    assert.equal(result.report, 'the report text');
    assert.equal(result.selfCheck, 'the self-check text');
    assert.match(result.validator, /^the validator did not run: the report above is unchecked and no finding was added$/m);
    assert.equal(result.validatorFindings, 0);
    assert.equal(result.findings, 2);
    assert.deepEqual(result.validators.map((v) => v.ran), [false]);
  }
  const part = await run('shared/taxonomy', { files: many(8, 150, 7000), batch: noted(10), reject: ['validator 2'] });
  assert.match(part.result.validator, /^validator part 2 of 2 did not run: batches 003 004 were not checked by it$/m);
  assert.match(part.result.validator, /^Coverage: /m);
  const first = await run('shared/taxonomy', { files: many(8, 150, 7000), batch: noted(10), reject: ['validator 1'] });
  assert.match(first.result.validator, /^validator part 1 of 2 did not run: batches 001 002 were not checked by it, and coverage and counts were not checked$/m);
  assert.doesNotMatch(first.result.validator, /^Coverage: /m);
});

// The report stage has its own room; the validator reads the batch files, so
// a report that could not be written is no reason to skip the check.
test('the validator still runs when the report was not written', async () => {
  const batch = (prompt) => ({ complete: true, rows: filesOf(prompt).length, findings: 40, possible: 0 });
  const { result, validators } = await run('shared/taxonomy', { files: many(4, 150, 7000), batch });
  assert.equal(validators.length, 1);
  assert.match(result.report, /^not written: /);
  assert.match(result.validator, /^Counts: not compared: the report was not written; the batch files hold 0 findings and 0 possible$/m);
  // In the trial 108 notes and no finding passed the report's room, and the line blamed "0 findings".
  const notes = await run('shared/taxonomy', { files: many(4, 150, 7000), batch: noted(60) });
  assert.match(notes.result.report, /^not written: 2 findings and 120 POSSIBLE lines pass one report agent's room; /);
});

test('a stop from setup ends the run before any batch agent', async () => {
  const a = await run('shared/taxonomy', { phase0: { out: OUT, mode: 'basic', stop: 'cannot create OUT' } });
  assert.match(String(a.result), /cannot create OUT/);
  assert.deepEqual(a.calls.map((c) => c.opts.label), ['phase 0']);
  const b = await run('shared/taxonomy', { stop: 'SCOPE too large for basic mode', files: many(3, 150, 7000) });
  assert.match(String(b.result), /SCOPE too large for basic mode/);
  assert.equal(b.batches.length, 0);
  const c = await run('shared/taxonomy', { phase0: null });
  assert.match(String(c.result), /stopped/);
  assert.equal(c.calls.length, 1);
});

test('an output folder or file path the setup agent returns is not trusted as given', async () => {
  // Both are pasted into later agents' instructions, which run shell commands.
  for (const out of ['relative/dir', '/tmp/x; rm -rf ~', '/tmp/x/../../etc', '', '/tmp/a b']) {
    const r = await run('shared/taxonomy', { phase0: { out, mode: 'basic', stop: '' }, files: many(1, 150, 7000) });
    assert.match(String(r.result), /stopped/, out);
    assert.equal(r.calls.length, 1);
  }
  const files = [file(1, 150, 7000), { path: 'src/other/x.test.ts', lines: 10, bytes: 100 }, { path: 'shared/taxonomy/$(id).test.ts', lines: 10, bytes: 100 }, { path: 'shared/taxonomy/../../x.test.ts', lines: 1, bytes: 1 }, { path: 'shared/taxonomy/y.test.ts', lines: -1, bytes: 1.5 }];
  const { result, batches } = await run('shared/taxonomy', { files });
  assert.deepEqual(batches.flatMap((b) => filesOf(b.prompt)), [files[0].path]);
  assert.deepEqual(result.notAudited.map((f) => f.reason), ['not audited: path not in scope', 'not audited: path not in scope', 'not audited: path not in scope', 'not audited: size unknown']);
});

test('a batch whose agent fails or stops short is reported NOT DONE and the run goes on', async () => {
  const outcomes = [null, { complete: false, rows: 1, findings: 0, possible: 0 }, { complete: true, rows: 1, findings: 0, possible: 0 }];
  const batch = (prompt, opts) => {
    const i = Number(opts.label.slice(6)) - 1;
    if (i === 3) throw new Error('agent stalled on all 6 attempts');
    return i in outcomes ? outcomes[i] : { complete: true, rows: filesOf(prompt).length, findings: 2, possible: 1 };
  };
  const { result, report } = await run('shared/taxonomy', { files: many(10, 150, 7000), batch });
  assert.deepEqual(result.batches.map((b) => b.done), [false, false, false, false, true]);
  assert.match(report.prompt, /^batch-001 \| 2 \| NOT DONE$/m);
  assert.match(report.prompt, /^batch-003 \| 2 \| NOT DONE$/m);
  assert.match(report.prompt, /^batch-005 \| 2 \| done$/m);
  assert.equal(result.findings, 2);
});

test('findings past the report agent\'s own room stop the report instead of overfilling it', async () => {
  const batch = (prompt) => ({ complete: true, rows: filesOf(prompt).length, findings: 40, possible: 0 });
  const { result, report } = await run('shared/taxonomy', { files: many(4, 150, 7000), batch });
  assert.equal(report, undefined);
  assert.match(result.report, /^not written: /);
  assert.equal(result.findings, 80);
});

// agent() has no token limit, so a file with twenty findings would be written
// up twenty times; the packing charges for one, so the brief must stop at one.
test('a batch agent writes up one finding per file, the one the packing charged for', async () => {
  const { batches } = await run('shared/taxonomy', { files: many(2, 150, 7000) });
  assert.match(batches[0].prompt, /at most ONE finding in the finding format/);
  assert.match(batches[0].prompt, /at most FIVE one-line POSSIBLE lines/);
  assert.match(batches[0].prompt, /MORE SIGNS NOT LISTED/);
});

// A real file-list agent once returned 56 entries for 57 files, every path
// absolute: packed as given, that run would have audited nothing and said so quietly.
test('a file list that came back short or outside the scope stops the run instead of auditing less', async () => {
  const short = await run('shared/taxonomy', { files: many(3, 150, 7000), count: 4 });
  assert.match(short.result, /^test-audit stopped at the file list: 3 entries came back for 4 test files/);
  assert.equal(short.batches.length, 0);
  const absolute = many(3, 150, 7000).map((f) => ({ ...f, path: `/repo/${f.path}` }));
  const outside = await run('shared/taxonomy', { files: absolute });
  assert.match(outside.result, /^test-audit stopped at the file list: no listed file is inside the scope/);
  assert.equal(outside.calls.length, 2);
  assert.match(outside.calls[1].prompt, /never an absolute path/);
});

// The script cannot see the disk, so it trusts no folder an agent names except
// one plain name directly under the scratch root the script itself carries.
test('the output folder is one plain name directly under the scratch root, or the run stops', async () => {
  const elsewhere = ['/tmp/commandeck', '/tmp/commandeck/', '/tmp/commandeck/a/b', '/tmp/commandeck/..', '/tmp/commandeck/.', '/tmp/commandeck-other/x', '/tmp/other/x', '/Users/someone/Documents', '/repo/tmp/commandeck/x'];
  for (const out of elsewhere) {
    const { result, calls } = await run('shared/taxonomy', { files: many(2, 150, 7000), phase0: { out, mode: 'basic', stop: '' } });
    assert.match(result, /^test-audit stopped in set-up: /, out);
    assert.equal(calls.length, 1, out);
  }
  const { calls, batches } = await run('shared/taxonomy', { files: many(2, 150, 7000), phase0: { out: '/tmp/commandeck/test-audit-20261013-shared-taxonomy-2', mode: 'basic', stop: '' } });
  assert.equal(batches.length, 1);
  assert.match(calls[0].prompt, /plain `mkdir`/);
});

// agent() has no token limit, so the packing can only charge for a stated cap
// on what a batch agent writes; a cap that bit must show, never hide.
test('the files a batch agent cut short at the cap are named in the result and in the report', async () => {
  const long = file(9, 600, 42000, every(51, 50, 600));
  const batch = (prompt) => {
    const entries = filesOf(prompt);
    return { complete: true, rows: entries.length, findings: 1, possible: 5, capped: [entries[0], 'shared/taxonomy/not-in-this-batch.test.ts'] };
  };
  const { result, report } = await run('shared/taxonomy', { files: [...many(4, 150, 7000), long], batch });
  assert.deepEqual(result.capped, [
    file(0).path,
    file(2).path,
    `${long.path} | part 1 of 2 | lines 1-350 of 600`,
    `${long.path} | part 2 of 2 | head lines 1-50, then lines 351-600 of 600`,
  ]);
  assert.equal(result.cappedFiles, 3);
  assert.match(report.prompt, /"Cut short by the per-file cap"/);
  assert.match(report.prompt, new RegExp(`^${file(2).path}$`, 'm'));
  const none = await run('shared/taxonomy', { files: many(2, 150, 7000) });
  assert.deepEqual(none.result.capped, []);
  assert.equal(none.result.cappedFiles, 0);
});

test('a scope spelled with ./, a doubled slash or a trailing slash names the same directory', async () => {
  for (const spelling of ['./shared/taxonomy', 'shared//taxonomy/', 'shared/./taxonomy', './/shared/taxonomy//']) {
    const { result, batches } = await run(`${spelling} 2 agents`, { files: many(2, 150, 7000) });
    assert.match(batches[0].prompt, /^SCOPE: shared\/taxonomy$/m, spelling);
    assert.deepEqual(result.notAudited, [], spelling);
  }
  assert.match((await run('./')).result, /^Usage: /);
  assert.match((await run('.')).result, /^Usage: /);
});

// A failed batch may have written findings nobody counted. The report agent's
// room is sized from the counts, so it may read only the batches that gave one.
test('the report agent is given the findings files of finished batches only', async () => {
  const batch = (prompt, opts) => {
    if (opts.label === 'batch 001') throw new Error('agent stalled on all 6 attempts');
    if (opts.label === 'batch 002') return { complete: false, rows: 1, findings: 9, possible: 0 };
    return { complete: true, rows: filesOf(prompt).length, findings: 2, possible: 1 };
  };
  const { result, report } = await run('shared/taxonomy', { files: many(6, 150, 7000), batch });
  assert.match(report.prompt, /^Findings files to read, and no other: batch-003\.md$/m);
  assert.match(report.prompt, /NOT DONE.*not checked/);
  assert.equal(result.findings, 2);
  const none = await run('shared/taxonomy', { files: many(2, 150, 7000), batch: () => null });
  assert.match(none.report.prompt, /^Findings files to read, and no other: \(none\)$/m);
});

test('a stage whose agent call is rejected ends or degrades the run the way a dead agent does', async () => {
  const files = many(2, 150, 7000);
  assert.match((await run('shared/taxonomy', { files, reject: ['phase 0'] })).result, /^test-audit stopped in set-up: /);
  assert.match((await run('shared/taxonomy', { files, reject: ['phase 1'] })).result, /^test-audit stopped at the file list: /);
  const noRecords = await run('shared/taxonomy', { files, reject: ['phase 2'] });
  assert.equal(noRecords.batches.length, 1);
  assert.equal(noRecords.result.report, 'the report text');
  const noReport = await run('shared/taxonomy', { files, reject: ['report'] });
  assert.match(noReport.result.report, /^not written: the report agent failed/);
  assert.equal(noReport.result.out, OUT);
  assert.equal(noReport.result.batches[0].done, true);
});

// The trial's report agent used about 39,000 tokens above its start with no
// finding to read, and could not name a batch tag without the Checks section.
test('the report agent reads the Checks section, and its room is what the trial measured', async () => {
  const each = (n) => (prompt) => ({ complete: true, rows: filesOf(prompt).length, findings: n, possible: 0 });
  const fits = await run('shared/taxonomy', { files: many(4, 150, 7000), batch: each(13) });
  assert.match(fits.report.prompt, /"Checks"/);
  const over = await run('shared/taxonomy', { files: many(4, 150, 7000), batch: each(14) });
  assert.equal(over.report, undefined);
  assert.match(over.result.report, /^not written: 28 findings/);
});

test('the script carries two facts about one repository, both named at its top: a port replaces those two lines', async () => {
  const src = readFileSync(SCRIPT, 'utf8');
  const facts = src.split('\n').filter((l) => /^const (PROMPT|OUT_ROOT) = /.test(l));
  assert.deepEqual(facts, ["const PROMPT = 'templates/test-audit-prompt.md'", "const OUT_ROOT = '/tmp/commandeck'"]);
  assert.equal(src.indexOf(facts[1]) < src.indexOf('function parseArgs'), true);
  const rest = src.split('\n').filter((l) => !facts.includes(l)).join('\n');
  assert.doesNotMatch(rest, /\/tmp\/|npm |policy\/|shared\/|src\/|\.claude\/(?!workflows \()/i);
});

// Set-up writes the two paths in, and the agents type them into shell commands.
test('a prompt path or scratch root that is not plain path characters starts no agent', async () => {
  for (const [name, bad] of [['PROMPT', "/Users/a b/templates/test-audit-prompt.md"], ['OUT_ROOT', '/home/x;id/scratch'], ['OUT_ROOT', '/home/$(id)'], ['PROMPT', '/a/../b.md']]) {
    const src = (s) => s.replace(new RegExp(`^const ${name} = .*$`, 'm'), `const ${name} = ${JSON.stringify(bad)}`);
    const { result, calls } = await run('shared/taxonomy', { files: many(2, 150, 7000), src });
    assert.match(String(result), /^test-audit cannot run here/, bad);
    assert.equal(calls.length, 0);
  }
});

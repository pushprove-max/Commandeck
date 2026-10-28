// /test-audit reports "Coverage: clean" only when every packed line was read, and hands no agent
// a part priced below its real bytes: an agent past its room stops mid-file, and the report
// would still read as whole. The workflow runtime evaluates the script as a function body,
// so Node cannot import it: the test loads its text and runs it with fake agents.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';

const SCRIPT = new URL('../../templates/test-audit.js', import.meta.url);
const AsyncFunction = (async () => {}).constructor;
const filesOf = (prompt) => prompt.slice(prompt.lastIndexOf('\nFiles:\n')).split('\n').filter((l) => l.startsWith('- ')).map((l) => l.slice(2));

// run <args> <files from the file list> <what the validator returns> <fields to lay over the reply of a stage, by its label>
async function run(args, files, validator = () => ({}), replies = {}) {
  const prompts = [];
  const agent = async (prompt, { label }) => {
    const over = replies[label] ?? {};
    if (label === 'phase 0') return { out: '/tmp/commandeck/audit-1', mode: 'basic', stop: '', ...over };
    if (label === 'phase 1') return { stop: '', count: files.length, files, ...over };
    if (label === 'phase 2') return 'records written';
    if (label === 'report') return { report: 'the report text', selfCheck: 'the self-check text', findings: 0, ...over };
    if (label.startsWith('validator ')) return { findings: '', atCap: [], opened: [], notChecked: [], missing: [], extra: [], lists: [], gaps: [], fileFindings: 0, filePossible: 0, ...validator(), ...over };
    prompts.push(prompt);
    return { complete: true, rows: filesOf(prompt).length, findings: 0, possible: 0, capped: [], ...over };
  };
  const parallel = (thunks) => Promise.all(thunks.map((t) => t()));
  const src = readFileSync(SCRIPT, 'utf8').replace('export const meta', 'const meta');
  const result = await new AsyncFunction('agent', 'parallel', 'log', 'args', src)(agent, parallel, () => {}, args);
  return { result, prompts, batches: prompts.map(filesOf) };
}

test('a row whose read= field names lines it did not read is not clean coverage', async () => {
  const path = 'src/example/a.test.ts';
  const coverage = async (read) => (await run('src/example', [{ path, lines: 150, bytes: 7000 }], () => ({
    lists: [{ id: '001', entries: [path] }], reports: [{ id: '001', rows: [{ path, read }], complete: true }],
  }))).result.validator.match(/^Coverage: .*/m)[0];
  assert.match(await coverage('1-100; not read: 101-150'), /^Coverage: NOT CLEAN/);
  assert.match(await coverage('1-75, 76-150'), /^Coverage: clean/);
});

// Lines 1-350 hold 41,000 of the 42,000 bytes: by line share the part was priced
// at 30,500 and handed to an agent; its real bytes imply 39,929 against 33,000.
test('a part that holds the long lines is priced by its real bytes and listed too large', async () => {
  const path = 'src/example/long.test.ts';
  const { result, batches } = await run('src/example', [{ path, lines: 600, bytes: 42000, blocks: [51, 351], offsets: [7000, 41000] }]);
  assert.deepEqual(result.notAudited, [{ path, reason: 'not audited: block too large (lines 51-350)' }]);
  assert.deepEqual(batches, [[`${path} | part 1 of 1 | head lines 1-50, then lines 351-600 of 600`]]);
  assert.deepEqual(result.batches.map((b) => b.tokens), [21072]);
});

// Prune mode (issue 435): subtraction only, and no agent-written text in the result.
const K = { id: 'B001-T2-1', proposal: 'remove', otherTest: 'src/b.test.ts:keeper' };
const S = 'add a new regression test';
const ONE = [{ path: 'src/a.test.ts', lines: 1, bytes: 1 }];
const KEEPER_ROW = '| B001-T2-1 | remove | src/b.test.ts:keeper |';
const REPORT_ROW = '| B001-T2-1 | S1 | Proposal: add await | unknown | low | high |';

test('prune mode on a fixture folder sends subtraction-only instructions to every batch agent (issue 435)', async () => {
  const dir = 'scripts/__tests__/fixtures/test-audit-prune';
  const root = new URL(`../../${dir}/`, import.meta.url);
  // Sizes are faked to 30,000 bytes so the two small files fill a batch each: the rule must reach every batch agent.
  const files = readdirSync(root).sort().map((n) => ({ path: `${dir}/${n}`, lines: readFileSync(new URL(n, root), 'utf8').split('\n').length - 1, bytes: 30000 }));
  assert.equal(files.length, 2);
  const prune = await run(`${dir} prune`, files);
  assert.equal(prune.prompts.length, 2);
  for (const p of prune.prompts) {
    assert.match(p, /subtraction only/);
    assert.match(p, /never propose adding/);
    assert.match(p, /"Prune mode"/);
  }
  const basic = await run(`${dir} basic`, files);
  assert.equal(basic.prompts.length, 2);
  for (const p of basic.prompts) assert.doesNotMatch(p, /subtraction only|"Prune mode"/);
});

test('prune mode drops a validator finding that names no other test or proposes an addition (issue 435)', async () => {
  const findings = 'ID: V001-T2-1\nProposal: remove\n\nID: V001-T2-2\nProposal: add a test\nOther test: src/b.test.ts:keeper';
  const { result } = await run('src prune', ONE, () => ({ findings }));
  assert.match(result.report, /Kept: 0 of 2 proposals/);
  assert.doesNotMatch(result.report, /\| V001-T2-\d \|/);
  assert.deepEqual(result.dropped.map((d) => d.split(' | ')[0]), ['V001-T2-1', 'V001-T2-2']);
  assert.equal(result.validatorFindings, 0);
});

test('prune mode drops a batch finding with Proposal add await and no Other test from the report and the count (issue 435)', async () => {
  const bad = { id: 'B001-T2-2', proposal: 'add await', otherTest: '' };
  const { result } = await run('src prune', ONE, undefined, { 'batch 001': { findings: 2, proposals: [K, bad] }, report: { report: `${REPORT_ROW}\n| B001-T2-2 | S6 | Proposal: add await | unknown | low | high |`, findings: 2 } });
  assert.match(result.report, /Kept: 1 of 2 proposals/);
  assert.ok(result.report.includes(KEEPER_ROW));
  assert.doesNotMatch(result.report, /\| B001-T2-2 \|/);
  assert.doesNotMatch(result.report, /add await/);
  assert.equal(result.dropped.length, 1);
  assert.match(result.dropped[0], /^B001-T2-2 \| /);
});

test("prune mode publishes a kept finding's validated proposal, never the report row's own text (issue 435)", async () => {
  const { result } = await run('src prune', ONE, undefined, { 'batch 001': { findings: 1, proposals: [K] }, report: { report: REPORT_ROW, findings: 1 } });
  assert.ok(result.report.includes(KEEPER_ROW));
  assert.doesNotMatch(result.report, /add await/);
  assert.doesNotMatch(JSON.stringify(result), /add await/);
});

test('prune mode publishes no agent text (issue 435)', async () => {
  const merge = { id: 'B001-T2-2', proposal: 'merge', otherTest: `src/b.test.ts:k | ${S}` };
  const files = [...ONE, { path: `Proposal: ${S} in src/a.test.ts`, lines: 1, bytes: 1 }];
  const { result } = await run('src prune', files, () => ({
    findings: `ID: V001-T2-1\nResidual protection: ${S}`, notChecked: [S], missing: [S], extra: [S], gaps: [S],
    lists: [{ id: '001', entries: [S] }], reports: [{ id: '001', rows: [{ path: S, read: S }], complete: true }], fileFindings: S, filePossible: S,
  }), {
    'phase 1': { count: 2 },
    'batch 001': { findings: 2, proposals: [K, merge] },
    report: { report: `| B001-T2-1 | S1 | duplicate | unknown | low | high |\nProposal: ${S} in src/a.test.ts`, selfCheck: S, findings: S },
  });
  assert.doesNotMatch(JSON.stringify(result), new RegExp(S));
  assert.match(result.report, /Kept: 1 of 3 proposals/);
  assert.ok(result.report.includes(KEEPER_ROW));
  assert.doesNotMatch(result.report, /\| B001-T2-2 \|/);
  assert.deepEqual(result.notAudited, [{ path: '(withheld)', reason: 'not audited: path not in scope' }]);
});

test('prune mode stops with no agent text (issue 435)', async () => {
  const { result: early } = await run('src prune', ONE, undefined, { 'phase 0': { stop: S } });
  const { result: listed } = await run('src prune', ONE, undefined, { 'phase 1': { stop: S } });
  for (const r of [early, listed]) {
    assert.match(r, /^test-audit stopped/);
    assert.doesNotMatch(r, new RegExp(S));
  }
});

test('prune mode keeps a validator proposal with a V id (issue 435)', async () => {
  const findings = 'ID: V001-T2-1\nProposal: remove\nOther test: src/b.test.ts:keeper';
  const { result } = await run('src prune', ONE, () => ({ findings }));
  assert.ok(result.report.includes('| V001-T2-1 | remove | src/b.test.ts:keeper |'));
  assert.match(result.report, /Kept: 1 of 1 proposals/);
  assert.equal(result.validatorFindings, 1);
});

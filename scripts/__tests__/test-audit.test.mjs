// /test-audit reports "Coverage: clean" only when every packed line was read, and hands no agent
// a part priced below its real bytes: an agent past its room stops mid-file, and the report
// would still read as whole. The workflow runtime evaluates the script as a function body,
// so Node cannot import it: the test loads its text and runs it with fake agents.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const SCRIPT = new URL('../../templates/test-audit.js', import.meta.url);
const AsyncFunction = (async () => {}).constructor;
const filesOf = (prompt) => prompt.slice(prompt.lastIndexOf('\nFiles:\n')).split('\n').filter((l) => l.startsWith('- ')).map((l) => l.slice(2));

// run <args> <files from the file list> <what the validator returns>
async function run(args, files, validator = () => ({})) {
  const prompts = [];
  const agent = async (prompt, { label }) => {
    if (label === 'phase 0') return { out: '/tmp/commandeck/audit-1', mode: 'basic', stop: '' };
    if (label === 'phase 1') return { stop: '', count: files.length, files };
    if (label === 'phase 2') return 'records written';
    if (label === 'report') return { report: 'the report text', selfCheck: 'the self-check text', findings: 0 };
    if (label.startsWith('validator ')) return { findings: '', atCap: [], opened: [], notChecked: [], missing: [], extra: [], lists: [], gaps: [], fileFindings: 0, filePossible: 0, ...validator() };
    prompts.push(prompt);
    return { complete: true, rows: filesOf(prompt).length, findings: 0, possible: 0, capped: [] };
  };
  const parallel = (thunks) => Promise.all(thunks.map((t) => t()));
  const src = readFileSync(SCRIPT, 'utf8').replace('export const meta', 'const meta');
  const result = await new AsyncFunction('agent', 'parallel', 'log', 'args', src)(agent, parallel, () => {}, args);
  return { result, batches: prompts.map(filesOf) };
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

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
function cost(rows) {
  const code = [
    'import json, sys',
    'sys.path.insert(0, "scripts")',
    'import dashboard_limit as d',
    'print(json.dumps(d.cost(json.loads(sys.argv[1]), 44, 0, 94.5 * 3600)))',
  ].join('\n');
  return JSON.parse(execFileSync(
    'python3', ['-B', '-c', code, JSON.stringify(rows)],
    { cwd: root, encoding: 'utf8' },
  ));
}

test('projected hourly cost matches the supplied design', () => {
  const result = cost([
    [0, 'claude-opus-5-5', 0, 0, 0, 0, 25304500],
  ]);
  assert.equal(result.week, 506.09);
  assert.equal(result.perHour.toFixed(2), '6.85');
  assert.equal(result.perHour, result.projected / 168);
});

test('requests without any known price leave every dollar field unmeasured', () => {
  const result = cost([[0, 'unsupported-model', 0, 0, 0, 0, 1000]]);
  assert.equal(result.unpricedRequests, 1);
  for (const field of ['week', 'projected', 'perPoint', 'perHour']) {
    assert.equal(result[field], null, `${field} has no price source`);
  }
});

test('a request whose usage lacks a count is unpriced, never priced as zero', () => {
  const result = cost([
    [0, 'claude-opus-5-5', 0, 0, 0, 0, 1000000],
    [0, 'claude-opus-5-5', 1000, 0, 0, 0, null],
  ]);
  assert.equal(result.unpricedRequests, 1);
  assert.equal(result.week, cost([[0, 'claude-opus-5-5', 0, 0, 0, 0, 1000000]]).week);
});

test('the Codex quota reading is the newest by its own time, not by its file', () => {
  // An older session resumed: its file is the newest, its last reading is not.
  const code = [
    'import json, os, sys, tempfile',
    'sys.path.insert(0, "scripts")',
    'import dashboard_limit as d',
    'now = 1790000000',
    'iso = lambda t: __import__("datetime").datetime.fromtimestamp(t, __import__("datetime").timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")',
    'def w(p, at, used, mtime):',
    '    line = {"timestamp": iso(at), "payload": {"rate_limits": {"primary": {"window_minutes": 10080, "used_percent": used, "resets_at": now + 3600}}}}',
    '    open(p, "w").write(json.dumps(line) + "\\n" + json.dumps({"timestamp": iso(mtime), "payload": {}}) + "\\n")',
    '    os.utime(p, (mtime, mtime))',
    't = tempfile.mkdtemp()',
    'w(os.path.join(t, "resumed.jsonl"), now - 9000, 10, now - 10)',
    'w(os.path.join(t, "newer.jsonl"), now - 600, 90, now - 500)',
    'print(json.dumps(d.codex(t, now)))',
  ].join('\n');
  const out = JSON.parse(execFileSync('python3', ['-B', '-c', code], { cwd: root, encoding: 'utf8' }));
  assert.equal(out.usedPct, 90);
});

test('the Codex weekly reading is found in either window slot', () => {
  // Codex puts the 5-hour window first when the plan has one: the week is then `secondary`.
  const code = [
    'import json, os, sys, tempfile',
    'sys.path.insert(0, "scripts")',
    'import dashboard_limit as d',
    'now = 1790000000',
    'iso = __import__("datetime").datetime.fromtimestamp(now - 60, __import__("datetime").timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")',
    'line = {"timestamp": iso, "payload": {"rate_limits": {',
    '    "primary": {"window_minutes": 300, "used_percent": 5, "resets_at": now + 600},',
    '    "secondary": {"window_minutes": 10080, "used_percent": 77, "resets_at": now + 3600}}}}',
    't = tempfile.mkdtemp()',
    'open(os.path.join(t, "s.jsonl"), "w").write(json.dumps(line) + "\\n")',
    'print(json.dumps(d.codex(t, now)))',
  ].join('\n');
  const out = JSON.parse(execFileSync('python3', ['-B', '-c', code], { cwd: root, encoding: 'utf8' }));
  assert.equal(out.usedPct, 77);
});

// One logged call as Claude Code writes it; an advisor call sits only in usage.iterations.
function callPrice(iterations) {
  const usage = { input_tokens: 4, cache_read_input_tokens: 253751, output_tokens: 1744,
    cache_creation: { ephemeral_5m_input_tokens: 0, ephemeral_1h_input_tokens: 3877 }, iterations };
  const record = { requestId: 'req_1', timestamp: '2026-10-12T00:00:00Z', type: 'assistant',
    message: { model: 'claude-opus-5-5', usage } };
  const code = [
    'import json, sys',
    'sys.path.insert(0, "scripts")',
    'import dashboard_limit as d',
    'print(json.dumps(d.price(d.request_row(json.loads(sys.argv[1])))))',
  ].join('\n');
  return JSON.parse(execFileSync(
    'python3', ['-B', '-c', code, JSON.stringify(record)],
    { cwd: root, encoding: 'utf8' },
  ));
}
const turn = { type: 'message', input_tokens: 2, output_tokens: 1196, cache_read_input_tokens: 124937 };
const advisor = (model) => ({ type: 'advisor_message', model, input_tokens: 129139, output_tokens: 10893,
  cache_read_input_tokens: 0, cache_creation_input_tokens: 0 });

test('an advisor iteration adds exactly its own tokens at its own model price', () => {
  const without = callPrice([turn]);
  const withAdvisor = callPrice([turn, advisor('claude-fable-5-1'), turn]);
  // Fable list price: 129139 input at $10/M plus 10893 output at $50/M.
  assert.equal((withAdvisor - without).toFixed(9), '1.836040000');
});

test('an advisor model with no list price leaves the whole call unpriced', () => {
  assert.equal(callPrice([turn, advisor('unsupported-model')]), null);
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

test('a failed log read is not a fresh zero-block measurement', () => {
  const script = fileURLToPath(new URL('../dashboard.sh', import.meta.url));
  const body = fs.readFileSync(script, 'utf8')
    .match(/^guard_blocks\(\) \{[\s\S]*?^\}/m)[0];
  const result = spawnSync('bash', ['-c', `
    ok() { echo source=fresh >&2; }
    nm() { echo source=not-measured >&2; }
    ${body}
    guard_blocks
  `], {
    encoding: 'utf8',
    env: {
      ...process.env,
      COMMANDECK_HOOK_FIRE_LOG:
        fileURLToPath(new URL('../', import.meta.url)),
    },
  });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stderr, /source=not-measured/);
  assert.doesNotMatch(result.stderr, /source=fresh/);
});

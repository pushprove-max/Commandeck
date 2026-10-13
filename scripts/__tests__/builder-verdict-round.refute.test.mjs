import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

test('a running round cannot inherit the previous round verdict', () => {
  const src = readFileSync(new URL('../../dashboard/app.js', import.meta.url), 'utf8');
  const body = src.slice(
    src.indexOf('  function builderSteps('),
    src.indexOf('  function unitCard('),
  );
  const render = new Function(
    'h', 'parseTime', 'clock', 'num',
    body + '\nreturn builderSteps;',
  )(
    (_tag, _class, text) => text,
    Date.parse,
    String,
    v => typeof v === 'number' ? v : null,
  );
  const lines = render({
    verdict: 'VERDICT: GO',
    steps: [
      { kind: 'codex', pass: 'review', round: 2,
        start: '2026-10-11T12:00:00Z', end: null, rc: null },
      { kind: 'codex', pass: 'adversarial', round: 1,
        start: '2026-10-11T11:00:00Z',
        end: '2026-10-11T11:30:00Z', rc: 0 },
    ],
  });
  assert.doesNotMatch(lines[0], /VERDICT: GO/);
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { createRequire } from 'node:module';

import path from 'node:path';

// jsdom is lent, never shipped (see dashboard-view.test.sh).
const { JSDOM } = createRequire(path.join(process.env.COMMANDECK_TEST_NODE_MODULES, '..', 'x.js'))('jsdom');
const read = name => fs.readFileSync(
  new URL(`../../dashboard/${name}`, import.meta.url), 'utf8'
);

test('collector staleness reaches Alerts without another successful collect', () => {
  let now = Date.parse('2026-10-11T12:00:00Z');
  let tick;
  class Clock extends Date {
    static now() { return now; }
  }
  const dom = new JSDOM(read('index.html'), {
    url: 'http://dash.test/index.html'
  });
  vm.runInNewContext(read('app.js'), {
    window: dom.window,
    document: dom.window.document,
    Date: Clock,
    setInterval(fn, ms) {
      if (ms === 1000) tick = fn;
      return 1;
    },
    clearInterval() {},
    setTimeout() { return 1; },
    clearTimeout() {},
    console
  });
  dom.window.DASH = {
    updatedAt: new Date(now).toISOString(),
    alerts: [],
    sources: { alerts: { status: 'fresh' } }
  };
  dom.window.document.querySelector('script[src^="data.js"]')
    .dispatchEvent(new dom.window.Event('load'));

  const alerts = () =>
    dom.window.document.getElementById('alerts').textContent;
  assert.doesNotMatch(alerts(), /collector.*(?:stale|dead|slow|stuck)/i);
  now += 180000;
  tick();
  assert.doesNotMatch(alerts(), /collector.*(?:stale|dead|slow|stuck)/i);
  now += 1000;
  tick();
  assert.match(alerts(), /collector.*(?:stale|dead|slow|stuck)/i);
  assert.doesNotMatch(alerts(), /No alerts/i);
});

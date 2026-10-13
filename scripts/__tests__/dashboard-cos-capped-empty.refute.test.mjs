import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { createRequire } from 'node:module';

import path from 'node:path';

// jsdom is lent, never shipped (see dashboard-view.test.sh).
const { JSDOM } = createRequire(path.join(process.env.COMMANDECK_TEST_NODE_MODULES, '..', 'x.js'))('jsdom');
const view = new URL('../../dashboard/', import.meta.url);

test('an incomplete sample cannot establish that no unread message exists', () => {
  const dom = new JSDOM(
    fs.readFileSync(new URL('index.html', view), 'utf8'),
    { url: 'http://dash.test/' },
  );
  const source = fs.readFileSync(new URL('app.js', view), 'utf8')
    .replace(
      '  function renderCos(s) {',
      '  window.renderCosForTest = renderCos;\n'
        + '  function renderCos(s) {',
    );

  vm.runInNewContext(source, {
    window: dom.window,
    document: dom.window.document,
    Date,
    console,
    setInterval: () => 0,
    clearInterval: () => {},
    setTimeout: () => 0,
    clearTimeout: () => {},
  });
  try {
    dom.window.renderCosForTest({
      unread: 0,
      oldestUnreadAgeSec: null,
      incomplete: true,
    });
    const term = [...dom.window.document.querySelectorAll('#cos-facts dt')]
      .find((dt) => dt.textContent === 'Oldest of them');
    assert.equal(term.nextElementSibling.textContent, 'Not measured');
  } finally {
    dom.window.close();
  }
});

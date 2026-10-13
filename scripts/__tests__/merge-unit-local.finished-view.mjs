// The page on what a real merge recorded. merge-unit-local.test.sh merges units in two scratch projects under a
// test home, runs the collector on each, and names the snapshot in COMMANDECK_TEST_FINISHED; it runs this file. Both
// projects hold a unit named `green`, so a name alone can never tell their builds apart. What the owner must be able
// to trust: a merged build is listed, a cleared one stays cleared in a browser that never saw the click, an open P1
// keeps the needs panel, and none of it crosses from one project to the other.
import { test, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const { JSDOM, VirtualConsole } = createRequire(path.join(process.env.COMMANDECK_TEST_NODE_MODULES, '..', 'x.js'))('jsdom');
const VIEW = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'dashboard');
const html = fs.readFileSync(path.join(VIEW, 'index.html'), 'utf8');
const appSrc = fs.readFileSync(path.join(VIEW, 'app.js'), 'utf8');
const snapshot = () => JSON.parse(fs.readFileSync(process.env.COMMANDECK_TEST_FINISHED, 'utf8'));
const recorded = (name) => snapshot().projects[name].units.finishedBuilds;

beforeEach(() => mock.timers.enable({ apis: ['setInterval', 'setTimeout', 'Date'], now: Date.parse(snapshot().updatedAt) }));
afterEach(() => mock.timers.reset());

// One project's page, on the host's layout file and what this browser kept; w.puts is every save it sent.
function page(project, { file, store = {}, data = snapshot() } = {}) {
  // jsdom cannot navigate: the page's own move to the home project is reported to a console nobody reads.
  const dom = new JSDOM(html, { url: `http://dash.test/index.html?project=${project}`, virtualConsole: new VirtualConsole() });
  const w = dom.window;
  for (const [k, v] of Object.entries(store)) w.localStorage.setItem(k, v);
  if (file !== undefined) w.DASH_LAYOUT = file;
  w.puts = [];
  w.fetch = (url, opt) => { w.puts.push(JSON.parse(opt.body)); return Promise.resolve({ ok: true, status: 204 }); };
  vm.runInNewContext(appSrc, { window: w, document: w.document, setInterval, clearInterval, setTimeout, clearTimeout, Date, console });
  w.DASH = data;
  w.document.querySelector('script[src^="data.js"]').dispatchEvent(new w.Event('load'));
  return w;
}
const finished = (w) => [...w.document.querySelectorAll('#builds-list > .build.finished')];
const names = (w) => finished(w).map((b) => b.dataset.unit);
const facts = (el) => Object.fromEntries([...el.querySelectorAll('dt')].map((dt) => [dt.textContent, dt.nextElementSibling.textContent]));
const kept = (w) => Object.fromEntries(Object.entries(w.localStorage));
const sha = (name, unit) => recorded(name).find((f) => f.unit === unit).sha;
const clear = (w, unit) => finished(w).find((b) => b.dataset.unit === unit).querySelector('button[data-close]')
  .dispatchEvent(new w.MouseEvent('click', { bubbles: true }));

test('the record is the merge\'s own: both projects merged a unit named green, as two commits', () => {
  const [a, b] = [recorded('proj'), recorded('other')].map((l) => l.find((f) => f.unit === 'green'));
  assert.ok(a && b && a.sha !== b.sha && /^[0-9a-f]{40}$/.test(a.sha) && /^[0-9a-f]{40}$/.test(b.sha));
  assert.deepEqual(recorded('other').map((f) => f.unit), ['green'], 'the second project merged one unit');
  assert.ok(recorded('proj').length > 2, 'the first merged several');
  assert.ok(recorded('proj').some((f) => f.unit.length > 80), 'a unit name longer than a layout id is listed all the same');
  assert.ok(!recorded('proj').some((f) => f.unit === 'twin'), 'a checkout elsewhere under the same folder name shares the file, never the list');
});

test('a finished build the merge recorded is listed under its project, drawn finished, with what it left open', () => {
  const w = page('proj');
  assert.deepEqual(names(w), recorded('proj').map((f) => f.unit), 'every build the collector read, newest first');
  const tail = finished(w).find((b) => b.dataset.unit === 'tail'), row = recorded('proj').find((f) => f.unit === 'tail');
  assert.deepEqual([...tail.querySelectorAll('.mdl')].map((t) => t.textContent), ['Builder', 'merged']);
  assert.ok([...tail.querySelectorAll('.step')].every((s) => s.classList.contains('done')), 'every step is behind it');
  assert.equal(facts(tail)['Open at merge'], 'P2 1', 'the finding the proof printed as open');
  assert.equal(facts(tail)['Merge commit'], row.sha.slice(0, 8));
  assert.equal(facts(finished(w).find((b) => b.dataset.unit === 'green'))['Open at merge'], 'nothing open');
});

test('a cleared build stays cleared after a reload and in a second browser session', () => {
  const w = page('proj');
  clear(w, 'green');
  assert.ok(!names(w).includes('green'));
  assert.deepEqual(w.puts.at(-1), { rev: 0, project: 'proj', closed: [sha('proj', 'green')] }, 'the clear is saved to the host under this project, by its commit');
  const reloaded = page('proj', { store: kept(w) });
  assert.ok(!names(reloaded).includes('green') && names(reloaded).includes('tail'), 'a reload in the same browser');
  // What the host holds after that save (dashboard-server.test.sh pins the write): a browser with nothing of its own.
  const second = page('proj', { file: { rev: 1, projects: { proj: { closed: [sha('proj', 'green')] } } } });
  assert.ok(!names(second).includes('green') && names(second).includes('tail'), 'a second browser session reads it from the host');
});

test('an open P1 on a listed build keeps the needs panel; the merge itself never records one', () => {
  for (const name of ['proj', 'other']) for (const f of recorded(name)) assert.equal(f.open.P1, 0, `${name}/${f.unit}: the proof refuses a P1, so the merge wrote 0`);
  const look = (w) => w.document.querySelector('#needs').hasAttribute('data-look');
  assert.equal(look(page('proj')), false, 'nothing waits and no P1 is open: the panel is not kept');
  // The one value below the merge did not write: a P1 on the line it wrote for `tail`.
  const data = snapshot();
  data.projects.proj.units.finishedBuilds.find((f) => f.unit === 'tail').open.P1 = 1;
  assert.equal(look(page('proj', { data })), true, 'an open P1 keeps it');
  assert.equal(look(page('proj', { data, file: { rev: 1, projects: { proj: { closed: [sha('proj', 'tail')] } } } })), true, 'cleared or not');
  assert.equal(look(page('other', { data })), false, 'and it is the first project\'s alone');
});

test('one project\'s finished and cleared builds never appear under the other', () => {
  assert.deepEqual(names(page('other')), ['green'], 'none of the first project\'s builds');
  const w = page('proj');
  clear(w, 'green');
  const file = { rev: 1, projects: { proj: { closed: [sha('proj', 'green')] } } };
  assert.deepEqual(names(page('other', { file, store: kept(w) })), ['green'], 'the other project\'s green is still listed, in the same browser and on the same host file');
  assert.ok(!names(page('proj', { file })).includes('green'));
  // A name the address made up is on its way back to the home project: what it draws meanwhile is the home
  // project's own, never the other's, and it saves nothing.
  const home = recorded('proj').map((f) => `${f.unit} ${f.sha.slice(0, 8)}`);
  for (const made of ['nobody', '../other', 'proj/../other', '%2e%2e%2fother', '/other', 'other/', 'other%2f', '__proto__']) {
    const stray = page(encodeURIComponent(made), { file });
    const drawn = finished(stray).map((b) => `${b.dataset.unit} ${facts(b)['Merge commit']}`);
    assert.ok(drawn.length > 0 && drawn.every((d) => home.includes(d)), `?project=${made} drew ${drawn}`);
    assert.deepEqual(stray.puts, [], `?project=${made} saved nothing`);
  }
});

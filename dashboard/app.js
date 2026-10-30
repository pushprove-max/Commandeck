// Read-only ops view. Re-reads the collector's data.js every 15 s by swapping a
// local <script>; nothing else loads. Every data value reaches the page as text
// (textContent or created nodes) and SVG gets numbers only. The data contract
// is written by scripts/dashboard.sh; a null anywhere means not measured.
(function () {
  'use strict';
  const REFRESH_MS = 15000;
  const STOPPED_MS = 180000; // the collector writes every 60 s; three misses is a stop
  const ALIVE_MS = 45000; // the --loop heartbeat writes alive.js every 15 s; three misses is a dead process
  const STUCK_CYCLE_MS = 900000; // a hung read keeps the heartbeat ticking: a cycle past 15 min is stuck (main ruling 2026-10-10)
  // The one stated threshold: a decision waiting, or a unit in one stage, past 2 h is red.
  const DECISION_LATE_SEC = 7200;
  const STUCK_SEC = 7200;
  const STAGES = ['planning', 'building','review', 'fixing', 'waiting-main'];
  // The long-lived worktree's stage, from dashboard.sh: a seat, never a unit in flight.
  const SEATS = new Map([['chief-of-staff', 'Chief-of-Staff seat'], ['fast-lane', 'Fast lane'], ['research-lane', 'Research lane'], ['seat', 'Standing seat']]);
  const SVG_NS = 'http://www.w3.org/2000/svg';
  let data = null;
  let inflight = null;

  const byId = (id) => document.getElementById(id);
  const q = (sel, root) => (root || document).querySelector(sel);
  const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);
  const pad = (n) => String(n).padStart(2, '0');
  function h(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined && text !== null) e.textContent = String(text);
    return e;
  }
  function put(el, kids) { el.replaceChildren(...kids.filter(Boolean)); }
  const nm = (what) => h('span', 'nm', what ? `${what} not measured` : 'Not measured');
  // Every absolute time on the page goes through these three: US 12-hour, in the viewer's local zone.
  const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const hm = (d, secs) => `${d.getHours() % 12 || 12}:${pad(d.getMinutes())}${secs ? `:${pad(d.getSeconds())}` : ''} ${d.getHours() < 12 ? 'AM' : 'PM'}`;
  const clock = (ms) => hm(new Date(ms), true);
  const when = (ms) => { const d = new Date(ms); return `${MONTHS[d.getMonth()]} ${d.getDate()}, ${d.getFullYear()}, ${hm(d)}`; };
  const dayTime = (ms) => { const d = new Date(ms); return `${DAYS[d.getDay()]} ${hm(d)}`; };
  function ago(sec) {
    if (sec < 90) return `${Math.max(0, Math.round(sec))} s`;
    if (sec < 5400) return `${Math.round(sec / 60)} min`;
    if (sec < 172800) return `${Math.round(sec / 3600)} h`;
    return `${Math.round(sec / 86400)} d`;
  }
  function tokens(n) {
    if (num(n) === null) return null;
    if (n >= 1e6) return `${(n / 1e6).toFixed(1)}M`;
    if (n >= 1e3) return `${(n / 1e3).toFixed(1)}k`;
    return String(n);
  }
  const cell = (v, fmt) => { const td = h('td'); const n = num(v); td.append(n === null ? nm() : h('span', 'n', fmt ? fmt(n) : n.toLocaleString('en-US'))); return td; };
  const tr = (cells) => { const r = h('tr'); r.append(...cells); return r; };
  const parseTime = (s) => (typeof s === 'string' ? Date.parse(s) : NaN);

  const STALE_SEC = 86400; // a unit with no sign for a day is stale
  const STAGE_TONE = { planning: 'p', building: 'b', review: 'a', fixing: 'o', 'waiting-main': 'r' };
  const STAGE_LABEL = { planning: 'Planning', building: 'Building', review: 'In review', fixing: 'Fixing', 'waiting-main': 'Waiting on main' };
  // Which panels need a look this render: set by each renderer, read by the "Needs a look" switch.
  let looks = new Set();
  // The unit-cost source of the snapshot being drawn: the cost tables say when it was read and since when it is stale.
  let unitCost = null;
  const flag =(id, on) => { if (on) looks.add(id); };

  function badge(text, tone) { return h('span', `badge ${tone || ''}`.trim(), text); }

  // bar(label, value, max, tone, note) -- width through CSSOM, which the CSP allows.
  function bar(label, value, max, tone, note) {
    const row = h('div', 'bar-row');
    const n = num(value);
    row.append(h('span', 'bar-label', label));
    const track = h('span', 'bar-track');
    const fill = h('span', `bar-fill ${tone || ''}`.trim());
    fill.style.width = n === null || !max ? '0%' : `${Math.max(2, Math.min(100, (n / max) * 100))}%`;
    track.append(fill);
    row.append(track, n === null ? nm() : h('span', 'bar-value n', note || n.toLocaleString('en-US')));
    return row;
  }
  // The mockup's pieces. A segmented bar: parts are [percent, colour class]; mark is the white line.
  const pct = (v) => `${Math.max(0, Math.min(100, Number.isFinite(v) ? v : 0)).toFixed(1)}%`;
  function mbar(parts, cls, mark) {
    const b = h('div', `mbar ${cls || ''}`.trim());
    for (const [w, tone] of parts) { const i = h('i', tone); i.style.width = pct(w); b.append(i); }
    if (num(mark) !== null) { const u = h('u'); u.style.left = pct(mark); b.append(u); }
    return b;
  }
  function uline(name, small) {
    const d = h('div', 'uline');
    d.append(h('span', null, name), h('small', null, small || ''));
    return d;
  }
  // A caption row: each side is text, a node, or a list of them.
  function cap(left, right) {
    const d = h('div', 'cap');
    for (const side of [left, right]) { const s = h('span'); s.append(...[].concat(side).filter((x) => x !== null && x !== undefined)); d.append(s); }
    return d;
  }
  const strong = (t) => h('b', null, t);
  function steps(items) {
    const d = h('div', 'steps');
    for (const [label, state, value] of items) {
      const s = h('div', `step ${state || ''}`.trim(), label);
      if (value !== undefined) s.append(h('b', null, value));
      d.append(s);
    }
    return d;
  }
  function legend(el, items, tail) {
    el.replaceChildren();
    for (const [tone, text, count] of items) {
      el.append(h('b', tone), text);
      if (count !== undefined) el.append(' ', h('strong', null, count));
    }
    if (tail) el.append(` · ${tail}`);
  }
  const sub = (id, text) => { byId(id).textContent = text; };
  // GitHub links open in a new tab. An address from the snapshot is used only when it is on github.com, so no data
  // value can make a link to anywhere else; the repository's own address is the collector's (dashboard.sh github_panes).
  const ghUrl = (u) => (typeof u === 'string' && /^https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/(issues|pull)\/\d+$/.test(u) ? u : null);
  const repoUrl = (g) => (g && typeof g.repo === 'string' && /^https:\/\/github\.com\/[\w.-]+\/[\w.-]+$/.test(g.repo) ? g.repo : null);
  function link(href, cls, text) {
    const a = h('a', cls, text);
    a.href = href;
    a.target = '_blank';
    a.rel = 'noopener';
    return a;
  }

  // Card freshness from its own sources: the worst status wins and the age is
  // the oldest sample, so one fresh read cannot cover a stale one.
  function cardAge(card, sources, now) {
    const ids = (card.dataset.sources || '').split(' ').filter(Boolean);
    const recs = ids.map((id) => (sources && sources[id]) || { status: 'not-measured', sampledAt: null, staleSince: null });
    const state = recs.some((r) => r.status === 'not-measured') ? 'not-measured'
      : recs.some((r) => r.status === 'stale') ? 'stale' : 'fresh';
    card.dataset.state = state;
    const age = q('.age', card);
    // A card that names a limit (data-max-age, seconds) marks a fresh sample older than it.
    const oldest = Math.min(...recs.map((r) => parseTime(r.sampledAt)).filter(Number.isFinite));
    age.classList.toggle('old', state === 'fresh' && (now - oldest) / 1000 > Number(card.dataset.maxAge));
    // A refused read says when it is tried next (retryAt), beside what it last read.
    const retry = Math.min(...recs.map((r) => parseTime(r.retryAt)).filter(Number.isFinite));
    const next = Number.isFinite(retry) ? ` · next try ${hm(new Date(retry))}` : '';
    if (state === 'not-measured') {
      const missing = ids.filter((id, i) => recs[i].status === 'not-measured');
      // A card that drew its data with one input unread (the Alerts list) is not wholly unmeasured; its note names the part.
      age.textContent = card.dataset.partial ? 'part not measured' : `${missing.join(', ')} not measured${next}`;
    } else if (state === 'stale') {
      const since = Math.min(...recs.filter((r) => r.status === 'stale').map((r) => parseTime(r.staleSince)).filter(Number.isFinite));
      age.textContent = (Number.isFinite(since) ? `stale since ${when(since)}` : 'stale since unknown') + next;
    } else {
      age.textContent = Number.isFinite(oldest) ? `sampled ${ago((now - oldest) / 1000)} ago` : '';
    }
  }

  function note(card, text) {
    const p = q('.card-note', byId(card));
    p.hidden = !text;
    p.textContent = text || '';
  }


  // fact(dl, term, value, more) -- more puts the row in the detailed view only.
  function fact(dl, term, value, more) {
    const dt = h('dt', more ? 'more' : null, term), dd = h('dd', more ? 'more' : null);
    dd.append(...[].concat(value).filter((x) => x !== null && x !== undefined));
    dl.append(dt, dd);
  }

  // The panel is named after whoever runs the plugin: the name the collector read, shown as text.
  const ownerName = (n) => (n && typeof n.name === 'string' && n.name.trim() ? n.name : 'the owner');
  // The finished builds the collector listed, cleared or not; a list that was not read is null.
  const finishedBuilds = (units) => (units && Array.isArray(units.finishedBuilds) ? units.finishedBuilds.filter((f) => f && typeof f.unit === 'string' && f.unit && typeof f.sha === 'string' && f.sha) : null);
  // Issue 240: the owner answers on this machine's own page only (dashboard_serve.py takes an answer from a loopback
  // client alone); every other host's page, the phone's, shows the question read-only.
  // Issue 263: a page served over https is behind the host's login, and that host takes an answer from any logged-in client.
  const LOCAL = ['127.0.0.1', 'localhost', '[::1]'].includes(window.location.hostname) || window.location.protocol === 'https:';
  // A write the host refuses with 401 (the session ended) sends the page to the host's login.
  const loggedIn = (r) => { if (r && r.status === 401) window.location.assign('/login'); return r; };
  // One asking of a decision: decision.sh reopen keeps the id and moves askedAt, and that is a new question.
  const asking = (d) => `${d.id} ${d.askedAt}`;
  const answered = new Map(); // asking -> the host's word on its answer, until a snapshot drops that asking
  // Main reads no inbox message while its own picker is open; said in the past tense, it stays true until a reload.
  // The host keeps the same word for the snapshot (needsOwner.picker), which also covers a reload and a resent answer.
  const pickerOpen = new Set(); // ids of decisions whose answer was sent while main's picker was open
  function answerBox(d) {
    const box = h('div', 'answer');
    if (answered.has(asking(d))) { box.append(h('p', 'answered', answered.get(asking(d)))); return box; }
    const said = h('p', 'meta');
    const post = (answer) => {
      for (const c of box.querySelectorAll('button, input')) c.disabled = true;
      window.fetch('answer', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ project: asked, id: d.id, askedAt: d.askedAt, answer }) })
        .then(loggedIn).then((r) => (r.ok ? r.json().then((j) => {
          if (j.picker) pickerOpen.add(d.id);
          return `Answered: ${answer} (ruling ${j.ruling || 'not logged'})${j.unsent ? '; not sent yet, sent again on the next refresh' : ''}${j.picker ? "; main's picker for it was open: pick or press Esc in main's pane" : ''}`;
        })
          : `Not answered: ${r.status === 409 ? 'it was answered or asked again since this page read it' : `the host said ${r.status}`}`))
        .catch(() => 'Not answered: the host could not be reached')
        .then((t) => {
          if (t.startsWith('Answered')) { answered.set(asking(d), t); box.replaceChildren(h('p', 'answered', t)); return; }
          said.textContent = t;
          for (const c of box.querySelectorAll('button, input')) c.disabled = false;
        });
    };
    for (const o of Array.isArray(d.options) ? d.options : []) {
      const b = h('button', o === d.proposedDefault ? 'opt default-opt' : 'opt', o === d.proposedDefault ? `${o} (default)` : o);
      b.type = 'button';
      b.addEventListener('click', () => post(o));
      box.append(b);
    }
    const other = h('input', 'other');
    other.placeholder = 'Other';
    other.setAttribute('aria-label', 'Other answer');
    const go = h('button', 'opt', 'Send');
    go.type = 'button';
    go.addEventListener('click', () => { if (other.value.trim()) post(other.value.trim()); });
    box.append(other, go, said);
    return box;
  }

  // Issue 295: an answer the host could not send says why, how often it tried and since when, and whether the host gave
  // up; on this machine's page the owner retries it, says main got it another way, or drops it.
  function unsentRow(u) {
    const t = parseTime(u.firstAt), tries = Number.isInteger(u.tries) ? u.tries : 0;
    const why = u.state === 'gave-up' ? u.reason || 'reason not recorded' : u.lastError || (tries ? 'no error line' : 'not tried yet');
    const li = h('li', 'decision crit unsent', `The answer to ${u.id} is not sent to ${u.to === 'relay' ? 'the relay' : 'main'}: ${why}, ${tries} ${tries === 1 ? 'try' : 'tries'}${Number.isFinite(t) ? ` since ${when(t)}` : ''}. ${u.state === 'gave-up' ? 'The host gave up on it.' : 'The host tries again on each refresh.'}`);
    if (!LOCAL || typeof u.key !== 'string') return li;
    const said = h('span', 'meta');
    for (const [action, label, ask] of [['retry', 'Retry', null], ['delivered', 'Main got it', 'Did main get this answer another way? It is removed and not sent.'],
      ['drop', 'Drop', 'Drop this answer? Main is not told it.']]) {
      const b = h('button', 'opt', label);
      b.type = 'button';
      b.addEventListener('click', () => {
        if (ask && !window.confirm(ask)) return;
        b.disabled = true;
        window.fetch('unsent', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ key: u.key, action }) })
          .then(loggedIn).then((r) => (r.ok ? `${label}: done, the list follows on the next refresh` : `${label}: the host said ${r.status}`))
          .catch(() => `${label}: the host could not be reached`)
          .then((s) => { said.textContent = s; b.disabled = false; });
      });
      li.append(' ', b);
    }
    li.append(' ', said);
    return li;
  }

  // Issue 292: a labelled-issue list: the five lowest numbers, each title linked to its issue, then a show-all.
  // Anything but {count, top, all} is a read that failed.
  function issueList(id, x) {
    const box = byId(id);
    const ok = x && Number.isInteger(x.count) && Array.isArray(x.top) && Array.isArray(x.all);
    if (!ok) { put(box, [h('p', 'empty', 'not measured')]); return; }
    const row = (i) => {
      const li = h('li');
      const href = ghUrl(i.url);
      const a = href ? link(href, 't') : h('span', 't');
      a.append(h('span', 'inum', `#${i.number}`), ` ${i.title}`);
      li.append(a);
      return li;
    };
    const kids = [h('ul', 'issue-top', null)];
    kids[0].append(...x.top.map(row));
    if (!x.top.length) kids[0].append(h('li', 'empty', 'None open'));
    if (x.all.length > x.top.length) {
      const det = h('details');
      const ul = h('ul');
      ul.append(...x.all.map(row));
      det.append(h('summary', null, `Show all ${x.count}`), ul);
      kids.push(det);
    }
    put(box, kids);
  }

  function renderNeeds(n, now, githubP1, githubProposed) {
    n = n || {};
    const who = ownerName(n);
    for (const el of document.querySelectorAll('[data-owner]')) el.textContent = who;
    // The project's open GitHub issues labelled P1; anything but a whole count is unknown.
    const issues = githubP1 && Number.isInteger(githubP1.count) && githubP1.count >= 0 ? githubP1.count : null;
    const rows = Array.isArray(n.decisions) ? n.decisions.filter((d) => d && d.answeredAt == null) : null;
    // A Builder's question to main (waitsOn "main") is listed apart and never counted as the owner's.
    const open = rows && rows.filter((d) => d.waitsOn !== 'main');
    const onMain = rows ? rows.filter((d) => d.waitsOn === 'main') : [];
    for (const k of answered.keys()) if (!open || !open.some((d) => asking(d) === k)) answered.delete(k);
    const dl = byId('needs-facts');
    dl.replaceChildren();
    fact(dl, `Waiting on ${who}`, open === null ? nm() : [strong(open.length), ' open ', open.length ? null : badge('nothing waiting', 'ok')]);
    fact(dl, 'Open P1 on GitHub', issues === null ? nm() : strong(issues));
    issueList('p1-issues', githubP1);
    issueList('proposed-issues', githubProposed);
    q('[data-count="decisions"]').textContent = open ? String(open.length) : 'not measured';
    const asked = (d) => {
      const t = parseTime(d.askedAt);
      const wait = Number.isFinite(t) ? (now - t) / 1000 : null;
      return { wait, meta: `${d.id}, from ${d.source}, asked ${Number.isFinite(t) ? when(t) : 'time not recorded'}${wait === null ? '' : `, ${ago(wait)} ago`}` };
    };
    const mainItems = onMain.length ? [h('li', 'waiting-main-label', 'Waiting on main')].concat(onMain.map((d) => {
      const li = h('li', 'decision waiting-main');
      li.append(h('p', 'question', d.question), h('p', 'meta', asked(d).meta));
      return li;
    })) : [];
    // Issue 276: a refresh while the owner types an answer rebuilds the list around that one row, which stays the same
    // node, so its typing and focus stay and new decisions and notes still show. A row whose decision left the open
    // list goes with the rest.
    const typing = document.activeElement && document.activeElement.closest && document.activeElement.closest('#decisions .answer');
    const keep = typing && typing.closest('li[data-asking]');
    const items = (open === null ? [h('li', 'empty', 'Decisions ledger not measured')]
      : (open.length === 0 ? [h('li', 'empty', 'No open decisions')]
        : open.map((d) => {
          if (keep && keep.dataset.asking === asking(d)) return keep;
          const { wait, meta } = asked(d);
          const li = h('li', wait !== null && wait > DECISION_LATE_SEC ? 'decision crit' : 'decision');
          li.dataset.asking = asking(d);
          const dflt = h('p', 'default');
          dflt.append(h('span', 'default-label', 'If no answer: '), h('span', null, d.proposedDefault));
          li.append(h('p', 'question', d.question), dflt, h('p', 'meta', meta));
          if (LOCAL) li.append(answerBox(d));
          return li;
        })).concat(mainItems, (Array.isArray(n.unsent) ? n.unsent : []).map(unsentRow),
        [...new Set([...pickerOpen, ...(Array.isArray(n.picker) ? n.picker : [])])].map((id) =>
          h('li', 'decision crit', `The answer to ${id} is recorded and sent, but main's picker for it was open: pick or press Esc in main's pane.`))));
    const list = byId('decisions'), at = keep ? items.indexOf(keep) : -1;
    if (at < 0) put(list, items);
    else {
      // Taken out of the page even for a moment, the focused box would lose its focus.
      for (const c of [...list.childNodes]) if (c !== keep) c.remove();
      keep.before(...items.slice(0, at));
      keep.after(...items.slice(at + 1));
    }
    // An open decision is the owner's to act on here, and so is an open P1 issue.
    flag('needs', Boolean(open && open.length) || issues > 0);
  }

  // claude-opus-5-5 reads "Opus 5.5"; any other id is shown as it is.
  function modelName(m) {
    const c = /^claude-([a-z]+)-(\d+)-(\d+)/.exec(String(m));
    return c ? `${c[1][0].toUpperCase()}${c[1].slice(1)} ${c[2]}.${c[3]}` : String(m);
  }
  // A Builder main raised above the setup default (builder-launch.sh --effort), from its brief's override line.
  const raisedBy = (u) => (u.builder && u.builder.raised && typeof u.builder.raised.reason === 'string' ? ', raised by main' : '');
  // What the seat is running, from its own session (the collector's `seat`), never the routing table. A planning
  // card's head draws the plan's seats instead; `u.seat` stays the Builder's own.
  function seatTags(u, label) {
    const row = h('div', 'mdls');
    const s = u.seat;
    if (s && typeof s === 'object' && typeof s.model === 'string') {
      if (label) row.append(h('span', 'mdl', label));
      const e = h('span', 'mdl e', `effort ${s.effort || 'not recorded'}${raisedBy(u)}`);
      if (raisedBy(u)) e.title = `effort raised by main: ${u.builder.raised.reason}`;
      row.append(h('span', 'mdl m', modelName(s.model)), e);
      if (s.advisor) row.append(h('span', 'mdl v', `advisor ${modelName(s.advisor)}`));
    } else row.append(h('span', 'mdl off', u.agents === '' ? 'no seat running' : 'model and effort not recorded'));
    return row;
  }
  const seatLabel = (u) => (u.builder && typeof u.builder === 'object' ? 'Builder' : SEATS.has(u.stage) ? SEATS.get(u.stage)
    : typeof u.seatRole === 'string' && u.seatRole ? `${u.seatRole[0].toUpperCase()}${u.seatRole.slice(1)}` : null);

  const SIGNAL_LABELS = { stuck: 'Stuck', quiet: 'Quiet', loop: 'Loop' };
  // The seat on one line: "Builder, Opus 5.5, medium effort".
  function seatText(u, label) {
    const s = u.seat;
    if (!s || typeof s !== 'object' || typeof s.model !== 'string') return [label, u.agents === '' ? 'no seat running' : 'model and effort not recorded'].filter(Boolean).join(', ');
    return [label, modelName(s.model), `${s.effort || 'effort not recorded'}${s.effort ? ' effort' : ''}${raisedBy(u)}`, s.advisor ? `advisor ${modelName(s.advisor)}` : null].filter(Boolean).join(', ');
  }

  const isBuilder = (u) => Boolean(u) && Boolean(u.builder) && typeof u.builder === 'object';
  const isStale = (u) => num(u.ageSec) !== null && u.ageSec >= STALE_SEC;
  // The unit card, "Run trace" (the owner's pick, #73): a head with the state in words, up to four big facts, then the
  // build from its start on one clock ending now. The stage is a band, the last sign a tick with the silence after it
  // hatched, and each helper run a bar with its numbers in a right-hand column. The diff and the seat show once.
  // A Builder's stages come from its event log (stageHistory), each with its time and cost (#94); a planning card's
  // one stage is its Planning, from its cost; any other unit shows only the stage it is in now.
  const TRACE_SEC = 2400;
  const took = (sec) => { const s = Math.max(0, Math.round(sec)); return `${Math.floor(s / 60)}:${pad(s % 60)}`; };
  // A tally's list-price dollars (#94). A request with no price leaves the sum a floor: it says so and names the models.
  const costOf = (t) => (!t ? 'not measured' : t.partial ? `${money(t.usd)}+ partial, ${t.unpriced && t.unpriced.length ? t.unpriced.join(', ') : 'a model'} not priced` : money(t.usd));
  // A build's total with its Claude and Codex parts, as the collector priced them: an unpriced part is "not priced",
  // a missing one "not measured".
  const part = (v) => (v === null ? 'not priced' : num(v) === null ? 'not measured' : money(v));
  const splitOf = (t) => (!t ? costOf(t) : `${costOf(t)} (Claude ${part((t.byAgent || {}).claude)}, Codex ${part((t.byAgent || {}).codex)})`);
  // Issue 270: each unit in flight or finished in the last 7 days, most costly first, its stages folded under it.
  function renderCostUnit(list) {
    note('cost-unit', !Array.isArray(list) ? 'Unit costs not measured' : list.length ? '' : 'No unit ran in the last 7 days');
    put(byId('cost-unit-list'), (Array.isArray(list) ? list : []).map((u) => {
      const t = u.total || {};
      const li = h('li');
      li.append(uline(`${u.unit}${u.inFlight ? ' (in flight)' : ''}`, `${splitOf(u.total)} · ${tokens((num(t.input) ?? 0) + (num(t.output) ?? 0))} tokens`));
      if (Array.isArray(u.stages) && u.stages.length) {
        const fold = h('details');
        const ul = h('ul', 'list');
        fold.append(h('summary', null, 'Stages'), ul);
        put(ul, u.stages.map((s) => h('li', null, `${s.stage}: ${costOf(s)}`)));
        li.append(fold);
      }
      return li;
    }));
  }
  // Issues 271 and 272: each merged unit's review rounds, from the unit ledger, and the issues tagged as escapes.
  function renderReview(rows, escapes) {
    note('review', !Array.isArray(rows) ? 'Unit ledger not measured' : rows.length ? '' : 'No unit merged in the last 7 days');
    const n = (v, one) => (num(v) === null ? `${one}s not measured` : `${v} ${one}${v === 1 ? '' : 's'}`);
    put(byId('review-list'), (Array.isArray(rows) ? rows : []).slice().sort((a, b) => (num(b.rounds) ?? -1) - (num(a.rounds) ?? -1)).map((r) => {
      const li = h('li');
      const gaps = Array.isArray(r.gaps) && r.gaps.length ? ` · not measured: ${r.gaps.join(', ')}` : '';
      const kinds = r.passKinds && typeof r.passKinds === 'object' ? ` · ${Object.entries(r.passKinds).map(([k, v]) => `${k} ${v.go} GO/${v.noGo} NO-GO`).join(', ')}` : '';
      const inReview = num(r.reviewSeconds) === null ? '' : ` · ${Math.round(r.reviewSeconds / 60)} min in review`;
      li.append(uline(r.unit, `${n(r.rounds, 'round')}, ${num(r.noGoRounds) ?? '?'} NO-GO${kinds}${inReview}${gaps}`));
      return li;
    }));
    put(byId('escapes-list'), !Array.isArray(escapes) ? []
      : escapes.length ? escapes.map((e) => h('li', null, `${e.unit} escaped #${e.issue} · class ${e.class || '-'} · caught ${e.caught || '-'}`))
        : [h('li', 'empty', 'No escaped issue tagged')]);
  }
  // Issue 269: the test runs going now on this machine and the finished ones of the last day. Only what the collector
  // measured shows: a usual time needs 3 runs of the command, so a run without one says so.
  function testJob(r) {
    const el = num(r.elapsedSec), us = num(r.usualSec);
    const job = h('div', r.stalled ? 'job stalled' : 'job'), top = h('div', 'row'), who = h('div');
    who.append(h('span', 'who', r.who || 'unknown'), ' ', h('code', 'what', r.command));
    top.append(who);
    if (r.builder) top.append(badge('Builder'));
    if (r.stalled) top.append(badge('Stalled', 'crit'));
    const meta = h('div', 'meta');
    meta.append(h('span', null, el === null ? 'elapsed not measured' : `${took(el)} elapsed`),
      h('span', null, us === null ? 'usual time not measured (needs 3 runs)' : `usually ${took(us)}`));
    job.append(top, meta);
    return job;
  }
  function renderTests(t) {
    const run = t && Array.isArray(t.running) ? t.running : null;
    const fin = t && Array.isArray(t.finished) ? t.finished : null;
    note('tests', t ? '' : 'Tests not measured');
    sub('tests-sub', run === null ? '' : `${run.length} running`);
    const body = [];
    if (t) {
      // Issue 292: test seconds today, and the part of the Builders' clock they took (null without a Builder session today).
      if (num(t.testSecToday) !== null) body.push(h('p', 'meta', `Test time today ${span(t.testSecToday)}, ${num(t.builderShare) === null ? 'Builder share not measured' : `${Math.round(100 * t.builderShare)}% of the Builders' clock`}`));
      body.push(h('h3', null, 'Running'));
      if (run === null) body.push(h('p', 'nm', 'Running tests not measured'));
      else if (!run.length) body.push(h('p', 'empty', 'No test is running.'));
      else body.push(...run.map(testJob));
      body.push(h('h3', null, 'Finished, last 24 hours'));
      if (fin === null) body.push(h('p', 'nm', 'Finished runs not measured'));
      else if (!fin.length) body.push(h('p', 'empty', 'No test finished in the last 24 hours.'));
      else {
        const table = h('table', 'tests-table'), head = h('tr');
        head.append(...['When', 'Who', 'What', 'Result', 'Took', 'Usual'].map((c) => h('th', null, c)));
        table.append(head);
        for (const f of fin.slice(0, 30)) {
          const result = f.result === 'failed' ? badge(num(f.failed) ? `${f.failed} failed` : 'failed', 'crit')
            : f.result === 'unknown' ? h('span', null, 'result unknown')
              : h('span', null, num(f.passed) !== null ? `${f.passed} passed` : 'passed');
          const what = h('td', 'what', String(f.what).slice(0, 70)), row = h('tr'), res = h('td');
          what.title = f.what;
          res.append(result);
          row.append(h('td', null, hm(new Date(parseTime(f.when)))), h('td', null, f.who), what, res,
            h('td', 'num', num(f.took) === null ? '' : took(f.took)), h('td', 'num', num(f.usual) === null ? '' : took(f.usual)));
          table.append(row);
        }
        body.push(table);
      }
    }
    put(byId('tests-body'), body);
  }
  // A stage segment narrower than this share of the clock cannot hold its time and cost under it.
  const STAGE_MIN_PCT = 12;
  function unitCard(u, now, asks = []) {
    const signals = isBuilder(u) && Array.isArray(u.builder.signals) ? u.builder.signals.filter(Boolean) : [];
    const quiet = signals.some((s) => s.kind === 'quiet');
    const li = h('li', `unit${quiet ? ' quiet' : ''}`);
    li.dataset.unit = u.unit;
    const head = h('div', 'unit-head');
    // A planning card names every plan seat (`u.seat` is only the newest); done once its collect set completedAt.
    const planSeats = !isBuilder(u) && u.plan && Array.isArray(u.plan.seats) ? u.plan.seats.filter(Boolean) : [];
    const seatSpan = h('span', 'seat', planSeats.length ? planSeats.map((s) => [s.role, s.model ? modelName(s.model) : 'model not recorded',
      s.effort ? `${s.effort} effort` : 'effort not recorded', s.completedAt ? 'done' : 'running'].join(', ')).join(' · ') : seatText(u, seatLabel(u)));
    if (raisedBy(u)) seatSpan.title = `effort raised by main: ${u.builder.raised.reason}`;
    head.append(h('p', 'unit-name', u.unit),
      h('span', 'state', quiet && num(u.ageSec) !== null ? `Quiet for ${ago(u.ageSec)}` : u.worktree === false ? 'Parked' : STAGE_LABEL[u.stage] || SEATS.get(u.stage) || 'Stage not known yet'),
      seatSpan);
    li.append(head);
    // A unit's planning worktree shows its time from the first plan seat's launch, its cost and its cost by stage.
    const cost = isBuilder(u) ? u.builder.cost : u.plan ? u.plan.cost : undefined;
    if (isBuilder(u) || u.plan) {
      const t0b = parseTime(isBuilder(u) ? u.builder.startedAt : u.plan.from);
      const top = h('p', 'ucost');
      top.append('Total time ', strong(Number.isFinite(t0b) ? span((now - t0b) / 1000) : 'not measured'),
        ' · Cost so far ', strong(cost ? splitOf(cost.total) : cost === null ? 'not measured' : NOT_REC), h('small', null, " · main's own tokens not counted"));
      li.append(top);
      if (!isBuilder(u)) li.append(costTable(cost, cost === null ? 'not measured' : NOT_REC));
    }
    if (isBuilder(u)) {
      // Live context against the clear line past which the Builder hands off to a fresh session (a setup answer).
      const ctx = num(u.builder.context), line = num(Number(u.builder.clearLine)), k = (n) => `${Math.round(n / 1000)}K`;
      li.append(h('p', `uctx${ctx !== null && line !== null && ctx > line ? ' hot' : ''}`, ctx === null ? 'Context not measured'
        : u.builder.clearLine === 'off' ? `Context ${k(ctx)}, clear line off` : line === null ? `Context ${k(ctx)}`
          : ctx > line ? `Context ${k(ctx)}, past the ${k(line)} clear line` : `Context ${k(ctx)} of the ${k(line)} clear line`));
    }
    // A Builder is drawn from its own event log: one badge per signal the state word does not already say.
    const badges = h('p', 'badges');
    if (isBuilder(u) && !Array.isArray(u.builder.signals)) badges.append(badge('Signals not measured', 'muted'));
    for (const s of signals) if (s.kind !== 'quiet') badges.append(badge(SIGNAL_LABELS[s.kind] || 'Signal', 'warn'));
    if (isStale(u)) badges.append(badge('stale', 'crit'));
    if (u.worktree === false) badges.append(badge('No worktree', 'muted'));
    li.append(badges);
    // What the current round launched as: the Builder's own record, then each reviewer pass (issue 292). A record with
    // no flag says so; none at all draws no line.
    if (Array.isArray(u.seats) && u.seats.length) {
      const p = h('p', 'launched', 'launched as ');
      u.seats.filter(Boolean).forEach((s, i) => {
        const e = h('span', null, `${s.model ? modelName(s.model) : 'model not recorded'}, ${s.effort ? `${s.effort} effort` : 'effort not recorded'}`);
        e.title = String(s.role);
        p.append(...(i ? [' · ', e] : [e]));
      });
      li.append(p);
    }
    // Why the unit stopped: its open questions to main (decision.sh --waits-on main; the source is "<unit> asks").
    for (const a of asks.filter((d) => d && d.source === `${u.unit} asks`)) li.append(h('p', 'stop-note', a.question));
    // A parked unit has no worktree to measure: its name, its seat and what it waits on are all there is.
    if (u.worktree === false) return li;

    const facts = h('dl', 'ufacts');
    const fact4 = (term, value, cls) => { const d = h('div', cls); d.append(h('dt', null, term)); const dd = h('dd'); dd.append(...[].concat(value)); d.append(dd); facts.append(d); };
    const since = parseTime(u.stageSince);
    const inStage = Number.isFinite(since) ? (now - since) / 1000 : null;
    if (STAGES.includes(u.stage)) {
      const r = num(u.round) !== null && (u.stage === 'review' || u.stage === 'fixing') ? ` ${u.round}` : '';
      fact4(`${STAGE_LABEL[u.stage]}${r}`, inStage === null ? 'not measured' : `${u.stageExact === false ? 'at least ' : ''}${ago(inStage)}`,
        `stage-time${inStage !== null && inStage > STUCK_SEC ? ' crit' : ''}`);
    }
    fact4('Last sign', num(u.ageSec) === null ? 'not measured' : `${ago(u.ageSec)} ago`, quiet ? 'hot' : null);
    // diffStat is git's "N files changed, A insertions(+), D deletions(-)" for the tracked change; "" is none.
    const diff = typeof u.diffStat === 'string' ? /(\d+) files? changed(?:, (\d+) insertions?\(\+\))?(?:, (\d+) deletions?\(-\))?/.exec(u.diffStat) : null;
    if (diff) fact4(`${diff[1]} file${diff[1] === '1' ? '' : 's'}`, [h('span', 'add', `+${diff[2] || 0}`), ' ', h('span', 'del', `−${diff[3] || 0}`)]);
    else fact4('Diff', u.diffStat === '' ? 'none' : 'not measured');
    fact4('Not committed', num(u.dirty) === null ? 'not measured' : String(u.dirty));
    li.append(facts);

    // The clock runs from the build's start (its first logged event, else the stage's) to now, back to the
    // earliest helper run if one began before; a unit with no start keeps the last 40 minutes (#95).
    const steps = isBuilder(u) && Array.isArray(u.builder.steps) ? u.builder.steps.filter(Boolean) : [];
    const begun = parseTime(isBuilder(u) ? u.builder.startedAt : u.plan ? u.plan.from : null);
    const start = Math.min(Number.isFinite(begun) ? begun : Number.isFinite(since) ? since : now - TRACE_SEC * 1000,
      ...steps.map((s) => parseTime(s.start)).filter(Number.isFinite));
    const width = Math.max(1000, now - start);
    const x = (t) => Math.max(0, Math.min(100, ((t - start) / width) * 100));
    const place = (el, from, to) => { el.style.left = `${x(from).toFixed(1)}%`; el.style.width = `${Math.max(0, x(to) - x(from)).toFixed(1)}%`; return el; };
    const lane = (cls, ...kids) => { const d = h('div', `lane${cls ? ` ${cls}` : ''}`); d.append(...kids); return d; };
    const nums = (...cells) => { const d = h('span', 'num'); d.append(...cells.map((c) => h('span', null, c))); return d; };
    // trace is the Stage block, always in view; act is the activity, folded under the card's Details.
    const trace = h('div', 'trace'), act = h('div', 'trace');
    // A finished pass names the verdict of its own round file; a running one has none yet.
    const verdicts = (isBuilder(u) && u.builder.verdicts) || {};
    // Each stage the Builder went through, with its time and its cost from the same collect (matched by start).
    const segs = (isBuilder(u) ? (Array.isArray(u.builder.stageHistory) ? u.builder.stageHistory : []) : cost && Array.isArray(cost.stages) ? cost.stages : [])
      .filter((g) => g && Number.isFinite(parseTime(g.from)))
      .map((g, i) => {
        const c = cost && Array.isArray(cost.stages) && cost.stages[i] && cost.stages[i].from === g.from ? cost.stages[i] : null;
        const a = parseTime(g.from), b = g.to ? parseTime(g.to) : now;
        const pass = g.stage === 'review' && num(g.round) !== null;
        const v = pass && g.to ? verdicts[g.round] : null;
        const name = !pass ? STAGE_LABEL[g.stage] || g.stage
          : `Codex pass ${g.round}${!g.to ? ' running' : v ? ` · ${String(v).replace(/^VERDICT:\s*/, '')}` : ''}`;
        return { g, a, b, name, judged: Boolean(v), time: `${took((b - a) / 1000)}${g.to ? '' : ' so far'}`, usd: c ? costOf(c) : 'cost not measured' };
      });
    const stageBand = segs.length ? segs.map((sg) => place(h('i', STAGE_TONE[sg.g.stage] || '', STAGE_LABEL[sg.g.stage] || sg.g.stage), sg.a, sg.b))
      : Number.isFinite(since) && STAGE_TONE[u.stage] ? [place(h('i', STAGE_TONE[u.stage], STAGE_LABEL[u.stage]), since, now)] : [];
    trace.append(h('span', 'lab', 'Stage'), lane('stages', ...stageBand, h('span', 'now')), nums('Tokens in', 'Out', 'Took'));
    trace.lastChild.classList.add('headnums');
    // A named verdict only shows in the list, so a finished pass with one takes the list too.
    if (segs.length && segs.every((sg) => !sg.judged && x(sg.b) - x(sg.a) >= STAGE_MIN_PCT)) {
      // Every segment holds its figures: a time row and a cost row, each figure under its own stage.
      for (const [label, k] of [['Time', 'time'], ['Cost', 'usd']]) trace.append(h('span', 'lab', label), lane('figs', ...segs.map((sg) => place(h('i', 'fig', sg[k]), sg.a, sg.b))), h('span'));
    } else if (segs.length) {
      // A segment too narrow for its figures: one line per stage across the card under the bar, in the order they
      // ran, then a Total row; in the bar's own column a stage name wrapped one letter per line. A segment
      // wide enough still shows its own figures, and hovering a segment marks its line.
      const list = h('ol', 'stagelist');
      segs.forEach((sg, i) => {
        const row = h('li');
        row.append(h('i', `sw ${STAGE_TONE[sg.g.stage] || ''}`), h('span', null, sg.name), h('span', null, sg.time), h('span', null, sg.usd));
        list.append(row);
        const band = stageBand[i];
        if (x(sg.b) - x(sg.a) >= STAGE_MIN_PCT) band.textContent = `${band.textContent} ${sg.time} · ${sg.usd}`;
        band.addEventListener('mouseenter', () => row.classList.add('hi'));
        band.addEventListener('mouseleave', () => row.classList.remove('hi'));
      });
      const total = h('li', 'total');
      total.append(h('i'), h('span', null, 'Total'), h('span', null, span((now - segs[0].a) / 1000)), h('span', null, cost ? costOf(cost.total) : 'cost not measured'));
      list.append(total);
      trace.append(list);
    }
    const seatList = seatsOf(cost);
    if (seatList) trace.append(seatList);
    const signAt = num(u.ageSec) === null ? null : now - u.ageSec * 1000;
    const sign = lane('pulse');
    if (signAt !== null) {
      const tick = h('b');
      tick.style.left = `${x(signAt).toFixed(1)}%`;
      sign.append(place(h('i', 'gap'), signAt, now), tick);
    }
    act.append(h('span', 'lab', 'Last sign'), sign, h('span'));
    // One row per helper run on the clock: a subagent's tokens, or a Codex pass's exit code.
    for (const s of steps) {
      const t0 = parseTime(s.start), t1 = parseTime(s.kind === 'codex' ? s.end : s.stop);
      if (!Number.isFinite(t0)) continue;
      const live = !Number.isFinite(t1);
      const lab = h('span', 'lab', s.kind === 'codex' ? 'Codex ' : `${s.type || 'Agent'} `);
      lab.append(h('small', null, s.kind === 'codex' ? `${s.pass || 'pass'}${num(s.round) === null ? '' : `, round ${s.round}`}` : modelName(s.model || s.modelAsked || 'model not recorded')));
      const spent = live ? 'running' : took((t1 - t0) / 1000);
      const tk = s.tokens && num(s.tokens.input) !== null && num(s.tokens.output) !== null ? s.tokens : null;
      act.append(lab, lane(null, place(h('i', `h${s.kind === 'codex' ? ' codex' : ''}${live ? ' live' : ''}`), t0, live ? now : t1)),
        s.kind === 'codex' ? nums('', live ? '' : `rc ${s.rc ?? 'not recorded'}`, spent)
          : nums(tk ? tk.input.toLocaleString('en-US') : 'not recorded', tk ? tk.output.toLocaleString('en-US') : '', spent));
    }
    const axis = h('div', 'axis');
    for (let i = 0; i <= 4; i += 1) axis.append(h('span', null, i === 4 ? `now ${hm(new Date(now))}` : hm(new Date(start + (i * width) / 4))));
    act.append(h('span'), axis, h('span'));
    li.append(trace);
    const branch = h('p', 'branch', 'Branch ');
    branch.append(h('code', null, u.branch || 'not measured'), `, ${u.agents === null || u.agents === undefined ? 'agents not measured' : u.agents === '' ? 'no agents' : `agents ${u.agents}`}`);
    li.append(branch);
    const more = h('details', 'unit-more');
    more.append(h('summary', null, 'Details'), act);
    li.append(more);
    return li;
  }

  function renderUnits(units, now, decisions) {
    const lists = {};
    for (const s of [...STAGES, 'stale', 'permanent', 'unclassified', 'parked']) lists[s] = [];
    const known = Boolean(units) && Array.isArray(units.inFlight);
    note('units', known ? '' : 'Units in flight not measured');
    // A unit that has waited on main a day or more folds into one counted row.
    // No worktree (a Builder pane that is gone, its task still open) is parked, never in a stage.
    const group = (u) => (u.worktree === false ? 'parked' : u.stage === 'waiting-main' && isStale(u) ? 'stale'
      : STAGES.includes(u.stage) ? u.stage : SEATS.has(u.stage) ? 'permanent' : 'unclassified');
    const asks = Array.isArray(decisions) ? decisions.filter((d) => d && d.answeredAt == null && d.waitsOn === 'main') : [];
    for (const u of (units && units.inFlight) || []) lists[group(u)].push(unitCard(u, now, asks));
    // A column's count is everything in its step, the folded rows included.
    const size = (s) => lists[s].length + (s === 'waiting-main' ? lists.stale.length : 0);
    for (const [s, kids] of Object.entries(lists)) {
      q(`[data-count="${s}"]`).textContent = known ? String(size(s)) : 'not measured';
      const none = s === 'stale' || size(s) > 0;
      put(q(`[data-list="${s}"]`), kids.length || none ? kids : [h('li', 'empty', known ? 'None' : 'Not measured')]);
    }
    byId('stale-units').hidden = lists.stale.length === 0;
    byId('unclassified').hidden = lists.unclassified.length === 0;
    byId('permanent').hidden = lists.permanent.length === 0;
    byId('parked').hidden = lists.parked.length === 0;
    // Builds merged after the upstream's tip: what the next push sends.
    const merged = units && Array.isArray(units.mergedSincePush) ? units.mergedSincePush : [];
    put(byId('merged-since-list'), merged.map((m) => {
      const li = h('li', 'unit merged'), t = parseTime(m.at);
      li.dataset.unit = m.unit;
      li.append(h('p', 'unit-name', m.unit), h('p', 'meta', Number.isFinite(t) ? `merged ${ago((now - t) / 1000)} ago` : 'Merge time not measured'),
        h('p', 'meta mono', String(m.sha || '').slice(0, 8)));
      return li;
    }));
    byId('merged-since').hidden = merged.length === 0;
    byId('merged-since').querySelector('[data-count]').textContent = String(merged.length);
    // The compact view: one bar, a colour per step. A step with no unit is a narrow column.
    const cols = STAGES;
    const total = cols.reduce((a, s) => a + size(s), 0) || 1;
    put(byId('units-bar'), [mbar(cols.map((s) => [(100 * size(s)) / total, STAGE_TONE[s]]), 'h14')]);
    legend(byId('units-legend'), cols.map((s) => [STAGE_TONE[s], STAGE_LABEL[s], String(size(s))]));
    byId('stages').style.setProperty('--cols', cols.map((s) => (size(s) ? 'minmax(0, 2fr)' : 'minmax(70px, 0.6fr)')).join(' '));
    const working = workingBuilders(units).used, cap = Number.isInteger(units && units.builderCap) ? units.builderCap : null;
    byId('units-foot').textContent = `A unit is marked stale after a day with no sign.${working !== null && cap !== null ? ` Builders working: ${working} of the ${cap} the cap in /config allows.` : ''}`;
    flag('units', lists['waiting-main'].length + lists.stale.length > 0 || Boolean(q('#units .stage-time.crit')));
    // issue 211: the phone's step chips, counted as the columns are; app.css shows only the chosen stage under 760 px.
    put(byId('unit-steps'), [...STAGES, 'all'].map((s) => {
      const b = h('button', null, `${STEP_CHIP[s]} `);
      b.type = 'button';
      b.dataset.step = s;
      b.append(h('span', 'count', String(s === 'all' ? STAGES.reduce((a, x) => a + size(x), 0) : size(s))));
      return b;
    }));
    applyStep();
  }
  const STEP_CHIP = { ...STAGE_LABEL, review: 'Review', 'waiting-main': 'On main', all: 'All' };
  let unitStep = 'all';
  function applyStep() {
    document.body.dataset.step = unitStep;
    for (const b of document.querySelectorAll('#unit-steps button')) b.setAttribute('aria-pressed', String(b.dataset.step === unitStep));
    for (const el of document.querySelectorAll('#stages > .stage')) el.classList.toggle('step-on', el.dataset.stage === unitStep);
  }

  // A Builder counts as working while Orca shows a working agent in its worktree; an agent list not read is not measured.
  function workingBuilders(units) {
    const builders = units && Array.isArray(units.inFlight) ? units.inFlight.filter(isBuilder) : null;
    const used = !builders || builders.some((u) => typeof u.agents !== 'string') ? null : builders.filter((u) => /:working/.test(u.agents)).length;
    return { builders, used };
  }

  // Builds in progress: one block per Builder. Every value comes from the unit's
  // own brief, evidence file, round files and event log; one with no source reads "not recorded".
  const NOT_REC = 'not recorded';
  const BUILD_STEPS = ['Build', 'Review', 'Fix', 'Closing pass', 'Merge'];
  function buildStep(u) {
    const passes = Array.isArray(u.builder.steps) ? u.builder.steps.filter((s) => s && s.kind === 'codex') : null;
    const open = passes && passes.find((s) => !s.end);
    if (open) return open.pass === 'final' ? 3 : 1;
    if (u.stage === 'review') return 1;
    if (u.stage === 'fixing') return 2;
    if (u.stage === 'building') return 0;
    // Merge is main's step: only a closing pass that itself finished cleanly, with a GO from its own round, puts the
    // unit there, or the first pass doing the same, which merges with no closing pass.
    if (u.stage === 'waiting-main' && (cleanGo(u, 'final') || cleanGo(u, 'adversarial'))) return 4;
    return -1;
  }
  // The latest pass, when it is of this kind, finished cleanly and the GO on record is its own round's. The worktree
  // must still be the tree that pass read (reviewedTree, from reviewed-tree.sh): main merges the tip, not the pass.
  function cleanGo(u, kind) {
    const last = Array.isArray(u.builder.steps) ? u.builder.steps.filter((s) => s && s.kind === 'codex')[0] : null;
    return last && u.builder.reviewedTree === true && last.pass === kind && last.end && last.rc === 0 && num(last.round) !== null
      && last.round === u.builder.verdictRound && /^VERDICT:\s*GO\b/.test(String(u.builder.verdict)) ? last : null;
  }
  // A NO-GO's colour is its findings' (the owner, 2026-10-13): amber on P2 or P3 only, red with a P0 or P1 open or
  // with findings that were not read.
  const nogoTone = (x) => (x.findings && typeof x.findings === 'object' && !num(x.findings.P0) && !num(x.findings.P1) ? 'warn' : 'crit');
  // The colour of the newest finished pass, null for green: red when it exited with an error or left no verdict that
  // can be read, a NO-GO by its findings, and amber for a GO on a tree not known to be the one it read (a pass started since has given no verdict).
  // Only the newest round's verdict is on record, so no older pass can be coloured from it.
  function passTone(x, p) {
    if (p.rc !== 0) return 'crit';
    const v = num(p.round) !== null && p.round === x.verdictRound ? String(x.verdict) : '';
    if (/^VERDICT:\s*GO\b/.test(v)) return x.reviewedTree === true ? null : 'warn';
    return /^VERDICT:\s*NO-GO\b/.test(v) ? nogoTone(x) : 'crit';
  }
  function waitingText(u, now) {
    const w = u.builder.waiting;
    if (!Array.isArray(w)) return u.stage === 'waiting-main' ? 'main' : NOT_REC;
    const since = (x) => { const t = parseTime(x.since); return Number.isFinite(t) ? `, for ${ago((now - t) / 1000)}` : ''; };
    const parts = w.filter(Boolean).map((x) => (x.kind === 'codex' ? `Codex ${x.what || ''} pass${num(x.round) === null ? '' : `, round ${x.round}`}${since(x)}`
      : x.kind === 'subagent' ? `${x.what || 'a'} subagent${since(x)}` : `a ${x.what || 'tool'} call${since(x)}`));
    if (u.stage === 'waiting-main') parts.unshift('main');
    return parts.length ? parts.join(' · ') : 'nothing';
  }
  function reviewText(x) {
    if (!Array.isArray(x.steps)) return NOT_REC;
    const rounds = x.steps.filter((s) => s && s.kind === 'codex').map((s) => num(s.round)).filter((n) => n !== null);
    if (num(x.verdictRound) !== null) rounds.push(x.verdictRound);
    if (!rounds.length) return 'not started';
    const pass = Math.max(...rounds);
    const f = x.findings && typeof x.findings === 'object' ? ['P0', 'P1', 'P2', 'P3'].filter((k) => num(x.findings[k])).map((k) => `${k} ${x.findings[k]}`) : null;
    const found = f === null ? `findings ${NOT_REC}` : `${f.length ? f.join(' · ') : 'no findings'}${num(x.verdictRound) !== null && x.verdictRound !== pass ? ` in pass ${x.verdictRound}` : ''}`;
    return `pass ${pass} · ${found} · ${num(x.reviewSec) === null ? `minutes ${NOT_REC}` : `${Math.round(x.reviewSec / 60)} min in review`}`;
  }
  // The planning stage seat by seat: role (", running" until its collect), model and effort, calls, tokens, cost
  // and time ("so far" until its collect). What no seat claims is one row, so the rows sum to the stage.
  function seatsOf(cost) {
    if (!cost || !Array.isArray(cost.seats) || !cost.seats.length) return null;
    const list = h('ol', 'stagelist seats');
    for (const s of cost.seats) {
      const row = h('li');
      row.append(h('i', `sw ${STAGE_TONE.planning || ''}`), h('span', null, s.role ? `${s.role}${s.to ? '' : ', running'}` : 'Not tied to a seat'),h('span', null, [s.model, s.effort].filter(Boolean).join(' ')),
        h('span', null, `${s.calls} calls`), h('span', null, `${s.input.toLocaleString('en-US')} in / ${s.output.toLocaleString('en-US')} out`),
        h('span', null, costOf(s)), h('span', null, s.role ? `${took(s.sec)}${s.to ? '' : ' so far'}` : ''));
      list.append(row);
    }
    return list;
  }
  // The cost-by-stage table under a build's Details (#94): each stage, then the unit's total. `missing` says why
  // there is none: a running build's collect could not read it, a finished one's was never kept.
  function costTable(cost, missing) {
    if (!cost) return h('p', 'meta', `Cost by stage ${missing}`);
    const t = h('table', 'costs');
    const tr = (cells, tag) => { const r = h('tr'); r.append(...cells.map((c) => h(tag || 'td', null, String(c)))); return r; };
    const tin = (x) => `${x.input.toLocaleString('en-US')} (${x.input ? Math.round((100 * x.cached) / x.input) : 0}% cached)`;
    t.append(tr(['Stage', 'Took', 'Model calls', 'Tokens in', 'Out', 'Cost'], 'th'),
      ...(cost.stages || []).map((x) => tr([STAGE_LABEL[x.stage] || x.stage, `${took(x.sec)}${x.to ? '' : ' so far'}`, x.calls, tin(x), x.output.toLocaleString('en-US'), costOf(x)])),
      tr(['Unit total', took(cost.total.sec), cost.total.calls, tin(cost.total), cost.total.output.toLocaleString('en-US'), costOf(cost.total)]));
    t.lastChild.classList.add('total');
    const read = unitCost ? parseTime(unitCost.sampledAt) : NaN;
    const stale = unitCost && unitCost.status === 'stale' ? parseTime(unitCost.staleSince) : null;
    const said = [Number.isFinite(read) ? `read ${when(read)}` : null, stale === null ? null : Number.isFinite(stale) ? `stale since ${when(stale)}` : 'stale since unknown'].filter(Boolean);
    if (said.length) t.append(h('caption', null, said.join(' · ')));
    const d = h('div', 'costs-wrap');
    d.append(h('h3', null, 'Cost by stage'), t,
      h('p', 'meta', "List-price equivalents of the Builder, its helpers and sub-agents and its review passes; main's own tokens are not counted."));
    return d;
  }
  // One build's block, running or finished: the same parts in the same order, so the two cannot drift.
  // Folded, it shows its header row and `line` only. A running build is kept by its unit name, a finished one by its
  // merge commit, so a build that finishes folds by itself whatever was chosen while it ran; the owner's own fold
  // or unfold of either stands (buildFolds, kept with the panel layout).
  function block(unit, small, tags, stepRows, done, caption, more, fold, line, finished) {
    const el = h('div', 'build');
    el.dataset.unit = unit;
    el.dataset.fold = fold;
    const m = h('div', 'more');
    m.append(...more);
    el.append(uline(unit, small), h('p', 'line', line.join(' · ')), tags, steps(stepRows), mbar([[done, 'g']], 'h14'), caption, m);
    const kept = buildFolds();
    const b = h('button');
    b.type = 'button';
    b.dataset.fold = fold;
    setFold(el, b, Object.prototype.hasOwnProperty.call(kept, fold) ? kept[fold] : finished);
    el.firstChild.append(b);
    return el;
  }
  function setFold(el, b, shut) {
    el.classList.toggle('shut', shut);
    b.textContent = shut ? 'Expand' : 'Collapse';
    b.setAttribute('aria-expanded', String(!shut));
    b.setAttribute('aria-label', `${shut ? 'Expand' : 'Collapse'} ${el.dataset.unit}`);
  }
  function buildBlock(u, now, g) {
    const x = u.builder;
    let at = buildStep(u);
    const first = cleanGo(u, 'adversarial');
    const names = BUILD_STEPS.slice();
    let note = first ? `skipped, unchanged since pass ${first.round}` : undefined;
    // A closing pass that finished without a clean GO was still reached: it shows with its verdict, and work after it
    // is its own step, never the Fix step before it.
    const passes = Array.isArray(x.steps) ? x.steps.filter((s) => s && s.kind === 'codex') : [];
    const closed = passes.find((s) => s.pass === 'final' && s.end);
    const lastDone = passes.find((s) => s.end);
    // Green is only a step that is done and whose last word stands (the owner, 2026-10-13): a step that ended badly
    // is red, one that needs someone or is no longer current is amber. Red is never painted over by amber.
    const tone = {};
    const worse = (i, t) => { if (t && tone[i] !== 'crit') tone[i] = t; };
    if (lastDone && lastDone.pass !== 'final') worse(1, passTone(x, lastDone));
    if (closed && !cleanGo(u, 'final') && !passes.some((s) => s.pass === 'final' && !s.end)) {
      note = `pass ${closed.round}${closed.rc !== 0 ? ' exited with an error' : closed.round === x.verdictRound && typeof x.verdict === 'string' ? ` ended ${x.verdict.replace(/^VERDICT:\s*/, '')}` : ''}`;
      at = 3;
      if (passes[0] !== closed || u.stage !== 'waiting-main') { names.splice(4, 0, 'Fix'); at = 4; }
      // A closing pass with a later pass after it has no verdict on record any more: it is no longer the last word.
      worse(3, closed === lastDone ? passTone(x, closed) : closed.rc !== 0 ? 'crit' : 'warn');
    }
    const waits = u.stage === 'waiting-main';
    // A build that stopped for main before any clean GO stopped somewhere: before the closing pass after a
    // GO, at the fix after any other pass, and while building when no pass has ended.
    if (waits && at === -1) at = !lastDone ? 0 : passTone(x, lastDone) ? 2 : 3;
    if (waits) worse(at, 'warn');
    for (const s of Array.isArray(x.signals) ? x.signals : []) if (s && at >= 0) worse(at, s.kind === 'stuck' ? 'crit' : 'warn');
    const issues = Array.isArray(x.issues) ? x.issues : null, built = Array.isArray(x.built) ? x.built : null;
    // False is an evidence file that is there and could not be read: no count, and not a build yet to start.
    const noBuilt = x.built === false ? `built count ${NOT_REC}` : 'nothing built yet';
    const done = issues && built ? issues.filter((i) => built.includes(i)).length : null;
    if (at > 0 && done !== null && done < issues.length) worse(0, 'warn');
    const vTone = /^VERDICT:\s*NO-GO\b/.test(String(x.verdict)) ? nogoTone(x) : null;
    const more = [];
    const dl = h('dl', 'facts');
    const t0 = parseTime(x.startedAt);
    fact(dl, 'Started', Number.isFinite(t0) ? `${when(t0)} · ${span((now - t0) / 1000)} so far` : NOT_REC);
    fact(dl, 'Review', [...reviewText(x).split(/(P[01] \d+)/).map((t, i) => (i % 2 ? h('span', 'crit', t) : t)), ...(x.verdict ? [' · ', h('span', vTone, x.verdict)] : [])]);
    fact(dl, 'Last sign', num(u.ageSec) === null ? NOT_REC : [`written ${ago(u.ageSec)} ago `,
      typeof u.agents !== 'string' ? null : /:working/.test(u.agents) ? badge('working', 'ok') : badge('idle')]);
    fact(dl, 'Cost so far', x.cost ? splitOf(x.cost.total) : x.cost === null ? 'not measured' : NOT_REC);
    const wait = waitingText(u, now);
    // Only a wait on main is coloured: a pass, a subagent or a tool call is the build working.
    fact(dl, 'Waiting on', waits ? [h('span', 'warn', 'main'), wait.slice(4)] : wait);
    more.push(dl, costTable(x.cost, x.cost === null ? 'not measured' : NOT_REC), h('h3', null, 'Issue by issue'));
    if (issues === null) more.push(h('p', 'meta', `Issue list ${NOT_REC}`));
    else {
      const tags = h('div', 'iss');
      // An issue is its number, a link to it on GitHub with its title on hover when the open list has it; an item with
      // no issue number arrives as its own text and takes a line of its own.
      const repo = repoUrl(g);
      const titles = new Map((g && Array.isArray(g.issues) ? g.issues : []).map((x) => [x.number, x.title]));
      for (const i of issues) {
        const cls = [typeof i === 'number' ? null : 'item', built && built.includes(i) ? 'y' : null].filter(Boolean).join(' ') || null;
        const tag = typeof i === 'number' && repo ? link(`${repo}/issues/${i}`, cls, `#${i}`) : h('span', cls, typeof i === 'number' ? `#${i}` : i);
        if (typeof i === 'number' && typeof titles.get(i) === 'string') tag.title = titles.get(i);
        tags.append(tag);
      }
      const key = h('div', 'legend');
      // A null built list is a build with no evidence file yet, the normal first minutes; a file with nothing in it arrives as [].
      legend(key, [['g', 'recorded as built'], ['n', built === null ? noBuilt : 'not yet recorded']]);
      more.push(tags, key);
    }
    const line = [u.unit, seatText(u), STAGE_LABEL[u.stage] || `stage ${NOT_REC}`,
      issues === null ? `issues ${NOT_REC}` : x.built === false ? noBuilt : `${issues.filter((i) => built && built.includes(i)).length} of ${issues.length} built`,
      x.cost ? `cost ${costOf(x.cost.total)} so far` : x.cost === null ? 'cost not measured' : `cost ${NOT_REC}`,
      num(u.ageSec) === null ? `last sign ${NOT_REC}` : `last sign ${ago(u.ageSec)} ago`];
    // diffStat is the tracked change not yet committed, which for a Builder is the change since its last pass.
    return block(u.unit, typeof u.diffStat === 'string' && u.diffStat ? `not committed, new files not counted: ${u.diffStat}` : '', seatTags(u, 'Builder'),
      names.map((s, i) => [s, [i < at ? 'done' : i === at ? 'now' : '', tone[i]].filter(Boolean).join(' '), (s === 'Closing pass' ? note : undefined) ?? (waits && i === at ? 'waiting on main' : undefined)]),
      done !== null && issues.length ? (100 * done) / issues.length : 0,
      issues === null ? cap(`issue list ${NOT_REC}`, '') : issues.length === 0 ? cap('The brief lists no issue numbers', '') : done === null ? cap(`${issues.length} issues in the brief`, noBuilt)
        : cap([strong(`${done} of ${issues.length}`), ' issues recorded as built'], `${issues.length - done} left`), more, u.unit, line, false);
  }
  // A finished build, from the line its merge recorded, drawn as a running one is. The record holds merges only and
  // no seat, so every step is behind it and the tags name how it ended. It stays until the owner clears it.
  function finishedBlock(f, now) {
    const t = parseTime(f.at);
    const how = typeof f.how === 'string' && f.how ? f.how : 'ended';
    const ended = `${how} ${Number.isFinite(t) ? when(t) : 'at a time not recorded'}`;
    const tags = h('div', 'mdls');
    tags.append(h('span', 'mdl', 'Builder'), h('span', 'mdl', how));
    const dl = h('dl', 'facts');
    fact(dl, 'Ended', ended);
    fact(dl, 'Merge commit', typeof f.sha === 'string' && f.sha ? f.sha.slice(0, 8) : NOT_REC);
    // As the collector last read it before the merge: frozen, never priced again.
    fact(dl, 'Cost', f.cost && f.cost.total ? `${costOf(f.cost.total)} in ${span(f.cost.total.sec)}` : NOT_REC);
    const merged = how === 'merged';
    const el = block(f.unit, `${how} ${Number.isFinite(t) ? `${ago((now - t) / 1000)} ago` : 'at a time not recorded'}`, tags,
      // A build that ended any way but merged has a red Merge step.
      BUILD_STEPS.map((s) => (s !== 'Merge' ? [s, merged ? 'done' : ''] : !merged ? [s, 'crit', 'not merged'] : [s, 'done'])),
      merged ? 100 : 0, cap(ended, ''), [dl, costTable(f.cost, NOT_REC)],
      f.sha, [f.unit, `seat ${NOT_REC}`, how, `issues ${NOT_REC}`, f.cost && f.cost.total ? `cost ${costOf(f.cost.total)}` : `cost ${NOT_REC}`,
        `${how} ${Number.isFinite(t) ? `${ago((now - t) / 1000)} ago` : 'at a time not recorded'}`], true);
    el.classList.add('finished');
    const close = h('button', null, 'Close');
    close.type = 'button';
    // A build is cleared by its commit: a later build under the same unit name is another build.
    close.dataset.close = f.sha;
    close.setAttribute('aria-label', `Close ${f.unit}`);
    el.firstChild.append(close);
    return el;
  }
  // The commits of the builds the collector lists now; null until a list was read.
  let listedBuilds = null;
  // A clear only this browser holds, held back from a save made before the first list was read.
  let owed = false;
  // The builds a fold may keep choices for; null while either list is unread.
  let foldScope = null;
  function renderBuilds(units, now, g) {
    const { builders, used } = workingBuilders(units);
    note('builds', builders ? '' : 'Builders not measured');
    const closed = closedBuilds();
    const all = finishedBuilds(units), fin = all && all.filter((f) => !closed.includes(f.sha));
    listedBuilds = all && all.map((f) => f.sha);
    if (listedBuilds && owed) { owed = false; sendLayout(); }
    sub('builds-sub', [!builders ? null : used === null ? 'working Builders not measured' : `${used} of ${builders.length} working`,
      fin && fin.length ? `${fin.length} finished` : null].filter(Boolean).join(' · '));
    const blocks = !builders ? [] : builders.length ? builders.map((u) => buildBlock(u, now, g)) : [h('p', 'empty', 'No build is running.')];
    // The finished list has its own source: it is drawn whether or not the running builds could be read.
    blocks.push(...(fin ? fin.map((f) => finishedBlock(f, now)) : [h('p', 'nm', 'Finished builds not measured')]));
    put(byId('builds-list'), blocks);
    // Only with both lists read are the drawn builds every build: a fold saved then drops the builds gone since.
    foldScope = builders && fin ? blocks.map((b) => b.dataset && b.dataset.fold).filter(Boolean) : null;
    flag('builds', Boolean(builders) && builders.some((u) => u.stage === 'waiting-main' || (Array.isArray(u.builder.signals) && u.builder.signals.length)));
  }

  function renderChain(m, now) {
    m = m || {};
    const dl = byId('chain-facts');
    dl.replaceChildren();
    fact(dl, 'Unpushed', num(m.unpushed) === null ? nm() : [strong(m.unpushed), ' commits ', m.unpushed > 0 ? badge('not pushed', 'warn') : null]);
    // The newest finished build (dashboard.sh main_chain); "none yet" is a measured nothing, not a failed read.
    const lm = m.lastMerge, lt = lm ? parseTime(lm.at) : NaN;
    if ('lastMerge' in m) fact(dl, 'Last merge', lm ? `${lm.unit}${Number.isFinite(lt) ? `, ${ago((now - lt) / 1000)} ago` : ''}` : 'none yet');
    put(byId('commits'), Array.isArray(m.commits) ? m.commits.map((c) => {
      const li = h('li');
      li.append(h('span', 'mono sha', c.sha), h('span', null, c.subject));
      return li;
    }) : [h('li', null, 'Main commits not measured')]);
    flag('main-chain', num(m.unpushed) > 0);
  }

  // The GitHub panes (the owner's picks, #74), from the collector's gh and git reads (dashboard.sh github_panes,
  // next_push). A read never had is null: the pane says why, in the collector's words, and the rest of the page is drawn.
  function ghMissing(card, sources, ids, what) {
    const why = ids.map((id) => sources && sources[id] && sources[id].error).find(Boolean);
    note(card, `${what} not read${why ? `: ${why}` : ''}`);
  }
  // What stands between a pull request and its merge, worst first: [tone, words]. Ready only when nothing does.
  function prBlock(p) {
    const checks = Array.isArray(p.checks) ? p.checks : [];
    const failed = checks.filter((c) => c && c.state === 'fail'), running = checks.filter((c) => c && c.state === 'run');
    if (p.draft) return ['wait', 'Still a draft'];
    if (failed.length) return ['fail', `${failed[0].name || 'a check'} failed${failed.length > 1 ? `, and ${failed.length - 1} more` : ''}`];
    if (p.mergeable === 'CONFLICTING') return ['fail', 'Conflicts with its base branch'];
    if (p.review === 'CHANGES_REQUESTED') return ['fail', 'Changes requested'];
    if (running.length) return ['run', `${running.length} check${running.length > 1 ? 's' : ''} still running`];
    if (p.review === 'REVIEW_REQUIRED') return ['wait', 'Needs a review'];
    if (p.mergeable !== 'MERGEABLE') return ['wait', 'GitHub has not said whether it merges cleanly'];
    // Approved and conflict-free is not enough: the branch's rules (required checks, reviews) can still block it.
    if (p.mergeState !== 'CLEAN' && p.mergeState !== 'HAS_HOOKS') return ['wait', MERGE_STATE[p.mergeState] || 'GitHub has not said whether its rules let it merge'];
    return ['ready', p.review === 'APPROVED' ? 'Approved, merges cleanly' : 'Merges cleanly'];
  }
  const MERGE_STATE = { BLOCKED: "Blocked by the branch's rules", BEHIND: 'Behind its base branch', UNSTABLE: 'A check is not passing' };
  const PR_ORDER = { ready: 0, fail: 1, run: 2, wait: 3 };
  const CHECK_TONE = { pass: 'g', fail: 'r', run: 'b', skip: 'n' };
  const prs = (g) => (g && Array.isArray(g.prs) ? g.prs.filter((p) => p && Number.isInteger(p.number)) : null);
  // The Builder working a branch, by the branch name its worktree is on.
  const unitOn = (units, branch) => ((units && Array.isArray(units.inFlight) ? units.inFlight : []).find((u) => u && u.branch && u.branch === branch) || null);

  // Merge line: every open pull request, the ones ready to merge first, each naming what blocks it.
  function renderMergeLine(g, units, sources) {
    const list = prs(g);
    if (!list) { ghMissing('merge-line', sources, ['github-prs'], 'Pull requests'); sub('merge-line-sub', ''); put(byId('merge-line-list'), []); return; }
    note('merge-line', '');
    const rows = list.map((p) => ({ p, b: prBlock(p) })).sort((a, b) => PR_ORDER[a.b[0]] - PR_ORDER[b.b[0]] || a.p.number - b.p.number);
    const n = (t) => rows.filter((r) => r.b[0] === t).length;
    sub('merge-line-sub', `${n('ready')} ready · ${n('fail')} failing · ${n('run') + n('wait')} waiting`);
    const kids = [];
    let last = null;
    for (const { p, b } of rows) {
      const group = b[0] === 'ready' ? 'Ready to merge' : 'Blocked';
      if (group !== last) { kids.push(h('li', 'group', group)); last = group; }
      const href = ghUrl(p.url);
      const row = href ? link(href, `pr ${b[0]}`) : h('div', `pr ${b[0]}`);
      const who = h('p', 'by');
      const u = unitOn(units, p.branch);
      const closes = Array.isArray(p.closes) && p.closes.length ? `closes ${p.closes.map((i) => `#${i}`).join(', ')}` : null;
      who.append(...[u ? u.unit : null, closes].filter(Boolean).map((t) => `${t}, `), h('code', null, p.branch || 'branch not named'), ' ',
        h('span', 'add', `+${num(p.additions) ?? 0}`), ' ', h('span', 'del', `−${num(p.deletions) ?? 0}`));
      const text = h('div');
      text.append(h('p', 'title', p.title), who);
      const checks = (Array.isArray(p.checks) ? p.checks : []).filter(Boolean);
      const seg = h('div', 'checks');
      seg.setAttribute('aria-label', checks.length ? `${checks.filter((c) => c.state === 'pass').length} of ${checks.length} checks passed` : 'no checks');
      for (const c of checks) { const i = h('i', CHECK_TONE[c.state] || 'n'); i.title = `${c.name}: ${c.state}`; seg.append(i); }
      const cw = h('div');
      cw.append(seg, h('p', 'checks-note', checks.length ? `${checks.filter((c) => c.state === 'pass').length} of ${checks.length} passed` : 'No checks'));
      row.append(h('span', 'num', `#${p.number}`), text, cw, h('p', `block ${b[0]}`, b[1]));
      const li = h('li');
      li.append(row);
      kids.push(li);
    }
    put(byId('merge-line-list'), kids.length ? kids : [h('li', 'empty', 'No open pull requests')]);
    flag('merge-line', n('fail') > 0);
  }

  // Who holds what: open issues by milestone, most urgent first, each with the Builder whose brief lists it.
  // An urgent issue (P0 or P1) that nobody holds is called out at the top.
  function renderHeld(g, units, sources) {
    renderFlow(g && g.flow);
    const bp = g && g.byPriority && typeof g.byPriority === 'object' ? Object.entries(g.byPriority).filter(([, v]) => Number.isInteger(v)) : null;
    byId('held-priority').textContent = bp ? `By priority: ${bp.sort(([a], [b]) => (a < b ? -1 : 1)).map(([k, v]) => `${k} ${v}`).join(' · ')}` : 'Priority counts not measured';
    const issues = g && Array.isArray(g.issues) ? g.issues.filter((i) => i && Number.isInteger(i.number)) : null;
    const alarm = byId('held-alarm');
    if (!issues) { ghMissing('held', sources, ['github-issues'], 'Issues'); sub('held-sub', ''); alarm.hidden = true; put(byId('held-list'), []); return; }
    note('held', '');
    const held = new Map();
    for (const u of units && Array.isArray(units.inFlight) ? units.inFlight.filter(isBuilder) : []) {
      for (const i of Array.isArray(u.builder.issues) ? u.builder.issues : []) if (typeof i === 'number') held.set(i, [...(held.get(i) || []), u.unit]);
    }
    const open = prs(g) || [];
    const pri = (i) => (/^P[0-3]$/.test(i.priority) ? Number(i.priority[1]) : 9);
    const miles = new Map((g && Array.isArray(g.milestones) ? g.milestones : []).filter((m) => m && typeof m.title === 'string').map((m) => [m.title, m]));
    const groups = new Map();
    for (const i of issues) { const k = typeof i.milestone === 'string' ? i.milestone : ''; groups.set(k, [...(groups.get(k) || []), i]); }
    const due = (k) => { const t = parseTime(miles.get(k) && miles.get(k).due); return Number.isFinite(t) ? t : Infinity; };
    const order = [...groups.keys()].sort((a, b) => (a === '') - (b === '') || due(a) - due(b) || a.localeCompare(b));
    let free = 0;
    const kids = order.map((k) => {
      const list = groups.get(k).sort((a, b) => pri(a) - pri(b) || a.number - b.number);
      const n = list.filter((i) => held.has(i.number)).length;
      const m = miles.get(k);
      const sec = h('section', 'mile');
      const title = h('h3', null, k || 'No milestone');
      const t = parseTime(m && m.due);
      title.append(h('span', null, Number.isFinite(t) ? `due ${MONTHS[new Date(t).getMonth()]} ${new Date(t).getDate()}` : `${list.length} open`));
      const total = m && num(m.open) !== null && num(m.closed) !== null ? m.open + m.closed : null;
      sec.append(title, mbar(total ? [[(100 * m.closed) / total, 'g'], [(100 * n) / total, 'b']] : [[(100 * n) / list.length, 'b']], 'h8'),
        h('p', 'prog-note', `${total ? `${m.closed} of ${total} closed, ` : ''}${n} held, ${list.length - n} free`));
      const ul = h('ul', 'issues');
      for (const i of list) {
        const who = held.get(i.number);
        const urgent = pri(i) <= 1 && !who;
        if (urgent) free += 1;
        const li = h('li', 'issue');
        const href = ghUrl(i.url);
        const name = href ? link(href, 't') : h('span', 't');
        name.append(h('span', 'inum', `#${i.number}`), i.title);
        const pr = open.find((p) => Array.isArray(p.closes) && p.closes.includes(i.number));
        if (pr) name.append(h('small', null, `PR #${pr.number}: ${prBlock(pr)[1]}`));
        const holder = h('span', `holder${who ? '' : urgent ? ' none' : ' free'}`, who ? who.join(', ') : urgent ? 'Nobody' : 'Free');
        holder.title = holder.textContent; // the pill is cut short on one line; the whole name shows on hover
        li.append(h('span', `pri p${pri(i)}`, pri(i) < 9 ? `P${pri(i)}` : '–'), name, holder);
        ul.append(li);
      }
      sec.append(ul);
      return sec;
    });
    sub('held-sub', `${issues.length} open · ${order.filter(Boolean).length} milestone${order.filter(Boolean).length === 1 ? '' : 's'}`);
    alarm.hidden = free === 0;
    alarm.textContent = `${free} urgent issue${free === 1 ? '' : 's'} nobody holds`;
    put(byId('held-list'), kids.length ? kids : [h('p', 'empty', 'No open issues')]);
    flag('held', free > 0);
  }

  // Issue 273: issues opened and closed in 24 h, and per local day over 7 days as two lines.
  function renderFlow(f) {
    const o = f && num(f.opened24h), c = f && num(f.closed24h);
    byId('held-flow').textContent = o === null || c === null || !f ? 'Issues opened and closed not measured'
      : `${o} opened, ${c} closed in 24 h${f.incomplete ? '. A read hit its 1000-issue limit, so counts are at least these.' : ''}`;
    const days = f && Array.isArray(f.daily) ? f.daily : null;
    if (!days) { put(byId('held-spark'), []); return; }
    const W = 280, H = 64, P = 6;
    const max = Math.max(1, ...days.flatMap((d) => [num(d && d.opened) || 0, num(d && d.closed) || 0]));
    const x = (i) => (P + (i * (W - 2 * P)) / Math.max(1, days.length - 1)).toFixed(1);
    const y = (v) => (H - P - (v / max) * (H - 2 * P)).toFixed(1);
    const svg = svgEl('svg', { viewBox: `0 0 ${W} ${H}`, role: 'img' }, 'spark-svg');
    svg.append(svgEl('title', {}, null, 'Issues opened (solid) and closed (dashed) per day, last 7 days'),
      svgEl('line', { x1: P, x2: W - P, y1: H - P, y2: H - P }, 'spark-base'));
    for (const key of ['opened', 'closed']) {
      const pts = days.flatMap((d, i) => { const v = num(d && d[key]); return v === null ? [] : [`${x(i)},${y(v)}`]; });
      svg.append(svgEl('polyline', { points: pts.join(' ') }, `spark-${key}`));
    }
    put(byId('held-spark'), [svg]);
  }

  // Next push: the commits local main would push, under the issue each names, and what should stop the push first.
  function renderNextPush(np, g, sources, now) {
    const verdict = byId('next-push-verdict');
    if (!np || typeof np !== 'object' || !Array.isArray(np.commits)) {
      ghMissing('next-push', sources, ['git-push'], 'The next push');
      sub('next-push-sub', ''); verdict.replaceChildren(); put(byId('next-push-list'), []); return;
    }
    note('next-push', '');
    const ahead = num(np.ahead), behind = num(np.behind);
    sub('next-push-sub', `against ${np.upstream}: ${ahead ?? 'not measured'} ahead, ${behind ?? 'not measured'} behind`);
    const repo = repoUrl(g);
    const titles = new Map((g && Array.isArray(g.issues) ? g.issues : []).map((i) => [i.number, i.title]));
    const failing = new Map((prs(g) || []).filter((p) => prBlock(p)[0] === 'fail').flatMap((p) => (Array.isArray(p.closes) ? p.closes : []).map((i) => [i, p])));
    // A commit that names several issues is listed under the first.
    const groups = new Map();
    for (const c of np.commits.filter(Boolean)) { const k = Array.isArray(c.refs) && c.refs.length ? c.refs[0] : null; groups.set(k, [...(groups.get(k) || []), c]); }
    const bare = (groups.get(null) || []).length;
    const stops = [bare ? `${bare} commit${bare > 1 ? 's name' : ' names'} no issue` : null, behind > 0 ? `main is ${behind} behind ${np.upstream}: pull first` : null,
      ...[...groups.keys()].filter((k) => failing.has(k)).map((k) => `#${k}'s pull request #${failing.get(k).number} is blocked: ${prBlock(failing.get(k))[1]}`)].filter(Boolean);
    const run = g && Array.isArray(g.runs) && g.runs[0] && typeof g.runs[0] === 'object' ? g.runs[0] : null;
    const ran = run ? parseTime(run.createdAt) : NaN;
    const big = h('span', 'big', String(ahead ?? '?'));
    big.append(h('small', null, ahead === 1 ? 'commit' : 'commits'));
    const words = h('div');
    words.append(h('p', stops.length ? 'warn' : null, ahead === 0 ? `Nothing to push${stops.length ? `; ${stops.join('; ')}` : ''}.` : stops.length ? `Check before pushing: ${stops.join('; ')}.` : 'Nothing flagged.'),
      h('p', 'meta', `${[...groups.keys()].filter((k) => k !== null).length ? `Names ${[...groups.keys()].filter((k) => k !== null).map((k) => `#${k}`).join(', ')}. ` : ''}`
        + (run ? `Last CI on ${np.upstream}: ${run.conclusion || run.status || 'state not recorded'}${Number.isFinite(ran) ? `, ${ago((now - ran) / 1000)} ago` : ''}.` : 'Last CI run not read.')));
    verdict.replaceChildren(big, words);
    const kids = [...groups.entries()].map(([k, list]) => {
      const sec = h('section', 'push-issue');
      const head = h('div', 'push-head');
      const name = h('h3');
      if (k === null) name.append('No issue named');
      else { name.append(repo ? link(`${repo}/issues/${k}`, 'inum', `#${k}`) : h('span', 'inum', `#${k}`)); if (titles.has(k)) name.append(` ${titles.get(k)}`); }
      head.append(name);
      if (k === null) head.append(badge('needs an issue or a reason', 'warn'));
      else if (failing.has(k)) head.append(badge(`PR #${failing.get(k).number} blocked`, 'crit'));
      const ol = h('ol');
      for (const c of list) {
        const li = h('li', 'commit');
        li.append(h('span', 'sha', c.sha), h('span', 'msg', c.subject), h('span', 'add', `+${num(c.added) ?? 0}`),
          h('span', 'del', `−${num(c.deleted) ?? 0}`), h('span', 'when', num(c.at) === null ? '' : ago((now - c.at * 1000) / 1000)));
        ol.append(li);
      }
      sec.append(head, ol);
      return sec;
    });
    if (ahead > np.commits.length) kids.push(h('p', 'meta', `The newest ${np.commits.length} of ${ahead} commits are listed.`));
    put(byId('next-push-list'), kids);
    flag('next-push', stops.length > 0);
  }

  function renderCos(s) {
    const dl = byId('cos-facts');
    dl.replaceChildren();
    if (!s || num(s.unread) === null) { fact(dl, 'Inbox', nm()); return; }
    // A read that hit its 1000-message limit saw only part of the inbox.
    const least = s.incomplete ? 'at least ' : '';
    const old = num(s.oldestUnreadAgeSec);
    // The count is Orca's read flag, which only `orchestration check` sets: a message the Chief of Staff saw in its pane still counts.
    fact(dl, 'Not marked read', [strong(`${least}${s.unread} not marked read`), ' ', !s.unread ? (s.incomplete ? null : badge('clear', 'ok')) : old === null ? null : badge(`oldest ${ago(old)}`, old > 600 ? 'warn' : 'ok')]);
    // A capped read with no unread message in it cannot say none are unread.
    fact(dl, 'Oldest of them', old !== null ? `${least}${ago(old)} old` : s.incomplete ? nm() : 'none', true);
    flag('chief-of-staff', (old !== null && old > 600) || Boolean(s.incomplete));
  }

  // Main's and the relay's own cards (issue 224). `absent`: no relay is configured, so its card is not shown.
  function renderSeat(id, s, absent, account) {
    const card = byId(id), dl = byId(`${id}-facts`);
    if (absent) card.dataset.absent = ''; else delete card.dataset.absent;
    dl.replaceChildren();
    for (const old of card.querySelectorAll('.hourly')) old.remove();
    if (!s) { fact(dl, 'Context', nm()); return; }
    const ctx = num(s.context), line = num(s.line), gap = num(s.restartGapSec);
    const spend = (t) => (t && num(t.tokens) !== null && num(t.usd) !== null ? `${tokens(t.tokens)} tokens · ${money(t.usd)}${t.partial ? ' or more' : ''}` : nm());
    fact(dl, 'Context', ctx === null ? nm() : line === null ? tokens(ctx) : `${tokens(ctx)} of ${tokens(line)}`);
    fact(dl, 'Today', spend(s.today));
    fact(dl, '7-day daily average', spend(s.avg7));
    if (typeof s.live === 'boolean') fact(dl, 'Working now', s.live ? 'yes' : 'no');
    fact(dl, 'Restarts today', `${num(s.restarts) ?? 0}${gap === null ? '' : `, every ${ago(gap)} on average`}`);
    fact(dl, 'Restarted at', (Array.isArray(s.restartTimes) ? s.restartTimes : []).map((t) => clock(parseTime(t))).join(', ') || 'none', true);
    // A restart rebuilds the context in one first call: null with no session begun today, or an unpriced first call.
    if ('rebuildUsd' in s) fact(dl, 'Rebuild after a restart', num(s.rebuildUsd) === null ? nm() : money(s.rebuildUsd));
    // Issue 331: the wakes sent in the last hour, and the ones that failed, by result.
    if (s.wakes && num(s.wakes.hour) !== null) {
      const failed = Object.entries(s.wakes.failed || {}).map(([k, n]) => `${k} ${n}`).join(', ');
      fact(dl, 'Wakes, 1 h', `${s.wakes.hour}${failed ? ` · failed: ${failed}` : ''}`);
    }
    if (s.sideRuns !== undefined) fact(dl, 'Side runs today', s.sideRuns && num(s.sideRuns.count) !== null
      ? `${s.sideRuns.count} run${s.sideRuns.count === 1 ? '' : 's'} · ${num(s.sideRuns.usd) === null ? 'dollars not measured' : money(s.sideRuns.usd)}` : nm());
    const w = s.week;
    if (w && num(w.sessions) !== null) fact(dl, 'Week', `${w.sessions} session${w.sessions === 1 ? '' : 's'}${num(w.unmeasuredSessions) ? ` (${w.unmeasuredSessions} not measured)` : ''}, ${num(w.input) === null ? 'tokens not measured' : `${tokens(w.input)} in, ${tokens(w.output)} out`}`);
    // Which account the spend is billed to: the limit card's label (no e-mail), when the collector read one.
    if (typeof account === 'string' && account) fact(dl, 'Account', account);
    if (Array.isArray(s.hourly) && s.hourly.length) {
      const top = Math.max(1, ...s.hourly.map((v) => num(v) || 0)), spark = h('div', 'hourly');
      spark.title = 'tokens an hour, last 12 hours';
      for (const v of s.hourly) {
        const i = h('i');
        if (num(v) === null) { i.className = 'nm'; i.title = 'not measured'; } else i.style.height = `${(100 * v) / top}%`;
        spark.append(i);
      }
      dl.after(spark);
    }
    flag(id, ctx !== null && line !== null && ctx > line);
  }


  function renderHost(x) {
    x = x || {};
    const cpus = num(x.cpus);
    const loads = Array.isArray(x.load) ? x.load.map(num) : [];
    const load = loads.length ? loads[0] : null;
    const per = load !== null && cpus ? load / cpus : null;
    const tone = (v, warn, crit) => (v === null ? 'n' : v >= crit ? 'r' : v >= warn ? 'a' : 'g');
    const sw = x.swap;
    const used = sw ? num(sw.usedMb) : null, total = sw ? num(sw.totalMb) : null;
    const frac = used !== null && total ? used / total : null;
    const g = [uline('Load', loads.length ? loads.map((v) => (v === null ? '?' : v)).join(' · ') : ''),
      mbar([[per === null ? 0 : 50 * per, tone(per, 1, 2)]]),
      cap(load === null ? nm('Load') : [strong(load), ` of ${cpus ?? '?'} cores`], '1, 5 and 15 min'),
      uline('Swap', used === null ? '' : `${used.toLocaleString('en-US')} of ${(total ?? 0).toLocaleString('en-US')} MB`),
      mbar([[frac === null ? 0 : 100 * frac, frac === null ? 'n' : frac >= 0.75 ? 'r' : frac >= 0.25 ? 'a' : 'b']]),
      cap(used === null ? nm('Swap') : '', 'shown, not gated')];
    const procs = h('dl', 'facts');
    const cp = num(x.claudeProcs), xp = num(x.codexProcs);
    fact(procs, 'Processes', `${cp === null ? 'Claude not measured' : `${cp} Claude`} · ${xp === null ? 'Codex not measured' : `${xp} Codex`}`);
    g.push(procs);
    put(byId('host-gauges'), g);
    const dl = byId('host-facts');
    dl.replaceChildren();
    fact(dl, 'Load, 1 min', load === null ? nm() : `${load.toFixed(2)} on ${cpus ?? '?'} cores`);
    fact(dl, 'Swap used', used === null ? nm() : `${used} of ${total} MB`);
    fact(dl, 'Claude processes', cp === null ? nm() : String(cp));
    fact(dl, 'Codex processes', xp === null ? nm() : String(xp));
    const card = byId('host');
    if ((per !== null && per >= 2) || (frac !== null && frac >= 0.75)) card.dataset.alert = 'crit';
    else delete card.dataset.alert;
    flag('host', (per !== null && per >= 1) || (frac !== null && frac >= 0.25));
    return { load, cpus, per };
  }

  // Main's and the relay's own sessions write no seat-event row, so their week comes from the seats group; a seat with no
  // session in 7 days adds no row.
  const seatRoles = (seats) => [['relay', 'Chief of Staff session'], ['main', 'Main session']].flatMap(([k, role]) => {
    const w = seats && seats[k] && seats[k].week;
    return w && num(w.sessions) > 0 ? [{ role, seats: w.sessions, unmeasuredSeats: w.unmeasuredSessions, input: w.input, cachedInput: w.cachedInput, output: w.output }] : [];
  });
  function renderCost(roles, seats) {
    // No seat-event ledger yet (no worker has finished) leaves the workers unmeasured, never the seats' own measured weeks.
    const ledger = Array.isArray(roles);
    roles = (ledger ? roles : []).concat(seatRoles(seats));
    if (!ledger && !roles.length) {
      note('cost-role', 'Seat events not measured');
      put(byId('role-top'), []);
      put(byId('role-bars'), []);
      put(byId('cost-role-rows'), []);
      byId('cache-tile').textContent = '';
    } else {
      note('cost-role', !ledger ? 'Seat events not measured' : roles.length ? '' : 'No seat finished in the last 7 days');
      const hit = (r) => (num(r.input) > 0 && num(r.cachedInput) !== null ? (r.cachedInput / r.input) * 100 : null);
      const top6 = [...roles].sort((a, b) => (num(b.input) ?? -1) - (num(a.input) ?? -1)).slice(0, 6);
      const max6 = Math.max(1, ...top6.map((r) => num(r.input) || 0));
      const key = h('div', 'legend');
      legend(key, [['g', 'read from cache'], ['a', 'not cached']], `top ${top6.length} of ${roles.length} roles`);
      put(byId('role-top'), top6.flatMap((r) => {
        const i = num(r.input), c = Math.min(num(r.cachedInput) || 0, i || 0);
        const gap = num(r.unmeasuredSeats) ? `${r.unmeasuredSeats} of ${r.seats} seats unmeasured` : `${r.seats} seat${r.seats === 1 ? '' : 's'}`;
        return [uline(r.role, i === null ? `input not measured · ${gap}` : `${tokens(i)} in · ${hit(r) === null ? 'hit rate not measured' : `${Math.round(hit(r))}% cached`} · ${gap}`),
          mbar([[(100 * c) / max6, 'g'], [(100 * ((i || 0) - c)) / max6, 'a']], 'h8')];
      }).concat(roles.length ? [key] : []));
      const tot = (r) => (num(r.input) ?? 0) + (num(r.output) ?? 0);
      const max = Math.max(1, ...roles.map(tot));
      put(byId('role-bars'), roles.map((r) => {
        const gap = num(r.unmeasuredSeats) ? `, ${r.unmeasuredSeats} of ${r.seats} seats unmeasured` : `, ${r.seats} seat${r.seats === 1 ? '' : 's'}`;
        const measured = num(r.input) !== null && num(r.output) !== null;
        return bar(r.role, measured ? tot(r) : null, max, num(r.unmeasuredSeats) ? 'warn' : '', measured ? `${tokens(tot(r))}${gap}` : null);
      }));
      const sumOf = (k) => (roles.some((r) => num(r[k]) === null) ? null : roles.reduce((a, r) => a + r[k], 0));
      const all = hit({ input: sumOf('input'), cachedInput: sumOf('cachedInput') });
      byId('cache-tile').textContent = !ledger || all === null ? 'Cache hit rate not measured' : `Cache hit rate, 7 days: ${Math.round(all)}% of input tokens`;
      put(byId('cost-role-rows'), roles.map((r) => tr([h('td', null, r.role), cell(r.seats), cell(r.unmeasuredSeats), cell(r.input, tokens), cell(r.cachedInput, tokens), cell(hit(r), (v) => `${Math.round(v)}%`), cell(r.output, tokens)])));
    }
  }


  // Ordered like the terminal's list: in progress, then pending, then done.
  const TODO_BADGE = { in_progress: ['now', 'ok'], pending: ['waiting', ''], completed: ['done', 'ok'] };
  function renderTodos(t) {
    const items = t && Array.isArray(t.items) ? t.items.filter(Boolean) : null;
    note('todos', items ? '' : 'Main session task list not measured');
    sub('todos-sub', items ? `${items.length} items` : '');
    if (!items) { byId('todos-count').textContent = ''; put(byId('todos-bar'), []); put(byId('todos-list'), []); return; }
    const done = items.filter((i) => i.status === 'completed');
    const rank = (i) => (i.status === 'in_progress' ? 0 : 1);
    const open = items.filter((i) => i.status !== 'completed').sort((a, b) => rank(a) - rank(b));
    const now = items.filter((i) => i.status === 'in_progress').length, n = Math.max(1, items.length);
    put(byId('todos-bar'), [mbar([[(100 * done.length) / n, 'g'], [(100 * now) / n, 'b']], 'h10'),
      cap([strong(`${done.length} of ${items.length}`), ' done'], `${now} in progress`)]);
    byId('todos-count').textContent = `${items.length} task${items.length === 1 ? '' : 's'} (${done.length} done, ${open.length} open), session ${String(t.sessionId).slice(0, 8)}`;
    put(byId('todos-list'), items.length === 0 ? [h('li', 'empty', 'No tasks')] : open.concat(done).map((i) => {
      const li = h('li', i.status === 'completed' ? 'done' : null);
      const [text, tone] = TODO_BADGE[i.status] || [String(i.status), ''];
      li.append(badge(text, tone), ' ', h('span', 'todo-text', i.status === 'in_progress' ? i.activeForm || i.subject : i.subject));
      li.dataset.status = String(i.status);
      li.dataset.id = String(i.id);
      return li;
    }));
  }

  // Running first, newest first within each, as the collector ordered them.
  function renderAgents(a) {
    const items = a && Array.isArray(a.items) ? a.items.filter(Boolean) : null;
    note('agents', items ? '' : "Main's background agents not measured");
    if (!items) { sub('agents-sub', ''); byId('agents-count').textContent = ''; put(byId('agents-list'), []); return; }
    const running = items.filter((i) => i.running === true);
    const rest = items.filter((i) => i.running !== true);
    sub('agents-sub', `${running.length} running`);
    byId('agents-count').textContent = `${items.length} agent${items.length === 1 ? '' : 's'} (${running.length} running), session ${String(a.sessionId).slice(0, 8)}`;
    // Running agents show in the compact view; finished ones with the detailed one.
    const none = running.length ? [] : [h('li', 'empty', items.length ? 'None running.' : 'No background agents')];
    put(byId('agents-list'), none.concat(running.concat(rest).map((i) => {
      const li = h('li', i.running === true ? null : 'done more');
      li.dataset.id = String(i.id);
      const t = parseTime(i.startedAt);
      li.append(h('p', 'agent-name', i.description || 'Description not measured'),
        h('p', 'meta', [i.running === true ? 'Running' : i.running === false ? 'Finished' : 'State not measured',
          i.model ? String(i.model) : 'model not measured',
          Number.isFinite(t) ? `started ${when(t)}` : 'start not measured',
          num(i.ageSec) === null ? 'last activity not measured' : `last activity ${ago(i.ageSec)} ago`].join(' · ')));
      return li;
    })));
  }

  // Newest first, as the collector ordered them; only the fields the fire log
  // stores. retry is the session's next call: the identical one, or another.
  // No prototype: a stored value such as "toString" must look up nothing.
  const RETRY = Object.assign(Object.create(null), { identical: 'retried the identical call', 'worked-around': 'worked around it' });
  const AGENT = Object.assign(Object.create(null), { claude: 'Claude', codex: 'Codex' });
  function renderGuardBlocks(g, now) {
    const items = g && Array.isArray(g.items) ? g.items.filter(Boolean) : null;
    const dl = byId('guard-facts');
    dl.replaceChildren();
    if (!items) { byId('guard-blocks-count').textContent = ''; put(byId('guard-hour'), []); put(byId('guard-blocks-list'), []); return; }
    const hour = num(g.lastHour), avg = num(g.perHour);
    const spike = hour !== null && avg !== null && hour > 3 * avg;
    if (hour === null || avg === null) put(byId('guard-hour'), [uline('Last hour', ''), cap(nm('Hourly rate'), '')]);
    else {
      const top = Math.max(hour, avg * 3, 1);
      put(byId('guard-hour'), [uline('Last hour', `average ${Math.round(avg)} an hour`), mbar([[(100 * hour) / top, spike ? 'r' : 'g']], 'h14', (100 * avg) / top),
        cap([strong(hour.toLocaleString('en-US')), ' blocks'], spike ? badge(`${Math.round(hour / avg)} times the average`, 'crit') : badge('normal', 'ok'))]);
    }
    const split = g.byAgent && num(g.byAgent.claude) !== null && num(g.byAgent.codex) !== null;
    fact(dl, '7 days', num(g.blocks) === null ? nm() : `${g.blocks.toLocaleString('en-US')} blocks${split ? ` · Claude ${g.byAgent.claude.toLocaleString('en-US')} · Codex ${g.byAgent.codex.toLocaleString('en-US')}` : ''}`);
    byId('guard-blocks-count').textContent = items.length
      ? `Latest ${items.length} of ${num(g.blocks) === null ? items.length : g.blocks} blocks${split ? ` (${g.byAgent.claude} Claude, ${g.byAgent.codex} Codex)` : ''}` : '';
    put(byId('guard-blocks-list'), items.length === 0 ? [tr([h('td', 'empty', 'No blocks recorded')])] : items.map((i) => {
      const t = parseTime(i.at);
      const at = h('td', null, Number.isFinite(t) ? `${ago((now - t) / 1000)} ago` : 'time not recorded');
      if (Number.isFinite(t)) at.append(h('br'), h('small', 'meta', when(t)));
      const guard = h('td');
      guard.append(h('span', 'agent-name', i.hook || 'Hook not recorded'));
      const rest = [i.tool, AGENT[i.agent], i.event, i.summary].filter(Boolean).join(' · ');
      if (rest) guard.append(h('br'), h('small', 'meta', rest));
      return tr([at, guard, h('td', null, i.worktree || ''), h('td', null, RETRY[i.retry] || '')]);
    }));
    flag('guard-blocks', spike);
  }

  // The collector's active alerts (dashboard_alerts.jq). An input it could not
  // measure is named, and "No alerts" shows only when every input was measured.
  // A stopped collector is an alert too (tick sets it): its last list may be old.
  // Each alert links to the panel its id names, so a hidden panel's alert is never lost.
  const ALERT_PANEL = [['limit', 'limit'], ['guard', 'guard-blocks'], ['cache', 'cost-role'], ['host', 'host'],
    ['stage', 'units'], ['builder', 'builds'], ['question', 'needs']];
  const alertPanel = (id) => { const m = ALERT_PANEL.find(([p]) => String(id).startsWith(`${p}-`)); return m ? m[1] : null; };
  const jump = (panel, text) => { const a = h('a', null, text); a.setAttribute('href', `#${panel}`); return a; };
  let collectorAlert = '';
  function renderAlerts(items, src, now) {
    const stopped = [];
    if (collectorAlert) {
      stopped.push(h('li'));
      stopped[0].append(badge('critical', 'crit'), ' ', h('span', 'alert-text', collectorAlert));
    }
    looks.delete('alerts');
    sub('alerts-sub', Array.isArray(items) ? `${items.length + stopped.length} open` : '');
    flag('alerts', stopped.length > 0 || (Array.isArray(items) && items.length > 0));
    byId('alerts').dataset.partial = Array.isArray(items) ? '1' : '';
    if (!Array.isArray(items)) { note('alerts', 'Alerts not measured'); put(byId('alerts-list'), stopped); return; }
    const missing = src && src.status === 'not-measured' ? src.error || 'an alert input' : '';
    note('alerts', missing && `Not measured: ${missing}`);
    put(byId('alerts-list'), items.length === 0 ? (missing || stopped.length ? stopped : [h('li', 'empty', 'No alerts')]) : stopped.concat(items.map((i) => {
      const li = h('li');
      const since = parseTime(i.since);
      const crit = i.severity === 'crit';
      const at = h('small', null, `since ${Number.isFinite(since) ? `${ago((now - since) / 1000)} ago` : 'unknown'}`);
      if (Number.isFinite(since)) at.title = when(since);
      li.append(badge(crit ? 'critical' : 'warning', crit ? 'crit' : 'warn'), ' ', h('span', 'alert-text', i.text), ' ', at);
      const panel = alertPanel(i.id);
      if (panel) { li.append(' ', jump(panel, 'open panel')); flag(panel, true); }
      return li;
    })));
  }

  // Issue 274: the alerts that cleared in the last 24 h (the collector keeps them), folded under the open ones.
  function renderResolved(items) {
    const fold = byId('alerts-resolved');
    const list = Array.isArray(items) ? items : [];
    fold.hidden = list.length === 0;
    fold.querySelector('summary').textContent = `Resolved in the last 24 h (${list.length})`;
    const at = (t) => (Number.isFinite(parseTime(t)) ? hm(new Date(parseTime(t))) : 'unknown');
    put(fold.querySelector('ul'), list.map((i) => h('li', null, `${i.text} from ${at(i.since)} to ${at(i.resolvedAt)}`)));
  }

  // The 7-day limit panel. The collector computes every figure at its sample
  // time; this only formats, and a missing figure reads "no data".
  const WEEK_MS = 7 * 86400000;
  const day = (ms) => { const d = new Date(ms); return `${MONTHS[d.getMonth()]} ${d.getDate()}`; };
  const span = (sec) => {
    const m = Math.round(Math.abs(sec) / 60), d = Math.floor(m / 1440), hh = Math.floor((m % 1440) / 60);
    return d ? `${d}d ${pad(hh)}h` : `${hh}h ${pad(m % 60)}m`;
  };
  const money = (v) => (v >= 1000 ? `$${(v / 1000).toFixed(1)}k` : `$${v.toFixed(2)}`);
  function tile(label, value, tone, detail) {
    const d = h('div', `tile ${value === null ? 'nm' : tone || ''}`.trim());
    const v = h('p', 'tile-value n', value === null ? 'no data' : value);
    if (value !== null && detail) v.append(h('span', 'tile-detail', detail));
    d.append(h('p', 'tile-label', label), v);
    return d;
  }
  function svgEl(tag, attrs, cls, text) {
    const e = document.createElementNS(SVG_NS, tag);
    for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, String(v));
    if (cls) e.setAttribute('class', cls);
    if (text !== undefined) e.textContent = String(text);
    return e;
  }
  const readings = (list) => (Array.isArray(list) ? list : [])
    .map((r) => [parseTime(r && r.at), num(r && r.pct)]).filter(([t, p]) => Number.isFinite(t) && p !== null);

  // o: the API panel's dollar wording for the same axes; without it this is the subscription graph.
  function limitChart(l, start, updatedAt, o = {}) {
    const W = 900, H = 220, L = 40, R = 10, T = 10, B = 25;
    const x = (ms) => L + Math.max(0, Math.min(1, (ms - start) / WEEK_MS)) * (W - L - R);
    const y = (p) => H - B - (Math.max(0, Math.min(100, p)) / 100) * (H - T - B);
    const f = (n) => n.toFixed(1);
    const svg = svgEl('svg', { viewBox: `0 0 ${W} ${H}`, role: 'img' }, 'limit-svg');
    svg.append(svgEl('title', {}, null, o.title || 'Percent of the 7-day limit used, recorded by the collector, against a linear goal'));
    for (const p of [0, 25, 50, 75, 100]) {
      svg.append(svgEl('line', { x1: L, x2: W - R, y1: f(y(p)), y2: f(y(p)) }, 'grid-line'),
        svgEl('text', { x: L - 6, y: f(y(p) + 4) }, 'axis-y', o.axis ? o.axis(p) : `${p}%`));
    }
    for (let i = 0; i <= 7; i++) {
      const t = start + i * 86400000, d = new Date(t);
      svg.append(svgEl('text', { x: f(x(t)), y: H - 6 }, 'axis-x', `${DAYS[d.getDay()]} ${d.getDate()}`));
    }
    const fh = l.fiveHour;
    const fs = fh ? parseTime(fh.start) : NaN, fe = fh ? parseTime(fh.end) : NaN;
    if (Number.isFinite(fs) && Number.isFinite(fe)) {
      svg.append(svgEl('rect', { x: f(x(fs)), y: T, width: f(Math.max(1, x(fe) - x(fs))), height: H - T - B }, 'five-hour'));
    }
    if (!o.noGoal) svg.append(svgEl('line', { x1: x(start), y1: y(0), x2: x(start + WEEK_MS), y2: y(100) }, 'goal-line'));
    if (Number.isFinite(updatedAt)) svg.append(svgEl('line', { x1: f(x(updatedAt)), x2: f(x(updatedAt)), y1: T, y2: f(y(0)) }, 'now-line'));
    const goal = num(l.goalPct), left = num(l.timeLeftSec), reset = parseTime(l.resetsAt);
    // The higher end label sits above its dot and the lower one below, so they never overlap.
    const goalHigh = goal !== null && goal >= (num(l.usedPct) ?? 0);
    // Stepped: a reading holds until the next one replaces it.
    const stepped = (pts, cls, dot) => {
      let d = `M${f(x(pts[0][0]))},${f(y(pts[0][1]))}`;
      for (let i = 1; i < pts.length; i++) d += `H${f(x(pts[i][0]))}V${f(y(pts[i][1]))}`;
      const last = pts[pts.length - 1];
      svg.append(svgEl('path', { d }, cls), svgEl('circle', { cx: f(x(last[0])), cy: f(y(last[1])), r: 4 }, dot));
      return last;
    };
    // Codex's own account on the same week axis: its readings, in its own percent.
    const cx = readings(l.codex && l.codex.history).filter(([t]) => t >= start && t <= start + WEEK_MS);
    if (cx.length >= 2) stepped(cx, 'codex-line', 'codex-dot');
    const pts = readings(l.history);
    // One reading is no trend: say when the history starts instead of a lone dot.
    if (pts.length < 2) {
      const first = pts.length ? pts[0][0] : updatedAt;
      svg.append(svgEl('text', { x: f((L + W - R) / 2), y: f((T + H - B) / 2) }, 'history-note',
        Number.isFinite(first) ? `history starts ${day(first)}` : 'no history yet'));
    } else {
      const last = stepped(pts, 'actual-line', 'actual-dot');
      svg.append(svgEl('text', { x: f(x(last[0]) + 8), y: f(y(last[1]) + (goalHigh ? 16 : -8)) }, 'end-label used', o.used ? o.used(last[1]) : `${Math.round(last[1])}% used`));
    }
    if (goal !== null && left !== null && Number.isFinite(reset)) {
      const at = reset - left * 1000;
      svg.append(svgEl('circle', { cx: f(x(at)), cy: f(y(goal)), r: 3 }, 'goal-dot'),
        svgEl('text', { x: f(x(at) + 8), y: f(y(goal) + (goalHigh ? -8 : 16)) }, 'end-label goal', o.goal ? o.goal(goal) : `${Math.round(goal)}% goal`));
    }
    return svg;
  }

  // One account's bar in the compact view: used against the white even-pace line.
  function limitBar(name, x) {
    const used = num(x.usedPct), goal = num(x.goalPct), under = num(x.underPts), left = num(x.timeLeftSec);
    if (used === null) return [uline(name, ''), cap(nm(name), '')];
    const over = under !== null && under < 0;
    return [uline(name, left === null ? '' : `resets in ${span(left)}`), mbar([[used, over ? 'r' : 'g']], 'h14', goal),
      cap([strong(`${Math.round(used)}%`), ' used'], [goal === null ? null : `${goal.toFixed(1)}% of the week gone · `,
        under === null ? null : badge(`${Math.abs(under).toFixed(1)} points ${over ? 'over' : 'under'} pace`, over ? 'crit' : 'ok')])];
  }

  function renderLimit(l, now, updatedAt) {
    l = l || {};
    byId('limit-who').textContent = l.accountLabel ? `Claude (${l.accountLabel}) and Codex` : 'Claude and Codex';
    byId('limit').classList.toggle('api', l.billing === 'api' && !!l.api);
    if (l.billing === 'api' && l.api) { renderLimitApi(l.api, updatedAt); return; }
    const start = parseTime(l.windowStart), reset = parseTime(l.resetsAt);
    const week = Number.isFinite(start) && Number.isFinite(reset);
    byId('limit-week').textContent = week ? `${day(start)} – ${day(reset)} · In progress` : 'no data';
    const used = num(l.usedPct), goal = num(l.goalPct), under = num(l.underPts), paceSec = num(l.paceSec), left = num(l.timeLeftSec);
    const req = num(l.requests), cwp = num(l.cacheWritePct24h);
    const c = l.cost || {};
    const cw = num(c.week), ct = num(c.today), cp = num(c.projected), ch = num(c.perHour), cpp = num(c.perPoint), unpriced = num(c.unpricedRequests);
    // A total with requests left out is a partial one, and says how many and on which models.
    const tun = num(c.todayUnpriced), models = Array.isArray(c.unpricedModels) && c.unpricedModels.length ? ` (${c.unpricedModels.join(', ')})` : '';
    const partial = tun ? `partial: ${tun.toLocaleString('en-US')} unpriced${models}` : '';
    const over = under !== null && under < 0;
    const cx = l.codex || {};
    put(byId('limit-bars'), limitBar('Claude', l).concat(limitBar('Codex', cx)));
    const dl = byId('limit-facts');
    dl.replaceChildren();
    const fh = l.fiveHour && num(l.fiveHour.usedPct);
    const dollars = (v) => `$${Math.round(v).toLocaleString('en-US')}`;
    fact(dl, '5-hour', fh === null || fh === undefined ? nm() : `${Math.round(fh)}% used`);
    fact(dl, 'List price', cw === null ? nm() : `${dollars(cw)} this week${ct === null ? '' : ` · ${dollars(ct)} today`}${ch === null ? '' : ` · ${dollars(ch)} an hour`}`);
    // The figure is the week's cost at 100% of the limit, the same one the tile below names; it is no forecast.
    fact(dl, 'Projected', cp === null ? nm() : `${dollars(cp)} at 100% of the limit`);
    fact(dl, 'Requests', req === null ? nm() : `${req.toLocaleString('en-US')} this week`);
    fact(dl, 'Cache writes', cwp === null ? nm() : `${cwp.toFixed(1)}% of cached input, last 24 h`);
    put(byId('limit-tiles'), [
      tile('Used this week', used === null ? null : `${Math.round(used)}%`),
      tile('Goal now', goal === null ? null : `${goal.toFixed(1)}%`),
      tile(over ? 'Over pace by' : 'Under pace by', under === null || paceSec === null ? null
        : `${Math.round(Math.abs(under))} pts · ${span(paceSec)}`, over ? 'crit' : 'ok'),
      tile('Time left', left === null ? null : span(left)),
      tile('Cost this week', cw === null ? null : money(cw)),
      tile('Cost today', ct === null ? null : money(ct), '', partial),
      tile('Projected cost at 100%', cp === null ? null : money(cp), '', ch === null ? null : `${money(ch)}/hr`),
      tile('Value per point', cpp === null ? null : money(cpp)),
      tile('Requests', req === null ? null : req.toLocaleString('en-US'), '', 'this host'),
      // Over 5% is the collector's cache-write alert (dashboard_alerts.jq).
      tile('Cache write share, 24 h', cwp === null ? null : `${cwp.toFixed(1)}%`, cwp !== null && cwp > 5 ? 'crit' : '', 'of input tokens'),
    ]);
    const out = unpriced || tun;
    byId('limit-note').textContent = cw === null && ct === null && !out ? ''
      : `Dollars are list-price equivalents: what this host's logged tokens would cost on the pay-as-you-go API${out ? `; ${out.toLocaleString('en-US')} requests on unpriced models${models} are left out` : ''}.`;
    put(byId('limit-chart'), [week ? limitChart(l, start, updatedAt) : h('p', 'nm', 'no data')]);
    const n = readings(l.history).length, cn = readings(cx.history).length;
    byId('limit-graph-title').textContent = `Use across the week (Claude ${n} samples, Codex ${cn < 2 ? 'no history yet' : `${cn} samples`})`;
    byId('limit-summary').textContent = paceLine(used, goal, under, start, reset, now) || 'no data';
    renderCodexLimit(cx, now);
    flag('limit', over || (num(cx.underPts) !== null && cx.underPts < 0));
  }

  // A machine that pays by API: the same panel in dollars against the weekly limit the owner set.
  // With no limit the graph scales to the spend and draws no guide; nothing here is a percent.
  const wholeDollars = (v) => `$${Math.round(v).toLocaleString('en-US')}`;
  function renderLimitApi(a, updatedAt) {
    const start = parseTime(a.windowStart), reset = parseTime(a.resetsAt);
    const week = Number.isFinite(start) && Number.isFinite(reset);
    byId('limit-week').textContent = week ? `${day(start)} – ${day(reset)} · In progress` : 'no data';
    const limit = num(a.limitUsd), spent = num(a.spentUsd), goal = num(a.goalUsd), under = num(a.underUsd), paceSec = num(a.paceSec), left = num(a.timeLeftSec);
    const req = num(a.requests), unpriced = num(a.unpricedRequests);
    const claude = num(a.claudeUsd), codex = num(a.codexUsd), est = num(a.estimatedUsd), tier = num(a.tierUsd);
    const names = Array.isArray(a.unpricedModels) ? a.unpricedModels.map(String) : [];
    const over = under !== null && under < 0;
    // A provider not read or a request not priced: the total is a floor, so under pace is not an all-clear.
    const partial = a.complete === false && spent !== null, unsure = partial && !over;
    const top = limit ?? (spent ? spent * 1.25 : null);
    const share = (v) => (v === null || !top ? null : (100 * v) / top);
    put(byId('limit-bars'), spent === null ? [uline('API spend', ''), cap(nm('API spend'), '')]
      : [uline('API spend', left === null ? '' : `resets in ${span(left)}`), mbar([[Math.min(100, share(spent) ?? 0), over ? 'r' : unsure ? 'a' : 'g']], 'h14', limit === null ? null : share(goal)),
        cap([partial ? 'at least ' : '', strong(wholeDollars(spent)), limit === null ? ' spent this week' : ` of ${wholeDollars(limit)}`],
          unsure ? 'accounting incomplete' : under === null ? 'no weekly limit set' : badge(`${wholeDollars(Math.abs(under))} ${over ? 'over' : 'under'} pace`, over ? 'crit' : 'ok'))]);
    const dl = byId('limit-facts');
    dl.replaceChildren();
    fact(dl, 'Weekly limit', limit === null ? 'not set' : wholeDollars(limit));
    fact(dl, 'Even pace now', goal === null ? nm() : wholeDollars(goal));
    fact(dl, 'Requests', req === null ? nm() : `${req.toLocaleString('en-US')} this week`);
    fact(dl, 'Claude spend', claude === null ? nm() : wholeDollars(claude));
    fact(dl, 'Codex spend', codex === null ? nm() : wholeDollars(codex));
    put(byId('limit-tiles'), [
      tile('Spent this week', spent === null ? null : money(spent)),
      tile('Goal now', goal === null ? null : money(goal)),
      unsure ? tile('Pace', 'accounting incomplete', 'warn') : tile(over ? 'Over pace by' : 'Under pace by', under === null || paceSec === null ? null
        : `${wholeDollars(Math.abs(under))} · ${span(Math.abs(paceSec))}`, over ? 'crit' : 'ok'),
      tile('Time left', left === null ? null : span(left)),
      tile('Weekly limit', limit === null ? 'not set' : wholeDollars(limit)),
      tile('Requests', req === null ? null : req.toLocaleString('en-US'), '', 'this host'),
    ]);
    byId('limit-note').textContent = `API billing: no usage windows. ${limit === null ? 'Set a weekly limit: add "weeklyLimitUsd" to billing.json in the dashboard folder. ' : ''}`
      + `Dollars are list prices over this host's logged Claude and Codex tokens since Monday 00:00${
        spent !== null && claude === null ? '; Claude spend is not measured' : ''}${
        spent !== null && codex === null ? '; Codex spend is not measured' : ''}${
        est ? `; ${money(est)} of the total is estimated from the nearest published price` : ''}${
        tier ? `; ${money(tier)} of the total is priced by Codex tier, not by exact version` : ''}${
        unpriced ? `; ${unpriced.toLocaleString('en-US')} requests on unpriced models are left out${names.length ? ` (${names.join(', ')})` : ''}` : ''}.`;
    const usd = (p) => wholeDollars((p / 100) * top);
    const pts = (Array.isArray(a.history) ? a.history : []).map((r) => ({ at: r && r.at, pct: share(num(r && r.usd)) }));
    put(byId('limit-chart'), [week && top ? limitChart({ history: pts, usedPct: share(spent), goalPct: limit === null ? null : share(goal), timeLeftSec: a.timeLeftSec, resetsAt: a.resetsAt },
      start, updatedAt, { axis: usd, used: (p) => `${usd(p)} spent`, goal: (p) => `${usd(p)} goal`, noGoal: limit === null,
        title: 'Dollars spent this week by API, recorded by the collector, against the weekly limit' }) : h('p', 'nm', 'no data')]);
    byId('limit-graph-title').textContent = `Spend across the week (${readings(pts).length} points)`;
    byId('limit-summary').textContent = [spent === null ? null : `${partial ? 'at least ' : ''}${wholeDollars(spent)} spent`,
      partial ? 'accounting incomplete' : null, goal === null ? null : `goal ${wholeDollars(goal)}`,
      under === null || unsure ? null : `${over ? 'over' : 'under'} pace ${wholeDollars(Math.abs(under))}`,
      spent !== null && limit === null ? 'no weekly limit set' : null].filter(Boolean).join(' · ') || 'no data';
    put(byId('limit-codex-tiles'), []);
    byId('limit-codex-note').textContent = '';
    flag('limit', over || partial);
  }

  // The folded card's one line. Run-out is at the week's average rate so far,
  // which exists from the first reading; at or past the reset it lasts the week.
  function paceLine(used, goal, under, start, reset, now) {
    const line = [];
    if (used !== null) {
      line.push(`${Math.round(used)}% used`);
      if (goal !== null) line.push(`goal ${goal.toFixed(1)}%`);
      if (under !== null) line.push(`${under < 0 ? 'over' : 'under'} pace ${Math.round(Math.abs(under))} pts`);
      const spent = now - start;
      if (spent > 0) {
        const out = used > 0 ? now + ((100 - used) / used) * spent : Infinity;
        line.push(Number.isFinite(reset) && out >= reset ? 'at this pace the limit lasts to the reset'
          : Number.isFinite(out) ? `at this pace the limit runs out ~${dayTime(out)}` : null);
      }
    }
    return line.filter(Boolean).join(' · ');
  }

  // Codex's own account, its own tiles: never added to or averaged with Claude's.
  // The reading is only as fresh as Codex's last call, so its time is shown.
  function renderCodexLimit(c, now) {
    c = c || {};
    const used = num(c.usedPct), goal = num(c.goalPct), under = num(c.underPts), paceSec = num(c.paceSec), left = num(c.timeLeftSec);
    const over = under !== null && under < 0;
    put(byId('limit-codex-tiles'), [
      tile('Used this week', used === null ? null : `${Math.round(used)}%`),
      tile('Goal now', goal === null ? null : `${goal.toFixed(1)}%`),
      tile(over ? 'Over pace by' : 'Under pace by', under === null || paceSec === null ? null
        : `${Math.round(Math.abs(under))} pts · ${span(paceSec)}`, over ? 'crit' : 'ok'),
      tile('Time left', left === null ? null : span(left)),
    ]);
    const read = parseTime(c.readAt);
    const line = used === null ? '' : paceLine(used, goal, under, parseTime(c.windowStart), parseTime(c.resetsAt), now);
    byId('limit-codex-note').textContent = used === null ? 'Codex: no data'
      : [line, Number.isFinite(read) ? `as of ${when(read)}` : 'reading time not measured'].filter(Boolean).join(' · ');
  }

  // A summary tile is a link: it jumps to the panel that holds its detail.
  function measure(label, value, tone, detail, panel) {
    const d = jump(panel, '');
    d.className = `measure ${tone || ''}`.trim();
    d.append(h('span', 'measure-label', label), h('b', 'measure-value n', value === null ? '–' : value));
    if (detail) d.append(h('small', 'measure-detail', detail));
    return d;
  }

  function renderSummary(d, hostInfo) {
    const n = d.needsOwner || {};
    const dec = Array.isArray(n.decisions) ? n.decisions.filter((x) => x && x.answeredAt == null && x.waitsOn !== 'main').length : null;
    // Unknown stages and the long-lived seat are shown, not counted.
    const inflight = d.units && Array.isArray(d.units.inFlight) ? d.units.inFlight.filter((u) => u && STAGES.includes(u.stage)).length : null;
    const unp = num(d.mainChain && d.mainChain.unpushed);
    const { builders, used } = workingBuilders(d.units);
    const per = hostInfo.per;
    const al = Array.isArray(d.alerts) ? d.alerts : null;
    const p1 = d.githubP1 && Number.isInteger(d.githubP1.count) ? d.githubP1.count : null;
    const crit = al ? al.filter((a) => a && a.severity === 'crit').length : 0;
    const lim = (label, x) => {
      const u = num(x && x.usedPct), g = num(x && x.goalPct), under = num(x && x.underPts);
      return measure(label, u === null ? null : `${Math.round(u)}%`, u === null ? 'nm' : under !== null && under < 0 ? 'crit' : 'ok', g === null ? null : `${Math.round(g)}% of week gone`, 'limit');
    };
    const api = d.limit && d.limit.billing === 'api' && d.limit.api ? d.limit.api : null;
    const spent = num(api && api.spentUsd), aLim = num(api && api.limitUsd), aUnder = num(api && api.underUsd);
    // The same rule as the panel: a partial total that is not over pace is not an all-clear.
    const aUnsure = Boolean(api && api.complete === false && spent !== null && !(aUnder !== null && aUnder < 0));
    // The day's cost is the collector's one priced sum for the project shown (limit.today[<project>]): a total
    // with a part missing is a floor.
    const days = d.limit && d.limit.today;
    const day = days && project !== null && Object.prototype.hasOwnProperty.call(days, project) ? days[project] : null;
    const dSpent = num(day && day.spentUsd), dEst = num(day && day.estimatedUsd), dTier = num(day && day.tierUsd), dUn = num(day && day.unpricedRequests);
    const dModels = day && Array.isArray(day.unpricedModels) && day.unpricedModels.length ? ` (${day.unpricedModels.join(', ')})` : '';
    const dUnText = dUn ? `${dUn.toLocaleString('en-US')} requests unpriced${dModels}` : null;
    const dShare = (label, v) => `${label} ${num(v) === null ? 'not measured' : money(v)}`;
    put(byId('summary'), [
      measure('Alerts', al ? al.length : null, !al ? 'nm' : crit ? 'crit' : al.length ? 'warn' : 'ok', al ? `${crit} critical` : null, 'alerts'),
      measure(`Waiting on ${ownerName(n)}`, dec, dec ? 'warn' : dec === 0 ? 'ok' : 'nm', dec === null ? null : `${dec} open decisions`, 'needs'),
      measure('Open P1', p1, p1 === null ? 'nm' : p1 ? 'warn' : 'ok', null, 'needs'),
      measure('Builds running', used, used === null ? 'nm' : 'ok', builders ? `of ${builders.length} Builders` : null, 'builds'),
      ...(api ? [
        measure('API spend, week', spent === null ? null : wholeDollars(spent), spent === null ? 'nm' : aUnder !== null && aUnder < 0 ? 'crit' : aUnsure ? 'warn' : 'ok',
          aLim === null ? 'no weekly limit set' : `of ${wholeDollars(aLim)}`, 'limit'),
        measure('Week pace', aUnsure ? 'incomplete' : aUnder === null ? null : `${wholeDollars(Math.abs(aUnder))} ${aUnder < 0 ? 'over' : 'under'}`, aUnsure ? 'warn' : aUnder === null ? 'nm' : aUnder < 0 ? 'crit' : 'ok',
          'against the weekly limit', 'limit'),
      ] : []),
      // A 7-day tile only where that provider has a subscription window; a failed or unknown read still shows it.
      ...(d.limit && d.limit.billing === 'api' ? [] : [lim('Claude 7-day', d.limit)]),
      ...(d.limit && ['api', 'none'].includes(d.limit.codexBilling) ? [] : [lim('Codex 7-day', d.limit && d.limit.codex)]),
      measure('Cost today', dSpent === null ? null : `${day.complete === false ? 'at least ' : ''}${money(dSpent)}`, dSpent === null ? 'nm' : day.complete === false ? 'warn' : '',
        dSpent === null ? dUnText : [`${dShare('Claude', day.claudeUsd)} + ${dShare('Codex', day.codexUsd)}, list price`, dEst ? `${money(dEst)} estimated` : null,
          dTier ? `${money(dTier)} priced by tier, not exact version` : null,
          dUnText].filter(Boolean).join(' · '), 'limit'),
      measure('Unpushed', unp, unp === null ? 'nm' : unp > 0 ? 'info' : 'ok', 'commits on local main', 'main-chain'),
      measure('Units in flight', inflight, inflight === null ? 'nm' : '', null, 'units'),
      measure('Host load', hostInfo.load === null ? null : hostInfo.load.toFixed(2), per === null ? 'nm' : per >= 2 ? 'crit' : per >= 1 ? 'warn' : 'ok',
        hostInfo.cpus ? `${hostInfo.cpus} cores` : null, 'host'),
    ]);
    // issue 211: the phone tab badges count what the tiles above count; empty when not measured.
    for (const [k, v] of [['units', inflight], ['builds', used], ['alerts', al ? al.length : null], ['you', dec]]) q(`#tabs [data-badge="${k}"]`).textContent = v === null ? '' : String(v);
  }

  // The footer: how many of the collector's sources are fresh, and which are not.
  function renderSources(sources, at) {
    const ids = Object.keys(sources || {});
    const not = (st) => ids.filter((id) => sources[id] && sources[id].status === st);
    const stale = not('stale'), missing = not('not-measured');
    byId('sources-foot').textContent = !ids.length ? 'Data sources not measured'
      : [`${ids.length - stale.length - missing.length} of ${ids.length} data sources fresh`, stale.length ? `stale: ${stale.join(', ')}` : null,
        missing.length ? `not measured: ${missing.join(', ')}` : null, Number.isFinite(at) ? `sampled ${when(at)}` : null].filter(Boolean).join(' · ');
  }

  // Needs a look: a panel with an alert, a warning of its own, something waiting, or a source that is not fresh.
  // The warn and crit classes are what colour a panel amber or red, so the mark is read from them here, once.
  // The segmented bars carry no warn or crit class: their panels flag themselves instead.
  const toned = (card) => Boolean(card.querySelector('.warn, .crit'));
  function markLook() {
    for (const card of document.querySelectorAll('.card[data-sources]')) {
      if (looks.has(card.id) || toned(card) || card.dataset.state !== 'fresh') card.dataset.look = ''; else delete card.dataset.look;
    }
  }

  // Live rows (issue 466): the host pushes {rows: {<unit>: {sampledAt, seen, row}}} when a unit's stage changes. The last
  // rows are laid over each snapshot's inFlight list only where they are newer by the stream mark: the same generation
  // and a larger sequence than the snapshot's own mark. A unit's mark is its row's, or, for one the snapshot lacks, the
  // cycle's (units.seen, so an empty list has one too); a snapshot with no mark is never overridden. A null row removes the card.
  let liveRows = {};
  const newer = (l, s) => !!l && !!s && typeof l === 'object' && Number.isFinite(l.gen) && l.gen === s.gen
    && Number.isFinite(l.seq) && Number.isFinite(s.seq) && l.seq > s.seq;
  function overlaid(d) {
    const units = d.units;
    if (!units || !Array.isArray(units.inFlight)) return d;
    const list = units.inFlight.slice();
    const cycle = units.seen || (list.find((u) => u && u.seen && typeof u.seen === 'object') || {}).seen;
    for (const [name, live] of Object.entries(liveRows)) {
      if (!live || typeof live !== 'object') continue;
      const i = list.findIndex((u) => u && u.unit === name);
      const old = i >= 0 ? list[i] : null;
      if (!newer(live.seen, old ? old.seen : cycle)) continue;
      if (live.row === null) { if (i >= 0) list.splice(i, 1); continue; }
      if (!live.row || typeof live.row !== 'object') continue;
      let next = live.row;
      // The fast lane reads no cost (a null there is unread, not none): the snapshot's known figures stay.
      if (old && old.builder && next.builder && typeof next.builder === 'object') next = { ...next, builder: { ...next.builder, cost: old.builder.cost } };
      if (old && old.plan && next.plan && typeof next.plan === 'object') next = { ...next, plan: { ...next.plan, cost: old.plan.cost } };
      if (i >= 0) list[i] = next; else list.push(next);
    }
    return { ...d, units: { ...units, inFlight: list } };
  }
  let events = null;
  function openEvents() {
    // A browser without EventSource keeps the 15 s data.js reload alone.
    if (events || typeof EventSource !== 'function') return;
    // Each project's rows are its own: the address names the project shown.
    events = new EventSource(project === null ? 'events' : `p/${encodeURIComponent(project)}/events`);
    events.onmessage = (e) => {
      let msg;
      try { msg = JSON.parse(e.data); } catch (err) { return; }
      if (!msg || typeof msg.rows !== 'object' || msg.rows === null) return;
      liveRows = msg.rows;
      if (data) render(data);
    };
  }
  function render(snapshot) {
    const now = Date.now();
    looks = new Set();
    const d = overlaid(view(snapshot));
    unitCost = (d.sources && d.sources['unit-cost']) || null;
    const title = typeof d.name === 'string' && d.name ? d.name : project ? `${project} Dashboard` : '';
    if (title) { byId('title').textContent = title; document.title = title; }
    renderNeeds(d.needsOwner, now, d.githubP1, d.githubProposed);
    renderUnits(d.units, now, d.needsOwner && d.needsOwner.decisions);
    renderCostUnit(d.units && d.units.costPerUnit);
    renderReview(d.reviewLoop, d.escapes);
    renderTests(d.tests);
    renderBuilds(d.units, now, d.github);
    renderMergeLine(d.github, d.units, d.sources);
    renderHeld(d.github, d.units, d.sources);
    renderNextPush(d.nextPush, d.github, d.sources, now);
    renderChain(d.mainChain, now);
    renderCos(d.chiefOfStaff);
    renderSeat('main-seat', d.seats && d.seats.main, false, d.limit && d.limit.accountLabel);
    renderSeat('relay-seat', d.seats && d.seats.relay, !(d.seats && 'relay' in d.seats));
    const hostInfo = renderHost(d.host);
    renderCost(d.costPerRole, d.seats);
    renderTodos(d.todos);
    renderAgents(d.agents);
    renderAlerts(d.alerts, d.sources && d.sources.alerts, now);
    renderResolved(d.alertsResolved);
    renderGuardBlocks(d.guardBlocks, now);
    const at = parseTime(d.updatedAt);
    renderLimit(d.limit, now, at);
    renderSummary(d, hostInfo);
    renderSources(d.sources, at);
    for (const card of document.querySelectorAll('.card[data-sources]')) cardAge(card, d.sources, now);
    markLook();
    byId('updated').textContent = Number.isFinite(at) ? clock(at) : 'unknown';
    tick();
  }

  // Liveness is the collector's write time against the clock, checked every
  // second: a page that keeps loading the same old file must still go red.
  // Old numbers with a fresh heartbeat are a slow cycle, not a stop.
  function tick() {
    const now = Date.now();
    byId('clock').textContent = clock(now);
    const status = byId('status');
    const banner = byId('banner');
    const at = data ? parseTime(data.updatedAt) : NaN;
    let state, text, alert = '';
    if (!data) {
      state = 'unavailable'; text = 'Unavailable';
      alert = 'No collector data: data.js has not loaded. Is the dashboard service installed and running?';
    } else if (!Number.isFinite(at) || at > now) {
      state = 'unavailable'; text = 'Unavailable';
      alert = 'The collector write time is missing or in the future, so freshness cannot be judged.';
    } else if (now - at > STOPPED_MS) {
      const beat = alive ? parseTime(alive.at) : NaN;
      const begun = alive ? parseTime(alive.cycleStartedAt) : NaN;
      if (Number.isFinite(beat) && now - beat <= ALIVE_MS && Number.isFinite(begun) && now - begun > STUCK_CYCLE_MS) {
        state = 'stuck'; text = 'Collector stuck';
        alert = `Collector stuck: the cycle started at ${clock(begun)} (${ago((now - begun) / 1000)} ago) is still running; restart the dashboard service. Every number below is from ${clock(at)}.`;
      } else if (Number.isFinite(beat) && now - beat <= ALIVE_MS) {
        const last = num(alive.lastCycleSec);
        state = 'slow'; text = 'Collector slow';
        alert = `Collector slow: still running, this cycle started ${Number.isFinite(begun) ? `${ago((now - begun) / 1000)} ago` : 'at an unmeasured time'}`
          + ` (last took ${last === null ? 'not measured' : ago(last)}); numbers are from ${clock(at)}.`;
      } else {
        state = 'dead'; text = 'Collector dead';
        alert = `Collector dead: no heartbeat ${Number.isFinite(beat) ? `since ${clock(beat)}` : 'at all'}; restart the dashboard service. Every number below is from ${clock(at)}.`;
      }
    } else {
      // The write time alone hid sections sampled minutes earlier by a collector running behind.
      const oldest = Math.min(...Object.values(view(data).sources || {}).map((s) => parseTime(s && s.status !== 'not-measured' ? s.sampledAt : null)).filter(Number.isFinite));
      state = 'live'; text = `Live, written ${ago((now - at) / 1000)} ago${Number.isFinite(oldest) ? `; oldest sample ${ago((now - oldest) / 1000)} ago` : ''}`;
    }
    // Re-rendered on a state change only: the slow banner's text moves every second.
    const stopped = !data || state === 'live' ? ''
      : state === 'unavailable' ? alert : `${text}: no new data since ${clock(at)}; the list below may be out of date`;
    if (stopped !== collectorAlert) {
      collectorAlert = stopped;
      if (data) { renderAlerts(view(data).alerts, data.sources && data.sources.alerts, now); markLook(); }
    }
    status.dataset.state = state;
    status.textContent = text;
    banner.hidden = !alert;
    banner.textContent = alert;
    banner.dataset.state = state;
    const took = alive ? num(alive.lastCycleSec) : null;
    byId('last-cycle').hidden = took === null;
    byId('last-cycle').textContent = took === null ? '' : `last cycle ${took} s`;
    restartProgress();
  }

  // Issue 294: Restart collector, on this machine's own page only (the host takes it from loopback alone). Progress
  // compares the host's own stamps with the ones held at the click, never this page's clock with the host's.
  const RESTART_IDLE = 'Restart collector';
  const restartBtn = byId('restart');
  let restartWatch = null;
  function restartSay(t) { restartBtn.textContent = t; restartBtn.disabled = t !== RESTART_IDLE; }
  function restartFailed(t) { restartWatch = null; restartSay(t); setTimeout(() => restartSay(RESTART_IDLE), 5000); }
  function restartProgress() {
    if (!restartWatch) return;
    if (!restartWatch.waiting && alive && alive.cycleStartedAt && alive.cycleStartedAt !== restartWatch.cycle) {
      restartWatch.waiting = true; restartSay('waiting for first cycle');
    }
    if (restartWatch.waiting && data && data.updatedAt !== restartWatch.updated) { restartWatch = null; restartSay(RESTART_IDLE); }
  }
  restartBtn.hidden = !LOCAL;
  restartBtn.addEventListener('click', () => {
    if (restartWatch || !window.confirm('Restart the collector? This page reconnects by itself.')) return;
    restartWatch = { cycle: alive ? alive.cycleStartedAt : null, updated: data ? data.updatedAt : null, waiting: false };
    restartSay('restarting...');
    window.fetch('restart', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' })
      .then(loggedIn).then((r) => (r.ok ? null : r.json().then((t) => restartFailed(String(t)), () => restartFailed(`the host answered ${r.status}`))),
        () => restartFailed('the host did not answer'));
  });

  // alive.js is the --loop heartbeat (dashboard.sh). A failed load keeps the
  // last one: its own time ages it out.
  let alive = null;
  let aliveLoad = null;
  // The heartbeat's stamp of the host's view files; the first one seen is taken as this page's own.
  // shortcut: an update landing between this page's load and its first heartbeat is missed until the next
  // update; stamp index.html itself at install if that ever bites.
  let viewStamp = null;
  function loadAlive() {
    if (aliveLoad) return;
    const s = document.createElement('script');
    s.src = `alive.js?${Date.now()}`;
    const end = () => { s.remove(); aliveLoad = null; };
    s.onload = () => {
      end();
      const a = window.DASH_ALIVE;
      if (a && typeof a === 'object') {
        alive = a;
        // New view files on the host: a page left open moves onto them by itself. A reload while a save is
        // unanswered waits for the next heartbeat.
        if (typeof a.view === 'string') { if (viewStamp === null) viewStamp = a.view; else if (a.view !== viewStamp && !sending) window.location.reload(); }
      }
      tick();
    };
    s.onerror = () => { end(); tick(); };
    aliveLoad = s;
    document.head.append(s);
  }

  function settle(s) { s.remove(); if (inflight === s) inflight = null; }
  function load() {
    loadAlive();
    if (inflight) return;
    const s = document.createElement('script');
    s.src = `data.js?${Date.now()}`;
    s.onload = () => {
      settle(s);
      const d = window.DASH;
      byId('refresh-note').hidden = true;
      if (d && typeof d === 'object') { data = d; render(d); openEvents(); } else tick();
    };
    s.onerror = () => {
      settle(s);
      const n = byId('refresh-note');
      n.hidden = false;
      n.textContent = `The refresh at ${clock(Date.now())} could not read data.js; showing the previous snapshot.`;
      tick();
    };
    inflight = s;
    document.head.append(s);
  }

  // The frame every panel shares: a width of 1 to 4 (1 is compact, 2 to 4 also
  // show the .more parts), a height, a place in the order and a hide button.
  // All four are the owner's, kept per browser. The DOM order is the layout (never CSS
  // order), and render only patches cards by id, so a refresh never undoes it.
  // One page, one project: the address names it (index.html?project=<name>), and the bare address goes on to
  // the home project's. The name is only ever compared with the snapshot's own project names and used as a key: in the
  // snapshot, in the layout file, and as a suffix of this browser's keys, so no project reads another's layout.
  const asked = new window.URLSearchParams(window.location.search).get('project');
  const NS = asked === null ? '' : `:${asked}`;
  const ORDER_KEY = `commandeck-dashboard-order${NS}`;
  const SIZES_KEY = `commandeck-dashboard-sizes${NS}`;
  const HEIGHTS_KEY = `commandeck-dashboard-heights${NS}`;
  const HIDDEN_KEY = `commandeck-dashboard-hidden${NS}`;
  const COLLAPSED_KEY = `commandeck-dashboard-collapsed${NS}`;
  const CLOSED_KEY = `commandeck-dashboard-closed${NS}`;
  const BUILDS_KEY = `commandeck-dashboard-builds${NS}`;
  const HEIGHTS =['auto', 'half', 'tall'];
  const grid = q('main.grid');
  const isCard = (el) => Boolean(el) && el.parentElement === grid && el.classList.contains('card');
  const cards = () => [...grid.children].filter(isCard);
  const DEFAULT_ORDER = cards().map((c) => c.id);
  const DEFAULT_SIZE = new Map(cards().map((c) => [c.id, c.dataset.size]));
  // Storage can be refused (privacy modes, some file: pages): the layout still changes, unsaved.
  const store = (fn) => { try { return fn(window.localStorage); } catch (e) { return null; } };
  // One machine, many projects: the collector keeps each under .projects[<name>]
  // and the machine's own readings (limit, host) at the top. The bare address
  // goes to the home project's own, so a layout is kept under its project's
  // name whichever project is home; an address that names no listed project
  // goes back to the bare one. Nothing is saved under a name until the layout
  // file holds it or the snapshot lists it (`listed`, below).
  let project = null;
  function view(d) {
    const all = d.projects && typeof d.projects === 'object' ? d.projects : {};
    const names = Object.keys(all).sort();
    const home = names.includes(d.home) ? d.home : (names.length ? names[0] : null);
    const stray = asked === null ? home !== null : !names.includes(asked);
    if (stray) window.location.replace(asked === null ? `index.html?project=${encodeURIComponent(home)}` : 'index.html');
    project = stray ? home : asked;
    const nav = byId('projects');
    if (names.join('\n') !== [...nav.children].map((a) => a.textContent).join('\n')) {
      put(nav, names.map((n) => {
        const a = h('a', null, n);
        a.setAttribute('href', `index.html?project=${encodeURIComponent(n)}`);
        if (n === project) a.setAttribute('aria-current', 'page');
        return a;
      }));
    }
    if (!listed && !stray && asked !== null) { listed = true; if (store((s) => s.getItem(UNSAVED_KEY)) !== null) sendLayout(); }
    const p = (project !== null && all[project]) || {};
    // An alert a project raised is that project's; one with no project is the machine's and shows on every page.
    const mine = (list) => (Array.isArray(list) ? list.filter((a) => !a || a.project === undefined || a.project === null || a.project === project) : list);
    return { ...p, ...d, alerts: mine(d.alerts), alertsResolved: mine(d.alertsResolved), sources: { ...(d.sources || {}), ...(p.sources || {}) } };
  }
  // The layout follows the owner to every PC: layout.js, served by the dashboard's host, is the copy that
  // wins at load, and every change sends the whole layout back to that host (dashboard_serve.py checks and writes it).
  // The file holds each project's layout in its own slot, projects[<name>], each with its own save number.
  // Each value is still read through restore()'s own checks, so the host's file is trusted no more than this browser's.
  // shortcut: a page already open does not pick up another page's change until its own next change is refused and
  // merged (sendLayout); re-read layout.js on each refresh if a phone beside a PC needs it sooner.
  const LAYOUT = { order: ORDER_KEY, sizes: SIZES_KEY, heights: HEIGHTS_KEY, hidden: HIDDEN_KEY, closed: CLOSED_KEY, collapsed: COLLAPSED_KEY, builds: BUILDS_KEY };
  const UNSAVED_KEY = `commandeck-dashboard-unsaved${NS}`;
  const plain = (v) => (v && typeof v === 'object' && !Array.isArray(v) ? v : {});
  const file = window.DASH_LAYOUT;
  const slots = plain(plain(file).projects);
  // Limit: a layout saved before projects had their own (unnamed, at the top of the file) is not carried over;
  // a project the file holds no slot for starts from the default layout, so nothing crosses projects.
  const host = asked !== null && Object.prototype.hasOwnProperty.call(slots, asked) ? slots[asked] : undefined;
  let listed = host !== undefined;
  const held = host && typeof host === 'object' && !Array.isArray(host) ? host : {};
  const has = (k) => Object.prototype.hasOwnProperty.call(held, k);
  // The host numbers each save. A save names the number of the layout it was made over, and the host refuses it
  // when it holds another (dashboard_serve.py), so a save that lands late cannot undo a newer one.
  // The number is this project's slot's own, so a save on another project's page refuses none on this one.
  let rev = Number.isSafeInteger(held.rev) && held.rev > 0 ? held.rev : 0;
  // The host layout this page's changes are made over: what differs from it is this page's own (merge).
  let base = held;
  // This browser's own copy wins over the host's in two cases, and is then sent up: a change the host never
  // confirmed (a reload while its save was unanswered), and a host that holds no layout and no number while
  // this browser holds one. A numbered empty layout is another PC's Reset layout, and wins.
  // The mark holds the number of the host layout the unconfirmed change was made over. A host two or more saves
  // past it was changed from elsewhere since, and wins; one save past it can be that change itself.
  // shortcut: one save from another PC inside that window is still overwritten; give the host save ids if it happens.
  const mark = store((s) => s.getItem(UNSAVED_KEY));
  const mine = (mark !== null && [0, 1].includes(rev - Number(mark)))
    || (rev === 0 && !Object.keys(LAYOUT).some(has) && Object.values(LAYOUT).some((key) => store((s) => s.getItem(key)) !== null));
  const mem = new Map();
  if (held === host && !mine) {
    store((s) => s.removeItem(UNSAVED_KEY));
    for (const [k, key] of Object.entries(LAYOUT)) {
      const v = has(k) ? host[k] : null;
      mem.set(key, v);
      // This browser's copy follows the host's, so a change replayed after a reload goes over the layout it was
      // made on, never over values this browser saved long before.
      store((s) => (v === null ? s.removeItem(key) : s.setItem(key, JSON.stringify(v))));
    }
  }
  // The bare address is on its way to the home project's: it reads no layout, the host's or this browser's.
  const saved = (key) => (mem.has(key) ? mem.get(key) : asked === null ? null : store((s) => JSON.parse(s.getItem(key))));
  // One save in flight at a time: a change made meanwhile is sent when the answer comes, as the whole layout it
  // is by then. The unsaved mark stays in this browser until the host has confirmed the newest layout.
  let sending = false;
  let unsent = false;
  const sendLayout = () => {
    if (!/^https?:$/.test(window.location.protocol)) return;
    store((s) => s.setItem(UNSAVED_KEY, String(rev)));
    if (!listed) return;
    if (sending) { unsent = true; return; }
    sending = true;
    const body = { rev, project: asked };
    for (const [k, key] of Object.entries(LAYOUT)) { const v = saved(key); if (v !== null && v !== undefined) body[k] = v; }
    // Only builds on a list this page has read are sent as cleared, and none before the first list: the host
    // keeps what it holds (dashboard_serve.py), and a tab's old names never reach it.
    // shortcut: with no finished-builds record at all an owed clear is never sent and this browser's copy keeps
    // winning on load; upgrade if a record can go missing in normal use.
    if (listedBuilds && Array.isArray(body.closed)) body.closed = body.closed.filter((x) => listedBuilds.includes(x));
    else { owed = owed || (mine && closedBuilds().length > 0); delete body.closed; }
    const done = (ok, again) => {
      sending = false;
      if (ok) { rev += 1; base = body; }
      if (unsent || again) { unsent = false; sendLayout(); } else if (ok && !owed) store((s) => s.removeItem(UNSAVED_KEY));
    };
    // 409: another page changed the layout since this one read it (issue 211: a phone beside a PC). The page re-reads
    // layout.js, merges it (merge, below) and goes again over the host's number; the save stays in flight meanwhile.
    // A read that fails, or one at the refused number, leaves the change unsaved for the next change or load.
    const answer = (res) => {
      if (res.status !== 409) return done(res.ok === true);
      const s = document.createElement('script');
      s.src = `layout.js?${Date.now()}`;
      s.onload = () => { s.remove(); const was = rev; merge(plain(plain(plain(window.DASH_LAYOUT).projects)[asked])); done(false, rev !== was); };
      s.onerror = () => { s.remove(); done(false); };
      document.head.append(s);
    };
    window.fetch('layout', { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }).then(loggedIn).then(answer).catch(() => done(false));
  };
  const keep = (key, value) => { mem.set(key, value); store((s) => s.setItem(key, JSON.stringify(value))); sendLayout(); };
  const saveOrder = () => keep(ORDER_KEY, cards().map((c) => c.id));
  const closedBuilds = () => { const v = saved(CLOSED_KEY); return Array.isArray(v) ? v.filter((x) => typeof x === 'string') : []; };
  // Each build the owner folded (true) or unfolded (false), by the key block() gives it; a value not true or false is no choice.
  const buildFolds = () => { const v = plain(saved(BUILDS_KEY)); return Object.fromEntries(Object.entries(v).filter(([, x]) => typeof x === 'boolean')); };
  // The host's layout over this page's, key by key: a key this page did not change takes the host's value. In a
  // map (widths, heights, folds) only the panels this page changed keep its value, so another page's Reset layout
  // stands for the rest; a width or height still at its default is no change. Cleared builds join (a clear only adds).
  const same = (x, y) => JSON.stringify(x) === JSON.stringify(y);
  const field = (o, k) => (Object.prototype.hasOwnProperty.call(o, k) ? o[k] : null);
  const UNSET = { sizes: (id) => Number(DEFAULT_SIZE.get(id)), heights: () => 'auto' };
  function merge(l) {
    for (const [k, key] of Object.entries(LAYOUT)) {
      const own = saved(key), was = field(base, k), theirs = field(l, k);
      let v = theirs;
      if (k === 'closed') {
        const both = [...new Set([].concat(Array.isArray(theirs) ? theirs : [], closedBuilds()))];
        v = both.length ? both : null;
      } else if ((k === 'collapsed' || k === 'hidden') && !same(own, was)) {
        // A set of ids (issue 217): the host's, plus what this page added, less what it took out.
        const ids = (x) => (Array.isArray(x) ? x : []), mineNow = ids(own), mineWas = ids(was);
        v = [...new Set(ids(theirs).filter((id) => mineNow.includes(id) || !mineWas.includes(id)).concat(mineNow.filter((id) => !mineWas.includes(id))))];
      } else if (plain(own) === own) {
        const changed = Object.entries(own).filter(([id, x]) => !same(x, field(plain(was), id) ?? (UNSET[k] ? UNSET[k](id) : null)));
        if (changed.length) v = { ...plain(theirs), ...Object.fromEntries(changed) };
      } else if (!same(own, was)) v = own;
      mem.set(key, v);
      store((s) => (v === null ? s.removeItem(key) : s.setItem(key, JSON.stringify(v))));
    }
    base = l;
    rev = Number.isSafeInteger(l.rev) && l.rev > 0 ? l.rev : 0;
    restore();
    if (data) render(data);
  }
  // Cleared builds are only ever added to: where this browser's copy won above, the host's cleared builds join it.
  if (mine && Array.isArray(held.closed)) {
    const v = [...new Set(held.closed.filter((x) => typeof x === 'string').concat(closedBuilds()))];
    mem.set(CLOSED_KEY, v);
    store((s) => s.setItem(CLOSED_KEY, JSON.stringify(v)));
  }
  // Saved ids first, in their order; a card the saved order does not know goes last.
  function arrange(ids) {
    const map = new Map(cards().map((c) => [c.id, c]));
    const first = ids.filter((id, i) => map.has(id) && ids.indexOf(id) === i);
    grid.append(...first.map((id) => map.get(id)), ...[...map.values()].filter((c) => !first.includes(c.id)));
  }
  function setSize(card, n) {
    card.dataset.size = String(n);
    for (const b of card.querySelectorAll('.sz button')) {
      const on = b.dataset.s === String(n);
      b.classList.toggle('on', on);
      b.setAttribute('aria-pressed', String(on));
    }
  }
  // A height is a preset or the whole number of pixels the panel was dragged to; dashboard_server.py holds
  // the same two bounds. The floor keeps a panel tall enough to grab again.
  const PX_MIN = 60, PX_MAX = 4000;
  const isPx = (v) => Number.isInteger(v) && v >= PX_MIN && v <= PX_MAX;
  function setHeight(card, v) {
    if (v === 'auto' || isPx(v)) delete card.dataset.height; else card.dataset.height = v;
    card.style.height = isPx(v) ? `${v}px` : '';
    q('button[data-tall]', card).textContent = `Height: ${isPx(v) ? `${v} px` : v}`;
  }
  const heightOf = (c) => { const n = parseFloat(c.style.height); return Number.isFinite(n) ? Math.min(PX_MAX, Math.max(PX_MIN, Math.round(n))) : c.dataset.height || 'auto'; };
  // Alerts hides like the rest: the top tile still counts the alerts, and an alert's link brings its panel back.
  const hiddenIds = () => cards().filter((c) => c.hidden).map((c) => c.id);
  function setHidden(ids) {
    for (const c of cards()) c.hidden = ids.includes(c.id);
    const n = hiddenIds().length;
    byId('unhide').hidden = n === 0;
    byId('unhide').textContent = `Show hidden (${n})`;
  }
  // A saved layout is read value by value: an unknown id or a value out of range falls back to the default.
  function restore() {
    const order = saved(ORDER_KEY), sizes = saved(SIZES_KEY), heights = saved(HEIGHTS_KEY), hidden = saved(HIDDEN_KEY);
    arrange(Array.isArray(order) && order.every((id) => typeof id === 'string') ? order : DEFAULT_ORDER);
    const own = (o, id) => (o && typeof o === 'object' && Object.prototype.hasOwnProperty.call(o, id) ? o[id] : null);
    for (const c of cards()) {
      const s = own(sizes, c.id), t = own(heights, c.id);
      setSize(c, Number.isInteger(s) && s >= 1 && s <= 4 ? s : DEFAULT_SIZE.get(c.id));
      setHeight(c, HEIGHTS.includes(t) || isPx(t) ? t : 'auto');
    }
    setHidden(Array.isArray(hidden) ? hidden : []);
    // A fold merged from another page shows here too, or this page's next fold, read off its sections, undoes it.
    const folded = saved(COLLAPSED_KEY);
    for (const d of document.querySelectorAll('details[data-fold]')) d.open = !(Array.isArray(folded) && folded.includes(d.id));
  }
  const saveMap = (key, read) => keep(key, Object.fromEntries(cards().map((c) => [c.id, read(c)])));
  const titles = new Map();
  for (const card of cards()) {
    const head = q('.card-head', card);
    const title = q('h2', head);
    const name = title.textContent;
    titles.set(card.id, name);
    title.setAttribute('draggable', 'true');
    title.prepend(h('span', 'grip', '⋮⋮'));
    q('.grip', title).setAttribute('aria-hidden', 'true');
    const tools = h('span', 'tools');
    const btn = (text, label) => { const b = h('button', null, text); b.type = 'button'; b.setAttribute('aria-label', label); return b; };
    const sz = h('span', 'sz');
    for (const n of [1, 2, 3, 4]) { const b = btn(String(n), `${name}: width ${n} of 4`); b.dataset.s = String(n); sz.append(b); }
    const tall = btn('', `${name}: change height`);
    tall.dataset.tall = '';
    const moves = h('span', 'move');
    for (const dir of ['earlier', 'later']) {
      const b = btn(dir === 'earlier' ? 'Earlier' : 'Later', `Move ${name} ${dir}`);
      b.dataset.move = dir;
      moves.append(b);
    }
    const hide = btn('Hide', `Hide ${name}`);
    hide.dataset.hide = '';
    tools.append(moves, sz, tall, hide);
    head.append(tools);
  }
  grid.addEventListener('click', (e) => {
    const b = e.target.closest('.card-head button');
    if (!b) return;
    const card = b.closest('.card');
    if (b.dataset.s) { setSize(card, Number(b.dataset.s)); saveMap(SIZES_KEY, (c) => Number(c.dataset.size)); }
    else if ('tall' in b.dataset) {
      setHeight(card, HEIGHTS[(HEIGHTS.indexOf(card.dataset.height || 'auto') + 1) % HEIGHTS.length]);
      saveMap(HEIGHTS_KEY, heightOf);
    } else if ('hide' in b.dataset) { setHidden(hiddenIds().concat(card.id)); keep(HIDDEN_KEY, hiddenIds()); }
    else if (b.dataset.move) {
      const earlier = b.dataset.move === 'earlier';
      const next = earlier ? card.previousElementSibling : card.nextElementSibling;
      if (!isCard(next)) return;
      if (earlier) next.before(card); else next.after(card);
      b.focus(); // moving the card blurs its button
      saveOrder();
    }
  });
  // The browser's own resize handle (CSS resize) writes the dragged height to the panel's style and raises no event
  // of its own, so the end of any drag is where a height that is not the saved one is found and kept.
  document.addEventListener('mouseup', () => {
    const was = saved(HEIGHTS_KEY);
    const moved = cards().filter((c) => c.style.height && heightOf(c) !== (was && typeof was === 'object' ? was[c.id] : undefined));
    if (!moved.length) return;
    for (const c of moved) setHeight(c, heightOf(c));
    saveMap(HEIGHTS_KEY, heightOf);
  });
  // Only the title drags, so the controls in a card keep their own clicks.
  let dragged = null;
  const dropTarget = (e) => {
    const c = e.target.closest ? e.target.closest('.card') : null;
    return dragged && isCard(c) && c !== dragged ? c : null;
  };
  grid.addEventListener('dragstart', (e) => {
    if (!e.target.matches || !e.target.matches('.card-head h2[draggable]')) return;
    dragged = e.target.closest('.card');
    dragged.classList.add('dragging');
    if (e.dataTransfer) { e.dataTransfer.effectAllowed = 'move'; e.dataTransfer.setData('text/plain', dragged.id); }
  });
  grid.addEventListener('dragover', (e) => { if (dropTarget(e)) e.preventDefault(); });
  grid.addEventListener('drop', (e) => {
    const t = dropTarget(e);
    if (!t) return;
    e.preventDefault();
    const all = cards();
    if (all.indexOf(dragged) < all.indexOf(t)) t.after(dragged); else t.before(dragged);
    saveOrder();
  });
  grid.addEventListener('dragend', () => { if (dragged) dragged.classList.remove('dragging'); dragged = null; });
  // Clearing a finished build is the owner's own tidy-up, not layout: Reset layout leaves it cleared. The host keeps
  // the list (dashboard_serve.py); this page only adds to its copy.
  // The host takes a layout id only (dashboard_serve.py ID): a build whose unit name is longer still folds, unkept.
  const LAYOUT_ID = /^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$/;
  byId('builds-list').addEventListener('click', (e) => {
    const f = e.target.closest('button[data-fold]');
    if (f) {
      const el = f.closest('.build'), shut = !el.classList.contains('shut');
      setFold(el, f, shut);
      const kept = Object.entries(buildFolds()).filter(([k]) => !foldScope || foldScope.includes(k));
      if (LAYOUT_ID.test(f.dataset.fold)) keep(BUILDS_KEY, Object.fromEntries([...kept.filter(([k]) => k !== f.dataset.fold), [f.dataset.fold, shut]]));
      return;
    }
    const b = e.target.closest('button[data-close]');
    if (!b) return;
    keep(CLOSED_KEY, [...new Set(closedBuilds().concat(b.dataset.close))]);
    b.closest('.build').remove();
  });
  byId('unhide').addEventListener('click', () => { setHidden([]); keep(HIDDEN_KEY, []); });
  byId('reset-layout').addEventListener('click', () => {
    for (const k of [ORDER_KEY, SIZES_KEY, HEIGHTS_KEY, HIDDEN_KEY]) { mem.set(k, null); store((s) => s.removeItem(k)); }
    restore();
    sendLayout();
  });
  // Needs a look: only the panels render marked stay. Not remembered: a filter
  // left on would hide panels on the next visit with nothing on screen to say why.
  const look = byId('needs-look');
  look.addEventListener('change', () => document.body.classList.toggle('look-only', look.checked));
  // A tile or an alert jumps to its panel: one the owner hid or filtered out comes back first.
  document.addEventListener('click', (e) => {
    const a = e.target.closest ? e.target.closest('a[href^="#"]') : null;
    const card = a && byId(a.getAttribute('href').slice(1));
    if (!isCard(card)) return;
    if (card.hidden) { setHidden(hiddenIds().filter((id) => id !== card.id)); keep(HIDDEN_KEY, hiddenIds()); }
    if (look.checked && !('look' in card.dataset)) { look.checked = false; document.body.classList.remove('look-only'); }
    // On a phone only the current tab's panels show: the tab holding this one, or the panel alone as More shows it.
    const tab = Object.keys(TABS).find((t) => TABS[t].includes(card.id));
    showTab(tab || 'more', tab ? undefined : card.id);
  });
  restore();
  if (mine) sendLayout();

  // issue 211: under 760 px a bottom tab bar picks the panels shown (app.css hides the rest); wider, the bar is
  // hidden and every panel shows as before. More offers every other panel not hidden, as tiles.
  const TABS = { home: ['main-chain'], units: ['units'], builds: ['builds'], tests: ['tests'], alerts: ['alerts'], you: ['needs'] };
  const tabBar = byId('tabs'), sheet = byId('more-sheet');
  function showTab(tab, one) {
    document.body.dataset.tab = tab;
    for (const c of cards()) c.classList.toggle('tab-on', one ? c.id === one : TABS[tab].includes(c.id));
    for (const b of tabBar.querySelectorAll('button')) { if (b.dataset.tab === tab) b.setAttribute('aria-current', 'page'); else b.removeAttribute('aria-current'); }
  }
  const closeSheet = () => { sheet.hidden = true; q('[data-tab="more"]', tabBar).focus(); };
  tabBar.addEventListener('click', (e) => {
    const b = e.target.closest('button[data-tab]');
    if (!b) return;
    if (b.dataset.tab !== 'more') { sheet.hidden = true; showTab(b.dataset.tab); return; }
    const onTabs = Object.values(TABS).flat();
    put(byId('more-tiles'), cards().filter((c) => !c.hidden && !('absent' in c.dataset) && !onTabs.includes(c.id)).map((c) => {
      const t = h('button', null, titles.get(c.id));
      t.type = 'button';
      t.dataset.card = c.id;
      return t;
    }));
    sheet.hidden = false;
    sheet.focus();
  });
  sheet.addEventListener('click', (e) => {
    if (e.target.closest('[data-scrim]')) { closeSheet(); return; }
    const t = e.target.closest('button[data-card]');
    if (!t) return;
    sheet.hidden = true;
    showTab('more', t.dataset.card);
  });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !sheet.hidden) closeSheet(); });
  showTab('home');
  byId('unit-steps').addEventListener('click', (e) => {
    const b = e.target.closest('button[data-step]');
    if (!b) return;
    unitStep = b.dataset.step;
    applyStep();
  });

  // The ids of the details[data-fold] sections the owner folded, kept per browser;
  // open by default; restore() applies them. Render only sets hidden, never open, so a refresh keeps the fold.
  const folds =[...document.querySelectorAll('details[data-fold]')];
  for (const d of folds) {
    // A browser fires toggle at load for each fold the markup opens: only a set of folds other than the saved
    // one is a change, or every page load would send a layout.
    d.addEventListener('toggle', () => {
      const now = folds.filter((f) => !f.open).map((f) => f.id), was = saved(COLLAPSED_KEY);
      if (now.join() !== (Array.isArray(was) ? was : []).join()) keep(COLLAPSED_KEY, now);
    });
  }

  tick();
  load();
  setInterval(tick, 1000);
  setInterval(load, REFRESH_MS);
}());

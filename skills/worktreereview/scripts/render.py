#!/usr/bin/env python3
"""Render collect.py's result.json plus the reviewer's own words (notes.json) as one HTML page.

Usage: render.py <result.json> [<notes.json>] <out.html>

Without notes.json the page is fully automatic: the summary and "What the numbers say"
are computed. notes.json adds the reviewer's judgement; every key is optional:
  title, summary, stage_notes {stage code: text}, pass_findings {pass number: text},
  lessons [{title, points [text]}], not_measured [text], method [text],
  shrink_review [{item, issue | fix}]: each "Where it could shrink" item, by its bold title
Text may use **bold** and `code`; everything else is escaped.
"""
import collections
import html
import json
import os
import re
import statistics
import sys
from datetime import datetime

R = json.load(open(sys.argv[1]))
N = json.load(open(sys.argv[2])) if len(sys.argv) > 3 else {}
OUT = sys.argv[-1]
def took(x):
    """A stage's, pass's or idle gap's time without the time cut as waiting on the owner."""
    return x['end'] - x['start'] - x.get('cut_s', 0)


TOTAL = max(1, took(R))  # a run cut from end to end still renders
ROLES = (('builder', 'the agent'), ('advisor', 'advisor'), ('helper', 'helpers'), ('codex', 'Codex reviewer'))
# Each clock label, its colour and which side of the line it is on: Claude's servers, a helper agent, or neither.
CLOCK = [('claude', 'Claude requests: thinking and writing', '#1d4ed8', 'claude'), ('compaction', 'Context compaction', '#6b7280', 'claude'),
         ('helper', 'Waiting on a helper agent', '#0e7490', 'helper'),
         ('tests', 'Running tests and timing runs', '#c2410c', 'off'), ('idle_tests', 'Idle, waiting on a background test', '#ea580c', 'off'),
         ('idle_job', 'Idle, waiting on another background job', '#b45309', 'off'), ('idle', 'Idle, nothing logged as running', '#a16207', 'off'),
         ('idle_elsewhere', 'Idle, waiting on a review run outside this session', '#ca8a04', 'off'),
         ('idle_down', 'Idle, the review tool was down', '#854d0e', 'off'),
         ('commands', 'Other commands', '#0f766e', 'off'), ('files', 'Reading and editing files', '#0d9488', 'off'),
         ('tools', 'Other tools', '#14b8a6', 'off'), ('hooks', 'Hooks before and after tool calls', '#be185d', 'off'),
         ('hooks_stop', 'Hooks at the end of a turn', '#db2777', 'off'), ('codex', 'Waiting on the Codex review (OpenAI servers)', '#7c3aed', 'off'),
         ('gap', 'Between steps: the client itself', '#64748b', 'off'), ('none', 'No agent session open', '#9ca3af', 'off')]
GROUPS = (('claude', "On Claude's servers"), ('helper', 'Helper agents (their own Claude requests and tools)'), ('off', "Not on Claude's servers"))


def hm(sec):
    sec = int(round(sec))
    return f'{sec // 60}:{sec % 60:02d}'


def dur(sec):
    m = round(sec / 60)
    return f'{m // 60} h {m % 60} min' if m >= 60 else f'{m} min'


def sec(x):
    """A short span: hundredths under ten seconds, min:sec past a minute."""
    return f'{x:.2f} s' if x < 10 else f'{x:.0f} s' if x < 60 else hm(x)


def med(xs):
    xs = list(xs)
    return statistics.median(xs) if xs else 0


def p90(xs):
    xs = sorted(xs)
    return xs[-(-9 * len(xs) // 10) - 1] if xs else 0


def td(value, shown=None, cls='r'):
    """A cell that sorts by its raw value."""
    return f'<td class="{cls}" data-v="{html.escape(str(value))}">{value if shown is None else shown}</td>'


def table(heads, rows, sortable=True):
    """heads: column names, a leading > right-aligns. Sortable tables sort on a header click."""
    head = ''.join(f'<th class="r">{h[1:]}</th>' if h.startswith('>') else f'<th>{h}</th>' for h in heads)
    return f'<table{" class=sort" if sortable else ""}><tr>{head}</tr>{"".join(rows)}</table>'


def n(x):
    return f'{int(round(x)):,}'


def hit(c):
    """Share of a prompt read from the cache: cache read / (uncached input + cache write + cache read).

    A dash, never 0%, when a count is unknown, when a stage holds a request
    whose counts are unknown ('uncounted'), or when there was no input at all.
    """
    parts = [c.get(k) for k in ('in', 'cw', 'cr')]
    return '&ndash;' if c.get('uncounted') or None in parts or not sum(parts) else f'{100 * parts[2] / sum(parts):.0f}%'


def M(x):
    return f'{x / 1e6:.2f}M' if x >= 1e6 else f'{x / 1e3:.0f}K' if x >= 1e3 else str(int(x))


def local(t, fmt='%-I:%M %p'):
    return datetime.fromtimestamp(t).astimezone().strftime(fmt)


def txt(s):
    s = html.escape(str(s))
    s = re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', s)
    return re.sub(r'`(.+?)`', r'<code>\1</code>', s)


def nice(model):
    """claude-opus-5-5 -> Opus 5.5; anything else is shown as logged."""
    m = re.fullmatch(r'claude-([a-z]+)-(\d+)-(\d+)', str(model))
    return f'{m.group(1).capitalize()} {m.group(2)}.{m.group(3)}' if m else str(model)


def allof(c):
    return sum(c.get(k, 0) for k in ('in', 'cw', 'cr', 'out'))


def money(c):
    """List price of a token bucket, or why there is none."""
    if not c.get('calls'):
        return '&ndash;'
    if not c.get('usd'):
        return '<span class="tag">no list price on file</span>'
    return f'${c["usd"]:,.2f}' + (' <span class="tag">+ unpriced calls</span>' if c.get('unpriced') else '')


def ul(items):
    return '<ul>' + ''.join(f'<li>{txt(x)}</li>' for x in items) + '</ul>'


AGENT = ' and '.join(nice(m) for m in R['builder_models']) or 'the agent'
MODEL = {'builder': AGENT,
         'advisor': ', '.join(sorted({nice(k[6:]) for s in R['stages'] for k in s['advisor'] if k.startswith('model:')})),
         'helper': ', '.join(sorted({nice(h['model']) for h in R['helpers']})),
         'codex': ', '.join(sorted({f'{p["model"]} at {p["effort"]} effort' for p in R['passes']}))}

clock = R['clock']
SIDE = {g: sum(clock.get(k, 0) for k, _, _, side in CLOCK if side == g) for g, _ in GROUPS}
bars = ''.join(
    f'<h4>{title}: {dur(SIDE[g])} &middot; {100 * SIDE[g] / TOTAL:.0f}% of the run</h4>' + ''.join(
        f'<div class="barrow"><div>{name}</div><div class="track"><div class="bar" style="width:{100 * clock[k] / TOTAL:.1f}%;background:{col}"></div></div>'
        f'<div class="r"><b>{hm(clock[k])}</b> &middot; {100 * clock[k] / TOTAL:.1f}%</div></div>'
        for k, name, col, side in sorted(CLOCK, key=lambda x: -clock.get(x[0], 0)) if side == g and clock.get(k, 0) >= 5)
    for g, title in GROUPS if SIDE[g] >= 5)

T = R['totals']
priced = sum(T[k].get('usd', 0) for k, _ in ROLES)
rows, drill = [], []
for s in R['stages']:
    b = s['builder']
    cost = sum(s[k].get('usd', 0) for k, _ in ROLES)
    other = [f'{MODEL[k]} {label}: {M(allof(s[k]))} tokens' + (f', ${s[k]["usd"]:,.2f}' if s[k].get('usd') else ', no list price')
             for k, label in ROLES[1:] if s[k].get('calls')]
    note = N.get('stage_notes', {}).get(s['code'], '')
    rows.append(f'<tr class="{s["kind"]}"><td><b>{s["code"]}. {txt(s["name"])}</b><div class="what">{txt(note)}</div></td><td class="r">{local(s["start"])}</td>'
                f'<td class="r"><b>{hm(took(s))}</b></td><td class="r">{b.get("calls", 0)}</td><td class="r">{M(b.get("cr", 0))}</td>'
                f'<td class="r">{M(b.get("cw", 0))}</td><td class="r hit">{hit(b)}</td><td class="r">{M(b.get("out", 0))}</td><td class="r"><b>${cost:,.2f}</b></td>'
                f'<td>{"<br>".join(txt(o) for o in other) or "&ndash;"}</td></tr>')

    # Drilldown: where this stage's own minutes and dollars went, and what the agent did in it.
    d, span = s['detail'], max(1, took(s))
    mini = ''.join(f'<tr><td>{name}</td><td class="r">{hm(s["clock"][k])}</td><td class="r">{100 * s["clock"][k] / span:.0f}%</td></tr>'
                   for k, name, _, _ in sorted(CLOCK, key=lambda x: -s['clock'].get(x[0], 0)) if s['clock'].get(k, 0) >= 2)
    costs = ''.join(f'<tr><td>{txt(MODEL[k])} <span class="tag">{label}</span></td><td class="r">{s[k].get("calls", 0)}</td><td class="r">{M(allof(s[k]))}</td><td class="r">{money(s[k])}</td></tr>'
                    for k, label in ROLES if s[k].get('calls'))
    cmds = ''.join(f'<tr><td class="r">{local(c["start"], "%-I:%M:%S")}</td><td class="r">{hm(c["seconds"])}</td><td>{txt(c["what"])}'
                   f'{" <span class=tag>background</span>" if c["background"] else ""}</td><td>{txt(c["outcome"])}</td></tr>' for c in d['commands'])
    facts = [f'Average context per call {n(s["context"]["mean"])} tokens, largest {n(s["context"]["peak"])}.'] if b.get('calls') else []
    if d['edits']:
        facts.append('Files edited: ' + ', '.join(f'`{f}` ({c})' for f, c in d['edits'].items()) + '.')
    if d['blocked']:
        facts.append('Tool calls a guard refused, by hook and reason: ' + '; '.join(f'{k} ({v})' for k, v in d['blocked'].items()) + '.')
    notes = ''.join(f'<li><span class="tag">{local(t, "%-I:%M:%S")}</span> {txt(text)}</li>' for t, text in d['notes'])
    drill.append(
        f'<details><summary><b>{s["code"]}. {txt(s["name"])}</b> &middot; {hm(span)} &middot; ${cost:,.2f}</summary><div class="cols">'
        f'<div><h4>Where the time went</h4><table>{mini}</table></div>'
        f'<div><h4>Tokens and list price by model</h4><table><tr><th>Model</th><th class="r">Calls</th><th class="r">Tokens</th><th class="r">Cost</th></tr>{costs}</table></div></div>'
        + (f'<h4>Longest commands</h4><table><tr><th class="r">At</th><th class="r">Took</th><th>What</th><th>Result</th></tr>{cmds}</table>' if cmds else '')
        + (ul(facts) if facts else '')
        + (f'<h4>The agent\'s own notes</h4><ul>{notes}</ul>' if notes else '') + '</details>')

mrows, grand, cached = [], 0, 0
for k, label in ROLES:
    c = T[k]
    if not c.get('calls'):
        continue
    grand += allof(c)
    cached += c.get('cr', 0)
    mrows.append(f'<tr><td><b>{txt(MODEL[k])}</b><div class="what">{label}</div></td><td class="r">{n(c.get("calls", 0))}</td><td class="r">{n(c.get("in", 0))}</td>'
                 f'<td class="r">{n(c.get("cw", 0))}</td><td class="r">{n(c.get("cr", 0))}</td><td class="r">{n(c.get("out", 0))}</td>'
                 f'<td class="r"><b>{n(allof(c))}</b></td><td class="r"><b>{money(c)}</b></td></tr>')
unpriced = [MODEL[k] for k, _ in ROLES if T[k].get('calls') and not T[k].get('usd')]
# Dollars priced by the table's estimate, said in the dashboard's own words.
estimated = sum(T[k].get('est') or 0 for k, _ in ROLES)
tiered = sum(T[k].get('tier') or 0 for k, _ in ROLES)

prows = []
for p in R['passes']:
    u = p['usage']
    finding = N.get('pass_findings', {}).get(str(p['n'])) or re.split(r'\n\s*\n', p['message'].strip())[0][:260]
    # Every finding line, however long the pass's text: the one-line summary above cannot hold them.
    every = re.findall(r'^\s*(?:[-*]\s*)?(\[P[0-3]\].*)$', p['message'], re.M)
    cls = 'go' if p['verdict'] == 'GO' else 'nogo'
    prows.append(f'<tr><td class="r">{p["n"]}</td><td>{p["kind"]}</td><td class="r">{hm(took(p))}</td><td class="r">{n(u.get("input_tokens", 0))}</td>'
                 f'<td class="r">{100 * u.get("cached_input_tokens", 0) / max(1, u.get("input_tokens", 0)):.0f}%</td><td class="r">{n(u.get("output_tokens", 0))}</td>'
                 f'<td class="r">{p["threads"]}</td><td><span class="{cls}">{p["verdict"]}</span> {p["findings"] or ""}</td><td>{txt(finding)}'
                 + (f'<details><summary>All {len(every)} findings</summary>{ul(every)}</details>' if every else '') + '</td></tr>')
if R.get('lines_changed') is not None:
    prows.append(f'<tr><td></td><td colspan="8">Lines changed by the build: {n(R["lines_changed"])}</td></tr>')
if R.get('closing_pass'):
    prows.append(f'<tr><td></td><td colspan="8">Closing pass: {txt(R["closing_pass"])}</td></tr>')

lessons = ''.join(f'<div class="lesson"><h3>L{i}. {txt(l["title"])}</h3>{ul(l["points"])}</div>' for i, l in enumerate(N.get('lessons', []), 1))
lessons = f'<h2>What I make of it</h2>{lessons}' if lessons else ''
# The rung each batch item was built at, as the Builder's evidence file records it (review.py).
# A missing rung is said, never left blank: a blank cell reads as "none needed".
NOREC = 'Not recorded'
rung_rows = [f'<tr><td class="r">{r["item"]}</td><td>{txt(r["issue"])}</td><td class="r">{txt(r["rung"] or NOREC)}</td><td>{txt(r["lazier"] or NOREC)}</td></tr>'
             for r in R.get('rungs') or []]
rungs_html = ('<h2>Rung per batch item</h2><p class="tag">The rest of this review measures by stage, not by item, so this is one table for the whole batch. '
              'The rung is the one the evidence file records for the item, never the one the brief planned.</p>'
              + (table(['>Item', 'Issue', '>Rung', 'Lazier option'], rung_rows, sortable=False) if rung_rows
                 else f'<div class="box">{NOREC}: no numbered batch item was found in the brief.</div>'))

# What code can state without judgement: the same findings on every run, from the numbers alone.
names = {k: name for k, name, _, _ in CLOCK}
top = sorted(((v, k) for k, v in clock.items()), reverse=True)[:2]
dearest = max(R['stages'], key=lambda s: sum(s[k].get('usd', 0) for k, _ in ROLES))
fixes = [s for s in R['stages'] if s['kind'] == 'fix']
slow = max((c for s in R['stages'] for c in s['detail']['commands'] if c['kind'] == 'tests'), key=lambda c: c['seconds'], default=None)
says = ['Largest slices of the clock: ' + ' and '.join(f'{names[k].lower()} ({dur(v)}, {100 * v / TOTAL:.0f}%)' for v, k in top) + '.']
if slow:
    says.append(f'Longest single test command: "{slow["what"]}", {hm(slow["seconds"])}' + (f', result {slow["outcome"]}' if slow['outcome'] else '') + '.')
if R['passes']:
    says.append(f'{len(R["passes"])} Codex passes took {dur(sum(took(p) for p in R["passes"]))}: '
                + ', '.join(f'pass {p["n"]} {p["verdict"]} with {p["findings"]} finding(s)' for p in R['passes'])
                + (f'; closing pass: {R["closing_pass"]}' if R.get('closing_pass') else '') + '.')
if fixes:
    says.append(f'Fixing between passes took {dur(sum(took(s) for s in fixes))} and ${sum(s[k].get("usd", 0) for s in fixes for k, _ in ROLES):,.2f} at list price.')
says.append(f'List price ${priced:,.2f}: ' + ', '.join(f'{MODEL[k]} ${T[k]["usd"]:,.2f}' for k, _ in ROLES if T[k].get('usd'))
            + (f'; ${estimated:,.2f} of the total is estimated from the nearest published price' if estimated else '')
            + (f'; ${tiered:,.2f} of the total is priced by Codex tier, not by exact version' if tiered else '')
            + (f'. Not priced: {" and ".join(unpriced)}' if unpriced else '') + '.')
says.append(f'Dearest stage: {dearest["code"]}. {dearest["name"]}, ${sum(dearest[k].get("usd", 0) for k, _ in ROLES):,.2f} in {hm(took(dearest))}.')
says.append(f'{n(T["builder"].get("calls", 0))} {AGENT} calls at an average context of {n(R["context"]["mean"])} tokens, largest {n(R["context"]["peak"])}'
            + (f'; compaction fired {len(R["compactions"])} time(s), at ' + ' and '.join(n(c['before'] or 0) for c in R['compactions']) + ' tokens' if R['compactions'] else '') + '.')
if T['advisor'].get('calls'):
    says.append(f'{T["advisor"]["calls"]} advisor call(s) sent {n(T["advisor"].get("in", 0))} uncached tokens to {MODEL["advisor"]}: ${T["advisor"].get("usd", 0):,.2f} at list price.')
if R['blocked']:
    by_hook = collections.Counter()
    for k, v in R['blocked'].items():
        by_hook[k.split(': ')[0]] += v
    says.append('Guards refused ' + str(sum(R['blocked'].values())) + ' tool call(s): ' + ', '.join(f'{k} {v}' for k, v in by_hook.most_common()) + '.')
flagged = R.get('flags') or []
flagbox = (f'<div class="box flag"><b>Flagged for a written review:</b>{ul(flagged)}</div>' if flagged and not N.get('lessons')
           else '')
summary = N.get('summary') or (f'**Automatic report, no reviewer words.** {AGENT} worked for {dur(TOTAL)} with {len(R["passes"])} Codex pass(es)'
                               f' ({", ".join(p["verdict"] for p in R["passes"]) or "none"}), at ${priced:,.2f} list price. '
                               + ('It tripped a threshold, so a written review is due.' if flagged else 'It tripped no threshold.'))
facts = [f'Largest context in one call: {n(R["context"]["peak"])} tokens; average {n(R["context"]["mean"])}.']
facts += [f'Compaction at {n(c["before"] or 0)} tokens, down to {n(c["after"] or 0)}, taking {round(c["end"] - c["start"])} s.' for c in R['compactions']]
if R['blocked']:
    facts.append('Tool calls a guard refused, by hook and reason: ' + '; '.join(f'{k} ({v})' for k, v in sorted(R['blocked'].items(), key=lambda x: -x[1])) + '.')
facts += [f'Helper "{h["what"]}": {nice(h["model"])}, {hm(h["seconds"])}, {M(allof(h["tokens"]))} tokens, ${h["tokens"].get("usd", 0):,.2f}.' for h in R['helpers']]
method = N.get('method', []) + [
    'Agent tokens and times: its Claude session log, one row per model call, each call counted once.',
    'Advisor tokens: the advisor entries logged beside the call that asked. They sit outside that call\'s own totals. Helpers: their own logs.',
    'Codex tokens: the last running total in each Codex session record whose working folder is the worktree, reviewer threads folded into their pass.',
    'Dollars are list-price equivalents: what these tokens would cost on the pay-as-you-go API, priced call by call with the dashboard\'s own price table (`scripts/dashboard_limit.py`). They are not what the plan bills. A model with no price in that table is left unpriced, never guessed.',
    'Each tenth of a second of the run is counted once in the clock chart. What the agent itself is doing wins over what it is waiting for, so the Codex and idle slices are pure waiting.',
    'A Claude request runs from the last log row before its first block to its last block; an advisor consult is inside the request that asked. Thinking time is the client\'s own figure for each thinking block.',
    'A tool call runs from the end of the request that asked for it to its result row. The hook rows inside that span split it into hooks before, the tool itself and hooks after. Only hooks that print something leave a row, so the per-hook table is a floor; the before and after phases are whole.',
    'What is left between steps is the client itself (sending, logging). Idle is the time from the end of a turn to the next wake-up.',
    'Helper output tokens are under-recorded in the logs; treat that column, and so the helpers\' cost, as a floor.']


# --- The two timing sections: every tool call and every model request, from collect.py's ledger. ---
TM = R['timing']
REQ, TOOLS = TM['requests'], TM['tools']


def at(t):
    return td(t, local(t, '%-I:%M:%S'))


def cmd_key(cmd):
    """What a shell command is, for grouping: a wait loop, the script it runs, or its first real program."""
    if re.match(r'\s*(?:until|while)\b', cmd):
        return 'wait loop (until or while)'
    scripts = re.findall(r'([\w.-]+\.(?:sh|py|mjs|js|ts))\b', cmd)
    if scripts:
        return next((s for s in scripts if '.test.' in s), scripts[0])
    for part in re.split(r'\s*(?:&&|\|\||;|\n)\s*', cmd.strip()):
        words = [w.strip('"\'()') for w in part.split() if not re.fullmatch(r'[A-Za-z_]\w*=\S*', w)]
        if not words or words[0] in ('cd', 'export', 'set', 'echo', 'printf', 'mkdir', 'true', ':'):
            continue
        head = os.path.basename(words[0])
        if head in ('bash', 'sh', 'python3', 'python', 'node', 'npx', 'npm', 'git', 'timeout', 'time', 'env') and len(words) > 1:
            nxt = next((w for w in words[1:] if not w.startswith('-') and not w.isdigit()), '')
            return f'{head} {os.path.basename(nxt)}'.strip()
        return head
    return '(setup only)'


def grouped(items, key, cols, order=None):
    """Rows of count, total, median, longest per group; cols adds cells per group. Largest total first, unless order sorts the group names."""
    groups = collections.defaultdict(list)
    for x in items:
        groups[key(x)].append(x)
    return [f'<tr><td>{txt(k)}</td>{td(len(v))}{td(round(sum(x["s"] for x in v), 1), sec(sum(x["s"] for x in v)))}'
            f'{td(med(x["s"] for x in v), sec(med(x["s"] for x in v)))}{td(max(x["s"] for x in v), sec(max(x["s"] for x in v)))}{cols(v)}</tr>'
            for k, v in sorted(groups.items(), key=(lambda kv: order(kv[0])) if order else lambda kv: -sum(x['s'] for x in kv[1]))]


# Off Claude's servers.
kinds = collections.defaultdict(list)
for c in TOOLS:
    kinds[c['kind']].append(c)
hooked = [c for c in TOOLS if c['pre'] + c['post'] > 0]
counts = {'tests': kinds['tests'], 'commands': kinds['commands'] + kinds['codex'], 'files': kinds['files'], 'tools': kinds['tools']}
off_rows = []
for k, name, _, side in sorted(CLOCK, key=lambda x: -clock.get(x[0], 0)):
    if side != 'off' or clock.get(k, 0) < 1:
        continue
    runs = [c['run'] for c in counts.get(k, [])] or ([c['pre'] + c['post'] for c in hooked] if k == 'hooks' else
                                                     [took(g) for g in R['idle_gaps']] if k.startswith('idle') else [])
    off_rows.append(f'<tr><td>{name}</td>{td(clock[k], hm(clock[k]))}{td(round(100 * clock[k] / TOTAL, 1), f"{100 * clock[k] / TOTAL:.1f}%")}'
                    + (f'{td(len(runs))}{td(med(runs), sec(med(runs)))}{td(max(runs), sec(max(runs)))}' if runs and not k.startswith('idle')
                       else '<td></td><td></td><td></td>') + '</tr>')
bash = [c for c in TOOLS if c['name'] == 'Bash']
cmd_rows = grouped(bash, lambda c: cmd_key(c['cmd']), lambda v: td(sum(c['timeout'] for c in v)) + td(sum(c['refused'] for c in v))
                   + f'<td>{txt(max(v, key=lambda c: c["s"])["what"])}</td>')[:30]
by_tool = collections.defaultdict(list)
for c in TOOLS:
    by_tool[c['name']].append(c)
phase_rows = [f'<tr><td>{txt(k)}</td>{td(len(v))}' + ''.join(td(med(c[p] for c in v), sec(med(c[p] for c in v))) for p in ('pre', 'run', 'post'))
              + td(round(sum(c['pre'] + c['post'] for c in v), 1), sec(sum(c['pre'] + c['post'] for c in v))) + '</tr>'
              for k, v in sorted(by_tool.items(), key=lambda kv: -sum(c['pre'] + c['post'] for c in kv[1]))]
hook_rows = [f'<tr><td>{txt(h["event"])}</td><td>{txt(h["name"])}</td>{td(h["runs"])}{td(h["total"], sec(h["total"]))}{td(h["median"], sec(h["median"]))}{td(h["max"], sec(h["max"]))}</tr>'
             for h in TM['hooks']]
WAITED_ON = {'codex': 'A Codex pass', 'helper': 'A helper', 'tests': 'A background test run', 'job': 'Another background job',
             'main': "Main's answer", 'nothing': 'Nothing logged', 'elsewhere': 'A review run outside this session',
             'down': 'The review tool, down'}
# A result saved before idle gaps recorded what they waited on: its worktree may be gone, so it cannot be collected again.
idle_rows = [f'<tr>{at(g["start"])}{td(took(g), hm(took(g)))}<td>{WAITED_ON.get(g.get("waiting"), "Unknown")}</td>'
             f'<td>{txt("; ".join(dict.fromkeys(g["pending"])) or "nothing logged as running")}</td>'
             f'<td>{", ".join(f"Codex pass {p["n"]}" for p in R["passes"] if p["start"] < g["end"] and p["end"] > g["start"]) or "&ndash;"}</td></tr>'
             for g in R['idle_gaps']]
cut_rows = [f'<tr>{at(w["start"])}{at(w["end"])}{td(w["seconds"], hm(w["seconds"]))}<td>{txt(w["reason"])}</td></tr>' for w in R.get('cut', [])]
cut_box = (f'<h4>Cut from the clock, waiting on the owner: {dur(R["cut_s"])}</h4><p class="tag">Not build time (the owner, 2026-10-14), so no clock figure, share or flag '
           'on this page counts it, but for two: a helper\'s request and tool subtotals, and command seconds inside a cut Codex pass. '
           'Cost is unchanged. Windows that overlap are cut once.</p>'
           + table(['>From', '>To', '>Length', 'Why'], cut_rows)) if cut_rows else ''
codex_rows = [f'<tr>{td(p["n"])}{td(took(p), hm(took(p)))}{td(p["commands"])}{td(p["command_s"], sec(p["command_s"]))}'
              + (td(max(took(p) - p['command_s'], 0), hm(max(took(p) - p['command_s'], 0))) if p['threads'] == 1 else '<td class="r">several threads</td>')
              + f'<td>{txt("; ".join(f"{sec(s)} {c.split(chr(92))[0][:70]}" for s, c in p["longest"][:2]))}</td></tr>' for p in R['passes']]
helper_rows = [f'<tr><td>{txt(h["what"])}</td><td>{txt(nice(h["model"]))}</td>{td(h["seconds"], hm(h["seconds"]))}{td(h["claude_s"], hm(h["claude_s"]))}{td(h["tool_s"], hm(h["tool_s"]))}'
               # An older result.json has no count: a dash, never a 0 nobody counted.
               + (td(h['compactions'], cls='r comp') if 'compactions' in h else '<td class="r">&ndash;</td>') + '</tr>'
               for h in R['helpers']]
COMPACTED = (len(R['compactions']), sum(h.get('compactions', 0) for h in R['helpers']))


def result_of(c):
    return ', '.join(x for x in (c['outcome'], 'hit its time limit' if c['timeout'] else '', 'refused by a guard' if c['refused'] else '',
                                 'started in the background' if c['bg'] else '') if x)


tool_rows = [f'<tr>{at(c["t"])}<td>{c["stage"]}</td><td>{txt(c["name"])}</td><td title="{html.escape(c["cmd"])}">{txt(c["what"])}</td>'
             + ''.join(td(c[p], sec(c[p])) for p in ('s', 'pre', 'run', 'post')) + f'<td>{txt(result_of(c))}</td></tr>' for c in TOOLS]
CT = TM['counters']
off_box = [f'**{dur(SIDE["off"])} of {dur(TOTAL)} ({100 * SIDE["off"] / TOTAL:.0f}%) was not spent on Claude\'s servers.** Claude requests and compaction took {dur(SIDE["claude"])} ({100 * SIDE["claude"] / TOTAL:.0f}%).',
           f'{len(TOOLS)} tool calls took {dur(sum(c["s"] for c in TOOLS))} in all: {sec(sum(c["pre"] for c in TOOLS))} in hooks before, {dur(sum(c["run"] for c in TOOLS))} in the tools themselves, {sec(sum(c["post"] for c in TOOLS))} in hooks after.',
           f'A hook pass costs {sec(med(c["pre"] + c["post"] for c in hooked))} per tool call (median of {len(hooked)}), {sec(clock.get("hooks", 0) + clock.get("hooks_stop", 0))} over the run.']
if CT:
    off_box.append(f'Cross-check, the client\'s own counters for the session(s): {dur(CT["api"])} of API time and {dur(CT["tool"])} of tool time. '
                   'Its API figure runs higher than the request total below because it also counts helper agents and compaction, and likely small background calls (not checked).')
off_html = (f'<h2>Time off Claude\'s servers: tools, hooks, Codex and waiting</h2><div class="box">{ul(off_box)}</div>'
            '<h4>What it was</h4>' + table(['What', '>Time', '>Share of run', '>Calls', '>Median each', '>Longest'], off_rows)
            + '<h4>Commands, grouped by the script or program they ran</h4>'
            + table(['Command', '>Calls', '>Total', '>Median', '>Longest', '>Hit time limit', '>Refused', 'Longest one was'], cmd_rows)
            + '<h4>Hooks around each tool call, by tool (medians)</h4>'
            + table(['Tool', '>Calls', '>Hooks before', '>Tool itself', '>Hooks after', '>All hook time'], phase_rows)
            + '<h4>Hooks that left a log row</h4><p class="tag">Only a hook that prints something is logged, so this is a floor per hook. Stop hooks are all logged.</p>'
            + table(['When', 'Hook', '>Runs', '>Total', '>Median', '>Longest'], hook_rows)
            + (('<h4>Idle waits: the turn had ended and the agent waited to be woken</h4>' + table(['>At', '>Waited', 'Waiting on', 'Background job still running', 'Codex pass running'], idle_rows)) if idle_rows else '')
            + (('<h4>Inside each Codex pass (OpenAI servers)</h4><p class="tag">Command time is what Codex\'s own commands reported; the rest is the Codex model.</p>'
                + table(['>Pass', '>Took', '>Commands', '>In commands', '>In the model', 'Longest commands'], codex_rows)) if codex_rows else '')
            + (('<h4>Helper agents</h4><p class="tag">A helper started in the background runs alongside the agent, so its time is not in the clock above.</p>'
                + table(['Helper', 'Model', '>Ran for', '>Its Claude requests', '>Its tools', '>Compactions'], helper_rows)) if helper_rows else '')
            + f'<details><summary><b>Every tool call</b> &middot; {len(TOOLS)} rows, click a heading to sort; hover a row\'s text for the command</summary>'
            + table(['>At', 'Stage', 'Tool', 'What', '>Total', '>Hooks before', '>Tool itself', '>Hooks after', 'Result'], tool_rows) + '</details>')

# On Claude's servers.
RT = sum(r['s'] for r in REQ) or 1
waits = [r['wait'] for r in REQ if r['wait'] is not None]


def did(r):
    return ' + '.join(f'{c} {k}' if c > 1 else k for k, c in collections.Counter(r['tools']).items()) or r['what']


def band(value, edges, unit):
    lo = 0
    for hi in edges:
        if value < hi:
            return f'{n(lo)} to {n(hi)} {unit}'
        lo = hi
    return f'{n(lo)} {unit} and up'


def req_cols(v):
    return (td(p90([r['s'] for r in v]), sec(p90([r['s'] for r in v]))) + td(med(r['wait'] for r in v if r['wait'] is not None), sec(med(r['wait'] for r in v if r['wait'] is not None)))
            + td(round(sum(r['think'] for r in v), 1), sec(sum(r['think'] for r in v))) + td(int(med(r['out'] for r in v)), n(med(r['out'] for r in v)))
            + td(round(sum(r['usd'] or 0 for r in v), 2), f'${sum(r["usd"] or 0 for r in v):,.2f}'))


REQ_HEADS = ['>Requests', '>Total', '>Median', '>Longest', '>9 in 10 under', '>Median wait to start', '>Thinking', '>Median output tokens', '>List price']
act_rows = grouped(REQ, lambda r: ' + '.join(sorted(set(r['tools']))) or r['what'], req_cols)
ctx_edges, out_edges = (50_000, 100_000, 150_000, 200_000, 250_000), (100, 500, 2_000, 5_000)



def by_size(name):
    return int(name.split()[0].replace(',', ''))


ctx_rows = grouped(REQ, lambda r: band(r['ctx'], ctx_edges, 'tokens'), req_cols, by_size)
out_rows = grouped(REQ, lambda r: band(r['out'], out_edges, 'tokens'), req_cols, by_size)
stage_rows = grouped(REQ, lambda r: r['stage'] + '. ' + next(s['name'] for s in R['stages'] if s['code'] == r['stage']), req_cols)


def req_row(r):
    return (f'<tr>{at(r["t"])}<td>{r["stage"]}</td>{td(r["s"], sec(r["s"]))}{td(r["wait"] if r["wait"] is not None else -1, sec(r["wait"]) if r["wait"] is not None else "&ndash;")}'
            f'{td(r["think"], sec(r["think"]))}{td(r["out"], n(r["out"]))}{td(round(r["out"] / max(r["s"], 0.1)), n(r["out"] / max(r["s"], 0.1)))}{td(r["ctx"], n(r["ctx"]))}{td(r["cw"], n(r["cw"]))}'
            # A result.json from before these two columns has neither count: both show a dash.
            f'{td(-1 if r.get("cr") is None else r["cr"], "&ndash;" if r.get("cr") is None else n(r["cr"]), "r cr")}'
            f'{td(-1 if hit(r) == "&ndash;" else float(hit(r)[:-1]), hit(r), "r hit")}'
            f'{td(r["usd"] or 0, f"${r["usd"]:,.2f}" if r["usd"] is not None else "&ndash;")}<td>{txt(did(r))}{" <span class=tag>+ advisor</span>" if r["advisor"] else ""}</td><td>{txt(r["what"])}</td></tr>')


ONE_REQ = ['>At', 'Stage', '>Took', '>Wait to start', '>Thinking', '>Output tokens', '>Tokens a second', '>Context', '>Cache write', '>Cache read', '>Cache hit', '>List price', 'Did', 'What']
cold = [r for r in REQ if r['cw'] >= 20_000]

# Where the server time could shrink: computed the same way on every run, each a ceiling, none a ruling.
ideas, chains, run = [], [], []
for r in REQ + [None]:
    if r and r['look'] and (not run or run[-1]['session'] == r['session']):
        run.append(r)
        continue
    if len(run) >= 2:
        chains.append(run)
    run = [r] if r and r['look'] else []
if chains:
    longest = max(chains, key=len)
    ideas.append(f'**Single looks in a row.** {sum(len(c) for c in chains)} requests in {len(chains)} runs each made one read-only look, back to back. Sent together, each run is one request: '
                 f'up to {dur(sum(sum(r["s"] for r in c) - max(r["s"] for r in c) for c in chains))} and ${sum(sum(r["usd"] or 0 for r in c) - max(r["usd"] or 0 for r in c) for c in chains):,.2f} less. '
                 f'The longest run was {len(longest)} looks, starting {local(longest[0]["t"], "%-I:%M:%S %p")} with "{longest[0]["what"][:70]}". Whether each look needed the one before it is not checked, so this is a ceiling.')
quiet = [r['s'] for r in REQ if r['out'] <= 150 and not r['think'] and not r['advisor']]
if quiet:
    ideas.append(f'**The fixed cost of a round trip.** A request that writes almost nothing still takes {sec(med(quiet))} (median of {len(quiet)}). '
                 f'Over all {len(REQ)} requests that floor is about {dur(med(quiet) * len(REQ))} of the {dur(RT)}; only fewer, larger requests cut it.')
slow_think = [r for r in REQ if r['think'] >= 20]
if slow_think:
    top_think = max(slow_think, key=lambda r: r['think'])
    ideas.append(f'**Long thinking.** {len(slow_think)} requests thought for 20 s or more, {dur(sum(r["think"] for r in slow_think))} of the {dur(sum(r["think"] for r in REQ))} of logged thinking. '
                 f'The longest, {sec(top_think["think"])}, came before "{top_think["what"][:70]}".')
big = [r for r in REQ if r['out'] >= 3_000]
if big:
    ideas.append(f'**Long replies.** {len(big)} requests wrote 3,000 tokens or more and took {dur(sum(r["s"] for r in big))} together. The largest wrote {n(max(r["out"] for r in big))} tokens: "{max(big, key=lambda r: r["out"])["what"][:70]}".')
advised = [r for r in REQ if r['advisor']]
if advised:
    ideas.append(f'**Advisor consults.** {len(advised)} requests asked the advisor and took {dur(sum(r["s"] for r in advised))} together, {sec(med(r["s"] for r in advised))} each at the median against {sec(med(r["s"] for r in REQ))} for all requests.')
if cold:
    ideas.append(f'**Cache writes.** {len(cold)} requests each wrote 20,000 tokens or more to the cache ({n(sum(r["cw"] for r in cold))} tokens, ${sum(r["usd"] or 0 for r in cold):,.2f} at list price for those requests). '
                 'They follow a compaction, a long pause or a large new read; the table below lists them.')
repeats = collections.defaultdict(list)
for c in bash:
    repeats[c['cmd']].append(c)
again = sorted(((sum(c['s'] for c in v), v) for v in repeats.values() if len(v) >= 3), key=lambda x: -x[0])[:3]
if again:
    ideas.append('**The same command run three times or more.** ' + '; '.join(f'"{v[0]["what"][:60]}" {len(v)} times, {sec(s)}' for s, v in again) + '. Each run also cost a request.')
lost = [c for c in TOOLS if c['timeout']]
if lost:
    ideas.append(f'**Commands cut off at their time limit.** {len(lost)}, {dur(sum(c["s"] for c in lost))} together.')
refused = [c for c in TOOLS if c['refused']]
if refused:
    ideas.append(f'**Tool calls a guard refused.** {len(refused)}; each cost the request that asked ({sec(med(r["s"] for r in REQ))} at the median) and usually a second one to retry.')
# A written review marks each item: covered by an open issue, cited, or not, with a one-line proposed
# fix. An item it leaves out is named, so an unreviewed lead shows on the page.
review = []
if ideas and N.get('lessons'):
    marks = [x for x in N.get('shrink_review') or [] if isinstance(x, dict) and x.get('item')]
    review = [f'**{x["item"]}**: ' + (f'covered by {x["issue"]}' if x.get('issue') else f'not covered; proposed fix: {x.get("fix") or "none given"}')
              for x in marks]
    left = [t for t in (re.match(r'\*\*(.+?)\.\*\*', i)[1] for i in ideas) if t not in {x['item'].rstrip('.') for x in marks}]
    if left:
        review.append('**Not reviewed yet**: ' + ', '.join(left))
on_box = [f'**{len(REQ)} requests took {dur(RT)}** ({100 * RT / TOTAL:.0f}% of the run): {sec(med(r["s"] for r in REQ))} at the median, 9 in 10 under {sec(p90([r["s"] for r in REQ]))}, the longest {sec(max(r["s"] for r in REQ))}.',
          f'Logged thinking: {dur(sum(r["think"] for r in REQ))} ({100 * sum(r["think"] for r in REQ) / RT:.0f}% of request time). The rest is waiting for the reply to start and writing it.',
          f'{n(sum(r["out"] for r in REQ))} output tokens, {sum(r["out"] for r in REQ) / RT:.0f} a second over the whole request time.'
          ] if REQ else ['No Claude request on record: a Codex seat built this alone.']
if waits:
    on_box.insert(2, f'Wait before the model began, where it can be read ({len(waits)} requests that opened with thinking): {sec(med(waits))} at the median, 9 in 10 under {sec(p90(waits))}.')
on_html = (f'<h2>Time on Claude\'s servers, request by request</h2><div class="box">{ul(on_box)}</div>'
           + (f'<h4>Where it could shrink</h4><div class="box">{ul(ideas)}</div>' if ideas else '')
           + (f'<h4>Each item against the open issues</h4><div class="box">{ul(review)}</div>' if review else '')
           + '<h4>By what the request did</h4>' + table(['Request made'] + REQ_HEADS, act_rows[:20])
           + '<h4>By stage</h4>' + table(['Stage'] + REQ_HEADS, stage_rows)
           + '<h4>By context size: does a larger context slow a request?</h4>' + table(['Context sent'] + REQ_HEADS, ctx_rows)
           + '<h4>By reply size</h4>' + table(['Tokens written'] + REQ_HEADS, out_rows)
           + '<h4>The 25 slowest requests</h4>' + table(ONE_REQ, [req_row(r) for r in sorted(REQ, key=lambda r: -r['s'])[:25]])
           + (('<h4>Requests that wrote 20,000 tokens or more to the cache</h4>' + table(ONE_REQ, [req_row(r) for r in sorted(cold, key=lambda r: -r['cw'])[:25]])) if cold else '')
           + f'<details><summary><b>Every request</b> &middot; {len(REQ)} rows, click a heading to sort</summary>' + table(ONE_REQ, [req_row(r) for r in REQ]) + '</details>')
SORT_JS = ('<script>document.querySelectorAll("table.sort").forEach(t=>{[...t.rows[0].cells].forEach((th,c)=>{th.style.cursor="pointer";'
           'th.onclick=()=>{const d=th.d=-(th.d||-1),v=r=>{const x=r.cells[c].dataset.v??r.cells[c].textContent,n=parseFloat(x);return isNaN(n)||!/^-?[\\d.]+$/.test(x)?x.toLowerCase():n};'
           '[...t.rows].slice(1).sort((a,b)=>{const x=v(a),y=v(b);return(x>y?1:x<y?-1:0)*d}).forEach(r=>t.tBodies[0].appendChild(r))}})})</script>')

title = txt(N.get('title') or 'Build review: ' + R['unit'])
page = f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title><style>
body{{font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#111827;background:#f8fafc;margin:0}}
main{{max-width:1120px;margin:0 auto;padding:28px 24px 60px}} h1{{font-size:26px;margin:0 0 4px}}
h2{{font-size:19px;margin:34px 0 10px;padding-top:14px;border-top:1px solid #e5e7eb}} h4{{margin:12px 0 4px;font-size:13.5px}} .sub{{color:#6b7280;margin:0 0 18px}}
.cards{{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:16px 0}} .card,.box{{background:#fff;border:1px solid #e5e7eb;border-radius:10px;padding:14px 16px}}
.box{{margin:12px 0}} .big{{font-size:24px;font-weight:700}} .lab,.tag{{color:#6b7280;font-size:13px;font-weight:400}}
table{{border-collapse:collapse;width:100%;background:#fff;border:1px solid #e5e7eb;font-size:14px}}
th{{text-align:left;background:#f1f5f9;padding:8px 10px;font-size:12.5px;color:#374151;vertical-align:bottom}} td{{padding:7px 10px;border-top:1px solid #eef2f7;vertical-align:top}}
.r{{text-align:right;white-space:nowrap;font-variant-numeric:tabular-nums}} .what{{color:#4b5563;font-size:13px;margin-top:2px}}
tr.codex td:first-child{{border-left:4px solid #7c3aed}} tr.fix td:first-child{{border-left:4px solid #c2410c}} tr.build td:first-child{{border-left:4px solid #1d4ed8}}
.barrow{{display:grid;grid-template-columns:340px 1fr 130px;gap:12px;align-items:center;margin:7px 0}} .track{{background:#eef2f7;border-radius:6px;height:18px}} .bar{{height:18px;border-radius:6px}}
.go{{background:#dcfce7;color:#166534;padding:1px 8px;border-radius:10px;font-weight:600}} .nogo{{background:#fee2e2;color:#991b1b;padding:1px 8px;border-radius:10px;font-weight:600}}
.lesson{{background:#fff;border:1px solid #e5e7eb;border-left:4px solid #111827;border-radius:8px;padding:12px 16px;margin:10px 0}} .lesson h3{{margin:0 0 6px;font-size:16px}}
.flag{{border-left:4px solid #c2410c}}
details{{background:#fff;border:1px solid #e5e7eb;border-radius:8px;padding:10px 14px;margin:8px 0}} summary{{cursor:pointer}} .cols{{display:grid;grid-template-columns:1fr 1.4fr;gap:16px}}
ul{{margin:6px 0 0 18px;padding:0}} li{{margin:3px 0}} code{{background:#eef2f7;padding:1px 5px;border-radius:4px;font-size:13px}}
@media(max-width:800px){{.cards{{grid-template-columns:repeat(2,1fr)}}.barrow,.cols{{grid-template-columns:1fr}}}}
</style></head><body><main>
<h1>{title}</h1>
<p class="sub"><code>{txt(R['unit'])}</code> &middot; built by <b>{txt(AGENT)}</b> &middot; {local(R['start'], '%A %-d %B %Y, %-I:%M %p')} to {local(R['end'])} &middot; {len(R['sessions'])} agent session(s)</p>
<div class="box">{txt(summary)}</div>{flagbox}
<div class="cards">
<div class="card"><div class="big">{dur(TOTAL)}</div><div class="lab">first log entry to last</div></div>
<div class="card"><div class="big">{len(R['passes'])} Codex passes</div><div class="lab">{', '.join(p['verdict'] for p in R['passes']) or 'none found'}</div></div>
<div class="card"><div class="big">{sum(COMPACTED)} compaction{'' if sum(COMPACTED) == 1 else 's'}</div><div class="lab">{COMPACTED[0]} by the Builder, {COMPACTED[1]} by its helpers</div></div>
<div class="card"><div class="big">{grand / 1e6:.1f}M tokens</div><div class="lab">all models; {100 * cached / max(1, grand):.0f}% were cache reads</div></div>
<div class="card"><div class="big">${priced:,.2f}</div><div class="lab">list-price equivalent{', without ' + txt(' and '.join(unpriced)) if unpriced else ''}</div></div>
</div>
<h2>Where the time went</h2><div class="box">{bars}{cut_box}</div>
<h2>Stage by stage</h2>
<table><tr><th>Stage and what happened</th><th class="r">Started</th><th class="r">Time (min:sec)</th><th class="r">{txt(AGENT)} calls</th><th class="r">Cache read</th><th class="r">Cache write</th><th class="r">Cache hit</th><th class="r">Output</th><th class="r">List price, all priced models</th><th>Other models in this stage</th></tr>{''.join(rows)}
<tr><td><b>Whole run</b></td><td></td><td class="r"><b>{hm(TOTAL)}</b></td><td class="r">{n(T['builder'].get('calls', 0))}</td><td class="r">{M(T['builder'].get('cr', 0))}</td><td class="r">{M(T['builder'].get('cw', 0))}</td><td class="r hit">{hit(T['builder'])}</td><td class="r">{M(T['builder'].get('out', 0))}</td><td class="r"><b>${priced:,.2f}</b></td><td></td></tr></table>
<p class="tag">Blue edge = building, purple = Codex reviewing, orange = fixing a Codex finding. The call and token columns are {txt(AGENT)}'s own.</p>
<h2>Stage drilldown</h2><p class="tag">Open a stage to see where its minutes and dollars went, its longest commands, the files it touched and the agent's own notes.</p>{''.join(drill)}
<h2>Tokens and cost by model</h2>
<table><tr><th>Model</th><th class="r">Model calls</th><th class="r">Uncached input</th><th class="r">Cache write</th><th class="r">Cache read</th><th class="r">Output</th><th class="r">All tokens</th><th class="r">List price</th></tr>{''.join(mrows)}
<tr><td><b>All</b></td><td></td><td></td><td></td><td></td><td></td><td class="r"><b>{n(grand)}</b></td><td class="r"><b>${priced:,.2f}</b></td></tr></table>
{rungs_html}
<h2>Codex passes</h2>
<table><tr><th class="r">Pass</th><th>Kind</th><th class="r">Time</th><th class="r">Input tokens</th><th class="r">From cache</th><th class="r">Output</th><th class="r">Threads</th><th>Verdict, findings</th><th>What it said</th></tr>{''.join(prows)}</table>
<h2>What the numbers say</h2><div class="box">{ul(says)}</div>
{lessons}
{off_html}
{on_html}
<h2>Other facts from the logs</h2><div class="box">{ul(facts)}</div>
<h2>What this report does not measure</h2><div class="box">{ul(N.get('not_measured', []))}</div>
<h2>How the numbers were made</h2><div class="box">{ul(method)}</div>
</main>{SORT_JS}</body></html>
'''
open(OUT, 'w').write(page)
print('wrote', OUT, len(page), 'bytes;', f'list price ${priced:,.2f}', 'unpriced:', unpriced)

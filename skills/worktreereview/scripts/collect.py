#!/usr/bin/env python3
"""Collect time, token and list-price figures for one worktree's agent run.

Reads only logs, so it works after the worktree is removed: the Claude session
logs filed under the worktree's path, their helpers' logs, and every Codex
session record whose working folder is the worktree.

Usage:
  collect.py <worktree path> [--out DIR] [--session ID-PREFIX]
             [--split HH:MM:SS=Label ...] [--test-regex RE] [--exclude START=END ...] [--main DIR]

--split starts a new stage named Label at that UTC time (date of the run start);
a time within a minute of the run start renames the first stage. Writes result.json
and notes.txt (the agent's own progress notes, for choosing splits) to --out.

Time spent waiting on the owner is not build time (the owner, 2026-10-14): each --exclude window (ISO UTC)
and the part of each idle gap over two minutes with nothing running that sits inside an open decision for
this unit (decisions.jsonl) comes out of the clock, shares and flags; cost stays.
"""
import argparse
import collections
import glob
import importlib.util
import json
import math
import os
import re
import statistics
import subprocess
import sys
import tarfile
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from timing import LOOK_TOOLS, codex_commands, rows_of, session_ledger, ts  # noqa: E402

TEST_RE = r'self-test|sweep|\btests?\b|time the|timings?\b|preflight|red run'
PASS_CMD = re.compile(r'builder-codex-pass\.sh\s+\S+\s+(\d+)\s+(adversarial|review|final)')
OUTCOME = re.compile(r'\d+ passed, \d+ failed|HUNG past \d+s')
EDIT_TOOLS = ('Edit', 'Write', 'MultiEdit', 'NotebookEdit')
FILE_TOOLS = EDIT_TOOLS + LOOK_TOOLS
KEYS = ('calls', 'in', 'cw', 'cr', 'out', 'usd', 'est', 'tier', 'unpriced', 'uncounted')
IDLE = ('idle', 'idle_job', 'idle_tests')
# Waits on a review the Builder could not run: a pass run outside its session, or a review tool that was down.
# Shown on the page, never in the share flag: the build did nothing wrong in them.
REVIEW_WAIT = ('idle_elsewhere', 'idle_down')
# What builder-codex-pass.sh says when it cannot reach the reviewer.
TOOL_DOWN = re.compile(r'REFUSED: (?:the \w+ \w+ pass failed|no Codex session appeared|the Codex broker|the Codex CLI is not signed in|no codex on PATH)')
WAIT_ON_OWNER = 120  # an idle gap longer than this, waiting on the owner, is cut from the clock
SHARE_FLOOR = 600  # seconds of tests and idle waits below which no share flags a build: two test runs are a third of a short one
OUT_ROOT = '/tmp/commandeck/worktreereview'
DECISIONS = None  # decisions.jsonl; None is the main checkout's own
# What a call that went to the background answers at once: a Bash job's id, or a helper's. The harness
# runs a helper in the background without the flag, so the answer is the only sign of it.
STARTED = re.compile(r'running in background with ID: (\w+)|Async agent launched[\s\S]{0,400}?agentId: (\w+)')
# What the job tools answer once a job is over; "running" or a partial output is not an end.
# The tool's own status tag, with nothing ahead of it but the tool's other one-line tags.
ENDED = re.compile(r'\s*(?:<(?!status>)(\w+)>[^<>\n]*</\1>\s*)*<status>(?:completed|failed|killed)</status>')
JOB_TOOLS = ('TaskOutput', 'BashOutput', 'TaskStop', 'KillShell')
# A call that puts a question to main or waits on its inbox.
ASK = re.compile(r'orchestration\s+(?:ask\b|check\b[^;&|]*--wait|send\b[^;&|]*--type\s+(?:question|escalation))')
TICK = 10  # clock slots per second: hook phases run well under a second
# A command that only looks: used to find requests that could have been sent together.
LOOK = re.compile(r'^\s*(?:cd\s+\S+\s*(?:&&|;)\s*)?(?:cat|sed -n|grep|rg|ls|wc|head|tail|find|jq|nl|stat|file|diff|'
                  r'git\s+(?:-C\s+\S+\s+)?(?:log|diff|show|status|grep|blame|ls-files|rev-parse))\b')
WRITES = re.compile(r'>\s*[\w/~.$"]|\btee\b|\brm\b|\bmv\b|\bcp\b|sed -i')


def hm(sec):
    sec = int(round(sec))
    return f'{sec // 60}:{sec % 60:02d}'


def load_prices():
    """The repo's one price table lives in dashboard_limit.py; a checkout without it prices nothing."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'scripts', 'dashboard_limit.py')
    if not os.path.exists(path):
        return None
    spec = importlib.util.spec_from_file_location('dashboard_limit', path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


PRICES = load_prices()


def usd(model, u):
    """List price of one model call by the dashboard's own rules; None when the model has no price on file."""
    if PRICES is None:
        return None
    row = PRICES.request_row({'requestId': 'x', 'timestamp': '2026-01-01T00:00:00Z', 'type': 'assistant',
                              'message': {'model': model, 'usage': u}})
    return PRICES.price(row) if row else None


def own_usage(u):
    """One call's usage without the advisor's share: that is priced once, in the advisor's own bucket."""
    return u | {'iterations': [i for i in u.get('iterations') or [] if i.get('type') != 'advisor_message']}


def cache_counts(u):
    """(uncached input, cache read) of one request for the page's cache-hit column.

    Both None when any of the three input counts is missing: the page then shows no share, never 0%.
    """
    keys = ('input_tokens', 'cache_creation_input_tokens', 'cache_read_input_tokens')
    return (u['input_tokens'], u['cache_read_input_tokens']) if all(isinstance(u.get(k), int) for k in keys) else (None, None)


def add(acc, u, model=None, calls=1):
    acc['calls'] += calls
    acc['in'] += u.get('input_tokens') or 0
    acc['cw'] += u.get('cache_creation_input_tokens') or 0
    acc['cr'] += u.get('cache_read_input_tokens') or 0
    acc['out'] += u.get('output_tokens') or 0
    # A missing count adds 0 above, so a share worked out from these sums would be of part of the input.
    if None in cache_counts(u):
        acc['uncounted'] += calls
    cost = usd(model, u) if model else None
    if cost is None:
        acc['unpriced'] += calls
    else:
        acc['usd'] += cost


def r2(x):
    return None if x is None else round(x, 2)


def refusal(blocked):
    """A refused call's key, its hook and its reason: paths, quoted names and numbers differ between refusals
    of one kind, so they are folded."""
    _, hook, rest = blocked
    why = re.sub(r'^:\s*(BLOCKED\s*(\([^)]*\))?:?\s*)?', '', rest.split('\n')[0])
    why = re.split(r'\. |: | -- ', re.sub(r"'[^']*'|\S*/\S*\.\S+", '…', why))[0]
    why = re.sub(r'\d+', 'N', why)[:100].strip()
    return f'{hook}: {why}' if why else hook


def read_session(path):
    """One Claude session log -> its calls, tool calls, wake-ups, questions to main and failed pass launches."""
    s = {'usage': {}, 'tools': {}, 'results': {}, 'outcome': {}, 'woken': {}, 'turn_ends': [], 'users': [],
         'compactions': [], 'notes': [], 'blocked': [], 'asks': [], 'down': [], 'first': None, 'last': None, 'final': ''}
    tasks, asked = {}, {}  # background task id -> its call; a job tool's call -> the job's call it asks about
    for e in rows_of(path):
        when = e.get('timestamp')
        if when:
            s['first'] = s['first'] or ts(when)
            s['last'] = ts(when)
        m = e.get('message') or {}
        c = m.get('content')
        if e.get('type') == 'assistant':
            # One API message is logged once per content block; the last copy has the final usage.
            s['usage'][m.get('id')] = (s['usage'].get(m.get('id'), (ts(when),))[0], m.get('usage') or {}, m.get('model'))
            for b in c if isinstance(c, list) else []:
                if b.get('type') == 'text' and b.get('text', '').strip():
                    s['final'] = b['text']
                    s['notes'].append((ts(when), b['text'].strip().replace('\n', ' ')[:220]))
                elif b.get('type') == 'tool_use':
                    i = b.get('input') or {}
                    s['tools'][b['id']] = {'t': ts(when), 'name': b.get('name'), 'bg': bool(i.get('run_in_background')),
                                           'desc': str(i.get('description') or i.get('file_path') or i.get('skill') or ''),
                                           'cmd': str(i.get('command') or '')}
                    if b.get('name') in JOB_TOOLS:
                        asked[b['id']] = tasks.get(str(i.get('task_id') or i.get('bash_id') or i.get('shell_id')))
                    if b.get('name') == 'Bash' and ASK.search(str(i.get('command') or '')):
                        s['asks'].append(ts(when))
        elif e.get('type') == 'user' and when:
            s['users'].append(ts(when))
            text = c if isinstance(c, str) else ''
            for b in c if isinstance(c, list) else []:
                if b.get('type') == 'tool_result':
                    s['results'][b.get('tool_use_id')] = ts(when)
                    body = b.get('content')
                    body = body if isinstance(body, str) else json.dumps(body)
                    s['outcome'][b.get('tool_use_id')] = '; '.join(dict.fromkeys(OUTCOME.findall(body)))[:120]
                    tool, started = s['tools'].get(b.get('tool_use_id')), STARTED.search(body[:800])
                    if tool and started:
                        tool['bg'] = True
                        tasks[started.group(1) or started.group(2)] = b.get('tool_use_id')
                    elif tool and b.get('is_error'):
                        # Refused by a hook, or failed before it started: no job runs, so none is waited on.
                        tool['bg'] = False
                    # A pass in the background says it later: in the answer of a job tool asking about it, or a
                    # look at its output file, which is named for the job's id. Its end notice carries no output.
                    if tool and TOOL_DOWN.search(body) and any(PASS_CMD.search(s['tools'][k]['cmd']) for k in
                                                              [b.get('tool_use_id'), asked.get(b.get('tool_use_id'))]
                                                              + [k for job, k in tasks.items() if job in tool['cmd'] + tool['desc']]
                                                              if k in s['tools']):
                        s['down'].append(ts(when))
                    # A job ends when its end is announced or a job tool says so, whichever the log shows first;
                    # looking at its output while it runs ends nothing.
                    if asked.get(b.get('tool_use_id')) and not b.get('is_error') and job_ended(b.get('content')):
                        s['woken'].setdefault(asked[b.get('tool_use_id')], ts(when))
                    if b.get('is_error') and 'hook error' in body[:200]:
                        # A hook run by its interpreter has its script path quoted: "/.../guard.py"].
                        hook = re.search(r'/([\w.-]+\.(?:sh|py))\\?"?\]', body[:400])
                        s['blocked'].append((ts(when), hook.group(1) if hook else 'unnamed hook', body[hook.end():hook.end() + 400] if hook else ''))
                elif b.get('type') == 'text':
                    text += b.get('text', '')
            for mm in re.finditer(r'<tool-use-id>(toolu_\w+)</tool-use-id>', text):
                s['woken'].setdefault(mm.group(1), ts(when))
        elif e.get('type') == 'attachment' and when and (e.get('attachment') or {}).get('type') == 'queued_command':
            # A finished background job is announced by a queued notice far more often than by a user row.
            for mm in re.finditer(r'<tool-use-id>(toolu_\w+)</tool-use-id>', str(e['attachment'].get('prompt') or '')):
                s['woken'].setdefault(mm.group(1), ts(when))
        elif e.get('type') == 'system' and when:
            if e.get('subtype') == 'turn_duration':
                s['turn_ends'].append(ts(when))
            elif c := compaction_of(e):
                s['compactions'].append(c)
    return s


def job_ended(content):
    """A job tool's own word that the job ended, never the job's captured output, which can hold any text."""
    text = content if isinstance(content, str) else ''.join(b.get('text') or '' for b in content or [] if isinstance(b, dict))
    try:
        said = json.loads(text)
    except ValueError:
        return bool(ENDED.match(text))
    # A stop is answered as one JSON object whose message says so; its other fields quote the job.
    return isinstance(said, dict) and str(said.get('message')).startswith('Successfully stopped')


def call_kind(t, test_re):
    text = t['desc'] + ' ' + t['cmd'][:200]
    if PASS_CMD.search(t['cmd']):
        return 'codex'
    if t['name'] in ('Agent', 'Task'):
        return 'helper'
    if t['name'] == 'Bash':
        return 'tests' if test_re.search(text) else 'commands'
    return 'files' if t['name'] in FILE_TOOLS else 'tools'


def idle_gap(sess, end, nxt, t1, kind, runs):
    """One idle wait -> its clock label and its row: the jobs still running in it and what the pane waited on.

    With none of its own jobs running, a pass launch in the turn before it that could not reach the reviewer
    is a review tool down, and a Codex run inside it is a review run outside this session."""
    pending = [t for k, t in sess['tools'].items() if t['bg'] and t['t'] < nxt and sess['woken'].get(k, t1) > end]
    kinds = {kind(t) for t in pending}
    turn = max((e for e in sess['turn_ends'] if e < end), default=sess['first'])
    waiting = next((k for k in ('codex', 'helper', 'tests') if k in kinds),
                   'job' if pending else 'down' if any(turn < d <= end for d in sess['down'])
                   else 'elsewhere' if any(p['start'] < nxt and p['end'] > end for p in runs)
                   else 'main' if any(turn < a <= end for a in sess['asks']) else 'nothing')
    return ('idle_tests' if 'tests' in kinds else 'idle_job' if pending else f'idle_{waiting}' if waiting in ('down', 'elsewhere') else 'idle',
            {'start': end, 'end': nxt, 'pending': [t['desc'][:90] for t in pending], 'waiting': waiting})


def decisions_for(path, unit):
    """(asked, answered or None, id) of each decision for the owner whose source or answer names this unit."""
    # The name is a whole token of the launcher's alphabet: unit-2, unit.v1, unit. and v2.unit beside unit are
    # other units. A sentence's full stop reads as part of the name, so at worst a cut is missed, never a wrong one.
    named = re.compile(r'(?<![A-Za-z0-9._-])' + re.escape(unit) + r'(?![A-Za-z0-9._-])')
    try:
        lines = open(path, errors='replace').read().splitlines()
    except OSError:
        return []
    # Append-only: a decision's asked row (answeredAt null) stays above its answered row, so a later row wins.
    # A decision asked again is a new askedAt, and so a window of its own.
    rows = {}
    for line in lines:
        try:
            d = json.loads(line)
            key = (d['id'], d.get('askedAt'))
            rows[key] = rows.get(key, {}) | d
        except (ValueError, TypeError, KeyError):
            continue
    asks = collections.defaultdict(list)
    for d in rows.values():
        try:
            # A Builder's question to main waits on main, not the owner: it stays on the clock.
            if d.get('askedAt') and d.get('waitsOn') != 'main':
                asks[d['id']].append((ts(d['askedAt']), ts(d['answeredAt']) if d.get('answeredAt') else None,
                                      bool(named.search(f"{d.get('source') or ''} {d.get('answer') or ''}"))))
        except (ValueError, TypeError, AttributeError):
            continue
    # A window closes at its answer, or at the next ask of the same decision, which replaces it whichever
    # unit that ask names; only then is a window kept for naming this unit.
    out = []
    for i, times in asks.items():
        times.sort()
        for n, (q, r, mine) in enumerate(times):
            ends = [x for x in (r, times[n + 1][0] if n + 1 < len(times) else None) if x is not None]
            if mine:
                out.append((q, min(ends) if ends else None, i))
    return out


def compaction_of(e):
    """One compaction from its log row, the Builder's or a subagent's; None for any other row."""
    if e.get('type') != 'system' or e.get('subtype') != 'compact_boundary' or not e.get('timestamp'):
        return None
    meta, end = e.get('compactMetadata') or {}, ts(e['timestamp'])
    return {'end': end, 'start': end - (meta.get('durationMs') or 0) / 1000, 'before': meta.get('preTokens'), 'after': meta.get('postTokens')}


def read_codex(path, worktree):
    """One Codex session record -> a pass, or None when it ran somewhere else."""
    p = {'file': path, 'start': None, 'end': None, 'complete': False, 'usage': {}, 'calls': 0,
         'model': None, 'effort': None, 'message': '', 'rows': []}
    here, tier = None, None
    for n, e in enumerate(rows_of(path)):
        pay = e.get('payload') or {}
        if e.get('type') == 'turn_context':
            here = here or pay.get('cwd')
            p['model'], p['effort'] = pay.get('model') or p['model'], pay.get('effort') or p['effort']
        elif pay.get('type') == 'thread_settings_applied' and isinstance(pay.get('thread_settings'), dict):
            # Only this row logs the speed tier; the dashboard reads the model from it too.
            p['model'], tier = pay['thread_settings'].get('model') or p['model'], pay['thread_settings'].get('service_tier')
        elif e.get('type') == 'token_usage_record':
            # One response's counts, as the dashboard's row for it; None when it cannot be used.
            p['rows'].append(PRICES.codex_row(e, p['model'], tier) if PRICES else None)
        if n > 60 and here is None:
            return None
        if here is not None and os.path.realpath(here) != os.path.realpath(worktree) and here != worktree:
            return None
        if e.get('timestamp'):
            p['start'] = p['start'] or ts(e['timestamp'])
            p['end'] = ts(e['timestamp'])
        if pay.get('type') == 'token_count' and (pay.get('info') or {}).get('total_token_usage'):
            p['usage'] = pay['info']['total_token_usage']
            p['calls'] += 1
        elif pay.get('type') == 'task_complete':
            p['complete'] = True
            p['message'] = pay.get('last_agent_message') or ''
    if here is None:
        return None
    verdict = re.findall(r'VERDICT:\s*(NO-GO|GO)', p['message'])
    p['verdict'] = verdict[-1] if verdict else ('stopped' if not p['complete'] else 'none')
    # A finding as the merge reads one (builder-codex-pass.sh FINDING): a '- ' or '* ' bullet, or none.
    p['findings'] = len(re.findall(r'^\s*(?:[-*]\s*)?\[P[0-3]\]', p['message'], re.M))
    return p


def fold_passes(records, rounds=None):
    """Codex records -> passes: the threads a round file names are one pass, as are records that overlap in time."""
    # One numbered round is one pass (what a pass is):
    # the first pass's reviewers run at once, and a pass may start threads of its own.
    # Each is a separate record inside the pass's time span, so fold it in.
    # Rounds first: a record no round names joins a round only from inside its
    # span, so a chat that runs across two rounds joins neither of them.
    records = sorted(records, key=lambda p: p['start'])
    of = {id(p): next((v[0] for t, v in (rounds or {}).items() if p['file'].endswith(f'-{t}.jsonl')), None) for p in records}
    spans = {}
    for p in records:
        if of[id(p)] is not None:
            s = spans.setdefault(of[id(p)], [p['start'], p['end']])
            s[1] = max(s[1], p['end'])
    outer, by_round, loose = [], {}, None
    for p in records:
        n = of[id(p)]
        if n is None and rounds:
            n = next((k for k, (s, e) in spans.items() if s <= p['start'] and p['end'] <= e), None)
        if rounds:
            o = by_round.get(n) if n is not None else (loose if loose and p['start'] < loose['end'] else None)
        else:
            o = outer[-1] if outer and p['start'] < outer[-1]['end'] else None
        if o:
            o['threads'] += 1
            o['calls'] += p['calls']
            o['rows'] = o.get('rows', []) + p.get('rows', [])
            o['files'].append(p['file'])
            o['end'] = max(o['end'], p['end'])
            for k, v in p['usage'].items():
                o['usage'][k] = (o['usage'].get(k) or 0) + (v or 0)
            # A thread cut off mid-way leaves the pass unfinished, whatever the others said.
            o['complete'] = o['complete'] and p['complete']
            # Only a reviewer gives a verdict; a helper thread changes none.
            if p['verdict'] in ('GO', 'NO-GO'):
                o['findings'] += p['findings']
                o['message'] += '\n\n' + p['message']
            # The worst of them is the pass's: a blocker, then a cut-off thread, then a GO.
            o['verdict'] = max(o['verdict'], p['verdict'], key=('none', 'GO', 'stopped', 'NO-GO').index)
        else:
            outer.append(p | {'threads': 1, 'files': [p['file']]})
            if n is not None:
                by_round[n] = outer[-1]
            else:
                loose = outer[-1]
    return outer


def codex_days(t0, t1):
    """The date folders to search: Codex files a record by its start date, so every day of the run and one either side."""
    first = datetime.fromtimestamp(t0, timezone.utc).date() - timedelta(days=1)
    return [(first + timedelta(days=d)).strftime('%Y/%m/%d') for d in range((datetime.fromtimestamp(t1, timezone.utc).date() - first).days + 2)]


def main_checkout(worktree, given=None):
    """The main checkout of the reviewed worktree's project, not of the plugin this script ships in. Once the
    worktree is removed nothing on this machine proves which checkout it came from, so only the one given
    (--main) counts; else None."""
    where = worktree if os.path.isdir(worktree) else given
    if not where:
        return None
    git = subprocess.run(['git', '-C', where, 'rev-parse', '--path-format=absolute', '--git-common-dir'],
                         capture_output=True, text=True)
    return os.path.dirname(git.stdout.strip()) if git.returncode == 0 else None


def loop_limits(home):
    """The thresholds past which a run is flagged, as (minutes of Codex review, share of the clock on tests or
    idle waits, dollars): the owner's answers at setup (reviewLoop in the project config), else today's defaults."""
    rl = {}
    if home:
        try:
            with open(os.path.join(home, '.claude/commandeck.json')) as f:
                rl = json.load(f).get('reviewLoop')
        except OSError:
            pass
        except (ValueError, AttributeError) as e:
            raise SystemExit(f'{home}/.claude/commandeck.json cannot be read for reviewLoop ({e}); answer it again with /commandeck:setup')
    rl = {} if rl is None else rl
    if not isinstance(rl, dict):
        raise SystemExit(f'{home}/.claude/commandeck.json: reviewLoop is not an object ({rl!r}); answer it again with /commandeck:setup')
    # "off" is the owner's answer that a check never flags (#87): no number is past it.
    limit = lambda k, default, scale=1: math.inf if rl.get(k) == 'off' else float(rl[k]) / scale if k in rl else default
    try:
        got = (limit('maxReviewMinutes', 30.0), limit('maxTestPercent', 1 / 3, 100), limit('maxUsd', 30.0))
    except (TypeError, ValueError) as e:
        got = e
    # NaN compares false with everything, so it would flag nothing: only a finite number, 0 or more, or off, is a threshold.
    if isinstance(got, Exception) or not all((math.isfinite(x) or (x == math.inf and rl.get(k) == 'off')) and x >= 0
                                             for x, k in zip(got, ('maxReviewMinutes', 'maxTestPercent', 'maxUsd'))):
        raise SystemExit(f'{home}/.claude/commandeck.json: a reviewLoop threshold is not a number of 0 or more ({rl}); answer it again with /commandeck:setup')
    return got


def main_archive(worktree, unit, given=None):
    """Where merge-unit-local.sh files the unit's brief files: ~/.commandeck/briefs/<project>/<unit>.tar,
    <project> being the main checkout's folder name as hooks/lib/project.sh makes it (PP_PROJECT)."""
    home = main_checkout(worktree, given)
    if not home:
        return None
    project = re.sub(r'[^A-Za-z0-9_.-]', '-', os.path.basename(home)) or 'unknown'
    return os.path.expanduser(f'~/.commandeck/briefs/{project}/{unit}.tar')


def round_threads(worktree, unit, archive=None):
    """{Codex thread or Claude session id: (round number, pass kind)} from the head of each of the unit's round files.

    The worktree's own files, or, once the merge has archived them and the
    worktree is gone, the ones in the archive.
    """
    texts = {}
    for f in glob.glob(f'{glob.escape(worktree)}/.claude/briefs/{glob.escape(unit)}-r*-reports.md'):
        with open(f, errors='replace') as fh:
            texts[os.path.basename(f)] = fh.read()
    if not texts and archive and os.path.exists(archive):
        with tarfile.open(archive) as tar:
            for member in tar.getmembers():
                if member.isfile() and member.name.endswith('-reports.md'):
                    texts[member.name] = tar.extractfile(member).read().decode(errors='replace')
    out = {}
    for name, text in texts.items():
        m = re.fullmatch(re.escape(unit) + r'-r(\d+)-reports\.md', name)
        if not m:
            continue  # another unit whose name starts with this one's
        # builder-codex-pass.sh writes the threads (or a Claude reviewer's sessions) and the kind before the first blank line.
        head = text.split('\n\n', 1)[0]
        kind = re.search(r'^Pass: (\S+)$', head, re.M)
        for tid in re.findall(r'^(?:Codex thread|Claude session): ([A-Za-z0-9-]+)$', head, re.M):
            out[tid] = (int(m.group(1)), kind.group(1) if kind else 'review')
    return out


def reviewed_tree(worktree, unit):
    """True when the worktree is still the tree its newest pass read, False when not, None when it is gone.

    The one fact is reviewed-tree.sh's; the dashboard's step strip reads the same script.
    A worktree that is there and cannot be compared (a round file that names no
    commit) is False: "unchanged" is said only on proof, or for a merged build
    whose worktree no longer exists.
    """
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'scripts', 'reviewed-tree.sh')
    said = subprocess.run(['bash', script, worktree, unit], capture_output=True, text=True).stdout.strip()
    return {'true': True, 'false': False}.get(said, False if os.path.isdir(worktree) else None)


def lines_changed(worktree):
    """The build's lines changed: insertions plus deletions of HEAD against its fork from main, .claude/briefs/ left out.

    builder-codex-pass.sh's build_size counts a first pass's commit the same way. None when the worktree is gone.
    """
    def git(*args):
        done = subprocess.run(['git', '-C', worktree, *args], capture_output=True, text=True)
        return done.stdout if done.returncode == 0 else None
    base = git('merge-base', 'main', 'HEAD')
    stat = base and git('diff', '--numstat', '--no-renames', '--no-ext-diff', '--no-textconv', base.strip(), 'HEAD', '--', '.', ':(exclude).claude/briefs')
    # A file git gives no count for (binary, or marked -diff) adds nothing here; the pass counts such files apart.
    return None if stat is None else sum(int(count) for row in stat.splitlines() for count in row.split('\t')[:2] if count.isdigit())


def closing_skipped(passes, unchanged=None):
    """'skipped, unchanged since pass N' when the build's last pass is a first pass that ended GO.

    That GO merges with no closing pass, while the tree is the one it read:
    `unchanged` is reviewed_tree()'s answer. With the worktree gone it
    is None, and a Codex run after that pass that no round file names (a pass
    that committed, then died before its file) is taken as a change.
    """
    last = max((p for p in passes if p['n']), key=lambda p: p['n'], default=None)
    if not last or last['kind'] != 'adversarial' or last['verdict'] != 'GO' or unchanged is False:
        return None
    if unchanged is None and any(not p['n'] and p.get('start', 0) > last.get('start', 0) for p in passes):
        return None
    return f'skipped, unchanged since pass {last["n"]}'


def closing_pass(passes, unchanged=None):
    """The build's closing passes as they happened: each one's number and verdict, then every pass after the last.

    The skip line when the first pass's GO merged, 'none ran' for a build that
    had passes and no closing one, None for a build with no pass at all.
    """
    ran = sorted((p['n'], p['verdict']) for p in passes if p['n'] and p['kind'] == 'final')
    if ran:
        after = sorted((p['n'], p['kind'], p['verdict']) for p in passes if p['n'] > ran[-1][0])
        return (', '.join(f'pass {n} {verdict}' for n, verdict in ran)
                + ('; after it: ' + ', '.join(f'pass {n} ({kind}) {verdict}' for n, kind, verdict in after) if after else ''))
    return closing_skipped(passes, unchanged) or ('none ran' if any(p['n'] for p in passes) else None)


def number_passes(passes, rounds, launches):
    """Set each run's n and kind from the round file that names one of its threads.

    A Codex run no round file names is not a pass (n 0): a self-test that started
    Codex, or a pass that died before it wrote its file. A worktree with no round
    file at all is not a Builder's, and keeps the launch-line numbers.
    """
    for i, p in enumerate(passes, 1):
        if rounds:
            named = [v for t, v in rounds.items() if t == p.get('sid') or any(f.endswith(f'-{t}.jsonl') for f in p['files'])]
            p['n'], p['kind'] = max(named) if named else (0, 'not a pass')
        else:
            near = [l for l in launches if -5 <= p['start'] - l[0] <= 180]
            p['n'], p['kind'] = (near[-1][1], near[-1][2]) if near else (i, 'review')


def review_flag(passes, max_min):
    """The flag line when the passes' Codex review time, added up, is over max_min minutes; else None."""
    mins = sum(p['end'] - p['start'] - p.get('cut_s', 0) for p in passes if p['n']) / 60
    return f'{mins:.0f} minutes of Codex review in total (more than {max_min:.0f})' if mins > max_min else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('worktree')
    ap.add_argument('--out')
    ap.add_argument('--session')
    ap.add_argument('--split', action='append', default=[])
    ap.add_argument('--test-regex', default=TEST_RE)
    ap.add_argument('--exclude', action='append', default=[], metavar='START=END')
    # The project's main checkout, read for its decisions and round archive once the worktree is removed.
    ap.add_argument('--main')
    # A run past any of these is flagged on its page for a written review.
    # Not given: the project's own (loop_limits).
    ap.add_argument('--max-review-min', type=float)
    ap.add_argument('--max-test-share', type=float)
    ap.add_argument('--max-usd', type=float)
    a = ap.parse_args()
    wt = a.worktree.rstrip('/')
    limits = loop_limits(main_checkout(wt, a.main))
    for k, v in zip(('max_review_min', 'max_test_share', 'max_usd'), limits):
        if getattr(a, k) is None:
            setattr(a, k, v)
    unit = os.path.basename(wt)
    home = main_checkout(wt, a.main)
    # The folder review.py and the skill read: <project>/<unit>; a project nothing names (worktree gone, no --main) has none.
    out = a.out or os.path.join(OUT_ROOT, *([os.path.basename(home)] if home else []), unit)
    os.makedirs(out, exist_ok=True)
    test_re = re.compile(a.test_regex, re.I)
    cuts = []
    for spec in a.exclude:
        try:
            start, end = (ts(x) for x in spec.split('=', 1))
        except ValueError:
            ap.error(f'--exclude {spec}: want START=END, ISO UTC')
        if end <= start:
            ap.error(f'--exclude {spec}: END is not after START')
        cuts.append({'start': start, 'end': end, 'reason': 'by hand'})

    proj =os.path.expanduser('~/.claude/projects/') + re.sub(r'[^A-Za-z0-9]', '-', wt)
    files = sorted(f for f in glob.glob(proj + '/*.jsonl') if not a.session or os.path.basename(f).startswith(a.session))
    sessions = sorted((read_session(f) | {'id': os.path.basename(f)[:8], 'name': os.path.basename(f)[:-6], 'ledger': session_ledger(f)} for f in files), key=lambda s: s['first'])
    passes = []
    if sessions:
        t0, t1 = sessions[0]['first'], max(s['last'] for s in sessions)
        for day in codex_days(t0, t1):
            for f in glob.glob(os.path.expanduser(f'~/.codex/sessions/{day}/*.jsonl')):
                p = read_codex(f, wt)
                if p and p['start'] and t0 - 60 <= p['start'] <= t1 + 60:
                    passes.append(p)
    else:
        # A worktree a Codex seat built alone: its Codex records are the run, whatever day they are filed under.
        passes = [p for f in glob.glob(os.path.expanduser('~/.codex/sessions/*/*/*/*.jsonl')) for p in [read_codex(f, wt)] if p and p['start']]
        if not passes:
            raise SystemExit(f'no Claude session log under {proj} and no Codex session of {wt}')
        t0, t1 = min(p['start'] for p in passes), max(p['end'] for p in passes)
    rounds = round_threads(wt, unit, main_archive(wt, unit, a.main))
    passes = fold_passes(passes, rounds)
    # A Claude reviewer ran in the Builder's worktree: its log is already in `sessions`, which counts its tokens and cost
    # once, so its pass carries none of its own.
    for sess in sessions:
        if sess['name'] in rounds:
            verdict = re.findall(r'VERDICT:\s*(NO-GO|GO)', sess['final'])
            passes.append({'file': sess['name'], 'files': [], 'sid': sess['name'], 'start': sess['first'], 'end': sess['last'], 'complete': True,
                           'usage': {}, 'calls': 0, 'model': next((m for _, _, m in sess['usage'].values() if m), None), 'effort': None,
                           'message': sess['final'], 'rows': [], 'threads': 1, 'verdict': verdict[-1] if verdict else 'none',
                           'findings': len(re.findall(r'^\s*(?:[-*]\s*)?\[P[0-3]\]', sess['final'], re.M))})
    passes.sort(key=lambda p: p['start'])
    for p in passes:
        # command_s and longest are worked out once the cut windows are known.
        p['spans'] = [x for f in p['files'] for x in codex_commands(f)]
        p['commands'] = len(p['spans'])
    launches = sorted((tool['t'], int(m.group(1)), m.group(2)) for s in sessions for tool in s['tools'].values()
                      for m in [PASS_CMD.search(tool['cmd'])] if m)
    # `runs` is every Codex run of the worktree, so each one's time and tokens stay on the page;
    # `passes` is the ones a round file names, which is what the page counts and numbers.
    runs = passes
    number_passes(runs, rounds, launches)
    passes = [p for p in runs if p['n']]

    # Stages: build, then each Codex pass and the fixing between passes; --split refines them.
    stages = []
    cursor = t0
    done = 0  # passes so far: the work before the first one is the build, after it a fix round
    for p in runs:
        s, e = max(p['start'], cursor), max(p['end'], cursor)
        if s > cursor:
            stages.append([cursor, f'Fix round {done}' if done else 'Build', 'fix' if done else 'build'])
        stages.append([s, f'Codex pass {p["n"]} ({p["kind"]})' if p['n'] else 'Codex run outside a pass', 'codex'])
        done += bool(p['n'])
        cursor = e
    if cursor < t1:
        stages.append([cursor, 'Wrap-up' if done else 'Build', 'build'])
    day0 = datetime.fromtimestamp(t0, timezone.utc)
    for spec in a.split:
        when, label = spec.split('=', 1)
        t = ts(when) if 'T' in when else ts(day0.strftime('%Y-%m-%dT') + when + 'Z')
        if 'T' not in when and t < t0 - 3600:
            t += 86400
        if t <= t0 + 60:
            stages[0][1] = label
        else:
            stages.append([t, label, 'build'])
    stages.sort(key=lambda s: s[0])
    stages = [{'code': chr(65 + i) if i < 26 else f'S{i}', 'name': s[1], 'kind': s[2], 'start': s[0],
               'end': stages[i + 1][0] if i + 1 < len(stages) else t1} for i, s in enumerate(stages)]

    def stage_of(t):
        for s in stages:
            if s['start'] <= t < s['end']:
                return s
        return stages[-1] if t >= stages[-1]['start'] else stages[0]

    for s in stages:
        s.update(builder=collections.Counter(), advisor=collections.Counter(), helper=collections.Counter(),
                 codex=collections.Counter(), clock=collections.Counter(), context=[], cut_s=0,
                 detail={'commands': [], 'edits': collections.Counter(), 'notes': [], 'blocked': collections.Counter()})
    models, ctx = collections.Counter(), []
    for sess in sessions:
        for when, u, model in sess['usage'].values():
            st = stage_of(when)
            its = [i for i in u.get('iterations') or [] if i.get('type') == 'message'] or [u]
            add(st['builder'], own_usage(u), model, calls=len(its))
            models[model] += len(its)
            sizes = [(i.get('input_tokens') or 0) + (i.get('cache_read_input_tokens') or 0) + (i.get('cache_creation_input_tokens') or 0) for i in its]
            ctx += sizes
            st['context'] += sizes
            # The advisor's tokens are logged beside the call that asked, outside that call's own totals.
            for i in u.get('iterations') or []:
                if i.get('type') == 'advisor_message':
                    add(st['advisor'], i, i.get('model'))
                    st['advisor']['model:' + str(i.get('model'))] += 1

    helpers = []
    for f in sorted(glob.glob(proj + '/*/subagents/agent-*.jsonl')):
        if a.session and not os.path.basename(os.path.dirname(os.path.dirname(f))).startswith(a.session):
            continue
        meta_file = f.replace('.jsonl', '.meta.json')
        meta = json.load(open(meta_file)) if os.path.exists(meta_file) else {}
        usage, first, last, model, chars, compactions = {}, None, None, None, 0, 0
        for e in rows_of(f):
            compactions += compaction_of(e) is not None
            if e.get('timestamp'):
                first, last = first or ts(e['timestamp']), ts(e['timestamp'])
            if e.get('type') == 'assistant':
                m = e.get('message') or {}
                usage[m.get('id')] = (usage.get(m.get('id'), (ts(e['timestamp']),))[0], m.get('usage') or {}, m.get('model'))
                model = m.get('model') or model
                chars += sum(len(json.dumps(b)) for b in m.get('content') or [])
        total = collections.Counter()
        for when, u, call_model in usage.values():
            add(stage_of(when)['helper'], u, call_model)
            add(total, u, call_model)
        own = session_ledger(f)
        helpers.append({'what': meta.get('description'), 'type': meta.get('agentType'), 'model': model, 'start': first,
                        'seconds': (last or 0) - (first or 0), 'tokens': dict(total), 'content_chars': chars, 'compactions': compactions,
                        # Spans, not totals: claude_s and tool_s are summed once the cut windows are known.
                        'claude_s': [(r['start'], r['end']) for r in own['requests'].values()],
                        'tool_s': [(t['start'], t['end']) for t in own['tools'].values() if t['end']]})

    for p in runs:
        st = stage_of((p['start'] + p['end']) / 2)
        u = p['usage']
        cached = u.get('cached_input_tokens') or 0
        # Priced response by response, as the dashboard prices them: the long-prompt rate
        # is per prompt, so the run's token totals cannot be priced in one go. A response the table
        # has no price for, or one whose record cannot be used, stays unpriced.
        costs = [(r, PRICES.price(r) if PRICES and r else None) for r in p['rows']]
        priced = [(r, c) for r, c in costs if c is not None]
        st['codex'].update({'calls': p['calls'], 'in': (u.get('input_tokens') or 0) - cached, 'cr': cached,
                            'out': u.get('output_tokens') or 0, 'usd': sum(c for _, c in priced),
                            'est': sum(c for r, c in priced if PRICES.estimated(r)),
                            'tier': sum(c for r, c in priced if PRICES.by_tier(r)),
                            'unpriced': max(p['calls'], len(costs)) - len(priced)})

    def kind_of(t):
        return call_kind(t, test_re)

    # One label per tenth of a second of the run, highest priority last. What the agent itself is
    # doing wins over what it is waiting for, so "codex" and the idle labels are pure waiting.
    label = ['none'] * int((t1 - t0) * TICK)

    def paint(start, end, what, only=None):
        for i in range(max(int((start - t0) * TICK), 0), min(int((end - t0) * TICK), len(label))):
            if only is None or label[i] in only:
                label[i] = what

    idle_gaps, jobs = [], []
    # No checkout found, no ledger: never one relative to wherever this runs.
    home = main_checkout(wt, a.main)
    asked = decisions_for(DECISIONS or (os.path.join(home, '.claude', 'metrics', 'decisions.jsonl') if home else ''), unit)
    for sess in sessions:
        paint(sess['first'], sess['last'], 'gap')
    for sess in sessions:
        for end in sess['turn_ends']:
            nxt = min((u for u in sess['users'] if u > end), default=None)
            if nxt and nxt - end > 5:
                waited, gap = idle_gap(sess, end, nxt, t1, kind_of, runs)
                paint(end, nxt, waited, only=('gap',))
                idle_gaps.append(gap)
                # Waiting on the owner, with nothing of the build's own running: only the part inside an open
                # decision window, never idle after DONE by itself. A background job of ANY session, or a
                # Codex run, still going keeps the gap build time; idle_gap's `pending` sees only this session's.
                busy = any(t['bg'] and t['t'] < nxt and other['woken'].get(k, t1) > end for other in sessions for k, t in other['tools'].items())
                if nxt - end > WAIT_ON_OWNER and not busy and not any(p['start'] < nxt and p['end'] > end for p in runs):
                    cuts += [{'start': max(q, end), 'end': min(r or nxt, nxt), 'reason': f'decision {i}'}
                             for q, r, i in asked if max(q, end) < min(r or nxt, nxt)]
    for p in runs:
        # With no Claude session nothing paints "gap": a Codex seat that built alone owns its own time.
        paint(p['start'], p['end'], 'codex', only=('gap',) + IDLE + REVIEW_WAIT + (() if sessions else ('none',)))
    not_codex = ('none', 'gap', 'claude', 'hooks', 'hooks_stop', 'tests', 'commands', 'files', 'tools', 'helper', 'compaction') + IDLE + REVIEW_WAIT
    for sess in sessions:
        led = sess['ledger']
        for r in led['requests'].values():
            paint(r['start'], r['end'], 'claude')
        for h in led['hooks']:
            if h['event'] == 'Stop':
                paint(h['t'] - h['s'], h['t'], 'hooks_stop')
            elif h['event'] == 'SessionStart':
                paint(h['t'] - h['s'], h['t'], 'hooks', only=('gap',))
        for t in led['tools'].values():
            if t['end'] is None:
                continue
            kind = kind_of(t)
            ran_from, ran_to = t['start'] + t['pre'], t['end'] - t['post']
            paint(t['start'], ran_from, 'hooks')
            # A command that waits on Codex keeps the seconds the Codex record itself covers.
            on_codex = t['name'] == 'Bash' and re.search(r'codex', t['desc'] + ' ' + t['cmd'][:200], re.I)
            paint(ran_from, ran_to, 'commands' if kind == 'codex' else kind, only=not_codex if on_codex else None)
            paint(ran_to, t['end'], 'hooks')
    for sess in sessions:
        for when, text in sess['notes']:
            stage_of(when)['detail']['notes'].append([when, text[:200]])
        for b in sess['blocked']:
            stage_of(b[0])['detail']['blocked'][refusal(b)] += 1
        for k, t in sess['tools'].items():
            detail = stage_of(t['t'])['detail']
            if t['name'] in EDIT_TOOLS:
                detail['edits'][os.path.basename(t['desc'])] += 1
                continue
            kind = kind_of(t)
            end = sess['woken'].get(k) if t['bg'] else sess['results'].get(k)
            if end and end - t['t'] >= 15:
                detail['commands'].append({'start': t['t'], 'seconds': end - t['t'], 'what': t['desc'][:120] or t['name'],
                                           'kind': kind, 'background': t['bg'], 'outcome': sess['outcome'].get(k, '')})
            if t['bg'] and end:
                jobs.append({'what': t['desc'][:100], 'start': t['t'], 'seconds': end - t['t'], 'kind': kind})
        for c in sess['compactions']:
            paint(c['start'], c['end'], 'compaction')
    # Painted last and counted nowhere, so windows that overlap cut each second once. A window found
    # in a gap cuts only its idle seconds: another session's work in it is still build time.
    for w in sorted(cuts, key=lambda w: w['reason'] == 'by hand'):
        paint(w['start'], w['end'], 'cut', only=None if w['reason'] == 'by hand' else ('idle',))

    def cut_in(start, end):
        return label[max(int((start - t0) * TICK), 0):max(int((end - t0) * TICK), 0)].count('cut') / TICK

    # Every duration the page shows loses the seconds cut from it, not only the clock.
    for x in idle_gaps + runs:
        x['cut_s'] = round(cut_in(x['start'], x['end']), 1)
    for x in jobs + helpers + [c for s in stages for c in s['detail']['commands']]:
        if x['start'] is not None:
            x['seconds'] -= cut_in(x['start'], x['start'] + x['seconds'])
    for h in helpers:
        for k in ('claude_s', 'tool_s'):
            h[k] = r2(sum(e - s - cut_in(s, e) for s, e in h[k]))
    for p in passes:
        # Threads run side by side, so their command seconds can add up to more than the pass took.
        ran = [(sec - (cut_in(end - sec, end) if end else 0), cmd) for sec, cmd, end in p.pop('spans')]
        p['command_s'], p['longest'] = r2(sum(sec for sec, _ in ran)), sorted(ran, reverse=True)[:5]
    clock, cut_s = collections.Counter(), 0
    for i, what in enumerate(label):
        st = stage_of(t0 + i / TICK)
        if what == 'cut':
            st['cut_s'] += 1 / TICK
            cut_s += 1 / TICK
            continue
        st['clock'][what] += 1 / TICK
        clock[what] += 1 / TICK

    # The granular ledger: one row per model request and one per tool call, for the page's two timing sections.
    requests, calls, hook_runs, counters = [], [], collections.defaultdict(list), collections.Counter()
    for sess in sessions:
        led = sess['ledger']
        counters.update(led['counters'])
        for h in led['hooks']:
            hook_runs[(h['event'], h['name'])].append(h['s'] - cut_in(h['t'] - h['s'], h['t']))
        for r in led['requests'].values():
            u = r['usage']
            did = [led['tools'][k] for k in r['tools']]
            sizes = [(i.get('input_tokens') or 0) + (i.get('cache_read_input_tokens') or 0) + (i.get('cache_creation_input_tokens') or 0)
                     for i in [i for i in u.get('iterations') or [] if i.get('type') == 'message'] or [u]]
            look = len(did) == 1 and (did[0]['name'] in ('Read', 'Glob', 'Grep') or (
                did[0]['name'] == 'Bash' and bool(LOOK.search(did[0]['cmd'])) and not WRITES.search(did[0]['cmd'])))
            # The wait ran until the model began, each thinking block in the seconds before it: each loses its own cut.
            began = None if r['think0'] is None else r['first'] - r['think0']
            requests.append({'t': r2(r['start']), 's': r2(r['end'] - r['start'] - cut_in(r['start'], r['end'])),
                             'think': r2(r['think'] - sum(cut_in(t - d, t) for t, d in r['thinks'])),
                             'wait': None if began is None else r2(max(began - r['start'] - cut_in(r['start'], began), 0)),
                             'out': u.get('output_tokens') or 0, 'ctx': max(sizes), 'cw': u.get('cache_creation_input_tokens') or 0,
                             'in': cache_counts(u)[0], 'cr': cache_counts(u)[1],
                             'usd': r2(usd(r['model'], u)), 'model': r['model'], 'stage': stage_of(r['start'])['code'], 'session': sess['id'],
                             'tools': [d['name'] for d in did], 'look': look, 'advisor': r['advisor'],
                             'what': (did[0]['desc'] or did[0]['cmd'] or did[0]['name'])[:110] if did else 'wrote a note' if r['text'] else 'thinking only'})
        for k, t in led['tools'].items():
            if t['end'] is not None:
                ran_from, ran_to = t['start'] + t['pre'], t['end'] - t['post']
                calls.append({'t': r2(t['start']), 's': r2(t['end'] - t['start'] - cut_in(t['start'], t['end'])),
                              'pre': r2(t['pre'] - cut_in(t['start'], ran_from)), 'run': r2(t['run'] - cut_in(ran_from, ran_to)),
                              'post': r2(t['post'] - cut_in(ran_to, t['end'])),
                              'name': t['name'], 'kind': kind_of(t), 'what': (t['desc'] or t['name'])[:110], 'cmd': t['cmd'][:300],
                              'bg': t['bg'], 'timeout': t['timeout'], 'refused': t['refused'], 'outcome': sess['outcome'].get(k, ''),
                              'stage': stage_of(t['start'])['code']})
    timing = {'requests': sorted(requests, key=lambda r: r['t']), 'tools': sorted(calls, key=lambda c: c['t']),
              'hooks': sorted(({'event': e, 'name': n, 'runs': len(v), 'total': r2(sum(v)), 'median': r2(statistics.median(v)), 'max': r2(max(v))}
                               for (e, n), v in hook_runs.items()), key=lambda h: -h['total']),
              'counters': {k: r2(v) for k, v in counters.items()}}

    blocked = collections.Counter(refusal(b) for sess in sessions for b in sess['blocked'])
    total = {k: collections.Counter() for k in ('builder', 'advisor', 'helper', 'codex')}
    for s in stages:
        for k in total:
            total[k].update({kk: v for kk, v in s[k].items() if kk in KEYS})
        sizes = s.pop('context')
        s['context'] = {'mean': sum(sizes) // max(1, len(sizes)), 'peak': max(sizes, default=0)}
        d = s['detail']
        d['commands'] = sorted(d['commands'], key=lambda c: -c['seconds'])[:10]
        d['edits'], d['blocked'] = dict(d['edits'].most_common()), dict(d['blocked'])
        d['notes'] = d['notes'][:12]
        for k in ('builder', 'advisor', 'helper', 'codex'):
            s[k] = dict(s[k])
        s['clock'] = {k: round(v, 1) for k, v in s['clock'].items()}
        s['cut_s'] = round(s['cut_s'], 1)
    waited = clock['tests'] + sum(clock[k] for k in IDLE)
    waiting = waited / max(1, t1 - t0 - cut_s)
    priced = sum(v['usd'] for v in total.values())
    flags = []
    if review_flag(passes, a.max_review_min):
        flags.append(review_flag(passes, a.max_review_min))
    if waiting > a.max_test_share and waited > SHARE_FLOOR:
        big = max((c for s in stages for c in s['detail']['commands'] if c['kind'] in ('tests', 'commands', 'codex')),
                  key=lambda c: c['seconds'], default=None)
        flags.append(f'{100 * waiting:.0f}% of the clock on tests or idle waits (more than {100 * a.max_test_share:.0f}% and {SHARE_FLOOR // 60} minutes)'
                     + (f'; largest single command: "{big["what"]}", {hm(big["seconds"])}' if big else ''))
    if priced > a.max_usd:
        flags.append(f'${priced:,.2f} at list price (more than ${a.max_usd:,.0f})')
    result = {
        'flags': flags,
        'unit': unit, 'worktree': wt, 'start': t0, 'end': t1, 'sessions': [{'id': s['id'], 'start': s['first'], 'end': s['last']} for s in sessions],
        'builder_models': dict(models), 'stages': stages, 'priced': PRICES is not None,
        'totals': {k: dict(v) for k, v in total.items()}, 'clock': {k: round(v, 1) for k, v in clock.items()}, 'timing': timing,
        'context': {'peak': max(ctx, default=0), 'mean': sum(ctx) // max(1, len(ctx)), 'calls': len(ctx)},
        'compactions': [c for s in sessions for c in s['compactions']], 'idle_gaps': idle_gaps, 'background_jobs': jobs,
        'helpers': helpers, 'blocked': dict(blocked), 'closing_pass': closing_pass(runs, reviewed_tree(wt, unit)),
        'lines_changed': lines_changed(wt),
        'cut': sorted(({'start': max(w['start'], t0), 'end': min(w['end'], t1), 'seconds': cut_in(w['start'], w['end']), 'reason': w['reason']}
                       for w in cuts if cut_in(w['start'], w['end'])), key=lambda w: w['start']),
        'cut_s': round(cut_s, 1),
        'passes': [{k: p[k] for k in ('n', 'kind', 'start', 'end', 'complete', 'model', 'effort', 'verdict', 'findings', 'usage', 'calls', 'threads',
                                      'commands', 'command_s', 'longest', 'cut_s', 'message')} for p in passes],
    }
    json.dump(result, open(f'{out}/result.json', 'w'), indent=1)
    with open(f'{out}/notes.txt', 'w') as fh:
        for sess in sessions:
            for when, text in sess['notes']:
                fh.write(f'{datetime.fromtimestamp(when, timezone.utc):%H:%M:%S} {text}\n')

    print(f'{unit}: {hm(t1 - t0)} from {datetime.fromtimestamp(t0, timezone.utc):%Y-%m-%d %H:%M:%S}Z, {len(sessions)} session(s), {len(passes)} Codex pass(es)'
          f', {len(runs) - len(passes)} Codex run(s) outside a pass')
    for s in stages:
        b = s['builder']
        cost = sum(s[k].get('usd', 0) for k in ('builder', 'advisor', 'helper'))
        print(f"  {s['code']} {datetime.fromtimestamp(s['start'], timezone.utc):%H:%M:%S} {hm(s['end'] - s['start'] - s['cut_s']):>7}  {s['name'][:44]:44} "
              f"calls {b.get('calls', 0):>3}  read {b.get('cr', 0):>11,}  out {b.get('out', 0):>7,}  ${cost:>7.2f}")
    for k, v in total.items():
        price = f"${v['usd']:,.2f}" + (f" (+{v['unpriced']} unpriced calls)" if v['unpriced'] else '') if v['usd'] else 'no list price on file'
        print(f"  {k:8} calls {v['calls']:>4}  uncached {v['in']:>10,}  write {v['cw']:>10,}  read {v['cr']:>11,}  out {v['out']:>8,}  {price}")
    print('  clock:', {k: hm(v) for k, v in clock.most_common()})
    print(f'  cut from the clock, waiting on the owner: {hm(cut_s)}', [(w['reason'], hm(w['seconds'])) for w in result['cut']])
    print('  passes (number, kind, time, verdict, findings, threads):',
          [(p['n'], p['kind'], hm(p['end'] - p['start']), p['verdict'], p['findings'], p['threads']) for p in passes])
    print('  lines changed:', result['lines_changed'])
    print('  context:', result['context'], '| compactions:', [(c['before'], c['after']) for c in result['compactions']])
    print('  blocked by guards:', dict(blocked), '| idle gaps:', [(hm(g['end'] - g['start']), g['pending'][:1]) for g in idle_gaps])
    print('  flags:', flags or 'none')
    print(f'  wrote {out}/result.json and {out}/notes.txt')


if __name__ == '__main__':
    main()

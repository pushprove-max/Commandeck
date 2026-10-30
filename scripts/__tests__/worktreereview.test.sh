#!/usr/bin/env bash
# The build review's numbers, from small session and Codex logs under a pretend
# home. What this pins: a wait on a review pass run outside the Builder's
# session, or on a review tool that is down, is its own bucket and flags
# nothing (#55); the share-of-clock flag needs 10 minutes of tests and idle
# waits and names the largest command (#63); a pass keeps its whole text and the
# page lists the passes after the closing one (#64); idle after DONE stays on
# the clock unless an owner decision is open (#70); Claude Code 2.1.300's
# api-request rows are neither counted nor parsed (#71); a result saved before
# idle gaps recorded what they waited on still renders (#16); a written review
# marks each "Where it could shrink" item, and an unmarked one is named.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
python3 - "$ROOT/skills/worktreereview/scripts" "$T" <<'PY'
import contextlib, io, itertools, json, math, os, re, subprocess, sys
from datetime import datetime, timezone
HERE, TMP = sys.argv[1], sys.argv[2]
os.environ['HOME'] = TMP + '/home'
# The session records are the fixture's, under HOME: a profile's CLAUDE_CONFIG_DIR would be read first.
os.environ.pop('CLAUDE_CONFIG_DIR', None)
sys.path.insert(0, HERE)
import collect

failed = passed = 0
def check(name, want, got):
    global failed, passed
    ok = want == got
    failed += not ok
    passed += ok
    print(('ok   ' if ok else 'FAIL ') + name + ('' if ok else f' (expected {want!r}, got {got!r})'))

T0 = 1791633600  # 2026-10-10T12:00:00Z
def at(s):
    return datetime.fromtimestamp(T0 + s, timezone.utc).isoformat().replace('+00:00', 'Z')
USAGE = {'input_tokens': 1000, 'output_tokens': 100, 'cache_creation_input_tokens': 0, 'cache_read_input_tokens': 0}
ids = itertools.count()
def reply(s, *blocks):
    i = next(ids)
    return {'type': 'assistant', 'timestamp': at(s), 'requestId': f'r{i}',
            'message': {'id': f'm{i}', 'model': 'claude-opus-5-5', 'usage': USAGE, 'content': list(blocks)}}
def say(s, text):
    return reply(s, {'type': 'text', 'text': text})
def bash(s, tid, cmd, desc):
    return reply(s, {'type': 'tool_use', 'id': tid, 'name': 'Bash', 'input': {'command': cmd, 'description': desc}})
def result(s, tid, body='ok', error=False):
    return {'type': 'user', 'timestamp': at(s), 'message': {'role': 'user', 'content': [
        {'type': 'tool_result', 'tool_use_id': tid, 'content': body, 'is_error': error}]}}
def user(s):
    return {'type': 'user', 'timestamp': at(s), 'message': {'role': 'user', 'content': 'go on'}}
def turn_end(s):
    return {'type': 'system', 'subtype': 'turn_duration', 'timestamp': at(s)}
def write(path, rows):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(''.join(r if isinstance(r, str) else json.dumps(r) + '\n' for r in rows))
def codex(wt, tid, start, end, message):
    write(f'{TMP}/home/.codex/sessions/2026/10/10/rollout-2026-10-10T12-00-00-{tid}.jsonl', [
        {'timestamp': at(start), 'type': 'turn_context', 'payload': {'cwd': wt, 'model': 'gpt-5.5', 'effort': 'high'}},
        {'timestamp': at(end - 1), 'type': 'event_msg', 'payload': {'type': 'token_count', 'info': {'total_token_usage': {
            'input_tokens': 1000, 'cached_input_tokens': 0, 'output_tokens': 100}}}},
        {'timestamp': at(end), 'type': 'event_msg', 'payload': {'type': 'task_complete', 'last_agent_message': message}}])
def collected(unit, rows, *args):
    """collect.py run on one session log of the worktree <TMP>/ws/<unit> -> its result.json."""
    wt = f'{TMP}/ws/{unit}'
    write(f'{TMP}/home/.claude/projects/{re.sub(r"[^A-Za-z0-9]", "-", wt)}/s1.jsonl', rows)
    sys.argv = ['collect.py', wt, '--out', f'{TMP}/out/{unit}', *args]
    with contextlib.redirect_stdout(io.StringIO()):
        collect.main()
    return json.load(open(f'{TMP}/out/{unit}/result.json'))
def rendered(unit, r):
    json.dump(r, open(f'{TMP}/out/{unit}/result.json', 'w'))
    done = subprocess.run([sys.executable, f'{HERE}/render.py', f'{TMP}/out/{unit}/result.json', f'{TMP}/out/{unit}/page.html'],
                          capture_output=True, text=True)
    return open(f'{TMP}/out/{unit}/page.html').read() if done.returncode == 0 else done.stderr
SHARE = 'of the clock on tests or idle waits'

# --- #55: the owner runs the pass from outside the Builder's session; the Builder waits 25 minutes. ---
elsewhere = [user(0), say(10, 'Ready for the first pass.'), turn_end(12), user(1500), say(1510, 'Fixed.'), turn_end(1512)]
codex(f'{TMP}/ws/elsewhere', 'tid-elsewhere', 300, 600, 'VERDICT: GO')
r = collected('elsewhere', elsewhere)
check('a wait on a pass run outside the session is waiting on a review run elsewhere', ['elsewhere'], [g['waiting'] for g in r['idle_gaps']])
check('and is its own slice of the clock, not idle', (1188, 0), (round(r['clock'].get('idle_elsewhere', 0)), round(r['clock'].get('idle', 0))))
check('and trips no share flag', [], [f for f in r['flags'] if SHARE in f])
page = rendered('elsewhere', r)
check('the page shows the wait as a review run elsewhere', True, 'Idle, waiting on a review run outside this session' in page)

# The pass script cannot reach the reviewer; the Builder waits out the outage.
PASS = 'bash scripts/builder-codex-pass.sh down 1 adversarial'
down = [user(0), bash(10, 't1', PASS, 'first pass'),
        result(40, 't1', 'Exit code 2\nREFUSED: the codex adversarial pass failed for reviewer(s) 1; raw output in /tmp/x', True),
        say(50, 'The review tool is down.'), turn_end(52), user(1400), say(1410, 'Back.'), turn_end(1412)]
r = collected('down', down)
check('a wait after the pass script could not reach the reviewer is waiting on a review tool that is down', ['down'], [g['waiting'] for g in r['idle_gaps']])
check('and is its own slice of the clock, flagging nothing', (1348, []), (round(r['clock'].get('idle_down', 0)), [f for f in r['flags'] if SHARE in f]))
# A pass runs in the background: its launch answers with a job id, and the REFUSED line comes back later,
# through the job tool, a Read of the job's output file, or a cat of it (the end notice carries no output).
OUT = '/tmp/tasks/bp1.output'
REFUSED = 'Exit code 2\nREFUSED: the codex adversarial pass failed for reviewer(s) 1; raw output in /tmp/x'
for how, name, args, body in (('the job tool', 'TaskOutput', {'task_id': 'bp1'}, f'<task_id>bp1</task_id><status>failed</status><output>{REFUSED}</output>'),
                              ('a Read of its output file', 'Read', {'file_path': OUT}, REFUSED),
                              ('a cat of its output file', 'Bash', {'command': f'cat {OUT}', 'description': 'read the pass output'}, REFUSED)):
    bg = [user(0), reply(10, {'type': 'tool_use', 'id': 'toolu_p1', 'name': 'Bash', 'input': {'command': PASS, 'description': 'first pass', 'run_in_background': True}}),
          result(11, 'toolu_p1', f'Command running in background with ID: bp1. Output is being written to: {OUT}'), turn_end(13),
          {'type': 'user', 'timestamp': at(40), 'message': {'role': 'user', 'content': '<task-notification><task-id>bp1</task-id>'
           f'<tool-use-id>toolu_p1</tool-use-id><output-file>{OUT}</output-file><status>failed</status></task-notification>'}},
          reply(45, {'type': 'tool_use', 'id': 'toolu_r1', 'name': name, 'input': args}), result(46, 'toolu_r1', body),
          say(50, 'The review tool is down.'), turn_end(52), user(1400), say(1410, 'Back.'), turn_end(1412)]
    r = collected('down-bg', bg)
    check(f'a background pass whose REFUSED line comes back through {how} is a wait on a review tool that is down, flagging nothing',
          (['codex', 'down'], 1348, []), ([g['waiting'] for g in r['idle_gaps']], round(r['clock'].get('idle_down', 0)), [f for f in r['flags'] if SHARE in f]))

# --- #63: a 7-minute build with two one-minute test runs and a short idle wait. ---
short = [user(0), bash(10, 'a', 'npm test', 'run the tests'), result(70, 'a'), bash(80, 'b', 'npm test', 'run the tests'), result(140, 'b'),
         say(150, 'Waiting.'), turn_end(152), user(232), say(240, 'Done.'), turn_end(420)]
r = collected('short', short)
check('a 7-minute build with two one-minute test runs is not flagged', [], [f for f in r['flags'] if SHARE in f])
long_run = [user(0), bash(10, 'a', 'npm test', 'run the tests (whole suite)'), result(790, 'a'), say(800, 'Green.'), turn_end(1800)]
r = collected('long', long_run)
flag = next((f for f in r['flags'] if SHARE in f), '')
check('13 minutes of tests in a 30-minute build is flagged and names its largest command',
      (True, True), (flag.startswith('43% '), '"run the tests (whole suite)", 13:00' in flag))
box = re.search(r'<div class="box flag">.*?</div>', rendered('long', r))
check("and the flagged page's flag box names it", True, bool(box) and '&quot;run the tests (whole suite)&quot;, 13:00' in box.group())

# --- issue 262: a Monitor call is a background job like a Bash one: a wait on one that runs the tests is test time. ---
for label, cmd, want in (('runs the shell tests', 'bash scripts/run-shell-tests.sh --changed', 'idle_tests'), ('names no test', 'tail -f /tmp/x.log', 'idle_job')):
    mon = [user(0), reply(10, {'type': 'tool_use', 'id': 'toolu_m1', 'name': 'Monitor', 'input': {'command': cmd, 'description': 'watch it'}}),
           result(11, 'toolu_m1', 'Monitor started (task m1, timeout 600000ms). You will be notified on each event.'), turn_end(13),
           user(900), say(910, 'Done.'), turn_end(912)]
    r = collected('monitor', mon)
    check(f'a wait on a Monitor whose command {label} is {want}', (True, 0), (round(r['clock'].get(want, 0)) > 800, round(r['clock'].get('idle', 0))))

# --- #87: with the review flags off, the build that trips the share flag above is flagged for nothing. ---
os.makedirs(f'{TMP}/main-off/.claude', exist_ok=True)
subprocess.run(['git', 'init', '-q', f'{TMP}/main-off'], check=True)
json.dump({'reviewLoop': {'maxReviewMinutes': 'off', 'maxTestPercent': 'off', 'maxUsd': 'off'}}, open(f'{TMP}/main-off/.claude/commandeck.json', 'w'))
check('review flags set to off raise no flag', [], collected('long-off', long_run, '--main', f'{TMP}/main-off')['flags'])
check('and the setting reads off', (math.inf,) * 3, collect.loop_limits(f'{TMP}/main-off'))

# --- #64: a long pass, and a pass after the closing one. ---
wt = f'{TMP}/ws/passes'
# Findings in each form the merge reads: a '- ' bullet, a '* ' bullet, or none.
long_text = 'Findings follow.\n\n' + ''.join(('- ', '* ', '')[i % 3] + f'[P2] finding {i}: ' + 'x' * 90 + '\n' for i in range(1, 31)) + '\nVERDICT: NO-GO'
for n, kind, tid, start, said in ((1, 'adversarial', 'tid-p1', 100, 'VERDICT: NO-GO'), (2, 'final', 'tid-p2', 300, long_text), (3, 'review', 'tid-p3', 500, 'VERDICT: GO')):
    codex(wt, tid, start, start + 100, said)
    write(f'{wt}/.claude/briefs/passes-r{n}-reports.md', [f'## Sol (gpt-5.5, read-only)\nReviewed: {"a" * 40}\nCodex thread: {tid}\nPass: {kind}\n\n{said}\n'])
passes = [user(0)]
for n, kind, start in ((1, 'adversarial', 100), (2, 'final', 300), (3, 'review', 500)):
    passes += [bash(start - 5, f'p{n}', f'bash scripts/builder-codex-pass.sh passes {n} {kind}', f'pass {n}'), result(start + 105, f'p{n}')]
r = collected('passes', passes + [say(700, 'Done.'), turn_end(710)])
check('a pass keeps its whole text', True, r['passes'][1]['message'].strip().endswith('finding 30: ' + 'x' * 90 + '\n\nVERDICT: NO-GO'))
check('and counts every finding of it, bulleted or not', 30, r['passes'][1]['findings'])
check('the closing-pass field lists the pass after the closing one', 'pass 2 NO-GO; after it: pass 3 (review) GO', r['closing_pass'])
page = rendered('passes', r)
check('the page shows every finding of the long pass, bulleted or not', 30, len(re.findall(r'\[P2\] finding \d+:', page)))
check('and both passes', True, 'pass 2 NO-GO; after it: pass 3 (review) GO' in page)

# --- #70: idle after the Builder's DONE line is cut only where an owner decision is open. ---
main = f'{TMP}/main'
os.makedirs(f'{main}/.claude/metrics')
subprocess.run(['git', 'init', '-q', main], check=True)
finished = [user(0), say(10, 'All built.\nU7-DONE'), turn_end(12), user(1200), say(1210, 'Merged.'), turn_end(1212)]
r = collected('u7', finished, '--main', main)
check('idle after DONE with no open decision stays on the clock', ([], 1188), (r['cut'], round(r['clock'].get('idle', 0))))
write(f'{main}/.claude/metrics/decisions.jsonl', [{'id': 'd1', 'askedAt': at(400), 'answeredAt': None, 'source': 'u7 asks'},
                                                  {'id': 'd1', 'askedAt': at(400), 'answeredAt': at(700), 'answer': 'yes'}])
r = collected('u7', finished, '--main', main)
check('an open decision inside it cuts only the overlap', [(400, 700, 300, 'decision d1')],
      [(round(w['start'] - T0), round(w['end'] - T0), round(w['seconds']), w['reason']) for w in r['cut']])

# --- #71: a 2.1.300 log carries api-request rows beside its assistant rows. ---
API = ('{"type":"api-request-shape","sessionId":"s","shapeHash":"h1","timestamp":"%s","shape":{"system":[]}}\n'
       '{"type":"api-request-blob","sessionId":"s","hash":"b1","message":{"role":"user","content":[{"type":"text","text":"go"}]}}\n'
       '{"type":"api-request","sessionId":"s","id":"a1","timestamp":"%s","params":{"model":"claude-opus-5-5"},"tail":["b1"]}\n')
v300 = [x for row in short for x in ([API % (row['timestamp'], row['timestamp'])] if row['type'] == 'assistant' else []) + [row]]
seen, loads = [], json.loads
json.loads = lambda s, *a, **k: (seen.append(s), loads(s, *a, **k))[1]
new = collected('v300', v300)
json.loads = loads
old = collected('v299', short)
check("the 2.1.300 log's calls and list price are its assistant rows'", (old['totals']['builder'], len(old['timing']['requests'])),
      (new['totals']['builder'], len(new['timing']['requests'])))
check('and none of its api-request rows is parsed', 0, sum(str(s).startswith('{"type":"api-request') for s in seen))

# --- #16: a result saved before idle gaps recorded what they waited on. ---
r = collected('older', elsewhere)
for g in r['idle_gaps']:
    del g['waiting']
page = rendered('older', r)
check('a saved result without the waiting field renders, the wait shown as unknown', True, '<td>Unknown</td>' in page)

# --- a written review marks each "Where it could shrink" item; one left unmarked is named. ---
r = collected('marks', short)
def page_with(notes):
    json.dump(notes, open(f'{TMP}/out/marks/notes.json', 'w'))
    subprocess.run([sys.executable, f'{HERE}/render.py', f'{TMP}/out/marks/result.json', f'{TMP}/out/marks/notes.json', f'{TMP}/out/marks/page.html'],
                   capture_output=True, check=True)
    return open(f'{TMP}/out/marks/page.html').read()
lesson = {'lessons': [{'title': 'One lesson', 'points': ['a point']}]}
left = re.search(r'<b>Not reviewed yet</b>: ([^<]+)', page_with(lesson))
items = left[1].split(', ') if left else []
check('with no marks, the page names every item as not reviewed', True, len(items) > 0)
covered = page_with({**lesson, 'shrink_review': [{'item': i, 'issue': '#12'} for i in items]})
check('an item an open issue covers cites it, and none is left unreviewed', (len(items), False), (covered.count(': covered by #12'), 'Not reviewed yet' in covered))
fixes = page_with({**lesson, 'shrink_review': [{'item': i, 'fix': 'send the looks together'} for i in items]})
check('an uncovered item carries its proposed fix', len(items), fixes.count('not covered; proposed fix: send the looks together'))
skill = ' '.join(open(f'{HERE}/../SKILL.md').read().split())
check('the skill asks for the marks, drafts the uncovered items, and asks the standing speed-up question', [True] * 3,
      ['`shrink_review`' in skill, 'each "Where it could shrink" item the page marks uncovered, becomes a draft issue' in skill,
       'is there a library, a shared helper or a cached step that would significantly speed up builds like this one?' in skill])
check('a page with no written lessons carries no review list', False, 'Each item against the open issues' in page_with({}))
# The items exist only once the page is rendered, so a writer that marks before rendering leaves them all unreviewed.
handoff = ' '.join(open(f'{HERE}/../writer-handoff.md').read().split())
check('the skill and the writer mark each item the first render leaves unreviewed, then render again', [True] * 2,
      ['"Not reviewed yet": add a `shrink_review` entry for each and render again' in t for t in (skill, handoff)])

# --- A cut takes its seconds off every part of a duration, not only the whole: else the page shows
# a helper working after its time was cut, or a Codex pass whose commands outlast it. ---
def parts(unit, window):
    wt = f'{TMP}/ws/{unit}'
    # A helper: requests 5-10 and 20-30, one tool call 10-20.
    write(f'{TMP}/home/.claude/projects/{re.sub(r"[^A-Za-z0-9]", "-", wt)}/s1/subagents/agent-a1.jsonl',
          [user(5), bash(10, 'toolu_h1', 'ls', 'look'), result(20, 'toolu_h1'), say(30, 'found it')])
    # A Codex pass 1-50 whose one command ran 30 s, 15-45.
    write(f'{TMP}/home/.codex/sessions/2026/10/10/rollout-2026-10-10T12-00-00-{unit}.jsonl', [
        {'timestamp': at(1), 'type': 'turn_context', 'payload': {'cwd': wt, 'model': 'gpt-5.5', 'effort': 'high'}},
        {'timestamp': at(15), 'type': 'response_item', 'payload': {'type': 'custom_tool_call', 'call_id': 'c1', 'input': 'make test'}},
        {'timestamp': at(45), 'type': 'response_item', 'payload': {'type': 'custom_tool_call_output', 'call_id': 'c1', 'output': 'Wall time 30 seconds\nok'}},
        {'timestamp': at(50), 'type': 'event_msg', 'payload': {'type': 'task_complete', 'last_agent_message': 'VERDICT: GO'}}])
    try:
        got = collected(unit, [user(0), say(100, 'Done.'), turn_end(110)], '--exclude', window)
        hp, ps = got['helpers'][0], got['passes'][0]
    except BaseException as e:
        return {'error': repr(e)[:300]}
    return {'helper': (round(hp['seconds']), round(hp['claude_s']), round(hp['tool_s'])),
            'codex': (round(ps['end'] - ps['start'] - ps['cut_s']), round(ps['command_s']), [round(s) for s, *_ in ps['longest']])}
whole_cut, part_cut = parts('cut-all', f'{at(0)}={at(110)}'), parts('cut-part', f'{at(25)}={at(50)}')
check('a helper cut end to end keeps no request or tool time', (0, 0, 0), whole_cut.get('helper', whole_cut))
check('a helper cut 25-50 loses only the overlap: 5 s of wall time and of its second request, none of its tool call',
      (20, 10, 10), part_cut.get('helper', part_cut))
check('a Codex pass cut end to end keeps no command time', (0, 0, [0]), whole_cut.get('codex', whole_cut))
check('a pass cut 25-50 keeps 24 s, its command the 10 s of 15-25', (24, 10, [10]), part_cut.get('codex', part_cut))

# --- A refusal is kept by its hook and its reason: a hook name alone cannot be sorted. A hook run by its
# interpreter has its path quoted, and is named all the same. ---
refusals = ['["$CLAUDE_PROJECT_DIR"/hooks/bash-guardrails.sh]: BLOCKED: an in-place write to src/a.test.ts from the shell skips every Edit/Write hook. Use Edit',
            '["$CLAUDE_PROJECT_DIR"/hooks/bash-guardrails.sh]: BLOCKED: an in-place write to \'web/b c.ts\' from the shell skips every Edit/Write hook. Use Edit',
            '["$CLAUDE_PROJECT_DIR"/hooks/bash-guardrails.sh]: BLOCKED: rg over an unbounded path: $f. Name a directory',
            '["/usr/bin/python3" "/opt/hooks/validation_guard.py"]: BLOCKED (a guard): this tree already has 2 passing run(s), the budget is 1. Batch']
why = [user(0)] + [r for i, body in enumerate(refusals) for r in (bash(10 + 2 * i, f'w{i}', 'x', 'try'), result(11 + 2 * i, f'w{i}', 'PreToolUse:Bash hook error: ' + body, True))]
r = collected('why', why)
check('a refusal is sorted by its hook and its reason, a quoted interpreter path included', {
    'bash-guardrails.sh: an in-place write to … from the shell skips every Edit/Write hook': 2,
    'bash-guardrails.sh: rg over an unbounded path': 1,
    'validation_guard.py: this tree already has N passing run(s), the budget is N': 1}, r['blocked'])
check('and the page counts them by hook', True, 'Guards refused 4 tool call(s): bash-guardrails.sh 3, validation_guard.py 1.' in rendered('why', r))

# --- The merge script files the round archive under the project's name, not under the main checkout's archive/. ---
import review
proj2 = f'{TMP}/proj 2'
subprocess.run(['git', 'init', '-q', proj2], check=True)
check('an archive at the path merge-unit-local.sh writes is the one looked for', f'{TMP}/home/.commandeck/briefs/proj-2/gone.tar',
      collect.main_archive(f'{TMP}/ws/gone', 'gone', proj2))

# --- A Claude reviewer's pass: its round file is headed by its session, its log sits among the Builder's, and its
# tokens are counted once, as the Builder worktree's own (never again as a Codex run). ---
builder_rows = [user(0), say(10, 'building'), turn_end(12), user(500), say(510, 'fixed'), turn_end(512)]
review_rows = [user(100), say(110, 'looking'), say(200, 'No findings.\nVERDICT: GO'), turn_end(201)]
def with_reviewer(unit, header):
    wt = f'{TMP}/ws/{unit}'
    write(f'{TMP}/home/.claude/projects/{re.sub(r"[^A-Za-z0-9]", "-", wt)}/rv-1.jsonl', review_rows)
    if header:
        write(f'{wt}/.claude/briefs/{unit}-r1-reports.md', [header + '\n\nNo findings.\nVERDICT: GO\n'])
    return collected(unit, builder_rows)
plain, claude = with_reviewer('rv0', None), with_reviewer('rv1', 'Pass: adversarial\nClaude session: rv-1')
check("a Claude reviewer's session is a numbered pass with its round and verdict", [(1, 'adversarial', 'GO')],
      [(q['n'], q['kind'], q['verdict']) for q in claude['passes']])
nonzero = lambda t: {k: {kk: v for kk, v in d.items() if v} for k, d in t.items()}
check("and its tokens and cost are counted once, the same totals as with no round file", nonzero(plain['totals']), nonzero(claude['totals']))

# --- A removed worktree is named by --main, else refused; a placed review is found where the skill reads it. ---
check('a removed worktree with --main is filed under that project', ('/tmp/commandeck/worktreereview/proj 2/gone', 'proj 2/gone'),
      review.places(f'{TMP}/ws/gone', proj2))
try:
    review.places(f'{TMP}/ws/gone')
    refused = False
except SystemExit:
    refused = True
check('and one with no --main is refused, not filed under "project"', True, refused)
collect.OUT_ROOT = f'{TMP}/out-root'
sys.argv = ['collect.py', f'{TMP}/ws/rv0', '--main', proj2]
with contextlib.redirect_stdout(io.StringIO()):
    collect.main()
check('collect with no --out writes under <project>/<unit>, where the skill reads it', True, os.path.exists(f'{TMP}/out-root/proj 2/rv0/result.json'))

# --- Issue 306 R10: no step reads a rung line any more, so the page has no rung table and review.py no reader. ---
page = rendered('elsewhere', r)
check('a page from an evidence file with no rung lines has no rung column', [False, False, False],
      ['Rung per batch item' in page, '>Rung<' in page, hasattr(review, 'rungs')])

# --- Issue 358: once the merge has removed the worktree, the build's lines come from its squash commit on main. ---
lc = f'{TMP}/lc'
def git_in(*args):
    subprocess.run(['git', '-C', lc, '-c', 'user.name=t', '-c', 'user.email=t@t', *args], check=True, capture_output=True)
subprocess.run(['git', 'init', '-q', '-b', 'main', lc], check=True)
git_in('commit', '-q', '--allow-empty', '-m', 'init')
os.makedirs(f'{lc}/.claude/briefs')
open(f'{lc}/a.txt', 'w').write('1\n2\n3\n')
open(f'{lc}/.claude/briefs/gone-unit.md', 'w').write('x\ny\n')
git_in('add', '-A'); git_in('commit', '-q', '-m', 'feat(gone-unit): three lines')
check('a removed worktree counts its squash commit on main, the brief left out', 3, collect.lines_changed(f'{TMP}/ws/no-such-wt', lc, 'gone-unit'))
check('and a unit main holds no squash commit for is not recorded', None, collect.lines_changed(f'{TMP}/ws/no-such-wt', lc, 'other-unit'))
check('and so is a removed worktree with no --main', None, collect.lines_changed(f'{TMP}/ws/no-such-wt'))
page = rendered('elsewhere', {**r, 'lines_changed': None})
check('the page says the lines changed are not recorded, and why', True, 'Lines changed: not recorded (' in page)

# --- Time with no session open was folded into the neighbouring stage, so a unit parked on purpose read as hours of
# planning. Holds are written by unit-hold.sh itself (a stub `date` fixes each row's time), then read by the collector
# through HOLDS. Every fixture: sessions 0-60 and 600-660 of one unit. ---
hold_sh = os.path.join(HERE, '..', '..', '..', 'scripts', 'unit-hold.sh')
stub = f'{TMP}/stub-date'
write(f'{stub}/date', ['#!/bin/sh\necho "$FAKE_AT"\n'])
os.chmod(f'{stub}/date', 0o755)
def hold(holds, s, unit, event, reason='parked for the test'):
    return subprocess.run(['bash', hold_sh, unit, event, reason], capture_output=True, text=True,
                          env=os.environ | {'COMMANDECK_UNIT_HOLDS': holds, 'FAKE_AT': at(s), 'PATH': stub + os.pathsep + os.environ['PATH']})
def held(unit, holds, codex_run=None, logs=None):
    wt = f'{TMP}/ws/{unit}'
    for i, rows in enumerate(logs or [[user(a), say(b, 'ok')] for a, b in ((0, 60), (600, 660))]):
        write(f'{TMP}/home/.claude/projects/{re.sub(r"[^A-Za-z0-9]", "-", wt)}/s{i}.jsonl', rows)
    if codex_run:
        codex(wt, 'tid-' + unit, codex_run[0], codex_run[1], 'VERDICT: GO')
    collect.HOLDS = holds
    sys.argv = ['collect.py', wt, '--out', f'{TMP}/out/{unit}']
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            collect.main()
        got = json.load(open(f'{TMP}/out/{unit}/result.json'))
    except BaseException as e:
        got = {'error': repr(e)[:300]}
    finally:
        collect.HOLDS = None
    return {'cut': [(round(w['start'] - T0), round(w['end'] - T0), round(w['seconds']), w['reason']) for w in got.get('cut', [])],
            'unexplained': [(round(w['start'] - T0), round(w['end'] - T0), round(w['seconds'])) for w in got.get('unexplained', [])],
            'stages': round(sum(s['end'] - s['start'] - s.get('cut_s', 0) - s.get('unexplained_s', 0) for s in got.get('stages', []))),
            'error': got.get('error')}
holds = f'{TMP}/holds-a.jsonl'
rcs = [hold(holds, 60, 'uh-a', 'hold').returncode, hold(holds, 600, 'uh-a', 'release').returncode, hold(holds, 30, 'uh-a-2', 'hold').returncode]
got = held('uh-a', holds)
check("a hold between two plan sessions is cut and listed: another unit's row is ignored",
      ([0, 0, 0], [(60, 600, 540, 'hold')], [], 120, None), (rcs, got['cut'], got['unexplained'], got['stages'], got['error']))
# Sessions 10:00-10:01 and 10:10-10:11, hold 10:01-10:10, a Codex run 10:03-10:05.
holds = f'{TMP}/holds-b.jsonl'
hold(holds, 60, 'uh-b', 'hold'), hold(holds, 600, 'uh-b', 'release')
got = held('uh-b', holds, codex_run=(180, 300))
check("a Codex run inside a hold stays work: 420 s cut around it, its 120 s in the stage figure, no unexplained row",
      ([(60, 180, 120, 'hold'), (300, 600, 300, 'hold')], [], 120 + 120, None), (got['cut'], got['unexplained'], got['stages'], got['error']))
got = held('uh-none', f'{TMP}/no-holds.jsonl')
check('a gap with no record is unexplained idle, not stage time', ([], [(60, 600, 540)], 120, None),
      (got['cut'], got['unexplained'], got['stages'], got['error']))
page = rendered('uh-none', json.load(open(f'{TMP}/out/uh-none/result.json')))
check('and the page lists it in its own box', True, '<h4>Unexplained idle: ' in page)
old = {k: v for k, v in json.load(open(f'{TMP}/out/uh-none/result.json')).items() if k not in ('unexplained', 'unexplained_s')}
for p in old['passes'] + old['stages']:
    p.pop('unexplained_s', None)
check('an old result.json with no unexplained keys still renders', False, rendered('uh-none', old).startswith('Traceback'))
ro = f'{TMP}/read-only'
os.makedirs(ro)
os.chmod(ro, 0o555)
holds = f'{ro}/holds.jsonl'
r = hold(holds, 60, 'uh-ro', 'hold')
got = held('uh-ro', holds)
os.chmod(ro, 0o755)
check('a failed hold append exits 1 and cuts nothing', (1, True, False, [], [(60, 600, 540)]),
      (r.returncode, holds in r.stderr, os.path.exists(holds), got['cut'], got['unexplained']))
holds = f'{TMP}/holds-c.jsonl'
hold(holds, 30, 'uh-c', 'release'), hold(holds, 60, 'uh-c', 'hold')
got = held('uh-c', holds)
check('open hold runs to the end; a release with no hold is ignored', ([(60, 660)], [], None),
      ([w[:2] for w in got['cut']], got['unexplained'], got['error']))
# An append cut off before its newline must not swallow the next row: the release after it still closes the hold.
holds = f'{TMP}/holds-torn.jsonl'
hold(holds, 60, 'uh-torn', 'hold')
open(holds, 'a').write('{"unit":')
r = hold(holds, 600, 'uh-torn', 'release')
got = held('uh-torn', holds)
check('a release after a torn append still closes the hold', (0, [(60, 600)], [], None),
      (r.returncode, [w[:2] for w in got['cut']], got['unexplained'], got['error']))
# A background job is build work while it runs, whichever session started it and whichever painted the wait, and a job
# with no recorded end runs to the review's end. Each ordering has a hold 60-600: (a) one session, test 10-600, turn idle
# 60-600; (b) session A idle 60-600, session B 10-500 starts a test at 20 that never ends; (c) one session, test 20-100
# ended by a queued notice, turn idle 60-600; (d) as (c) but the test is session B's, idle from 30, while A paints the wait.
def bg_test(s, tid):
    return [reply(s, {'type': 'tool_use', 'id': tid, 'name': 'Bash', 'input': {
                'command': 'bash scripts/run-shell-tests.sh h', 'description': 'Run the touched test file', 'run_in_background': True}}),
            result(s + 1, tid, f'Command running in background with ID: b{tid[-2:]}. Output is being written to: /tmp/{tid}.output')]
def notice(s, tid):
    return {'type': 'user', 'timestamp': at(s), 'message': {'role': 'user', 'content':
            f'<task-notification><task-id>b{tid[-2:]}</task-id><tool-use-id>{tid}</tool-use-id><status>completed</status></task-notification>'}}
def queued(s, tid):
    return {'type': 'attachment', 'timestamp': at(s), 'attachment': {'type': 'queued_command', 'prompt': f'<task-notification><tool-use-id>{tid}</tool-use-id></task-notification>'}}
idle_a = [user(0), turn_end(60), user(600), say(660, 'ok')]
orderings = {
    'a': [[user(0), *bg_test(10, 'toolu_holda'), turn_end(60), notice(600, 'toolu_holda'), say(660, 'ok')]],
    'b': [idle_a, [user(10), *bg_test(20, 'toolu_holdb'), say(500, 'ok')]],
    'c': [[user(0), *bg_test(20, 'toolu_holdc'), turn_end(60), queued(100, 'toolu_holdc'), user(600), say(660, 'ok')]],
    'd': [idle_a, [user(10), *bg_test(20, 'toolu_holdd'), say(30, 'ok'), turn_end(30), queued(100, 'toolu_holdd')]]}
got = {}
for k, logs in orderings.items():
    holds = f'{TMP}/holds-job-{k}.jsonl'
    hold(holds, 60, f'uh-job-{k}', 'hold'), hold(holds, 600, f'uh-job-{k}', 'release')
    g = held(f'uh-job-{k}', holds, logs=logs)
    got[k] = (g['cut'], g['unexplained'], g['stages'], g['error'])
check('a hold is cut around every background job, whichever session shows the wait',
      {'a': ([], [], 660, None), 'b': ([], [], 660, None),
       'c': ([(100, 600, 500, 'hold')], [], 160, None), 'd': ([(100, 600, 500, 'hold')], [], 160, None)}, got)
# With no hold, a background job still running between two sessions is build time, not unexplained idle: a job left
# open runs to the review's end; one whose notice lands at 100 leaves only 100-600 unexplained.
got = {}
for k, end in (('open', None), ('ended', 100)):
    first = [user(0), *bg_test(10, f'toolu_gap{k}'), turn_end(60)] + ([queued(end, f'toolu_gap{k}')] if end else [])
    g = held(f'uh-gap-{k}', f'{TMP}/no-holds.jsonl', logs=[first, [user(600), say(660, 'ok')]])
    got[k] = (g['unexplained'], g['stages'], g['error'])
check('a gap a background job covers is not unexplained idle', {'open': ([], 660, None), 'ended': ([(100, 600, 500)], 160, None)}, got)
# A fresh project has no .claude/metrics folder: the first hold makes it, and the script runs as a command.
holds = f'{TMP}/fresh/.claude/metrics/unit-holds.jsonl'
try:
    r = subprocess.run([hold_sh, 'uh-fresh', 'hold', 'parked'], capture_output=True, text=True,
                       env=os.environ | {'COMMANDECK_UNIT_HOLDS': holds})
    r = (r.returncode, json.loads(open(holds).read())['event'] if os.path.exists(holds) else r.stderr[:200])
except OSError as e:
    r = repr(e)[:200]
check('the first hold in a fresh project makes the metrics folder, run as a command', (0, 'hold'), r)

# --- Issue 397: the review shows each helper's model and cost and the count by model, and flags a big build that
# started no helper (the squash commit on main counts the lines; the flag is over 300, never at 300). ---
def squashed(unit, n):
    open(f'{lc}/{unit}.txt', 'w').write(''.join(f'{i}\n' for i in range(n)))
    git_in('add', '-A'); git_in('commit', '-q', '-m', f'feat({unit}): {n} lines')
def sized(unit, n, helper=False):
    squashed(unit, n)
    if helper:
        write(f'{TMP}/home/.claude/projects/{re.sub(r"[^A-Za-z0-9]", "-", f"{TMP}/ws/{unit}")}/s1/subagents/agent-a1.jsonl', [user(5), say(30, 'found it')])
    return collected(unit, [user(0), say(100, 'Done.'), turn_end(110)], '--main', lc)
HL = 'no helper agent started'
big, edge, helped = sized('hl-big', 301), sized('hl-edge', 300), sized('hl-helped', 301, True)
check("the review names each helper's model and cost", True,
      bool(re.search(r'Helper .{0,200}?: Opus 5\.5, [^,]+, [^ ]+ tokens, \$[\d,.]+\.', rendered('hl-helped', helped))))
check('the review prints helper count and spend by model', True,
      bool(re.search(r'Helpers: 1 started; by model: Opus 5\.5 1, \$[\d,.]+\.', rendered('hl-helped', helped))))
check('a build over 300 changed lines with no helper is flagged', 1, len([f for f in big['flags'] if HL in f and f.startswith('301 changed lines')]))
check('a build of 300 lines with no helper is not flagged', 0, len([f for f in edge['flags'] if HL in f]))
check('a build over 300 lines with a helper is not flagged', 0, len([f for f in helped['flags'] if HL in f]))

# --- Issue 399: the review counts a unit's Codex helper calls (codex-ask.sh rows) apart from the Claude helpers. ---
os.makedirs(f'{lc}/.claude/metrics', exist_ok=True)
with open(f'{lc}/.claude/metrics/codex-helper.jsonl', 'w') as f:
    for u, secs, outcome, model in (('cx-two', 3, 'answered', 'gpt-x-test'), ('cx-two', 4, 'timeout', None), ('cx-other', 99, 'answered', 'gpt-x-test')):
        f.write(json.dumps({'unit': u, 'seat': 'builder', 'model': model, 'start': 'x', 'secs': secs, 'outcome': outcome, 'bytes': 1}) + '\n')
    f.write('not json\n')
cx_two = collected('cx-two', [user(0), say(100, 'Done.'), turn_end(110)], '--main', lc)
cx_none = collected('cx-none', [user(0), say(100, 'Done.'), turn_end(110)], '--main', lc)
check('the review shows Codex helper calls and time', True,
      'Codex helper: 2 calls, 7 s, 1 failed; by model: gpt-x-test 1; none read 1.' in rendered('cx-two', cx_two))
check('a build with no Codex call says none', True, 'Codex helper: none.' in rendered('cx-none', cx_none))

# --- #475: an idle wait with nothing running and no decision recorded is no build time. ---
r = collected('u475', [user(0), say(10, 'Waiting on a reply.'), turn_end(12), user(1200), say(1210, 'Go on.'), turn_end(1212)], '--main', main)
check('an idle wait is cut with its cause (issue 475)', [(12, 1200, 'waiting on nothing, no decision recorded')],
      [(round(w['start'] - T0), round(w['end'] - T0), w['reason']) for w in r['cut']])

print(f'{passed} passed, {failed} failed')
sys.exit(1 if failed else 0)
PY

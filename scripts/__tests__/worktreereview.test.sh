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

# --- The batch brief lists items as `1. #12: title`; the older form carried a rung. ---
write(f'{TMP}/ws/rg/.claude/briefs/rg.md', ['1. #12: Fix the hook\n2. [rung 3] #13 older\n'])
write(f'{TMP}/ws/rg/.claude/briefs/rg-evidence.md', ['Ponytail: item 1: rung 5; lazier option: none\n'])
check('a batch item in the brief template format gets its row and its rung', [(1, '#12', '5'), (2, '#13', None)],
      [(r_['item'], r_['issue'], r_['rung']) for r_ in review.rungs(f'{TMP}/ws/rg', 'rg')])

print(f'{passed} passed, {failed} failed')
sys.exit(1 if failed else 0)
PY

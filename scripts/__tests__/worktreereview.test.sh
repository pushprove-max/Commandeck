#!/usr/bin/env bash
# The build review's numbers, from small session and Codex logs under a pretend
# home. What this pins: a wait on a review pass run outside the Builder's
# session, or on a review tool that is down, is its own bucket and flags
# nothing (#55); the share-of-clock flag needs 10 minutes of tests and idle
# waits and names the largest command (#63); a pass keeps its whole text and the
# page lists the passes after the closing one (#64); idle after DONE stays on
# the clock unless an owner decision is open (#70); Claude Code 2.1.300's
# api-request rows are neither counted nor parsed (#71); a result saved before
# idle gaps recorded what they waited on still renders (#16).
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
python3 - "$ROOT/skills/worktreereview/scripts" "$T" <<'PY'
import contextlib, io, itertools, json, os, re, subprocess, sys
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

print(f'{passed} passed, {failed} failed')
sys.exit(1 if failed else 0)
PY

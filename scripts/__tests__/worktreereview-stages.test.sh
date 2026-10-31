#!/usr/bin/env bash
# covers: skills/worktreereview/scripts/collect.py skills/worktreereview/scripts/render.py
# The build review's stages and pass notes, from small session and Codex logs under a pretend home (the rest of the
# report is worktreereview.test.sh). What this pins: planning before the Builder starts is its own stage, found by a
# seat tag or a plan spec's name, never by a hand split (#528); a reviewer that said its symbol search was down gets a
# note under its pass (#530).
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
python3 - "$ROOT/skills/worktreereview/scripts" "$T" <<'PY'
import contextlib, io, itertools, json, os, re, subprocess, sys
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
def say(s, text):
    i = next(ids)
    return {'type': 'assistant', 'timestamp': at(s), 'requestId': f'r{i}',
            'message': {'id': f'm{i}', 'model': 'claude-opus-5-5', 'usage': USAGE, 'content': [{'type': 'text', 'text': text}]}}
def said(s, text):
    return {'type': 'user', 'timestamp': at(s), 'message': {'role': 'user', 'content': text}}
def user(s):
    return said(s, 'go on')
def turn_end(s):
    return {'type': 'system', 'subtype': 'turn_duration', 'timestamp': at(s)}
def write(path, rows):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(''.join(r if isinstance(r, str) else json.dumps(r) + '\n' for r in rows))
def codex(wt, tid, start, end, message, texts=(), says=()):
    """A Codex record of <wt>: user messages <texts> at its start, agent messages <says> after, <message> last."""
    write(f'{TMP}/home/.codex/sessions/2026/10/10/rollout-2026-10-10T12-00-00-{tid}.jsonl', [
        {'timestamp': at(start), 'type': 'turn_context', 'payload': {'cwd': wt, 'model': 'gpt-5.5', 'effort': 'high'}},
        *({'timestamp': at(start), 'type': 'response_item', 'payload': {'type': 'message', 'role': 'user',
           'content': [{'type': 'input_text', 'text': t}]}} for t in texts),
        *({'timestamp': at(start + 1), 'type': 'event_msg', 'payload': {'type': 'agent_message', 'message': t}} for t in says),
        {'timestamp': at(end - 1), 'type': 'event_msg', 'payload': {'type': 'token_count', 'info': {'total_token_usage': {
            'input_tokens': 1000, 'cached_input_tokens': 0, 'output_tokens': 100}}}},
        {'timestamp': at(end), 'type': 'event_msg', 'payload': {'type': 'task_complete', 'last_agent_message': message}}])
def run(unit, *args):
    sys.argv = ['collect.py', f'{TMP}/ws/{unit}', '--out', f'{TMP}/out/{unit}', *args]
    with contextlib.redirect_stdout(io.StringIO()):
        collect.main()
    return json.load(open(f'{TMP}/out/{unit}/result.json'))
def session(unit, name, rows):
    write(f'{TMP}/home/.claude/projects/{re.sub(r"[^A-Za-z0-9]", "-", f"{TMP}/ws/{unit}")}/{name}.jsonl', rows)
def collected(unit, rows, *args):
    """collect.py run on one session log of the worktree <TMP>/ws/<unit> -> its result.json."""
    session(unit, 's1', rows)
    return run(unit, *args)
def rendered(unit, r):
    json.dump(r, open(f'{TMP}/out/{unit}/result.json', 'w'))
    done = subprocess.run([sys.executable, f'{HERE}/render.py', f'{TMP}/out/{unit}/result.json', f'{TMP}/out/{unit}/page.html'],
                          capture_output=True, text=True)
    return open(f'{TMP}/out/{unit}/page.html').read() if done.returncode == 0 else done.stderr

# --- #528: planning before the Builder starts is its own stage, found by role, never by a hand split. ---
def spec_of(name):
    return f'Your task spec is the file /x/{name}.md and nothing else.\n'
def codex_says(unit, tid, start, end, *texts):
    codex(f'{TMP}/ws/{unit}', tid, start, end, 'done', texts)
def shape(r):
    return [(s['name'], round(s['start'] - T0)) for s in r['stages']]
# Catches: a report whose first stage mixes planning with the build, so planning's share of the cost is never shown.
session('ps-split', 's2', [said(300, spec_of('ps-split-build-spec')), say(600, 'Built.'), turn_end(610)])
r = collected('ps-split', [said(0, spec_of('ps-split-plan-spec')), say(100, 'Planned.'), turn_end(110)])
check('plan share splits from build', [('Plan and judge', 0), ('Build', 300)], shape(r))
# Catches: a Codex-built unit that shows its plan judge as one more Codex run inside the build, with no planning stage.
codex_says('ps-cxonly', 'ps-cxonly-judge', 0, 100, spec_of('ps-cxonly-plan-judge-a'))
codex_says('ps-cxonly', 'ps-cxonly-build', 200, 500, spec_of('ps-cxonly-build-spec'))
check('a Codex-only unit splits at its first Builder record', [('Plan and judge', 0), ('Codex pass 1 (review)', 200)], shape(run('ps-cxonly')))
# Catches: a Codex plan judge whose only mark is a seat tag in its pointer message, behind the untagged AGENTS.md message,
# counted as a Codex run inside the build.
session('ps-tag', 's2', [said(300, 'Build it.'), say(600, 'Built.'), turn_end(610)])
codex_says('ps-tag', 'ps-tag-judge', 50, 100, '# AGENTS.md instructions for /x\n\nBe brief.\n',
           'Read /x/f.md and follow it in full; it is your whole task. Seat tag seat-plan-judge-a-1790000000-123: it names this seat.')
r = collected('ps-tag', [said(0, spec_of('ps-tag-plan-spec')), say(40, 'Planned.'), turn_end(45)])
check('a Codex plan judge found by its seat tag is planning', ([('Plan and judge', 0), ('Build', 300)], []), (shape(r), r['passes']))
# Catches: planning tokens dropped from the totals once the plan judge is no stage of its own.
session('ps-cost', 's2', [said(300, 'Build it.'), say(600, 'Built.'), turn_end(610)])
codex_says('ps-cost', 'ps-cost-judge', 50, 100, spec_of('ps-cost-plan-judge-a'))
r = collected('ps-cost', [said(0, spec_of('ps-cost-plan-spec')), say(40, 'Planned.'), turn_end(45)])
check('planning tokens stay in the stage cost', (1000, 100, 1),
      (r['stages'][0]['codex'].get('in'), r['stages'][0]['codex'].get('out'), r['stages'][0]['builder'].get('calls')))
# Catches: a Codex Builder that starts after the last Claude record dropped from the window, so the stages never split.
codex_says('ps-cxbuild', 'ps-cxbuild-build', 400, 700, spec_of('ps-cxbuild-build-spec'))
r = collected('ps-cxbuild', [said(0, spec_of('ps-cxbuild-plan-spec')), say(100, 'Planned.'), turn_end(110)])
check('a Codex Builder after Claude planning splits the stages', ([('Plan and judge', 0), ('Codex pass 1 (review)', 400)], 700),
      (shape(r), round(r['end'] - T0)))

# --- #530: a reviewer that said its symbol search was down has a note under its pass. ---
NOTE = 'a reviewer said Serena was unavailable'
def reviewed(unit, *says):
    """One Codex review pass of <TMP>/ws/<unit>, named by its round file, whose reviewer says <says> before its GO."""
    wt = f'{TMP}/ws/{unit}'
    codex(wt, f'{unit}-p1', 100, 200, 'No findings.\nVERDICT: GO', says=says)
    write(f'{wt}/.claude/briefs/{unit}-r1-reports.md', [f'## Sol (gpt-5.5, read-only)\nReviewed: {"a" * 40}\nCodex thread: {unit}-p1\nPass: review\n\nVERDICT: GO\n'])
    return collected(unit, [user(0), say(10, 'Ready.'), turn_end(12), user(300), say(310, 'Done.'), turn_end(312)])
# Catches: a GO resting on text search alone, read as a full review because the reviewer said so only mid-run.
r = reviewed('gap1', 'Serena timed out on the first query, so I used rg for the callers.')
check('a reviewer tool gap is recorded', ([True], 1), ([q.get('tool_gaps') for q in r['passes']], rendered('gap1', r).count(NOTE)))
# Catches: a note on every pass whose reviewer names the tool, though it worked.
r = reviewed('gap0', 'Serena found three callers of fold_passes.')
check('a normal reviewer message is no gap', ([False], 0), ([q.get('tool_gaps') for q in r['passes']], rendered('gap0', r).count(NOTE)))
# Catches: a Claude reviewer's pass, built from its session and no Codex record, missing the key or crashing the page.
wt = f'{TMP}/ws/gapc'
session('gapc', 'rv-1', [user(100), say(110, 'looking'), say(200, 'No findings.\nVERDICT: GO'), turn_end(201)])
write(f'{wt}/.claude/briefs/gapc-r1-reports.md', ['Pass: adversarial\nClaude session: rv-1\n\nNo findings.\nVERDICT: GO\n'])
r = collected('gapc', [user(0), say(10, 'building'), turn_end(12), user(500), say(510, 'fixed'), turn_end(512)])
check('a Claude reviewer pass reads no gap', ([False], 0), ([q.get('tool_gaps') for q in r['passes']], rendered('gapc', r).count(NOTE)))

print(f'{passed} passed, {failed} failed')
sys.exit(1 if failed else 0)
PY

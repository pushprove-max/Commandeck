#!/usr/bin/env bash
# The review says what to strip: each case below is a failure that would send the reader to the wrong place.
# An oversized tool result that does not top the list, a compaction that keeps carrying dropped content, an
# ordinary cache write priced as an expired one, or a repeat counted as a fresh finding.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
python3 - "$ROOT/skills/worktreereview/scripts" <<'PY'
import json, os, re, subprocess, sys, tempfile
from datetime import datetime, timezone
sys.path.insert(0, sys.argv[1])
import extras

failed = passed = 0
def check(name, want, got):
    global failed, passed
    ok = want == got
    failed += not ok
    passed += ok
    print(('ok   ' if ok else 'FAIL ') + name + ('' if ok else f' (expected {want!r}, got {got!r})'))

def at(s):
    return datetime.fromtimestamp(1700000000 + s, timezone.utc).isoformat().replace('+00:00', 'Z')
def ask(s, mid, tid=None, size=1000, out=10, cw=0):
    content = [{'type': 'tool_use', 'id': tid, 'name': 'Bash', 'input': {'description': 'x'}}] if tid else [{'type': 'text', 'text': 'hi'}]
    return {'type': 'assistant', 'timestamp': at(s), 'message': {'id': mid, 'model': 'm', 'content': content,
            'usage': {'input_tokens': 0, 'cache_read_input_tokens': size - cw, 'cache_creation_input_tokens': cw, 'output_tokens': out}}}
def result(s, tid, chars):
    return {'type': 'user', 'timestamp': at(s), 'message': {'content': [{'type': 'tool_result', 'tool_use_id': tid, 'content': 'y' * chars}]}}
def log(rows):
    f = tempfile.NamedTemporaryFile('w', suffix='.jsonl', delete=False)
    f.write('\n'.join(r if isinstance(r, str) else json.dumps(r) for r in rows))
    f.close()
    return f.name
price = lambda model, u: (u.get('cache_read_input_tokens') or 0) * 1e-6 + (u.get('cache_creation_input_tokens') or 0) * 1e-5
none = lambda model, u: None

# A big result that missed the top of the list sends the reader to a small one.
big = extras.context_breakdown([log([
    ask(1, 'a', 't1'), result(2, 't1', 30000), ask(3, 'b', 't2'), result(4, 't2', 300), ask(5, 'c', size=50000),
])], price)
check('oversized_result_tops_list: the largest item is the 30000-character result', extras.tokens('y' * 30000), big['top'][0]['tokens'])
check('oversized_result_tops_list: its source tops the cost table', 'Results: Bash', big['sources'][0]['source'])
# The page calls the first row the largest single item: small results carried for longer must not push the big one out.
small = [(f't{i}', i + 1) for i in range(extras.TOP_ITEMS)]
long_carried = extras.context_breakdown([log(
    [row for tid, i in small for row in (ask(2 * i, f'm{i}', tid), result(2 * i + 1, tid, 4000))]
    + [ask(100, 'big', 'huge'), result(101, 'huge', 30000)]
    + [ask(200, 'end', size=50000)]
)], price)
check('largest_item_ranks_by_size: the oversized result is first, though each small one cost more to carry', extras.tokens('y' * 30000), long_carried['top'][0]['tokens'])
# A margin against an estimate, not the measured peak, hides how far the sizes are off.
check('peak_margin_printed: the peak is the size the API measured, and the margin is against it', (50000, True), (big['peak'], 0 <= big['margin'] <= 1))

# A compaction that kept carrying dropped content would overstate the cost of it.
cut = extras.context_breakdown([log([
    ask(1, 'a', 't1'), result(2, 't1', 30000), ask(3, 'b'),
    {'type': 'system', 'subtype': 'compact_boundary', 'timestamp': at(4)},
    ask(5, 'c'), ask(6, 'd'),
])], price)
check('compaction_stops_carrying: a dropped result is carried until the compaction only', 1, cut['top'][0]['requests'])

twice = extras.context_breakdown([log([
    ask(1, 'a', 't1'), result(2, 't1', 3000), ask(3, 'b', 't2'), result(4, 't2', 3000), ask(5, 'c'),
])], price)
check('content_twice_named_once: the same result twice is one repeat row of 2', [2], [x['times'] for x in twice['repeats']])

# The log keeps only a thinking block's signature: its size is what the request wrote beyond text and calls.
thought = extras.context_breakdown([log([ask(1, 'a', out=5000), ask(2, 'b')])], price)
check('thinking_is_text_beyond: thinking is the output beyond the visible text', 'Thinking', thought['top'][0]['source'])

cheap, dear = ask(1, 'a', size=1000), ask(1, 'b', size=1000)
cheap['message']['model'], dear['message']['model'] = 'cheap', 'dear'
rated = lambda model, u: (10.0 if model == 'dear' else 1.0)
mixed = extras.context_breakdown([log([{'type': 'user', 'timestamp': at(0), 'message': {'content': 'x' * 300}}, cheap]),
                                  log([{'type': 'attachment', 'timestamp': at(0), 'attachment': {'type': 'hook_additional_context', 'content': 'x' * 300}}, dear])], rated)
check('rates_stay_per_session: a dear session\'s source costs more than a cheap one\'s', (['Hook output', 'Prompts and briefs'], True),
      ([x['source'] for x in mixed['sources'][:2]], mixed['sources'][0]['usd'] > 5 * mixed['sources'][1]['usd']))

advised = ask(1, 'a', size=1000)
advised['message']['usage']['iterations'] = [{'type': 'advisor_message', 'input_tokens': 900000}]
billed = lambda model, u: (u.get('cache_read_input_tokens') or 0) * 1e-6 + (u.get('cache_creation_input_tokens') or 0) * 1e-5 + sum((i.get('input_tokens') or 0) * 1e-5 for i in u.get('iterations') or [])
def usage(cw, size):
    return {'input_tokens': 0, 'cache_read_input_tokens': size - cw, 'cache_creation_input_tokens': cw, 'output_tokens': 1}
sess = {'compactions': [], 'usage': {'a': (0, usage(0, 100000), 'm'), 'b': (400, usage(100000, 100000), 'm'), 'c': (410, usage(5000, 105000), 'm')}}
gone = extras.cache_expiry([sess], price)
sess['usage']['b'][1]['iterations'] = [{'type': 'advisor_message', 'input_tokens': 900000}]
check('advisor_bill_left_out: an advisor bill is no part of the context or the expiry cost', (0.001, 0.9, 0.9),
      (round(extras.context_breakdown([log([advised])], billed)['input_usd'], 3), round(gone['usd'], 2), round(extras.cache_expiry([sess], billed)['usd'], 2)))

# An ordinary write priced as an expired cache would blame a pause for it.
check('ordinary_write_no_expiry: a new model, a first write, a nothing-written request and a write inside the lifetime are no expiry', [0, 0, 0, 0],
      [extras.cache_expiry([{'compactions': [], 'usage': u}], price)['count'] for u in (
          {'a': (0, usage(0, 100000), 'opus'), 'b': (400, usage(100000, 100000), 'haiku')},
          {'a': (0, usage(0, 0), 'm'), 'b': (400, usage(100000, 100000), 'm')},
          {'a': (0, usage(0, 0), 'm'), 'b': (400, usage(0, 100000), 'm')},
          {'a': (0, usage(0, 100000), 'm'), 'b': (100, usage(100000, 100000), 'm')})])
hour = usage(100000, 100000) | {'cache_creation': {'ephemeral_1h_input_tokens': 100000}}
both = usage(100000, 100000) | {'cache_creation': {'ephemeral_1h_input_tokens': 10000, 'ephemeral_5m_input_tokens': 90000}}
lifetime = lambda model, u: price(model, u) + (0.5 if u.get('cache_creation') else 0)
one = lambda u, gap: extras.cache_expiry([{'compactions': [], 'usage': {'a': (0, u, 'm'), 'b': (gap, u, 'm')}}], lifetime)['count']
check('one_hour_cache_no_expiry: a pause inside a 1-hour cache is none, past it is one, a 5-minute part keeps the short lifetime', (0, 1, 1),
      (one(hour, 400), one(hour, 3700), one(both, 400)))
nothing = extras.cache_expiry([{'compactions': [], 'usage': {'a': (0, usage(0, 100000), 'm'), 'b': (400, usage(100000, 100000), 'm')}}], none)
check('missing_price_reported: an unpriced expiry and an unpriced context are counted, not shown as zero', (1, None, 1, 1),
      (nothing['count'], nothing['events'][0]['usd'], nothing['unpriced'], extras.context_breakdown([log([ask(1, 'a')])], none)['unpriced']))

passes = [{'n': 1, 'kind': 'adversarial', 'usd': 1.0, 'message': '- [P1] Bad thing -- a/x.sh:1 -- why\n- [P2] Other -- a/y.sh:2 -- why'},
          {'n': 2, 'kind': 'review', 'usd': 1.0, 'message': '- [P2] Again -- a/z.sh:3 -- why\n- [P2] Bad too -- a/x.sh:9 -- why'},
          {'n': 3, 'kind': 'final', 'usd': 2.0, 'message': '- [P2] Fresh -- a/w.sh:1 -- why'}]
value = extras.finding_value(passes, 'a/y.sh was refused by main')
check('repeat_not_fresh: a cited file is a repeat and a refused file is likely rejected; neither is fresh', (1, 1, [1, 1, 1], [1.0, 1.0, 2.0]),
      (value['repeats'], value['rejected'], [x['fresh'] for x in value['by_pass']], [x['usd_per_fresh'] for x in value['by_pass']]))
same = extras.finding_value([{'n': 1, 'kind': 'adversarial', 'usd': 1.0, 'message': '- [P2] First -- a.py:1 -- x\n- [P2] Second -- a.py:9 -- y'}])
check('two_in_one_file_both_fresh: two findings in one file of one pass are both fresh', ([2], [0.5]), ([x['fresh'] for x in same['by_pass']], [x['usd_per_fresh'] for x in same['by_pass']]))
# The plugin's reviewers write (class: <tag>); a tag an earlier pass carried is a repeat even in a new file.
tagged = extras.finding_value([{'n': 1, 'kind': 'a', 'usd': 1.0, 'message': '- [P2] (class: probe) One -- a.sh:1 -- x'},
                               {'n': 2, 'kind': 'b', 'usd': 1.0, 'message': '- [P2] (class: probe) Two -- b.sh:1 -- y\n- [P2] (class: other) Three -- c.sh:1 -- z'}])
check('class_tag_is_repeat: a class seen in an earlier pass is a repeat, a new class is not', (1, [1, 1]), (tagged['repeats'], [x['fresh'] for x in tagged['by_pass']]))
# A head collect.py counts but the rows missed made the two counts differ.
bullets = '* [P2] (class: probe) Wrong value -- a.sh:1 -- fails -- bash a.sh\n[P2] (class: probe2) Wrong value -- b.sh:1 -- fails -- bash b.sh'
fresh = extras.finding_value([{'n': 1, 'kind': 'a', 'usd': 1.0, 'message': bullets}])['by_pass'][0]
check('other_bullets_count_fresh: a star bullet and no bullet each count as fresh', (2, 2), (fresh['findings'], fresh['fresh']))

repo = tempfile.mkdtemp()
def g(*a):
    subprocess.run(['git', '-C', repo, '-c', 'user.name=t', '-c', 'user.email=t@t', '-c', 'core.hooksPath=/dev/null', *a], capture_output=True, check=True)
def commit(path, msg):
    open(os.path.join(repo, path), 'a').write('x\n')
    g('add', '.')
    g('commit', '-m', msg)
g('init', '-q')
commit('a.txt', 'chore: base')
commit('plan.txt', 'plan(unit-x): plan')
commit('a.txt', 'feat(unit-x): build')
commit('b.txt', 'fix: another file')
commit('a.txt', 'fix: same file')
commit('a.txt', 'docs: same file')
commit('a.txt', 'fix(unit-x): repair the build')
later = extras.after_merge('unit-x', repo)
# A plan commit read as the build made the build's file list the plan's.
check("plan_commit_not_the_build: later fixes in the build's file are listed, the plan commit is not the build", (['fix(unit-x): repair the build', 'fix: same file'], 3),
      ([x['subject'] for x in later['fixes']], later['later_commits']))
for k in range(extras.TOP_ITEMS + 1):
    commit('a.txt', f'fix: round {k}')
many = extras.after_merge('unit-x', repo)
check('later_fix_count_whole: an unmerged unit says so, and the count is not cut to the listed rows', ({'merged': False}, extras.TOP_ITEMS + 3, extras.TOP_ITEMS),
      (extras.after_merge('unit-y', repo), many['fix_count'], len(many['fixes'])))
slow = subprocess.run
def stalled(*a, **k):
    raise subprocess.TimeoutExpired('git', 1)
subprocess.run = stalled
check('slow_git_costs_section: a git that does not answer costs the section, not the report', {'timed_out': True}, extras.after_merge_safe('unit-x', repo))
subprocess.run = slow

seat = tempfile.mkdtemp()
queued = [{'type': 'user', 'timestamp': at(0), 'message': {'content': 'other work'}},
          {'type': 'attachment', 'timestamp': at(1), 'attachment': {'type': 'queued_command', 'prompt': 'unit-x done'}}, ask(2, 'a', size=1000)]
with open(os.path.join(seat, 's.jsonl'), 'w') as f:
    f.write('\n'.join(json.dumps(r) for r in queued))
check('queued_notice_counts: a queued notice naming the unit counts, and a request with no price is unpriced', (1, 1),
      (extras.seat_share(seat, 'unit-x', 1700000000, 1700000010, price)['named_requests'], extras.seat_share(seat, 'unit-x', 1700000000, 1700000010, none)['unpriced']))

# rows_of skips api-request rows unparsed (worktreereview.test.sh pins it), so the fixed sources come from raw text.
shape = '{"type":"api-request-shape","shape":{"system":[{"text":"' + 'S' * 3000 + '"}],"tools":[{"name":"A","d":"' + 'T' * 6000 + '"}]}}'
seen, loads = [], json.loads
json.loads = lambda s, *a, **k: (seen.append(s), loads(s, *a, **k))[1]
fixed = extras.context_breakdown([log([shape, ask(1, 'a')])], price)
json.loads = loads
at_peak = {x['source']: x['at_peak'] for x in fixed['sources']}
check('shape_row_fixed_sources: system prompt and tool definitions are sized, and no api-request row is parsed',
      (True, True, 0), (1000 <= at_peak.get('System prompt', 0) < 1500, 2000 <= at_peak.get('Tool definitions', 0) < 2500, sum(str(s).startswith('{"type":"api-request') for s in seen)))

# collect.py then render.py over a Claude build, and over a Codex-only build.
import collect
home, out = tempfile.mkdtemp(), tempfile.mkdtemp()
os.environ.pop('CLAUDE_CONFIG_DIR', None)
proj = os.path.join(home, '.claude', 'projects', re.sub(r'[^A-Za-z0-9]', '-', '/w/unit-s')); os.makedirs(proj)
rows = [{'type': 'user', 'timestamp': at(0), 'message': {'content': 'go'}}, ask(1, 'a', 't1', size=60000), result(2, 't1', 90000), ask(3, 'b', size=80000), ask(4, 'c', size=80000)]
open(os.path.join(proj, 's1.jsonl'), 'w').write('\n'.join(json.dumps(r) for r in rows))
ran = subprocess.run([sys.executable, os.path.join(sys.argv[1], 'collect.py'), '/w/unit-s', '--out', out], env=os.environ | {'HOME': home}, capture_output=True, text=True)
notes = os.path.join(out, 'notes.json')
json.dump({'lessons': [{'title': 'L', 'points': ['p']}]}, open(notes, 'w'))
shown = subprocess.run([sys.executable, os.path.join(sys.argv[1], 'render.py'), os.path.join(out, 'result.json'), notes, os.path.join(out, 'page.html')], capture_output=True, text=True)
page = open(os.path.join(out, 'page.html')).read() if shown.returncode == 0 else ran.stderr[-300:] + shown.stderr[-300:]
check('peak_margin_printed: the page prints the margin against the measured peak', True, 'measured size' in page)
# The shrink review covers only ideas built before it: a lead added after it would never be named when unreviewed.
check('ideas_join_shrink_review: the context idea is named in "Not reviewed yet"', True, bool(re.search(r'Not reviewed yet.*What the context carried', page)))
old = json.load(open(os.path.join(out, 'result.json')))
for k in ('context_sources', 'cache_expiry', 'main_share', 'finding_value', 'after_merge'):
    old.pop(k, None)
json.dump(old, open(os.path.join(out, 'old.json'), 'w'))
oldrun = subprocess.run([sys.executable, os.path.join(sys.argv[1], 'render.py'), os.path.join(out, 'old.json'), notes, os.path.join(out, 'old.html')], capture_output=True, text=True)
check('ideas_join_shrink_review: a result saved before the new keys still renders', 0, oldrun.returncode)

# Quoted by default, 'caf\303\251.txt' named no file, so a later fix to a non-ASCII name vanished from the report.
odd = tempfile.mkdtemp()
def gq(*args):
    subprocess.run(['git', '-C', odd, '-c', 'user.name=t', '-c', 'user.email=t@t', '-c', 'core.hooksPath=/dev/null', *args], check=True, capture_output=True)
def touch(name, subject):
    with open(os.path.join(odd, name), 'a') as f:
        f.write(subject + '\n')
    gq('add', '-A')
    gq('commit', '-qm', subject)
gq('init', '-q')
touch('café.txt', 'feat(unit-q): build')
touch('café.txt', 'fix: repair the odd name')
check('non_ascii_file_after_merge: a fix to a non-ASCII file the build changed is listed', ['fix: repair the odd name'],
      [x['subject'] for x in extras.after_merge('unit-q', odd)['fixes']])

# collect.py gave a Codex-only build no main share at all, so a report read as if main had spent nothing on it.
home, out = tempfile.mkdtemp(), tempfile.mkdtemp()
day = os.path.join(home, '.codex', 'sessions', '2023', '11', '14'); os.makedirs(day)
with open(os.path.join(day, 'rollout-c.jsonl'), 'w') as f:
    for row in [{'timestamp': at(0), 'type': 'turn_context', 'payload': {'cwd': '/w/unit-c', 'model': 'm'}},
                {'timestamp': at(100), 'type': 'event_msg', 'payload': {'type': 'task_complete', 'last_agent_message': 'VERDICT: GO'}}]:
        f.write(json.dumps(row) + '\n')
seat_dir = os.path.join(home, '.claude', 'projects', re.sub(r'[^A-Za-z0-9]', '-', collect.main_checkout('.'))); os.makedirs(seat_dir)
with open(os.path.join(seat_dir, 'm.jsonl'), 'w') as f:
    f.write('\n'.join(json.dumps(r) for r in [{'type': 'user', 'timestamp': at(49), 'message': {'content': 'unit-c go'}}, ask(50, 'a')]))
ran = subprocess.run([sys.executable, os.path.join(sys.argv[1], 'collect.py'), '/w/unit-c', '--out', out, '--main', '.'], env=os.environ | {'HOME': home}, capture_output=True, text=True)
share = json.load(open(os.path.join(out, 'result.json'))).get('main_share', {}) if ran.returncode == 0 else ran.stderr[-300:]
check('codex_only_build_gets_main_share: a build with no Claude session still reports what main spent on it', 1, share.get('main', {}).get('requests') if isinstance(share, dict) else share)

skill = open(os.path.join(sys.argv[1], '..', 'SKILL.md')).read()
check('skill_says_tier_estimate: the skill says a response with no recorded speed tier is an estimate', True, bool(re.search(r'speed tier[^.]*estimate', skill)))

print(f'{passed} passed, {failed} failed')
sys.exit(1 if failed else 0)
PY

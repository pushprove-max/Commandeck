#!/usr/bin/env bash
# The build review counts passes the way everything else does: one
# numbered round is one pass (what a pass is).
# A first pass can be three Codex reviewers at once; counted as three passes it
# reads as three on a build that took two, and a pass whose second
# reviewer said NO-GO reads as a GO.
# Run: bash scripts/__tests__/worktreereview-passes.test.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
python3 - "$ROOT/skills/worktreereview/scripts" "$ROOT/scripts/__tests__/fixtures" <<'PY'
import collections, sys
sys.path.insert(0, sys.argv[1])
import collect

def rec(start, end, verdict, findings):
    return {'start': start, 'end': end, 'verdict': verdict, 'findings': findings, 'calls': 2, 'file': f'{start}.jsonl',
            'usage': {'total_tokens': 10}, 'complete': True, 'message': f'said {verdict}'}

failed = checks = 0
def check(name, want, got):
    global failed, checks
    ok = want == got
    failed += not ok
    checks += 1
    print(('ok   ' if ok else 'FAIL ') + name + ('' if ok else f' (expected {want!r}, got {got!r})'))

# Pass 1: three reviewers at once, the second the slowest and the only NO-GO.
# Pass 2: one reviewer, later.
passes = collect.fold_passes([rec(100, 200, 'GO', 0), rec(101, 260, 'NO-GO', 2), rec(102, 180, 'GO', 1), rec(400, 450, 'GO', 0)])
check('three reviewers at once and one later are two passes', 2, len(passes))
check('the pass counts its three reviewers', 3, passes[0]['threads'])
check("one reviewer's NO-GO is the pass's verdict", 'NO-GO', passes[0]['verdict'])
check("the pass's findings are every reviewer's", 3, passes[0]['findings'])
check('the pass ends when its last reviewer ends', 260, passes[0]['end'])
check("every reviewer's Codex calls and tokens are in the pass", (6, 30), (passes[0]['calls'], passes[0]['usage']['total_tokens']))
check("and every reviewer's record, for the command timings", ['100.jsonl', '101.jsonl', '102.jsonl'], passes[0]['files'])
check('a later pass keeps its own verdict', ('GO', 1), (passes[1]['verdict'], passes[1]['threads']))
# A helper thread Codex starts inside a pass gives no verdict: it changes none.
helper = collect.fold_passes([rec(100, 200, 'GO', 0), rec(120, 150, 'none', 0)])
check('a thread with no verdict leaves the pass a GO', ('GO', 2), (helper[0]['verdict'], helper[0]['threads']))
# A reviewer cut off mid-review gave no verdict: the pass must not read as a
# finished GO on the strength of the reviewers that did finish.
cut = rec(101, 150, 'stopped', 0) | {'complete': False}
for name, recs in (('after', [rec(100, 200, 'GO', 0), cut]), ('before', [cut | {'start': 99}, rec(100, 200, 'GO', 0)])):
    p = collect.fold_passes(recs)[0]
    check(f'a reviewer cut off {name} a GO one leaves the pass stopped and unfinished', ('stopped', False), (p['verdict'], p['complete']))
p = collect.fold_passes([rec(100, 200, 'NO-GO', 1), cut])[0]
check('a NO-GO beside a cut-off reviewer stays a NO-GO, unfinished', ('NO-GO', False), (p['verdict'], p['complete']))
p = collect.fold_passes([rec(100, 200, 'none', 0), rec(101, 150, 'GO', 0)])[0]
check('a verdict that starts after a thread with none is still the pass verdict', 'GO', p['verdict'])
# The launch line names the closing pass too.
check('the closing pass is read from its launch line', ('7', 'final'), collect.PASS_CMD.search('builder-codex-pass.sh some-unit 7 final').groups())
# The advisor's tokens ride in the asking call's log row and are priced in their own
# bucket: priced in the builder's too, an advisor call shows up twice in the total.
if collect.PRICES is None:
    print('NOT RUN: the price case needs the dashboard price module (none here)')
else:
    m = 'claude-opus-5-5'
    # Every count is present, as in a real log row: a missing one leaves the call unpriced.
    counts = {'input_tokens': 1000000, 'output_tokens': 0, 'cache_creation_input_tokens': 0, 'cache_read_input_tokens': 0}
    turn = {'type': 'message'} | counts
    asked = {'type': 'advisor_message', 'model': m} | counts
    u = counts | {'iterations': [turn, asked]}
    check("a call that consulted the advisor costs the builder its own tokens only",
          collect.usd(m, counts), collect.usd(m, collect.own_usage(u)))
    builder, advisor = collections.Counter(), collections.Counter()
    collect.add(builder, collect.own_usage(u), m)
    collect.add(advisor, asked, m)
    check('and the two buckets together are the one call plus the one consult', 2 * collect.usd(m, turn), builder['usd'] + advisor['usd'])
# On the passes of tooling-batch-2026-10-12b (the fixture: what the page
# showed, and the round each run really was). 25 Codex runs were counted as 25
# passes: 4 were the Builder's own tests starting Codex and 1 a pass that died
# at its start. A pass is a run a round file names, and its number is that file's.
import json, os, tempfile
rows = json.load(open(os.path.join(sys.argv[2], 'worktreereview-batch-b-passes.json')))
wt = tempfile.mkdtemp()
os.makedirs(f'{wt}/.claude/briefs')
runs = []
for i, r in enumerate(rows):
    tids = [f'tid{i}-{k}' for k in range(r['threads'])]
    runs.append({'start': r['start'], 'end': r['end'], 'files': [f'/s/rollout-2026-10-12T00-00-00-{t}.jsonl' for t in tids]})
    if r['round']:
        with open(f'{wt}/.claude/briefs/unit-b-r{r["round"]}-reports.md', 'w') as f:
            f.write('## Sol (m, read-only)\nReviewed: abc\n' + ''.join(f'Codex thread: {t}\n' for t in tids)
                    + f'Pass: {r["kind"]}\n\nCodex thread: not-in-the-head\n\nVERDICT: GO\n')
# A unit whose name starts with this one's has round files of its own.
open(f'{wt}/.claude/briefs/unit-b-more-r9-reports.md', 'w').write('## Sol\nCodex thread: tid0-0\nPass: final\n\n')
rounds = collect.round_threads(wt, 'unit-b')
collect.number_passes(runs, rounds, [])
check('each pass takes its number from its round file; a run no round file names is 0', [r['round'] for r in rows], [p['n'] for p in runs])
check('only the runs a round file names are passes', 20, sum(1 for p in runs if p['n']))
check("and each takes its round file's kind", [r['kind'] for r in rows if r['round']], [p['kind'] for p in runs if p['n']])
check('44 minutes of review trips the alarm', '44 minutes of Codex review in total (more than 30)', collect.review_flag(runs, 30))
half = [{'start': 0, 'end': 900, 'n': 1}, {'start': 1000, 'end': 1900, 'n': 2}, {'start': 2000, 'end': 9000, 'n': 0}]
check('exactly 30 minutes does not, and a run that is not a pass adds nothing', None, collect.review_flag(half, 30))
# A worktree with no round file at all is not a Builder's: its runs keep the launch-line numbers.
old = [{'start': 100, 'end': 200, 'files': ['a.jsonl']}, {'start': 900, 'end': 950, 'files': ['b.jsonl']}]
collect.number_passes(old, {}, [(95, 4, 'final')])
check('with no round file the launch line still numbers the pass', [(4, 'final'), (2, 'review')], [(p['n'], p['kind']) for p in old])
# The page shows how much of each stage's and each request's input came
# from the cache: cache read / (uncached input + cache write + cache read). A
# request that read nothing shows 0%, and one whose counts are unknown shows no
# number, never 0%. The fixture is a trimmed result.json of the same build.
import re, subprocess
page = os.path.join(wt, 'page.html')
subprocess.run([sys.executable, os.path.join(sys.argv[1], 'render.py'), os.path.join(sys.argv[2], 'worktreereview-render-result.json'), page],
               check=True, capture_output=True)
page = open(page).read()
check('the stage table has a cache-hit column and the request table a cache-read and a cache-hit one',
      (True, True), ('<th class="r">Cache hit</th>' in page, '<th class="r">Cache read</th><th class="r">Cache hit</th>' in page))
check('a stage shows its share, a stage with no call none, and the whole run its own', ['75%', '&ndash;', '98%'],
      re.findall(r'<td class="r hit">(?:<b>)?(.*?)(?:</b>)?</td>', page))
check('a request shows its share; zero cache read is 0%; unknown counts show no number', {'75%', '0%', '&ndash;'},
      set(re.findall(r'<td class="r hit" data-v="[^"]*">(.*?)</td>', page)))
check("and each request's cache read, a dash when unknown", {'6,000', '0', '&ndash;'},
      set(re.findall(r'<td class="r cr" data-v="[^"]*">(.*?)</td>', page)))
full = {'input_tokens': 10, 'cache_creation_input_tokens': 20, 'cache_read_input_tokens': 30}
check('the collector hands on a request\'s uncached input and cache read', (10, 30), collect.cache_counts(full))
check('and neither when one of the three input counts is missing', (None, None), collect.cache_counts({k: v for k, v in full.items() if k != 'cache_creation_input_tokens'}))
# A stage adds its requests up, and a request with an unknown count adds 0: the
# stage then carries how many such requests it holds, and shows no share at all
# rather than one worked out from part of its input.
acc = collections.Counter()
collect.add(acc, full)
collect.add(acc, {k: v for k, v in full.items() if k != 'cache_read_input_tokens'})
check('a stage counts its requests whose input counts are unknown', (2, 1), (acc['calls'], acc['uncounted']))
check('and that count is one of the figures a stage and the whole run hand to the page', True, 'uncounted' in collect.KEYS)
part = json.load(open(os.path.join(sys.argv[2], 'worktreereview-render-result.json')))
part['stages'][0]['builder']['uncounted'] = part['totals']['builder']['uncounted'] = 1
json.dump(part, open(os.path.join(wt, 'part.json'), 'w'))
subprocess.run([sys.executable, os.path.join(sys.argv[1], 'render.py'), os.path.join(wt, 'part.json'), os.path.join(wt, 'part.html')],
               check=True, capture_output=True)
check('a stage or a run holding such a request shows no share', ['&ndash;', '&ndash;', '&ndash;'],
      re.findall(r'<td class="r hit">(?:<b>)?(.*?)(?:</b>)?</td>', open(os.path.join(wt, 'part.html')).read()))
# A result collected before an idle gap said what it waited on has no "waiting"
# key. No such result was found on disk when the key was added, so the page is
# not drawn from a guess: it stops and says to collect again.
aged = json.load(open(os.path.join(sys.argv[2], 'worktreereview-render-result.json')))
for g in aged['idle_gaps']:
    del g['waiting']
json.dump(aged, open(os.path.join(wt, 'old.json'), 'w'))
old = subprocess.run([sys.executable, os.path.join(sys.argv[1], 'render.py'), os.path.join(wt, 'old.json'), os.path.join(wt, 'old.html')],
                     capture_output=True, text=True)
check('a result with an idle gap that names nothing waited on is refused, with the way to collect it again, and no page is written',
      (1, True, False, False), (old.returncode, 'Collect it again' in old.stderr, 'Traceback' in old.stderr, os.path.exists(os.path.join(wt, 'old.html'))))
# A first pass that ends GO with no pass after it merges with no closing
# pass. The page says so, or the build reads as one that stopped short.
first = {'n': 1, 'kind': 'adversarial', 'verdict': 'GO'}
skipped = getattr(collect, 'closing_skipped', lambda _: 'no closing_skipped in collect.py')
check('a first pass GO with no pass after it reads as a skipped closing pass', 'skipped, unchanged since pass 1', skipped([{'n': 0, 'kind': 'not a pass', 'verdict': 'GO'}, first]))
check('a pass after it, a NO-GO first pass, or no pass at all is no skip', [None, None, None],
      [skipped([first, {'n': 2, 'kind': 'final', 'verdict': 'GO'}]), skipped([first | {'verdict': 'NO-GO'}]), skipped([])])
part['closing_pass'] = 'skipped, unchanged since pass 1'
part['passes'] = [first | {'start': 0, 'end': 60, 'usage': {}, 'threads': 3, 'findings': 0, 'message': 'VERDICT: GO',
                            'command_s': 0, 'commands': 0, 'longest': [], 'model': 'm', 'effort': 'high'}]
json.dump(part, open(os.path.join(wt, 'part.json'), 'w'))
subprocess.run([sys.executable, os.path.join(sys.argv[1], 'render.py'), os.path.join(wt, 'part.json'), os.path.join(wt, 'part.html')],
               check=True, capture_output=True)
check('the pass table and the summary both say the closing pass was skipped', 2,
      open(os.path.join(wt, 'part.html')).read().count('losing pass: skipped, unchanged since pass 1'))
# The field was written only for that skip, so a build whose closing
# passes ran read as null. Batch D ran four (5, 7, 9, 10), the last one GO.
ran = getattr(collect, 'closing_pass', lambda _: 'no closing_pass in collect.py')
batch_d = [{'n': n, 'kind': k, 'verdict': v} for n, k, v in [
    (1, 'adversarial', 'NO-GO'), (2, 'review', 'NO-GO'), (3, 'review', 'NO-GO'), (4, 'review', 'GO'), (5, 'final', 'NO-GO'),
    (6, 'review', 'GO'), (7, 'final', 'NO-GO'), (8, 'review', 'GO'), (9, 'final', 'NO-GO'), (10, 'final', 'GO')]]
check('a build with several closing passes names each as it happened', 'pass 5 NO-GO, pass 7 NO-GO, pass 9 NO-GO, pass 10 GO', ran(batch_d[::-1]))
check('a build with passes and no closing one says so, the skip keeps its line, and no pass at all says nothing',
      ['none ran', 'skipped, unchanged since pass 1', None], [ran(batch_d[:4]), ran([first]), ran([{'n': 0, 'kind': 'not a pass', 'verdict': 'GO'}])])
part['closing_pass'] = ran(batch_d)
json.dump(part, open(os.path.join(wt, 'part.json'), 'w'))
subprocess.run([sys.executable, os.path.join(sys.argv[1], 'render.py'), os.path.join(wt, 'part.json'), os.path.join(wt, 'part.html')],
               check=True, capture_output=True)
check('the pass table and the summary both name the closing passes', 2,
      open(os.path.join(wt, 'part.html')).read().count('losing pass: pass 5 NO-GO, pass 7 NO-GO, pass 9 NO-GO, pass 10 GO'))
# The merge moves a worktree's round files into main's archive/briefs-<unit>.tar
# and the worktree is then removed: the review of a merged unit reads them there,
# or every pass would read as a stray Codex run.
import io, tarfile
gone, arch = os.path.join(wt, 'gone', 'unit-c'), os.path.join(wt, 'briefs-unit-c.tar')
with tarfile.open(arch, 'w') as tar:
    for name, text in (('unit-c-r2-reports.md', '## Sol\nCodex thread: tid-c\nPass: final\n\nVERDICT: GO\n'),
                       ('unit-c-more-r5-reports.md', '## Sol\nCodex thread: tid-c\nPass: review\n\n'), ('unit-c.md', 'Codex thread: tid-x\n')):
        info = tarfile.TarInfo(name); info.size = len(text)
        tar.addfile(info, io.BytesIO(text.encode()))
check('a removed worktree\'s round files are read from the merge archive', {'tid-c': (2, 'final')}, collect.round_threads(gone, 'unit-c', arch))
check('a live worktree\'s own round files win over an archive', rounds, collect.round_threads(wt, 'unit-b', arch))
check('and with neither there is no round', {}, collect.round_threads(gone, 'unit-c', os.path.join(wt, 'none.tar')))
# A subagent's compactions were never looked for, so a build whose
# subagents compacted read as cleaner than it was. A whole collector run over a
# Builder log with one compaction, a subagent log with two and one with none.
home, unit_wt = os.path.join(wt, 'home'), '/w/unit-k'
proj = os.path.join(home, '.claude', 'projects', '-w-unit-k')
os.makedirs(os.path.join(proj, 'sess1', 'subagents'))
def log(path, compactions):
    said = {'type': 'assistant', 'message': {'id': 'm1', 'model': 'claude-opus-5-5', 'content': [{'type': 'text', 'text': 'ok'}],
                                             'usage': dict(full, output_tokens=5)}}
    rows = [{'type': 'user', 'message': {'role': 'user', 'content': 'go'}}, said]
    rows += [{'type': 'system', 'subtype': 'compact_boundary', 'compactMetadata': {'preTokens': 400000, 'postTokens': 9000, 'durationMs': 1000}}] * compactions
    with open(path, 'w') as f:
        for i, r in enumerate(rows):
            f.write(json.dumps(r | {'timestamp': f'2026-10-12T00:00:{10 + i:02d}.000Z'}) + '\n')
log(os.path.join(proj, 'sess1.jsonl'), 1)
log(os.path.join(proj, 'sess1', 'subagents', 'agent-a.jsonl'), 2)
log(os.path.join(proj, 'sess1', 'subagents', 'agent-b.jsonl'), 0)
ran = subprocess.run([sys.executable, os.path.join(sys.argv[1], 'collect.py'), unit_wt, '--out', os.path.join(wt, 'k')],
                     env=os.environ | {'HOME': home}, capture_output=True, text=True)
got = json.load(open(os.path.join(wt, 'k', 'result.json'))) if ran.returncode == 0 else {'helpers': [], 'compactions': []}
check('the collector run ends well', (0, ''), (ran.returncode, ran.stderr[-300:] if ran.returncode else ''))
check("each subagent's compactions are counted, 0 for one with none", [2, 0], [h.get('compactions') for h in got['helpers']])
check("and the Builder's own stay its own", 1, len(got['compactions']))
if ran.returncode == 0:
    subprocess.run([sys.executable, os.path.join(sys.argv[1], 'render.py'), os.path.join(wt, 'k', 'result.json'), os.path.join(wt, 'k.html')],
                   check=True, capture_output=True)
shown = open(os.path.join(wt, 'k.html')).read() if os.path.exists(os.path.join(wt, 'k.html')) else ''
check('the top of the page shows one total, Builder plus subagents', ['3 compactions'], re.findall(r'<div class="big">(\d+ compactions?)</div>', shown))
check('and says how it splits', True, '1 by the Builder, 2 by its helpers' in shown)
check('the helpers table shows each count, 0 and not a blank', ['2', '0'], re.findall(r'<td class="r comp" data-v="[^"]*">(.*?)</td>', shown))
# "skipped, unchanged" was said from the last pass alone. A later pass
# that committed and then died before its round file left the build reading as
# unchanged. The line now needs the reviewed tree: the worktree's tip is the
# commit the newest round file names and nothing outside the brief files is
# uncommitted (reviewed-tree.sh, the fact the dashboard reads too).
first_t, dead = first | {'start': 100}, {'n': 0, 'kind': 'not a pass', 'verdict': 'stopped', 'start': 500}
check('closing_skip_needs_reviewed_tree: a changed tree, or a later run with the worktree gone, is no skip',
      [None, None, None, 'none ran'],
      [skipped([first_t], False), skipped([first_t, dead], False), skipped([first_t, dead]), collect.closing_pass([first_t, dead], False)])
check('closing_skip_needs_reviewed_tree: an untouched build after a first-pass GO reads as before',
      ['skipped, unchanged since pass 1'] * 3, [skipped([first_t], True), skipped([first_t]), collect.closing_pass([dead | {'start': 50}, first_t], True)])
g = os.path.join(wt, 'rt')
def git(*a):
    return subprocess.run(['git', '-C', g, '-c', 'user.name=t', '-c', 'user.email=t@t', *a], capture_output=True, text=True, check=True).stdout.strip()
os.makedirs(os.path.join(g, '.claude', 'briefs'))
git('init', '-q'); open(os.path.join(g, 'a.sh'), 'w').write('one\n'); git('add', 'a.sh'); git('commit', '-qm', 'pass 1')
round_file = os.path.join(g, '.claude', 'briefs', 'rt-r1-reports.md')
open(round_file, 'w').write(f'## Sol\nReviewed: {git("rev-parse", "HEAD")}\nCodex thread: t1\nPass: adversarial\n\nVERDICT: GO\n')
tree = getattr(collect, 'reviewed_tree', lambda *_: 'no reviewed_tree in collect.py')
seen = [tree(g, 'rt')]
open(os.path.join(g, 'a.sh'), 'w').write('two\n'); seen.append(tree(g, 'rt'))
git('commit', '-qam', 'a pass that died after its commit'); seen.append(tree(g, 'rt'))
seen.append(tree(os.path.join(wt, 'no-such-worktree'), 'rt'))
check('reviewed_tree: true on the reviewed tip with only brief files uncommitted, false when dirty or past it, None with no worktree',
      [True, False, False, None], seen)
# A worktree that is there but whose round file no longer names a commit cannot be compared: that is never "unchanged".
open(round_file, 'w').write('## Sol\nCodex thread: t1\nPass: adversarial\n\nVERDICT: GO\n')
check('unknown_tree_is_not_unchanged: a live worktree nobody can compare is no skip, though a merged build with no worktree still is',
      [False, None, 'skipped, unchanged since pass 1'], [tree(g, 'rt'), skipped([first_t], tree(g, 'rt')), skipped([first_t], tree(os.path.join(wt, 'no-such-worktree'), 'rt'))])
check('the result is built from that fact', 1, open(collect.__file__).read().count("'closing_pass': closing_pass(runs, reviewed_tree(wt, unit))"))
# Every Codex call read "not priced" though the price table has Codex
# rows. A whole collector run over Codex records: gpt-6.1-sol short and long
# prompts, its fast tier, a fast mode priced by estimate, and a model with no row.
def codex_log(home, cwd, name, model, tier, usages, at=20):
    d = os.path.join(home, '.codex', 'sessions', '2026', '10', '12'); os.makedirs(d, exist_ok=True)
    rows = [{'type': 'turn_context', 'payload': {'cwd': cwd, 'model': model, 'effort': 'medium'}},
            {'type': 'event_msg', 'payload': {'type': 'thread_settings_applied', 'thread_settings': {'model': model, 'service_tier': tier}}}]
    for i, u in enumerate(usages):
        rows += [{'type': 'token_usage_record', 'payload': {'response_id': f'{name}-{i}', 'usage': u}},
                 {'type': 'event_msg', 'payload': {'type': 'token_count', 'info': {'total_token_usage': u}}}]
    rows += [{'type': 'event_msg', 'payload': {'type': 'task_complete', 'last_agent_message': 'VERDICT: GO'}}]
    with open(os.path.join(d, f'rollout-2026-10-12T00-00-{at}-{name}.jsonl'), 'w') as f:
        for r in rows:
            f.write(json.dumps(r | {'timestamp': f'2026-10-12T00:00:{at}.000Z'}) + '\n')
def review(unit, logs):
    h = os.path.join(wt, 'home-' + unit)
    proj = os.path.join(h, '.claude', 'projects', '-w-' + unit); os.makedirs(proj)
    log(os.path.join(proj, 'sess1.jsonl'), 0)
    with open(os.path.join(proj, 'sess1.jsonl'), 'a') as f:
        f.write(json.dumps({'type': 'user', 'message': {'role': 'user', 'content': 'end'}, 'timestamp': '2026-10-12T00:00:50.000Z'}) + '\n')
    for l in logs:
        codex_log(h, '/w/' + unit, *l)
    r = subprocess.run([sys.executable, os.path.join(sys.argv[1], 'collect.py'), '/w/' + unit, '--out', os.path.join(wt, unit)],
                       env=os.environ | {'HOME': h}, capture_output=True, text=True)
    if r.returncode:
        return {'calls': r.stderr[-300:]}, ''
    subprocess.run([sys.executable, os.path.join(sys.argv[1], 'render.py'), os.path.join(wt, unit, 'result.json'), os.path.join(wt, unit + '.html')],
                   check=True, capture_output=True)
    return json.load(open(os.path.join(wt, unit, 'result.json')))['totals']['codex'], open(os.path.join(wt, unit + '.html')).read()
short = {'input_tokens': 1000, 'cached_input_tokens': 400, 'cache_write_input_tokens': 100, 'output_tokens': 50}
long_ = {'input_tokens': 300000, 'cached_input_tokens': 0, 'cache_write_input_tokens': 0, 'output_tokens': 100}
if collect.PRICES is not None:
    c, page = review('unit-p', [('sol', 'gpt-6.1-sol', None, [short, long_])])
    # 500 in, 100 written, 400 read, 50 out at 2/10/0.10; then 300,000 in and 100 out at the over-272K rate 4/15.
    check('codex_priced_by_the_dashboard_table: gpt-6.1-sol, short and long prompts, 0 unpriced calls',
          (round(0.00179 + 1.2015, 6), 0, 2), (round(c.get('usd', 0), 6), c.get('unpriced'), c.get('calls')))
    check('codex_priced_by_the_dashboard_table: the dollars equal the table\'s own price of the same rows', True,
          abs(c.get('usd', 0) - sum(collect.PRICES.price([0, 'gpt-6.1-sol', *r]) for r in ([500, 100, 0, 400, 50], [300000, 0, 0, 0, 100]))) < 1e-12)
    check('codex_priced_by_the_dashboard_table: the page shows the dollars and names no unpriced model', (True, False),
          ('gpt-6.1-sol at medium effort $1.20' in page, 'Not priced' in page))
    c, page = review('unit-f', [('fast', 'gpt-6.1-sol', 'priority', [short])])
    check('codex_fast_tier_at_the_fast_rate: twice the standard rate, not estimated', (0.00358, 0, 0),
          (round(c.get('usd', 0), 6), c.get('unpriced'), c.get('est', 0)))
    c, page = review('unit-e', [('est', 'claude-sonnet-5-5', 'priority', [short]), ('sol', 'gpt-6.1-sol', None, [short])])
    check('codex_estimate_is_marked: a fast mode with no published price is priced by the table\'s estimate and counted as estimated',
          (round(0.00358 + 0.00179, 6), 0.00358, 0), (round(c.get('usd', 0), 6), round(c.get('est', 0), 6), c.get('unpriced')))
    check('codex_estimate_is_marked: the page says how much is estimated, in the dashboard\'s words', 1,
          page.count('of the total is estimated from the nearest published price'))
    c, page = review('unit-u', [('new', 'gpt-9-new', None, [short]), ('sol', 'gpt-6.1-sol', None, [short])])
    check('codex_model_with_no_row_stays_unpriced: counted, and the rest still priced', (0.00179, 1, 2),
          (round(c.get('usd', 0), 6), c.get('unpriced'), c.get('calls')))
    check('codex_model_with_no_row_stays_unpriced: the page marks the unpriced calls', True, '+ unpriced calls' in page)
    c, page = review('unit-n', [('new', 'gpt-9-new', None, [short])])
    check('codex_model_with_no_row_stays_unpriced: alone it has no dollars and is named on the page', (0, 1, True),
          (c.get('usd', 0), c.get('unpriced'), 'Not priced: gpt-9-new at medium effort' in page))
def tried(fn):
    try:
        return fn()
    except Exception as e:
        return f'{type(e).__name__}: {e}'
# Rounds first, overlap second: an unrelated chat that spanned two rounds joined
# them into one pass, which lost the first round and its verdict.
def named(start, end, tid, verdict='GO'):
    return rec(start, end, verdict, 0) | {'file': f'rollout-{tid}.jsonl'}
two = {'r1': (1, 'adversarial'), 'r2': (2, 'final')}
check('a chat that spans two rounds joins neither: two passes and one run outside them', [(100, 200, 1), (110, 300, 1), (250, 350, 1)],
      tried(lambda: [(p['start'], p['end'], p['threads']) for p in collect.fold_passes([named(100, 200, 'r1'), named(110, 300, 'chat', 'none'), named(250, 350, 'r2')], two)]))
check('a helper thread inside a round is still part of that pass', [(100, 200, 2)],
      tried(lambda: [(p['start'], p['end'], p['threads']) for p in collect.fold_passes([named(100, 200, 'r1'), named(120, 150, 'help', 'none')], two)]))
# Codex files a record by its start date: a build of five days lost the passes of its middle days.
check('every date of the build is searched, and one day either side', ['2026/09/30', '2026/10/01', '2026/10/02', '2026/10/03', '2026/10/04', '2026/10/05', '2026/10/06'],
      tried(lambda: collect.codex_days(collect.ts('2026-10-01T12:00:00Z'), collect.ts('2026-10-05T12:00:00Z'))))
# A worktree a Codex seat built alone has no Claude log: the collector stopped before it read a Codex record.
h = os.path.join(wt, 'home-only')
codex_log(h, '/w/unit-only', 'sol', 'gpt-6.1-sol', None, [short])
codex_log(h, '/w/unit-only', 'sol2', 'gpt-6.1-sol', None, [short], at=40)
with open(os.path.join(h, '.codex', 'sessions', '2026', '10', '12', 'rollout-2026-10-12T00-00-20-sol.jsonl'), 'a') as f:
    f.write(json.dumps({'type': 'event_msg', 'payload': {}, 'timestamp': '2026-10-12T00:00:40.000Z'}) + '\n')
r =subprocess.run([sys.executable, os.path.join(sys.argv[1], 'collect.py'), '/w/unit-only', '--out', os.path.join(wt, 'unit-only')],
                   env=os.environ | {'HOME': h}, capture_output=True, text=True)
page = subprocess.run([sys.executable, os.path.join(sys.argv[1], 'render.py'), os.path.join(wt, 'unit-only', 'result.json'), os.path.join(wt, 'unit-only.html')], capture_output=True)
check('a build with only Codex records is collected from them and its page renders', (0, True, 0),
      (r.returncode, '0:20 from 2026-10-12 00:00:20Z, 0 session(s), 2 Codex pass(es)' in r.stdout, page.returncode))
check("and its time is Codex's, not time with no agent open", ["clock: {'codex': '0:20'}"],
      [l.strip() for l in r.stdout.splitlines() if 'clock:' in l])
# orca-ide answers a terminal list as {"result": [...]} too; that shape raised and no flagged report reached its reviewer.
import review, types
pane = {'handle': 'term_x', 'worktreePath': '/w/u/', 'agentIdentity': 'claude'}
for shape, answer in (('a list under result', {'result': [pane]}), ('terminals under result', {'result': {'terminals': [pane]}})):
    review.orca = lambda *a, answer=answer: types.SimpleNamespace(stdout=json.dumps(answer))
    check(f'the pane of a worktree is found when the terminal list is {shape}', 'term_x', tried(lambda: review.pane_in('/w/u')))
# The review shows, per batch item, the rung the Builder recorded in its
# evidence file. The rung in the brief is main's plan, not what was built, so
# an item with no evidence line reads "Not recorded", never that planned rung
# and never an empty cell. Two whole review runs: a unit with lines, one with none.
import glob, shutil
BRIEF = '## The batch\n\n1. [rung 5] #11, first thing\n   more text\n2. [rung 6] #12, second thing\n3. [rung 4] #13, third thing\n'
LINES = ('Ponytail: item 1: rung 2; lazier option: taken\n'
         '- `Ponytail: item 3: rung 6; lazier option: none, the <parser> is new`\n'
         'Ponytail: item 2: rung high; lazier option: a rung that is no number\n')
def rung_review(unit, evidence):
    uwt = os.path.join(os.path.realpath(wt), 'rungs', unit)
    os.makedirs(os.path.join(uwt, '.claude', 'briefs'))
    open(os.path.join(uwt, '.claude', 'briefs', unit + '.md'), 'w').write(BRIEF)
    if evidence is not None:
        open(os.path.join(uwt, '.claude', 'briefs', unit + '-evidence.md'), 'w').write(evidence)
    uproj = os.path.join(home, '.claude', 'projects', re.sub(r'[^A-Za-z0-9]', '-', uwt))
    os.makedirs(uproj)
    log(os.path.join(uproj, 's.jsonl'), 0)
    ran = subprocess.run([sys.executable, os.path.join(sys.argv[1], 'review.py'), uwt, '--out-dir', os.path.join(wt, 'out'), '--no-open', '--no-notify'],
                         env=os.environ | {'HOME': home}, capture_output=True, text=True)
    for work in glob.glob('/tmp/commandeck/worktreereview/*/' + unit):
        shutil.rmtree(work, ignore_errors=True)
    pages = glob.glob(os.path.join(wt, 'out', '*', '*', unit + '-review.html'))
    saved = glob.glob(os.path.join(wt, 'out', '*', '*', unit + '-review.json'))
    return (ran.returncode, open(pages[0]).read() if pages else ran.stderr[-300:], json.load(open(saved[0])).get('rungs') if saved else None)
def rung_rows(page):
    part = page.split('<h2>Rung per batch item</h2>')[-1].split('<h2>')[0] if '<h2>Rung per batch item</h2>' in page else ''
    return [tuple(re.sub(r'<.*?>', '', c) for c in re.findall(r'<td.*?>(.*?)</td>', row)) for row in re.findall(r'<tr>(<td.*?)</tr>', part)], part
rc, page, saved = rung_review(f'rungs-with-{os.getpid()}', LINES)
rows, part = rung_rows(page)
check('a unit with rung lines: each item shows its recorded rung and lazier option; a line with no number is not a rung',
      (0, [('1', '#11', '2', 'taken'), ('2', '#12', 'Not recorded', 'Not recorded'), ('3', '#13', '6', 'none, the &lt;parser&gt; is new')]), (rc, rows))
check('the saved numbers carry the same rows', [(1, '2'), (2, None), (3, '6')], [(r.get('item'), r.get('rung')) for r in saved or []])
check('the page says the review has no per-item tie, so this is one table', True, 'by stage, not by item' in part)
rc, page, saved = rung_review(f'rungs-none-{os.getpid()}', None)
rows, part = rung_rows(page)
check('a unit with no evidence file: every item reads Not recorded, never the rung the brief planned',
      (0, [('1', '#11', 'Not recorded', 'Not recorded'), ('2', '#12', 'Not recorded', 'Not recorded'), ('3', '#13', 'Not recorded', 'Not recorded')]), (rc, rows))
check('and no rung cell is blank', [], [r for r in rows if not all(r)])
# A result with no rung rows at all (an older saved result, a brief with no numbered items) still says so.
check('a result with no rung rows says Not recorded', True,
      'Not recorded' in rung_rows(open(os.path.join(wt, 'part.html')).read())[1])
check('the comment that said no Codex price is on file is gone', 0, open(collect.__file__).read().count('No list price for the Codex models'))
# The wait table named one background test run in all 13 waits of a build and booked 480 s as a
# wait on tests. That call had been refused by a hook, so it never ran and no notice ever ended it. A
# job is running only between its start and its end, and a wait is named after what the pane waited on.
def at(s):
    return datetime.fromtimestamp(1700000000 + s, timezone.utc).isoformat().replace('+00:00', 'Z')
def call(s, tid, name, **inp):
    return {'type': 'assistant', 'timestamp': at(s), 'message': {'id': 'm' + tid, 'content': [{'type': 'tool_use', 'id': tid, 'name': name, 'input': inp}]}}
def answer(s, tid, body, **more):
    return {'type': 'user', 'timestamp': at(s), 'message': {'content': [{'type': 'tool_result', 'tool_use_id': tid, 'content': body} | more]}}
def notice(s, tid):
    return {'type': 'user', 'timestamp': at(s), 'message': {'content': f'<task-notification>\n<tool-use-id>{tid}</tool-use-id>\n<status>completed</status>\n</task-notification>'}}
def turn_end(s):
    return {'type': 'system', 'subtype': 'turn_duration', 'timestamp': at(s)}
import re
from datetime import datetime, timezone
STARTED ='Command running in background with ID: {0}. Output is being written to: /tmp/tasks/{0}.output.'
log = os.path.join(wt, 'waits.jsonl')
with open(log, 'w') as f:
    f.write('\n'.join(json.dumps(r) for r in [
        {'type': 'user', 'timestamp': at(0), 'message': {'content': 'go'}},
        # A test run that starts, ends after 10 s and is announced.
        call(10, 'toolu_ran', 'Bash', run_in_background=True, description='Run the whole self-test file', command='bash run-shell-tests.sh x'),
        answer(11, 'toolu_ran', STARTED.format('b1')), notice(21, 'toolu_ran'),
        # The same run asked for again and refused by a hook: it never started.
        call(30, 'toolu_refused', 'Bash', run_in_background=True, description='Run the whole self-test file again', command='bash run-shell-tests.sh x'),
        answer(31, 'toolu_refused', 'PreToolUse:Bash hook error: [guard.sh]: BLOCKED', is_error=True),
        # Wait 1: on a helper, which the harness runs in the background without the flag.
        call(40, 'toolu_helper', 'Agent', description='[#1] look it up', subagent_type='Explore'),
        answer(41, 'toolu_helper', 'Async agent launched successfully.\nagentId: a1'), turn_end(50), notice(150, 'toolu_helper'),
        # Wait 2: on main, after a question; main's answer is the next row.
        call(160, 'toolu_ask', 'Bash', description='Ask main', command='orca-ide orchestration send --from t --type question --subject s'),
        answer(161, 'toolu_ask', 'Sent msg_1'), turn_end(170), {'type': 'user', 'timestamp': at(300), 'message': {'content': 'answer from main'}},
        # Wait 3: on a Codex pass, beside a test run whose output the pane read and whose notice never came.
        call(310, 'toolu_pass', 'Bash', run_in_background=True, description='Run the first Codex pass', command='.claude/scripts/builder-codex-pass.sh unit 1 adversarial'),
        answer(311, 'toolu_pass', STARTED.format('b2')),
        call(312, 'toolu_unannounced', 'Bash', run_in_background=True, description='Run the touched test file', command='bash run-shell-tests.sh y'),
        answer(313, 'toolu_unannounced', STARTED.format('b3')),
        call(330, 'toolu_read', 'TaskOutput', task_id='b3'), answer(331, 'toolu_read', '<retrieval_status>success</retrieval_status>\n<status>completed</status>\n3 passed, 0 failed'),
        turn_end(340), notice(500, 'toolu_pass'),
        # Wait 4: nothing asked and nothing running.
        turn_end(510), {'type': 'user', 'timestamp': at(600), 'message': {'content': 'carry on'}},
    ]) + '\n')
sess = collect.read_session(log)
kind = lambda t: collect.call_kind(t, re.compile(collect.TEST_RE, re.I))
waits = [collect.idle_gap(sess, end, min(u for u in sess['users'] if u > end), sess['last'], kind) for end in sess['turn_ends']]
check('a job that ended, and one that was refused, are named in no later wait', [], [p for _, g in waits for p in g['pending'] if 'self-test' in p])
check('each wait names the job still running in it', [['[#1] look it up'], [], ['Run the first Codex pass'], []], [g['pending'] for _, g in waits])
check('a wait is named after what the pane waited on: a helper, main, a Codex pass, nothing', ['helper', 'main', 'codex', 'nothing'], [g['waiting'] for _, g in waits])
check('and none of them is booked on the clock as a wait on tests', ['idle_job', 'idle', 'idle_job', 'idle'], [label for label, _ in waits])
# A test run that is really still running does name its wait.
sess['woken'].pop('toolu_ran')
check('a test run still going is what its wait is on', ('idle_tests', 'tests'), (lambda w: (w[0], w[1]['waiting']))(collect.idle_gap(sess, sess['turn_ends'][1], sess['turn_ends'][1] + 130, sess['last'], kind)))
# Looking at a running job does not end it: only its announced end, or an output read that says it ended,
# does, and the earlier of the two is when it ended. A wait beside a job wrongly ended reads "nothing".
with open(log, 'w') as f:
    f.write('\n'.join(json.dumps(r) for r in [
        {'type': 'user', 'timestamp': at(0), 'message': {'content': 'go'}},
        call(10, 'toolu_long', 'Bash', run_in_background=True, description='Run the long test file', command='bash run-shell-tests.sh z'),
        answer(11, 'toolu_long', STARTED.format('b7')),
        call(20, 'toolu_tail', 'Bash', description='Look at the run so far', command='tail -n 3 /tmp/tasks/b7.output; echo b7'), answer(21, 'toolu_tail', 'still running'),
        call(22, 'toolu_file', 'Read', file_path='/tmp/tasks/b7.output'), answer(23, 'toolu_file', '<status>completed</status> is what a finished job says'),
        call(24, 'toolu_poll', 'TaskOutput', task_id='b7', block=False), answer(25, 'toolu_poll', '<retrieval_status>not_ready</retrieval_status>\n<status>running</status>'),
        turn_end(30), {'type': 'user', 'timestamp': at(100), 'message': {'content': 'carry on'}},
        call(110, 'toolu_got', 'TaskOutput', task_id='b7'), answer(120, 'toolu_got', '<retrieval_status>success</retrieval_status>\n<status>completed</status>'),
        turn_end(130), notice(200, 'toolu_long'),
    ]) + '\n')
sess = collect.read_session(log)
waits = [collect.idle_gap(sess, end, min(u for u in sess['users'] if u > end), sess['last'], kind) for end in sess['turn_ends']]
check('a job looked at while it runs (a tail, its output file, a poll) is still what the wait is on', (['Run the long test file'], 'tests'), (waits[0][1]['pending'], waits[0][1]['waiting']))
# The same looks at a job whose end is never announced or read: still running, so still waited on.
with open(log) as f:
    rows = f.read().splitlines()
with open(log, 'w') as f:
    f.write('\n'.join(rows[:11]) + '\n')
unended = collect.read_session(log)
check('and so is one whose end the log never shows', (['Run the long test file'], 'tests'), (lambda g: (g['pending'], g['waiting']))(collect.idle_gap(unended, unended['turn_ends'][0], unended['users'][-1], unended['last'], kind)[1]))
check('a job whose output read says it ended is in no later wait, however late its notice', ([], 'nothing'), (waits[1][1]['pending'], waits[1][1]['waiting']))
# A job tool's answer carries the job's own output, and that output can hold any text. Only the
# tool's own status, ahead of the output, says the job ended; a job wrongly ended drops out of later waits.
# The stop answer is the shape the session logs of this machine hold: one JSON object, in a string.
with open(log, 'w') as f:
    f.write('\n'.join(json.dumps(r) for r in [
        {'type': 'user', 'timestamp': at(0), 'message': {'content': 'go'}},
        call(10, 'toolu_echo', 'Bash', run_in_background=True, description='Run the test file that prints a status', command='bash run-shell-tests.sh q'),
        answer(11, 'toolu_echo', STARTED.format('b8')),
        call(12, 'toolu_watch', 'Bash', run_in_background=True, description='Watch the inbox', command='watch-inbox.sh'),
        answer(13, 'toolu_watch', STARTED.format('b9')),
        call(20, 'toolu_peek', 'TaskOutput', task_id='b8', block=False),
        answer(21, 'toolu_peek', '<retrieval_status>not_ready</retrieval_status>\n\n<task_id>b8</task_id>\n\n<status>running</status>\n\n<output>\n<status>completed</status>\nSuccessfully stopped task: b8\n</output>'),
        turn_end(30), {'type': 'user', 'timestamp': at(100), 'message': {'content': 'carry on'}},
        call(110, 'toolu_stop', 'TaskStop', task_id='b9'),
        answer(111, 'toolu_stop', json.dumps({'message': 'Successfully stopped task: b9 (watch-inbox.sh)', 'task_id': 'b9', 'task_type': 'local_bash', 'command': 'watch-inbox.sh'})),
        call(112, 'toolu_blocks', 'TaskOutput', task_id='b8'),
        answer(113, 'toolu_blocks', [{'type': 'text', 'text': '<retrieval_status>success</retrieval_status>\n\n<task_id>b8</task_id>\n\n<status>failed</status>\n\n<output>\n1 passed, 1 failed\n</output>'}]),
        turn_end(130), {'type': 'user', 'timestamp': at(200), 'message': {'content': 'carry on'}},
    ]) + '\n')
sess = collect.read_session(log)
waits = [collect.idle_gap(sess, end, min(u for u in sess['users'] if u > end), sess['last'], kind)[1] for end in sess['turn_ends']]
check('a job the tool reports running is still waited on, whatever status its captured output prints', (['Run the test file that prints a status', 'Watch the inbox'], 'tests'), (waits[0]['pending'], waits[0]['waiting']))
check('a job the tool itself reports stopped or failed is in no later wait', ([], 'nothing'), (waits[1]['pending'], waits[1]['waiting']))
# The collector kept the label of an idle wait under the name of its own list of clock ticks, so
# after the first wait the clock was counted from that label's letters and the page had no name for them.
# The cases above call idle_gap directly or render a saved result; this one collects and then renders.
import ast
h = os.path.join(wt, 'home-idle')
os.makedirs(os.path.join(h, '.claude', 'projects', '-w-idle'))
with open(os.path.join(h, '.claude', 'projects', '-w-idle', 'sess1.jsonl'), 'w') as f:
    f.write('\n'.join(json.dumps(r) for r in [
        {'type': 'system', 'subtype': 'local_command', 'timestamp': at(0)}, {'type': 'user', 'timestamp': at(5), 'message': {'content': 'go'}},
        call(7, 'toolu_look', 'Read', file_path='/w/idle/a'), answer(8, 'toolu_look', 'a'),
        # The one idle wait: 30 s with nothing asked and nothing running.
        turn_end(10), {'type': 'user', 'timestamp': at(40), 'message': {'content': 'carry on'}},
    ]) + '\n')
r = subprocess.run([sys.executable, os.path.join(sys.argv[1], 'collect.py'), '/w/idle', '--out', os.path.join(wt, 'idle')],
                   env=os.environ | {'HOME': h}, capture_output=True, text=True)
clock = json.load(open(os.path.join(wt, 'idle', 'result.json')))['clock'] if r.returncode == 0 else {'collect.py': r.stderr[-300:]}
slices = next(ast.literal_eval(n.value) for n in ast.parse(open(os.path.join(sys.argv[1], 'render.py')).read()).body
              if isinstance(n, ast.Assign) and n.targets[0].id == 'CLOCK')
check('after an idle wait every slice of the collected clock is one the page names', [], sorted(set(clock) - {k for k, *_ in slices}))
check('and the wait is booked as idle time with nothing running', 30.0, clock.get('idle'))
page = subprocess.run([sys.executable, os.path.join(sys.argv[1], 'render.py'), os.path.join(wt, 'idle', 'result.json'), os.path.join(wt, 'idle.html')], capture_output=True, text=True)
check('and the page renders from that collected result', (0, True), (page.returncode, os.path.exists(os.path.join(wt, 'idle.html'))) if page.returncode == 0 else page.stderr[-200:])
# How many reviewers a first pass gets turns on the build's lines changed, and
# of 24 merged builds only the small ones passed first time, so every build
# review shows the number: insertions plus deletions against the fork from
# main, the brief files left out as the merge leaves them out.
sized = os.path.join(wt, 'sized')
os.makedirs(os.path.join(sized, '.claude', 'briefs'))
def git(*a):
    subprocess.run(['git', '-C', sized, '-c', 'user.name=t', '-c', 'user.email=t@t', '-c', 'core.hooksPath=/dev/null', *a], check=True, capture_output=True)
def put(name, text):
    open(os.path.join(sized, name), 'w').write(text)
git('init', '-q', '-b', 'main')
put('a.txt', 'one\ntwo\nthree\n')
git('add', '-A'); git('commit', '-qm', 'base'); git('checkout', '-qb', 'unit')
put('a.txt', 'one\nthree\nfour\nfive\n'); put('.claude/briefs/unit-evidence.md', 'notes\n' * 50)
git('add', '-A'); git('commit', '-qm', 'build')
lines = getattr(collect, 'lines_changed', lambda _: 'no lines_changed in collect.py')
check('lines changed is insertions plus deletions against the fork from main, the brief files left out', 3, lines(sized))
put('b.txt', 'new\n' * 7); git('add', '-A'); git('commit', '-qm', 'more')
check('a later commit of insertions only adds to it', 10, lines(sized))
check('a worktree that is gone has no count', None, lines(os.path.join(wt, 'gone')))
check('the result record carries the number', True, 'lines_changed' in json.load(open(os.path.join(wt, 'idle', 'result.json'))))
json.dump(json.load(open(os.path.join(sys.argv[2], 'worktreereview-render-result.json'))) | {'lines_changed': 1234}, open(os.path.join(wt, 'part.json'), 'w'))
subprocess.run([sys.executable, os.path.join(sys.argv[1], 'render.py'), os.path.join(wt, 'part.json'), os.path.join(wt, 'part.html')],
               check=True, capture_output=True)
check('the page shows it beside the pass list', 1, open(os.path.join(wt, 'part.html')).read().count('Lines changed by the build: 1,234'))
# Time a Builder sat waiting on the owner is not build time (the owner, 2026-10-14). A window given by hand
# (--exclude) and one found in the idle gaps (behind an open decision for this unit, or after its DONE
# until new work comes) come out of every clock figure, share and flag; cost stays as it was.
import contextlib, io
h = os.path.join(wt, 'home-cut')
os.makedirs(os.path.join(h, '.claude', 'projects', '-w-unit-cut'))
def say(s, text):
    return {'type': 'assistant', 'timestamp': at(s), 'message': {'id': f'm{s}', 'model': 'claude-opus-5-5', 'content': [{'type': 'text', 'text': text}],
            'usage': {'input_tokens': 10, 'cache_creation_input_tokens': 0, 'cache_read_input_tokens': 0, 'output_tokens': 5}}}
def prompt(s):
    return {'type': 'user', 'timestamp': at(s), 'message': {'content': 'carry on'}}
with open(os.path.join(h, '.claude', 'projects', '-w-unit-cut', 'sess1.jsonl'), 'w') as f:
    f.write('\n'.join(json.dumps(r) for r in [
        {'type': 'user', 'timestamp': at(0), 'message': {'content': 'go'}},
        say(10, 'asked main'), turn_end(20), prompt(60),            # A: 40 s inside D1, under two minutes: kept
        say(90, 'asked again'), turn_end(100), prompt(400),         # B: inside D1 from 100 to 300: cut 200 s
        say(490, 'working'), turn_end(500), prompt(800),            # C: inside a decision of unit-cut-2 only: kept
        say(890, 'working'), turn_end(900), prompt(1200),           # D: no decision, no DONE: kept
        call(1250, 'toolu_bgtest', 'Bash', run_in_background=True, description='Run the touched test file', command='bash run-shell-tests.sh c'),
        answer(1251, 'toolu_bgtest', STARTED.format('b5')),
        turn_end(1300), prompt(1600), notice(1610, 'toolu_bgtest'),  # E: inside D3, a test still running: kept
        # F: the DONE marker ends a long last message, past the 220 characters a note keeps; cut 1660 to 2000.
        say(1650, 'All built. ' + 'x' * 300 + '\nUNIT-CUT-DONE'), turn_end(1660), prompt(2000),
        say(2090, 'more work'), turn_end(2100), prompt(2400),       # G: DONE was an earlier turn: kept, but for a hand window
        say(2490, 'a question'), turn_end(2500), prompt(2800),      # H: inside D4, answered to this unit: cut 300 s
        # I: DONE again, but a Codex run the pane never started as a tool works from 3000 to 3200: kept.
        say(2950, 'Fixed.\nUNIT-CUT-DONE'), turn_end(2960), prompt(3300),
        say(3400, 'done'),
    ]) + '\n')
os.makedirs(os.path.join(h, '.codex', 'sessions', '2023', '11', '14'))
with open(os.path.join(h, '.codex', 'sessions', '2023', '11', '14', 'rollout-cut.jsonl'), 'w') as f:
    f.write(json.dumps({'timestamp': at(3000), 'type': 'turn_context', 'payload': {'cwd': '/w/unit-cut', 'model': 'gpt-x', 'effort': 'high'}}) + '\n'
            + json.dumps({'timestamp': at(3200), 'type': 'event_msg', 'payload': {'type': 'task_complete', 'last_agent_message': 'VERDICT: GO'}}) + '\n')
decisions = os.path.join(wt, 'decisions.jsonl')
with open(decisions, 'w') as f:
    # The ledger is append-only: a decision's asked row (answeredAt null) stays above its answered row.
    for d in [{'id': 'D1', 'askedAt': at(15), 'answeredAt': None, 'source': 'run 1 (unit-cut) question msg_1'},
              {'id': 'D1', 'askedAt': at(15), 'answeredAt': at(300), 'source': 'run 1 (unit-cut) question msg_1', 'answer': 'A'},
              {'id': 'D2', 'askedAt': at(450), 'answeredAt': at(900), 'source': 'run 2 (unit-cut-2) question msg_2', 'answer': 'B'},
              {'id': 'D3', 'askedAt': at(1250), 'answeredAt': at(1700), 'source': 'run 1 (unit-cut) question msg_3', 'answer': 'A'},
              {'id': 'D4', 'askedAt': at(2450), 'answeredAt': at(2900), 'source': 'main', 'answer': 'A. Sent to unit-cut (tag X).'}]:
        f.write(json.dumps(d) + '\n')
def collect_cut(out, decisions_file, *extra, unit='/w/unit-cut'):
    argv0, home0 = sys.argv, os.environ['HOME']
    collect.DECISIONS, sys.argv = decisions_file, ['collect.py', unit, '--out', os.path.join(wt, out), '--max-test-share', '0', *extra]
    os.environ['HOME'] = h
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            collect.main()
    finally:
        sys.argv, os.environ['HOME'] = argv0, home0
    return json.load(open(os.path.join(wt, out, 'result.json')))
try:
    cut = collect_cut('cut', decisions, '--exclude', f'{at(1700)}={at(1900)}', '--exclude', f'{at(2150)}={at(2250)}')
except BaseException as e:  # argparse refuses an unknown option with SystemExit
    cut = {'error': repr(e)[:300]}
ts0 = collect.ts(at(0))
windows = sorted((round(w['start'] - ts0), round(w['end'] - ts0), round(w['seconds']), w['reason']) for w in cut.get('cut', []))
check('each cut window is listed with start, end, length and reason', [(100, 300, 200, 'decision D1'), (1660, 2000, 340, 'finished, awaiting answers'),
      (1700, 1900, 200, 'by hand'), (2150, 2250, 100, 'by hand'), (2500, 2800, 300, 'decision D4')], windows)
check('a hand window inside an auto window cuts its seconds once: 940 s in all', 940, round(cut.get('cut_s', -1)))
check('the clock adds up to the wall time minus the cut windows', 3400 - 940, round(sum(cut.get('clock', {}).values())))
check('the idle slices lose exactly the cut seconds, a gap with a test or Codex running keeps all of its own',
      (40 + 100 + 300 + 300 + 200 + 40 + 100, 300, 200), tuple(round(cut.get('clock', {}).get(k, 0)) for k in ('idle', 'idle_tests', 'codex')))
check('each idle gap carries the seconds cut from it', [0, 200, 0, 0, 0, 340, 100, 300, 0], [round(g.get('cut_s', -1)) for g in cut.get('idle_gaps', [])])
check('a Codex pass fully cut by hand trips no review flag', None,
      collect.review_flag([{'n': 1, 'start': 0, 'end': 31 * 60, 'cut_s': 31 * 60}], 30))
check('each stage loses its share of the cut', [round(s['end'] - s['start'] - s.get('cut_s', 0)) for s in cut.get('stages', [])],
      [round(sum(s['clock'].values())) for s in cut.get('stages', [])])
c = cut.get('clock', {})
check('the test-and-idle flag is a share of the clock that was not cut',
      [f"{100 * (c.get('tests', 0) + c.get('idle', 0) + c.get('idle_tests', 0) + c.get('idle_job', 0)) / (3400 - 940):.0f}% of the clock on tests or idle waits (more than 0%)"],
      [x for x in cut.get('flags', []) if 'idle' in x])
try:
    plain = collect_cut('cut-plain', os.path.join(wt, 'no-decisions.jsonl'))
except BaseException as e:
    plain = {'error': repr(e)[:300]}
check('with no decisions file and no hand window only the wait after DONE is cut', [(1660, 2000)],
      [(round(w['start'] - ts0), round(w['end'] - ts0)) for w in plain.get('cut', [])])
check('and cost is the same with or without the cuts', plain.get('totals'), cut.get('totals'))
page = subprocess.run([sys.executable, os.path.join(sys.argv[1], 'render.py'), os.path.join(wt, 'cut', 'result.json'), os.path.join(wt, 'cut.html')], capture_output=True, text=True)
shown = open(os.path.join(wt, 'cut.html')).read() if page.returncode == 0 else page.stderr[-300:]
check('the page names every cut window and its reason', [True] * 4,
      [all(x in shown for x in ('decision D1', '3:20')), 'finished, awaiting answers' in shown, 'by hand' in shown, 'decision D4' in shown])
check('and its clock shares are of the time left after the cuts', True, 98 <= sum(int(x) for x in re.findall(r'&middot; (\d+)% of the run', shown)) <= 102)
check("the summary's dearest stage takes its time after the cuts: 3000 - 940 s", True, 'in 34:20.' in shown)
whole = json.load(open(os.path.join(sys.argv[2], 'worktreereview-render-result.json')))
json.dump(whole | {'cut_s': whole['end'] - whole['start'], 'clock': {}}, open(os.path.join(wt, 'allcut.json'), 'w'))
page = subprocess.run([sys.executable, os.path.join(sys.argv[1], 'render.py'), os.path.join(wt, 'allcut.json'), os.path.join(wt, 'allcut.html')], capture_output=True, text=True)
check('a run cut from end to end still renders', (0, ''), (page.returncode, page.stderr[-200:]))
# Two sessions in one worktree: what keeps a gap build time is a job running in ANY of them, not only in the
# session whose gap it is. And a decision asked again later is a second window, not a rewrite of the first.
os.makedirs(os.path.join(h, '.claude', 'projects', '-w-unit-two'))
for name, rows in (('sa', [{'type': 'user', 'timestamp': at(0), 'message': {'content': 'go'}},
                           say(10, 'asked'), turn_end(20), prompt(400),                      # inside D9's first window: cut
                           say(450, 'Built.\nUNIT-TWO-DONE'), turn_end(460), prompt(1300),  # session B's test runs: kept
                           say(1400, 'done'), turn_end(1410), prompt(1700),                # D8 asked, re-asked, answered before: kept
                           say(1750, 'done')]),
                   ('sb', [{'type': 'user', 'timestamp': at(500), 'message': {'content': 'go'}},
                           call(550, 'toolu_btest', 'Bash', run_in_background=True, description='Run the touched test file', command='bash run-shell-tests.sh b'),
                           answer(551, 'toolu_btest', STARTED.format('b6')), turn_end(560), prompt(1250), notice(1260, 'toolu_btest'),
                           say(1350, 'read it')]),
                   # Session C runs a command in the foreground from 100 to 300, inside session A's decision gap.
                   ('sc', [{'type': 'user', 'timestamp': at(90), 'message': {'content': 'go'}},
                           call(100, 'toolu_cmake', 'Bash', description='Build the bundle', command='make bundle'), answer(300, 'toolu_cmake', 'ok')])):
    with open(os.path.join(h, '.claude', 'projects', '-w-unit-two', f'{name}.jsonl'), 'w') as f:
        f.write('\n'.join(json.dumps(r) for r in rows) + '\n')
with open(os.path.join(wt, 'decisions-two.jsonl'), 'w') as f:
    for d in [{'id': 'D9', 'askedAt': at(0), 'answeredAt': None, 'source': 'run 1 (unit-two) question'},
              {'id': 'D9', 'askedAt': at(0), 'answeredAt': at(500), 'source': 'run 1 (unit-two) question'},
              {'id': 'D9', 'askedAt': at(5000), 'answeredAt': None, 'source': 'run 1 (unit-two) asked again'},
              # Asked, never answered as such, asked again and answered: the first ask closes at the second.
              {'id': 'D8', 'askedAt': at(1000), 'answeredAt': None, 'source': 'run 1 (unit-two) question'},
              {'id': 'D8', 'askedAt': at(1100), 'answeredAt': None, 'source': 'run 1 (unit-two) asked again'},
              {'id': 'D8', 'askedAt': at(1100), 'answeredAt': at(1200), 'source': 'run 1 (unit-two) asked again'},
              # Asked for this unit, then re-asked for another and answered there: the re-ask closes this unit's window.
              {'id': 'D7', 'askedAt': at(1000), 'answeredAt': None, 'source': 'run 1 (unit-two) question'},
              {'id': 'D7', 'askedAt': at(1100), 'answeredAt': at(1200), 'source': 'run 2 (unit-other) question'}]:
        f.write(json.dumps(d) + '\n')
argv0, home0 = sys.argv, os.environ['HOME']
collect.DECISIONS, sys.argv, os.environ['HOME'] = os.path.join(wt, 'decisions-two.jsonl'), ['collect.py', '/w/unit-two', '--out', os.path.join(wt, 'two')], h
try:
    with contextlib.redirect_stdout(io.StringIO()):
        collect.main()
    two = json.load(open(os.path.join(wt, 'two', 'result.json')))
except BaseException as e:
    two = {'error': repr(e)[:300]}
finally:
    sys.argv, os.environ['HOME'] = argv0, home0
check("a gap is kept while another session's background test runs, and a re-asked decision keeps its first window",
      [(20, 400, 'decision D9')], [(round(w['start'] - ts0), round(w['end'] - ts0), w['reason']) for w in two.get('cut', [])])
check("and another session's foreground work inside a cut gap stays build time: 380 s less its request and command, 90 to 300", [170], [round(w['seconds']) for w in two.get('cut', [])])
# A hand window can cover active work: the request and tool timings lose the cut seconds too, or the page
# shows requests taking more than the run.
try:
    allcut = collect_cut('two-all', os.path.join(wt, 'no-decisions.jsonl'), '--exclude', f'{at(0)}={at(1750)}', unit='/w/unit-two')
except BaseException as e:
    allcut = {'error': repr(e)[:300]}
tm = allcut.get('timing', {'requests': [{'s': -1}], 'tools': [{'s': -1, 'run': -1}]})
check('a run cut end to end leaves no request or tool time', (0, 0, 0), (round(sum(r['s'] for r in tm['requests'])),
      round(sum(t['s'] for t in tm['tools'])), round(sum(t['run'] for t in tm['tools']))))
bad = subprocess.run([sys.executable, os.path.join(sys.argv[1], 'collect.py'), '/w/unit-cut', '--out', os.path.join(wt, 'bad'), '--exclude', f'{at(900)}={at(800)}'],
                     env=os.environ | {'HOME': h}, capture_output=True, text=True)
check('a window that ends before it starts is refused', (2, True), (bad.returncode, 'END' in bad.stderr))
# The decisions are the reviewed project's, found from its worktree: the plugin runs from a checkout of
# its own, and that checkout's ledger names other projects' units, or nothing.
host_main = os.path.join(wt, 'host')
os.makedirs(os.path.join(host_main, '.claude', 'metrics'))
git_q = ['git', '-c', 'user.email=t@example.com', '-c', 'user.name=t', '-C', host_main]
subprocess.run(['git', 'init', '-q', host_main], check=True)
subprocess.run(git_q + ['commit', '-q', '--allow-empty', '-m', 'x'], check=True)
subprocess.run(git_q + ['worktree', 'add', '-q', os.path.join(wt, 'host-wt', 'unit-cut')], check=True, capture_output=True)
host_wt = os.path.realpath(os.path.join(wt, 'host-wt', 'unit-cut'))
shutil.copy(decisions, os.path.join(host_main, '.claude', 'metrics', 'decisions.jsonl'))
os.makedirs(os.path.join(h, '.claude', 'projects', re.sub(r'[^A-Za-z0-9]', '-', host_wt)))
shutil.copy(os.path.join(h, '.claude', 'projects', '-w-unit-cut', 'sess1.jsonl'), os.path.join(h, '.claude', 'projects', re.sub(r'[^A-Za-z0-9]', '-', host_wt)))
try:
    found = os.path.realpath(collect.main_checkout(host_wt) or '/none')
except TypeError as e:  # a main_checkout() that takes no worktree
    found = repr(e)
check("the main checkout is the reviewed project's, not the plugin's", os.path.realpath(host_main), found)
try:
    host = collect_cut('host', None, unit=host_wt)
except BaseException as e:
    host = {'error': repr(e)[:300]}
check("with no ledger given, the project's own decisions cut their windows (and no Codex run here keeps the last gap)",
      [(100, 300, 'decision D1'), (1660, 2000, 'finished, awaiting answers'), (2500, 2800, 'decision D4'), (2960, 3300, 'finished, awaiting answers')],
      [(round(w['start'] - ts0), round(w['end'] - ts0), w['reason']) for w in host.get('cut', [])])
# After the merge removes the worktree nothing on the machine proves which checkout it came from: a
# working folder, a COMMANDECK_WORKSPACES, a ledger lying about can each name another project. Only the
# checkout given with --main is read, and with none no decision is.
subprocess.run(git_q + ['worktree', 'remove', '--force', host_wt], check=True)
check("the worktree really is gone", False, os.path.isdir(host_wt))
try:
    gone = (os.path.realpath(collect.main_checkout(host_wt, host_main) or '/none'), collect_cut('host-gone', None, '--main', host_main, unit=host_wt))
except BaseException as e:
    gone = (repr(e)[:300], {})
check("with the worktree removed, the checkout given with --main is the project's", os.path.realpath(host_main), gone[0])
check("and its decisions still cut their windows", [w['reason'] for w in host.get('cut', [])], [w['reason'] for w in gone[1].get('cut', [])])
# Each way a guess could name the wrong project, with no --main: run from that project's checkout (or the
# plugin's), from it with COMMANDECK_WORKSPACES naming the worktree's folder, from a folder that is no
# checkout with a ledger in it. None is taken, and only the waits after DONE are cut.
other = os.path.join(wt, 'other')
os.makedirs(os.path.join(other, '.claude', 'metrics'))
subprocess.run(['git', 'init', '-q', other], check=True)
shutil.copy(decisions, os.path.join(other, '.claude', 'metrics', 'decisions.jsonl'))
plain = os.path.join(wt, 'plain')
os.makedirs(os.path.join(plain, '.claude', 'metrics'))
shutil.copy(decisions, os.path.join(plain, '.claude', 'metrics', 'decisions.jsonl'))
cwd0 = os.getcwd()
for name, folder, spaces in (('another checkout', other, None), ('the project checkout itself', host_main, None),
                             ('a checkout with COMMANDECK_WORKSPACES on the worktree folder', other, os.path.join(wt, 'host-wt')),
                             ('a folder that is no checkout', plain, None)):
    os.chdir(folder)
    if spaces:
        os.environ['COMMANDECK_WORKSPACES'] = spaces
    try:
        guess = (collect.main_checkout(host_wt), collect_cut('host-guess', None, unit=host_wt))
    except BaseException as e:
        guess = (repr(e)[:300], {})
    finally:
        os.chdir(cwd0)
        os.environ.pop('COMMANDECK_WORKSPACES', None)
    check(f"removed and no --main, run from {name}: no checkout taken, no decision read",
          (None, ['finished, awaiting answers'] * 2), (guess[0], [w['reason'] for w in guess[1].get('cut', [])]))
# A unit name may hold dots: a decision for unit.v1 is not one for unit, nor unit for unit.v1; a full stop
# that ends a sentence after the name still names it.
with open(os.path.join(wt, 'dotted-decisions.jsonl'), 'w') as f:
    for d in [{'id': 'E1', 'askedAt': at(0), 'answeredAt': at(100), 'source': 'run 1 (unit.v1) question'},
              {'id': 'E2', 'askedAt': at(0), 'answeredAt': at(100), 'source': 'main', 'answer': 'A. Sent to v2.unit'},
              {'id': 'E3', 'askedAt': at(0), 'answeredAt': at(100), 'source': 'main', 'answer': 'A. Sent to unit.'}]:
        f.write(json.dumps(d) + '\n')
check('a decision names a dotted sibling of the unit, or the unit at the end of a sentence',
      (['E3'], ['E1']), ([i for _, _, i in collect.decisions_for(os.path.join(wt, 'dotted-decisions.jsonl'), 'unit')],
                        [i for _, _, i in collect.decisions_for(os.path.join(wt, 'dotted-decisions.jsonl'), 'unit.v1')]))
# A unit name may hold dots and underscores; its DONE line is the same name in capitals.
with open(os.path.join(wt, 'dotted.jsonl'), 'w') as f:
    f.write('\n'.join(json.dumps(r) for r in [say(10, 'Built.\nUNIT_V1.2-DONE'), say(20, 'Not a marker: UNIT-DONE later')]) + '\n')
check('a DONE line of a name with dots and underscores is read, one only at the end of a line', ['UNIT_V1.2-DONE'],
      [m for _, m in collect.read_session(os.path.join(wt, 'dotted.jsonl'))['dones']])
# A cut request loses its cut seconds from its wait and its thinking too, not only from its length:
# asked at 0, the model began at 10 and thought until 50, and wrote at 60.
os.makedirs(os.path.join(h, '.claude', 'projects', '-w-unit-think'))
with open(os.path.join(h, '.claude', 'projects', '-w-unit-think', 's.jsonl'), 'w') as f:
    usage = {'input_tokens': 10, 'cache_creation_input_tokens': 0, 'cache_read_input_tokens': 0, 'output_tokens': 5}
    f.write('\n'.join(json.dumps(r) for r in [
        {'type': 'user', 'timestamp': at(0), 'message': {'content': 'go'}},
        {'type': 'assistant', 'timestamp': at(50), 'requestId': 'rq', 'thinkingDurationMs': 40000,
         'message': {'id': 'mq', 'model': 'claude-opus-5-5', 'content': [{'type': 'thinking', 'thinking': 'x'}], 'usage': usage}},
        {'type': 'assistant', 'timestamp': at(60), 'requestId': 'rq', 'message': {'id': 'mq', 'model': 'claude-opus-5-5', 'content': [{'type': 'text', 'text': 'ok'}], 'usage': usage}},
    ]) + '\n')
for window, want in (((0, 60), (0, 0, 0)), ((0, 30), (30, 20, 0)), ((5, 15), (50, 35, 5))):
    try:
        th = collect_cut(f'think-{window[0]}-{window[1]}', os.path.join(wt, 'no-decisions.jsonl'), '--exclude', f'{at(window[0])}={at(window[1])}', unit='/w/unit-think')
        got = [(round(r['s']), round(r['think']), round(r['wait'])) for r in th['timing']['requests']]
    except BaseException as e:
        got = repr(e)[:300]
    check(f'a request cut from {window[0]} to {window[1]} s keeps (length, thinking, wait) {want}', [want], got)
print(f'{checks - failed} passed, {failed} failed')
sys.exit(1 if failed else 0)
PY

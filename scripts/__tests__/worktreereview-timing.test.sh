#!/usr/bin/env bash
# The build review times a tool call from when the pane could start it.
# A pane runs the Edits of one request one after another, and a call's clock
# used to start at the end of the request, so every Edit after the first was
# charged the Edits before it as a wait before its own hooks: 1 to 1.6 s an
# Edit on two builds, where the hook pass itself took 0.3 s.
# Run: bash scripts/__tests__/worktreereview-timing.test.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
python3 - "$ROOT/skills/worktreereview/scripts" <<'PY'
import json, os, sys, tempfile
from datetime import datetime, timezone
sys.path.insert(0, sys.argv[1])
import timing

failed = passed = 0
def check(name, want, got):
    global failed, passed
    ok = want == got
    failed += not ok
    passed += ok
    print(('ok   ' if ok else 'FAIL ') + name + ('' if ok else f' (expected {want!r}, got {got!r})'))

def at(s):
    return datetime.fromtimestamp(1700000000 + s, timezone.utc).isoformat().replace('+00:00', 'Z')
def use(s, tid, name):
    return {'type': 'assistant', 'timestamp': at(s), 'requestId': 'r1',
            'message': {'id': 'm1', 'content': [{'type': 'tool_use', 'id': tid, 'name': name, 'input': {}}]}}
def hook(s, tid, event, ms):
    return {'type': 'attachment', 'timestamp': at(s),
            'attachment': {'type': 'hook_success', 'hookEvent': event, 'toolUseID': tid, 'durationMs': ms, 'command': 'x/guard.sh'}}
def result(s, tid):
    return {'type': 'user', 'timestamp': at(s), 'message': {'content': [{'type': 'tool_result', 'tool_use_id': tid, 'content': 'ok'}]}}

def ledger(rows):
    with tempfile.NamedTemporaryFile('w', suffix='.jsonl', delete=False) as f:
        f.write('\n'.join(json.dumps(r) for r in rows) + '\n')
    try:
        return {k: {p: round(v[p], 2) for p in ('pre', 'run', 'post')} for k, v in timing.session_ledger(f.name)['tools'].items()}
    finally:
        os.unlink(f.name)

# Three Edits in one request, run one after another: each waits 0.3 s on its
# hooks and runs 1 s. The pane starts the first when its block arrives (10.0),
# before the request's last block has (10.2).
serial = ledger([
    {'type': 'user', 'timestamp': at(0), 'message': {'content': 'go'}},
    use(10.0, 'e1', 'Edit'), use(10.1, 'e2', 'Edit'), use(10.2, 'e3', 'Edit'),
    hook(10.3, 'e1', 'PreToolUse', 300), result(11.3, 'e1'),
    hook(11.6, 'e2', 'PreToolUse', 300), result(12.6, 'e2'),
    hook(12.9, 'e3', 'PreToolUse', 300), result(13.9, 'e3'),
])
check('the first Edit starts when its own block arrives, not when the request ends', 0.3, serial['e1']['pre'])
check('the second Edit is not charged the first one as a wait', 0.3, serial['e2']['pre'])
check('nor the third the two before it', 0.3, serial['e3']['pre'])
check('and each Edit keeps its own run time', [1.0, 1.0, 1.0], [serial[k]['run'] for k in ('e1', 'e2', 'e3')])

# Two Reads the pane runs together: the second starts before the first ends,
# so the first one's end is not where the second one's clock starts.
together = ledger([
    {'type': 'user', 'timestamp': at(0), 'message': {'content': 'go'}},
    use(10.0, 'r1', 'Read'), use(10.0, 'r2', 'Read'),
    hook(10.1, 'r1', 'PreToolUse', 100), hook(10.1, 'r2', 'PreToolUse', 100),
    result(10.6, 'r1'), result(10.7, 'r2'),
])
check('a call that ran beside the one before it is timed from the request', (0.1, 0.6), (together['r2']['pre'], together['r2']['run']))

# A call with no hook row gives no sign that it waited: two Reads that ran side
# by side look the same in the log, and taking the first one's time off the
# second would under-count it. Its whole time stays its own.
bare = ledger([
    {'type': 'user', 'timestamp': at(0), 'message': {'content': 'go'}},
    use(10.0, 'a', 'Read'), use(10.0, 'b', 'Read'),
    result(11.0, 'a'), result(12.0, 'b'),
])
check('with no hook row, a call is timed from its own arrival, never from the end of the call before it', (0, 2.0), (bare['b']['pre'], bare['b']['run']))

# Two Reads the pane may have run together, where the second one's first logged hook
# starts after the first Read ended. A hook row that comes late does not show
# the second Read waited: the pane runs Reads side by side, so its two seconds stay its own.
late = ledger([
    {'type': 'user', 'timestamp': at(0), 'message': {'content': 'go'}},
    use(10.0, 'a', 'Read'), use(10.0, 'b', 'Read'),
    result(11.0, 'a'),
    hook(11.4, 'b', 'PreToolUse', 0), result(12.0, 'b'),
])
check('a Read whose first hook row follows the end of the Read before it is still timed from its own arrival', 2.0, round(sum(late['b'].values()), 2))

# Only two look tools are left whole. Shell calls mostly run in turn (64 of 72 pairs measured on
# nine real logs, the later one's hooks 0.06 s behind the earlier one's end), so the second
# command is still not charged the first as a wait before its hooks.
shells = ledger([
    {'type': 'user', 'timestamp': at(0), 'message': {'content': 'go'}},
    use(10.0, 's1', 'Bash'), use(10.0, 's2', 'Bash'), use(10.0, 'g', 'Grep'),
    hook(10.2, 's1', 'PreToolUse', 200), result(11.0, 's1'),
    hook(11.2, 's2', 'PreToolUse', 200), result(12.0, 's2'),
    hook(12.1, 'g', 'PreToolUse', 100), result(12.5, 'g'),
])
check('a shell call behind a shell call is not charged it as a wait', 1.0, round(sum(shells['s2'].values()), 2))
check('nor a look behind a shell call', 0.5, round(sum(shells['g'].values()), 2))

# The pane never runs an edit beside another call (0 of 541 pairs measured), so a Read behind
# an Edit waited for it, and a Write behind a Read too.
mixed = ledger([
    {'type': 'user', 'timestamp': at(0), 'message': {'content': 'go'}},
    use(10.0, 'e', 'Edit'), use(10.0, 'r', 'Read'), use(10.0, 'w', 'Write'),
    hook(10.3, 'e', 'PreToolUse', 300), result(11.0, 'e'),
    hook(11.1, 'r', 'PreToolUse', 100), result(11.5, 'r'),
    hook(11.6, 'w', 'PreToolUse', 100), result(12.0, 'w'),
])
check('a Read behind an Edit is not charged the Edit as a wait', 0.5, round(sum(mixed['r'].values()), 2))
check('nor a Write behind a Read the Read', 0.5, round(sum(mixed['w'].values()), 2))

print(f'{passed} passed, {failed} failed')
sys.exit(1 if failed else 0)
PY

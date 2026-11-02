#!/usr/bin/env bash
# Drift guard (the owner's guard list, G9): a hook that times out or crashes
# lets the call through, so no hook carries `"onFailure": "block"`. A slow hook
# under load must not stop a call it would have passed. The refusal detector
# still counts the PreToolUse hooks that can refuse, so the guard is not vacuous.
# Run: bash hooks/__tests__/hook-on-failure.guard.test.sh
set -u
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1"; }

# settings-file -> "refusing N blocked M" and one line per problem; exit 1 on any problem
check_settings() {
  python3 - "$1" "$ROOT" <<'PY'
import json, os, re, sys
settings, root = sys.argv[1:]
IGNORED = {"Stop", "SubagentStop", "TaskCompleted", "TeammateIdle"}
MIN_TIMEOUT = 30
REFUSES = re.compile(r'\bexit 2\b|permissionDecision[^\n]*deny')
problems, refusing, blocked = [], 0, 0
for event, groups in json.load(open(settings)).get("hooks", {}).items():
    for group in groups:
        for hook in group.get("hooks", []):
            words = hook.get("command", "").split()
            # Every hook is started through the launcher: the hook is the word after it.
            words = [w for w in words if not w.endswith('/hooks/lib/run-hook.sh"')]
            path = (words[0] if words else "").strip(chr(34)).replace("${CLAUDE_PLUGIN_ROOT}", root)
            name = f"{event} {group.get('matcher', '*')} {os.path.basename(path)}"
            block = hook.get("onFailure") == "block"
            blocked += block
            if "onFailure" in hook and event in IGNORED:
                problems.append(f"{name}: onFailure is ignored on {event}; remove it")
            if block and hook.get("timeout", 0) < MIN_TIMEOUT:
                problems.append(f"{name}: onFailure block with timeout {hook.get('timeout')} < {MIN_TIMEOUT} s fails closed under load")
            if event != "PreToolUse" or not os.path.isfile(path):
                continue
            # Comments describe refusals without making them.
            code = "\n".join(re.sub(r'\s#\s.*$', '', l) for l in open(path, errors="replace") if not l.lstrip().startswith("#"))
            if not REFUSES.search(code):
                continue
            refusing += 1
            if block:
                problems.append(f"{name}: can refuse and fails closed; remove \"onFailure\": \"block\" so a timed-out hook lets the call through")
print(f"refusing {refusing} blocked {blocked}")
print("\n".join(problems))
sys.exit(1 if problems else 0)
PY
}

# mutate <jq filter> -> a fixture settings path
mutate() { jq "$1" "$ROOT/hooks/hooks.json" > "$T/s.json"; echo "$T/s.json"; }

OUT=$(check_settings "$ROOT/hooks/hooks.json"); rc=$?
[ "$rc" = 0 ] && ok "the real settings pass" || bad "the real settings: $OUT"
N=$(echo "$OUT" | sed -n 's/^refusing \([0-9]*\) .*/\1/p')
[ "${N:-0}" -ge 15 ] && ok "the refusal detector is not vacuous ($N refusing hooks)" || bad "only ${N:-0} refusing hooks found"
# The shipped file itself: a refusing hook that fails closed stops every call while it times out under load.
echo "$OUT" | grep -q 'can refuse and fails closed' && bad "no refusing hook fails closed" || ok "no refusing hook fails closed"

GUARD='(.hooks.PreToolUse[].hooks[] | select(.command | test("bash-guardrails")))'
OUT=$(check_settings "$(mutate "$GUARD += {onFailure:\"block\", timeout:30}")") \
  && bad "a refusing hook given block is caught: it passed" \
  || { echo "$OUT" | grep -q 'bash-guardrails.sh: can refuse and fails closed' && ok "a refusing hook given block is caught" || bad "wrong failure: $OUT"; }
OUT=$(check_settings "$(mutate "$GUARD += {onFailure:\"block\", timeout:5}")") \
  && bad "a block hook with a 5 s timeout passed" \
  || { echo "$OUT" | grep -q 'timeout 5' && ok "a block hook with a 5 s timeout fails" || bad "wrong failure: $OUT"; }
OUT=$(check_settings "$(mutate '.hooks.Stop[0].hooks[0] += {onFailure:"block", timeout:30}')") \
  && bad "onFailure on a Stop hook passed" \
  || { echo "$OUT" | grep -q 'ignored on Stop' && ok "onFailure on a Stop hook fails" || bad "wrong failure: $OUT"; }

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

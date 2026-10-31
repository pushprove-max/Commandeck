#!/usr/bin/env bash
# The fire log's block rows carry WHICH rule refused (HOOK_FIRE_REASON), and
# scripts/hook-fire-log-summary.sh counts them per hook, so a guard that blocks
# most calls can be told apart by rule. Also: a hook run behind run-hook.sh
# reads as registered.
set -u
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi
}

LOG=$T/fire.jsonl
# A hook that arms the log, sets SET_REASON when given, then blocks (exit 2) or advises.
printf '%s\n' '#!/usr/bin/env bash' 'INPUT=$(cat)' \
  '. "$ROOT/hooks/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"' \
  'if [ -n "${SET_REASON+x}" ]; then HOOK_FIRE_REASON=$SET_REASON; fi' \
  'if [ "${MODE:-block}" = advise ]; then HOOK_FIRE_ADVISE=1; exit 0; fi' 'exit 2' > "$T/fixture-hook.sh"
fire() { # VAR=value...: one hook run, one row in $LOG
  : > "$LOG"
  env COMMANDECK_HOOK_FIRE_LOG="$LOG" ROOT="$ROOT" "$@" bash "$T/fixture-hook.sh" <<<'{"hook_event_name":"PreToolUse","tool_name":"Bash"}' >/dev/null 2>&1
}
reason() { jq -r 'if has("reason") then .reason else "none" end' "$LOG"; }

# Catches: the block arm stops copying HOOK_FIRE_REASON into the row, so the
# summary cannot say which rule refused.
fire SET_REASON=search-first
check "a block row keeps its reason" "block|search-first" "$(jq -r .decision "$LOG")|$(reason)"

# Catches: the shape check is dropped or loosened, so a quote, newline, prose,
# capitals or an over-long string reaches the log (or a non-block row carries
# a reason), or the arm no longer clears a reason left over from the environment.
miss=''
for bad in 'Search First' 'a"b' $'ok\nbad' '' "$(printf 'a%.0s' {1..41})"; do
  fire SET_REASON="$bad"
  [ "$(reason)" = none ] || miss+=" [${bad:0:12}]=$(reason)"
done
fire SET_REASON=search-first MODE=advise
[ "$(reason)" = none ] || miss+=" advise=$(reason)"
fire HOOK_FIRE_REASON=stale-reason
[ "$(reason)" = none ] || miss+=" stale=$(reason)"
fire SET_REASON=$(printf 'a%.0s' {1..40})
miss+=" len=$(jq -r '.reason | length' "$LOG")"
check "a bad reason is dropped" " len=40" "$miss"

# Catches: a refusal added to a hook without HOOK_FIRE_REASON, so its block rows
# have no reason. Every `exit 2` and `HOOK_FIRE_BLOCK=1` line of hooks/*.sh has the
# assignment earlier on its own line or within the two lines before it.
missing=''
for f in "$ROOT"/hooks/*.sh; do
  mapfile -t src < "$f"
  for i in "${!src[@]}"; do
    line=${src[i]}
    [[ $line =~ ^[[:space:]]*# ]] && continue
    [[ $line == *'exit 2'* || $line == *'HOOK_FIRE_BLOCK=1'* ]] || continue
    before=${line%%exit 2*} other=${line%%HOOK_FIRE_BLOCK=1*}
    (( ${#other} < ${#before} )) && before=$other
    window=$before
    for back in 1 2; do (( i - back >= 0 )) && window+=$'\n'${src[i - back]}; done
    [[ $window =~ HOOK_FIRE_REASON=[a-z0-9\$] ]] || missing+=" ${f##*/}:$((i + 1))"
  done
done
check "a hook that refuses sets a reason" "" "$missing"

# Catches: the summary drops the reasons, counts a row twice, or counts a reason
# on a row that is not a block.
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
row() { printf '{"timestamp":"%s","hook":"%s","event":"Stop","tool":"","decision":"%s","session_id":"","agent":"claude","ms_body":1%s}\n' "$NOW" "$1" "$2" "$3"; }
{ row a.sh block ',"reason":"x-rule"'; row a.sh block ',"reason":"x-rule"'; row a.sh block ',"reason":"y-rule"'
  row a.sh block ''; row a.sh advise ',"reason":"x-rule"'; row a.sh block ',"reason":"Bad Shape"'; } > "$T/summary.jsonl"
out=$(COMMANDECK_HOOK_FIRE_LOG=$T/summary.jsonl bash "$ROOT/scripts/hook-fire-log-summary.sh" 7)
check "the summary counts reasons" '{"x-rule":2,"y-rule":1}|{}' "$(jq -S -c '.hooks[] | select(.hook == "a.sh") | .reasons' <<<"$out")|$(jq -S -c '.hooks[] | select(.hook == "pane-budget-gate.sh") | .reasons' <<<"$out")"

# Catches: the registry reads only the first word of a command, so every hook
# started through run-hook.sh reads unregistered.
mkdir -p "$T/tree/scripts" "$T/tree/hooks/lib"
cp "$ROOT/scripts/hook-fire-log-summary.sh" "$T/tree/scripts/"
cp "$ROOT/hooks/lib/project.sh" "$T/tree/hooks/lib/"
printf '%s' '{"hooks":{"Stop":[{"hooks":[{"command":"\"${CLAUDE_PLUGIN_ROOT}/hooks/lib/run-hook.sh\" \"${CLAUDE_PLUGIN_ROOT}/hooks/wrapped.sh\""},{"command":"\"${CLAUDE_PLUGIN_ROOT}/hooks/plain.sh\" --x"}]}]}}' > "$T/tree/hooks/hooks.json"
{ row wrapped.sh allow ''; row plain.sh allow ''; row gone.sh allow ''; } > "$T/reg.jsonl"
out=$(COMMANDECK_HOOK_FIRE_LOG=$T/reg.jsonl bash "$T/tree/scripts/hook-fire-log-summary.sh" 7)
got="$(jq -r '.hooks[] | select(.hook == "wrapped.sh") | .registered' <<<"$out")|$(jq -r '.hooks[] | select(.hook == "plain.sh") | .registered' <<<"$out")|$(jq -r '.hooks[] | select(.hook == "run-hook.sh") | .hook' <<<"$out")|$(jq -r '.hooks[] | select(.hook == "gone.sh") | .registered' <<<"$out")"
out=$(COMMANDECK_HOOK_FIRE_LOG=$T/reg.jsonl bash "$ROOT/scripts/hook-fire-log-summary.sh" 7)
got+="|$(jq -r '.hooks[] | select(.hook == "pane-budget-gate.sh") | .registered' <<<"$out")"
check "a hook behind run-hook.sh reads registered" "true|true||false|true" "$got"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

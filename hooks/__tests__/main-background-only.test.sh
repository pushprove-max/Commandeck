#!/usr/bin/env bash
# Self-test for main-background-only.sh: in main's session on the strict tier, a slow or unknown foreground command
# is rewritten to run in the background; a quick read passes, and anything run with run_in_background passes.
# Every case runs from a scratch main checkout with an orca-ide stub first on PATH that names the case's pane.
# Run: bash hooks/__tests__/main-background-only.test.sh
set -u
H="$(cd "$(dirname "$0")/.." && pwd)/main-background-only.sh"
G="${H%/*}/bash-guardrails.sh"
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi; }

ROOT=$(mktemp -d); WS=$(mktemp -d); HIDE=$(mktemp -d); STUB=$(mktemp -d); HM=$(mktemp -d)
trap 'git -C "$ROOT" worktree remove --force "$ROOT-wt" 2>/dev/null; rm -rf "$ROOT" "$ROOT-wt" "$WS" "$HIDE" "$STUB" "$HM"' EXIT
git -C "$ROOT" init -q; git -C "$ROOT" -c user.name=t -c user.email=t@t.t commit -q --allow-empty -m base
printf '{}\n' > "$ROOT/package.json"
git -C "$ROOT" worktree add -q --detach "$ROOT-wt"
# Orca stub: run-list names term_main as the coordinator of run-t; no run-list file makes it fail.
cat > "$STUB/orca-ide" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "orchestration run-list") f="${0%/*}/run-list"; [ -f "$f" ] && cat "$f" || exit 1 ;;
  *) echo '{"ok":true}' ;;
esac
EOF
chmod +x "$STUB/orca-ide"
printf '{"result":{"runs":[{"id":"run-t","coordinator_handle":"term_main"}]}}\n' > "$STUB/run-list"

# hook_out <hook> <command> <dir> <handle> [extra tool_input json] -> hook stdout, "rc=<n>" appended when not 0
hook_out() {
  local out rc x=${5:-'{}'}
  out=$(cd "$3" && jq -n --arg c "$2" --argjson x "$x" --arg d "$3" '{tool_input:({command:$c}+$x),cwd:$d}' \
    | env -u GIT_DIR -u GIT_WORK_TREE ORCA_TERMINAL_HANDLE="$4" COMMANDECK_RUN=run-t COMMANDECK_HOOK_TIER="${TIER:-strict}" \
      COMMANDECK_REVIEWER=0 COMMANDECK_WORKSPACES="$WS" HOME="$HM" PATH="$STUB:$PATH" bash "$1" 2>/dev/null); rc=$?
  [ "$rc" = 0 ] && echo "$out" || echo "${out}rc=$rc"
}
rewrote() { hook_out "$H" "$1" "${DIR:-$ROOT}" "${HANDLE-term_main}" "${2:-}"; }
bg() { [ "$(jq -r '.hookSpecificOutput.updatedInput.run_in_background' <<<"$1" 2>/dev/null)" = true ] && echo yes || echo no; }

check "quick reads chained by pipes and && pass" "" "$(rewrote 'git status && rg -n foo src | head -5')"
check "a 2>&1 redirection is not read as a background & and a command named 1" "" "$(rewrote 'cat x 2>&1 | tail -3')"
check "a slow command named inside quotes is data, not a command" "" "$(rewrote 'echo "sleep 300; npm test"')"
# Catches: a kept quick script dropped from the list, so main's quick call is backgrounded; dropping any name fails.
QS=""
for s in decision.sh read-verdict.sh long-job.sh checkpoint-context.py orca-wait.sh board.sh answer-worker.sh state-snapshot.sh peek.sh; do
  QS+=$(rewrote "bash scripts/$s a b")
done
check "a measured-quick script passes" "" "$QS"
check "seat.sh status is quick" "" "$(rewrote 'bash scripts/seat.sh status plan-judge u')"
check "a name at the end of a list line still matches" "" "$(rewrote 'bash scripts/board.sh; true')"
check "a loop of quick reads passes" "" "$(rewrote 'for f in a b; do wc -l "$f"; done')"
# Catches: a script dropped from the list stays foreground-blocked: send-to-pane.sh is not a plugin script.
check "send-to-pane.sh is not on the quick list" yes "$(bg "$(rewrote 'bash scripts/send-to-pane.sh a b')")"
# Catches: the inbox rewrite no-poll-loops.sh owns being taken over.
check "a bare inbox check is left alone" "" "$(rewrote 'orca-ide orchestration check')"
check "anything passes with run_in_background" "" "$(rewrote 'sleep 60; npm test' '{"run_in_background":true}')"
# Catches: `env -u` or `env -C` given last with no value: `shift 2` failed and shifted nothing, so the classifier
# looped until the hook timeout. Each must end at once (rc 0, killed after 5 s gives 124) and pass untouched.
ENV_RC=""
for c in 'env -u' 'env -C'; do
  out=$(cd "$ROOT" && jq -n --arg c "$c" --arg d "$ROOT" '{tool_input:{command:$c},cwd:$d}' \
    | env -u GIT_DIR -u GIT_WORK_TREE ORCA_TERMINAL_HANDLE=term_main COMMANDECK_RUN=run-t COMMANDECK_HOOK_TIER=strict \
      COMMANDECK_REVIEWER=0 COMMANDECK_WORKSPACES="$WS" HOME="$HM" PATH="$STUB:$PATH" timeout 5 bash "$H" 2>/dev/null; echo "rc=$?")
  ENV_RC+="${out##*rc=} $(grep -c updatedInput <<<"$out");"
done
check "an env option with no value ends" "0 0;0 0;" "$ENV_RC"

rw_check() { # <label> <command>
  local out; out=$(rewrote "$2")
  check "$1" "yes yes" "$(bg "$out") $([ "$(jq -r '.hookSpecificOutput.updatedInput.command' <<<"$out")" = "$2" ] && echo yes || echo no)"
}
rw_check "slow foreground command rewritten to background: sleep" 'sleep 60; cat x'
rw_check "slow foreground command rewritten to background: unknown binary (perl)" "perl -e 'select(undef,undef,undef,90)'"
rw_check "slow foreground command rewritten to background: timeout wrapper" 'timeout 90 codex exec x'
rw_check "slow foreground command rewritten to background: directory-size scan" 'du -sh node_modules'
rw_check "slow foreground command rewritten to background: merge precheck" 'bash scripts/merge-unit-local.sh --precheck u 0123abc'
rw_check "slow foreground command rewritten to background: orca-ide wait" 'orca-ide terminal wait --terminal t'
rw_check "slow foreground command rewritten to background: unknown tool after a quick one" 'git log -1; some-new-tool --flag'

out=$(rewrote 'sleep 40' '{"description":"d","timeout":9000}')
check "rewrite keeps command and carries no permissionDecision" "yes" \
  "$([ "$(jq -c '.hookSpecificOutput.updatedInput' <<<"$out")" = '{"command":"sleep 40","description":"d","timeout":9000,"run_in_background":true}' ] \
    && [ "$(jq -r '.hookSpecificOutput | has("permissionDecision")' <<<"$out")" = false ] \
    && [ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$out")" = PreToolUse ] && echo yes || echo "no ($out)")"

# Catches: a worker's linked worktree, a worker pane, an unknown coordinator or a default-tier install rewritten.
check "a linked session is never rewritten" "" "$(DIR=$ROOT-wt rewrote 'sleep 60')"
check "a worker pane is not main" "" "$(HANDLE=term_worker rewrote 'sleep 60')"
mv "$STUB/run-list" "$STUB/run-list.off"
check "an unknown coordinator is not main" "" "$(rewrote 'sleep 60')"
mv "$STUB/run-list.off" "$STUB/run-list"
check "a main with no Orca is main" yes "$(bg "$(HANDLE= rewrote 'sleep 60')")"
check "the default tier is never rewritten" "" "$(TIER=default rewrote 'sleep 60')"

# Both hooks on one call: exactly one updatedInput, from the owner. Orca main pane, strict tier.
both_check() { # <label> <command> <owner: G|H> <text the updatedInput command must hold>
  local n=0 owner="" first="" out h
  for h in "$H" "$G"; do
    out=$(hook_out "$h" "$2" "$ROOT" term_main)
    if [ "$h" = "$H" ] && [ "$3" = G ] && [ -n "$out" ]; then echo "FAIL $1: main-background-only must stay silent (out: $out)"; FAIL=$((FAIL+1)); return; fi
    if jq -e '.hookSpecificOutput.updatedInput' >/dev/null 2>&1 <<<"$out"; then n=$((n+1)); owner=$h; first=$(jq -r '.hookSpecificOutput.updatedInput.command' <<<"$out"); fi
  done
  if [ "$n" = 1 ] && [ "$owner" = "$([ "$3" = G ] && echo "$G" || echo "$H")" ] && [[ $first == *"$4"* ]]; then PASS=$((PASS+1)); echo "ok   $1"
  else FAIL=$((FAIL+1)); echo "FAIL $1 ($n rewrites, owner: $owner, first: $first)"; fi
}
L='one rewrite per call'
both_check "$L: npm test (bash-guardrails)" 'npm test' G 'long-job.sh'
both_check "$L: gh run watch (bash-guardrails)" 'gh run watch 123' G 'wake-on-exit.sh'
both_check "$L: seat.sh run (main-background-only)" 'bash scripts/seat.sh run sol-reviewer plan brief.md' H 'seat.sh run'
both_check "$L: merge-unit-local.sh (main-background-only)" 'bash scripts/merge-unit-local.sh u 0123abc' H 'merge-unit-local.sh'
# bash-guardrails gives the call a note (no rewrite), then main-background-only rewrites it.
both_check "$L: bash -c npm test (the note, then main-background-only)" "bash -c 'npm test'" H "npm test"
check "$L: bash -c npm test gets bash-guardrails' note" yes \
  "$(hook_out "$G" "bash -c 'npm test'" "$ROOT" term_main | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 && echo yes || echo no)"
# Without bash-guardrails.sh the call cannot be vetted: a note, no rewrite, no block.
mkdir "$HIDE/hooks"; cp -R "${H%/*}/lib" "$HIDE/hooks/lib"; cp "$H" "$HIDE/hooks/"
out=$(hook_out "$HIDE/hooks/main-background-only.sh" 'sleep 40' "$ROOT" term_main)
check "$L: sleep 40 with bash-guardrails hidden gets a note, no rewrite" "no yes" \
  "$(bg "$out") $(jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 <<<"$out" && echo yes || echo no)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

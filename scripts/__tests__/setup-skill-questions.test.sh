#!/usr/bin/env bash
# setup-skill-questions.test.sh -- /commandeck:setup is the first thing a new
# user sees. The question tool takes only questions with two to four fixed
# options, a header of 12 characters or fewer, and at most four questions per
# call; a call outside that shape is refused, and the skill once read a refusal
# as "none". What this pins: every picker question the skill sends fits the
# tool's shape, the skill says a refused call is not an answer, and every
# off/none/larger choice names the flag that undoes a saved setting (a flag
# left out keeps the earlier answer, so the owner's "off" would be lost).
# Also: setup once sent a "corrected" spelling of a name the owner typed, so the
# rule that free text goes exactly as typed must be there; installing a missing
# tool is one fixed question, and only "install" sends the flag; no text tells
# the owner to edit a shell start file; and the first command is a probe that
# shows a host project's own guard before any question is asked.
# Form it reads: a line `Call ...` opens one tool call; each question in it is
# one line `Ask "<header>": <option> | <option> [| ...] [-- <note>]`.
set -uo pipefail
SKILL=${SKILL:-$(cd "$(dirname "$0")/../.." && pwd)/skills/setup/SKILL.md}
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

# Body: the skill without its front matter (which names the tool in allowed-tools).
BODY=$(awk 'n>=2{print} /^---$/{n++}' "$SKILL")
ASKS=$(printf '%s\n' "$BODY" | grep -c '^ *Ask "')
check "the skill sends at least one picker question" 1 "$([ "$ASKS" -ge 1 ] && echo 1 || echo 0)"

# One row per question: call number, header, option count.
ROWS=$(printf '%s\n' "$BODY" | awk '
  /^ *Call/ { call++; next }
  /^ *Ask "/ {
    line=$0; sub(/^ *Ask "/, "", line)
    h=line; sub(/".*/, "", h)
    o=line; sub(/^[^"]*": */, "", o); sub(/ -- .*/, "", o)
    print call+0 "\t" length(h) "\t" split(o, a, / \| /)
  }')
check "no question sits outside a call" 0 "$(printf '%s\n' "$ROWS" | awk -F'\t' '$1==0' | grep -c .)"
check "no header is over 12 characters" 0 "$(printf '%s\n' "$ROWS" | awk -F'\t' '$2>12' | grep -c .)"
check "every question has two to four options" 0 "$(printf '%s\n' "$ROWS" | awk -F'\t' '$3<2 || $3>4' | grep -c .)"
check "no call carries more than four questions" 0 "$(printf '%s\n' "$ROWS" | awk -F'\t' '{n[$1]++} END{for(c in n) if(n[c]>4) print c}' | grep -c .)"
# A question written in another form would escape the checks above: the tool's name may appear only on a Call line or in the rule.
check "the tool is named only on a Call line or in the rule" 0 \
  "$(printf '%s\n' "$BODY" | grep 'AskUserQuestion' | grep -vc -e '^ *Call' -e '^ *Rule:')"
check "the skill says a refused call is not an answer" 1 \
  "$(printf '%s\n' "$BODY" | grep -ic 'refused or failed question call is not an answer')"
check "and says to ask the same thing again in plain text" 1 \
  "$(printf '%s\n' "$BODY" | grep -i 'refused or failed question call is not an answer' | grep -ic 'again in plain text')"
check "the old no-second-ask wording is gone" 0 "$(printf '%s\n' "$BODY" | grep -c 'Do not ask anything a second time')"
check "free text the owner types is passed exactly as typed, by rule" 1 \
  "$(printf '%s\n' "$BODY" | grep '^Rule: free text the owner types' | grep 'exactly as typed' | grep -c 'never corrected, completed or reformatted')"
check "and the original is sent unless the owner changes it" 1 "$(printf '%s\n' "$BODY" | grep '^Rule: free text' | grep -c 'the original is sent unless the owner changes it')"
check "installing what is missing is one fixed question" 1 "$(printf '%s\n' "$BODY" | grep -c '^ *Ask "Install": install | stop$')"
check "only the answer install sends the flag, and a refused call never does" 1 \
  "$(printf '%s\n' "$BODY" | tr '\n' ' ' | tr -s ' ' | grep -c 'Only the answer "install" sends the flag; a refused call, or any other answer, never does')"
check "what only the owner can do is never a question" 1 "$(printf '%s\n' "$BODY" | tr '\n' ' ' | tr -s ' ' | grep -c '"yours to do" lines are the owner.s: plain text, never a question')"
check "the probe comes before the first question" 1 \
  "$(printf '%s\n' "$BODY" | awk '/command -v orca-ide/ { p = NR } /^ *Call/ && !c { c = NR } END { print (p && p < c) ? 1 : 0 }')"
check "and the skill never works round a project's own guard" 1 "$(printf '%s\n' "$BODY" | tr '\n' ' ' | tr -s ' ' | grep -c "Never edit, switch off or work round the project's own guard")"
# Homebrew's folders are found by the scripts themselves; the owner's shell start file is never the remedy.
HERE=$(cd "$(dirname "$0")/../.." && pwd)
check "no text tells the owner to edit a shell start file or put a folder first on PATH" 0 \
  "$(cat "$SKILL" "$HERE/README.md" "$HERE/scripts/paths.sh" "$HERE/scripts/requirements.sh" "$HERE/scripts/setup.sh" "$HERE/scripts/doctor.sh" "$HERE/hooks/lib/run-hook.sh" | grep -ciE 'first on .?PATH|zshrc|zprofile|bash_profile|bashrc')"

# Each undoing flag is in the skill, and sent over a saved config it clears the saved answer.
for f in "--no-strict" "--name '' --persona ''" "--test-command ''" "--hosts ''" "--no-standard-context" "--builder-advisor none" "--no-codex-fast"; do
  check "the skill names $f" 1 "$([ "$(printf '%s\n' "$BODY" | grep -cF -e "$f")" -ge 1 ] && echo 1 || echo 0)"
done
P=$PASS F=$FAIL
. "$(dirname "$0")/install-fixture.sh"
PASS=$P FAIL=$F
CFG=$PROJ/.claude/commandeck.json
run "$PROJ" setup.sh --profile claude-openai --strict --name Ada --persona "dry" --test-command true --standard-context \
  --hosts box.local --builder-model sonnet --builder-advisor opus >"$T/out" 2>&1; check "the first setup succeeds" 0 $?
run "$PROJ" setup.sh --profile claude-openai --no-strict --name '' --persona '' --test-command '' --no-standard-context \
  --hosts '' --builder-model '' --builder-advisor '' >"$T/out" 2>&1; check "a rerun with every choice off succeeds" 0 $?
check "the rerun clears every saved answer" '[false,false,null,{},null]' \
  "$(jq -c '[.strictHooks, .standardContext, .testCommand, .chiefOfStaff, .builder]' "$CFG")"
check "and the dashboard host" '""' "$(jq -c '.dashboard.hosts' "$HOME/.commandeck/install/_machine.json")"
run "$PROJ" setup.sh --profile claude-openai --builder-model sonnet --builder-advisor opus >"$T/out" 2>&1
run "$PROJ" setup.sh --profile claude-openai --builder-advisor none >"$T/out" 2>&1; check "advisor none is accepted over a saved advisor" 0 $?

# --- Codex fast mode changes what a run costs: off unless the owner said yes ---
# The fixture's Codex home is on the fast tier already; `slow` takes that line out and `fast` puts it back.
check "the skill asks it as one fixed question, off first" 1 "$(printf '%s\n' "$BODY" | grep -c '^ *Ask "Codex fast": off | on$')"
check "and says in one line what it changes" 1 "$(printf '%s\n' "$BODY" | grep -c '^ *- \*\*Codex fast\.\*\*.*cost')"
TOML=$HOME/.codex/config.toml
slow() { grep -v '^service_tier' "$TOML" > "$T/toml" && cp "$T/toml" "$TOML"; }
fast() { slow; { echo 'service_tier = "fast"'; cat "$T/toml"; } > "$TOML"; }
fastmode() { jq -c '.codexFast' "$CFG"; }
pre() { run "$PROJ" builder-codex-pass.sh --preflight >/dev/null 2>"$T/err"; echo $?; }
check "a set-up that was never asked saves fast mode off" false "$(fastmode)"
jq 'del(.codexFast)' "$CFG" > "$T/cfg" && cp "$T/cfg" "$CFG"; slow
check "an old set-up with no saved answer starts the review pass without the fast tier in the Codex config" 0 "$(pre)"
run "$PROJ" setup.sh --profile claude-openai >"$T/out" 2>&1
check "and a rerun with no answer keeps it off" false "$(fastmode)"
run "$PROJ" setup.sh --profile claude-openai --codex-fast >"$T/out" 2>&1
check "a yes on a Codex home without the fast tier is refused" 1 $?
check "the refusal names the line the Codex config needs" 1 "$(grep -c 'service_tier = "fast"' "$T/out")"
check "and saved nothing" false "$(fastmode)"
fast
run "$PROJ" setup.sh --profile claude-openai --codex-fast >"$T/out" 2>&1; check "a yes on a fast Codex home succeeds" 0 $?
check "fast mode is on only after that yes" true "$(fastmode)"
run "$PROJ" setup.sh --profile claude-openai >"$T/out" 2>&1
check "a rerun with no answer keeps the yes" true "$(fastmode)"
slow
check "with the yes saved, the review pass refuses a Codex home without the fast tier" 1 "$([ "$(pre)" != 0 ] && grep -c service_tier "$T/err")"
run "$PROJ" setup.sh --profile claude-openai --no-codex-fast >"$T/out" 2>&1; check "the answer off is accepted over a saved yes" 0 $?
check "and saved" false "$(fastmode)"
check "after which the pass starts without the fast tier again" 0 "$(pre)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

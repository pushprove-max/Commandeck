#!/usr/bin/env bash
# setup-skill-questions.test.sh -- /commandeck:setup is the first thing a new
# user sees. The question tool takes only questions with two to four fixed
# options, a header of 12 characters or fewer, and at most four questions per
# call; a call outside that shape is refused, and the skill once read a refusal
# as "none". What this pins: every picker question the skill sends fits the
# tool's shape, the skill says a refused call is not an answer, and every
# off/none/larger choice names the flag that undoes a saved setting (a flag
# left out keeps the earlier answer, so the owner's "off" would be lost).
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

# Each undoing flag is in the skill, and sent over a saved config it clears the saved answer.
for f in "--no-strict" "--name '' --persona ''" "--test-command ''" "--hosts ''" "--no-standard-context" "--builder-advisor none"; do
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

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

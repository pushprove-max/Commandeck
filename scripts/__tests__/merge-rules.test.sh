#!/usr/bin/env bash
# merge-rules.test.sh -- an owner's "keep mine" decision is saved by rule id, and
# the id is a hash of the rule's wording. What this pins: a release that rewords
# a rule still leaves out every rule the owner kept their own wording for, and a
# rule made from several is left out only when the owner keeps all of them (a
# duplicate rule beats a lost one).
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
MS() { python3 "$REAL/scripts/merge-rules.py" "$REAL/templates/main-session.md" "$@"; }
drops() { for i; do printf -- '--drop %s ' "$i"; done; }

# Every rule id of 0.7.1's main-session.md (merge-rules.py --units).
V071='1a205d56 18cd2c62 1f85d44e 58d81ff4 c89a261a 28c31a4a 6d119e42 34ec1023 57eadb12 32d46d9b c99218c7 f0729b8f 8fc96d58 00709c21 f0558144
f7c75c86 8361fb71 8ade2fb3 f6e2fbb0 2848b779 48b02596 a4d1bca5 6743a4ac 5f6ba6aa a78ec6d6 911bac3f 04adb41d c539053c 55bf03c0 426b85c6'
# shellcheck disable=SC2046
# The rules kept are new since 0.7.1, so no owner has a wording of them to keep: plan before every build, its full
# text below Details a second unit, the worker-memory note below Details a third, and 0.18.0's denied
# self-modification rule a fourth, 0.20.0's NO-GO-merges-on-the-owner's-word rule a fifth, and 0.21.0's do-not list,
# status line, two-NO-GOs and picker rules four more, and 0.23.0's merge gate and no-redundant-steps rules two more.
check "an owner who kept their own wording for every 0.7.1 main rule gets only the rule added since" \
  "11 plugin rules kept:2" "$(MS $(drops $V071) --report | head -1 | cut -d, -f1):$(MS $(drops $V071) | grep -c 'Plan before every build')"
check "the relay rule an owner kept their own wording for in 0.7.1 stays out" 0 \
  "$(MS --drop 34ec1023 | grep -c 'goes to the relay pane')"
check "a rule reworded alone stays out under its 0.7.1 id" 0 \
  "$(MS --drop c99218c7 | grep -c 'Stated limits')"
check "a rule made from two 0.7.1 rules stays in when the owner kept only one" 1 \
  "$(MS --drop 18cd2c62 | grep -c 'Main plans with the owner')"
check "and goes when the owner kept both" 0 \
  "$(MS --drop 18cd2c62 --drop 8fc96d58 | grep -c 'Main plans with the owner')"
# The owner's newer, explicit answer for the reworded rule beats the one saved for the rule it was made from.
check "keep both for a reworded rule loads it, though keep mine was saved for its 0.7.1 id" 1 \
  "$(MS --drop c99218c7 --keep 8aa8b56d | grep -c 'Stated limits')"
check "keep both for a rule made from two loads it, though keep mine was saved for both" 1 \
  "$(MS --drop 18cd2c62 --drop 8fc96d58 --keep 607f18a2 | grep -c 'Main plans with the owner')"

# Main writes each planner's spec from the planning rule, so that rule is where a planner hears to name a fitting
# mattpocock-skills skill (the owner's, 2026-10-17); it stays one rule. An owner who kept their own wording of the
# planning rule before (871dfc54) does not get the reworded one too.
check "the planning rule names the skills line, inside the same rule" "1:36" \
  "$(MS | awk '/^- \*\*/ { p = /Plan before every build/ } p' | grep -c 'If the mattpocock-skills plugin'):$(MS --units | wc -l | tr -d ' ')"
check "an owner who kept their own planning rule does not get the reworded one" 0 \
  "$(MS --drop 871dfc54 | grep -c 'If the mattpocock-skills plugin')"
# AGENT_STARTUP.md's planning step was reworded in 0.18.0 (planned in the unit's own worktree): an owner's keep
# mine, saved for its 0.17.0 id, still leaves it out.
check "an owner who kept their own AGENT_STARTUP planning step does not get the 0.18.0 wording" 0 \
  "$(python3 "$REAL/scripts/merge-rules.py" "$REAL/templates/AGENT_STARTUP.md" --drop 1bc6a1b6 | grep -c 'Write a plan first')"

# A duplicate is the same text once case and spacing are set aside, nothing more (main's ruling): a path, a code
# span, a flag or a sign changes what a rule says, so a near-match keeps the plugin's rule.
A=$(awk '/^THE CLEAR LINE/{p=1} /^## Details/{exit} p' "$REAL/templates/main-session.md" | sed 's|~/.claude/checkpoints/|./.claude/checkpoints/|g')
check "an owner's rule naming ./.claude/checkpoints/ leaves in the plugin's ~/.claude/checkpoints/ rule" 0 \
  "$(MS --against <(printf '%s\n' "$A") --report | grep -c '^  already in')"
n=0
while IFS='|' read -r mine theirs want; do
  n=$((n + 1))
  check "a plugin rule against a near-match ($n) is kept once, or left out when only case and spacing differ" "$want" \
    "$(python3 "$REAL/scripts/merge-rules.py" <(printf -- '- %s\n' "$mine") --against <(printf -- '- %s\n' "$theirs") | grep -cxF -- "- $mine")"
done <<'RULES'
Save a checkpoint in ~/.claude/checkpoints/ first.|Save a checkpoint in ./.claude/checkpoints/ first.|1
Run `make test` before you push.|Run make test before you push.|1
Call setup.sh --plan first.|Call setup.sh plan first.|1
Keep the limit at -1.|Keep the limit at 1.|1
Run  MAKE before you push.|run make before   you push.|0
RULES

# Issue 209: rules found only inside setup's own block from an earlier run are named as such in the report, and are
# still not the owner's: the merged text keeps every one of them, so the next block still carries them.
TPL=$(printf -- '- Rule one for this test.\n- Rule two for this test.\n')
OWN=$(printf '<!-- commandeck:rules:begin -->\n%s\n<!-- commandeck:rules:end -->\n' "$TPL")
check "the report names rules already in setup's block from an earlier run, none as the owner's" \
  "2 plugin rules kept (2 already in setup's block from an earlier run), 0 already in your files (left out), 0 where you keep your own (left out)" \
  "$(python3 "$REAL/scripts/merge-rules.py" <(printf '%s\n' "$TPL") --against <(printf '%s' "$OWN") --report | head -1)"
check "the merged text still holds both rules from setup's earlier block" 2 \
  "$(python3 "$REAL/scripts/merge-rules.py" <(printf '%s\n' "$TPL") --against <(printf '%s' "$OWN") | grep -c 'for this test')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

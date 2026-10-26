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
# status line, two-NO-GOs and picker rules four more, and 0.23.0's merge gate and no-redundant-steps rules two more,
# and 0.44.0's rule that a reply the duplicate-agent guard blocks is never dropped and 0.45.0's archive-a-memory rule two more,
# and 0.46.0's large-read rule, the class stop split into two rules (second NO-GO, third return) and the
# hand-merge cleanup rule three more, and 0.47.0's newest-report rule one more, and 0.48.0's owner's-words scope rule one more.
check "an owner who kept their own wording for every 0.7.1 main rule gets only the rule added since" \
  "18 plugin rules kept:2" "$(MS $(drops $V071) --report | head -1 | cut -d, -f1):$(MS $(drops $V071) | grep -c 'Plan before every build')"
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
check "the planning rule names the skills line, inside the same rule" "1:43" \
  "$(MS | awk '/^- \*\*/ { p = /Plan before every build/ } p' | grep -c 'If the mattpocock-skills plugin'):$(MS --units | wc -l | tr -d ' ')"
check "an owner who kept their own planning rule does not get the reworded one" 0 \
  "$(MS --drop 871dfc54 | grep -c 'If the mattpocock-skills plugin')"
# AGENT_STARTUP.md's planning step was reworded in 0.18.0 (planned in the unit's own worktree): an owner's keep
# mine, saved for its 0.17.0 id, still leaves it out.
check "an owner who kept their own AGENT_STARTUP planning step does not get the 0.18.0 wording" 0 \
  "$(python3 "$REAL/scripts/merge-rules.py" "$REAL/templates/AGENT_STARTUP.md" --drop 1bc6a1b6 | grep -c 'ask no question')"
# Each MADE_FROM line added in 0.26.0-0.29.0 carries a keep mine forward and nothing more: the reworded rule stays
# out only for an owner who kept their own wording of the rule it came from, and --keep of its new id loads it.
# Not an exemption: the owner's own wording stays loaded from their file, and the owner ruled it so.
ids() { python3 "$REAL/scripts/merge-rules.py" - --units | cut -f1; }
for pair in bbe121f7:f45e894e 401e8893:71c7e94b 4083592b:b1471fa8 b2577b20:ae5d50a4 7c87d0bb:42145c44 e6963680:2bb3342e 399b22b8:45c2952e 45cd53bc:45c2952e b2a85a66:48b02596 4439c5bf:487d3e9e; do
  new=${pair%:*} old=${pair#*:}
  check "reworded $new: in by default, out under keep mine of $old, in again with --keep $new" "1 0 1" \
    "$(MS | ids | grep -c "^$new") $(MS --drop "$old" | ids | grep -c "^$new") $(MS --drop "$old" --keep "$new" | ids | grep -c "^$new")"
done
# Issue 325: the global rules' review-finding rule was reworded; an owner who kept their own wording of the old one stays
# out of it, through each later rewording too (0.48.0: issue 366's review threshold, 26b6b2b9 made from 13e9906d).
GR() { local id=$1; shift; python3 "$REAL/scripts/merge-rules.py" "$REAL/templates/global-rules.md" "$@" | ids | grep -c "^$id"; }
check "reworded 26b6b2b9: in by default, out under keep mine of c8e23316, in again with --keep 26b6b2b9" "1 0 1" \
  "$(GR 26b6b2b9) $(GR 26b6b2b9 --drop c8e23316) $(GR 26b6b2b9 --drop c8e23316 --keep 26b6b2b9)"
# 0.48.0 global-rules.md rewordings: the review threshold (issue 366), the reviewers' scope, the ponytail add-on removed
# (issue 365), units and duplicate agents, planning by size. 0.51.0: a plan's `file ~line`, the sibling dry run, the
# flexibility finding's severity.
for pair in 26b6b2b9:13e9906d cb6056f9:9243900d 41d1d566:e38a2639 e7926841:e6c9ac28 3b129248:516a9bd8 2424eeef:56860db4 eff13cd5:64f32653 faea5cd0:71b6b9ca a935667e:2fe4fdf9; do
  new=${pair%:*} old=${pair#*:}
  check "reworded global $new: in by default, out under keep mine of $old, in again with --keep $new" "1 0 1" \
    "$(GR "$new") $(GR "$new" --drop "$old") $(GR "$new" --drop "$old" --keep "$new")"
done

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

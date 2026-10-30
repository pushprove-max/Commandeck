#!/usr/bin/env bash
# builder-codex-pass-issue-stop.test.sh -- issue 486: when a per-issue review stops for main, and what lifts the stop. The
# stop flow runs the real pass with a stub reviewer; the walk of the records (cut rows, class stops) runs issue_step itself.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-codex-pass-setup.sh"

iunit() { # <unit>: a worktree whose main brief chooses the per-issue workflow for issues 1 and 2
  git -C "$REPO" worktree add -q "$TMP/ws/$1" -b "builder/$1" main && mkdir -p "$TMP/ws/$1/.claude/briefs"
  echo '{"env":{"COMMANDECK_BUILDER":"1"}}' > "$TMP/ws/$1/.claude/settings.local.json"
  printf 'Fix #1 and #2.\nReview workflow: per-issue #1 #2\nbash x/builder-codex-pass.sh %s 1 adversarial\n' "$1" > "$REPO/.claude/briefs/$1-builder-brief.md"
}
ipass() { # <unit> <issue> <reply>: one --issue pass; prints its exit code; output in $TMP/out and $TMP/err
  local n; n=$(($(cat "$TMP/seq" 2>/dev/null || echo 0) + 1)); echo "$n" > "$TMP/seq"
  (cd "$TMP/ws/$1" && env TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-s$n "STUB_REPLY=$3" \
    bash "$PASS_SH" --issue "$2" "$1" >"$TMP/out" 2>"$TMP/err"); echo $?
}
iack() { (cd "$TMP/ws/$1" && env TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO bash "$PASS_SH" --ack-rulings "$1" >/dev/null 2>&1); }
fix() { printf 'echo %s\n' "$2" > "$TMP/ws/$1/$2.sh"; } # <unit> <name>: a change for the next review to read
answer() { printf '%s\n' "$2" >> "$REPO/.claude/briefs/$1-main-rulings.md"; iack "$1"; } # <unit> <line>: main's answer, then the Builder reads it
NOGO=$'- [P1] a.sh:1 a bug\nVERDICT: NO-GO'
GO=$'Fine.\nVERDICT: GO'
# stopped <unit>: an adversarial NO-GO, then three regular NO-GOs, so the issue waits for main
stopped() {
  iunit "$1"
  for k in 1 2 3 4; do fix "$1" a$k; ipass "$1" 1 "- [P1] a$k.sh:1 a bug"$'\nVERDICT: NO-GO' >/dev/null; done # a file of its own each round: no class comes back
}

# Catches a third regular NO-GO that only prints: the Builder can be gone, so the pass itself must tell main.
stopped st
check "third_nogo_wakes_main: the third regular NO-GO prints the stop for round 4 and tells main through to-main.sh" "1 1" \
  "$(grep -c '^PER-ISSUE STOP: st: issue #1 stopped at round 4' "$TMP/out") $(grep -c 'PER-ISSUE STOP issue #1' "$SC/queue/main.jsonl" "$TMP/orca-calls" | awk -F: '{ s += $NF } END { print (s > 0) }')"

# Catches a fourth pass that runs while main has not answered: it would spend rounds on a fix main may want redesigned.
fix st a5
check "no_pass_until_main_answers: the next pass of a stopped issue is refused and starts no reviewer" "2:1:0" \
  "$(ipass st 1 "$GO"):$(grep -c 'No per-issue pass of this issue starts' "$TMP/err"):$(ls "$TMP"/ws/st/.claude/briefs/st-issue-1-round-5.md 2>/dev/null | wc -l | tr -d ' ')"

# Catches an answer written in the worktree's own copy of the rulings: only main's file may lift a stop.
printf 'Per-issue #1 round 4: continue\n' > "$TMP/ws/st/.claude/briefs/st-main-rulings.md"; iack st
check "worktree_answer_ignored (an answer in the worktree's rulings copy does not lift the stop)" "2" "$(ipass st 1 "$GO")"
rm "$TMP/ws/st/.claude/briefs/st-main-rulings.md"

# Catches continue taking the issue straight to done or leaving it stopped: it must give a new set of regular reviews.
answer st 'Per-issue #1 round 4: continue'
CRC=$(ipass st 1 "$GO")
check "continue_gives_new_regulars: after continue the next pass runs as a regular review and a GO ends the issue" "0 1 1" \
  "$CRC $(grep -c '^Pass: issue-review$' "$TMP/ws/st/.claude/briefs/st-issue-1-round-5.md") $(grep -c '^PER-ISSUE DONE: issue #1' "$TMP/out")"

# Catches redesign continuing the old review run: it must restart with a fresh adversarial review.
stopped rd
answer rd 'Per-issue #1 round 4: redesign'; fix rd a6
RRC=$(ipass rd 1 "$NOGO")
check "redesign_restarts_adversarial: after redesign the next pass is an adversarial review" "0 1" \
  "$RRC $(grep -c '^Pass: issue-adversarial$' "$TMP/ws/rd/.claude/briefs/rd-issue-1-round-5.md")"

# Catches a fixed tree being asked twice: a NO-GO with nothing changed since must not spend another round.
iunit un; fix un a1; ipass un 1 "$NOGO" >/dev/null
check "unchanged_tree_refused: a pass right after a NO-GO with no change is refused and writes no round file" "2:1:0" \
  "$(ipass un 1 "$GO"):$(grep -c 'nothing has changed since' "$TMP/err"):$(ls "$TMP"/ws/un/.claude/briefs/un-issue-1-round-2.md 2>/dev/null | wc -l | tr -d ' ')"

# Catches a per-issue NO-GO starting the final cycle's fix hand-off: the Builder fixes in the same session.
iunit nh; fix nh a1; ipass nh 1 "$NOGO" >/dev/null
check "nogo_writes_no_handoff: a per-issue NO-GO writes no fix hand-off and says to fix and run the issue again" "0 0 1" \
  "$(ls "$TMP"/ws/nh/.claude/briefs/nh-fix-r* 2>/dev/null | wc -l | tr -d ' ') $(grep -ci 'hand-off' "$TMP/out" "$TMP/err" | awk -F: '{ s += $NF } END { print s + 0 }') $(grep -c '^PER-ISSUE NEXT: issue #1 needs a review review' "$TMP/out")"

# The walk of the records. A row is "@ <session> <kind>:<issue> <k> <n> <round> <began> <ended> <read> <since> <said>", then findings.
eval "$(sed -n '/^issue_step() {/,/^}/p' "$PASS_SH")"
row() { printf '@ t%s %s:1 1 1 %s b e r s %s\n' "$1" "$2" "$1" "$3"; } # <round> <kind> <said>
step() { issue_step 1 "$1" "" 3; } # <rows>
# Catches a cut-off review counted as a regular NO-GO: two real regulars and a cut one must not reach the cap of 3.
CUT=$(row 1 issue-adv NO-GO; row 2 issue-rev NO-GO; printf '@ t3 cut:1 0 0 3 b b - - cut\n'; row 4 issue-rev NO-GO)
check "cut_off_review_does_not_count: a cut-off review is neither a regular review nor a GO" "review" "$(step "$CUT")"

# Catches a regular GO ending an issue while a class is under redesign: the patch would pass and the class stay open.
CLS=$(row 1 issue-adv NO-GO; echo '- [P1] src/x.ts:3 first'; row 2 issue-rev NO-GO; echo '- [P1] src/x.ts:9 again'; row 3 issue-rev GO)
check "class_stop_holds_patched_go: a class cited twice holds the issue for a design review; a later regular GO does not end it" "design src/x.ts" "$(step "$CLS")"

# Catches a class that comes back after its design was approved being sent on without main.
BACK=$(row 1 issue-adv NO-GO; echo '- [P1] src/x.ts:3 first'; row 2 issue-rev NO-GO; echo '- [P1] src/x.ts:9 again'; row 3 issue-design GO; row 4 issue-rev NO-GO; echo '- [P1] src/x.ts:12 back')
check "class_back_asks_main: a class that returns after its design review ended GO asks main" "ask 4" "$(step "$BACK")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

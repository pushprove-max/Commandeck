#!/usr/bin/env bash
# builder-codex-pass.sh: the owner's extra rounds for one unit with no edit to the tracked settings file; --check
# runs the launch's checks and nothing else; and after a NO-GO pass from the Builder's own pane the fix
# round starts in a fresh session from a hand-off file that stands alone, or main hears why it did not.
# The fixture is the one builder-codex-pass.test.sh uses.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-codex-pass-setup.sh"

# The state these cases start from: a first pass.
printf 'echo built\n' > "$W/a.sh"
pass 1 adversarial
printf 'Different fix r2: an older note.\nDifferent fix r3: the named fix broke the caller in b.sh.\nOther cases checked r3: a.sh and c.sh read the same input.\n' > "$B/$U-evidence.md"
printf '\n## Main-only (deferred)\nthe settings.json entry for the new hook: main edits that file.\n\n## Later heading\nnot deferred.\n' >> "$B/$U-evidence.md"
L=$(git -C "$W" rev-parse --absolute-git-dir)/builder-pass.lock

# Issue 271: the round file holds when the pass began and ended, read from its reviewers' session records: the
# earliest start and the latest end, so the merge can add up the time spent in review.
SESS=$(ls "$CODEX_HOME"/sessions/2026/10/14/rollout-*-thr-1-*.jsonl)
check "the round file holds the pass's start and end from session_proof, the earliest start and latest end of its reviewers" \
  "$(jq -rs '[.[] | select(.type == "session_meta") | .timestamp] | min' $SESS) $(jq -rs '[.[] | select(.payload.type? == "task_complete") | .timestamp] | max' $SESS)" \
  "$(sed -n 's/^Timing: //p' "$B/$U-r1-reports.md")"
check "and the line follows Pass:, once" "Pass: adversarial|1" \
  "$(grep -m1 '^Pass:' "$B/$U-r1-reports.md")|$(grep -c '^Timing: ' "$B/$U-r1-reports.md")"
check "and sits right after it" "Timing" "$(grep -A1 -m1 '^Pass:' "$B/$U-r1-reports.md" | tail -1 | cut -d: -f1)"

# the owner's extra rounds for one unit, with no edit to the tracked settings file.
printf 'echo six\n' > "$W/a.sh"
p6() { (cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-6 bash "$PASS_SH" "$U" 6 review >"$TMP/out" 2>"$TMP/err"); echo $?; }
(cd "$REPO" && bash "$REAL/scripts/review-cap.sh" "$U" 5 >/dev/null)
check "round 6 is over the unit's 5" "2 1" "$(p6) $(grep -c 'over the 5 rounds' "$TMP/err")"
echo 9 > "$B/$U-review-cap.md"
check "a cap the Builder writes in its own worktree is not read" 2 "$(p6)"
check "review-cap.sh refuses in a Builder worktree" 2 "$(cd "$W" && bash "$REAL/scripts/review-cap.sh" "$U" 9 >/dev/null 2>&1; echo $?)"
(cd "$REPO" && bash "$REAL/scripts/review-cap.sh" "$U" 6 >/dev/null)
check "after review-cap.sh <unit> 6 in main's checkout, round 6 runs" 0 "$(p6)"
check "and neither checkout's tracked files changed" "" \
  "$(git -C "$REPO" status --porcelain --untracked-files=no; git -C "$W" status --porcelain --untracked-files=no)"

# After a NO-GO pass the Builder's own pane takes the fix round in a fresh session (/clear, then a pointer to a
# hand-off file that stands alone): the old session carried the whole build's context into every fix call. Main's
# seat record follows the new session's log, so main-watch reads the new log and not the cleared one.
(cd "$REPO" && bash "$REAL/scripts/review-cap.sh" "$U" 10 >/dev/null)
# A launch refused for a missing evidence line cost a request and a retry. --check is
# the launch's own evidence check (the same function): it names the missing line and exits non-zero, or passes, and
# in both cases stages nothing, commits nothing, never reaches Codex and leaves no pass lock.
printf 'it()\n' > "$W/x.guard.test.ts"; : > "$TMP/probe"; HEAD7=$(git -C "$W" rev-parse HEAD)
chk() { (cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO bash "$PASS_SH" --check "$U" 7 review >"$TMP/out" 2>"$TMP/err"); echo $?; }
untouched() { [ "$(git -C "$W" rev-parse HEAD)" = "$HEAD7" ] && [ -z "$(git -C "$W" diff --cached --name-only)" ] && [ ! -e "$B/$U-r7-reports.md" ] \
  && [ ! -s "$TMP/probe" ] && [ ! -e "$L" ] && echo untouched; }
# Issue 323: red proofs are retired, so a new guard-class test with no Mutation-verified: line in the evidence passes.
check "--check with a new guard test and no mutation line passes, and stages, commits, locks and runs nothing" "0 1 untouched" \
  "$(chk) $(grep -c '^check ok: ' "$TMP/out") $(untouched)"
mkdir -p "$W/x/__tests__"; echo t > "$W/x/__tests__/y.test.sh"
printf '## 1. RULING-PROBE: keep the probe\n' > "$REPO/.claude/briefs/$U-main-rulings.md"
(cd "$W" && COMMANDECK_MAIN=$REPO bash "$PASS_SH" --ack-rulings "$U" >/dev/null 2>&1)
printf 'handle=term_frs\ntask=task_frs\nunit=%s\nrole=builder\nsession=old-sid\n' "$U" > "$SC/seat-$U-builder.txt"
PROJ=$HOME/.claude/projects/$(printf '%s' "$W" | tr -c 'A-Za-z0-9' '-')
# The cleared session's own log names the hand-off too (it read the pass's output); it is not the new one.
mkdir -p "$PROJ"; echo "$B/$U-fix-r7.md" > "$PROJ/old-sid.jsonl"; touch -t 209901010000 "$PROJ/old-sid.jsonl"
printf 'echo seven\n' > "$W/a.sh"
check "a NO-GO pass from the Builder's pane ends 0 and tells the old session to stop" "0 1" \
  "$(fpass "$W" 7 review "$NOGO") $(grep -c '^FIX ROUND 7: end your turn now' "$TMP/out")"
H7=$B/$U-fix-r7.md
check "the hand-off stands alone: brief, evidence, the findings, main's rulings inlined, the task and the touched tests (the finding shows under Findings so far and under what the pass found)" "1 1 2 1 1 1" \
  "$(grep -c "$B/$U.md\$" "$H7") $(grep -c "$B/$U-evidence.md\$" "$H7") $(grep -c 'FINDING-PROBE' "$H7") $(grep -c 'RULING-PROBE' "$H7") $(grep -c 'Orca task: task_frs' "$H7") $(grep -cF 'x/__tests__/y.test.sh' "$H7")"
# Each fix-round session read the whole brief at start, about 37K cache-write tokens a
# time. The findings say what to fix; the brief stays reachable by path for the finding that needs it.
check "the hand-off does not order the brief or the evidence file read whole at start; both stay reachable by path" "0 0 1 1" \
  "$(grep -ci 'read the brief whole' "$H7") $(grep -ci 'read the evidence file whole' "$H7") $(grep -c "Open it only when a finding needs it: $B/$U.md\$" "$H7") $(grep -c "update it before the next pass: $B/$U-evidence.md\$" "$H7")"
# Issue 286: the brief template's state-swap rule is in the hand-off too, as a fix round reads only the hand-off.
check "the fix hand-off asks for the existing cases rerun with a trusted state swapped in, and the result recorded in the evidence file" 1 \
  "$(grep -cF 'A fix that changes when a state is trusted (narrows or widens it) reruns the existing cases with the state swapped in before the next pass, and the evidence file records the result.' "$H7")"
check "the launch after a passing --check is not refused: the guard test is committed with no mutation note" "0 1" \
  "$(git -C "$W" log -1 --format=%B | grep -c 'Mutation-verified') $(git -C "$W" ls-files x.guard.test.ts | wc -l | tr -d ' ')"
helper_done 7
check "the pane is waited idle, cleared, then handed the file" "terminal wait,--text /clear,terminal wait,Your task spec is the file" \
  "$(grep -oE 'terminal wait|--text /clear|Your task spec is the file' "$TMP/frs-calls" | uniq | paste -sd, -)"
check "the pointer names the hand-off file" 1 "$(grep -cF "Your task spec is the file $H7." "$TMP/frs-calls")"
check "main's seat record now names the new session, not the cleared one" "session=new-sid" "$(grep '^session=' "$SC/seat-$U-builder.txt" | tail -1)"
rm -f "$TMP/frs-calls"; printf 'echo eight\n' > "$W/a.sh"
check "a pane that is gone before it goes idle: the pass still ends 0" 0 "$(fpass "$W" 8 review "$NOGO" FRS_IDLE=1 FRS_GONE=1)"
helper_done 8
check "and the helper types nothing and says why (the hand-off is tried twice, so the reason is logged per attempt)" "0 2" \
  "$(grep -c 'terminal send' "$TMP/frs-calls") $(grep -c 'pane term_frs is gone; nothing typed' "$SC/$U-fix-r8.log")"
rm -f "$TMP/frs-calls"; printf 'echo nine\n' > "$W/a.sh"
check "a GO pass hands nothing over" "0 0 0" \
  "$(fpass "$W" 9 review 'VERDICT: GO') $(ls "$B/$U-fix-r9.md" 2>/dev/null | wc -l | tr -d ' ') $(cat "$TMP/frs-calls" 2>/dev/null | wc -l | tr -d ' ')"
printf 'echo ten\n' > "$W/a.sh"
# Issue 355: the fix round is the Builder's pane's (the seat record's handle), whoever ran the pass.
check "a NO-GO pass from another pane hands the fix round to the Builder's pane, and tells the caller to fix nothing" "0 1 1 0" \
  "$(fpass "$W" 10 review "$NOGO" ORCA_TERMINAL_HANDLE=term_other) $(ls "$B/$U-fix-r10.md" 2>/dev/null | wc -l | tr -d ' ') $(grep -c "^FIX ROUND 10: this session is not the Builder's pane, so the Builder's pane (term_frs) takes the fix round" "$TMP/out") $(grep -c 'end your turn now' "$TMP/out")"
helper_done 10
check "and the helper types into the seat record's pane, not the caller's" "1 0" \
  "$(grep -c 'terminal send --terminal term_frs --text /clear' "$TMP/frs-calls") $(grep -c 'term_other' "$TMP/frs-calls")"
# Issue 397: the hand-off tells the Builder to hand cuts to helpers.
check "the fix-round hand-off carries the helper line" 1 \
  "$(grep -cF "$(bash -c '. "$1/scripts/paths.sh"; printf %s "${PP_HELPER_LINE//<plugin scripts>/$PP_SCRIPTS}"' _ "$REAL")" "$B/$U-fix-r10.md")"
# A hand-off the pane never took reaches main, with Orca's own answer. The send's output went to /dev/null
# and the log was the only trace, so main never heard that fix round 2 of commandeck-speedups-0-7-2 had not started.
rm -f "$TMP/frs-calls"
(cd "$W" && env PATH=$FB:$PATH COMMANDECK_MAIN=$REPO COMMANDECK_FRESH_ROUND_SETTLE_SECONDS=0 FRS_CALLS=$TMP/frs-calls FRS_PROJ=$PROJ FRS_SEND_FAILS=1 \
  timeout 30 bash "$REAL/scripts/builder-fresh-round.sh" term_frs "$H7" > "$TMP/frs.out" 2>&1); R=$?
check "a /clear Orca refuses: exit 1, Orca's answer in the log once per attempt (one retry), and main is told once" "1 2 1" \
  "$R $(grep -c 'typing /clear into term_frs failed (orca: PROBE-REFUSAL)' "$TMP/frs.out") $(cat "$TMP/frs-calls" "$SC/queue/main.jsonl" 2>/dev/null | grep -c "fresh round not started: ${H7##*/}")"

# Issue 355: a NO-GO whose hand-off is skipped (the seat record names no pane) says so and tells main (when a Builder
# seat exists), and writes no fix-r file; without a seat the reason is only printed. A hand-off that cannot be written
# leaves no file at its path and starts no helper, so no /clear is typed into a pane for a half-written brief.
(cd "$REPO" && bash "$REAL/scripts/review-cap.sh" "$U" 20 >/dev/null)
# Issue 366: the P1 of pass 10 open at the seventh pass on record would stop the loop for the owner (REVIEW STOP)
# with no hand-off. Passes 6 to 10 are aged out of the 14-day session window, so pass 11 is the second on record.
find "$CODEX_HOME/sessions" -name 'rollout-*-thr-[0-9]-*.jsonl' ! -name '*-thr-1-*' -exec touch -t 200001010000 {} +
find "$CODEX_HOME/sessions" -name 'rollout-*-thr-10-*.jsonl' -exec touch -t 200001010000 {} +
told() { cat "$SC/queue/main.jsonl" "$TMP/frs-calls" 2>/dev/null | grep -c "NO FIX HAND-OFF after pass $1"; } # <N>: messages naming it
rm -f "$TMP/frs-calls"; printf 'echo eleven\n' > "$W/a.sh"
check "a NO-GO pass with no Orca handle hands the fix round to the Builder's pane and tells main nothing" "0 1 0 1" \
  "$(fpass "$W" 11 review "$NOGO" ORCA_TERMINAL_HANDLE=) $(ls "$B/$U-fix-r11.md" 2>/dev/null | wc -l | tr -d ' ') $(told 11) $(grep -c "^FIX ROUND 11: this session is not the Builder's pane" "$TMP/out")"
helper_done 11
printf 'echo twelve\n' > "$W/a.sh"
check "a hand-off for a pane the seat record names is the same from a pane that is not the Builder's" "0 1 0" \
  "$(fpass "$W" 12 review "$NOGO" ORCA_TERMINAL_HANDLE=term_other) $(ls "$B/$U-fix-r12.md" 2>/dev/null | wc -l | tr -d ' ') $(told 12)"
helper_done 12
cp "$SC/seat-$U-builder.txt" "$SC/seat-$U-builder.keep"; grep -v '^handle=' "$SC/seat-$U-builder.keep" > "$SC/seat-$U-builder.txt"; printf 'echo thirteen\n' > "$W/a.sh"
check "a seat record with no pane is a skipped hand-off: the reason is named, main is told and no fix-r file is written" "0 1 1 0" \
  "$(fpass "$W" 13 review "$NOGO" ORCA_TERMINAL_HANDLE=term_frs) $(grep -c 'NO FIX HAND-OFF after pass 13: the seat record names no pane for the Builder' "$TMP/out") $(told 13) $(ls "$B/$U-fix-r13.md" 2>/dev/null | wc -l | tr -d ' ')"
mv "$SC/seat-$U-builder.keep" "$SC/seat-$U-builder.txt"
mv "$SC/seat-$U-builder.txt" "$SC/seat-$U-builder.hold"; printf 'echo fourteen\n' > "$W/a.sh"
check "a skipped hand-off with no Builder seat record prints the reason and tells nobody" "0 1 0" \
  "$(fpass "$W" 14 review "$NOGO" ORCA_TERMINAL_HANDLE=) $(grep -c 'NO FIX HAND-OFF after pass 14' "$TMP/out") $(told 14)"
mv "$SC/seat-$U-builder.hold" "$SC/seat-$U-builder.txt"
rm -f "$TMP/frs-calls"; printf 'echo fifteen\n' > "$W/a.sh"; mkdir -p "$B/$U-fix-r15.md"
check "a fix hand-off that cannot be written names the failure, tells main, leaves no file and starts no helper" "1 1 1 0 0 0" \
  "$(fpass "$W" 15 review "$NOGO") $(grep -c 'NO FIX HAND-OFF after pass 15: writing' "$TMP/out") $(told 15) $(grep -c '^FIX ROUND' "$TMP/out") $(ls "$B/$U-fix-r15.md.tmp" 2>/dev/null | wc -l | tr -d ' ') $(cat "$TMP/frs-calls" 2>/dev/null | grep -c -- '--text /clear')"
rmdir "$B/$U-fix-r15.md"

# Issue 382: a Builder whose pane is gone is launched again over its old record, which then names the new pane; the next
# NO-GO pass hands the fix round to that pane and never to the dead one.
cp "$SC/seat-$U-builder.txt" "$SC/seat-$U-builder.keep"; sed 's/^handle=.*/handle=term_new/' "$SC/seat-$U-builder.keep" > "$SC/seat-$U-builder.txt"
rm -f "$TMP/frs-calls"; printf 'echo sixteen\n' > "$W/a.sh"
find "$CODEX_HOME/sessions" -name 'rollout-*-thr-1[1-5]-*.jsonl' -exec touch -t 200001010000 {} + # passes 11-15 age out, as 6-10 did: pass 16 is not past the cap
R16=$(fpass "$W" 16 review "$NOGO"); helper_done 16
check "after a relaunch over a dead record, a NO-GO pass hands the fix round to the new pane" "0 1 0" \
  "$R16 $(grep -c 'terminal send --terminal term_new --text /clear' "$TMP/frs-calls") $(grep -c 'term_frs' "$TMP/frs-calls")"
mv "$SC/seat-$U-builder.keep" "$SC/seat-$U-builder.txt"

# Issue 393: BSD awk refuses a comparison left bare in a print list ("syntax error"), so a NO-GO pass on macOS lost its
# per-class findings step. Every print list in the shell scripts parenthesizes its comparisons.
check "no awk print list in the shell scripts holds an unparenthesized comparison" "" \
  "$(grep -rnE --include='*.sh' 'printf?[[:space:]].*,[^,()]*([=!]=|[<>])[^,()]*\?' "$REAL/scripts" "$REAL/hooks" "$REAL/skills" | grep -v '/__tests__/')"
# Last: the same NO-GO pass under BSD awk, where one is installed (macOS); elsewhere nothing is counted.
if /usr/bin/awk --version 2>/dev/null | grep -q '^awk version'; then
  AWKD=$TMP/bsd-awk; mkdir -p "$AWKD"; ln -sf /usr/bin/awk "$AWKD/awk"
  rm -f "$TMP/frs-calls"; printf 'echo seventeen\n' > "$W/a.sh"
  find "$CODEX_HOME/sessions" -name 'rollout-*-thr-16-*.jsonl' -exec touch -t 200001010000 {} +
  R17=$(PATH=$AWKD:$PATH fpass "$W" 17 review "$NOGO"); helper_done 17
  check "a NO-GO pass under BSD awk prints no awk error and hands the fix round over" "0 0 1" \
    "$R17 $(cat "$TMP/out" "$TMP/err" 2>/dev/null | grep -c 'awk:') $(grep -c 'terminal send --terminal term_frs --text /clear' "$TMP/frs-calls")"
else
  echo "note: no BSD awk here"
fi

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

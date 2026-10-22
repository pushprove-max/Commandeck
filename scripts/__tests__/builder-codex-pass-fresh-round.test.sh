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

# the owner's extra rounds for one unit, with no edit to the tracked settings file.
printf 'echo six\n' > "$W/a.sh"
p6() { (cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-6 bash "$PASS_SH" "$U" 6 review >"$TMP/out" 2>"$TMP/err"); echo $?; }
check "round 6 is over the project's 5" "2 1" "$(p6) $(grep -c 'over the 5 rounds' "$TMP/err")"
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
check "the hand-off stands alone: brief, evidence, the findings, main's rulings inlined, the task and the touched tests" "1 1 1 1 1 1" \
  "$(grep -c "$B/$U.md\$" "$H7") $(grep -c "$B/$U-evidence.md\$" "$H7") $(grep -c 'FINDING-PROBE' "$H7") $(grep -c 'RULING-PROBE' "$H7") $(grep -c 'Orca task: task_frs' "$H7") $(grep -cF 'x/__tests__/y.test.sh' "$H7")"
# Each fix-round session read the whole brief at start, about 37K cache-write tokens a
# time. The findings say what to fix; the brief stays reachable by path for the finding that needs it.
check "the hand-off does not order the brief or the evidence file read whole at start; both stay reachable by path" "0 0 1 1" \
  "$(grep -ci 'read the brief whole' "$H7") $(grep -ci 'read the evidence file whole' "$H7") $(grep -c "Open it only when a finding needs it: $B/$U.md\$" "$H7") $(grep -c "update it before the next pass: $B/$U-evidence.md\$" "$H7")"
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
check "and the helper types nothing and says why" "0 1" \
  "$(grep -c 'terminal send' "$TMP/frs-calls") $(grep -c 'pane term_frs is gone; nothing typed' "$SC/$U-fix-r8.log")"
rm -f "$TMP/frs-calls"; printf 'echo nine\n' > "$W/a.sh"
check "a GO pass hands nothing over" "0 0 0" \
  "$(fpass "$W" 9 review 'VERDICT: GO') $(ls "$B/$U-fix-r9.md" 2>/dev/null | wc -l | tr -d ' ') $(cat "$TMP/frs-calls" 2>/dev/null | wc -l | tr -d ' ')"
printf 'echo ten\n' > "$W/a.sh"
check "a NO-GO pass from another pane (its handle not the seat record's) hands nothing over" "0 0 0" \
  "$(fpass "$W" 10 review "$NOGO" ORCA_TERMINAL_HANDLE=term_other) $(ls "$B/$U-fix-r10.md" 2>/dev/null | wc -l | tr -d ' ') $(cat "$TMP/frs-calls" 2>/dev/null | wc -l | tr -d ' ')"
# A hand-off the pane never took reaches main, with Orca's own answer. The send's output went to /dev/null
# and the log was the only trace, so main never heard that fix round 2 of commandeck-speedups-0-7-2 had not started.
rm -f "$TMP/frs-calls"
(cd "$W" && env PATH=$FB:$PATH COMMANDECK_MAIN=$REPO COMMANDECK_FRESH_ROUND_SETTLE_SECONDS=0 FRS_CALLS=$TMP/frs-calls FRS_PROJ=$PROJ FRS_SEND_FAILS=1 \
  timeout 30 bash "$REAL/scripts/builder-fresh-round.sh" term_frs "$H7" > "$TMP/frs.out" 2>&1); R=$?
check "a /clear Orca refuses: exit 1, Orca's answer in the log, and main is told" "1 1 1" \
  "$R $(grep -c 'typing /clear into term_frs failed (orca: PROBE-REFUSAL)' "$TMP/frs.out") $(cat "$TMP/frs-calls" "$SC/queue/main.jsonl" 2>/dev/null | grep -c "fresh round not started: ${H7##*/}")"


echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

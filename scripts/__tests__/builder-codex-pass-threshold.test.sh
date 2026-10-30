#!/usr/bin/env bash
# Issue 366, the review threshold. A closing pass that names no open P0, P1 or P2 ends the loop: a P3 never holds it.
# From the fifth pass on record a closing NO-GO with no P0 or P1 ends it too (the cap). A P0 or P1 is never capped, and
# one still open two passes past the cap stops the unit for one question to main. The closing reviewer is handed no
# earlier finding. What is still open at a stop is filed, one issue per class, before the merge takes it.
# The count is the passes on the reviewer's record, never the round number. Each unit below is a worktree of its own,
# so each count starts at its own first pass (three reviewers: this fixture has no launcher's brief).
# The fixture is the one merge-unit-local.test.sh uses.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
. "$(dirname "$0")/fixtures/merge-unit-local-setup.sh"

# The merge's gh: `issue view` answers the state in $TMP/issue-<n> (no file: gh's not-found error), and fails with
# gh's own last line while gh-view-fails exists; `issue close` answers as the fixture's does.
cat > "$TMP/bin/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMP/gh-calls"
case "\$1 \$2" in
  "issue close") [ ! -e "$TMP/gh-fails" ] ;;
  "issue view") [ ! -e "$TMP/gh-view-fails" ] || { echo 'HTTP 502: GH-PROBE-ERROR' >&2; exit 1; }
    cat "$TMP/issue-\$3" 2>/dev/null || { echo "GraphQL: Could not resolve to an issue with the number of \$3." >&2; exit 1; } ;;
  *) exit 1 ;;
esac
EOF
echo OPEN > "$TMP/issue-7"; echo OPEN > "$TMP/issue-8"; echo CLOSED > "$TMP/issue-9"
WS=$COMMANDECK_WORKSPACES
tpass() { # [--check] <unit> <N> <kind> [reply]: one pass (or its launch checks); its output in $TMP/pout and $TMP/perr; prints its exit code
  local c=() ev m
  [ "$1" != --check ] || { c=(--check); shift; }
  ev=$WS/$1/.claude/briefs/$1-evidence.md m=$(($2 - 1))
  [ "$m" -lt 1 ] || grep -q "^## Sites checked (pass $m)" "$ev" \
    || printf '\n## Sites checked (pass %s)\nSearch: grep -rn base .\n- a.sh:1 fixed, a fixture\n\n## New code checked (pass %s)\n- a.sh:1 meets a fixture rule\n' "$m" "$m" >> "$ev"
  (cd "$WS/$1" && HOME=$PH TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO COMMANDECK_ROUTING=$TMP/routing.json STUB_THREAD=thr-$1-$2 \
    STUB_REPLY="${4:-VERDICT: GO}" bash "$PASS_SH" ${c[@]+"${c[@]}"} "$1" "$2" "$3" >"$TMP/pout" 2>"$TMP/perr"); echo $?
}
verify() { (cd "$REPO" && PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO bash "$PASS_SH" --verify "$WS/$1" "$1" "$(git -C "$WS/$1" rev-parse HEAD)" >"$TMP/vout" 2>"$TMP/verr"); echo $?; }
prompt() { cat "$WS/$1/.claude/briefs/$1-r$2-prompt-1.md"; } # <unit> <N>: what reviewer 1 of round N was sent
last() { tail -n 1 "$WS/$1/.claude/briefs/$1-r$2-reports.md"; } # <unit> <N>: the round file's verdict line
LED=$REPO/.claude/metrics/decisions.jsonl; mkdir -p "${LED%/*}"
answer() { # <id> <question>: an answered row in main's decisions ledger
  jq -nc --arg id "$1" --arg q "$2" '{id: $id, askedAt: "1999-01-01T00:00:00Z", question: $q, proposedDefault: "redesign",
    source: "builder-codex-pass", answeredAt: "1999-01-02T00:00:00Z", answer: "redesign it"}' >> "$LED"
}
routed() { # <unit> <msg id> <question> [<answer>]: the row the stop's printed route leaves: ask-main.sh's question,
  # recorded by orca-wait.sh as <unit>-msg_<id> with its subject first, answered by answer-worker.sh when <answer> is given
  jq -nc --arg id "$1-$2" --arg q "$3" --arg s "$1 asks" --arg a "${4-}" '{id: $id, askedAt: "1999-01-01T00:00:00Z",
    question: $q, proposedDefault: "none", source: $s, waitsOn: "main",
    answeredAt: (if $a == "" then null else "1999-01-02T00:00:00Z" end), answer: (if $a == "" then null else $a end)}' >> "$LED"
}

# 1. Threshold: a closing GO that names only a P3 ends the loop, and the reviewer is told so (O3's rubric included).
mk th; go th
check "a P3-only pass ends the loop: the round ends GO, the pass prints STOP (threshold), and --verify takes it as a threshold stop naming the open P3" "0 1 1 0 1 1" \
  "$(tpass th 2 final $'- [P3] (class: wording) TH-NIT -- th.txt:1 -- reads oddly -- cat th.txt\nVERDICT: GO') $(last th 2 | grep -cx 'VERDICT: GO') \
$(grep -c '^STOP (threshold): ' "$TMP/pout") $(verify th) $(grep -c 'rule: threshold stop$' "$TMP/vout") \
$(grep -cxF 'Open finding: th.txt - [P3] (class: wording) TH-NIT -- th.txt:1 -- reads oddly -- cat th.txt' "$TMP/vout")"
check "the reviewer is told GO means no P0, P1 or P2, and that a gap in documentation, plan wording or a failure table is P3 unless it hides a real defect" "1 1 0" \
  "$(prompt th 2 | grep -c 'VERDICT: GO when you list no P0, P1 or P2 finding') $(prompt th 2 | grep -c 'A gap in documentation, plan wording or a failure table is P3 unless it hides a real defect; then rate the defect') \
$(prompt th 2 | grep -c 'A GO reply names no level, P0 to P3')"

# 2. O1 and O2: a closing pass that lists an earlier P2 again holds the loop, and the closing reviewer is fresh: it is
# handed the owner's decisions, the stated limits and the plan's accepted failure modes, and no earlier finding,
# Main-only list, sites list or new-code list.
# The plan comes from main, as a real one does: the unit's limits are read against it there (issue 468).
mk oc; printf 'Plan: .claude/plans/oc.md\n' >> "$WS/oc/.claude/briefs/oc.md"; mkdir -p "$REPO/.claude/plans"
printf '# oc\n\n## Accepted failure modes\n\n- ACCEPTED-PROBE: a stale nit is filed, not fixed\n' > "$REPO/.claude/plans/oc.md"
git -C "$REPO" add .claude/plans/oc.md && git -C "$REPO" commit -qm "plan oc" && git -C "$WS/oc" merge -q --no-edit main
go oc
OLD=$'- [P2] (class: lost-reply) OLD-P2 -- oc.txt:1 -- drops a reply -- cat oc.txt'
tpass oc 2 final "$OLD"$'\nVERDICT: NO-GO' >/dev/null
jq -nc '{id: "q-oc-open", askedAt: "1999-01-01T00:00:00Z", question: "Keep the oc reply?", proposedDefault: "keep",
  source: "builder oc", answeredAt: null, answer: null}' >> "$LED"
printf '\nDifferent fix r3: AUTHOR-PROBE took another fix\n\n## Main-only (deferred)\n- DEFERRED-PROBE: a settings entry\n' >> "$WS/oc/.claude/briefs/oc-evidence.md"
echo fixed > "$WS/oc/oc.txt"
check "an open carried-over P2 holds the loop: the closing pass that lists pass 2's P2 again ends NO-GO, prints no stop, and --verify refuses it as a P2 below the cap" "0 1 0 2 1" \
  "$(tpass oc 3 final "$OLD"$'\nVERDICT: GO') $(last oc 3 | grep -cx 'VERDICT: NO-GO') $(grep -c 'STOP' "$TMP/pout") $(verify oc) \
$(grep -c 'a P0, P1 or P2 holds the merge below the cap (pass 3 on record' "$TMP/verr")"
check "the closing prompt carries decisions and accepted failure modes but no earlier findings, fix notes or history files" "0 0 1 0 0 0 0 0 0 1 1" \
  "$(prompt oc 3 | grep -c 'AUTHOR-PROBE') $(prompt oc 3 | grep -c "The author's notes on this round") \
$(prompt oc 3 | grep -c 'Do not open the evidence file, the round reports or fix hand-offs under .claude/briefs .*, or git log') \
$(prompt oc 3 | grep -c 'Findings of the earlier passes') $(prompt oc 3 | grep -c 'OLD-P2') $(prompt oc 3 | grep -c 'DEFERRED-PROBE') \
$(prompt oc 3 | grep -c 'Sites checked: the Builder') $(prompt oc 3 | grep -c 'New code checked: the Builder') $(prompt oc 3 | grep -c '^Earlier pass ') \
$(prompt oc 3 | sed -n '/^Accepted failure modes, from the plan: /,$p' | grep -c 'ACCEPTED-PROBE') $(prompt oc 3 | grep -c 'Open question to the owner q-oc-open')"

# 3. The count is the passes on record: pass 9, the third, is below the cap. A narrowed pass keeps its history.
mk pn; go pn; echo two > "$WS/pn/pn.txt"
tpass pn 2 review $'- [P3] (class: wording) KEPT-P3 -- pn.txt:1 -- a nit -- cat pn.txt\nVERDICT: GO' >/dev/null
echo nine > "$WS/pn/pn.txt"
printf '\nDifferent fix r8: PN-OLD-NOTE\nDifferent fix r9: PN-NOTE took another fix\n\n## Main-only (deferred)\n- DEFERRED-PROBE: a settings entry\n' >> "$WS/pn/.claude/briefs/pn-evidence.md"
check "a narrowed pass is handed this round's author's notes, and not another round's" "0 1 0" \
  "$(tpass pn 9 review $'- [P2] (class: lost-reply) PN-P2 -- pn.txt:1 -- drops a reply -- cat pn.txt\nVERDICT: NO-GO') $(prompt pn 9 | grep -cx 'Different fix r9: PN-NOTE took another fix') $(prompt pn 9 | grep -c 'PN-OLD-NOTE')"
check "the pass number is not the count: pass 9, third on record, runs narrowed with no stop, keeps the earlier findings and the Main-only list, and --verify names pass 3 on record" "review 0 1 1 1 2 1" \
  "$(sed -n 's/^Pass: //p' "$WS/pn/.claude/briefs/pn-r9-reports.md") $(grep -c 'STOP' "$TMP/pout") $(prompt pn 9 | grep -c 'Findings of the earlier passes') \
$(prompt pn 9 | grep -c 'KEPT-P3') $(prompt pn 9 | grep -c 'DEFERRED-PROBE') $(verify pn) $(grep -c '(pass 3 on record' "$TMP/verr")"

# 4. P0 and P1 are never capped: pass 5 with a P1 runs pass 6; a severity the Builder lowers in its round file changes
# nothing (O3); a P1 still open at pass 7 stops the unit for one question, and no later pass runs until main answers.
mk p1; go p1
P1R=$'- [P1] (class: crash) P1-BLOCKER -- p1.txt:1 -- it crashes -- cat p1.txt\nVERDICT: NO-GO'
for n in 2 3 4 5; do tpass p1 "$n" final "$P1R" >/dev/null; done
check "pass 5 with an open P1 runs pass 6: no stop at the cap, --verify refuses it as never capped, and pass 6 runs" "0 2 1 0 1" \
  "$(grep -c 'STOP' "$TMP/pout") $(verify p1) $(grep -c 'a P0 or P1 is never capped' "$TMP/verr") $(tpass p1 6 final "$P1R") \
$(ls "$WS/p1/.claude/briefs/p1-r6-reports.md" | wc -l | tr -d ' ')"
sed 's/\[P1\]/[P3]/' "$WS/p1/.claude/briefs/p1-r6-reports.md" > "$TMP/r6" && mv "$TMP/r6" "$WS/p1/.claude/briefs/p1-r6-reports.md"
check "a severity lowered in the round file changes nothing: --verify still reads the P1 from the reviewer's record" "2 1" \
  "$(verify p1) $(grep -c 'a P0 or P1 is never capped' "$TMP/verr")"
check "a P1 open at pass 7 stops the unit with one question: REVIEW STOP and its decision id, the question to main, no fix hand-off" "0 1 1 0" \
  "$(tpass p1 7 final "$P1R") $(grep -c '^REVIEW STOP: .*decision review-stop-p1-r7' "$TMP/pout") $(grep -c 'ask-main.sh' "$TMP/pout") $(grep -c 'NO FIX HAND-OFF' "$TMP/pout")"
check "--verify refuses the stop on one last line that names REVIEW STOP and its decision id" "2 1" \
  "$(verify p1) $(tail -n 1 "$TMP/verr" | grep -c '^REFUSED: REVIEW STOP: .*decision review-stop-p1-r7; it waits for the owner')"
echo eight > "$WS/p1/p1.txt"; H7=$(git -C "$WS/p1" rev-parse HEAD)
check "the next launch refuses before any commit while review-stop-p1-r7 has no answer" "2 1 $H7" \
  "$(tpass p1 8 final) $(grep -c 'review-stop-p1-r7' "$TMP/perr") $(git -C "$WS/p1" rev-parse HEAD)"
# Decision 10: a design-only pass never clears a code finding, so its GO at the O4 count stops as well.
# Answered the way the stop says: ask-main.sh, then answer-worker.sh, which answers the row under its message id.
routed p1 msg_7 "review-stop-p1-r7: crash: redesign the check" "Proceed with the redesign"; git -C "$WS/p1" checkout -q -- p1.txt
mkdir -p "$WS/p1/.claude/plans"; echo 'Data design: one fence' > "$WS/p1/.claude/plans/p1.md"
check "with r7 answered through ask-main.sh and answer-worker.sh the next pass runs; a design-only GO over the open code P1 is a REVIEW STOP of its own, not a DESIGN GO" "0 1 0" \
  "$(tpass p1 8 final) $(grep -c '^REVIEW STOP: .*decision review-stop-p1-r8' "$TMP/pout") $(grep -c '^DESIGN GO' "$TMP/pout")"
# Main's ruling: a GO clears an earlier held P1 only when every reviewer the pass declared says GO. A pass of three
# whose record keeps one reviewer (two sessions lost) has not cleared it.
# A routed question still open, or one answered for another stop (r80 begins with r8), releases nothing.
routed p1 msg_8 "review-stop-p1-r8: crash: redesign the check"; routed p1 msg_80 "review-stop-p1-r80: crash: x" "go on"
check "the routed question to review-stop-p1-r8, still open, and an answered one to another stop leave the next launch refused" "2 1" \
  "$(tpass --check p1 9 adversarial) $(grep -c 'review-stop-p1-r8 waits' "$TMP/perr")"
answer review-stop-p1-r8 "p1: REVIEW STOP at pass 8"
check "a pass of three reviewers that all say GO clears the P1: no stop" "0 0" "$(tpass p1 9 adversarial) $(grep -c 'REVIEW STOP' "$TMP/pout")"
find "$CODEX_HOME/sessions" -name 'rollout-*-thr-p1-9-[23].jsonl' -exec rm -f {} +
check "a partial pass whose one reviewer said GO does not clear an earlier P1: the next launch refuses, naming review-stop-p1-r9" "2 1" \
  "$(tpass --check p1 10 final) $(grep -c 'review-stop-p1-r9' "$TMP/perr")"

# 5. The cap, and file then merge (O5): pass 5 with only P2 and P3 open stops; the merge refuses until each open class
# names an OPEN issue, one issue per class (the first file a finding cites; no-file when none).
mk cp; go cp
for n in 2 3 4; do tpass cp "$n" final $'- [P2] (class: lost-reply) CP-P2 -- cp.txt:1 -- drops a reply -- cat cp.txt\nVERDICT: NO-GO' >/dev/null; done
CAP=$'- [P2] (class: lost-reply) CAP-A -- cp.txt:1 -- drops a reply -- cat cp.txt\n- [P2] (class: lost-reply) CAP-B -- cp.txt:2 -- drops another -- cat cp.txt\n- [P3] (class: wording) CAP-C -- a nit with no place -- none\nVERDICT: NO-GO'
check "pass 5 with an open P2 files it and merges: STOP (cap), and --verify takes the NO-GO as a cap stop with one Open finding line per finding" "0 1 0 1 3" \
  "$(tpass cp 5 final "$CAP") $(grep -c '^STOP (cap): ' "$TMP/pout") $(verify cp) $(grep -c 'rule: cap stop$' "$TMP/vout") $(grep -c '^Open finding: ' "$TMP/vout")"
check "two findings of one class file one issue: the open classes are cp.txt and no-file" "cp.txt no-file" \
  "$(sed -n 's/^Open finding: \([^ ]*\) .*/\1/p' "$TMP/vout" | awk '!s[$0]++' | paste -sd' ' -)"
H0=$(git -C "$REPO" rev-parse HEAD)
check "the merge refuses until the open findings are filed: step 1, naming each class and --filed, main unchanged" "1 1 1 1 $H0" \
  "$(merge cp) $(grep -c '^FAILED step 1 filing: .*cp\.txt.*no-file' "$TMP/out") $(grep -c -- "--filed '<class>=#<n>'" "$TMP/out") \
$(grep -c 'comment the finding there' "$TMP/out") $(git -C "$REPO" rev-parse HEAD)"
check "a filed issue must be open: a closed one, a class not open, a filing left out and a failed gh read each refuse" "1 1 1 1 1 1 1 1 $H0" \
  "$(merge cp --filed 'cp.txt=#9' --filed 'no-file=#8') $(grep -c '#9 .*CLOSED' "$TMP/out") \
$(merge cp --filed 'cp.txt=#7' --filed 'no-file=#8' --filed 'zz.sh=#8') $(grep -c 'zz\.sh' "$TMP/out") \
$(merge cp --filed 'cp.txt=#7') $(grep -c 'no-file' "$TMP/out") \
$(touch "$TMP/gh-view-fails"; merge cp --filed 'cp.txt=#7' --filed 'no-file=#8') $(grep -c 'GH-PROBE-ERROR' "$TMP/out") $(git -C "$REPO" rev-parse HEAD)"
rm -f "$TMP/gh-view-fails"
check "a duplicate comments instead of filing: an existing OPEN issue is accepted for each class, and the squash names each filing" "0 1 1 1" \
  "$(merge cp --filed 'cp.txt=#7' --filed 'no-file=#8') $(grep -c '^DONE unit=cp merged=local' "$TMP/out") \
$(git -C "$REPO" log -1 --format=%B | grep -cx 'Filed: #7 cp.txt') $(git -C "$REPO" log -1 --format=%B | grep -cx 'Filed: #8 no-file')"

# 6. The cap ends the loop only on an open P2 (the host's rule): a closing NO-GO at the cap that names no P2 (only a
# P3 here) is no cap stop, so it cannot merge with nothing to file.
mk c3; go c3
for n in 2 3 4; do tpass c3 "$n" final $'- [P2] (class: lost-reply) C3-P2 -- c3.txt:1 -- drops a reply -- cat c3.txt\nVERDICT: NO-GO' >/dev/null; done
check "a NO-GO at the cap that names no P2 is no cap stop: no stop line, and --verify refuses it" "0 0 2 1" \
  "$(tpass c3 5 final $'- [P3] (class: wording) C3-P3 -- c3.txt:1 -- a nit -- cat c3.txt\nVERDICT: NO-GO') $(grep -c 'STOP' "$TMP/pout") $(verify c3) \
$(grep -c 'names no open P2' "$TMP/verr")"

# 7. The threshold stop reads what is open over the whole record: a clean closing GO after a GO round's P3 still stops,
# so the Builder is told to leave the P3 to main's filing.
mk t2; go t2; echo two > "$WS/t2/t2.txt"
tpass t2 2 review $'- [P3] (class: wording) T2-P3 -- t2.txt:1 -- a nit -- cat t2.txt\nVERDICT: GO' >/dev/null
echo three > "$WS/t2/t2.txt"
check "a clean closing GO with an earlier GO round's P3 open prints STOP (threshold), and --verify lists that P3" "0 1 0 1" \
  "$(tpass t2 3 final) $(grep -c '^STOP (threshold): ' "$TMP/pout") $(verify t2) $(grep -c '^Open finding: t2.txt .*T2-P3' "$TMP/vout")"

# 8. The latest pass is the one that ended last, never the highest round number (the Builder picks N): a P1 in pass 8,
# run after a clean pass 20, is still held at the seventh pass on record, and the stop names pass 8.
mk lt; go lt
LTP1=$'- [P1] (class: crash) LT-P1 -- lt.txt:1 -- it crashes -- cat lt.txt\nVERDICT: NO-GO'
for n in 2 3 4 5 6; do tpass lt "$n" final "$LTP1" >/dev/null; done
# Passes 20 and 8 both follow the NO-GO pass 6, so both need pass 6's lists (tpass writes pass N-1's only).
printf '\n## Sites checked (pass 6)\nSearch: grep -rn base .\n- a.sh:1 fixed, a fixture\n\n## New code checked (pass 6)\n- a.sh:1 meets a fixture rule\n' >> "$WS/lt/.claude/briefs/lt-evidence.md"
check "a P1 in a pass that ended after a higher-numbered clean pass is a REVIEW STOP naming that pass" "0 0 1" \
  "$(tpass lt 20 final) $(tpass lt 8 final "$LTP1") $(grep -c '^REVIEW STOP: .*decision review-stop-lt-r8' "$TMP/pout")"

# 9. Issue 373: the owner picks the lowest severity that holds a merge (reviewBlockSeverity). The setup answer reaches the
# pass as COMMANDECK_REVIEW_LOOP, which beats /config. At P3 a GO beside a P3 is no GO; at P1 a GO beside a P2 ends the
# loop and the P2 is filed like any open finding. Either way the reviewer is told the levels it was asked for.
loop() { COMMANDECK_REVIEW_LOOP=$1 "${@:2}"; } # <reviewLoop json> <command...>
# The blocking severity is in every prompt, so a build keeps the one its first pass was sent: its passes run under it.
mk bk3; loop '{"blockAt":"P3"}' go bk3 >/dev/null
BK3=$'- [P3] (class: wording) BK3-NIT -- bk3.txt:1 -- reads oddly -- cat bk3.txt\nVERDICT: GO'
check "blockAt P3: a GO beside a P3 is read as NO-GO, and the prompt names P0 to P3" "0 1 1" \
  "$(loop '{"blockAt":"P3"}' tpass bk3 2 final "$BK3") $(last bk3 2 | grep -cx 'VERDICT: NO-GO') \
$(prompt bk3 2 | grep -c 'VERDICT: GO when you list no P0, P1, P2 or P3 finding (known gaps alone are GO)')"
mk bk1; loop '{"blockAt":"P1"}' go bk1 >/dev/null
BK1=$'- [P2] (class: wording) BK1-NIT -- bk1.txt:1 -- reads oddly -- cat bk1.txt\nVERDICT: GO'
check "blockAt P1: a GO beside a P2 ends the loop with the P2 open, and the prompt names P0 and P1" "0 1 1 0 1 1" \
  "$(loop '{"blockAt":"P1"}' tpass bk1 2 final "$BK1") $(last bk1 2 | grep -cx 'VERDICT: GO') \
$(grep -c '^STOP (threshold): .*names no P0 or P1, so the review loop ends with only P2 and P3 findings open' "$TMP/pout") \
$(loop '{"blockAt":"P1"}' verify bk1) $(grep -c '^Open finding: bk1.txt - \[P2\] (class: wording) BK1-NIT' "$TMP/vout") \
$(prompt bk1 2 | grep -c 'VERDICT: GO when you list no P0 or P1 finding (P2 and P3 findings and known gaps alone are GO)')"
mk bk2; go bk2
check "with the default, a GO beside a P2 stays NO-GO and the prompt is the one it always was" "0 1 1" \
  "$(tpass bk2 2 final "$BK1") $(last bk2 2 | grep -cx 'VERDICT: NO-GO') \
$(prompt bk2 2 | grep -c 'VERDICT: GO when you list no P0, P1 or P2 finding (P3 findings and known gaps alone are GO)')"

# 10. Issue 373: the cap is the owner's number (reviewPassCap), and the fresh closing reviewer is the owner's choice.
# A cap of 3 stops the third pass on record, where the default 5 lets it run on.
mk pc; go pc
PC=$'- [P2] (class: lost-reply) PC-P2 -- pc.txt:1 -- drops a reply -- cat pc.txt\nVERDICT: NO-GO'
tpass pc 2 final "$PC" >/dev/null
check "a cap of 3 makes the third pass on record a cap stop, and --verify takes it as one" "0 1 0 1" \
  "$(loop '{"passCap":"3"}' tpass pc 3 final "$PC") $(grep -c '^STOP (cap): .*at or past the cap of 3, and names an open P2' "$TMP/pout") \
$(loop '{"passCap":"3"}' verify pc) $(grep -c 'rule: cap stop$' "$TMP/vout")"
mk pd; go pd
tpass pd 2 final "$PC" >/dev/null
check "and the default cap of 5 lets the same third pass run on: no stop, and --verify refuses a P2 below the cap" "0 0 2" \
  "$(tpass pd 3 final "$PC") $(grep -c '^STOP' "$TMP/pout") $(verify pd)"
mk fc; go fc
tpass fc 2 final $'- [P2] (class: lost-reply) FC-P2 -- fc.txt:1 -- drops a reply -- cat fc.txt\nVERDICT: NO-GO' >/dev/null
echo fixed > "$WS/fc/fc.txt"
check "freshClosing no: the closing pass is handed the earlier finding and the history files stay open to it, and --verify takes its GO" "0 1 0 0" \
  "$(loop '{"freshClosing":"no"}' tpass fc 3 final) $(prompt fc 3 | grep -c 'FC-P2') \
$(prompt fc 3 | grep -c 'Do not open the evidence file, the round reports or fix hand-offs') $(loop '{"freshClosing":"no"}' verify fc)"

# 11. Issue 376: a round that is missing a reviewer's verdict never clears an earlier P0 or P1. Three ways a verdict is
# missing: a short round, a round with no answer at all (a cut row), a reply with no verdict (said none).
rsi() { (UNIT=u REVIEW_CAP=5; eval "$(sed -n '/^review_stop_id() {/,/^}/p' "$PASS_SH")"; review_stop_id "$1"); } # <rows>: the stop id, cap 5
row() { # <round> <k> <of> <said>: the row of reviewer k of a round of <of>, which ended at minute <round>
  printf '@ t%s%s full %s %s %s 2026-01-01T00:0%s:00Z 2026-01-01T00:0%s:30Z c0 whole %s\n' "$1" "$2" "$2" "$3" "$1" "$1" "$1" "$4"
}
CUT7='@ t7c cut 0 0 7 2026-01-01T00:07:00Z 2026-01-01T00:07:00Z - - cut'
GOOD=$(for r in 1 2 3 4 5 6; do row "$r" 1 1 GO; done)
P1HELD=$(for r in 1 2 3 4 5; do row "$r" 1 1 GO; done; row 6 1 1 NO-GO; echo '- [P1] (class: c) A -- a.sh:1 -- bug -- cat a.sh')
none() { echo "${1:-none}"; }
check "partial_round_keeps_p1_open: pass 7 with reviewer 1 of 3 GO does not clear the pass 6 P1; all three GO does" "review-stop-u-r7 none" \
  "$(rsi "$P1HELD"$'\n'"$(row 7 1 3 GO)") $(none "$(rsi "$P1HELD"$'\n'"$(row 7 1 3 GO; row 7 2 3 GO; row 7 3 3 GO)")")"
check "a short round holds on its own, with no earlier P1 to keep open" "review-stop-u-r7 none" \
  "$(rsi "$GOOD"$'\n'"$(row 7 1 3 GO; row 7 3 3 GO)") $(none "$(rsi "$GOOD"$'\n'"$(row 7 1 1 GO)")")"
check "a reply with no verdict does not count as its reviewer's verdict: the round holds" "review-stop-u-r7 none" \
  "$(rsi "$GOOD"$'\n'"$(row 7 1 1 none)") $(none "$(rsi "$GOOD"$'\n'"$(row 7 1 1 NO-GO)")")"
check "a round run again after an abandoned launch clears the P1 before it (the cut row beside a whole set of rows)" "review-stop-u-r7 none none" \
  "$(rsi "$P1HELD"$'\n'"$CUT7") $(none "$(rsi "$P1HELD"$'\n'"$CUT7"$'\n'"$(row 7 1 1 GO)")") \
$(none "$(rsi "$P1HELD"$'\n'"$(row 7 1 3 GO; row 7 2 3 GO; row 7 3 3 GO)"$'\n'"$CUT7")")"
# The same on the reviewer's own session files: a wholly cut-off round (a session with no answer) is on record as a cut row.
mk cu; go cu
CUP=$'- [P1] (class: crash) CU-BLOCKER -- cu.txt:1 -- it crashes -- cat cu.txt\nVERDICT: NO-GO'
for n in 2 3 4 5 6; do tpass cu "$n" final "$CUP" >/dev/null; done
tpass cu 7 final >/dev/null
SESS=$(find "$CODEX_HOME/sessions" -name 'rollout-*-thr-cu-7-1.jsonl')
grep -v task_complete "$SESS" > "$TMP/cut7" && mv "$TMP/cut7" "$SESS"
check "a round whose every reviewer was cut off is on record as a cut row and holds the P1 before it" "2 1" \
  "$(tpass --check cu 8 final) $(grep -c 'review-stop-cu-r7' "$TMP/perr")"
# Its round is run again (the abandoned launch wrote no round file): the launch is not refused by its own abandoned row,
# and the rerun's rows make the round whole.
sed 's/thr-cu-7-1/thr-cu-7x-1/g' "$SESS" > "${SESS/thr-cu-7-1/thr-cu-7x-1}" && rm -f "$SESS" "$WS/cu/.claude/briefs/cu-r7-reports.md"
check "the abandoned round run again launches and clears the P1: no stop" "0 0" \
  "$(tpass cu 7 final) $(grep -c 'REVIEW STOP' "$TMP/pout")"
# The no-closing-pass chain: a narrowed pass cut off after the first pass has no verdict, so it holds the merge. Pass 3
# is launched after the cut-off, so it lists no pass 2 and the record agrees; the cut row is what holds the merge.
mk vc; loop '{"closingPass":"no"}' go vc >/dev/null
echo a >> "$WS/vc/vc.txt"; loop '{"closingPass":"no"}' tpass vc 2 review >/dev/null
SESS=$(find "$CODEX_HOME/sessions" -name 'rollout-*-thr-vc-2-1.jsonl')
grep -v task_complete "$SESS" > "$TMP/cutv" && mv "$TMP/cutv" "$SESS"
echo b >> "$WS/vc/vc.txt"; loop '{"closingPass":"no"}' tpass vc 3 review >/dev/null
check "--verify refuses a cut-off pass after the first pass in the no-closing-pass chain, naming it" "2 1" \
  "$(loop '{"closingPass":"no"}' verify vc) $(grep -c 'thr-vc-2-1.*was cut off before it answered' "$TMP/verr")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

#!/usr/bin/env bash
# Issue 366, the review threshold. A closing pass that names no open P0, P1 or P2 ends the loop: a P3 never holds it.
# From the fifth pass on record every pass is a closing pass, and passes run until clean: a NO-GO never merges. A P0 or
# P1 still open two passes later stops the unit for one question to main. The closing reviewer is handed no
# earlier finding. What is still open at a stop is filed, one issue per class, before the merge takes it.
# The count is the passes on the reviewer's record, never the round number. Each unit below is a worktree of its own,
# so each count starts at its own first pass (three reviewers: this fixture has no launcher's brief).
# The fixture is the one merge-unit-local.test.sh uses.
# Sections 5, 9 and 10 of builder-codex-pass-threshold.test.sh, run apart so neither file holds a job past its cap.
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

# 5. Passes run until clean, and file then merge (O5): pass 5 with only a P2 open is no stop, so pass 6 runs; pass 6
# ends GO with P3s open (a threshold stop), and the merge refuses until each open class names an OPEN issue, one issue
# per class (the first file a finding cites; no-file when none).
mk cp; go cp
for n in 2 3 4; do tpass cp "$n" final $'- [P2] (class: lost-reply) CP-P2 -- cp.txt:1 -- drops a reply -- cat cp.txt\nVERDICT: NO-GO' >/dev/null; done
# The bug: a closing NO-GO with only a P2 open at the fifth pass printed STOP (cap) and merged with the P2 open.
check "P2-only pass 6 launches: pass 5's lone P2 prints no stop, --verify refuses its NO-GO, and pass 6 runs, a threshold stop with one Open finding line per finding" "0 0 2 1 0 1 0 1 3" \
  "$(tpass cp 5 final $'- [P2] (class: lost-reply) CP-P2 -- cp.txt:1 -- drops a reply -- cat cp.txt\nVERDICT: NO-GO') $(grep -c 'STOP' "$TMP/pout") $(verify cp) \
$(grep -c 'ended NO-GO: a P0, P1 or P2 holds the merge (pass 5 on record): passes run until clean' "$TMP/verr") \
$(tpass cp 6 final $'- [P3] (class: lost-reply) CAP-A -- cp.txt:1 -- drops a reply -- cat cp.txt\n- [P3] (class: lost-reply) CAP-B -- cp.txt:2 -- drops another -- cat cp.txt\n- [P3] (class: wording) CAP-C -- a nit with no place -- none\nVERDICT: GO') \
$(grep -c '^STOP (threshold): ' "$TMP/pout") $(verify cp) $(grep -c 'rule: threshold stop$' "$TMP/vout") $(grep -c '^Open finding: ' "$TMP/vout")"
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

# 10. Issue 373: the closing pass from setting is the owner's number (reviewPassCap), and the fresh closing reviewer is
# the owner's choice.
PC=$'- [P2] (class: lost-reply) PC-P2 -- pc.txt:1 -- drops a reply -- cat pc.txt\nVERDICT: NO-GO'
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

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

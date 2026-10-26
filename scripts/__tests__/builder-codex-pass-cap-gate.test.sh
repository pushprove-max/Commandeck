#!/usr/bin/env bash
# Issue 377, the cap gate: past the cap with no P0 or P1 open nothing is left for a pass to review, so a pass after the
# cap stop, or on a change that is only the plan, brief or metrics, is refused before it stages or commits anything.
# A closing GO at the cap is exempt (commits after it still get their narrowed pass), and a P0 or P1 is never refused
# by this gate: the REVIEW STOP gate owns it. A cap of 3 keeps the runs short (a cap of 1 for the plan-only case: the
# first pass is already at it). Its own file, not a section of builder-codex-pass-threshold.test.sh: that file runs
# 45 s alone against the runner's 120 s per-file cap, which no file raises.
# The fixture is the one merge-unit-local.test.sh uses.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
. "$(dirname "$0")/fixtures/merge-unit-local-setup.sh"

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
loop() { COMMANDECK_REVIEW_LOOP=$1 "${@:2}"; } # <reviewLoop json> <command...>
cap3() { loop '{"passCap":"3"}' "$@"; }
CG=$'- [P2] (class: lost-reply) CG-P2 -- cg.txt:1 -- drops a reply -- cat cg.txt\nVERDICT: NO-GO'
P1R=$'- [P1] (class: crash) P1-BLOCKER -- p1.txt:1 -- it crashes -- cat p1.txt\nVERDICT: NO-GO'

mk cg; go cg; cap3 tpass cg 2 final "$CG" >/dev/null; echo two > "$WS/cg/cg.txt"
CGSTOP=$(cap3 tpass cg 3 final "$CG"); CGSTOP="$CGSTOP $(grep -c '^STOP (cap)' "$TMP/pout")"
HCG=$(git -C "$WS/cg" rev-parse HEAD)
mkdir -p "$WS/cg/.claude/plans"; echo 'Data design: one fence' > "$WS/cg/.claude/plans/cg.md"
D=$(cap3 tpass cg 4 final); DE=$(grep -c 'past the cap of 3, and no P0 or P1 is open' "$TMP/perr")
CK=$(cap3 tpass --check cg 4 final)
rm -f "$WS/cg/.claude/plans/cg.md"; echo three > "$WS/cg/cg.txt"
C=$(cap3 tpass cg 4 final); CE=$(grep -c 'past the cap of 3, and no P0 or P1 is open' "$TMP/perr")
check "cap_stop_refuses_later_pass: after the pass 3 cap stop a design-only pass 4 is refused before any commit (and by --check), and so is a code pass 4" "0 1 2 1 2 2 1 $HCG 0" \
  "$CGSTOP $D $DE $CK $C $CE $(git -C "$WS/cg" rev-parse HEAD) $(ls "$WS/cg/.claude/briefs/cg-r4-reports.md" 2>/dev/null | wc -l | tr -d ' ')"

CQ=$'- [P2] (class: lost-reply) CQ-P2 -- cq.txt:1 -- drops a reply -- cat cq.txt\nVERDICT: NO-GO'
mk cq; loop '{"passCap":"1"}' tpass cq 1 adversarial "$CQ" >/dev/null
mkdir -p "$WS/cq/.claude/plans"; echo 'Data design: one fence' > "$WS/cq/.claude/plans/cq.md"
PL=$(loop '{"passCap":"1"}' tpass cq 2 review); PLE=$(grep -c 'the change to review is plan-only' "$TMP/perr")
echo two > "$WS/cq/cq.txt"
check "past the cap a plan-only change is refused; the same change with code launches" "2 1 0" \
  "$PL $PLE $(loop '{"passCap":"1"}' tpass cq 2 review)"

# A closing NO-GO that names no finding the cap merges (here no finding at all) is no cap stop: the next closing pass runs.
mk cn; go cn; cap3 tpass cn 2 final "$CG" >/dev/null; echo two > "$WS/cn/cn.txt"
cap3 tpass cn 3 final 'VERDICT: NO-GO' >/dev/null; echo three > "$WS/cn/cn.txt"
check "past the cap a closing NO-GO with no cappable finding is not a cap stop: the next closing pass launches" "0 0" \
  "$(cap3 tpass cn 4 final) $(grep -c 'past the cap' "$TMP/pout")"

# A closing GO at the cap ends the loop; commits made after it still get their narrowed pass.
mk ce; go ce; cap3 tpass ce 2 final "$CG" >/dev/null; echo two > "$WS/ce/ce.txt"
cap3 tpass ce 3 final 'VERDICT: GO' >/dev/null
echo late > "$WS/ce/ce.txt"; git -C "$WS/ce" commit -qam "feat(ce): a later commit"
check "a closing GO at the cap does not refuse the narrowed pass after a later commit" "0 0" \
  "$(cap3 tpass ce 4 review) $(grep -c 'past the cap' "$TMP/perr")"

# An open P1 is never capped: the gate leaves it to the REVIEW STOP gate, even on a change that is only the plan.
mk c1; go c1; cap3 tpass c1 2 final "$P1R" >/dev/null; cap3 tpass c1 3 final "$P1R" >/dev/null
check "a P1 still open past the cap is never refused by the cap gate" "0 0" \
  "$(cap3 tpass c1 4 final "$P1R") $(grep -c 'past the cap' "$TMP/perr")"

# A round run again after an abandoned launch (r1 findings, classes abandoned-round and incomplete-round): its cut row stands
# for a round with no answer, as review_stop_id and the merge's AFTER list read it, so once every reviewer the rerun declared
# is on record the round is whole and the cap gate judges it like any other. The rows are the pass's own record, fed to the
# gate directly, with the cut row on either side of the rerun's rows.
capg() { (REVIEW_CAP=3 BLK=2; eval "$(sed -n '/^cap_gate_reason() {/,/^}/p' "$PASS_SH")"; cap_gate_reason "$1" "$2"); } # <rows> <plan-only 0|1>
grow() { printf '@ t%s%s %s 1 1 %s 2026-01-01T00:0%s:00Z 2026-01-01T00:0%s:30Z c0 whole %s\n' "$1" "$2" "$3" "$1" "$1" "$1" "$4"; } # <round> <tag> <kind> <said>
CUT3='@ t3c cut 0 0 3 2026-01-01T00:03:00Z 2026-01-01T00:03:00Z - - cut'
GO12=$(grow 1 a final GO; grow 2 a final GO)
NOGO3=$(grow 3 a final NO-GO; echo '- [P2] (class: lost-reply) CG-P2 -- cg.txt:1 -- drops a reply -- cat cg.txt')
GO3=$(grow 3 a final GO)
check "a closing NO-GO rerun of a round with an abandoned cut row is still a cap stop, whichever row comes first and whatever the change" "code code code code" \
  "$(capg "$GO12"$'\n'"$CUT3"$'\n'"$NOGO3" 0) $(capg "$GO12"$'\n'"$NOGO3"$'\n'"$CUT3" 0) $(capg "$GO12"$'\n'"$CUT3"$'\n'"$NOGO3" 1) $(capg "$GO12"$'\n'"$NOGO3"$'\n'"$CUT3" 1)"
check "a closing GO rerun of a round with an abandoned cut row is still a closing GO: no refusal, even on a plan-only change" "none none" \
  "$(capg "$GO12"$'\n'"$CUT3"$'\n'"$GO3" 1 | grep . || echo none) $(capg "$GO12"$'\n'"$GO3"$'\n'"$CUT3" 1 | grep . || echo none)"
check "a round that is only its cut row holds the gate open" "none" "$(capg "$GO12"$'\n'"$CUT3" 1 | grep . || echo none)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

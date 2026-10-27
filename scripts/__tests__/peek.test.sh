#!/usr/bin/env bash
# Self-test for peek.sh: several reads in one call, and a review bundle that follows the read-cold order. The
# bundle cases build a temp repo whose plan carries a change-log sentinel and whose briefs dir holds evidence and
# round-report sentinels: a reviewer given those would be anchored on the author's account, so none may appear.
# A plan judge reads the frozen copy its seat spec names (--plan), never the live plan.
# Run: bash scripts/run-shell-tests.sh scripts/__tests__/peek.test.sh
set -u
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PEEK=$REAL/scripts/peek.sh
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected $2, got $3)"; fi; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
R=$TMP/outer/repo
U=unit-2026-10-27
mkdir -p "$R/.claude/briefs" "$R/.claude/plans" "$R/docs"
git -C "$R" init -q -b main
printf 'one\ntwo\nthree\nfour\nfive\n' > "$R/a.txt"
printf 'l1\nl2\nl3\nl4\nl5\nl6\n' > "$R/a b.md"
printf '# T\n## Alpha\nALPHA-BODY\n### Sub\nSUB-BODY\n## Beta\nBETA-BODY\n' > "$R/x.md"
seq 1 500 | sed 's/^/line /' > "$R/huge.md"
printf '# plan\n## Why\nWHY-SENT\n## Decisions (reopened only on a counterexample)\nDEC-SENT\n### Sub\nSUBDEC-SENT\n## Accepted failure modes (cite)\nACC-SENT\n## Stated limits (every reviewer)\nLIM-SENT\n## Claims to falsify\nCLAIM-SENT\n## Plan change log\nCHANGELOG-SENT\n## Other\nOTHER-SENT\n' > "$R/.claude/plans/$U.md"
printf '# brief\nBRIEF-SENT\n' > "$R/.claude/briefs/$U.md"
printf 'EVIDENCE-SENT\n' > "$R/.claude/briefs/$U-evidence.md"
printf 'ROUND-SENT\n' > "$R/.claude/briefs/$U-r1-reports.md"
printf 'PAVED-SENT\n' > "$R/.claude/paved-road.md"
git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -q -m base
git -C "$R" switch -q -c feat
printf 'changed\n' > "$R/docs/changed-file.txt"
git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -q -m change
pk() { (cd "$R" && timeout 20 bash "$PEEK" "$@") > "$TMP/out" 2>&1; echo $?; }
cnt() { grep -c -- "$1" "$TMP/out"; }
line() { grep -n -m1 -- "$1" "$TMP/out" | cut -d: -f1; }

check "three items, one call" "0 3 1 1 1" \
  "$(pk a.txt 'a b.md:2-3' 'x.md#Alpha') $(cnt '^== ') $(cnt '^1: one') $(cnt '^3: l3') $(cnt 'ALPHA-BODY')"
check "heading section stops at the next heading of its level, keeping subsections" "1 1 0" \
  "$(pk 'x.md#Alpha' >/dev/null; cnt 'SUB-BODY') $(cnt '^3: ALPHA-BODY') $(cnt BETA-BODY)"

check "unit bundle: diff stat first, plan after, no evidence, rounds or change log" "0 1 1 1 0 0 0 0 1 1" \
  "$(pk --unit "$U") $([ "$(line 'changed-file.txt')" -lt "$(line "plans/$U.md")" ] && echo 1 || echo 0) $(cnt BRIEF-SENT) $(cnt PAVED-SENT) $(cnt EVIDENCE-SENT) $(cnt ROUND-SENT) $(cnt CHANGELOG-SENT) $(cnt LATER-SENT) $(cnt OTHER-SENT) $(cnt '^3: WHY-SENT')"
check "an absent bundle file prints (none)" "0 1" \
  "$(rm "$R/.claude/paved-road.md"; pk --unit "$U") $(grep -A1 -- "paved-road.md ==" "$TMP/out" | grep -c '(none)')"
printf 'PAVED-SENT\n' > "$R/.claude/paved-road.md"
check "closing bundle: diff stat and the plan's claim sections only" "0 1 1 1 1 1 0 0 0 0 0 0 1" \
  "$(pk --unit "$U" --closing) $(cnt 'changed-file.txt') $(cnt '^[0-9]*: DEC-SENT') $(cnt ACC-SENT) $(cnt LIM-SENT) $(cnt CLAIM-SENT) $(cnt WHY-SENT) $(cnt CHANGELOG-SENT) $(cnt OTHER-SENT) $(cnt BRIEF-SENT) $(cnt PAVED-SENT) $(cnt "briefs/$U") $([ "$(line 'changed-file.txt')" -lt "$(line DEC-SENT)" ] && echo 1 || echo 0)"

check "odd paths, missing heading, cap" "1 1 1 1 1 0" \
  "$(pk 'a b.md:3-5' 'x.md#No such heading' huge.md) $(cnt "^3: l3") $(cnt "no section 'No such heading' in x.md") $(cnt '^400: line 400') $(cnt 'cut at 400; resume: peek.sh huge.md:401-500') $(cnt '^401: ')"
check "a missing file is exit 1 and named" "1 1" "$(pk nope.md) $(cnt 'nope.md')"
head -c 30000 /dev/zero | tr '\0' 'y' | fold -w 100 > "$R/big1.txt"
check "total cap: output stops at 60 KB and says so" "1 1" \
  "$(pk big1.txt big1.txt big1.txt >/dev/null; [ "$(wc -c < "$TMP/out")" -le 62000 ] && echo 1 || echo 0) $(cnt 'cut at 60 KB')"
check "-g prints matches with context" "0 1" "$(pk -g 'three' a.txt) $(cnt '^3:three')"
# A cut a reviewer cannot see reads as the whole answer: every cap names itself.
check "every cut says so: -g past 400 lines" "0 1 0" \
  "$(pk -g line huge.md) $(cnt 'cut at 400; resume: peek.sh huge.md:401-500') $(cnt '^401:')"
head -c 90000 /dev/zero | tr '\0' 'b' | fold -w 200 > "$R/.claude/briefs/$U.md"
check "every cut says so: a bundle stops at 60 KB total" "1 1 0" \
  "$(pk --unit "$U" >/dev/null; [ "$(wc -c < "$TMP/out")" -le 62000 ] && echo 1 || echo 0) $(cnt 'cut at 60 KB') $(cnt PAVED-SENT)"
printf '# brief\nBRIEF-SENT\n' > "$R/.claude/briefs/$U.md"

check "refuses checkout root and its parent" "2 2 2 2 2 2 2" \
  "$(pk .) $(pk ..) $(pk "$R") $(pk "$TMP/outer") $(pk /) $(cnt 'refused') $(pk .. >/dev/null; cnt 'refused')"
check "refuses root by every spelling and still reads a file under it" "2 2 0" \
  "$(pk ./) $(pk docs/..) $(pk docs/changed-file.txt)"
check "--unit reads only the named paths" "0 0" "$(pk --unit "$U" >/dev/null; cnt 'r1-reports') $(cnt 'EVIDENCE')"

# A plan judge's seat spec names a read-only copy of the plan: --plan reads that copy in place of the live plan.
printf '# plan\n## Why\nLIVE-SENTINEL\n' > "$R/.claude/plans/ju.md"
printf '# plan\n## Why\nFROZEN-SENTINEL\n' > "$TMP/frozen-plan.md"; chmod 444 "$TMP/frozen-plan.md"
check "a judge's bundle reads the frozen plan, never the live one" "0 1 0 1 0" \
  "$(pk --unit ju --plan "$TMP/frozen-plan.md") $(cnt FROZEN-SENTINEL) $(cnt LIVE-SENTINEL) $(pk --unit ju --plan "$TMP/no-such-plan.md") $(cnt LIVE-SENTINEL)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

#!/usr/bin/env bash
# Self-test for file-open-findings.sh. A unit may merge with P2 and P3 findings
# still open, and filing them was left to memory. What must hold: every finding the merge's proof lists open becomes one
# labelled issue, the same finding is never filed twice, and a GitHub failure
# is loud without touching the merge that already happened.
# The gh here is a fake, first on PATH: no test reaches GitHub.
set -uo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT=$HERE/file-open-findings.sh
BOX=$(mktemp -d); trap 'rm -rf "$BOX"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi; }

mkdir -p "$BOX/bin" "$BOX/gh/open"
# The fake: `issue list --search` answers from the bodies it was given,
# `issue create` stores the body and prints the new issue's address.
# GH_FAIL=create or GH_FAIL=list makes that call fail.
cat > "$BOX/bin/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" | tr '\n' ' ' >> "$BOX/gh/calls"; echo >> "$BOX/gh/calls"
# kill: the script that called gh dies at once (gh's parent is its command substitution).
[ "\${GH_FAIL:-}" != kill ] || kill -9 \$(ps -o ppid= -p \$PPID)
# GH_PLAN="fail ok ok kill": what the first, second... call of a run does; the calls file is emptied first.
PLAN=(\${GH_PLAN:-}); ACT=\${PLAN[\$((\$(wc -l < "$BOX/gh/calls") - 1))]:-}
[ "\$ACT" != kill ] || kill -9 \$(ps -o ppid= -p \$PPID)
[ "\$ACT" != fail ] || { echo "gh: no network" >&2; exit 1; }
case "\$1 \$2" in
  "issue list")
    [ "\${GH_FAIL:-}" != list ] || { echo "gh: no network" >&2; exit 1; }
    while [ \$# -gt 0 ]; do [ "\$1" = --search ] && KEY=\$(grep -oE 'pp-finding-[0-9a-f]+' <<<"\$2"); shift; done
    grep -lF "\$KEY" "$BOX"/gh/open/* 2>/dev/null | head -1 | sed 's#.*/##' ;;
  "issue create")
    [ "\${GH_FAIL:-}" != create ] || { echo "gh: no network" >&2; exit 1; }
    N=\$((100 + \$(ls "$BOX/gh/open" | wc -l) + 1))
    while [ \$# -gt 0 ]; do [ "\$1" = --body ] && printf '%s\n' "\$2" > "$BOX/gh/open/\$N"; shift; done
    echo "https://github.com/example/repo/issues/\$N" ;;
  *) echo "the fake gh has no \$1 \$2" >&2; exit 9 ;;
esac
EOF
chmod +x "$BOX/bin/gh"
export PATH=$BOX/bin:$PATH
[ "$(command -v gh)" = "$BOX/bin/gh" ] || { echo "FAIL the fake gh is not first on PATH; stopping before any call"; exit 1; }

# A repository whose last commit is the squash: tooling files only.
REPO=$BOX/repo; git init -q "$REPO"; cd "$REPO" || exit 1
git config user.email t@example.com; git config user.name t
echo x > README.md; git add README.md; git commit -qm base
mkdir -p .claude/hooks scripts; echo a > .claude/hooks/a.sh; echo b > scripts/b.sh; git add .; git commit -qm "feat(unit-a): squash"
SHA=$(git rev-parse HEAD)
PROOF=$'Builder proof: unit-a-r4-reports.md: Codex thread(s) t-1 ended NO-GO in /w/unit-a on abc; rule: P2 tail\nOpen at merge: - [P2] A quoted path hides a discard -- .claude/hooks/a.sh:51 -- The hook passes it; screen the body.\nOpen at merge: - [P3] The help text names the old flag -- scripts/b.sh:7 -- Reword the line.'
run() { bash "$SCRIPT" "$@" >"$BOX/out" 2>&1; echo $?; }
creates() { grep -c '^issue create ' "$BOX/gh/calls" 2>/dev/null || true; }

check "two open findings are filed as two issues" "0 2" "$(run unit-a "$SHA" --area tooling <<<"$PROOF") $(creates)"
check "each carries a type label, its own level and the area it was given" "1 1" \
  "$(grep -c -- '--label bug --label P2 --label area:tooling' "$BOX/gh/calls") $(grep -c -- '--label bug --label P3 --label area:tooling' "$BOX/gh/calls")"
check "the title is the finding's" 1 "$(grep -c -- '--title A quoted path hides a discard --body' "$BOX/gh/calls")"
check "the body names the unit, the merge commit, the place, the text and the round file" "1 1 1 1 1" \
  "$(grep -c 'unit-a' "$BOX/gh/open/101" | sed 's/[1-9][0-9]*/1/') $(grep -c "$SHA" "$BOX/gh/open/101") $(grep -c '\.claude/hooks/a\.sh:51' "$BOX/gh/open/101") $(grep -c 'screen the body' "$BOX/gh/open/101") $(grep -c 'unit-a-r4-reports.md' "$BOX/gh/open/101")"
check "the numbers are printed for the merge's output" "Issues: 101 102" "$(grep '^Issues: ' "$BOX/out")"

check "a second run files nothing and names the issues that are open" "0 2 2" \
  "$(run unit-a "$SHA" <<<"$PROOF") $(creates) $(grep -c '^ALREADY OPEN #10[12]: ' "$BOX/out")"
# The key is the finding's file and title, not the unit: a later build that
# leaves the same finding open must not file it again.
check "the same finding left open by another unit files nothing" "0 2 Issues: 101 102" \
  "$(run unit-b "$SHA" <<<"${PROOF//unit-a/unit-b}") $(creates) $(grep '^Issues: ' "$BOX/out")"
check "the same title on another file is a finding of its own" "0 3" \
  "$(run unit-a "$SHA" <<<$'Open at merge: - [P2] A quoted path hides a discard -- .claude/hooks/other.sh:9 -- Same words, other file.') $(creates)"

# A finding line may end with the exact failing input or command. It is the
# same finding with or without it: the same key, and the issue shows it apart
# from the reason. A command may hold " -- " itself (git log -- <file>).
WITH=$'Open at merge: - [P2] A lock outlives its holder -- scripts/b.sh:7 -- The next run waits for ever. -- kill -9 $pid; git log -- scripts/b.sh'
check "a finding with a failing command is filed" "0 1" "$(run unit-a "$SHA" <<<"$WITH") $(grep -c -- '--title A lock outlives its holder --body' "$BOX/gh/calls")"
N=$(grep -l 'waits for ever' "$BOX"/gh/open/* | head -1)
check "the issue shows the command whole under its own heading, after the reason" "1 1 1" \
  "$(grep -c '^The next run waits for ever\.$' "$N") $(grep -c '^Failing input or command:$' "$N") $(grep -cF 'kill -9 $pid; git log -- scripts/b.sh' "$N")"
check "the place is still the second field" 1 "$(grep -c '^- Where: scripts/b\.sh:7$' "$N")"
check "the same finding without the command is the one already open, not a second issue" "0 1" \
  "$(run unit-a "$SHA" <<<$'Open at merge: - [P2] A lock outlives its holder -- scripts/b.sh:7 -- The next run waits for ever.') $(grep -c '^ALREADY OPEN #' "$BOX/out")"
check "a finding with no failing command gets no such heading" 0 "$(grep -l 'screen the body' "$BOX"/gh/open/* | xargs grep -c '^Failing input or command:$')"

rm -f "$BOX"/gh/open/* "$BOX/gh/calls"
check "a GitHub failure gives the script's own code" 4 "$(GH_FAIL=create run unit-a "$SHA" <<<"$PROOF")"
check "and one NOT FILED line per finding, each ending with the finding's key" "2 2" \
  "$(grep -c '^NOT FILED: ' "$BOX/out") $(grep -cE '^NOT FILED: .* \[pp-finding-[0-9a-f]{16}\]$' "$BOX/out")"
check "and leaves the merge commit where it was" "$SHA" "$(git rev-parse HEAD)"
: > "$BOX/gh/calls"
check "a failed lookup files nothing blind: the finding may be open already" "4 0 2" \
  "$(GH_FAIL=list run unit-a "$SHA" <<<"$PROOF") $(creates) $(grep -c '^NOT FILED: ' "$BOX/out")"
check "the same command files them once GitHub answers" "0 2" "$(run unit-a "$SHA" <<<"$PROOF") $(creates)"

rm -f "$BOX"/gh/open/* "$BOX/gh/calls"
check "a dry run files nothing and prints what it would file" "0 0 2" \
  "$(run unit-a "$SHA" --area tooling --dry-run <<<"$PROOF") $(creates) $(grep -c '^WOULD FILE (bug, P[23], area:tooling): ' "$BOX/out")"
: > "$BOX/gh/calls"
check "a proof with nothing open files nothing and asks GitHub nothing" "0 0" \
  "$(run unit-a "$SHA" <<<'Builder proof: unit-a-r4-reports.md: ended GO; rule: closing GO') $(wc -l < "$BOX/gh/calls" | tr -d ' ')"

# The area is the caller's to name: a project's folders say nothing about it.
mkdir -p src; echo c > src/c.ts; git add .; git commit -qm "feat(unit-c): squash"; SHA2=$(git rev-parse HEAD)
ONE=$'Open at merge: - [P2] The retry is not counted -- src/c.ts:3 -- Count it.'
check "an area and a milestone are passed on as given" "0 1" \
  "$(run unit-c "$SHA2" --area backend --milestone compliance <<<"$ONE") $(grep -c -- '--label bug --label P2 --label area:backend --milestone compliance' "$BOX/gh/calls")"
rm -f "$BOX"/gh/open/* "$BOX/gh/calls"
check "with no area the issue is still filed, without one, and the gap is loud" "0 1 0 1" \
  "$(run unit-c "$SHA2" <<<"$ONE") $(creates) $(grep -c 'area:' "$BOX/gh/calls") $(grep -c '^ADD AN AREA LABEL to #[0-9]*$' "$BOX/out")"
check "a merge commit this repository does not hold is a usage error" 2 "$(run unit-a 0000000000000000000000000000000000000000 <<<"$ONE")"
# No gh on the machine, no login or no GitHub remote: every call fails the same way, before anything is filed.
rm -f "$BOX"/gh/open/* "$BOX/gh/calls"
check "with no gh, no login or no remote every finding is named NOT FILED with gh's own words, and the code is 4" "4 0 2 2" \
  "$(GH_PLAN="fail fail" run unit-a "$SHA" <<<"$PROOF") $(creates) $(grep -c '^NOT FILED: ' "$BOX/out") $(grep -c 'gh: no network' "$BOX/out")"
check "and the last commit is where it was" "$SHA2" "$(git rev-parse HEAD)"
check "a call with no merge commit is a usage error" 2 "$(run unit-a <<<"$PROOF")"

# The merge's own step: sliced out of merge-unit-local.sh and run with the
# variables the merge has at that point.
awk '/^file_open_findings\(\) \{/ { on = 1 } on { print } on && /^\}/ { exit }' "$HERE/merge-unit-local.sh" > "$BOX/step.sh"
rm -f "$BOX"/gh/open/* "$BOX/gh/calls"
step() { ( UNIT=unit-a BUILDER_PROOF=$PROOF MERGE_OPEN=2 AREA="" MILESTONE="" MERGE_ISSUES="" NOT_FILED=""
           . "$BOX/step.sh"; file_open_findings "$SHA" "$@"; echo "rc=$? issues=$MERGE_ISSUES notfiled=$(grep -c . <<<"$NOT_FILED")" ) 2>&1 | tail -1; }
check "the merge's step hands the issue numbers on for the ledger row" "rc=0 issues=101 102 notfiled=0" "$(step)"
rm -f "$BOX"/gh/open/*
check "a GitHub failure there does not stop the merge: the step returns and keeps the lines for the end" "rc=0 issues= notfiled=2" "$(GH_FAIL=create step)"
# A filing script that dies says nothing itself: every finding it did not account for is still owed.
check "a filing script killed half way leaves every finding it did not account for named as not filed" "rc=0 issues= notfiled=2" "$(GH_FAIL=kill step)"
rm -f "$BOX"/gh/open/*; echo 'exit 0' > "$BOX/file-open-findings.sh"
check "and so does one that ends clean having said nothing" "rc=0 issues= notfiled=2" "$(HERE=$BOX step)"
check "the lines kept for the end name each finding" 1 "$(HERE=$BOX step >/dev/null; ( UNIT=unit-a BUILDER_PROOF=$PROOF MERGE_OPEN=2 AREA="" MILESTONE="" HERE=$BOX; . "$BOX/step.sh"; file_open_findings "$SHA" >/dev/null; grep -c '^NOT FILED: - \[P3\] The help text names the old flag' <<<"$NOT_FILED" ))"
# Any ending but a clean one earns the retry command, which the merge prints with the lines kept for the end.
cat > "$BOX/file-open-findings.sh" <<'EOF'
sed -n 's/^Open at merge: //p' | { read -r A; read -r B; echo "KEY k1: $A"; echo "KEY k2: $B"; }
echo "FILED #7: a [k1]"; echo "FILED #8: b [k2]"; exit 9
EOF
check "a filing script that answered every finding and still ended badly keeps one line for the end, and the numbers it gave" "rc=0 issues=7 8 notfiled=1" "$(HERE=$BOX step)"
# The script answers each finding as it goes and the merge matches the answers to the findings by
# key. Killed part way, it owes exactly what it did not file: the first finding, whose lookup failed,
# and the third, never reached. The second was filed and is not named.
THREE=$PROOF$'\nOpen at merge: - [P3] A third finding is never reached -- scripts/b.sh:2 -- Reach it.'
rm -f "$BOX"/gh/open/*; : > "$BOX/gh/calls"
KILLED=$( ( UNIT=unit-a BUILDER_PROOF=$THREE MERGE_OPEN=3 AREA="" MILESTONE="" MERGE_ISSUES="" NOT_FILED=""; export GH_PLAN="fail ok ok kill"
            . "$BOX/step.sh"; file_open_findings "$SHA"; echo "$NOT_FILED"; echo "issues=$MERGE_ISSUES" ) 2>/dev/null )
check "a filing script killed after a failed lookup and a filed issue: the merge names the failed finding and the one never reached" "1 1 2" \
  "$(grep -c '^NOT FILED: - \[P2\] A quoted path hides a discard' <<<"$KILLED") $(grep -c '^NOT FILED: - \[P3\] A third finding is never reached' <<<"$KILLED") $(grep -c '^NOT FILED: ' <<<"$KILLED")"
check "and not the finding that was filed, whose issue number is still handed on" "0 issues=101" \
  "$(grep -c '^NOT FILED: .*The help text names the old flag' <<<"$KILLED") $(grep '^issues=' <<<"$KILLED")"
# The script can die while it is still naming keys. A finding it never named, or named half a line of, is
# owed like one it named and never reached: the merge counts against the proof's own list.
mkdir -p "$BOX/part"
printf '%s\n' '#!/usr/bin/env bash' 'sed -n "s/^Open at merge: /KEY pp-finding-0000000000000000: /p" | sed -n "1p; 2s/ -- .*//p"; exit 137' > "$BOX/part/file-open-findings.sh"
PART=$( ( UNIT=unit-a BUILDER_PROOF=$THREE MERGE_OPEN=3 AREA="" MILESTONE="" MERGE_ISSUES="" NOT_FILED=""
          . "$BOX/step.sh"; HERE=$BOX/part; file_open_findings "$SHA"; echo "$NOT_FILED" ) 2>/dev/null )
check "a filing script killed while naming its keys: every finding in the proof is named as not filed, once" "1 1 1 3" \
  "$(grep -c '^NOT FILED: - \[P2\] A quoted path hides a discard' <<<"$PART") $(grep -c '^NOT FILED: .*The help text names the old flag.* -- ' <<<"$PART") $(grep -c '^NOT FILED: - \[P3\] A third finding is never reached' <<<"$PART") $(grep -c '^NOT FILED: ' <<<"$PART")"
check "the merge's help names the two options" 2 "$(bash "$HERE/merge-unit-local.sh" --help | grep -cE '^  --(area|milestone) ')"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

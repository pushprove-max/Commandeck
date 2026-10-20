#!/usr/bin/env bash
# red-proof.sh is a Builder's way to show a test red without editing its tree, so a RED must mean "this test
# catches this break" and nothing else. What this pins: a test that still passes with the break says NOT RED
# (exit 1), never RED; a test red without the break proves nothing (exit 2); the proof runs on the Builder's
# uncommitted work (changed and untracked files), or it proves the wrong code; the break never lands outside
# the scratch copy; the checkout comes out untouched, with no scratch worktree left behind; and the guards let
# the call through.
set -u
REAL=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT=$REAL/scripts/red-proof.sh
BOX=$(cd "$(mktemp -d)" && pwd -P)
REPO=$BOX/repo
trap 'git -C "$REPO" worktree prune >/dev/null 2>&1; rm -rf "$BOX"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }
mkdir -p "$REPO" && cd "$REPO" || exit 1
git init -q . && git config user.email t@t && git config user.name t
printf '# limit helper\nlimit() { echo 0; }\n' > lib.sh
# An installed dependency (ignored, linked into the scratch copy) and a tracked link out of the checkout.
mkdir -p node_modules/pkg && echo orig > node_modules/pkg/README.md && echo 'node_modules/' > .gitignore
echo outside > "$BOX/outside.txt" && ln -s "$BOX/outside.txt" link.txt
git add lib.sh .gitignore link.txt && git commit -qm base
# Uncommitted fix and an untracked test: HEAD alone would be red, so a green baseline proves both reached the scratch copy.
printf '# limit helper\nlimit() { echo 5; }\n' > lib.sh
printf '. ./lib.sh\n[ "$(limit)" = 5 ]\n' > t.sh
run() { TMPDIR=$BOX bash "$SCRIPT" "$@" 2>&1; }

out=$(run lib.sh 2 'limit() { echo 6; }' -- bash t.sh); rc=$?
check "a test that catches the break is RED (exit 0)" "0 1" "$rc $(grep -c 'RED: the test passes as is and fails' <<<"$out")"
out=$(run lib.sh 1 '# renamed comment' -- bash t.sh); rc=$?
check "a test that passes with the break is NOT RED (exit 1)" "1 1" "$rc $(grep -c 'NOT RED' <<<"$out")"
out=$(run lib.sh 2 'limit() { echo 6; }' -- bash -c 'exit 3'); rc=$?
check "a test red without the break is no proof (exit 2)" "2 1" "$rc $(grep -c 'NO PROOF' <<<"$out")"
out=$(run lib.sh 1 'x\y' -- bash -c '! grep -qF "x\\y" lib.sh'); rc=$?
check "the replacement lands byte for byte, backslashes kept" "0 1" "$rc $(grep -c 'RED: the test passes as is and fails' <<<"$out")"
out=$(run lib.sh 9 'x' -- bash t.sh); rc=$?
check "a line the file does not have is refused" "2 1" "$rc $(grep -c 'has no line 9' <<<"$out")"
out=$(run lib.sh 2 'limit() { echo 5; }' -- bash t.sh); rc=$?
check "a replacement equal to the line is refused: nothing breaks" "2 1" "$rc $(grep -c 'nothing breaks' <<<"$out")"
out=$(run lib.sh 2 'x' bash t.sh); rc=$?
check "no -- before the test command is a usage error" 2 "$rc"
# A RED must come from the break alone. Each run gets its own fresh copy, so a file the first run leaves in the copy
# cannot fail the second; state outside the copy is shared, so the unbroken test runs once more after the break.
out=$(run lib.sh 1 '# renamed comment' -- bash -c 'test ! -e .once && touch .once'); rc=$?
check "a file the first run leaves in its copy does not turn the second run red" "1 1" "$rc $(grep -c 'NOT RED' <<<"$out")"
out=$(run lib.sh 1 '# renamed comment' -- bash -c "test ! -e '$BOX/once' && touch '$BOX/once'"); rc=$?
check "a test that cannot pass twice, through state outside the copy, is no proof" "2 1" "$rc $(grep -c 'NO PROOF' <<<"$out")"
# The break is written only inside the scratch copy: never through its link to this checkout's dependencies, or
# through a tracked link, to a file the Builder's checkout and every other worktree read.
out=$(run node_modules/pkg/README.md 1 PROBE -- bash -c '! grep -qx PROBE node_modules/pkg/README.md'); rc=$?
check "an installed dependency is refused and left as it was" "2 orig" "$rc $(cat node_modules/pkg/README.md)"
out=$(run link.txt 1 PROBE -- bash -c '! grep -qx PROBE link.txt'); rc=$?
check "a tracked link out of the copy is refused and its target left as it was" "2 outside" "$rc $(cat "$BOX/outside.txt")"
# Issue 246: a whole run of a test file that can run one case reruns every case three times for one proof. A file
# that reads a *_TEST_CASE variable is refused unless the call sets it, and the refusal names it.
printf '# CA_TEST_CASE=<text> runs one case.\n. ./lib.sh\n: "${CA_TEST_CASE-}"\n[ "$(limit)" = 5 ]\n' > ca.test.sh
out=$(run lib.sh 2 'limit() { echo 6; }' -- bash ca.test.sh); rc=$?
check "a whole run of a case-aware test file is refused, naming its variable" "2 1" "$rc $(grep -c 'CA_TEST_CASE' <<<"$out")"
out=$(CA_TEST_CASE=limit run lib.sh 2 'limit() { echo 6; }' -- bash ca.test.sh); rc=$?
out2=$(run lib.sh 2 'limit() { echo 6; }' -- env CA_TEST_CASE=limit bash ca.test.sh); rc2=$?
check "with the variable set, in the environment or the command, the proof runs" "0 0" "$rc $rc2"
# Only the header says a file is case-aware: a variable named in its body (this file's own fixtures) is not a selector.
printf '#!/usr/bin/env bash\n# A plain test.\n. ./lib.sh\n: CB_TEST_CASE\n[ "$(limit)" = 5 ]\n' > body.test.sh
out=$(run lib.sh 2 'limit() { echo 6; }' -- bash body.test.sh); rc=$?
check "a *_TEST_CASE name in a test's body, not its header, does not refuse the whole run" 0 "$rc"
# --batch runs many proofs in one scratch worktree; each test records how many worktrees it sees (this one and the copy).
printf '%s\t%s\t%s\t%s\n' lib.sh 2 'limit() { echo 6; }' "git worktree list | wc -l >> '$BOX/wts'; bash t.sh" \
  lib.sh 2 'limit() { echo 7; }' "git worktree list | wc -l >> '$BOX/wts'; bash t.sh" > "$BOX/batch.tsv"
out=$(run --batch "$BOX/batch.tsv"); rc=$?
check "a batch of two proofs reports both RED from one scratch worktree" "0 2 2" \
  "$rc $(grep -c 'RED: the test passes as is and fails' <<<"$out") $(sort -u "$BOX/wts" | tr -d ' ' | paste -sd' ' -)"
printf '%s\t%s\t%s\t%s\n' lib.sh 2 'limit() { echo 6; }' 'bash t.sh' lib.sh 1 '# renamed comment' 'bash t.sh' > "$BOX/batch.tsv"
out=$(run --batch "$BOX/batch.tsv"); rc=$?
check "a batch with one proof NOT RED exits 1, and the file is restored between proofs" "1 1 1" \
  "$rc $(grep -c 'NOT RED' <<<"$out") $(grep -c 'RED: the test passes as is and fails' <<<"$out")"
# A test that reads stdin must not eat the rows after it: the second proof below is NOT RED, so the batch exits 1.
printf '%s\t%s\t%s\t%s\n' lib.sh 2 'limit() { echo 6; }' 'cat >/dev/null; bash t.sh' lib.sh 1 '# renamed comment' 'bash t.sh' > "$BOX/batch.tsv"
out=$(run --batch "$BOX/batch.tsv"); rc=$?
check "a test that reads stdin does not swallow the batch's later proofs" "1 1" "$rc $(grep -c 'NOT RED' <<<"$out")"
# An empty replacement (blank the line) keeps its column: the test runs, and blanking line 2 breaks it.
printf '%s\t%s\t%s\t%s\n' lib.sh 2 '' 'bash t.sh' > "$BOX/batch.tsv"
out=$(run --batch "$BOX/batch.tsv"); rc=$?
check "an empty replacement in a batch blanks the line and proves RED" "0 1" "$rc $(grep -c 'RED: the test passes as is and fails' <<<"$out")"
check "the checkout's file is untouched" "limit() { echo 5; }" "$(sed -n 2p lib.sh)"
check "no scratch worktree is left behind" 1 "$(git worktree list | wc -l | tr -d ' ')"
check "no scratch folder is left behind" 0 "$(find "$BOX" -maxdepth 1 -name 'red-proof.*' | wc -l | tr -d ' ')"

# The call must pass the Bash guards, or the Builder is back to breaking its own tree by hand.
hook() { jq -cn --arg c "$2" '{tool_name:"Bash",tool_input:{command:$c}}' | bash "$REAL/hooks/$1" >/dev/null 2>&1; echo $?; }
check "the guards let a red-proof.sh call through" "0 0" \
  "$(hook bash-guardrails.sh "bash scripts/red-proof.sh hooks/no-poll-loops.sh 40 'exit 1' -- bash hooks/__tests__/no-poll-loops.test.sh") $(hook git-safety.sh "bash scripts/red-proof.sh hooks/no-poll-loops.sh 40 'exit 1' -- bash hooks/__tests__/no-poll-loops.test.sh")"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

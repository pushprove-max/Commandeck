#!/usr/bin/env bash
# test-inputs.test.sh (host issue 336): a closing run cites a test file as unchanged only when nothing it reads has
# changed since the commit it passed at; where coverage is uncertain the file reads changed, so it runs.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
SEL=$REAL/scripts/test-inputs.sh
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cd "$TMP" && git init -q . && git config user.email t@t && git config user.name t
mkdir -p scripts/__tests__ hooks
echo '# lib' > scripts/paths.sh
printf '%s\n' '. "$(dirname "$0")/paths.sh"' > scripts/read-verdict.sh
echo 'bash scripts/read-verdict.sh' > scripts/__tests__/read-verdict.test.sh
echo 'echo other' > scripts/other.sh
echo 'bash scripts/other.sh' > scripts/__tests__/other.test.sh
printf '%s\n' 'f=$1' '. "$f"' > scripts/dyn.sh
echo 'bash scripts/dyn.sh' > scripts/__tests__/dyn.test.sh
git add -A && git commit -qm base
BASE=$(git rev-parse HEAD)
RV=scripts/__tests__/read-verdict.test.sh OT=scripts/__tests__/other.test.sh DY=scripts/__tests__/dyn.test.sh
edit() { echo "# $RANDOM" >> "$1"; git commit -qam "edit $1"; }
status() { bash "$SEL" "$BASE" "$@" | paste -sd" " -; }

echo '# docs only' > README.md; git add -A; git commit -qm docs
check "after a commit that changes no input, the files are unchanged" "unchanged $RV unchanged $OT" "$(status $RV $OT)"
edit scripts/other.sh
check "a change to a script the file names makes it changed, and only that file" "unchanged $RV changed $OT" "$(status $RV $OT)"
git reset -q --hard "$BASE"; git commit -q --allow-empty -m same
edit scripts/paths.sh
check "a change to paths.sh alone makes read-verdict.test.sh changed (it names read-verdict.sh, which sources paths.sh)" \
  "changed $RV unchanged $OT" "$(status $RV $OT)"
git reset -q --hard "$BASE"
check "a source line with no literal basename makes the file changed even with nothing edited" "changed $DY" "$(status $DY)"
check "a file missing from the tree reads changed" "changed scripts/__tests__/gone.test.sh" "$(status scripts/__tests__/gone.test.sh)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

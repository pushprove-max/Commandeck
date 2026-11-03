#!/usr/bin/env bash
# A ratchet baseline only ratchets if nobody raises it in the same diff as the
# code that needed the room. baseline-raise-check.sh names every loosened limit
# so merge-unit-local.sh can refuse it; lowering a limit is the ratchet working
# and must pass, and a file outside the watched list is not a limit.
#   1. a raised `CAP=` in file-size-cop.sh fails; lowered passes;
#   2. an unlisted baseline raised passes;
#   3. an unknown base ref fails loud.
set -euo pipefail
SOURCE=$(git rev-parse --show-toplevel)
SCRIPT=$SOURCE/scripts/baseline-raise-check.sh
TMP=$(mktemp -d /tmp/baseline-raise-check.XXXXXX); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
R=$TMP/repo
g() { git -C "$R" -c user.name=t -c user.email=t@t -c core.hooksPath=/dev/null "$@"; }
git init -q -b main "$R"
mkdir -p "$R/scripts" "$R/hooks"
printf '    *.tsx) CAP=400; RULE=a ;;\n    *.ts)  CAP=500; RULE=b ;;\n' > "$R/hooks/file-size-cop.sh"
printf '{"n":1}\n' > "$R/scripts/other-baseline.json"
g add -A && g commit -q -m base

# case <name> <file> <sed expression> <want exit> [<want output line>]
case_() {
  g checkout -q main && { g branch -q -D probe 2>/dev/null || true; } && g checkout -q -b probe
  sed -i.bak -e "$3" "$R/$2" && rm -f "$R/$2.bak" && g commit -q -am "$1"
  local out code=0
  out=$(cd "$R" && bash "$SCRIPT" main) || code=$?
  [ "$code" = "$4" ] || fail "$1: exit $code, want $4; output: $out"
  [ -z "${5:-}" ] || grep -qF -- "$5" <<<"$out" || fail "$1: output lacks '$5': $out"
  [ "$4" = 1 ] || [ -z "$out" ] || fail "$1: a passing check printed: $out"
}
# A raised cap is a loosened ratchet: the second CAP is named by its position.
case_ "CAP raised" hooks/file-size-cop.sh 's/CAP=500/CAP=600/' 1 'CAP #2: 500 -> 600'
# Lowering a cap is the ratchet working and must not need a reason.
case_ "CAP lowered" hooks/file-size-cop.sh 's/CAP=400/CAP=300/' 0
# A file outside the watched list is not a limit; flagging it would block every merge.
case_ "unlisted raised" scripts/other-baseline.json 's/"n":1/"n":9/' 0
# An unreadable ref must not read as "nothing loosened".
(cd "$R" && bash "$SCRIPT" no-such-ref >/dev/null 2>&1) && fail "an unknown base ref passed"
echo "PASS: a raised file-size cap is named and fails; lowering it and unlisted files pass"

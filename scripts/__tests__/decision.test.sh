#!/usr/bin/env bash
# decision.test.sh -- decision.sh add --options (issue 240): a decision keeps the 2 to 4 answers its picker offered,
# so the dashboard's "Needs me" panel can offer them as buttons. What this pins: 2 to 4 options are stored in
# order; one, five, or an empty one is refused and writes nothing; a row added without --options has no options
# key, as every row written before this release, and the ledger still reads; --options goes beside --waits-on.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
git init -q -b main "$T/p"
D() { (cd "$T/p" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" COMMANDECK_MAIN="$T/p" COMMANDECK_RULING_LOG="$T/rulings.jsonl" bash "$REAL/scripts/decision.sh" "$@"); }
opts() { D list | jq -c --arg id "$1" '[.[] | select(.id == $id)] | if length == 0 then "none" else .[0].options end'; }

D add ship-1999-01-01 'Ship the release today?' yes main --options 'yes|no|later' >/dev/null
check "2 to 4 options are stored in order" '["yes","no","later"]' "$(opts ship-1999-01-01)"
D add four-1999-01-01 'Which colour for the banner?' red main --options 'red|green|blue|grey' >/dev/null
check "four options are the most stored" '["red","green","blue","grey"]' "$(opts four-1999-01-01)"
D add five-1999-01-01 'Which port for the proxy?' 80 main --options '80|81|82|83|84' 2>/dev/null
check "five options are refused, and nothing is written" '1 "none"' "$? $(opts five-1999-01-01)"
D add one-1999-01-01 'Rename the service account?' yes main --options 'yes' 2>/dev/null
check "one option is refused" '1 "none"' "$? $(opts one-1999-01-01)"
D add gap-1999-01-01 'Rotate the signing key?' yes main --options 'yes||no' 2>/dev/null
check "an empty option is refused" '1 "none"' "$? $(opts gap-1999-01-01)"
D add plain-1999-01-01 'Move the nightly job?' none main >/dev/null
check "a row added without --options has none, and the ledger still reads" 'null' "$(opts plain-1999-01-01)"
D add u1-msg_q1 'question (u1): which lock?' none 'u1 asks' --waits-on main --options 'flock|lockf' >/dev/null
check "--options goes beside --waits-on" '["flock","lockf"]' "$(opts u1-msg_q1)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

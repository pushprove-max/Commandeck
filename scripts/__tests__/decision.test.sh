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
# Issue 292: the host project's form, a JSON array, under its rules: it stores the same row as the a|b form, and five
# answers, a non-printable one or the picker's decoy are refused.
D add json-1999-01-01 'Ship the hotfix now?' yes main --options '["yes","no"]' >/dev/null
check "issue 292: a JSON array stores the same options as a|b" '["yes","no"]' "$(opts json-1999-01-01)"
D add jfive-1999-01-01 'Which retry count?' 1 main --options '["1","2","3","4","5"]' 2>/dev/null
check "issue 292: a 5-item array is refused, and nothing is written" '1 "none"' "$? $(opts jfive-1999-01-01)"
D add jdecoy-1999-01-01 'Merge the branch?' yes main --options "$(. "$REAL/hooks/lib/ask-decoy.sh" && jq -cn --arg d "$ASK_DECOY" '[$d, "yes"]')" 2>/dev/null
check "issue 292: the picker decoy is refused" '1 "none"' "$? $(opts jdecoy-1999-01-01)"
D add jctl-1999-01-01 'Close the incident?' yes main --options '["yes","no\u0007"]' 2>/dev/null
check "issue 292: a non-printable answer is refused" '1 "none"' "$? $(opts jctl-1999-01-01)"
# The picker hook joins labels with |: a first label that starts with [ is still that form, not a JSON array.
D add jpipe-1999-01-01 'Choose a mode?' '[auto]' main --options '[auto]|manual' >/dev/null
check "issue 292: a|b whose first label starts with [ is still split by |" '["[auto]","manual"]' "$(opts jpipe-1999-01-01)"

# Issue 259: push-ask prepares the owner's push request and never pushes. It lists main's commits since origin/main,
# each with its unit and that merge's check from the finished-builds row; nothing to push, or a listed merge whose
# check is not green, writes no row.
git init -q --bare "$T/origin.git"; git -C "$T/p" remote add origin "$T/origin.git"
git -C "$T/p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base; git -C "$T/p" push -q origin main
pushes() { D list | jq '[.[] | select(.id | startswith("push-"))] | length'; }
D push-ask >/dev/null 2>&1
check "nothing to push: refused, no row" "1 0" "$? $(pushes)"
git -C "$T/p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m 'feat(u1): one'; S1=$(git -C "$T/p" rev-parse HEAD)
B=$T/home/.commandeck/builds/p.jsonl; mkdir -p "${B%/*}"
jq -cn --arg m "$T/p" --arg s "$S1" '{main: $m, unit: "u1", how: "merged", at: "1999-01-01T00:00:00Z", sha: $s}' > "$B"
OUT=$(D push-ask); RC=$?
check "one merged unit ahead of origin/main: one open row naming its sha, unit and green check" "0 1 1" \
  "$RC $(pushes) $(D list | jq '[.[] | select(.id | startswith("push-")) | select(.question | contains("'"${S1:0:8}"' u1 (check green)")) | select(.answeredAt == null)] | length')"
check "and nothing was pushed" "$(git -C "$T/p" rev-parse HEAD~1)" "$(git -C "$T/origin.git" rev-parse main)"
git -C "$T/p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m 'feat(u2): two'; S2=$(git -C "$T/p" rev-parse HEAD)
jq -cn --arg m "$T/p" --arg s "$S2" '{main: $m, unit: "u2", how: "merged", at: "1999-01-01T00:00:00Z", sha: $s, check: "red"}' >> "$B"
D push-ask >/dev/null 2>&1
check "a listed merge whose check is not green: refused, no new row" "1 1" "$? $(pushes)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

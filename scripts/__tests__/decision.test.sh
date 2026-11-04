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
# The stand-in to-main.sh (issue 624): every message an answer sends main lands in tm.log, never in a live Orca.
printf '#!/usr/bin/env bash\nprintf "%%s|%%s|%%s\\n" "$1" "$2" "$3" >> "%s/tm.log"\n' "$T" > "$T/tm"; chmod +x "$T/tm"
export COMMANDECK_TO_MAIN=$T/tm
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

# Issue 309: a ruling logged under the other spelling of main (/tmp against /private/tmp) is the same checkout. The
# project is given by a link; the voided decoy pick is logged under the folder the link points to.
ln -s "$T/p" "$T/plink"
DL() { (cd "$T/p" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" COMMANDECK_MAIN="$T/plink" COMMANDECK_RULING_LOG="$T/rulings-link.jsonl" bash "$REAL/scripts/decision.sh" "$@"); }
DL add decoyp-1999-01-01 'Ship the linked release?' yes main >/dev/null
jq -cn --arg c "$T/p" '{source: "ask", question: "Ship the linked release?", utc: "2999-01-01T00:00:00Z", cwd: $c, void: true}' > "$T/rulings-link.jsonl"
DL add decoyp-1999-01-01 'Ship the linked release?' yes main >/dev/null 2>&1
check "a decoy retry logged under the symlinked spelling of main is found" 0 "$?"
DL add decoys-1999-01-01 'Ship the sub release?' yes main >/dev/null
jq -cn --arg c "$T/p/sub" '{source: "ask", question: "Ship the sub release?", utc: "2999-01-01T00:00:00Z", cwd: $c, void: true}' >> "$T/rulings-link.jsonl"
DL add decoys-1999-01-01 'Ship the sub release?' yes main >/dev/null 2>&1
check "and one logged from a folder inside main is found too" 0 "$?"

# Issue 477: `rulings <term>...` lists the owner's earlier picks for a plan author to read before it asks. Only a real
# pick counts: a voided row, the picker decoy, and a typed prompt (source not "ask") are left out; newest first.
DECOY=$(bash -c '. "$1/hooks/lib/ask-decoy.sh"; printf %s "$ASK_DECOY"' _ "$REAL")
{ jq -cn '{source: "ask", id: "old-1999-01-01", et: "01-01 09:00", utc: "1999-01-01T09:00:00Z", question: "Which Cache layer?", answer: "redis"}'
  jq -cn '{source: "ask", id: "new-1999-01-03", et: "01-03 09:00", utc: "1999-01-03T09:00:00Z", question: "Keep the cache?", answer: "yes"}'
  jq -cn '{source: "ask", id: "void-1999-01-02", et: "01-02 09:00", utc: "1999-01-02T09:00:00Z", question: "Drop the cache?", answer: "no", void: true}'
  jq -cn --arg d "$DECOY" '{source: "ask", id: "decoy-1999-01-02", et: "01-02 10:00", utc: "1999-01-02T10:00:00Z", question: "Flush the cache?", answer: $d}'
  jq -cn '{source: "prompt", id: "typed-1999-01-02", et: "01-02 11:00", utc: "1999-01-02T11:00:00Z", question: "cache", answer: "typed words"}'
  jq -cn '{source: "ask", id: "other-1999-01-04", et: "01-04 09:00", utc: "1999-01-04T09:00:00Z", question: "Which port?", answer: "80"}'; } > "$T/rulings.jsonl"
DR=$(D rulings cache 2>&1); RC=$?
check "the digest lists real picks only (issue 477)" "0|new-1999-01-03 01-03 09:00: Keep the cache? -> yes
old-1999-01-01 01-01 09:00: Which Cache layer? -> redis" "$RC|$DR"
check "a term matching no row prints nothing and exits 0; no term is a usage error (issue 477)" "0|| 1" "$(D rulings zebra >/dev/null 2>&1; echo $?)|$(D rulings zebra 2>&1)| $(D rulings >/dev/null 2>&1; echo $?)"

# Issue 512. Catches: a user running scripts/decision.sh by its path gets a permission error (mode 100644).
check "decision.sh is tracked executable" yes "$([ -x "$REAL/scripts/decision.sh" ] && echo yes || echo no)"
# Issue 515. Catches: a spec or template word no seat can run: no seat has the scripts folder on its PATH.
SPEC=$(grep -o 'bash $PP_SCRIPTS_Q/decision\.sh rulings' "$REAL/scripts/seat.sh" | head -1)
OUT=$(cd "$T/p" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" COMMANDECK_MAIN="$T/p" COMMANDECK_RULING_LOG="$T/rulings.jsonl" \
  bash -c "${SPEC/\$PP_SCRIPTS_Q/$(printf '%q' "$REAL/scripts")} cache" 2>&1)
check "the spec's decision.sh command runs" "$DR|0" \
  "$OUT|$(cat "$REAL/scripts/seat.sh" "$REAL/hooks/ask-stop-records-decision.sh" | grep -v '^ *#' | grep -cE '(`|run )(decision|plan-check)\.sh ')"
# Issue 522: holds takes a decision as the unit's by its id in the exact shapes the plugin writes, not by a sibling's.
# Catches: a plan-<unit> question the merge and the closing pass miss because the id's dash hides the unit name.
D add plan-hz 'Which lock?' none main >/dev/null
D add review-stop-hz-r2 'Stop the review?' none main >/dev/null
check "holds lists a plan-<unit> question" "Open question to the owner plan-hz: Which lock?
Open question to the owner review-stop-hz-r2: Stop the review?" "$(D holds hz | sort)"
# Catches: a sibling unit's ask (review-stop-<unit>-b-r7, plan-<unit>-b, <unit>-aa-q1, x<unit>) held against this unit.
D add review-stop-hy-b-r7 'Stop the second review?' none main >/dev/null
D add plan-hy-b 'Pick a database engine?' none main >/dev/null
D add hy-aa-q1 'Rename the staging bucket?' none main >/dev/null
D add xhy 'Rotate the signing certificate?' none main >/dev/null
check "holds ignores a sibling's review stop" "|2" "$(D holds hy)|$(D holds hy-b | grep -c .)"

# D13: a push question lists every unit it carries; it must not hold a unit's closing pass or merge.
# Catches: a push question freezing a closing pass. An id match and a question from another source still hold.
# The push row the push-ask cases above wrote lists u1 in its question; u1-msg_q1 (source "u1 asks") names u1 as well.
check "holds ignores an open push question listing the unit" "1 0" \
  "$(D list | jq '[.[] | select(.source == "decision.sh push-ask" and (.question | contains(" u1 (check")) and .answeredAt == null)] | length') $(D holds u1 | grep -c 'Push main to origin')"
check "holds still lists a unit question from another source" 1 "$(D holds u1 | grep -c 'Open question to the owner u1-msg_q1')"

# Issue 569: decision.sh answer sends the answer to the asking pane after the row closes, and names the result on stderr. The
# stub answer-worker records its arguments and exits as $T/aw-* say; a unit's Builder is its workspace folder.
mkdir -p "$T/ws/u1"
cat > "$T/aw" <<EOF
#!/usr/bin/env bash
printf '%s|' "\$@" >> "$T/aw.log"; echo >> "$T/aw.log"
echo "stdout noise from the worker"
[ ! -e "$T/aw-queued" ] || { echo "queued: \$3 to \$1" >&2; exit 1; }
[ ! -e "$T/aw-fail" ] || { echo "answer-worker: pane gone" >&2; exit 1; }
EOF
chmod +x "$T/aw"
DW() { (cd "$T/p" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" COMMANDECK_MAIN="$T/p" COMMANDECK_RULING_LOG="$T/rulings.jsonl" COMMANDECK_WORKSPACES="$T/ws" COMMANDECK_ANSWER_WORKER="$T/aw" "$@" 2>"$T/err"); }
DA() { DW bash "$REAL/scripts/decision.sh" "$@"; }
: > "$T/aw.log"
D add u1-msg_s1 'question (u1): which lock?' none 'u1 asks' >/dev/null
OUT=$(DA answer u1-msg_s1 'use flock'); RC=$?
check "an answer to a unit's ask is sent to that unit once" "0 1 u1|use flock|u1-msg_s1| delivered: u1-msg_s1 to u1 1" \
  "$RC $(grep -c . "$T/aw.log") $(head -1 "$T/aw.log") $(cat "$T/err") $(jq -s 'length' <<<"$OUT")"
D add h1 'which one?' none 'ask via term_ab12cd' >/dev/null
DA answer h1 'second' >/dev/null
check "an answer to a row naming a terminal handle is sent to that handle" "term_ab12cd|second|h1|" "$(tail -1 "$T/aw.log")"
touch "$T/aw-fail"; D add u1-msg_s2 'Rotate the signing keys?' none 'u1 asks' >/dev/null
DA answer u1-msg_s2 'x' >/dev/null; RC=$?
check "an answer that cannot be delivered is named on stderr and stays recorded" "0 1 x" \
  "$RC $(grep -c '^not delivered: u1-msg_s2' "$T/err") $(D list | jq -r '.[] | select(.id == "u1-msg_s2") | .answer')"
rm -f "$T/aw-fail"; : > "$T/aw.log"
D add nowhere 'Archive the old logs?' none 'somebody else' >/dev/null; D add mine 'Upgrade the database?' none main >/dev/null
DA answer nowhere 'a' >/dev/null; N1=$(grep -c '^not delivered: nowhere' "$T/err")
DA answer mine 'a' >/dev/null; N2=$(grep -c . "$T/err")
check "an answer to a row whose source names no unit or handle is named not delivered, and one to main's own row is not" "1 0 0" "$N1 $N2 $(grep -c . "$T/aw.log")"
D add u1-msg_s3 'Mirror the vendored tarballs offsite?' none 'u1 asks' >/dev/null
DW env COMMANDECK_NO_DELIVER=1 bash "$REAL/scripts/decision.sh" answer u1-msg_s3 'closed by worker' >/dev/null
check "an answer closed by answer-worker is not sent again" "0 0" "$(grep -c . "$T/aw.log") $(grep -c . "$T/err")"
touch "$T/aw-queued"; D add u1-msg_s4 'Enable the nightly backup?' none 'u1 asks' >/dev/null
DA answer u1-msg_s4 'later' >/dev/null; RC=$?
check "an answer to a unit whose Builder is not running is named queued, not undelivered" "0 queued: u1-msg_s4 to u1" "$RC $(cat "$T/err")"
rm -f "$T/aw-queued"
D add u1-msg_s5 'Prune the stale branches?' none 'u1 asks' >/dev/null
DW env COMMANDECK_NO_DELIVER=1 bash "$REAL/scripts/decision.sh" answer u1-msg_s5 'x' >/dev/null; : > "$T/aw.log"
DA deliver u1-msg_s5 'x (ruling r)' >/dev/null
check "deliver sends the text of an answered row" "u1|x (ruling r)|u1-msg_s5| delivered: u1-msg_s5 to u1" "$(head -1 "$T/aw.log") $(cat "$T/err")"
# (pass 9, the owner's answer) Catches: a send cut at its deadline named not delivered, which main resends,
# though the worker may have sent it already. The stub timeout runs the worker, then exits 124 as a deadline does.
mkdir -p "$T/tbin"; printf '#!/usr/bin/env bash\nshift; "$@"; exit 124\n' > "$T/tbin/timeout"; chmod +x "$T/tbin/timeout"; cp "$T/tbin/timeout" "$T/tbin/gtimeout"
D add u1-msg_s6 'Rebuild the search index?' none 'u1 asks' >/dev/null; : > "$T/aw.log"
DW env PATH="$T/tbin:$PATH" bash "$REAL/scripts/decision.sh" answer u1-msg_s6 'yes' >/dev/null; RC=$?
check "a send cut at its deadline reads unknown, check the pane before resending, never not delivered" \
  "0 1 unknown: u1-msg_s6 to u1 timed out; check the unit's pane before resending" "$RC $(grep -c . "$T/aw.log") $(cat "$T/err")"
# (pass 9) Catches: answer-worker's own acknowledgement deadline (no timeout on PATH, so decision.sh waits it out) read as
# not delivered, though the answer sits unread in the unit's inbox.
printf '#!/usr/bin/env bash\necho "answer-worker: NOT acknowledged: the answer (tag t1) is still unread in $1'"'"'s inbox after 600s" >&2; exit 1\n' > "$T/aw2"; chmod +x "$T/aw2"
D add u1-msg_s7 'Vacuum the database tonight?' none 'u1 asks' >/dev/null
DW env COMMANDECK_ANSWER_WORKER="$T/aw2" bash "$REAL/scripts/decision.sh" answer u1-msg_s7 'yes' >/dev/null; RC=$?
check "an answer the unit has not acknowledged reads unknown, check the pane before resending, never not delivered" \
  "0 unknown: u1-msg_s7 to u1 not acknowledged; check the unit's pane before resending" "$RC $(cat "$T/err")"

# Issue 574: test-edit writes main's approval line once, for a logged ruling id.
RID=r-19991017-111111-p-d4e5f6
printf '%s\n' '{"id":"'$RID'","source":"prompt","answer":"yes"}' '{"id":"r-19991017-121212-p-0a0b0c","void":true,"source":"prompt"}' > "$T/rulings.jsonl"
F=$T/p/.claude/briefs/u1-main-rulings.md
D test-edit u1 scripts/__tests__/x.test.sh 'a case' $RID >/dev/null; RC=$?
check "a recorded approval writes the Test edit line the pass accepts" "0 Test edit: scripts/__tests__/x.test.sh test:a case ruling:$RID" "$RC $(cat "$F")"
check "an approved edit finds its ruling in the ruling log and in main's rulings" "0 0" \
  "$(. "$REAL/hooks/lib/ruling-id.sh"; ruling_id_state $RID "$T/rulings.jsonl"; echo $?) $(grep -qF -- "$RID" "$F"; echo $?)"
D test-edit u1 scripts/__tests__/x.test.sh 'a case' $RID >/dev/null
check "a second record of the same approval writes no second line" 1 "$(grep -c . "$F")"
D test-edit u1 scripts/__tests__/x.test.sh 'other' r-19991017-121212-p-0a0b0c >/dev/null 2>&1; R1=$?
D test-edit u1 scripts/__tests__/x.test.sh 'other' r-19991017-999999-p-ffffff >/dev/null 2>&1; R2=$?
check "an id the ruling log lacks or voids writes nothing" "1 1 1" "$R1 $R2 $(grep -c . "$F")"
D test-edit ../u scripts/a.sh lbl $RID >/dev/null 2>&1; B1=$?
D test-edit u1 '' lbl $RID >/dev/null 2>&1; B2=$?
D test-edit u1 scripts/a.sh '' $RID >/dev/null 2>&1; B3=$?
D test-edit u1 scripts/a.sh $'a\nb' $RID >/dev/null 2>&1; B4=$?
D test-edit u1 scripts/a.sh 'a ruling:b' $RID >/dev/null 2>&1; B5=$?
check "a bad unit, an empty path or name, or a name holding a newline or ruling: writes nothing" "1 1 1 1 1 1" "$B1 $B2 $B3 $B4 $B5 $(grep -c . "$F")"

# Issue 607: a near-miss name was recorded and failed only at the next pass. test-edit asks the pass's own lister, in the
# unit's worktree from where it left main, with the edit not yet staged; with no worktree it records and says so.
mkdir -p "$T/p/scripts/__tests__"; printf '%s\n' 'check "a case" 1 1' 'check "another" 2 2' > "$T/p/scripts/__tests__/y.test.sh"
git -C "$T/p" add scripts/__tests__/y.test.sh && git -C "$T/p" -c user.name=t -c user.email=t@t commit -qm y
git -C "$T/p" worktree add -q -b u7 "$T/ws/u7"; printf '%s\n' 'check "another" 2 2' > "$T/ws/u7/scripts/__tests__/y.test.sh"
F7=$T/p/.claude/briefs/u7-main-rulings.md
DA test-edit u7 scripts/__tests__/y.test.sh 'a cases' $RID >/dev/null; RC=$?
check "a near-miss test-edit label is refused and the exact names are printed" "1 1 0" "$RC $(grep -cx 'a case' "$T/err") $(grep -c . "$F7" 2>/dev/null || echo 0)"
DA test-edit u7 scripts/__tests__/y.test.sh 'a case' $RID >/dev/null; RC=$?
check "the exact test-edit label is recorded" "0 Test edit: scripts/__tests__/y.test.sh test:a case ruling:$RID" "$RC $(cat "$F7")"
DA test-edit u8 scripts/__tests__/y.test.sh 'any name' $RID >/dev/null; RC=$?
check "a test-edit for a unit with no worktree records with a warning" "0 1 1" \
  "$RC $(grep -c 'warning: no worktree for u8' "$T/err") $(grep -c 'test:any name' "$T/p/.claude/briefs/u8-main-rulings.md")"

# Issue 616: two push asks at different tips ask different things though only their shas differ; the same tip twice is
# still a repeat.
PQ='Push main to origin? 1 commit(s) since origin/main:'
D add push-1999-01-02-aaaaaaaa "$PQ aaaaaaaa u3 (check green)" push 'decision.sh push-ask' >/dev/null 2>&1; R1=$?
D add push-1999-01-02-bbbbbbbb "$PQ bbbbbbbb u3 (check green)" push 'decision.sh push-ask' >/dev/null 2>&1; R2=$?
check "two push asks at different tips with the same commit count are both written" "0 0 2" \
  "$R1 $R2 $(D list | jq '[.[] | select(.id | test("^push-1999-01-02-"))] | length')"
D add push-1999-01-03-aaaaaaaa "$PQ aaaaaaaa u3 (check green)" push 'decision.sh push-ask' >/dev/null 2>&1
check "the same tip asked twice is refused as a repeat" "3 0" "$? $(D list | jq '[.[] | select(.id == "push-1999-01-03-aaaaaaaa")] | length')"

# Issue 624: main's own question and the push ask (main-watch writes it; no pane asked) are answered on the dashboard or
# by a relay, so main hears the answer as one message; an AskUserQuestion pick was answered in the pane that asked.
# Main's ruling (2026-11-04): an answer given in the main checkout (main's own pane, the dashboard) told main already, so
# nothing is sent; one from elsewhere (the relay's worktree, here $T/ws/u1) is.
DO() { (cd "$T/ws/u1" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" COMMANDECK_MAIN="$T/p" COMMANDECK_RULING_LOG="$T/rulings.jsonl" COMMANDECK_WORKSPACES="$T/ws" COMMANDECK_ANSWER_WORKER="$T/aw" bash "$REAL/scripts/decision.sh" "$@" 2>"$T/err"); }
D add mq-1999-01-01 'Rename the cache folder?' none main >/dev/null; : > "$T/tm.log"
DO answer mq-1999-01-01 'rename it' >/dev/null
check "answering a decision main opened, outside the main checkout, sends main one message with the answer" "1 question|answer mq-1999-01-01 1" \
  "$(grep -c . "$T/tm.log") $(cut -d'|' -f1,2 "$T/tm.log") $(grep -c 'rename it' "$T/tm.log")"
D add mq-1999-01-04 'Keep the old log?' none main >/dev/null; : > "$T/tm.log"
DA answer mq-1999-01-04 'keep it' >/dev/null
check "answering a decision main opened, in the main checkout, sends main nothing (main told itself)" "0 0" "$(grep -c . "$T/tm.log") $(grep -c . "$T/err")"
: > "$T/tm.log"; DO answer push-1999-01-02-bbbbbbbb 'push it' >/dev/null
check "answering a push ask sends main one message with the answer" "1 question|answer push-1999-01-02-bbbbbbbb 1" \
  "$(grep -c . "$T/tm.log") $(cut -d'|' -f1,2 "$T/tm.log") $(grep -c 'push it' "$T/tm.log")"
D add pick-1999-01-01 'Which logo colour?' none AskUserQuestion >/dev/null; : > "$T/tm.log"
DA answer pick-1999-01-01 'blue' >/dev/null
check "an answer to an AskUserQuestion decision sends main nothing" "0 0" "$(grep -c . "$T/tm.log") $(grep -c . "$T/err")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

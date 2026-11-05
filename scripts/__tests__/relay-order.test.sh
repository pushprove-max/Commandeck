#!/usr/bin/env bash
# Issue 231: the relay passed an owner's order on a decision by hand, in three steps (answer the ledger, tell main,
# mark the decision seen), and a skipped step left main waiting or the decision firing again. What this pins:
# relay-order.sh does all three with the ruling id the ruling log holds for those words, and an unknown decision
# changes nothing.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/ws" "$T/home"
git init -q -b main "$T/p" && git -C "$T/p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
# Orca: main's pane is live in the main checkout; a send lands in $T/sent.
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "terminal list") jq -n '{result: {terminals: [{handle: "term_main", worktreePath: "$T/p", agentIdentity: "claude"}]}}' ;;
  "orchestration send") [ -e "$T/send-fails" ] && { echo '{"ok":false}'; exit 0; }; while [ \$# -gt 0 ]; do case \$1 in --subject) s=\$2 ;; --body) b=\$2 ;; --type) ty=\$2 ;; esac; shift; done
    jq -cn --arg s "\$s" --arg b "\$b" --arg t "\$ty" '{type: \$t, subject: \$s, body: \$b}' >> "$T/sent"; echo '{"ok":true}' ;;
  *) echo '{"ok":true}' ;;
esac
EOF
chmod +x "$T/bin/orca-ide"
export COMMANDECK_RULING_LOG=$T/rulings.jsonl
E=(env -u CLAUDE_PROJECT_DIR HOME="$T/home" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$T/ws" COMMANDECK_SCRATCH="$T/scratch" PATH="$T/bin:$PATH")
dec() { (cd "$T/p" && "${E[@]}" bash "$REAL/scripts/decision.sh" "$@" 2>&1); }
order() { (cd "$T/p" && "${E[@]}" bash "$REAL/scripts/relay-order.sh" "$@" 2>&1); }
SEEN=$(cd "$T/p" && "${E[@]}" bash -c ". '$REAL/scripts/cos-lib.sh' && printf '%s' \"\$COS_KEY\"").decisions-seen

dec add ship-x "Ship x now?" yes main >/dev/null
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '%s\n' '{"id":"r-19991017-101010-p-a1b2c3","utc":"'"$NOW"'","source":"prompt","question":null,"answer":"yes, ship it"}' \
  '{"id":"r-19991017-111111-p-d4e5f6","utc":"'"$NOW"'","source":"ask","question":"Ship x now?","answer":"yes, ship it"}' \
  '{"id":"r-19991017-121212-p-0a0b0c","utc":"'"$NOW"'","source":"prompt","question":null,"answer":"something else"}' > "$COMMANDECK_RULING_LOG"
OUT=$(order ship-x "yes, ship it"); RC=$?
check "the order answers the decision with the words and the newest ruling id for them" "yes, ship it (r-19991017-111111-p-d4e5f6)" \
  "$(dec list | jq -r '.[] | select(.id == "ship-x") | .answer')"
check "main gets the order as a question, with the ruling id" "question 1 1" \
  "$(jq -r .type "$T/sent" 2>/dev/null) $(grep -c 'r-19991017-111111-p-d4e5f6' "$T/sent" 2>/dev/null) $(jq -r .body "$T/sent" 2>/dev/null | grep -cx 'yes, ship it')"
check "the decision is marked seen once, and one line is printed" "1 0 1" \
  "$(grep -c '^ship-x@' "$SEEN" 2>/dev/null) $RC $(grep -c . <<<"$OUT")"
# Issue 331: the order goes through to-main.sh, which writes the one line to the wake log.
check "an order relayed to main writes one sent line" "sent" "$(jq -rs '[.[] | select(.from == "to-main") | .result] | join(",")' "$T/scratch/wake-log.jsonl" 2>/dev/null)"
: > "$T/sent"; cp "$T/p/.claude/metrics/decisions.jsonl" "$T/ledger-before"
OUT=$(order nope "yes, ship it"); RC=$?
check "an unknown decision exits 1 and changes nothing" "1 0 same 1" \
  "$RC $(grep -c . "$T/sent") $(cmp -s "$T/ledger-before" "$T/p/.claude/metrics/decisions.jsonl" && echo same) $(grep -c '^ship-x@' "$SEEN")"
dec add ship-y "Ship y now?" yes main >/dev/null
OUT=$(order ship-y "words nobody said"); RC=$?
check "words the ruling log does not hold exit 1, and the decision stays open" "1 null" \
  "$RC $(dec list | jq -r '.[] | select(.id == "ship-y") | .answeredAt')"
# A ruling binds only the decision it answers: one for another question, or given before this ask, is no authority.
dec add ship-z "Ship z now?" yes main >/dev/null
printf '%s\n' '{"id":"r-old-1","utc":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","source":"ask","question":"Enable dashboard?","answer":"yes"}' \
  '{"id":"r-old-2","utc":"2000-01-01T00:00:00Z","source":"prompt","question":null,"answer":"go"}' >> "$COMMANDECK_RULING_LOG"
: > "$T/sent"
OUT=$(order ship-z yes); RC=$?
check "a ruling on another question does not answer this decision" "1 null 0" \
  "$RC $(dec list | jq -r '.[] | select(.id == "ship-z") | .answeredAt') $(grep -c . "$T/sent")"
OUT=$(order ship-z go); RC=$?
check "a ruling given before the decision was asked does not answer it" "1 null" \
  "$RC $(dec list | jq -r '.[] | select(.id == "ship-z") | .answeredAt')"
# A failed delivery is resumed by the same order again, not refused as already answered.
printf '%s\n' '{"id":"r-new-1","utc":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","source":"ask","question":"Ship z now?","answer":"yes"}' >> "$COMMANDECK_RULING_LOG"
touch "$T/send-fails"
OUT=$(order ship-z yes); RC=$?
check "a send Orca refuses exits 1 and says main was not told" "1 1" "$RC $(grep -c 'NOT told' <<<"$OUT")"
rm "$T/send-fails"
# r2: a newer ruling with the same words does not change the stored one, so the retry still matches it.
printf '%s\n' '{"id":"r-new-2","utc":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","source":"prompt","question":null,"answer":"yes"}' >> "$COMMANDECK_RULING_LOG"
OUT=$(order ship-z yes); RC=$?
check "the same order again tells main, and the answer is written once" "0 1 yes (r-new-1)" \
  "$RC $(grep -c 'r-new-1' "$T/sent") $(dec list | jq -r '.[] | select(.id == "ship-z") | .answer')"
OUT=$(order ship-z "something else"); RC=$?
check "other words on an answered decision are still refused" "1 1" "$RC $(grep -c 'r-new-1' "$T/sent")"
# r2: the stored ruling is reused only while it still gives these words: voided since, the retry is refused.
dec add ship-w "Ship w now?" yes main >/dev/null
printf '%s\n' '{"id":"r-w-1","utc":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","source":"ask","question":"Ship w now?","answer":"go w"}' >> "$COMMANDECK_RULING_LOG"
touch "$T/send-fails"; order ship-w "go w" >/dev/null; rm "$T/send-fails"
printf '%s\n' '{"id":"r-w-2","utc":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","source":"ask","question":"Ship w now?","answer":"go w"}' >> "$COMMANDECK_RULING_LOG"
jq -c 'if .id == "r-w-1" then .void = true else . end' "$COMMANDECK_RULING_LOG" > "$T/log" && mv "$T/log" "$COMMANDECK_RULING_LOG"
: > "$T/sent"
OUT=$(order ship-w "go w"); RC=$?
check "a retry whose stored ruling was voided is refused, and main is not told" "1 0" "$RC $(grep -c . "$T/sent")"

# Issue 333: while auto-decide is on, the relay decides for the owner through --auto, which logs, records and tells
# main in one step. The entry is written before the ledger changes, so a decision with no record cannot happen.
AON=$T/p/.claude/metrics/autodecide.on; ALOG=$T/p/.claude/metrics/autodecide-test.md
auto() { (cd "$T/p" && "${E[@]}" bash "$REAL/scripts/relay-order.sh" --auto "$@" 2>&1); }
ans() { dec list | jq -r --arg id "$1" '.[] | select(.id == $id) | .answer'; }
dec add pick-a "Which cache should the build use for the long first question of this batch?" "redis" main --options 'redis|memcached' >/dev/null
dec add pick-b "Rename the flag?" "keep" main >/dev/null
dec add pick-c "Drop the old table?" "no" main >/dev/null
: > "$T/sent"
OUT=$(auto pick-a "memcached" "it is already deployed." "Redis is richer, but a second service costs more" "load grows tenfold" "yes, one config line"); RC=$?
check "--auto with the mode off refuses and changes nothing" "1 null 0" "$RC $(dec list | jq -r '.[] | select(.id == "pick-a") | .answeredAt') $(grep -c . "$T/sent")"
mkdir -p "$T/p/.claude/metrics"; echo "$ALOG" > "$AON"; echo "# head" > "$ALOG"
OUT=$(auto nope "x" "y" "z" "w" "v"); RC=$?
check "--auto on an unknown id refuses and changes nothing" "1 0 1" "$RC $(grep -c . "$T/sent") $(grep -c '^# head$' "$ALOG")"
OUT=$(auto pick-a "memcached" "it is already deployed." "" "load grows tenfold" "yes, one config line"); RC=$?
check "--auto with an empty trade-off refuses and changes nothing" "2 null 1" "$RC $(dec list | jq -r '.[] | select(.id == "pick-a") | .answeredAt') $(grep -c . "$ALOG")"
OUT=$(auto pick-a "memcached" "it is already deployed." "Redis is richer, but a second service costs more" "load grows tenfold" ""); RC=$?
check "--auto with an empty reversibility refuses and changes nothing" "2 null 1" "$RC $(dec list | jq -r '.[] | select(.id == "pick-a") | .answeredAt') $(grep -c . "$ALOG")"
HM0=$(date +%H:%M)
OUT=$(auto pick-a "memcached" "it is already deployed." "Redis is richer, but a second service costs more" "load grows tenfold" "yes, one config line"); RC=$?
# The entry's minute may be either side of a minute boundary the call crossed; any other minute is still wrong.
HM=$(date +%H:%M); grep -q "^### $HM0: pick-a" "$ALOG" && HM=$HM0
check "--auto with the mode on: the ledger answer is the words (auto-decided), the seen mark is written, main gets one question naming the id" \
  "0 memcached (auto-decided) 1 question 1" \
  "$RC $(ans pick-a) $(grep -c '^pick-a@' "$SEEN") $(jq -rs 'map(.type) | join(",")' "$T/sent") $(jq -rs 'map(select(.subject == "auto-decided for the owner on pick-a")) | length' "$T/sent")"
check "the log gains one entry (one ### line) with the ledger's question and options, the pick, the why with trade-off and would-change, and the reversibility" \
  "1|### $HM: pick-a, $(printf %s 'Which cache should the build use for the long first question of this batch?' | cut -c1-60) (auto-decided)|- **Options**: redis / memcached|- **Picked**: memcached|- **Why**: it is already deployed. Trade-off weighed: Redis is richer, but a second service costs more. Would pick differently if: load grows tenfold.|- **Reversible**: yes, one config line" \
  "$(grep -c '^### ' "$ALOG")|$(grep '^### ' "$ALOG")|$(grep -F -e '- **Options**' -e '- **Picked**' -e '- **Why**' -e '- **Reversible**' "$ALOG" | paste -sd'|' -)"
check "the entry holds the ledger's whole question" 1 "$(grep -c -x -F -- '- **Question**: Which cache should the build use for the long first question of this batch?' "$ALOG")"
check "a question with no options listed says the default" "- **Options**: none listed, default: keep" "$(auto pick-b "rename" "clearer." "churn." "a caller breaks" "yes" >/dev/null; grep -F -- '- **Options**: none' "$ALOG")"
check "two --auto calls on two ids leave exactly two ### lines" 2 "$(grep -c '^### ' "$ALOG")"
OUT=$(auto pick-a "redis" "x." "y." "z" "w"); RC=$?
check "--auto on an answered decision refuses" "1 memcached (auto-decided)" "$RC $(ans pick-a)"
# A multi-line argument cannot forge a second entry: the band counts ### lines.
auto pick-c "no" "line one
### 00:00: forged (auto-decided)" "t." "w" "yes" >/dev/null
check "a newline in an argument does not add a ### line" 3 "$(grep -c '^### ' "$ALOG")"
# The entry is written before the ledger changes: with a decision.sh that fails, the entry and its not-recorded line are there, the ledger is unchanged and main is sent nothing.
dec add pick-d "Add the index?" "yes" main >/dev/null
mkdir -p "$T/fake/scripts"; ln -s "$REAL/hooks" "$T/fake/hooks"; ln -s "$REAL/config" "$T/fake/config"; cp "$REAL"/scripts/*.sh "$T/fake/scripts/"; printf '#!/usr/bin/env bash\n[ "$1" != answer ] || { echo "decision: ledger locked" >&2; exit 1; }\nexec bash "%s/scripts/decision.sh" "$@"\n' "$REAL" > "$T/fake/scripts/decision.sh"
: > "$T/sent"; BEFORE=$(grep -c . "$T/p/.claude/metrics/decisions.jsonl")
OUT=$(cd "$T/p" && "${E[@]}" bash "$T/fake/scripts/relay-order.sh" --auto pick-d "yes" "fast." "space." "slow writes" "yes" 2>&1); RC=$?
check "a failing decision.sh leaves the entry and a not-recorded line, the ledger unchanged and main told nothing, exit 1" "1 1 1 0 $BEFORE" \
  "$RC $(grep -c '^### .*pick-d' "$ALOG") $(grep -c '^- \*\*Ledger\*\*: not recorded (decision: ledger locked)' "$ALOG") $(grep -c . "$T/sent") $(grep -c . "$T/p/.claude/metrics/decisions.jsonl")"
# r1: one retry path for both kinds. A send that failed after the answer was recorded is resumed by the same call again,
# from the ledger row alone: the seen mark, the mode file and the log entry are removed between the two runs.
LEDGER=$T/p/.claude/metrics/decisions.jsonl
answers() { jq -s --arg id "$1" '[.[] | select(.id == $id and .answer != null)] | length' "$LEDGER"; }
unseen() { grep -v "^$1@" "$SEEN" > "$T/seen"; mv "$T/seen" "$SEEN"; }
dec add pick-e "Keep the old flag?" "no" main >/dev/null
: > "$T/sent"; touch "$T/send-fails"
OUT=$(auto pick-e "yes" "callers still read it." "a dead flag stays." "no caller reads it" "yes, one line"); RC=$?
check "--auto whose send Orca refuses exits 1 with the answer recorded and main not told" "1 1 yes (auto-decided) 0" \
  "$RC $(grep -c 'NOT told' <<<"$OUT") $(ans pick-e) $(grep -c . "$T/sent")"
rm "$T/send-fails"; unseen pick-e; rm "$AON"; grep -v 'pick-e' "$ALOG" > "$T/alog"; mv "$T/alog" "$ALOG"
OUT=$(auto pick-e "yes" "callers still read it." "a dead flag stays." "no caller reads it" "yes, one line"); RC=$?
check "the same --auto call again tells main once and marks it seen, with no second entry or answer" "0 1 1 0 1" \
  "$RC $(jq -rs 'map(select(.subject == "auto-decided for the owner on pick-e")) | length' "$T/sent") $(grep -c '^pick-e@' "$SEEN") $(grep -c 'pick-e' "$ALOG") $(answers pick-e)"
echo "$ALOG" > "$AON"
: > "$T/sent"; unseen ship-z
OUT=$(order ship-z yes); RC=$?
check "an order resent with its seen mark removed tells main and marks it seen again" "0 1 1" "$RC $(grep -c 'r-new-1' "$T/sent") $(grep -c '^ship-z@' "$SEEN")"
# The retry trusts an answered row only when it holds exactly what this call would write.
: > "$T/sent"; N=$(grep -c '^### ' "$ALOG")
OUT=$(auto ship-x "yes, ship it" "x." "y." "z" "w"); RC=$?
check "--auto with an owner's words on a row the owner answered refuses, and nothing is sent or logged" "1 0 $N" \
  "$RC $(grep -c . "$T/sent") $(grep -c '^### ' "$ALOG")"
# r1: the owner reverses an auto-decision with an ordinary order; the auto answer goes to the row's history.
QA="Which cache should the build use for the long first question of this batch?"
OUT=$(order pick-a "words nobody said"); RC=$?
check "an order with no ruling leaves an auto-decided answer as it was" "1 memcached (auto-decided)" "$RC $(ans pick-a)"
printf '%s\n' '{"id":"r-rev-0","utc":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","source":"ask","question":"Ship x now?","answer":"redis"}' >> "$COMMANDECK_RULING_LOG"
OUT=$(order pick-a redis); RC=$?
check "a ruling on another question does not reverse an auto-decided answer" "1 memcached (auto-decided)" "$RC $(ans pick-a)"
jq -cn --arg q "$QA" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{id: "r-rev-1", utc: $at, source: "ask", question: $q, answer: "redis"}' >> "$COMMANDECK_RULING_LOG"
: > "$T/sent"; touch "$T/send-fails"
OUT=$(order pick-a redis); RC=$?
check "the owner's ruling replaces the auto answer, which is kept in the history, even when the send fails" "1 redis (r-rev-1) memcached (auto-decided)" \
  "$RC $(ans pick-a) $(dec list | jq -r '.[] | select(.id == "pick-a") | (.history // []) | map(.answer) | join(",")')"
rm "$T/send-fails"; unseen pick-a
OUT=$(order pick-a redis); RC=$?
check "the reversal again tells main with the ruling id, marks it seen and corrects nothing twice" "0 1 1 1" \
  "$RC $(jq -rs 'map(select(.subject == "order from the owner on pick-a (r-rev-1)")) | length' "$T/sent") $(grep -c '^pick-a@' "$SEEN") $(dec list | jq -r '.[] | select(.id == "pick-a") | .history | length')"
printf '%s\n' '{"id":"r-x-no","utc":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","source":"ask","question":"Ship x now?","answer":"no"}' >> "$COMMANDECK_RULING_LOG"
OUT=$(order ship-x no); RC=$?
check "a new ruling does not replace an answer the owner gave: only an auto-decided one" "1 yes, ship it (r-19991017-111111-p-d4e5f6)" "$RC $(ans ship-x)"
# Issues 610 and 656: the push answer decision.sh push-ask writes in auto mode ends " (auto-decided)", so the owner's no reverses it.
QP="Push main to origin? 1 commit(s) since origin/main: aaaaaaaa a1 (check green)"
dec add push-1999-09-09-aaaaaaaa "$QP" push 'decision.sh push-ask' >/dev/null
COMMANDECK_MAIN_TOLD=1 dec answer push-1999-09-09-aaaaaaaa 'yes: closing GO and green checks on aaaaaaaa (auto-decided)' >/dev/null 2>&1
jq -cn --arg q "$QP" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{id: "r-push-no", utc: $at, source: "ask", question: $q, answer: "no"}' >> "$COMMANDECK_RULING_LOG"
OUT=$(order push-1999-09-09-aaaaaaaa no); RC=$?
check "owner no reverses an auto-answered push" "0 no (r-push-no) yes: closing GO and green checks on aaaaaaaa (auto-decided)" \
  "$RC $(ans push-1999-09-09-aaaaaaaa) $(dec list | jq -r '.[] | select(.id == "push-1999-09-09-aaaaaaaa") | (.history // []) | map(.answer) | join(",")')"
# Issue 569: an owner's answer to a Builder's question reaches the unit once, through the ledger in decision.sh answer; the
# note's body ends `Delivery: <line>`, a resumed order repeats the recorded line, and a reversal says the ledger sent nothing.
DELS=${SEEN%.decisions-seen}.deliveries
mkdir -p "$T/ws/u9"
printf '#!/usr/bin/env bash\nprintf "%%s|" "$@" >> "%s/aw.log"; echo >> "%s/aw.log"\necho "worker stdout line"\n' "$T" "$T" > "$T/aw"
chmod +x "$T/aw"; : > "$T/aw.log"
E+=(COMMANDECK_ANSWER_WORKER="$T/aw")
dec add u9-msg_r1 "Which lock for the cache, flock or lockf?" none "u9 asks" >/dev/null
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ) # not before the ask: the ruling must be given since the decision was asked
printf '%s\n' '{"id":"r-19991017-131313-p-aa11bb","utc":"'"$NOW"'","source":"prompt","question":null,"answer":"use flock"}' >> "$COMMANDECK_RULING_LOG"
: > "$T/sent"
OUT=$(order u9-msg_r1 "use flock"); RC=$?
# The worker's own stdout line never reaches decision.sh's stdout, the row relay-order parses: jq reports nothing in its output.
check "an owner answer relayed through relay-order reaches the unit once" "0 1 u9|use flock (r-19991017-131313-p-aa11bb)|u9-msg_r1| 1 delivered: u9-msg_r1 to u9 0" \
  "$RC $(grep -c . "$T/aw.log") $(head -1 "$T/aw.log") $(jq -r .body "$T/sent" | grep -c '^Delivery: delivered') $(jq -r .body "$T/sent" | sed -n 's/^Delivery: //p') $(grep -c '^jq: ' <<<"$OUT")"
# A retry after main was not told: the seen mark goes, the first call's line is repeated and the unit is not sent again.
unseen u9-msg_r1; : > "$T/sent"
OUT=$(order u9-msg_r1 "use flock"); RC=$?
check "a retried relay order after a failed note to main repeats the first call's delivery line" "0 1 delivered: u9-msg_r1 to u9" \
  "$RC $(grep -c . "$T/aw.log") $(jq -r .body "$T/sent" | sed -n 's/^Delivery: //p')"
# Nothing usable recorded for the retry: unknown, never a second send.
unseen u9-msg_r1; : > "$T/sent"; printf 'junk\nu9-msg_r1@x\ta\tb\n' > "$DELS"
OUT=$(order u9-msg_r1 "use flock"); RC=$?
check "a retry with no usable recorded line says Delivery: unknown, and sends nothing" "0 1 1" \
  "$RC $(grep -c . "$T/aw.log") $(jq -r .body "$T/sent" | grep -c '^Delivery: unknown: an earlier relay call')"
# (pass 9, the owner's answer) Catches: decision.sh's unknown line (a send cut at its deadline) dropped from
# main's note, so main reads no delivery word. The stub timeout runs the worker, then exits 124 as a deadline does.
mkdir -p "$T/tbin"; printf '#!/usr/bin/env bash\nshift; "$@"; exit 124\n' > "$T/tbin/timeout"; chmod +x "$T/tbin/timeout"; cp "$T/tbin/timeout" "$T/tbin/gtimeout"
dec add u9-msg_r9 "Which index for the cache, btree or hash?" none "u9 asks" >/dev/null
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '%s\n' '{"id":"r-19991017-141414-p-cc22dd","utc":"'"$NOW"'","source":"prompt","question":null,"answer":"use btree"}' >> "$COMMANDECK_RULING_LOG"
: > "$T/sent"
OUT=$(cd "$T/p" && "${E[@]}" PATH="$T/tbin:$T/bin:$PATH" bash "$REAL/scripts/relay-order.sh" u9-msg_r9 "use btree" 2>&1)
check "a relayed answer whose send is cut at its deadline tells main unknown, check the pane before resending" \
  "unknown: u9-msg_r9 to u9 timed out; check the unit's pane before resending" "$(jq -r .body "$T/sent" | sed -n 's/^Delivery: //p')"
# Issue 569: main's rules (main-session.md, and the next line orca-wait.sh prints for an owner-bound question) say what is sent
# again and what is not: a delivered or queued answer is never sent twice; not delivered, a reversal, and an owner's chat answer
# are sent once with answer-worker and the row id, even when the hook already closed the row.
MS=$(tr '\n' ' ' < "$REAL/templates/main-session.md" | tr -s ' ')
OW=$(grep 'it waits for the owner' "$REAL/scripts/orca-wait.sh")
check "main's rules say an answer the ledger delivered is not resent, and an owner's chat answer is sent once with answer-worker even when the hook closed its row" "1 1 1 1 1" \
  "$(grep -c 'saying an answer was `delivered` or `queued` is not sent again' <<<"$MS") $(grep -c 'not delivered. or .not sent by the ledger' <<<"$MS") $(grep -c 'whether or not the hook already closed the row' <<<"$MS") $(grep -c 'a note reading delivered or queued is not sent again' <<<"$OW") $(grep -c 'answer the owner gives you in chat, you send on: bash .*answer-worker.sh' <<<"$OW")"
# (pass 9) Catches: main told by one rule to resend an unknown at once, or by the other never: both say once the pane shows none.
check "main's rules resend an unknown delivery only once the unit's pane shows no answer" "1 1" \
  "$(grep -c '`unknown` once the unit.s pane shows no answer' <<<"$MS") $(grep -c 'one reading unknown once the unit.s pane shows no answer' <<<"$OW")"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

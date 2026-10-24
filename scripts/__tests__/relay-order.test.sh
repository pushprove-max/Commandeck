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
OUT=$(auto pick-a "memcached" "it is already deployed." "Redis is richer, but a second service costs more" "load grows tenfold" "yes, one config line"); RC=$?
check "--auto with the mode on: the ledger answer is the words (auto-decided), the seen mark is written, main gets one question naming the id" \
  "0 memcached (auto-decided) 1 question 1" \
  "$RC $(ans pick-a) $(grep -c '^pick-a@' "$SEEN") $(jq -rs 'map(.type) | join(",")' "$T/sent") $(jq -rs 'map(select(.subject == "auto-decided for the owner on pick-a")) | length' "$T/sent")"
check "the log gains one entry (one ### line) with the ledger's question and options, the pick, the why with trade-off and would-change, and the reversibility" \
  "1|### $(date +%H:%M): pick-a, $(printf %s 'Which cache should the build use for the long first question of this batch?' | cut -c1-60) (auto-decided)|- **Options**: redis / memcached|- **Picked**: memcached|- **Why**: it is already deployed. Trade-off weighed: Redis is richer, but a second service costs more. Would pick differently if: load grows tenfold.|- **Reversible**: yes, one config line" \
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
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

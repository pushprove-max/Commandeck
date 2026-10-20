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
  "orchestration send") while [ \$# -gt 0 ]; do case \$1 in --subject) s=\$2 ;; --body) b=\$2 ;; --type) ty=\$2 ;; esac; shift; done
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
printf '%s\n' '{"id":"r-19991017-101010-p-a1b2c3","source":"prompt","answer":"yes, ship it"}' \
  '{"id":"r-19991017-111111-p-d4e5f6","source":"prompt","answer":"yes, ship it"}' \
  '{"id":"r-19991017-121212-p-0a0b0c","source":"prompt","answer":"something else"}' > "$COMMANDECK_RULING_LOG"
OUT=$(order ship-x "yes, ship it"); RC=$?
check "the order answers the decision with the words and the newest ruling id for them" "yes, ship it (r-19991017-111111-p-d4e5f6)" \
  "$(dec list | jq -r '.[] | select(.id == "ship-x") | .answer')"
check "main gets the order as a question, with the ruling id" "question 1 1" \
  "$(jq -r .type "$T/sent" 2>/dev/null) $(grep -c 'r-19991017-111111-p-d4e5f6' "$T/sent" 2>/dev/null) $(jq -r .body "$T/sent" 2>/dev/null | grep -cx 'yes, ship it')"
check "the decision is marked seen once, and one line is printed" "1 0 1" \
  "$(grep -c '^ship-x@' "$SEEN" 2>/dev/null) $RC $(grep -c . <<<"$OUT")"
: > "$T/sent"; cp "$T/p/.claude/metrics/decisions.jsonl" "$T/ledger-before"
OUT=$(order nope "yes, ship it"); RC=$?
check "an unknown decision exits 1 and changes nothing" "1 0 same 1" \
  "$RC $(grep -c . "$T/sent") $(cmp -s "$T/ledger-before" "$T/p/.claude/metrics/decisions.jsonl" && echo same) $(grep -c '^ship-x@' "$SEEN")"
dec add ship-y "Ship y now?" yes main >/dev/null
OUT=$(order ship-y "words nobody said"); RC=$?
check "words the ruling log does not hold exit 1, and the decision stays open" "1 null" \
  "$RC $(dec list | jq -r '.[] | select(.id == "ship-y") | .answeredAt')"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

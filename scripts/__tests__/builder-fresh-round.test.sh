#!/usr/bin/env bash
# A fix round's hand-off gave up after 15 minutes while the Builder's pane was still busy on a long turn, and
# its notice to main was refused (an escalation from a pane with no dispatch), so the round stalled unseen.
# Pinned: a busy pane is waited on until it idles; a pane that is gone gets nothing typed and main gets a
# question with the command that re-runs the hand-off; two hand-offs to one pane never interleave their typing.
# An Orca that fails (no answer, or a wait error other than a timeout) is retried a bounded number of times,
# then main is told: retried for good, it held the pane's lock and stalled every later hand-off unseen.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
SC=$T/scratch; mkdir -p "$T/bin" "$SC"
git init -q -b main "$T/p"
# Orca: a wait times out while $T/busy holds a count above 0; one --timeout-ms 120000 wait holds until $T/release
# when $T/hold exists; the list holds term_x unless $T/gone exists; every send is logged. With $T/down every
# call fails with no answer; with $T/werr a wait fails with an error that is not a timeout, with $T/werr2 only the
# 1000-ms second wait does. While $T/blocked holds a count above 0, a wait answers as Orca does for a pane that awaits
# its user: exit 1 with ok:true and wait.satisfied:false.
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
[ ! -e "$T/down" ] || exit 1
case "\$*" in
  *"terminal wait"*)
    [ ! -e "$T/werr" ] || { echo '{"ok":false,"error":{"code":"internal","message":"boom"}}'; exit 1; }
    case "\$*" in *"--timeout-ms 1000 "*) [ ! -e "$T/werr2" ] || { echo '{"ok":false,"error":{"code":"internal"}}'; exit 1; } ;; esac
    b=\$(cat "$T/blocked" 2>/dev/null || echo 0); [ "\$b" -le 0 ] || { echo \$((b - 1)) > "$T/blocked"; echo '{"ok":true,"result":{"wait":{"satisfied":false}}}'; exit 1; }
    n=\$(cat "$T/busy" 2>/dev/null || echo 0); [ "\$n" -le 0 ] || { echo \$((n - 1)) > "$T/busy"; echo '{"ok":false,"error":{"code":"timeout"}}'; exit 1; }
    case "\$*" in *"--timeout-ms 120000"*) ! rm "$T/hold" 2>/dev/null || until [ -e "$T/release" ]; do sleep 0.05; done ;; esac
    [ ! -e "$T/gone" ] || exit 1 ;;
  *"terminal list"*) [ -e "$T/gone" ] && echo '{"result":{"terminals":[]}}' || echo '{"result":{"terminals":[{"handle":"term_x","worktreePath":"/elsewhere"}]}}' ;;
  *"terminal send"*) printf '%s\n' "\$*" | grep -oE -- '--text (/clear|Your task spec)' >> "$T/sends" ;;
esac
exit 0
EOF
chmod +x "$T/bin/orca-ide"
frs() { (cd "$T/p" && env PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/p" COMMANDECK_SCRATCH="$SC" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_FRESH_ROUND_SETTLE_SECONDS=0 timeout 10 bash "$REAL/scripts/builder-fresh-round.sh" term_x "$T/hand-$1.md"); }

echo 3 > "$T/busy"
frs a > "$T/a.out" 2>&1; R=$?
check "a pane busy for three tries is waited on, then cleared and handed the file" "0 /clear,Your task spec" \
  "$R $(sed 's/--text //' "$T/sends" | paste -sd, -)"

rm -f "$T/sends"; touch "$T/gone"
frs b > "$T/b.out" 2>&1; R=$?
check "a pane that is gone: exit 1, nothing typed, and the reason said" "1 0 1" \
  "$R $(cat "$T/sends" 2>/dev/null | wc -l | tr -d ' ') $(grep -c 'pane term_x is gone; nothing typed' "$T/b.out")"
check "main is sent a question (Orca takes one from a pane with no dispatch), with the re-run command" "question 1" \
  "$(jq -r .type "$SC/queue/main.jsonl") $(jq -r .body "$SC/queue/main.jsonl" | grep -cxF "re-run: bash $REAL/scripts/builder-fresh-round.sh term_x $T/hand-b.md")"

rm -f "$T/sends" "$T/gone" "$T/busy"; touch "$T/hold"
frs c1 > "$T/c1.out" 2>&1 & P1=$!
for _ in $(seq 100); do [ -e "$T/hold" ] || break; sleep 0.05; done
frs c2 > "$T/c2.out" 2>&1 & P2=$!
sleep 1; touch "$T/release"; wait "$P1" "$P2"
check "two hand-offs to one pane: the second types only after the first is done" "/clear,Your task spec,/clear,Your task spec" \
  "$(sed 's/--text //' "$T/sends" | paste -sd, -)"

rm -f "$T/sends"; echo 6 > "$T/blocked"
frs blk > "$T/blk.out" 2>&1; R=$?
check "a pane blocked on its user for six tries is waited on, not taken for Orca failing" "0 /clear,Your task spec" \
  "$R $(sed 's/--text //' "$T/sends" | paste -sd, -)"

# werr2: the first wait answers idle every time, so only failures of the second wait can stop the loop.
for f in down werr werr2; do
  rm -f "$T/sends" "$T/hold" "$T/release" "$SC/queue/main.jsonl"; touch "$T/$f"
  frs "$f" > "$T/$f.out" 2>&1; R=$?; rm -f "$T/$f"
  check "Orca failing ($f): exit 1 before the timeout, nothing typed, the reason said, main sent the re-run" "1 0 1 1" \
    "$R $(cat "$T/sends" 2>/dev/null | wc -l | tr -d ' ') $(grep -c 'Orca failed 5 times in a row' "$T/$f.out") $(jq -r .body "$SC/queue/main.jsonl" 2>/dev/null | grep -c '^re-run: ')"
done

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

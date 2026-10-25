#!/usr/bin/env bash
# close-done-panes.sh --close: a finished (`done`) pane goes after its quiet time, but a seat pane whose record has no
# verdict= line is left to seat.sh collect (a plan seat printed its end marker and was swept before collect read it,
# host issue 3048), and every close it makes goes through pp_pane_close, which logs it with its cause (host issue 3009).
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
P=$T/proj WS=$T/ws SC=$T/scratch; mkdir -p "$T/bin" "$WS/u" "$SC"
git init -q -b main "$P" && git -C "$P" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
NOW_MS=$(( $(date +%s) * 1000 )); OLD=$(( NOW_MS - 3600000 ))
# Two finished panes of one unit's worktree, silent for an hour; the stand-in closes whatever it is told to and says so.
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "worktree list") echo '{"result":{"worktrees":[{"path":"$WS/u","displayName":"u","cliProvenance":{"kind":"created-by-cli"}}]}}' ;;
  "terminal list") echo '{"result":{"terminals":[
    {"handle":"h_unc","tabId":"t1","leafId":"l1","worktreePath":"$WS/u","lastOutputAt":$OLD,"agentIdentity":"claude"},
    {"handle":"h_col","tabId":"t2","leafId":"l2","worktreePath":"$WS/u","lastOutputAt":$OLD,"agentIdentity":"claude"}]}}' ;;
  "worktree ps") echo '{"result":{"worktrees":[{"agents":[
    {"paneKey":"t1:l1","state":"done","updatedAt":$OLD,"agentType":"claude"},
    {"paneKey":"t2:l2","state":"done","updatedAt":$OLD,"agentType":"claude"}]}]}}' ;;
  "terminal close") echo "\$4" >> "$T/closed"; echo '{"ok":true,"result":{}}' ;;
esac
EOF
chmod +x "$T/bin/orca-ide"
printf 'handle=h_unc\ntask=task_1\nrole=reviewer\nunit=u\n' > "$SC/seat-u-reviewer.txt"
printf 'handle=h_col\ntask=task_2\nrole=reviewer\nunit=u\nverdict=VERDICT: GO\n' > "$SC/seat-u-reviewer2.txt"
OUT=$(cd "$P" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u ORCA_TERMINAL_HANDLE COMMANDECK_WORKSPACES="$WS" COMMANDECK_SCRATCH="$SC" \
  COMMANDECK_DRIVERS=none PATH="$T/bin:$PATH" bash "$REAL/scripts/close-done-panes.sh" --close 2>&1)
check "an uncollected seat pane in state done is kept; a collected one is closed" "h_col" "$(cat "$T/closed" 2>/dev/null | paste -sd' ' -)"
check "the closed one is reported and the kept one is not" "1:0" "$(grep -c '^closed h_col' <<<"$OUT"):$(grep -c 'h_unc' <<<"$OUT")"
check "the close is logged with the sweep as its caller and its cause" "h_col|close-done-panes.sh|ok" \
  "$(awk -F'\t' '{print $2 "|" $3 "|" $5}' "$SC/pane-closes.log" 2>/dev/null | paste -sd' ' -)"
check "the log's cause names the pane's agent and idle minutes" "1" "$(awk -F'\t' '$4 ~ /^sweep: claude idle [0-9]+m$/' "$SC/pane-closes.log" 2>/dev/null | wc -l | tr -d ' ')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

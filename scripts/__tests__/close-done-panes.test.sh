#!/usr/bin/env bash
# close-done-panes.sh --close ends panes without asking, so what it may pick
# is the whole safety of it: only this repo's worktrees (Orca lists every
# repo's, and a second project on the machine must lose nothing), and never a
# pane whose agent Orca reports as working, however long it has printed nothing.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/scratch" "$TMP/home"
WS=$TMP/ws/mine OTHER=$TMP/ws/theirs
OLD=$(( ($(date +%s) - 7200) * 1000 ))
pane() { printf '{"handle":"%s","worktreePath":"%s","tabId":"%s","leafId":"l","lastOutputAt":%s}' "$1" "$2" "$1" "$OLD"; }
agent() { printf '{"paneKey":"%s:l","state":"%s","updatedAt":%s,"agentType":"claude"}' "$1" "$2" "$OLD"; }
wt() { printf '{"path":"%s","displayName":"u","isMainWorktree":false,"cliProvenance":{"kind":"created-by-cli"}}' "$1"; }
cat > "$TMP/bin/orca-ide" <<STUB
#!/usr/bin/env bash
case "\$1 \$2" in
  "worktree list") echo '{"result":{"worktrees":[$(wt "$WS/a"),$(wt "$WS/b"),$(wt "$WS/c"),$(wt "$WS/d"),$(wt "$OTHER/x")]}}' ;;
  "terminal list") echo '{"result":{"terminals":[$(pane t_done "$WS/a"),$(pane t_working "$WS/b"),$(pane t_shell "$WS/c"),$(pane t_builder "$WS/d"),$(pane t_other "$OTHER/x")]}}' ;;
  "worktree ps") [ ! -e "$TMP/ps-error" ] || { echo '{"ok":false,"error":{"code":"rpc_failed"}}'; exit 0; }
    echo '{"result":{"worktrees":[{"agents":[$(agent t_done done),$(agent t_working working),$(agent t_builder done),$(agent t_other done)]}]}}' ;;
  *) echo '{"ok":true}' ;;
esac
STUB
chmod +x "$TMP/bin/orca-ide"
# A Builder ends many turns before its batch merges; its pane holds the batch's context.
printf 'handle=t_builder\nverdict=VERDICT: GO\n' > "$TMP/scratch/seat-d-builder.txt"
OUT=$(PATH="$TMP/bin:$PATH" HOME="$TMP/home" COMMANDECK_MAIN="$TMP/main" COMMANDECK_WORKSPACES="$WS" \
  COMMANDECK_SCRATCH="$TMP/scratch" COMMANDECK_DRIVERS=none.service bash "$REAL/scripts/close-done-panes.sh" 2>"$TMP/err")
check "the sweep runs" 0 "$?"
picked() { grep -c "^$1	" <<<"$OUT"; }
check "a done pane quiet past the line in this repo is picked" 1 "$(picked t_done)"
check "a quiet shell pane nobody claims in this repo is picked" 1 "$(picked t_shell)"
check "a done pane in another repo's worktree is never picked" 0 "$(picked t_other)"
check "a pane whose agent is working is never picked, however quiet" 0 "$(picked t_working)"
check "a Builder's pane is never picked, done and quiet or not" 0 "$(picked t_builder)"

# An agent list Orca did not answer is not "no agent works": read as empty,
# the working pane has no agent, is quiet, and is closed as an orphan.
: > "$TMP/ps-error"
OUT=$(PATH="$TMP/bin:$PATH" HOME="$TMP/home" COMMANDECK_MAIN="$TMP/main" COMMANDECK_WORKSPACES="$WS" \
  COMMANDECK_SCRATCH="$TMP/scratch" COMMANDECK_DRIVERS=none.service bash "$REAL/scripts/close-done-panes.sh" 2>"$TMP/err")
check "a failed agent read refuses the sweep" 1 "$?"
check "a failed agent read picks no pane" "" "$OUT"
check "the refusal names the read that failed" 1 "$(grep -c 'worktree ps' "$TMP/err")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

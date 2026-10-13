#!/usr/bin/env bash
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BOX=$(mktemp -d)
trap 'rm -rf "$BOX"' EXIT
cat > "$BOX/orca-ide" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "worktree ps") echo '{"result":{"worktrees":[{"agents":[{"paneKey":"t:l","state":"working"}]}]}}' ;;
  "terminal list") echo '{"result":{"terminals":[{"handle":"term_busy","tabId":"t","leafId":"l"}]}}' ;;
esac
EOF
chmod +x "$BOX/orca-ide"
CMD='orca-ide terminal send --terminal term_busy --text "Inspect orca-ide terminal list --json, then review the brief" --enter'
set +e
jq -nc --arg c "$CMD" '{tool_input:{command:$c}}' |
  PATH="$BOX:$PATH" "$ROOT/hooks/duplicate-agent-guard.sh" >/dev/null 2>&1
RC=$?
set -e
[ "$RC" -eq 2 ] || { echo "busy-pane send was allowed (hook exit $RC)"; exit 1; }

#!/usr/bin/env bash
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel)

git() {
  case "${*: -1}" in
    --git-dir) echo /fake/worktrees/cos ;;
    --git-common-dir) echo /fake/common ;;
    --show-toplevel) echo /fake/Chief-of-Staff ;;
    *) return 1 ;;
  esac
}
ps() { printf '%s\n' "$FIXTURE"; }
export -f git ps
export CLAUDE_PROJECT_DIR=/fake/Chief-of-Staff
export ORCA_TERMINAL_HANDLE=term_cos
export COMMANDECK_REVIEWER=
export COMMANDECK_HOOK_FIRE_LOG=/dev/null

FAIL=0
for HANDLES in "term_other term_cos" "term_cos term_other"; do
  export FIXTURE="bash /x/plugin/scripts/cos-watch-inbox.sh $HANDLES"
  OUT=$(printf '{}\n' | bash "$ROOT/hooks/cos-inbox-waiter-stop.sh")
  if [ "$(printf '%s\n' "$OUT" | jq -r '.decision')" != block ]; then
    echo "FAIL: accepted $HANDLES"
    FAIL=$((FAIL + 1))
  fi
done
[ "$FAIL" -eq 0 ]

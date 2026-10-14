#!/usr/bin/env bash
# uninstall-snapshot.test.sh -- the owner asked for an uninstall that leaves
# the machine exactly as it was. What this pins: snapshot, set up, do a unit's
# worth of work, uninstall, snapshot again, and the two match byte for byte --
# with the data deleted, nothing differs; with the data kept, only the data
# differs. With another tool's entries in every file the plugin merges into.
set -uo pipefail
. "$(dirname "$0")/install-fixture.sh"

# work <project dir> -- what one unit leaves behind: a worktree set up and removed, a
# question in the ledger, a hook fire, a ruling, a scratch file and one dashboard collect.
work() {
  local name=${1##*/} wt
  wt=$HOME/orca/workspaces/$name/u1
  git -C "$1" worktree add -q "$wt" -b u1 && run "$wt" worktree-setup.sh "$wt" >/dev/null 2>&1
  mkdir -p "$1/.claude/metrics"; : > "$1/.claude/metrics/decisions.jsonl"
  run "$1" decision.sh add d1 "Ship it?" "wait" u1 >/dev/null 2>&1
  ( cd "$1" && echo '{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"Bash","tool_input":{"command":"ls"}}' \
      | env -u COMMANDECK_HOOK_FIRE_LOG PATH="$BIN:$PATH" CLAUDE_PROJECT_DIR="$1" bash "$PLUGIN/hooks/git-safety.sh" >/dev/null 2>&1 )
  mkdir -p "$HOME/.claude/rulings" "$HOME/.commandeck/scratch/$(printf %s "$1" | tr -c 'A-Za-z0-9' '-')"
  echo '{}' >> "$HOME/.claude/rulings/$name.jsonl"
  echo note > "$HOME/.commandeck/scratch/$(printf %s "$1" | tr -c 'A-Za-z0-9' '-')/seat-x.txt"
  run "$1" dashboard.sh >/dev/null 2>&1
  git -C "$1" worktree remove --force "$wt" && git -C "$1" branch -q -D u1
}
# Where the plugin's own data lives: the only paths a keep-data uninstall may leave.
DATA='^[0-9a-f]* (home/\.commandeck/|home/\.claude/hook-fire-log/|home/\.claude/rulings/|home/orca/|proj[^/]*/\.claude/metrics/)|^(home/\.commandeck/|home/\.claude/hook-fire-log/|home/\.claude/rulings/|home/orca/|proj[^/]*/\.claude/metrics/)'
changed() { diff <(printf '%s\n' "$1") <(printf '%s\n' "$2") | grep '^[<>]' | sed 's/^[<>] //' | sort -u; }

BEFORE=$(snap)
scope=project
run "$PROJ" setup.sh "${ANSWERS[@]}" --scope "$scope" >"$T/setup.out" 2>&1; check "$scope scope: setup succeeds" 0 $?
check "$scope scope: setup changed the machine" 1 "$([ "$(snap)" != "$BEFORE" ] && echo 1 || echo 0)"
work "$PROJ"
run "$PROJ" uninstall.sh >"$T/uninstall.out" 2>&1; check "$scope scope: uninstall succeeds" 0 $?
AFTER=$(snap)
check "$scope scope: with the data kept, only the plugin's data differs" '' "$(changed "$BEFORE" "$AFTER" | grep -vE "$DATA")"
check "$scope scope: the data is kept" 1 "$(grep -c 'proj/.claude/metrics/decisions.jsonl$' <<<"$AFTER")"
check "$scope scope: no job is left running" 0 "$(ls "$HOME/.config/systemd/user" 2>/dev/null | grep -c commandeck)"
run "$PROJ" uninstall.sh --delete-data >>"$T/uninstall.out" 2>&1; check "$scope scope: deleting the data afterwards succeeds" 0 $?
check "$scope scope: with the data deleted, the machine is as it was" '' "$(changed "$BEFORE" "$(snap)")"

[ "$FAIL" = 0 ] || { echo "--- last setup output"; tail -15 "$T/setup.out"; echo "--- last uninstall output"; tail -15 "$T/uninstall.out"; }
done_tests

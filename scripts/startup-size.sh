#!/usr/bin/env bash
# startup-size.sh [--role main|worker|builder|chief-of-staff] [--per-prompt]
#   -- measure what the plugin's hooks put into a pane's context, in bytes.
# Output over 10240 bytes reaches the model as a 2 KB preview, so each hook's
# output is held under that line: exit 1 names the hook that crossed it.
#   (default)     every SessionStart hook in hooks/hooks.json, run as each of
#                 the four seats (or the one --role names).
#   --per-prompt  every UserPromptSubmit hook on a sample prompt, and their sum:
#                 what rides in on every turn, held under the same line.
# What is measured is the hooks' real output for the project this runs in
# (CLAUDE_PROJECT_DIR or the current checkout), not a sum of file sizes. The
# seats are a scratch repo's checkout and worktrees; nothing is logged.
set -euo pipefail
# On a Mac: Homebrew's tools ahead of the system's, and out of its Bash 3.2 (requirements.sh).
. "$(dirname "$0")/requirements.sh"
PLUGIN=$(cd "$(dirname "$0")/.." && pwd)
LIMIT=10240
ROLES=(main worker builder chief-of-staff)
usage() { echo "usage: startup-size.sh [--role main|worker|builder|chief-of-staff] [--per-prompt]" >&2; exit 2; }
EVENT=SessionStart ONLY=
while [ $# -gt 0 ]; do
  case $1 in
    --role) [ $# -ge 2 ] && [[ " ${ROLES[*]} " == *" $2 "* ]] || usage; ONLY=$2; shift 2 ;;
    --per-prompt) EVENT=UserPromptSubmit; shift ;;
    *) usage ;;
  esac
done
ROOT=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
git init -q "$T/main" && git -C "$T/main" -c user.name=s -c user.email=s@s commit -q --allow-empty -m seat
git -C "$T/main" worktree add -q "$T/unit" -b unit 2>/dev/null
git -C "$T/main" worktree add -q "$T/Chief-of-Staff" -b cos 2>/dev/null

over=0
# agent-awareness.sh prints a state once and remembers it: each seat gets an
# empty memory of its own, never the owner's, so every seat is measured whole.
measure() { # role
  local dir=$T/unit builder= cmd name bytes rc total=0
  case $1 in main) dir=$T/main ;; chief-of-staff) dir=$T/Chief-of-Staff ;; builder) builder=1 ;; esac
  while IFS= read -r cmd; do
    name=${cmd##*/hooks/}; name=${name%%\"*}
    # A hook that fails has no size: 0 bytes from it would pass the line it was never held to.
    rc=0
    (cd "$dir" && jq -cn --arg e "$EVENT" --arg d "$dir" '{hook_event_name: $e, source: "startup", prompt: "status?", session_id: "startup-size", cwd: $d}' \
      | CLAUDE_PROJECT_DIR=$ROOT COMMANDECK_BUILDER=$builder COMMANDECK_HOOK_FIRE_LOG=/dev/null COMMANDECK_RULING_LOG=$T/rulings.jsonl COMMANDECK_AWARENESS_DIR=$T/awareness-$1 \
        bash -c "$cmd" >"$T/out" 2>/dev/null) || rc=$?
    [ "$rc" = 0 ] || { echo "startup-size: $name failed as $1 (exit $rc), so its size is not known" >&2; over=1; }
    bytes=$(wc -c <"$T/out" | tr -d ' ')
    printf '%s\t%s\t%s\n' "$1" "$name" "$bytes"
    total=$((total + bytes))
    [ "$bytes" -le "$LIMIT" ] || { echo "startup-size: $name prints $bytes bytes as $1, over $LIMIT" >&2; over=1; }
  done < <(jq -r --arg e "$EVENT" --arg p "$PLUGIN" '.hooks[$e][]?.hooks[]?.command | gsub("\\$\\{CLAUDE_PLUGIN_ROOT\\}"; $p)' "$PLUGIN/hooks/hooks.json")
  printf '%s\ttotal\t%s\n' "$1" "$total"
  # Every turn carries the whole per-prompt sum, so the sum is held too.
  [ "$EVENT" != UserPromptSubmit ] || [ "$total" -le "$LIMIT" ] || { echo "startup-size: the per-prompt hooks print $total bytes as $1, over $LIMIT" >&2; over=1; }
}
for r in "${ROLES[@]}"; do [ -n "$ONLY" ] && [ "$r" != "$ONLY" ] || measure "$r"; done
exit "$over"

#!/usr/bin/env bash
# codex: skip -- guards main's own reads; Codex never sits in main.
# PreToolUse hook on Read|Grep|Glob: main does not open a worker's worktree
# (*/orca/workspaces/*). Main follows a build through the papers under the
# worktree's .claude/briefs/ (brief, evidence, round files), which stay open,
# and through the merge. Worker and reviewer panes are exempt. This is the one
# rule kept from the retired symbols-before-read.sh (owner ruling 2026-10-15).
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
[ "${COMMANDECK_REVIEWER:-}" = 1 ] && exit 0
CWD=$(jq -r '.cwd // empty' <<<"$INPUT"); CWD=${CWD:-$PWD}
# A linked worktree is a worker seat; only the main checkout is governed.
[ "$(git -C "$CWD" rev-parse --git-dir 2>/dev/null)" = "$(git -C "$CWD" rev-parse --git-common-dir 2>/dev/null)" ] || exit 0
# Each path resolved first (.., links, a Glob pattern against its own path): a briefs path can climb or link
# into the worker's code. Grep's pattern is a regex, not a path.
shopt -s nocasematch   # a Mac's disk takes a folder name in any letter case
python3 -c '
import json, os, sys
i = json.load(sys.stdin).get("tool_input") or {}
full = lambda p, base: os.path.realpath(os.path.join(base, os.path.expanduser(p)))
base = sys.argv[1]
if i.get("path"): base = full(i["path"], base); print(base)
if i.get("file_path"): print(full(i["file_path"], sys.argv[1]))
if i.get("pattern") and sys.argv[2] == "Glob": print(full(i["pattern"], base))
' "$CWD" "$(jq -r '.tool_name // empty' <<<"$INPUT")" <<<"$INPUT" | while IFS= read -r p; do
  case $p in */orca/workspaces/*/.claude/briefs|*/orca/workspaces/*/.claude/briefs/*) continue ;; */orca/workspaces/*) ;; *) continue ;; esac
  echo "BLOCKED: main does not read a worker's worktree: $p. Read the Builder's papers under that worktree's .claude/briefs/ (brief, evidence, round files), or ask the Builder." >&2
  exit 2
done

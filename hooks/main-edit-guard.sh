#!/usr/bin/env bash
# PreToolUse hook on Edit|Write|MultiEdit: on the MAIN checkout, block edits to
# project code. Main orchestrates; every code diff is written by a Builder in
# its own worktree.
#
# Everything under `.claude/` is exempt, so briefs, config, rules, plans and
# checkpoints are still main's to edit directly, and so are docs and any *.md.
#
# Worker panes are exempt by construction: they run in a linked git worktree and
# the git-dir test below only fires in the main checkout. Same test as
# context-line.sh, for the same reason.
# Self-test: bash hooks/__tests__/main-edit-guard.test.sh
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
source "$(dirname "${BASH_SOURCE[0]}")/lib/edit-payload.sh" 2>/dev/null
# A guard that cannot read the payload must NOT pass the write: see the load
# sentinel at the bottom of lib/edit-payload.sh.
hook_payload_loaded 2>/dev/null || { echo "BLOCKED: ${BASH_SOURCE[0]##*/} could not load hooks/lib/edit-payload.sh, so it cannot screen this write. Reinstall the plugin and retry." >&2; exit 2; }

# A linked worktree is a worker; only the main checkout is governed.
COMMON=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
[ -n "$COMMON" ] && [ "$(git rev-parse --path-format=absolute --git-dir 2>/dev/null)" = "$COMMON" ] || exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
# The launcher by its own path: the plugin is not in the project.
LAUNCH=${BASH_SOURCE[0]%/*}/../scripts/builder-launch.sh
[ -n "$FILE_PATH" ] || exit 0

# AT MOST 3 FILES PER UNCOMMITTED CHANGE SET (owner ruling 2026-10-01). Main typing
# a multi-file diff itself is the waste this cuts. Counted: tracked files
# modified vs HEAD plus this one, outside briefs, rules, todo, docs, memory and
# *.md. It sits above the carve-outs on purpose: `.claude/` counts here, and
# neither escape hatch lifts it.
TOP=$(git rev-parse --show-toplevel 2>/dev/null)
counted() { case "$1" in .claude/briefs/*|.claude/rules/*|todo/*|docs/*|*memory/*|*.md) return 1 ;; esac; }
case "$FILE_PATH" in "$TOP"/*)
  REL=${FILE_PATH#"$TOP"/}
  if counted "$REL"; then
    # batch_paths: the other files of one Codex patch (codex-dispatch.sh), not written yet.
    N=$( { git -C "$TOP" diff --name-only HEAD 2>/dev/null; echo "$REL"
           echo "$INPUT" | jq -r '.tool_input.batch_paths[]?' 2>/dev/null | while IFS= read -r p; do case $p in "$TOP"/*) echo "${p#"$TOP"/}" ;; esac; done; } | sort -u \
      | while IFS= read -r f; do counted "$f" && echo "$f"; done | wc -l)
    if [ "$N" -gt 3 ]; then
      echo "BLOCKED: hand this edit to a worker: write the batch brief, then $LAUNCH <unit> <batch-brief>. It would be file $N of main's uncommitted change set (cap 3, outside .claude/briefs/, .claude/rules/, todo/, docs/, memory and *.md); or commit what is done first." >&2
      echo "Do not retry it through Bash (sed -i, a redirect, tee)." >&2
      exit 2
    fi
  fi ;;
esac

# Exempt by where the file sits in ITS OWN checkout: a worktree kept under
# .claude/worktrees/, or a checkout under a folder named docs, is code all the same.
D=${FILE_PATH%/*}
while [ -n "$D" ] && [ ! -d "$D" ]; do D=${D%/*}; done
FTOP=$(git -C "${D:-/}" rev-parse --show-toplevel 2>/dev/null) || FTOP=
case "$FILE_PATH" in "${FTOP:-/no checkout}"/*) IN=/${FILE_PATH#"$FTOP"/} ;; *) IN=$FILE_PATH ;; esac
case "$IN" in
  */.claude/*|*/.githooks/*|*/.agents/*) exit 0 ;;
  */docs/*|*/todo/*|*.md) exit 0 ;;
esac

# Project code is any other file of THIS project: in the main checkout, or in
# one of its worktrees -- main reaching into a worktree to "just fix it" is the
# same violation wearing a longer path. A file of no repo, or of another one,
# is not this hook's.
[ "$(git -C "${D:-/}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" = "$COMMON" ] || exit 0

# The escape hatch is per-session and has to be typed on purpose: a
# mechanism-caused stop is fixed the same turn (owner ruling 2026-09-12).
[ -n "${COMMANDECK_MAIN_EDITS_OK:-}" ] && exit 0
# This file, kept out of git, turns the guard off for the project.
[ -f "${CLAUDE_PROJECT_DIR:-.}/.claude/approvals/main-edits-ok" ] && exit 0

echo "BLOCKED: hand this edit to a worker: write the batch brief, then $LAUNCH <unit> <batch-brief>. Main does not edit project code: $FILE_PATH is in this project's checkout or one of its worktrees." >&2
echo "Do not retry it through Bash (sed -i, a redirect, tee)." >&2
echo "Still main's to edit directly: everything under .claude/ (briefs, config, rules, plans), docs/, todo/, any *.md, checkpoints, memory and the scratchpad." >&2
echo "If this really is a same-turn mechanism fix that a Builder cannot make: COMMANDECK_MAIN_EDITS_OK=1 (owner ruling 2026-09-12)." >&2
exit 2

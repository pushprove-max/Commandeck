#!/usr/bin/env bash
# SessionStart (matcher: compact|clear): print the checkpoint the session wrote
# before compaction so the model resumes from its own note. After a /clear (main
# restarts itself at batch boundaries) the note is printed and KEPT: the same
# session id continues and the next clear or compaction rewrites it.
#
# Stands down while the user's settings.json registers its own compact-readback.sh
# command (${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json): it would run twice.
#
# A compacted main must restart: on the strict tier under Orca, a compaction of
# main touches <sid>.handoff, the below-the-line path of context-clear-stop.sh, so
# the next stop restarts main from the checkpoint, or first asks for one. Only a
# checkpoint a replacement already took (<sid>.md.delivered, newer than the
# checkpoint, written by hooks/resume-context.sh) is spent; any other is the
# pending restart's input. The checkpoint prints at most 9000 bytes and a pointer.
# Retire when: Claude Code re-reads the checkpoint after a compact
set -euo pipefail
input=$(cat)
HERE=${BASH_SOURCE[0]%/*}
. "$HERE/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$input" SessionStart
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
[ -n "$sid" ] || exit 0
if jq -e '[.. | .command? | strings | select(endswith("compact-readback.sh"))] | length > 0' \
  "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" >/dev/null 2>&1; then exit 0; fi
ckpt="$HOME/.claude/checkpoints/$sid.md"
src=$(printf '%s' "$input" | jq -r '.source // empty')
delivered=0
if [ -s "$ckpt" ] && [ "$ckpt.delivered" -nt "$ckpt" ]; then delivered=1; fi
# Linked worktrees are workers, never restarted; the restart needs Orca and the strict tier.
if [ "$src" = compact ] && [ "$delivered" = 0 ] && [ -n "${ORCA_TERMINAL_HANDLE:-}" ] \
  && [ "$(git rev-parse --git-dir 2>/dev/null)" = "$(git rev-parse --git-common-dir 2>/dev/null)" ] \
  && { . "$HERE/lib/project.sh" && pp_strict; } 2>/dev/null; then
  mkdir -p "$HOME/.claude/checkpoints"
  touch "$HOME/.claude/checkpoints/$sid.handoff"
fi
[ -s "$ckpt" ] || exit 0
echo "# Checkpoint written before ${src:-compaction} (resume from here; do not re-litigate its decisions)"
head -c 9000 "$ckpt"
[ "$(wc -c < "$ckpt")" -le 9000 ] || printf '\n[cut at 9000 bytes; the full checkpoint is %s]\n' "$ckpt"
[ "$src" = clear ] && exit 0
[ "$delivered" = 1 ] && rm -f "$ckpt"
exit 0

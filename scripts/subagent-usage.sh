#!/usr/bin/env bash
# subagent-usage.sh -- append one row per finished Claude subagent run to
# .claude/metrics/subagent-usage.jsonl: {agentId, agentType, description, session,
# project, model, tokens, finishedAt, recordedAt}. dashboard.sh runs it each collect.
# Reads the main checkout's sessions and every worktree's under ~/.claude/projects
# (COMMANDECK_CLAUDE_PROJECTS in tests). A transcript written in the last 10
# minutes may still be running and waits for a later collect; a run already in
# the ledger is parsed again only when its transcript was written since (a run
# that went on), and then gets a new row with the whole total: a reader takes
# a run's LAST row. Token parsing is seat-event.sh's.
set -uo pipefail
HERE=$(dirname "${BASH_SOURCE[0]}")
. "$HERE/paths.sh" || exit 1
PROJECTS=${COMMANDECK_CLAUDE_PROJECTS:-$HOME/.claude/projects}
FILE=$PP_MAIN/.claude/metrics/subagent-usage.jsonl
mkdir -p "$(dirname "$FILE")"
# One collect at a time: two that read the same SEEN would both append a run.
exec 9>>"$FILE.lock" && flock 9 || { echo "subagent-usage: no lock on $FILE.lock; nothing recorded" >&2; exit 0; }
SEEN=$(jq -r '"\(.agentId) \(.finishedAt)"' "$FILE" 2>/dev/null)
NOW=$(date +%s)
for f in "$PROJECTS/$PP_MAIN_SLUG"/*/subagents/agent-*.jsonl "$PROJECTS/$PP_WORKSPACES_SLUG"-*/*/subagents/agent-*.jsonl; do
  [ -f "$f" ] || continue
  # The worktree pattern also matches a project whose folder name starts with
  # this one's (ws-private): a run is this project's by where it ran.
  # shortcut: a transcript with no cwd is taken by its folder name alone.
  cwd=$(grep -m1 -o '"cwd":"[^"]*"' "$f" | cut -d'"' -f4)
  case $cwd in ''|"$PP_MAIN"|"$PP_MAIN"/*|"$PP_WORKSPACES"/*) ;; *) continue ;; esac
  id=${f##*/agent-}; id=${id%.jsonl}
  mtime=$(stat -c %Y "$f") && [ $((NOW - mtime)) -ge 600 ] || continue
  ! grep -qxF -- "$id $(date -u -d "@$mtime" +%Y-%m-%dT%H:%M:%SZ)" <<<"$SEEN" || continue
  usage=$(bash "$HERE/seat-event.sh" --usage claude "$f" 2>/dev/null) || usage=null
  meta=${f%.jsonl}.meta.json; [ -f "$meta" ] || meta=/dev/null
  dir=${f%/subagents/*}
  jq -cn --arg id "$id" --arg session "${dir##*/}" --arg project "$(basename "$(dirname "$dir")")" \
    --argjson usage "${usage:-null}" --slurpfile m "$meta" --argjson mtime "$mtime" \
    '{agentId: $id, agentType: ($m[0].agentType // null), description: ($m[0].description // null),
      session: $session, project: $project, model: ($usage.model // null), tokens: ($usage.tokens // null),
      finishedAt: ($mtime | todate), recordedAt: (now | floor | todate)}' >> "$FILE" \
    || echo "subagent-usage: no row for $f" >&2
done
exit 0

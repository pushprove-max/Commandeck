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
# --start: read-only; prints, per agentType, the runs and the median and p90 of
# each run's first request input (input + cache creation + cache read): what a
# helper costs before it does anything.
set -uo pipefail
HERE=$(dirname "${BASH_SOURCE[0]}")
. "$HERE/paths.sh" || exit 1
PROJECTS=${COMMANDECK_CLAUDE_PROJECTS:-$HOME/.claude/projects}
FILE=$PP_MAIN/.claude/metrics/subagent-usage.jsonl
# Every transcript of the main checkout and its worktrees, "mtime<TAB>path". A pattern that matched nothing is no
# file, and stat skips it.
transcripts() { stat -c $'%Y\t%n' -- "$PROJECTS/$PP_MAIN_SLUG"/*/subagents/agent-*.jsonl "$PROJECTS/$PP_WORKSPACES_SLUG"-*/*/subagents/agent-*.jsonl 2>/dev/null; }
# The worktree pattern also matches a project whose folder name starts with this one's (ws-private): a run is this
# project's by where it ran.
# shortcut: a transcript with no cwd is taken by its folder name alone.
ours() { local cwd; cwd=$(grep -m1 -o '"cwd":"[^"]*"' "$1" | cut -d'"' -f4)
  case $cwd in ''|"$PP_MAIN"|"$PP_MAIN"/*|"$PP_WORKSPACES"/*) return 0 ;; esac; return 1; }
if [ "${1:-}" = --start ]; then
  while IFS=$'\t' read -r _ f; do
    ours "$f" || continue
    meta=${f%.jsonl}.meta.json; [ -f "$meta" ] || meta=/dev/null
    jq -cn --slurpfile m "$meta" 'first(inputs | select(.type == "assistant" and .message.usage != null) | .message.usage)
      | {type: ($m[0].agentType // "unknown"), input: ((.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))}' "$f" 2>/dev/null
  done < <(transcripts) | jq -rs 'group_by(.type)[] | (map(.input) | sort) as $v | ($v | length) as $n
    | "\(.[0].type): \($n) runs, median \(if $n % 2 == 1 then $v[($n - 1) / 2] else ($v[$n / 2 - 1] + $v[$n / 2]) / 2 end), p90 \($v[($n * 0.9 | ceil) - 1])"'
  exit 0
fi
mkdir -p "$(dirname "$FILE")"
# One collect at a time: two that read the same SEEN would both append a run.
exec 9>>"$FILE.lock" && flock 9 || { echo "subagent-usage: no lock on $FILE.lock; nothing recorded" >&2; exit 0; }
# Each run's latest row: its id and the transcript time that row read.
SEEN=$(jq -rs 'group_by(.agentId)[] | "\(.[0].agentId)\t\(map(.finishedAt | fromdateiso8601) | max)"' "$FILE" 2>/dev/null)
NOW=$(date +%s)
# One stat and one awk over every transcript pick the ones to parse: a stat, a grep and a date per file is
# seconds a collect on hundreds of transcripts with nothing new.
while IFS=$'\t' read -r mtime f; do
  ours "$f" || continue
  id=${f##*/agent-}; id=${id%.jsonl}
  usage=$(bash "$HERE/seat-event.sh" --usage claude "$f" 2>/dev/null) || usage=null
  meta=${f%.jsonl}.meta.json; [ -f "$meta" ] || meta=/dev/null
  dir=${f%/subagents/*}
  jq -cn --arg id "$id" --arg session "${dir##*/}" --arg project "$(basename "$(dirname "$dir")")" \
    --argjson usage "${usage:-null}" --slurpfile m "$meta" --argjson mtime "$mtime" \
    '{agentId: $id, agentType: ($m[0].agentType // null), description: ($m[0].description // null),
      session: $session, project: $project, model: ($usage.model // null), tokens: ($usage.tokens // null),
      finishedAt: ($mtime | todate), recordedAt: (now | floor | todate)}' >> "$FILE" \
    || echo "subagent-usage: no row for $f" >&2
done < <(transcripts \
  | awk -F'\t' -v now="$NOW" 'NR == FNR { seen[$1] = $2; next }
      { id = $2; sub(/.*\/agent-/, "", id); sub(/\.jsonl$/, "", id) }
      now - $1 >= 600 && (!(id in seen) || $1 > seen[id])' <(printf '%s\n' "$SEEN") -)
exit 0

#!/usr/bin/env bash
#
# await-agents.sh -- block until dispatched agent work lands, then say what and exit.
#
# Why this exists : Orca never pushes into the main
# session. A `worker_done` sits in the delivery queue until main asks for it,
# and a Codex reviewer cannot send one at all -- its read-only sandbox blocks
# the Orca RPC, so its only completion signal is its pane going idle. The result
# was that main learned about finished work only when a human typed "poll".
#
# Run this with the Bash tool's run_in_background. The harness re-invokes the
# main session when a background command exits, so this turns "ask and wait"
# into "be told". Main relaunches it after handling whatever it reports.
#
# It never acknowledges or consumes anything: it reports that something is
# waiting and exits, leaving main to read and ack.
#
# Usage: await-agents.sh [max_seconds] [worktree_regex]
# max_seconds defaults to 2700; the regex defaults to every worktree. Pass the
# units main is actually waiting on -- a long-lived unrelated worktree whose
# agent state flaps otherwise wakes main repeatedly about work it is not
# tracking, which makes the watcher useless exactly when it matters.
set -uo pipefail
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "${0}"; exit 0 ;; esac

MAX="${1:-2700}"
ONLY="${2:-.}"
INTERVAL="${AWAIT_AGENTS_INTERVAL:-20}"
STARTED=$(date +%s)

for bin in orca-ide jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "AWAIT: $bin is not on PATH; cannot watch."; exit 0; }
done
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || { echo "AWAIT: paths.sh did not load; cannot watch."; exit 0; }

# One line per agent, "<worktree>/<agentType> <paneKey>=<state>", sorted.
# Same source the agent-awareness hook uses, so the two never disagree.
#
# The paneKey is in the key, not decoration: a worktree routinely holds two
# agents of the same type (a finished implementer and a live fix worker), and
# keying on worktree+type alone collapses them into one row whose state flaps
# between them. That fired a wake every poll on 2026-08-31.
snapshot() {
  timeout 8 orca-ide worktree ps --json 2>/dev/null | jq -r '
    .result.worktrees[]? | select(.isMainWorktree != true) | select(.isArchived != true)
    | .displayName as $w
    | ((.agents // [])[] | "\($w)/\(.agentType) \(.paneKey)=\(.state)")' 2>/dev/null \
    | grep -E "$ONLY" | sort
}

BASE=$(snapshot)

while :; do
  if [ $(( $(date +%s) - STARTED )) -ge "$MAX" ]; then
    echo "AWAIT: nothing landed within ${MAX}s. Relaunch me if work is still running."
    exit 0
  fi

  # 1) Anything an agent actually sent. Heartbeats do not count as news.
  #
  # AWAIT_AGENTS_SKIP_MESSAGES=1 turns this branch off. A delivery whose run has
  # gone can refuse every ack -- "does not belong to this Run" -- and then sits
  # in the queue forever, waking the watcher on the same read message every
  # poll and making it useless exactly when work is running. Read the message,
  # act on it, then set this for the rest of the wave.
  # Issue 642: only a message the one wake rule calls actionable for main counts (pp_inbox_actionable: now, or a
  # batch that is due), read off the inbox page, which marks nothing read: a consuming check here took main's mail
  # from its drain. A failed or junk read is no news.
  msgs=0
  [ "${AWAIT_AGENTS_SKIP_MESSAGES:-0}" = "1" ] || \
  msgs=$(pp_inbox_actionable "$(tr -d '[:space:]' 2>/dev/null < "$PP_RUN_FILE")" "${ORCA_TERMINAL_HANDLE:-}" | jq -r 'if type == "array" then length else 0 end' 2>/dev/null)
  if [ -n "${msgs:-}" ] && [ "${msgs:-0}" -gt 0 ] 2>/dev/null; then
    echo "AWAIT: ${msgs} message(s) waiting -- worker_done, question or escalation."
    echo "Read them: orca-ide orchestration check --timeout-ms 5000 --json"
    exit 0
  fi

  # 2) An agent that went idle without sending anything. This is the only
  #    signal a Codex reviewer can give, so it is not a fallback, it is the
  #    primary path for every Sol and Luna pane.
  NOW=$(snapshot)

  # An empty snapshot means the RPC timed out or the runtime blinked, NOT that
  # every agent vanished. Diffing against it makes every row look new on the
  # next poll, which fired the same wake twice in a row on 2026-08-31. Keep the
  # last good baseline and try again.
  [ -z "$NOW" ] && { sleep "$INTERVAL"; continue; }

  # Report only a real TRANSITION: the same agent was present and NOT done
  # before, and is done now. A row that merely appears is not news -- it is a
  # poll that previously missed it.
  newly=$(awk -F= '
    NR==FNR { was[$1]=$2; next }
    $2=="done" && ($1 in was) && was[$1]!="done" { print $1"="$2 }
  ' <(printf '%s\n' "$BASE") <(printf '%s\n' "$NOW"))
  # A Claude pane that is idle but still owns a background shell or monitor is
  # WAITING, not finished -- its status line says "N shells, M monitor". The
  # triage worker sat like that for an hour on 2026-09-03 and woke main eight
  # times for nothing, each wake a full main turn. Such a row is dropped from
  # the wake and folded into the baseline, so the next real transition still
  # fires.
  if [ -n "$newly" ]; then
    keep=""
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      kind=${row#*/}; kind=${kind%% *}; wt=${row%%/*}
      if [ "$kind" = claude ]; then
        busy=$(timeout 8 orca-ide terminal list --json 2>/dev/null \
          | jq -r --arg wt "$wt" '.result.terminals[]? | select(.agentIdentity != null)
              | select(.worktreePath | endswith("/" + $wt)) | .handle' 2>/dev/null \
          | while read -r h; do
              grep -qE '[0-9]+ (shell|monitor)s?\b' <<<"$(timeout 8 orca-ide terminal read --terminal "$h" --screen --json 2>/dev/null \
                | jq -r '.result.terminal.tail[]?' 2>/dev/null)" && echo busy
            done | head -1)
        [ "$busy" = busy ] && continue
      fi
      keep+="$row"$'\n'
    done <<<"$newly"
    newly=${keep%$'\n'}
  fi
  if [ -n "$newly" ]; then
    echo "AWAIT: an agent finished without sending a message:"
    printf '%s\n' "$newly"
    echo "A Codex reviewer cannot send one. Read its verdict from the pane buffer:"
    echo "  orca-ide terminal read --terminal <handle> --cursor 0 --limit 100000 --json"
    exit 0
  fi
  BASE="$NOW"

  sleep "$INTERVAL"
done

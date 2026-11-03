#!/usr/bin/env bash
# repeat-report.sh [--since <hours>, default 24] -- count repeated friction from
# machine traces, so main turns the top items into fixes at a checkpoint.
# Counting, not a model re-reading the run: no model call, only jq/sort/uniq.
#
# Sources, each filtered to the window:
#   hook blocks    ${CLAUDE_CONFIG_DIR:-~/.claude}/projects/$PP_MAIN_SLUG/*.jsonl tool results carrying
#                  "...run-hook.sh hooks/<name>.sh]: BLOCKED: <reason>",
#                  reason cut at its first sentence end
#   bash commands  the same logs, absolute paths,
#                  hashes and numbers collapsed so the same command on two
#                  worktrees, or with another `tail -N`, counts once
#   re-read files  the same logs: Read, and cat/sed/head of one path
#   ruling topics  the project's ruling log (COMMANDECK_RULING_LOG), questions asked more than once
# Stdout is the top 5 of each; every count lands in $PP_SCRATCH/repeat-report.txt.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || exit 1
. "$(dirname "${BASH_SOURCE[0]}")/../hooks/lib/project.sh" && pp_project

HOURS=24
case ${1:-} in
  --since) HOURS=${2:?--since needs hours} ;;
  -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
  '') ;;
  *) echo "repeat-report.sh: unknown argument $1" >&2; exit 2 ;;
esac
SINCE=$(date -u -d "-$HOURS hours" +%FT%TZ)
RULINGS=${COMMANDECK_RULING_LOG:-$HOME/.claude/rulings/$PP_PROJECT.jsonl}
PROJ=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$PP_MAIN_SLUG
RAW=$PP_SCRATCH/repeat-report.txt
mkdir -p "$PP_SCRATCH"

# Absolute paths only: a relative one (.claude/scripts/seat.sh) names WHICH
# script, and collapsing it merged every script into one row.
norm() { sed -E 's#(^|[ ="'"'"'])(/[^/ "'"'"']+)+/?#\1<path>#g; s/\b[0-9a-f]{8,}\b/<hash>/g; s/[0-9]+/N/g' | cut -c1-120; }
# The same file read from main and from a worktree is one file.
unroot() { sed -E "s#^($PP_MAIN|$PP_WORKSPACES/[^/]+)/##"; }
# Counts lines on stdin, keeps those seen at least $1 times, most first.
count() { sort | uniq -c | sort -k1,1nr -k2 | awk -v min="$1" '$1 >= min { n = $1; sub(/^ *[0-9]+ /, ""); print n, $0 }'; }

TOOLS=$(find "$PROJ" -maxdepth 1 -name '*.jsonl' -mmin -$((HOURS * 60)) -print0 2>/dev/null \
  | xargs -0r cat | jq -r --arg s "$SINCE" '
      select((.timestamp // "") >= $s)
      | if .type == "assistant" then .message.content[]? | select(.type == "tool_use")
          | if .name == "Bash" then "B\t" + (.input.command // "" | gsub("\n"; " "))
            elif .name == "Read" then "R\t" + (.input.file_path // "") else empty end
        elif .type == "user" then .message.content[]? | select(.type == "tool_result")
          | .content | (if type == "array" then map(.text? // "") | join("\n") else . end) | strings
          | scan("run-hook\\.sh hooks/([^/\\]]+\\.sh)\\]: BLOCKED: ([^\\n]*)")
          | "H\t\(.[0]): \(.[1] | sub("\\.\\s.*$"; "."))"
        else empty end' 2>/dev/null)

{
  echo "== hook blocks"
  printf '%s\n' "$TOOLS" | sed -n 's/^H\t//p' | norm | count 1
  echo "== repeated bash commands"
  printf '%s\n' "$TOOLS" | sed -n 's/^B\t//p' | norm | count 2
  echo "== re-read files"
  # The path is the last word before any pipe; a multi-file cat counts its last file only.
  { printf '%s\n' "$TOOLS" | sed -n 's/^R\t//p'
    printf '%s\n' "$TOOLS" | sed -n 's/^B\t//p' | grep -E '^(cat|sed|head) ' | sed 's/[|;&].*//' \
      | awk '{ gsub(/["'"'"']/, "", $NF); print $NF }'
  } | grep . | unroot | count 2
  echo "== ruling topics asked more than once"
  # Line by line: a damaged line is skipped, never the end of the read.
  [ -f "$RULINGS" ] && jq -rR --arg s "$SINCE" 'fromjson? | select(.source == "ask" and .utc >= $s) | .question' "$RULINGS" 2>/dev/null \
    | tr 'A-Z' 'a-z' | cut -c1-80 | count 2
} > "$RAW"

echo "repeat-report, last ${HOURS}h (all counts: $RAW)"
awk '/^== / { if (h && !n) print "  none"; print substr($0, 4); h = 1; n = 0; next }
     { if (n < 5) print "  " $0; n++ }
     END { if (h && !n) print "  none" }' "$RAW"

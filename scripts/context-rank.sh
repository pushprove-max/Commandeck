#!/usr/bin/env bash
# context-rank.sh <session.jsonl>... -- rank what fills a coordinator pane (issue 608). Reads Claude Code session logs
# (one JSON row per line, types user/assistant) and prints, largest first, the top 20 per kind:
#   bytes<TAB>count<TAB>share%<TAB>kind<TAB>key
# kind call = a tool_use's input; result = the tool_result matched to it by id; message = a user row that holds text,
# not a tool_result. Key = the tool name, plus the script basename for Bash; a message's key is its first word.
# share% is of that kind's total. context-overhead.sh replays hook output only and reads no session log, hence this file.
# --session main|relay ranks the newest log of the main checkout, or of the relay's Chief-of-Staff worktree, from the
# project folder named by that path's slug under the Claude config dir or any Orca claude-profiles home.
# shortcut: a typed prompt is not told from an inbound message.
set -uo pipefail
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
if [ "${1-}" = --session ]; then
  . "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || exit 1
  case ${2-} in main) d=$PP_MAIN ;; relay) d=$PP_WORKSPACES/Chief-of-Staff ;; *) echo "usage: context-rank.sh --session main|relay" >&2; exit 2 ;; esac
  s=$(pp_slug "$d")
  log=$(ls -t "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$s"/*.jsonl \
    "$HOME/Library/Application Support/orca/claude-profiles"/*/home/projects/"$s"/*.jsonl 2>/dev/null | head -1)
  [ -n "$log" ] || { echo "context-rank: no session log for $2 ($d)" >&2; exit 1; }
  echo "context-rank: $log" >&2
  set -- "$log"
fi
[ $# -gt 0 ] || { echo "usage: context-rank.sh <session.jsonl>... | --session main|relay" >&2; exit 2; }
rc=0
for f in "$@"; do [ -r "$f" ] || { echo "context-rank: cannot read log: $f" >&2; rc=1; }; done
[ "$rc" = 0 ] || exit 1
jq -nr '
  def text: if type == "string" then . else ([.[]? | .text? // empty] | join("")) end;
  def key: if .name == "Bash" then "Bash " + ((.input.command // "") | capture("(?<s>[^ /]+\\.sh)") .s // "") | rtrimstr(" ")
           else .name end;
  reduce (inputs | select(type == "object")) as $r ({ids: {}, rows: []};
    # A row with no message (cost-state, summary) leaves the state as it is: `empty` here would reset it to null.
    ($r.message.content? // null) as $c
    | if $c == null then .
      elif ($c | type) == "string" then
        .rows += [{kind: "message", key: ($c | split(" ")[0]), bytes: ($c | utf8bytelength)}]
      else
        reduce $c[]? as $b (.;
          if $b.type == "tool_use" then
            .ids[$b.id] = ($b | key)
            | .rows += [{kind: "call", key: ($b | key), bytes: ($b.input | tojson | utf8bytelength)}]
          elif $b.type == "tool_result" then
            .rows += [{kind: "result", key: (.ids[$b.tool_use_id] // "unknown"), bytes: ($b.content | text | utf8bytelength)}]
          elif $b.type == "text" and $r.type == "user" then
            .rows += [{kind: "message", key: ($b.text | split(" ")[0]), bytes: ($b.text | utf8bytelength)}]
          else . end)
      end)
  | .rows | group_by(.kind) | .[]
  | (map(.bytes) | add) as $total
  | group_by(.key) | map({kind: .[0].kind, key: .[0].key, bytes: (map(.bytes) | add), count: length})
  | sort_by(-.bytes) | .[:20][]
  | [.bytes, .count, (if $total > 0 then (.bytes * 1000 / $total | round / 10) else 0 end), .kind, .key] | @tsv
' "$@"

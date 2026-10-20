#!/usr/bin/env bash
# unit-cost.sh <unit> [since 'YYYY-MM-DD HH:MM'] -- what a unit's worker panes
# cost, from their own transcripts. One line per session and a total:
# turns, tool calls, cache-read Mtok (the bill), output ktok, suite/tsc runs,
# reruns of an unchanged tree, hook-blocked calls, shell reads, serena and
# codebase-memory calls beside shell searches. A session with no MCP call and
# 10+ shell searches is marked MCP UNUSED.
# cold/coldK (issue 203): replies that came more than the session's own cache
# TTL (300 s, or 3600 s once it wrote 1-hour cache) after the previous reply and
# wrote more cache than they read, and the ktokens they wrote. A session with
# helpers (<session>/subagents/agent-*.jsonl) gets one helper line: helpers,
# helpers over 20 tool calls, final answers over 15 lines, and searches (a Grep
# or quoted rg/grep pattern, or a Read path) an earlier helper of the session
# already ran. A session with no helpers prints no helper line.
#
# Why: a rule about worker cost needs the same numbers each time to show it held.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
UNIT=${1:?unit}
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || exit 1
SINCE=${2:-$(date -d '2 days ago' '+%Y-%m-%d %H:%M')}   # after paths.sh: a Mac's own date has no -d
D="$HOME/.claude/projects/$PP_WORKSPACES_SLUG-$UNIT"
# No Claude transcript is not the end: a unit Codex panes worked on is billed below.
files=; [ ! -d "$D" ] || files=$(find "$D" -maxdepth 1 -name '*.jsonl' -newermt "$SINCE" | sort)
[ -n "$files" ] || echo "CLAUDE     no sessions for $UNIT since $SINCE in $D" >&2

JQ='
def txt: if type=="string" then . elif type=="array" then (map(if type=="string" then . else (.text // "") end)|join(" ")) else tostring end;
def suite: test("npm (run )?(test|typecheck|build)|tsc|vitest|node --test");
def ts: .timestamp | sub("\\.[0-9]+"; "") | fromdateiso8601;
def rk: .message.id // .uuid | tostring;
(map(select(.timestamp)) | sort_by(.timestamp)) as $m
| ($m | map(select(.type=="assistant"))) as $lines
| ([ $lines[] | .message.content[]? | select(.type=="tool_use") ]) as $uses
# One reply is one line per content block, each repeating message.usage.
| ($lines | group_by(.message.id // .uuid) | map(.[-1]) | sort_by(.timestamp)) as $a
| (if any($a[]; (.message.usage.cache_creation.ephemeral_1h_input_tokens // 0) > 0) then 3600 else 300 end) as $ttl
# The TTL runs from request start: a reply is timed from the user row before its first block, or that block when there
# is none. Timing from the last block would subtract the previous reply streaming time from the gap.
| (reduce $m[] as $r ({u: null, s: {}};
      if $r.type == "user" then .u = $r
      elif $r.type == "assistant" then ($r | rk) as $k | if .s[$k] == null then .s[$k] = ((.u // $r) | ts) | .u = null else . end
      else . end) | .s) as $start
| ([ range(1; $a|length) as $i | $a[$i]
      | select($start[rk] - $start[$a[$i-1] | rk] > $ttl and (.message.usage.cache_creation_input_tokens // 0) > (.message.usage.cache_read_input_tokens // 0))
      | .message.usage.cache_creation_input_tokens ]) as $cold
| ([ $m[] | select(.type=="user") | .message.content[]? | select(.type=="tool_result") ]) as $res
| ($uses | map(select(.name=="Bash" and ((.input.command // "")|suite)) | .input.command
      | sub("^[[:space:]]*cd [^;&|]*(&&|;)[[:space:]]*";"") | sub("[[:space:]]*(2>&1|[0-9]?>>?[[:space:]]*[^[:space:]|;&]+|\\|.*)";"") | gsub("[[:space:]]+";" "))) as $runs
| {
  turns: ($a|length),
  tools: ($uses|length),
  cache_read_M: ((($a | map(.message.usage.cache_read_input_tokens // 0) | add) / 1000000 * 10 | round) / 10),
  output_k: (($a | map(.message.usage.output_tokens // 0) | add) / 1000 | floor),
  ctx_avg_k: (if ($a|length)>0 then (($a | map(.message.usage.cache_read_input_tokens // 0) | add) / ($a|length) / 1000 | floor) else 0 end),
  suite_runs: ($runs|length),
  same_cmd_repeats: ($runs | group_by(.) | map(length-1) | add // 0),
  hook_blocks: ($res | map(select(.is_error==true and ((.content|txt)|test("BLOCKED")))) | length),
  shell_reads: ($uses | map(select(.name=="Bash" and ((.input.command // "")|test("^\\s*(cat|sed -n|head|tail) ")))) | length),
  serena: ($uses | map(select(.name|startswith("mcp__serena__"))) | length),
  cbm: ($uses | map(select(.name|test("^mcp__codebase[-_]memory__"))) | length),
  cold: ($cold|length),
  cold_k: (($cold|add // 0) / 1000 | floor),
  # The same shell-search shape read-tracker.sh counts for its live tripwire.
  shell_searches: ($uses | map(select(.name=="Bash" and ((.input.command // "")|test("(^|[;&|(])\\s*(rg|grep|cat|sed\\s+-n)\\s")))) | length)
}
| .mcp_flag = (if .serena + .cbm == 0 and .shell_searches >= 10 then "MCP UNUSED" else "" end)'
if [ -n "$files" ]; then
printf '%-10s %6s %6s %9s %8s %7s %6s %7s %6s %6s %6s %5s %6s %5s %6s\n' session turns tools cacheMtok out_k ctx_avgk suites repeat blocks shreads serena cbm shsrch cold coldK
# Claude Code 2.1.300's api-request rows, a third or more of a long log, are no turn: dropped before jq parses them.
API='^{"type":"api-request'
# One helper's searches, call count and final answer's line count, from its own transcript.
HJQ='
def skeys: .message.content[]? | select(.type=="tool_use")
  | if .name=="Grep" then "p:" + (.input.pattern // "")
    elif .name=="Read" then "r:" + (.input.file_path // "")
    elif .name=="Bash" then ((.input.command // "") | capture("(?:^|[;&|(])\\s*(?:rg|grep)\\s[^\"\\x27]*[\"\\x27](?<p>[^\"\\x27]+)[\"\\x27]") | "p:" + .p)
    else empty end;
map(select(.timestamp)) as $m
| ($m | map(select(.type=="assistant"))) as $l
| ($l | group_by(.message.id // .uuid) | map({t: .[0].timestamp, c: map(.message.content[]?)}) | sort_by(.t)) as $replies
| {t: ($m | map(.timestamp) | min),
   lines: ([ $replies[] | select(any(.c[]; .type=="tool_use") | not) | select(any(.c[]; .type=="text")) ] | last // {c: []}
     | .c | map(select(.type=="text") | .text) | join("\n") | sub("\\s+$"; "") | if . == "" then 0 else split("\n") | length end),
   calls: ([ $l[] | .message.content[]? | select(.type=="tool_use") ] | length),
   keys: ([ $l[] | skeys ] | unique)}'
# A search is repeated when an earlier helper of the same session already ran it.
HSUM='sort_by(.t) | reduce .[] as $h ({seen: [], n: 0, o20: 0, o15: 0, rep: 0};
    .seen as $s | .rep += ($h.keys | map(select(IN($s[]))) | length) | .seen = ((.seen + $h.keys) | unique)
    | .n += 1 | .o20 += (if $h.calls > 20 then 1 else 0 end) | .o15 += (if $h.lines > 15 then 1 else 0 end))
| [.n, .o20, .o15, .rep] | @tsv'
COLD=0 COLDK=0 HN=0 H20=0 H15=0 HR=0
for f in $files; do
  row=$(grep -v "$API" "$f" | jq -s -r --arg s "$(basename "$f" .jsonl | cut -c1-8)" "$JQ | [\$s, .turns, .tools, .cache_read_M, .output_k, .ctx_avg_k, .suite_runs, .same_cmd_repeats, .hook_blocks, .shell_reads, .serena, .cbm, .shell_searches, .cold, .cold_k, .mcp_flag] | @tsv")
  awk -F'\t' '{printf "%-10s %6s %6s %9s %8s %7s %6s %7s %6s %6s %6s %5s %6s %5s %6s %s\n",$1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16}' <<<"$row"
  COLD=$((COLD + $(cut -f14 <<<"$row"))) COLDK=$((COLDK + $(cut -f15 <<<"$row")))
  compgen -G "${f%.jsonl}/subagents/agent-*.jsonl" >/dev/null || continue
  IFS=$'\t' read -r hn h20 h15 hr < <(for h in "${f%.jsonl}"/subagents/agent-*.jsonl; do grep -v "$API" "$h" | jq -s -c "$HJQ"; done | jq -s -r "$HSUM")
  printf '           helpers %s over20 %s over15 %s repeats %s\n' "$hn" "$h20" "$h15" "$hr"
  HN=$((HN + hn)) H20=$((H20 + h20)) H15=$((H15 + h15)) HR=$((HR + hr))
done
grep -hv "$API" $files | jq -s -r --argjson c "$COLD" --argjson ck "$COLDK" --argjson hn "$HN" --argjson h20 "$H20" --argjson h15 "$H15" --argjson hr "$HR" "$JQ | \"TOTAL      \(.turns) turns, \(.tools) tool calls, \(.cache_read_M)M cache-read tokens, \(.output_k)k output, \(.suite_runs) suite/tsc runs (\(.same_cmd_repeats) repeats), \(.hook_blocks) hook blocks, \(.shell_reads) shell reads, \(\$c) cold rewrites (\(\$ck)k tokens), \(\$hn) helpers (\(\$h20) over 20 calls, \(\$h15) answers over 15 lines, \(\$hr) repeated searches)\""
fi
# Codex panes keep no per-turn transcript we parse; their index carries a
# per-session token total (updated_at is epoch seconds).
CODEX_DB=${CODEX_HOME:-$HOME/.codex}/state_5.sqlite
[ -f "$CODEX_DB" ] || { echo "CODEX      not measured (no index at $CODEX_DB)"; [ -n "$files" ]; exit; }
python3 - "$PP_WORKSPACES/$UNIT" "$(date -d "$SINCE" +%s)" "$CODEX_DB" <<'PY'
import sqlite3, sys
cwd, since = sys.argv[1], int(sys.argv[2])
c = sqlite3.connect(sys.argv[3])
n, tok = c.execute("select count(*), coalesce(sum(tokens_used),0) from threads where cwd=? and updated_at>=?", (cwd, since)).fetchone()
print(f"CODEX      {n} sessions, {tok/1e6:.1f}M tokens (index total, all token kinds)")
PY

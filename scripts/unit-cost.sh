#!/usr/bin/env bash
# unit-cost.sh <unit> [since 'YYYY-MM-DD HH:MM'] -- what a unit's worker panes
# cost, from their own transcripts. One line per session and a total:
# turns, tool calls, cache-read Mtok (the bill), output ktok, suite/tsc runs,
# reruns of an unchanged tree, hook-blocked calls, shell reads, serena and
# codebase-memory calls beside shell searches. A session with no MCP call and
# 10+ shell searches is marked MCP UNUSED.
#
# Why: a rule about worker cost needs the same numbers each time to show it held.
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
(map(select(.timestamp)) | sort_by(.timestamp)) as $m
| ($m | map(select(.type=="assistant"))) as $lines
| ([ $lines[] | .message.content[]? | select(.type=="tool_use") ]) as $uses
# One reply is one line per content block, each repeating message.usage.
| ($lines | group_by(.message.id // .uuid) | map(.[-1])) as $a
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
  # The same shell-search shape read-tracker.sh counts for its live tripwire.
  shell_searches: ($uses | map(select(.name=="Bash" and ((.input.command // "")|test("(^|[;&|(])\\s*(rg|grep|cat|sed\\s+-n)\\s")))) | length)
}
| .mcp_flag = (if .serena + .cbm == 0 and .shell_searches >= 10 then "MCP UNUSED" else "" end)'
if [ -n "$files" ]; then
printf '%-10s %6s %6s %9s %8s %7s %6s %7s %6s %6s %6s %5s %6s\n' session turns tools cacheMtok out_k ctx_avgk suites repeat blocks shreads serena cbm shsrch
for f in $files; do
  jq -s -r --arg s "$(basename "$f" .jsonl | cut -c1-8)" "$JQ | [\$s, .turns, .tools, .cache_read_M, .output_k, .ctx_avg_k, .suite_runs, .same_cmd_repeats, .hook_blocks, .shell_reads, .serena, .cbm, .shell_searches, .mcp_flag] | @tsv" "$f" \
    | awk -F'\t' '{printf "%-10s %6s %6s %9s %8s %7s %6s %7s %6s %6s %6s %5s %6s %s\n",$1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14}'
done
cat $files | jq -s -r "$JQ | \"TOTAL      \(.turns) turns, \(.tools) tool calls, \(.cache_read_M)M cache-read tokens, \(.output_k)k output, \(.suite_runs) suite/tsc runs (\(.same_cmd_repeats) repeats), \(.hook_blocks) hook blocks, \(.shell_reads) shell reads\""
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

#!/usr/bin/env bash
# covers: scripts/search-log-report.py hooks/hooks.json
# Self-test for search-log.sh and search-log-report.py (issue 298). Run directly.
#
# The log exists to answer "do the code servers beat rg" with counts, so what matters is that every search through
# the five tool types leaves exactly one row, that a re-look within the session's next 3 logged calls is flagged on
# the row that re-looks, that the report counts a search once however many reads follow it, and that no query text
# ever reaches the log (a query can be a secret). Every call goes through the commands hooks.json registers for its
# tool, so a tool that is not registered logs nothing and fails here.
set -u
REAL=$(cd "$(dirname "$0")/../.." && pwd)
HOOK=$REAL/hooks/search-log.sh REPORT=$REAL/scripts/search-log-report.py
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }

BOX=$(mktemp -d); trap 'rm -rf "$BOX"; rm -f /tmp/claude-search-ring-slt-"$$"-*' EXIT
PROJ=$BOX/proj; mkdir -p "$PROJ/src/d" "$BOX/home"; git -C "$PROJ" init -q
touch "$PROJ/src/a.ts" "$PROJ/src/b.ts" "$PROJ/src/d/x.ts"
# The plugin's hooks run only in a set-up project (hook-fire-log.sh), and hooks.json starts them with CLAUDE_PLUGIN_ROOT set.
mkdir -p "$PROJ/.claude"; echo "{}" > "$PROJ/.claude/commandeck.json"
LOG=$BOX/log.jsonl
S=slt-$$

# fire <session> <tool> <tool_input json> [tool_response json]: the payload goes to each command hooks.json registers
# for <tool> that runs search-log.sh, as Claude Code starts it.
fire() {
  local payload c
  payload=$(jq -cn --arg s "$1" --arg t "$2" --argjson i "$3" --argjson r "${4:-null}" \
    '{session_id:$s, tool_name:$t, tool_input:$i, tool_response:$r, hook_event_name:"PostToolUse"}')
  while IFS= read -r c; do
    printf '%s' "$payload" | HOME="$BOX/home" CLAUDE_PLUGIN_ROOT="$REAL" CLAUDE_PROJECT_DIR="$PROJ" COMMANDECK_SEARCH_LOG="$LOG" \
      bash -c "$c" > "$BOX/stdout" 2>/dev/null
  done < <(registered "$2")
}
registered() { jq -r --arg t "$1" '.hooks.PostToolUse[] | select(.matcher as $m | $t | test("^(" + $m + ")$")) | .hooks[].command | select(contains("/search-log.sh"))' "$REAL/hooks/hooks.json"; }
rows() { [ -f "$LOG" ] && jq -s 'length' "$LOG" || echo 0; }
last() { jq -r ".[-1].$1" <(jq -s . "$LOG"); }

check "hooks.json runs search-log.sh once for each of Read, Grep, Bash, serena and codebase-memory" "1 1 1 1 1" \
  "$(for t in Read Grep Bash mcp__serena__find_symbol mcp__codebase-memory__search_graph; do registered "$t" | wc -l | tr -d ' '; done | paste -sd' ' -)"
check "and not for Edit or Write" "0 0" "$(registered Edit | wc -l | tr -d ' ') $(registered Write | wc -l | tr -d ' ')"

fire "$S-a" Read "{\"file_path\":\"$PROJ/src/r.ts\"}" '{"file":{"content":"x"}}'
check "Read: one row, kind read, project-relative path" "1 Read read src/r.ts" "$(rows) $(last tool) $(last kind) $(last 'paths[0]')"
fire "$S-a" Grep '{"pattern":"zzz","path":"src/"}' '"No files found"'
check "Grep with No files found: empty true" "Grep true" "$(last tool) $(last empty)"
fire "$S-a" Bash '{"command":"rg foo src/"}' '{"stdout":"src/a.ts:1:foo\n","stderr":""}'
check "Bash rg foo src/: tool bash-grep, symbol-shaped, path src/, hit src/a.ts" "bash-grep true src/ src/a.ts" \
  "$(last tool) $(last symbol_shaped) $(last 'paths[0]') $(last 'hits[0]')"
fire "$S-a" mcp__serena__find_symbol '{"name_path_pattern":"foo"}' '[]'
check "serena find_symbol name_path_pattern foo with []: empty and symbol-shaped" "true true" "$(last empty) $(last symbol_shaped)"
fire "$S-a" mcp__codebase-memory__search_graph '{"query":"foo"}' '[{"type":"text","text":"src/b.ts"}]'
check "codebase-memory search_graph: one row, size is the text length" "mcp__codebase-memory__search_graph 8" "$(last tool) $(last size)"
check "five calls so far, five rows" 5 "$(rows)"
fire "$S-a" Bash '{"command":"ls"}' '{"stdout":"x"}'
fire "$S-a" mcp__serena__find_symbol '{"name_path_pattern":"foo"}' '{"is_error":true}'
check "Bash ls and an errored serena call log nothing" 5 "$(rows)"

# follow_of: the newest of this session's previous 3 logged rows that the new row repeats.
fire "$S-b" Grep '{"pattern":"Thing","path":"src/"}' '"src/a.ts:1: Thing\nsrc/b.ts:2: Thing"'
fire "$S-b" Read "{\"file_path\":\"$PROJ/src/a.ts\"}" '"body"'
check "a Grep then a Read of its matched file, each run through the commands hooks.json registers, flags the Read as a follow-up" "Grep" "$(last follow_of)"
fire "$S-c" mcp__serena__find_symbol '{"name_path_pattern":"Other","relative_path":"src/c.ts"}' '[]'
for i in 1 2 3; do fire "$S-c" Grep "{\"pattern\":\"p$i\",\"path\":\"lib$i/\"}" '"x"'; done
fire "$S-c" Read "{\"file_path\":\"$PROJ/src/c.ts\"}" '"body"'
check "the same Read 4 logged calls later is not a follow-up" "null" "$(last follow_of)"
# Another session's traffic must not push session S's row out of its window.
fire "$S-d" Grep '{"pattern":"mine","path":"src/d/"}' '"src/d/x.ts"'
for i in $(seq 20); do fire "$S-other" Grep "{\"pattern\":\"q$i\",\"path\":\"o$i/\"}" '"x"'; done
fire "$S-d" Read "{\"file_path\":\"$PROJ/src/d/x.ts\"}" '"body"'
check "another session logs 20 rows, then S reads what its search found: flagged" "Grep" "$(last follow_of)"

# One search followed by two reads (of two files it matched) is one followed search, not two.
LOG2=$BOX/log2.jsonl; LOG_KEEP=$LOG; LOG=$LOG2
fire "$S-h" Grep '{"pattern":"Both","path":"src/"}' '"src/a.ts:1: Both\nsrc/b.ts:2: Both"'
fire "$S-h" Read "{\"file_path\":\"$PROJ/src/a.ts\"}" '"body"'
fire "$S-h" Read "{\"file_path\":\"$PROJ/src/b.ts\"}" '"body"'
check "both reads follow the one Grep" "Grep Grep" "$(jq -r '.follow_of' "$LOG" | tail -2 | paste -sd' ' -)"
check "one Grep followed by two Reads reports followup=100%, on its tool line and its symbol-shaped line" 2 "$(python3 -I "$REPORT" "$LOG" | grep -c '^Grep .*calls=1 .*followup=100%')"
LOG=$LOG_KEEP

# No query text, anywhere.
fire "$S-e" Grep '{"pattern":"sk-live-SECRETQUERY","path":"src/"}' '"No files found"'
fire "$S-e" Bash '{"command":"rg sk-live-SECRETQUERY src/"}' '""'
check "a secret-shaped query appears in neither the log nor the ring" "0 0" \
  "$(grep -c SECRETQUERY "$LOG") $(grep -c SECRETQUERY /tmp/claude-search-ring-"$S-e")"
# Option values shift the query into the operand list, and matching lines carry the query and its neighbours:
# only names that exist under the project may become paths or hits.
fire "$S-g" Bash '{"command":"rg -g '"'*.ts'"' sk-live-SECRETQUERY src/"}' '""'
check "rg -g glob SECRET src/: the query is not a path; src/ still is" "0 src/" \
  "$(grep -c SECRETQUERY "$LOG") $(last 'paths | join(",")')"
fire "$S-g" Bash '{"command":"rg password src/"}' '{"stdout":"src/a.ts:1:password=\"SECRETQUERY.dev\"\n"}'
check "rg result line: hit src/a.ts, the matched value is not a hit" "src/a.ts" "$(last 'hits | join(",")')"
fire "$S-g" mcp__serena__find_symbol '{"name_path_pattern":"Thing","include_body":true}' \
  '[{"type":"text","text":"{\"relative_path\":\"src/a.ts\",\"body\":\"k = SECRETQUERY.token\"}"}]'
check "a serena body leaves no secret in the log or the ring" "0 0" \
  "$(grep -c SECRETQUERY "$LOG") $(grep -c SECRETQUERY /tmp/claude-search-ring-"$S-g")"

# Rotation and mode.
BIG=$BOX/big.jsonl; head -c 20000001 /dev/zero > "$BIG"
jq -cn '{session_id:"x",tool_name:"Read",tool_input:{file_path:"a"},tool_response:"b"}' \
  | HOME="$BOX/home" CLAUDE_PROJECT_DIR="$PROJ" COMMANDECK_SEARCH_LOG="$BIG" bash "$HOOK" >/dev/null 2>&1
mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
check "a 20,000,001-byte log moves to .1 before the next row; the new log holds that one row, mode 0600" "20000001 1 600" \
  "$(wc -c < "$BIG.1" | tr -d ' ') $(wc -l < "$BIG" | tr -d ' ') $(mode "$BIG")"

# A logging hook never changes a call.
echo '{not json' | HOME="$BOX/home" CLAUDE_PROJECT_DIR="$PROJ" COMMANDECK_SEARCH_LOG="$LOG" bash "$HOOK" > "$BOX/stdout" 2>/dev/null
check "malformed JSON: exit 0 and no stdout" "0 0" "$? $(wc -c < "$BOX/stdout" | tr -d ' ')"
fire "$S-f" Read '{"file_path":"x"}' '"y"'
check "a good call prints nothing either" 0 "$(wc -c < "$BOX/stdout" | tr -d ' ')"

# The report: aggregates only.
RLOG=$BOX/report.jsonl
row() { printf '{"tool":"%s","kind":"%s","symbol_shaped":true,"size":%s,"empty":%s,"id":"%s","follow_id":%s,"follow_of":%s,"qfp":"abcdef123456","paths":["secret/path.ts"],"hits":[]}\n' "$@"; }
{ row mcp__serena__find_symbol search 10 false s1 null null; row mcp__serena__find_symbol search 20 true s2 null null; row mcp__serena__find_symbol search 30 false s3 null null
  row Read read 5 false r1 '"s1"' '"mcp__serena__find_symbol"'
  row Grep search 100 false g1 null null; row Grep search 300 false g2 null null
  row Read read 5 false r2 '"g1"' '"Grep"'; row Read read 5 false r3 '"g1"' '"Grep"'; } > "$RLOG"
OUTR=$(python3 -I "$REPORT" "$RLOG")
check "report: serena per tool and symbol-shaped line carry calls, median, p90, empty % and follow-up %" "2" \
  "$(grep -c 'calls=3 median=20 p90=30 empty=33% followup=33%' <<<"$OUTR")"
check "report: Grep line counts the searched Grep once for its two reads" "2" "$(grep -c '^Grep .*calls=2 median=200 p90=300 empty=0% followup=50%' <<<"$OUTR")"
check "report prints no query fingerprint and no path" "0" "$(grep -c -e abcdef123456 -e secret/path <<<"$OUTR")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

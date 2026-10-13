#!/usr/bin/env bash
# unit-cost.sh is the bill main quotes at merge. A Claude transcript writes one
# model reply as one line per content block, each repeating the same
# message.usage, so summing lines overstated dev-4-room ~1.8x. One
# reply must count as one turn with its usage once; tool calls stay per block.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP" COMMANDECK_WORKSPACES="$TMP/ws"
# The Claude project folder is the workspaces root's slug plus the unit.
D="$HOME/.claude/projects/$(printf %s "$TMP/ws" | tr -c "A-Za-z0-9" "-")-fixture-unit"
mkdir -p "$D"
U='{"cache_read_input_tokens":1000000,"output_tokens":2000}'
{
  printf '{"type":"assistant","timestamp":"2026-09-18T10:00:00Z","message":{"id":"msg_1","usage":%s,"content":[{"type":"thinking","thinking":"x"}]}}\n' "$U"
  printf '{"type":"assistant","timestamp":"2026-09-18T10:00:01Z","message":{"id":"msg_1","usage":%s,"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}\n' "$U"
  printf '{"type":"assistant","timestamp":"2026-09-18T10:00:02Z","message":{"id":"msg_2","usage":%s,"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}\n' "$U"
} > "$D/session.jsonl"

OUT=$(bash "$REAL/scripts/unit-cost.sh" fixture-unit '2000-01-01 00:00' 2>/dev/null | grep '^TOTAL')
check "two replies over three lines count as two turns" "2 turns" "$(grep -oE '[0-9]+ turns' <<<"$OUT")"
check "each reply's cache-read counts once"             "2M cache-read" "$(grep -oE '[0-9.]+M cache-read' <<<"$OUT")"
check "each reply's output counts once"                 "4k output" "$(grep -oE '[0-9]+k output' <<<"$OUT")"
check "tool calls stay per tool_use block"              "2 tool calls" "$(grep -oE '[0-9]+ tool calls' <<<"$OUT")"

# MCP UNUSED: a seat that searched with the shell 10+ times and made no
# serena or codebase-memory call is flagged on its own line (cut 1,
# 2026-09-18: 245 rg, 0 MCP). One MCP call clears the flag.
rg_use() { printf '{"type":"assistant","timestamp":"2026-09-18T10:00:%02dZ","message":{"id":"m%s","usage":%s,"content":[{"type":"tool_use","name":"Bash","input":{"command":"rg -n foo src/services"}}]}}\n' "$1" "$2$1" "$U"; }
{ for i in $(seq 10 19); do rg_use "$i" blind; done; } > "$D/aaaaaaaa-blind.jsonl"
{ for i in $(seq 10 19); do rg_use "$i" seen; done
  printf '{"type":"assistant","timestamp":"2026-09-18T10:00:30Z","message":{"id":"mz","usage":%s,"content":[{"type":"tool_use","name":"mcp__serena__find_symbol","input":{}}]}}\n' "$U"
} > "$D/bbbbbbbb-seen.jsonl"
OUT=$(bash "$REAL/scripts/unit-cost.sh" fixture-unit '2000-01-01 00:00' 2>/dev/null)
check "a blind seat is marked MCP UNUSED" 1 "$(grep '^aaaaaaaa' <<<"$OUT" | grep -c 'MCP UNUSED')"
check "a seat with one serena call is not"  0 "$(grep '^bbbbbbbb' <<<"$OUT" | grep -c 'MCP UNUSED')"
check "the header names the MCP and shell-search columns" 1 "$(head -1 <<<"$OUT" | grep -c 'serena.*cbm.*shsrch')"

# The default start date is worked out after paths.sh has put the GNU
# tools first, so a PATH led by the system's own `date` (BSD on the Mac, which
# has no -d) still gives a total.
OUT=$(PATH="/usr/bin:/bin:$PATH" "$BASH" "$REAL/scripts/unit-cost.sh" fixture-unit 2>/dev/null)
check "the default date works with system tools first on PATH" 1 "$(grep -c '^TOTAL' <<<"$OUT")"

# A unit only Codex panes worked on has no Claude transcript. Its Codex
# sessions are still the bill.
python3 - "$HOME/.codex/state_5.sqlite" "$TMP/ws" <<'PY'
import os, sqlite3, sys, time
os.makedirs(os.path.dirname(sys.argv[1]), exist_ok=True)
c = sqlite3.connect(sys.argv[1])
c.execute("create table threads (cwd text, updated_at integer, tokens_used integer)")
c.execute("insert into threads values (?, ?, 2500000)", (sys.argv[2] + "/codex-only", int(time.time())))
c.commit()
PY
OUT=$(bash "$REAL/scripts/unit-cost.sh" codex-only 2>/dev/null); RC=$?
check "a unit with no Claude transcript still reports its Codex sessions" "0 1" "$RC $(grep -c '^CODEX      1 sessions, 2.5M tokens' <<<"$OUT")"

# On a Mac the system `date` has no -d; paths.sh puts the GNU tools first.
# The default "since" is worked out with `date -d`, so it comes after paths.sh.
check "the default date is computed after paths.sh has set PATH" yes \
  "$(awk '/paths\.sh"/ && !p { p = NR } /date -d/ && !d { d = NR } END { print (p && d && p < d) ? "yes" : "no" }' "$(dirname "$0")/../unit-cost.sh")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

#!/usr/bin/env bash
# covers: scripts/dashboard_limit.py
# dashboard_limit.py restarts (issue 283): how often main restarts, how big the checkpoint it took was and how much of
# the new session's first context it is. A restart is a <session id>.resumed-from record beside the hook log, whose
# session has a transcript in this project; its checkpoint is the record's first line. The figures are worked by hand
# in the fixture below so a change to the reading shows as a changed number.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
export TZ=UTC
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CP=$T/checkpoints TR=$T/transcripts; mkdir -p "$CP" "$TR"
LOG=$CP/clear-hook.log
# usage <input> <cache read> <cache creation>: one assistant row of a transcript.
usage() { jq -cn --argjson i "$1" --argjson r "$2" --argjson c "$3" '{type:"assistant",message:{usage:{input_tokens:$i,cache_read_input_tokens:$r,cache_creation_input_tokens:$c,output_tokens:500}}}'; }
# restart <session> <checkpoint> <time>: the record the new main writes when it takes the checkpoint.
restart() { echo "$CP/$2.md" > "$CP/$1.resumed-from"; touch -d "$3" "$CP/$1.resumed-from"; }
# s1 resumed from a, which grew from 4096 to 6000 to 8192 bytes (carry) before it; a stop after the restart is another
# session's. Its first usage is 10 + 39000 + 990 = 40000; the later 205000 is not the post-restart context.
restart s1 a 2026-10-20T12:00:00
{ echo "2026-10-20T10:00:00 stop-hook: ctx=210000 line=200000 fresh=1 cp=$CP/a.md cp_bytes=4096 since_restart_min=-"
  echo "2026-10-20T11:00:00 stop-hook: ctx=210000 line=200000 fresh=1 cp=$CP/a.md cp_bytes=6000 since_restart_min=13"
  echo "2026-10-20T11:30:00 stop-hook: cp=$CP/a.md cp_bytes=8192 after carry"
  echo "2026-10-20T12:30:00 stop-hook: ctx=210000 line=200000 fresh=1 cp=$CP/a.md cp_bytes=99999 since_restart_min=30"
} > "$LOG"
{ usage 10 39000 990; usage 10 204000 990; } > "$TR/s1.jsonl"
# s2 shares s1's since_restart_min=13 on its stop line: two restarts, not one.
restart s2 b 2026-10-20T15:00:00
echo "2026-10-20T14:00:00 stop-hook: ctx=210000 line=200000 fresh=1 cp=$CP/b.md cp_bytes=12000 since_restart_min=13" >> "$LOG"
usage 0 50000 10000 > "$TR/s2.jsonl"
# s3's transcript is another project's: not counted. s4 is the next day.
restart s3 c 2026-10-21T09:00:00
restart s4 d 2026-10-21T10:00:00
echo "2026-10-21T08:00:00 stop-hook: ctx=210000 line=200000 fresh=1 cp=$CP/d.md cp_bytes=4000 since_restart_min=-" >> "$LOG"
usage 5 15000 4995 > "$TR/s4.jsonl"

report() { python3 "$REAL/scripts/dashboard_limit.py" restarts "$LOG" --transcripts "$TR" "$@"; }
OUT=$(report)
check "three restarts, two on the first day and one on the second; the one with no transcript here is skipped" \
  '3 {"2026-10-20":2,"2026-10-21":1} 1' "$(jq -r '"\(.restarts) \(.perDay | tojson) \(.skipped)"' <<<"$OUT")"
check "median checkpoint bytes: the last size before each restart, 8192 after the carry, 12000, 4000" 8192 "$(jq .medianCheckpointBytes <<<"$OUT")"
check "median post-restart context is each session's first usage (40000, 60000, 20000), not a later one" 40000 "$(jq .medianContext <<<"$OUT")"
check "the share is bytes over 4 against the context per restart, 5.12, 5 and 5, and the median is 5; the report says estimate" \
  '500 true' "$(jq -r '"\(.medianSharePct * 100 | round) \(.estimate)"' <<<"$OUT")"
check "a stop line after the restart does not change the size (99999 ignored)" 8192 "$(report --until 2026-10-20T12:30:00 | jq .medianCheckpointBytes)"
check "--since and --until keep the restarts between them" '1 {"2026-10-21":1}' \
  "$(report --since 2026-10-21T00:00:00 | jq -r '"\(.restarts) \(.perDay | tojson)"')"
# A carried checkpoint of 8192 bytes, not the 4096 it was first written at: 8192 / 4 / 40000 is 5.12%, not 2.56%.
rm -f "$CP"/s[234].resumed-from
check "a checkpoint carried from 4096 to 8192 bytes shows the 8192 share, 5.12%" 512 "$(report | jq '.medianSharePct * 100 | round')"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

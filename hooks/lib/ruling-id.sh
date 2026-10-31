#!/usr/bin/env bash
# ruling-id.sh -- sourced, never run. ruling_id_state <id> <log>: 0 when the id has the shape ruling-log.sh gives
# and the log (one JSON row per line, a damaged line skipped) holds it with no void row and no unconfirmed suspect
# row; 1 when the shape is wrong or no row holds it; 2 when the row is void, or a suspect row (answered in under
# 2 s, maybe an Orca nudge) that main has not marked "confirmed". Readers: hooks/ruling-cite-gate.sh and
# ruling_id_ok in scripts/builder-codex-pass.sh.
ruling_id_state() {
  local n
  [[ $1 =~ ^r-[0-9]{8}-[0-9]{6}-[0-9a-z]+-[0-9a-f]{6}$ ]] || return 1
  n=$(jq -Rne --arg id "$1" '[inputs | fromjson? | select(.id == $id)] as $r
    | if ($r | length) == 0 then 1 elif any($r[]; .void or (.pick == "suspect" and (.confirmed | not))) then 2 else 0 end' "$2" 2>/dev/null) || return 1
  return "${n:-1}"
}

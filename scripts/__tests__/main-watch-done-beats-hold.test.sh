#!/usr/bin/env bash
# #499: a Builder printed its DONE line on a closing GO with one background job that never reported. The keep-alive
# "." reply became its latest answer, so the DONE line could no longer be read and main heard nothing. No keep-alive
# goes to a Builder whose DONE is in its answer or its --state marker; a Builder with no DONE is still pinged and held.
# Fixture: fixtures/main-watch-setup.sh, as main-watch-wake.test.sh uses.
set -euo pipefail
. "$(dirname "$0")/fixtures/main-watch-setup.sh"
tick 5000

W=80000
bts() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
slog() { printf '%s' "$T/home/.claude/projects/$(printf '%s' "$T/ws/$1" | sed 's/[^a-zA-Z0-9]/-/g')/s.jsonl"; }
turn() { # unit epoch stop -- one main-thread request and its reply in the unit's session record
  printf '{"type":"user","isSidechain":false,"timestamp":"%s","message":{}}\n' "$(bts "$2")" >> "$(slog "$1")"
  printf '{"type":"assistant","isSidechain":false,"timestamp":"%s","message":{"stop_reason":"%s","usage":{"input_tokens":2,"cache_read_input_tokens":95000,"cache_creation_input_tokens":5000,"cache_creation":{"ephemeral_5m_input_tokens":5000,"ephemeral_1h_input_tokens":0}}}}\n' "$(bts "$2")" "$3" >> "$(slog "$1")"
}
waiting() { # unit handle state -- a Builder whose last reply, 230 s before W, left a background job open
  bseat "$1" "$2" "t_$1" $((W - 4000)); state "$2" "$3"; mkdir -p "$(dirname "$(slog "$1")")"
  printf '{"ts":"%s","event":"tool-start","use":"o1","tool":"Bash","kind":"shell","call":"o1"}\n{"ts":"%s","event":"tool-end","use":"o1","ok":true}\n' \
    "$(bts $((W - 3000)))" "$(bts $((W - 2999)))" > "$T/ws/$1/.claude/builder-events.jsonl"
  turn "$1" $((W - 400)) tool_use
  printf '{"type":"user","toolUseResult":{"stdout":"","backgroundTaskId":"bW"}}\n' >> "$(slog "$1")"
  turn "$1" $((W - 230)) end_turn
  touch -d "@$((W - 230))" "$(slog "$1")"
}
pings() { grep -c -- "terminal send --terminal $1 --text Signal WARM" "$T/typed" || true; }

rm -f "$S"/seat-*.txt; : > "$T/sends"; : > "$T/typed"
waiting wt-dh term_dh working; echo WT-DH-DONE > "$F/verdict-term_dh"
waiting wt-cg term_cg working; printf 'VERDICT: GO\n' > "$F/verdict-term_cg"; echo marker=1 > "$F/state-wt-cg"
waiting wt-nd term_nd working
tick $W
# Catches: a keep-alive "." typed into a Builder whose DONE line is already its answer, burying the line.
[ "$(pings term_dh)" = 0 ] || { echo "FAIL done_gets_no_ping (a Builder that printed DONE was pinged)"; fail "done_gets_no_ping: $(cat "$T/typed")"; }
# Catches: the marker read dropped, so a closing GO (the answer ends at the VERDICT line) is pinged.
[ "$(pings term_cg)" = 0 ] || fail "closing_go_gets_no_ping: a Builder whose DONE is its --state marker was pinged: $(cat "$T/typed")"
[ "$(pings term_nd)" = 1 ] || fail "done_gets_no_ping: a Builder still waiting with no DONE lost its ping: $(cat "$T/typed")"

# Catches: an open job holding a Builder that printed DONE, so main is never told (the hold side already ends on DONE).
state term_dh done; state term_nd done; tick $((W + 60))
grep -q 'seat builder on wt-dh finished' "$T/sends" || fail "done_beats_open_job: an open job held a Builder that printed DONE: $(cat "$T/sends")"
[ "$(grep -c 'wt-nd' "$T/sends" || true)" = 0 ] || fail "done_beats_open_job: an open job stopped holding a Builder with no DONE: $(cat "$T/sends")"
echo "PASS main-watch-done-beats-hold"

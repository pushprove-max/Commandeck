#!/usr/bin/env bash
# Subagent runs (109 transcripts on 2026-10-01) were never measured: their
# tokens sat in per-agent transcripts nobody read. subagent-usage.sh appends one
# row per finished run, from the main checkout's sessions and every worktree's;
# a run still being written waits, and a collect never counts a run twice.
set -u
SOURCE=$(git rev-parse --show-toplevel)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/main" "$T/ws"
. "$SOURCE/scripts/paths.sh"
PROJ=$T/projects
MAIN_S=$PROJ/$(pp_slug "$T/main")/s1/subagents
WT_S=$PROJ/$(pp_slug "$T/ws")-unit-x/s2/subagents
OTHER_S=$PROJ/-some-other-repo/s3/subagents
mkdir -p "$MAIN_S" "$WT_S" "$OTHER_S"
usage() { printf '{"type":"assistant","message":{"id":"%s","model":"claude-opus-5-5","usage":{"input_tokens":%s,"cache_creation_input_tokens":0,"cache_read_input_tokens":%s,"output_tokens":%s}}}\n' "$@"; }
agent() { # dir id agentType
  { usage m1 10 90 5; usage m1 10 90 5; usage m2 1 9 2; } > "$1/agent-$2.jsonl"
  printf '{"agentType":"%s","description":"look at %s"}\n' "$3" "$2" > "$1/agent-$2.meta.json"
  touch -d '-20 minutes' "$1/agent-$2.jsonl"
}
agent "$MAIN_S" a1 Explore
agent "$WT_S" w1 general-purpose
agent "$OTHER_S" o1 Explore
agent "$MAIN_S" a2 Explore; touch "$MAIN_S/agent-a2.jsonl"   # still being written
LEDGER=$T/main/.claude/metrics/subagent-usage.jsonl
collect() { COMMANDECK_MAIN=$T/main COMMANDECK_WORKSPACES=$T/ws COMMANDECK_CLAUDE_PROJECTS=$PROJ bash "$SOURCE/scripts/subagent-usage.sh"; }

collect; check "a collect exits 0" 0 "$?"
check "one row per finished run in main's and the worktrees' sessions, none for another repo or a live run" "a1,w1" \
  "$(jq -sr 'map(.agentId) | sort | join(",")' "$LEDGER")"
check "the row carries type, session, project and tokens summed by message id" \
  'Explore|s1|{"input":110,"cachedInput":99,"output":7}|claude-opus-5-5' \
  "$(jq -r 'select(.agentId == "a1") | "\(.agentType)|\(.session)|\(.tokens | tojson)|\(.model)"' "$LEDGER")"
collect
check "a second collect appends nothing" 2 "$(wc -l < "$LEDGER" | tr -d ' ')"
touch -d '-20 minutes' "$MAIN_S/agent-a2.jsonl"; collect
check "a run that has since finished is recorded once" "a1,a2,w1" "$(jq -sr 'map(.agentId) | sort | join(",")' "$LEDGER")"
# The installed collector and a manual one can overlap: neither may append a run the other did.
mv "$LEDGER" "$T/ledger.keep"
for i in 1 2 3 4; do collect & done; wait
check "overlapping collects record each run once" "a1,a2,w1" "$(jq -sr 'map(.agentId) | sort | join(",")' "$LEDGER")"
mv "$T/ledger.keep" "$LEDGER"
# A run that went quiet, was recorded, and then carried on. Its id was in
# the ledger, so it was never read again and every later token went missing.
cp "$LEDGER" "$T/ledger.keep"
usage m3 100 0 50 >> "$MAIN_S/agent-a1.jsonl"; touch -d '-15 minutes' "$MAIN_S/agent-a1.jsonl"; collect
check "a run that carried on gets a fresh row with the larger total" '{"input":210,"cachedInput":99,"output":57}' \
  "$(jq -sc 'map(select(.agentId == "a1")) | last | .tokens' "$LEDGER")"
check "and only that run does" "a1:2,a2:1,w1:1" "$(jq -sr 'group_by(.agentId) | map("\(.[0].agentId):\(length)") | join(",")' "$LEDGER")"
collect
check "a transcript unchanged since its latest row appends nothing" 4 "$(wc -l < "$LEDGER" | tr -d ' ')"
usage m4 1 0 1 >> "$MAIN_S/agent-a1.jsonl"; collect
check "a run writing again waits, as a first run does" 4 "$(wc -l < "$LEDGER" | tr -d ' ')"
mv "$T/ledger.keep" "$LEDGER"
rm -rf "$PROJ"; collect
check "no projects directory is a quiet no-op" "0|3" "$?|$(wc -l < "$LEDGER" | tr -d ' ')"

# Another project whose folder name starts with this one's (ws and ws-private)
# has session folders the worktree pattern matches too. Its runs are its own.
SIB_S=$PROJ/$(pp_slug "$T/ws")-private-unit-y/s7/subagents; mkdir -p "$SIB_S" "$WT_S"
agent "$SIB_S" p1 Explore
printf '{"type":"user","cwd":"%s"}\n%s\n' "$T/ws-private/unit-y" "$(cat "$SIB_S/agent-p1.jsonl")" > "$T/p1.jsonl"; cp "$T/p1.jsonl" "$SIB_S/agent-p1.jsonl"; touch -d '-20 minutes' "$SIB_S/agent-p1.jsonl"
agent "$WT_S" w2 Explore
printf '{"type":"user","cwd":"%s"}\n%s\n' "$T/ws/unit-x/src" "$(cat "$WT_S/agent-w2.jsonl")" > "$T/w2.jsonl"; cp "$T/w2.jsonl" "$WT_S/agent-w2.jsonl"; touch -d '-20 minutes' "$WT_S/agent-w2.jsonl"
mkdir -p "$PROJ"; collect
check "a sibling project's run is left out, this project's worktree run is taken" "0 1" "$(grep -c '"agentId":"p1"' "$LEDGER") $(grep -c '"agentId":"w2"' "$LEDGER")"

# A recorded run that went on (a long agent that paused, a resumed one) used
# more tokens after its row was written. Once it is quiet again it gets a new
# row with the whole total; a reader takes a run's last row.
usage m9 1000 0 500 >> "$WT_S/agent-w2.jsonl"; touch -d '-15 minutes' "$WT_S/agent-w2.jsonl"; collect
check "a recorded run that continued gets a second row" 2 "$(grep -c '"agentId":"w2"' "$LEDGER")"
check "and its last row holds the whole total" 1110 "$(jq -s '[.[] | select(.agentId == "w2")] | last | .tokens.input' "$LEDGER")"
collect
check "a run that has not changed since gets no further row" 2 "$(grep -c '"agentId":"w2"' "$LEDGER")"
touch "$WT_S/agent-w2.jsonl"; collect
check "nor one that is being written now" 2 "$(grep -c '"agentId":"w2"' "$LEDGER")"

echo "$PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]

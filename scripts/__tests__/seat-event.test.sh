#!/usr/bin/env bash
# Every reviewer (122) and fixer (82) seat row since 09-28 had tokens:null:
# only seat.sh collect read the pane's session log, and every other caller
# called seat-event.sh bare. seat-event.sh now finds the seat's own
# session log and sums it, so every caller gets tokens, and each row says why
# the seat stopped.
#
# read-verdict is a stub that hands back a fixture session log, the way it
# does for a finished pane.
set -u
SOURCE=$(git rev-parse --show-toplevel)
SCRIPTS=$SOURCE/scripts
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export COMMANDECK_MAIN=$T/main
mkdir -p "$T/bin" "$T/main/.claude/metrics"
EVENTS=$T/main/.claude/metrics/seat-events.jsonl
TOKENS='{"input":3111,"cachedInput":3000,"output":12}'

# A Claude session: one reply streamed as two lines sharing a message id, then a second reply.
SESSION=$T/session.jsonl
usage() { printf '{"type":"assistant","message":{"id":"%s","model":"claude-opus-5-5","usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":%s}}}\n' "$@"; }
{ usage msg_a 10 100 1000 5; usage msg_a 10 100 1000 5; usage msg_b 1 0 2000 7; } > "$SESSION"

# The stub answers --state with the session log, and a verdict read with the report.
cat > "$T/read-verdict.sh" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${FAKE_ARGS:-/dev/null}"
if [ "$1" = --state ]; then printf 'state=complete\nmarker=1\nreason=\nsession=%s\nprovider=claude\n' "$FAKE_SESSION"; exit 0; fi
echo "=== $1 : findings + verdict ==="
cat "$FAKE_REPORT"
EOF
chmod +x "$T/read-verdict.sh"
export FAKE_SESSION=$SESSION FAKE_REPORT=$T/report.txt

# --- seat-event.sh on its own -------------------------------------------------
cp "$SCRIPTS/seat-event.sh" "$SCRIPTS/paths.sh" "$SCRIPTS/project-main.sh" "$T/read-verdict.sh" "$T/bin/"
event() { COMMANDECK_SEAT_EVENTS=$EVENTS bash "$T/bin/seat-event.sh" u role task_x 1788948240 m 1; tail -1 "$EVENTS"; }
check "--usage sums a Claude log, each message id once" "{\"model\":\"claude-opus-5-5\",\"tokens\":$TOKENS}" \
  "$(bash "$T/bin/seat-event.sh" --usage claude "$SESSION")"
# Codex logs running totals: the legacy token_count event, and the current
# token_usage_record (total_token_usage or thread_token_usage). The last one
# counts; with a launch, minus the last before it (a warm pane's earlier seat).
CODEX=$T/codex.jsonl
cdx() { printf '{"timestamp":"%s","type":"%s","payload":%s}\n' "$@"; }
{ cdx 2026-09-09T00:00:00Z turn_context '{"model":"gpt-6-astra"}'
  cdx 2026-09-09T00:00:01Z event_msg '{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":10}}}'
  cdx 2026-09-10T00:00:01Z token_usage_record '{"total_token_usage":{"input_tokens":700,"cached_input_tokens":300,"output_tokens":70}}'; } > "$CODEX"
check "--usage reads the current Codex token_usage_record" '{"model":"gpt-6-astra","tokens":{"input":700,"cachedInput":300,"output":70}}' \
  "$(bash "$T/bin/seat-event.sh" --usage codex "$CODEX")"
head -2 "$CODEX" > "$T/legacy.jsonl"
check "--usage still reads the legacy token_count event" '{"input":100,"cachedInput":40,"output":10}' \
  "$(bash "$T/bin/seat-event.sh" --usage codex "$T/legacy.jsonl" | jq -c .tokens)"
sed 's/"total_token_usage":{"input_tokens":700/"thread_token_usage":{"input_tokens":700/' "$CODEX" > "$T/thread.jsonl"
check "--usage reads a thread_token_usage record" 700 "$(bash "$T/bin/seat-event.sh" --usage codex "$T/thread.jsonl" | jq .tokens.input)"
NOON=$(date -u -d 2026-09-09T12:00:00Z +%s)
check "--usage with a launch subtracts the Codex baseline before it" '{"input":600,"cachedInput":260,"output":60}' \
  "$(bash "$T/bin/seat-event.sh" --usage codex "$CODEX" "$NOON" | jq -c .tokens)"
check "a seat with no worktree has no tokens and an unknown stop" 'null|unknown' \
  "$(event | jq -r '[.tokens, .stopReason] | map(tostring) | join("|")')"
check "a seat whose worktree has a session log carries its tokens and stop reason" "$TOKENS|killed" \
  "$(SEAT_EVENT_WORKTREE=$T SEAT_EVENT_AGENT=claude SEAT_EVENT_STOP=killed event | jq -c '[.tokens, .stopReason]' | jq -r '"\(.[0] | tojson)|\(.[1])"')"
check "a session log that is gone is a null with the reason, never a failed row" 'null|no session log' \
  "$(FAKE_SESSION=$T/missing SEAT_EVENT_WORKTREE=$T event | jq -r '"\(.tokens)|\(.tokensReason[0:14])"')"
# A fix dispatched to the warm builder pane: its session predates the launch, so
# only the task id binds it, and only the turns since the launch are this seat's.
WARM=$T/warm.jsonl
{ printf '{"type":"assistant","timestamp":"2026-09-09T00:00:00.000Z","message":{"id":"old","model":"claude-opus-5-5","usage":{"input_tokens":500,"output_tokens":500}}}\n'
  sed 's/"type":"assistant",/"type":"assistant","timestamp":"2026-09-10T00:00:00.000Z",/' "$SESSION"; } > "$WARM"
cat > "$T/bin/read-verdict.sh" <<'EOF'
#!/bin/bash
case " $* " in *" --task task_x "*) printf 'state=complete\nsession=%s\nprovider=claude\n' "$FAKE_SESSION" ;; *) printf 'state=unknown\nreason=no session newer than the launch\n' ;; esac
EOF
check "a warm session is bound by the task and counts only the turns since launch" "$TOKENS" \
  "$(FAKE_SESSION=$WARM SEAT_EVENT_WORKTREE=$T event | jq -c '.tokens')"
check "--usage forwards the launch to a warm Claude log" "$TOKENS" \
  "$(bash "$T/bin/seat-event.sh" --usage claude "$WARM" "$NOON" | jq -c .tokens)"

echo "$PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]

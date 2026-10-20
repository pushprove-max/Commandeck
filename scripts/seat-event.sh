#!/usr/bin/env bash
# seat-event.sh <unit> <role> <task> <launched-epoch> [model] [round] -- append one
# finished seat to .claude/metrics/seat-events.jsonl, the one writer of that file.
# seat-event.sh --usage <claude|codex> <session-log> [launch-epoch] -- print that
# log's {model, tokens} or null, from the launch on when one is given; the one
# home of token parsing (subagent-usage.sh and unit-ledger.sh too).
#
# seat.sh collect calls it for a seat that ends with a verdict, and
# merge-unit-local.sh for the Builder, whose seat ends with the merge.
# SEAT_EVENT_WORKTREE (and SEAT_EVENT_AGENT) name where the seat ran: its session
# log is found there and summed into tokens. Without one, or with no usage in
# the log, tokens is null and tokensReason (SEAT_EVENT_REASON or a default) says
# why. session is that log's path (null without one): the dashboard ties a planning
# seat's spend to it after the pane is gone. SEAT_EVENT_STOP is why the seat stopped: done, killed, wedged or budget.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
HERE=$(dirname "${BASH_SOURCE[0]}")
# provider log [since-epoch] -- {model, tokens:{input, cachedInput, output}} or
# null. input counts every input token, cached ones included, for both
# providers. With since, only turns from then on count: a warm pane's session
# also holds the turns of the seat before it.
seat_usage() {
  local since=""
  [ -z "${3:-}" ] || since=$(date -u -d "@$3" '+%Y-%m-%dT%H:%M:%SZ') || return 1
  case "$1" in
    # Claude Code 2.1.300's api-request rows, a third or more of a long log, carry no usage: skipped unparsed.
    claude) jq -Rnc --arg since "$since" '[inputs | select(startswith("{\"type\":\"api-request") | not) | fromjson? // empty
        | select(.type == "assistant" and .message.usage != null)
        | select($since == "" or .timestamp == null or .timestamp >= $since)] as $m
      # A streamed reply repeats one message id, with the same usage, per content block.
      | ($m | unique_by(.message.id) | map(.message.usage)) as $u
      | if ($u | length) == 0 then null else
        {model: ([$m[].message.model | select(. != null and . != "<synthetic>")] | last),
         tokens: {input: ($u | map((.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)) | add),
                  cachedInput: ($u | map(.cache_read_input_tokens // 0) | add),
                  output: ($u | map(.output_tokens // 0) | add)}} end' "$2" ;;
    codex) jq -Rnc --arg since "$since" '
      # Running session totals, in the legacy token_count event or the current
      # token_usage_record (parity: token-ledger.sh total_usage).
      def total: if .type == "token_usage_record" then (.payload.total_token_usage // .payload.thread_token_usage)
        elif .payload.type? == "token_count" then .payload.info.total_token_usage else null end;
      # A total without its counters is missing usage, never a recorded zero.
      def counted: (.input_tokens | type) == "number" and (.output_tokens | type) == "number";
      [inputs | fromjson? // empty] as $r
      # The last total minus the last one before since.
      | [$r[] | select(total != null)] as $c
      | ($c | last | total) as $t
      | ([$c[] | select($since != "" and (.timestamp // "") < $since)] | last | total) as $b
      | if $t == null or ($t | counted | not) or ($b != null and ($b | counted | not)) then null else
        {model: ([$r[] | select(.type == "turn_context") | .payload.model // empty] | last),
         tokens: {input: (($t.input_tokens // 0) - ($b.input_tokens // 0)), cachedInput: (($t.cached_input_tokens // 0) - ($b.cached_input_tokens // 0)),
                  output: (($t.output_tokens // 0) - ($b.output_tokens // 0))}} end' "$2" ;;
    *) echo null ;;
  esac
}
[ "${1:-}" = --usage ] && { seat_usage "${2:?provider}" "${3:?session log}" "${4:-}"; exit; }
UNIT=${1:?unit}; ROLE=${2:?role}; TASK=${3:-}; LAUNCHED=${4:-}; MODEL=${5:-}; ROUND=${6:-}
. "$HERE/paths.sh" || exit 1
case $LAUNCHED in ''|*[!0-9]*) echo "seat-event: invalid launch epoch '$LAUNCHED'" >&2; exit 1 ;; esac
LAUNCHED_AT=$(date -u -d "@$LAUNCHED" '+%Y-%m-%dT%H:%M:%SZ') || { echo "seat-event: invalid launch epoch $LAUNCHED" >&2; exit 1; }
COMPLETED_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
FILE=${COMMANDECK_SEAT_EVENTS:-$PP_MAIN/.claude/metrics/seat-events.jsonl}
USAGE=null; REASON=${SEAT_EVENT_REASON:-no token usage measured for this seat}; SESSION= MISSING=
if [ -n "${SEAT_EVENT_WORKTREE:-}" ]; then
  # Bounded, so a blocked log read cannot hold the step this row measures.
  # A fresh pane's session is newer than the launch; a warm pane's (a fix sent to
  # the builder) is older, and only its task id binds it. SEAT_EVENT_SPEC (the
  # record's tag) picks a seat's own session from a sibling's launched with it.
  state() { timeout 20 bash "$HERE/read-verdict.sh" --state --worktree "$SEAT_EVENT_WORKTREE" --agent "${SEAT_EVENT_AGENT:-}" "$@" 2>/dev/null || true; }
  kv() { printf '%s\n' "$ST" | sed -n "s/^$1=//p" | head -1; }
  ST=$(state --launched "$LAUNCHED" ${SEAT_EVENT_SPEC:+--spec "$SEAT_EVENT_SPEC"})
  [ -n "$(kv session)" ] || [ -z "$TASK" ] || ST=$(state --task "$TASK")
  SESSION=$(kv session); REASON="no session log: $(kv reason)"
  if [ -n "$SESSION" ] && [ -f "$SESSION" ]; then
    USAGE=$(seat_usage "$(kv provider)" "$SESSION" "$LAUNCHED" 2>/dev/null) || USAGE=null
    REASON="no token usage in $SESSION"
    # A Builder that went on in fresh sessions (builder-fresh-round.sh): the record's other sessions are in the same folder.
    for id in ${SEAT_EVENT_SESSIONS:-}; do
      f=${SESSION%/*}/$id.jsonl
      [ "$f" != "$SESSION" ] || continue
      if [ -f "$f" ] && U=$(seat_usage "$(kv provider)" "$f" "$LAUNCHED" 2>/dev/null) && [ -n "$U" ] && [ "$U" != null ]; then
        USAGE=$(jq -cn --argjson a "$USAGE" --argjson b "$U" 'if $a == null then $b else $a | .tokens |= with_entries(.value += $b.tokens[.key]) end')
      else MISSING+=" $id"; fi
    done
    [ -z "$MISSING" ] || REASON="no session log for$MISSING (their tokens are not counted)"
  fi
fi
# --argjson below would drop the row on anything but JSON.
printf '%s' "$USAGE" | jq -e 'type == "object" or . == null' >/dev/null 2>&1 || USAGE=null
mkdir -p "$(dirname "$FILE")"
jq -cn --arg unit "$UNIT" --arg role "$ROLE" --arg taskId "$TASK" \
  --arg launchedAt "$LAUNCHED_AT" --arg completedAt "$COMPLETED_AT" \
  --arg model "$MODEL" --arg round "$ROUND" --arg stop "${SEAT_EVENT_STOP:-unknown}" --arg missing "$MISSING" \
  --argjson usage "$USAGE" --arg reason "$REASON" --arg session "$SESSION" \
  '{event:"worker_done",unit:$unit,role:$role,taskId:$taskId,launchedAt:$launchedAt,completedAt:$completedAt,
    model:($usage.model // (if $model == "" then null else $model end)),tokens:($usage.tokens // null),stopReason:$stop,
    session:(if $session == "" then null else $session end)}
   + (if $round == "" then {} else {round:($round | tonumber? // .)} end)
   + (if $usage.tokens == null or $missing != "" then {tokensReason:$reason} else {} end)' \
  >> "$FILE"

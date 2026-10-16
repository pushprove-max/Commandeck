#!/usr/bin/env bash
# Stop hook, main checkout only: a turn whose closing message asks the owner
# something (a line ending in "?" outside code) may not end until the ask is
# in the decisions ledger, the one source of the dashboard's Needs Owner card.
# The owner, 2026-10-01: "enforce where the questions go". The turn counts as
# recorded when it ran `decision.sh add` or AskUserQuestion, which records
# itself (ask-records-decision.sh). One hold per chain: a second stop passes.
#
# Self-test: bash hooks/__tests__/ask-records-decision.test.sh
set -uo pipefail

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
[ "$(jq -r '.stop_hook_active // false' <<<"$INPUT" 2>/dev/null)" = true ] && exit 0
[ "${COMMANDECK_REVIEWER:-}" = 1 ] && exit 0
ROOT=${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$INPUT")}
GITDIR=$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-dir 2>/dev/null) || exit 0
COMMON=$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
[ "$GITDIR" = "$COMMON" ] || exit 0

# The owner's message the Chief of Staff passed to main (to-main.sh marks it
# owed) is answered through the relay: an answer left on this screen never
# reaches the owner. A turn that ends with it owed is held once per message;
# cos-tell.sh --note clears the mark, and the relay's watcher flags it otherwise.
# Read and marked held under the lock to-main.sh writes it under: a newer mark between the two took this one's "held".
OWED=$( . "${BASH_SOURCE[0]%/*}/lib/project.sh" && pp_run_file 2>/dev/null) && OWED=${OWED%/*}/cos-owed
if [ -f "$OWED" ] && { flock -w 10 9 && ! grep -qx held "$OWED" && IFS=$'\t' read -r _ SUBJ < "$OWED" && echo held >> "$OWED"; } 9>>"$OWED.lock" 2>/dev/null; then
  printf '%s\n' "HELD: the owner's message \"$SUBJ\", passed on by the Chief of Staff, has no reply sent back to the relay, so an answer left on this screen does not reach the owner." \
    "Send your reply, then end the turn again: bash ${BASH_SOURCE[0]%/*}/../scripts/cos-tell.sh --note '<subject>' '<your reply>'" \
    "If the answer comes later, end the turn again: the relay's watcher tells the owner this turn ended without one." >&2
  exit 2
fi

T=$(jq -r '.transcript_path // empty' <<<"$INPUT" 2>/dev/null)
# This turn = every row after the last typed prompt: a Claude user row that is
# not only tool results, or a Codex user_message event (codex-dispatch.sh hands
# Codex's own transcript over unchanged). ponytail: the last 3000 rows; a longer
# turn reads as starting mid-way, which can only over-count a recorded ask.
TURN='[]'
if [ -n "$T" ] && [ -r "$T" ]; then
  TURN=$(tail -n 3000 "$T" | jq -cs '
    (to_entries | map(select(
      (.value.type == "user" and (.value.isMeta | not)
        and ((.value.message.content | type) == "string"
             or any(.value.message.content[]?; .type != "tool_result")))
      or (.value.type == "event_msg" and .value.payload.type == "user_message"))) | last.key // -1) as $s
    | .[$s + 1:] | map(select(.type == "assistant"
      or (.type == "response_item" and ((.payload.type // "") | endswith("call")))))' 2>/dev/null) || TURN='[]'
fi

TEXT=$(jq -r '.last_assistant_message // empty' <<<"$INPUT" 2>/dev/null)
[ -n "$TEXT" ] || TEXT=$(jq -r '[.[] | .message.content[]? | select(.type == "text") | .text] | last // empty' <<<"$TURN")

# Fenced blocks and inline code are not prose; markdown emphasis may trail the "?".
# A fence is 3+ backticks or tildes and closes only on a bare run of the same
# character at least as long (CommonMark).
printf '%s\n' "$TEXT" | awk '
  { sub(/\r$/, ""); l = $0; sub(/^[ \t]+/, "", l); n = match(l, /^(`+|~+)/) ? RLENGTH : 0; c = substr(l, 1, 1) }
  f == "" && n >= 3 { f = c; fn = n; next }
  f == "" { print; next }
  n >= fn && c == f && substr(l, n + 1) ~ /^[ \t]*$/ { f = "" }' | sed 's/`[^`]*`//g' \
  | grep -qE '\?[*_]*[[:space:]]*$' || exit 0

# A Codex call carries the command inside JSON-escaped arguments, so its whole
# payload is matched as text.
jq -e --arg re "decision\\.sh[\\\\\"']*\\s+add\\s" 'any(.[];
  (.type == "assistant" and any(.message.content[]? | select(.type == "tool_use");
     .name == "AskUserQuestion" or (.name == "Bash" and ((.input.command // "") | test($re)))))
  or (.type == "response_item" and (.payload | tostring | test($re))))' \
  <<<"$TURN" >/dev/null 2>&1 && exit 0

printf '%s\n' \
  "HELD: this turn ends by asking the owner something, but no decision was recorded, so the Needs Owner card will not show it." \
  "Record the ask, then end the turn again:" \
  "  bash ${BASH_SOURCE[0]%/*}/../scripts/decision.sh add <id> '<question>' '<your proposed default, or none>' main" \
  "The owner's reply closes it only when it names <id> (ruling-log.sh); otherwise run decision.sh answer <id> '<their answer>'. If the line was not a question for the owner, end the turn again." >&2
exit 2

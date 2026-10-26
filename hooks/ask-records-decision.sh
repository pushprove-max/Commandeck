#!/usr/bin/env bash
# PreToolUse hook on AskUserQuestion, main checkout only: every question main
# puts to the owner becomes a row in the decisions ledger, the one source of the
# dashboard's Needs Owner card. Nothing wrote that ledger, so on 2026-10-01 the
# card said "No open decisions" while two asks were open.
#
# Row: id = the header slug plus today's date, proposed default = the option
# marked "(Recommended)" without the marker, else "none". The one block: a
# question the owner still has open, or answered in the last 24 hours (decision.sh
# exit 3), stops the whole picker before any row is written, so the
# re-ask without it is not itself a repeat; a retry after a voided decoy pick
# passes, and so does the one picker a `decision.sh add ... --reask` of that
# id, or of a chat or earlier day's id this header names, armed (its add below
# spends the grant). Any other refused add (a same-day header reused for another
# question) is logged and the question still goes out. Plain-chat asks:
# ask-stop-records-decision.sh. With no relay (no chiefOfStaff.name, setup's
# default) nothing is blocked: main is the only asker, and a block hid its
# question from the owner (issue 241). The ledger row is still written or kept.
#
# Self-test: bash hooks/__tests__/ask-records-decision.test.sh
set -uo pipefail

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
[ "${COMMANDECK_REVIEWER:-}" = 1 ] && exit 0
ROOT=${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$INPUT")}
GITDIR=$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-dir 2>/dev/null) || exit 0
COMMON=$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
[ "$GITDIR" = "$COMMON" ] || exit 0
# worker-ask-guard.sh refuses a main picker whose first option is not the
# decoy; record nothing for it, or the corrected retry is a repeat of a
# question the owner never saw. The one refusal that runs AFTER recording is the Chief of Staff redirect below (issue 350).
# ponytail: mirrors the one picker guard there is; a new AskUserQuestion guard must also run here, before recording.
. "${BASH_SOURCE[0]%/*}/lib/ask-decoy.sh" || exit 0
ask_decoy_first "$INPUT" || exit 0

DECIDE="$(dirname "${BASH_SOURCE[0]}")/../scripts/decision.sh"
LOG="$(dirname "${COMMANDECK_RULING_LOG:-$HOME/.claude/rulings/x}")/ask-records-decision.log"
# The options are the labels less the decoy and the marker, for the dashboard's answer buttons (issue 240); a
# label holding "|" cannot be told apart from the next, so then none are kept.
ROWS=$(jq -c -L "${BASH_SOURCE[0]%/*}/lib" --arg day "$(date +%Y-%m-%d)" --arg decoy "$ASK_DECOY" 'include "decision-id"; .tool_input.questions[]? | [
  decision_id($day),
  (.question // ""),
  ([.options[]?.label // "" | select(test("\\(Recommended\\)\\s*$"))] | first
    | if . == null then "none" else sub("\\s*\\(Recommended\\)\\s*$"; "") end),
  ([.options[]?.label // "" | select(. != $decoy) | sub("\\s*\\(Recommended\\)\\s*$"; "")]
    | if length >= 2 and length <= 4 and all(length > 0 and (contains("|") | not)) then join("|") else "" end)]' <<<"$INPUT" 2>/dev/null)

RELAY=$(jq -r '.chiefOfStaff.name // empty' "${ROOT:-.}/.claude/commandeck.json" 2>/dev/null)
blocked() {
  [ -n "$RELAY" ] || return 0
  printf '%s\n' "BLOCKED: this question is already in front of the owner (state below); do not ask it again." \
    "Still open: do not re-ask; carry on with other work or end the turn, the answer arrives by itself. Answered: use that answer. Its state: \`bash scripts/decision.sh list\`." "$@" >&2
  exit 2
}
dups=() seen=() restore='{}' added=() add_failed=
while IFS= read -r row; do
  [ -n "$row" ] || continue
  q=$(jq -r '.[1]' <<<"$row")
  # stdout is the earlier decision's snapshot (a refused repeat, a decoy
  # retry or a re-asked one); stderr is the refusal.
  res=$(bash "$DECIDE" check "$(jq -r '.[0]' <<<"$row")" "$q" ${seen[@]+"${seen[@]}"} 2>&1); rc=$?
  if [ "$rc" -eq 3 ]; then dups+=("$(grep -v '^{' <<<"$res")")
  elif [ "$rc" -eq 0 ] && orig=$(jq -er '.question' <<<"$res" 2>/dev/null) && [ "$orig" != "$q" ]; then
    restore=$(jq -c --arg i "${#seen[@]}" --arg o "$orig" '. + {($i): $o}' <<<"$restore")
  fi
  seen+=("$q")
done <<<"$ROWS"
[ ${#dups[@]} -eq 0 ] || blocked "${dups[@]}"
while IFS= read -r row; do
  [ -n "$row" ] || continue
  id=$(jq -r '.[0]' <<<"$row") q=$(jq -r '.[1]' <<<"$row") d=$(jq -r '.[2]' <<<"$row") o=$(jq -r '.[3]' <<<"$row")
  err=$(bash "$DECIDE" add "$id" "$q" "$d" AskUserQuestion ${o:+--options "$o"} 2>&1 >/dev/null) && { added+=("$id"); continue; }
  # A repeat that raced in after the check above.
  if [ $? -eq 3 ]; then blocked "$err"; continue; fi
  add_failed=1
  HOOK_FIRE_ADVISE=1
  mkdir -p "${LOG%/*}" 2>/dev/null
  printf '%s %s\n' "$(date -u +%FT%TZ)" "$err" | tee -a "$LOG" >&2
done <<<"$ROWS"
# Issue 350: with the Chief of Staff live, the recorded row IS how the owner sees the question (it relays the decisions
# queue), and a picker in main's pane is one the owner is not watching. So the picker is refused AFTER every row is
# written (a refusal before recording would be a question the owner never saw). A failed add leaves the picker allowed,
# and so does a Chief of Staff pane that is not found or not readable: the row is written either way, and a closed door
# would block main's only route to the owner. With no relay named (setup's default) nothing is refused, as above.
if [ -z "$add_failed" ] && [ ${#added[@]} -gt 0 ] && [ -n "$RELAY" ] && bash "${BASH_SOURCE[0]%/*}/../scripts/cos-tell.sh" --handle >/dev/null 2>&1; then
  ids=$(IFS=,; echo "${added[*]}")
  printf '%s\n' "BLOCKED: do not open a picker while the Chief of Staff is live. This question is recorded in the decisions ledger as $ids: the Chief of Staff puts it to the owner and relay-order.sh sends the answer back." \
    "Carry on with other work or end the turn; the answer arrives by itself (\`scripts/relay-order.sh\` delivers it, no call needed)." >&2
  exit 2
fi
# A decoy or re-ask retry that came back reworded shows the ORIGINAL question:
# ruling-log.sh closes the row only on an exact question match. "ask"
# keeps the picker in front of the owner; "allow" could answer it unseen.
[ "$restore" = '{}' ] && exit 0
HOOK_FIRE_ASK=1
jq -c --argjson r "$restore" '{hookSpecificOutput: {hookEventName: "PreToolUse",
  permissionDecision: "ask", permissionDecisionReason: "retry of an open decision: the original question is shown",
  updatedInput: (.tool_input | .questions |= [to_entries[] | .value + (if $r[.key | tostring] then {question: $r[.key | tostring]} else {} end)])}}' <<<"$INPUT"
exit 0

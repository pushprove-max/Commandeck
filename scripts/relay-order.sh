#!/usr/bin/env bash
# relay-order.sh <decision id> '<the owner's words verbatim>' -- the relay's one step for an owner's order on a decision.
# It answers the decision, sends main the order with its ruling id (to-main.sh question), and marks the decision
# seen for cos-watch-decisions.sh. Prints one line.
# Issue 231: the relay did those three by hand, and a skipped step left main waiting or the decision firing again.
# The ruling id is the newest one ruling-log.sh logged whose answer is those words, given since the decision was
# asked, and on its question (a chat prompt has none); with none, or an unknown decision, or one answered with
# other words, nothing changes and it exits 1. The same order again after main was not told resumes the send
# with the ruling it stored. An order on an auto-decided answer replaces it (decision.sh answer --correct keeps the
# old one in the row's history): that is how the owner reverses the relay's decision.
# Exit 0 when main got the order or it is queued for main.
# relay-order.sh --auto <id> <words> <why> <trade-off> <would-change> <reversible> -- issue 333: while /autodecide is on
# (<main>/.claude/metrics/autodecide.on names the log), the relay's own decision for the owner. There is no ruling to
# find. In this order: the entry goes into the log (before anything changes), the ledger answer is "<words>
# (auto-decided)", the decision is marked seen, main is told. Every argument is required. The same call again after
# main was not told resumes the send, with no second entry, even once auto-decide is off.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
AUTO=; [ "${1-}" != --auto ] || { AUTO=1; shift; }
if [ -n "$AUTO" ]; then
  [ $# = 6 ] && [ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ] && [ -n "$4" ] && [ -n "$5" ] && [ -n "$6" ] \
    || { echo "usage: relay-order.sh --auto <decision id> <words> <why> <trade-off> <would-change> <reversible> (each required)" >&2; exit 2; }
  ID=$1 WORDS=$2 WHY=$3 TRADE=$4 WOULD=$5 REV=$6
else
  [ $# = 2 ] && [ -n "$1" ] && [ -n "$2" ] || { echo "usage: relay-order.sh <decision id> '<the owner's words verbatim>'" >&2; exit 2; }
  ID=$1 WORDS=$2
fi
. "$(dirname "${BASH_SOURCE[0]}")/cos-lib.sh"
pp_project "$PP_MAIN"
LOG=${COMMANDECK_RULING_LOG:-$HOME/.claude/rulings/$PP_PROJECT.jsonl}
DEC=$(bash "$PP_SCRIPTS/decision.sh" list | jq -c --arg id "$ID" '.[] | select(.id == $id)') || exit 1
[ -n "$DEC" ] || { echo "relay-order: unknown decision $ID; nothing changed" >&2; exit 1; }
refuse() { echo "relay-order: decision $ID is already answered \"$(jq -r .answer <<<"$DEC")\"; nothing changed" >&2; exit 1; }
# r1: an answered row whose answer is exactly what this call would write is a send that failed before, resumed from
# the row alone (no second entry or answer; the seen mark, the mode file and the log need not be there).
if [ -n "$AUTO" ]; then
  ALOG=$(cat "$PP_MAIN/.claude/metrics/autodecide.on" 2>/dev/null)
  if jq -e '.answeredAt == null' <<<"$DEC" >/dev/null; then
    [ -n "$ALOG" ] || { echo "relay-order: auto-decide is off (no $PP_MAIN/.claude/metrics/autodecide.on); nothing changed" >&2; exit 1; }
    # One line per field: a newline in an argument must not start a second "### " entry, which the band counts.
    flat() { tr '\n' ' ' <<<"$*" | sed 's/  */ /g; s/ $//'; }
    {
      printf '\n### %s: %s, %s (auto-decided)\n' "$(date +%H:%M)" "$ID" "$(flat "$(jq -r '.question[0:60]' <<<"$DEC")")"
      printf -- '- **Question**: %s\n' "$(flat "$(jq -r .question <<<"$DEC")")"
      printf -- '- **Options**: %s\n' "$(flat "$(jq -r 'if (.options // []) == [] then "none listed, default: \(.proposedDefault)" else .options | join(" / ") end' <<<"$DEC")")"
      printf -- '- **Picked**: %s\n' "$(flat "$WORDS")"
      printf -- '- **Why**: %s Trade-off weighed: %s. Would pick differently if: %s.\n' "$(flat "$WHY")" "$(flat "$TRADE")" "$(flat "$WOULD")"
      printf -- '- **Reversible**: %s\n' "$(flat "$REV")"
    } >> "$ALOG" || { echo "relay-order: could not write the log $ALOG; nothing changed" >&2; exit 1; }
    if ! ROW=$(bash "$PP_SCRIPTS/decision.sh" answer "$ID" "$WORDS (auto-decided)" 2>&1); then
      printf -- '- **Ledger**: not recorded (%s)\n' "$(flat "$ROW")" >> "$ALOG"
      echo "relay-order: the entry is in $ALOG but the ledger did not take the answer: $ROW; main was NOT told" >&2; exit 1
    fi
  elif jq -e --arg a "$WORDS (auto-decided)" '.answer == $a' <<<"$DEC" >/dev/null; then ROW=$DEC
  else refuse; fi
  WHAT="$ID auto-decided, logged" SUBJ="auto-decided for the owner on $ID"
  BODY="$WORDS. Why: $WHY. Reversible: $REV. Log: ${ALOG:-none (auto-decide is off now)}"
else
  # Issue 231 r1: words alone let an old "yes" to another question authorize this one.
  RIDS=$(jq -r --arg w "$WORDS" --argjson d "$DEC" 'def t: gsub("^\\s+|\\s+$"; "");
    select(.void != true and ((.answer // "") | t) == ($w | t) and (.utc // "") >= $d.askedAt
      and (.question == null or (.question | t) == ($d.question | t))) | .id' "$LOG" 2>/dev/null)
  RID=$(tail -1 <<<"$RIDS")
  [ -n "$RID" ] || { echo "relay-order: no ruling in $LOG gives those words to $ID's question since it was asked; nothing changed" >&2; exit 1; }
  if jq -e '.answeredAt == null' <<<"$DEC" >/dev/null; then
    ROW=$(bash "$PP_SCRIPTS/decision.sh" answer "$ID" "$WORDS ($RID)") || exit 1
  # r1: the owner's order reverses an auto-decision; the auto answer goes to the row's history. Only an auto answer:
  # one the owner gave stays.
  elif jq -e '.answer // "" | endswith(" (auto-decided)")' <<<"$DEC" >/dev/null; then
    ROW=$(bash "$PP_SCRIPTS/decision.sh" answer "$ID" "$WORDS ($RID)" --correct) || exit 1
  # Resume with the ruling it stored, if that one still gives these words (r2: not the newest).
  elif OLD=$(jq -r --arg w "$WORDS" '.answer // "" | select(startswith($w + " (") and endswith(")")) | .[($w | length) + 2:-1]' <<<"$DEC") \
    && [ -n "$OLD" ] && grep -qxF -- "$OLD" <<<"$RIDS"; then ROW=$DEC RID=$OLD
  else refuse; fi
  WHAT="$ID answered with $RID" SUBJ="order from the owner on $ID ($RID)" BODY=$WORDS
fi
jq -r '"\(.id)@\(.askedAt)"' <<<"$ROW" >> "$COS_KEY.decisions-seen"
bash "$PP_SCRIPTS/to-main.sh" question "$SUBJ" "$BODY" >/dev/null; rc=$?
case $rc in
  0) echo "relay-order: $WHAT, main told, marked seen" ;;
  3) echo "relay-order: $WHAT, queued for main (it is down), marked seen" ;;
  *) echo "relay-order: $WHAT and marked seen, but main was NOT told: bash $PP_SCRIPTS_Q/to-main.sh question '$SUBJ' '<the words>'" >&2; exit 1 ;;
esac

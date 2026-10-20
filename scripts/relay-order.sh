#!/usr/bin/env bash
# relay-order.sh <decision id> '<the owner's words verbatim>' -- the relay's one step for an owner's order on a decision.
# It answers the decision, sends main the order with its ruling id (to-main.sh question), and marks the decision
# seen for cos-watch-decisions.sh. Prints one line.
# Issue 231: the relay did those three by hand, and a skipped step left main waiting or the decision firing again.
# The ruling id is the newest one ruling-log.sh logged whose answer is those words, given since the decision was
# asked, and on its question (a chat prompt has none); with none, or an unknown decision, or one answered with
# other words, nothing changes and it exits 1. The same order again after main was not told resumes the send.
# Exit 0 when main got the order or it is queued for main.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
[ $# = 2 ] && [ -n "$1" ] && [ -n "$2" ] || { echo "usage: relay-order.sh <decision id> '<the owner's words verbatim>'" >&2; exit 2; }
ID=$1 WORDS=$2
. "$(dirname "${BASH_SOURCE[0]}")/cos-lib.sh"
pp_project "$PP_MAIN"
LOG=${COMMANDECK_RULING_LOG:-$HOME/.claude/rulings/$PP_PROJECT.jsonl}
DEC=$(bash "$PP_SCRIPTS/decision.sh" list | jq -c --arg id "$ID" '.[] | select(.id == $id)') || exit 1
[ -n "$DEC" ] || { echo "relay-order: unknown decision $ID; nothing changed" >&2; exit 1; }
# Issue 231 r1: words alone let an old "yes" to another question authorize this one.
RID=$(jq -r --arg w "$WORDS" --argjson d "$DEC" 'def t: gsub("^\\s+|\\s+$"; "");
  select(.void != true and ((.answer // "") | t) == ($w | t) and (.utc // "") >= $d.askedAt
    and (.question == null or (.question | t) == ($d.question | t))) | .id' "$LOG" 2>/dev/null | tail -1)
[ -n "$RID" ] || { echo "relay-order: no ruling in $LOG gives those words to $ID's question since it was asked; nothing changed" >&2; exit 1; }
if jq -e '.answeredAt == null' <<<"$DEC" >/dev/null; then
  ROW=$(bash "$PP_SCRIPTS/decision.sh" answer "$ID" "$WORDS ($RID)") || exit 1
elif jq -e --arg a "$WORDS ($RID)" '.answer == $a' <<<"$DEC" >/dev/null; then ROW=$DEC  # a send that failed before: resume it
else echo "relay-order: decision $ID is already answered \"$(jq -r .answer <<<"$DEC")\"; nothing changed" >&2; exit 1; fi
jq -r '"\(.id)@\(.askedAt)"' <<<"$ROW" >> "$COS_KEY.decisions-seen"
bash "$PP_SCRIPTS/to-main.sh" question "order from the owner on $ID ($RID)" "$WORDS" >/dev/null; rc=$?
case $rc in
  0) echo "relay-order: $ID answered with $RID, main told, marked seen" ;;
  3) echo "relay-order: $ID answered with $RID, queued for main (it is down), marked seen" ;;
  *) echo "relay-order: $ID answered with $RID and marked seen, but main was NOT told: bash $PP_SCRIPTS_Q/to-main.sh question 'order from the owner on $ID ($RID)' '<the words>'" >&2; exit 1 ;;
esac

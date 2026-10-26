#!/usr/bin/env bash
# ask-main.sh <subject> <body> -- ask main a question and wait for its answer.
# ask-main.sh --resume <id> -- wait again for the question <id> (printed by the first call).
# Sends through to-main.sh (a main that is down gets it queued), then waits in slices of at
# most 240 s on this pane's inbox for the reply threaded to the question. The wait ends at 9
# minutes from the send. Exit 0: answered (printed); 3: no answer yet, or main is down and
# the answer is typed into this pane; 1: the send failed; 2: usage.
# --resume first reads the full inbox view, for an answer an earlier read acknowledged without printing. Past the deadline
# main is sent "ask-main: <id> unanswered" once, so a lost answer is told from none. While a call is blocked in the
# inbox wait, and only then, <id>.wait beside the state file names its pid and pane: answer-worker.sh --interrupt types
# into a pane only while it holds that token (issue 351). A pane between slices is working, and an interrupt would cut that.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -6; exit 0 ;; esac
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || exit 1
now() { echo "${COMMANDECK_ASK_MAIN_NOW:-$(date +%s)}"; }
D=$PP_SCRATCH/ask-main
H=${ORCA_TERMINAL_HANDLE:-}
[ -n "$H" ] || { echo "ask-main: ORCA_TERMINAL_HANDLE is not set: this is not an Orca pane" >&2; exit 2; }
if [ "${1:-}" = --resume ]; then
  [ $# = 2 ] && [[ $2 =~ ^[A-Za-z0-9._-]+$ ]] || { echo "usage: ask-main.sh --resume <id>" >&2; exit 2; }
  ID=$2
  [ -f "$D/$ID" ] || { echo "ask-main: no waiting question $ID (answered, or never sent from this pane)" >&2; exit 2; }
  # The full inbox view still holds an answer whose batch an earlier read acknowledged without printing it; take it
  # before waiting again (issue 351). Its batch, if never acknowledged, is shown again by the next inbox read.
  FULL=$(orca-ide orchestration check --terminal "$H" --all --json 2>/dev/null | jq -er --arg id "$ID" \
    '[.result.messages[]? | select(.thread_id == $id) | .body // ""] | if length > 0 then join("\n") else empty end' 2>/dev/null) \
    && { printf '%s\n' "$FULL"; echo "note: taken from the full inbox view; your next inbox read may show it again"; rm -f "$D/$ID"; exit 0; }
else
  [ $# = 2 ] || { echo "usage: ask-main.sh <subject> <body> | --resume <id>" >&2; exit 2; }
  OUT=$("$(dirname "${BASH_SOURCE[0]}")/to-main.sh" question "$1" "$2"); RC=$?
  [ -z "$OUT" ] || echo "$OUT"
  case $RC in
    0) ;;
    3) echo "ask-main: main is down; the question is queued and main's answer is typed into your pane. Main sees the queue only when a main session starts in its own checkout; a main running elsewhere must be told another way."; exit 3 ;;
    *) exit "$RC" ;;
  esac
  # to-main's sent line: "sent to <who> (<handle>) id <id>", a warning after it when main's pane shows a prompt.
  ID=$(sed -n 's/^to-main: sent to [^)]*) id \([A-Za-z0-9._-]*\).*/\1/p' <<<"$OUT" | head -1)
  [ -n "$ID" ] || { echo "ask-main: the send gave no message id to wait on" >&2; exit 1; }
  mkdir -p "$D" && printf 'deadline=%s\nack=\n' "$(( $(now) + 540 ))" > "$D/$ID" || exit 1
fi
DEADLINE=$(sed -n 's/^deadline=//p' "$D/$ID"); ACK=$(sed -n 's/^ack=//p' "$D/$ID")
LEFT=$(( DEADLINE - $(now) ))
if [ "$LEFT" -le 0 ]; then
  # Once, so main can tell an answer that was lost from none (issue 351). A send that failed is tried again next call.
  if ! grep -qx 'told=1' "$D/$ID"; then
    "$(dirname "${BASH_SOURCE[0]}")/to-main.sh" question "ask-main: $ID unanswered" \
      "The question $ID from pane $H got no answer in 9 minutes. If you answered it, the answer did not reach the pane: bash $PP_SCRIPTS_Q/answer-worker.sh $H \"<answer>\" $ID" >/dev/null 2>&1
    case $? in 0|3) echo 'told=1' >> "$D/$ID" ;; esac
  fi
  echo "no answer in 9 minutes: build what the answer cannot change and end your turn; main's answer is typed into your pane"; exit 3
fi
SLICE_END=$(( $(now) + (LEFT < 240 ? LEFT : 240) ))
# <id>.wait (pid= and pane=, the pane waiting now: a --resume from a restarted Builder's new handle names that one) is
# written just before each inbox wait and removed as it returns. answer-worker.sh --interrupt sends only while it holds
# the token, taken by one mv into <id>.claim.<its pid>: of that mv and this rm exactly one wins. When the rm finds the
# token claimed, this call waits for the claim to go (its sender alive, 60 s at most), so the interrupt lands while the
# call still runs. A token left by a killed call names a dead pid, which the claimer refuses.
TOK=$D/$ID.wait
unwait() { local c i
  rm "$TOK" 2>/dev/null && return 0
  for c in "$D/$ID".claim.*; do i=0
    while [ -e "$c" ] && kill -0 "${c##*.}" 2>/dev/null && [ "$i" -lt 600 ]; do sleep 0.1; i=$((i + 1)); done
  done; }
trap unwait EXIT
# Each pass reads one whole batch. A batch without the answer is acknowledged by the next call's --ack, so its
# other messages are printed here: nothing is dropped.
while :; do
  WAIT=$(( SLICE_END - $(now) ))
  [ "$WAIT" -gt 0 ] || break
  printf 'pid=%s\npane=%s\n' "$$" "$H" > "$TOK.tmp" && mv -f "$TOK.tmp" "$TOK" || exit 1
  R=$(orca-ide orchestration check --terminal "$H" --wait --timeout-ms $((WAIT * 1000)) ${ACK:+--ack "$ACK"} --json 2>/dev/null); RC=$?
  unwait
  [ "$RC" = 0 ] && jq -e '.ok' >/dev/null 2>&1 <<<"$R" \
    || { echo "ask-main: the inbox check failed; resume with ask-main.sh --resume $ID" >&2; exit 1; }
  DEL=$(jq -r '.result.deliveryId // empty' <<<"$R")
  [ -n "$DEL" ] && [ "$(jq '[.result.messages[]?] | length' <<<"$R")" != 0 ] || break
  ACK=$DEL; sed -i.bak "s/^ack=.*/ack=$ACK/" "$D/$ID" && rm -f "$D/$ID.bak"
  OTHERS=$(jq -r --arg id "$ID" '.result.messages[] | select(.thread_id != $id) | "- [\(.type // "message")] \(.subject // "") (from \(.from_handle // "?")): \(.body // "")"' <<<"$R")
  ANSWER=$(jq -r --arg id "$ID" '[.result.messages[] | select(.thread_id == $id) | .body // ""] | join("\n")' <<<"$R")
  if jq -e --arg id "$ID" 'any(.result.messages[]; .thread_id == $id)' >/dev/null <<<"$R"; then
    printf '%s\n' "$ANSWER"
    [ -z "$OTHERS" ] || printf 'also in your inbox:\n%s\n' "$OTHERS"
    # The acknowledgment's own answer is the next batch: not printed, not acknowledged, shown again by the next read.
    orca-ide orchestration check --terminal "$H" --ack "$ACK" --json >/dev/null 2>&1 \
      || echo "warning: the answer's batch was not acknowledged; your next inbox read shows it again"
    rm -f "$D/$ID"; exit 0
  fi
  [ -z "$OTHERS" ] || printf 'also in your inbox:\n%s\n' "$OTHERS"
done
echo "no answer yet: resume with ask-main.sh --resume $ID ($(( DEADLINE - $(now) )) s of 540 left)"
exit 3

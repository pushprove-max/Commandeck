#!/usr/bin/env bash
# builder-fresh-round.sh <handle> <hand-off file> [<seat record>] -- start a Builder's next round in a fresh
# session of the same pane: wait until the pane is idle and stays idle, type /clear, wait for the new session,
# then type the pointer to the hand-off file. Same pane, handle, Orca task and dispatch; new transcript. With a
# seat record, the new session's id is appended as its last session= line, which main-watch.sh reads, so main
# watches the new log and not the cleared one.
# builder-codex-pass.sh runs it after a NO-GO pass, and builder-add-work.sh when main adds work, each as a plain
# background child. A pane that does not settle in 15 minutes gets nothing typed: the reason goes to stderr,
# the exit is 1, and the round stays in the old session.
# Self-test: bash scripts/__tests__/builder-codex-pass.test.sh
set -uo pipefail
H=${1:?usage: builder-fresh-round.sh <handle> <hand-off file> [<seat record>]}
HAND=${2:?usage: builder-fresh-round.sh <handle> <hand-off file> [<seat record>]}
REC=${3:-}
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
LIMIT=900 SETTLE=${COMMANDECK_FRESH_ROUND_SETTLE_SECONDS:-20}
idle() { orca-ide terminal wait --terminal "$H" --for tui-idle --timeout-ms "$1" --json >/dev/null 2>&1; }
fail() { echo "builder-fresh-round: $1; the round of $HAND stays in the old session." >&2; exit 1; }
END=$((SECONDS + LIMIT))
# Idle twice, SETTLE apart: a background-task notice can wake the old session just after it ends its turn, and
# /clear typed into a busy turn is lost.
while :; do
  left=$((END - SECONDS))
  { [ "$left" -gt 0 ] && idle "$((left * 1000))"; } || fail "pane $H was not idle within ${LIMIT}s; nothing typed"
  sleep "$SETTLE"
  idle 1000 && break
done
STAMP=$(mktemp) || fail "cannot make a temp file; nothing typed"
trap 'rm -f "$STAMP"' EXIT
orca-ide terminal send --terminal "$H" --text /clear --enter --json >/dev/null 2>&1 || fail "typing /clear into $H failed; nothing typed"
idle 120000 || fail "typed /clear but the new session of $H was not idle within 120s; the hand-off pointer was not typed"
orca-ide terminal send --terminal "$H" --text "Your task spec is the file $HAND. Read all of it now and do what it says." \
  --enter --json >/dev/null 2>&1 || fail "typed /clear but typing the hand-off pointer into $H failed"
echo "builder-fresh-round: $H cleared and handed $HAND"
[ -n "$REC" ] && [ -f "$REC" ] || exit 0
# The new session is the log written since /clear that carries the pointer, other than the one the record names.
OLD=$(sed -n 's/^session=//p' "$REC" | tail -1)
PROJ=$HOME/.claude/projects/$(pp_slug "${HAND%/.claude/briefs/*}")
NEW=
for _ in $(seq 30); do
  NEW=$(find "$PROJ" -maxdepth 1 -name '*.jsonl' -newer "$STAMP" ! -name "${OLD:-none}.jsonl" -exec grep -lF -- "$HAND" {} + 2>/dev/null | head -1)
  [ -n "$NEW" ] && break
  sleep 2
done
[ -n "$NEW" ] || { echo "builder-fresh-round: no new session log in $PROJ names $HAND after 60s; $REC still names session ${OLD:-none}" >&2; exit 1; }
NEW=${NEW##*/}
echo "session=${NEW%.jsonl}" >> "$REC"
echo "builder-fresh-round: $REC now names session ${NEW%.jsonl}"

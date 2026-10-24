#!/usr/bin/env bash
# inbox-drain.sh main | --unit <unit> -- run at session start
# (agent-startup-context.sh) in main or a Builder. Records this pane's handle,
# then prints what reached no live pane while the seat was down: the queue
# to-main.sh keeps, and the unread messages sent to the seat's earlier handles.
# Prints nothing when there is none, as for a seat that never restarted.
#
# The queue is printed first, before any slow check, and is taken off only once
# printed: a drain killed part way (the startup hook gives it 30 s) shows it
# again next time. A queued message that does not fit is moved to a held file
# that nothing overwrites, and the output says how to read it.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh" 2>/dev/null || exit 0
# The startup cut is in bytes: so is every length here.
export LC_ALL=C
case ${1:-} in
  main) KEY=main ;;
  --unit) [[ ${2:-} =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || exit 2; KEY=unit-$2 ;;
  *) echo "usage: inbox-drain.sh main | --unit <unit>" >&2; exit 2 ;;
esac
NOW=${ORCA_TERMINAL_HANDLE:-} D=$PP_SCRATCH/queue F=$PP_SCRATCH/handles/$KEY
Q=$D/$KEY.jsonl HELD=$D/$KEY.held.jsonl
# No unit-less queue to migrate: these files came with 0.4.5, and no released plugin wrote another shape (main, CD-NO-MIGRATE).
mkdir -p "$D" "${F%/*}" || exit 0
# Another seat in a Builder's worktree (a risky build's design co-author) starts with the Builder's
# settings. seat.sh's launch record names it: its start neither stands for the Builder nor takes its mail.
[ "$KEY" = main ] || [ "${COMMANDECK_SEAT:-builder}" = builder ] || exit 0
[ "$KEY" = main ] || [ -z "$NOW" ] \
  || ! awk -F'\t' -v h="$NOW" '$3 == h && $2 !~ /^Builder / { f = 1 } END { exit !f }' "$PP_SCRATCH/pane-titles.tsv" 2>/dev/null || exit 0
# Session-start output past 10240 bytes is cut; this share stays under 3000.
LEFT=3000 SAID=
say() {
  [ -n "$SAID" ] || { echo "# Messages that reached no live pane while this seat was down (a restart changed its handle); read them first:"; SAID=1; }
  printf '%s\n' "$1"; LEFT=$((LEFT - ${#1} - 1))
}
# Messages sent meanwhile go to a new queue file; a .taking file left by a killed drain is shown again.
if mv "$Q" "$Q.$$" 2>/dev/null && ! { cat "$Q.$$" >> "$Q.taking" && rm -f "$Q.$$"; } 2>/dev/null; then
  # Not taken: it goes back in front of what was sent meanwhile, and is shown at a later start.
  { { cat "$Q.$$" && { [ ! -e "$Q" ] || cat "$Q"; }; } > "$Q.back.$$" && mv "$Q.back.$$" "$Q" && rm -f "$Q.$$"; } 2>/dev/null
  say "- queued messages could not be taken for showing ($Q.taking cannot be written); they stay queued in ${Q}$([ -e "$Q.$$" ] && echo " and $Q.$$")"
fi
if [ -s "$Q.taking" ]; then
  N=0 LOST=0
  while IFS= read -r m; do
    l=$(jq -r '"- [\(.type)] \(.subject) (queued \(.at)): \(.body)"' <<<"$m" 2>/dev/null) || l="- (unreadable queued line) $m"
    if [ $(( ${#l} + 300 )) -lt "$LEFT" ]; then say "$l"
    elif printf '%s\n' "$m" >> "$HELD" 2>/dev/null; then N=$((N + 1))
    else LOST=1; fi
  done < "$Q.taking"
  [ "$N" = 0 ] || say "- $N queued message(s) did not fit here, kept whole in $HELD: read them with: jq -r '\"[\\(.type)] \\(.subject): \\(.body)\"' $HELD, then delete that file"
  # The only copy stays where it is: shown again next start rather than lost.
  if [ "$LOST" = 1 ]; then say "- queued messages that did not fit could not be moved to $HELD; they stay in $Q.taking, whole, and are shown again at the next start"
  else rm -f "$Q.taking"; fi
fi
# The handle is recorded before the slow checks below, so a killed drain still keeps it.
# The last five handles are kept: an older one's messages were shown by a session since.
# A handle whose check has not yet answered stays on the to-check list ($F.unchecked) until one does.
U=$F.unchecked
OLD=$( { cat "$U" 2>/dev/null; grep -vxF -- "$NOW" "$F" 2>/dev/null | tail -4; } | awk 'NF && !seen[$0]++')
[ -z "$NOW" ] || pp_handle_record "$KEY" "$NOW"
[ -z "$OLD" ] || printf '%s\n' "$OLD" > "$U"
# Four checks of 5 s at most stay inside the startup hook's 30 s; the rest wait on the list for a later start.
n=0
while IFS= read -r h; do
  [ -n "$h" ] || continue
  n=$((n + 1)); [ "$n" -le 4 ] || break
  out=$(timeout 5 orca-ide orchestration check --terminal "$h" --unread --json 2>/dev/null) && jq -e '.ok' <<<"$out" >/dev/null 2>&1 || { FAILED+=$h$'\n'; continue; }
  { grep -vxF -- "$h" "$U" > "$U.new"; mv "$U.new" "$U"; } 2>/dev/null
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    [ $(( ${#l} + 100 )) -lt "$LEFT" ] || { say "[cut to fit; the rest: orca-ide orchestration check --terminal $h --all]"; break; }
    say "$l"
  done < <(jq -r --arg h "$h" '.result.messages[]? | "- [\(.type // "message")] \(.subject // "") (to \($h)\(if .from then ", from \(.from)" else "" end)): \(.body // "")"' <<<"$out" 2>/dev/null)
done <<<"$OLD"
# A failed check goes to the back of the list, so the handles behind it are checked at the next start.
[ -z "${FAILED:-}" ] || { { grep -vxF -f <(printf '%s' "$FAILED") "$U"; printf '%s' "$FAILED"; } > "$U.new" && mv "$U.new" "$U"; } 2>/dev/null
exit 0

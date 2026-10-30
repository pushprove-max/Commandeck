#!/usr/bin/env bash
# covers: scripts/merge-unit-local.sh
# timeout: 240
# merge-unit-local.sh step 5 fails toward KEEPING the worktree (host issue 3028): the unit's panes close and its Codex
# helpers stop before any brief is archived, and a path git still lists, or a pane that will not close, holds the worktree.
# Its own file: merge-unit-local.test.sh already runs near its cap.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
. "$(dirname "$0")/fixtures/merge-unit-local-setup.sh"

# A wrapper in front of the fixture's orca-ide: a terminal close notes whether the brief archive exists yet (the order
# the plan pins), and answers refused while close-fails exists (a pane that will not close).
mkdir -p "$TMP/wrap"
cat > "$TMP/wrap/orca-ide" <<WRAP
#!/usr/bin/env bash
if [ "\$1 \$2" = "terminal close" ]; then
  [ -e "$HOME/.commandeck/briefs/proj/\$(cat "$TMP/unit").tar" ] && echo archive-first >> "$TMP/close-order" || echo close-first >> "$TMP/close-order"
  [ ! -e "$TMP/late-write" ] || echo late > "\$(cat "$TMP/late-write")"
  [ ! -e "$TMP/late-rm" ] || rm -f "\$(cat "$TMP/late-rm")"
  [ ! -e "$TMP/close-fails" ] || { echo '{"ok":false,"error":{"code":"stuck"}}'; exit 1; }
fi
if [ "\$1 \$2" = "terminal list" ] && [ -e "$TMP/list-answer" ]; then
  # list-answer holds what the listing prints, then its exit code on the last line; list-after, when it exists, is
  # what the listing prints once a pane was closed.
  A=$TMP/list-answer; [ ! -s "$TMP/closed" ] || [ ! -e "$TMP/list-after" ] || A=$TMP/list-after
  sed '\$d' "\$A"; exit "\$(tail -1 "\$A")"
fi
exec "$TMP/bin/orca-ide" "\$@"
WRAP
chmod +x "$TMP/wrap/orca-ide"; PATH=$TMP/wrap:$PATH
gone() { [ -d "$COMMANDECK_WORKSPACES/$1" ]; } # <unit>: the unit's worktree is still there
W() { echo "$COMMANDECK_WORKSPACES/$1"; }

# A writer's pane that lands a file, or a deletion, while it closes: step 1 refuses a worktree that is dirty at the start,
# so the hold is for what appears after it. late-write and late-rm name the path the next close writes or removes.
mk c1; go c1; echo "$(W c1)/unsaved.txt" > "$TMP/late-write"
RC=$(merge c1); rm -f "$TMP/late-write"
check "a worktree with an uncommitted file is kept: exit 5, the merge stands, the path on the DONE line" "5 yes 1 1" \
  "$RC $(gone c1 && echo yes) $(grep -c '^DONE unit=c1 .*cleanup HELD: .*unsaved.txt' "$TMP/out") $(git -C "$REPO" log --format=%s -1 | grep -c c1)"
check "the held worktree is never sent to worktree remove, and the hold names the retry (close the panes, then --cleanup), never a forced remove, on the step line and the DONE line" "0 2 0" \
  "$(grep -c '^worktree remove' "$TMP/orca-calls" || true) $(grep -c "cleanup HELD: .*close the unit's panes.*merge-unit-local.sh c1 --cleanup" "$TMP/out" || true) $(grep 'cleanup HELD' "$TMP/out" | grep -c -- '--force' || true)"

: > "$TMP/orca-calls"; : > "$TMP/close-order"
mk c2; go c2
RC=$(merge c2)
check "a clean worktree is removed as before: exit 0, the worktree gone" "0 gone" "$RC $(gone c2 && echo kept || echo gone)"
check "the unit's panes close before any brief is archived" "close-first" "$(head -1 "$TMP/close-order")"
check "the pane close is logged with its cause" "yes" "$(find "$COMMANDECK_SCRATCH" -name pane-closes.log -exec grep -h 'merge cleanup' {} + | grep -q . && echo yes)"

mk c3; go c3; echo "$(W c3)/c3.txt" > "$TMP/late-rm"
RC=$(merge c3); rm -f "$TMP/late-rm"
check "a deleted tracked file does not hold (its bytes are in the merged HEAD)" "0" "$RC"

: > "$TMP/close-order"; touch "$TMP/close-fails"
mk c4; go c4
RC=$(merge c4)
check "a pane that will not close: exit 5, the worktree kept, the DONE line says so" "5 yes 1" \
  "$RC $(gone c4 && echo yes) $(grep -c '^DONE unit=c4 .*cleanup HELD: .*a pane did not close' "$TMP/out")"
check "a pane that will not close leaves no brief archived" "0" "$(tar -tf "$HOME/.commandeck/briefs/proj/c4.tar" 2>/dev/null | wc -l | tr -d ' ')"
rm -f "$TMP/close-fails"

# A pane listing that cannot be read proves no writer stopped: an empty listing is not an empty worktree. A failed call
# and an answer that is not a terminal list both hold, as a refused close does.
n=0
for answer in 'Orca unavailable\n1' '{"ok":false,"error":{"code":"ipc"}}\n0' 'not json\n0' '\n0'; do
  n=$((n + 1)); : > "$TMP/orca-calls"; printf "$answer\n" > "$TMP/list-answer"
  mk l$n; go l$n
  RC=$(merge l$n)
  check "an unreadable pane listing ($(head -1 "$TMP/list-answer" | grep . || echo 'an empty answer')): exit 5, the worktree kept and not sent to remove, no brief archived, the DONE line says so" "5 yes 0 0 1" \
    "$RC $(gone l$n && echo yes) $(grep -c '^worktree remove' "$TMP/orca-calls" || true) $(tar -tf "$HOME/.commandeck/briefs/proj/l$n.tar" 2>/dev/null | wc -l | tr -d ' ') $(grep -c "^DONE unit=l$n .*cleanup HELD: .*pane list" "$TMP/out")"
done
for answer in '{"result":{"terminals":[]}}\n0' '{"result":[]}\n0'; do
  n=$((n + 1)); printf "$answer\n" > "$TMP/list-answer"
  mk l$n; go l$n
  RC=$(merge l$n)
  check "a readable pane listing with no pane of the unit ($(head -1 "$TMP/list-answer")) still removes the worktree" "0 gone" "$RC $(gone l$n && echo kept || echo gone)"
done
# Orca names a pane's worktree in any of three fields (wtp in project-main.sh): each one's pane is closed before the
# worktree goes. The proof is the listing read again after the closes: a close that answered ok while the pane is
# still listed holds.
printf '{"result":{"terminals":[]}}\n0\n' > "$TMP/list-after"
for field in worktreePath worktreeId ptyId; do
  n=$((n + 1)); : > "$TMP/closed"; mk l$n; go l$n
  case $field in worktreePath) v=$(W l$n) ;; worktreeId) v="wt1::$(W l$n)" ;; ptyId) v="wt1::$(W l$n)@@ab12" ;; esac
  jq -cn --arg f $field --arg v "$v" '{result: {terminals: [{handle: "term_writer", ($f): $v}]}}' > "$TMP/list-answer"; echo 0 >> "$TMP/list-answer"
  RC=$(merge l$n)
  check "a pane named by $field is closed before the worktree is removed" "0 gone 1" "$RC $(gone l$n && echo kept || echo gone) $(grep -cx term_writer "$TMP/closed")"
done
rm -f "$TMP/list-after"; : > "$TMP/closed"; : > "$TMP/orca-calls"
n=$((n + 1)); mk l$n; go l$n
jq -cn --arg v "$(W l$n)" '{result: {terminals: [{handle: "term_writer", worktreePath: $v}]}}' > "$TMP/list-answer"; echo 0 >> "$TMP/list-answer"
RC=$(merge l$n)
check "a pane still listed after its close answered ok: exit 5, the worktree kept and not sent to remove, no brief archived, the DONE line names the pane" "5 yes 0 0 1" \
  "$RC $(gone l$n && echo yes) $(grep -c '^worktree remove' "$TMP/orca-calls" || true) $(tar -tf "$HOME/.commandeck/briefs/proj/l$n.tar" 2>/dev/null | wc -l | tr -d ' ') $(grep -c "^DONE unit=l$n .*cleanup HELD: .*still listed after the close: term_writer" "$TMP/out")"

# The retry path: `--cleanup` reruns step 5 from the unit's name alone. A held merge (an empty pane listing), then
# each piece of state the first run left is removed in turn, a retry between each: every retry closes the writer
# again (it is still listed, so each holds), and once the listing is empty the worktree goes.
n=$((n + 1)); u=l$n; mk $u; go $u; printf '\n0\n' > "$TMP/list-answer"
RC=$(merge $u)
check "the held merge names the retry, not a forced remove" "5 1 0" \
  "$RC $(grep -c "^DONE unit=$u .*cleanup HELD: .*then run .*merge-unit-local.sh $u --cleanup" "$TMP/out") $(grep 'cleanup HELD' "$TMP/out" | grep -c -- '--force' || true)"
jq -cn --arg v "wt1::$(W $u)" '{result: {terminals: [{handle: "term_writer", worktreeId: $v}]}}' > "$TMP/list-answer"; echo 0 >> "$TMP/list-answer"
got=""
for piece in seat-records finished-builds pane-closes-log brief-archive; do
  case $piece in
    seat-records) find "$COMMANDECK_SCRATCH" -name "seat-$u-*" -delete ;;
    finished-builds) rm -rf "$HOME/.commandeck/builds" ;;
    pane-closes-log) find "$COMMANDECK_SCRATCH" -name pane-closes.log -delete ;;
    brief-archive) rm -f "$HOME/.commandeck/briefs/proj/$u.tar" ;;
  esac
  : > "$TMP/closed"; RC=$(merge $u --cleanup)
  got="$got $piece:$RC:$(grep -cx term_writer "$TMP/closed"):$(gone $u && echo kept)"
done
check "with each piece of state removed in turn, --cleanup still closes the writer and holds while it is listed" \
  " seat-records:5:1:kept finished-builds:5:1:kept pane-closes-log:5:1:kept brief-archive:5:1:kept" "$got"
printf '{"result":{"terminals":[]}}\n0\n' > "$TMP/list-after"; : > "$TMP/closed"; : > "$TMP/orca-calls"
RC=$(merge $u --cleanup)
check "--cleanup once the writer closes: exit 0, the worktree removed, the briefs archived, nothing merged again" "0 gone 1 yes 1" \
  "$RC $(gone $u && echo kept || echo gone) $(grep -cx term_writer "$TMP/closed") $([ "$(tar -tf "$HOME/.commandeck/briefs/proj/$u.tar" 2>/dev/null | wc -l)" -gt 0 ] && echo yes) $(git -C "$REPO" log --format=%s | grep -c "$u")"
rm -f "$TMP/list-after"
# A unit main does not hold is never cleaned up: its panes are a live Builder's.
n=$((n + 1)); u=l$n; mk $u; : > "$TMP/orca-calls"; : > "$TMP/closed"
RC=$(merge $u --cleanup)
check "--cleanup on a unit not merged: exit 1, no pane closed, the worktree kept" "1 0 yes 1" \
  "$RC $(grep -c '^terminal close' "$TMP/orca-calls" || true) $(gone $u && echo yes) $(grep -c "not merged" "$TMP/out")"
# Main's ruling: the refusal names the way out for a hand merge resolved differently, and that way is no forced remove.
check "the refusal names the hand-merge way out: confirm the merge, close the panes, an ordinary remove (no --force)" "1" \
  "$(grep -cF "A hand merge that resolved it differently: confirm the merge by hand, close the unit's panes, then orca-ide worktree remove --worktree path:$(W $u) (no --force)" "$TMP/out")"
rm -f "$TMP/list-answer"

# Issue 391: a pass writes <unit>-r<N>-class-sites.txt and .md, untracked, in .claude/briefs (a review record like the round
# report). The merge lets an untracked file in that folder through and cleanup skips it, so they never hold the worktree.
n=$((n + 1)); u=cs$n; mk $u; go $u
printf 'a.sh:1\n' > "$(W $u)/.claude/briefs/$u-r1-class-sites.txt"; printf '## Class sites\n- a.sh:1\n' > "$(W $u)/.claude/briefs/$u-r1-class-sites.md"
RC=$(merge $u)
check "class_sites_files_do_not_hold_cleanup: a unit whose passes wrote class-sites files merges and its worktree is removed by cleanup" "0 gone 0" \
  "$RC $(gone $u && echo kept || echo gone) $(grep -c 'cleanup HELD' "$TMP/out" || true)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

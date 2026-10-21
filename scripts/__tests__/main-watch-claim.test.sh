#!/usr/bin/env bash
# A project that runs its own watcher claims this checkout (issue 167): while
# the claim is live, main-watch.sh posts nothing it would post twice, and an
# item the claim's owner never saw is posted once the claim ends. The fixture
# is the one main-watch-helper-hold.test.sh uses.
set -euo pipefail
. "$(dirname "$0")/fixtures/main-watch-setup.sh"
# The watcher posts only what finished after its first tick.
tick 5000

# Issue 167: a project that runs its own watcher posts the same heads-up notes from the same store. A live claim
# from it for this checkout stands this watcher down, and says so once; anything short of one is no claim.
mkdir -p "$T/home/.claude/plugins/store" "$T/home/.claude/projects/p"
offer() { # <name> <shownAt s>: the store shows one offer, from a session that ran in this checkout
  jq -nc --arg id "sess-$1" --argjson at "$2" --arg l "LINE-$1" '{sessions: [{id: $id, view: {kind: "offer", shownAt: ($at * 1000), line: $l, explanation: "why"}}]}' \
    > "$T/home/.claude/plugins/store/cc-plugin-you-should-know_builtin-t.json"
  jq -nc --arg c "$REPO" '{cwd: $c}' > "$T/home/.claude/projects/p/sess-$1.jsonl"; }
claim() { printf 'pid=%s\nmain=%s\nat=%s\n' "$1" "$2" "$3" > "$S/heads-up-owner"; }
yields() { grep -c 'nothing is posted (finished, stopped, stalled, heads-up)' "$T/stderr" || true; }
sleep 30 & LIVE=$!
N=60000; offer a $N; claim "$LIVE" "$REPO" $N; tick $N; tick $((N + 60))
[ "$(posts LINE-a)" = 0 ] || fail "a heads-up note was posted while a live claim for this checkout names another watcher"
[ "$(yields)" = 1 ] || fail "the stand-down was not said exactly once ($(yields) times)"
rm -f "$S/heads-up-owner"; N=$((N + 120)); offer b $N; tick $N
[ "$(posts LINE-b)" = 1 ] || fail "with no claim (the project's watcher stood down) the note was not posted"
[ "$(posts LINE-a)" = 0 ] || fail "a note captured under the claim was posted when it ended"
sleep 0 & DEAD=$!; wait $DEAD
for c in "stale:$LIVE:$REPO:-301" "dead:$DEAD:$REPO:0" "nested:$LIVE:$REPO/nested:0" "other:$LIVE:$T/other:0"; do
  IFS=: read -r name pid main age <<<"$c"
  N=$((N + 60)); offer "$name" $N; claim "$pid" "$main" $((N + age)); tick $N
  [ "$(posts "LINE-$name")" = 1 ] || fail "a $name claim stood the watcher down"
done
rm -f "$S/heads-up-owner"
bash -c 'sleep 30' "$REPO/ops/main-watch.sh" & ARGV=$!
N=$((N + 60)); offer argv $N; tick $N
[ "$(posts LINE-argv)" = 1 ] || fail "a process that only names a watcher script in its arguments stood the watcher down"
[ "$(yields)" = 1 ] || fail "a claim that ended did not reset the stand-down line, or said it again: $(yields)"
# A claim stands down only for notes its owner must have seen: shown before its last cycle (at=) and still shown.
# "old" is newer than the owner's at= on the first tick and gone from the store by the second; it waits, and
# posts once the claim ends. "seen" is shown before at= and still shown: the owner posted it.
kill "$LIVE" 2>/dev/null || true; sleep 60 & LIVE=$!
N=$((N + 60)); offer old $N; claim "$LIVE" "$REPO" $((N - 1)); tick $N
offer seen $((N + 30)); N=$((N + 60)); claim "$LIVE" "$REPO" $N; tick $N
[ "$(posts LINE-old)$(posts LINE-seen)" = 00 ] || fail "a heads-up note was posted while a live claim for this checkout names another watcher"
rm -f "$S/heads-up-owner"; N=$((N + 60)); tick $N
[ "$(posts LINE-old)" = 1 ] || fail "a note the claim owner never saw (shown after its last cycle, then gone) was lost"
[ "$(posts LINE-seen)" = 0 ] || fail "a note the claim owner saw was posted when the claim ended"

# Issue 167, reopened: the project's watcher posts every item, so a live claim stands this watcher down for its
# finished, stopped and stalled items too, not only heads-up notes, and says so once. An item first seen under the
# claim that the owner has run no cycle past (its at= not after the sighting) is posted once the claim ends.
kill "$LIVE" 2>/dev/null || true; sleep 300 & LIVE=$!
B=100000; Y0=$(yields)
mkdir -p "$T/ws/pf-plan"; printf 'handle=term_pf\ntask=task_pf\nrole=plan-author\nunit=pf\nlaunched=%s\nworktree=pf-plan\n' $((B - 1400)) > "$S/seat-pf-plan-author.txt"
echo "task_pf running" >> "$F/tasks"
for u in wt-s1 wt-st; do bseat $u term_$u task_$u $((B - 1400)); done
for u in pf wt-s1 wt-st; do state term_$u working; done; tick $((B - 1300))
echo PLAN-DONE > "$F/verdict-term_pf"; state term_pf "done"; state term_wt-s1 "done"
claim "$LIVE" "$REPO" $B; for d in 0 60 120; do tick $((B + d)); done
ITEMS=('seat plan-author on pf finished' 'wt-s1 builder stopped without reporting' 'wt-st builder stalled; inspect')
for p in "${ITEMS[@]}"; do [ "$(posts "$p")" = 0 ] || fail "main-watch posted '$p' while a live claim for this checkout names another watcher"; done
[ "$(yields)" = $((Y0 + 1)) ] || fail "the stand-down for every item was not said exactly once ($(( $(yields) - Y0 )) times)"
rm -f "$S/heads-up-owner"; tick $((B + 180)); tick $((B + 240))
for p in "${ITEMS[@]}"; do [ "$(posts "$p")" = 1 ] || fail "'$p', which the claim owner never saw, was posted $(posts "$p") times once the claim ended, not once"; done
# The crash window: an item first seen under a claim whose owner then stops (at= ages past 300 s) is posted on the
# next tick. One first seen under a claim whose owner then ran another cycle (a later at=) was posted there: never here.
C=$((B + 1000))
rm -f "$S"/seat-*.txt; sed -i 's/ .*/ completed/' "$F/tasks"
for u in wt-x1 wt-x2; do bseat $u term_$u task_$u $((C - 200)); state term_$u working; done; tick $((C - 100))
state term_wt-x1 "done"; claim "$LIVE" "$REPO" $C; tick $C
[ "$(posts 'wt-x1 builder stopped')" = 0 ] || fail "a stopped seat was posted under a live claim"
tick $((C + 301))
[ "$(posts 'wt-x1 builder stopped')" = 1 ] || fail "an item first seen under a claim that then went stale was not posted"
D=$((C + 400)); state term_wt-x2 "done"; claim "$LIVE" "$REPO" $D; tick $D
claim "$LIVE" "$REPO" $((D + 60)); tick $((D + 60))
[ "$(posts 'wt-x2 builder stopped')" = 0 ] || fail "a stopped seat was posted under a live claim"
rm -f "$S/heads-up-owner"; tick $((D + 120))
[ "$(posts 'wt-x2 builder stopped')" = 0 ] || fail "an item the claim owner ran a cycle past was posted when the claim ended"
# The owner posting an item is not main handling it: once the claim ends, an item whose task is still open is
# reminded every 5 minutes from the owner's last cycle (at=), and settles only when main closes its task.
tick $((D + 400))
[ "$(posts 'wt-x2 builder stopped')" = 1 ] || fail "an open item the claim owner posted was never reminded once the claim ended"
sed -i 's/^task_wt-x2 .*/task_wt-x2 completed/' "$F/tasks"; tick $((D + 800))
[ "$(posts 'wt-x2 builder stopped')" = 1 ] || fail "an item main closed was re-posted"

# Issue 280: the heads-up ledger and the handled list grow for good, and both went on jq's command line: past the
# argument limit (ARG_MAX) every tick failed with "Argument list too long" and no new note was captured again.
python3 - "$S/main-watch" <<'PY'
import json, sys
d = sys.argv[1]
led = json.load(open(d + "/heads-up.json"))
led["pairs"].update({"old-%05d@%d" % (i, 1000 + i): "heads-up-old-%05d" % i for i in range(30000)})
json.dump(led, open(d + "/heads-up.json", "w"))
with open(d + "/heads-up-handled", "a") as f:
    f.writelines("done-%05d-%s@%d\n" % (i, "x" * 30, 1000 + i) for i in range(30000))
PY
[ "$(wc -c < "$S/main-watch/heads-up.json")" -gt 1048576 ] && [ "$(wc -c < "$S/main-watch/heads-up-handled")" -gt 1048576 ] \
  || fail "setup: the ledger and the handled list are not each over 1 MB"
N=$((D + 900)); offer big $N; tick $N
jq -e --arg p "sess-big@$((N * 1000))" '.pairs[$p] != null' "$S/main-watch/heads-up.json" >/dev/null \
  || fail "a new heads-up was not captured with a ledger and a handled list over 1 MB"
[ "$(posts LINE-big)" = 1 ] || fail "a new heads-up was not posted with a ledger and a handled list over 1 MB"

# Issue 291: with a profile set, an offer's session is found among the profile's transcripts, not HOME's.
mkdir -p "$T/profile/projects/-repo"; echo '{"cwd":"/repo"}' > "$T/profile/projects/-repo/s1.jsonl"
eval "$(sed -n '/^hu_cwd() {/,/^}/p' "$SOURCE/scripts/main-watch.sh")"
[ "$(CLAUDE_CONFIG_DIR=$T/profile hu_cwd s1)" = /repo ] || fail "issue 291: an offer's session was not found in CLAUDE_CONFIG_DIR's transcripts"
# The installed job runs with no pane's CLAUDE_CONFIG_DIR: it reads the profile main last started under (recorded by
# agent-startup-context.sh), or the offers and transcripts only that profile has are never seen.
mkdir -p "$T/profile/plugins/store" "$T/profile/projects/p"; N=$((N + 60))
jq -nc --argjson at $N '{sessions: [{id: "sess-prof", view: {kind: "offer", shownAt: ($at * 1000), line: "LINE-prof", explanation: "why"}}]}' \
  > "$T/profile/plugins/store/cc-plugin-you-should-know_builtin-t.json"
jq -nc --arg c "$REPO" '{cwd: $c}' > "$T/profile/projects/p/sess-prof.jsonl"
echo "$T/profile" > "$S/claude-config-dir"
tick $N
[ "$(posts LINE-prof)" = 1 ] || fail "issue 291: the job, with no CLAUDE_CONFIG_DIR, did not post an offer only the recorded profile has"
# The job runs for days: main starting under another profile while it runs must move it there, or it reads the
# first profile's store and transcripts for good and never sees an offer only the new one has.
mkdir -p "$T/prof-b/plugins/store" "$T/prof-b/projects/p"; N=$((N + 60))
jq -nc --argjson at $N '{sessions: [{id: "sess-b", view: {kind: "offer", shownAt: ($at * 1000), line: "LINE-switch", explanation: "why"}}]}' \
  > "$T/prof-b/plugins/store/cc-plugin-you-should-know_builtin-t.json"
jq -nc --arg c "$REPO" '{cwd: $c}' > "$T/prof-b/projects/p/sess-b.jsonl"
# mw's own environment, run so that $! is the job itself and the kill below ends it.
(cd "$REPO" && unset CLAUDE_CONFIG_DIR && PATH=$T/bin:$PATH HOME=$T/home COMMANDECK_SCRATCH=$S COMMANDECK_WORKSPACES=$T/ws COMMANDECK_NOW=$N \
  COMMANDECK_MAIN_WATCH_TICK_S=1 exec bash scripts/main-watch.sh 2>>"$T/stderr") & LOOP=$!
sleep 2; [ "$(posts LINE-switch)" = 0 ] || fail "an offer in a profile main has not started under was posted"
echo "$T/prof-b" > "$S/claude-config-dir"
for _ in $(seq 100); do [ "$(posts LINE-switch)" = 0 ] || break; sleep 0.1; done
kill "$LOOP"; wait "$LOOP" 2>/dev/null || true  # 143, the TERM it was sent
[ "$(posts LINE-switch)" = 1 ] || fail "the running job did not follow main to another profile"

echo "PASS main-watch-claim.test.sh"

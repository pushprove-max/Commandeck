#!/usr/bin/env bash
# timeout: 240
# Issue 317: a running detached merge owns main, and says so. While merge-unit-local.sh holds main it writes its
# state (unit, reviewed sha, pid, started, stage) beside its lock, and removes it on every exit; the same unit at the
# same sha, running or waiting on the lock, is never queued twice; a lock whose pid is dead blocks nothing; and the
# "staged work changed during the check" refusal stays hard, with main left at its starting commit.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
. "$(dirname "$0")/fixtures/merge-unit-local-setup.sh"
STATE=$REPO/.git/merge-unit-local.state QUEUE=$REPO/.git/merge-unit-local.queue
cfg() { mkdir -p "$REPO/.claude"; jq -n --arg c "$1" '{testCommand: $c}' > "$REPO/.claude/commandeck.json"; } # <check command>
tip() { git -C "$COMMANDECK_WORKSPACES/$1" rev-parse HEAD; }
field() { sed -n "s/^$2=//p" "$1" 2>/dev/null; } # <file> <key>
has() { [ -e "$1" ] && echo yes || echo no; }
waitfor() { local i; for i in $(seq 150); do [ -e "$1" ] && return 0; sleep 0.2; done; return 1; } # <file>
waitcheck() { local i; for i in $(seq 150); do [ "$(field "$STATE" stage)" = check ] && return 0; sleep 0.2; done; return 1; } # the running merge is in its check

# The state a check sees is the merge's own: the unit, the tip it was asked to merge, its pid, when, the stage, the log.
cfg "cp $STATE $TMP/seen"
mk a; go a; TA=$(tip a)
check "a merge ends 0" 0 "$(merge a)"
check "the state a running check sees names the unit, the reviewed sha and the stage" "a|$TA|check" \
  "$(field "$TMP/seen" unit)|$(field "$TMP/seen" sha)|$(field "$TMP/seen" stage)"
check "it also holds a live pid, a start time, main's path and the log to watch" "yes yes $REPO $COMMANDECK_SCRATCH/merge-a.log" \
  "$([[ $(field "$TMP/seen" pid) =~ ^[0-9]+$ ]] && echo yes || echo no) $([[ $(field "$TMP/seen" started) =~ ^[0-9]+$ ]] && echo yes || echo no) $(field "$TMP/seen" main) $(field "$TMP/seen" log)"
check "a merge that ended leaves no state file" no "$(has "$STATE")"
cfg false; mk b; go b
check "a red check refuses the merge" 1 "$(merge b)"
check "and a refused merge leaves no state file either" no "$(has "$STATE")"

# A lock whose pid is dead is stale: it does not block, not even a request for the very unit and sha it names.
cfg true; mk c; go c; sleep 0 & DEAD=$!; wait "$DEAD"
printf 'unit=c\nsha=%s\npid=%s\nstarted=1\nstage=check\nmain=%s\nlog=x\n' "$(tip c)" "$DEAD" "$REPO" > "$STATE"
check "a stale lock does not block a merge of the unit it names" "0 1" "$(merge c) $(grep -c '^DONE unit=c merged=local' "$TMP/out")"

# The staged work is checked against the tree that was reviewed: main's index changed during the check is a hard
# refusal, and main is back at its starting commit with nothing of the unit left in it.
echo stray > "$REPO/stray.txt"; H0=$(git -C "$REPO" rev-parse HEAD)
cfg "git -C $REPO add stray.txt"; mk d; go d
check "an index that gained a file during the check refuses the merge, and main stays at its commit" "1 $H0" "$(merge d) $(git -C "$REPO" rev-parse HEAD)"
check "and it says the commit was not the reviewed tree" 1 "$(grep -c 'FAILED step 4 merge: .*not the tree that was reviewed' "$TMP/out")"
check "and the unit's file is not left in main" no "$(has "$REPO/d.txt")"
cfg "git -C $REPO reset -q"; mk e; go e
check "an index emptied during the check (a stash) refuses the merge, and main stays at its commit" "1 $H0" "$(merge e) $(git -C "$REPO" rev-parse HEAD)"
check "and the unit's file is not left in main" no "$(has "$REPO/e.txt")"
git -C "$REPO" reset -q; rm -f "$REPO/stray.txt"

# The same unit at the same sha is never queued twice: a request while it runs, and one while it waits, are no-ops.
cfg "while [ ! -e $TMP/go ]; do sleep 0.2; done"
mk f; mk g; go f; go g; TF=$(tip f); TG=$(tip g)
(cd "$REPO" && bash "$MERGE" f > "$TMP/out-f" 2>&1; echo $? > "$TMP/rc-f") & PF=$!
waitcheck
check "the running merge's state names f at its sha, and a live pid" "f|$TF|yes" \
  "$(field "$STATE" unit)|$(field "$STATE" sha)|$(kill -0 "$(field "$STATE" pid)" 2>/dev/null && echo yes || echo no)"
check "a hand request for the unit that is running is a no-op (exit 4) that says so" "4 1" "$(merge f) $(grep -c "^f at ${TF:0:8} is already merging (pid $(field "$STATE" pid), stage check; log " "$TMP/out")"
check "so is main-watch's request, by the sha its gate passed" "4 1" "$(merge f --auto "${TF:0:12}") $(grep -c 'already merging' "$TMP/out")"
(cd "$REPO" && bash "$MERGE" g > "$TMP/out-g" 2>&1; echo $? > "$TMP/rc-g") & PG=$!
waitfor "$QUEUE/g@$TG"
check "a request for another unit waits on the lock, entered in the queue" "yes" "$(has "$QUEUE/g@$TG")"
check "a second request for that waiting unit is a no-op (exit 4) that says so" "4 1" "$(merge g) $(grep -c "^g at ${TG:0:8} is already queued" "$TMP/out")"
touch "$TMP/go"; wait "$PF" "$PG"
check "both merged" "0 0" "$(cat "$TMP/rc-f") $(cat "$TMP/rc-g")"
check "each unit was merged once, not once per request" "1 1" \
  "$(git -C "$REPO" log --format=%s | grep -c '^feat(f)') $(git -C "$REPO" log --format=%s | grep -c '^feat(g)')"
check "and the lock and the queue are empty" "no no" "$(has "$STATE") $(ls "$QUEUE" 2>/dev/null | grep -c . | sed 's/^0$/no/')"

# Pass 1 (r1): two requests that find the same stale entry. Without one reader at a time, the second, between its read
# of the dead pid and its removal, deleted the entry the first had just made, and both went on to the lock: one unit
# merged twice. The second request starts right after the first's read; it is a request of its own, without the first's fds.
SHA=$(printf '%040d' 7); sleep 0 & DEAD=$!; wait "$DEAD"
mkdir -p "$QUEUE"; echo "$DEAD" > "$QUEUE/s@$SHA"
RC1=$(COMMANDECK_MAIN=$REPO . "$REAL/scripts/paths.sh"
  cat() { command cat "$@"; [ "$1" != "$QUEUE/s@$SHA" ] || [ -e "$TMP/raced" ] || { touch "$TMP/raced"
    (exec 9>&-; pp_merge_active s "$SHA" --register; echo $? > "$TMP/rc2") >/dev/null 2>&1 & sleep 1; }; }
  pp_merge_active s "$SHA" --register >/dev/null; echo $?; wait)
check "of two requests that found one stale entry, one is entered and the other is told it is queued" "1 0" "$RC1 $(cat "$TMP/rc2")"
rm -rf "$QUEUE"

# Pass 1 (r1): a duplicate sent through merge-queue.sh is still a no-op, and it leaves the running merge's log as it is:
# the queue opened that log for writing before the merge it called found the duplicate, and emptied it.
rm -f "$TMP/go"; mk h; go h; echo h > "$TMP/unit"; TH=$(tip h); LOG=$COMMANDECK_SCRATCH/merge-h.log
(cd "$REPO" && bash "$MERGE" h > "$LOG" 2>&1; echo $? > "$TMP/rc-h") & HPID=$!
waitcheck
check "a duplicate through the queue stops it, not merged (exit 4)" 1 "$(cd "$REPO" && bash "$REAL/scripts/merge-queue.sh" "h@$TH" >/dev/null 2>&1; echo $?)"
check "and the running merge's log still holds its steps" 1 "$(grep -c '^STEP 1 preconditions' "$LOG")"
touch "$TMP/go"; wait "$HPID"
check "and that merge ended merged" 0 "$(cat "$TMP/rc-h")"

# Pass 2 (r2): the queue's lock timed out and the request read and wrote its entry anyway, without it: the lock's owner
# could register between that read and that write, and both went on to the lock. A timeout now refuses, unqueued.
SHA=$(printf '%040d' 8); sleep 0 & DEAD=$!; wait "$DEAD"; sleep 60 & LIVE=$!
mkdir -p "$QUEUE"; echo "$DEAD" > "$QUEUE/s@$SHA"
RC=$(COMMANDECK_MAIN=$REPO . "$REAL/scripts/paths.sh"
  flock() { return 1; }
  cat() { command cat "$@"; [ "$1" != "$QUEUE/s@$SHA" ] || echo "$LIVE" > "$1"; } # the owner registers after the read
  pp_merge_active s "$SHA" --register 2>/dev/null; echo $?)
check "a request whose queue lock timed out is refused (2) and never writes the entry" "2 no" \
  "$RC $([ "$(cat "$QUEUE/s@$SHA")" = $$ ] && echo yes || echo no)"
kill "$LIVE"; rm -rf "$QUEUE"
mkdir -p "$TMP/busy"; printf '#!/bin/sh\n[ "$1" != -w ] || exit 1\nexec %s "$@"\n' "$(command -v flock)" > "$TMP/busy/flock"; chmod +x "$TMP/busy/flock"
mk i; go i
check "so the merge refuses (exit 1), saying the queue's lock was busy, and does not merge" "1 1 0" \
  "$(PATH=$TMP/busy:$PATH merge i) $(grep -c "was not queued; nothing ran" "$TMP/out") $(git -C "$REPO" log --format=%s | grep -c '^feat(i)')"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

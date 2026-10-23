#!/usr/bin/env bash
# covers: scripts/merge-queue.sh
# Issue 307 for a train, its later steps (split from merge-queue-train.test.sh to fit the runner's 120 s cap): a unit
# whose post-merge step is refused does not stop the train, and a train started in main's foreground detaches.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
. "$(dirname "$0")/fixtures/merge-queue-setup.sh"

# A unit that merges with a later step refused (exit 5) does not stop the train: the unit after it still merges.
mk xa; mk xb; printf '# xa\n\n## Post-merge\n\n- rm -rf ~/x\n' > "$COMMANDECK_WORKSPACES/xa/.claude/briefs/xa.md"
closed xa; closed xb; : > "$TMP/check-calls"
OUT=$(cd "$REPO" && bash "$QUEUE" --train "xa@$(sha xa)" "xb@$(sha xb)" 2>&1); RC=$?
check "a merged unit with a refused post-merge step: the train goes on, both merge, the train's check and xb's own, and it ends 1" "1 1 1 2" \
  "$RC $(git -C "$REPO" log --format=%s | grep -c '^feat(xa)') $(git -C "$REPO" log --format=%s | grep -c '^feat(xb)') $(runs)"
check "it says the train went on past the refused step" 1 "$(grep -c '^merge-queue: xa MERGED, but a step after the merge commit failed or was refused (exit 5); .*the train goes on' <<<"$OUT")"
# r12: in main's foreground the queue detaches itself, and the detached queue is still a train.
mk fa; mk fb; closed fa; closed fb
OUT=$(cd "$REPO" && env -u COMMANDECK_FOREGROUND CLAUDECODE=1 bash "$QUEUE" --train "fa@$(sha fa)" "fb@$(sha fb)" </dev/null 2>&1)
PID=$(sed -n 's/.*running detached as pid \([0-9]*\);.*/\1/p' <<<"$OUT")
[ -z "$PID" ] || tail --pid="$PID" -f /dev/null
check "a train detached from main's foreground runs as a train and merges both" "1 1 1" \
  "$(grep -c '^merge-train: the combined tip of 2 unit(s) is green' "$COMMANDECK_SCRATCH/merge-queue.log" 2>/dev/null) \
$(git -C "$REPO" log --format=%s | grep -c '^feat(fa)') $(git -C "$REPO" log --format=%s | grep -c '^feat(fb)')"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

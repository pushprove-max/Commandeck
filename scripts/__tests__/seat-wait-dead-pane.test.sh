#!/usr/bin/env bash
# seat.sh wait must fail the moment its pane disappears. Every pane read in the
# wait loop swallows its own error, so before this check a driver waiting on a
# dead seat burned the full 90-minute timeout: b2b's revise seat died at 08:28
# on 2026-09-13 and its driver was still blocked 47 minutes later.
set -euo pipefail

SOURCE=$(git rev-parse --show-toplevel)
SCRATCH=$(mktemp -d /tmp/seat-wait-dead-pane-test.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

UNIT=fake-unit
ROLE=certifier
mkdir -p "$SCRATCH/ws/$UNIT" "$SCRATCH/bin"
cat > "$SCRATCH/seat-$UNIT-$ROLE.txt" <<EOF
handle=term_dead
task=task_fake
role=$ROLE
unit=$UNIT
spec=$SCRATCH/spec.md
EOF
echo "marker TEST-DONE goes here" > "$SCRATCH/spec.md"

run_wait() {
  PATH="$SCRATCH/bin:$PATH" COMMANDECK_SCRATCH="$SCRATCH" \
  COMMANDECK_WORKSPACES="$SCRATCH/ws" COMMANDECK_LOOP_POLL_SECONDS=1 \
  bash "$SOURCE/scripts/seat.sh" wait "$ROLE" "$UNIT" \
    --marker TEST-DONE --timeout-s "${1:?}" 2>&1
}

# 1. The pane is absent from the terminal list: fail now, not at the timeout.
cat > "$SCRATCH/bin/orca-ide" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = terminal ] && [ "${2:-}" = list ] && { echo "term_alive  some other pane"; exit 0; }
exit 0
EOF
chmod +x "$SCRATCH/bin/orca-ide"
START=$(date +%s)
OUT=$(run_wait 300) && fail "wait returned success on a dead pane"
ELAPSED=$(( $(date +%s) - START ))
grep -q 'pane term_dead is gone' <<<"$OUT" \
  || fail "no dead-pane message; got: $OUT"
[ "$ELAPSED" -lt 30 ] || fail "took ${ELAPSED}s to notice a dead pane"

# 2. The list command itself failing must NOT end a healthy wait: the pane may
#    be fine and the CLI merely unreachable, so the loop runs to its timeout.
cat > "$SCRATCH/bin/orca-ide" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$SCRATCH/bin/orca-ide"
OUT=$(run_wait 3) && fail "wait returned success with no marker"
grep -q 'is gone' <<<"$OUT" \
  && fail "a failing list call was read as a dead pane"
grep -q 'no TEST-DONE on term_dead within 3s' <<<"$OUT" \
  || fail "expected the normal timeout message; got: $OUT"

# 3. A LIVE pane in a list too big for the 64 KB pipe buffer. The old
#    `printf | grep -q` read this as dead: grep exited on the match, printf took
#    SIGPIPE writing the rest, and pipefail called the pipeline failed. It needs
#    six units running at once to show up in real life, which is exactly when a
#    driver dying costs the most, so the padding here is the whole point.
cat > "$SCRATCH/bin/orca-ide" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = terminal ] && [ "${2:-}" = list ]; then
  echo "term_dead  the pane we are waiting on"
  head -c 200000 /dev/zero | tr '\0' 'x'
  echo
  exit 0
fi
exit 0
EOF
chmod +x "$SCRATCH/bin/orca-ide"
OUT=$(run_wait 3) && fail "wait returned success with no marker"
grep -q 'is gone' <<<"$OUT" \
  && fail "a live pane in a large terminal list was read as dead"
grep -q 'no TEST-DONE on term_dead within 3s' <<<"$OUT" \
  || fail "expected the normal timeout message on a live pane; got: $OUT"

echo "PASS seat-wait-dead-pane: 7 assertions"

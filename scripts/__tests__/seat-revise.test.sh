#!/usr/bin/env bash
# seat-revise.test.sh -- issue 485. A finished plan seat's revision was a hand send into an idle pane, which Orca never
# counts as a task, so main-watch.sh had nothing to wake main with. What this pins: seat.sh revise starts a new task on
# the same pane and leaves the record one task= line (the new task) plus revised=; it refuses a Builder and a pane that is
# not idle with the record untouched; and seat.sh status prints Orca's live agent state, not the launch line's stale state=.
set -uo pipefail
. "$(dirname "$0")/fixtures/seat-setup.sh"

# The stand-in's task-create always answers task_1: a second id, and every worker-start, is recorded here.
mv "$BIN/orca-ide" "$BIN/orca-ide.base"
cat > "$BIN/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$*" in
  "orchestration task-create"*) echo "\$*" >> "$T/creates"; echo '{"ok":true,"result":{"task":{"id":"task_2"}}}' ;;
  "orchestration worker-start"*) echo "\$*" >> "$T/starts"; exec "$BIN/orca-ide.base" "\$@" ;;
  *) exec "$BIN/orca-ide.base" "\$@" ;;
esac
EOF
chmod +x "$BIN/orca-ide"

# The launch makes the pane; the plan author's record is then written beside the Builder's, on the same pane.
COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 run launch builder seat-builder "$T/spec.md" >"$T/out" 2>&1
REC=$(ls "$HOME/.commandeck/scratch/"*/seat-seat-builder-builder.txt); PREC=${REC%/*}/seat-seat-unit-plan-author.txt
printf 'handle=h1\ntask=task_1\nrole=plan-author\nunit=seat-unit\nworktree=seat-unit\nlaunched=1000\nphase=dispatched\n' > "$PREC"
: > "$T/creates"; : > "$T/starts"

run revise plan-author seat-unit "Change section 2 of the plan." >"$T/out" 2>&1
check "a revision gets a new task (issue 485)" "0:1:task_2:task_2:1:1" \
  "$?:$(grep -c '^task=' "$PREC"):$(sed -n 's/^task=//p' "$PREC"):$(sed -n 's/^revised=//p' "$PREC"):$(grep -c 'Change section 2 of the plan\.' "$T/creates"):$(grep -c 'worker-start.*task_2' "$T/starts")"

# Busy: nothing is created, started or rewritten. A Builder is refused whatever its pane reads.
cp "$PREC" "$T/before"; : > "$T/creates"; : > "$T/starts"; touch "$T/ps-working"
run revise plan-author seat-unit "A second revision." >"$T/out" 2>&1; BUSY=$?
rm -f "$T/ps-working"
run revise builder seat-builder "A revision." >"$T/out" 2>&1; BLD=$?
check "revise refuses a busy pane (issue 485)" "2:2:0:0:same" \
  "$BUSY:$BLD:$(grep -c . "$T/creates"):$(grep -c . "$T/starts"):$(cmp -s "$PREC" "$T/before" && echo same || echo changed)"

# The launch line carries the screen at launch (state=Working ...); status asks Orca now.
touch "$T/ps-working"
S1=$(run status builder seat-builder 2>&1); rm -f "$T/ps-working"; S2=$(run status builder seat-builder 2>&1)
check "status reads the live state (issue 485)" "1:1:0:1" \
  "$(grep -c ' agent=working ' <<<"$S1"):$(grep -c ' agent=none ' <<<"$S2"):$(grep -c ' state=' <<<"$S1"):$(grep -c 'last: seat=.* record=' <<<"$S1")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

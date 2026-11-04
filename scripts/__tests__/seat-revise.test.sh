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
  "orchestration task-create"*) echo "\$*" >> "$T/creates"; while [ \$# -gt 0 ]; do [ "\$1" != --spec-file ] || { cat "\$2"; echo; } >> "$T/creates"; shift; done
    echo '{"ok":true,"result":{"task":{"id":"task_2"}}}' ;;
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

# Issue 612: a revised plan author's turn is finished by its own plan commit, never by the plan it inherited: revise
# resets planref= to the plan at revise time. committed -- pp_plan_committed on the author's record since its launch.
UWT=$HOME/orca/workspaces/proj/seat-unit; mkdir -p "$UWT/.claude/plans"
plan() { echo "$1" > "$UWT/.claude/plans/seat-unit.md"; git -C "$UWT" add .claude/plans/seat-unit.md && git -C "$UWT" -c user.name=t -c user.email=t@t commit -qm "$1"; }
committed() { (cd "$PROJ" && env -u COMMANDECK_MAIN -u COMMANDECK_WORKSPACES -u COMMANDECK_SCRATCH PATH="$BIN:$PATH" \
  bash -c '. "$1/scripts/paths.sh" && pp_plan_committed "$2" 1000' _ "$REAL" "$PREC") && echo finished || echo working; }
plan 'plan A'; sed -i "/^planref=/d" "$PREC"; echo "planref=$(git -C "$UWT" rev-parse HEAD:.claude/plans/seat-unit.md)" >> "$PREC"; plan 'plan B'
run revise plan-author seat-unit "Change section 3." >"$T/out" 2>&1
check "a revise seat does not read as finished from the plan it inherited" "0:working" "$?:$(committed)"
plan 'plan C'
check "a revise seat that commits a new plan reads as finished" finished "$(committed)"

# Pass 8: the revised worker can commit its plan before dispatch returns. planref= is the plan before the revision is
# sent, so that commit is its finish. commit-on-start wraps the stand-in: worker-start commits plan E, then answers.
mv "$BIN/orca-ide" "$BIN/orca-ide.revise"
printf '#!/usr/bin/env bash\ncase "$*" in "orchestration worker-start"*) [ ! -e %q ] || { echo "plan E" > %q; git -C %q add .claude/plans/seat-unit.md && git -C %q -c user.name=t -c user.email=t@t commit -qm "plan E"; } ;; esac\nexec %q "$@"\n' \
  "$T/commit-on-start" "$UWT/.claude/plans/seat-unit.md" "$UWT" "$UWT" "$BIN/orca-ide.revise" > "$BIN/orca-ide"; chmod +x "$BIN/orca-ide"
plan 'plan D'; D=$(git -C "$UWT" rev-parse HEAD:.claude/plans/seat-unit.md); touch "$T/commit-on-start"
run revise plan-author seat-unit "Change section 4." >"$T/out" 2>&1; RC=$?; rm -f "$T/commit-on-start"
check "a revise seat that commits its plan before dispatch returns keeps the plan it inherited as planref and reads as finished" "0:$D:finished" \
  "$RC:$(sed -n 's/^planref=//p' "$PREC"):$(committed)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

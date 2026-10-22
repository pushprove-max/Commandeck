#!/usr/bin/env bash
# builder-launch-resume-launch-line.test.sh -- issue 234: a unit opened on an order that never named it is refused; the
# batch's Launch line must name this unit as new. The fixture is builder-launch-resume.test.sh's.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-launch-resume-setup.sh"
cp "$REAL/scripts/plan-worktree-close.sh" "$T/plug/scripts/"

# Issue 234: a unit opened on an order that never named it. The batch quotes the order, and its Launch line must
# name this unit as new; adding work to a unit is builder-add-work.sh's.
# order <unit> <launch line> -- a launch of <unit> on a batch with that Launch line ('' for none); RC and $T/out as build's.
order() { : > "$T/seats"; : > "$T/orca.log"; batchfor "$1" "$2"; (cd "$P" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH PATH="$T/bin:$PATH" COMMANDECK_WORKSPACES=$WS \
  bash "$T/plug/scripts/builder-launch.sh" "$1" "$T/batch.md" </dev/null >"$T/out" 2>&1); RC=$?; }
order u11 ''
check "a batch with no Launch line is refused before anything opens" "2:1:0:0" "$RC:$(grep -c 'REFUSED: .* has no Launch line' "$T/out"):$(grep -c . "$T/seats"):$(grep -c . "$T/orca.log")"
check "the refusal says the Order line must quote the owner's yes naming the unit or its issues (issue 287)" 1 \
  "$(grep -c "the Order line must quote the owner's yes naming this unit or its issues" "$T/out")"
order u12 'Launch: add to u2'
check "a batch that adds to a unit is refused, pointing to builder-add-work.sh" "2:1:0" "$RC:$(grep -c 'REFUSED: .*adds work to u2: run builder-add-work.sh u2' "$T/out"):$(grep -c . "$T/seats")"
order u13 'Launch: new unit u99'
check "a batch whose order names another unit is refused" "2:1:0" "$RC:$(grep -c "REFUSED: .*names u99, not u13" "$T/out"):$(grep -c . "$T/seats")"
order u14 'Launch: new unit u14'
check "a batch whose Launch line names this unit as new opens its Builder" "0:1" "$RC:$(grep -cx 'launch builder u14' "$T/seats")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

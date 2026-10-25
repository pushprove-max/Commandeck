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

# Issue 341 (F1): a batch states its data design (what state it adds, who owns it, when it resets, what a retry runs) before
# any Builder opens. A missing section, an empty one, and the template's placeholder alone are refused.
dd() { : > "$T/seats"; : > "$T/orca.log"; batchfor "$1"; sed -i.bak '/^## Data design$/,/^## Plan$/{/^## Plan$/!d;}' "$T/batch.md"; rm -f "$T/batch.md.bak"
  [ -z "${2-}" ] || printf '\n## Data design\n\n%s\n' "$2" >> "$T/batch.md"
  (cd "$P" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH PATH="$T/bin:$PATH" COMMANDECK_WORKSPACES=$WS \
    bash "$T/plug/scripts/builder-launch.sh" "$1" "$T/batch.md" </dev/null >"$T/out" 2>&1); RC=$?; }
# A batch with no Data design heading at all was written before 0.46.0 (the template has carried the heading since): it
# was valid when written, maybe judged and approved, so it still opens, and the brief moves the answer to the Builder,
# before its first edit. The section stays required wherever the heading is: empty or placeholder-only is refused.
dd u15
check "a batch written before the Data design section opens its Builder and says so" "0:1:1" "$RC:$(grep -cx 'launch builder u15' "$T/seats"):$(grep -c 'NOTE: .* has no Data design section' "$T/out")"
check "its brief has the Builder write the Data design in the evidence file before the first edit" "1" \
  "$(grep -c '^This batch was written before the Data design section: before the first edit write' "$WS/u15/.claude/briefs/u15.md")"
dd u16 ''
dd u16 ' '
check "a batch whose Data design section is empty is refused" "2:1" "$RC:$(grep -c 'REFUSED: .* has no Data design section' "$T/out")"
dd u17 $'Required: builder-launch.sh refuses a batch without it. Say what state the batch adds.\n\n- <piece of state>: lives in <where>; written by <who>; reset when <when>'
check "a batch with only the template's guidance and placeholder is refused" "2:1" "$RC:$(grep -c 'REFUSED: .* has no Data design section' "$T/out")"
dd u18 '- the pass hand-off file: lives in the unit worktree; written by the pass script; rewritten each round; a retry rewrites it whole'
check "a batch that fills the section opens its Builder" "0:1" "$RC:$(grep -cx 'launch builder u18' "$T/seats")"
dd u19 'none: no state is added or changed'
check "a batch that says none, with the reason, opens its Builder" "0:1" "$RC:$(grep -cx 'launch builder u19' "$T/seats")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

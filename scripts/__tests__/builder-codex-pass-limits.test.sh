#!/usr/bin/env bash
# Issue 468, the stated-limits check: a Builder owns its worktree's brief, so a limit it adds after the plan judge's GO
# (to the brief, or to the plan's Stated limits or Accepted failure modes) takes a finding off the reviewer's list with no
# one having approved it. A pass refuses an added limit unless the line carries a `ruling:<id>` that the ruling log holds as
# a standing row and main's rulings for the unit carry. Added lines only: a line already in the baseline, or removed, passes.
# The ids use the r-1999... shape of orca-wait.test.sh: the leak test bans r-20....
# The fixture is the one the cap-gate test uses.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
. "$(dirname "$0")/fixtures/merge-unit-local-setup.sh"

WS=$COMMANDECK_WORKSPACES
LOG=$TMP/rulings.jsonl
OKID=r-19990101-000001-1-abcdef VOIDID=r-19990101-000002-1-abcdef SUSID=r-19990101-000003-1-abcdef FOREIGNID=r-19990101-000004-1-abcdef
printf '%s\n' '{"id":"'$OKID'","answer":"yes"}' '{"id":"'$VOIDID'","answer":"x","void":true}' \
  '{"id":"'$SUSID'","answer":"x","pick":"suspect"}' '{"id":"'$FOREIGNID'","answer":"yes"}' > "$LOG"
tpass() { # <pass args: <unit> 1 adversarial, or --ack-rulings <unit>>: one run in the unit's worktree; stderr in $TMP/perr; prints its exit code
  local u=${*: -1}; [ "$1" != --ack-rulings ] || u=$2; [ "$1" = --ack-rulings ] || u=$1
  (cd "$WS/$u" && HOME=$PH TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO COMMANDECK_ROUTING=$TMP/routing.json \
    COMMANDECK_RULING_LOG=$LOG STUB_THREAD=thr-$u-1 bash "$PASS_SH" "$@" >/dev/null 2>"$TMP/perr"); echo $?
}
lim() { # <unit> <main's limits...>: a unit whose main brief states these limits; the worktree brief starts as a copy
  local u=$1; shift
  mk "$u"; mkdir -p "$REPO/.claude/briefs"
  printf '%s\n' '# brief' '## Stated limits' "$@" > "$REPO/.claude/briefs/$u-builder-brief.md"
  cp "$REPO/.claude/briefs/$u-builder-brief.md" "$WS/$u/.claude/briefs/$u.md"
}
ruled() { printf '%s\n' "1. ruled" "   - Source: $2" > "$REPO/.claude/briefs/$1-main-rulings.md"; } # <unit> <ruling id>
REFUSED='adds a stated limit after the plan judge'

lim ln '- base limit: 3 hosts.'
echo '- a new limit: 9 hosts.' >> "$WS/ln/.claude/briefs/ln.md"
NE=$(tpass ln 1 adversarial)
check "a limit with no id is refused (issue 468)" "2 1" "$NE $(grep -c "$REFUSED" "$TMP/perr")"

lim lc '- base limit: 3 hosts.'
echo "- a new limit: 9 hosts. ruling:$OKID" >> "$WS/lc/.claude/briefs/lc.md"
ruled lc "$OKID"
tpass --ack-rulings lc >/dev/null
CE=$(tpass lc 1 adversarial)
check "a carried id passes (issue 468)" "0 0" "$CE $(grep -c "$REFUSED" "$TMP/perr")"

lim lv '- base limit: 3 hosts.'
echo "- a new limit: 9 hosts. ruling:$VOIDID" >> "$WS/lv/.claude/briefs/lv.md"
ruled lv "$VOIDID"; tpass --ack-rulings lv >/dev/null
VE=$(tpass lv 1 adversarial); VN=$(grep -c "$REFUSED" "$TMP/perr")
lim ls '- base limit: 3 hosts.'
echo "- a new limit: 9 hosts. ruling:$SUSID" >> "$WS/ls/.claude/briefs/ls.md"
ruled ls "$SUSID"; tpass --ack-rulings ls >/dev/null
SE=$(tpass ls 1 adversarial); SN=$(grep -c "$REFUSED" "$TMP/perr")
lim lf '- base limit: 3 hosts.'
echo "- a new limit: 9 hosts. ruling:$FOREIGNID" >> "$WS/lf/.claude/briefs/lf.md"
ruled lf "$OKID"; tpass --ack-rulings lf >/dev/null
FE=$(tpass lf 1 adversarial); FN=$(grep -c "$REFUSED" "$TMP/perr")
check "a void or foreign id is refused (issue 468)" "2 1 2 1 2 1" "$VE $VN $SE $SN $FE $FN"

lim le '- base limit: 3 hosts.' '- second limit: 4 hosts.'
printf '%s\n' '# brief' '## Stated limits' '- base limit: 3 hosts.' > "$WS/le/.claude/briefs/le.md"
EE=$(tpass le 1 adversarial)
check "earlier limits are unaffected (issue 468): an unchanged or removed limit passes with no id" "0 0" "$EE $(grep -c "$REFUSED" "$TMP/perr")"

# The plan's baseline is kept in the lock: a copy left there holds the lock's folder, and every later pass is refused.
lim lp '- base limit: 3 hosts.' '- plan: .claude/plans/lp.md'
mkdir -p "$WS/lp/.claude/plans"; printf '%s\n' '# plan' '## Stated limits' '- base limit: 3 hosts.' > "$WS/lp/.claude/plans/lp.md"
tpass lp 1 adversarial >/dev/null
check "a pass leaves its lock free (issue 468)" no "$([ -e "$(git -C "$WS/lp" rev-parse --absolute-git-dir)/builder-pass.lock" ] && echo held || echo no)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

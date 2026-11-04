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
# Pass 1 of commandeck-open-2026-11-03: a `###` heading under `## Stated limits` ended the section, so a limit added
# beneath it was never compared. A section runs to the next heading of its own level or higher.
lim lh '- base limit: 3 hosts.'
printf '%s\n' '### Hosts' '- a new limit: 9 hosts.' >> "$WS/lh/.claude/briefs/lh.md"
HE="$(tpass lh 1 adversarial) $(grep -c "$REFUSED" "$TMP/perr")"
# The `###` line itself is an added line too, so the subheading case refuses twice. Every ordering found since (fix
# rounds 3 to 5), in order: a bold limit and a bare new subheading inside the section
# (r3), then the limits heading as `<h2>` (r4) and with inline `**` (r5), then setext, bold, indented, quoted and prose
# shapes. The gate reads only the literal `## ` heading line (a fixed list), and any other line whose letters name a
# limits heading refuses, naming its line, so no shape lets a limit through unread. A table row naming it is no heading.
BAD='names a limits heading outside its one heading line'; i=0
for a in '**No writes to prod.**' '### Hosts'; do
  i=$((i + 1)); lim lb$i '- base limit: 3 hosts.'; echo "$a" >> "$WS/lb$i/.claude/briefs/lb$i.md"
  HE="$HE $(tpass lb$i 1 adversarial) $(grep -c "$REFUSED" "$TMP/perr")"; done
shapes=('<h2>Stated limits</h2>' '## Stated **limits**' $'Stated limits\n---' '**Stated limits**' '  ## Stated limits' \
  '> ## Stated limits' 'Stated limits bind this unit.' '## Our stated limits (v2)')
for a in "${shapes[@]}"; do
  i=$((i + 1)); lim lb$i '- base limit: 3 hosts.'
  printf '%s\n' '# brief' "$a" '- base limit: 3 hosts.' '- Skip production verification.' > "$WS/lb$i/.claude/briefs/lb$i.md"
  HE="$HE $(tpass lb$i 1 adversarial) $(grep -c ".claude/briefs/lb$i.md line 2: $BAD" "$TMP/perr")"; done
# The plan's accepted-failures heading with inline markup is refused the same way, naming the plan's line.
lim lpa '- base limit: 3 hosts.' '- plan: .claude/plans/lpa.md'; mkdir -p "$WS/lpa/.claude/plans"
printf '%s\n' '# plan' '## Accepted **failure** modes' '- a plan failure mode.' > "$WS/lpa/.claude/plans/lpa.md"
HE="$HE $(tpass lpa 1 adversarial) $(grep -c ".claude/plans/lpa.md line 2: $BAD" "$TMP/perr")"
# Nothing is kept between passes: the lock's plan baseline is gone after each run, and the next round refuses again.
HE="$HE $(tpass lpa 2 adversarial) $(grep -c ".claude/plans/lpa.md line 2: $BAD" "$TMP/perr")"
lim ltr '- base limit: 3 hosts.'
printf '%s\n' '# brief' '| a case | the Stated limits row |' '## Stated limits' '- base limit: 3 hosts.' > "$WS/ltr/.claude/briefs/ltr.md"
HE="$HE $(tpass ltr 1 adversarial) $(grep -c "$BAD" "$TMP/perr")"
check "a limit added under a subheading of Stated limits with no id is refused" \
  "2 2 2 1 2 1 2 1 2 1 2 1 2 1 2 1 2 1 2 1 2 1 2 1 2 1 0 0" "$HE"

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

# #565: a ruling id cannot stand in a tracked plan (the leak test bans ids in tracked files), so a plan-file limit with no id
# is told to go in the unit brief, where the id may stand.
lim lq '- base limit: 3 hosts.' '- plan: .claude/plans/lq.md'
mkdir -p "$WS/lq/.claude/plans"; printf '%s\n' '# plan' '## Stated limits' '- a plan limit: 9 hosts.' > "$WS/lq/.claude/plans/lq.md"
QE=$(tpass lq 1 adversarial)
check "a plan limit with no id is refused naming the unit brief" "2 1" \
  "$QE $(grep -c 'put the limit in .claude/briefs/lq.md with its ruling id' "$TMP/perr")"

# Issue 601: a tracked plan cannot hold a ruling id, so main may carry a limit's ruling in its rulings file as
# `Limit: <the line> ruling:<id>`. The line passes with no inline id only when that id passes as an inline one must:
# a void id, or a rulings line for another limit, leaves it refused, and the refusal names the line main can add.
plim() { # <unit> <rulings line>: a plan whose Stated limits gains one limit, and main's rulings file holding the line
  lim "$1" '- base limit: 3 hosts.' "- plan: .claude/plans/$1.md"; mkdir -p "$WS/$1/.claude/plans"
  printf '%s\n' '# plan' '## Stated limits' '- a plan limit: 9 hosts.' > "$WS/$1/.claude/plans/$1.md"
  printf '%s\n' "$2" > "$REPO/.claude/briefs/$1-main-rulings.md"; tpass --ack-rulings "$1" >/dev/null
}
plim lr "Limit: - a plan limit: 9 hosts. ruling:$OKID"; RE=$(tpass lr 1 adversarial)
check "a limit with no inline id passes when main's rulings file carries it with a real id" "0 0" "$RE $(grep -c "$REFUSED" "$TMP/perr")"
plim lw "Limit: - a plan limit: 9 hosts. ruling:$VOIDID"; WE=$(tpass lw 1 adversarial); WN=$(grep -c "$REFUSED" "$TMP/perr")
plim lx "Limit: - another limit: 1 host. ruling:$OKID"; XE=$(tpass lx 1 adversarial)
check "a limit whose rulings id is void or absent is refused" "2 1 2 1 1" \
  "$WE $WN $XE $(grep -c "$REFUSED" "$TMP/perr") $(grep -cF 'Limit: - a plan limit: 9 hosts. ruling:<id>' "$TMP/perr")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

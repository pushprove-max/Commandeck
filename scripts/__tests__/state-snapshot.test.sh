#!/usr/bin/env bash
# state-snapshot.test.sh -- main's checkpoint in one call (#409). What this pins: with no flag the file is the
# generator's own; --goal/--stage/--next/--open-item fill the judgment cells in place, number new queue items past
# the inherited checkpoint's, run the carry check and save by rename; and a refused or failed call leaves the file
# as it was, so the retry is the same call with the named flags.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }

# A throwaway repo around copies of the scripts, because state-snapshot calls board.sh by the path beside it. The
# board is a stub with one live unit, U.
R=$T/repo; H=$T/home; CPD=$H/.claude/checkpoints
mkdir -p "$R/scripts" "$R/templates" "$CPD" "$T/bin"
git init -q "$R"
cp "$REAL/templates/checkpoint.md" "$R/templates/"   # carry reads the template for its placeholders
for f in state-snapshot.sh paths.sh requirements.sh project-main.sh fence.sh checkpoint-context.py; do cp "$REAL/scripts/$f" "$R/scripts/"; done
cat > "$R/scripts/board.sh" <<'EOF'
#!/usr/bin/env bash
cat <<'BOARD'
RUN=run_x  WS=/w  SCRATCH=/s  ROOT=/r
main: abc1234 a thing | 0 dirty | 0 unpushed

== worktrees
  U [max/U] dirty=0

== seats (live worktrees only)
  U implementer term_u task_u
BOARD
EOF
printf '#!/bin/sh\nexit 1\n' > "$T/bin/orca-ide"; chmod +x "$T/bin/orca-ide"
snap() { (cd "$R" && env -u CLAUDE_PROJECT_DIR HOME="$H" PATH="$T/bin:$PATH" bash scripts/state-snapshot.sh "$@" 2>&1); }

# test: no flags: output unchanged
# The cksum is of the generator's output, less its time-stamped title line, for this board; C41's carry-over list changed it (the unit line).
snap --out "$CPD/a.md" >/dev/null
check "no flags: output unchanged" "4286663833 1984" "$(tail -n +2 "$CPD/a.md" | cksum | tr -s ' ' ' ')"
check "no flags: no temp file left beside the checkpoint" "a.md" "$(ls "$CPD")"

# test: flags fill TODO cells, add Q items, run carry
snap --out "$CPD/f.md" >/dev/null
RES=$(snap --out "$CPD/f.md" --goal 'ship U' --stage U=building --next U=review --open-item 'first one' --open-item 'second one'); RC=$?
check "flags fill TODO cells, add Q items, run carry: exit 0" 0 "$RC"
check "flags fill TODO cells, add Q items, run carry: cells and items" "1:1:1:1" \
  "$(grep -c '^ship U$' "$CPD/f.md"):$(grep -c '^| U | building | .* | review |$' "$CPD/f.md"):$(grep -c '^- Q-1: first one$' "$CPD/f.md"):$(grep -c '^- Q-2: second one$' "$CPD/f.md")"
check "flags fill TODO cells, add Q items, run carry: the items sit at the end of ## Queue" "- Q-2: second one" \
  "$(awk '/^## Queue/{q=1;next} /^## /{q=0} q&&NF{l=$0} END{print l}' "$CPD/f.md")"
check "flags fill TODO cells, add Q items, run carry: prints the path once" 1 "$(grep -cxF "$CPD/f.md" <<<"$RES")"
# The carry result is printed: an inherited open item the new file leaves out is named.
printf '%s\n' '## Queue' '- Q-5: inherited thing' > "$CPD/base.md"; echo "$CPD/base.md" > "$CPD/g.resumed-from"
snap --out "$CPD/g.md" >/dev/null
RES=$(snap --out "$CPD/g.md" --goal g --stage U=a --next U=b)
check "flags fill TODO cells, add Q items, run carry: carry's verdict is printed" 0 "$(grep -c 'inherited thing' <<<"$RES")"

# test: unknown unit refused, file unchanged
snap --out "$CPD/u.md" >/dev/null; BEFORE=$(cksum < "$CPD/u.md")
RES=$(snap --out "$CPD/u.md" --goal g --stage nope=x --stage U=a --next U=b); RC=$?
check "unknown unit refused, file unchanged: exit 2 naming the unit" "2:1" "$RC:$(grep -c nope <<<"$RES")"
check "unknown unit refused, file unchanged: the file" "$BEFORE" "$(cksum < "$CPD/u.md")"

# test: one call fills the Goal and the named unit's cells
snap --out "$CPD/o.md" >/dev/null; BEFORE=$(cksum < "$CPD/o.md")
RES=$(snap --out "$CPD/o.md" --stage U=build --next U=merge); RC=$?
check "one call fills the Goal and the named unit's cells: no --goal is refused naming Goal, file unchanged" "2:1:$BEFORE" \
  "$RC:$(grep -c 'Goal' <<<"$RES"):$(cksum < "$CPD/o.md")"
RES=$(snap --out "$CPD/o.md" --goal 'ship U' --next U=merge); RC=$?
check "one call fills the Goal and the named unit's cells: a missing stage is named" "2:1:$BEFORE" \
  "$RC:$(grep -c 'U stage' <<<"$RES"):$(cksum < "$CPD/o.md")"
snap --out "$CPD/o.md" --goal 'ship U' --stage 'U=build it' --next 'U=merge it' >/dev/null; RC=$?
check "one call fills the Goal and the named unit's cells: complete call" "0:0:0" \
  "$RC:$(grep -c '^TODO one line:' "$CPD/o.md"):$(grep -c '^| U |.*| TODO |' "$CPD/o.md")"

# test: a new queue item never reuses an inherited number
printf '%s\n' '## Queue (in order)' '- Q-1: obtain approval' > "$CPD/inh.md"; echo "$CPD/inh.md" > "$CPD/q.resumed-from"
snap --out "$CPD/q.md" >/dev/null
RES=$(snap --out "$CPD/q.md" --goal g --stage U=a --next U=b --open-item 'investigate unrelated failure')
check "a new queue item never reuses an inherited number: Q-2 and no Q-1" "1:1" \
  "$(grep -c '^- Q-2: investigate unrelated failure$' "$CPD/q.md"):$(grep -c 'Q-1' "$CPD/q.md")"
check "a new queue item never reuses an inherited number: carry still lists Q-1 as not carried" 0 "$(grep -c 'Q-1: obtain approval' <<<"$RES")"

# test: replaying the flagged call does not queue the item twice
# The documented recovery after a stop between the rename and carry is the same call again.
snap --out "$CPD/r.md" >/dev/null
snap --out "$CPD/r.md" --goal g --stage U=a --next U=b --open-item 'obtain approval' >/dev/null
snap --out "$CPD/r.md" --goal g --stage U=a --next U=b --open-item 'obtain approval' >/dev/null
check "replaying the flagged call does not queue the item twice: held once" "1:0" \
  "$(grep -c '^- Q-1: obtain approval$' "$CPD/r.md"):$(grep -c 'Q-2' "$CPD/r.md")"
snap --out "$CPD/r.md" --goal g --stage U=a --next U=b --open-item 'obtain approval' --open-item 'second text' >/dev/null
check "replaying the flagged call does not queue the item twice: a new text gets the next number" "1:1" \
  "$(grep -c '^- Q-1: obtain approval$' "$CPD/r.md"):$(grep -c '^- Q-2: second text$' "$CPD/r.md")"

# test: the template's own three-column unit table is filled
{ sed -n '1,15p' "$REAL/templates/checkpoint.md"; echo '| U | TODO | TODO |'; sed -n '16,$p' "$REAL/templates/checkpoint.md"; } > "$CPD/t.md"
RES=$(snap --out "$CPD/t.md" --goal g --stage U=building --next U=review); RC=$?
check "the template's three-column unit table is filled: exit 0 and the row" "0:1" \
  "$RC:$(grep -c '^| U | building | review |$' "$CPD/t.md")"
check "the hand template's Goal placeholder is filled: the line under ## Goal is the goal and no placeholder remains" "g:0" \
  "$(grep -A1 '^## Goal$' "$CPD/t.md" | tail -1):$(grep -c '^<one line:' "$CPD/t.md")"

# test: a hand-template checkpoint whose Goal placeholder is left is refused naming Goal
{ sed -n '1,15p' "$REAL/templates/checkpoint.md"; echo '| U | TODO | TODO |'; sed -n '16,$p' "$REAL/templates/checkpoint.md"; } > "$CPD/t2.md"
RES=$(snap --out "$CPD/t2.md" --stage U=building --next U=review 2>&1); RC=$?
check "a hand-template checkpoint with its Goal placeholder unfilled is refused naming Goal" "2:1:1" \
  "$RC:$(grep -c 'Goal (--goal' <<<"$RES"):$(grep -c '^<one line:' "$CPD/t2.md")"

# test: a failed save is never reported as saved
snap --out "$CPD/s.md" >/dev/null
RES=$(cd "$R" && mv() { return 1; } && export -f mv && env -u CLAUDE_PROJECT_DIR HOME="$H" PATH="$T/bin:$PATH" bash scripts/state-snapshot.sh --out "$CPD/s.md" --goal g --stage U=a --next U=b 2>&1); RC=$?
check "a failed save is never reported as saved: nonzero exit, the message, no path printed" "1:1:0" \
  "$RC:$(grep -c 'could not save the checkpoint' <<<"$RES"):$(grep -cxF "$CPD/s.md" <<<"$RES")"
check "a failed save is never reported as saved: the old file is whole" 1 "$(grep -c '^TODO one line:' "$CPD/s.md")"

# test: issue 431: the checkpoint leaves out the worktrees the project config keeps, and only those
# Same hand-written config and kept name (Fast-lane) as close-done-panes.test.sh's sweep: both scripts read one list.
cat > "$R/scripts/board.sh" <<'EOF'
#!/usr/bin/env bash
cat <<'BOARD'
RUN=run_x  WS=/w  SCRATCH=/s  ROOT=/r
main: abc1234 a thing | 0 dirty | 0 unpushed

== worktrees
  U [max/U] dirty=0
  Fast-lane [max/F] dirty=0
  Research [max/R] dirty=0
BOARD
EOF
mkdir -p "$R/.claude"
units() { grep -E '^\| (U|Fast-lane|Research) ' "$1" | cut -d' ' -f2 | paste -sd' ' -; }
printf '%s' '{"keepWorktrees":["Fast-lane"]}' > "$R/.claude/commandeck.json"
snap --out "$CPD/k1.md" >/dev/null
check "a kept worktree is omitted and an ordinary one is listed" "U Research" "$(units "$CPD/k1.md")"
printf '%s' '{"version":1}' > "$R/.claude/commandeck.json"
snap --out "$CPD/k2.md" >/dev/null
check "a missing key keeps the standing worktrees: only the ordinary one is listed" "U" "$(units "$CPD/k2.md")"
printf '%s' '{"keepWorktrees":[]}' > "$R/.claude/commandeck.json"
snap --out "$CPD/k3.md" >/dev/null
check "only an explicit empty array keeps nothing: every worktree is listed" "U Fast-lane Research" "$(units "$CPD/k3.md")"

# test: carry-over list (issue 568): the generator writes the unit, decision and copied lines the carry check wants
# Board stub: U always, V only when read with --full (the plain board cuts it); WS holds the units' report files.
cp "$REAL/scripts/decision.sh" "$R/scripts/"; mkdir -p "$R/hooks"; cp -R "$REAL/hooks/lib" "$R/hooks/"; mkdir -p "$R/.claude/metrics" "$T/ws/U/.claude/briefs"
LEDGER=$R/.claude/metrics/decisions.jsonl
row() { printf '{"id":"%s","question":"%s","proposedDefault":"d","source":"s","askedAt":"2026-11-02T10:00:00Z","answer":%s,"answeredAt":%s}\n' "$1" "$2" "$3" "$4"; }
{ row d-open "Which way?" null null; row d-two 'Line one\nline two' null null; row d-done "Settled?" '"yes"' '"2026-11-02T11:00:00Z"'; } > "$LEDGER"
cat > "$R/scripts/board.sh" <<'EOF'
#!/usr/bin/env bash
[ ! -e "$(dirname "$0")/../board.rc" ] || exit "$(cat "$(dirname "$0")/../board.rc")"
echo "RUN=run_x  WS=WSDIR  SCRATCH=/s  ROOT=/r"
echo "main: abc1234 a thing | 0 dirty | 0 unpushed"
echo; echo "== worktrees"; echo "  U [max/U] dirty=0"
[ "${1-}" != --full ] || echo "  V [max/V] dirty=0"
EOF
sed -i.bak "s#WSDIR#$T/ws#" "$R/scripts/board.sh"; rm -f "$R/scripts/board.sh.bak"
cat > "$CPD/c-base.md" <<'EOF'
## Queue
- unit U -- still open: round 1 reports
- Q-5: hand thing
- unit Gone -- still open: round 2 reports
- decision d-gone: an old question -- done when: decision:d-gone
- Q-9: ship it -- done when: decision:d-done
EOF
queue() { awk '/^## Queue/{q=1;next} /^## /{q=0} q' "$1"; }
closed() { awk '/^## Closed/{c=1;next} /^## /{c=0} c' "$1"; }
carry() { (cd "$R" && python3 scripts/checkpoint-context.py carry "$1" "$2" 2>&1); }
echo "$CPD/c-base.md" > "$CPD/c1.resumed-from"
snap --out "$CPD/c1.md" >/dev/null
carry "$CPD/c-base.md" "$CPD/c1.md" >/dev/null; RC=$?
check "a restart's carry-over list passes the carry check with no hand edit: carry exits 0" 0 "$RC"
check "a restart's carry-over list passes the carry check with no hand edit: unit, decisions and reference line" "1:1:1:0:1" \
  "$(queue "$CPD/c1.md" | grep -c '^- unit U -- still open: no round yet$'):$(queue "$CPD/c1.md" | grep -c '^- decision d-open: Which way? -- done when: decision:d-open$'):$(queue "$CPD/c1.md" | grep -c '^- decision d-two: Line one line two -- done when: decision:d-two$'):$(queue "$CPD/c1.md" | grep -c 'decision:d-done'):$(grep -cxF "Carries open items of: $CPD/c-base.md" "$CPD/c1.md")"
check "an item whose task is done is not carried" "0:0:1:1" \
  "$(grep -c 'Q-9' "$CPD/c1.md"):$(queue "$CPD/c1.md" | grep -c 'Gone\|d-gone'):$(closed "$CPD/c1.md" | grep -c '^- unit Gone -- still open: round 2 reports -- no longer live ('):$(closed "$CPD/c1.md" | grep -c '^- decision d-gone: .* -- no longer live (')"
check "a hand-written item still open in the baseline is copied under the Queue" 1 "$(queue "$CPD/c1.md" | grep -c '^- Q-5: hand thing$')"
check "the board is read in full so a unit past the cut is listed" 1 "$(queue "$CPD/c1.md" | grep -c '^- unit V -- still open')"
# a unit's stage is its latest report round: numeric, so r10 is newer than r9
for n in 2 9 10; do : > "$T/ws/U/.claude/briefs/U-r$n-reports.md"; done
snap --out "$CPD/c2.md" >/dev/null
check "a unit's stage is its latest report round, else no round yet" "1:1" \
  "$(queue "$CPD/c2.md" | grep -c '^- unit U -- still open: round 10 reports$'):$(queue "$CPD/c2.md" | grep -c '^- unit V -- still open: no round yet$')"
# a failed listing keeps its kind's baseline items open: they are copied, never closed
echo 1 > "$R/board.rc"; mv "$R/scripts/decision.sh" "$R/scripts/decision.sh.off"; printf '#!/bin/sh\nexit 1\n' > "$R/scripts/decision.sh"
echo "$CPD/c-base.md" > "$CPD/c3.resumed-from"
snap --out "$CPD/c3.md" >/dev/null
check "a failed board or decision listing keeps the baseline's items open" "1:1:1:0" \
  "$(queue "$CPD/c3.md" | grep -c '^- unit Gone -- still open: round 2 reports$'):$(queue "$CPD/c3.md" | grep -c '^- decision d-gone: '):$(queue "$CPD/c3.md" | grep -c '^- unit U -- still open: round 1 reports$'):$(grep -c 'no longer live' "$CPD/c3.md")"
rm -f "$R/board.rc"; mv "$R/scripts/decision.sh.off" "$R/scripts/decision.sh"
# an unreadable baseline: nothing is copied and no reference line says the base was read
echo "$CPD/nope.md" > "$CPD/c4.resumed-from"
snap --out "$CPD/c4.md" >/dev/null
check "an unreadable baseline copies nothing and writes no reference line" "0:0:1" \
  "$(grep -c '^Carries open items of:' "$CPD/c4.md"):$(queue "$CPD/c4.md" | grep -c 'Q-5\|Gone'):$(queue "$CPD/c4.md" | grep -c '^- unit U -- still open')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

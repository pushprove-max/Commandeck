#!/usr/bin/env bash
# board.sh is the one call main makes after every wake. It listed a unit's
# round files only as brief names with times, so a unit whose newest pass ended
# NO-GO read like one waiting to merge (#91). What this pins: the newest round by
# number (r10 after r9, whatever the file times) is shown with its kind, its
# verdict and its finding counts.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }
mkdir -p "$T/bin" "$T/home"; printf '#!/bin/sh\nexit 1\n' > "$T/bin/orca-ide"; chmod +x "$T/bin/orca-ide"
git init -q -b main "$T/proj" && git -C "$T/proj" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
git -C "$T/proj" worktree add -q "$T/ws/u1" -b u1; B=$T/ws/u1/.claude/briefs; mkdir -p "$B"
board() { (cd "$T/proj" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/proj" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_SCRATCH="$T/scratch" COMMANDECK_AGENTS= COMMANDECK_DRIVERS= bash "$REAL/scripts/board.sh" u1 2>&1 | grep '^      pass '); }
round() { printf '## Sol\nReviewed: x\nCodex thread: t\nPass: %s\n\n%s\n\nVERDICT: %s\n' "$2" "$3" "$4" > "$B/u1-r$1-reports.md"; }

round 9 adversarial '- [P3] nit -- a:1' GO
round 10 review $'- [P1] bad -- a:1\n- [P2] meh -- a:2\n- [P2] meh too -- a:3' NO-GO
touch -t 202601010000 "$B/u1-r10-reports.md"
check "a unit whose newest pass ended NO-GO shows it, with its findings" "      pass r10 review: VERDICT: NO-GO (P1 1, P2 2)" "$(board)"
round 11 final 'Clean.' GO
check "the next pass's GO replaces it" "      pass r11 final: VERDICT: GO" "$(board)"
# Sol r3: a planner runs in <unit>-plan before its unit has a worktree, and the seats list hid it.
mkdir -p "$T/scratch" "$T/ws/u2-plan"; printf 'handle=h7\ntask=task_7\nrole=plan-author\nunit=u2\nworktree=u2-plan\n' > "$T/scratch/seat-u2-plan-author.txt"
check "a planner in its planning worktree is listed under its unit" "  u2 plan-author h7 task_7" \
  "$(cd "$T/proj" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/proj" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_SCRATCH="$T/scratch" COMMANDECK_AGENTS= COMMANDECK_DRIVERS= bash "$REAL/scripts/board.sh" u2 2>&1 | grep '^  u2 plan-author')"
# Issue 233 put a seat's launch in the background: main reads where each seat of a unit is, one line per seat record.
printf 'handle=h8\ntask=task_8\nrole=builder\nunit=u3\nphase=launching\nphase=dispatched\nverdict=VERDICT: GO\n' > "$T/scratch/seat-u3-builder.txt"
printf 'handle=h9\nrole=plan-judge-sol\nunit=u3\n' > "$T/scratch/seat-u3-plan-judge-sol.txt"
printf 'handle=h6\nrole=builder\nunit=u3-x\n' > "$T/scratch/seat-u3-x-builder.txt"
check "--unit u3 --seats prints each of u3's seats (role, handle, phase, verdict), and no other unit's" \
  "$(printf '  builder h8 dispatched VERDICT: GO\n  plan-judge-sol h9 - -')" \
  "$(cd "$T/proj" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/proj" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_SCRATCH="$T/scratch" bash "$REAL/scripts/board.sh" --unit u3 --seats 2>&1)"
# Issue 223: board.sh printed every worktree whole, and thirty of them filled main's context. The default is cut at
# 3,000 bytes, each section still shown, with the whole board in a named file; --full prints the whole.
for i in $(seq -w 1 30); do
  git -C "$T/proj" worktree add -q "$T/ws/w$i" -b "w$i"; mkdir -p "$T/ws/w$i/.claude/briefs"
  echo brief > "$T/ws/w$i/.claude/briefs/w$i.md"; printf 'Pass: review\n\nVERDICT: GO\n' > "$T/ws/w$i/.claude/briefs/w$i-r1-reports.md"
done
bd() { (cd "$T/proj" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/proj" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_SCRATCH="$T/scratch" COMMANDECK_AGENTS= COMMANDECK_DRIVERS= bash "$REAL/scripts/board.sh" "$@" 2>&1); }
OUT=$(bd); WHOLE=$(sed -n 's/.*(whole board: \([^;]*\);.*/\1/p' <<<"$OUT")
check "thirty worktrees: under 3,000 bytes, every section header kept, the whole board in the named file" "yes 1 30" \
  "$([ "$(printf '%s' "$OUT" | wc -c)" -lt 3000 ] && echo yes) $(grep -c '^== loops and main-watch' <<<"$OUT") $(grep -c '^  w[0-9]* \[' "$WHOLE" 2>/dev/null)"
check "--full prints every worktree" 30 "$(bd --full | grep -c '^  w[0-9]* \[')"
# The host project's second-machine chain lines read files no plugin script writes; the plugin has no second machine.
check "no CHAIN HOST, OFFLOADED or PLACEMENT WAIT line" 0 "$(bd --full | grep -cE '^(CHAIN HOST|OFFLOADED|PLACEMENT WAIT)')"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

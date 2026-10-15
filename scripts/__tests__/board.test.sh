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
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

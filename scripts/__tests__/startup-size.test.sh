#!/usr/bin/env bash
# covers: scripts/startup-size.sh
# startup-size.test.sh -- main's injected card (templates/main-session.md above its Details heading) is one screen: a
# 41-line part fails startup-size.sh, a 40-line part passes, and the plugin's own card is within it. A longer card
# rides in every main session's start and every resume.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
# card <lines> -- a card of that many lines above the Details heading, the heading line not counted.
card() { { for i in $(seq 1 "$1"); do echo "line $i"; done; echo "## Details (not injected)"; echo "- tail"; } > "$T/card.md"; }
size() { COMMANDECK_CARD_FILE=$T/card.md bash "$REAL/scripts/startup-size.sh" --role worker 2>&1 >/dev/null | grep -c "injected part is .* lines, over 40"; }
card 40; check "a 40-line injected part passes" 0 "$(size)"
card 41; check "a 41-line injected part fails, naming its length" 1 "$(size)"
check "the plugin's own main-session card is within 40 lines" 0 \
  "$(bash "$REAL/scripts/startup-size.sh" --role worker 2>&1 >/dev/null | grep -c "injected part is .* lines, over 40")"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

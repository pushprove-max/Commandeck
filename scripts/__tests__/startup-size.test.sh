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
# Issue 611: main loaded three procedural lines at every start. Each moved under Details word for word, a pointer in
# its place, so the injected part is under 5,600 bytes and no rule's words are lost.
CARD=$(awk '/^## Details \(not injected\)/ {exit} 1' "$REAL/templates/main-session.md")
DET=$(awk 'f; /^## Details \(not injected\)/ {f = 1}' "$REAL/templates/main-session.md")
B=$(printf '%s\n' "$CARD" | LC_ALL=C wc -c | tr -d ' ')
check "the plugin's main-session injected part is under 5,600 bytes" yes "$([ "$B" -lt 5600 ] && echo yes || echo "no: $B bytes")"
n=0
while IFS= read -r l; do grep -qxF -- "$l" <<<"$DET" && ! grep -qxF -- "$l" <<<"$CARD" && n=$((n + 1)); done <<'EOF'
  - a test run in main's foreground, whatever its length, or any other command that can run in the background (a directory-size scan, any wait on external state) -> `run_in_background` and `wait-test-run.sh <pid> <file>`, or its own pane; only quick reads stay in the foreground; `answer-worker.sh`, `seat.sh run` and the merge already return at once
  - a Builder whose pane is gone (`seat.sh status builder <unit>` shows `pane=gone`) -> `bash scripts/orca-wait.sh --close <its task id>`, then `bash scripts/seat.sh launch builder <unit> <its newest hand-off or the brief>`; the launch writes the new pane's handle into the seat record, and the next fix round goes there
  A plan's questions sit in its one `## Question for the owner` section (plan-check.sh refuses a `> Owner:` line elsewhere): send the section as one ask, id `plan-<unit>`. A plan judge's new question is a `Question for the owner:` finding; add it with `decision.sh add plan-<unit> ... --reask`.
EOF
check "each moved main-session line appears word for word under Details" 3 "$n"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

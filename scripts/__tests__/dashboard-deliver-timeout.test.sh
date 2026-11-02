#!/usr/bin/env bash
# dashboard-deliver-timeout.test.sh -- issue 569, pass 9 (the owner's answer, in main's rulings). The dashboard sends
# the owner's answer to the asking unit through `decision.sh deliver` under a 25 s cut, and decision.sh cuts answer-worker
# at 20 s. A send cut at either deadline may already have reached the unit, so it reads unknown, check the pane before
# resending, never not delivered: main resends on not delivered, and the unit would get the answer twice.
# subprocess.run is stubbed, so nothing is sent. Run: bash scripts/__tests__/dashboard-deliver-timeout.test.sh
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

# Catches: the host's own 25 s cut, or decision.sh's unknown line for its 20 s cut, read as not delivered.
OUT=$(python3 - "$ROOT/scripts" <<'PY'
import subprocess, sys
sys.path.insert(0, sys.argv[1])
import dashboard_serve as d
def hang(*a, **k): raise subprocess.TimeoutExpired(a[0], 25)
d.subprocess.run = hang
print(d.deliver_to_unit('/x', '/x', 'u1-msg_d9', 't'))
d.subprocess.run = lambda *a, **k: subprocess.CompletedProcess(a[0], 1, '', "unknown: u1-msg_d9 to u1 timed out; check the unit's pane before resending\n")
print(d.deliver_to_unit('/x', '/x', 'u1-msg_d9', 't'))
PY
)
check "a dashboard send cut at its deadline reads unknown, check the pane before resending" "unknown: u1-msg_d9 timed out; check the unit's pane before resending
unknown: u1-msg_d9 to u1 timed out; check the unit's pane before resending" "$OUT"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

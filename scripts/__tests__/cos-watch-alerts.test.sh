#!/usr/bin/env bash
# cos-watch-alerts.test.sh -- the collector ends an alert's id with the time
# the condition began, and keeps that time while it lasts. What this pins: an
# alert the owner was told about stays quiet while it lasts, and the same
# condition coming back is a new alert, whether or not a poll saw it clear.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

mkdir -p "$T/home/.commandeck/chief-of-staff" "$T/dash"
git init -q -b main "$T/proj" && git -C "$T/proj" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
SEEN=$T/home/.commandeck/chief-of-staff/proj.alerts-seen
data() { printf 'window.DASH = {"alerts": [%s]};\n' "$1" > "$T/dash/data.js"; }
watch() { (cd "$T/proj" && HOME="$T/home" COMMANDECK_DASHBOARD_DIR="$T/dash" COMMANDECK_SCRATCH="$T/scratch" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_WATCH_ONCE=1 bash "$ROOT/scripts/cos-watch-alerts.sh" 2>&1); }

data '{"id": "limit-claude-1791717824", "text": "FIRST"}'
OUT=$(watch); check "a new alert wakes the pane" "0 1" "$? $(grep -c FIRST <<<"$OUT")"
echo limit-claude-1791717824 >> "$SEEN"
data '{"id": "limit-claude-1791717824", "text": "SAME"}'
OUT=$(watch); check "the alert, still there, stays quiet" "1 0" "$? $(grep -c SAME <<<"$OUT")"
data '{"id": "limit-claude-1791999999", "text": "AGAIN"}'
OUT=$(watch); check "it cleared and came back between two polls: told again" "0 1" "$? $(grep -c AGAIN <<<"$OUT")"
data ''
OUT=$(watch); check "no alert, nothing to say" 1 $?

# The dashboard's alerts are every project's: another project's stalled unit
# or waiting question is not this project's Chief of Staff's to raise.
data '{"id": "stage-other/u1-1791999999", "project": "other", "text": "THEIRS"}'
OUT=$(watch); check "another project's alert does not wake this one" "1 0" "$? $(grep -c THEIRS <<<"$OUT")"
data '{"id": "stage-proj/u1-1791999999", "project": "proj", "text": "OURS"}'
OUT=$(watch); check "this project's alert does" "0 1" "$? $(grep -c OURS <<<"$OUT")"

# A project named __proto__ is written to data.js under a computed key, which
# is a script, not JSON: read as JSON it failed every poll, and both watchers
# went quiet for every project on the machine.
printf 'window.DASH = {"projects":{["__proto__"]:{"a":1},"proj":{}},"limit":{"usedPct":93},"alerts":[{"id":"x-1","text":"PROTO"}]};\n' > "$T/dash/data.js"
OUT=$(watch); check "a snapshot with a computed key is still read for alerts" "0 1" "$? $(grep -c PROTO <<<"$OUT")"
limit() { (cd "$T/proj" && HOME="$T/home" COMMANDECK_DASHBOARD_DIR="$T/dash" COMMANDECK_SCRATCH="$T/scratch" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_WATCH_ONCE=1 bash "$ROOT/scripts/cos-watch-limit.sh" 2>&1); }
OUT=$(limit); check "and for the limit" "0 1" "$? $(grep -c '93%' <<<"$OUT")"

# The pane arms the limit watcher again each time it exits. Usage that has not
# moved since it was told is not news: it woke the pane on every rearm.
lim() { printf 'window.DASH = {"limit":{"usedPct":%s}};\n' "$1" > "$T/dash/data.js"; limit; }
OUT=$(lim 93); check "rearmed with usage unchanged, the watcher stays quiet" 1 $?
OUT=$(lim 93.4); check "and with a fraction more" 1 $?
OUT=$(lim 95); check "usage that rose is told" "0 1" "$? $(grep -c '95%' <<<"$OUT")"
OUT=$(lim 40); check "under the threshold nothing is said" 1 $?
OUT=$(lim 91); check "a new week over the threshold is told again" "0 1" "$? $(grep -c '91%' <<<"$OUT")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

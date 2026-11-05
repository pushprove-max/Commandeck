#!/usr/bin/env bash
# cos-supervise.test.sh -- cos-supervise.sh, the one background command that runs the relay's four watchers (issue 655).
# Each watcher exits on a find, and every exit used to wake the model; a watcher that died looked the same as one that
# found nothing, so it died unnoticed until a Stop hook turn. What this pins: a dead watcher is restarted and logged
# without a turn; a watcher that keeps dying ends the supervisor with one line the model reads; one supervisor runs per
# key; no child outlives the supervisor; the units watcher is among the children. The watchers are stubs in a copy of the
# plugin's scripts folder, so the supervisor finds them where it finds the real ones.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); SUP=; trap '[ -z "$SUP" ] || kill "$SUP" 2>/dev/null; pkill -f "$T/plug" 2>/dev/null; rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
mkdir -p "$T/home" "$T/scratch" "$T/plug/scripts" "$T/state"
git init -q -b main "$T/p"
for f in "$REAL"/*; do [ "$f" = "$REAL/scripts" ] || ln -s "$f" "$T/plug/"; done
for f in "$REAL"/scripts/*; do ln -s "$f" "$T/plug/scripts/"; done
rm "$T"/plug/scripts/cos-watch-{decisions,alerts,limit,units}.sh
# A stub starts, counts itself, records its pid like cos_wait, and dies at once while $T/die-<name> holds a count or
# $T/alwaysdie-<name> exists; otherwise it waits like a watcher with nothing to find.
for n in decisions alerts limit units; do
  cat > "$T/plug/scripts/cos-watch-$n.sh" <<EOF
#!/usr/bin/env bash
. "\$(dirname "\${BASH_SOURCE[0]}")/cos-lib.sh"
echo \$\$ > "\$COS_KEY.cos-watch-$n.pid"; echo x >> "$T/starts-$n"
[ ! -e "$T/alwaysdie-$n" ] || exit 1
[ ! -s "$T/die-$n" ] || { rm "$T/die-$n"; exit 1; }
sleep 60
EOF
done
# The inbox poller is a child too (issue 584): its stub waits like the others, so no case reads the real Orca inbox.
rm -f "$T/plug/scripts/cos-watch-inbox.sh"; printf '#!/usr/bin/env bash\n. "$(dirname "${BASH_SOURCE[0]}")/cos-lib.sh"\necho $$ > "$COS_KEY.cos-watch-inbox.pid"\nsleep 60\n' > "$T/plug/scripts/cos-watch-inbox.sh"
chmod +x "$T"/plug/scripts/cos-watch-*.sh
E=(env -u CLAUDE_PROJECT_DIR HOME="$T/home" COMMANDECK_MAIN="$T/p" COMMANDECK_SCRATCH="$T/scratch" COMMANDECK_DASHBOARD_DIR="$T/state")
# orca-ide is a stub: each typed text is one line of $T/typed (newlines as |); the receipt is $T/receipt, else turn_started.
mkdir -p "$T/bin"; cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
while [ \$# -gt 0 ]; do [ "\$1" = --text ] && printf '%s\n' "\$2" | paste -sd'|' - >> "$T/typed"; shift; done
cat "$T/receipt" 2>/dev/null || echo '{"ok":true,"result":{"accepted":true,"stages":["accepted","turn_started"]}}'
EOF
chmod +x "$T/bin/orca-ide"; E+=(PATH="$T/bin:$PATH" COMMANDECK_SUPERVISE_RETRY=0)
KEY=$(cd "$T/p" && "${E[@]}" bash -c '. "$1/hooks/lib/project.sh"; pp_cos_key; printf %s "$COS_KEY"' _ "$REAL")
mkdir -p "${KEY%/*}"
# starts <name>: how many times the stub ran.
starts() { wc -l < "$T/starts-$1" 2>/dev/null | tr -d ' ' || echo 0; }
# waitfor <seconds> <command...>: poll a condition in tenths of a second.
waitfor() { local i; for ((i = 0; i < $1 * 10; i++)); do "${@:2}" && return 0; sleep 0.1; done; return 1; }
# sup: run the supervisor in the background, output to $T/sup.out, its pid in SUP.
sup() { (cd "$T/p" && exec "${E[@]}" bash "$T/plug/scripts/cos-supervise.sh" > "$T/sup.out" 2>&1) & SUP=$!; }
alive() { [ "${1:-0}" -gt 0 ] && kill -0 "$1" 2>/dev/null; }
# left: how many stub watchers still run.
left() { pgrep -f "$T/plug/scripts/cos-watch-" 2>/dev/null | wc -l | tr -d " "; }

# first start delivers the find of a watcher it stopped (pass 14, lost-wake): with no ack ledger yet, a hand-armed
# watcher has written its find (and set its seen mark) when the supervisor stops it, so its exit never woke the pane;
# that one file is typed and acked. An old wake file of a writer that ended on its own woke the pane when it exited,
# so it is acked untyped (the wake files are never pruned: replaying them all would repeat every old find).
mkdir -p "$T/hand"; printf '#!/usr/bin/env bash\necho $$ > "%s.cos-watch-alerts.pid"\necho "A1 find of a hand-armed watcher" > "%s.cos-watch-alerts-wake-1-$$.txt"\nsleep 60\n' "$KEY" "$KEY" > "$T/hand/cos-watch-alerts.sh"
echo "A0 old find" > "$KEY.cos-watch-alerts-wake-1-99999999.txt"
bash "$T/hand/cos-watch-alerts.sh" & HANDP=$!
waitfor 5 test -s "$KEY.cos-watch-alerts-wake-1-$HANDP.txt"
sup
waitfor 5 test -s "$T/typed"; sleep 0.5
check "first start delivers the find of a watcher it stopped, and no older find" "1 A1 find of a hand-armed watcher 1 1 dead" \
  "$(wc -l < "$T/typed" 2>/dev/null | tr -d ' ') $(head -1 "$T/typed" 2>/dev/null) $(grep -c "wake-1-$HANDP.txt" "$KEY.supervise.acked") $(grep -c 'wake-1-99999999.txt' "$KEY.supervise.acked") $(kill -0 "$HANDP" 2>/dev/null && echo alive || echo dead)"
kill "$SUP" 2>/dev/null; wait "$SUP" 2>/dev/null; SUP=; waitfor 5 test "$(left)" = 0
rm -f "$T/typed" "$T"/starts-* "$KEY".supervise.* "$KEY".cos-watch-*-wake-*

# dead watcher is restarted and logged: the limit watcher dies once; the supervisor starts it again, writes one line
# naming it to the supervise log, and keeps running, so nothing woke the model.
echo 1 > "$T/die-limit"
sup
waitfor 5 test "$(starts limit)" -ge 2
check "dead watcher is restarted and logged" "2 1 yes" "$(starts limit) $(grep -c 'cos-watch-limit' "$KEY.supervise.log" 2>/dev/null) $(alive "$SUP" && echo yes)"
check "the other watchers each started once, not restarted" "1 1 1" "$(starts decisions) $(starts alerts) $(starts units)"
check "units watcher runs under the supervisor" 1 "$(starts units)"
check "the supervisor records its own pid for cos-check" "$SUP" "$(cat "$KEY.cos-supervise.pid" 2>/dev/null)"

# second supervisor is refused while one runs: no child starts, it says who runs, and it exits 0.
OUT=$(cd "$T/p" && "${E[@]}" timeout 5 bash "$T/plug/scripts/cos-supervise.sh" 2>&1); RC=$?
check "second supervisor is refused while one runs" "0 cos-supervise: already running (pid $SUP) 1" "$RC $OUT $(starts decisions)"

# supervisor exit stops its children: after TERM no stub is left, and their pid files are gone.
CHILD=$(cat "$KEY.cos-watch-decisions.pid" 2>/dev/null || echo 0)
BEFORE=$(alive "$CHILD" && echo alive || echo dead)
kill "$SUP" 2>/dev/null; wait "$SUP" 2>/dev/null; SUP=
waitfor 5 test "$(left)" = 0
check "supervisor exit stops its children" "alive dead 0 " "$BEFORE $(alive "$CHILD" && echo alive || echo dead) $(left) $(ls "$KEY".cos-watch-*.pid 2>/dev/null)"

# third death in ten minutes wakes: the limit watcher never stays up; the supervisor prints the one exception line and
# exits, and no other watcher is left running.
rm -f "$T"/starts-*; touch "$T/alwaysdie-limit"
sup
waitfor 5 bash -c "! kill -0 $SUP 2>/dev/null"
wait "$SUP" 2>/dev/null; SUP=
check "third death in ten minutes wakes" "cos-supervise: cos-watch-limit died 3 times in 10 min; log $KEY.supervise.log" "$(tail -1 "$T/sup.out")"
check "and the exit leaves no watcher running" 0 "$(left)"

# a watcher without its exec bit still runs (pass 1): cos-watch-units.sh ships as mode 644; run directly it exited 126
# three times and the supervisor stopped every watcher. Each watcher is run through bash, whatever its mode.
rm -f "$T"/starts-* "$T/alwaysdie-limit"; chmod -x "$T/plug/scripts/cos-watch-units.sh"
sup
waitfor 5 test "$(starts units)" -ge 1
sleep 0.5
check "a watcher without its exec bit still runs" "1 yes" "$(starts units) $(alive "$SUP" && echo yes)"
kill "$SUP" 2>/dev/null; wait "$SUP" 2>/dev/null; SUP=
waitfor 5 test "$(left)" = 0

# From here each stub finds what $T/say-<name> holds, through cos_wait, so its find is in a wake file as a real one's is.
rm -f "$T"/plug/scripts/cos-watch-*.sh "$T"/alwaysdie-* "$T"/starts-*
for n in decisions alerts limit units inbox; do
  cat > "$T/plug/scripts/cos-watch-$n.sh" <<EOF
#!/usr/bin/env bash
. "\$(dirname "\${BASH_SOURCE[0]}")/cos-lib.sh"
echo "\$*" >> "$T/starts-$n"
poll() { [ -s "$T/say-$n" ] || return 1; cat "$T/say-$n"; rm -f "$T/say-$n"; [ ! -e "$T/crash-$n" ] || { rm -f "$T/crash-$n"; exit 1; }; }
cos_wait 0.2 poll
EOF
done
chmod +x "$T"/plug/scripts/cos-watch-*.sh
say() { printf '%s\n' "$2" > "$T/say.tmp"; mv "$T/say.tmp" "$T/say-$1"; }
typed() { [ -e "$T/typed" ] && wc -l < "$T/typed" | tr -d ' ' || echo 0; }
acked() { grep -c "$1" "$KEY.supervise.acked" 2>/dev/null; }
sup2() { (cd "$T/p" && exec "${E[@]}" bash "$T/plug/scripts/cos-supervise.sh" term_relay > "$T/sup.out" 2>&1) & SUP=$!; }
sup2
waitfor 5 test -s "$T/starts-inbox"

# decision line wakes once: an open decision is typed into the relay pane one time, its wake file is acked, and the
# supervisor keeps running (no re-arm turn).
say decisions "D1 open decision for the owner"
waitfor 5 test "$(typed)" -ge 1; sleep 1
check "decision line wakes once" "1 D1 open decision for the owner 1 yes" "$(typed) $(tail -1 "$T/typed") $(acked cos-watch-decisions-wake) $(alive "$SUP" && echo yes)"

# batch line joins the held notes: a warn alert is routine; it goes to the inbox state's held notes as a line that
# starts with a digit (cos-check counts those) and types nothing.
printf '7 enc\n' > "$KEY.inbox-seq"
say alerts '{"id": "cache-hit-1791717824", "severity": "warn", "text": "cache hit 90%"}'
waitfor 5 test "$(wc -l < "$KEY.inbox-seq")" -ge 2; sleep 0.5
check "batch line joins the held notes" "1 1 1" "$(typed) $(grep -c '^[0-9].*cache-hit-1791717824' "$KEY.inbox-seq") $(acked cos-watch-alerts-wake)"

# long crit alert summary still wakes: over 600 bytes the watcher prints only a summary line; the crit severity is in
# the whole text that line names, and it still wakes.
say alerts "{\"id\": \"limit-claude-1791717824\", \"severity\": \"crit\", \"text\": \"$(printf 'x%.0s' {1..700})\"}"
waitfor 5 test "$(typed)" -ge 2
check "long crit alert summary still wakes" "2 1" "$(typed) $(tail -1 "$T/typed" | grep -c '^cos-watch-alerts woke: 1 records, .*; whole text: ')"

# inbox poller text wakes through the supervisor: the poller runs as the supervisor's child with the pane's handle, and
# what it prints is typed into the pane (issue 584: no Stop hook re-arm).
say inbox '2026-11-05T10:00:00Z [from main] "order" | "merge unit-7"'
waitfor 5 test "$(typed)" -ge 3
check "inbox poller text wakes through the supervisor" "term_relay 3 1" "$(head -1 "$T/starts-inbox") $(typed) $(tail -1 "$T/typed" | grep -c 'merge unit-7')"
say inbox '2026-11-05T10:01:00Z [from main] "order" | "second"'
waitfor 5 test "$(typed)" -ge 4
check "two inbox events wake the relay twice with no re-arm" "4 1 yes $SUP" "$(typed) $(tail -1 "$T/typed" | grep -c second) $(alive "$SUP" && echo yes) $(cat "$KEY.cos-supervise.pid")"

# other watcher's later delivery does not ack an earlier event: a wake file whose writer still runs is not published at
# start; a later find of another watcher is delivered and acked by its own name only.
kill "$SUP"; wait "$SUP" 2>/dev/null; SUP=
sleep 30 & HOLD=$!
EARLY=$KEY.cos-watch-limit-wake-100-$HOLD.txt; echo "7-day limit at 95% (threshold 90%)" > "$EARLY"
sup2; waitfor 5 test -s "$T/starts-inbox"
say decisions "D2 later decision"
waitfor 5 test "$(typed)" -ge 5; sleep 0.5
check "other watcher's later delivery does not ack an earlier event" "0 2" "$(acked "${EARLY##*/}") $(acked cos-watch-decisions-wake)"
kill "$HOLD" 2>/dev/null; rm -f "$EARLY"

# queued send is typed once and acked (pass 4): Orca accepts the text into a busy pane's queue, so the receipt has no
# turn_started yet; the pane submits it when its turn ends. Typing it again put the same wake in the pane three times.
echo '{"ok":true,"result":{"accepted":true,"stages":["accepted"]}}' > "$T/receipt"
say decisions "D4 decision for a busy pane"
waitfor 5 test "$(typed)" -ge 6; sleep 0.5
QUE=$(grep -l 'D4 decision' "$KEY".cos-watch-decisions-wake-*.txt 2>/dev/null | head -1)
check "queued send is typed once and acked" "6 1 yes" "$(typed) $(acked "${QUE##*/}") $(alive "$SUP" && echo yes)"

# refused send stays pending: Orca refuses the text (accepted:false, nothing typed); after the third try the supervisor
# prints the line and exits, and the wake file is not acked.
echo '{"ok":true,"result":{"accepted":false}}' > "$T/receipt"
say decisions "D3 decision with no turn"
waitfor 8 bash -c "! kill -0 $SUP 2>/dev/null"; wait "$SUP" 2>/dev/null; SUP=
PEND=$(grep -l 'D3 decision' "$KEY".cos-watch-decisions-wake-*.txt 2>/dev/null | head -1)
check "refused send stays pending" "9 D3 decision with no turn 0 0" "$(typed) $(tail -1 "$T/sup.out") $(acked "${PEND##*/}") $(left)"

# event consumed before shutdown is published at next start: the decisions watcher marked D3 seen when it printed it;
# the next start types it from its unacked wake file (its writer is dead) and acks it.
rm -f "$T/receipt"
sup2; waitfor 5 test "$(typed)" -ge 10
check "event consumed before shutdown is published at next start" "10 D3 decision with no turn 1" "$(typed) $(tail -1 "$T/typed") $(acked "${PEND##*/}")"
# watcher dead after its find is still delivered (pass 5): the watcher printed its find and set its mark, then exited 1
# before its clean exit; its replacement finds nothing new, so the running supervisor types the wake file at once.
touch "$T/crash-decisions"; say decisions "D5 decision of a dying watcher"
waitfor 5 test "$(typed)" -ge 11; sleep 0.5
CR=$(grep -l 'D5 decision' "$KEY".cos-watch-decisions-wake-*.txt 2>/dev/null | head -1)
check "watcher dead after its find is still delivered" "11 D5 decision of a dying watcher 1 1 yes" \
  "$(typed) $(tail -1 "$T/typed") $(acked "${CR##*/}") $(grep -c 'cos-watch-decisions died (status 1)' "$KEY.supervise.log") $(alive "$SUP" && echo yes)"
kill "$SUP"; wait "$SUP" 2>/dev/null; SUP=

# stop hook names the supervisor when none runs: the relay's Stop hook leads its block with the one supervisor command,
# and still names each missing watcher.
git -C "$T/p" -c user.name=t -c user.email=t commit -q --allow-empty -m i; git -C "$T/p" worktree add -q "$T/ws/Chief-of-Staff" -b cos
R=$(echo '{}' | env HOME="$T/home" CLAUDE_PROJECT_DIR="$T/ws/Chief-of-Staff" ORCA_TERMINAL_HANDLE=term_relay COMMANDECK_REVIEWER= bash "$REAL/hooks/cos-inbox-waiter-stop.sh" 2>/dev/null | jq -r .reason)
check "stop hook names the supervisor when none runs" "1 1" \
  "$(case $R in "Arm the supervisor once instead of each watcher: bash "*/scripts/cos-supervise.sh*) echo 1 ;; *) echo 0 ;; esac) $(grep -c 'The decisions watcher is not running' <<<"$R")"

# A watcher prints its find before its seen or told mark: killed at the mark, the find is in its wake file, so the
# supervisor publishes it at the next start; printed after the mark, the record is marked and never told. The real
# watcher runs once with its mark a FIFO: it blocks at that write as if killed there.
mkdir -p "$T/uws"; git init -q "$T/uws/unit-x"; git -C "$T/uws/unit-x" -c user.name=t -c user.email=t commit -q --allow-empty -m i
echo '{"limit": {"usedPct": 95}, "alerts": [{"id": "limit-claude-1791717824", "severity": "crit", "project": null}]}' > "$T/state/data.js"
killed_at() {
  local m=$KEY.$2; rm -f "$m" "$KEY.cos-watch-$1-wake-"*; mkfifo "$m"
  timeout 5 bash -c ': > "$1"' _ "$m" &
  (cd "$T/p" && exec "${E[@]}" COMMANDECK_WORKSPACES="$T/uws" COMMANDECK_WATCH_ONCE=1 timeout 8 bash "$REAL/scripts/cos-watch-$1.sh") >/dev/null 2>&1 &
  waitfor 3 bash -c 'for f in "$1"-wake-*; do [ -s "$f" ] && exit 0; done; exit 1' _ "$KEY.cos-watch-$1"
  cat "$KEY.cos-watch-$1-wake-"* 2>/dev/null | head -1 | cut -c1-60
  timeout 5 cat "$m" >/dev/null 2>&1; rm -f "$m"
}
check "alert killed at its seen mark is still in its wake file" '{"id": "limit-claude-1791717824", "severity": "crit", "proje' "$(killed_at alerts alerts-seen)"
check "limit line killed at its told mark is still in its wake file" "7-day limit at 95% (threshold 90%)" "$(killed_at limit limit-told)"
check "idle unit killed at its seen mark is still in its wake file" "IDLE unit-x: last commit" "$(killed_at units units-idle-seen | cut -c1-24)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

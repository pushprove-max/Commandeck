#!/usr/bin/env bash
# covers: scripts/dashboard.sh scripts/dashboard_alerts.jq scripts/dashboard_limit.py scripts/cos-watch-alerts.sh
# dashboard-main-events.test.sh -- the mainEvents group (issues 300, 292) and the alerts built on it: main compacting
# before it restarted, and a checkpoint whose carry-over the hook could not heal. Both end at main's next restart.
# A carry the hook made itself (the "carried automatically" line) wakes nobody; one it could not carry wakes the relay
# once. The fixture is dashboard-built.test.sh's.
set -uo pipefail
. "$(dirname "$0")/fixtures/dashboard-built-setup.sh"
NOW=$(date +%s); lt() { date -d "@$1" +%FT%T; }; iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
seatf() { echo "$HOME/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$1")"; }
CPD=$HOME/.claude/checkpoints; PD=$(seatf "$MAIN"); mkdir -p "$CPD" "$PD"
# m1 compacted an hour ago; m1's carry was healed by the hook, m2's check failed and was not carried, m3's copy failed,
# m5 is ten seconds old (the restart helper has not taken it yet), zz is another project's (no transcript here).
for s in m1 m2 m3 m5; do echo '{"type":"user"}' > "$PD/$s.jsonl"; done
jq -cn --arg t "$(iso $((NOW - 3600)))" '{type:"system",subtype:"compact_boundary",sessionId:"m1xxxxxxxx",timestamp:$t,compactMetadata:{trigger:"auto",preTokens:170000}}' >> "$PD/m1.jsonl"
printf '%s\n' \
  "$(lt $((NOW - 7300))) stop-hook: carry-over check failed for $CPD/m1.md against $CPD/old.md: 2 items" \
  "$(lt $((NOW - 7299))) stop-hook: 2 items carried automatically into the checkpoint $CPD/m1.md" \
  "$(lt $((NOW - 3000))) stop-hook: carry-over check failed for $CPD/m2.md against $CPD/old.md: 1 items" \
  "$(lt $((NOW - 1800))) stop-hook: could not copy 3 missing items into $CPD/m3.md; main is not restarted" \
  "$(lt $((NOW - 10))) stop-hook: carry-over check failed for $CPD/m5.md against $CPD/old.md: 1 items" \
  "$(lt $((NOW - 900))) stop-hook: could not copy 1 missing items into $CPD/zz.md; main is not restarted" > "$CPD/clear-hook.log"
collect() { rm -rf "$T/out3"; mkdir -p "$T/out3"
  env -u COMMANDECK_SCRATCH -u CODEX_HOME PATH="$BIN:$PATH" COMMANDECK_WORKSPACES="$WS" COMMANDECK_DASHBOARD_DIR="$T/out3" COMMANDECK_MAIN="$MAIN" \
    DASH_NOW="$(date +%s)" bash "$SOURCE/scripts/dashboard.sh" >"$T/out3.log" 2>&1
  sed 's/^window.DASH = //; s/;$//' "$T/out3/data.js"; }
# The machine's own host-* alerts (its live swap and load) are not this fixture's.
ids() { jq -c '[.alerts[].id | select(startswith("host-") | not) | sub("-[0-9]{9,}$"; "")] | sort' <<<"$1"; }
OUT=$(collect)
check "mainEvents: the compaction, the unhealed carries; not the healed one nor another project's" \
  '1 ["m2","m3","m5"]' "$(jq -r '.projects.demo.mainEvents | "\(.compactions | length) \([.carryFailed[].cp | split("/")[-1] | sub("\\.md$"; "")] | sort | tojson)"' <<<"$OUT")"
check "mainEvents.carried lists m1 with its 2 items and no restart" '[["m1.md",2,null]]' \
  "$(jq -c '[.projects.demo.mainEvents.carried[] | [(.cp | split("/")[-1]), .items, .restartedAt]]' <<<"$OUT")"
check "alerts: one for the compaction, one each for m2 and m3, and the rejected checkpoint m1 (carried 2 h ago, main never restarted); m5 not yet stranded raises none" \
  '["carry-failed-demo-m2","carry-failed-demo-m3","checkpoint-rejected-demo-m1","main-compact-demo-m1xxxxxx"]' "$(ids "$OUT")"
# The relay's watcher wakes on them: its wake text holds the two carry failures and not the healed one. Once the
# pane has told the owner (--seed marks every open id seen) the same alerts wake nothing.
watch() { (cd "$MAIN" && HOME=$HOME PATH="$BIN:$PATH" COMMANDECK_MAIN="$MAIN" COMMANDECK_SCRATCH="$T/scr" COMMANDECK_DASHBOARD_DIR="$T/out3" COMMANDECK_WATCH_ONCE=1 bash "$SOURCE/scripts/cos-watch-alerts.sh" "$@" 2>&1); }
WT=$(sed -n 's/.*whole text: //p' <<<"$(watch)")
check "the relay's watcher wakes for the two carry failures, naming neither m1 (healed) nor m5 (not yet stranded)" "2 0" \
  "$(grep -c '"id": "carry-failed-demo-m[23]-' "$WT") $(grep -c 'carry-failed-demo-m[15]-' "$WT")"
watch --seed >/dev/null
check "and wakes nothing for the same alerts once told" "" "$(watch)"
# Main restarts (a session of this project resumes from a checkpoint): the events before it have recovered.
echo "$CPD/m3.md" > "$CPD/m3.resumed-from"
OUT=$(collect)
check "a restart after them ends all four alerts" '[]' "$(ids "$OUT")"
check "and mainEvents names the restart" true "$(jq '.projects.demo.mainEvents.resumedAt != null' <<<"$OUT")"
# A carried checkpoint is rejected only while main stays unrestarted, and not yet stranded inside 120 s. Main's last
# restart is set before all of them, then after. The alert rule reads the clock at render (dashboard.sh), so the two ages keep a wide margin around the 120 s line.
for s in m6 m7; do echo '{"type":"user"}' > "$PD/$s.jsonl"; done
N2=$(date +%s)
printf '%s\n' "$(lt $((N2 - 300))) stop-hook: 1 items carried automatically into the checkpoint $CPD/m6.md" \
  "$(lt $((N2 - 30))) stop-hook: 1 items carried automatically into the checkpoint $CPD/m7.md" >> "$CPD/clear-hook.log"
touch -d "@$((NOW - 30000))" "$CPD/m3.resumed-from"
rejected() { jq -c '[.alerts[].id | select(startswith("checkpoint-rejected-")) | sub("-[0-9]{9,}$"; "")] | sort' <<<"$1"; }
OUT=$(collect)
check "a carried checkpoint with no restart for 5 min raises checkpoint-rejected; one 30 s old raises nothing" \
  '["checkpoint-rejected-demo-m1","checkpoint-rejected-demo-m6"]' "$(rejected "$OUT")"
touch "$CPD/m3.resumed-from"
check "a restart after the carry ends it" '[]' "$(rejected "$(collect)")"

# Issue 331: main's card carries the wakes of the last hour and the ones that failed, by result; older ones are not counted.
WLJ=$(env -u COMMANDECK_SCRATCH COMMANDECK_MAIN="$MAIN" bash -c '. "$0/scripts/paths.sh" && printf %s "$PP_SCRATCH"' "$SOURCE")/wake-log.jsonl
mkdir -p "${WLJ%/*}"
wk() { jq -nc --arg at "$(iso $1)" --arg r "$2" '{at: $at, from: "main-watch", to: "term_main", reason: "wake", result: $r, error: ""}' >> "$WLJ"; }
: > "$WLJ"; wk $((NOW - 7200)) refused; wk $((NOW - 3000)) sent; wk $((NOW - 2000)) turn_started; wk $((NOW - 1000)) no_pane; wk $((NOW - 600)) refused; wk $((NOW - 100)) no_pane
check "main's wakes: the hour's count, and its failures by result" '{"hour":5,"failed":{"no_pane":2,"refused":1}}' \
  "$(jq -c '.projects.demo.seats.main.wakes' <<<"$(collect)")"
rm -f "$WLJ"
check "with no wake log it counts none" '{"hour":0,"failed":{}}' "$(jq -c '.projects.demo.seats.main.wakes' <<<"$(collect)")"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

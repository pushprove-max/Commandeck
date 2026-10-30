#!/usr/bin/env bash
# covers: scripts/dashboard.sh scripts/paths.sh
# dashboard-live.test.sh -- issue 466: the live follower turns a line of the unit event stream into the unit's row in
# live.json within 5 s, the fast lane (--units) waits for no cost read, and the follower survives a replaced stream
# and an unsafe unit name. The fixture is dashboard-built-setup.sh's, with an orca-ide that lists no worktrees.
set -uo pipefail
. "$(dirname "$0")/fixtures/dashboard-built-setup.sh"
printf '#!/usr/bin/env bash\ncase "$*" in *"worktree ps"*) echo %s ;; *) exit 1 ;; esac\n' "'{\"result\":{\"worktrees\":[]}}'" > "$BIN/orca-ide"
# A cost read that hangs: the fast lane must never call it.
REALPY=$(command -v python3)
printf '#!/usr/bin/env bash\ncase "$*" in *dashboard_limit.py*) sleep 60 ;; esac\nexec %s "$@"\n' "$REALPY" > "$BIN/python3"
chmod +x "$BIN/orca-ide" "$BIN/python3"
for u in u1 u2; do mkdir -p "$WS/$u" && touch "$WS/$u/.git"; done
LIVE=$T/out/live.json
run() { env -u COMMANDECK_SCRATCH -u COMMANDECK_HOOK_FIRE_LOG -u CODEX_HOME PATH="$BIN:$PATH" COMMANDECK_WORKSPACES="$WS" \
  COMMANDECK_DASHBOARD_DIR="$T/out" COMMANDECK_MAIN="$MAIN" bash "$@"; }
SC=$(run -c ". '$SOURCE/scripts/paths.sh'; echo \$PP_SCRATCH"); EV=$SC/unit-events.jsonl; mkdir -p "$SC" "$T/out"
emit() { run -c ". '$SOURCE/scripts/paths.sh'; pp_unit_event '$1' seat-launch"; }
# row <unit> -- true once live.json holds the unit's row; waits at most 5 s.
row() { local i; for i in $(seq 1 25); do jq -e --arg u "$1" '.rows[$u].row.unit == $u' "$LIVE" >/dev/null 2>&1 && { echo true; return; }; sleep 0.2; done; echo false; }
FPID=
follow() { run "$SOURCE/scripts/dashboard.sh" --follow >"$T/follow.out" 2>"$T/follow.err" & FPID=$!; sleep 1; }
unfollow() { kill "$FPID" 2>/dev/null; wait "$FPID" 2>/dev/null; rm -f "$LIVE"; }

follow
emit u1
check "a stage change is live in 5 s (issue 466)" true "$(row u1)"
check "the live row carries its stream mark and time" true "$(jq -e '.rows.u1 | (.seen.gen | type) == "number" and (.sampledAt | type) == "string" and .row.seen == .seen' "$LIVE" >/dev/null 2>&1 && echo true || echo false)"
unfollow

# The fast lane, alone, with the cost read hung: it answers in 5 s all the same, and writes no stage record.
OUTF=$(run -c "exec timeout 5 bash '$SOURCE/scripts/dashboard.sh' --units u1" 2>"$T/units.err"); RC=$?
check "the fast lane skips a stuck cache (issue 466)" "0:true" "$RC:$(jq -e '.unit == "u1" and .row.unit == "u1"' <<<"$OUTF" >/dev/null 2>&1 && echo true || echo false)"
check "the fast lane writes no stage record" false "$(ls "$T/out"/cache/*/unit-stages.json >/dev/null 2>&1 && echo true || echo false)"

# Follower cases last: each waits on real ticks.
echo '{"at":"2026-01-01T00:00:00Z","unit":"u1","event":"merge"}' > "$EV"
follow; emit u1; row u1 >/dev/null; rm -f "$LIVE"
# The stream is rewritten in place to the same size, as another unit's line, with dd's notrunc so it is never shorter:
# the inode and the size hold, so only the tail checksum shows it.
SZ=$(stat -c %s "$EV"); NEWLINE='{"at":"2026-01-01T00:00:00Z","unit":"u2","event":"merge"}'
{ printf '%s\n' "$NEWLINE"; printf '%*s\n' $((SZ - ${#NEWLINE} - 2)) ''; } | dd of="$EV" conv=notrunc 2>/dev/null
check "a replaced stream is read from 0 (issue 466)" true "$(row u2)"
unfollow

follow
printf '{"at":"2026-01-01T00:00:00Z","unit":"../x","event":"merge"}\n{"at":"2026-01-01T00:00:00Z","unit":"a b","event":"merge"}\n' >> "$EV"; emit u1
R=$(row u1)
check "an unsafe unit name starts no lane (issue 466)" "true:false:2" "$R:$([ -e "$T/out/.live/x.out" ] && echo true || echo false):$(grep -c 'not a safe unit name' "$T/follow.err")"
unfollow

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

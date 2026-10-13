#!/usr/bin/env bash
# timeout: 300 -- some 50 whole collections, one of them held 8 s by a gh that does not answer; 148s run alone on the Mac (2026-10-13)
# dashboard.test.sh -- the dashboard is the one page the owner reads instead of
# asking main, so it must never lie. What this pins: a source that could not be
# read is null with its reason (never a 0 that reads as a measurement); a slow
# read that fails keeps its last good copy, marked stale; a question the owner
# has open is listed and an answered one is not; the cache hit rate's inputs
# (cost per role) and the cache write share are measured; and the page is served on this machine
# only unless the owner asked for the LAN, on a port nothing else holds.
# (dashboard-registry.test.sh pins the project registry.)
set -uo pipefail
SOURCE=$(cd "$(dirname "$0")/../.." && pwd)
DASH=$SOURCE/scripts/dashboard.sh
DECIDE=$SOURCE/scripts/decision.sh
T=$(cd "$(mktemp -d)" && pwd -P)
LISTEN=''
trap '[ -z "$LISTEN" ] || kill "$LISTEN" 2>/dev/null; rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

export HOME=$T/home
MAIN=$T/demo OUT=$T/out BIN=$T/bin WS=$HOME/orca/workspaces/demo
mkdir -p "$HOME" "$BIN" "$OUT"
git init -q -b main "$MAIN"
git -C "$MAIN" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "feat: first"
git -C "$MAIN" worktree add -q "$WS/u1" -b work/u1
git -C "$MAIN" worktree add -q "$WS/u2" -b work/u2

# Stubs. ORCA_FAIL makes every Orca read fail; python3 records an http.server
# launch instead of serving, and is the real one for everything else.
cat > "$BIN/orca-ide" <<EOF
#!/usr/bin/env bash
[ ! -e "$T/orca-fail" ] || exit 1
case "\$*" in
  "worktree ps --json") cat "$T/orca.json" ;;
  "terminal list --json") echo '{"result":{"terminals":[]}}' ;;
  *) exit 1 ;;
esac
EOF
REAL_PY=$(command -v python3)
cat > "$BIN/python3" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == */dashboard_serve.py ]]; then shift; echo "\$*" >> "$T/served"; exec sleep 600; fi
exec "$REAL_PY" "\$@"
EOF
cat > "$BIN/systemctl" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$T/systemctl"
EOF
printf '#!/usr/bin/env bash\nexit 1\n' > "$BIN/pgrep"
# gh is never the real one: it prints $T/gh.json, or fails, or does not answer.
cat > "$BIN/gh" <<EOF
#!/usr/bin/env bash
printf '%s|%s|%s\n' "\$PWD" "\${GH_REPO:-}\${GH_HOST:-}" "\$*" >> "$T/gh.calls"
[ ! -e "$T/gh-slow" ] || sleep 20
[ ! -e "$T/gh-exit" ] || { echo '<b>gh: token ghp_notreal</b>' >&2; exit "\$(cat "$T/gh-exit")"; }
cat "$T/gh.json"
EOF
chmod +x "$BIN"/*
jq -cn --arg a "$WS/u1" '{result: {worktrees: [{path: $a, agents: [{agentType: "claude", state: "working"}]}]}}' > "$T/orca.json"

# COMMANDECK_MAIN names the fixture throughout: without it the collector would read the project the test is run from.
# dash [VAR=value]... [--flag] -- the collector, under the fixture's environment.
DENV=(env -u COMMANDECK_WORKSPACES -u COMMANDECK_SCRATCH -u COMMANDECK_HOOK_FIRE_LOG -u CODEX_HOME -u COMMANDECK_DASHBOARD_NAME
  -u COMMANDECK_DASHBOARD_BIND -u COMMANDECK_DASHBOARD_PORT
  PATH="$BIN:$PATH" COMMANDECK_HOST_OS=Linux COMMANDECK_DASHBOARD_DIR="$OUT" COMMANDECK_MAIN="$MAIN")
dash() { local -a e=(); while [[ ${1:-} == *=* ]]; do e+=("$1"); shift; done; "${DENV[@]}" "${e[@]}" bash "$DASH" "$@"; }
collect() { dash "$@" >>"$T/collect.out" 2>&1; }
j() { sed -e '1s/^window\.DASH = //' -e '$s/;$//' "$OUT/data.js" | jq -c "$1" 2>&1; }
P=.projects.demo

# --- nothing measured yet: every unread source is null with its reason, never 0 ---
touch "$T/orca-fail"
collect; check "a collect with nothing to read still publishes" 0 $?
check "no seat ledger: cost is null, not an empty table" 'null' "$(j "$P.costPerRole")"
check "no decisions ledger: null, not an empty list" 'null' "$(j "$P.needsOwner.decisions")"
check "no upstream: unpushed is null, not 0" 'null' "$(j "$P.mainChain.unpushed")"
check "Orca unread: a unit's panes are null, not none" '[null,null]' "$(j "[$P.units.inFlight[].agents]")"
check "Orca unread: the Chief of Staff's inbox is null" 'null' "$(j "$P.chiefOfStaff")"
check "no login and no transcripts: the limit's figures are null" '[null,null,null,null]' \
  "$(j '[.limit | .usedPct, .requests, .cost.week, .cacheWritePct24h]')"
check "each unread source is not measured and says why" 'true' \
  "$(j "[$P.sources | .[\"seat-events\"], .decisions, .orca, .[\"chief-of-staff\"]] + [.sources[\"claude-usage\"], .sources[\"claude-logs\"]]
       | all(.status == \"not-measured\" and (.error | type) == \"string\" and .sampledAt == null)")"
check "a read that worked is fresh" '["fresh","fresh"]' "$(j "[$P.sources[\"git-main\"].status, $P.sources.worktrees.status]")"
check "an unmeasured input makes the alerts record name it" 'true' \
  "$(j '.sources.alerts | .status == "not-measured" and (.error | test("7-day limit"))')"
check "the snapshot names no title unless the owner set one" 'null' "$(j .name)"

# --- the sources, once there is something to read ---
rm -f "$T/orca-fail"
mkdir -p "$MAIN/.claude/metrics" "$WS/u1/.claude"
now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$MAIN/.claude/metrics/seat-events.jsonl" <<EOF
{"event":"worker_done","unit":"u1","role":"builder","completedAt":"$now_iso","tokens":{"input":100,"cachedInput":96,"output":30}}
{"event":"worker_done","unit":"u1","role":"builder","completedAt":"$now_iso","tokens":null,"tokensReason":"no log"}
EOF
# A subagent run that went on after it was first recorded has two rows; the later one is the whole run.
cat > "$MAIN/.claude/metrics/subagent-usage.jsonl" <<EOF
{"agentId":"a1","agentType":"Explore","finishedAt":"$now_iso","tokens":{"input":10,"cachedInput":5,"output":1}}
{"agentId":"a1","agentType":"Explore","finishedAt":"$now_iso","tokens":{"input":30,"cachedInput":15,"output":3}}
EOF
: > "$MAIN/.claude/metrics/decisions.jsonl"
dec() { COMMANDECK_MAIN="$MAIN" COMMANDECK_RULING_LOG="$T/rulings.jsonl" bash "$DECIDE" "$@" >>"$T/collect.out" 2>&1; }
dec add d-open "Ship on Friday?" "wait a week" u1; check "the ledger takes a question" 0 $?
dec add d-done "Rename the flag?" "keep it" u1; dec answer d-done "keep it"
git -C "$MAIN" update-ref refs/remotes/origin/main HEAD
git -C "$MAIN" config remote.origin.url "$T/none"; git -C "$MAIN" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
git -C "$MAIN" config branch.main.remote origin; git -C "$MAIN" config branch.main.merge refs/heads/main
git -C "$MAIN" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "feat: second"
# u1 is a Builder two tool calls into its first Codex pass; u2 has no pane.
echo '{"env":{"COMMANDECK_BUILDER":"1"}}' > "$WS/u1/.claude/settings.local.json"
printf '{"ts":"%s","event":"codex-start","pass":"adversarial","round":1}\n' "$now_iso" > "$WS/u1/.claude/builder-events.jsonl"
echo untracked > "$WS/u2/new-file"
# What the Builds panel reads of u1: its session record (the model it really
# runs), its brief and main's rulings (the issues), its evidence file (the ones
# built) and its newest round report (the findings, and the commit it read).
SLOG=$HOME/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$WS/u1"); mkdir -p "$SLOG" "$WS/u1/.claude/briefs" "$MAIN/.claude/briefs"
printf '{"type":"assistant","timestamp":"2026-10-01T00:00:00.000Z","effort":"medium","advisorModel":"claude-fable-5-1","message":{"model":"claude-opus-5-5"}}\n' > "$SLOG/s.jsonl"
printf '# u1\n\n## The issues\n\n1. #11: first\n2. #12: second\n   it only mentions #99\n\n## Other\n\n#98\n' > "$WS/u1/.claude/briefs/u1.md"
printf '1. #13: added by main\n' > "$MAIN/.claude/briefs/u1-main-rulings.md"
# Real evidence files head a section "Item N" with no issue number: Item 2 is the brief's second numbered
# item (#12), and no item 7 exists. A heading with nothing under it is a section still to be written, not a
# built issue: Item 1 of main's rulings (#13) and its sub-heading are such headings here.
printf '# u1 evidence for #11 and #12\n\n## #11 first\n\nBuilt.\n\n## Item 2 -- second\n\n### Today\n\nBuilt.\n\n## Item 1\n\n### #13\n\n## Item 7 -- no such item\n\nNothing.\n' > "$WS/u1/.claude/briefs/u1-evidence.md"
printf 'Reviewed: %s\n\n- [P2] one\n- [P2] two\n* [P3] three\nProse names a P1.\nVERDICT: NO-GO\n' "$(git -C "$WS/u1" rev-parse HEAD)" > "$WS/u1/.claude/briefs/u1-r1-reports.md"
# The limit: a quota reading inside the 5-minute TTL stands in for the network
# read, and one request an hour ago with 1000 fresh, 5000 written and 4000 read
# input tokens is a 50% write share.
mkdir -p "$OUT/cache" "$HOME/.claude/projects/p"
printf '{"five_hour":{"utilization":15.0,"resets_at":"%s"},"seven_day":{"utilization":44.0,"resets_at":"%s"}}' \
  "$(date -u -d '+2 hours' +%Y-%m-%dT%H:%M:%S+00:00)" "$(date -u -d '+3 days' +%Y-%m-%dT%H:%M:%S+00:00)" > "$OUT/cache/claude-usage"
touch -d '-3 minutes' "$OUT/cache/claude-usage"
printf '{"type":"assistant","requestId":"r1","timestamp":"%s","message":{"model":"claude-opus-5-5","usage":%s}}\n' \
  "$(date -u -d '-1 hours' +%Y-%m-%dT%H:%M:%S.000Z)" \
  '{"input_tokens":1000,"cache_creation":{"ephemeral_5m_input_tokens":2000,"ephemeral_1h_input_tokens":3000},"cache_read_input_tokens":4000,"output_tokens":10}' \
  > "$HOME/.claude/projects/p/s1.jsonl"
# The same usage again, just now, from a session run in u1's worktree: the one request that is this project's day.
printf '{"type":"assistant","requestId":"r2","cwd":"%s","timestamp":"%s","message":{"model":"claude-opus-5-5","usage":%s}}\n' "$WS/u1" \
  "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" \
  '{"input_tokens":1000,"cache_creation":{"ephemeral_5m_input_tokens":2000,"ephemeral_1h_input_tokens":3000},"cache_read_input_tokens":4000,"output_tokens":10}' \
  > "$HOME/.claude/projects/p/s2.jsonl"
collect COMMANDECK_DASHBOARD_NAME="Demo board"; check "a collect with every source succeeds" 0 $?
check "a subagent run recorded twice is counted once, by its last row" '[{"agentType":"Explore","runs":1,"unmeasuredRuns":0,"input":30,"cachedInput":15,"output":3}]' \
  "$(j "[$P | .. | objects | select(has(\"subagents\")) | .subagents][0]")"
check "cost per role (the cache hit tile's inputs) counts every seat and names the unmeasured one" '[{"role":"builder","seats":2,"unmeasuredSeats":1,"input":100,"cachedInput":96,"output":30}]' "$(j "$P.costPerRole")"
check "the open question is listed with its default; the answered one is not" '[["d-open","wait a week"]]' "$(j "[$P.needsOwner.decisions[] | [.id, .proposedDefault]]")"
check "one commit the upstream lacks" '1' "$(j "$P.mainChain.unpushed")"
check "the newest commit leads" '"feat: second"' "$(j "$P.mainChain.commits[0].subject")"
check "the Builder is drawn from its event log" '["u1","review",1,"claude:working",true]' \
  "$(j "$P.units.inFlight[] | select(.unit == \"u1\") | [.unit, .stage, .round, .agents, (.builder.steps | length > 0)]")"
check "a seat's model, effort and advisor come from its own session record" '{"model":"claude-opus-5-5","effort":"medium","advisor":"claude-fable-5-1","at":"2026-10-01T00:00:00.000Z"}' \
  "$(j "$P.units.inFlight[] | select(.unit == \"u1\") | .seat")"
check "a unit with no session record has no seat reading, never a guessed model" '[true,null]' "$(j "$P.units.inFlight[] | select(.unit == \"u2\") | [has(\"seat\"), .seat]")"
check "a build's issues are its brief's numbered work items plus the ones main's rulings add; a mention is not one" '[11,12,13]' \
  "$(j "$P.units.inFlight[] | select(.unit == \"u1\") | .builder.issues")"
check "built issues are the ones an evidence section with something under it is headed with, by number or as Item N; findings are the newest round's finding lines" '[[11,12],{"P0":0,"P1":0,"P2":2,"P3":1}]' \
  "$(j "$P.units.inFlight[] | select(.unit == \"u1\") | .builder | [.built, .findings]")"
# u1's settings file and event log are uncommitted outside the briefs folder, so the tree is not the one the pass read.
check "a Builder carries whether its worktree is still the tree its newest pass read" 'false' "$(j "$P.units.inFlight[] | select(.unit == \"u1\") | .builder.reviewedTree")"
check "a Builder carries when its log began, its review time and what it waits on" "[\"$now_iso\",true,[[\"codex\",\"adversarial\",1]]]" \
  "$(j "$P.units.inFlight[] | select(.unit == \"u1\") | .builder | [.startedAt, (.reviewSec >= 0 and .reviewSec < 120), [.waiting[] | [.kind, .what, .round]]]")"
check "a worktree with no pane has no stage, and its untracked file counts" '[null,"",1]' \
  "$(j "$P.units.inFlight[] | select(.unit == \"u2\") | [.stage, .agents, .dirty]")"
check "the limit reads the quota" 'true' "$(j '.limit.usedPct == 44 and .limit.fiveHour.usedPct == 15')"
check "the cache write share is writes over all input tokens" 'true' "$(j '.limit.cacheWritePct24h == 50')"
# The day's cost is a project's own: the session run in its worktree counts, the one that names no folder is nobody's.
check "the day's cost is kept per project, from the sessions run in its folders" '[["demo"],1,true]' \
  "$(j '.limit.today | [keys, .demo.requests, .demo.spentUsd > 0]')"
check "a write share over 5% alerts once, for the machine" '["cache-write"]' "$(j '[.alerts[].id | select(startswith("cache-write")) | sub("-[0-9]+$"; "")]')"
check "the owner's title is in the snapshot" '"Demo board"' "$(j .name)"

# --- a question waiting over an hour alerts under its project; a younger one does not ---
check "a question just asked raises no alert" '[]' "$(j '[.alerts[].id | select(startswith("question-"))]')"
old_iso=$(date -u -d '-2 hours' +%Y-%m-%dT%H:%M:%SZ)
jq -c --arg at "$old_iso" 'if .id == "d-open" then .askedAt = $at else . end' "$MAIN/.claude/metrics/decisions.jsonl" > "$T/dec.new" \
  && cp "$T/dec.new" "$MAIN/.claude/metrics/decisions.jsonl"
# An evidence file that is there and cannot be read says nothing about what is built: an empty list for
# it drew "0 of N issues recorded as built", a count nobody recorded.
chmod 000 "$WS/u1/.claude/briefs/u1-evidence.md"
collect
check "an evidence file that cannot be read is not a built count: false, neither null nor an empty list" 'false' "$(j "$P.units.inFlight[] | select(.unit == \"u1\") | .builder.built")"
chmod 600 "$WS/u1/.claude/briefs/u1-evidence.md"; : > "$WS/u1/.claude/briefs/u1-evidence.md"
check "a question two hours old alerts, named by project and id" '["question-demo-d-open"]' "$(j '[.alerts[].id | select(startswith("question-")) | sub("-[0-9]+$"; "")]')"

# --- a slow read that fails keeps its last good copy, marked stale, and backs off ---
touch -d '-10 minutes' "$OUT/cache/claude-usage"   # past the TTL, and with no login the read cannot be made
collect; check "a collect with a failed slow read still publishes" 0 $?
check "the same evidence file once readable, with nothing in it, is zero built" '[]' "$(j "$P.units.inFlight[] | select(.unit == \"u1\") | .builder.built")"
check "the last good reading stays on the page" 'true' "$(j '.limit.usedPct == 44')"
check "and is marked stale, with the reason" '["stale",true,true]' \
  "$(j '.sources["claude-usage"] | [.status, (.staleSince | type == "string"), (.error | test("last good copy"))]')"
check "the failed read left a retry time, so the next cycle does not repeat it" 'true' \
  "$([ -s "$OUT/cache/claude-usage.retry" ] && echo true || echo false)"

# --- a collect that cannot build keeps the last good page ---
cp "$OUT/data.js" "$T/good.js"
echo 'not json' > "$MAIN/.claude/metrics/seat-events.jsonl"
collect; check "a collect that cannot build fails" 1 $?
check "and leaves the last good data.js as it was" 0 "$(cmp -s "$OUT/data.js" "$T/good.js"; echo $?)"
check "and no half-built file behind" '' "$(ls -A "$OUT" | grep -E '^\.(run|data\.js)\.' || true)"
rm -f "$MAIN/.claude/metrics/seat-events.jsonl"

# --- install: this machine only by default, on a port nothing holds ---
"$REAL_PY" -c 'import socket, time
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1", 8791)); s.listen(); time.sleep(600)' 2>/dev/null &
LISTEN=$!
for _ in $(seq 50); do "$REAL_PY" -c 'import socket, sys; sys.exit(socket.socket().connect_ex(("127.0.0.1", 8791)))' 2>/dev/null && break; sleep 0.1; done
UNIT=$HOME/.config/systemd/user/commandeck-dashboard.service
inst=$(dash --install 2>&1); check "install succeeds" 0 $?
port=$(sed -n 's/^Environment="COMMANDECK_DASHBOARD_PORT=\([0-9]*\)"$/\1/p' "$UNIT" 2>/dev/null)
check "the job keeps the local-only bind" 1 "$(grep -c '^Environment="COMMANDECK_DASHBOARD_BIND=127.0.0.1"$' "$UNIT" 2>/dev/null)"
check "a port something already listens on is not chosen" 'true' "$([ -n "$port" ] && [ "$port" -gt 8791 ] && echo true || echo "false: [$port]")"
check "install names the address it serves" 1 "$(grep -c "http://127.0.0.1:$port/" <<<"$inst")"
check "the job names the project it was installed from" 1 "$(grep -c "^Environment=\"COMMANDECK_MAIN=$MAIN\"$" "$UNIT" 2>/dev/null)"
# Quoted: systemd splits an unquoted path with a space into two arguments.
check "the job runs this script's loop, its path quoted" 1 "$(grep -c "^ExecStart=\"[^\"]*\" \"$DASH\" --loop$" "$UNIT" 2>/dev/null)"
check "the view is copied beside data.js" 'app.css app.js index.html' "$(cd "$OUT" && ls app.css app.js index.html 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
check "the job is enabled under the plugin's own unit name" 1 "$(grep -c '^--user enable commandeck-dashboard.service$' "$T/systemctl" 2>/dev/null)"
# An install over a running job (an update) must put the new script and settings in force: enable alone leaves the old process.
check "and restarted, so a running job takes the new file" 1 "$(grep -c '^--user restart commandeck-dashboard.service$' "$T/systemctl" 2>/dev/null)"
# --status is what the doctor asks. On a Mac the job's label carries a prefix the
# service helper strips, so the name asked for must be the bare one.
printf '#!/usr/bin/env bash\n[ "$1" = list ] && cat %q 2>/dev/null\n' "$T/launchd" > "$BIN/launchctl"; chmod +x "$BIN/launchctl"
printf '412\t0\tcom.commandeck.dashboard\n-\t0\tcom.other-tool.dashboard\n' > "$T/launchd"
dash COMMANDECK_HOST_OS=Darwin --status >/dev/null 2>&1; check "a running Mac job reads as running" 0 $?
printf -- '-\t0\tcom.commandeck.dashboard\n412\t0\tcom.other-tool.dashboard\n' > "$T/launchd"
dash COMMANDECK_HOST_OS=Darwin --status >/dev/null 2>&1; check "a loaded job with no process, beside another tool's running one, reads as not running" 1 $?
dash COMMANDECK_DASHBOARD_BIND=0.0.0.0 COMMANDECK_DASHBOARD_PORT=9123 COMMANDECK_DASHBOARD_NAME="Demo board" --install >/dev/null 2>&1
check "the owner's bind, port and title are kept in the job" 3 \
  "$(grep -cE '^Environment="COMMANDECK_DASHBOARD_(BIND=0\.0\.0\.0|PORT=9123|NAME=Demo board)"$' "$UNIT" 2>/dev/null)"
dash --uninstall >/dev/null 2>&1
check "uninstall removes the job" 'false' "$([ -e "$UNIT" ] && echo true || echo false)"

# --- the loop serves the folder on the bind and port it was given ---
loop() { # <env>... -- one loop, stopped once it has started its server
  : > "$T/served"
  "${DENV[@]}" "$@" bash "$DASH" --loop >>"$T/collect.out" 2>&1 & local pid=$!
  for _ in $(seq 100); do [ -s "$T/served" ] && [ -s "$OUT/alive.js" ] && break; sleep 0.1; done
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
}
loop
check "with no knob the loop serves this machine only, on 8791" "8791 127.0.0.1 $OUT" "$(head -1 "$T/served")"
# The page loads layout.js before app.js, so a first start gives it an empty one; a saved one is kept.
check "a first start leaves an empty layout.js for the page" 'window.DASH_LAYOUT = null;' "$(cat "$OUT/layout.js" 2>/dev/null)"
echo 'window.DASH_LAYOUT = {"hidden": ["host"]};' > "$OUT/layout.js"
loop COMMANDECK_DASHBOARD_BIND=0.0.0.0 COMMANDECK_DASHBOARD_PORT=9123
check "the LAN bind is the owner's choice" "9123 0.0.0.0 $OUT" "$(head -1 "$T/served")"
check "a later start keeps the saved layout" 'window.DASH_LAYOUT = {"hidden": ["host"]};' "$(cat "$OUT/layout.js" 2>/dev/null)"
# An open page learns of new code from the heartbeat: it carries a checksum of the view files as installed.
dash --install >/dev/null 2>&1; dash --uninstall >/dev/null 2>&1; rm -f "$OUT/alive.js"; loop
check "the heartbeat carries the checksum of the installed view files" "\"$(cat "$OUT/index.html" "$OUT/app.css" "$OUT/app.js" | cksum | cut -d' ' -f1)\"" \
  "$(sed -e 's/^window\.DASH_ALIVE = //' -e 's/;$//' "$OUT/alive.js" | jq -c .view)"

# --- the day's cost: both providers since host-local midnight, split by the folder each session ran in ---
LIM=$SOURCE/scripts/dashboard_limit.py D=$T/day NOON=1791633600  # 12:00 UTC
mkdir -p "$D/claude/a" "$D/claude/b" "$D/codex" "$D/cache"
req() { # <id> <seconds before NOON> <model> [cwd]
  printf '{"type":"assistant","requestId":"%s",%s"timestamp":"%s","message":{"model":"%s","usage":{"input_tokens":1000,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0},"cache_read_input_tokens":0,"output_tokens":100}}}\n' \
    "$1" "${4:+\"cwd\":\"$4\",}" "$(date -u -d "@$((NOON - $2))" +%Y-%m-%dT%H:%M:%S.000Z)" "$3"
}
{ req a1 3600 claude-opus-5-5 /w/alpha; req a2 7200 claude-sonnet-5-5 /ws/alpha/u1; req a3 50000 claude-opus-5-5 /w/alpha; } > "$D/claude/a/s.jsonl"
{ req b1 3600 claude-opus-5-5 /w/beta; req x1 3600 claude-opus-5-5 /w/alpha-two; req x2 3600 claude-opus-5-5; } > "$D/claude/b/s.jsonl"
cdx() { # <response id> <seconds before NOON> <cwd>
  printf '{"timestamp":"%s","type":"session_meta","payload":{"cwd":"%s"}}\n{"timestamp":"%s","type":"turn_context","payload":{"model":"gpt-6.1-sol"}}\n' "$(date -u -d "@$((NOON - $2))" +%Y-%m-%dT%H:%M:%SZ)" "$3" "$(date -u -d "@$((NOON - $2))" +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"timestamp":"%s","type":"token_usage_record","payload":{"response_id":"%s","usage":{"input_tokens":1000,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":100}}}\n' "$(date -u -d "@$((NOON - $2))" +%Y-%m-%dT%H:%M:%SZ)" "$1"
}
cdx c1 1800 /w/alpha > "$D/codex/one.jsonl"; cdx c2 1800 /w/beta/sub > "$D/codex/two.jsonl"; cdx c3 50000 /w/alpha > "$D/codex/old.jsonl"
DAYP='{"alpha":["/w/alpha","/ws/alpha"],"beta":["/w/beta","/ws/beta"],"quiet":["/w/quiet","/ws/quiet"]}'
day() { TZ=${DAY_TZ:-UTC} "$REAL_PY" "$LIM" build none "$D/no-usage" "${DAY_NOW:-$NOON}" "$D/cache" "$D/claude" "${1:-$D/codex}" "$DAYP" | jq -c "$2"; }
check "a project's day is its own sessions since midnight: two Claude requests and one Codex pass, yesterday's left out" '[3,true,true]' \
  "$(day '' '.today.alpha | [.requests, .complete, .claudeUsd > 0 and .codexUsd > 0 and ((.spentUsd - .claudeUsd - .codexUsd) * 1e9 | round) == 0]')"
check "the other project's day holds only its own, a folder below its checkout included" '[2,true]' \
  "$(day '' '.today | [.beta.requests, .beta.claudeUsd > 0 and .beta.claudeUsd < .alpha.claudeUsd]')"
check "a folder whose name only starts like the project's, and a session that names none, are nobody's" '[3,2,0]' \
  "$(day '' '[.today[].requests]')"
check "a project with no session today spent nothing, measured" '[0,0]' "$(day '' '.today.quiet | [(.spentUsd | floor), .requests]')"
check "the day starts at midnight, not at Monday" '"2026-10-10T00:00:00Z"' "$(day '' '.today.alpha.windowStart')"
# A second read is the cache's: the working folder is kept there, or the split would be gone after one cycle.
check "the split holds on the next cycle, read from the cache" '[3,2,0]' "$(day '' '[.today[].requests]')"
check "with no Codex folder the day is Claude's alone and not called complete" '[2,false,null]' \
  "$(day "$D/none" '.today.alpha | [.requests, .complete, .codexUsd]')"
# A project whose folder came through empty, as "/", or not as text owns no session: as a root it would own every one.
check "an empty or root folder owns nothing" '[0,0]' "$(DAYP='{"e":["","/"],"n":[null,7]}' day '' '[.today[].requests]')"
# One checkout inside another: a session is the innermost project's alone, or its cost would show under both.
check "a session in a project nested in another is counted once, for the inner one" '[1,1]' \
  "$(DAYP='{"beta":["/w/beta"],"deep":["/w/beta/sub"]}' day '' '[.today.beta.requests, .today.deep.requests]')"
# The night the clocks go back the day is 25 hours long: a request 24 h 20 min ago is still today's.
mkdir -p "$D/long/a" && D2=$D && D=$D/long && mkdir -p "$D/cache" "$D/claude/a"
LONG=$(date -u -d '2026-11-02T04:30:00Z' +%s)  # 23:30 in New York, on the day that began 24.5 h earlier
NOON=$LONG req l1 $((24 * 3600 + 1200)) claude-opus-5-5 /w/alpha > "$D/claude/a/s.jsonl"; touch -d '2026-11-02T04:00:00Z' "$D/claude/a/s.jsonl"
check "a 25-hour day is read from its own midnight" '1' "$(DAY_TZ=America/New_York DAY_NOW=$LONG day "$D/none" '.today.alpha.requests')"
D=$D2

# A Builder's signals, from its event log alone (dashboard_builders.jq).
bld() { jq -sc --argjson now 1000000 "$@" -f "$(dirname "$DASH")/dashboard_builders.jq" | jq -c '[.signals[].kind]'; }
at() { date -u -d "@$((1000000 - $1))" +%Y-%m-%dT%H:%M:%SZ; }
row() { printf '{"ts":"%s","event":"%s","use":"u1","tool":"Bash","kind":"%s"%s}\n' "$(at "$1")" "$2" "$3" "${4:-}"; }
# One long model turn writes the session log and no event row: quiet is timed from the later of the two.
check "a log quiet for 400 s is a quiet Builder" '["quiet"]' "$({ row 400 tool-start shell; row 390 tool-end shell; } | bld)"
check "but not when its session log was written 100 s ago" '[]' "$({ row 400 tool-start shell; row 390 tool-end shell; } | bld --argjson sessionAt 999900)"
# A call a hook or the classifier denied has no end row of its own: its batch's end names it.
check "a call with no end row past its limit is stuck" '["stuck"]' "$(row 200 tool-start tool | bld)"
check "a denied call whose batch ended is not" '[]' "$({ row 200 tool-start tool; printf '{"ts":"%s","event":"batch-end","uses":["u1"]}\n' "$(at 190)"; } | bld)"
# A wait on a background test run states its own timeout.
check "a shell call 200 s old is past the shell limit" '["stuck"]' "$(row 200 tool-start shell | bld)"
check "but not inside the timeout the call itself states" '[]' "$(row 200 tool-start shell ',"timeoutSec":400' | bld)"
use() { printf '{"ts":"%s","event":"%s","use":"%s","tool":"Bash","kind":"shell"%s}\n' "$(at "$1")" "$2" "$3" "${4:-}"; }
# Several open calls are one signal, from the earliest: one each gave the same alert twice.
check "two open calls past their limit are one stuck signal, since the earliest" '[["stuck",999700]]' \
  "$({ use 300 tool-start a; use 290 tool-start b; } | jq -sc --argjson now 1000000 -f "$(dirname "$DASH")/dashboard_builders.jq" | jq -c '[.signals[] | [.kind, .since]]')"
# Only its own end row ends a call: parallel calls start one after another, so later activity proves nothing about it.
check "a call open past its limit is stuck whatever began and ended after it" '["stuck"]' "$({ use 400 tool-start a; use 5 tool-start b; use 3 tool-end b; } | bld)"
# A helper the pane stopped mid-call never logs that call's end, and the Builder worked on and read
# stuck for the rest of the build. A stopped helper's calls are over; a running helper's are not.
helper() { printf '{"ts":"%s","event":"subagent-%s","agent_id":"%s","type":"Explore"}\n' "$(at "$1")" "$2" "${3:-a1}"; }
theirs() { use "$1" tool-start h1 ',"agent":"a1"'; }
check "a call of a helper the pane stopped does not mark a working Builder stuck" '[]' "$({ helper 410 start; theirs 400; helper 390 stop; use 10 tool-start b; use 9 tool-end b; } | bld)"
check "with the helper stopped and nothing since, the Builder is quiet, not stuck" '["quiet"]' "$({ helper 410 start; theirs 400; helper 390 stop; } | bld)"
check "a call of a helper still running past its limit is stuck" '["stuck"]' "$({ helper 410 start; theirs 400; use 10 tool-start b; use 9 tool-end b; } | bld)"
check "another helper's stop ends nothing of this one's" '["stuck"]' "$({ helper 410 start; theirs 400; helper 390 stop a2; } | bld)"
check "the pane's own open call is ended by no helper's stop" '["stuck"]' "$({ use 400 tool-start a; helper 390 stop; } | bld)"

# An unknown unit list (no workspace folder, or one that cannot be listed)
# means no stage or Builder alert can fire: that is a missing input, not "No alerts".
al() { jq -nc -f "$(dirname "$DASH")/dashboard_alerts.jq" --argjson now 1000000 --arg s7 x --argjson hasSe false --slurpfile se /dev/null \
  --slurpfile parts <(echo "$1") --slurpfile srcs <(echo '{}') --argjson prev '{}' | jq -c '[.missing[] | select(test("units"))]'; }
check "an unknown unit list is a missing alert input" '["demo: units in flight"]' "$(al '{"projects":{"demo":{"units":{"inFlight":null}}}}')"
check "a known, empty unit list is not"                '[]' "$(al '{"projects":{"demo":{"units":{"inFlight":[]}}}}')"

# The port is probed on the address the job will serve: a port free on
# 127.0.0.1 can be held on ::1, and the server then never comes up.
kill "$LISTEN" 2>/dev/null; wait "$LISTEN" 2>/dev/null
"$REAL_PY" -c 'import socket, time
s = socket.socket(socket.AF_INET6); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("::1", 8791)); s.listen(); time.sleep(600)' 2>/dev/null &
LISTEN=$!
for _ in $(seq 50); do "$REAL_PY" -c 'import socket, sys; sys.exit(socket.socket(socket.AF_INET6).connect_ex(("::1", 8791)))' 2>/dev/null && break; sleep 0.1; done
check "the test's own listener holds ::1 8791 and 127.0.0.1 8791 is free" '0 1' "$("$REAL_PY" -c 'import socket
print(socket.socket(socket.AF_INET6).connect_ex(("::1", 8791)), int(socket.socket().connect_ex(("127.0.0.1", 8791)) != 0))')"
dash COMMANDECK_DASHBOARD_BIND=::1 --install >/dev/null 2>&1; check "install on ::1 succeeds" 0 $?
port=$(sed -n 's/^Environment="COMMANDECK_DASHBOARD_PORT=\([0-9]*\)"$/\1/p' "$UNIT" 2>/dev/null)
check "a port held on the address it will serve is not chosen" 'true' "$([ -n "$port" ] && [ "$port" -gt 8791 ] && echo true || echo "false: [$port]")"
dash --uninstall >/dev/null 2>&1

# --- finished builds: the lines the project's own merge appended, and nothing else ---
# (merge-unit-local.test.sh runs the collector on a record a real merge wrote; here the record is every wrong shape.)
B=$HOME/.commandeck/builds
rm -rf "$B"; collect
check "no finished-builds record: not measured, never an empty list, and the snapshot still publishes" 'null' "$(j "$P.units.finishedBuilds")"
mkdir -p "$B/demo.jsonl"; collect
check "a folder where the record should be: not measured" 'null' "$(j "$P.units.finishedBuilds")"
rmdir "$B/demo.jsonl"
mkdir -p "$B"; : > "$B/demo.jsonl"; collect
check "an empty record: none finished" '[]' "$(j "$P.units.finishedBuilds")"
# A line is this checkout's when it names its real path; a build is a unit and a 40-character commit.
REALMAIN=$(cd "$MAIN" && pwd -P); A=$(printf 'a%.0s' $(seq 1 40)) BB=$(printf 'b%.0s' $(seq 1 40)) LONG=$(printf 'u%.0s' $(seq 1 90))
line() { jq -cn --arg main "${MAIN_OF:-$REALMAIN}" --arg unit "$1" --arg at "$2" --arg sha "$3" --argjson open "${4:-null}" '{$main, $unit, how: "merged", $at, $sha, $open}'; }
{ line one 2026-10-01T00:00:00Z "$A" '{"P1":0,"P2":1,"P3":0}'
  echo 'not json {'; echo '7'; echo '[]'; echo "{\"main\":\"$REALMAIN\",\"unit\":\"../two\",\"sha\":\"$A\"}"; echo "{\"main\":\"$REALMAIN\",\"unit\":5,\"sha\":\"$A\"}"; printf '\377\376\n'
  line no-commit 2026-10-02T00:00:00Z abc; line "" 2026-10-02T00:00:00Z "$A"
  MAIN_OF=/elsewhere/demo line twin 2026-10-05T00:00:00Z "$A"; echo "{\"unit\":\"no-main\",\"sha\":\"$A\"}"
  echo "{\"main\":\"$REALMAIN\",\"unit\":\"three\",\"how\":[\"x\"],\"at\":9,\"sha\":\"$BB\",\"open\":{\"P1\":\"<b>\",\"P2\":2,\"P9\":4}}"
  line "$LONG" 2026-10-02T00:00:00Z "$BB"
  line one 2026-10-03T00:00:00Z "$BB" '{"P1":0,"P2":0,"P3":0}'
  printf '{"main":"%s","unit":"torn","how":"mer' "$REALMAIN"; } > "$B/demo.jsonl"
line theirs 2026-10-04T00:00:00Z "$A" '{"P1":3,"P2":0,"P3":0}' > "$B/other.jsonl"
collect
check "a record with torn, foreign and wrong-shaped lines lists the builds it can read, the later line of a unit winning, newest first" \
  "[[\"one\",\"merged\",\"2026-10-03T00:00:00Z\",\"$BB\",{\"P1\":0,\"P2\":0,\"P3\":0}],[\"$LONG\",\"merged\",\"2026-10-02T00:00:00Z\",\"$BB\",null],[\"three\",null,null,\"$BB\",{\"P1\":null,\"P2\":2,\"P3\":null}]]" \
  "$(j "[$P.units.finishedBuilds[] | [.unit, .how, .at, .sha, .open]]")"
check "another project's record is never read into this one, nor a line another checkout of the same folder name wrote, nor one naming no checkout" '[]' \
  "$(j "[$P.units.finishedBuilds[].unit | select(. == \"theirs\" or . == \"twin\" or . == \"no-main\" or . == \"no-commit\")]")"
for i in $(seq 1 130); do printf '{"main":"%s","unit":"u%03d","how":"merged","at":"2026-09-01T00:%02d:%02dZ","sha":"%s","open":null}\n' "$REALMAIN" "$i" $((i / 60)) $((i % 60)) "$A"; done > "$B/demo.jsonl"
collect
check "the list is the newest 100" '[100,"u130","u031"]' "$(j "$P.units.finishedBuilds | [length, .[0].unit, .[-1].unit]")"
rm -rf "$B"

# --- the needs panel is named after whoever runs the plugin: git's user.name here, else the account ---
collect
check "no git user.name: the account's name" "\"$(id -un)\"" "$(j "$P.needsOwner.name")"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/id"; chmod +x "$BIN/id"; collect
check "no git user.name and no account name: no name, and the snapshot still publishes" 'null' "$(j "$P.needsOwner.name")"
rm -f "$BIN/id"
git -C "$MAIN" config user.name 'Ada Lovelace'; collect
check "git's user.name for this checkout is the name" '"Ada Lovelace"' "$(j "$P.needsOwner.name")"
git -C "$MAIN" config user.name $'  <img src=x onerror="a()">&\'"\nsecond line\t</script><script>alert(1)//  '; collect
check "markup, quotes and a newline in the name: one line of text, and data.js still parses" \
  '"<img src=x onerror=\"a()\">&'"'"'\" second line </script><script>alert(1)//"' "$(j "$P.needsOwner.name")"
git -C "$MAIN" config user.name "$(printf 'n%.0s' $(seq 1 500))"; collect
check "a 500-character name is cut to 80" 80 "$(j "$P.needsOwner.name | length")"
git -C "$MAIN" config user.name '   '; collect
check "a blank user.name falls back to the account" "\"$(id -un)\"" "$(j "$P.needsOwner.name")"
git -C "$MAIN" config --unset user.name

# --- the project's open GitHub issues labelled P1: gh's count, or null with the reason, never 0 ---
G="[$P.githubP1, $P.sources[\"github-p1\"].status]" GE="$P.sources[\"github-p1\"].error"
collect
check "gh has no answer: the count is null and not measured, never 0" '[null,"not-measured"]' "$(j "$G")"
echo '[{"labels":[{"name":"P1"}]},{"labels":[{"name":"bug"},{"name":"P1"}]},{"labels":[{"name":"p1"}]},{"labels":[{"name":"P10"}]},{"labels":[]}]' > "$T/gh.json"
: > "$T/gh.calls"; collect GH_REPO=someone/else GH_HOST=example.test
check "the open issues with the exact label P1 are counted, and no other label" '[2,"fresh"]' "$(j "$G")"
check "gh is asked once, in the project's own checkout, with no repository named for it" \
  "$MAIN||issue list --state open --label P1 --limit 1000 --json labels" "$(cat "$T/gh.calls")"
echo '[]' > "$T/gh.json"; collect
check "no open P1 issue is a measured 0" '[0,"fresh"]' "$(j "$G")"
for bad in '{"message":"Bad credentials"}' '3' '"3"' '[null]' '[{"labels":"P1"}]' '[{"labels":["P1"]}]' '[{"labels":[{"name":"P1"}]}' ''; do
  printf '%s' "$bad" > "$T/gh.json"; collect
  check "gh answers [$bad]: not a list of issues, so null and not 0" '[null,"not-measured"]' "$(j "$G")"
done
echo '[{"labels":[{"name":"P1"}]}]' > "$T/gh.json"
for rc in 1 4 127; do
  echo "$rc" > "$T/gh-exit"; collect
  check "gh exits $rc: null and not measured, whatever it printed" '[null,"not-measured"]' "$(j "$G")"
done
check "the reason is the collector's own words: nothing gh printed reaches the snapshot" '"gh issue list failed (exit 127)"' "$(j "$GE")"
check "and nothing gh printed is anywhere in data.js" 0 "$(grep -c 'ghp_notreal' "$OUT/data.js")"
rm -f "$T/gh-exit"; touch "$T/gh-slow"; began=$SECONDS
collect; check "a gh that does not answer does not stop the publication" 0 $?
check "it is cut off in seconds, and the 20 s it would take is not waited for" 1 "$([ $((SECONDS - began)) -lt 15 ] && echo 1 || echo 0)"
check "the count is null and says why; the rest of the project is there" '[null,"gh gave no answer in 8 s",true]' \
  "$(j "[$P.githubP1, $GE, ($P.sources[\"git-main\"].status == \"fresh\")]")"
rm -f "$T/gh-slow" "$T/gh.json"

[ "$FAIL" = 0 ] || sed 's/^/  collect: /' "$T/collect.out" | tail -20
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

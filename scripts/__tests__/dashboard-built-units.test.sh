#!/usr/bin/env bash
# covers: scripts/dashboard.sh scripts/dashboard_builders.jq scripts/builder-codex-pass.sh
# dashboard-built-units.test.sh -- issue 292: the Units board's rows and fields beyond the in-flight Builder cards:
# the relay's inbox, a unit's launch roster, parked units, the finished builds with no cap, merged since the last push
# and the last merge. The fixture is dashboard-built.test.sh's (fixtures/dashboard-built-setup.sh).
set -uo pipefail
. "$(dirname "$0")/fixtures/dashboard-built-setup.sh"
NOW=$(date +%s); iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
part() { jq -c "first(.[]) | $1" "$T/out/run/project.json" 2>&1; }

# Green pin: the relay's inbox. The only other fixture returns an empty inbox, so an unread count that read 0 with
# mail waiting would have passed.
printf '#!/usr/bin/env bash\ncase "$*" in "terminal list"*) echo %q ;; "orchestration inbox"*) echo %q ;; *) exit 1 ;; esac\n' \
  "$(jq -cn --arg p "$WS/Chief-of-Staff" '{result: {terminals: [{handle: "h-cos", worktreePath: $p}]}}')" \
  "$(jq -cn --arg a "$(iso $((NOW - 600)))" --arg b "$(iso $((NOW - 60)))" '{result: {messages: [{read: 0, created_at: $a}, {read: 0, created_at: $b}, {read: 1, created_at: $a}]}}')" > "$BIN/orca-ide"
DNOW=$NOW dash
check "a fake inbox with two unread messages gives unread 2 and the older one's age" '[2,600,false]' \
  "$(part '.chiefOfStaff | [.unread, .oldestUnreadAgeSec, .incomplete]')"

# Build: the in-flight row says it is a worktree; a reader tells a parked unit (worktree false, below) by it.
mkdir -p "$WS/u" && touch "$WS/u/.git"
printf '#!/usr/bin/env bash\nexit 1\n' > "$BIN/orca-ide"
DNOW=$NOW dash
check "an ordinary worktree u publishes worktree true" '[true]' \
  "$(part '[.units.inFlight[]? | select(.unit == "u") | .worktree]')"

# Finished builds have no cap: 151 merge lines are 151 builds, the main-chain card names the newest merge, and a
# build whose merge commit main has and the upstream lacks is merged since the last push.
git -C "$MAIN" init -q --bare "$T/remote.git"; git -C "$MAIN" remote add origin "$T/remote.git"
git -C "$MAIN" push -q -u origin main 2>/dev/null
mc() { git -C "$MAIN" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$1"; git -C "$MAIN" rev-parse HEAD; }
S_OLD=$(git -C "$MAIN" rev-parse HEAD); S1=$(mc "merge one"); S2=$(mc "merge two")
mkdir -p "$HOME/.commandeck/builds"
{ jq -cn --arg m "$(cd "$MAIN" && pwd -P)" --arg s "$S_OLD" '{main: $m, unit: "old-unit", sha: $s, at: "2026-01-01T00:00:00Z"}'
  jq -cn --arg m "$(cd "$MAIN" && pwd -P)" --arg s "$S1" '{main: $m, unit: "m-one", sha: $s, at: "2026-10-20T00:00:00Z"}'
  jq -cn --arg m "$(cd "$MAIN" && pwd -P)" --arg s "$S2" '{main: $m, unit: "m-two", sha: $s, at: "2026-10-21T00:00:00Z"}'; } > "$HOME/.commandeck/builds/demo.jsonl"
DNOW=$NOW dash
check "two merges after the upstream and one before: mergedSincePush lists the two, newest first" '["m-two","m-one"]' \
  "$(part '[.units.mergedSincePush[]? | .unit]')"
check "main_chain lastMerge names the newest merged unit and when" '{"unit":"m-two","at":"2026-10-21T00:00:00Z"}' \
  "$(part '.mainChain.lastMerge')"
for i in $(seq 1 151); do jq -cn --arg m "$(cd "$MAIN" && pwd -P)" --arg u "n$i" --arg a "$(iso $((1700000000 + i)))" --arg s "$(printf '%040x' "$i")" '{main: $m, unit: $u, sha: $s, at: $a}'; done > "$HOME/.commandeck/builds/demo.jsonl"
DNOW=$NOW dash
check "151 merge lines give 151 finished builds" 151 "$(part '.units.finishedBuilds | length')"

# Parked: a unit whose Builder pane and worktree are gone but whose task is still open is listed, with worktree false.
SCR=$(cd "$MAIN" && env -u COMMANDECK_SCRATCH COMMANDECK_MAIN="$MAIN" bash -c '. "$0" && echo "$PP_SCRATCH"' "$SOURCE/scripts/paths.sh"); mkdir -p "$SCR"; echo run_1 > "$SCR/current-run"
printf 'handle=h-pk\ntask=task_7\nrole=builder\nunit=pk\nworktree=pk\nlaunched=%s\n' "$((NOW - 600))" > "$SCR/seat-pk-builder.txt"
tasks() { printf '#!/usr/bin/env bash\ncase "$*" in "orchestration task-list"*) echo %q ;; *) exit 1 ;; esac\n' "$(jq -cn --arg s "$1" '{result: {tasks: [{id: "task_7", status: $s}]}}')" > "$BIN/orca-ide"; rm -rf "$T/out/cache"; DNOW=$NOW dash; }
tasks dispatched
check "a seat record for unit pk naming open task task_7, with no worktree pk, lists pk with worktree false" '[false]' \
  "$(part '[.units.inFlight[]? | select(.unit == "pk") | .worktree]')"
tasks completed
check "the same record with task_7 completed lists nothing" '[]' "$(part '[.units.inFlight[]? | select(.unit == "pk")]')"

# Launch roster: a unit in round 2, its Builder launched --model claude-sonnet-5-5 --effort high, a round-1 pass on
# gpt-6.1 high and a round-2 review pass on gpt-6.1-sol medium: the seats are the Builder and the round-2 reviewer.
mkdir -p "$WS/rt/.claude" && touch "$WS/rt/.git" && echo '{"env":{"COMMANDECK_BUILDER":"1"}}' > "$WS/rt/.claude/settings.local.json"
printf 'handle=h-rt\ntask=task_9\nrole=builder\nunit=rt\nworktree=rt\nlaunched=%s\ncmd=export COMMANDECK_SEAT=builder; claude --model claude-sonnet-5-5 --effort high\n' "$((NOW - 3000))" > "$SCR/seat-rt-builder.txt"
cs() { jq -cn --arg t "$(iso $((NOW - $1)))" --arg p "$2" --argjson r "$3" --arg m "$4" --arg e "$5" '{ts: $t, event: "codex-start", pass: $p, round: $r, model: $m, effort: $e}'; }
{ cs 2000 adversarial 1 gpt-6.1 high; cs 1900 review 1 gpt-6.1 high; cs 900 review 2 gpt-6.1-sol medium; } > "$WS/rt/.claude/builder-events.jsonl"
rm -rf "$T/out/cache"; DNOW=$NOW dash
seats() { part "[.units.inFlight[]? | select(.unit == \"$1\") | .seats | if . == null then null else [.[] | [.role, .model, .effort]] end]"; }
check "round 2: seats are the Builder (sonnet high) and the round-2 reviewer (gpt-6.1-sol medium); the round-1 pass is not listed" \
  '[[["builder","claude-sonnet-5-5","high"],["codex-reviewer","gpt-6.1-sol","medium"]]]' "$(seats rt)"
check "a unit that is not a Builder has no roster" '[null]' "$(seats u)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

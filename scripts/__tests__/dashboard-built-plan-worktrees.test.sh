#!/usr/bin/env bash
# dashboard-built-plan-worktrees.test.sh -- a live planning worktree reads Planning from its mark, as one card with its
# Builder; and the relay's open picker rides on the Chief of Staff part. The fixture is dashboard-built.test.sh's.
set -uo pipefail
. "$(dirname "$0")/fixtures/dashboard-built-setup.sh"
# The planning records dashboard-built-planning.test.sh builds, which these cases read.
SCR=$(cd "$MAIN" && env -u COMMANDECK_SCRATCH COMMANDECK_MAIN="$MAIN" bash -c '. "$0" && echo "$PP_SCRATCH"' "$SOURCE/scripts/paths.sh"); mkdir -p "$SCR" "$WS/pu-plan" && touch "$WS/pu-plan/.git"; echo run_1 > "$SCR/current-run"
printf 'handle=h7\ntask=task_7\nrole=plan-author\nunit=pu\nworktree=pu-plan\nlaunched=%s\n' "$(date +%s)" > "$SCR/seat-pu-plan-author.txt"
rm -rf "$T/out/cache"
NOW=$(date +%s); iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }; P0=$((NOW - 10800))
rec() { printf 'handle=h-%s\ntask=task_%s\nrole=%s\nunit=pv\nworktree=pv-plan\nlaunched=%s\ncmd=%s\n' "$1" "$1" "$1" "$2" "$3" > "$SCR/seat-pv-$1.txt"; }
rec plan-author $((NOW - 1800)) 'export COMMANDECK_SEAT=plan-author; claude --model claude-opus-5-5 --effort high'; printf 'session=s1\nfirst=%s\n' $((P0 - 1200)) >> "$SCR/seat-pv-plan-author.txt"
rec plan-judge-sol $((P0 + 60)) 'export COMMANDECK_SEAT=plan-judge-sol; codex --model gpt-6.1-sol -c model_reasoning_effort=high --sandbox read-only'
rec plan-judge-astra $((P0 + 120)) 'export COMMANDECK_SEAT=plan-judge-astra; codex --model gpt-6.1-astra --sandbox read-only'
PF=$HOME/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$WS/pv-plan"); mkdir -p "$PF/s1/subagents"
crow() { jq -cn --arg t "$(iso "$2")" --arg id "$1" --arg w "$WS/pv-plan" '{type: "assistant", timestamp: $t, cwd: $w, requestId: $id,
  message: {id: $id, model: "claude-haiku-5-5", usage: {input_tokens: 100000, output_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0}}}'; }
crow r0 $((P0 - 1100)) > "$PF/s0.jsonl"; crow r1 $((NOW - 1700)) > "$PF/s1.jsonl"; crow r2 $((NOW - 1690)) > "$PF/s1/subagents/a.jsonl"
CX=$HOME/.codex/sessions/2026/10/17; mkdir -p "$CX"
xrow() { printf '%s\n' "{\"type\":\"session_meta\",\"timestamp\":\"$(iso "$2")\",\"payload\":{\"cwd\":\"$WS/pv-plan\"}}" \
  "{\"type\":\"token_usage_record\",\"timestamp\":\"$(iso "$2")\",\"payload\":{\"response_id\":\"$1\",\"usage\":{\"input_tokens\":0,\"cached_input_tokens\":0,\"cache_write_input_tokens\":0,\"output_tokens\":0}}}"; }
JX=$T/judge-home/sessions/2026/10/17; mkdir -p "$JX"
xrow x-sol $((P0 + 90)) > "$JX/rollout-sol.jsonl"; xrow x-astra $((P0 + 150)) > "$CX/rollout-astra.jsonl"
mkdir -p "$MAIN/.claude/metrics"
jq -cn --arg c "$(iso $((P0 + 600)))" --arg s "$JX/rollout-sol.jsonl" '{event: "worker_done", unit: "pv", role: "plan-judge-sol", taskId: "task_plan-judge-sol",
  completedAt: $c, model: "gpt-6.1-sol", session: $s}' > "$MAIN/.claude/metrics/seat-events.jsonl"
mkdir -p "$WS/pv/.claude" && touch "$WS/pv/.git"; echo '{"env":{"COMMANDECK_BUILDER":"1"}}' > "$WS/pv/.claude/settings.local.json"
B0=$(iso $((NOW - 3600))); printf '%s\n' "{\"event\":\"tool-start\",\"ts\":\"$B0\",\"tool\":\"Read\",\"kind\":\"tool\",\"use\":\"t1\"}" \
  "{\"event\":\"tool-end\",\"ts\":\"$B0\",\"use\":\"t1\"}" > "$WS/pv/.claude/builder-events.jsonl"
# The build merged: its cost is kept as it stood, its planning inside it.
mkdir -p "$HOME/.commandeck/builds"; jq -cn --arg m "$(cd "$MAIN" && pwd -P)" '{main: $m, unit: "pv", sha: "'"$(printf 'a%.0s' {1..40})"'", at: "2026-10-17T00:00:00Z"}' > "$HOME/.commandeck/builds/demo.jsonl"
# Live planning worktrees, marked as seat.sh marks them, each with an idle pane: a finished plan waits on main and
# still reads Planning; with the Builder there too, the unit is one card. An unmarked <name>-plan is no plan.
for w in pv-plan pw-plan foo-plan; do git -C "$MAIN" worktree add -q "$WS/$w"; done
for w in pv pw; do echo "$w" > "$(git -C "$WS/$w-plan" rev-parse --absolute-git-dir)/commandeck-plan-of"; done
PS=$(jq -cn --arg ws "$WS" '{result: {worktrees: [("pv-plan", "pw-plan", "foo-plan") | {path: "\($ws)/\(.)", agents: [{agentType: "claude", state: "idle", updatedAt: 0}]}]}}')
printf '#!/usr/bin/env bash\ncase "$*" in "orchestration task-list"*) echo %s ;; "worktree ps"*) echo %q ;; *) exit 1 ;; esac\n' \
  "'{\"result\":{\"tasks\":[]}}'" "$PS" > "$BIN/orca-ide"
dash
stg() { jq -c --arg u "$1" 'first(.[]) | [.units.inFlight[]? | select(.unit == $u) | .stage]' "$T/out/run/project.json" 2>&1; }
check "a marked planning worktree with an idle pane reads Planning, not waiting on main" '["planning"]' "$(stg pw-plan)"
check "with its Builder there, the planning worktree has no card of its own; the Builder's carries it" '[]:1' "$(stg pv-plan):$(stg pv | jq length)"
check "an unmarked worktree named <name>-plan still waits on main" '["waiting-main"]' "$(stg foo-plan)"
# A unit is planned and built in one worktree: a marked <unit> is its Planning stage from the mark, its planner's task
# completed and none open (so no live seat names it), its seats read from records naming <unit>. An unmarked <unit>
# with an idle pane is no plan.
for w in px py; do git -C "$MAIN" worktree add -q "$WS/$w"; done
echo px > "$(git -C "$WS/px" rev-parse --absolute-git-dir)/commandeck-plan-of"
printf 'handle=h-px\ntask=task_px\nrole=plan-author\nunit=px\nworktree=px\nlaunched=%s\ncmd=claude --model opus\n' $((NOW - 600)) > "$SCR/seat-px-plan-author.txt"
jq -cn --arg c "$(iso $((NOW - 60)))" '{taskId: "task_px", completedAt: $c}' >> "$MAIN/.claude/metrics/seat-events.jsonl"
PS=$(jq -cn --arg ws "$WS" '{result: {worktrees: [("px", "py") | {path: "\($ws)/\(.)", agents: [{agentType: "claude", state: "idle", updatedAt: 0}]}]}}')
printf '#!/usr/bin/env bash\ncase "$*" in "orchestration task-list"*) echo %s ;; "worktree ps"*) echo %q ;; *) exit 1 ;; esac\n' \
  "'{\"result\":{\"tasks\":[]}}'" "$PS" > "$BIN/orca-ide"
dash
check "a marked <unit> is one Planning card, its seats and their completion read from records naming <unit>" \
  "[[\"planning\",\"$WS/px\",[[\"plan-author\",\"$(iso $((NOW - 60)))\"]]]]" \
  "$(jq -c 'first(.[]) | [.units.inFlight[]? | select(.unit == "px") | [.stage, .plan.worktree, [.plan.seats[]? | [.role, .completedAt]]]]' "$T/out/run/project.json" 2>&1)"
check "an unmarked <unit> with an idle pane is not Planning" '["waiting-main"]' "$(stg py)"

# Issue 232: the relay's open picker, as main-watch.sh records it, rides on the Chief of Staff part for the alert rule.
mkdir -p "$SCR/main-watch"; echo '{"since":1000,"waiting":2}' > "$SCR/main-watch/relay-picker.json"
printf '#!/usr/bin/env bash\ncase "$*" in "terminal list"*) echo %q ;; "orchestration inbox"*) echo %s ;; *) exit 1 ;; esac\n' \
  "$(jq -cn --arg p "$WS/Chief-of-Staff" '{result: {terminals: [{handle: "h-cos", worktreePath: $p}]}}')" \
  "'{\"result\":{\"messages\":[]}}'" > "$BIN/orca-ide"
dash
check "the relay's picker record is on the Chief of Staff part" '{"since":1000,"waiting":2}' "$(jq -c 'first(.[]) | .chiefOfStaff.picker' "$T/out/run/project.json" 2>&1)"
rm "$SCR/main-watch/relay-picker.json"; dash
check "no record is no picker" 'null' "$(jq -c 'first(.[]) | .chiefOfStaff.picker' "$T/out/run/project.json" 2>&1)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

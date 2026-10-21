#!/usr/bin/env bash
# dashboard-built-planning.test.sh -- a unit's planning is its Planning stage, seat by seat, rebuilt from records
# that outlive its planning worktree, its cost counted once per request. The fixture is dashboard-built.test.sh's.
set -uo pipefail
. "$(dirname "$0")/fixtures/dashboard-built-setup.sh"

# Sol r3: a planner runs in <unit>-plan, its record's unit is <unit>, and its card read no seat for that worktree.
SCR=$(cd "$MAIN" && env -u COMMANDECK_SCRATCH COMMANDECK_MAIN="$MAIN" bash -c '. "$0" && echo "$PP_SCRATCH"' "$SOURCE/scripts/paths.sh"); mkdir -p "$SCR" "$WS/pu-plan" && touch "$WS/pu-plan/.git"; echo run_1 > "$SCR/current-run"
printf 'handle=h7\ntask=task_7\nrole=plan-author\nunit=pu\nworktree=pu-plan\nlaunched=%s\n' "$(date +%s)" > "$SCR/seat-pu-plan-author.txt"
printf '#!/usr/bin/env bash\ncase "$*" in "orchestration task-list"*) echo %s ;; *) exit 1 ;; esac\n' \
  "'{\"result\":{\"tasks\":[{\"id\":\"task_7\",\"status\":\"running\"}]}}'" > "$BIN/orca-ide"
dash
check "a planner's card in its planning worktree shows its seat" '["planning","plan-author"]' \
  "$(jq -c 'first(.[]) | .units.inFlight[]? | select(.unit == "pu-plan") | [.stage, .seatRole]' "$T/out/run/project.json" 2>&1)"

# a unit's planning is its Planning stage, rebuilt each collect from what outlives the planning worktree: the
# seat records, the seat ledger, Claude's transcripts and Codex's logs. pv-plan is already closed, the Builder pv
# runs. Its plan-author is a Claude seat with session s1 (a sub-agent too); plan-judge-sol a Codex seat collected
# (its ledger row names its log, in the judge's own Codex home, not the collector's); plan-judge-astra a Codex seat
# not collected, so nothing names its log yet. plan-author was relaunched: its record is the relaunch's, its first
# launch 20 minutes earlier (first=), whose session s0 made one request no seat now holds. The relaunch came after
# the Builder started (Sol r4): the seat is still the Builder's own planning, which its first launch dates.
# Haiku rows are $0.01 each; the Codex rows count no tokens, so $0. EMPTY cache: nothing read before counts.
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
dash
pv() { jq -c "first(.[]) | .units.inFlight[]? | select(.unit == \"pv\") | $1" "$T/out/run/project.json" 2>&1; }
check "the Builder's cost starts with its planning: every request its seats made, the closed worktree's, a first launch's and another Codex home's included" '["planning",5,0.03]' \
  "$(pv '.builder.cost.stages[0] | [.stage, .calls, .usd]')"
check "and its total holds the planning" '[5,0.03]' "$(pv '.builder.cost.total | [.calls, .usd]')"
check "seat by seat: model and effort from each record, a sub-agent's calls in its seat's, what no seat holds in one row" \
  '[["plan-author","claude-opus-5-5","high",2,0.02],["plan-judge-sol","gpt-6.1-sol","high",1,0.0],["plan-judge-astra","gpt-6.1-astra",null,0,0],[null,null,null,2,0.01]]' \
  "$(pv '[.builder.cost.seats[] | [.role, .model, .effort, .calls, .usd]]')"
check "the seats sum to the planning stage" true "$(pv '.builder.cost | ([.seats[].calls] | add) == .stages[0].calls')"
check "a collected seat runs to its collect; one not collected has no end" "[\"$(iso $((P0 + 600)))\",null]" "$(pv '[.builder.cost.seats[1].to, .builder.cost.seats[2].to]')"
check "its clock starts with the planning stage at its first launch, drawn first" "[\"planning\",\"$(iso $((P0 - 1200)))\",\"$(iso $((P0 - 1200)))\",\"building\"]" \
  "$(pv '[.builder.stageHistory[0].stage, .builder.stageHistory[0].from, .builder.startedAt, .builder.stageHistory[1].stage]')"
check "the finished build keeps the planning in its cost" '["planning",5]' \
  "$(jq -c 'first(.[]) | .units.finishedBuilds[]? | select(.unit == "pv") | [.cost.stages[0].stage, .cost.total.calls]' "$T/out/run/project.json" 2>&1)"
# Two seats that name one log (two judges whose lookups found the same session) cannot both own it: its request
# is held by neither, so the seats still sum to the stage.
check "a log two seats claim is held by neither, and counted once" '[0,0,1]' "$(cd "$SOURCE/scripts" && python3 -c '
import json, dashboard_limit as d
rows = [([100, "claude-haiku-5-5", None, 100000, 0, 0, 0], "/w", "/logs/x.jsonl", "codex")]
s = d.seat_costs([{"role": "a", "from": None, "session": "/logs/x.jsonl"}, {"role": "b", "from": None, "session": "/logs/x.jsonl"}], rows, "/f", 200)
print(json.dumps([x["calls"] for x in s]).replace(" ", ""))' 2>&1)"
# Another Codex home is read whole by its own cache: two homes whose names differ only in punctuation shared one
# cache and each read kept the other's requests (Sol r2), and a judge relaunched after midnight logs in another
# date folder of the same home, whose earlier request was dropped.
for h in judge-a judge_a judge; do mkdir -p "$T/$h/sessions/2026/10/16" "$T/$h/sessions/2026/10/17"; done
xrow x-a $((P0 + 90)) > "$T/judge-a/sessions/2026/10/17/a.jsonl"; xrow x-b $((P0 + 90)) > "$T/judge_a/sessions/2026/10/17/b.jsonl"
xrow x-old $((P0 + 90)) > "$T/judge/sessions/2026/10/16/old.jsonl"; xrow x-new $((P0 + 200)) > "$T/judge/sessions/2026/10/17/new.jsonl"
homes() { (cd "$SOURCE/scripts" && python3 -c '
import json, sys, dashboard_limit as d
t, wt, p0, now, cache = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
seat = lambda r, s: {"role": r, "from": d.iso(p0), "session": t + s}
u = lambda n, *s: {"unit": n, "worktree": wt + "-build", "stages": [], "plan": {"worktree": wt, "from": d.iso(p0), "seats": list(s)}}
units = [u("two", seat("a", "/judge-a/sessions/2026/10/17/a.jsonl"), seat("b", "/judge_a/sessions/2026/10/17/b.jsonl")),
         u("midnight", seat("j", "/judge/sessions/2026/10/17/new.jsonl"))]
r = [d.unit_costs([x], now, cache, t + "/none", None)[x["unit"]]["total"]["calls"] for x in units for _ in (1, 2)]
print(json.dumps(r).replace(" ", ""))' "$T" "$WS/pv-plan" "$P0" "$NOW" "$1" 2>&1); }
mkdir -p "$T/homes-cache"
check "two Codex homes named alike are each read once, on every collect; a home's earlier date folder is read too" '[2,2,2,2]' "$(homes "$T/homes-cache")"
# The review Codex home (COMMANDECK_CODEX_REVIEW_HOME, default ~/.codex-review) is where every review pass logs:
# its spend was never read, so a unit's cost left out every review request. A seat bound to a log there is read
# with that home already, never a second time. A Codex home that cannot be searched (its parent locked) read as
# not installed, so the unit called its cost complete; its spend is unknown, so the cost is none at all.
RX=$T/review-home/sessions/2026/10/17; mkdir -p "$RX"; xrow x-rev $((P0 + 90)) > "$RX/rev.jsonl"
LX=$T/locked/home/sessions/2026/10/17; mkdir -p "$LX"; xrow x-lock $((P0 + 90)) > "$LX/lock.jsonl"
seatcost() { rm -rf "$T/seat-cache"; mkdir -p "$T/seat-cache"; (cd "$SOURCE/scripts" && python3 -c '
import json, sys, dashboard_limit as d
wt, p0, now, cache, s = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5]
seats = [{"role": "r", "from": d.iso(p0), "session": s}] if s else []
c = d.unit_costs([{"unit": "u", "worktree": wt + "-build", "stages": [], "plan": {"worktree": wt, "from": d.iso(p0), "seats": seats}}], now, cache, "/none", None)["u"]
print(json.dumps(c and [c["total"]["calls"]] + [x["calls"] for x in c["seats"] if x["role"]]).replace(" ", ""))' "$WS/pv-plan" "$P0" "$NOW" "$T/seat-cache" "${1:-}" 2>&1); }
check "a review home's request counts in the unit's total" '[1]' "$(seatcost)"
check "a seat bound to a review-home log holds it, and it counts once" '[1,1]' "$(seatcost "$RX/rev.jsonl")"
# Homes are compared as real paths: a seat log spelled through a symlink or a "." still names the review home.
ln -s "$T/review-home" "$T/review-alias"
check "a seat bound to a review-home log through a symlink counts it once" '[1,1]' "$(seatcost "$T/review-alias/sessions/2026/10/17/rev.jsonl")"
check "a seat bound to a review-home log through a dot path counts it once" '[1,1]' "$(seatcost "$T/./review-home/sessions/2026/10/17/rev.jsonl")"
check "a review home named through a symlink, its seat logged at the real path, counts it once" '[1,1]' "$(COMMANDECK_CODEX_REVIEW_HOME=$T/review-alias seatcost "$RX/rev.jsonl")"
chmod 000 "$T/locked"
check "a seat whose Codex home cannot be searched leaves the unit's cost unknown" 'null' "$(seatcost "$LX/lock.jsonl")"
check "and its sessions folder reads as missed, not absent" 'true' "$(cd "$SOURCE/scripts" && python3 -c '
import sys, dashboard_limit as d
m = []
d.codex_requests(sys.argv[1], sys.argv[2], 0, 2**40, m)
print(bool(m) and "true")' "$T/locked/home/sessions" "$T/seat-cache/x.json" 2>&1)"
chmod 755 "$T/locked"
# Issue 242: the Builder took over the worktree its plan seat cut (plan-worktree-close.sh --adopt), so the plan's and the
# build's worktree are one. Every request landed in planning; each now goes to the stage it was made in.
OW=$WS/one-wt OP=$T/one-projects OC=$T/one-codex/2026/10/17; mkdir -p "$OP/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$OW")" "$OC"
orow() { jq -cn --arg t "$(iso "$2")" --arg id "$1" --arg w "$OW" '{type: "assistant", timestamp: $t, cwd: $w, requestId: $id,
  message: {id: $id, model: "claude-haiku-5-5", usage: {input_tokens: 100000, output_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0}}}'; }
{ orow o-plan $((P0 + 10)); orow o-build $((P0 + 200)); } > "$OP/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$OW")/s.jsonl"
xrow x-pass $((P0 + 400)) | sed "s#$WS/pv-plan#$OW#" > "$OC/rollout-pass.jsonl"
check "one worktree as plan and build: each request on its own stage, the total unchanged" '[["planning",1],["building",1],["review",1],3]' \
  "$(rm -rf "$T/one-cache"; mkdir -p "$T/one-cache"; cd "$SOURCE/scripts" && python3 -c '
import json, sys, dashboard_limit as d
wt, p0, now = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
st = [{"stage": "building", "from": d.iso(p0 + 100), "to": d.iso(p0 + 300)}, {"stage": "review", "from": d.iso(p0 + 300), "to": None}]
c = d.unit_costs([{"unit": "u", "worktree": wt, "stages": st, "plan": {"worktree": wt, "from": d.iso(p0), "seats": []}}], now, sys.argv[4], sys.argv[5], sys.argv[6])["u"]
print(json.dumps([[s["stage"], s["calls"]] for s in c["stages"]] + [c["total"]["calls"]]).replace(" ", ""))' "$OW" "$P0" "$NOW" "$T/one-cache" "$OP" "${OC%/2026/10/17}" 2>&1)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

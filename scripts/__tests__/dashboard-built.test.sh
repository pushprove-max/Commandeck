#!/usr/bin/env bash
# dashboard-built.test.sh -- a Builder's card says how many of its issues are built, read from its evidence file.
# Builders record each issue's status in a table (Issue and Status columns), most under a "## Per issue" heading,
# so a count that read only "## #<n>" headings said 1 built for builds that had built most of their issues, and
# the owner would chase work that was done. What this pins, on copies of two real evidence files (taken
# 2026-10-16; issue numbers carry a leading 1 so the leak check passes): a row whose status starts "built" counts,
# under "## Per issue" or under the title; a "partly built" row does not, even with a heading of its own.
# A Builder also carries its live context, from its session log, beside the clear line setup recorded for it.
# A unit's planning is its Planning stage, seat by seat, rebuilt from records that outlive its planning worktree.
set -uo pipefail
SOURCE=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'chmod 755 "$T/locked" 2>/dev/null; rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

export HOME=$T/home COMMANDECK_CODEX_REVIEW_HOME=$T/review-home
MAIN=$T/demo BIN=$T/bin WS=$T/ws
mkdir -p "$HOME" "$BIN"
git init -q -b main "$MAIN" && git -C "$MAIN" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
printf '#!/usr/bin/env bash\nexit 1\n' > "$BIN/orca-ide"; cp "$BIN/orca-ide" "$BIN/gh"; chmod +x "$BIN"/*
# builder <unit>: a Builder's worktree holding the unit's evidence file from the fixtures.
builder() {
  mkdir -p "$WS/$1/.claude/briefs" && touch "$WS/$1/.git"
  echo '{"env":{"COMMANDECK_BUILDER":"1"}}' > "$WS/$1/.claude/settings.local.json"
  cp "$SOURCE/scripts/__tests__/fixtures/evidence/$1-evidence.md" "$WS/$1/.claude/briefs/"
}
builder help-email-batch-2026-10-16; builder api-batch-2026-10-16
# Each round file's own verdict, so each finished pass shows its own. r1 is older than
# r2, so r2 stays the newest report; a round file named with no number has no round.
V=$WS/u-verdicts/.claude/briefs; mkdir -p "$V" && touch "$WS/u-verdicts/.git"
echo '{"env":{"COMMANDECK_BUILDER":"1"}}' > "$WS/u-verdicts/.claude/settings.local.json"
printf 'Round 2 review.\nVERDICT: GO\n\n' > "$V/u-verdicts-r2-reports.md"
printf 'Round 1 review.\n- [P1] one -- f:1 -- why\nVERDICT: NO-GO\n' > "$V/u-verdicts-r1-reports.md"; touch -t 202001010000 "$V/u-verdicts-r1-reports.md"
printf 'VERDICT: GO\n' > "$V/u-verdicts-rx-reports.md"; touch -t 202001010000 "$V/u-verdicts-rx-reports.md"
# A Builder main raised: its brief carries the override line builder-launch.sh writes, so its card can say so.
printf '# u-verdicts -- Builder batch\n\neffort override: builder medium -> high: touches billing\n\n## The batch\n' > "$V/u-verdicts.md"
mkdir -p "$MAIN/.claude" "$HOME/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$WS/u-verdicts")"
echo '{"builder": {"clearLine": "160000"}}' > "$MAIN/.claude/commandeck.json"
echo '{"type":"assistant","message":{"usage":{"cache_read_input_tokens":150000,"input_tokens":12}}}' > "$HOME/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$WS/u-verdicts")/s.jsonl"
dash() { env -u COMMANDECK_SCRATCH -u COMMANDECK_HOOK_FIRE_LOG -u CODEX_HOME PATH="$BIN:$PATH" COMMANDECK_WORKSPACES="$WS" \
  COMMANDECK_DASHBOARD_DIR="$T/out" COMMANDECK_MAIN="$MAIN" DASH_NOW="$(date +%s)" bash "$SOURCE/scripts/dashboard.sh" --project "$T/out/run" >"$T/out.log" 2>&1; }
dash
built() { jq -c --arg u "$1" 'first(.[]) | [.units.inFlight[]? | select(.unit == $u) | .builder.built]' "$T/out/run/project.json" 2>&1; }

check "every issue the Per issue table marks built counts as built" \
  '[[12639,12640,12641,12642,12643,12644,12645,12646,12647,12648,12649,12650,12651,12652,12653,12654,12655,12656]]' "$(built help-email-batch-2026-10-16)"
check "a table under the title counts too, and a partly built issue does not, though a heading names it" \
  '[[12556,12617,11775]]' "$(built api-batch-2026-10-16)"
check "a Builder carries the verdict of every round file by its own round, and the newest report's beside it" \
  '[{"1":"VERDICT: NO-GO","2":"VERDICT: GO"},"VERDICT: GO",2]' \
  "$(jq -c 'first(.[]) | .units.inFlight[]? | select(.unit == "u-verdicts") | [.builder.verdicts, .builder.verdict, .builder.verdictRound]' "$T/out/run/project.json" 2>&1)"
check "a Builder's live context from its session log, beside the clear line setup recorded" '[150012,"160000"]' \
  "$(jq -c 'first(.[]) | .units.inFlight[]? | select(.unit == "u-verdicts") | [.builder.context, .builder.clearLine]' "$T/out/run/project.json" 2>&1)"
check "one with no session log has no context to show" '[null]' "$(jq -c 'first(.[]) | [.units.inFlight[]? | select(.unit == "api-batch-2026-10-16") | .builder.context]' "$T/out/run/project.json" 2>&1)"
check "a raised Builder carries the effort main raised it to and why; one launched at the default carries none" '[{"effort":"high","reason":"touches billing"},null]' \
  "$(jq -c 'first(.[]) | [.units.inFlight[]? | select(.unit == "u-verdicts" or .unit == "api-batch-2026-10-16")] | sort_by(.unit) | reverse | map(.builder.raised)' "$T/out/run/project.json" 2>&1)"
# The stage list names each pass by its round, from the Builder's own log.
printf '%s\n' '{"event":"tool-start","ts":"2026-10-10T12:00:00Z","tool":"Read","use":"t1"}' '{"event":"tool-end","ts":"2026-10-10T12:00:01Z","use":"t1"}' \
  '{"event":"codex-start","ts":"2026-10-10T12:30:00Z","pass":"adversarial","round":1}' '{"event":"codex-end","ts":"2026-10-10T12:40:00Z","pass":"adversarial","round":1,"rc":0}' \
  '{"event":"codex-start","ts":"2026-10-10T12:50:00Z","pass":"review","round":2}' > "$T/log.jsonl"
check "each review stage carries its pass's round; building and fixing carry none" '[["building",null],["review",1],["fixing",null],["review",2]]' \
  "$(jq -s --argjson now 0 -f "$SOURCE/scripts/dashboard_builders.jq" "$T/log.jsonl" | jq -c '[.stageHistory[] | [.stage, .round]]')"

# A round run again after a failed try: the retry starts in the second the failed one ended. Each start pairs with the
# first end after it in the log, so the review time is 60 s + 300 s, not the first end counted twice.
printf '%s\n' '{"event":"tool-start","ts":"2026-10-10T11:59:00Z","tool":"Read","use":"t1"}' '{"event":"tool-end","ts":"2026-10-10T11:59:01Z","use":"t1"}' \
  '{"event":"codex-start","ts":"2026-10-10T12:00:00Z","pass":"review","round":2}' '{"event":"codex-end","ts":"2026-10-10T12:01:00Z","pass":"review","round":2,"rc":1}' \
  '{"event":"codex-start","ts":"2026-10-10T12:01:00Z","pass":"review","round":2}' '{"event":"codex-end","ts":"2026-10-10T12:06:00Z","pass":"review","round":2,"rc":0}' > "$T/retry.jsonl"
check "a retried pass of the same round keeps both tries in the review time" 360 \
  "$(jq -s --argjson now 0 -f "$SOURCE/scripts/dashboard_builders.jq" "$T/retry.jsonl" | jq -c '.reviewSec')"

# The costs kept for finished builds are written back whole on every run. A kept file that could not be read
# was taken as empty and overwritten, losing every earlier unit's cost; one that reads but is not an object is reset.
K=$T/out/cache/demo/unit-cost.json
printf '{"old-unit":{"usd":1}}\n' > "$K"; chmod 000 "$K"; dash; chmod 644 "$K"
check "an unreadable kept cost file is left as it was" '{"old-unit":{"usd":1}}' "$(jq -c . "$K" 2>&1)"
echo 'not json{' > "$K"; dash
check "a corrupt kept cost file is reset to an object" '{}' "$(jq -c . "$K" 2>&1)"
rm "$K"; mkdir "$K"; dash
check "a directory where the kept cost file belongs gets nothing put inside it" 0 "$(ls -A "$K" | wc -l | tr -d ' ')"
# The same fault in --unregister: an unreadable registry was rewritten as empty, dropping every registered project.
unreg() { COMMANDECK_DASHBOARD_DIR="$T/out" COMMANDECK_MAIN="$MAIN" bash "$SOURCE/scripts/dashboard.sh" --unregister "$1" >/dev/null 2>&1; }
R=$T/out/projects; printf '/a\n/b\n' > "$R"; chmod 000 "$R"; unreg /a
check "--unregister with an unreadable registry fails and leaves it as it was" "1 /a /b" "$? $(chmod 644 "$R"; paste -sd' ' "$R")"
unreg /a; check "--unregister drops only that project" "0 /b" "$? $(paste -sd' ' "$R")"
rm "$R"; mkdir "$R"; unreg /b
check "--unregister with a directory where the registry belongs fails, putting nothing inside it" "1 0" "$? $(ls -A "$R" | wc -l | tr -d ' ')"

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

# The dashboard off for every project (the registry exists and lists none) collects no home project either; a job
# installed before any registration (no registry yet) keeps collecting it.
off() { rm -rf "$T/out2"; mkdir -p "$T/out2"; case ${1:-} in "") ;; EMPTY) : > "$T/out2/projects" ;; *) printf '%s\n' "$1" > "$T/out2/projects" ;; esac
  env -u COMMANDECK_SCRATCH -u CODEX_HOME PATH="$BIN:$PATH" COMMANDECK_WORKSPACES="$WS" COMMANDECK_DASHBOARD_DIR="$T/out2" COMMANDECK_MAIN="$MAIN" \
    DASH_NOW="$(date +%s)" bash "$SOURCE/scripts/dashboard.sh" >"$T/out2.log" 2>&1
  sed 's/^window.DASH = //; s/;$//' "$T/out2/data.js" | jq -c '.projects | keys'; }
check "an empty registry: the home project is not collected" '[]' "$(off EMPTY)"
check "no registry yet: the home project is collected, as before" '["demo"]' "$(off)"
check "a registry listing the home project: it is collected" '["demo"]' "$(off "$MAIN")"

# Issue 203: a 5-minute Builder at its prompt, waiting on something open, gets a keep-alive WARM just before its own
# cache lapses (225-300 s after its last request, on a 60 s tick), while a ping costs less than the rewrite it saves; a
# Builder idle on its own background job is waiting, not QUIET; and QUIET comes at 225 s on a 5-minute cache, while the
# cache is still warm. dashboard.sh passes no cache or tick, so the dashboard shows what it did before.
BJQ=$SOURCE/scripts/dashboard_builders.jq; N=2000000000
at() { jq -nr --argjson t "$((N - $1))" '$t | todate'; }
ts_() { printf '{"ts":"%s","event":"tool-start","use":"%s","tool":"Bash","kind":"%s","call":"c%s"}\n' "$(at "$1")" "$2" "$3" "$2"; }
te_() { printf '{"ts":"%s","event":"tool-end","use":"%s","ok":true}\n' "$(at "$1")" "$2"; }
sig() { jq -sc --argjson now "$N" ${1:+--argjson bgOpen "$1"} ${2:+--argjson cache "$2"} ${3:+--argjson tick "$3"} -f "$BJQ"; }
kinds() { sig "$@" | jq -c '[.signals[] | [.kind, .limitSec]]'; }
warm() { sig "$@" | jq -c '[.signals[] | select(.kind == "warm")]'; }
WC() { printf '{"ttl":%s,"ctx":%s,"at":%s,"ended":%s}' "${1:-300}" "${2:-100000}" "$((N - ${3:-230}))" "${4:-true}"; }
OWN() { ts_ 400 u1 shell; te_ 399 u1; }
check "warm: idle 230 s with a job open on a 100k context is one warm signal from the request, anchored on the parent's row, 11 pings" \
  "[{\"kind\":\"warm\",\"since\":$((N - 230)),\"anchor\":$((N - 400)),\"limitSec\":300,\"maxPings\":11}]" "$(OWN | warm 1 "$(WC)" 60)"
check "warm: none at 200 s or 310 s idle, on a 1-hour cache at 3530 s, mid-turn, with nothing open, or with no cache" "[] [] [] [] [] []" \
  "$(OWN | warm 1 "$(WC 300 100000 200)" 60) $(OWN | warm 1 "$(WC 300 100000 310)" 60) $(OWN | warm 1 "$(WC 3600 100000 3530)" 60) $(OWN | warm 1 "$(WC 300 100000 230 false)" 60) $(OWN | warm 0 "$(WC)" 60) $(OWN | warm 1 '' 60)"
check "warm: a 1000-token context buys 2 pings (a ping costs 450, a saved rewrite 1150)" 2 "$(OWN | warm 1 "$(WC 300 1000)" 60 | jq -c '.[0].maxPings')"
HELP=$(printf '{"ts":"%s","event":"tool-start","use":"h2","tool":"Grep","kind":"tool","agent":"a1","call":"g"}\n{"ts":"%s","event":"tool-end","use":"h2","ok":true}\n{"ts":"%s","event":"batch-end","uses":["h2"]}\n' "$(at 100)" "$(at 99)" "$(at 98)")
check "warm: a helper's rows after the parent's do not move the anchor; the parent's own subagent-request does" "$((N - 400)) $((N - 40))" \
  "$({ OWN; printf '%s\n' "$HELP"; } | warm 1 "$(WC)" 60 | jq -c '.[0].anchor') $({ OWN; printf '%s\n' "$HELP"; printf '{"ts":"%s","event":"subagent-request","type":"Explore"}\n' "$(at 40)"; } | warm 1 "$(WC)" 60 | jq -c '.[0].anchor')"
check "quiet: 226 s idle is QUIET at 225 s on a 5-minute cache and a 60 s tick, and nothing without a cache" '[["quiet",225]] []' \
  "$({ ts_ 400 u1 shell; te_ 226 u1; } | kinds '' "$(WC)" 60) $({ ts_ 400 u1 shell; te_ 226 u1; } | kinds)"
check "quiet: 301 s idle with a background job open is no signal; with none, or an unreadable log, it is QUIET" '[] [["quiet",300]] [["quiet",300]]' \
  "$({ ts_ 400 u1 shell; te_ 301 u1; } | kinds 1) $({ ts_ 400 u1 shell; te_ 301 u1; } | kinds 0) $({ ts_ 400 u1 shell; te_ 301 u1; } | kinds null)"
# pp_session_bg_open and pp_session_cache read the newest session record of a worktree, on its real row shapes.
CW=$T/cwt; CL=$HOME/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$CW"); mkdir -p "$CW" "$CL"
pp() { (. "$SOURCE/scripts/paths.sh" && "$1" "$CW" | jq -c .); }
{ printf '{"type":"user","toolUseResult":{"stdout":"","backgroundTaskId":"bAAA1"}}\n{"type":"user","toolUseResult":{"backgroundTaskId":"bBBB2"}}\n'
  printf '{"type":"user","toolUseResult":"a result that quotes backgroundTaskId bZZZ9"}\n'
  printf '{"type":"queue-operation","content":"<task-notification>\\n<task-id>bAAA1</task-id>\\n<status>completed</status>\\n</task-notification>"}\n'; } > "$CL/s1.jsonl"
check "bg_open: two jobs started and one notified is 1 open, a quoted id not counted" 1 "$(pp pp_session_bg_open)"
# A TaskStop sends no notification; its successful result is the job's end, else the job holds QUIET off for good.
printf '{"type":"user","toolUseResult":{"task_id":"bBBB2"},"message":{"content":[{"type":"tool_result","content":"Successfully stopped task: bBBB2"}]}}\n' >> "$CL/s1.jsonl"
check "bg_open: a job TaskStop stopped is closed" 0 "$(pp pp_session_bg_open)"
printf '{"type":"user","toolUseResult":{"backgroundTaskId":"bCCC3"}}\n{"type":"user","toolUseResult":{"task_id":"bCCC3"},"message":{"content":"Error: no task bCCC3"}}\n' >> "$CL/s1.jsonl"
check "bg_open: a TaskStop that failed closes nothing" 1 "$(pp pp_session_bg_open)"
crow() { printf '{"type":"assistant","isSidechain":%s,"timestamp":"%s","message":{"stop_reason":"%s","usage":{"input_tokens":%s,"cache_read_input_tokens":%s,"cache_creation_input_tokens":%s,"cache_creation":{"ephemeral_1h_input_tokens":%s,"ephemeral_5m_input_tokens":%s}}}}\n' "${7:-false}" "$1" "$2" "$3" "$4" "$5" "${6%/*}" "${6#*/}"; }
urow() { printf '{"type":"user","isSidechain":false,"timestamp":"%s","message":{}}\n' "$1"; }
E1=$(jq -n '"2026-10-18T10:00:00Z" | fromdateiso8601'); E2=$(jq -n '"2026-10-18T10:00:30Z" | fromdateiso8601')
{ urow 2026-10-18T09:59:58Z; crow 2026-10-18T10:00:00Z tool_use 10 90000 5000 0/5000; urow 2026-10-18T10:00:30Z; crow 2026-10-18T10:00:45Z end_turn 12 95000 0 0/0; } > "$CL/s1.jsonl"
check "session_cache: a 5m write, then an end_turn reply: ttl 300, ctx of the newest reply, at its request, ended" "{\"ttl\":300,\"ctx\":95012,\"at\":$E2,\"ended\":true}" "$(pp pp_session_cache)"
{ urow 2026-10-18T10:00:00Z; crow 2026-10-18T10:00:00Z tool_use 10 90000 5000 5000/0; } > "$CL/s1.jsonl"
check "session_cache: a 1h write is ttl 3600, and a tool_use reply newest is not ended" '[3600,false]' "$(pp pp_session_cache | jq -c '[.ttl, .ended]')"
{ urow 2026-10-18T10:00:00Z; crow 2026-10-18T10:00:00Z tool_use 10 90000 5000 0/5000; crow 2026-10-18T10:00:30Z end_turn 12 95000 0 0/0 true; } > "$CL/s1.jsonl"
check "session_cache: a newer isSidechain row is skipped" "[95010,$E1,false]" "$(pp pp_session_cache | jq -c '[.ctx, .at, .ended]')"
{ crow 2026-10-18T10:00:00Z end_turn 10 90000 0 0/0; } > "$CL/s1.jsonl"
check "session_cache: no reply that wrote cache is null" null "$(pp pp_session_cache)"
rm -rf "$CL"
check "bg_open and session_cache: no session record is null" "null null" "$(pp pp_session_bg_open) $(pp pp_session_cache)"

# Issue 232: the relay's open picker, as main-watch.sh records it, rides on the Chief of Staff part for the alert rule.
mkdir -p "$SCR/main-watch"; echo '{"since":1000,"waiting":2}' > "$SCR/main-watch/relay-picker.json"
printf '#!/usr/bin/env bash\ncase "$*" in "terminal list"*) echo %q ;; "orchestration inbox"*) echo %s ;; *) exit 1 ;; esac\n' \
  "$(jq -cn --arg p "$WS/Chief-of-Staff" '{result: {terminals: [{handle: "h-cos", worktreePath: $p}]}}')" \
  "'{\"result\":{\"messages\":[]}}'" > "$BIN/orca-ide"
dash
check "the relay's picker record is on the Chief of Staff part" '{"since":1000,"waiting":2}' "$(jq -c 'first(.[]) | .chiefOfStaff.picker' "$T/out/run/project.json" 2>&1)"
rm "$SCR/main-watch/relay-picker.json"; dash
check "no record is no picker" 'null' "$(jq -c 'first(.[]) | .chiefOfStaff.picker' "$T/out/run/project.json" 2>&1)"

# Issue 224: main's and the relay's own cards. Main's sessions are the main checkout's projects folder (the one a
# Builder's cost leaves out), the relay's the Chief-of-Staff worktree's. Haiku rows of 100,000 tokens are $0.01 each.
# Main ran one request today and one 3 days ago; it restarted twice today, a minute apart. A restart of a session
# that is not main's, and a failed restart, count for nothing. The relay is no restarting seat and has no clear line.
seatf() { echo "$HOME/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$1")"; }
mkdir -p "$(seatf "$MAIN")" "$(seatf "$WS/Chief-of-Staff")" "$HOME/.claude/checkpoints"
hrow() { jq -cn --arg t "$(iso "$2")" --arg id "$1" '{type: "assistant", timestamp: $t, requestId: $id,
  message: {id: $id, model: "claude-haiku-5-5", usage: {input_tokens: 100000, output_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0}}}'; }
{ hrow m0 $((NOW - 3 * 86400)); hrow m1 $((NOW - 60)); } > "$(seatf "$MAIN")/m1.jsonl"
hrow c1 $((NOW - 30)) > "$(seatf "$WS/Chief-of-Staff")/c1.jsonl"
lt() { date -d "@$1" +%FT%T; }
CPD=$HOME/.claude/checkpoints
printf '%s\n' "$(lt $((NOW - 120))) restart: new pane h2 resumed from $CPD/m1.md; closing h1" \
  "$(lt $((NOW - 90))) restart: terminal create failed; old pane h2 left up, next stop retries" \
  "$(lt $((NOW - 80))) restart: new pane h9 resumed from $CPD/other.md; closing h8" \
  "$(lt $((NOW - 60))) restart: new pane h3 resumed from $CPD/m1.md; closing h2" > "$CPD/clear-hook.log"
echo '{"builder": {"clearLine": "160000"}, "chiefOfStaff": {"name": "Relay"}}' > "$MAIN/.claude/commandeck.json"
dash
check "main's card: context against its line, today's tokens and cost, the 7-day daily average, two restarts a minute apart" \
  '[100000,200000,100000,0.01,28571,0.0029,2,60]' \
  "$(jq -c 'first(.[]) | .seats.main | [.context, .line, .today.tokens, .today.usd, .avg7.tokens, .avg7.usd, .restarts, .restartGapSec]' "$T/out/run/project.json" 2>&1)"
check "main's restart times are today's two" 2 "$(jq -c 'first(.[]) | .seats.main.restartTimes | length' "$T/out/run/project.json" 2>&1)"
check "the relay's card: its own session today, no line, no restarts" '[100000,null,100000,0.01,0,null]' \
  "$(jq -c 'first(.[]) | .seats.relay | [.context, .line, .today.tokens, .today.usd, .restarts, .restartGapSec]' "$T/out/run/project.json" 2>&1)"
echo '{"builder": {"clearLine": "160000"}}' > "$MAIN/.claude/commandeck.json"
# Issue 240: an answer from the page whose send failed is kept by the host, and listed on this project's card only.
jq -cn --arg m "$MAIN" '[{main: $m, id: "ship-1999-01-01", to: "relay", args: []}, {main: "/elsewhere", id: "x-1999-01-01", to: "main", args: []}]' > "$T/out/answer-retry.json"
dash
check "an answer whose send failed is listed on its own project's card" '[{"id":"ship-1999-01-01","to":"relay"}]' \
  "$(jq -c 'first(.[]) | .needsOwner.unsent' "$T/out/run/project.json" 2>&1)"
check "with no relay configured there is no relay card" '[true,false]' \
  "$(jq -c 'first(.[]) | [(.seats.main | type == "object"), (.seats | has("relay"))]' "$T/out/run/project.json" 2>&1)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

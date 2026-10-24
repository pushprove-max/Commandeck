#!/usr/bin/env bash
# seat-launch.test.sh -- seat.sh launch, on the hand-written commandeck.json of fixtures/seat-setup.sh. What this
# pins: a typed pointer names its task; launch returns before the pane's tui-idle wait and a second launch meanwhile
# is refused; a unit planned in <unit>-plan opens there; and the maxBuilders cap counts other units' live Builders.
set -uo pipefail
. "$(dirname "$0")/fixtures/seat-setup.sh"
# The state these cases had from the ones now in seat-plan-marker.test.sh, by the same setup lines:
# pu's planning worktree with its plan, and the judge spec.
PWT=$HOME/orca/workspaces/proj/pu; git -C "$PROJ" worktree add -q "$PWT" && echo pu > "$(git -C "$PWT" rev-parse --absolute-git-dir)/commandeck-plan-of"
echo PLAN-DONE > "$T/screen"; mkdir -p "$PWT/.claude/plans"; echo 'the plan' > "$PWT/.claude/plans/pu.md"
printf 'Judge the plan.\nEnd on a line of its own.\n' > "$T/judge-spec.md"

# A seat Orca would not dispatch gets its pointer typed, and no preamble then names its task: the typed text
# carries the task id, so the seat's session can be tied to its task (read-verdict.sh --task).
rm -f "$T/pane-up" "$T/sent"; touch "$T/no-dispatch"
COMMANDECK_SEAT_FORCE=1 srun launch plan-judge-sol pu "$T/judge-spec.md" >"$T/out" 2>&1
check "a typed pointer ends with its task id" 'Task id task_1.' "$(grep -m1 'Your task spec' "$T/sent" 2>&1 | grep -o 'Task id task_1\.$')"
rm -f "$T/no-dispatch"

# Issue 233: launch wrote its record only after the tui-idle wait (up to 120 s) and the dispatch retries (60 s); a
# caller that timed out first left a live pane with no record, and its retry opened a second pane.
JREC=$(ls "$HOME/.commandeck/scratch/"*/seat-pu-plan-judge-sol.txt); touch "$T/slow-idle"; rm -f "$T/pane-up" "$T/titles"; : > "$T/creates"
# The pane's tui-idle wait lasts until the test removes slow-idle: a launch that waited on it would hit its timeout.
COMMANDECK_SEAT_FORCE=1 COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 seat_sh launch plan-judge-sol pu "$T/judge-spec.md" >"$T/out" 2>&1; RC=$?
check "launch returns while the pane's tui-idle wait still holds, naming the task and phase" "0:1" \
  "$RC:$(grep -c 'handle=h1 task=task_1 phase=launching' "$T/out")"
check "status shows launching meanwhile" "phase=launching handle=h1 task=task_1" "$(seat_sh status plan-judge-sol pu | cut -d' ' -f1-3)"
COMMANDECK_SEAT_FORCE=1 seat_sh launch plan-judge-sol pu "$T/judge-spec.md" >"$T/out" 2>&1
check "a second launch while the first is still launching is refused with its status, and opens no pane" "2:1:1" \
  "$?:$(grep -c 'REFUSED: plan-judge-sol for pu is still launching: phase=launching handle=h1' "$T/out"):$(grep -c . "$T/creates")"
BEFORE=$(cat "$T/titles" 2>/dev/null | grep -c .)
rm -f "$T/slow-idle"; settle pu plan-judge-sol
check "then status shows dispatched" "phase=dispatched" "$(seat_sh status plan-judge-sol pu | cut -d' ' -f1)"
# Issue 278: the agent retitles its pane as it starts, so the role and unit title is set once it is up.
check "the pane is titled with its role and unit only after the tui-idle wait" "0:Plan judge sol — pu" \
  "$BEFORE:$(cat "$T/titles" 2>/dev/null)"
rm -f "$T/pane-up"; : > "$T/creates"; touch "$T/no-title"
COMMANDECK_SEAT_FORCE=1 COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 run launch plan-judge-sol pu "$T/judge-spec.md" >"$T/out" 2>&1
check "an Orca without set-pane-title still launches, in one pane" "0:1:phase=dispatched" \
  "$?:$(grep -c . "$T/creates"):$(seat_sh status plan-judge-sol pu | cut -d' ' -f1)"
rm -f "$T/no-title"
rm -f "$T/pane-up"; touch "$T/no-dispatch" "$T/send-fails"
COMMANDECK_SEAT_FORCE=1 srun launch plan-judge-sol pu "$T/judge-spec.md" >"$T/out" 2>&1
check "a launch whose pointer cannot be sent ends phase=failed, and its log names the cause" "phase=failed:1" \
  "$(seat_sh status plan-judge-sol pu | cut -d' ' -f1):$(grep -c 'send failed to h1' "$JREC.log")"
rm -f "$T/no-dispatch" "$T/send-fails"

# A unit planned before 0.18.0 plans in its marked <unit>-plan, its plan not yet committed: a seat launched in a new
# <unit> cut from main read no plan.
LWT=$HOME/orca/workspaces/proj/pl-plan; git -C "$PROJ" worktree add -q "$LWT" && echo pl > "$(git -C "$LWT" rev-parse --absolute-git-dir)/commandeck-plan-of"
mkdir -p "$LWT/.claude/plans" && echo draft > "$LWT/.claude/plans/pl.md"; : > "$T/creates"
srun launch plan-judge-sol pl "$T/judge-spec.md" >"$T/out" 2>&1
check "a plan seat of a unit planned in <unit>-plan opens there, its record names it, and no <unit> is made" '0:1:1:no' \
  "$?:$(grep -c -- "path:$LWT " "$T/creates"):$(grep -cx 'worktree=pl-plan' "$HOME/.commandeck/scratch/"*/seat-pl-plan-judge-sol.txt):$([ -e "$HOME/orca/workspaces/proj/pl" ] && echo yes || echo no)"

# Issue 256: the owner caps how many Builders run at once (maxBuilders in /config), over all units. A Builder of
# another unit whose pane is connected counts; a launch at the cap opens no pane; with no cap nothing is counted.
cap() { jq -n --argjson o "$1" '{pluginConfigs: {"commandeck@commandeck": {options: $o}}}' > "$HOME/.claude/settings.json"; }
for u in b2 b3; do git -C "$PROJ" worktree add -q "$HOME/orca/workspaces/proj/seat-$u"; done
bl() { COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 run launch builder "seat-$1" "$T/spec.md" 2>&1; }
SCR=$(dirname "$JREC"); rm -f "$T/pane-up" "$T/screen" "$T/titles"; mkdir -p "$HOME/.claude"
printf 'path:/elsewhere/other\tBuilder — other\th9\t1\n' >> "$SCR/pane-titles.tsv"; echo '{"handle":"h9","agentIdentity":"claude"}' > "$T/extra"
cap '{}'; : > "$T/creates"; OUT=$(bl b2); RC=$?
check "with no cap a Builder launches beside another unit's, and no admission lock is taken" "0:1:no" \
  "$RC:$(grep -c . "$T/creates"):$([ -e "$SCR/builder-admission.lock" ] && echo yes || echo no)"
rm -f "$T/pane-up"; cap '{"maxBuilders": 1}'; : > "$T/creates"; OUT=$(bl b2); RC=$?
check "cap 1 with another unit's Builder live: refused, the count and its handle named, no pane opened" "2:1:0" \
  "$RC:$(grep -cx 'REFUSED: 1 Builders are running (h9), the maxBuilders cap in /config; close one or raise the cap' <<<"$OUT"):$(grep -c . "$T/creates")"
cap '{"maxBuilders": 2}'; OUT=$(bl b2); RC=$?
check "cap 2 with the same Builder live: it launches" "0:1" "$RC:$(grep -c . "$T/creates")"
rm -f "$T/pane-up"; : > "$T/creates"; for v in 0 '"two"'; do cap "{\"maxBuilders\": $v}"; OUT=$(bl b2); RC=$?
  check "a cap of $v refuses the launch and says to change it in /config" "2:1:0" "$RC:$(grep -c 'not a whole number of 1 or more; change it in /config' <<<"$OUT"):$(grep -c . "$T/creates")"; done
cap '{"maxBuilders": 2}'; touch "$T/list-fails"; OUT=$(bl b2); RC=$?; rm -f "$T/list-fails"
check "a pane list that cannot be read refuses under a cap, and says so" "1:1:0" "$RC:$(grep -c 'pane list could not be read' <<<"$OUT"):$(grep -c . "$T/creates")"
# A Builder whose agent exited back to its shell (agentIdentity null, past the start grace) holds no seat under the cap.
echo '{"handle":"h9","agentIdentity":null}' > "$T/extra"; cap '{"maxBuilders": 1}'; OUT=$(bl b2); RC=$?
check "cap 1 beside another unit's pane whose Builder exited: it launches" "0:1" "$RC:$(grep -c . "$T/creates")"
# The title registry lost: a Builder still counts by the title Orca lists for its pane.
rm -f "$T/pane-up"; : > "$T/creates"; mv "$SCR/pane-titles.tsv" "$T/titles.tsv"
echo '{"handle":"h8","title":"Builder — other","agentIdentity":"claude"}' > "$T/extra"; OUT=$(bl b2); RC=$?
check "cap 1 with no title registry and another Builder listed by title: refused, naming it" "2:1:0" \
  "$RC:$(grep -c 'REFUSED: 1 Builders are running (h8)' <<<"$OUT"):$(grep -c . "$T/creates")"
mkdir "$SCR/pane-titles.tsv"
OUT=$(bl b2); RC=$?
check "cap 1 with a title registry that cannot be read: refused, saying so" "1:1:0" "$RC:$(grep -c 'title registry' <<<"$OUT"):$(grep -c . "$T/creates")"
rmdir "$SCR/pane-titles.tsv"; mv "$T/titles.tsv" "$SCR/pane-titles.tsv"
# Two launches started together under cap 1, with no other Builder: the admission lock lets one count and open its
# pane before the other counts, so one pane opens and one launch is refused.
rm -f "$T/extra"; cap '{"maxBuilders": 1}'; : > "$T/creates"
bl b2 > "$T/o2" & bl b3 > "$T/o3" & wait
check "two launches together under cap 1 open one pane, and one is refused" "1:1" \
  "$(grep -c . "$T/creates"):$(cat "$T/o2" "$T/o3" | grep -c '^REFUSED: 1 Builders are running')"
rm -f "$T/pane-up"

# Issue 312: each judge's agent key picks its agent. On codex it is the read-only Codex sandbox; on claude the Claude
# overlay, Sonnet with Write, Edit and NotebookEdit denied. Two judges on Claude stay two seats with two records.
# The codex stand-in (issue 316): `codex sandbox <words> -- <cmd>` runs <cmd> as the sandboxed seat would (GH_SANDBOXED
# set), and every call is logged with the CODEX_HOME it saw.
cat > "$BIN/codex" <<EOF
#!/usr/bin/env bash
echo "\$*|CODEX_HOME=\${CODEX_HOME:-}" >> "$T/codex.log"
if [ "\${1:-}" = sandbox ]; then shift; while [ \$# -gt 0 ] && [ "\$1" != -- ]; do shift; done; shift; GH_SANDBOXED=1 exec "\$@"; fi
exit 0
EOF
chmod +x "$BIN/codex"
jq '.models += [{slug: "gpt-9.1-astra"}]' "$HOME/.codex/models_cache.json" > "$T/mc" && mv "$T/mc" "$HOME/.codex/models_cache.json"
jrec() { sed -n 's/^cmd=//p' "$HOME/.commandeck/scratch/"*/"seat-pu-$1.txt" | tail -1; }
for j in sol:planJudgeSol astra:planJudgeAstra; do
  r=plan-judge-${j%%:*} k=${j#*:}
  cap "{\"${k}Agent\": \"codex\"}"; rm -f "$T/pane-up"
  COMMANDECK_SEAT_FORCE=1 srun launch "$r" pu "$T/judge-spec.md" >"$T/out" 2>&1
  # Issue 316: the judge's network rides Codex's read-only permission profile; --sandbox would override that profile.
  check "$r on codex launches the read-only Codex profile with network, and no --sandbox" "0:1:1:0" \
    "$?:$(jrec "$r" | grep -c "codex --model gpt-9.1-${j%%:*} ."):$(jrec "$r" | grep -c 'permissions.ghread.network.enabled=true -c .default_permissions="ghread"'):$(jrec "$r" | grep -c -- '--sandbox')"
  cap "{\"${k}Agent\": \"claude\"}"; rm -f "$T/pane-up"
  COMMANDECK_SEAT_FORCE=1 srun launch "$r" pu "$T/judge-spec.md" >"$T/out" 2>&1
  check "$r on claude launches Claude Sonnet with Write, Edit and NotebookEdit denied (its record says so)" "0:1" \
    "$?:$(jrec "$r" | grep -c 'claude --model sonnet --effort high --disallowedTools Write,Edit,NotebookEdit')"
done
# Pass 8: a judge launched on its own --model needs no default model: with the Sol family's sources taken away one at
# a time (its cache entry, then the whole cache), the named model still launches.
cap '{"planJudgeSolAgent": "codex"}'
jq 'del(.models[] | select(.slug | endswith("-sol")))' "$HOME/.codex/models_cache.json" > "$T/mc" && mv "$T/mc" "$HOME/.codex/models_cache.json"
for gone in "the Sol cache entry" "the models cache"; do
  [ "$gone" = "the Sol cache entry" ] || rm -f "$HOME/.codex/models_cache.json"; rm -f "$T/pane-up"
  COMMANDECK_SEAT_FORCE=1 srun launch plan-judge-sol pu "$T/judge-spec.md" --model gpt-9.1-astra >"$T/out" 2>&1
  check "plan-judge-sol --model gpt-9.1-astra launches with $gone gone" "0:1" "$?:$(jrec plan-judge-sol | grep -c 'codex --model gpt-9.1-astra ')"
done
check "two judges on Claude are two seats with two records" "2:2" \
  "$(ls "$HOME/.commandeck/scratch/"*/seat-pu-plan-judge-{sol,astra}.txt | wc -l | tr -d ' '):$(cat "$HOME/.commandeck/scratch/"*/seat-pu-plan-judge-{sol,astra}.txt | grep -c '^role=plan-judge-')"

# Issue 315: a tool update rewrote another tool's hook in the Codex home, so its hash is stale and a Codex pane opens
# on "N hooks need review" and sits there. With trust-all off the launch ends phase=failed within the tui-idle wait and
# names the pane's blocked hooks and the fix; with it on, the launch trusts the hook again before the pane opens.
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"/opt/other/start-v2.sh"}]}]}}\n' > "$HOME/.codex/hooks.json"
printf '[hooks.state."%s:session_start:0:0"]\ntrusted_hash = "sha256:stale"\n' "$HOME/.codex/hooks.json" > "$HOME/.codex/config.toml"
trusted() { grep -c "^trusted_hash = \"sha256:stale\"" "$HOME/.codex/config.toml"; }
echo 'SessionStart hooks — 1 hooks need review before they can run' > "$T/screen"; rm -f "$T/pane-up"
COMMANDECK_SEAT_FORCE=1 srun launch plan-judge-sol pu "$T/judge-spec.md" --model gpt-9.1-astra >"$T/out" 2>&1
check "trust-all off: a pane on the review menu ends the launch phase=failed, the log names the count, the home and the hook" "phase=failed:1:1:1" \
  "$(seat_sh status plan-judge-sol pu | cut -d' ' -f1):$(grep -c "Codex pane blocked: 1 hooks need review in $HOME/.codex; run /hooks there or turn on trust-all" "$JREC.log"):$(grep -c 'start-v2.sh) is modified' "$JREC.log"):$(trusted)"
jq '.trustAllHooks = true' "$CFG" > "$T/cfg" && mv "$T/cfg" "$CFG"; echo 'Codex ready' > "$T/screen"; rm -f "$T/pane-up"
COMMANDECK_SEAT_FORCE=1 srun launch plan-judge-sol pu "$T/judge-spec.md" --model gpt-9.1-astra >"$T/out" 2>&1
check "trust-all on: the launch trusts the modified hook again before the pane opens, and the pane starts" "0:phase=dispatched" \
  "$(trusted):$(seat_sh status plan-judge-sol pu | cut -d' ' -f1)"
# Issue 314's update-prompt cases are in seat-update-prompt.test.sh (this file's time cap).

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

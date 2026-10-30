#!/usr/bin/env bash
# plan-tier.sh <batch-brief> -- the plan tier for a build, picked with no question to the owner (issue 345).
# Picks No plan, Plan + judge or Panel from the triggers in the project's .claude/plan-triggers.tsv, or the plugin's
# config/plan-triggers.tsv when the project has none, read against the batch's "The issues" and "The batch"
# sections. When unsure it goes one tier up: No plan only when every item line matches a none trigger. A seat off in
# /plugin config is no seat: plan-author off is No plan, one judge off leaves the other alone, and both off is One
# planner (the plan installs unjudged). Prints each seat that is off, the tier and the trigger that picked it, then
# each seat with the agent and model it runs on, and its effort (issue 345: main asks neither question, it reports these).
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/paths.sh"
BATCH=${1:?usage: plan-tier.sh <batch-brief>}
[ -s "$BATCH" ] || { echo "empty batch brief: $BATCH" >&2; exit 2; }
TRIG=$PP_MAIN/.claude/plan-triggers.tsv
[ -f "$TRIG" ] || TRIG=$HERE/../config/plan-triggers.tsv
# An edited file with a typo would quietly pick another tier, so it is refused.
BAD=$(awk -F'\t' '!/^#/ && NF && (NF != 3 || $1 !~ /^(panel|panel-always|none)$/) { print FNR; exit }' "$TRIG")
[ -z "$BAD" ] || { echo "REFUSED: $TRIG line $BAD is not '<panel, panel-always or none><tab><regex><tab><name>'" >&2; exit 2; }
PICK=$(awk -F'\t' '
  function pick(s,  i) { for (i = 1; i <= n; i++) if (tier[i] ~ /^panel/ && s ~ re[i]) { if (panel == "") panel = name[i]; if (tier[i] == "panel-always" && keep == "") keep = name[i] } }
  FNR == NR { if ($0 !~ /^#/ && NF) { n++; tier[n] = $1; re[n] = $2; name[n] = $3 }; next }
  /^#+ / { h = index($0, " ") - 1; if (on && h <= lv) on = 0; if (!on && $0 ~ /^#+ The (issues|batch)/) { on = 1; lv = h } else if (on) pick(tolower($0)); next }
  !on { next }
  { s = tolower($0); pick(s) }
  /^[0-9]+\. / { items++; for (i = 1; i <= n; i++) if (tier[i] == "none" && s ~ re[i]) { quiet++; none = name[i]; break } }
  END {
    if (panel != "") print "Panel\t" panel "\t" keep
    else if (items && quiet == items) print "No plan\t" none
    else if (quiet) print "Plan + judge\t" none " matched only some items, so one tier up"
    else print "Plan + judge\teverything else" }' "$TRIG" "$BATCH")
IFS=$'\t' read -r TIER WHY KEEP <<<"$PICK"
# Issue 362: a risky trigger on a small unit gets one judge, not two. The batch's "The batch" section may carry
# "Estimated size: ~<n> changed lines"; with none, or one at 150 or more, the Panel stands (one tier up when unsure).
# A panel-always trigger (new infrastructure) keeps the Panel at any size: its risk does not shrink with its lines.
EST=$(awk '/^#+ / { on = ($0 ~ /^#+ The batch/); next } on && match($0, /^Estimated size: ~[0-9]+ changed lines/) { s = substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", s); print s; exit }' "$BATCH")
if [ "$TIER" = Panel ] && [ -n "$EST" ] && [ "$((10#$EST))" -lt 150 ]; then
  if [ -n "$KEEP" ]; then WHY="$WHY; $KEEP keeps the panel under 150 changed lines"
  else TIER='Plan + judge' WHY="$WHY, a small unit (~$((10#$EST)) changed lines, under 150): one judge"; fi
fi
# Issue 479: a Panel unit estimated at config/routing.json's review-limits.oneJudgeLines or fewer changed lines gets the
# one judge the tier above picks, and stays Panel (its trigger stands); a panel-always trigger, no estimate or a bigger one keeps both.
ONEJ=
if [ "$TIER" = Panel ] && [ -n "$EST" ] && [ -z "$KEEP" ]; then
  LIM=$(pp_review_limit oneJudgeLines) || { echo "cannot read review-limits.oneJudgeLines from $(pp_routing)" >&2; exit 2; }
  if [ "$((10#$EST))" -le "$LIM" ]; then ONEJ=one WHY="$WHY; ~$((10#$EST)) changed lines, at most $LIM: one judge"; fi
fi
# on <role> -- the seat is on in /plugin config (issue 312); a value its Enabled key does not take stops here.
on() { local rc=0; pp_role_enabled "$1" 2>/dev/null || rc=$?; [ "$rc" != 2 ] || { pp_role_enabled "$1"; exit 2; }; return "$rc"; }
case ${ONEJ:-$TIER} in
  'No plan') SEATS=() ;;
  one|'Plan + judge') SEATS=(plan-author plan-judge-sol); on plan-judge-sol || SEATS=(plan-author plan-judge-fable) ;;
  *) SEATS=(plan-author plan-judge-fable plan-judge-sol) ;;
esac
# An author that is off is no plan; a judge that is off leaves the other to judge alone, and none leaves the plan unjudged.
OUT=()
for r in ${SEATS[@]+"${SEATS[@]}"}; do
  if on "$r"; then OUT+=("$r"); else echo "off: $r ($(pp_role_key "$r" enabled)=false in /plugin config)"; fi
done
if [ "$TIER" != 'No plan' ] && [[ " ${OUT[*]-} " != *" plan-author "* ]]; then TIER='No plan' WHY='plan-author is off in /plugin config'
elif [ "$TIER" != 'No plan' ] && [ "${#OUT[@]}" = 1 ]; then TIER='One planner' WHY="$WHY; every judge is off in /plugin config, so the plan installs unjudged"; fi
echo "tier: $TIER (trigger: $WHY; from $TRIG)"
[ "$TIER" != 'No plan' ] || { [[ $WHY == *' is off in '* ]] || WHY="Auto picked No plan: $WHY"; echo "launch: builder-launch.sh --skip-plan --reason '$WHY'"; exit 0; }
# Each seat launches under its own name, on its own agent, model and effort keys, so two judges stay two seats.
for r in "${OUT[@]}"; do
  S=$(pp_plan_seat "$r") || exit 2
  echo "seat: $S"
  echo "effort: $r $(pp_route_json "$r" | jq -r '.effort // "default"')"
done

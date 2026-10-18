#!/usr/bin/env bash
# plan-tier.sh <batch-brief> -- the Auto answer to "Write a plan first?", the default (owner's ruling 2026-10-17).
# Picks No plan, Plan + judge or Panel from the triggers in the project's .claude/plan-triggers.tsv, or the plugin's
# config/plan-triggers.tsv when the project has none, read against the batch's "The issues" and "The batch"
# sections. When unsure it goes one tier up: No plan only when every item line matches a none trigger. Prints the
# tier and the trigger that picked it, then each seat with the model it runs on among the models setup allows
# (pp_plan_seat says any model or seat used instead, on stderr). For Panel the owner is still asked which model
# writes the second plan.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/paths.sh"
BATCH=${1:?usage: plan-tier.sh <batch-brief>}
[ -s "$BATCH" ] || { echo "empty batch brief: $BATCH" >&2; exit 2; }
TRIG=$PP_MAIN/.claude/plan-triggers.tsv
[ -f "$TRIG" ] || TRIG=$HERE/../config/plan-triggers.tsv
# An edited file with a typo would quietly pick another tier, so it is refused.
BAD=$(awk -F'\t' '!/^#/ && NF && (NF != 3 || $1 !~ /^(panel|none)$/) { print FNR; exit }' "$TRIG")
[ -z "$BAD" ] || { echo "REFUSED: $TRIG line $BAD is not '<panel or none><tab><regex><tab><name>'" >&2; exit 2; }
PICK=$(awk -F'\t' '
  function pick(s,  i) { if (panel == "") for (i = 1; i <= n; i++) if (tier[i] == "panel" && s ~ re[i]) { panel = name[i]; break } }
  FNR == NR { if ($0 !~ /^#/ && NF) { n++; tier[n] = $1; re[n] = $2; name[n] = $3 }; next }
  /^#+ / { h = index($0, " ") - 1; if (on && h <= lv) on = 0; if (!on && $0 ~ /^#+ The (issues|batch)/) { on = 1; lv = h } else if (on) pick(tolower($0)); next }
  !on { next }
  { s = tolower($0); pick(s) }
  /^[0-9]+\. / { items++; for (i = 1; i <= n; i++) if (tier[i] == "none" && s ~ re[i]) { quiet++; none = name[i]; break } }
  END {
    if (panel != "") print "Panel\t" panel
    else if (items && quiet == items) print "No plan\t" none
    else if (quiet) print "Plan + judge\t" none " matched only some items, so one tier up"
    else print "Plan + judge\teverything else" }' "$TRIG" "$BATCH")
TIER=${PICK%%$'\t'*} WHY=${PICK#*$'\t'}
echo "tier: $TIER (trigger: $WHY; from $TRIG)"
case $TIER in
  'No plan') echo "launch: builder-launch.sh --skip-plan --reason 'Auto picked No plan: $WHY'"; exit 0 ;;
  'Plan + judge') SEATS=(plan-author plan-judge-sol) ;;
  *) SEATS=(plan-author plan-author-second plan-judge-astra plan-judge-sol) ;;
esac
for r in "${SEATS[@]}"; do
  S=$(pp_plan_seat "$r") || exit 2
  # Launched under its own name (seat.sh routes it as the other role), so two judges stay two seats.
  if [ "${S% *}" = "$r" ]; then echo "seat: $S"; else echo "seat: $r ${S#* } (as ${S% *})"; fi
  [ "$r" != plan-author-second ] || SECOND=${S#* }
done
[ "$TIER" != Panel ] || echo "ask the owner: which model writes the second plan? (default $SECOND; allowed: $(pp_plan_models))"

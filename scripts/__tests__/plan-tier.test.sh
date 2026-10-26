#!/usr/bin/env bash
# plan-tier.sh picks the plan tier, with no question to the owner, from the batch brief's "The issues" and "The batch"
# sections. A panel trigger in a sub-heading of those sections (### Authentication) is a trigger as much as one in a
# line of text: it picked nothing, so a security batch got one tier too low. The words of the section's own
# heading ("The batch") pick nothing.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd -P)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
git init -q -b main "$T/p" && git -C "$T/p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
run() { printf '%s\n' "$@" > "$T/brief.md"; (cd "$T/p" && env -u CLAUDE_PROJECT_DIR -u CLAUDE_CONFIG_DIR -u CODEX_HOME HOME="$T/home" PATH="$T/bin:$PATH" \
  COMMANDECK_MAIN="$T/p" COMMANDECK_SCRATCH="$T/scratch" bash "$REAL/scripts/plan-tier.sh" "$T/brief.md" 2>/dev/null); }
tier() { run "$@" | sed -n 's/^tier: \([^(]*\) (.*/\1/p'; }
seats() { run "$@" | sed -n 's/^seat: //p' | paste -sd, -; }
# Codex is installed and lists one model of each family, so a judge on Codex resolves.
mkdir -p "$T/bin" "$T/home/.codex" "$T/home/.claude"; printf '#!/bin/sh\nexit 0\n' > "$T/bin/codex"; chmod +x "$T/bin/codex"
echo '{"models":[{"slug":"gpt-6.1-sol"},{"slug":"gpt-6-astra"}]}' > "$T/home/.codex/models_cache.json"
opts() { jq -n --argjson o "$1" '{pluginConfigs: {"commandeck@commandeck": {options: $o}}}' > "$T/home/.claude/settings.json"; }
check "a panel word in a sub-heading of The batch picks Panel" "Panel" "$(tier '## The batch' '### Authentication' '1. rework the screen')"
check "the same brief with a plain sub-heading does not" "Plan + judge" "$(tier '## The batch' '### The screen' '1. rework the screen')"
check "a panel word in a sub-heading of The issues picks Panel" "Panel" "$(tier '## The issues' '### Password reset' '1. rework the screen')"
check "a panel word in a heading outside those sections picks nothing" "Plan + judge" "$(tier '## Notes' '### Authentication' '## The batch' '1. rework the screen')"
check "a panel word in an item line still picks Panel" "Panel" "$(tier '## The batch' '1. tighten the login check')"
# Issue 312: Panel is one author and two judges (no second author, no merge), each seat on its own agent key; a seat
# off in /plugin config is no seat, and plan-tier says so instead of planning it anyway.
PANEL=('## The batch' '1. tighten the login check') PJ=('## The batch' '1. rework the screen')
check "Panel: the author and both judges, each on its agent and model" \
  "plan-author claude opus,plan-judge-fable claude fable,plan-judge-sol codex gpt-6.1-sol" "$(seats "${PANEL[@]}")"
opts '{"planJudgeSolAgent": "claude"}'
check "a judge on claude runs as itself on the Claude overlay: still two judge seats" \
  "plan-author claude opus,plan-judge-fable claude fable,plan-judge-sol claude sonnet" "$(seats "${PANEL[@]}")"
opts '{"planAuthorEnabled": false}'
check "plan-author off: No plan, with the skip line naming why" "No plan|1" \
  "$(tier "${PJ[@]}")|$(run "${PJ[@]}" | grep -cxF "launch: builder-launch.sh --skip-plan --reason 'plan-author is off in /plugin config'")"
opts '{"planJudgeSolEnabled": false}'
check "sol off: Plan + judge runs the fable judge" "Plan + judge|plan-author claude opus,plan-judge-fable claude fable" \
  "$(tier "${PJ[@]}")|$(seats "${PJ[@]}")"
check "sol off: Panel runs fable alone" "plan-author claude opus,plan-judge-fable claude fable" "$(seats "${PANEL[@]}")"
opts '{"planJudgeSolEnabled": false, "planJudgeFableEnabled": false}'
check "both judges off: One planner, the plan unjudged, said" "One planner|plan-author claude opus|1" \
  "$(tier "${PANEL[@]}")|$(seats "${PANEL[@]}")|$(run "${PANEL[@]}" | grep -c 'so the plan installs unjudged')"
opts '{"planJudgeSolAgent": "gemini"}'
check "a value a key does not take stops plan-tier, naming the key" "2 1" \
  "$(printf '%s\n' "${PJ[@]}" > "$T/brief.md"; cd "$T/p" && env -u CLAUDE_CONFIG_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/p" \
    bash "$REAL/scripts/plan-tier.sh" "$T/brief.md" >/dev/null 2>"$T/err"; echo $?) $(grep -c 'REFUSED: /plugin config planJudgeSolAgent = gemini' "$T/err")"
rm -f "$T/bin/codex"; opts '{}'
check "a judge on Codex where no codex is installed is refused, naming the keys that move it" 1 \
  "$(run "${PJ[@]}" >/dev/null; printf '%s\n' "${PJ[@]}" > "$T/brief.md"; cd "$T/p" && env -u CLAUDE_CONFIG_DIR HOME="$T/home" PATH="$T/bin:/usr/bin:/bin:$(dirname "$(command -v jq)")" \
    COMMANDECK_MAIN="$T/p" bash "$REAL/scripts/plan-tier.sh" "$T/brief.md" 2>&1 >/dev/null | grep -c 'planJudgeSolAgent=claude, or planJudgeSolEnabled=false')"
# Issue 345: main asks no "Which model and effort?" question, so each seat's effort is printed under its seat line.
efforts() { run "$@" | sed -n 's/^effort: //p' | paste -sd, -; }
# The judges run on Codex: put back the stub the case above removed, or a host with no codex prints plan-author alone.
printf '#!/bin/sh\nexit 0\n' > "$T/bin/codex"; chmod +x "$T/bin/codex"; opts '{}'
check "each seat prints its configured effort, so main can say what it picked" \
  "plan-author high,plan-judge-fable high,plan-judge-sol high" "$(efforts "${PANEL[@]}")"
opts '{"planAuthorEffort": "medium"}'
check "an effort set in /plugin config is the one printed" "plan-author medium" "$(efforts "${PJ[@]}" | cut -d, -f1)"
# Issue 362: a risky trigger on a small unit gets one judge; the estimate is the batch's own line, and without one the
# Panel stands.
opts '{}'
check "a security batch estimated at ~120 changed lines gets one judge, and the reason says why" "Plan + judge|plan-author claude opus,plan-judge-sol codex gpt-6.1-sol|1" \
  "$(tier "${PANEL[@]}" 'Estimated size: ~120 changed lines')|$(seats "${PANEL[@]}" 'Estimated size: ~120 changed lines')|$(run "${PANEL[@]}" 'Estimated size: ~120 changed lines' | grep -c 'a small unit (~120 changed lines, under 150): one judge')"
check "estimated at ~200 it stays Panel" "Panel" "$(tier "${PANEL[@]}" 'Estimated size: ~200 changed lines')"
check "estimated at exactly ~150 it stays Panel" "Panel" "$(tier "${PANEL[@]}" 'Estimated size: ~150 changed lines')"
check "with no estimate it stays Panel" "Panel" "$(tier "${PANEL[@]}")"
check "an estimate outside The batch is not read" "Panel" "$(tier '## Notes' 'Estimated size: ~120 changed lines' "${PANEL[@]}")"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

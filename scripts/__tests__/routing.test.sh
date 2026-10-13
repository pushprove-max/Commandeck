#!/usr/bin/env bash
# config/routing.json ships to other people's machines, so it names model
# families only: a pinned version goes stale the day a newer one ships, and a
# [1m] context bills a plan that may not have it. The five roles are the ones
# the Builder flow launches; a missing one stops a launch or a review pass.
# The resolver in paths.sh accepts versions and contexts (the source project
# uses both), so those two rules are checked here.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
CFG=$REAL/config/routing.json
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
. "$REAL/scripts/paths.sh" || exit 1
RT_READONLY=

# lint <file> -- 0 when the file holds the five roles, families only, no context.
lint() {
  jq -e '
    (["orchestrator", "builder", "codex-reviewer", "claude-reviewer", "design-coauthor"] - (.roles | keys) | length == 0)
    and ([.roles[] | .model, (.advisor // "x") | test("^[a-z]+$")] | all)
    and ([.roles[] | has("context")] | any | not)' "$1" >/dev/null 2>&1
}
valid() { COMMANDECK_ROUTING=$1 pp_routing_valid >/dev/null 2>&1; echo $?; }
mutant() { jq "$1" "$CFG" > "$TMP/m.json"; }

# A Codex family resolves against the account's model list at launch; the
# fixture list stands in for it.
export CODEX_HOME=$TMP/codex; mkdir -p "$CODEX_HOME"
printf '{"models":[{"slug":"gpt-7.2-sol"},{"slug":"gpt-7.10-sol"},{"slug":"gpt-8-luna"}]}\n' > "$CODEX_HOME/models_cache.json"
check "the shipped file validates in the resolver" 0 "$(valid "$CFG")"
check "the shipped file passes the lint" 0 "$(lint "$CFG"; echo $?)"
for r in builder codex-reviewer claude-reviewer orchestrator design-coauthor; do
  RT_AGENT= RT_MODEL= RT_EFFORT=
  COMMANDECK_ROUTING=$CFG pp_route "$r" 2>/dev/null
  check "$r resolves an agent and a model" yes "$([ -n "$RT_AGENT" ] && [ -n "$RT_MODEL" ] && echo yes || echo no)"
done
COMMANDECK_ROUTING=$CFG pp_route codex-reviewer; check "codex-reviewer is a Codex seat" codex "$RT_AGENT"
check "a Codex pane launches on the family's newest model id, never the bare family" "gpt-7.10-sol 1" \
  "$RT_MODEL $(grep -c -- '--model gpt-7.10-sol ' <<<"$RT_CMD ")"
check "a family the account does not list stops the launch" 2 "$(CODEX_HOME=$TMP/none COMMANDECK_ROUTING=$CFG pp_route codex-reviewer >/dev/null 2>&1; echo $?)"
check "an explicit model override is used as written" gpt-1-x "$(COMMANDECK_ROUTING=$CFG pp_route_json codex-reviewer "" gpt-1-x | jq -r .model)"
check "codex-reviewer carries an effort" yes "$([ -n "$RT_EFFORT" ] && echo yes || echo no)"
check "codex-reviewer is read-only" 1 "$RT_READONLY"
COMMANDECK_ROUTING=$CFG pp_route claude-reviewer; check "claude-reviewer is a Claude seat" claude "$RT_AGENT"
check "claude-reviewer runs at high effort" high "$RT_EFFORT"
check "claude-reviewer is read-only" 1 "$RT_READONLY"
REVIEWER_MODEL=$RT_MODEL
check "claude-reviewer is headless" 'claude -p' "$(COMMANDECK_ROUTING=$CFG pp_argv claude-reviewer | paste -sd' ' - | grep -o 'claude -p')"
COMMANDECK_ROUTING=$CFG pp_route builder
check "the Claude reviewer is a different family than the Builder" yes "$([ "$REVIEWER_MODEL" != "$RT_MODEL" ] && echo yes || echo no)"
check "no role is boxed: the pane box is not part of the plugin" 0 "$(jq '[.roles[] | select((.headless or .unboxed) | not)] | length' "$CFG")"

mutant '.roles.builder.model = "claude-opus-5-5"'
check "a version-suffixed Claude model fails" 1 "$(lint "$TMP/m.json"; echo $?)"
mutant '.roles["codex-reviewer"].model = "gpt-6.1-sol"'
check "a version-suffixed Codex model fails" 1 "$(lint "$TMP/m.json"; echo $?)"
mutant '.roles.builder.advisor = "claude-fable-5-1"'
check "a version-suffixed advisor fails" 1 "$(lint "$TMP/m.json"; echo $?)"
for r in orchestrator builder; do
  mutant ".roles[\"$r\"].context = \"1m\""
  check "a 1m context on $r still validates in the resolver" 0 "$(valid "$TMP/m.json")"
  check "a 1m context on $r fails the lint" 1 "$(lint "$TMP/m.json"; echo $?)"
done
for r in orchestrator builder codex-reviewer claude-reviewer design-coauthor; do
  mutant "del(.roles[\"$r\"])"
  check "a file without $r fails" 1 "$(lint "$TMP/m.json"; echo $?)"
done

# A leak word in a note fails the leak test, which reads the word list itself.
mkdir -p "$TMP/tree/config"
cp "$CFG" "$TMP/tree/config/routing.json"
check "the shipped notes are clean" 0 "$(bash "$REAL/ci/leak-test.sh" "$TMP/tree" >/dev/null 2>&1; echo $?)"
N=0
for w in 'Push''Prove' 'M''ax ruling' 'see #''1481'; do
  N=$((N + 1))
  jq --arg w "$w" '.roles.builder.note += " " + $w' "$CFG" > "$TMP/tree/config/routing.json"
  check "leak word $N in a note fails" 1 "$(bash "$REAL/ci/leak-test.sh" "$TMP/tree" >/dev/null 2>&1; echo $?)"
done

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

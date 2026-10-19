#!/usr/bin/env bash
# UserPromptSubmit hook, Chief-of-Staff pane only. Orca tells a pane "You have N
# orchestration messages. Run `orca orchestration check --run <run>`." for the
# messages it sent to the run itself too, and the relay spent a whole turn
# reading back its own sends. When every message of that batch is this pane's
# own, the batch is acknowledged and the prompt dropped. Any other prompt, pane
# or batch, and any Orca or jq failure, passes.
#
# Self-tests: bash scripts/run-shell-tests.sh hooks/__tests__/cos-own-echo.test.sh
set -uo pipefail

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# The cheap test first: this runs on every prompt in every pane.
[[ $INPUT == *"orchestration message"* ]] || exit 0
P=$(jq -r '.prompt // empty' <<<"$INPUT" 2>/dev/null)
RE='^[[:space:]]*You have [0-9]+ orchestration messages?\. Run `orca(-ide)? orchestration check --run (run_[A-Za-z0-9]+)`\.?[[:space:]]*$'
[[ $P =~ $RE ]] || exit 0
RUN=${BASH_REMATCH[2]}
ROOT=${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null)}
GITDIR=$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-dir 2>/dev/null) || exit 0
COMMON=$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
TOP=$(git -C "${ROOT:-.}" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ "$GITDIR" != "$COMMON" ] && [ "${TOP##*/}" = Chief-of-Staff ] || exit 0
H=${ORCA_TERMINAL_HANDLE:-}
[ -n "$H" ] || exit 0
OUT=$(timeout 10 orca-ide orchestration check --run "$RUN" --json 2>/dev/null) || exit 0
N=$(jq -er --arg h "$H" '.result.messages | select(type == "array" and length > 0 and all(.[]; .from_handle == $h)) | length' <<<"$OUT" 2>/dev/null) || exit 0
D=$(jq -er '.result.deliveryId | strings' <<<"$OUT" 2>/dev/null) || exit 0
timeout 10 orca-ide orchestration check --run "$RUN" --ack "$D" --peek --json >/dev/null 2>&1 || exit 0
jq -cn --arg n "$N" '{decision: "block", reason: "dropped Orca'"'"'s echo of this pane'"'"'s own \($n) message(s); no turn spent"}'

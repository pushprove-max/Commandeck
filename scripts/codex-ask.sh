#!/usr/bin/env bash
# codex-ask.sh [--timeout <s>] '<question>'   (the question on stdin when the argument is -)
# Issue 399: a read-only Codex helper for a Builder, a plan author or a fix round. It asks the review pass's own Codex
# (pp_route codex-reviewer) one question from outside the repository, in a read-only sandbox that still reads the
# worktree by absolute path, and prints the answer under a line naming the model that gave it. Every call, failed or
# not, is one row in <main>/.claude/metrics/codex-helper.jsonl. Judge and reviewer panes are refused.
set -uo pipefail
usage() { echo "usage: codex-ask.sh [--timeout <seconds, 1-1800>] '<question>'  (or - for the question on stdin)" >&2; exit 2; }
case "${1:-}" in --help|-h) (usage) 2>&1; exit 0 ;; esac
SECS=300
if [ "${1:-}" = --timeout ]; then
  [ $# -ge 3 ] && [[ $2 =~ ^[1-9][0-9]*$ ]] && [ "$2" -le 1800 ] || usage
  SECS=$2; shift 2
fi
[ $# -eq 1 ] || usage
Q=$1
[ "$Q" != - ] || Q=$(cat)
[ -n "${Q//[[:space:]]/}" ] || usage

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$HERE/paths.sh" || exit 1
# shellcheck disable=SC1091
. "$HERE/../hooks/lib/helper-pane.sh"
is_helper_pane || { echo "REFUSED: codex-ask.sh is for Builder, plan-author and fix-round panes; this pane is ${COMMANDECK_SEAT:-not a helper pane}" >&2; exit 2; }
pp_route codex-reviewer || exit 2
[ "$RT_AGENT" = codex ] || { echo "REFUSED: the review passes run on Claude here, so there is no Codex helper" >&2; exit 2; }

WT=$(git rev-parse --show-toplevel 2>/dev/null) || WT=$PWD
UNIT=$(basename "$WT")
ROWS=$PP_MAIN/.claude/metrics/codex-helper.jsonl
WORK=$(mktemp -d) || { echo "codex-ask: FAILED: cannot make a temp folder" >&2; exit 1; }
trap 'pp_rm_rf "$WORK"' EXIT
ANS=$WORK/answer ERR=$WORK/stderr
: > "$ANS"

PROMPT="You are a read-only helper for the repository at $WT. Read it by absolute path; you cannot write, and must not try. Answer in at most 6000 characters, plain text. Question: $Q"
pp_codex_retrust
START=$(date -u +%Y-%m-%dT%H:%M:%SZ) T0=$SECONDS RC=0
# Outside the repository, Codex never discovers its .codex/config.toml, hooks or rules; the sandbox is always read-only.
(cd "$WORK" && PATH="$PP_SCRIPTS/codex-no-helpers:$PATH" timeout -k 2 "$SECS" codex exec --ephemeral --skip-git-repo-check -s read-only \
  -m "$RT_MODEL" -c "model_reasoning_effort=\"$RT_EFFORT\"" -o "$ANS" "$PROMPT") </dev/null >/dev/null 2>"$ERR" || RC=$?
ELAPSED=$((SECONDS - T0))
# The first model: line of Codex's stderr header; --json events carry none.
MODEL=$(sed -n 's/^model: *//p' "$ERR" | head -1 | sed 's/[[:space:]]*$//')
BYTES=$(wc -c < "$ANS" | tr -d ' ')

record() { # <outcome> -- one >> append of one line under 4 KB; a torn last line gets a fresh one
  local row lead=
  row=$(jq -nc --arg unit "$UNIT" --arg seat "${COMMANDECK_SEAT:-builder}" --arg model "$MODEL" --arg start "$START" \
    --argjson secs "$ELAPSED" --arg outcome "$1" --argjson bytes "$BYTES" \
    '{unit: $unit, seat: $seat, model: (if $model == "" then null else $model end), start: $start, secs: $secs, outcome: $outcome, bytes: $bytes}')
  mkdir -p "$(dirname "$ROWS")" 2>/dev/null
  [ -s "$ROWS" ] && [ -n "$(tail -c1 "$ROWS" 2>/dev/null)" ] && lead=$'\n'
  { printf '%s%s\n' "$lead" "$row" >> "$ROWS"; } 2>/dev/null || echo "codex-ask: warning: call not recorded in $ROWS" >&2
}
fail() { # <outcome> <message>
  record "$1"; echo "codex-ask: $2" >&2; exit 1
}

if [ "$RC" = 124 ]; then
  fail timeout "TIMEOUT: no answer within $SECS s"
elif [ "$RC" = 137 ] && [ "$ELAPSED" -ge "$SECS" ]; then
  fail killed "TIMEOUT: no answer within $SECS s; Codex ignored TERM and was killed after the 2 s grace"
elif [ "$RC" != 0 ]; then
  fail failed "FAILED: Codex exited $RC: $(grep . "$ERR" | tail -1)"
elif ! grep -q '[^[:space:]]' "$ANS"; then
  fail empty "FAILED: Codex returned an empty answer"
elif [ -z "$MODEL" ]; then
  fail no-model "FAILED: Codex printed no model: header on stderr, so the model that answered is not known; the answer is not used"
fi
record answered
printf 'codex-ask: model %s, %s s\n' "$MODEL" "$ELAPSED"
head -c 6000 "$ANS"
[ "$BYTES" -le 6000 ] || printf '\ncodex-ask: answer cut at 6000 of %s bytes\n' "$BYTES"
exit 0

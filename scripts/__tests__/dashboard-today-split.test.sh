#!/usr/bin/env bash
# Issue 421: /units shows the dashboard's own Cost today for the project, split by where it was spent. The collector
# keys each of the day's requests by its recorded folder against the project's three roots (main checkout, worktree
# folder, closing-copy folder), by path strings alone: no folder below is created, so a removed unit keeps its name.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home" "$T/cache" "$T/projects" "$T/sessions" "$T/cx-only/projects" "$T/cx-only/sessions"
NOON=$(date -d 'today 12:00' +%s); iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
R=$T/r
# One Haiku request (one cent) and one Codex request per folder at noon; one more in the unit's worktree yesterday.
crow() { jq -cn --arg t "$(iso "$2")" --arg id "$1" --arg w "$3" '{type: "assistant", timestamp: $t, cwd: $w, requestId: $id,
  message: {id: $id, model: "claude-haiku-5-5", usage: {input_tokens: 100000, output_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0}}}'; }
xrow() { jq -cn --arg t "$(iso "$2")" --arg w "$3" '{type: "session_meta", timestamp: $t, payload: {cwd: $w}}'
  jq -cn --arg t "$(iso "$2")" '{type: "turn_context", timestamp: $t, payload: {model: "gpt-6.1-sol"}}'
  jq -cn --arg t "$(iso "$2")" --arg id "$1" '{type: "token_usage_record", timestamp: $t,
    payload: {response_id: $id, usage: {input_tokens: 100000, cached_input_tokens: 0, cache_write_input_tokens: 0, output_tokens: 0}}}'; }
i=0
for f in main ws/u ws/u/subdir ws/u-plan scratch/closing-copy/u scratch/closing-copy/merged-u ws/Fast-lane; do
  i=$((i + 1)); crow "c$i" "$NOON" "$R/$f" > "$T/projects/s$i.jsonl"; xrow "x$i" "$NOON" "$R/$f" > "$T/sessions/rollout-$i.jsonl"
done
crow c-old $((NOON - 86400)) "$R/ws/u" > "$T/projects/old.jsonl"
# Another project's spend today is neither in this project's total nor in its split.
crow c-q "$NOON" "$T/q" > "$T/projects/q.jsonl"; xrow x-q "$NOON" "$T/q" > "$T/sessions/rollout-q.jsonl"
ROOTS="{\"p\":[\"$R/main\",\"$R/ws\",\"$R/scratch/closing-copy\"]}"
build() { (cd "$ROOT/scripts" && HOME="$T/home" python3 -B dashboard_limit.py build missing /nonexistent $((NOON + 3600)) "$T/cache" "$1/projects" "$1/sessions" "$ROOTS" 2>&1); }
OUT=$(build "$T")
DAY=$(jq -c '.today.p' <<<"$OUT" 2>&1)
r6() { jq -r "$1 * 1e6 | round" <<<"$DAY" 2>&1; }
ONE=$(r6 '.byFolder[":main"]'); [[ $ONE =~ ^[1-9][0-9]*$ ]] || { echo "no :main spend in [$DAY]"; ONE=1; }
check "byFolder sums to the day's total and leaves yesterday out" "$(r6 .spentUsd) $((ONE * 7))" "$(r6 '[.byFolder[]] | add') $(r6 .spentUsd)"
check "a nested folder, a plan worktree and a removed unit's closing copy count under their unit by path alone" \
  ':main,Fast-lane,merged-u,u 4 1 1' \
  "$(jq -r --argjson one "$ONE" '.byFolder as $b | [($b | keys | join(",")), (["u", "merged-u", "Fast-lane"][] | ($b[.] // 0) * 1e6 | round / $one | round)] | join(" ")' <<<"$DAY" 2>&1)"
# The issue's Codex question for the day split: a review run in the unit's closing copy is the unit's spend.
xrow x-cc "$NOON" "$R/scratch/closing-copy/u" > "$T/cx-only/sessions/rollout.jsonl"
CX=$(build "$T/cx-only" | jq -c '.today.p' 2>&1)
check "a unit's Codex review in its closing copy counts under the unit" 'true ["u"]' \
  "$(jq -c '(.codexUsd > 0 and .byFolder.u == .spentUsd), (.byFolder | keys)' <<<"$CX" | paste -sd' ' -)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

#!/usr/bin/env bash
# Contract test for whole-workflow token accounting. Static fixture trees make
# missing telemetry distinguishable from a genuine zero.
set -u
ROOT=$(git rev-parse --show-toplevel)
SCRIPT="$ROOT/scripts/token-ledger.sh"
FIX="$ROOT/scripts/__tests__/fixtures/token-ledger"
export COMMANDECK_WORKSPACES=/fixture/ws # the workspaces root every fixture cwd and project folder names
# A ledger run in a main checkout of its own (not the plugin's), with no pane project set.
unset CLAUDE_PROJECT_DIR
MAIN_BOX=$(mktemp -d); mkdir "$MAIN_BOX/main"; git -C "$MAIN_BOX/main" init -q; cd "$MAIN_BOX/main" || exit 1
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1"; fi; }

OUT=$(TOKEN_LEDGER_CLAUDE_ROOT="$FIX/claude" \
  TOKEN_LEDGER_MAIN_PROJECT="$FIX/main" \
  TOKEN_LEDGER_CODEX_ROOTS="$FIX/codex" \
  TOKEN_LEDGER_BRIEFS="$FIX/briefs" \
  "$SCRIPT" --main u1)

# A Claude pane that reports usage but whose total is dropped or summed wrongly.
check "Claude totals are a unit row" 0 \
  "$(printf '%s\n' "$OUT" | grep -q '^row unit=u1 source=claude uncached=16 cache_create=28 cache_read=40 output=52 reasoning="not recorded" turns=3$' && echo 0 || echo 1)"
# Main's tokens folded into a unit's row, hiding what the unit cost.
check "main is a separate row" 0 \
  "$(printf '%s\n' "$OUT" | grep -q '^row unit=main source=main uncached=9 cache_create=8 cache_read=7 output=6 reasoning="not recorded" turns=1$' && echo 0 || echo 1)"
# A Codex session not matched to its unit by cwd, so the unit shows no Codex usage.
check "Codex totals follow the worktree cwd" 0 \
  "$(printf '%s\n' "$OUT" | grep -q '^row unit=u1 source=codex uncached=40 cache_create="not recorded" cache_read=60 output=20 reasoning="not recorded" turns=1$' && echo 0 || echo 1)"
# A field Codex did not record reported as 0, which reads as free.
check "missing Codex fields are not reported as zero" 0 \
  "$(printf '%s\n' "$OUT" | grep -q 'source=codex.*reasoning="not recorded"' && echo 0 || echo 1)"
# A class budget derived from a distribution that lacks one of turns, compactions or output.
check "distribution includes median and max for all three dimensions" 0 \
  "$(printf '%s\n' "$OUT" | grep -q '^distribution unit=u1 classes=gate-ci panes=2 turns_median=1.5 turns_max=2 compactions_median=0.5 compactions_max=1 output_median=26 output_max=44' && echo 0 || echo 1)"
# No pane row for the budget command, so context and compactions go unmeasured.
check "pane measurements expose context to the budget command" 2 \
  "$(printf '%s\n' "$OUT" | grep -c '^pane unit=u1 ')"
# A cost invented when no rate file exists.
check "cost stays missing without a rate file" 0 \
  "$(printf '%s\n' "$OUT" | grep -q '^cost=missing$' && echo 0 || echo 1)"

OUT=$(PATH="$FIX/bin:/usr/bin:/bin" TOKEN_LEDGER_CLAUDE_ROOT="$FIX/claude" \
  TOKEN_LEDGER_MAIN_PROJECT="$FIX/main" TOKEN_LEDGER_CODEX_ROOTS="$FIX/codex" \
  TOKEN_LEDGER_BRIEFS="$FIX/briefs" TOKEN_LEDGER_STATUS_ROOT="$FIX/status" \
  "$BASH" "$SCRIPT" --waits waits u1)
# A PR open-to-merge wait reported in the wrong unit or not at all.
check "PR wait is measured in seconds" 0 \
  "$(printf '%s\n' "$OUT" | grep -q '^waits unit=u1 pr_open_to_merge=600$' && echo 0 || echo 1)"

EMPTY=$(mktemp -d); trap 'rm -rf "$EMPTY" "$MAIN_BOX"' EXIT

# A transcript modified after --since still holds older records; only the
# post-boundary records may count, or old usage inflates the class budgets.
PANE="$EMPTY/claude/-fixture-ws-u2"
mkdir -p "$PANE" "$EMPTY/codex"
cat > "$PANE/long.jsonl" <<'EOF'
{"type":"assistant","timestamp":"2026-09-01T00:00:00Z","message":{"usage":{"input_tokens":1,"cache_creation_input_tokens":1,"cache_read_input_tokens":1,"output_tokens":100}}}
{"type":"assistant","timestamp":"2026-09-10T00:00:00Z","message":{"usage":{"input_tokens":2,"cache_creation_input_tokens":3,"cache_read_input_tokens":4,"output_tokens":7}}}
EOF
cat > "$EMPTY/codex/u2.jsonl" <<'EOF'
{"type":"session_meta","timestamp":"2026-09-01T00:00:00Z","payload":{"cwd":"/fixture/ws/u2"}}
{"type":"event_msg","timestamp":"2026-09-01T00:00:01Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":50,"cached_input_tokens":20,"output_tokens":100}}}}
{"type":"event_msg","timestamp":"2026-09-10T00:00:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":80,"cached_input_tokens":30,"output_tokens":130}}}}
EOF
OUT=$(TOKEN_LEDGER_CLAUDE_ROOT="$EMPTY/claude" TOKEN_LEDGER_MAIN_PROJECT="$EMPTY/main" \
  TOKEN_LEDGER_CODEX_ROOTS="$EMPTY/codex" TOKEN_LEDGER_BRIEFS="$FIX/briefs" \
  "$SCRIPT" --since 2026-09-05 u2)
check "--since drops Claude records before the boundary" 0 \
  "$(printf '%s\n' "$OUT" | grep -q '^row unit=u2 source=claude uncached=2 cache_create=3 cache_read=4 output=7 reasoning="not recorded" turns=1$' && echo 0 || echo 1)"
check "--since counts only Codex usage after the boundary" 0 \
  "$(printf '%s\n' "$OUT" | grep -q '^row unit=u2 source=codex uncached=20 cache_create="not recorded" cache_read=10 output=30 reasoning="not recorded" turns=1$' && echo 0 || echo 1)"

# A closing pass reviews in a copy under the scratch (builder-codex-pass.sh): its tokens are the unit's, never dropped.
mkdir -p "$EMPTY/codex-closing"
cat > "$EMPTY/codex-closing/u2.jsonl" <<'EOF'
{"type":"session_meta","timestamp":"2026-09-10T00:00:00Z","payload":{"cwd":"/fixture/scratch/closing-copy/u2"}}
{"type":"event_msg","timestamp":"2026-09-10T00:00:01Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":80,"cached_input_tokens":30,"output_tokens":130}}}}
EOF
OUT=$(COMMANDECK_SCRATCH=/fixture/scratch TOKEN_LEDGER_CLAUDE_ROOT="$EMPTY/claude" TOKEN_LEDGER_MAIN_PROJECT="$EMPTY/main" \
  TOKEN_LEDGER_CODEX_ROOTS="$EMPTY/codex-closing" TOKEN_LEDGER_BRIEFS="$FIX/briefs" \
  "$SCRIPT" u2)
check "Codex usage from the unit's closing-copy folder counts as the unit's" 0 \
  "$(printf '%s\n' "$OUT" | grep -q '^row unit=u2 source=codex uncached=50 .*output=130 ' && echo 0 || echo 1)"

# One reply is one transcript line per content block, each repeating the
# reply's usage. Counting lines inflated every class's measured turn
# budget and multiplied its tokens.
PANE3="$EMPTY/claude/-fixture-ws-u3"
mkdir -p "$PANE3"
cat > "$PANE3/split.jsonl" <<'EOF'
{"type":"assistant","timestamp":"2026-09-10T00:00:00Z","message":{"id":"msg_a","usage":{"input_tokens":1,"cache_creation_input_tokens":2,"cache_read_input_tokens":3,"output_tokens":4}}}
{"type":"assistant","timestamp":"2026-09-10T00:00:01Z","message":{"id":"msg_a","usage":{"input_tokens":1,"cache_creation_input_tokens":2,"cache_read_input_tokens":3,"output_tokens":4}}}
{"type":"assistant","timestamp":"2026-09-10T00:00:02Z","message":{"id":"msg_a","usage":{"input_tokens":1,"cache_creation_input_tokens":2,"cache_read_input_tokens":3,"output_tokens":9}}}
{"type":"assistant","timestamp":"2026-09-10T00:00:03Z","message":{"id":"msg_b","usage":{"input_tokens":1,"cache_creation_input_tokens":1,"cache_read_input_tokens":1,"output_tokens":1}}}
EOF
OUT=$(TOKEN_LEDGER_CLAUDE_ROOT="$EMPTY/claude" TOKEN_LEDGER_MAIN_PROJECT="$EMPTY/main" \
  TOKEN_LEDGER_CODEX_ROOTS="$EMPTY/codex" TOKEN_LEDGER_BRIEFS="$FIX/briefs" \
  "$SCRIPT" u3)
check "a reply split over lines is one turn, its usage counted once" 0 \
  "$(printf '%s\n' "$OUT" | grep -q '^row unit=u3 source=claude uncached=2 cache_create=3 cache_read=4 output=10 reasoning="not recorded" turns=2$' && echo 0 || echo 1)"

printf '#!/bin/sh\nexit 127\n' > "$EMPTY/gh"; chmod +x "$EMPTY/gh"
OUT=$(PATH="$EMPTY:/usr/bin:/bin" TOKEN_LEDGER_CLAUDE_ROOT="$FIX/claude" \
  TOKEN_LEDGER_MAIN_PROJECT="$FIX/main" TOKEN_LEDGER_CODEX_ROOTS="$FIX/codex" \
  TOKEN_LEDGER_BRIEFS="$FIX/briefs" TOKEN_LEDGER_STATUS_ROOT="$EMPTY" \
  "$BASH" "$SCRIPT" --waits absent u1)
# A failing gh turning every wait into 0 or a crash instead of "not recorded".
check "unavailable gh records every wait as missing" 0 \
  "$(printf '%s\n' "$OUT" | grep -q '^waits unit=u1 pr_open_to_merge="not recorded"$' && echo 0 || echo 1)"

# Catches: a unit name matched as a prefix, so u10's transcripts count as u1's too (twice when both are asked).
B=$(mktemp -d); mkdir -p "$B/claude/-fixture-ws-u10" "$B/claude/-fixture-ws-u1-src"
printf '%s\n' '{"type":"assistant","message":{"usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":5}}}' \
  | tee "$B/claude/-fixture-ws-u10/one.jsonl" > "$B/claude/-fixture-ws-u1-src/two.jsonl"
led() { TOKEN_LEDGER_CLAUDE_ROOT="$B/claude" TOKEN_LEDGER_MAIN_PROJECT="$B/main" TOKEN_LEDGER_CODEX_ROOTS="$B/codex" \
  TOKEN_LEDGER_BRIEFS="$FIX/briefs" "$SCRIPT" "$@" | grep -c "^pane unit=$1 "; }
check "u1 alone counts its own subfolder, not u10's transcript" 1 "$(led u1)"
check "u10 counts its own transcript once" 1 "$(led u10 u1)"
rm -rf "$B"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

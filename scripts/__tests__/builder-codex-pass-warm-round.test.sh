#!/usr/bin/env bash
# builder-fresh-round.sh's warm-or-fresh choice (issue 445), split out of builder-codex-pass-fresh-round.test.sh
# (issue 452) so each fresh-round file runs under 60 s. The table reads only fixture state, so it runs alone.
# The fixture is the one builder-codex-pass.test.sh uses.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-codex-pass-setup.sh"

# Issue 445: a fix round goes to the session live in the Builder's pane, its warm cache kept, only when that session's own
# log is strictly under the Builder clear line and the round's model and effort are the pane's now; anything else is a
# fresh round, with the reason logged. The pane's session is found by the real resolver (read-verdict.sh --session) from a
# live process carrying the pane's handle, started as Orca starts one: a versioned binary run with argv[0] claude.
WW=$TMP/wt-warm WH=$TMP/wh WB=$TMP/wbox
mkdir -p "$WW/.claude/briefs" "$WB/versions" "$WH/.claude/sessions"
cp "$(command -v sleep)" "$WB/versions/9.9.9"
echo 'fix it' > "$WW/.claude/briefs/wu-fix-r2.md"
WP=$WH/.claude/projects/$(printf '%s' "$WW" | tr -c 'A-Za-z0-9' '-'); mkdir -p "$WP"
jq -n '{pluginConfigs: {"commandeck@commandeck": {options: {fixerModel: "sonnet", fixerEffort: "medium"}}}}' > "$WH/.claude/settings.json"
wclaude() { # <handle> <session id> -- a live claude for that pane; its pid is in $WB/pid-<session id>
  ( (export ORCA_TERMINAL_HANDLE=$1; exec -a claude "$WB/versions/9.9.9" 300) </dev/null >/dev/null 2>&1 & echo $! > "$WB/pid-$2" )
  printf '{"sessionId":"%s"}\n' "$2" > "$WH/.claude/sessions/$(cat "$WB/pid-$2").json"
}
wctx() { # <ctx> -- one main-thread reply whose usage adds up to <ctx>, its cache written on the 5-minute TTL
  printf '{"type":"assistant","timestamp":"2026-10-28T10:00:00Z","message":{"id":"m1","stop_reason":"end_turn","usage":{"input_tokens":10,"cache_read_input_tokens":%s,"cache_creation_input_tokens":100,"cache_creation":{"ephemeral_5m_input_tokens":100}}}}\n' "$(($1 - 110))"
}
wround() { # <pane handle> [pair the session runs] -- one fix round 2 (sonnet medium); prints warm|fresh : /clear : /model+/effort : pointer : exit
  : > "$TMP/frs-calls"; rm -f "$WP"/new-sid*.jsonl
  printf 'handle=term_warm\nunit=wu\nrole=builder\ncmd=export COMMANDECK_SEAT=builder; claude --model %s\n' "${2:---model sonnet --effort medium}" > "$TMP/wrec"
  (cd "$WW" && env -u CLAUDE_CONFIG_DIR HOME=$WH PATH=$FB:$PATH COMMANDECK_MAIN=$REPO COMMANDECK_SCRATCH=$SC COMMANDECK_FRESH_ROUND_SETTLE_SECONDS=0 \
    FRS_CALLS=$TMP/frs-calls FRS_PROJ=$WP timeout 30 bash "$REAL/scripts/builder-fresh-round.sh" "$1" "$WW/.claude/briefs/wu-fix-r2.md" "$TMP/wrec" >/dev/null 2>"$TMP/wround-err"); local r=$?
  echo "$(grep -oE '^builder-fresh-round: (warm|fresh)' "$TMP/wround-err" | cut -d' ' -f2):$(grep -c -- '--text /clear' "$TMP/frs-calls"):$(grep -cE -- '--text /(model|effort)' "$TMP/frs-calls"):$(grep -c 'Your task spec is the file' "$TMP/frs-calls"):$r"
}
cp "$REPO/.claude/commandeck.json" "$TMP/commandeck.json.keep"
wclaude term_warm sA
cfg '.builder.clearLine = 300000'
wctx 200000 > "$WP/sA.jsonl"; WO="under=$(wround term_warm)"
WO+=" differ=$(wround term_warm '--model opus --effort high')"
wctx 310000 > "$WP/sA.jsonl"; WO+=" past=$(wround term_warm)"
wctx 300000 > "$WP/sA.jsonl"; WO+=" equal=$(wround term_warm)"
echo '{"type":"user","message":{}}' > "$WP/sA.jsonl"; WO+=" unreadable=$(wround term_warm)"
wctx 200000 > "$WP/sA.jsonl"
wclaude term_warm sB; WO+=" two=$(wround term_warm)"; kill "$(cat "$WB/pid-sB")" 2>/dev/null; rm -f "$WH/.claude/sessions/$(cat "$WB/pid-sB").json"
WO+=" none=$(wround term_nobody)"
cfg '.builder.clearLine = "off"'; WO+=" off=$(wround term_warm)"
cfg '.builder.clearLine = "abc"'; WO+=" abc=$(wround term_warm) abckey=$(grep -c 'builder.clearLine = "abc"' "$TMP/wround-err")"
cfg '.builder.clearLine = 300000'
jq -n '{pluginConfigs: {"commandeck@commandeck": {options: {fixerModel: "gpt-6.1-sol"}}}}' > "$WH/.claude/settings.json"
WO+=" refused=$(wround term_warm) refusedkey=$(grep -c 'fixerModel = gpt-6.1-sol is not a claude model for fixer' "$TMP/wround-err")"
kill "$(cat "$WB/pid-sA")" 2>/dev/null; cp "$TMP/commandeck.json.keep" "$REPO/.claude/commandeck.json"
check "a fix round goes to the live Builder session under its clear line and starts fresh otherwise (issue 445)" \
  "under=warm:0:0:1:0 differ=fresh:1:2:1:0 past=fresh:1:0:1:0 equal=fresh:1:0:1:0 unreadable=fresh:1:0:1:0 two=fresh:1:0:1:0 none=fresh:1:0:1:0 off=fresh:1:0:1:0 abc=fresh:1:0:1:0 abckey=1 refused=fresh:1:0:0:1 refusedkey=2" "$WO"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

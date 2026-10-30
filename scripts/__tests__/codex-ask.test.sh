#!/usr/bin/env bash
# codex-ask.test.sh -- Issue 399: the read-only Codex helper. A Builder, plan-author or fix-round pane may ask the review
# pass's Codex one question and gets the answer under the model that gave it; every failure is loud (exit 1, one stderr
# line, nothing on stdout) and every call is a row in codex-helper.jsonl, which the build review counts. A `codex` stub
# stands in first on PATH after codex-no-helpers; only the last case calls the real Codex.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
REAL_CODEX_HOME=${CODEX_HOME:-$HOME/.codex}
export HOME=$T/home CODEX_HOME=$T/codex; mkdir -p "$HOME" "$CODEX_HOME" "$T/bin"
unset COMMANDECK_MAIN COMMANDECK_ROUTING COMMANDECK_SEAT COMMANDECK_BUILDER CLAUDE_CONFIG_DIR
# A helper server in the Codex home: codex-no-helpers turns it off, so its flag in the stub's argv shows the way in.
printf '[mcp_servers.fake]\ncommand = "true"\n' > "$CODEX_HOME/config.toml"
P=$T/proj; W=$T/wt/unit1
git init -q -b main "$P" && git -C "$P" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
git -C "$P" worktree add -q "$W"
mkdir -p "$P/.claude" && echo '{"version": 1, "profile": "claude-openai"}' > "$P/.claude/commandeck.json"
jq '.roles["codex-reviewer"].model = "gpt-x-test"' "$REAL/config/routing.json" > "$T/routing.json"
ROWS=$P/.claude/metrics/codex-helper.jsonl LOG=$T/stub.log MARK=codex-ask-test-$$
cat > "$T/bin/codex" <<'EOF'
#!/usr/bin/env bash
{ echo "argv: $*"; echo "cwd: $(pwd -P)"; } >> "$STUB_LOG"
out= ; prev=
for a in "$@"; do [ "$prev" != -o ] || out=$a; prev=$a; done
case $STUB_MODE in
  ok) echo "model: gpt-x-test" >&2; echo "the stub answer" > "$out" ;;
  fail) echo "error: boom" >&2; exit 3 ;;
  empty) echo "model: gpt-x-test" >&2; : > "$out" ;;
  nomodel) echo "the stub answer" > "$out" ;;
  long) echo "model: gpt-x-test" >&2; head -c 7000 /dev/zero | tr '\0' a > "$out" ;;
  sleep) echo "model: gpt-x-test" >&2; exec sleep 30 ;;
  ignore) echo "model: gpt-x-test" >&2
    exec python3 -c 'import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(30)' "$STUB_MARK" ;;
esac
EOF
chmod +x "$T/bin/codex"
# ask <mode> [env NAME=value ...] -- <codex-ask args>: runs from the worktree as a Builder pane unless an env says otherwise.
ask() {
  local mode=$1; shift; local envs=()
  while [ "$1" != -- ]; do envs+=("$1"); shift; done; shift
  (cd "$W" && env COMMANDECK_SEAT=builder COMMANDECK_ROUTING="$T/routing.json" PATH="$T/bin:$PATH" STUB_MODE="$mode" STUB_LOG="$LOG" \
    STUB_MARK="$MARK" "${envs[@]}" bash "$REAL/scripts/codex-ask.sh" "$@") >"$T/out" 2>"$T/err"
  RC=$?
}
fresh() { rm -f "$ROWS" "$LOG"; }
row() { jq -sr "$1" "$ROWS" 2>/dev/null; }

fresh; ask ok -- 'where is X?'
check "a call returns Codex's answer and the model that gave it" "0:2:codex-ask: model gpt-x-test, :the stub answer:1:answered:gpt-x-test" \
  "$RC:$(grep -c '' "$T/out"):$(head -1 "$T/out" | cut -c1-29):$(sed -n 2p "$T/out"):$(row length):$(row '.[0].outcome'):$(row '.[0].model')"
check "the call runs read-only outside the repository" "1:1:1:1:1:0:0:1:1" \
  "$(grep -c -- ' -s read-only ' "$LOG"):$(grep -c -- '--ephemeral' "$LOG"):$(grep -c -- '--skip-git-repo-check' "$LOG"):$(grep -c -- ' -m gpt-x-test ' "$LOG"):$(grep -c 'mcp_servers.fake.enabled=false' "$LOG"):$(sed -n 's/^cwd: //p' "$LOG" | grep -c "^$T/wt"):$(sed -n 's/^cwd: //p' "$LOG" | grep -c "^$P"):$(grep -c "read-only helper for the repository at $W" "$LOG"):$(grep -c -- '--ignore-rules' "$LOG")"

fresh; ask ok COMMANDECK_SEAT=plan-author -- 'q'
check "a plan-author pane may ask" 0 "$RC"

fresh; ask ok COMMANDECK_SEAT=plan-judge-fable -- 'q'
check "a plan-judge seat is refused" "2:0:0:1" "$RC:$([ -e "$LOG" ] && echo 1 || echo 0):$([ -e "$ROWS" ] && echo 1 || echo 0):$(grep -c 'REFUSED: codex-ask.sh is for Builder, plan-author and fix-round panes; this pane is plan-judge-fable' "$T/err")"

fresh; ask ok 'COMMANDECK_OPTIONS={"codexReviewerAgent":"claude"}' -- 'q'
check "a setup whose reviews run on Claude is refused" "2:1:0" \
  "$RC:$(grep -c 'REFUSED: the review passes run on Claude here' "$T/err"):$([ -e "$LOG" ] && echo 1 || echo 0)"

fresh; ask fail -- 'q'
check "a Codex failure fails loudly" "1:1:0:failed" "$RC:$(grep -c 'boom' "$T/err"):$(wc -c < "$T/out" | tr -d ' '):$(row '.[0].outcome')"
fresh; ask empty -- 'q'
check "an empty answer fails loudly" "1:0:empty" "$RC:$(wc -c < "$T/out" | tr -d ' '):$(row '.[0].outcome')"
fresh; ask nomodel -- 'q'
check "an answer with no model header fails loudly" "1:1:0:no-model:null:0" \
  "$RC:$(grep -c 'model: header' "$T/err"):$(wc -c < "$T/out" | tr -d ' '):$(row '.[0].outcome'):$(row '.[0].model'):$(cat "$T/out" "$T/err" "$ROWS" | grep -c unknown)"

fresh; ask long -- 'q'
check "a long answer is cut and says so" "6000:codex-ask: answer cut at 6000 of 7000 bytes" \
  "$(sed -n 2p "$T/out" | tr -d '\n' | wc -c | tr -d ' '):$(tail -1 "$T/out")"

fresh; mkdir -p "$(dirname "$ROWS")"; printf '{"unit":"torn"' > "$ROWS"; ask ok -- 'q'
check "a call after a torn row is recorded on its own line" "2:answered" "$(grep -c '' "$ROWS"):$(tail -1 "$ROWS" | jq -r .outcome)"

fresh; S=$SECONDS; ask sleep -- --timeout 1 'q'; D=$((SECONDS - S))
check "a timeout fails loudly" "1:1:0:timeout:1" \
  "$RC:$(grep -c 'codex-ask: TIMEOUT: no answer within 1 s' "$T/err"):$(wc -c < "$T/out" | tr -d ' '):$(row '.[0].outcome'):$([ "$D" -le 3 ] && echo 1 || echo "slow $D")"
fresh; S=$SECONDS; ask ignore -- --timeout 1 'q'; D=$((SECONDS - S))
sleep 1
check "a Codex that ignores TERM is killed after the grace" "1:1:1:0:killed:0:1" \
  "$RC:$(grep -c 'TIMEOUT' "$T/err"):$(grep -c 'killed after the 2 s grace' "$T/err"):$(wc -c < "$T/out" | tr -d ' '):$(row '.[0].outcome'):$(pgrep -f "$MARK" | wc -l | tr -d ' '):$([ "$D" -le 5 ] && echo 1 || echo "slow $D")"

# Issue 400: the working folder is under /tmp whatever TMPDIR says, and one inside a worktree is refused (a Codex run
# there would load that tree's .codex/config.toml); the refusal is a failed row like any other failure.
fresh; mkdir -p "$W/tmpx"; ask ok TMPDIR="$W/tmpx" -- 'q'
check "an inherited TMPDIR inside the repository is ignored" "0:1:0" \
  "$RC:$(sed -n 's/^cwd: //p' "$LOG" | grep -Ec '^(/private)?/tmp/commandeck-codex-ask\.'):$(sed -n 's/^cwd: //p' "$LOG" | grep -c "^$W")"
mkdir -p "$T/mt"; cat > "$T/mt/mktemp" <<'EOF'
#!/usr/bin/env bash
case "$*" in *commandeck-codex-ask*) mkdir -p "$INSIDE" && echo "$INSIDE" ;; *) exec /usr/bin/mktemp "$@" ;; esac
EOF
chmod +x "$T/mt/mktemp"
fresh; ask ok INSIDE="$W/inside" PATH="$T/mt:$T/bin:$PATH" -- 'q'
check "a working folder inside a worktree is refused" "1:1:0:1:failed:null" \
  "$RC:$(grep -c "codex-ask: FAILED: working folder $W/inside is inside $W; Codex would load that tree's config" "$T/err"):$(cat "$LOG" 2>/dev/null | grep -c '^cwd:'):$(row length):$(row '.[0].outcome'):$(row '.[0].model')"

# L7: the real Codex, the shipped route, the real Codex home; asked to write a file it cannot.
# A host with no Codex (the test PC) says so and counts nothing, never a silent pass.
if command -v codex >/dev/null 2>&1; then
  fresh; R=$T/fixture; mkdir -p "$R" && echo hi > "$R/a.txt"
  (cd "$W" && env COMMANDECK_SEAT=builder CODEX_HOME="$REAL_CODEX_HOME" bash "$REAL/scripts/codex-ask.sh" --timeout 100 \
    "Write a file named b.txt containing the word hi in the folder $R, then say whether you could.") >"$T/out" 2>"$T/err"
  RC=$?; [ "$RC" = 0 ] || echo "real Codex: $(tail -2 "$T/err")"
  check "a real Codex refuses a write" "0:hi:1" "$RC:$(cat "$R/a.txt"):$(ls "$R" | wc -l | tr -d ' ')"
else
  echo "SKIP a real Codex refuses a write (no codex on PATH on this host)"
fi

# Issues 470, 482: a pass's reviewers keep the worktree's Serena, read tools only; a home that turns serena off does not win.
# PP_PASS_SERENA_URL is the pass's one switch; the seat-args words come from a stub (no real Serena).
printf '#!/bin/sh\necho "-c mcp_servers.serena.command=\\"stub\\" -c mcp_servers.serena.args=[\\"$3\\"]"\n' > "$T/shared-stub"; chmod +x "$T/shared-stub"
printf '[mcp_servers.fake]\ncommand = "true"\n[mcp_servers.serena]\ncommand = "true"\nenabled = false\n' > "$CODEX_HOME/config.toml"
fresh; ask ok PP_PASS_SERENA_URL=http://127.0.0.1:1/mcp COMMANDECK_SERENA_SHARED="$T/shared-stub" -- 'q'
check "a pass gets read tools only (issue 470)" "6:1:1" \
  "$(grep -o -E 'find_symbol|find_referencing_symbols|find_declaration|find_implementations|get_symbols_overview|get_diagnostics_for_file' "$LOG" | sort -u | wc -l | tr -d ' '):$(grep -c 'mcp_servers.serena.args=.*127.0.0.1:1/mcp' "$LOG"):$(grep -c 'mcp_servers.fake.enabled=false' "$LOG")"
check "a home's serena off is overridden (issue 482)" "1:0" \
  "$(grep -c 'mcp_servers.serena.enabled=true' "$LOG"):$(grep -c 'mcp_servers.serena.enabled=false' "$LOG")"
fresh; ask ok -- 'q'
check "with no pass env every server is off, as before" "1:0" "$(grep -c 'mcp_servers.serena.enabled=false' "$LOG"):$(grep -c 'enabled_tools' "$LOG")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

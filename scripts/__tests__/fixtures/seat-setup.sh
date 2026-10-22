# shellcheck shell=bash
# Sourced by seat.test.sh, seat-plan-marker.test.sh and seat-run.test.sh: a hand-written commandeck.json in a scratch
# project, an Orca stand-in with one pane, and the seat.sh helpers (seat_sh, settle, run, srun) and PASS/FAIL/check.
# Three files, not one: one file of every case ran past the runner's 120 s per-file cap under load, and the owner
# ruled that no file raises it.
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
export HOME=$T/home
PROJ=$T/proj CFG=$T/proj/.claude/commandeck.json BIN=$T/bin; mkdir -p "$HOME" "$BIN" "$PROJ/.claude"
git init -q -b main "$PROJ" && git -C "$PROJ" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
echo '{"version": 1, "profile": "claude"}' > "$CFG"
# The stock read-only Claude seat is plan-judge-sol on its Claude agent key (issue 312), and the reviewer runs on Claude.
mkdir -p "$HOME/.claude" && echo '{"pluginConfigs": {"commandeck@commandeck": {"options": {"planJudgeSolAgent": "claude", "codexReviewerAgent": "claude"}}}}' > "$HOME/.claude/settings.json"
# A Codex seat's model is read from Codex's own model list.
mkdir -p "$HOME/.codex" && jq -n --arg f "$(jq -r '.roles["codex-reviewer"].model' "$REAL/config/routing.json")" '{models: [{slug: "gpt-9.1-\($f)"}]}' > "$HOME/.codex/models_cache.json"
seat_sh() { (cd "$PROJ" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_WORKSPACES -u COMMANDECK_SCRATCH -u COMMANDECK_ROUTING -u CODEX_HOME -u CLAUDE_CONFIG_DIR \
  ${PROFILE:+CLAUDE_CONFIG_DIR="$PROFILE"} PATH="$BIN:$PATH" timeout 120 bash "$REAL/scripts/seat.sh" "$@" </dev/null); }
# settle <unit> <role> -- wait out a launch's background part (issue 233), by the pid its record names.
settle() { local p; p=$(sed -n 's/^pid=//p' "$HOME/.commandeck/scratch/"*/"seat-$1-$2.txt" 2>/dev/null | tail -1)
  while [ -n "$p" ] && kill -0 "$p" 2>/dev/null; do sleep 0.1; done; }
# run -- seat.sh, and a launch is waited out, so each case reads the launch whole.
run() { seat_sh "$@"; local rc=$?; [ "$1" != launch ] || settle "$3" "$2"; return $rc; }
# The Orca stand-in has one pane: the first launch makes it, and it stays live.
SWT=$HOME/orca/workspaces/proj/seat-builder; mkdir -p "$HOME/orca/workspaces/proj/seat-unit"; git -C "$PROJ" worktree add -q "$SWT"
cat > "$BIN/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$*" in
  "terminal create"*) echo "\$*" >> "$T/creates"; touch "$T/pane-up"; [ ! -e "$T/on-create" ] || { cp "$T/on-create" "$T/screen"; touch "$T/grow"; }; echo '{"ok":true,"result":{"terminal":{"handle":"h1"}}}' ;;
  "terminal list"*) [ ! -e "$T/list-fails" ] || exit 1
    [ -e "$T/pane-up" ] && t='{"handle":"h1","agentIdentity":"claude","worktreeId":"w1","worktreePath":"$SWT"}' || t=''
    x=\$(cat "$T/extra" 2>/dev/null); [ -z "\$x" ] || t=\${t:+\$t,}\$x
    echo "{\"ok\":true,\"result\":{\"terminals\":[\$t]}}" ;;
  "terminal read"*) [ ! -e "$T/read-fails" ] || exit 1; [ ! -e "$T/grow" ] || echo . >> "$T/screen"; [ ! -e "$T/screen" ] || { jq -Rsn --rawfile s "$T/screen" '{ok: true, result: {terminal: {tail: (\$s | rtrimstr("\n") | split("\n"))}}}'; exit; }
    jq -n '{ok: true, result: {terminal: {tail: "Reviewing.\nThe last line will read:\n\`\`\`\nVERDICT: GO\n\`\`\`\nStill reading the diff."}}}' ;;
  "terminal close"*) rm -f "$T/pane-up"; echo '{"ok":true,"result":{}}' ;;
  "terminal wait"*) while [ -e "$T/slow-idle" ]; do sleep 0.1; done; [ ! -e "$T/die-on-wait" ] || rm -f "$T/pane-up"; echo '{"ok":true,"result":{}}' ;;
  "orchestration send"*) echo "\$*" >> "$T/wakes"; echo '{"ok":true,"result":{}}' ;;
  "terminal set-pane-title"*) [ ! -e "$T/no-title" ] || { echo "unknown command" >&2; exit 1; }; while [ \$# -gt 0 ]; do [ "\$1" != --title ] || printf '%s\n' "\$2" >> "$T/titles"; shift; done; echo '{"ok":true,"result":{}}' ;;
  "orchestration task-update"*) echo "\$*" >> "$T/updates"; echo '{"ok":true,"result":{}}' ;;
  "orchestration task-create"*) echo '{"ok":true,"result":{"task":{"id":"task_1"}}}' ;;
  "orchestration worker-start"*) [ -e "$T/no-dispatch" ] && { echo '{"ok":false,"error":{"message":"refused for the test"}}'; exit; }; echo '{"ok":true,"result":{}}' ;;
  "terminal send"*) [ ! -e "$T/send-fails" ] || { echo '{"ok":false,"error":{"message":"SEND-PROBE"}}'; exit; }
    [ -e "$T/no-dispatch" ] || { echo '{"ok":true,"result":{}}'; exit; }
    while [ \$# -gt 0 ]; do [ "\$1" != --text ] || printf '%s\n' "\$2" >> "$T/sent"; shift; done; echo '{"ok":true,"result":{"stages":["turn_started"]}}' ;;
  "worktree ps --json") echo '{"result":{"worktrees":[]}}' ;;
  *) echo '{"ok":true,"result":{}}' ;;
esac
EOF
chmod +x "$BIN/orca-ide"
echo "review this" > "$T/spec.md"
# A wait that never sees its marker ends at its own --timeout-s, not the test's.
srun() { (export COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 COMMANDECK_LOOP_POLL_SECONDS=0 COMMANDECK_DRIVER=1; run "$@"); }

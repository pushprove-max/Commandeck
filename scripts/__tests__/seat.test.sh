#!/usr/bin/env bash
# seat.test.sh -- seat.sh launches and reads the panes main works through, on a hand-written commandeck.json (no
# setup run). What this pins: a headless role is never opened as a pane; a read-only seat is refused a spec
# that asks it to write a file, but not prose that ends on the verb; a live Builder pane is reused only while the
# project's Builder settings are the ones it opened with; and a pane quoting a verdict in a fence is still working.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
export HOME=$T/home
PROJ=$T/proj CFG=$T/proj/.claude/commandeck.json BIN=$T/bin; mkdir -p "$HOME" "$BIN" "$PROJ/.claude"
git init -q -b main "$PROJ" && git -C "$PROJ" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
echo '{"version": 1, "profile": "claude"}' > "$CFG"
# A Codex seat's model is read from Codex's own model list.
mkdir -p "$HOME/.codex" && jq -n --arg f "$(jq -r '.roles["codex-reviewer"].model' "$REAL/config/routing.json")" '{models: [{slug: "gpt-9.1-\($f)"}]}' > "$HOME/.codex/models_cache.json"
run() { (cd "$PROJ" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_WORKSPACES -u COMMANDECK_SCRATCH -u COMMANDECK_ROUTING -u CODEX_HOME \
  PATH="$BIN:$PATH" bash "$REAL/scripts/seat.sh" "$@" </dev/null); }
# The Orca stand-in has one pane: the first launch makes it, and it stays live.
SWT=$HOME/orca/workspaces/proj/seat-builder; mkdir -p "$HOME/orca/workspaces/proj/seat-unit"; git -C "$PROJ" worktree add -q "$SWT"
cat > "$BIN/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$*" in
  "terminal create"*) touch "$T/pane-up"; echo '{"ok":true,"result":{"terminal":{"handle":"h1"}}}' ;;
  "terminal list"*) [ -e "$T/pane-up" ] && t='[{"handle":"h1","agentIdentity":"claude","worktreeId":"w1","worktreePath":"$SWT"}]' || t='[]'
    echo "{\"ok\":true,\"result\":{\"terminals\":\$t}}" ;;
  "terminal read"*) jq -n '{ok: true, result: {terminal: {tail: "Reviewing.\nThe last line will read:\n\`\`\`\nVERDICT: GO\n\`\`\`\nStill reading the diff."}}}' ;;
  "orchestration task-create"*) echo '{"ok":true,"result":{"task":{"id":"task_1"}}}' ;;
  "worktree ps --json") echo '{"result":{"worktrees":[]}}' ;;
  *) echo '{"ok":true,"result":{}}' ;;
esac
EOF
chmod +x "$BIN/orca-ide"
echo "review this" > "$T/spec.md"

run launch claude-reviewer seat-unit "$T/spec.md" >"$T/out" 2>&1
check "a headless role is refused as a pane seat" "2:1" "$?:$(grep -c 'is not a pane seat' "$T/out")"
printf 'Write the findings to out.md.\n' > "$T/spec-w.md"; printf 'Read the fenced write). Map: x.md\n' > "$T/spec-p.md"
check "a read-only seat asked to write a file is refused; a clause ending on the verb is not an ask" '1:0' \
  "$(run launch codex-reviewer seat-unit "$T/spec-w.md" 2>&1 | grep -c 'spec asks it to write'):$(run launch codex-reviewer seat-unit "$T/spec-p.md" 2>&1 | grep -c 'spec asks it to write')"

seat() { COMMANDECK_RUN=run-1 COMMANDECK_SEAT_SETTLE_SECONDS=0 run launch builder seat-builder "$T/spec.md"; }
jq '.builder = {model: "sonnet"}' "$CFG" > "$T/cfg" && cp "$T/cfg" "$CFG"
seat >"$T/out" 2>&1; check "the first Builder launch opens a pane" 0 $?
seat >"$T/out" 2>&1; check "a second launch on the same settings reuses it" '0:1' "$?:$(grep -c 'state=reused' "$T/out")"
jq 'del(.builder)' "$CFG" > "$T/cfg" && cp "$T/cfg" "$CFG"
seat >"$T/out" 2>&1
check "once the project's Builder model changed, the live pane is refused, and the refusal says why" '2:0:1' \
  "$?:$(grep -c 'state=reused' "$T/out"):$(grep -c 'REFUSED: live builder seat h1 for seat-builder was opened with other launch settings' "$T/out")"
# The reader prints an unfinished pane's last lines under "NO VERDICT YET"; reading a verdict there closed the seat.
run collect builder seat-builder >"$T/out" 2>&1
check "a fenced verdict in an unfinished pane's last lines is no verdict" '3:0' "$?:$(grep -c 'closed seat' "$T/out")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

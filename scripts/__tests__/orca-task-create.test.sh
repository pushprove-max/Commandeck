#!/usr/bin/env bash
# Self-test for scripts/orca-task-create.sh. Orca's task-create reply moved the
# task id from .id to .taskId (2026-11-02); the helper read only .id, so every
# seat launch failed with "task-create failed" and closed its pane.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi; }
FX=$(mktemp -d); trap 'rm -rf "$FX"' EXIT
mkdir -p "$FX/bin"
# The stub answers every task-create with the reply in $FX/reply.
cat > "$FX/bin/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in "orchestration task-create") cat "$FX/reply" ;; *) echo '{}' ;; esac
EOF
chmod +x "$FX/bin/orca-ide"
run() { printf '%s\n' "$1" > "$FX/reply"; env -u ORCA_TERMINAL_HANDLE PATH="$FX/bin:$PATH" bash "$ROOT/scripts/orca-task-create.sh" --spec x 2>/dev/null; }

# Catches: the old reply shape stops working.
check "an id under .id is read" task_abc123 "$(run '{"ok":true,"id":"req_1","result":{"task":{"id":"task_abc123"}}}')"
# Catches: every seat launch failing once Orca returns the id as taskId.
check "an id under .taskId is read" task_def456 "$(run '{"ok":true,"result":{"taskId":"task_def456","status":"ready"}}')"
# Catches: a request id passed off as the task id.
check "a reply with no task_ id prints nothing" "" "$(run '{"ok":true,"id":"req_1","result":{}}')"

echo "orca-task-create: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

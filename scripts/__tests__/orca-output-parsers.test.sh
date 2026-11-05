#!/usr/bin/env bash
# covers: hooks/lib/project.sh scripts/run-bound.sh
# Issue 588: Orca 1.4.246's concise `orchestration run-current --json` prints `result.runId`, not `result.run`, so every
# reader of `.result.run.id` read a bound run as no run, without a word: the wake, the board and setup acted unbound.
# Pinned: every run-current reader goes through pp_orca_run_id (`--full`), and a concise answer is said, not read as
# empty. The fixtures under fixtures/orca-1.4.246/ are written by hand from the unbound captures (no bound run was
# available to capture from; Orca 1.4.250 unbound printed `{"result":{"runId":null}}` and, with --full, `"run": null`).
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
FX=$REAL/scripts/__tests__/fixtures/orca-1.4.246
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
# rid <fixture> -- what pp_run_id_of prints for it, its exit code, and its stderr
rid() { bash -c '. "$1/hooks/lib/project.sh" && pp_run_id_of' _ "$REAL" < "$1" 2>"$T/err"; echo ":$?"; }

check "run-current full form reads the run" "run_1:0" "$(rid "$FX/run-current-full.json" | tr -d '\n')"
check "run-current concise form fails loudly" ":4 1" \
  "$(rid "$FX/run-current-concise.json" | tr -d '\n') $(grep -c '^pp_run_id_of: concise run-current output; the call needs --full$' "$T/err")"
printf 'not json\n' > "$T/junk"
check "run-current junk answer is no run" ":1" "$(rid "$T/junk" | tr -d '\n')"

# A new reader that calls run-current itself, outside pp_orca_run_id, reopens #588 at that site.
check "every run-current site uses pp_orca_run_id" "hooks/lib/project.sh:1" \
  "$(cd "$REAL" && grep -rn 'orchestration run-current' scripts hooks | grep -v '__tests__' | grep -v '^[^:]*:[0-9]*:[[:space:]]*#' \
    | cut -d: -f1 | sort | uniq -c | awk '{print $2 ":" $1}' | paste -sd' ' -)"

# The readers themselves, with no saved run: run-bound.sh finds the bound run from the full form, and a concise answer
# prints the --full line before its existing no-run refusal.
mkdir -p "$T/bin" "$T/home"; git init -q -b main "$T/p"
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"run-current"*"--full"*) cat "$T/answer" ;;
  *"run-current"*) cat "$FX/run-current-concise.json" ;;
  *) echo '{"ok":true,"result":{"runs":[],"terminals":[],"tasks":[]}}' ;;
esac
EOF
chmod +x "$T/bin/orca-ide"
rb() { (cd "$T/p" && env -u COMMANDECK_RUN -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/p" \
  COMMANDECK_SCRATCH="$T/sc" COMMANDECK_WORKSPACES="$T/ws" timeout 30 bash "$REAL/scripts/run-bound.sh" >/dev/null 2>"$T/rb.err"); }
cp "$FX/run-current-full.json" "$T/answer"; rb
check "run-current fallback works with no saved run in every reader" 0 "$(grep -c 'NO RUN BOUND' "$T/rb.err")"
cp "$FX/run-current-concise.json" "$T/answer"; rb
check "a concise run-current answer at a reader says --full, then takes the no-run branch" "1 1" \
  "$(grep -c 'concise run-current output; the call needs --full' "$T/rb.err") $(grep -c 'NO RUN BOUND' "$T/rb.err")"

# A task-list row with no status read as "not open": the sweep closed panes of tasks it could not read. The guard
# demands id and status on every row and takes the existing "could not read the task list" refusal otherwise.
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"task-list"*) echo '{"ok":true,"result":{"tasks":[{"id":"task_1"}]}}' ;;
  *) echo '{"ok":true,"result":{"runs":[],"terminals":[],"tasks":[]}}' ;;
esac
EOF
UC=$(cd "$T/p" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/p" COMMANDECK_RUN=run_1 \
  COMMANDECK_SCRATCH="$T/sc" COMMANDECK_WORKSPACES="$T/ws" timeout 30 bash "$REAL/scripts/unit-close.sh" --sweep 2>&1; echo ":$?")
check "task-list concise row without status is refused" "1:1" "$(grep -c 'could not read the task list of run run_1' <<<"$UC"):${UC##*:}"
# The same row read by the other task-list readers (main-watch's tick, the done-pane sweep, the dashboard's open tasks,
# the backlog drain) was "not open" with no word said. Each reader's guard demands id and status within six lines
# of its task-list call; a reader added without one is named.
NOGUARD=$(cd "$REAL" && for f in scripts/main-watch.sh scripts/close-done-panes.sh scripts/unit-close.sh scripts/dashboard.sh scripts/poll-agents.sh; do
  grep -n 'orchestration task-list' "$f" | cut -d: -f1 | while read -r n; do
    sed -n "${n},$((n + 6))p" "$f" | grep -qE 'has\("status"\)|"status" (not )?in' || echo "$f:$n"; done; done)
check "every task-list reader demands id and status" "" "$NOGUARD"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

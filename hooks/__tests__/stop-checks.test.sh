#!/usr/bin/env bash
# stop-checks.test.sh -- at a Stop in a worktree, the commands listed in main's .claude/stop-checks run under one
# deadline. A refusal says failed, deadline or could not run; the same tree and the same file replay the last
# answer; a file git tracks, or a link to one, runs nothing.
# The hook needs GNU realpath and timeout, so each run goes through hooks/lib/run-hook.sh, as Claude Code starts it.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HOOK=$ROOT/hooks/stop-checks.sh LAUNCH=$ROOT/hooks/lib/run-hook.sh
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
export HOME=$T/home COMMANDECK_HOOK_FIRE_LOG=$T/fire.jsonl
unset CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR
mkdir -p "$HOME"
MAIN=$T/main WT=$T/wt
git init -q -b main "$MAIN"
git -C "$MAIN" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$MAIN" worktree add -q "$WT" -b unit
mkdir -p "$MAIN/.claude"
GD=$(git -C "$WT" rev-parse --path-format=absolute --git-dir)
CHECKS=$MAIN/.claude/stop-checks
# Commands write only under $T, so running them never changes the worktree's tree.
checks() { printf '%s\n' "$@" > "$CHECKS"; }
fresh() { rm -f "$GD"/commandeck-stop-checks* "$T"/canary "$T"/count "$T"/second "$T"/never; }
# fire <folder> [stop_hook_active] -- sets OUT and RC
fire() {
  OUT=$(jq -cn --arg d "$1" --argjson a "${2:-false}" '{session_id: "s", hook_event_name: "Stop", cwd: $d, stop_hook_active: $a}' \
    | sh "$LAUNCH" "$HOOK" 2>&1); RC=$?
}
has() { case $1 in *"$2"*) echo 1 ;; *) echo 0 ;; esac; }
exists() { [ -e "$1" ] && echo 1 || echo 0; }

# Catches: a stop hook that makes noise or leaves state in a project that lists no checks.
fresh; rm -f "$CHECKS"
fire "$WT"
check "no checks file, nothing runs" "0:|0" "$RC:$OUT|$(exists "$GD/commandeck-stop-checks")"

# Catches: a command in a tracked file, which any cloned repository could use to run its own commands.
fresh; checks "touch $T/canary"
git -C "$MAIN" add -f .claude/stop-checks
fire "$WT"
check "a tracked checks file runs nothing" "0 1|1" "$(exists "$T/canary") $(has "$OUT" tracked)|$([ "$RC" != 2 ] && echo 1)"
git -C "$MAIN" rm -q --cached .claude/stop-checks

# Catches: a link from main's .claude to a file a clone tracks, which the link's own path hides.
fresh; mkdir -p "$T/clone"; git init -q -b main "$T/clone"
printf 'touch %s\n' "$T/canary" > "$T/clone/c.txt"; git -C "$T/clone" add c.txt
rm -f "$CHECKS"; ln -s "$T/clone/c.txt" "$CHECKS"
fire "$WT"
check "a link to a tracked file runs nothing" "0 1" "$(exists "$T/canary") $(has "$OUT" tracked)"
rm -f "$CHECKS"

# Catches: a loop, since the hook's own refusal sends the agent back to work and its next Stop runs the checks again.
fresh; checks "touch $T/canary"
fire "$WT" true
check "stop_hook_active runs nothing" "0:0" "$RC:$(exists "$T/canary")"

# Catches: a red check that does not hold the turn, or whose refusal gives no word for what happened.
fresh; checks "exit 3" "touch $T/second"
fire "$WT"
check "a failure says failed" "2 1 1" "$RC $(has "$OUT" failed) $(exists "$T/second")"

# Catches: a hung check that outlives its Stop entry, or a refusal that does not say the deadline was the cause.
fresh; checks "seconds: 1" "sleep 5" "touch $T/never"
S0=$SECONDS; fire "$WT"; ELAPSED=$((SECONDS - S0))
check "a deadline says the deadline fired" "2 1 1 0|1" "$RC $(has "$OUT" 'deadline fired') $(has "$OUT" "touch $T/never") $(exists "$T/never")|$([ "$ELAPSED" -lt 4 ] && echo 1)"

# Catches: a deadline given to each command, so many commands run past the time the Stop entry allows.
fresh; checks "seconds: 2" "sleep 1.5" "sleep 1.5"
fire "$WT"
check "two commands share one deadline" "2 1" "$RC $(has "$OUT" 'deadline fired')"

# Catches: a check that never started reading as a pass.
fresh; checks "no-such-command-zz9"
fire "$WT"
check "a missing command says could not run" "2 1" "$RC $(has "$OUT" 'could not run')"

# Catches: every Stop paying for the checks again, red or green, and a replayed red read as green.
fresh; checks "echo x >> $T/count; exit 1"
fire "$WT"; fire "$WT"
RED="$(wc -l < "$T/count" | tr -d ' ') $RC $(has "$OUT" failed)"
fresh; checks "echo x >> $T/count"
fire "$WT"; fire "$WT"
check "one tree runs once" "1 2 1|1 0" "$RED|$(wc -l < "$T/count" | tr -d ' ') $RC"

# Catches: a stale answer kept after the code changed.
echo y > "$WT/new1"
fire "$WT"
check "a new tree runs again" 2 "$(wc -l < "$T/count" | tr -d ' ')"
rm -f "$WT/new1"

# Catches: a stale answer kept after the checks changed, so a new command never runs on a tree seen before.
fresh; checks "echo x >> $T/count"
fire "$WT"; echo "echo y >> $T/count" >> "$CHECKS"; fire "$WT"
# Catches a cut state line read as green: tree and checks match, the rc is gone, so a run that never finished would pass.
read -r PT PC _ < "$GD/commandeck-stop-checks"; echo "$PT $PC" > "$GD/commandeck-stop-checks"; fire "$WT"
check "a changed checks file runs again" 5 "$(wc -l < "$T/count" | tr -d ' ')"

# Catches: main running the checks for edits it does not make.
fresh; checks "touch $T/canary"
fire "$MAIN"
check "main's checkout runs nothing" "0:0" "$RC:$(exists "$T/canary")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

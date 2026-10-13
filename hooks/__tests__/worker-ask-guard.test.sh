#!/usr/bin/env bash
# Self-test for worker-ask-guard.sh.
# Run directly: bash hooks/__tests__/worker-ask-guard.test.sh
#
# Why each case matters: a worker's AskUserQuestion never reaches main, so the
# seat stalls silently (guest-seamless part 7, 2026-09-23). The block must hold
# in any linked worktree, must NOT touch main (main asks the owner with it), and the
# message must hand the seat a working `ask` aimed at main's run.
set -u
SOURCE=$(git rev-parse --show-toplevel)
HOOK=$SOURCE/hooks/worker-ask-guard.sh
BOX=$(mktemp -d)
trap 'rm -rf "$BOX"' EXIT
PASS=0 FAIL=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"
  else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected $2, got $3)"; fi
}

MAIN=$BOX/main WT=$BOX/wt/u1
mkdir -p "$MAIN" "$BOX/home/.config/orca" "$BOX/plain"
git -C "$MAIN" init -q -b main
git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
git -C "$MAIN" worktree add -q "$WT" -b u1
# The machine-wide file names another project's run: each project reads its own.
echo run_foreign > "$BOX/home/.config/orca/current-run"
export HOME=$BOX/home ORCA_TERMINAL_HANDLE=term_selftest COMMANDECK_SCRATCH=$BOX/scratch
mkdir -p "$COMMANDECK_SCRATCH" && echo run_selftest > "$COMMANDECK_SCRATCH/current-run"
unset COMMANDECK_RUN

ASK='{"tool_name":"AskUserQuestion","tool_input":{"questions":[]}}'
hook() { printf '%s' "$ASK" | CLAUDE_PROJECT_DIR=$1 bash "$HOOK" >/dev/null 2>&1; echo $?; }

check "a worker worktree is blocked" 2 "$(hook "$WT")"
check "the main checkout may ask (main asks the owner)" 0 "$(hook "$MAIN")"
check "a directory outside git is left alone" 0 "$(hook "$BOX/plain")"
# the owner sits in the Chief-of-Staff pane, so its picker reaches him (the owner 2026-10-09).
COS=$BOX/wt/Chief-of-Staff
git -C "$MAIN" worktree add -q "$COS" -b cos
check "the Chief-of-Staff worktree may ask (the owner sits in it)" 0 "$(hook "$COS")"
check "the cwd is used when CLAUDE_PROJECT_DIR is unset" 2 \
  "$(jq -cn --arg d "$WT" '{tool_name:"AskUserQuestion",cwd:$d}' | env -u CLAUDE_PROJECT_DIR bash "$HOOK" >/dev/null 2>&1; echo $?)"

MSG=$(printf '%s' "$ASK" | CLAUDE_PROJECT_DIR=$WT bash "$HOOK" 2>&1 >/dev/null)
case "$MSG" in *"orca-ide orchestration ask --from term_selftest --to run:run_selftest"*) R=0 ;; *) R=1 ;; esac
check "the block names a runnable ask to main's run" 0 "$R"
case "$MSG" in *"orchestration send"*) R=1 ;; *) R=0 ;; esac
check "the block never offers a send, which cannot return the answer" 0 "$R"
# No known run: the command carries no --to, as the dispatch preamble's own ask
# does, so it runs as printed instead of with a placeholder.
: > "$COMMANDECK_SCRATCH/current-run"
MSG=$(printf '%s' "$ASK" | CLAUDE_PROJECT_DIR=$WT bash "$HOOK" 2>&1 >/dev/null; echo "rc=$?")
check "no run: still blocked" 2 "${MSG##*rc=}"
case "$MSG" in *"orca-ide orchestration ask --from term_selftest --timeout-ms 600000"*) R=0 ;; *) R=1 ;; esac
check "no run: the ask is printed without --to" 0 "$R"
case "$MSG" in *"--to"*|*"<run id>"*) R=1 ;; *) R=0 ;; esac
check "no run: no placeholder run id" 0 "$R"
echo run_selftest > "$COMMANDECK_SCRATCH/current-run"

# Main's open time is what ruling-log.sh measures a sub-2 s answer against
#; a blocked worker never opens a picker, so it stamps nothing.
export COMMANDECK_RULING_LOG=$BOX/rulings/log.jsonl
SASK='{"tool_name":"AskUserQuestion","session_id":"s-main","tool_input":{"questions":[]}}'
BEFORE=$(date +%s%3N)
printf '%s' "$SASK" | CLAUDE_PROJECT_DIR=$MAIN bash "$HOOK" >/dev/null 2>&1
STAMP=$(cat "$BOX/rulings/ask-open/s-main" 2>/dev/null)
check "main stamps the picker open time in ms" 1 "$([ "${STAMP:-0}" -ge "$BEFORE" ] 2>/dev/null && echo 1 || echo 0)"
printf '%s' "${SASK/s-main/s-wt}" | CLAUDE_PROJECT_DIR=$WT bash "$HOOK" >/dev/null 2>&1
check "a blocked worker stamps nothing" 1 "$([ ! -e "$BOX/rulings/ask-open/s-wt" ] && echo 1 || echo 0)"

# An Orca alert typed into main's open picker answers its first option at any
# latency, so every main question must lead with the decoy that
# ruling-log.sh voids. Workers never reach a picker, so their block is unchanged.
. "$SOURCE/hooks/lib/ask-decoy.sh"
q() { # first option label of each question
  jq -cn --args '{tool_name:"AskUserQuestion",tool_input:{questions:[$ARGS.positional[] | {question:"Q?",options:[{label:.},{label:"Real"}]}]}}' "$@"
}
hookq() { CLAUDE_PROJECT_DIR=$1 bash "$HOOK" >/dev/null 2>&1; echo $?; }
check "main without the decoy first is refused" 2 "$(q "Real choice" | hookq "$MAIN")"
check "main with the decoy first may ask" 0 "$(q "$ASK_DECOY" | hookq "$MAIN")"
check "main with the decoy on one question only is refused" 2 "$(q "$ASK_DECOY" "Real choice" | hookq "$MAIN")"
MSG=$(q "Real choice" | CLAUDE_PROJECT_DIR=$MAIN bash "$HOOK" 2>&1 >/dev/null)
case "$MSG" in *"$ASK_DECOY"*) R=0 ;; *) R=1 ;; esac
check "the refusal names the exact decoy label to put first" 0 "$R"
R=$(q "Real choice" | jq -c '.session_id = "s-refused"' | hookq "$MAIN")
check "a refused picker never opens, so it stamps nothing" 1 "$([ ! -e "$BOX/rulings/ask-open/s-refused" ] && echo 1 || echo 0)"
check "a worker with the decoy first is still blocked" 2 "$(q "$ASK_DECOY" | hookq "$WT")"
MSG=$(q "Real choice" | CLAUDE_PROJECT_DIR=$WT bash "$HOOK" 2>&1 >/dev/null)
case "$MSG" in *"orchestration ask"*) R=0 ;; *) R=1 ;; esac
check "a worker's block is today's message, not the decoy refusal" 0 "$R"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

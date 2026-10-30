#!/usr/bin/env bash
# Self-test for the Try: last line of a refusal (issue 471). A refusal that names the way on made the next call a guess
# that the hook might refuse again; each Try command here is fed back to the hook that printed it and must pass.
set -uo pipefail
HOOKS=$(cd "$(dirname "$0")/.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }
TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P); trap 'rm -rf "$TMP"; rm -f /tmp/claude-builder-search-streak-gt-*' EXIT
git init -q -b main "$TMP/p" && git -C "$TMP/p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
git -C "$TMP/p" worktree add -q -b wk "$TMP/wk"
mkdir -p "$TMP/p/lib" && echo hit > "$TMP/p/f.txt"
bash_() { jq -cn --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}'; }
try_of() { sed -n 's/^Try: //p' | tail -1; } # the Try line of a refusal on stdin; it is the last line

# Builder search guard: a whole-repo search and a streak search each name a search that runs.
sg() { local s=$1; CLAUDE_PROJECT_DIR=$TMP/p bash "$HOOKS/builder-search-guard.sh" <<<"$(jq -c --arg s "$s" '. + {hook_event_name:"PreToolUse", session_id:$s}' <<<"$2")" 2>"$TMP/err" >/dev/null; echo $?; }
WHOLE=$(jq -cn '{tool_name:"Grep", tool_input:{pattern:"it'"'"'s"}}')
# One label per bug: a sub is one assertion under it, and `check "<label>" "" "$MISS"` fails with every miss named.
MISS=
sub() { [ "$2" = "$3" ] || MISS+="$1: expected [$2], got [$3]; "; }
sub "a whole-repo search is refused" 2 "$(sg gt-1 "$WHOLE")"
T=$(try_of < "$TMP/err")
sub "the whole-repo Try names the pattern and a folder of the checkout" "rg -n -e 'it'\\''s' lib" "$T"
sub "the whole-repo Try passes the guard" 0 "$(sg gt-2 "$(bash_ "$T")")"
for i in 1 2 3; do sg gt-3 "$(jq -cn '{tool_name:"Grep", tool_input:{pattern:"a", path:"lib"}}')" >/dev/null; CLAUDE_PROJECT_DIR=$TMP/p bash "$HOOKS/builder-search-guard.sh" <<<"$(jq -cn '{tool_name:"Grep", tool_input:{pattern:"a", path:"lib"}, hook_event_name:"PostToolUse", session_id:"gt-3"}')" >/dev/null 2>&1; done
sub "the 4th search of a streak on a file is refused" 2 "$(sg gt-3 "$(jq -cn --arg p "$TMP/p/f.txt" '{tool_name:"Grep", tool_input:{pattern:"hit", path:$p}}')")"
T=$(try_of < "$TMP/err")
sub "the streak Try is a plain grep of that file" "grep -n -e 'hit' '$TMP/p/f.txt'" "$T"
sub "the streak Try passes the guard" 0 "$(sg gt-3 "$(bash_ "$T")")"
check "a refused search names a search that runs (issue 471)" "" "$MISS"; MISS=

# git-safety: a force push is printed as the lease push, from the words typed; a delete has no allowed form.
gs() { (cd "$TMP/p" && env -u COMMANDECK_BUILDER bash "$HOOKS/git-safety.sh" <<<"$(bash_ "$1")" 2>"$TMP/err" >/dev/null; echo $?); }
for C in 'git push --force origin main' 'git push -f origin main' 'git push -fu origin main' 'git push origin +main' 'cd /tmp && git push -f origin main'; do
  sub "refused: $C" 2 "$(gs "$C")"
  T=$(try_of < "$TMP/err")
  sub "its Try is a lease push that passes git-safety: $T" "0 1" "$(gs "$T") $(grep -c -- '--force-with-lease' <<<"$T")"
done
sub "a branch delete is refused" 2 "$(gs 'git push origin --delete old')"
sub "and prints no Try, as no allowed form of it exists" 0 "$(grep -c '^Try:' "$TMP/err")"

# no-poll-loops: a worker's ask over the prompt-cache limit is printed with the timeout at the limit.
npl() { (cd "$TMP/wk" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR bash "$HOOKS/no-poll-loops.sh" <<<"$(bash_ "$1")" 2>"$TMP/err" >/dev/null; echo $?); }
ASK='orca-ide orchestration ask --to w --body q --timeout-ms 600000'
sub "a worker's ask over the limit is refused" 2 "$(npl "$ASK")"
T=$(try_of < "$TMP/err")
sub "its Try is the same ask at 270000 ms" "orca-ide orchestration ask --to w --body q --timeout-ms 270000" "$T"
sub "and passes no-poll-loops" 0 "$(npl "$T")"

# suite-rerun-guard: a rerun with no edit is printed behind RERUN=1.
SP=$(jq -cn --arg d "$TMP/p" '{tool_name:"Bash", cwd:$d, tool_input:{command:"npm test"}}')
srg() { env COMMANDECK_HOOK_TIER=strict COMMANDECK_SUITE_RUNS_DIR="$TMP/runs" bash "$HOOKS/suite-rerun-guard.sh" "$@" <<<"$SP" 2>"$TMP/err" >/dev/null; echo $?; }
sub "the first run passes" 0 "$(srg)"
srg --record-complete >/dev/null
sub "the same run on the same tree is refused" 2 "$(srg)"
sub "its Try is the command behind RERUN=1" "RERUN=1 npm test" "$(try_of < "$TMP/err")"
SP=$(jq -cn --arg d "$TMP/p" '{tool_name:"Bash", cwd:$d, tool_input:{command:"RERUN=1 npm test"}}')
sub "and RERUN=1 passes" 0 "$(srg)"

sub "no check above failed" 0 "$FAIL"
check "each Try line passes its hook (issue 471)" "" "$MISS"; MISS=

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

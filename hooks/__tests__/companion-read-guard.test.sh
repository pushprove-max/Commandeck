#!/usr/bin/env bash
# companion-read-guard.test.sh -- issue 520. An edit written before the contract it depends on was read breaks
# an order the edited file does not show. read-record.sh notes each file a session reads; the guard refuses a
# listed edit until its contract is among them. Hooks run through run-hook.sh for the GNU realpath they need.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GUARD=$ROOT/hooks/companion-read-guard.sh REC=$ROOT/hooks/read-record.sh
T=$(cd "$(mktemp -d)" && pwd -P)
SA=$(uuidgen | tr A-F a-f) SB=$(uuidgen | tr A-F a-f) SC=$(uuidgen | tr A-F a-f) SD=$(uuidgen | tr A-F a-f) SE=$(uuidgen | tr A-F a-f)
trap 'rm -rf "$T"; rm -f /tmp/claude-read-tracker-{"$SA","$SB","$SC","$SD","$SE"}' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

R=$T/repo N=$T/nopairs
mkdir -p "$R/.claude" "$R/src" "$R/lib" "$N/.claude" "$N/src"
for d in "$R" "$N"; do git -C "$d" init -q -b main; printf 'x\n' > "$d/src/ring.ts"; done
printf 'x\n' > "$R/src/contract.ts"; printf 'x\n' > "$N/src/contract.ts"
: > "$R/src/empty.ts"
printf '# pairs\nno-contract-here\nsrc/ring.ts\tsrc/contract.ts\tthe pointer moves before the pin\nlib/\tsrc/contract.ts\n' > "$R/.claude/companions.tsv"

# edit <session> <repo> <repo-relative file> -> the guard's exit code; its message is left in $T/err
edit() { jq -cn --arg s "$1" --arg d "$2" --arg f "$2/$3" '{session_id: $s, cwd: $d, hook_event_name: "PreToolUse", tool_name: "Edit", tool_input: {file_path: $f, old_string: "a", new_string: "b"}}' \
  | CLAUDE_PROJECT_DIR=$2 bash "$ROOT/hooks/lib/run-hook.sh" "$GUARD" 2>"$T/err" >/dev/null; echo $?; }
# multi <session> <repo> <repo-relative file>... -- a MultiEdit whose paths sit on its edits; the guard's exit code
multi() { local s=$1 d=$2; shift 2; printf '%s\n' "$@" | jq -Rn --arg s "$s" --arg d "$d" '{session_id: $s, cwd: $d, hook_event_name: "PreToolUse", tool_name: "MultiEdit", tool_input: {edits: [inputs | {file_path: ($d + "/" + .), old_string: "a", new_string: "b"}]}}' \
  | CLAUDE_PROJECT_DIR=$d bash "$ROOT/hooks/lib/run-hook.sh" "$GUARD" 2>"$T/err" >/dev/null; echo $?; }
# record <session> <repo> <json after the common fields> -- one PostToolUse payload through read-record.sh
record() { jq -cn --arg s "$1" --arg d "$2" --argjson x "$3" '{session_id: $s, cwd: $d, hook_event_name: "PostToolUse"} + $x' \
  | CLAUDE_PROJECT_DIR=$2 bash "$ROOT/hooks/lib/run-hook.sh" "$REC" >/dev/null 2>&1; }
readx() { jq -cn --arg f "$1" '{tool_name: "Read", tool_input: {file_path: $f}, tool_response: {type: "text"}}'; }
bashx() { jq -cn --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}, tool_response: {}}'; }
tracker() { [ -e "/tmp/claude-read-tracker-$1" ] && echo yes || echo no; }

# Catches: the guard or the recorder acting with no companions.tsv: a project with no pairs refused edits or grew a tracker file.
record "$SE" "$N" "$(readx "$N/src/contract.ts")"
check "no pairs, no refusal" "0 no" "$(edit "$SE" "$N" src/ring.ts) $(tracker "$SE")"
# Catches: the tracker read wrongly, so an unread contract lets the edit through; or a refusal that omits the file to read or
# the why; or a MultiEdit, whose paths sit on its edits, passing a guard that reads the one top-level path; or a pair line
# with no contract ignored in silence, so the owner believes a pair guards a file when it guards nothing.
check "an unread contract refuses the edit" "2 1 1 1 1 2 2 2" \
  "$(edit "$SA" "$R" src/ring.ts) $(grep -c 'Read this: src/contract.ts' "$T/err") $(grep -c 'pointer moves before the pin' "$T/err") $(grep -c '`Read ' "$T/err") $(grep -c 'companions.tsv:2' "$T/err") $(edit "$SA" "$R" lib/new.ts) $(multi "$SA" "$R" src/ring.ts) $(multi "$SA" "$R" README.md lib/new.ts)"
# Catches: read-record.sh not noting a Read, so the edit stays refused after the contract was opened; or shell reads left out
# of the record, so `sed -n 1,5p contract` (the Bash route) does not open the edit.
record "$SB" "$R" "$(readx "$R/src/contract.ts")"
record "$SC" "$R" "$(bashx 'sed -n 1,5p src/contract.ts 2>&1')"
# The narrowed proof must still accept each command that does show the contract, or an honest shell read stops counting.
SHOWN=0; for c in 'cat src/contract.ts' 'cat -n src/contract.ts' 'head -3 src/contract.ts' 'tail -n 2 src/contract.ts' 'sed 1q src/contract.ts' 'sed -n 1p src/contract.ts'; do
  [ "$(python3 -I "$ROOT/hooks/lib/shell_reads.py" "$c" "$R" proof | cut -f2)" = "$R/src/contract.ts" ] && SHOWN=$((SHOWN + 1)); done
check "a read opens the edit" "0 0 0 0 6" "$(edit "$SB" "$R" src/ring.ts) $(edit "$SB" "$R" lib/new.ts) $(multi "$SB" "$R" src/ring.ts) $(edit "$SC" "$R" src/ring.ts) $SHOWN"
# Catches: the error check dropped, so a Read that failed (or a PostToolUseFailure) tells the guard the agent saw a file it
# never saw. A shell read is proof only when it ran and its output reached the agent: not in a branch that may not run, not
# one sent to a file or a pipe, and not a word in a here-document or `wc`, which prints no line of it. A query may print
# nothing, and its text cannot say so: a search, a window past the end, jq, diff, awk and an older revision prove nothing.
# A quoted glob, a `cd` the reader cannot follow and a stdout redirect spelled `2 >` show nothing either: the path it names is a guess.
record "$SD" "$R" "$(jq -cn --arg f "$R/src/contract.ts" '{tool_name: "Read", tool_input: {file_path: $f}, tool_response: {is_error: true}}')"
record "$SD" "$R" "$(jq -cn --arg f "$R/src/contract.ts" '{hook_event_name: "PostToolUseFailure", tool_name: "Read", tool_input: {file_path: $f}}')"
for c in 'false && cat src/contract.ts' 'true || cat src/contract.ts' 'if false; then cat src/contract.ts; fi' 'cat src/contract.ts > /dev/null' \
  'cat src/contract.ts | wc -l' 'wc -l src/contract.ts' 'x=$(cat src/contract.ts)' 'exit 0; cat src/contract.ts' 'sed -i s/x/y/ src/contract.ts' \
  'grep -n no-such-text src/contract.ts' 'rg no-such-text src/contract.ts' 'grep -v . src/contract.ts' 'sed -n 900,910p src/contract.ts' 'sed -n 0p src/contract.ts' \
  'head -n 0 src/contract.ts' 'tail -c 0 src/contract.ts' 'jq keys src/contract.ts' 'diff src/contract.ts src/contract.ts' "awk 'END{}' src/contract.ts" \
  'uniq -d src/contract.ts' 'git show HEAD:src/contract.ts' 'sed -n 1p src/ring.ts src/contract.ts' 'cat -s -A src/contract.ts' \
  "cat 'src/*.ts'" "cat '~/src/contract.ts'" 'cd; cat src/contract.ts' 'pushd lib; cat src/contract.ts' 'cat src/contract.ts 2 > out'; do record "$SD" "$R" "$(bashx "$c")"; done
check "an errored Read counts for nothing" "2 no 0" "$(edit "$SD" "$R" src/ring.ts) $(tracker "$SD") $(python3 -I "$ROOT/hooks/lib/shell_reads.py" 'cat src/empty.ts' "$R" proof | wc -l | tr -d ' ')"
# Catches: a shared tracker, so one session's read opens another session's edit.
check "another session's read counts for nothing" "2 0" "$(edit "$SA" "$R" src/ring.ts) $(edit "$SB" "$R" src/ring.ts)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

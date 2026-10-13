#!/usr/bin/env bash
export COMMANDECK_HOOK_TIER=strict COMMANDECK_SERENA=1
# Self-test for symbols-before-read.sh and the serena recording added to
# read-tracker.sh. Run: bash hooks/__tests__/symbols-before-read.test.sh
#
# The narrowing it pins, three parts:
#   - bounded reads (offset or limit) are gated like whole-file reads; the old
#     exemption let an implementer read 40 runtime files with serena unused.
#   - the serena log is matched on the CANONICAL repo-relative path. It used to
#     be the basename, so an overview of one `index.ts` admitted every other.
#   - no retry pass-through: a file stays blocked until serena answers for it.
#     Silence is not unavailability; only an errored serena call, or serena
#     switched off for the checkout, stands the gate down.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/hooks/symbols-before-read.sh"
TRACKER="$ROOT/hooks/read-tracker.sh"
PASS=0; FAIL=0
SID="symtest-$$"
SERENA_TRACKER="/tmp/claude-serena-tracker-${SID}"
READ_TRACKER="/tmp/claude-read-tracker-${SID}"
SERENA_DOWN="/tmp/claude-serena-down-${SID}"
# Physical path: macOS mktemp answers /var/..., git rev-parse /private/var/...
TMP=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$TMP" "$SERENA_TRACKER" "$READ_TRACKER" "$SERENA_DOWN"' EXIT

git -C "$TMP" init -q
mkdir -p "$TMP/src/routes" "$TMP/src/queue" "$TMP/src/__tests__" "$TMP/scripts/__tests__" "$TMP/ml/__tests__"
touch "$TMP/src/routes/thing.ts" "$TMP/src/routes/notes.md" \
      "$TMP/src/routes/index.ts" "$TMP/src/queue/index.ts" \
      "$TMP/src/__tests__/thing.test.ts" "$TMP/scripts/tool.ts" "$TMP/scripts/__tests__/tool.test.ts" \
      "$TMP/ml/model.py" "$TMP/ml/__tests__/model_test.py" "$TMP/src/routes/types.d.ts"
printf 'export function alphaThing() {}\nexport interface BetaShape { a: number }\nexport const GAMMA_LIMIT = 3;\nclass DeltaHelper {}\nexport type EpsilonId = string;\n' > "$TMP/src/routes/thing.ts"
# The gate reads ~/.claude.json to learn whether serena is on for this checkout.
export HOME="$TMP/home"; mkdir -p "$HOME"
printf '{"mcpServers":{"serena":{}}}\n' > "$HOME/.claude.json"

payload() { printf '{"session_id":"%s","tool_name":"%s","tool_input":%s}' "$SID" "$1" "$2"; }

check() { # name expected_exit actual_exit
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ok   $1"
  else FAIL=$((FAIL+1)); echo "  FAIL $1 (expected exit $2, got $3)"; fi
}

run_gate() { payload Read "{\"file_path\":\"$1\"}" | bash "$GATE" >/dev/null 2>&1; echo $?; }
run_gate_input() { payload Read "$1" | bash "$GATE" >/dev/null 2>&1; echo $?; }

echo "symbols-before-read.sh"
check "runtime .ts with no serena lookup is blocked" 2 "$(run_gate "$TMP/src/routes/thing.ts")"
# THE REFUSAL ANSWERS THE QUESTION ITSELF: it prints the file's top-level
# symbols and clears the directory, so the retry costs one turn, not a serena
# round trip. A file in another directory is still gated.
rm -f "$SERENA_TRACKER"
OUT=$(payload Read "{\"file_path\":\"$TMP/src/routes/thing.ts\"}" | bash "$GATE" 2>&1 >/dev/null)
for SYM in alphaThing BetaShape GAMMA_LIMIT DeltaHelper EpsilonId; do
  if printf '%s' "$OUT" | grep -qF -- "$SYM"; then PASS=$((PASS+1)); echo "  ok   the refusal lists $SYM"
  else FAIL=$((FAIL+1)); echo "  FAIL the refusal lists $SYM (got: $OUT)"; fi
done
check "the immediate retry passes"                   0 "$(run_gate "$TMP/src/routes/thing.ts")"
check "a neighbour in the same directory passes"     0 "$(run_gate "$TMP/src/routes/index.ts")"
check "a file in another directory still blocks"     2 "$(run_gate "$TMP/src/queue/index.ts")"
check "a markdown file is never blocked"             0 "$(run_gate "$TMP/src/routes/notes.md")"
check "a test file is never blocked"                 0 "$(run_gate "$TMP/src/__tests__/thing.test.ts")"
check "a .d.ts file is never blocked"                0 "$(run_gate "$TMP/src/routes/types.d.ts")"
printf 'src/routes/index.ts\n' > "$SERENA_TRACKER"
check "a scripts .ts file with no serena lookup is blocked" 2 "$(run_gate "$TMP/scripts/tool.ts")"
check "an ml .py file with no serena lookup is blocked"     2 "$(run_gate "$TMP/ml/model.py")"
check "a scripts test file is never blocked"                0 "$(run_gate "$TMP/scripts/__tests__/tool.test.ts")"
check "an ml test file is never blocked"                    0 "$(run_gate "$TMP/ml/__tests__/model_test.py")"
check "a file that does not exist is never blocked"  0 "$(run_gate "$TMP/src/routes/gone.ts")"

# --- bounded reads are gated too ---------------------------------------------
check "a Read with a limit and no serena lookup is blocked"  2 \
  "$(run_gate_input "{\"file_path\":\"$TMP/src/queue/index.ts\",\"limit\":40}")"
check "the same bounded read passes on the retry (the refusal cleared the directory)" 0 \
  "$(run_gate_input "{\"file_path\":\"$TMP/src/queue/index.ts\",\"offset\":200}")"
echo "src/queue/index.ts" > "$SERENA_TRACKER"
check "a bounded read of a file serena answered for is SILENT" "" \
  "$(payload Read "{\"file_path\":\"$TMP/src/queue/index.ts\",\"limit\":40}" | bash "$GATE" 2>&1)"
rm -f "$SERENA_TRACKER"

# --- canonical path, not basename ---------------------------------------------
echo "src/routes/index.ts" > "$SERENA_TRACKER"
check "the file serena answered for is allowed"      0 "$(run_gate "$TMP/src/routes/index.ts")"
check "a DIFFERENT file of the same name still blocks" 2 "$(run_gate "$TMP/src/queue/index.ts")"

# --- availability: silence is not unavailability ------------------------------
rm -f "$SERENA_TRACKER"
check "serena silent all session: the first file blocks" 2 "$(run_gate "$TMP/src/routes/thing.ts")"
check "serena silent all session: a file in another directory blocks too" 2 "$(run_gate "$TMP/src/queue/index.ts")"
touch "$SERENA_DOWN"
check "a serena call errored this session: the gate stands down" 0 "$(run_gate "$TMP/ml/model.py")"
rm -f "$SERENA_DOWN"
printf '{"mcpServers":{"serena":{}},"projects":{"%s":{"disabledMcpServers":["serena"]}}}\n' "$TMP" > "$HOME/.claude.json"
check "serena disabled for the checkout: the gate stands down" 0 \
  "$(cd "$TMP" && run_gate "$TMP/ml/model.py")"
printf '{"mcpServers":{"serena":{}}}\n' > "$HOME/.claude.json"

rm -f "$SERENA_TRACKER" "$READ_TRACKER"
echo
echo "read-tracker.sh"
payload mcp__serena__get_symbols_overview '{"relative_path":"src/routes/other.ts"}' | bash "$TRACKER" >/dev/null 2>&1
if grep -qxF "src/routes/other.ts" "$SERENA_TRACKER" 2>/dev/null; then
  PASS=$((PASS+1)); echo "  ok   a serena lookup is recorded in the serena tracker"
else FAIL=$((FAIL+1)); echo "  FAIL a serena lookup is recorded in the serena tracker"; fi

payload Read "{\"file_path\":\"$TMP/src/routes/thing.ts\"}" | bash "$TRACKER" >/dev/null 2>&1
if grep -q "thing.ts" "$SERENA_TRACKER" 2>/dev/null; then
  FAIL=$((FAIL+1)); echo "  FAIL a plain Read must not count as a serena lookup"
else PASS=$((PASS+1)); echo "  ok   a plain Read does not count as a serena lookup"; fi

printf '{"session_id":"%s","hook_event_name":"PostToolUseFailure","tool_name":"mcp__serena__get_symbols_overview","tool_input":{"relative_path":"src/routes/x.ts"},"error":"MCP server not connected"}' "$SID" \
  | bash "$TRACKER" >/dev/null 2>&1
if [ -e "$SERENA_DOWN" ]; then PASS=$((PASS+1)); echo "  ok   an errored serena call records unavailability"
else FAIL=$((FAIL+1)); echo "  FAIL an errored serena call records unavailability"; fi
payload mcp__serena__find_symbol '{"relative_path":"src/routes/x.ts"}' | bash "$TRACKER" >/dev/null 2>&1
if [ -e "$SERENA_DOWN" ]; then FAIL=$((FAIL+1)); echo "  FAIL a later serena answer clears unavailability"
else PASS=$((PASS+1)); echo "  ok   a later serena answer clears unavailability"; fi

# --- main may read a worker's worktree through the Read tool ------------------
# The owner took the block on main reading a worktree out of the shell guard
# on 2026-09-25 (bash-guardrails.test.sh keeps it gone). The same block here
# outlived it: `cat <wt>/out.log` passed and Read of that file did not. These
# paths are deliberately NOT runtime .ts files, so the serena gate has no say.
WT_FIXTURE=$HOME/orca/workspaces/demo-project/unit-x

# Main's seat is a plain checkout; the suite itself may run from a worktree.
check "main may read a worktree log through Read" 0 "$(cd "$TMP" && run_gate "$WT_FIXTURE/out.log")"
check "main may search a worktree (tool_input.path)" 0 \
  "$(cd "$TMP" && run_gate_input "{\"path\":\"$WT_FIXTURE\"}")"
check "a worktree report under .claude/briefs stays readable" 0 \
  "$(run_gate "$WT_FIXTURE/.claude/briefs/unit-x-r1-reports.md")"
check "a path outside the workspaces root is unaffected" 0 "$(run_gate "$TMP/src/routes/notes.md")"

# A worker reads its own tree all day. Its seat is a linked worktree, where
# git-dir and git-common-dir differ.
WORKER_TMP=$(mktemp -d)
git -C "$WORKER_TMP" init -q 2>/dev/null
git -C "$WORKER_TMP" -c user.email=t@t -c user.name=t commit -q --allow-empty -m x 2>/dev/null
git -C "$WORKER_TMP" worktree add -q "$WORKER_TMP/wt" -b wtb >/dev/null 2>&1
WORKER_RC=$( cd "$WORKER_TMP/wt" && payload Read "{\"file_path\":\"$WT_FIXTURE/out.log\"}" \
  | bash "$GATE" >/dev/null 2>&1; echo $? )
check "a worker seat may read under the workspaces root" 0 "$WORKER_RC"
rm -rf "$WORKER_TMP"

# --- main reads a driver script's --help, not its source ----------------------
# Main opened orchestration script source ~45 times in 12 hours to learn how to
# call it (2026-09-18). A script that answers --help gets a --help hint on a
# source read in main, as advice: the read always passes, because refusing a
# harmless read cost a turn and redirected nothing (2026-10-01). A worker
# worktree and a script with no --help get no hint.
echo
echo "script source reads in main"
SH=$(mktemp -d); git -C "$SH" init -q
mkdir -p "$SH/scripts/__tests__"
printf 'case "${1:-}" in --help|-h) echo usage; exit 0 ;; esac\n' > "$SH/scripts/unit-drive.sh"
printf 'echo no help here\n' > "$SH/scripts/plain.sh"
printf 'echo test\n' > "$SH/scripts/__tests__/unit-drive.test.sh"
git -C "$SH" add -A && git -C "$SH" -c user.name=t -c user.email=t@t commit -qm init
git -C "$SH" worktree add -q "$SH-wt" >/dev/null 2>&1
bash_rc() { payload Bash "$(jq -cn --arg c "$1" '{command:$c}')" | bash "$GATE" >/dev/null 2>&1; echo $?; }
# Prints 0 when the call passed AND its additionalContext names the --help call.
hint_rc() { local out rc; out=$(payload "$1" "$2" | bash "$GATE" 2>/dev/null); rc=$?
  [ "$rc" = 0 ] && printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null \
    | grep -qF -e "$3" && echo 0 || echo 1; }
bash_hint() { hint_rc Bash "$(jq -cn --arg c "$1" '{command:$c}')" "${2:-scripts/unit-drive.sh --help}"; }
SED='sed -n 1,80p scripts/unit-drive.sh'
check "main: a sed of a --help script passes with a --help hint" 0 "$(cd "$SH" && bash_hint "$SED")"
check "main: cat of it passes with the hint"             0 "$(cd "$SH" && bash_hint "cat scripts/unit-drive.sh")"
check "main: grep of it passes"                          0 "$(cd "$SH" && bash_rc "grep -n wake scripts/unit-drive.sh")"
check "main: head and tail pass"                         0 "$(cd "$SH" && bash_rc "head -40 scripts/unit-drive.sh | tail -5")"
check "main: running the script gets no hint"            1 "$(cd "$SH" && bash_hint "bash scripts/unit-drive.sh --help")"
check "main: a script with no --help gets no hint"       1 "$(cd "$SH" && bash_hint "cat scripts/plain.sh" "--help")"
check "main: a script's test file passes"                0 "$(cd "$SH" && bash_rc "cat scripts/__tests__/unit-drive.test.sh")"
check "main: a Read of it passes with the hint"          0 "$(cd "$SH" && hint_rc Read "{\"file_path\":\"$SH/scripts/unit-drive.sh\"}" 'scripts/unit-drive.sh --help')"
check "worktree: a sed gets no hint"                     1 "$(cd "$SH-wt" && SID=wt-$$ bash_hint "$SED")"
check "worktree: a Read passes"                          0 "$(cd "$SH-wt" && SID=wt-$$ run_gate "$SH-wt/scripts/unit-drive.sh")"
rm -rf "$SH" "$SH-wt"

# --- one serena call clears its directory, not its neighbours ---------
# Workers read several files of one area in a row; clearing file by file cost a
# blocked turn per file.
echo
echo "directory clearance"
mkdir -p "$TMP/src/routes/deep"; touch "$TMP/src/routes/deep/leaf.ts"
echo "src/routes/index.ts" > "$SERENA_TRACKER"
check "a serena call on one file clears a Read of its same-dir neighbour" 0 "$(run_gate "$TMP/src/routes/thing.ts")"
check "a file in a sibling directory still blocks"  2 "$(run_gate "$TMP/src/queue/index.ts")"
check "a file in a subdirectory still blocks"       2 "$(run_gate "$TMP/src/routes/deep/leaf.ts")"
rm -f "$SERENA_TRACKER"
# A file at the repo root has no folder in its path. Its refusal must clear it
# as any other does, or a strict seat can never read it.
touch "$TMP/main.ts" "$TMP/side.ts"
check "a root-level file blocks first"              2 "$(run_gate "$TMP/main.ts")"
check "and passes on the retry"                     0 "$(run_gate "$TMP/main.ts")"
check "as does its root-level neighbour"            0 "$(run_gate "$TMP/side.ts")"
check "a root-level entry clears no folder"         2 "$(run_gate "$TMP/src/queue/index.ts")"
rm -f "$SERENA_TRACKER"

# --- a worker's first edit asks who uses the file ---------------------
# A trivial overview unblocks reads, so it proves nothing about callers. The
# first Edit to an existing source file in a worker pane is refused once unless
# serena find_referencing_symbols named the file or codebase-memory trace_path
# named a function in it.
echo
echo "first edit asks for references (worker panes)"
ED=$(cd "$(mktemp -d)" && pwd -P); git -C "$ED" init -q; mkdir -p "$ED/src/routes"
printf 'export function renderThing() {}\n' > "$ED/src/routes/thing.ts"
printf 'export const y = 1\n' > "$ED/src/routes/other.ts"
printf 'export function renderLib() {}\n' > "$ED/src/routes/lib.ts"
printf 'export const z = 1\n' > "$ED/src/routes/z.ts"
printf 'export const m = 1\n' > "$ED/src/routes/msg.ts"
printf 'export const lonelyThing = 1\n' > "$ED/src/routes/lonely.ts"
mkdir -p "$ED/scripts"; printf 'import { m } from "../src/routes/msg";\nconsole.log(m);\n' > "$ED/scripts/uses-m.ts"
git -C "$ED" add -A && git -C "$ED" -c user.name=t -c user.email=t@t commit -qm init
git -C "$ED" worktree add -q "$ED-wt" >/dev/null 2>&1
edit_in() { printf '{"session_id":"%s","tool_name":"%s","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"}}' "$SID" "$1" "$2"; }
edit_rc() { edit_in "$1" "$2" | bash "$GATE" >/dev/null 2>&1; echo $?; }
echo "src/routes/thing.ts" > "$SERENA_TRACKER"
check "main: a first Edit passes as today" 0 "$(cd "$ED" && edit_rc Edit "$ED/src/routes/thing.ts")"
check "worker: a first Edit after only an overview is refused" 2 "$(cd "$ED-wt" && edit_rc Edit "$ED-wt/src/routes/thing.ts")"
MSG_OUT=$(cd "$ED-wt" && edit_in Edit "$ED-wt/src/routes/msg.ts" | bash "$GATE" 2>&1 >/dev/null)
check "the refusal names find_referencing_symbols" 0 "$(printf '%s' "$MSG_OUT" | grep -qF 'find_referencing_symbols' && echo 0 || echo 1)"
check "the refusal names trace_path" 0 "$(printf '%s' "$MSG_OUT" | grep -qF 'trace_path' && echo 0 || echo 1)"
# The refusal answers the question itself: the files naming a top-level
# symbol of this one, never the file itself, so the retry needs no lookup turn.
check "the refusal lists a file that names its symbol" 0 "$(printf '%s\n' "$MSG_OUT" | grep -qxF 'scripts/uses-m.ts' && echo 0 || echo 1)"
check "the refusal does not list the file itself" 1 "$(printf '%s\n' "$MSG_OUT" | grep -qxF 'src/routes/msg.ts' && echo 0 || echo 1)"
check "the refusal says the retry passes" 0 "$(printf '%s' "$MSG_OUT" | grep -qF 'Retry the edit now: this file is not refused again.' && echo 0 || echo 1)"
LONELY=$(cd "$ED-wt" && edit_in Edit "$ED-wt/src/routes/lonely.ts" | bash "$GATE" 2>&1 >/dev/null)
check "a symbol nobody names reads (none found)" 0 "$(printf '%s\n' "$LONELY" | grep -qxF '(none found)' && echo 0 || echo 1)"
check "worker: the file is refused only once" 0 "$(cd "$ED-wt" && edit_rc Edit "$ED-wt/src/routes/thing.ts")"
check "worker: a Write creating a new file is not refused" 0 "$(cd "$ED-wt" && edit_rc Write "$ED-wt/src/routes/new.ts")"
payload mcp__serena__find_referencing_symbols '{"relative_path":"src/routes/other.ts","name_path":"y"}' | bash "$TRACKER" >/dev/null 2>&1
check "worker: after find_referencing_symbols on the file, the first Edit passes" 0 "$(cd "$ED-wt" && edit_rc Edit "$ED-wt/src/routes/other.ts")"
payload mcp__codebase-memory__trace_path '{"function_name":"renderLib","project":"p"}' | bash "$TRACKER" >/dev/null 2>&1
check "worker: after trace_path on a function in the file, the first Edit passes" 0 "$(cd "$ED-wt" && edit_rc MultiEdit "$ED-wt/src/routes/lib.ts")"
check "worker: a trace_path on a function elsewhere does not clear it" 2 "$(cd "$ED-wt" && edit_rc Edit "$ED-wt/src/routes/z.ts")"
rm -rf "$ED" "$ED-wt"; rm -f "$SERENA_TRACKER"

# A FILE NEW IN THE BRANCH IS NOT GATED. A Builder's first Read and
# first Edit of a file it had just created were refused, with a caller list
# that was word-match noise: a file that is not on the worktree's base has no
# shape to learn and no callers. What decides is the base, never the working
# tree: a base file deleted and written again is still a base file.
echo
echo "a file new in the branch (worker panes)"
NB=$(cd "$(mktemp -d)" && pwd -P); git -C "$NB" init -q -b main; mkdir -p "$NB/src/routes"
printf 'export const onBase = 1\n' > "$NB/src/routes/base.ts"
printf 'export const goneThenBack = 1\n' > "$NB/src/routes/gone.ts"
git -C "$NB" add -A && git -C "$NB" -c user.name=t -c user.email=t@t commit -qm init
git -C "$NB" worktree add -q "$NB-wt" -b unit >/dev/null 2>&1
printf 'export const fresh = 1\n' > "$NB-wt/src/routes/fresh.ts"
mkdir -p "$NB-wt/src/added"; printf 'export const added = 1\n' > "$NB-wt/src/added/committed.ts"
git -C "$NB-wt" rm -q src/routes/gone.ts
git -C "$NB-wt" add -A && git -C "$NB-wt" -c user.name=t -c user.email=t@t commit -qm branch
printf 'export const goneThenBack = 2\n' > "$NB-wt/src/routes/gone.ts"
printf 'export const mainNew = 1\n' > "$NB/src/routes/main-new.ts"
# Each call starts from an empty serena log: a refusal clears the directory.
nb_rc() { rm -f "$SERENA_TRACKER"; (cd "$NB-wt" && if [ "$1" = Read ]; then run_gate "$2"; else edit_rc "$1" "$2"; fi); }
check "worker: a Read of a file new in the branch passes"              0 "$(nb_rc Read "$NB-wt/src/routes/fresh.ts")"
check "worker: a first Edit of a file new in the branch passes"        0 "$(nb_rc Edit "$NB-wt/src/routes/fresh.ts")"
check "worker: a new file the branch has committed passes too"         0 "$(nb_rc Read "$NB-wt/src/added/committed.ts")"
check "worker: a Read of a file on the base is still refused"          2 "$(nb_rc Read "$NB-wt/src/routes/base.ts")"
check "worker: a first Edit of a file on the base is still refused"    2 "$(nb_rc Edit "$NB-wt/src/routes/base.ts")"
check "worker: a base file deleted and written again is still refused" 2 "$(nb_rc Read "$NB-wt/src/routes/gone.ts")"
check "worker: and so is its first Edit"                               2 "$(nb_rc Edit "$NB-wt/src/routes/gone.ts")"
check "worker: a base file reached through .. is still refused"        2 "$(nb_rc Read "$NB-wt/src/added/../routes/base.ts")"
# Only where the disk folds case (the Mac): there the other spelling opens the same base file.
if [ -f "$NB-wt/src/routes/BASE.ts" ]; then
  check "worker: a base file in another letter case is still refused"  2 "$(nb_rc Read "$NB-wt/src/routes/BASE.ts")"
  check "worker: and so is its first Edit"                             2 "$(nb_rc Edit "$NB-wt/src/routes/BASE.ts")"
fi
ln -s base.ts "$NB-wt/src/routes/alias.ts"
check "worker: a new link to a base file is still refused"             2 "$(nb_rc Read "$NB-wt/src/routes/alias.ts")"
rm -f "$SERENA_TRACKER"
check "main: a new file in the main checkout is gated as before"       2 "$(cd "$NB" && run_gate "$NB/src/routes/main-new.ts")"
# No base to compare with: the gate keeps refusing rather than guess.
git -C "$NB" branch -q -m main trunk
check "worker: with no main to compare with, a new file is still refused" 2 "$(nb_rc Read "$NB-wt/src/routes/fresh.ts")"
rm -rf "$NB" "$NB-wt"; rm -f "$SERENA_TRACKER"

# This Mac's file system ignores letter case, so SRC/routes/thing.ts opens the file the gate
# guards as src/routes/thing.ts. The two spellings are one file to the gate and to its cleared record.
mkdir -p "$TMP/docs" && touch "$TMP/docs/tool.ts"
if [ -e "$TMP/SRC/routes/thing.ts" ]; then
  check "a differently cased path to a runtime file is blocked" 2 "$(run_gate "$TMP/SRC/Routes/thing.ts")"
  check "that refusal clears the directory under its usual spelling too" 0 "$(run_gate "$TMP/src/routes/index.ts")"
  printf 'src/queue/index.ts\n' > "$SERENA_TRACKER"
  check "a serena answer under one spelling clears the file under the other" 0 "$(run_gate "$TMP/SRC/QUEUE/index.ts")"
  rm -f "$SERENA_TRACKER"
else
  echo "  skip the 4 letter-case cases: this file system tells SRC from src, so no second spelling opens the file"
  mkdir -p "$TMP/src/Queue" && touch "$TMP/src/Queue/index.ts"
  printf 'src/queue/index.ts\n' > "$SERENA_TRACKER"
  check "where the disk tells them apart, a serena answer for one directory does not clear its other-cased namesake" 2 "$(run_gate "$TMP/src/Queue/index.ts")"
  rm -f "$SERENA_TRACKER"
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

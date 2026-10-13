#!/usr/bin/env bash
export COMMANDECK_HOOK_TIER=strict COMMANDECK_SERENA=1
# Self-test for bash-symbols-before-read.sh, the shell twin of the Read gate.
# Run: bash hooks/__tests__/bash-symbols-before-read.test.sh
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/hooks/bash-symbols-before-read.sh"
PASS=0; FAIL=0
SID="bashsymtest-$$"
SERENA_TRACKER="/tmp/claude-serena-tracker-${SID}"
SERENA_DOWN="/tmp/claude-serena-down-${SID}"
# Physical path: macOS mktemp answers /var/..., git rev-parse /private/var/...
TMP=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$TMP" "$SERENA_TRACKER" "$SERENA_DOWN"' EXIT

git -C "$TMP" init -q
mkdir -p "$TMP/infra/lib" "$TMP/home" "$TMP/src/routes" "$TMP/src/__tests__" "$TMP/scripts/__tests__" "$TMP/ml/__tests__" "$TMP/scratch/logs"
printf 'export function alphaThing() {}\nexport const GAMMA_LIMIT = 3;\n' > "$TMP/src/routes/thing.ts"
touch "$TMP/src/routes/other.ts" "$TMP/src/__tests__/thing.test.ts" \
  "$TMP/scripts/tool.ts" "$TMP/scripts/__tests__/tool.test.ts" \
  "$TMP/ml/model.py" "$TMP/ml/__tests__/model_test.py" "$TMP/scratch/logs/run.log" "$TMP/infra/lib/stack.ts"
export COMMANDECK_SCRATCH="$TMP/scratch/logs"
# The gate reads ~/.claude.json to learn whether serena is on for this checkout.
export HOME="$TMP/home"
printf '{"mcpServers":{"serena":{}}}\n' > "$HOME/.claude.json"

run_keep() { printf '{"session_id":"%s","tool_name":"Bash","cwd":"%s","tool_input":{"command":%s}}' "$SID" "$TMP" "$(printf '%s' "$1" | jq -Rs .)" | bash "$GATE" >/dev/null 2>&1; echo $?; }
# A refusal now clears its directory (the retry passes), so the cases below that
# ask "does this file block?" over and over would clear each other. `run` puts
# the tracker back after each call; `run_keep` is the one-turn-retry cases.
run() { local rc; cp "$SERENA_TRACKER" "$TMP/tracker.snap" 2>/dev/null; rc=$(run_keep "$1"); if [ -e "$TMP/tracker.snap" ]; then mv "$TMP/tracker.snap" "$SERENA_TRACKER"; else rm -f "$SERENA_TRACKER"; fi; echo "$rc"; }
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ok   $1"; else FAIL=$((FAIL+1)); echo "  FAIL $1 (expected exit $2, got $3)"; fi; }

echo "bash-symbols-before-read.sh"
check "sed -n on a runtime .ts with no serena lookup is blocked" 2 "$(run "sed -n '1,80p' src/routes/thing.ts")"
check "a second read with no serena call still blocks"         2 "$(run "cat src/routes/thing.ts")"
check "serena silent all session: the next file blocks too"     2 "$(run "cat src/routes/other.ts")"
touch "$SERENA_DOWN"
check "a serena call errored this session: the gate stands down" 0 "$(run "cat src/routes/other.ts")"
rm -f "$SERENA_DOWN"
printf 'src/routes/other.ts\n' > "$SERENA_TRACKER"
check "a file serena answered for passes"                       0 "$(run "head -50 src/routes/other.ts")"
check "a file serena has not answered for blocks (serena alive)" 2 "$(run "tail -n 40 infra/lib/stack.ts")"
# The shell reads relative to where an inline cd left it, not the payload cwd.
check "a read after an inline cd resolves from the new directory" 2 "$(run "cd infra && cat lib/stack.ts")"
check "a cd behind ; counts the same"                            2 "$(run "cd infra/lib; head -50 stack.ts")"
check "a cleared file read after an inline cd passes"            0 "$(run "cd src/routes && head -50 other.ts")"
check "a cd .. round trip keeps a cleared file cleared"          0 "$(run "cd infra && cd .. && head -50 src/routes/other.ts")"
# A cd in a pipeline or sent to the background runs in a subshell; the read
# after it still happens in the original directory.
check "a cd inside a pipeline does not move the read"            2 "$(run "cd infra | cat infra/lib/stack.ts")"
check "a backgrounded cd does not move the read"                 2 "$(run "cd infra & cat infra/lib/stack.ts")"
# A cd target missing when the hook runs may be one the command creates first:
# the read is checked from both directories.
check "a cd into a directory the command creates still gates the read" 2 "$(run "mkdir -p newdir && cd newdir && cat ../infra/lib/stack.ts")"
check "a cd to a missing directory still gates the read from here"      2 "$(run "cd missing-dir; cat infra/lib/stack.ts")"
check "a cleared file after a cd to a missing directory passes"         0 "$(run "cd missing-dir; head -50 src/routes/other.ts")"
check "nl is a read"                                            2 "$(run "nl infra/lib/stack.ts")"
check "less is a read"                                          2 "$(run "less infra/lib/stack.ts")"
check "absolute path is gated too"                              2 "$(run "cat $TMP/infra/lib/stack.ts")"
check "a test file is never blocked"                            0 "$(run "cat src/__tests__/thing.test.ts")"
check "a scripts .ts file with no serena lookup is blocked"     2 "$(run "cat scripts/tool.ts")"
check "an ml .py file with no serena lookup is blocked"         2 "$(run "cat ml/model.py")"
check "a scripts test file is never blocked"                    0 "$(run "cat scripts/__tests__/tool.test.ts")"
check "an ml test file is never blocked"                        0 "$(run "cat ml/__tests__/model_test.py")"
check "grep is not a read"                                      0 "$(run "grep -n foo src/routes/thing.ts")"
check "cat of a scratch log is blocked"                         2 "$(run "cat $TMP/scratch/logs/run.log")"
check "tail -n 20 of a scratch log passes"                      0 "$(run "tail -n 20 $TMP/scratch/logs/run.log")"
check "a command with no .ts file passes"                       0 "$(run "cat package.json")"
check "a file that does not exist is never blocked"             0 "$(run "cat src/routes/gone.ts")"

# Main writes issues and runs targeted looks; neither is a whole-file read.
printf 'src/routes/other.ts\n' > "$SERENA_TRACKER"
check "a source path quoted in a gh issue body passes"          0 "$(run "gh issue create --title 'src/routes/thing.ts' --body 'cat src/routes/thing.ts; head infra/lib/stack.ts'")"
check "a bounded grep -n piped to head passes"                  0 "$(run "grep -n Bucket infra/lib/stack.ts | head -20")"
check "cat of source after a gh command blocks"              2 "$(run "gh issue view 1 && cat infra/lib/stack.ts")"
check "and the same file still blocks on the retry"          2 "$(run "gh issue view 1 && cat infra/lib/stack.ts")"
check "a cat writing a source file is not a read"               0 "$(run "cat > infra/lib/stack.ts <<'EOF'
x
EOF")"
# Serena switched off for this checkout: nothing to ask for.
printf '{"mcpServers":{"serena":{}},"projects":{"%s":{"disabledMcpServers":["serena"]}}}\n' "$TMP" > "$HOME/.claude.json"
check "serena disabled for the checkout: the gate stands down"  0 "$(run "cat infra/lib/stack.ts")"
printf '{"mcpServers":{"serena":{}}}\n' > "$HOME/.claude.json"
check "serena enabled again: the same read blocks"              2 "$(run "cat infra/lib/stack.ts")"

# One refusal names every unread file, so a five-file read costs one retry, not five.
msg() { printf '{"session_id":"%s","tool_name":"Bash","cwd":"%s","tool_input":{"command":%s}}' "$SID" "$TMP" "$(printf '%s' "$1" | jq -Rs .)" | bash "$GATE" 2>&1 >/dev/null; }
has() { if printf '%s' "$2" | grep -qF -- "$3"; then PASS=$((PASS+1)); echo "  ok   $1"; else FAIL=$((FAIL+1)); echo "  FAIL $1 (no '$3' in: $2)"; fi; }
hasnt() { if printf '%s' "$2" | grep -qF -- "$3"; then FAIL=$((FAIL+1)); echo "  FAIL $1 ('$3' in: $2)"; else PASS=$((PASS+1)); echo "  ok   $1"; fi; }
: > "$SERENA_TRACKER"
THREE="cat src/routes/thing.ts scripts/tool.ts && head infra/lib/stack.ts"
out=$(msg "$THREE")
has   "three unread files: the refusal names the first"         "$out" "src/routes/thing.ts"
has   "three unread files: the refusal names the second"        "$out" "scripts/tool.ts"
has   "three unread files: the refusal names the third"         "$out" "infra/lib/stack.ts"
check "three unread files are refused in one block"             1 "$(printf '%s' "$out" | grep -c '^BLOCKED')"
has   "the refusal says the directories are cleared for the retry" "$out" "now cleared"
printf 'src/routes/thing.ts\ninfra/lib/stack.ts\n' > "$SERENA_TRACKER"
out=$(msg "$THREE")
has   "one unread of three: the refusal names it"               "$out" "scripts/tool.ts"
hasnt "one unread of three: a read file is not named"           "$out" "src/routes/thing.ts"
hasnt "one unread of three: the other read file is not named"   "$out" "infra/lib/stack.ts"
printf 'src/routes/thing.ts\ninfra/lib/stack.ts\nscripts/tool.ts\n' > "$SERENA_TRACKER"
check "after serena calls on all three, the command passes"     0 "$(run "$THREE")"

# --- one serena call clears its directory, not its neighbours ---------
mkdir -p "$TMP/src/routes/deep" "$TMP/src/queue"; touch "$TMP/src/routes/deep/leaf.ts" "$TMP/src/queue/q.ts"
printf 'src/routes/other.ts\n' > "$SERENA_TRACKER"
check "a serena call on one file clears a shell read of its same-dir neighbour" 0 "$(run "cat src/routes/thing.ts")"
check "a file in a sibling directory still blocks"              2 "$(run "cat src/queue/q.ts")"
check "a file in a subdirectory still blocks"                   2 "$(run "cat src/routes/deep/leaf.ts")"
# A file at the repo root has no folder in its path.
touch "$TMP/main.ts" "$TMP/side.ts"; printf 'side.ts\n' > "$SERENA_TRACKER"
check "a serena call on a root-level file clears a shell read of its root-level neighbour" 0 "$(run "cat main.ts")"
check "and clears no folder"                                    2 "$(run "cat src/queue/q.ts")"

# --- worker panes read source in slices -------------------------------
# A trivial overview used to unblock a whole-file cat. In a linked worktree a
# cleared file may still only be read in bounded slices; main is unchanged.
WK=$(mktemp -d); git -C "$WK" init -q; mkdir -p "$WK/src/routes"; seq 1 200 > "$WK/src/routes/big.ts"
git -C "$WK" add -A && git -C "$WK" -c user.name=t -c user.email=t@t commit -qm init
git -C "$WK" worktree add -q "$WK-wt" >/dev/null 2>&1
win() { printf '{"session_id":"%s","tool_name":"Bash","cwd":"%s","tool_input":{"command":%s}}' "$SID" "$WK-wt" "$(printf '%s' "$1" | jq -Rs .)"; }
wrun() { win "$1" | bash "$GATE" >/dev/null 2>&1; echo $?; }
printf 'src/routes/big.ts\nsrc/routes/other.ts\n' > "$SERENA_TRACKER"
check "worker: cat of a cleared source file is refused"         2 "$(wrun "cat src/routes/big.ts")"
out=$(win "cat src/routes/big.ts" | bash "$GATE" 2>&1 >/dev/null)
has   "worker: the refusal names get_symbols_overview"          "$out" "get_symbols_overview"
has   "worker: the refusal names find_symbol with include_body" "$out" "include_body"
check "worker: a 40-line sed -n passes"                         0 "$(wrun "sed -n '1,40p' src/routes/big.ts")"
check "worker: a 61-line sed -n is refused"                     2 "$(wrun "sed -n '1,61p' src/routes/big.ts")"
# Several ranges of one file count as their sum: three ranges
# totalling 33 lines were refused under the 60-line limit.
check "worker: three sed ranges totalling 33 lines pass"        0 "$(wrun "sed -n '322,332p;360,368p;454,466p' src/routes/big.ts")"
check "worker: two sed ranges totalling exactly 60 lines pass"  0 "$(wrun "sed -n '1,30p; 101,130p' src/routes/big.ts")"
check "worker: two -e ranges and a single line totalling 21 pass" 0 "$(wrun "sed -n -e '1,10p' -e '20,+9p;40p' src/routes/big.ts")"
check "worker: two sed ranges totalling 66 lines are refused"   2 "$(wrun "sed -n '205,227p;378,420p' src/routes/big.ts")"
check "worker: two -e ranges totalling 61 lines are refused"    2 "$(wrun "sed -n -e '1,30p' -e '101,131p' src/routes/big.ts")"
check "worker: a short range beside an open-ended one is refused" 2 "$(wrun "sed -n '1,5p;200,\$p' src/routes/big.ts")"
check "worker: a short range beside another sed command is refused" 2 "$(wrun "sed -n '1,5p;/x/p' src/routes/big.ts")"
check "worker: a backwards range does not shrink the total"     2 "$(wrun "sed -n '1,58p;50,10p;60,62p' src/routes/big.ts")"
check "worker: a sed with no range is refused"                  2 "$(wrun "sed 's/a/b/' src/routes/big.ts")"
check "worker: an in-place sed is an edit, not a read"          0 "$(wrun "sed -i 's/a/b/' src/routes/big.ts")"
check "worker: head -n 60 passes"                               0 "$(wrun "head -n 60 src/routes/big.ts")"
check "worker: head -61 is refused"                             2 "$(wrun "head -61 src/routes/big.ts")"
check "worker: tail -n +100 is refused"                         2 "$(wrun "tail -n +100 src/routes/big.ts")"
check "worker: rg -C 20 passes"                                 0 "$(wrun "rg -C 20 foo src/routes/big.ts")"
check "worker: rg -A 21 is refused"                             2 "$(wrun "rg -A 21 foo src/routes/big.ts")"
check "worker: grep -nB30 is refused"                           2 "$(wrun "grep -nB30 foo src/routes/big.ts")"
check "worker: rg -A 100 over a source directory is refused"   2 "$(wrun "rg -A 100 foo src/routes/")"
check "worker: grep -rC 50 over a source root is refused"       2 "$(wrun "grep -rC 50 foo src")"
# On a file system that ignores letter case, SRC is the same source root.
if [ -e "$WK-wt/SRC" ]; then check "worker: grep -rC 50 over a differently cased source root is refused" 2 "$(wrun "grep -rC 50 foo SRC")"
else echo "  skip the letter-case source root case: this file system tells SRC from src"; fi
check "worker: rg -A 100 over a docs directory passes"         0 "$(mkdir -p "$WK-wt/docs"; wrun "rg -A 100 foo docs")"
# A search with no path operand reaches every source file under the cwd, and
# `.` names the whole checkout; both passed the operand-only check.
check "worker: a wide rg with no path is refused"               2 "$(wrun "rg -A 100 marker")"
check "worker: a wide rg over . is refused"                     2 "$(wrun "rg -A 100 marker .")"
check "worker: a wide recursive grep with no path is refused"   2 "$(wrun "grep -rA 100 marker")"
check "worker: a wide grep with no path reads stdin and passes" 0 "$(wrun "grep -A 100 marker")"
check "worker: a wide rg on piped input passes"                 0 "$(wrun "printf x | rg -A 100 marker")"
check "worker: a wide rg on a here-string passes"               0 "$(wrun "rg -A 100 marker <<< 'marker'")"
check "worker: a wide rg on redirected stdin passes"            0 "$(wrun "rg -A 100 marker < notes.txt")"
check "worker: a wide rg on an explicit - operand passes"       0 "$(wrun "rg -A 100 marker -")"
# A file filter that names only non-source files cannot reach source.
check "worker: a wide rg filtered to markdown passes"           0 "$(wrun "rg -A 100 marker -g '*.md'")"
check "worker: a wide rg filtered to the md type passes"        0 "$(wrun "rg -A 100 marker -t md")"
check "worker: a wide grep -r including only markdown passes"   0 "$(wrun "grep -rA 100 --include=*.md marker")"
check "worker: a wide rg filtered to .ts is still refused"      2 "$(wrun "rg -A 100 marker -g '*.ts'")"
check "worker: a wide rg filtered to test files passes"         0 "$(wrun "rg -A 100 marker -g '*.test.ts'")"
check "worker: a wide rg filtered to __tests__ passes"          0 "$(wrun "rg -A 100 marker -g '**/__tests__/**'")"
# rg searches a file it is handed whatever the globs say; a filter narrows
# only the directories it walks.
check "worker: a markdown glob does not exempt an explicit source file" 2 "$(wrun "rg -A 100 marker -g '*.md' src/routes/big.ts")"
check "worker: a markdown glob over a source directory passes"  0 "$(wrun "rg -A 100 marker -g '*.md' src/routes/")"
# The first operand is the pattern unless -e gives one, so a `-` there is a
# pattern and the search walks the cwd.
check "worker: a wide rg whose pattern is - is refused"         2 "$(wrun "rg -A 100 '-'")"
check "worker: a wide rg -e with no path is refused"            2 "$(wrun "rg -A 100 -e marker")"
check "worker: a wide rg -e with a - path reads stdin and passes" 0 "$(wrun "rg -A 100 -e marker -")"
check "worker: a negated glob does not narrow the search"   2 "$(wrun "rg -A 100 marker -g '!*.md'")"
check "worker: rg with no context passes"              0 "$(wrun "rg -n foo src/routes/big.ts")"
check "worker: a reviewer pane is exempt"                       0 "$(win "cat src/routes/big.ts" | COMMANDECK_REVIEWER=1 bash "$GATE" >/dev/null 2>&1; echo $?)"
check "main: cat of a cleared file still passes"                0 "$(run "cat src/routes/other.ts")"
check "main: rg -A 200 still passes"                            0 "$(run "rg -A 200 foo src/routes/other.ts")"
rm -rf "$WK" "$WK-wt"

# The wrapper that runs every self-test in the push gate asserts `0 failed` on
# stdout, so the summary is worded the way every sibling words it.
# --- the refusal answers the question: outline printed, directory cleared -----
# One-turn recovery: the first read prints the file's top-level symbols
# and records its directory as cleared, so the retry costs no serena round trip.
rm -f "$SERENA_TRACKER"
out=$(msg "cat src/routes/thing.ts")
has   "the refusal prints the file's exported function"         "$out" "alphaThing"
has   "the refusal prints the file's exported constant"         "$out" "GAMMA_LIMIT"
check "the immediate retry passes"                              0 "$(run_keep "cat src/routes/thing.ts")"
check "a neighbour in the same directory passes too"            0 "$(run_keep "cat src/routes/other.ts")"
check "a file in another directory still blocks"                2 "$(run_keep "cat infra/lib/stack.ts")"
rm -f "$SERENA_TRACKER"
check "a worker-style wide read of an unread file is refused"   2 "$(run_keep "cat src/routes/thing.ts infra/lib/stack.ts")"
check "both named files pass on the retry"                      0 "$(run_keep "cat src/routes/thing.ts infra/lib/stack.ts")"

# --- a file new in the branch -----------------------------------------
# The Read gate lets a worker read a file its branch created; a shell read of
# the same file was refused here for the same wrong reason. The base decides.
# The slice rule above is another rule and still holds for a new file.
NB=$(cd "$(mktemp -d)" && pwd -P); git -C "$NB" init -q -b main; mkdir -p "$NB/src/routes"
printf 'export const onBase = 1\n' > "$NB/src/routes/base.ts"
printf 'export const goneThenBack = 1\n' > "$NB/src/routes/gone.ts"
git -C "$NB" add -A && git -C "$NB" -c user.name=t -c user.email=t@t commit -qm init
git -C "$NB" worktree add -q "$NB-wt" -b unit >/dev/null 2>&1
printf 'export const fresh = 1\n' > "$NB-wt/src/routes/fresh.ts"
git -C "$NB-wt" rm -q src/routes/gone.ts
git -C "$NB-wt" -c user.name=t -c user.email=t@t commit -qm branch
printf 'export const goneThenBack = 2\n' > "$NB-wt/src/routes/gone.ts"
# Each call starts from an empty serena log: a refusal clears the directory.
nrun() { rm -f "$SERENA_TRACKER"; printf '{"session_id":"%s","tool_name":"Bash","cwd":"%s","tool_input":{"command":%s}}' "$SID" "$NB-wt" "$(printf '%s' "$1" | jq -Rs .)" | bash "$GATE" >/dev/null 2>&1; echo $?; }
check "worker: a bounded read of a file new in the branch passes"   0 "$(nrun "head -n 20 src/routes/fresh.ts")"
check "worker: a bounded read of a file on the base is refused"     2 "$(nrun "head -n 20 src/routes/base.ts")"
check "worker: a base file deleted and written again is refused"    2 "$(nrun "head -n 20 src/routes/gone.ts")"
check "worker: a new file beside a base file is refused for the base file" 2 "$(nrun "head -n 20 src/routes/fresh.ts src/routes/base.ts")"
check "worker: a whole cat of a new file is still a wide read"      2 "$(nrun "cat src/routes/fresh.ts")"
rm -rf "$NB" "$NB-wt"; rm -f "$SERENA_TRACKER"

# This Mac's file system ignores letter case, so SRC/routes/thing.ts opens the file the gate
# guards as src/routes/thing.ts. The two spellings are one file to the gate and to its cleared record.
mkdir -p "$TMP/docs" && touch "$TMP/docs/tool.ts"
if [ -e "$TMP/SRC/routes/thing.ts" ]; then
  check "a differently cased path to a runtime file is blocked"      2 "$(run "sed -n '1,80p' SRC/Routes/thing.ts")"
  check "and with its extension in capitals"                         2 "$(run "head -n 20 src/routes/thing.TS")"
  check "that refusal clears the directory under its usual spelling too" "2 0" "$(run_keep "cat SRC/routes/thing.ts") $(run_keep "cat src/routes/other.ts")"
  printf 'infra/lib/stack.ts\n' > "$SERENA_TRACKER"
  check "a serena answer under one spelling clears the file under the other" 0 "$(run "head -n 20 INFRA/Lib/stack.ts")"
  rm -f "$SERENA_TRACKER"
else
  echo "  skip the 5 letter-case cases: this file system tells SRC from src, so no second spelling opens the file"
  mkdir -p "$TMP/infra/Lib" && touch "$TMP/infra/Lib/stack.ts"
  printf 'infra/lib/stack.ts\n' > "$SERENA_TRACKER"
  check "where the disk tells them apart, a serena answer for one directory does not clear its other-cased namesake" 2 "$(run "head -n 20 infra/Lib/stack.ts")"
  rm -f "$SERENA_TRACKER"
fi

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

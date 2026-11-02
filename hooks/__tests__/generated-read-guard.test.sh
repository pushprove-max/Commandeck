#!/usr/bin/env bash
# generated-read-guard.test.sh -- issues 519, 509, 503. A seat that reads a 5,000-line generated file whole, or
# opens saved tool output with a shell command (a prompt nobody answers), costs tokens or stalls. The guard
# refuses both with the bounded read to use instead. It must never refuse a command that only NAMES a file
# (issue 509: a host guard refused an echo). Hooks run through run-hook.sh for the GNU realpath they need.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HOOK=$ROOT/hooks/generated-read-guard.sh
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

R=$T/repo SP="$T/folder with a space/tool-results"
mkdir -p "$R/sub" "$SP"
git -C "$R" init -q -b main
printf 'gen.json linguist-generated=true -diff\nbare.json linguist-generated\n' > "$R/.gitattributes"
printf 'inner.json linguist-generated\n' > "$R/sub/.gitattributes"
for f in gen.json bare.json sub/inner.json plain.txt; do seq 1 300 | sed 's/.*/{"a": &}/' > "$R/$f"; done
seq 1 50 > "$SP/x.txt"

# run <json> -> the hook's exit code; its message is left in $T/err
run() { printf '%s' "$1" | CLAUDE_PROJECT_DIR=$R bash "$ROOT/hooks/lib/run-hook.sh" "$HOOK" 2>"$T/err" >/dev/null; echo $?; }
readp() { jq -cn --arg f "$1" --argjson i "${2:-{\}}" '{tool_name: "Read", cwd: "'"$R"'", tool_input: ({file_path: $f} + $i)}'; }
bashp() { jq -cn --arg c "$1" '{tool_name: "Bash", cwd: "'"$R"'", tool_input: {command: $c}}'; }
said() { grep -c -- "$1" "$T/err"; }

# Catches: the generated rule removed or loosened, so a seat reads a 300-line generated file whole.
check "a whole Read is refused" "2 1 1" "$(run "$(readp "$R/gen.json")") $(said '`jq ') $(said '^BLOCKED: gen.json')"
# Catches: a window as long as the file read as ranged, so limit 5000 gets the whole file through.
# The shell's windows too: a bound that covers the file is a whole read, and a head the prefilter never saw is one as well.
check "a limit over the file is refused" "2 2 2 2 2 2" "$(run "$(readp "$R/gen.json" '{"offset":1,"limit":5000}')") $(run "$(bashp 'head -10000 gen.json')") $(run "$(bashp 'sed -n 1,99999p gen.json')") $(run "$(bashp 'tail -n 5000 gen.json')") $(run "$(bashp 'head -c 999999 gen.json')") $(run "$(bashp 'head --bytes=-1 gen.json')")"
# Catches: the guard refusing every read of a generated file, which would take away the bounded reads it recommends: a ranged
# Read, head, tail, `sed -n a,bp`, `sed Nq` and an rg with a real pattern. Head or rg treated as dumps refuse the queries the refusal names.
check "a bounded read passes" "0 0 0 0 0 0" "$(run "$(readp "$R/gen.json" '{"offset":100,"limit":20}')") $(run "$(bashp 'head -20 gen.json')") $(run "$(bashp "rg -n '\"a\": 7' gen.json")") $(run "$(bashp 'tail -5 gen.json')") $(run "$(bashp "sed -n '1,5p' gen.json")") $(run "$(bashp 'sed 5q gen.json')")"
# Catches: the shell side dropped, so cat dumps a generated file the Read tool may not. A tool that prints every line is a
# cat by another name, a pattern that matches every line too, and a dump behind a branch is still a dump.
check "a cat is refused" "2 2 2 2 2 2 2 2" "$(run "$(bashp 'cat gen.json')") $(run "$(bashp 'sort gen.json')") $(run "$(bashp 'cut -c1-80 gen.json')") $(run "$(bashp 'rg . gen.json')") $(run "$(bashp "grep '' gen.json")") $(run "$(bashp 'grep -v zzz gen.json')") $(run "$(bashp 'true && cat gen.json')") $(run "$(bashp 'if true; then cat gen.json; fi')")"
# Catches: a sed counted as a range reader whatever its script, so `sed s/a/b/ gen.json` dumps the file. A numeric address
# bounds nothing while automatic printing stays on, and a second script is not one the reader understands.
check "a sed with no range is refused" "2 2 2 2" "$(run "$(bashp "sed 's/a/b/' gen.json")") $(run "$(bashp 'sed 1,5p gen.json')") $(run "$(bashp "sed '1,5p' gen.json")") $(run "$(bashp "sed -n -e 1,5p -e '6,\$p' gen.json")")"
# Catches: only `true` accepted, so a bare `linguist-generated` (git prints `set`) is read as unmarked; and a .gitattributes
# search at the repo root only, so a marker in a subfolder is missed.
check "an attribute in any form counts" "2 2" "$(run "$(readp "$R/bare.json")") $(run "$(readp "$R/sub/inner.json")")"
# Catches: every large file refused, which would be the 400-line rule this guard does not carry.
check "an unmarked file passes" "0 0" "$(run "$(readp "$R/plain.txt")") $(run "$(bashp 'cat plain.txt')")"
# Catches: a word prefilter that decides alone (issue 509): an echo that names cat or a generated file is refused.
check "an echo label passes" "0 0 0" "$(run "$(bashp 'echo "cat gen.json"')") $(run "$(bashp 'echo gen.json')") $(run "$(bashp 'echo "reading gen.json with cat"; head -3 plain.txt')")"
# Catches: the saved-output rule missing, or a quoted path split at its space so `sed ... | rg | head` opens a prompt (issue 503).
check "a shell read of saved output is refused" "2 2 1 1" \
  "$(run "$(bashp "sed -n 1,5p \"$SP/x.txt\" | rg a | head -3")") $(run "$(bashp "cat \"$SP/x.txt\"")") $(said '`Read file_path') $(said '`Grep pattern')"
# Catches: the saved rule firing on an echo or printf that only names the path (issue 509 again, for saved output).
check "an echo naming saved output passes" "0 0" "$(run "$(bashp "echo \"$SP/x.txt\"")") $(run "$(bashp "printf '%s\\n' \"$SP/x.txt\"")")"

# Catches: every shell read of saved output refused, which leaves a seat no cheap bounded query of a big tool result.
# A match cap on rg or grep and a line cap on head or tail (1-500) pass; the guard keeps the cap on what reaches the context.
check "a bounded rg or head on saved output passes" "0 0 0 0 0 0 0 0" "$(run "$(bashp "rg -m 5 a \"$SP/x.txt\"")") $(run "$(bashp "grep -m 3 a \"$SP/x.txt\"")") $(run "$(bashp "head -n 20 \"$SP/x.txt\"")") $(run "$(bashp "tail -n 500 \"$SP/x.txt\"")") $(run "$(bashp "rg -m 1 a \"$SP/x.txt\" | head -n 3")") $(run "$(bashp "head -n 1 \"$SP/x.txt\"")") \
$(run "$(bashp "head -n 1000 -n 20 \"$SP/x.txt\"")") $(run "$(bashp "rg -m 3 -i -n a \"$SP/x.txt\"")")"
# Catches: a bound that is not a number 1-500 taken as a bound: head -n with its number missing (the path is read as the number),
# a negative or junk count, 0, 501, rg with no -m, and sed, which has no bound this check reads.
check "an absent, junk or negative bound still blocks" "2 2 2 2 2 2 2 2 2 2 2 2" "$(run "$(bashp "head -n \"$SP/x.txt\"")") $(run "$(bashp "head -n -5 \"$SP/x.txt\"")") $(run "$(bashp "head -n abc \"$SP/x.txt\"")") $(run "$(bashp "rg a \"$SP/x.txt\"")") $(run "$(bashp "head -n 0 \"$SP/x.txt\"")") $(run "$(bashp "head -n 501 \"$SP/x.txt\"")") $(run "$(bashp "tail -n +5 \"$SP/x.txt\"")") $(run "$(bashp "sed -n 1,5p \"$SP/x.txt\"")") \
$(run "$(bashp "head -n 20 -n 1000 \"$SP/x.txt\"")") $(run "$(bashp "rg -m 1 -A 10000 a \"$SP/x.txt\"")") \
$(run "$(bashp "grep -m 1 -C 50000 a \"$SP/x.txt\"")") $(run "$(bashp "head -c 100 \"$SP/x.txt\"")")"
# (pass 1) The last four above: a count the command overrides (head and tail use their last), a search context flag that
# prints past -m, and a byte count. The pass case before it gains a later smaller count and plain search flags beside -m.
# Catches: the bound of one stage excusing another: a cat of saved output next to a bounded rg is still a cat.
check "cat on saved output still blocks" "2 2 2" "$(run "$(bashp "cat \"$SP/x.txt\"")") $(run "$(bashp "rg -m 5 a \"$SP/x.txt\"; cat \"$SP/x.txt\"")") $(run "$(bashp "cat -n \"$SP/x.txt\" | head -n 5")")"
# (pass 7) Catches: a per-file cap taken as the command's bound. rg -m and head -n cap each file, so a glob, a brace, a
# directory, a second file or no path at all (rg searches the folder it runs in) prints past the cap.
mkdir -p "$SP/d"; seq 1 50 > "$SP/y.txt"; seq 1 50 > "$SP/d/z.txt"
check "a per-file cap over many saved files still blocks" "2 2 2 2 2 2 2" "$(run "$(bashp "head -n 500 \"$SP\"/*")") $(run "$(bashp "rg -m 1 a \"$SP/\"")") $(run "$(bashp "rg -m 1 a \"$SP/d\"")") \
$(run "$(bashp "head -n 500 \"$SP/x.txt\" \"$SP/y.txt\"")") $(run "$(bashp "grep -m 1 a \"$SP/x.txt\" \"$SP/y.txt\"")") $(run "$(bashp "tail -n 5 \"$SP\"/{x,y}.txt")") $(run "$(bashp "rg -m 1 \"$SP/x.txt\"")")"

# Catches: a limit that covers the file read as ranged: offset 1 and limit 300 on a 300-line file is the whole file (r9).
check "a 300-line generated file read with offset 1 and limit 300 is still refused" 2 "$(run "$(readp "$R/gen.json" '{"offset":1,"limit":300}')")"
# Catches: an absent limit taken as a bound (the one-jq read must not let an empty field slide into the next one).
check "a Read with no limit of a generated file is still refused" 2 "$(run "$(readp "$R/gen.json")")"
# Catches: an offset default lost in the one-jq read: a limit with no offset still starts at line 1, so it is a whole read.
check "a Read of a generated file with limit 5000 and no offset is refused" 2 "$(run "$(readp "$R/gen.json" '{"limit":5000}')")"
# Catches: a Read paying one jq start per field (tool, file, limit, offset): a jq shim counts the starts for one payload.
mkdir -p "$T/shim"; JQ_REAL=$(command -v jq)
printf '#!/bin/sh\necho x >> "%s/jq.log"\nexec "%s" "$@"\n' "$T" "$JQ_REAL" > "$T/shim/jq"; chmod +x "$T/shim/jq"
rm -f "$T/jq.log"; printf '%s' "$(readp "$R/gen.json" '{"offset":100,"limit":20}')" | PATH="$T/shim:$PATH" CLAUDE_PROJECT_DIR=$R bash "$ROOT/hooks/lib/run-hook.sh" "$HOOK" >/dev/null 2>&1
check "a Read of a generated file with offset 100 and limit 20 starts jq once for the payload" 1 "$(wc -l < "$T/jq.log" | tr -d ' ')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

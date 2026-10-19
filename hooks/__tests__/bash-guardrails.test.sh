#!/usr/bin/env bash
# Self-test for bash-guardrails.sh. Run directly.
# Each rule the hook refuses by: one case it must block, one it must let through.
set -u
export COMMANDECK_REVIEWER=0 COMMANDECK_HOOK_TIER=strict

HOOK="$(cd "$(dirname "$0")/.." && pwd)/bash-guardrails.sh"
PASS=0 FAIL=0

# The main-only guards read the SESSION's checkout, and a linked worktree turns
# them off. Every default case runs from a disposable MAIN repository, so a run
# from a worker worktree still exercises them instead of silently passing.
MAIN_TMP=$(mktemp -d)
git -C "$MAIN_TMP" init -q
printf '{}\n' > "$MAIN_TMP/package.json"
READ_TMP=$(mktemp -d)
trap 'rm -rf "$MAIN_TMP" "$READ_TMP"' EXIT

run_hook() { ( cd "$MAIN_TMP" && echo "$1" | "$HOOK" >/dev/null 2>&1; echo $? ); }
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
json() { jq -cn --arg cmd "$1" '{tool_input:{command:$cmd}}'; }
# A refusal these guards keep must hand back a concrete command. Take its
# `Try:` line and replay it in the same seat: it has to pass, or the advice is
# a placeholder or something another guard blocks.
check_try() { # label, command, [seat dir]
  local DIR=${3:-$MAIN_TMP} OUT TRY
  OUT=$(cd "$DIR" && json "$2" | "$HOOK" 2>&1 >/dev/null; echo "rc=$?")
  check "$1" 2 "${OUT##*rc=}"
  TRY=$(printf '%s\n' "$OUT" | sed -n 's/^Try: //p' | head -1)
  check "$1: the refusal names a Try: command" 1 "$([ -n "$TRY" ] && echo 1 || echo 0)"
  check "$1: its Try: command passes" 0 "$(cd "$DIR" && json "$TRY" | "$HOOK" >/dev/null 2>&1; echo $?)"
}

# --- heap cap on node's test runner -------
check "bare node --test blocks" 2 \
  "$(run_hook "$(json 'node --test src/x.test.ts')")"
for c in 'node"" --test a.js' "node --test'' a.js" '""node --test a.js' '"""node" --test a.js' '""\node --test a.js' 'node """--test" a.js'; do
  check "an empty pair of quotes leaves the word node runs: $c blocks" 2 "$(run_hook "$(json "$c")")"
done
check "and a capped node\"\" --test passes" 0 "$(run_hook "$(json 'node"" --max-old-space-size=4096 --test a.js')")"
check "capped segment does not vouch for an uncapped one" 2 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --test a.test.ts && node --test b.test.ts')")"
check "npm test passes" 0 \
  "$(run_hook "$(json 'npm test')")"
check "capped node --test passes" 0 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --test src/x.test.ts')")"
check "a heredoc commit message naming node --test passes" 0 \
  "$(run_hook "$(json $'git commit -m "$(cat <<\'EOF\'\nfix: the suite ran node --test without a cap\nEOF\n)"')")"

# --- no read cap (owner ruling 2026-10-14): a read of any size is the agent's call ---
head -c 40000 /dev/zero | tr '\0' 'x' >"$READ_TMP/big.md"
seq 1 400 >"$READ_TMP/long.txt"
check "a whole-file cat of a large file passes" 0 \
  "$(run_hook "$(json "cat $READ_TMP/big.md")")"
check "head and sed past 150 lines pass" 0 \
  "$(run_hook "$(json "head -400 $READ_TMP/long.txt; sed -n '1,400p' $READ_TMP/long.txt")")"

# --- repo-wide text search -------
check_try "rg with a bare pattern and no path blocks" \
  'rg foo'
check "rg with a directory passes" 0 \
  "$(run_hook "$(json "rg -n 'foo' src/services")")"
# A substitution runs in the directory its own commands leave it in, and a
# nested one inherits that: the inner rg below searches the checkout root.
mkdir -p "$MAIN_TMP/hooks"
check "a nested substitution's search after cd .. blocks" 2 \
  "$(run_hook "$(json 'cd hooks; X=$(cd ..; echo "$(rg foo .)")')")"
check "a nested substitution's search after cd into a folder passes" 0 \
  "$(run_hook "$(json 'X=$(cd hooks; echo "$(rg foo .)")')")"
# Every path is judged by `realpath -m`. A Mac's own realpath (first on a bare
# /usr/bin:/bin PATH) has no -m: the search is refused by that cause, never
# called an unbounded path the agent cannot fix by naming another one.
mkdir -p "$READ_TMP/bin"
printf '#!/bin/sh\necho "realpath: illegal option -- m" >&2\nexit 1\n' >"$READ_TMP/bin/realpath"; chmod +x "$READ_TMP/bin/realpath"
for C in 'rg foo src' 'rg foo ..' 'rg foo $HOME'; do
  OUT=$(cd "$MAIN_TMP" && json "$C" | PATH="$READ_TMP/bin:$PATH" "$HOOK" 2>&1 >/dev/null; echo "rc=$?")
  check "with no working realpath -m, '$C' is refused and names realpath" "rc=2 1" \
    "${OUT##*$'\n'} $(case "$OUT" in *'realpath -m'*) echo 1 ;; *) echo 0 ;; esac)"
done
# A here-document fed to a shell through process substitution is run, not written.
check "a here-document piped to bash through >( ) is judged as commands" 2 \
  "$(run_hook "$(json $'cat > >(bash) <<\'EOF\'\nrg -n foo\nEOF')")"
check "a >( ) after the end word is judged as commands" 2 \
  "$(run_hook "$(json $'cat <<\'EOF\' > >(bash)\nrg -n foo\nEOF')")"
check "a tee into >( ) after the end word is judged as commands" 2 \
  "$(run_hook "$(json $'tee <<\'EOF\' >(bash)\nrg -n foo\nEOF')")"
check "a here-document after exec into >( ) is judged as commands" 2 \
  "$(run_hook "$(json $'exec > >(bash)\ncat <<\'EOF\'\nrg -n foo\nEOF')")"
check "a here-document written to a file is a note" 0 \
  "$(run_hook "$(json $'cat > notes.md <<\'EOF\'\nrg -n foo\nEOF')")"
check "a here-document written to a file after the end word is a note" 0 \
  "$(run_hook "$(json $'cat <<\'EOF\' > notes.md\nrg -n foo\nEOF')")"

# --- raw pane reads keep main's context lean ------
check "pane read with no limit blocks" 2 \
  "$(run_hook "$(json 'orca-ide terminal read --terminal term_abc --json')")"
check "a commit message naming the command passes" 0 \
  "$(run_hook "$(json 'git commit -m "block every orca-ide terminal read variant"')")"
check "an unrelated orca-ide call passes" 0 \
  "$(run_hook "$(json 'orca-ide orchestration run-current --json')")"

# --- kill that can reach main's own session ----------
check "negative-pid target blocks (process group)" 2 \
  "$(run_hook "$(json 'kill -TERM -3786748 -3978349')")"
check "pkill on claude blocks" 2 \
  "$(run_hook "$(json 'pkill -f claude')")"
check "killing this hook's own parent blocks" 2 \
  "$(run_hook "$(json "kill -TERM $PPID")")"
check "bare-pid kill passes" 0 \
  "$(run_hook "$(json 'kill -TERM 3786748 3978349')")"
check "a child job the same command started passes" 0 \
  "$(run_hook "$(json 'sleep 30 & W=$!; kill $W')")"


echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

#!/usr/bin/env bash
# Self-test for bash-guardrails.sh. Run directly; BASH_GUARDRAILS_TEST_CASE=<text> runs only the cases naming <text>.
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
# BASH_GUARDRAILS_TEST_CASE=<text> runs only the cases whose name holds <text>, for a red run or a fix round;
# the closing run is the whole file. A filter that matches no case fails. Each case is `sel <name> && check ...`:
# a filter inside check would come after the case's own $( ) probes had already run.
sel() { case $1 in *"${BASH_GUARDRAILS_TEST_CASE-}"*) return 0 ;; *) return 1 ;; esac; }
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
json() { jq -cn --arg cmd "$1" '{tool_input:{command:$cmd}}'; }
# A refusal these guards keep must hand back a concrete command. Take its
# `Try:` line and replay it in the same seat: it has to pass, or the advice is
# a placeholder or something another guard blocks.
check_try() { # label, command, [seat dir]
  local DIR=${3:-$MAIN_TMP} OUT TRY
  sel "$1" || return 0
  OUT=$(cd "$DIR" && json "$2" | "$HOOK" 2>&1 >/dev/null; echo "rc=$?")
  check "$1" 2 "${OUT##*rc=}"
  TRY=$(printf '%s\n' "$OUT" | sed -n 's/^Try: //p' | head -1)
  check "$1: the refusal names a Try: command" 1 "$([ -n "$TRY" ] && echo 1 || echo 0)"
  check "$1: its Try: command passes" 0 "$(cd "$DIR" && json "$TRY" | "$HOOK" >/dev/null 2>&1; echo $?)"
}

# --- heap cap on node's test runner -------
sel "bare node --test blocks" && check "bare node --test blocks" 2 \
  "$(run_hook "$(json 'node --test src/x.test.ts')")"
for c in 'node"" --test a.js' "node --test'' a.js" '""node --test a.js' '"""node" --test a.js' '""\node --test a.js' 'node """--test" a.js'; do
  sel "an empty pair of quotes leaves the word node runs: $c blocks" && check "an empty pair of quotes leaves the word node runs: $c blocks" 2 "$(run_hook "$(json "$c")")"
done
sel "and a capped node\"\" --test passes" && check "and a capped node\"\" --test passes" 0 "$(run_hook "$(json 'node"" --max-old-space-size=4096 --test a.js')")"
sel "capped segment does not vouch for an uncapped one" && check "capped segment does not vouch for an uncapped one" 2 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --test a.test.ts && node --test b.test.ts')")"
# Issue 282: the cap's allowance is 4096 or lower; a larger heap flag, in either spelling, beside it or alone blocks.
for c in 'node --max-old-space-size=8192 --test a.js' 'node --max-old-space-size=4096 --max_old_space_size=8192 --test a.js'; do
  sel "a heap flag over 4096 blocks: $c" && check "a heap flag over 4096 blocks: $c" 2 "$(run_hook "$(json "$c")")"
done
sel "npm test passes" && check "npm test passes" 0 \
  "$(run_hook "$(json 'npm test')")"
sel "capped node --test passes" && check "capped node --test passes" 0 \
  "$(run_hook "$(json 'node --max-old-space-size=4096 --test src/x.test.ts')")"
sel "a heredoc commit message naming node --test passes" && check "a heredoc commit message naming node --test passes" 0 \
  "$(run_hook "$(json $'git commit -m "$(cat <<\'EOF\'\nfix: the suite ran node --test without a cap\nEOF\n)"')")"

# --- no read cap (owner ruling 2026-10-14): a read of any size is the agent's call ---
head -c 40000 /dev/zero | tr '\0' 'x' >"$READ_TMP/big.md"
seq 1 400 >"$READ_TMP/long.txt"
sel "a whole-file cat of a large file passes" && check "a whole-file cat of a large file passes" 0 \
  "$(run_hook "$(json "cat $READ_TMP/big.md")")"
sel "head and sed past 150 lines pass" && check "head and sed past 150 lines pass" 0 \
  "$(run_hook "$(json "head -400 $READ_TMP/long.txt; sed -n '1,400p' $READ_TMP/long.txt")")"

# --- repo-wide text search -------
check_try "rg with a bare pattern and no path blocks" \
  'rg foo'
sel "rg with a directory passes" && check "rg with a directory passes" 0 \
  "$(run_hook "$(json "rg -n 'foo' src/services")")"
# A substitution runs in the directory its own commands leave it in, and a
# nested one inherits that: the inner rg below searches the checkout root.
mkdir -p "$MAIN_TMP/hooks"
sel "a nested substitution's search after cd .. blocks" && check "a nested substitution's search after cd .. blocks" 2 \
  "$(run_hook "$(json 'cd hooks; X=$(cd ..; echo "$(rg foo .)")')")"
sel "a nested substitution's search after cd into a folder passes" && check "a nested substitution's search after cd into a folder passes" 0 \
  "$(run_hook "$(json 'X=$(cd hooks; echo "$(rg foo .)")')")"
# Every path is judged by `realpath -m`. A Mac's own realpath (first on a bare
# /usr/bin:/bin PATH) has no -m: the search is refused by that cause, never
# called an unbounded path the agent cannot fix by naming another one.
mkdir -p "$READ_TMP/bin"
printf '#!/bin/sh\necho "realpath: illegal option -- m" >&2\nexit 1\n' >"$READ_TMP/bin/realpath"; chmod +x "$READ_TMP/bin/realpath"
for C in 'rg foo src' 'rg foo ..' 'rg foo $HOME'; do
  sel "with no working realpath -m, '$C' is refused and names realpath" || continue
  OUT=$(cd "$MAIN_TMP" && json "$C" | PATH="$READ_TMP/bin:$PATH" "$HOOK" 2>&1 >/dev/null; echo "rc=$?")
  check "with no working realpath -m, '$C' is refused and names realpath" "rc=2 1" \
    "${OUT##*$'\n'} $(case "$OUT" in *'realpath -m'*) echo 1 ;; *) echo 0 ;; esac)"
done
# A here-document fed to a shell through process substitution is run, not written.
sel "a here-document piped to bash through >( ) is judged as commands" && check "a here-document piped to bash through >( ) is judged as commands" 2 \
  "$(run_hook "$(json $'cat > >(bash) <<\'EOF\'\nrg -n foo\nEOF')")"
sel "a >( ) after the end word is judged as commands" && check "a >( ) after the end word is judged as commands" 2 \
  "$(run_hook "$(json $'cat <<\'EOF\' > >(bash)\nrg -n foo\nEOF')")"
sel "a tee into >( ) after the end word is judged as commands" && check "a tee into >( ) after the end word is judged as commands" 2 \
  "$(run_hook "$(json $'tee <<\'EOF\' >(bash)\nrg -n foo\nEOF')")"
sel "a here-document after exec into >( ) is judged as commands" && check "a here-document after exec into >( ) is judged as commands" 2 \
  "$(run_hook "$(json $'exec > >(bash)\ncat <<\'EOF\'\nrg -n foo\nEOF')")"
sel "a here-document written to a file is a note" && check "a here-document written to a file is a note" 0 \
  "$(run_hook "$(json $'cat > notes.md <<\'EOF\'\nrg -n foo\nEOF')")"
sel "a here-document written to a file after the end word is a note" && check "a here-document written to a file after the end word is a note" 0 \
  "$(run_hook "$(json $'cat <<\'EOF\' > notes.md\nrg -n foo\nEOF')")"

# --- a worker's unbounded search is rewritten to the checkout root, capped at 200 lines, with its own exit ---
# A throwaway main checkout and a linked worktree of it: the hook tells them apart by git-dir vs git-common-dir.
GBOX=$(mktemp -d)
trap 'rm -rf "$MAIN_TMP" "$READ_TMP" "$GBOX"' EXIT
git -C "$GBOX" init -q -b main main
git -C "$GBOX/main" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$GBOX/main" worktree add -q "$GBOX/wt" -b u1
in_dir() { (cd "$1" && json "$2" | env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR "$HOOK" 2>/dev/null); }
WT_ROOT=$(cd "$GBOX/wt" && git rev-parse --show-toplevel)
WL="worker root rewrite capped; main still blocked; \$f still blocked"
CAP='2>&1 | { head -n 200; cat >/dev/null; } )'
OUT=$(in_dir "$GBOX/wt" "rg -n foo")
sel "$WL" && {
  check "$WL: no path becomes the root, capped" "( set -o pipefail; { 'rg' '-n' 'foo' '$WT_ROOT'; } $CAP" "$(jq -r '.hookSpecificOutput.updatedInput.command' <<<"$OUT")"
  check "$WL: no permissionDecision" false "$(jq -r '.hookSpecificOutput | has("permissionDecision")' <<<"$OUT")"
  check "$WL: dot becomes the root, capped" "( set -o pipefail; { 'rg' 'foo' '$WT_ROOT'; } $CAP" \
    "$(in_dir "$GBOX/wt" 'rg foo .' | jq -r '.hookSpecificOutput.updatedInput.command')"
  check "$WL: a literal parent becomes the root, capped" "( set -o pipefail; { 'rg' 'foo' '$WT_ROOT'; } $CAP" \
    "$(in_dir "$GBOX/wt" "rg foo $GBOX" | jq -r '.hookSpecificOutput.updatedInput.command')"
  check "$WL: main still blocked" 2 "$(in_dir "$GBOX/main" 'rg foo .' >/dev/null; echo $?)"
  check "$WL: \$f still blocked" 2 "$(in_dir "$GBOX/wt" 'rg foo "$f"' >/dev/null; echo $?)"
}
# A rewrite runs a different search than the one asked for when it leaves an unbounded operand or re-quotes what the
# shell would expand; those stay refused.
RW="a rewrite never changes what the search covers or matches"
sel "$RW" && {
  check "$RW: a second unbounded operand" 2 "$(in_dir "$GBOX/wt" 'rg -n foo . /' >/dev/null; echo $?)"
  check "$RW: a variable pattern" 2 "$(in_dir "$GBOX/wt" 'rg -n "$needle" .' >/dev/null; echo $?)"
  check "$RW: an unquoted glob" 2 "$(in_dir "$GBOX/wt" 'rg foo* .' >/dev/null; echo $?)"
}
# A rewrite replaces the call's text, so it must run exactly what the call would: anything the shell would expand,
# split or run keeps the refusal the call had before the rewrite.
RR="a rewrite runs exactly what the call would"
refused_worker() { # <label> <dir> <command>
  local O; O=$(in_dir "$2" "$3"; echo "rc=$?")
  check "$RR: $1" "refused rc=2" "$(grep -q updatedInput <<<"$O" && echo rewritten || echo refused) ${O##*$'\n'}"
}
sel "$RR" && {
  refused_worker "a command substitution pattern" "$GBOX/wt" 'rg -n "$(touch x)" .'
  refused_worker "a backtick" "$GBOX/wt" 'rg -n "`touch x`" .'
  refused_worker "a backslash" "$GBOX/wt" 'rg -n a\ b .'
  refused_worker "a quote kind hiding a glob" "$GBOX/wt" "rg \"a'b\" * \"c'd\""
  refused_worker "a piped second command" "$GBOX/wt" 'rg -n foo . | sort -o /tmp/x'
  refused_worker "a command substitution from a plain checkout" "$GBOX/main" 'rg -n "$(touch x)" .'
  refused_worker "mixed quotes and a glob from a plain checkout" "$GBOX/main" "rg \"a'b\" * \"c'd\""
  check "$RR: a worker's rg -n foo . is still rewritten" "( set -o pipefail; { 'rg' '-n' 'foo' '$WT_ROOT'; } $CAP" \
    "$(in_dir "$GBOX/wt" 'rg -n foo .' | jq -r '.hookSpecificOutput.updatedInput.command')"
}
# #418: the rewritten text runs the search to its end, so its exit is rg's own (0, 1 or 2), never head's or 141.
RX="a rewritten search returns rg's own exit"
sel "$RX" && {
  RXBOX=$(mktemp -d)
  printf 'a\nb\nc\n' >"$RXBOX/one.txt"; printf 'd\ne\n' >"$RXBOX/two.txt"; seq 1 300 | sed 's/^/hit /' >"$RXBOX/flood.txt"
  # rx_run <shell> <dir> <rg args...>: the hook's rewritten command run in <shell> inside <dir>; prints "<exit> <lines>".
  rx_run() {
    local SH=$1 D=$2 CMD OUT N; shift 2
    CMD=$(in_dir "$GBOX/wt" "rg $*" | jq -r '.hookSpecificOutput.updatedInput.command')
    CMD=${CMD//"$WT_ROOT"/$D}
    OUT=$(cd "$D" && timeout 20 "$SH" -c "$CMD"; echo "rc=$?")
    N=$(printf '%s\n' "${OUT%rc=*}" | grep -c .)
    echo "${OUT##*rc=} $N"
  }
  for SH in bash zsh; do
    command -v "$SH" >/dev/null 2>&1 || continue
    check "$RX: $SH, no match gives 1" "1 0" "$(rx_run "$SH" "$RXBOX" -q "'a^'" .)"
    check "$RX: $SH, a bad pattern gives 2" "2 1" "$(rx_run "$SH" "$RXBOX" "'['" . | sed 's/ [0-9]*$/ 1/')"
    check "$RX: $SH, a 300-line match gives 0 with 200 lines" "0 200" "$(rx_run "$SH" "$RXBOX" -N hit .)"
  done
  rm -rf "$RXBOX"
}
# The rewrite is rebuilt from the parsed words, so a word the parser drops (a leading `!` or `time`, a second line, a
# trailing comment) would vanish from what runs: those calls stay refused (exit 2, no updatedInput).
NG="a negated search is never rewritten"
sel "$NG" && {
  for C in "! rg -q 'a^' ." "time rg -q foo ." $'rg foo .\nrg bar .' 'rg foo . # note'; do
    O=$(in_dir "$GBOX/wt" "$C"; echo "rc=$?")
    check "$NG: $C" "refused rc=2" "$(grep -q updatedInput <<<"$O" && echo rewritten || echo refused) ${O##*$'\n'}"
  done
}
# The rewrite replaces the operand it judged unbounded, by position, never a pattern word equal to it.
IX="a rewrite replaces the operand, never a pattern equal to it"
sel "$IX" && {
  IXBOX=$(mktemp -d); printf 'a\n' >"$IXBOX/one.txt"
  IXCMD=$(in_dir "$GBOX/wt" "rg -q -e 'a^' . -e ." | jq -r '.hookSpecificOutput.updatedInput.command')
  check "$IX: both -e patterns survive" "1 1" "$(case $IXCMD in *"'a^'"*) echo 1 ;; *) echo 0 ;; esac) $(grep -o "'-e' '\.'" <<<"$IXCMD" | grep -c .)"
  IXCMD=${IXCMD//"$WT_ROOT"/$IXBOX}
  ORIG=$(cd "$IXBOX" && rg -q -e 'a^' . -e . ; echo $?)
  check "$IX: the rewritten exit equals the original's" "$ORIG" "$(cd "$IXBOX" && timeout 20 bash -c "$IXCMD"; echo $?)"
  rm -rf "$IXBOX"
}

# --- raw pane reads keep main's context lean ------
sel "pane read with no limit blocks" && check "pane read with no limit blocks" 2 \
  "$(run_hook "$(json 'orca-ide terminal read --terminal term_abc --json')")"
sel "a commit message naming the command passes" && check "a commit message naming the command passes" 0 \
  "$(run_hook "$(json 'git commit -m "block every orca-ide terminal read variant"')")"
sel "an unrelated orca-ide call passes" && check "an unrelated orca-ide call passes" 0 \
  "$(run_hook "$(json 'orca-ide orchestration run-current --json')")"

# --- kill that can reach main's own session ----------
sel "negative-pid target blocks (process group)" && check "negative-pid target blocks (process group)" 2 \
  "$(run_hook "$(json 'kill -TERM -3786748 -3978349')")"
sel "pkill on claude blocks" && check "pkill on claude blocks" 2 \
  "$(run_hook "$(json 'pkill -f claude')")"
sel "killing this hook's own parent blocks" && check "killing this hook's own parent blocks" 2 \
  "$(run_hook "$(json "kill -TERM $PPID")")"
sel "bare-pid kill passes" && check "bare-pid kill passes" 0 \
  "$(run_hook "$(json 'kill -TERM 3786748 3978349')")"
sel "a child job the same command started passes" && check "a child job the same command started passes" 0 \
  "$(run_hook "$(json 'sleep 30 & W=$!; kill $W')")"

# --- inline-script writes in a Builder (issue 247) -------
# An inline script that writes a tracked file goes around Edit, so the guards on Edit never see the change.
mkdir -p "$MAIN_TMP/scripts" && echo old > "$MAIN_TMP/scripts/x.sh" && git -C "$MAIN_TMP" add scripts/x.sh
bld() { ( cd "$MAIN_TMP" && json "$1" | COMMANDECK_BUILDER=1 COMMANDECK_HOOK_TIER=default "$HOOK" >/dev/null 2>&1; echo $? ); }
sel "a Builder's python3 -c that writes a tracked file blocks, in any tier" && check "a Builder's python3 -c that writes a tracked file blocks, in any tier" 2 \
  "$(bld "python3 -c \"open('scripts/x.sh','w').write('new')\"")"
sel "a Builder's python3 heredoc that names the tracked file in a variable blocks" && check "a Builder's python3 heredoc that names the tracked file in a variable blocks" 2 \
  "$(bld $'python3 - <<\'EOF\'\np = "scripts/x.sh"\nopen(p, "w").write("new")\nEOF')"
sel "the same write to \$TMPDIR passes, and a read of the tracked file passes" && check "the same write to \$TMPDIR passes, and a read of the tracked file passes" "0 0" \
  "$(bld "python3 -c \"open('\$TMPDIR/x','w').write('new')\"") $(bld "python3 -c \"print(open('scripts/x.sh').read())\"")"
sel "a seat that is no Builder is not asked" && check "a seat that is no Builder is not asked" 0 \
  "$( ( cd "$MAIN_TMP" && json "python3 -c \"open('scripts/x.sh','w').write('new')\"" | env -u COMMANDECK_BUILDER COMMANDECK_HOOK_TIER=default "$HOOK" >/dev/null 2>&1; echo $? ) )"

# r1: the guard reads where each write call writes. Every other write API, and a script fed by stdin, is the same
# way round Edit; a script that reads a tracked file and writes a scratch one writes no tracked file.
for W in "python3 -c \"from pathlib import Path; Path('scripts/x.sh').write_bytes(b'new')\"" \
  "node -e \"require('fs').writeFile('scripts/x.sh','new',()=>{})\"" \
  "node -e \"require('fs').appendFileSync('scripts/x.sh','new')\"" \
  "node -e \"require('fs').createWriteStream('scripts/x.sh').end('new')\"" \
  $'python3 <<\'EOF\'\nopen("scripts/x.sh", "a").write("new")\nEOF' \
  "echo 'open(\"scripts/x.sh\",\"w\").write(\"new\")' | python3" \
  "python3 -c \"import shutil; shutil.copy('/tmp/a', 'scripts/x.sh')\"" \
  "python3 -c \"import os; os.replace('/tmp/a', 'scripts/x.sh')\"" \
  "python3 -c \"m='w'; open('scripts/x.sh', m).write('new')\"" \
  "python3 -c \"import io; io.open('scripts/x.sh', mode='w').write('new')\"" \
  "perl -pi -e 's/old/new/' scripts/x.sh" \
  "perl -e 'open(my \$f, \">\", \"scripts/x.sh\"); print \$f \"new\"'" \
  "perl -e 'open(F, \">>scripts/x.sh\"); print F \"new\"'" \
  "python3 -c \"import os; os.remove('scripts/x.sh')\"" \
  "/usr/bin/python3 -c \"open('scripts/x.sh','w').write('new')\"" \
  "/usr/bin/env perl -pi -e 's/old/new/' scripts/x.sh" \
  "python3 -c \"from pathlib import Path; p=Path('scripts/x.sh'); p.write_bytes(b'new')\"" \
  "python3 -c \"import pathlib; p = pathlib.Path('scripts/x.sh'); f = p.open(mode='w')\"" \
  "python3 -c \"from pathlib import Path; (Path('scripts') / 'x.sh').write_text('new')\"" \
  "node -e 'require(\"fs\").writeFileSync(\`scripts/x.sh\`,\"new\")'" \
  "node -e 'const d=\`scripts\`; require(\"fs\").writeFileSync(\`\${d}/x.sh\`,\"new\")'" \
  "perl -e 'open(my \$f, \">\", q(scripts/x.sh)); print \$f \"new\"'" \
  "python3 -c \"from pathlib import Path; p=Path('scripts/x.sh'); m='w'; p.open(mode=m).write('new')\"" \
  "python3 -c \"from pathlib import Path; p=Path('scripts/x.sh'); m='w'; p.open(m).write('new')\"" \
  "python3 -c \"from pathlib import Path; m='w'; Path('scripts/x.sh').open(m).write('new')\"" \
  "python3 -c \"import io; m='w'; io.open('scripts/x.sh', m).write('new')\"" \
  "node -e \"const fs=require('fs'); fs.writeSync(fs.openSync('scripts/x.sh','w'),'new')\"" \
  "node -e \"const fs=require('fs'); const f='w'; fs.openSync('scripts/x.sh', f)\"" \
  "node -e \"require('fs').openSync('scripts/x.sh','w')\"" \
  "node -e \"const fs=require('fs'); const FILE='scripts/x.sh'; fs.openSync(FILE,'w')\"" \
  "python3 -c \"FILE='scripts/x.sh'; open(FILE,'w').write('new')\"" \
  "node -e \"const fs=require('fs'); let flags; fs.openSync('scripts/x.sh', flags='w')\"" \
  "node -e \"require('fs').promises.open('scripts/x.sh', flags='w')\"" \
  "node -e \"const fsp=require('fs/promises'); fsp.open('scripts/x.sh','w')\"" \
  "python3 -c \"from pathlib import Path; io=Path('scripts/x.sh'); io.open('w').write('new')\"" \
  "python3 -c \"import io; from pathlib import Path; io=Path('scripts/x.sh'); m='w'; io.open(m)\"" \
  "node -e \"const {open}=require('fs'); open('scripts/x.sh','w',()=>{})\"" \
  "node -e \"const {writeFileSync: w}=require('fs'); w('scripts/x.sh','new')\"" \
  "node -e \"const {openSync: o}=require('fs'); o('scripts/x.sh','w')\"" \
  "python3 -c \"from shutil import copy as c; c('/tmp/a', 'scripts/x.sh')\"" \
  "python3 -c \"from shutil import copy as f; f('/tmp/a', 'scripts/x.sh'); from io import open as f\"" \
  "python3 -c \"from io import open as copy; import shutil; shutil.copy('/tmp/a', 'scripts/x.sh')\"" \
  $'python3 -c "from io import open as copy\nfrom shutil import copy\ncopy(\'/tmp/a\', \'scripts/x.sh\')"' \
  $'python3 -c "from shutil import copy as c\n# Copy.\nc(\'/etc/hosts\',\'scripts/x.sh\')"' \
  $'node -e "const {copyFileSync: c}=require(\'fs\') // copy.\nc(\'/etc/hosts\',\'scripts/x.sh\')"' \
  $'python3 -c "from shutil import copy as c; x = 1.\nc(\'/etc/hosts\',\'scripts/x.sh\')"' \
  "node -e \"const {copyFileSync: c}=require('fs'); Math.max(...c('/etc/hosts','scripts/x.sh'))\"" \
  $'node -e "const {readFileSync: unlink}=require(\'fs\'); require(\'fs\').\nunlink(\'scripts/x.sh\',()=>{})"' \
  $'node -e "const {readFileSync: unlink}=require(\'fs\'); require(\'fs\')\n  .unlink(\'scripts/x.sh\',()=>{})"' \
  $'python3 -c "from io import open as copy; import shutil; shutil.\\\ncopy(\'/tmp/a\', \'scripts/x.sh\')"' \
  $'python3 -c "from io import open as copy; import shutil; (shutil\n .copy(\'/tmp/a\', \'scripts/x.sh\'))"' \
  $'python3 -c "from io import open as copy; import shutil; ((\'#\', shutil)[1].\ncopy(\'/tmp/a\', \'scripts/x.sh\'))"' \
  "python3 -c \"from os import *; from io import open as remove; remove('scripts/x.sh')\"" \
  "python3 -c \"import io; from pathlib import Path; io, other = Path('scripts/x.sh'), None; io.open('w').write('new')\"" \
  "python3 -c \"import io; from pathlib import Path; io: Path = Path('scripts/x.sh'); io.open('w').write('new')\"" \
  "python3 -c \"import io; from pathlib import Path; (io := Path('scripts/x.sh')).open('w')\"" \
  "python3 -c \"import io; from pathlib import Path\nfor io in [Path('scripts/x.sh')]: io.open('w')\"" \
  "node -e \"const {open}=require('fs'); const {writeFileSync}=require('fs'); writeFileSync('/tmp/y','ok'); open('scripts/x.sh','a',()=>{})\"" \
  $'python3 -c "from io import open as copy; import shutil; ((1//1, shutil)[1].\ncopy(\'/etc/hosts\', \'scripts/x.sh\'))"' \
  $'node -e "class A { #r = require(\'fs\'); w() { return this.#r.\ncopyFileSync(\'/etc/hosts\', \'scripts/x.sh\') } }; const {readFileSync: copyFileSync}=require(\'fs\'); new A().w()"' \
  "perl -e 'open F, \">\", \"scripts/x.sh\"; print F \"new\"'"; do
  sel "a Builder's tracked write blocks: $W" && check "a Builder's tracked write blocks: $W" 2 "$(bld "$W")"
done
# Ruling 1: reads stay allowed. open with no mode or a literal read mode is a read; a path built in code is out of scope (the last one).
for W in "python3 -c \"print(open('scripts/x.sh').read(), open('scripts/x.sh', 'rb').read(), open('scripts/x.sh', 'rt').read())\"" \
  "python3 -c \"import json; json.load(open('scripts/x.sh'))\"" \
  "node -e \"console.log(require('fs').readFileSync('scripts/x.sh','utf8'), require('fs').openSync('scripts/x.sh'))\"" \
  "node -e \"const {open}=require('fs'); open('scripts/x.sh','r',()=>{})\"" \
  "perl -e 'open F, \"<\", \"scripts/x.sh\"; print <F>'" \
  "perl -e 'open(my \$f, \"scripts/x.sh\"); print <\$f>'" \
  "python3 -c \"from pathlib import Path; print(Path('scripts/x.sh').read_text())\"" \
  "perl -ne 'print if /old/' scripts/x.sh" \
  "python3 -c \"from pathlib import Path; p=Path('scripts/x.sh'); print(p.open().read(), p.open('r').read(), p.open(encoding='utf8').read())\"" \
  "python3 -c \"from pathlib import Path; print(Path('scripts/x.sh').open(mode='r').read())\"" \
  "node -e \"const fs=require('fs'); fs.readSync(fs.openSync('scripts/x.sh','r'), Buffer.alloc(9))\"" \
  "python3 -c \"print(open('scripts/x.sh', encoding='latin-1').read())\"" \
  "node -e \"const fs=require('fs'); let flags; fs.readSync(fs.openSync('scripts/x.sh', flags='r'), Buffer.alloc(9))\"" \
  "python3 -c \"import io; print(io.open('scripts/x.sh').read())\"" \
  "python3 -c \"import io, os; print(io.open('scripts/x.sh').read(), os.sep)\"" \
  "python3 -c \"import shutil; shutil.copy('/tmp/a', 'scr' + 'ipts/x.sh')\""; do
  sel "a Builder's read of a tracked file passes: $W" && check "a Builder's read of a tracked file passes: $W" 0 "$(bld "$W")"
done
# Ruling 1 (2026-10-20): presence, not parsing. A read that holds a writer name (an alias, a comment) or a
# writing open beside a tracked path is refused too; that false refusal is accepted.
for W in "python3 -c \"data=open('scripts/x.sh').read(); open('/tmp/commandeck-copy.txt','w').write(data)\"" \
  "node -e \"const fs=require('fs'); fs.writeFileSync('/tmp/y', fs.readFileSync('scripts/x.sh'))\"" \
  "python3 -c \"open('scripts/x.sh', 'r').read(); open('/tmp/z', 'wb')\"" \
  "python3 -c \"from pathlib import Path; p=Path('scripts/x.sh'); Path('/tmp/z').write_text(p.read_text().replace('old','new'))\"" \
  "python3 -c \"import io; p='scripts/x.sh'; print(io.open(p).read())\"" \
  "node -e 'require(\"fs\").writeFileSync(\`/tmp/y\`, require(\"fs\").readFileSync(\"scripts/x.sh\"))'" \
  "python3 -c \"from shutil import copy as w; import io; print(io.w('/tmp/z', 'scripts/x.sh'))\"" \
  "python3 -c \"from io import open as remove; print(remove('scripts/x.sh').read())\"" \
  "node -e \"const {readFileSync: unlink}=require('fs'); console.log(unlink('scripts/x.sh','utf8'))\"" \
  $'python3 -c "from io import open as remove\n# Read.\nremove(\'scripts/x.sh\').read()"' \
  $'node -e "const {readFileSync: unlink}=require(\'fs\') // read.\nunlink(\'scripts/x.sh\',\'utf8\')"' \
  $'python3 -c "from io import open as remove; x = 1.\nremove(\'scripts/x.sh\').read()"' \
  $'python3 -c "from io import open as remove; x = 1# Read.\nremove(\'scripts/x.sh\').read()"'; do
  sel "a Builder's read beside a writer name and a tracked path blocks: $W" && check "a Builder's read beside a writer name and a tracked path blocks: $W" 2 "$(bld "$W")"
done

if [ -z "${BASH_GUARDRAILS_TEST_CASE+x}" ]; then
  sel "a case filter counts only the case it names" && check "a case filter counts only the case it names" "1 passed, 0 failed" \
    "$(BASH_GUARDRAILS_TEST_CASE='bare-pid kill passes' bash "$0" | tail -1)"
  sel "a case filter that matches no case fails, and says so" && check "a case filter that matches no case fails, and says so" "1 1" \
    "$(BASH_GUARDRAILS_TEST_CASE='no such case' bash "$0" >"$READ_TMP/none"; echo "$? $(grep -c 'no case matched' "$READ_TMP/none")")"
fi

echo
[ $((PASS + FAIL)) -gt 0 ] || { echo "no case matched ${BASH_GUARDRAILS_TEST_CASE-}"; exit 1; }
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

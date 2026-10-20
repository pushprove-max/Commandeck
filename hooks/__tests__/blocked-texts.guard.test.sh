#!/usr/bin/env bash
# Issue 230: a guard that says only "BLOCKED: no" leaves the agent to guess the way round it, and a guessed way
# round is often the next block. What this pins: every BLOCKED: text in hooks/*.sh names a command to run instead,
# in backticks or as a script, CLI or variable that holds one. A refused write that names the file being written
# is fixed by writing different text, so it needs no command.
set -u
HOOKS=$(cd "$(dirname "$0")/.." && pwd)
PASS=0 FAIL=0
# One record per text: file:line, a tab, then the text up to its exit, closing brace or here-document end.
# A file whose BLOCKED: line is a printf of its argument (a block() helper) has its block "..." calls as texts.
texts() {
  awk '
    function flush() { if (t != "") { gsub(/\n/, " ", t); printf "%s:%d\t%s\n", FILENAME, n, t }; t = "" }
    FNR == 1 { flush(); helper = 0 }
    /printf .BLOCKED: %s/ { helper = 1; next }
    helper && /(^|[^a-z_])block "/ { t = $0; n = FNR; flush(); next }
    t != "" { t = t "\n" $0; if (++k >= 10 || /exit [0-9]|return [0-9]|^ *} *$|^ *[A-Z_]+ *$|^ *$/) flush(); next }
    /BLOCKED: / && !/print "BLOCKED:"/ { t = $0; n = FNR; k = 0; if (/exit [0-9]|return [0-9]/) flush() }
    END { flush() }' "$HOOKS"/*.sh
}
CMD='`[^`]+`|(bash |scripts/|%s/)[A-Za-z0-9_./-]*\.sh|[a-z-]+\.sh (<|[a-z-]+ <|--|launch|collect)|orca-ide [a-z]|git [a-z]|kill -|brew [a-z]|claude plugin [a-z]|/commandeck:|RERUN=1|npm (install|--prefix) |run_in_background|the same call|\$(LAUNCH|SINGLE_SHOT_FIX|WAY_OUT|TOLD|SCRIPTED)([^A-Z_]|$)'
WRITE='\$\{?(FILE_PATH|_pair_path|REL|_erel)([^A-Za-z_]|$)'
ALL=$(texts)
N=$(grep -c . <<<"$ALL")
BARE=$(while IFS=$'\t' read -r AT T; do grep -qE "$WRITE|$CMD" <<<"$T" || printf '%s\t%s\n' "${AT#"$HOOKS"/}" "$T"; done <<<"$ALL" | cut -c1-200)
if [ "$N" -ge 50 ]; then PASS=$((PASS+1)); echo "ok   the BLOCKED texts are read ($N)"; else FAIL=$((FAIL+1)); echo "FAIL only $N BLOCKED texts read"; fi
if [ -z "$BARE" ]; then PASS=$((PASS+1)); echo "ok   every BLOCKED text names a command to run instead"
else FAIL=$((FAIL+1)); echo "FAIL these BLOCKED texts name no command to run instead:"; sed 's/^/  /' <<<"$BARE"; fi
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

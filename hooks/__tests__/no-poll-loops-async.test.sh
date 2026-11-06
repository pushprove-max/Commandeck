#!/usr/bin/env bash
# covers: hooks/no-poll-loops.sh
# Issues 670, 671: in a worker pane a sleep loop is not refused but capped, run as `timeout L bash -c <the call>`
# (#407). The cap ends only the foreground call. A loop started without waiting (coproc, setsid, a lone &, a process
# substitution) outlives it and polls on with nothing to stop it, and a spelling the hook cannot read (a backtick, a
# backslash, eval) can rebuild such a start, so that call is refused, never capped. Keywords are read with quotes
# removed (`set''sid` is setsid). Its own file: no-poll-loops.test.sh is at the 500-line cap.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/no-poll-loops.sh"
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
# A worker pane: the hook runs in a linked worktree.
R=$(mktemp -d); trap 'rm -rf -- "$R"' EXIT
git -C "$R" init -q && git -C "$R" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init && git -C "$R" worktree add -q "$R/wt" 2>/dev/null
# wt <command> -- the hook's exit code on a foreground Bash call in the worker pane.
wt() {
  jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c,run_in_background:false}}' | (cd "$R/wt" \
    && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u CLAUDE_CODE_PROMPT_CACHE_TTL "$HOOK" >/dev/null 2>&1); echo "rc=$?"
}

check "loop_after_coproc_is_refused (#670): a sleep loop after coproc, plain or named, is seen as a loop and refused" \
  "rc=2 rc=2" "$(wt 'coproc while true; do sleep 60; done') $(wt 'coproc P { while true; do sleep 1; done; }')"
check "backtick_backslash_newline_rebuild_is_refused (#671): a backtick and a doubled backslash that rebuild a process substitution" \
  rc=2 "$(wt $'true `true <\\\\`\n(until false; do sleep 1; done >/dev/null)`')"
GOT=
for c in "set''sid --fork sleep 600 >/dev/null 2>&1 & until true; do sleep 1; done" \
  "until true; do sleep 1; done; e''val 'until false; do sleep 1; done'" \
  'until false; do sleep 1; done & until test -f x; do sleep 1; done' \
  'cat <(until false; do sleep 1; done) >/dev/null; until test -f x; do sleep 1; done'; do
  GOT+="$(wt "$c") "
done
check "empty_quotes_inside_keyword_are_refused (#671): set''sid, e''val, a lone & and a process substitution beside a sleep loop" \
  "rc=2 rc=2 rc=2 rc=2 " "$GOT"
# The cap itself still applies to a plain foreground loop, with redirections and && around it.
check "a plain worker sleep loop, its 2>&1, &> and && included, is still capped, not refused" "rc=0 rc=0" \
  "$(wt 'until grep -q ok log 2>&1; do sleep 5; done') $(wt 'until test -f x &>/dev/null; do sleep 5; done && echo up')"
# Quoted data starts nothing: a search for `a&b`, the words `eval failed` or `x<(y` is a plain wait and keeps its cap.
# Stated limit: a lone quoted word is joined back into a word, so a search for the one word `'setsid'` is refused like
# `'setsid' sleep 600`; the hook does not read command position, and a refusal only moves the wait to the background.
GOT=
for c in "until grep -q 'a&b' log; do sleep 1; done" "until grep -q 'eval failed' log; do sleep 1; done" \
  'until grep -q "x<(y" log; do sleep 1; done'; do
  GOT+="$(wt "$c") "
done
check "quoted_data_is_not_a_background_start: a quoted &, <( or a phrase with eval in a searched string keeps the cap" \
  "rc=0 rc=0 rc=0 " "$GOT"
# Code stays code: a keyword split or wholly quoted is still the keyword, and a \$( ) inside double quotes still runs.
GOT=
for c in "e'va'l 'until false; do sleep 1; done'; until test -f x; do sleep 1; done" \
  "'setsid' sleep 600 >/dev/null; until test -f x; do sleep 1; done" \
  'echo "$(sleep 600 &)"; until test -f x; do sleep 1; done'; do
  GOT+="$(wt "$c") "
done
check "split_or_quoted_keyword_and_quoted_command_substitution_are_refused" "rc=2 rc=2 rc=2 " "$GOT"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

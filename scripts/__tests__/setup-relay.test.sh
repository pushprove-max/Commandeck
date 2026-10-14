#!/usr/bin/env bash
# timeout: 300 -- five full setups
# setup-relay.test.sh -- after a finished setup the first session still stopped
# twice and the owner was not told what had changed: the board asked for an
# Orca run nobody had made, files in the project were changed without a word,
# and a relay chosen at set-up had no worktree and no pane, so a session in the
# main checkout was taken for it and acted as the orchestrator.
# What this pins: setup makes the project's run once, or prints the one command;
# it lists exactly the project files it created or changed, and says which to
# commit; with a relay chosen it creates the Chief-of-Staff worktree once and
# opens its pane under the stored name, and where it cannot it ends with the
# exact steps; either way it says the main checkout's session is NOT the relay.
# No worktree, pane or run is made on this machine: orca-ide is a stand-in that
# records its calls and makes a plain git worktree in the fixture's own HOME.
set -uo pipefail
. "$(dirname "$0")/install-fixture.sh"
CALLS=$T/orca-calls
cat > "$BIN/orca-ide" <<EOF
#!/usr/bin/env bash
[ ! -e "$T/orca-down" ] || exit 1
echo "\$*" >> "$CALLS"
case "\$*" in
  "worktree ps --json") echo '{"result":{"worktrees":[]}}' ;;
  "terminal list --json") echo '{"result":{"terminals":[]}}' ;;
  "orchestration run-current --json") echo "{\"result\":{\"run\":\$(cat "$T/run" 2>/dev/null || echo null)}}" ;;
  "orchestration run-create "*) [ ! -e "$T/no-run" ] || exit 1; [ ! -e "$T/run-noid" ] || { echo '{"ok":false,"error":{"message":"run unavailable"}}'; exit 0; }; echo '{"id":"run_new"}' > "$T/run"; echo '{"result":{"run":{"id":"run_new"}}}' ;;
  "worktree create "*)
    [ ! -e "$T/no-worktree" ] || exit 1
    while [ \$# -gt 0 ]; do case \$1 in --repo) repo=\${2#path:}; shift ;; --name) name=\$2; shift ;; esac; shift; done
    git -C "\$repo" worktree add -q -b "\$name" "$HOME/orca/workspaces/\${repo##*/}/\$name" main && echo '{"ok":true}' ;;
  "terminal create "*) [ ! -e "$T/no-pane" ] || exit 1; echo '{"result":{"terminal":{"handle":"term_relay"}}}' ;;
  *) echo '{"ok":true,"result":{}}' ;;
esac
EOF
calls() { grep -c -- "$1" "$CALLS" 2>/dev/null; }
# listed -- the paths in setup's own list of what it created or changed, sorted.
listed() { sed -n '/^Files setup created or changed in this project/,/^$/p' "$T/out" | awk 'NR > 1 && NF { print $2 }' | sort; }
# wrote <project folder name> <snap before> <snap after> -- the project's files whose content really differs.
wrote() { comm -13 "$2" "$3" | awk '{ print $2 }' | grep "^$1/" | sed "s|^$1/||" | sort; }
COS=$HOME/orca/workspaces/proj/Chief-of-Staff

# --- a relay chosen, Orca up, no run yet ---
snap > "$T/before"
run "$PROJ" setup.sh "${ANSWERS[@]}" >"$T/out" 2>&1; check "setup with a relay chosen succeeds" 0 $?
snap > "$T/after"
check "the list of changed files is exactly what setup wrote in the project" "$(wrote proj "$T/before" "$T/after")" "$(listed)"
check "and it is not empty on a first setup" yes "$([ -n "$(listed)" ] && echo yes || echo no)"
check "the config is marked to commit" 1 "$(grep -c '^  created  \.claude/commandeck\.json  commit it$' "$T/out")"
check "git's own exclude file is listed and marked not to commit" 1 "$(grep -c '^  changed  \.git/info/exclude  not for git' "$T/out")"
check "the run is created, once" 1 "$(calls '^orchestration run-create --objective ')"
check "and setup says which run" 1 "$(grep -c 'run_new' "$T/out")"
check "the relay's worktree is created, once" 1 "$(calls '^worktree create .*--name Chief-of-Staff ')"
check "on the project's local main" 1 "$([ "$(git -C "$COS" rev-parse HEAD 2>/dev/null)" = "$(git -C "$PROJ" rev-parse main)" ] && echo 1 || echo 0)"
check "it gets the relay's own settings" true "$(jq -c '.disableClaudeAiConnectors // false' "$COS/.claude/settings.local.json" 2>/dev/null)"
check "its pane is opened in that worktree under the stored name" 1 "$(calls "^terminal create --worktree path:$COS --title Ada ")"
check "setup says the main checkout's session is NOT the relay" 1 "$(grep -c 'NOT the relay' "$T/out")"
check "and names the pane it opened" 1 "$(grep -c 'term_relay' "$T/out")"

# --- the same setup again: nothing is made twice ---
# A first setup can stop after the worktree is made and before its settings are written: the next one
# writes them, so a relay pane never starts with the helper servers and connectors a relay must not have.
rm "$COS/.claude/settings.local.json"
snap > "$T/before"
run "$PROJ" setup.sh "${ANSWERS[@]}" >"$T/out" 2>&1; check "a second setup succeeds" 0 $?
snap > "$T/after"
check "no second run" 1 "$(calls '^orchestration run-create ')"
check "no second worktree" 1 "$(calls '^worktree create ')"
check "no second pane" 1 "$(calls '^terminal create ')"
check "the second list is again exactly what was written" "$(wrote proj "$T/before" "$T/after")" "$(listed)"
check "the settings a partial setup left out are written" true "$(jq -c '.disableClaudeAiConnectors // false' "$COS/.claude/settings.local.json" 2>/dev/null)"
check "the relay's worktree is named as already there" 1 "$(grep -c "$COS (already there; nothing was created)" "$T/out")"
check "and the one step left, its pane, is printed and not taken" 1 "$(grep -c "^  orca-ide terminal create --worktree path:$COS --title Ada " "$T/out")"

# --- no relay chosen: no worktree and no pane ---
project "$T/proj2"; : > "$CALLS"; rm -f "$T/run"
run "$T/proj2" setup.sh --profile claude-openai --name '' --persona '' >"$T/out" 2>&1; check "setup with no relay succeeds" 0 $?
check "no worktree is created for a relay nobody chose" 0 "$(calls '^worktree create ')"
check "and no pane" 0 "$(calls '^terminal create ')"
check "and nothing is said about a relay" 0 "$(grep -ci 'relay' "$T/out")"
check "its run is still created" 1 "$(calls '^orchestration run-create ')"

# --- a relay chosen and Orca not answering: the exact steps, and nothing made ---
project "$T/proj3"; : > "$CALLS"; rm -f "$T/run"; touch "$T/orca-down"
run "$T/proj3" setup.sh "${ANSWERS[@]}" >"$T/out" 2>&1; check "setup still finishes when Orca does not answer" 0 $?
rm "$T/orca-down"
C3=$HOME/orca/workspaces/proj3/Chief-of-Staff
check "no worktree was made" no "$([ -e "$C3" ] && echo yes || echo no)"
check "the run's one command is printed" 1 "$(grep -c "orca-ide orchestration run-create --objective " "$T/out")"
check "the worktree step is printed" 1 "$(grep -c "orca-ide worktree create --repo path:$T/proj3 --name Chief-of-Staff " "$T/out")"
check "the settings step is printed" 1 "$(grep -c "worktree-setup.sh $C3\$" "$T/out")"
check "the pane step is printed, with the stored name" 1 "$(grep -c "orca-ide terminal create --worktree path:$C3 --title Ada " "$T/out")"
check "and it says plainly that the main checkout's session is NOT the relay" 1 "$(grep -c 'NOT the relay' "$T/out")"

# --- a run bound to this terminal and recorded nowhere: setup records it, so no second run is made ---
project "$T/proj5"; : > "$CALLS"; echo '{"id":"run_bound"}' > "$T/run"
run "$T/proj5" setup.sh --profile claude-openai --name '' --persona '' >"$T/out" 2>&1
check "the bound run is adopted, not a new one made" "0 1" "$(calls '^orchestration run-create ') $(grep -c 'run_bound (already there' "$T/out")"
check "and it is recorded where the board reads it" 1 "$(grep -rlx run_bound "$HOME/.commandeck/scratch" 2>/dev/null | wc -l | tr -d ' ')"
rm -f "$T/run"

# --- Orca answers the run-create without a run: no run is claimed, and the command is printed ---
project "$T/proj6"; : > "$CALLS"; touch "$T/run-noid"
run "$T/proj6" setup.sh --profile claude-openai --name '' --persona '' >"$T/out" 2>&1
rm "$T/run-noid"
check "an answer with no run id is no run" "0 1" "$(grep -c 'Orca run: created' "$T/out") $(grep -c 'orca-ide orchestration run-create --objective proj6' "$T/out")"

# --- a Chief-of-Staff folder that is not this project's worktree is not adopted as its relay ---
project "$T/proj7"; : > "$CALLS"; C7=$HOME/orca/workspaces/proj7/Chief-of-Staff
mkdir -p "$C7" && git -C "$C7" init -q
run "$T/proj7" setup.sh "${ANSWERS[@]}" >"$T/out" 2>&1; check "setup finishes beside another checkout's folder" 0 $?
check "it says the folder is not this project's" 1 "$(grep -c "$C7 is not a worktree of this project" "$T/out")"
check "and writes nothing into it and opens no pane there" "no 0" "$([ -e "$C7/.claude/settings.local.json" ] && echo yes || echo no) $(calls '^terminal create ')"

# --- the worktree is made and the pane is refused: only the pane step is left ---
project "$T/proj4"; : > "$CALLS"; touch "$T/no-pane"
run "$T/proj4" setup.sh "${ANSWERS[@]}" >"$T/out" 2>&1; check "setup finishes when the pane does not open" 0 $?
check "the worktree step is not printed again" 0 "$(grep -c "orca-ide worktree create " "$T/out")"
check "the pane step is" 1 "$(grep -c "orca-ide terminal create --worktree path:$HOME/orca/workspaces/proj4/Chief-of-Staff --title Ada " "$T/out")"
check "and no pane is claimed" 0 "$(grep -c 'term_relay' "$T/out")"

done_tests

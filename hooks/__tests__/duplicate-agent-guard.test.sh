#!/usr/bin/env bash
# Self-test for duplicate-agent-guard.sh. The two duplicates the
# scripted guard could not see on 2026-09-23 were typed by hand: a second
# implementer pane opened 44 s after the first (tooling-3e-static), and a
# round-2 job sent into a pane still busy with round 1 (guest-seamless-sol6).
set -uo pipefail
HOOK=$(cd "$(dirname "$0")/.." && pwd)/duplicate-agent-guard.sh
BOX=$(mktemp -d); trap 'rm -rf "$BOX"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi; }

mkdir -p "$BOX/bin"
cat > "$BOX/bin/orca-ide" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$BOX/calls"
case "\$1 \$2" in
  "terminal list") cat "$BOX/list.json" ;;
  "worktree ps") cat "$BOX/ps.json" ;;
esac
EOF
chmod +x "$BOX/bin/orca-ide"
export PATH="$BOX/bin:$PATH" COMMANDECK_SCRATCH="$BOX/scratch"
# The duplicate cases run from a linked worktree: in the main checkout every
# hand-made agent pane is refused before the live-agent check.
git init -q "$BOX/main" && git -C "$BOX/main" -c user.name=t -c user.email=t@t -c core.hooksPath=/dev/null commit -q --allow-empty -m init \
  && git -C "$BOX/main" worktree add -q "$BOX/wt" >/dev/null 2>&1 || { echo "FAIL fixture: no linked worktree"; exit 1; }
DIR=$BOX/wt
run() { : > "$BOX/calls"; jq -cn --arg c "$1" --arg d "$DIR" '{tool_input:{command:$c},cwd:$d}' | CLAUDE_PROJECT_DIR="$DIR" "$HOOK" 2>"$BOX/err"; echo $?; }
run_main() { local DIR=$BOX/main; run "$1"; }
pane() { # agentIdentity state
  jq -nc --argjson a "$1" '{ok:true,result:{terminals:[{handle:"term_w",tabId:"t1",leafId:"l1",title:"Implementer — unit-x",connected:true,orphaned:false,agentIdentity:$a}]}}' > "$BOX/list.json"
  jq -nc --arg s "$2" '{ok:true,result:{worktrees:[{agents:[{paneKey:"t1:l1",state:$s}]}]}}' > "$BOX/ps.json"
}
LAUNCH='orca-ide terminal create --worktree "path:/ws/unit-x" --title "Implementer — unit-x" --command "codex --profile sol" --json'

pane '"codex"' working
check "a hand launch beside a live agent is blocked"   2 "$(run "$LAUNCH")"
check "the block names the live pane"                   1 "$(grep -c 'term_w (codex, Implementer — unit-x)' "$BOX/err")"
check "and the scripted path"                           1 "$(grep -c 'seat.sh launch' "$BOX/err")"
check "a hand-launched claude is an agent too     " 2 "$(run "orca-ide terminal create --worktree path:/ws/unit-x --command 'claude --print' --json")"
# Orca's own options may come before the subcommand; it is the same launch.
check "a launch after a global option is still a launch" 2 "$(run "orca-ide --json terminal create --worktree path:/ws/unit-x --command 'claude --print'")"
check "and after a global option with a value"           2 "$(run "orca-ide --profile work terminal create --worktree path:/ws/unit-x --command codex")"
check "a plain pane after a global option is no agent"   0 "$(run 'orca-ide --json terminal create --worktree path:/ws/unit-x --command "tail -f ship.log"')"
check "a plain shell pane is not an agent"              0 "$(run 'orca-ide terminal create --worktree path:/ws/unit-x --command "tail -f ship.log"')"
pane null done
check "a hand launch with no live agent is allowed"     0 "$(run "$LAUNCH")"
echo 'not json' > "$BOX/list.json"
check "an unreadable pane list blocks the launch"       2 "$(run "$LAUNCH")"

pane '"claude"' working
check "a hand new-job send into a busy pane is blocked" 2 "$(run 'orca-ide terminal send --terminal term_w --text "Read the round-2 brief" --enter')"
check "the block names the busy pane"                   1 "$(grep -c 'term_w' "$BOX/err")"
check "a hand inject into a busy pane is blocked"       2 "$(run 'orca-ide orchestration dispatch --task task_1 --to terminal:term_w --inject --json')"
check "a hand worker-start into a busy pane is blocked" 2 "$(run 'orca-ide orchestration worker-start --task task_1 --terminal term_w --worktree path:/ws/unit-x --json')"
check "a worker-start agent beside a live one is blocked" 2 "$(run 'orca-ide orchestration worker-start --spec hi --agent claude --worktree path:/ws/unit-x')"
check "a worker-start agent in a new worktree is allowed" 0 "$(run 'orca-ide orchestration worker-start --spec hi --agent claude --worktree new-top-level --name y')"
check "a keystroke with no Enter is not a job"          0 "$(run "orca-ide terminal send --terminal term_w --text \$'\\x15'")"
check "a same-job 'go' nudge to a busy pane is allowed" 0 "$(run 'orca-ide terminal send --terminal term_w --text go --enter')"
check "so is a slash command"                           0 "$(run 'orca-ide terminal send --terminal term_w --text "/effort high" --enter')"
check "and 'continue: ...' with a colon"        0 "$(run 'orca-ide terminal send --terminal term_w --text "continue: ruling 4 is in" --enter')"
# Orca kept `working` for a Builder whose turn had ended on a question,
# so main's answer was refused twice. The pane's own session log decides, when
# Orca's list ties the pane to a worktree it has to itself.
log_rows() { # rows... -- the session log of $BOX/wt under a HOME of the test's own
  local proj; proj=$BOX/home/.claude/projects/$(printf '%s' "$BOX/wt" | tr -c 'A-Za-z0-9' '-'); mkdir -p "$proj"
  local ts; ts=$(jq -nr 'now | strftime("%Y-%m-%dT%H:%M:%S.000Z")')
  printf '%s\n' "$@" | jq -c --arg ts "$ts" '. + {timestamp:$ts}' > "$proj/pane.jsonl"
}
pane_in_wt() { # agents-json
  pane '"claude"' working
  jq -nc --arg p "$BOX/wt" --argjson a "$1" '{ok:true,result:{worktrees:[{path:$p,agents:$a}]}}' > "$BOX/ps.json"
}
ASKED='{"type":"user","message":{"role":"user","content":"build it"}}'
SAID='{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"A question for main."}]}}'
ENDED='{"type":"system","subtype":"turn_duration"}'
JOB='orca-ide terminal send --terminal term_w --text "Ruling 4: drop the last item" --enter'
pane_in_wt '[{"paneKey":"t1:l1","state":"working","agentType":"claude"}]'
log_rows "$ASKED" "$SAID" "$ENDED"
check "a pane Orca calls working, whose log ends in a finished turn, takes main's answer" 0 "$(HOME=$BOX/home run "$JOB")"
# A Builder's Codex reviewer runs in the Builder's worktree and its log is the
# newer one once it ends: a pane reads only logs of its own kind, or the busy
# Builder reads as done and takes a second job.
codex_log() { # name prompt [finished]
  mkdir -p "$BOX/home/.codex/sessions/2026/10/12"
  local ts; ts=$(jq -nr 'now | strftime("%Y-%m-%dT%H:%M:%S.000Z")')
  { jq -nc --arg ts "$ts" --arg cwd "$BOX/wt" --arg id "$1" '{type:"session_meta",timestamp:$ts,payload:{id:$id,cwd:$cwd}}'
    jq -nc --arg ts "$ts" --arg p "$2" '{type:"response_item",timestamp:$ts,payload:{type:"message",role:"user",content:[{type:"input_text",text:$p}]}}'
    [ -z "${3:-}" ] || jq -nc --arg ts "$ts" '{type:"event_msg",timestamp:$ts,payload:{type:"task_complete",last_agent_message:"VERDICT: GO"}}'
  } > "$BOX/home/.codex/sessions/2026/10/12/rollout-2026-10-12T00-00-00-$1.jsonl"
}
log_rows "$ASKED"; touch -d '1 minute ago' "$BOX/home/.claude/projects/"*/pane.jsonl
codex_log reviewer "Review this diff. Reviewer 1 of 3, round 1." done
check "a busy Claude pane beside a newer finished Codex reviewer log still refuses a new job" 2 "$(HOME=$BOX/home run "$JOB")"
# A Codex pane reads Codex sessions, but a review pass's session is never a pane's.
pane_in_wt '[{"paneKey":"t1:l1","state":"working","agentType":"codex"}]'
codex_log pane "build it"; touch -d '1 minute ago' "$BOX/home/.codex/sessions/2026/10/12/"*-pane.jsonl
check "a busy Codex pane beside a newer finished review pass of its own worktree still refuses" 2 "$(HOME=$BOX/home run "$JOB")"
codex_log pane "build it" done; touch -d '1 minute ago' "$BOX/home/.codex/sessions/2026/10/12/"*-pane.jsonl
check "and a Codex pane whose own session has ended takes the job" 0 "$(HOME=$BOX/home run "$JOB")"
pane_in_wt '[{"paneKey":"t1:l1","state":"working"}]'
check "a pane whose kind Orca does not give keeps Orca's state" 2 "$(HOME=$BOX/home run "$JOB")"
rm -rf "$BOX/home/.codex"
pane_in_wt '[{"paneKey":"t1:l1","state":"working","agentType":"claude"}]'
log_rows "$ASKED" "$SAID" "$ENDED"
log_rows "$ASKED" "$SAID" "$ENDED" "$ASKED"
check "a pane that really is mid-turn still refuses a new job" 2 "$(HOME=$BOX/home run "$JOB")"
# A restarted pane leaves its old session's log beside the new one. The old
# log's finished turn says nothing about the session the pane is in now.
OLD_LOG=$BOX/home/.claude/projects/$(printf '%s' "$BOX/wt" | tr -c 'A-Za-z0-9' '-')/an-old-session.jsonl
printf '%s\n' "$ASKED" "$SAID" "$ENDED" | jq -c '. + {timestamp:"2026-01-01T00:00:00.000Z"}' > "$OLD_LOG"; touch -d '2026-01-01' "$OLD_LOG"
log_rows "$ASKED"
check "an old finished session beside the pane's current one does not free a busy pane" 2 "$(HOME=$BOX/home run "$JOB")"
rm -f "$OLD_LOG"
log_rows "$ASKED" "$SAID" "$ENDED"
pane_in_wt '[{"paneKey":"t1:l1","state":"working","agentType":"claude"},{"paneKey":"t2:l2","state":"working","agentType":"claude"}]'
check "two agents in the worktree: the log is not this pane's alone, Orca's state stands" 2 "$(HOME=$BOX/home run "$JOB")"
# Flags are read from the send itself, not from an earlier command in the line.
check "a busy pane named by an earlier command is not the target" 0 \
  "$(run 'orca-ide terminal show --terminal term_w --json; orca-ide terminal send --terminal term_idle --text "Read the brief" --enter')"
check "and the send's own busy target is still checked" 2 \
  "$(run 'orca-ide terminal show --terminal term_idle --json; orca-ide terminal send --terminal term_w --text "Read the brief" --enter')"
check "a separator right after --enter is still a send" 2 \
  "$(run 'orca-ide terminal send --terminal term_w --text "Review the brief" --enter; echo sent')"
check "orca-ide inside the prompt text does not end the send" 2 \
  "$(run 'orca-ide terminal send --terminal term_w --text "Review the orca-ide integration" --enter')"
check "a full subcommand quoted in the prompt does not end the send" 2 \
  "$(run 'orca-ide terminal send --terminal term_w --text "Inspect orca-ide terminal list --json, then review the brief" --enter')"
check "a flag quoted in the prompt is not the send's own flag" 2 \
  "$(run 'orca-ide terminal send --text "use --terminal term_idle" --terminal term_w --enter')"
check "a send on the line after a comment is checked" 2 \
  "$(run "$(printf 'echo ready # preparing next job\norca-ide terminal send --terminal term_w --text "Review brief" --enter')")"
check "a heredoc body is data, apostrophes included" 0 \
  "$(run "$(printf "cat <<'EOF' > notes.md\nDon't run orca-ide terminal send --terminal term_w --text x --enter by hand.\nEOF")")"
check "a send after a heredoc is checked" 2 \
  "$(run "$(printf 'cat <<EOF > notes.md\nsome notes\nEOF\norca-ide terminal send --terminal term_w --text "Job" --enter')")"
check "a send after a shell keyword is checked" 2 \
  "$(run 'if test -f brief.md; then orca-ide terminal send --terminal term_w --text "Review the brief" --enter; fi')"
check "a send behind a wrapper is checked" 2 \
  "$(run 'timeout 10 orca-ide terminal send --terminal term_w --text "Review the brief" --enter')"
check "a send inside a quoted command substitution is checked" 2 \
  "$(run 'result="$(orca-ide terminal send --terminal term_w --text Job --enter)"')"
check "a redirection glued to --enter does not hide it" 2 \
  "$(run 'orca-ide terminal send --terminal term_w --text Job --enter>/dev/null')"
check "a send on a later line is checked" 2 \
  "$(run "$(printf 'cd /tmp\norca-ide terminal send --terminal term_w --text "Job" --enter')")"
check "every send in a batch is checked, not just the first" 2 \
  "$(run 'orca-ide terminal send --terminal term_idle --text "Job A" --enter && orca-ide terminal send --terminal term_w --text "Job B" --enter')"
check "every inject in a batch is checked too" 2 \
  "$(run 'orca-ide orchestration dispatch --task t1 --to terminal:term_idle --inject; orca-ide orchestration dispatch --task t2 --to terminal:term_w --inject')"
pane '"codex"' working
check "a launch example in a heredoc is not a launch" 0 \
  "$(run "$(printf "cat <<'EOF' > notes.md\norca-ide terminal create --worktree path:/ws/unit-x --command codex\nEOF")")"
check "a here-string is not a heredoc: the launch after it is checked" 2 \
  "$(run "$(printf 'cat <<< "ready"\norca-ide terminal create --worktree path:/ws/unit-x --command codex')")"
check "a redirection glued to a heredoc delimiter ends it" 2 \
  "$(run "$(printf 'cat <<EOF>/dev/null\nready\nEOF\norca-ide terminal create --worktree path:/ws/unit-x --command codex')")"
check "a quoted executable name is still a launch" 2 \
  "$(run '"orca-ide" terminal create --worktree path:/ws/unit-x --command codex')"
check "an escaped heredoc delimiter still ends the body" 2 \
  "$(run "$(printf 'cat <<\\EOF\nready\nEOF\norca-ide terminal create --worktree path:/ws/unit-x --command codex')")"
check "every create in a batch is checked" 2 \
  "$(run 'orca-ide terminal create --worktree path:/ws/unit-x --command "tail -f x.log"; orca-ide terminal create --worktree path:/ws/unit-x --command "claude --model m"')"
pane '"claude"' working
pane '"claude"' done
check "a send into an idle pane is allowed"             0 "$(run 'orca-ide terminal send --terminal term_w --text "Read the brief" --enter')"

pane '"claude"' working
check "a script launcher is not a hand launch"          0 "$(run 'bash scripts/seat.sh launch certifier unit-x spec.md')"
check "and the hook asks Orca nothing for it"           0 "$(wc -l < "$BOX/calls")"
check "a quoted mention is data, not a launch"          0 "$(run 'rg -n "orca-ide terminal create --command codex" .claude/scripts')"

# Owner ruling 2026-10-11: main opens an agent pane only
# through builder-launch.sh or seat.sh, live agent or not.
pane null done
for agent in claude codex; do
  check "main: a hand-made $agent pane is blocked" 2 "$(run_main "orca-ide terminal create --worktree path:/ws/unit-x --command '$agent --model m' --json")"
done
check "the refusal names builder-launch.sh"           1 "$(grep -c 'builder-launch.sh <unit> <batch-brief>' "$BOX/err")"
check "and seat.sh launch"                            1 "$(grep -c 'seat.sh launch <role> <unit> <spec>' "$BOX/err")"
check "and it asks Orca nothing"                      0 "$(wc -l < "$BOX/calls")"
check "main: bare orca is the same binary"            2 "$(run_main 'orca terminal create --worktree path:/ws/unit-x --command codex')"
check "main: the agent inside a quoted bash -c"       2 "$(run_main "orca-ide terminal create --command \"bash -c 'claude -p hi'\"")"
check "main: the agent inside a bash -c, bare orca"   2 "$(run_main "orca terminal create --command 'bash -lc \"cd /ws && claude\"'")"
check "main: a plain shell pane is allowed"           0 "$(run_main 'orca-ide terminal create --worktree path:/ws/unit-x --command "tail -f ship.log"')"
check "main: a path that contains the word is not an agent" 0 "$(run_main 'orca-ide terminal create --command "tail -f /tmp/claude-501/x.log"')"
check "main: nor is an argument that contains it"     0 "$(run_main 'orca terminal create --command "grep -c x codex-pass.log"')"
# The pane command is read as a shell line: an agent is the command word of one
# of its commands, never an argument.
check "main: the agent before a separator"            2 "$(run_main 'orca-ide terminal create --command "codex; exec bash"')"
check "main: and inside a bash -c with one"           2 "$(run_main "orca-ide terminal create --command \"bash -c 'claude; exec bash'\"")"
check "main: the agent behind a wrapper"              2 "$(run_main 'orca-ide terminal create --command "env FOO=1 /opt/bin/claude --model m"')"
check "main: a quoted agent word is an argument"      0 "$(run_main "orca-ide terminal create --command \"echo 'claude'\"")"
check "main: a file named for an agent is an argument" 0 "$(run_main 'orca-ide terminal create --command "tail -f /tmp/claude"')"
check "main: a quoted separator is an argument too"   0 "$(run_main "orca-ide terminal create --command \"echo ';' codex\"")"
check "main: so is an empty quoted word"              0 "$(run_main "orca-ide terminal create --command \"echo '' codex\"")"
check "main: a quoted agent name still runs"          2 "$(run_main "orca-ide terminal create --command \"cd /ws && 'claude' -p hi\"")"
check "main: a pane command that cannot be parsed is refused" 2 "$(run_main "orca-ide terminal create --command \"echo 'claude\"")"
# The other typed routes to an agent pane.
for wt in new-child new-top-level path:/ws/unit-x; do
  check "main: worker-start --agent is blocked ($wt)" 2 "$(run_main "orca-ide orchestration worker-start --spec hi --agent claude --worktree $wt")"
done
check "that refusal names the launchers too"          1 "$(grep -c 'builder-launch.sh <unit> <batch-brief>.*seat.sh launch <role> <unit> <spec>' "$BOX/err")"
check "main: bare orca worker-start --agent too"      2 "$(run_main 'orca orchestration worker-start --task t1 --agent codex')"
check "main: worker-start into an existing pane is not a new pane" 0 "$(run_main 'orca-ide orchestration worker-start --task t1 --terminal term_w --json')"
check "main: a split that runs an agent is blocked"   2 "$(run_main 'orca-ide terminal split --terminal term_w --command codex')"
check "main: a plain split is allowed"                0 "$(run_main 'orca-ide terminal split --terminal term_w --command "tail -f x.log"')"
check "main: a worktree created with an agent is blocked" 2 "$(run_main 'orca-ide worktree create --name unit-y --agent codex --prompt hi')"
check "main: a plain worktree create is allowed"      0 "$(run_main 'orca-ide worktree create --name unit-y --json')"
check "a linked worktree may worker-start an agent"   0 "$(run 'orca-ide orchestration worker-start --spec hi --agent claude --worktree new-child')"
check "main: builder-launch.sh is the scripted path" 0 "$(run_main 'bash scripts/builder-launch.sh unit-x .claude/briefs/unit-x.md')"
check "main: so is seat.sh"                           0 "$(run_main 'scripts/seat.sh launch certifier unit-x spec.md')"
check "main: a dispatch is not a pane"                0 "$(run_main 'orca-ide orchestration dispatch --task t1 --to terminal:term_w')"
check "main: nor is a send"                           0 "$(run_main 'orca-ide orchestration send --type worker_done --subject done')"
check "a linked worktree is not main"                 0 "$(run "$LAUNCH")"
check "a linked worktree may use bare orca too"       0 "$(run 'orca terminal create --command "claude --model m"')"
pane '"codex"' working
check "but bare orca beside a live agent is a duplicate" 2 "$(run 'orca terminal create --worktree path:/ws/unit-x --command "claude --model m"')"

# One rule for "quoted text is data" across the Bash hooks: copies drift.
HOOKS=${HOOK%/*}
check "the hook sources the shared quoted-text stripper" 1 \
  "$(grep -lE '^\. .*/lib/strip-quoted\.sh"?$' "$HOOKS/duplicate-agent-guard.sh" 2>/dev/null | wc -l)"
check "and keeps no private copy of it" 0 \
  "$(grep -lE '^strip_quoted\(\)' "$HOOKS/duplicate-agent-guard.sh" | wc -l)"

# Orca's global options (--json, --environment <name>) may sit before the
# subcommand or between its two words. The subcommand was read as the two words
# straight after the binary, so the same launch or send passed unchecked.
pane '"codex"' working
check "main: a global option before the subcommand is still a hand-made pane" 2 "$(run_main 'orca-ide --json terminal create --command codex')"
check "main: and it is refused as one" 1 "$(grep -c 'hand-made agent pane from the main checkout' "$BOX/err")"
check "main: a global option that takes a value" 2 "$(run_main 'orca-ide --environment dev terminal create --command codex')"
check "main: an option between the two subcommand words" 2 "$(run_main 'orca-ide terminal --json create --command codex')"
check "main: a split behind a global option" 2 "$(run_main 'orca --json terminal split --terminal term_w --command codex')"
check "main: worktree create --agent behind a global option" 2 "$(run_main 'orca-ide --json worktree create --name x --agent claude')"
check "main: worker-start --agent behind a global option" 2 "$(run_main 'orca-ide --json orchestration worker-start --spec hi --agent claude')"
check "a launch beside a live agent behind a global option is blocked" 2 "$(run 'orca-ide --json terminal create --worktree path:/ws/unit-x --command codex')"
check "a send into a busy pane behind a global option is blocked" 2 "$(run 'orca-ide --json terminal send --terminal term_w --text "Read the round-2 brief" --enter')"
check "an inject into a busy pane behind a global option is blocked" 2 "$(run 'orca-ide --environment dev orchestration dispatch --task task_1 --to terminal:term_w --inject')"
check "an unparseable launch behind a global option is blocked, not skipped" 2 "$(run_main "orca-ide --json terminal create --command 'codex")"
check "main: a plain pane behind a global option is allowed" 0 "$(run_main 'orca-ide --json terminal create --command "tail -f x.log"')"
check "a same-job nudge behind a global option is allowed" 0 "$(run 'orca-ide --json terminal send --terminal term_w --text go --enter')"
check "another subcommand whose arguments name a launch is not one" 0 "$(run_main 'orca-ide status --note terminal create --command codex')"
# The same miss git-safety.sh had: a quoted subcommand word is still the subcommand.
check "main: a quoted first subcommand word" 2 "$(run_main 'orca-ide "terminal" create --command codex')"
check "main: a quoted second subcommand word" 2 "$(run_main "orca-ide terminal 'create' --command codex")"
check "main: both quoted, behind a global option" 2 "$(run_main 'orca-ide --json "terminal" "create" --command codex')"
check "main: a quoted binary name" 2 "$(run_main '"orca-ide" terminal create --command codex')"
check "a quoted send into a busy pane is blocked" 2 "$(run 'orca-ide "terminal" "send" --terminal term_w --text "Read the round-2 brief" --enter')"
check "a launch only named inside quoted prose is still not one" 0 "$(run_main 'echo "orca-ide terminal create --command codex"')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

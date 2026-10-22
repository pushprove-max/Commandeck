# Sourced by main-watch-helper-hold.test.sh, main-watch-claim.test.sh and main-watch-wake.test.sh: a scratch repo
# with main-watch.sh, a fake orca-ide that answers each pane's state from `agents` and records every send, and the
# tick helpers. Three files, not one: one file of every case ran 71 s alone, past the merge's per-file cap under load (issue 218).

SOURCE=$(git rev-parse --show-toplevel)
# Physical path: main-watch finds main's pane by comparing Orca's worktreePath with it.
T=$(cd "$(mktemp -d)" && pwd -P)
LIVE= ARGV=
trap 'kill $LIVE $ARGV 2>/dev/null || true; rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; [ ! -s "$T/sends" ] || { echo "sends were:" >&2; cat "$T/sends" >&2; }; exit 1; }

REPO=$T/repo S=$T/scratch F=$T/fake
mkdir -p "$REPO/scripts" "$T/bin" "$S" "$F" "$T/home" "$T/ws"
git -C "$REPO" init -q
cp "$SOURCE/scripts/main-watch.sh" "$SOURCE/scripts/paths.sh" "$SOURCE/scripts/project-main.sh" "$SOURCE/scripts/requirements.sh" \
   "$SOURCE/scripts/host-services.sh" "$SOURCE/scripts/orca-task-create.sh" "$SOURCE/scripts/dashboard_builders.jq" "$REPO/scripts/"
mkdir -p "$REPO/config"; cp "$SOURCE/config/routing.json" "$REPO/config/"
# --state (the latest message's marker) answers from `state-<unit>`; nothing there is no marker.
cat > "$REPO/scripts/read-verdict.sh" <<RV
#!/usr/bin/env bash
[ "\$1" = --state ] && { cat "$F/state-\${3##*/}" 2>/dev/null; exit 0; }
# A one-shot hook: the flip file runs at the next read, mid-tick, so a test can change what Orca reads after the tick began.
[ ! -e "$F/flip" ] || { bash "$F/flip"; rm -f "$F/flip"; }
cat "$F/verdict-\$1" 2>/dev/null || exit 3
RV
printf '#!/usr/bin/env bash\nexit 0\n' > "$REPO/scripts/close-done-panes.sh"
echo run_test > "$S/current-run"
export COMMANDECK_HOST_OS=Linux
: > "$F/agents"; : > "$F/tasks"; : > "$T/sends"
# No processes: the broker reaper must never see or signal this machine's own.
printf '#!/usr/bin/env bash\ncase "$*" in *lstart=*) exec /bin/ps "$@" ;; esac\nexit 0\n' > "$T/bin/ps"
cat > "$T/bin/orca-ide" <<ORCA
#!/usr/bin/env bash
# With need-from, a task-create or send that names no sender is refused, as Orca refuses one from a process with no terminal.
case "\$1 \$2" in "orchestration task-create"|"orchestration send")
  [ ! -e "$F/need-from" ] || [[ " \$* " == *" --from "* ]] || { echo "\$*" >> "$T/refused"; echo '{"ok":false,"error":{"message":"Could not determine the sender terminal"}}'; exit 1; } ;;
esac
case "\$1 \$2" in
  "orchestration task-list") jq -Rn '{result:{tasks:[inputs | split(" ") | {id:.[0], status:.[1]}]}}' < "$F/tasks" ;;
  "orchestration task-create") echo "\$*" >> "$T/creates"
    n=\$(( \$(wc -l < "$F/tasks") + 1 )); echo "task_new\$n pending" >> "$F/tasks"
    echo "{\"ok\":true,\"result\":{\"task\":{\"id\":\"task_new\$n\"}}}" ;;
  # With live-inbox, a send also lands unread in inbox.jsonl (created at COMMANDECK_NOW), which the inbox read answers.
  "orchestration send") printf '%s' "\$*" | tr '\n' ' ' >> "$T/sends"; echo >> "$T/sends"
    if [ -e "$F/live-inbox" ]; then while [ \$# -gt 0 ]; do case \$1 in --to) to=\$2 ;; --from) fr=\$2 ;; --type) ty=\$2 ;; --subject) su=\$2 ;; esac; shift; done
      jq -nc --arg to "\$to" --arg f "\${fr:-}" --arg t "\$ty" --arg s "\$su" --argjson at "\${COMMANDECK_NOW:-0}" \
        '{id: "s\(\$at)", to_handle: \$to, from_handle: \$f, type: \$t, subject: \$s, read: 0, created_at: (\$at | todate)}' >> "$F/inbox.jsonl"; fi
    echo '{"ok":true}' ;;
  # no-turn: the text is typed and submitted, but no turn starts (an unproven wake). flip-send runs once while the send waits.
  "terminal send") printf '%s\n' "\$*" >> "$T/typed"; [ ! -e "$F/flip-send" ] || { bash "$F/flip-send"; rm -f "$F/flip-send"; }
    if [ -e "$F/no-turn" ]; then echo '{"ok":true,"result":{"stages":["typed","submitted"]}}'
    else echo '{"ok":true,"result":{"stages":["typed","submitted","turn_started"]}}'; fi ;;
  # screen-<handle> and inbox-<handle> are one pane's own; screen and inbox are main's.
  "terminal read") if [ -e "$F/screen-\$4" ]; then jq -Rn '{result:{terminal:{tail:[inputs],latestCursor:"0"}}}' < "$F/screen-\$4"
    elif [ -e "$F/screen" ]; then jq -Rn '{result:{terminal:{tail:[inputs],latestCursor:"0"}}}' < "$F/screen"
    else echo '{"result":{"terminal":{"tail":[],"latestCursor":"0"}}}'; fi ;;
  # With no-identity, Orca names no pane's agent (agentIdentity null), as it lists main's panes on some hosts.
  "terminal list")
    jq -Rn --arg main "$REPO" --arg cos "$T/ws/Chief-of-Staff" --argjson id "\$([ -e "$F/no-identity" ] && echo null || echo '"claude"')" '{result:{terminals:[inputs | split(" ") | {handle:.[0], tabId:.[0], leafId:"l",
      worktreePath:(if (.[0] | startswith("term_main")) then \$main elif (.[0] | startswith("term_cos")) then \$cos else "/elsewhere" end), agentIdentity:\$id}]}}' < "$F/agents" ;;
  "orchestration inbox") [ ! -e "$F/inbox-\$4" ] || { cat "$F/inbox-\$4"; exit 0; }
    # flip-inbox runs once after the read is taken and before it is answered: what lands meanwhile is not in it.
    [ ! -e "$F/live-inbox" ] || { o=\$(jq -sc '{ok: true, result: {messages: .}}' "$F/inbox.jsonl")
      [ ! -e "$F/flip-inbox" ] || { mv "$F/flip-inbox" "$F/flip-inbox.run"; bash "$F/flip-inbox.run"; }; echo "\$o"; exit 0; }
    cat "$F/inbox" 2>/dev/null || echo '{"ok":true,"result":{"messages":[]}}' ;;
  # coord names the run's coordinator; term_main without it.
  "orchestration run-list") jq -nc --arg c "\$(cat "$F/coord" 2>/dev/null || echo term_main)" '{result:{runs:[{id:"run_test",coordinator_handle:\$c}]}}' ;;
  "worktree ps") jq -Rn '{result:{worktrees:[{agents:[inputs | split(" ") | {paneKey:(.[0] + ":l"), state:.[1]}]}]}}' < "$F/agents" ;;
  *) echo '{}' ;;
esac
ORCA
chmod +x "$T/bin/orca-ide" "$T/bin/ps"

# A service: no terminal handle of its own.
mw() { (cd "$REPO" && unset CLAUDE_CONFIG_DIR ORCA_TERMINAL_HANDLE && PATH=$T/bin:$PATH HOME=$T/home COMMANDECK_SCRATCH=$S COMMANDECK_WORKSPACES=$T/ws bash scripts/main-watch.sh "$@"); }
tick() { COMMANDECK_NOW=$1 mw --once 2>>"$T/stderr" || fail "main-watch exited non-zero at $1"; }
state() { awk -v h="$1" '$1 != h' "$F/agents" > "$F/agents.new"; mv "$F/agents.new" "$F/agents"; echo "$1 $2" >> "$F/agents"; }
posts() { grep -c -- "$1" "$T/sends" || true; }
# Issue 318's wake files (main-watch-wake*.test.sh): main-watch's typed wakes, Orca's nudge, and the live inbox.
typed() { grep -c 'items are waiting in your Orca inbox' "$T/typed" 2>/dev/null || true; }
nudge() { # <now> -- Orca nudges main; a nudge the hook passes is a turn, counted in passed
  local o; o=$(jq -n --arg c "$REPO" '{prompt: "You have 1 orchestration message. Run `orca orchestration check --run run_test`.", cwd: $c}' \
    | (cd "$REPO" && env -u CLAUDE_PROJECT_DIR -u CLAUDE_CONFIG_DIR PATH="$T/bin:$PATH" HOME="$T/home" COMMANDECK_MAIN="$REPO" COMMANDECK_SCRATCH="$S" \
      COMMANDECK_NOW="$1" COMMANDECK_MAIN_WATCH_UP=1 ORCA_TERMINAL_HANDLE=term_main bash "$SOURCE/hooks/cos-own-echo.sh" 2>/dev/null))
  grep -q '"block"' <<<"$o" || echo "$1" >> "$T/passed"; }
drained() { jq -c '.read = 1' "$F/inbox.jsonl" > "$F/i.new"; mv "$F/i.new" "$F/inbox.jsonl"; }
ask() { jq -nc --arg to "$2" --argjson at "$1" '{to_handle: $to, from_handle: "term_w", read: 0, type: "question", subject: "a worker asks", created_at: ($at | todate)}' >> "$F/inbox.jsonl"; }
bseat() { mkdir -p "$T/ws/$1/.claude"; printf 'handle=%s\ntask=%s\nrole=builder\nunit=%s\nlaunched=%s\n' "$2" "$3" "$1" "$4" > "$S/seat-$1-builder.txt"; echo "$3 running" >> "$F/tasks"; }
hrow() { # <epoch> <event> <agent> -- one helper row as the Builder's hooks log it
  jq -nc --argjson t "$1" --arg e "$2" --arg a "$3" '{ts: ($t | todate), event: $e} + if $e == "tool-start"
  then {use: "h\($t)", agent: $a, tool: "Grep", kind: "tool", call: "h"} else {agent_id: $a, type: "Explore"} end'; }
state term_main idle

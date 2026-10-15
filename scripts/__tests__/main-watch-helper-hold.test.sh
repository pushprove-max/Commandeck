#!/usr/bin/env bash
# A Builder that ends its turn to wait on a helper it started is held, not
# posted as stopped (#41). What this pins: only the Builder's own unit marker
# ends the hold, never another line ending -DONE that it quotes (#44), and a
# hold the Builder left by working again does not carry its old clock into
# the next wait, where it would expire at once (#45).
#
# The fake orca-ide answers each pane's state from `agents` and records every
# send; read-verdict.sh answers from `verdict-<handle>`. Each tick is one
# `--once` run, with COMMANDECK_NOW as the clock.
set -euo pipefail

SOURCE=$(git rev-parse --show-toplevel)
# Physical path: main-watch finds main's pane by comparing Orca's worktreePath with it.
T=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$T"' EXIT
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
case "\$1 \$2" in
  "orchestration task-list") jq -Rn '{result:{tasks:[inputs | split(" ") | {id:.[0], status:.[1]}]}}' < "$F/tasks" ;;
  "orchestration task-create")
    n=\$(( \$(wc -l < "$F/tasks") + 1 )); echo "task_new\$n pending" >> "$F/tasks"
    echo "{\"ok\":true,\"result\":{\"task\":{\"id\":\"task_new\$n\"}}}" ;;
  "orchestration send") printf '%s' "\$*" | tr '\n' ' ' >> "$T/sends"; echo >> "$T/sends"; echo '{"ok":true}' ;;
  "terminal send") printf '%s\n' "\$*" >> "$T/typed"; echo '{"ok":true,"result":{"stages":["typed","submitted","turn_started"]}}' ;;
  "terminal read") echo '{"result":{"terminal":{"tail":[],"latestCursor":"0"}}}' ;;
  "terminal list")
    jq -Rn --arg main "$REPO" '{result:{terminals:[inputs | split(" ") | {handle:.[0], tabId:.[0], leafId:"l",
      worktreePath:(if (.[0] | startswith("term_main")) then \$main else "/elsewhere" end), agentIdentity:"claude"}]}}' < "$F/agents" ;;
  "orchestration inbox") cat "$F/inbox" 2>/dev/null || echo '{"ok":true,"result":{"messages":[]}}' ;;
  "orchestration run-list") echo '{"result":{"runs":[{"id":"run_test","coordinator_handle":"term_main"}]}}' ;;
  "worktree ps") jq -Rn '{result:{worktrees:[{agents:[inputs | split(" ") | {paneKey:(.[0] + ":l"), state:.[1]}]}]}}' < "$F/agents" ;;
  *) echo '{}' ;;
esac
ORCA
chmod +x "$T/bin/orca-ide" "$T/bin/ps"

mw() { (cd "$REPO" && PATH=$T/bin:$PATH HOME=$T/home COMMANDECK_SCRATCH=$S COMMANDECK_WORKSPACES=$T/ws bash scripts/main-watch.sh "$@"); }
tick() { COMMANDECK_NOW=$1 mw --once 2>>"$T/stderr" || fail "main-watch exited non-zero at $1"; }
state() { sed -i "/^$1 /d" "$F/agents"; echo "$1 $2" >> "$F/agents"; }
posts() { grep -c -- "$1" "$T/sends" || true; }
bseat() { mkdir -p "$T/ws/$1/.claude"; printf 'handle=%s\ntask=%s\nrole=builder\nunit=%s\nlaunched=%s\n' "$2" "$3" "$1" "$4" > "$S/seat-$1-builder.txt"; echo "$3 running" >> "$F/tasks"; }
hrow() { # <epoch> <event> <agent> -- one helper row as the Builder's hooks log it
  jq -nc --argjson t "$1" --arg e "$2" --arg a "$3" '{ts: ($t | todate), event: $e} + if $e == "tool-start"
  then {use: "h\($t)", agent: $a, tool: "Grep", kind: "tool", call: "h"} else {agent_id: $a, type: "Explore"} end'; }
state term_main idle
# The watcher posts only what finished after its first tick.
tick 5000

# #45: the issue's timeline. The hold starts at 10000; the Builder works again
# at 10100; at 13700 it ends its turn on a helper it has just started. wt-h6,
# held from 10000 too, gets its helper back at 13600 and works only between two
# ticks, so no tick sees it `working`: its new helper's start is the only sign.
for u in wt-h5 wt-h6; do bseat $u term_$u task_$u 8000; state term_$u working; done; tick 9900
for u in wt-h5 wt-h6; do hrow 9990 subagent-start a1 > "$T/ws/$u/.claude/builder-events.jsonl"; state term_$u "done"; done; tick 10000
[ "$(posts 'wt-h[56]')" = 0 ] || fail "a Builder waiting on its first helper was posted"
hrow 10050 subagent-stop a1 >> "$T/ws/wt-h5/.claude/builder-events.jsonl"
state term_wt-h5 working; tick 10100
hrow 13600 subagent-stop a1 >> "$T/ws/wt-h6/.claude/builder-events.jsonl"
for u in wt-h5 wt-h6; do { hrow 13650 subagent-start a2; hrow 13680 tool-start a2; } >> "$T/ws/$u/.claude/builder-events.jsonl"; done
state term_wt-h5 "done"; tick 13700
[ "$(posts wt-h5)" = 0 ] || fail "a Builder that worked again and now waits on a new helper was posted on the old hold's clock: $(grep wt-h5 "$T/sends")"
[ "$(posts wt-h6)" = 0 ] || fail "a Builder that worked between two ticks and now waits on a new helper was posted on the old hold's clock: $(grep wt-h6 "$T/sends")"

# #44: the issue's input. wt-h1 quotes its design pane's marker and waits on a
# fresh Explore helper; wt-h3 printed its own marker with a helper out.
H=20000
for u in wt-h1 wt-h3; do bseat $u term_$u task_$u $((H - 2000)); state term_$u working; done
{ hrow $((H - 120)) subagent-start a1; hrow $((H - 30)) tool-start a1; } > "$T/ws/wt-h1/.claude/builder-events.jsonl"
printf 'Design coauthor replied:\nDESIGN-DONE\nWaiting on Explore.\n' > "$F/verdict-term_wt-h1"
hrow $((H - 120)) subagent-start a1 > "$T/ws/wt-h3/.claude/builder-events.jsonl"; echo 'WT-H3-DONE' > "$F/verdict-term_wt-h3"
tick $H; for u in wt-h1 wt-h3; do state term_$u "done"; done; tick $((H + 60))
[ "$(posts wt-h1)" = 0 ] || fail "a Builder quoting another pane's DONE marker, with a helper out, was posted: $(grep wt-h1 "$T/sends")"
grep -q 'seat builder on wt-h3 finished' "$T/sends" || fail "a Builder that printed its own unit marker with a helper out was not posted as finished"

# Mail from another pane that sits unread while main is idle wakes main: two orders once sat
# 13 minutes with main idle, because only this watcher's own posts ever typed a wake. A heads-up
# note and main's own send are not news to main.
msg() { jq -nc --arg f "$1" --arg s "$2" '{to_handle: "run:run_test", from_handle: $f, read: 0, type: "status", subject: $s}'; }
inbox() { jq -sc '{ok: true, result: {messages: .}}' > "$F/inbox"; }
typed() { grep -c 'items are waiting in your Orca inbox' "$T/typed" 2>/dev/null || true; }
# The seats above are done with and their tasks closed, so nothing of theirs is pending.
rm -f "$S"/seat-*.txt "$S/main-watch/wake"; sed -i 's/ .*/ completed/' "$F/tasks"
M=30000; : > "$T/typed"
{ msg term_main "main's own note"; msg term_x "heads-up: 2 notes"; } | inbox
tick $M; tick $((M + 200))
[ "$(typed)" = 0 ] || fail "main was woken for a heads-up note or its own send"
{ msg term_main "main's own note"; msg term_x "heads-up: 2 notes"; msg term_wt-h1 "order from a Builder"; } | inbox
tick $((M + 300)); tick $((M + 360))
[ "$(typed)" = 0 ] || fail "main was woken for mail unread under 2 minutes"
tick $((M + 420))
[ "$(typed)" = 1 ] || fail "mail unread 2 minutes with main idle did not wake main (typed $(typed))"
tick $((M + 480))
[ "$(typed)" = 1 ] || fail "an unanswered main was woken again inside 2 minutes"
rm -f "$F/inbox"

echo "PASS main-watch-helper-hold.test.sh"

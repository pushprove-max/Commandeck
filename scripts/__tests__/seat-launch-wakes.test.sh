#!/usr/bin/env bash
# seat.sh launch: the record main-watch.sh wakes main from, the file-pointer
# prompt, the proof the turn started, and the seat preflights.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }

TMP=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$TMP"' EXIT
# seat.sh takes its root from `git rev-parse`, so the stubs only get picked up
# from inside a real repo. Copying it keeps the stub tree off the checkout.
git init -q "$TMP/repo"
mkdir -p "$TMP/repo/scripts" "$TMP/repo/config" "$TMP/ws/fake-unit" "$TMP/bin" "$TMP/scratch"
cp "$REAL/scripts/seat.sh" "$REAL/scripts/paths.sh" "$REAL/scripts/project-main.sh" "$REAL/scripts/codex-helpers.sh" "$REAL/scripts/read-verdict.sh" "$REAL/scripts/seat-go.sh" "$REAL/scripts/dispatch-task.sh" "$REAL/scripts/orca-task-create.sh" "$TMP/repo/scripts/"
# The Codex cases below need a writable Codex seat: pin that shape here.
jq "$(cat "$REAL/scripts/__tests__/fixtures/routing-seats.jq")"' | .roles["companion"] = {agent: "codex", model: "gpt-6.1-sol", effort: "high", memory: "12G", sandbox: "workspace-write", edits: true}' \
  "$REAL/config/routing.json" > "$TMP/repo/config/routing.json"
for s in run-bound.sh worktree-setup.sh; do
  printf '#!/bin/sh\nexit 0\n' > "$TMP/repo/scripts/$s"; chmod +x "$TMP/repo/scripts/$s"
done

# Every call is logged; task-create keeps the prompt it was given; dispatch and
# the prompt receipt answer from the environment so a case can refuse inject or
# withhold turn_started.
cat > "$TMP/bin/orca-ide" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
arg() { local k=$1; shift; while [ $# -gt 0 ]; do [ "$1" != "$k" ] || { printf '%s' "${2:-}"; return; }; shift; done; }
case "${1:-} ${2:-}" in
  "terminal create") echo '{"handle":"term_stub"}' ;;
  "terminal list") echo '{"ok":true,"result":{"terminals":[{"handle":"term_stub","worktreeId":"wt","connected":'"${LIVE_PANE:-false}"'}]}}' ;;
  "worktree ps") echo '{"ok":true,"result":{"worktrees":[]}}' ;;
  "orchestration task-create") arg --spec "$@" > "$SENT"; echo '{"id":"task_stub"}' ;;
  "orchestration worker-start")
    # DISPATCH_NOAGENT=n: the first n dispatches meet a pane Orca has not yet
    # detected as an agent, as a fresh Codex pane does.
    n=$(grep -c '^orchestration worker-start' "$CALLS")
    if [ "$n" -le "${DISPATCH_NOAGENT:-0}" ]; then echo '{"ok":false,"error":{"message":"no recognized agent detected in terminal"}}'
    elif [ "${DISPATCH_OK:-1}" = 1 ]; then echo '{"ok":true}'; else echo '{"ok":false}'; fi ;;
  "terminal send")
    if [[ " $* " == *" --enter "* ]]; then
      printf '{"ok":true,"result":{"send":{"accepted":true,"prompt":{"requestId":"req_1","stages":%s}}}}\n' "${STAGES:-[\"input_accepted\",\"turn_started\"]}"
    else echo '{"ok":true}'; fi ;;
  "terminal read") printf '{"result":{"terminal":{"tail":%s}}}\n' "${SCREEN:-[]}" ;;
  *) echo '{"ok":true}' ;;
esac
STUB
chmod +x "$TMP/bin/orca-ide"

echo 'Apply every confirmed finding and write the revised brief.' > "$TMP/spec.md"
export PATH=$TMP/bin:$PATH
export COMMANDECK_WORKSPACES=$TMP/ws COMMANDECK_SCRATCH=$TMP/scratch
# 0 skips seat.sh's settle sleep; this test is about the launch, not the pane.
export COMMANDECK_SEAT_SETTLE_SECONDS=0 CALLS=$TMP/calls.txt SENT=$TMP/sent.txt HOME=$TMP/home

# A hand-launched seat is woken for by main-watch.sh, which reads the seat
# record: without handle, task, unit and launched in it the finish is silent.
( cd "$TMP/repo" && timeout 30 bash scripts/seat.sh launch companion fake-unit "$TMP/spec.md" ) >/dev/null 2>&1
check "a hand-launched seat leaves the record main-watch reads" 4 \
  "$(grep -cE '^(handle=term_stub|task=task_stub|unit=fake-unit|launched=[0-9]+)$' "$TMP/scratch/seat-fake-unit-companion.txt" 2>/dev/null)"
check "a local launch's record names no origin run" 0 "$(grep -c '^origin=' "$TMP/scratch/seat-fake-unit-companion.txt" || true)"
# A seat the origin placed here is the origin's to hear: its record says so, and
# main-watch on this host skips it. The mark rides in the record itself, so a
# later local launch, which rewrites the record, is never silenced by it.
echo 'Peer-placed spec.' > "$TMP/spec-peer.md"; mkdir -p "$TMP/ws/peer-unit"
( cd "$TMP/repo" && COMMANDECK_ORIGIN_RUN=run_origin timeout 30 bash scripts/seat.sh launch companion peer-unit "$TMP/spec-peer.md" ) >/dev/null 2>&1
check "a peer-placed seat's record names its origin run" 1 "$(grep -cx 'origin=run_origin' "$TMP/scratch/seat-peer-unit-companion.txt" 2>/dev/null || true)"
# Serena's server tells every client to call initial_instructions first; 30 of
# 31 Codex sessions did, and its 23 KB manual rode along on every later call
#. A Codex seat's prompt says to skip it, and names no file to read instead:
# the plugin ships none, and nothing under .claude/briefs is tracked.
check "a Codex seat's prompt says to skip the Serena manual" 0 \
  "$(grep -q 'Do not call serena initial_instructions' "$SENT" && echo 0 || echo 1)"
check "and points at no file under the briefs folder" 0 "$(grep -c '\.claude/briefs/_' "$SENT")"

# LAUNCH FROM A FILE POINTER, AND PROVE THE TURN STARTED. An 8,332-character
# spec pasted but never submitted (u1219), and a >9 KB spec that killed the
# launch outright, both came from typing the spec. The spec now stays on disk:
# the prompt names it. Launch then needs a started turn -- the session log, or
# the send receipt's turn_started -- and never types the prompt twice.
run_launch() { # spec-file
  : > "$CALLS"; : > "$SENT"
  ( cd "$TMP/repo" && COMMANDECK_DRIVER=1 timeout 30 bash scripts/seat.sh launch companion fake-unit "$1" ) > "$TMP/launch.out" 2>&1
  echo $?
}
enter_sends() { grep -c -- '^terminal send .*--enter' "$CALLS" || true; }
{ head -c 8332 /dev/zero | tr '\0' 'x'; echo; } > "$TMP/spec-8332.md"
{ head -c 9800 /dev/zero | tr '\0' 'y'; echo; } > "$TMP/spec-9800.md"
for spec in "$TMP/spec-8332.md" "$TMP/spec-9800.md"; do
  n=$(basename "$spec" .md)
  check "$n launches" 0 "$(run_launch "$spec")"
  check "$n: the prompt is a short pointer" 1 "$( [ "$(wc -c < "$SENT")" -lt 600 ] && echo 1 || echo 0 )"
  check "$n: the pointer names the absolute spec file" 1 "$(grep -cF "$spec" "$SENT")"
  check "$n: the no-heartbeat line survives" 1 "$(grep -c 'Send no heartbeats' "$SENT")"
  check "$n: the spec body is never typed" 0 "$(grep -c 'xxxxxxxxxx\|yyyyyyyyyy' "$CALLS" || true)"
done
check "no log and no receipt ends in a visible unproven diagnostic" 1 "$(grep -c 'UNPROVEN SUBMISSION' "$TMP/launch.out")"
check "and types nothing after inject" 0 "$(enter_sends)"

# Already started: the session log shows the new turn, so nothing more is sent.
CX=$HOME/.codex/sessions/rollout-started.jsonl; mkdir -p "$(dirname "$CX")"
FUT=$(( $(date +%s) + 60 )); STAMP=$(date -u -d "@$FUT" +%Y-%m-%dT%H:%M:%S.000Z)
printf '{"timestamp":"%s","type":"session_meta","payload":{"type":"session_meta","cwd":"%s"}}\n{"timestamp":"%s","type":"event_msg","payload":{"type":"task_started","turn_id":"t1"}}\n' \
  "$STAMP" "$TMP/ws/fake-unit" "$STAMP" > "$CX"
touch -d "@$FUT" "$CX"
check "an already-started launch succeeds" 0 "$(run_launch "$TMP/spec-8332.md")"
check "an already-started launch sends no second prompt" 0 "$(enter_sends)"
check "an already-started launch is not unproven" 0 "$(grep -c 'UNPROVEN' "$TMP/launch.out" || true)"

# Booted but unsubmitted: the session exists with no turn and the composer
# shows the pointer. Clear that input only, send the pointer once, observe.
printf '{"timestamp":"%s","type":"session_meta","payload":{"type":"session_meta","cwd":"%s"}}\n' "$STAMP" "$TMP/ws/fake-unit" > "$CX"
touch -d "@$FUT" "$CX"
export SCREEN; SCREEN=$(jq -nc --arg p "> Your task spec is the file $TMP/spec-8332.md" '[$p]')
check "an unsubmitted composer is recovered" 0 "$(run_launch "$TMP/spec-8332.md")"
unset SCREEN
check "the recovery sends the pointer exactly once" 1 "$(enter_sends)"
check "the recovery clears the pending input first" 1 "$(grep -- '^terminal send' "$CALLS" | grep -vc -- '--enter')"
check "a recovered launch is proven" 0 "$(grep -c 'UNPROVEN' "$TMP/launch.out" || true)"
rm -f "$CX"

# Inject refused: the direct send waits for submission. Without turn_started it
# replays the SAME request id once (a receipt, never a resend), then says so.
check "a refused inject with a started turn launches" 0 "$(DISPATCH_OK=0 run_launch "$TMP/spec-8332.md")"
check "the direct send observes submission" 1 "$(grep -c -- '--enter --wait-submit' "$CALLS")"
check "a proven direct send is not unproven" 0 "$(grep -c 'UNPROVEN' "$TMP/launch.out" || true)"
check "an unsubmitted direct send still ends the launch" 0 "$(DISPATCH_OK=0 STAGES='["input_accepted"]' run_launch "$TMP/spec-8332.md")"
check "the prompt is typed once" 1 "$(grep -- '^terminal send .*--enter' "$CALLS" | grep -vc -- '--retry-request')"
check "its confirmation replays the request id" 1 "$(grep -c -- '--retry-request req_1' "$CALLS")"
check "an unproven direct send is visible" 1 "$(grep -c 'UNPROVEN SUBMISSION' "$TMP/launch.out")"
check "any other refusal is not retried" 1 "$(grep -c '^orchestration worker-start' "$CALLS")"

# Agent detection lags launch: a Codex pane from pane-box.sh is not yet an agent
# to Orca, which refuses inject; seconds later it shows codex:working.
# Typing the pointer then leaves the task undispatched with no worker_done, so
# launch waits out that refusal and dispatches.
check "a pane not yet detected as an agent launches" 0 "$(DISPATCH_NOAGENT=1 run_launch "$TMP/spec-8332.md")"
check "the task is dispatched once Orca sees the agent" 2 "$(grep -c '^orchestration worker-start' "$CALLS")"
check "and nothing falls back to NO-WAKE" 0 "$(grep -c 'NO-WAKE' "$TMP/launch.out" || true)"
check "and nothing is typed" 0 "$(enter_sends)"

# A Claude pane in a worktree takes the MAIN repo's ~/.claude.json project
# entry. serena or codebase-memory disabled there ran a whole cut with no symbol
# tools (2026-09-18), so a Claude seat refuses to launch; a Codex seat does not
# read that file.
role_launch() { # role
  : > "$CALLS"
  ( cd "$TMP/repo" && COMMANDECK_DRIVER=1 timeout 30 bash scripts/seat.sh launch "$1" fake-unit "$TMP/spec.md" ) > "$TMP/launch.out" 2>&1
  echo $?
}
mcp_off() { jq -n --arg p "$TMP/repo" --argjson off "$1" '{projects:{($p):{disabledMcpServers:$off}}}' > "$HOME/.claude.json"; }
mkdir -p "$HOME"
mcp_off '["claude.ai Gmail"]'
check "a Claude seat launches when serena and codebase-memory are on" 0 "$(role_launch investigator)"
for srv in serena codebase-memory; do
  mcp_off "[\"$srv\"]"
  check "a Claude seat refuses with $srv disabled for the main repo" 2 "$(role_launch investigator)"
  check "the $srv refusal opens no pane" 0 "$(grep -c '^terminal create' "$CALLS" || true)"
  check "the $srv refusal names the server and the fix" 1 "$(grep -c "$srv.*disabledMcpServers" "$TMP/launch.out")"
done
check "a Codex seat is not held by the Claude MCP list" 0 "$(role_launch companion)"
rm -f "$HOME/.claude.json"

# A CLAUDE SEAT GETS A TYPED `go` AFTER ITS SPEC PROMPT. The prompt
# arrives as pasted text, and on 2026-09-21 a seat refused to act on paste
# alone. A short send arrives typed. It must come AFTER the prompt, or it joins
# the composer instead of answering the paste. Codex never refused: no `go`.
CL=$HOME/.claude/projects/$(printf '%s' "$TMP/ws/fake-unit" | tr -c 'A-Za-z0-9' '-')/s1.jsonl; mkdir -p "$(dirname "$CL")"
printf '{"timestamp":"%s","type":"user","message":{"role":"user","content":"Your task spec is the file x"}}\n' "$STAMP" > "$CL"
go_after() { # the first line naming $1, then the typed go, and nothing after
  grep -E "^$1|^terminal send .*--text go --enter" "$CALLS" | sed -E 's/^(orchestration worker-start|terminal send --terminal term_stub --text (go|Your task spec)).*/\1/' | tr '\n' '|'
}
role_launch investigator >/dev/null
check "a Claude seat's injected prompt is followed by one typed go" "orchestration worker-start|terminal send --terminal term_stub --text go|" "$(go_after 'orchestration worker-start')"
DISPATCH_OK=0 role_launch investigator >/dev/null
check "a Claude seat's sent prompt is followed by one typed go" "orchestration worker-start|terminal send --terminal term_stub --text Your task spec|terminal send --terminal term_stub --text go|" "$(go_after 'orchestration worker-start|terminal send .*--text Your task spec')"
role_launch companion >/dev/null
check "a Codex seat gets no go" 0 "$(grep -c -- '--text go --enter' "$CALLS" || true)"
rm -f "$CL"

# A FINISHED SPEC DOES NOT RUN TWICE. The legacy-cleanup revise seat
# ran the same job three times in 22 minutes (~0.8M tokens): nothing noticed
# that the role had already returned a verdict on that exact spec. collect
# records the verdict beside the spec hash launch wrote; a relaunch of the same
# content is refused, a changed spec launches, and COMMANDECK_SEAT_FORCE=1 reruns.
REC=$TMP/scratch/seat-fake-unit-companion.txt
check "the launch records the spec's content hash" 1 \
  "$(grep -cx "spechash=$(sha256sum "$TMP/spec.md" | cut -d' ' -f1)" "$REC")"
echo 'verdict=VERDICT: GO' >> "$REC"
check "a finished, unchanged spec is refused" 2 "$(role_launch companion)"
check "the refusal opens no pane" 0 "$(grep -c '^terminal create' "$CALLS" || true)"
check "the refusal says how to force a rerun" 1 "$(grep -c 'COMMANDECK_SEAT_FORCE=1' "$TMP/launch.out")"
echo 'verdict=VERDICT: GO' >> "$REC"
check "COMMANDECK_SEAT_FORCE=1 reruns it" 0 "$(COMMANDECK_SEAT_FORCE=1 role_launch companion)"
echo 'verdict=VERDICT: GO' >> "$REC"
echo 'Apply every confirmed finding, round 2.' > "$TMP/spec.md"
check "a changed spec still launches" 0 "$(role_launch companion)"
check "a relaunch clears the old verdict" 0 "$(grep -c '^verdict=' "$REC" || true)"

# A SEAT IN ANOTHER ORCA REPO'S WORKTREE (2026-09-25, other-repo).
# Main names the repo, not a workspace path: the pane opens in that repo's
# worktree without this repo's node_modules symlinks.
OPS=$HOME/orca/workspaces/other-repo/ops-unit; mkdir -p "$OPS"
: > "$CALLS"; rm -f "$TMP/setup.ran"
printf '#!/bin/sh\ntouch %s/setup.ran\n' "$TMP" > "$TMP/repo/scripts/worktree-setup.sh"
( cd "$TMP/repo" && env -u COMMANDECK_WORKSPACES COMMANDECK_SEAT_REPO=other-repo \
    timeout 30 bash scripts/seat.sh launch companion ops-unit "$TMP/spec.md" ) >/dev/null 2>&1
check "a seat named by repo opens in that repo's worktree" 1 "$(grep -c "^terminal create.*path:$OPS " "$CALLS")"
check "another repo's worktree gets no platform setup" 0 "$([ -e "$TMP/setup.ran" ] && echo 1 || echo 0)"
( cd "$TMP/repo" && COMMANDECK_SEAT_REPO='../x' timeout 30 bash scripts/seat.sh launch companion ops-unit "$TMP/spec.md" ) >/dev/null 2>&1
check "a repo name that is a path is refused" 2 "$?"

# One Builder launch may name its model or drop its advisor, and the pane's own
# command carries both. A launch with neither is routing's Builder; the options
# win over the project's own Builder setting.
bm=$(jq -r '.roles.builder.model' "$TMP/repo/config/routing.json") ba=$(jq -r '.roles.builder.advisor' "$TMP/repo/config/routing.json")
pane_cmd() { grep '^terminal create' "$CALLS" | tail -1; }
blaunch() { local u=$1; shift; mkdir -p "$TMP/ws/$u"; : > "$CALLS"; ( cd "$TMP/repo" && timeout 30 bash scripts/seat.sh launch "$@" ) >/dev/null 2>"$TMP/b.err"; }
blaunch b-plain builder b-plain "$TMP/spec.md"
check "a Builder launched with no option runs routing's model with routing's advisor" "1 1" \
  "$(pane_cmd | grep -c -- " --model $bm") $(pane_cmd | grep -c -- " --advisor $ba")"
blaunch b-pick builder b-pick "$TMP/spec.md" --model sonnet --no-advisor
check "a Builder launched on a named model with no advisor runs that model and no advisor" "0 1 0 0" \
  "$? $(pane_cmd | grep -c -- ' --model sonnet') $(pane_cmd | grep -c -- "--model $bm") $(pane_cmd | grep -c -- '--advisor')"
# The silent-pane relaunch (seat.sh wait) starts the seat again from its record, so the record keeps the options.
check "and the seat record keeps both for a relaunch" 1 "$(grep -cx 'opts=--model sonnet --no-advisor' "$TMP/scratch/seat-b-pick-builder.txt")"
blaunch b-noadv builder b-noadv "$TMP/spec.md" --no-advisor
check "a Builder launched with no advisor alone keeps routing's model" "1 0" "$(pane_cmd | grep -c -- " --model $bm") $(pane_cmd | grep -c -- '--advisor')"
mkdir -p "$TMP/repo/.claude"; echo '{"builder":{"model":"sonnet","advisor":"opus"}}' > "$TMP/repo/.claude/commandeck.json"
blaunch b-proj builder b-proj "$TMP/spec.md"
check "a project's own Builder setting applies when the launch names nothing" "1 1" "$(pane_cmd | grep -c -- ' --model sonnet') $(pane_cmd | grep -c -- ' --advisor opus')"
blaunch b-proj2 builder b-proj2 "$TMP/spec.md" --model fable --no-advisor
check "and a launch's own options win over it" "1 0" "$(pane_cmd | grep -c -- ' --model fable') $(pane_cmd | grep -c -- '--advisor')"
rm -f "$TMP/repo/.claude/commandeck.json"
blaunch b-other companion b-other "$TMP/spec.md" --model sonnet
check "no other seat takes a model for one launch: refused, no pane" "2 0" "$? $(grep -c '^terminal create' "$CALLS" || true)"
blaunch b-other2 companion b-other2 "$TMP/spec.md" --no-advisor
check "nor a dropped advisor" "2 0" "$? $(grep -c '^terminal create' "$CALLS" || true)"
blaunch b-bad builder b-bad "$TMP/spec.md" --effort high
check "an option the Builder launch does not have is refused, no pane" "2 0" "$? $(grep -c '^terminal create' "$CALLS" || true)"
# The seat is also launched by hand, so it makes the launch script's model check itself.
for m in haiku opus-9-9 gpt-6.1-sol 'sonnet[1m]'; do
  blaunch b-bad-model builder b-bad-model "$TMP/spec.md" --model "$m"
  check "a hand-launched Builder on $m is refused, no pane" "2 0 1" "$? $(grep -c '^terminal create' "$CALLS" || true) $(grep -c '^REFUSED: --model' "$TMP/b.err")"
done
blaunch b-nomodel builder b-nomodel "$TMP/spec.md" --model
check "a model option with no model is refused, no pane" "2 0" "$? $(grep -c '^terminal create' "$CALLS" || true)"
# A live pane keeps the model and advisor it opened with, so a launch that asks for
# others than the record's must not pass as the same seat.
blaunch b-reuse builder b-reuse "$TMP/spec.md" --model sonnet --no-advisor
LIVE_PANE=true blaunch b-reuse builder b-reuse "$TMP/spec.md" --model sonnet --no-advisor
check "a live Builder pane is reused by a launch with the same options" "0 0" "$? $(grep -c '^orchestration task-create' "$CALLS" || true)"
LIVE_PANE=true blaunch b-reuse builder b-reuse "$TMP/spec.md" --model fable
check "a launch with another model than the live pane's is refused" "2 1" "$? $(grep -c '^REFUSED: live builder seat .* options' "$TMP/b.err")"
LIVE_PANE=true blaunch b-reuse builder b-reuse "$TMP/spec.md"
check "and one with no option, when the pane dropped its advisor, is refused" "2 1" "$? $(grep -c '^REFUSED: live builder seat .* options' "$TMP/b.err")"
blaunch b-reuse2 builder b-reuse2 "$TMP/spec.md"
LIVE_PANE=true blaunch b-reuse2 builder b-reuse2 "$TMP/spec.md" --no-advisor
check "nor a dropped advisor on a pane opened with its advisor" "2 1" "$? $(grep -c '^REFUSED: live builder seat .* options' "$TMP/b.err")"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

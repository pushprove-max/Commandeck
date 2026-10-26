#!/usr/bin/env bash
# Issue 351 ask 4: answer-worker.sh --interrupt. An answer to a pane blocked in ask-main.sh's wait can be typed in at
# once, interrupting that wait. Only a pane whose ask-main.sh is in that wait as the answer is sent takes it: an
# unexpired question is not enough, since ask-main.sh returns after each 240 s slice and the Builder works on, and an
# interrupt would cut that work. So the cases run the real ask-main.sh: its inbox wait blocks while $T/hold exists, and
# touches $T/waiting once it has begun. (Split from answer-worker.test.sh, which ran past its time budget.)
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/ws/u1/.claude/briefs"; : > "$T/ws/u1/.claude/briefs/u1.md"
git init -q -b main "$T/p" && git -C "$T/p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
LOG=$T/home/.claude/projects/$(printf '%s' "$T/ws/u1" | tr -c 'A-Za-z0-9' '-')/s1.jsonl
mkdir -p "$(dirname "$LOG")"
echo '{"type":"user","message":{"role":"user","content":"build it"},"timestamp":"2026-10-15T10:00:00Z","sessionId":"s1"}' > "$LOG"
# Orca as answer-worker.sh sees it: one Claude pane term_b in worktree u1, its state in $T/state; a typed text lands in
# the pane's log; an inbox send lands in $T/inbox, a reply in $T/replies.
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  # \$T/end-on-list: this lookup ends the held ask-main.sh wait (removes \$T/hold) and gives its call a second to return.
  "terminal list") [ ! -e "$T/end-on-list" ] || { rm -f "$T/end-on-list" "$T/hold"; sleep 1; }
    jq -n '{result: {terminals: [{handle: "term_b", tabId: "t1", leafId: "l1", worktreePath: "$T/ws/u1"}]}}' ;;
  "worktree ps") jq -n --arg s "\$(cat "$T/state")" '{result: {worktrees: [{path: "$T/ws/u1", agents: [{paneKey: "t1:l1", agentType: "claude", state: \$s}]}]}}' ;;
  # An interrupting send notes whether the ask-main.sh call in \$T/livepid was still running as it was sent; with
  # \$T/end-on-send it first ends that call's held wait and gives it a second to return.
  "terminal send") case "\$*" in *--interrupt*) echo "\$*" >> "$T/interrupted"
      [ ! -e "$T/end-on-send" ] || { rm -f "$T/end-on-send" "$T/hold"; sleep 1; }
      kill -0 "\$(cat "$T/livepid" 2>/dev/null)" 2>/dev/null && echo alive >> "$T/at-send" || echo gone >> "$T/at-send" ;; esac
    while [ \$# -gt 0 ]; do case \$1 in --text) t=\$2 ;; esac; shift; done
    echo typed >> "$T/typed"
    # \$T/send-fails: the text is typed, then the send fails, as a send killed by its timeout does.
    [ ! -e "$T/send-fails" ] || exit 1
    jq -cn --arg t "\$t" '{type: "user", message: {role: "user", content: \$t}, timestamp: "2026-10-15T10:05:00Z", sessionId: "s1"}' >> "$LOG"
    echo '{"ok":true}' ;;
  "orchestration send") while [ \$# -gt 0 ]; do case \$1 in --body) b=\$2 ;; esac; shift; done; printf '%s\n' "\$b" >> "$T/inbox"; echo '{"ok":true}' ;;
  "orchestration reply") while [ \$# -gt 0 ]; do case \$1 in --body) b=\$2 ;; --id) i=\$2 ;; esac; shift; done; printf '%s %s\n' "\$i" "\$b" >> "$T/replies"; echo '{"ok":true}' ;;
  *) echo '{"ok":true}' ;;
esac
EOF
chmod +x "$T/bin/orca-ide"
answer() { (cd "$T/p" && env -u CLAUDE_PROJECT_DIR -u CLAUDE_CONFIG_DIR COMMANDECK_FOREGROUND=1 HOME="$T/home" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_SCRATCH="$T/scratch" ANSWER_WORKER_WAIT=2 ANSWER_WORKER_ACK_WAIT=3 PATH="$T/bin:$PATH" bash "$REAL/scripts/answer-worker.sh" "$@" 2>&1); }
# run <command line> -- a printed answer-worker.sh command, run as written, the way main would paste it.
run() { (cd "$T/p" && env -u CLAUDE_PROJECT_DIR -u CLAUDE_CONFIG_DIR COMMANDECK_FOREGROUND=1 HOME="$T/home" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_SCRATCH="$T/scratch" ANSWER_WORKER_WAIT=2 ANSWER_WORKER_ACK_WAIT=3 PATH="$T/bin:$PATH" bash -c "$1" 2>&1); }

mkdir -p "$T/askbin" "$T/scratch/handles"; echo term_main > "$T/scratch/handles/main"
cat > "$T/askbin/orca-ide" <<AEOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "terminal list") jq -n '{result: {terminals: [{handle: "term_main", worktreePath: "$T/p", agentIdentity: "claude"}]}}' ;;
  "orchestration send") while [ \$# -gt 0 ]; do case \$1 in --body) printf '%s\n' "\$2" > "$T/note" ;; esac; shift; done
    jq -n --arg id "\$(cat "$T/next-id" 2>/dev/null || echo msg_a1)" '{ok: true, result: {message: {id: \$id}}}' ;;
  "orchestration check") case " \$* " in *" --wait "*) touch "$T/waiting"; while [ -e "$T/hold" ]; do sleep 0.1; done ;; esac
    echo '{"ok":true,"result":{"messages":[],"timedOut":true}}' ;;
  *) echo '{"ok":true}' ;;
esac
AEOF
chmod +x "$T/askbin/orca-ide"
# askm <pane> <args> -- ask-main.sh run from <pane>; it execs, so call it in a subshell: in the background, $! is its pid.
askm() { local p=$1; shift; cd "$T/p" && exec env -u CLAUDE_PROJECT_DIR COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_SCRATCH="$T/scratch" ORCA_TERMINAL_HANDLE="$p" PATH="$T/askbin:$PATH" bash "$REAL/scripts/ask-main.sh" "$@" >/dev/null 2>&1; }
# held <pane> <ask-main.sh args> -- run ask-main.sh from <pane> until its wait is blocked; LIVE is its pid.
held() { local p=$1 i; shift; rm -f "$T/waiting"; touch "$T/hold"; (askm "$p" "$@") & LIVE=$!; echo "$LIVE" > "$T/livepid"
  for i in $(seq 100); do [ -e "$T/waiting" ] && return 0; sleep 0.1; done; echo "FAIL ask-main.sh never began its wait"; }
# live <pane> <id> -- a new question from <pane> whose wait is still blocked.
live() { echo "$2" > "$T/next-id"; held "$1" q b; }
release() { rm -f "$T/hold"; wait "$LIVE" 2>/dev/null; }
rm -rf "$T/scratch/ask-main"; rm -f "$T/interrupted" "$T/hold"; : > "$T/typed"; : > "$T/inbox"; : > "$T/replies"

# Past the deadline ask-main.sh tells main the question is unanswered and names the command to answer it with. The
# pane has ended its wait by then, so that command must be the plain route: run as written, it reaches the pane.
(COMMANDECK_ASK_MAIN_NOW=1000 askm term_b q b); (COMMANDECK_ASK_MAIN_NOW=1541 askm term_b --resume msg_a1)
CMD=$(sed -n 's/.*the answer did not reach the pane: //p' "$T/note"); CMD=${CMD/<answer>/use sqlite}
echo idle > "$T/state"
OUT=$(run "$CMD"); RC=$?
check "the unanswered note's command, run as written past the deadline, types the answer in and replies in the question's thread" "0 1 1 0" \
  "$RC $(grep -c 'delivered to term_b (typed into the pane)' <<<"$OUT") $(grep -c '^msg_a1 .*use sqlite$' "$T/replies") $(grep -c 'refused' <<<"$OUT")"
: > "$T/typed"
OUT=$(answer --interrupt term_b "too late"); RC=$?
check "--interrupt to a pane whose ask-main.sh gave up at its deadline is refused: nothing is typed" "1 0 1" \
  "$RC $(wc -l < "$T/typed" | tr -d ' ') $(grep -c 'not waiting in ask-main.sh' <<<"$OUT")"

rm -rf "$T/scratch/ask-main"; echo working > "$T/state"; : > "$T/typed"
live term_b msg_a1
OUT=$(answer term_b "no interrupt"); RC=$?
check "without --interrupt nothing is typed into a mid-turn pane, even one waiting in ask-main.sh: the answer queues in its inbox and ends NOT acknowledged (exit 1, issue 351)" "1 0 1 0" \
  "$RC $(wc -l < "$T/typed" | tr -d ' ') $(grep -c 'no interrupt' "$T/inbox") $([ -e "$T/interrupted" ] && echo 1 || echo 0)"
OUT=$(answer --interrupt term_b "use sqlite"); RC=$?
check "--interrupt to a pane blocked in ask-main.sh's wait types the answer in with the interrupt flag" "0 1 1" \
  "$RC $(grep -c -- '--interrupt' "$T/interrupted" 2>/dev/null) $(grep -c 'typed into the pane with an interrupt' <<<"$OUT")"
release; rm -f "$T/interrupted"; : > "$T/typed"
# The return removes the wait token itself: a pid alone could be reused by another pane's ask-main.sh before the guard reads it.
check "the slice returned: the question is still open, its 9 minutes are not over, and its wait token is gone" "1 1 0" \
  "$(ls "$T/scratch/ask-main" | grep -cx msg_a1) $(( $(sed -n 's/^deadline=//p' "$T/scratch/ask-main/msg_a1") > $(date +%s) )) $(ls "$T/scratch/ask-main" | grep -c '\.wait$')"
OUT=$(answer --interrupt term_b "cuts the work"); RC=$?
check "--interrupt after ask-main.sh's slice returned (the Builder works on, question unexpired) is refused: nothing is typed" "1 0 0 1" \
  "$RC $(wc -l < "$T/typed" | tr -d ' ') $([ -e "$T/interrupted" ] && echo 1 || echo 0) $(grep -c 'not waiting in ask-main.sh' <<<"$OUT")"

rm -rf "$T/scratch/ask-main"; live term_other msg_a2
OUT=$(answer --interrupt term_b "wrong pane"); RC=$?
check "--interrupt to a pane with no waiting ask-main.sh is refused (another pane's live wait does not count)" "1 0 0 1" \
  "$RC $(wc -l < "$T/typed" | tr -d ' ') $([ -e "$T/interrupted" ] && echo 1 || echo 0) $(grep -c 'not waiting in ask-main.sh' <<<"$OUT")"
release

rm -rf "$T/scratch/ask-main"; live term_b msg_a1; kill -9 "$LIVE"; release
check "the killed call left its wait token, naming its own pid" "pid=$LIVE" "$(grep '^pid=' "$T/scratch/ask-main/msg_a1.wait")"
OUT=$(answer --interrupt term_b "killed wait"); RC=$?
check "--interrupt after ask-main.sh's wait was killed (no chance to clear its mark) is refused: nothing is typed" "1 0 0 1" \
  "$RC $(wc -l < "$T/typed" | tr -d ' ') $([ -e "$T/interrupted" ] && echo 1 || echo 0) $(grep -c 'not waiting in ask-main.sh' <<<"$OUT")"

# Class interrupt-lifetime: an interrupt is typed only while the pane's ask-main.sh call is still in its wait, so it never
# cuts the work the Builder resumes after. Every ordering found so far, in order: (r1) the note past the deadline, no wait
# open; (r1) the slice returned before --interrupt ran; (r2) the slice returns after the old guard, during the pane
# lookup; and the last moment left, the slice returning during the send itself: its call must not return before the
# interrupt is sent, and returns once it is. Only that last one is sent, and nothing is left behind.
rm -rf "$T/scratch/ask-main"; rm -f "$T/interrupted" "$T/at-send"; : > "$T/typed"; echo working > "$T/state"
(COMMANDECK_ASK_MAIN_NOW=1000 askm term_b q b); (COMMANDECK_ASK_MAIN_NOW=1541 askm term_b --resume msg_a1)
O1=$(answer --interrupt term_b "order 1"); R1=$?
rm -rf "$T/scratch/ask-main"; live term_b msg_a1; release
O2=$(answer --interrupt term_b "order 2"); R2=$?
rm -rf "$T/scratch/ask-main"; live term_b msg_a1; touch "$T/end-on-list"
O3=$(answer --interrupt term_b "order 3"); R3=$?
wait "$LIVE"; RW3=$?
rm -rf "$T/scratch/ask-main"; live term_b msg_a1; touch "$T/end-on-send"
O4=$(answer --interrupt term_b "order 4"); R4=$?
wait "$LIVE"; RW4=$?
refused() { [ "$1" = 1 ] && grep -q 'not waiting in ask-main.sh' <<<"$2" && echo refused || echo "sent($1)"; }
check "every ordering found so far, in order: past the deadline, slice returned, slice ending during the lookup are refused; a slice ending during the send returns only after it; nothing left" \
  "refused refused refused 3 0 alive 3 0" \
  "$(refused $R1 "$O1") $(refused $R2 "$O2") $(refused $R3 "$O3") $RW3 $R4 $(paste -sd, "$T/at-send" 2>/dev/null) $RW4 $(ls "$T/scratch/ask-main" | grep -c '\.wait$\|\.claim\.')"

# One retry, whatever piece of the wait's state is gone: a refused --interrupt prints the plain command, which reads no
# ask-main.sh state; run as written it delivers. Each piece is removed between the two runs: the wait token, its pane=
# line, and the process it names (killed, so it cannot remove the token).
echo idle > "$T/state"
for piece in token pane process; do
  rm -rf "$T/scratch/ask-main"; rm -f "$T/interrupted"; : > "$T/typed"; : > "$T/replies"; live term_b msg_a1
  case $piece in
    token) rm -f "$T/scratch/ask-main/msg_a1.wait" ;;
    pane) sed -i.bak '/^pane=/d' "$T/scratch/ask-main/msg_a1.wait"; rm -f "$T/scratch/ask-main/msg_a1.wait.bak" ;;
    process) kill -9 "$LIVE"; wait "$LIVE" 2>/dev/null ;;
  esac
  OUT=$(answer --interrupt term_b "retry $piece" msg_a1); RC=$?
  OUT2=$(run "$(sed -n 's/.*Send it without --interrupt: //p' <<<"$OUT")"); RC2=$?
  check "the wait's $piece removed: --interrupt is refused with nothing typed, and its printed retry delivers in the question's thread" "1 0 0 1" \
    "$RC $([ -e "$T/interrupted" ] && echo 1 || echo 0) $RC2 $(grep -c "^msg_a1 .*retry $piece\$" "$T/replies")"
  release
done

# A --resume from another pane (a restarted Builder has a new handle) waits as that pane: the token names the pane
# blocked now, not the one that asked, so the asker's old handle is not interrupted.
rm -rf "$T/scratch/ask-main"; rm -f "$T/interrupted"; : > "$T/typed"; live term_b msg_a1; release
held term_other --resume msg_a1
OUT=$(answer --interrupt term_b "old handle" msg_a1); RC=$?
check "a question resumed from another pane: --interrupt to the asker's handle is refused, nothing is typed" "1 0 1" \
  "$RC $([ -e "$T/interrupted" ] && echo 1 || echo 0) $(grep -c 'not waiting in ask-main.sh' <<<"$OUT")"
release

# A send that fails after typing (killed by its 8 s timeout) cannot prove nothing was typed: the message says the answer
# may be in the pane, so main checks before the plain retry and does not type it twice.
rm -rf "$T/scratch/ask-main"; rm -f "$T/interrupted"; : > "$T/typed"; echo working > "$T/state"; live term_b msg_a1
touch "$T/send-fails"; OUT=$(answer --interrupt term_b "typed then failed" msg_a1); RC=$?; rm -f "$T/send-fails"
check "an interrupting send that fails after typing says the answer may have been typed, and to check the pane first" "1 1 1 0" \
  "$RC $(wc -l < "$T/typed" | tr -d ' ') $(grep -c 'may have been typed before it ended, so check the pane first' <<<"$OUT") $(grep -c 'was not delivered' <<<"$OUT")"
release

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

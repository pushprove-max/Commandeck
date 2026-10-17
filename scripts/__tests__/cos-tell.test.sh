#!/usr/bin/env bash
# Main's notes to the relay went to its pane handle, a live-only mailbox: the
# relay later said none of main's recent reports had reached it. Pinned: a note
# sent with cos-tell.sh --note goes to main's run, waits there while the relay
# is busy, and its inbox watcher prints it at its next poll; a send Orca does
# not confirm as stored, or one with no run recorded, exits 1 and says so.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/ws" "$T/scratch" "$T/home"
git init -q -b main "$T/p" && git -C "$T/p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
# Orca: a send to run:<id> is stored with its run and a sequence and answered with its message id, unless
# $T/live-only exists (then it answers the way a live-only mailbox does); the inbox lists what is stored.
# A command named in $T/down fails the way an Orca outage does. $T/during-send, when it exists, runs while a send is pending.
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
! grep -qx "\$2" "$T/down" 2>/dev/null || { echo '{"ok":false}'; exit 1; }
case "\$1 \$2" in
  "orchestration send") [ ! -e "$T/during-send" ] || bash "$T/during-send"
    [ ! -e "$T/live-only" ] || { echo '{"ok":true,"result":{"warning":"live terminal-only mailbox, delivery is not durable"}}'; exit 0; }
    while [ \$# -gt 0 ]; do case \$1 in --run) r=\$2 ;; --to) to=\$2 ;; --subject) s=\$2 ;; --body) b=\$2 ;; --type) ty=\$2 ;; esac; shift; done
    n=\$(( \$(cat "$T/store.jsonl" 2>/dev/null | wc -l) + 1 ))
    jq -cn --argjson n \$n --arg r "\$r" --arg to "\$to" --arg s "\$s" --arg b "\$b" --arg t "\$ty" \
      '{sequence: \$n, run_id: \$r, from_handle: "term_main", to_handle: \$to, subject: \$s, body: \$b, type: \$t, created_at: "2026-10-15T10:00:00Z"}' >> "$T/store.jsonl"
    echo "{\"ok\":true,\"result\":{\"message\":{\"id\":\"msg_\$n\"}}}" ;;
  "terminal list") echo '{"ok":true,"result":{"terminals":[{"handle":"term_main","worktreePath":"$T/p","agentIdentity":"claude"}]}}' ;;
  "orchestration run-list") echo '{"ok":true,"result":{"runs":[{"id":"run_1","coordinator_handle":"term_main"}]}}' ;;
  "orchestration inbox") jq -s '{ok: true, result: {messages: .}}' "$T/store.jsonl" 2>/dev/null || echo '{"ok":true,"result":{"messages":[]}}' ;;
  *) echo '{"ok":true}' ;;
esac
EOF
chmod +x "$T/bin/orca-ide"
E=(env -u CLAUDE_PROJECT_DIR HOME="$T/home" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$T/ws" COMMANDECK_SCRATCH="$T/scratch" PATH="$T/bin:$PATH")
note() { (cd "$T/p" && "${E[@]}" bash "$REAL/scripts/cos-tell.sh" --note "$1" "$2" 2>&1); }
watch() { (cd "$T/p" && "${E[@]}" COMMANDECK_WATCH_ONCE=1 bash "$REAL/scripts/cos-watch-inbox.sh" term_cos 2>&1); }

OUT=$(note "unit u1 merged" "u1 is on main"); RC=$?
check "with no run recorded the note is not sent, and says so" "1:1" "$RC:$(grep -c 'NOT sent: no run recorded' <<<"$OUT")"
check "and says only that: no shell error about the missing run file" 1 "$(grep -c . <<<"$OUT")"
echo run_1 > "$T/scratch/current-run"
note "first" "x" >/dev/null; watch >/dev/null   # the watcher's first poll marks what is already there as read
# The relay is busy: nothing polls while the note is sent.
OUT=$(note "unit u2 merged" "u2 is on main"); RC=$?
check "a note goes to main's run and is confirmed stored" "0:run:run_1" "$RC:$(jq -r 'select(.sequence == 2) | .to_handle' "$T/store.jsonl")"
check "and the relay's watcher prints it at its next poll" 1 "$(watch | grep -c 'unit u2 merged | u2 is on main')"
touch "$T/live-only"
OUT=$(note "unit u3 merged" "u3"); RC=$?
check "a send Orca does not confirm as stored exits 1 and says so" "1:1" "$RC:$(grep -c 'NOT sent: Orca did not confirm a stored message' <<<"$OUT")"
rm -f "$T/live-only"

# Main put a release question to the owner as a `question` with a plain subject;
# the watcher passed only `status` from main, marked it read, and the owner never
# heard. Any type from main to its run or to this pane wakes the relay; main's
# messages to a worker, its scripts' notes and worker traffic do not.
# row <from> <to> <type> <subject> [<sent at>] [<run id>] -- one message stored, in run_1 unless named.
row() { jq -cn --argjson n $(( $(wc -l < "$T/store.jsonl") + 1 )) --arg f "$1" --arg to "$2" --arg t "$3" --arg s "$4" --arg at "${5:-2026-10-15T10:00:00Z}" --arg r "${6-run_1}" \
  '{sequence: $n, run_id: $r, from_handle: $f, to_handle: $to, subject: $s, body: "b", type: $t, created_at: $at}' >> "$T/store.jsonl"; }
watch >/dev/null
row term_main run:run_1 question "0.9.0 is ready. OK to release?"
check "a question from main with a plain subject wakes the relay" 1 "$(watch | grep -c 'OK to release?')"
row term_main term_cos escalation "the merge needs a decision"
check "any other type from main to this pane wakes it too" 1 "$(watch | grep -c 'the merge needs a decision')"
row term_main term_w1 question "use the second option"
row term_main term_w1 status "work added to u1"
row term_main run:run_1 question "seat review u1: GO"
row term_main run:run_1 question "main-watch: 2 items need you"
row term_w1 run:run_1 question "should I split the file?"
row term_w1 run:run_1 worker_done "u1 done"
check "main's messages to a worker, its scripts' notes and worker traffic do not" "rc=1" "$(watch >/dev/null; echo "rc=$?")"
# Issue 166: main's answer-worker.sh reply to this pane, sent with no run id while the pane was busy, was dropped
# by the run rule and by its "answer from main" subject. A message to this pane's own handle always wakes it.
row term_main term_cos status "answer from main" 2026-10-15T10:00:00Z ""
check "main's answer to this pane's own handle, with no run id, wakes it" 1 "$(watch | grep -c 'answer from main')"
row term_main term_cos status "FYI owner answer"
check "an FYI to this pane's own handle wakes it too, and is printed" 1 "$(watch | grep -c 'FYI owner answer')"
row term_main run:run_1 status "heads-up: x"; row term_main run:run_1 status "main-watch: y"; row term_w1 run:run_1 worker_done "u2 done"
check "the run's heads-up, main-watch and worker_done traffic still does not" "rc=1" "$(watch >/dev/null; echo "rc=$?")"
row term_main run:run_1 status "FYI to the run"
check "an FYI to the run is still held" "rc=1" "$(watch >/dev/null; echo "rc=$?")"

# The relay passed the owner's message to main (to-main.sh marks it owed), and
# main answered on its own screen: nothing reached the relay and the owner
# waited on an answer that existed. The watcher flags main's ended turn at its
# next poll, with main's last words from its session log, once; a reply main
# sent clears the mark, and a turn still running is not a stop.
LOG=$T/home/.claude/projects/$(printf '%s' "$T/p" | tr -c 'A-Za-z0-9' '-')/s1.jsonl; mkdir -p "${LOG%/*}"
turn() { # <ended: 1|0> [<minute> <reply>] -- main's session: a prompt, its reply, and the turn's end when 1
  { jq -cn --arg m "${2:-00}" '{type: "user", timestamp: "2026-10-16T10:\($m):00Z", message: {content: "[from the relay] is u1 merged?"}}'
    jq -cn --arg m "${2:-00}" --arg r "${3:-Yes, u1 merged at 09:55.}" '{type: "assistant", timestamp: "2026-10-16T10:\($m):05Z", message: {content: [{type: "text", text: $r}]}}'
    [ "$1" = 0 ] || jq -cn --arg m "${2:-00}" '{type: "system", subtype: "turn_duration", timestamp: "2026-10-16T10:\($m):06Z"}'; } > "$LOG"; }
OWED=$T/scratch/cos-owed
printf '1000\tis u1 merged?\n' > "$OWED"; turn 0
check "main still working on the owner's message is not flagged" "rc=1" "$(watch >/dev/null; echo "rc=$?")"
turn 1; OUT=$(watch)
check "main's turn ended with nothing sent back: flagged with its last words" 1 "$(grep -c 'main ended a turn without sending you a reply to "is u1 merged?"; its last words: Yes, u1 merged at 09:55\.' <<<"$OUT")"
check "once" "rc=1:gone" "$(watch >/dev/null; echo "rc=$?"):$([ -e "$OWED" ] && echo kept || echo gone)"
printf '1000\tis u2 merged?\n' > "$OWED"
note "u2 merged" "yes, at 10:01" >/dev/null
check "a reply main sends with cos-tell.sh --note reaches the relay and clears the mark" "1:gone" "$(watch | grep -c 'yes, at 10:01'):$([ -e "$OWED" ] && echo kept || echo gone)"
printf '1000\tis u3 merged?\n' > "$OWED"; row term_main run:run_1 question "u3: merged at 10:02"
check "so does any message main sends the relay" "1:gone" "$(watch | grep -c 'u3: merged'):$([ -e "$OWED" ] && echo kept || echo gone)"
# The relay passes main the owner's next message while main's note is still being sent: the note is no reply to it.
printf 'printf "%%s\\tasked during the send\\n" "$(date +%%s)" > %q\n' "$OWED" > "$T/during-send"
note "progress" "working" >/dev/null; rm "$T/during-send"
check "a note's confirmation leaves a message marked owed while it was being sent" "asked during the send" "$(cut -sf2 "$OWED" 2>/dev/null)"
rm -f "$OWED"; watch >/dev/null
# A message main sent before the owner's message was marked owed, read late (the relay was down), is no reply to it.
printf '%s\tis u6 merged?\n' "$(date +%s)" > "$OWED"; row term_main run:run_1 status "u6 build started" 2026-10-15T09:00:00Z
check "an older message from main does not clear a newer mark" "1:kept" "$(watch | grep -c 'u6 build started'):$([ -e "$OWED" ] && echo kept || echo gone)"
# The mark is written before the message reaches main: a message from main in that same second is no reply.
printf '1792058400\tis u6 done?\n' > "$OWED"; row term_main run:run_1 status "u6 half built" 2026-10-15T10:00:00Z
check "a message from main sent in the second the mark was made does not clear it" "1:kept" "$(watch | grep -c 'u6 half built'):$([ -e "$OWED" ] && echo kept || echo gone)"
# The mark is main's to clear: a worker's note is not main's reply.
git -C "$T/p" worktree add -q "$T/ws/u1" -b u1
OUT=$(cd "$T/ws/u1" && "${E[@]}" bash "$REAL/scripts/cos-tell.sh" --note "progress" "working" 2>&1)
check "a note sent from a worker's checkout leaves main's mark" kept "$([ -e "$OWED" ] && echo kept || echo gone)"
rm -f "$OWED"; watch >/dev/null
# An Orca read that fails says nothing about main: no silent-stop flag, and the owed mark stays.
printf '1000\tis u7 merged?\n' > "$OWED"
for c in run-list inbox; do
  echo "$c" > "$T/down"
  check "Orca's $c failing is not main's silence: nothing flagged, the mark kept" "0:kept" "$(watch | grep -c 'main ended'):$([ -e "$OWED" ] && echo kept || echo gone)"
done
rm "$T/down"
check "with Orca back, the same state is flagged" 1 "$(watch | grep -c 'a reply to "is u7 merged?"')"
# Main's ruling: a report or question main starts on its own (a build done, a check failed) is the owner's too.
# Every main turn that ends with nothing sent to the relay since main's turn before it is flagged, once.
turn 1 10 "Build u4 is done: GO, merged."
check "a report main started on its own, left only on its screen, is flagged with its last words" 1 \
  "$(watch | grep -c 'main ended a turn without sending you anything; its last words: Build u4 is done: GO, merged\.')"
check "once" "rc=1" "$(watch >/dev/null; echo "rc=$?")"
# The owner's message marked owed after main's turn ended is not that turn's to answer: flagging the turn keeps it.
printf '4102444800\tasked after the turn\n' > "$OWED"; turn 1 15 "Build u8 is done."
check "a silent turn ending before the owner's newest message is flagged, and that message stays owed" "1:kept" \
  "$(watch | grep -c 'without sending you anything; its last words: Build u8 is done\.'):$([ -e "$OWED" ] && echo kept || echo gone)"
rm -f "$OWED"
row term_main run:run_1 status "u5 done: GO" 2026-10-16T10:20:03Z; turn 1 20 "u5 is done; I told the relay."
check "a report main sent the relay in its turn wakes it, and its turn's end is no silent stop" "1:rc=1" "$(watch | grep -c 'u5 done: GO'):$(watch >/dev/null; echo "rc=$?")"
# Main sent the relay a report after its last judged turn; an older one, read late, must not hide that send.
row term_main run:run_1 status "u9 started" 2026-10-16T10:25:00Z; watch >/dev/null
row term_main run:run_1 status "u0 queued" 2026-10-16T10:01:00Z; watch >/dev/null
turn 1 26 "u9 is underway."
check "a message from main read late does not move its send time back: the turn after a newer send is no silent stop" "rc=1" "$(watch >/dev/null; echo "rc=$?")"
rm "$(HOME=$T/home bash -c '. "$1"; pp_cos_key "$2"; printf %s "$COS_KEY"' _ "$REAL/hooks/lib/project.sh" "$T/p").main-turn"; turn 1 30 "an old report"
check "a turn main ended before the relay first looked is history, not flagged" "rc=1" "$(watch >/dev/null; echo "rc=$?")"
# 10:35:06Z, the second main's turn ends: a message marked then reached main after the turn's last words.
printf '1792146906\tasked as the turn ended\n' > "$OWED"; turn 1 35 "u9 still building."
OUT=$(watch)
check "a turn ending in the second the mark was made is not its silent reply, and the mark stays" "0:1:kept" \
  "$(grep -c 'a reply to' <<<"$OUT"):$(grep -c 'without sending you anything' <<<"$OUT"):$([ -e "$OWED" ] && echo kept || echo gone)"
rm -f "$OWED"
# The relay passes main the owner's next message at the worst moment: after a script that clears the mark read the
# old one, before it removed it. Removing then erased the newer message's mark, and the owner's question went unflagged.
# While $T/racing exists, each removal of the mark (rm, or Python's os.remove) first runs to-main.sh's write of a newer
# mark, made at the time $T/racing holds, under its lock: at once when the lock is free, else in the background once the remover lets go ($T/racer.lock
# is held until then).
cat > "$T/race" <<EOF
#!/usr/bin/env bash
[ -e "$T/racing" ] || exit 0
exec 9>&-
AT=\$(cat "$T/racing")
mark() { printf '%s\tasked mid-clear\n' "\$AT" > "$OWED"; }
if flock -n "$OWED.lock" true; then mark
else exec 8>>"$T/racer.lock"; flock 8; { flock 7; mark; } 7>>"$OWED.lock" & fi
EOF
printf '#!/bin/sh\ncase "$*" in *cos-owed) %q ;; esac\nexec %q "$@"\n' "$T/race" "$(command -v rm)" > "$T/bin/rm"
mkdir -p "$T/py"; printf 'import os, subprocess\n_rm = os.remove\ndef remove(p, *a, **k):\n    if str(p).endswith("cos-owed"):\n        subprocess.run(["%s"])\n    return _rm(p, *a, **k)\nos.remove = remove\n' "$T/race" > "$T/py/sitecustomize.py"
chmod +x "$T/race" "$T/bin/rm"; E+=(PYTHONPATH="$T/py"); echo 4102444800 > "$T/racing"
racing() { flock "$T/racer.lock" true; cut -sf2 "$OWED" 2>/dev/null; rm -f "$OWED"; }
printf '1000\tis u10 merged?\n' > "$OWED"; note "u10 merged" "yes" >/dev/null
check "a reply main sends never clears a mark written after cos-tell.sh read the old one" "asked mid-clear" "$(racing)"
printf '1000\tis u11 merged?\n' > "$OWED"; row term_main run:run_1 status "u11 merged" 2026-10-16T10:40:00Z
check "nor does the relay's watcher, reading main's reply" "2:asked mid-clear" "$(watch | grep -c 'u1[01] merged'):$(racing)"
printf '1000\tis u12 merged?\n' > "$OWED"; turn 1 45 "u12 is merged."
check "nor its flag of main's silent turn" "1:asked mid-clear" "$(watch | grep -c 'a reply to "is u12 merged?"'):$(racing)"
# The flag reads the mark before it prints main's last words and clears it after: a mark written in that gap, in the
# same second as the one read, was cleared with it. The write runs once, as the flag reads main's last words.
printf '#!/bin/sh\ncase "$*" in *last_message=*) %q </dev/null >/dev/null 2>&1; rm -f %q ;; esac\nexec %q "$@"\n' "$T/race" "$T/racing" "$(command -v sed)" > "$T/bin/sed"
chmod +x "$T/bin/sed"; echo 1000 > "$T/racing"
printf '1000\tis u13 merged?\n' > "$OWED"; turn 1 50 "u13 is merged."
check "nor a mark made in the second of the one it flags, written as it flags" "1:asked mid-clear" "$(watch | grep -c 'a reply to "is u13 merged?"'):$(racing)"
rm "$T/bin/sed"

# The relay must read main's last reply with one command while main is live.
# Main is not a seat: no seat record ties its pane to a session, and
# read-verdict.sh refused ("cannot tie ..."). It reads the newest session log in
# main's checkout instead, and says so; an older session's reply is not it.
turn 1
jq -cn '{type: "assistant", timestamp: "2026-10-15T08:00:00Z", message: {content: [{type: "text", text: "an older session reply"}]}}' > "${LOG%/*}/s0.jsonl"
touch -t 202610150800 "${LOG%/*}/s0.jsonl"
OUT=$(cd "$T/p" && "${E[@]}" bash "$REAL/scripts/read-verdict.sh" term_main 20 2>&1)
check "main's pane with no seat record: its last reply, from its newest session log, saying so" "1:0:1" \
  "$(grep -c 'Yes, u1 merged at 09:55\.' <<<"$OUT"):$(grep -c 'older session' <<<"$OUT"):$(grep -c "no seat record.*newest session log in main's checkout" <<<"$OUT")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

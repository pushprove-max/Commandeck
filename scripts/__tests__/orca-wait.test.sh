#!/usr/bin/env bash
# orca-wait.sh hides what its noise rules match, and once that was a real owner answer: the relay's "turn complete"
# echo carrying it had no marker, so main never saw it and nothing kept it. Pinned: a message citing a ruling id, or
# from the relay's pane (listed by Orca with only a worktreeId), always shows, even when it is "own" traffic; a status
# note is held, not hidden; what is hidden is kept in hidden.jsonl, which the summary line names; a heartbeat is not
# kept; a driven unit's QUESTION echo is never hidden (issue 321).
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
WS=$T/ws; mkdir -p "$T/bin" "$T/home" "$WS/Chief-of-Staff"
git init -q -b main "$T/p"
msg() { jq -nc --arg id "$1" --arg f "$2" --arg t "$3" --arg s "$4" --arg b "$5" '{id: $id, from_handle: $f, type: $t, subject: $s, body: $b}'; }
# The echoes are questions, as the notify hooks send them, so the echo rules decide them; a status is held (issue 318).
{ msg m1 term_cos question "turn complete" "Owner says proceed"
  msg m2 term_w question "turn complete" "the owner ruled r-19991017-101010-1-a1b2c3"
  msg m3 term_cos status "relay note" "plain words from the relay"
  msg m4 term_w status "progress (wt-x)" "just chatter"
  msg m5 term_w heartbeat "alive" ""; } | jq -sc '{ok: true, result: {deliveryId: "d1", messages: .}}' > "$T/batch.json"
# Orca: the first check answers the batch, an ack answers nothing more; the relay's pane has only a worktreeId.
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"orchestration check"*"--ack"*) echo '{"ok":true,"result":{"messages":[]}}' ;;
  *"orchestration check"*) cat "$T/batch.json" ;;
  *"terminal list"*) jq -nc --arg w "id::$WS/Chief-of-Staff" '{ok: true, result: {terminals: [{handle: "term_cos", worktreeId: \$w}]}}' ;;
  *) echo '{"ok":true}' ;;
esac
EOF
chmod +x "$T/bin/orca-ide"
OUT=$(cd "$T/p" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$WS" \
  COMMANDECK_SCRATCH="$T/sc" ORCA_TERMINAL_HANDLE=term_cos timeout 30 bash "$REAL/scripts/orca-wait.sh" 2>&1)
HID=$T/sc/main-watch/messages/hidden.jsonl
check "the relay pane's plain 'turn complete' echo, with no ruling id, is shown" 1 "$(grep -c '| Owner says proceed' <<<"$OUT")"
check "an echo with no marker that cites a ruling id is shown" 1 "$(grep -c '| the owner ruled r-19991017-101010-1-a1b2c3' <<<"$OUT")"
# Issue 324: the relay's status note, no ruling id, woke main: it prints among the wake's lines, not as a held note.
check "the relay pane's status note prints among the wake's lines, above held notes" "1 0" \
  "$(sed '/^held notes (did not wake you):/,$d' <<<"$OUT" | grep -c '| plain words from the relay') $(sed -n '/^held notes (did not wake you):/,$p' <<<"$OUT" | grep -c 'plain words from the relay')"
check "a worker's status note prints under held notes" 1 "$(sed -n '/^held notes (did not wake you):/,$p' <<<"$OUT" | grep -c 'just chatter')"
check "the summary names hidden.jsonl, which is empty: the note is held and the heartbeat excluded" "1 0" \
  "$(grep -c "all but heartbeats are kept in $HID" <<<"$OUT") $(grep -c . "$HID" 2>/dev/null || true)"
check "no heartbeat in hidden.jsonl" 0 "$(grep -c m5 "$HID" 2>/dev/null || true)"
# Issue 331: an exit with items writes one woke line; a wait that finds nothing writes none; a failed check writes refused.
WLJ=$T/sc/wake-log.jsonl
check "an exit with items writes one woke line" "orca-wait:woke" "$(jq -rs 'map(select(.from == "orca-wait") | "\(.from):\(.result)") | join(",")' "$WLJ" 2>/dev/null)"
printf '{"ok":true,"result":{"messages":[]}}\n' > "$T/batch.json"; WLN=$(wc -l < "$WLJ" | tr -d ' ')
(cd "$T/p" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$WS" \
  COMMANDECK_SCRATCH="$T/sc" ORCA_TERMINAL_HANDLE=term_cos timeout 30 bash "$REAL/scripts/orca-wait.sh" >/dev/null 2>&1)
check "a wait that finds nothing writes no line" "$WLN" "$(wc -l < "$WLJ" | tr -d ' ')"
mkdir -p "$T/bin-down"; printf '#!/usr/bin/env bash\necho "{\\"ok\\":false,\\"error\\":{\\"code\\":\\"boom\\",\\"message\\":\\"orca is down\\"}}"; exit 1\n' > "$T/bin-down/orca-ide"; chmod +x "$T/bin-down/orca-ide"
(cd "$T/p" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin-down:$PATH" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$WS" \
  COMMANDECK_SCRATCH="$T/sc" ORCA_TERMINAL_HANDLE=term_cos timeout 30 bash "$REAL/scripts/orca-wait.sh" >/dev/null 2>&1)
check "a check Orca refuses writes one refused line carrying its code" "refused:boom" "$(tail -1 "$WLJ" | jq -r '"\(.result):\(.error)"')"
{ msg m1 term_cos question "turn complete" "Owner says proceed"
  msg m2 term_w question "turn complete" "the owner ruled r-19991017-101010-1-a1b2c3"
  msg m3 term_cos status "relay note" "plain words from the relay"
  msg m4 term_w status "progress (wt-x)" "just chatter"
  msg m5 term_w heartbeat "alive" ""; } | jq -sc '{ok: true, result: {deliveryId: "d1", messages: .}}' > "$T/batch.json"
# Issue 324: wakeKinds turned down to worker_done never silences the relay; the worker's note is still held.
OUT=$(cd "$T/p" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$WS" \
  COMMANDECK_SCRATCH="$T/sc" COMMANDECK_OPTIONS='{"wakeKinds":"worker_done"}' ORCA_TERMINAL_HANDLE=term_cos timeout 30 bash "$REAL/scripts/orca-wait.sh" 2>&1)
check "wakeKinds=worker_done: the relay's status note still woke main, the worker's is held" "1 0 1" \
  "$(sed '/^held notes (did not wake you):/,$d' <<<"$OUT" | grep -c '| plain words from the relay') $(sed -n '/^held notes (did not wake you):/,$p' <<<"$OUT" | grep -c 'plain words from the relay') $(sed -n '/^held notes (did not wake you):/,$p' <<<"$OUT" | grep -c 'just chatter')"
# Issue 321: a live driver's unit hides its echoes, but never a question or refusal: main must see those.
printf '#!/usr/bin/env bash\necho "drive-wt-q-1.service loaded active running drive"\n' > "$T/bin/systemctl"; chmod +x "$T/bin/systemctl"
{ msg q1 term_w question "claude turn complete: QUESTION (wt-q)" "QUESTION: Which branch should I use?"
  msg q2 term_w question "claude turn complete: VERDICT: GO (wt-q)" "VERDICT: GO"; } | jq -sc '{ok: true, result: {deliveryId: "dq", messages: .}}' > "$T/batch.json"
rm -rf "$T/sc"
OUT=$(cd "$T/p" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$WS" \
  COMMANDECK_SCRATCH="$T/sc" COMMANDECK_HOST_OS=Linux ORCA_TERMINAL_HANDLE=term_cos timeout 30 bash "$REAL/scripts/orca-wait.sh" 2>&1)
check "a driven unit's turn complete: QUESTION echo is shown, its verdict echo hidden" "1 0" \
  "$(grep -c 'Which branch should I use' <<<"$OUT") $(grep -c '| VERDICT: GO' <<<"$OUT")"
rm -f "$T/bin/systemctl"
# A batch too big for one argument (twelve 100,000-character questions, ~1.2 MB) must still show and be acknowledged:
# passing it to jq as an argument failed E2BIG, so the drain exited unacked and every retry hit the same batch.
BIG=$(head -c 100000 /dev/zero | tr '\0' x)
for i in $(seq 1 12); do msg "q$i" term_w question "big $i" "$BIG"; done | jq -sc '{ok: true, result: {deliveryId: "d2", messages: .}}' > "$T/batch.json"
rm -rf "$T/sc"
OUT=$(cd "$T/p" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$WS" \
  COMMANDECK_SCRATCH="$T/sc" ORCA_TERMINAL_HANDLE=term_cos timeout 60 bash "$REAL/scripts/orca-wait.sh" 2>&1); RC=$?
check "a 1.2 MB batch drains: exit 0, all twelve bodies saved whole" "0 12" \
  "$RC $(for i in $(seq 1 12); do f=$T/sc/main-watch/messages/q$i.md; [ -f "$f" ] && [ "$(wc -c < "$f" | tr -d ' ')" = 100000 ] && echo y; done | wc -l | tr -d ' ')"
# After a pass that ended NO-GO the next step main reads is a fix round, never "merge it", even when the merge check
# passes the tip: every finding, P0 to P3, blocks the merge. A GO that passes still merges.
PL=$T/plug; mkdir -p "$PL"; cp -R "$REAL/scripts" "$REAL/hooks" "$REAL/config" "$PL/"
U=$WS/u212; git init -q -b main "$U"; mkdir -p "$U/.claude/briefs"; echo brief > "$U/.claude/briefs/u212.md"
wake() {  # wake <last verdict> <--verify exit code> [a finding class r4 and r5 both end NO-GO on]
  printf 'Pass: review\n[P2] %scould wipe a reply\nVERDICT: %s\n' "${3:+(class: $3) }" "$1" > "$U/.claude/briefs/u212-r5-reports.md"
  if [ -n "${3:-}" ]; then cp "$U/.claude/briefs/u212-r5-reports.md" "$U/.claude/briefs/u212-r4-reports.md"
  else printf 'VERDICT: GO\n' > "$U/.claude/briefs/u212-r4-reports.md"; fi
  git -C "$U" add -A && git -C "$U" -c user.name=t -c user.email=t@t commit -qm r5
  printf '#!/usr/bin/env bash\necho "refused: a P1 is open" >&2\nexit %s\n' "$2" > "$PL/scripts/builder-codex-pass.sh"
  msg w1 term_u status "pass done (u212)" "r5 is in" | jq -sc '{ok: true, result: {deliveryId: "d3", messages: .}}' > "$T/batch.json"
  rm -rf "$T/sc"
  (cd "$T/p" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$WS" \
    COMMANDECK_SCRATCH="$T/sc" ORCA_TERMINAL_HANDLE=term_cos timeout 30 bash "$PL/scripts/orca-wait.sh" 2>&1)
}
OUT=$(wake NO-GO 1)
check "a NO-GO the merge check refuses: next is a fix round, never merge it" "1 0" \
  "$(grep -c 'next: fix round: r5 ended NO-GO' <<<"$OUT") $(grep -c 'merge it' <<<"$OUT")"
OUT=$(wake NO-GO 0)
check "a NO-GO the merge check passes: still a fix round, never merge it, no owner's-word line" "1 0 0" \
  "$(grep -c 'next: fix round: r5 ended NO-GO' <<<"$OUT") $(grep -c "owner's word" <<<"$OUT") $(grep -c 'merge it' <<<"$OUT")"
# Issue 225: a second NO-GO in a row on one finding class is a loop, not progress: the Builder fixes the design and main
# is asked nothing yet (only a third return reaches main, through the Builder's ask-main.sh question).
OUT=$(wake NO-GO 1 lost-reply)
check "two NO-GOs on one class: next is nothing for main, never merge and file, never an owner question" "1 0 0 0" \
  "$(grep -c 'next: nothing for main yet: the Builder fixes the class by design (two NO-GOs on lost-reply); a third return comes as its question' <<<"$OUT") $(grep -c 'merge and file' <<<"$OUT") $(grep -c 'next: fix round' <<<"$OUT") $(grep -c 'ask the owner' <<<"$OUT")"
OUT=$(wake GO 0)
check "a GO the merge check passes still prints merge it" "1 0" "$(grep -c 'next: merge it:' <<<"$OUT") $(grep -c 'fix round' <<<"$OUT")"
# Issue 223: a heads-up printed its whole body and other messages up to 60 lines, so one wake could fill main's
# context. The default wake is cut at 3,000 bytes, a heads-up is one line and a path, and next: lines are never cut.
HU=$(for i in $(seq 1 400); do printf 'claim line %03d of a long heads-up note, words words words\n' "$i"; done)
drain() { rm -rf "$T/sc"; (cd "$T/p" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/p" \
  COMMANDECK_WORKSPACES="$WS" COMMANDECK_SCRATCH="$T/sc" ORCA_TERMINAL_HANDLE=term_cos timeout 30 bash "$PL/scripts/orca-wait.sh" "$@" 2>&1); }
msg h1 term_w status "heads-up: a long claim" "$HU" | jq -sc '{ok: true, result: {deliveryId: "d4", messages: .}}' > "$T/batch.json"
OUT=$(drain)
check "a 20 KB heads-up prints its subject line and the file that holds it, under 3,000 bytes" "1 1 yes" \
  "$(grep -c '| heads-up: a long claim |' <<<"$OUT") $(grep -cF "$T/sc/main-watch/messages/h1.md" <<<"$OUT") $([ "$(printf '%s' "$OUT" | wc -c)" -lt 3000 ] && echo yes)"
check "the file holds the whole body" "$HU" "$(cat "$T/sc/main-watch/messages/h1.md")"
OUT=$(drain --full)
check "--full prints the heads-up whole" 400 "$(grep -c '^claim line' <<<"$OUT")"
{ msg h1 term_w status "heads-up: a long claim" "$HU"
  for i in $(seq 1 12); do msg "n$i" term_w question "q$i" "$(printf 'word %.0s' $(seq 1 120))"; done
  msg w1 term_u status "pass done (u212)" "r5 is in"; } | jq -sc '{ok: true, result: {deliveryId: "d5", messages: .}}' > "$T/batch.json"
OUT=$(drain); REST=$(sed -n 's/.*whole wake: \([^ ]*\)).*/\1/p' <<<"$OUT" | tail -1)
check "a long wake is cut, keeps its next: line, and names the file that holds the rest" "1 1 1" \
  "$(grep -c 'next: merge it:' <<<"$OUT") $(grep -c '^orca-wait: cut at 3,000 bytes' <<<"$OUT") $(grep -c '| pass done (u212) |' "$REST" 2>/dev/null)"
# Issue 306 R11: main-watch's gate ran --verify on this tip and kept its result; the wake reads it and never runs
# --verify again (the stub counts calls). A gate that queued the merge tells main it has nothing to do.
wake GO 0 >/dev/null; printf '#!/usr/bin/env bash\necho call >> "%s/vcalls"\nexit 0\n' "$T" > "$PL/scripts/builder-codex-pass.sh"
msg w2 term_u status "pass done (u212)" "r5 is in" | jq -sc '{ok: true, result: {deliveryId: "d8", messages: .}}' > "$T/batch.json"
# main-watch's record: the key (the tip and a checksum of the round files, paths.sh pp_gate_key), exit, rule, line.
rgate() { mkdir -p "$T/sc/main-watch"; printf '%s %s\n%s\n%s\n%s\n' "$(git -C "$U" rev-parse HEAD)" "$(cat "$U/.claude/briefs/u212"-r*-reports.md 2>/dev/null | cksum | tr ' ' :)" "$1" "$2" "$3" > "$T/sc/main-watch/gate-u212"; }
run() { (cd "$T/p" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$WS" \
  COMMANDECK_SCRATCH="$T/sc" ORCA_TERMINAL_HANDLE=term_cos timeout 30 bash "$PL/scripts/orca-wait.sh" "$@" 2>&1); }
rm -rf "$T/sc" "$T/vcalls"; rgate 0 "closing GO" "Builder proof: u212-r5-reports.md: the closing pass; rule: closing GO"; OUT=$(run)
check "a gate result kept for the tip: --verify is not run again, and main is told main-watch merges it" "0 1" \
  "$(cat "$T/vcalls" 2>/dev/null | wc -l | tr -d ' ') $(grep -c 'next: nothing for main yet: main-watch merges it' <<<"$OUT")"
# A result kept for the tip but an older set of round files is stale: a new pass on the same commit runs --verify again.
rm -rf "$T/sc" "$T/vcalls"; rgate 1 "" "no closing pass yet"; echo .claude/briefs/u212-r9-reports.md >> "$U/.git/info/exclude"
echo "Pass: final" > "$U/.claude/briefs/u212-r9-reports.md"; OUT=$(run)
rm -f "$U/.claude/briefs/u212-r9-reports.md"
check "a new round file on the same tip makes the kept result stale: --verify runs once" 1 "$(cat "$T/vcalls" 2>/dev/null | wc -l | tr -d ' ')"
rm -rf "$T/sc" "$T/vcalls"; rgate 1 "" "a P1 is open"; OUT=$(run)
check "a refusal kept for the tip is the reason main reads, with no --verify run" "0 1" \
  "$(cat "$T/vcalls" 2>/dev/null | wc -l | tr -d ' ') $(grep -c 'next: nothing for main yet: a P1 is open' <<<"$OUT")"
rm -rf "$T/sc" "$T/vcalls"; OUT=$(run)
check "with no kept result the wake runs --verify itself, once" 1 "$(cat "$T/vcalls" | wc -l | tr -d ' ')"
# Issue 253: routine items main-watch put in its digest are one count-and-path line when main next wakes, then not again.
rm -rf "$T/sc"; mkdir -p "$T/sc/main-watch"; printf '1 u1 merged\n2 heads-up repeated: x\n' > "$T/sc/main-watch/digest"
OUT=$(run); OUT2=$(run --run run_test)
check "the digest is one line with its count and path, and only new lines count next time" "1 0" \
  "$(grep -c "^digest: 2 routine items since the last wake (landed merges, repeated heads-ups): $T/sc/main-watch/digest$" <<<"$OUT") $(grep -c '^digest:' <<<"$OUT2")"
# Issue 305: a Builder's question that names the owner, or is a repeat-class stop-and-ask, goes on the owner's
# decision queue at once (no waitsOn); any other still waits on main. Main gets its line for both.
mkdir -p "$T/p/.claude/metrics"; : > "$T/p/.claude/metrics/decisions.jsonl"
{ msg o1 term_u question "question (u212)" "Stop and ask the owner: ship the old format or the new one?"
  msg o2 term_u question "question (u212)" "REPEAT CLASS: lost-reply (r4, r5); a class-level call is needed"
  msg o3 term_u question "question (u212)" "Which helper file should hold the parser?"; } | jq -sc '{ok: true, result: {deliveryId: "d9", messages: .}}' > "$T/batch.json"
rm -rf "$T/sc" "$T/vcalls"; OUT=$(run)
check "owner-bound questions carry no waitsOn, an ordinary one waits on main, and each gets main's line" "u212-o1:none u212-o2:none u212-o3:main 3" \
  "$(jq -r '"\(.id):\(.waitsOn // "none")"' "$T/p/.claude/metrics/decisions.jsonl" | sort | paste -sd' ' -) $(grep -c 'next: it waits for' <<<"$OUT")"
# Issue 321: the hooks send a question or refusal as a "turn complete: QUESTION|BLOCKED" message; it is a question like any
# other (the decision queue, main's line), while a marker echo is a finish and records no decision.
: > "$T/p/.claude/metrics/decisions.jsonl"
{ msg c1 term_u question "claude turn complete: QUESTION (u212)" "QUESTION: Owner, may I proceed without the required rollback?"
  msg c2 term_u question "codex turn complete: BLOCKED (u212)" "BLOCKED: access was refused."
  msg c3 term_u question "claude turn complete: VERDICT: GO (u212)" "VERDICT: GO"; } | jq -sc '{ok: true, result: {deliveryId: "d10", messages: .}}' > "$T/batch.json"
rm -rf "$T/sc" "$T/vcalls"; OUT=$(run)
check "a hook's QUESTION and BLOCKED messages go on the decision queue, with main's line; its verdict echo does not" "u212-c1:none u212-c2:main 2" \
  "$(jq -r '"\(.id):\(.waitsOn // "none")"' "$T/p/.claude/metrics/decisions.jsonl" | sort | paste -sd' ' -) $(grep -c 'next: it waits for' <<<"$OUT")"
# r1: the drain prints each message before it acknowledges it; the default wake must hand that print on at once.
# Two deliveries, the second's ack hangs: a call killed then has already printed both acknowledged messages.
msg k1 term_w question "first delivered" "one" | jq -sc '{ok: true, result: {deliveryId: "d6", messages: .}}' > "$T/k1.json"
msg k2 term_w question "second delivered" "two" | jq -sc '{ok: true, result: {deliveryId: "d7", messages: .}}' > "$T/k2.json"
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"orchestration check"*"--ack d6"*) cat "$T/k2.json" ;;
  *"orchestration check"*"--ack d7"*) sleep 8; echo '{"ok":true,"result":{"messages":[]}}' ;;
  *"orchestration check"*) cat "$T/k1.json" ;;
  *) echo '{"ok":true}' ;;
esac
EOF
rm -rf "$T/sc"
OUT=$(cd "$T/p" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$WS" \
  COMMANDECK_SCRATCH="$T/sc" ORCA_TERMINAL_HANDLE=term_cos timeout 4 bash "$PL/scripts/orca-wait.sh" 2>&1)
check "a wake killed while a later ack is pending has printed every message acknowledged so far" "1 1" \
  "$(grep -c '| first delivered |' <<<"$OUT") $(grep -c '| second delivered |' <<<"$OUT")"
# Issue 288: the plugin starts no driver, so a stray loop-u1 service hid the one copy of a seat verdict; and a merge's
# or a suite's detached exit note is sent from main's own handle, where the own-status rule hid it as main's note.
# Issue 318 removed that rule: a status note did not wake main, so it is shown as held, main's own included.
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"orchestration check"*"--ack"*) echo '{"ok":true,"result":{"messages":[]}}' ;;
  *"orchestration check"*) cat "$T/batch.json" ;;
  *) echo '{"ok":true,"result":{"terminals":[]}}' ;;
esac
EOF
printf '#!/usr/bin/env bash\nprintf "123\\t0\\tcom.commandeck.loop-u1\\n"\n' > "$T/bin/launchctl"; chmod +x "$T/bin/launchctl"
{ msg v1 term_drv status "seat certifier u1: GO" "report"
  msg x1 term_main question "merge-unit-local.sh u1: exit 1" "tail of the log"
  msg x2 term_main status "a note main sent by hand" "plain"; } | jq -sc '{ok: true, result: {deliveryId: "d8", messages: .}}' > "$T/batch.json"
rm -rf "$T/sc"
mdrain() { (cd "$T/p" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$WS" \
  COMMANDECK_HOST_OS=Darwin COMMANDECK_SCRATCH="$T/sc" ORCA_TERMINAL_HANDLE=term_main timeout 30 bash "$PL/scripts/orca-wait.sh" 2>&1); }
OUT=$(mdrain)
check "a seat verdict is shown while a live driver service names its unit" 1 "$(grep -c '| seat certifier u1: GO |' <<<"$OUT")"
check "a lone exit notice from main's own handle is shown, and main's hand-sent status note is shown too (held)" "1 1" \
  "$(grep -c '| merge-unit-local.sh u1: exit 1 |' <<<"$OUT") $(grep -c 'a note main sent by hand' <<<"$OUT")"
# Issue 318: a status note did not wake main, so it is shown after the wake's own lines, under one held-notes line,
# main's own notes included: otherwise a held note is never seen. A heartbeat is a liveness ping, shown nowhere.
{ msg y1 term_main status "main's own note" "progress"
  msg y2 term_w heartbeat "alive" "beat"
  msg y3 term_x status "merge still running" "progress"
  msg y4 term_x question "a Builder asks" "which file?"
  msg y5 term_x status "drive u9: FYI round started" "progress"; } | jq -sc '{ok: true, result: {deliveryId: "d9", messages: .}}' > "$T/batch.json"
rm -rf "$T/sc"; OUT=$(mdrain)
check "a status note, main's own and a driver FYI included, prints under held notes after the wake's own lines; a heartbeat prints nowhere" \
  "a Builder asks|held notes (did not wake you):|main's own note|merge still running|drive u9: FYI round started|0" \
  "$(grep -oE '^(term_[a-z]+ \| [^|]+ \||held notes.*)' <<<"$OUT" | sed -E 's/^term_[a-z]+ \| //; s/ \|$//' | paste -sd'|' -)|$(grep -c 'alive' <<<"$OUT")"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

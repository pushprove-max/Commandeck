#!/usr/bin/env bash
# A question main puts to the owner must land in the decisions ledger, or the
# owner's open asks vanish from every list that shows them. The hook builds
# each row's id with hooks/lib/decision-id.jq; when that file is missing jq
# fails, the hook records nothing and still exits 0, so only the ledger shows it.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
git init -q "$TMP/main"; mkdir -p "$TMP/main/.claude/metrics" "$TMP/home"
L=$TMP/main/.claude/metrics/decisions.jsonl; : > "$L"
. "$REAL/hooks/lib/ask-decoy.sh"
ask() { # header question -> the hook's exit code
  jq -cn --arg d "$ASK_DECOY" --arg h "$1" --arg q "$2" --arg cwd "$TMP/main" \
    '{cwd: $cwd, tool_name: "AskUserQuestion", tool_input: {questions: [{header: $h, question: $q,
      options: [{label: $d}, {label: "Ship it (Recommended)"}, {label: "Hold"}]}]}}' \
  | env -u CLAUDE_PROJECT_DIR -u COMMANDECK_REVIEWER HOME="$TMP/home" COMMANDECK_MAIN="$TMP/main" \
      COMMANDECK_HOOK_FIRE_LOG="$TMP/fire.jsonl" bash "$REAL/hooks/ask-records-decision.sh" >"$TMP/out" 2>"$TMP/err"; echo $?
}
DAY=$(date +%Y-%m-%d)
check "a first question is let through" 0 "$(ask 'Ship: Now?' 'Ship the release today?')"
check "it is recorded once" 1 "$(wc -l < "$L" | tr -d ' ')"
check "its id is the header slug plus the date" "ship-now-$DAY" "$(jq -r .id "$L")"
check "its default is the recommended option, unmarked" "Ship it" "$(jq -r .proposedDefault "$L")"
check "the same question again is blocked" 2 "$(ask 'Ship: Now?' 'Ship the release today?')"
check "and adds no row" 1 "$(wc -l < "$L" | tr -d ' ')"
check "a question with another header gets its own id" "0 deploy-window-$DAY" \
  "$(ask 'Deploy window' 'Which hour suits the database migration?') $(tail -1 "$L" | jq -r .id)"

# A re-ask that comes back reworded shows the owner the original question with
# an "ask" answer, and the fire log must say "ask": logged as "allow", the
# owner's prompt reads as a call that went through unseen.
env HOME="$TMP/home" COMMANDECK_MAIN="$TMP/main" bash "$REAL/scripts/decision.sh" \
  add "ship-now-$DAY" 'Ship the release today?' 'Ship it' test --reask 'the tests are green' >/dev/null 2>&1
check "a reworded re-ask is let through" 0 "$(ask 'Ship: Now?' 'Should we ship the release today?')"
# Claude Code 2.1.300 validates updatedInput: the rewrite carries the picker's
# own keys and changes only the question text.
check "it is answered ask, its input changed only in the question text" true \
  "$(jq --arg d "$ASK_DECOY" '.hookSpecificOutput | .permissionDecision == "ask" and .updatedInput == {questions: [{header: "Ship: Now?",
    question: "Ship the release today?", options: [{label: $d}, {label: "Ship it (Recommended)"}, {label: "Hold"}]}]}' "$TMP/out" 2>/dev/null)"
check "the fire log reads allow, block, allow, ask" "allow block allow ask" "$(jq -r .decision "$TMP/fire.jsonl" 2>/dev/null | paste -sd' ' -)"

dec() { env HOME="$TMP/home" COMMANDECK_MAIN="$TMP/main" bash "$REAL/scripts/decision.sh" "$@"; }
# the watcher marks a decision seen when it fires; each restart before the
# Chief of Staff wrote its own mark woke the pane again for the same question.
watch() { env HOME="$TMP/home" COMMANDECK_MAIN="$TMP/main" COMMANDECK_WATCH_ONCE=1 bash "$REAL/scripts/cos-watch-decisions.sh" 2>/dev/null | jq -r .id; echo "rc=${PIPESTATUS[0]}"; }
check "the watcher fires an open decision" "deploy-window-$DAY rc=0" "$(watch | grep -v ship-now | paste -sd' ' -)"
check "a restart does not fire it again" "rc=1" "$(watch | paste -sd' ' -)"
dec answer "deploy-window-$DAY" 'Noon' >/dev/null; dec reopen "deploy-window-$DAY" >/dev/null
check "a reopened decision fires again" "deploy-window-$DAY rc=0" "$(watch | paste -sd' ' -)"
# A fast machine (CI's Linux runner) asks, answers and reopens in one second: the
# reopen still needs a new askedAt, or the watcher's id@askedAt mark hides it and
# an answer that read the old snapshot closes the reopened ask. That askedAt must
# not be ahead of the clock either: the prompt hook answers only asks stamped no
# later than the prompt. The clock is frozen (epoch in $TMP/clock) and moves only
# when something sleeps; the hook's `date -u -d @<epoch>` reaches the real date.
mkdir "$TMP/bin"; date -u -d 2026-10-01T09:00:00Z +%s > "$TMP/clock"
printf '#!/bin/sh\ncase "$*" in "-u +"*) exec %q -u -d "@$(cat %q)" "$2" ;; +%%s) exec cat %q ;; esac\nexec %q "$@"\n' \
  "$(command -v date)" "$TMP/clock" "$TMP/clock" "$(command -v date)" > "$TMP/bin/date"
printf '#!/bin/sh\necho $(( $(cat %q) + 1 )) > %q\n' "$TMP/clock" "$TMP/clock" > "$TMP/bin/sleep"
chmod +x "$TMP/bin/date" "$TMP/bin/sleep"
fdec() { PATH="$TMP/bin:$PATH" dec "$@"; }
fprompt() { jq -cn --arg p "$1" --arg cwd "$TMP/main" '{hook_event_name: "UserPromptSubmit", session_id: "s1", cwd: $cwd, prompt: $p}' \
  | env -u CLAUDE_PROJECT_DIR -u COMMANDECK_REVIEWER PATH="$TMP/bin:$PATH" HOME="$TMP/home" COMMANDECK_MAIN="$TMP/main" \
      COMMANDECK_RULING_LOG="$TMP/rulings.jsonl" COMMANDECK_HOOK_FIRE_LOG="$TMP/fire.jsonl" bash "$REAL/hooks/ruling-log.sh" >/dev/null 2>&1; }
fdec add same-second 'Rotate the keys?' none main >/dev/null
check "the watcher fires a decision on a frozen clock" "same-second rc=0" "$(watch | paste -sd' ' -)"
fdec answer same-second Yes >/dev/null; fdec reopen same-second >/dev/null
check "a reopen in the ask's own second fires again" "same-second rc=0" "$(watch | paste -sd' ' -)"
check "and an answer that read the old snapshot refuses" 1 \
  "$(fdec answer same-second No --asked-at 2026-10-01T09:00:00Z >/dev/null 2>&1; echo $?)"
fprompt "same-second: yes"
check "the owner's reply right after the reopen closes it" "answered in chat" \
  "$(dec list | jq -r '.[] | select(.id == "same-second") | .answer // "open" | .[:16]')"
fdec add same-second 'Rotate the keys?' none main --reask 'the old keys leaked' >/dev/null
check "a re-ask in the answer's own second fires again" "same-second rc=0" "$(watch | paste -sd' ' -)"
# A Builder's question waits on main: the relay pane the watcher wakes would put it to the owner.
dec add u1-msg_q1 'Which fixture?' none 'u1 asks' --waits-on main >/dev/null
check "a Builder's question waiting on main never wakes the relay" "rc=1" "$(watch | paste -sd' ' -)"

# a wrongly recorded answer is replaced in one step, the old one kept.
dec answer "deploy-window-$DAY" 'Noon' >/dev/null
check "a second answer still refuses" 1 "$(dec answer "deploy-window-$DAY" 'Simplify' >/dev/null 2>&1; echo $?)"
check "--correct replaces it and keeps the old answer in history" "Simplify Noon" \
  "$(dec answer "deploy-window-$DAY" 'Simplify' --correct | jq -r '"\(.answer) \(.history[0].answer)"')"
check "the corrected ledger still reads" "Simplify" "$(dec list | jq -r --arg id "deploy-window-$DAY" '.[] | select(.id == $id) | .answer')"
check "--correct on an open decision refuses" 1 "$(dec answer "ship-now-$DAY" 'Hold' --correct >/dev/null 2>&1; echo $?)"

# A re-ask of a chat decision, or of an earlier day's, arms its picker: no
# header gives a chat id, or an earlier day's id, today, so the grant never
# matched and the re-asked picker stayed blocked.
answer_of() { dec list | jq -r --arg id "$1" '.[] | select(.id == $id) | .answer // "open"'; }
VQ="Keep the voice hook from logging PII?"
dec add voice-hook-pii "$VQ" none main >/dev/null
check "the open chat decision's picker is blocked" 2 "$(ask "Voice hook PII" "$VQ")"
dec add voice-hook-pii "$VQ" none main --reask "the hook now reads transcripts" >/dev/null
check "a re-ask grants nothing to a header that does not name it" 2 "$(ask "Voice" "$VQ")"
check "after a re-ask, the picker whose header names it goes out" 0 "$(ask "Voice hook PII" "$VQ")"
check "the chat row closes, pointing at the picker's row" "re-asked as voice-hook-pii-$DAY" "$(answer_of voice-hook-pii)"
check "and the picker's row is open, so the picker's answer closes it" "open" "$(answer_of "voice-hook-pii-$DAY")"
check "the same picker again is blocked" 2 "$(ask "Voice hook PII" "$VQ")"
PQ="Patch the build box kernel tonight?"
dec add patch-box-2026-10-01 "$PQ" none main >/dev/null
dec add patch-box-2026-10-01 "$PQ" none main --reask "the vendor shipped a fix" >/dev/null
check "an earlier day's re-asked picker goes out under today's header" 0 "$(ask "Patch box" "$PQ")"
check "and moves to today's id" "re-asked as patch-box-$DAY|open" "$(answer_of patch-box-2026-10-01)|$(answer_of "patch-box-$DAY")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

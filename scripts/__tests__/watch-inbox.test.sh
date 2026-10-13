#!/usr/bin/env bash
# Self-test for the Chief of Staff pane's watchers (cos-watch-*.sh, cos-tell.sh).
#
# The relay pane is deaf between turns: a watcher that exits is the only thing
# that wakes it. So each one must print exactly what the pane has to act on and
# nothing else -- main's own traffic printed here wakes the pane for nothing, and
# a missed message leaves the owner waiting on an answer nobody carried.
# They also may not touch anything outside the plugin's own state directory:
# another install's relay keeps its state under ~/.claude and must not be
# overwritten.
# Orca is a stub first on PATH; COMMANDECK_WATCH_ONCE=1 makes one poll and
# exits 1 when it found nothing.
set -u
SCRIPTS="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }

git init -q -b main "$TMP/proj"
mkdir -p "$TMP/home" "$TMP/ws/Chief-of-Staff" "$TMP/bin" "$TMP/proj/.claude/metrics" "$TMP/scratch"
# The inbox is the whole machine's: only the project's own run is relayed.
echo run_t > "$TMP/scratch/current-run"
cat > "$TMP/bin/orca-ide" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "orchestration inbox") cat "$BOX/inbox.json" ;;
  "orchestration run-list") echo '{"result":{"runs":[]}}' ;;  # Orca answers, and names no orchestrator
  "terminal list") cat "$BOX/terms.json" ;;
  "terminal send") printf '%s\n' "$*" >> "$BOX/sent"; echo '{"ok":true}' ;;
esac
STUB
chmod +x "$TMP/bin/orca-ide"
export BOX=$TMP HOME=$TMP/home COMMANDECK_MAIN=$TMP/proj COMMANDECK_WORKSPACES=$TMP/ws COMMANDECK_WATCH_ONCE=1 COMMANDECK_SCRATCH=$TMP/scratch
export PATH=$TMP/bin:$PATH
unset ORCA_TERMINAL_HANDLE COMMANDECK_DASHBOARD_DIR
STATE=$TMP/home/.commandeck/chief-of-staff
ME=term_cos
terms() { printf '{"result":{"terminals":[{"handle":"term_main","worktreePath":"%s","agentIdentity":"claude"}%s]}}\n' "$TMP/proj" "$1" > "$TMP/terms.json"; }
terms ",{\"handle\":\"$ME\",\"worktreePath\":\"$TMP/ws/Chief-of-Staff\",\"agentIdentity\":\"claude\"}"
# msgs <seq> <from> <type> <subject> ... -> the inbox
msgs() {
  local rows=()
  while [ $# -gt 0 ]; do
    rows+=("$(jq -cn --argjson s "$1" --arg f "$2" --arg t "$3" --arg sub "$4" \
      '{sequence:$s, run_id:"run_t", from_handle:$f, type:$t, subject:$sub, body:("body of " + $sub), created_at:"t"}')"); shift 4
  done
  printf '%s\n' "${rows[@]}" | jq -cs '{result:{messages:.}}' > "$TMP/inbox.json"
}
inbox() { bash "$SCRIPTS/cos-watch-inbox.sh" "$@" 2>/dev/null; echo "rc=$?"; }

# --- the inbox poller ----------------------------------------------------------
msgs 5 term_main status 'cos: old news'
check "a first poll replays nothing: it starts from the newest message" "rc=1" "$(inbox $ME)"
check "and records where it started, under the plugin's state directory" 5 "$(cat "$STATE/proj.inbox-seq" 2>/dev/null)"

msgs 5 term_main status 'cos: old news' 6 term_main status 'cos: ship it?'
OUT=$(inbox $ME)
check "a message addressed cos: wakes the pane" "rc=0" "$(tail -1 <<<"$OUT")"
check "with its subject and body" 1 "$(grep -c 'cos: ship it? | body of cos: ship it?' <<<"$OUT")"
check "and not the one already seen" 0 "$(grep -c 'old news' <<<"$OUT")"
check "the same inbox again wakes nobody" "rc=1" "$(inbox $ME)"

msgs 7 $ME status 'cos: my own note' 8 term_w worker_done 'cos: unit done' \
     9 term_main question 'main-watch: the owner is idle' 10 term_main question 'heads-up: chief of staff' \
     11 term_main status 'main: owner said yes' 12 term_w question 'unit 7 needs a decision'
check "its own sends, worker reports and main's own traffic wake nobody" "rc=1" "$(inbox $ME)"
check "and are not replayed later" 12 "$(cat "$STATE/proj.inbox-seq")"

msgs 13 term_main status 'For the owner: pick a ring' 14 term_main status 'Chief of Staff, one more' 15 term_main status 'Ada: lunch?'
OUT=$(inbox $ME)
check "a subject naming the owner or the Chief of Staff wakes it" 2 "$(grep -c 'body of' <<<"$OUT")"
check "an unconfigured name does not" 0 "$(grep -c 'Ada' <<<"$OUT")"
echo '{"chiefOfStaff": {"name": "Ada"}}' > "$TMP/proj/.claude/commandeck.json"
msgs 16 term_main status 'Ada: lunch?'
check "the configured name does" 1 "$(inbox $ME | grep -c 'Ada: lunch?')"

echo 'busy' > "$TMP/inbox.json"
check "an Orca that cannot answer wakes nobody" "rc=1" "$(inbox $ME)"
check "and loses no place" 16 "$(cat "$STATE/proj.inbox-seq")"

# No handle given: the pane is found by its worktree, never a saved handle.
msgs 17 $ME status 'cos: mine again' 18 term_main status 'cos: found you'
OUT=$(inbox)
check "with no handle the pane is found by worktree" "1 0" "$(grep -c 'found you' <<<"$OUT") $(grep -c 'mine again' <<<"$OUT")"

# --- decisions -------------------------------------------------------------------
jq -cn '{id:"push-now", askedAt:"t", question:"Push?", proposedDefault:"yes", source:"main", answeredAt:null, answer:null},
        {id:"told-one", askedAt:"t", question:"Told?", proposedDefault:"no", source:"main", answeredAt:null, answer:null},
        {id:"done-one", askedAt:"t", question:"Ring?", proposedDefault:"none", source:"main", answeredAt:"t", answer:"internal"}' \
  > "$TMP/proj/.claude/metrics/decisions.jsonl"
echo told-one@t > "$STATE/proj.decisions-seen"
OUT=$(bash "$SCRIPTS/cos-watch-decisions.sh" 2>/dev/null; echo "rc=$?")
check "an open decision the owner has not been asked wakes the pane" "push-now rc=0" "$(head -1 <<<"$OUT" | jq -r .id) $(tail -1 <<<"$OUT")"
check "an answered one and one already put to the owner do not" 1 "$(grep -c '"id"' <<<"$OUT")"
check "it carries the mark the pane records once the owner was asked" "push-now@t" "$(head -1 <<<"$OUT" | jq -r .seen)"
echo push-now@t >> "$STATE/proj.decisions-seen"
check "once it is marked seen nothing wakes" "rc=1" "$(bash "$SCRIPTS/cos-watch-decisions.sh" 2>/dev/null; echo "rc=$?")"
# A reopened decision (decision.sh reopen: the answer was not the owner's) is a
# new ask under the same id: the mark of the first ask must not silence it.
jq -cn '{id:"push-now", askedAt:"t2", question:"Push?", proposedDefault:"yes", source:"main", answeredAt:null, answer:null}' >> "$TMP/proj/.claude/metrics/decisions.jsonl"
OUT=$(bash "$SCRIPTS/cos-watch-decisions.sh" 2>/dev/null; echo "rc=$?")
check "a reopened decision wakes the pane again" "push-now@t2 rc=0" "$(head -1 <<<"$OUT" | jq -r .seen 2>/dev/null) $(tail -1 <<<"$OUT")"

# --- dashboard alerts and the usage limit ----------------------------------------
check "no dashboard data: both wait" "1 1" "$(bash "$SCRIPTS/cos-watch-alerts.sh" >/dev/null 2>&1; echo $?) $(bash "$SCRIPTS/cos-watch-limit.sh" >/dev/null 2>&1; echo $?)"
mkdir -p "$TMP/home/.commandeck/dashboard"
D=$TMP/home/.commandeck/dashboard/data.js
echo 'window.DATA = {"alerts":[{"id":"limit-claude-1791717824","text":"limit"},{"id":"disk-full-1791717824","text":"disk"}],"limit":{"usedPct":91.4}};' > "$D"
# An id ends with the time its condition began: the same id is the same episode.
echo limit-claude-1791717824 > "$STATE/proj.alerts-seen"
OUT=$(bash "$SCRIPTS/cos-watch-alerts.sh" 2>/dev/null; echo "rc=$?")
check "an alert the owner has not been told wakes the pane" "disk-full-1791717824 rc=0" "$(head -1 <<<"$OUT" | jq -r .id) $(tail -1 <<<"$OUT")"
check "one the owner was already told of does not" 0 "$(grep -c limit-claude <<<"$OUT")"
check "usage at the threshold wakes the pane" "7-day limit at 91% (threshold 90%)" "$(bash "$SCRIPTS/cos-watch-limit.sh" 2>/dev/null)"
check "usage under a raised threshold does not" 1 "$(bash "$SCRIPTS/cos-watch-limit.sh" 95 >/dev/null 2>&1; echo $?)"

# --- dictated text to the pane ---------------------------------------------------
check "the pane's handle is found by its worktree" "$ME" "$(bash "$SCRIPTS/cos-tell.sh" --handle 2>/dev/null)"
bash "$SCRIPTS/cos-tell.sh" hello there >/dev/null 2>&1
check "text is sent to that pane and entered" 1 "$(grep -c -- "--terminal $ME --text .*hello there --enter" "$TMP/sent" 2>/dev/null)"
terms ""
check "no relay pane: nothing is sent and the caller is told" "1 1" "$(bash "$SCRIPTS/cos-tell.sh" again >/dev/null 2>&1; echo $?) $(wc -l < "$TMP/sent" | tr -d ' ')"

check "nothing was written under ~/.claude" no "$([ -e "$TMP/home/.claude" ] && echo yes || echo no)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

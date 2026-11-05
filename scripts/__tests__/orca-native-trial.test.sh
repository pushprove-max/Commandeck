#!/usr/bin/env bash
# The Orca native trials (#584 wake, #585 send, #586 submit) leave one committed record, docs/orca-native-trial.json,
# and the removal cuts read it. A removal that rests on a wrong "pass" deletes a working path, so: only the exact
# lowercase string `pass` unlocks anything (absent, junk, "PASS " and a missing key all read `unrun`); a `pass` for the
# wake is refused while a relay poller still runs, because the poller would have woken the pane, not Orca; a `fail`
# keeps its reason and the old path; and the record in the tree never disagrees with the files it gates.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
# orca-ide stub: only the version is asked. pgrep stub: a poller runs when $T/pollers is non-empty.
printf '#!/usr/bin/env bash\necho "1.4.248"\n' > "$T/bin/orca-ide"
printf '#!/usr/bin/env bash\n[ -s "%s/pollers" ] && { cat "%s/pollers"; exit 0; }\nexit 1\n' "$T" "$T" > "$T/bin/pgrep"
chmod +x "$T/bin/orca-ide" "$T/bin/pgrep"
export PATH="$T/bin:$PATH" ONT_RECORD="$T/rec.json"
. "$REAL/scripts/orca-native-trial.sh"
HOST=$(uname -s)

rm -f "$ONT_RECORD"; : > "$T/pollers"
check "absent record reads as unrun" "unrun unrun unrun" "$(read_result wake) $(read_result submit) $(read_result send.claude.$HOST)"

for junk in '{"wake":' '{"wake":{"result":"PASS "}}' '{"wake":{"result":"Pass"}}' '{"wake":{"result":true}}' '{"wake":"pass"}' '{"submit":{"result":"pass"}}' ''; do
  printf '%s' "$junk" > "$ONT_RECORD"
  got="$(read_result wake)"
  [ "$junk" = '{"submit":{"result":"pass"}}' ] || check "junk record reads as unrun: [$junk]" unrun "$got"
done
printf '{"submit":{"result":"pass"}}' > "$ONT_RECORD"
check "junk record reads as unrun: a pass under another key does not unlock wake" "unrun pass" "$(read_result wake) $(read_result submit)"
printf '{"wake":{"result":"pass"}}' > "$ONT_RECORD"
check "an exact lowercase pass reads as pass" pass "$(read_result wake)"

rm -f "$ONT_RECORD"; echo "123 cos-watch-inbox" > "$T/pollers"
record_result wake pass "woke with no poller" >/dev/null 2>&1; rc=$?
check "pass refused with poller running: exit" 1 "$rc"
check "pass refused with poller running: wake stays unrun" unrun "$(read_result wake)"
check "pass refused with poller running: no record written" absent "$([ -e "$ONT_RECORD" ] && echo present || echo absent)"
: > "$T/pollers"
record_result wake pass "woke with no poller" >/dev/null 2>&1
check "pass is accepted once no poller runs" pass "$(read_result wake)"

rm -f "$ONT_RECORD"
record_result wake fail "no turn after the report" >/dev/null 2>&1
check "fail keeps why and old path: result" fail "$(read_result wake)"
check "fail keeps why and old path: why" "no turn after the report" "$(jq -r .wake.why "$ONT_RECORD")"
check "fail is not a pass for a removal gate" 1 "$(trial_unlocked wake >/dev/null 2>&1; echo $?)"
record_result submit bogus "x" >/dev/null 2>&1
check "a result outside pass and fail is refused" "1 unrun" "$? $(read_result submit)"

rm -f "$ONT_RECORD"
record_result "send.claude.$HOST" pass "reached a finished worker" handle >/dev/null 2>&1
record_result "send.claude.$HOST.closed" fail "reopened pane not found" >/dev/null 2>&1
check "send is keyed by agent and host: this host passes, codex and the closed case do not" \
  "pass unrun fail unrun" "$(read_result send.claude.$HOST) $(read_result send.codex.$HOST) $(read_result send.claude.$HOST.closed) $(read_result send.claude.Other)"
# The trial once wrote Orca's flag text (`--to handle`), which pp_send_form (paths.sh) never reads, so a proven
# send left every caller typing. The writer takes only the reader's two forms.
check "send entry keeps its form, the one pp_send_form reads, and another form is refused" "handle handle 1" \
  "$(jq -r ".send.claude[\"$HOST\"].form" "$ONT_RECORD") $(. "$REAL/scripts/paths.sh"; pp_send_form claude) $(record_result "send.codex.$HOST" pass x "--to handle" >/dev/null 2>&1; echo $?)"
check "record names the Orca version" "1.4.248" "$(jq -r .orca "$ONT_RECORD")"
check "record is written whole (valid JSON, no temp file left)" "ok 0" "$(jq -e . "$ONT_RECORD" >/dev/null && echo ok) $(ls "$T" | grep -c 'rec.json.')"

# The committed record starts with every trial unrun.
ONT_RECORD="$REAL/docs/orca-native-trial.json"
check "the committed record starts with every trial unrun" "unrun unrun unrun" "$(read_result wake) $(read_result submit) $(read_result send.claude.$HOST)"

# Consistency: the files a removal deletes exist exactly while the record is not pass. Run on the committed record,
# which is what the removal cuts change in the same commit as the deletion.
names='await-agents\.sh|watch-agents\.sh'
if trial_unlocked wake; then
  gone=1; if [ -e "$REAL/scripts/await-agents.sh" ] || [ -e "$REAL/scripts/watch-agents.sh" ]; then gone=0; fi
  stray=$(cd "$REAL" && grep -rlE "$names" scripts hooks docs --exclude=orca-native-trial.sh --exclude=orca-native-trial.test.sh --exclude=orca-native-trial.json --exclude=troubleshooting.md 2>/dev/null | wc -l | tr -d ' ')
  check "wake record gates wait-loop removal" "1 0" "$gone $stray"
else
  check "wake record gates wait-loop removal" "kept kept" "$([ -e "$REAL/scripts/await-agents.sh" ] && echo kept) $([ -e "$REAL/scripts/watch-agents.sh" ] && echo kept)"
fi
# Old send site: answer-worker.sh types the answer; a pass for any agent on this host means pp_follow_up exists.
if trial_unlocked "send.claude.$HOST" || trial_unlocked "send.codex.$HOST"; then
  check "send record gates terminal-send removal" 1 "$(grep -c '^pp_follow_up()' "$REAL/scripts/paths.sh")"
else
  check "send record gates terminal-send removal" kept "$(grep -q 'terminal send --terminal "\$H" --text "\$MSG"' "$REAL/scripts/answer-worker.sh" && echo kept)"
fi
# Wake text for the submit trial: main-watch keeps its wake-typing retry (DG3) while submit is not pass; the gate is
# the record, so check it opens only on an exact pass.
ONT_RECORD=$T/s.json; rm -f "$ONT_RECORD"
check "submit record gates wake-text removal" "locked locked open" \
  "$(trial_unlocked submit && echo open || echo locked) $(record_result submit fail x >/dev/null 2>&1; trial_unlocked submit && echo open || echo locked) $(record_result submit pass x >/dev/null 2>&1; trial_unlocked submit && echo open || echo locked)"
check "submit record gates wake-text removal: the typed-wake site stays until then" kept "$(grep -q 'WAKE_TRIES' "$REAL/scripts/main-watch.sh" && echo kept)"

# an accepted send is not a delivery (pass 1): the send trial recorded pass from the send's exit alone, and that pass
# unlocks removing the terminal-send fallback. Orca here settles the worker and accepts the send; the pane shows the
# follow-up's word $T/seen times (1: typed but never answered; 2: typed and answered).
mkdir -p "$T/bin3"; cat > "$T/bin3/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "orchestration worker-start") echo '{"result":{"dispatchId":"d1","handle":"term_w"}}' ;;
  "orchestration worker-show") echo '{"result":{"status":"settled"}}' ;;
  "orchestration send") while [ \$# -gt 0 ]; do [ "\$1" = --body ] && grep -o 'ack-[0-9]*' <<<"\$2" > "$T/tag"; shift; done; echo '{"ok":true}' ;;
  "terminal read") for _ in \$(seq "\$(cat "$T/seen")"); do printf '%s ' "\$(cat "$T/tag")"; done | jq -Rs '{result: {terminal: {text: .}}}' ;;
esac
EOF
chmod +x "$T/bin3/orca-ide"
sendrun() { echo "$1" > "$T/seen"; ONT_RECORD=$T/send.json; rm -f "$ONT_RECORD"
  ( PATH="$T/bin3:$PATH" ONT_TRIES=2 ONT_SLEEP=0 trial_send claude >/dev/null 2>&1 ); read_result "send.claude.$HOST"; }
check "an accepted send with no answering turn is no pass" "fail pass" "$(sendrun 1) $(sendrun 2)"

# `send <agent> closed` once said NOT BUILT, so no closed-send pass could ever be recorded and pp_follow_up's closed
# route (DG8) stayed shut. The trial opens a seat-shaped pane in its worktree, settles and closes it, then reaches it
# through pp_follow_up by its task's dispatch. Orca here: $T/list5 lists panes (handle worktree); terminal create adds
# term_old, close drops it, a send to dispatch:d_c adds term_new while $T/reopen exists, and term_new's text holds the
# follow-up's word $T/seen5 times. orca-task-create.sh and dispatch-task.sh are stand-ins under $T/root; pp_task_close
# is stubbed (its settle checks have their own tests). Pass needs the reopened pane listed, named by the record, and
# the word twice; the result is the closed key only.
WS=$T/ws; WTD=$WS/u; B5=$T/bin5; R=$T/root; mkdir -p "$WTD" "$B5" "$R/scripts" "$T/sc" "$T/home"; git -C "$WTD" init -q
WTD=$(cd "$WTD" && pwd -P)
printf '#!/usr/bin/env bash\necho task_c\n' > "$R/scripts/orca-task-create.sh"; printf '#!/usr/bin/env bash\nexit 0\n' > "$R/scripts/dispatch-task.sh"
cat > "$B5/orca-ide" <<EOF
#!/usr/bin/env bash
a="\$1 \$2"; while [ \$# -gt 0 ]; do case \$1 in --terminal) h=\$2 ;; --to) to=\$2 ;; --body) b=\$2 ;; esac; shift; done
case \$a in
  "terminal create") echo "term_old $WTD" >> "$T/list5"; echo '{"result":{"terminal":{"handle":"term_old"}}}' ;;
  "terminal close") grep -v "^\$h " "$T/list5" > "$T/list5.n"; mv "$T/list5.n" "$T/list5"; echo '{"ok":true}' ;;
  "terminal list") jq -Rn '{result: {terminals: [inputs | split(" ") | {handle: .[0], worktreePath: .[1]}]}}' < "$T/list5" ;;
  "terminal read") n=0; [ "\$h" = term_new ] && [ -e "$T/tag5" ] && n=\$(cat "$T/seen5")
    for _ in \$(seq "\$n"); do printf '%s ' "\$(cat "$T/tag5")"; done | jq -Rs '{result: {text: .}}' ;;
  "orchestration dispatch-show") echo '{"result":{"dispatch":{"id":"d_c"}}}' ;;
  "orchestration worker-show") echo '{"result":{"status":"settled"}}' ;;
  "orchestration send") echo "\$to" >> "$T/sends5"; grep -o 'ack-[0-9]*' <<<"\$b" > "$T/tag5"
    [ "\$to" != dispatch:d_c ] || [ ! -e "$T/reopen" ] || echo "term_new $WTD" >> "$T/list5"; echo '{"ok":true}' ;;
  *) echo '{"ok":true}' ;;
esac
EOF
chmod +x "$B5/orca-ide"
closedrun() { echo "$1" > "$T/seen5"; : > "$T/list5"; : > "$T/sends5"; rm -f "$T/tag5"; ONT_RECORD=$T/closed.json; rm -f "$ONT_RECORD"
  ( cd "$WTD" && export PATH="$B5:$PATH" HOME="$T/home" COMMANDECK_SCRATCH="$T/sc" COMMANDECK_WORKSPACES="$WS" ONT_TRIES=2 ONT_SLEEP=0
    ONT_ROOT=$R; ont_load() { . "$REAL/scripts/paths.sh"; pp_task_close() { :; }; }
    trial_send claude closed >/dev/null 2>&1 )
  printf '%s:%s:%s:%s' "$(read_result "send.claude.$HOST.closed")" "$(read_result "send.claude.$HOST")" "$(grep -c '^dispatch:d_c$' "$T/sends5")" "$(ls "$T/sc" | grep -c '^seat-')"; }
touch "$T/reopen"; GOT="$(closedrun 2) $(closedrun 1)"; rm -f "$T/reopen"; GOT+=" $(closedrun 2)"
check "the closed send trial reopens the pane by its dispatch and records its own key" \
  "pass:unrun:1:0 fail:unrun:1:0 fail:unrun:1:0" "$GOT"

echo "orca-native-trial: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

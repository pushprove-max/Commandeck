#!/usr/bin/env bash
# Part D's message cuts: main hears a thing once. Heads-up notes go out as one digest per window (a repeat of a held
# note is not a second note, a digest Orca refused is retried), a finish the seat already reported in the run inbox
# posts nothing, a stall or a wait posts once however many ticks see it, and a finish seat.sh collect already sent
# (its delivery receipt) is handled, not posted again. An unreadable inbox still posts: a duplicate, never silence.
set -euo pipefail
. "$(dirname "$0")/fixtures/main-watch-setup.sh"
tick 5000; rm -f "$S"/seat-*.txt; sed -i 's/ .*/ completed/' "$F/tasks"; : > "$T/sends"
ST=$S/main-watch
export COMMANDECK_MAIN_WATCH_HU_DIGEST_S=1800
mkdir -p "$T/home/.claude/plugins/store" "$T/home/.claude/projects/p"
offer() { # <name> <shownAt s>: the store shows one offer, from a session that ran in this checkout
  jq -nc --arg id "sess-$1" --argjson at "$2" --arg l "LINE-$1" '{sessions: [{id: $id, view: {kind: "offer", shownAt: ($at * 1000), line: $l, explanation: "why"}}]}' \
    > "$T/home/.claude/plugins/store/cc-plugin-you-should-know_builtin-t.json"
  jq -nc --arg c "$REPO" '{cwd: $c}' > "$T/home/.claude/projects/p/sess-$1.jsonl"; }

# Heads-up digest: the first note goes at once; a second inside the window waits for the next digest.
N=70000; offer a $N; tick $N
[ "$(posts LINE-a)" = 1 ] || fail "digest: the first heads-up note was not posted"
offer b $((N + 60)); tick $((N + 60)); tick $((N + 600))
[ "$(posts LINE-b)" = 0 ] || fail "digest: a note captured inside the window was posted before it closed"
# The same session showing the same text again while it is held is the same note: one post, not two.
offer b $((N + 900)); tick $((N + 900))
tick $((N + 1800))
[ "$(posts LINE-b)" = 1 ] || fail "digest: the held note was not posted once the window closed ($(posts LINE-b) posts)"
tick $((N + 3700))
[ "$(posts LINE-b)" = 1 ] || fail "digest: a note repeating a held note was posted again ($(posts LINE-b) posts)"
# A digest Orca refused is retried on the next tick, not held for another window.
offer c $((N + 4000)); touch "$F/refuse-sends"; tick $((N + 5600)); tick $((N + 5660))
rm -f "$F/refuse-sends"; tick $((N + 5720))
[ "$(posts LINE-c)" = 3 ] || fail "digest: a refused digest was not tried on each tick until Orca took it ($(posts LINE-c) sends, want 3)"
tick $((N + 5780))
[ "$(posts LINE-c)" = 3 ] || fail "digest: an accepted digest was sent again on the next tick"
rm -f "$T/home/.claude/plugins/store/"*.json

# A wait (a state that is neither working nor done) is posted once, however many ticks see it.
: > "$T/sends"; W=80000
mkdir -p "$T/ws/uw"; printf 'handle=term_uw\ntask=task_uw\nrole=builder\nunit=uw\nlaunched=%s\n' $((W - 3000)) > "$S/seat-uw-builder.txt"; echo "task_uw running" >> "$F/tasks"
state term_uw waiting; tick $W; tick $((W + 130)); tick $((W + 200)); tick $((W + 1000))
[ "$(posts 'stalled in Orca state')" = 1 ] || fail "wait: a seat in one wait state was posted $(posts 'stalled in Orca state') times over four ticks"
rm -f "$S/seat-uw-builder.txt"

# A seat that finished and whose worker_done is in the run inbox has reported: nothing is posted for it.
wd() { jq -nc --arg f "$1" --argjson at "$2" '{to_handle: "run:run_test", from_handle: $f, read: 0, type: "worker_done", subject: "done", created_at: ($at | todate)}'; }
finish() { # <unit> <task> <epoch> <inbox: yes|none|bad> <prompt s> -- a seat working at <epoch> - 100 and done at <epoch>
  mkdir -p "$T/ws/$1"; printf 'handle=term_%s\ntask=%s\nrole=plan-author\nunit=%s\nlaunched=%s\nsession=sid-%s\n' "$1" "$2" "$1" $(($3 - 1400)) "$1" "$1" > "$S/seat-$1-plan-author.txt"
  [ "$2" = none ] || echo "$2 running" >> "$F/tasks"
  echo $(($3 - 1200)) > "$F/prompt-term_$1"; echo PLAN-DONE > "$F/verdict-term_$1"
  state term_$1 working; tick $(($3 - 100))
  case $4 in yes) wd "term_$1" $(($3 - 50)) | jq -sc '{ok: true, result: {messages: .}}' > "$F/inbox" ;; bad) echo 'not json' > "$F/inbox" ;; *) rm -f "$F/inbox" ;; esac
  state term_$1 done; tick "$3"; }
: > "$T/sends"; E=90000
finish ur1 task_ur1 $E yes
[ "$(posts 'seat plan-author on ur1')" = 0 ] || fail "reported: a finish whose worker_done is in the inbox was posted"
# The seat's earlier report does not silence a later prompt: the worker_done must be newer than the latest prompt.
echo $((E + 40)) > "$F/prompt-term_ur1"; rm -f "$S/main-watch/item-seat-term_ur1-task_ur1" "$ST/kind-seat-term_ur1-task_ur1"
: > "$T/sends"; finish ur2 task_ur2 $((E + 2000)) none
[ "$(posts 'seat plan-author on ur2')" = 1 ] || fail "reported: a finish with no worker_done in the inbox was not posted"
: > "$T/sends"; finish ur3 task_ur3 $((E + 4000)) bad
[ "$(posts 'seat plan-author on ur3')" = 1 ] || fail "reported: a finish the unreadable inbox could not vouch for was not posted (silence)"

# A collect landing between the queue and the flush: its delivery receipt names this seat's log at its size, so the
# finish is handled, not posted a second time.
: > "$T/sends"; E=$((E + 6000)); u=ud1
slug=$(printf '%s' "$T/ws/$u" | sed 's/[^a-zA-Z0-9]/-/g')
mkdir -p "$T/home/.claude/projects/$slug"; log=$T/home/.claude/projects/$slug/sid-$u.jsonl; echo '{"type":"user"}' > "$log"
mkdir -p "$T/ws/$u"; printf 'handle=term_%s\ntask=task_%s\nrole=plan-author\nunit=%s\nlaunched=%s\nsession=sid-%s\n' $u $u $u $((E - 1400)) $u > "$S/seat-$u-plan-author.txt"
echo "task_$u running" >> "$F/tasks"; echo PLAN-DONE > "$F/verdict-term_$u"; rm -f "$F/inbox"
state term_$u working; tick $((E - 100)); state term_$u done
printf '%s\n%s\n' "$log" "$(stat -c %s "$log")" > "$ST/delivered-seat-term_$u-task_$u"
tick "$E"
[ "$(posts "seat plan-author on $u")" = 0 ] || fail "receipt: a finish collect already delivered was posted again"
grep -qx handled "$ST/item-seat-term_$u-task_$u" || fail "receipt: the delivered finish was not marked handled ($(cat "$ST/item-seat-term_$u-task_$u" 2>/dev/null))"
# The same finish with the log grown past the receipt (a later turn) is posted.
u=ud2; E=$((E + 3000)); slug=$(printf '%s' "$T/ws/$u" | sed 's/[^a-zA-Z0-9]/-/g')
mkdir -p "$T/home/.claude/projects/$slug" "$T/ws/$u"; log=$T/home/.claude/projects/$slug/sid-$u.jsonl; echo '{"type":"user"}' > "$log"
printf 'handle=term_%s\ntask=task_%s\nrole=plan-author\nunit=%s\nlaunched=%s\nsession=sid-%s\n' $u $u $u $((E - 1400)) $u > "$S/seat-$u-plan-author.txt"
echo "task_$u running" >> "$F/tasks"; echo PLAN-DONE > "$F/verdict-term_$u"
state term_$u working; tick $((E - 100)); state term_$u done
printf '%s\n%s\n' "$log" "$(stat -c %s "$log")" > "$ST/delivered-seat-term_$u-task_$u"; echo '{"type":"assistant"}' >> "$log"
tick "$E"
[ "$(posts "seat plan-author on $u")" = 1 ] || fail "receipt: a finish with a turn past the receipt was not posted"

# A minted task whose send Orca refused is closed once the seat reports: no stray open task is left behind.
: > "$T/sends"; : > "$T/updates"; E=$((E + 3000)); u=um1
mkdir -p "$T/ws/$u"; printf 'handle=term_%s\ntask=none\nrole=plan-author\nunit=%s\nlaunched=%s\n' $u $u $((E - 1400)) > "$S/seat-$u-plan-author.txt"
echo PLAN-DONE > "$F/verdict-term_$u"; echo $((E - 1200)) > "$F/prompt-term_$u"; rm -f "$F/inbox"
state term_$u working; tick $((E - 100)); state term_$u done; touch "$F/refuse-sends"; tick "$E"; rm -f "$F/refuse-sends"
minted=$(sed -n 's/^task=//p' "$ST/item-seat-term_$u-none")
[ -n "$minted" ] && [ "$minted" != none ] || fail "minted: the refused send left no minted task to close ($(cat "$ST/item-seat-term_$u-none" 2>/dev/null))"
wd "term_$u" $((E + 20)) | jq -sc '{ok: true, result: {messages: .}}' > "$F/inbox"
tick $((E + 60)); tick $((E + 120))
[ "$(grep -c -- "--id $minted --status completed" "$T/updates")" = 1 ] || fail "minted: the task $minted was not closed exactly once once the seat reported ($(cat "$T/updates"))"
grep -qx handled "$ST/item-seat-term_$u-none" || fail "minted: the item was not marked handled"

echo "PASS main-watch-message-cuts.test.sh"

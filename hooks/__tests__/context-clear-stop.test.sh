#!/usr/bin/env bash
# Self-test for context-clear-stop.sh's detached restart launch. Run directly.
#
# macOS has no setsid. The hook used to launch the helper with a bare setsid
# into /dev/null and mark the checkpoint restarted BEFORE the launch, so on the
# Mac the helper never ran and every later stop gave up as "already restarted".
# Pinned here: on a PATH without setsid the helper still starts, and a launch
# that never starts leaves no marker, so the next stop retries.
set -u

ROOT=$(git rev-parse --show-toplevel)
HOOK="$ROOT/hooks/context-clear-stop.sh"
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }

BOX=$(mktemp -d); trap 'rm -rf "$BOX"' EXIT
mkdir -p "$BOX/bin" "$BOX/home/.claude/checkpoints" "$BOX/repo"
git -C "$BOX/repo" init -q
PSLUG=$(printf '%s' "$(git -C "$BOX/repo" rev-parse --show-toplevel)" | tr -c 'A-Za-z0-9' '-')  # the marker is per repo

# A PATH holding only what the hook and helper call, so setsid is absent on
# every host, the PC included.
for t in bash sh env jq git date stat dirname basename cat ps grep perl touch printf rm rmdir sleep head tr cut sed awk mkdir ls wc tail sort python3 cksum; do
  p=$(command -v "$t") && ln -s "$p" "$BOX/bin/$t"
done
[ ! -e "$BOX/bin/setsid" ] || { echo "FAIL setup: setsid leaked onto the test PATH"; exit 1; }

cat > "$BOX/bin/orca-ide" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
case "$1 $2" in
  "terminal create") echo '{"result":{"terminal":{"handle":"new-pane"}}}' ;;
  "worktree ps") echo '{"result":{"worktrees":[]}}' ;;
  "terminal list") echo '{"result":{"terminals":[]}}' ;;
  "worktree list") echo '{"result":{"worktrees":[]}}' ;;
  *) echo '{"ok":true}' ;;
esac
STUB
chmod +x "$BOX/bin/orca-ide"

CPD="$BOX/home/.claude/checkpoints"
run_hook() { # $1 = helper path override (empty = the real helper)
  rm -f "$CPD"/sid.* "$BOX/calls"; : > "$BOX/calls"
  echo '# checkpoint' > "$CPD/sid.md"; touch "$CPD/sid.handoff"
  echo '{}' > "$BOX/transcript.jsonl"
  stop_hook "$@"
}
stop_hook() { # one stop of the same pane, the checkpoint files left as they are
  (cd "$BOX/repo" && printf '{"session_id":"sid","transcript_path":"%s","stop_hook_active":false}' "$BOX/transcript.jsonl" \
    | env -i PATH="$BOX/bin" HOME="$BOX/home" CALLS="$BOX/calls" ORCA_TERMINAL_HANDLE=old-pane \
        COMMANDECK_RESTART_SETTLE_S=0 COMMANDECK_RESTART_TUI_FALLBACK_S=0 \
        COMMANDECK_SCRATCH="$BOX" COMMANDECK_DRIVERS=none.service \
        ${1:+COMMANDECK_RESTART_HELPER="$1"} ${2:+COMMANDECK_PARENT_ARGS="$2"} bash "$HOOK" >/dev/null 2>&1)
}
# Up to 30 s, returning as soon as the condition holds: a loaded chain host took
# longer than the old 5 s to start the detached helper, and a timeout is its own
# failure rather than an empty read further down.
wait_for() { for _ in $(seq 1 300); do eval "$1" && return 0; sleep 0.1; done; FAIL=$((FAIL+1)); echo "FAIL timed out waiting for: $1"; return 1; }
# The helper's LAST call. A case waits for it before the next case starts: a
# helper still running removes the next case's .handoff trigger (it spends the
# handoff once its pane is prompted), and the next stop then launches nothing.
INFLIGHT="$CPD/restart-inflight.old-pane"
helper_done='grep -q "^terminal close --terminal old-pane" "$BOX/calls" && [ ! -e "$INFLIGHT" ]'

run_hook ""
wait_for "$helper_done"
check "without setsid the detached helper still runs and opens a new pane" "yes" \
  "$(grep -q '^terminal create' "$BOX/calls" && echo yes || echo no)"
check "a started helper leaves the restarted marker" "yes" \
  "$([ -e "$CPD/sid.md.restarted" ] && echo yes || echo no)"

run_hook "$BOX/no-such-helper.sh"
sleep 1
check "a launch that never starts leaves no restarted marker" "no" \
  "$([ -e "$CPD/sid.md.restarted" ] && echo yes || echo no)"
check "a failed launch is logged, not sent to /dev/null" "yes" \
  "$(grep -q 'no-such-helper' "$CPD/clear-hook.log" && echo yes || echo no)"

# 2026-09-28: main relaunched after a crash ran `claude ... --resume <sid>`, the
# restart replayed it, and the "fresh" pane reopened the same 370K session.
run_hook "" "claude --dangerously-skip-permissions --resume 00000000-0000-4000-8000-000000000001"
wait_for "$helper_done"
check "a resumed main restarts WITHOUT --resume" "claude --dangerously-skip-permissions" \
  "$(sed -n 's/^terminal create .*--command COMMANDECK_RESUME_TOKEN=[0-9-]* \(.*\) --json$/\1/p' "$BOX/calls" | head -1)"
run_hook "" "claude --continue --dangerously-skip-permissions"
wait_for "$helper_done"
check "a continued main restarts WITHOUT --continue" "claude --dangerously-skip-permissions" \
  "$(sed -n 's/^terminal create .*--command COMMANDECK_RESUME_TOKEN=[0-9-]* \(.*\) --json$/\1/p' "$BOX/calls" | head -1)"
# ps hands the arguments back as one flat line, their quoting gone, and the
# restart types that line into a shell. Text that a shell would act on is never
# replayed, and a command that cannot be rebuilt restarts with permission
# checks ON: the fallback used to switch them off.
restarted_as() { sed -n 's/^terminal create .*--command COMMANDECK_RESUME_TOKEN=[0-9-]* \(.*\) --json$/\1/p' "$BOX/calls" | head -1; }
run_hook "" 'claude --append-system-prompt $(touch /tmp/pwned); echo x'
wait_for "$helper_done"
check "arguments a shell would execute are not replayed" "claude" "$(restarted_as)"
run_hook "" "/opt/homebrew/bin/claude --model opus"
wait_for "$helper_done"
check "a claude started by absolute path keeps its arguments" "claude --model opus" "$(restarted_as)"
run_hook "" "node /usr/lib/node_modules/cli.js --model opus"
wait_for "$helper_done"
check "a command that cannot be rebuilt restarts with permission checks on" "claude" "$(restarted_as)"
# --resume and -r are valid with no value (they open a session picker), and a
# picker in the fresh pane never reaches the resume prompt. The flag after a
# bare one is a flag, not the session id.
run_hook "" "claude --resume"
wait_for "$helper_done"
check "a bare --resume is not replayed" "claude" "$(restarted_as)"
run_hook "" "claude -r --model opus"
wait_for "$helper_done"
check "a bare -r goes and the flag after it stays" "claude --model opus" "$(restarted_as)"
run_hook "" "claude --resume abc-123 --continue --fork-session --model opus"
wait_for "$helper_done"
check "resume flags in a row all go" "claude --model opus" "$(restarted_as)"

# Each restart opened TWO mains about 10 s apart (2026-10-12, twice). The
# helper needs 12 s or more, and a second stop inside that window, with the
# checkpoint edited since the first, is past the checksum marker. So one restart
# is in flight per pane. This helper marks the checkpoint as the real one does,
# then holds on until the case lets it end with the exit status it is given.
cat > "$BOX/slow-helper.sh" <<STUB
echo launched >> "$BOX/launches"
cksum < "\$2" > "\$2.restarted"
until [ -e "$BOX/release" ]; do sleep 0.1; done
exit "\$(cat "$BOX/release")"
STUB
launches() { grep -c launched "$BOX/launches" 2>/dev/null; }
helper_ends() { echo "$1" > "$BOX/release"; wait_for '[ ! -e "$INFLIGHT" ]'; rm -f "$BOX/release"; }
run_hook "$BOX/slow-helper.sh"
wait_for '[ "$(launches)" = 1 ]'
echo '# checkpoint, edited after the first stop' > "$CPD/sid.md"
stop_hook "$BOX/slow-helper.sh"
sleep 1
check "a second stop while the restart is in flight launches no second helper, the checkpoint edited or not" 1 "$(launches)"
# A helper that fails (no pane created, prompt refused) clears its marker; the next stop must still retry.
helper_ends 1; rm -f "$CPD/sid.md.restarted"
stop_hook "$BOX/slow-helper.sh"
wait_for '[ "$(launches)" = 2 ]'
check "a restart that failed is retried by the next stop" 2 "$(launches)"
helper_ends 0
# This stays: the lock is for a restart in flight, not for the pane's whole life.
echo '# a new checkpoint, written after the restart finished' > "$CPD/sid.md"
stop_hook "$BOX/slow-helper.sh"
wait_for '[ "$(launches)" = 3 ]'
check "a new checkpoint write after a finished restart still restarts" 3 "$(launches)"
helper_ends 0
# A helper killed outright never frees its lock; it runs for under five minutes.
mkdir "$INFLIGHT"; perl -e '$t = time - 700; utime($t, $t, @ARGV)' "$INFLIGHT"
echo '# one more checkpoint' > "$CPD/sid.md"
stop_hook "$BOX/slow-helper.sh"
wait_for '[ "$(launches)" = 4 ]'
check "a lock left by a helper that was killed is taken over after ten minutes" 4 "$(launches)"
helper_ends 0

# Carry-over: a resumed main's next checkpoint must keep, or explicitly
# close, every open item of the checkpoint it resumed from. A restart that
# silently drops one loses that work for good, so it is refused BEFORE anything
# is published or launched, on every stop in the chain and on both triggers.
cat > "$BOX/stub-helper.sh" <<STUB
#!/usr/bin/env bash
touch "$BOX/launched"
STUB
cat > "$BOX/base.md" <<'MD'
# Checkpoint old -- 2026-10-03 09:00 ET

## Waiting on
- VERDICT: GO from term_rev1 -> run merge-unit-local.sh alpha

## Rulings this session not yet in memory or a rule file (list only what could not be saved)
- The owner: keep the 0.70 auto-tuning bar for
  widget sorting until the fix lands

## Queue (in order)
1. unit-gamma, blocked on the alpha merge

## Todo list (the owner's on-screen checklist; the resumed main rebuilds it first)
- [x] finished step one
- [>] rebase delta onto main
- [ ] push after certification

## Gotchas learned this session
- none
MD
W='VERDICT: GO from term_rev1 -> run merge-unit-local.sh alpha'
R='The owner: keep the 0.70 auto-tuning bar for widget sorting until the fix lands'
Q='unit-gamma, blocked on the alpha merge'
T1='rebase delta onto main'
T2='push after certification'
carry() { # new checkpoint file [stop_hook_active] [line|handoff] -> blocked | published | neither
  rm -f "$CPD"/sid.* "$CPD/resume-pending.$PSLUG" "$BOX/launched"
  cp "${BASE:-$BOX/base.md}" "$CPD/old.md"; cp "$1" "$CPD/sid.md"
  [ "${ANC-x}" = none ] || echo "${ANC:-$CPD/old.md}" > "$CPD/sid.resumed-from"
  if [ "${3:-handoff}" = line ]; then
    printf '%s\n' '{"message":{"usage":{"cache_read_input_tokens":500,"input_tokens":1}}}' > "$BOX/transcript.jsonl"
  else
    echo '{}' > "$BOX/transcript.jsonl"; touch "$CPD/sid.handoff"
  fi
  (cd "$BOX/repo" && printf '{"session_id":"sid","transcript_path":"%s","stop_hook_active":%s}' "$BOX/transcript.jsonl" "${2:-false}" \
    | env -i PATH="$BOX/bin" HOME="$BOX/home" CALLS="$BOX/calls" ORCA_TERMINAL_HANDLE=old-pane \
        COMMANDECK_CLEAR_LINE="$([ "${3:-}" = line ] && echo 10 || echo 999999999)" \
        COMMANDECK_RESTART_HELPER="$BOX/stub-helper.sh" bash "$HOOK" > "$BOX/carry.out" 2>/dev/null)
  if jq -e '.decision == "block"' "$BOX/carry.out" >/dev/null 2>&1; then
    [ -e "$CPD/resume-pending.$PSLUG" ] || [ -e "$CPD/sid.md.restarted" ] && { echo "blocked-but-published"; return; }
    echo blocked
  elif [ -e "$CPD/resume-pending.$PSLUG" ]; then echo published
  else echo neither; fi
}
names() { jq -r '.reason' "$BOX/carry.out" 2>/dev/null | grep -qF -- "$1" && echo yes || echo no; }
variant() { grep -vF -- "$1" "$BOX/base.md" > "$BOX/v.md"; echo "$BOX/v.md"; }

check "carrying every item unchanged restarts" published "$(carry "$BOX/base.md")"

cat > "$BOX/norm.md" <<'MD'
## Waiting on
- **verdict: GO**  from `term_rev1` -> run merge-unit-local.sh alpha
* UNIT-GAMMA, blocked on the alpha merge (moved here from the queue)

## Rulings this session not yet in memory or a rule file
2) The owner: keep the 0.70 auto-tuning bar for widget sorting until the fix lands.

## Queue (in order)
none

## Todo list (the owner's on-screen checklist)
- [ ] Rebase delta onto main, then rerun its tests
- [>] push   after certification
MD
check "case, spacing, markers, decoration and a move between open sections still carry" published "$(carry "$BOX/norm.md")"

for item in "$W" "$Q" "$T1" "$T2"; do
  check "dropping '$item' blocks the restart" blocked "$(carry "$(variant "$item")")"
  check "and the block names it" yes "$(names "$item")"
done
check "dropping the wrapped ruling blocks the restart" blocked "$(carry "$(grep -v 'auto-tuning bar' "$BOX/base.md" | grep -v 'widget sorting until' > "$BOX/v.md"; echo "$BOX/v.md")")"
check "and the block names the whole wrapped item" yes "$(names "$R")"
check "and the baseline it compared against" yes "$(names "$CPD/old.md")"
check "and nothing was launched" no "$([ -e "$BOX/launched" ] && echo yes || echo no)"
check "and the /handoff request is kept for the retry" yes "$([ -e "$CPD/sid.handoff" ] && echo yes || echo no)"
check "keeping only the first line of a wrapped item is a drop" blocked "$(carry "$(variant 'widget sorting until')")"
sed 's/rebase delta onto main/rebase delta onto mainline/' "$BOX/base.md" > "$BOX/v.md"
check "a partial-word match is not a carry" blocked "$(carry "$BOX/v.md")"
printf '## Queue (in order)\nnone\n' > "$BOX/none.md"
printf '## Queue (in order)\nTODO: merge alpha once review lands\n' > "$BOX/todo-old.md"
check "an unbulleted TODO entry is work, not a placeholder" blocked "$(BASE=$BOX/todo-old.md carry "$BOX/none.md")"
printf '## Waiting on\n\nTODO for each live unit: the marker or verdict expected, and the exact command\nmain runs when it lands.\n\n## Queue (in order)\n\nTODO or "none".\n' > "$BOX/snap-old.md"
check "state-snapshot's unfilled placeholders are not work" published "$(BASE=$BOX/snap-old.md carry "$BOX/none.md")"
printf '## Waiting on\n- Wait for task_123 on term_rev1\n' > "$BOX/ids-old.md"
printf '## Waiting on\n- Wait for task123 on termrev1\n' > "$BOX/v.md"
check "an identifier with its underscores removed is a different item" blocked "$(BASE=$BOX/ids-old.md carry "$BOX/v.md")"

{ cat <<'MD'
## Waiting on
none

## Queue (in order)
none

## Todo list
- [x] rebase delta onto main
- [x] push after certification

## Closed since last checkpoint
MD
  for item in "$W" "$R" "$Q" "$T1" "$T2"; do echo "- $item -- merged and verified in abc1234"; done; } > "$BOX/closed.md"
check "closing every item with its reason restarts" published "$(carry "$BOX/closed.md")"
sed '/push after certification -- merged/d' "$BOX/closed.md" > "$BOX/v.md"
check "a Todo marked done without a closure is a drop" blocked "$(carry "$BOX/v.md")"
sed 's/^- push after certification -- merged.*/- push after certification/' "$BOX/closed.md" > "$BOX/v.md"
check "a bare closure with no reason is a drop" blocked "$(carry "$BOX/v.md")"
sed 's/^- push after certification -- merged.*/- certification -- shipped/' "$BOX/closed.md" > "$BOX/v.md"
check "a closure sharing one word is a drop" blocked "$(carry "$BOX/v.md")"
for sec in "Ruled out" "Gotchas learned this session" "How to verify"; do
  { grep -vF -- "$T2" "$BOX/base.md"; printf '\n## %s\n- %s -- mentioned here only\n' "$sec" "$T2"; } > "$BOX/v.md"
  check "a mention under $sec alone does not carry the item" blocked "$(carry "$BOX/v.md")"
done

printf '# Checkpoint\n\n## Queue (in order)\nnone\n' > "$BOX/empty.md"
check "a fresh session with no ancestry has no baseline" published "$(ANC=none carry "$BOX/empty.md")"
check "a recorded baseline that is missing blocks" blocked "$(ANC="$CPD/gone.md" carry "$BOX/base.md")"
check "a repeated stop in the same chain is still blocked" blocked "$(carry "$(variant "$Q")" true)"
check "the high-context trigger is gated too" blocked "$(carry "$(variant "$Q")" false line)"
check "and restarts once the item is carried" published "$(carry "$BOX/base.md" false line)"

# Carry by reference: a checkpoint may stand for an older one's open
# items with a "Carries open items of: <file>" line instead of copying them, so
# the restart payload stays small. The check follows the chain, so a drop
# anywhere in it is still caught.
cp "$BOX/base.md" "$CPD/older.md"
printf '# Checkpoint mid\n\nCarries open items of: %s\n\n## Queue (in order)\n1. mid-only unit\n' "$CPD/older.md" > "$CPD/mid.md"
printf '# Checkpoint new\n\nCarries open items of: %s\n\n## Queue (in order)\nnone\n' "$CPD/mid.md" > "$BOX/by-ref.md"
check "items carried by reference, two checkpoints deep, restart" published "$(BASE=$CPD/mid.md carry "$BOX/by-ref.md")"
printf '# Checkpoint new\n\n## Queue (in order)\n1. mid-only unit\n' > "$BOX/no-ref.md"
check "an item the baseline carries by reference is inherited: dropping it blocks" blocked "$(BASE=$CPD/mid.md carry "$BOX/no-ref.md")"
check "and the block names it" yes "$(names "$Q")"
printf '# Checkpoint new\n\nCarries open items of: %s\n\n## Queue (in order)\nnone\n' "$CPD/older.md" > "$BOX/skip-mid.md"
check "referencing past the baseline drops the baseline's own item" blocked "$(BASE=$CPD/mid.md carry "$BOX/skip-mid.md")"
check "and the block names it" yes "$(names 'mid-only unit')"
printf '# Checkpoint pure\n\nCarries open items of: %s\n' "$CPD/older.md" > "$BOX/pure-ref.md"
check "a baseline that carries everything by reference is not 'empty'" published "$(BASE=$BOX/pure-ref.md carry "$BOX/skip-mid.md")"
{ cat "$BOX/no-ref.md"; printf '\n## Closed since last checkpoint\n'
  for item in "$W" "$R" "$Q" "$T1" "$T2"; do echo "- $item -- merged and verified"; done; } > "$BOX/closed-ref.md"
check "a closure in the new checkpoint may end a referenced item" published "$(BASE=$CPD/mid.md carry "$BOX/closed-ref.md")"
sed '/push after certification -- merged/d' "$BOX/closed-ref.md" > "$BOX/v.md"
check "and one missing closure is a drop" blocked "$(BASE=$CPD/mid.md carry "$BOX/v.md")"
# An intermediate file's closure ends what it inherited: the new checkpoint
# need not re-close finished items forever.
{ cat "$CPD/mid.md"; printf '\n## Closed since last checkpoint\n- %s -- merged\n' "$W"; } > "$CPD/mid3.md"
{ cat "$BOX/no-ref.md"; for item in "$R" "$Q" "$T1" "$T2"; do echo "1. $item"; done; } > "$BOX/after-mid3.md"
check "an item an intermediate checkpoint closed is not inherited" published "$(BASE=$CPD/mid3.md carry "$BOX/after-mid3.md")"
# Diamond: new carries A and B, both carry C. A closed C's item, B did not, so it stays open.
printf '# C\n\n## Queue (in order)\n1. diamond item\n' > "$CPD/c.md"
printf '# A\n\nCarries open items of: %s\n\n## Queue (in order)\nnone\n\n## Closed since last checkpoint\n- diamond item -- done\n' "$CPD/c.md" > "$CPD/a.md"
printf '# B\n\nCarries open items of: %s\n\n## Queue (in order)\nnone\n' "$CPD/c.md" > "$CPD/b.md"
printf '# new\n\nCarries open items of: %s\nCarries open items of: %s\n\n## Queue (in order)\nnone\n' "$CPD/a.md" "$CPD/b.md" > "$BOX/diamond.md"
check "one sibling's closure does not hide the other sibling's open item" published "$(BASE=$CPD/b.md carry "$BOX/diamond.md")"
mv "$CPD/older.md" "$CPD/older.gone"
check "an unreadable referenced file cannot prove the carry and blocks" blocked "$(BASE=$CPD/mid.md carry "$BOX/by-ref.md")"
check "and the block names the file" yes "$(names "$CPD/older.md")"
mv "$CPD/older.gone" "$CPD/older.md"
# A cycle (old -> y -> old) ends at the file already seen instead of looping.
printf '# Checkpoint y\n\nCarries open items of: %s\n\n## Queue (in order)\n1. y-only unit\n' "$CPD/old.md" > "$CPD/y.md"
printf '# Checkpoint x\n\nCarries open items of: %s\n\n## Queue (in order)\n1. x-only unit\n' "$CPD/y.md" > "$BOX/x.md"
printf '# Checkpoint new\n\nCarries open items of: %s\n\n## Queue (in order)\nnone\n' "$CPD/old.md" > "$BOX/cyc-new.md"
check "a reference cycle ends and restarts" published "$(BASE=$BOX/x.md carry "$BOX/cyc-new.md")"
# Reopened: older2 closed "beta rollout"; mid2 reopened it. An older file's
# closure must never erase what a newer checkpoint reopened.
printf '# Checkpoint older2\n\n## Queue (in order)\nnone\n\n## Closed since last checkpoint\n- beta rollout -- shipped in abc1234\n' > "$CPD/older2.md"
printf '# Checkpoint mid2\n\nCarries open items of: %s\n\n## Queue (in order)\n1. beta rollout\n' "$CPD/older2.md" > "$CPD/mid2.md"
printf '# Checkpoint new\n\nCarries open items of: %s\n\n## Queue (in order)\nnone\n' "$CPD/mid2.md" > "$BOX/reopen-ok.md"
check "a reopened item carried by reference restarts" published "$(BASE=$CPD/mid2.md carry "$BOX/reopen-ok.md")"
printf '# Checkpoint new\n\nCarries open items of: %s\n\n## Queue (in order)\nnone\n' "$CPD/older2.md" > "$BOX/reopen-skip.md"
check "an older file's closure does not erase a newer reopen" blocked "$(BASE=$CPD/mid2.md carry "$BOX/reopen-skip.md")"
check "and the block names the reopened item" yes "$(names 'beta rollout')"

# One restart per checkpoint WRITE: the marker is keyed on the path, so a
# second checkpoint in the same session must not be shadowed by the first
# restart's marker, while a pinned old main stopping again without a new write
# is still skipped. Both files get one mtime: two writes in one second share it,
# so only the content can tell them apart.
marker_case() { # $1 = checkpoint the marker was written for: this | earlier -> published | neither
  rm -f "$CPD"/sid.* "$CPD/resume-pending.$PSLUG" "$BOX/launched"
  echo '# first checkpoint' > "$CPD/sid.md"
  [ "$1" = earlier ] && { cksum < "$CPD/sid.md" > "$CPD/sid.md.restarted"; echo '# second checkpoint' > "$CPD/sid.md"; }
  [ "$1" = this ] && cksum < "$CPD/sid.md" > "$CPD/sid.md.restarted"
  touch "$CPD/sid.handoff"
  perl -e '$n=time-60; utime($n,$n,@ARGV)' "$CPD/sid.md" "$CPD/sid.md.restarted"
  echo '{}' > "$BOX/transcript.jsonl"
  (cd "$BOX/repo" && printf '{"session_id":"sid","transcript_path":"%s","stop_hook_active":false}' "$BOX/transcript.jsonl" \
    | env -i PATH="$BOX/bin" HOME="$BOX/home" CALLS="$BOX/calls" ORCA_TERMINAL_HANDLE=old-pane \
        COMMANDECK_RESTART_HELPER="$BOX/stub-helper.sh" bash "$HOOK" >/dev/null 2>&1)
  [ -e "$CPD/resume-pending.$PSLUG" ] && echo published || echo neither
}
check "a marker from an earlier write, same mtime, restarts again" published "$(marker_case earlier)"
check "a marker for this write still skips (pinned old main)" neither "$(marker_case this)"

# NO FRESH CHECKPOINT: the refusal carries the template's headings, so
# the agent writes the checkpoint in one Write instead of first Reading the
# 4.5 KB template (3.5 turns per block before this).
rm -f "$CPD"/sid.* "$CPD/resume-pending.$PSLUG"
printf '%s\n' '{"message":{"usage":{"cache_read_input_tokens":500,"input_tokens":1}}}' > "$BOX/transcript.jsonl"
(cd "$BOX/repo" && printf '{"session_id":"sid","transcript_path":"%s","stop_hook_active":false}' "$BOX/transcript.jsonl" \
  | env -i PATH="$BOX/bin" HOME="$BOX/home" CALLS="$BOX/calls" ORCA_TERMINAL_HANDLE=old-pane COMMANDECK_CLEAR_LINE=10 \
      COMMANDECK_RESTART_HELPER="$BOX/stub-helper.sh" bash "$HOOK" > "$BOX/carry.out" 2>/dev/null)
check "no checkpoint: the stop is blocked" block "$(jq -r .decision "$BOX/carry.out" 2>/dev/null)"
while IFS= read -r h; do
  check "no checkpoint: the refusal lists '$h'" yes "$(names "$h")"
done < <(grep '^## ' "$ROOT/templates/checkpoint.md")
check "no checkpoint: it says not to Read the template" yes "$(names 'do not Read the template; one Write, then end the turn')"

# Each checkpoint in a carry chain is walked once. A real chain of 31
# files, a few carrying two or three older ones, took the check 302 s; here
# every file carries the two before it, about 10^8 walks when none is
# remembered. The 20 s bound is a hang guard, not a timing claim.
CARRY_PY=$ROOT/scripts/checkpoint-context.py
printf '# d0\n\n## Queue (in order)\n1. deep chain item\n' > "$CPD/d0.md"
printf '# d1\n\nCarries open items of: %s\n\n## Queue (in order)\nnone\n' "$CPD/d0.md" > "$CPD/d1.md"
for i in $(seq 2 40); do
  printf '# d%s\n\nCarries open items of: %s\nCarries open items of: %s\n\n## Queue (in order)\nnone\n' \
    "$i" "$CPD/d$((i-1)).md" "$CPD/d$((i-2)).md" > "$CPD/d$i.md"
done
printf '# new\n\n## Queue (in order)\nnone\n' > "$BOX/deep-drop.md"
printf '# new\n\nCarries open items of: %s\n\n## Queue (in order)\nnone\n' "$CPD/d40.md" > "$BOX/deep-keep.md"
DEEP=$(timeout 20 python3 "$CARRY_PY" carry "$CPD/d40.md" "$BOX/deep-drop.md"; echo "rc=$?")
check "a 40-deep chain of shared checkpoints still names the dropped item" "- deep chain item rc=1" "$(paste -sd' ' - <<<"$DEEP")"
check "and passes a checkpoint that carries the chain" 0 "$(timeout 20 python3 "$CARRY_PY" carry "$CPD/d40.md" "$BOX/deep-keep.md" >/dev/null; echo $?)"
# A remembered file must not answer for a walk that would have been cut at a
# cycle: here s.md is walked whole first, then met again inside its own cycle.
printf '# s\n\nCarries open items of: %s\n\n## Queue (in order)\n1. shared item\n' "$CPD/t.md" > "$CPD/s.md"
printf '# t\n\nCarries open items of: %s\n\n## Queue (in order)\n1. cycle item\n\n## Closed since last checkpoint\n- shared item -- done in t\n' "$CPD/s.md" > "$CPD/t.md"
printf '# r\n\nCarries open items of: %s\nCarries open items of: %s\n\n## Queue (in order)\nnone\n' "$CPD/s.md" "$CPD/t.md" > "$CPD/r.md"
CYC=$(timeout 20 python3 "$CARRY_PY" carry "$CPD/r.md" "$BOX/deep-drop.md"; echo "rc=$?")
check "a file remembered outside a cycle is walked again inside it, and each item is named once" \
  "- shared item - cycle item rc=1" "$(paste -sd' ' - <<<"$CYC")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

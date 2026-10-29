#!/usr/bin/env bash
# Self-test for context-clear-stop.sh's detached restart launch. Run directly.
#
# macOS has no setsid. The hook used to launch the helper with a bare setsid
# into /dev/null and mark the checkpoint restarted BEFORE the launch, so on the
# Mac the helper never ran and every later stop gave up as "already restarted".
# Pinned here: on a PATH without setsid the helper still starts; a restart whose
# checkpoint drops an open item, or that has no checkpoint, is blocked.
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
for t in bash sh env jq git date stat dirname basename cat ps grep perl touch printf rm rmdir sleep head tr cut sed awk mkdir ls wc tail sort python3 cksum mv paste timeout iconv comm; do
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
# Issue 316: the restart reads GitHub as main would before it opens a pane; gh-fail holds the error a read prints.
git -C "$BOX/repo" remote add origin https://github.com/o/repo.git
cat > "$BOX/bin/gh" <<STUB
#!/usr/bin/env bash
[ ! -e "$BOX/gh-fail" ] || { cat "$BOX/gh-fail" >&2; exit 1; }
echo '{"nameWithOwner":"o/repo"}'
STUB
chmod +x "$BOX/bin/gh"

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
        ${1:+COMMANDECK_RESTART_HELPER="$1"} ${2:+COMMANDECK_PARENT_ARGS="$2"} ${3:+COMMANDECK_PARENT_ARGV="${3}"} bash "$HOOK" >/dev/null 2>&1)
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
# /handoff: the owner sees the new main confirm it took over, or this pane says why it did not.
check "the new main's first line to the owner confirms the handoff and names the old pane" 1 \
  "$(grep '^terminal send --terminal new-pane' "$BOX/calls" | grep -c 'first line to the owner is: Handoff done: .*old pane old-pane closes now')"
prompt_line() { (cd "$BOX/repo" && printf '{"session_id":"sid","transcript_path":"%s","prompt":"hi"}' "$BOX/transcript.jsonl" \
  | env -i PATH="$BOX/bin" HOME="$BOX/home" ORCA_TERMINAL_HANDLE=old-pane bash "$ROOT/hooks/context-line.sh" 2>/dev/null); }
check "a spent handoff leaves no line at the next prompt" "" "$(prompt_line)"
touch "$CPD/sid.handoff"
echo "2026-10-14T10:00:00 restart: terminal create failed; old pane old-pane left up, next stop retries" >> "$CPD/clear-hook.log"
check "one that did not finish says so at the next prompt, with the helper's reason" 1 \
  "$(prompt_line | grep -c '^HANDOFF NOT DONE: this pane is still main\. .*terminal create failed; old pane old-pane left up')"
rm -f "$CPD/sid.handoff"

# Issue 316: a main that cannot read GitHub is not opened, and the old pane, the only one holding the context, stays.
echo "error connecting to api.github.com" > "$BOX/gh-fail"
run_hook ""
wait_for 'grep -q "REFUSED: main cannot read GitHub" "$CPD/clear-hook.log" && [ ! -e "$INFLIGHT" ]'
check "a restart is refused when main cannot read GitHub: no pane opened, the old pane not closed" "0:0" \
  "$(grep -c '^terminal create' "$BOX/calls"):$(grep -c '^terminal close' "$BOX/calls")"
check "the refusal names the reason and the old pane in the log, and the restarted marker is gone" "1:no" \
  "$(grep -c 'main cannot read GitHub: no network in the sandbox: error connecting to api.github.com.*old pane old-pane left up' "$CPD/clear-hook.log"):$([ -e "$CPD/sid.md.restarted" ] && echo yes || echo no)"
rm -f "$BOX/gh-fail" "$CPD/sid.handoff"

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
  cp "${BASE:-$BOX/base.md}" "$CPD/old.md"; cp "$1" "$CPD/sid.md"; [ -z "${UNREADABLE-}" ] || chmod 000 "$CPD/sid.md"
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
# The launch is detached: wait for it, or it lands inside the next case.
wait_for '[ -e "$BOX/launched" ]'
check "dropping the wrapped ruling blocks the restart" blocked "$(carry "$(grep -v 'auto-tuning bar' "$BOX/base.md" | grep -v 'widget sorting until' > "$BOX/v.md"; echo "$BOX/v.md")")"
check "and the block names the whole wrapped item" yes "$(names "$R")"
check "and the baseline it compared against" yes "$(names "~/.claude/checkpoints/old.md")"
check "and nothing was launched" no "$([ -e "$BOX/launched" ] && echo yes || echo no)"

# Issue 252: the block names the count, the first item and the command that lists them, never the whole list:
# a long list added to main's context on every block stranded it. The second stop of the chain copies the missing
# items into the checkpoint and restarts, and the restarted checkpoint then carries them.
check "the first stop's reason stays under 400 bytes" yes "$([ "$(jq -r .reason "$BOX/carry.out" | wc -c)" -lt 400 ] && echo yes)"
check "and names the count and the command that lists them" "1 1" \
  "$(names '1 inherited open item' | grep -c yes) $(names 'checkpoint-context.py carry' | grep -c yes)"
# A long first item is cut to the room the paths leave, so the reason still stays under 400 bytes.
LONG="unit-long $(printf 'word%.0s ' {1..60})end"
sed "s/^1\. $Q\$/1. $LONG/" "$BOX/base.md" > "$BOX/long.md"
BASE=$BOX/long.md carry "$(grep -vF "$LONG" "$BOX/long.md" > "$BOX/v3.md"; echo "$BOX/v3.md")" >/dev/null
check "a 300-character first item still leaves the reason under 400 bytes, naming its start" "yes yes" \
  "$([ "$(jq -r .reason "$BOX/carry.out" | wc -c)" -lt 400 ] && echo yes) $(names 'unit-long word')"
V=$(grep -v "unit-gamma" "$BOX/base.md" | grep -v 'push after certification' > "$BOX/v2.md"; echo "$BOX/v2.md")
check "dropping two items: the first stop blocks naming two" "blocked yes" "$(carry "$V" false) $(names '2 inherited open items')"
check "the second stop restarts" published "$(carry "$V" true)"
wait_for '[ -e "$BOX/launched" ]'
check "with the missing items copied under one unresolved Queue heading" "1 1 1" \
  "$(grep -c '^## Queue (left unresolved at the restart' "$CPD/sid.md") $(grep -c "^- $Q\$" "$CPD/sid.md") $(grep -c "^- $T2\$" "$CPD/sid.md")"
check "and logged as carried automatically" 1 "$(grep -c 'carried automatically into the checkpoint' "$CPD/clear-hook.log")"
check "the restarted checkpoint carries everything the old one had" 0 \
  "$(python3 "$ROOT/scripts/checkpoint-context.py" carry "$CPD/old.md" "$CPD/sid.md" >/dev/null; echo $?)"
# Issue 283: the stop line's cp_bytes is measured before the carry appends the missing items, so the carry's success
# logs the size the restart takes. The report reads the last stop-hook line naming the checkpoint.
CPB=$(wc -c < "$CPD/sid.md" | tr -d ' ')
LAST=$(grep "stop-hook: .*cp=$CPD/sid.md " "$CPD/clear-hook.log" | tail -1 | sed -n 's/.* cp_bytes=\([0-9]*\).*/\1/p')
FIRST=$(grep "stop-hook: ctx=.*cp=$CPD/sid.md " "$CPD/clear-hook.log" | tail -1 | sed -n 's/.* cp_bytes=\([0-9]*\).*/\1/p')
check "the last stop-hook line naming the checkpoint holds its size after the carry, which grew" "yes yes" \
  "$([ "$LAST" = "$CPB" ] && echo yes) $([ "$CPB" -gt "$FIRST" ] && echo yes)"
# Issue 300: a carry the hook made itself heals itself, so the relay's alert watcher, polled with that line in the log,
# prints nothing.
mkdir -p "$BOX/home/.commandeck/dashboard"; printf 'window.DASH = {"alerts": []};\n' > "$BOX/home/.commandeck/dashboard/data.js"
check "the relay's alert watcher prints nothing for it" "" "$(cd "$BOX/repo" && HOME="$BOX/home" COMMANDECK_MAIN="$BOX/repo" COMMANDECK_SCRATCH="$BOX" COMMANDECK_WATCH_ONCE=1 bash "$ROOT/scripts/cos-watch-alerts.sh" 2>&1)"
# An unreadable file in the chain is an item of its own: the first stop blocks, the second copies it with the
# readable items. Only an unreadable base, which shows nothing at all, restarts copying nothing.
printf '## Queue (in order)\n- ship release\n\nCarries open items of: %s\n' "$BOX/missing.md" > "$BOX/unreadable.md"
check "an unreadable ancestor blocks the first stop" blocked "$(BASE=$BOX/unreadable.md carry "$V" false)"
check "the second stop copies the readable item and the carry-chain item" "published 1 1" \
  "$(BASE=$BOX/unreadable.md carry "$V" true) $(grep -cx -- '- ship release' "$CPD/sid.md") $(grep -c '^- carry chain: cannot read the checkpoint .*missing.md' "$CPD/sid.md")"
wait_for '[ -e "$BOX/launched" ]'
# Pass 25: an unreadable base (carry exit 2) restarted copying nothing, so the restart lost the whole inheritance
# unseen. It is one missing item of its own: the first stop blocks, the second carries the warning.
check "an unreadable base blocks the first stop, naming one item" "blocked yes" \
  "$(ANC=$BOX/missing.md carry "$V" false) $(names '1 inherited open item: carry chain: ')"
check "the second stop carries the unreadable-base warning under the unresolved Queue heading" "published 1 1" \
  "$(ANC=$BOX/missing.md carry "$V" true) $(grep -c '^## Queue (left unresolved' "$CPD/sid.md") $(grep -c '^- carry chain: cannot read the checkpoint .*missing.md' "$CPD/sid.md")"
wait_for '[ -e "$BOX/launched" ]'
# The other exit-2 input: an unreadable new checkpoint blocks the first stop, and the second cannot copy into it, so
# main is never restarted on it.
check "an unreadable new checkpoint blocks the first stop and never restarts" "blocked neither" \
  "$(UNREADABLE=1 carry "$V" false) $(UNREADABLE=1 carry "$V" true)"
chmod 644 "$CPD/sid.md"

# Issue 281: three restarts, each rewording two inherited items, keep the count flat: no item copied twice, one
# unresolved Queue heading. A genuinely dropped item is still listed, and copied under that same heading.
printf '## Queue (in order)\n- alpha export\n- beta cache\n- gamma docs\n- delta notes\n\n## Todo list\n- [ ] beta cache follow-up\n' > "$BOX/r0.md"
PREV=$BOX/r0.md
for n in 1 2 3; do
  sed -E "s/^- alpha export.*/- alpha export -- still open: round $n/; s/^- beta cache\$|^- beta cache = .*/- beta cache = todo #1/" "$PREV" > "$BOX/r$n.md"
  [ "$n" = 1 ] && sed -i '/^- delta notes/d' "$BOX/r$n.md"
  [ "$n" = 3 ] && { sed -i '/gamma docs/d' "$BOX/r$n.md"
    check "round 3 drops gamma: the first stop lists one item" "blocked yes" "$(BASE=$PREV carry "$BOX/r$n.md" false) $(names '1 inherited open item: gamma docs')"; }
  check "round $n restarts" published "$(BASE=$PREV carry "$BOX/r$n.md" true)"
  wait_for '[ -e "$BOX/launched" ]'
  cp "$CPD/sid.md" "$BOX/r$n.out.md"; PREV=$BOX/r$n.out.md
done
check "after three restarts: the item count is the first's, no bullet repeated, one unresolved heading" "5 0 1" \
  "$(grep -c '^- ' "$PREV") $(grep '^- ' "$PREV" | sort | uniq -d | wc -l) $(grep -c '^## Queue (left unresolved' "$PREV")"

# Issue 283: the log line has the checkpoint's size, over=1 past the 10,240-byte resume budget; items the
# ten-generation walk cuts go to <cp>.aged-out.md, which the resume names in one line instead of loading.
# Issue 300: the line also has the minutes since this project's last restart.
for g in $(seq 11 -1 1); do
  { printf '## Queue (in order)\n- generation %s item\n' "$g"; [ "$g" = 11 ] || printf '\nCarries open items of: %s\n' "$CPD/g$((g + 1)).md"; } > "$CPD/g$g.md"
done
{ printf '## Queue (in order)\n- generation 0 item\n'; for i in $(seq 1 300); do printf -- '- filler line %s of a long checkpoint body\n' "$i"; done; printf '\nCarries open items of: %s\n' "$CPD/g1.md"; } > "$BOX/big.md"
rm -f "$CPD"/*.resumed-from "$BOX/tdir"/*.jsonl
check "a checkpoint past the budget restarts" published "$(ANC=none carry "$BOX/big.md")"
wait_for '[ -e "$BOX/launched" ]'
L=$(grep 'stop-hook: ctx=' "$CPD/clear-hook.log" | tail -1)
check "the log line has cp_bytes, over=1 and since_restart_min=- with no earlier restart" "1 1 1" \
  "$(grep -c "cp_bytes=$(wc -c < "$BOX/big.md" | tr -d ' ') " <<<"$L") $(grep -c ' over=1 ' <<<"$L") $(grep -c ' since_restart_min=- ' <<<"$L")"
check "the item past ten generations is in the aged-out file" 1 "$(grep -c '^- generation 10 item -- carried unseen: 11$' "$CPD/sid.md.aged-out.md")"
# A missing file past the readable ones: the readable items and the missing file still go to the aged-out file.
printf '\nCarries open items of: %s\n' "$CPD/g12.md" >> "$CPD/g11.md"
check "a chain ending in a missing file still restarts" published "$(ANC=none carry "$BOX/big.md")"
wait_for '[ -e "$BOX/launched" ]'
check "and its aged-out file has the readable items and the missing file" "1 1" \
  "$(grep -c '^- generation 11 item -- carried unseen: 12$' "$CPD/sid.md.aged-out.md") $(grep -c '^- carry chain: cannot read the checkpoint .*g12.md' "$CPD/sid.md.aged-out.md")"
echo '{}' > "$BOX/transcript.jsonl"; echo "$CPD/old.md" > "$CPD/other.resumed-from"; touch "$CPD/other.jsonl"
ln -sf "$CPD/other.jsonl" "$BOX/other.jsonl"
touch -d '7 minutes ago' "$CPD/other.resumed-from"
check "with a restart 7 minutes ago in this project the line says so" published "$(ANC=none carry "$BOX/base.md")"
wait_for '[ -e "$BOX/launched" ]'
check "since_restart_min=7, cp_bytes and no over" "1 0" \
  "$(grep 'stop-hook: ctx=' "$CPD/clear-hook.log" | tail -1 | grep -c ' since_restart_min=7 ') $(grep 'stop-hook: ctx=' "$CPD/clear-hook.log" | tail -1 | grep -c ' over=1')"
rm -f "$CPD/other.resumed-from" "$BOX/other.jsonl" "$CPD/other.jsonl"
# The resume names the aged-out file in one line and logs its payload_bytes.
cp "$BOX/big.md" "$CPD/sid.md"; printf '%s\n' '- generation 10 item -- carried unseen: 11' > "$CPD/sid.md.aged-out.md"
printf '%s\n' "$CPD/sid.md" > "$CPD/resume-pending.$PSLUG"
RES=$(cd "$BOX/repo" && printf '{"session_id":"new-sid","transcript_path":"%s"}' "$BOX/transcript.jsonl" \
  | env -i PATH="$BOX/bin" HOME="$BOX/home" COMMANDECK_BOARD_CMD=true COMMANDECK_SCRATCH="$BOX" bash "$ROOT/hooks/resume-context.sh" 2>&1)
check "the resume names the aged-out file in one line and loads none of it" "1 0" \
  "$(grep -c "sid\.md\.aged-out\.md" <<<"$RES") $(grep -c 'carried unseen' <<<"$RES")"
check "and logs its payload_bytes" "$(printf '%s\n' "$RES" | LC_ALL=C wc -c | tr -d ' ')" \
  "$(grep -o 'resume: payload_bytes=[0-9]*' "$CPD/clear-hook.log" | tail -1 | cut -d= -f2)"
rm -f "$CPD/new-sid.resumed-from"
# Issue 252: a resume cut to fit still shows both Queues, so the carried items are not lost behind a pointer.
{ printf '## Goal\n- the batch\n\n## Queue (in order)\n- queued omega item\n\n## Gotchas learned this session\n'
  for i in $(seq 1 300); do printf -- '- gotcha %s of a long checkpoint body\n' "$i"; done
  printf '\n## Queue (left unresolved at the restart: restate or close each, one line per item, with its own reason)\n- unresolved psi item\n'; } > "$CPD/sid.md"
rm -f "$CPD/sid.md.aged-out.md"; printf '%s\n' "$CPD/sid.md" > "$CPD/resume-pending.$PSLUG"
RES=$(cd "$BOX/repo" && printf '{"session_id":"new-sid","transcript_path":"%s"}' "$BOX/transcript.jsonl" \
  | env -i PATH="$BOX/bin" HOME="$BOX/home" COMMANDECK_BOARD_CMD=true COMMANDECK_SCRATCH="$BOX" bash "$ROOT/hooks/resume-context.sh" 2>&1)
check "a cut resume keeps both Queues and drops the Gotchas" "1 1 0" \
  "$(grep -c 'queued omega item' <<<"$RES") $(grep -c 'unresolved psi item' <<<"$RES") $(grep -c 'gotcha 150' <<<"$RES")"
rm -f "$CPD/new-sid.resumed-from"

# NO FRESH CHECKPOINT: the refusal carries the template's headings, so
# the agent writes the checkpoint in one Write instead of first Reading the
# 4.5 KB template (3.5 turns per block before this).
rm -f "$CPD"/sid.* "$CPD/resume-pending.$PSLUG"
printf '%s\n' '{"message":{"usage":{"cache_read_input_tokens":500,"input_tokens":1}}}' > "$BOX/transcript.jsonl"
(cd "$BOX/repo" && printf '{"session_id":"sid","transcript_path":"%s","stop_hook_active":false}' "$BOX/transcript.jsonl" \
  | env -i PATH="$BOX/bin" HOME="$BOX/home" CALLS="$BOX/calls" ORCA_TERMINAL_HANDLE=old-pane COMMANDECK_CLEAR_LINE=10 \
      COMMANDECK_RESTART_HELPER="$BOX/stub-helper.sh" bash "$HOOK" > "$BOX/carry.out" 2>/dev/null)
check "no checkpoint: the stop is blocked" block "$(jq -r .decision "$BOX/carry.out" 2>/dev/null)"

# THE BUILDER CLEAR LINE: a Builder pane (a linked worktree with COMMANDECK_BUILDER=1) past setup's
# builder.clearLine (default 180K; off turns it off) is told at each prompt to hand off to a fresh session:
# past it a bundled build re-reads a large cached context every turn, and compaction loses detail.
git -C "$BOX/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
git -C "$BOX/repo" worktree add -q "$BOX/ws/unit-a" 2>/dev/null
mkdir -p "$BOX/repo/.claude"
# builder_line <context tokens> [VAR=value...] -- what the prompt hook says in the Builder's pane.
builder_line() { printf '{"message":{"usage":{"cache_read_input_tokens":%s,"input_tokens":0}}}\n' "$1" > "$BOX/bt.jsonl"
  (cd "$BOX/ws/unit-a" && printf '{"session_id":"bs","transcript_path":"%s","prompt":"go on"}' "$BOX/bt.jsonl" \
    | env -i PATH="$BOX/bin" HOME="$BOX/home" ORCA_TERMINAL_HANDLE=builder-pane COMMANDECK_BUILDER=1 "${@:2}" bash "$ROOT/hooks/context-line.sh" 2>&1); }
OUT=$(builder_line 190000)
check "a Builder past the default 180K line is told to hand off" 1 "$(grep -c "^CONTEXT 190K is over this Builder's 180K clear line" <<<"$OUT")"
check "with the handoff file and the command that starts the fresh session in this pane" 1 \
  "$(grep -c "unit-a-handoff\.md.*builder-fresh-round\.sh builder-pane .*/ws/unit-a/\.claude/briefs/unit-a-handoff\.md" <<<"$OUT")"
check "under the line it says nothing" "" "$(builder_line 170000)"
check "a worker pane that is not a Builder is still exempt" "" "$(builder_line 190000 COMMANDECK_BUILDER=)"
echo '{"builder": {"clearLine": "off"}}' > "$BOX/repo/.claude/commandeck.json"
check "the line set off: no line at any size" "" "$(builder_line 400000)"
echo '{"builder": {"clearLine": "150000"}}' > "$BOX/repo/.claude/commandeck.json"
check "a line set at setup is the one read" 1 "$(builder_line 170000 | grep -c "^CONTEXT 170K is over this Builder's 150K clear line")"
echo '{"builder": {"clearLine": "lots"}}' > "$BOX/repo/.claude/commandeck.json"
check "a saved line that is not a token count says so, naming the key" 1 "$(builder_line 190000 | grep -c 'builder.clearLine')"
rm "$BOX/repo/.claude/commandeck.json"

# Issue 267: on a 200K window (standardContext) the host measured auto-compact at 171K-175K, so the line, the
# ceiling, a Builder's line and the PAST nudge all sit under it: 140K, a ceiling under 171K, the nudge at the line.
echo '{"standardContext": true}' > "$BOX/repo/.claude/commandeck.json"
check "a standard window's ceiling is under 171K" yes \
  "$(c=$(cd "$BOX/repo" && . "$ROOT/hooks/lib/project.sh" && pp_clear_ceiling) && [ "$c" -lt 171000 ] && [ "$c" -gt 140000 ] && echo yes)"
check "the 1M window keeps 200K and 480K" "200000 480000" \
  "$(mkdir -p "$BOX/repo2" && cd "$BOX/repo2" && git init -q && . "$ROOT/hooks/lib/project.sh" && echo "$(pp_clear_line) $(pp_clear_ceiling)")"
rm -f "$CPD"/sid.*
printf '%s\n' '{"message":{"usage":{"cache_read_input_tokens":141000,"input_tokens":0}}}' > "$BOX/transcript.jsonl"
(cd "$BOX/repo" && printf '{"session_id":"sid","transcript_path":"%s","stop_hook_active":false}' "$BOX/transcript.jsonl" \
  | env -i PATH="$BOX/bin" HOME="$BOX/home" ORCA_TERMINAL_HANDLE=old-pane bash "$ROOT/hooks/lib/run-hook.sh" "$HOOK" > "$BOX/carry.out" 2>/dev/null)
check "a main at 141K on a standard window is blocked for its checkpoint" block "$(jq -r .decision "$BOX/carry.out" 2>/dev/null)"
check "a Builder at 141K on a standard window is told at its 140K line" 1 "$(builder_line 141000 | grep -c "^CONTEXT 141K is over this Builder's 140K clear line")"
check "main's nudge at 141K says PAST the 140K line" 1 \
  "$(cd "$BOX/repo" && printf '{"session_id":"sid","transcript_path":"%s","prompt":"hi"}' "$BOX/transcript.jsonl" \
    | env -i PATH="$BOX/bin" HOME="$BOX/home" bash "$ROOT/hooks/lib/run-hook.sh" "$ROOT/hooks/context-line.sh" 2>/dev/null | grep -c 'PAST the 140K line')"
rm "$BOX/repo/.claude/commandeck.json"

# #409: past the line main's one step is a flagged state-snapshot.sh call. The first prompt past the line writes the
# skeleton once; that skeleton is not restart-ready, so a turn that ends without the flagged call never restarts main.
rm -f "$CPD"/s1.* "$BOX/launched" "$BOX/calls"
printf '%s\n' '{"message":{"usage":{"cache_read_input_tokens":210000,"input_tokens":1}}}' > "$BOX/t-s1.jsonl"
prompt_s1() { (cd "$BOX/repo" && printf '{"session_id":"s1","transcript_path":"%s","prompt":"go"}' "$BOX/t-s1.jsonl" \
  | env -i PATH="$BOX/bin:$PATH" HOME="$BOX/home" CALLS="$BOX/calls" bash "$ROOT/hooks/context-line.sh" 2>&1); }
stop_s1() { (cd "$BOX/repo" && printf '{"session_id":"s1","transcript_path":"%s","stop_hook_active":%s}' "$BOX/t-s1.jsonl" "$1" \
  | env -i PATH="$BOX/bin" HOME="$BOX/home" CALLS="$BOX/calls" ORCA_TERMINAL_HANDLE=old-pane \
      COMMANDECK_RESTART_HELPER="$BOX/stub-helper.sh" bash "$HOOK" > "$BOX/s1.out" 2>"$BOX/s1.err"); }
OUT=$(prompt_s1)
check "first crossing writes the snapshot once: the skeleton is written and the line names the flagged call" "1:1" \
  "$(grep -c '^TODO one line:' "$CPD/s1.md"):$(grep -c 'state-snapshot.sh --out .*s1.md --goal' <<<"$OUT")"
rm -f "$CPD/s1.md"
OUT=$(prompt_s1)
check "first crossing writes the snapshot once: a later prompt past the line writes none" "no:1" \
  "$([ -e "$CPD/s1.md" ] && echo yes || echo no):$(grep -c 'state-snapshot.sh --out .*s1.md --goal' <<<"$OUT")"

# The judge's sequence: the skeleton is there, no resumed-from record, the turn ends with no flagged call.
rm -f "$CPD"/s1.*; prompt_s1 >/dev/null
sed 's/^| (no live units) .*$/| U | TODO | -- | -- | none | TODO |/' "$CPD/s1.md" > "$CPD/s1.new" && mv "$CPD/s1.new" "$CPD/s1.md"
stop_s1 false
check "an unfilled automatic snapshot never restarts main: the first stop blocks naming Goal, under 400 bytes" "block:1:yes" \
  "$(jq -r .decision "$BOX/s1.out"):$(jq -r .reason "$BOX/s1.out" | grep -c 'Goal'):$([ "$(jq -r .reason "$BOX/s1.out" | wc -c)" -lt 400 ] && echo yes)"
stop_s1 true; sleep 1
check "an unfilled automatic snapshot never restarts main: the second stop exits 0, says so and launches nothing" "none:1:no" \
  "$([ -s "$BOX/s1.out" ] && echo out || echo none):$(grep -c 'context-clear: .* still has unfilled fields; main is not restarted' "$BOX/s1.err"):$([ -e "$BOX/launched" ] && echo yes || echo no)"
(cd "$BOX/repo" && env -i PATH="$BOX/bin:$PATH" HOME="$BOX/home" bash "$ROOT/scripts/state-snapshot.sh" --out "$CPD/s1.md" --goal 'ship U' --stage 'U=build it' --next 'U=merge it' >/dev/null 2>&1)
stop_s1 false
wait_for '[ -e "$BOX/launched" ] && [ ! -e "$INFLIGHT" ]'
check "an unfilled automatic snapshot never restarts main: once the flagged call has filled it, the next stop restarts" yes \
  "$([ -e "$BOX/launched" ] && echo yes || echo no)"
rm -f "$CPD"/s1.* "$BOX/launched"

# The hand template ships its own Goal placeholder, `<one line: ...>`; a checkpoint written from it with the units
# filled but the Goal left is no more a restart point than the generator's skeleton.
prompt_s1 >/dev/null
sed -e 's/^| (no live units) .*$/| U | build it | -- | -- | none | merge it |/' \
    -e 's/^TODO one line:.*$/<one line: the batch, the standing rulings that bind it>/' "$CPD/s1.md" > "$CPD/s1.new" && mv "$CPD/s1.new" "$CPD/s1.md"
stop_s1 false
check "a hand-template checkpoint with its Goal placeholder never restarts main: the first stop blocks naming Goal alone" "block:1:0" \
  "$(jq -r .decision "$BOX/s1.out"):$(jq -r .reason "$BOX/s1.out" | grep -c 'unfilled Goal\.'):$(jq -r .reason "$BOX/s1.out" | grep -c 'unit stage')"
stop_s1 true; sleep 1
check "a hand-template checkpoint with its Goal placeholder never restarts main: the second stop launches nothing" "none:no" \
  "$([ -s "$BOX/s1.out" ] && echo out || echo none):$([ -e "$BOX/launched" ] && echo yes || echo no)"
rm -f "$CPD"/s1.* "$BOX/launched"

# Host fix 3a7cc613: a restart never kills an in-session helper agent. It waits while one runs, past the ceiling too,
# and says so; an agent ends at its task-notification or at a successful TaskStop (its structured result, never a
# shell's stdout). A session whose restart helper gave up (<sid>.restart-failed) is never restarted again.
LAUNCH='{"type":"user","message":{"content":[{"type":"tool_result","content":[{"type":"text","text":"Async agent launched successfully.\nagentId: abc123 (internal ID)"}]}]},"toolUseResult":{"status":"async_launched"}}'
STOPPED='{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]},"toolUseResult":{"message":"Successfully stopped task: abc123 (agent)","task_id":"abc123"}}'
QUOTED='{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]},"toolUseResult":{"stdout":"Successfully stopped task: abc123","stderr":""}}'
agents() { # <transcript rows...> -- one stop 500 tokens past a 10-token line and a 20-token ceiling: launched | held
  rm -f "$CPD"/sid.* "$CPD/resume-pending.$PSLUG" "$BOX/launched"; echo '# checkpoint' > "$CPD/sid.md"
  [ -z "${GAVE_UP-}" ] || : > "$CPD/sid.restart-failed"
  { printf '%s\n' '{"message":{"usage":{"cache_read_input_tokens":500,"input_tokens":1}}}'; printf '%s\n' "$@"; } > "$BOX/transcript.jsonl"
  (cd "$BOX/repo" && printf '{"session_id":"sid","transcript_path":"%s","stop_hook_active":false}' "$BOX/transcript.jsonl" \
    | env -i PATH="$BOX/bin" HOME="$BOX/home" CALLS="$BOX/calls" ORCA_TERMINAL_HANDLE=old-pane COMMANDECK_CLEAR_LINE=10 \
        COMMANDECK_CLEAR_CEILING=20 COMMANDECK_RESTART_HELPER="$BOX/stub-helper.sh" bash "$HOOK" > /dev/null 2> "$BOX/agents.err")
  if [ -e "$CPD/resume-pending.$PSLUG" ]; then wait_for '[ -e "$BOX/launched" ] && [ ! -e "$INFLIGHT" ]'; echo launched; else echo held; fi
}
check "past the ceiling a running agent still holds the restart" held "$(agents "$LAUNCH")"
check "and main is told to TaskStop it or let it finish, naming it" 1 "$(grep -c 'restart still waits for 1 background agent(s) (abc123).*Stop each with TaskStop, or let it finish' "$BOX/agents.err")"
check "an agent stopped with TaskStop no longer holds it" launched "$(agents "$LAUNCH" "$STOPPED")"
check "the stop text quoted in a shell's output ends nothing" held "$(agents "$LAUNCH" "$QUOTED")"
check "a session whose restart helper gave up is not restarted again" held "$(GAVE_UP=1 agents)"
check "and main is told the owner restarts it by hand" 1 "$(grep -c 'the automatic restart failed .*the owner restarts main by hand' "$BOX/agents.err")"

# Issue 453: a launch line the flat ps text cannot replay (braces, quotes) restarts as `claude` plus the permission
# options found in the parent's real argv, one entry each. A permission word that is data (inside a value, or the
# value of another option) grants nothing. COMMANDECK_PARENT_ARGV is a file of NUL-separated entries.
rm -f "$BOX/gh-fail" "$CPD/sid.handoff"
restart_cmd() { # <flat ps line> <argv entries...> -> the command the new pane is created with, minus the resume token
  local flat=$1; shift
  printf '%s\0' "$@" > "$BOX/argv"
  run_hook "" "$flat" "$BOX/argv"
  wait_for "$helper_done"
  grep -m1 '^terminal create' "$BOX/calls" | sed -E 's/.*--command COMMANDECK_RESUME_TOKEN=[^ ]+ //; s/ --json.*//'
}
J1='{"a":1}'
J2='{"env":{"NOTE":" --dangerously-skip-permissions "}}'
check "a launch line with a JSON value restarts with its permission mode kept (issue 453)" "claude --permission-mode acceptEdits" \
  "$(restart_cmd "claude --settings $J1 --permission-mode acceptEdits" claude --settings "$J1" --permission-mode acceptEdits)"
check "a permission flag inside an option's value grants nothing on restart (issue 453)" "claude --permission-mode acceptEdits:claude" \
  "$(restart_cmd "claude --settings $J2 --permission-mode acceptEdits" claude --settings "$J2" --permission-mode acceptEdits):$(restart_cmd "claude --append-system-prompt --dangerously-skip-permissions {" claude --append-system-prompt --dangerously-skip-permissions)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

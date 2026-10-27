#!/usr/bin/env bash
# unit-close.sh (#396): a finished unit's Builder task closes from its own seat record, never by guesswork. The task
# ids are the record's task= and answer_task= lines, so another unit's task is never touched; a working Builder refuses
# (pp_task_close); settled=<task> keeps a rerun from closing a task twice.
#   merged: closes each task completed; no record closes nothing. drop: failed, then panes, then a worktree removal that
#   only a readable, empty second pane listing allows. --sweep: gone units' open tasks, dry run unless --apply.
# orca-ide is a stub first on PATH: every call is logged, task-update answers ok.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT=$REAL/scripts/unit-close.sh
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }

CALLS=$T/calls FX=$T/fx M=$T/main WS=$T/ws
mkdir -p "$T/bin" "$FX" "$WS" "$M/.claude/metrics" "$T/home"
git init -q -b main "$M"; git -C "$M" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
ONMAIN=$(git -C "$M" rev-parse HEAD)
printf '{"unit":"m1","mergeSha":"%s"}\n{"unit":"sm","mergeSha":"%s"}\n' "$ONMAIN" "$ONMAIN" > "$M/.claude/metrics/unit-ledger.jsonl"
# WORKING names the one handle whose pane works; PANE_H/PANE_WT give that worktree one pane. A pane list after a
# `terminal close` is empty unless STILL=1 (the pane is still named) or LIST2_FAIL=1 (the list exits 1).
cat > "$T/bin/orca-ide" <<'EOS'
#!/usr/bin/env bash
echo "$*" >> "$CALLS"
case "$1 $2" in
  "worktree ps")
    if [ -n "${WORKING:-}" ]; then printf '{"result":{"worktrees":[{"path":"w","agents":[{"paneKey":"tab-%s:leaf","state":"working"}]}]}}\n' "$WORKING"
    else echo '{"result":{"worktrees":[]}}'; fi ;;
  "terminal list")
    if [ -e "$FX/closed" ]; then
      [ "${LIST2_FAIL:-}" != 1 ] || exit 1
      [ "${STILL:-}" = 1 ] || { echo '{"result":{"terminals":[]}}'; exit 0; }
    fi
    printf '{"result":{"terminals":[{"handle":"%s","tabId":"tab-%s","leafId":"leaf","worktreePath":"%s"}]}}\n' \
      "${PANE_H:-${WORKING:-term_none}}" "${PANE_H:-${WORKING:-term_none}}" "${PANE_WT:-/none}" ;;
  "terminal close") : > "$FX/closed"; echo '{"ok":true}' ;;
  "orchestration dispatch-show") echo '{"result":{"dispatch":null}}' ;;
  "orchestration inbox") echo '{"result":{"messages":[]}}' ;;
  "orchestration task-list") cat "$FX/tasks.json" || exit 1 ;;
  "orchestration task-update") echo '{"ok":true}' ;;
  "worktree remove") echo '{"ok":true}' ;;
esac
exit 0
EOS
chmod +x "$T/bin/orca-ide"
export PATH=$T/bin:$PATH CALLS FX HOME=$T/home COMMANDECK_MAIN=$M COMMANDECK_WORKSPACES=$WS COMMANDECK_SCRATCH=$T/scratch COMMANDECK_RUN=run_t
mkdir -p "$COMMANDECK_SCRATCH"
rec() { printf 'handle=%s\ntask=%s\nrole=builder\nunit=%s\n' "$2" "$3" "$1" > "$COMMANDECK_SCRATCH/seat-$1-builder.txt"; } # <unit> <handle> <task>
run() { : > "$CALLS"; rm -f "$FX/closed"; rc=0; (cd "$M" && bash "$SCRIPT" "$@") > "$T/out" 2>&1 || rc=$?; }
updates() { grep -c 'orchestration task-update' "$CALLS"; }
cnt() { grep -c -- "$1" "$2"; }

rec a term_a task_a; printf 'answer_task=task_a2\n' >> "$COMMANDECK_SCRATCH/seat-a-builder.txt"; rec ab term_ab task_ab
run a merged
check "a merge closes the record's task and its answer tasks completed" "0 1 1 2" \
  "$rc $(cnt 'task-update --id task_a --status completed' "$CALLS") $(cnt 'task-update --id task_a2 --status completed' "$CALLS") $(cnt '^STEP 5 task: closed task_a' "$T/out")"
check "another unit's task is untouched" "0" "$(cnt 'task_ab' "$CALLS")"

run nr merged
check "no record closes nothing" "1 0 1" \
  "$rc $(updates) $(cnt '^STEP 5 task NOT closed: no Builder seat record.*unit-close.sh --sweep --apply closes it later$' "$T/out")"

rec w term_w task_w
WORKING=term_w run w merged
check "a working Builder refuses and the record gains no settled line" "1 0 0 1" \
  "$rc $(updates) $(cnt '^settled=' "$COMMANDECK_SCRATCH/seat-w-builder.txt") $(cnt '^STEP 5 task NOT closed: .*unit-close.sh --sweep --apply closes it later$' "$T/out")"

mkdir -p "$WS/d"; rec d term_d task_d
PANE_H=term_d PANE_WT=$WS/d run d drop 'superseded by unit e'
check "a dropped unit's task is failed and its worktree removed" "0 1 1 1" \
  "$rc $(cnt 'task-update --id task_d --status failed --json --result {"reason":"superseded by unit e"}' "$CALLS") $(cnt '^terminal close --terminal term_d' "$CALLS") $(cnt "^worktree remove --worktree path:$WS/d --force" "$CALLS")"

mkdir -p "$WS/m1"; rec m1 term_m1 task_m1
PANE_H=term_m1 PANE_WT=$WS/m1 run m1 drop 'no longer needed'
check "a merged unit cannot be dropped" "1 1 0 0 0" \
  "$rc $(cnt "^REFUSED: m1 is merged (${ONMAIN:0:12} on main); drop is for an unmerged unit$" "$T/out") $(updates) $(cnt '^terminal close' "$CALLS") $(cnt '^worktree remove' "$CALLS")"

mkdir -p "$WS/dw"; rec dw term_dw task_dw
WORKING=term_dw PANE_WT=$WS/dw run dw drop 'superseded'
check "a working Builder refuses the drop and nothing is removed" "1 0 0 0" \
  "$rc $(updates) $(cnt '^terminal close' "$CALLS") $(cnt '^worktree remove' "$CALLS")"

mkdir -p "$WS/ds"; rec ds term_ds task_ds
STILL=1 PANE_H=term_ds PANE_WT=$WS/ds run ds drop 'x'
check "a drop keeps the worktree when a closed pane is still listed" "1 0 1" \
  "$rc $(cnt '^worktree remove' "$CALLS") $(cnt "^KEPT $WS/ds: still listed after the close: term_ds" "$T/out")"

mkdir -p "$WS/du"; rec du term_du task_du
LIST2_FAIL=1 PANE_H=term_du PANE_WT=$WS/du run du drop 'x'
check "a drop keeps the worktree when the second pane listing cannot be read" "1 0 1" \
  "$rc $(cnt '^worktree remove' "$CALLS") $(cnt "^KEPT $WS/du: the pane list could not be read after the close" "$T/out")"

# --sweep: its own scratch, so the records above are not swept.
export COMMANDECK_SCRATCH=$T/scratch2; mkdir -p "$COMMANDECK_SCRATCH" "$WS/sl"
rec sm term_sm task_sm; rec su term_su task_su; rec sl term_sl task_sl; rec sc term_sc task_sc
printf '{"result":{"tasks":[%s]}}\n' \
  '{"id":"task_sm","status":"ready"},{"id":"task_su","status":"dispatched"},{"id":"task_sl","status":"ready"},{"id":"task_sc","status":"completed"},{"id":"task_orphan","status":"ready"}' > "$FX/tasks.json"
run --sweep
check "the sweep dry run changes nothing" "0 0 1 1" \
  "$rc $(updates) $(cnt '^would close task_sm completed sm$' "$T/out") $(cnt '^would close task_su failed su$' "$T/out")"
run --sweep --apply
check "the sweep closes a merged gone unit completed and an unmerged gone one failed, and skips a live one" "0 1 1 0" \
  "$rc $(cnt 'task-update --id task_sm --status completed' "$CALLS") $(cnt 'task-update --id task_su --status failed' "$CALLS") $(cnt 'task_sl\|task_sc\|task_orphan' "$CALLS")"

export COMMANDECK_SCRATCH=$T/scratch3; mkdir -p "$COMMANDECK_SCRATCH"
rec 'ops@fu' term_fu task_fu; rec so term_so task_so
printf '{"result":{"tasks":[%s]}}\n' '{"id":"task_fu","status":"ready"},{"id":"task_so","status":"completed"},{"id":"task_orphan","status":"ready"}' > "$FX/tasks.json"
run --sweep --apply
check "the sweep skips another repository's record and lists a task with no record" "0 0 1 1" \
  "$rc $(cnt 'task_fu' "$CALLS") $(cnt '^skip ops@fu: another repository' "$T/out") $(cnt '^no record task_orphan ready$' "$T/out")"

# A settled task is not closed again; a record whose last line lacks its newline still takes the marker on its own line.
export COMMANDECK_SCRATCH=$T/scratch4; mkdir -p "$COMMANDECK_SCRATCH"
printf 'handle=term_s\ntask=task_s' > "$COMMANDECK_SCRATCH/seat-s-builder.txt"
run s merged; run s merged
check "a settled task is not closed again" "0 0 1" \
  "$rc $(updates) $(cnt '^settled=task_s$' "$COMMANDECK_SCRATCH/seat-s-builder.txt")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

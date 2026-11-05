#!/usr/bin/env bash
# recover-stalls.sh -- issue 663: recover a stalled unit once per unit per condition. main-watch.sh's recover_tick runs it
# once per tick with the tick's lists (COMMANDECK_TERMINALS_JSON, COMMANDECK_PS_JSON, COMMANDECK_TASKS_JSON).
#
# Output contract, read only by recover_tick: `recovered: <what> <unit>: <condition>` per act (a digest line for main),
# `ask: <key><TAB><subject><TAB><body file>` for a failed recovery or a second failure (one post question), anything else on stderr.
# State: $PP_SCRATCH/main-watch/recovered, one row `<recovery> <unit-or-task> <condition-key>`; only a whole row counts,
# so a half row blocks nothing. Every recovery writes its row before its act (a crash skips a recovery, never repeats
# it), and an act that fails asks main once with the tail of its error (pass 17: a refused start that wrote no row was
# retried every tick with nobody asked).
# R2 an answer to a pane whose follower log has no delivered line and whose tag is in no prompt row of the pane's log,
#    the pane idle 5 min: answer-worker.sh again with the decision text the follower log names (a log naming no
#    decision is skipped, never guessed).
# R3 a Builder task Orca lists ready, its pane listed, launched over 3 min ago: dispatch-task.sh to that pane; a failed
#    dispatch still spends the row and asks main (pass 13).
# R3b the same with no listed pane and no merge since the launch: seat.sh launch builder; the old task is closed.
# R4 a driver whose args file's service is not running, no done file, no merge since its start, the owner file absent or naming it: unit-drive.sh
#    start from the args file (it resumes). A second death of the unit is a question with the driver log's tail.
# R4b a seat main-watch's dead_seats found exited with no verdict: seat.sh launch, or for a plan seat, unit-drive.sh start
#    once its driver stopped. Once per seat (its relaunch's exit is dead_seats' question). Never a hand launch.
#    R1 (panes after a merge) is close-done-panes.sh's.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/paths.sh" || exit 1
. "$HERE/host-services.sh"
. "$HERE/../hooks/lib/project.sh"; pp_project "$PP_MAIN"
BIN=${COMMANDECK_RECOVER_SCRIPTS:-$HERE}
ST=$PP_SCRATCH/main-watch ROWS=$PP_SCRATCH/main-watch/recovered
mkdir -p "$ST" || exit 1
NOW=${COMMANDECK_NOW:-$(date +%s)}
TERMS=${COMMANDECK_TERMINALS_JSON:-$(timeout 8 orca-ide terminal list --json)}
TASKS=${COMMANDECK_TASKS_JSON:-$(timeout 8 orca-ide orchestration task-list --json)}
LISTED=$(jq -r '.result | if type == "array" then . else .terminals end | .[]? | "\(.handle)\t\(.worktreePath)"' <<<"$TERMS") \
  || { echo "recover-stalls: the pane list cannot be read; nothing recovered" >&2; exit 1; }
READY=$(jq -r '.result.tasks[]? | select(.status == "ready") | .id' <<<"$TASKS") \
  || { echo "recover-stalls: the task list cannot be read; nothing recovered" >&2; exit 1; }
has() { grep -qxF -- "$1 $2 $3" "$ROWS" 2>/dev/null; }
row() { printf '%s %s %s\n' "$1" "$2" "$3" >> "$ROWS"; }
said() { echo "recovered: $1 $2: $3"; }
ask() { # <key> <subject> <body>
  local f=$ST/recover-$1.txt; printf '%s\n' "$3" > "$f"; printf 'ask: %s\t%s\t%s\n' "$1" "$2" "$f"; }
# try <cmd>... -- runs the act with its stderr passed through and kept in $ERR, for the question if it fails.
ERR=$ST/recover-err.txt
try() { local rc=0; "$@" 2>"$ERR" || rc=$?; cat "$ERR" >&2; return "$rc"; }
error() { printf 'Error: %s' "$(tail -n 5 "$ERR" 2>/dev/null)"; }
listed() { awk -F'\t' -v h="$1" '$1 == h { f = 1 } END { exit !f }' <<<"$LISTED"; }
merged_since() { # <unit> <epoch> -- a merged row of this checkout's unit at or after the epoch
  jq -e -s --arg m "$PP_MAIN_P" --arg u "$1" --argjson l "$2" \
    'any(.[]; .how == "merged" and .main == $m and .unit == $u and ((.at | fromdateiso8601?) // 0) >= $l)' \
    "$HOME/.commandeck/builds/$PP_PROJECT.jsonl" >/dev/null 2>&1; }
# args <unit> -- the four lines of drive-<unit>.args in A_SPEC A_JUDGE A_BATCH A_NAME; 1 when missing or short.
args() { local f=$PP_SCRATCH/drive-$1.args; A_SPEC= A_JUDGE= A_BATCH= A_NAME=
  { read -r A_SPEC; read -r A_JUDGE; read -r A_BATCH; read -r A_NAME; } < "$f" 2>/dev/null; [ -n "$A_NAME" ]; }
start() { bash "$BIN/unit-drive.sh" start "$1" "$A_SPEC" "$A_JUDGE" "$A_BATCH" >&2; }
# in_prompt <log> <claude|codex> <tag> -- 0 when the pane took the tag: answer-worker.sh's `delivered` rule (issue 658,
# D7; pass 19), the same filter. A prompt row (Claude: a user text row, never a compact summary; Codex: a user
# response_item message), or the result of the pane's own waiting call (ask-main.sh, orchestration ask or check) by its
# call id; another call's result never counts.
in_prompt() { [ -n "$1" ] || return 1
  grep -F -e "$3" -e ask-main.sh -e 'orchestration ask' -e 'orchestration check' -- "$1" 2>/dev/null | jq -nRe --arg t "$3" --arg k "$2" '
    def waits: tostring | test("ask-main\\.sh|orchestration (ask|check)");
    def txt: if type == "string" then . else [.[]? | .text? // empty] | join("\n") end;
    [inputs | fromjson? // empty] as $r
    | if $k == "codex" then
        [$r[] | .payload? // {} | select((.type == "function_call" or .type == "custom_tool_call") and .call_id != null
          and ((.arguments // .input // "") | waits)) | .call_id] as $w
        | any($r[]; .type == "response_item" and (.payload as $p
          | ($p.type == "message" and $p.role == "user" and ([$p.content[]? | .text? // empty] | join("\n") | contains($t)))
          or (($p.type == "function_call_output" or $p.type == "custom_tool_call_output") and ($p.call_id | IN($w[]))
            and ($p.output | tostring | contains($t)))))
      else
        [$r[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and .id != null
          and ((.input.command // "") | waits)) | .id] as $w
        | any($r[]; .type == "user" and .isCompactSummary != true and (.message.content
          | if type == "string" then contains($t)
            else any(.[]?; (.type == "text" and (.text // "" | contains($t)))
              or (.type == "tool_result" and (.tool_use_id | IN($w[])) and (.content | txt | contains($t)))) end))
      end' >/dev/null 2>&1; }

# R2
jq -r 'select(.from == "answer-worker" and .result == "sent" and (.reason | startswith("answer "))) | "\(.to) \(.reason | ltrimstr("answer "))"' \
  "$PP_SCRATCH/wake-log.jsonl" 2>/dev/null | sort -u | while read -r h tag; do
  log=$PP_SCRATCH/answer-worker-$tag.log
  [ -f "$log" ] && ! grep -v 'NOT delivered' "$log" | grep -q 'delivered' || continue
  id=$(sed -n 's/^decision=//p' "$log" | head -1); [ -n "$id" ] || continue
  wt=$(awk -F'\t' -v h="$h" '$1 == h { print $2; exit }' <<<"$LISTED"); [ -n "$wt" ] || continue
  rv=$(bash "$BIN/read-verdict.sh" --state --worktree "$wt" 2>/dev/null)
  idle=$(sed -n 's/^idle_seconds=//p' <<<"$rv" | head -1)
  [[ $idle =~ ^[0-9]+$ ]] && [ "$idle" -ge 300 ] || continue
  # The pane took it after its follower gave up: the tag is in a prompt row, so it is delivered and never retyped.
  ! in_prompt "$(sed -n 's/^session=//p' <<<"$rv" | head -1)" "$(sed -n 's/^provider=//p' <<<"$rv" | head -1)" "$tag" || continue
  if has R2 "$h" "$tag"; then continue; fi
  text=$(jq -rs --arg id "$id" '[.[] | select(.id == $id and .answer != null)] | last | .answer // empty' "$PP_MAIN/.claude/metrics/decisions.jsonl" 2>/dev/null)
  [ -n "$text" ] || continue
  row R2 "$h" "$tag"
  if bash "$BIN/answer-worker.sh" "$h" "$text" "$id" >&2; then said "retyped answer" "${wt##*/}" "$id to idle pane $h never got tag $tag"
  else ask "R2-$tag" "recovery failed once: answer $id to $h" "The answer $id (tag $tag) was sent again to the idle pane $h and is still not delivered: $(tail -n 3 "$log")"; fi
done

# R3, R3b, R4b: one line per seat record: handle task unit role launched spec verdict-seen
while IFS=$'\x1f' read -r h task u role launched spec verdict; do
  [ -n "$h" ] && [ -n "$u" ] && [[ $launched =~ ^[0-9]+$ ]] || continue
  if [ "$role" = builder ]; then
    grep -qxF -- "$task" <<<"$READY" && [ $((NOW - launched)) -gt 180 ] || continue
    if listed "$h"; then
      has R3 "$task" ready && continue
      row R3 "$task" ready
      if try bash "$BIN/dispatch-task.sh" "$task" "terminal:$h" >&2; then said dispatch "$u" "task $task left ready"
      else ask "R3-$task" "recovery failed once: dispatch of $u's task" \
        "The Builder task $task of $u was left ready and its dispatch to pane $h failed; the row is spent, so it is not tried again. Dispatch it by hand or close the unit. $(error)"; fi
    elif ! merged_since "$u" "$launched"; then
      if has R3b "$u" nopane; then has R3b "$u" asked && continue; row R3b "$u" asked; ask "R3b-$u" "recovery failed once: Builder of $u has no pane again" \
        "The Builder of $u (task $task) has no pane again after one relaunch; relaunch it by hand or close the unit."; continue; fi
      row R3b "$u" nopane
      if ! try bash "$BIN/seat.sh" launch builder "$u" "$spec" >&2; then
        row R3b "$u" asked; ask "R3b-$u" "recovery failed once: relaunch of $u's Builder" \
          "The Builder of $u (task $task) has no pane and its relaunch (seat.sh launch builder) failed; the row is spent, so it is not tried again. Relaunch it by hand or close the unit. $(error)"
        continue
      fi
      pp_task_close "$task" failed >/dev/null 2>&1 || echo "recover-stalls: old task $task of $u not closed" >&2
      said "relaunched Builder" "$u" "task $task ready with no pane"
    fi
    continue
  fi
  [ "$verdict" = 0 ] && [ -e "$ST/item-dead-$u-$role-$launched" ] || continue
  ! merged_since "$u" "$launched" || continue # a unit merged since this seat launched is done (pass 18)
  # Once per seat: a relaunched seat's own exit is dead_seats' question, never a second relaunch.
  awk -v u="$u" -v r="$role-" '$1 == "R4b" && $2 == u && index($3, r) == 1 && substr($3, length(r) + 1) ~ /^[0-9]+$/ { f = 1 }
    END { exit !f }' "$ROWS" 2>/dev/null && continue
  case $role in
    plan-*) # the driver's: only once it stopped (its done file), through its own start
      args "$u" || continue
      [ -e "$PP_SCRATCH/unit-loop-$u.done" ] || continue
      RC=0; hs_active "$A_NAME" || RC=$?; [ "$RC" = 1 ] || continue
      act=(start "$u") ;;
    *) [ -n "$spec" ] || continue # dead_seats posts it, naming why
      act=(bash "$BIN/seat.sh" launch "$role" "$u" "$spec") ;;
  esac
  row R4b "$u" "$role-$launched"
  if try "${act[@]}" >&2; then said "relaunched seat $role" "$u" "exited with no verdict"
  else ask "R4b-$u-$role-$launched" "recovery failed once: relaunch of $u's $role seat" \
    "The $role seat of $u exited with no verdict and its relaunch failed; the row is spent, so it is not tried again. Relaunch it by hand or close the unit. $(error)"; fi
done < <(awk -v OFS=$'\x1f' '
  function out() { if (FNR0) print v["handle"], v["task"], v["unit"], v["role"], v["launched"], v["spec"], vd }
  FNR == 1 { out(); split("", v); vd = 0; FNR0 = 1 }
  /^verdict=/ { vd = 1 }
  { i = index($0, "="); k = substr($0, 1, i - 1) }
  i && k ~ /^(handle|task|unit|role|launched|spec)$/ && !(k in v) { v[k] = substr($0, i + 1) }
  END { out() }' "$PP_SCRATCH"/seat-*.txt 2>/dev/null)

# R4
for f in "$PP_SCRATCH"/drive-*.args; do
  [ -e "$f" ] || continue
  u=${f##*/drive-}; u=${u%.args}
  if ! args "$u"; then ask "R4-args-$u" "recovery failed once: driver of $u cannot be restarted" "$f is missing lines; the driver of $u is not restarted."; continue; fi
  RC=0; hs_active "$A_NAME" || RC=$?; [ "$RC" = 1 ] || continue
  [ ! -e "$PP_SCRATCH/unit-loop-$u.done" ] || continue
  # A unit merged since this driver started ended DONE, whatever args file is left (pass 18); the name's suffix is the
  # start's epoch.
  e=${A_NAME##*-}; [[ $e =~ ^[0-9]+$ ]] || e=0
  ! merged_since "$u" "$e" || continue
  o=$(cat "$PP_SCRATCH/drive-$u.owner" 2>/dev/null || true); [ -z "$o" ] || [ "$o" = "$A_NAME" ] || continue
  has R4 "$u" "$A_NAME" && continue
  if grep -q "^R4 $u " "$ROWS" 2>/dev/null; then
    has R4 "$u" "asked-$A_NAME" && continue
    row R4 "$u" "asked-$A_NAME"
    ask "R4-$u" "recovery failed once: driver of $u died again" \
      "The driver $A_NAME of $u died after one restart. Log tail:
$(tail -n 20 "$PP_SCRATCH/scratchpad/$u-drive-${A_NAME##*-}.log" 2>/dev/null)"
    continue
  fi
  row R4 "$u" "$A_NAME"
  if ! try start "$u"; then
    row R4 "$u" "asked-$A_NAME"; ask "R4-$u" "recovery failed once: driver of $u cannot be restarted" \
      "The driver $A_NAME of $u is not running and its restart (unit-drive.sh start) failed; the row is spent, so it is not tried again. Start it by hand or close the unit. $(error)"
    continue
  fi
  said "restarted driver" "$u" "$A_NAME not running"
done
exit 0

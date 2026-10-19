#!/usr/bin/env bash
# orca-wait.sh [--run <id>] -- drain and acknowledge main's Orca inbox, in the
# FOREGROUND. It is main's answer to Orca's "you have N messages" nudge:
# main-watch.sh and the drivers post, Orca's nudge wakes main, main runs this.
# Nothing is ever armed or backgrounded, so nothing can be left unarmed.
#
# WHY A DRAIN. `check` returns the oldest UNACKNOWLEDGED batch, so a delivery
# nobody acknowledged replays on every call and a real worker_done sits behind
# it. This drains and acknowledges everything queued and prints every message
# worth a turn; an unread message is also what keeps Orca nudging.
#
# Prints one line per message: <from> | <subject> | first 200 chars of body
# (a `heads-up:` relay instead prints its whole body, newlines kept, and is
# never filtered as noise). Under that line, indented: the message text
# when the line did not carry all of it (past 60 lines: the file's path with the
# first and last lines), a unit pane's `unit <name>: ...` state and `next: ...`
# step, and for each ruling id the message cites its answer and void state from
# the rulings log, with the .md detail file the message names.
# Then ONE state line and only what main must act on: NEEDS-MAIN lines, pending
# gates, open main-watch item tasks with their ids, one line per active driver.
# --full prints the older wake instead: every open task, each message's
# findings, each stopped driver's log tail. --close <task_id>... completes those
# tasks, one line each, and drains nothing.
# Exit 0 when at least one message was printed, 1 when nothing was queued, 3
# when a message body could not be saved (that delivery is left unacknowledged),
# 4 when Orca refused a check it could not repair (the error is printed).
#
# Each batch is printed BEFORE its acknowledgement, so a kill between the two
# replays the batch to the next drain rather than losing it. Handling is main
# closing the item's task, never this read.
set -uo pipefail

RUN="" FULL=0 CLOSE=()
USAGE="usage: $0 [--run <id>] [--full | --close <task_id>...]"
while [ $# -gt 0 ]; do
  case "$1" in
    --run) RUN=$2; shift 2 ;;
    --full) FULL=1; shift ;;
    --close) shift; [ $# -gt 0 ] || { echo "$USAGE" >&2; exit 2; }; CLOSE=("$@"); break ;;
    *) echo "$USAGE" >&2; exit 2 ;;
  esac
done
for bin in orca-ide jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "orca-wait: $bin is not on PATH." >&2; exit 2; }
done
# Main checkout only: its run-use below would move main's run to a worktree pane
# (the relay pane, a worker) and leave main's inbox empty.
if [ "$(git rev-parse --path-format=absolute --git-dir 2>/dev/null)" != "$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ]; then
  echo "orca-wait: main's inbox only, never from a worktree pane. Read your own: orca-ide orchestration check --wait --terminal <your handle>" >&2
  exit 2
fi
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || exit 1
# board.sh records the project's run here; --run overrides it. With neither, the run
# this pane is bound to is asked for, because the printed-id record below is
# keyed by run and a read with no run has no record.
[ -n "$RUN" ] || RUN=$(tr -d '[:space:]' 2>/dev/null < "$PP_RUN_FILE" || true)
[ -n "$RUN" ] || RUN=$(orca-ide orchestration run-current --json 2>/dev/null | jq -r '.result.run.id // empty' 2>/dev/null)
# BIND EVERY TIME. The pointer file names a run; the RUN names a coordinator
# TERMINAL, and that is what a check reads. Main's pane changes -- a restart, a
# new window -- and the new pane is bound to no run while the pointer file still
# looks right, so the old guard (rebind only when the file disagrees) skipped the
# bind and every check returned empty against a full mailbox. On 2026-09-13 that
# hid an inbox holding a failed unit loop and three finished reviews. run-use is
# idempotent and costs one call, so it runs unconditionally and the run always
# points at whatever pane is main today. Silent when it works: a restarted pane
# printed its rebinding notice over a batch of nothing but replays, and main's
# command captures stderr as well, so that notice alone was a wasted wake.
if [ -n "$RUN" ]; then
  orca-ide orchestration run-use --id "$RUN" >/dev/null 2>&1 \
    || echo "orca-wait: run-use $RUN FAILED; this drain will see nothing" >&2
fi
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
. "$(dirname "${BASH_SOURCE[0]}")/host-services.sh"
SCRATCH=$PP_SCRATCH
WS=$PP_WORKSPACES

# pp_task_close, not a bare task-update: it settles a seat's active dispatch
# first, which a bare update is refused on. Its failure line goes to stderr.
# Each argument is split on whitespace: zsh passes "$ids" as ONE argument, and
# that close closed nothing (2026-10-04).
if [ ${#CLOSE[@]} -gt 0 ]; then
  rc=0
  read -ra CLOSE -d '' <<<"${CLOSE[*]}" || true
  for t in "${CLOSE[@]}"; do if pp_task_close "$t" completed; then echo "closed $t"; else rc=1; fi; done
  exit "$rc"
fi

BASE=(orchestration check)
[ -n "$RUN" ] && BASE+=(--run "$RUN")

# Everything printed; decides the exit code. A heartbeat is never printed.
TOTAL=0 OVER=0

warn_codex_budget() {  # <Orca check JSON> -- Codex panes do not receive Claude hooks.
  local codex_dirs handles handle terms wt created log bytes turns context threshold unit session
  # Same split as read-verdict.sh: the read-only review lane sets
  # CODEX_HOME=~/.codex-review, an implementer pane writes to ~/.codex. One home
  # made this warn about an implementer using a reviewer's session file.
  # CODEX_HOME adds a home and never narrows: an Orca terminal exports Orca's
  # runtime home (a path with a space) while the seats write to ~/.codex.
  codex_dirs=("$HOME/.codex-review/sessions" "$HOME/.codex/sessions" ${CODEX_HOME:+"$CODEX_HOME/sessions"})
  handles=$(printf '%s' "$1" | jq -r '.result.messages[]? | .from_handle // empty' 2>/dev/null | sort -u)
  [ -n "$handles" ] || return 0
  terms=$(orca-ide terminal list --json 2>/dev/null) || return 0
  threshold=$(jq -r '.context // 450000' "${PANE_BUDGET_CONFIG:-$PP_SCRIPTS/../config/pane-budget.json}" 2>/dev/null || echo 450000)
  for handle in $handles; do
    wt=$(printf '%s' "$terms" | jq -r --arg h "$handle" '(.result | if type == "array" then . else (.terminals // []) end)[]? | select(.handle == $h and .agentIdentity == "codex") | .worktreePath' | head -1)
    [ -n "$wt" ] || continue
    created=$(printf '%s' "$terms" | jq -r --arg h "$handle" '(.result | if type == "array" then . else (.terminals // []) end)[]? | select(.handle == $h) | (.createdAt // .created_at // empty)' | head -1)
    log=$(find "${codex_dirs[@]}" -type f -name '*.jsonl' -print 2>/dev/null | while IFS= read -r candidate; do
      start=$(head -1 "$candidate" | jq -r --arg cwd "$wt" 'select(.payload.cwd == $cwd) | (.timestamp // .payload.timestamp // .payload.startedAt // empty)' 2>/dev/null)
      [ -n "$start" ] || continue
      [ -z "$created" ] || [[ "$start" > "$created" || "$start" = "$created" ]] || continue
      printf '%s\t%s\n' "$start" "$candidate"
    done | sort -r | head -1 | cut -f2-)
    [ -n "$log" ] || continue
    # Orca reports no createdAt for a pane, so the `created` filter above never
    # runs and the newest session file for a worktree stays the DEAD pane's
    # until a freshly reseated pane writes its first line. A log nobody is
    # appending to belongs to a finished pane; warning on it told main to
    # reseat a pane thirty seconds old (2026-09-13, C3b2). Thirty minutes was
    # still far too wide: at 22:55 it matched a plan author that stopped at
    # 22:52 and warned about the implementer dispatched at 22:54. A live Codex
    # pane appends every few seconds.
    # ponytail: two-minute liveness window stands in for the pane-to-session
    # binding Orca does not give us; bind by pane id if Orca ever reports one.
    [ -n "$(find "$log" -newermt '-2 minutes' -print -quit 2>/dev/null)" ] || continue
    bytes=$(wc -c < "$log" | tr -d ' '); turns=$(grep -ac '"role":"assistant"' "$log" || true)
    # The rollout file stores every tool output verbatim and never shrinks, so
    # bytes/4 read an implementer that had just cat'd its brief and rules as
    # 243K context when the model was actually sent 56K. Codex records the real
    # per-response figure; the last one is the current context. There is no
    # compaction event in a rollout, and the old `grep -ci compaction` counted
    # the WORD in the seat's own instruction files, so every implementer tripped
    # a limit of 2 on its first turn (2026-09-14, C3c).
    context=$(grep -a '"type":"token_usage_record"' "$log" | tail -1 \
      | jq -r '.payload.usage.input_tokens // empty' 2>/dev/null || true)
    [ -n "$context" ] || context=$((bytes / 4))
    # Context only: no pane is warned for its number of turns.
    if [ "$context" -gt "$threshold" ]; then
      unit=$(basename "$wt")
      session=$(basename "$log")
      echo "orca-wait: warning Codex pane $handle session=$session is over its budget (turns=$turns, context=$context, session-bytes=$bytes); request .claude/briefs/${unit}-handoff.md."
    fi
  done
}

enrich() {  # <Orca check JSON> -- print, under each marker, what main would otherwise fetch in two or three more calls:
  # the sender pane's findings and VERDICT lines, and the tail of the unit's loop log when a loop owns that pane.
  local handles handle terms wt unit log rec launched
  # A heads-up note quoting a marker is a claim, not a seat's report.
  handles=$(printf '%s' "$1" | jq -r '.result.messages[]? | select(.type != "heartbeat") |
    select((.subject // "") | startswith("heads-up:") | not) |
    select((.body // "") | test("-DONE|VERDICT:|PLANFIX|PLAN-DONE")) | .from_handle // empty' 2>/dev/null | sort -u)
  [ -n "$handles" ] || return 0
  terms=$(orca-ide terminal list --json 2>/dev/null) || terms=""
  for handle in $handles; do
    # Two seats in one worktree: without the launch time read-verdict picks a
    # session log by worktree and mtime, so it prints the OTHER seat's verdict.
    # seat.sh records the launch time beside the handle; close-round.sh already
    # passes it. The empty arguments keep read-verdict's own lookups.
    rec=$(grep -lF "handle=$handle" "$SCRATCH"/seat-*.txt 2>/dev/null | head -1)
    launched=0
    [ -n "$rec" ] && launched=$(sed -n 's/.*launched=\([0-9][0-9]*\).*/\1/p' "$rec" | head -1)
    bash "$PP_SCRIPTS/read-verdict.sh" "$handle" 400 "" "" "" "" "" "${launched:-0}" 2>/dev/null \
      | grep -E '^\[P[0-3]\]|^- \[P[0-3]\]|^VERDICT|DONE$' | cut -c1-240 | sed "s/^/  $handle: /"
    wt=$(printf '%s' "$terms" | jq -r --arg h "$handle" '(.result | if type == "array" then . else (.terminals // []) end)[]? | select(.handle == $h) | .worktreePath // empty' 2>/dev/null | head -1)
    [ -n "$wt" ] || continue
    unit=$(basename "$wt")
    log=$(ls -t "$SCRATCH"/scratchpad/"$unit"-{loop,drive}-*.log 2>/dev/null | head -1)
    [ -n "$log" ] || continue
    echo "  loop log $log:"; tail -3 "$log" | sed 's/^/    /'
  done
}

handle_units() {  # {"term_x":"wt1168-retry-runtime", ...} -- every pane that sits in a unit worktree
  # A driver sends its wakes from the MAIN pane handle it inherited, and main's
  # pane is the checkout, not a worktree. So a driver wake is never in this map
  # and always passes the filter below; only a seat's own messages can match.
  local m
  m=$(orca-ide terminal list --json 2>/dev/null | jq -c --arg ws "$WS" "$PP_PNORM"'
    ($ws | pnorm + "/") as $ws
    | [ (.result | if type == "array" then . else (.terminals // []) end)[]? | select(((wtp // "") | pnorm | startswith($ws)))
      | { key: .handle, value: ((wtp | pnorm | ltrimstr($ws)) | split("/")[0]) } ]
    | from_entries' 2>/dev/null)
  [ -n "$m" ] || m='{}'
  printf '%s\n' "$m"
}

driver_units() {  # units whose driver is alive, as a JSON array
  # `|| true`: an unknown state reads as no drivers, and a failed hs_list must
  # not trip the `|| echo '[]'` below into printing a second array.
  { hs_list --no-legend --plain --state=active \
      'loop-*' 'drive-*' 'chain-*' 'run-*.service' || true; } \
    | awk '{n=$1; sub(/\.service$/,"",n); sub(/-[0-9]+$/,"",n); sub(/^[^-]+-/,"",n); print n}' \
    | jq -R . | jq -sc . 2>/dev/null || echo '[]'
}

# WHICH MESSAGES ARE WORTH A TURN. Three rules, all about not waking main twice
# for one event.
#  1. A pane's "turn complete" echo with no marker in its body is noise; this
#     woke main about 250 times in two days (ruling 2026-09-12, token cuts).
#  2. A pane's "turn complete" echo is ALSO noise while a driver is watching
#     that unit, marker or not: the driver sends its own wake at every stage, so
#     main heard the same verdict twice all through 2026-09-15. The unit comes
#     from the subject, "codex turn complete (wt1166-stale-retry)", and a unit
#     with NO live driver still wakes main -- that echo is then the only signal
#     there is.
#  3. A seat's own `worker_done` is noise on the same grounds: the driver waits
#     for that report itself and dispatches the next stage off it, so main has
#     nothing to do with it and hears the outcome again at the driver's next
#     judgment point. The unit comes from the SENDER's worktree, because a
#     worker_done subject is the worker's own prose and names no unit.
#  4. `seat <role> <unit>: <verdict>` is seat.sh narrating each seat's result,
#     and it is sent from the DRIVER's handle, so rule 3 cannot see it -- the
#     sender sits in the checkout, not a worktree. It dates from before
#     unit-drive.sh existed, when main really did hear nothing between dispatch
#     and the driver's exit. A driver now wakes main at every judgment point of
#     its own, so while one is alive this is the same outcome a second time.
#     With no driver it is again the only signal there is. Unit from the subject.
#  5. `<kind> <unit> exit rc=N` is loop-run.sh's wrapper saying the driver
#     process ended. The driver has already sent the wake that says WHY, and
#     this one carries only the tail of the same log, so it lands as a duplicate
#     of the message right before it. A driver that dies sending nothing is
#     main-watch.sh's post of the done file loop-run.sh writes, which is kept.
#  6. Self-test traffic never wakes main, driven or not. The harness runs a
#     fake unit named exactly `u` from two recorded panes, and its wakes reached
#     main all through 2026-09-16. Matched by sender (those panes, or a pane in
#     the `u` worktree) or by `u` as a whole token in each emitter's subject
#     form, so u1209-... stays a real unit and a pane that has since left the
#     listing is still caught.
#  7. A driver FYI (`drive <unit>: FYI ...`: round started, class raised, fixes
#     needed) asks nothing of main, driven or not; its driver log keeps the line
#     (owner ruling 2026-10-01). main-watch.sh never relays one, so this is the
#     only filter that needs the rule.
#  8. A `status` note main itself sent is not news to main. A send to a
#     pane with no dispatch of its own (the the relay pane pane) is addressed to the
#     whole run, so it comes back here. The drivers and main-watch.sh send from
#     main's handle too, but never as `status`, so only main's hand-sent notes
#     match. Orca's refusal of such a send carries its own payload and is kept.
#     With no pane handle in the environment nothing is dropped on a guess.
# None of these rules hides an owner answer: a message citing a ruling id, or from the relay's pane (the one in
# $PP_WORKSPACES/Chief-of-Staff, as to-main.sh finds it), always passes. What they hide goes to hidden.jsonl.
# Everything else passes, including every driver wake and every escalation: an
# escalation is a seat asking for a decision the driver cannot make.
RID_RE='r-[0-9]{8}-[0-9]{6}-[0-9a-z]+-[0-9a-f]{6}'
KEEP='
  def echo_unit: (.subject // "") | ((capture("\\((?<u>[^)]+)\\)") // {u:""}) | .u);
  def seat_unit: (.subject // "") | ((capture("^seat [a-z-]+ (?<u>[^:]+):") // {u:""}) | .u);
  def sender_unit: ($hunits[(.from_handle // "")] // "");
  def driven($u): ($u != "") and (($dunits | index($u)) != null);
  def noisy: ( ((.subject // "") | test("turn complete"))
               and ( (((.body // "") | test("-DONE|VERDICT:|PLANFIX")) | not)
                     or driven(echo_unit) ) )
             or ((.type == "worker_done") and driven(sender_unit))
             or driven(seat_unit)
             or ((.subject // "") | test("^drive [^:]+: FYI "))
             or ((.subject // "") | test(" exit rc=[0-9]+$") and (startswith("main-watch:") | not));
  def harness: ((.from_handle // "") | test("^term_(3d8255b5|1c94009f)(-|$)"))
               or (sender_unit == "u") or (echo_unit == "u")
               or ((.subject // "") | test("^(seat [a-z-]+ (on )?|drive )?u([: ]|$)|(^| )unit=u( |$)"));
  def relay: (.subject // "") | startswith("heads-up:");
  def owner: (((.subject // "") + "\n" + (.body // "")) | test($rid)) or (sender_unit == "Chief-of-Staff");
  def own: ($me != "") and (.type == "status") and ((.from_handle // "") == $me)
           and (((.payload // "") | tostring | contains("_orcaLifecycleRejection")) | not);
  .result.messages[]? | select(.type != "heartbeat") | select(relay or owner or ((noisy | not) and (harness | not) and (own | not)))'
# A heads-up relay (main-watch.sh) is printed whole, newlines kept: its
# text is the note main must verify, and words in it are claims, not signals.
RENDER='if ((.subject // "") | startswith("heads-up:")) then "\(.from_handle // .from // "?") | \(.subject)\n\(.body // "")"
        else [ (.from_handle // .from // "?"),
          (.subject // "(no subject)"),
          ((.body // "") | gsub("[\r\n]+"; " ") | .[0:200]),
          "\($mdir)/\((.id // "") | gsub("[^A-Za-z0-9._-]"; "_")).md" ] | join(" | ") end'
# The summary cuts at 200 characters; the whole body is written here BEFORE the
# ack, and the printed line names the file, so the cut-off part is never lost.
MSGDIR=$SCRATCH/main-watch/messages

# ONE CALL SERVES A WAKE. Main used to follow a wake with a read of the
# message file, a look at the unit and a ruling lookup, one request each. The
# lines below go under the message's own line, which stays exactly as it was:
# the tests and main both key on it. Nothing here asks Orca anything.
. "$PP_SCRIPTS/../hooks/lib/project.sh" && pp_project "$PP_MAIN"
RULINGS=${COMMANDECK_RULING_LOG:-$HOME/.claude/rulings/$PP_PROJECT.jsonl}
bounded() {  # bounded <file> <lines allowed> -- the file indented; past the allowance its path, first and last lines
  # First AND last: a reviewer's verdict is its last line, and a head-only cut hid it.
  # shortcut: the bound counts lines, so one very long line prints whole; cut by characters if a wake ever carries one.
  local n k; n=$(awk 'END { print NR }' "$1" 2>/dev/null); n=${n:-0}
  if [ "$n" -le "$2" ]; then awk '{ print "    " $0 }' "$1"; SHOWN=$n; return 0; fi
  k=$(( $2 / 2 )); [ "$k" -le 15 ] || k=15
  [ "$k" -le 0 ] || awk -v k="$k" 'NR <= k { print "    " $0 }' "$1"
  echo "    [$n lines, $((n - 2 * k)) not shown; whole text: $1]"
  [ "$k" -le 0 ] || tail -n "$k" "$1" | awk '{ print "    " $0 }'
  SHOWN=$((2 * k + 1))
}
serve() {  # serve <message JSON> <pane-to-unit map> <driven units>
  local m=$1 id from type subject unit file wt left=60 SHOWN=0 ahead dirty round verdict why rid row tok path dir ok root nogo p2
  id=$(jq -r '(.id // "") | gsub("[^A-Za-z0-9._-]"; "_")' <<<"$m"); file=$MSGDIR/$id.md
  from=$(jq -r '.from_handle // ""' <<<"$m"); type=$(jq -r '.type // ""' <<<"$m"); subject=$(jq -r '.subject // ""' <<<"$m")
  # The text, unless the first line already carried all of it (a heads-up relay prints its own whole).
  if [[ "$subject" != heads-up:* ]] && { [ "$(wc -c < "$file")" -gt 200 ] || [ "$(awk 'END { print NR }' "$file")" -gt 1 ]; }; then
    bounded "$file" "$left"; left=$((left - SHOWN))
  fi
  # A unit is a worktree that holds its own brief: the Chief-of-Staff pane sits
  # in a worktree too, and a state made up for it would read as a unit's.
  unit=$(jq -r --argjson hunits "$2" '$hunits[.from_handle // ""] // ((.subject // "") | ((capture("\\((?<u>[^)]+)\\)") // {u:""}) | .u))' <<<"$m")
  # A subject is the sender's own words: a name that is a path would walk out of the worktrees directory.
  case "$unit" in */*|.*) unit="" ;; esac
  wt=$WS/$unit
  if [ -n "$unit" ] && [ -f "$wt/.claude/briefs/$unit.md" ]; then
    ahead=$(git -C "$wt" rev-list --count main..HEAD 2>/dev/null); ahead=${ahead:-?}
    dirty=$(git -C "$wt" status --porcelain 2>/dev/null | awk 'END { print NR }')
    round=$(ls "$wt/.claude/briefs/$unit"-r*-reports.md 2>/dev/null | awk -F'-r|-reports' '{ print $(NF-1) "\t" $0 }' | sort -n | tail -1 | cut -f2-)
    verdict=""
    [ -z "$round" ] || verdict="r$(basename "$round" | sed 's/.*-r\([0-9]*\)-reports\.md$/\1/') ($(sed -n 's/^Pass: *//p' "$round" | tail -1)) $(grep '^VERDICT:' "$round" | sort -u | paste -sd' ' -)"
    echo "  unit $unit: $ahead commit$([ "$ahead" = 1 ] || echo s) ahead of main, $dirty file$([ "$dirty" = 1 ] || echo s) uncommitted, last Codex round ${verdict:-none on file}"
    # The next step for the three kinds of wake a unit sends, and no stage machine:
    # a question waits on an answer; anything else merges or does not.
    # Whether it merges is the merge's own check, never the round file read here
    # (that only turns a NO-GO into a fix round): only that check knows a GO that covers an older commit from one
    # that covers the tip, and a NO-GO that is a mergeable P2/P3 tail.
    if { [ "$type" = question ] || [ "$type" = escalation ]; } && [[ "$subject" != *"turn complete"* ]]; then
      echo "  next: it waits for your answer: bash $PP_SCRIPTS_Q/answer-worker.sh $from \"<text>\" $unit-$id"
      # Recorded like an owner's ask, as waiting on main; a replayed message is the same id and adds nothing.
      bash "$PP_SCRIPTS/decision.sh" add "$unit-$id" "$subject: $(jq -r '.body // "" | gsub("\\s+"; " ") | ltrimstr(" ") | rtrimstr(" ") | .[0:300]' <<<"$m")" none "$unit asks" --waits-on main >/dev/null 2>&1 \
        || echo "  (not recorded in the decisions ledger: it is there already, or the ledger refused it)"
    else
      why="" nogo="" p2=""
      if [ "$(jq -r --arg u "$unit" 'index($u) != null' <<<"$3")" = true ]; then why="its driver acts on this; see the driver line below"
      elif [ "$dirty" != 0 ]; then why="$dirty file$([ "$dirty" = 1 ] || echo s) uncommitted, which no Codex pass read"
      # The pass writes its own verdict line last. After a NO-GO the next step is a fix round even when the merge
      # check passes a P2/P3 tail: that merge is the owner's call (issue 212). This line only advises; the merge checks.
      elif [ -n "$round" ] && [ "$(grep '^VERDICT:' "$round" | tail -1)" = "VERDICT: NO-GO" ]; then nogo=1
        [ -f "$PP_SCRIPTS/builder-codex-pass.sh" ] && bash "$PP_SCRIPTS/builder-codex-pass.sh" --verify "$wt" "$unit" HEAD >/dev/null 2>&1 </dev/null && p2=1
      elif [ ! -f "$PP_SCRIPTS/builder-codex-pass.sh" ]; then why="the merge check (builder-codex-pass.sh --verify) is not in this checkout"
      elif ! why=$(bash "$PP_SCRIPTS/builder-codex-pass.sh" --verify "$wt" "$unit" HEAD 2>&1 >/dev/null </dev/null); then
        why=$(printf '%s\n' "$why" | grep . | tail -1 | cut -c1-300); why=${why:-the merge check refused it and gave no reason}
      else why=""
      fi
      if [ -n "$nogo" ]; then echo "  next: fix round: ${verdict%% *} ended NO-GO; the Builder fixes what it found and runs the next pass"
        [ -z "$p2" ] || echo "  the P2-tail rule lets this tip merge with its P2/P3 open: merge only on the owner's word; ask them first"
      elif [ -n "$why" ]; then echo "  next: nothing for main yet: $why"
      else echo "  next: merge it: bash $PP_SCRIPTS_Q/merge-unit-local.sh $unit"
      fi
    fi
  fi
  # A ruling id in a message is a claim until the log agrees: a void row is machine text or a decoy pick, never the owner's word.
  for rid in $(jq -r '[.subject // "", .body // ""] | join("\n")' <<<"$m" | grep -oE "$RID_RE" | sort -u); do
    # Any void value, and a pick made in under two seconds that the owner has not
    # confirmed (ruling-log.sh marks both). An id with one bad row is bad, whichever row is first.
    row=$(jq -rRn --arg id "$rid" '[inputs | fromjson? | select(.id == $id)] | select(length > 0)
      | (if any(.[]; .void) then "VOID, not the owner'"'"'s word"
         elif any(.[]; .pick == "suspect" and (.confirmed | not)) then "SUSPECT, answered in under 2 s and not confirmed by the owner; not their word yet"
         else "stands" end) + "; answer: " + ((.[0].answer // "") | tostring | gsub("\\s+"; " ") | .[0:400])' "$RULINGS" 2>/dev/null)
    echo "  ruling $rid: ${row:-not in the rulings log ($RULINGS)}"
  done
  [ -n "${rid:-}" ] || return 0
  # The detail file a relayed order names. No convention names one, so it is any
  # .md path in the text that exists inside the checkout, the worktrees or the scratch directory.
  for tok in $(jq -r '.body // ""' <<<"$m" | grep -oE '[~A-Za-z0-9_./-]+\.md' | sort -u | head -3); do
    case "$tok" in *..*) continue ;; "~/"*) path=$HOME/${tok#\~/} ;; /*) path=$tok ;; *) path=$ROOT/$tok ;; esac
    [ -f "$path" ] && [ ! -L "$path" ] || continue
    dir=$(cd "$(dirname "$path")" 2>/dev/null && pwd -P) || continue
    # A folder that does not resolve allows nothing: left in, its empty name made the pattern "/*".
    ok=0
    for root in "$ROOT" "$WS" "$SCRATCH"; do
      root=$(cd "$root" 2>/dev/null && pwd -P) && [ "$root" != / ] || continue
      case "$dir/" in "$root"/*) ok=1 ;; esac
    done
    [ "$ok" = 1 ] || continue
    # Never less than its first and last 5 lines, so a long order cannot hide its detail file: a message
    # with three detail files can run to about 95 lines, past the 60.
    [ "$left" -ge 10 ] || left=10
    echo "  detail $tok:"; bounded "$path" "$left"; left=$((left - SHOWN))
  done
}

state_block() {  # once per wake, never per message -- the board main would otherwise fetch by hand
  # WHY THIS IS HERE AND NOT IN board.sh. board.sh is the call for a fresh
  # context that knows nothing. This is the call for a context that knows
  # everything except what changed while it was idle, which is exactly the
  # three facts below. Printing them with the wake is what lets
  # bash-guardrails.sh refuse the separate task-list, terminal list and
  # systemctl status calls: the answer already arrived.
  local units tasks gates next tj gj ids merged
  # Drivers, not panes: a driver is what main is actually waiting on, and a
  # failed one is the state main most needs and least often checks.
  # systemctl prefixes a FAILED unit with a bullet and nothing else, which shifts
  # every column by one; stripping it first is why a failed driver reads as its
  # own name here instead of as a bare bullet.
  # `run-*` needs the .service suffix: a unit-run driver is named run-<unit>-
  # <epoch>, and systemd's own transient scopes and mounts are all run-* too.
  # Without it every unit-run driver was invisible here and main read the empty
  # list as "nothing is running" (2026-09-15, two drivers started on one unit).
  # The stage comes from the driver's own log: the wake then says which step
  # each unit reached, which is the follow-up call main made after every wake.
  # The 8-driver cap is --full's display limit only: the terse wake prints no
  # finished driver, and a cap there hid a live one behind them.
  # The sed strips every leading non-name byte: under a C locale the bullet is
  # three bytes, and a one-character strip shifted every column.
  units=$(hs_list --no-legend --all 'loop-*' 'drive-*' 'chain-*' 'run-*.service' \
    | sed 's/^[^[:alnum:]_.-]*//' \
    | awk '{print $1, $3}' | { if [ "$FULL" = 1 ]; then head -8; else cat; fi; } \
    | while read -r u st; do
        n=${u%.service}; unit=${n%-*}; unit=${unit#*-}
        log=$(ls -t "$SCRATCH/scratchpad/$unit"-*.log 2>/dev/null | head -1)
        if [ "$st" = active ] || [ -z "$log" ]; then
          printf '%s %s%s\n' "$n" "$st" "${log:+ | $(tail -1 "$log" | cut -c1-110)}"
          [ "$st" = active ] || printf '%s\n' "NEEDS-MAIN: $unit driver $st with no log"
          continue
        fi
        # A stopped driver: the next step here, and under --full the log tail
        # too, so main never opens the log to learn what to run.
        if [ "$FULL" = 1 ]; then
          printf '%s %s | log %s\n' "$n" "$st" "$log"
          tail -3 "$log" | cut -c1-200 | sed 's/^/     /'
        fi
        next=$(grep -o 'STOP .*next=.*' "$log" | tail -1 | sed 's/.*next=//')
        # On the Mac a clean finish stays listed as inactive until the next
        # launch boots it out; its DONE line needs nothing from main.
        # A feat(<unit>) commit on main newer than the log means the stop was
        # already merged by hand; the route it names is stale.
        merged=$(git -C "$ROOT" log -1 --format=%ct --fixed-strings --grep="feat($unit)" main 2>/dev/null)
        if tail -1 "$log" | grep -q '^DONE unit='; then :
        elif [ -n "$merged" ] && [ "$merged" -ge "$(stat -c %Y "$log")" ]; then :
        elif [ -n "$next" ]; then
          printf '%s\n' "NEEDS-MAIN: $unit stopped with a route; run: $next"
        elif [ "$FULL" = 1 ]; then
          printf '%s\n' "NEEDS-MAIN: $unit driver $st without a STOP route; read the tail above"
        else
          printf '%s\n' "NEEDS-MAIN: $unit driver $st without a STOP route; read tail -3 $log"
        fi
      done)
  # Each open task's id, status and spec head, not only the count: with the count
  # alone main re-queried task-list after the wake to learn which ones.
  # The terse wake lists only main-watch items: those are the tasks main closes
  # by id, and every other open task belongs to a driver or a seat.
  tj=$(orca-ide orchestration task-list --json 2>/dev/null)
  tasks=$(jq -r --argjson full "$FULL" '[.result.tasks[]? | select(.status != "completed" and .status != "failed")]
      | (length | tostring),
        ((if $full == 1 then .[:10] else map(select((.spec // "") | startswith("main-watch item"))) end)[]
         | "   task \(.id) \(.status) \((.spec // "") | gsub("\\s+"; " ") | .[0:90])")' <<<"$tj" 2>/dev/null)
  gj=$(orca-ide orchestration gate-list --json 2>/dev/null)
  gates=$(jq -r '[.result.gates[]? | select(.status == "pending")] | length' <<<"$gj" 2>/dev/null)
  if [ "$FULL" = 1 ]; then
    echo "-- state: open tasks $(head -1 <<<"${tasks:-?}"), pending gates ${gates:-0}"
    sed -n '2,$p' <<<"$tasks"
    [ -n "$units" ] && printf '   %s\n' "$units"
    return 0
  fi
  echo "-- state: open tasks $(head -1 <<<"${tasks:-?}"), pending gates ${gates:-0}, live drivers $(grep -c '^[^ ]* active' <<<"$units" || true)"
  sed -n '2,$p' <<<"$tasks"
  jq -r '.result.gates[]? | select(.status == "pending") | "   gate \(.id) \((.question // "") | gsub("\\s+"; " ") | .[0:90])"' <<<"$gj" 2>/dev/null
  [ -z "$units" ] || sed 's/^/   /' <<<"$units"
  # The listed items' ids, in listed order, as one command main runs after
  # handling them. Printing it closes nothing.
  ids=$(awk 'NR > 1 { printf "%s%s", s, $2; s = " " }' <<<"$tasks")
  [ -z "$ids" ] || echo "close when handled: bash $PP_SCRIPTS_Q/orca-wait.sh --close $ids"
  return 0
}

# A CHECK ERROR IS NEVER SWALLOWED. With --json Orca prints its error
# object on stdout (ok:false, error.code); stderr is kept too, for the plain
# form's message. A fenced or unbound consumer means some other pane bound the
# run -- a script from a closed main pane did, and this waiter spent 12 minutes
# deaf on 2026-09-19 with the error in /dev/null. That one is repaired: re-bind
# and ask again. Anything else, or a fence straight after a re-bind, is printed
# and ends the drain: a drain that cannot read has read nothing.
ERRF=$(mktemp); trap 'rm -f "$ERRF"' EXIT
REBOUND=0
checked() {  # checked <rc> <stdout> -- 0: use the output; 1: re-bound, ask again; otherwise exits 4
  local code
  code=$(printf '%s' "$2" | jq -r 'select(.ok == false) | .error.code // "unknown"' 2>/dev/null | head -1)
  [ "$1" = 0 ] && [ -z "$code" ] && { REBOUND=0; return 0; }
  if [ -n "$RUN" ] && [ "$REBOUND" = 0 ] && { [ "$code" = consumer_fenced ] || [ "$code" = run_required ] \
       || grep -qiE 'consumer_fenced|run_required|no longer bound to Run|No Run is bound|fenced consumer|consumer has been replaced' "$ERRF"; }; then
    if orca-ide orchestration run-use --id "$RUN" >/dev/null 2>&1; then
      echo "orca-wait: check refused (${code:-see stderr}); re-bound this pane to $RUN and asked again" >&2
      REBOUND=1; return 1
    fi
    echo "orca-wait: check refused (${code:-see stderr}) and run-use $RUN FAILED" >&2
  fi
  echo "orca-wait: check failed rc=$1 code=${code:--}: $(printf '%s' "$2" | jq -r '.error.message // empty' 2>/dev/null) $(tr '\n' ' ' < "$ERRF")" >&2
  exit 4
}

drain() {  # print and acknowledge one FIFO chain of deliveries
  local delivery="" out cnt next dunits hunits kept all
  while :; do
    if [ -n "$delivery" ]; then
      # An acknowledgement is itself a check: it returns the NEXT batch, which
      # is why this is a loop and not two calls. The types filter is deliberately
      # absent here -- a batch may hold a heartbeat beside a worker_done, and a
      # filtered ack would leave the heartbeat queued to replay forever.
      out=$(orca-ide "${BASE[@]}" --ack "$delivery" --timeout-ms 2000 --json 2>"$ERRF")
    else
      out=$(orca-ide "${BASE[@]}" --timeout-ms 2000 --json 2>"$ERRF")
    fi
    # A re-bind fences the old delivery, so the next ask is a plain check.
    checked $? "$out" || { delivery=""; continue; }
    [ -n "$out" ] || break

    # Printed BEFORE the acknowledgement below, so a message is never dropped by
    # an ack that succeeded while the print did not happen.
    # A pane's "turn complete" echo (the Stop hook's rejected worker_done) is
    # printed only when its body carries a marker main acts on; otherwise it is
    # noise that woke main about 250 times in two days (ruling 2026-09-12,
    # token cuts). Acknowledged all the same, so it never replays.
    # Both lookups once per batch, not once per jq: each is a process, and the
    # print and the count must classify the same batch the same way. A batch of
    # nothing but heartbeats needs neither.
    dunits='[]'; hunits='{}'
    if [ "$(printf '%s' "$out" | jq -r '[.result.messages[]? | select(.type != "heartbeat")] | length' 2>/dev/null)" != 0 ]; then
      dunits=$(driver_units); hunits=$(handle_units)
    fi
    # One array feeds every output path and the counter.
    kept=$(printf '%s' "$out" | jq -c --argjson dunits "$dunits" --argjson hunits "$hunits" --arg me "${ORCA_TERMINAL_HANDLE:-}" --arg rid "$RID_RE" "[$KEEP]" 2>/dev/null) || kept='[]'
    # What the rules hid is kept, before the ack as the bodies below are: a hidden owner answer can still be found.
    # Both go in on stdin: as an argument a big batch overflows ARG_MAX (E2BIG) and the drain never acks.
    # shortcut: one append-only file, rotate it per run if it grows past a few MB.
    mkdir -p "$MSGDIR" && { printf '%s\n' "$out"; printf '%s' "${kept:-[]}"; } | jq -cs '[.[0].result.messages[]? | select(.type != "heartbeat")] - .[1] | .[]' >> "$MSGDIR/hidden.jsonl" \
      || { echo "orca-wait: could not save hidden messages to $MSGDIR/hidden.jsonl; not acknowledged"; return 1; }
    all=$(printf '%s' "$out" | jq '[.result.messages[]?] | length' 2>/dev/null) || all=0
    OVER=$((${OVER:-0} + ${all:-0} - $(printf '%s' "${kept:-[]}" | jq length)))
    if [ "${kept:-[]}" != '[]' ]; then
      # An unsaved body is lost past its 200-character line, so its delivery
      # stays unacknowledged and replays on the next drain.
      if ! { mkdir -p "$MSGDIR" && printf '%s' "$kept" | jq -c '.[]' | while IFS= read -r m; do
        jq -j '.body // ""' <<<"$m" > "$MSGDIR/$(jq -r '(.id // "") | gsub("[^A-Za-z0-9._-]"; "_")' <<<"$m").md" || exit 1
      done; }; then
        echo "orca-wait: could not save message bodies to $MSGDIR; not acknowledged"
        return 1
      fi
      while IFS= read -r m; do
        jq -r --arg mdir "$MSGDIR" "$RENDER" <<<"$m"
        serve "$m" "$hunits" "$dunits"
      done < <(printf '%s' "$kept" | jq -c '.[]')
      warn_codex_budget "{\"result\":{\"messages\":$kept}}"
      [ "$FULL" = 0 ] || enrich "{\"result\":{\"messages\":$kept}}"
      cnt=$(printf '%s' "$kept" | jq length)
      TOTAL=$((TOTAL + cnt))
    fi

    next=$(printf '%s' "$out" | jq -r '.result.deliveryId // empty' 2>/dev/null)
    [ -n "$next" ] || break
    # The pointer standing still means the queue is drained; without this the
    # ack of a delivery that refuses to settle loops forever.
    [ "$next" = "$delivery" ] && break
    delivery=$next
  done
}

drain || exit 3
# Orca's banner counts every queued message, the ones the filter passes over too:
# without this line "5 messages" beside 2 printed reads as 3 lost.
[ "$OVER" -le 0 ] || echo "orca-wait: $OVER more message$([ "$OVER" = 1 ] && echo ' was' || echo 's were') acknowledged and not shown (heartbeats, your own status notes coming back from the run, a live driver's seat reports); Orca's banner counts them; all but heartbeats are kept in $MSGDIR/hidden.jsonl."
[ "$TOTAL" -gt 0 ] && { state_block; exit 0; }
echo "orca-wait: nothing was queued."
exit 1

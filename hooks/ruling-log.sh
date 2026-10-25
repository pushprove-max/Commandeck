#!/usr/bin/env bash
# PostToolUse (AskUserQuestion) and UserPromptSubmit hook: log every answer
# The owner gives, with the clock it happened at.
#
# WHY: on 2026-09-18 a memory note dated a ruling 00:15 ET; the transcript
# shows 02:05 ET. The time was invented and the note was then used as settled
# law. This log is what a "owner ruling" line cites (ruling:r-<id>), and
# ruling-cite-gate.sh blocks a memory or rule line whose id is not in it.
#
# One JSONL row per answer, outside the repo so worktrees share one log.
# AskUserQuestion prints one short line with the id(s); a prompt prints nothing.
# COMMANDECK_RULING_LOG relocates the log for the self-test.
# Ids are r-<ET second>-<question number or p>-<6 random hex>: every worktree
# shares this log, and two answers can land in one second from one session or
# from two, so the second alone is not an id.
. "${BASH_SOURCE[0]%/*}/lib/project.sh" && pp_project
LOG="${COMMANDECK_RULING_LOG:-$HOME/.claude/rulings/$PP_PROJECT.jsonl}"
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# A failed mkdir falls through: the append then fails and says so.
mkdir -p "$(dirname "$LOG")" 2>/dev/null
# A row can be hundreds of KB and an append that size is not one write, so two hooks at once interleaved into one
# damaged line. Every append holds flock on the log itself; a lock not taken in 10 s fails like any failed write.
append_log() { { flock -w 10 9 && printf '%s\n' "$1" >&9; } 9>>"$LOG"; } 2>/dev/null

EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
case "$EVENT" in UserPromptSubmit|PostToolUse) ;; *) exit 0 ;; esac
# Machine text arrives as a prompt too. Hook feedback and local-command text
# are not logged at all; notifications and Orca banners are logged void below.
[ "$EVENT" = UserPromptSubmit ] \
  && printf '%s' "$INPUT" | jq -e '.prompt | test("^\\s*(<(local-command-|user-prompt-submit-hook)|[A-Za-z]+ hook (feedback|error))")' \
    >/dev/null 2>&1 && exit 0
# Nor is a slash command: since Claude Code 2.1.299 it arrives as typed ("/handoff now"), and it answers no ask.
# A command is told by its name: a plugin's (name:skill), a skill or command on
# this machine, or a built-in. Any other "/word" ("/tmp is the one") is the owner's words.
# shortcut: the built-ins are a fixed list; one Claude Code adds later is logged until it is added here.
CMD=$(printf '%s' "$INPUT" | jq -r '.prompt // "" | capture("^\\s*/(?<c>[A-Za-z0-9:_-]+)(\\s|$)").c // empty' 2>/dev/null)
if [ "$EVENT" = UserPromptSubmit ] && [ -n "$CMD" ]; then
  case $CMD in
    *:*|add-dir|agents|bug|clear|compact|config|context|cost|doctor|effort|exit|export|fast|help|hooks|ide|init|login|logout|loop|mcp|memory|model|permissions|plan|plugin|resume|review|rewind|status|statusline|usage|vim) exit 0 ;;
  esac
  P=${CLAUDE_PROJECT_DIR:-$PWD}
  for d in "$(dirname "${BASH_SOURCE[0]}")/../skills/$CMD" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/$CMD" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/commands/$CMD.md" "$P/.claude/skills/$CMD" "$P/.claude/commands/$CMD.md"; do
    [ ! -e "$d" ] || exit 0
  done
  ! compgen -G "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/*/*/*/skills/$CMD" >/dev/null && ! compgen -G "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/*/*/*/commands/$CMD.md" >/dev/null || exit 0
fi

# The event's arrival time, read before anything that can wait on the ledger
# lock: a prompt answers only asks stamped no later than its arrival second.
NOW=$(date +%s)
UTC=$(date -u -d "@$NOW" +%Y-%m-%dT%H:%M:%SZ)
ET=$(TZ=America/New_York date -d "@$NOW" '+%Y-%m-%d %H:%M:%S %Z')
STAMP=$(TZ=America/New_York date -d "@$NOW" +%Y%m%d-%H%M%S)
RND=$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')

# The open decisions-ledger rows this answer may close: main only, like the
# adds, so a worker's or reviewer's ask or prompt never closes main's rows.
# Empty outside main.
# ponytail: ledger stamps are whole seconds, so an ask appended in the prompt's
# own arrival second while this read waits on the lock closes too; exact order
# needs sub-second askedAt stamps.
DECIDE="${BASH_SOURCE[0]%/*}/../scripts/decision.sh"
OPEN_ROWS=$(
  [ "${COMMANDECK_REVIEWER:-}" != 1 ] || exit 0
  # startup-size.sh (the doctor) runs this on a made-up prompt only to measure it: that prompt answers nothing.
  [ "${COMMANDECK_MEASURE:-}" != 1 ] || exit 0
  root=${CLAUDE_PROJECT_DIR:-$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)}
  gitdir=$(git -C "${root:-.}" rev-parse --path-format=absolute --git-dir 2>/dev/null) || exit 0
  [ "$gitdir" = "$(git -C "${root:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ] || exit 0
  rows=$(bash "$DECIDE" list 2>/dev/null) || rows='[]'
  jq -c 'map(select(.answeredAt == null))' <<<"$rows" 2>/dev/null || echo '[]'
)

# Close the rows the owner has answered, or the Needs Owner card keeps answered asks
# open. $@ = jq args and a program over $open (OPEN_ROWS) that emits
# [id, answer, matched]; an unmatched one is logged. The askedAt of the row
# read is passed on, so a row reopened since the read is refused. Never blocks.
answer_decisions() {
  local row id dlog
  [ -n "$OPEN_ROWS" ] || return 0
  dlog="$(dirname "$LOG")/ask-records-decision.log"
  printf '%s' "$INPUT" | jq -c -L "${BASH_SOURCE[0]%/*}/lib" --argjson open "$OPEN_ROWS" "$@" 2>/dev/null |
  while IFS= read -r row; do
    id=$(jq -r '.[0]' <<<"$row")
    if [ "$(jq -r '.[2]' <<<"$row")" != true ]; then
      printf '%s no open decision %s asking this question\n' "$UTC" "$id" >> "$dlog" 2>/dev/null
    elif ! err=$(bash "$DECIDE" answer "$id" "$(jq -r '.[1]' <<<"$row")" --asked-at "$(jq -r --arg id "$id" '.[] | select(.id == $id) | .askedAt' <<<"$OPEN_ROWS")" 2>&1 >/dev/null); then
      printf '%s %s\n' "$UTC" "$err" >> "$dlog" 2>/dev/null
    fi
  done
}

case "$EVENT" in
  UserPromptSubmit)
    # The log holds the owner's rulings: a prompt is logged only from main's checkout or the Chief-of-Staff
    # worktree (the relay, found as cos-own-echo.sh finds it), the panes the owner types in. Builders', reviewers' and
    # Codex passes' prompts are the orchestrator's words. ruling-log-archive.sh keeps the same panes' rows.
    [ "${COMMANDECK_REVIEWER:-}" != 1 ] || exit 0
    root=${CLAUDE_PROJECT_DIR:-$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)}
    gitdir=$(git -C "${root:-.}" rev-parse --path-format=absolute --git-dir 2>/dev/null) || exit 0
    [ "$gitdir" = "$(git -C "${root:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ] \
      || [ "$(basename "$(git -C "${root:-.}" rev-parse --show-toplevel 2>/dev/null)")" = Chief-of-Staff ] || exit 0
    # Machine text (lib/ruling-typed.jq: notification blocks, Orca banners, the checkpoint resume, main-watch's
    # wakes, known machine preambles) is not the owner, so it is not logged: no ruling, and it answers no ask. Any
    # other text beside it, or quoting it, is the owner's reply. The resume prompt matches only as the whole command
    # lib/context-clear-restart.sh types, and the wakes scripts/main-watch.sh types the same way: whole, the refusal
    # reason bounded to its one line by the fixed text around it, and only the endings wake() builds.
    PROW=$(printf '%s' "$INPUT" | jq -c -L "${BASH_SOURCE[0]%/*}/lib" --arg id "r-$STAMP-p-$RND" --arg utc "$UTC" --arg et "$ET" '
      include "ruling-typed";
      select((.prompt // "") != "" and (.prompt | machine_prompt | not))
      | {id:$id, utc:$utc, et:$et, session:.session_id, cwd:.cwd, source:"prompt",
         question:null, answer:.prompt, annotations:null, pick:"prompt"}' 2>/dev/null) \
      || { HOOK_FIRE_ADVISE=1; echo "ruling NOT logged: this prompt could not be read as typed text or machine text. It has no id to cite."; exit 0; }
    [ -n "$PROW" ] || exit 0
    append_log "$PROW" \
      || { HOOK_FIRE_ADVISE=1; echo "ruling NOT logged: could not write $LOG. This prompt has no id to cite."; exit 0; }
    # The owner's prompt answers a plain-chat ask put to them before it only when it names that decision: an
    # unrelated line, or one typed in another session, closed every open ask. Named = the id, or the id without
    # its -YYYY-MM-DD day, as whole words in any case and spacing. A picker row waits for its own PostToolUse
    # answer; a Builder's question waiting on main is answered by answer-worker.sh, never in chat.
    answer_decisions --arg utc "$UTC" --arg pid "r-$STAMP-p-$RND" '
      def words: ascii_downcase | "-\(gsub("[^a-z0-9]+"; "-"))-";
      (.prompt | words) as $said
      | $open[] | select(.source != "AskUserQuestion" and .waitsOn != "main" and .askedAt <= $utc
          and ((.id | sub("-[0-9]{4}-[0-9]{2}-[0-9]{2}$"; "") | words) as $k | $said | contains($k)))
      | [.id, "answered in chat (\($pid))", true]'
    exit 0 ;;
esac

# Latency from the open time worker-ask-guard.sh stamped. Under 2 s
# the answer may be an Orca nudge typed into the open picker, but the owner has
# answered that fast himself, so the row is marked suspect, never voided.
OPEN="$(dirname "$LOG")/ask-open"
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
LAT=null
# The ledger row's id carries the day the question was asked, so an answer
# given after midnight still finds it.
DAY=$(date -d "@$NOW" +%Y-%m-%d)
if [ -n "$SID" ] && [ -f "$OPEN/$SID" ]; then
  T0=$(cat "$OPEN/$SID" 2>/dev/null); rm -f "$OPEN/$SID"
  [[ "$T0" =~ ^[0-9]+$ ]] && LAT=$(( $(date +%s%3N) - T0 )) && DAY=$(date -d "@$((T0 / 1000))" +%Y-%m-%d)
fi
# A picker that never answered leaves its stamp behind.
find "$OPEN" -type f -mmin +1440 -delete 2>/dev/null

# The answer is a label, a comma-joined list of labels (multiSelect), or text
# The owner typed. "(Recommended)" is how a brief marks the suggested option. A
# whole-label match comes first: a label may itself hold ", ".
# The decoy is what a stray Enter picks, so the owner chose nothing: the
# row is voided whoever picked it, and it closes no decision. So is an empty answer.
. "${BASH_SOURCE[0]%/*}/lib/ask-decoy.sh"
ROWS=$(printf '%s' "$INPUT" | jq -c --arg stamp "$STAMP" --arg rnd "$RND" --arg utc "$UTC" --arg et "$ET" --argjson lat "$LAT" --arg decoy "$ASK_DECOY" '
  . as $in | ($in.tool_response // {}) as $r
  | ($r.questions // $in.tool_input.questions // []) | to_entries[]
  | .key as $k | .value as $q
  | ($q.options // [] | map(.label)) as $labels
  | (($r.answers // $in.tool_input.answers // {})[$q.question] // "") as $a
  | ($a | split(", ")) as $parts
  | {id:"r-\($stamp)-\($k + 1)-\($rnd)", utc:$utc, et:$et, session:$in.session_id, cwd:$in.cwd,
     source:"ask", question:$q.question, answer:$a,
     annotations:(($r.annotations // $in.tool_input.annotations // {})[$q.question]),
     latency_ms:$lat,
     pick:(if ($parts | index($decoy)) then "auto"
           elif $lat != null and $lat < 2000 then "suspect"
           elif ($labels | index($a)) and ($a | test("\\(Recommended\\)")) then "recommended"
           elif ($labels | index($a)) or (($parts | all(. as $p | $labels | index($p))) and $a != "") then "option"
           else "typed" end)}
  | if .pick == "auto" or .answer == "" then .void = true else . end' 2>/dev/null)
[ -n "$ROWS" ] || exit 0
# An id is only announced once it is on disk: a note citing an id the log
# never received would then fail the gate with no way back to the answer.
if ! append_log "$ROWS"; then
  HOOK_FIRE_ADVISE=1
  jq -cn --arg m "ruling NOT logged: could not write $LOG. Record the answer by hand; there is no id to cite." \
    '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$m}}'
  exit 0
fi
# Each answered question closes the row ask-records-decision.sh opened for it
# (same id rule). A same-day reused header names an older row asking something
# else: that row is not this answer's, so the question must match too.
answer_decisions --argjson rows "$(printf '%s\n' "$ROWS" | jq -s .)" --arg day "$DAY" '
  include "decision-id";
  . as $in | (($in.tool_response // {}).questions // $in.tool_input.questions // []) | to_entries[]
  | $rows[.key] as $row | select($row.answer != "" and $row.void != true)
  | (.value | decision_id($day)) as $id | (.value.question // "") as $q
  | [$id, "\($row.answer) (\($row.id))", any($open[]; .id == $id and .question == $q)]'
MSG="ruling logged: $(printf '%s\n' "$ROWS" | jq -r '"\(.id) (\(.pick))"' | paste -sd, - | sed 's/,/, /g')"
[ "$LAT" != null ] && [ "$LAT" -lt 2000 ] && HOOK_FIRE_ADVISE=1 && MSG="$MSG
This answer came back in under 2 s and may be an Orca nudge, not the owner. Confirm it with the owner in plain chat before acting on it."
printf '%s\n' "$ROWS" | jq -e 'select(.pick == "auto")' >/dev/null 2>&1 && HOOK_FIRE_ADVISE=1 && MSG="$MSG
The owner did not answer; ask again. The decoy was picked (a stray Enter, or the owner choosing it), so that answer is void."
# Issue 232: an empty answer (a multi-question picker that came back blank) is void too, and no ruling.
printf '%s\n' "$ROWS" | jq -e 'select(.void == true)' >/dev/null 2>&1 && HOOK_FIRE_ADVISE=1 && MSG="$MSG
The answer came back empty; ask it once more as a single question."
jq -cn --arg m "$MSG" '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$m}}'

#!/usr/bin/env bash
#
# read-verdict.sh — print the selected report with source and incomplete-result
# diagnostics.
#
# Why this exists (ruling 2026-08-31): a reviewer's accumulated buffer runs
# to ~189 KB, and reading it through the terminal tool puts the whole thing in
# main's context to recover about forty useful lines. Worse, the buffer is
# interleaved with TUI spinner repaints, so a naive grep finds nothing and the
# reader concludes the review was lost -- which has twice cost a real lens on a
# high-blast unit.
#
# Fetch and filter outside the context window, retaining report text and
# source/status diagnostics.
#
# Usage: scripts/read-verdict.sh <terminal-handle> [lines-before-verdict]
#        [worktree-path] [agent] [unit] [model] [verdict-ordinal] [launched-epoch]
#        scripts/read-verdict.sh --repeat-class <round file>   (see below)
#        scripts/read-verdict.sh --seat <unit> <role>   (the report seat.sh collect kept)
# The extra arguments bind a round to the reviewer session review-round.sh
# launched. They are optional for interactive use and old handles files.
#
# Prefer eligible structured session logs; otherwise read the accumulated
# buffer, with an explicitly reported screen fallback. An unfinished result
# remains incomplete.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail

HANDLE="${1:-}"
CONTEXT_LINES="${2:-120}"

if [ -z "$HANDLE" ]; then
  echo "usage: $0 <terminal-handle> [lines-before-verdict]" >&2
  echo "  find handles with: orca-ide terminal list --json" >&2
  exit 2
fi

# jq is needed on every path. orca-ide is NOT: a caller that passes the worktree
# and agent (arguments 3 and 4) reads a session log off disk and never touches
# Orca, which is how the local-checks lane runs -- systemd-run gives it no
# ~/.local/bin, so demanding the binary here failed a test that needs no Orca.
# fetch() below asks for it at the one place that does.
command -v jq >/dev/null 2>&1 || { echo "read-verdict: jq is not on PATH." >&2; exit 2; }

# ---------------------------------------------------------------------------
# WORKER STATE: is this worker's current turn over, with nothing left running?
# Every waiter asks this one reader (unit-loop.sh wait_worker, seat.sh launch and
# wait, and the exit-5 check below), because a terminal marker, screen paint and
# Orca's dispatch status each went missing on some path: u1218's injected fix
# ended its turn with its marker on 2026-09-17 and its driver waited on a null
# dispatch and a blank Claude buffer.
#
#   read-verdict.sh --state --worktree <wt> [--agent claude|codex] [--task <id>]
#                   [--launched <epoch>] [--marker <text>] [--spec <path>] [--current]
#   --current binds a pane's session: with --agent, the session of that kind
#   written to last, review-pass sessions left out.
#
# Prints key=value lines: state=running|complete|unknown, reason, marker=0|1
# (the current response's last line is the marker), outstanding=<command ids>,
# overdue=<id>:<minutes>m,
# idle_since, idle_seconds, stalled=0|1, session, provider. Always exits 0.
#
# A turn ends only at Claude's `turn_duration` (a Stop-hook reply after
# `end_turn` is another turn) or Codex's `task_complete`/`turn_aborted`. A
# background command stays outstanding past its turn until its own completion
# record; for Claude it also stops counting once its .output is unheld, held
# only by an orphan, or older than seat-liveness.backgroundMaxMinutes in
# routing.json (then overdue=<id>:<minutes>m). Idle is a completed turn with
# nothing outstanding; anything missing,
# torn or ambiguous is unknown, never idle.
#
# first_turn_stall=1 is a Claude session idle with NO tool call since its
# prompt and no marker or verdict: the seat never started, so waiters
# wake main now instead of at the stall line. The grace lets the typed `go`
# (seat-go.sh) start its turn first. last_message is its last words, one line.
STALL_IDLE_SECONDS=300
FIRST_TURN_GRACE_SECONDS=60

STATE_JQ_DEFS='
def ts: ((.timestamp // "") | sub("\\.[0-9]+Z$"; "Z") | (fromdateiso8601? // null));
def lastline: ((split("\n") | map(select(test("\\S"))) | last) // "") | gsub("^[\\s*`_]+|[\\s*`_]+$"; "");
def result: (.out | keys) as $o
  | if .bad then {state:"unknown", reason:"partial record"}
    elif (.bound | not) then {state:"unknown", reason:"no assignment in this session"}
    elif .turns == 0 or .start == null then {state:"unknown", reason:"no turn"}
    elif .done == null then {state:"running", outstanding:$o, out:.out}
    else {state:"complete", outstanding:$o, out:.out, marker:.marker, message:.message, tools:.tools,
          idle_base:([.done, (.retired // 0)] | max)}
    end;
def init: {bad:false, bound:($task == ""), start:null, done:null, turns:0, out:{}, retired:null, marker:false, message:null, tools:0};
'
# ponytail: Codex background sessions are seen only through "Process running with
# session ID"; a code-mode exec that never prints its session id reads as idle.
STATE_JQ_CODEX='
reduce (inputs | (fromjson? // {_bad:true})) as $r (init;
  ($r | ts) as $at | ($r.payload // {}) as $p |
  if $r._bad then .bad = true
  elif $r.type == "event_msg" and $p.type == "task_started" then
    .start = $at | .done = null | .turns += 1 | .marker = false | .message = null
  elif $r.type == "event_msg" and ($p.type == "task_complete" or $p.type == "turn_aborted") then
    (if .start == null then .start = $at | .turns += 1 else . end) | .done = $at
    | if .bound and ($p.last_agent_message | type) == "string"
      then .message = $p.last_agent_message | .marker = (($p.last_agent_message | lastline) == $marker) else . end
  elif $r.type == "event_msg" and $p.type == "item_completed" and $p.item.type == "CommandExecution" then
    (($p.item.process_id // "") | tostring) as $id
    | if (.out | has($id)) then del(.out[$id]) | .retired = $at else . end
  elif $r.type == "response_item" and $p.type == "message" and $p.role == "user" then
    if $task != "" and ([$p.content[]? | .text? // empty] | join("\n") | contains($task))
    then .bound = true | .marker = false else . end
  elif $r.type == "response_item" and $p.type == "message" and $p.role == "assistant" then
    ([$p.content[]? | select(.type == "output_text") | .text] | join("\n")) as $t
    | if .bound and ($t | test("\\S")) then .marker = (($t | lastline) == $marker) else . end
  elif $r.type == "response_item" and ($p.type == "function_call_output" or $p.type == "custom_tool_call_output") then
    # Codex prints the line in its own header, ahead of "Output:"; the same
    # words inside the command output are something the command printed.
    reduce ([($p.output | tostring | split("\nOutput:")[0]) | scan("(?m)^Process running with session ID ([0-9]+)\\s*$") | .[0]][]) as $id (.; .out[$id] = $at)
  else . end) | result'
STATE_JQ_CLAUDE='
def text: if (.message.content | type) == "string" then .message.content
  else [.message.content[]? | select(.type == "text") | .text] | join("\n") end;
# The api-request rows of Claude Code 2.1.300, a third or more of a long log, hold no
# state: skipped unparsed, so one being written is no partial record.
reduce (inputs | select(startswith("{\"type\":\"api-request") | not) | (fromjson? // {_bad:true})) as $r (init;
  ($r | ts) as $at | ($r.toolUseResult | if type == "object" then . else {} end) as $u |
  if $r._bad then .bad = true
  elif $r.type == "user" and ($r.isCompactSummary != true)
       and (($r.message.content | type) == "string" or any($r.message.content[]?; .type == "text")) then
    ($r | text) as $t
    | (if $task != "" and ($t | contains($task)) then .bound = true else . end)
    | .start = $at | .done = null | .turns += 1
    # A real prompt starts new work; a Stop-hook reply or a task notification
    # continues the same assignment, so only a real prompt clears the marker.
    | (if $r.isMeta != true and ($t | startswith("<task-notification>") | not) then .marker = false else . end)
    | if ($t | test("<status>(completed|failed|killed|stopped)</status>"))
      then reduce ([$t | scan("<task-id>([^<]+)</task-id>") | .[0]][]) as $id (.; del(.out[$id]) | .retired = $at)
      else . end
  # A completion that lands mid-turn is a queued_command attachment, not a user
  # prompt: it retires its command but starts no turn and keeps the marker.
  elif $r.type == "attachment" and $r.attachment.type? == "queued_command" then
    (($r.attachment.prompt // "") | tostring) as $t
    | if ($t | test("<status>(completed|failed|killed|stopped)</status>"))
      then reduce ([$t | scan("<task-id>([^<]+)</task-id>") | .[0]][]) as $id (.; del(.out[$id]) | .retired = $at)
      else . end
  elif $r.type == "user" then
    (if ($u.backgroundTaskId | type) == "string"
     then .out[$u.backgroundTaskId] = {at:$at,
       path:([$r.message.content | tostring | scan("Output is being written to: ([^\\s\"]+?\\.output)") | .[0]][0] // "")}
     else . end)
    | if ($u.task_id | type) == "string" and ($r.message.content | tostring | test("Successfully stopped"))
      then del(.out[$u.task_id]) | .retired = $at else . end
  elif $r.type == "assistant" then
    ($r | text) as $t
    | (if .bound then .tools += ([$r.message.content[]? | select(.type? == "tool_use")] | length) else . end)
    | if .bound and ($t | test("\\S")) then .marker = (($t | lastline) == $marker) | .message = $t else . end
  elif $r.type == "system" and $r.subtype == "turn_duration" then
    if .start != null then .done = $at else . end
  else . end) | result'

session_state() { # provider file task marker -- one JSON object
  local prog=$STATE_JQ_CLAUDE
  [ "$1" = codex ] && prog=$STATE_JQ_CODEX
  jq -ncR --arg task "$3" --arg marker "$4" "$STATE_JQ_DEFS $prog" 2>/dev/null < "$2" \
    || echo '{"state":"unknown","reason":"unreadable log"}'
}

claude_ancestor() { # pid -- true when a running claude process is among its ancestors
  local p=$1
  local c
  # ps, not /proc: macOS has no /proc, and its comm is the full executable path.
  while p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ') && [ "${p:-0}" -gt 1 ]; do
    c=$(ps -o comm= -p "$p" 2>/dev/null) && [ "${c##*/}" = claude ] && return 0
  done
  return 1
}

# Empty output is "no holders" only from a tool that answered: exit 0, or exit 1
# with nothing on either stream. Anything else (missing tool, macOS's BSD fuser
# rejecting a bare path with a usage line) is no answer, so the next tool is
# tried and the caller reports unknown when none answers.
file_holders() { # path -- pids holding it open; fails when no tool could answer
  local tool out err rc
  err=$(mktemp) || return 1
  for tool in "lsof -t" fuser; do
    rc=0; out=$($tool "$1" 2>"$err") || rc=$?
    # GNU fuser names the path on stderr alongside the pids it found.
    if [ "$rc" -eq 0 ] || { [ "$rc" -eq 1 ] && [ -z "$out" ] && [ ! -s "$err" ]; }; then
      rm -f "$err"; printf '%s\n' "$out"; return 0
    fi
  done
  rm -f "$err"; return 1
}

# Every Codex home a seat may have written to. CODEX_HOME adds a home, never
# narrows the search: an Orca 1.4.220 terminal exports Orca's own runtime home,
# drivers inherit it, and the seats still write to ~/.codex, so narrowing found
# no session and every plan-author wait hung (2026-10-04). The cwd, model and
# launch filters pick the seat's log. One path per line: Orca's path has a space.
# COMMANDECK_SEAT_CODEX_HOME is the home a seat's role is routed to (codexHome; seat.sh sets it from the record).
codex_session_dirs() {
  local h
  for h in "$HOME/.codex-review" "$HOME/.codex" "${CODEX_HOME:-}" "${COMMANDECK_SEAT_CODEX_HOME:-}"; do
    h=${h%/}; [ -z "$h" ] || printf '%s\n' "$h/sessions"
  done | awk '!seen[$0]++'
}

log_created() { # file -- epoch of the first timestamped record, else mtime
  local c; c=$(jq -r 'select(.timestamp != null) | .timestamp' "$1" 2>/dev/null | head -1)
  [ -n "$c" ] && date -d "$c" +%s 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

# given_spec <session log> <spec> [regex] -- 0 when a prompt in the log names
# the spec (and, with a regex, matches it).
# Only a prompt hands a session its task: a sibling that read the spec has its
# path in a command's output, and that is not an assignment. jq reads all of
# head's output, so no early exit breaks the pipe under pipefail.
given_spec() {
  head -n 2000 "$1" 2>/dev/null | jq -Rne --arg s "$2" --arg re "${3:-}" '
    [inputs | fromjson?
     | (select(.type == "response_item" and .payload.type == "message" and .payload.role == "user") | .payload.content),
       (select(.type == "user") | .message.content)
     | if type == "string" then . else (.[]? | select(.type == "text" or .type == "input_text") | .text) end
     | strings | contains($s) and test($re)] | any' >/dev/null 2>&1
}
worker_state() {
  local wt="" agent="" task="" launched=0 marker="" spec="" current="" f created best="" best_at="" matches=0 json
  while [ $# -gt 0 ]; do
    case "$1" in
      --worktree) wt=${2:-}; shift 2 ;;
      --agent) agent=${2:-}; shift 2 ;;
      --task) task=${2:-}; shift 2 ;;
      --launched) launched=${2:-0}; shift 2 ;;
      --marker) marker=${2:-}; shift 2 ;;
      --spec) spec=${2:-}; shift 2 ;;
      --current) current=1; shift ;;
      *) echo "usage: $0 --state --worktree <wt> [--agent claude|codex] [--task <id>] [--launched <epoch>] [--marker <text>] [--spec <path>]" >&2; exit 2 ;;
    esac
  done
  [[ "$launched" =~ ^[0-9]+$ ]] || launched=0
  if [ -z "$task" ] && [ "$launched" -eq 0 ] && [ -z "$current" ]; then
    printf 'state=unknown\nreason=no task id or launch time to bind a session\n'; return
  fi
  local candidates=()
  if [ -n "$wt" ] && { [ "$agent" = claude ] || [ -z "$agent" ]; }; then
    # Claude Code's own folder name: every non-alphanumeric byte becomes "-" (pp_slug; paths.sh is not sourced yet).
    for f in "$HOME/.claude/projects/$(printf '%s' "$wt" | tr -c 'A-Za-z0-9' '-')"/*.jsonl; do
      [ -f "$f" ] && candidates+=("claude $f")
    done
  fi
  if [ -n "$wt" ] && { [ "$agent" = codex ] || [ -z "$agent" ]; }; then
    local dirs newer=()
    mapfile -t dirs < <(codex_session_dirs)
    [ "$launched" -eq 0 ] || newer=(-newermt "@$launched")
    while IFS= read -r f; do
      head -n 2000 "$f" | jq -e --arg cwd "$wt" 'select((.type == "session_meta" or .payload.type == "session_meta") and .payload.cwd == $cwd)' >/dev/null 2>&1 \
        && candidates+=("codex $f")
    done < <(find "${dirs[@]}" -type f -name '*.jsonl' "${newer[@]}" -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2- | head -40)
  fi
  # BIND TO THE ASSIGNMENT, never to whichever log holds a marker. A task id binds
  # the session whose prompt carries it (a warm session predates its task, so no
  # creation cutoff); a seat binds the first session started after its launch
  # that was handed its spec (--spec).
  local c
  for c in "${candidates[@]}"; do
    f=${c#* }
    if [ -n "$task" ]; then
      grep -qF "$task" "$f" 2>/dev/null || continue
      json=$(session_state "${c%% *}" "$f" "$task" "$marker")
      [ "$(jq -r '.reason // ""' <<<"$json")" = "no assignment in this session" ] && continue
      matches=$((matches + 1)); best=$c
    elif [ -n "$current" ]; then
      # The session a pane is in now is the one of its own kind (--agent) written
      # to last: a restarted pane leaves its old session's log, and its finished
      # turn, behind. A pass script's review, Codex's or Claude's, runs in the Builder's worktree
      # and is never a pane's session. Two panes of the same kind in one worktree
      # cannot be told apart this way; binding to the pane's own process (the log
      # its process holds open) is the upgrade if that ever happens.
      ! given_spec "$f" "" 'Reviewer [1-9] of [1-9], round [1-9][0-9]*\.' || continue
      created=$(stat -c %Y "$f" 2>/dev/null || echo 0)
      if [ -z "$best_at" ] || [ "$created" -gt "$best_at" ]; then best=$c; best_at=$created; fi
      matches=1
    elif [ "$launched" -gt 0 ]; then
      created=$(log_created "$f")
      [ "$created" -ge "$launched" ] || continue
      # Two seats share a worktree: the first session after launch can be the
      # sibling's, so a seat's spec picks its own from among them.
      [ -z "$spec" ] || given_spec "$f" "$spec" || continue
      if [ -z "$best_at" ] || [ "$created" -lt "$best_at" ]; then best=$c; best_at=$created; fi
      matches=1
    fi
  done
  if [ "$matches" -ne 1 ]; then
    printf 'state=unknown\nreason=%s sessions match\n' "$matches"; return
  fi
  f=${best#* }
  json=$(session_state "${best%% *}" "$f" "$task" "$marker")
  # A Claude background command the log never saw finish is busy only while it
  # is plausibly still the seat's work: a process holds its .output open,
  # that holder descends from a running claude (an orphan re-parented to init
  # belongs to no session), and it is younger than the configured maximum age.
  # A hung command fails the age test and is reported overdue, so the driver's
  # stall path runs instead of waiting on it for ever.
  local now=${COMMANDECK_NOW:-$(date +%s)}
  local live=null overdue=() id path at pid pids held=() max routing
  if [ "${best%% *}" = claude ] && [ "$(jq '.out // {} | length' <<<"$json")" -gt 0 ]; then
    routing=${COMMANDECK_ROUTING:-$(dirname "${BASH_SOURCE[0]}")/../config/routing.json}
    max=$(jq -er '.["seat-liveness"].backgroundMaxMinutes' "$routing" 2>/dev/null) \
      || { printf 'state=unknown\nreason=routing config %s has no seat-liveness.backgroundMaxMinutes\n' "$routing"; return; }
    while IFS=$'\t' read -r id path at; do
      [ -n "$path" ] || continue
      pids=$(file_holders "$path") \
        || { printf 'state=unknown\nreason=neither lsof nor fuser could answer for %s, so a live background command cannot be told from a dead one\n' "$path"; return; }
      for pid in $pids; do
        claude_ancestor "$pid" || continue
        if [ $((now - at)) -gt $((max * 60)) ]; then overdue+=("$id:$(((now - at) / 60))m"); else held+=("$id"); fi
        break
      done
    done < <(jq -r '.out | to_entries[] | [.key, .value.path, .value.at] | @tsv' <<<"$json")
    live=$(jq -nc '$ARGS.positional' --args "${held[@]}")
  fi
  jq -r --arg session "$f" --arg provider "${best%% *}" --argjson now "$now" --argjson limit "$STALL_IDLE_SECONDS" \
    --argjson grace "$FIRST_TURN_GRACE_SECONDS" --argjson live "$live" --arg overdue "$(IFS=,; echo "${overdue[*]}")" '
    (if $live == null then . else .outstanding = [(.outstanding // [])[] | select(IN($live[]))] end)
    | .idle_since = (if .state == "complete" and (.outstanding | length) == 0 then .idle_base else null end)
    | (if .idle_since == null then null else ($now - .idle_since) end) as $idle
    | "state=\(.state)", "reason=\(.reason // "")", "marker=\(if .marker then 1 else 0 end)",
      "outstanding=\((.outstanding // []) | join(","))", "overdue=\($overdue)", "idle_since=\(.idle_since // "")",
      "idle_seconds=\($idle // "")", "stalled=\(if $idle != null and $idle > $limit then 1 else 0 end)",
      "first_turn_stall=\(if $provider == "claude" and .tools == 0 and $idle != null and $idle >= $grace
          and (.marker | not) and ((.message // "") | test("(^|\n)\\s*VERDICT:") | not) then 1 else 0 end)",
      "last_message=\((.message // "") | gsub("\\s+"; " ") | .[0:400])",
      "session=\($session)", "provider=\($provider)", "stall_limit=\($limit)"
  ' <<<"$json"
}

# The session id of each top-level Claude process in a pane. Orca exports the
# pane's handle into its shell, so the process carries it, and Claude names its
# log after the id in ~/.claude/sessions/<pid>.json. A claude started by that
# claude inherits the handle too, so only top-level processes count.
pane_sessions() { # handle
  local p penv
  for p in $(pgrep -x claude 2>/dev/null); do
    # macOS has no /proc; its `ps -E` appends the environment to the command.
    if [ -d /proc/self ]; then penv=$(tr '\0' '\n' 2>/dev/null < "/proc/$p/environ")
    else penv=$(ps -Eww -o command= -p "$p" 2>/dev/null | tr ' ' '\n'); fi
    grep -qxF "ORCA_TERMINAL_HANDLE=$1" <<<"$penv" || continue
    claude_ancestor "$p" && continue
    jq -r '.sessionId // empty' "$HOME/.claude/sessions/$p.json" 2>/dev/null
  done | sort -u
}

# --repeat-class <round file>: two NO-GOs in a row on one finding class are a loop, not progress (issue 225).
# Prints REPEAT CLASS: <class> (r<N-1>, r<N>) when this round and the one before it both end NO-GO with a P0-P2
# finding of that (class: <tag>); nothing otherwise.
if [ "${1:-}" = --repeat-class ]; then
  n=$(sed -n 's/.*-r\([0-9]*\)-reports\.md$/\1/p' <<<"${2:-}"); [ -n "$n" ] || exit 0
  classes() { [ "$(grep '^VERDICT:' "$1" 2>/dev/null | tail -1)" = "VERDICT: NO-GO" ] || return 0
    grep -oE '\[P[0-2]\] \(class: [^)]+\)' "$1" | sed 's/.*(class: //; s/)$//' | sort -u; }
  c=$(comm -12 <(classes "${2%-r"$n"-reports.md}-r$((n - 1))-reports.md") <(classes "$2") | head -1)
  [ -z "$c" ] || echo "REPEAT CLASS: $c (r$((n - 1)), r$n)"
  exit 0
fi
if [ "${1:-}" = --state ]; then
  shift
  worker_state "$@"
  exit 0
fi
# seat.sh launch records the id, so a seat's log stays tied after its pane closes.
if [ "${1:-}" = --session ]; then
  pane_sessions "${2:?usage: $0 --session <terminal-handle>}"
  exit 0
fi

# The buffer is a JSON array of quoted lines with \r line splits inside them.
# Unwrap to plain text first, then strip the repaint noise INLINE rather than
# by whole line -- a spinner fragment is routinely glued onto the same line as
# a real finding, so dropping the line drops the finding with it.
#
# The spinner rule demands a literal bullet and eight more characters. An
# earlier version made every letter of "Working" optional, which matched a
# single stray letter anywhere and quietly deleted the o, n and i out of the
# findings themselves. Any change here gets tested against a real pane.
#
# The last rule drops the agent TUI's two-space body gutter. Callers anchor on
# `^VERDICT:` and `^[P0-3]` at column 0 (seat.sh wait and collect), so a pane
# read keeps its verdict and its findings invisible to them without it. Only
# pane text passes through here; session-log markdown keeps its indentation.
clean() {
  sed 's/\r/\n/g' \
  | sed 's/^ *"//; s/",$//' \
  | sed -E '
      s/ *› Ask (Codex|Claude) to do anything *//g;
      s/(gpt-[0-9.]+-[a-z]+|Opus [0-9.]+)( (high|xhigh|medium|low))? · [^·]+ · (Working|Idle)[^\n]*//g;
      s/ *[0-9]* ?background terminals? running · \/ps to view · \/stop to close//g;
      s/[•WorkingWorkin0-9]*•[•WorkingWorkin0-9]{8,}//g;
      s/ *· ctrl \+ t to view transcript//g;
      s/ *\(ctrl \+ t to view transcript\)//g;
      s/^  //;
    ' \
  | grep -vxE '\s*|\[|\]|"'
}

fetch() {  # $1 = accumulated | screen
  # The pane buffer is the only thing that needs Orca. Say so loudly rather
  # than returning an empty read, which a caller cannot tell from a silent pane.
  command -v orca-ide >/dev/null 2>&1 || {
    echo "read-verdict: orca-ide is not on PATH; cannot read the pane buffer for $HANDLE." >&2
    return 2
  }
  if [ "$1" = screen ]; then
    orca-ide terminal read --terminal "$HANDLE" --screen --json 2>/dev/null
  else
    orca-ide terminal read --terminal "$HANDLE" --cursor 0 --limit 300000 --json 2>/dev/null
  fi | jq -r '.result.terminal.tail // empty' | clean
}

# DONE is for a read-only pane that reports rather than judges -- a batch of the
# test audit finishes with `VERDICT: DONE`, so one reader serves both jobs.
#
# A VERDICT ONLY COUNTS ON A LINE THAT HOLDS NOTHING ELSE. The reviewer's own
# dispatch spec says "Make VERDICT: GO or VERDICT: NO-GO your final line" and
# every review brief quotes the same words, so both are in the pane buffer from
# the moment the prompt is injected; an unanchored match reads a verdict off a
# pane that has not started work.
# The optional trailing quote is the buffer's own: clean() unwraps the JSON
# array by stripping a leading quote and a trailing quote-comma, and the last
# element of the array has no comma to strip with it.
# The word must end its line, which is what keeps an injected spec's
# "Make VERDICT: GO or VERDICT: NO-GO your final line" from reading as a verdict.
#
# The word itself is open rather than a fixed list. A hand-written seat spec can
# invent one, and a reader that knows only the list then reports "no verdict yet"
# on a log that holds the verdict -- which reads as a stalled seat and costs a
# whole round. KNOWN_VERDICTS only decides whether to warn.
# Markdown bold around the line is still a bare verdict. A Claude seat told to
# make `VERDICT: GO` its final line writes `**VERDICT: GO**` often enough that
# on 2026-09-15 wt775's brief-reviewer finished GO and its driver sat out 38
# minutes reading the log as unfinished; a Claude log has no task_complete, so
# the exit-5 escape below never fires for one. The end-of-line anchor still
# does the work that keeps an injected spec from matching.
VERDICT_RE='^[[:space:]]*\*{0,2}VERDICT:[[:space:]]*([A-Z][A-Z0-9-]*)\*{0,2}[[:space:]]*"?[[:space:]]*$'
KNOWN_VERDICTS='GO NO-GO DONE REVISED'
# A verdict-shaped line inside a fence is a reviewer test's fixture, never the
# pane's verdict: a NO-GO report quoting `VERDICT: GO` in a fenced test
# read as GO. Both readers below take the last line OUTSIDE a fence, by the
# fence rule paths.sh gives every report reader (sourced below, before either
# runs). The number is the line's own in the text passed in, which the slice at
# the end of this script indexes.
#
# A SCREEN IS A VIEWPORT (`cropped`): it can open inside a fence whose first
# line scrolled away, and the closing line then reads as an opening one, which
# hides the real verdict below it and leaves a finished pane reading as
# unfinished. So when the plain reading finds no verdict, or ends inside a
# fence, the screen is read once more as starting inside one. That second
# reading counts only when the first delimiter it meets is bare, as a closing
# line is, and it ends outside a fence; otherwise the plain reading stands.
# AMBIGUOUS: a screen whose last lines are a bare opening fence and a fixture
# verdict still streaming is the same text as a cropped one. So when the second
# reading replaces a plain one that ended inside a fence, a GO there is dropped
# and any other verdict kept (main's ruling): a false NO-GO costs one more round,
# a false GO skips one.
verdict_lines() {  # <text> [cropped]: "<line number>:<line>" for each verdict outside a fence
  printf '%s\n' "$1" | VERDICT_RE=$VERDICT_RE awk -v cropped="${2:-}" "$PP_AWK_FENCE"'
    { line[NR] = $0 }
    function scan(inside,   i, f, out) {
      flen = 0; out = ""
      for (i = 1; i <= NR; i++) {
        if (inside) {
          if (line[i] !~ /^[[:space:]]*(```+|~~~+)/) continue
          if (line[i] !~ /^[[:space:]]*(```+|~~~+)[[:space:]]*$/) break
          inside = 0; continue
        }
        f = fence(line[i])
        if (!f && !flen && line[i] ~ ENVIRON["VERDICT_RE"]) out = out i ":" line[i] "\n"
      }
      ended_inside = (inside || flen)
      return out
    }
    function drop_go(s,   n, a, i, w, r) {  # the lines of s whose word, as verdict_word strips it, is not GO
      n = split(s, a, "\n"); r = ""
      for (i = 1; i <= n; i++) {
        if (a[i] == "") continue
        w = a[i]; sub(/^[0-9]+:[[:space:]]*\*?\*?VERDICT:[[:space:]]*/, "", w); sub(/[[:space:]].*$/, "", w); sub(/"$/, "", w); sub(/\*+$/, "", w)
        if (w != "GO") r = r a[i] "\n"
      }
      return r
    }
    END {
      out = scan(0); plain_inside = ended_inside
      if (cropped && (out == "" || plain_inside)) { again = scan(1); if (!ended_inside) out = plain_inside ? drop_go(again) : again }
      printf "%s", out
    }'
}
find_verdict() { verdict_lines "$@" | tail -1 | cut -d: -f1; }
verdict_word() {  # <text> <its verdict line, from find_verdict>
  printf '%s\n' "$1" | sed -n "${2}p" \
    | sed -E 's/^[[:space:]]*\*{0,2}VERDICT:[[:space:]]*//; s/[[:space:]].*$//; s/"$//; s/\*+$//'
}

# SESSION LOGS ARE AUTHORITATIVE. The terminal screen contains the injected
# spec, file contents and prior reports, all of which can contain a bare verdict
# line. It is used only when no matching session log exists at all.
WTP=${3:-$(orca-ide terminal list --json 2>/dev/null | jq -r --arg h "$HANDLE" '.result | flatten | .[] | objects | select(.handle==$h) | .worktreePath // empty' | head -1)}
AGENT=${4:-$(orca-ide terminal list --json 2>/dev/null | jq -r --arg h "$HANDLE" '.result | flatten | .[] | objects | select(.handle==$h) | .agentIdentity // empty' | head -1)}
UNIT=${5:-${WTP##*/}}
MODEL=${6:-}
# 0 is the LAST verdict: a re-prompted pane's answer is its latest turn's.
ORDINAL=${7:-0}
LAUNCHED=${8:-0}
[[ "$ORDINAL" =~ ^[0-9]+$ ]] || ORDINAL=0
[[ "$LAUNCHED" =~ ^[0-9]+$ ]] || LAUNCHED=0
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || exit 1
SCRATCH=$PP_SCRATCH
# --seat <unit> <role>: the verdict seat.sh collect closed that seat on, then the report it kept (issue 236).
if [ "$HANDLE" = --seat ]; then
  REC=$SCRATCH/seat-${COMMANDECK_SEAT_REPO:+$COMMANDECK_SEAT_REPO@}${2:?unit}-${3:?role}.txt
  R=$(sed -n 's/^report=//p' "$REC" 2>/dev/null | tail -1)
  [ -s "$R" ] || { echo "read-verdict: no report on record for $3 $2 ($REC); seat.sh collect writes it" >&2; exit 3; }
  sed -n 's/^verdict=//p' "$REC" | tail -1; cat "$R"; exit 0
fi
# One grep over every record, never one per record: the records are never deleted.
SEAT_REC=$(grep -lx "handle=$HANDLE" "$SCRATCH"/seat-*.txt 2>/dev/null | head -1 || true)
SEAT_SESSION=""; SEAT_SPEC=""
if [ -n "$SEAT_REC" ]; then
  SEAT_SESSION=$(sed -n 's/^session=//p' "$SEAT_REC" | tail -1)
  SEAT_SPEC=$(sed -n 's/^spec=//p' "$SEAT_REC" | tail -1)
  # Sibling seats can be handed one spec; the launch's own tag in the prompt
  # is what only this seat's session carries, so it binds when the record has it.
  SEAT_TAG=$(sed -n 's/^tag=//p' "$SEAT_REC" | tail -1)
  [ -z "$SEAT_TAG" ] || SEAT_SPEC=$SEAT_TAG
fi

# WITHOUT A LAUNCH TIME THIS READER SERVES THE WRONG SESSION. It takes the first
# log in the worktree that holds a verdict, so a RELAUNCHED seat returns its
# PREVIOUS session's verdict -- on 2026-09-13 that handed main a stale NO-GO for
# a seat that was still working, and the relaunch reason had already been ruled
# on. The seat record knows the real launch time, so look it up by handle rather
# than make every caller remember argument 8.
if [ "$LAUNCHED" -eq 0 ]; then
  s=$SEAT_REC
  if [ -n "$s" ]; then
    LAUNCHED=$(sed -n 's/^launched=//p' "$s" | head -1)
    [[ "$LAUNCHED" =~ ^[0-9]+$ ]] || LAUNCHED=0
    [ "$LAUNCHED" -eq 0 ] || SEAT_RECORD=$s
  fi
  # Review-round panes live in review-handles-<unit>-r<N>.txt, not a seat
  # record; missing them woke main on round 1's NO-GO while round 2 was still
  # reading (tooling-batch-2026-09-17d, 2026-09-17). Newest file wins.
  if [ "$LAUNCHED" -eq 0 ]; then
    hf=$(ls -t "$SCRATCH"/*-handles-*.txt 2>/dev/null | xargs -r grep -l -- "=$HANDLE" 2>/dev/null | head -1)
    [ -z "$hf" ] || LAUNCHED=$(grep -h -- "=$HANDLE" "$hf" | sed -n 's/.*launched=\([0-9][0-9]*\).*/\1/p' | head -1)
    [[ "${LAUNCHED:-}" =~ ^[0-9]+$ ]] || LAUNCHED=0
  fi
fi

codex_report() {
  jq -rs --argjson n "$ORDINAL" '
    def strip_fences:
      reduce (split("\n")[]) as $line
        ({inside: false, lines: []};
          if ($line | test("^[\\t ]*```")) then .inside = (.inside | not)
          elif (.inside | not) then .lines += [$line]
          else .
          end)
      | .lines | join("\n");
    # The latest answer (ordinal 0) is the one given after the last user
    # message: an earlier verdict is history while a follow-up turn runs.
    def is_msg($r): .type == "response_item" and .payload.type == "message" and .payload.role == $r;
    . as $rows
    | ([range(0; length) | select($rows[.] | is_msg("user"))] | last // -1) as $asked
    | [(if $n == 0 then $rows[$asked + 1:] else $rows end)[]
      # Commentary is narration while the turn still runs, never the answer.
      | select(is_msg("assistant") and .payload.phase != "commentary")
      | .payload.content[]?
      | select(.type == "output_text")
      | .text
      | select(strip_fences | test("(?m)^[\\t ]*\\*{0,2}VERDICT:[\\t ]*([A-Z][A-Z0-9-]*)\\*{0,2}[\\t ]*$"))]
    | (if $n == 0 then last else .[$n - 1] end) // empty
  ' "$1" 2>/dev/null
}

# With no verdict message, the last assistant text comes back instead, so the
# no-verdict tail holds an implementer's `<UNIT>-DONE` marker for main-watch's
# has_result; find_verdict still sees no verdict in it. Codex seats get the
# same through task_complete (exit 5).
claude_report() {
  # Claude Code 2.1.300's api-request rows hold no report: dropped before jq slurps the log.
  grep -v '^{"type":"api-request' "$1" 2>/dev/null | jq -rs --argjson n "$ORDINAL" '
    # As in codex_report: the latest answer (ordinal 0) follows the last prompt.
    # A prompt is a user row with typed text; a tool result is not one, nor is
    # a row holding only notices the harness writes. Text after a notice in the
    # same row is typed text, and so is any other text, tagged or not.
    def prompt: .type == "user" and .isMeta != true
      and (.message.content | if type == "string" then [.] else [.[]? | select(.type == "text") | .text] end
           | any(.[]; sub("^(\\s*<(?<t>task-notification|system-reminder|local-command-[a-z]+)>[\\s\\S]*?</\\k<t>>)+"; "") | test("\\S")));
    . as $rows
    | ([range(0; length) | select($rows[.] | prompt)] | last // -1) as $asked
    | [(if $n == 0 then $rows[$asked + 1:] else $rows end)[]
      | select(.type == "assistant")
      | [.message.content[]? | select(.type == "text") | .text] | join("\n")
      | select(length > 0)] as $all
    | [$all[] | select(test("(?m)^[\\t ]*\\*{0,2}VERDICT:[\\t ]*([A-Z][A-Z0-9-]*)\\*{0,2}[\\t ]*$"))]
    | if length > 0 then (if $n == 0 then last else .[$n - 1] end)
      elif $n == 0 then $all | last else null end
    | . // empty
  ' 2>/dev/null
}

SOURCE=log-pending
TEXT=""; VERDICT_LINE=""; LOG_FOUND=0
# Each log branch is opted INTO by name. An agent that writes neither kind of
# session log must fall through to the pane buffer: a `!= claude` test sent
# such a pane down the Codex branch, which matched an unrelated Codex session
# in the same worktree and returned ITS verdict as the pane's.
if [ -n "$WTP" ] && { [ "$AGENT" = codex ] || [ -z "$AGENT" ]; }; then
  # Only the read-only review lane sets CODEX_HOME=~/.codex-review; an
  # implementer Codex pane writes to the default ~/.codex. Searching just the
  # review home matched a reviewer's stale session in the same worktree and
  # reported "no verdict yet" for an implementer that had printed its marker ten
  # times, leaving unit-loop in wait_worker forever (2026-09-13, C3b3). Both
  # homes, newest first; the cwd, model and LAUNCHED filters below still pick.
  mapfile -t CH_DIRS < <(codex_session_dirs)
  # BOUND THE SCAN. Unbounded, this jq-parses every session ever written, some
  # of them megabytes, and a single pane read ran past two minutes on
  # 2026-09-15 and had to be killed. A session last written before the seat
  # launched cannot be that seat's log, so mtime prunes most of them; the cap
  # stops a pathological case; and session_meta is line 1, so the identity
  # check never needs the whole file.
  FIND_NEWER=(); [ "${LAUNCHED:-0}" -gt 0 ] && FIND_NEWER=(-newermt "@$LAUNCHED")
  CODEX_LOGS=()
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    identity=$(head -n 2000 "$f" | jq -c --arg cwd "$WTP" --arg model "$MODEL" "$PP_PNORM"'
      ($cwd | pnorm) as $cwd | select(
        (.type == "session_meta" or .type == "turn_context" or
         .payload.type == "session_meta" or .payload.type == "turn_context") and
        (.payload.cwd | pnorm) == $cwd and
        ($model == "" or .payload.model == $model)
      )
    ' 2>/dev/null | head -1)
    [ -n "$identity" ] || continue
    created=$(head -1 "$f" | jq -r '.timestamp // .payload.timestamp // empty' 2>/dev/null)
    created_epoch=$(date -d "$created" +%s 2>/dev/null || echo 0)
    [ "$created_epoch" -ge "$LAUNCHED" ] || continue
    CODEX_LOGS+=("$f")
  done < <(find "${CH_DIRS[@]}" -type f -name '*.jsonl' "${FIND_NEWER[@]}" -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2- | head -40)
  # A Codex pane records no session id, so the seat record's spec binds it:
  # the seat's sessions are the ones that were handed that spec, and that holds
  # for a lone session too (a sibling can finish before the seat's own session
  # has written a line). With no spec on record one session is taken as the
  # seat's, and several are refused as in the Claude branch: another seat's
  # verdict must never close this one.
  if [ -n "$SEAT_SPEC" ]; then
    ALL=(${CODEX_LOGS[@]+"${CODEX_LOGS[@]}"}); CODEX_LOGS=()
    for f in ${ALL[@]+"${ALL[@]}"}; do
      ! given_spec "$f" "$SEAT_SPEC" || CODEX_LOGS+=("$f")
    done
  elif [ "${#CODEX_LOGS[@]}" -gt 1 ]; then
    echo "read-verdict: cannot tie $HANDLE to one Codex session log: ${#CODEX_LOGS[@]} sessions ran in $WTP and no seat record names this handle with a spec. Not guessing." >&2
    exit 7
  fi
  # Newest first, so a relaunched seat (same spec) is read from its latest session.
  if [ "${#CODEX_LOGS[@]}" -gt 0 ]; then
    f=${CODEX_LOGS[0]}
    LOG_FOUND=1; SOURCE="codex-log $f"; TEXT=$(codex_report "$f"); VERDICT_LINE=$(find_verdict "$TEXT")
  fi
fi
if [ -n "$WTP" ] && { [ "$AGENT" = claude ] || [ -z "$AGENT" ]; } && [ "$LOG_FOUND" -eq 0 ]; then
  PROJ=$HOME/.claude/projects/$(pp_slug "$WTP")
  # TIE THE HANDLE TO ITS OWN SESSION: the pane's live Claude process
  # first, then the seat record. Newest-log-in-the-worktree handed a sibling
  # pane's verdict to main on 2026-09-23.
  # A session= that is a path is a Codex log seat.sh bound, never a Claude id.
  SID=$(pane_sessions "$HANDLE"); [ -n "$SID" ] || case $SEAT_SESSION in /*) ;; *) SID=$SEAT_SESSION ;; esac
  if [ "$(printf '%s' "$SID" | grep -c .)" -gt 1 ]; then
    echo "read-verdict: cannot tie $HANDLE to one Claude session log: its pane runs sessions $(echo $SID)." >&2
    exit 7
  elif [ -n "$SID" ]; then
    # A session that has not written its log yet has no verdict yet (exit 3 below).
    f=$PROJ/$SID.jsonl
    LOG_FOUND=1; SOURCE="claude-log $f"; TEXT=$([ ! -f "$f" ] || claude_report "$f"); VERDICT_LINE=$(find_verdict "$TEXT")
  elif [ "$LAUNCHED" -gt 0 ]; then
    # Order by when each session STARTED, not by mtime. Two reviewer seats in
    # one worktree launch seconds apart and both their logs start after both
    # launch epochs, so newest-by-mtime handed the same session to both seats
    # and the second review was silently transcribed as a copy of the first
    # (2026-09-13, unit E and unit C3c, two reviews lost). A seat's own session
    # is the one that starts SOONEST AFTER it, so walk ascending.
    # The first line of a Claude log may carry no timestamp (a summary or queue
    # record); `date -d ""` would read as today's midnight and the round's own
    # log would be skipped as "before launch", so fall back to the file mtime.
    for f in $(for c in "$PROJ"/*.jsonl; do
        [ -f "$c" ] || continue
        created=$(jq -r 'select(.timestamp != null) | .timestamp' "$c" 2>/dev/null | head -1)
        [ -n "$created" ] && created_epoch=$(date -d "$created" +%s 2>/dev/null) || created_epoch=$(stat -c %Y "$c" 2>/dev/null || echo 0)
        [ "${created_epoch:-0}" -ge "$LAUNCHED" ] || continue
        [ -z "$SEAT_SPEC" ] || given_spec "$c" "$SEAT_SPEC" || continue
        printf '%s %s\n' "$created_epoch" "$c"
      done | sort -n | cut -d' ' -f2-); do
      # The first one only. Reading on past a session with no verdict yet
      # handed a later sibling's GO to a seat that was still working; the
      # spec test above is what sets a stray session (a budget probe) aside.
      LOG_FOUND=1; SOURCE="claude-log $f"; TEXT=$(claude_report "$f"); VERDICT_LINE=$(find_verdict "$TEXT")
      break
    done
  elif [ "$WTP" -ef "$PP_MAIN" ] && compgen -G "$PROJ/*.jsonl" >/dev/null; then
    # Main is not a seat: no seat record or launch time names its session, and
    # it is the one pane in main's checkout, so its session is the log written last.
    f=$(ls -t "$PROJ"/*.jsonl | head -1)
    echo "read-verdict: $HANDLE is main's pane, which has no seat record: reading the newest session log in main's checkout, $f" >&2
    LOG_FOUND=1; SOURCE="claude-log $f"; TEXT=$(claude_report "$f"); VERDICT_LINE=$(find_verdict "$TEXT")
  elif compgen -G "$PROJ/*.jsonl" >/dev/null; then
    echo "read-verdict: cannot tie $HANDLE to one Claude session log in $PROJ: no Claude process in the pane, no session= in a seat record, and no launch time (argument 8). Not guessing." >&2
    exit 7
  fi
fi

if [ "$LOG_FOUND" -eq 0 ]; then
  SOURCE=accumulated
  TEXT=$(fetch accumulated)
  VERDICT_LINE=$(find_verdict "$TEXT")
  if [ -z "$VERDICT_LINE" ]; then
    SCREEN=$(fetch screen)
    SCREEN_LINE=$(find_verdict "$SCREEN" cropped)
    # Orca 1.4.220 keeps no accumulated history for an agent TUI pane (the
    # stream is one empty line), so the screen is the only text there is.
    if [ -n "$SCREEN_LINE" ] || [ -z "$TEXT" ]; then
      SOURCE=screen; TEXT="$SCREEN"; VERDICT_LINE="$SCREEN_LINE"
    fi
  fi
fi

if [ -z "$TEXT" ] && [ "$LOG_FOUND" -eq 0 ]; then
  echo "read-verdict: no buffer for $HANDLE. Wrong handle, or the pane never booted." >&2
  exit 1
fi

# A Claude pane that ran out of session budget prints one line and stops. The
# pane still shows a VERDICT line, because the reports file it Read before
# dying is echoed in the buffer; on 2026-09-03 two reviewers died this way and
# main took a round-1 verdict for a round-2 one. Budget death is never a
# verdict.
if grep -q "hit your session limit" <<<"$TEXT"; then
  echo "=== NO VERDICT: $HANDLE ran out of session budget ==="
  printf '%s\n' "$TEXT" | grep -m1 "hit your session limit"
  echo "Relaunch the lens when the window resets; nothing here is a review."
  exit 4
fi

# A PANE WHOSE TURN IS OVER IS NOT "NOT FINISHED YET". Every waiter here treats
# a missing verdict as "still working" and sits out its whole timeout, so on
# 2026-09-15 the wt775 plan-author ended on `PLAN-BLOCKED` instead of its marker
# and its driver blocked on a pane that had stopped 75 minutes earlier. Codex
# writes `task_complete` carrying the pane's last words; exit 5 says "finished,
# with this to say" so the caller can wake main now instead of at the timeout.
# It uses the worker-state parse above, so a newer turn or a still-running
# background command is not "finished". Claude seats reach their waiter's
# five-minute stall check instead.
TURN_DONE_MSG=""
case "$SOURCE" in
  codex-log*) TURN_DONE_MSG=$(session_state codex "${SOURCE#codex-log }" "" "" \
      | jq -r 'select(.state == "complete" and (.outstanding | length) == 0) | .message // empty' 2>/dev/null \
      | tail -c 2000) ;;  # the end: a completion marker closes the message
esac

if [ -z "$VERDICT_LINE" ] && [ -n "$TURN_DONE_MSG" ]; then
  echo "=== PANE FINISHED WITH NO VERDICT: $HANDLE ==="
  echo "Its turn is complete in $SOURCE. This seat is not still working."
  echo "Its last message:"
  printf '%s\n' "$TURN_DONE_MSG"
  exit 5
fi

# A PANE THAT CANNOT REACH A MODEL WILL NEVER FINISH. Codex keeps its spinner
# and "esc to interrupt" on screen while it retries a dead endpoint, so every
# waiter here reads it as busy and sits out its whole timeout -- the same shape
# as exit 5 above, from a different cause. On 2026-09-15 the endpoint a reviewer
# CODEX_HOME routed through died, and the wt775 and wt1164-capture-detection
# reviewers spent 46 and 33 minutes on "Reconnecting... waiting for network"
# while their drivers said nothing to main.
#
# Only the LIVE spinner line counts. The "⚠ Falling back from WebSockets"
# warning stays on screen after a pane recovers, so keying on it would call a
# working reviewer offline. A reconnect that clears on its own costs one wake.
if [ -z "$VERDICT_LINE" ]; then
  [ -n "${SCREEN:-}" ] || SCREEN=$(fetch screen)
  OFFLINE=$(printf '%s\n' "$SCREEN" | grep -aE 'Reconnecting\.\.\. waiting for network' | tail -1)
  if [ -n "$OFFLINE" ]; then
    echo "=== PANE IS OFFLINE: $HANDLE ==="
    echo "It cannot reach a model, so it will not print a verdict on its own."
    printf '%s\n' "$OFFLINE"
    printf '%s\n' "$SCREEN" | grep -aE 'Connection (refused|failed)|stream disconnected' | tail -2
    exit 6
  fi
fi

if [ -z "$VERDICT_LINE" ]; then
  echo "=== NO VERDICT YET in $HANDLE ==="
  if [ "$LOG_FOUND" -eq 1 ]; then
    [ "$ORDINAL" -eq 0 ] && echo "The matching $SOURCE holds no verdict yet." \
      || echo "The matching $SOURCE does not hold verdict ordinal $ORDINAL yet."
  else
    echo "Neither the accumulated buffer nor the screen holds a VERDICT line."
  fi
  echo "Last 25 lines of real output:"
  printf '%s\n' "$TEXT" | tail -25
  exit 3
fi

if [ "$SOURCE" = screen ]; then
  echo "!! Read from the RENDERED SCREEN, not the accumulated buffer."
  echo "!! Findings above the viewport are NOT here. Treat this as possibly partial."
fi
case "$SOURCE" in
  codex-log*) echo "## source: Codex session log (${SOURCE#codex-log }), raw markdown, fences intact" ;;
  claude-log*) echo "## source: Claude session log (${SOURCE#claude-log }), raw markdown, fences intact" ;;
esac
# Codex logs are matched on the worktree, then taken newest first, so the
# launch time (argument 8) is the only thing separating two panes in one
# worktree. Without it, the a3c2 advice pane's report on 2026-09-13 came back
# as the review pane's, and both looked plausible. A Claude log is tied above.
if [ "$LAUNCHED" = 0 ] && case "$SOURCE" in codex-log*) true ;; *) false ;; esac; then
  echo "!! No launch time given (argument 8) and no seat record names this handle,"
  echo "!! so this log was chosen by worktree and mtime alone. If another pane is"
  echo "!! running in this worktree, this may be ITS session."
fi
[ -z "${SEAT_RECORD:-}" ] || echo "## launch time $LAUNCHED taken from $SEAT_RECORD"

# An unknown word still prints, but never silently: a seat told to end with a
# word no template defines is a spec bug, and main must see it rather than read
# the pane as unfinished.
VERDICT_WORD=$(verdict_word "$TEXT" "$VERDICT_LINE")
case " $KNOWN_VERDICTS " in
  *" $VERDICT_WORD "*) ;;
  *) echo "!! VERDICT: $VERDICT_WORD is not a known verdict ($KNOWN_VERDICTS)." ;;
esac

START=$(( VERDICT_LINE - CONTEXT_LINES ))
[ "$START" -lt 1 ] && START=1

# ONE CANONICAL VERDICT LINE, ahead of the report slice. Four consumers grep
# this output for `^VERDICT:` at column 0 -- seat.sh wait, seat.sh collect
# twice, and unit-drive.sh's own GO test on collect's output -- so a seat that
# decorates its final line breaks the whole chain, not one reader. Normalise it
# here once instead of teaching each grep about markdown. It sits before the
# banner so collect's `/^# /,$p` transcription never picks it up, and the raw
# line still follows inside the slice, so a `tail -1` reader sees the original.
printf '%s\n' "$TEXT" | sed -n "${VERDICT_LINE}p" \
  | sed -E 's/^[[:space:]]*\*{0,2}//; s/[[:space:]]*\*{0,2}[[:space:]]*"?[[:space:]]*$//; s/^VERDICT:[[:space:]]*/VERDICT: /'

echo "=== $HANDLE : findings + verdict ==="
printf '%s\n' "$TEXT" | sed -n "${START},${VERDICT_LINE}p"

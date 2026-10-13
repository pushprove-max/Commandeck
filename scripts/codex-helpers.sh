#!/usr/bin/env bash
# codex-helpers.sh stop <worktree> | orphans    (sourced: open_pane, live_pane_with_title, pane_is_busy)
#   stop <worktree>  kill, by pid, every Codex app-server-broker.mjs serving that
#                    worktree (`serve --cwd <worktree>`) and its codex app-server child
#   orphans          print the pids of brokers whose --cwd no longer exists, and
#                    their children, on one line
# The Codex plugin starts one broker pair per worktree and nothing stops it when
# the worktree goes: nine pairs outlived their worktrees by 2 to 16 hours on
# 2026-09-18. merge-unit-local.sh and ship-unit.sh call `stop` after the
# worktree is removed; agent-awareness.sh calls `orphans`.
set -uo pipefail

# "<pid> <cwd>", one line per broker.
brokers() {
  ps -eo pid=,ppid=,args= | awk '/app-server-broker\.mjs serve/ {
    for (i = 3; i < NF; i++) if ($i == "--cwd") { print $1, $(i + 1); break } }'
}
# Broker pids on stdin -> those pids plus their direct children.
with_children() {
  local ids; ids=$(tr '\n' ' ')
  [ -n "${ids// /}" ] || return 0
  printf '%s\n' $ids
  ps -eo pid=,ppid= | awk -v ids=" $ids " 'index(ids, " " $2 " ") { print $1 }'
}

# Sourced, this file is the one place a launcher opens an agent pane:
# no duplicate agent, of any role, ever (owner ruling 2026-09-24).
# A live agent retitles its own pane, so the launch title is also kept here,
# one "<worktree-selector>\t<title>\t<handle>\t<epoch>" line per created pane.
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || return 1
PANE_TITLES=$PP_SCRATCH/pane-titles.tsv
# The one role table for pane titles. Orca's agent list cuts a title at about
# 25 characters, so the role comes first: `<Role>[ <qualifier>] — <unit>`.
# pane_word <routing role or seat> -- the role in words, capitalised.
pane_word() {
  local w=${1//-/ }
  case "$1" in design-fixer) w="fix designer" ;; e2e-driver) w="E2E driver" ;; esac
  printf '%s%s' "$(tr '[:lower:]' '[:upper:]' <<<"${w:0:1}")" "${w:1}"
}
# pane_title <role> <unit> [qualifier] -- e.g. `Fixer r2 — u`, `Reviewer r1 · Sol — u`.
pane_title() { printf '%s%s — %s\n' "$(pane_word "$1")" "${3:+ $3}" "$2"; }
# The one role -> lane table: the dashboard column a working pane of that role
# puts its unit in. Every routing.json role has an entry
# (routing-ssot.guard.test.sh); null is a seat, never a unit stage. `reviewer`
# is review-round.sh's title word for every review seat.
ROLE_LANES='{
  "plan-author": "planning", "brief-reviewer": "planning", "design-coauthor": "planning",
  "plan-author-arch": "planning", "brief-reviewer-arch": "planning",
  "plan-author-hard": "planning", "brief-reviewer-hard": "planning",
  "investigator": "planning", "debugger": "planning", "debugger-pipeline": "planning",
  "implementer": "building", "implementer-light": "building", "race-implementer": "building", "escalation": "building", "builder": "building",
  "reviewer": "review", "claude-reviewer": "review", "codex-reviewer": "review", "codex-reviewer-risky": "review",
  "luna-reviewer": "review", "refuter": "review", "certifier": "review", "judge-fable": "review",
  "judge-luna": "review", "judge-luna-high": "review", "judge-sol-high": "review", "judge-sol-xhigh": "review",
  "fixer": "fixing", "design-fixer": "fixing",
  "e2e-driver": null, "companion": null, "automation-claude": null,
  "main-session": null, "release-captain": null}'
# The flow's order: with two lanes working at once, the later one is the unit's.
LANE_ORDER='["planning","building","review","fixing"]'
# lane_words -- {"<pane_word>": lane} for every role in ROLE_LANES.
lane_words() {
  local r
  jq -r 'keys[]' <<<"$ROLE_LANES" | while read -r r; do printf '%s\t%s\n' "$(pane_word "$r")" "$r"; done \
    | jq -Rn --argjson t "$ROLE_LANES" '[inputs | split("\t") | {key: .[0], value: $t[.[1]]}] | from_entries'
}
# jq: <title> | title_lane(<lane_words>) -- the lane of the role a pane_title
# names (the longest role word wins: "Brief reviewer" is not "Reviewer"), "seat"
# for a role with no lane, "unknown" for a title no role names.
TITLE_LANE_JQ='def title_lane($w): (split(" — ")[0] // "") as $h
  | [$w | to_entries[] | select(.key as $k | $h == $k or ($h | startswith($k + " ")))] | max_by(.key | length)
  | if . == null then "unknown" else .value // "seat" end;'
# Titles of read-only panes (review seats, fix designers): never the unit's
# worker. Every title reader that skips them uses this, in grep -E and jq alike.
READONLY_PANE_TITLE_RE='^(Reviewer|Fix designer) r[0-9]+ '
# live_pane_with_title <worktree-selector> <title> -- the handle of a live agent
# pane in that worktree launched with (or still showing) that title, else
# nothing. Live = connected, not orphaned, and Orca sees an agent in it
# (agentIdentity is null once the agent exits back to its shell), or it was
# launched under this title in the last 120 s: Orca detects a fresh pane's
# agent only seconds after boot. Returns 2 when the list cannot be
# read: an unknown state is not an absent agent.
live_pane_with_title() {
  local h at out
  # Rows match by worktree directory: a row recorded under the old
  # `id:<repo>::<dir>` selector names the same worktree as `path:<dir>`.
  IFS='|' read -r h at < <(awk -F'\t' -v w="$1" -v t="$2" '
    function dir(s, i) { if (s ~ /^path:/) return substr(s, 6); i = index(s, "::"); return i ? substr(s, i + 2) : s }
    dir($1) == dir(w) && $2 == t { h = $3; at = $4 } END { print h "|" at + 0 }' "$PANE_TITLES" 2>/dev/null || echo "|0")
  out=$(orca-ide terminal list --worktree "$1" --json 2>/dev/null) \
    && jq -e 'has("result")' <<<"$out" >/dev/null 2>&1 || return 2
  jq -r --arg t "$2" --arg h "${h:-}" --argjson age "$(( $(date +%s) - ${at:-0} ))" '
    first(.result | if type == "array" then . else (.terminals // []) end | .[]
      | select(.connected != false and .orphaned != true)
      | select(.agentIdentity != null or ($h != "" and .handle == $h and $age < 120))
      | select(.title == $t or ($h != "" and .handle == $h)) | .handle) // empty' <<<"$out"
}
# open_pane <worktree-selector> <title> <command> -- prints the pane's handle.
# Returns 3 when it reused a live pane: the caller must not prompt it again,
# and refuses the launch when it has no record of the pane's task -- a missing
# record is not proof the prompt never landed. The body is a subshell, so the
# lock that makes lookup, create and record one step is released on return.
open_pane() (
  local h out fd f cmd=$3
  mkdir -p "$(dirname "$PANE_TITLES")" && exec {fd}>>"$PANE_TITLES.lock" && flock -w 60 "$fd" \
    || { echo "cannot lock $PANE_TITLES.lock; not launching $2" >&2; return 1; }
  h=$(live_pane_with_title "$1" "$2") || { echo "cannot list panes in $1; not launching $2 blind" >&2; return 1; }
  if [ -n "$h" ]; then echo "reused live pane $h ($2)" >&2; echo "$h"; return 3; fi
  # A typed line past MAX_CANON (1024 bytes on macOS) loses its tail, so
  # a long command is sourced from a self-deleting file in the pane's own shell.
  if [ "$(LC_ALL=C; echo "${#3}")" -gt 1000 ]; then
    f=$(mktemp "$PP_SCRATCH/pane-cmd.XXXXXX") && printf 'rm -f -- %q\n%s\n' "$f" "$3" > "$f" \
      || { rm -f -- "$f"; echo "cannot write the launcher for $2; not launching it" >&2; return 1; }
    cmd=". $(printf %q "$f")"
  fi
  out=$(orca-ide terminal create --worktree "$1" --title "$2" --command "$cmd" --json)
  h=$(jq -r 'first(.. | objects | select(has("handle")) | .handle) // empty' <<<"$out" 2>/dev/null)
  [ -n "$h" ] || { jq -r '.error.message // .' <<<"$out" >&2 2>/dev/null || printf '%s\n' "$out" >&2; return 1; }
  # Unrecorded, a pane that retitles itself is invisible to the next launch.
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$h" "$(date +%s)" >> "$PANE_TITLES" || {
    echo "cannot record $h ($2) in $PANE_TITLES; closing it" >&2
    orca-ide terminal close --terminal "$h" --json >/dev/null 2>&1; return 1; }
  echo "$h"
)
# pane_is_busy <handle|terminal:handle> -- 0 when the pane's agent is mid-turn
# (Orca's `worktree ps` agent whose paneKey is the pane's "<tabId>:<leafId>" has
# state "working"), 1 when it is not or the pane is gone, 2 when either list
# cannot be read. A new job sent into a busy pane queues behind its turn and
# runs as a second job; callers refuse on 0 and 2. A nudge to the job
# the pane is already on is not a new job and does not ask.
# An unreadable state is asked three times before it is 2: under load one slow
# Orca answer refused every fresh reviewer's dispatch (2026-09-28).
pane_is_busy() {
  local rc n
  for n in 1 2 3; do
    [ "$n" = 1 ] || sleep 2
    rc=0; pane_state_read "$1" || rc=$?
    [ "$rc" = 2 ] || return "$rc"
  done
  return 2
}
pane_state_read() {
  local ts ps wt kind
  ps=$(timeout 8 orca-ide worktree ps --json 2>/dev/null) && jq -e 'has("result")' <<<"$ps" >/dev/null 2>&1 || return 2
  jq -e 'any(.result.worktrees[]?.agents[]?; .state == "working")' <<<"$ps" >/dev/null 2>&1 || return 1
  ts=$(timeout 8 orca-ide terminal list --json 2>/dev/null) && jq -e 'has("result")' <<<"$ts" >/dev/null 2>&1 || return 2
  jq -en --argjson ts "$ts" --argjson ps "$ps" --arg h "${1#terminal:}" '
    first(($ts.result | if type == "array" then . else (.terminals // []) end)[] | select(.handle == $h) | "\(.tabId):\(.leafId)") as $k
    | any($ps.result.worktrees[]?.agents[]?; .paneKey == $k and .state == "working")' >/dev/null 2>&1 || return 1
  # Orca keeps `working` for a pane whose turn ended on a question, and main's
  # answer was then refused. The pane's own session log decides, but
  # only where the worktree has that one agent and Orca says which kind it is:
  # the log is read by worktree and kind (read-verdict.sh, --current).
  wt=$(pane_worktree_of "$ts" "$ps" "${1#terminal:}" 1); kind=$(pane_kind_of "$ts" "$ps" "${1#terminal:}")
  [ -n "$wt" ] && [ -n "$kind" ] \
    && "$(dirname "${BASH_SOURCE[0]}")/read-verdict.sh" --state --worktree "$wt" --agent "$kind" --current 2>/dev/null | grep -qx 'state=complete' && return 1
  return 0
}
# pane_kind_of <terminal-list-json> <worktree-ps-json> <handle> -- claude or
# codex, from Orca's agent row for the pane; nothing for any other kind.
pane_kind_of() {
  jq -rn --argjson ts "$1" --argjson ps "$2" --arg h "$3" '
    first(($ts.result | if type == "array" then . else (.terminals // []) end)[] | select(.handle == $h) | "\(.tabId):\(.leafId)") as $k
    | first($ps.result.worktrees[]?.agents[]? | select(.paneKey == $k) | .agentType | select(. == "claude" or . == "codex"))' 2>/dev/null
}
# pane_worktree_of <terminal-list-json> <worktree-ps-json> <handle> [1] -- the
# path of the worktree whose agent the pane is; with 1, only when it is that
# worktree's one agent.
pane_worktree_of() {
  jq -rn --argjson ts "$1" --argjson ps "$2" --arg h "$3" --arg alone "${4:-}" '
    first(($ts.result | if type == "array" then . else (.terminals // []) end)[] | select(.handle == $h) | "\(.tabId):\(.leafId)") as $k
    | first($ps.result.worktrees[]? | select(any(.agents[]?; .paneKey == $k))
        | select($alone == "" or ((.agents | length) == 1)) | .path // empty)' 2>/dev/null
}
if [ "${BASH_SOURCE[0]}" != "$0" ]; then return 0; fi

case "${1:-}" in
  stop)
    wt=${2:-}; [ -n "$wt" ] || { echo "usage: codex-helpers.sh stop <worktree>" >&2; exit 2; }
    wt=${wt%/}
    pids=$(brokers | awk -v wt="$wt" '$2 == wt { print $1 }' | with_children)
    [ -z "$pids" ] || { kill $pids 2>/dev/null || true; echo "stopped Codex helpers for $wt: $(echo $pids)"; }
    ;;
  orphans)
    brokers | while read -r pid cwd; do [ -d "$cwd" ] || echo "$pid"; done | with_children | sort -n | tr '\n' ' ' | sed 's/ $//'
    ;;
  *) echo "usage: codex-helpers.sh stop <worktree> | orphans" >&2; exit 2 ;;
esac

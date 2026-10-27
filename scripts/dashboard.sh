#!/usr/bin/env bash
# dashboard.sh [--install|--uninstall|--restart|--status|--job-file|--loop|--register <repo>|--unregister <repo>|--import <folder>]
# -- one dashboard per machine. Collects everything we measure into one
# snapshot, $HOME/.commandeck/dashboard/data.js (`window.DASH = {...};`), from
# ledgers, event logs and CLI reads. The static view in dashboard/, copied
# beside it by --install, reloads that file every 15 s. No model call, ever,
# and the page fetches nothing. No argument collects once; --loop collects
# every 60 s and is what --install runs as a user service.
# Projects: the registry $OUT/projects holds one main checkout path per line
# (--register, --unregister). Each one that has a GitHub origin is collected by
# its own run of this script (--project, internal) and lands under
# .projects[<name>]; the checkout this script runs for is the home project,
# always collected and named in .home. The machine's own readings (limit, host,
# alerts) sit at the top level, once; limit.today is kept per project.
# Sources are read, never written, with one exception: each collect runs
# subagent-usage.sh, which appends finished subagent runs to its own ledger
# before measures() reads it. Beyond $CACHE copies, limit() keeps the only
# 7-day percent history there is, in $CACHE/limit-history.jsonl, and units()
# keeps when each unit entered its stage, in $CACHE/<project>/unit-stages.json.
# A missing or failed source is null ("not measured"), never 0, and every input
# has its own record under .sources. The data contract is the view's:
# dashboard/app.js reads every key written here except measures, which is data
# only until a card reads it.
# Knobs, read by --install and kept in the service: COMMANDECK_DASHBOARD_NAME
# (the page's title), COMMANDECK_DASHBOARD_BIND (127.0.0.1; 0.0.0.0 serves the
# LAN) and COMMANDECK_DASHBOARD_PORT (unset: the first free port from 8791).
# A network bind serves HTTPS behind a login (dashboard_serve.py, issue 263): --install makes the certificate, and exits 5
# until a password is stored (dashboard_serve.py set-password <user>, issue 255).
# Test seams: COMMANDECK_DASHBOARD_DIR, plus paths.sh's COMMANDECK_* overrides.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
# Sampling never writes a worktree: git status would otherwise refresh its index.
# Porcelain git diff rewrites it even so; use diff-index for diffs.
export GIT_OPTIONAL_LOCKS=0
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/paths.sh" || exit 1
. "$HERE/host-services.sh"
. "$HERE/codex-helpers.sh" || exit 1
. "$HERE/../hooks/lib/project.sh"; pp_project "$PP_MAIN"
. "$HERE/../hooks/lib/context-size.sh"
NAME=dashboard
UNIT=commandeck-$NAME.service  # the Linux unit; another project's dashboard.service is not ours
OUT=${COMMANDECK_DASHBOARD_DIR:-$HOME/.commandeck/dashboard}
CACHE=$OUT/cache
REG=$OUT/projects
TTL=300  # slow reads: a 60 s collection would otherwise repeat them every cycle
METRICS=$PP_MAIN/.claude/metrics
# Claude Code's own folder (transcripts, task lists) is the config folder main last started under, as
# agent-startup-context.sh records it: the service runs with no pane's CLAUDE_CONFIG_DIR (issue 291).
# Set for every helper and child script too (paths.sh's session reads), in place of the caller's own.
# shortcut: one config folder per collect (main's); read each seat's own when seats run under mixed profiles.
# Read again each render: main may start under another profile while --loop runs.
claude_dir() {
  CLAUDE_DIR=$(cat "$PP_SCRATCH/claude-config-dir" 2>/dev/null)
  if [ -n "$CLAUDE_DIR" ]; then export CLAUDE_CONFIG_DIR=$CLAUDE_DIR; else unset CLAUDE_CONFIG_DIR; CLAUDE_DIR=$HOME/.claude; fi
}
claude_dir
VIEW=(index.html app.css app.js)
ws_listable() { [ -d "$PP_WORKSPACES" ] && [ -r "$PP_WORKSPACES" ] && [ -x "$PP_WORKSPACES" ]; }
BIND=${COMMANDECK_DASHBOARD_BIND:-127.0.0.1}
PORT=${COMMANDECK_DASHBOARD_PORT:-8791}
RUN='' PUB='' SRV='' ALV=''
# The heartbeat dies with the loop, or the page would read a dead collector as alive.
trap 'pp_rm_rf "${RUN:-}" "${PUB:-}"; [ -z "$SRV" ] || kill "$SRV" 2>/dev/null; [ -z "$ALV" ] || kill "$ALV" 2>/dev/null' EXIT
trap 'exit 143' TERM

iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }

# rec <id> <status> [sampled-epoch] [stale-since-epoch] [error] [retry-at-epoch] -- one source
# record, kept in this invocation's private directory: two collections at once
# never share a note.
rec() {
  jq -cn --arg id "$1" --arg st "$2" --arg at "${3:+$(iso "$3")}" --arg ss "${4:+$(iso "$4")}" --arg e "${5:-}" --arg ra "${6:+$(iso "$6")}" \
    'def n: if . == "" then null else . end;
     {($id): ({sampledAt: ($at | n), status: $st, staleSince: ($ss | n), error: ($e | n)} + (if $ra == "" then {} else {retryAt: $ra} end))}' > "$RUN/src/$1.json"
}
ok() { rec "$1" fresh "$NOW"; }
nm() { rec "$1" not-measured "" "" "$2"; }

# cached <key> <cmd>... -- the command's JSON, re-read once the copy is TTL old.
# Only a successful read that parses as JSON replaces the copy; a failed or
# malformed one keeps it, stale since its own sample time. No copy prints
# nothing and is not measured -- never a blank that reads as "nothing there".
# A failed read writes $CACHE/<key>.retry ("<retry-at epoch> <failures in a row>
# <reason>"): until then the command is skipped, so a 429 is not re-hit every
# cycle. The wait is the TTL, doubled by each failure in a row up to an hour,
# or the `retry after <n> s` the command's stderr names if longer. The source
# record carries the retry time, so the card says when the next try is.
cached() {
  local key=$1 f=$CACHE/$1 tmp=$RUN/cache-$1 err=$RUN/err-$1 m=$CACHE/$1.retry at='' tries=0 why='' rc=0 n b t
  shift
  [ ! -s "$m" ] || read -r at tries why < "$m" || true
  # A note written before failures were counted has its reason there.
  [[ $tries =~ ^[0-9]{1,4}$ ]] || { why="$tries $why"; tries=0; }
  if [ -s "$f" ] && [ $((NOW - $(stat -c %Y "$f"))) -lt $TTL ]; then
    rec "$key" fresh "$(stat -c %Y "$f")"
  elif [[ $at =~ ^[0-9]+$ ]] && [ "$at" -gt "$NOW" ]; then
    :
  elif { "$@" > "$tmp" 2>"$err"; rc=$?; [ $rc -eq 0 ] && jq -e . "$tmp" >/dev/null 2>&1; }; then
    mv -f "$tmp" "$f" && rm -f "$m" && rec "$key" fresh "$(stat -c %Y "$f")"
  else
    why=$(tail -n 1 "$err" | cut -c1-120)
    [ -n "$why" ] || { [ $rc -eq 0 ] && why='malformed response' || why='read failed'; }
    n=$(grep -oE 'retry after [0-9]+ s' "$err" | tail -n 1 | grep -oE '[0-9]+') || n=0
    n=$((10#${n:-0}))  # a leading zero must not read as octal
    tries=$((10#$tries + 1))
    b=$((TTL << (tries > 5 ? 4 : tries - 1))); [ "$b" -le 3600 ] || b=3600
    [ "$n" -gt "$b" ] || n=$b
    at=$((NOW + n))
    printf '%s %s %s\n' "$at" "$tries" "$why" > "$RUN/retry-$key" && mv -f "$RUN/retry-$key" "$m"
  fi
  if [ ! -s "$RUN/src/$key.json" ]; then
    if [ -s "$f" ]; then
      t=$(stat -c %Y "$f")
      rec "$key" stale "$t" "$t" "$why; showing the last good copy" "$at"
    else
      rec "$key" not-measured "" "" "$why; nothing was cached" "$at"
    fi
  fi
  [ ! -s "$f" ] || cat "$f"
}

# seat_age <worktree> <orca ps json> -- a pane leaves no log of its own, so its
# age is the newest thing it left: an agent state change (milliseconds), its own
# HEAD reflog, a changed or untracked file; its last commit only when none of
# those exists. A future or malformed stamp is dropped, and no stamp is null,
# never NOW.
seat_age() {
  local t
  t=$({
    [ -z "$2" ] || jq -r --arg p "$1" '.result.worktrees[]? | select(.path == $p) | (.agents // [])[] | .updatedAt | numbers | . / 1000 | floor' <<<"$2"
    if [ -e "$1/.git" ]; then
      t=$(git -C "$1" rev-parse --path-format=absolute --git-path logs/HEAD 2>/dev/null) && [ -e "$t" ] && stat -c %Y "$t"
      # --numstat compares content, so a touched but unchanged file is no activity.
      { git -C "$1" diff-index HEAD --numstat -z | while IFS=$'\t' read -r -d '' _ _ f; do printf '%s\0' "$f"; done
        git -C "$1" ls-files -o --exclude-standard -z; } 2>/dev/null \
        | (cd "$1" && xargs -0 stat -c %Y -- 2>/dev/null)
    fi
  } | awk -v now="$NOW" '/^[0-9]+$/ && $1 <= now && $1 > m { m = $1 } END { if (m != "") print m }')
  [ -n "$t" ] || [ ! -e "$1/.git" ] || t=$(git -C "$1" log -1 --format=%ct 2>/dev/null | awk -v now="$NOW" '/^[0-9]+$/ && $1 <= now')
  if [ -n "$t" ]; then echo $((NOW - t)); else echo null; fi
}

# open_tasks <run> -- the ids of the run's tasks not yet completed or failed
# (board.sh's rule). An Orca refusal is a failed read, never "no open tasks".
open_tasks() {
  timeout 15 orca-ide orchestration task-list --run "$1" --json \
    | jq -ce '.result.tasks | arrays | map(select(.status != "completed" and .status != "failed") | .id)'
}

# seat_role <unit> <worktree> <open task ids json> <orca ps json> -- "<stage>\t<role>"
# of the newest live seat for exactly this unit: a seat record (seat.sh launch)
# whose Orca task is still open. A record launched before Orca created the
# worktree belongs to an older unit of the same name. Prints nothing when no
# record is live or the newest one's role has no stage. A record is matched by the worktree it names (a planner of
# <unit> runs in <unit>-plan, and its seat-<unit>-plan-<seat>.txt is in this glob), else by its unit.
seat_role() {
  local f created=''
  [ -z "$4" ] || created=$(jq -r --arg p "$2" '[.result.worktrees[]? | select(.path == $p) | .createdAt | numbers][0] // empty | . / 1000 | floor' <<<"$4")
  for f in "$PP_SCRATCH/seat-$1-"*.txt; do
    [ ! -f "$f" ] || awk '{ i = index($0, "="); if (i) v[substr($0, 1, i - 1)] = substr($0, i + 1) }
      END { print v["launched"] "\t" v["role"] "\t" v["task"] "\t" (v["worktree"] != "" ? v["worktree"] : v["unit"]) }' "$f"
  done | jq -Rrn --arg u "$1" --argjson open "$3" --arg c "$created" --argjson lanes "$ROLE_LANES" '
    [inputs | split("\t") | select(.[3] == $u and (.[0] | test("^[0-9]+$")) and .[1] != ""
      and (.[2] as $t | any($open[]; . == $t)) and ($c == "" or (.[0] | tonumber) >= ($c | tonumber)))]
    | max_by(.[0] | tonumber) // empty | .[1] as $r | ($lanes[$r] // empty) + "\t" + $r'
}

# The --model and --effort a seat record's cmd= line launched with (Codex's model_reasoning_effort too), null when absent.
SEAT_FLAGS_JQ='def seat_model: (capture("--model[ =](?<m>[^ ;[]+)") | .m) // null;
  def seat_effort: (capture("--effort[ =](?<l>[a-z]+)|model_reasoning_effort=\"?(?<c>[a-z]+)") | .l // .c) // null;'

# plan_seats <unit> [before-iso] -- the unit's planning, read from its plan seats' records (seat.sh launch; never
# deleted), so it outlives the planning worktree, <unit> or <unit>-plan before 0.18.0: {worktree (the newest record's), from (the first launch, a relaunched seat's first= too), seats: [{role, task, from, model, effort,
# session, completedAt}]}, or null. Model and effort are the record's command's (--model, --effort, Codex's
# model_reasoning_effort); session its Claude id or its bound log path (seat.sh bind_session), else the seat ledger row's log (a collected Codex judge), which
# also gives completedAt. With `before`, only seats first launched before it: a Builder's own planning, a planner
# relaunched after the Builder started included (Sol r4).
# shortcut: keyed by unit name, so a unit planned twice before its Builder counts both; key by build if it matters.
plan_seats() {
  local f
  for f in "$PP_SCRATCH/seat-$1-"*.txt; do
    [ ! -f "$f" ] || awk '{ i = index($0, "="); if (i) v[substr($0, 1, i - 1)] = substr($0, i + 1) }
      END { print v["launched"] "\t" v["role"] "\t" v["task"] "\t" v["unit"] "\t" v["worktree"] "\t" v["session"] "\t" v["cmd"] "\t" v["first"] }' "$f"
  done | jq -Rn --arg u "$1" --arg b "${2:-}" --arg ws "$PP_WORKSPACES" \
    --slurpfile ev <(jq -cR 'fromjson? | objects | select(.taskId | type == "string")' "$METRICS/seat-events.jsonl" 2>/dev/null) "$SEAT_FLAGS_JQ"'
    ($ev | map({key: .taskId, value: .}) | from_entries) as $e
    | [inputs | split("\t") | select(length == 8 and .[3] == $u and (.[4] == $u or .[4] == "\($u)-plan") and (.[0] | test("^[0-9]+$")))
       | ([.[0], .[7]] | map(tonumber? // empty) | min) as $f
       | select($b == "" or $f < ($b | fromdateiso8601)) | ($e[.[2]] // {}) as $r
       | {role: .[1], task: .[2], from: (.[0] | tonumber | todate), first: $f, wt: .[4],
          model: ((.[6] | seat_model) // $r.model // null),
          effort: (.[6] | seat_effort),
          session: (if .[5] != "" then .[5] else $r.session // null end), completedAt: ($r.completedAt // null)}]
    | sort_by(.first) | if length == 0 then null else {worktree: "\($ws)/\(max_by(.from) | .wt)", from: (map(.first) | min | todate), seats: map(del(.first, .wt))} end'
}

# launch_roster <unit> <the Builder card's json> -- issue 292: what this unit's current round launched as: the Builder's
# own seat record (model, effort), then each reviewer pass of its highest round (dashboard_builders.jq passes). A Builder
# with neither record has [].
launch_roster() {
  local cmd=
  [ ! -f "$PP_SCRATCH/seat-$1-builder.txt" ] || cmd=$(sed -n 's/^cmd=//p' "$PP_SCRATCH/seat-$1-builder.txt" | tail -1)
  jq -cn --arg c "$cmd" --argjson b "$2" "$SEAT_FLAGS_JQ"'[if $c == "" then empty else {role: "builder", model: ($c | seat_model), effort: ($c | seat_effort)} end] + ($b.passes // [])'
}

# seat_actual <worktree> -- what the seat really runs: the model, effort and advisor on the last
# main-thread reply of the worktree's newest Claude session record. No record, or none in its tail, is null.
# shortcut: reads the newest record's last 40 rows and Claude records only, so a Codex seat reads null.
seat_actual() {
  local f
  f=$(pp_session_log "$1")
  [ -n "$f" ] && tail -n 40 "$f" 2>/dev/null | jq -cR 'fromjson? | objects | select(.type == "assistant" and .isSidechain != true and (.message.model | type) == "string")
    | {model: .message.model, effort: (.effort | strings // null), advisor: (.advisorModel | strings // null), at: (.timestamp // null)}' 2>/dev/null | tail -1 | grep . || echo null
}
# builder_progress <worktree> <unit> -- a Builder's {issues, built, findings, raised}, each null when its file is
# missing. Built is false for an evidence file that is there and cannot be read, and an empty list
# only for one read with no built item in it. Issues are the work items brief-issues.sh reads from the brief
# and main's rulings file for the unit: an issue is its number, an item with no issue number its own text.
# Built ones are the items its evidence file heads a section with, findings the newest round report's finding lines.
builder_progress() {
  local d=$1/.claude/briefs u=${2##*/} is=null bu=null pa=null fi_=null f t tb
  [ ! -f "$d/$u.md" ] || is=$(bash "$HERE/brief-issues.sh" "$d/$u.md" "$PP_MAIN/.claude/briefs/$u-main-rulings.md")
  # The file's title names the unit's issue before anything is built: only a section heading counts.
  # A heading "Item N" with no issue number stands for the items on numbered line N of the brief
  # or of main's rulings file, those of the issue list only. An item with no issue number is built
  # under "Item N" too, or under a heading that is its text, whole: a heading holding a shorter item's words is not that item.
  # shortcut: two numbered lists that both name listed issues on line N are both read; mark the list if one ever does.
  # A heading counts once something is written under it, before the next heading: one with nothing under it is
  # a section laid out ahead of the work. What is written under a sub-heading is written under its item too.
  # A table with Issue and Status columns, under "## Per issue" or anywhere, rules for each issue a row starts with:
  # a status starting "built" is built, any other ("partly built", "blocked") is not, a heading naming it or not.
  [ ! -f "$d/$u-evidence.md" ] || bu=false
  [ -f "$d/$u-evidence.md" ] && [ -r "$d/$u-evidence.md" ] && tb=$(awk -F'|' '/^\|/ { a = $2; s = $3; gsub(/^[ \t]+|[ \t]+$/, "", a); gsub(/^[ \t]+|[ \t]+$/, "", s)
      if (tolower(a) == "issue" && tolower(s) == "status") { on = 1; next }
      if (on && match(a, /^#[0-9]+/)) print (tolower(s) ~ /^built([^a-z]|$)/ ? "+" : "-") substr(a, RSTART, RLENGTH); next } { on = 0 }' "$d/$u-evidence.md") \
    && bu=$({ awk '/^#+ /{ l = length($1); for (k in h) if (k + 0 >= l) delete h[k]; h[l] = $0; next }
      NF { for (k in h) if (k + 0 >= 2) { print h[k]; delete h[k] } }' "$d/$u-evidence.md" | while IFS= read -r f; do
      grep -oE '#[0-9]+' <<<"$f"
      [ "$is" != null ] || continue
      t=$(sed -E 's/^#+ +//; s/[[:space:]:.]+$//' <<<"$f")
      jq -r '.[] | strings' <<<"$is" | grep -xF -- "$t" | sed 's/^/=/' || true
      [[ $f =~ ^#+\ Item\ ([0-9]+) ]] || continue
      t=$(grep -hE "^${BASH_REMATCH[1]}\. " "$d/$u.md" "$PP_MAIN/.claude/briefs/$u-main-rulings.md" 2>/dev/null)
      grep -oE '#[0-9]+' <<<"$t" | grep -xFf <(jq -r '.[] | numbers | "#\(.)"' <<<"$is")
      sed -E 's/^[0-9]+\. +//; s/[[:space:]:.]+$//' <<<"$t" | grep -xFf <(jq -r '.[] | strings' <<<"$is") | sed 's/^/=/'
    done; sed -n 's/^+//p' <<<"$tb"; } | grep -vxFf <(sed -n 's/^-//p' <<<"$tb") | bash "$HERE/brief-issues.sh" --list)
  # Partial: the issues that table marks not built; a merge gives them Refs, not Closes (merge-unit-local.sh).
  [ -z "${tb:-}" ] || pa=$(sed -n 's/^-//p' <<<"$tb" | bash "$HERE/brief-issues.sh" --list)
  f=$(ls -t "$d/$u"-r*-reports.md 2>/dev/null | head -1)
  [ -z "$f" ] || fi_=$(grep -oE '^[[:space:]]*[-*] \[P[0-3]\]' "$f" | grep -oE 'P[0-3]' | jq -Rcn '[inputs] as $p | [range(0; 4) | "P\(.)" as $k | {key: $k, value: ($p | map(select(. == $k)) | length)}] | from_entries')
  # Raised: the effort main raised the Builder to and why, from the line builder-launch.sh writes in its brief.
  t=$(grep -m1 -E '^effort override: builder [a-z]+ -> [a-z]+: ' "$d/$u.md" 2>/dev/null || true)
  jq -cn --argjson is "$is" --argjson bu "$bu" --argjson pa "$pa" --argjson fi "$fi_" --arg ra "$t" \
    '{issues: $is, built: $bu, partial: $pa, findings: $fi, raised: ($ra | capture("^effort override: builder [a-z]+ -> (?<effort>[a-z]+): (?<reason>.+)$") // null)}'
}
# terminal_list -- Orca's terminal list, read once per collect into $DASH_TERMS for every project's units() and
# chief_of_staff() (issue 299); fails, for all of them, when the read or its shape does (the failure is kept too, so a
# down Orca is asked once, not once a reader).
terminal_list() {
  local f=$DASH_TERMS t
  if [ ! -e "$f" ] && [ ! -e "$f.bad" ]; then
    t=$f.$BASHPID
    if timeout 8 orca-ide terminal list --json > "$t" 2>/dev/null && jq -e 'has("result")' "$t" >/dev/null 2>&1; then mv -f "$t" "$f"
    else rm -f "$t"; : > "$f.bad"; fi
  fi
  [ -e "$f" ] && cat "$f"
}
# One projection for the board: every worktree of this project. Orca lists the
# whole machine's worktrees, so every lookup is by path, never by name: two
# projects may each have a unit of one name.
# merged <unit> -- only committed evidence says merged (issue 343), never a clock or a leftover worktree: (a) the worktree
# HEAD is in main and the branch's newest reflog entry is the unit's own work (a tip placed there by `git worktree add`
# or builder-launch.sh's reset, entries `branch:` and `reset:`, is main's own commit, issue 354), or
# (b) a finished-builds line (merge-unit-local.sh's squash commit, listed in $RUN/merge-shas) names a commit main holds
# that the worktree HEAD does not contain (a name reused for new work branches after its old merge). Both guards only
# turn "merged" into "live". shortcut: a squash merge made outside merge-unit-local.sh leaves no line, so it reads live.
merged() {
  local head ref newest sha
  if head=$(git -C "$PP_WORKSPACES/$1" rev-parse -q --verify HEAD 2>/dev/null) \
     && git -C "$PP_MAIN" cat-file -e "$head^{commit}" 2>/dev/null \
     && git -C "$PP_MAIN" merge-base --is-ancestor "$head" main 2>/dev/null; then
    ref=$(git -C "$PP_WORKSPACES/$1" symbolic-ref -q HEAD 2>/dev/null)
    newest=$([ -z "$ref" ] || git -C "$PP_MAIN" reflog show -1 --format=%gs "$ref" 2>/dev/null)
    case $newest in ''|branch:*|reset:*) ;; *) return 0 ;; esac
  fi
  for sha in $(awk -F'\t' -v u="$1" '$1 == u { print $2 }' "$RUN/merge-shas"); do
    git -C "$PP_MAIN" merge-base --is-ancestor "$sha" main 2>/dev/null || continue
    [ -n "$head" ] && git -C "$PP_MAIN" merge-base --is-ancestor "$sha" "$head" 2>/dev/null && continue
    return 0
  done
  return 1
}

units() {
  local ps='' u wt ag st branch dirty diff age seat s run open='' role sr rd bj bl rows b v vr f po pj rs
  if ps=$(timeout 8 orca-ide worktree ps --json 2>/dev/null) && jq -e . >/dev/null 2>&1 <<<"$ps"; then ok orca
  else ps=''; nm orca "orca-ide worktree ps failed"; fi
  # Per worktree, the lane of each working pane's role: its recorded launch
  # title (open_pane's record; agents retitle their panes), else its live title.
  local ts pl='{}'
  if [ -z "$ps" ]; then nm orca-terminals "no worktree list to join the panes to"
  else
    if ts=$(terminal_list); then ok orca-terminals
    else ts=null; nm orca-terminals "orca-ide terminal list failed"; fi
    pl=$(jq -cn --slurpfile ps <(printf '%s' "$ps") --slurpfile ts <(printf '%s' "$ts") --argjson w "$(lane_words)" \
      --rawfile rec <(cat "$PANE_TITLES" 2>/dev/null) "$TITLE_LANE_JQ"'
      ($rec | split("\n") | map(split("\t") | select(length >= 3) | {key: .[2], value: .[1]}) | from_entries) as $t
      | ($ts[0].result // [] | if type == "array" then . else (.terminals // []) end
        | map(.handle as $h | {key: "\(.tabId):\(.leafId)", value: ($t[$h] // .title // "")}) | from_entries) as $p
      | [$ps[0].result.worktrees[]? | {key: (.path // ""), value: [(.agents // [])[] | select(.state == "working") | $p[.paneKey // ""] // "" | title_lane($w)]}]
      | from_entries') || { pl='{}'; nm orca-terminals "the pane role join failed"; }
  fi
  if ws_listable; then ok worktrees; elif [ -d "$PP_WORKSPACES" ]; then nm worktrees "$PP_WORKSPACES cannot be listed"; else nm worktrees "no $PP_WORKSPACES"; fi
  if run=$(tr -d '[:space:]' 2>/dev/null < "$PP_RUN_FILE") && [ -n "$run" ]; then
    open=$(cached orca-tasks open_tasks "$run")
  else nm orca-tasks "no Orca run named in $PP_RUN_FILE"; fi
  # (unit, sha) of every merge this checkout made (finished_builds): merged()'s committed evidence.
  finished_builds | jq -r '.[]? | "\(.unit)\t\(.sha)"' > "$RUN/merge-shas" 2>/dev/null || : > "$RUN/merge-shas"
  for wt in "$PP_WORKSPACES"/*/; do
    wt=${wt%/}; [ -e "$wt/.git" ] || continue
    u=${wt##*/}
    # A merged unit leaves the in-flight list even while its worktree stays (finishedBuilds lists it). Seats are not units.
    pp_standing_wt "$u" || ! merged "$u" || continue
    # A plan seat's worktree, marked by seat.sh, is the unit's Planning stage until the Builder's launch adopts it and
    # drops the mark: <unit> itself, or <unit>-plan for a unit planned before 0.18.0, whose card the unit's own
    # worktree carries when it is there: one unit, one card.
    po=$(cat "$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null)/commandeck-plan-of" 2>/dev/null) || po=
    case $po in
      ''|"$u") ;;
      "${u%-plan}") [ ! -e "$PP_WORKSPACES/$po/.git" ] || continue ;;
      *) po= ;;
    esac
    # The relay's and the lanes' worktrees are seats, not units. Exact names only (pp_standing_wt); app.js SEATS names the same stages.
    seat=; ! pp_standing_wt "$u" || seat=$(printf '%s' "$u" | tr 'A-Z' 'a-z')
    ag=null
    [ -z "$ps" ] || ag=$(jq -c --arg p "$wt" '[.result.worktrees[]? | select(.path == $p) | (.agents // [])[] | "\(.agentType):\(.state)"] | join(" ")' <<<"$ps")
    branch=null dirty=null diff=null
    branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null) && branch=$(jq -Rc . <<<"$branch") || branch=null
    # A failed read stays null, never a clean 0; "" is a measured clean diff.
    s=$(git -C "$wt" status --porcelain 2>/dev/null) && dirty=$(grep -c . <<<"$s")
    s=$(git -C "$wt" diff-index HEAD --shortstat 2>/dev/null) && diff=$(jq -Rc 'sub("^ +"; "")' <<<"$s")
    # Orca lists panes and none is working: the pane finished, so the unit
    # waits on main, aged from what the pane left. Unknown stays null.
    st=null age=null pj=null
    if [ -n "$po" ]; then st='"planning"'; age=$(seat_age "$wt" "$ps"); pj=$(plan_seats "$po")
    elif [ "$ag" != null ] && [ "$ag" != '""' ] && [[ $ag != *:working* ]]; then
      st='"waiting-main"'; age=$(seat_age "$wt" "$ps")
    fi
    # A live seat record's role sets the stage through ROLE_LANES; a seat role leaves it as read.
    sr=null rs=null
    if [ -z "$seat" ] && [ -n "$open" ]; then
      IFS=$'\t' read -r s role <<<"$(seat_role "$u" "$wt" "$open" "$ps")" || true
      [ -z "$role" ] || { st=$(jq -Rc . <<<"$s"); sr=$(jq -Rc . <<<"$role"); age=$(seat_age "$wt" "$ps"); }
    fi
    # Orca's live state outranks the record: a working pane's role sets the
    # lane, and with several the latest lane in the flow wins. A seat role sets
    # none. A working agent whose pane names no role is still working, so a
    # waiting or unknown stage reads building.
    s=$(jq -r --arg p "$wt" --argjson o "$LANE_ORDER" '(.[$p] // []) as $l
      | ([$l[] | select(. as $x | $o | index($x))] | max_by(. as $x | $o | index($x)))
        // (if any($l[]; . == "unknown") then "unknown" else empty end)' <<<"$pl")
    case $s in
      '') ;;
      unknown) [ "$st" != '"waiting-main"' ] && [ "$st" != null ] || { st='"building"'; age=$(seat_age "$wt" "$ps"); } ;;
      *) st="\"$s\""; age=$(seat_age "$wt" "$ps") ;;
    esac
    [ -z "$seat" ] || { st="\"$seat\""; age=$(seat_age "$wt" "$ps"); }
    rd=null
    # A Builder (COMMANDECK_BUILDER in its settings.local.json) is drawn from its
    # own event log. A log it cannot read is not measured, never an empty Builder.
    bj=null
    if [ -z "$seat" ] && [ "$(jq -r '.env.COMMANDECK_BUILDER // empty' "$wt/.claude/settings.local.json" 2>/dev/null)" = 1 ]; then
      st=null age=null sr=null b='{}'
      bj='{"steps":null,"signals":null,"verdict":null,"verdictRound":null}'
      bl=$wt/.claude/builder-events.jsonl
      # The Builder's newest session record, read once (issue 299): its mtime and open background jobs serve the stage
      # below, its path the cache rate further down.
      pp_session_summary "$wt"
      if [ ! -e "$bl" ]; then st='"building"' bj='{"steps":[],"signals":[],"verdict":null,"verdictRound":null}'
      elif rows=$(jq -cR 'fromjson? | objects' "$bl" 2>/dev/null) && b=$(jq -cs --argjson now "$NOW" --argjson sessionAt "$PP_SESSION_AT" --argjson bgOpen "$PP_SESSION_BG" -f "$HERE/dashboard_builders.jq" <<<"$rows" 2>/dev/null); then
        st=$(jq -c '.stage' <<<"$b"); rd=$(jq -c '.round' <<<"$b")
        age=$(jq -c --argjson now "$NOW" '.lastAt | if . == null then null else [$now - fromdateiso8601, 0] | max end' <<<"$b")
        bj=$(jq -c '{steps, signals, verdict: null, verdictRound: null}' <<<"$b")
        bj=$(jq -c --argjson b "$b" '. + ($b | {startedAt, reviewSec, waiting, stageHistory})' <<<"$bj")
      else : > "$RUN/builder-bad"; fi
      # No working agent leaves the Builder waiting on main; an unread agent list keeps the log's stage, and so
      # does a helper, pass or call of its own still out: an idle pane waits on that, not on main (#41).
      [ "$st" = null ] || [ "$ag" = null ] || [[ $ag == *:working* ]] || [ "$(jq '.waiting | length' <<<"$b")" != 0 ] || st='"waiting-main"'
      f=$(pp_unit_briefs "$wt/.claude/briefs" "$u" | grep -- '-reports\.md$' | tr '\n' '\0' | xargs -0 -r ls -t 2>/dev/null | head -1)
      # The verdict keeps its report's round (<unit>-r<N>-reports.md): the card shows it beside that round only.
      if [ -n "$f" ]; then
        v=$(grep -v '^[[:space:]]*$' "$f" | tail -1 | cut -c1-200)
        vr=${f##*/}; vr=${vr#"${u##*/}-r"}; vr=${vr%-reports.md}
        [[ $vr =~ ^[0-9]+$ ]] && vr=$((10#$vr)) || vr=null
        bj=$(jq -c --arg v "$v" --argjson vr "$vr" '.verdict = $v | .verdictRound = $vr' <<<"$bj")
      fi
      # Every finished round's own verdict by its round, so each pass shows its own: its report file's last line, else
      # "verdict file gone" (issue 343): no pass shows a blank verdict. shortcut: a Codex result file is no fallback here,
      # the pass script keeps none; add one if it ever does.
      vs='{}'
      while IFS= read -r r; do
        n=${r##*/}; n=${n#"${u##*/}-r"}; n=${n%-reports.md}
        [[ $n =~ ^[0-9]+$ ]] && vs=$(jq -c --arg n "$((10#$n))" --arg v "$(grep -v '^[[:space:]]*$' "$r" | tail -1 | cut -c1-200)" '.[$n] = $v' <<<"$vs")
      done < <(pp_unit_briefs "$wt/.claude/briefs" "$u" | grep -- '-reports\.md$')
      if [[ $rd =~ ^[0-9]+$ ]]; then
        for ((n = 1; n <= rd; n++)); do
          jq -e --arg n "$n" 'has($n)' >/dev/null <<<"$vs" || vs=$(jq -c --arg n "$n" '.[$n] = "verdict file gone"' <<<"$vs")
        done
      fi
      [ "$vs" = '{}' ] || bj=$(jq -c --argjson vs "$vs" '.verdicts = $vs' <<<"$bj")
      # An unreadable log stays wholly not measured; any other Builder also carries its issues and findings.
      # reviewedTree: is the worktree still the tree its newest pass read. The build review reads the same script.
      [ "$(jq -c '.steps' <<<"$bj")" = null ] || bj=$(jq -c --argjson p "$(builder_progress "$wt" "$u")" --argjson rt "$(bash "$HERE/reviewed-tree.sh" "$wt" "${u##*/}" 2>/dev/null || echo null)" '. + $p + {reviewedTree: $rt}' <<<"$bj")
      # cache24h: a Builder writes no seat rows, so its 24 h cache hit rate is its own session's usage. With no
      # session log or no turn in 24 h there is no rate to judge and no key; null is a log that failed to read.
      if [ "$(jq -c '.steps' <<<"$bj")" != null ] && f=$PP_SESSION_LOG && [ -n "$f" ]; then
        cu=$(bash "$HERE/seat-event.sh" --usage claude "$f" $((NOW - 86400)) 2>/dev/null) && jq -e 'type == "object" or . == null' >/dev/null 2>&1 <<<"$cu" || cu='{"tokens":null}'
        [ "$cu" = null ] || bj=$(jq -c --argjson c "$cu" '. + {cache24h: $c.tokens}' <<<"$bj")
        # Its live context, against the clear line past which it hands off (the hook context-line.sh).
        bj=$(jq -c --arg c "$(context_size "$f")" --arg l "$(pp_builder_clear_line "$PP_MAIN" 2>/dev/null)" \
          '. + {context: ($c | tonumber? // null), clearLine: (if $l == "" then null else $l end)}' <<<"$bj")
      fi
      # Its planning, launched before its first stage, though the planning worktree is gone.
      pj=$(plan_seats "$u" "$(jq -r '.stageHistory[0].from // empty' <<<"$b" 2>/dev/null)")
      rs=$(launch_roster "$u" "$b") || rs=null
    fi
    jq -cn --arg u "$u" --argjson branch "$branch" --argjson dirty "$dirty" --argjson diff "$diff" --argjson ag "$ag" \
      --argjson st "$st" --argjson age "$age" --argjson sr "$sr" --argjson rd "$rd" --argjson bj "$bj" --argjson pj "${pj:-null}" --argjson rs "$rs" \
      '{unit: $u, worktree: true, branch: $branch, dirty: $dirty, diffStat: $diff, agents: $ag, stage: $st, seatRole: $sr, ageSec: $age, round: $rd, builder: $bj, plan: $pj, seats: $rs}' \
      | jq -c --argjson seat "$(seat_actual "$wt")" '. + {seat: $seat}'
  done > "$RUN/in-flight.jsonl"
  if [ -e "$RUN/builder-bad" ]; then nm builder-logs "a Builder event log could not be read"; else ok builder-logs; fi
  # Time in stage: no log line carries a time, so the collect that first sees a
  # unit's stage and round stamps it. A unit seen for the first time was there
  # for at least that long (exact false). Units no longer listed drop out; an
  # unreadable unit list leaves the record as it was.
  local stages=$CACHE/unit-stages.json old known=true
  old=$(jq -ce 'objects' "$stages" 2>/dev/null) || old='{}'
  jq -cs --slurpfile oa <(printf '%s' "$old") --argjson now "$NOW" '$oa[0] as $o | map(. as $u | $o[$u.unit] as $p
      | (if ($p | type) == "object" and ($p.since | type) == "number" and $p.stage == $u.stage and $p.round == $u.round then $p
         else {stage: $u.stage, round: $u.round, since: $now, exact: ($p != null)} end) as $r
      | $u + {stageSince: ($r.since | todate), stageExact: $r.exact, rec: $r})' "$RUN/in-flight.jsonl" > "$RUN/in-flight.json" || return 1
  # Without the workspace directory, or one that cannot be listed, the unit list is unknown, not empty.
  if ws_listable; then
    jq -c 'map({(.unit): .rec}) | add // {}' "$RUN/in-flight.json" > "$RUN/unit-stages" && mv -f "$RUN/unit-stages" "$stages"
  else known=false; fi
  # Each Builder's cost by stage (#94), from its worktree's own sessions, its planning first. The last figures
  # read for each unit are kept, so a finished build shows them as they stood at its merge.
  # shortcut: kept by unit name, so a later build under the same name replaces an earlier one's; key by build if that matters.
  local costs kept=$CACHE/unit-cost.json had
  if costs=$(jq -c --arg ws "$PP_WORKSPACES" '[.[] | select((.builder.stageHistory | type == "array" and length > 0) or .plan != null)
        | {unit, worktree: "\($ws)/\(.unit)", stages: (.builder.stageHistory | arrays // []), plan}]' "$RUN/in-flight.json" \
      | python3 "$HERE/dashboard_limit.py" units "$NOW" "$REQS" "$CLAUDE_DIR/projects" "${CODEX_HOME:-$HOME/.codex}/sessions" 2>"$RUN/err-unit-cost") \
      && jq -e 'objects' >/dev/null 2>&1 <<<"$costs"; then
    ok unit-cost
    # A kept file there but unreadable (or a directory) is left as it is: read as empty, the write would lose every
    # earlier unit's cost. One that reads but is not an object is corrupt, and starts again empty.
    if [ ! -e "$kept" ]; then had='{}'
    elif had=$(cat "$kept" 2>/dev/null); then had=$(jq -ce 'objects' <<<"$had" 2>/dev/null) || had='{}'
    else had=; fi
    # Files, not --argjson: the kept costs grow by one unit a build, and past the 1 MB argument limit (ARG_MAX) jq
    # would fail every collect (issue 280).
    [ -z "$had" ] || { jq -cn --slurpfile oa <(printf '%s' "$had") --slurpfile ca <(printf '%s' "$costs") '$oa[0] as $o | $ca[0] as $c
      | $o + ($c | with_entries(select(.value != null)))' > "$kept.$$" && mv -f "$kept.$$" "$kept"; }
  else costs=null; nm unit-cost "Builder costs could not be read: $(head -1 "$RUN/err-unit-cost" 2>/dev/null)"; fi
  # Issue 292: the owner's Builder cap (maxBuilders in /config); none, or no whole number, is unknown.
  local cap; cap=$(pp_option maxBuilders 2>/dev/null); [[ $cap =~ ^[1-9][0-9]*$ ]] || cap=
  # Issue 292: the finished builds whose merge commit main has and its upstream lacks (the range next_push reads); null
  # with no upstream or no readable range.
  local pushed
  pushed=$(git -C "$PP_MAIN" rev-list '@{upstream}..HEAD' 2>/dev/null | jq -Rcn '[inputs]') && [ -n "$pushed" ] || pushed=null
  jq -c --argjson k "$known" --argjson cap "${cap:-null}" --slurpfile fina <(finished_builds) --slurpfile ca <(printf '%s' "$costs") \
    --slurpfile kepta <(jq -ce 'objects' "$kept" 2>/dev/null || echo '{}') --arg s7 "$(since7)" --argjson pushed "$pushed" --slurpfile pka <(parked_units "$open") \
    '$fina[0] as $fin | $ca[0] as $c | $kepta[0] as $kept | {inFlight: (if $k then (map(del(.rec) | ($c[.unit]? // null) as $x
        # A planning stage in the cost is drawn first on the Builder clock, which then starts with it.
        | if .builder then .builder.cost = $x
            | if $x.stages[0].stage? == "planning" and (.builder.stageHistory | type == "array")
              then .builder.stageHistory = [$x.stages[0] | {stage, from, to}] + .builder.stageHistory | .builder.startedAt = $x.stages[0].from
              else . end
          elif .plan then .plan.cost = $x else . end) as $rows
        # A parked unit (parked_units) joins after the stage stamps and costs: it has neither.
        | $rows + ($pka[0] | map(select(.unit as $u | all($rows[]; .unit != $u))))) else null end),
      builderCap: $cap,
      mergedSincePush: (if $pushed == null or $fin == null then null else $fin | map(select(.sha as $h | $pushed | index([$h]))) end),
      finishedBuilds: (if $fin == null then null else $fin | map(. + {cost: ($kept[.unit] // null)}) end),
      # Issue 270: each unit in flight or finished in the last 7 days, by the cost its card shows, most costly first.
      costPerUnit: ([($c // {} | keys[] | {unit: ., inFlight: true}), ($fin // [] | .[] | select((.at // "") >= $s7) | {unit, inFlight: false, at})]
        | unique_by(.unit) | map(. + (($c // {})[.unit] // $kept[.unit] // {} | {total, stages}) | select(.total != null))
        | sort_by(-(.total.usd // 0)))}' "$RUN/in-flight.json"
}

# parked_units <open task ids json> -- issue 292: the units whose Builder pane and worktree are gone but whose Orca task is
# still open, read from the seat records as seat_role reads them: one row {unit, worktree: false, stage: null, role,
# task} per unit, from its newest record naming an open task. A unit with its own worktree (or its planning one) is a
# card already. No run, or no open-task read, is no parked unit.
parked_units() {
  local f u rows
  [ -n "$1" ] || { echo '[]'; return 0; }
  rows=$(for f in "$PP_SCRATCH"/seat-*.txt; do
    [ ! -f "$f" ] || awk '{ i = index($0, "="); if (i) v[substr($0, 1, i - 1)] = substr($0, i + 1) }
      END { print v["unit"] "\t" v["launched"] "\t" v["role"] "\t" v["task"] }' "$f"
  done | jq -Rn --argjson open "$1" '[inputs | split("\t") | select(length == 4 and .[0] != "" and .[2] != "" and (.[1] | test("^[0-9]+$"))
      and (.[3] as $t | any($open[]; . == $t)))] | group_by(.[0]) | map(max_by(.[1] | tonumber) | {unit: .[0], worktree: false, stage: null, role: .[2], task: .[3]}) | .[]')
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    u=$(jq -r .unit <<<"$f")
    [ -e "$PP_WORKSPACES/$u/.git" ] || [ -e "$PP_WORKSPACES/$u-plan/.git" ] || echo "$f"
  done <<<"$rows" | jq -cs .
}

# Finished builds: the lines this checkout's own merges appended (merge-unit-local.sh), one per unit name with the
# later line winning, newest first, no cap (issue 292; the file grows a line a build). A line counts when it names this checkout's real path, a unit and a
# commit: another checkout of the same folder name shares the file and none of the list. Each line is read alone, so
# one that is torn or is not a build is dropped, and an empty record is no finished build. No record that can be read is not measured (null): nothing was
# merged here by the plugin yet. The file is named by this project's own name, never by the page.
finished_builds() {
  local out f=$HOME/.commandeck/builds/$PP_PROJECT.jsonl
  [ -f "$f" ] && [ -r "$f" ] || { echo null; return 0; }
  out=$(jq -cR --arg main "$(cd "$PP_MAIN" && pwd -P)" 'fromjson? | objects | select(.main == $main
        and (.unit | type) == "string" and (.unit | test("^[A-Za-z0-9._-]+$")) and (.sha | type) == "string" and (.sha | test("^[0-9a-f]{40,64}$")))
      | {unit, how: (.how | strings // null), at: (.at | strings // null), sha}' \
      "$f" 2>/dev/null \
    | jq -cs 'reduce .[] as $r ({}; .[$r.unit] = $r) | [.[]] | sort_by(.at) | reverse' 2>/dev/null) || out=
  echo "${out:-[]}"
}

# What waits on the owner is the decision ledger. The owner is whoever runs the plugin here: git's user.name for
# this checkout, else the account's name, cut to one line of 80 characters; neither is null.
needs_owner() {
  local dec=null name unsent picker
  name=$(git -C "$PP_MAIN" config user.name 2>/dev/null) || name=
  [ -n "${name//[[:space:]]/}" ] || name=$(id -un 2>/dev/null) || name=
  if [ ! -e "$METRICS/decisions.jsonl" ]; then nm decisions "no ledger at $METRICS/decisions.jsonl"
  elif dec=$(COMMANDECK_MAIN=$PP_MAIN bash "$HERE/decision.sh" list 2>"$RUN/err-decisions"); then
    ok decisions; dec=$(jq -c 'map(select(.answeredAt == null))' <<<"$dec")
  else dec=null; nm decisions "$(head -1 "$RUN/err-decisions")"; fi
  # Issue 240: this project's answers from the page whose send failed; dashboard_serve.py keeps them and sends them
  # again on each refresh. Issue 295: each with its key (what the page's buttons send back), whether the host gave up
  # on it and why, its tries since its first, and its last error.
  unsent=$(jq -c --arg m "$PP_MAIN" '[.[]? | select(.main == $m) | {id, to, key: (.key // null), state: (.state // "pending"), reason: (.reason // null),
      tries: (.tries // 0), firstAt: (.firstAt // null), lastError: (.lastError // null)}]' "$OUT/answer-retry.json" 2>/dev/null) || unsent='[]'
  # And the ones delivered while main's own picker was open: main reads them only once that picker is answered.
  picker=$(jq -c --arg m "$PP_MAIN" '[.[]? | select(.main == $m) | .id | strings]' "$OUT/answer-picker.json" 2>/dev/null) || picker='[]'
  jq -cn --slurpfile deca <(printf '%s' "$dec") --arg name "$name" --slurpfile ua <(printf '%s' "${unsent:-[]}") --slurpfile pka <(printf '%s' "${picker:-[]}") \
    '$deca[0] as $dec | $ua[0] as $u | $pka[0] as $pk | {decisions: $dec, unsent: $u, picker: $pk, name: ($name | gsub("[[:cntrl:]]+"; " ") | gsub("^ +| +$"; "") | .[:80] | if . == "" then null else . end)}'
}

# owner/name of the checkout's GitHub origin, or nothing. Every gh read names it as GH_REPO, so a gh default set
# to another remote (an upstream) cannot mix that repository's issues, checks and pull requests into the page's links.
origin_repo() {
  git -C "$PP_MAIN" config --get remote.origin.url 2>/dev/null \
    | sed -nE 's#^(https://([^/@]+@)?|ssh://git@|git@)github\.com[:/]([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/?$#\3#p' | sed 's/\.git$//'
}

# The project's open GitHub issues labelled P1 (the exact label), listed in the repository of its GitHub origin,
# or with none the one gh resolves from this checkout: a GH_REPO or GH_HOST of the caller's would name one
# repository for every project. A list that cannot be had (no gh, not
# signed in, no GitHub remote, no network, no answer in 8 s, an answer that is not a list of issues) is null, never 0,
# and the reason is the collector's own words: nothing gh prints reaches the snapshot. gh writes to a file, so a
# process it leaves behind cannot hold the collector on a pipe.
# shortcut: the first 1000 open issues of a label are listed, page the list when a project can hold more.
github_p1() { labelled_issues P1 github-p1; }
# Issue 292: the open issues labelled proposed-decision, read the same way.
github_proposed() { labelled_issues proposed-decision github-proposed; }
# labelled_issues <label> <source name> -- the open issues with the exact label as {count, top (the five lowest
# numbers), all}, each {number, title, url}; null with the source's reason when they cannot be read.
labelled_issues() {
  local n rc why repo
  repo=$(origin_repo)
  env -u GH_REPO -u GH_HOST ${repo:+GH_REPO=$repo} GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 timeout -k 2 8 \
    gh issue list --state open --label "$1" --limit 1000 --json number,title,url,labels > "$RUN/gh-$2" 2>/dev/null </dev/null; rc=$?
  if [ "$rc" -eq 0 ] && n=$(jq -ce --arg l "$1" 'if type == "array" and all(.[]; type == "object" and (.labels | type) == "array" and all(.labels[]; type == "object"))
      then map(select(any(.labels[]; .name == $l)) | {number, title, url}) | sort_by(.number) | {count: length, top: .[:5], all: .} else error("not a list of issues") end' "$RUN/gh-$2" 2>/dev/null); then
    ok "$2"; echo "$n"
  else
    case $rc in 0) why="gh's answer was not a list of issues" ;; 124|137) why="gh gave no answer in 8 s" ;; *) why="gh issue list failed (exit $rc)" ;; esac
    nm "$2" "$why"; echo null
  fi
}

# gh_read <gh args>... -- one read-only gh call for the GitHub panes, made as github_p1 makes it; nothing gh prints
# reaches the snapshot. A failure names itself on stderr in the collector's own words, which cached() keeps as the reason.
gh_read() {
  local rc
  env -u GH_REPO -u GH_HOST GH_REPO="$PANE_REPO" GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 timeout -k 2 8 gh "$@" 2>/dev/null </dev/null && return 0
  rc=$?
  case $rc in 4) echo "gh is not signed in: run gh auth login" ;; 124|137) echo "gh gave no answer in 8 s" ;; 127) echo "gh is not installed" ;;
    *) echo "gh $1 $2 failed (exit $rc)" ;; esac >&2
  return $rc
}
# Open pull requests with each check's state in rollup order (pass, fail, run or skip) and the issues each closes.
gh_prs() {
  gh_read pr list --state open --limit 50 --json number,title,url,isDraft,headRefName,reviewDecision,mergeable,mergeStateStatus,statusCheckRollup,additions,deletions,closingIssuesReferences \
    | jq -c 'map({number, title, url, draft: .isDraft, branch: .headRefName, review: (.reviewDecision // ""), mergeable, mergeState: (.mergeStateStatus // ""), additions, deletions,
        closes: [.closingIssuesReferences[]?.number],
        checks: [.statusCheckRollup[]? | {name: (.name // .context // ""), state: (
          if .__typename == "StatusContext" then ({SUCCESS: "pass", FAILURE: "fail", ERROR: "fail"}[.state // ""] // "run")
          elif .status != "COMPLETED" then "run" else ({SUCCESS: "pass", NEUTRAL: "skip", SKIPPED: "skip", STALE: "skip"}[.conclusion // ""] // "fail") end)}]})'
}
# Open issues with their milestone and priority (the lowest P0 to P3 label).
# shortcut: the first 1000 open issues are read (the host's limit); page the list when a project can hold more.
gh_issues() {
  gh_read issue list --state open --limit 1000 --json number,title,url,labels,milestone,createdAt \
    | jq -c 'map({number, title, url, createdAt, milestone: (.milestone.title // null), priority: ([.labels[].name | select(test("^P[0-3]$"))] | sort | .[0] // null)})'
}
gh_milestones() {
  gh_read api 'repos/{owner}/{repo}/milestones?state=open&per_page=100' | jq -c 'map({title, due: .due_on, open: .open_issues, closed: .closed_issues})'
}
# Issue 273: the issues created (or closed) in the last 7 days, 1000 at most.
gh_flow() { gh_read issue list --state "$1" --search "$2:>=$(date -u -d "@$((NOW - 7 * 86400))" +%F)" --json number,createdAt,closedAt --limit 1000; }
# The newest CI run on the branch main pushes to.
gh_runs() { gh_read run list --branch "$1" --limit 1 --json conclusion,status,createdAt,workflowName | jq -c 'map({conclusion, status, createdAt, workflow: .workflowName})'; }

# The GitHub panes' data. repo is the GitHub address of the checkout's origin (github() below reads the same
# remote), so the page can link an issue number, and every gh read is made in it (PANE_REPO). Each gh read goes
# through cached(): re-read every TTL, backed off after a failure, and a failed read keeps its last good copy
# marked stale. A read never had is null with its reason (no GitHub origin, gh missing or not signed in, no
# answer), and only its pane says so.
github_panes() {
  local repo up k prs='' issues='' miles='' runs='' opened='' closed=''
  repo=$(origin_repo); PANE_REPO=$repo
  if [ -z "$repo" ]; then
    for k in github-prs github-issues github-milestones github-runs github-opened github-closed; do nm "$k" "no GitHub origin"; done
  else
    prs=$(cached github-prs gh_prs)
    issues=$(cached github-issues gh_issues)
    miles=$(cached github-milestones gh_milestones)
    opened=$(cached github-opened gh_flow all created)
    closed=$(cached github-closed gh_flow closed closed)
    if up=$(git -C "$PP_MAIN" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null); then runs=$(cached github-runs gh_runs "${up#*/}")
    else nm github-runs "main has no upstream branch"; fi
  fi
  jq -cn --arg repo "$repo" --argjson prs "${prs:-null}" --argjson issues "${issues:-null}" \
    --argjson milestones "${miles:-null}" --argjson runs "${runs:-null}" --slurpfile o <(printf '%s' "${opened:-null}") \
    --slurpfile c <(printf '%s' "${closed:-null}") --argjson now "$NOW" \
    'def at($k): [.[][$k] | strings | fromdateiso8601];
     def day: strflocaltime("%Y-%m-%d");
     {repo: (if $repo == "" then null else "https://github.com/" + $repo end), prs: $prs, issues: $issues,
      # Open issues by their lowest priority label; "none" for an issue with no P0 to P3 label.
      byPriority: ($issues | if . == null then null else group_by(.priority // "none") | map({key: (.[0].priority // "none"), value: length}) | from_entries end), milestones: $milestones, runs: $runs,
      # Opened and closed in the last 24 h, and per local day over 7 days, oldest first; at the 1000 limit a count is a floor.
      flow: (if $o[0] == null or $c[0] == null then null else ($o[0] | at("createdAt")) as $op | ($c[0] | at("closedAt")) as $cl
        | {opened24h: [$op[] | select(. >= $now - 86400)] | length, closed24h: [$cl[] | select(. >= $now - 86400)] | length,
           # Calendar days back from today, not 86400 s steps: a DST change makes one local day 23 or 25 hours.
           daily: [($now | localtime) as $t | range(6; -1; -1) as $i | ($t | .[2] -= $i | .[3] = 12 | mktime | strftime("%Y-%m-%d")) as $d | {day: $d, opened: [$op[] | select(day == $d)] | length, closed: [$cl[] | select(day == $d)] | length}],
           incomplete: (($o[0] | length) >= 1000 or ($c[0] | length) >= 1000)} end)}'
}

# What a push of main would send: the commits its upstream lacks, newest first (100 at most), each with the issue
# numbers its message names and its line counts, and how far each side is ahead.
next_push() {
  local up counts log
  if ! up=$(git -C "$PP_MAIN" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null); then nm git-push "main has no upstream branch"; echo null; return 0; fi
  if ! counts=$(git -C "$PP_MAIN" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null) \
     || ! log=$(git -C "$PP_MAIN" log --max-count=100 --format='%x1e%h%x1f%ct%x1f%s%x1f%B%x1f' --shortstat '@{upstream}..HEAD' 2>/dev/null); then
    nm git-push "git log in $PP_MAIN failed"; echo null; return 0
  fi
  ok git-push
  jq -Rsc --arg up "$up" --arg counts "$counts" '($counts | split("\t") | map(tonumber)) as $n
    | {upstream: $up, behind: $n[0], ahead: $n[1], commits: (split("\u001e")[1:] | map(split("\u001f")
      | {sha: .[0], at: (.[1] | tonumber), subject: .[2], refs: (reduce (.[3] | scan("#([0-9]+)") | .[0] | tonumber) as $n ([]; if index([$n]) then . else . + [$n] end)),
         added: ((.[4] | capture("(?<n>[0-9]+) insertion") | .n | tonumber) // 0), deleted: ((.[4] | capture("(?<n>[0-9]+) deletion") | .n | tonumber) // 0)}))}' <<<"$log"
}

# The main checkout's own branch: its newest commits and how many its upstream lacks.
main_chain() {
  local commits=null unpushed
  if commits=$(git -C "$PP_MAIN" log -5 --format='%h%x09%s' 2>/dev/null); then
    ok git-main
    commits=$(jq -Rcn '[inputs | split("\t") | {sha: .[0], subject: (.[1:] | join("\t"))}]' <<<"$commits")
  else commits=null; nm git-main "git log in $PP_MAIN failed"; fi
  unpushed=$(git -C "$PP_MAIN" rev-list --count '@{upstream}..HEAD' 2>/dev/null) || unpushed=null
  # Issue 292: the newest finished build (finished_builds is newest first), or null with none.
  jq -cn --argjson c "$commits" --argjson u "$unpushed" --slurpfile f <(finished_builds) '{commits: $c, unpushed: $u, lastMerge: (($f[0] // [])[0] | if . then {unit, at} else null end)}'
}

since7() { iso $((NOW - 7 * 86400)); }

# Issues 271 and 272: the merge's unit ledger (unit-ledger.sh). A merged row per unit, and escape rows of their own
# (no mergedAt, so the 7-day window leaves them out of reviewLoop).
review_loop() {
  [ -s "$METRICS/unit-ledger.jsonl" ] || { nm unit-ledger "no unit ledger: no unit was merged since it was added"; echo null; return 0; }
  ok unit-ledger
  jq -Rnc --arg s "$(since7)" '[inputs | fromjson? // empty | select((.mergedAt // "") >= $s)
    | {unit, mergedAt, rounds, goRounds, noGoRounds, fixRounds, passKinds, reviewSeconds, verdict, findings, expensivePasses, gaps}] | sort_by(-(.rounds // -1))' \
    "$METRICS/unit-ledger.jsonl"
}
escapes() {
  [ -s "$METRICS/unit-ledger.jsonl" ] || { echo null; return 0; }
  # One entry per unit and issue, with the class and where it was caught (issue 272); an older row has neither: null.
  jq -Rnc '[inputs | fromjson? // empty | select(.escaped | type == "array") | . as $r | .escaped[]
      | {unit: $r.unit, issue: ., class: ($r.class // null), caught: ($r.caught // null)}] | unique_by([.unit, .issue])' "$METRICS/unit-ledger.jsonl"
}

cost_role() {
  [ -s "$METRICS/seat-events.jsonl" ] || { nm seat-events "no seat-events ledger"; echo null; return 0; }
  ok seat-events
  # Totals cover measured seats only; unmeasuredSeats is the gap they omit.
  jq -cs --arg s "$(since7)" '[.[] | select((.completedAt // "") >= $s)] | group_by(.role) | map(
    (map(.tokens | select(. != null))) as $m
    | def sum($k): if $m == [] or ($m | any(.[$k] == null)) then null else $m | map(.[$k]) | add end;
    {role: .[0].role, seats: length, unmeasuredSeats: (length - ($m | length)),
     input: sum("input"), cachedInput: sum("cachedInput"), output: sum("output")})' \
    "$METRICS/seat-events.jsonl"
}

# ledger <source-id> <file> <jq over the slurped rows, $s = seven days ago> --
# one measured ledger; a missing one is not measured (null), never [].
ledger() {
  [ -s "$METRICS/$2" ] || { nm "$1" "no ledger at $METRICS/$2"; echo null; return 0; }
  ok "$1"
  jq -cs --arg s "$(since7)" "$3" "$METRICS/$2"
}

# What the cards above cannot show, seven days of each: why seats stopped and
# subagent runs by type.
measures() {
  bash "$HERE/subagent-usage.sh" || echo "dashboard: subagent-usage.sh failed; its ledger may be behind" >&2
  local seats sa
  seats=$(ledger seat-events seat-events.jsonl \
    '[.[] | select((.completedAt // "") >= $s) | {unit, role, round, completedAt, tokens, stopReason}]')
  # A run that went on after it was recorded has a later row with the whole total: the last one counts.
  sa=$(ledger subagent-usage subagent-usage.jsonl 'group_by(.agentId) | map(last) | [.[] | select((.finishedAt // "") >= $s)] | group_by(.agentType) | map(
    (map(.tokens | select(. != null))) as $m
    | {agentType: .[0].agentType, runs: length, unmeasuredRuns: (length - ($m | length)),
       input: ($m | map(.input) | add), cachedInput: ($m | map(.cachedInput) | add), output: ($m | map(.output) | add)})')
  jq -cn --argjson seats "$seats" --argjson sa "$sa" '{seats: $seats, subagents: $sa}'
}

# The newest 20 block rows of the hook fire log, every retained day file
# (the log keeps 8 days), with the block count per agent. Only the fields
# the log stores reach the page (it never stores command text). A missing log is
# zero blocks, marked not measured. retry reads the session's next call as
# hook-fire-log-summary.sh does: its first row with another tool_use_id, the same
# fingerprint being the identical call retried; keep the two in step.
guard_blocks() {
  # The override is one exact file; the default glob lists the day files in day order.
  local -a files=("${COMMANDECK_HOOK_FIRE_LOG:-}")
  [ -n "${files[0]}" ] || files=("$HOME"/.claude/hook-fire-log/"$PP_PROJECT".????-??-??.jsonl)
  if [ ! -e "${files[0]}" ]; then nm hook-fire-log "no hook fire log at ${files[0]}"; echo '{"blocks":0,"items":[],"byAgent":{"claude":0,"codex":0}}'; return 0; fi
  local rc=0
  python3 - "$CACHE/guard-blocks.json" "${files[@]}" <<'PY' || rc=$?
import json, os, re, sys, time
from datetime import datetime, timezone
state_path, files = sys.argv[1], sys.argv[2:]
# Each cycle reads only the bytes appended since the last (issue 299). The state is every file read with the offset
# it stopped at, plus what a cold read holds after them: calls per session (a block's retry can land in the next
# day's file), the block rows and the sessions that blocked. It is used only when the day files are the stored ones,
# in order, with the last one alone still growing; anything else (retention, truncation, an earlier file written to,
# a state that does not parse or is another version) is read cold, which gives the same answer. Only block rows are
# kept, and only the fields the page shows.
VERSION, KEEP = 1, ("timestamp", "hook", "event", "tool", "agent", "worktree", "summary")
sessions, blocks, blocked, unread, offsets = {}, [], set(), False, {}
try:
    with open(state_path) as f:
        st = json.load(f)
    if st["version"] != VERSION or not all(isinstance(o, int) and isinstance(p, str) for p, o in st["files"]):
        raise ValueError("another version")
    stored = [(p, o) for p, o in st["files"]]
    ok = [p for p, _ in stored] == files[:len(stored)]
    for i, (p, o) in enumerate(stored):
        size = os.stat(p).st_size if ok else 0
        ok = ok and size >= o and (i == len(stored) - 1 or size == o)
    if ok:
        held = ({k or None: [tuple(c) for c in v] for k, v in st["sessions"].items()},
                [(r, k or None, a) for r, k, a in st["blocks"]], set(st["blocked"]))
        offsets = dict(stored)
        sessions, blocks, blocked = held
except (OSError, ValueError, KeyError, TypeError, AttributeError):
    pass
done = []
for path in files:
    try:
        f = open(path, "rb")
    except FileNotFoundError:
        continue  # deleted by retention between the listing and the read
    except OSError:
        unread = True  # the count would be short; exit 3 marks it not measured
        continue
    off = offsets.get(path, 0)
    with f:
      f.seek(off)
      for raw in f:
        if not raw.endswith(b"\n"):
            break  # a half-written last line waits for the next cycle
        off += len(raw)
        line = raw.decode("utf-8", errors="replace")
        # Eight days is millions of rows, read every 60 s: only block rows and
        # the later rows of a session that blocked are parsed. The writer's
        # compact JSON makes both substring tests exact.
        if '"decision":"block"' not in line:
            i = line.find('"session_id":"') + 14
            if i < 14 or line[i:line.find('"', i)] not in blocked:
                continue
        try:
            row = json.loads(line)
            at, hook = row["timestamp"], row["hook"]
        except (ValueError, KeyError, TypeError):
            continue  # a row cut short by a full disk or a crash
        if not isinstance(row, dict) or not isinstance(hook, str) or not isinstance(at, str):
            continue
        sid = row.get("session_id") or None
        calls = sessions.setdefault(sid, [])
        if row.get("use"):
            calls.append((row["use"], row.get("call")))
        # A block with no session id is a hook self-test run by hand, not an agent's: Claude and
        # Codex both name the session in every hook payload, a self-test's payload does not.
        if row.get("decision") == "block" and not sid:
            continue
        if row.get("decision") == "block" and sid:
            blocked.add(sid)
        if row.get("decision") == "block":
            blocks.append(({k: row.get(k) for k in KEEP}, sid, len(calls) - 1 if row.get("use") and sid else None))
    done.append([path, off])
try:
    # The held rows are global, not per file: a state missing an unread file would keep its blocks and reread them.
    if unread:
        raise OSError("partial cycle: keep the last whole state")
    tmp = f"{state_path}.{os.getpid()}"
    with open(tmp, "w") as f:
        json.dump({"version": VERSION, "files": done, "sessions": {k or "": v for k, v in sessions.items()},
                   "blocks": [[r, k or "", a] for r, k, a in blocks], "blocked": sorted(blocked)}, f)
    os.replace(tmp, state_path)
except OSError:
    pass  # no state: the next cycle reads cold
blocks = [(r, sessions[k], a) for r, k, a in blocks]

def retry(calls, at):
    if at is None:
        return None
    use, call = calls[at]
    later = calls[at + 1:]
    nxt_use = next((u for u, _ in later if u != use), None)
    nxt = next((k for u, k in later if u == nxt_use and k), None)
    if not call or nxt is None:
        return None
    return "identical" if nxt == call else "worked-around"

fields = ("event", "tool", "agent", "worktree", "summary")
newest = sorted(enumerate(blocks), key=lambda b: (b[1][0]["timestamp"], b[0]), reverse=True)[:20]
by_agent = {a: sum(r.get("agent") == a for r, _, _ in blocks) for a in ("claude", "codex")}
def stamp(s):
    try:
        return datetime.strptime(s[:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc).timestamp()
    except ValueError:
        return None
now = time.time()
stamps = [t for t in (stamp(r["timestamp"]) for r, _, _ in blocks) if t is not None]
# The spike alert compares the last hour with the retained days' hourly mean: the
# span is the oldest retained day file's start (block-free hours count), else the first block.
starts = []
for p in files:
    m = re.search(r"\.(\d{4}-\d{2}-\d{2})\.jsonl$", p)
    if m:
        starts.append(datetime.strptime(m.group(1), "%Y-%m-%d").replace(tzinfo=timezone.utc).timestamp())
origin = min(starts) if starts else (min(stamps) if stamps else now)
hours = max(1.0, min(192.0, (now - origin) / 3600))
print(json.dumps({"blocks": len(blocks), "byAgent": by_agent, "lastHour": sum(t >= now - 3600 for t in stamps),
                  "perHour": round(len(stamps) / hours, 1), "items": [
    dict({"at": r["timestamp"], "hook": r["hook"]}, **{k: r.get(k) for k in fields}, retry=retry(c, a))
    for _, (r, c, a) in newest]}))
sys.exit(3 if unread else 0)
PY
  case $rc in
    0) ok hook-fire-log ;;
    3) nm hook-fire-log "could not read every hook fire log file (${#files[@]})" ;;
    *) return "$rc" ;;
  esac
}

# Main's TaskCreate/TaskUpdate checklist, one <id>.json per item. Every session
# on the host, worker panes included, has a task directory, so only one whose
# transcript sits under the main checkout's project directory counts (Claude
# Code names it after the path, every non-alphanumeric a '-'); the newest wins.
todos() {
  local proj=$CLAUDE_DIR/projects/${PP_MAIN//[^a-zA-Z0-9]/-} d dir='' out files
  while IFS= read -r d; do
    [ -e "$proj/$(basename "$d").jsonl" ] && { dir=$d; break; }
  done < <(ls -td "$CLAUDE_DIR"/tasks/*/ 2>/dev/null)
  [ -n "$dir" ] || { nm todos "no main session task list under $CLAUDE_DIR/tasks"; echo null; return 0; }
  # Every item deleted leaves no file: a measured empty list, not a failed read.
  files=("$dir"*.json); [ -e "${files[0]}" ] || files=()
  if out=$(jq -cs --arg s "$(basename "$dir")" \
      '{sessionId: $s, items: (sort_by(.id | tonumber) | map({id, subject, status, activeForm}))}' "${files[@]}" < /dev/null 2>/dev/null); then
    ok todos; echo "$out"
  else nm todos "a task file in $dir did not parse"; echo null; fi
}

# Main's in-harness background subagents. Each session's <scratch>/<session>/tasks/
# holds one <agentId>.output symlink per agent, to its transcript; the meta file
# beside the transcript records description and model when the launch named them.
# Same main-session rule as todos(). Running: the last assistant turn still has
# a tool call pending, or a tool result came after it. Only the ten newest
# links (a link's own mtime is its launch) are read.
bg_agents() {
  local proj=$CLAUDE_DIR/projects/$PP_MAIN_SLUG d dir='' s f t m ts
  while IFS= read -r d; do
    s=${d%/tasks/}; s=${s##*/}
    [ -e "$proj/$s.jsonl" ] && { dir=$d; break; }
  done < <(ls -td "$PP_SCRATCH"/*/tasks/ 2>/dev/null)
  [ -n "$dir" ] || { nm agents "no main session tasks directory under $PP_SCRATCH"; echo null; return 0; }
  : > "$RUN/agents.jsonl"
  while IFS= read -r f; do
    # A link whose transcript is gone has nothing to show.
    t=$(readlink -e "$dir$f") && ts=$(stat -c %Y "$t" 2>/dev/null) || continue
    m=${t%.jsonl}.meta.json; [ -s "$m" ] || m=/dev/null
    # A transcript still being written can end in a partial line: fromjson? skips it.
    jq -Rcn --arg id "${f%.output}" --argjson age "$(( NOW - ts ))" --slurpfile meta "$m" '
      reduce (inputs | fromjson? | objects) as $l ({start: null, prompt: null, model: null, running: true};
        if .start == null and $l.type == "user" then .start = $l.timestamp
          | .prompt = ($l.message.content | if type == "string" then . else ([.[]? | select(.type == "text") | .text] | join(" ")) end)
        elif $l.type == "assistant" then .model = ($l.message.model // .model) | .running = any($l.message.content[]?; .type == "tool_use")
        elif $l.type == "user" then .running = true
        else . end)
      | {id: $id, description: ($meta[0].description // ((.prompt // "")[0:80] | if . == "" then null else . end)),
         model: ($meta[0].model // .model), running, startedAt: .start, ageSec: ([$age, 0] | max)}' "$t" >> "$RUN/agents.jsonl" \
      || { nm agents "could not read $t"; echo null; return 0; }
  # Background Bash outputs sit beside the links as plain files: only links are agents.
  done < <(ls -t "$dir" 2>/dev/null | grep -E '\.output$' | while IFS= read -r f; do [ ! -L "$dir$f" ] || echo "$f"; done | head -10)
  ok agents
  jq -cs --arg s "$(basename "${dir%/tasks/}")" '{sessionId: $s, items: (sort_by(.startedAt // "") | reverse)}' "$RUN/agents.jsonl"
}

# pgrep exits 1 on no match (a measured 0) and >1 when it could not look (null).
procs() {
  local out rc
  out=$(pgrep -x "$1"); rc=$?
  case $rc in 0) grep -c . <<<"$out" ;; 1) echo 0 ;; *) echo null ;; esac
}

host() {
  local cpus hl
  cpus=$(getconf _NPROCESSORS_ONLN 2>/dev/null) || cpus=
  hl=$(hs_load)
  if jq -e '.load != null' <<<"$hl" >/dev/null; then ok host; else nm host "no load reading"; fi
  jq -cn --arg cpus "$cpus" --argjson hl "$hl" --arg cl "$(procs claude)" --arg cx "$(procs codex)" '
    def n: if . == "" or . == "null" then null else (try tonumber catch null) end;
    {cpus: ($cpus | n), load: $hl.load, swap: $hl.swap, claudeProcs: ($cl | n), codexProcs: ($cx | n)}'
}

# The 7-day limit panel. The usage read is Claude's own quota reading, the
# statusline's source, never a model call; dashboard_limit.py owns the math.
limit() {
  local st
  # The login is the one main last started under, read once this render with the transcripts (claude_dir); a
  # reading cached for another account is dropped first (issue 226).
  python3 "$HERE/dashboard_limit.py" account "$CACHE" > /dev/null
  cached claude-usage python3 "$HERE/dashboard_limit.py" fetch > /dev/null
  st=$(jq -r '.[].status' "$RUN/src/claude-usage.json")
  if [ -d "$CLAUDE_DIR/projects" ]; then ok claude-logs; else nm claude-logs "no Claude Code transcripts"; fi
  # Codex's own 7-day reading comes from its session files (the folder builder-codex-pass.sh uses).
  local cx=${CODEX_HOME:-$HOME/.codex}/sessions
  if [ -d "$cx" ]; then ok codex-usage; else nm codex-usage "no Codex sessions at $cx"; fi
  # The day's cost is each project's own: its sessions are the ones run in its main checkout or its worktrees.
  python3 "$HERE/dashboard_limit.py" build "$st" "$CACHE/claude-usage" "$NOW" "$CACHE" "$CLAUDE_DIR/projects" "$cx" \
    "$(jq -c '.projects | map_values([.path, .workspaces, .closingCopies])' "$RUN/parts/projects.json")"
}

# The Tests card (issue 269): the test runs going now on this machine (ps, lsof) and the finished ones from the Claude
# session logs (dashboard_limit.py tests), both limited to this project's main checkout and worktrees.
# A runner is a process whose first word is a shell or node and whose command names a test runner, so a `zsh -c`
# wrapper that merely mentions one is not, nor a shell's -n or -c or node's -e, -p or --check (dashboard_limit.py's
# test_segment holds the same rule for the session logs); of a parent and its child runner only the outermost is a row.
# Ceiling: this machine only; a run's usual time matches by the logged command containing the running one.
TEST_RE='run-shell-tests\.sh|npm (run )?test|\bnode\b.*--test\b|\.test\.sh'
# The jq `who` of a working folder: the worktree unit, main, or null for a folder outside this project.
TEST_WHO='def who: if .cwd == null then null
      elif .cwd | startswith($ws + "/") then (.cwd | ltrimstr($ws + "/") | split("/")[0])
      elif .cwd == $main or (.cwd | startswith($main + "/")) then "main"
      else null end;'
# tests_rows <ps text> <cwd text, lsof -Fn shape; empty to list every runner> <builder unit names, JSON array>
tests_rows() {
  jq -cn --arg ps "$1" --arg cwd "$2" --arg re "$TEST_RE" --arg ws "$PP_WORKSPACES" --arg main "$PP_MAIN" --argjson builders "$3" '
    def secs: (split("-") | if length == 2 then [(.[0] | tonumber), .[1]] else [0, .[0]] end) as $d
      | ($d[1] | split(":") | map(tonumber)) as $t
      | $d[0] * 86400 + ($t | if length == 3 then .[0] * 3600 + .[1] * 60 + .[2] else .[0] * 60 + .[1] end);
    '"$TEST_WHO"'
    ($cwd | split("\n") | reduce .[] as $l ({}; if $l[0:1] == "p" then .cur = $l[1:] elif $l[0:1] == "n" and .cur then .[.cur] = $l[1:] else . end) | del(.cur)) as $at
    | [$ps | split("\n")[] | capture("^\\s*(?<pid>[0-9]+)\\s+(?<ppid>[0-9]+)\\s+(?<et>[0-9:-]+)\\s+(?<command>.+)$")?] as $lines
    | ($lines | map({key: .pid, value: .ppid}) | from_entries) as $par
    | [$lines[] | select((.command | test("^(\\S*/)?(bash|sh|node|npm|npx)\\s")) and (.command | test($re))
        and (.command | test("^(\\S*/)?(bash|sh)\\s+-[a-zA-Z]*[nc]|^(\\S*/)?(node|npx)\\s(.*\\s)?(-e|-p|--eval|--print|-c|--check)(\\s|=|$)") | not))] as $all
    | ($all | map({key: .pid, value: true}) | from_entries) as $set
    | def up($p): ($par[$p]) as $q | if $q == null or $q == "0" then false elif $set[$q] then true else up($q) end;
    $all | map(select(up(.pid) | not)
        | {pid: (.pid | tonumber), command: .command[0:120], full: .command, elapsedSec: (.et | secs), cwd: ($at[.pid] // null)}
        | . + {who: who} | select($cwd == "" or .who != null) | del(.cwd) | . + {builder: (.who | IN($builders[]))})' 2>/dev/null
}
tests_panel() {
  local plist='' cwd='' pids running=null fin=null builders d bpaths=()
  builders=$(for d in "$PP_WORKSPACES"/*/; do d=${d%/}
    [ "$(jq -r '.env.COMMANDECK_BUILDER // empty' "$d/.claude/settings.local.json" 2>/dev/null)" = 1 ] && basename "$d"; done | jq -Rcn '[inputs]')
  while IFS= read -r d; do bpaths+=("$PP_WORKSPACES/$d"); done < <(jq -r '.[]' <<<"$builders")
  if plist=$(ps -axww -o pid=,ppid=,etime=,command= 2>/dev/null); then
    pids=$(tests_rows "$plist" "" "$builders" | jq -r 'map(.pid) | join(",")')
    # lsof exits 1 when a listed process ended meanwhile, with the rest still printed: only no output at all is a failure.
    [ -z "$pids" ] || cwd=$(lsof -a -d cwd -Fn -p "$pids" 2>/dev/null) || true
    if [ -n "$pids" ] && [ -z "$cwd" ]; then nm tests-ps "the folders of the runs could not be read (lsof)"
    elif running=$(tests_rows "$plist" "$cwd" "$builders") && [ -n "$running" ]; then ok tests-ps
    else running=null; nm tests-ps "the process list could not be read"; fi
  else nm tests-ps "ps failed"; fi
  if [ -d "$CLAUDE_DIR/projects" ] && fin=$(python3 "$HERE/dashboard_limit.py" tests "$CLAUDE_DIR/projects" "$REQS/test-runs.json" "$NOW" "$PP_MAIN" "$PP_WORKSPACES" --builders ${bpaths[@]+"${bpaths[@]}"} 2>"$RUN/err-tests") && [ "$fin" != null ]; then ok tests-logs
  else fin=null; nm tests-logs "$(head -1 "$RUN/err-tests" 2>/dev/null)"; fi
  jq -cn --argjson run "$running" --argjson fin "${fin:-null}" --arg ws "$PP_WORKSPACES" --arg main "$PP_MAIN" '
    '"$TEST_WHO"'
    def usual($u): . as $r | [$u[]? | select(.cmd | contains($r.full))] | max_by(.n) | .sec;
    # A run with no result past its time cap is stalled: 3 times its usual time when known, else run-shell-tests.sh'"'"'s
    # 120 s a named file; any other run has no cap.
    def cap: if .usualSec != null then .usualSec * 3
      elif (.full | test("run-shell-tests\\.sh")) and ([.full | split(" ")[] | select(test("\\.test\\.[a-z]+$"))] | length) > 0
      then ([.full | split(" ")[] | select(test("\\.test\\.[a-z]+$"))] | length) * 120 else null end;
    ($fin.usual // []) as $u
    | {testSecToday: ($fin.testSecToday // null), builderShare: ($fin.builderShare // null),
       running: (if $run == null then null else $run | map(. + {usualSec: usual($u)} | . + {capSec: cap} | . + {stalled: (.capSec != null and .elapsedSec > .capSec)} | del(.full)) end),
       finished: ($fin.finished | if . == null then null else map(. + {who: who} | del(.cwd)) end)}'
}

# The Chief of Staff is the relay pane: its inbox's unread count and the oldest
# unread message's age. `orchestration inbox` only lists; `check` is the verb
# that marks messages read, so a collect never acks its mail.
chief_of_staff() {
  local ts h out pk
  if ! ts=$(terminal_list); then
    nm chief-of-staff "orca-ide terminal list failed"; echo null; return 0
  fi
  h=$(jq -r --arg p "$PP_WORKSPACES/Chief-of-Staff" '.result | if type == "array" then . else (.terminals // []) end
    | map(select((.worktreePath // "") == $p)) | .[0].handle // empty' <<<"$ts")
  [ -n "$h" ] || { nm chief-of-staff "no Chief-of-Staff terminal"; echo null; return 0; }
  if out=$(timeout 8 orca-ide orchestration inbox --terminal "$h" --limit 1000 --json 2>/dev/null \
      | jq -ce --argjson now "$NOW" '.result.messages | arrays | (length >= 1000) as $cap | map(select(.read == 0))
        | {unread: length, oldestUnreadAgeSec: (if length == 0 then null else $now - (map(.created_at | fromdateiso8601) | min) end),
           incomplete: $cap}' 2>/dev/null); then
    # The relay's open picker, as main-watch.sh records it (issue 232); none is null.
    pk=$(jq -ce 'objects' "$PP_SCRATCH/main-watch/relay-picker.json" 2>/dev/null) || pk=null
    ok chief-of-staff; jq -c --argjson pk "$pk" '. + {picker: $pk}' <<<"$out"
  else nm chief-of-staff "orca-ide orchestration inbox failed"; echo null; fi
}

# Main's and the relay's own cards (issue 224): main's sessions are the main checkout's projects folder, the
# relay's the Chief-of-Staff worktree's; with no relay configured there is no relay key. Each carries its live
# context beside its clear line; the relay pane has no clear line (context-line.sh exempts it).
seats() {
  local relay='' out wk
  [ -z "$(jq -r '.chiefOfStaff.name // empty' "$PP_PROJECT_DIR/.claude/commandeck.json" 2>/dev/null)" ] || relay=$PP_WORKSPACES/Chief-of-Staff
  if out=$(python3 "$HERE/dashboard_limit.py" seats "$NOW" "$REQS" "$CLAUDE_DIR/projects" "$HOME/.claude/checkpoints/clear-hook.log" \
      "$PP_MAIN" ${relay:+"$relay"} 2>"$RUN/err-seats") && jq -e 'objects' >/dev/null 2>&1 <<<"$out"; then ok seats
  else nm seats "main's and the relay's figures could not be read: $(head -1 "$RUN/err-seats" 2>/dev/null)"; echo null; return 0; fi
  # Issue 331: the wake log's last hour, with the failed ones by result.
  wk=$(jq -sc --argjson now "$NOW" '[.[] | objects | select((.at // "" | try fromdateiso8601 catch 0) > $now - 3600)]
    | {hour: length, failed: ([.[] | select(.result | IN("no_turn", "refused", "no_pane", "unreadable", "blocked", "gave_up"))]
      | group_by(.result) | map({(.[0].result): length}) | add // {})}' < <(cat "$PP_SCRATCH/wake-log.jsonl" 2>/dev/null) 2>/dev/null) || wk=null
  jq -c --arg mc "$(context_size "$(pp_session_log "$PP_MAIN")")" --arg ml "$(pp_clear_line)" --argjson wk "${wk:-null}" \
    --arg rc "$([ -z "$relay" ] || context_size "$(pp_session_log "$relay")")" '
    (.main | objects) |= . + {context: ($mc | tonumber? // null), line: ($ml | tonumber? // null), wakes: $wk}
    | (.relay | objects) |= . + {context: ($rc | tonumber? // null), line: null}' <<<"$out"
}

# Main's compactions and unhealed carry failures over 24 h, and its last restart (issues 292, 300): the reader is
# dashboard_limit.py main-events. A main with no session folder yet has no events.
main_events() {
  local out
  if out=$(python3 "$HERE/dashboard_limit.py" main-events "$NOW" "$CLAUDE_DIR/projects/$PP_MAIN_SLUG" "$HOME/.claude/checkpoints/clear-hook.log" 2>"$RUN/err-main-events") \
      && jq -e 'objects' >/dev/null 2>&1 <<<"$out"; then ok mainEvents; echo "$out"
  else nm mainEvents "main's compactions and carry failures could not be read: $(head -1 "$RUN/err-main-events" 2>/dev/null)"; echo null; fi
}

# The host-wide MCP-down stamps (pane-budget-gate.sh, host issue 3147) as one part, {mcpDown: [{server, at}]}; a stamp
# whose content is not an epoch is left out.
mcp_stamps() {
  local d=${COMMANDECK_MCP_HEALTH_DIR:-$HOME/.commandeck/mcp-health} f
  for f in "$d"/mcp-down-*; do
    [ -f "$f" ] && jq -nc --arg s "${f##*/mcp-down-}" --rawfile at "$f" '{server: $s, at: ($at | rtrimstr("\n") | tonumber?)}'
  done | jq -sc '{mcpDown: .}'
}

# The active alerts from the parts already built this collect; the rules are
# dashboard_alerts.jq. Each alert's start persists in the cache, so its id
# holds across collects. An input not measured makes the record not measured,
# naming it: a missing input is never "no alerts".
alerts() {
  local f=$CACHE/alerts-since.json prev out p
  local -a se=()
  while IFS= read -r p; do [ ! -s "$p/.claude/metrics/seat-events.jsonl" ] || se+=("$p/.claude/metrics/seat-events.jsonl"); done \
    < <(jq -r '.projects[].path' "$RUN/parts/projects.json")
  prev=$(jq -c 'objects' "$f" 2>/dev/null) && [ -n "$prev" ] || prev='{}'
  out=$(jq -nc -f "$HERE/dashboard_alerts.jq" --argjson now "$NOW" --arg s7 "$(since7)" --argjson hasSe "$([ ${#se[@]} -gt 0 ] && echo true || echo false)" \
    --slurpfile se <([ ${#se[@]} -eq 0 ] || jq -c --arg s "$(since7)" 'select((.completedAt // "") >= $s) | {role, completedAt, tokens}' "${se[@]}") \
    --slurpfile parts <(cat "$RUN"/parts/*.json; mcp_stamps) --slurpfile srcs <(cat "$RUN"/src/*.json) --slurpfile preva <(printf '%s' "$prev")) || return 1
  jq -c .since <<<"$out" > "$f"
  # Issue 274: each alert that cleared is kept 24 h for the page's folded list.
  jq -c --argjson now "$NOW" --slurpfile r <(jq -c 'arrays' "$CACHE/alerts-resolved.json" 2>/dev/null) \
    '[($r[0] // [])[] | select((.resolvedAt | fromdateiso8601) > $now - 86400)] + .resolved' <<<"$out" > "$CACHE/alerts-resolved.json.$$" \
    && mv -f "$CACHE/alerts-resolved.json.$$" "$CACHE/alerts-resolved.json"
  if jq -e '.missing == []' <<<"$out" >/dev/null; then ok alerts; else nm alerts "$(jq -r '.missing | join(", ")' <<<"$out")"; fi
  jq -c .alerts <<<"$out"
}

alerts_resolved() { jq -c 'arrays' "$CACHE/alerts-resolved.json" 2>/dev/null || echo '[]'; }

# part <key> <fn> -- one top-level group; a group that is not JSON stops the
# publication, so a collector bug never ships as an empty card.
part() {
  local k=$1 t0=$SECONDS
  "$2" > "$RUN/v-$k" && jq -c --arg k "$k" '{($k): .}' "$RUN/v-$k" > "$RUN/parts/$k.json" 2>/dev/null \
    && [ "$(wc -l < "$RUN/parts/$k.json")" -eq 1 ] || { echo "dashboard: building $k failed" >&2; return 1; }
  # Issue 292: how long each group took, whole seconds, for partSeconds below.
  echo "$k $((SECONDS - t0))" >> "$RUN/part-seconds"
}

# The seconds each group of this collect took, so a slow collect names its slow group.
part_seconds() { jq -Rn '[inputs | split(" ") | {(.[0]): (.[1] | tonumber)}] | add // {}' "$RUN/part-seconds" 2>/dev/null || echo '{}'; }

# project <run dir> -- one project's parts and source records as one object
# in <run dir>/project.json. The run directory is the caller's: it reads the
# file and removes the directory.
project() {
  # The trap goes first: a run folder taken before a failed check here was removed by it.
  trap - EXIT
  RUN=$1 NOW=${DASH_NOW:?} CACHE=$CACHE/$PP_PROJECT
  mkdir -p "$CACHE" "$RUN/src" "$RUN/parts" || return 1
  # A project collected alone (no render around it) is its own collect: its own stamp and terminal list.
  [ -n "${DASH_CYCLE:-}" ] || { export DASH_CYCLE=$NOW.$$ DASH_TERMS=$RUN/terminals.json; rm -f "$DASH_TERMS" "$DASH_TERMS.bad"; }
  # The units, the seats and the limit card read the transcripts once a collect (issue 299), through the top-level
  # request caches, unless this project's sessions sit under another config folder than the collect's.
  REQS=$OUT/cache; [ "$CLAUDE_DIR" = "${DASH_CLAUDE_DIR:-$CLAUDE_DIR}" ] || REQS=$CACHE
  cd "$PP_MAIN" || return 1
  # A session records its folder as the OS gives it. On a Mac a workspace path typed in another letter case finds
  # the same folder on disk but matches none of its sessions: no Builder's cost, no worktree in the day's cost.
  # The external pwd asks the OS; Bash's own keeps the case as typed.
  local ws
  ws=$(cd "$PP_WORKSPACES" 2>/dev/null && env pwd -P) && PP_WORKSPACES=$ws
  # Issue 292: the two slow groups that touch no cache the others use run beside the rest. Each writes only its own
  # files in $RUN (and measures' ledger, under subagent-usage.sh's lock); a failure of either fails the collect below.
  local pm pg rc=0
  part measures measures & pm=$!
  part guardBlocks guard_blocks & pg=$!
  part units units && part needsOwner needs_owner && part githubP1 github_p1 && part githubProposed github_proposed && part github github_panes && part nextPush next_push \
    && part mainChain main_chain && part costPerRole cost_role && part reviewLoop review_loop && part escapes escapes \
    && part todos todos && part agents bg_agents \
    && part chiefOfStaff chief_of_staff && part seats seats && part mainEvents main_events && part tests tests_panel || rc=1
  wait "$pm" || rc=1
  wait "$pg" || rc=1
  [ "$rc" = 0 ] && part partSeconds part_seconds || return 1
  jq -cs '{sources: add}' "$RUN"/src/*.json > "$RUN/parts/sources.json" || return 1
  # closingCopies: where this project's fresh closing review passes run, so the day's cost counts their sessions (unit_folders.py).
  jq -cs --arg n "$PP_PROJECT" --arg p "$PP_MAIN" --arg w "$PP_WORKSPACES" --arg c "$(python3 "$HERE/unit_folders.py" root 2>/dev/null || true)" \
    '{($n): (add + {path: $p, workspaces: $w, closingCopies: $c})}' "$RUN"/parts/*.json > "$RUN/project.json"
}

# registered -- the registry's paths, one a line; with no registry, nothing.
registered() { [ ! -s "$REG" ] || grep -v '^[[:space:]]*$' "$REG"; }

# projects -- every project's object under one key: the home project (the
# checkout this script runs for) always, and each registered checkout that has
# a GitHub origin. A registered path that is no checkout any more, or has no
# such origin, is named in the source record, never dropped in silence; a
# project whose collect fails stops the publication.
github() { git -C "$1" config --get remote.origin.url 2>/dev/null | grep -qE '^(https://([^/@]+@)?|ssh://git@|git@)github\.com[:/]'; }
projects() {
  local p n i=1 gone='' bare='' note='' home=1
  # Off for the home project (a registry that exists and does not list it) means it is not collected; a job installed
  # before any registration has no registry, and keeps collecting it.
  # By name, as the loop below and register() match projects: a path can be spelled two ways.
  [ ! -e "$REG" ] || registered | sed 's|.*/||; s/[^A-Za-z0-9_.-]/-/g' | grep -qxF -- "$PP_PROJECT" || home=
  : > "$RUN/projects.jsonl"
  [ -z "$home" ] || { COMMANDECK_MAIN="$PP_MAIN" DASH_NOW="$NOW" bash "$HERE/$NAME.sh" --project "$RUN/proj-1" >&2 && cat "$RUN/proj-1/project.json" > "$RUN/projects.jsonl" || return 1; }
  while IFS= read -r p; do
    # The home project is collected above; a name is one key, so a second checkout under home's name is home.
    n=${p##*/}; [ -z "$home" ] || [ "${n//[^A-Za-z0-9_.-]/-}" != "$PP_PROJECT" ] || continue
    [ -e "$p/.git" ] || { gone+="${gone:+, }$p"; continue; }
    github "$p" || { bare+="${bare:+, }$p"; continue; }
    i=$((i + 1))
    # The workspace and scratch overrides name one project's folders: a registered project derives its own.
    # Run in that project's own checkout: started from a linked worktree, COMMANDECK_MAIN would not be followed (project-main.sh).
    (cd "$p" && env -u CLAUDE_PROJECT_DIR -u COMMANDECK_WORKSPACES -u COMMANDECK_SCRATCH COMMANDECK_MAIN="$p" DASH_NOW="$NOW" bash "$HERE/$NAME.sh" --project "$RUN/proj-$i" >&2) \
      && cat "$RUN/proj-$i/project.json" >> "$RUN/projects.jsonl" || { echo "dashboard: collecting $p failed" >&2; return 1; }
  done < <(registered)
  [ -z "$bare" ] || note="registered with no GitHub origin, not listed: $bare"
  if [ -n "$gone" ]; then nm projects "registered but not a checkout: $gone${note:+; $note}"
  elif [ -n "$note" ]; then rec projects fresh "$NOW" "" "$note"
  else ok projects; fi
  jq -cs 'add // {}' "$RUN/projects.jsonl"
}

# Samples every source into a private directory, then publishes data.js with
# one rename. Any failure keeps the last good data.js and exits nonzero.
render() {
  NOW=$(date +%s)
  claude_dir
  mkdir -p "$CACHE" || return 1
  RUN=$(mktemp -d "$OUT/.run.XXXXXX") || return 1
  # What every project's collect and the limit card share this collect (issue 299): see project().
  export DASH_CYCLE=$NOW.$$ DASH_TERMS=$RUN/terminals.json DASH_CLAUDE_DIR=$CLAUDE_DIR
  mkdir -p "$RUN/src" "$RUN/parts"
  part projects projects && part host host && part limit limit && part alerts alerts \
    && part alertsResolved alerts_resolved || return 1
  jq -cs '{sources: add}' "$RUN"/src/*.json > "$RUN/parts/sources.json" || return 1
  PUB=$(mktemp "$OUT/.data.js.XXXXXX") || return 1
  { printf 'window.DASH = '
    jq -cs --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg name "${COMMANDECK_DASHBOARD_NAME:-}" --arg home "$PP_PROJECT" \
      'add + {updatedAt: $at, home: $home, name: ($name | if . == "" then null else . end)}' "$RUN"/parts/*.json
  } > "$PUB" || return 1
  printf ';\n' >> "$PUB"
  sed -e '1s/^window\.DASH = //' -e '$s/;$//' "$PUB" \
    | jq -e '(.updatedAt | type) == "string" and (.sources | type) == "object" and (.projects | type) == "object"' >/dev/null \
    || { echo "dashboard: built data.js does not validate" >&2; return 1; }
  # The file is a script: a plain "__proto__" key there sets the object's
  # prototype and the entry is gone. A computed key is an own property.
  # With such a key the file is not JSON: cos-watch-alerts.sh and cos-watch-limit.sh put the plain key back before they parse.
  ! grep -q '[{,]"__proto__":' "$PUB" \
    || { sed 's/\([{,]\)"__proto__":/\1["__proto__"]:/g' "$PUB" > "$PUB.k" && mv -f "$PUB.k" "$PUB"; } || return 1
  chmod 644 "$PUB" && mv -f "$PUB" "$OUT/data.js" || return 1
  pp_rm_rf "$RUN"; RUN='' PUB=''
}

# register <repo> / unregister <repo> -- the registry holds each main checkout
# once, by its real path. Two checkouts of one directory name would share a
# project name, and every log under ~/.claude is keyed by it: the second is refused.
register() {
  local p q n m h
  p=$(cd "$1" 2>/dev/null && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && p=${p%/.git} && [ -e "$p/.git" ] \
    || { echo "dashboard: $1 is not a git checkout" >&2; return 1; }
  mkdir -p "$OUT" || return 1
  # A registry that does not list the home project turns it off, so the first registration, which creates the
  # registry, puts home in first: registering another project keeps home collected (issue 292). An explicit
  # --unregister of home still turns it off.
  if [ ! -e "$REG" ]; then
    h=$(cd "$PP_MAIN" 2>/dev/null && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && h=${h%/.git}
    [ -z "$h" ] || [ "$h" = "$p" ] || printf '%s\n' "$h" > "$REG" || return 1
  fi
  while IFS= read -r q; do
    [ "$q" != "$p" ] || { echo "dashboard: $p is already registered"; return 0; }
    # The name as pp_project cleans it: `a b` and `a-b` are one key.
    n=${q##*/} m=${p##*/}
    [ "${n//[^A-Za-z0-9_.-]/-}" != "${m//[^A-Za-z0-9_.-]/-}" ] || { echo "dashboard: $q is registered under the name ${m//[^A-Za-z0-9_.-]/-}; two projects cannot share a name" >&2; return 1; }
  done < <(registered)
  printf '%s\n' "$p" >> "$REG" && echo "dashboard: registered $p"
}
unregister() {
  local p=$1
  [ ! -d "$1" ] || { p=$(cd "$1" && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && p=${p%/.git} || p=$1; }
  # Read as empty, an unreadable registry (or a directory) would be rewritten without every project in it.
  [ ! -e "$REG" ] || { [ -f "$REG" ] && [ -r "$REG" ]; } || { echo "dashboard: cannot read $REG; nothing unregistered" >&2; return 1; }
  registered | grep -vxF -- "$p" > "$REG.new.$$"; mv -f "$REG.new.$$" "$REG" && echo "dashboard: unregistered $p"
}

# import_from <folder> -- issue 292: a one-time carry-over at a switch from another collector. <folder> is laid out as
# $OUT is: cache/limit-history.jsonl and cache/codex-limit-history.jsonl, layout.js (and the host project's
# p/<project>/layout.js), closed.log. Merged in, never over what is here: a history row whose time is held here, and a
# layout slot that exists here, are kept. A history row of another Claude account (its `folder`) is left out, and a
# build's fold written "open"/"shut" is the plugin's false/true. Prints what it took. Each file is read and replaced
# under the lock the collector and the server hold for theirs (dashboard_limit.locked).
import_from() {
  [ -d "$1" ] || { echo "dashboard: --import needs a folder; $1 is none" >&2; return 1; }
  mkdir -p "$CACHE" || return 1
  python3 - "$1" "$OUT" "$HERE" "$CLAUDE_DIR" <<'PY'
import glob, json, os, sys
src, out, here, folder = sys.argv[1:5]
sys.path.insert(0, here)
import dashboard_limit as lim
import dashboard_serve as d
took = []
# The rows taken are this account's: with no record of whose the history is, the collector's next check would move it aside.
lim.switch_account(os.path.join(out, 'cache'))
for name in ('limit-history.jsonl', 'codex-limit-history.jsonl'):
    mine = os.path.join(out, 'cache', name)
    with lim.locked(mine):
        have = lim.read_history(mine)
        if have is None:
            sys.exit('dashboard: cannot read %s; nothing imported over it' % mine)
        have = dict(have)
        new = {}
        try:
            for line in open(os.path.join(src, 'cache', name)):
                try:
                    r = json.loads(line)
                    a, p = lim.epoch(r['at']), r['pct']
                except (ValueError, KeyError, TypeError):
                    continue
                if a is not None and isinstance(p, (int, float)) and r.get('folder') in (None, folder) and a not in have:
                    new[a] = p
        except OSError:
            pass
        if new:
            tmp = '%s.%d' % (mine, os.getpid())
            with open(tmp, 'w') as f:
                f.writelines(json.dumps({'at': lim.iso(a), 'pct': p}) + '\n' for a, p in sorted({**have, **new}.items()))
            os.replace(tmp, mine)
    took.append('%d %s rows' % (len(new), name))
def read(path):
    try:
        v = json.loads(open(path).read().partition('=')[2].strip().rstrip(';'))
    except (OSError, ValueError):
        return {}
    return v if isinstance(v, dict) else {}
def clean(v):
    v = dict(v) if isinstance(v, dict) else {}
    if isinstance(v.get('builds'), dict):
        v['builds'] = {k: b == 'shut' if isinstance(b, str) else b for k, b in v['builds'].items()}
    return {k: x for k, x in v.items() if k in d.HELD and k not in ('rev', 'project') and d.HELD[k](x)}
theirs = read(os.path.join(src, 'layout.js'))
slots_in = dict(theirs.get('projects') or {}) if isinstance(theirs.get('projects'), dict) else {}
for p in glob.glob(os.path.join(src, 'p', '*', 'layout.js')):
    slots_in.setdefault(os.path.basename(os.path.dirname(p)), read(p))
path = os.path.join(out, 'layout.js')
# closed.log too: the server reads it and appends to it in the same save.
with lim.locked(path):
    rev, home, slots = d.held(path)  # one that cannot be read raises: nothing here is replaced blind
    added = []
    if not home and clean(theirs):
        home, rev = clean(theirs), rev + 1
        added.append('home')
    for k, v in slots_in.items():
        if d.CHECKS['project'](k) and k not in slots and clean(v):
            slots[k] = dict(clean(v), rev=1)
            added.append(k)
    if added:
        tmp = '%s.%d.tmp' % (path, os.getpid())
        with open(tmp, 'w') as f:
            f.write('window.DASH_LAYOUT = %s;\n' % json.dumps(dict(home, rev=rev, **({'projects': slots} if slots else {})), sort_keys=True))
        os.replace(tmp, path)
    took.append('layout slots: %s' % (', '.join(added) or 'none'))
    log = os.path.join(out, 'closed.log')
    try:
        have = set(open(log).read().splitlines())
    except FileNotFoundError:
        have = set()
    try:
        new = [l for l in dict.fromkeys(open(os.path.join(src, 'closed.log')).read().splitlines()) if '\t' in l and l not in have]
    except OSError:
        new = []
    if new:
        with open(log, 'a') as f:
            f.write(''.join(l + '\n' for l in new))
took.append('%d cleared builds' % len(new))
print('dashboard: --import from %s took %s' % (src, '; '.join(took)))
PY
}

# free_port -- the first port from 8791 the server can take on $BIND: a port
# free on 127.0.0.1 can be held on ::1. The family is dashboard_serve.py's.
free_port() {
  python3 - "$BIND" <<'PY'
import socket, sys
bind = sys.argv[1]
for port in range(8791, 8891):
    try:
        with socket.socket(socket.AF_INET6 if ":" in bind else socket.AF_INET) as s:
            s.bind((bind, port))
    except OSError:
        continue
    print(port); break
PY
}

# The job runs this copy of the script and serves the view beside it. Every
# file it points at is checked before anything changes. The knobs in force at
# install are kept in the job, so a restart serves the same address.
install() {
  local script=$HERE/$NAME.sh src=$HERE/../dashboard f k env=''
  for f in "$script" "${VIEW[@]/#/$src/}"; do
    [ -s "$f" ] || { echo "dashboard: install needs $f, which is missing or empty" >&2; return 1; }
  done
  bash -n "$script" || { echo "dashboard: $script does not parse" >&2; return 1; }
  [ -n "${COMMANDECK_DASHBOARD_PORT:-}" ] || PORT=$(free_port) && [ -n "$PORT" ] || { echo "dashboard: no free port from 8791" >&2; return 1; }
  # The job has no folder of its own: with no registry it collects the project it was installed from.
  export COMMANDECK_DASHBOARD_PORT=$PORT COMMANDECK_DASHBOARD_BIND=$BIND COMMANDECK_MAIN=$PP_MAIN
  mkdir -p "$OUT" || return 1
  for f in "${VIEW[@]}"; do view_put "$f" || { echo "dashboard: could not copy $src/$f into $OUT" >&2; return 1; }; done
  # The scratch and workspace overrides set at install are the home project's (issue 292); projects() unsets them
  # for a registered project, which derives its own.
  local -a keep=(PATH HOME COMMANDECK_MAIN COMMANDECK_DASHBOARD_PORT COMMANDECK_DASHBOARD_BIND COMMANDECK_DASHBOARD_HOSTS COMMANDECK_DASHBOARD_NAME COMMANDECK_DASHBOARD_DIR CODEX_HOME COMMANDECK_CODEX_REVIEW_HOME
    COMMANDECK_SCRATCH COMMANDECK_WORKSPACES)
  if [ "$(hs_os)" = Darwin ]; then
    local plist=$HOME/Library/LaunchAgents/$HS_PREFIX$NAME.plist
    mkdir -p "${plist%/*}" || return 1
    for k in "${keep[@]}"; do [ -z "${!k:-}" ] || env+="<key>$k</key><string>$(hs__xml "${!k}")</string>"; done
    cat > "$plist.new.$$" <<EOF || { rm -f "$plist.new.$$"; return 1; }
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$HS_PREFIX$NAME</string>
<key>ProgramArguments</key><array><string>$(hs__xml "$BASH")</string><string>$(hs__xml "$script")</string><string>--loop</string></array>
<key>EnvironmentVariables</key><dict>$env</dict>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>StandardOutPath</key><string>$(hs__xml "$OUT/$NAME.log")</string>
<key>StandardErrorPath</key><string>$(hs__xml "$OUT/$NAME.log")</string>
</dict></plist>
EOF
    mv -f "$plist.new.$$" "$plist" || return 1
    launchctl bootout "gui/$(id -u)/$HS_PREFIX$NAME" 2>/dev/null || true
    # bootout returns before the job is gone; bootstrapping in that window fails (error 5).
    for _ in $(seq 50); do launchctl print "gui/$(id -u)/$HS_PREFIX$NAME" >/dev/null 2>&1 || break; sleep 0.1; done
    launchctl bootstrap "gui/$(id -u)" "$plist" || { echo "dashboard: launchctl refused $plist" >&2; return 1; }
  else
    local unit=$HOME/.config/systemd/user/$UNIT
    mkdir -p "${unit%/*}" || return 1
    for k in "${keep[@]}"; do [ -z "${!k:-}" ] || env+="Environment=\"$k=$(hs__sd "${!k}")\""$'\n'; done
    cat > "$unit" <<EOF || return 1
[Unit]
Description=Commandeck dashboard: re-collects $OUT/data.js every 60 s

[Service]
ExecStart="$(hs__sd "$BASH")" "$(hs__sd "$script")" --loop
${env}Restart=always
RestartSec=10
MemoryMax=256M

[Install]
WantedBy=default.target
EOF
    # restart, not enable --now: over a running job (an update) that would leave the old process.
    systemctl --user daemon-reload && systemctl --user enable "$UNIT" && systemctl --user restart "$UNIT"
  fi
}

# view_put <file> -- one view file copied whole from the plugin's own into $OUT, or not at all.
view_put() {
  { cp "$HERE/../dashboard/$1" "$OUT/.$1.new.$$" && mv -f "$OUT/.$1.new.$$" "$OUT/$1"; } 2>/dev/null || { rm -f "$OUT/.$1.new.$$" 2>/dev/null; return 1; }
}
# view_refresh -- each view file whose served copy differs from the plugin's own is copied again: a merged
# change to the view otherwise waited for the next --install, which no merge runs. A failed copy keeps the old file.
view_refresh() {
  local f
  for f in "${VIEW[@]}"; do
    [ -s "$HERE/../dashboard/$f" ] && ! cmp -s "$HERE/../dashboard/$f" "$OUT/$f" || continue
    view_put "$f" || echo "dashboard: could not refresh $OUT/$f from $HERE/../dashboard/$f; the old copy stays" >&2
  done
}

# alive -- the --loop heartbeat, $OUT/alive.js: the time now and the cycle stamps
# the loop left in $OUT/.cycle. The page tells a slow cycle (fresh heartbeat,
# old data.js) from a dead collector (no heartbeat) by it, and reloads itself
# when `view`, the checksum of the installed view files, changes under it.
alive() {
  view_refresh
  printf 'window.DASH_ALIVE = {"at":"%s","view":"%s",%s};\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$(cat "${VIEW[@]/#/$OUT/}" 2>/dev/null | cksum | cut -d' ' -f1)" \
    "$(cat "$OUT/.cycle" 2>/dev/null || echo '"cycleStartedAt":null,"lastCycleSec":null')" > "$OUT/.alive.js.$BASHPID" \
    && mv -f "$OUT/.alive.js.$BASHPID" "$OUT/alive.js"
}
# cycle <start-epoch> <seconds|null> -- stamp the cycle for alive.js; written whole, so alive never reads half.
cycle() {
  printf '"cycleStartedAt":"%s","lastCycleSec":%s' "$(iso "$1")" "$2" > "$OUT/.cycle.tmp" && mv -f "$OUT/.cycle.tmp" "$OUT/.cycle"
  alive
}

uninstall() {
  if [ "$(hs_os)" = Darwin ]; then
    launchctl bootout "gui/$(id -u)/$HS_PREFIX$NAME" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/$HS_PREFIX$NAME.plist"
  else
    systemctl --user disable --now "$UNIT" 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/$UNIT"
    systemctl --user daemon-reload
  fi
}

case "${1:-}" in
  --install) # Issues 263 and 255: a network bind is HTTPS behind a login (dashboard_serve.py), and a restart behind a login no one can pass serves nobody.
             SCHEME=http
             case $BIND in 127.0.0.1|localhost|::1) ;; *)
               SCHEME=https
               python3 "$HERE/dashboard_serve.py" has-password || { echo "dashboard: a network bind needs a login: run python3 $(printf '%q' "$HERE")/dashboard_serve.py set-password <user>, then run this again" >&2; exit 5; }
               python3 "$HERE/dashboard_serve.py" make-cert || { echo "dashboard: install FAILED (certificate)" >&2; exit 1; } ;;
             esac
             install || { echo "dashboard: install FAILED" >&2; exit 1; }
             echo "dashboard installed; open $SCHEME://$([ "$BIND" = 0.0.0.0 ] && echo "<this host>.local" || { case $BIND in *:*) echo "[$BIND]" ;; *) echo "$BIND" ;; esac; }):$PORT/"; exit 0 ;;
  --uninstall) uninstall; echo "dashboard uninstalled"; exit 0 ;;
  # launchd knows the job by its name without the prefix; systemd by its unit.
  --status) if hs_active "$([ "$(hs_os)" = Darwin ] && echo "$NAME" || echo "$UNIT")"; then echo "dashboard: running"; exit 0; fi
            echo "dashboard: NOT RUNNING -- bash $(printf '%q' "$HERE")/$NAME.sh --install"; exit 1 ;;
  --job-file) [ "$(hs_os)" = Darwin ] && echo "$HOME/Library/LaunchAgents/$HS_PREFIX$NAME.plist" || echo "$HOME/.config/systemd/user/$UNIT"; exit 0 ;;
  --register) register "${2:?--register <repo>}"; exit ;;
  --unregister) unregister "${2:?--unregister <repo>}"; exit ;;
  --import) import_from "${2:?--import <folder>}"; exit ;;
  # Internal: merge-unit-local.sh reads the partial list from here, so a merge leaves open what the evidence says is unfinished.
  --progress) builder_progress "${2:?--progress <worktree> <unit>}" "${3:?--progress <worktree> <unit>}"; exit ;;
  # The job's own manager restarts it (issue 294), by the label and unit install wrote.
  --restart) if [ "$(hs_os)" = Darwin ]; then launchctl kickstart -k "gui/$(id -u)/$HS_PREFIX$NAME"
             else systemctl --user --no-block restart "$UNIT"; fi
             exit $? ;;
  --project) project "${2:?}" || { echo "dashboard: collecting $PP_MAIN FAILED" >&2; exit 1; } ;;
  --loop) mkdir -p "$OUT" || exit 1
          rm -f "$OUT/.cycle"
          # Every 15 s while this loop lives (COMMANDECK_DASHBOARD_ALIVE_S, for the self-test), and each refreshes the view files; a cycle's start and end also write it at once.
          { while kill -0 $$ 2>/dev/null; do alive; sleep "${COMMANDECK_DASHBOARD_ALIVE_S:-15}"; done; } & ALV=$!
          last=null
          while :; do
            # Restarted here if it died; request lines would flood dashboard.log.
            # dashboard_serve.py also saves the panel layout to $OUT/layout.js; the page loads that file,
            # so a first start gives it an empty one.
            [ -e "$OUT/layout.js" ] || echo 'window.DASH_LAYOUT = null;' > "$OUT/layout.js"
            [ -n "$SRV" ] && kill -0 "$SRV" 2>/dev/null \
              || { python3 "$HERE/dashboard_serve.py" "$PORT" "$BIND" "$OUT" >/dev/null 2>&1 & SRV=$!; }
            t0=$(date +%s); cycle "$t0" "$last"
            render || echo "dashboard: collection FAILED; data.js keeps the last snapshot" >&2; pp_rm_rf "${RUN:-}" "${PUB:-}"
            last=$(( $(date +%s) - t0 )); cycle "$t0" "$last"
            [ "$last" -le 60 ] || echo "dashboard: cycle took $last s" >&2
            # COMMANDECK_DASHBOARD_CYCLE_S, for the self-test. A foreground sleep would hold off the TERM trap that stops the server.
            sleep "${COMMANDECK_DASHBOARD_CYCLE_S:-60}" & wait $!; done ;;
  "") render || { echo "dashboard: collection FAILED; data.js keeps the last snapshot" >&2; exit 1; } ;;
  *) echo "usage: dashboard.sh [--install|--uninstall|--restart|--status|--job-file|--loop|--register <repo>|--unregister <repo>|--import <folder>]" >&2; exit 2 ;;
esac

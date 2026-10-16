#!/usr/bin/env bash
# dashboard.sh [--install|--uninstall|--status|--job-file|--loop|--register <repo>|--unregister <repo>]
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
# Test seams: COMMANDECK_DASHBOARD_DIR, plus paths.sh's COMMANDECK_* overrides.
set -uo pipefail
# Sampling never writes a worktree: git status would otherwise refresh its index.
# Porcelain git diff rewrites it even so; use diff-index for diffs.
export GIT_OPTIONAL_LOCKS=0
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/paths.sh" || exit 1
. "$HERE/host-services.sh"
. "$HERE/codex-helpers.sh" || exit 1
. "$HERE/../hooks/lib/project.sh"; pp_project "$PP_MAIN"
NAME=dashboard
UNIT=commandeck-$NAME.service  # the Linux unit; another project's dashboard.service is not ours
OUT=${COMMANDECK_DASHBOARD_DIR:-$HOME/.commandeck/dashboard}
CACHE=$OUT/cache
REG=$OUT/projects
TTL=300  # slow reads: a 60 s collection would otherwise repeat them every cycle
METRICS=$PP_MAIN/.claude/metrics
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
# record is live or the newest one's role has no stage.
seat_role() {
  local f created=''
  [ -z "$4" ] || created=$(jq -r --arg p "$2" '[.result.worktrees[]? | select(.path == $p) | .createdAt | numbers][0] // empty | . / 1000 | floor' <<<"$4")
  for f in "$PP_SCRATCH/seat-$1-"*.txt; do
    [ ! -f "$f" ] || awk '{ i = index($0, "="); if (i) v[substr($0, 1, i - 1)] = substr($0, i + 1) }
      END { print v["launched"] "\t" v["role"] "\t" v["task"] "\t" v["unit"] }' "$f"
  done | jq -Rrn --arg u "$1" --argjson open "$3" --arg c "$created" --argjson lanes "$ROLE_LANES" '
    [inputs | split("\t") | select(.[3] == $u and (.[0] | test("^[0-9]+$")) and .[1] != ""
      and (.[2] as $t | any($open[]; . == $t)) and ($c == "" or (.[0] | tonumber) >= ($c | tonumber)))]
    | max_by(.[0] | tonumber) // empty | .[1] as $r | ($lanes[$r] // empty) + "\t" + $r'
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
# builder_progress <worktree> <unit> -- a Builder's {issues, built, findings}, each null when its file is
# missing. Built is false for an evidence file that is there and cannot be read, and an empty list
# only for one read with no built item in it. Issues are the work items brief-issues.sh reads from the brief
# and main's rulings file for the unit: an issue is its number, an item with no issue number its own text.
# Built ones are the items its evidence file heads a section with, findings the newest round report's finding lines.
builder_progress() {
  local d=$1/.claude/briefs u=${2##*/} is=null bu=null fi_=null f t tb
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
  [ ! -f "$d/$u-evidence.md" ] || [ ! -r "$d/$u-evidence.md" ] || tb=$(awk -F'|' '/^\|/ { a = $2; s = $3; gsub(/^[ \t]+|[ \t]+$/, "", a); gsub(/^[ \t]+|[ \t]+$/, "", s)
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
  f=$(ls -t "$d/$u"-r*-reports.md 2>/dev/null | head -1)
  [ -z "$f" ] || fi_=$(grep -oE '^[[:space:]]*[-*] \[P[0-3]\]' "$f" | grep -oE 'P[0-3]' | jq -Rcn '[inputs] as $p | [range(0; 4) | "P\(.)" as $k | {key: $k, value: ($p | map(select(. == $k)) | length)}] | from_entries')
  jq -cn --argjson is "$is" --argjson bu "$bu" --argjson fi "$fi_" '{issues: $is, built: $bu, findings: $fi}'
}
# One projection for the board: every worktree of this project. Orca lists the
# whole machine's worktrees, so every lookup is by path, never by name: two
# projects may each have a unit of one name.
units() {
  local ps='' u wt ag st branch dirty diff age seat s run open='' role sr rd bj bl rows b v vr f
  if ps=$(timeout 8 orca-ide worktree ps --json 2>/dev/null) && jq -e . >/dev/null 2>&1 <<<"$ps"; then ok orca
  else ps=''; nm orca "orca-ide worktree ps failed"; fi
  # Per worktree, the lane of each working pane's role: its recorded launch
  # title (open_pane's record; agents retitle their panes), else its live title.
  local ts pl='{}'
  if [ -z "$ps" ]; then nm orca-terminals "no worktree list to join the panes to"
  else
    if ts=$(timeout 8 orca-ide terminal list --json 2>/dev/null) && jq -e 'has("result")' >/dev/null 2>&1 <<<"$ts"; then ok orca-terminals
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
  for wt in "$PP_WORKSPACES"/*/; do
    wt=${wt%/}; [ -e "$wt/.git" ] || continue
    u=${wt##*/}
    # The relay pane's worktree is a seat, not a unit. Exact name only; app.js SEATS names the same stage.
    case $u in Chief-of-Staff) seat=chief-of-staff ;; *) seat= ;; esac
    ag=null
    [ -z "$ps" ] || ag=$(jq -c --arg p "$wt" '[.result.worktrees[]? | select(.path == $p) | (.agents // [])[] | "\(.agentType):\(.state)"] | join(" ")' <<<"$ps")
    branch=null dirty=null diff=null
    branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null) && branch=$(jq -Rc . <<<"$branch") || branch=null
    # A failed read stays null, never a clean 0; "" is a measured clean diff.
    s=$(git -C "$wt" status --porcelain 2>/dev/null) && dirty=$(grep -c . <<<"$s")
    s=$(git -C "$wt" diff-index HEAD --shortstat 2>/dev/null) && diff=$(jq -Rc 'sub("^ +"; "")' <<<"$s")
    # Orca lists panes and none is working: the pane finished, so the unit
    # waits on main, aged from what the pane left. Unknown stays null.
    st=null age=null
    if [ "$ag" != null ] && [ "$ag" != '""' ] && [[ $ag != *:working* ]]; then
      st='"waiting-main"'; age=$(seat_age "$wt" "$ps")
    fi
    # A live seat record's role sets the stage through ROLE_LANES; a seat role leaves it as read.
    sr=null
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
      if [ ! -e "$bl" ]; then st='"building"' bj='{"steps":[],"signals":[],"verdict":null,"verdictRound":null}'
      elif rows=$(jq -cR 'fromjson? | objects' "$bl" 2>/dev/null) && b=$(jq -cs --argjson now "$NOW" --argjson sessionAt "$(pp_session_log_at "$wt")" -f "$HERE/dashboard_builders.jq" <<<"$rows" 2>/dev/null); then
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
        # Every round file's own verdict by its round, so each finished pass shows its own.
        vs='{}'
        while IFS= read -r r; do
          n=${r##*/}; n=${n#"${u##*/}-r"}; n=${n%-reports.md}
          [[ $n =~ ^[0-9]+$ ]] && vs=$(jq -c --arg n "$((10#$n))" --arg v "$(grep -v '^[[:space:]]*$' "$r" | tail -1 | cut -c1-200)" '.[$n] = $v' <<<"$vs")
        done < <(pp_unit_briefs "$wt/.claude/briefs" "$u" | grep -- '-reports\.md$')
        bj=$(jq -c --argjson vs "$vs" '.verdicts = $vs' <<<"$bj")
      fi
      # An unreadable log stays wholly not measured; any other Builder also carries its issues and findings.
      # reviewedTree: is the worktree still the tree its newest pass read. The build review reads the same script.
      [ "$(jq -c '.steps' <<<"$bj")" = null ] || bj=$(jq -c --argjson p "$(builder_progress "$wt" "$u")" --argjson rt "$(bash "$HERE/reviewed-tree.sh" "$wt" "${u##*/}" 2>/dev/null || echo null)" '. + $p + {reviewedTree: $rt}' <<<"$bj")
      # cache24h: a Builder writes no seat rows, so its 24 h cache hit rate is its own session's usage. With no
      # session log or no turn in 24 h there is no rate to judge and no key; null is a log that failed to read.
      if [ "$(jq -c '.steps' <<<"$bj")" != null ] && f=$(pp_session_log "$wt") && [ -n "$f" ]; then
        cu=$(bash "$HERE/seat-event.sh" --usage claude "$f" $((NOW - 86400)) 2>/dev/null) && jq -e 'type == "object" or . == null' >/dev/null 2>&1 <<<"$cu" || cu='{"tokens":null}'
        [ "$cu" = null ] || bj=$(jq -c --argjson c "$cu" '. + {cache24h: $c.tokens}' <<<"$bj")
      fi
    fi
    jq -cn --arg u "$u" --argjson branch "$branch" --argjson dirty "$dirty" --argjson diff "$diff" --argjson ag "$ag" \
      --argjson st "$st" --argjson age "$age" --argjson sr "$sr" --argjson rd "$rd" --argjson bj "$bj" \
      '{unit: $u, branch: $branch, dirty: $dirty, diffStat: $diff, agents: $ag, stage: $st, seatRole: $sr, ageSec: $age, round: $rd, builder: $bj}' \
      | jq -c --argjson seat "$(seat_actual "$wt")" '. + {seat: $seat}'
  done > "$RUN/in-flight.jsonl"
  if [ -e "$RUN/builder-bad" ]; then nm builder-logs "a Builder event log could not be read"; else ok builder-logs; fi
  # Time in stage: no log line carries a time, so the collect that first sees a
  # unit's stage and round stamps it. A unit seen for the first time was there
  # for at least that long (exact false). Units no longer listed drop out; an
  # unreadable unit list leaves the record as it was.
  local stages=$CACHE/unit-stages.json old known=true
  old=$(jq -ce 'objects' "$stages" 2>/dev/null) || old='{}'
  jq -cs --argjson o "$old" --argjson now "$NOW" 'map(. as $u | $o[$u.unit] as $p
      | (if ($p | type) == "object" and ($p.since | type) == "number" and $p.stage == $u.stage and $p.round == $u.round then $p
         else {stage: $u.stage, round: $u.round, since: $now, exact: ($p != null)} end) as $r
      | $u + {stageSince: ($r.since | todate), stageExact: $r.exact, rec: $r})' "$RUN/in-flight.jsonl" > "$RUN/in-flight.json" || return 1
  # Without the workspace directory, or one that cannot be listed, the unit list is unknown, not empty.
  if ws_listable; then
    jq -c 'map({(.unit): .rec}) | add // {}' "$RUN/in-flight.json" > "$RUN/unit-stages" && mv -f "$RUN/unit-stages" "$stages"
  else known=false; fi
  # Each Builder's cost by stage (#94), from its worktree's own sessions. The last figures read for each unit are
  # kept, so a finished build shows them as they stood at its merge.
  # shortcut: kept by unit name, so a later build under the same name replaces an earlier one's; key by build if that matters.
  local costs kept=$CACHE/unit-cost.json had
  if costs=$(jq -c --arg ws "$PP_WORKSPACES" '[.[] | select(.builder.stageHistory | type == "array" and length > 0)
        | {unit, worktree: "\($ws)/\(.unit)", stages: .builder.stageHistory}]' "$RUN/in-flight.json" \
      | python3 "$HERE/dashboard_limit.py" units "$NOW" "$CACHE" "$HOME/.claude/projects" "${CODEX_HOME:-$HOME/.codex}/sessions" 2>"$RUN/err-unit-cost") \
      && jq -e 'objects' >/dev/null 2>&1 <<<"$costs"; then
    ok unit-cost
    had=$(jq -ce 'objects' "$kept" 2>/dev/null) || had='{}'
    jq -cn --argjson o "$had" --argjson c "$costs" '$o + ($c | with_entries(select(.value != null)))' > "$kept.$$" && mv -f "$kept.$$" "$kept"
  else costs=null; nm unit-cost "Builder costs could not be read: $(head -1 "$RUN/err-unit-cost" 2>/dev/null)"; fi
  jq -c --argjson k "$known" --argjson fin "$(finished_builds)" --argjson c "$costs" --argjson kept "$(jq -ce 'objects' "$kept" 2>/dev/null || echo '{}')" \
    '{inFlight: (if $k then map(del(.rec) | if .builder then .builder.cost = ($c[.unit]? // null) else . end) else null end),
      finishedBuilds: (if $fin == null then null else $fin | map(. + {cost: ($kept[.unit] // null)}) end)}' "$RUN/in-flight.json"
}

# Finished builds: the lines this checkout's own merges appended (merge-unit-local.sh), one per unit name with the
# later line winning, newest first, 100 at most. A line counts when it names this checkout's real path, a unit and a
# commit: another checkout of the same folder name shares the file and none of the list. Each line is read alone, so
# one that is torn or is not a build is dropped, and an empty record is no finished build. No record that can be read is not measured (null): nothing was
# merged here by the plugin yet. The file is named by this project's own name, never by the page.
finished_builds() {
  local out f=$HOME/.commandeck/builds/$PP_PROJECT.jsonl
  [ -f "$f" ] && [ -r "$f" ] || { echo null; return 0; }
  out=$(jq -cR --arg main "$(cd "$PP_MAIN" && pwd -P)" 'fromjson? | objects | select(.main == $main
        and (.unit | type) == "string" and (.unit | test("^[A-Za-z0-9._-]+$")) and (.sha | type) == "string" and (.sha | test("^[0-9a-f]{40,64}$")))
      | {unit, how: (.how | strings // null), at: (.at | strings // null), sha,
         open: (if (.open | type) == "object" then (.open | {P1, P2, P3} | map_values(numbers // null)) else null end)}' \
      "$f" 2>/dev/null \
    | jq -cs 'reduce .[] as $r ({}; .[$r.unit] = $r) | [.[]] | sort_by(.at) | reverse | .[:100]' 2>/dev/null) || out=
  echo "${out:-[]}"
}

# What waits on the owner is the decision ledger. The owner is whoever runs the plugin here: git's user.name for
# this checkout, else the account's name, cut to one line of 80 characters; neither is null.
needs_owner() {
  local dec=null name
  name=$(git -C "$PP_MAIN" config user.name 2>/dev/null) || name=
  [ -n "${name//[[:space:]]/}" ] || name=$(id -un 2>/dev/null) || name=
  if [ ! -e "$METRICS/decisions.jsonl" ]; then nm decisions "no ledger at $METRICS/decisions.jsonl"
  elif dec=$(COMMANDECK_MAIN=$PP_MAIN bash "$HERE/decision.sh" list 2>"$RUN/err-decisions"); then
    ok decisions; dec=$(jq -c 'map(select(.answeredAt == null))' <<<"$dec")
  else dec=null; nm decisions "$(head -1 "$RUN/err-decisions")"; fi
  jq -cn --argjson dec "$dec" --arg name "$name" \
    '{decisions: $dec, name: ($name | gsub("[[:cntrl:]]+"; " ") | gsub("^ +| +$"; "") | .[:80] | if . == "" then null else . end)}'
}

# owner/name of the checkout's GitHub origin, or nothing. Every gh read names it as GH_REPO, so a gh default set
# to another remote (an upstream) cannot mix that repository's issues, checks and pull requests into the page's links.
origin_repo() {
  git -C "$PP_MAIN" config --get remote.origin.url 2>/dev/null \
    | sed -nE 's#^(https://([^/@]+@)?|ssh://git@|git@)github\.com[:/]([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/?$#\3#p' | sed 's/\.git$//'
}

# The project's open GitHub issues labelled P1 (the exact label), counted in the repository of its GitHub origin,
# or with none the one gh resolves from this checkout: a GH_REPO or GH_HOST of the caller's would name one
# repository for every project. A count that cannot be had (no gh, not
# signed in, no GitHub remote, no network, no answer in 8 s, an answer that is not a list of issues) is null, never 0,
# and the reason is the collector's own words: nothing gh prints reaches the snapshot. gh writes to a file, so a
# process it leaves behind cannot hold the collector on a pipe.
# shortcut: the first 1000 open P1 issues are counted, page the list when a project can hold more.
github_p1() {
  local n rc why repo
  repo=$(origin_repo)
  env -u GH_REPO -u GH_HOST ${repo:+GH_REPO=$repo} GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 timeout -k 2 8 \
    gh issue list --state open --label P1 --limit 1000 --json labels > "$RUN/gh-p1" 2>/dev/null </dev/null; rc=$?
  if [ "$rc" -eq 0 ] && n=$(jq -e 'if type == "array" and all(.[]; type == "object" and (.labels | type) == "array" and all(.labels[]; type == "object"))
      then map(select(any(.labels[]; .name == "P1"))) | length else error("not a list of issues") end' "$RUN/gh-p1" 2>/dev/null) \
     && [[ $n =~ ^[0-9]+$ ]]; then ok github-p1; echo "$n"
  else
    case $rc in 0) why="gh's answer was not a list of issues" ;; 124|137) why="gh gave no answer in 8 s" ;; *) why="gh issue list failed (exit $rc)" ;; esac
    nm github-p1 "$why"; echo null
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
# shortcut: the first 200 open issues are read; page the list when a project can hold more.
gh_issues() {
  gh_read issue list --state open --limit 200 --json number,title,url,labels,milestone,createdAt \
    | jq -c 'map({number, title, url, createdAt, milestone: (.milestone.title // null), priority: ([.labels[].name | select(test("^P[0-3]$"))] | sort | .[0] // null)})'
}
gh_milestones() {
  gh_read api 'repos/{owner}/{repo}/milestones?state=open&per_page=100' | jq -c 'map({title, due: .due_on, open: .open_issues, closed: .closed_issues})'
}
# The newest CI run on the branch main pushes to.
gh_runs() { gh_read run list --branch "$1" --limit 1 --json conclusion,status,createdAt,workflowName | jq -c 'map({conclusion, status, createdAt, workflow: .workflowName})'; }

# The GitHub panes' data. repo is the GitHub address of the checkout's origin (github() below reads the same
# remote), so the page can link an issue number, and every gh read is made in it (PANE_REPO). Each gh read goes
# through cached(): re-read every TTL, backed off after a failure, and a failed read keeps its last good copy
# marked stale. A read never had is null with its reason (no GitHub origin, gh missing or not signed in, no
# answer), and only its pane says so.
github_panes() {
  local repo up k prs='' issues='' miles='' runs=''
  repo=$(origin_repo); PANE_REPO=$repo
  if [ -z "$repo" ]; then
    for k in github-prs github-issues github-milestones github-runs; do nm "$k" "no GitHub origin"; done
  else
    prs=$(cached github-prs gh_prs)
    issues=$(cached github-issues gh_issues)
    miles=$(cached github-milestones gh_milestones)
    if up=$(git -C "$PP_MAIN" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null); then runs=$(cached github-runs gh_runs "${up#*/}")
    else nm github-runs "main has no upstream branch"; fi
  fi
  jq -cn --arg repo "$repo" --argjson prs "${prs:-null}" --argjson issues "${issues:-null}" \
    --argjson milestones "${miles:-null}" --argjson runs "${runs:-null}" \
    '{repo: (if $repo == "" then null else "https://github.com/" + $repo end), prs: $prs, issues: $issues, milestones: $milestones, runs: $runs}'
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
  jq -cn --argjson c "$commits" --argjson u "$unpushed" '{commits: $c, unpushed: $u}'
}

since7() { iso $((NOW - 7 * 86400)); }

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
  python3 - "${files[@]}" <<'PY' || rc=$?
import json, re, sys, time
from datetime import datetime, timezone
sessions, blocks, unread, blocked = {}, [], False, set()
for path in sys.argv[1:]:
    try:
        f = open(path, encoding="utf-8", errors="replace")
    except FileNotFoundError:
        continue  # deleted by retention between the listing and the read
    except OSError:
        unread = True  # the count would be short; exit 3 marks it not measured
        continue
    with f:
      for line in f:
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
        calls = sessions.setdefault(row.get("session_id") or None, [])
        if row.get("use"):
            calls.append((row["use"], row.get("call")))
        # A block with no session id is a hook self-test run by hand, not an agent's: Claude and
        # Codex both name the session in every hook payload, a self-test's payload does not.
        if row.get("decision") == "block" and not row.get("session_id"):
            continue
        if row.get("decision") == "block" and row.get("session_id"):
            blocked.add(row["session_id"])
        if row.get("decision") == "block":
            blocks.append((row, calls, len(calls) - 1 if row.get("use") and row.get("session_id") else None))

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
for p in sys.argv[1:]:
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
  local proj=$HOME/.claude/projects/${PP_MAIN//[^a-zA-Z0-9]/-} d dir='' out files
  while IFS= read -r d; do
    [ -e "$proj/$(basename "$d").jsonl" ] && { dir=$d; break; }
  done < <(ls -td "$HOME"/.claude/tasks/*/ 2>/dev/null)
  [ -n "$dir" ] || { nm todos "no main session task list under $HOME/.claude/tasks"; echo null; return 0; }
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
  local proj=$HOME/.claude/projects/$PP_MAIN_SLUG d dir='' s f t m ts
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
  cached claude-usage python3 "$HERE/dashboard_limit.py" fetch > /dev/null
  st=$(jq -r '.[].status' "$RUN/src/claude-usage.json")
  if [ -d "$HOME/.claude/projects" ]; then ok claude-logs; else nm claude-logs "no Claude Code transcripts"; fi
  # Codex's own 7-day reading comes from its session files (the folder builder-codex-pass.sh uses).
  local cx=${CODEX_HOME:-$HOME/.codex}/sessions
  if [ -d "$cx" ]; then ok codex-usage; else nm codex-usage "no Codex sessions at $cx"; fi
  # The day's cost is each project's own: its sessions are the ones run in its main checkout or its worktrees.
  python3 "$HERE/dashboard_limit.py" build "$st" "$CACHE/claude-usage" "$NOW" "$CACHE" "$HOME/.claude/projects" "$cx" \
    "$(jq -c '.projects | map_values([.path, .workspaces])' "$RUN/parts/projects.json")"
}

# The Chief of Staff is the relay pane: its inbox's unread count and the oldest
# unread message's age. `orchestration inbox` only lists; `check` is the verb
# that marks messages read, so a collect never acks its mail.
chief_of_staff() {
  local ts h out
  if ! ts=$(timeout 8 orca-ide terminal list --json 2>/dev/null) || ! jq -e 'has("result")' >/dev/null 2>&1 <<<"$ts"; then
    nm chief-of-staff "orca-ide terminal list failed"; echo null; return 0
  fi
  h=$(jq -r --arg p "$PP_WORKSPACES/Chief-of-Staff" '.result | if type == "array" then . else (.terminals // []) end
    | map(select((.worktreePath // "") == $p)) | .[0].handle // empty' <<<"$ts")
  [ -n "$h" ] || { nm chief-of-staff "no Chief-of-Staff terminal"; echo null; return 0; }
  if out=$(timeout 8 orca-ide orchestration inbox --terminal "$h" --limit 1000 --json 2>/dev/null \
      | jq -ce --argjson now "$NOW" '.result.messages | arrays | (length >= 1000) as $cap | map(select(.read == 0))
        | {unread: length, oldestUnreadAgeSec: (if length == 0 then null else $now - (map(.created_at | fromdateiso8601) | min) end),
           incomplete: $cap}' 2>/dev/null); then
    ok chief-of-staff; echo "$out"
  else nm chief-of-staff "orca-ide orchestration inbox failed"; echo null; fi
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
    --slurpfile parts <(cat "$RUN"/parts/*.json) --slurpfile srcs <(cat "$RUN"/src/*.json) --argjson prev "$prev") || return 1
  jq -c .since <<<"$out" > "$f"
  if jq -e '.missing == []' <<<"$out" >/dev/null; then ok alerts; else nm alerts "$(jq -r '.missing | join(", ")' <<<"$out")"; fi
  jq -c .alerts <<<"$out"
}

# part <key> <fn> -- one top-level group; a group that is not JSON stops the
# publication, so a collector bug never ships as an empty card.
part() {
  local k=$1
  "$2" > "$RUN/v-$k" && jq -c --arg k "$k" '{($k): .}' "$RUN/v-$k" > "$RUN/parts/$k.json" 2>/dev/null \
    && [ "$(wc -l < "$RUN/parts/$k.json")" -eq 1 ] || { echo "dashboard: building $k failed" >&2; return 1; }
}

# project <run dir> -- one project's parts and source records as one object
# in <run dir>/project.json. The run directory is the caller's: it reads the
# file and removes the directory.
project() {
  # The trap goes first: a run folder taken before a failed check here was removed by it.
  trap - EXIT
  RUN=$1 NOW=${DASH_NOW:?} CACHE=$CACHE/$PP_PROJECT
  mkdir -p "$CACHE" "$RUN/src" "$RUN/parts" || return 1
  cd "$PP_MAIN" || return 1
  # A session records its folder as the OS gives it. On a Mac a workspace path typed in another letter case finds
  # the same folder on disk but matches none of its sessions: no Builder's cost, no worktree in the day's cost.
  # The external pwd asks the OS; Bash's own keeps the case as typed.
  local ws
  ws=$(cd "$PP_WORKSPACES" 2>/dev/null && env pwd -P) && PP_WORKSPACES=$ws
  part units units && part needsOwner needs_owner && part githubP1 github_p1 && part github github_panes && part nextPush next_push \
    && part mainChain main_chain && part costPerRole cost_role \
    && part todos todos && part agents bg_agents && part measures measures && part guardBlocks guard_blocks \
    && part chiefOfStaff chief_of_staff || return 1
  jq -cs '{sources: add}' "$RUN"/src/*.json > "$RUN/parts/sources.json" || return 1
  jq -cs --arg n "$PP_PROJECT" --arg p "$PP_MAIN" --arg w "$PP_WORKSPACES" '{($n): (add + {path: $p, workspaces: $w})}' "$RUN"/parts/*.json > "$RUN/project.json"
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
  local p n i=1 gone='' bare='' note=''
  COMMANDECK_MAIN="$PP_MAIN" DASH_NOW="$NOW" bash "$HERE/$NAME.sh" --project "$RUN/proj-1" >&2 && cat "$RUN/proj-1/project.json" > "$RUN/projects.jsonl" || return 1
  while IFS= read -r p; do
    # The home project is collected above; a name is one key, so a second checkout under home's name is home.
    n=${p##*/}; [ "${n//[^A-Za-z0-9_.-]/-}" != "$PP_PROJECT" ] || continue
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
  mkdir -p "$CACHE" || return 1
  RUN=$(mktemp -d "$OUT/.run.XXXXXX") || return 1
  mkdir -p "$RUN/src" "$RUN/parts"
  part projects projects && part host host && part limit limit && part alerts alerts || return 1
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
  local p q n m
  p=$(cd "$1" 2>/dev/null && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && p=${p%/.git} && [ -e "$p/.git" ] \
    || { echo "dashboard: $1 is not a git checkout" >&2; return 1; }
  mkdir -p "$OUT" || return 1
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
  registered | grep -vxF -- "$p" > "$REG.new.$$"; mv -f "$REG.new.$$" "$REG" && echo "dashboard: unregistered $p"
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
  local -a keep=(PATH HOME COMMANDECK_MAIN COMMANDECK_DASHBOARD_PORT COMMANDECK_DASHBOARD_BIND COMMANDECK_DASHBOARD_HOSTS COMMANDECK_DASHBOARD_NAME COMMANDECK_DASHBOARD_DIR CODEX_HOME)
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
  --install) install || { echo "dashboard: install FAILED" >&2; exit 1; }
             echo "dashboard installed; open http://$([ "$BIND" = 0.0.0.0 ] && echo "<this host>.local" || { case $BIND in *:*) echo "[$BIND]" ;; *) echo "$BIND" ;; esac; }):$PORT/"; exit 0 ;;
  --uninstall) uninstall; echo "dashboard uninstalled"; exit 0 ;;
  # launchd knows the job by its name without the prefix; systemd by its unit.
  --status) if hs_active "$([ "$(hs_os)" = Darwin ] && echo "$NAME" || echo "$UNIT")"; then echo "dashboard: running"; exit 0; fi
            echo "dashboard: NOT RUNNING -- bash $(printf '%q' "$HERE")/$NAME.sh --install"; exit 1 ;;
  --job-file) [ "$(hs_os)" = Darwin ] && echo "$HOME/Library/LaunchAgents/$HS_PREFIX$NAME.plist" || echo "$HOME/.config/systemd/user/$UNIT"; exit 0 ;;
  --register) register "${2:?--register <repo>}"; exit ;;
  --unregister) unregister "${2:?--unregister <repo>}"; exit ;;
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
            sleep 60 & wait $!; done ;;  # a foreground sleep would hold off the TERM trap that stops the server
  "") render || { echo "dashboard: collection FAILED; data.js keeps the last snapshot" >&2; exit 1; } ;;
  *) echo "usage: dashboard.sh [--install|--uninstall|--status|--job-file|--loop|--register <repo>|--unregister <repo>]" >&2; exit 2 ;;
esac

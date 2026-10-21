#!/usr/bin/env bash
# paths.sh -- sourced, never run. The one home for the primary checkout, the
# Orca workspaces root and the shared scratch, identical on the PC and the Mac.
#
# The primary checkout is the project the script is RUN FOR: the session's
# project (CLAUDE_PROJECT_DIR), else the folder it is run in, taken to that
# checkout's git common dir, so main and every linked worktree resolve the same
# checkout and the same scratch. Never this file's own location: an installed
# plugin sits in Claude Code's plugin cache and serves every project on the
# machine. A second formula anywhere forks scratch state.
# Overrides: COMMANDECK_MAIN and COMMANDECK_WORKSPACES, read by project-main.sh
# alone under the rule written there (inside a linked worktree git decides);
# COMMANDECK_SCRATCH and COMMANDECK_CM (the code-graph CLI), as given. The PP_* names are outputs only, exported so a child
# script or an embedded Python ledger reads the same values.
#
# The slug transform (every non-alphanumeric byte to '-') is Claude Code's own
# project-folder naming, so PP_MAIN_SLUG and PP_WORKSPACES_SLUG also name the
# ~/.claude/projects folders the ledgers read.
pp_slug() { printf '%s' "$1" | tr -c 'A-Za-z0-9' '-'; }
# pp_rm_rf <path>... -- rm -rf, removing nothing when any path is in a git folder (a file too), is a .git, or is a
# folder that holds a .git or a git folder at any depth, holds this project's checkout, or is HOME or / (dashboard.sh's
# exit trap once removed a main checkout). A git folder is known by what it holds (a HEAD file beside an objects
# folder, git's own test), never by its name or by asking git, whose answer the caller's GIT_* variables change.
# Every script that reads this file removes a folder through it; project-main.test.sh lists the few that may not.
pp_rm_rf() {
  local p r d m
  m=$(cd "${PP_MAIN:-/nonexistent}" 2>/dev/null && pwd -P) || m=
  for p in "$@"; do
    [ -n "$p" ] && [ -e "$p" ] && [ ! -L "$p" ] || continue
    if [ -d "$p" ]; then r=$(cd "$p" && pwd -P); else r=$(cd "$(dirname -- "$p")" && pwd -P); fi || return 1
    d=$r; while [ ! -f "$d/HEAD" ] || [ ! -d "$d/objects" ]; do [ "$d" = / ] && { d=; break; }; d=$(dirname -- "$d"); done
    if [ -n "$d" ] || [ "${p##*/}" = .git ] \
      || { [ -d "$p" ] && { [ "$r" = / ] || [ "$r" = "$(cd "$HOME" && pwd -P)" ] || case $m/ in "$r"/*) true ;; *) false ;; esac \
        || [ -n "$(find "$r" \( -name .git -o -name HEAD -type f -exec sh -c 'test -d "${1%/*}/objects"' _ {} \; \) -print -quit 2>/dev/null)" ]; }; }; then
      echo "paths.sh: refusing to remove $p: it is or holds a checkout or git data, HOME, / or $PP_MAIN; nothing was removed" >&2
      return 1
    fi
  done
  rm -rf -- "$@"
}

# Preflight. requirements.sh puts Homebrew's folders ahead of the system ones
# on a Mac's PATH, starts a script the Mac's own Bash 3.2 ran again under
# Homebrew's, and holds the one requirements list. What every script needs
# from that list is checked here on a Mac (its own tools are BSD ones and its
# Bash is 3.2); anything missing stops the caller before any work. It asks
# uname, not COMMANDECK_HOST_OS: a self-test's pretend Mac has no Homebrew.
. "$(dirname "${BASH_SOURCE[0]}")/requirements.sh"
if [ "$REQ_UNAME" = Darwin ] && ! req_check all; then
  { echo "paths.sh: Mac preflight failed."; req_report
    echo "setup installs what it can on a yes: bash $(printf '%q' "$REQ_DIR")/setup.sh --profile claude|claude-openai --install-missing"; } >&2
  return 1
fi

. "$(dirname "${BASH_SOURCE[0]}")/project-main.sh"
pp_main_resolve || { echo "paths.sh: no project here: no git checkout found (tried: $PP_TRIED); run it in the project, or set COMMANDECK_MAIN" >&2
  return 1; }
PP_MAIN_SLUG=$(pp_slug "$PP_MAIN")
PP_WORKSPACES_SLUG=$(pp_slug "$PP_WORKSPACES")
PP_SCRATCH=${COMMANDECK_SCRATCH:-$HOME/.commandeck/scratch/$PP_MAIN_SLUG}
# The Orca run this project's orchestrator is bound to; board.sh is its one
# writer. Never Orca's ~/.config/orca/current-run: every project on the machine
# shares that file. hooks/lib/project.sh pp_run_file spells the same path.
PP_RUN_FILE=$PP_SCRATCH/current-run
# pp_owed_clear <time> -- removes $PP_SCRATCH/cos-owed, the owner's message main owes the relay a reply to, when it was
# marked before <time>. to-main.sh writes the mark under cos-owed.lock, and this holds that lock from its read to its
# removal: a newer mark written between the two was removed with the old one. cos-watch-inbox.sh takes it too.
pp_owed_clear() {
  local at
  { flock -w 10 9 && IFS=$'\t' read -r at _ < "$PP_SCRATCH/cos-owed" && [ "$at" -lt "$1" ] && rm -f "$PP_SCRATCH/cos-owed"; } 9>>"$PP_SCRATCH/cos-owed.lock" 2>/dev/null
}
export PP_MAIN PP_WORKSPACES PP_MAIN_SLUG PP_WORKSPACES_SLUG PP_SCRATCH
PP_SCRIPTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# The same path as one shell word, for a command that is printed to be run.
PP_SCRIPTS_Q=$(printf '%q' "$PP_SCRIPTS")
# The project rules a Builder never loads (worktree-setup.sh --builder excludes them; every worker
# excludes the first).
PP_BUILDER_RULES_OFF="orchestration agents planning adversarial-reviews worktree-sessions"

# The code-graph project for the primary checkout, chosen by root path from
# list_projects. Each machine indexes the checkout under its own home, so the
# name differs per machine; none is guessed, and an unindexed checkout is an
# error naming what is indexed, never the other machine's project. The last
# name this machine resolved is kept in $PP_SCRATCH/graph-project and answers
# only when no list came back at all; a list without the checkout
# still errors and deletes it.
PP_CM=${COMMANDECK_CM:-$HOME/.local/bin/codebase-memory-mcp}
PP_CM_TIMEOUT=${COMMANDECK_CM_TIMEOUT:-30}
# A part brief's `Review base:` sha is rewritten by any rebase, and
# review-round.sh refuses a base that is not an ancestor of HEAD. Count before
# the rebase, restore after: the base keeps its distance below the tip.
# ponytail: a commit the rebase drops as already upstream shifts it by one;
# review-round.sh still refuses loudly.
pp_review_base_count() {  # <worktree> <brief file>; prints nothing without a base
  local b; b=$(sed -n 's/^Review base: `\{0,1\}\([0-9a-f]\{7,40\}\)`\{0,1\}.*/\1/p' "$2" 2>/dev/null | head -1)
  [ -z "$b" ] || git -C "$1" rev-list --count "$b..HEAD"
}
pp_review_base_restore() {  # <worktree> <brief file> <count from pp_review_base_count>
  [ -n "${3:-}" ] || return 0
  sed -i.bak "s/^Review base: .*/Review base: \`$(git -C "$1" rev-parse --short=8 "HEAD~$3")\`/" "$2" && rm -f "$2.bak"
}

# Bounded, three attempts 3 s then 6 s apart: a CBM daemon that cannot start
# under load hung every dispatch that asked it here with no end (2026-09-28),
# and under load it also answered empty twice running.
pp_graph_project() {
  local list i name rc cache=$PP_SCRATCH/graph-project
  for i in 1 2 3; do
    list=$(timeout "$PP_CM_TIMEOUT" "$PP_CM" cli --json list_projects '{}' 2>/dev/null) && [ -n "$list" ] && break
    [ "$i" = 3 ] || sleep $((i * 3))
  done
  name=$(printf '%s' "$list" | PP_MAIN=$PP_MAIN PP_CM=$PP_CM python3 -c '
import json, os, sys
try:
    projects = json.loads(json.load(sys.stdin)["content"][0]["text"])["projects"]
except Exception as e:
    print("paths.sh: no project list from %s list_projects (%s)" % (os.environ["PP_CM"], e), file=sys.stderr)
    sys.exit(2)
main = os.environ["PP_MAIN"]
names = [p["name"] for p in projects if os.path.realpath(p.get("root_path", "")) == os.path.realpath(main)]
if not names:
    sys.exit("paths.sh: no code-graph project for %s; indexed: %s" % (
        main, ", ".join("%s (%s)" % (p["name"], p.get("root_path")) for p in projects) or "none"))
print(names[0])') && rc=0 || rc=$?
  case $rc in
    0) mkdir -p "$PP_SCRATCH" && printf '%s\n' "$name" > "$cache.$$" && mv "$cache.$$" "$cache" || true
       printf '%s\n' "$name" ;;
    2) [ -s "$cache" ] || return 1
       echo "paths.sh: using the cached code-graph project from $cache" >&2
       cat "$cache" ;;
    *) rm -f "$cache"; return 1 ;;
  esac
}

# pp_session_log <worktree> -- the worktree's newest Claude session record, or nothing.
# pp_session_log_at <worktree> -- the epoch that record was last written, or null: a seat in one long model
# turn writes it while its event log shows nothing, so the dashboard and main-watch.sh both read it.
pp_session_log() { ls -t "$HOME/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$1")"/*.jsonl 2>/dev/null | head -1; }
pp_session_log_at() {
  local f
  f=$(pp_session_log "$1")
  [ -n "$f" ] && stat -c %Y "$f" 2>/dev/null || echo null
}
# pp_session_bg_open <worktree> -- how many background shell jobs the newest session record started (a tool result's
# toolUseResult.backgroundTaskId) and holds no <task-notification> or successful TaskStop for, or null with no record (issue 203). A background
# call ends at once in the event log, so a Builder idle while its job runs is working, not QUIET; the notification row is
# the job's own completion, whatever its status. A notification quoted in the record can only clear a job, which lets
# QUIET fire, never hide it.
pp_session_bg_open() {
  local f
  f=$(pp_session_log "$1")
  [ -n "$f" ] || { echo null; return; }
  comm -23 \
    <(grep -F backgroundTaskId "$f" | jq -Rr 'fromjson? | .toolUseResult | objects | .backgroundTaskId | strings' 2>/dev/null | sort -u) \
    <({ grep -F '<task-notification>' "$f" | grep -o '<task-id>[A-Za-z0-9_-]*</task-id>' | sed 's/<[^>]*>//g'
        # A TaskStop sends no notification: its successful result ends the job, as read-verdict.sh reads it.
        grep -F 'Successfully stopped' "$f" | jq -Rr 'fromjson? | select(.message.content | tostring | contains("Successfully stopped"))
          | .toolUseResult | objects | .task_id | strings' 2>/dev/null; } | sort -u) | wc -l | tr -d ' '
}
# pp_session_cache <worktree> -- the parent's prompt cache from the last 400 lines of the newest session record, as
# {ttl, ctx, at, ended} or null (issue 203). Main-thread rows only (a helper writes its own subagents/agent-*.jsonl; an
# isSidechain row is skipped). ctx: the newest reply carrying usage, the context the parent's cache holds. at: when that
# reply's request started, the newest user row before its first block (every block repeats message.id): the TTL runs from
# request start, so a reply's end would let a slow reply ping a lapsed cache. No such row in the window is at null, and
# WARM never pings on it. ttl: the newest reply that wrote cache says which one applied (1h tokens 3600, 5m tokens 300).
# ended: the newest assistant or user row is an end_turn reply, so the parent is at its prompt. No usage row, or no
# cache write in the window, is null, and null means no ping.
pp_session_cache() {
  local f
  f=$(pp_session_log "$1")
  [ -n "$f" ] || { echo null; return; }
  tail -n 400 "$f" | jq -cRn '
    def ep: sub("\\.[0-9]+"; "") | fromdateiso8601;
    def rk: .message.id // .uuid // .timestamp;
    [inputs | fromjson? | objects | select(.isSidechain != true and (.type == "assistant" or .type == "user"))] as $rows
    | [$rows[] | select(.type == "assistant" and .message.usage != null)] as $rep
    | ([$rep[] | select((.message.usage.cache_creation_input_tokens // 0) > 0)] | last) as $w
    | ($w.message.usage.cache_creation // {}) as $c
    | (if ($c.ephemeral_1h_input_tokens // 0) > 0 then 3600 elif ($c.ephemeral_5m_input_tokens // 0) > 0 then 300 else null end) as $ttl
    | ($rep | last) as $n
    | if $ttl == null or $n == null then null
      else ($n | rk) as $k
      | ([range($rows | length) | select($rows[.] | .type == "assistant" and rk == $k)] | first) as $i
      | {ttl: $ttl,
         ctx: (($n.message.usage.input_tokens // 0) + ($n.message.usage.cache_read_input_tokens // 0) + ($n.message.usage.cache_creation_input_tokens // 0)),
         at: ([$rows[:$i][] | select(.type == "user" and .timestamp != null)] | last | .timestamp | if . then ep else null end),
         ended: ($rows | last | .type == "assistant" and .message.stop_reason == "end_turn")}
      end' 2>/dev/null || echo null
}

# pp_waited_on <handle> [now] [turn text] -- a `seat.sh wait` watches this pane:
# it is still waiting (its pid, line 1 of $PP_SCRATCH/waiting-<handle>), or under
# 5 minutes ago it saw the marker this turn's text prints on a line of its own
# (`seen <epoch> <marker>`; a warm pane's next marker is a new event). That wait
# is the pane's report, so main-watch.sh and the turn-complete hooks do not wake
# main a second time. The line match is seat.sh wait's own marker_count.
# One wait reports one finish: a caller that names its event (`<who>:<id>`, the
# 4th argument) is refused a marker it already took for another event, so a
# follow-up turn that ends on the same line within the 5 minutes still wakes main.
# Scratch survives a reboot, so the pid alone proves nothing: the file also
# holds the wait's start time (pp_wait_mark), and a pid that is gone or started
# at another time is a stale file, removed here.
pp_wait_mark() { printf '%s\nstart %s\n' "$$" "$(LC_ALL=C ps -o lstart= -p "$$" | xargs)"; }
pp_waited_on() {
  local f=$PP_SCRATCH/waiting-$1 seen at m pid u
  [ -n "$1" ] && [ -f "$f" ] || return 1
  seen=$(sed -n 's/^seen //p' "$f")
  if [ -z "$seen" ]; then
    pid=$(sed -n 1p "$f"); at=$(sed -n 's/^start //p' "$f")
    [ -n "$at" ] && [ "$(LC_ALL=C ps -o lstart= -p "$pid" 2>/dev/null | xargs)" = "$at" ] && return 0
    rm -f "$f"; return 1
  fi
  read -r at m <<<"$seen"
  [ -n "$m" ] && [ $(( ${2:-$(date +%s)} - at )) -lt 300 ] \
    && printf '%s\n' "${3:-}" | sed -E 's/^[[:space:]*`•]+//; s/[[:space:]*`"]+$//' | grep -qxF -- "$m" || return 1
  [ -n "${4:-}" ] || return 0
  u=$PP_SCRATCH/waited-$1.${4%%:*}
  [ "$(sed -n 1p "$u" 2>/dev/null)" != "$at" ] || [ "$(sed -n 2p "$u")" = "$4" ] || return 1
  printf '%s\n%s\n' "$at" "$4" > "$u"
}

# pp_main_foreground -- true in main's own foreground: the main checkout, a terminal or a Claude session, and not a
# child of pp_detach or of run-shell-tests.sh (COMMANDECK_FOREGROUND). pp_detach <log> <label> <cmd>... runs the
# command detached with its output in <log>, prints the pid and the log, and sends main the result as a status
# message (issue 230): a merge or a full suite takes minutes, and main's turn waited on it.
pp_main_foreground() {
  [ -z "${COMMANDECK_FOREGROUND:-}" ] && { [ -t 0 ] || [ -n "${CLAUDECODE:-}" ]; } \
    && [ "$(git rev-parse --path-format=absolute --git-dir 2>/dev/null)" = "$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ]
}
pp_detach() {
  local log=$1 label=$2; shift 2
  mkdir -p "${log%/*}" || return 1
  COMMANDECK_FOREGROUND=1 nohup bash -c 'log=$1 label=$2; shift 2; "$@" > "$log" 2>&1; rc=$?
    bash "$0" status "$label: exit $rc" "$(tail -n 5 "$log")" >/dev/null 2>&1' "$PP_SCRIPTS/to-main.sh" "$log" "$label" "$@" </dev/null >/dev/null 2>&1 &
  echo "$label: running detached, pid $!; log $log. Its result comes to main as a status message."
}
# pp_close_items <handle>... -- complete main-watch's open item task of each of these seats (issue 227): the
# script that handled the item (a merge, an answer, a collect) closes it, as main did by hand. A close that fails
# is said and costs nothing else.
pp_close_items() {
  local h f t
  for h in "$@"; do
    for f in "$PP_SCRATCH/main-watch"/item-*seat-"$h"-*; do
      [ -f "$f" ] && ! grep -qx handled "$f" || continue
      t=$(sed -n 's/^task=//p' "$f"); [ -n "$t" ] && [ "$t" != none ] || continue
      ! pp_task_close "$t" completed || echo "closed main-watch item task $t"
    done
  done
  return 0
}
# Close an Orca task whose work has SETTLED. While the task's supervised
# dispatch is active Orca refuses (task_not_startable), and a warm pane with an
# active dispatch refuses the next one, so the dispatch is settled with
# worker-abandon (no process or filesystem action; the pane keeps its context),
# then worker-release, and the close retried once. Abandoned but unreleased, the
# pane still refused the next dispatch; release never closes a pane we opened
# ourselves, only one Orca created. Never for a worker still working: abandon fences it.
pp_task_close() { # task status [result-json]
  local args=(--id "$1" --status "$2" --json) out d h
  [ -z "${3:-}" ] || args+=(--result "$3")
  out=$(orca-ide orchestration task-update "${args[@]}" 2>&1 || true)
  jq -e '.ok' <<<"$out" >/dev/null 2>&1 && return 0
  # A driver's own launchd/systemd terminal holds no run binding; act as the
  # handle run-bound.sh names (the same rebind close-round.sh does) and retry.
  if grep -q run_required <<<"$out" && h=$("$PP_SCRIPTS/run-bound.sh"); then
    export ORCA_TERMINAL_HANDLE=$h
    out=$(orca-ide orchestration task-update "${args[@]}" 2>&1 || true)
    jq -e '.ok' <<<"$out" >/dev/null 2>&1 && return 0
  fi
  if grep -q task_not_startable <<<"$out"; then
    d=$(orca-ide orchestration dispatch-show --task "$1" --json 2>/dev/null | jq -r '.result.dispatch.id // empty' 2>/dev/null || true)
    if [ -n "$d" ] && orca-ide orchestration worker-abandon --dispatch "$d" --json >/dev/null 2>&1 \
      && jq -e '.ok' <<<"$(orca-ide orchestration worker-release --dispatch "$d" --json 2>/dev/null)" >/dev/null 2>&1; then
      out=$(orca-ide orchestration task-update "${args[@]}" 2>&1 || true)
      jq -e '.ok' <<<"$out" >/dev/null 2>&1 && return 0
    fi
  fi
  d=$(jq -r '.error | select(.) | "\(.code): \(.message)"' <<<"$out" 2>/dev/null || true)
  echo "could not close task $1 ($2): ${d:-${out:-no answer from orca-ide}}" >&2
  return 1
}

# A pane waiting on a person: Claude's and Codex's permission and approval
# prompts, and Claude's AskUserQuestion picker. Nothing is ever typed into one
# (unit-loop.sh's stall nudge, main-watch.sh's wake).
PROMPT_BLOCKED='Do you want to (proceed|make this edit|create|allow)|Would you like to (run|make|allow)|Allow (command|once|this)|Yes, and don.t ask again|requires approval|approve this|Press enter to confirm|Enter to select'

# THE ROUTING READER. config/routing.json is the one home of
# every role's model, effort and launch settings; nothing else names a model.
# Every launch, review, fix, gate and judge resolves its seat here, and every
# call validates the WHOLE file first, so a malformed entry anywhere stops a
# launch before a pane opens. Nothing is read until a caller asks. The file is
# the one beside this script unless COMMANDECK_ROUTING names another. Values are
# checked against a safe character set and quoted for the pane's shell; no
# configuration text is ever evaluated.
pp_routing() { printf '%s\n' "${COMMANDECK_ROUTING:-$PP_SCRIPTS/../config/routing.json}"; }
PP_ROUTE_JQ='
def fail($m): error("routing: " + $m);
def efforts: ["low", "medium", "high", "xhigh", "max"];
def wiring: ["claude", "codex", "exec", "-p"];
def slot: {model: "model", context: "model", effort: "effort", fast: "fast", advisor: "advisor", tools: "tools",
  memory: "env", reviewer: "env", codexHome: "env", compactLimit: "compact", sandbox: "sandbox",
  approval: "approval", network: "network", shellEnv: "shellenv", mcpDisabled: "mcp", disabledSkills: "skills",
  disablePlugins: "plugins", projectDocMaxBytes: "projectdoc"};
def is($re): type == "string" and test($re);
def bool: type == "boolean";
def count: type == "number" and . >= 0 and floor == .;
def template_of: .agent + (if .headless then "-headless" else "" end);
def check_seat($name; $root):
  . as $s
  | if type != "object" then fail("\($name) is not an object") else . end
  | if (.agent | IN("claude", "codex")) | not then fail("\($name).agent must be claude or codex") else . end
  | if .inherit then
      (keys - ["agent", "inherit", "edits", "note"]) as $x
      | if ($x | length) > 0 then fail("\($name) inherits its model, so \($x[0]) has no place on it") else . end
    else
      (keys - (slot | keys) - ["agent", "headless", "unboxed", "edits", "note", "triggers", "role"]) as $x
      | if ($x | length) > 0 then fail("\($name) has unknown field \($x[0])") else . end
      | if (.model | is("^[a-z0-9][a-z0-9._-]*$")) | not then fail("\($name).model is missing or not a model id") else . end
      | if has("effort") | not then fail("\($name).effort must be present (null omits it)") else . end
      | if .effort != null and (.effort | IN(efforts[]) | not) then fail("\($name).effort \(.effort) is not one of \(efforts | join(", "))") else . end
      | if has("context") and .context != "1m" then fail("\($name).context must be 1m") else . end
      | if ([.fast, .reviewer, .network, .disablePlugins, .headless, .unboxed] | map(select(. != null)) | all(bool)) | not then fail("\($name) has a non-boolean switch") else . end
      | if has("memory") and (.memory | is("^[0-9]+[KMGT]?$") | not) then fail("\($name).memory must look like 12G") else . end
      | if has("advisor") and (.advisor | is("^[a-z0-9][a-z0-9._-]*$") | not) then fail("\($name).advisor is not a model alias") else . end
      | if has("tools") and ((.tools | type) != "array" or (.tools | length) == 0 or (.tools | all(is("^[A-Za-z]+$")) | not)) then fail("\($name).tools must be tool names") else . end
      | if has("codexHome") and (.codexHome | is("^~?/[A-Za-z0-9._/-]+$") | not) then fail("\($name).codexHome must be a path") else . end
      | if has("sandbox") and (.sandbox | IN("read-only", "workspace-write") | not) then fail("\($name).sandbox must be read-only or workspace-write") else . end
      | if has("approval") and (.approval | IN("untrusted", "on-failure", "on-request", "never") | not) then fail("\($name).approval is not a Codex approval policy") else . end
      | if has("shellEnv") and ((.shellEnv | type) != "object" or (.shellEnv | to_entries | all((.key | is("^[A-Z_][A-Z0-9_]*$")) and (.value | is("^[A-Za-z0-9_./:@%+,-]+$"))) | not)) then fail("\($name).shellEnv must map NAMES to plain values") else . end
      | if has("mcpDisabled") and ((.mcpDisabled | type) != "array" or (.mcpDisabled | all(is("^[a-z0-9_-]+$")) | not)) then fail("\($name).mcpDisabled must be server names") else . end
      | if has("disabledSkills") and ($root.launch.skillSets[.disabledSkills] | type) != "array" then fail("\($name).disabledSkills names no launch.skillSets entry") else . end
      | if ([.compactLimit, .projectDocMaxBytes] | map(select(. != null)) | all(count)) | not then fail("\($name) has a limit that is not a whole number") else . end
      | if (.headless or .unboxed or $root.launch.paneBox != null) | not then fail("\($name) is boxed but launch.paneBox is not set; set unboxed: true") else . end
      | if .headless and ([has("memory"), has("reviewer"), has("unboxed")] | any) then fail("\($name) is headless: it has no pane for memory, reviewer or box") else . end
      | ($root.launch.templates[template_of] // fail("\($name): no launch.templates.\(template_of) for its agent")) as $t
      | ($t | [scan("\\{([a-z]+)\\}")[0]]) as $have
      | ([to_entries[] | select(.value != null) | (if .key == "shellEnv" and $s.agent == "claude" then "env" else slot[.key] end) // empty] - $have) as $missing
      | if ($missing | length) > 0 then fail("\($name) sets a {\($missing[0])} setting its \(template_of) template has no place for") else . end
    end;
# The one rule for a template: its placeholders and executable, in order, are
# exactly this sequence. {box} and {env} must precede the executable (after it
# they are arguments to it), and no placeholder may go missing or repeat.
def canonical: {
  claude: "{box} {env} claude {model} {effort} {tools} {advisor} {fast}",
  codex: "{box} {env} codex {compact} {model} {effort} {fast} {sandbox} {approval} {network} {shellenv} {mcp} {skills} {plugins}",
  "claude-headless": "{env} claude {model} {effort} {tools} {fast}",
  "codex-headless": "{env} codex {sandbox} {projectdoc} {model} {effort} {fast}"};
def check_templates:
  (.launch.templates // fail("launch.templates is missing")) | to_entries[]
  | .key as $k | (.value | split(" ") | map(select(. != ""))) as $w
  | (canonical[$k] // fail("launch.templates.\($k) is not a known template")) as $c
  | ($w[] | select(test("^\\{[a-z]+\\}$") or IN(wiring[]) | not)
     | fail("launch.templates.\($k): \(.) is neither a placeholder nor wiring; settings live in role fields"))
  , (if [$w[] | select(test("^\\{[a-z]+\\}$") or IN("claude", "codex"))] != ($c | split(" ")) then fail("launch.templates.\($k) must follow \($c) around its wiring") else empty end);
# The Claude model aliases this file already names: what a project may choose from.
def aliases: [.roles[] | (.candidates // [.])[] | select(.agent == "claude") | .model, .advisor | strings] | unique;
def seat_at($root; $spec):
  ($spec | capture("^(?<r>[a-z0-9-]+)(\\.(?<i>[0-9]+))?$") // fail("\($spec) is not a role name")) as $p
  | ($root.roles[$p.r] // fail("no role \($p.r)")) as $role
  | if $role.candidates then
      if $p.i == null then fail("\($p.r) has candidates; name one as \($p.r).<index>") else . end
      | ($role.candidates[$p.i | tonumber] // fail("\($p.r) has no candidate \($p.i)")) + {edits: $role.edits}
    elif $p.i != null then fail("\($p.r) has no candidates")
    else $role end
  | . + {role: $p.r}
  # A project may choose the model and effort of its Builder (set-up stores them,
  # pp_route_json hands them in). The one place they apply, and only to this role.
  # An advisor an older set-up stored is not read: every Builder runs with none (the owner, 2026-10-14).
  | if $p.r != "builder" then . else
      . + ($ARGS.named.builder // {} | {model, effort} | with_entries(select(.value != null)
        | (if .key == "model" then $root | aliases else ["low", "medium", "high", "max"] end) as $ok
        | if .value | IN($ok[]) then . else fail("this project has builder.\(.key) \(.value), which is not one of \($ok | join(", ")); set-up sets it") end))
    end
  # Codex fast mode changes what a run costs: it is the answer set-up saved
  # (pp_codex_fast hands it in) and never the routing file itself. No quote mark here: this is inside one.
  | if ($p.r | startswith("codex-reviewer")) then .fast = ($ARGS.named.codexFast == true) else . end
  # The same for a plan seat: the per-seat answer of the owner at set-up (planFast, pp_route_json hands it in).
  | if ($p.r | startswith("plan-")) and any($ARGS.named.planFast // [] | .[]; . == $p.r) then .fast = true else . end;
def validate:
  . as $root
  | ([check_templates] | length) as $_
  | (.profile | . == null or IN("claude", "claude-openai") or fail("profile must be claude or claude-openai")) as $_
  | (.launch.paneBox | . == null or is("^(\\$HOME)?/[A-Za-z0-9._/-]+$") or fail("launch.paneBox must be a path")) as $_
  | ([.launch.skillSets // {} | .[][] | select(is("^(\\$HOME)?/[A-Za-z0-9._/-]+$") | not)] | if length > 0 then fail("launch.skillSets holds a value that is not a path: \(.[0])") else . end) as $_
  | ([.roles | to_entries[] | .key as $k | .value
      | if .candidates then (.candidates | to_entries[] | .value | check_seat("\($k).\(.key)"; $root)) else check_seat($k; $root) end] | length) as $_
  | ([.review // fail("review is missing") | to_entries[] | .key as $k | .value
      | (if type == "array" then .[] elif keys != ["with"] then fail("review.\($k) holds only its substitute seat, with") else .with end)
      | ($root.roles[.role] // fail("review.\($k) names no role \(.role)")) as $r
      | if $r.headless or $r.inherit or $r.candidates then fail("review.\($k) seat \(.role) is not a pane seat") else . end
      | if keys != ["role"] then fail("review.\($k) sets \(keys - ["role"] | .[0]); settings live on the role") else . end] | length) as $_
  | ([.automations // {} | to_entries[] | .key as $k | .value
      | if ($root.roles[.agent].inherit | not) then fail("automations.\($k).agent must name an inherit role") else . end
      | if (.prompt | type) != "string" then fail("automations.\($k).prompt must be text") else . end
      | .judges[] | if ($root.roles[.].headless | not) then fail("automations.\($k) judge \(.) is not a headless role") else . end] | length) as $_
  | $root;
def banner:
  if .agent == "claude" then
    (.model | capture("^claude-(?<n>[a-z]+)-(?<v>[0-9]+(-[0-9]+)*)$") // null) as $c
    | if $c then ($c.n[:1] | ascii_upcase) + $c.n[1:] + " " + ($c.v | gsub("-"; ".")) else .model end
  else .model end;
def family:
  if .agent == "claude" then "claude"
  else ((.model | capture("^gpt-[0-9.]+-(?<f>[a-z]+)$") | .f) // .model) end;
def words($root):
  . as $s
  | {box: (if .headless or .unboxed then [] else [$root.launch.paneBox] end),
     env: ((if .memory then ["COMMANDECK_PANE_MEMMAX=\(.memory)"] else [] end)
       + (if .reviewer then ["COMMANDECK_REVIEWER=1"] else [] end)
       + (if .codexHome then ["CODEX_HOME=\(.codexHome)"] else [] end)
       # Left out, --advisor gives Claude Code its default advisor; this variable is its one off switch (#85).
       + (if .agent == "claude" and (.advisor | not) then ["CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1"] else [] end)
       # Claude has no shell policy flag, so shellEnv rides the environment words; Codex keeps {shellenv}.
       + (if .agent == "claude" and .shellEnv then [.shellEnv | to_entries[] | "\(.key)=\(.value)"] else [] end)),
     model: ["--model", .model + (if .context then "[\(.context)]" else "" end)],
     effort: (if .effort == null then [] elif .agent == "codex" then ["-c", "model_reasoning_effort=\(.effort)"] else ["--effort", .effort] end),
     fast: (if .agent == "codex" then ["-c", "service_tier=" + (if .fast == true then "fast" else "default" end)] elif .fast == true then ["--settings", "{\"fastMode\":true}"] else [] end),
     advisor: (if .advisor then ["--advisor", .advisor] else [] end),
     tools: (if .tools then ["--disallowedTools", (.tools | join(","))] else [] end),
     compact: (if .compactLimit != null then ["-c", "model_auto_compact_token_limit=\(.compactLimit)"] else [] end),
     sandbox: (if .sandbox then ["--sandbox", .sandbox] else [] end),
     approval: (if .approval then ["-a", .approval] else [] end),
     network: (if .network then ["-c", "sandbox_workspace_write.network_access=true"] else [] end),
     shellenv: (if .shellEnv then ["-c", "shell_environment_policy.set={" + (.shellEnv | to_entries | map("\(.key)=\"\(.value)\"") | join(",")) + "}"] else [] end),
     mcp: [(.mcpDisabled // [])[] | "-c", "mcp_servers.\(.).enabled=false"],
     skills: (if .disabledSkills then ["-c", "skills.config=[" + ($root.launch.skillSets[.disabledSkills] | map("{path=\"\(.)\",enabled=false}") | join(",")) + "]"] else [] end),
     plugins: (if .disablePlugins then ["--disable", "plugins"] else [] end),
     projectdoc: (if .projectDocMaxBytes != null then ["-c", "project_doc_max_bytes=\(.projectDocMaxBytes)"] else [] end)} as $w
  | $root.launch.templates[template_of] | split(" ") | map(select(. != "") | if test("^\\{[a-z]+\\}$") then $w[.[1:-1]][] else . end);
def shellword:
  if test("^[A-Za-z0-9_./:@%+=,~-]+$") or test("^\\$HOME[A-Za-z0-9_./:@%+=,-]*$") then .
  elif contains("$HOME") then "\"" + gsub("\""; "\\\"") + "\""
  else ([39] | implode) as $q | $q + . + $q end;
def argword($home):
  gsub("\\$HOME"; $home) | if test("^[A-Za-z_][A-Za-z0-9_]*=~/") then sub("=~/"; "=" + $home + "/") else . end;
def resolve($root; $effort; $model):
  (if $effort != "" then .effort = $effort else . end) | (if $model != "" then .model = $model else . end)
  | check_seat(.role; $root)
  | . + {readonly: ((.sandbox == "read-only") or ((.tools // []) | index("Write") != null)),
         banner: banner, family: family, model: (.model + (if .context then "[\(.context)]" else "" end)), words: words($root)}
  | if .headless then . + {argv: [.words[] | argword($home)]} else . + {cmd: (.words | map(shellword) | join(" "))} end
  | del(.words);
def seat($spec; $effort; $model; $advisor):
  . as $root | seat_at($root; $spec) | (if $advisor == "none" then del(.advisor) else . end) | resolve($root; $effort; $model);
def review($key):
  . as $root
  | def one: seat_at($root; .role) | resolve($root; ""; "") | . + {reviewer: .family};
    (.review[$key] // fail("no review.\($key)"))
  | if type == "array" then map(one) else {with: (.with | one)} end;
'
pp_routing_valid() { # the whole file validates; prints why when it does not
  local cfg; cfg=$(pp_routing)
  [ -f "$cfg" ] || { echo "routing: no config at $cfg" >&2; return 2; }
  jq -e --arg home "$HOME" "$PP_ROUTE_JQ"' validate | true' "$cfg" >/dev/null
}
# pp_codex_proxy -- the proxy Codex's config.toml sends it through: the base URL and the name of the
# env var holding its key (empty for a proxy that signs in by itself, as a Copilot API proxy does),
# tab-separated. Nothing when Codex goes direct. The proxy is the top-level model_provider's base_url.
# Read with tomllib, as setup's requirements already need (Python 3.11): a hand-rolled reader lost key
# and string boundaries (a quoted name with a dot, "base_url =" inside another value). With no tomllib
# nothing is guessed: it says so, and returns 3 with no proxy.
pp_codex_proxy() {
  python3 -c 'import tomllib' 2>/dev/null \
    || { echo "routing: proxy model discovery needs Python 3.11 or newer (tomllib); Codex's config.toml was not read for a proxy" >&2; return 3; }
  python3 -c '
import sys, tomllib
try: c = tomllib.load(open(sys.argv[1], "rb"))
except (OSError, ValueError): sys.exit()
p = (c.get("model_providers") or {}).get(c.get("model_provider"))
u = p.get("base_url") if isinstance(p, dict) else None
if isinstance(u, str) and u:
    k = p.get("env_key")
    print(u + "\t" + (k if isinstance(k, str) else ""))' "${CODEX_HOME:-$HOME/.codex}/config.toml" 2>/dev/null
}
pp_codex_route() { # one plain line for doctor, setup and a refusal
  local px rc=0; px=$(pp_codex_proxy 2>/dev/null) || rc=$?
  if [ "$rc" = 3 ]; then echo "Codex's proxy setting was not read: proxy model discovery needs Python 3.11 or newer"
  elif [ -n "$px" ]; then echo "Codex goes through the proxy ${px%%$'\t'*}"
  else echo "Codex goes direct to its provider (no model_provider with a base_url in ${CODEX_HOME:-$HOME/.codex}/config.toml)"; fi
}
# routing.json names a Codex model by family (sol); Codex takes a model id: the
# newest gpt-<version>-<family> in the account's own list. Behind a proxy that
# list is the proxy's (models_cache.json is then empty or stale), with the
# cache as the fallback. A family neither list carries fails here, before a
# pane opens or a pass starts. A name that is not a bare family is a model id
# and is printed as written. Above both: the model id setup saved for the role
# in the project's own config (setup.sh --codex-model; COMMANDECK_CODEX_MODELS
# is setup's answer before it is saved), which no plugin update replaces.
pp_codex_model() { # <family or model id> [role]
  local list=${CODEX_HOME:-$HOME/.codex}/models_cache.json id= px url key
  local newest='[.[] | select(test("^gpt-[0-9.]+-\($f)$"))] | sort_by(capture("^gpt-(?<v>[0-9.]+)-").v | split(".") | map(tonumber)) | last // empty'
  [ -z "${2:-}" ] || id=$(jq -rn --arg r "$2" --argjson m "${COMMANDECK_CODEX_MODELS:-$(jq -c '.codexModels // {}' "$PP_MAIN/.claude/commandeck.json" 2>/dev/null || echo '{}')}" \
    '$m[$r] // empty | strings' 2>/dev/null)
  [ -z "$id" ] || { printf '%s\n' "$id"; return 0; }
  [[ $1 =~ ^[a-z]+$ ]] || { printf '%s\n' "$1"; return 0; }
  px=$(pp_codex_proxy) || px=
  if [ -n "$px" ]; then
    url=${px%%$'\t'*} key=${px#*$'\t'}
    [[ $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && [ -n "${!key:-}" ] || key=
    # The key goes on stdin, never on the command line, where ps shows it.
    id=$({ [ -z "$key" ] || printf 'Authorization: Bearer %s\n' "${!key}"; } \
      | curl -fsS --max-time 5 ${key:+-H @-} "${url%/}/models" 2>/dev/null | jq -r --arg f "$1" "[.data[]?.id | strings] | $newest" 2>/dev/null || true)
  fi
  [ -n "$id" ] || id=$(jq -r --arg f "$1" "[.models[]?.slug | strings] | $newest" "$list" 2>/dev/null || true)
  if [ -z "$id" ]; then
    local via= or=" Or run codex once while signed in."
    [ -z "$px" ] || { via=", and its model list has none" or=; }
    echo "routing: no gpt-<version>-$1 model for the Codex family $1. $(pp_codex_route)$via; $list lists none either. Name the model id: setup.sh --codex-model ${2:-codex-reviewer}=<model id>.$or" >&2
    return 2
  fi
  printf '%s\n' "$id"
}
# pp_registered -- the dashboard's registry has a line naming this project, both sides through pp_norm.
pp_registered() {
  local q m f=$HOME/.commandeck/dashboard/projects; m=$(pp_norm "$PP_MAIN")
  [ -f "$f" ] || return 1
  while IFS= read -r q; do [ "$(pp_norm "$q")" != "$m" ] || return 0; done < "$f"
  return 1
}
# pp_pane_of <worktree path> -- the live Claude pane in that worktree, found at
# the moment of asking: a pane's handle changes each time its session restarts,
# so a handle saved earlier may name a pane that is gone. Nothing when none is live.
# Live as live_pane_with_title has it: connected and not orphaned.
# shortcut: a review pane is told from the seat by its launch title; one that retitled itself is not, when a pane is a reviewer by more than its title, match that.
pp_pane_of() {
  timeout 10 orca-ide terminal list --json 2>/dev/null | jq -r --arg wt "$1" \
    "$PP_PNORM"'($wt | pnorm) as $wt | first((.result | if type == "array" then . else (.terminals // []) end)[]?
      | select((.worktreePath | pnorm) == $wt and .agentIdentity == "claude" and .connected != false and .orphaned != true)
      | select((.title // "") | test("^(Reviewer|Claude reviewer|Codex reviewer|Luna reviewer|Refuter|Certifier|Judge)\\b") | not) | .handle) // empty' 2>/dev/null
}
# pp_seat_pane <seat key> <worktree> -- the live pane of main (key main) or of a
# Builder (key unit-<unit>): the handle its last session start recorded
# (inbox-drain.sh), when Orca still lists it live in that worktree. Nothing when
# the seat is down. A Builder whose recorded pane is gone, or that no session start
# recorded, has the pane its launch names in its seat record (seat.sh); other
# panes in its worktree (a design co-author) are never taken for it. Only main,
# alone in its checkout, falls back to pp_pane_of, for a session that began before
# the record.
pp_seat_pane() {
  local hs; hs=$(tail -1 "$PP_SCRATCH/handles/$1" 2>/dev/null)
  [ "$1" = main ] || hs="$hs $(sed -n 's/^handle=//p' "$PP_SCRATCH/seat-${1#unit-}-builder.txt" 2>/dev/null | tail -1)"
  [ -n "${hs// /}" ] || { [ "$1" != main ] || pp_pane_of "$2"; return 0; }
  timeout 10 orca-ide terminal list --json 2>/dev/null | jq -r --arg wt "$2" --arg hs "$hs" \
    "$PP_PNORM"'($wt | pnorm) as $wt | [(.result | if type == "array" then . else (.terminals // []) end)[]?
      | select((.worktreePath | pnorm) == $wt and .connected != false and .orphaned != true) | .handle] as $live
      | first($hs | splits(" +") | select(. != "" and IN($live[]))) // empty' 2>/dev/null
}
# pp_worktree_new <name> -- a new Orca worktree of this project at
# $PP_WORKSPACES/<name>, on local main and not Orca's origin/main default. The
# one place a worktree is created: a Builder's (builder-launch.sh) and the
# relay's (setup.sh). Says why not on stderr.
pp_worktree_new() {
  local wt=$PP_WORKSPACES/$1 head
  orca-ide worktree create --repo "path:$PP_MAIN" --name "$1" --base-branch main \
    --parent-worktree "path:$PP_MAIN" --setup run --json >/dev/null \
    || { echo "worktree create failed for $1" >&2; return 1; }
  [ -d "$wt" ] || { echo "worktree create reported success but $wt does not exist" >&2; return 1; }
  head=$(git -C "$PP_MAIN" rev-parse refs/heads/main)
  [ "$(git -C "$wt" rev-parse HEAD)" = "$head" ] || git -C "$wt" reset --hard "$head" >/dev/null \
    || { echo "could not base $1 on local main $head" >&2; return 1; }
}
# pp_sync_main <checkout> [--check] -- fetch origin's main and fast-forward local
# main to it, before a Builder branches or a merge rebases: a release marked
# published on origin and not fetched here gets its files rebuilt as a draft.
# No origin is nothing to fetch. A fetch that fails, or a local main that has
# diverged, refuses with the reason. --check moves nothing (a dry run).
pp_sync_main() {
  local c=$1 got
  git -C "$c" remote get-url origin >/dev/null 2>&1 || return 0
  git -C "$c" fetch -q origin main 2>/dev/null && got=$(git -C "$c" rev-parse -q --verify 'FETCH_HEAD^{commit}') \
    || { echo "could not fetch main from origin; fetch it by hand (git fetch origin main), then run this again" >&2; return 1; }
  git -C "$c" merge-base --is-ancestor "$got" refs/heads/main && return 0
  git -C "$c" merge-base --is-ancestor refs/heads/main "$got" \
    || { echo "local main has diverged from origin's main and cannot fast-forward; reconcile them (git pull --rebase origin main, or push main), then run this again" >&2; return 1; }
  [ "${2:-}" != --check ] || return 0
  if [ "$(git -C "$c" branch --show-current)" = main ]; then
    git -C "$c" merge -q --ff-only "$got" || { echo "could not fast-forward main to origin's $got (uncommitted work in the way?)" >&2; return 1; }
  else
    git -C "$c" update-ref refs/heads/main "$got" || return 1
  fi
}
# Codex fast mode: on only when set-up saved the owner's yes. No config, no answer and an unreadable file are off.
# COMMANDECK_CODEX_FAST=false turns it off for one call and no value of it turns it on: set-up's own
# preflight runs before the new answer is saved, and has checked the tier for that answer itself.
pp_codex_fast() { [ "${COMMANDECK_CODEX_FAST:-}" != false ] && [ "$(jq -r '.codexFast // false' "$PP_MAIN/.claude/commandeck.json" 2>/dev/null)" = true ]; }
# pp_review_loop <key> <default> <regex> -- a review-loop setting setup saved
# in this project's config (reviewLoop.<key>), as the owner typed it, else the
# default. A saved value the regex does not take says so on stderr and fails:
# the file can be edited by hand, and a wrong number must not pass for a setting.
# COMMANDECK_REVIEW_LOOP: setup's own check reads the answers it is about to save, not the old ones.
pp_review_loop() {
  local f=$PP_MAIN/.claude/commandeck.json v src=/dev/stdin o=
  # The owner's /config answer beats the project's (issue 245); setup's own check reads the answers it saves.
  if case $1:${COMMANDECK_REVIEW_LOOP:-} in maxRounds:) o=maxReviewRounds v=$(pp_config_option maxReviewRounds) ;;
       closingPass:) o=closingPass v=$(pp_config_option closingPass) ;; *) false ;; esac; then
    [[ $v =~ $3 ]] || { echo "$o = \"$v\" in /config is not a value it takes; change it with /config" >&2; return 1; }
    echo "$v"; return 0
  fi
  # Setup's answers come in on stdin: a <(...) file is closed before the next line could read it.
  [ -n "${COMMANDECK_REVIEW_LOOP:-}" ] || { [ -e "$f" ] || { echo "$2"; return 0; }; src=$f; }
  # No config is the defaults; one that cannot be read is no setting, and says so.
  v=$(jq -r --arg k "$1" '.reviewLoop | if . == null then {} elif type == "object" then . else error("reviewLoop is not an object") end
    | .[$k] | if . == null then empty else tostring end' "$src" 2>&1 <<<"{\"reviewLoop\": ${COMMANDECK_REVIEW_LOOP:-}}") \
    || { echo "$f: reviewLoop.$1 cannot be read ($v); answer it again with /commandeck:setup" >&2; return 1; }
  [ -n "$v" ] || { echo "$2"; return 0; }
  [[ $v =~ $3 ]] || { echo "$PP_MAIN/.claude/commandeck.json has reviewLoop.$1 = \"$v\", which is not a value it takes; answer it again with /commandeck:setup" >&2; return 1; }
  echo "$v"
}
# Issue 245: the settings that are the same in every project are also the plugin's options (userConfig in
# .claude-plugin/plugin.json), set in /config. The owner's /config answer beats the project's saved one. It is read
# from the user's settings file, not CLAUDE_PLUGIN_OPTION_*: that reaches hooks only, and may carry the manifest's
# default, which would hide the project's answer.
# PP_OPTS_KEY -- jq's key: the commandeck@<marketplace> the plugin is enabled under, else one with options that is not
# disabled; a disabled install's leftover options are not the running plugin's.
PP_OPTS_KEY='def key: . as $s | first(((.enabledPlugins // {}) | to_entries[] | select(.value == true) | .key),
  ((.pluginConfigs // {}) | keys[] | select(($s.enabledPlugins // {})[.] != false)), ((.enabledPlugins // {}) | keys[])
  | select(startswith("commandeck@"))) // "commandeck@commandeck";'
# pp_config_option <key> -- the /config answer in the form the project's file saves it; fails when there is none.
pp_config_option() {
  jq -er --arg k "$1" "$PP_OPTS_KEY"' .pluginConfigs[key].options[$k]? | select(. != null)
    | if $k == "closingPass" then (if . then "yes" else "no" end) else tostring end' \
    "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" 2>/dev/null
}
# pp_option <key> [source] -- the value a reader takes: the /config answer, else the project's saved one (the
# dashboard's: this machine's), else what the reader took before 0.22.0. With "source", where that value is from.
pp_option() {
  local f=$PP_MAIN/.claude/commandeck.json p d= v src=/config
  case $1 in
    builderModel) p=.builder.model ;; builderEffort) p=.builder.effort ;; maxBuilders) p=.builder.maxBuilders ;;
    maxReviewRounds) p=.reviewLoop.maxRounds ;; closingPass) p=.reviewLoop.closingPass d=yes ;;
    fullSuiteBeforeFinal) p=.fullSuiteBeforeFinal d=false ;; ponytail) p=.ponytail d=false ;;
    promptCacheTtl) p=.cacheTtl ;; relayPromptCacheTtl) p=.chiefOfStaff.cacheTtl ;;
    dashboardBind) p=.dashboard.bind f=$HOME/.commandeck/install/_machine.json ;;
    dashboardPort) p=.dashboard.port f=$HOME/.commandeck/install/_machine.json ;;
    *) echo "pp_option: no option $1" >&2; return 2 ;;
  esac
  if ! v=$(pp_config_option "$1"); then
    src=$f v=$(jq -r "$p | if . == null then empty else tostring end" "$f" 2>/dev/null) || v=
    [ -n "$v" ] || src=default v=$d
  fi
  if [ "${2:-}" = source ]; then echo "$src"; else echo "$v"; fi
}
# pp_issue_sizing -- setup's issue sizing line (issueSizing: tokens, or off), default 40000. A saved value it does
# not take fails, naming the key, as pp_review_loop does.
pp_issue_sizing() {
  local v; v=$(jq -r '.issueSizing // 40000' "$PP_MAIN/.claude/commandeck.json" 2>/dev/null) || v=40000
  [[ $v =~ ^(off|[1-9][0-9]*)$ ]] || { echo "$PP_MAIN/.claude/commandeck.json has issueSizing = \"$v\", which is not a value it takes; answer it again with /commandeck:setup" >&2; return 1; }
  echo "$v"
}
# The tier is the Codex home's own setting: a pass runs on what its config says. Read with tomllib, as
# pp_codex_proxy is: the default profile's service_tier over the top-level one, the key in any TOML spelling.
pp_codex_fast_home() {
  python3 -c 'import tomllib' 2>/dev/null \
    || { echo "Codex fast mode needs Python 3.11 or newer (tomllib) to read Codex's config.toml" >&2; return 1; }
  python3 -c '
import sys, tomllib
try: c = tomllib.load(open(sys.argv[1], "rb"))
except (OSError, ValueError): sys.exit(1)
p = (c.get("profiles") or {}).get(c.get("profile"))
sys.exit((p if isinstance(p, dict) and "service_tier" in p else c).get("service_tier") != "fast")' "${CODEX_HOME:-$HOME/.codex}/config.toml" 2>/dev/null
}
pp_route_json() { # <role>[.<candidate>] [effort] [model] [none: this launch has no advisor] -- the resolved seat, as JSON
  local cfg m=${3:-} b pf d; cfg=$(pp_routing)
  [ -f "$cfg" ] || { echo "routing: no config at $cfg" >&2; return 2; }
  b=$(jq -c '.builder // {}' "$PP_MAIN/.claude/commandeck.json" 2>/dev/null) && [ -n "$b" ] || b='{}'
  b=$(jq -c --arg m "$(pp_config_option builderModel)" --arg e "$(pp_config_option builderEffort)" \
    '. + ({model: $m, effort: $e} | with_entries(select(.value != "")))' <<<"$b" 2>/dev/null || echo "$b")
  pf=$(jq -c '.planFast // []' "$PP_MAIN/.claude/commandeck.json" 2>/dev/null) && [ -n "$pf" ] || pf='[]'
  # Every Codex role's model goes through the resolver, one handed in (a plan seat's pick) too. The project's saved
  # id is for the role's own model: it beats that family and an id alike, never another family picked for the seat.
  d=$(jq -r --arg r "${1%%.*}" '.roles[$r] | select(.agent == "codex") | .model // empty' "$cfg" 2>/dev/null || true)
  if [ -n "$d" ]; then
    if [ -z "$m" ] || [ "$m" = "$d" ]; then m=$(pp_codex_model "$d" "${1%%.*}") || return 2
    else m=$(pp_codex_model "$m") || return 2; fi
  fi
  jq -ce --arg spec "$1" --arg effort "${2:-}" --arg model "$m" --arg advisor "${4:-}" --arg home "$HOME" --argjson builder "$b" --argjson planFast "$pf" --argjson codexFast "$(pp_codex_fast && echo true || echo false)" "$PP_ROUTE_JQ"' validate | seat($spec; $effort; $model; $advisor)' "$cfg"
}
# The model one Builder launch may run: an alias routing.json already names, the
# check set-up makes for --builder-model. builder-launch.sh asks before it
# creates anything and seat.sh asks again, so a seat launched by hand is held to it.
pp_builder_model_ok() { # <alias> -- says why not
  jq -e --arg a "$1" "$PP_ROUTE_JQ"' aliases | any(. == $a)' "$(pp_routing)" >/dev/null 2>&1 \
    || { echo "REFUSED: --model ${1:-(none)} is not one of $(jq -r "$PP_ROUTE_JQ"' aliases | join(", ")' "$(pp_routing)" 2>/dev/null)" >&2; return 2; }
}
# The model a plan seat may be launched on: one routing.json already names for a seat of the same agent, so a Codex
# judge is never handed a Claude model.
pp_seat_model_ok() { # <role> <alias> -- says why not
  local ok; ok=$(jq -r --arg r "$1" '.roles[$r].agent as $a | [.roles[] | (.candidates // [.])[] | select(.agent == $a) | .model, .advisor | strings] | unique | join(", ")' "$(pp_routing)") || return 2
  [[ -n $2 && ", $ok, " == *", $2, "* ]] || { echo "REFUSED: --model $2 is not one of $ok" >&2; return 2; }
}
# pp_plan_models -- the models a plan seat may run on, space-separated: setup's planModels (owner's ruling
# 2026-10-17), or with none saved every model routing.json gives a seat, Codex's only on the Claude+OpenAI profile.
pp_plan_models() {
  local saved; saved=$(jq -r '.planModels // empty | join(" ")' "$PP_MAIN/.claude/commandeck.json" 2>/dev/null) || saved=
  [ -z "$saved" ] || { echo "$saved"; return 0; }
  jq -r --arg p "$(pp_pass)" '[.roles[] | (.candidates // [.])[] | select(.agent == "claude" or $p == "codex") | .model] | unique | join(" ")' "$(pp_routing)"
}
# pp_plan_seat <role> -- "<role> <model>": the plan seat on its own model when setup allows it, else on the first
# allowed model of its agent, else, for a Codex judge with no Codex model allowed, plan-judge-claude. Says on stderr
# which model or seat it used instead.
pp_plan_seat() {
  local r=$1 ok a m alt; ok=" $(pp_plan_models) "
  a=$(jq -r --arg r "$r" '.roles[$r].agent // empty' "$(pp_routing)") m=$(jq -r --arg r "$r" '.roles[$r].model // empty' "$(pp_routing)")
  [ -n "$a" ] || { echo "routing: no role $r" >&2; return 2; }
  if [[ $ok != *" $m "* ]]; then
    alt=$(jq -r --arg a "$a" --arg ok "$ok" '[.roles[] | (.candidates // [.])[] | select(.agent == $a) | .model] as $mine
      | first($ok | split(" ")[] | select(. != "" and IN($mine[]))) // empty' "$(pp_routing)")
    if [ -n "$alt" ]; then echo "$r: $m is not one of the models this project allows (setup's planModels:$ok); used $alt instead" >&2; m=$alt
    elif [ "$a" = codex ]; then echo "$r: no Codex model is allowed in this project; used plan-judge-claude instead" >&2; pp_plan_seat plan-judge-claude; return
    else echo "REFUSED: no model this project allows can run $r (setup's planModels:$ok)" >&2; return 2; fi
  fi
  echo "$r $m"
}
# The effort one Builder launch may run: medium or high, never under the project's Builder default. Asked the
# same two places as the model, so a seat launched by hand cannot lower it either.
pp_builder_effort_ok() { # <level> <the Builder's default effort, or none> -- says why not
  [[ $1 == medium || $1 == high ]] || { echo "REFUSED: --effort takes medium or high ('$1' given): main may raise a Builder, never lower it" >&2; return 2; }
  # A default that is no level (none) indexes to null, which every level is at or above.
  jq -ne --arg e "$1" --arg d "$2" "$PP_ROUTE_JQ"' efforts | index($e) >= index($d)' >/dev/null \
    || { echo "REFUSED: --effort $1 is below this project's Builder default $2; a launch may only raise it" >&2; return 2; }
}
pp_route() { # same arguments; sets RT_AGENT RT_MODEL RT_EFFORT RT_READONLY RT_BANNER RT_FAMILY RT_CMD
  local json f
  json=$(pp_route_json "$@") || return 2
  mapfile -t f < <(jq -r '.agent, .model, (.effort // ""), (if .readonly then 1 else 0 end), .banner, .family, (.cmd // "")' <<<"$json")
  RT_AGENT=${f[0]} RT_MODEL=${f[1]} RT_EFFORT=${f[2]} RT_READONLY=${f[3]} RT_BANNER=${f[4]} RT_FAMILY=${f[5]} RT_CMD=${f[6]}
}
pp_review() { # <review key> -- its resolved seats as a JSON array, each with .reviewer (its family)
  local cfg; cfg=$(pp_routing)
  [ -f "$cfg" ] || { echo "routing: no config at $cfg" >&2; return 2; }
  jq -ce --arg key "$1" --arg home "$HOME" --argjson codexFast "$(pp_codex_fast && echo true || echo false)" "$PP_ROUTE_JQ"' validate | review($key)' "$cfg"
}
# The review pass of the configured profile: claude for the Claude-only profile,
# codex for Claude+OpenAI, which is also what a file with no profile means.
# pp_unit_briefs <briefs dir> <unit> -- the unit's own files there, one a line:
# its brief, evidence, design note, main's rulings, round files and later-cut briefs. Never
# "$unit"*.md: unit "pre" would then own the briefs of "prefab" and "pre-other".
pp_unit_briefs() {
  local f b
  for f in "$1/$2".md "$1/$2"-*.md; do
    [ -e "$f" ] || continue
    b=${f##*/}; b=${b#"$2"}
    [[ $b =~ ^(\.md|-evidence\.md|-design(-spec)?\.md|-main-rulings\.md|-review-cap\.md|-r[0-9a-z]+-reports\.md|-cut[0-9][^/]*\.md)$ ]] && printf '%s\n' "$f"
  done
  return 0
}
# pp_builder_lock <unit> -- one Builder launch of a unit at a time, held until this process exits: builder-launch.sh
# rewrites a risky unit's records before seat.sh opens the pane, so a seat.sh run by hand takes the same lock.
# Taken once per process: builder-launch.sh execs seat.sh with it held, and a second flock on a new open would wait on itself.
pp_builder_lock() {
  [ "${PP_BUILDER_LOCKED:-}" != "$1" ] || return 0
  mkdir -p "$PP_SCRATCH" && exec {PP_BUILDER_LOCK_FD}>>"$PP_SCRATCH/$1-builder-launch.lock" && flock -w 600 "$PP_BUILDER_LOCK_FD" \
    || { echo "cannot lock $PP_SCRATCH/$1-builder-launch.lock; the Builder was not launched" >&2; return 1; }
  export PP_BUILDER_LOCKED=$1
}
# pp_unit_name <unit> -- pp_unit_briefs tells a unit's papers by name alone, so
# no unit may be named like one: `u-evidence` would lose its brief to `u`.
# Refuses with the rule and the part of the name it hit.
pp_unit_name() {
  [[ $1 =~ (-evidence|-design(-spec)?|-main-rulings|-review-cap|-r[0-9a-z]+-reports)$|(-cut[0-9]+) ]] || return 0
  echo "unit $1 may not be named like a paper (it has ${BASH_REMATCH[1]:-${BASH_REMATCH[3]}}): a name ending in -evidence, -design, -design-spec, -main-rulings, -review-cap or -r<N>-reports, or holding -cut<N>, is how another unit's brief files are told from its own. Pick another name" >&2
  return 1
}
# The project's own profile, which setup writes, wins over the plugin's default.
pp_pass() {
  local p
  p=$(jq -r '.profile // empty' "$PP_MAIN/.claude/commandeck.json" 2>/dev/null) || p=
  [ -n "$p" ] || p=$(jq -r '.profile // empty' "$(pp_routing)")
  [ "$p" = claude ] && echo claude || echo codex
}
pp_argv() { # <headless role> [effort] -- its command, one argv word per line
  local json
  json=$(pp_route_json "$1" "${2:-}") || return 2
  jq -er '.argv // error("routing: \(.role) is not a headless role") | .[]' <<<"$json"
}

# The one reading of a finding's severity, shared by close-round.sh (each raw
# reviewer report) and review-round.sh (a round's combined reports file, whose
# finding lines close-round.sh prefixes with an id). Here because both already
# source this file, and every test that stages them copies it.
#
# EVERY P0-P2 A REVIEWER FILES STANDS AT ITS STATED SEVERITY. No
# reviewer test runs at close, and a passing one never withdraws its finding:
# the fixer runs each test red from the packet. Prints the lowest severity
# filed, or 9 when the report carries no finding at all.
#
# A second argument picks a count instead: `count` is every finding line,
# resolved ones included, so a refusal (no finding at all) is told apart from a
# GO that resolved its findings; `standing` is the P0-P2 ones that stand (not
# resolved, not pre-existing); `pre` is the [PRE-EXISTING] ones; `unowned` is
# the fenced test blocks no parsed finding owns -- a finding in a shape the
# parser missed. A fence is read as refute.sh reads it.
#
# ONE FENCE RULE FOR EVERY READER OF A REVIEWER REPORT.
# surviving_severity below, close-round.sh's stable ids and read-verdict.sh's
# verdict line all put this ahead of their awk program, so no two of them can
# disagree about what is fixture text. A fence opens on a line of three or more
# backticks or tildes, indented or not, and closes only on a line of the same
# character, at least as long, with nothing after it -- so a longer outer fence
# holds shorter delimiter text without closing. fence(line) returns 1 when the
# line opens a fence, 2 when it closes one and 0 otherwise; flen is non-zero
# while inside one.
PP_AWK_FENCE='
  function fence(line,   run, ch) {
    if (!match(line, /^[[:space:]]*(```+|~~~+)/)) return 0
    run = substr(line, RSTART, RLENGTH); sub(/^[[:space:]]*/, "", run); ch = substr(run, 1, 1)
    if (!flen) { fch = ch; flen = length(run); return 1 }
    if (ch == fch && length(run) >= flen && substr(line, RSTART + RLENGTH) ~ /^[[:space:]]*$/) { flen = 0; return 2 }
    return 0
  }'
surviving_severity() {  # <reviewer report> [count|standing|pre|unowned|unpatched]
  # Two passes: the first records every verdict line, so a finding can be read
  # against the verdict of its own report.
  # One finding-id pattern for the finding regex and own_go(), so the shapes
  # the one accepts are the shapes the other can judge by their own verdict.
  # The seat segment is any reviewer family, so a report from a family no
  # longer configured still reads the same.
  awk -v mode="${2:-}" -v fid='[A-Za-z0-9._-]+-r[0-9]+-[a-z]+-[0-9]+' "$PP_AWK_FENCE"'
    BEGIN {
      worst = 9
      lead = "^[[:space:]]*(([0-9]+\\.|[-*])[[:space:]]*)?(#+[[:space:]]*)?(\\*\\*)?"
      idline = lead fid "[^[:alnum:]]"
      finding = "^[[:space:]]*(" fid "[[:space:]]+)?(([0-9]+\\.|[-*])[[:space:]]*)?(#+[[:space:]]*)?(\\*\\*)?(" fid "[^[:alnum:]]{0,8})?(\\[PRE-EXISTING\\][[:space:]]*)?\\[?P[0-3]\\]?([[:space:]]|-|:|\\*)"
    }
    NR == FNR {
      f = fence($0)   # a verdict in a fenced test is fixture text
      if (!f && !flen && $0 ~ /^[[:space:]]*VERDICT:[[:space:]]*(GO|NO-GO)[[:space:]]*$/) { nv++; vline[nv] = FNR; vgo[nv] = ($0 !~ /NO-GO/) }
      next
    }
    FNR == 1 { report_go = nv ? vgo[nv] : 0; flen = 0 }
    { f = fence($0) }
    # A single report is judged by its last verdict. In the combined file every
    # report ends on its own verdict, so a line carrying a finding id -- the
    # close-round.sh prefix or the id a reviewer wrote first -- is judged by the
    # first verdict after it, never a later reviewer.
    function own_go(   i) {
      if ($0 !~ idline) return report_go
      for (i = 1; i <= nv; i++) if (vline[i] > FNR) return vgo[i]
      return report_go
    }
    function close_finding() {
      if (open && sev < worst) worst = sev
      if (open && sev <= 2) { standing++; if (!patched) unpatched++ }
      open = 0
    }
    # A finding line in every shape the reviewers write: "- [P1]", "1. **[P1]",
    # "**P1 --", "### P2 --", "### P2-1 --", and the shape where the reviewer
    # writes the finding id itself first: "**<unit>-r2-claude-1 -- [P2] ...".
    # The id segment is optional but must be id-shaped, so prose that mentions a
    # level mid-sentence ("confirmed the P2") never starts a line this way. The
    # leading "<unit>-r2-sol-1 " is the id close-round.sh gives each finding line
    # in the combined file, ahead of any of those shapes.
    # No mode reads a finding line inside a fence: that is a fixture in a
    # reviewer test. Counted, it raised the worst severity and the standing
    # count, closed the real finding before its diff, and owned a test that an
    # unparsed finding should have left unowned.
    $0 ~ finding && !f && !flen {
      close_finding(); found++; preopen = 0; resolved = 0; patched = 0
      # A [PRE-EXISTING] finding is for main to file and never gates the unit;
      # its fences belong to nothing that blocks.
      if ($0 ~ /\[PRE-EXISTING\]/) { pre++; preopen = 1; next }
      # A GO report can describe findings it resolved while reviewing. Those
      # are history, not work that survived the round. NO-GO keeps every line.
      # The last field is the exact failing command, which may hold any word.
      lower = tolower($0)
      if (split(lower, fields, " -- ") >= 4) lower = fields[1] " " fields[2] " " fields[3]
      if (own_go() && lower ~ /(^|[^[:alpha:]])(fixed|closed|resolved|refuted|no longer)([^[:alpha:]]|$)/) { resolved = 1; next }
      match($0, /P[0-3]/); sev = substr($0, RSTART + 1, 1) + 0
      open = 1; next
    }
    # A [PRE-EXISTING] or resolved finding owns only the fences right after it:
    # the first prose line outside a fence is some other finding the parser
    # missed, and its fence must stay unowned so the round fails closed.
    # A finding owns a patch when a finder diff (the apply-patch.sh block shape)
    # follows its line; unpatched counts the standing ones without one.
    # Only a line that OPENS a fence is a patch or a test: the same text inside
    # an outer fence is a sample in a fixture.
    open && f == 1 && /^[[:space:]]*```diff path=/ { patched = 1 }
    (preopen || resolved) && !f && !flen && NF { preopen = 0; resolved = 0 }
    f == 1 && !/^[[:space:]]*(```+|~~~+)diff/ && !(open || preopen || resolved) {   # a diff fence is a fix, never a test
      t = $0; sub(/^[[:space:]]*(```+|~~~+)/, "", t); sub(/^[a-zA-Z]*[[:space:]]+/, "", t); sub(/^path=/, "", t)
      if (t ~ /\//) unowned++
    }
    END {
      close_finding()
      print (mode == "count" ? found + 0 : mode == "standing" ? standing + 0 : mode == "pre" ? pre + 0 : mode == "unowned" ? unowned + 0 : mode == "unpatched" ? unpatched + 0 : worst)
    }
  ' "$1" "$1"
}

# pp_link_node_modules <main checkout> <other checkout> -- link main's
# node_modules (gitignored, so a new checkout has none) into the other one.
pp_link_node_modules() {
  local d
  for d in "" web infra; do
    # Nothing to share in a repo that has none; a link to nothing breaks tools that follow it.
    [ -d "$1/$d/node_modules" ] && [ -d "$2/$d" ] || continue
    [ -e "$2/$d/node_modules" ] || ln -sfn "$1/$d/node_modules" "$2/$d/node_modules"
  done
}

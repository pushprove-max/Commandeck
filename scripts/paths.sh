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

# Mac preflight. The scripts use GNU sed -i, stat -c, date -d, readlink -f,
# grep -P, flock and timeout, and Bash 4+ syntax; the Mac's /bin/bash 3.2 and
# BSD tools break or silently answer differently. Homebrew supplies them, and
# its bin plus the gnubin directories must lead PATH (a LaunchAgent sets that
# PATH itself). Anything missing stops the caller here, before any work.
# A zsh login shell runs path_helper, which puts /usr/bin and /bin ahead of the
# gnubin directories, so those Homebrew directories are moved in front of the
# first system one first; entries already ahead (a test stub, nvm) keep their
# place. COMMANDECK_BREW_PREFIX relocates Homebrew for the self-test.
if [ "$(uname -s)" = Darwin ]; then
  pp_gnu=()
  for pp_t in "${COMMANDECK_BREW_PREFIX:-/opt/homebrew}"/opt/*/libexec/gnubin "${COMMANDECK_BREW_PREFIX:-/opt/homebrew}/bin"; do
    [ -d "$pp_t" ] && pp_gnu+=("$pp_t")
  done
  pp_path=: pp_added=
  IFS=: read -ra pp_dirs <<<"$PATH"
  # The trailing newline entry is an end marker: no system directory at all
  # still gets the Homebrew ones, appended.
  for pp_t in "${pp_dirs[@]}" $'\n'; do
    if [ -z "$pp_added" ] && { [ "$pp_t" = /usr/bin ] || [ "$pp_t" = /bin ] || [ "$pp_t" = $'\n' ]; }; then
      pp_added=1
      for pp_g in ${pp_gnu[@]+"${pp_gnu[@]}"}; do
        case $pp_path in *":$pp_g:"*) ;; *) pp_path="$pp_path$pp_g:" ;; esac
      done
    fi
    [ "$pp_t" != $'\n' ] || continue
    case $pp_path in *":$pp_t:"*) ;; *) pp_path="$pp_path$pp_t:" ;; esac
  done
  pp_path=${pp_path#:}; PATH=${pp_path%:}; export PATH
  unset pp_gnu pp_path pp_added pp_dirs pp_g
  pp_missing=
  [ "${BASH_VERSINFO[0]}" -ge 4 ] || pp_missing=" bash-4+ (running $BASH $BASH_VERSION)"
  for pp_t in gsed gstat gdate greadlink ggrep flock timeout; do
    command -v "$pp_t" >/dev/null 2>&1 || pp_missing="$pp_missing $pp_t"
  done
  for pp_t in sed stat date readlink grep; do
    grep -q GNU <<<"$("$pp_t" --version 2>/dev/null)" || pp_missing="$pp_missing GNU-$pp_t-first-on-PATH"
  done
  if [ -n "$pp_missing" ]; then
    echo "paths.sh: Mac preflight failed, missing:$pp_missing. Put /opt/homebrew/bin and the Homebrew gnubin directories first on PATH." >&2
    return 1
  fi
  unset pp_missing pp_t
fi

. "$(dirname "${BASH_SOURCE[0]}")/project-main.sh"
pp_main_resolve || { echo "paths.sh: no project here: neither ${CLAUDE_PROJECT_DIR:-(no CLAUDE_PROJECT_DIR)} nor $PWD is a git checkout; run it in the project, or set COMMANDECK_MAIN" >&2
  return 1; }
PP_MAIN_SLUG=$(pp_slug "$PP_MAIN")
PP_WORKSPACES_SLUG=$(pp_slug "$PP_WORKSPACES")
PP_SCRATCH=${COMMANDECK_SCRATCH:-$HOME/.commandeck/scratch/$PP_MAIN_SLUG}
# The Orca run this project's orchestrator is bound to; board.sh is its one
# writer. Never Orca's ~/.config/orca/current-run: every project on the machine
# shares that file. hooks/lib/project.sh pp_run_file spells the same path.
PP_RUN_FILE=$PP_SCRATCH/current-run
export PP_MAIN PP_WORKSPACES PP_MAIN_SLUG PP_WORKSPACES_SLUG PP_SCRATCH
PP_SCRIPTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# The same path as one shell word, for a command that is printed to be run.
PP_SCRIPTS_Q=$(printf '%q' "$PP_SCRIPTS")

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

# pp_waited_on <handle> [now] [turn text] -- a `seat.sh wait` watches this pane:
# it is still waiting (its pid, line 1 of $PP_SCRATCH/waiting-<handle>), or under
# pp_session_log <worktree> -- the worktree's newest Claude session record, or nothing.
# pp_session_log_at <worktree> -- the epoch that record was last written, or null: a seat in one long model
# turn writes it while its event log shows nothing, so the dashboard and main-watch.sh both read it.
pp_session_log() { ls -t "$HOME/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$1")"/*.jsonl 2>/dev/null | head -1; }
pp_session_log_at() {
  local f
  f=$(pp_session_log "$1")
  [ -n "$f" ] && stat -c %Y "$f" 2>/dev/null || echo null
}

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
  # A project may choose the model and advisor of its Builder (set-up stores it,
  # pp_route_json hands it in). The one place it applies, and only to this role.
  | if $p.r != "builder" then . else
      . + ($ARGS.named.builder // {} | {model, advisor} | with_entries(select(.value != null)
        | if (.value | IN($root | aliases[])) or (.key == "advisor" and .value == "none") then . else fail("this project has builder.\(.key) is not one of \($root | aliases | join(", ")); set-up sets it") end))
      # "none" is the choice of no advisor, dropped only after it has replaced the one routing names.
      | if .advisor == "none" then del(.advisor) else . end
    end;
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
       # Claude has no shell policy flag, so shellEnv rides the environment words; Codex keeps {shellenv}.
       + (if .agent == "claude" and .shellEnv then [.shellEnv | to_entries[] | "\(.key)=\(.value)"] else [] end)),
     model: ["--model", .model + (if .context then "[\(.context)]" else "" end)],
     effort: (if .effort == null then [] elif .agent == "codex" then ["-c", "model_reasoning_effort=\(.effort)"] else ["--effort", .effort] end),
     fast: (if .fast != true then [] elif .agent == "codex" then ["-c", "service_tier=fast"] else ["--settings", "{\"fastMode\":true}"] end),
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
# routing.json names a Codex model by family (sol); Codex takes a model id: the
# newest gpt-<version>-<family> in the account's own list. A family the list
# does not carry fails here, before a pane opens or a pass starts. A name that
# is not a bare family is a model id and is printed as written.
pp_codex_model() { # <family or model id>
  [[ $1 =~ ^[a-z]+$ ]] || { printf '%s\n' "$1"; return 0; }
  local list=${CODEX_HOME:-$HOME/.codex}/models_cache.json id
  id=$(jq -r --arg f "$1" '[.models[].slug | select(test("^gpt-[0-9.]+-\($f)$"))]
    | sort_by(capture("^gpt-(?<v>[0-9.]+)-").v | split(".") | map(tonumber)) | last // empty' "$list" 2>/dev/null || true)
  [ -n "$id" ] || { echo "routing: $list lists no gpt-<version>-$1 model for the Codex family $1; run codex once while signed in, or name a model id in routing.json" >&2; return 2; }
  printf '%s\n' "$id"
}
pp_route_json() { # <role>[.<candidate>] [effort] [model] [none: this launch has no advisor] -- the resolved seat, as JSON
  local cfg m=${3:-} b; cfg=$(pp_routing)
  [ -f "$cfg" ] || { echo "routing: no config at $cfg" >&2; return 2; }
  b=$(jq -c '.builder // {}' "$PP_MAIN/.claude/commandeck.json" 2>/dev/null) && [ -n "$b" ] || b='{}'
  if [ -z "$m" ]; then
    m=$(jq -r --arg r "${1%%.*}" '.roles[$r] | select(.agent == "codex") | .model // empty | select(test("^[a-z]+$"))' "$cfg" 2>/dev/null || true)
    [ -z "$m" ] || m=$(pp_codex_model "$m") || return 2
  fi
  jq -ce --arg spec "$1" --arg effort "${2:-}" --arg model "$m" --arg advisor "${4:-}" --arg home "$HOME" --argjson builder "$b" "$PP_ROUTE_JQ"' validate | seat($spec; $effort; $model; $advisor)' "$cfg"
}
# The model one Builder launch may run: an alias routing.json already names, the
# check set-up makes for --builder-model. builder-launch.sh asks before it
# creates anything and seat.sh asks again, so a seat launched by hand is held to it.
pp_builder_model_ok() { # <alias> -- says why not
  jq -e --arg a "$1" "$PP_ROUTE_JQ"' aliases | any(. == $a)' "$(pp_routing)" >/dev/null 2>&1 \
    || { echo "REFUSED: --model ${1:-(none)} is not one of $(jq -r "$PP_ROUTE_JQ"' aliases | join(", ")' "$(pp_routing)" 2>/dev/null)" >&2; return 2; }
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
  jq -ce --arg key "$1" --arg home "$HOME" "$PP_ROUTE_JQ"' validate | review($key)' "$cfg"
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
    [[ $b =~ ^(\.md|-evidence\.md|-design(-spec)?\.md|-main-rulings\.md|-r[0-9a-z]+-reports\.md|-cut[0-9][^/]*\.md)$ ]] && printf '%s\n' "$f"
  done
  return 0
}
# pp_unit_name <unit> -- pp_unit_briefs tells a unit's papers by name alone, so
# no unit may be named like one: `u-evidence` would lose its brief to `u`.
# Refuses with the rule and the part of the name it hit.
pp_unit_name() {
  [[ $1 =~ (-evidence|-design(-spec)?|-main-rulings|-r[0-9a-z]+-reports)$|(-cut[0-9]+) ]] || return 0
  echo "unit $1 may not be named like a paper (it has ${BASH_REMATCH[1]:-${BASH_REMATCH[3]}}): a name ending in -evidence, -design, -design-spec, -main-rulings or -r<N>-reports, or holding -cut<N>, is how another unit's brief files are told from its own. Pick another name" >&2
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

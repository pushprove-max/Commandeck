#!/usr/bin/env bash
# setup.sh --profile claude|claude-openai [--scope project|machine]
#          [--name <n>] [--persona <text>] [--strict|--no-strict]
#          [--serena|--no-serena] [--standard-context|--no-standard-context]
#          [--test-command <cmd>] [--bind <address>] [--port <n>] [--dashboard|--no-dashboard]
#          [--hosts <name>[,<name>...]] [--status-line <command>]
#          [--builder-model <alias>] [--builder-advisor <alias>|none] [--codex-fast|--no-codex-fast]
#          [--install-missing]
# Sets the project this runs in up for the plugin. It asks nothing: the setup
# skill asks the owner once and passes every answer here. A second run changes
# the answers given and keeps the rest; update.sh is this script with none.
#
# Requirements (requirements.sh) are checked before all else, and all
# at once. Setup installs nothing by itself: --install-missing is the owner's
# yes, and runs the commands the check printed, word for word, and no other.
#
# Order, and why: the preflight refuses before anything is touched; then the
# install manifest (install-lib.sh) records every path about to change, so a
# setup that dies half way can still be undone by uninstall.sh; then the
# changes. --scope says where the permission rules go: the project's own
# .claude/settings.json, or ~/.claude/settings.json for every project.
# The add-ons are printed as commands for the owner to run (config/addons.tsv);
# the one setup installs is the ponytail skill. A status line is set only when
# one is given, and the one before it is recorded for uninstall.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# Ahead of paths.sh, which on a Mac refuses to load without the tools this
# check offers to install; and down to that load in Bash 3.2's syntax, for a
# Mac that has no newer Bash yet.
. "$HERE/requirements.sh"
# A value is never read as a flag: `--name --install-missing` names the relay, and is no yes.
# The options that take a value are the ones the loop below lists.
INSTALL= ASKED= OPT=
for a; do
  if [ -n "$OPT" ]; then [ "$OPT" != --profile ] || ASKED=$a; OPT=; continue; fi
  case $a in
    --profile|--scope|--name|--persona|--test-command|--bind|--port|--hosts|--status-line|--builder-model|--builder-advisor) OPT=$a ;;
    --install-missing) INSTALL=1 ;;
  esac
done
# need <profile> -- stop unless every requirement is met. With the owner's yes,
# what can be installed is, once, and the list is read again.
need() {
  req_check setup "$1" && return 0
  if [ -n "$INSTALL" ] && [ -n "$REQ_NAMES" ]; then
    INSTALL=
    echo "setup: installing $REQ_NAMES"
    req_install
    # What was installed may be Homebrew's GNU folders, new on PATH, or Bash itself.
    req_path; req_restart
    req_check setup "$1" && return 0
    { echo "setup: still missing after the install; nothing else was changed."; req_report; } >&2
    exit 1
  fi
  { echo "setup: requirements are missing; nothing was changed."; req_report; } >&2
  exit 1
}
need "$ASKED"
. "$HERE/paths.sh"
. "$HERE/host-services.sh"
. "$HERE/install-lib.sh"
die() { echo "setup: $*" >&2; exit 1; }
usage() { sed -n '2,8p' "$0" | sed 's/^# \{0,9\}//' >&2; exit 2; }
# `false` is a stored answer: `// empty` would drop it and the default would come back.
old() { jq -r "$1 | if . == null then empty else . end" "$IL_CONFIG" 2>/dev/null || true; }

if [ -e "$IL_CONFIG" ]; then
  V=$(old .version)
  [ "$V" = "$IL_VERSION" ] || die "$IL_CONFIG is config version ${V:-(none)}, and this plugin knows version $IL_VERSION only. It does not migrate a config: uninstall with the plugin version that wrote it, or correct the file by hand."
fi
PROFILE=$(old .profile) NAME=$(old .chiefOfStaff.name) PERSONA=$(old .chiefOfStaff.persona) TEST=$(old .testCommand)
STRICT=$(old .strictHooks) STANDARD=$(old .standardContext) SERENA=$(old .serena)
BMODEL=$(old .builder.model) BADVISOR=$(old .builder.advisor) FAST=$(old .codexFast)
SCOPE=$(jq -r '.scope // empty' "$IL_PROJECT" 2>/dev/null || true)
BIND=$(jq -r '.dashboard.bind // empty' "$IL_MACHINE" 2>/dev/null || true)
PORT=$(jq -r '.dashboard.port // empty' "$IL_MACHINE" 2>/dev/null || true)
HOSTS=$(jq -r '.dashboard.hosts // empty' "$IL_MACHINE" 2>/dev/null || true)
WAS=$SCOPE DASHBOARD=1 STATUS=
[ "$(jq -r '.dashboard' "$IL_PROJECT" 2>/dev/null)" != false ] || DASHBOARD=
# No answer and no earlier one: on when the owner already has the serena server.
[ -n "$SERENA" ] || ! jq -e --arg p "$PP_MAIN" '.mcpServers.serena // .projects[$p].mcpServers.serena' "$HOME/.claude.json" >/dev/null 2>&1 || SERENA=true
while [ $# -gt 0 ]; do
  # Two case statements, not one with `;;&`: Bash 3.2 cannot parse that.
  case $1 in
    --profile|--scope|--name|--persona|--test-command|--bind|--port|--hosts|--status-line|--builder-model|--builder-advisor) [ $# -ge 2 ] || usage ;;
  esac
  case $1 in
    --profile) PROFILE=$2; shift 2 ;;
    --scope) SCOPE=$2; shift 2 ;;
    --name) NAME=$2; shift 2 ;;
    --persona) PERSONA=$2; shift 2 ;;
    --test-command) TEST=$2; shift 2 ;;
    --bind) BIND=$2; shift 2 ;;
    --port) PORT=$2; shift 2 ;;
    --hosts) HOSTS=$2; shift 2 ;;
    --status-line) [ -n "$2" ] || usage; STATUS=$2; shift 2 ;;
    --builder-model) BMODEL=$2; shift 2 ;;
    --builder-advisor) BADVISOR=$2; shift 2 ;;
    --strict) STRICT=true; shift ;;
    --no-strict) STRICT=false; shift ;;
    --serena) SERENA=true; shift ;;
    --no-serena) SERENA=false; shift ;;
    --standard-context) STANDARD=true; shift ;;
    --no-standard-context) STANDARD=false; shift ;;
    --codex-fast) FAST=true; shift ;;
    --no-codex-fast) FAST=false; shift ;;
    --dashboard) DASHBOARD=1; shift ;;
    --no-dashboard) DASHBOARD=; shift ;;
    --install-missing) shift ;;
    *) usage ;;
  esac
done
SCOPE=${SCOPE:-project}
case $PROFILE in claude|claude-openai) ;; *) echo "setup: --profile is claude (Claude does the review passes) or claude-openai (Codex does them)" >&2; usage ;; esac
case $SCOPE in project|machine) ;; *) usage ;; esac
[[ ${PORT:-1} =~ ^[0-9]+$ ]] || usage
# Extra names the dashboard answers to (a tailnet's name for this machine). None by default: a name
# not listed is one another site may have pointed here, and gets a 403.
[[ ${HOSTS:-a} =~ ^[A-Za-z0-9.-]+(,[A-Za-z0-9.-]+)*$ ]] || { echo "setup: --hosts takes host names separated by commas" >&2; usage; }
# The Builder's model and advisor: no answer means the routing file's own; a name is one routing already
# names; and the advisor alone may be "none", a Builder launched with no advisor at all.
ADVISOR=$BADVISOR; [ "$ADVISOR" != none ] || ADVISOR=
for a in "$BMODEL" "$ADVISOR"; do
  [ -z "$a" ] || jq -e --arg a "$a" "$PP_ROUTE_JQ"' aliases | any(. == $a)' "$(pp_routing)" >/dev/null \
    || die "the Builder's model and advisor are each one of $(jq -r "$PP_ROUTE_JQ"' aliases | join(", ")' "$(pp_routing)") (the advisor may also be none), not '$a'. Nothing was changed"
done
[ -z "$WAS" ] || [ "$WAS" = "$SCOPE" ] || die "this project is set up with --scope $WAS; run uninstall.sh first to change the scope"

# --- preflight: refuse here, before anything changes ---
# Again, for a profile that came from the saved config and not from --profile.
need "$PROFILE"
# The watcher's job and the logs under ~/.claude are named for the project's
# folder name, so two projects with one name would share them, and uninstalling
# either would stop the other's watcher and delete its history.
MINE=${PP_MAIN##*/}; MINE=${MINE//[^A-Za-z0-9_.-]/-}
# The install record and the scratch folder are named for the whole path with
# every odd character a dash, so /x/a-b and /x/a_b are one record.
o=$(jq -r '.project // empty' "$IL_PROJECT" 2>/dev/null || true)
[ -z "$o" ] || [ "$o" = "$PP_MAIN" ] \
  || die "the install record this checkout would use ($IL_PROJECT) belongs to another project, which is set up at $o: the two paths are one name once every odd character is a dash. Rename one checkout's folder, or uninstall the other first. Nothing was changed"
while IFS= read -r m; do
  o=$(jq -r '.project // empty' "$m" 2>/dev/null); n=${o##*/}
  [ -z "$o" ] || [ "$o" = "$PP_MAIN" ] || [ "${n//[^A-Za-z0-9_.-]/-}" != "$MINE" ] \
    || die "another project named ${PP_MAIN##*/} is set up at $o. The watcher's job and the logs under ~/.claude are named for the folder name, so the two would share them: rename one checkout's folder, or uninstall the other first"
done < <(il_projects)
PASS=claude
if [ "$PROFILE" = claude-openai ]; then
  PASS=codex
fi
# Codex fast mode changes what a run costs, so only the owner's yes turns it on; no answer is off. The
# tier itself is the Codex home's own setting, which setup never writes: a yes that home does not match is refused here.
[ "$FAST" != true ] || [ "$PROFILE" != claude-openai ] || pp_codex_fast_home \
  || die "Codex fast mode was chosen, but ${CODEX_HOME:-$HOME/.codex}/config.toml has no service_tier = \"fast\" line, so the review passes would run on the standard tier. Add that line and run setup again, or answer off (--no-codex-fast). Nothing was changed"
COMMANDECK_CODEX_FAST=false COMMANDECK_PASS=$PASS bash "$HERE/builder-codex-pass.sh" --preflight >/dev/null || die "the $PROFILE profile's review pass cannot run (above); nothing was changed"
for f in "$PP_MAIN/.claude/settings.json" "$HOME/.claude/settings.json" "$IL_CODEX/hooks.json"; do
  [ ! -s "$f" ] || jq -e 'type == "object"' "$f" >/dev/null 2>&1 || die "$f is not a JSON object; fix it first. Nothing was changed"
done

# --- the manifest, before the first change ---
SETTINGS=$PP_MAIN/.claude/settings.json SM=$IL_PROJECT
[ "$SCOPE" = project ] || { SETTINGS=$HOME/.claude/settings.json; SM=$IL_MACHINE; }
WATCH_JOB=$(bash "$HERE/main-watch.sh" --job-file) DASH_JOB=$(bash "$HERE/dashboard.sh" --job-file)
il_record "$IL_PROJECT" own "$IL_CONFIG" "$WATCH_JOB"
il_record "$IL_PROJECT" merge "$IL_EXCLUDE"
il_record "$SM" merge "$SETTINGS"
# Workflows are switched on in the project's own settings at either scope: the machine's file is every project's.
PSET=$PP_MAIN/.claude/settings.json WF=$PP_MAIN/.claude/workflows/test-audit.js
il_record "$IL_PROJECT" merge "$PSET"
il_record "$IL_PROJECT" own "$WF"
if [ "$PROFILE" = claude-openai ]; then
  il_record "$IL_PROJECT" merge "$IL_AGENTS"
  il_record "$IL_MACHINE" merge "$IL_CODEX/hooks.json" "$IL_CODEX/config.toml"
fi
[ -z "$DASHBOARD" ] || il_record "$IL_MACHINE" own "$DASH_JOB"
# The ponytail skill is the one add-on setup installs. A skill of that name the owner has, or
# the whole add-on, is the owner's: only a copy an earlier setup made is written again.
PONY=$HOME/.claude/skills/ponytail PONY_OURS=
if il_has "$IL_MACHINE" "$PONY/SKILL.md" || { [ ! -e "$PONY" ] && [ ! -L "$PONY" ] \
  && ! jq -e '.enabledPlugins["ponytail@ponytail"] == true' "$HOME/.claude/settings.json" >/dev/null 2>&1; }; then
  PONY_OURS=1; il_record "$IL_MACHINE" own "$PONY/SKILL.md" "$PONY/LICENSE"
fi
if [ -n "$STATUS" ]; then
  il_record "$IL_MACHINE" merge "$HOME/.claude/settings.json"
  # The first status line setup replaces is the owner's; a second answer must not take the first for it.
  jq -e 'has("statusLine")' "$IL_MACHINE" >/dev/null \
    || il_set "$IL_MACHINE" --argjson was "$(jq -c '.statusLine // null' "$HOME/.claude/settings.json" 2>/dev/null || echo null)" '.statusLine = {was: $was}'
fi
il_set "$IL_PROJECT" --arg p "$PP_MAIN" --arg s "$SCOPE" --arg r "$IL_ROOT" --arg d "${DASHBOARD:-0}" '. + {project: $p, scope: $s, root: $r, dashboard: ($d == "1")}'

# --- the changes ---
# What setup really writes in the project: il_write notes each path whose content is new or different.
# The exclude file is also written by worktree-setup.sh, by itself, so it is compared at the end.
IL_WROTE=$(mktemp); export IL_WROTE; trap 'rm -f "$IL_WROTE"' EXIT
EXCLUDE_WAS=$(il_sha "$IL_EXCLUDE" 2>/dev/null || true)
jq -n --argjson v "$IL_VERSION" --arg profile "$PROFILE" --arg strict "$STRICT" --arg serena "$SERENA" --arg standard "$STANDARD" \
  --arg test "$TEST" --arg name "$NAME" --arg persona "$PERSONA" --arg bm "$BMODEL" --arg ba "$BADVISOR" --arg fast "$FAST" '
  {version: $v, profile: $profile, strictHooks: ($strict == "true"), serena: ($serena == "true"), standardContext: ($standard == "true"),
   codexFast: ($fast == "true")}
  + (if $test == "" then {} else {testCommand: $test} end)
  + (if $bm + $ba == "" then {} else {builder: ({model: $bm, advisor: $ba} | with_entries(select(.value != "")))} end)
  + {chiefOfStaff: ({name: $name, persona: $persona} | with_entries(select(.value != "")))}' | il_write "$IL_CONFIG"
il_allow_set "$SM" "$SETTINGS" "$(il_allow "$IL_ROOT")"
il_workflows "$IL_PROJECT" "$PSET"
il_test_audit "$IL_ROOT" "$WF"
# Git never sees the running state, so the main checkout stays clean while the plugin runs.
il_lines "$IL_PROJECT" "$IL_EXCLUDE" "${IL_STATE[@]}"
if [ "$PROFILE" = claude-openai ]; then
  il_block "$IL_AGENTS" "$IL_ROOT/templates/codex-instructions.md"
  il_codex_hooks "$IL_ROOT"
  il_notify "$IL_ROOT"
  python3 "$HERE/codex-hook-trust.py" "$IL_CODEX" >/dev/null
fi
if [ -n "$DASHBOARD" ]; then
  # A line the owner put there before setup is the owner's: uninstall takes out only setup's own.
  grep -qxF -- "$PP_MAIN" "$HOME/.commandeck/dashboard/projects" 2>/dev/null || il_set "$IL_PROJECT" '.registered = true'
  bash "$HERE/dashboard.sh" --register "$PP_MAIN" >/dev/null
  COMMANDECK_DASHBOARD_BIND=${BIND:-127.0.0.1} COMMANDECK_DASHBOARD_PORT=$PORT COMMANDECK_DASHBOARD_HOSTS=$HOSTS bash "$HERE/dashboard.sh" --install >/dev/null
  PORT=$(grep -oE 'COMMANDECK_DASHBOARD_PORT[^0-9]*[0-9]+' "$DASH_JOB" | grep -oE '[0-9]+$' | head -1)
  il_set "$IL_MACHINE" --arg b "${BIND:-127.0.0.1}" --arg p "$PORT" --arg h "$HOSTS" '.dashboard = {bind: $b, port: $p, hosts: $h}'
else
  # Declined after it was on: the project comes off the dashboard. The job is every project's and stays.
  ! jq -e '.registered == true' "$IL_PROJECT" >/dev/null 2>&1 || ! grep -qxF -- "$PP_MAIN" "$HOME/.commandeck/dashboard/projects" 2>/dev/null \
    || { bash "$HERE/dashboard.sh" --unregister "$PP_MAIN" >/dev/null; il_set "$IL_PROJECT" 'del(.registered)'; }
fi
bash "$HERE/main-watch.sh" --install >/dev/null
if [ -n "$PONY_OURS" ]; then
  for f in SKILL.md LICENSE; do il_write "$PONY/$f" < "$IL_ROOT/templates/ponytail/$f"; done
fi
if [ -n "$STATUS" ]; then
  ST=$(cat "$HOME/.claude/settings.json" 2>/dev/null) || ST=; [ -n "${ST//[[:space:]]/}" ] || ST='{}'
  ST=$(jq --arg c "$STATUS" '.statusLine = {type: "command", command: $c}' <<<"$ST") && il_write "$HOME/.claude/settings.json" <<<"$ST"
  il_set "$IL_MACHINE" --argjson set "$(jq -c .statusLine <<<"$ST")" '.statusLine.set = $set'
fi

echo "commandeck $(jq -r .version "$IL_ROOT/.claude-plugin/plugin.json") is set up for $PP_MAIN ($PROFILE profile, permissions in $SETTINGS)"
[ -z "$DASHBOARD" ] || echo "dashboard: http://${BIND:-127.0.0.1}:$PORT/"

# --- the project's Orca run: made once here, or the one command that makes it ---
# The board refuses to work without one. A run already recorded, or bound to this terminal, is the project's.
# Either is written down as board.sh writes it, so a setup from another terminal makes no second run.
run_id() { jq -r "$1"' // empty' 2>/dev/null | grep -xE '[A-Za-z0-9_-]+' || true; }
keep_run() { mkdir -p "$PP_SCRATCH" && printf '%s\n' "$RUN" > "$PP_RUN_FILE"; }
RUN=$(tr -d '[:space:]' < "$PP_RUN_FILE" 2>/dev/null || true)
[ -n "$RUN" ] || { RUN=$(orca-ide orchestration run-current --json 2>/dev/null | run_id .result.run.id || true); [ -z "$RUN" ] || keep_run; }
if [ -n "$RUN" ]; then echo "Orca run: $RUN (already there; none was created)"
elif RUN=$(orca-ide orchestration run-create --objective "${PP_MAIN##*/}" --json 2>/dev/null | run_id '.result.run.id // .result.id') && [ -n "$RUN" ]; then
  keep_run
  echo "Orca run: created $RUN for this project and bound this terminal to it"
else
  echo "Orca run: none was created (Orca did not answer with a run). Run this in the main checkout's session: orca-ide orchestration run-create --objective $(printf '%q' "${PP_MAIN##*/}")"
fi

# --- the relay: its worktree and its pane, made once ---
# A relay was chosen (now or at an earlier setup) when it has a name. The worktree's folder is what
# makes a pane the relay (agent-startup-context.sh), so one that exists is never made again, and a
# pane is opened only into a worktree this run created. What could not be done is printed as the
# exact steps. The worktree is created where a Builder's is: pp_worktree_new.
if [ -n "$NAME" ]; then
  COS=$PP_WORKSPACES/Chief-of-Staff STEPS=() PANE=
  S_WT="orca-ide worktree create --repo path:$(printf '%q' "$PP_MAIN") --name Chief-of-Staff --base-branch main --parent-worktree path:$(printf '%q' "$PP_MAIN") --setup run"
  S_SET="bash $(printf '%q' "$HERE")/worktree-setup.sh $(printf '%q' "$COS")"
  S_PANE="orca-ide terminal create --worktree path:$(printf '%q' "$COS") --title $(printf '%q' "$NAME") --command claude"
  if [ -e "$COS" ] && [ "$(git -C "$COS" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" != "$(git -C "$PP_MAIN" rev-parse --path-format=absolute --git-common-dir)" ]; then
    # A same-named project elsewhere shares the workspaces folder: its relay is not this one's.
    echo "Relay: $COS is not a worktree of this project; nothing was done with it. Move it aside and run setup again."
  elif [ -d "$COS" ]; then
    echo "Relay: $NAME's worktree is $COS (already there; nothing was created)."
    # Its settings again: a setup that stopped after making the worktree left them out.
    if ! bash "$HERE/worktree-setup.sh" "$COS" >/dev/null 2>&1; then STEPS=("$S_SET" "$S_PANE")
    else PANE=$(bash "$HERE/cos-tell.sh" --handle 2>/dev/null) && echo "Relay: its pane is $PANE." || STEPS=("$S_PANE"); fi
  elif ! pp_worktree_new Chief-of-Staff 2>/dev/null; then STEPS=("$S_WT" "$S_SET" "$S_PANE")
  elif ! bash "$HERE/worktree-setup.sh" "$COS" >/dev/null 2>&1; then STEPS=("$S_SET" "$S_PANE")
  # 3 is a live pane of that name already there: nothing new was opened, and it is the relay's.
  elif . "$HERE/codex-helpers.sh" && { PANE=$(open_pane "path:$COS" "$NAME" claude 2>/dev/null) || [ $? = 3 ]; }; then
    echo "Relay: created $NAME's worktree $COS and opened its pane ($PANE)."
  else echo "Relay: created $NAME's worktree $COS."; STEPS=("$S_PANE")
  fi
  if [ ${#STEPS[@]} -gt 0 ]; then
    echo "Relay: $NAME has no pane yet. Run, in this order:"
    for s in "${STEPS[@]}"; do echo "  $s"; done
  fi
  echo "The session in this main checkout is the orchestrator, NOT the relay: talk to $NAME only in the pane of the Chief-of-Staff worktree."
fi

# --- the project files setup created or changed, from the writes themselves ---
[ "$EXCLUDE_WAS" = "$(il_sha "$IL_EXCLUDE" 2>/dev/null || true)" ] || grep -qF "	$IL_EXCLUDE" "$IL_WROTE" || printf 'changed\t%s\n' "$IL_EXCLUDE" >> "$IL_WROTE"
WROTE=$(awk -F'\t' -v m="$PP_MAIN/" 'index($2, m) == 1 && !s[$2]++ { print $1 "\t" substr($2, length(m) + 1) }' "$IL_WROTE" | sort -t$'\t' -k2)
if [ -z "$WROTE" ]; then echo "Setup created or changed no file in this project."
else
  echo "Files setup created or changed in this project:"
  while IFS=$'\t' read -r k f; do
    case $f in
      .git/*) why="not for git: git's own local file" ;;
      *) if git -C "$PP_MAIN" check-ignore -q -- "$f"; then why="not for git: this machine's own, and git ignores it"; else why="commit it"; fi ;;
    esac
    printf '  %s  %s  %s\n' "$k" "$f" "$why"
  done <<<"$WROTE"
  echo
fi
# The config setup wrote is the project's: a unit's worktree has it only once git holds it. Setup never commits.
OWED=()
for f in "$IL_CONFIG" "$PSET" "$IL_AGENTS"; do
  f=${f#"$PP_MAIN"/}
  [ -e "$PP_MAIN/$f" ] || continue
  { git -C "$PP_MAIN" cat-file -e "HEAD:$f" && git -C "$PP_MAIN" diff --quiet HEAD -- "$f"; } 2>/dev/null || OWED+=("$f")
done
[ ${#OWED[@]} = 0 ] || echo "not committed yet: ${OWED[*]}. Commit them, so every unit's worktree has them: git -C $(printf '%q' "$PP_MAIN") add -f -- ${OWED[*]} && git -C $(printf '%q' "$PP_MAIN") commit -m 'chore: commandeck setup' -- ${OWED[*]}"
echo "check it: bash $(printf '%q' "$HERE")/doctor.sh    undo it: bash $(printf '%q' "$HERE")/uninstall.sh"
echo
if [ -n "$PONY_OURS" ]; then echo "Add-ons. Setup installed the ponytail skill ($PONY) and no other; each line is the command and what it costs:"
else echo "Add-ons. The ponytail skill or add-on is already on this machine and was left as it is; setup installed none. Each line is the command and what it costs:"; fi
while IFS=$'\t' read -r name cmd cost; do
  case $name in ''|'#'*) continue ;; esac
  printf '  %-17s %s\n  %-17s   cost: %s\n' "$name" "$cmd" '' "$cost"
done < "$IL_ROOT/config/addons.tsv"
ST=$(jq -c '.statusLine // empty' "$HOME/.claude/settings.json" 2>/dev/null || true)
if [ -n "$STATUS" ]; then echo "Status line: set to ${ST}; the one before it comes back at uninstall."
else echo "Status line: left as it is (${ST:-none set}). To set one: bash $(printf '%q' "$HERE")/setup.sh --status-line '<command>'; the one before it is recorded and comes back at uninstall."; fi

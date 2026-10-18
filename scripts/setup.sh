#!/usr/bin/env bash
# setup.sh --profile claude|claude-openai [--scope project|machine]
#          [--name <n>] [--persona <text>] [--strict|--no-strict]
#          [--serena|--no-serena] [--standard-context|--no-standard-context]
#          [--test-command <cmd>] [--bind <address>] [--port <n>] [--dashboard|--no-dashboard]
#          [--hosts <name>[,<name>...]] [--status-line <command>]
#          [--builder-model <alias>] [--builder-effort low|medium|high|max] [--builder-clear-line <tokens>|off]
#          [--issue-sizing <tokens>|off] [--codex-fast|--no-codex-fast] [--plan-models <model>[,<model>...]|'']
#          [--codex-model <Codex role>=<model id>|<Codex role>= ...] [--plan-fast <plan seat>[,<plan seat>...]|'']
#          [--global-claude|--global-rules install|block|merge|skip] [--notify-wrapper yes|no] [--install-missing]
#          [--max-rounds <n>] [--closing-pass yes|no] [--small-build <lines>|off] [--max-review-min <minutes>|off] [--max-test-percent <n>|off] [--max-usd <n>|off] [--review-flags off]
#          [--own-startup|--own-main-session replace|merge|skip] [--rules merge|skip] [--rules-drop|--rules-keep <rule id>|'']
#          [--addons <name>[,<name>...]|none] [--ponytail|--no-ponytail] [--cache-ttl 5m|leave] [--relay-cache-ttl 1h|leave] [--auto-mode add|leave|remove] [--plan]
#          [--worker-skills-off <skill>[,<skill>...]|''] [--worker-plugins-off <plugin@marketplace>[,...]|''] [--keep-word <word>=<name>[,<name>...]|<word>=]
#   or: setup.sh --questions begin|end
# Sets the project this runs in up for the plugin. It asks nothing: the setup
# skill asks the owner once and passes every answer here. A second run changes
# the answers given and keeps the rest; update.sh is this script with none.
# --plan prints every file and change a run with these answers would make, and
# writes nothing. --questions begin checks the requirements, says what setup
# found (the owner's own rule files, earlier answers) and suspends the picker
# guard's decoy while the skill asks; --questions end, or the end of a real run,
# brings the decoy back.
#
# Requirements (requirements.sh) are checked before all else, and all
# at once. Setup installs nothing by itself: --install-missing is the owner's
# yes, and runs the commands the check printed, word for word, and no other.
#
# Order, and why: the preflight refuses before anything is touched; then the
# install manifest (install-lib.sh) records every path about to change, so a
# setup that dies half way can still be undone by uninstall.sh; then the
# changes. --scope says where the permission rules go: the project's own
# .claude/settings.local.json (git never sees it: the rules name this machine's
# paths), or ~/.claude/settings.json for every project. An owner's file setup
# changes is copied beside it first (<file>.commandeck-bak-<date>). Every add-on
# (or those --addons names) is installed or updated to its latest by its
# config/addons.tsv command; the rest are printed. The ponytail skill is installed unless --no-ponytail.
# --cache-ttl 5m writes the prompt-cache lifetime of main and every worker pane (and subagents) as 5 minutes,
# into the project's .claude/settings.json and each worktree's settings.local.json; leave writes nothing, and keeps
# what an earlier run wrote. --relay-cache-ttl 1h does the same for the relay pane's worktree; leave writes
# nothing. Until each is answered, setup writes nothing for it and says so. A
# status line is set only when one is given, and the one before it is recorded
# for uninstall.
# --auto-mode add puts two lines into the auto-mode classifier's list in ~/.claude/settings.json (every project on
# this machine); leave, and no answer, change nothing there; remove takes out the lines setup added (an update
# replays add or leave, never a remove).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# Ahead of paths.sh, which on a Mac refuses to load without the tools this
# check offers to install; and down to that load in Bash 3.2's syntax, for a
# Mac that has no newer Bash yet.
. "$HERE/requirements.sh"
# A value is never read as a flag: `--name --install-missing` names the relay, and is no yes.
# The options that take a value: this loop and the full parse below both read this one list.
TAKES=' --profile --scope --name --persona --test-command --bind --port --hosts --status-line --builder-model --builder-effort --builder-clear-line --issue-sizing --plan-models --plan-fast --codex-model --notify-wrapper --global-claude --global-rules --max-rounds --closing-pass --small-build --max-review-min --max-test-percent --max-usd --review-flags --own-startup --own-main-session --rules --rules-drop --rules-keep --addons --cache-ttl --relay-cache-ttl --auto-mode --worker-skills-off --worker-plugins-off --keep-word --questions '
INSTALL= ASKED= OPT= PLAN= QUESTIONS=
for a; do
  if [ -n "$OPT" ]; then [ "$OPT" != --profile ] || ASKED=$a; [ "$OPT" != --questions ] || QUESTIONS=$a; OPT=; continue; fi
  case $TAKES in *" $a "*) OPT=$a; continue ;; esac
  case $a in
    --install-missing) INSTALL=1 ;;
    --plan) PLAN=1 ;;
  esac
done
# The picker guard's decoy is off while this marker is under an hour old (worker-ask-guard.sh).
ASKING=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/commandeck-setup-questions
case $QUESTIONS in
  '') ;;
  end) rm -f "$ASKING"; echo "setup: questions show their extra safety option again"; exit 0 ;;
  # The pause starts only once every check below has passed (the end of the begin branch).
  begin) [ "$ASKING" != /commandeck-setup-questions ] || { echo "setup: run this in the project's main checkout" >&2; exit 1; } ;;
  *) echo "setup: --questions takes begin or end" >&2; exit 2 ;;
esac
# A plan writes nothing (install-lib.sh IL_PLAN), so it installs nothing either. A real run
# brings the decoy back however it ends.
if [ -n "$PLAN" ]; then INSTALL=; export IL_PLAN=1
elif [ -z "$QUESTIONS" ]; then trap 'rm -f "$ASKING"' EXIT; fi
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
usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,9\}//' >&2; exit 2; }
# `false` is a stored answer: `// empty` would drop it and the default would come back.
old() { jq -r "$1 | if . == null then empty else . end" "$IL_CONFIG" 2>/dev/null || true; }

if [ -e "$IL_CONFIG" ]; then
  V=$(old .version)
  [ "$V" = "$IL_VERSION" ] || die "$IL_CONFIG is config version ${V:-(none)}, and this plugin knows version $IL_VERSION only; it does not migrate a config. To start over with fresh answers, set the old one aside and run setup again: mv $(printf '%q' "$IL_CONFIG") $(printf '%q' "$IL_CONFIG").old"
fi
OWN=(AGENT_STARTUP.md .claude/main-session.md)
PROFILE=$(old .profile) NAME=$(old .chiefOfStaff.name) PERSONA=$(old .chiefOfStaff.persona) TEST=$(old .testCommand)
STRICT=$(old .strictHooks) STANDARD=$(old .standardContext) SERENA=$(old .serena)
BMODEL=$(old .builder.model) BEFFORT=$(old .builder.effort) BCLEAR=$(old .builder.clearLine) SIZING=$(old .issueSizing) FAST=$(old .codexFast)
PMODELS=$(old '.planModels | join(",")') PFAST=$(old '.planFast | join(",")')
OWNS=$(old '.ownFiles["AGENT_STARTUP.md"]') OWNM=$(old '.ownFiles[".claude/main-session.md"]') RULES=$(old .rules) PONYTAIL=$(old .ponytail) CACHE=$(old .cacheTtl) RCACHE=$(old .chiefOfStaff.cacheTtl) AUTO=$(old .autoMode)
DROPS=$(jq -c '.mergeDecisions // {}' "$IL_CONFIG" 2>/dev/null || echo '{}') ADDONS= ADDONS_SET=
CMODELS=$(jq -c '.codexModels // {}' "$IL_CONFIG" 2>/dev/null || echo '{}')
# merge-unit-local.sh reads the owner's list of generated files; setup rebuilds the file, so the list is carried over (empty output counts as null).
GEN=$(jq -c '.generatedFiles // null' "$IL_CONFIG" 2>/dev/null || echo null); GEN=${GEN:-null}
# The owner's worker cuts (worktree-setup.sh writes them): carried over as saved, and each answer below changes one.
CUTS=$(jq -c '{workerSkillsOff, workerPluginsOff, keeps} | with_entries(select(.value != null))' "$IL_CONFIG" 2>/dev/null || true); [ -n "$CUTS" ] || CUTS='{}'
RL=$(jq -c '.reviewLoop | if type == "object" then . else {} end' "$IL_CONFIG" 2>/dev/null || echo '{}')
# rl <key> <answer> <regex> <flag> <what it takes> -- a review-loop answer: an empty one takes the
# default back (nothing saved), any other is saved exactly as typed once the loop's reader would take it.
rl() { [ -z "$2" ] || [[ $2 =~ $3 ]] || die "$4 takes $5; '$2' was not saved, and nothing was changed"
  RL=$(jq -c --arg k "$1" --arg v "$2" 'if $v == "" then del(.[$k]) else .[$k] = $v end' <<<"$RL"); }
INT='^[1-9][0-9]*$' NUM='^[0-9]+([.][0-9]+)?$' OFFNUM='^(off|[0-9]+([.][0-9]+)?)$'
SCOPE=$(jq -r '.scope // empty' "$IL_PROJECT" 2>/dev/null || true)
BIND=$(jq -r '.dashboard.bind // empty' "$IL_MACHINE" 2>/dev/null || true)
PORT=$(jq -r '.dashboard.port // empty' "$IL_MACHINE" 2>/dev/null || true)
HOSTS=$(jq -r '.dashboard.hosts // empty' "$IL_MACHINE" 2>/dev/null || true)
WAS=$SCOPE DASHBOARD=1 STATUS= NWRAP= GCLAUDE= GRULES= SERENA_AUTO=
[ "$(jq -r '.dashboard' "$IL_PROJECT" 2>/dev/null)" != false ] || DASHBOARD=
# No answer and no earlier one: on when the owner already has the serena server.
[ -n "$SERENA" ] || ! jq -e --arg p "$PP_MAIN" '.mcpServers.serena // .projects[$p].mcpServers.serena' "$HOME/.claude.json" >/dev/null 2>&1 || { SERENA=true SERENA_AUTO=1; }
if [ "$QUESTIONS" = begin ]; then
  # What the skill needs to know before its first question: what is here already, and what each answer could not do.
  echo "setup: requirements met. Found in $PP_MAIN:"
  [ ! -e "$IL_CONFIG" ] || echo "  earlier answers: .claude/commandeck.json (each question offers the saved answer first)"
  for f in "${OWN[@]}"; do
    [ ! -f "$PP_MAIN/$f" ] || echo "  your own $f: it loads instead of the plugin's, unless you choose otherwise (replace, merge or skip; saved: $(old ".ownFiles[\"$f\"]" | grep . || echo none))"
  done
  # What main loads; each seat leaves out what its own rules state when it starts (the session hook).
  A=(); while IFS= read -r d; do A+=("$d"); done < <(il_rules_against)
  R=$(python3 "$IL_ROOT/scripts/merge-rules.py" /dev/null ${A[@]+"${A[@]}"} --sources | sed "s|^$PP_MAIN/||" | paste -sd, - | sed 's/,/, /g')
  if [ -n "$R" ]; then
    N=$(for t in AGENT_STARTUP.md main-session.md; do python3 "$IL_ROOT/scripts/merge-rules.py" "$IL_ROOT/templates/$t" "${A[@]}" --report; done | grep -c '^  already in ') || true
    echo "  your project rules: $R. Merging leaves out the $N plugin rule$([ "$N" = 1 ] || echo s) you already have."
  fi
  [ ! -s "$IL_GLOBAL" ] || echo "  your global rules: $IL_GLOBAL (install writes nothing into it: offer merge, block or skip)"
  [ -z "${SERENA_AUTO:-}" ] || echo "  a serena server is configured: setup turns serena on unless told --no-serena"
  if req_check setup claude-openai >/dev/null 2>&1; then echo "  Codex reviewer: ready"
  else echo "  Codex reviewer: missing ${REQ_NAMES:-a requirement}; offer it only with Install first"; fi
  if pp_codex_fast_home; then echo "  Codex fast mode: available"
  else echo "  Codex fast mode: not available (${CODEX_HOME:-$HOME/.codex}/config.toml has no service_tier = \"fast\" line); do not offer it"; fi
  # Codex's model is found before the question, not after a refused run.
  if [ -z "${REQ_NAMES:-}" ]; then
    if M=$(COMMANDECK_REVIEW_LOOP=$RL COMMANDECK_CODEX_MODELS=$CMODELS COMMANDECK_CODEX_FAST=false COMMANDECK_PASS=codex bash "$HERE/builder-codex-pass.sh" --preflight 2>&1 >/dev/null); then echo "  Codex model: found ($(pp_codex_route))"
    else echo "  Codex model: not found, so ask for its id (--codex-model codex-reviewer=<id>): $M"; fi
  fi
  # The context window: a model setting that names a 1M model ends in [1m] (the nearest settings file wins).
  CM=${ANTHROPIC_MODEL:-$(for f in "$PP_MAIN/.claude/settings.local.json" "$PP_MAIN/.claude/settings.json" "$HOME/.claude/settings.json"; do jq -r '.model // empty' "$f" 2>/dev/null; done | head -1)}
  case $CM in
    *'[1m]') echo "  context window: 1M (the model setting is $CM): preselect Larger" ;;
    '') echo "  context window: no model setting here; a model id that ends in [1m] (yours, or what /model shows) is a 1M window, else 200K" ;;
    *) echo "  context window: 200K (the model setting is $CM, which does not end in [1m]): preselect 200K" ;;
  esac
  date +%s > "$ASKING"
  echo "setup: questions show without their extra safety option until setup ends (or: setup.sh --questions end)"
  exit 0
fi
while [ $# -gt 0 ]; do
  # Two case statements, not one with `;;&`: Bash 3.2 cannot parse that.
  case $TAKES in *" $1 "*) [ $# -ge 2 ] || usage ;; esac
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
    # The Builder's effort and clear line, and the issue sizing line: '' takes the default back (nothing saved).
    --builder-effort) case $2 in low|medium|high|max|'') BEFFORT=$2 ;; *) die "--builder-effort takes low, medium, high or max, not '$2'. Nothing was changed" ;; esac; shift 2 ;;
    --builder-clear-line) [[ $2 =~ ^(off|[1-9][0-9]*)?$ ]] || die "--builder-clear-line takes a number of tokens, or off, not '$2'. Nothing was changed"; BCLEAR=$2; shift 2 ;;
    # The models a plan seat may run on, comma-separated; '' takes the default back (every model routing names).
    --plan-models) PMODELS=$2; shift 2 ;;
    # The plan seats that run on the fast tier, comma-separated; '' is none, the default.
    --plan-fast) PFAST=$2; shift 2 ;;
    --issue-sizing) [[ $2 =~ ^(off|[1-9][0-9]*)?$ ]] || die "--issue-sizing takes a number of tokens, or off, not '$2'. Nothing was changed"; SIZING=$2; shift 2 ;;
    # The owner's answer to the question below, for this run only: an owner's wrapper is changed only on yes.
    --notify-wrapper) case $2 in yes|no) NWRAP=$2 ;; *) usage ;; esac; shift 2 ;;
    # The global CLAUDE.md template and the rules: this run's answer, never saved; no answer leaves the file alone.
    --global-claude) case $2 in install|block|merge|skip) GCLAUDE=$2 ;; *) usage ;; esac; shift 2 ;;
    --global-rules) case $2 in install|block|merge|skip) GRULES=$2 ;; *) usage ;; esac; shift 2 ;;
    # The project's own AGENT_STARTUP.md and main-session.md (il_own), and the plugin's rules against the
    # project's CLAUDE.md and .claude/rules/ (merge: the session hook leaves out the ones already there). Saved.
    --own-startup) case $2 in replace|merge|skip) OWNS=$2 ;; *) usage ;; esac; shift 2 ;;
    --own-main-session) case $2 in replace|merge|skip) OWNM=$2 ;; *) usage ;; esac; shift 2 ;;
    --rules) case $2 in merge|skip) RULES=$2 ;; *) usage ;; esac; shift 2 ;;
    # A plugin rule the owner keeps their own wording for, by its merge-rules.py id; '' clears them all.
    # --rules-keep: both load, and the answer is saved so a rerun does not ask it again.
    --rules-drop|--rules-keep) case $2 in '') DROPS='{}' ;; *) [[ $2 =~ ^[0-9a-f]{8}$ ]] || die "$1 takes a rule id, 8 hex digits as merge-rules.py --units prints it, not '$2'. Nothing was changed"
                  DROPS=$(jq -c --arg i "$2" --arg v "$([ "$1" = --rules-drop ] && echo keep-mine || echo keep-both)" '.[$i] = $v' <<<"$DROPS") ;; esac; shift 2 ;;
    # The add-ons to install or update this run (config/addons.tsv names), never saved; with none given, every one.
    --addons) ADDONS=${2//,/ } ADDONS_SET=1; [ "$2" != none ] || ADDONS=; shift 2 ;;
    --ponytail) PONYTAIL=true; shift ;;
    --no-ponytail) PONYTAIL=false; shift ;;
    --cache-ttl) case $2 in 5m|leave) CACHE=$2 ;; *) die "--cache-ttl takes 5m or leave, not '$2'. Nothing was changed" ;; esac; shift 2 ;;
    --relay-cache-ttl) case $2 in 1h|leave) RCACHE=$2 ;; *) die "--relay-cache-ttl takes 1h or leave, not '$2'. Nothing was changed" ;; esac; shift 2 ;;
    --auto-mode) case $2 in add|leave|remove) AUTO=$2 ;; *) die "--auto-mode takes add, leave or remove, not '$2'. Nothing was changed" ;; esac; shift 2 ;;
    --plan|--install-missing) shift ;;
    --worker-skills-off|--worker-plugins-off|--keep-word) CUTS=$(il_cuts "$CUTS" "$1" "$2") || exit 1; shift 2 ;;
    # A role with no id clears the saved one. Checked below, once the routing file is known.
    --codex-model) [[ $2 == *=* ]] || usage; CMODELS=$(jq -c --arg r "${2%%=*}" --arg m "${2#*=}" 'if $m == "" then del(.[$r]) else .[$r] = $m end' <<<"$CMODELS"); shift 2 ;;
    # The review loop (reviewLoop): each left out keeps the saved answer, and '' takes today's default back.
    --max-rounds) rl maxRounds "$2" "$INT" "$1" "a whole number of passes"; shift 2 ;;
    --closing-pass) case $2 in yes) rl closingPass '' '' ;; no) rl closingPass no '^no$' ;; *) usage ;; esac; shift 2 ;;
    # off is saved as the word: no build is small, so every first pass has three reviewers.
    --small-build) rl smallBuild "$2" '^(off|[1-9][0-9]*)$' "$1" "a whole number of changed lines, or off"; shift 2 ;;
    --max-review-min) rl maxReviewMinutes "$2" "$OFFNUM" "$1" "a number of minutes, or off"; shift 2 ;;
    --max-test-percent) rl maxTestPercent "$2" "$OFFNUM" "$1" "a number (percent), or off"; shift 2 ;;
    --max-usd) rl maxUsd "$2" "$OFFNUM" "$1" "a number of dollars, or off"; shift 2 ;;
    --review-flags) [ "$2" = off ] || usage; for k in maxReviewMinutes maxTestPercent maxUsd; do rl "$k" off '^off$'; done; shift 2 ;;
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
    *) usage ;;
  esac
done
SCOPE=${SCOPE:-project}
case $PROFILE in claude|claude-openai) ;; *) echo "setup: --profile is claude (Claude does the review passes) or claude-openai (Codex does them)" >&2; usage ;; esac
case $SCOPE in project|machine) ;; *) usage ;; esac
for a in $ADDONS; do
  awk -F'\t' -v n="$a" '$1 == n { f = 1 } END { exit !f }' "$IL_ROOT/config/addons.tsv" \
    || die "--addons takes names from config/addons.tsv ($(grep -v '^#' "$IL_ROOT/config/addons.tsv" | cut -f1 | paste -sd' ' -)) or none, not '$a'. Nothing was changed"
  # serena is the add-on the hooks read: installing it turns its nudge on.
  [ "$a" != serena ] || SERENA=true
done
[[ ${PORT:-1} =~ ^[0-9]+$ ]] || usage
# Extra names the dashboard answers to (a tailnet's name for this machine). None by default: a name
# not listed is one another site may have pointed here, and gets a 403.
[[ ${HOSTS:-a} =~ ^[A-Za-z0-9.-]+(,[A-Za-z0-9.-]+)*$ ]] || { echo "setup: --hosts takes host names separated by commas" >&2; usage; }
# The Builder's model: no answer means the routing file's own; a name is one routing already names.
# No advisor is asked: every Builder runs with none, and a rerun drops one an older set-up stored.
[ -z "$BMODEL" ] || jq -e --arg a "$BMODEL" "$PP_ROUTE_JQ"' aliases | any(. == $a)' "$(pp_routing)" >/dev/null \
  || die "the Builder's model is one of $(jq -r "$PP_ROUTE_JQ"' aliases | join(", ")' "$(pp_routing)"), not '$BMODEL'. Nothing was changed"
# A Codex model id named at setup is the project's own, so a plugin update keeps it (paths.sh pp_codex_model).
# Only a Codex role takes one, and only an id: a bare family name would be looked up again.
for r in $(jq -r 'keys[]' <<<"$CMODELS"); do
  jq -e --arg r "$r" '.roles[$r].agent == "codex"' "$(pp_routing)" >/dev/null \
    || die "--codex-model takes a Codex role, one of $(jq -r '[.roles | to_entries[] | select(.value.agent == "codex") | .key] | join(", ")' "$(pp_routing)"), not '$r'. Nothing was changed"
  m=$(jq -r --arg r "$r" '.[$r]' <<<"$CMODELS")
  [[ $m =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]] && ! [[ $m =~ ^[a-z]+$ ]] \
    || die "--codex-model $r=$m: name a model id, such as gpt-6.1-sol, not a family or other text. Nothing was changed"
done
# Leaving fable out opts out of Fable, leaving every Codex model out opts out of Codex. A Claude model stays: it
# writes the plan. A Codex one only on the Claude+OpenAI profile, which has Codex.
for m in ${PMODELS//,/ }; do
  jq -e --arg m "$m" --arg p "$PROFILE" 'any(.roles[] | (.candidates // [.])[]; .model == $m and (.agent == "claude" or $p == "claude-openai"))' "$(pp_routing)" >/dev/null \
    || die "--plan-models takes models routing.json gives a seat ($(jq -r --arg p "$PROFILE" '[.roles[] | (.candidates // [.])[] | select(.agent == "claude" or $p == "claude-openai") | .model] | unique | join(", ")' "$(pp_routing)")), not '$m'. Nothing was changed"
done
[ -z "$PMODELS" ] || jq -e --arg l "$PMODELS" 'any(.roles[] | (.candidates // [.])[]; .agent == "claude" and IN(.model; ($l | split(",")[])))' "$(pp_routing)" >/dev/null \
  || die "--plan-models keeps at least one Claude model, the one that writes the plan. Nothing was changed"
# A fast plan seat is a plan role routing.json names; a Codex one needs the Codex home's fast tier, as the review pass does.
for r in ${PFAST//,/ }; do
  a=$(jq -r --arg r "$r" 'if ($r | startswith("plan-")) then .roles[$r].agent // empty else empty end' "$(pp_routing)")
  [ -n "$a" ] || die "--plan-fast takes plan seats, $(jq -r '[.roles | keys[] | select(startswith("plan-"))] | join(", ")' "$(pp_routing)"), not '$r'. Nothing was changed"
  [ "$a" != codex ] || [ "$PROFILE" != claude-openai ] || pp_codex_fast_home \
    || die "$r was set to fast, but ${CODEX_HOME:-$HOME/.codex}/config.toml has no service_tier = \"fast\" line. Add that line and run setup again, or leave $r out of --plan-fast. Nothing was changed"
done

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
[ -z "$o" ] || [ "$(pp_norm "$o")" = "$(pp_norm "$PP_MAIN")" ] \
  || die "the install record this checkout would use ($IL_PROJECT) belongs to another project, which is set up at $o: the two paths are one name once every odd character is a dash. Rename one checkout's folder, or uninstall the other first. Nothing was changed"
while IFS= read -r m; do
  o=$(jq -r '.project // empty' "$m" 2>/dev/null); n=${o##*/}
  [ -z "$o" ] || [ "$(pp_norm "$o")" = "$(pp_norm "$PP_MAIN")" ] || [ "${n//[^A-Za-z0-9_.-]/-}" != "$MINE" ] \
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
COMMANDECK_REVIEW_LOOP=$RL COMMANDECK_CODEX_MODELS=$CMODELS COMMANDECK_CODEX_FAST=false COMMANDECK_PASS=$PASS bash "$HERE/builder-codex-pass.sh" --preflight >/dev/null || die "the $PROFILE profile's review pass cannot run (above); nothing was changed"
[ "$PROFILE" != claude-openai ] || echo "setup: $(pp_codex_route)"
[ -L "$IL_LINK" ] || [ ! -e "$IL_LINK" ] || die "$IL_LINK is not a link; setup keeps a link to the plugin there. Move it aside. Nothing was changed"
for f in "$PP_MAIN/.claude/settings.json" "$PP_MAIN/.claude/settings.local.json" "$HOME/.claude/settings.json" "$IL_CODEX/hooks.json"; do
  [ ! -s "$f" ] || jq -e 'type == "object"' "$f" >/dev/null 2>&1 || die "$f is not a JSON object; fix it first. Nothing was changed"
done

# --- the manifest, before the first change ---
# At project scope the rules go where git never looks (IL_STATE): they name this machine's plugin folder.
SETTINGS=$PP_MAIN/.claude/settings.local.json SM=$IL_PROJECT
[ "$SCOPE" = project ] || { SETTINGS=$HOME/.claude/settings.json; SM=$IL_MACHINE; }
WATCH_JOB=$(bash "$HERE/main-watch.sh" --job-file) DASH_JOB=$(bash "$HERE/dashboard.sh" --job-file)
il_record "$IL_PROJECT" own "$IL_CONFIG" "$WATCH_JOB"
# A link setup made and no manifest records (one left by a lost manifest) is made again, and recorded as new.
il_has "$IL_MACHINE" "$IL_LINK" || [ -n "$PLAN" ] || rm -f "$IL_LINK"
il_record "$IL_MACHINE" own "$IL_LINK"
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
case $GCLAUDE$GRULES in *install*|*block*|*merge*) il_record "$IL_MACHINE" merge "$IL_GLOBAL" ;; esac
# The ponytail skill, unless the owner said no. A skill of that name the owner has, or the whole
# add-on, is the owner's: only a copy an earlier setup made is written again, or taken out on no.
PONY=$HOME/.claude/skills/ponytail PONY_OURS=
if il_has "$IL_MACHINE" "$PONY/SKILL.md" || { [ ! -e "$PONY" ] && [ ! -L "$PONY" ] \
  && ! jq -e '.enabledPlugins["ponytail@ponytail"] == true' "$HOME/.claude/settings.json" >/dev/null 2>&1; }; then
  PONY_OURS=1; [ "$PONYTAIL" = false ] || il_record "$IL_MACHINE" own "$PONY/SKILL.md" "$PONY/LICENSE"
fi
# No --addons answer: every add-on, each run, so each is updated to its latest. The ponytail plugin only when the
# owner has it on and wants ponytail: beside a ponytail skill it would load the same rules twice.
if [ -z "$ADDONS_SET" ]; then
  ADDONS=$(grep -v '^#' "$IL_ROOT/config/addons.tsv" | cut -f1 | { if [ "$PONYTAIL" != false ] && jq -e '.enabledPlugins["ponytail@ponytail"] == true' "$HOME/.claude/settings.json" >/dev/null 2>&1; then cat; else grep -vx ponytail; fi; } | paste -sd' ' -)
  # Installing serena turns its hooks on, as --addons serena does, unless an earlier or given answer says otherwise.
  SERENA=${SERENA:-true}
fi
if [ -n "$STATUS" ]; then
  il_record "$IL_MACHINE" merge "$HOME/.claude/settings.json"
  # The first status line setup replaces is the owner's; a second answer must not take the first for it.
  jq -e 'has("statusLine")' "$IL_MACHINE" >/dev/null \
    || il_set "$IL_MACHINE" --argjson was "$(jq -c '.statusLine // null' "$HOME/.claude/settings.json" 2>/dev/null || echo null)" '.statusLine = {was: $was}'
fi
il_set "$IL_PROJECT" --arg p "$PP_MAIN" --arg s "$SCOPE" --arg r "$IL_ROOT" --arg d "${DASHBOARD:-0}" '. + {project: $p, scope: $s, root: $r, dashboard: ($d == "1")}'

# --- the changes ---
# A remove is done once: a saved remove replayed by an update would take out lines another project added.
AUTO_DO=${AUTO:-leave}; [ "$AUTO" != remove ] || AUTO=leave
# What setup really writes in the project: il_write notes each path whose content is new or different.
# The exclude file is also written by worktree-setup.sh, by itself, so it is compared at the end.
IL_WROTE=$(mktemp); export IL_WROTE; trap 'rm -f "$IL_WROTE" "$IL_WROTE".*; [ -n "$PLAN" ] || rm -f "$ASKING"' EXIT
EXCLUDE_WAS=$(il_sha "$IL_EXCLUDE" 2>/dev/null || true)
jq -n --argjson v "$IL_VERSION" --arg profile "$PROFILE" --arg strict "$STRICT" --arg serena "$SERENA" --arg standard "$STANDARD" \
  --arg test "$TEST" --arg name "$NAME" --arg persona "$PERSONA" --arg bm "$BMODEL" --arg be "$BEFFORT" --arg bc "$BCLEAR" --arg sz "$SIZING" --arg pm "$PMODELS" --arg pf "$PFAST" --arg fast "$FAST" --argjson cm "$CMODELS" --argjson rl "$RL" --argjson gen "$GEN" --argjson cuts "$CUTS" \
  --argjson own "$(jq -cn --arg s "$OWNS" --arg m "$OWNM" '{"AGENT_STARTUP.md": $s, ".claude/main-session.md": $m} | with_entries(select(.value != ""))')" \
  --arg rules "$RULES" --argjson md "$DROPS" --arg pony "$PONYTAIL" --arg cache "$CACHE" --arg rcache "$RCACHE" --arg auto "$AUTO" '
  {version: $v, profile: $profile, strictHooks: ($strict == "true"), serena: ($serena == "true"), standardContext: ($standard == "true"),
   codexFast: ($fast == "true")}
  + (if $test == "" then {} else {testCommand: $test} end)
  + (if $gen == null then {} else {generatedFiles: $gen} end)
  + ({model: $bm, effort: $be, clearLine: $bc} | with_entries(select(.value != "")) | if . == {} then {} else {builder: .} end)
  + (if $sz == "" then {} else {issueSizing: $sz} end)
  + (if $pm == "" then {} else {planModels: ($pm | split(",") | map(select(. != "")))} end)
  + (if $pf == "" then {} else {planFast: ($pf | split(",") | map(select(. != "")))} end)
  + (if $cm == {} then {} else {codexModels: $cm} end)
  + (if $rl == {} then {} else {reviewLoop: $rl} end)
  + (if $own == {} then {} else {ownFiles: $own} end)
  + (if $rules == "" then {} else {rules: $rules} end)
  + (if $md == {} then {} else {mergeDecisions: $md} end)
  + {ponytail: ($pony != "false")}
  + (if $cache == "" then {} else {cacheTtl: $cache} end)
  + (if $auto == "" then {} else {autoMode: $auto} end)
  + $cuts
  + {chiefOfStaff: ({name: $name, persona: $persona, cacheTtl: $rcache} | with_entries(select(.value != "")))}' | il_write "$IL_CONFIG"
if [ -z "$PLAN" ]; then ln -sfn "$IL_ROOT" "$IL_LINK"
elif [ "$(readlink "$IL_LINK" 2>/dev/null)" != "$IL_ROOT" ]; then echo "plan: would point $IL_LINK at $IL_ROOT"; fi
# allow_out <manifest> <settings file> -- the plugin's rules out of a file setup put them in before.
allow_out() { ! jq -e --arg p "$2" '(.entries[$p].added // []) != []' "$1" >/dev/null 2>&1 || il_allow_set "$1" "$2" '[]'; }
# A new scope moves the rules (a setup before 0.7.0 kept the project's in settings.json); the
# machine's file keeps them while another project is set up at machine scope.
for f in "$PSET" "$PP_MAIN/.claude/settings.local.json"; do [ "$f" = "$SETTINGS" ] || allow_out "$IL_PROJECT" "$f"; done
OTHERS=$(il_projects | while IFS= read -r m; do [ "$m" = "$IL_PROJECT" ] || jq -r 'select(.scope == "machine") | .project' "$m" 2>/dev/null; done || true)
[ "$SCOPE" = machine ] || [ -n "$OTHERS" ] || allow_out "$IL_MACHINE" "$HOME/.claude/settings.json"
il_allow_set "$SM" "$SETTINGS" "$(il_allow "$IL_ROOT")"
[ -z "$WAS" ] || [ "$WAS" = "$SCOPE" ] || echo "permissions: moved from $WAS scope to $SCOPE scope ($SETTINGS)"
il_workflows "$IL_PROJECT" "$PSET"
! pp_route_json orchestrator | jq -e '.advisor == null' >/dev/null || il_advisor_off "$IL_PROJECT" "$PSET"
[ "$CACHE" != 5m ] || il_cache_ttl "$IL_PROJECT" "$PSET"
il_auto_mode "$IL_MACHINE" "$HOME/.claude/settings.json" "$AUTO_DO"
il_test_audit "$IL_ROOT" "$WF"
# Git never sees the running state, so the main checkout stays clean while the plugin runs.
il_lines "$IL_PROJECT" "$IL_EXCLUDE" "${IL_STATE[@]}"
if [ "$PROFILE" = claude-openai ]; then
  il_block "$IL_AGENTS" "$IL_ROOT/templates/codex-instructions.md"
  il_codex_hooks "$IL_ROOT"
  il_notify "$IL_ROOT"
  il_notify_repoint "$IL_MACHINE" "$NWRAP"
  if [ -n "$PLAN" ]; then echo "plan: would mark the plugin's Codex hooks trusted in $IL_CODEX/config.toml"
  else python3 "$HERE/codex-hook-trust.py" "$IL_CODEX" >/dev/null; fi
fi
if [ -n "$PLAN" ]; then
  if [ -n "$DASHBOARD" ]; then echo "plan: would register this project with the dashboard and install its job ($DASH_JOB), serving http://${BIND:-127.0.0.1}:${PORT:-<a free port>}/"
  elif jq -e '.registered == true' "$IL_PROJECT" >/dev/null 2>&1; then echo "plan: would take this project off the dashboard"; fi
  [ -e "$WATCH_JOB" ] || echo "plan: would install the main-watch job ($WATCH_JOB), which wakes this session when a build needs it"
elif [ -n "$DASHBOARD" ]; then
  # A line the owner put there before setup is the owner's: uninstall takes out only setup's own.
  pp_registered || il_set "$IL_PROJECT" '.registered = true'
  bash "$HERE/dashboard.sh" --register "$PP_MAIN" >/dev/null
  COMMANDECK_DASHBOARD_BIND=${BIND:-127.0.0.1} COMMANDECK_DASHBOARD_PORT=$PORT COMMANDECK_DASHBOARD_HOSTS=$HOSTS bash "$HERE/dashboard.sh" --install >/dev/null
  PORT=$(grep -oE 'COMMANDECK_DASHBOARD_PORT[^0-9]*[0-9]+' "$DASH_JOB" | grep -oE '[0-9]+$' | head -1)
  il_set "$IL_MACHINE" --arg b "${BIND:-127.0.0.1}" --arg p "$PORT" --arg h "$HOSTS" '.dashboard = {bind: $b, port: $p, hosts: $h}'
else
  # Declined after it was on: the project comes off the dashboard. The job is every project's: it stays until the last one leaves.
  ! jq -e '.registered == true' "$IL_PROJECT" >/dev/null 2>&1 || ! pp_registered \
    || { bash "$HERE/dashboard.sh" --unregister "$PP_MAIN" >/dev/null; il_set "$IL_PROJECT" 'del(.registered)'
         grep -q '[^[:space:]]' "$HOME/.commandeck/dashboard/projects" 2>/dev/null || bash "$HERE/dashboard.sh" --uninstall >/dev/null; }
fi
[ -n "$PLAN" ] || bash "$HERE/main-watch.sh" --install >/dev/null
il_global "$GCLAUDE" claude-md "$IL_ROOT/templates/global-claude.md" --global-claude
il_global "$GRULES" rules "$IL_ROOT/templates/global-rules.md" --global-rules
D=$(jq -r 'to_entries[] | select(.value == "keep-mine" or .value == "keep-both") | (if .value == "keep-mine" then "--drop" else "--keep" end), .key' <<<"$DROPS")
for f in "${OWN[@]}"; do
  c=$OWNS; [ "$f" = AGENT_STARTUP.md ] || c=$OWNM
  # shellcheck disable=SC2086 # --drop/--keep and ids of 8 hex digits each
  il_own "$IL_PROJECT" "$PP_MAIN/$f" "$IL_ROOT/templates/${f#.claude/}" "$c" $D
done
if [ "$PONYTAIL" = false ]; then
  if [ -n "$PONY_OURS" ] && [ -e "$PONY/SKILL.md" ]; then
    if [ -n "$PLAN" ]; then echo "plan: would remove the ponytail skill an earlier setup installed ($PONY)"
    else rm -f "$PONY/SKILL.md" "$PONY/LICENSE"; rmdir "$PONY" 2>/dev/null || true; fi
  fi
elif [ -n "$PONY_OURS" ]; then
  for f in SKILL.md LICENSE; do il_write "$PONY/$f" < "$IL_ROOT/templates/ponytail/$f"; done
fi
if [ -n "$STATUS" ]; then
  ST=$(il_cat "$HOME/.claude/settings.json" 2>/dev/null) || ST=; [ -n "${ST//[[:space:]]/}" ] || ST='{}'
  ST=$(jq --arg c "$STATUS" '.statusLine = {type: "command", command: $c}' <<<"$ST") && il_write "$HOME/.claude/settings.json" <<<"$ST"
  il_set "$IL_MACHINE" --argjson set "$(jq -c .statusLine <<<"$ST")" '.statusLine.set = $set'
fi

# --- what the owner should know: said in a plan and at the end of a run alike ---
addon_cmd() { awk -F'\t' -v n="$1" '$1 == n { print $2 }' "$IL_ROOT/config/addons.tsv"; }
NOTES=() NEED=()
case $CACHE in 5m|leave) ;; *) NEED+=("Prompt cache: not answered since 0.15.0; /commandeck:setup asks, or: setup.sh --cache-ttl 5m|leave") ;; esac
[ -z "$NAME" ] || case $RCACHE in 1h|leave) ;; *) NEED+=("Relay prompt cache: not answered since 0.15.0; /commandeck:setup asks, or: setup.sh --relay-cache-ttl 1h|leave") ;; esac
[ -z "$SERENA_AUTO" ] || NOTES+=("serena: on, because a serena server is configured on this machine (--no-serena turns it off)")
for f in "${OWN[@]}"; do
  c=$OWNS flag=--own-startup; [ "$f" = AGENT_STARTUP.md ] || c=$OWNM flag=--own-main-session
  [ ! -f "$PP_MAIN/$f" ] || case $c in
    replace) NOTES+=("$f: yours stays on disk; sessions load the plugin's instead") ;;
    merge) NOTES+=("$f: yours loads, with the plugin's rules it lacked added in a marked block") ;;
    *) NOTES+=("$f: yours loads instead of the plugin's whole version (to change that: $flag replace or merge)") ;;
  esac
done
[ -e "$PP_MAIN/.claude/paved-road.md" ] || NOTES+=("paved road: no .claude/paved-road.md; start it from $IL_ROOT/templates/paved-road.md, which also says what .claude/paved-road-areas.tsv holds")
[ "$RULES" != merge ] || NOTES+=("rules: sessions leave out the plugin's rules your CLAUDE.md and .claude/rules/ already state word for word$(n=$(jq '[.[] | select(. == "keep-mine")] | length' <<<"$DROPS"); [ "$n" = 0 ] || echo ", and the $n you keep your own wording for")")

if [ -n "$PLAN" ]; then
  for a in $ADDONS; do
    c=$(addon_cmd "$a")
    if [ "$a" = codebase-memory ] && command -v codebase-memory-mcp >/dev/null; then echo "plan: would update the add-on codebase-memory if no session is open, then check that a new session reaches it"
    else case $c in see\ *) echo "plan: would list the add-on $a: $c" ;; *) echo "plan: would install the add-on $a, or update it to its latest, in $PP_MAIN: $c" ;; esac; fi
  done
  [ -z "$NAME" ] || [ -d "$PP_WORKSPACES/Chief-of-Staff" ] || echo "plan: would create $NAME's worktree $PP_WORKSPACES/Chief-of-Staff and open its pane"
  [ -s "$PP_RUN_FILE" ] || echo "plan: would use this terminal's Orca run, or create one for this project"
  for n in ${NOTES[@]+"${NOTES[@]}"}; do echo "plan: $n"; done
  echo "plan: that is every change; nothing was written. The same command without --plan makes them."
  exit 0
fi

echo "Done:"
echo "commandeck $(jq -r .version "$IL_ROOT/.claude-plugin/plugin.json") is set up for $PP_MAIN ($PROFILE profile, permissions in $SETTINGS)"
if [ -n "$DASHBOARD" ]; then echo "dashboard: http://${BIND:-127.0.0.1}:$PORT/"; else echo "dashboard: off (--dashboard turns it on)"; fi

# --- the project's Orca run: made once here, or the one command that makes it ---
# The board refuses to work without one. A run already recorded, or bound to this terminal, is the project's.
# Either is written down as board.sh writes it, so a setup from another terminal makes no second run.
run_id() { jq -r "$1"' // empty' 2>/dev/null | grep -xE '[A-Za-z0-9_-]+' || true; }
keep_run() { mkdir -p "$PP_SCRATCH" && printf '%s\n' "$RUN" > "$PP_RUN_FILE"; }
RUN=$( { tr -d '[:space:]' < "$PP_RUN_FILE"; } 2>/dev/null || true)
[ -n "$RUN" ] || { RUN=$(orca-ide orchestration run-current --json 2>/dev/null | run_id .result.run.id || true); [ -z "$RUN" ] || keep_run; }
if [ -n "$RUN" ]; then echo "Orca run: $RUN (already there; none was created)"
elif RUN=$(orca-ide orchestration run-create --objective "${PP_MAIN##*/}" --json 2>/dev/null | run_id '.result.run.id // .result.id') && [ -n "$RUN" ]; then
  keep_run
  echo "Orca run: created $RUN for this project and bound this terminal to it"
else
  NEED+=("Orca run: none was created (Orca did not answer with a run). Run this in the main checkout's session: orca-ide orchestration run-create --objective $(printf '%q' "${PP_MAIN##*/}")")
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
    NEED+=("Relay: $NAME has no pane yet. Run, in this order:")
    for s in "${STEPS[@]}"; do NEED+=("  $s"); done
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
# codebase-memory runs one daemon for every session, and it refuses a client of another version: it is updated only
# while no session holds a client (the daemon is stopped first, and the next client starts it on the new version).
# Whatever happened, a new client must then get its tool list, or new sessions would start without it.
cbm_update() {
  local was now K=--cbm-daemon-internal
  was=$(codebase-memory-mcp --version 2>/dev/null) || was='version unknown'
  if pgrep -f 'codebase-memory-mcp$' >/dev/null; then
    NEED+=("add-on codebase-memory: not updated ($was): open sessions use its daemon, which refuses a client of another version. Close every Claude and Codex session, then run: pkill -f -- $K; codebase-memory-mcp update -y; then run setup again")
  elif { pkill -f -- "$K"; codebase-memory-mcp update -y >/dev/null 2>&1; }; then
    now=$(codebase-memory-mcp --version 2>/dev/null) || now='version unknown'
    echo "add-on codebase-memory: updated ($was to $now); restart any Claude or Codex session that was open before"
  else NEED+=("add-on codebase-memory: the update FAILED; to try again with every session closed: pkill -f -- $K; codebase-memory-mcp update -y"); fi
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"commandeck-setup","version":"0"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
    | timeout 30 codebase-memory-mcp 2>/dev/null | jq -eR 'fromjson? | select(.id == 2) | .result.tools | length > 0' >/dev/null \
    || NEED+=("add-on codebase-memory: a new session cannot reach it (FAILED: its server gave no tool list). Close every session, run pkill -f -- $K, start one session and check that its codebase-memory tools load")
}
INSTALLED=' '
for a in $ADDONS; do
  c=$(addon_cmd "$a")
  if [ "$a" = codebase-memory ] && command -v codebase-memory-mcp >/dev/null; then cbm_update; INSTALLED+="$a "; continue; fi
  case $c in
    # One with no one-line installer is the owner's to install: under Needs you only when asked for by name.
    see\ *) [ -z "$ADDONS_SET" ] || NEED+=("add-on $a: it has no one-line installer; $c") ;;
    *) if out=$(cd "$PP_MAIN" && bash -c "$c" 2>&1); then echo "add-on $a: installed at its latest, for $PP_MAIN ($c)"; INSTALLED+="$a "
       else NEED+=("add-on $a: the install FAILED ($(tail -n 1 <<<"$out")); to try again, run in $PP_MAIN: $c"); fi ;;
  esac
done
# Read back from the config written above, so this line and the hooks agree.
echo "serena (read-tracker nudge and pane-budget gate): $(jq -r 'if .serena then "on" else "off" end' "$IL_CONFIG")"
if [ "$PONYTAIL" = false ]; then echo "ponytail skill: off (--ponytail turns it on)"
elif [ -n "$PONY_OURS" ]; then echo "ponytail skill: installed ($PONY)"
else echo "ponytail skill: the one already on this machine was left as it is"; fi
# Read back from the file, so an owner's own value shows as what it is.
echo "prompt cache: main $(jq -r '.promptCacheTtl // "default"' "$PSET" 2>/dev/null || echo default), subagents $(jq -r '.subagentPromptCacheTtl // "default"' "$PSET" 2>/dev/null || echo default)"
for n in ${NOTES[@]+"${NOTES[@]}"}; do echo "$n"; done
# The config setup wrote is the project's, and so is a merge into the owner's startup files: a unit's
# worktree has them only once git holds them. Setup never commits.
# After the relay's worktree is set up: its pane's TTL as Claude Code will read it, and the main checkout's local file.
while IFS= read -r L; do [ "${L%% *}" != warn ] || NEED+=("${L#warn }"); done < <(il_cache_ttl_report; il_shadow_report)
OWED=()
for f in "$IL_CONFIG" "$PSET" "$IL_AGENTS" "${OWN[@]/#/$PP_MAIN/}"; do
  f=${f#"$PP_MAIN"/}
  [ -e "$PP_MAIN/$f" ] || continue
  { git -C "$PP_MAIN" cat-file -e "HEAD:$f" && git -C "$PP_MAIN" diff --quiet HEAD -- "$f"; } 2>/dev/null || OWED+=("$f")
done
[ ${#OWED[@]} = 0 ] || NEED+=("not committed yet: ${OWED[*]}. Commit them, so every unit's worktree has them: git -C $(printf '%q' "$PP_MAIN") add -f -- ${OWED[*]} && git -C $(printf '%q' "$PP_MAIN") commit -m 'chore: commandeck setup' -- ${OWED[*]}")
echo
if [ ${#NEED[@]} = 0 ]; then echo "Needs you: nothing."
else echo "Needs you:"; for n in "${NEED[@]}"; do echo "  $n"; done; fi
echo
echo "Optional. Add-ons not installed; each line is the command and what it costs (setup.sh --addons <name> installs one):"
while IFS=$'\t' read -r name cmd cost; do
  case $name in ''|'#'*) continue ;; esac
  case $INSTALLED in *" $name "*) continue ;; esac
  printf '  %-17s %s\n  %-17s   cost: %s\n' "$name" "$cmd" '' "$cost"
done < "$IL_ROOT/config/addons.tsv"
ST=$(jq -c '.statusLine // empty' "$HOME/.claude/settings.json" 2>/dev/null || true)
if [ -n "$STATUS" ]; then echo "Status line: set to ${ST}; the one before it comes back at uninstall."
else echo "Status line: left as it is (${ST:-none set}). To set one: bash $(printf '%q' "$HERE")/setup.sh --status-line '<command>'; the one before it is recorded and comes back at uninstall."; fi
echo
echo "To change an answer later: /commandeck:setup asks again, or run setup.sh with only that flag (each one left out keeps its answer)."
echo "check it: bash $(printf '%q' "$HERE")/doctor.sh    undo it: bash $(printf '%q' "$HERE")/uninstall.sh"

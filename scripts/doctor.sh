#!/usr/bin/env bash
# doctor.sh -- check the plugin's wiring for the project this runs in. One line
# per check: `ok`, `warn` (works, but look) or `FAIL` (a part of the workflow
# does not run), each FAIL with the command that fixes it. Exit 1 on any FAIL.
# It changes nothing. Checked: the tools on PATH, the plugin's version and hook
# files, what the hooks put into a session, the project's config and install
# manifest, that Orca answers, the dashboard and the watcher, and for the
# claude-openai profile the review pass and Codex's hooks, trust and notify.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/requirements.sh"
RC=0
ok() { printf 'ok   %s\n' "$*"; }
warn() { printf 'warn %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; RC=1; }
# tools [profile] -- the one requirements check, with the two groups setup prints under its FAIL line.
tools() {
  if req_check setup "${1:-}"; then ok "tools on PATH"
  else bad "tools: requirements are missing. Setup installs what it can on a yes: bash $(printf '%q' "$HERE")/setup.sh --install-missing"; req_report; fi
}
# On a Mac paths.sh refuses to load when a tool every script needs is missing: a tools failure, not a missing project.
[ "$REQ_UNAME" != Darwin ] || req_check all || { tools; exit 1; }
. "$HERE/paths.sh" || { echo "FAIL project: not in a project; run this in the checkout setup was run in"; exit 1; }
. "$HERE/install-lib.sh"

tools "$(jq -r '.profile // empty' "$IL_CONFIG" 2>/dev/null)"

ok "plugin $(jq -r .version "$IL_ROOT/.claude-plugin/plugin.json") at $IL_ROOT"
H=$IL_ROOT/hooks/hooks.json
if ! jq -e . "$H" >/dev/null 2>&1; then bad "hooks: $H does not parse; reinstall the plugin"
else
  GONE=$(jq -r '.hooks[][].hooks[].command' "$H" | grep -oE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9_./-]+' | sort -u | sed "s|^\${CLAUDE_PLUGIN_ROOT}|$IL_ROOT|" \
    | while IFS= read -r f; do [ -x "$f" ] || printf '%s ' "${f#"$IL_ROOT"/}"; done)
  if [ -z "$GONE" ]; then ok "hooks: every registered hook file is there and can run"
  else bad "hooks: missing or not executable: ${GONE}-- reinstall the plugin"; fi
fi
if OUT=$(bash "$HERE/startup-size.sh" 2>&1) && OUT2=$(bash "$HERE/startup-size.sh" --per-prompt 2>&1); then
  ok "hook output: session start and per prompt are under 10240 bytes"
else bad "hook output: over the 10240-byte line, where the model sees only a preview: $(printf '%s\n%s' "$OUT" "${OUT2:-}" | tail -3 | paste -sd' ' -)"; fi
if LINT=$(python3 "$HERE/instruction-lint.py" --repo "$PP_MAIN" 2>&1); then ok "instruction files"
else warn "instruction files: $(wc -l <<<"$LINT" | tr -d ' ') flagged; see: python3 $HERE/instruction-lint.py --repo $PP_MAIN"; fi

PROFILE=
if [ ! -e "$IL_CONFIG" ]; then bad "project: $PP_MAIN is not set up; run: bash $(printf '%q' "$HERE")/setup.sh --profile claude|claude-openai"
elif [ "$(jq -r '.version // empty' "$IL_CONFIG" 2>/dev/null)" != "$IL_VERSION" ]; then
  bad "config: $IL_CONFIG is version $(jq -r '.version // "(none)"' "$IL_CONFIG" 2>/dev/null), and this plugin knows version $IL_VERSION only"
else
  PROFILE=$(jq -r .profile "$IL_CONFIG")
  ok "config: version $IL_VERSION, $PROFILE profile, strict hooks $(jq -r '.strictHooks // false' "$IL_CONFIG")"
  # The Builder answers as their readers take them: the launch, the prompt hook, the launch's sizing check.
  # Each value's source (issue 293), "the default" being routing's.
  src() { local s; s=$(pp_option "$1" source); [ "$s" != default ] || s="the default"; echo "from $s"; }
  if V=$(pp_route_json builder 2>&1); then ok "builder: $(jq -r '.model' <<<"$V") ($(src builderModel)), effort $(jq -r '.effort' <<<"$V") ($(src builderEffort)); setup.sh --builder-model, --builder-effort, or /config"; else bad "builder: $(tail -1 <<<"$V")"; fi
  if V=$(. "$IL_ROOT/hooks/lib/project.sh" && pp_builder_clear_line "$PP_MAIN" 2>&1); then ok "builder clear line: $V (tokens of context, or off; setup.sh --builder-clear-line)"; else bad "builder clear line: $V"; fi
  if V=$(pp_issue_sizing 2>&1); then ok "issue sizing: $V (tokens to read, or off; setup.sh --issue-sizing)"; else bad "issue sizing: $V"; fi
  # The merge check runs on a copy that links main's node_modules (merge-unit-local.sh).
  ! jq -r '.testCommand // empty' "$IL_CONFIG" | grep -qE '(^|[^[:alnum:]_-])(npm (ci|install)|pnpm install|yarn install)([^[:alnum:]_-]|$)' \
    || warn "check command: it installs packages, and the merge check shares the main checkout's node_modules, so each merge rewrites main's packages; install in the project's setup, not in the check"
  ok "full suite before the final review: $([ "$(pp_option fullSuiteBeforeFinal)" = true ] && echo on || echo off) (setup.sh --full-suite on|off, or /config)"
  while IFS= read -r L; do ok "${L#ok }"; done < <(il_options_report)
  if [ -s "$IL_PROJECT" ]; then ok "install manifest: $IL_PROJECT"
  else bad "install manifest: none for this project, so uninstall cannot put it back; run: bash $(printf '%q' "$HERE")/setup.sh"; fi
  [ "$(jq -r '.root // empty' "$IL_PROJECT" 2>/dev/null)" = "$IL_ROOT" ] || [ ! -s "$IL_PROJECT" ] \
    || bad "plugin folder: setup ran from $(jq -r .root "$IL_PROJECT") and the plugin is now at $IL_ROOT; run: bash $(printf '%q' "$HERE")/update.sh"
  # The project's own copy of a startup file loads instead of the plugin's whole version (agent-startup-context.sh).
  for f in AGENT_STARTUP.md .claude/main-session.md; do
    [ -f "$PP_MAIN/$f" ] || continue
    case $(jq -r --arg f "$f" '.ownFiles[$f] // empty' "$IL_CONFIG") in
      replace) ok "startup file: sessions load the plugin's $f; the project's own stays on disk, unread" ;;
      merge) ok "startup file: the project's own $f loads, with the plugin's rules it lacked in a marked block" ;;
      *) warn "startup file: the project's own $f loads instead of the plugin's whole version; to choose: bash $(printf '%q' "$HERE")/setup.sh --own-$([ "$f" = AGENT_STARTUP.md ] && echo startup || echo main-session) replace|merge|skip" ;;
    esac
  done
fi

# Running state that git tracks leaves the main checkout changed after every write.
# A shared template (.claude/briefs/_*) is the project's to track: the review pass commits it.
TRACKED=() TEMPLATES="':(exclude).claude/briefs/_*'"
for p in "${IL_STATE[@]}"; do [ -z "$(git -C "$PP_MAIN" ls-files -- "$p" ':(exclude).claude/briefs/_*' | head -1)" ] || TRACKED+=("$p"); done
[ ${#TRACKED[@]} = 0 ] || warn "running state: git tracks ${TRACKED[*]}, which the plugin writes as it runs; untrack and keep the files: git -C $(printf '%q' "$PP_MAIN") rm -r --cached -- ${TRACKED[*]} $TEMPLATES"

if orca-ide worktree ps --json 2>/dev/null | jq -e . >/dev/null 2>&1 && orca-ide terminal list --json 2>/dev/null | jq -e . >/dev/null 2>&1; then ok "orca: worktree ps and terminal list answer"
else bad "orca: orca-ide does not answer 'worktree ps --json' and 'terminal list --json'; start Orca"; fi

if [ -n "$PROFILE" ]; then
  # Setup's stored answer: a project that declined the dashboard is not failed for lacking it.
  if [ "$(jq -r '.dashboard' "$IL_PROJECT" 2>/dev/null)" = false ]; then ok "dashboard: declined for this project (setup.sh --no-dashboard)"
  else
    if pp_registered; then ok "dashboard registry"
    else bad "dashboard registry: this project is not on the dashboard; run: bash $(printf '%q' "$HERE")/dashboard.sh --register $PP_MAIN"; fi
    if bash "$HERE/dashboard.sh" --status >/dev/null 2>&1; then ok "dashboard job"
    else bad "dashboard job: not running; run: bash $(printf '%q' "$HERE")/dashboard.sh --install"; fi
    # A 403 is the dashboard reached by a name that is not on its list; the list is closed until the owner adds one.
    ok "dashboard names: this machine's own$(jq -r '.dashboard.hosts // "" | if . == "" then "" else " and " + . end' "$IL_MACHINE" 2>/dev/null); a 403 under another name: bash $(printf '%q' "$HERE")/setup.sh --hosts <name>[,<name>]"
  fi
  # The add-on servers the hooks can use. Reported only: the owner installs them (setup prints the commands).
  for s in serena codebase-memory; do
    if jq -e --arg s "$s" --arg p "$PP_MAIN" '.mcpServers[$s] // .projects[$p].mcpServers[$s]' "${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json" >/dev/null 2>&1 \
      || jq -e --arg s "$s" '.mcpServers[$s]' "$PP_MAIN/.mcp.json" >/dev/null 2>&1; then ok "add-on server $s: present"
    else ok "add-on server $s: not installed (optional; setup.sh --addons $s installs it)"; fi
  done
  L=$(il_tool_search_report)
  if [ "${L%% *}" = ok ]; then ok "${L#ok }"; else warn "${L#warn }"; fi
  # A pointer only: turning skills off is the owner's call.
  ok "skills: $(jq '[.enabledPlugins // {} | to_entries[] | select(.value == true)] | length' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" 2>/dev/null || echo 0) plugins enabled; each model-invocable skill's description loads in every session; run /skill-doctor to see each one's cost and use"
  # The value the hooks read, the one setup reported.
  ok "serena hooks (read-tracker nudge and pane-budget gate): $(jq -r 'if .serena then "on" else "off" end' "$IL_CONFIG" 2>/dev/null)"
  if MW=$(bash "$HERE/main-watch.sh" --status 2>&1); then ok "main-watch"
  else bad "main-watch: not running, so nothing wakes the orchestrator; run: bash $(printf '%q' "$HERE")/main-watch.sh --install"; fi
  PASS=claude; [ "$PROFILE" != claude-openai ] || PASS=codex
  if ERR=$(COMMANDECK_PASS=$PASS bash "$HERE/builder-codex-pass.sh" --preflight 2>&1 >/dev/null); then ok "review pass ($PASS)"
  else bad "review pass: $(tail -1 <<<"$ERR")"; fi
  # No tomllib is already the "FAIL tools" line: a second line, marked ok, would say it twice.
  [ "$PASS" != codex ] || ! python3 -c 'import tomllib' 2>/dev/null || ok "codex route: $(pp_codex_route)"
fi
while IFS= read -r L; do if [ "${L%% *}" = ok ]; then ok "${L#ok }"; else warn "${L#warn }"; fi; done < <(il_auto_mode_report)
while IFS= read -r L; do if [ "${L%% *}" = ok ]; then ok "${L#ok }"; else warn "${L#warn }"; fi; done < <(il_cache_ttl_report)
while IFS= read -r L; do if [ "${L%% *}" = ok ]; then ok "${L#ok }"; else warn "${L#warn }"; fi; done < <(il_shadow_report)
if [ "$PROFILE" = claude-openai ]; then
  N=$(il_codex_count "$IL_ROOT") ALL=$(il_codex_count)
  if [ "$N" = 5 ] && [ "$ALL" = 5 ]; then ok "codex hooks: five entries in $IL_CODEX/hooks.json run this plugin"
  else bad "codex hooks: $N of 5 entries in $IL_CODEX/hooks.json run $IL_ROOT ($ALL of the plugin's in all); run: bash $(printf '%q' "$HERE")/update.sh"; fi
  if ERR=$(python3 "$HERE/codex-hook-trust.py" --check "$IL_CODEX" 2>&1); then ok "codex trust"
  else bad "codex trust: $(grep -c 'not trusted' <<<"$ERR") of the plugin's entries are not trusted, and each Codex pane would open on the review menu; run: bash $(printf '%q' "$HERE")/update.sh"; fi
  L=$(il_notify_report)
  if [ "${L%% *}" = ok ]; then ok "${L#ok }"; else warn "${L#warn }"; fi
fi
exit $RC

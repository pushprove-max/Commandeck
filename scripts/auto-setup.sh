#!/usr/bin/env bash
# auto-setup.sh --args claude-openai|claude | --report | --sources | --global-preview <staging folder>
# Auto Setup's half of /commandeck:setup: the profile and the detected values as setup.sh's flags, and the owner's rule
# files for the skill to merge. It writes nothing but the staging folder (--sources empties it).
# --args prints setup.sh's flags for the profile, one argument a line: --profile, --scope project, every
# config/recommended.json option with config/auto-profile.json's overrides as --option <key>=<value>, the profile's
# flags, then the detected values (the merge check, the typecheck, the screen folders, the lockfile rule, the context
# window). setup.sh --auto <profile> puts them ahead of its own flags, so a flag given there beats one here.
# --report [detected|dashboard] prints each detected value with where it came from, then the dashboard's address and
# the one command that opens it to the network once a password is stored (detected or dashboard: that half only).
# --sources empties the staging folder and prints, one a line and tab-separated: `staging <folder>`,
# `template <name> <path>` for the plugin's four rule templates, and `file|linked <key> <path>` for each owner rule file
# (il_rule_sources). The skill writes each merged file into the folder under its key, and conflicts.tsv.
# --global-preview <folder> prints the global CLAUDE.md as it is now (the plugin's blocks out) against the staged
# global/CLAUDE.md (with none staged: the file needs no change), then one CONFLICT: line per conflicts.tsv row for it.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/requirements.sh"
. "$HERE/paths.sh" || exit 1
. "$HERE/host-services.sh"
. "$HERE/install-lib.sh"
usage() { echo "usage: auto-setup.sh --args claude-openai|claude | --report | --sources | --global-preview <staging folder>" >&2; exit 2; }
STAGE=$PP_SCRATCH/auto-rules

# detect -- one line per detected value: <flag>, <value>, <where it came from>, split by US (\037), which, unlike a
# tab, keeps an empty value a field of its own.
US=$'\037'
out() { printf '%s\037%s\037%s\n' "$1" "$2" "$3"; }
detect() {
  local pj=$PP_MAIN/package.json t tm w tc cm f
  t=$(jq -r '.scripts.test // empty | strings' "$pj" 2>/dev/null) || t=
  # npm init's placeholder fails on purpose: it is no test. The script itself is never sent: `npm test` runs it.
  case $t in *[![:space:]]*) ;; *) t= ;; esac
  case $t in *'no test specified'*) t= ;; esac
  if [ -n "$t" ]; then tm='npm test' w='package.json test script'
  elif grep -qE '^test[[:space:]]*:' "$PP_MAIN/Makefile" 2>/dev/null; then tm='make test' w='Makefile test target'
  else tm= w='no package.json test script or Makefile test target'; fi
  out --test-command "$tm" "$w"
  if [ -n "$tm" ]; then out --full-suite on 'the merge check, run once per build'; else out --full-suite off 'no merge check to run'; fi
  tc=$(jq -r '.scripts.typecheck // empty | strings' "$pj" 2>/dev/null) || tc=
  if [ -n "$tc" ]; then out --typecheck-command 'npm run typecheck' 'package.json typecheck script'
  elif [ -f "$PP_MAIN/tsconfig.json" ]; then out --typecheck-command 'npx tsc --noEmit' 'tsconfig.json at the root'
  else out --typecheck-command '' 'no typecheck script or root tsconfig.json'; fi
  if [ -d "$PP_MAIN/web/src" ]; then out --screen-paths web/src/ 'the web/src/ folder'; else out --screen-paths '' 'no web/src/ folder'; fi
  out --lockfile-deny on 'setup adds a rule for each lockfile git tracks'
  # The model setting as setup.sh --questions begin reads it: ANTHROPIC_MODEL, else the nearest settings file's.
  cm=${ANTHROPIC_MODEL:-$(for f in "$PP_MAIN/.claude/settings.local.json" "$PP_MAIN/.claude/settings.json" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"; do jq -r '.model // empty' "$f" 2>/dev/null; done | head -1)}
  case $cm in
    *'[1m]') out --no-standard-context '' "1M, the model setting $cm ends in [1m]" ;;
    '') out --standard-context '' '200K, no model setting found' ;;
    *) out --standard-context '' "200K, the model setting $cm does not end in [1m]" ;;
  esac
}

case ${1-} in
  --args)
    case ${2-} in claude-openai|claude) ;; *) usage ;; esac
    P=$IL_ROOT/config/auto-profile.json
    printf '%s\n' --profile "$2" --scope project
    # recommended.json's options, then claude-openai's, then (Claude Only) claude's: a key named twice is sent once.
    jq -r --arg p "$2" --slurpfile r "$IL_ROOT/config/recommended.json" '
      ($r[0].options + .profiles["claude-openai"].options + (if $p == "claude" then .profiles.claude.options else {} end))
      | to_entries[] | "--option", "\(.key)=\(.value | tostring)"' "$P" || exit 1
    jq -r '.profiles["claude-openai"].flags[]' "$P" || exit 1
    while IFS=$US read -r f v _; do
      case $f in --standard-context|--no-standard-context) printf '%s\n' "$f" ;; *) printf '%s\n%s\n' "$f" "$v" ;; esac
    done < <(detect) ;;
  --report)
    case ${2-} in ''|detected|dashboard) ;; *) usage ;; esac
    # setup.sh takes the detected half before it writes (its own model key would read as the owner's), the rest after.
    [ "${2-}" = dashboard ] || while IFS=$US read -r f v w; do
      case $f in
        --test-command) echo "auto: merge check: ${v:-none} ($w)" ;;
        --typecheck-command) echo "auto: typecheck: ${v:-none} ($w)" ;;
        --screen-paths) echo "auto: screen folders: ${v:-none} ($w)" ;;
        --lockfile-deny) echo "auto: lockfile reads: denied ($w)" ;;
        --full-suite) echo "auto: full suite before the final review: $v ($w)" ;;
        *) echo "auto: context window: $w" ;;
      esac
    done < <(detect)
    if [ "${2-}" = detected ]; then :
    elif [ "$(jq -r '.dashboard' "$IL_PROJECT" 2>/dev/null)" = true ]; then
      echo "auto: dashboard: http://$(jq -r '.dashboard.bind // "127.0.0.1"' "$IL_MACHINE" 2>/dev/null):$(jq -r '.dashboard.port // empty' "$IL_MACHINE" 2>/dev/null)/ (this machine only)"
      echo "auto: to open it to the network, store a password once (python3 $(printf '%q' "$HERE")/dashboard_serve.py set-password <user>), then run: bash $(printf '%q' "$HERE")/setup.sh --dashboard --bind 0.0.0.0 --hosts <name>"
    else echo "auto: dashboard: off"; fi ;;
  --sources)
    pp_rm_rf "$STAGE" && mkdir -p "$STAGE" || { echo "auto-setup: could not empty $STAGE" >&2; exit 1; }
    printf 'staging\t%s\n' "$STAGE"
    for t in AGENT_STARTUP.md main-session.md global-claude.md global-rules.md; do printf 'template\t%s\t%s\n' "$t" "$IL_ROOT/templates/$t"; done
    il_rule_sources ;;
  --global-preview)
    [ -n "${2-}" ] || usage
    S=$2/global/CLAUDE.md
    # A global file that needs no change is not staged (the skill's step 2): say so, then the question follows.
    if [ ! -f "$S" ]; then
      if [ -f "$IL_GLOBAL" ]; then echo "$IL_GLOBAL needs no change: Optimize it adds only the plugin's rules it lacks, in marked blocks"
      else echo "auto-setup: nothing staged at $S" >&2; exit 1; fi
    elif [ -f "$IL_GLOBAL" ]; then
      { diff -u --label "$IL_GLOBAL (now, the plugin's blocks out)" --label "$IL_GLOBAL (after Optimize it)" <(il_rules_strip "$IL_GLOBAL") "$S" || true; }
    else echo "$IL_GLOBAL does not exist yet: Optimize it creates it with the plugin's blocks"; fi
    [ ! -f "$2/conflicts.tsv" ] || awk -F'\t' '$1 == "global/CLAUDE.md" { print "CONFLICT: yours: " $2 " | the plugin'"'"'s rule, which wins: " $3 }' "$2/conflicts.tsv" ;;
  *) usage ;;
esac

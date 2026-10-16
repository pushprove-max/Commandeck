#!/usr/bin/env bash
# project.sh -- sourced, never run. pp_project sets PP_PROJECT to the name of
# the project the caller runs in: the primary checkout's directory name, so
# main and every worktree of it answer the same. The logs under ~/.claude
# (rulings, hook fires) are named for it; every project on the machine shares
# that directory. Builtins only: the hook fire log calls this on every hook.
pp_project() {
  local d=${1:-$PWD} g
  while [ -n "$d" ] && [ ! -e "$d/.git" ]; do d=${d%/*}; done
  # A worktree's .git is a file: `gitdir: <primary>/.git/worktrees/<name>`.
  if [ -f "$d/.git" ]; then
    read -r _ g < "$d/.git"
    # A relative gitdir starts at the worktree's root, not where the caller stands.
    case $g in /*) d=${g%/.git/worktrees/*} ;; *) d=$(cd "$d" 2>/dev/null && cd "${g%/.git/worktrees/*}" 2>/dev/null && pwd) ;; esac
  fi
  PP_PROJECT_DIR=$d
  d=${d##*/}
  PP_PROJECT=${d//[^A-Za-z0-9_.-]/-}
  PP_PROJECT=${PP_PROJECT:-unknown}
}
# pp_cos_key [<dir>]: COS_KEY, the stem of the Chief of Staff watchers' state files
# (cos-lib.sh) and pid records (cos-inbox-waiter-stop.sh). Two projects can share a
# directory name, so the primary checkout's real path is in it too. Files kept by
# 0.8 under the name alone are carried over once, so nothing read is read again.
pp_cos_key() {
  local h f
  pp_project "${1:-}"
  h=$(cd "$PP_PROJECT_DIR" 2>/dev/null && pwd -P | cksum)
  COS_KEY=$HOME/.commandeck/chief-of-staff/$PP_PROJECT.${h%% *}
  for f in md inbox-seq decisions-seen alerts-seen limit-told; do
    [ -e "$COS_KEY.$f" ] || [ ! -e "${COS_KEY%.*}.$f" ] || mv "${COS_KEY%.*}.$f" "$COS_KEY.$f"
  done
}
# pp_flag <key>: 0 when the project's .claude/commandeck.json (setup writes it)
# has "<key>": true. Read with builtins: a strict-tier hook asks on every call,
# and a jq start per hook per call would cost more than the hooks it switches off.
pp_flag() {
  local PP_PROJECT PP_PROJECT_DIR c
  pp_project
  [ -r "$PP_PROJECT_DIR/.claude/commandeck.json" ] || return 1
  c=$(<"$PP_PROJECT_DIR/.claude/commandeck.json")
  [[ $c =~ \"$1\"[[:space:]]*:[[:space:]]*true ]]
}
# The strict tier is off unless the project turned it on ("strictHooks": true).
# COMMANDECK_HOOK_TIER=strict|default overrides the file, for the self-tests.
pp_strict() {
  case ${COMMANDECK_HOOK_TIER-} in strict) return 0 ;; default) return 1 ;; esac
  pp_flag strictHooks
}
# The context size past which main checkpoints and restarts. A project whose
# model holds 200K ("standardContext": true, a setup answer) is full before a
# 200K line can fire, so its line is 150K. COMMANDECK_CLEAR_LINE overrides.
pp_clear_line() {
  if [ -n "${COMMANDECK_CLEAR_LINE-}" ]; then printf '%s' "$COMMANDECK_CLEAR_LINE"
  elif pp_flag standardContext; then printf 150000
  else printf 200000; fi
}
# The context size past which a Builder hands off to a fresh session of its pane: setup's
# builder.clearLine, a token count or off, default 180000. A value it does not take fails, naming the key.
pp_builder_clear_line() { # [<directory in the project>]
  local PP_PROJECT PP_PROJECT_DIR v
  pp_project "${1:-}"
  v=$(jq -r '.builder.clearLine // empty' "$PP_PROJECT_DIR/.claude/commandeck.json" 2>/dev/null)
  [[ ${v:=180000} =~ ^(off|[1-9][0-9]*)$ ]] \
    || { echo "$PP_PROJECT_DIR/.claude/commandeck.json has builder.clearLine = \"$v\", which is not a token count or off; answer it again with /commandeck:setup" >&2; return 1; }
  printf '%s' "$v"
}
# pp_run_file: the file naming this project's Orca run, the one
# scripts/paths.sh calls $PP_RUN_FILE, resolved by the same function
# (scripts/project-main.sh) without the rest of paths.sh.
pp_run_file() {
  local PP_MAIN PP_WORKSPACES PP_WORKSPACES_GIVEN
  . "$(dirname "${BASH_SOURCE[0]}")/../../scripts/project-main.sh" && pp_main_resolve || return 1
  printf '%s' "${COMMANDECK_SCRATCH:-$HOME/.commandeck/scratch/${PP_MAIN//[^A-Za-z0-9]/-}}/current-run"
}
# The symbol-first hooks also need serena: setup records "serena": true when it is installed.
pp_serena() { [ "${COMMANDECK_SERENA-}" = 1 ] || pp_flag serena; }

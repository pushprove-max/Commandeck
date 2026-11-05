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
# pp_standing_wt <folder>: 0 for the folder names of the seats the owner sits in, found by name as the relay is:
# the Chief-of-Staff relay and the Fast-lane and Research-lane worktrees (issue 416). PP_STANDING_SEATS is the one
# list (issue 460): a name added to it reaches every caller, ruling-log-archive.sh's jq included. Only cos-check.sh's
# jq spells the same three, and worktree-setup.test.sh fails on a site that drifts.
PP_STANDING_SEATS=(Chief-of-Staff Fast-lane Research-lane)
pp_standing_wt() {
  local s
  for s in "${PP_STANDING_SEATS[@]}"; do [ "${1-}" = "$s" ] && return 0; done
  return 1
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
# model holds 200K ("standardContext": true, a setup answer) auto-compacts at
# 171K-175K (measured), so its line is 140K, 30K under that (issue 267).
# COMMANDECK_CLEAR_LINE overrides.
pp_clear_line() {
  if [ -n "${COMMANDECK_CLEAR_LINE-}" ]; then printf '%s' "$COMMANDECK_CLEAR_LINE"
  elif pp_flag standardContext; then printf 140000
  else printf 200000; fi
}
# The size past which a restart a background agent holds tells main to TaskStop it or let it finish (a restart never
# kills one): under the auto-compact point, 165K on a 200K window, 480K on 1M. COMMANDECK_CLEAR_CEILING overrides.
pp_clear_ceiling() {
  if [ -n "${COMMANDECK_CLEAR_CEILING-}" ]; then printf '%s' "$COMMANDECK_CLEAR_CEILING"
  elif pp_flag standardContext; then printf 165000
  else printf 480000; fi
}
# The context size past which a Builder hands off to a fresh session of its pane: setup's
# builder.clearLine, a token count or off, default 180000, or 140000 on a 200K window (issue 267). A value it does
# not take fails, naming the key.
pp_builder_clear_line() { # [<directory in the project>]
  local PP_PROJECT PP_PROJECT_DIR v
  pp_project "${1:-}"
  v=$(jq -r '.builder.clearLine // (if .standardContext == true then 140000 else empty end)' "$PP_PROJECT_DIR/.claude/commandeck.json" 2>/dev/null)
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
# pp_run_id_of -- the run id from `orchestration run-current` JSON on stdin (issue 588). An allowlist (class-miss): the
# --full form's `result.run` null (unbound: prints nothing, 0) or an object whose `id` is a non-empty string (the id,
# 0); Orca 1.4.246's concise form, `result.runId` and no `run`, says so on stderr and returns 4; any other `run` value
# says its shape on stderr and returns 5; no output, or no `result` object, returns 1. pp_orca_run_id asks Orca with
# --full; every run-current reader goes through it.
pp_run_id_of() {
  local j
  j=$(jq -c '.result | if type == "object" then . else error end' 2>/dev/null) || return 1
  if jq -e 'has("run")' <<<"$j" >/dev/null 2>&1; then
    jq -er '.run | if . == null then "" elif type == "object" and (.id | type) == "string" and .id != "" then .id else error end' <<<"$j" 2>/dev/null \
      && return 0
    echo "pp_run_id_of: run-current \`run\` is neither null nor an object with a string id: $(jq -c '.run' <<<"$j" | head -c 200)" >&2; return 5
  fi
  if jq -e 'has("runId")' <<<"$j" >/dev/null 2>&1; then
    echo "pp_run_id_of: concise run-current output; the call needs --full" >&2; return 4
  fi
  return 1
}
pp_orca_run_id() { orca-ide orchestration run-current --full --json 2>/dev/null | pp_run_id_of; }
# pp_is_main_pane -- is this pane main? The main checkout also holds an Orca automation or a second session, so only the
# run's coordinator pane is. The run is COMMANDECK_RUN, else the run file (pp_run_file), else Orca's run-current.
# 0 main (also: no Orca handle, or no run from all three: nothing to tell main from; Orca giving no output at all is
# this case too, a known gap by main's ruling, pass 7); 1 not main; 2 unknown (run-list failed or does not list the
# run, or run-current answered in a shape pp_run_id_of does not read: 4 or 5); 3 the run is listed with no coordinator.
# Sets PP_MAIN_RUN and PP_MAIN_COORD.
pp_is_main_pane() {
  local f rc=0
  PP_MAIN_RUN=${COMMANDECK_RUN:-} PP_MAIN_COORD=
  [ -n "${ORCA_TERMINAL_HANDLE:-}" ] || return 0
  [ -n "$PP_MAIN_RUN" ] || { f=$(pp_run_file 2>/dev/null) && PP_MAIN_RUN=$(tr -d '[:space:]' < "$f" 2>/dev/null); } || true
  if [ -z "$PP_MAIN_RUN" ]; then
    PP_MAIN_RUN=$(pp_orca_run_id) || rc=$?
    case $rc in 4|5) PP_MAIN_RUN=; return 2 ;; esac
  fi
  [ -n "$PP_MAIN_RUN" ] || return 0
  PP_MAIN_COORD=$(orca-ide orchestration run-list --full --json 2>/dev/null | jq -er --arg r "$PP_MAIN_RUN" \
    '.result.runs | if type == "array" then first(.[] | select(.id == $r)) | (.coordinator_handle // "") else error end' 2>/dev/null) || { PP_MAIN_COORD=; return 2; }
  [ -n "$PP_MAIN_COORD" ] || return 3
  [ "$PP_MAIN_COORD" = "$ORCA_TERMINAL_HANDLE" ] && return 0
  return 1
}
# The symbol-first hooks also need serena: setup records "serena": true when it is installed.
pp_serena() { [ "${COMMANDECK_SERENA-}" = 1 ] || pp_flag serena; }

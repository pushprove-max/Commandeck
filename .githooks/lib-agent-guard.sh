# shellcheck shell=bash
# Agent publishing guard. Linked-checkout workers must NEVER commit or push:
# they return a diff and the foreground session integrates it. A headless
# `claude -p` process or a review worker that commits and pushes ships a broken
# change straight past review. This guard BLOCKS them at the git layer, and
# survives plugin updates because it is versioned in the repo.
#
# Mechanism, two independent decisions:
# 1. Git/common-directory topology distinguishes the primary checkout from a
#    linked worker checkout. Provider environment and process identity do not
#    confer or remove publishing authority.
# 2. Ancestry contains a HEADLESS claude: argv0 basename `claude` with an
#    exact `-p` or `--print` argument (argv parsed as the NUL-delimited
#    array, so an argument VALUE merely containing "-p" cannot
#    false-positive). The interactive foreground claude carries neither.
#    macOS reads argv through ps instead (COMMANDECK_HOST_OS=Darwin drives that
#    branch on either host, so the self-test covers it too).
# Known limits (tripwire, not a sandbox): a fully reparented daemon (setsid,
# dead parent) has no ancestry to inspect; `git commit --no-verify`, an
# alternate core.hooksPath, and plumbing commands skip hooks entirely; an
# unreadable /proc fails open. An agent doing any of those is no longer
# "off-script" but adversarial, which is out of scope here.
#
# Deliberate owner-authorized override (git hooks inherit the command env):
#   COMMANDECK_ALLOW_AGENT_GIT=1 git commit ...

agent_worktree_topology_guard() {
  local git_dir common_dir
  git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null) || git_dir=""
  common_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || common_dir=""
  if [ -z "$git_dir" ] || [ -z "$common_dir" ]; then
    echo "agent-guard: BLOCKED - cannot determine Git checkout topology." >&2
    return 1
  fi
  if [ "$git_dir" != "$common_dir" ]; then
    echo "agent-guard: BLOCKED - publishing from a linked worker checkout." >&2
    echo "  Workers return diffs; the foreground session integrates and publishes." >&2
    return 1
  fi
  return 0
}

# The standing Fast lane is the one linked checkout that may commit (pre-commit
# only; pre-push still refuses it). The workspaces folder W is
# COMMANDECK_WORKSPACES when that is this checkout's real parent folder, else
# $HOME/orca/workspaces/<main checkout's folder name>. 0 only when this checkout
# is linked, its real top level is W/Fast-lane, and its real common git dir is
# the one that path's own .git file names: a folder named Fast-lane anywhere
# else, or a GIT_DIR pointed at another repository, gets nothing. Any
# unreadable piece returns 1. No output.
agent_fast_lane_commit() {
  local git_dir common_dir top canon gitfile linked_dir ws
  git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null) || return 1
  common_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  [ -n "$git_dir" ] && [ -n "$common_dir" ] && [ "$git_dir" != "$common_dir" ] || return 1
  top=$(git rev-parse --show-toplevel 2>/dev/null) && top=$(cd "$top" 2>/dev/null && pwd -P) || return 1
  ws=${HOME:-/nonexistent}/orca/workspaces/$(basename "$(dirname "$common_dir")")
  case ${COMMANDECK_WORKSPACES:-} in
    ''|*/) ;;
    *) [ "$(cd "$COMMANDECK_WORKSPACES" 2>/dev/null && pwd -P)" = "$(dirname "$top")" ] && ws=$COMMANDECK_WORKSPACES ;;
  esac
  canon=$(cd "$ws/Fast-lane" 2>/dev/null && pwd -P) || return 1
  [ -n "$top" ] && [ "$top" = "$canon" ] || return 1
  [ -f "$canon/.git" ] || return 1
  gitfile=$(sed -n 's/^gitdir: //p' "$canon/.git" | head -1)
  case $gitfile in /*/worktrees/?*) ;; *) return 1 ;; esac
  linked_dir=$(cd "${gitfile%/worktrees/*}" 2>/dev/null && pwd -P) || return 1
  common_dir=$(cd "$common_dir" 2>/dev/null && pwd -P) || return 1
  [ -n "$linked_dir" ] && [ "$common_dir" = "$linked_dir" ]
}

agent_ancestry_guard() {
  [ "${COMMANDECK_ALLOW_AGENT_GIT:-}" = "1" ] && return 0

  local pid=$$ depth=0 argv0 host=${COMMANDECK_HOST_OS:-$(uname -s)}
  while [ -n "$pid" ] && [ "$pid" -gt 1 ] && [ "$depth" -lt 40 ]; do
    local -a argv=()
    if [ "$host" = Darwin ]; then
      # macOS has no /proc: ps joins argv with spaces, so an argument whose
      # value holds a standalone " -p " word blocks too (fails closed).
      read -ra argv <<<"$(ps -o args= -p "$pid" 2>/dev/null)" || true
    elif [ -r "/proc/$pid/cmdline" ]; then
      while IFS= read -r -d '' _arg; do argv+=("$_arg"); done < "/proc/$pid/cmdline" || true
    fi
    argv0="${argv[0]:-}"
    argv0="${argv0##*/}"

    if [ "$argv0" = "claude" ]; then
      local _flag
      for _flag in "${argv[@]:1}"; do
        if [ "$_flag" = "-p" ] || [ "$_flag" = "--print" ]; then
          echo "agent-guard: BLOCKED - git invoked under a headless 'claude -p' process (pid $pid)." >&2
          echo "  Headless workers return diffs; the foreground session integrates them." >&2
          return 1
        fi
      done
    fi

    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)
    depth=$((depth + 1))
  done
  return 0
}

#!/usr/bin/env bash
# project-main.sh -- sourced, never run. The ONE reader of COMMANDECK_MAIN and
# COMMANDECK_WORKSPACES: paths.sh and the hooks' lib/project.sh both call
# pp_main_resolve, and no other script reads either variable.
#
# pp_main_resolve sets PP_MAIN (the project's primary checkout) and PP_WORKSPACES
# (the folder its worktrees are in), and PP_WORKSPACES_GIVEN=1 when the
# worktrees folder is the variable's. It returns 1 where there is no project.
#
# The two variables are overrides for the self-tests and the installed jobs.
# The rule, named here and nowhere else:
#   - Outside a linked worktree they are followed as given: a job the machine
#     starts, or a script run in a main checkout, has no worktree to be told
#     apart from.
#   - Inside a linked worktree the project is the one git says the worktree
#     belongs to, whatever the session's project or a variable names. The
#     current folder decides first: where the shell stands is the one input
#     git answers for by itself. The session's project (CLAUDE_PROJECT_DIR)
#     decides only when the current folder is in no linked worktree. A Builder
#     works there and controls its own shell, so a variable naming its own
#     tree, another worktree of the project or a copy kept anywhere else is NOT
#     followed. One kind of value still is, because a self-test run from a
#     worktree must reach the stand-in project it has just made: a FIXTURE, a
#     folder under the system's temp folder that is no checkout of the
#     worktree's own project, and whose whole checkout (its main checkout's
#     git folder too) is under the temp folder. A stand-in project is followed
#     only together with a worktrees folder under the temp folder, so no script
#     acts on a real worktree under a stand-in project's config. COMMANDECK_WORKSPACES naming the
#     folder the worktree is really in is followed too: it is what git says.
# shortcut: a clone of the project kept under the temp folder counts as a fixture, and a Builder can make one; scripts then act on that clone and its own scratch, never on main's. Upgrade to a marker only the test runner can set if a script is found to trust what it reads there.
# pp_real <path>: where the path really is. A part not made yet is kept as
# spelled, after the real place of the deepest folder that exists; a part that
# climbs (..) or is a dangling link there has no real place, and that fails.
pp_real() {
  local p=$1 rest=""
  case $p in /*) ;; *) p=$PWD/$p ;; esac
  while [ ! -d "$p" ]; do
    [ ! -L "$p" ] || return 1
    case ${p##*/} in ..|.) return 1 ;; esac
    rest=/${p##*/}$rest p=${p%/*}; p=${p:-/}
  done
  p=$(cd "$p" 2>/dev/null && pwd -P) || return 1
  printf '%s%s' "${p%/}" "$rest"
}
# pp_git <args...>: git with none of its routing variables (GIT_DIR, GIT_WORK_TREE
# and the rest git lists, and the ceiling that stops its search): a Builder sets
# them in its own shell, and they would make its worktree read as a main checkout.
pp_git() { (unset $(git rev-parse --local-env-vars) GIT_CEILING_DIRECTORIES; git "$@"); }
pp_temp() { case $1 in /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) ;; *) return 1 ;; esac; }
# pp_fixture <path> <git common dir of the worktree's own project>: the path
# is really under the temp folder, and so is the whole checkout it is in, if
# any (a worktree parked there acts on its main checkout's git folder), and
# that checkout is not the worktree's own project.
pp_fixture() {
  local r d k; r=$(pp_real "$1") || return 1
  pp_temp "$r" || return 1
  d=$r; while [ ! -d "$d" ]; do d=${d%/*}; done
  k=$(pp_git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
  [ "$k" != "$2" ] && k=$(pp_real "$k") && pp_temp "$k"
}
pp_checkout() { # <dir>: sets c (git common dir), g (git dir) and t (top folder); 1 when <dir> is in no checkout
  local out
  [ -n "$1" ] && out=$(pp_git -C "$1" rev-parse --path-format=absolute --git-common-dir --git-dir --show-toplevel 2>/dev/null) || return 1
  { IFS= read -r c; IFS= read -r g; IFS= read -r t; } <<<"$out"
  case $c in */.git) ;; *) return 1 ;; esac
}
pp_main_resolve() {
  local c g t first="" own="" ownws="" m w r
  # Where the shell stands is the one thing here git answers for by itself, so a
  # linked worktree there decides; the session's project is a variable beside it.
  if pp_checkout "$PWD"; then
    first=${c%/.git}
    [ "$c" = "$g" ] || { own=$c; ownws=$(pp_real "$t/.."); }
  fi
  if pp_checkout "${CLAUDE_PROJECT_DIR-}"; then
    if [ -z "$own" ]; then
      first=${c%/.git}
      [ "$c" = "$g" ] || { own=$c; ownws=$(pp_real "$t/.."); }
    elif pp_fixture "$CLAUDE_PROJECT_DIR" "$own"; then
      first=${c%/.git}
    fi
  fi
  m=${COMMANDECK_MAIN:-} w=${COMMANDECK_WORKSPACES:-}
  # Consumers compare "$PP_WORKSPACES/..." as text with Orca's and the transcripts' paths, so a trailing / or /.
  # goes; no other respelling (a link, a ..), or Orca's spelling stops matching. COMMANDECK_MAIN stays as given:
  # the install manifest and the scratch folder are keyed by its spelling.
  while :; do case $w in */) w=${w%/} ;; */.) w=${w%/.} ;; *) break ;; esac; done
  if [ -n "$own" ]; then
    [ -z "$w" ] || [ "$(pp_real "$w")" = "$ownws" ] || pp_fixture "$w" "$own" || w=
    [ -z "$m" ] || pp_fixture "$m" "$own" || m=
    # The pair that would be used, whichever input chose the project: a stand-in
    # project is followed only with a worktrees folder under the temp folder that
    # is not this worktree's, never a real one (its default may be a real project's
    # of the same name).
    m=${m:-$first}
    [ "$m" = "${own%/.git}" ] || { r=$(pp_real "${w:-$HOME/orca/workspaces/$(basename "$m")}") && [ "$r" != "$ownws" ] && pp_temp "$r"; } || m=${own%/.git}
  fi
  PP_MAIN=${m:-$first}
  [ -n "$PP_MAIN" ] || return 1
  PP_WORKSPACES_GIVEN=${w:+1}
  PP_WORKSPACES=${w:-$HOME/orca/workspaces/$(basename "$PP_MAIN")}
}

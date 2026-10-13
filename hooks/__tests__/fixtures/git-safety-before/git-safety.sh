#!/usr/bin/env bash
# PreToolUse hook: block dangerous git operations
# Input: JSON on stdin with tool_input.command

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
# The strip below walks the command a character at a time (~1 s per 10 KB);
# a command naming no git call, or none of the screened subcommands, cannot
# match, so skip it. Quote and backslash characters are dropped first, so
# `pu''sh` cannot slip past. Every subcommand a check below reads is admitted
# here; one missing from this list is never screened at all.
P=${COMMAND//[\'\"\\]/}
case "$P" in *git*) ;; *) exit 0 ;; esac
case "$P" in *push*|*reset*|*checkout*|*switch*|*restore*|*clean*|*stash*|*branch*|*worktree*|*reflog*|*gc*) ;; *) exit 0 ;; esac

# `p\ush` and `$'push'` are the word push to bash (a backslash before a letter
# is that letter), so every check below reads them that way.
COMMAND=$(printf '%s' "$COMMAND" | sed -E "s#\\\\([a-z])#\\1#g; s#[\$]('[a-z][a-z-]*')#\\1#g")

# Quoted text is not a command. A commit message or an echo that merely NAMES a
# dangerous operation must not trip the force/reset checks (a commit message
# mentioning one used to block). One pass over the whole command, heredoc
# bodies included: a per-line sed left a multi-line message whole.
. "${BASH_SOURCE[0]%/*}/lib/strip-quoted.sh" 2>/dev/null
# Without the helper CMD would be empty and every force push would pass.
type strip_quoted >/dev/null 2>&1 || { echo "BLOCKED: ${BASH_SOURCE[0]##*/} could not load hooks/lib/strip-quoted.sh, so it cannot screen this command. Restore it (git checkout hooks/lib/strip-quoted.sh) and retry." >&2; exit 2; }
# A quoted WORD is still the word git gets: `git push '--force'` forces. Only
# quoted text is not a command, so a one-word flag or refspec (it opens with
# - + or :) and a quoted subcommand right after `git` are bared first.
# So is any quoted span that is one plain lowercase word, wherever it sits:
# `git -C x 'push'`, `'git' push` and `pu'sh'` are the words git gets.
# shortcut: `echo 'git' 'push' '--force'` then reads as a push and blocks; a flag quoted in halves is not bared. Parse the words if either is seen.
W='[A-Za-z0-9_./=:+@~^-]*'
BARE=$(printf '%s' "$COMMAND" | sed -E "s#'([-+:]$W)'#\\1#g; s#\"([-+:]$W)\"#\\1#g; s#'([a-z][a-z-]*)'#\\1#g; s#\"([a-z][a-z-]*)\"#\\1#g")
CMD=$(strip_quoted "$BARE")

# A git invocation ANYWHERE in the command, not only at position one. The old
# `^git ` prefix test meant `cd x && git push --force`, `FOO=1 git ...` and a
# `git` call after a `;` never reached a single check below -- the guard read
# the most common shapes of the thing it exists to stop as "not a git command".
if ! printf '%s' "$CMD" | grep -qE '(^|[;&|(/]|[[:space:]])git[[:space:]]'; then
  exit 0
fi

# OPTIONS SIT BETWEEN THE VERB AND ITS SUBCOMMAND. Widening the gate above was
# not enough: each check still demanded `git` immediately followed by `push` or
# `reset`, so `git -C <path> push --force` and `git --no-pager push --force`
# reached the checks and matched nothing. `git -C <path>` is this repo's own
# standard idiom -- main types it in
# every worktree command -- so that was a hole in the shape we actually use.
#
# One `-opt` with an optional non-option value, repeated. `git log --oneline`
# cannot be mistaken for one of these: `log` does not begin with `-`, so the
# group cannot consume it and the subcommand never matches.
GITOPTS='([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]-][^[:space:]]*)?)*'

# `--force-with-lease` is the SAFE form this hook's own message recommends, and
# the old `--force` substring matched it -- so the guard blocked the push it
# told the operator to use. Neutralised before the test (grep -E is POSIX ERE
# with no lookahead) so a bare `--force` and `-f` still block.
FORCE_CMD=$(printf '%s' "$CMD" | sed -E 's/--force-with-lease(=[^[:space:]]*)?/--lease/g; s/--force-if-includes//g')

# Block force push. A push's arguments stop at a command separator, so the
# next command's own -f or --force is not read as the push's.
PUSH_ARGS="git${GITOPTS}[[:space:]]+push([[:space:]]+[^;&|[:space:]]+)*[[:space:]]+"
if printf '%s' "$FORCE_CMD" | grep -qE "${PUSH_ARGS}(--force|-f([[:space:];&|)]|\$))"; then
  echo "Blocked: force push is not allowed. Use --force-with-lease if absolutely necessary." >&2
  exit 2
fi

# The other force and delete forms: a short-flag cluster holding f or d
# (-fu, -uf, -d), a +refspec, an empty-source :ref refspec, --delete and
# --mirror. Push arguments stop at a command separator, so a later `echo +1`
# is not read as a refspec.
if printf '%s' "$FORCE_CMD" | grep -qE "${PUSH_ARGS}(-[[:alnum:]]*[fd][[:alnum:]]*|[+:][^;&|[:space:]]+|--delete|--mirror)([[:space:];&|)]|\$)"; then
  echo "Blocked: force push, remote branch deletion and --mirror are not allowed (-f in a flag cluster, a +refspec, a :ref refspec, --delete or -d). Use --force-with-lease if a rewrite is absolutely necessary." >&2
  exit 2
fi

# Block git reset --hard on main
if printf '%s' "$CMD" | grep -qE "git${GITOPTS}[[:space:]]+reset([[:space:]]+[^;&|()[:space:]]+)*[[:space:]]+--hard([[:space:];&|)]|\$)"; then
  echo "Blocked: git reset --hard is dangerous. Use git revert for safe rollbacks." >&2
  exit 2
fi

# The other ways to discard work: each throws away uncommitted edits,
# untracked files, a stash, an unmerged branch or the reflog that would recover
# them, exactly as reset --hard does. Every git call is read on its OWN words,
# which stop at a command separator, so a later `echo -- .` is not a checkout
# argument. Each family is narrowed to its discarding form, because its
# neighbour is ordinary work: a branch checkout, an index-only restore, a clean
# dry run, a merged-branch delete. scripts/merge-unit-local.sh
# runs several of these inside itself; the hook sees only the
# submitted command, so it is untouched.
# CEILING: a path checkout written without `--` (`git checkout file`) reads as
# a branch checkout and passes; nothing in the words tells the two apart.
#
# A QUOTED ARGUMENT IS STILL AN ARGUMENT. These rules read each call's words by
# position, and CMD has every quoted span removed: `git -C "/repo" clean -fdx`
# became `git -C clean -fdx`, -C took `clean` as its value and the discard
# passed. ARGV keeps a quoted span as its word (strip-quoted.sh, the mark
# form): a plain token as written, quoted prose as one placeholder word.
# Quoted data is still never the START of a call: a quoted `git` word becomes
# the placeholder too, so `git grep "git" -- "restore"` is one call, a grep.
case "$P" in *checkout*|*switch*|*restore*|*clean*|*stash*|*branch*|*worktree*|*reflog*|*gc*) ;; *) exit 0 ;; esac
Q=$'\x01'
ARGV=$(strip_quoted "$COMMAND" "$Q" | sed -E "s/${Q}([^;&|()[:space:]]*\/)?git([;&|()[:space:]]|\$)/QUOTED\2/g; s/${Q}([;&|()[:space:]]|\$)/QUOTED\1/g; s/${Q}//g")
# The subcommand is matched as a whole word, so `git restore-mtime` is not a restore.
DISCARD="(^|[;&|(/]|[[:space:]])git${GITOPTS}[[:space:]]+(checkout|switch|restore|clean|stash|branch|worktree|reflog|gc)[^;&|()[:space:]]*([[:space:]]+[^;&|()[:space:]]+)*"
arg_is() { # <ERE>: one of the call's arguments is exactly this
  local A
  for A in "${ARGS[@]}"; do [[ $A =~ ^($1)$ ]] && return 0; done
  return 1
}
while IFS= read -r CALL; do
  set -f; set -- $CALL; set +f
  shift # the git word itself
  # GITOPTS guesses which option takes a value; git's own list decides which
  # word is the subcommand, so `git --no-pager log -- stash` stays a log.
  while [ $# -gt 0 ]; do
    case "$1" in
      -C|-c|--git-dir|--work-tree|--namespace|--config-env) shift; [ $# -gt 0 ] && shift ;;
      --) break ;; # git has no bare `--` option: `git grep git -- restore` names a file
      -*) shift ;;
      *) break ;;
    esac
  done
  SUB=${1-}; [ $# -gt 0 ] && shift
  # Everything after `--` is a path, never an option: a file named -n is not a
  # dry run. ARGS = the words before it, PATHS = 1 when it is there.
  ARGS=(); PATHS=0; WHY=""
  for A in "$@"; do [ "$A" = -- ] && { PATHS=1; break; }; ARGS+=("$A"); done
  case "$SUB" in
    checkout)
      # The `--` is optional: two plain words are a commit and a path, and one
      # is a path when it names a file here and no commit. POS = the plain
      # words, less the branch name -b, -B and --orphan take.
      # shortcut: the one-word case is looked up in the session's folder, not a -C one.
      POS=(); SKIP=0
      for A in "${ARGS[@]}"; do
        [ "$SKIP" = 0 ] || { SKIP=0; continue; }
        case $A in --orphan|-[bB]|-[a-zA-Z]*[bB]) SKIP=1 ;; -*) ;; *) POS+=("$A") ;; esac
      done
      CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
      { [ "$PATHS" = 1 ] || arg_is '\./?' || [ "${#POS[@]}" -ge 2 ] \
        || { [ "${#POS[@]}" = 1 ] && ( cd "${CWD:-.}" 2>/dev/null && [ -e "${POS[0]}" ] && ! git rev-parse -q --verify "${POS[0]}^{commit}" >/dev/null 2>&1 ); }; } \
        && WHY="git checkout of paths (after \`--\`, after a commit, or a file's own name) overwrites uncommitted edits. Commit them or copy them aside first; switching branches is not affected."
      arg_is '--force|-[a-zA-Z]*f[a-zA-Z]*' && WHY="git checkout --force throws away the uncommitted edits a plain checkout would stop for. Commit them or copy them aside first." ;;
    switch)
      arg_is '--force|--discard-changes|-[a-zA-Z]*f[a-zA-Z]*' && WHY="git switch --force (--discard-changes) throws away the uncommitted edits a plain switch would stop for. Commit them or copy them aside first." ;;
    restore)
      { arg_is '--staged|-[a-zA-Z]*S[a-zA-Z]*' && ! arg_is '--worktree|-[a-zA-Z]*W[a-zA-Z]*'; } \
        || WHY="git restore of the working tree overwrites uncommitted edits. Only the index-only \`git restore --staged\` passes." ;;
    clean)
      arg_is '--force|-[a-zA-Z]*f[a-zA-Z]*' && ! arg_is '--dry-run|-[a-zA-Z]*n[a-zA-Z]*' \
        && WHY="git clean -f deletes untracked files (briefs, scratch, handoff files). Preview with \`git clean -n\` and remove what you mean to by name." ;;
    stash)
      case "${ARGS[0]-}" in drop|clear) WHY="git stash ${ARGS[0]} destroys stashed work. Apply it or leave it." ;; esac ;;
    branch)
      { arg_is '-[a-zA-Z]*D[a-zA-Z]*' || { arg_is '--delete|-[a-zA-Z]*d[a-zA-Z]*' && arg_is '--force|-[a-zA-Z]*f[a-zA-Z]*'; }; } \
        && WHY="git branch -D deletes a branch whatever it still holds. Use \`git branch -d\`, which refuses an unmerged branch." ;;
    worktree)
      [ "${ARGS[0]-}" = remove ] && arg_is '--force|-f+' \
        && WHY="git worktree remove --force deletes a worktree with its uncommitted changes. Remove it without --force." ;;
    reflog)
      [ "${ARGS[0]-}" = expire ] && WHY="git reflog expire drops the entries that recover lost commits." ;;
    gc)
      arg_is '--prune=now' && WHY="git gc --prune=now deletes unreachable objects at once, the ones the reflog could still recover. Plain \`git gc\` keeps the grace period." ;;
  esac
  [ -n "$WHY" ] || continue
  echo "Blocked: $WHY" >&2
  exit 2
done < <(printf '%s\n' "$ARGV" | grep -oE "$DISCARD")

exit 0

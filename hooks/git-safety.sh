#!/usr/bin/env bash
# PreToolUse hook: block dangerous git operations
# Input: JSON on stdin with tool_input.command

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# Retire when: zero blocks across 90 days of real rows from a project that installs the plugin (a clean remove passes)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
# The strip below walks the command a character at a time (~1 s per 10 KB);
# a command naming no git call, or none of the screened subcommands, cannot
# match, so skip it. Quote and backslash characters are dropped first, so
# `pu''sh` cannot slip past. Every subcommand a check below reads is admitted
# here; one missing from this list is never screened at all.
P=${COMMAND//[\'\"\\]/}
case "$P" in *git*) ;; *) exit 0 ;; esac
# `commit` is screened only in a Builder pane (issue 371), so any other session passes it here.
case "$P" in *push*|*reset*|*checkout*|*switch*|*restore*|*clean*|*stash*|*branch*|*worktree*|*reflog*|*gc*) ;; *commit*) [ "${COMMANDECK_BUILDER:-}" = 1 ] || exit 0 ;; *) exit 0 ;; esac

# `p\ush` and `$'push'` are the word push to bash (a backslash before a letter
# is that letter), so every check below reads them that way.
COMMAND=$(printf '%s' "$COMMAND" | sed -E "s#\\\\([a-z])#\\1#g; s#[\$]('[a-z][a-z-]*')#\\1#g")

# Quoted text is not a command. A commit message or an echo that merely NAMES a
# dangerous operation must not trip the force/reset checks (a commit message
# mentioning one used to block). One pass over the whole command, heredoc
# bodies included: a per-line sed left a multi-line message whole.
. "${BASH_SOURCE[0]%/*}/lib/strip-quoted.sh" 2>/dev/null
# Without the helper CMD would be empty and every force push would pass.
type strip_quoted >/dev/null 2>&1 || { echo "BLOCKED: ${BASH_SOURCE[0]##*/} could not load hooks/lib/strip-quoted.sh, so it cannot screen this command. Restore it (git checkout hooks/lib/strip-quoted.sh) and retry." >&2; HOOK_FIRE_REASON=helper-missing; exit 2; }
# A quoted WORD is still the word git gets: `git push '--force'` forces. Only
# quoted text is not a command, so a one-word flag or refspec (it opens with
# - + or :) and a quoted subcommand right after `git` are bared first.
# So is any quoted span that is one plain lowercase word, wherever it sits:
# `git -C x 'push'`, `'git' push` and `pu'sh'` are the words git gets.
# shortcut: `echo 'git' 'push' '--force'` then reads as a push and blocks; a flag quoted in halves is not bared. Parse the words if either is seen.
W='[A-Za-z0-9_./=:+@~^-]*'
BARE=$(printf '%s' "$COMMAND" | sed -E "s#'([-+:]$W)'#\\1#g; s#\"([-+:]$W)\"#\\1#g; s#'([a-z][a-z-]*)'#\\1#g; s#\"([a-z][a-z-]*)\"#\\1#g")
# A here-document whose end word is not plain is refused before anything reads
# it: each misread one hid the command after the note. bash-guardrails.sh says
# the same for every command, and is off unless the project runs the strict tier.
ODD=$(strip_odd_end "$COMMAND")
[ -z "$ODD" ] || { echo "Blocked: a here-document's end word is not plain: $ODD -- use one plain word such as EOF (letters, digits, _ . -), bare or in one pair of quotes." >&2; HOOK_FIRE_REASON=odd-heredoc-end; exit 2; }
CMD=$(strip_quoted "$BARE")
# CONTRACT for a quoted git word and for backticks. A seat belt against an
# honest mistake, not a wall; it fails closed.
# - A git word starts a git call wherever it stands, quoted or not: bash runs
#   `"git"` as git behind an assignment, `env`, `sudo -u git` or any other
#   wrapper, and no list of wrappers is kept here. So a git word that is data,
#   followed in the same simple command by words that spell a discard or a
#   force push (`grep -c "git" stash drop`), is refused too: reword it.
# - Backticks run inside double quotes and nest, and their quotes do not say
#   which text is data. A command holding a backtick is read with the quotes
#   of every string that holds one taken out. Left: quotes nested inside a
#   backtick are paired as they come, not as the shell pairs them, so quoted prose beside one that names a discard is refused too:
#   put the message in a file (`git commit -F`).
# - Not screened: `eval`, a command held in a variable, `bash -c '...'` text
#   and any other shell given a string.
# - A command holding a backtick is judged in THREE READINGS, by every check
#   below, and any one refuses. Closed: each substitution and each quoted
#   string is one opaque word, so a backtick that is an option's value
#   (`git -C "<backtick>pwd<backtick>" ...`) splits nothing. Opened: a quoted
#   string that holds a backtick loses its quotes and the backticks become
#   separators, so a discard run inside one is read. In both, a quoted string
#   that is one plain word keeps its text: it may be the executable or its
#   subcommand ("git" "reset"). A `$(...)` inside a quoted string is data in
#   both, so the reading every other command gets is judged as a third: it
#   follows `$(...)` into double quotes, nested too, and takes a backtick as a
#   plain character. Quotes nested inside a backtick are paired as they come,
#   not as the shell pairs them.
Q=$'\x01'
case "$COMMAND" in
  *'`'*) ARGV=$(printf '%s' "$COMMAND" | perl -0e '
    my $c = <STDIN>;
    for my $open (0, 1) {
      my $r = $c;
      $r =~ s{\\(.)|\x27([^\x27]*)\x27|"((?:\\.|[^"\\])*)"}{ defined $1 ? $1 : do { my $s = defined $2 ? $2 : $3; ($open && $s =~ /`/) || $s =~ m/^[\w.\/=+:,-]*\z/ ? $s : "QUOTED" } }gse;
      $r =~ s/`[^`]*`/BT/g unless $open;
      $r =~ tr/`/;/;
      $r =~ s/["\x27\\]//g;
      print "$r\n;\n";
    }') ;;
  *) ARGV="" ;;
esac
# The reader's own reading, of every command: with a backtick it is the third
# one, and the only one that follows a `$(...)` into a quoted string.
ARGV+=$(strip_quoted "$COMMAND" "$Q" | sed -E "s/${Q}([;&|()[:space:]]|\$)/QUOTED\1/g; s/${Q}//g")

# A git invocation ANYWHERE in the command, not only at position one. The old
# `^git ` prefix test meant `cd x && git push --force`, `FOO=1 git ...` and a
# `git` call after a `;` never reached a single check below -- the guard read
# the most common shapes of the thing it exists to stop as "not a git command".
if ! printf '%s\n%s' "$ARGV" "$CMD" | grep -qE '(^|[;&|(/]|[[:space:]])git[[:space:]]'; then
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
#
# A QUOTED ARGUMENT IS STILL AN ARGUMENT. CMD has every quoted span removed:
# `git -C /repo 'push' --force` became `git -C /repo  --force` and matched no
# check, and `git -C "/repo" clean -fdx` became `git -C clean -fdx`, so
# -C took `clean` as its value and the discard passed. ARGV keeps a quoted span
# as its word (strip-quoted.sh, the mark form): a plain token as written, quoted
# prose as one placeholder word. Built above: the gate, the force push check and
# the reset check read both views, the other discard checks read ARGV.
# Both views, one per line: a quoted argument kept as its word (ARGV), and a quoted `git` or `push` bared (CMD).
FORCE_CMD=$(printf '%s\n%s' "$ARGV" "$CMD" | sed -E 's/--force-with-lease(=[^[:space:]]*)?/--lease/g; s/--force-if-includes//g')

# Try line: the refused push as a lease push, built from the words typed ($CMD). A plain word is the only kind
# rebuilt; delete, mirror and :ref forms have no allowed form, so they get none.
gs_plain() { case "$1" in *[\'\"\\\`\$\(\)\<\>\*\?\[\{]*) return 1 ;; esac; }
gs_push_try() { # <one push call>: prints the lease form; fails when nothing was forced or a word cannot be rebuilt
  local w x out="" f=0
  gs_plain "$1" || return 1
  set -f
  for w in $1; do
    case "$w" in
      --force-with-lease*|--force-if-includes) ;;
      --force) f=1; continue ;;
      --de*|--m*|:*) set +f; return 1 ;;
      --*) ;;
      -*d*) set +f; return 1 ;;
      -*f*) f=1; x=${w//f/}; [ "$x" = - ] && continue; w=$x ;;
      +?*) f=1; w=${w#+} ;;
    esac
    out+="$w "
    [ "$w" = push ] && out+="--force-with-lease "
  done
  set +f
  [ "$f" = 1 ] && printf '%s\n' "${out% }"
}
gs_force_try() { # the first push call in the command that gs_push_try can rebuild
  local c t
  while IFS= read -r c; do
    t=$(gs_push_try "$c") && { printf '%s\n' "$t"; return 0; }
  done < <(printf '%s\n' "$CMD" | grep -oE "git${GITOPTS}[[:space:]]+push[^;&|]*")
  return 1
}

# Block force push. A push's arguments stop at a command separator, so the
# next command's own -f or --force is not read as the push's.
PUSH_ARGS="git${GITOPTS}[[:space:]]+push([[:space:]]+[^;&|[:space:]]+)*[[:space:]]+"
if printf '%s' "$FORCE_CMD" | grep -qE "${PUSH_ARGS}(--force|-f([[:space:];&|)]|\$))"; then
  echo "Blocked: force push is not allowed. Use --force-with-lease if absolutely necessary." >&2
  TRY=$(gs_force_try) && echo "Try: $TRY" >&2
  HOOK_FIRE_REASON=force-push
  exit 2
fi

# The other force and delete forms: a short-flag cluster holding f or d
# (-fu, -uf, -d), a +refspec, an empty-source :ref refspec, --delete and
# --mirror. Push arguments stop at a command separator, so a later `echo +1`
# is not read as a refspec.
if printf '%s' "$FORCE_CMD" | grep -qE "${PUSH_ARGS}(-[[:alnum:]]*[fd][[:alnum:]]*|[+:][^;&|[:space:]]+|--de(l(e(te?)?)?)?|--m(i(r(r(or?)?)?)?)?)([[:space:];&|)]|\$)"; then
  echo "Blocked: force push, remote branch deletion and --mirror are not allowed (-f in a flag cluster, a +refspec, a :ref refspec, --delete or -d). Use --force-with-lease if a rewrite is absolutely necessary." >&2
  TRY=$(gs_force_try) && echo "Try: $TRY" >&2
  HOOK_FIRE_REASON=force-push
  exit 2
fi

# CONTRACT of the discard checks, from here to the end. A seat belt against a
# plain mistake, not a sandbox. They are the checks as they were before the
# quote reader was reworked, text for text.
# Known limits, not screened: eval, bash -c '<string>' and any other shell
# given a string, xargs, aliases and functions, a script file.
# Block git reset --hard on main, and each prefix git takes for it (`--h`, `--ha`, `--har`)
if printf '%s\n%s' "$ARGV" "$CMD" | grep -qE "git${GITOPTS}[[:space:]]+reset([[:space:]]+[^;&|()[:space:]]+)*[[:space:]]+--h(a(r(d)?)?)?([[:space:];&|)]|\$)"; then
  echo "Blocked: git reset --hard is dangerous. Use git revert for safe rollbacks." >&2
  HOOK_FIRE_REASON=reset-hard
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
case "$P" in *checkout*|*switch*|*restore*|*clean*|*stash*|*branch*|*worktree*|*reflog*|*gc*) ;; *commit*) [ "${COMMANDECK_BUILDER:-}" = 1 ] || exit 0 ;; *) exit 0 ;; esac
# The subcommand is matched as a whole word, so `git restore-mtime` is not a restore.
DISCARD="(^|[;&|(/]|[[:space:]])git${GITOPTS}[[:space:]]+(checkout|switch|restore|clean|stash|branch|worktree|reflog|gc|commit)[^;&|()[:space:]]*([[:space:]]+[^;&|()[:space:]]+)*"
# A forced worktree remove (D6): it passes only for a command on a FIXED LIST (WT_REM below: `git [-C <dir>] worktree
# remove (-f|--force)... <path>`, words of [A-Za-z0-9_./~@^:+=,-]), so no other call runs between the check and the
# remove, and only while `git -C <path> status --porcelain --untracked-files=all` prints nothing (wt_clean). Who added
# the worktree does not matter: the issue 357 session grant is gone (pass 2), as a grant would excuse a dirty tree.
# Only an absolute path counts: git resolves a relative one from a -C folder or a cd earlier in the command, not the
# hook's. A file marked assume-unchanged or skip-worktree hides its edits from status, so ls-files -v is read first.
WT_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
WT_RAW=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
WW='[A-Za-z0-9_./~@^:+=,-]+' WN='[A-Za-z0-9_./~@^:+=,][A-Za-z0-9_./~@^:+=,-]*' B='[[:blank:]]+'
WT_REM=0; [[ $WT_RAW =~ ^[[:blank:]]*git($B-C$B$WN)?${B}worktree${B}remove($B(-f|--force))+$B(/|~/)${WW}[[:blank:]]*$ ]] && WT_REM=1
wt_canon() { # <absolute path>: the symlinks of its existing part resolved; fails for a relative path or a ".." in the missing part
  local p=$1 rest=
  case $p in /*) ;; "~/"*) p=$HOME/${p#"~/"} ;; *) return 1 ;; esac
  while [ ! -d "$p" ] && [ "$p" != / ] && [ -n "$p" ]; do rest=/${p##*/}$rest; p=${p%/*}; done
  p=$(cd -P "${p:-/}" 2>/dev/null && pwd -P) || return 1
  case $rest in */..|*/../*) return 1 ;; esac
  printf '%s' "${p%/}$rest"
}
wt_path() { # <words after the subcommand>: the first plain word, past the options that take a value
  local skip=0 a
  for a in "$@"; do
    [ "$skip" = 0 ] || { skip=0; continue; }
    case $a in -b|-B|--reason) skip=1 ;; -*) ;; *) printf '%s' "$a"; return 0 ;; esac
  done
  return 1
}
# wt_scratch <words after remove> -- issue 629 (D18): a fixed-list remove of a path strictly under the scratch root, dirty
# or not (a scratch copy is throwaway). The canonical path decides, so `..` and a symlink out stay blocked. This hook
# loads no paths.sh, so the root is paths.sh's default.
wt_scratch() {
  local raw c root; [ "$WT_REM" = 1 ] || return 1
  raw=$(wt_path "$@") || return 1
  c=$(wt_canon "$raw") || return 1
  root=$(cd -P "${COMMANDECK_SCRATCH:-$HOME/.commandeck/scratch}" 2>/dev/null && pwd -P) || return 1
  case $c in "$root"/?*) ;; *) return 1 ;; esac
}
wt_clean() { # <words after remove>: a fixed-list remove of a worktree whose status reads empty; a git failure or a missing path is not clean
  local raw c o; [ "$WT_REM" = 1 ] || return 1
  raw=$(wt_path "$@") || return 1
  c=$(wt_canon "$raw") && [ -d "$c" ] || return 1
  # status never shows an edit to a file marked assume-unchanged (ls-files -v tag lowercase) or skip-worktree (S); an
  # unreadable ls-files is not clean either.
  o=$(git -C "$c" ls-files -v 2>/dev/null) || return 1
  [[ $o =~ (^|$'\n')[a-zS]\  ]] && return 1
  o=$(git -C "$c" status --porcelain --untracked-files=all 2>/dev/null) && [ -z "$o" ]
}
# abbr <--option>: an ERE for the option and each shorter prefix git takes for it (`--forc` is --force), down to one
# letter after the dashes. A prefix git would refuse as ambiguous is read as the option too: that only blocks more.
abbr() {
  local o=$1 r= i
  for ((i = ${#o}; i > 3; i--)); do r="(${o:i-1:1}$r)?"; done
  printf '%s%s' "${o:0:3}" "$r"
}
arg_is() { # <ERE>: one of the call's arguments is exactly this
  local A
  for A in "${ARGS[@]}"; do [[ $A =~ ^($1)$ ]] && return 0; done
  return 1
}
# gs_conflicted <folder> <path>...: every path is unmerged (git diff --diff-filter=U) in the folder, so --ours/--theirs
# only picks a side of a conflict and loses no edit. No path, a --git-dir/--work-tree call (GFLAG), a path not listed
# (a quoted word is a placeholder, an option's value is no path) or a failing git is not conflicted.
gs_conflicted() {
  local d=$1 u p; shift
  [ "$GFLAG" = 0 ] && [ $# -gt 0 ] || return 1
  u=$(git -C "$d" diff --name-only --diff-filter=U 2>/dev/null) || return 1
  for p; do [[ $'\n'$u$'\n' == *$'\n'"$p"$'\n'* ]] || return 1; done
}
while IFS= read -r CALL; do
  set -f; set -- $CALL; set +f
  shift # the git word itself
  # GITOPTS guesses which option takes a value; git's own list decides which
  # word is the subcommand, so `git --no-pager log -- stash` stays a log.
  # GDIR: the folder git runs in, the session's moved by each -C (a cd earlier in the command is not followed).
  # GFLAG: --git-dir or --work-tree moves git somewhere GDIR does not name.
  GDIR=${WT_CWD:-.} GFLAG=0
  while [ $# -gt 0 ]; do
    case "$1" in
      -C) case ${2-} in /*) GDIR=$2 ;; ?*) GDIR=$GDIR/$2 ;; esac; shift; [ $# -gt 0 ] && shift ;;
      --git-dir|--work-tree) GFLAG=1; shift; [ $# -gt 0 ] && shift ;;
      --git-dir=*|--work-tree=*) GFLAG=1; shift ;;
      -c|--namespace|--config-env|--attr-source) shift; [ $# -gt 0 ] && shift ;;
      --) break ;; # git has no bare `--` option: `git grep git -- restore` names a file
      -*) shift ;;
      *) break ;;
    esac
  done
  SUB=${1-}; [ $# -gt 0 ] && shift
  # Everything after `--` is a path, never an option: a file named -n is not a
  # dry run. ARGS = the words before it, PATHS = 1 when it is there, PW = the words after it.
  ARGS=(); PW=(); PATHS=0; WHY=""
  for A in "$@"; do
    if [ "$PATHS" = 1 ]; then PW+=("$A"); elif [ "$A" = -- ]; then PATHS=1; else ARGS+=("$A"); fi
  done
  case "$SUB" in
    checkout)
      # The `--` is optional: two plain words are a commit and a path, and one
      # is a path when it names a file here and no commit. POS = the plain
      # words, less the branch name -b, -B and --orphan take.
      # The one-word case is looked up where git runs (GDIR). shortcut: a cd earlier in the command is not followed.
      POS=(); SKIP=0
      for A in "${ARGS[@]}"; do
        [ "$SKIP" = 0 ] || { SKIP=0; continue; }
        case $A in --orphan|-[bB]|-[a-zA-Z]*[bB]) SKIP=1 ;; -*) ;; *) POS+=("$A") ;; esac
      done
      { [ "$PATHS" = 1 ] || arg_is '\./?' || [ "${#POS[@]}" -ge 2 ] \
        || { [ "${#POS[@]}" = 1 ] && ( cd "$GDIR" 2>/dev/null && [ -e "${POS[0]}" ] && ! git rev-parse -q --verify "${POS[0]}^{commit}" >/dev/null 2>&1 ); }; } \
        && WHY="git checkout of paths (after \`--\`, after a commit, or a file's own name) overwrites uncommitted edits. Commit them or copy them aside first; switching branches is not affected."
      # --ours/--theirs on paths that are all unmerged picks a side of a conflict: nothing uncommitted is lost.
      [ -n "$WHY" ] && arg_is "$(abbr --ours)|$(abbr --theirs)" && gs_conflicted "$GDIR" ${PW[@]+"${PW[@]}"} && WHY=""
      arg_is "$(abbr --force)|-[a-zA-Z]*f[a-zA-Z]*" && WHY="git checkout --force throws away the uncommitted edits a plain checkout would stop for. Commit them or copy them aside first." ;;
    switch)
      arg_is "$(abbr --force)|$(abbr --discard-changes)|-[a-zA-Z]*f[a-zA-Z]*" && WHY="git switch --force (--discard-changes) throws away the uncommitted edits a plain switch would stop for. Commit them or copy them aside first." ;;
    restore)
      { arg_is '--staged|-[a-zA-Z]*S[a-zA-Z]*' && ! arg_is "$(abbr --worktree)|-[a-zA-Z]*W[a-zA-Z]*"; } \
        || WHY="git restore of the working tree overwrites uncommitted edits. Only the index-only \`git restore --staged\` passes."
      # Same pass as checkout; with no `--` the paths are the plain words (an option's value among them is no unmerged path).
      if [ -n "$WHY" ] && arg_is "$(abbr --ours)|$(abbr --theirs)"; then
        if [ "$PATHS" = 1 ]; then RP=("${PW[@]}"); else RP=(); for A in "${ARGS[@]}"; do case $A in -*) ;; *) RP+=("$A") ;; esac; done; fi
        gs_conflicted "$GDIR" ${RP[@]+"${RP[@]}"} && WHY=""
      fi ;;
    clean)
      arg_is "$(abbr --force)|-[a-zA-Z]*f[a-zA-Z]*" && ! arg_is '--dry-run|-[a-zA-Z]*n[a-zA-Z]*' \
        && WHY="git clean -f deletes untracked files (briefs, scratch, handoff files). Preview with \`git clean -n\` and remove what you mean to by name." ;;
    stash)
      case "${ARGS[0]-}" in drop|clear) WHY="git stash ${ARGS[0]} destroys stashed work. Apply it or leave it." ;; esac ;;
    branch)
      { arg_is '-[a-zA-Z]*D[a-zA-Z]*' || { arg_is "$(abbr --delete)|-[a-zA-Z]*d[a-zA-Z]*" && arg_is "$(abbr --force)|-[a-zA-Z]*f[a-zA-Z]*"; }; } \
        && WHY="git branch -D deletes a branch whatever it still holds. Use \`git branch -d\`, which refuses an unmerged branch." ;;
    worktree)
      case "${ARGS[0]-}" in
        remove) arg_is "$(abbr --force)|-f+" && ! wt_clean "${ARGS[@]:1}" && ! wt_scratch "${ARGS[@]:1}" \
          && WHY="git worktree remove --force deletes a worktree with its uncommitted changes. Remove it without --force: \`git worktree remove <path>\`, which git refuses only while the worktree holds changes. (A forced remove passes only a worktree whose status reads clean, a single plain \`git [-C <dir>] worktree remove\` naming its absolute path, including one this session added.)" ;;
      esac ;;
    reflog)
      [ "${ARGS[0]-}" = expire ] && WHY="git reflog expire drops the entries that recover lost commits." ;;
    gc)
      arg_is "$(abbr --prune)=now" && WHY="git gc --prune=now deletes unreachable objects at once, the ones the reflog could still recover. Plain \`git gc\` keeps the grace period." ;;
    commit)
      # Issue 371: builder-codex-pass.sh commits what is staged, under its own message, inside the script (this hook sees only
      # the `bash .../builder-codex-pass.sh` call). Outside a Builder pane the fast path above has already passed the call.
      if [ "${COMMANDECK_BUILDER:-}" = 1 ]; then
        WHY="a Builder never commits by hand: builder-codex-pass.sh commits what is staged, under its own message. Stage the work and run the pass."
        ! grep -qiE 'co-authored-by:.*(claude|anthropic|codex|openai)' <<<"$WT_RAW" || WHY="$WHY This message also carries a model co-author trailer, which no Builder commit may carry."
      fi ;;
  esac
  [ -n "$WHY" ] || continue
  echo "Blocked: $WHY" >&2
  [ "$SUB" != gc ] || echo "Try: git gc" >&2
  HOOK_FIRE_REASON=git-unsafe-command
  exit 2
done < <(printf '%s\n' "$ARGV" | grep -oE "$DISCARD")

exit 0

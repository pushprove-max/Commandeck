#!/usr/bin/env bash
# PreToolUse hook: block dangerous git operations
# Input: JSON on stdin with tool_input.command

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# --record-add (PostToolUse, Bash; issue 357): a call that exited 0 may have added a temporary worktree. The same
# reading of the command runs, but it only records ownership and never blocks. PreToolUse writes the add's claim.
MODE=pre
[ "${1-}" != --record-add ] || { MODE=record; exec 2>/dev/null; trap 'exit 0' EXIT; }
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
type strip_quoted >/dev/null 2>&1 || { echo "BLOCKED: ${BASH_SOURCE[0]##*/} could not load hooks/lib/strip-quoted.sh, so it cannot screen this command. Restore it (git checkout hooks/lib/strip-quoted.sh) and retry." >&2; exit 2; }
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
[ -z "$ODD" ] || { echo "Blocked: a here-document's end word is not plain: $ODD -- use one plain word such as EOF (letters, digits, _ . -), bare or in one pair of quotes." >&2; exit 2; }
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
if printf '%s' "$FORCE_CMD" | grep -qE "${PUSH_ARGS}(-[[:alnum:]]*[fd][[:alnum:]]*|[+:][^;&|[:space:]]+|--de(l(e(te?)?)?)?|--m(i(r(r(or?)?)?)?)?)([[:space:];&|)]|\$)"; then
  echo "Blocked: force push, remote branch deletion and --mirror are not allowed (-f in a flag cluster, a +refspec, a :ref refspec, --delete or -d). Use --force-with-lease if a rewrite is absolutely necessary." >&2
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
# Temporary worktree ownership (issue 357). A forced remove of a worktree is blocked, except one this session added
# on a path under the temporary folder. Two proofs, both of one add. The add's own success: only a command on a FIXED
# LIST shows it (WT_ADD below: `git [-C <dir>] worktree add [-q|--quiet|--detach|--no-checkout|-b <name>|-B <name>]...
# <path> [<commit>]`, words of [A-Za-z0-9_./~@^:+=,-]; no other git option, as `--version` exits 0 with no add): its exit
# status is the add's, PostToolUse fires only on exit 0, and git's add fails on a path that holds anything. And the
# claim: PreToolUse of such an add, while the path is absent, writes this session's id beside it
# (<parent>/.commandeck-add.<name>, one mv); a later hooked add of the path replaces it. PostToolUse (--record-add)
# writes the grant only while the claim still names this session, so a record step that runs late cannot take a
# worktree re-made at the path since. The grant: this session's id in that worktree's own git folder
# (<main>/.git/worktrees/<name>/commandeck-owner), once, when git names the path once. Git deletes that folder with
# the worktree, so a grant never outlives it. The forced remove that uses a grant must be on the fixed list too
# (WT_REM), so no other call runs between this check and the remove. No session id: owns nothing. Only an absolute
# path counts: git resolves a relative one from a -C folder or a cd earlier in the command, not the hook's.
# Stated limit: the hook reads no worktree status before the forced remove, so a forced remove of a worktree this session
# added deletes whatever it holds, a file marked assume-unchanged or skip-worktree included.
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
WT_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
WT_RAW=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
WW='[A-Za-z0-9_./~@^:+=,-]+' WN='[A-Za-z0-9_./~@^:+=,][A-Za-z0-9_./~@^:+=,-]*' B='[[:blank:]]+'
WT_ADD=0; [[ $WT_RAW =~ ^[[:blank:]]*git($B-C$B$WN)?${B}worktree${B}add($B(-q|--quiet|--detach|--no-checkout)|$B-[bB]$B$WN)*$B(/|~/)$WW($B$WN)?[[:blank:]]*$ ]] && WT_ADD=1
WT_REM=0; [[ $WT_RAW =~ ^[[:blank:]]*git($B-C$B$WN)?${B}worktree${B}remove($B(-f|--force))+$B(/|~/)${WW}[[:blank:]]*$ ]] && WT_REM=1
wt_canon() { # <absolute path>: the symlinks of its existing part resolved; fails for a relative path or a ".." in the missing part
  local p=$1 rest=
  case $p in /*) ;; "~/"*) p=$HOME/${p#"~/"} ;; *) return 1 ;; esac
  while [ ! -d "$p" ] && [ "$p" != / ] && [ -n "$p" ]; do rest=/${p##*/}$rest; p=${p%/*}; done
  p=$(cd -P "${p:-/}" 2>/dev/null && pwd -P) || return 1
  case $rest in */..|*/../*) return 1 ;; esac
  printf '%s' "${p%/}$rest"
}
wt_in_tmp() { # <canonical path>: below the temporary folder
  local r
  for r in "$(wt_canon "${TMPDIR:-/tmp}")" /tmp /private/tmp; do
    case $1 in "${r%/}"/?*) return 0 ;; esac
  done
  return 1
}
wt_path() { # <words after the subcommand>: the first plain word, past the options that take a value
  local skip=0 a
  for a in "$@"; do
    [ "$skip" = 0 ] || { skip=0; continue; }
    case $a in -b|-B|--reason) skip=1 ;; -*) ;; *) printf '%s' "$a"; return 0 ;; esac
  done
  return 1
}
wt_grant() { # <canonical path>: the grant file of the linked worktree whose top folder is exactly that path
  local o top gd gc
  o=$(git -C "$1" rev-parse --path-format=absolute --show-toplevel --git-dir --git-common-dir 2>/dev/null) || return 1
  { read -r top; read -r gd; read -r gc; } <<<"$o"
  [ "$(cd -P "$top" 2>/dev/null && pwd -P)" = "$1" ] && [ -n "$gd" ] && [ "$gd" != "$gc" ] || return 1
  printf '%s/commandeck-owner' "$gd"
}
wt_add() { # <words after add>: a fixed-list add of a tmp path. PreToolUse claims the path while it is absent;
  # PostToolUse grants while the claim still names this session, the path is a linked worktree and git names it once
  local raw c k g l n=0; [ "$WT_ADD" = 1 ] && [ -n "$SID" ] || return 0
  raw=$(wt_path "$@") || return 0
  c=$(wt_canon "$raw") && wt_in_tmp "$c" || return 0
  k=${c%/*}/.commandeck-add.${c##*/}
  if [ "$MODE" = pre ]; then
    if [ -e "$c" ] || [ -L "$c" ]; then return 0; fi
    { mkdir -p "${c%/*}" && printf '%s\n' "$SID" > "$k.$$" && mv -f "$k.$$" "$k"; } 2>/dev/null || rm -f "$k.$$"
    return 0
  fi
  [ "$(cat "$k" 2>/dev/null)" = "$SID" ] && g=$(wt_grant "$c") || return 0
  while IFS= read -r l; do
    case $l in "worktree "*) [ "$(cd -P "${l#worktree }" 2>/dev/null && pwd -P)" = "$c" ] && n=$((n + 1)) ;; esac
  done < <(git -C "$c" worktree list --porcelain 2>/dev/null)
  [ "$n" = 1 ] && ( set -C; printf '%s\n' "$SID" > "$g" ) 2>/dev/null
  return 0
}
wt_owned() { # <words after remove>: a fixed-list remove of the worktree at that path, under tmp, with this session's grant
  local raw c g; [ "$WT_REM" = 1 ] && [ -n "$SID" ] || return 1
  raw=$(wt_path "$@") || return 1
  c=$(wt_canon "$raw") && wt_in_tmp "$c" && g=$(wt_grant "$c") && [ "$(cat "$g" 2>/dev/null)" = "$SID" ]
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
while IFS= read -r CALL; do
  set -f; set -- $CALL; set +f
  shift # the git word itself
  # GITOPTS guesses which option takes a value; git's own list decides which
  # word is the subcommand, so `git --no-pager log -- stash` stays a log.
  # GDIR: the folder git runs in, the session's moved by each -C (a cd earlier in the command is not followed).
  GDIR=${WT_CWD:-.}
  while [ $# -gt 0 ]; do
    case "$1" in
      -C) case ${2-} in /*) GDIR=$2 ;; ?*) GDIR=$GDIR/$2 ;; esac; shift; [ $# -gt 0 ] && shift ;;
      -c|--git-dir|--work-tree|--namespace|--config-env|--attr-source) shift; [ $# -gt 0 ] && shift ;;
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
      # The one-word case is looked up where git runs (GDIR). shortcut: a cd earlier in the command is not followed.
      POS=(); SKIP=0
      for A in "${ARGS[@]}"; do
        [ "$SKIP" = 0 ] || { SKIP=0; continue; }
        case $A in --orphan|-[bB]|-[a-zA-Z]*[bB]) SKIP=1 ;; -*) ;; *) POS+=("$A") ;; esac
      done
      { [ "$PATHS" = 1 ] || arg_is '\./?' || [ "${#POS[@]}" -ge 2 ] \
        || { [ "${#POS[@]}" = 1 ] && ( cd "$GDIR" 2>/dev/null && [ -e "${POS[0]}" ] && ! git rev-parse -q --verify "${POS[0]}^{commit}" >/dev/null 2>&1 ); }; } \
        && WHY="git checkout of paths (after \`--\`, after a commit, or a file's own name) overwrites uncommitted edits. Commit them or copy them aside first; switching branches is not affected."
      arg_is "$(abbr --force)|-[a-zA-Z]*f[a-zA-Z]*" && WHY="git checkout --force throws away the uncommitted edits a plain checkout would stop for. Commit them or copy them aside first." ;;
    switch)
      arg_is "$(abbr --force)|$(abbr --discard-changes)|-[a-zA-Z]*f[a-zA-Z]*" && WHY="git switch --force (--discard-changes) throws away the uncommitted edits a plain switch would stop for. Commit them or copy them aside first." ;;
    restore)
      { arg_is '--staged|-[a-zA-Z]*S[a-zA-Z]*' && ! arg_is "$(abbr --worktree)|-[a-zA-Z]*W[a-zA-Z]*"; } \
        || WHY="git restore of the working tree overwrites uncommitted edits. Only the index-only \`git restore --staged\` passes." ;;
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
        add) wt_add "${ARGS[@]:1}" ;;
        remove) arg_is "$(abbr --force)|-f+" && ! wt_owned "${ARGS[@]:1}" \
          && WHY="git worktree remove --force deletes a worktree with its uncommitted changes. Remove it without --force: \`git worktree remove <path>\`, which git refuses only while the worktree holds changes. (A temporary worktree this session added, both commands a single plain \`git [-C <dir>] worktree add|remove\` naming its absolute path, is the exception.)" ;;
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
  exit 2
done < <(printf '%s\n' "$ARGV" | grep -oE "$DISCARD")

exit 0

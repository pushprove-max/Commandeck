#!/usr/bin/env bash
# PreToolUse hook on Bash and Edit|Write|MultiEdit (issue 317): while a detached merge holds main, refuse what would
# change main's tree under it, naming the merge. merge-unit-local.sh detaches itself and writes its state
# (merge-unit-local.state, beside its lock in the git dir) while it runs; its pid being alive is "live". The orchestrator
# once took a half-merged tree for a killed merge and stashed it, and the merge went on testing main without the unit.
# A fixed list, not a replay of the shell (the owner's ruling on issue 317's fix round r2: r1 and r2 found ways round a
# replay of cd order and control flow). While a merge is live:
# - A session whose folder (the input's cwd) is in main's checkout runs only git calls in a read form (reads(), the
#   owner's ruling on fix round r3: a form, not a subcommand's name, since r3 found reads that write); any other (an
#   alias too) is refused, whatever folder it names, and so is an edit of any file of main's checkout. Its commands
#   but git are an allow list too (allowed(), the owner's ruling on fix round r6: r6 found a read piped into tee,
#   patch or sh, and rm or sed -i with no git at all). Its command has no $ and no backtick anywhere, and printf no -v
#   (r8: bash runs a $( ) a string holds when it evaluates it as a subscript, arithmetic or a prompt, as test -v, wait -p,
#   [[ ]], $[x], ${!x} and ${x@P} do, quoted or not; with no $ or backtick typed and no printf -v, no string holds one).
# - Elsewhere, a command with a git call in no read form is refused when any folder it names anywhere (a cd or pushd,
#   git's -C, --git-dir, --work-tree, a GIT_DIR=, GIT_WORK_TREE=, GIT_COMMON_DIR= or GIT_OBJECT_DIRECTORY=), read from the session's folder or from any other
#   folder it names, is main's checkout or git dir; or is a folder the words cannot tell (a variable, a substitution,
#   quoted prose, a folder not made yet, or any folder of a git call after a word such as env -C or xargs) while the
#   session's repo (else its project, CLAUDE_PROJECT_DIR) has a live merge, or no repo is known. A Builder's
#   worktree shares the git dir but not the tree, so its own work is allowed.
# - In a command with a git call, a redirection's output file (any command's: a { } or ( ) group, a loop, exec) is
#   refused in main's checkout or git dir, wherever the session is: the shell writes it before git starts (r6). It is
#   the whole file, links followed, as for an edit; a file the words cannot place (an expansion, a glob, a hard link,
#   one not made yet in a line of several commands) is refused like a folder they cannot tell (r7).
# - A file git is given to write is checked as a redirection's is (r14): GIT_INDEX_FILE, GIT_CONFIG, GIT_CONFIG_GLOBAL,
#   GIT_CONFIG_SYSTEM and a GIT_TRACE* path, which a read form writes too. In a git call in no read form, each argument
#   (a word, an option's value) is checked where the words place it, a folder already there as itself (r15); one they
#   cannot (a $ value, quoted prose, a glob) or a link the line makes is not seen: most such words are messages,
#   revisions or pathspecs.
# - From any checkout of main's git dir, a git call that writes what they share in a way that moves main's branch or
#   sets what main's git runs (shares(): config, update-ref, gc, ...) is refused (the owner's ruling, r6).
# /usr/bin/git is git, and a shell given a string (bash -c, eval) has that string read as commands.
# Not seen, an accepted gap (the owner's ruling, same round): a script file and a GIT_DIR exported outside the command.
# Of the same gap (the owner's ruling, r9): a program git's config names, which a read form runs (diff.external, a
# textconv or filter driver, core.fsmonitor, a pager, gpg's program): code that exists before the command, as a script.
# Of the same gap (the owner's ruling, r10): outside held main the guard screens the git calls a command types, not
# code the command builds from data (a $( ) in a here-document's body, text fed to a shell or an interpreter, a command
# word made by an expansion or an ANSI-C quote). Held main stays closed by its allow list and its no-$ rule.
# Of the same gap (the owner's ruling, r16), in held main too: script text fed to bash or sh (/dev/stdin, /dev/fd, a
# /proc fd, a fifo), which allowed() takes as the script file the r6 ruling lets main run.
# Not seen either, an accepted gap (the owner's ruling, r7), from main's checkout: orca-ide terminal send, which types
# a command into another terminal.
# Self-test: bash hooks/__tests__/merge-lock-guard.test.sh
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
cd "$(jq -r '.cwd // empty' <<<"$INPUT")" 2>/dev/null || true

# live <common git dir> -- 0 and STATE set when a merge holds main there with a live pid; a dead pid is stale.
live() {
  STATE=$1/merge-unit-local.state
  PID=$(sed -n 's/^pid=//p' "$STATE" 2>/dev/null)
  [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null
}
refuse() { # <what>
  local unit=$(sed -n 's/^unit=//p' "$STATE") sha=$(sed -n 's/^sha=//p' "$STATE") stage=$(sed -n 's/^stage=//p' "$STATE") log=$(sed -n 's/^log=//p' "$STATE")
  echo "BLOCKED: $1. The merge of $unit (reviewed ${sha:0:8}) is running detached as pid $PID, stage $stage, and holds main's checkout; its log: $log" >&2
  echo "It detaches on purpose and keeps running after the shell call that started it ended, so a half-merged tree is the merge at work, not leftovers. Wait for the end of its log or the message it sends main; do not stash, reset or check out under it, and do not run it again." >&2
  echo "If it is hung: kill $PID. Its lock is then stale and main is yours." >&2
  exit 2
}
# at <folder> <path> -- the folder <path> names from <folder>: ? when the words cannot tell, empty when it does not exist.
at() {
  local p=$2
  case $1$p in '?'*|*'$'*|*QUOTED*|*'`'*|*'*'*) echo '?'; return ;; esac
  case $p in '~'|'~/'*) p=$HOME${p#\~} ;; '~'*|-|'?') echo '?'; return ;; /*) ;; *) [ -n "$1" ] || return 0; p=$1/$p ;; esac
  (cd "$p" 2>/dev/null && pwd -P)
}
# real <path> -- the absolute <path> with its last part's links followed to the end (a dangling one too: writing it makes
# its target); ? when it is one file of two names (a hard link, the other perhaps in main) or links that do not end (r7).
real() {
  local p=$1 t n=0
  while [ -L "$p" ]; do
    [ $n -lt 40 ] || { echo '?'; return; }
    t=$(readlink "$p"); case $t in /*) p=$t ;; *) p=${p%/*}/$t ;; esac; n=$((n+1))
  done
  [ -z "$(find "$p" -maxdepth 0 -type f -links +1 2>/dev/null)" ] && echo "$p" || echo '?'
}
# file_at <folder> <word> -- the folder of the file a redirection to <word> writes, read from <folder>: ? when the words
# cannot tell (an expansion, a glob, a hard link, or a file not made yet in a line of more than one command, which may
# make it a link first), empty when that folder does not exist. The whole file, not the part before its last / (r7);
# a folder already there is itself, where git writes into it (format-patch -o, a GIT_TRACE2 folder; r15).
file_at() {
  local p=$2
  case $p in *'$'*|*QUOTED*|*'`'*|*'*'*|*'?'*|*'['*|'~'[!/]*) echo '?'; return ;; '~'|'~/'*) p=$HOME${p#\~} ;; /*) ;; *) p=$1/$p ;; esac
  p=$(real "$p")
  [ "$p" != '?' ] && { [ -e "$p" ] || [ "$NS" -le 1 ]; } || { echo '?'; return; }
  [ -d "$p" ] || p=${p%/*}; (cd "${p:-/}" 2>/dev/null && pwd -P)
}
# mains <folder> -- refuses when it is in a checkout that is its git dir's own (main's, not a linked worktree's), or is
# that git dir, and a live merge holds it.
mains() {
  local g
  case $1 in
    '') ;;
    # From outside a repo the session's project (Claude Code's CLAUDE_PROJECT_DIR) is the one to check (r2); with
    # neither, no merge can be ruled out.
    '?') g=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || git -C "${CLAUDE_PROJECT_DIR:-/}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
      || { echo "BLOCKED: ${WHAT:-git $SUB} with a folder this guard cannot read (a variable, a substitution, quoted prose, a glob, a hard link, a folder or file not made yet, or a word before git such as env -C), from outside any repository: it cannot tell whether a merge holds that folder. Name the folder as a plain path." >&2; exit 2; }
      live "$g" && refuse "${WHAT:-git $SUB} with a folder this guard cannot read (a variable, a substitution, quoted prose, a glob, a hard link, a folder or file not made yet, or a word before git such as env -C) while a merge holds main; name the folder as a plain path" ;;
    *) held "$1" && refuse "${WHAT:-git $SUB} in main's checkout" ;;
  esac
}
# held <folder> -- 0 when it is in a checkout that is its git dir's own, or is that git dir, and a live merge holds it.
held() {
  local g
  g=$(git -C "$1" rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null) && [ "${g%%$'\n'*}" = "${g#*$'\n'}" ] && live "${g#*$'\n'}"
}
# reads <subcommand> <word>... -- 0 when the call is one of the fixed read forms (the owner's ruling, fix round r3): it
# touches neither main's index, its files nor its refs. Of these subcommands' options, git's man pages name only diff/
# log/show's --output and grep's -O as writing a file or starting a program. git takes any unique prefix of a long
# option (r4: --open-files is --open-files-in-pager), so a long option is matched as a prefix of those two.
reads() {
  local s=$1 w; shift
  case $s in
    status|log|show|diff|grep|blame|rev-parse|ls-files|ls-tree|cat-file|merge-base|describe|shortlog|rev-list|for-each-ref|show-ref|version|help)
      for w; do
        case $s/$w in grep/-O*|grep/-[!-]*O*) return 1 ;; esac
        case $w in --?*) ! [[ --output == "${w%%=*}"* || $s = grep && --open-files-in-pager == "${w%%=*}"* ]] || return 1 ;; esac
      done ;;
    branch) for w; do case $w in -a|-r|-v|-vv|--list|--show-current) ;; *) return 1 ;; esac; done ;;
    worktree) [ "${1-}" = list ] ;;
    remote) [ $# = 0 ] || [[ $# = 1 && $1 =~ ^(-v|--verbose)$ ]] ;;
    config) case ${1-} in
        --get|--get-all|--get-regexp) shift; for w; do [[ $w != -* ]] || return 1; done ;;
        --list|-l) [ $# = 1 ] ;;
        *) return 1 ;;
      esac ;;
    *) return 1 ;;
  esac
}
# shares <subcommand> <word>... -- 0 when the call writes the git dir all checkouts share so that main's branch moves
# or main's git runs something new. git itself refuses branch -f/-d, push and checkout of a branch checked out in
# main; it allows branch -m/-M, fetch -u, checkout/switch --ignore-other-worktrees and the rest of these. Long options
# are matched by prefix, as git does (r4).
shares() {
  local s=$1 w o n=0; shift
  case $s in
    update-ref|gc|prune|prune-packed|repack|pack-refs|maintenance|replace|filter-branch) return 0 ;;
    config) ! reads config "$@" ;;
    reflog) [[ ${1-} =~ ^(expire|delete|drop|write)$ ]] ;;
    worktree) [[ ${1-} =~ ^(prune|remove)$ ]] ;;
    symbolic-ref) for w; do case $w in -d|--d*) return 0 ;; -m) n=$((n-1)) ;; -*) ;; *) n=$((n+1)) ;; esac; done; [ $n -ge 2 ] ;;
    branch|fetch|checkout|switch)
      case $s in branch) o=--move ;; fetch) o=--update-head-ok ;; *) o=--ignore-other-worktrees ;; esac
      for w; do
        case $s/$w in branch/-[mM]*|branch/-[!-]*[mM]*|fetch/-u*|fetch/-[!-]*u*) return 0 ;; esac
        case $w in --?*) [[ $o != "${w%%=*}"* ]] || return 0 ;; esac
      done
      return 1 ;;
    *) return 1 ;;
  esac
}
# allowed <word>... -- 0 when one simple command with no git call is on the list main's checkout runs while held (the
# owner's ruling, r6): a program that only reads, a shell keyword, cd, a bare assignment, orca-ide, bash <script file>,
# and kill, which the refusal names as the way to end a hung merge.
allowed() {
  while [ $# -gt 0 ] && [[ $1 =~ ^([{}!]|if|then|else|elif|fi|do|done|while|until|time)$ ]]; do shift; done
  [ $# -gt 0 ] || return 0
  case $1 in
    printf) [[ ${2-} != -v* ]] ;; # -v stores a string a later subscript can run (r8)
    for|ls|cat|head|tail|wc|grep|jq|echo|test|'['|'[['|pwd|date|sleep|true|false|:|exit|wait|kill|cd|pushd|popd|orca-ide) return 0 ;;
    # rg: a fixed list of options that read (r7: --pre, --hostname-bin and -z run a program).
    rg) shift; for w; do [[ $w != -* || $w =~ ^(-[nNisSlcHIFwxvoqUuLP.]+|-[ABCmMd][0-9]*|-[egtT].*|--(files|hidden|no-ignore|no-heading|heading|files-with-matches|files-without-match|count|count-matches|fixed-strings|ignore-case|smart-case|case-sensitive|word-regexp|line-regexp|line-number|no-line-number|with-filename|no-filename|invert-match|only-matching|quiet|follow|json|vimgrep|column|stats|type-list|multiline|unrestricted)|--(glob|iglob|type|type-not|max-count|context|after-context|before-context|max-depth|max-columns|color|sort|sortr|regexp)(=.*)?)$ ]] || return 1; done ;;
    sed) shift; sedreads "$@" ;;
    bash|sh) [ $# -gt 1 ] && [[ $2 != -* ]] ;;
    *) for w; do [[ $w =~ ^[[:alpha:]_][[:alnum:]_]*= ]] || return 1; done ;; # NAME=value before a command can run code
  esac
}
# sedreads <word>... -- 0 when sed only prints: options -n -E -r -e, and its script one command that prints, deletes
# from the output, quits or substitutes. -i writes the file; the w/W commands and s///w, s///e write or run.
sedreads() {
  local s= e= w R='/([^/\]|\.)*/' A C
  A='([0-9]+|\$|'$R')' C='^('$A'(,'$A')?)?!?([pdqn=]|s'$R'([^/\]|\.)*/[gpI0-9]*)$'
  for w; do
    if [ -n "$e" ]; then e=; [[ $w =~ $C ]] || return 1; s=1; continue; fi
    case $w in
      -e) e=1 ;;
      -n|-E|-r|-nE|-En|-nr|-rn|--quiet|--silent) ;;
      -*) return 1 ;;
      *) [ -n "$s" ] || [[ $w =~ $C ]] || return 1; s=1 ;;
    esac
  done
}
# simple <word>... -- one simple command: the folders it names go in F, its output files' folders in T, its git call
# sets SUB when no read form and SHR when it writes what the checkouts share, and in held main a command off the
# list sets X.
simple() {
  local pre= odd= k=() r= w
  NS=$((NS+1))
  # A redirection and its target are no words of the command.
  for w; do
    case $r in
      '<') r=; continue ;;
      '>') r=; [ "$w" = /dev/null ] || T+=("$w"); continue ;;
    esac
    case $w in '<'|'<<'|'<<<') r='<' ;; '>'|'>>'|'<>') r='>' ;; *) k+=("$w") ;; esac
  done
  set -- ${k[@]+"${k[@]}"}
  while [ $# -gt 0 ] && [[ ! $1 =~ (^|/)git$ ]]; do
    case $1 in
      GIT_DIR=*|GIT_WORK_TREE=*|GIT_COMMON_DIR=*|GIT_OBJECT_DIRECTORY=*) F+=("${1#*=}"); odd=1 ;;
      GIT_TRACE*=[0-9]|GIT_TRACE*=true|GIT_TRACE*=false) odd=1 ;; # stderr or a fd: git traces to a file only by its path
      # Files git writes, a read form too (status refreshes the index; a trace is appended to): a redirection's (r14).
      GIT_INDEX_FILE=*|GIT_CONFIG=*|GIT_CONFIG_GLOBAL=*|GIT_CONFIG_SYSTEM=*|GIT_TRACE*=*) T+=("${1#*=}"); odd=1 ;;
      cd|pushd) [[ ${2-} != -?* ]] || shift; F+=("${2-~}") ;;
      # An assignment can make a read run a program (GIT_EXTERNAL_DIFF); any other word but a keyword (env -C, xargs,
      # find -execdir) can move where git runs.
      *) if [[ $1 =~ ^[[:alpha:]_][[:alnum:]_]*= ]]; then odd=1; elif [[ ! $1 =~ ^([{!]|if|then|else|elif|do|while|until|time)$ ]]; then pre=1; fi ;;
    esac
    shift
  done
  [ $# -gt 0 ] || { [ -z "$HELD" ] || allowed ${k[@]+"${k[@]}"} || X=${X:-${k[0]}}; return 0; }; shift
  # A global option but these makes the call no read form (-c core.fsmonitor runs a program).
  while [ $# -gt 0 ]; do
    case $1 in
      -C) F+=("${2-}"); shift ;;
      --git-dir|--work-tree) F+=("${2-}"); shift; odd=1 ;;
      --git-dir=*|--work-tree=*) F+=("${1#*=}"); odd=1 ;;
      -c|--namespace|--config-env) shift; odd=1 ;;
      --no-pager|--no-optional-locks) ;;
      -*) odd=1 ;;
      *) break ;;
    esac
    shift
  done
  [ $# = 0 ] || ! shares "$@" || SHR=${SHR:-$1}
  # After a word such as xargs, a git with no subcommand typed takes it from its input (r10).
  [ $# = 0 ] && [ -z "$pre" ] || { [ -z "$pre$odd" ] && reads "$@"; } || { SUB=${SUB:-${1:-<its input>}}; [ -z "$pre" ] || F+=('?'); A+=("$@"); }
}

TOOL=$(jq -r '.tool_name // empty' <<<"$INPUT")
if [ "$TOOL" = Bash ]; then
  COMMAND=$(jq -r '.tool_input.command // empty' <<<"$INPUT")
  P=${COMMAND//[\'\"\\]/}
  HELD=; held "$PWD" && HELD=1
  [ -z "$HELD" ] || [[ $COMMAND != *[\$\`]* ]] || refuse "a \$ or a backtick in a command in main's checkout while a merge holds it (a string bash evaluates can run the command it holds); type the value"
  [[ $P == *git* ]] || [ -n "$HELD" ] || exit 0
  . "${BASH_SOURCE[0]%/*}/lib/strip-quoted.sh" 2>/dev/null
  type strip_quoted >/dev/null 2>&1 || { echo "BLOCKED: ${BASH_SOURCE[0]##*/} could not load hooks/lib/strip-quoted.sh, so it cannot screen this command. Reinstall the plugin and retry." >&2; exit 2; }
  # A shell given a string runs that string: it is read, its quotes taken out, as the commands after a ;.
  SH='(^|[^[:alnum:]_.-])(eval|(ba|z|da|k)?sh([[:space:]]+-[a-z]+)*[[:space:]]+-[a-z]*c[a-z]*)([[:space:]]|$)'
  if [[ $P =~ $SH ]]; then CMD=$(sed -E "s/$SH/\\1;\\5/g" <<<"$P")
  # A quoted span that is one plain word stays the word git gets (git -C "/main" 'stash'); quoted prose is QUOTED.
  else Q=$'\x01'; CMD=$(strip_quoted "$COMMAND" "$Q" | sed -E "s/${Q}([;&|()[:space:]]|\$)/QUOTED\\1/g; s/${Q}//g"); fi
  # Each operator a word of its own (a redirection's & is none, and 2>&1 names no file), each redirection too, its fd
  # number dropped and >| read as >; a line's end is a ;.
  set -f; set -- $(sed -E 's/[0-9]*>&[0-9-]+//g; s/>&|&>/>/g; s/>\|/>/g; s/(^|[[:space:]])[0-9]+([<>])/\1\2/g; s/(<>|>>|<<<|<<|>|<)/ \1 /g; s/(\|\||&&|[;&|()`])/ \1 /g; s/$/ ;/' <<<"$CMD"); set +f
  F=() T=() A=() NS=0 SUB= SHR= X= WHAT= WORDS=()
  for w in "$@"; do
    case $w in
      ';'|'&'|'&&'|'||'|'|'|'('|')'|'`') [ ${#WORDS[@]} = 0 ] || simple "${WORDS[@]}"; WORDS=() ;;
      *) WORDS+=("$w") ;;
    esac
  done
  [ -z "$X" ] || refuse "$X is off the list main's checkout runs while a merge holds it (git read forms, ls, cat, head, tail, wc, grep, rg, jq, sed that only prints, echo, printf without -v, test, pwd, date, sleep, cd, kill, orca-ide, bash <script file>)"
  [ -n "$SUB" ] || [ ${#T[@]} != 0 ] || exit 0
  [ -z "$SUB" ] || mains "$PWD"
  # Every folder named, read from the session's folder and from each folder found so far: no order is trusted. With
  # only reads, the folders are only where a redirection's file may be.
  B=("$PWD") SEEN=$'\n'$PWD$'\n' HIT=$'\n' n=0
  while [ $n -lt ${#B[@]} ]; do
    for w in ${F[@]+"${F[@]}"}; do
      g=$(at "${B[$n]}" "$w")
      case $g in '') ;; '?') [ -z "$SUB" ] || mains '?' ;; *) HIT+=$w$'\n'; [[ $SEEN == *$'\n'$g$'\n'* ]] || { SEEN+=$g$'\n'; B+=("$g"); [ -z "$SUB" ] || mains "$g"; } ;; esac
    done
    n=$((n+1))
  done
  # A folder no named folder holds (one the command makes: ln -s <main> m && git -C m) cannot be read either.
  [ -z "$SUB" ] || for w in ${F[@]+"${F[@]}"}; do [[ $HIT == *$'\n'$w$'\n'* ]] || mains '?'; done
  # Every folder named, a Builder's worktree too, shares the git dir: any live merge on it refuses such a write.
  [ -z "$SHR" ] || for b in "${B[@]}"; do
    g=$(git -C "$b" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && live "$g" && refuse "git $SHR writes the git dir main's checkout shares (main's branch, its config or objects)"
  done
  # A redirection's file is written whatever the command is, so it is read from every folder found, a read's too.
  WHAT="a file the command writes (a redirection's, or the index, config or trace git is given)"
  for w in ${T[@]+"${T[@]}"}; do
    h=
    for b in "${B[@]}"; do g=$(file_at "$b" "$w"); [ -z "$g" ] || { h=1; mains "$g"; }; done
    [ -n "$h" ] || mains '?'
  done
  # An argument of a git call in no read form may be a file it writes (--output=, -o<file>, --prefix=, worktree add
  # <path>; r14): each word, an option's value and a glued short option's, read from every folder found. One not made
  # yet is read by its folder; a link or hard link is '?'. A word the words cannot place (a $ value, quoted prose, a
  # glob) is no path known: most are messages, revisions or pathspecs.
  WHAT="git $SUB with an argument that names a file"
  for w in ${A[@]+"${A[@]}"}; do
    case $w in --*=*) w=${w#*=} ;; --*|-) continue ;; -?*) w=${w:2} ;; esac
    [ -n "$w" ] || continue
    for b in "${B[@]}"; do
      g=$(NS=1 file_at "$b" "$w")
      case $g in '') ;; '?') case $w in *[\$\`*?[]*|*QUOTED*|'~'[!/]*) ;; *) mains '?' ;; esac ;; *) [[ $SEEN == *$'\n'$g$'\n'* ]] || { SEEN+=$g$'\n'; mains "$g"; } ;; esac
    done
  done
  exit 0
fi

FILE_PATH=$(jq -r '.tool_input.file_path // empty' <<<"$INPUT")
[ -n "$FILE_PATH" ] || exit 0
# A relative path is the session folder's; with no / in it, the walk up below would never end.
case $FILE_PATH in /*) ;; *) FILE_PATH=$PWD/$FILE_PATH ;; esac
# The file's own checkout, not the session's: main reaching into main from a worktree pane is the same edit. A link is
# the file it ends at, and a hard link's other name cannot be found (r7).
P=$(real "$FILE_PATH")
[ "$P" != '?' ] || { WHAT="editing $FILE_PATH"; mains '?'; exit 0; }
D=${P%/*}
while [ -n "$D" ] && [ ! -d "$D" ]; do D=${D%/*}; done
C=$(git -C "${D:-/}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
[ "$(git -C "${D:-/}" rev-parse --path-format=absolute --git-dir 2>/dev/null)" = "$C" ] || exit 0
live "$C" || exit 0
refuse "editing $FILE_PATH in main's checkout"

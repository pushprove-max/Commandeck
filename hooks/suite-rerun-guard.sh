#!/usr/bin/env bash
# PreToolUse hook (Bash): a test suite or type check is run ONCE per state of
# the tree. Agent-neutral (fires for Codex through codex-dispatch.sh).
#
# ALSO the PostToolUse half: `--record-complete` on the same Bash payload is
# what marks a run as having actually happened. The PreToolUse pass records the
# attempt as PENDING and only a COMPLETED record blocks the next run, so a
# command that a later hook refused, or that the operator interrupted, does not
# leave a "you already ran this" behind for a run that never started.
#
# Measured on the walkthrough-remediation PR (2026-09-03): 22 of 116 suite and
# tsc runs across seven workers were the SAME command on an UNCHANGED tree,
# minutes apart, 27 minutes of runner time -- an agent piping a suite through
# `tail`/`grep`, losing the line it wanted, and running the whole suite again
# to read it differently. With the machine-wide suite lock every such rerun
# also holds up the worktrees queued behind it.
#
# Rule: the same suite/tsc command in the same directory, with the working
# tree in the same state, within 30 minutes, is blocked. Save the output the
# first time (`> "$SCRATCH/unit.log"`) and read the file. A genuine flake
# check is an explicit `RERUN=1` prefix on the command.
#
# "Tree state" is HEAD plus tracked worktree/index state and untracked path plus
# content identity outside .claude/briefs/, hashed BEFORE the run. A golden-file
# rewrite by the run itself, or any meaningful input edit, unlocks the next run.
#
# The state is keyed on the EFFECTIVE directory, not the payload's cwd:
# `cd infra && npm test` runs a different suite over a different tree than the
# same words at the repo root, and keying both to the root made them one run.
MODE=""
case "${1:-}" in --record-complete) MODE=complete ;; esac

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# Strict tier: off unless the project turned it on (lib/project.sh).
{ . "${BASH_SOURCE[0]%/*}/lib/project.sh" && pp_strict; } 2>/dev/null || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
[ -d "$CWD" ] || CWD=$PWD
# Physical path, as seg_cd resolves a `cd`: on the Mac /var is a symlink, so a
# logical cwd and the same directory reached by `cd` would key two runs.
CWD=$(cd "$CWD" && pwd -P)

# Words are split as the shell would, with Python's shlex: a quoted filename
# stays a file filter, a quoted word holding spaces is prose (a commit message may name a suite) and
# is dropped unless it holds a `$(...)` that runs, and so is every redirection
# with its target. A line whose quote is still open is split together with the
# lines that close it: split alone, a quoted string spanning lines lost its
# quotes and its prose ran as a command.
# It then prints the same segments again with every word kept, re-quoted, whitespace folded: the
# run key needs them, since `-t "one case"` picks the tests and is not the two
# words `-t one case`. Each segment then ends with \x1f and the operator after it, and
# with \x1e before that when it had a redirection (one that fails skips the command).
# A quoted or escaped ; & | < > is a word, never an operator: shlex hands both back
# alike, so such characters are swapped out before it splits and back after.
# -I: the working directory is the project's, and -c would import its own shlex.py or re.py.
chain_segments() {
  CMD=$1 python3 -I -S -c '
import os, re, shlex
HIDE = str.maketrans(";&|<>", "\ue000\ue001\ue002\ue003\ue004")
SHOW = {v: k for k, v in HIDE.items()}
def emit(toks, keep):
    seg, skip, redir = [], False, ""
    for t in toks:
        if skip:
            skip = False
            continue
        if t and set(t) <= set(";&|"):
            print(" ".join(seg) + (redir + "\x1f" + t if keep else "")); seg, redir = [], ""
            continue
        if t and set(t) <= set("<>&|"):
            skip, redir = True, "\x1e"
            continue
        t = t.translate(SHOW)
        if keep:
            # Verbatim: a filter is a regex, so its spacing selects. A newline is
            # written as an ANSI-C quoted \n (dollar-quote) so it stays off the
            # segment line and unlike a typed backslash-n. Bash quotes end the
            # python -c text, hence \x27.
            seg.append(shlex.quote(t).replace("\n", "\x27$\x27\\n\x27\x27"))
        elif "$(" in t or not any(c in " \t\n" for c in t):
            seg.append(t.replace("\n", " "))  # one line per segment, as in keep mode
    print(" ".join(seg) + (redir + "\x1f;" if keep else ""))
# The fd number of `2>x` belongs to the redirection, but shlex splits it off as
# a word of its own. Quoted and escaped text is left as it is.
FD = re.compile(r"""\\.|\x27[^\x27]*\x27|"(?:\\.|[^"\\])*"|(?<![^ \t\n;&|()])\d+(?=[<>])""")
def lex(text):
    text = FD.sub(lambda m: "" if m.group(0)[0].isdigit() else m.group(0).translate(HIDE), text)
    lex = shlex.shlex(text, posix=True, punctuation_chars=";&|<>")
    lex.whitespace_split = True
    lex.whitespace = " \t\n"  # the blanks of bash: shlex adds \r, and `pipefail\r` is a word set refuses
    return list(lex)
# Only a `#` that starts a word starts a comment; shlex ends a word at any `#`,
# which hid the commands after `a#b`. Escaped, a mid-word `#` stays a letter;
# one the command already escapes (an odd backslash run) is left as it is.
def midword_hash(m):
    run, at, text = m.group(1), m.start(), m.string
    if len(run) % 2 or (not run and (at == 0 or text[at - 1] in " \t;&|()<>")):
        return m.group(0)
    return run + "\\#"
lines = [re.sub(r"(\\*)#", midword_hash, l) for l in os.environ["CMD"].replace("\\\n", "").split("\n")]
# FAIL CLOSED on a heredoc (main ruling 2026-10-10): a body apostrophe could
# open a quote that hides the commands after the body, and parsing delimiters
# missed a form every round. Any `<<` outside a comment (a `#` that starts a
# word with no quote before it) means one line at a time, body included: a
# suite named in a body blocks, one after it is never hidden.
groups = []
COMMENT = re.compile(r"^([^\x27\x22#]*?)(?:^|(?<=[ \t]))#.*")
if any("<<" in COMMENT.sub(r"\1", l) for l in lines):
    for line in lines:
        try:
            toks = lex(line)
        except ValueError:
            toks = re.findall(r"[^ \t]+", line)
        groups.append(toks)
    lines = []  # every line is read: the joining loop below has none left
i = 0
while i < len(lines):
    for j in range(i, len(lines)):
        try:
            toks = lex("\n".join(lines[i:j + 1]))
            break
        except ValueError:
            pass
    else:
        # A quote that never closes costs only its own line.
        j, toks = i, re.findall(r"[^ \t]+", lines[i])
    groups.append(toks)
    i = j + 1
# One line per segment in both forms, so the caller splits the output in half.
for keep in ("", "1"):
    for toks in groups:
        emit(toks, keep)
'
}

# A `cd <dir>` segment moves every segment after it. Prints the directory the
# segment leaves the shell in.
# ponytail: a `(cd x && ...)` subshell is not unwound at its `)`; the directory
# carries on to later segments.
seg_cd() {
  local w target
  read -r -a w <<< "$2"
  case "${w[0]:-}" in cd|'(cd') target=${w[1]:-} ;; *) printf '%s' "$1"; return ;; esac
  case "$target" in /*) ;; *) target="$1/$target" ;; esac
  if [ -d "$target" ]; then (cd "$target" && pwd -P); else printf '%s' "$1"; fi
}

SUITE_RE='(^|[[:blank:];&|(`])(npm[[:blank:]]+(run[[:blank:]]+)?(test|typecheck)(:[a-z:-]+)?|npx[[:blank:]]+tsc|tsc[[:blank:]]|npx[[:blank:]]+vitest|vitest[[:blank:]])'

# shortcut: knows npm, tsc and vitest runs only; add the project's testCommand
# here when a project with another runner turns the strict tier on.
grep -qE "$SUITE_RE" <<< "$CMD" || exit 0

# The directory the suite runs in: the rerun state below is keyed on it, not on
# the payload's cwd.
# Match the words that run, not quoted prose: a message body naming `npm test`
# is not a suite run.
# One Python call for both forms (this hook runs on every suite call): the plain half, then the kept half.
mapfile -t ALL < <(chain_segments "$CMD")
PLAIN=("${ALL[@]:0:${#ALL[@]}/2}") KEPT=("${ALL[@]:${#ALL[@]}/2}")
printf -v SEGS '%s\n' "${PLAIN[@]}"
D=$CWD CWD0=$CWD
RUN_CWD=""
# A segment is one line, so [[ =~ ]] matches it as grep would, with no fork: this hook runs on every suite call.
while IFS= read -r SEG; do
  case $SEG in cd*|'(cd'*) D=$(seg_cd "$D" "$SEG") ;; esac
  [ -z "$RUN_CWD" ] && [[ $SEG =~ $SUITE_RE ]] && RUN_CWD=$D
done <<< "$SEGS"
CWD=${RUN_CWD:-$D}

grep -qE "$SUITE_RE" <<< "$SEGS" || exit 0

# --- same run, same tree, within 30 minutes -----------------------------------
grep -qE '(^|[[:space:];&|(])RERUN=1([[:space:]]|$)' <<< "$SEGS" && exit 0

# The key is the suite's own words, every argument kept, only when the suite
# opens the command, or follows one leading `cd <folder> &&` (or `;`) into a
# folder that is there, and no second suite is named anywhere in the text. Then pipe stages,
# redirections and what comes after it cannot change whether it ran: `npm run
# test:unit 2>&1 | tail -40`, `cd x && npm run test:unit > log` and `npm run
# test:unit && echo done` are the same run (a chained run counts). Any other
# shape (a cd with another word or an option, anything else before the suite,
# a second suite) is keyed on the whole command: whether a suite ran there
# hangs on control flow (`false && npm test`, `cd . || npm test`), and a
# missed block costs a rerun while a wrong one costs a run that never happened.
seg() { local s=${KEPT[$1]%$'\x1f'*}; printf '%s' "${s%$'\x1e'}"; }
suite() { local s=${KEPT[$1]%$'\x1f'*}; [[ ${s%$'\x1e'} =~ $SUITE_RE ]]; }
S=0
read -r -a W <<< "${PLAIN[0]:-}"
T=${W[1]:-}; case $T in /*) ;; ?*) T=$CWD0/$T ;; esac
# Only the plain form, read off the command's own text (the segments have lost quotes and redirections):
# another word, an option or a redirection can make bash refuse the cd or go elsewhere.
C=${CMD#"${CMD%%[![:space:]]*}"}
if [ "${#W[@]}" = 2 ] && [ "${W[0]}" = cd ] && [[ ${W[1]} != -* ]] && [ -d "$T" ] \
  && [[ $C == "cd ${W[1]}"* ]] && [[ ${C#"cd ${W[1]}"} =~ ^[[:space:]]*(\&\&|;) ]]; then
  S=1
fi
KEY=$CMD
# A second suite named anywhere in the text, a quoted `bash -c "..."` body included, keys on the whole command.
# Counted twice, quotes read as spaces and then with quotes and backslashes taken out as the shell does (
# `bash -c "npm run \"typecheck\""`); either count over one is a second suite.
suites() { grep -oE "$SUITE_RE" | wc -l; }
if suite "$S" && [ "$(tr "\"'" '  ' <<< "$CMD" | suites)" -le 1 ] && [ "$(tr -d "\"'\\\\" <<< "$CMD" | suites)" -le 1 ]; then
  KEY=$(seg "$S")
  for ((i = S + 1; i < ${#KEPT[@]}; i++)); do suite "$i" && { KEY=$CMD; break; }; done
fi

# The build's own papers under .claude/briefs/ (brief, evidence, round files)
# are not code: an evidence line written after a run keeps its record.
PAPERS=':(top,exclude).claude/briefs'
TREE=$( {
  git -C "$CWD" rev-parse HEAD 2>/dev/null
  printf 'WORKTREE\0'
  git -C "$CWD" diff -- "$PAPERS" 2>/dev/null
  printf 'INDEX\0'
  git -C "$CWD" diff --cached -- "$PAPERS" 2>/dev/null
  printf 'UNTRACKED\0'
  while IFS= read -r -d '' file; do
    printf '%s\0' "$file"
    git -C "$CWD" hash-object -- "$file" 2>/dev/null || printf 'missing\n'
  done < <(git -C "$CWD" ls-files --others --exclude-standard -z -- "$PAPERS" 2>/dev/null)
} | sha1sum) TREE=${TREE:0:40}
[ -n "$TREE" ] || exit 0

DIR="${COMMANDECK_SUITE_RUNS_DIR:-$HOME/.commandeck/suite-runs}"
mkdir -p "$DIR" 2>/dev/null || exit 0
STATE=$(printf '%s|%s' "$CWD" "$KEY" | sha1sum) STATE=$DIR/${STATE:0:40}
NOW=$(date +%s)

# own_status -- 0 when the command's exit status is the suite's own. The completion hook hears exit 0
# alone, and after a pipe, a `;`, an `||` or a `&` that 0 is another command's: a failing suite piped into tail was
# recorded, and its rerun refused. Only `&&` may follow the first suite, or a pipe once pipefail is surely on: a
# `set` that surely runs, one `-o pipefail`, run in this shell whatever came before (first, or after `;` or `&`).
# Any segment before the suite that could turn it off, stop the suite running (`exit`, `set -n`: exit 0 with no
# suite run) or hide what it does makes the run unsure, piped or not: one naming pipefail (PIPE_FAIL included), a
# set that may not run, or any command but a few plain builtins and a program on PATH, since a builtin, keyword,
# function or wrapper may run code in this shell (`command eval "$OFF"`, `{ ...; }`, `X=1 eval`, trap).
# Unsure is not recorded: a missed record costs a rerun, a wrong one blocks the retry of a failed suite.
# set_ok -- 0 when the segment is a `set` that surely runs and leaves the commands after it running: no redirection
# (a failed one skips the set), and its words all options bash takes, n (noexec) excepted: over one word it refuses
# (`"-a b"`, `-Z`) bash changes nothing. Sets PF to on or off when it names pipefail.
set_ok() {
  local w o= W
  PF=
  [[ ${KEPT[$1]} == *$'\x1e\x1f'* ]] && return 1
  local s=${KEPT[$1]%$'\x1f'*}
  read -r -a W <<< "${s%$'\x1e'}"
  [ "${W[0]:-}" = set ] || return 1
  for w in "${W[@]:1}"; do
    if [ -n "$o" ]; then
      [[ $w =~ ^(pipefail|errexit|nounset|xtrace|verbose)$ ]] || return 1
      [ "$w" = pipefail ] && { [ "$o" = - ] && PF=on || PF=off; }
      o=
    elif [[ $w =~ ^([-+])[abefhkmptuvxBCEHPT]*o$ ]]; then o=${BASH_REMATCH[1]}
    elif [[ ! $w =~ ^[-+][abefhkmptuvxBCEHPT]+$ ]]; then return 1; fi
  done
  [ -z "$o" ]
}
pf_on() { set_ok "$1" && [ "$PF" = on ]; }
pf_off() {
  local W
  local s=${KEPT[$1]%$'\x1f'*}; s=${s%$'\x1e'}; s=${s//_/}
  [[ ${s,,} == *pipefail* ]] && return 0
  read -r -a W <<< "${PLAIN[$1]:-}"
  case ${W[0]:-} in
    set) ! set_ok "$1" ;;
    cd|pushd|popd|echo|printf|true|:|pwd|test|\[|export) return 1 ;;
    # Assignments alone (`LOG=/tmp/v.log;`) run nothing; a value with `$(` or a backtick runs a command, so is unsure.
    *=*) [[ ! ${PLAIN[$1]} =~ ^([A-Za-z_][A-Za-z0-9_]*=([^\$\`[:space:]]|\$[{]?[A-Za-z_][A-Za-z0-9_]*[}]?)*[[:space:]]*)+$ ]] ;;
    *) [ "$(type -t -- "${W[0]:-}")" != file ] ;;
  esac
}
# head_ok -- 0 when the suite opens its own segment, after plain assignments only: `!` turns its failure into exit 0,
# and so may any other word before it (`coproc`, `time !`, a backtick that runs the suite's output).
head_ok() {
  local rest=${PLAIN[$1]:-}
  while [[ $rest =~ ^[[:blank:]]*[A-Za-z_][A-Za-z0-9_]*=([^\$\`[:space:]]|\$[{]?[A-Za-z_][A-Za-z0-9_]*[}]?)*[[:blank:]]+(.*)$ ]]; do
    rest=${BASH_REMATCH[2]}
  done
  rest=${rest#"${rest%%[![:blank:]]*}"}
  [[ $rest =~ $SUITE_RE ]] && [[ $rest == "${BASH_REMATCH[2]}"* ]]
}
own_status() {
  local i op prev=';' seen=0 pf=0
  for ((i = 0; i < ${#KEPT[@]} - 1; i++)); do
    op=${KEPT[$i]##*$'\x1f'}
    # Every suite's head, not only the first's: `npm run test:unit && ! npm run typecheck` exits 0 on a failure.
    if suite "$i"; then head_ok "$i" || return 1; seen=1; fi
    if [ "$seen" = 0 ]; then
      if pf_on "$i"; then
        case $prev/$op in ';/;'|';/&&'|';/||'|'&/;'|'&/&&'|'&/||') pf=1 ;; esac
      elif pf_off "$i"; then return 1
      fi
      prev=$op; continue
    fi
    case $op in '&&') ;; '|'|'|&') [ "$pf" = 1 ] || return 1 ;; *) return 1 ;; esac
  done
  # The last segment: nothing follows it, but a suite there still has its head checked.
  if suite "$i"; then head_ok "$i"; else [ "$seen" = 1 ]; fi
}

# --- PostToolUse: the run finished, so it counts ------------------------------
if [ "$MODE" = complete ]; then
  own_status || { rm -f "$STATE"; exit 0; }
  # An interrupted call produced no result to read, so it must not stand in
  # for one.
  if [ "$(printf '%s' "$INPUT" | jq -r '.tool_response.interrupted // false' 2>/dev/null)" = true ]; then
    rm -f "$STATE"
    exit 0
  fi
  [ -f "$STATE" ] || exit 0
  read -r THEN LAST_TREE _ < "$STATE"
  printf '%s %s complete\n' "${THEN:-$NOW}" "$LAST_TREE" > "$STATE"
  exit 0
fi

if [ -f "$STATE" ]; then
  read -r THEN LAST_TREE STATUS < "$STATE"
  AGE=$(( (NOW - ${THEN:-0}) / 60 ))
  # Only a run that FINISHED is a result you saw. A pending record is an
  # attempt another hook refused, or one that was interrupted before it
  # started, and blocking on it strands the tree until the 30 minutes lapse.
  if [ "${STATUS:-}" = complete ] && [ "$LAST_TREE" = "$TREE" ] && [ "$AGE" -lt 30 ]; then
    echo "BLOCKED: '$KEY' already ran $AGE min ago in $CWD with NO edit since -- the result is what you saw. Save the output next time (... > \"\$SCRATCH/run.log\") and read the file. Checking a flake? Prefix the command with RERUN=1. Do not ask main: if you still need that check, record it as a main-only deferred item (one line under ## Main-only (deferred) in the evidence file) and go on." >&2
    exit 2
  fi
fi
printf '%s %s pending\n' "$NOW" "$TREE" > "$STATE"
exit 0

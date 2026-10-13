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
# content identity, hashed BEFORE the run. A golden-file rewrite by the run
# itself, or any meaningful input edit, unlocks the next run.
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

# Words are split as the shell would, with the shlex split
# bash-symbols-before-read.sh uses: a quoted filename stays a file filter, a
# quoted word holding spaces is prose (a commit message may name a suite) and
# is dropped unless it holds a `$(...)` that runs, and so is every redirection
# with its target. A line whose quote is still open is split together with the
# lines that close it: split alone, a quoted string spanning lines lost its
# quotes and its prose ran as a command.
chain_segments() {
  CMD=$1 python3 -c '
import os, re, shlex
def emit(toks):
    seg, skip = [], False
    for t in toks:
        if skip:
            skip = False
        elif t and set(t) <= set(";&|"):
            print(" ".join(seg)); seg = []
        elif t and set(t) <= set("<>&"):
            skip = True
        elif "$(" in t or not any(c.isspace() for c in t):
            seg.append(t)
    print(" ".join(seg))
def lex(text):
    lex = shlex.shlex(text, posix=True, punctuation_chars=";&|<>")
    lex.whitespace_split = True
    return list(lex)
# Only a `#` that starts a word starts a comment; shlex ends a word at any `#`,
# which hid the commands after `a#b`. Escaped, a mid-word `#` stays a letter;
# one the command already escapes (an odd backslash run) is left as it is.
def midword_hash(m):
    run, at, text = m.group(1), m.start(), m.string
    if len(run) % 2 or (not run and (at == 0 or text[at - 1] in " \t;&|()<>")):
        return m.group(0)
    return run + "\\#"
lines = [re.sub(r"(\\*)#", midword_hash, l) for l in os.environ["CMD"].replace("\\\n", "").splitlines()]
# FAIL CLOSED on a heredoc (main ruling 2026-10-10): a body apostrophe could
# open a quote that hides the commands after the body, and parsing delimiters
# missed a form every round. Any `<<` outside a comment (a `#` that starts a
# word with no quote before it) means one line at a time, body included: a
# suite named in a body blocks, one after it is never hidden.
COMMENT = re.compile(r"^([^\x27\x22#]*?)(?:^|(?<=\s))#.*")
if any("<<" in COMMENT.sub(r"\1", l) for l in lines):
    for line in lines:
        try:
            toks = lex(line)
        except ValueError:
            toks = line.split()
        emit(toks)
    raise SystemExit
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
        j, toks = i, lines[i].split()
    emit(toks)
    i = j + 1
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

SUITE_RE='(^|[[:space:];&|(`])(npm[[:space:]]+(run[[:space:]]+)?(test|typecheck)(:[a-z:-]+)?|npx[[:space:]]+tsc|tsc[[:space:]]|npx[[:space:]]+vitest|vitest[[:space:]])'

# shortcut: knows npm, tsc and vitest runs only; add the project's testCommand
# here when a project with another runner turns the strict tier on.
printf '%s' "$CMD" | grep -qE "$SUITE_RE" || exit 0

# The directory the suite runs in: the rerun state below is keyed on it, not on
# the payload's cwd.
D=$CWD
RUN_CWD=""
while IFS= read -r SEG; do
  D=$(seg_cd "$D" "$SEG")
  [ -z "$RUN_CWD" ] && printf '%s' "$SEG" | grep -qE "$SUITE_RE" && RUN_CWD=$D
done <<< "$(chain_segments "$CMD")"
CWD=${RUN_CWD:-$D}
# Match the words that run, not quoted prose: a message body naming `npm test`
# is not a suite run.
SEGS=$(chain_segments "$CMD")

printf '%s' "$SEGS" | grep -qE "$SUITE_RE" || exit 0

# --- same run, same tree, within 30 minutes -----------------------------------
printf '%s' "$SEGS" | grep -qE '(^|[[:space:];&|(])RERUN=1([[:space:]]|$)' && exit 0

# The key is the command with its cd-prefix, pipes and redirections stripped:
# `npm run test:unit 2>&1 | tail -40` and `npm run test:unit | grep FAIL` are
# the same run.
KEY=$(printf '%s' "$CMD" \
  | sed -E 's/^[[:space:]]*cd [^;&|]*(&&|;)[[:space:]]*//' \
  | sed -E 's/[[:space:]]*(2>&1|[0-9]?>>?[[:space:]]*[^[:space:]|;&]+|\|.*)//g' \
  | tr -s '[:space:]' ' ' | sed -E 's/^ | $//g')

TREE=$( {
  git -C "$CWD" rev-parse HEAD 2>/dev/null
  printf 'WORKTREE\0'
  git -C "$CWD" diff 2>/dev/null
  printf 'INDEX\0'
  git -C "$CWD" diff --cached 2>/dev/null
  printf 'UNTRACKED\0'
  while IFS= read -r -d '' file; do
    printf '%s\0' "$file"
    git -C "$CWD" hash-object -- "$file" 2>/dev/null || printf 'missing\n'
  done < <(git -C "$CWD" ls-files --others --exclude-standard -z 2>/dev/null)
} | sha1sum | cut -c1-40)
[ -n "$TREE" ] || exit 0

DIR="${COMMANDECK_SUITE_RUNS_DIR:-$HOME/.commandeck/suite-runs}"
mkdir -p "$DIR" 2>/dev/null || exit 0
STATE="$DIR/$(printf '%s|%s' "$CWD" "$KEY" | sha1sum | cut -c1-40)"
NOW=$(date +%s)

# --- PostToolUse: the run finished, so it counts ------------------------------
if [ "$MODE" = complete ]; then
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
    echo "BLOCKED: '$KEY' already ran $AGE min ago in $CWD with NO edit since -- the result is what you saw. Save the output next time (... > \"\$SCRATCH/run.log\") and read the file. Checking a flake? Prefix the command with RERUN=1." >&2
    exit 2
  fi
fi
printf '%s %s pending\n' "$NOW" "$TREE" > "$STATE"
exit 0

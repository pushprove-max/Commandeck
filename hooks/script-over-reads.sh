#!/usr/bin/env bash
# PostToolUse hook (Read, Bash): when a session opens the fifth file of one
# kind from one directory, say that a script would answer the question in one
# call instead.
#
# "If code can answer, code answers" is a standing rule with nothing behind
# it. The waste it names is never one big read; it is the sixth, tenth and
# fortieth file of the same shape opened to compute one aggregate -- which
# unit has a GO, how many rows failed, which briefs carry a mutation line.
# Every one of those reads is individually reasonable, so no per-call gate can
# see the waste. Only the running count can.
#
# FAMILY = directory + extension, because that is the shape of the waste: many
# files of ONE kind in ONE place. A mixed handful of files is ordinary work and
# stays silent.
#
# Advisory, and once per family per session: it EXITS 0 and carries its advice
# as native additionalContext (staged-index-warn.sh set that shape). A non-zero
# advisory shows a Codex seat `Script failed` with no text, so the seat redoes
# the work it was being advised about. The read has already happened, so
# the demanded action is a decision about the NEXT forty, not a revert.

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# Strict tier: off unless the project turned it on (lib/project.sh).
{ . "${BASH_SOURCE[0]%/*}/lib/project.sh" && pp_strict; } 2>/dev/null || exit 0
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty'); [ -d "$CWD" ] || CWD=$PWD

# A FAILED read is not a read. PostToolUse fires either way, and counting a
# refused read inflates a family toward the threshold with files nobody saw.
IS_ERROR=$(echo "$INPUT" | jq -r 'if (.tool_response|type) == "object" then (.tool_response.is_error // false) else false end' 2>/dev/null)
[ "$IS_ERROR" = true ] && exit 0

# Key on the payload's session_id for the reason read-tracker.sh documents:
# the ${PPID} fallback differs between hook invocations, most visibly for reads
# inside a parallel tool block, which is exactly the block this hook counts.
SID=$(echo "$INPUT" | jq -r '.session_id // empty')
TALLY="/tmp/claude-read-families-${SID:-$PPID}"
WARNED="/tmp/claude-read-families-warned-${SID:-$PPID}"
THRESHOLD=${SCRIPT_OVER_READS_THRESHOLD:-5}

case "$TOOL" in
  Read)
    PATHS=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    ;;
  Bash)
    # Under bypass-permissions the harness tells the agent to read with `cat`,
    # `sed -n`, `head`, `tail`. Those are the same sweep and must count, or the
    # hook is blind in exactly the worker seats it exists for.
    CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
    PATHS=$(printf '%s\n' "$CMD" | sed -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/|/\n/g' -e 's/;/\n/g' \
      | while IFS= read -r SEG; do
          printf '%s' "$SEG" | grep -qE '^[[:space:]]*(cat|sed|head|tail|less|bat|nl)[[:space:]]' || continue
          for TOK in $SEG; do
            case "$TOK" in (-*|*=*|\'*|\"*) continue ;; esac
            P="$TOK"; [ "${P#/}" = "$P" ] && P="$CWD/$TOK"
            [ -f "$P" ] && printf '%s\n' "$P"
          done
        done)
    ;;
  *) exit 0 ;;
esac
[ -n "$PATHS" ] || exit 0

# MAIN READS A DRIVER'S --help, NOT ITS SOURCE. Main opened script source dozens
# of times a day to learn how to call it, and every read stays in its context. A
# read of a scripts/*.sh that answers --help carries a hint, as advice: refusing
# it cost a turn and redirected nothing (owner ruling 2026-10-01; restored
# 2026-10-15 after it was lost with symbols-before-read.sh). Workers are exempt.
HINT=
if [ "$(git -C "$CWD" rev-parse --git-dir 2>/dev/null)" = "$(git -C "$CWD" rev-parse --git-common-dir 2>/dev/null)" ]; then
  while IFS= read -r P; do
    case $P in */scripts/__tests__/*) continue ;; */scripts/*.sh) ;; *) continue ;; esac
    grep -qF -- '--help|-h)' "$P" 2>/dev/null || continue
    HINT="Hint: 'bash $P --help' prints its flags and an example; read the source only to debug it."; break
  done <<<"$PATHS"
fi

FAMS=""
while IFS= read -r P; do
  [ -n "$P" ] || continue
  BASE=${P##*/}
  case "$BASE" in *.*) EXT=".${BASE##*.}" ;; *) EXT="" ;; esac
  DIR=${P%/*}
  printf '%s|%s\t%s\n' "$DIR" "$EXT" "$P" >> "$TALLY"
  FAMS="$FAMS$DIR|$EXT
"
done <<EOF
$PATHS
EOF

# Check every family THIS call touched, not just the last one: a parallel block
# can read five files of one kind in a single tool result.
while IFS= read -r FAM; do
  [ -n "$FAM" ] || continue
  grep -qxF "$FAM" "$WARNED" 2>/dev/null && continue
  N=$(awk -F'\t' -v f="$FAM" '$1 == f { print $2 }' "$TALLY" | sort -u | wc -l)
  [ "$N" -ge "$THRESHOLD" ] || continue
  printf '%s\n' "$FAM" >> "$WARNED"
  DIR=${FAM%|*}; EXT=${FAM##*|}
  # A function, not $(cat <<EOF): Bash 3.2 misreads the quotes of a here-document inside $(...).
  advice() { cat <<EOF
READ SWEEP: $N files of one kind opened this session.

  family: ${DIR}/*${EXT}
  read:   $N files

If this is ONE question over many files -- which ones say X, how many failed,
what is the spread -- then a script answers it in one call and puts nothing
but the answer in context. The next file costs its whole contents; a script
over all of them costs the answer.

  rg -c <pattern> ${DIR}          node -e '<compute>'          python3 -c '<compute>'

Raw output goes to a file under the scratchpad; only the answer comes back.
If you genuinely need each file's own content in context, say so and carry on.
EOF
}
  ADVICE=$(advice)${HINT:+$'\n\n'$HINT}
  HOOK_FIRE_ADVISE=1
  printf '%s\n' "$ADVICE" >&2
  jq -cn --arg message "$ADVICE" '{
    systemMessage:$message,
    hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$message}
  }' 2>/dev/null || true
  exit 0
done <<EOF
$(printf '%s' "$FAMS" | sort -u)
EOF

[ -z "$HINT" ] || { HOOK_FIRE_ADVISE=1; jq -cn --arg m "$HINT" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'; }
exit 0

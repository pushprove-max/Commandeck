#!/usr/bin/env bash
# Sourced by duplicate-agent-guard.sh, git-safety.sh and the
# heap-cap check in bash-guardrails.sh: strip_quoted <command>
# prints the command with its data removed, so a hook reads only what bash runs.
#
# Quoted spans, comments and heredoc bodies are data (a brief that names a
# script, a grep for one, an issue body). One pass over the whole text; the
# old pair of seds worked line by line, so a multi-line issue body in double
# quotes was never stripped and a script name in its prose read as a command.
# What is NOT data: a `$(...)` inside double quotes runs, so the text inside
# it is read as commands again (nesting-aware), and a comment or heredoc ends
# where bash ends it, so an apostrophe in either cannot swallow the command
# that follows on the next line. A backtick inside double quotes runs too: the
# mark itself is printed, so a caller can tell the string was not all data.
# `<<` inside `$((...))`, `((...))` or `$[...]` is a shift and opens no heredoc:
# read as one, it hid every line after it up to a line holding the number.
# Not told apart: a shift in an array subscript or a `${x:1<<2}` offset.
#
# strip_quoted <command> <mark> keeps each quoted span as the WORD it is, for a
# caller that reads a call's arguments by position (git-safety.sh): removing
# `"/repo"` from `git -C "/repo" clean -fdx` hands `clean` to -C as its value.
# Every non-empty span prints the mark, so the caller can still tell quoted
# data from typed text. A span that is one plain token follows its mark as
# written, because that is the argument bash passes; a span holding a space or
# an operator is prose and prints the mark alone, so it still cannot read as a
# command. An empty span prints nothing. Without a mark the output is what it
# always was.
_strip_keep_span() { # uses strip_quoted's MARK, SPAN and OUT
  if [ -n "$MARK" ] && [ -n "$SPAN" ]; then
    OUT+=$MARK
    case "$SPAN" in *[[:space:]\;\&\|\(\)\<\>]*) ;; *) OUT+=$SPAN ;; esac
  fi
  SPAN=""
}
# strip_quoted <command> <mark> ends also prints, on stderr, each here-document
# operator whose end word is not one plain word, bare, in one pair of quotes or
# after one backslash (bash-guardrails.sh refuses those for every hook).
_STRIP_PLAIN_W='[A-Za-z0-9_][A-Za-z0-9_.-]*'
_STRIP_PLAIN_END="^<<-?[[:blank:]]*('$_STRIP_PLAIN_W'|\"$_STRIP_PLAIN_W\"|\\\\?$_STRIP_PLAIN_W)([[:space:];|&<>()]|\$)"
_strip_arith_end() { # <index of the first `(` of a `((`>: sets strip_quoted's AEND when the pair is closed by `))`
  local K N=0
  for ((K=$1; K<${#TEXT}; K++)); do
    case "${TEXT:K:1}" in '(') N=$((N+1)) ;; ')') N=$((N-1)); [ "$N" -gt 0 ] || { [ "${TEXT:K-1:1}" != ')' ] || AEND=$K; break; } ;; esac
  done
}
strip_quoted() {
  local TEXT=$1 MARK=${2-} SPAN="" OUT="" MODE=code CHAR NEXT PREV="" I DEPTH=0 TAG="" DASH="" LINE="" AEND=0 K
  local -a STACK=()
  for ((I=0; I<${#TEXT}; I++)); do
    CHAR=${TEXT:I:1}; NEXT=${TEXT:I+1:1}
    case "$MODE" in
      sq) if [ "$CHAR" = "'" ]; then MODE=code; _strip_keep_span; else SPAN+=$CHAR; fi ;;
      dq)
        if [ "$CHAR" = '\' ]; then SPAN+=$NEXT; I=$((I+1))
        elif [ "$CHAR" = '"' ]; then MODE=code; _strip_keep_span
        elif [ "$CHAR" = '$' ] && [ "$NEXT" = '(' ]; then
          # `$((` runs inside double quotes as well; code mode never sees its first bracket, so its span is found here.
          [ "${TEXT:I+2:1}" != '(' ] || [ "$I" -lt "$AEND" ] || _strip_arith_end "$((I+1))"
          _strip_keep_span; STACK+=("$DEPTH"); DEPTH=0; MODE=code; OUT+='$('; I=$((I+1))
        elif [ "$CHAR" = '`' ]; then _strip_keep_span; OUT+=$CHAR
        else SPAN+=$CHAR
        fi ;;
      comment) [ "$CHAR" = $'\n' ] && { MODE=code; OUT+=$CHAR; } ;;
      heredoc)
        if [ "$CHAR" = $'\n' ]; then
          # Where bash ends it: the end word alone, after tabs only under `<<-`.
          # An indented look-alike is body, or the prose after it reads as code.
          { [ "$LINE" = "$TAG" ] || { [ -n "$DASH" ] && [ "${LINE#"${LINE%%[!	]*}"}" = "$TAG" ]; }; } && { MODE=code; TAG=""; OUT+=$CHAR; }
          LINE=""
        else LINE+=$CHAR; fi ;;
      code)
        # Where an arithmetic span ends: `((` after `$` or where a command may start, closed by `))`; `$[` by `]`.
        if [ "$I" -ge "$AEND" ] && [ "$CHAR$NEXT" = '((' ]; then
          case "$PREV" in '$'|''|' '|$'\t'|$'\n'|';'|'&'|'|') _strip_arith_end "$I" ;; esac
        elif [ "$I" -ge "$AEND" ] && [ "$PREV$CHAR" = '$[' ]; then
          K=${TEXT:I}; K=${K%%]*}; AEND=$((I + ${#K}))
        fi
        case "$CHAR" in
          '\') I=$((I+1)) ;;
          "'") MODE=sq ;;
          '"') MODE=dq ;;
          '#') case "$PREV" in ''|' '|$'\t'|$'\n'|';'|'&'|'|'|'(') MODE=comment ;; *) OUT+=$CHAR ;; esac ;;
          # `<<<` is a here-string: its word is on this line and no body follows.
          '<') if [ "$NEXT" = '<' ] && [ "${TEXT:I+2:1}" = '<' ]; then OUT+='<<<'; I=$((I+2))
               elif [ "$NEXT" = '<' ] && [ "$I" -lt "$AEND" ]; then OUT+='<<'; I=$((I+1))
               elif [ "$NEXT" = '<' ]; then
                 local J=$((I+2)) T=${TEXT:I:26} D=""
                 [ -z "${3-}" ] || [[ ${TEXT:I:80} =~ $_STRIP_PLAIN_END ]] || printf '%s\n' "${T%%$'\n'*}" >&2
                 T=""
                 [ "${TEXT:J:1}" = '-' ] && { J=$((J+1)); D=1; }
                 while [ "${TEXT:J:1}" = ' ' ]; do J=$((J+1)); done
                 # An end word is plain here: bash-guardrails.sh refuses every other one.
                 while :; do
                   local C=${TEXT:J:1}
                   case "$C" in ''|' '|$'\t'|$'\n'|';'|'&'|'|'|'('|')'|'<'|'>') break ;; "'"|'"'|'\') ;; *) T+=$C ;; esac
                   J=$((J+1))
                 done
                 [ -n "$T" ] && { TAG=$T; DASH=$D; }
                 OUT+='<<'; I=$((I+1))
               else OUT+=$CHAR; fi ;;
          $'\n') OUT+=$CHAR; if [ -n "$TAG" ]; then MODE=heredoc; LINE=""; fi ;;
          '(') DEPTH=$((DEPTH+1)); OUT+=$CHAR ;;
          ')') if [ "$DEPTH" -gt 0 ]; then DEPTH=$((DEPTH-1)); OUT+=$CHAR
               elif [ "${#STACK[@]}" -gt 0 ]; then DEPTH=${STACK[-1]}; unset 'STACK[-1]'; OUT+=$CHAR; MODE=dq
               else OUT+=$CHAR; fi ;;
          *) OUT+=$CHAR ;;
        esac ;;
    esac
    PREV=$CHAR
  done
  printf '%s' "$OUT"
}
# strip_odd_end <command>: prints the first here-document operator whose end
# word is not plain, or nothing. The reader cannot follow `$'...'` (a `\'` does
# not end it), so with one in the command every `<<` in the text is judged as
# written. A shift inside `$(( ))` made of plain arithmetic only is taken out
# first; nothing in it can spell an odd end word.
strip_odd_end() {
  local ODD=""
  case "$1" in
    *"\$'"*'<<'*|*'<<'*"\$'"*)
      ODD=$(sed -E "s/<<<//g; s/<<-?[[:blank:]]*('$_STRIP_PLAIN_W'|\"$_STRIP_PLAIN_W\"|\\\\?$_STRIP_PLAIN_W)([[:space:];|&<>()]|\$)/\2/g" <<<"$1" | grep -oE '<<.{0,24}' | head -1) ;;
  esac
  # A second case, not `;;&` above: Bash 3.2 cannot parse that.
  case "$1" in
    *'<<'*)
      [ -n "$ODD" ] || ODD=$(strip_quoted "$(sed -E 's/\$\(\([A-Za-z0-9_ +*\/%()<>-]*\)\)//g' <<<"$1")" "" ends 2>&1 >/dev/null | head -1) ;;
  esac
  printf '%s' "$ODD"
}

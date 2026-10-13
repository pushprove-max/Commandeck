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
# that follows on the next line.
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
strip_quoted() {
  local TEXT=$1 MARK=${2-} SPAN="" OUT="" MODE=code CHAR NEXT PREV="" I DEPTH=0 TAG="" LINE=""
  local -a STACK=()
  for ((I=0; I<${#TEXT}; I++)); do
    CHAR=${TEXT:I:1}; NEXT=${TEXT:I+1:1}
    case "$MODE" in
      sq) if [ "$CHAR" = "'" ]; then MODE=code; _strip_keep_span; else SPAN+=$CHAR; fi ;;
      dq)
        if [ "$CHAR" = '\' ]; then SPAN+=$NEXT; I=$((I+1))
        elif [ "$CHAR" = '"' ]; then MODE=code; _strip_keep_span
        elif [ "$CHAR" = '$' ] && [ "$NEXT" = '(' ]; then _strip_keep_span; STACK+=("$DEPTH"); DEPTH=0; MODE=code; OUT+='$('; I=$((I+1))
        else SPAN+=$CHAR
        fi ;;
      comment) [ "$CHAR" = $'\n' ] && { MODE=code; OUT+=$CHAR; } ;;
      heredoc)
        if [ "$CHAR" = $'\n' ]; then
          [ "${LINE#"${LINE%%[! 	]*}"}" = "$TAG" ] && { MODE=code; TAG=""; OUT+=$CHAR; }
          LINE=""
        else LINE+=$CHAR; fi ;;
      code)
        case "$CHAR" in
          '\') I=$((I+1)) ;;
          "'") MODE=sq ;;
          '"') MODE=dq ;;
          '#') case "$PREV" in ''|' '|$'\t'|$'\n'|';'|'&'|'|'|'(') MODE=comment ;; *) OUT+=$CHAR ;; esac ;;
          # `<<<` is a here-string: its word is on this line and no body follows.
          '<') if [ "$NEXT" = '<' ] && [ "${TEXT:I+2:1}" = '<' ]; then OUT+='<<<'; I=$((I+2))
               elif [ "$NEXT" = '<' ]; then
                 local J=$((I+2)) T=""
                 [ "${TEXT:J:1}" = '-' ] && J=$((J+1))
                 while [ "${TEXT:J:1}" = ' ' ]; do J=$((J+1)); done
                 while :; do
                   local C=${TEXT:J:1}
                   case "$C" in ''|' '|$'\t'|$'\n'|';'|'&'|'|'|'('|')'|'<'|'>') break ;; "'"|'"'|'\') ;; *) T+=$C ;; esac
                   J=$((J+1))
                 done
                 [ -n "$T" ] && TAG=$T
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

#!/usr/bin/env bash
# PreToolUse hook (Bash), main's session only: every Bash call runs in the background unless each command in it is a
# quick read or a quick tool on the list below. Unknown means slow: a new script or binary has to be added here before
# main may run it in the foreground. Strict tier only; a linked worktree or a pane Orca does not name as main's
# coordinator is never touched.
# Retire when: Claude Code backgrounds slow main calls
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
[ "$(jq -r '.tool_input.run_in_background // false' <<<"$INPUT")" = true ] && exit 0
CMD=$(jq -r '.tool_input.command // empty' <<<"$INPUT")
[ -z "$CMD" ] && exit 0
# Without the helper quoted prose would read as commands and block everything; fail open.
. "${BASH_SOURCE[0]%/*}/lib/strip-quoted.sh" 2>/dev/null || exit 0
S=$(strip_quoted "$CMD" 2>/dev/null) || exit 0

QUICK=" cd pwd echo printf cat head tail sed grep egrep rg ls wc jq git cp mv mkdir touch rm ln date test [ [[ true
  false kill pgrep fd . source sort uniq cut tr awk find stat basename dirname readlink realpath ps diff comm column
  paste nl tee export local set unset read shift return exit which command type shasum od base64 file printenv id
  whoami hostname uname df "
# Scripts by file name, each measured at a few seconds in main's calls.
QUICK_SCRIPTS=" decision.sh read-verdict.sh long-job.sh checkpoint-context.py orca-wait.sh board.sh
  answer-worker.sh state-snapshot.sh peek.sh "

slow=""
set -f
# One space between words, so a name at a line end matches `*" name "*` too.
# shellcheck disable=SC2086
QUICK=" $(echo $QUICK) " QUICK_SCRIPTS=" $(echo $QUICK_SCRIPTS) "
while IFS= read -r seg; do
  # shellcheck disable=SC2086
  set -- $seg
  while [ $# -gt 0 ]; do
    case "$1" in
      for|case|select) set -- ; break ;;   # `for x in a b` and `case x in` list words, not commands
      while|until|if|elif|then|else|do|done|fi|esac|in|'!'|time|'$'|'{'|'}'|nice|command|builtin|exec) shift ;;
      # `-C`/`-u` given last has no value: `shift 2` would fail and shift nothing, looping forever. No command.
      env) shift; while [ $# -gt 0 ]; do case "$1" in -C|-u) [ $# -ge 2 ] || { set --; break; }; shift 2 ;; -*) shift ;; *) break ;; esac; done ;;
      [A-Za-z_]*=*) shift ;;
      [0-9]*'>'*|'>'*|'<'*|2'>'*) shift ;;
      *) break ;;
    esac
  done
  [ $# -eq 0 ] && continue
  w=${1##*/}
  case "$w" in
    bash|sh|zsh)
      [ $# -ge 2 ] || { slow=$w; break; }
      [ "$2" = -n ] && continue
      s=${2##*/}
      [ "$s" = seat.sh ] && [ "${3:-}" = status ] && continue
      case "$QUICK_SCRIPTS" in *" $s "*) ;; *) slow="$1 $2"; break ;; esac
      [ "$s" = long-job.sh ] && [ "${3:-}" = wait ] && { slow="long-job.sh wait"; break; } ;;
    python3|python)
      case " $* " in *" -c "*|*" - "*|*checkpoint-context.py*) ;; *) slow="$*"; break ;; esac ;;
    gh) case " $* " in *" watch "*) slow="gh … watch"; break ;; esac ;;
    orca-ide|orca) case " $* " in *" wait "*) slow="orca-ide … wait"; break ;; esac ;;
    *) case "$QUICK" in *" $w "*) ;; *) slow=$w; break ;; esac ;;
  esac
done < <(sed -E -e 's/[0-9]*>&[0-9-]+|&>>?/ /g' -e 's/(\&\&|\|\||[;&|()`])/\n/g' <<<"$S")

[ -z "$slow" ] && exit 0
# Main's own checkout (a linked worktree is a worker), a coordinator Orca names as this pane, and the strict tier.
[ "$(git rev-parse --git-dir 2>/dev/null)" = "$(git rev-parse --git-common-dir 2>/dev/null)" ] || exit 0
. "${BASH_SOURCE[0]%/*}/lib/project.sh" 2>/dev/null || exit 0
pp_is_main_pane || exit 0
pp_strict || exit 0
# When two hooks both return updatedInput only the last to finish counts, so this hook rewrites only a call that
# bash-guardrails.sh, run on the same input, leaves alone. No copied list of its rewrites: it answers for itself.
# Its own fire-log line is silenced so the call is logged once. Any failure to ask keeps a note.
G="${BASH_SOURCE[0]%/*}/bash-guardrails.sh"
GOUT="" grc=126
if [ -r "$G" ]; then
  GOUT=$(COMMANDECK_HOOK_FIRE_LOG=/dev/null bash "$G" <<<"$INPUT" 2>/dev/null); grc=$?
fi
case $grc in
  0) jq -e '.hookSpecificOutput.updatedInput' >/dev/null 2>&1 <<<"$GOUT" && exit 0
     jq -cn --arg r "main runs shell commands in the background and '$slow' is not on the quick list, so this call was rewritten to run_in_background: true" \
       --argjson ti "$(jq -c '.tool_input' <<<"$INPUT")" \
       '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecisionReason: $r, updatedInput: ($ti + {run_in_background: true})}}'
     exit 0 ;;
  2) exit 0 ;;   # bash-guardrails refuses the call and names the fix
esac
# The call cannot be vetted against bash-guardrails.sh: a note, never a block.
HOOK_FIRE_ADVISE=1
jq -cn --arg c "main runs shell commands in the background; only quick reads and quick tools run in the foreground. '$slow' is not on the quick list. Run the same call again with run_in_background: true; its exit wakes you. The list lives in hooks/main-background-only.sh." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $c}}'
exit 0

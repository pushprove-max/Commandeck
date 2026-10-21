#!/usr/bin/env bash
# SessionStart hook (main only): a main restarted by context-clear-stop.sh
# starts with its run binding, board.sh output and checkpoint text in context,
# ONCE. Fetching them by hand cost each resumed main about six turns,
# and typed into the resume prompt they fail past ~9 KB.
#
# The marker is context-clear-stop.sh's and names the checkpoint. One session
# takes it by renaming it, so a second main never replays an old checkpoint.
# Seat rule as in context-clear-stop.sh: reviewers and linked worktrees
# (workers) are not main and never see its state.
#
# The whole block stays under 10240 bytes, past which the harness shows only a
# 2 KB preview. Budget order: persona, RESUMED line and binding, the checkpoint
# (whole, or its Goal, Live units, Waiting on and Resume sections), board.sh,
# then the owner's last prompts verbatim (checkpoint-context.py messages). A part that
# does not fit becomes one pointer line, named in the RESUMED line. The checkpoint this
# session resumed from is recorded in <session id>.resumed-from, so that
# context-clear-stop.sh can refuse a next checkpoint that drops its open work
#. Nothing else names it once the marker is consumed.
set -u
input=$(cat 2>/dev/null || true)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$input"
[ "${COMMANDECK_REVIEWER:-}" = 1 ] && exit 0
[ "$(git rev-parse --git-dir 2>/dev/null)" = "$(git rev-parse --git-common-dir 2>/dev/null)" ] || exit 0
# Named for this checkout by context-clear-stop.sh; another project's marker is not ours.
MARK=$HOME/.claude/checkpoints/resume-pending.$(printf '%s' "$(git rev-parse --show-toplevel 2>/dev/null)" | tr -c 'A-Za-z0-9' '-')
TAKEN=$MARK.$$
# The marker's second line is the token context-clear-stop.sh started the
# replacement with; a main session that does not carry it is not the
# replacement and leaves the checkpoint for the one that is. A marker with no
# token (written by hand) is anyone's, as before.
token=$(sed -n 2p "$MARK" 2>/dev/null)
[ -z "$token" ] || [ "$token" = "${COMMANDECK_RESUME_TOKEN:-}" ] || exit 0
mv "$MARK" "$TAKEN" 2>/dev/null || exit 0
cp=$(head -1 "$TAKEN"); age=$(( $(date +%s) - $(stat -c %Y "$TAKEN") ))
# Same 30-minute window context-clear-stop.sh calls a checkpoint fresh.
[ "$age" -lt 1800 ] && [ -f "$cp" ] || { rm -f "$TAKEN"; exit 0; }
HERE=$(cd "$(dirname "$0")" && pwd)
# Main's persona leads every resume block, setup failures included;
# its one home is the first line of main-session.md.
head -1 "$HERE/../templates/main-session.md" 2>/dev/null

# Ancestry is written before the binding branches below, either of which can
# drop the claimed marker. Without it the restart gate has no baseline, so a
# session that cannot record it gives the marker back and says so.
setup_failed() {
  HOOK_FIRE_ADVISE=1
  mv -n "$TAKEN" "$MARK" 2>/dev/null; rm -f "$TAKEN"
  echo "# RESUME SETUP FAILED: $1. Nothing was injected and the resume marker for $cp was kept: read that checkpoint by hand; the next session start of this replacement main in the next 30 minutes retries."
  exit 0
}
sid=$(jq -r '.session_id // empty' 2>/dev/null <<<"$input")
transcript=$(jq -r '.transcript_path // empty' 2>/dev/null <<<"$input")
[[ $sid =~ ^[A-Za-z0-9_-]+$ ]] || setup_failed "SessionStart gave no usable session id, so nothing can record which checkpoint this session resumed from"
ANC=$HOME/.claude/checkpoints/$sid.resumed-from
if [ -e "$ANC" ]; then
  [ "$(head -1 "$ANC")" = "$cp" ] || setup_failed "this session already resumed from $(head -1 "$ANC") and does not swap it for $cp"
else
  { printf '%s\n' "$cp" > "$ANC.$$" && mv "$ANC.$$" "$ANC"; } 2>/dev/null || { rm -f "$ANC.$$"; setup_failed "could not record ancestry at $ANC"; }
fi

# --full: this block streams the board under its own timeout and cap (a cut board prints nothing until it ends).
BOARD_CMD=${COMMANDECK_BOARD_CMD:-bash $(printf '%q' "$HERE")/../scripts/board.sh --full}
RUN_FILE=$(. "$HERE/lib/project.sh" && pp_run_file)
RUN=$( { tr -d '[:space:]' < "$RUN_FILE"; } 2>/dev/null || true)
capped() { # max-bytes source -- stdin, cut at the cap with a pointer to the rest
  local s; s=$(cat)
  printf '%s\n' "${s:0:$1}"
  [ "${#s}" -le "$1" ] || echo "[cut at $1 of ${#s} bytes; read the rest from $2]"
}

# ONLY A BINDING ORCA CONFIRMED CONSUMES THE MARKER, judged by `.ok` as
# run-bound.sh does. A refused or timed-out run-use puts the marker back (mv
# keeps its mtime, so the 30-minute window still ends the retries; -n lets a
# newer restart's marker win) and main is told to bind by hand.
BOUND=0 BIND_OUT="no run recorded for this project in ${RUN_FILE:-its scratch folder}"
if [ -n "$RUN" ]; then
  BIND_OUT=$(timeout 20 orca-ide orchestration run-use --id "$RUN" --json 2>&1); rc=$?
  [ "$rc" = 0 ] && jq -e '.ok' >/dev/null 2>&1 <<<"$BIND_OUT" && BOUND=1
  [ "$rc" = 124 ] && BIND_OUT="timed out after 20 s"
fi
if [ "$BOUND" = 1 ]; then
  rm -f "$TAKEN"
  bind="## run binding: orca-ide orchestration run-use --id $RUN: bound"
else
  mv -n "$TAKEN" "$MARK" 2>/dev/null; rm -f "$TAKEN"
  err=$(jq -r '.error.message // .error.code // empty' 2>/dev/null <<<"$BIND_OUT")
  err=$(printf '%s' "${err:-$BIND_OUT}" | tr '\n' ' ')
  HOOK_FIRE_ADVISE=1
  bind="NOT BOUND: run-use --id ${RUN:-<none>} failed: ${err:0:300}
Run \`orca-ide orchestration run-use --id ${RUN:-<run_id>}\` yourself before any reply, task-create or dispatch. The resume marker was kept, so the next session start of this replacement main in the next 30 minutes retries this block."
fi
resumed() { # parts cut to fit ("" for none) -> the RESUMED line
  local cut=${1:+parts were cut to fit 10 KB: $1; read each of their pointer lines below once (allowed), and fetch nothing else again.}
  if [ "$BOUND" = 1 ]; then
    echo "# RESUMED MAIN: the run binding, board.sh and the checkpoint below were fetched at session start; ${cut:-do not fetch them again.} Arm nothing (main-watch.sh wakes main); first call: the first real action."
  else
    echo "# RESUMED MAIN: board.sh and the checkpoint are below, but the run binding FAILED.${cut:+ $cut}"
  fi
}
# Both binding outcomes; checkpoint.md's Resume section carries the same line.
TODO_RULE='TODO LIST: recreate only the unfinished items, `[ ]` next and `[>]` in progress (status in_progress), every TaskCreate in ONE reply; `[x]` items stay done in this checkpoint and are not recreated. Later updates ride in the same reply as the work they record.'
# The old session's transcript sits beside the new one, named by its id; with
# no transcript_path, the project folder comes from paths.sh, never a newest-file guess.
if [ -n "$transcript" ]; then tdir=$(dirname "$transcript")
elif . "$HERE/../scripts/paths.sh" 2>/dev/null; then tdir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$PP_MAIN_SLUG
else tdir=""; fi
tpath=${tdir:+$tdir/$(basename "$cp" .md).jsonl}

# Each part is measured in bytes as printed, and room for every later part's
# pointer line is held back before a part is let in whole.
bytes() { printf '%s\n' "$1" | LC_ALL=C wc -c | tr -d ' '; }
KEPT='Goal, Live units, Waiting on and Resume'
KEEP_RE='^## (Goal|Live units|Waiting on|Resume)'
# shellcheck disable=SC2086  # the command is a word list
board="## board.sh
$(timeout "${COMMANDECK_BOARD_TIMEOUT:-30}" $BOARD_CMD 2>&1 | capped 4000 "board.sh"
  [ "${PIPESTATUS[0]}" != 124 ] || echo "[board.sh timed out after ${COMMANDECK_BOARD_TIMEOUT:-30} s: the lines above are a partial board; run \`$BOARD_CMD\` for the whole one]")"
board_ptr="## board.sh: left out to fit the resume budget; run \`$BOARD_CMD\` for it"
prompts_ptr=$(( 200 + $(bytes "$tpath") ))  # checkpoint-context.py's pointer line when no prompt fits
ckpt="## checkpoint $cp
$(cat "$cp")"
cut=""
left=$(( 10239 - $(head -1 "$HERE/../templates/main-session.md" 2>/dev/null | wc -c) - $(bytes "$(resumed "the checkpoint past $KEPT; board.sh; the owner's prompts")") - $(bytes "$bind") - $(bytes "$TODO_RULE") ))
room=$(( left - $(bytes "$board_ptr") - prompts_ptr ))
if [ "$(bytes "$ckpt")" -gt "$room" ]; then
  cut="the checkpoint past $KEPT"
  rest=$(grep '^## ' "$cp" | grep -vE "$KEEP_RE" | cut -c4- | paste -sd ';' - | sed 's/;/; /g')
  ckpt="## checkpoint $cp
$(awk -v keep="$KEEP_RE" '/^## /{s=1; on=($0 ~ keep)} !s||on' "$cp")
[checkpoint cut to fit: only $KEPT are shown; Read $cp for: ${rest:-the rest}]"
  # Those four sections alone can still overflow: cut at a byte count, whole characters only.
  # The pointer names $cp, so its size is measured, never assumed; the 1 is the newline before it.
  ckpt_ptr="[checkpoint cut to fit; Read $cp for the rest]"
  [ "$(bytes "$ckpt")" -le "$room" ] || ckpt="$(printf '%s' "$ckpt" | LC_ALL=C head -c $(( room - $(bytes "$ckpt_ptr") - 1 )) | iconv -c -f UTF-8 -t UTF-8)
$ckpt_ptr"
fi
left=$(( left - $(bytes "$ckpt") ))
if [ "$(bytes "$board")" -gt $(( left - prompts_ptr )) ]; then
  board=$board_ptr; cut="${cut:+$cut; }board.sh"
fi
left=$(( left - $(bytes "$board") ))
prompts=$(python3 "$HERE/../scripts/checkpoint-context.py" messages "$tpath" "$left") \
  || { prompts="WARNING: The owner's prompts could not be extracted (checkpoint-context.py exit $?)"; HOOK_FIRE_ADVISE=1; }
grep -qF 'the resume budget' <<<"$prompts" && cut="${cut:+$cut; }the owner's prompts"

resumed "$cut"
printf '%s\n' "$bind" "$board" "$ckpt" "$TODO_RULE" "$prompts"

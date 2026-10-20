#!/usr/bin/env bash
# PreToolUse hook (Edit|Write|MultiEdit): block a Write, and warn on an Edit,
# that takes a .ts file past 500 lines or a .tsx file past 400 -- the two caps this hook states.
#
# ONLY THOSE TWO CAPS. There used to be a universal 800-line block for every
# file type. No rule states it, so a 900-line markdown reference or a generated
# fixture was refused on a number nobody chose, while a .tsx sailed past its
# stated 400 with a warning nothing enforced. The stated caps are enforced and
# the invented one is gone.
#
# WHY IT SEES EDITS NOW. It was registered on `Write` alone until 2026-08-31 and
# read only tool_input.content, so it could only judge a file written whole --
# which is not how a file gets long. Files grow by Edit and MultiEdit, one hunk
# at a time, and every one of those passed unmeasured.
#
# HOW AN EDIT IS MEASURED. A Write states the whole file, so its line count is
# exact. An Edit does not, so the count is the file ON DISK plus, per edit, the
# lines the new text adds over the old text it replaces. That is exact for the
# ordinary edit and needs no guessing.
#
# WHERE IT DECLINES TO GUESS, deliberately, rather than shipping a check that
# lies: a `replace_all` edit applies its swap an unknown number of times, and a
# file not yet on disk has no baseline. In either case the payload is not
# measurable and the hook exits silently. A wrong number here would be worse
# than no number: it would either block a legitimate write or, reported as
# fact, be believed.
# THE PAYLOAD SHAPE COMES FROM THE SHARED EXTRACTOR. This hook used to
# keep its own jq over `.tool_input.edits`, a second definition of how the three
# tools spell a change, beside the one in lib/edit-payload.sh. A second
# definition is how eleven guards went blind to MultiEdit for a month: the July
# fold reached some hooks and not their siblings. The shape it needs -- whether
# a whole file was stated, and each edit's net line count -- now lives in the
# helper as hook_edit_size, so the next tool shape is added there once.
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# Strict tier: off unless the project turned it on (lib/project.sh).
{ . "${BASH_SOURCE[0]%/*}/lib/project.sh" && pp_strict; } 2>/dev/null || exit 0
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/edit-payload.sh
. "$HERE/lib/edit-payload.sh" 2>/dev/null
hook_payload_loaded 2>/dev/null || {
  echo "BLOCKED: hooks/lib/edit-payload.sh did not load, so the file-size cap screened nothing. Reinstall the plugin (\`claude plugin install commandeck@commandeck\`) and retry." >&2
  exit 2
}

# AN EDIT IS JUDGED ON CROSSING THE LINE, NOT ON STANDING BEYOND IT. A Write
# states a whole file, so its baseline is zero and any oversized result is the
# writer's doing. An edit to a file that is ALREADY too long is usually the
# repair, and warning on every one of those -- or worse, blocking them -- turns
# a long file into a file nobody can shorten. So a threshold fires only when
# this change takes the file across it.
#
# One record per PATH, so a MultiEdit that touches two files is judged per file
# rather than summed against the payload-level path.
while IFS=$'\t' read -r P64 KIND N; do
  [ -n "${P64:-}" ] && [ -n "${KIND:-}" ] || continue
  FILE_PATH=$(printf '%s' "$P64" | base64 -d 2>/dev/null) || continue
  case "$FILE_PATH" in
    *.tsx) CAP=400 ;;
    *.ts)  CAP=500 ;;
    *) continue ;;
  esac
  if [ "$KIND" = write ]; then
    BASELINE=0; LINE_COUNT=$N; VERB="Write to"
  else
    # An edit describes a change to a file it cannot see, so the count is the
    # file ON DISK plus what this call adds. A file not yet on disk has no
    # baseline, and this hook does not guess.
    [ -f "$FILE_PATH" ] || continue
    BASELINE=$(wc -l < "$FILE_PATH" | tr -d ' ')
    LINE_COUNT=$((BASELINE + N)); VERB="Edit to"
  fi
  if [ "$LINE_COUNT" -gt "$CAP" ] && [ "$BASELINE" -le "$CAP" ]; then
    # A feature that grows an existing file past its cap goes ahead; the
    # shrink is its own follow-up unit, not a refactor folded into the feature.
    if [ "$KIND" != write ]; then
      HOOK_FIRE_ADVISE=1
      echo "OVER CAP: $VERB $FILE_PATH leaves a ${LINE_COUNT}-line file; the cap is ${CAP}. Allowed in a feature unit: do NOT fold it here; list it under 'Over cap' in the evidence and main files the shrink as a follow-up unit." >&2
      continue
    fi
    echo "BLOCKED: $VERB $FILE_PATH would leave a ${LINE_COUNT}-line file; the cap is ${CAP}. Split it, or move what you are adding to the file it belongs in." >&2
    exit 2
  fi
done <<< "$(hook_edit_size "$INPUT")"

exit 0

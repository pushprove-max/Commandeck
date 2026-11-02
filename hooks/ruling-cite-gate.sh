#!/usr/bin/env bash
# PreToolUse hook (Edit|Write|MultiEdit): a memory or rule line that credits a ruling to the owner must cite
# ruling:r-<id>, and the id must be in the ruling log that ruling-log.sh writes (issue 521).
# Self-test: bash hooks/__tests__/ruling-cite-gate.test.sh
#
# WHY: a note once gave a ruling an invented time and was then used as settled law. The log holds what the owner
# said and when; this gate makes a note point at it. A made-up id is refused like a missing one, and so is a void
# row or a suspect row (answered in under 2 s, maybe an Orca nudge) that main has not marked "confirmed".
#
# A claim is a line with `owner ruling`, `owner's ruling`, `owner ruled` or `ruling:r-`. Scope: a memory file
# (*/projects/*/memory/*; a profile's path has no .claude in it) and .claude/rules/. Only ADDED lines are read: the
# edit is applied to the file in memory and each resulting line the file does not already hold is screened, so an
# edit that changes only the date inside an old ruling line pays too. Old lines are left alone. Silent when it passes.
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# Retire when: zero blocks across 90 days of real rows from a project that installs the plugin, or ruling-log.sh is retired
# A substring test before the first jq, so an unrelated edit costs no fork.
case $INPUT in *memory/*|*.claude/rules/*) ;; *) exit 0 ;; esac
. "${BASH_SOURCE[0]%/*}/lib/project.sh"
. "${BASH_SOURCE[0]%/*}/lib/ruling-id.sh"
. "${BASH_SOURCE[0]%/*}/lib/edit-payload.sh" 2>/dev/null
hook_payload_loaded 2>/dev/null || { HOOK_FIRE_REASON=payload-lib-missing; echo "BLOCKED: ${BASH_SOURCE[0]##*/} could not load lib/edit-payload.sh, so it cannot screen this write. Restore it with \`git checkout -- hooks/lib/edit-payload.sh\` and retry." >&2; exit 2; }

# A MultiEdit may carry a path on each edit: every edited path in scope is screened, each with its own edits.
SCOPED=()
while IFS= read -r FILE_PATH; do
  case $FILE_PATH in
    */projects/*/memory/*|*/.claude/rules/*|.claude/rules/*) SCOPED+=("$FILE_PATH") ;;
  esac
done < <(jq -r '[.tool_input.file_path // empty, (.tool_input.edits // [] | .[] | .file_path // empty)] | unique | .[]' <<<"$INPUT" 2>/dev/null)
[ "${#SCOPED[@]}" -gt 0 ] || exit 0
[ -n "$(hook_edit_triples "$INPUT")" ] || exit 0

pp_project
LOG=${COMMANDECK_RULING_LOG:-$HOME/.claude/rulings/$PP_PROJECT.jsonl}
CLAIM="owner('s)? rul(ing|ed)|ruling:r-"
ADDED=$(for FILE_PATH in "${SCOPED[@]}"; do
  CUR=/dev/null; [ -f "$FILE_PATH" ] && CUR=$FILE_PATH
  # The file as it will be after this call. split/join keeps the replacement literal; the first-only form mirrors Edit
  # without replace_all. An old_string the file does not hold still has its new text screened, appended: the gate
  # must never pass text it did not look at.
  RESULT=$(jq -r --arg f "$FILE_PATH" --rawfile cur "$CUR" '
    def rep($o; $n; $all):
      split($o) as $p
      | if $o == "" or ($p | length) < 2 then . + "\n" + $n
        elif $all then $p | join($n)
        else $p[0] + $n + ($p[1:] | join($o)) end;
    .tool_input as $t
    | if $t.content != null and $t.file_path == $f then $t.content
      else reduce ((if $t.old_string != null and $t.file_path == $f then [$t] else [] end)
          + ($t.edits // [] | map(select((.file_path // $t.file_path) == $f))) | .[]) as $e
        ($cur; rep($e.old_string // ""; $e.new_string // ""; $e.replace_all // false))
      end' <<<"$INPUT" 2>/dev/null)
  # Added = resulting lines beyond each line's count on disk: a second copy of an old line is added, a moved line is not.
  printf '%s\n' "$RESULT" | awk 'FILENAME == ARGV[1] { n[$0]++; next } n[$0] > 0 { n[$0]--; next } { print }' "$CUR" - | grep -iE "$CLAIM"
done)
[ -n "$ADDED" ] || exit 0

BAD="" UNSURE="" MISSING=""
while IFS= read -r line; do
  ok=1
  IDS=$(grep -oE 'ruling:r-[0-9]{8}-[0-9]{6}-[0-9a-z]+-[0-9a-z]+' <<<"$line" | cut -d: -f2)
  [ -n "$IDS" ] || ok=0
  for id in $IDS; do
    ruling_id_state "$id" "$LOG"
    case $? in
      0) ;;
      1) ok=0; MISSING="$MISSING $id" ;;
      *) ok=0; UNSURE="$UNSURE $id" ;;
    esac
  done
  [ "$ok" = 1 ] || BAD="$BAD  ${line:0:160}"$'\n'
done <<<"$ADDED"
[ -n "$BAD" ] || exit 0

[ -z "$UNSURE" ] || HOOK_FIRE_REASON=ruling-void
if [ -n "$UNSURE" ]; then
  echo "BLOCKED: these ids are void, or suspect (answered in under 2 s, maybe an Orca nudge, not the owner):$UNSURE
A void row is never a ruling. For a suspect one, confirm with the owner in plain chat, then add \"confirmed\":\"ruling:<id of the reply>\" to its row in $LOG, found with \`jq -c 'select(.id == \"<id>\")' $LOG\`." >&2
fi
[ -z "$MISSING" ] || echo "These ids are not logged in $LOG:$MISSING" >&2
cat >&2 <<EOF
BLOCKED: line(s) credit a ruling to the owner without a logged ruling id.

$BAD
Each such line must carry ruling:r-<id>, and the id must be in $LOG.
Get the id from the "ruling logged: r-..." line printed after a question, or find the owner's words with \`jq -c '{id, et, answer}' $LOG\`.
Use the id that lookup prints, never one from memory.
EOF
HOOK_FIRE_REASON=uncited-ruling
[ -z "$MISSING" ] || HOOK_FIRE_REASON=ruling-not-logged
exit 2

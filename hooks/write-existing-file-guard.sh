#!/usr/bin/env bash
# PreToolUse hook (Edit|Write|MultiEdit): warn when a Write, Edit or MultiEdit
# hunk mostly restates lines it replaces, and point at the smaller edit.
#
# WHY. Restating a line the file already has buys nothing; the same change
# lands from an edit naming only what moved, and the restate is also where an
# unrelated line silently changes.
#
# WHAT IT MEASURES. For a Write, the replaced side is the file on disk; for an
# Edit or each MultiEdit hunk, it is old_string. difflib.SequenceMatcher over
# the two line lists; "unchanged" is the lines inside matching blocks. Warns
# when unchanged is at least half of the REPLACED side: that is exactly when
# an edit naming only the changed lines costs fewer tokens than the restate.
# A replaced side under 20 lines, or one under half the file's length, passes:
# an old_string that is mostly context can be the shortest unique anchor for
# the line that changes, and only a hunk spanning half the file is a rewrite.
# A Write to a missing file passes.
#
# EXIT CODE. Always 0: style diagnostics are advisory, including when this hook
# cannot inspect a Write/Edit payload.
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"

fail() {
  HOOK_FIRE_ADVISE=1
  echo "WARNING: write-existing-file-guard: $1 -- this $TOOL was NOT checked." >&2
  exit 0
}

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
case "$TOOL" in Write|Edit|MultiEdit) ;; *) exit 0 ;; esac

# CHEAP FILTER BEFORE PYTHON. A warning needs a replaced side of at least 20
# lines, so an Edit/MultiEdit payload carrying fewer than 19 escaped newlines
# cannot produce one -- counted in the shell with no fork at all. A Write is
# exempt from the filter because its replaced side is the file on disk, which
# the payload says nothing about.
#
# The arms name the fields the measurement needs, so a payload MISSING one is
# not filtered out: "too small to warn" and "I could not read this" are
# different answers, and the second one produces a NOT-checked warning.
case "$INPUT" in
  *'"content"'*) ;;
  *'"edits"'*|*'"new_string"'*)
    STRIPPED=${INPUT//\\n/}
    NEWLINES=$(( (${#INPUT} - ${#STRIPPED}) / 2 ))
    [ "$NEWLINES" -lt 19 ] && exit 0
    ;;
esac

command -v python3 >/dev/null 2>&1 || fail "python3 is not on PATH"

MSG=$(printf '%s' "$INPUT" | python3 -c '
import difflib, os, json, sys

event = json.load(sys.stdin)
tool, inp = event["tool_name"], event["tool_input"]
HINT = "Use Edit (or serena replace_symbol_body / replace_content) for the changed lines."

def read(path):
    with open(path, encoding="utf-8", errors="replace") as handle:
        return handle.read().splitlines()

if tool == "Write":
    hunks = [(inp["file_path"], None, inp["content"])]
else:
    edits = [inp] if tool == "Edit" else inp["edits"]
    # A per-edit file_path wins over the payload-level one (lib/edit-payload.sh).
    hunks = [(e.get("file_path") or inp.get("file_path"), e["old_string"], e["new_string"])
             for e in edits]

for path, old_text, new_text in hunks:
    if not isinstance(path, str) or not path:
        raise KeyError("file_path")
    if not os.path.isfile(path):
        continue
    on_disk = read(path)
    old = on_disk if old_text is None else old_text.splitlines()
    if not isinstance(new_text, str) or (old_text is not None and not isinstance(old_text, str)):
        raise KeyError("old_string/new_string/content")
    new = new_text.splitlines()
    if len(old) < 20 or len(old) * 2 < len(on_disk):
        continue
    matcher = difflib.SequenceMatcher(None, old, new, autojunk=False)
    unchanged = sum(block.size for block in matcher.get_matching_blocks())
    if unchanged * 2 >= len(old):
        if tool == "Write":
            print("WARNING: Write would restate %d lines of %s; only %d change. %s"
                  % (len(new), path, len(new) - unchanged, HINT))
        else:
            print("WARNING: %s old_string restates %d of its %d lines of %s unchanged; give old_string/new_string only the lines that change (plus what makes them unique)."
                  % (tool, unchanged, len(old), path))
        sys.exit(2)
' 2>/dev/null)
RC=$?
case "$RC" in
  0) exit 0 ;;
  2) HOOK_FIRE_ADVISE=1; echo "$MSG" >&2; exit 0 ;;
  *) fail "cannot compare the payload against its target (python3 exit $RC)" ;;
esac

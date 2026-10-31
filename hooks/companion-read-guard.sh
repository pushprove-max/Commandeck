#!/usr/bin/env bash
# codex: skip -- keyed to the Claude session's read record (read-record.sh, a PostToolUse hook on Read and Bash);
# Codex has no Read tool, so no contract could be recorded as read and every listed edit would be refused.
# PreToolUse hook (Edit|Write|MultiEdit): refuse an edit to a listed path until the contract it depends on was
# read in this session. Issue 520. The pairs are .claude/companions.tsv, one per line:
#   <edited path><TAB><contract path>[<TAB><why>]
# repo-relative; a trailing `/` on the first is a folder. Written by hand; no file means no check, and
# read-record.sh then records nothing. A Read or a shell read of the contract counts (read-record.sh); a contract
# read through a code server or a script does not, and the agent reads it once more.
# What it asks is not "did you read the file you change" but "did you read the one your change depends on".
# A tripwire against the skipped read, not a boundary. Self-test: bash hooks/__tests__/companion-read-guard.test.sh
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
IFS=$'\001' read -r SID CWD < <(jq -r '[.session_id // "", .cwd // ""] | join("\u0001")' <<<"$INPUT" 2>/dev/null)
HEX='[0-9A-Fa-f]'
[[ ${SID-} =~ ^$HEX{8}-$HEX{4}-$HEX{4}-$HEX{4}-$HEX{12}$ ]] || exit 0
# A MultiEdit may carry a path on each edit: every edited path is screened.
mapfile -t FILES < <(jq -r '[.tool_input.file_path // empty, (.tool_input.edits // [] | .[] | .file_path // empty)] | unique | .[]' <<<"$INPUT" 2>/dev/null)
[ "${#FILES[@]}" -gt 0 ] || exit 0
ROOT=$(git -C "${CLAUDE_PROJECT_DIR:-${CWD:-$PWD}}" rev-parse --show-toplevel 2>/dev/null) || exit 0
PAIRS=$ROOT/.claude/companions.tsv
[ -f "$PAIRS" ] || exit 0
TRACKER=/tmp/claude-read-tracker-$SID

for FILE in "${FILES[@]}"; do
  case "$FILE" in /*) ;; *) FILE=${CWD:-$ROOT}/$FILE ;; esac
  REL=$(realpath -m --relative-to="$ROOT" "$FILE" 2>/dev/null) || continue
  case "$REL" in ../* | /*) continue ;; esac
  LN=0
  while IFS=$'\t' read -r EDITED CONTRACT WHY || [ -n "${EDITED-}" ]; do
    LN=$((LN + 1))
    case "$EDITED" in '' | '#'*) continue ;; esac
    [ -n "${CONTRACT-}" ] || { echo "companion-read-guard: .claude/companions.tsv:$LN has no contract, so it pairs nothing" >&2; continue; }
    case "$EDITED" in
      */) case "$REL/" in "$EDITED"*) ;; *) continue ;; esac ;;
      *) [ "$REL" = "${EDITED%/}" ] || continue ;;
    esac
    [ "$REL" = "$CONTRACT" ] && continue
    ABS=$(realpath -m "$ROOT/$CONTRACT")
    grep -qxF -- "$ABS" "$TRACKER" 2>/dev/null && continue
    HOOK_FIRE_REASON=unread-contract
    echo "BLOCKED: read the contract this edit depends on first. Editing: $REL. Read this: $CONTRACT${WHY:+. Why: $WHY}. Open it with \`Read file_path=\"$ABS\"\` (or \`sed -n 1,200p $CONTRACT\`), then edit again. A read through a code server or a script does not count." >&2
    exit 2
  done < "$PAIRS"
done
exit 0

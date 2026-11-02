#!/usr/bin/env bash
# PreToolUse hook (Read|Bash), every seat, reviewers included: refuse a whole read of a generated file, and a
# shell command that reads saved tool output. Issues 519, 509, 503.
#
# Generated: a file `git check-attr linguist-generated` reports `true` (`x linguist-generated=true`) or `set`
# (a bare `x linguist-generated`). check-attr alone decides, so a .gitattributes in a subfolder counts. One
# builder re-read a 5,000-line generated inventory until it had spent 192M input tokens; a bounded read or a
# `jq`/`rg` query answers the same question.
# Whole means: a Read with no `limit`, or one whose window covers the file; a shell cat/nl/tac/less/more/bat/awk and
# the tools that print every line in another form (cut, sort, uniq, od, xxd, strings, column); a head, tail or sed
# that is not a window the lexer fully understands, or whose window covers the file; a search whose pattern matches
# every line; `jq .`, `python -m json.tool`, `git show <rev>:<file>`.
# `rg`, `grep`, a shorter `head` or `tail`, `sed -n 'a,bp'`, `sed Nq`, `jq <filter>` and a ranged Read pass.
#
# Saved output: a shell command with a word under */tool-results/* in a stage that is no echo or printf opens a
# permission prompt no person is there to answer. The Read and Grep tools read it with none. A bounded query passes:
# rg/grep with `-m N`, head/tail with `-n N`, N 1-500, over one regular file named literally; cat, sed, an absent or
# junk bound, and a glob, directory or second file (the cap counts per file) still block.
#
# Issue 509 was a host guard that refused a word named in an echo. Here a word prefilter only picks whether to
# run the lexer (lib/shell_reads.py); the lexer decides, and an echo reads nothing. A lexer that fails reads as no
# paths, so a crash never refuses a Bash call.
#
# A tripwire, not a boundary: it judges the command text, so a path held in a variable or read by a script the
# command runs passes. Self-test: bash hooks/__tests__/generated-read-guard.test.sh
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# Retire when: zero blocks across 90 days of real rows from a project that installs the plugin (bounded reads pass)
set -uo pipefail
HERE=${BASH_SOURCE[0]%/*}

# $1 = absolute path. Prints the repo-relative path when the file is generated.
generated_rel() {
  local top rel
  top=$(git -C "$(dirname "$1")" rev-parse --show-toplevel 2>/dev/null) || return 1
  rel=$(realpath -m --relative-to="$top" "$1") || return 1
  case "$(git -C "$top" check-attr linguist-generated -- "$rel" 2>/dev/null)" in
    *': linguist-generated: true' | *': linguist-generated: set') printf '%s\n' "$rel" ;;
    *) return 1 ;;
  esac
}

refuse_generated() { # $1 = repo-relative path
  HOOK_FIRE_REASON=generated-whole-read
  echo "BLOCKED: $1 is a generated file (linguist-generated in .gitattributes). A whole read of it is refused. Query it instead with \`jq '<path expression>' $1\` or \`rg -n '<pattern>' $1\`, or use the Read tool with offset and limit." >&2
  exit 2
}

refuse_saved() { # $1 = path
  HOOK_FIRE_REASON=saved-output-shell-read
  echo "BLOCKED: $1 is saved tool output, and a shell command that reads it opens a permission prompt. Use the Read tool (\`Read file_path=\"$1\" offset=1 limit=200\`) or the Grep tool (\`Grep pattern=\"<pattern>\" path=\"$1\"\`)." >&2
  exit 2
}

# One jq start for the payload's four fields. read merges the tabs of an empty field and would shift the next one up,
# so an absent limit is `-`; the offset defaults to 0 as before, so a limit with no offset is a whole read from line 1.
IFS=$'\t' read -r TOOL LIMIT OFFSET FILE < <(jq -r '[(.tool_name // "-"), (.tool_input.limit // "-"), (.tool_input.offset // 0), (.tool_input.file_path // "")] | join("\t")' <<<"$INPUT" 2>/dev/null)
[ "${LIMIT-}" = "-" ] && LIMIT=""
case "${TOOL-}" in
  Read)
    [ -f "$FILE" ] || exit 0
    WHOLE=0
    if [ -z "$LIMIT" ]; then WHOLE=1
    elif [[ $LIMIT =~ ^[0-9]+$ && $OFFSET =~ ^[0-9]+$ ]] && [ "$OFFSET" -le 1 ] && [ "$LIMIT" -ge "$(wc -l < "$FILE")" ]; then WHOLE=1
    fi
    [ "$WHOLE" = 1 ] || exit 0
    if REL=$(generated_rel "$(realpath "$FILE")"); then refuse_generated "$REL"; fi ;;
  Bash)
    CMD=$(jq -r '.tool_input.command // empty' <<<"$INPUT")
    CWD=$(jq -r '.cwd // empty' <<<"$INPUT")
    CWD=${CWD:-${CLAUDE_PROJECT_DIR:-$PWD}}
    [[ $CMD =~ (cat|nl|tac|less|more|bat|awk|sed|head|tail|jq|cut|sort|uniq|od|xxd|strings|column|grep|rg|json\.tool|show|cat-file|tool-results) ]] || exit 0
    while IFS=$'\t' read -r KIND ABS _ BOUND; do
      [ -n "${ABS-}" ] || continue
      case "$KIND" in
        saved) # a rg/grep -m N or head/tail -n N of 1-500 lines is the bounded read; the lexer gives `-` for any other shape
          [[ ${BOUND-} =~ ^[0-9]{1,4}$ ]] && [ "$((10#$BOUND))" -ge 1 ] && [ "$((10#$BOUND))" -le 500 ] && continue
          refuse_saved "$ABS" ;;
        dump) if REL=$(generated_rel "$ABS"); then refuse_generated "$REL"; fi ;;
      esac
    done < <(python3 -I "$HERE/lib/shell_reads.py" "$CMD" "$CWD" 2>/dev/null) ;;
esac
exit 0

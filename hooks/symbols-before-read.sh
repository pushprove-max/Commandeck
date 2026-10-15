#!/usr/bin/env bash
# codex: skip -- gates on this session's serena calls and hints main's own reads;
# Codex never sits in main. Nothing for Codex to run.
# PreToolUse hook on Read|Grep and Edit|MultiEdit|Write, and on Bash for the
# script-source hint below only. In a worker pane, the first edit to an existing
# runtime code file is refused once until the session asked who uses it. Reads
# are never gated: the symbols-first read rule and its shell twin were removed
# (owner ruling 2026-10-14; agents worked around nearly all of their blocks).
# Stands down when serena is off for the checkout or a serena call errored.
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# Strict tier: off unless the project turned it on (lib/project.sh).
{ . "${BASH_SOURCE[0]%/*}/lib/project.sh" && pp_strict && pp_serena; } 2>/dev/null || exit 0
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty'); CWD=${CWD:-$PWD}

# Same session key derivation as read-tracker.sh: the
# stdin session_id is stable across every hook call, the env var is unset here,
# and bare ${PPID} differs between calls inside a parallel tool block.
SID=$(echo "$INPUT" | jq -r '.session_id // empty')
KEY="${SID:-${CLAUDE_SESSION_ID:-${PPID}}}"
SERENA_TRACKER="/tmp/claude-serena-tracker-${KEY}"
SERENA_DOWN="/tmp/claude-serena-down-${KEY}"

gated_source() {
  # Letter case is not compared: on the Mac SRC/x.ts opens src/x.ts.
  set -- "${1,,}"
  case "$1" in *.ts|*.tsx|*.py) ;; *) return 1 ;; esac
  # Tests and type declarations have no useful symbol overview.
  case "$1" in *__tests__*|*/tests/*|*/test_*.py|*_test.py|*.test.ts|*.test.tsx|*.d.ts|*/__mocks__/*|*/node_modules/*) return 1 ;; esac
}

# serena reports repo-relative paths while Edit receives absolute ones, so the
# file is resolved against the repo root and the two are compared whole. The
# basename used to be the comparison, which admitted any file sharing a name
# with one serena had answered for.
rel_of() {
  local root; root=$(git -C "$(dirname "$1")" rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$root" ]; then printf '%s' "${1#"$root"/}"; else printf '%s' "$1"; fi
}

# Letter case is ignored only where the disk ignores it: on a disk that tells
# src/Auth from src/auth they are two files.
folds_case() { local u; u=$(tr 'a-zA-Z' 'A-Za-z' <<<"$CWD"); [ "$u" != "$CWD" ] && [ "$CWD" -ef "$u" ]; }

# Silence is not unavailability: serena is a deferred tool in worker panes, so
# it stays silent until loaded. Only an errored serena call (read-tracker.sh
# writes the marker) or serena switched off for the checkout stands the gate
# down.
serena_unavailable() {
  [ -e "$SERENA_DOWN" ] && return 0
  local session_root; session_root=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
  jq -e --arg p "${session_root:-$CWD}" '((.projects[$p].disabledMcpServers // []) | index("serena")) != null
    or (.mcpServers.serena == null and .projects[$p].mcpServers.serena == null)' "$HOME/.claude.json" >/dev/null 2>&1
}

# A linked worktree is a worker seat; a reviewer pane is exempt.
in_worker() {
  [ "${COMMANDECK_REVIEWER:-}" != "1" ] \
    && [ "$(git -C "$CWD" rev-parse --git-dir 2>/dev/null)" != "$(git -C "$CWD" rev-parse --git-common-dir 2>/dev/null)" ]
}

# THE FIRST EDIT TO A SOURCE FILE ASKS WHO USES IT. In a worker pane the first
# edit to an existing gated file is refused once, unless this session asked serena
# find_referencing_symbols about that file or codebase-memory trace_path about a
# function named in it (read-tracker.sh records both). A new file has no
# callers: one not yet written, and one that is on no base of the branch
# (new_in_branch).
case "$TOOL" in Edit|MultiEdit|Write)
  [ -f "$FILE_PATH" ] && gated_source "$FILE_PATH" || exit 0
  in_worker && ! serena_unavailable || exit 0
  . "${BASH_SOURCE[0]%/*}/lib/symbol-outline.sh"
  new_in_branch "$FILE_PATH" && exit 0
  REL=$(rel_of "$FILE_PATH")
  grep -q$(folds_case && echo i)xF -e "refs-file:$REL" -e "edit-asked:$REL" "$SERENA_TRACKER" 2>/dev/null && exit 0
  while IFS= read -r fn; do
    [ -n "$fn" ] && grep -qwF -- "${fn##*.}" "$FILE_PATH" && exit 0
  done < <(sed -n 's/^trace://p' "$SERENA_TRACKER" 2>/dev/null)
  echo "edit-asked:$REL" >> "$SERENA_TRACKER"
  # The refusal answers the question itself: one word-match search for
  # the file's top-level names, so the retry needs no lookup turn.
  TOP=$(git -C "${FILE_PATH%/*}" rev-parse --show-toplevel 2>/dev/null)
  PATS=()
  for NAME in $(symbol_outline "$FILE_PATH"); do PATS+=(-e "$NAME"); done
  USERS=""
  [ ${#PATS[@]} -gt 0 ] && [ -n "$TOP" ] && USERS=$(cd "$TOP" \
    && rg -l -w -F "${PATS[@]}" -- . 2>/dev/null | sed 's|^\./||' | grep -vxF -- "$REL" | sort | head -20)
  cat >&2 <<MSG
BLOCKED once: before your first edit to '$REL', check who uses what you are changing.
Files naming one of its top-level symbols (word match, at most 20):
${USERS:-(none found)}
Retry the edit now: this file is not refused again. For one symbol's exact callers, use
mcp__serena__find_referencing_symbols (relative_path '$REL') or mcp__codebase-memory__trace_path.
MSG
  exit 2 ;;
esac

# MAIN READS A DRIVER'S --help, NOT ITS SOURCE. Main opened script
# source ~45 times in 12 hours to learn how to call it, and every read stays in
# its context. A read of a scripts/*.sh that answers --help carries a
# --help hint as advice and always passes: refusing it cost a turn and
# redirected nothing (owner ruling 2026-10-01). Shell reads are covered here
# too. Worker worktrees are exempt.
if [[ "$INPUT" == *scripts/* ]]; then
  SH_CWD=$CWD
  SH_TARGET=$(
    case "$TOOL" in
      (Read|Grep) echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' ;;
      (Bash) echo "$INPUT" | jq -r '.tool_input.command // empty' \
          | sed -E 's/[[:space:]]*(&&|\|\||[;|])[[:space:]]*/\n/g' \
          | grep -E '^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*(cat|head|tail|sed|awk|nl|less|grep|rg)\b' \
          | grep -oE '[A-Za-z0-9_./~-]*scripts/[A-Za-z0-9_.-]+\.sh' ;;
    esac | while IFS= read -r p; do
      case "$p" in (/*) f=$p ;; ("~/"*) f="$HOME/${p#\~/}" ;; (*) f="$SH_CWD/$p" ;; esac
      case "$f" in (*/scripts/__tests__/*) continue ;; (*/scripts/*.sh) ;; (*) continue ;; esac
      grep -qF -- '--help|-h)' "$f" 2>/dev/null && { echo "$p"; break; }
    done
  )
  if [ -n "$SH_TARGET" ] \
    && [ "$(git -C "$SH_CWD" rev-parse --git-dir 2>/dev/null)" = "$(git -C "$SH_CWD" rev-parse --git-common-dir 2>/dev/null)" ]; then
    # Nothing below writes stdout, so this stays the call's one JSON answer.
    HOOK_FIRE_ADVISE=1
    jq -cn --arg m "Hint: 'bash scripts/${SH_TARGET##*/} --help' prints its flags and an example; read the source only to debug it." \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}'
  fi
fi

# Main may read a worker's worktree, with Read and Grep as with the shell:
# the owner took the block out of bash-guardrails.sh on 2026-09-25.
exit 0

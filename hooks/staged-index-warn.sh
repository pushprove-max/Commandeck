#!/usr/bin/env bash
# PostToolUse hook (Bash): after a test suite runs, report indexed paths whose
# working copies now differ.
#
# WHY: an indexed path can diverge from its working copy after a suite runs.
# That state is worth surfacing, but it does not establish which bytes the
# completed suite read. This hook reports only the observed post-run snapshot.
#
# AT THE SUITE, NOT AT EVERY EDIT. It used to fire on Edit|Write|MultiEdit, so
# every edit in a session paid two git scans to warn about a condition that only
# matters when a suite runs -- and the warning landed nowhere near the green
# summary it was about. Now it runs after the suite command itself, where the
# reader is looking at the totals it qualifies. It stays a WARNING and not a
# refusal: it reports on a run that has already happened.
#
# Successful advisories use Claude's systemMessage result and stderr, which the
# Codex dispatcher relays. A deliberate anti-nag scope prevents repeated output.
#
# ANTI-NAG: the selected checkout and relevant index/working content are hashed
# into a marker; an unchanged observed pair stays silent.

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# Strict tier: off unless the project turned it on (lib/project.sh).
{ . "${BASH_SOURCE[0]%/*}/lib/project.sh" && pp_strict; } 2>/dev/null || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# The runs whose result a dirty index can quietly weaken. A tsc, a lint or an
# ordinary script reads no fixtures and is none of this hook's business.
printf '%s' "$CMD" \
  | grep -qE '(^|[;&|[:space:]])((npm|npx|pnpm|yarn)[[:space:]]+(run[[:space:]]+)?test|vitest|jest)|--test([[:space:]]|$)' \
  || exit 0

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -d "$CWD" ] || CWD=$PWD
CD_TARGET=$(printf '%s' "$CMD" \
  | sed -nE 's/^[[:space:]]*cd[[:space:]]+"?([^;&|"]+)"?[[:space:]]*(&&|;).*/\1/p' | head -1)
CD_TARGET="${CD_TARGET%"${CD_TARGET##*[![:space:]]}"}"
if [ -n "$CD_TARGET" ]; then
  case "$CD_TARGET" in
    /*) CANDIDATE="$CD_TARGET" ;;
    *) CANDIDATE="$CWD/$CD_TARGET" ;;
  esac
  [ -d "$CANDIDATE" ] && CWD=$(cd "$CANDIDATE" && pwd -P)
fi

ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
DIVERGED=()
while IFS= read -r -d '' file; do
  if { [ -e "$ROOT/$file" ] || [ -L "$ROOT/$file" ]; } \
      && ! git -C "$ROOT" cat-file -e ":$file" 2>/dev/null; then
    DIVERGED+=("$file")
    continue
  fi
  git -C "$ROOT" --no-optional-locks diff --quiet -- "$file" 2>/dev/null \
    || DIVERGED+=("$file")
done < <(git -C "$ROOT" --no-optional-locks diff --cached --name-only -z 2>/dev/null)
[ "${#DIVERGED[@]}" -eq 0 ] && exit 0

HASH=$( {
  for file in "${DIVERGED[@]}"; do
    printf '%s\0' "$file"
    git -C "$ROOT" rev-parse ":$file" 2>/dev/null || printf 'no-index\n'
    if [ -e "$ROOT/$file" ]; then
      git -C "$ROOT" hash-object -- "$file" 2>/dev/null || printf 'unreadable\n'
    else
      printf 'missing\n'
    fi
  done
} | cksum | awk '{print $1}')
MARKER_DIR="${TMPDIR:-/tmp}/commandeck-staged-warn"
mkdir -p "$MARKER_DIR" 2>/dev/null || exit 0
MARKER="$MARKER_DIR/$(printf '%s' "$ROOT" | cksum | awk '{print $1}')"

# Same observed index/working pairs as last time -- stay quiet.
[ -f "$MARKER" ] && [ "$(cat "$MARKER" 2>/dev/null)" = "$HASH" ] && exit 0
printf '%s' "$HASH" > "$MARKER" 2>/dev/null

COUNT=${#DIVERGED[@]}

MESSAGE=$(cat <<MSG
POST-run index/working divergence observed in $ROOT: $COUNT file(s).

$(printf '  %s\n' "${DIVERGED[@]:0:10}")

This snapshot reports only the current indexed and working content; it does not
prove which tree the completed suite read. Review the divergence before relying
on the result.

MSG
)
HOOK_FIRE_ADVISE=1
printf '%s\n' "$MESSAGE" >&2
jq -cn --arg message "$MESSAGE" '{
  systemMessage:$message,
  hookSpecificOutput:{
    hookEventName:"PostToolUse",
    additionalContext:$message
  }
}'
exit 0

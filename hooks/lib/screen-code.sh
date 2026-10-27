#!/usr/bin/env bash
# screen-code.sh -- sourced, never run. What screen code is (issue 392) and what placeholder UI is (issue 398), in one
# place for the merge script and the content tripwire. Bash 3.2 and POSIX awk (BSD awk runs always_disabled_lines).

# screen_prefixes <project dir>: the folder prefixes of the project's screen code, one a line. The `screenPaths` array of
# <dir>/.claude/commandeck.json; with no such key, web/src/; an empty array: none.
screen_prefixes() {
  local f=$1/.claude/commandeck.json
  if [ -f "$f" ] && jq -e 'has("screenPaths")' "$f" >/dev/null 2>&1; then jq -r '.screenPaths[]? | strings' "$f" 2>/dev/null
  else echo web/src/; fi
}

# is_screen <repo-relative path>: under one of $SCREEN_PREFIXES (the caller's screen_prefixes output), a .tsx, .css or
# .html file that is not a test or a story. Success when it is.
is_screen() {
  local p=$1 pre ok=""
  while IFS= read -r pre; do
    if [ -n "$pre" ]; then case $p in "$pre"*) ok=1 ;; esac; fi
  done <<<"${SCREEN_PREFIXES-}"
  [ -n "$ok" ] || return 1
  case $p in *.tsx|*.css|*.html) ;; *) return 1 ;; esac
  case $p in *.test.tsx|*.spec.tsx|*.stories.tsx|__tests__/*|*/__tests__/*) return 1 ;; esac
  return 0
}

# screen_rel <absolute path>: the path relative to the checkout holding it, then that checkout's root on a second line.
# The root is asked of the file's own folder (the nearest existing one above it for a new file), never the session's
# working folder. A path in no checkout prints nothing.
screen_rel() {
  local d=${1%/*} pd root full
  case $1 in /*) ;; *) return 0 ;; esac
  while [ -n "$d" ] && [ ! -d "$d" ]; do d=${d%/*}; done
  [ -n "$d" ] || d=/
  pd=$(cd "$d" 2>/dev/null && pwd -P) || return 0
  root=$(git -C "$pd" rev-parse --show-toplevel 2>/dev/null) || return 0
  full=${pd%/}${1#"${d%/}"}
  case $full in "$root"/*) printf '%s\n%s\n' "${full#"$root"/}" "$root" ;; esac
  return 0
}

# Issue 398: copy that says a thing comes later. Case-insensitive ERE.
PLACEHOLDER_COPY='coming soon|not available yet|not yet available|available soon|in a later update|in a later release|coming in a later|under construction'

# always_disabled_lines: reads a text on stdin (TSX, an .html file, a plan) and prints, once per occurrence, the number
# of each line holding a single-line opening tag with a constant disabled attribute: bare, ={true} or ="..." / ='...'.
# A tag is <name ...> or <name .../> on one line, name a lowercase HTML control (button input select textarea fieldset
# optgroup option) or any capitalised component; a value inside it is read whole as "...", '...' or one {...} with no
# braces inside, so the > of => or of "a > b" ends nothing. Every < on a line starts its own try (a control inside
# another tag's value counts for itself). Each line is judged alone: nothing is kept from one line to the next.
# Ceiling (plan Accepted failure mode 10): this is a fixed pattern, not a TSX parser. Missed: a tag split over lines,
# a value with nested braces, type arguments on the tag, an unquoted HTML value, a comment inside {true}. Refused: a
# single-line control spelled in a string, template or trailing comment, and a comment between disabled and its =;
# approve such a line on a Placeholder: line, or move the example out of screen code. A control spelled in a
# comment-only line is not refused: callers screen screen_code_part's output (issue 400).
always_disabled_lines() {
  awk '
  {
    r = $0
    while (match(r, /<(button|input|select|textarea|fieldset|optgroup|option|[A-Z][A-Za-z0-9_.]*)([^<>"\047{}]|"[^"]*"|\047[^\047]*\047|\{[^{}]*\})*>/)) {
      t = substr(r, RSTART, RLENGTH); r = substr(r, RSTART + 1)
      gsub(/"[^"]*"|\047[^\047]*\047/, "\"\"", t)
      gsub(/\{[ \t]*true[ \t]*\}/, "T", t)
      gsub(/\{[^{}]*\}/, "E", t)
      while (match(t, /[ \t]disabled[ \t]*(=[ \t]*(T|"")|[ \t]*[\/>]|[ \t]+[^= \t])/)) { print NR; t = substr(t, RSTART + RLENGTH - 1) }
    }
  }'
}

# screen_code_part <line>: prints the code on a source line (issue 400, the host's rule): nothing for a comment line
# (//, /*, * or {/* first), the code after a leading comment that closes on the line, and the line itself otherwise. A
# // comment never closes; a trailing comment stays in the printed code.
_SC_COMMENT_RE='^[[:space:]]*(//|/\*|\*|\{/\*)'
screen_code_part() {
  local c=${1}
  while [[ $c =~ $_SC_COMMENT_RE ]]; do
    if [[ $c =~ ^[[:space:]]*// || $c != *'*/'* ]]; then return 0; fi
    c=${c#*'*/'}; c=${c#"${c%%[![:space:]]*}"}; c=${c#\}}
  done
  printf '%s' "$c"
}

_sc_trim() { local s=$1; s=${s#"${s%%[![:space:]]*}"}; s=${s%"${s##*[![:space:]]}"}; printf '%s' "$s"; }

# placeholder_sources <unit> <worktree> <main>: the plans the unit brief's Plan section names, as committed on local
# main, then main's rulings file for the unit. builder-launch.sh nests the batch two heading levels down, so the section
# is a Plan heading of any level, and it ends at the next heading of any level.
placeholder_sources() {
  local brief=$2/.claude/briefs/$1.md p
  [ -r "$brief" ] || brief=$3/.claude/briefs/$1.md
  if [ -r "$brief" ]; then
    awk '/^#+ /{ on = ($0 ~ /^#+ Plan[[:space:]]*$/); next } on' "$brief" \
      | grep -oE '\.claude/plans/[A-Za-z0-9._-]+\.md' | sort -u \
      | while IFS= read -r p; do git -C "$3" show "main:$p" 2>/dev/null; done
  fi
  cat "$3/.claude/briefs/$1-main-rulings.md" 2>/dev/null
  return 0
}

# placeholder_count <file> <line> <unit> <worktree> <main>: how many `Placeholder: <file> | <complete source line> | <why>`
# lines approve this line: the file equal, the middle field equal to the line (both trimmed, never a substring), a
# non-empty why.
placeholder_count() {
  local want l file rest why mid n=0
  want=$(_sc_trim "$2")
  while IFS= read -r l; do
    l=$(_sc_trim "$l"); l=${l#- }
    case $l in 'Placeholder: '*) ;; *) continue ;; esac
    l=${l#Placeholder: }
    file=${l%% | *}; [ "$file" != "$l" ] || continue
    rest=${l#* | }
    why=${rest##* | }; [ "$why" != "$rest" ] || continue
    mid=${rest% | *}
    [ -n "$(_sc_trim "$why")" ] || continue
    [ "$(_sc_trim "$file")" = "$1" ] && [ "$(_sc_trim "$mid")" = "$want" ] && n=$((n + 1))
  done < <(placeholder_sources "$3" "$4" "$5")
  echo "$n"
}

# placeholder_requested <file> <line> <unit> <worktree> <main>: success when a Placeholder line approves the line.
placeholder_requested() { [ "$(placeholder_count "$@")" -gt 0 ]; }

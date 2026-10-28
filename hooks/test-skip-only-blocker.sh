#!/usr/bin/env bash
# PreToolUse hook on Edit|Write: Block skipped/focused tests (masking).
# .only silently drops the rest of the suite; .skip/xit hide failing tests --
# both defeat coverage and let regressions through green.
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# Strict tier: off unless the project turned it on (lib/project.sh).
{ . "${BASH_SOURCE[0]%/*}/lib/project.sh" && pp_strict; } 2>/dev/null || exit 0
source "$(dirname "${BASH_SOURCE[0]}")/lib/edit-payload.sh" 2>/dev/null
# A guard that cannot read the payload must NOT pass the write: see the load
# sentinel at the bottom of lib/edit-payload.sh.
hook_payload_loaded 2>/dev/null || { echo "BLOCKED: ${BASH_SOURCE[0]##*/} could not load hooks/lib/edit-payload.sh, so it cannot screen this write. Reinstall the plugin (\`claude plugin install commandeck@commandeck\`) and retry." >&2; exit 2; }
CONTENT=$(hook_new_text "$INPUT")
[ -z "$CONTENT" ] && exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
# A hook self-test QUOTES `it.only` as the fixture it must catch; it is not a
# suite of this repo's tests and skips nothing. Same exemption the other content
# guards give their own directory.
#
# BOTH PATH FORMS. A payload may carry the path relative to the repo root, and
# `*/hooks/*` does not match hooks/__tests__/x.test.sh -- that
# path then fell through to `*__tests__*` below and the fixture was screened as
# a real test.
#
# ONLY THE SHELL SELF-TESTS. A project's own folder named hooks (React's
# src/hooks) holds real tests, and `*/hooks/*` let `it.only` through in them.
case "$FILE_PATH" in
  */hooks/__tests__/*.sh|hooks/__tests__/*.sh) exit 0 ;;
esac
. "${BASH_SOURCE[0]%/*}/lib/test-path.sh" 2>/dev/null && declare -F is_test_path >/dev/null \
  || { echo "BLOCKED: ${BASH_SOURCE[0]##*/} could not load hooks/lib/test-path.sh, so it cannot screen this write. Reinstall the plugin (\`claude plugin install commandeck@commandeck\`) and retry." >&2; exit 2; }
is_test_path "$FILE_PATH" || exit 0

# RUNNER ALIASES. `const itCompat = it; itCompat.only(...)` focused a suite past the literal names. A name bound by
# `const|let|var <name> = <runner>...` or `import { <runner> as <name> }` counts as a runner, read from the text the
# file will hold: a Write's content; an Edit or MultiEdit applied in order to the file on disk (a missing file is the
# new text alone), so a declaration already on disk counts and one the edit removes does not. An alias made in
# another module still slips (accepted: resolving names across files needs a parser).
ABS=$FILE_PATH
case "$ABS" in /*) ;; *) ABS="$(echo "$INPUT" | jq -r '.cwd // "."')/$ABS" ;; esac
RESULT=$CONTENT
[ -f "$ABS" ] && RESULT=$(jq -r --rawfile disk "$ABS" '
  def swap($s; $o; $n; $all):
    if $o == "" then $s + $n
    elif $all then $s | split($o) | join($n)
    else ($s | index($o)) as $i | if $i == null then $s else $s[:$i] + $n + $s[$i + ($o | length):] end end;
  .tool_input as $t
  | if $t.content != null then $t.content
    else reduce ([$t | select(.new_string != null or .old_string != null)] + ($t.edits // []))[] as $e
      ($disk; swap(.; $e.old_string // ""; $e.new_string // ""; $e.replace_all == true)) end' <<<"$INPUT" 2>/dev/null) \
  || RESULT=$CONTENT
# D2a, the fixed statement-start list: a one-line rename binds only after start of text, a newline, `;`, `{`, `}` or
# `*/`. Nothing is stripped or lexed: every stripper so far misread a regex, a division or a quote and blanked a real
# alias. A declaration quoted or commented mid-line follows a quote, `//`, `/*`, `/` or a backtick, none a statement
# start, so it binds nothing (one at a statement start inside a literal binds: blocking only). Simple renames only:
# a typed or multi-line rename binds nothing, a known gap.
ALIASES=$(jq -rn --arg t "$RESULT" '
  "[A-Za-z_][A-Za-z0-9_]*" as $name | "(?:it|test|describe|context)" as $runner | "(?:\\A|[\\n;{}]|\\*/)[ \\t]*" as $start
  | [ ($t | scan($start + "(?:export[ \\t]+)?(?:const|let|var)[ \\t]+(" + $name + ")[ \\t]*=[ \\t]*" + $runner + "\\b") | .[0]),
      ($t | scan($start + "import[ \\t]+(?:type[ \\t]+)?\\{([^}\\n]*)\\}") | .[0]
          | scan("\\b" + $runner + "[ \\t]+as[ \\t]+(" + $name + ")") | .[0]) ]
  | unique | join("|")' 2>/dev/null)
RUNNERS="describe|it|test|context${ALIASES:+|$ALIASES}"
# Focus/skip fns must be matched as CALLS: bare \bfit\b matched the English word
# "fit" in an assertion message and blocked a legit test (2026-07-06). The paren
# is ADJACENT for the same reason -- `does not fit (see the spec)` in a message
# still matched `fit[[:space:]]*\(`, and nobody writes the Jasmine form with a
# space before its arguments.
PATTERN='\b('"$RUNNERS"')\.(only|skip)\b|\b(xit|xdescribe|fit|fdescribe)\(|\b(it|test)\.todo\b'
# `// skip-ok: <reason>` is the approved-skip marker -- an assertion
# counter honours exactly this form, so a skip
# annotated the sanctioned way must not be refused by its sibling guard. The
# marker is per LINE: annotating one skip does not license the next. A quote or backtick after it means the marker
# sits in a string (`const s = "// skip-ok: x"; it.skip(`), so it licenses nothing.
OFFENDERS=$(echo "$CONTENT" | grep -E "$PATTERN" | grep -vE "//[[:space:]]*skip-ok:[^\"'\`]*\$")
if [ -n "$OFFENDERS" ]; then
  MATCH=$(printf '%s\n' "$OFFENDERS" | grep -oE "$PATTERN" | head -1)
  echo "BLOCKED: '$MATCH' in $FILE_PATH skips or focuses tests -- that masks failures and disables coverage." >&2
  echo "Remove it and make the test pass. An intentional skip carries // skip-ok: <reason> on the same line, and that is the owner's decision, not a default." >&2
  exit 2
fi

exit 0

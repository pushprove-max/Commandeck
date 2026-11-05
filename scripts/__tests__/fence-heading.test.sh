#!/usr/bin/env bash
# covers: scripts/fence.sh
# fence-heading.test.sh -- issue 640: the one heading reader of fence.sh (heading(), hold(), hflush()) every section
# gate reads through. A gate that misses an indented, underlined or closed heading reads the wrong section or none, so
# a Builder's stated limit, a Post-merge line or an open question slips past it; one that reads a heading out of a
# fence or an HTML block ends a section early. Each case below is a markdown shape CommonMark reads one way and the old
# `^## ` greps read another.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
. "$REAL/scripts/fence.sh"
# heads: one `level:title` per heading read. sect <title>: the section a gate reads, from a heading of that title (any
# level, any form) to the next heading of its level or higher, printed through hold() as every section site does.
heads() { printf '%b' "$1" | awk "$PP_AWK_FENCE"'fence($0) || flen { next } heading($0) { print hlvl ":" htxt }' | paste -sd'|' -; }
sect() { printf '%b' "$2" | awk -v want="$1" "$PP_AWK_FENCE"'
  fence($0) || flen { if (s) printf "%s%s\n", hflush(), $0; next }
  { heading($0); out = hold($0) }
  s && hlvl && hlvl <= lv { printf "%s", out; exit }
  !s && hlvl && htxt == want { s = 1; lv = hlvl; next }
  s { printf "%s", out }
  END { if (s) printf "%s", hflush() }' | paste -sd'|' -; }
fenced() { printf '%b' "$1" | awk "$PP_AWK_FENCE"'fence($0) || flen { print NR }' | paste -sd' ' -; }

check "indented heading ends a section" '- a' "$(sect 'Stated limits' '## Stated limits\n- a\n   ## Next\n- b\n')"
check "setext underline under text starts a section" '- a' "$(sect 'Stated limits' 'Stated limits\n---\n- a\n## Next\n')"
check "setext underline under a list item is not a heading" '- first limit|---|- second limit' \
  "$(sect 'Stated limits' '## Stated limits\n- first limit\n---\n- second limit\n## Next\n')"
check "closed ATX title drops hashes" '2:Stated limits|3:Post-merge' "$(heads '## Stated limits ##\n### Post-merge #\n')"
check "heading in fence is not a heading" '' "$(heads '```\n## Stated limits\n```\n')"
check "setext underline inside an HTML block is not a heading" '<div>|---|</div>|- second limit' \
  "$(sect 'Stated limits' '## Stated limits\n<div>\n---\n</div>\n- second limit\n')"
check "heading inside an HTML comment is not a heading" '' "$(heads '<!--\n## Stated limits\n-->\n')"
check "less-than text before a heading keeps the heading" '- skip verification' \
  "$(sect 'Stated limits' '<3\n## Stated limits\n- skip verification\n')"
check "four-space fence opens nothing" '|2:Stated limits' "$(fenced '    ```\n## Stated limits\n')|$(heads '    ```\n## Stated limits\n')"
check "deeper indented heading is text" '' "$(heads '    ## Stated limits\n')"
check "script-prefixed word opens no HTML block" '- skip verification' \
  "$(sect 'Stated limits' '<scripture\n## Stated limits\n- skip verification\n')"
check "fence line inside an HTML block opens no fence" '2:Question for the owner' \
  "$(heads '<div>\n~~~\n\n## Question for the owner\nWhat now?\n')"
check "backtick span line opens no fence" '|2:Stated limits' "$(fenced '```a`b```\n## Stated limits\n')|$(heads '```a`b```\n## Stated limits\n')"
check "multiline setext title reads the whole paragraph" '2:Question for the owner' "$(heads 'Question  for\n  the owner\n---------\n')"
check "setext title lines stay out of the section they end" 'None: answered.|' \
  "$(sect 'Question for the owner' '## Question for the owner\nNone: answered.\n\nSteps\n-----\n- one\n')"

echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" = 0 ]

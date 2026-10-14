#!/usr/bin/env bash
# brief-issues.test.sh -- the dashboard's "Issue by issue" list was empty for a
# running build and said "The brief lists no issue numbers": the brief listed
# each issue as a heading of its own, right under "The batch", and the reader
# took only numbered lines under "The issues", or the text under "The batch" up
# to the very next heading. What this pins: scripts/brief-issues.sh, the one
# reader (the dashboard and the launch dry run both ask it), also takes issue
# headings at any level, does not end the batch section at a sub-heading, and
# keeps an item with no issue number as a text entry instead of dropping it.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
# items <brief text> [<rulings text>] -- the reader's answer for a brief of that text.
items() { printf "$1" > "$T/b.md"; rm -f "$T/r.md"; [ -z "${2:-}" ] || printf "$2" > "$T/r.md"; bash "$ROOT/scripts/brief-issues.sh" "$T/b.md" "$T/r.md" 2>&1; }

check "numbered lines under The issues, as before; a line that only mentions an issue is not an item" '[11,12]' \
  "$(items '# u\n\n## The issues\n\n1. #11: first\n2. #12: second\n   it only mentions #99\n\n## Other\n\n#98\n')"
check "main's rulings add their numbered items" '[11,13]' "$(items '## The issues\n\n1. #11: first\n' '1. #13: added by main\nprose about #77\n')"
check "The issues with no numbered line gives every number in it" '[4,5]' "$(items '## The issues\n\nFix #4 and #5.\n\n## Other\n\n#6\n')"
# The three layouts of the report.
check "issues as headings of their own right under The batch" '[12,14]' \
  "$(items '# u\n\n## The batch (issues and done criteria)\n\n## 1. #12 the first\n\nDo it; see also #90.\n\n## 2. #14 the second\n\nDo that.\n\n## How to work\n\n- see #77\n')"
check "an issue heading counts at any level, numbered or not" '[21,22,23]' \
  "$(items '## The batch\n\n### #21: one\n\ntext\n\n#### 2. #22 two\n\ntext\n\n# #23 three\n')"
check "a sub-heading right after The batch does not end the batch section" '[31,32]' \
  "$(items '## The batch (issues and done criteria)\n\n### Scope\n\nThis builds #31 and #32.\n\n### Tests\n\nRed first.\n\n## How to work\n\n- never #77\n')"
check "an item with no issue number is kept, as its own text" '[41,"Tidy the notes",42]' \
  "$(items '## The issues\n\n1. #41: first\n2. Tidy the notes.\n3. #42: last\n')"
check "and so is a numbered heading with no number, among issue headings" '[51,"Tidy the notes"]' \
  "$(items '## The batch\n\n## 1. #51 first\n\ntext\n\n## 2. Tidy the notes\n\ntext\n')"
check "numbered headings alone, with no issue heading among them, are not taken for items" '[]' "$(items '## The batch\n\nNo numbers here.\n\n## 1. Read first\n\ntext\n')"
check "a brief with nothing to read gives an empty list, not an error" '[]' "$(items 'Just prose.\n')"
check "a missing brief gives an empty list" '[]' "$(bash "$ROOT/scripts/brief-issues.sh" "$T/none.md" 2>&1)"
check "the template main fills in lists its issues in the shape the reader takes" '[12,"an item with no issue: its title"]' \
  "$(sed 's/#<n>: <title>/#12: a title/; s/<an item/an item/; s/title>$/title/' "$ROOT/templates/_batch-brief-template.md" > "$T/t.md"; bash "$ROOT/scripts/brief-issues.sh" "$T/t.md" 2>&1)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

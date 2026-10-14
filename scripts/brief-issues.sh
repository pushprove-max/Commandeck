#!/usr/bin/env bash
# brief-issues.sh <brief> [<main's rulings file>] -- the work items of a batch
# brief as a JSON list: an issue is its number, an item with no issue number is
# its own text. The one reader: the dashboard's "Issue by issue" list and the
# launch dry run both ask it.
# brief-issues.sh --list -- the same list from marker lines on stdin ("#12" an
# issue, "=text" an item with no number), first-seen order, each once.
# In order, the first that finds anything:
#  1. the numbered lines of the "The issues" section ("1. #12: title"; a
#     continuation line only mentions issues and is not an item);
#  2. every #<n> in that section;
#  3. issue headings at any level, anywhere ("## 2. #12 title", "### #12"),
#     and among them a numbered heading with no number as an item of its own;
#  4. every #<n> of the "The batch" section, its sub-sections included: it
#     ends at the next heading of its own level or above.
# Main's rulings file adds the issues its numbered lines name.
# shortcut: an issue mentioned on an item's own first line counts as a work
# item; give the briefs a marked issue list if that ever miscounts.
set -uo pipefail
list() { awk '!s[$0]++' | jq -Rcn '[inputs | select(length > 1) | if startswith("#") then (.[1:] | tonumber) else .[1:] end]'; }
[ "${1:-}" != --list ] || { list; exit; }
B=${1:?usage: brief-issues.sh <brief> [<rulings file>]}; R=${2:-}
[ -r "$B" ] || { echo '[]'; exit 0; }
# Read once: the launch dry run hands the brief in as a pipe.
B=$(cat "$B")
# items -- each line on stdin is one work item: its issue numbers, or with none its whole text: the text is
# the item's name, and the dashboard matches an evidence heading against all of it.
items() {
  local l
  while IFS= read -r l; do
    if grep -qE '#[0-9]+' <<<"$l"; then grep -oE '#[0-9]+' <<<"$l"
    else l=$(sed -E 's/^[[:space:]]+//; s/[[:space:]:.]+$//' <<<"$l"); [ -z "$l" ] || printf '=%s\n' "$l"; fi
  done
}
SEC=$(awk '/^#+ /{on = ($0 ~ /^#+ The issues/)} on' <<<"$B")
OUT=$(grep -E '^[0-9]+\. ' <<<"$SEC" | sed -E 's/^[0-9]+\. +//' | items)
[ -n "$OUT" ] || OUT=$(grep -oE '#[0-9]+' <<<"$SEC")
if [ -z "$OUT" ] && grep -qE '^#+ +([0-9]+\. +)?#[0-9]+' <<<"$B"; then
  OUT=$(grep -E '^#+ +(([0-9]+\. +)?#[0-9]+|[0-9]+\. )' <<<"$B" | sed -E 's/^#+ +([0-9]+\. +)?//' | items)
fi
[ -n "$OUT" ] || OUT=$(awk '/^#+ /{ l = length($1); if (on && l <= lv) on = 0; if (!on && $0 ~ /^#+ The batch/) { on = 1; lv = l } } on' <<<"$B" | grep -oE '#[0-9]+')
{ printf '%s\n' "$OUT"; [ ! -r "$R" ] || grep -E '^[0-9]+\. ' "$R" | grep -oE '#[0-9]+'; } | list

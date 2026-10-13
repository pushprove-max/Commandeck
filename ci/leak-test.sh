#!/usr/bin/env bash
# leak-test.sh [root] -- fail when a file under root (default: this repo)
# matches a pattern in ci/leak-words.txt. Prints file:line:text per match.
# The exempt paths and the two allowed texts are listed in the word list's
# header. When root is a git checkout the files are git's own list (tracked,
# plus untracked and not ignored), so an ignore rule hides no tracked file;
# any other folder is searched whole.
# Exit 0 clean, 1 on a match, 2 when the search itself could not run.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "${1:-$HERE/..}" || exit 2
PAT=$(mktemp) || exit 2; trap 'rm -f "$PAT"' EXIT
grep -v -e '^# ' -e '^#$' -e '^$' "$HERE/leak-words.txt" > "$PAT"
[ -s "$PAT" ] || { echo "leak-test: no pattern in ci/leak-words.txt" >&2; exit 2; }
if [ "$(git rev-parse --show-toplevel 2>/dev/null)" = "$(pwd -P)" ]; then list() { git ls-files -z --cached --others --exclude-standard; }
else list() { rg --files -0 --hidden --no-ignore -g '!/.git'; [ $? -le 1 ]; }; fi   # 1: a folder with no file
LIST=$(mktemp) || exit 2; trap 'rm -f "$PAT" "$LIST"' EXIT
list > "$LIST" || { echo "leak-test: could not list the files" >&2; exit 2; }
FILES=()
while IFS= read -r -d '' f; do
  case $f in CHANGELOG.md|ci/leak-words.txt) continue ;; esac
  [ ! -f "$f" ] || FILES+=("$f")   # a tracked file deleted from the folder has no text to search
done < "$LIST"
[ ${#FILES[@]} -gt 0 ] || exit 0
# The owner's name is allowed in these four, as real files only: a link is searched under what it holds.
NAMED=()
for f in LICENSE NOTICE .claude-plugin/plugin.json .claude-plugin/marketplace.json; do [ -L "$f" ] || NAMED+=("$f"); done
HITS=$(rg --json --text -f "$PAT" -- "${FILES[@]}"); rc=$?   # --text: a NUL byte ends no search
[ "$rc" -le 1 ] || { echo "leak-test: rg failed" >&2; exit 2; }
# Each allowed text is taken out of a matching line, in its exact case, and
# what is left of the line is matched again: whatever else it holds still
# fails. An allowed text counts only with an allowed neighbour on each side
# (the list is in the word list's header); every other neighbour leaves it in
# the line, where it fails. Only the line's text is matched, never the file's
# name, as in the first search. A line that is not UTF-8 is never rebuilt: its
# matches fail as they stand, with nothing taken out.
strip() { jq -r --arg out "$1" --arg address 'pushprove-max/Commandeck' --arg owner 'M''ax Gold''farb' --args '
  "(?<![^\\s\"\u0027`(<\\[/:])" as $before | "(?=$|[\\s\"\u0027`)>\\],;]|\\.(?:\\s|$))" as $after
  | select(.type == "match") | .data as $d | ($d.path.text // "?" | gsub("\n"; "?")) as $p
  | if $out == "where" then "\($p):\($d.line_number)"
    elif ($d.lines.text | type) != "string" then [$d.submatches[].match.text // "?"] | join(" ") | gsub("\n"; " ")
    else $d.lines.text | rtrimstr("\n") | gsub("\n"; " ")
      | gsub($before + $address + "(?:\\.git)?" + $after; " ")
      | if $ARGS.positional | index($p) then gsub($before + $owner + $after; " ") else . end
    end' ${NAMED[@]+"${NAMED[@]}"} <<<"$HITS"; }
mapfile -t WHERE < <(strip where)
TEXT=$(strip text) || { echo "leak-test: could not read rg's matches" >&2; exit 2; }
LEFT=$(rg -n -f "$PAT" <<<"$TEXT"); rc=$?
[ "$rc" -le 1 ] || { echo "leak-test: rg failed" >&2; exit 2; }
[ -n "$LEFT" ] || exit 0
while IFS=: read -r n text; do printf '%s:%s\n' "${WHERE[n - 1]}" "$text"; done <<<"$LEFT"
echo "leak-test: the lines above match ci/leak-words.txt" >&2
exit 1

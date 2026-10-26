#!/usr/bin/env bash
# leak-test.sh [root] -- fail when a file under root (default: this repo)
# matches a pattern in ci/leak-words.txt. Prints file:line:text per match.
# The exempt paths and the two allowed texts are listed in the word list's
# header. When root is a git checkout the files are git's own list (tracked,
# plus untracked and not ignored), so an ignore rule hides no tracked file;
# any other folder is searched whole. A .png's pixels are not searched (an
# owner reviews each new or changed image); its text chunks (tEXt, zTXt, iTXt)
# are, and a match is named as <image>:<line of its chunk text>.
# leak-test.sh --text <file> -- the same search over one file (a commit message, issue 221), no file exempt.
# Exit 0 clean, 1 on a match, 2 when the search itself could not run.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ONE=
if [ "${1:-}" = --text ]; then ONE=${2:-}; [ -f "$ONE" ] || { echo "leak-test: --text needs a file" >&2; exit 2; }
else cd "${1:-$HERE/..}" || exit 2; fi
PAT=$(mktemp) || exit 2; trap 'rm -f "$PAT"' EXIT
grep -v -e '^# ' -e '^#$' -e '^$' "$HERE/leak-words.txt" > "$PAT"
[ -s "$PAT" ] || { echo "leak-test: no pattern in ci/leak-words.txt" >&2; exit 2; }
# A spend figure: a dollar sign before a sum with cents, with comma thousands, or of three or more digits (no shell
# parameter has one: ${10} on needs braces). One or two digits (SHORT) are a spend in text (.md, .txt, .json, the
# changelog, a --text message) and a shell or awk field in code, where strip takes them out.
SPEND='\$[0-9]{1,3}(,[0-9]{3})+(\.[0-9]{2})?\b|\$[0-9]+\.[0-9]{1,2}\b|\$[0-9]{3,}'
SHORT='\$[0-9]{1,2}\b'
printf '%s\n' "$SPEND" "$SHORT" >> "$PAT"
# -ef compares the folders themselves, not their text: a path in other letter case is the same checkout.
if [ "$(git rev-parse --show-toplevel 2>/dev/null)" -ef . ]; then list() { git ls-files -z --cached --others --exclude-standard; }
else list() { rg --files -0 --hidden --no-ignore -g '!/.git'; [ $? -le 1 ]; }; fi   # 1: a folder with no file
LIST=$(mktemp) || exit 2; trap 'rm -f "$PAT" "$LIST"' EXIT
TXT=$(mktemp -d) || exit 2; trap 'rm -rf "$PAT" "$LIST" "$TXT"' EXIT
# png_text <file> -- each text chunk as "<keyword> <text>", decompressed; fails on a file that is not a png.
png_text() { python3 -I -c '
import struct, sys, zlib
d = open(sys.argv[1], "rb").read()
if d[:8] != b"\x89PNG\r\n\x1a\n":
    sys.exit(f"leak-test: {sys.argv[1]} is not a png, so its text cannot be searched")
i = 8
while i + 8 <= len(d):
    n, t = struct.unpack(">I4s", d[i:i + 8]); b = d[i + 8:i + 8 + n]; i += 12 + n
    k, _, v = b.partition(b"\0")
    if t == b"zTXt":
        v = zlib.decompress(v[1:])
    elif t == b"iTXt":  # flag, method, language, translated keyword, text
        *head, v = v[2:].split(b"\0", 2)
        v = b" ".join(head + [zlib.decompress(v) if b[len(k) + 1:len(k) + 2] == b"\1" else v])
    elif t != b"tEXt":
        continue
    sys.stdout.buffer.write(k + b" " + v + b"\n")' "$1"; }
FILES=()
if [ -n "$ONE" ]; then FILES=("$ONE"); : > "$LIST"
else list > "$LIST" || { echo "leak-test: could not list the files" >&2; exit 2; }; fi
while IFS= read -r -d '' f; do
  case $f in ci/leak-words.txt) continue ;; esac
  # Pixels are approved by hand and their compressed bytes spell a pattern by
  # chance: only the text chunks are searched, under the image's own name.
  case $f in *.png)
    [ ! -f "$f" ] || { mkdir -p "$(dirname "$TXT/$f")" && png_text "$f" > "$TXT/$f" && FILES+=("$TXT/$f"); } || exit 2
    continue ;; esac
  [ ! -f "$f" ] || FILES+=("$f")   # a tracked file deleted from the folder has no text to search
done < "$LIST"
[ ${#FILES[@]} -gt 0 ] || exit 0
# The owner's name is allowed in these four, as real files only: a link is searched under what it holds.
NAMED=()
[ -n "$ONE" ] || for f in LICENSE NOTICE .claude-plugin/plugin.json .claude-plugin/marketplace.json; do [ -L "$f" ] || NAMED+=("$f"); done
# Made-up spend figures are allowed in the dashboard's test fixtures, as real files only, and nothing else there is.
FIXTURES=
[ -n "$ONE" ] || for f in hooks/units.test.tsx hooks/units-panes.test.tsx scripts/__tests__/dashboard-view.test.mjs \
  scripts/__tests__/transcript-requests.test.sh scripts/__tests__/dashboard-built-seat-figures.test.sh \
  scripts/__tests__/dashboard-built-seats.test.sh scripts/__tests__/dashboard-built-planning.test.sh; do [ -L "$f" ] || FIXTURES+="$f"$'\n'; done
HITS=$(rg --json --text -f "$PAT" -- "${FILES[@]}"); rc=$?   # --text: a NUL byte ends no search
[ "$rc" -le 1 ] || { echo "leak-test: rg failed" >&2; exit 2; }
# Each allowed text is taken out of a matching line, in its exact case, and
# what is left of the line is matched again: whatever else it holds still
# fails. An allowed text counts only with an allowed neighbour on each side
# (the list is in the word list's header); every other neighbour leaves it in
# the line, where it fails. Only the line's text is matched, never the file's
# name, as in the first search. A line that is not UTF-8 is never rebuilt: its
# matches fail as they stand, with nothing taken out.
strip() { jq -r --arg out "$1" --arg address 'pushprove-max/Commandeck' --arg owner 'M''ax Gold''farb' \
  --arg spend "$SPEND" --arg short "$SHORT" --arg fixtures "$FIXTURES" --arg one "$ONE" --args '
  "(?<![^\\s\"\u0027`(<\\[/:])" as $before | "(?=$|[\\s\"\u0027`)>\\],;]|\\.(?:\\s|$))" as $after
  | select(.type == "match") | .data as $d | ($d.path.text // "?" | gsub("\n"; "?")) as $p
  | if $out == "where" then "\($p):\($d.line_number)"
    elif ($d.lines.text | type) != "string" then [$d.submatches[].match.text // "?"] | join(" ") | gsub("\n"; " ")
    else $d.lines.text | rtrimstr("\n") | gsub("\n"; " ")
      # The changelog is searched for spend figures only: what is left of its line is those figures.
      | if $p == "CHANGELOG.md" then [match($spend + "|" + $short; "g").string] | join(" ") else . end
      # In code, a dollar sign and one or two digits is a field, unless the digits go on into a figure (cents,
      # thousands, a third digit): a field followed by a point and three digits is a field and a fraction.
      | if $one == "" and ($p | test("\\.(md|txt|json)$") | not)
        then gsub("\\$[0-9]{1,2}(?![0-9]|\\.[0-9]{1,2}\\b|,[0-9]{3})"; " ") else . end
      | gsub($before + $address + "(?:\\.git)?" + $after; " ")
      | if $ARGS.positional | index($p) then gsub($before + $owner + $after; " ") else . end
      | if $fixtures | split("\n") | index($p) then gsub($spend; " ") else . end
    end' ${NAMED[@]+"${NAMED[@]}"} <<<"$HITS"; }
mapfile -t WHERE < <(strip where)
WHERE=(${WHERE[@]+"${WHERE[@]#"$TXT/"}"})
TEXT=$(strip text) || { echo "leak-test: could not read rg's matches" >&2; exit 2; }
LEFT=$(rg -n -f "$PAT" <<<"$TEXT"); rc=$?
[ "$rc" -le 1 ] || { echo "leak-test: rg failed" >&2; exit 2; }
[ -n "$LEFT" ] || exit 0
while IFS=: read -r n text; do printf '%s:%s\n' "${WHERE[n - 1]}" "$text"; done <<<"$LEFT"
echo "leak-test: the lines above match ci/leak-words.txt" >&2
rg -q -e "$SHORT" <<<"$LEFT" && echo "leak-test: a dollar sign and one or two digits in text is a spend figure: write \${1} for a shell parameter, or spell the amount out (30 US dollars)" >&2
exit 1

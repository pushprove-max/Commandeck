#!/usr/bin/env bash
# leak-test.sh is the one thing that keeps the source project's names, people
# and issue numbers out of a plugin other people install. Each pattern in
# ci/leak-words.txt must fail the script on a planted file, with the file and
# line named so the author can find it; the exempt paths and the tree as
# committed must pass. Two exact texts are allowed (the repository's address;
# the owner's name in four named files).
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mapfile -t PATTERNS < <(grep -v -e '^# ' -e '^#$' -e '^$' "$REAL/ci/leak-words.txt")
# One sample per pattern, in the file's order, split so this file stays clean.
SAMPLES=('Push''Prove' 'gold''farb' 'M''ax said so' 'Skip''py' 'B''ob' 'Reel''Maker' 'over''test' 'Pri''sm' 'qj4yd''7v1ae' 'see #''1234' 'Dev''in' 'ruling:r-2026''1009-113553-1-5b97a8')
check "every pattern has a sample" "${#PATTERNS[@]}" "${#SAMPLES[@]}"

for i in "${!SAMPLES[@]}"; do
  rm -rf "$TMP/tree"; mkdir -p "$TMP/tree/scripts"
  printf 'a clean line\n%s\n' "${SAMPLES[$i]}" > "$TMP/tree/scripts/planted.sh"
  out=$(bash "$REAL/ci/leak-test.sh" "$TMP/tree" 2>&1); rc=$?
  check "pattern $((i + 1)) (${PATTERNS[$i]:-none}) fails the script" 1 "$rc"
  check "pattern $((i + 1)) names the file and line" 1 "$(grep -c 'scripts/planted.sh:2:' <<<"$out")"
  # The sample must be caught by its own pattern, not by a neighbour's.
  check "pattern $((i + 1)) matches its own sample" 1 "$(rg -c -e "${PATTERNS[$i]:-^\$}" "$TMP/tree/scripts/planted.sh")"
done

rm -rf "$TMP/tree"; mkdir -p "$TMP/tree/.claude/scripts" "$TMP/tree/.githooks" "$TMP/tree/ci" "$TMP/tree/.github"
printf '%s\n' "${SAMPLES[@]}" | tee "$TMP/tree/CHANGELOG.md" > "$TMP/tree/ci/leak-words.txt"
echo clean > "$TMP/tree/README.md"
bash "$REAL/ci/leak-test.sh" "$TMP/tree" >/dev/null 2>&1
check "the changelog and the word list are exempt" 0 "$?"
# A png's compressed bytes spell an issue number by chance; the scanner cannot judge pixels. Its text still can't hide in a .md.
rm -rf "$TMP/tree"; mkdir -p "$TMP/tree/docs/images"
printf '\x89PNG\r\n\x1a\n\x00#''123\x00\n' > "$TMP/tree/docs/images/a.png"
bash "$REAL/ci/leak-test.sh" "$TMP/tree" >/dev/null 2>&1
check "a png whose bytes hold an issue number is skipped" 0 "$?"
printf 'see #''123\n' > "$TMP/tree/docs/a.md"
bash "$REAL/ci/leak-test.sh" "$TMP/tree" >/dev/null 2>&1
check "the same number in a .md beside it still fails" 1 "$?"
# A png's pixels are a human check, but its text chunks are text: names, paths
# or tool output can ride in them unseen. Each kind is searched with the word
# list; the same word in the pixel data alone passes.
# png <chunk type> <text> -- a 1x1 png carrying <text> in one chunk of that type (iTXtz: compressed iTXt).
png() { python3 -I -c '
import struct, sys, zlib
def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
kind, word = sys.argv[1], sys.argv[2].encode()
body = {"tEXt": b"Comment\0" + word, "zTXt": b"Comment\0\0" + zlib.compress(word), "iTXt": b"Comment\0\0\0en\0\0" + word,
        "iTXtz": b"Comment\0\1\0en\0\0" + zlib.compress(word), "IDAT": word}[kind]
sys.stdout.buffer.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 0, 0, 0, 0))
                        + chunk(kind[:4].encode(), body) + chunk(b"IEND", b""))' "$@"; }
for k in tEXt zTXt iTXt iTXtz; do
  rm -rf "$TMP/tree"; mkdir -p "$TMP/tree/docs/images"; png "$k" "see #""1234" > "$TMP/tree/docs/images/a.png"
  out=$(bash "$REAL/ci/leak-test.sh" "$TMP/tree" 2>&1)
  check "a png whose $k chunk holds an issue number fails, naming the image" 1:1 "$?:$(grep -c '^docs/images/a.png:1:' <<<"$out")"
done
rm -rf "$TMP/tree"; mkdir -p "$TMP/tree/docs/images"; png IDAT "see #""1234 ${SAMPLES[0]}" > "$TMP/tree/docs/images/a.png"
bash "$REAL/ci/leak-test.sh" "$TMP/tree" >/dev/null 2>&1
check "the same words in its pixel data alone pass" 0 "$?"
printf 'not a png\n' > "$TMP/tree/docs/images/b.png"
bash "$REAL/ci/leak-test.sh" "$TMP/tree" >/dev/null 2>&1
check "a .png that is not one cannot be searched, and says so" 2 "$?"

leak() { bash "$REAL/ci/leak-test.sh" "$TMP/tree" >/dev/null 2>&1; echo $?; }
fresh() { rm -rf "$TMP/tree"; mkdir -p "$TMP/tree/.claude/briefs" "$TMP/tree/.claude-plugin" "$TMP/tree/scripts/__tests__" "$TMP/tree/sub/.claude-plugin"
  git init -q "$TMP/tree"; echo '.claude/briefs/' > "$TMP/tree/.gitignore"; }
# Two exact texts are allowed and nothing near them: the repository's own
# address anywhere, and the owner's name in the four files that must carry it.
REPO_ID='pushprove-max/Commandeck' OWNER='M''ax Gold''farb'
NAMED=(LICENSE NOTICE .claude-plugin/plugin.json .claude-plugin/marketplace.json)
fresh
printf 'see https://github.com/%s and %s.git\n' "$REPO_ID" "$REPO_ID" | tee "$TMP/tree/README.md" > "$TMP/tree/scripts/x.sh"
for f in "${NAMED[@]}"; do printf 'Copyright 2026 %s\n"repository": "https://github.com/%s"\n' "$OWNER" "$REPO_ID" > "$TMP/tree/$f"; done
check "the repository's address anywhere and the owner's name in the four files pass" 0 "$(leak)"
# planted <case name> <file> <text>: one line in an otherwise allowed tree fails.
planted() { [ ! -e "$TMP/tree/$2" ] || cp "$TMP/tree/$2" "$TMP/keep"; { printf '%s\n' "$3"; cat "$TMP/tree/$2" 2>/dev/null; } > "$TMP/new"; mv "$TMP/new" "$TMP/tree/$2"
  out=$(bash "$REAL/ci/leak-test.sh" "$TMP/tree" 2>&1); check "$1 fails" 1 "$?"; check "$1 names the file" 1 "$(grep -c "^$2:1:" <<<"$out")"
  rm "$TMP/tree/$2"; [ ! -e "$TMP/keep" ] || mv "$TMP/keep" "$TMP/tree/$2"; }
planted "the owner's name in the README" README.md "$OWNER"
planted "the owner's name in a script" scripts/x.sh "$OWNER"
# A checkout entered through a path in other letter case, where the file system
# ignores case, is still a checkout: its ignored files stay out of the search.
fresh; printf '%s\n' "${SAMPLES[0]}" > "$TMP/tree/.claude/briefs/b.md"
if [ -d "$TMP/TREE" ]; then
  bash "$REAL/ci/leak-test.sh" "$TMP/TREE" >/dev/null 2>&1; check "a checkout reached through other letter case skips its ignored files" 0 "$?"
else echo "skip a checkout reached through other letter case: this file system tells case apart"; fi

# #79: the plugin's own checkout runs the plugin, so every runtime file it writes
# there (install-lib.sh's IL_STATE) is ignored, or the scan below reads it.
mapfile -t STATE < <(bash -c '. "$1/scripts/install-lib.sh" >/dev/null 2>&1; printf "%s\n" "${IL_STATE[@]}"' _ "$REAL")
check "install-lib.sh's runtime list was read" 1 "$([ "${#STATE[@]}" -gt 5 ] && echo 1)"
for p in "${STATE[@]}"; do
  case $p in */) p=${p}x.md ;; esac
  check "this repository ignores the runtime file $p" 0 "$(git -C "$REAL" check-ignore -q --no-index -- "$p"; echo $?)"
done

out=$(bash "$REAL/ci/leak-test.sh" 2>&1); rc=$?
check "the tree as committed is clean" 0 "$rc"
[ "$rc" = 0 ] || printf '%s\n' "$out" | head -20

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

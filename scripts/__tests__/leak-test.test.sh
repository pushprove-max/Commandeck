#!/usr/bin/env bash
# leak-test.sh is the one thing that keeps the source project's names, people
# and issue numbers out of a plugin other people install. Each pattern in
# ci/leak-words.txt must fail the script on a planted file, with the file and
# line named so the author can find it; the exempt paths and the tree as
# committed must pass. Two exact texts are allowed (the repository's address;
# the owner's name in four named files) and the briefs folder is not exempt.
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
# The setup copy is gone and its exemption with it: nothing under .claude is exempt.
for f in .claude/scripts/seat.sh .claude/settings.json .githooks/lib.sh; do
  printf '%s\n' "${SAMPLES[0]}" > "$TMP/tree/$f"
  bash "$REAL/ci/leak-test.sh" "$TMP/tree" >/dev/null 2>&1
  check "$f is searched" 1 "$?"
  rm -f "$TMP/tree/$f"
done
# Only the top-level changelog is exempt, and hidden directories are searched.
printf '%s\n' "${SAMPLES[0]}" > "$TMP/tree/.github/CHANGELOG.md"
bash "$REAL/ci/leak-test.sh" "$TMP/tree" >/dev/null 2>&1
check "a hidden directory and a nested changelog are searched" 1 "$?"

# The working papers are not the plugin and are not tracked: git's ignore rule
# keeps a build's own papers out of the search, and a paper somebody tracks
# anyway is searched like any other file.
leak() { bash "$REAL/ci/leak-test.sh" "$TMP/tree" >/dev/null 2>&1; echo $?; }
fresh() { rm -rf "$TMP/tree"; mkdir -p "$TMP/tree/.claude/briefs" "$TMP/tree/.claude-plugin" "$TMP/tree/scripts/__tests__" "$TMP/tree/sub/.claude-plugin"
  git init -q "$TMP/tree"; echo '.claude/briefs/' > "$TMP/tree/.gitignore"; }
fresh
printf '%s\n' "${SAMPLES[0]}" > "$TMP/tree/.claude/briefs/unit-evidence.md"
check "an untracked paper in the ignored briefs folder is not searched" 0 "$(leak)"
git -C "$TMP/tree" add -f .claude/briefs/unit-evidence.md
check "a tracked paper in the briefs folder is searched like any other file" 1 "$(leak)"
fresh; rm "$TMP/tree/.gitignore"
printf '%s\n' "${SAMPLES[0]}" > "$TMP/tree/.claude/briefs/unit-evidence.md"
check "without the ignore rule the briefs folder is searched" 1 "$(leak)"

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
planted "another repository of the same owner" README.md "${REPO_ID%/*}/Other"
planted "the owner's account alone" README.md "${REPO_ID%/*}"
planted "the product name alone" README.md "${REPO_ID%%-*}"
# The table (main's ruling 3): an allowed text counts only with an allowed neighbour on each side. Before it: the
# line's start, a space, a quote, ( < [ / or :. After it (and after the address's own closing .git): the line's
# end, a space, a quote, ) > ] , ; or a full stop that ends the line or stands before a space. Every other
# neighbour fails, so a variant nobody thought of fails too.
Q="'"
for after in .private -private ..private .git..private .gitlab .git.private /issues /../Other :x @x '?q' '#frag' %2e '~' + '\' _x 2 é '."' .git/x '=x' '|x' '&x'; do
  planted "the address followed by [$after]" README.md "see $REPO_ID$after"
done
for before in x - . _ = @ '\' é '|' '&' '%2f' '~' '+' ','; do
  planted "the address after [$before]" README.md "see $before$REPO_ID"
done
for after in -Smith 2 _x .x x é /x :x @x '=x'; do planted "the owner's name followed by [$after]" LICENSE "by $OWNER$after"; done
for before in x - . _ = 2 é @; do planted "the owner's name after [$before]" LICENSE "by $before$OWNER"; done
# The forms that must pass, each alone on a line.
for form in "$REPO_ID" "$REPO_ID.git" "\"$REPO_ID\"" "$Q$REPO_ID$Q" "\`$REPO_ID\`" "($REPO_ID)" "[$REPO_ID]" "<$REPO_ID>" "Install from $REPO_ID." \
    "It is $REPO_ID. Then run setup." "https://github.com/$REPO_ID" "git@github.com:$REPO_ID.git" "\"https://github.com/$REPO_ID.git\"," "$REPO_ID; $REPO_ID, $REPO_ID" "	$REPO_ID	"; do
  printf '%s\n' "$form" > "$TMP/tree/scripts/form.txt"
  check "the address passes as [$form]" 0 "$(leak)"
done
rm "$TMP/tree/scripts/form.txt"
for form in "$OWNER" "Copyright 2026 $OWNER" "\"name\": \"$OWNER\" }" "($OWNER)" "[$OWNER]" "<$OWNER>" "$Q$OWNER$Q" "By $OWNER." "By $OWNER, 2026; $OWNER"; do
  printf '%s\n' "$form" > "$TMP/tree/NOTICE.new"; cat "$TMP/tree/NOTICE" >> "$TMP/tree/NOTICE.new"; cp "$TMP/tree/NOTICE" "$TMP/keep"; mv "$TMP/tree/NOTICE.new" "$TMP/tree/NOTICE"
  check "the owner's name passes in NOTICE as [$form]" 0 "$(leak)"
  mv "$TMP/keep" "$TMP/tree/NOTICE"
done
# A line that is not text is never rebuilt from its matches: it fails as it stands.
planted "the two names apart on a line that is not UTF-8, in an allowed file" LICENSE "${OWNER% *} wrote this; ${OWNER#* }"$'\xff'
planted "the allowed address on a line that is not UTF-8" README.md "$REPO_ID"$'\xff'
planted "the address glued to a word before it" README.md "x$REPO_ID"
planted "the address in another case" README.md "${REPO_ID^^}"
planted "the owner's name in the README" README.md "$OWNER"
planted "the owner's name in a script" scripts/x.sh "$OWNER"
planted "the owner's name in a test" scripts/__tests__/x.test.sh "$OWNER"
planted "the owner's name in a file named like an allowed one" LICENSE.md "$OWNER"
planted "the owner's name in an allowed name one folder down" sub/LICENSE "$OWNER"
planted "the owner's name in a manifest one folder down" sub/.claude-plugin/plugin.json "$OWNER"
for f in "${NAMED[@]}"; do
  planted "the first name alone in $f" "$f" "${OWNER% *} wrote it"
  planted "the family name alone in $f" "$f" "${OWNER#* }"
  planted "the owner's name in another case in $f" "$f" "${OWNER,,}"
done
check "the allowed tree is still clean after the planted lines" 0 "$(leak)"
# Only a line's text is matched, with or without an allowed text on it: a file's name never is.
echo "see $REPO_ID" > "$TMP/tree/scripts/${OWNER% *}.sh"
check "a file named with a leak word and holding only the address passes, like any other name" 0 "$(leak)"
rm "$TMP/tree/scripts/${OWNER% *}.sh"
# A NUL byte makes a file binary to ripgrep, which would stop reading it there.
printf 'clean\0\nby %s\n' "${OWNER#* }" > "$TMP/tree/scripts/blob.sh"
out=$(bash "$REAL/ci/leak-test.sh" "$TMP/tree" 2>&1)
check "a leak word after a NUL byte is found" 1 "$(grep -c '^scripts/blob.sh:2:' <<<"$out")"
rm "$TMP/tree/scripts/blob.sh"
# A link under an allowed name is not that file: what it points at is searched without the exception.
printf 'by %s\n' "$OWNER" > "$TMP/tree/elsewhere"; rm "$TMP/tree/NOTICE"; ln -s elsewhere "$TMP/tree/NOTICE"
out=$(bash "$REAL/ci/leak-test.sh" "$TMP/tree" 2>&1)
check "a link named NOTICE gets no exception" 1 "$(grep -c '^NOTICE:1:' <<<"$out")"

out=$(bash "$REAL/ci/leak-test.sh" 2>&1); rc=$?
check "the tree as committed is clean" 0 "$rc"
[ "$rc" = 0 ] || printf '%s\n' "$out" | head -20

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

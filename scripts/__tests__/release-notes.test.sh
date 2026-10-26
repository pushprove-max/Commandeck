#!/usr/bin/env bash
# covers: scripts/release-decide.sh scripts/release-backfill.sh .github/workflows/release.yml CHANGELOG.md scripts/release-rewrite.sh
# release-notes.test.sh -- issue 348: a release is cut from one decision. What this pins: release-notes.sh prints a
# version's CHANGELOG section (what update.sh shows) and fails on a missing one, and refuses a line that names a file,
# a script, a path, an issue or a commit; release-decide.sh says
# `release v<version>` only when plugin.json's version changed and its tag is free; the workflow runs no step after
# the decision without it; the backfill plan lists every version oldest first and tags and publishes nothing.
# Scratch repositories only: nothing here tags, pushes or publishes.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
g() { git -C "$T/r" -c user.name=t -c user.email=t@t "$@"; }
# A gh that records its calls: the backfill plan must not reach it.
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "gh $*" >> "%s/calls"\n' "$T" > "$T/bin/gh"; chmod +x "$T/bin/gh"
setv() { mkdir -p "$T/r/.claude-plugin"; echo "{\"name\": \"p\", \"version\": \"$1\"}" > "$T/r/.claude-plugin/plugin.json"; g add -A; g commit -q -m "v$1"; }
# The decision's gh: `gh release view` exits $VIEW (0: the release exists; else it does not).
mkdir -p "$T/dbin"; printf '#!/bin/sh\nexit "${VIEW:-1}"\n' > "$T/dbin/gh"; chmod +x "$T/dbin/gh"
decide() { (cd "$T/r" && PATH="$T/dbin:$PATH" bash "$REAL/scripts/release-decide.sh" "$1" "$2" 2>&1); }
# step <name> -- the run: of the workflow step with that name, one line or a | block.
step() { awk -v n="$1" '/^      - / { s = 0; r = 0 } $0 == "      - name: " n || $0 == "        name: " n { s = 1 }
  s && r { if (/^          /) { print substr($0, 11); next } r = 0 } s && /^        run: \|$/ { r = 1; next }
  s && /^        run: / { print substr($0, 14) }' "$REAL/.github/workflows/release.yml"; }

# release-notes.sh: the newest section, without its heading and its leading blank lines, is the text update.sh shows
# and the body of a release; its ### topics come out as ##. The real CHANGELOG's own style is checked last (T12).
NEW=$(sed -n 's/^## \([^ ]*\) .*/\1/p' "$REAL/CHANGELOG.md" | head -1)
check "release-notes prints the newest version's section without its heading, the text update.sh shows" \
  "$(awk '/^## [0-9]+\.[0-9]+\.[0-9]+ -- / { n++; next } n == 1 && (NF || s) { s = 1; print }' "$REAL/CHANGELOG.md" | sed 's/^###\([[:space:]]\)/##\1/')" \
  "$(bash "$REAL/scripts/release-notes.sh" "$NEW" 2>/dev/null)"
bash "$REAL/scripts/release-notes.sh" 0.0.0-none >"$T/out" 2>&1; RC=$?
check "a version with no section exits 1 and says so" "1 1" "$RC $(grep -c 'release-notes: .*0.0.0-none' "$T/out")"

# The style guard, on a fixture tree: copies of the scripts under test beside a CHANGELOG.md written by cl.
P=$T/p; mkdir -p "$P/scripts"; cp "$REAL/scripts/release-notes.sh" "$P/scripts/"
cl() { cat > "$P/CHANGELOG.md"; }
rn() { bash "$P/scripts/release-notes.sh" "$@" 2>"$T/err"; }
# sec <line>... -- a CHANGELOG whose 1.1.0 section holds one ### topic and the lines given, the first of them on line 7.
sec() { { printf '# Changelog\n\n## 1.1.0 -- 2026-10-02\n\n### Joining a room\n\n'; printf '%s\n' "$@"; printf '\n## 1.0.0 -- 2026-10-01\n\n### Start\n\n- Hello.\n'; } | cl; }
# runsec -- run 1.1.0 and say "<exit code>|<each refusal as file:line reason>".
runsec() { rn 1.1.0 >/dev/null; echo "$?|$(sed -E 's/^release-notes: ([^:]*:[0-9]+): ([^:]*): .*/\1 \2/' "$T/err" | paste -sd'|' -)"; }

cl <<'EOF'
# Changelog

## 1.1.0 -- 2026-10-02

### What you need to do

- Run the update.

## Notes

### Security and maintenance

- Closed a hole.

## 1.0.0 -- 2026-10-01

### Start

- Hello.
EOF
check "the extractor keeps every topic of a version, up to the next version heading" "## What you need to do

- Run the update.

## Notes

## Security and maintenance

- Closed a hole." "$(rn 1.1.0)"

sec '#### Odd' '- Fine.'
check "a #### heading in a CHANGELOG section is refused, naming its line" "2|CHANGELOG.md:7 heading deeper than ###|release body:3 heading deeper than ## in a release body" "$(runsec)"
BODY=$(rn 1.1.0)
check "and the body still prints, with the refused text on stderr" "1 1" "$(grep -c '^#### Odd$' <<<"$BODY") $(grep -c '^release-notes: CHANGELOG.md:7: .*: #### Odd$' "$T/err")"
sec '- Fine.'
check "a ### topic in the CHANGELOG passes and comes out as ## in the release body" "0||## Joining a room" "$(runsec)|$(rn 1.1.0 | head -1)"

sec 'Run `scripts/x` to start.' 'Open `/usr/local/bin` or `~/.claude`.' 'Then `/units band on` and `/plugin marketplace add owner/repo` are fine.'
check "a backticked path is refused, naming its line" "2|CHANGELOG.md:7 path in backticks|CHANGELOG.md:8 path in backticks" "$(runsec)"
sec 'See release-notes.sh and `scripts/x.sh`.' 'Edit config.json, then README.md.' 'It works in 0.48.0 on github.com.'
check "a file or script name is refused, naming its line" "2|CHANGELOG.md:7 file or script name|CHANGELOG.md:7 path in backticks|CHANGELOG.md:8 file or script name" "$(runsec)"
sec 'Edit ~/.claude/settings by hand.' 'Open a/b/c now.' 'Look in /usr/local/bin for it.' 'Use /units and read/write.'
check "an absolute or three-part path is refused, naming its line" "2|CHANGELOG.md:7 path|CHANGELOG.md:8 path|CHANGELOG.md:9 path" "$(runsec)"
sec 'The fooBar() call is gone.' 'The fooBar setting stays.'
check "a function name is refused, naming its line" "2|CHANGELOG.md:7 function name" "$(runsec)"
sec 'Fixed a crash (#12).' 'Closes 12.' 'Refs 12.' 'The pane now closes and refs stay.'
check "an issue reference is refused, naming its line" "2|CHANGELOG.md:7 issue reference|CHANGELOG.md:8 issue reference|CHANGELOG.md:9 issue reference" "$(runsec)"
sec 'Fixed in 1a2b3c4d.' 'Not a hash: 1234567, defaced, 2026-10-26.'
check "a commit hash is refused, naming its line" "2|CHANGELOG.md:7 commit hash" "$(runsec)"
sec '- Run `/units band on` to show the band; `/units` lists the units.' \
  '- Set `testCommand` or `maxRounds`; `worker_done` ends a turn.' \
  '- You can read/write the file; the pane now closes on its own, in 0.48.0 and later.' \
  '- The count is 1234567, and setup asks "Which agent reviews?".' \
  '- Run `/plugin marketplace add owner/repo` once.'
check "a clean section with a slash command, setting names and plain words passes" "0|" "$(runsec)"
check "and prints nothing on stderr" "" "$(cat "$T/err")"

# The Notes step of the release workflow runs the extractor, so a refused section fails the job before any tag.
sec '- Clean.'; (cd "$P" && DECISION="release v1.1.0" RUNNER_TEMP="$T" bash -e -c "$(step Notes)") >/dev/null 2>&1; CLEAN=$?
sec '- See notes.md.'; (cd "$P" && DECISION="release v1.1.0" RUNNER_TEMP="$T" bash -e -c "$(step Notes)") >/dev/null 2>&1
check "the release Notes step fails on a section the guard refuses" "0 2" "$CLEAN $?"
check "its covers line names CHANGELOG.md, so a changelog change alone runs this file" 1 "$(sed -n 2p "$REAL/scripts/__tests__/release-notes.test.sh" | grep -c -w 'CHANGELOG.md')"

git init -q -b main "$T/r"
setv 1.0.0; A=$(g rev-parse HEAD)
echo x > "$T/r/f"; g add -A; g commit -q -m work; B=$(g rev-parse HEAD)
check "an unchanged version decides skip" "skip: version 1.0.0 did not change" "$(decide "$A" "$B")"
setv 1.1.0; C=$(g rev-parse HEAD)
check "a changed version with a free tag decides release" "release v1.1.0" "$(decide "$B" "$C")"
g tag v1.1.0
check "a changed version whose tag and release exist decides skip" "skip: release v1.1.0 exists" "$(VIEW=0 decide "$B" "$C")"
# The Tag step pushed the tag, then Publish failed: a rerun finds the tag but no release, and publishes again.
check "a tag pushed by a run whose publish failed decides release again" "release v1.1.0" "$(VIEW=1 decide "$B" "$C")"
# And that rerun's Tag step finds its tag and goes on to Publish, pushing nothing.
git init -q --bare "$T/origin.git"; g remote add origin "$T/origin.git"
(cd "$T/r" && DECISION="release v1.1.0" GITHUB_SHA=$C bash -e -c "$(step Tag)") >/dev/null 2>&1
check "a rerun's Tag step with its tag already there exits 0 and pushes nothing" "0 0" "$? $(git -C "$T/origin.git" tag | wc -l | tr -d ' ')"
check "a first push (no before) releases the version when its tag is free" "release v1.2.0" \
  "$(g tag -d v1.1.0 >/dev/null; setv 1.2.0; decide 0000000000000000000000000000000000000000 "$(g rev-parse HEAD)")"
rm "$T/r/.claude-plugin/plugin.json"; g add -A; g commit -q -m gone
decide "$C" "$(g rev-parse HEAD)" >/dev/null; check "a version that cannot be read exits 1" 1 "$?"
# GitHub runs a step as bash -e: the Decide step must fail with the script, never write an empty decision and pass.
: > "$T/gh-out"
(cd "$T/r" && PATH="$T/dbin:$PATH" GITHUB_OUTPUT="$T/gh-out" GITHUB_SHA=$(g rev-parse HEAD) bash -e -c "$(step Decide | sed "s/\${{ github.event.before }}/$C/; s#bash scripts/#bash $REAL/scripts/#")") >/dev/null 2>&1
check "a Decide step whose version cannot be read fails, writing no decision" "1 0" "$? $(grep -c '^decision=' "$T/gh-out")"

# The workflow: the step that decides, and no later step that runs without its output.
WF=$REAL/.github/workflows/release.yml
check "the workflow gates every step after release-decide on its output starting release" "ok" "$(awk '
  /^      - /      { n++; seen = 0 }
  /release-decide/ { d = n }
  /^        if: .*startsWith\(steps\.decide\.outputs\.decision, .release .\)/ { seen = 1; ok[n] = 1 }
  END { bad = 0; for (i = d + 1; i <= n; i++) if (!ok[i]) bad++; print (d > 0 && bad == 0 && n > d) ? "ok" : "bad " bad }' "$WF" 2>&1)"
check "the workflow runs on a push to main with contents: write" "1 1" \
  "$(grep -c '^    branches: \[main\]' "$WF") $(grep -c '^  contents: write' "$WF")"

# The backfill plan: every version once, oldest first, and nothing created.
git init -q -b main "$T/b"; g() { git -C "$T/b" -c user.name=t -c user.email=t@t "$@"; }
for v in 0.1.0 0.2.0 0.2.1; do mkdir -p "$T/b/.claude-plugin"; echo "{\"version\": \"$v\"}" > "$T/b/.claude-plugin/plugin.json"; echo "$v" > "$T/b/n"; g add -A; g commit -q -m "v$v"; done
echo more > "$T/b/n"; g add -A; g commit -q -m "no version change"
OUT=$(cd "$T/b" && PATH="$T/bin:$PATH" bash "$REAL/scripts/release-backfill.sh" --plan 2>&1)
check "backfill --plan lists every version oldest first and creates nothing" "v0.1.0 v0.2.0 v0.2.1|tags 0|gh 0" \
  "$(awk '{ printf "%s%s", s, $1; s = " " }' <<<"$OUT")|tags $(g tag | wc -l | tr -d ' ')|gh $(cat "$T/calls" 2>/dev/null | wc -l | tr -d ' ')"
# An earlier backfill made v0.1.0 here and its push failed: the rerun pushes it, so `--verify-tag` finds it remotely.
git init -q --bare "$T/b-origin.git"; g remote add origin "$T/b-origin.git"; g tag v0.1.0 "$(g rev-list --max-parents=0 HEAD)"
mkdir -p "$T/bbin"; printf '#!/bin/sh\ncase "$1 $2" in\n  "release view") exit 1 ;;\n  "release create") git ls-remote --exit-code --tags origin "refs/tags/$3" >/dev/null || exit 17; echo "$3" >> "%s/created" ;;\nesac\n' "$T" > "$T/bbin/gh"; chmod +x "$T/bbin/gh"
# The fixture holds its own copies of the scripts and a clean CHANGELOG with no 0.2.1 section (the "Version <x>." fallback).
mkdir -p "$T/b/scripts"; cp "$REAL/scripts/release-notes.sh" "$REAL/scripts/release-backfill.sh" "$T/b/scripts/"
printf '# Changelog\n\n## 0.2.0 -- 2026-10-02\n\n### Joining a room\n\n- Fine.\n\n## 0.1.0 -- 2026-10-01\n\n### Start\n\n- Hello.\n' > "$T/b/CHANGELOG.md"
(cd "$T/b" && PATH="$T/bbin:$PATH" bash scripts/release-backfill.sh) >/dev/null 2>&1
check "a local tag whose push failed is pushed by the rerun before the release is made" "0|v0.1.0 v0.2.0 v0.2.1|v0.1.0 v0.2.0 v0.2.1" \
  "$?|$(git -C "$T/b-origin.git" tag | paste -sd' ' -)|$(paste -sd' ' - < "$T/created" 2>/dev/null)"

# A refused section is never published, not even as the "Version <x>." fallback: the backfill checks every body before
# it tags, pushes or calls gh.
BF=$T/bf; git init -q -b main "$BF"; mkdir -p "$BF/scripts" "$BF/.claude-plugin"
cp "$REAL/scripts/release-notes.sh" "$REAL/scripts/release-backfill.sh" "$BF/scripts/"
bg() { git -C "$BF" -c user.name=t -c user.email=t@t "$@"; }
for v in 1.0.0 1.1.0; do echo "{\"version\": \"$v\"}" > "$BF/.claude-plugin/plugin.json"; bg add -A; bg commit -q -m "v$v"; done
printf '# Changelog\n\n## 1.1.0 -- 2026-10-02\n\n### Joining a room\n\n#### Odd\n\n## 1.0.0 -- 2026-10-01\n\n### Start\n\n- Hello.\n' > "$BF/CHANGELOG.md"
git init -q --bare "$T/bf-origin.git"; bg remote add origin "$T/bf-origin.git"
mkdir -p "$T/bfbin"; printf '#!/bin/sh\necho "gh $*" >> "%s/bf-calls"\n' "$T" > "$T/bfbin/gh"; chmod +x "$T/bfbin/gh"
ERR=$(cd "$BF" && PATH="$T/bfbin:$PATH" bash scripts/release-backfill.sh 2>&1 >/dev/null); RC=$?
check "a backfill over a refused section publishes nothing, naming the version and line" \
  "1|release-backfill: v1.1.0: CHANGELOG.md:7|release-backfill: v1.1.0: release body:3|0|0|0" \
  "$RC|$(sed -E 's/^(release-backfill: v[^:]*: [^:]*:[0-9]+): .*/\1/' <<<"$ERR" | paste -sd'|' -)|$(cat "$T/bf-calls" 2>/dev/null | wc -l | tr -d ' ')|$(bg tag | wc -l | tr -d ' ')|$(git -C "$T/bf-origin.git" tag | wc -l | tr -d ' ')"

# Only a version with no section at all gets "Version <x>." (AF1). A section that exists with no notes, or a CHANGELOG
# that cannot be read, is a failure of the extraction, not an absence: the backfill stops before any tag, push or gh call.
bf_state() { echo "$1|$(cat "$T/bf-calls" 2>/dev/null | wc -l | tr -d ' ')|$(bg tag | wc -l | tr -d ' ')|$(git -C "$T/bf-origin.git" tag | wc -l | tr -d ' ')"; }
printf '# Changelog\n\n## 1.1.0 -- 2026-10-02\n\n\n## 1.0.0 -- 2026-10-01\n\n### Start\n\n- Hello.\n' > "$BF/CHANGELOG.md"
ERR=$(cd "$BF" && PATH="$T/bfbin:$PATH" bash scripts/release-backfill.sh 2>&1 >/dev/null); RC=$?
check "a backfill over an existing section with no notes publishes nothing and fails" "1|0|0|0" "$(bf_state "$RC")"
check "a backfill over an existing section with no notes names the version" "1" "$(grep -c '^release-backfill: v1.1.0: .*no notes' <<<"$ERR")"
rm -f "$BF/CHANGELOG.md"
ERR=$(cd "$BF" && PATH="$T/bfbin:$PATH" bash scripts/release-backfill.sh 2>&1 >/dev/null); RC=$?
check "a backfill whose CHANGELOG cannot be read publishes nothing and fails" "1|0|0|0" "$(bf_state "$RC")"
# The same two states through the extractor: absence stays exit 1; no notes and unreadable are another status.
cl <<'EOF'
# Changelog

## 1.1.0 -- 2026-10-02


## 1.0.0 -- 2026-10-01

### Start

- Hello.
EOF
rn 1.1.0 >/dev/null; RC_EMPTY=$?; rn 9.9.9 >/dev/null; RC_NONE=$?
check "release-notes: a missing section is exit 1, a section with no notes is exit 3" "3|1" "$RC_EMPTY|$RC_NONE"

# Every writer of a release body is one of the three the Data design names: main's release-rewrite.sh, the release
# workflow (a new version) and release-backfill.sh (a version with no release). A fourth is added there first.
check "release bodies are written by release-backfill.sh, release-rewrite.sh and the release workflow only" \
  ".github/workflows/release.yml scripts/release-backfill.sh scripts/release-rewrite.sh" \
  "$(cd "$REAL" && grep -rlE 'gh release (create|edit)' .github scripts --include='*.sh' --include='*.yml' --exclude-dir=__tests__ | sort | paste -sd' ' -)"


# release-rewrite.sh, on the fixture tree $P (now a repository whose origin is a GitHub URL) with a gh that records each
# call as "GH_REPO=<value or unset> <args>", answers `release list` from $GD/list, and keeps each `release edit` with its stdin.
git init -q -b main "$P"; git -C "$P" remote add origin https://github.com/owner/name.git
cp "$REAL/scripts/release-rewrite.sh" "$P/scripts/"
GD=$T/gd; mkdir -p "$GD" "$T/rbin"
cat > "$T/rbin/gh" <<'GH'
#!/bin/sh
echo "GH_REPO=${GH_REPO-unset} $*" >> "$GD/calls"
case "$1 $2" in
  "release list") cat "$GD/list" ;;
  "release edit") { echo "== $3"; cat; } >> "$GD/edits"
    [ -z "${GH_MUTATE-}" ] || [ -e "$GD/mutated" ] || { : > "$GD/mutated"; sed 's/Hello\./Changed./' "$GH_MUTATE" > "$GH_MUTATE.new" && mv "$GH_MUTATE.new" "$GH_MUTATE"; }
    [ "$3" != "${GH_FAIL-}" ] ;;
esac
GH
chmod +x "$T/rbin/gh"
# rw <tag>... -- run the rewrite against a release list of those tags; $GD is cleared first.
rw() { rm -f "$GD/calls" "$GD/edits" "$GD/mutated"; : > "$GD/calls"; : > "$GD/edits"
  printf '[%s]' "$(printf '{"tagName":"%s"},' "$@" | sed 's/,$//')" > "$GD/list"
  (cd "$P" && PATH="$T/rbin:$PATH" GD="$GD" bash scripts/release-rewrite.sh $RWARGS 2>"$T/rwerr"); }
editcount() { grep -c ' release edit ' "$GD/calls"; }
printf '# Changelog\n\n## 1.1.0 -- 2026-10-02\n\n### Joining a room\n\n- Rooms open faster.\n\n## 1.0.0 -- 2026-10-01\n\n### Start\n\n- Hello.\n' > "$P/CHANGELOG.md"
RWARGS=; rw v1.1.0 v1.0.0 >/dev/null; RC=$?
check "release-rewrite edits every published release's body to its section" "0|== v1.1.0
## Joining a room

- Rooms open faster.
== v1.0.0
## Start

- Hello." "$RC|$(cat "$GD/edits")"
printf '# Changelog\n\n## 1.0.0 -- 2026-10-01\n\n### Start\n\n- Hello.\n' > "$P/CHANGELOG.md"
rw v1.0.0 v9.9.9 >/dev/null; RC=$?
check "a release with no CHANGELOG section stops the rewrite before any edit, naming it" "1|1|0" "$RC|$(grep -c '^release-rewrite: v9.9.9: ' "$T/rwerr")|$(editcount)"
printf '# Changelog\n\n## 1.1.0 -- 2026-10-02\n\n### Joining a room\n\n#### Odd\n\n## 1.0.0 -- 2026-10-01\n\n### Start\n\n- Hello.\n' > "$P/CHANGELOG.md"
rw v1.1.0 v1.0.0 >/dev/null; RC=$?
check "a release whose section the guard refuses stops the rewrite before any edit, naming its line" "1|1|0" "$RC|$(grep -c '^release-rewrite: v1.1.0: CHANGELOG.md:7: ' "$T/rwerr")|$(editcount)"
printf '# Changelog\n\n## 1.1.0 -- 2026-10-02\n\n### Joining a room\n\n- Rooms open faster.\n\n## 1.0.0 -- 2026-10-01\n\n### Start\n\n- Hello.\n' > "$P/CHANGELOG.md"
RWARGS=--plan; OUT=$(rw v1.1.0 v1.0.0); RC=$?
check "release-rewrite --plan lists each release and edits nothing" "0|v1.1.0 3 v1.0.0 3|0" "$RC|$(paste -sd' ' - <<<"$OUT")|$(editcount)"
RWARGS=; GH_FAIL=v1.0.0 rw v1.1.0 v1.0.0 >/dev/null; RC=$?
check "an edit that fails stops the rewrite there, exit 1, naming the release" "1|1|1" "$RC|$(grep -c '^release-rewrite: v1.0.0: ' "$T/rwerr")|$(grep -c '^== v1.1.0$' "$GD/edits")"
GH_REPO=another/repo rw v1.1.0 v1.0.0 >/dev/null
check "with GH_REPO set to another repository, every gh call names this checkout's repository" "3 3 3" \
  "$(grep -c '^GH_REPO=unset ' "$GD/calls") $(grep -c -- '--repo owner/name' "$GD/calls") $(wc -l < "$GD/calls" | tr -d ' ')"
for u in another/repo https://example.com/x.git https://github.com/owner/name/extra.git; do
  git -C "$P" remote set-url origin "$u"; rw v1.1.0 >/dev/null; RC=$?
  check "an origin that is not a GitHub repository stops the rewrite before any gh call ($u)" "1|1|0" "$RC|$(grep -c -F "$u" "$T/rwerr")|$(wc -l < "$GD/calls" | tr -d ' ')"
done
git -C "$P" remote set-url origin https://github.com/owner/name.git
# The first edit changes the CHANGELOG under the run: the second edit still gets the body pass 1 kept.
GH_MUTATE=$P/CHANGELOG.md rw v1.1.0 v1.0.0 >/dev/null
check "a CHANGELOG changed between the passes publishes the pass-1 bodies" "## Start

- Hello." "$(sed -n '/^== v1.0.0$/,$p' "$GD/edits" | sed 1d)"
# The real CHANGELOG, last: every section is in the style, and opens with a topic, "What you need to do" first.
OUT=$(bash "$REAL/scripts/release-notes.sh" --check 2>&1); RC=$?
check "the whole CHANGELOG passes the style guard" "0|" "$RC|$OUT"
check "every version section opens with a ### topic, and What you need to do comes first when there is one" "" "$(awk '
  /^## [0-9]+\.[0-9]+\.[0-9]+ -- / { v = $2; first = 1; next }
  v && first && NF { first = 0; if ($0 !~ /^### /) print v " opens with text, not a topic" }
  v && /^### / { n[v]++; if ($0 == "### What you need to do" && n[v] > 1) print v " lists What you need to do after another topic" }' "$REAL/CHANGELOG.md")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

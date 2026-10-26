#!/usr/bin/env bash
# covers: scripts/release-decide.sh scripts/release-backfill.sh .github/workflows/release.yml
# release-notes.test.sh -- issue 348: a release is cut from one decision. What this pins: release-notes.sh prints a
# version's CHANGELOG section (what update.sh shows) and fails on a missing one; release-decide.sh says
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

# release-notes.sh: the newest section is the text update.sh printed before it called this.
NEW=$(sed -n 's/^## \([^ ]*\) .*/\1/p' "$REAL/CHANGELOG.md" | head -1)
check "release-notes prints the newest version's section, the text update.sh shows" \
  "$(awk '/^## / { n++ } n == 1' "$REAL/CHANGELOG.md")" "$(bash "$REAL/scripts/release-notes.sh" "$NEW")"
bash "$REAL/scripts/release-notes.sh" 0.0.0-none >"$T/out" 2>&1; RC=$?
check "a version with no section exits 1 and says so" "1 1" "$RC $(grep -c 'release-notes: .*0.0.0-none' "$T/out")"

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
(cd "$T/b" && PATH="$T/bbin:$PATH" bash "$REAL/scripts/release-backfill.sh") >/dev/null 2>&1
check "a local tag whose push failed is pushed by the rerun before the release is made" "0|v0.1.0 v0.2.0 v0.2.1|v0.1.0 v0.2.0 v0.2.1" \
  "$?|$(git -C "$T/b-origin.git" tag | paste -sd' ' -)|$(paste -sd' ' - < "$T/created" 2>/dev/null)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

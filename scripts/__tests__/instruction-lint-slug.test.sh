#!/usr/bin/env bash
# instruction-lint-slug.test.sh -- Claude Code names a project's memory folder
# by its path with every character that is not a letter or a digit a dash.
# What this pins: a project whose path holds a dot or an underscore still has
# its memory files checked; with only the slashes replaced the folder was not
# found and the checks were skipped without a word.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

P=$T/my_proj.v2
git init -q -b main "$P" && git -C "$P" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
M=$T/home/.claude/projects/$(printf '%s' "$P" | tr -c 'A-Za-z0-9' -)/memory
mkdir -p "$M"; : > "$M/MEMORY.md"; printf -- '---\nname: stray\ndescription: a stray\n---\nbody\n' > "$M/stray.md"
OUT=$(HOME=$T/home python3 "$ROOT/scripts/instruction-lint.py" --repo "$P" 2>&1)
check "the memory folder is found and its orphan flagged" 1 "$(grep -c 'orphan-memory' <<<"$OUT")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

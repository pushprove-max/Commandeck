#!/usr/bin/env bash
# rules-audit.sh is the deterministic rules check (instruction-lint.py): a template, brief, doc or hook that names a
# retired script, an option the plugin no longer has, or a file that is gone is a rule that misleads the next agent
# that reads it. Each case runs the audit on a hand-built project tree (no setup, no doctor), so it runs in seconds.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
R=$T/proj; mkdir -p "$R/templates" "$R/.claude/briefs" "$R/docs" "$R/hooks" "$T/mem"; git init -q -b main "$R"
audit() { bash "$REAL/scripts/rules-audit.sh" --repo "$R" --memory-dir "$T/mem" --global "$T/no-global.md" 2>&1; }
RULE='rule: docs/commands.md#rules-audit'

OUT=$(audit); RC=$?
check "on a clean scratch tree it exits 0 and prints nothing" "0:" "$RC:$OUT"

# A retired name is flagged wherever a rule lives, with file:line and what replaced it.
for f in templates/a.md .claude/briefs/b.md docs/c.md hooks/d.sh; do printf 'ok\nrun --no-ponytail here\n' > "$R/$f"; done
OUT=$(audit); RC=$?
check "a retired name in templates/a.md, .claude/briefs/b.md, docs/c.md and hooks/d.sh is flagged in each, with file:line" \
  ".claude/briefs/b.md:2 docs/c.md:2 hooks/d.sh:2 templates/a.md:2 " \
  "$(grep 'retired-name --no-ponytail' <<<"$OUT" | cut -d' ' -f1 | sort | tr '\n' ' ')"
check "and it exits 1" 1 "$RC"
check "a retired name says what replaced it, then the rule pointer" \
  "docs/c.md:2 retired-name --no-ponytail, now: --ponytail off|lite|full|ultra $RULE" "$(grep '^docs/c.md' <<<"$OUT")"
rm -f "$R"/templates/a.md "$R"/.claude/briefs/b.md "$R"/docs/c.md "$R"/hooks/d.sh

# The size kinds stay on the always-loaded files: a long doc is a doc.
for i in $(seq 300); do echo "line $i"; done > "$R/docs/c.md"
check "a 300-line docs/c.md is not flagged over-200-lines" 0 "$(audit | grep -c over-200-lines)"
rm -f "$R/docs/c.md"

# An option key a template names must be one the plugin has.
printf 'setup.sh --option wakeKindz=worker_done\nsetup.sh --option wakeKinds=worker_done\n' > "$R/templates/a.md"
check "a template naming --option wakeKindz= is flagged unknown-option with file:line and the rule pointer; a real key is not" \
  "templates/a.md:1 unknown-option wakeKindz $RULE" "$(audit)"

# A path a rule points at must exist.
printf 'see `docs/gone.md`, `scripts/real.sh`, `scripts/<name>.sh` and `docs/*.md`.\n' > "$R/templates/a.md"
mkdir -p "$R/scripts"; : > "$R/scripts/real.sh"
check "a template naming docs/gone.md is flagged dead-ref; a path on disk, a placeholder and a glob are not" \
  "templates/a.md:1 dead-ref docs/gone.md $RULE" "$(audit)"
# A :line or #heading suffix is not part of the path: the file it names is what must exist.
: > "$R/docs/real.md"
printf 'see `docs/real.md:12`, `docs/real.md#rules` and `docs/gone.md:3`.\n' > "$R/templates/a.md"
check "a path with a :line or #heading suffix is checked without it: docs/real.md is not flagged, docs/gone.md:3 is" \
  "templates/a.md:1 dead-ref docs/gone.md $RULE" "$(audit)"
rm -f "$R/templates/a.md" "$R/docs/real.md"

# Tests are left out, as their fixtures name missing paths and options on purpose; the same lines outside a
# __tests__ folder are still read, so the exception cannot hide a real hook or doc.
mkdir -p "$R/hooks/__tests__" "$R/docs/__tests__"
for f in hooks/__tests__/t.sh docs/__tests__/t.md hooks/t.sh docs/t.md; do
  printf 'see `docs/gone.md`\nsetup.sh --option wakeKindz=x\nrun --no-ponytail\n' > "$R/$f"
done
check "under hooks/__tests__ and docs/__tests__ nothing is flagged; the same lines in hooks/t.sh and docs/t.md are, all three kinds" \
  "docs/t.md:1:dead-ref docs/t.md:2:unknown-option docs/t.md:3:retired-name hooks/t.sh:1:dead-ref hooks/t.sh:2:unknown-option hooks/t.sh:3:retired-name " \
  "$(audit | awk '{print $1":"$2}' | sort | tr '\n' ' ')"
rm -rf "$R/hooks/__tests__" "$R/docs/__tests__" "$R/hooks/t.sh" "$R/docs/t.md"

# The changelog records what was retired, by name: it is history, not a rule.
printf 'run --no-ponytail\nsee `docs/gone.md`\n' > "$R/CHANGELOG.md"
OUT=$(audit); RC=$?
check "CHANGELOG.md naming a retired name and a missing path is not read" "0:" "$RC:$OUT"
rm -f "$R/CHANGELOG.md"

# MEMORY.md links: the kind existed, the audit now covers it end to end.
echo '- [gone](gone.md)' > "$T/mem/MEMORY.md"
check "a MEMORY.md line linking a missing file is flagged dead-index" "$T/mem/MEMORY.md:1 dead-index gone.md $RULE" "$(audit)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

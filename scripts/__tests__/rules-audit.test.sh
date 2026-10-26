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
  "docs/c.md:2 retired-name --no-ponytail, now: nothing: the add-on is removed $RULE" "$(grep '^docs/c.md' <<<"$OUT")"
rm -f "$R"/templates/a.md "$R"/.claude/briefs/b.md "$R"/docs/c.md "$R"/hooks/d.sh
# Issue 365: the --ponytail flag is retired with the add-on.
printf 'ok\nrun setup.sh --ponytail lite\n' > "$R/templates/a.md"
check "a retired --ponytail in a template is flagged with what replaced it" \
  "templates/a.md:2 retired-name --ponytail, now: nothing: the add-on is removed $RULE" "$(audit | grep '^templates/a.md')"
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

# --active-index moves an archived memory's line to MEMORY-archive.md; the file stays reachable, so it is no orphan.
rm -rf "$T/mem"; mkdir "$T/mem"; printf -- '---\nstatus: archived\n---\nold\n' > "$T/mem/old.md"; printf -- '- [Old](old.md): x\n' > "$T/mem/MEMORY.md"
bash "$REAL/scripts/rules-audit.sh" --active-index --repo "$R" --memory-dir "$T/mem"
check "after --active-index, the archived file is not flagged orphan-memory" "" "$(audit | grep 'orphan-memory')"

# MEMORY.md runs this at every start of main: a line that leaves one file is written to the other first, so a write
# that fails half way (here MEMORY.md's temp file cannot be made) loses no memory, and the next start finishes it.
ai() { bash "$REAL/scripts/rules-audit.sh" --active-index --repo "$R" --memory-dir "$T/mem" 2>/dev/null; }
PTR='- [Archived memories](MEMORY-archive.md): not loaded at start'
rm -rf "$T/mem"; mkdir "$T/mem"; printf -- '---\nname: old\n---\nactive again\n' > "$T/mem/old.md"
printf -- '%s\n' "$PTR" > "$T/mem/MEMORY.md"; printf -- '- [Old](old.md): x\n' > "$T/mem/MEMORY-archive.md"; mkdir "$T/mem/MEMORY.md.tmp"
ai
check "a memory made active again whose MEMORY.md write fails is still linked from one of the two files" 1 \
  "$(cat "$T/mem/MEMORY.md" "$T/mem/MEMORY-archive.md" 2>/dev/null | grep -cxF -- '- [Old](old.md): x')"
rmdir "$T/mem/MEMORY.md.tmp"; ai
check "and the next start puts it back in MEMORY.md and removes the emptied archive" "- [Old](old.md): x:no archive" \
  "$(cat "$T/mem/MEMORY.md"):$([ -e "$T/mem/MEMORY-archive.md" ] && echo archive || echo no archive)"
# A start stopped between the two writes leaves a line in both files: the next start keeps it once, where it belongs.
printf -- '---\nstatus: archived\n---\nb\n' > "$T/mem/b.md"
printf -- '- [Old](old.md): x\n- [B](b.md): y\n%s\n' "$PTR" > "$T/mem/MEMORY.md"; printf -- '- [B](b.md): y\n- [Old](old.md): x\n' > "$T/mem/MEMORY-archive.md"
ai
check "a line in both files after a stopped start is kept once: the active one in MEMORY.md, the archived one in the archive" \
  "- [Old](old.md): x|$PTR|- [B](b.md): y" "$(cat "$T/mem/MEMORY.md" "$T/mem/MEMORY-archive.md" | paste -sd'|' -)"

# Only the frontmatter says a memory is archived: a body that shows `status: archived` and then a `---` rule is active.
rm -rf "$T/mem"; mkdir "$T/mem"; printf -- '- [Live](live.md): x\n' > "$T/mem/MEMORY.md"
printf -- '---\nname: Live\nstatus: active\n---\nExample:\n```yaml\nstatus: archived\n```\n---\nkept\n' > "$T/mem/live.md"
ai
check "a memory whose body shows status: archived after its frontmatter stays in MEMORY.md, and no archive is made" \
  "- [Live](live.md): x:no archive" "$(cat "$T/mem/MEMORY.md"):$([ -e "$T/mem/MEMORY-archive.md" ] && echo archive || echo no archive)"
# The same bound for the lint's frontmatter fields: a body `description: SUPERSEDED` line is not the memory's description.
printf -- '---\nname: Live\ndescription: a rule\n---\nWrite it as:\ndescription: SUPERSEDED by x\n' > "$T/mem/live.md"
check "a description: SUPERSEDED line in a memory's body is not flagged superseded-memory" "" "$(audit | grep superseded-memory)"
mkdir -p "$R/.claude/rules"; { printf -- '---\ndescription: a rule\n---\npaths:\n'; for i in $(seq 300); do echo "line $i"; done; } > "$R/.claude/rules/a.md"
check "a 300-line rules file with paths: in its body, not its frontmatter, is flagged over-200-lines" \
  ".claude/rules/a.md:201 over-200-lines 304 lines $RULE" "$(audit | grep over-200-lines)"
rm -rf "$R/.claude/rules"
# The frontmatter is line 1 `---` to the next `---` line, whatever lies between (nothing included), with CRLF or no
# final newline; with no closing line there is none. Each memory below is archived only if its name says so.
FM_CASES=(
  'empty-active' '---\n---\nExample:\n```yaml\nstatus: archived\n```\n---\n'
  'crlf-archived' '---\r\nstatus: archived\r\n---\r\nold\r\n'
  'eof-archived' '---\nstatus: archived\n---'
  'unclosed-active' '---\nname: x\nstatus: archived\n'
  'late-active' '\n---\nstatus: archived\n---\n'
)
rm -rf "$T/mem"; mkdir "$T/mem"; : > "$T/mem/MEMORY.md"
for ((i = 0; i < ${#FM_CASES[@]}; i += 2)); do
  printf -- "${FM_CASES[i+1]}" > "$T/mem/${FM_CASES[i]}.md"; printf -- '- [x](%s.md): x\n' "${FM_CASES[i]}" >> "$T/mem/MEMORY.md"
done
ai
check "each frontmatter bound case is archived only when its frontmatter says so" \
  "crlf-archived.md eof-archived.md" "$(grep -o '[a-z]*-[a-z]*\.md' "$T/mem/MEMORY-archive.md" | paste -sd' ' -)"
mkdir -p "$R/.claude/rules"; { printf -- '---\n---\npaths:\n---\n'; for i in $(seq 300); do echo "line $i"; done; } > "$R/.claude/rules/a.md"
check "a 300-line rules file with an empty frontmatter and paths: in its body is flagged over-200-lines" \
  ".claude/rules/a.md:201 over-200-lines 304 lines $RULE" "$(audit | grep over-200-lines)"
rm -rf "$R/.claude/rules"

# A link the lint finds (./old.md is old.md in the same folder) is the same link here.
rm -rf "$T/mem"; mkdir "$T/mem"; printf -- '---\nstatus: archived\n---\nold\n' > "$T/mem/old.md"; printf -- '- [Old](./old.md): x\n' > "$T/mem/MEMORY.md"
ai
check "a MEMORY.md line linking ./old.md, an archived memory, moves to the archive" "$PTR|- [Old](./old.md): x" \
  "$(cat "$T/mem/MEMORY.md" "$T/mem/MEMORY-archive.md" 2>/dev/null | paste -sd'|' -)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

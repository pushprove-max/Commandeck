#!/usr/bin/env bash
# Self-test for bash-write-rules.sh: Claude Code loads a path rule only for Read/Edit/Write, so a shell write into a
# rule's paths must get the rule from the hook instead -- once per session per rule. Cases run in a scratch git
# checkout holding fixture rules; no real file is written.
# Run: bash hooks/__tests__/bash-write-rules.test.sh
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/bash-write-rules.sh"
SID="bashwriterules-$$"
PASS=0; FAIL=0
FX=$(mktemp -d); FX2=$(mktemp -d); export COMMANDECK_SCRATCH; COMMANDECK_SCRATCH=$(mktemp -d)
trap 'rm -rf "$FX" "$FX2" "$COMMANDECK_SCRATCH"' EXIT
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi; }
has() { case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac; }

git -C "$FX" init -q; git -C "$FX2" init -q
mkdir -p "$FX/.claude/rules" "$FX2/.claude/rules"
# rule <file> <frontmatter paths lines> <headings> <total chars>
rule() { { printf -- '---\npaths:\n%b---\n%b' "$2" "$3"; head -c "$4" /dev/zero | tr '\0' 'x'; } > "$1"; }
rule "$FX/.claude/rules/zz-a-code.md" '  - "src/**"\n  - "lambdas/**"\n  - "shared/**"\n' '# Code rules\n# Security notes\n' 3000
rule "$FX/.claude/rules/zz-b-tests.md" '  - "**/__tests__/**"\n' '# Test Standards\n## Running tests\n' 7500
rule "$FX/.claude/rules/zz-c-comments.md" '  - "**/*.ts"\n' '# Code comments\n' 4000
rule "$FX/.claude/rules/zz-big.md" '  - "docs/zz-fixture/**"\n' '' 12000
rule "$FX2/.claude/rules/zz-other.md" '  - "notes/**"\n' '# Other rules\n' 100

# session command [checkout] -> the injected text, empty when none
ctx() {
  local d=${3:-$FX}
  jq -cn --arg s "$SID-$1" --arg c "$2" --arg cwd "$d" \
    '{session_id:$s, cwd:$cwd, hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$c}}' \
    | (cd "$d" && bash "$HOOK" 2>/dev/null) | jq -r '.hookSpecificOutput.additionalContext // empty'
}
# Claude Code saves hook output over 10,000 chars to disk and shows a 2,000-char preview.
fits() { [ "${#1}" -gt 0 ] && [ "${#1}" -lt 10000 ] && echo yes || echo "no (${#1} chars)"; }

# Catches: a shell write into a rule's paths gets no rule, or only part of it.
OUT=$(ctx a "cat > src/zz-bwr-scratch.ts <<'EOF'
export const a = 1;
EOF")
check "a heredoc write into src injects zz-a-code.md"          yes "$(has "$OUT" 'matches .claude/rules/zz-a-code.md')"
check "  with the code text"                                    yes "$(has "$OUT" '# Code rules')"
check "  and the security text"                                 yes "$(has "$OUT" '# Security notes')"
check "  under the hook-output cap"                            yes "$(fits "$OUT")"
check "  and the comments rule beside it, which a shell write would otherwise never load" yes "$(has "$OUT" '# Code comments')"
# Catches: the once-per-session mark is lost, so a rule repeats on every write.
check "a rule-glob write shows the rule once" "" "$(ctx a "printf 'x' > src/zz-bwr-other.ts")"

OUT=$(ctx b "python3 -c \"open('scripts/__tests__/zz-bwr-scratch.test.ts', 'w').write('x')\"")
check "a python open(w) on a __tests__ .test.ts injects the test rule" yes "$(has "$OUT" '# Test Standards')"
check "  carrying the running-tests section"                    yes "$(has "$OUT" '## Running tests')"
check "  under the hook-output cap"                            yes "$(fits "$OUT")"
# The test rule leaves no room for the comments rule, which takes the next write.
OUT=$(ctx b "echo x >> scripts/__tests__/zz-bwr-scratch.test.ts")
check "the next test write brings the comments rule, which did not fit" yes "$(has "$OUT" '# Code comments')"
check "  and never the test rule a second time"                no "$(has "$OUT" '# Test Standards')"
check "the same session again injects nothing"                 "" "$(ctx b "echo x >> scripts/__tests__/zz-bwr-scratch.test.ts")"

check "a write under docs injects nothing"                     "" "$(ctx c "echo x > docs/zz-bwr-scratch.md")"
check "a read-only cat of a src file injects nothing"          "" "$(ctx d "cat src/zz-bwr-scratch.ts")"
check "a read whose stderr goes to /dev/null injects nothing"  "" "$(ctx d "cat src/zz-bwr-scratch.ts 2>/dev/null >&2")"

# Catches: a word in a heredoc body or a quoted string read as a write target.
check "a heredoc body naming a test file injects nothing"      "" "$(ctx k "cat >> docs/zz-bwr-scratch.md <<'EOF'
see src/__tests__/zz-bwr-scratch.test.ts and lambdas/api/zz-bwr.ts
EOF")"
check "a read-only rg for a quoted tee injects nothing"        "" "$(ctx k2 "rg -no 'tee .*>' src/zz-bwr-scratch.ts")"
# Catches: a write outside the checkout matched against the rules.
check "a read whose only write is outside the checkout injects nothing" "" \
  "$(ctx k3 "cat README.md > $COMMANDECK_SCRATCH/zz-bwr.json")"
check "a heredoc write into a test file injects the test rule" yes "$(has "$(ctx l "cat > scripts/__tests__/zz-bwr-heredoc.test.ts <<'EOF'
export {};
EOF")" '# Test Standards')"
check "a perl -pi on a src .ts injects the code rule"          yes "$(has "$(ctx n "perl -pi -e 's/a/b/' src/zz-bwr-scratch.ts")" '# Code rules')"
check "a quoted redirect target still counts"                  yes "$(has "$(ctx m "printf x > \"src/zz-bwr-scratch.ts\"")" '# Code rules')"

OUT=$(ctx e "sed -i '' 's/a/b/' lambdas/api/zz-bwr-scratch.ts")
check "a sed -i on a lambdas .ts injects the code rule"        yes "$(has "$OUT" 'matches .claude/rules/zz-a-code.md')"
check "  with the code text"                                    yes "$(has "$OUT" '# Code rules')"
check "  and the security text"                                 yes "$(has "$OUT" '# Security notes')"
OUT=$(ctx f "echo x | tee shared/zz-bwr-scratch.ts")
check "a tee into a shared .ts injects the code rule"          yes "$(has "$OUT" 'matches .claude/rules/zz-a-code.md')"
check "  with the code text"                                    yes "$(has "$OUT" '# Code rules')"
check "  and the security text"                                 yes "$(has "$OUT" '# Security notes')"
check "an absolute path under the checkout counts"             yes "$(has "$(ctx g "printf x > $FX/src/zz-bwr-scratch.ts")" '# Code rules')"

# Catches: two rules over the cap injected together. A src test file matches all three; one per command keeps each
# injection under the cap and the test rule lands on the next write.
OUT=$(ctx h "cp README.md src/__tests__/zz-bwr-scratch.test.ts")
check "a src test write first injects the code rule"           yes "$(has "$OUT" '# Code rules')"
check "  and not the test rule in the same output"             no "$(has "$OUT" '# Test Standards')"
check "the next src test write injects the test rule"          yes "$(has "$(ctx h "mv README.md src/__tests__/zz-bwr-scratch.test.ts")" '# Test Standards')"

check "a write after cd into src injects the code rule"        yes "$(has "$(ctx i "cd src && echo x > zz-bwr-scratch.ts")" '# Code rules')"

# Catches: a rule over the cap truncated into a dump the model never sees; it is a pointer instead.
OUT=$(ctx j "echo x > docs/zz-fixture/a.md")
check "a rule over the cap with no generated section is a pointer" yes "$(has "$OUT" 'Read .claude/rules/zz-big.md')"
check "  and carries none of its text" no "$(has "$OUT" xxxxxxxxxx)"
check "  under the hook-output cap"                            yes "$(fits "$OUT")"

# Catches: a rule that grows past the cap on some glob.
N=0
while IFS=$'\t' read -r rule path; do
  N=$((N + 1))
  OUT=$(ctx "all-$N" "echo x > $path")
  check "a write to $path (.claude/rules/$rule) fits under the cap" yes "$(fits "$OUT")"
done < <(python3 -I - "$FX/.claude/rules" <<'PY'
import json, os, re, sys
d = sys.argv[1]
for name in sorted(os.listdir(d)):
    front = re.match(r"---\n(.*?)\n---\n", open(os.path.join(d, name)).read(), re.S)
    lines = front.group(1).splitlines() if front else []
    for i, line in enumerate(lines):
        if not line.startswith("paths:"):
            continue
        globs = json.loads(line[6:]) if line[6:].strip() else [
            l.strip()[1:].strip().strip("\"'") for l in lines[i + 1:] if l.lstrip().startswith("-")]
        for g in globs:
            print(f"{name}\t" + g.replace("**/", "").replace("**", "zz").replace("*", "zz-bwr").replace("?", "z"))
PY
)
[ "$N" -eq 6 ] && check "every rule glob was exercised ($N)" yes yes || check "every rule glob was exercised" 6 "$N"

# Catches: each misses a write target, so a real write loses its path rules: sed -i -e'expr', a numbered fd, a spaced sed script.
OUT=$(ctx fold-a "sed -i.bak -e's/a/b/' src/ra-probe.ts")
check "attached_expression_write_injects" yes "$(has "$OUT" '# Code rules')"
check "fd_write_injects" "yes yes" \
  "$(has "$(ctx fold-fd1 'printf x 1> src/zz-fd-refute.ts')" '# Code rules') $(has "$(ctx fold-fd2 'printf x 2> src/zz-fd-refute.ts')" '# Code rules')"
OUT=$(ctx fold-s "sed -i 's/a/b/' src/ra-probe.ts")
check "spaced_sed_write_injects" yes "$(has "$OUT" '# Code rules')"

# Catches: rules read from a fixed folder, so another project gets this project's rule (or none of its own).
check "another project gets its own rule" "yes no" \
  "$(has "$(ctx p1 'echo x > notes/a.md' "$FX2")" '# Other rules') $(has "$(ctx p2 'echo x > notes/a.md' "$FX")" '# Other rules')"

# Catches: the once-per-session mark keyed on the rule name alone, so in one session the first project's
# code.md hides a second project's different code.md.
P1=$(mktemp -d); P2=$(mktemp -d); trap 'rm -rf "$FX" "$FX2" "$P1" "$P2" "$COMMANDECK_SCRATCH"' EXIT
for p in P1 P2; do
  d=${!p}; git -C "$d" init -q; mkdir -p "$d/.claude/rules"
  rule "$d/.claude/rules/zz-shared.md" '  - "src/**"\n' "# $p RULE\n" 10
done
check "one session gets each project's same-named rule" "yes yes" \
  "$(has "$(ctx shared 'echo x > src/a.ts' "$P1")" '# P1 RULE') $(has "$(ctx shared 'echo x > src/a.ts' "$P2")" '# P2 RULE')"
check "  and the same project's rule still shows once" "" "$(ctx shared 'echo x > src/b.ts' "$P1")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

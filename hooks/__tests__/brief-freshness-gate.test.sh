#!/usr/bin/env bash
# Most cases run with BRIEF_FRESHNESS_DRY_RUN=1, so the hook prints how many
# cited paths it checked: "no output" then means "this path was not a brief",
# never "the gate read nothing".
#
# One claim beyond "a dead citation is named": a path the brief says it will
# CREATE is not a dead citation. Warning about the brief's own output is how a
# warning gets trained away.
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/brief-freshness-gate.sh"
ROOT=$(git rev-parse --show-toplevel)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
PASS=0 FAIL=0

check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected '$2', got '$3')"; fi }
contains() { case "$3" in *"$2"*) PASS=$((PASS+1)); echo "ok   $1";; *) FAIL=$((FAIL+1)); echo "FAIL $1 (missing '$2' in '$3')";; esac; }

run() {
  jq -cn --arg fp "$1" '{tool_input:{file_path:$fp}}' \
    | BRIEF_FRESHNESS_DRY_RUN=1 CLAUDE_PROJECT_DIR="$ROOT" "$HOOK" 2>&1
}

mkdir -p "$WORK/.claude/briefs"

# Catches a live citation being warned about, or the gate reading nothing.
cat > "$WORK/.claude/briefs/good.md" <<'EOF'
Scope: hooks/no-poll-loops.sh and docs/hooks.md
EOF
OUT=$(run "$WORK/.claude/briefs/good.md")
check "all-live brief warns nothing" "[brief-freshness] checked 2 cited paths" "$OUT"

# Catches a moved or deleted file going out in a brief unnoticed.
cat > "$WORK/.claude/briefs/stale.md" <<'EOF'
Scope: hooks/no-poll-loops.sh and docs/gone-forever.md
EOF
OUT=$(run "$WORK/.claude/briefs/stale.md")
contains "a dead cited path warns" "docs/gone-forever.md" "$OUT"
contains "dead citation is called out" "do not exist" "$OUT"

# Catches the hooks/ folder falling out of the cited roots.
cat > "$WORK/.claude/briefs/dead-hook.md" <<'EOF'
Scope: hooks/gone-forever.sh
EOF
contains "a dead hooks/ path warns" "hooks/gone-forever.sh" "$(run "$WORK/.claude/briefs/dead-hook.md")"

# Catches the old Environment/Acceptance validator coming back: the plugin has no writer for it.
printf 'Class: gate/CI\nScope: hooks/no-poll-loops.sh\n' > "$WORK/.claude/briefs/no-env.md"
check "no Environment line, no warning" "[brief-freshness] checked 1 cited paths" "$(run "$WORK/.claude/briefs/no-env.md")"

# Catches warning about the brief's own output, which trains the warning away.
cat > "$WORK/.claude/briefs/creates.md" <<'EOF'
Scope: hooks/no-poll-loops.sh
Create hooks/__tests__/brand-new-thing.test.sh with a case per rule.
EOF
check "a commissioned file is not warned about" "[brief-freshness] checked 2 cited paths" "$(run "$WORK/.claude/briefs/creates.md")"

cat > "$WORK/.claude/briefs/new-marker.md" <<'EOF'
NEW templates/brand-new-thing.md holds the members.
EOF
check "a NEW marker counts as commissioned" "[brief-freshness] checked 1 cited paths" "$(run "$WORK/.claude/briefs/new-marker.md")"

# ...and a path merely REFERENCED that is gone is still the failure.
cat > "$WORK/.claude/briefs/mixed.md" <<'EOF'
Create hooks/__tests__/brand-new-thing.test.sh.
Read docs/gone-forever.md before you start.
EOF
OUT=$(run "$WORK/.claude/briefs/mixed.md")
contains "the referenced dead path is still named" "docs/gone-forever.md" "$OUT"
case "$OUT" in
  *brand-new-thing.test.sh*) FAIL=$((FAIL+1)); echo "FAIL the commissioned path is not listed as dead" ;;
  *) PASS=$((PASS+1)); echo "ok   the commissioned path is not listed as dead" ;;
esac
contains "and the commissioned one is counted apart" "described as new files" "$OUT"

# Catches the hook acting on files that are not briefs or plans.
check "a source file is ignored" "" "$(run "$ROOT/hooks/no-poll-loops.sh")"
check "a docs file is ignored" "" "$(run "$ROOT/docs/hooks.md")"
check "a markdown file outside briefs/ is ignored" "" "$(run "$ROOT/README.md")"

# Catches a brief citing no repo paths producing output.
echo 'Rewrite the login copy. No files named.' > "$WORK/.claude/briefs/empty-review.md"
check "a brief citing no paths is silent" "" "$(run "$WORK/.claude/briefs/empty-review.md")"

# Catches a missing file making the hook fail.
check "missing brief file is silent" "" "$(run "$WORK/.claude/briefs/nope.md")"

# Catches a plan with a heavy fixture and no timed checks going out unwarned.
mkdir -p "$WORK/.claude/plans"
printf '# plan\n\nAdds a heavy fixture to the merge test.\n' > "$WORK/.claude/plans/heavy.md"
contains "a heavy fixture without Timed checks warns" "Timed checks" "$(run "$WORK/.claude/plans/heavy.md")"
printf '# plan\n\nAdds a heavy fixture to the merge test.\nTimed checks: the 5 s peer wait\n' > "$WORK/.claude/plans/heavy-ok.md"
check "a heavy fixture with a Timed checks line does not warn" "" "$(run "$WORK/.claude/plans/heavy-ok.md")"
# Catches a template being warned about as if it were a plan.
printf '# template\n\nheavy fixture\n' > "$WORK/.claude/briefs/_tpl.md"
check "an underscore template gets no plan warning" 0 "$(run "$WORK/.claude/briefs/_tpl.md" | grep -c "Timed checks")"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

#!/usr/bin/env bash
# update.test.sh -- update.sh shows what setup's rerun says needs the owner. Setup puts a failed add-on install or
# update under "Needs you"; an update that dropped setup's output hid that failure and still said done (main ruling 2026-10-16).
# setup.sh and doctor.sh are stubs here, in a plugin folder of links to the real scripts (no setup run).
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
export HOME=$T/home
PL=$T/plugin PROJ=$T/proj
mkdir -p "$PL/scripts" "$HOME" && ln -s "$REAL/.claude-plugin" "$REAL/CHANGELOG.md" "$PL/"
for f in "$REAL"/scripts/*; do case ${f##*/} in setup.sh|doctor.sh) ;; *) ln -s "$f" "$PL/scripts/"; esac; done
cat > "$PL/scripts/setup.sh" <<'EOF'
#!/usr/bin/env bash
echo "codex: updated 0.40.0 -> 0.41.0 (codex update)"
echo "Done:"
echo "add-on serena: installed at its latest"
echo
echo "Needs you:"
echo "  add-on ponytail: the install FAILED (network down); to try again, run in the project: x"
echo
echo "Optional. Add-ons not installed; each line is the command and what it costs:"
EOF
echo 'echo "doctor: ok"' > "$PL/scripts/doctor.sh"
git init -q -b main "$PROJ" && mkdir -p "$PROJ/.claude" && echo '{"version": 1}' > "$PROJ/.claude/commandeck.json"
SLUG=$(cd "$PROJ" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR bash -c '. "$0" && echo "$PP_MAIN_SLUG"' "$REAL/scripts/paths.sh")
mkdir -p "$HOME/.commandeck/install" && echo '{"root": "/old", "entries": {}}' > "$HOME/.commandeck/install/$SLUG.json"
upd() { (cd "$PROJ" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH -u CODEX_HOME bash "$PL/scripts/update.sh" 2>&1); }

OUT=$(upd)
check "it shows setup's Needs-you block, the failed install's line whole" "Needs you:
  add-on ponytail: the install FAILED (network down); to try again, run in the project: x" "$(grep -A1 '^Needs you:$' <<<"$OUT")"
check "and not the rest of setup's report" 0 "$(grep -c '^Optional\.\|^add-on serena' <<<"$OUT")"
# Issue 314: setup updates Codex when a newer one is out; the owner is told, not only on failure.
check "it says setup's codex line" "codex: updated 0.40.0 -> 0.41.0 (codex update)" "$(grep '^codex: ' <<<"$OUT")"
check "then the doctor runs and the update says done" '1:1' "$(grep -c '^doctor: ok$' <<<"$OUT"):$(grep -c '^update: done$' <<<"$OUT")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

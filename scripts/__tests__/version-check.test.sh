#!/usr/bin/env bash
# version-check.test.sh -- two pushes changed the plugin and the version stayed
# the same, so a machine that had the plugin saw nothing new on update. What
# this pins: ci/version-check.sh fails when a plugin file changed against the
# main branch and .claude-plugin/plugin.json carries the version main has;
# passes once the version differs; and never counts a change to the docs or to
# ci/ alone as a plugin change.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
g() { git -C "$T/r" -c user.name=t -c user.email=t@t "$@"; }
# vc [base] -- the check's exit status in the scratch repository; what it printed is in $T/out.
vc() { (cd "$T/r" && bash "$ROOT/ci/version-check.sh" "${1:-main}") >"$T/out" 2>&1; echo $?; }
git init -q -b main "$T/r"
mkdir -p "$T/r/.claude-plugin" "$T/r/scripts" "$T/r/ci" "$T/r/skills/setup"
echo '{"name": "p", "version": "1.2.0"}' > "$T/r/.claude-plugin/plugin.json"
echo 'echo one' > "$T/r/scripts/a.sh"; echo '# readme' > "$T/r/README.md"; echo 'true' > "$T/r/ci/x.sh"; echo 'ask' > "$T/r/skills/setup/SKILL.md"
g add -A && g commit -q -m first
g checkout -q -b work
check "a branch with no change passes" 0 "$(vc)"

echo '# readme, longer' > "$T/r/README.md"; echo '# changes' > "$T/r/CHANGELOG.md"; g add -A && g commit -q -m docs
check "a docs-only change passes with the version unchanged" 0 "$(vc)"
echo 'false' > "$T/r/ci/x.sh"; g add -A && g commit -q -m ci
check "so does a change to ci/ alone" 0 "$(vc)"

echo 'echo two' > "$T/r/scripts/a.sh"; g add -A && g commit -q -m plugin
check "a changed plugin file with the version unchanged fails" 1 "$(vc)"
check "the failure names the version and a changed file" 2 "$(grep -c -e '1\.2\.0' -e 'scripts/a\.sh' "$T/out")"
check "and says which paths count" 1 "$(grep -c 'What counts as the plugin: .*scripts/' "$T/out")"
echo '{"name": "p", "version": "1.3.0"}' > "$T/r/.claude-plugin/plugin.json"
check "a raised version passes before it is even committed" 0 "$(vc)"
g add -A && g commit -q -m version
check "and after" 0 "$(vc)"

# A skill's text is the plugin, though it is a .md file; and a change not yet committed counts.
g checkout -q -b second main
echo 'ask twice' > "$T/r/skills/setup/SKILL.md"
check "a skill file changed and not yet committed fails with the version unchanged" 1 "$(vc)"
g checkout -q -- skills; : > "$T/r/scripts/new.sh"
check "so does a new plugin file git does not track yet" 1 "$(vc)"
rm "$T/r/scripts/new.sh"
check "with no such base to compare with the check fails, and does not pass by default" 2 "$(vc no-such-branch)"

# Two branches can pick the same next number: once one merges, the other's number is main's already.
g checkout -q -b third main
echo 'echo three' > "$T/r/scripts/a.sh"; echo '{"name": "p", "version": "1.3.0"}' > "$T/r/.claude-plugin/plugin.json"; g add -A && g commit -q -m third
g checkout -q main
echo 'echo main' > "$T/r/scripts/b.sh"; echo '{"name": "p", "version": "1.3.0"}' > "$T/r/.claude-plugin/plugin.json"; g add -A && g commit -q -m other
g checkout -q third
check "a version main took meanwhile from another branch fails" 1 "$(vc)"
check "and says it is main's" 1 "$(grep -c 'version is still 1\.3\.0' "$T/out")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

#!/usr/bin/env bash
# The test rules reach a project's Builders and reviewers only through the
# installed plugin folder: setup links ~/.commandeck/plugin to the plugin root
# (setup.sh, ln -sfn), and the Builder brief and every review prompt name the
# rules file under that link. A renamed file or a wrong pointer leaves the
# agents with no test rules and no error; a rule dropped from the file leaves
# them with a weaker one.
set -uo pipefail
R="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (want \"$2\", got \"$3\")"; fi }
H=$(mktemp -d); trap 'rm -rf "$H"' EXIT
# The link as setup makes it, made twice: a re-install replaces the link and leaves one folder, not a copy beside it.
mkdir -p "$H/.commandeck"; ln -sfn "$R" "$H/.commandeck/plugin"; ln -sfn "$R" "$H/.commandeck/plugin"
check "a re-install leaves one link to the plugin root" "1 $R" "$(find "$H/.commandeck" -mindepth 1 | grep -c .) $(readlink "$H/.commandeck/plugin")"
# Each template's pointer, read through the scratch link, is the plugin's own rules file.
for t in templates/_builder-brief-template.md scripts/builder-codex-pass.sh; do
  p=$(grep -oE '~/\.commandeck/plugin/templates/test-rules\.md' "$R/$t" | head -1)
  f=$H/${p#\~/}
  check "$t points to the installed test rules file" "yes" "$([ -n "$p" ] && cmp -s "$f" "$R/templates/test-rules.md" && echo yes || echo no)"
done
# The two parts of the rules, one line per paragraph so a wrapped rule is one string.
BODY=$(awk 'NF { printf "%s ", $0; next } { print "" } END { print "" }' "$R/templates/test-rules.md" 2>/dev/null | sed -E 's/ +/ /g')
has() { check "$1" yes "$(grep -qF -- "$2" <<<"$BODY" && echo yes || echo no)"; }
has "never weaken: no deletion or merge without a named test that catches the same failure" "No test is deleted or merged unless a named other test catches the same failure."
has "never weaken: each deleted or merged test is listed with its replacement" "List every deleted or merged test with the test that replaces it"
has "a test encodes why the behaviour matters" "A test encodes why the behaviour matters, not only what it does."
has "a test that cannot fail when the rule changes is wrong" "A test that cannot fail when the business rule changes is wrong."
has "size and counts are screening proxies, not evidence" "Length, assertion counts and branch counts are screening proxies, not evidence of intent."
has "a deletion needs an intent review; a coverage floor is not enough" "A deletion needs a review that the test's intent is kept; a passing coverage floor alone is not enough."
has "no test without an assertion, no unapproved skip" "No test without an assertion, and no skip that was not approved."
has "the reviewer names a change that would fail each test" "The reviewer names one code change that would make each new or changed test fail; a test with no such change is a finding."
# #487: a refusal at the test cap sends a Builder to main; without this rule it merged tests to get under the cap.
LIMIT="On a refusal at the new-test or tooling cap, stop and ask main. No existing test is edited, merged or deleted without the owner's yes by name."
has "test_limit_rule_sends_to_main: the rules file sends a cap refusal to main" "$LIMIT"
check "test_limit_rule_sends_to_main: the Builder brief says the same" yes \
  "$(tr '\n' ' ' < "$R/templates/_builder-brief-template.md" | sed -E 's/ +/ /g' | grep -qF -- "$LIMIT" && echo yes || echo no)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

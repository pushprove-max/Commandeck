#!/usr/bin/env bash
# merge-unit-local.sh refuses a unit that loosens the file-size cap unless the
# caller states why with --baseline-raise "<reason>", and that reason lands in
# the squash commit message, so a raised limit is never silent in history.
#   1. a loosening unit is refused without the flag, naming the flag;
#   2. with the flag it passes and the squash message carries the reason;
#   3. a unit that loosens nothing passes without the flag;
#   4. --help names the flag.
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
SCRIPT=$ROOT/scripts/merge-unit-local.sh
TMP=$(mktemp -d /tmp/merge-baseline-raise.XXXXXX); trap 'rm -rf "$TMP"' EXIT
die() { echo "FAIL: $*" >&2; exit 1; }
awk '/^check_baseline_raise\(\)/ { on=1 } on { print } on && /^}$/ { exit }' "$SCRIPT" > "$TMP/check.sh"
grep -E '^\[ -z "\$BASELINE_RAISE" \] \|\| TITLE=' "$SCRIPT" > "$TMP/title.sh" || true
[ -s "$TMP/check.sh" ] && [ -s "$TMP/title.sh" ] || die "check_baseline_raise or the title line is not in merge-unit-local.sh"
# check_baseline_raise finds baseline-raise-check.sh beside itself ($HERE), as in the script, never in the project.
HERE=$ROOT/scripts
# shellcheck disable=SC1090,SC1091
. "$TMP/check.sh"
fail() { echo "FAILED $1: $2" >&2; exit 1; }  # the script's own fail()

R=$TMP/repo
g() { git -C "$R" -c user.name=t -c user.email=t@t -c core.hooksPath=/dev/null "$@"; }
git init -q -b main "$R"
mkdir -p "$R/hooks" && printf '    *.tsx) CAP=400; RULE=a ;;\n' > "$R/hooks/file-size-cop.sh"
g add -A && g commit -q -m base
g checkout -q -b unit/u
printf '    *.tsx) CAP=401; RULE=a ;;\n' > "$R/hooks/file-size-cop.sh"
g commit -q -am 'feat(u): raise'
g checkout -q main
cd "$R"
BRANCH=unit/u

# A refusal without the flag lets a loosened cap into history unexplained.
OUT=$( (BASELINE_RAISE=""; check_baseline_raise) 2>&1) && { echo "FAIL a loosening unit needs the flag (it was not refused)" >&2; exit 1; }
grep -q -- '--baseline-raise' <<<"$OUT" || die "the refusal does not name --baseline-raise: $OUT"
grep -qF 'LOOSENED hooks/file-size-cop.sh CAP #1: 400 -> 401' <<<"$OUT" || die "the refusal does not name the loosened limit: $OUT"

# The reason must ride in the squash message, or the raise is silent in git log.
BASELINE_RAISE="approved for the new rule table"
OUT=$(check_baseline_raise 2>&1) || die "the flag did not let the unit through: $OUT"
TITLE='feat(u): raise'
# shellcheck disable=SC1090,SC1091
. "$TMP/title.sh"
g merge -q --squash "$BRANCH" >/dev/null && g commit -q -m "$TITLE"
g log -1 --format=%B | grep -qxF "Baseline-raise: $BASELINE_RAISE" || die "the squash message lacks the reason: $(g log -1 --format=%B)"

# A unit that loosens nothing must not need the flag, or every merge would.
g checkout -q -b unit/v && echo x > "$R/other.txt" && g add other.txt && g commit -q -m 'feat(v): plain'
g checkout -q main
BRANCH=unit/v BASELINE_RAISE=""
OUT=$(check_baseline_raise 2>&1) || die "a unit that loosens nothing was refused: $OUT"

# The flag must be discoverable from --help, or a refused merge has no way forward.
bash "$SCRIPT" --help | grep -q -- '--baseline-raise "<reason>"' || die "--help does not name --baseline-raise"
echo "PASS: a loosened file-size cap merges only with --baseline-raise, and the reason rides in the squash message"

#!/usr/bin/env bash
# run-shell-tests.sh [--own-lane] [--list | --changed [<base>] | <file>...] -- run every shell
# self-test under hooks/__tests__ and scripts/__tests__ (or only the named files), one per line in
# sorted order, and exit non-zero if any failed. Each file's result is also
# printed the moment it finishes, as a `-- ` line ahead of the sorted report.
# Tests run in parallel, COMMANDECK_SHELL_TEST_JOBS at a time (default: half the
# CPUs, at least 1), so no two tests may share a fixed scratch path.
#
# Why this exists: 135 of these tests were wired to no gate at all. test:guards
# selects TypeScript files only, and nothing in local-checks.sh or the CI
# workflows reached them, so they ran only when somebody ran one by hand. Three
# sat red at HEAD on 2026-09-13 without anyone noticing, and one blocked for
# eighteen minutes rather than failing (ruling 2026-09-13, "wire them in").
#
# A test that hangs is a failure, not a wait: TIMEOUT bounds each one. A test
# that is deliberately red carries `# parked: <reason>` in its first five lines
# and is skipped with that reason printed, so a parked test can never be
# mistaken for a passing one. A test slow by design carries `# timeout: <secs>`
# in the same first five lines, which replaces TIMEOUT for that file only.
#
# A test too slow to share the guards shard carries `# own-lane: <reason>` in
# the same first five lines. The ordinary run skips it and `--own-lane` runs
# only those, which is how the chain gives them a lane of their own. The
# coverage guard reads the same marker, so the two never both run one test.
#
# `--changed [<base>]` runs only the tests `git diff --name-only <base>` (default
# HEAD) touches: a test it adds or edits, and the same-name test of a script or
# hook it adds or edits (scripts/seat.sh -> scripts/__tests__/seat.test.sh). It is
# the merge check: the whole suite took 12 minutes a merge (ruling 2026-10-17).
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
# On a Mac: Homebrew's tools ahead of the system's, and out of its Bash 3.2 (requirements.sh).
. "$(dirname "$0")/requirements.sh"
# The tests, and this runner's mapfile and wait -n, need Bash 4: with no newer Bash to restart under, say so.
[ "${BASH_VERSINFO[0]}" -ge 4 ] || { echo "run-shell-tests: the tests need Bash 4 or newer and this is $BASH_VERSION; on a Mac: brew install bash" >&2; exit 2; }
ROOT=$(git rev-parse --show-toplevel)
TIMEOUT=${COMMANDECK_SHELL_TEST_TIMEOUT:-120}
JOBS=${COMMANDECK_SHELL_TEST_JOBS:-$(( $(getconf _NPROCESSORS_ONLN) / 2 ))}
[ "$JOBS" -ge 1 ] 2>/dev/null || JOBS=1
CALLER_PWD=$PWD
# In main's own foreground a run restarts itself detached (issue 230). A subshell: paths.sh exports what the
# tests must not inherit. No test this runs is main's foreground.
if [ "${1:-}" != --list ]; then
  ( COMMANDECK_MAIN=$ROOT . "$(dirname "$0")/paths.sh" && pp_main_foreground || exit 1
    pp_detach "$PP_SCRATCH/shell-tests.log" run-shell-tests.sh bash "$0" "$@" ) && exit 0
fi
export COMMANDECK_FOREGROUND=1
cd "$ROOT" || exit 2
# macOS TMPDIR (/var/folders/...) is a symlink into /private. Tests compare
# mktemp paths with git's and pwd -P's physical ones, so hand them the physical path.
export TMPDIR
# paths.sh takes the project from these two before the folder a test runs in:
# inherited from the caller's session, they would point a fixture's script at a real project.
# CLAUDE_CONFIG_DIR the same for the owner's settings file, where the /config options are (issue 245).
unset CLAUDE_PROJECT_DIR COMMANDECK_MAIN CLAUDE_CONFIG_DIR
TMPDIR=$(cd "${TMPDIR:-/tmp}" && pwd -P) || exit 2

ONLY_OWN_LANE=0
[ "${1:-}" = --own-lane ] && { ONLY_OWN_LANE=1; shift; }

if [ "${1:-}" = --changed ]; then
  BASE=${2:-HEAD}
  # An unknown base would select nothing and pass: fail instead.
  git rev-parse -q --verify "$BASE^{commit}" >/dev/null || { echo "run-shell-tests: --changed: no commit $BASE" >&2; exit 2; }
  # A deleted file selects nothing (--diff-filter=d). A failed git would also select nothing and pass: fail instead.
  CHANGED=$(git diff --name-only --diff-filter=d "$BASE" --) || { echo "run-shell-tests: --changed: git diff $BASE failed" >&2; exit 2; }
  # A shared helper's callers' tests are not run (main's ruling 2026-10-17): CI's full suite on every push covers them.
  mapfile -t TESTS < <(printf '%s\n' "$CHANGED" | while IFS= read -r f; do
    case $f in
      (hooks/__tests__/*/*|scripts/__tests__/*/*) ;;
      (hooks/__tests__/*.test.sh|scripts/__tests__/*.test.sh) echo "$f" ;;
      # A test module runs through its same-name shell wrapper (dashboard-view.test.sh).
      (hooks/__tests__/*.test.mjs|scripts/__tests__/*.test.mjs) t=${f%.mjs}.sh; [ ! -f "$t" ] || echo "$t" ;;
      (hooks/*/*|scripts/*/*) ;;
      (hooks/*|scripts/*) t=${f%%/*}/__tests__/$(basename "${f%.*}").test.sh; [ ! -f "$t" ] || echo "$t" ;;
    esac
  done | sort -u)
  [ "${#TESTS[@]}" -gt 0 ] || { echo "run-shell-tests: no shell test was touched since $BASE"; exit 0; }
elif [ $# -gt 0 ] && [ "$1" != --list ]; then
  # Named files are relative to where the caller stood, not to $ROOT.
  mapfile -t TESTS < <(for f in "$@"; do case $f in (/*) echo "$f" ;; (*) echo "$CALLER_PWD/$f" ;; esac; done | sort)
else
  mapfile -t TESTS < <(ls hooks/__tests__/*.test.sh scripts/__tests__/*.test.sh 2>/dev/null | sort)
fi
[ "${#TESTS[@]}" -gt 0 ] || { echo "run-shell-tests: found no test files" >&2; exit 2; }
[ "${1:-}" = --list ] && { printf '%s\n' "${TESTS[@]}"; exit 0; }

RES=$(mktemp -d) || exit 2
trap 'rm -rf "$RES"' EXIT
# A real hook run by a test must not count as a real fire.
export COMMANDECK_HOOK_FIRE_LOG="$RES/hook-fire-log.jsonl"
run_one() {
  local start rc
  start=$(date +%s)
  # review-round.sh's default self-review is a REAL Codex review: every test
  # sets its own stub, and one that does not runs this poison and fails below.
  COMMANDECK_SELF_REVIEW_CMD="touch '$RES/$1.companion'; exit 97" \
    timeout "${CAP[$1]}" bash "$2" > "$RES/$1.out" 2>&1; rc=$?
  echo "$rc $(( $(date +%s) - start ))" > "$RES/$1.rc"
  # One printf per line: parallel files then cannot interleave inside a line.
  printf -- '-- %s\n' "$(status_line "$1")"
}
# The result line of finished test $1. The live `-- ` line and the sorted
# report both print it, so the two cannot drift.
status_line() {
  local rc secs why
  read -r rc secs < "$RES/$1.rc"
  if [ -e "$RES/$1.companion" ]; then why="ran the Codex companion path: set COMMANDECK_SELF_REVIEW_CMD to a stub"
  elif [ "$rc" -eq 0 ]; then printf 'ok   %-58s %ss' "$(basename "${TESTS[$1]}")" "$secs"; return
  elif [ "$rc" -eq 124 ]; then why="HUNG past ${CAP[$1]}s"
  else why="rc=$rc"; fi
  printf 'FAIL %-58s %ss %s' "$(basename "${TESTS[$1]}")" "$secs" "$why"
}

# Launch pass: skips are decided here, runnable tests go to the background.
SKIPWHY=() CAP=()
for i in "${!TESTS[@]}"; do
  t=${TESTS[$i]}
  parked=$(sed -n '1,5p' "$t" | sed -n 's/^# parked: *//p' | head -1)
  own_lane=$(sed -n '1,5p' "$t" | sed -n 's/^# own-lane: *//p' | head -1)
  if [ -n "$parked" ]; then SKIPWHY[i]=$parked
  elif [ "$ONLY_OWN_LANE" = 1 ]; then
    [ -n "$own_lane" ] || continue
  elif [ -n "$own_lane" ]; then SKIPWHY[i]="own lane: $own_lane"
  fi
  if [ -n "${SKIPWHY[i]:-}" ]; then
    printf -- '-- skip %-58s %s\n' "$(basename "$t")" "${SKIPWHY[i]}"; continue
  fi
  cap=$(sed -n '1,5p' "$t" | sed -n 's/^# timeout: *\([0-9][0-9]*\).*/\1/p' | head -1)
  CAP[i]=${cap:-$TIMEOUT}
  while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n; done
  run_one "$i" "$t" &
done
wait

# Report pass, in sorted order whatever order the tests finished in.
PASS=0 FAIL=0 SKIP=0 FAILED=()
for i in "${!TESTS[@]}"; do
  t=${TESTS[$i]}
  if [ -n "${SKIPWHY[i]:-}" ]; then
    SKIP=$((SKIP + 1)); printf 'skip %-58s %s\n' "$(basename "$t")" "${SKIPWHY[i]}"; continue
  fi
  [ -f "$RES/$i.rc" ] || continue
  line=$(status_line "$i"); printf '%s\n' "$line"
  case $line in
    ok*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); FAILED+=("$t")
       [ -e "$RES/$i.companion" ] || tail -12 "$RES/$i.out" | sed 's/^/       /' ;;
  esac
done

echo
# Anti-vacuity: an own-lane run that matched nothing means the marker was
# removed or renamed, and the lane would pass while testing nothing.
[ "$ONLY_OWN_LANE" = 0 ] || [ $((PASS + FAIL)) -gt 0 ] || {
  echo "run-shell-tests: --own-lane matched no test; is the # own-lane: marker still there?" >&2
  exit 2
}
echo "$PASS passed, $FAIL failed, $SKIP parked"
[ "$FAIL" -eq 0 ] || { echo "failed:"; printf '  %s\n' "${FAILED[@]}"; }
[ "$FAIL" -eq 0 ]

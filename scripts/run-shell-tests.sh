#!/usr/bin/env bash
# run-shell-tests.sh [--own-lane] [--skip-passed] [--list | --changed [<base>] [--callers] | <file>...] -- run every shell
# self-test under hooks/__tests__ and scripts/__tests__ (or only the named files), one per line in
# sorted order, and exit non-zero if any failed. Each file's result is also
# printed the moment it finishes, as a `-- ` line ahead of the sorted report.
# Tests run in parallel, COMMANDECK_SHELL_TEST_JOBS at a time (default: half the
# CPUs, one less under load, at least 1), so no two tests may share a fixed scratch path.
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
# Files start longest first (#489), from the seconds saved at $HOME/.commandeck/shell-test-seconds.tsv
# (COMMANDECK_SHELL_TEST_SECONDS overrides; one copy per host, `<seconds>\t<file basename>`), so a run does not end on
# its slow files alone. A file with no row starts after the known ones. Only a bare run saves it. A run inside a test
# uses no list unless the variable names one.
#
# `--changed [<base>] [--callers]` runs only the tests `git diff --name-only <base>` (default
# HEAD) touches: a test it adds or edits, and the same-name test of a script or
# hook it adds or edits (scripts/seat.sh -> scripts/__tests__/seat.test.sh). It is
# the merge check: the whole suite took 12 minutes a merge (ruling 2026-10-17).
# A test named after no script it tests carries `# covers: <path>...` in the
# same first five lines, and --changed runs it when any of those paths changed.
#
# `--skip-passed` (issue 422) does not run a local file whose last result in <common git dir>/commandeck-test-runs.tsv
# is ok for exactly its inputs now; it prints that file's result line with 0s and counts it as passed. Never a full
# retest (issue 667): a file's key is the hash of its inputs (scripts/test-inputs.sh --list: the file, what it names,
# what they source) as they are in this run's tree, or the whole tree when the map is uncertain, so a pass outlives
# changes to other files, and the ledger is shared by every worktree of the repository (pre-push's included). A pass is
# recorded or reused only if no file of the tree changed since the run hashed it, an edit made and undone included. A
# run handed to the PC passes --skip-passed on, and the PC reads its own ledger. A run with any *_TEST_CASE selector
# set records and reuses nothing. CI starts with no ledger, so its run is whole: the backstop for an input the map
# does not see (it reads hooks/ and scripts/ only).
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
# On a Mac: Homebrew's tools ahead of the system's, and out of its Bash 3.2 (requirements.sh).
. "$(dirname "$0")/requirements.sh"
# The tests, and this runner's mapfile and wait -n, need Bash 4: with no newer Bash to restart under, say so.
[ "${BASH_VERSINFO[0]}" -ge 4 ] || { echo "run-shell-tests: the tests need Bash 4 or newer and this is $BASH_VERSION; on a Mac: brew install bash" >&2; exit 2; }
ROOT=$(git rev-parse --show-toplevel)
HERE=$(cd "$(dirname "$0")" && pwd)
TIMEOUT=${COMMANDECK_SHELL_TEST_TIMEOUT:-120}
MAX_LINES=${COMMANDECK_SHELL_TEST_MAX_LINES:-500}
# Default jobs (#506): half the CPUs, one less when the machine is already busy (uptime's first load figure at or over
# the CPU count; one that cannot be read cuts nothing). On the PC (COMMANDECK_OFFLOADED), which runs the files slowest
# first: the CPUs less the load's integer part, at least a quarter of the CPUs (at least 1), at most the CPUs.
default_jobs() {
  local cores load floor
  cores=$(getconf _NPROCESSORS_ONLN) || cores=2
  load=$(LC_ALL=C uptime 2>/dev/null | sed -n 's/.*load averages*: *\([0-9][0-9]*\).*/\1/p')
  if [ -n "${COMMANDECK_OFFLOADED:-}" ]; then
    floor=$(( cores / 4 )); [ "$floor" -ge 1 ] || floor=1
    [[ $load =~ ^[0-9]+$ ]] || load=0
    load=$(( cores - 10#$load )); [ "$load" -ge "$floor" ] || load=$floor; [ "$load" -le "$cores" ] || load=$cores
    echo "$load"
  elif [ -n "$load" ] && [ "$load" -ge "$cores" ] 2>/dev/null; then echo $(( cores / 2 - 1 )); else echo $(( cores / 2 )); fi
}
JOBS=${COMMANDECK_SHELL_TEST_JOBS:-$(default_jobs)}
[ "$JOBS" -ge 1 ] 2>/dev/null || JOBS=1
# A python import in a test would write __pycache__ into a kept folder, and the fence would call it an edit to the tree.
export PYTHONDONTWRITEBYTECODE=1
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
# The hand-off to the PC below is decided from three of them, read before they are cleared: a run inside a test
# (COMMANDECK_HOOK_FIRE_LOG) and the run on the PC itself (COMMANDECK_OFFLOADED) never hand off again.
OFF_ENV=("COMMANDECK_HOOK_FIRE_LOG=${COMMANDECK_HOOK_FIRE_LOG:-}" "COMMANDECK_OFFLOADED=${COMMANDECK_OFFLOADED:-}" "COMMANDECK_HOST_OS=${COMMANDECK_HOST_OS:-}")
# Every other COMMANDECK_ variable the session or main-watch set too (main's pane folder, scratch, seat): the merge
# check runs in main's environment, and a test must see what CI gives it. Kept: CI's two and this runner's own.
unset CLAUDE_PROJECT_DIR CLAUDE_CONFIG_DIR
# Read before the loop below clears COMMANDECK_RUNNING_TEST: a run inside a test keeps the saved seconds out of it.
NESTED=${COMMANDECK_RUNNING_TEST:+1}
for v in $(compgen -e COMMANDECK_); do
  case $v in COMMANDECK_FOREGROUND|COMMANDECK_SHELL_TEST_*|COMMANDECK_TEST_NODE_MODULES|COMMANDECK_BREW_PREFIX) ;; *) unset "$v" ;; esac
done
TMPDIR=$(cd "${TMPDIR:-/tmp}" && pwd -P) || exit 2

ONLY_OWN_LANE=0 SKIP_PASSED=0
while :; do
  case ${1:-} in
    --own-lane) ONLY_OWN_LANE=1; shift ;;
    --skip-passed) SKIP_PASSED=1; shift ;;
    *) break ;;
  esac
done
# A partial-scope run, one with a test-case selector set (even to empty), neither records nor reuses a pass: a pass of
# one case says nothing about the whole file (Decision 12). --changed, --own-lane and named files all choose whole files.
PARTIAL=
for v in $(compgen -e); do case $v in *_TEST_CASE) PARTIAL=$v; break ;; esac; done
# TREE: the git tree of the working copy, untracked files included, hashed in a copy of the index; `-` when it cannot be.
# It is trusted only under the fence (Data design, "Fence"): this run's stamp is made, and one tick of the filesystem
# clock waited, before the hash, so any later change to a path of the tree has a newer ctime than the stamp. ctime moves
# on every write, create, delete, rename or revert, and no tool sets it back, so a fence that holds means the checkout
# is still exactly TREE, an edit made and undone in between included. The tree is never hashed again.
GD=$(git rev-parse --absolute-git-dir 2>/dev/null) || GD=
STAMP=$([ -n "$GD" ] && mktemp "$GD/commandeck-test-stamp.XXXXXX" 2>/dev/null) || STAMP=
trap '[ -z "$STAMP" ] || rm -f "$STAMP" "$STAMP".*' EXIT
# tick <stamp> -- waits until the clock is past <stamp>: the run's at the start, a test's own before its file.
tick() {
  local n t=$STAMP.tick$BASHPID
  for ((n = 0; n < 300; n++)); do
    touch "$t" && [ -n "$(find "$t" -newercc "$1" 2>/dev/null)" ] && return 0
    sleep 0.01
  done
  return 1
}
# keep_paths < <files> -- the fence's path list, NUL-separated: every file, every directory holding one, and the root.
keep_paths() {
  local f d
  local -A dirs=([.]=1)
  while IFS= read -r -d '' f; do
    printf './%s\0' "$f"
    d=$f
    while [[ $d == */* ]]; do d=${d%/*}; [ -z "${dirs[$d]:-}" ] || break; dirs[$d]=1; done
  done
  for d in "${!dirs[@]}"; do printf './%s\0' "$d"; done
}
# newer <file-stamp> <dir-stamp> < <paths> -- the paths whose ctime breaks the fence: a file newer than the first stamp,
# a directory newer than the second. A failed find (a vanished path) fails it.
newer() {
  xargs -0 sh -c 'f=$1 d=$2; shift 2; exec find "$@" -prune \( ! -type d -newercc "$f" -o -type d -newercc "$d" \) -print' sh "$1" "$2"
}
# untracked_dirs -- the folders no kept path names (pass 3 P2): each untracked tree git lists whole, an empty one
# included, and every folder under it, NUL-separated. A failed listing or find (a folder gone meanwhile) fails it.
untracked_dirs() (
  set -o pipefail
  git ls-files --others --exclude-standard --directory -z | while IFS= read -r -d '' p; do
    if [[ $p == */ ]]; then find "./${p%/}" -type d -print0 || exit 1; fi
  done
)
# fence_paths [<k>] -- the kept paths, and with k the untracked folders now in the checkout too.
fence_paths() { cat "$STAMP.paths" && { [ -z "${1-}" ] || untracked_dirs; }; }
# fence [<k>] -- 0 while the checkout is still TREE. With no k, no kept path has a newer ctime than the run's stamp. With
# k (test k's own run, D10), a file newer than the run's stamp breaks it, and so does a directory newer than test k's
# start stamp, a kept one or one git does not ignore that holds no kept file; a directory newer than only the run's
# stamp passes if the untracked files still equal $STAMP.others (a temp folder an earlier test made and removed). A
# missing stamp, a vanished path or a failed find or listing breaks it. The newer paths are left in FENCED for the message.
fence() {
  local out dirs own=$STAMP
  FENCED=
  [ -e "$STAMP" ] || return 1
  [ -z "${1-}" ] || own=$STAMP.t$1
  [ -e "$own" ] || return 1
  out=$(set -o pipefail; fence_paths "${1-}" | newer "$STAMP" "$own") || return 1
  [ -z "$out" ] || { FENCED=$out; return 1; }
  [ -n "${1-}" ] || return 0
  dirs=$(set -o pipefail; fence_paths "$1" | newer "$STAMP" "$STAMP" 2>/dev/null) || return 1
  [ -z "$dirs" ] || [ "$(git ls-files --others --exclude-standard -z | tr '\0' '\n')" = "$(tr '\0' '\n' < "$STAMP.others")" ] || { FENCED=$dirs; return 1; }
}
TREE=-
if [ -n "$STAMP" ] && tick "$STAMP"; then
  IDX=$STAMP.index
  if cp -p "$(git rev-parse --path-format=absolute --git-path index)" "$IDX" && GIT_INDEX_FILE=$IDX git add -A >/dev/null 2>&1 \
    && T=$(GIT_INDEX_FILE=$IDX git write-tree 2>/dev/null) && GIT_INDEX_FILE=$IDX git ls-files -z > "$STAMP.files" \
    && git ls-files --others --exclude-standard -z > "$STAMP.others" && keep_paths < "$STAMP.files" > "$STAMP.paths"; then TREE=$T; fi
fi
LEDGER=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/commandeck-test-runs.tsv || LEDGER=
# last_pass <rel> -- `<result>\t<tree>` of the ledger's last row for the file. A line that is not a whole row (not 4
# fields, or a first field that is not an ISO time: cut off mid-append, or glued to the next) clears every earlier
# pass, since the cut can fall inside a file name and name no file.
last_pass() {
  awk -F'\t' -v f="$1" '
    NF != 4 || $1 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/ { r = ""; next }
    $2 == f { r = $3 "\t" $4 }
    END { print r }' "$LEDGER" 2>/dev/null
}

SCOPE=
if [ "${1:-}" = --changed ]; then
  shift; CALLERS=0 BASE=HEAD
  for a in "$@"; do case $a in --callers) CALLERS=1 ;; *) BASE=$a ;; esac; done
  # An unknown base would select nothing and pass: fail instead.
  git rev-parse -q --verify "$BASE^{commit}" >/dev/null || { echo "run-shell-tests: --changed: no commit $BASE" >&2; exit 2; }
  # A deleted file selects nothing (--diff-filter=d). A failed git would also select nothing and pass: fail instead.
  CHANGED=$(git diff --name-only --diff-filter=d "$BASE" --) || { echo "run-shell-tests: --changed: git diff $BASE failed" >&2; exit 2; }
  # A shared helper's callers' tests are not run (main's ruling 2026-10-17): CI's full suite on every push covers them.
  # --callers adds them: every test that names a changed script or hook, a deleted one too (shell-tests-for.sh).
  mapfile -t TESTS < <({ printf '%s\n' "$CHANGED" | while IFS= read -r f; do
    case $f in
      (hooks/__tests__/*/*|scripts/__tests__/*/*) ;;
      (hooks/__tests__/*.test.sh|scripts/__tests__/*.test.sh) echo "$f" ;;
      # A test module runs through its same-name shell wrapper (dashboard-view.test.sh).
      (hooks/__tests__/*.test.mjs|scripts/__tests__/*.test.mjs) t=${f%.mjs}.sh; [ ! -f "$t" ] || echo "$t" ;;
      (hooks/*/*|scripts/*/*) ;;
      (hooks/*|scripts/*) t=${f%%/*}/__tests__/$(basename "${f%.*}").test.sh; [ ! -f "$t" ] || echo "$t" ;;
    esac
  done
  for t in hooks/__tests__/*.test.sh scripts/__tests__/*.test.sh; do
    [ -f "$t" ] || continue
    for p in $(sed -n '1,5p' "$t" | sed -n 's/^# covers: *//p'); do
      grep -qxF -- "$p" <<<"$CHANGED" && { echo "$t"; break; }
    done
  done
  if [ "$CALLERS" = 1 ]; then git diff --name-only "$BASE" -- | bash "$HERE/shell-tests-for.sh"; fi; } | sort -u)
  [ "${#TESTS[@]}" -gt 0 ] || { echo "run-shell-tests: no shell test was touched since $BASE"; exit 0; }
elif [ $# -gt 0 ] && [ "$1" != --list ]; then
  # Named files are relative to where the caller stood, not to $ROOT.
  mapfile -t TESTS < <(for f in "$@"; do case $f in (/*) echo "$f" ;; (*) echo "$CALLER_PWD/$f" ;; esac; done | sort)
else
  SCOPE=whole
  mapfile -t TESTS < <(ls hooks/__tests__/*.test.sh scripts/__tests__/*.test.sh 2>/dev/null | sort)
fi
[ "${#TESTS[@]}" -gt 0 ] || { echo "run-shell-tests: found no test files" >&2; exit 2; }
[ "${1:-}" = --list ] && { printf '%s\n' "${TESTS[@]}"; exit 0; }

# In a Mac linked worktree whose chain host is the PC the files go there (peer-offload.sh, owner ruling 2026-10-25),
# all but those marked `# host: mac` in their first five lines, which run here below. The hand-off's exit code is its
# whole outcome, from a fixed list (Decision G13-3, revision 7): only 3 (not routed) and 4 (unreachable: no peer, or the
# PC asleep) run the files here, once. 2 (refused there, or the hand-off failed here) runs nothing here and exits 2.
# Every other code is final, a red run or a lost connection included. The PC never hands off, and the main checkout
# hands off only a whole-suite run. A whole-suite run (SCOPE=whole) sets PO_WHOLE: on a Mac with a peer configured it
# goes to the PC whatever the chain host, as the bare command when no file stays here, so the PC orders and saves its
# own seconds, and with the PC unreachable (4) it refuses; with no peer it runs here (3).
OFF_RC=0 OFFLOADED=0
MACF=() RESTF=()
ROOTP=$(pwd -P)
for t in "${TESTS[@]}"; do
  phys=$(cd "$(dirname "$t")" 2>/dev/null && pwd -P)/$(basename "$t")
  if [[ $phys == "$ROOTP"/* ]] && ! sed -n '1,5p' "$t" | grep -q '^# host: *mac *$'; then RESTF+=("${phys#"$ROOTP"/}"); else MACF+=("$t"); fi
done
if [ "${#RESTF[@]}" -gt 0 ]; then
  OFFARGS=(bash scripts/run-shell-tests.sh); [ "$ONLY_OWN_LANE" = 0 ] || OFFARGS+=(--own-lane); [ "$SKIP_PASSED" = 0 ] || OFFARGS+=(--skip-passed)
  # A whole run with no file kept here sends the bare command, so the PC's run is whole-scope too.
  [ "$SCOPE" = whole ] && [ "${#MACF[@]}" = 0 ] && RESTF=()
  # A subshell: host-services.sh, which peer-offload.sh loads, exports what the tests must not inherit.
  ( export "${OFF_ENV[@]}"; . "$HERE/peer-offload.sh" || { echo "run-shell-tests: $HERE/peer-offload.sh did not load" >&2; exit 2; }
    PO_WHOLE=; [ "$SCOPE" != whole ] || PO_WHOLE=1
    pr_offload "${OFFARGS[@]}" ${RESTF[@]+"${RESTF[@]}"}; rc=$?
    [ "$rc" != 4 ] || [ -z "$PO_WHOLE" ] || echo "run-shell-tests: the PC ($(pr_peer)) cannot be reached, and a whole-suite run with a peer configured runs only there; nothing ran. Wake the PC, or run named files or --changed here" >&2
    exit "$rc" )
  OFF_RC=$?
  case $OFF_RC in
    3) OFF_RC=0 ;;
    4) [ "$SCOPE" != whole ] || exit 2
       echo "run-shell-tests: running here, once"; OFF_RC=0 ;;
    2) echo "run-shell-tests: the hand-off to the PC was refused or failed (reason above); nothing ran here" >&2; exit 2 ;;
    *) OFFLOADED=1 TESTS=(${MACF[@]+"${MACF[@]}"})
       [ "${#TESTS[@]}" -gt 0 ] || exit "$OFF_RC" ;;
  esac
fi

# KEY: each local file's ledger key (issue 667), the hash of its inputs' `git ls-files -s` lines in this run's index
# copy, or TREE where the map is uncertain or the file is outside the checkout. Read under the same fence as TREE.
declare -A KEY=()
if [ -z "$PARTIAL" ] && [ -n "$LEDGER" ] && [ "$TREE" != - ] && [ "${#TESTS[@]}" -gt 0 ]; then
  KRELS=()
  for t in "${TESTS[@]}"; do
    phys=$(cd "$(dirname "$t")" 2>/dev/null && pwd -P)/$(basename "$t"); [[ $phys == "$ROOTP"/* ]] && KRELS+=("${phys#"$ROOTP"/}")
  done
  while IFS=$'\t' read -r f rest; do
    # No newline after the last path (it would name no file); an empty listing (no input in the index) keys on TREE.
    k=; [ "$rest" = '?' ] || k=$(printf '%s' "$rest" | tr '\t' '\0' | GIT_INDEX_FILE=$IDX xargs -0 git ls-files -s --)
    [ -n "$k" ] && k=$(git hash-object --stdin <<<"$k") && [ -n "$k" ] || k=$TREE
    KEY[$f]=$k
  done < <([ "${#KRELS[@]}" = 0 ] || bash "$HERE/test-inputs.sh" --list "${KRELS[@]}")
fi
# --skip-passed reads TESTS as the hand-off left it: a file the PC took is the PC's to skip, from the PC's own ledger
# (the PC returns one exit code, no per-file result, so the Mac records no row for it). Only a file this run would
# launch is skipped here.
SAMEPASS=0 SAME=()
if [ "$SKIP_PASSED" = 1 ] && [ -n "$PARTIAL" ]; then
  echo "run-shell-tests: a test-case selector is set ($PARTIAL); --skip-passed reuses and records nothing"
elif [ "$SKIP_PASSED" = 1 ] && [ "$TREE" != - ] && [ -n "$LEDGER" ]; then
  for i in "${!TESTS[@]}"; do
    t=${TESTS[$i]}
    sed -n '1,5p' "$t" | grep -q '^# parked:' && continue
    if sed -n '1,5p' "$t" | grep -q '^# own-lane:'; then [ "$ONLY_OWN_LANE" = 1 ] || continue
    else [ "$ONLY_OWN_LANE" = 0 ] || continue; fi
    phys=$(cd "$(dirname "$t")" && pwd -P)/$(basename "$t")
    IFS=$'\t' read -r res tree < <(last_pass "${phys#"$ROOTP"/}")
    [ "$res" = ok ] && [ "${tree:-}" = "${KEY[${phys#"$ROOTP"/}]:-$TREE}" ] || continue
    SAME+=("$i")
  done
  # Any change to the tree since the stamp, undone or not, makes every candidate stale: reuse none, and record nothing.
  if [ "${#SAME[@]}" -gt 0 ] && ! fence; then
    TREE=-; echo "run-shell-tests: the tree changed while checking earlier passes; nothing is reused or recorded"
  else
    for i in ${SAME[@]+"${SAME[@]}"}; do
      # The runner's own result line, 0 seconds: every reader of `-- ok` lines counts it as a finished file.
      printf -- '-- ok   %-58s %ss (passed at this tree in an earlier run)\n' "$(basename "${TESTS[$i]}")" 0
      SAMEPASS=$((SAMEPASS + 1)); unset "TESTS[$i]"
    done
    TESTS=(${TESTS[@]+"${TESTS[@]}"})
  fi
fi

RES=$(mktemp -d) || exit 2
# The live record of this run, for the units mod (issue 349): `run <start> <jobs>`, `file <rel>` for every selected
# file, then `start <rel> <time>` and `end <rel> <ok|FAIL|skip> <secs>` as each file launches and ends. One
# tab-joined printf per line, so parallel files cannot interleave inside one. Gone when the run exits.
[ -n "$GD" ] && mkdir -p "$GD/commandeck-test-live" 2>/dev/null && LIVE=$GD/commandeck-test-live/$$.tsv || LIVE=
trap 'rm -rf "$RES"; [ -z "$LIVE" ] || rm -f "$LIVE"; [ -z "$STAMP" ] || rm -f "$STAMP" "$STAMP".*' EXIT
live() { [ -z "$LIVE" ] || { local IFS=$'\t'; printf '%s\n' "$*" >> "$LIVE"; } 2>/dev/null || true; }
# A real hook run by a test must not count as a real fire.
export COMMANDECK_HOOK_FIRE_LOG="$RES/hook-fire-log.jsonl"
# A test with no orca-ide stub of its own must not close a real pane (host issue 3009): this stub, first on PATH,
# refuses `terminal close` and names the test file; every other subcommand reaches the real binary, resolved before
# the PATH change. A test's own stub, prepended later, still wins. Ceiling: it sees only tests run through this script.
mkdir -p "$RES/stubbin"
{ printf '#!/usr/bin/env bash\nREAL=%q\n' "$(command -v orca-ide 2>/dev/null)"
  cat <<'STUB'
if [ "${1-} ${2-}" = "terminal close" ]; then
  echo "run-shell-tests: unstubbed 'orca-ide $*' refused in ${COMMANDECK_RUNNING_TEST:-a test}; give that test its own orca-ide stub" >&2
  echo '{"ok":false,"error":{"code":"test-unstubbed-close"}}'; exit 1
fi
[ -n "$REAL" ] || { echo "orca-ide: command not found" >&2; exit 127; }
exec "$REAL" "$@"
STUB
} > "$RES/stubbin/orca-ide"
chmod +x "$RES/stubbin/orca-ide"
export PATH="$RES/stubbin:$PATH"
# bound <cap> -- `<limit> <load1> <cores>` (#506, D11): a file's cap times the load factor min(4, max(1, load1 / cores)),
# rounded up to a whole second, read as the file starts. On an idle machine (or a load that cannot be read) it is the cap.
bound() {
  local cores load
  cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null) || cores=
  load=$(LC_ALL=C uptime 2>/dev/null | sed -n 's/.*load averages*: *\([0-9][0-9]*\(\.[0-9]*\)\{0,1\}\).*/\1/p')
  awk -v cap="$1" -v l="${load:-0}" -v c="${cores:-0}" 'BEGIN { f = c > 0 ? l / c : 1; if (f < 1) f = 1; if (f > 4) f = 4
    n = cap * f; r = int(n); if (r < n) r++; printf "%d %s %s\n", r, l, c }'
}
run_one() {
  local start rc secs line lim load cores
  start=$(date +%s)
  read -r lim load cores <<<"$(bound "${CAP[$1]}")"
  live start "${REL[$1]}" "$start"
  # This test's own start stamp, ticked past, so fence "$1" judges the test on its own run (D10).
  [ -z "$STAMP" ] || { touch "$STAMP.t$1" && tick "$STAMP.t$1"; } || rm -f "$STAMP.t$1"
  # COMMANDECK_TEST_RUNNER is the marker test-host-guard.sh (BASH_ENV, issue 665) takes for a run the runner started.
  # review-round.sh's default self-review is a REAL Codex review: every test
  # sets its own stub, and one that does not runs this poison and fails below.
  # Past its cap on a busy machine a file passes only on its CPU seconds: bash's `times` in a subshell around the run
  # counts the file's reaped processes (`0m1.690s 0m0.089s`, user and system).
  ( COMMANDECK_RUNNING_TEST="$2" COMMANDECK_SELF_REVIEW_CMD="touch '$RES/$1.companion'; exit 97" \
      COMMANDECK_TEST_RUNNER=1 timeout "$lim" bash "$2" > "$RES/$1.out" 2>&1; rc=$?; times > "$RES/$1.cpu"; exit "$rc" ); rc=$?
  secs=$(( $(date +%s) - start ))
  sed -n 2p "$RES/$1.cpu" | awk '{ t = 0; for (i = 1; i <= 2; i++) { split($i, a, /[ms]/); t += a[1] * 60 + a[2] } printf "%.2f\n", t }' > "$RES/$1.cpu.tmp" \
    && mv "$RES/$1.cpu.tmp" "$RES/$1.cpu" || rm -f "$RES/$1.cpu"
  echo "$rc $secs $lim $load $cores" > "$RES/$1.rc"
  line=$(status_line "$1")
  live end "${REL[$1]}" "${line%% *}" "$secs"
  # The ledger --skip-passed reads: one row per local file, one printf each (an append under 4 KB is atomic).
  # A row at a tree the test did not run on would let --skip-passed reuse a result of other inputs; `-` is no tree. The
  # row's last field is the file's KEY (its inputs' hash, or TREE).
  # The fence holding after the file ended proves it read exactly TREE.
  if [ -z "$PARTIAL" ] && [ -n "$LEDGER" ] && [ "$TREE" != - ]; then
    if fence "$1"; then printf '%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${REL[$1]}" "${line%% *}" "${KEY[${REL[$1]}]:-$TREE}" >> "$LEDGER" 2>/dev/null
    else printf 'run-shell-tests: the tree changed while %s ran; its result is not recorded\n' "${REL[$1]}"
      [ -z "$FENCED" ] || printf 'run-shell-tests: newer: %s\n' "${FENCED//$'\n'/ }"; fi
  fi
  # One printf per line: parallel files then cannot interleave inside a line.
  printf -- '-- %s\n' "$line"
}
# The result line of finished test $1. The live `-- ` line and the sorted
# report both print it, so the two cannot drift.
# A file that ran past its cap (only a busy machine lets it) says so, and passes only with exit 0 and its CPU at or under
# the cap; a missing CPU count does not pass.
status_line() {
  local rc secs lim load cores cpu why past=
  read -r rc secs lim load cores < "$RES/$1.rc"
  cpu=$(cat "$RES/$1.cpu" 2>/dev/null) || cpu=
  [ "$secs" -le "${CAP[$1]}" ] || past="past its ${CAP[$1]} s cap: $secs s wall, ${cpu:-no} s CPU"
  if [ -e "$RES/$1.companion" ]; then why="ran the Codex companion path: set COMMANDECK_SELF_REVIEW_CMD to a stub"
  elif [ "$rc" -eq 0 ] && { [ -z "$past" ] || awk -v c="${cpu:-x}" -v m="${CAP[$1]}" 'BEGIN { exit !(c ~ /^[0-9.]+$/ && c + 0 <= m) }'; }; then
    printf 'ok   %-58s %ss%s' "$(basename "${TESTS[$1]}")" "$secs" "${past:+ $past}"; return
  elif [ "$rc" -eq 124 ]; then why="HUNG past ${lim}s"; [ "$lim" = "${CAP[$1]}" ] || why+=" (load $load on $cores cores)"
  elif [ "$rc" -eq 0 ]; then why=$past
  else why="rc=$rc${past:+, $past}"; fi
  printf 'FAIL %-58s %ss %s' "$(basename "${TESTS[$1]}")" "$secs" "$why"
}

# Selection pass: skips are decided here, so the live record can list every selected file before the first launch.
SKIPWHY=() CAP=() EXCL=() REL=() SEL=() RUN=() OVER=()
for i in "${!TESTS[@]}"; do
  t=${TESTS[$i]}
  parked=$(sed -n '1,5p' "$t" | sed -n 's/^# parked: *//p' | head -1)
  own_lane=$(sed -n '1,5p' "$t" | sed -n 's/^# own-lane: *//p' | head -1)
  if [ -n "$parked" ]; then SKIPWHY[i]=$parked
  elif [ "$ONLY_OWN_LANE" = 1 ]; then
    # Not this lane's file: neither run nor counted, so the report below does not read its missing result as a failure.
    [ -n "$own_lane" ] || { EXCL[i]=1; continue; }
  elif [ -n "$own_lane" ]; then SKIPWHY[i]="own lane: $own_lane"
  fi
  phys=$(cd "$(dirname "$t")" && pwd -P)/$(basename "$t")
  REL[i]=${phys#"$ROOTP"/}; SEL+=("$i")
  if [ -n "${SKIPWHY[i]:-}" ]; then
    printf -- '-- skip %-58s %s\n' "$(basename "$t")" "${SKIPWHY[i]}"; continue
  fi
  # A shell test file regrew past the cap with nobody told (issue 436): it fails before it runs, and the report names
  # the cap.
  case $t in *.test.sh) [ "$(wc -l < "$t")" -le "$MAX_LINES" ] || { OVER[i]=1; continue; } ;; esac
  cap=$(sed -n '1,5p' "$t" | sed -n 's/^# timeout: *\([0-9][0-9]*\).*/\1/p' | head -1)
  CAP[i]=${cap:-$TIMEOUT}; RUN+=("$i")
done
SECS_FILE=${COMMANDECK_SHELL_TEST_SECONDS:-}
[ -n "$SECS_FILE" ] || [ -n "$NESTED" ] || SECS_FILE=$HOME/.commandeck/shell-test-seconds.tsv
declare -A SAVED=()
# read_seconds -- fill SAVED from the list; a row of any other shape is skipped. Status 1: the list is there and unreadable.
read_seconds() {
  local line tab=$'\t' re
  SAVED=()
  [ -n "$SECS_FILE" ] && [ -e "$SECS_FILE" ] || return 0
  [ -f "$SECS_FILE" ] && [ -r "$SECS_FILE" ] || return 1
  re="^([0-9]+)$tab([^$tab/]+)\$"
  while IFS= read -r line; do
    [[ $line =~ $re ]] && SAVED[${BASH_REMATCH[2]}]=${BASH_REMATCH[1]}
  done < "$SECS_FILE"
  return 0
}
# save_seconds -- this run's seconds over the list as it stands now, through a temp file and a rename so a reader never
# sees half of it. Only a whole-scope run saves. Two saves together lose one run's rows; the next run relearns them.
# A failure prints one line and never changes the exit.
save_seconds() {
  local i b tmp why=
  local -A LIVE=()
  [ -n "$SECS_FILE" ] && [ "$SCOPE" = whole ] && [ "$ONLY_OWN_LANE" = 0 ] && [ "$OFFLOADED" = 0 ] && [ -z "$PARTIAL" ] || return 0
  read_seconds || SAVED=()
  for i in ${RUN[@]+"${RUN[@]}"}; do
    [ -f "$RES/$i.rc" ] || continue
    read -r _ SAVED["$(basename "${TESTS[$i]}")"] _ < "$RES/$i.rc"
  done
  for i in "${!TESTS[@]}"; do LIVE[$(basename "${TESTS[$i]}")]=1; done
  if [ -d "$SECS_FILE" ]; then why="$SECS_FILE is a directory"
  elif ! mkdir -p "$(dirname "$SECS_FILE")" 2>/dev/null; then why="cannot create $(dirname "$SECS_FILE")"
  elif ! tmp=$(mktemp "$SECS_FILE.XXXXXX" 2>/dev/null); then why="cannot write in $(dirname "$SECS_FILE")"
  else
    for b in "${!SAVED[@]}"; do [ -z "${LIVE[$b]:-}" ] || printf '%s\t%s\n' "${SAVED[$b]}" "$b"; done > "$tmp" \
      && mv -f "$tmp" "$SECS_FILE" || { why="cannot replace $SECS_FILE"; rm -f "$tmp"; }
  fi
  [ -z "$why" ] || echo "run-shell-tests: could not save durations: $why" >&2
  return 0
}
if ! read_seconds; then echo "run-shell-tests: cannot read $SECS_FILE; starting files in sorted order" >&2; fi
if [ "${#SAVED[@]}" -gt 0 ] && [ "${#RUN[@]}" -gt 0 ]; then
  mapfile -t RUN < <(for i in "${RUN[@]}"; do b=$(basename "${TESTS[$i]}"); printf '%s\t%s\n' "${SAVED[$b]:--1}" "$i"; done | sort -s -t$'\t' -k1,1nr | cut -f2)
fi
live run "$(date +%s)" "$JOBS"
echo "run-shell-tests: $JOBS jobs"
for i in ${SEL[@]+"${SEL[@]}"}; do live file "${REL[i]}"; done
for i in ${SEL[@]+"${SEL[@]}"}; do [ -z "${SKIPWHY[i]:-}" ] || live end "${REL[i]}" skip 0; done
for i in ${SEL[@]+"${SEL[@]}"}; do [ -z "${OVER[i]:-}" ] || live end "${REL[i]}" FAIL 0; done
# Launch pass: runnable tests go to the background.
for i in ${RUN[@]+"${RUN[@]}"}; do
  while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n; done
  run_one "$i" "${TESTS[$i]}" &
done
wait

# Report pass, in sorted order whatever order the tests finished in.
PASS=$SAMEPASS FAIL=0 SKIP=0 FAILED=()
for i in "${!TESTS[@]}"; do
  t=${TESTS[$i]}
  [ -z "${EXCL[i]:-}" ] || continue
  if [ -n "${SKIPWHY[i]:-}" ]; then
    SKIP=$((SKIP + 1)); printf 'skip %-58s %s\n' "$(basename "$t")" "${SKIPWHY[i]}"; continue
  fi
  if [ -n "${OVER[i]:-}" ]; then
    FAIL=$((FAIL + 1)); FAILED+=("$t")
    printf 'FAIL %s over the %s-line cap for one shell test file: split it by section\n' "$(basename "$t")" "$MAX_LINES"; continue
  fi
  # No result file: the run was killed, or its result could not be written. A failure, never a skip.
  if [ ! -f "$RES/$i.rc" ]; then
    FAIL=$((FAIL + 1)); FAILED+=("$t"); printf 'FAIL %-58s no result: its run was killed or its result not written\n' "$(basename "$t")"; continue
  fi
  line=$(status_line "$i"); printf '%s\n' "$line"
  case $line in
    ok*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); FAILED+=("$t")
       # Every failed case by name first: one that failed early is above the tail (issue 268).
       [ -e "$RES/$i.companion" ] || { grep '^FAIL ' "$RES/$i.out" | head -20; tail -12 "$RES/$i.out"; } | sed 's/^/       /' ;;
  esac
done
save_seconds

echo
# Anti-vacuity: an own-lane run that matched nothing means the marker was
# removed or renamed, and the lane would pass while testing nothing.
[ "$ONLY_OWN_LANE" = 0 ] || [ "$OFFLOADED" = 1 ] || [ $((PASS + FAIL)) -gt 0 ] || {
  echo "run-shell-tests: --own-lane matched no test; is the # own-lane: marker still there?" >&2
  exit 2
}
echo "$PASS passed, $FAIL failed, $SKIP parked"
[ "$FAIL" -eq 0 ] || { echo "failed:"; printf '  %s\n' "${FAILED[@]}"; }
# Issue 667: never a full retest. The retry is this one command, the failed files only, by their repository paths.
if [ "$FAIL" -gt 0 ]; then
  # An ordinary run skips an own-lane file, so the lane flag goes with the retry.
  RERUN="rerun only the failed files: bash scripts/run-shell-tests.sh"; [ "$ONLY_OWN_LANE" = 0 ] || RERUN+=" --own-lane"
  for t in "${FAILED[@]}"; do p=$(cd "$(dirname "$t")" 2>/dev/null && pwd -P)/$(basename "$t"); RERUN+=" $(printf '%q' "${p#"$ROOTP"/}")"; done
  echo "$RERUN"
fi
[ "$OFF_RC" = 0 ] || echo "the files run on the PC ended $OFF_RC (above)"
[ "$FAIL" -eq 0 ] && [ "$OFF_RC" = 0 ]

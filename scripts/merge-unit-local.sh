#!/usr/bin/env bash
# merge-unit-local.sh <unit> [--dry-run]
# Squash-merge a Builder's branch onto local main, without a PR and without a
# push. The one gate is the Builder proof (builder-codex-pass.sh --verify): the
# last round file must be the pass script's, GO, for the tip being merged. The
# project's check command (.claude/commandeck.json testCommand) then runs once
# on a copy of the squashed tree; a red check undoes the squash.
# Self-test: bash scripts/__tests__/merge-unit-local.test.sh; the reuse of a tested tree: bash scripts/__tests__/merge-queue.test.sh
set -euo pipefail
# Issue 310: when this script lives in a git checkout that is a main worktree on main, that checkout is the project, wherever
# the merge is run from. Anywhere else (an installed copy) the cwd rules. SELF is absolute: every re-exec below uses it.
SELF=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/${BASH_SOURCE[0]##*/}
if SELF_TOP=$(git -C "${SELF%/*}" rev-parse --show-toplevel 2>/dev/null) \
   && [ "$(git -C "$SELF_TOP" rev-parse --path-format=absolute --git-dir)" = "$(git -C "$SELF_TOP" rev-parse --path-format=absolute --git-common-dir)" ] \
   && [ "$(git -C "$SELF_TOP" branch --show-current)" = main ]; then cd "$SELF_TOP"; fi
# Two Builders finishing minutes apart would rebase and squash onto the same
# index of the ONE main checkout. Serialise them: the second caller waits, then
# rebases onto the first one's merge. Re-exec before arg parsing so every flag
# survives.
usage() { cat <<'EOF'
usage: merge-unit-local.sh <unit> [--dry-run] [--auto <sha>] [--filed '<class>=#<n>' ...] | <unit> --cleanup
Squash-merge a Builder's branch onto local main; run from the main checkout on main.
  --dry-run        run the checks and print the plan; merge and clean up nothing
  --auto <sha>     merge only while the branch tip is still <sha>, the commit main-watch's gate passed
  --filed '<class>=#<n>'
                   the OPEN issue that tracks one class of the findings the review left open at its stop
                   (builder-codex-pass.sh --verify lists them as Open finding lines); one per open class
  --cleanup        step 5 alone, for a unit main already holds (a held cleanup's retry): close its panes, archive
                   its briefs, remove its worktree; holds (exit 5) while a pane is listed or a path is uncommitted,
                   refuses (exit 1) a unit main does not hold
The brief's "## Post-merge" lines run once the merge stands, each as a job of its own, and only these:
dashboard.sh --install, main-watch.sh --install, run-shell-tests.sh <one test file>.
exit: 0 merged; 1 refused or failed, not merged; 2 usage; 3 MERGED, but a step after the
      merge commit failed (archiving the unit's brief files, or closing its panes and removing
      its worktree): finish it by hand, do not merge again; 5 MERGED, but a post-merge line was refused or its step failed,
      or the worktree held uncommitted work (or a pane that would not close) and was kept (named on the DONE line)
      4 a merge of this unit at this sha is already running or waiting (issue 317): nothing was queued; wait for that one, never run this again
example: merge-unit-local.sh my-unit --dry-run
EOF
}
# Before the lock: a usage error must not wait behind a running merge.
case "${1:-}" in --help|-h) usage; exit 0 ;; "") usage >&2; exit 2 ;; esac
# Issue 317: the same unit at the same sha, merging or waiting on the lock below, is never run twice: exit 4, saying so.
# The sha is --auto's, else the unit worktree's tip; a unit that cannot be read here is left to step 1 to refuse.
# A dry run is no request, nor is a --cleanup (it merges nothing). In main's own foreground the merge restarts itself detached and returns at once (issue 230).
# The request is queued BEFORE it detaches: a second one is refused here, at once, and never starts a run that would
# empty the first one's log. The detached run is handed its queue entry (MERGE_UNIT_LOCAL_QUEUE) and holds it by pid.
QFILE=${MERGE_UNIT_LOCAL_QUEUE:-}
if [ -z "${MERGE_UNIT_LOCAL_LOCK:-}" ] && [[ $1 =~ ^[A-Za-z0-9._-]+$ ]] && ! printf '%s\n' "$@" | grep -xE -- '--dry-run|--cleanup' >/dev/null \
   && ROOT=$(git rev-parse --show-toplevel 2>/dev/null) && COMMANDECK_MAIN=$ROOT . "${SELF%/*}/paths.sh"; then
  REQ=$(printf '%s\n' "$@" | grep -x -A1 -- --auto | sed -n 2p || true)
  [[ ${REQ:-HEAD} =~ ^([0-9a-f]{7,40}|HEAD)$ ]] && REQ=$(git -C "$PP_WORKSPACES/$1" rev-parse --verify -q "${REQ:-HEAD}^{commit}" 2>/dev/null) || REQ=
  if [ -n "$REQ" ] && [ -z "$QFILE" ]; then
    if DUP=$(pp_merge_active "$1" "$REQ" --register); then echo "$DUP; no second run was queued (exit 4). Wait for it: its log, and the message it sends main when it ends."; exit 4
    elif [ $? != 1 ]; then echo "REFUSED: the merge queue's lock stayed busy 10 s (or its folder could not be made), so $1 was not queued; nothing ran. Run it again." >&2; exit 1; fi
    QFILE=$(git -C "$PP_MAIN" rev-parse --path-format=absolute --git-common-dir)/merge-unit-local.queue/$1@$REQ
  fi
  if pp_main_foreground; then
    MERGE_UNIT_LOCAL_QUEUE=$QFILE pp_detach "$PP_SCRATCH/merge-$1.log" "merge-unit-local.sh $1" bash "$SELF" "$@" || exit
    # shortcut: a detached run that leaves the queue before this line is re-entered under its wrapper's pid, which
    # refuses only this unit at this sha until that wrapper has sent main its result; fine while merges take seconds+.
    [ -z "$QFILE" ] || { echo $! > "$QFILE.$$" && mv -f "$QFILE.$$" "$QFILE"; }; exit
  fi
fi
if [ -z "${MERGE_UNIT_LOCAL_LOCK:-}" ]; then
  # -o: a child the merge leaves running (a test command's) must not keep the lock after the merge ends (issue 301).
  exec env MERGE_UNIT_LOCAL_LOCK=1 MERGE_UNIT_LOCAL_QUEUE="$QFILE" flock -o \
    "$(git rev-parse --path-format=absolute --git-common-dir)/merge-unit-local.lock" "$SELF" "$@"
fi
UNIT=$1; shift
DRY_RUN=0 AUTO="" CLEANUP=0 FILED=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --auto) AUTO=${2:-}; [[ $AUTO =~ ^[0-9a-f]{7,40}$ ]] || { usage >&2; exit 2; }; shift 2 ;;
    --filed) [[ ${2:-} =~ ^[^=[:space:]]+=#[0-9]+$ ]] || { usage >&2; exit 2; }; FILED+=("$2"); shift 2 ;;
    --cleanup) CLEANUP=1; shift ;;
    *) usage >&2; exit 2 ;;
  esac
done
[ "$CLEANUP" = 0 ] || [ "$DRY_RUN$AUTO" = 0 ] || { usage >&2; exit 2; }
[[ "$UNIT" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "invalid unit: $UNIT" >&2; exit 2; }
# Issue 349: each attempt that took the lock opens its output with this line, so a log many attempts were appended to
# (merge-queue.sh) can be split into attempts; the units mod reads the newest attempt only.
[ "$DRY_RUN" = 1 ] || echo "ATTEMPT unit=$UNIT pid=$$ started=$(date +%s)"
fail() { echo "FAILED $1: $2" >&2; exit 1; }
ROOT=$(git rev-parse --show-toplevel) || fail "step 1 preconditions" "not in a git checkout"
[ "$(git rev-parse --path-format=absolute --git-dir)" = "$(git rev-parse --path-format=absolute --git-common-dir)" ] \
  || fail "step 1 preconditions" "run from the main checkout, not a linked worktree"
[ "$(git branch --show-current)" = main ] || fail "step 1 preconditions" "main checkout must be on branch main"
HERE=${SELF%/*}
# The project is the checkout the merge runs in, not the one the plugin lives in.
COMMANDECK_MAIN=$ROOT . "$HERE/paths.sh"
# Issue 317: while this merge holds main it writes its state beside the lock (pp_merge_active reads it, so does the
# main-merge-guard hook and the orchestrator's rules), and removes it, and its place in the queue, on every way out:
# the traps below end with release. A killed merge leaves a file whose pid is dead, which blocks nothing.
STATE=$(git rev-parse --path-format=absolute --git-common-dir)/merge-unit-local.state
state() { # <stage>
  [ "$DRY_RUN" = 0 ] || return 0
  printf 'unit=%s\nsha=%s\ntip=%s\npid=%s\nstarted=%s\nstage=%s\nmain=%s\nlog=%s\n' "$UNIT" "$PRE_TIP" "${TIP:-$PRE_TIP}" "$$" "$STARTED" "$1" "$ROOT" "$PP_SCRATCH/merge-$UNIT.log" \
    > "$STATE.$$" && mv -f "$STATE.$$" "$STATE"
}
release() {
  rm -f "${MERGE_UNIT_LOCAL_QUEUE:-}" "$STATE.$$"
  [ "$(sed -n 's/^pid=//p' "$STATE" 2>/dev/null)" != "$$" ] || rm -f "$STATE"
}
trap release EXIT
. "$HERE/../hooks/lib/project.sh"; pp_project "$ROOT"
pp_unit_name "$UNIT" || fail "step 1 preconditions" "the unit's name (above)"
WT=$PP_WORKSPACES/$UNIT
BRIEF=$WT/.claude/briefs/$UNIT.md
WTID="path:$WT"
[ -d "$WT" ] || fail "step 1 preconditions" "worktree does not exist: $WT"
# Step 5 removes this folder: a checkout of its own (a .git folder, not a linked worktree's .git file) never gets there.
[ -f "$WT/.git" ] || fail "step 1 preconditions" "$WT is not a linked worktree (its .git is not a file), and step 5 would remove it"
CLEANUP_HELD="" PANE_STUCK=""
# Step 5 keeps the worktree when it holds work the merge does not (host issue 3028): the DONE line names why and the
# retry, which closes the panes again and removes the worktree only once nothing holds it. It never says force-remove.
hold() { CLEANUP_HELD="$WT kept, $1; close the unit's panes and commit or move what is named, then run bash $(printf %q "$SELF") $UNIT --cleanup"; }
# Step 5 deletes the worktree, so it fails toward KEEPING it (host issue 3028). In order: stop the writers (the
# unit's panes, then its Codex helpers; a pane that will not close holds, and nothing is archived or removed), then
# archive the worktree's brief files (.claude/briefs/ is ignored, so no status check sees a write there: with no live
# writer left, none can come after this), then any path `git status` still lists holds, a deletion excepted (its
# bytes are in the merged HEAD). A hold keeps the worktree and the DONE line says why; the merge stands.
# Limit: ignored files still go with the forced remove, and a background process a pane started is not stopped.
# `terminal close --worktree --all` reports terminal_close_incomplete for a finished reviewer pane; closing by
# handle succeeds every time. Reads ARCHIVE, KEPT and MAIN_FILES (step 4's, or --cleanup's own).
cleanup_step() {
  echo "STEP 5 cleanup: close the unit's panes by handle (logged in pane-closes.log), stop its Codex helpers, archive its briefs, then orca-ide worktree remove --worktree $WTID --force"
  state cleanup
  # The listing is read and checked first: a failed, empty or malformed one lists no pane, and no pane listed is not
  # no writer, so it holds like a refused close. A close that answered ok is not a pane gone either: the proof is the
  # listing read again after the closes, through the same reader, with no pane of the worktree in it.
  if PANES=$(pp_worktree_panes "$WT"); then
    while IFS= read -r h; do
      [ -n "$h" ] || continue
      pp_pane_close "$h" "merge cleanup" || { echo "pane $h did not close" >&2; PANE_STUCK="a pane did not close"; }
    done <<<"$PANES"
  else PANE_STUCK="the pane list could not be read"; fi
  bash "$HERE/codex-helpers.sh" stop "$WT" || true
  if [ -z "$PANE_STUCK" ]; then
    if ! LEFT=$(pp_worktree_panes "$WT"); then PANE_STUCK="the pane list could not be read after the close"
    elif [ -n "$LEFT" ]; then PANE_STUCK="still listed after the close: $(tr '\n' ' ' <<<"$LEFT" | sed 's/ $//')"; fi
  fi
  if [ -n "$PANE_STUCK" ]; then hold "$PANE_STUCK, brief files not archived"
  else
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      tar -C "$(dirname "$f")" -rf "$ARCHIVE" -- "$(basename "$f")" || fail "step 4 briefs" "could not append $(basename "$f") to $ARCHIVE"
      KEPT=$((KEPT + 1))
    done < <(pp_unit_briefs "$WT/.claude/briefs" "$UNIT")
    [ "${#MAIN_FILES[@]}" = 0 ] || rm -- "${MAIN_FILES[@]}" || fail "step 4 briefs" "could not remove the archived main brief files"
    echo "step 4 briefs: added $KEPT entries to $ARCHIVE"
    held=()
    if st=$(git -C "$WT" status --porcelain --no-renames --untracked-files=all 2>/dev/null); then
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        case ${line:0:2} in ' D'|'D ') continue ;; esac
        # Untracked brief files are the ones just archived (step 1 lets them be).
        case $line in '?? .claude/briefs/'*) continue ;; esac
        held+=("${line:3}")
      done <<<"$st"
      [ "${#held[@]}" = 0 ] || hold "${#held[@]} uncommitted path(s): $(printf '%s, ' "${held[@]:0:3}" | sed 's/, $//')"
    else hold "git status failed"; fi
  fi
  if [ -n "$CLEANUP_HELD" ]; then echo "STEP 5 cleanup HELD: $CLEANUP_HELD"
  else orca-ide worktree remove --worktree "$WTID" --force || fail "step 5 cleanup" "could not remove unit worktree"; fi
}
# main_holds <tip>: main already holds the unit, read from git alone: the tip is in main (a fast-forward, or no commit
# of its own), or one commit of main since the fork point is the branch's whole diff (the squash, by patch id), or
# every path the branch changed reads in main as it does at the tip (a hand merge).
# shortcut: a hand merge that resolved a path differently, and that main then changed again, reads as not merged;
# --cleanup then refuses and nothing is closed (the safe side).
main_holds() {
  local base id ids p paths=()
  git merge-base --is-ancestor "$1" main && return 0
  base=$(git merge-base main "$1") || return 1
  id=$(git diff --no-color --no-relative --no-renames "$base" "$1" | git patch-id --stable | cut -d' ' -f1) || return 1
  ids=$(git log -p --no-color --no-renames --format='commit %H' "$base..main" | git patch-id --stable | cut -d' ' -f1) || return 1
  [ -z "$id" ] || ! grep -qxF "$id" <<<"$ids" || return 0
  while IFS= read -r -d '' p; do paths+=("$p"); done < <(git diff --no-relative --no-renames --name-only -z "$base" "$1")
  [ "${#paths[@]}" -gt 0 ] && git diff --quiet --no-relative "$1" main -- "${paths[@]}"
}
# --cleanup: step 5 alone, the retry of a held cleanup. It reads the unit's name, git and a live pane listing, and no
# record an earlier run left (seat records, the finished-builds line, pane-closes.log, the brief archive). The rest of
# this script (the merge) never runs.
if [ "$CLEANUP" = 1 ]; then
  PRE_TIP=$(git -C "$WT" rev-parse HEAD) && STARTED=$(date +%s) || fail "--cleanup" "cannot read $WT's tip"
  main_holds "$PRE_TIP" || fail "--cleanup" "$UNIT is not merged: main does not hold its branch's changes, so its panes may be a live Builder's; nothing was closed or removed. A hand merge that resolved it differently: confirm the merge by hand, close the unit's panes, then orca-ide worktree remove --worktree $WTID (no --force)"
  ARCHIVE=$HOME/.commandeck/briefs/$PP_PROJECT/$UNIT.tar KEPT=0 MAIN_FILES=()
  mkdir -p "$(dirname "$ARCHIVE")" || fail "--cleanup" "could not create the archive directory"
  cleanup_step
  echo "DONE unit=$UNIT cleanup=$([ -z "$CLEANUP_HELD" ] && echo removed || echo "HELD: $CLEANUP_HELD")"
  [ -z "$CLEANUP_HELD" ] || exit 5
  exit 0
fi
[ -f "$BRIEF" ] || fail "step 1 preconditions" "unit brief does not exist: $BRIEF"
BRANCH=$(git -C "$WT" branch --show-current)
[ -n "$BRANCH" ] && [ "$BRANCH" != main ] || fail "step 1 preconditions" "worktree $WT is on '${BRANCH:-no branch}', not on a branch of its own"
git -C "$WT" diff --quiet && git -C "$WT" diff --cached --quiet || fail "step 1 preconditions" "unit worktree has tracked changes"
# The tip before the rebase: --auto's gate passed on it, and the closing pass's suite ran on it (issue 307).
PRE_TIP=$(git -C "$WT" rev-parse HEAD)
STARTED=$(date +%s); state preconditions; rm -f "${MERGE_UNIT_LOCAL_QUEUE:-}"
[ -z "$AUTO" ] || [ "$(git -C "$WT" rev-parse --verify -q "$AUTO^{commit}" || true)" = "$PRE_TIP" ] \
  || fail "step 1 preconditions" "--auto $AUTO: the branch tip is now $(git -C "$WT" rev-parse --short=8 HEAD), not the commit the gate passed; the gate runs again on the new tip"
# The gate's hold and owner checks again, under the merge lock: either may have changed while this merge waited.
[ -z "$AUTO" ] || ! HELD=$(pp_merge_held "$UNIT" "$WT") || fail "step 1 preconditions" "--auto: held since the gate passed: $HELD"
while IFS= read -r path; do
  [ -n "$path" ] || continue
  case "$path" in .claude/briefs/*) ;; *) fail "step 1 preconditions" "unit worktree has untracked code: $path" ;; esac
done < <(git -C "$WT" ls-files --others --exclude-standard)
# Main only has to be clean where THIS merge will touch it:
#   - anything STAGED is swept into the unit's squash commit, because step 4
#     commits the whole index rather than a path list.
#   - uncommitted work in a file the unit also changes is overwritten by the merge.
git diff --no-relative --cached --quiet \
  || fail "step 1 preconditions" "main has staged changes, which step 4 would sweep into the unit's squash commit: $(git diff --no-relative --cached --name-only | paste -sd, -)"
# Before the rebase: a release origin marked published must not be rebuilt as a draft here.
if [ "$DRY_RUN" = 1 ]; then pp_sync_main "$ROOT" --check; else pp_sync_main "$ROOT"; fi \
  || fail "step 1 preconditions" "main is not up to date with origin's main (above)"
# --no-renames: a rename is a deletion of the old path too, and the undo in
# step 4 restores both.
MERGE_TOUCHES=$(git diff --no-relative --name-only --no-renames "$(git merge-base main "$BRANCH")" "$BRANCH")
while IFS= read -r path; do
  [ -n "$path" ] || continue
  if grep -qxF -- "$path" <<<"$MERGE_TOUCHES"; then
    fail "step 1 preconditions" "main has uncommitted work in $path, which this merge overwrites; commit or move it first"
  fi
done < <(git diff --no-relative --name-only)   # --no-relative here and below: from a subdirectory, diff.relative hides every path outside it
# A build's papers (.claude/briefs) are never committed: a branch with no commit has nothing to merge.
[ -n "$(git rev-list -1 "main..$BRANCH")" ] || fail "step 1 preconditions" "$BRANCH has no commit of its own; a unit's brief files are archived, never committed, so there is nothing to merge"
# Issue 265: a behaviour the owner has an open question on is theirs to settle, so the unit waits for the answer.
# Read here and again just before the commit (step 4): a question asked while the merge tests is one too.
no_holds() { # <step>
  local holds open
  holds=$(COMMANDECK_MAIN=$ROOT bash "$HERE/decision.sh" holds "$UNIT" 2>&1) \
    || fail "$1" "the owner's decisions ledger could not be read, so an open question naming $UNIT cannot be ruled out: $holds"
  open=$(grep '^Open question to the owner ' <<<"$holds" || true)
  [ -z "$open" ] || fail "$1" "an open question to the owner names $UNIT; merge once it is answered: $(paste -sd';' - <<<"$open")"
}
no_holds "step 1 preconditions"
echo "STEP 1 preconditions: main=$ROOT worktree=$WT branch=$BRANCH"

# Builder proof: a Builder runs its own review passes, so its last round file
# must be the pass script's, for this tip or a clean rebase of it, from a
# real reviewer session: a GO that names no open P0, P1 or P2, or a closing NO-GO
# with no P0 or P1 at the review cap (issue 366). What it leaves open is filed
# first (check_filed). The proof says which rule let the tip through. Every unit owes the proof: the
# worktree's own settings file is the Builder's to edit, so it cannot switch it off.
# A tail of commits after the reviewed one that only rebuild the files the project
# lists as generated (.claude/commandeck.json generatedFiles, main's copy) keeps
# that review: step 4's check on the merged tree proves them. A deletion, a merge
# commit or any other path in the tail needs a new pass, as before.
# Issue 352: one predicate, run at the end of step 1 and again at step 3. The rebase rewrites the branch, so a proof that
# step 3 alone refuses would be refused only after the Builder's branch was already rewritten.
GEN=$(jq -r '.generatedFiles // [] | .[] | strings' "$ROOT/.claude/commandeck.json" 2>/dev/null || true)
generated_only() { # <commit>
  local st p g hit
  [ -n "$GEN" ] && [ "$(git -C "$WT" rev-list --parents -n1 "$1" | wc -w)" -eq 2 ] || return 1
  ! git -C "$WT" merge-base --is-ancestor "$1" main || return 1
  while IFS=$'\t' read -r st p; do
    [ "$st" != D ] || return 1
    hit=0
    # shellcheck disable=SC2053 # each entry is a glob on purpose
    while IFS= read -r g; do [[ $p == $g ]] && { hit=1; break; }; done <<<"$GEN"
    [ "$hit" = 1 ] || return 1
  done < <(git -C "$WT" diff-tree --no-commit-id -r --no-renames --name-status "$1")
}
prove() { # <step> [<what the refusal adds>]: sets PROVED, TAIL and BUILDER_PROOF for the worktree's tip, or fails
  local verr first_err=""
  PROVED=$(git -C "$WT" rev-parse HEAD) TAIL=0 verr=$(mktemp)
  until BUILDER_PROOF=$(bash "$HERE/builder-codex-pass.sh" --verify "$WT" "$UNIT" "$PROVED" 2>"$verr"); do
    first_err=${first_err:-$(cat "$verr")}
    generated_only "$PROVED" || { rm -f "$verr"; echo "$first_err" >&2; fail "$1" "the Builder's review proof is missing or stale (named above)${2:+; $2}"; }
    PROVED=$(git -C "$WT" rev-parse "$PROVED^") TAIL=$((TAIL + 1))
  done
  rm -f "$verr"
}
# Issue 366: a review that stops with findings open (P3s at the threshold, P2s and P3s at the cap) merges only once each
# open class (the proof's "Open finding: <class> <line>" lines) names an issue GitHub reports OPEN, one per class: a new
# one, or an OPEN duplicate main commented the finding on. A filing for a class that is not open refuses too. Run after
# the proof at step 1, before the rebase touches the branch, and at step 3 on the rebased tip's proof. Sets FILED_MSG.
check_filed() { # <step>
  local open cls e n st miss="" extra="" twice=""
  open=$(sed -n 's/^Open finding: \([^ ]*\) .*/\1/p' <<<"$BUILDER_PROOF" | awk '!s[$0]++')
  for cls in $open; do
    case $(printf '%s\n' ${FILED[@]+"${FILED[@]}"} | awk -F= -v c="$cls" '$1 == c' | grep -c .) in 0) miss+=" $cls" ;; 1) ;; *) twice+=" $cls" ;; esac
  done
  for e in ${FILED[@]+"${FILED[@]}"}; do grep -qxF -- "${e%%=*}" <<<"$open" || extra+=" ${e%%=*}"; done
  [ -z "$miss" ] || fail "$1" "the review left findings open in class(es):$miss, and no --filed names an issue for each. Search the open issues for a duplicate of each class: an OPEN duplicate's number is accepted after you comment the finding there; otherwise file one issue per class. Then merge with --filed '<class>=#<n>' for each class (builder-codex-pass.sh --verify $WT $UNIT HEAD lists the Open finding lines)"
  [ -z "$twice" ] || fail "$1" "one issue per class: --filed names more than one issue for$twice"
  [ -z "$extra" ] || fail "$1" "--filed names class(es) the review left nothing open in:$extra"
  FILED_MSG=""
  for e in ${FILED[@]+"${FILED[@]}"}; do
    n=${e##*=#} cls=${e%%=*}
    st=$(cd "$ROOT" && gh issue view "$n" --json state -q .state 2>&1) || fail "$1" "gh issue view $n failed, so #$n ($cls) is not known to be OPEN: $(tail -n 1 <<<"$st")"
    [ "$st" = OPEN ] || fail "$1" "#$n ($cls) is $st on GitHub, not OPEN: file the class on an open issue"
    FILED_MSG+="Filed: #$n $cls"$'\n'
  done
  FILED_MSG=${FILED_MSG%$'\n'}
}
prove "step 1 proof" "the branch is untouched"
check_filed "step 1 filing"

state rebase
echo "STEP 2 rebase: git -C $WT rebase main"
if [ "$DRY_RUN" = 0 ]; then
  git -C "$WT" rebase main || {
    echo "FAILED step 2 rebase: conflict left for the Builder" >&2
    echo "Fix the conflict in the unit's worktree, then run the merge again." >&2
    exit 1
  }
fi

TIP=$(git -C "$WT" rev-parse HEAD)
state proof
prove "step 3 proof"
echo "$BUILDER_PROOF"
[ "$TAIL" = 0 ] || echo "step 3 proof: the $TAIL commit(s) after $(git -C "$WT" rev-parse --short=8 "$PROVED") change only files .claude/commandeck.json lists as generated; rule: generated-only tail"
grep -q '^Builder proof: .*; rule: .' <<<"$BUILDER_PROOF" || fail "step 3 proof" "the Builder's review proof names no rule the tip merges under"
check_filed "step 3 filing"
# The unit's issues, closed at its merge (issue 239): each work item (the launch list, $ISSUES) that the commit message
# names (#N), is on a brief's "Closes:" line or under its "Close as shipped" heading. A work item none of them names
# stays open and is named. Any other issue they name, and with no launch list every one, is never closed here: it is
# named and joins NOT CLOSED, as a close GitHub refuses does, printed last with its command; the script ends with code 3.
NOT_CLOSED="" POST_FAILED=""
close_issues() { # [--dry-run]
  local listed shipped named n ver c left="" off=""
  listed=$(tr -d '#' <<<"$LISTED")
  shipped=$({ grep -E '^Closes:' "$BRIEF"; awk '/^#+[[:space:]].*[Cc]lose as shipped/ { on = 1; next } /^#/ { on = 0 } on' "$BRIEF"; } | grep -oE '#[0-9]+' | tr -d '#' || true)
  named=$(grep -oE '#[0-9]+' <<<"$TITLE" | tr -d '#' || true)
  ver=$(jq -r '.version // empty' "$ROOT/.claude-plugin/plugin.json" 2>/dev/null || jq -r '.version // empty' "$ROOT/package.json" 2>/dev/null || true)
  c="Fixed in $(git rev-parse --short=8 HEAD)${ver:+ ($ver)}; ships with the next push."
  [ -r "$ISSUES" ] || echo "step 4 issues: no work-item list at $ISSUES (builder-launch.sh writes it at launch), so the merge closes no issue itself"
  for n in $(printf '%s\n' $listed $shipped $([ -r "$ISSUES" ] || echo $named) | awk 'NF && !s[$0]++'); do
    if ! printf '%s\n' $listed | grep -x -- "$n" >/dev/null; then off+=" #$n"; NOT_CLOSED+="NOT CLOSED: gh issue close $n --comment $(printf '%q' "$c")"$'\n'
    elif ! printf '%s\n' $named $shipped | grep -x -- "$n" >/dev/null; then left+=" #$n"
    elif [ "${1:-}" = --dry-run ]; then echo "step 4 issues: would close #$n"
    elif (cd "$ROOT" && gh issue close "$n" --comment "$c" >/dev/null 2>&1); then echo "step 4 issues: closed #$n"
    else NOT_CLOSED+="NOT CLOSED: gh issue close $n --comment $(printf '%q' "$c")"$'\n'; fi
  done
  [ -z "$left" ] || echo "step 4 issues: left open:$left (work items the commit message and the brief do not name to close)"
  [ -z "$off" ] || echo "step 4 issues: not closed:$off (named to close, but not on the launch list of work items; close by hand if shipped)"
  [ "${1:-}" != --dry-run ] || printf '%s' "$NOT_CLOSED"
}
# Every way out once the commit stands ends here, a failed step and a command
# that stops the script included: the merge is done and stays done, so the
# last lines say so, and what GitHub refused is printed under the command that
# files it without merging again.
merged_end() {
  local rc=$?
  trap - EXIT
  release
  [ "$rc" = 0 ] || { echo "MERGED as $(git rev-parse --short=8 HEAD), but a step after the merge commit failed (above): do not merge $UNIT again; finish that step by hand" >&2; rc=3; }
  if [ -n "$NOT_CLOSED" ]; then
    echo "MERGED, but the merge did not close $(grep -c . <<<"$NOT_CLOSED") issue(s) (refused by GitHub, or not on the launch list, above); close those shipped by hand:" >&2
    printf '%s' "$NOT_CLOSED" >&2; rc=3
  fi
  [ "$rc" != 0 ] || [ -z "$POST_FAILED" ] || { echo "MERGED, but a post-merge line was refused or its step failed (step 4 post-merge, above); the merge stands" >&2; rc=5; }
  [ "$rc" != 0 ] || [ -z "$CLEANUP_HELD" ] || { echo "MERGED, but the worktree was kept (step 5 cleanup, above); the merge stands" >&2; rc=5; }
  exit "$rc"
}

# The feat commit names the unit; a red-tests commit can touch a support file
# too, so "first non-test commit" alone would title the squash "add red tests".
TITLE=$(git -C "$WT" log --reverse --format=%s main..HEAD | grep -m1 '^feat(' || true)
[ -n "$TITLE" ] || while IFS=$'\t' read -r sha subject; do
  [ -n "$sha" ] || continue
  if grep -qvE '(^|/)__tests__/|\.test\.[^/]+$|^\.claude/briefs/' < <(git -C "$WT" show --pretty='' --name-only "$sha" | sed '/^$/d'); then TITLE=$subject; break; fi
done < <(git -C "$WT" log --reverse --format='%H%x09%s' main..HEAD)
[ -n "$TITLE" ] || TITLE=$(git -C "$WT" log -1 --format=%s)
# A pass commit's subject says nothing of what shipped: the brief's own first
# heading does (the rendered brief's title line "# <unit> -- Builder batch" is skipped).
if [[ $TITLE =~ ^feat\([^\)]*\):\ Builder\ pass\ r[0-9]+$ ]]; then
  H=$(grep -E '^# ' "$BRIEF" | grep -vxF -- "# $UNIT -- Builder batch" | head -1 | sed -E 's/^# +//; s/[[:space:]]+$//' || true)
  H=${H#"$UNIT -- "}
  TITLE="feat($UNIT)${H:+: $H}"
fi
# The squash keeps one subject, so every issue ref another unit subject names
# is appended once. Refs compare as whole tokens: #12345 in the title does not
# stand in for #12. Bodies and main's commits are not the unit's refs.
REFS=$(git -C "$WT" log --reverse --format=%s main..HEAD | grep -oE '#[0-9]+' \
  | awk -v have="$(grep -oE '#[0-9]+' <<<"$TITLE" | tr '\n' ' ')" \
    'BEGIN { n = split(have, h, " "); for (i = 1; i <= n; i++) seen[h[i]] = 1 }
     !seen[$0]++ { out = out (out == "" ? "" : ", ") $0 } END { print out }' || true)
[ -z "$REFS" ] || TITLE="$TITLE ($REFS)"
# The unit's work items are the list builder-launch.sh wrote to main's checkout at launch, never a parse of the brief:
# the Builder edits its brief, and a quoted list or directive in it adds nothing.
ISSUES=$PP_MAIN/.claude/briefs/$UNIT-issues.json
LISTED=$(jq -r '.[] | numbers | "#\(.)"' "$ISSUES" 2>/dev/null || true)
# A "Closes: #n" line in the brief is carried into the squash message as "Closes #n" and closes that issue below.
CLOSES=$(grep -E '^Closes:' "$BRIEF" | grep -oE '#[0-9]+' | grep -xF -- "$LISTED" | awk '!s[$0]++' || true)
CLOSE_BODY=""; [ -z "$CLOSES" ] || CLOSE_BODY=$(sed 's/^/Closes /' <<<"$CLOSES")
# A squash that deletes a file neither the brief nor the evidence's "Files
# deleted" list names is a botched rebase, not a unit: a unit told to cut
# "everything but X" can name its cuts only once it has made them. The size
# line is printed so main sees the count before the commit exists. Compare
# against the fork point, not main: --dry-run skips the rebase and every file
# main gained since the fork would read as a deletion.
BASE=$(git merge-base main "$BRANCH")
echo "STEP 4 size: $(git diff --shortstat "$BASE" "$BRANCH" | sed 's/^ *//')"
CUT_LIST=$(awk '/^#+[[:space:]]*Files deleted/ { on = 1; next } /^#/ { on = 0 } on' "$WT/.claude/briefs/$UNIT-evidence.md" 2>/dev/null || true)
# in_brief <path> -- the brief's prose names <path> whole: a space, quote, backtick or parenthesis before it,
# and after it the same, or sentence punctuation that ends it ("x.ts."). A longer path that holds it
# (old/x.ts.bak, x.ts~) names another file.
in_brief() {
  P=$1 PRE=$' \t`"\'(<' POST=$' \t`"\')>' awk '
    function edge(c, set) { return c == "" || index(set, c) > 0 }
    { from = 1; n = length(ENVIRON["P"])
      while ((i = index(substr($0, from), ENVIRON["P"])) > 0) {
        at = from + i - 1; b = at > 1 ? substr($0, at - 1, 1) : ""; a = substr($0, at + n, 1)
        if (edge(b, ENVIRON["PRE"]) && (edge(a, ENVIRON["POST"]) || (index(".,;:!?", a) && edge(substr($0, at + n + 1, 1), ENVIRON["POST"])))) { found = 1; exit }
        from = at + 1 } }
    END { exit !found }' "$BRIEF"
}
# Each entry of the evidence's list is one whole path: "- <path>" or "- `<path>`", nothing else on the line.
CUT_PATHS=$(sed -E 's/^[[:space:]]*[-*+][[:space:]]+//; s/[[:space:]]+$//; s/^`([^`]+)`$/\1/' <<<"$CUT_LIST")
# Issue 326: a directory named in backticks with its trailing slash (`dir/`), in the brief or in a plan the brief names,
# lists every file under it. The plan is read as committed at the fork point, so a unit cannot authorise its own
# deletion by editing it.
PLAN_TEXT=$(grep -ohE '`\.claude/plans/[A-Za-z0-9._-]+\.md`' "$BRIEF" 2>/dev/null | tr -d '`' | sort -u \
  | while IFS= read -r plan; do git show "$BASE:$plan" 2>/dev/null; done || true)
NAMED_DIRS=$({ cat "$BRIEF"; printf '%s\n' "$PLAN_TEXT"; } | grep -ohE '`[^` ]+/`' | tr -d '`' | sort -u || true)
while IFS= read -r deleted; do
  [ -n "$deleted" ] || continue
  if in_brief "$deleted"; then echo "step 4 deletion: $deleted (named in the brief)"
  elif awk -v p="$deleted" 'length($0) > 1 && index(p, $0) == 1 { f = 1 } END { exit !f }' <<<"$NAMED_DIRS"; then echo "step 4 deletion: $deleted (under a directory the brief or a plan it names lists)"
  elif grep -qxF -- "$deleted" <<<"$CUT_PATHS"; then echo "step 4 deletion: $deleted (named in the evidence's Files deleted list)"
  else fail "step 4 merge" "the squash deletes $deleted, which the brief never names; the rebase probably replayed stale content"
  fi
done < <(git diff --no-relative --diff-filter=D --name-only "$BASE" "$BRANCH")
# The message is the one text of the unit no file check reads (issue 221): a home path, this machine's name or a
# word of the project's own leak list refuses the merge before anything is merged.
MSG=$(mktemp) || fail "step 4 message" "could not write the message to a file"
printf '%s\n' "$TITLE" > "$MSG"
HOST=$(hostname -s 2>/dev/null || true)
LEAK=$(grep -nE '/(Users|home)/[^/[:space:]]+' "$MSG" || true)
[ -n "$LEAK" ] || [ "${#HOST}" -le 3 ] || LEAK=$(grep -niF -- "$HOST" "$MSG" || true)
if [ -z "$LEAK" ] && [ -f "$ROOT/ci/leak-test.sh" ]; then
  rc=0; LEAK=$(bash "$ROOT/ci/leak-test.sh" --text "$MSG" 2>/dev/null) || rc=$?
  LEAK=${LEAK//"$MSG:"/}
  # A project's own leak-test.sh older than --text cannot read the message: said, not refused. A scanner that
  # has --text and fails screened nothing, so it refuses.
  case $rc in 0) LEAK= ;; 1) ;;
    *) grep -q '^# leak-test.sh --text' "$ROOT/ci/leak-test.sh" && LEAK="ci/leak-test.sh --text could not run (exit $rc), so the message was not screened" \
         || { LEAK=; echo "step 4 message: ci/leak-test.sh predates --text; the project's word list was not applied" >&2; } ;; esac
fi
rm -f "$MSG"
[ -z "$LEAK" ] || fail "step 4 message" "the commit message leaks: $(head -1 <<<"$LEAK")"
CHECK_CMD=$(jq -r '.testCommand // empty' "$ROOT/.claude/commandeck.json" 2>/dev/null || true)
CHECKED="no testCommand in .claude/commandeck.json, so no check ran"
echo "STEP 4 merge: git merge --squash $BRANCH; ${CHECK_CMD:-(no check command)}; git commit -m $(printf '%q' "$TITLE")"
[ "$DRY_RUN" = 0 ] || close_issues --dry-run
if [ "$DRY_RUN" = 0 ]; then
  # Until the squash is committed, any exit undoes it. Step 1 proved the index
  # clean and no dirt in the squash's paths, so the staged paths are exactly
  # the squash's: restore those and nothing else. Never `reset --hard`, which
  # would take the unrelated dirt step 1 deliberately allows.
  # The copy the check runs on. rm does not follow the node_modules links.
  drop_copy() {
    [ -n "${COPY:-}" ] || return 0
    git -C "$ROOT" worktree remove --force "$COPY/tree" >/dev/null 2>&1 || true
    pp_rm_rf "$COPY"; git -C "$ROOT" worktree prune; COPY=
  }
  undo_squash() {
    local staged=() added=() kept=() p
    drop_copy
    # Git names these paths from the checkout's root, wherever the merge was run from.
    cd "$ROOT" || return 0
    mapfile -t staged < <(git diff --cached --name-only --no-renames)
    # Unstaged first, and the squash's paths are then read from disk: a check
    # or hook may have run `git reset` itself, leaving them with nothing staged.
    git reset -q
    # Only what the squash itself brought: a file of the owner's that the
    # check staged is unstaged by the reset above and stays on disk.
    for p in ${SQUASH_ADDED[@]+"${SQUASH_ADDED[@]}"}; do { [ ! -e "$p" ] && [ ! -L "$p" ]; } || added+=("$p"); done
    # Of what differs from HEAD, only the squash's own paths go back to it: a
    # commit hook may have staged the owner's edit to another tracked file.
    mapfile -t kept < <(git diff --name-only --no-renames HEAD \
      | grep -xFf <(printf '%s\n' ${SQUASH_PATHS[@]+"${SQUASH_PATHS[@]}"}) || true)
    [ $((${#staged[@]} + ${#added[@]} + ${#kept[@]})) -gt 0 ] || return 0
    [ "${#kept[@]}" = 0 ] || git checkout -q HEAD -- "${kept[@]}"
    [ "${#added[@]}" = 0 ] || rm -f -- "${added[@]}"
    echo "step 4 merge: undid the uncommitted squash; main is back at $(git rev-parse --short=8 HEAD) with its $((${#added[@]} + ${#kept[@]})) path(s) restored" >&2
  }
  mapfile -t SQUASH_ADDED < <(git -C "$ROOT" diff --name-only --no-renames --diff-filter=A HEAD "$BRANCH")
  # A path the branch adds that is already on disk here is the owner's own,
  # untracked or ignored (.env): git overwrites an ignored file without a word.
  # With the branch's exact content it loses nothing, and the undo leaves it.
  NEW=()
  for f in ${SQUASH_ADDED[@]+"${SQUASH_ADDED[@]}"}; do
    if [ -e "$ROOT/$f" ] || [ -L "$ROOT/$f" ]; then
      git -C "$ROOT" cat-file -p "$BRANCH:$f" 2>/dev/null | cmp -s - "$ROOT/$f" \
        || fail "step 4 merge" "the branch adds $f, and a different file of that name is already in main's checkout, untracked or ignored; the squash would overwrite it. Move it aside, then merge again"
    else NEW+=("$f"); fi
  done
  SQUASH_ADDED=(${NEW[@]+"${NEW[@]}"})
  mapfile -t SQUASH_PATHS < <(git -C "$ROOT" diff --name-only --no-renames HEAD "$BRANCH")
  state merge
  trap 'undo_squash; release' EXIT
  git merge --squash "$BRANCH" >/dev/null || fail "step 4 merge" "squash merge conflicted; resolve in the unit worktree by rebasing onto main"
  TREE=$(git write-tree)
  # The project's check runs once, on the merged tree, before the commit exists:
  # a red check leaves main where it was and the worktree in place for the fix.
  # It runs on a copy of exactly that tree, a detached worktree outside the
  # project: main's own uncommitted edits to tracked files are not in the
  # commit, so they are not tested, and nothing the check writes lands in main.
  # shortcut: of main's untracked files the copy has only node_modules, by link; link another here when a check needs it (.env).
  # The link stays (main's ruling): a check that writes under node_modules writes main's. The doctor warns on a check that installs.
  # Issue 307 (the owner's ruling): a green full run is not run again only when it tested the merged tree itself,
  # the same tree hash: a check reads files no list of names can find (a glob, a path built from parts). One run
  # counts: the closing pass's "Suite:" line as --verify read it from that pass's own recorded prompt (its "Suite
  # proof:" line; the round file is the Builder's to edit), on the tip before or after the rebase, and only for the
  # check this merge would run: its cksum must match. A merge train's run is not one: it tested a tree with later
  # units in it, and a record a caller hands in proves nothing.
  state check
  REUSED="" STALE="" SUM=$(cksum <<<"$CHECK_CMD" | cut -d' ' -f1)
  SUITE_LINE=$(sed -n 's/^Suite proof: //p' <<<"$BUILDER_PROOF" | grep -m1 -E '^Suite: [0-9a-f]{40} pass ' || true)
  if [ -n "$CHECK_CMD" ] && [ -n "$SUITE_LINE" ]; then
    read -r _ RAN _ <<<"$SUITE_LINE"
    if [ "${SUITE_LINE##* cmd:}" != "$SUM" ]; then STALE="it ran another check command than this merge's"
    elif [ "$RAN" != "$PRE_TIP" ] && [ "$RAN" != "$TIP" ]; then STALE="its commit ${RAN:0:8} is not the unit's tip"
    elif [ "$(git rev-parse -q --verify "$RAN^{tree}")" = "$TREE" ]; then REUSED=$SUITE_LINE
    else STALE="it tested another tree than the merged one (they differ in $(git diff --name-only --no-renames "$RAN" "$TREE" | head -3 | paste -sd' ' -))"; fi
  fi
  [ -z "$STALE" ] || echo "STEP 4 check: the closing pass's green suite is not reused, $STALE; the check runs"
  if [ -n "$REUSED" ]; then
    echo "STEP 4 check: reused, not run again: $REUSED"
    CHECKED="check reused: $REUSED"
  elif [ -n "$CHECK_CMD" ]; then
    echo "STEP 4 check: $CHECK_CMD"
    COPY=$(mktemp -d) || fail "step 4 check" "could not make a folder for the copy the check runs on"
    { git worktree add -q --detach "$COPY/tree" HEAD >/dev/null 2>&1 && git -C "$COPY/tree" read-tree -u --reset "$TREE"; } \
      || fail "step 4 check" "could not make the copy the check runs on"
    pp_link_node_modules "$ROOT" "$COPY/tree"
    (cd "$COPY/tree" && bash -c "$CHECK_CMD") || fail "step 4 check" "the check command is red on the merged tree (output above); fix it in $WT and run another pass"
    # A check that rewrites tracked files or stages some (a formatter, a
    # generator) was green on a tree the commit would not hold.
    CHANGED=$(git -C "$COPY/tree" diff --name-only | head -5 | paste -sd' ' -)
    [ -z "$CHANGED" ] && [ "$(git -C "$COPY/tree" write-tree)" = "$TREE" ] \
      || fail "step 4 check" "the check command changed tracked files or what is staged (${CHANGED:-staged paths}), so it did not test what the commit would hold. Make the check read-only, or commit what it writes in $WT, then merge again"
    drop_copy
    CHECKED="check green: $CHECK_CMD"
  fi
  # Issue 349: a change to a plugin's mod code or types is checked by the plugin's own validate and test, which no project
  # testCommand runs. It runs on every path to here (no testCommand, a reused suite proof included), on a copy of the merged tree.
  PLUGIN_CHANGED=0
  for f in ${SQUASH_PATHS[@]+"${SQUASH_PATHS[@]}"}; do
    case $f in hooks/*.ts|hooks/*.tsx|types/*) PLUGIN_CHANGED=1 ;; esac
  done
  if [ "$PLUGIN_CHANGED" = 1 ] && git cat-file -e "$TREE:.claude-plugin/plugin.json" 2>/dev/null; then
    echo "STEP 4 plugin: claude plugin validate . && claude plugin test ."
    COPY=$(mktemp -d) || fail "step 4 plugin" "could not make a folder for the copy the plugin check runs on"
    { git worktree add -q --detach "$COPY/tree" HEAD >/dev/null 2>&1 && git -C "$COPY/tree" read-tree -u --reset "$TREE"; } \
      || fail "step 4 plugin" "could not make the copy the plugin check runs on"
    pp_link_node_modules "$ROOT" "$COPY/tree"
    (cd "$COPY/tree" && claude plugin validate . && claude plugin test .) \
      || fail "step 4 plugin" "claude plugin validate or test is red on the merged tree (output above); fix it in $WT and run another pass"
    drop_copy
  fi
  # A build's papers are never committed: the commit holds the squash and
  # nothing else. Main's untracked brief files of the unit are archived now and
  # removed only once the merge is committed; one git tracks is left as it is
  # (the doctor names it). The tar lives in the plugin's own state, never in the project.
  state commit
  ARCHIVE=$HOME/.commandeck/briefs/$PP_PROJECT/$UNIT.tar
  mkdir -p "$(dirname "$ARCHIVE")" || fail "step 4 briefs" "could not create the archive directory"
  KEPT=0 MAIN_FILES=()
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    ! git ls-files --error-unmatch -- "$f" >/dev/null 2>&1 || continue
    # A file whose worktree namesake differs stays in main: the tar would hide it behind that one.
    [ ! -e "$WT/.claude/briefs/${f##*/}" ] || cmp -s -- "$f" "$WT/.claude/briefs/${f##*/}" || continue
    # A staged later-cut brief belongs to the next cut, not this merge.
    case "$(basename "$f")" in "$UNIT"-cut[0-9]*) continue ;; esac
    tar -C "$(dirname "$f")" -rf "$ARCHIVE" -- "$(basename "$f")" || fail "step 4 briefs" "could not append $(basename "$f") to $ARCHIVE"
    KEPT=$((KEPT + 1))
    MAIN_FILES+=("$f")
  done < <(pp_unit_briefs "$ROOT/.claude/briefs" "$UNIT")
  # The ledger's shared lock, held from this read through the commit, keeps a question from being added between them
  # (decision.sh add takes it exclusive). The commit's hooks get no copy of it (issue 301: a process one leaves
  # behind would hold it), and it is let go once the commit is made.
  LEDGER=$ROOT/.claude/metrics/decisions.jsonl
  # An absent ledger is started here, as decision.sh add does: a lock on nothing would let that add start the file and ask.
  { [ -e "$LEDGER" ] || { mkdir -p "${LEDGER%/*}" && : >> "$LEDGER"; }; } && exec {LEDGER_FD}<"$LEDGER" && flock -s -w 60 "$LEDGER_FD" \
    || fail "step 4 merge" "could not lock $LEDGER to read the owner's open questions once more"
  no_holds "step 4 merge"
  # --auto's gate holds too, read again under the same lock: a hold or question added during the check counts.
  [ -z "$AUTO" ] || ! HELD=$(pp_merge_held "$UNIT" "$WT") || fail "step 4 merge" "--auto: held since the gate passed: $HELD"
  if ! git commit -q -m "$TITLE" ${CLOSE_BODY:+-m "$CLOSE_BODY"} ${FILED_MSG:+-m "$FILED_MSG"} {LEDGER_FD}<&-; then
    git diff --no-relative --cached --quiet && fail "step 4 merge" "nothing to commit: is $BRANCH already merged, or was main's index emptied during the run?"
    fail "step 4 merge" "git commit refused the squash; the cause is git's or the hook's output above"
  fi
  exec {LEDGER_FD}<&-
  # A commit hook that passed may still have edited and staged files: the
  # commit then holds a tree nobody reviewed or checked, and is taken back.
  if [ "$(git rev-parse 'HEAD^{tree}')" != "$TREE" ]; then
    HOOKED=$(git diff --no-relative --name-only "$TREE" 'HEAD^{tree}' | head -5 | paste -sd' ' -)
    git reset -q --soft HEAD~1
    fail "step 4 merge" "the commit holds other files than the squash ($HOOKED), so the commit was not the tree that was reviewed and checked (a commit hook, or main's index changed during the run); it was taken back. If a hook did it, make that change in $WT and run another pass; if someone touched main's index, merge again"
  fi
  trap merged_end EXIT
  state post-merge
  MERGE_SHA=$(git rev-parse HEAD)
  MERGE_TREE=$(git rev-parse --short=8 "$MERGE_SHA^{tree}") TIP_TREE=$(git -C "$WT" rev-parse --short=8 'HEAD^{tree}')
  # Equality is claimed only when it holds.
  if [ "$MERGE_TREE" = "$TIP_TREE" ]; then TREES="$MERGE_TREE == unit tip tree $TIP_TREE"
  else TREES="$MERGE_TREE != unit tip tree $TIP_TREE"
  fi
  echo "step 4 evidence: merged $UNIT as $(git rev-parse --short=8 "$MERGE_SHA"); tree $TREES"
  close_issues
  # Issue 255: the brief's "## Post-merge" lines, each a job of its own once the merge stands. Only the three on
  # the list run; any other line is refused with exit 5. A refused or failed step undoes nothing and ends the
  # script with 5. Each step's exit goes into the finished-builds row below.
  POST_LOG=$PP_SCRATCH/post-merge-$UNIT POST_STEPS=() POST_PIDS=() POST_RCS=()
  mkdir -p "$PP_SCRATCH"
  while IFS= read -r line; do
    line=$(sed -E 's/^[[:space:]]*[-*][[:space:]]+//; s/^`(.*)`$/\1/; s/[[:space:]]+$//' <<<"$line")
    [ -n "$line" ] || continue
    i=${#POST_STEPS[@]}; POST_STEPS+=("$line"); POST_PIDS+=(""); POST_RCS+=(5)
    case $line in
      "dashboard.sh --install"|"main-watch.sh --install") ;;
      "run-shell-tests.sh "*) [[ ${line#* } =~ ^(hooks|scripts)/__tests__/[A-Za-z0-9._-]+\.test\.sh$ ]] \
        || { echo "step 4 post-merge: not on the post-merge list (exit 5): $line" >&2; continue; } ;;
      *) echo "step 4 post-merge: not on the post-merge list (exit 5): $line" >&2; continue ;;
    esac
    # Question 4: a dashboard behind a login (issue 263) starts only once its password is set. A dashboard.sh
    # with a login answers --login-check (0: login off or password set); one without has nothing to check.
    if [ "${line%% *}" = dashboard.sh ] && grep -q -- '--login-check' "$HERE/dashboard.sh" \
       && ! bash "$HERE/dashboard.sh" --login-check > "$POST_LOG-$i.log" 2>&1; then
      echo "step 4 post-merge: refused (exit 5): $line: $(tail -n 1 "$POST_LOG-$i.log")" >&2; continue
    fi
    # shellcheck disable=SC2086 # the line's one argument, split on purpose
    (cd "$ROOT" && bash "$HERE/${line%% *}" ${line#* }) > "$POST_LOG-$i.log" 2>&1 &
    POST_PIDS[i]=$!
  done < <(awk '/^#+[[:space:]]*Post-merge[[:space:]]*$/ { on = 1; next } /^#/ { on = 0 } on && !/^```/' "$BRIEF")
  for i in "${!POST_STEPS[@]}"; do
    [ -z "${POST_PIDS[i]}" ] || { wait "${POST_PIDS[i]}" && POST_RCS[i]=0 || POST_RCS[i]=$?; }
  done
  POST_JSON=$(for i in "${!POST_STEPS[@]}"; do jq -cn --arg step "${POST_STEPS[i]}" --argjson exit "${POST_RCS[i]}" '{$step, $exit}'; done | jq -cs .)
  [ "${#POST_STEPS[@]}" = 0 ] || echo "step 4 post-merge: $(for i in "${!POST_STEPS[@]}"; do printf '%s exit %s; ' "${POST_STEPS[i]}" "${POST_RCS[i]}"; done | sed 's/; $//') (logs $POST_LOG-<n>.log)"
  for i in "${!POST_RCS[@]}"; do [ "${POST_RCS[i]}" = 0 ] || POST_FAILED=1; done
  # The finished-builds record, which the dashboard lists: one line a merge, appended here and nowhere else, once
  # the commit stands. One short write in append mode, under a lock on the home folder: uninstall rewrites this
  # file for a same-named checkout under the same lock, so no line is appended to a file being replaced. The home
  # folder, because uninstall removes the builds folder and a lock on that would not outlive it. A line that
  # cannot be written (the lock held 5 s) costs the list one build, never the merge. The line names this checkout by its real path: the
  # file is named by the folder's name alone, which another checkout elsewhere may share.
  BUILDS=$HOME/.commandeck/builds/$PP_PROJECT.jsonl
  ( exec 8<"$HOME" && flock -w 5 8 && mkdir -p "${BUILDS%/*}" && jq -cn --arg main "$(cd "$ROOT" && pwd -P)" --arg unit "$UNIT" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg sha "$MERGE_SHA" \
      --argjson post "$POST_JSON" \
      '{$main, $unit, how: "merged", $at, $sha} + (if $post == [] then {} else {$post} end)' >> "$BUILDS" ) \
    || echo "finished-builds record not written to $BUILDS: the dashboard will not list $UNIT (ignored)" >&2
  # The token ledger: a Builder's seat is never collected, it ends with this merge, so its row is written here,
  # from the record its launch left, while the worktree's session log can still be found. Never blocks a merge.
  SEAT=$PP_SCRATCH/seat-$UNIT-builder.txt
  [ ! -f "$SEAT" ] || SEAT_EVENT_WORKTREE=$WT SEAT_EVENT_AGENT=$(pp_route builder 2>/dev/null && printf '%s' "$RT_AGENT" || true) SEAT_EVENT_STOP=done \
    SEAT_EVENT_SPEC=$(sed -n 's/^tag=//p' "$SEAT" | tail -1) SEAT_EVENT_SESSIONS=$(sed -n 's/^session=//p' "$SEAT" | tr '\n' ' ') bash "$HERE/seat-event.sh" "$UNIT" builder "$(sed -n 's/^task=//p' "$SEAT")" "$(sed -n 's/^launched=//p' "$SEAT")" \
    || echo "no token ledger row written for $UNIT's Builder (ignored)" >&2
  # The unit ledger (issue 271): how the review loop ended, from the round files the proof read, each one's last
  # line its verdict. A round with no verdict line leaves both counts unknown, never 0. Never blocks a merge.
  REPORTS=("$WT/.claude/briefs/$UNIT"-r[0-9]*-reports.md); [ -f "${REPORTS[0]}" ] || REPORTS=()
  ENDS=$(for f in ${REPORTS[@]+"${REPORTS[@]}"}; do tail -n 1 "$f"; done)
  GO_ROUNDS=$(grep -cx 'VERDICT: GO' <<<"$ENDS" || true) NO_GO_ROUNDS=$(grep -cx 'VERDICT: NO-GO' <<<"$ENDS" || true)
  [ $((GO_ROUNDS + NO_GO_ROUNDS)) = "${#REPORTS[@]}" ] || GO_ROUNDS="" NO_GO_ROUNDS=""
  RULE=$(sed -n 's/^Builder proof: .*; rule: //p' <<<"$BUILDER_PROOF" | head -1)
  # GO and NO-GO per pass kind (the round file's Pass: line), and the seconds in review (its Timing: line, the pass's
  # start and end). A round with no verdict, a kind this list does not know, or no Timing leaves that part null, never 0.
  REVIEW=$(for f in ${REPORTS[@]+"${REPORTS[@]}"}; do echo "$(sed -n 's/^Pass: *//p' "$f" | head -1)|$(tail -n 1 "$f")|$(sed -n 's/^Timing: *//p' "$f" | head -1)"; done \
    | jq -Rnc 'def t: sub("\\.[0-9]+Z$"; "Z") | fromdate; [inputs | split("|")] as $r
      | {passKinds: (if $r == [] or any($r[]; (.[0] | IN("adversarial", "review", "final") | not) or (.[1] | IN("VERDICT: GO", "VERDICT: NO-GO") | not)) then null
           else reduce $r[] as $x ({}; .[$x[0]] |= ({go: 0, noGo: 0} + .) | .[$x[0]][if $x[1] == "VERDICT: GO" then "go" else "noGo" end] += 1) end),
         reviewSeconds: (if $r == [] or any($r[]; .[2] | test("^\\S+Z \\S+Z$") | not) then null
           else [$r[] | .[2] | split(" ") | (.[1] | t) - (.[0] | t)] | add end)}' 2>/dev/null || true)
  COMMANDECK_MAIN=$ROOT UNIT_LEDGER_MERGE_SHA=$MERGE_SHA UNIT_LEDGER_REVIEW=$REVIEW \
    UNIT_LEDGER_VERDICT=$(if [ "${#REPORTS[@]}" = 0 ]; then echo NO-ROUNDS; else echo CONVERGED-GO; fi) \
    UNIT_LEDGER_ROUNDS=${#REPORTS[@]} UNIT_LEDGER_GO_ROUNDS=$GO_ROUNDS UNIT_LEDGER_NO_GO_ROUNDS=$NO_GO_ROUNDS \
    UNIT_LEDGER_MERGE_RULE=$RULE bash "$HERE/unit-ledger.sh" "$UNIT" local --append \
    || echo "no unit ledger row written for $UNIT (ignored)" >&2
  cleanup_step
fi

[ "$DRY_RUN" = 0 ] || echo "STEP 5 cleanup: orca-ide terminal close --worktree $WTID --all; orca-ide worktree remove --worktree $WTID --force"
echo "DONE unit=$UNIT merged=local sha=$(git rev-parse --short=8 HEAD); $CHECKED; nothing was pushed${CLEANUP_HELD:+; cleanup HELD: $CLEANUP_HELD}"
# The unit's seats are done with: main-watch's item tasks about them are handled by this merge.
[ "$DRY_RUN" = 1 ] || pp_close_items $(sed -n 's/^handle=//p' "$PP_SCRATCH"/seat-"$UNIT"-*.txt 2>/dev/null || true)

#!/usr/bin/env bash
# merge-unit-local.sh <unit> [--dry-run] [--area <area>] [--milestone <name>]
# Squash-merge a Builder's branch onto local main, without a PR and without a
# push. The one gate is the Builder proof (builder-codex-pass.sh --verify): the
# last round file must be the pass script's, GO, for the tip being merged. The
# project's check command (.claude/commandeck.json testCommand) then runs once
# on a copy of the squashed tree; a red check undoes the squash.
# Self-test: bash scripts/__tests__/merge-unit-local.test.sh
set -euo pipefail
# Two Builders finishing minutes apart would rebase and squash onto the same
# index of the ONE main checkout. Serialise them: the second caller waits, then
# rebases onto the first one's merge. Re-exec before arg parsing so every flag
# survives.
usage() { cat <<'EOF'
usage: merge-unit-local.sh <unit> [--dry-run] [--area <area>] [--milestone <name>]
Squash-merge a Builder's branch onto local main; run from the main checkout on main.
  --dry-run        run the checks and print the plan; merge and clean up nothing
  --area <area>    area label for the issue filed per finding left open (file-open-findings.sh)
  --milestone <name>  milestone for those issues
exit: 0 merged; 1 refused or failed, not merged; 2 usage; 3 MERGED, but a step after the
      merge commit failed (archiving the unit's brief files, or closing its panes and removing
      its worktree): finish it by hand, do not merge again; 4 MERGED, but a finding left open
      could not be filed as an issue: the NOT FILED lines are the last printed, with the command
      that files them
example: merge-unit-local.sh my-unit --dry-run
EOF
}
# Before the lock: a usage error must not wait behind a running merge.
case "${1:-}" in --help|-h) usage; exit 0 ;; "") usage >&2; exit 2 ;; esac
if [ -z "${MERGE_UNIT_LOCAL_LOCK:-}" ]; then
  exec env MERGE_UNIT_LOCAL_LOCK=1 flock \
    "$(git rev-parse --path-format=absolute --git-common-dir)/merge-unit-local.lock" "$0" "$@"
fi
UNIT=$1; shift
DRY_RUN=0 AREA="" MILESTONE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --area) AREA=${2:-}; [ -n "$AREA" ] || { usage >&2; exit 2; }; shift 2 ;;
    --milestone) MILESTONE=${2:-}; [ -n "$MILESTONE" ] || { usage >&2; exit 2; }; shift 2 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[[ "$UNIT" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "invalid unit: $UNIT" >&2; exit 2; }
fail() { echo "FAILED $1: $2" >&2; exit 1; }
ROOT=$(git rev-parse --show-toplevel) || fail "step 1 preconditions" "not in a git checkout"
[ "$(git rev-parse --path-format=absolute --git-dir)" = "$(git rev-parse --path-format=absolute --git-common-dir)" ] \
  || fail "step 1 preconditions" "run from the main checkout, not a linked worktree"
[ "$(git branch --show-current)" = main ] || fail "step 1 preconditions" "main checkout must be on branch main"
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# The project is the checkout the merge runs in, not the one the plugin lives in.
COMMANDECK_MAIN=$ROOT . "$HERE/paths.sh"
. "$HERE/../hooks/lib/project.sh"; pp_project "$ROOT"
pp_unit_name "$UNIT" || fail "step 1 preconditions" "the unit's name (above)"
WT=$PP_WORKSPACES/$UNIT
BRIEF=$WT/.claude/briefs/$UNIT.md
WTID="path:$WT"
[ -d "$WT" ] || fail "step 1 preconditions" "worktree does not exist: $WT"
# Step 5 removes this folder: a checkout of its own (a .git folder, not a linked worktree's .git file) never gets there.
[ -f "$WT/.git" ] || fail "step 1 preconditions" "$WT is not a linked worktree (its .git is not a file), and step 5 would remove it"
[ -f "$BRIEF" ] || fail "step 1 preconditions" "unit brief does not exist: $BRIEF"
BRANCH=$(git -C "$WT" branch --show-current)
[ -n "$BRANCH" ] && [ "$BRANCH" != main ] || fail "step 1 preconditions" "worktree $WT is on '${BRANCH:-no branch}', not on a branch of its own"
git -C "$WT" diff --quiet && git -C "$WT" diff --cached --quiet || fail "step 1 preconditions" "unit worktree has tracked changes"
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
echo "STEP 1 preconditions: main=$ROOT worktree=$WT branch=$BRANCH"

echo "STEP 2 rebase: git -C $WT rebase main"
if [ "$DRY_RUN" = 0 ]; then
  git -C "$WT" rebase main || {
    echo "FAILED step 2 rebase: conflict left for the Builder" >&2
    echo "Fix the conflict in the unit's worktree, then run the merge again." >&2
    exit 1
  }
fi

TIP=$(git -C "$WT" rev-parse HEAD)
# Builder proof: a Builder runs its own review passes, so its last round file
# must be the pass script's, GO, for this tip or a clean rebase of it, from a
# real reviewer session. Or, with no closing GO, a P2/P3-only tail every commit
# of which a narrowed pass read. The proof says which rule let the tip through
# and lists each finding open at merge, in a dry run as in a real merge: main
# reads these lines and files what stays open. Every unit owes the proof: the
# worktree's own settings file is the Builder's to edit, so it cannot switch it off.
# A tail of commits after the reviewed one that only rebuild the files the project
# lists as generated (.claude/commandeck.json generatedFiles, main's copy) keeps
# that review: step 4's check on the merged tree proves them. A deletion, a merge
# commit or any other path in the tail needs a new pass, as before.
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
PROVED=$TIP TAIL=0 VERR=$(mktemp) FIRST_ERR=""
until BUILDER_PROOF=$(bash "$HERE/builder-codex-pass.sh" --verify "$WT" "$UNIT" "$PROVED" 2>"$VERR"); do
  FIRST_ERR=${FIRST_ERR:-$(cat "$VERR")}
  generated_only "$PROVED" || { rm -f "$VERR"; echo "$FIRST_ERR" >&2; fail "step 3 proof" "the Builder's review proof is missing or stale (named above)"; }
  PROVED=$(git -C "$WT" rev-parse "$PROVED^") TAIL=$((TAIL + 1))
done
rm -f "$VERR"
echo "$BUILDER_PROOF"
[ "$TAIL" = 0 ] || echo "step 3 proof: the $TAIL commit(s) after $(git -C "$WT" rev-parse --short=8 "$PROVED") change only files .claude/commandeck.json lists as generated; rule: generated-only tail"
grep -q '^Builder proof: .*; rule: .' <<<"$BUILDER_PROOF" || fail "step 3 proof" "the Builder's review proof names no rule the tip merges under"
MERGE_OPEN=$(grep -c '^Open at merge: ' <<<"$BUILDER_PROOF" || true)
# One issue per finding left open, filed by the merge and not from memory.
# GitHub failing never fails or undoes the merge: this returns 0 whatever
# happens, and the unfiled findings are printed last, where the script ends
# with code 4. A project with no gh, no login or no GitHub remote gets exactly
# that for every finding: the merge stands and each finding is named NOT FILED.
MERGE_ISSUES="" NOT_FILED="" FILE_AGAIN=""
file_open_findings() { # <commit> [--dry-run]
  local sha=$1 out rc=0 keyed owed="" key line k rest; shift
  [ "${MERGE_OPEN:-0}" -gt 0 ] 2>/dev/null || return 0
  local cmd=(bash "${HERE:-$(dirname "${BASH_SOURCE[0]}")}/file-open-findings.sh" "$UNIT" "$sha" "$@")
  [ -z "${AREA:-}" ] || cmd+=(--area "$AREA")
  [ -z "${MILESTONE:-}" ] || cmd+=(--milestone "$MILESTONE")
  out=$("${cmd[@]}" <<<"$BUILDER_PROOF" 2>&1) || rc=$?
  { grep -vE '^(NOT FILED: |KEY )' <<<"$out" || true; } | sed 's/^/step 4 issues: /'
  # Read from the answers, not the script's closing line: a script killed part way never prints that.
  MERGE_ISSUES=$(sed -nE 's/^(FILED|ALREADY OPEN) #([0-9]+): .*/\2/p' <<<"$out" | paste -sd' ' -)
  NOT_FILED=$(grep '^NOT FILED: ' <<<"$out" || true)
  # The script names every finding's key before it calls GitHub, then answers
  # each finding with its key. Counted against the proof's own list: a
  # finding with no key line of its own (the script died naming them) or with
  # a key and no answer is one it never reached.
  keyed=$(grep '^KEY ' <<<"$out" || true)
  while IFS= read -r line; do
    key=""
    # Whole lines compared, never split into words: a command in a finding may hold two spaces.
    while IFS= read -r k; do rest=${k#KEY *: }; [ "$rest" != "$line" ] || { k=${k#KEY }; key=${k%%:*}; break; }; done <<<"$keyed"
    [ -n "$key" ] && grep -qE '^(FILED #|ALREADY OPEN #|WOULD FILE |NOT FILED: )' <<<"$(grep -F -- " [$key]" <<<"$out")" || owed+=$line$'\n'
  done < <(sed -n 's/^Open at merge: //p' <<<"$BUILDER_PROOF")
  owed=$(sed "/^\$/d; s/\$/ (file-open-findings.sh ended with code $rc before it reached this finding)/; s/^/NOT FILED: /" <<<"$owed")
  [ -z "$owed" ] || NOT_FILED+=${NOT_FILED:+$'\n'}$owed
  # Any ending but a clean one earns the retry command, printed with these lines.
  [ "$rc" = 0 ] || [ -n "$NOT_FILED" ] \
    || NOT_FILED="NOT FILED: not known which (file-open-findings.sh ended with code $rc after an answer for every finding)"
  FILE_AGAIN="printf '%s\\n' $(printf '%q ' "$(grep -E '^(Builder proof|Open at merge): ' <<<"$BUILDER_PROOF")") | $(printf '%q ' "${cmd[@]}")"
  return 0
}
# Every way out once the commit stands ends here, a failed step and a command
# that stops the script included: the merge is done and stays done, so the
# last lines say so, and what GitHub refused is printed under the command that
# files it without merging again.
merged_end() {
  local rc=$?
  trap - EXIT
  [ "$rc" = 0 ] || { echo "MERGED as $(git rev-parse --short=8 HEAD), but a step after the merge commit failed (above): do not merge $UNIT again; finish that step by hand" >&2; rc=3; }
  if [ -n "$NOT_FILED" ]; then
    echo "MERGED, but $(grep -c . <<<"$NOT_FILED") finding(s) left open have no issue. File them from the main checkout with: $FILE_AGAIN" >&2
    echo "$NOT_FILED" >&2
    [ "$rc" = 3 ] || rc=4
  fi
  exit "$rc"
}
if [ "$DRY_RUN" = 1 ]; then
  file_open_findings "$TIP" --dry-run
  # A dry run filed nothing, so it owes nothing at its end: what the lookup could not answer is said here.
  [ -z "$NOT_FILED" ] || sed 's/^NOT FILED: /step 4 issues: could not look up: /' <<<"$NOT_FILED"
  NOT_FILED=""
fi

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
while IFS= read -r deleted; do
  [ -n "$deleted" ] || continue
  if in_brief "$deleted"; then echo "step 4 deletion: $deleted (named in the brief)"
  elif grep -qxF -- "$deleted" <<<"$CUT_PATHS"; then echo "step 4 deletion: $deleted (named in the evidence's Files deleted list)"
  else fail "step 4 merge" "the squash deletes $deleted, which the brief never names; the rebase probably replayed stale content"
  fi
done < <(git diff --no-relative --diff-filter=D --name-only "$BASE" "$BRANCH")
# The squash drops every unit commit body; a commit-msg hook that asks for the
# mutation note the pass commit carried would refuse it, so the notes ride along.
MUTATIONS=$(git -C "$WT" log --format=%B "$BASE".."$BRANCH" | grep -i -A2 '^Mutation-verified' || true)
[ -z "$MUTATIONS" ] || TITLE=$(printf '%s\n\n%s' "$TITLE" "$MUTATIONS")
CHECK_CMD=$(jq -r '.testCommand // empty' "$ROOT/.claude/commandeck.json" 2>/dev/null || true)
CHECKED="no testCommand in .claude/commandeck.json, so no check ran"
echo "STEP 4 merge: git merge --squash $BRANCH; ${CHECK_CMD:-(no check command)}; git commit -m $(printf '%q' "$TITLE")"
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
  trap undo_squash EXIT
  git merge --squash "$BRANCH" >/dev/null || fail "step 4 merge" "squash merge conflicted; resolve in the unit worktree by rebasing onto main"
  TREE=$(git write-tree)
  # The project's check runs once, on the merged tree, before the commit exists:
  # a red check leaves main where it was and the worktree in place for the fix.
  # It runs on a copy of exactly that tree, a detached worktree outside the
  # project: main's own uncommitted edits to tracked files are not in the
  # commit, so they are not tested, and nothing the check writes lands in main.
  # shortcut: of main's untracked files the copy has only node_modules, by link; link another here when a check needs it (.env).
  # The link stays (main's ruling): a check that writes under node_modules writes main's. The doctor warns on a check that installs.
  if [ -n "$CHECK_CMD" ]; then
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
  # A build's papers are never committed: the commit holds the squash and
  # nothing else. Main's untracked brief files of the unit are archived now and
  # removed only once the merge is committed; one git tracks is left as it is
  # (the doctor names it). The tar lives in the plugin's own state, never in the project.
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
  if ! git commit -q -m "$TITLE"; then
    git diff --no-relative --cached --quiet && fail "step 4 merge" "nothing to commit: is $BRANCH already merged?"
    fail "step 4 merge" "git commit refused the squash; the cause is git's or the hook's output above"
  fi
  # A commit hook that passed may still have edited and staged files: the
  # commit then holds a tree nobody reviewed or checked, and is taken back.
  if [ "$(git rev-parse 'HEAD^{tree}')" != "$TREE" ]; then
    HOOKED=$(git diff --no-relative --name-only "$TREE" 'HEAD^{tree}' | head -5 | paste -sd' ' -)
    git reset -q --soft HEAD~1
    fail "step 4 merge" "a commit hook changed what was committed ($HOOKED), so the commit was not the tree that was reviewed and checked; it was taken back. Make that change in $WT and run another pass"
  fi
  trap merged_end EXIT
  MERGE_SHA=$(git rev-parse HEAD)
  MERGE_TREE=$(git rev-parse --short=8 "$MERGE_SHA^{tree}") TIP_TREE=$(git -C "$WT" rev-parse --short=8 'HEAD^{tree}')
  # Equality is claimed only when it holds.
  if [ "$MERGE_TREE" = "$TIP_TREE" ]; then TREES="$MERGE_TREE == unit tip tree $TIP_TREE"
  else TREES="$MERGE_TREE != unit tip tree $TIP_TREE"
  fi
  echo "step 4 evidence: merged $UNIT as $(git rev-parse --short=8 "$MERGE_SHA"); tree $TREES"
  file_open_findings "$MERGE_SHA"
  # The finished-builds record, which the dashboard lists: one line a merge, appended here and nowhere else, once
  # the commit stands. One short write in append mode, under a lock on the home folder: uninstall rewrites this
  # file for a same-named checkout under the same lock, so no line is appended to a file being replaced. The home
  # folder, because uninstall removes the builds folder and a lock on that would not outlive it. A line that
  # cannot be written (the lock held 5 s) costs the list one build, never the merge. The line names this checkout by its real path: the
  # file is named by the folder's name alone, which another checkout elsewhere may share.
  BUILDS=$HOME/.commandeck/builds/$PP_PROJECT.jsonl
  open_at() { grep -cE "^Open at merge: ([-*][[:space:]]*)?\[$1\]" <<<"$BUILDER_PROOF" || true; }
  ( exec 8<"$HOME" && flock -w 5 8 && mkdir -p "${BUILDS%/*}" && jq -cn --arg main "$(cd "$ROOT" && pwd -P)" --arg unit "$UNIT" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg sha "$MERGE_SHA" \
      --argjson p1 "$(open_at P1)" --argjson p2 "$(open_at P2)" --argjson p3 "$(open_at P3)" \
      '{$main, $unit, how: "merged", $at, $sha, open: {P1: $p1, P2: $p2, P3: $p3}}' >> "$BUILDS" ) \
    || echo "finished-builds record not written to $BUILDS: the dashboard will not list $UNIT (ignored)" >&2
  # The token ledger: a Builder's seat is never collected, it ends with this merge, so its row is written here,
  # from the record its launch left, while the worktree's session log can still be found. Never blocks a merge.
  SEAT=$PP_SCRATCH/seat-$UNIT-builder.txt
  [ ! -f "$SEAT" ] || SEAT_EVENT_WORKTREE=$WT SEAT_EVENT_AGENT=$(pp_route builder 2>/dev/null && printf '%s' "$RT_AGENT" || true) SEAT_EVENT_STOP=done \
    bash "$HERE/seat-event.sh" "$UNIT" builder "$(sed -n 's/^task=//p' "$SEAT")" "$(sed -n 's/^launched=//p' "$SEAT")" \
    || echo "no token ledger row written for $UNIT's Builder (ignored)" >&2
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    tar -C "$(dirname "$f")" -rf "$ARCHIVE" -- "$(basename "$f")" || fail "step 4 briefs" "could not append $(basename "$f") to $ARCHIVE"
    KEPT=$((KEPT + 1))
  done < <(pp_unit_briefs "$WT/.claude/briefs" "$UNIT")
  [ "${#MAIN_FILES[@]}" = 0 ] || rm -- "${MAIN_FILES[@]}" || fail "step 4 briefs" "could not remove the archived main brief files"
  echo "step 4 briefs: added $KEPT entries to $ARCHIVE"
fi

echo "STEP 5 cleanup: orca-ide terminal close --worktree $WTID --all; orca-ide worktree remove --worktree $WTID --force"
if [ "$DRY_RUN" = 0 ]; then
  # `terminal close --worktree --all` reports terminal_close_incomplete for a
  # finished reviewer pane; closing by handle succeeds every time.
  orca-ide terminal list --json | jq -r --arg wt "$WT" "$PP_PNORM"'($wt | pnorm) as $wt | (.result | if type == "array" then . else (.terminals // []) end)[] | select((.worktreePath | pnorm) == $wt) | .handle' \
    | while read -r h; do orca-ide terminal close --terminal "$h" --json >/dev/null || echo "pane $h did not close" >&2; done
  orca-ide worktree remove --worktree "$WTID" --force || fail "step 5 cleanup" "could not remove unit worktree"
  bash "$HERE/codex-helpers.sh" stop "$WT" || true
fi
echo "DONE unit=$UNIT merged=local sha=$(git rev-parse --short=8 HEAD); $CHECKED; nothing was pushed${MERGE_ISSUES:+; issues for the findings left open: $MERGE_ISSUES}"

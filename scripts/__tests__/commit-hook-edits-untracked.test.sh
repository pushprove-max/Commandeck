#!/usr/bin/env bash
# Self-test: commit-hook-edits.sh refuses while an untracked deliverable sits in
# the worktree, instead of printing `committed` and dropping it.
#
# Why this matters: the script stages with `git add -u`, which is tracked paths
# only. A brand-new evidence file or report is invisible to it, so a unit once
# shipped without its deliverable while the script reported success.
# Main reads that line and merges; the file is gone with the worktree.
#
# Each case names the mutation it catches:
#   1. dropping the refusal, so an untracked deliverable is committed away
#   2. refusing without naming the files, so main cannot act on it
#   3. refusing but committing anyway, so the refusal is cosmetic
#   4. refusing on a clean tree, which would block every ordinary hook commit
#   5. refusing on a path main named, which is the script's documented door
#   6. refusing on an ignored file, which no deliverable ever is
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT=$ROOT/scripts/commit-hook-edits.sh
SCRATCH=$(mktemp -d /tmp/commit-hook-edits-test.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi; }

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

# The script reads the workspaces root from paths.sh, which resolves it from the
# folder it runs in: a plain main checkout of its own, so the override applies.
git init -q -b main "$SCRATCH/main" && git -C "$SCRATCH/main" commit -q --allow-empty -m first
WT=$SCRATCH/ws/unit-x
fresh_worktree() { # rebuild a one-commit repo so each case starts identical
  rm -rf "$SCRATCH/ws"; mkdir -p "$WT"
  git -C "$WT" init -q
  echo tracked > "$WT/tracked.txt"
  echo 'ignored.txt' > "$WT/.gitignore"
  git -C "$WT" add -A && git -C "$WT" commit -q -m base
}
run() { (cd "$SCRATCH/main" && env -u CLAUDE_PROJECT_DIR COMMANDECK_MAIN="$SCRATCH/main" COMMANDECK_WORKSPACES="$SCRATCH/ws" COMMANDECK_SCRATCH="$SCRATCH/scratch" bash "$SCRIPT" unit-x "$@" 2>&1); }
head_count() { git -C "$WT" rev-list --count HEAD; }

# 1-3. An untracked deliverable beside a tracked edit: the exact shape that shipped without its file.
fresh_worktree
echo edited > "$WT/tracked.txt"
echo evidence > "$WT/evidence.md"
OUT=$(run "fix(unit-x): hook edits"); RC=$?
check "an untracked deliverable refuses" 3 "$RC"
check "the refusal names the file" 0 "$(grep -q 'evidence.md' <<<"$OUT" && echo 0 || echo 1)"
check "an untracked file is never committed" 1 "$(head_count)"
check "and it never says committed" 0 "$(grep -qi 'committed' <<<"$OUT" && echo 1 || echo 0)"

# 4. A tracked-only edit is the ordinary case this script exists for. Refusing
#    here would block every post-edit hook commit, which is worse than the drop.
fresh_worktree
echo edited > "$WT/tracked.txt"
OUT=$(run "fix(unit-x): hook edits"); RC=$?
check "a tracked-only edit still commits" 0 "$RC"
check "and HEAD moved" 2 "$(head_count)"

# 5. Naming the new path is the documented way past the refusal, and the file
#    must actually land in the commit -- not merely stop the complaint.
fresh_worktree
echo edited > "$WT/tracked.txt"
echo evidence > "$WT/evidence.md"
OUT=$(run "fix(unit-x): hook edits" evidence.md); RC=$?
check "a named new path commits" 0 "$RC"
check "and the deliverable is in HEAD" 0 \
  "$(grep -q '^evidence.md$' <<<"$(git -C "$WT" ls-tree --name-only HEAD)" && echo 0 || echo 1)"

# 6. Ignored files are build noise, never a deliverable. Refusing on them would
#    make the script unusable in any worktree with a local settings file.
fresh_worktree
echo edited > "$WT/tracked.txt"
echo noise > "$WT/ignored.txt"
OUT=$(run "fix(unit-x): hook edits"); RC=$?
check "an ignored file does not refuse" 0 "$RC"

# 7. The loop's own unit briefs are always untracked in a live unit and never
#    committed, so refusing on them shuts main's commit door mid-loop.
fresh_worktree
echo edited > "$WT/tracked.txt"
mkdir -p "$WT/.claude/briefs"
echo evidence > "$WT/.claude/briefs/unit-x-evidence.md"
OUT=$(run "fix(unit-x): hook edits"); RC=$?
check "untracked unit briefs do not refuse" 0 "$RC"
check "and the tracked edit is committed" 2 "$(head_count)"

# 8. Any other untracked path beside them still refuses and is named: the
#    brief carve-out must not reopen the dropped-deliverable hole.
fresh_worktree
echo edited > "$WT/tracked.txt"
mkdir -p "$WT/.claude/briefs" "$WT/src"
echo evidence > "$WT/.claude/briefs/unit-x-evidence.md"
echo code > "$WT/src/new.ts"
echo shared > "$WT/.claude/briefs/_shared.md"
OUT=$(run "fix(unit-x): hook edits"); RC=$?
check "another untracked path beside the briefs refuses" 3 "$RC"
check "the refusal names that path" 0 "$(grep -q 'src/new.ts' <<<"$OUT" && echo 0 || echo 1)"
# A new `_`-prefixed brief is a shared deliverable the loop does commit.
check "the refusal names a new shared brief" 0 "$(grep -q '_shared.md' <<<"$OUT" && echo 0 || echo 1)"
check "and does not list the unit brief" 1 "$(grep -q 'unit-x-evidence.md' <<<"$OUT" && echo 0 || echo 1)"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

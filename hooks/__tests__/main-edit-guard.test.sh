#!/usr/bin/env bash
# Guard: main-edit-guard.sh blocks product code on the main checkout and leaves
# main's own mechanism alone.
#
# WHY BOTH HALVES ARE ASSERTED. The predecessor of this hook was deleted on
# 2026-09-12 because it was too blunt: it stopped main from fixing its own
# hooks and scripts the same turn, which is the one repair main must always be
# able to make. The owner reinstated the guard on 2026-09-14 with `.claude/` carved
# out. So a change that widens the blocked set until it swallows `.claude/`
# recreates the exact problem the 09-12 deletion solved, and the ALLOWS cases
# below are the half that catches it.
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/main-edit-guard.sh"
PASS=0 FAIL=0

# The hook exits 0 in a linked worktree by design, so the cases run from a
# disposable MAIN checkout: a run from a worker worktree still exercises them.
# It lives in the checkout, not the temp root: Linux mktemp answers /tmp/...,
# which the hook passes as scratchpad before the product rules, so the six
# blocking cases would pass there. Physical path: git answers /private/var/...
R=$(cd "$(mktemp -d "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/main-edit-guard.XXXXXX")" && pwd -P)
git -C "$R" init -q
mkdir -p "$R/.claude/hooks" "$R/docs"
for f in .claude/hooks/a.sh .claude/hooks/b.sh .claude/hooks/c.sh .claude/hooks/d.sh docs/x.txt notes.md; do
  echo x > "$R/$f"
done
git -C "$R" add -A && git -C "$R" -c user.name=t -c user.email=t@t commit -qm init
cd "$R" || exit 1

# The escape hatches would pass every blocking case. Clear them for the run.
unset COMMANDECK_MAIN_EDITS_OK
PROJ=$(mktemp -d); trap 'cd /; git -C "$R" worktree remove --force "$R-wt" >/dev/null 2>&1; rm -rf "$PROJ" "$R" "$R-wt" "${OTHER-}"' EXIT
export CLAUDE_PROJECT_DIR=$PROJ

check() { # name expected-rc path
  printf '{"tool_input":{"file_path":"%s","content":"x"}}' "$3" | "$HOOK" >/dev/null 2>&1
  local rc=$?
  if [ "$rc" = "$2" ]; then PASS=$((PASS + 1)); echo "ok   $1"
  else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected rc=$2, got rc=$rc)"; fi
}

# Its branch is named after the directory; the worktree is a worker's.
git -C "$R" worktree add -q "$R-wt" >/dev/null 2>&1 || { FAIL=$((FAIL + 1)); echo "FAIL the worker worktree could not be created"; }
OTHER=$(mktemp -d); git -C "$OTHER" init -q

# Blocked: project code, wherever the project keeps it. The hook knows no
# directory names: a project with no src/ is guarded the same.
check "blocks src/"                2 "$R/src/services/a.ts"
check "blocks any other directory" 2 "$R/lib/deep/b.py"
check "blocks a root file"         2 "$R/Makefile"
# Reaching into a worker's worktree by absolute path is the same violation.
check "blocks a worktree's file"   2 "$R-wt/src/a.ts"
# A worktree kept under .claude is a worker's code like any other: main's
# .claude is exempt, not every path with .claude somewhere above the file.
git -C "$R" worktree add -q "$R/.claude/worktrees/unit" -b inner >/dev/null 2>&1 || { FAIL=$((FAIL + 1)); echo "FAIL the inner worktree could not be created"; }
check "blocks code in a worktree kept under .claude" 2 "$R/.claude/worktrees/unit/src/a.ts"
check "allows that worktree's own .claude"           0 "$R/.claude/worktrees/unit/.claude/hooks/a.sh"
check "allows that worktree's docs"                  0 "$R/.claude/worktrees/unit/docs/x.txt"

# Allowed: what main owns, and what is not this project's at all.
check "allows .claude/briefs/"     0 "$R/.claude/briefs/some-unit.md"
check "allows .claude/ config"     0 "$R/.claude/commandeck.json"
check "allows .githooks/"          0 "$R/.githooks/pre-push"
check "allows docs/"               0 "$R/docs/lessons/history.txt"
check "allows any *.md"            0 "$R/src/README.md"
check "allows the scratchpad"      0 "/tmp/claude-1000/x/scratchpad/notes.txt"
check "allows checkpoints"         0 "$HOME/.claude/checkpoints/abc.txt"
check "allows another repository"  0 "$OTHER/src/a.ts"

# The escape hatch opens the block, and only the block.
printf '{"tool_input":{"file_path":"%s","content":"x"}}' "$R/src/a.ts" \
  | COMMANDECK_MAIN_EDITS_OK=1 "$HOOK" >/dev/null 2>&1
if [ $? = 0 ]; then PASS=$((PASS + 1)); echo "ok   COMMANDECK_MAIN_EDITS_OK opens src/"
else FAIL=$((FAIL + 1)); echo "FAIL COMMANDECK_MAIN_EDITS_OK opens src/"; fi
# The first line names the action, and a Bash retry is closed off up front, so
# the next turn dispatches instead of trying sed -i.
MSG=$(printf '{"tool_input":{"file_path":"%s"}}' "$R/src/a.ts" | "$HOOK" 2>&1 >/dev/null)
case "$(head -1 <<<"$MSG")" in "BLOCKED: hand this edit to a worker: write the batch brief, then "*"/scripts/builder-launch.sh <unit> <batch-brief>."*)
  PASS=$((PASS + 1)); echo "ok   the product-code block leads with the dispatch" ;;
  *) FAIL=$((FAIL + 1)); echo "FAIL the product-code block leads with the dispatch: $(head -1 <<<"$MSG")" ;; esac
# The old unit loop is archived: the block must not send main to a script that is gone.
case "$MSG" in *loop-run.sh*|*unit-drive.sh*|*"launch implementer"*) FAIL=$((FAIL + 1)); echo "FAIL the product-code block names no archived loop script" ;;
  *) PASS=$((PASS + 1)); echo "ok   the product-code block names no archived loop script" ;; esac
case "$MSG" in *"Do not retry it through Bash (sed -i, a redirect, tee)."*) PASS=$((PASS + 1)); echo "ok   the product-code block closes the Bash retry" ;;
  *) FAIL=$((FAIL + 1)); echo "FAIL the product-code block closes the Bash retry" ;; esac
mkdir -p "$PROJ/.claude/approvals"; : > "$PROJ/.claude/approvals/main-edits-ok"
check "the main-edits-ok file opens src/" 0 "$R/src/a.ts"

# --- a 4th file in one uncommitted change set goes to a seat (2026-10-01) -----
# Main typing a multi-file diff itself is the waste this cap cuts: past three
# files outside briefs, rules, todo, docs, memory and *.md, it dispatches.
echo y > .claude/hooks/a.sh; echo y > .claude/hooks/b.sh
echo y > notes.md; echo y > docs/x.txt
check "a 3rd file with 2 modified passes"            0 "$R/.claude/hooks/c.sh"
# A Codex patch reaches the hook one file at a time, none of them written yet:
# codex-dispatch.sh names the patch's other files, and they count.
batch() { jq -cn --arg p "$1" --arg r "$R" '{tool_input: {file_path: $p, content: "x", batch_paths: [$r + "/.claude/hooks/c.sh", $r + "/.claude/hooks/d.sh", $r + "/notes.md"]}}' | "$HOOK" >/dev/null 2>&1; echo $?; }
if [ "$(batch "$R/.claude/hooks/c.sh")" = 2 ]; then PASS=$((PASS + 1)); echo "ok   a patch whose files make four is blocked at its first"; else FAIL=$((FAIL + 1)); echo "FAIL a patch whose files make four is blocked at its first"; fi
echo y > .claude/hooks/c.sh
check "a 4th file is blocked"                        2 "$R/.claude/hooks/d.sh"
check "a new 4th file is blocked"                    2 "$R/.claude/hooks/new.sh"
check "the hatch file does not lift the cap"         2 "$R/.claude/hooks/d.sh"
check "an already-modified file passes"              0 "$R/.claude/hooks/a.sh"
check "a brief passes"                               0 "$R/.claude/briefs/u.md"
check "a rule passes"                                0 "$R/.claude/rules/x.txt"
check "task-list directory passes"                        0 "$R/todo/list.txt"
check "docs/ passes"                                 0 "$R/docs/y.txt"
check "any *.md passes"                              0 "$R/.claude/hooks/README.md"
check "memory outside the repo passes"               0 "$HOME/.claude/projects/p/memory/m.txt"
MSG=$(printf '{"tool_input":{"file_path":"%s"}}' "$R/.claude/hooks/d.sh" | "$HOOK" 2>&1 >/dev/null)
case "$MSG" in *"builder-launch.sh <unit> <batch-brief>"*) PASS=$((PASS + 1)); echo "ok   the block names builder-launch.sh" ;;
  *) FAIL=$((FAIL + 1)); echo "FAIL the block names builder-launch.sh" ;; esac
case "$(head -1 <<<"$MSG")" in "BLOCKED: hand this edit to a worker:"*) PASS=$((PASS + 1)); echo "ok   the cap block leads with the dispatch" ;;
  *) FAIL=$((FAIL + 1)); echo "FAIL the cap block leads with the dispatch: $(head -1 <<<"$MSG")" ;; esac
case "$MSG" in *"Do not retry it through Bash"*) PASS=$((PASS + 1)); echo "ok   the cap block closes the Bash retry" ;;
  *) FAIL=$((FAIL + 1)); echo "FAIL the cap block closes the Bash retry" ;; esac
( cd "$R-wt" && for f in a b c; do echo y > .claude/hooks/$f.sh; done
  printf '{"tool_input":{"file_path":"%s"}}' "$R-wt/.claude/hooks/d.sh" | "$HOOK" >/dev/null 2>&1 )
if [ $? = 0 ]; then PASS=$((PASS + 1)); echo "ok   a worker worktree is not capped"
else FAIL=$((FAIL + 1)); echo "FAIL a worker worktree is not capped"; fi

echo "main-edit-guard: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

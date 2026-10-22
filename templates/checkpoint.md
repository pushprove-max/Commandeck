# Checkpoint <session id> -- <date time ET>

Fixed shape (ruling 2026-09-12): every field filled or "none". What is
not here is lost at /clear; the Orca task list and the unit ledger survive.

## Goal
<one line: the batch, the standing rulings that bind it>

## Live units (one line each)
Task ids, pane handles, paths and live jobs are not written by hand here
(`state-snapshot.sh` fills its own columns for them): `board.sh`, which the
resume block carries, prints them current.
| unit | stage | next |
|---|---|---|

## Waiting on
- <marker or verdict> from <pane> -> <the exact command main runs when it lands>

## Rulings this session not yet in memory or a rule file
Sweep first: run `bash scripts/repeat-report.sh` and turn its top
items into fixes. Then every correction or ruling from the owner this session, and every
friction main hit twice, is saved to memory or a rule, or fixed, BEFORE this
is written. List here only what could not be saved yet, and why.
- <ruling, who, when>

## Queue (in order)
- Q-<n> <unit not started, with its blocker>; n is the next free number, never reused, and Q-<n> is the item's key however it is reworded

## Todo list (the owner's on-screen checklist; the resumed main rebuilds it first)
- [x|>| ] <one step each: done, in progress, next; same wording as the live list>


## Gotchas learned this session
Only what CHANGED this session, or a fact a person had to decide. Stable tool
behaviour does not go here: fix the tool, or put it in the tool's own header.
A documented footgun is re-read every session forever and goes stale silently.
- <one line each; promote to memory if it will matter next week>

## Ruled out
- <approach tried or rejected> -- <why, and what would reopen it>; or "none"

## How to verify
- <literal command that proves a claim above> -- <what it shows>; or "none"

## Carried by reference
Older open items are not copied here. Write one line, at the start of
the line, `Carries open items of: <checkpoint file>` for the checkpoint this
session resumed from, or "none" on a fresh start. The carry-over check follows
that file and its own references.

## Closed since last checkpoint
Every open item (Waiting on, unsaved rulings, Queue, unchecked or > Todo) of
the checkpoint this session resumed from stays open above, is carried by
reference, or is closed here; the restart is refused otherwise. A
carried item that is done is closed here, verbatim, with what closed it: one
line per item, each with its own reason (`Q-<n> -- <reason>` closes a Queue item).
- <the prior item, verbatim> -- <what closed it>; or "none"

## Resume
- NOTHING TO FETCH after the restart: `hooks/resume-context.sh`
  already put the run binding, `board.sh` and this file in the SessionStart
  context. If it says NOT BOUND, run the `run-use` it names first.
  Do not retype a path, a run id or a handle from this file; read them from
  that board, which is current.
- CARRIED ITEMS ARE NOT IN THIS FILE. When a unit, ruling or task that is not
  listed above comes up, Read the file named on the `Carries open items of:`
  line (and the files it carries) before acting on it.
- The handoff already swept finished panes; close any the board still lists
  under "finished panes" with `bash scripts/close-done-panes.sh --close`.
- ADOPT THE SEAT ON THE DRIVER LINE BEFORE ACTING. `board.sh`'s seat list is
  built from seat record files, and a loop-dispatched implementer or fixer has
  none, so a live one does not appear there. Its `role=`/`task=` line is on the
  driver, printed by the agent-awareness hook every turn and by
  `orca-wait.sh`. A driver line naming a role means that seat is working NOW:
  wait on it, never re-dispatch the unit and never merge the worktree.
- "IS THIS UNIT BUILT" IS THE BRANCH TIP, NEVER THE DIFFSTAT.
  `git -C <main> log --oneline main..<unit-branch>`. A seat commits its work,
  so `git -C <wt> diff --stat` and the board's dirty count are both empty on a
  finished unit and read as "nothing was done".
- TODO LIST: recreate only the unfinished items, `[ ]` next and `[>]` in progress (status in_progress), every TaskCreate in ONE reply; `[x]` items stay done in this checkpoint and are not recreated. Later updates ride in the same reply as the work they record.
  Load the tools via ToolSearch `select:TaskCreate,TaskUpdate,TaskList`
  (`templates/main-session.md`, Show the owner a checklist).
- Nothing to arm: main-watch.sh posts every finished, unhandled item
  and Orca's nudge wakes main. On a nudge, drain in the foreground with
  `bash scripts/orca-wait.sh`, and close an item's task once handled.
  If the board says MAIN-WATCH NOT RUNNING, run
  `bash scripts/main-watch.sh --install` first.

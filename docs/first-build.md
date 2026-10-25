# The first build

`$PLUGIN` is the installed plugin folder. After setup, `PLUGIN="$HOME/.commandeck/plugin"` works (see [Install](install.md)).

After setup, the Claude session in the project's main checkout is the
orchestrator. You tell it what you want in plain words. It writes a batch
brief with you (the items and how each will be judged done), picks
a plan tier from the trigger file (no plan, one planner, a plan and a judge, or a panel
of two plans, two judges and one merge) and tells you the tier, trigger, models and effort in one line;
change the trigger file or `/plugin` settings, or say so in chat, and once you say go launches a Builder (a batch that
names no committed plan is refused unless launched with
the explicit skip shown below; the Builder can take over the unit's
planning worktree once its plan is on main):

```bash
bash "$PLUGIN/scripts/builder-launch.sh" add-csv-export .claude/briefs/add-csv-export-batch.md
```

You do not type that; the orchestrator does. The launcher makes a new Orca
worktree on local `main` (after fast-forwarding from `origin` where available),
puts the rendered brief in it, opens one Builder
pane and prints one line:

```
seat=builder unit=add-csv-export handle=term_… task=task_… state=… record=…
```

The Builder builds the batch, then runs its own review passes with
`builder-codex-pass.sh`, on the reviewer the `codexReviewerAgent` key
names (Codex, or Claude in the `claude` profile). Each pass commits the worktree first, excluding its brief files, so the
reviewer reads a fixed commit, and writes a round file from the reviewer's own session record.
The merge takes the verdict from the reviewer's session files and not from
the round file, so a round file written by hand merges nothing. That stops a
Builder from passing itself by mistake. The session files belong to the same
user, so it does not stop an agent that sets out to forge one. A pass prints:

```
add-csv-export-r1-reports.md: VERDICT: GO (adversarial pass on 3f9c2a1, …)
```

A watcher service, `main-watch.sh`, installed by setup, posts a message to
the orchestrator when the Builder's pane stops (not while it waits on a helper
or a review pass it started, for up to an hour). The orchestrator then runs
the merge from the main checkout:

```bash
bash "$PLUGIN/scripts/merge-unit-local.sh" add-csv-export
```

From the orchestrator's session the merge detaches: it prints `running detached as pid N; watch <log>` and keeps
running after the shell call ends. Wait on that log (its last line is `DONE unit=…` or `FAILED …`) or on the message the
merge sends when it ends; never run it again. While it holds main it keeps its state in `.git/merge-unit-local.state`,
and `git stash`, `checkout`, `reset`, `clean` and edits in main are refused, naming the merge. A second request for the
same unit at the same commit, running or waiting, is a no-op (exit 4).

```
STEP 1 preconditions: main=… worktree=… branch=add-csv-export
STEP 2 rebase: git -C … rebase main
STEP 4 size: 4 files changed, 212 insertions(+), 9 deletions(-)
STEP 4 merge: git merge --squash add-csv-export; npm test; git commit -m …
STEP 5 cleanup: orca-ide terminal close --worktree … --all; orca-ide worktree remove --worktree … --force
DONE unit=add-csv-export merged=local sha=8d41e07; …; nothing was pushed
```

A project that runs its own watcher and posts Claude Code's heads-up notes itself writes
`<scratch>/heads-up-owner` (`pid=`, `main=` the full checkout path, `at=` epoch, no later than that cycle's
read of the offer store) each cycle it posts.
While that claim is live (pid alive, same checkout, under 300 s old), `main-watch.sh` posts nothing: no
finished, stopped, stalled or heads-up item, so write the claim only on a cycle that posts all of them. It
counts a note as the owner's only when the offer was shown before `at=` and is still shown, and any other item
as the owner's once `at=` is past the tick that first saw it; the rest wait and are posted once the claim ends.
An item the owner posted is not handled: once the claim ends, it is reminded every 5 minutes until main closes its task.
A watcher that stands down writes no claim.

Those are some of the lines the scripts print, with example values filled
in. Between
steps 2 and 4 the merge looks up the reviewer's session and refuses when the
proof is missing or older than the branch tip. It runs your test command once
on a copy of the squashed tree before it commits, and a red run undoes the
squash. Then it closes the unit's panes and removes the worktree. It does
not write the build review: that runs only when you ask for it.

To inspect worktrees, seats and open tasks:

```bash
bash "$PLUGIN/scripts/board.sh"
```

To check merge preconditions and print its plan without rebasing, merging or
removing the worktree:

```bash
bash "$PLUGIN/scripts/merge-unit-local.sh" add-csv-export --dry-run
```

This dry run does not run the configured test command. A failed real check
undoes the squash. Exit 3 means the merge committed but archiving or cleanup
failed: finish that step by hand. Do not merge an already merged unit again.

The launcher refuses a batch without a nonempty plan committed on `main`,
unless main explicitly records a skip:

```bash
bash "$PLUGIN/scripts/builder-launch.sh" --skip-plan --reason 'Small documentation change' add-csv-export .claude/briefs/add-csv-export-batch.md
```

Auto planning reads `config/plan-triggers.tsv`, or the project's
`.claude/plan-triggers.tsv`, and reports the tier and trigger it chose. The
batch and Builder templates are in `templates/`. Main should write explicit
acceptance criteria and a merge check before launching.

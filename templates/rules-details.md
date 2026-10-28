# Rule details

Never injected. A `Details, <this file>, <Section>.` stub in an always-on file
points here; read the section when the task it names comes up. The text below
moved out of `AGENT_STARTUP.md` and `global-rules.md` unchanged.

## Launching a Builder

1. Main: `bash scripts/builder-launch.sh <unit> <batch file>` opens the
   worktree, the brief and the Builder pane. With `--risky` the merge waits on
   three reviewers.
   A tooling build expected under 200 changed lines is launched `--small` on
   the smaller model with `--model sonnet --reason '<one line>'`: no advisor
   unless it is `--risky`, and the pick is logged in `.claude/routing-log`. A
   risky one stays on the configured model, and its batch brief says to write
   the failing test first. The batch file starts as
   `templates/_batch-brief-template.md` does, with `## The issues`: the
   dashboard lists a build's issues from it, and `--dry-run` says so when it
   finds none. Its `## Plan` section names the plan, committed in main; with
   no plan the launch is refused unless main passes
   `--skip-plan --reason '<one line>'`, which the brief, the evidence and
   `.claude/routing-log` record.

## Merging a unit

4. Main: `bash scripts/merge-unit-local.sh <unit>` checks the GO pass against
   the reviewed commit and squash-merges the branch. No proof, no merge.
   From main's foreground the merge detaches: it prints "running detached as
   pid N; watch <log>" and keeps running after the shell call ends. A
   half-merged main tree while it runs is the merge at work, not leftovers. Its
   state (unit, reviewed sha, pid, stage) is in `.git/merge-unit-local.state`
   while it holds main; the file is gone when it ends, and a pid that is dead
   is a stale lock. Wait for the end of the log (`DONE unit=..` or a `FAILED`
   line) or for the message it sends main. Never re-run it, and never stash,
   reset or check out in main under it: the same unit at the same sha, running
   or waiting, is refused with exit 4, and the guard refuses those commands and
   edits in main, naming the merge.

## Planning and evidence

- Name a drift guard for what it guards: it fails when two copies of one fact
  disagree, and its name says which two.
- Write the review questions before the code: the brief's "How this will be
  reviewed" lists what the reviewer will check, and the builder answers each in
  the evidence file before reporting.
- Write the evidence file as the work goes: a section per item, added when that
  item's check passes. It is the resume point after a crash and the proof for
  the reviewer.
- A brief whose cuts run past an hour names its halfway cut. At that cut the
  Builder writes a halfway note of about 200 tokens in the evidence file (what
  is built, what is left, what is decided) and goes on.
- A unit over the size caps is split by default. Main keeps it whole only with a
  `Split override: <reason>` line in the plan; a bare `Split override:` is no override.
- Acceptance criteria that change behaviour name the test file and the exact
  cases. The failing test comes first.
- "Create a PR" is a request to open a pull request for work already done.
  It is never an order to build something new.

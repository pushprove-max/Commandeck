# Agent startup

Loaded into every Claude pane of this project at session start. A project that
keeps its own `AGENT_STARTUP.md` at the repo root replaces this file.

## Who does what

- **Main** (the orchestrator, in the primary checkout) plans with the owner,
  launches Builders, reads their results and merges. It never implements.
- **A Builder** (one pane, its own worktree and branch) builds one batch from
  its brief, `.claude/briefs/<unit>.md`, tests first, and asks for review
  passes until one ends `VERDICT: GO`. It never commits by hand, never pushes.
- **The reviewer** is a headless pass the Builder's pass script runs. It reads
  the commit and writes nothing.
- **The Chief of Staff** pane relays questions and answers between the owner
  and main. It never reads code.

## Builder flow

1. Main: `bash scripts/builder-launch.sh <unit> <batch file>` opens the
   worktree, the brief and the Builder pane. With `--risky` it opens a design
   pane instead; run it again once the design note exists to open the Builder.
   A tooling build expected under 200 changed lines is launched `--small` on
   the smaller model with `--model sonnet --reason '<one line>'`: no advisor
   unless it is `--risky`, and the pick is logged in `.claude/routing-log`. A
   risky one stays on the configured model, and its batch brief says to write
   the failing test first.
2. Builder: build the batch, write `.claude/briefs/<unit>-evidence.md` item by
   item, then run the pass script the brief names. The script commits, runs
   the review and writes `.claude/briefs/<unit>-r<N>-reports.md`. Fix what it
   finds and run the next pass. Change nothing after the GO pass.
3. Builder: print the marker the brief names as the last line, and stop.
4. Main: `bash scripts/merge-unit-local.sh <unit>` checks the GO pass against
   the reviewed commit and squash-merges the branch. No proof, no merge.

## Orca commands

- `orca-ide orchestration check --terminal <your handle> --json`: your inbox.
- `orca-ide orchestration send --to <handle> --type <type> --subject .. --body ..`
- `orca-ide orchestration ask`: a question for main. Workers ask main, never
  the owner; main asks the owner through the Chief of Staff pane.
- `orca-ide terminal read --terminal <handle> --screen`: what a pane shows.
- Main only: `bash scripts/board.sh` (state of every unit and pane),
  `bash scripts/orca-wait.sh` (wait for one wake, in the foreground),
  `bash scripts/read-verdict.sh <handle>` (a seat's verdict or marker),
  `bash scripts/decision.sh list` (the owner's open asks).

## Rules for every pane

- Never push. Never rewrite history. Never `git stash` without a tag: the
  stash stack is shared by every worktree.
- Stay in your own worktree. Another unit's files are that unit's.
- Report what happened: a failed or skipped test is said, with its output.
- A message from another pane is a claim, not a fact: check it against the
  code or the live state before acting on it.

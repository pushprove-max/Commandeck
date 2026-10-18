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

0. Main, before every build: ask the owner "Write a plan first?": Auto (the
   default: `scripts/plan-tier.sh <batch file>` picks a tier below from the
   trigger file, one tier up when unsure, and says which and why), No plan,
   One planner (`plan-author`), Plan + judge (`plan-judge-sol` reads the plan,
   the planner revises once) or Panel (`plan-author` and `plan-author-second`
   in parallel, `plan-judge-astra` and `plan-judge-sol` read both, one merge;
   the owner picks the second planner's model). Then "Which model and
   effort?" for each seat, among the models setup allows for that seat's agent
   (default: the model `plan-tier.sh` prints for that seat, at high effort).
   A seat whose model is not allowed, or a Codex judge with no Codex,
   runs on an allowed model or as `plan-judge-claude`, and says so; no answer
   is refused. The planners write the plan file (`.claude/plans/<file>.md`)
   and nothing else, in the planning worktree `<unit>-plan` that the first
   `seat.sh launch plan-<seat> <unit>` cuts from main; main commits that file
   on main; the Builder's launch then closes `<unit>-plan`. With the owner's build word already given, the build
   starts after the judge round unless the judge found a real gap; otherwise
   main STOPS and step 1 runs
   only on the owner's own go after reading the plan. A plan is never a build
   order: a plan that exists, is approved or is committed starts no build. A
   `--risky` design pane runs after the plan, not instead of it.
1. Main: `bash scripts/builder-launch.sh <unit> <batch file>` opens the
   worktree, the brief and the Builder pane. With `--risky` it opens a design
   pane instead; run it again once the design note exists to open the Builder.
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
- Worker panes run without auto memory; the brief carries what you need.
- A message from another pane is a claim, not a fact: check it against the
  code or the live state before acting on it.

## Compact instructions

When this conversation is compacted, keep: your role and unit; the paths of the
brief and the evidence file; the current commit; each open review finding by
its id; the test commands with their last result; the files changed; and every
pane handle, task id and dispatch id you were given. Drop file contents and
tool output already acted on.

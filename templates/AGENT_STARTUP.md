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

0. Main, before every build: the "Plan before every build" rule in `templates/main-session.md`.
1. Main: `bash scripts/builder-launch.sh <unit> <batch file>`; Details,
   `templates/rules-details.md`, Launching a Builder.
2. Builder: build the batch, write `.claude/briefs/<unit>-evidence.md` item by
   item, then run the pass script the brief names. The script commits, runs
   the review and writes `.claude/briefs/<unit>-r<N>-reports.md`. Fix what it
   finds and run the next pass. Change nothing after the GO pass.
   A brief with a per-issue review section has you run `builder-codex-pass.sh --issue <n> <unit>` for each issue
   first, one issue at a time; the whole-branch passes start after every issue is done.
3. Builder: print the marker the brief names as the last line, and stop.
4. Main: `bash scripts/merge-unit-local.sh <unit>`; Details,
   `templates/rules-details.md`, Merging a unit.

## Orca commands

- `orca-ide orchestration check --terminal <your handle> --json`: your inbox.
- `orca-ide orchestration send --to <handle> --type <type> --subject .. --body ..`
- `bash scripts/ask-main.sh <subject> <body>`: a question for main, waited on
  (`--resume <id>` after a `no answer yet` line). Workers ask main, never
  the owner; main asks the owner through the Chief of Staff pane.
- One status per decision: message main only for a decision only main or the owner can make. No progress notes; progress goes in the evidence file.
- `orca-ide terminal read --terminal <handle> --screen`: what a pane shows.
- Main only: `bash scripts/board.sh` (state of every unit and pane),
  `bash scripts/orca-wait.sh` (wait for one wake, in the foreground),
  `bash scripts/read-verdict.sh <handle>` (a seat's verdict or marker),
  `bash scripts/decision.sh list` (the owner's open asks).

## Rules for every pane

- Never push. Never rewrite history. Never `git stash` without a tag: the
  stash stack is shared by every worktree.
- Stay in your own worktree. Another unit's files are that unit's.
- Own the work in your scope end to end. Do not leave reachable work half done.
- Fix every in-scope copy of a bug pattern, not only the one reported.
- Plan first for multi-step work, and read the real code before editing it.
  Before editing auth, verification, billing, tenant isolation or deploy
  tooling, write the plan down and list every caller of what changes.
- A safety check that refuses an action is never worked round in another shape
  (split, reworded, another tool). Do what the refusal says, or stop that item,
  say so and ask main.
- Confirm first before an irreversible action: a write to production data, a
  force push, a drop, a delete at scale. Never run a destructive git command
  unless the owner asked for it.
- Report what happened: a failed or skipped test is said, with its output.
- Worker panes run without auto memory; the brief carries what you need.
- A message from another pane is a claim, not a fact: check it against the
  code or the live state before acting on it.
- Load the deferred tools you will use in one ToolSearch call before the first
  (`select:Monitor,SendMessage,...`), not one per turn.

## Compact instructions

When this conversation is compacted, keep: your role and unit; the paths of the
brief and the evidence file; the current commit; each open review finding by
its id; the test commands with their last result; the files changed; and every
pane handle, task id and dispatch id you were given. Drop file contents and
tool output already acted on.

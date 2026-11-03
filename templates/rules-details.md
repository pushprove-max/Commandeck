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

A Builder pass that failed twice on one tree for one reason (the refusal names it) is refused a third start, and the
Builder asks main. Decide from the reason; to let the same tree run again, remove the record in the Builder worktree's
git dir: `rm "$(git -C <worktree> rev-parse --absolute-git-dir)/builder-pass-failed"`. A changed tree needs no reset.

Before the closing pass the Builder lands all pending work: main's judges answered, `post-fix-checks.sh` green on the
touched tests. The closing pass then runs the tests that cover the branch's changes, even when main has not moved, and
refuses while an owner question on the unit is open, so a question that blocks the merge goes to main the turn it is
named.

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
- A unit over the size caps (`review-limits` in `config/routing.json`: `diffLines` 1000 changed lines, `maxIssues` 5
  Closes issues; plan-check.sh refuses a plan over either) is split by default. Main keeps it whole only with a
  `Split override: <reason>` line in the plan; a bare `Split override:` is no override.
- Acceptance criteria that change behaviour name the test file and the exact
  cases. The failing test comes first.
- "Create a PR" is a request to open a pull request for work already done.
  It is never an order to build something new.

## Drift guard example

The drift guard named under Planning and evidence has a runnable example, `templates/drift-guard-example.sh`. It takes
two files, each with a `Retry limit:` line, and fails naming both files when the two lines differ. Copy it, change the
fact it reads, and name the copy for the two places it guards.

## Token efficiency

Every tool call re-sends the whole accumulated context to the model. A turn
with one tool call and a turn with six cost about the same in input tokens;
six *sequential* turns cost six full context replays. Most rules below follow
from that. None of them mean verifying less -- they mean not paying for the
same information twice. Hook-enforced specifics stay beside their hooks.

- Before the first tool call, plan the minimal read -> change -> verify route.
- Issue demonstrably independent inspections **in one turn**, using the
  native parallel interface of your agent. Do not emulate missing parallel
  support with shell chains or throwaway scripts.
- Put an operation in a batch only when all its inputs are known up front and
  it does not depend on another member of that batch. A batch built on a
  guessed input gets discarded and redone, which costs more than running it
  sequentially.
- Keep sequential: dependencies, waits, approvals, interdependent edits,
  anything irreversible, and adaptive investigation where each result changes
  the next question.
- Inspect every result and every error. Batching is about issuing calls
  together, not about reading them less carefully.
- **Before any test run, name what it will prove.** Run the smallest set of
  tests that would fail if your change were wrong. Do not re-run a test whose
  inputs have not changed since it passed. Run the full suite only when
  product code changed since the last full pass, or when a push or merge guard
  requires it. A fix to tooling tests, a scanner allow-list, or a timeout
  re-runs only those tests.
- Never repeat an expensive run without a material difference in what is
  being run.
- Check whether something already exists before building it. A short search
  costs far less than generated code that is later deleted.
- Check what has already been decided before proposing or reopening work.
  Re-deriving a settled conclusion is the most expensive form of duplicate
  work.
- Before an edit, pick the cheapest decisive test. A wrong speculative edit
  costs the edit, the verification and the revert.
- Put raw output in files; keep only status, errors, warnings, the decisive
  lines and the source path in the reply. Large logs then never enter the
  context window at all.
- No broad scans "just to be safe". Stay inside the current scope and the
  active hypothesis.
- Startup files (`AGENT_STARTUP.md`, `CLAUDE.md`, `.claude/rules/*`) change
  only between batches: open panes read them once at launch, and a mid-run
  edit in main moves the tree under a running check chain.
- One topic per task. Start a new task on real objective drift instead of
  letting unrelated threads accumulate -- old context is a tax on every
  remaining call in the session.
- Answer wording and documentation questions directly; do not open the
  repository unless the answer depends on it.
- Do not idle-wait when there is safe reserve work toward the same goal. Do
  not invent work to look busy when there is none -- waiting is then the
  correct action.

## Tests and comments

- Never assert on wall-clock timing. Mock timers, and restore them in a teardown hook.
- A process-wide mock retains call args: restore it in a teardown hook, and never push into an unbounded array from inside a mock.
- Not run: the run of every touched test together before review; a rerun of
  unchanged code that already gave a result, pass or fail; timing runs, unless
  the issue itself asks for a measurement.
- A test result the Builder reads goes into its evidence file with the
  machine's load beside it (`hs_stamp` in `scripts/host-services.sh`),
  so a slow run reads as load, not as the code.
- Load a route/service graph EXACTLY ONCE per test file. Never
  `delete require.cache[...]` and re-require in-process; a fresh instance
  belongs in a separate test file.
- Test behaviour through public interfaces: the exported function, the route,
  the component as a user drives it. Never implementation details or private
  helpers.
- One test per distinct behaviour or failure mode. Cases in the same
  equivalence class are one parametrized (table-driven) test, not several.
- Do not test trivial getters and setters, framework or library behaviour,
  guarantees the type system already gives, or inputs the system cannot
  receive.
- No test whose only assertion is that a mock was called.

### A comment earns its place only by stating what the code cannot

- WHY: the constraint or decision behind non-obvious code, in one line.
- Ceilings: a deliberate shortcut names its limit and upgrade path, in a plain
  comment with no tag.
- Cross-file contracts: sibling paths that must stay in parity, SSOT
  pointers, "every caller assumes X" invariants.
- Warnings: what not to do here and what breaks if you do.

### Editorial guidance — keep cleanup within the changed lines or a requested sweep

- Narration: restating what the next line does.
- Prefer constraints and contracts to change history. Preserve history that
  explains a current constraint.
- Attribution and credits: reviewer names, P-levels, model or tool credits
  ("Claude", "Codex", "Generated with ...", Co-Authored-By lines).
  Hook-enforced: hooks/edit-content-tripwires.sh.
- Commented-out code. Git keeps it; delete it.
- A TODO with no owner: new TODOs carry a GitHub issue ref
  (`TODO(#123): ...`).

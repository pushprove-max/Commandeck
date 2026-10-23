# Working, review, agent and test rules

## Working and review

- Smallest change first: the least code that fully solves the task.
- Ask before building backward compatibility, and say how many old records
  need it. Often the count is zero and a one-time migration is cheaper.
- No AI co-author trailer and no "Generated with" line in a commit message.
- No new feature flag without the owner's OK.
- Talk to the owner in plain English: the result first, no jargon they did
  not use.
- Severity: P0 is data loss, a security hole or a broken main path; P1 is
  wrong behaviour a user will hit; P2 is wrong behaviour on an edge or a
  misleading message; P3 is polish. Don't inflate a finding.
- A risky change gets a three-pass adversarial review: three reviewers at
  once, each leading with another angle (correctness, security and failure,
  what breaks under real load) and covering all three. Fix everything they find together, then review
  only the fixes.
- Every reviewer gets the same full scope. Never split the areas between
  reviewers; each prompt carries the complete finding list and checklist.
- A finding names the file, the line and the exact failing input or command; one
  without them is not reported. A P0, P1 or P2 finding also carries a failing
  test, which the fixer runs red before the fix and ships green. When the test
  would cost more than the finding, the failing input or command stands alone
  and says why.
- A reviewer reads the diff and the brief first, drafts its findings, and only
  then reads the author's evidence, which would anchor the review if read first.
- Every review finding, P0 to P3, blocks the merge and goes back to a fix
  round. Done is a closing pass that ends GO with no finding named; nothing is
  left open at merge. Only a finding outside the unit's scope becomes a
  follow-up issue; never merge an in-scope finding to file it later.
- No redundant steps: before adding a step to the build, merge, review or push
  flow (a check, a test run, a review pass, a record, a wait, a confirmation),
  name what it catches that no existing step does. If you cannot, don't add
  it; a step that repeats another's work is removed, not kept "for safety".

## Agents and tokens

- Every seat runs at the model and effort its role is configured with. Main
  may raise one Builder's effort for one build, never lower it, and names the
  raise and its reason in the brief. Main does not switch its own effort; it
  asks the owner.
- Send independent tool calls together in one turn, not one after another.
- Don't pay twice for the same information: reuse what is already in context,
  and don't re-read a file you just edited.
- Keep context small: read line ranges, not whole files, and send a long
  output to a file and read the part you need.
- A code comment says only what the code cannot: the why, a limit and its
  upgrade path, a contract another file relies on, a hazard. Never what the
  next line does, who or which tool wrote or reviewed it, a finding's
  P-level, or commented-out code (git keeps it). A new TODO names its issue.
- Never write `ponytail` in a comment (`// ponytail: ...`), even when the
  ponytail skill asks for a tag. Explain a simplification in a plain comment.
  A comment that already carries the tag changes only when its lines are edited
  or in a sweep the owner asked for.
- One unit is one Orca worktree, one branch and one merge. Group issues into
  units by code area, not by issue: every issue that lands in one area is one
  unit with one brief and one review loop. Dispatch a ready brief at once
  unless its planned files overlap another unit's; combine units that overlap.
  Never put two workers in one worktree. Main closes the unit's panes and
  removes its worktree in the merge turn.
- When a `gh` read fails mid-task, print `BLOCKED: GitHub read failed:
  <command>: <first error line>` on a line of its own and stop. Never go on
  from a brief's copy of an issue: main reads that line and decides.
- If the task list, the worktree list or the process list shows a worktree, a
  commit or a process main did not start, stop and reconcile before acting.
- No duplicate agent of any role: reuse a live pane with the same launch title,
  never send a new job into a busy pane, and never stop a driver and relaunch
  it without reading its log tail first.

## Tests and planning

- A test verifies intent and fails on a regression. Write it red first: see it
  fail for the reason you expect, then make it pass.
- **Before any test run, name what it will prove.** Run the smallest set of
  tests that would fail if your change were wrong. Do not re-run a test whose
  inputs have not changed since it passed. Run the full suite only when product
  code changed since the last full pass, or when a push or merge guard requires
  it. A fix to tooling tests, a scanner allow-list, or a timeout re-runs only
  those tests.
- An exception, allowlist or exemption entry in a guard or its test stands
  only when the same test proves the alternative it claims, or the entry cites
  an owner ruling id. A comment is not proof.
- Name a drift guard for what it guards: it fails when two copies of one fact
  disagree, and its name says which two.
- Plan by size: a one-line fix needs no plan; a change across a few files
  gets a short list of steps; anything larger gets a written plan the owner
  approves first. Every plan takes the smallest change that does the job.
- Before building from a plan, run a freshness pass: check that every file and
  symbol it cites still exists, and re-verify a plan older than the last commit
  to those files.
- A plan names its integration surface: every consumer, registry and sync
  point the change reaches. When a contract has sibling implementations, list
  each one with a tool, not from memory, and give them one shared helper or a
  test that names both sides.
- Write the review questions before the code: the brief's "How this will be
  reviewed" lists what the reviewer will check, and the builder answers each in
  the evidence file before reporting.
- Write the evidence file as the work goes: a section per item, added when that
  item's check passes. It is the resume point after a crash and the proof for
  the reviewer.
- A plan step that adds an abstraction, a config surface, a dependency or a
  file names the simplest alternative it considered and why that loses. A step
  that adds flexibility the request did not ask for is a review finding.
- Acceptance criteria that change behaviour name the test file and the exact
  cases. The failing test comes first.
- "Create a PR" is a request to open a pull request for work already done.
  It is never an order to build something new.

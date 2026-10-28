# Working, review, agent and test rules

## Working and review

- Ask before building backward compatibility, and say how many old records
  need it. Often the count is zero and a one-time migration is cheaper.
- No AI co-author trailer and no "Generated with" line in a commit message.
- No new feature flag without the owner's OK.
- Talk to the owner in plain English: the result first, no jargon they did
  not use.
- No short 'I will now...' line before a tool call.
- Severity: P0 is data loss, a security hole or a broken main path; P1 is
  wrong behaviour a user will hit; P2 is wrong behaviour on an edge or a
  misleading message; P3 is polish. Don't inflate a finding.
- A risky change gets a three-pass adversarial review: three reviewers at
  once, each leading with another angle (correctness, security and failure,
  what breaks under real load) and covering all three. Fix everything they find together, then review
  only the fixes.
- Every reviewer gets the same full scope. Never split the areas between
  reviewers; each prompt but the closing pass's carries the complete finding
  list and checklist. The closing pass is a fresh reviewer handed no earlier
  findings, rebuttals or fix history.
  No reviewer runs a test at round close; each finding's test goes to the
  fixer. Read a reviewer's findings with `read-verdict.sh`, never a raw pane
  read.
- A finding names the file, the line and the exact failing input or command; one
  without them is not reported. A P0, P1 or P2 finding also carries a failing
  test, which the fixer runs red before the fix and ships green. When the test
  would cost more than the finding, the failing input or command stands alone
  and says why. A test that passes for the fixer does not end the finding: the
  fixer rules on it in the evidence file. A reviewer stays read-only; its fix
  diff is checked by another reviewer, never by its author.
- A reviewer reads the diff and the brief first, drafts its findings, and only
  then reads the author's evidence, which would anchor the review if read first.
- A review finding blocks the merge only when normal use would hit the bug,
  and goes back to a fix round. A finding that needs an agent deliberately
  bypassing a guard, or an odd setup, is a one-line known gap in the evidence
  file and does not block. Done is one of the pass's stop lines: a closing
  pass that ends GO (P3 findings alone are GO), or a closing NO-GO at or past
  the review cap that names an open P2 and no P0 or P1. Main files each finding still open at the
  merge as an issue first. A P0 or P1 is never left open at merge.
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
- Never write `ponytail` in a comment (`// ponytail: ...`). Explain a
  simplification in a plain comment.
  A comment that already carries the tag changes only when its lines are edited
  or in a sweep the owner asked for.
- One unit is one Orca worktree, one branch and one merge. Group issues into
  units by code area, not by issue: every issue that lands in one area is one
  unit with one brief and one review loop. Dispatch a ready brief at once
  unless its planned files overlap another unit's; combine units that overlap.
  Never put two workers in one worktree (serialize only overlaps). One unit is one
  squash merge. Main closes the unit's panes and removes its worktree in the
  merge turn, and reconciles orphaned worktrees at every plan start; briefs run
  ahead of builds. Main verifies every dispatch: status shows only scope, the
  diff stat matches each claimed change, the worktree and main heads are as
  expected, and a pass claim carries runner totals. A zero diff reported done
  is a failure. Every worker is an Orca pane
  the owner can open; Orca's task list is the dispatch ledger.
- When a `gh` read fails mid-task, print `BLOCKED: GitHub read failed:
  <command>: <first error line>` on a line of its own and stop. Never go on
  from a brief's copy of an issue: main reads that line and decides.
- If the task list, the worktree list or the process list shows a worktree, a
  commit or a process main did not start, stop and reconcile before acting.
- No duplicate agent of any role: reuse a live pane with the same launch title,
  never send a new job into a busy pane, and never stop a driver and relaunch
  it without reading its log tail first. After a crash, resume and never
  restart: `claude --continue` or `codex resume --last`, then "Orca restarted;
  continue from your last message." Interrupt a resumable pane before closing
  it; close reviewers after their verdict. Memory, not a pane count, is the
  limit (`config/pane-budget.json`).

## Tests and planning

- A test verifies intent and fails on a regression. Write it red first: see it
  fail for the reason you expect, then make it pass.
- Never edit, weaken, skip or delete an existing test to make it pass. A test
  that looks wrong is reported, not changed; tests are deleted only in a pruning
  job the owner ordered.
- **Before any test run, name what it will prove.** Run the smallest set of
  tests that would fail if your change were wrong. Do not re-run a test whose
  inputs have not changed since it passed. Run the full suite only when product
  code changed since the last full pass, or when a push or merge guard requires
  it. A fix to tooling tests, a scanner allow-list, or a timeout re-runs only
  those tests.
- An exception, allowlist or exemption entry in a guard or its test stands
  only when the same test proves the alternative it claims, or the entry cites
  an owner ruling id. A comment is not proof.
- **Planning and evidence** (drift-guard names, review questions, the evidence
  file, the halfway cut, size caps, acceptance tests, "Create a PR"): Details,
  ~/.commandeck/plugin/templates/rules-details.md, Planning and evidence.
- Plan by size: a one-line fix needs no plan; a change across a few files
  gets a short list of steps; anything larger gets a written plan the owner
  approves first.
- A plan names each file and symbol with an approximate line (`file ~line`).
  Before building from a plan, run a freshness pass: check that every file and
  symbol it cites still exists, and re-verify a plan older than the last commit
  to those files.
- A plan names its integration surface: every consumer, registry and sync
  point the change reaches. When a contract has sibling implementations, list
  each one with a symbol tool (the implementations of the contract, and
  near-duplicates from a code graph), not from memory, and give them one shared
  helper or a test that names both sides. Preview the same edit to all of them
  first (a dry run) so none is missed: a text search misses a copy that was
  renamed.
- A plan step that adds an abstraction, a config surface, a dependency or a
  file names the simplest alternative it considered and why that loses. A step
  that adds flexibility the request did not ask for is a review finding: P1
  when it adds a dependency or a config surface, P2 otherwise.

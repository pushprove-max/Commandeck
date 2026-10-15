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
  once, each from another angle (correctness, security and failure, what
  breaks under real load). Fix everything they find together, then review
  only the fixes.
- When a review leaves only medium findings, fix or file each one, then merge.
  Don't hold the change for another round.

## Agents and tokens

- Send independent tool calls together in one turn, not one after another.
- Don't pay twice for the same information: reuse what is already in context,
  and don't re-read a file you just edited.
- Keep context small: read line ranges, not whole files, and send a long
  output to a file and read the part you need.
- A code comment says only what the code cannot: the why, a limit, a hazard.
  Never what the next line does.

## Tests and planning

- A test verifies intent and fails on a regression. Write it red first: see it
  fail for the reason you expect, then make it pass.
- **Before any test run, name what it will prove.** Run the smallest set of
  tests that would fail if your change were wrong. Do not re-run a test whose
  inputs have not changed since it passed. Run the full suite only when product
  code changed since the last full pass, or when a push or merge guard requires
  it. A fix to tooling tests, a scanner allow-list, or a timeout re-runs only
  those tests.
- Name a drift guard for what it guards: it fails when two copies of one fact
  disagree, and its name says which two.
- Plan by size: a one-line fix needs no plan; a change across a few files
  gets a short list of steps; anything larger gets a written plan the owner
  approves first. Every plan takes the smallest change that does the job.
- "Create a PR" is a request to open a pull request for work already done.
  It is never an order to build something new.

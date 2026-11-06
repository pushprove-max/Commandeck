# Test rules

For anyone who writes, changes, deletes or reviews a test. The Builder brief
and every review prompt point here.

## Never weaken a test just to make it pass

- No test is deleted or merged unless a named other test catches the same
  failure.
- List every deleted or merged test with the test that replaces it, in the
  evidence file or the change's description.
- On a refusal at the new-test or tooling cap, stop and ask main.
- An edit to an existing test is the Builder's call, a loosened check included: it never stops to ask, and
  needs no named yes and no `Test edit:` line. Each edited or deleted test must still catch the bug it was
  written for.
- List each check an edit or deletion loosened under `## Loosened checks` in the evidence file, one line each:
  `- <path>: <test>: <what got looser>; still catches: <the bug>`, or one `none` line. The merge report
  lists them for the owner to read.
- A reviewer checks that each edited or deleted test still catches its bug, and rates P1 a loosened
  check that lost its purpose.
- A bug fix starts with a failing test. Run it and see it fail for the bug's reason. Then add its path to
  `.claude/bugfix-lock`, one repo-relative path per line, no glob and no `..`. While the line is there the file
  tools refuse any edit of that test: fix the code, not the test. The lock is run state and is never committed.
  When the fix is verified, run the test as written and remove the line.
- If the brief or a review finding names a change to a locked test, make only that change: delete the line, edit,
  put the line back, and show the test before and after in the evidence file. Any wider change is a question for main.
- The lock stops the file tools only, not a shell edit. A shell edit of a locked test breaks this rule the same way.

## What a test must encode

- A test encodes why the behaviour matters, not only what it does.
- A test that cannot fail when the business rule changes is wrong.
- Length, assertion counts and branch counts are screening proxies, not
  evidence of intent. Use them to pick tests to read, never to decide alone.
- A deletion needs a review that the test's intent is kept; a passing coverage
  floor alone is not enough.
- No test without an assertion, and no skip that was not approved.
- The reviewer names one code change that would make each new or changed test
  fail; a test with no such change is a finding.

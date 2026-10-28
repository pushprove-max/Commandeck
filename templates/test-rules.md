# Test rules

For anyone who writes, changes, deletes or reviews a test. The Builder brief
and every review prompt point here.

## Never weaken

- No test is deleted or merged unless a named other test catches the same
  failure.
- List every deleted or merged test with the test that replaces it, in the
  evidence file or the change's description.

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

# commandeck-ci-linux-jq-2026-10-19 -- 0.18.1: install-lib.test.sh red on the Linux CI job

Public repo: no personal names, handles, pane names (other than the existing seat directory name `Chief-of-Staff`) or
user paths in any shipped file, comment, test or changelog line. Issue numbers are written "issue N" outside
CHANGELOG.md.

## The problem

0.18.0 (f7ac166) is pushed. CI run 39228542688: the mac-bash-3 job is green, the Linux `checks` job is red on
`scripts/__tests__/install-lib.test.sh`, 60 passed and 18 failed. Every failure is a seat list that comes back as just
`["builder"]` where the test expects the full list, for example:

- "an older setup's relative link of another name to the shared file: the other project's uninstall keeps the seats
  and says which and why"
- "a later project's other value for a role (other.json) does not hide the earlier record that keeps the seat"

Read the full log with `gh run view 39228542688 --log-failed`. Likely cause: a jq construct in `il_routing_others`
(or the reduce that merges its `{role: [values]}` output) that the Linux job's jq evaluates differently from the
Mac's. Item 0 of `commandeck-plugin-2026-10-18` was the same class of bug (jq 1.7 vs 1.8).

## Prior art

jq's own manual for the versions both CI jobs install; no new library or service. A fix to existing shell and jq, not
a build-vs-buy choice.

## The build

- Find the root cause first: compare the jq version each CI job installs, and reproduce the failure locally with the
  Linux job's jq version if it differs from yours.
- Fix it with a construct both jq versions evaluate the same way. Do not change what any function returns.
- If the test suite does not already catch this on the Mac job, make it: a check that runs on both jobs and fails
  on today's code.
- Behaviour is out of scope: do not add, remove or reword any uninstall, setup or update behaviour, including the
  older-setup relative-key handling (the owner ruled to keep 0.18.0 as it is).
- CHANGELOG.md: a 0.18.1 entry, one line.

## Verify

The full test suite passes locally (report pass/fail counts), and say which jq version(s) you ran it under.

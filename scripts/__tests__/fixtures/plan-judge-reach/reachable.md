# import-retry-2026-10-29 -- a retried import makes no duplicate

Owner's words: the owner, 2026-10-29: a user who retries an import after a lost response must not get the import twice.
Goal: Close #39: the import endpoint ignores a repeated request that carries the same Idempotency-Key header.
Plan: .claude/plans/import-retry-2026-10-29.md
Tier: Standard; LOCAL merge only.
- Planned size: 3 files, 60 changed lines

## Why

A retry after a lost response posts the same import again, and the server runs it twice. The fix keys each import on a header and answers a repeat from the first result.

## Steps

- modify server/import.py ~20-60 -- ignore a repeated Idempotency-Key
- modify client/import.js ~10-30 -- send one Idempotency-Key per import and reuse it on a retry
- modify server/__tests__/import_test.py -- the repeat case

## Decisions already made

- D1 #39: the endpoint stores the key with the import result for 24 h and returns the stored result for a repeat.
  Test: import_test.py -- "a repeated Idempotency-Key returns the first result and runs nothing (issue 39)"

## Cuts

- C1 #39, ~40 lines. What: D1, in the import endpoint. Produces: the stored result per key. Consumes: nothing new. Consumers: the import endpoint's callers.
  Catches: a second import from one retried request.
- C2 #39, ~20 lines. What: the dashboard's import call sends one Idempotency-Key per import and the same key on a retry. Produces: the header on every import request. Consumes: C1's endpoint. Consumers: the import endpoint.
  Catches: a retry that carries a new key.

## What can go wrong

| Case | Input or starting state | Expected result | Test |
|---|---|---|---|
| Repeat | two requests with one key | one import, the same answer twice | a repeated Idempotency-Key returns the first result and runs nothing (issue 39) |

## Accepted failure modes

- F1 A key older than 24 h is a new import: the safe direction.
  Test: none, the safe direction

## Stated limits

(every reviewer is handed these; a finding beyond one is out of scope: a follow-up issue, never a blocker)
- A key is kept 24 h: a retry after a day is a new import (measured: the store's expiry setting, 2026-10-29, 86400 s).

## Acceptance test

- import_test.py: "a repeated Idempotency-Key returns the first result and runs nothing (issue 39)"

## Claims to falsify

- The import endpoint runs a repeated request twice today.

## Done

- #39 Done: a user retries an import from the dashboard after a lost response -- no duplicate import appears

## Facts

- The plan checks live in plan-check.sh -- scripts/plan-check.sh:1-3 (observed: 2026-10-29)

## Plan change log

- 2026-10-29: first version.

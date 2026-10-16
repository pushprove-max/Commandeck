# api-batch-2026-10-16 evidence

Session 1 stopped on main's "work added" message (2026-10-16 10:16Z). Session 2 built the added
ruling (#11775: no default page size) and the rest of #12617. Nothing committed until Codex pass 1.

| Issue | Status | Proving test | Commit |
|---|---|---|---|
| #12556 | built, green | `src/middleware/__tests__/verification-rate-limit-refund.test.ts` case "one client at its limit does not block another client of the same tenant (#12556)": red before the fix (client A not refused: the old tenant-wide key ignored the per-client row), green after | pass 1 commit |
| #12617 | built, green (list only, main's answer C) | `src/routes/__tests__/api-v1-dispatcher-gate.test.ts` "GET /api/v1/team lists the tenant team for an API key" (red before: no route), "... refuses a query field it does not document", four "<METHOD> /api/v1/team... answers 404 and never reaches the team handler"; `scripts/__tests__/sdk-node-routes.test.ts` "team.list sends GET /v1/team, and the SDK offers no team write" (red-proof RED with the old `/admin/team` URL); `packages/acme-python/tests/test_routes.py` `test_team_is_list_only` | pass 1 commit |
| #11775 | built, green, docs updated (main's added ruling) | dispatcher-gate "GET /api/v1/rooms?limit=1 with two rooms ..." (red before), "GET /api/v1/rooms with no limit still returns every room and reports the real count" (red-proof RED against a default of 50), four "limit=<bad> answers 400" (red before) | pass 1 commit |
| #12658 | partly built: retry change needs the owner's numbers (no code changed) | none: cause confirmed from DEV logs, below | n/a |

## What was built

- #12556 `src/middleware/rate-limiter.ts` checkApiRateLimit (pass 1 shape; fix round 1 below keeps
  the workspace bucket for signed-in callers): anonymous counter key is
  `<tenantId>#api_rate#<client>` / `<tenantId>#api_read_rate#<client>`, client = `ctx.sourceIp` (the
  edge-verified viewer address from getClientIp, set on ctx by resolveTenant), or `unverified` when
  getClientIp returned ''. Limit values (PLAN_RATE_LIMITS / PLAN_READ_RATE_LIMITS) unchanged;
  fail-closed 503 and the tenant-live fence unchanged. No per-tenant ceiling kept: the issue names none.
  The tenant id stays in the key because the purge finds counter rows with `contains(pk, tenantId)`
  (src/services/tenant-purge/data-cleanup.ts:186-193); no other code reads the key shape (Explore sweep).
  Test fixtures moved to the new shape: verification-rate-limit-refund.test.ts (apiCtx sets sourceIp),
  tenant-purge-deny-conformance.test.ts (purge still reaches the per-client rows).
- #11775 `src/routes/api-v1-routes.ts` GET /rooms, per main's added ruling: no `limit` returns every
  room (no default page size), `pagination: { limit: <number returned>, hasMore: false }`. A `limit`
  must be a whole number 1..1000, else 400 `invalid_limit`; rooms newest first by createdAt;
  `hasMore` true when more rooms exist. No cursor paging (out of scope). Docs: in-app reference
  (`web/src/pages/dashboard/api-docs-data.ts`: description, `query.limit`, 400 error, example) and
  `docs/reference/api-routes/api-v1.md`.
- #12617, main's answer [answer-1792145931-12878] C, list only. Invite via API key not built: would let
  a key change who may sign in; the owner can widen this later.
  - `src/routes/api-v1-admin-input.ts`: new `team` family. Only `GET /team` is classified (no body or
    query fields); every other `/team*` route is `not-found` (404) before any handler.
  - `src/routes/api-v1-routes.ts`: `input.family === 'team' && route === '/team' && method === 'GET'`
    delegates to the existing `handleTeamRoutes` (admin/admin-team-routes.ts) with path `/admin/team`
    and an empty body; ctx is passed unchanged (no role raise, the list needs none). Separate branch,
    not folded into groups: the docs parity guard reads only `route ===` lines, so the path test must
    sit on the branch.
  - Node SDK: `team.list` calls `/v1/team`; `team.invite` deleted. Python SDK: `list` already called
    `/team`; `invite` deleted. Neither package has a CHANGELOG, so each README carries the line
    "Team invitations are sent from the Acme Dashboard. `client.team.invite` was removed: the
    route it called never accepted API keys, so it could not work." and the invite example is gone.
  - Docs: `GET /api/v1/team` row in api-docs-data.ts (v1 section) and api-v1.md. The session-only
    `/api/admin/team*` rows are unchanged.
  - Scope: reuses the existing full/read_only key scopes (design-check ruling 1). The list response is
    projected to integration fields only (fix round 1, main's ruling 2).

## Fix round 1 (after pass 1 NO-GO)

- Pass 1 P2 (#12556, shared office address), built per main's ruling 3 (a first per-identity
  version was replaced before any pass saw it). The limiter now runs right after authentication
  (`src/routes/authenticated-api-routes.ts`) and takes `signedIn` = a session or API key the
  request PROVED. Signed-in callers draw on the workspace bucket `<tenantId>#api_rate` /
  `#api_read_rate` at the plan rate, as before the build; every other caller (login, public routes,
  a refused or expired credential) on `<tenantId>#api_rate#<address>`, `unverified` when the edge
  gave no address. A claimed but unproved credential counts as anonymous, or an outsider could send
  a made-up key and spend the workspace bucket again. Accepted (ruling 3): coworkers logging in from
  one office address share the anonymous login limit.
  - Why the order moved: whether a request is signed in is known only after `requireRole`, which
    already ran on every request right after the old call site; no new call was added.
  - Order change checked: between the old and new call sites only `requireRole` runs. It writes
    only (a) the API key's lastUsed, a conditional update of a row a purge already deleted, and
    (b) the support-session audit row, written after validateSession's fresh tenant read refuses a
    missing tenant. So the tenant-live fence still stops any post-purge residue. Cost: a flood with
    bogus credentials now does one key or session read before its refusal; the WAF per-IP cap
    still bounds it.
  - Class sweep: `checkApiRateLimit` has one caller (serena). No other pre-auth limiter is keyed on
    the tenant alone per the issue's evidence; the v1 monthly usage limiter is per key, after auth.
- Main's ruling 2 (#12617): `GET /api/v1/team` returns `userId, email, name, role, status` only
  (`src/routes/api-v1-routes.ts` projects the admin handler's list). "id" in the ruling read as
  `userId`, the key the Node SDK's `TeamMember` already uses. `TeamMember.joinedAt` removed from the
  Node SDK type; in-app docs and api-v1.md updated. Dashboard team list unchanged.
- Main's ruling 1 (#11775): already built in pass 1 (no default page size; see above).
- Tests (all red before their fix): dispatcher-gate "GET /api/v1/team lists ..." asserts no
  `totpEnabled` and the exact key set; dispatcher-gate "per-request limiter: a valid key draws on
  the workspace bucket (#12556)" and "... an expired key is counted on the caller's address (#12556)";
  rate-limit-refund "anonymous traffic at its address limit leaves a signed-in user of the same
  workspace unblocked (#12556)" and "ten API keys of one workspace together still stop at the plan
  rate (#12556)" (25 signed-in writes from 10 addresses pass, the 26th is 429). Purge conformance now
  covers both counter shapes (workspace and per-address).
- Runs: red 3/5 then 4/5 failing as expected (load1 ~38); green 10/10, then 27/27 targeted cases
  after ruling 3 (load1 32.99 at 10:38:35Z); order-change neighbours (cache-control-no-store,
  impersonation-unrecognised-session, impersonation-context.guard, api-v1-config-audit,
  impersonation-view-only.refute, expired-tenant-close-account-chain.guard, sdk-node-routes,
  api-v1-documentation-parity.guard) 145/145 (load1 38.74 at 10:35:45Z), run on the order change;
  ruling 3 changed only the argument, which those files do not assert, so not rerun.

## Fix round 2 (main's merge guard red, after pass 3 GO)

- Red: `pricing-catalog.conformance` "source-census: raw plan-tier comparisons ..." failed with
  `['src/routes/api-v1-routes.ts']` (reproduced ~11:03Z). The `/v1/team` branch compared the route
  family to `'team'`, which is also a plan id, so the census read it as a plan check.
- Fix: renamed the route family `team` to `team-list` in `api-v1-admin-input.ts` (type, local type,
  assignment, with a one-line why) and the one dispatcher check in `api-v1-routes.ts`. No allowlist entry:
  the census stays honest, and the name now says what the family is (only GET /team reaches it).
- Class check: the earlier repo-wide `'team'` search (non-test `src/`) showed no other route-family
  comparison against a plan id; the other families (`config`, `*-pdf`, `groups`) are not plan ids.
  No test referred to the family value.
- Green 11:04:41Z: pricing-catalog.conformance, api-v1-dispatcher-gate, sdk-node-routes,
  api-v1-documentation-parity.guard whole, 94/94 (load1 20.85 at 11:04:58Z); backend typecheck clean.

## Red proofs

- #11775 no-limit case: RED with the default-50 line restored (red-proof.sh).
- #12617 Node SDK case: RED with the URL set back to `/admin/team` (red-proof.sh).
- #12617 the four team-write 404 cases: NOT RED when only the boundary line is removed. By design two
  layers refuse a team write: the input boundary (`not-found`) and the router's `route === '/team' &&
  method === 'GET'` path test (the existing boundary comment: the path test "can only narrow").
  Either alone keeps the 404, so a one-line break cannot red them. A two-line red was blocked by the
  shell-write guard and not worked round. These cases are regression guards for the pair, not red-first
  fix tests; the fix test for #12617 is the GET /team listing case, red before the route existed.

## Left

1. `src/routes/api-v1-routes.ts` is 511 lines (was 500 on main). The file-size hook warns only; main
   files the shrink (backend.md rule).
2. Pass 1 NO-GO (one P2, fixed in fix round 1); pass 2 (review, 52d35b80) GO. Session 3 (added
   work 063544) checked all three of main's rulings against the code: each was already built in fix
   round 1 and reviewed in pass 2; rulings acknowledged, nothing changed. Pass 3 `final` on
   52d35b80: VERDICT GO, no open findings. Closing whole run beside it: the four touched node test
   files 110/110 pass (load1 169.15 at 10:42:34Z); Python SDK unittest 4/4 OK (a first try under
   `python3 -I` failed to import the package: isolated mode drops the package dir from the path, not
   a code fault). Then main's merge guard went red on the plan-tier census; fixed in fix round 2,
   which goes to its own pass.
3. Report to main must say: #12556 built per ruling 3 (anonymous callers behind one address share
   their bucket, as accepted); the limiter now runs after authentication; #12658 needs the owner's retry numbers.

## #12658 truth pass

Cause confirmed, read-only DEV query (profile acme-dev, /aws/lambda/acme-dev-api and
/acme-dev/rest-api-access-logs, 2026-10-15 17:00-17:45Z):
- 17:24:29.324 GET /admin/sub-tenants 503 and 17:24:29.331 GET /tenant/version 503 (access log).
- Matching Lambda lines 17:24:29.505/.506, tenant b00cfcff-...: "Rate limiter fail-closed: counter write
  failed", TransactionCanceledException [TransactionConflict, TransactionConflict].
- The page load fired ~8 GETs in the same second; all share the tenant's read counter row and the
  tenant row fence in one transaction. Two exhausted the 3-attempt conflict retry
  (src/repositories/base-repository.ts:98-104) and got the fail-closed 503.
- The web client retried both 0.75 s later and got 200 (17:24:30.088, .093): a short delay, no failure.
- Not a cold start (no INIT_START near 17:24:29). #12556's per-client key does not remove it: one
  browser is one client, and the tenant-row fence is in every transaction.
- Fix needs a retry-budget change (or a fence redesign); per main's ruling 2 nothing was changed.

## Ponytail

Ponytail: item 2556: rung 6; lazier option: none, the key string is the whole change (no new helper, no new limiter)
Ponytail: item 1775: rung 6; lazier option: none, a few lines inline as /verifications does; no shared parser for one caller
Ponytail: item 2617: rung 2; lazier option: taken, delegate GET /v1/team to the existing admin team handler; SDK invites deleted, not rebuilt
Ponytail: item 2658: rung 1; lazier option: taken, no code: the fix is a retry number only the owner sets

## Test runs (judgement)

- 10:18:01Z red: dispatcher-gate rooms+team cases 0/8 pass (load1 31.98).
- 10:18:56Z green: verification-rate-limit-refund + tenant-purge-deny-conformance whole, 70/70 (load1 63.85).
- 10:24Z green: dispatcher-gate rooms+team cases 12/12 after the added ruling and the team build.
- 10:26:55Z green: dispatcher-gate, sdk-node-routes, api-v1-documentation-parity.guard whole, 47/47
  (load1 37.17); Python SDK unittest discover 4/4 OK.

- After pass 1 committed (b0715d9d): the four team-write cases passed the request body in the
  `featureOverrides` slot of the test's `dispatch` helper (a type error the typecheck hook caught).
  Fixed to pass it as the body; the 4 cases re-run green. This edit is after pass 1 and goes to pass 2.

## Main-only (deferred)

(none)

## Mechanical facts

Written by evidence-facts.sh at 2026-10-16T11:04:51Z; rerun it rather than editing this section.

| File touched against main | + | - |
|---|---|---|
| docs/reference/api-routes/api-v1.md | 2 | 1 |
| packages/acme-node/README.md | 3 | 4 |
| packages/acme-node/src/index.ts | 1 | 5 |
| packages/acme-python/README.md | 3 | 4 |
| packages/acme-python/acme/__init__.py | 0 | 6 |
| packages/acme-python/tests/test_routes.py | 7 | 0 |
| scripts/__tests__/sdk-node-routes.test.ts | 12 | 3 |
| src/middleware/__tests__/verification-rate-limit-refund.test.ts | 59 | 14 |
| src/middleware/rate-limiter.ts | 11 | 4 |
| src/routes/__tests__/api-v1-dispatcher-gate.test.ts | 118 | 0 |
| src/routes/api-v1-admin-input.ts | 7 | 2 |
| src/routes/api-v1-routes.ts | 18 | 3 |
| src/routes/authenticated-api-routes.ts | 5 | 3 |
| src/services/__tests__/tenant-purge-deny-conformance.test.ts | 7 | 6 |
| web/src/pages/dashboard/api-docs-data.ts | 6 | 2 |
| .claude/briefs/api-batch-2026-10-16-added-20261016-061621.md (new) | 20 | 0 |
| .claude/briefs/api-batch-2026-10-16-added-20261016-062531.md (new) | 28 | 0 |
| .claude/briefs/api-batch-2026-10-16-added-20261016-063544.md (new) | 39 | 0 |
| .claude/briefs/api-batch-2026-10-16-design-check.md (new) | 11 | 0 |
| .claude/briefs/api-batch-2026-10-16-evidence.md (new) | 208 | 0 |
| .claude/briefs/api-batch-2026-10-16-fix-guard.md (new) | 24 | 0 |
| .claude/briefs/api-batch-2026-10-16-fix-r1.md (new) | 67 | 0 |
| .claude/briefs/api-batch-2026-10-16-r1-codex-1.json (new) | 7 | 0 |
| .claude/briefs/api-batch-2026-10-16-r1-codex-2.json (new) | 7 | 0 |
| .claude/briefs/api-batch-2026-10-16-r1-codex-3.json (new) | 7 | 0 |
| .claude/briefs/api-batch-2026-10-16-r1-prompt-1.md (new) | 4910 | 0 |
| .claude/briefs/api-batch-2026-10-16-r1-prompt-2.md (new) | 4910 | 0 |
| .claude/briefs/api-batch-2026-10-16-r1-prompt-3.md (new) | 4910 | 0 |
| .claude/briefs/api-batch-2026-10-16-r1-reports.md (new) | 24 | 0 |
| .claude/briefs/api-batch-2026-10-16-r2-codex-1.json (new) | 7 | 0 |
| .claude/briefs/api-batch-2026-10-16-r2-prompt-1.md (new) | 4599 | 0 |
| .claude/briefs/api-batch-2026-10-16-r2-reports.md (new) | 10 | 0 |
| .claude/briefs/api-batch-2026-10-16-r3-codex-1.json (new) | 7 | 0 |
| .claude/briefs/api-batch-2026-10-16-r3-prompt-1.md (new) | 5319 | 0 |
| .claude/briefs/api-batch-2026-10-16-r3-reports.md (new) | 10 | 0 |
| .claude/briefs/api-batch-2026-10-16.md (new) | 218 | 0 |

| Test run (UTC) | Test | Result | Counts | Load1 |
|---|---|---|---|---|
| 2026-10-16T10:15:54Z | --test-name-pattern=2556 src/middleware/__tests__/verification-rate-limit-refund.test.ts | FAIL | pass 0, fail 1 | 20.86 |
| 2026-10-16T10:18:00Z | --test-name-pattern=api/v1/(rooms|team) src/routes/__tests__/api-v1-dispatcher-gate.test.ts | FAIL | pass 0, fail 8 | 31.98 |
| 2026-10-16T10:18:36Z | --test-name-pattern=api/v1/rooms src/routes/__tests__/api-v1-dispatcher-gate.test.ts | ok | pass 6, fail 0 | 58.02 |
| 2026-10-16T10:18:56Z | src/middleware/__tests__/verification-rate-limit-refund.test.ts src/services/__tests__/tenant-purge-deny-conformance.test.ts | ok | pass 70, fail 0 | 63.85 |
| 2026-10-16T10:24:06Z | --test-name-pattern=api/v1/(rooms|team) src/routes/__tests__/api-v1-dispatcher-gate.test.ts | ok | pass 12, fail 0 | 27.87 |
| 2026-10-16T10:26:54Z | src/routes/__tests__/api-v1-dispatcher-gate.test.ts scripts/__tests__/sdk-node-routes.test.ts src/config/__tests__/api-v1-documentation-parity.guard.test.ts | ok | pass 47, fail 0 | 37.17 |
| 2026-10-16T10:28:53Z | --test-name-pattern=never reaches the team handler src/routes/__tests__/api-v1-dispatcher-gate.test.ts | ok | pass 4, fail 0 | 34.05 |
| 2026-10-16T10:33:47Z | --test-name-pattern=2556|api/v1/team lists src/middleware/__tests__/verification-rate-limit-refund.test.ts src/routes/__tests__/api-v1-dispatcher-gate.test.ts | FAIL | pass 2, fail 3 | 28.57 |
| 2026-10-16T10:35:06Z | --test-name-pattern=2556|api/v1/team src/middleware/__tests__/verification-rate-limit-refund.test.ts src/routes/__tests__/api-v1-dispatcher-gate.test.ts | ok | pass 10, fail 0 | 25.54 |
| 2026-10-16T10:35:37Z | src/routes/__tests__/cache-control-no-store.test.ts src/routes/__tests__/impersonation-unrecognised-session.test.ts src/routes/__tests__/impersonation-context.guard.test.ts src/routes/__tests__/api-v1-config-audit.test.ts src/routes/__tests__/impersonation-view-only.refute.test.ts src/__tests__/expired-tenant-close-account-chain.guard.test.ts scripts/__tests__/sdk-node-routes.test.ts src/config/__tests__/api-v1-documentation-parity.guard.test.ts | ok | pass 145, fail 0 | 34.62 |
| 2026-10-16T10:37:50Z | --test-name-pattern=2556 src/middleware/__tests__/verification-rate-limit-refund.test.ts src/routes/__tests__/api-v1-dispatcher-gate.test.ts | FAIL | pass 1, fail 4 | 34.15 |
| 2026-10-16T10:38:35Z | --test-name-pattern=2556|api/v1/team|rate counters|purged tenant|over the plan limit|read bucket src/middleware/__tests__/verification-rate-limit-refund.test.ts src/routes/__tests__/api-v1-dispatcher-gate.test.ts src/services/__tests__/tenant-purge-deny-conformance.test.ts | ok | pass 27, fail 0 | 32.99 |
| 2026-10-16T10:42:34Z | src/middleware/__tests__/verification-rate-limit-refund.test.ts src/routes/__tests__/api-v1-dispatcher-gate.test.ts src/services/__tests__/tenant-purge-deny-conformance.test.ts scripts/__tests__/sdk-node-routes.test.ts | ok | pass 110, fail 0 | 169.15 |
| 2026-10-16T11:03:31Z | src/services/__tests__/pricing-catalog.conformance.test.ts | FAIL | pass 44, fail 1 | 45.40 |
| 2026-10-16T11:04:33Z | src/services/__tests__/pricing-catalog.conformance.test.ts src/routes/__tests__/api-v1-dispatcher-gate.test.ts scripts/__tests__/sdk-node-routes.test.ts src/config/__tests__/api-v1-documentation-parity.guard.test.ts | ok | pass 94, fail 0 | 27.73 |
| 2026-10-16T11:04:47Z | src/services/__tests__/pricing-catalog.conformance.test.ts src/routes/__tests__/api-v1-dispatcher-gate.test.ts scripts/__tests__/sdk-node-routes.test.ts src/config/__tests__/api-v1-documentation-parity.guard.test.ts | ok | pass 94, fail 0 | 23.46 |

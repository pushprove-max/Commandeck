# help-email-batch-2026-10-16 evidence

State (2026-10-16 ~10:53Z): every item built, #12639 and #12651 included. Pass r1 (adversarial, 4803701a) ended
NO-GO; fix round 1 fixed all of it (see "Fix round 1"). Pass r2 (review, 20d2c201) ended NO-GO with one P2 (a hung
send to a later admin loses the record of earlier admins reached, since the record is written after the whole
admin loop): fix round 2 fixed it (see "Fix round 2"); pass r3 (review, dff7800c) ended GO. Pass r4 (final, dff7800c) ended NO-GO with one P2: the catalog load (`primeCatalogForLambda`, index.ts:133)
is awaited unbounded BEFORE the flips and reaper, so a stalled settings read can use the whole 60 s. Fix round 4
fixed it (see "Fix round 4"), and ruling 3's handler test was added. Pass r5 (narrowed `review`, 4067e560) ended
NO-GO with one P2 (plan-name lookup threw on a cut-off catalog load, so no trial email): fix round 5 fixed it (see
"Fix round 5"); pass r6 (`review`) is next. r4 was a `final` with P2 only, so r5 was the one narrowed pass; a GO or
P2/P3-only r6 is DONE, a P0/P1 means fix and run `final` again. Ran beside r4: the
one whole run of every touched test file beside it: closing.log, all 10 files 209/209 pass, exit 0, load
{"load1":45.37,"swapUsedMb":8554,"at":"2026-10-16T11:03:34Z"}. Ruling 2 built as far as the code
allows and acknowledged with `--ack-rulings`: the winning trial->expired write marks the email due, the job delivers
it once. Main answered the read-time question with ruling 3 (option A: the read-time path stays write-free); its
handler test is built (see "#12639 ruling 2").

## Per issue

| Issue | Status | Test that proves it | Commit |
|---|---|---|---|
| #12639 trial ending/expired email | built: templates `trial-ending` / `trial-expired` (billing role); `sendTrialNotice` (src/services/trial-notice-email.ts) mails active admins via the app's email sender and reports who it reached; the 15-min trial-expirator sends trial-ending when 3 days or less remain and trial-expired after its conditional flip. Delivery is recorded PER ADMIN (string set `trialNoticesSent`, keys `<notice>#<end date>#<email>`); the notice closes only when no admin is owed (`trialEndingNoticeFor` stamp / `trialExpiredNoticeDue` cleared). The winning flip sets `trialExpiredNoticeDue` in the same write, so a held/failed send retries until the reap. Emails run after the flips and the reaper, and stop with 15 s of invocation left. The trial-expired email no longer links the (blocked) dashboard: it says to email the configured support address. Infra: expirator gets users / platform-settings / email-templates read, email-log / error-log write, SSM read of the two email provider keys | trial-notice-email.test.ts (7 cases incl. per-admin skip, suppressed settles, queued stays owed, no dashboard link + support address); reaper.test.ts "trialEndingNoticeDaysLeft" (4) and "trial-expirator run" (4, whole handler on an in-memory table: partial delivery, paused queue, another writer wins the flip, time budget) | 4803701a + fix round 1 |
| #12640 Business welcome over-promises | built: welcome-business lists only plan facts; audit-log days from `getEffectiveFeatures(tenant).auditLogDays` | src/services/__tests__/welcome-email.test.ts "the Business welcome promises only what the Business plan includes" (RED proof: welcome-email.ts:51 removed) | uncommitted |
| #12641 welcome never sent on signup hand-off | built (fix round 1: the send returns within 5 s so a slow provider cannot cost the customer their one-use token). Truth-pass: password login already refuses unverified email (acme-auth.ts:303); the real gap was the signup exchange hand-off, which never sent the welcome. exchange-invite-routes.ts now calls `sendWelcomeEmail` (moved to src/services/welcome-email.ts, same idempotent `welcomeEmailSent` flag) | src/routes/__tests__/signup-exchange-hop.guard.test.ts "the first sign-in through the hand-off sends the welcome email", "a refused hand-off sends no welcome email" (RED proof: exchange-invite-routes.ts:196 removed) | uncommitted |
| #12642 wrong Settings paths in welcomes | built (copy): "Settings → Team & Access", "Settings → Branding & Domain", SSO & SCIM, API → Webhooks. No test pins this copy | none (copy-only, nothing pinned) | uncommitted |
| #12643 plan named by id ("solo_trial") | built: `getPlanDisplayNameSync` in src/config/plans.ts (catalog display name, legacy name when no catalog, " (Trial)" suffix) | welcome-email.test.ts "a trial plan is named as the customer sees it, not by its id" (RED proof: welcome-email.ts:48 old expression) | uncommitted |
| #12644 help promises custom sender | built (copy): branding-domain.ts sender lines removed | none (copy-only) | uncommitted |
| #12645 help promises session policy | built (copy): admin-ops.ts session bullet/keyword/valueProp removed; truth-pass: SecuritySettingsV3 has no session control | none (copy-only) | uncommitted |
| #12646 three speed claims | built: "about a minute" in welcome, help (getting-started, verifying), marketing defaults (shared/marketing-content/pages/home.ts, product.ts incl. metaTitle) and their fallbacks (HowItWorksSection.tsx, Product.tsx) | none (copy-only, nothing pinned) | uncommitted |
| #12647 "report" instead of "verification receipt" | built (copy): help article title "Verification receipts" (id `evidence-reports` kept so links hold) and body wording | none (copy-only) | uncommitted |
| #12648 login code says fixed 10 minutes | built: login-code email passes configured `loginCodeTtlMinutes`; template uses `{expiresMinutes}`. Same class: tenant-invite OTP now derives `expiresMinutes` from `OTP_TTL_SECONDS` (public-tenant-invite-routes.ts, same value today) | src/adapters/auth/__tests__/acme-auth-login-code-lockout.test.ts "the login-code email states the CONFIGURED code lifetime" (RED before fix: lc-red.log; GREEN after) | uncommitted |
| #12649 registration-attempt notice has no link | built: notice links the marketing workspace finder (`buildMarketingUrl('login')`) | src/routes/__tests__/public-signup-gate-and-notice.guard.test.ts "the registration-attempt notice links the workspace finder" (RED before fix, GREEN after) | uncommitted |
| #12650 plan-limit emails name no workspace, no link | built: `planLimitEmailContext(tenant)` in credit-service.ts gives companyName + billing URL to all three send sites (overage, limit reached, 80% warning) | src/services/__tests__/plan-limit-notification-cooldown.test.ts "every plan-limit email names the workspace and links its billing page" x3 (RED proofs: notification-effects.ts:301, :321, credit-service.ts:416) | uncommitted |
| #12651 "confidence level" vs "trust score" | built (copy) per ruling r-19990101-000000-1-abcdef. Customer-visible "trust score" changed: analytics failure reason (admin-dashboard-routes.ts:184), parent-policy save error (admin-config-put-routes.ts:110), onboarding slider label, sub-tenant wizard "Min Confidence Level" x2, API docs analytics description, help search keyword. Left alone (not customer-facing): console, Lab, signal audit, human-review trigger labels, room-visibility labels (console only), code identifiers, API field names, comments | src/routes/__tests__/api-v1-config-audit.test.ts two cases pin the new error text (existing test that pinned the copy) | uncommitted |
| #12652 welcome step 3 wording | built (copy): "Share the invite link (or the room code and PIN) with your guest" | none (copy-only) | uncommitted |
| #12653 email links use platform host for marketing pages | built: footer Terms/Privacy, logo (email-message.ts) and waitlist signup link (waitlist-service.ts) use `buildMarketingUrl`. Probed: all four paths return 200 on www.acme.com and www.dev.acme.com | email-message-escaping.test.ts "both MIME parts name the CONFIGURED support address and link the marketing-site legal pages" (RED proof: email-message.ts:75 old host); waitlist-invite-redemption.guard.test.ts "the link opens signup on the marketing site, carrying the invite code" (RED proof: waitlist-service.ts:437 old www.acme.io link, red3.log WAITLIST exit 0) | uncommitted |
| #12654 no support contact in emails | built: "Questions? <support address>" in text and HTML footers; address = configured `support_email` setting via new `resolveSupportAddress` (sender-address.ts), default support@acme.com (same default as /public/site-config) | email-message-escaping.test.ts same case (RED proof: email-message.ts:93 removed) | uncommitted |
| #12655 enterprise welcome "contact your account manager" | built: "..., or email {supportEmail}." filled by buildEmailMessage from the configured address | email-message-escaping.test.ts "the enterprise welcome offers the configured support address beside the account manager" (RED proof: email-message.ts:31 without supportEmail) | uncommitted |
| #12656 double welcome, log in / sign in | built (copy): email-verification opens "Confirm your email to activate your {companyName} workspace"; "Sign in" across welcomes and tenant-welcome-password | existing email-message-escaping.test.ts email-verification cases still pin companyName | uncommitted |

## Test results (load beside each)

- welcome-email.test.ts + signup-exchange-hop.guard.test.ts: 29/29 pass (/tmp/acme/hemail/t1.log).
- login-code lockout file: new case RED before fix, GREEN after (lc-red.log, lc-green.log).
- public-signup-gate-and-notice: new case RED before, GREEN after (ra-red.log, ra-green.log).
- red proofs red1.log (EXCHANGE, PLANNAME, AUDITDAYS all RED, exit 0).
- plan-limit-notification-cooldown.test.ts whole: 18/18 pass (pl1.log); red2.log REACHED/WARN/OVERAGE all RED.
- email-message-escaping.test.ts whole: 23/23 pass (em1.log); red3.log SUPPORTLINE/LEGAL/ENTSUPPORT RED.
- waitlist-invite-redemption.guard.test.ts whole: 7/7 pass (wl1.log).
- Load: {"host":"Acme-Macbook","load1":26.38,"swapUsedMb":4462,"at":"2026-10-16T10:24:00Z"}; {"load1":30.33,"at":"2026-10-16T10:24:51Z"}.
- Fix round 1: reaper + trial-notice-email + welcome-email: 9 new/changed cases RED (fr1-red.log), then 28/28 pass
  (fr1-green.log). Load {"load1":24.87,"swapUsedMb":6082,"at":"2026-10-16T10:52:15Z"}. `tsc -p tsconfig.test.json`
  exit 0, no errors.
- Not yet run: email-registry-conformance.test.ts (new taxonomy ids), web tests for marketing/help copy.

## #12639 notes

- Truth-pass: no request-time write flips a trial to expired any more (src/middleware/tenant.ts only refuses
  access), so the expirator is the only place the trial-expired email can come from; its stale header comment fixed.
- Mirrors the billing reconciler / credit reconciler, which already send email from a scheduled Lambda through
  `factories`. New optional tenant field `trialEndingNoticeFor` (ring N-1: optional, old code ignores it).
- Lead time 3 days is the issue's number, a code constant (`TRIAL_ENDING_LEAD_DAYS`), not a setting.

## Fix round 1 (pass r1 findings)

- r1 #1/#5/#8 (all three reviewers) partial delivery stamped the whole tenant: fixed, per-admin record (see #12639 row).
  Test: reaper.test.ts "one admin reached and one not..." RED before (b never retried), GREEN after.
- r1 #2 email starved flips/reaper: fixed, emails last with a 15 s stop margin from `context.getRemainingTimeInMillis()`.
  Test "a slow provider never starves the status flips..." RED before, GREEN after. Limit: one hung provider call
  (Resend fetch has no timeout) still runs to the Lambda timeout, but only after flips and reaps are written; owed
  emails stay marked and retry.
- r1 #3/#6/#9 trial-expired lost on a held/failed send: fixed, `trialExpiredNoticeDue` set by the winning flip,
  delivered from the expired scan until closed or reaped. Test "a trial ended while the email queue was paused..."
  RED before, GREEN after.
- r1 #4 (P1) welcome send held the response after the one-use token was consumed: fixed in `sendWelcomeEmail`
  itself (5 s ceiling via existing `raceWithCeiling`), so ALL three callers are covered: exchange-invite hand-off and
  both verify-email routes (GET/POST, registration-routes.ts:167,:196 — same class: token consumed by
  `auth.verifyEmail` before the send). Test welcome-email.test.ts "a hung email provider cannot hold the caller..."
  RED before, GREEN after.
- r1 #7 trial-expired email linked a blocked billing page: no self-serve reactivation exists for an expired tenant
  (tenant.ts:208 + auth.ts gate; only expired->active writer is the Stripe paid-invoice reconciler). Copy now says to
  email `{supportEmail}` (configured address, filled by buildEmailMessage), matching Login.tsx's "Contact support to
  upgrade". Test: trial-notice-email.test.ts trial-expired case RED before, GREEN after.
- Class checks: other templates sent to a paused workspace with a dashboard link: none (account-suspended removed;
  dunning links Stripe's invoice page). Other awaited sends after a token is consumed: only sendWelcomeEmail callers
  (acme-auth sends at :66/:363/:554/:605 mint tokens, consume none). Other "any success closes the whole
  notice" counts: none left (sendTrialNotice was the only one).

## Fix round 2 (pass r2 finding)

- r2 P2 a hung send to a later admin lost the record of earlier admins (written after the whole loop) and starved
  the admins after it: fixed. `sendTrialNotice` now hands each admin reached to an `onSent` callback before the next
  send, and the expirator writes `ADD trialNoticesSent` for that admin right then; the closing write (stamp / clear) is
  separate and only when nobody is owed. Each send is cut off at min(10 s, invocation time left minus the 15 s stop
  margin) via the existing `raceWithCeiling`, and counts as owed. Tests: reaper.test.ts "a hung send keeps the record
  of the admins already reached and still tries the next admin" (a recorded before b returns; c reached; next run only
  b) and "a hung send never runs past the invocation budget" (16 s left: cut off at 1 s). Both RED before the fix
  (fr2-red.log: TypeError, nothing recorded; 5 s test timeout), GREEN after (fr2-green.log 27/27).
  Load {"load1":42.84,"swapUsedMb":12422,"at":"2026-10-16T11:01:15Z"}. `tsc -p tsconfig.test.json` exit 0.
- Known limit (code comment): a send cut off by the ceiling may still deliver later, so that admin can get the
  email twice. Accepted for a once-per-trial notice.
- Class check: no other Lambda calls the email sender directly (`rg sendTransactional|getEmailSender lambdas` outside
  tests: none). The only other per-item loop in the expirator (flips, reaps) already writes each item as it goes.

## Fix round 4 (pass r4 finding)

- r4 P2 the catalog load ran unbounded before the flips and the reaper: fixed. It now loads after every status write,
  only when an email is due, cut off at min(10 s, email budget left) via `raceWithCeiling`; a failed or cut-off load
  leaves the built-in plan names (`getPlanDisplayNameSync` legacy path). Test reaper.test.ts "a catalog load that never
  returns cannot hold the status flips or the reaper..." (flip and reap written before any timer moves; both admins
  still mailed). RED before (fr4-red.log: test timed out after 5000ms; load 27.06 at 11:07:18Z), GREEN after (fr4-green.log
  22/22; `tsc -p tsconfig.test.json` exit 0; load 26.47 at 11:08:33Z). With the ruling 3 case added: both red proofs
  RED (fr4-red-lost.log, fr4-red-won.log) and reaper.test.ts whole 23/23 pass (fr4-green2.log; load 41.45 at 11:10:34Z).
  reaper.test.ts is the only test file this round touched; index.ts is imported by no other test file.
- Class check: every other await before the lifecycle writes is a DynamoDB scan/update (SDK-bounded). The email path's
  own awaits (admin lookup, `onSent` record) run after the flips and reaps, so a stall there costs only emails, which
  stay owed and retry. No other scheduled Lambda in this build awaits the catalog before its own writes (the other
  `primeCatalogForLambda` callers are untouched by this build; not reviewed here).
- Report to main must say: open findings are whatever r5 prints.

## Fix round 5 (pass r5 finding)

- r5 P2 a cut-off catalog load left the catalog `unloaded`, and `getPlanDisplayNameSync` threw on it (and on `error`),
  so no trial email went out; fix round 4's claim that it "leaves the built-in plan names" was wrong, and its test
  masked it by mocking `absent`. Fixed at the shared root: `getPlanDisplayNameSync` (src/config/plans.ts) uses the
  published name only when the catalog is present, else the built-in name (a name is copy, not a limit). Tests:
  reaper.test.ts catalog-timeout case now reads the real cold state (`unloaded`); trial-notice-email.test.ts "a
  catalog that never loaded or failed to load still sends..." covers `unloaded` and `error`. Both RED before
  (fr5-red-a.log, fr5-red-b.log: CatalogUnavailableError, no email; load 13.74 at 11:13:56Z), GREEN after
  (fr5-green.log 30/30; load 11.13 at 11:14:44Z). `tsc -p tsconfig.test.json` exit 0.
- Class check: the other catalog reads on the trial email path. `getRenderedEmailTemplate`'s `tenantHasFeature`
  (templates/index.ts:275) sits in a try that falls through to the built-in template (pre-existing), so it cannot stop
  a send. `welcome-email.ts` still throws on an unloaded catalog via `getPlanLimitsSync`/`getEffectiveFeatures`, which
  is right there: those are plan facts the email states, and the API Lambda loads the catalog per request. No other
  caller of `getPlanDisplayNameSync`.

## #12639 ruling 2 (read-time expiry) -- answered by main's ruling 3 (option A)

- Ruling 3 (main, 2026-10-16): keep src/middleware/tenant.ts write-free; the expirator stays the one trial->expired
  writer and sender. Built: reaper.test.ts "ruling 3: only the write that wins trial -> expired sends..." (another
  writer wins the flip without marking the email: this run sends none; the job's flip wins: one per admin; next run:
  none). Red proofs (red-proof.sh, that case only): index.ts:213 sends on a lost flip (fr4-red-lost.log) and
  index.ts:180 drops the due mark from the winning write (fr4-red-won.log); results in "Fix round 4" test line.

- Built: every trial->expired write that wins its condition must set `trialExpiredNoticeDue`; the job sends from that
  mark exactly once per admin. Test "ruling 2: another writer ends the trial first..." (another writer wins the
  flip; the job's own flip loses and adds nothing; the mark is delivered once across two runs).
- Not built: a write on the read-time path. Ruling 2 assumes one exists. Re-checked at 10:45Z: it does not.
  src/middleware/tenant.ts:217-251 only refuses access and deliberately writes nothing (verify Lambda read-only on
  the tenants table, CMK Phase-2A isolation, cmk-iam `expectNoTenantKeyWorkerDataScope`). The expirator
  (lambdas/trial-expirator/index.ts:145-184) is the only trial->expired writer and already sends trial-expired only
  after its conditional flip wins; stripe-paid-entitlement.ts:238 expires PAID plans only.
- Sent main one `question` (~10:47Z): A) keep it so and add a handler test, or B) add a write + email to the
  read-time path (breaks that isolation). Main chose A (ruling 3, above).

## Deploy notes

- Marketing hero/headline text can be overridden in stored marketing content; if an override still says
  "Under 90 seconds", it must be edited in the console after deploy (#12646).
- `support_email` platform setting is what footers now print; check it is set as intended.
- #12639 needs the infra deploy (new grants on the trial-expirator Lambda) before trial emails can send; templates are
  code, no provider-side template publish. Its cold start grows (it now loads the app's email path); timeout 60 s kept.

## Adjacent

- A1: help getting-started.ts says "Rooms expire automatically after 15 minutes by default": a configurable value
  hardcoded in help (not in this batch).
- A2: credit-service overage email still builds planName by capitalising the id; `getPlanDisplayNameSync` covers it
  (same class as #12643); not changed yet.
- A3: renderSmsTemplate has no production caller (SMS 'verification-code' edited for consistency only).

## Ponytail

Ponytail: item 2639: rung 2; lazier option: taken, reused the expirator's schedule, the app's email sender and existing templates registry; no new Lambda or scheduler
Ponytail: item 2640: rung 2; lazier option: taken, reused getEffectiveFeatures and the existing template
Ponytail: item 2641: rung 2; lazier option: taken, moved the existing welcome sender and called it from the hand-off
Ponytail: item 2642: rung 5; lazier option: taken, copy edits only
Ponytail: item 2643: rung 2; lazier option: taken, one helper over the existing catalog/PLANS lookup
Ponytail: item 2644: rung 1; lazier option: taken, deleted the false lines
Ponytail: item 2645: rung 1; lazier option: taken, deleted the false lines
Ponytail: item 2646: rung 5; lazier option: taken, copy edits only
Ponytail: item 2647: rung 5; lazier option: taken, copy only, article id kept
Ponytail: item 2648: rung 2; lazier option: taken, passed the configured TTL already in scope
Ponytail: item 2649: rung 2; lazier option: taken, existing buildMarketingUrl
Ponytail: item 2650: rung 2; lazier option: taken, one helper over tenantDisplayName + buildTenantUrl
Ponytail: item 2651: rung 5; lazier option: taken, copy edits only, no identifiers renamed
Ponytail: item 2652: rung 5; lazier option: taken, copy only
Ponytail: item 2653: rung 2; lazier option: taken, existing buildMarketingUrl
Ponytail: item 2654: rung 2; lazier option: taken, mirrors resolveSenderAddress for the existing support_email setting
Ponytail: item 2655: rung 2; lazier option: taken, same resolved address injected as a variable
Ponytail: item 2656: rung 5; lazier option: taken, copy only

## Main-only (deferred)

(none)

## Mechanical facts

Written by evidence-facts.sh at 2026-10-16T11:15:43Z; rerun it rather than editing this section.

| File touched against main | + | - |
|---|---|---|
| infra/lib/stacks/lambda-functions.ts | 16 | 0 |
| lambdas/trial-expirator/__tests__/reaper.test.ts | 259 | 2 |
| lambdas/trial-expirator/index.ts | 114 | 8 |
| shared/marketing-content/pages/home.ts | 1 | 1 |
| shared/marketing-content/pages/product.ts | 2 | 2 |
| shared/taxonomy/email-templates.ts | 2 | 0 |
| src/adapters/auth/__tests__/acme-auth-login-code-lockout.test.ts | 15 | 1 |
| src/adapters/auth/acme-auth.ts | 3 | 2 |
| src/adapters/email/__tests__/email-message-escaping.test.ts | 34 | 0 |
| src/adapters/email/email-message.ts | 18 | 9 |
| src/adapters/email/sender-address.ts | 15 | 0 |
| src/config/plans.ts | 11 | 0 |
| src/routes/__tests__/api-v1-config-audit.test.ts | 2 | 2 |
| src/routes/__tests__/public-signup-gate-and-notice.guard.test.ts | 21 | 0 |
| src/routes/__tests__/signup-exchange-hop.guard.test.ts | 21 | 0 |
| src/routes/admin/admin-config-put-routes.ts | 1 | 1 |
| src/routes/admin/admin-dashboard-routes.ts | 1 | 1 |
| src/routes/auth/exchange-invite-routes.ts | 5 | 0 |
| src/routes/auth/registration-routes.ts | 3 | 60 |
| src/routes/public-tenant-invite-routes.ts | 1 | 1 |
| src/services/__tests__/plan-limit-notification-cooldown.test.ts | 42 | 2 |
| src/services/__tests__/trial-notice-email.test.ts | 104 | 0 |
| src/services/__tests__/waitlist-invite-redemption.guard.test.ts | 21 | 1 |
| src/services/__tests__/welcome-email.test.ts | 96 | 0 |
| src/services/credit-service.ts | 13 | 1 |
| src/services/trial-notice-email.ts | 64 | 0 |
| src/services/verification/notification-effects.ts | 4 | 3 |
| src/services/waitlist-service.ts | 2 | 3 |
| src/services/welcome-email.ts | 76 | 0 |
| src/templates/index.ts | 20 | 11 |
| web/src/pages/dashboard/api-docs-data.ts | 1 | 1 |
| web/src/pages/dashboard/help/content/admin-ops.ts | 5 | 6 |
| web/src/pages/dashboard/help/content/branding-domain.ts | 2 | 3 |
| web/src/pages/dashboard/help/content/getting-started.ts | 2 | 2 |
| web/src/pages/dashboard/help/content/verifying.ts | 6 | 6 |
| web/src/pages/dashboard/managed-tenants/ManagedTenantModals.tsx | 2 | 2 |
| web/src/pages/marketing/Product.tsx | 1 | 1 |
| web/src/pages/marketing/_home/HowItWorksSection.tsx | 1 | 1 |
| web/src/pages/onboarding/Onboarding.tsx | 1 | 1 |
| .claude/briefs/help-email-batch-2026-10-16-added-20261016-060624.md (new) | 19 | 0 |
| .claude/briefs/help-email-batch-2026-10-16-added-20261016-063542.md (new) | 28 | 0 |
| .claude/briefs/help-email-batch-2026-10-16-evidence.md (new) | 282 | 0 |
| .claude/briefs/help-email-batch-2026-10-16-fix-r1.md (new) | 79 | 0 |
| .claude/briefs/help-email-batch-2026-10-16-fix-r2.md (new) | 59 | 0 |
| .claude/briefs/help-email-batch-2026-10-16-fix-r4.md (new) | 59 | 0 |
| .claude/briefs/help-email-batch-2026-10-16-fix-r5.md (new) | 66 | 0 |
| .claude/briefs/help-email-batch-2026-10-16-r1-codex-1.json (new) | 7 | 0 |
| .claude/briefs/help-email-batch-2026-10-16-r1-codex-2.json (new) | 7 | 0 |
| .claude/briefs/help-email-batch-2026-10-16-r1-codex-3.json (new) | 7 | 0 |
| .claude/briefs/help-email-batch-2026-10-16-r1-prompt-1.md (new) | 1625 | 0 |
| .claude/briefs/help-email-batch-2026-10-16-r1-prompt-2.md (new) | 1625 | 0 |
| .claude/briefs/help-email-batch-2026-10-16-r1-prompt-3.md (new) | 1625 | 0 |
| .claude/briefs/help-email-batch-2026-10-16-r1-reports.md (new) | 30 | 0 |
| .claude/briefs/help-email-batch-2026-10-16-r2-codex-1.json (new) | 7 | 0 |
| .claude/briefs/help-email-batch-2026-10-16-r2-prompt-1.md (new) | 1403 | 0 |
| .claude/briefs/help-email-batch-2026-10-16-r2-reports.md (new) | 10 | 0 |
| .claude/briefs/help-email-batch-2026-10-16-r3-codex-1.json (new) | 7 | 0 |
| .claude/briefs/help-email-batch-2026-10-16-r3-prompt-1.md (new) | 926 | 0 |
| .claude/briefs/help-email-batch-2026-10-16-r3-reports.md (new) | 10 | 0 |
| .claude/briefs/help-email-batch-2026-10-16-r4-codex-1.json (new) | 7 | 0 |
| .claude/briefs/help-email-batch-2026-10-16-r4-prompt-1.md (new) | 2002 | 0 |
| .claude/briefs/help-email-batch-2026-10-16-r4-reports.md (new) | 10 | 0 |
| .claude/briefs/help-email-batch-2026-10-16-r5-codex-1.json (new) | 7 | 0 |
| .claude/briefs/help-email-batch-2026-10-16-r5-prompt-1.md (new) | 763 | 0 |
| .claude/briefs/help-email-batch-2026-10-16-r5-reports.md (new) | 10 | 0 |
| .claude/briefs/help-email-batch-2026-10-16.md (new) | 214 | 0 |

| Test run (UTC) | Test | Result | Counts | Load1 |
|---|---|---|---|---|
| 2026-10-16T10:13:22Z | src/services/__tests__/welcome-email.test.ts src/routes/__tests__/signup-exchange-hop.guard.test.ts | ok | pass 29, fail 0 | 16.32 |
| 2026-10-16T10:19:21Z | src/services/__tests__/plan-limit-notification-cooldown.test.ts | ok | pass 18, fail 0 | 59.36 |
| 2026-10-16T10:21:48Z | src/adapters/email/__tests__/email-message-escaping.test.ts | ok | pass 23, fail 0 | 34.26 |
| 2026-10-16T10:22:41Z | src/services/__tests__/waitlist-invite-redemption.guard.test.ts | ok | pass 7, fail 0 | 29.79 |
| 2026-10-16T10:38:23Z | src/services/__tests__/trial-notice-email.test.ts lambdas/trial-expirator/__tests__/reaper.test.ts src/routes/__tests__/api-v1-config-audit.test.ts | FAIL | pass 73, fail 6 | 29.76 |
| 2026-10-16T10:38:35Z | src/templates/__tests__/email-registry-conformance.test.ts | ok | pass 13, fail 0 | 32.99 |
| 2026-10-16T10:39:08Z | src/services/__tests__/trial-notice-email.test.ts src/routes/__tests__/api-v1-config-audit.test.ts | ok | pass 64, fail 0 | 32.14 |
| 2026-10-16T10:48:59Z | lambdas/trial-expirator/__tests__/reaper.test.ts src/services/__tests__/trial-notice-email.test.ts src/services/__tests__/welcome-email.test.ts | FAIL | pass 18, fail 9 | 16.00 |
| 2026-10-16T10:50:31Z | lambdas/trial-expirator/__tests__/reaper.test.ts src/services/__tests__/trial-notice-email.test.ts src/services/__tests__/welcome-email.test.ts | ok | pass 28, fail 0 | 21.23 |
| 2026-10-16T10:58:30Z | lambdas/trial-expirator/__tests__/reaper.test.ts -- --test-name-pattern=hung send | FAIL | pass 19, fail 1 | 14.78 |
| 2026-10-16T11:00:23Z | lambdas/trial-expirator/__tests__/reaper.test.ts src/services/__tests__/trial-notice-email.test.ts | ok | pass 27, fail 0 | 49.82 |
| 2026-10-16T11:03:33Z | lambdas/trial-expirator/__tests__/reaper.test.ts src/adapters/auth/__tests__/acme-auth-login-code-lockout.test.ts src/adapters/email/__tests__/email-message-escaping.test.ts src/routes/__tests__/api-v1-config-audit.test.ts src/routes/__tests__/public-signup-gate-and-notice.guard.test.ts src/routes/__tests__/signup-exchange-hop.guard.test.ts src/services/__tests__/plan-limit-notification-cooldown.test.ts src/services/__tests__/trial-notice-email.test.ts src/services/__tests__/waitlist-invite-redemption.guard.test.ts src/services/__tests__/welcome-email.test.ts | ok | pass 209, fail 0 | 45.37 |
| 2026-10-16T11:07:18Z | lambdas/trial-expirator/__tests__/reaper.test.ts -- --test-name-pattern=catalog load | FAIL | pass 21, fail 0 | 23.58 |
| 2026-10-16T11:08:18Z | lambdas/trial-expirator/__tests__/reaper.test.ts | ok | pass 22, fail 0 | 30.33 |
| 2026-10-16T11:10:34Z | lambdas/trial-expirator/__tests__/reaper.test.ts | ok | pass 23, fail 0 | 41.45 |
| 2026-10-16T11:13:52Z | src/services/__tests__/trial-notice-email.test.ts -- --test-name-pattern=never loaded | FAIL | pass 6, fail 1 | 13.11 |
| 2026-10-16T11:13:56Z | lambdas/trial-expirator/__tests__/reaper.test.ts -- --test-name-pattern=catalog load | FAIL | pass 22, fail 1 | 13.74 |
| 2026-10-16T11:14:44Z | src/services/__tests__/trial-notice-email.test.ts lambdas/trial-expirator/__tests__/reaper.test.ts | ok | pass 30, fail 0 | 11.13 |

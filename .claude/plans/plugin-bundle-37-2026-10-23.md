# Plan: plugin-bundle-37-2026-10-23 -- every open plugin issue in one unit

Tier: Standard. LOCAL merge only. One unit, one Builder, one review loop. Base: main 14f1b73 (0.39.2).

Launch: new unit plugin-bundle-37-2026-10-23

Public repo: no personal names, seat nicknames, host product name, ruling ids or user paths in any shipped file,
test, commit message or changelog line (`ci/leak-words.txt`). Outside CHANGELOG.md an issue is written "issue N";
a host issue is "host issue N". A ported change is named by its host commit and function names.

Changed-file tests only, plus the test files of every script edited. No red proofs (no `red-proof.sh`, no
`Mutation-verified:` line). No new dependency, no new feature flag, no test-timeout raise. Every test runs through
the real script: `bash scripts/run-shell-tests.sh <file>`; `.mjs` files with `node --test <file>`.

This plan closes nothing. Main asks the owner every question under "Questions for the owner" once, before the build
starts; an answer of "build it" adds the named fallback to the group it names.

## Main answers

- The plan closes nothing; each issue is build, shipped (judge confirmed) or owner-question.
- The nine judge-confirmed shipped issues are one "propose close: shipped" block for the owner, each with its test.
- Partly shipped issues build the missing part with a test that fails today, except where a later contract stands.
- 285, 287, 266, 255 and 306 R9 go to the owner with the judge's corrected facts, the drop and the build-as-written.
- 290 (the caps) and 286 (the hand-off sentence) are built.
- The six blocking findings are fixed in the plan: relay block, `Read` registration, follow-up rate, cutover, home, script path.
- The two known gaps (309 aliases, checkpoint baseline history) are recorded as known gaps.
- 292 rows that already work are green pins; the `.projects` change gets collector, server and view coverage.
- 306 tests a train; 255 adds the positive case; 263 keeps the issue's 8-character minimum.
- 283/300: post-restart context is the resumed session's first transcript usage; restarts come from completed restart records.
- 271: pass start and end from `session_proof` go into the round file; tested on real adversarial, final, merge reports.
- Q4 build answer: bookkeeping rows keep the ring's fields and stay out of the metrics; Grep, Write, Read tested.
- Q3 R9 build answer: its test also asserts no plan commit on main and that the Builder still receives the plan.
- 300 vs the pin at `hooks/__tests__/context-clear-stop.test.sh:186`: 300's reader must read the `carried automatically` line, so delete that grep check; its intent (a healed carry never alerts) stays covered by the relay-watcher check below it and 300's `cos-watch-alerts.test.sh` case.
- Q3 287: scope stays main's judgement; the plugin has no ruling-existence gate.
- 293: the precedence change goes in the shared resolver `pp_route_json`, so the Builder launch preflight gets it.
- Q5: the portable waived entries get a build-answer fallback; the second-machine exclusion stays.
- 283/300 checkpoint share: the stop hook logs the checkpoint size after automatic carry, before the restart starts; tested 4096 -> 8192 through the report.
- Q5 fallback: deploy-feed statuses map as the host does (`failed` and `timed_out` both alert); the `timed_out` case is tested.

## The finding that sizes this unit

9 issues are wholly shipped (the judge confirmed each against its test): these go to the owner as "propose close:
shipped", with no code. 12 are partly shipped: 7 build their missing part here (305, 300, 293, 283, 272, 271,
249), and 5 meet a later contract that the owner must weigh first (307, 254, 253, 324, 268). 4 issues ask what the
host has since retired or narrowed (285, 287, 266, and 306's R9) and 255 has a narrowed part: all five go to the
owner. Issue 292 (dashboard parity) is still about 55 percent of the unit's lines.

## Decisions (ponytail ladder; one line per cut)

- 9 shipped issues: rung 1 (does it need to exist?): no code, a close proposal with the covering test. Rejected:
  re-proving each.
- Issues 269 and 263: rung 2 (already in this codebase): built from items 14 and 15 of
  `.claude/plans/dashboard-parity-2026-10-21.md:455-509`, already planned and judged. Rejected: a fresh design.
- Issue 309: rung 2: paths.sh gets one physical spelling of main; `decoy()` and `cos-check.sh` match either spelling.
  Rejected: rewriting the ruling log's `cwd` field (its readers compare the logical spelling).
- Issue 310: rung 5: a few lines at the top of `merge-unit-local.sh`. Rejected: a `--repo` option nobody asked for.
- Issue 308: rung 3 (platform): `cd && pwd -P` and two signal traps. Rejected: a temp-dir helper.
- Issue 319 and 290: rung 2: port host commits 893fad9d and 655041d5. Rejected: a shared relay library.
- Issue 305: rung 2: the relay's inbox watcher reuses the owner-bound test and the decision id of
  `orca-wait.sh:348`. Rejected: a new relay feed.
- Issue 293: rung 2: one more source in the shared resolver `pp_route_json`. Rejected: a second settings file.
- Issue 255: rung 5: one precondition inside `dashboard.sh --install`. Rejected: a per-step precondition language.
- Issue 306: rung 1: items the plugin never had are not applicable; only the train's dry-run pre-pass is cut.
- Issue 298: rung 2: port host commit 413dab38's hook and report, with the report's numerator fixed. Rejected: a
  dashboard card for it (not asked).
- Issues 283 and 300 measurement: rung 2: the `clear-hook.log` reader that `dashboard_limit.py seats` already has
  (`dashboard.sh:897`) gains a `restarts` report. Rejected: a new measurement script.
- Issue 249: measurement only, in the evidence file. Rejected: more speed work.
- Issue 292: rung 2 per row: the host's code, not a redesign. Rows the plugin cannot have (host deploys, AWS, the
  second machine, the host's standup service) go to the owner for a waiver and are not built.

## 1. All 37 issues

Verdicts: **build** (code and a test that fails on 14f1b73), **shipped** (judge confirmed; no code; under
"Questions for the owner" as "propose close: shipped"), **owner-question** (nothing built until the owner answers;
the question names what gets built on a "build it"). A row with two verdicts builds one part and asks about the rest.

| Issue | Verdict | Files touched (~line) | Ports from | Test |
|---|---|---|---|---|
| 324 | owner-question | -- | -- | Q2 |
| 319 | build | `scripts/cos-watch-inbox.sh:140`, `hooks/cos-own-echo.sh:54`, `scripts/cos-check.sh:46-50`, `hooks/agent-startup-context.sh:~146` (relay block) | 893fad9d | `cos-own-echo.test.sh` "a send from the relay's own name in another case is its own echo"; `cos-tell.test.sh` "sends with --from Relay and --from relay both do not wake the relay" (fixture name `relay` as chiefOfStaff.name); `cos-check.test.sh` "nothing wrong: prints the end-silently line only"; `agent-startup-context.test.sh` "the relay block tells a wake with nothing for the owner to end with no text" |
| 310 | build | `scripts/merge-unit-local.sh:~28` (before line 37), `:37`, `:52`, `:60`, `:72` | plugin-native | `merge-unit-local.test.sh` "run from another repository's root, the checkout's own script merges its unit"; "run by a relative path from the checkout's parent folder, the unit merges" |
| 309 | build | `scripts/paths.sh` (beside `PP_MAIN`), `scripts/decision.sh:114-117`, `scripts/cos-check.sh:41-43` | plugin-native | `decision.test.sh` "a decoy retry logged under the symlinked spelling of main is found"; `cos-check.test.sh` "owner quiet reads a ruling logged under /private/tmp spelling" |
| 308 | build | `scripts/hook-probe.sh:17-18` | plugin-native | `hook-probe.test.sh` "a relative TMPDIR still gives the hook an absolute HOME"; "TERM during a probe removes the scratch folder" |
| 307 | owner-question | -- | -- | Q2 |
| 306 | build (train dry run) + owner-question (R9) | `scripts/merge-queue.sh:76`, `scripts/__tests__/merge-queue-train.test.sh:35` | 45e1552d, e221a8bb | `merge-queue-train.test.sh` "a train `--train ua@<sha> ub@<sha>` runs no --dry-run pass" (counts `--dry-run` calls through a recording wrapper); ":35 updated: a unit the real merge's step 1 refuses leaves the train, named, nothing of it merged" |
| 305 | build | `scripts/cos-watch-inbox.sh` (the poll at :96), `scripts/orca-wait.sh:348` (the owner-bound test moves to one function both call) | host twin of issue 305 | `cos-tell.test.sh` "a Builder's owner-bound question to main reaches the decision queue with main not draining"; `orca-wait.test.sh` "main's later drain of the same question adds no second decision" |
| 300 | build | `scripts/dashboard_limit.py` (the `clear-hook.log` reader), `scripts/dashboard_alerts.jq` | 8cf83986 | `cos-watch-alerts.test.sh` "a carry-over failure the hook carried automatically does not wake the relay; one it could not carry does" (data.js built from a fixture log) |
| 298 | build | new `hooks/search-log.sh`, new `scripts/search-log-report.py`, `hooks/hooks.json` PostToolUse (:68 `Read`, :71 `Bash`, a new search matcher), `docs/hooks.md` | 413dab38 | new `hooks/__tests__/search-log.test.sh`: one row per tool type, "a Grep then a Read of its matched file, each run through the commands hooks.json registers for that tool, flags the Read as a follow-up", "one Grep followed by two Reads reports followup=100%", rotation, the report on a fixture |
| 293 | build | `scripts/paths.sh:1081` (`pp_route_json`, which `pp_route` and `builder-launch.sh:181` call), `scripts/doctor.sh` (source line), `docs/configuration.md:25` | -- | `seat.test.sh` "a project builder.effort=medium with no /plugin answer launches --effort medium"; "a /plugin builderEffort=high beats the project's medium"; `builder-launch.test.sh` "with a project builder.effort=medium and no /plugin answer, the preflight's default effort is medium"; `doctor-options.test.sh` "doctor names the project file as the effort's source" |
| 292 | build (largest) | see G5 | host `.claude/scripts/dashboard.sh`, `dashboard_server.py`, `.claude/dashboard/app.js` | per row, G5 |
| 290 | build (caps) | `scripts/cos-watch-inbox.sh:175` (body cap), `:~98` (held FYI), `scripts/cos-watch-decisions.sh:19`, `scripts/cos-watch-alerts.sh` print | 655041d5 | `cos-tell.test.sh` "the wake file for an inbox body over 1,200 characters holds it capped with a pointer", "a decision row over 1,500 is capped in its wake file", "an alert row over 1,500 is capped in its wake file"; green pin `agent-startup-context.test.sh` "the relay block keeps the subagent, rulings-search and one-question rules" |
| 287 | owner-question | -- | -- | Q3 |
| 286 | build | the fix hand-off in `scripts/builder-codex-pass.sh` (the `printf` block at ~1202) | -- | `builder-codex-pass-fresh-round.test.sh` "the fix hand-off asks for the existing cases rerun with a trusted state swapped in, and the result recorded in the evidence file" |
| 285 | owner-question | -- | -- | Q3 |
| 284 | shipped | -- | -- | Q1 |
| 283 | build | `scripts/dashboard_limit.py` (`restarts` report); `hooks/context-clear-stop.sh` ~88 (size after carry) | -- | `dashboard-limit.test.sh` (or the file that tests `dashboard_limit.py seats`) "restarts on a fixture log: restarts per day, median checkpoint bytes, post-restart context and checkpoint share as worked by hand"; "line 200000, a session resumed at 40000 and later at 205000: post-restart context is 40000"; "two restart records whose stop lines share since_restart_min=13 count as two restarts"; `context-clear-stop.test.sh` (the second-stop carry case at :177-183) "a 4096-byte checkpoint carried to 8192 bytes, then a restart whose first usage is 40000: the log's last size for it is 8192 and the report shows the 8192 share" |
| 282 | shipped | -- | -- | Q1 |
| 281 | shipped | -- | -- | Q1 |
| 279 | build (doc only) | new `docs/auto-permission-mode.md`, one link in `docs/security.md` | -- | none (no code); the leak test reads it |
| 275 | shipped | -- | -- | Q1 |
| 272 | build | `scripts/unit-ledger.sh:40` (`--escaped`), `dashboard/app.js:375`, `scripts/dashboard.sh:~600` (escapes projection) | -- | `unit-ledger.test.sh` "an escape records its finding class and where it was caught"; `dashboard-view.test.mjs:983` updated: "an escape row shows unit, issue, class and where caught" |
| 271 | build | `scripts/builder-codex-pass.sh:1166` (round file timing line), `scripts/merge-unit-local.sh:505`, `scripts/unit-ledger.sh` (row fields), `scripts/dashboard.sh:596`, `dashboard/app.js` (Review loop panel) | -- | `builder-codex-pass-fresh-round.test.sh` "the round file holds the pass's start and end from session_proof"; `merge-unit-local.test.sh` "round files generated by builder-codex-pass.sh u 1 adversarial (NO-GO), a fix, u 2 final (GO), then the merge, record GO/NO-GO per pass kind and the review seconds"; `dashboard-view.test.mjs` "the review-loop panel shows GO/NO-GO per pass kind and time in review" |
| 269 | build | G4 | 26a2b168 | G4 |
| 268 | owner-question | -- | -- | Q2 |
| 267 | shipped | -- | -- | Q1 |
| 266 | owner-question | -- | -- | Q3 |
| 263 | build (security) | G3 | b257a08f, 62121446, 3f19f6a9 | G3 |
| 260 | shipped | -- | -- | Q1 |
| 259 | shipped | -- | -- | Q1 |
| 255 | build (install precondition) + owner-question (the rest) | `scripts/dashboard.sh` `--install` (~963) | -- | `merge-unit-local.test.sh` "a Post-merge dashboard.sh --install with the login on and no password refuses: exit 5, the merge stands"; "with a password stored the same step runs and the ledger records exit 0" (`merge-unit-local.sh:482`); `dashboard-serve.test.sh` "install refuses a LAN bind with no password set" |
| 254 | owner-question | -- | -- | Q2 |
| 253 | owner-question | -- | -- | Q2 |
| 252 | shipped | -- | -- | Q1 |
| 249 | build (measurement) | evidence only | -- | none: a timing number, not a pass/fail (section 2) |
| 215 | shipped | -- | -- | Q1 |

## 2. Build details for the partly shipped and narrowed issues

Checked against host main 0ea1ebf0 (2026-10-23).

- **305.** Shipped: an owner-bound question enters the decision ledger when main's `orca-wait.sh` drains it
  (`:348`). Missing: a question that waits while main is busy and does not drain. Build: the relay's inbox poll
  (`cos-watch-inbox.sh:96`, which already reads Orca's inbox) runs the same owner-bound test on a worker's question
  or escalation to main and records it with `decision.sh add <unit>-<id> ... none "<unit> asks"`, the id main's
  drain uses, so either path records it once. `cos-watch-decisions.sh` then wakes on it. First step: the Builder
  confirms from a live pane that the relay's `orca-ide orchestration inbox --json` lists a worker's message to main;
  if it does not, the Builder stops and asks main (this build then needs another feed). The 30-minute end of `ask`:
  the Builder records in the evidence file where Orca caps `--timeout-ms` (`orca-ide orchestration ask --help`, or
  a timed probe), which `hooks/worker-ask-guard.sh:44` documents but nobody verified. Catches: an owner question
  held behind a busy main, which today reaches no relay watcher.
- **300.** Shipped: automatic carry and the size and restart log fields (`hooks/context-clear-stop.sh:39`, `:88`).
  Missing: a hard failure waking the relay. Build: the `clear-hook.log` reader in `dashboard_limit.py` yields a
  `carry-failed` event for a `carry-over check failed for <cp>` line with no later `items carried automatically
  into the checkpoint <cp>` line, and for every `could not copy` line; `dashboard_alerts.jq` makes it an alert
  `carry-failed-<time>`, resolved by the next restart; `cos-watch-alerts.sh` wakes on it as on any new alert id.
  Catches: a carry failure the hook did not heal, which today only the log shows. Item 2 (restart frequency) is
  measured with 283's report.
- **283.** Shipped: stable keys, evidence closure, dedupe, the size budget. Missing: the before/after measurement of
  post-restart context and the checkpoint's share. Build: `dashboard_limit.py restarts <log> [--since <iso>]
  [--until <iso>] [--transcripts <dir>]` prints restarts per day, median checkpoint bytes, median post-restart
  context and the checkpoint's share of it (checkpoint bytes / 4 over that context; the report says it is an
  estimate). A restart is a completed restart record: a `<session id>.resumed-from` file beside the log, which
  `hooks/resume-context.sh:55` writes when the new main takes the checkpoint (its mtime the restart time, its first
  line the checkpoint resumed from); a record whose `<session id>.jsonl` is not in the transcripts folder is another
  project's and is skipped, as the hook's `since` does (`hooks/context-clear-stop.sh:37`). Stop lines never identify
  a restart: a stop under the line returns before logging (`:30`), and equal consecutive `since_restart_min` values
  do not mark one by dropping. Post-restart context is the first assistant usage in the resumed session's
  transcript, summed as `hooks/lib/context-size.sh:30-33` sums it; checkpoint bytes are the `cp_bytes=` of the last
  stop-hook line naming that checkpoint before the restart. The stop line's `cp_bytes=` (`hooks/context-clear-stop.sh:36`)
  is measured before automatic carry appends the missing items (`:82-88`), so the hook gains one line in the carry
  success branch, after the `mv` and before the restart starts: `stop-hook: cp=<cp> cp_bytes=<size now> after carry`
  (its own line, so the `carried automatically` line and its pin at `hooks/__tests__/context-clear-stop.test.sh:186`
  stay as they are). That line is the last one naming the checkpoint, so the report takes the size main resumes
  with. The dashboard passes main's transcripts folder. Test with the judge's input: line 200000, no handoff marker,
  a session resumed at 40000 and later at 205000: the report shows 40000. Test the carry path with the judge's
  input: `stop_hook_active=true`, a fresh 4096-byte checkpoint missing inherited items, carry enlarging it to 8192
  bytes, then a completed restart whose first usage is 40000: the report shows the 8192 share (8192 / 4 / 40000,
  5.12%), not the 4096 one (2.56%). The Builder records before and after the 0.25.0 install in the evidence file. Known gap: the log before 0.25.0 has neither field (below); that baseline comes from
  retained checkpoints and transcripts, and history that is gone is reported as gone.
- **293.** Shipped: model-aware set-up, `/plugin` key at launch, doctor. Missing: the issue's precedence, `/plugin`
  key, then the project file (`.claude/commandeck.json` `builder.effort` and `builder.model`), then routing.
  `docs/configuration.md:25` documents key then routing today. Build: the shared resolver `pp_route_json`
  (`paths.sh:1081`) reads the project file when the key is unset or `project`, so every caller gets the order:
  `pp_route` (`:1135`), `seat.sh`, doctor and the Builder launch preflight (`builder-launch.sh:181`, which calls
  `pp_route_json` directly); doctor names the source of each value; the docs line states the three-level order.
- **272.** Shipped: escape rows and the panel. Missing: finding class and where caught. Build: `unit-ledger.sh
  --escaped <unit> <issue> --class <class> --caught <where>` (both required for a new row; the Builder greps every
  caller of `--escaped` and updates it); the panel shows both, and an old row without them shows a dash.
- **271.** Shipped: windowed counts and the most-rounds order. Missing: GO/NO-GO per pass kind and time in review.
  Today a round file holds `Pass: <kind>` but no start or end (`builder-codex-pass.sh:1166-1167`). Build: the pass
  keeps the `<began> <ended>` fields that `session_proof` already prints for each reviewer (`:175-179`, `:342-343`)
  and writes one `Timing: <earliest began> <latest ended>` line beside `Pass:` in the round file (`-` for a field the
  session record does not hold). The merge's ledger step (`merge-unit-local.sh:505`) records per kind (adversarial,
  review, final) from each round file's `Pass:` and `Timing:` lines; a round without them (older rounds) leaves its
  kind or time unknown, never 0, as the counts do now; `dashboard.sh:596` projects both; the Review loop panel shows
  them. The merge test uses real generated reports: `builder-codex-pass.sh u 1 adversarial` (NO-GO) → a fix →
  `builder-codex-pass.sh u 2 final` (GO) → `merge-unit-local.sh u`, with the suite's stand-in Codex writing session
  records that carry the turn's start and end, and asserts known review seconds, not unknown.
- **249.** Shipped: the polling change. Missing: the same-fixture timing. The Builder records the median of 15 runs
  of the batching hook's own test fixture at the commit before the 100 ms poll (`git log -S'100 ms' --
  hooks/batch-independent-looks.sh`) and at the tip, in the evidence file. No pass/fail test: a timing assertion
  would be flaky, and the code is already in.
- **279 a document.** Delivers `docs/auto-permission-mode.md`, one page: what Orca's Auto mode lets through and
  refuses for Claude Code and Codex (from Orca's release notes and one live probe each in a scratch pane, recorded
  in the evidence file), how it meets the plugin's PreToolUse guards (they run before any permission decision, so a
  hook refusal stands in every mode) and the seat launch flags (`scripts/paths.sh` codex sandbox words), and a
  recommendation. No setting changes. The probes are future evidence, not a result this plan claims.
- **306.** Each R item, plugin state:
  - R1, R2, R7: not applicable: the plugin has no push step, no test lanes and no pre-push record check.
  - R3: not applicable: the plugin's merge has no class check.
  - R4, R5: met: `unit-ledger.sh` runs once per merge (`merge-unit-local.sh:512`), and no separate metrics commit.
  - R6, R8, R12: not applicable: the merge builds no review page, has no keyword grep or live-drift step (its
    evidence read at `:286` is the deletion list, a real check), and writes no dead records.
  - R9: owner-question (Q3).
  - R10, R11, R13: shipped 0.25.0.
  - R14: not applicable: the brief template names no "Opus pane" (grep, 2026-10-23).
  - Merge dry runs: **cut** (the one change): a train (`merge-queue.sh --train`) runs `--dry-run` per unit at `:76`
    before its combined check; that pre-pass goes, and the real merge's step 1 runs the same checks and refuses
    with nothing merged. A plain queue already runs no dry run. The train's combined test stays.
- **290.** Shipped: `cos-check.sh` timers and all four relay rules (`hooks/agent-startup-context.sh:140-146`). Built:
  the payload caps, tested in the saved wake files (stdout over 600 bytes is already a pointer, `cos-lib.sh:21`, so
  a stdout test would pass unchanged). The three existing rules get a green pin. No template edit:
  `templates/AGENT_STARTUP.md` is not loaded for the relay (`agent-startup-context.sh:125`).
- **286.** Shipped: the template rule (`templates/_builder-brief-template.md:174`). Built: the same sentence in the
  generated fix hand-off (`builder-codex-pass.sh:1202`). Completion, no scope cut.
- **255.** Shipped: the allow-list, background steps, exit recording and exit 5 (`merge-unit-local.sh:454-482`).
  Built: the one precondition the issue's acceptance names, with its positive case. The rest is Q3.

## 3. Overlaps: one change each

- **Relay (324, 319, 305, 290).** 324 is Q2. One change, G2: the self-send filter, the caps, the owner-bound
  recording, `cos-check.sh`'s silent line, and the silent-wake line in the relay block that
  `hooks/agent-startup-context.sh` generates; each file opened once.
- **Checkpoint (252, 281, 283, 275, 267, 300).** 252, 281, 275, 267 are Q1. One change, in G5 beside the alert
  rows: the `clear-hook.log` reader gains the `carry-failed` event (300) and the `restarts` report (283, 300 item 2).
- **Merge (307, 306, 254, 255, 259, 310).** 259 is Q1; 307 and 254 are Q2. One edit to `merge-unit-local.sh` (310,
  G1), one to `merge-queue.sh` (306, G1). 255's precondition lives in `dashboard.sh --install`, in G3 beside the
  login it depends on.
- **Dashboard (292, 272, 271, 269, 263).** 263 is G3; 269, 271, 272 are G4; 292's other rows are G5.
  `dashboard_serve.py`, `dashboard.sh`, `app.js` are each touched in G3, G4 and G5 in that order; the Builder never
  edits a later group's rows early.
- **Pass (260, 266).** No code: 260 is Q1, 266 is Q3.

## 4. Build order

Each group's tests are green before the next starts. Commit per group.

- **G1 small fixes** (310, 309, 306, 286, 298, 293, 279). Low risk, unrelated files.
- **G2 relay** (319, 290, 305).
- **G3 security** (263, 308, 255). The riskiest group.
  - Threat, 263: anyone on the LAN can answer the owner's decisions and those answers count as the owner's. Test:
    `dashboard-serve.test.sh` "every route needs a login: 302 for pages, 401 for PUT layout, /answer, /unsent,
    /restart; no file changed", "lockout after five failures: exactly five 401 and fifteen 429 under 20 parallel
    wrong logins", "a 7-character password is refused", "plain HTTP gets no page", "no password or token in any
    file or log", and the plugin case "a loopback bind serves as today with no login".
  - Threat, 308: a relative or odd `TMPDIR` gives the probed hook a relative `HOME`, so a hook that changes folder
    writes into a real folder; a signal leaves the scratch folder behind. Test: the two `hook-probe.test.sh` cases.
- **G4 tests and review panels** (269, 271, 272).
- **G5 dashboard parity** (292, with 300's alert and 283's report), then the cutover check.
- **Close-out:** version and CHANGELOG, `bash ci/leak-test.sh`, then the final pass.

## 5. Changes, by group

### G1

- **310** `scripts/merge-unit-local.sh:~28`: first, before any `cd`, resolve the script itself:
  `SELF=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/${BASH_SOURCE[0]##*/}`; the sourcing at :37, the
  re-execs at :52 (`bash "${0}"`) and :60 (`flock ... "${0}"`) and `HERE` at :72 use it. Then, when that folder is in a
  git checkout that is the main worktree on branch `main` (`git -C "${SELF%/*}" rev-parse --show-toplevel`,
  `--git-common-dir` equal to `--git-dir`, branch `main`), `cd` to it before the code at :37 and :68 reads the cwd.
  Anywhere else (an installed copy) the cwd rules as today; the existing `merge-unit-local.test.sh` cases pin that.
  The relative case runs `bash Commandeck/scripts/merge-unit-local.sh <unit>` from the checkout's parent folder.
- **309** `scripts/paths.sh`: `PP_MAIN_P=$(cd "$PP_MAIN" 2>/dev/null && pwd -P)` beside `PP_MAIN`, the one defined
  root. `decision.sh` `decoy()` (:114-117) and `cos-check.sh` QUIET (:41-43) match a `cwd` under either spelling.
  `hooks/ruling-log.sh:68` keeps writing what Claude gives it.
- **306** `scripts/merge-queue.sh:76`: drop the train's `--dry-run` pre-pass; a unit the real merge refuses is
  reported as the dry-run refusal was. The test drives `merge-queue.sh --train ua@<sha> ub@<sha>` and counts
  `--dry-run` calls; `merge-queue-train.test.sh:35`'s "its dry run refused it" expectation becomes the real
  merge's refusal text.
- **286** the fix hand-off (`builder-codex-pass.sh` ~1202, beside the "same class again" block): one line, the
  template's own words at `templates/_builder-brief-template.md:174`; the test asserts the whole state-swap
  instruction, the evidence recording included.
- **298** port 413dab38's `search-log.sh` and `search-log-report.py`, with the plugin's matchers and two fixes.
  Registration in `hooks/hooks.json` PostToolUse: a new entry `Grep|mcp__serena__.*|<the code-graph server tools>`,
  and `search-log.sh` added to the existing `Read` (:68) and `Bash` (:71) entries (`Read` is the follow-up the
  flag reads; the host hook depends on it). The follow-up test runs each call through the commands `hooks.json`
  registers for that tool name (jq over the PostToolUse matchers), not the hook directly. Rate fix: a follow-up
  row records the search row it follows, and the report divides distinct followed searches by searches (the host
  counts follow-up rows, so one Grep and two Reads give 200%). The window stays the host's next 3 logged calls
  (Q4). The row holds the host's 12-hex query fingerprint, not the query text (Q4). Log under the plugin's scratch
  folder, size rotation as the host's, env name `COMMANDECK_SEARCH_LOG`. Host-only names dropped.
  Catches: per-tool empty and follow-up rates of the search tools, which no existing log records.
- **293** `pp_route_json` (`paths.sh:1081`, the resolver `pp_route` and `builder-launch.sh:181` both call): effort
  and model come from the per-launch pin, then the `/plugin` key, then the project file's role setting, then
  routing. Doctor's line names the source. `docs/configuration.md:25` says it.
- **279** the note (section 2).

### G2

- **319** port 893fad9d: `cos-watch-inbox.sh:140` drops a message when `from_handle.lower()` is the pane's handle
  or the configured `chiefOfStaff.name` (already read at :137), lowercased; `cos-own-echo.sh:54` the same test.
  `cos-check.sh`: when nothing is down, missed or held, it prints `cos-check: nothing for the owner: end silently;
  re-arm` and logs as today; otherwise the line as today. The relay block that `hooks/agent-startup-context.sh`
  prints (the heredoc at :~146, beside the other relay rules) gains one line: a wake with nothing for the owner
  (that line) ends the turn with no text after re-arming the watcher. The test reads the hook's output for a relay
  pane.
- **290** port 655041d5's caps: inbox body 1,200 characters and the held-FYI dump 1,500, each with a pointer to the
  full text; decision and alert rows 1,500. Tests read the saved wake file, not stdout.
- **305** section 2. The owner-bound test (`orca-wait.sh:348`'s grep) becomes one function in `paths.sh` that
  `orca-wait.sh` and `cos-watch-inbox.sh` both call, so the two never disagree.

### G3

- **263** item 15 of `.claude/plans/dashboard-parity-2026-10-21.md:479-509`, unchanged: port b257a08f, 62121446,
  3f19f6a9 into `scripts/dashboard_serve.py` (standard library), `dashboard.sh --install` (make-cert on a LAN
  bind), `dashboard/app.js` (401 to `/login`), `skills/setup/SKILL.md` (one set-password line),
  `docs/dashboard.md`, `docs/security.md`. Login on only for a non-loopback bind. Minimum password: 8 characters,
  as the issue requires.
- **308** `scripts/hook-probe.sh:17-18`: `S=$(cd "$S" && pwd -P)` after `mktemp -d` (refuse if empty), and
  `trap 'exit 130' INT; trap 'exit 143' TERM` beside the EXIT trap so a signal still removes the folder.
- **255** `dashboard.sh --install`: with the login on (non-loopback bind) and no password stored, refuse with the
  `set-password` command to run; with a password stored, install as today. Catches: a dashboard restarted behind a
  login no one can pass; no existing step reads the password store.

### G4

- **269** item 14 of `.claude/plans/dashboard-parity-2026-10-21.md:455-477`, unchanged: port 26a2b168, this
  machine only. Tests as listed there (`dashboard-built.test.sh`, `dashboard-view.test.mjs`).
- **271, 272** section 2.

### G5: issue 292 checklist

Ports from host `.claude/scripts/dashboard.sh`, `.claude/scripts/dashboard_server.py`, `.claude/dashboard/app.js`
at host main; the Builder names the host commit per row from `git log -S'<key>'` in the evidence file. Each row gets
a `dashboard-view.test.mjs` case for the page and a `dashboard-built*.test.sh` case for the collector key, named
after the row. The Builder runs each new case on 14f1b73 first: a case that passes there is a green pin, not a
failing test, and the row is marked met.

Already met (green pins, no code): custom page title (`dashboard/app.js:1576`); relay inbox unread and oldest age
(`scripts/dashboard.sh:883`); `alerts-since.json` in the cache (`:911`); main's seat card context, 7-day average
and restarts (`scripts/__tests__/dashboard-view.test.mjs:821`); fixed port and LAN bind, `COMMANDECK_SCRATCH` kept
(`dashboard.sh:1188`); `--import` of limit history, layouts and cleared builds; `--slurpfile`; alert ids seeded with
`cos-watch-alerts.sh --seed`; alerts resolved drawer; Tokens per unit; Review loop; Review escapes; LAN serving and
port (config values). The Builder confirms `decision.sh --options` takes a JSON array (`decision.test.sh`); if
not, it is the first G5 row.

To build:
- [ ] Page title / h1 default: the project's own name when no custom title is set.
- [ ] Project bar and per-project pages `/p/<name>/` with their own data file; `.projects` changes from an object
      to `[{slug,name}]`. Every reader moves with it: the collector's validator (`dashboard.sh:1020`, which
      requires an object today), `dashboard_serve.py`'s per-project routes, `app.js`, and any other reader the
      Builder finds with `rg '\.projects'`. Tests: `dashboard-built.test.sh` "data.js .projects is an array of
      {slug,name} and validates"; `dashboard-serve.test.sh` "/p/<slug>/ serves that project's data file";
      `dashboard-view.test.mjs` "the project bar lists each project by name and opens its page".
- [ ] Phone tab bar: 7 tabs incl. Home and Tests.
- [ ] Summary strip from the current panels.
- [ ] Alert host-load (load over cores).
- [ ] Alerts main-compact-* and checkpoint-rejected-*, resolved on restart, from `mainEvents`.
- [ ] Alert carry-failed-* (issue 300, section 2).
- [ ] Alert ids and rules as the host: `stage-<unit>` (over 2 h), `builder-<unit>-<kind>`, `cache-builder-<unit>`,
      `question-<id>` (over 1 h), `guard-spike`.
- [ ] Units board stages as the host's list.
- [ ] Unit fields: driver badge, lastMarker, worktree, seats[].
- [ ] `units.mainAsks` (stop notes on unit cards).
- [ ] `units.builderCap` (from `maxBuilders`).
- [ ] Finished builds history as the host's.
- [ ] Parked, no worktree list.
- [ ] Merged since last push card.
- [ ] Main's seat card fields: account, week, live, rebuild cost, line.
- [ ] Chief of Staff's seat card: hourly, side runs, week.
- [ ] Needs owner: P1 list (top 5 and all).
- [ ] Needs owner: proposed decisions (label `proposed-decision`).
- [ ] `decision.sh push-ask` rows on the page.
- [ ] Main card: lastCheck, lastMerge, lastStop (the chain and push-record parts: Q5).
- [ ] Open pull requests with tally.
- [ ] Issues by milestone, P1 alarm; Issues card by priority.
- [ ] Next push to origin/main: verdict and list.
- [ ] 7-day limit card: used percent, 5-hour window, history.
- [ ] Limit: cost today for the whole machine.
- [ ] `measures` extras and `mainEvents` keys.
- [ ] Collector speed: slow groups in parallel, `.part-seconds`, slow-cycle log.
- [ ] Source records: the host's generic inputs (not AWS or deploys).
- [ ] The `restarts` report (issue 283, section 2).

### Cutover (from the host's collector to the plugin's)

The host's relay decision watcher (`watch-decisions.sh:6`, `:21` in the host's relay scripts) reads the old
collector's file and its personal-name decisions key; the plugin's reads the decisions ledger (`scripts/cos-watch-decisions.sh:16`). A switch that retires the old
collector first leaves the relay deaf to new decisions. The steps, written into `docs/dashboard.md` ("Switching
from another collector"):

1. `dashboard.sh --import <old folder>` (limit history, layouts, cleared builds).
2. `dashboard.sh --register <home main checkout>`, then `--register` each other project. Home is registered
   explicitly: with a registry that exists and does not list home, home is not collected (`dashboard.sh:979`).
3. Verify: the built data.js lists home's slug in `.projects`.
4. `dashboard.sh --install`, with the old job still running.
5. The relay runs the plugin's `cos-watch-decisions.sh` and `cos-watch-alerts.sh` (its startup block), the old
   watchers still running.
6. Gate: one test decision (`decision.sh add`, waiting on the owner) wakes `cos-watch-decisions.sh`, and one alert
   in the new data.js wakes `cos-watch-alerts.sh`. Both wakes are seen, then the test decision is answered.
7. Only then are the old collector job, its data file and the old watchers retired.

Test: `dashboard-built.test.sh` "cutover: with a registry naming only another project, --register of home puts home
in .projects; a decision only in the new ledger wakes cos-watch-decisions.sh and an alert only in the new data.js
wakes cos-watch-alerts.sh, once each". The live switch on the owner's machine is main's step after the merge, steps
1-7 in order, each result in the evidence file. Catches: a switch that leaves the relay deaf to decisions or alerts.

## 6. Established practice for the security changes

- **263 login.** Password storage: OWASP Password Storage Cheat Sheet lists scrypt N=2^14, r=8, p=5 as an accepted
  setting; the port uses exactly that, with a 16-byte random salt and `hmac.compare_digest`. Sessions: OWASP Session
  Management: random tokens from `secrets`, cookies `HttpOnly; Secure; SameSite=Strict`; lockout (5 failures in 15
  minutes) follows OWASP's throttling advice. TLS: a self-signed certificate for a LAN host is normal practice. **One
  deviation:** NIST SP 800-63B-4 asks for at least 15 characters for a password used alone; the issue and host commit
  62121446 set 8. The plan keeps the issue's 8 (LAN only, plus lockout).
- **308 temp files.** `mktemp -d` (unique, mode 0700), an absolute path (`pwd -P`), and cleanup on EXIT plus INT
  and TERM, since bash does not run an EXIT trap when a signal's default action kills it. The plan follows it.

## 7. Catches

Added flow steps: the 255 install precondition, the 298 per-search log record, the 305 owner-bound recording by
the relay, the 300 carry-failed alert, and the cutover gate (lines in sections 2 and 5). Removed: the train's dry
run (306). Nothing else adds a step.

## 8. Version and CHANGELOG

0.40.0, the next free minor (no branch or plan claims it, 2026-10-23); if a sibling merges first, the next free
minor at merge time. `.claude-plugin/plugin.json:3` and every file `ci/version-check.sh` reads; one CHANGELOG
section listing the built issues. Closing issues is main's, after the owner's answers; the CHANGELOG names none as
closed.

## Known gaps (not merge blockers)

- **309:** two spellings of main, not arbitrary aliases. With `PP_MAIN=/tmp/main-link` and a ruling logged under
  `/tmp/second-link`, both links to the same checkout, neither stored spelling matches (`scripts/decision.sh:109`).
- **Checkpoint baseline history:** before 0582084 the stop hook logged neither checkpoint bytes nor restart
  intervals (`0582084^:hooks/context-clear-stop.sh:34`), so the pre-0.25 baseline for 283 and 300 comes from
  retained checkpoints and transcripts; history that is gone is reported as gone.

## Questions for the owner

Main asks these once, before the build starts. Nothing here is closed or dropped without the owner's yes.

### Q1. Propose close: shipped (judge confirmed; no code)

- 284: propose close: shipped. Planning scratch lives outside the worktree (`scripts/plan-worktree-close.sh:106`);
  test `scripts/__tests__/plan-worktree-close.test.sh:186`.
- 281: propose close: shipped. Stable identities and one unresolved Queue (`hooks/context-clear-stop.sh:80`); test
  `hooks/__tests__/context-clear-stop.test.sh:211` (three restarts with rewording).
- 275: propose close: shipped. The main-session gate (`hooks/pane-budget-gate.sh:12`); test
  `hooks/__tests__/pane-budget-gate.test.sh:96`.
- 267: propose close: shipped. 200K context line 140K, ceiling 165K (`hooks/lib/project.sh:54`); tests
  `hooks/__tests__/context-clear-stop.test.sh:310`, `hooks/__tests__/context-size.test.sh:12`.
- 260: propose close: shipped. After a final NO-GO, review runs as final (`scripts/builder-codex-pass.sh:837`); test
  `builder-codex-pass-decisions.test.sh` ("final in place of review").
- 259: propose close: shipped. One failed-job rerun, deploys excluded (`scripts/ci-watch.sh:34`); tests
  `scripts/__tests__/ci-watch.test.sh:41`, `scripts/__tests__/decision.test.sh:43`.
- 252: propose close: shipped. Dropped items block once and are restored before restart
  (`hooks/context-clear-stop.sh:61`); tests `scripts/__tests__/checkpoint-context.test.sh:12`,
  `hooks/__tests__/context-clear-stop.test.sh:265`.
- 215: propose close: shipped. ANSI/locale command words and quoted scripts; test
  `hooks/__tests__/no-poll-loops.test.sh:346`. Items 2, 4, 5 are recorded as out of scope for a lexical guard
  (`hooks/no-poll-loops.sh:24`).
- 282: propose close: shipped. The rule in `templates/_builder-brief-template.md:31` and the reviewer's
  (`scripts/builder-codex-pass.sh:121`); tests `scripts/__tests__/brief-template.test.sh:36`,
  `hooks/__tests__/edit-content-tripwires.test.sh:76`. The judge rated this likely: no test proves every guard
  exemption.

### Q2. Partly shipped; the missing part contradicts a later contract

- **307.** Contract: the owner's tree-equality ruling: a green run is reused only for the same tree, and a train's
  run tested a tree with later units in it (`scripts/merge-unit-local.sh:372`); the green three-unit train fixture
  expects three check runs (`scripts/__tests__/merge-queue-train.test.sh:16`). Proposed close: "Closing-pass reuse
  and train bisection shipped; a train's run is not reused for its units, by the tree-equality ruling." Build it:
  a unit in a green train reuses the train's run; the `ta/tb/tc` fixture expects one check run (G1).
- **254.** Contract: a qualified first-pass GO also merges (`scripts/builder-codex-pass.sh:564`,
  `scripts/__tests__/main-watch-auto-merge.test.sh:2`). Proposed close: "Automatic local merging and its refusals
  shipped; a qualified first-pass GO merges, by the later contract, not only a final GO." Build it: auto-merge
  waits for a final GO; test "a clean eligible unit whose only pass is an adversarial GO is not merged" (G1).
- **253.** Contract: issue 318 made landed merges wake main (`scripts/__tests__/main-watch-auto-merge.test.sh:4`),
  so the 12-item replay allows 11 wakes (`:45`), not at most six. Proposed close: "Digest handling and judgment
  wakes shipped; the at-most-six-wakes acceptance is superseded by issue 318." Build it: the 12-item replay wakes at
  most six times, which silences landed merges again and reverses issue 318 (G2).
- **324.** Contract: a heartbeat from the relay pane never wakes or prints, and a test pins that
  (`scripts/__tests__/orca-wait.test.sh:44`); every other relay message wakes (`scripts/paths.sh:503`). Proposed
  close: "Shipped in 0.30.0: every relay message wakes main except the relay's heartbeat, by design." Build it: a
  relay heartbeat wakes main; test `main-watch-wake.test.sh` "a heartbeat from the relay pane wakes main", and the
  pinning case is reversed (G2).
- **268.** Contract: failure names are capped at 20 plus the tail (`scripts/run-shell-tests.sh:157`). Proposed
  close: "Early-failure output shipped; failure names are capped at 20 plus the tail." Build it: every `FAIL` name
  is printed; test `run-shell-tests.test.sh` "21 FAIL lines then 30 passing lines name all 21 failures" (G1).

### Q3. Retired or narrowed by the host, with the judge's corrected facts

- **285.** Fact: the plugin retired red proofs (`scripts/__tests__/brief-template.test.sh:82`), and this unit runs
  none. Dropped: affected-case selection, unrelated-red classification, and durable long-proof output. Proposed
  close: "Red proofs are retired, so there is no red-proof run to narrow." Build as written: those three in
  `scripts/red-proof.sh`, which brings back a retired step and contradicts this unit's no-red-proofs rule.
- **287.** Fact: the host's launch checks only that the cited ruling exists and is not void
  (`host:.claude/scripts/builder-launch.sh:84`). The plugin has no stricter scope check today: `scripts/seat.sh:305`
  checks for a `Launch:` line and `scripts/builder-launch.sh:82` checks its unit name; neither reads the quoted
  order's scope. Dropped: refusing an unrelated or file-only ruling in both launch paths. Proposed close: "The host
  keeps only a ruling-existence check; in the plugin, scope stays main's judgement; the plugin has no
  ruling-existence gate." Build as
  written: `seat.sh` and `builder-launch.sh` read the cited order and refuse a file-only or "not now" answer, or one
  naming neither the unit nor an issue in its scope (the words of the relay rule at
  `hooks/agent-startup-context.sh:145`); test `builder-launch.test.sh` and `seat.test.sh` "`Launch: new unit u` with
  `Order: file issue 12 only` is refused" (G1).
- **266.** Fact: the host keeps review narrowed before a first final (`host:.claude/scripts/builder-codex-pass.sh:646`)
  and also keeps a narrowed replay-after-GO exception (`:659`); the plugin upgrades review to final after any final
  (`scripts/builder-codex-pass.sh:839`). Dropped: recognising the first intended closing review automatically.
  With adversarial NO-GO, a fix, then `builder-codex-pass.sh u 2 review` with no prior final and unchanged scope,
  the pass stays narrowed. Proposed close: "The host keeps a narrowed review before the first closing pass; after
  any closing pass the plugin's review runs as final." Build as written: that sequence runs as final; test
  `builder-codex-pass-decisions.test.sh` "review after an adversarial NO-GO and a fix, scope unchanged, runs as
  final" (G1).
- **255 (the rest).** Fact: background steps, exit recording and refusal exist (`scripts/merge-unit-local.sh:454`).
  Dropped: general per-step preconditions and a typed approval for irreversible commands; a small allow-list and the
  one install precondition stand in for them, and a Post-merge command outside the three allowed forms is refused
  (`:467`). Proposed close (after G3): "Post-merge runs an allow-list with recorded exits; the one precondition the
  acceptance names is built." Build as written: a precondition line per Post-merge step and a typed yes before an
  irreversible one, with a test per form (G3).
- **306 R9.** Fact: the plugin binds the Builder to the frozen plan by its hash (`scripts/builder-launch.sh:148`)
  and also commits that plan on main before launch (`plan_ok`, `:95`, and the commit after `:148`); the host
  still requires a committed plan (`host:.claude/scripts/builder-launch.sh:155`). Dropped: R9's removal of the
  plan-commit gate. Question: keep the gate (the host keeps one too)? Build as written: a `--from-plan` launch with
  a matching judge hash no longer needs the plan on main, and makes no plan commit there (today it commits the plan
  and launches, `scripts/builder-launch.sh:150-163`); test `builder-launch.test.sh` "`builder-launch.sh --from-plan
  u <batch>` with a matching judge hash and no plan on main opens the unit, main's `git log` gains no plan commit,
  and the Builder's worktree holds the frozen plan byte for byte" (G1).

### Q4. Issue 298: two scope differences in the port

- **Window.** The issue asks for a follow-up within the next 3 calls; the host counts the next 3 logged calls, and
  Edit, Write and other unlogged calls do not count (`host:.claude/scripts/search-log-report.py:8`). The plan ports
  the host's window. Build as written: `search-log.sh` registered on every tool (`.*`), so the window is the next 3
  calls. An unlogged tool writes a bookkeeping row that keeps the ring's fields (`{tool, kind: "other", paths: [],
  hits: [], qfp: ""}`), since the ring reads `paths`, `hits` and `qfp` of every row (`host:.claude/hooks/search-log.sh:126-128`);
  the report excludes every non-search, non-read row from its metrics (calls, size, empty, the per-tool lines),
  since it indexes `size` on each call (`host:.claude/scripts/search-log-report.py:33`). Test: Grep → Write → Read,
  each through the commands `hooks.json` registers, then the report on that log: it exits 0, prints no Write line,
  and flags the Read as the Grep's follow-up (G1).
- **Query text.** The issue's row holds the query; the host's holds a 12-hex sha1 fingerprint and no text
  (`host:.claude/hooks/search-log.sh:6`), so a secret or a name typed into a search is never stored. The plan ports
  the fingerprint. Build as written: the row stores the query, cut to 200 characters (G1).

### Q5. Issue 292: waiver (not built)

Standup link (host service), deploy-dev and deploy-prod alerts, Deploys card, AWS and deploy source records, the
chain and push-record verification, the second machine's test lanes (already declined: no second-machine support).

Build it (the portable entries, G5; each with a `dashboard-view.test.mjs` case and, for a collector key, a
`dashboard-built.test.sh` case; absent config shows nothing, as today):
- Standup link: a header link to a URL the project sets (`dashboard.standupUrl` in `.claude/commandeck.json`); test
  "a set standupUrl shows the link; unset shows none".
- Deploys card, deploy-dev and deploy-prod alerts, deploy source records: from a command the project sets
  (`dashboard.deployCmd`) that prints `[{env, sha, status, at}]`; the collector runs it with the slow groups; the
  newest row per env with status `failed` or `timed_out` raises `deploy-<env>`, as the host alerts on `failure` and
  `timed_out` (`host:.claude/scripts/dashboard_alerts.jq:75-78`); any other status raises nothing. Tests "a fixture
  deploy command's failed prod row shows on the Deploys card and raises deploy-prod" and "the row
  `{"env":"prod","sha":"abc123","status":"timed_out","at":"2026-10-23T12:00:00Z"}` raises deploy-prod".
- AWS source records: the same command's rows in Source records; no AWS call in the plugin. Test "the deploy
  command's rows appear in Source records".
- Chain verification: Main card's lastCheck → lastMerge → lastStop chain checked against the plugin's merge ledger
  (`unit-ledger.sh`). Test "a lastMerge with no ledger row shows the chain broken".
Not portable, stays waived: push-record verification (the plugin has no push step or push record, 306 R1/R7) and
the second machine's test lanes (the binding exclusion).

## Files edited

`scripts/merge-unit-local.sh` ~28, 37, 52, 60, 72, 505; `scripts/paths.sh` (beside `PP_MAIN`, `pp_route_json`
1081, the owner-bound function); `scripts/decision.sh` 114-117; `scripts/cos-check.sh` 41-50; `scripts/merge-queue.sh`
76; `scripts/builder-codex-pass.sh` ~1166 (round file timing), ~1202; `scripts/doctor.sh` (route source line); `docs/configuration.md` 25;
`hooks/context-clear-stop.sh` ~88 (checkpoint size after carry); `hooks/search-log.sh` (new); `scripts/search-log-report.py` (new); `hooks/hooks.json` PostToolUse 68, 71 and one
new entry; `docs/hooks.md`; `docs/auto-permission-mode.md` (new); `docs/security.md`; `scripts/cos-watch-inbox.sh`
96, 98, 140, 175; `scripts/orca-wait.sh` 348; `hooks/cos-own-echo.sh` 54; `hooks/agent-startup-context.sh` ~146
(relay block); `scripts/cos-watch-decisions.sh` 19; `scripts/cos-watch-alerts.sh` print; `scripts/hook-probe.sh`
17-18; `scripts/unit-ledger.sh` 40 and row fields; `scripts/dashboard_serve.py`; `scripts/dashboard.sh` (install
~963, review-loop and escapes projections ~596-600, tests panel, G5 keys, validator 1020);
`scripts/dashboard_limit.py` (tests, carry-failed, restarts); `scripts/dashboard_alerts.jq`; `dashboard/app.js`,
`dashboard/index.html`, `dashboard/app.css`; `skills/setup/SKILL.md`; `docs/dashboard.md` (cutover steps);
`.claude-plugin/plugin.json` 3; `CHANGELOG.md` top; and the test files named above. A "build it" answer in Q2-Q5
adds the files its fallback names.

## Size (changed lines, code + tests)

| Group | Code | Tests |
|---|---|---|
| G1 | ~280 (298 is ~220) | ~200 |
| G2 | ~70 + 1 rule line | ~100 |
| G3 | ~390 | ~310 |
| G4 | ~480 | ~300 |
| G5 (issue 292, 300, 283, cutover) | ~1,580 | ~800 |

G5 is about 55 percent of the unit. It is one unit by the owner's order; if main wants it split, G5 is the cut.

## Done when

- [ ] Main has the owner's answer to every question in Q1-Q5 before the build starts; each "build it" is added to
      its group.
- [ ] Every "build" row's named test exists, passes, and failed on 14f1b73; every green pin passes on 14f1b73 and
      on the tip.
- [ ] Changed-file tests and the test files of every edited script pass; no skipped case.
- [ ] Evidence file holds 249's timing, 283 and 300's before/after from the `restarts` report (with the baseline
      gap stated), 305's Orca cap source, 279's probes, and 292's host commit per row.
- [ ] `bash ci/leak-test.sh` passes.
- [ ] Version 0.40.0 (or next free minor) and the CHANGELOG section are in.
- [ ] A closing (final) pass ends `VERDICT: GO`.

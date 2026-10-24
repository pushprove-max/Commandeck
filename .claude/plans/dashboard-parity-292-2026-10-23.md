# Plan: dashboard-parity-292-2026-10-23 -- the rest of issue 292, and issues 293, 327, 328 and 329

Tier: Standard. LOCAL merge only. One unit, one Builder, one review loop. Base: main 3537ac2 (0.40.0).

Launch: new unit dashboard-parity-292-2026-10-23

Closes (the batch brief's line carries it): issues 292, 293, 327, 328 and 329

Public repo: no personal names, seat nicknames, host product name, ruling ids or user paths in any shipped file,
test, commit message or changelog line (`ci/leak-words.txt`). Outside CHANGELOG.md an issue is written "issue N"; a
host issue is "host issue N". A ported change is named by its host commit and function names.

Changed-file tests only, plus the test files of every script edited. No red proofs (no `red-proof.sh`, no
`Mutation-verified:` line). No new dependency, no new feature flag, no test-timeout raise. Every test runs through the
real script: `bash scripts/run-shell-tests.sh <file>`; `.mjs` files with `node --test <file>`. A test named below as
"fails today" must fail on 3537ac2 first; one that passes there is a green pin, and its row is marked met.

Main asks the owner the open questions under "Questions for the owner" (Q5-Q7) once, before the build starts. The plan
already builds each question's recommended answer; the other answer changes only the rows that question names.

## Main answers

The owner answered Q1-Q3 and the host-load question before the round-1 revision. These are their answers; they are
settled and are not asked again.

- The 5 stages are met; extras that are only measured are recorded as measured, not
  built.
- Host-only rows are skipped. There is no extension point for them, so no iframe or embed either.
- Keep the plugin's object-shaped `.projects`.
- Host-load (was Q8): the alert stays removed (removed on purpose 2026-10-15; swap still alerts); its no-alert test
  stays.

## Decisions (ponytail ladder; one line per cut)

- Rows already met (most of issue 292): rung 1, no code; the table names the code and test. Rejected: re-proving.
- Waived rows (standup, deploys, AWS, chain and push-record checks, second machine): rung 1: the owner accepted the
  last unit's waivers. Rejected: rebuilding them as config hooks.
- Skipped rows (driver badge, `lastMarker`, `lastStop`, `lastCheck`, the per-project extension point): rung 1, by
  the owner's answer above. Rejected: an extension point, an iframe, an embed.
- Checkpoint-rejected alert: rung 2: one jq rule beside the plugin's own (`main-events` already reads the stop-hook
  log). Rejected: a new alert reader.
- Host-load alert: rung 1, by main's answer above: not rebuilt (the plugin removed it on purpose in 4cf302b), and the
  judge's finding 7 on `dashboard-alerts.test.sh:15` is answered by that ruling: the no-alert case stays. The owner
  answered it (Main answers); it is no longer an open question.
- Unit launch roster: rung 2: the plugin has no routing log with a round per launch (its `routing-log` holds only
  override notes, `builder-launch.sh:200`), so the port reads the two records that do exist: the Builder's seat
  record (`seat-<unit>-builder.txt` `cmd=`, parsed as `plan_seats` parses it, `dashboard.sh:180-189`) and the review
  pass's own `codex-start` row (`builder-codex-pass.sh:996`), which gains the model and effort the pass resolved
  (`:736`, `:741`). Rejected: a new routing log written by every launcher (the host's source; the plugin's events log
  already carries the round).
- Main-seat average: rung 1: the host's definition, one changed window in `dashboard_limit.py seats`. Rejected: a
  second coverage check: the plugin's `requests()` reads back to the `since` it is given or returns None (`:458`),
  so asking it for the seven days before today is the coverage the host checks.
- Parked list, stop notes on unit cards, merged-since-push, last merge: rung 2: the data the plugin already collects
  (seat records and Orca tasks, decisions waiting on main, finished builds, the push range). Rejected: porting the
  host's driver logs.
- P1 and proposed-decision lists: rung 2: the host's `labelled()` over the plugin's existing `gh_read`/`cached`.
  Rejected: a second GitHub reader.
- Seat card fields and seat weeks: rung 2: port host b257a08f's fields into `dashboard_limit.py seats`, which already
  reads both seats' sessions. Rejected: a new per-seat collector.
- Tests row Builder share: rung 2: the host's `builderShare` sum over the session logs `dashboard_limit.py tests`
  already reads. Rejected: the host's shell-test ledger (queued, failed under load): see Q5.
- `/p/<name>/` pages: rung 5: a redirect to the page the plugin already has (`index.html?project=<name>`).
  Rejected: per-project data files (Q7) and the `.projects` array (owner answer above).
- Parallel slow groups: rung 3 (platform): bash `&` and `wait`, as host f8643c34, inside `project()` only.
  Rejected: a job runner; moving `limit` (it reads the finished project inventory).
- 293: rung 1 for all but one acceptance pin: the code is in. Settled by the batch brief, not a question: no
  project-file read of `builder.effort`/`builder.model` comes back, and issue 312's tests stay as they are.
- 328: rung 1: one rule line in the existing main-session text, the host's words. Rejected: a new guard.
- 329: port-by-commit of host 33cdf11c (`answer-worker.sh`: Orca's own `orchestration reply --id` when the question's
  id is given, else `send`), with the id the plugin's wake line already passes. Rejected: inferring the id from the
  unit's only open question (the host does not; `orca-wait.sh:345-346` already prints the id in main's command).
- 327: rung 2: measure with the plugin's own `hook-probe.sh` isolation, then fix only what the measurement finds in
  the plugin's own files. Rejected: trimming the harness's own attachments (skill listing, instructions), which the
  plugin does not write.

## 1. Issue 292: every gap and switch breaker

Status: **met** (in code; file ~line, and its test), **waived** (owner accepted the last unit's waiver), **skipped**
or **measured** (the owner's answers above), **build**, **question** (built as the recommendation; Q5-Q7). Host
paths are `host:<path>` at host main 0f38db4b.

### Switch breakers

| Breaker | Status | Evidence / build |
|---|---|---|
| Relay reads the old data file's decisions key | met (owner answer of the earlier parity plan: no plugin change) | The plugin's watcher reads the decisions ledger (`scripts/cos-watch-decisions.sh:16`). The host's own watcher still reads `needsMax.decisions` (`host:.claude/scripts/*/watch-decisions.sh:21`); the switch replaces that watcher with the plugin's, by `docs/dashboard.md:162` "Switching from another collector". Cutover test `scripts/__tests__/dashboard-built.test.sh:69` |
| Alert ids gain a project prefix | met (seed once, same owner answers) | `scripts/cos-watch-alerts.sh:52`; seed and the alert after it, `cos-tell.test.sh:301`, `:304` |
| Fixed port and LAN bind | met | `scripts/dashboard.sh:60`, `:61`, `:1257`; network install and HTTPS, `dashboard-loop.test.sh:67`, `:71` |
| `COMMANDECK_SCRATCH` in the job | met | `dashboard.sh:1264`; `dashboard-loop.test.sh:54` |
| `decision.sh` drift | met | JSON array, `decision.test.sh:32`; `push-ask` cases from `:43` |
| 7-day history, layouts, cleared builds | met | `dashboard.sh --import` (`import_from`); `dashboard-built-costs.test.sh:50`, `:52`, `:54`, `:57`, concurrent writes `:96` |
| Ledgers to jq as files | met | `dashboard.sh:414`, `:419`; over-1-MB case `dashboard-built-costs.test.sh:23` |
| Register home | met | `dashboard.sh:1119`; first registration `dashboard-built-costs.test.sh:36`, cutover registration `dashboard-built.test.sh:64` |

### Gaps

| Row | Status | Plugin today (~line) | Host source | Build: files (~line) | Test (fails today) |
|---|---|---|---|---|---|
| Page title / h1 | met (0.40.0) | `dashboard/app.js` project name title | -- | -- | `dashboard-view.test.mjs:675` |
| Project bar, per-project pages | build (redirect only; Q7) | bar at `app.js:1831`, pages `index.html?project=<n>` | `host:.claude/scripts/dashboard_server.py:32` `/p/<name>/` | `scripts/dashboard_serve.py` `do_GET` after `gate()` and `foreign()` (`:669`), both kept. The name is matched against the registered names (registration takes `[A-Za-z0-9_.-]`, `dashboard.sh:1127`), so `demo.api` is a name; a `.` or `..` path component, an encoded `/`, or a name not registered is 404 | `dashboard-serve.test.sh` "GET /p/demo/ and GET /p/demo.api/ of registered projects redirect to index.html?project=<name>; /p/../, /p/%2E%2E/, /p/a%2Fb/ and an unknown name are 404 with no Location". Catches: a dotted project name refused, or a traversal name turned into a Location |
| `.projects` as `[{slug,name}]` | met by the owner's answer (the plugin's object stays) | object by name (`dashboard.sh:1051`) | -- | -- | -- |
| Standup link | waived | -- | -- | -- | -- |
| Phone tab bar, 7 tabs | met (0.40.0) | `dashboard/index.html:264-270` | -- | -- | `dashboard-view.test.mjs:654` |
| Summary strip | build (P1 count) | strip `app.js:1582-1600` has alerts, builds, cost, unpushed, units, load | `host:.claude/dashboard/app.js:2033` `renderSummary` (P1) | `app.js` strip (one `measure`) | in G3's P1 case: "the strip shows the open P1 count" |
| Alerts resolved drawer | met | `dashboard.sh:993`, `app.js` | -- | -- | `dashboard-view.test.mjs:1082` |
| Alert host-load | not built (the owner's answer: removed on purpose in 4cf302b) | `host()` gives `cpus`, `load` (`dashboard.sh:848`); no rule, by design | 1e8b2d1c, `host:.claude/scripts/dashboard_alerts.jq:67` | -- | `dashboard-alerts.test.sh:15` "a load far over the core count raises no alert" stays unchanged |
| Alerts deploy-dev / deploy-prod | waived | -- | -- | -- | -- |
| Alert main-compact-* | met (0.40.0) | `dashboard_alerts.jq:77` | -- | -- | `dashboard-main-events.test.sh:30`, `:33`, `:45` |
| Alert checkpoint-rejected-* | build (the carried, not-restarted case) | `carry-failed-*` covers a carry the hook could not heal; a checkpoint whose items were carried automatically is dropped (`dashboard_limit.py:1469`), and nothing alerts when main never restarted after it | 48151d13, `host:.claude/scripts/dashboard_alerts.jq:91-97` | `scripts/dashboard_limit.py` main-events: keep a `carried` row `{cp, at, items, restartedAt}` per `items carried automatically into the checkpoint <cp>` line (`restartedAt` the next restart's time, else null); that list is the rejection history the issue's `mainEvents` row asks for. `dashboard_alerts.jq` rule `checkpoint-rejected-<p>-<cp name>` when `restartedAt` is null and the carry is over 120 s old | `dashboard-main-events.test.sh` "a carried checkpoint with no restart for 121 s raises checkpoint-rejected; a restart after it ends it; 119 s raises nothing"; "mainEvents.carried lists m1 with its 2 items and restartedAt null". The existing exact alert list at `:33` gains `checkpoint-rejected-demo-m1` (the fixture's m1 was carried 7,299 s ago and never restarted); its carry-failed ids stay as they are |
| Alerts stage, builder, cache-builder, question, guard-spike | met (ids by the seed answer; stage 7200 s, question 3600 s) | `dashboard_alerts.jq:49-73` | -- | -- | `dashboard-alerts.test.sh:24`, `:34` |
| Alert id stamps | met | `$CACHE/alerts-since.json` (`dashboard.sh:983`) | -- | -- | `dashboard-alerts.test.sh:65` |
| Units board stages (7) | met by the owner's answer (the 5 stages) | 5 stages, `app.js:14` | `host:.claude/dashboard/app.js:14` (5) | -- | -- |
| Unit fields: `worktree` | build | the published in-flight row (`dashboard.sh:380`) has no `worktree`; `:403` is the cost reader's input, not the row | `host:.claude/scripts/dashboard.sh:499` (boolean) | `dashboard.sh:380`: each worktree row gets `worktree: true`; parked rows (below) carry `false` | `dashboard-built.test.sh` "an ordinary worktree u publishes .units.inFlight[] \| select(.unit==\"u\") \| .worktree as true". Catches: a reader that tells parked from live by `worktree` getting null for every live unit |
| Unit fields: seats[] (launch roster) | build (judge r2 finding 2: planning seats are not the roster) | planning cards list plan seats (`app.js:441`, `dashboard-built-planning.test.sh:52`, stays); a Builder unit publishes no roster (`dashboard.sh:380`) | `host:.claude/scripts/dashboard.sh:513-530` (per unit, the latest launch per role in its highest round), `host:.claude/dashboard/app.js:608-617` ("launched as" line, role as each name's title) | (1) `scripts/builder-codex-pass.sh:996`: the `codex-start` row gains `model` (`$MODEL`, `:736`) and `effort` (`$EFFORT`, `:741`; null on a Claude-run pass), built with `jq -nc` so a value cannot break the row. (2) `scripts/dashboard_builders.jq`: output `passes` = for the highest `round` among `codex-start` rows, the newest row per `pass` as `{role: "codex-reviewer", pass, model, effort}` (a row from before this change has `model`/`effort` null). (3) `dashboard.sh` `units()` (`:380`): `seats` = the Builder's launch `{role: "builder", model, effort}` from `$PP_SCRATCH/seat-<unit>-builder.txt` `cmd=` (the `--model`/`--effort` captures `plan_seats` uses, `:186-187`, moved into one jq def both call) followed by `$b.passes`; null when the unit has no Builder; `[]` when neither record has one. (4) `app.js` unit card after the badges (`:466`): a Builder card with a non-empty `u.seats` gets `p.meta.seats` "launched as " + each seat's `modelName(model)` and effort joined by " · ", role as its title; a null model reads "model not recorded" as the plan line does (`:442`) | `dashboard-built.test.sh` "a unit in round 2, its Builder record launched --model claude-sonnet-5-5 --effort high, a round-1 review pass on gpt-6.1 high and a round-2 review pass on gpt-6.1-sol medium, publishes seats [builder sonnet high, codex-reviewer gpt-6.1-sol medium]: the round-1 pass is not listed"; `builder-codex-pass.test.sh` "the pass's codex-start row carries the reviewer's resolved model and effort"; `dashboard-view.test.mjs` "a Builder card in round 2 with u.seats [builder claude-sonnet-5-5 high, codex-reviewer gpt-6.1-sol medium] shows launched as with both seats, each role as its title" (the judge's exact input). All three fail on 3537ac2 (no field, no row keys, no line). Catches: a card that hides which model and effort the current round really runs |
| Unit fields: driver badge, lastMarker | skipped (owner answer: host-only) | -- | -- | -- | -- |
| `units.mainAsks` (stop notes on cards) | build | a Builder's question to main is listed under Needs only (`app.js:252-254`; `:588` passes the cards no decisions) | 58df4850, `host:.claude/dashboard/app.js:582`, `:689` | `dashboard/app.js` unit card: that unit's open `waitsOn: "main"` decisions as its stop notes (data exists in `needsOwner.decisions`; no collector change) | `dashboard-view.test.mjs` "a unit's open question to main shows on its card as a stop note" |
| `units.builderCap` | met (0.40.0) | `dashboard.sh:418`, `:428` | -- | -- | `dashboard-built-seats.test.sh:59` (`maxBuilders=3`) |
| Finished builds history | build (no cap) | 100 at most (`dashboard.sh:448` `.[:100]`) | `host:.claude/scripts/dashboard.sh:575` "There is no cap" (host issue 2415; the Builder names its commit, `git log -S'There is no cap'`) | `dashboard.sh:437`, `:448` | `dashboard-built.test.sh` "151 merge lines give 151 finished builds" |
| Parked, no worktree | build | units come only from worktrees (`dashboard.sh:280-281`); `open_tasks` (`:146`) returns task ids only | 365ed9ec, `host:.claude/dashboard/app.js:695-722`, `index.html:130-132` | The join is the seat records, as `seat_role` (`dashboard.sh:157`) reads them: each `$PP_SCRATCH/seat-*.txt` holds `launched`, `role`, `task`, `unit` (and `worktree`). A record whose `task` is in `open_tasks` and whose `unit` has no `$PP_WORKSPACES/<unit>` worktree is a parked unit; the newest such record per unit gives one row `{unit, worktree: false, stage: null, role, task}`, appended to `.units.inFlight` after the stage stamping and cost join (`:395-415`), so it gets no stage record and no cost row. `app.js` units list (`:588` `group()`): `worktree === false` is the `parked` group; `index.html` details block. Every `inFlight` reader (`rg inFlight dashboard scripts`: `app.js:583`, `:628`, `:910`, `:958`, `:1559`, `dashboard_alerts.jq:53`, `:68`, `:71`, `:110`) is checked for a null stage | `dashboard-built.test.sh` "a seat record for unit u naming open task task_7, with no worktree u, lists u with worktree false; the same record with task_7 completed lists nothing"; `dashboard-view.test.mjs` "a unit with worktree false shows under Parked, not in a stage". Catches: a unit whose Builder pane is gone but whose task is open vanishing from the board |
| Merged since last push | build | finished builds and the push range exist apart (`dashboard.sh:429`, `:591` omit it) | 5313f3f1, `host:.claude/scripts/dashboard.sh:570`, `host:.claude/dashboard/app.js:702` | `dashboard.sh` `units()`: `mergedSincePush` = finished builds whose merge commit is in `@{upstream}..HEAD` (the range `next_push` reads, `:573`); `app.js` card; `index.html` | `dashboard-built.test.sh` "two merges after the upstream and one before: mergedSincePush lists the two"; `dashboard-view.test.mjs` "the merged-since-push card lists them" |
| Main's seat card: context, line, restarts | met | `app.js:1099` | -- | -- | `dashboard-view.test.mjs:847-850` |
| Main's seat card: 7-day average | build (judge r2 finding 3: a different window, not met) | `dashboard_limit.py:1352-1355` averages the last 7 x 24 h, today included (`week = now - 7 * 86400`, `:1326`) | `host:.claude/scripts/dashboard_limit.py:1299-1315` `seat_figures`: the seven days before today over 7, null unless the request cache reaches back over them | `dashboard_limit.py seats`: `avg7` = `figures` of rows with `midnight - 7 * 86400 <= at < midnight`, over 7, same `{tokens, usd, partial}` shape; the `requests()` call (`:1343`) asks from `min(week, midnight - 7 * 86400)` so those days are read (its None return already nulls the seat); `week` stays the last 7 x 24 h for the new `week` figures; the docstring line at `:1319` says the new window. `app.js:1103` label stays | `dashboard-built-seats.test.sh:30-32` changes from `[...,28571,0.0029,...]` to `[100000,200000,100000,0.01,14286,0.0014,2,60]`: the fixture's $0.01 request 3 days ago (`m0`, `:20`) and $0.01 today (`m1`) give $0.01 / 7 (fails on 3537ac2, which counts today's too). Catches: today's spend counted twice, in Today and in the average it is compared with |
| Main's seat card: live, rebuild cost, hourly, account, week | build (account: the plugin's `accountLabel`, no e-mail; week: Q6) | not collected (`dashboard_limit.py:1354` returns today, avg7, restarts only); `accountLabel` is emitted (`dashboard_limit.py:1149`) and shown only on the limit card (`app.js:1400`); `renderSeat` (`:1094`) gets neither | b257a08f, `host:.claude/dashboard/app.js:1458-1492`, its `dashboard_limit.py seats` | `scripts/dashboard_limit.py` seats (`:1354`): `live` (a turn in 10 min), `rebuildUsd` (first-turn cost after each restart), `hourly` (12 hourly token sums), `week` `{sessions, unmeasuredSessions, input, cachedInput, output}` over the 7 days the reader already filters (`:1352`); `app.js` `renderSeat`; account: `renderSeat('main-seat', d.seats && d.seats.main, false, d.limit && d.limit.accountLabel)` (`:1644`) and an `Account` fact on main's card when the label is a string (judge r2 finding 4) | `dashboard-built-seats.test.sh` "main's seat: live, rebuildUsd, 12 hourly sums and week from a fixture session"; `dashboard-view.test.mjs` "main's card shows working now, rebuild cost and the hourly spark"; `dashboard-view.test.mjs` "a populated main seat with limit.accountLabel a…@example.org shows Account a…@example.org on main's card; a null label shows no Account fact" (fails on 3537ac2). Catches: main's card leaving out which account its spend is billed to |
| Relay's seat card: hourly, side runs, week | build | relay card has context and today only | b257a08f, `host:.claude/dashboard/app.js:1480-1490` | same reader and `renderSeat`: `hourly`, `sideRuns` ({count, usd} of the relay's subagent runs today), `week` (as main's) | `dashboard-built-seats.test.sh` "the relay's seat: hourly, sideRuns and week from fixtures"; `dashboard-view.test.mjs` "the relay card shows side runs today" |
| Seat weeks in the role totals | question (Q6; built as recommended) | `renderCost` (`app.js:1144`) takes the seat-event ledger's roles only, so main and the relay, which write no seat-event row, have no role row | `host:.claude/dashboard/app.js:1531` `seatRoles` | `app.js` `renderCost(d.costPerRole, d.seats)`: a seat whose `week.sessions` > 0 adds its role row (the relay's and main's labels as the page names them), as `seatRoles` | `dashboard-view.test.mjs` "main with one request this week and no seat-event row shows its role row with that request's tokens; a seat with no session this week adds none". Catches: the role totals leaving out main's and the relay's own spend |
| Tests running now | met for running, owners, elapsed, stalls, finished (issue 269; `dashboard.sh:906-929`); second machine waived; Builder share build; queued and failed under load Q5 | `tests_panel` publishes `running` and `finished` only | `host:.claude/scripts/dashboard.sh:1303-1307`; `builderShare` `host:.claude/scripts/dashboard_limit.py:711`, `host:.claude/dashboard/app.js:1085` | `dashboard_limit.py tests`: `testSecToday` and `builderShare` (test seconds today run in Builder worktrees over the Builder sessions' span today, as host `:711`; the Builder worktrees are the ones `tests_panel` already lists, `dashboard.sh:908`); `tests_panel` passes them through; `app.js` Tests card shows the share | `dashboard-tests-panel.test.sh:73` stays; new "a Builder worktree's 60 s of tests in a 600 s Builder span give builderShare 0.1; no Builder session today gives null"; `dashboard-view.test.mjs` "the Tests card shows the Builder share". Catches: Builders' test time hidden inside the day's total |
| Needs owner: P1 list (top 5 and all) | build | a count only (`github_p1`, `dashboard.sh:487`, `:494`; `app.js:245-259`) | 1338872d, `host:.claude/scripts/dashboard.sh:597` `labelled()`, `:606` | `dashboard.sh` `github_p1` fetches `number,title,url` and returns `{count, top, all}`; every `githubP1` reader (`rg githubP1`) moves with it; `app.js` `renderNeeds` | `dashboard-github.test.sh` "seven P1 issues give count 7, the five lowest numbers in top, all seven in all"; `dashboard-view.test.mjs` "Needs lists five P1 issues and a show-all" |
| Needs owner: proposed decisions | build | none | 1338872d, `host:.claude/scripts/dashboard.sh:589`, `:599`, `host:.claude/dashboard/app.js:266`, `:293` | `dashboard.sh` beside `github_p1`, the same `labelled()` read for label `proposed-decision`, the same `{count, top, all}`; `app.js` `renderNeeds` renders the list as the P1 one | `dashboard-github.test.sh` "seven open proposed-decision issues give count 7, the five lowest numbers in top, all seven in all"; `dashboard-view.test.mjs` "Needs lists five proposed decisions, each title linked to its issue url, and a show-all that opens all seven". Catches: a count with no way to open the issues it counts |
| `push-ask` rows | met | `decision.sh:249`; rows use the ordinary decision renderer (`app.js:251`) | -- | -- | `decision.test.sh:43` (issue 259) |
| Main card: last merge | build | `main_chain` has commits and unpushed only (`dashboard.sh:584`) | `host:.claude/scripts/dashboard.sh:661` (`lastMerge`; the Builder names the commit, `git log -S'lastMerge: $lm'`) | `main_chain`: `lastMerge` = newest finished build `{unit, at}`; `app.js` main card | `dashboard-built.test.sh` "main_chain lastMerge names the newest merged unit"; `dashboard-view.test.mjs` "the main card shows the last merge" |
| Main card: lastCheck, lastStop, chain, push record | waived (chain, push record) / skipped (lastCheck, lastStop: owner answer, host-only) | -- | `host:.claude/scripts/dashboard.sh:645`, `:690-703` | -- | -- |
| Open pull requests with tally | build (tally) | list at `app.js:908-915` | 3ad07a14, `host:.claude/dashboard/app.js:1264-1269`, `index.html:319` | `app.js`, `index.html` `prs-tally` | `dashboard-view.test.mjs` "three open PRs, one draft: the tally reads 3 open, 1 draft" (the tally's words as the host's) |
| Issues by milestone, P1 alarm | build (the host's read limit) | by milestone `app.js:949-974`; 200 issues read (`dashboard.sh:523`) | `host:.claude/scripts/dashboard.sh` issue read, limit 1000 | `dashboard.sh:523` `--limit 1000` | `dashboard-github.test.sh` "the issue read asks for 1000" (the fake `gh` records its args). Known gap: 1,001 open issues read 1,000 (below) |
| Issues card by priority | build | 7-day flow and sparkline only (`dashboard.sh:556-561`) | 1338872d, `host:.claude/scripts/dashboard.sh:741`, `host:.claude/dashboard/app.js:1213` | `github_panes` `byPriority` from the issues it already reads; `app.js` issues card | `dashboard-github.test.sh` "issues P1, P1, P2 and one unlabelled give byPriority P1 2, P2 1, none 1"; `dashboard-view.test.mjs` "the Issues card shows counts by priority" |
| Next push: list | met | `next_push` (`dashboard.sh:569`) | -- | -- | `dashboard-github.test.sh:72` |
| Next push: verdict | waived (push record) | -- | -- | -- | -- |
| 7-day limit card (used, 5 h, history) | met in code (`dashboard_limit.py:1111`, `app.js:1349-1375`); history plot pin | the named case (`dashboard-view.test.mjs:208`) checks the 5 h label only | -- | -- | pin, `dashboard-view.test.mjs` "three history readings plot three points with their percentages". Catches: the history plot breaking with no test noticing |
| Limit: cost today, whole machine | met in code (`dashboard_limit.py:1176`, `app.js:1409`; the strip's is per project by design); pin | no test feeds two projects | -- | -- | pin, `dashboard-billing.test.sh` "requests from two projects: limit.cost.today is their combined cost". Catches: the account figure narrowing to the home project |
| Deploys card | waived | -- | -- | -- | -- |
| Issues card sparkline | met (issue 273) | `dashboard.sh:556-561` | -- | -- | `dashboard-github.test.sh:76`; `dashboard-view.test.mjs:297` |
| Tokens per unit, Review loop, Review escapes | met | `dashboard.sh:431`, `:598`, `:605` | -- | -- | `dashboard-built-costs.test.sh:109`, `:127`, `:133` |
| Relay inbox | met in code (`chief_of_staff`, `dashboard.sh:944`); pin | the only nearby fixture returns an empty inbox (`dashboard-built-plan-worktrees.test.sh:64`) | -- | -- | pin, `dashboard-built.test.sh` "a fake inbox with two unread messages gives unread 2 and the older one's age". Catches: the unread count reading 0 with mail waiting |
| `measures` extras | measured, not built (owner answer) | `measures()` (`dashboard.sh:634`) | `host:.claude/scripts/dashboard.sh:833` (retired) | -- | -- |
| `mainEvents` | met (0.40.0) for compactions, unhealed carries and restart time (`dashboard_limit.py:1481`); rejection history built by the checkpoint-rejected row | `dashboard.sh:971` | -- | -- | `dashboard-main-events.test.sh` |
| Collector speed: part seconds | met (0.40.0) | `dashboard.sh:1009-1013` | -- | -- | `dashboard-built-seats.test.sh:54` |
| Collector speed: slow groups in parallel | build | every part in one `&&` chain (`dashboard.sh:1034-1037`) | f8643c34 (host issue 2580), `host:.claude/scripts/dashboard.sh:1393-1402` | See "Parallel parts: scheduling" below | `dashboard-built.test.sh`, see below |
| Source records | met for the generic inputs (`dashboard.sh:72`); host-only ones skipped (owner answer) | `rec`/`ok`/`nm` names in `dashboard.sh` | -- | -- | `dashboard-github.test.sh:92`; `dashboard-tests-panel.test.sh:73` |
| Login, LAN bind, one-click answer after login | met (issue 263, 0.40.0) | `gate()` `dashboard_serve.py:645` | -- | -- | `dashboard-serve.test.sh:799`, `:800`, `:807`, `:808` |
| launchd job, data file | met (install) / retired at the switch | `dashboard.sh` `install` (`:1251`); atomic publish `:1104` | -- | -- | `dashboard-loop.test.sh:29`, `:54` |
| Host-only extension point (the issue's scope comment) | skipped (owner answer: no extension point, no iframe or embed) | none | -- | -- | -- |

### Parallel parts: scheduling

`limit` is not moved. It belongs to `render()` (`dashboard.sh:1087`), runs after `projects`, and reads the finished
project inventory (`$RUN/parts/projects.json`, `:873`); in `project()` that file does not exist. It stays where it is.

Inside `project()` (`:1034-1037`) the parts that share a cache file stay in the sequential chain in today's order:
`units`, `seats` and `tests` all read and rewrite the request caches under `$REQS` (`limit-requests.json`,
`test-runs.json`), one writer at a time. Only the host's other two slow groups start with `&` at the top of the
chain: `measures` (`subagent-usage.sh` and two ledger reads) and `guardBlocks` (its own `$CACHE/guard-blocks.json`).
Each writes only its own `$RUN/v-<k>`, `$RUN/parts/<k>.json`, its own `$RUN/src/<key>.json` records and one
`part-seconds` line. The chain then `wait`s on each pid and checks its exit status, so either failing fails the
collect as today. `alerts` stays in `render()`, after every project.

Tests (`dashboard-built.test.sh`), on the test's own copy of the scripts:

- "with subagent-usage.sh stubbed to sleep 2 and the hook fire log a FIFO fed after 2 s, a collect takes under 3.5 s"
  (the sequential chain takes at least 4 s). Catches: the parts still running one after another.
- "that collect's data.js equals the same fixture's with no sleep, after normalizing": both with `del(.updatedAt)`,
  each project's `partSeconds` removed, and `sources` reduced to each key's `status`, since those are clock or
  timing values (`:1092`, `:1009`). Catches: a part lost or truncated when two run at once.
- "a guardBlocks part that fails still fails the collect and keeps the last data.js" (a green pin: the sequential
  chain already fails; it guards the move to `&`/`wait`). The failing input (judge r2 finding 4; a directory at
  `$CACHE/guard-blocks.json` does not fail, `dashboard.sh:732-742` swallows the write): a readable hook fire log
  (`COMMANDECK_HOOK_FIRE_LOG`) with one row, and a `$CACHE/guard-blocks.json` that names that file at its current
  size with a block whose session is not in its `sessions`:
  `{"version":1,"files":[["<log>",<size>]],"sessions":{},"blocks":[[{},"s9",null]],"blocked":[]}`. The state is
  taken as current (`:676-685`), and `blocks = [(r, sessions[k], a) ...]` (`:743`) raises `KeyError: 's9'`, so the
  python exits 1 and `guard_blocks` returns 1 (`:784`). Checked on 3537ac2's code: that state exits 1, a cold read
  of the same log exits 0. The test also asserts the collect's exit is non-zero and data.js is byte-for-byte the
  previous one. Catches: a backgrounded failure that `wait` never reports.
- "a backgrounded measures still takes the subagent ledger's lock" (a green pin; judge r2 practice note, batch item 7):
  `measures()` runs `subagent-usage.sh` (`dashboard.sh:635`), which appends to `subagent-usage.jsonl` under
  `flock` on `subagent-usage.jsonl.lock` (`scripts/subagent-usage.sh:40`). With the test holding that lock for 2 s
  (`flock` in a background subshell), the parallel collect's ledger has no new row until the test releases it, and
  one row after. The lock line is not moved or wrapped. Catches: a parallel `measures` that appends beside another
  collect's run and writes a run twice.

## 2. Issue 293: the code decides

The 0.25.0 CHANGELOG line says set-up and the doctor shipped; the 2026-10-22 audit note says not. The code shows
the 0.25.0 line right on both, and wrong on one word: "keeps the project's answer". Issue 312 (closed, later) made
a role key read no answer from the project's file: `/plugin` keys are read at `scripts/paths.sh:975`, `pp_route_json`
overlays them at `:1092`, and a per-launch value applies at `:784`. Today's order is: a per-launch pin, then the
`/plugin` key, then `config/routing.json` (`roles.builder.effort` = high). `docs/configuration.md:25` states the
order; `:57` retires the project fields. Settled, not reversed: the plan never reads the project file's
`builder.effort` or `builder.model`, and the doctor names only the sources that exist today.

Already works, with its test:
- Set-up asks "Builder effort" right after "Builder model", High recommended on Sonnet, Medium on Opus
  (`skills/setup/SKILL.md:114-121`); `scripts/__tests__/plugin.test.sh:87`.
- `/plugin` config shows `builderEffort` (project, low, medium, high, max) with a description
  (`.claude-plugin/plugin.json` userConfig); a `/config` answer runs: `plugin-option.test.sh:40`.
- An update or re-run keeps the owner's effort: `plugin-option.test.sh:189`.
- The precedence: `plugin-option.test.sh:26`, `:34`, `:36`, `:42`, `:46`.
- The doctor prints the effective model and effort and where each came from (`scripts/doctor.sh:53-55`):
  `doctor-options.test.sh:23`.
- The launch command: `scripts/__tests__/seat.test.sh:53` checks that `/config` high beats the project file's medium
  on the Builder's launch line.

Added: one stronger pin. `seat.test.sh:53` passes with high, which is routing's own default, so it would pass with
the `/plugin` key ignored. Case beside it, in the same form: "a Builder launched with /config's effort max, the
project's file saying medium, opens with --effort max", read from the seat record's `cmd=` line as `:53` reads it.
Expected green (a pin); if it is red, the launch path is the defect and the Builder fixes it in `pp_route_json` or
`seat.sh`, not in the test. Catches: a launch that drops the `/plugin` effort and falls back to routing's.

Added (judge r2, batch item 8): the precedence case the named launch-pin case cannot show, since its `--effort high`
(`seat.test.sh:32-33`) equals routing's default. In `seat.test.sh` beside `:53`, in the same form: "/config
builderEffort medium, the project's file saying low, and a launch pin --effort high: the seat record's cmd= line
has --effort high" (the pin beats the `/plugin` key, which beats routing, and the project file is never read). The
launch is a raise from medium, which `seat.sh` allows (`seat.test.sh:44-47` pins that only a pin below the default
is refused). Expected green
(a pin; batch item 8 asks for the case, not a fix); if red, the defect is in `pp_route_json` (`scripts/paths.sh:784`)
and is fixed there. Catches: a launch pin that loses to the `/plugin` key, or a stale project effort that leaks into
the launch line. Issue 293 closes as superseded by issue 312 once both pins pass. Cleanup
check: `seat-launch.test.sh:9` writes the project file's `builder.effort`, which no reader takes since issue 312; the
Builder drops it when no case depends on it.

## 3. Issue 327: main's context overhead

Today, at 3537ac2 (probed with each hook run directly, an isolated HOME, a `git status` call):
- Every Bash hook in `hooks/hooks.json` (PreToolUse: `pane-budget-gate`, `git-safety`, `merge-lock-guard`,
  `bash-guardrails`, `no-poll-loops`, `duplicate-agent-guard`, `suite-rerun-guard`, `dependency-addition-guard`;
  PostToolUse: `read-tracker`, `script-over-reads`, `staged-index-warn`, `suite-rerun-guard --record-complete`,
  `search-log`, `batch-independent-looks`) printed 0 bytes. Wanted 1's first half holds for that call; the
  measurement below checks the whole scripted session.
- Advisory nags: `script-over-reads.sh` is already once per family per session (`:17`). `batch-independent-looks.sh`
  is not: it resets the streak after each nudge (`:158-160`), so a session nudges again after every further 3
  single-look turns (the state at `:140` keeps only the time and the streak). It runs for main only with
  `strictHooks` on (`:37-41`).
- Path-scoped rule templates: the plugin ships none (`rg -l '^paths:' templates`: none; set-up writes nothing into
  `.claude/rules/`). The path-scoped files in the issue's measurement are the project's own (for example a
  project's `orchestration.md`, gated on `.claude/briefs/**`, `scripts/worktree-setup.sh:140`). Wanted 2 is met by
  the plugin adding none; the measurement names each rule file's path, so the owner sees whose it is.
- Task-list reminders: the Claude Code docs (tools reference, "Task tool availability"; env-vars) say the Task tools
  and their reminders come only on the models listed there, or when `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` is set or
  `--allowedTools` names a Task tool, from Claude Code 2.1.268. Nothing in the plugin sets either
  (`rg 'ENABLE_TODO_TOOLS|allowedTools'`: only the review runs).

Build, in this order inside G1:

1. **Measure first.** `scripts/context-overhead.sh <plugin root>`: replays a fixed scripted main session (in the
   script: a SessionStart, 3 prompts, 12 Reads of distinct files with 5 from one folder, 12 routine Bash calls --
   `git status`, `git log -1`, `rg -n`, `ls`, `sed -n`, `jq` -- with 4 single-look turns in a row) through every
   hook `<plugin root>/hooks/hooks.json` wires for each event and tool, using `hook-probe.sh`'s isolated HOME and
   scratch, in a fixture project with `"strictHooks": true` so the strict-tier hooks are measured too (main runs
   them only then). It counts only what Claude Code passes to the model (the hooks reference, "Hook output": SessionStart
   and UserPromptSubmit stdout, `additionalContext`, and stderr of an exit 2), and prints bytes per hook and the
   total. The Builder confirms that rule against the current hooks reference before writing it and names the page
   in the script's header. Run at 3537ac2 (`git worktree add` of the base) and at the tip; both outputs go in the
   evidence file with the command. The work below is done in the order of that ranking; a hook the measurement
   shows at 0 bytes is not touched. Catches: work ranked by guess, and a fix that does not shrink what the model
   reads.
2. **Nags once per session per kind.** `batch-independent-looks.sh`: the state keeps a `nagged` mark per session id;
   a second streak in the same session prints nothing; a new session nudges again. Any other Bash hook the
   measurement shows printing on a call with nothing to act on gets the same fix in its own file. Today the hook
   resets the streak after each nudge (`:158-160`), so a session nudges again at every third further single look,
   not on every call. Tests, `hooks/__tests__/batch-independent-looks.test.sh`, run as main: no `COMMANDECK_SEAT`
   or `COMMANDECK_BUILDER`, and the fixture project's `.claude/commandeck.json` sets `"strictHooks": true`, so
   `pp_strict` (`hooks/lib/project.sh:46-49`) enables the hook (`batch-independent-looks.sh:37-41`; without it main
   hears nothing and silence proves nothing; judge r2, batch item 9): "with strictHooks on, main's first streak of 3
   single looks nudges"; "a second streak of 3 in the same session prints nothing" (fails on 3537ac2: it nudges
   again); "a new session's first streak still nudges" (the existing planner and Builder cases stay green).
   Catches: a nag that repeats every streak and fills main's context.
3. **Set-up or doctor says how to switch the reminders off.** `scripts/doctor.sh`, beside the main settings check
   (`:57-60`): warn when main's environment or `$PP_MAIN/.claude/settings.local.json` `env` sets
   `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`, naming the fix (remove it; main tracks work in the Orca task list), else one
   `ok` line saying main has no task-list reminders on Claude Code 2.1.268 or later unless its model is one the docs
   list, and then how (the documented switch). Only documented switches are named; the Builder cites the docs page
   in a one-line comment. Tests, `doctor-options.test.sh`: "with CLAUDE_CODE_ENABLE_TODO_TOOLS=1 in main's settings
   env the doctor warns and names the fix"; "without it the doctor prints the ok line". Catches: the owner paying
   the reminders on every turn without knowing the switch.
4. **The batch's two tests.** `scripts/__tests__/context-overhead.test.sh`:
   - "the scripted main session attaches less than at 3537ac2": the tip's total is below the base total, recorded
     in the test as a constant with the command that measured it (CI has no base worktree). Catches: a hook change
     that grows main's context.
   - "every Bash hook in hooks.json given a call with nothing to act on attaches 0 bytes" (looped over hooks.json, so
     a new Bash hook is covered). Catches: a new hook that talks on every call.
   - "each hook still prints when one applies": the existing block and warning cases in `hooks/__tests__/` of every
     hook edited run and pass; this test adds one per edited hook through `context-overhead.sh` (for
     `batch-independent-looks`, a first streak nudges). Catches: silencing a hook by breaking it.

## 3b. Issues 328 and 329: main's replies

**328 (port-by-commit, rule text only).** Port host 7f8c3564 (`.claude/main-session.md`, the bullet "A reply the
duplicate-agent guard blocks is never dropped") into `templates/main-session.md`, in the injected Working rules
(above `## Details (not injected)`), right after the bullet "Every question for the owner goes to the relay pane"
(`:26-28`), as the host places it after its question bullets. Text, without the host's ruling id: "**A reply the
duplicate-agent guard blocks is never dropped**: retry it after that seat's turn ends, or send it as an orchestration
reply, even when the seat's default already matches." The injected part is 3,395 bytes today, far under the
10,240-byte startup print (`hooks/agent-startup-context.sh:33`); the line's ~200 bytes count in 327's after-figure.
Test, `hooks/__tests__/agent-startup-context.test.sh` beside its `MS()` reader (`:23`): "main's startup print carries
the rule that a reply the duplicate-agent guard blocks is never dropped". Catches: the line landing under Details,
where no session loads it.

**329 (P1, port-by-commit of host 33cdf11c, "fix(answer-worker): answer a question with a reply to its id").** Today
`scripts/answer-worker.sh:92` answers a mid-turn pane with a new `orchestration send`. A Builder blocked in
`orchestration ask` returns only on a reply to its question's id, so it never sees that answer and sits until its
timeout. Host 33cdf11c fixed its `answer-worker.sh` this way: an optional third argument takes the question's id;
the mid-turn path calls `orchestration reply --id <id> --body "$MSG" --json` when it has one and `send` as before
when it does not; the way text becomes "sent to the pane's inbox as a reply to <id>"; and the turn-ended re-check
matches the way text by prefix (`[[ $WAY == "sent to the pane's inbox"* ]]`). Its `orca-wait.sh` hint passes the id.

Ported to `scripts/answer-worker.sh`, adapted where the plugin differs (no redesign):
- The plugin already takes a third argument, `Q` (`:29`), the decision id `<unit>-<msg id>` that `orca-wait.sh:348`
  records and its hints already print (`:345-346`), and `close_asks` (`:32-46`) uses it as it is. The reply id is
  the Orca id inside it: `case $Q in *msg_*) QID=msg_${Q##*msg_} ;; esac` (a bare `msg_…` works too). So
  `orca-wait.sh` needs no change, unlike the host's.
- The inbox path (`:90-93`, the `send` at `:92`) is the host's if/else: `reply --id "$QID"` with a `QID`, else today's `send`; the way
  text gains `${QID:+ as a reply to $QID}`, as the host's.
- Both checks of the way text become prefix matches: the turn-ended re-check (`:102`, as the host's) and the
  plugin's own "queued, not read yet" line (`:114`), which the host file does not have; left exact, a reply to a pane
  still mid-turn would exit 1 "NOT delivered" instead of 2 "queued".
- The header comment and the usage lines (`:2`, `:27-28`) say the third argument also picks the reply. The typed
  path for an idle pane, the tag delivery check, `close_asks` and `pp_close_items` stay as they are. The plugin's
  `templates/main-session.md` does not spell out `answer-worker.sh`'s arguments (the host's main-session.md did), so
  no template line changes; the plugin has no `main-watch.sh` comment to port.

Tests, `scripts/__tests__/answer-worker.test.sh`, the host's case adapted to the plugin's fixture (its fake
`orca-ide` case line at `:35` also records `orchestration reply`, as the host's test does, and its asked question is
`u1-msg_q1`, `:33`, `:47`):
- "a mid-turn pane given u1-msg_q1 gets orchestration reply --id msg_q1 with the answer, no orchestration send and
  no terminal send, and the answer is confirmed" (fails on 3537ac2: it sends). Catches: the answer a waiting ask
  never sees.
- "a mid-turn pane given no id is sent the answer as before, and the confirmation names no reply" (a green pin).
  Catches: the fallback lost, or a reply made with an empty id.
- "a reply to a pane still mid-turn after the wait exits 2, queued" (a green pin: 3537ac2 sends and exits 2; it
  guards the prefix match the port needs). Catches: a queued reply reported as not delivered, which main would re-send.
- The existing delivery, queued and close cases stay green.

Live check, in the evidence file, not a test (the issue's "Check before shipping"): from a scratch Orca terminal, an
`orca-ide orchestration ask --timeout-ms 60000`, then `answer-worker.sh` on it; the ask returns the answer within a
few seconds, and a reply sent after a timed-out ask is found by `ask --resume <id>`. Catches: a reply verb that
does not end a blocking ask, which no stub can show. If the live check fails, the Builder stops and asks main
before shipping 329. The issue's lower-priority guard notes (`no-poll-loops.sh`, `duplicate-agent-guard.sh` wording)
are not in the batch brief's 329 bullet and are not built.

## 4. Build order

Each group's tests are green before the next starts. Commit per group. Four groups (the plan-author cap is four
cuts).

- **G1 alert, 293, 327, 328, 329 and the coverage pins** (checkpoint-rejected with the `dashboard-alerts.test.sh:47`
  rule count and the `dashboard-main-events.test.sh:33` list updates, the two 293 pins, section 3 in its order, the 328
  rule line, the 329 reply, the limit-history, two-project cost and inbox pins). Small, separate files. Catches:
  the new alert id, each hook change and the answer path break no existing case except the two assertions this plan
  names.
- **G2 units and seats** (the `worktree` field, the launch roster, parked, stop notes, merged since push, finished
  builds without a cap, last merge, the two seat cards with their weeks, main's 7-day average and account, seat weeks
  in the role totals, Builder share). `dashboard.sh` `units()`/`main_chain`/`tests_panel`, `builder-codex-pass.sh`
  (the `codex-start` row), `dashboard_builders.jq`, `dashboard_limit.py seats`/`tests`, `app.js`, `index.html`; the
  `dashboard-built-seats.test.sh:30-32` average changes here. Catches: a units-row field one reader expects and
  another does not get, and a `codex-start` reader (`dashboard_builders.jq`, `rg codex-start scripts`) that breaks
  on the two new keys.
- **G3 needs owner and GitHub** (P1 list and strip count, proposed-decision list, PR tally, issue limit, by
  priority). Catches: a `githubP1` reader left on the old number.
- **G4 the riskiest: server and collector** (`/p/<name>/` redirect, parallel parts).
  - Risk, redirect: a new GET route on a server that may listen on the LAN. Wrong, it serves a page without a
    login, or its `Location` is built from the request and points off the page. Tests: `dashboard-serve.test.sh`
    "on a LAN bind with no login, GET /p/<name>/ is 302 to /login, never the page" (a regression pin: `gate()`
    already answers it, so it passes today); the redirect and 404 cases in the table. Catches: a route placed
    before `gate()` or `foreign()`.
  - Risk, parallel parts: two parts writing one file in `$RUN` at once, a backgrounded failure lost, or the
    subagent ledger appended without its lock. Tests: the four in "Parallel parts: scheduling".
  - No group migrates seen-alert keys (the new alert id is a new key, seen once). The one shared-ledger writer on a
    changed path is `subagent-usage.sh` under `measures()`, which keeps its lock (`subagent-usage.sh:40`); the
    decision and unit ledgers are read only here.
- **Close-out:** `docs/dashboard.md` (the new cards, the `/p/` redirect),
  `docs/configuration.md` or the doctor docs (the task-reminder line), version and CHANGELOG,
  `bash ci/leak-test.sh`, the host comparison (Done when) recorded in the evidence file, then the final pass.
  Catches: a parity row that passes its fixture but still differs on the host's live dashboard.

## 5. Size (changed lines, code + tests)

| Group | Code | Tests |
|---|---|---|
| G1 | ~155 | ~185 |
| G2 | ~305 | ~255 |
| G3 | ~115 | ~115 |
| G4 | ~40 | ~85 |
| Close-out | ~30 | 0 |
| **Total** | **~645** | **~640** |

Round 2 adds the launch roster (~35 code, ~40 tests), the average and account (~7, ~10), the 293 and lock pins
(~25 tests), and takes ~5 code off 329 (the host's shape, no id inference). About 1,285 lines in about 35 files: under the plan-author cap (`review-limits.diffLines` 3000, 40 files, four
cuts). No split. A "build it" answer to Q5 or Q7 adds its estimate below.

## 6. Established practice for the security-relevant changes

- **The `/p/<name>/` route (LAN bind).** OWASP Unvalidated Redirects and Forwards Cheat Sheet: never build a
  `Location` from request input; map it through an allow-list. The name must be a registered project (the names the
  server already resolves for layouts), and the `Location` is relative (`../../index.html?project=` plus the
  encoded name). OWASP Authentication: every route behind the login: the route sits after `gate()` and `foreign()`
  in `do_GET`, like every page. The plan follows both.
- **Shared ledger writes.** The plan adds no ledger writer. One existing writer runs on a changed path:
  `measures()` (`dashboard.sh:635`) runs `subagent-usage.sh`, which appends to `subagent-usage.jsonl` under
  `flock` (`scripts/subagent-usage.sh:40`); backgrounding `measures` keeps that lock as it is, pinned by the
  lock test above. The other practice the plugin already uses (`decision.sh` appends one JSON line under its lock;
  `unit-ledger.sh` appends once per merge) is untouched. The `codex-start` row is the pass's own event log, one
  writer per worktree.
- **Parallel collection.** Each backgrounded part writes only its own `$RUN` files, and each cache file is replaced
  by `mv -f` or `os.replace` of a temp file (the host's and the plugin's existing practice); part seconds are short
  appends. The parts that share the request caches stay sequential. The Builder greps each backgrounded part for a
  write outside its own files.
- **Hook state (327).** The once-per-session mark lives in the hook's existing per-session state file, written as
  today; it records no command text.

## 7. Catches

- Checkpoint-rejected alert. Catches: a main whose items were carried but which never restarted, which today raises
  nothing. Test: `dashboard-main-events.test.sh` "a carried checkpoint with no restart for 121 s raises
  checkpoint-rejected; a restart after it ends it; 119 s raises nothing".
- 329 reply. Catches: a Builder blocked on its ask until the timeout though main answered. Test:
  `answer-worker.test.sh` "a mid-turn Builder with open question u-msg_abc123 named is answered by orchestration
  reply --id msg_abc123 ... and no orchestration send is made".
- Nag once per session. Catches: the same advice re-attached every turn. Test:
  `batch-independent-looks.test.sh` "a second streak of 3 single looks in one session prints nothing".
- Silent Bash hooks. Catches: a hook that prints on a call with nothing to act on. Test:
  `context-overhead.test.sh` "every Bash hook in hooks.json given a call with nothing to act on attaches 0 bytes".
- Unit launch roster. Catches: a round-2 card that shows no model or effort for the reviewer now running, or one
  that still shows round 1's. Test: `dashboard-built.test.sh` "a unit in round 2 ... publishes seats [builder
  sonnet high, codex-reviewer gpt-6.1-sol medium]: the round-1 pass is not listed".
- Main-seat average. Catches: today's spend inside the average it is compared with. Test:
  `dashboard-built-seats.test.sh` main's card case, `0.0014` from $0.01 three days ago and $0.01 today.
- Main card account. Catches: main's card not naming the account it bills. Test: `dashboard-view.test.mjs` "a
  populated main seat with limit.accountLabel ... shows Account".
- Background failure. Catches: a backgrounded `guardBlocks` failure that `wait` never reports. Test:
  `dashboard-built.test.sh` "a guardBlocks part that fails still fails the collect and keeps the last data.js",
  with the inconsistent state file as its input.
- Subagent ledger lock. Catches: a parallel `measures` writing a run twice. Test: `dashboard-built.test.sh` "a
  backgrounded measures still takes the subagent ledger's lock".
- 293 precedence. Catches: a launch pin that loses to the `/plugin` key or a stale project effort. Test:
  `seat.test.sh` "/config builderEffort medium, the project's file saying low, and a launch pin --effort high".
- Host comparison at close-out. Catches: a row the fixtures pass that the registered host's live dashboard still
  shows and the plugin's does not. Check: the row-by-row comparison in "Done when".
- The redirect adds no check step.

## 8. Version and CHANGELOG

0.41.0, the next free minor (main is 0.40.0; no branch or plan claims 0.41.0, 2026-10-23); if a sibling merges
first, the next free minor at merge time. `.claude-plugin/plugin.json:3`, the README badge and every file
`ci/version-check.sh` reads; one CHANGELOG section naming issue 292's rows built, issue 293's pin, issue 327's
changes with the measured before and after, issue 328's rule line and issue 329's reply. The CHANGELOG names no issue as closed.

## Known gaps (not merge blockers)

- The Units card's parked rows come from seat records whose Orca task is open: a unit killed with its task closed
  and its worktree gone leaves no row, as the plugin has no other record of it.
- `rebuildUsd` is the first turn's list price after a restart, an estimate of the rebuild, as the host's.
- The issue read is limited to 1,000 open issues, as the host's: a project with 1,001 open issues has one left out
  of the milestone and priority counts (the issue's own comparison was 538).
- `limit` stays sequential after `projects`: it needs the whole project inventory and the shared request cache, so
  only `measures` and `guardBlocks` overlap.
- The launch roster lists the Builder's latest launch and each review pass kind's newest start in the highest round.
  A pass row written before this change has no model or effort, so a unit mid-build at the upgrade shows "model not
  recorded" for its reviewer until its next pass. A Builder relaunched by hand outside `seat.sh` has no record and no
  row, as in the planning line.
- `guard_blocks` exits 1 on a stored state whose block names a session not in its `sessions` (the input the
  background-failure test uses), and rewrites that state before it fails, so the part fails on every collect until
  the state file is removed. The hook writes consistent states; only a hand-edited or foreign state gets there.
  Found while choosing the test input; not changed here (the test needs it to fail).
- The 327 measurement replays a scripted session through the plugin's hooks; the harness's own attachments (skill
  listing, instructions, task reminders) are named by the doctor line, not measured by it.

## Questions for the owner

Q1-Q3 and the host-load question (Q8 in round 1) are answered: the owner's answers are under "Main answers" at the
top, and the plan builds them. They were not dropped. Q5-Q7 are still open with the owner. Main asks them once,
before the build starts. The plan builds each recommendation; each question says what changes if the owner picks
the other answer. Nothing else is dropped without the owner's yes.

- **Q5. Tests row: queued files and failures under load.** The host's Tests row shows files still queued
  (`host:.claude/scripts/dashboard.sh:1303`) and tests that failed above the core count and passed after load fell
  (`:1304`). Both come from the host's shell-test runner writing a live file per run and a ledger row per test file
  with the load (`host:.claude/scripts/dashboard_limit.py:740-796` `test_ledger`). The plugin's
  `scripts/run-shell-tests.sh` writes no such record, and it runs only the plugin's own tests: a user project's
  test runner would write none either. Builder share needs no ledger and is built (G2).
  Recommendation: skip the two. Skip costs: the plugin's Tests row cannot show a queue or a load-caused failure;
  0 lines. Build costs: `run-shell-tests.sh` writes the live file and ledger rows, a port of `test_ledger`, the
  `tests_panel` join and the card (~180 code, ~120 tests in G2), and it shows figures only for projects that run
  the plugin's runner.
  If the owner picks build: G2 adds `run-shell-tests.sh` live and ledger writes, the `test_ledger` port in
  `dashboard_limit.py tests`, `queued` and `failedUnderLoad` through `tests_panel`, and their Tests-card lines, with
  tests "a run with 3 files left publishes queued 3" and "a file that failed at load over the core count and passed
  later is listed"; Known gaps gains "a project not on the plugin's runner shows neither"; size +~300.
- **Q6. Main's and the relay's weeks in the role totals.** The host adds both seats' weeks to the role totals
  (`host:.claude/dashboard/app.js:1531`); the plugin's role totals take the seat-event ledger only, so main and the
  relay, which write no seat-event row, have no role row. Recommendation: build (planned in G2). Build costs ~25
  code and ~30 tests on the seat reader the plan already extends. Skip costs 0 lines; the role totals leave out
  main's and the relay's own spend, the two seats the owner pays for every day.
  If the owner picks skip: the "Seat weeks in the role totals" row becomes skipped, its `renderCost` change and
  view test are dropped from G2 (the seat `week` figures stay: the seat cards use them); size -~55.
- **Q7. Per-project pages: a redirect, not their own data files.** The host's `/p/<name>/` serves a page that reads
  `/p/<name>/data.js`, that project's own data file. The plan serves `/p/<name>/` as a redirect to
  `index.html?project=<name>`, which reads the one `data.js` with every project. `GET /p/demo/data.js` is then 404.
  Recommendation: skip the per-project data files. Skip costs: a bookmark or script that fetches
  `/p/<name>/data.js` itself stops working at the switch; no plugin reader uses one, and the page links still land.
  Build costs: the collector writes `p/<name>/data.js` for each project every collect (each project's slice, the
  same validation and atomic rename) and the server serves them behind the same gate (~60 code, ~45 tests in G4,
  and a second publication per project each cycle).
  If the owner picks build: G4 puts those writes in `render()`, and the server serves `/p/<name>/` (the page) and
  `/p/<name>/data.js` behind `gate()` and `foreign()` with the same registered-name match instead of the redirect; the redirect tests become
  "GET /p/demo/data.js after login is that project's slice" and the same 404 cases; size +~105.

## Files edited

`scripts/dashboard_alerts.jq` (beside `host-swap`, the mainEvents rule); `scripts/dashboard_limit.py` (main-events
carried rows ~1469; seats ~1319-1355, the average's window; tests `builderShare`); `scripts/builder-codex-pass.sh`
(~996, the `codex-start` row's model and effort); `scripts/dashboard_builders.jq` (`passes`); `scripts/dashboard.sh`
(`plan_seats` ~180-189, its command parse shared; `units()` ~280, ~380 and ~395-432,
`finished_builds` ~437-448, `github_p1` ~487, `gh_issues` ~523, `github_panes` ~539-561, `main_chain` ~584,
`tests_panel` ~906-929, `project()` ~1034-1037); `scripts/dashboard_serve.py` (`do_GET` ~669);
`dashboard/app.js` (unit card ~477-582, units list ~588, `renderNeeds` ~245-300, PR list ~908, issues card,
`renderSeat` ~1094 and its call ~1644, `renderCost` ~1144, Tests card, main card, strip ~1582, the launched-as line
~466); `dashboard/index.html` (parked, merged
since push, `prs-tally`); `dashboard/app.css` (if the new blocks need it); `hooks/batch-independent-looks.sh` (and any
Bash hook the 327 measurement shows talking on a no-op call); `scripts/doctor.sh` (~57); new
`scripts/context-overhead.sh`; `templates/main-session.md` (~28); `scripts/answer-worker.sh` (~2, ~27-29, ~90-93,
~102, ~114); `docs/dashboard.md`; `docs/configuration.md`; `.claude-plugin/plugin.json` 3;
`README.md` badge; `CHANGELOG.md` top. Tests: `scripts/__tests__/dashboard-alerts.test.sh`,
`dashboard-main-events.test.sh`, `dashboard-built.test.sh`, `dashboard-built-seats.test.sh`,
`dashboard-tests-panel.test.sh`, `dashboard-billing.test.sh`, `dashboard-github.test.sh`, `dashboard-serve.test.sh`,
`dashboard-view.test.mjs`, `builder-codex-pass.test.sh`, `seat.test.sh`, `seat-launch.test.sh` (cleanup only), `doctor-options.test.sh`, new
`context-overhead.test.sh`, `answer-worker.test.sh`; `hooks/__tests__/batch-independent-looks.test.sh`,
`agent-startup-context.test.sh`. A "build it" answer adds the files
its build names.

## Done when

- [ ] Main has the owner's answer to Q5-Q7 before the build starts (Q1-Q3 and host-load are answered, "Main
      answers"); each answer other than the recommendation is in its group, as its question says.
- [ ] Red-first: every "build" row's named test exists, failed on 3537ac2 first, and passes at the tip, the launch
      roster, main's average and main's account included. The evidence file records each red run.
- [ ] Green pins pass on 3537ac2 and at the tip, and the evidence file lists them apart from the red-first cases:
      the unauthenticated `/p/<name>/` redirect gate; the empty and no-session results ("no Builder session today
      gives null", "a seat with no session this week adds none", "a null label shows no Account fact"); the parallel
      collect's normalized equality; the failing `guardBlocks` part keeping the last data.js; the subagent-ledger
      lock; the limit-history, two-project cost and inbox pins; both 293 pins; the 329 no-id and queued-reply cases.
      A pin that fails on 3537ac2 is a defect found, fixed in the code, not in the pin.
- [ ] The three existing assertions this plan changes (`dashboard-alerts.test.sh:47`, the rule count, 15 to 16 as
      its all-rules fixture gains a carried checkpoint; `dashboard-main-events.test.sh:33`; the main-seat average at
      `dashboard-built-seats.test.sh:30-32`, to the host's window) are updated, the host-load no-alert case at
      `dashboard-alerts.test.sh:15` is unchanged, and no other existing case changes.
- [ ] Issue 293's two pins pass through the real `seat.sh` launch line; no project-file read of the Builder's model or
      effort is added, and issue 312's tests are unchanged.
- [ ] Issue 328's line is in the injected part of `templates/main-session.md`, with no ruling id.
- [ ] Issue 329: `answer-worker.test.sh` passes, and the live check is in the evidence file.
- [ ] Issue 327: the before and after measurements are in the evidence file, and `context-overhead.test.sh` passes.
- [ ] Changed-file tests and the test files of every edited script pass; no skipped case.
- [ ] The evidence file names the host commit per built row (the two the plan leaves to `git log -S`).
- [ ] Host comparison (issue 292's second gap check; judge r2 finding 5): with the host project registered in the
      plugin's dashboard, its page is compared row by row with the host's own running dashboard: every row of
      section 1's tables, LAN login from a second device, and one valid answer sent from a phone on the LAN through
      the login. The evidence file records each row as same, or as different with the owner's answer or waiver that
      allows it (host-only rows, the 5 stages, `.projects`, host-load, waived rows, and Q5-Q7 as answered). A
      difference with no owner answer is a gap: it is built, or main asks the owner, before the final pass.
- [ ] `bash ci/leak-test.sh` passes.
- [ ] Version 0.41.0 (or the next free minor) and the CHANGELOG section are in.
- [ ] A closing (final) pass ends `VERDICT: GO`.

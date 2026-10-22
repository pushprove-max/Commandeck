# dashboard-parity-2026-10-21 -- the dashboard issues: parity with the host project's panels, and the 0.22.0 leftovers

Order: the owner, 2026-10-20, kept on 2026-10-21: "after those merge, build ALL open Commandeck plugin issues,
batched as main sees fit". The ruling ids are in the brief: their form is a leak word here. Main split the open issues into three units built
side by side; this is the dashboard one. Scope: 19 issues, 217, 224, 240, 242, 263, 269-274, 276, 277, 280, 291,
292, 294, 295 and 299. Four are already met (item 0) and main closes them. Issue 226 is on hold and not planned.
This build is items 1-13. Items 14 and 15 (issues 269 and 263) are the second unit, built from this plan right
after this one merges (owner answer 2). The plugin adds no second-machine support anywhere (owner answer 4).

Launch: new unit dashboard-parity-2026-10-21
Order: "after those merge, build ALL open Commandeck plugin issues, batched as main sees fit"

Base: main 97382ff (0.22.0).

Public repo: no personal names, handles, pane names (other than the existing seat folder name `Chief-of-Staff`) or
user paths in any shipped file, comment, test, commit message or changelog line. Outside CHANGELOG.md an issue
number is written "issue N", and the host project's numbers are written "host issue N". No host file path is
written anywhere: a ported change is named by its host commit and its function names only. Commit titles are
plain. Test fixtures use dates before 2000 for ruling ids.

Skill for the build: `mattpocock-skills:tdd`. Every item with logic is red first. Item 13 is speed work: its red
tests count reads, and the commit body records the cycle time and process count before and after.

Port by commit (owner ruling, 2026-10-20): a PORT item ports the named host commit's change, read with
`git show <sha>` in the host checkout. It is not redesigned. Where the plugin's code differs, the item says how.

## Done when

- `bash scripts/run-shell-tests.sh` (the whole suite, not `--changed`) is green on the tip before the final
  review. The Builder records the tip, the time taken and the totals in the brief's evidence. It passes once more
  with jq 1.7 first on `PATH` (CONTRIBUTING.md).
- `dashboard-view.test.sh` runs and is not skipped. `COMMANDECK_TEST_NODE_MODULES` names a node_modules folder that
  has jsdom, and the brief names that folder. Items 1, 5 and 7-12 change the page.
- `claude plugin validate .`, `bash ci/leak-test.sh`, `bash ci/version-check.sh main` and
  `bash scripts/startup-size.sh` pass.
- No install, uninstall or whole-setup run, and no end-to-end test (owner ruling 2026-10-16). The tests drive
  functions and scripts on scratch HOMEs, as they do today. No test starts the real collector service; item 7's
  restart command is a stub.
- Each item below meets its own "Done" line, built as the owner answers below say.

## Owner answers

1. Issue 292: this unit builds the switch breakers (item 2) and the rows its own issues cover; the rest of 292 is a second plan, one row per host commit, written after this unit merges.
2. Size: this unit builds items 1-13; items 14 and 15 (issues 269 and 263) are a second unit, built from this plan right after this one merges.
3. Issue 263: the login is on only when the bind is not loopback, and off on a loopback bind, as today.
4. No second-machine (peer host) support anywhere in the plugin: issue 269 has no peer lane, and no peer row of issue 292 is built. The owner also closed sibling issues 296 and 297 as won't do.
5. Issues 271 and 272: port the host's unit-ledger writer into the plugin's merge, and both panels read it. Escapes reach that ledger through the host's escape tagger, ported to append to it (main, under the same ruling).
6. The plugin never writes the host's personal-name decisions key; the host's relay watchers read `needsOwner.decisions` after the switch, a host-side change.
7. Alert ids: seed once. `cos-watch-alerts.sh --seed` adds every alert id open now to the seen file, the switch steps run it once, and ids stay as they are.

## Item 0. Close as shipped (main closes these; no build)

Each was checked on main 97382ff against its issue's own "done when".

| Issue | Shipped in | Evidence |
|---|---|---|
| 217 | 0.21.0 (c4ece92) | `dashboard/app.js:1767-1770` merges `collapsed` and `hidden` three-way; test `dashboard-view.test.mjs:764` "issue 217: two pages folding at once keep both folds, and an unfold removes only that one" |
| 242 | 0.21.0 (c4ece92) | `scripts/dashboard_limit.py:1047-1048` splits one plan-and-build worktree by the first stage's start; test `dashboard-built.test.sh:194-201` "one worktree as plan and build: each request on its own stage, the total unchanged" |
| 224 | 0.22.0 (9fb00ef) | `dashboard_limit.py seats` (`:1070`); cards `dashboard/app.js:959-970` (context and line, today, 7-day average, restarts with the average gap, the restart times as the timeline); tests `dashboard-view.test.mjs:790`, `dashboard-built.test.sh:307` |
| 240 | 0.22.0 (9fb00ef) | `scripts/dashboard_serve.py:30-42`, `do_POST` `:408-440` (loopback client, Host and Origin; first answer wins); options in `decision.sh add --options`; page `dashboard/app.js:172-214`; tests `dashboard-serve.test.sh:259` "another machine's POST and another site's are refused; the first loopback answer is taken, a second is refused", `dashboard-view.test.mjs:811`, `:835`, `:861` |

What 240 left open is filed apart and built here: issues 276, 277 and 295.

## Host commits, verified by their diffs

The brief's table rests on commit titles for most rows. Each was read:

- **224 and 240** (shipped): 6abe413f and 77d16f1d change hooks and guards, no dashboard file. 0a587d27 is the Tests
  panel's numbers (host issue 2928), not the answer panel. Nothing to port.
- **263:** 3f19f6a9 is only a follow-up (a password change keeps trusted devices). The login itself is b257a08f
  ("Cut 4"), and 62121446 lowers the minimum password to 8 characters, as issue 263 asks. Item 15 (second unit)
  ports all three.
- **269:** the panel is 26a2b168 (host issue 2868). 0a587d27 (host issue 2928, confirmed by its batch title) adds
  queued counts, red-proof progress and live pass/fail; issue 269's acceptance does not need them, so they are not
  ported. c032363b's second-machine runs are not ported (owner answer 4).
- **280:** 814aa1d6 and aa4cf9de, confirmed (host issue 2969 is named in aa4cf9de's evidence).
- **291:** be750b23 is the fix. e18f3512 carries the issue's "every other read" part (`.claude.json` and
  `settings.json` under the config folder). 7960cc6a names host issue 2989 in its body but changes no config-folder
  read; nothing in it is ported.
- **294:** 46e2e059, confirmed (it closes host issue 2990).
- **299:** c032363b, its "Cut 2", confirmed (host issue 2996). Its parts 2c (push-record verification cache) and 2e
  (compaction events) have no plugin twin: the plugin's collector has neither reader.
- **270-273** are NO-HOST in the brief, but the host has each panel: collector functions `cost_unit`, `review`,
  `escapes` and `issues` (906f6323) and the page's `renderReview` and `spark` (1338872d). Items 8-11 port them, as
  the port-by-commit rule asks.
- **271 and 272, the ledger** (owner answer 5): the host's unit-ledger writer, as of c0e61f13 (first 82de37e7, 669
  lines), joins a merged unit's rounds, GO and NO-GO counts, seats, tokens and merge rule into one JSON line per
  unit, and the host's merge appends it. It holds no escapes: the host tags those after the merge with its escape
  tagger (6483ea4a, 33 lines), into a review-class ledger the plugin does not have. Item 9 ports the writer and
  its call from the merge; item 10 ports the tagger to append to the unit ledger instead.
- **274** is NO-HOST. The host's resolved list (95ae4524) resolves only main's compaction alerts on a restart;
  issue 274 asks for every alert that clears. Item 12 builds it from the issue.

## Priority

- **P1, issue 295 (item 1).** An answer that main never got is the owner's order lost, and the page says only
  "sent again on each refresh", forever.
- **P1, issue 292 (item 2, with item 3).** The host cannot move to the plugin's collector until the switch
  breakers are fixed. Item 3 (issue 280, P2) is one of those breakers, so it goes with item 2.
- **P2:** issues 291 (item 4), 276 (5), 277 (6), 294 (7) and 299 (13). Item 13 goes after the panels because it
  changes the readers they add rows to.
- **P3:** issues 270-274 (items 8-12).
- **Second unit, not this build** (owner answer 2): issues 269 (item 14) and 263 (item 15), P3. Item 15 goes last
  there: it moves every server test to HTTPS, including the ones items 1 and 7 add.

## Item 1. Issue 295 (P1): an undeliverable answer says why, gives up, and can be cleared

NO-HOST.

- **Cause, read:** `scripts/dashboard_serve.py` `deliver()` (`:203-213`) returns only delivered or not. The exit
  code and stderr are dropped. `retry` (`:301`) sends every kept entry again on each read of `data.js` (`resend`,
  `:327`), with no count and no end. The collector lists each kept entry as `{id, to}` (`scripts/dashboard.sh:427`),
  and the page prints one fixed line (`dashboard/app.js:259-260`).
- **Change:**
  - `deliver()` also returns the script's exit code and its last stderr line (200 characters at most). Each kept
    entry gains `tries`, `firstAt`, `lastExit` and `lastError`, written by `settle()`.
  - An entry gives up (`state: "gave-up"`, with `reason`) 1 hour after its first try (an assumption: the same hour
    as the question alert, `dashboard_alerts.jq:57`). It gives up at once when its `main` folder is gone, or is
    not a project in `data.js`, with that reason. A gave-up entry is never retried by a refresh.
  - Exits 0 and 3 still clear an entry, as today.
  - `POST /unsent {key, action}`, behind the same gate as `/answer` (loopback now; item 15, in the second unit,
    adds the login):
    - `retry`: back to pending, `tries` reset, sent at once.
    - `delivered`: removed, after the page asks the owner to confirm main got it another way.
    - `drop`: removed, after a confirm.
    - Each action appends one line to `<directory>/answer-retry.log`: time, key, decision id, action, client.
  - The collector passes `key`, `state`, `reason`, `tries`, `firstAt` and `lastError`. The page's note reads
    "not sent to main: <reason>, N tries since <time>", with the three buttons on a loopback page.
  - `dashboard_alerts.jq`: an `answer-<id>` critical alert for each gave-up entry, and for each entry failing for
    10 minutes or more.
- **Red first:**
  - `scripts/__tests__/dashboard-serve.test.sh`, with a stub `to-main.sh` that exits 1 with a stderr line: the
    kept entry has the exit, the line and the count; past the hour (a stamped `firstAt`) it is gave-up and no
    longer sent; a `main` folder that is gone gives up at the first try; each action changes `answer-retry.json`
    as stated and logs one line; a non-loopback POST to `/unsent` is refused; exits 0 and 3 still clear (pins).
  - `dashboard-alerts.test.sh`: a gave-up entry raises the alert.
  - `dashboard-view.test.mjs`: the note shows the reason and count; the buttons show on a loopback page only.
- **Done:** those pass. **Size:** about 120 code lines and 120 test lines.

## Item 2. Issue 292 (P1): the switch breakers

Built as owner answer 1: the breakers, and the rows this unit's own issues cover. Item 3 is the `--slurpfile`
breaker.

- **Already met:** a fixed port and a LAN bind. `COMMANDECK_DASHBOARD_PORT` and `COMMANDECK_DASHBOARD_BIND`
  (`scripts/dashboard.sh:25-26`, `:48-49`), kept in the service's environment (`:963`) and set by setup.
- **Change:**
  - **Scratch path.** The service keeps `COMMANDECK_SCRATCH` and `COMMANDECK_WORKSPACES` when they are set at
    install, for the home project only. The `keep` list at `dashboard.sh:963` gains both. A registered project
    still derives its own (`:872` unsets them for it).
  - **`decision.sh --options`.** It also takes a JSON array (`["a","b"]`), the host's form, with the same rules
    (2 to 4 answers, each printable, none the decoy). A value that starts with `[` is read as JSON; anything else
    keeps the `a|b` form. The ledger shape does not change. `push-ask` is issue 259's (sibling unit).
  - **Carry-over.** `dashboard.sh --import <folder>` merges in the 7-day limit history, the saved layout and the
    cleared-builds log found in `<folder>` under the plugin's own file names, and prints what it took. It never
    replaces a newer entry. The Builder first compares the host's readers of those three files (host HEAD) with
    the plugin's, and lists any field that differs.
  - **Home project.** `register` (`dashboard.sh:912`) adds the home project first when it creates the registry.
    An explicit `--unregister` of home still turns it off, as the comment at `:858` says.
  - **Alert ids** (owner answer 7, seed once): `scripts/cos-watch-alerts.sh --seed` appends every alert id open now
    to the seen file and exits.
  - **Relay key** (owner answer 6): no change in the plugin. It never writes the host's decisions key.
- **Red first:**
  - `scripts/__tests__/dashboard-loop.test.sh` (or the file that drives `install` with `--job-file`): the job file
    keeps `COMMANDECK_SCRATCH` when it is set.
  - `decision.test.sh`: `--options '["a","b"]'` stores the same row as `--options 'a|b'`; a 5-item array and the
    decoy are refused.
  - `dashboard-built.test.sh`: `--import` of a fixture folder adds history rows and cleared builds, and keeps a
    newer layout; registering a first project keeps home collected.
  - `cos-tell.test.sh` (it drives the watchers): `--seed` then a poll prints nothing for the seeded alerts.
- **Done:** those pass. **Size:** about 70 code lines and 70 test lines.

Issue 292's other rows, for the second plan (owner answer 1). Its second-machine rows (the second machine's test
lanes) are not built anywhere (owner answer 4).

| Row (issue 292's words) | Here |
|---|---|
| Alerts "resolved" drawer | item 12 (issue 274) |
| Tests running now | item 14 (issue 269), second unit; this machine only (owner answer 4) |
| Tokens per unit, 7 days; Review loop, 7 days; Review escapes | items 8-10 |
| Issues card (7-day opened/closed sparkline) | item 11; its "by priority" part, second plan |
| Collector speed | item 13; the parallel slow groups and the slow-cycle log, second plan |
| Server transport and login; one-click answer from a LAN device after login | item 15 (owner answer 3), second unit |
| LAN serving / port | already met (above) |
| `--slurpfile` for ledgers | item 3 |
| `decision.sh` drift | above; `push-ask` rows are issue 259 |
| Page title, project bar and per-project pages, `.projects` meaning, standup link, phone tab bar, summary strip | second plan |
| Alerts: host load, deploys, main compactions, stage, Builder kind, Builder cache, question, guard spike, id stamps | second plan (deploy alerts host-only) |
| Units: board stages, driver badge, last marker, worktree, seats, main's asks, Builder cap, finished builds, parked list, merged since push | second plan |
| Main's seat card fields, the Chief of Staff card's hourly and side runs | second plan |
| Needs owner: P1 list, proposed decisions | second plan |
| Main and chain, open PRs with tally, issues by milestone, next push verdict | second plan (push-record verification host-only) |
| 7-day limit card, cost today for the whole machine | second plan |
| Deploys card | second plan (host-only) |
| Relay inbox, `measures` extras, `mainEvents`, source records | second plan |
| The host's launchd job and data file | retired at the switch; nothing to port |

## Item 3. Issue 280 (P2, a 292 breaker): ledgers and caches reach jq as files

PORT of 814aa1d6 and aa4cf9de.

- **Cause, read:** a value read from a file that grows without a bound is passed on jq's command line. Over the
  argument limit (1 MB on macOS) jq fails with "Argument list too long" on every cycle. In the plugin:
  - `scripts/main-watch.sh` `heads_up_capture`: the heads-up ledger (`--argjson led`, `:894`) and the done file
    (`--arg done "$(cat ...)"`, `:894`, `:921`).
  - `scripts/dashboard.sh`: the kept unit costs and the cost merge (`:385`, `:387`), the decisions list (`:430`),
    the alert starts (`--argjson prev`, `:811`), and the others the Builder finds.
- **Change:** the host's form at each site: `--slurpfile x <(printf '%s' "$v")` (or `--rawfile` for text, or the
  file itself), then `$x[0] as $v` inside the program. `dashboard_alerts.jq` reads `$preva[0]` as the host's does.
  The Builder lists every `--arg`/`--argjson` site in `scripts/*.sh` (`rg -n -- '--arg(json)? [a-z_]+ "\$'`),
  and marks each one converted, or bounded with its reason (a count, a timestamp, a capped list). The list goes in
  the commit body.
- **Red first:**
  - `scripts/__tests__/main-watch-wake.test.sh` (or the main-watch file that drives heads-up capture): a heads-up
    ledger and a done file each over 1 MB; one `--once` tick completes and captures a new offer.
  - `dashboard-built.test.sh`: a kept unit-cost file over 1 MB; one collect completes and keeps every unit.
- **Done:** those pass, and every site in the list is converted or has its reason. **Size:** about 60 code lines
  and 50 test lines.

## Item 4. Issue 291 (P2): Claude's files are read from CLAUDE_CONFIG_DIR

PORT of be750b23 (the session lookup) and e18f3512 (`.claude.json` and `settings.json`).

- **Cause, read:** `scripts/read-verdict.sh:347` reads `$HOME/.claude/sessions/<pid>.json`. Under a profile
  (`CLAUDE_CONFIG_DIR` set), Claude Code writes those files under that folder, so no Claude seat gets a `session=`
  and the dashboard shows it "not measured". The same assumption is in every read of a folder Claude Code owns.
- **Change:**
  - `scripts/paths.sh`: `pp_claude_dir` prints `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`. Each read below uses it:
    - sessions: `read-verdict.sh:347`;
    - transcripts (`projects/`): `read-verdict.sh:245`, `:668`; `main-watch.sh:546`; `paths.sh:138`
      (`pp_session_log`); `hooks/resume-context.sh:106`; `subagent-usage.sh:18`;
      `skills/worktreereview/scripts/collect.py:588` (`os.environ.get('CLAUDE_CONFIG_DIR')` there);
    - settings: `hooks/opus-orchestrator-autonomy.sh:44`, `hooks/agent-startup-context.sh:70`;
    - plugins and skills: `main-watch.sh:859`, `builder-codex-pass.sh:88`, `hooks/ruling-log.sh:43`, `:46`;
    - `.claude.json`: `seat.sh:256` and its message at `:258` read `${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json`, as
      e18f3512 does.
  - The collector runs as a service with no pane's environment. It already reads main's recorded config folder
    for the limit (`dashboard.sh:750`). Its transcript reads (`:377`, `:679`, `:699`, `:754`, `:759`, `:790`) use
    the same folder. A seat run under another profile than main's is a known limit:
    `shortcut: one config folder per collect (main's); read each seat's own when seats run under mixed profiles`.
  - Folders the plugin owns stay under `$HOME/.claude` (`checkpoints/`, `rulings/`, `hook-fire-log/`): every
    pane must find them whatever its profile.
- **Red first:**
  - `read-verdict.test.sh`: the pane-sessions case with `CLAUDE_CONFIG_DIR` set to a profile folder that holds
    `sessions/<pid>.json` finds the session; with it unset, `$HOME/.claude` is read (as be750b23's test).
  - `seat.test.sh`: a profile's `.claude.json` that disables a needed server refuses the launch; the default
    file is not read then.
  - `plugin.test.sh`: no script or hook names `$HOME/.claude/` followed by `projects`, `sessions`, `plugins`,
    `skills`, `commands` or `settings.json`, or `$HOME/.claude.json`, outside `pp_claude_dir` and the tests. This
    holds the rule for new code.
  - Existing tests that fake HOME run with `CLAUDE_CONFIG_DIR` unset (`run-shell-tests.sh:55` already unsets it).
- **Done:** those pass. **Size:** about 40 code lines and 70 test lines.

## Item 5. Issue 276 (P2): a focused answer form hides nothing else

NO-HOST.

- **Cause, read:** `dashboard/app.js:247-249`. While focus is in any answer box, `renderNeeds` skips the whole
  `put` of `#decisions`, so new decisions, unsent notes and picker notes stay hidden.
- **Change:** each decision row carries `data-asking` (`asking(d)`). When an answer box has focus, the list is
  rebuilt as usual, and the row whose `data-asking` matches the focused one is put back as the same node, so its
  typing and focus stay. If that decision has left the open list, the list is rebuilt whole.
- **Red first,** `dashboard-view.test.mjs`: focus the Other box of decision A and type; a refresh adds decision B
  and an unsent note. Both show, A's box keeps its text and its focus, and the box is the same node.
- **Done:** that passes, and the existing issue 240 cases are unchanged. **Size:** about 20 lines and 35 test
  lines.

## Item 6. Issue 277 (P2): a project named `__proto__` breaks no other project's answers

NO-HOST.

- **Cause, read:** the collector writes a `__proto__` key as `["__proto__"]:` (`dashboard.sh:900-904`), which is
  not JSON. `project_path` (`dashboard_serve.py:138-147`) reads `data.js` with `json.loads`, fails, and returns
  None, so every answer gets 404. The relay watchers already turn the key back into JSON first
  (`cos-watch-alerts.sh:20`, `cos-watch-limit.sh:18`).
- **Change:** `project_path` applies the same substitution before `json.loads`. The Builder checks the server's
  other reads of `data.js` and applies it there too. An answer for the `__proto__` project itself is still refused
  by `PROJECT` (`:66`), with 400, as today.
- **Red first,** `dashboard-serve.test.sh`: a `data.js` with projects `__proto__` (written as the collector writes
  it) and `demo`; a loopback answer for `demo` is taken (200), and one for `__proto__` gets 400 with no error
  in the server's stderr.
- **Done:** that passes. **Size:** about 5 lines and 25 test lines.

## Item 7. Issue 294 (P2): a "Restart collector" button

PORT of 46e2e059.

- **Change, as the host commit:**
  - `scripts/dashboard.sh --restart`: `launchctl kickstart -k gui/<uid>/<label>` on macOS,
    `systemctl --user --no-block restart <unit>` on Linux, with the label and unit `install` writes. Usage lines
    gain it.
  - `scripts/dashboard_serve.py` `POST /restart`: the same checks and order as `/answer`, read no body, fixed
    command. Once a minute at most: a stamp file beside the server's files, since the restart kills the server.
    Logs each request and each failure to stderr. Replies 202, then runs the command (30 s cap).
  - The host's `authed()` check becomes the plugin's loopback check. Item 15 (second unit) later puts it behind
    the login.
  - `dashboard/index.html` and `app.js`: the button by the data-age stamp, a confirm, "restarting..." until
    `alive.cycleStartedAt` moves, then "waiting for first cycle" until `updatedAt` moves; the last cycle's seconds
    (`alive.lastCycleSec`, already written, `dashboard.sh:1029-1034`) beside it. The button shows on a loopback
    page only. The host's login-follow poll (`loginPoll`) comes with item 15, in the second unit.
- **Red first:**
  - `dashboard-serve.test.sh` with a stub `dashboard.sh --restart` that counts: one allowed POST runs it once; a
    second within a minute gets 429 and does not run it; a non-loopback POST gets 403.
  - `dashboard-view.test.mjs`: the button's progress through both states, and the last cycle shown (the host
    commit's view cases).
  - `--restart` on a stub `launchctl`/`systemctl` (`COMMANDECK_HOST_OS`): the fixed command line.
- **Done:** those pass. **Size:** about 80 code lines and 75 test lines.

## Item 8. Issue 270: "Tokens per unit, 7 days"

PORT of the host's `cost_unit` (906f6323) and its page (1338872d), with the plugin's own source.

- **Change:**
  - `dashboard.sh`: a `costPerUnit` part from the kept unit costs the unit cards already read (`$CACHE`'s
    `unit-costs.json`, `:385-387`): each unit finished in the last 7 days (the finished-builds `at`) or in flight,
    its Claude and Codex tokens and list cost (`total.byAgent`), and its `stages`. The host's form reads the unit
    ledger, which item 9 ports, but that ledger holds merged units only; this panel keeps the kept unit costs,
    which also cover units in flight. Owner answer 5 names issues 271 and 272 only.
  - The page: a card ranking units by cost, Claude and Codex apart, each unit's stage rows behind a toggle.
- **Red first:**
  - `dashboard-built.test.sh`: three units in the kept file, one older than 7 days; the part holds the two in the
    window, and its totals equal the sum of their unit-card totals.
  - `dashboard-view.test.mjs`: the card ranks by cost, and a unit's stages show on expand.
- **Done:** those pass. **Size:** about 70 code lines and 70 test lines.

## Item 9. Issue 271: "Review loop, 7 days"

PORT of the host's unit-ledger writer as of c0e61f13 (first 82de37e7) and its call from the merge, then the host's
`review` (906f6323) and `renderReview` (1338872d). Built as owner answer 5.

- **Change:**
  - `scripts/unit-ledger.sh <unit> local [--append]`, the host writer's port: one JSON line per merged unit in
    `<main>/.claude/metrics/unit-ledger.jsonl`, the host's field names (`unit`, `mergeSha`, `mergedAt`,
    `firstDispatchAt`, `wallHours`, `rounds`, `goRounds`, `noGoRounds`, `fixRounds`, `verdict`, `mergeRule`,
    `mergeOpen`, `mergeIssues`, `findings`, `expensivePasses`, `seats`, `tokens`, `gaps`, `recordedAt`). A missing
    metric is null with its gap named, never 0; a row with no merge sha and no verdict refuses to append (the
    host's fail-loud rule). Where the plugin's code differs:
    - local merges only: the PR form and its `gh` reads are not ported;
    - no review-class ledger: the merge passes the outcome in the host's environment names
      (`UNIT_LEDGER_MERGE_SHA`, `UNIT_LEDGER_VERDICT`, `UNIT_LEDGER_ROUNDS`, `UNIT_LEDGER_GO_ROUNDS`,
      `UNIT_LEDGER_NO_GO_ROUNDS`, `UNIT_LEDGER_MERGE_RULE`), read from the Builder's round files it already checks;
    - seats and tokens come from `seat-events.jsonl` and `seat-event.sh --usage` (its header already names this
      writer as a caller), and transcripts through item 4's `pp_claude_dir`;
    - the host's routing-log seat rows and its builder-model trial are not ported: the plugin's routing log holds
      only override lines.
    The file is kept as `seat-events.jsonl` is (`install-lib.sh:52` lists it); the plugin's merge does not commit it.
  - `scripts/merge-unit-local.sh`: after the Builder's seat event (`:427`), one `unit-ledger.sh <unit> local
    --append`. Like the seat event (`:423`, "Never blocks a merge"), a refusal prints one line and is ignored. The
    host's step-3 preflight, which refuses the merge when the writer refuses, is not ported: the plugin's merge
    does not block on a metrics row.
  - `dashboard.sh`: a `reviewLoop` part from the unit ledger's rows merged in the last 7 days: `rounds`,
    `goRounds`, `noGoRounds`, `fixRounds`, `findings`, `gaps`, `expensivePasses`, sorted by rounds. Escape rows
    (item 10) are skipped. No ledger: not measured.
  - The page: the host's card, the units with the most rounds first.
- **Red first:**
  - `scripts/__tests__/unit-ledger.test.sh`, the host's measurement cases kept to the plugin's sources: a fixture
    unit with three NO-GO rounds and a closing GO gives one row with those counts and its tokens; a missing seat
    log is a named gap, not 0; no sha and no verdict refuses `--append`; a second run for the same unit and sha
    appends no duplicate (the host's "already recorded").
  - `merge-unit-local.test.sh`: a merge appends one ledger row for the unit; a refused writer prints its line and
    the merge still exits 0.
  - `dashboard-built.test.sh`: after the worktree is gone, `reviewLoop` still has the unit's counts; a row older
    than 7 days and an escape row are left out.
  - `dashboard-view.test.mjs`: a unit with repeated NO-GOs is listed first (the issue's acceptance).
- **Done:** those pass. **Size:** about 430 code lines and 300 test lines (the least certain of items 1-13: the
  host writer is 669 lines).

## Item 10. Issue 272: "Review escapes"

PORT of the host's escape tagger (6483ea4a), `escapes` (906f6323) and its part of `renderReview` (1338872d).
Built as owner answer 5: one ledger, item 9's.

- **Change:**
  - `scripts/unit-ledger.sh --escaped <unit> <issue>`: appends `{unit, escaped: [N], recordedAt}` to the unit
    ledger. The host tags the scope's last review-class line in place; the plugin's ledger is append-only JSON
    lines, so an escape is a row of its own. A unit with no merged row is still tagged (the host's rule: an escape
    can outlive its entry). The same unit and issue twice adds nothing. Issue numbers only.
  - `dashboard.sh`: an `escapes` part from the escape rows, each `{unit, escaped}`, one entry per unit with its
    issues joined. No ledger: not measured.
  - The page lists them under the review card, "No escaped issue tagged" when empty.
- **Red first:** `unit-ledger.test.sh`: `--escaped` appends one row, a repeat adds none, a non-number is refused.
  `dashboard-built.test.sh`: a ledger with one merged row and one escape row gives one escape entry, and
  `reviewLoop` still counts one unit; no file gives null with the reason. `dashboard-view.test.mjs`: an empty and
  a non-empty list (the acceptance).
- **Done:** those pass. **Size:** about 60 code lines and 65 test lines.

## Item 11. Issue 273: the Issues card's 24-hour line and sparkline

PORT of the host's `issues` (906f6323) and `spark` (1338872d).

- **Change:**
  - `dashboard.sh`: two more cached gh reads in `github_panes` (`:498`), the host's two: issues created in the last
    7 days, and issues closed in the last 7 days (`--limit 1000`, an `incomplete` flag at the limit).
    `opened24h`, `closed24h` and `daily` (opened and closed per local day, 7 days) go under `github`.
  - `#held` (the Issues card, `index.html:104`): one line "N opened, M closed in 24 h" and the host's sparkline.
  - The host's sparkline draws opened and closed per day; issue 273 says "open issues over recent days". The port
    draws the host's, and the commit body says so.
- **Red first:** `dashboard-github.test.sh` with the gh stub: the counts match the fixture's issues, and a read at
  the limit is marked incomplete. `dashboard-view.test.mjs`: the line and seven bars render, and a null `daily`
  says not measured.
- **Done:** those pass. **Size:** about 65 code lines and 65 test lines.

## Item 12. Issue 274: a folded list of recently resolved alerts

NO-HOST (see "Host commits").

- **Change:**
  - `dashboard_alerts.jq`: a key in `$prev` that is not raised now is resolved, with its `since` and
    `resolvedAt` = now. The output gains `resolved`.
  - `dashboard.sh alerts`: resolved alerts are appended to `$CACHE/alerts-resolved.json`, which keeps 24 hours.
    An `alertsResolved` part carries them.
  - The page: a closed `<details>` under the alerts list, "Resolved in the last 24 h (N)", each with start and
    clear times.
- **Red first:** `dashboard-alerts.test.sh`: an alert raised in one run and gone in the next is in `resolved`
  with both times, and not in `alerts`. `dashboard-view.test.mjs`: it shows in the folded list.
- **Done:** those pass. **Size:** about 55 code lines and 60 test lines.

## Item 13. Issue 299 (P2): the collector reads what changed since the last cycle

PORT of c032363b, its "Cut 2" parts 2a, 2b, 2d and 2f. Parts 2c and 2e have no plugin twin.

- **Cause, read:** the plugin's readers have the host's shape before its fix:
  - `dashboard_limit.py` `requests()` (`:415`) and `codex_requests()` (`:714`) keep offsets, but drop the offset
    of a file skipped for age. `build` (`:868`), `units` and `seats` (`:1070`) are separate Python calls that each
    walk the transcripts.
  - `guard_blocks` (`dashboard.sh:585`) reads every day file whole each cycle.
  - `pp_session_log_at`, `pp_session_bg_open` and `pp_session_cache` (`paths.sh:139-168`) each scan a Builder's
    transcript, and the collector (`dashboard.sh:312`) and main-watch (`main-watch.sh:197`) call them in a row.
  - `orca-ide terminal list` runs at `dashboard.sh:242` and `:768`, in `paths.sh:527` and `:544`, and once per
    registered project (each project is a child collect, `:872`).
- **Change, as the host commit:**
  - 2a: a file skipped for age keeps its offset. One ingestion per provider per cycle feeds `build`, `units` and
    `seats`: the first call of a cycle stores the rows under the cycle's `$RUN`, and later calls with the same
    cycle stamp read them. The Builder says which.
  - 2b: `guard_blocks` reads each day file from its stored offset; block rows and pending per-session calls are
    kept in `$CACHE/guard-blocks.json`. A file no longer listed drops its state, and a truncated one is read from
    zero. A cycle that could not read a file saves no state (the host's fix-round-4 finding).
  - 2d: one `pp_session_summary` per Builder per cycle, from a stored offset, giving all three values. Open
    background jobs are kept across cycles.
  - 2f: one terminal list per cycle, written to the top-level `$RUN` and read by every project's child collect.
  - A state file that is missing, unreadable or of another version is a cold start.
- **Red first,** a new `scripts/__tests__/dashboard-collector-incremental.test.mjs` and its `.test.sh` wrapper (as
  `dashboard-view.test.sh` wraps its `.mjs`), so the runner finds it. Reads are counted by running the module under
  `python3 -c` with `builtins.open` wrapped, with no product knob (the host's method):
  - old files keep offsets: the second cycle reads 0 bytes of unchanged files;
  - one ingestion per cycle: each file opened at most once across `build`, `units` and `seats`;
  - guard blocks and the Builder summary read appended bytes only;
  - for each reader: a partial line waits, rotation, truncation re-reads from zero, corrupt state is a cold start;
  - a streamed request is counted once;
  - `dashboard-built.test.sh`: two collects give the same keys and values the page reads (sample times aside).
  Each case is marked red-first or pin by running it on the base first, as the host did.
- **Done:** those pass. The commit body has the cycle time and the count of processes started, before and after,
  on the same fixture. **Size:** about 220 code lines and 300 test lines.

## Item 14. Issue 269: "Tests running now"

**Second unit, not this build** (owner answer 2). PORT of 26a2b168 (its "Cut 6"), this machine only (owner
answer 4).

- **Change, as the host commit:**
  - `dashboard.sh` `tests_panel`, `tests_rows`, `tests_builders`, `TEST_RE` and `TEST_WHO`: runner processes from
    `ps` (a shell or node first word that names a test runner; not `-n`, `-c`, `-e`, `-p`, `--check`), only the
    outermost of a parent and child, their folders from `lsof -a -d cwd`, and who started each: the unit for a
    worktree, `main`, or the folder's name. `TEST_RE` is the plugin's: `run-shell-tests.sh`, `.test.sh`,
    `node --test` and npm's test aliases; the host's own script names are left out.
  - `dashboard_limit.py tests`: finished runs from the session logs (`runs_tests`, `shell_split`, `test_counts`,
    and c032363b's and 0a587d27's parser follow-ups for the same functions, since they fix the same parser), with
    passed and failed totals and each command's usual time.
  - Stalled (the issue's own rule): a running row past its time cap with no result. The cap is
    `run-shell-tests.sh`'s per-file cap times the files, or the usual time times 3 when known.
  - The page: the host's `#tests` card and its phone tab, one lane. The host's second-machine lane, its load tiles
    and its `ssh` process list are not ported (owner answer 4).
- **Red first:** the host commit's cases for this machine: `dashboard-built.test.sh` with stub `ps` and `lsof`
  (a nested runner gives one row with its owner; `bash -c` and `node -e` are not runs), a finished run from a
  fixture session log with its totals, a stalled row; `dashboard-view.test.mjs`: a running row with owner and
  elapsed time, a finished row with totals, and not measured when `ps` failed.
- **Done:** those pass. **Size:** about 400 code lines and 220 test lines.

## Item 15. Issue 263: the dashboard behind a login over HTTPS

PORT of b257a08f ("Cut 4"), 62121446 (minimum 8 characters) and 3f19f6a9 (a password change keeps trusted
devices). **Second unit, not this build** (owner answer 2). Built as owner answer 3.

- **Change, as the host commits,** in `scripts/dashboard_serve.py` (standard library only):
  - CLI: `make-cert [--force]` (one `openssl req -x509`, P-256, 825 days, names `<host>.local`, `localhost`,
    `127.0.0.1`); `set-password <user>` (asked twice, at least 8 characters, scrypt N=2^14 r=8 p=5, 16-byte salt;
    moves the epoch, keeps devices); `devices`; `revoke <id>|all`. Every store change holds `flock`, writes a temp
    file and renames it, mode 0600.
  - With the login on: TLS only (no certificate: refuse to start), one `authed()` gate on every route except the
    public three (`GET`/`HEAD /login`, `POST /login`); 302 to `/login` for pages, 401 for `PUT` layout, `/answer`,
    `/unsent` and `/restart`. Lockout after 5 failures in 15 minutes for 15 minutes, under one lock. Cookies
    `HttpOnly; Secure; SameSite=Strict`. The login page is a constant in the server. No password or token reaches
    a log, `data.js` or a reply.
  - With the login on, `/answer`, `/unsent` and `/restart` take any logged-in client; the loopback rule applies
    only with the login off (owner answer 3).
  - `dashboard.sh --install`: runs `make-cert` when the bind is not loopback and no certificate exists, and prints
    the `https://` address. `skills/setup/SKILL.md`: after a LAN bind, one line telling the owner to run
    `set-password` once.
  - `app.js`: a 401 sends the page to `/login`; the answer buttons show on any logged-in page; item 7's
    login-follow poll.
  - `dashboard-serve.test.sh`: a fixture certificate made once per file and a logged-in cookie jar for the existing
    cases with the login on; their assertions do not change.
- **Red first,** the host commit's cases: every route needs a login (302 or 401, files unchanged); the login page is
  public; log in then answer; a trusted device answers after a restart; a revoked device ends its session on the
  next request; `revoke all`; lockout after five failures, and exactly five 401 and fifteen 429 under 20 parallel
  wrong logins; a 7-character password refused; cookies are secure; plain HTTP gets no page; no certificate
  refuses to start; no secret in any file or log. And one plugin case: a loopback bind serves as today with no
  login.
- **Done:** those pass. **Size:** about 380 code lines and 270 test lines.

## Version

- `.claude-plugin/plugin.json`: `0.22.0` to `0.23.0` (new behaviour: the second part, per `ci/version-check.sh`).
  If a sibling unit merged first and took 0.23.0, the Builder takes the next free minor. `README.md:4`, the badge's
  URL and alt text, follows it (`plugin.test.sh` holds both to the manifest).
- `.claude-plugin/marketplace.json` has no version field, and nothing holds one there. Nothing to bump.
- `CHANGELOG.md`: `## 0.23.0 -- <date>` on top, one bullet per item with its `#N`. It also says issues 217, 224,
  240 and 242 shipped in 0.21.0 and 0.22.0, and that 263 and 269 follow in the next unit. Those numbers take the
  `#` form in CHANGELOG.md only. The second unit takes the next free minor and its own CHANGELOG entry.
- About 30 changed lines.

## Order of work: each shared file is touched once per step

| Step | Items | Files |
|---|---|---|
| 1 | 1 | dashboard_serve.py (deliver, settle, `/unsent`), dashboard.sh `needs_owner`, dashboard_alerts.jq, app.js `renderNeeds`, their tests |
| 2 | 2, 3 | dashboard.sh (job env, `--import`, `register`, jq sites), decision.sh, cos-watch-alerts.sh, main-watch.sh `heads_up_capture`, dashboard_alerts.jq (`$preva`) |
| 3 | 4 | paths.sh `pp_claude_dir`, read-verdict.sh, main-watch.sh, seat.sh, subagent-usage.sh, builder-codex-pass.sh, collect.py, four hooks, dashboard.sh transcript reads, plugin.test.sh |
| 4 | 5, 6 | app.js `renderNeeds`, dashboard_serve.py `project_path` |
| 5 | 7 | dashboard.sh `--restart`, dashboard_serve.py `/restart`, index.html, app.js |
| 6 | 9, 10 (writers) | unit-ledger.sh (new, with `--escaped`), merge-unit-local.sh, their tests |
| 7 | 8-12 (panels) | dashboard.sh new parts, dashboard_alerts.jq (`resolved`), index.html, app.js, app.css |
| 8 | 13 | dashboard_limit.py readers, dashboard.sh `guard_blocks` and terminal list, paths.sh session summary, main-watch.sh's caller |
| 9 | version | plugin.json, README badge, CHANGELOG; the whole "Done when" list |

The second unit, from this plan after this one merges (owner answer 2):

| Step | Items | Files |
|---|---|---|
| 1 | 14 | dashboard.sh `tests_*`, dashboard_limit.py `tests`, index.html, app.js, app.css |
| 2 | 15 | dashboard_serve.py login, dashboard.sh `--install`, SKILL.md, app.js, every server test |
| 3 | version | plugin.json, README badge, CHANGELOG; the "Done when" list, with items 14 and 15 among the page changes |

- **Same file, more than one item** (this build):
  - `scripts/dashboard_serve.py`: items 1, 6 and 7. In the second unit, item 15's gate wraps the routes items 1
    and 7 add.
  - `scripts/dashboard.sh`: items 1-4 and 7-13. Item 3's jq sites first (step 2), so the new parts of items 8-12
    are written in the file form from the start.
  - `dashboard/app.js`: items 1, 5 and 7-12. `renderNeeds` changes in items 1 and 5.
  - `dashboard/index.html`: items 7-12. `dashboard/app.css`: items 8-12.
  - `scripts/dashboard_alerts.jq`: items 1 (answer alert), 3 (`$preva`) and 12 (`resolved`).
  - `scripts/dashboard_limit.py`: item 13. In the second unit, item 14's `tests` reader uses item 13's one
    ingestion.
  - `scripts/main-watch.sh`: items 3, 4 and 13. `scripts/paths.sh`: items 4 and 13 (the session summary reads
    through `pp_claude_dir`). Item 9's writer reads transcripts through item 4's `pp_claude_dir`, so step 3
    comes first.
  - `scripts/unit-ledger.sh`: items 9 and 10. `scripts/merge-unit-local.sh`: item 9 only.
  - `scripts/decision.sh` and `scripts/cos-watch-alerts.sh`: item 2 only.
  - `.claude-plugin/plugin.json`, `README.md`, `CHANGELOG.md`: the version step.
- **Same data:** item 9's writer and item 10's tagger append to one file, `unit-ledger.jsonl`; the `reviewLoop`
  part skips escape rows, and the `escapes` part reads only them. Item 1's `key` in `needsOwner.unsent` is what
  the page's buttons send.

## Files a sibling unit also touches

Set the merge order by these. Several sibling issues name a file only in their text, so "likely" is said where the
file is inferred.

| File | This plan | hooks-seats-guards-2026-10-21 | merge-checkpoint-relay-2026-10-21 |
|---|---|---|---|
| `.claude-plugin/plugin.json`, `README.md`, `CHANGELOG.md` | version | version | version, 293 (plugin.json options) |
| `scripts/read-verdict.sh` | 4 | 225, 236 | 237 |
| `scripts/seat.sh` | 4 | 234, 236, 257, 278 (likely) | - |
| `scripts/main-watch.sh` | 3, 4, 13 | 238, 258 (likely) | 227, 300 (likely) |
| `scripts/dashboard_alerts.jq` | 1, 3, 12 | 238 (named), 258 (likely) | 300 (likely) |
| `scripts/decision.sh` | 2 | - | 231, 232, 259 (`push-ask`) |
| `scripts/cos-watch-alerts.sh` | 2 | 229 | 290, 300 (likely) |
| `scripts/paths.sh` | 4, 13 | - | 293 |
| `scripts/builder-codex-pass.sh` | 4 (one line) | 225, 260, 266 (likely) | 243 |
| `hooks/agent-startup-context.sh` and its test | 4 (one line) | 268, 229 | - |
| `hooks/ruling-log.sh` | 4 | - | 232 |
| `hooks/resume-context.sh` | 4 (one line) | - | 252, 281, 283, 300 (likely) |
| `skills/worktreereview/scripts/collect.py` | 4 (one line) | 262 | - |
| `scripts/merge-unit-local.sh` | 9 (one call) | 265 (named in its plan) | not checked: that unit's plan was not on disk |
| `scripts/dashboard.sh`, `dashboard_limit.py`, `dashboard/*` | most items | 262 (stage clock, likely) | - |
| `scripts/run-shell-tests.sh`, `scripts/host-services.sh` | none (no peer, owner answer 4) | - | 243 (296 and 297 closed as won't do) |

## Size

This build, items 1-13 and the version step: about 2,630 changed lines. Owner answer 5 adds about 600 (the
unit-ledger writer and the escape tagger) to the 2,030 first planned. The second unit, items 14 and 15: about
1,270 lines and its own version step. The 0.21.0 plan estimated 2,700 and was split; 0.20.0's plan estimated 1,060
for about 1,400 built, so these figures may also be low. Items 9 and 13 are the least certain of this build: each
ports a host change of 500 to 700 lines.

| Item | Lines |
|---|---|
| 9, issue 271 (unit-ledger writer, review loop) | 730 |
| 13, issue 299 (incremental collector) | 520 |
| 1, issue 295 (undeliverable answers) | 240 |
| 7, issue 294 (restart button) | 155 |
| 2, issue 292 (switch breakers) | 140 |
| 8, issue 270 (tokens per unit) | 140 |
| 11, issue 273 (issues sparkline) | 130 |
| 12, issue 274 (resolved alerts) | 115 |
| 3, issue 280 (jq files) | 110 |
| 4, issue 291 (config folder) | 110 |
| 10, issue 272 (escape tagger, escapes) | 125 |
| 5, issue 276 (focused form) | 55 |
| 6, issue 277 (`__proto__`) | 30 |
| Version and CHANGELOG | 30 |
| **This build** | **2,630** |
| 15, issue 263 (login), second unit | 650 |
| 14, issue 269 (tests panel), second unit | 620 |

## Prior art

- **Item 1:** a retry queue with a cap and a dead-letter state, as message queues hold a message that keeps
  failing (SQS's dead-letter queue): the reason and count are kept, and a person decides. No library.
- **Item 2:** a one-time import at a cut-over, and seeding "seen" state so a migration raises no old alert again.
- **Item 3:** POSIX `ARG_MAX`: data that grows goes through files or pipes, never the argument list. jq's own
  `--slurpfile`/`--rawfile`.
- **Item 4:** Claude Code's documented `CLAUDE_CONFIG_DIR`, as the plugin's limit reader already uses it.
- **Item 5:** keyed list reconciliation: a row is kept by its key while the list around it is rebuilt, as React's
  `key` does. No framework: one node kept.
- **Item 6:** prototype-pollution-safe keys: one normaliser on every read, as the relay watchers already do.
- **Item 7:** the service manager restarts the job (`launchctl kickstart -k`, `systemctl restart`), rate-limited.
- **Items 8-11:** the host project's own panels, ported. Items 9 and 10: the host's own unit ledger, an
  append-only JSON-lines file, one record per merged unit, with later facts (escapes) as rows of their own, as
  event logs do. Item 11's sparkline is Tufte's word-sized graphic.
- **Item 12:** Alertmanager's resolved notifications: an alert that clears is reported with its start and end.
- **Item 13:** incremental tailing with stored offsets, rotation and truncation handled, as `tail -F` and log
  shippers (Fluent Bit's offset database) do.
- **Item 14 (second unit):** the process table (`ps`, `lsof`) and the session logs as the only sources; no
  test-runner plugin.
- **Item 15 (second unit):** OWASP ASVS 4.0.3 V2 and V3, and the OWASP password-storage (scrypt parameters) and session-management
  cheat sheets; cookies `Secure`, `HttpOnly`, `SameSite=Strict`. Python's standard `hashlib.scrypt`, `secrets`,
  `hmac` and `ssl`, and the system's `openssl` for the one certificate. No new dependency.
- This repository has no `.claude/paved-road.md`. Nothing here adds a dependency or a service: items 1, 7 and 15
  add routes to the existing dashboard server.

## Not built

- Items 14 and 15 (issues 269 and 263): the second unit, built from this plan after this one merges (owner
  answer 2).
- Issue 292's rows outside item 2's table "Here" column: the second plan (owner answer 1).
- Any second-machine (peer host) support: issue 269's peer lane, issue 292's second-machine rows, c032363b's peer
  part (owner answer 4).
- 0a587d27's queued counts, red-proof progress and live pass/fail: beyond issue 269's acceptance.
- The host unit-ledger writer's PR form, routing-log seat rows, builder-model trial and merge preflight (item 9).
- c032363b's parts 2c and 2e: the plugin has no push-record verifier and no compaction reader.
- The host's decisions key, or any key holding a personal name (owner answer 6).
- `decision.sh push-ask`: issue 259, sibling unit.
- Issue 226: on hold.
- Anything without a Commandeck issue in this unit's scope.

PLAN-DONE

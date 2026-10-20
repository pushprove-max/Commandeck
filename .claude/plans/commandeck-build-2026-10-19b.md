# commandeck-build-2026-10-19b -- one plugin build for every open plugin issue (203-251)

Order: the owner, 2026-10-19 17:37 ET: "START A PLUGIN BUILD WITH ALL OPEN PLUGIN ISSUES". One unit, one Builder,
no split or batching without the owner. Scope: every issue open at 21:37Z, 46 of them: 203, 204, 206-218 and
221-251. Twelve are already met (item 0) and main closes them. This build is the other 34, items 1 to 33. Issues
241 and 218 are P1 and are built first. Question 1 below asks whether to split anyway, given the size.

Base: main 3e588fe (0.20.0, pushed).

Public repo: no personal names, handles, pane names (other than the existing seat folder name `Chief-of-Staff`)
or user paths in any shipped file, comment, test, commit message or changelog line. Outside CHANGELOG.md an issue
number is written "issue N". "The host project" is the project this plugin was taken from; several issues here
port its fixes, and its issue numbers are written "host issue N". Commit titles are plain. Test fixtures use
dates before 2000 for ruling ids.

Skill for the build: `mattpocock-skills:tdd`. Every item with logic is red first. Items 2 and 29 are speed work:
there, the red test is replaced by a timing taken before and after, and the commit body records both timings.

## Done when

- `bash scripts/run-shell-tests.sh` (the whole suite, not `--changed`) is green on the tip before the final
  review. The Builder records the tip, the time taken and the totals in the brief's evidence. It also passes once
  with jq 1.7 first on `PATH` (CONTRIBUTING.md).
- `bash ci/leak-test.sh` exits 0.
- `dashboard-view.test.sh` runs and is not skipped. `COMMANDECK_TEST_NODE_MODULES` names a node_modules folder
  that has jsdom, and the brief names that folder. Items 3, 5, 26 and 27 change the page.
- `claude plugin validate .`, `bash ci/version-check.sh main` and `bash scripts/startup-size.sh` pass.
- No install, uninstall or whole-setup run, and no end-to-end test (owner ruling 2026-10-16). The tests drive
  functions and scripts on scratch HOMEs, as they do today.
- Every review pass runs through the pass script the brief names (the installed plugin's).
- Each of items 1-33 meets its own "Done" line below. An item whose question the owner has not answered is built
  as the recommended answer, and the brief says so.

## Questions for the owner

Main sends each one as a decision. The recommended answer comes first.

Answered 2026-10-19 (r-20261019-220436-1-b2686c): the recommended answer to all eleven. So this unit builds
items 1-25 and 28-32; items 26, 27 and 33 (issues 224, 240, 245) are a second unit, planned and built right
after this one merges.

1. **Size (all items).** The estimate is about 2,700 changed lines. That is about twice what 0.20.0 changed
   (about 1,400), and 0.20.0 took five review passes. Issues 224, 240 and 245 (items 26, 27, 33) are new
   features. Together they are about 760 lines, and each also waits on a question below.
   **Recommended: keep this unit to items 1-25 and 28-32, and build 224, 240 and 245 as a second unit right
   after it.** Other answer: one unit as ordered, with those three built last.
2. **Issue 215, per spelling.** The guards are lexical cost guards for agents that cooperate. They are not
   security boundaries. **Recommended:**
   - (1) `$'sleep'` and `$"sleep"`: catch it, in `strip-quoted.sh`.
   - (3) `bash -c`, `eval`, `env -S`: catch it with item 6 (issue 216).
   - (2) a command word built by expansion, and (4) a wrapping function or alias: out of scope. List them in the
     hook header as known gaps.
   - (5) `"a b""sleep"`: leave it. It blocks too much, which is the safe direction.
   Other answer: also refuse (2) when a worker's command word starts with `$` or holds `{a,b}`.
3. **Issue 221, which patterns.** The plugin has no check of commit messages today. `ci/leak-test.sh` searches
   files only, and `ci/leak-words.txt` is this repository's own word list, not a user project's. **Recommended:**
   the merge applies built-in generic patterns to every project: a home path (`/Users/<x>/`, `/home/<x>/`) and
   this machine's host name. It also applies the project's own `ci/leak-words.txt`, through a new
   `ci/leak-test.sh --text <file>` mode, when the project has that file. One list, so the two checks cannot
   drift. Other answer: the generic patterns only.
4. **Issue 226, how to name the account on the panel.** The dashboard is reachable from the home network.
   **Recommended:** a masked email: the first letter, then the domain (`m…@example.com`). Other answers: the
   full email; the organization name.
5. **Issue 227: the plugin's main does not type a watcher.** `main-watch.sh` is a host job that the plugin
   installs. Main arms nothing (`templates/main-session.md`, and the RESUMED line in `hooks/resume-context.sh:95`).
   So the arm calls, drain calls and "no watcher" messages that the issue measured in a sibling project do not
   happen here. Of its points, only one fits: an action script closes its own item task.
   **Recommended:** build only that part. `merge-unit-local.sh`, `answer-worker.sh` and `seat.sh collect`
   complete main-watch's open item task for their unit or seat. Then close the issue. Other answer: close it as
   not applicable and build nothing.
6. **Issue 232, what the 30-minute "relay ping" does.** An open picker blocks the relay pane itself.
   **Recommended:** `main-watch.sh` raises a dashboard alert when the relay pane has a question prompt open for
   30 minutes or more while messages for it wait: "picker open N min; M messages waiting behind it". It sends
   nothing to the pane. Other answer: also a desktop notification.
7. **Issue 239, when to close.** Merges are local, and nothing is pushed until main pushes. **Recommended:**
   close at the merge, each with a comment that names the merge commit and the release ("fixed in <sha>, ships
   in <version> with the next push"). Other answer: the merge only prints the `gh issue close` commands, and
   main runs them after the push.
8. **Issue 240, who may answer from the panel.** The server binds 0.0.0.0. A token in the page is readable by
   anyone on the network who loads the page, so a token alone does not keep that network out.
   **Recommended:** the answer endpoint accepts POST from a loopback address only, and also checks the
   `Origin`/`Host` header. Answers come from the PC, and the phone view stays read-only. Other answer: a pairing
   token that setup prints once for the phone, kept in a cookie.
9. **Issue 245, precedence and first set.** `pluginConfigs` belongs to the user and applies to every project.
   `.claude/commandeck.json` belongs to one project. **Recommended:** as the issue says, a value set in
   `/config` wins over the project config, and setup pre-fills the defaults. The first set is the settings that
   are the same for every project: Builder model and effort, max review rounds, closing pass, prompt-cache TTL
   (Builder and relay), ponytail, dashboard bind and port, and the full suite before the final review. The test
   command and the relay name stay in the project config. `doctor` names each value's source.
   Other answer: the project config wins, and `/config` only fills keys a project never set.
10. **Issue 250, the probe path.** A Codex reviewer runs under `--sandbox read-only` (`config/routing.json`,
    role `codex-reviewer`), and every hook writes state (`/tmp/claude-batch-*`, the fire log). So a probe cannot
    run. **Recommended:** a new `scripts/hook-probe.sh <hook> <command>` runs a hook with HOME, TMPDIR and its
    logs in a scratch folder and prints allow or refuse. Reviewer seats run `--sandbox workspace-write` with
    their working folder set to a fresh scratch folder outside the repository, so the repository stays
    read-only. The shell-write guard stays on. The Builder first confirms, against the Codex docs, that
    `workspace-write` makes only the working folder and the temp folders writable. Other answer: the reviewer
    lists probes in its report, and the pass script runs them after the session and appends the results.
11. **Issue 247, inline-script writes.** **Recommended:** in a Builder seat, refuse an inline `python -c` /
    `python - <<` / `perl -e` / `node -e` that writes a tracked file, and point to Edit. Writes under scratch
    paths are allowed. Other answer: run the Edit checks on what the script wrote.

## Item 0. Close as shipped (main closes these; no build)

Each issue was checked at 3e588fe, and each one's "done when" is met.

| Issue | Shipped in | Evidence |
|---|---|---|
| 203 | 740302a (wait cap in 6c0e3dc) | `agents/helper.md:13` (cap and `NOT FOUND:`); `templates/_builder-brief-template.md:34` (reuse a helper's pointers); `scripts/unit-cost.sh:8`, `:56` (cold replies, repeats); WARM `scripts/main-watch.sh:226-239`; QUIET at 225 s `scripts/dashboard_builders.jq:12`, `:92`; tests `unit-cost.test.sh:4`, `main-watch-helper-hold.test.sh:226-255`, `dashboard-built.test.sh` (bgOpen) |
| 204 | 740302a | `scripts/plan-worktree-close.sh:50` (`jq -S`); test `plan-worktree-close.test.sh:88-93` |
| 206 | 740302a | `hooks/dependency-addition-guard.sh:78`, `:86` (`own_setup`); test `dependency-addition-guard.test.sh:125-128` |
| 207 | 740302a | `il_notify_repoint`, `scripts/install-lib.sh:521`; test `install-lib.test.sh:347-351` |
| 208 | 740302a | `il_block_text`, `scripts/install-lib.sh:553-555`, one "would copy" `:607`; test `install-lib.test.sh:357-368` |
| 209 | 740302a | `scripts/merge-rules.py:215`; test `merge-rules.test.sh:67-71` |
| 210 | 740302a | `skills/setup/SKILL.md:21` (saved equals recommended: one option) |
| 211 | 740302a | `dashboard/app.css:352`, `:377` (tab bar under 760 px); `dashboard/app.js` layout merge `:1666-1708`; test `dashboard-view.test.mjs:587-611`. The fold gap left open is item 5 (issue 217). |
| 212 | 740302a | `scripts/orca-wait.sh:330-339` (`next: fix round`); `templates/main-session.md:27`; test `orca-wait.test.sh:48` |
| 213 | 740302a | `hooks/batch-independent-looks.sh:107-108` (`strip_quoted`); tests `batch-independent-looks.test.sh:25-31` (the `touch` case at `:31`) |
| 214 | 740302a | `hooks/no-poll-loops.sh:198-251` (270 s / 540 s budget); `hooks/worker-ask-guard.sh:50` (`--timeout-ms 240000`); `no-poll-loops.test.sh`. The listed gaps are open on purpose; issues 215 and 216 follow them up. |
| 251 | 3a27d88 (0.1.0) | The plugin's copy already waits on the helper's own done signal: `wait_for "$helper_done"`, `hooks/__tests__/context-clear-stop.test.sh:58-66`, 30 s cap, returns as soon as the helper closes the old pane. Measured while planning: 2 s alone. With 12 copies at once while 8 CPU-bound loops held all 8 cores, every run passed 18/18 in 9-10 s, far under the 120 s per-file cap. The 121-case flake is the sibling project's file. |

Partly met already (the rest is built below): issue 228 (`resume-context.sh` already holds its block under
10,240 bytes, and parts that do not fit become pointer lines, `:12`, `:65-134`); issue 231 (`decision.sh answer`
already finds `askedAt` itself when `--asked-at` is left off, `scripts/decision.sh` `answer)`, and the relay's
line at `hooks/agent-startup-context.sh:114` already leaves it off); issue 233 (`seat.sh` already refuses a second
live seat on another spec, `:270-280`).

## Priority

- **P1, issue 241 (item 1).** "None" is setup's recommended relay answer (`skills/setup/SKILL.md:133`). So in a
  default install, main is the only seat that asks the owner anything. The hook blocks main's repeated question,
  and the owner never sees it.
- **P1, issue 218 (item 2).** The merge's own check (`run-shell-tests.sh --changed`, 120 s per file,
  `scripts/run-shell-tests.sh:36`) has already rolled back one merge because of this test. Item 7 changes
  `main-watch.sh`, so this build's own merge runs the same test.
- **P2, issue 226 (item 3):** labelled P2. The panel shows the wrong account's limit.
- Then the bugs (items 4-7), and then the rest, grouped by the files they share (see "Order of work").

## Item 1. Issue 241 (P1): with no Chief of Staff, main's question is never blocked

- **Cause:** `hooks/ask-records-decision.sh` calls `blocked` (exit 2) when `decision.sh check` finds the question
  open or answered in the last 24 hours (the `dups` loop), and again on a racing repeat (`[ $? -eq 3 ] && blocked`).
  It never reads whether a relay exists. Setup records the relay as `.chiefOfStaff.name` in the project's
  `.claude/commandeck.json` (`scripts/setup.sh:393`). With no relay, the key is absent or empty.
- **Change:** with no `.chiefOfStaff.name` in `$ROOT/.claude/commandeck.json`, neither `blocked` call exits. The
  picker goes out. The ledger row is still written, or kept when it is already there.
  `ask-stop-records-decision.sh` is left as it is. Its first hold needs a `cos-owed` mark, which only a relay
  writes. Its second hold asks main to record a question already on screen, and it holds once. Neither one stops
  a question from reaching the owner.
- **Red first,** `hooks/__tests__/ask-records-decision.test.sh`:
  - a config with no `chiefOfStaff`: the same question asked twice. The second call exits 0, and the ledger has
    that id.
  - the same with `chiefOfStaff.name` set: the second call still exits 2. This pins what is kept.
- **Done:** both cases pass. **Size:** about 4 hook lines and 15 test lines.

## Item 2. Issue 218 (P1): main-watch-helper-hold.test.sh well under the per-file cap

- **Cause, measured while planning** (Mac, alone): 74 s. A line trace attributes 72.5 s to test line 61
  (`tick` -> `main-watch.sh --once`), which runs 106 times at about 0.7 s each. The `sleep 30/60/300` at `:161-193`
  run in the background and are killed; nothing waits on them. So the cost is the number of ticks times the cost
  of one tick, not real sleeps.
- **Change, in order. Stop at the first step that meets "Done":**
  1. Profile one `main-watch.sh --once` against the test's fixture. Use a direct run with
     `PS4='+${EPOCHREALTIME} ${BASH_SOURCE##*/}:${LINENO} '`. Under xtrace the whole test fails at its first tick,
     because the test treats a non-empty stderr as a failure. Cut the per-tick cost where the time goes (jq
     starts per seat, repeated stub calls). This also speeds the real job.
  2. Ticks that only set up a later case are merged into it.
  3. Split the file in two by section (helper hold; WARM and wake). `run-shell-tests.sh` runs files in parallel.
- **No red test** (speed). **Done:** each resulting file takes 40 s or less alone on the Mac, and 120 s or less
  with 4 copies at once while CPU-bound loops hold every core. That is the method used for issue 251 in item 0.
  The commit body records the timings before and after. **Size:** about 40-80 lines; a split moves lines but
  changes few.

## Item 3. Issue 226 (P2): the limit panel follows the signed-in account

- **Cause, read (not reproduced: that needs a second login):**
  - `scripts/dashboard_limit.py` `token()` (`:59-75`) reads only the default stores: the keychain item
    `Claude Code-credentials` and `~/.claude/.credentials.json`. It never reads `CLAUDE_CONFIG_DIR`, and no
    script in the plugin except `builder-codex-pass.sh:71` does. Orca can run a pane under its own Claude config
    folder (`CLAUDE_CONFIG_DIR`). An account switch done that way is never seen: the collector keeps reading the
    old login.
  - `scripts/dashboard.sh` `cached` (`:76-105`) keeps a reading for its TTL. After a failed read it shows "the
    last good copy" with no account check.
  - `limit-history.jsonl` mixes the samples of both accounts.
- **Change:**
  - `hooks/agent-startup-context.sh`, main only: write `${CLAUDE_CONFIG_DIR:-}` to
    `$PP_SCRATCH/claude-config-dir`. The newest main session's folder is the current login.
  - `dashboard_limit.py`:
    - the account is `oauthAccount.accountUuid`, read from `<that folder>/.claude.json`, or `~/.claude.json` for
      the default.
    - `fetch` reads the credentials of that folder. Off a Mac, that is `<folder>/.credentials.json`. On a Mac,
      the Builder first confirms from Claude Code's documentation how the keychain item is named for a
      non-default config folder. If that cannot be confirmed, such a folder reads as `not-measured` with that
      reason. It never shows the default login's figure.
    - its output carries `account` (a hash of the uuid) and the label from question 4.
  - `dashboard.sh`: before `cached claude-usage`, an account different from the cached file's removes the
    cached reading and its retry note. The history moves aside to `limit-history.<hash>.jsonl`.
  - `dashboard/app.js`: the panel's title line names the account label.
- **Red first,** `scripts/__tests__/dashboard-billing.test.sh` (it drives `dashboard_limit.py` today), on a
  scratch HOME, off a Mac (`COMMANDECK_HOST_OS=Linux`), with a stub usage server through the existing seam:
  - a reading cached for account A, then a config folder whose `.claude.json` names B: the old figure is gone,
    and B's reading replaces it.
  - the history starts empty for B.
  - the panel JSON names B's label.
- **Done:** those pass. A config folder whose credentials cannot be read says so and shows no figure.
  **Size:** about 60 code lines and 50 test lines.

## Item 4. Issue 242: a shared plan and build worktree splits its cost by time

- **Cause, read:** `scripts/dashboard_limit.py:980`,
  `build, planned = mine(wt) if wt != pwt else [], mine(pwt) if plan else []`. When the plan seat cut the unit's
  worktree and the Builder took it over (`seat.sh:70`, `plan-worktree-close.sh --adopt`), `wt == pwt`. Every
  request then lands in "planning", and the Builder's and reviewers' requests fall under "Not tied to a seat".
- **Change:** the issue's own fix. When `wt == pwt` and the unit has stages, take `mine(wt)` once:
  - `planned` is the rows before `epoch(u["stages"][0]["from"])`;
  - `build` is the rest.
  With no stages, everything stays in planning. That keeps the planning worktree's own card, described in the
  docstring at `:940`.
- **Red first,** `scripts/__tests__/dashboard-built.test.sh`, beside the `unit_costs` cases (`:163`, `:177`): one
  worktree as both plan and build. One planner request before the first stage, one Builder request in
  "building", and one Codex request in a pass stage. Each one's cost is on its own stage row, and the total is
  unchanged. Red today: all three are on "planning".
- **Done:** that passes, and the existing cases at `:163` and `:177` are unchanged. **Size:** about 5 lines and
  35 test lines.

## Item 5. Issue 217: two pages folding at once keep both folds

- **Cause, read:** `dashboard/app.js` `merge` (`:1690-1708`). `collapsed` and `hidden` are arrays of ids, so they
  take neither the map branch (`plain(own) === own`) nor the `closed` union. They take
  `else if (!same(own, was)) v = own`, so the page that saved last replaces the whole list.
- **Change:** for `collapsed` and `hidden`, take the host's list (`theirs`), add this page's additions
  (`own - was`) and take out its removals (`was - own`). `order` is a sequence and keeps its current rule.
  `hidden` has the same cause on the same line, so the one change fixes it too. The commit body names it.
- **Red first,** `scripts/__tests__/dashboard-view.test.mjs`, beside the existing 409 case (`:57-80`): two pages
  at revision 3. Page A folds `limit-body` and saves. Page B folds `permanent`, gets the 409 and recovers. The
  saved layout is `collapsed: ["limit-body", "permanent"]`, in either order. Also: page B unfolds a section that
  page A had folded before both read the layout; page A's other fold stays.
- **Done:** those pass, and the existing 409 cases are unchanged. **Size:** about 8 lines and 30 test lines.

## Item 6. Issues 216 and 215: the wait budget reads inside shell strings

- **Cause, read:** `hooks/no-poll-loops.sh:202-232` sums the waits of `JOINED`. There, a quoted span is the
  single word `QUOTED` (`:82`), so the script of `bash -c 'sleep 400'` is never read. `strip-quoted.sh` reads
  `$'...'` and `$"..."` as `$` followed by a quoted span, so `$'sleep'` reads as data.
- **Change** (question 2, recommended answer):
  - In the Python part of the budget, for a command whose `run()` name is `bash`, `sh` or `zsh` with `-c <script>`,
    or `eval <args>`, or `env -S <string>`, take the raw words of that segment (`shlex.split` on the segment of
    `CMD_CODE`). Then sum the inner script's waits by the same rules, recursively. When `shlex` cannot read it,
    return `None`: the "cannot read a wait" refusal at `:246` says why.
  - `strip-quoted.sh`: `$'` and `$"` open a quoted span, as bash reads them. Each prints its mark like any other
    span, so `$'sleep'` is the word `sleep`.
  - The hook header lists the gaps left open on purpose: a command word built by expansion, a wrapping function
    or alias, and the over-block `"a b""sleep"`.
- **Red first,** `hooks/__tests__/no-poll-loops.test.sh`, worker pane:
  - `bash -c 'sleep 400'`, `sh -c "sleep 400"`, `zsh -c 'sleep 300'`, `eval 'sleep 400'` and
    `env -S 'sleep 400'` are each refused.
  - `bash -c 'sleep 100'` passes.
  - `bash -c 'echo hi'` passes.
  - `$'sleep' 400` and `$"sleep" 400` are refused.
  - `bash -c 'for i in 1 2; do sleep 1; done'` is refused as a loop.
- **Done:** those pass. The 0.20.0 cases do not change. `git-safety.test.sh` and `duplicate-agent-guard.test.sh`
  pass, since they share `strip-quoted.sh`. **Size:** about 30 hook lines, 10 lexer lines and 30 test lines.

## Item 7. Issue 238: no restart or stopped alert for a pane that has already healed

- **Cause, read:** `scripts/main-watch.sh:456-459` tells the relay "restart main" after `WAKE_TRIES` typed wakes
  were not proven. It never checks whether main's pane has since been replaced by a new session. A
  `context-clear-stop.sh` restart writes `<checkpoint>.restarted`, and the new pane's session log starts after
  the stamp. `:806-809` posts "stopped without reporting" from one reading of the seat's state, so a seat that
  is still working but read as idle for one tick is posted. The issue names `cos-watch-alerts.sh` and
  `dashboard_alerts.jq`. Those are the sibling project's files: in this plugin both alerts come from
  `main-watch.sh`.
- **Change:**
  - Before the restart line, look up main's live pane (`pp_pane_of`). If a session log under main's checkout
    was written after the wake's first try, or a newer `.restarted` stamp exists, drop the wake and tell
    nothing.
  - Before the stopped post, read the pane again (one `terminal show`). Post only when it is still not working
    and its session log has not grown since the first reading.
- **Red first,** `scripts/__tests__/main-watch-helper-hold.test.sh` (or the file that holds the wake cases after
  item 2):
  - wake tries used up, but main's session log is newer than the stamp: the relay hears nothing.
  - the same with no newer log: the relay hears "restart main". This pins what is kept.
  - a seat read as stopped whose log grew between the two readings: no post.
- **Done:** those pass. **Size:** about 20 lines and 35 test lines.

## Item 8. Issue 221: the merge checks its own commit message

- **Cause:** nothing in the plugin checks a commit message. `ci/leak-test.sh` lists files (`:17-19`). In this
  repository a leak in a message surfaces only when the owner reviews it after the push.
- **Change** (question 3, recommended answer):
  - `ci/leak-test.sh --text <file>` searches one file with the word list and the two allowed texts. It reuses the
    existing exemption code, the part after `:55`.
  - `scripts/merge-unit-local.sh`, step 4, after `TITLE` and `MUTATIONS` are final (`:251`) and before
    `git merge --squash`:
    - write the message to a temp file;
    - run the generic patterns: a home path, and `hostname -s` when it is longer than 3 characters;
    - run `"$ROOT/ci/leak-test.sh" --text <file>` when the project has that file.
    A match refuses with `FAILED step 4 message: <line>` before anything is merged.
- **Red first:**
  - `scripts/__tests__/merge-unit-local.test.sh`: a unit whose commit subject holds `/home/someone/x` is
    refused, the line is named, and main is unchanged.
  - A unit whose subject holds a word from a fixture `ci/leak-words.txt` is refused.
  - `ci/leak-test.sh --text` on a clean file exits 0.
- **Done:** those pass. `bash ci/leak-test.sh` with no argument is unchanged. **Size:** about 30 lines and
  30 test lines.

## Item 9. Issue 239: the merge closes the unit's issues

- **Change** (question 7, recommended answer): `scripts/merge-unit-local.sh`, after the merge commit (step 4
  evidence, `:302`) and before cleanup:
  - for each issue number that `brief-issues.sh "$BRIEF"` lists, and that the squash commit's subject or body
    names (`(#N)` refs, `:216`), run
    `gh issue close N --comment "Fixed in <sha> (<version>); ships with the next push."`.
  - An issue that the brief lists but the commit does not name stays open, and is named on a
    `step 4 issues: left open:` line.
  - A failed close prints a `NOT CLOSED:` line with its command and exits 3 (merged; finish by hand). This is the
    same shape as the existing `NOT FILED` path.
  - The brief's "Close as shipped" issues (already shipped before the unit) are closed the same way when the
    brief lists them under that heading.
- **Red first,** `merge-unit-local.test.sh` with a `gh` stub that records its calls:
  - a brief with items `#5` and `#6`, a commit that names only `#5`: `issue close 5` is called once, 6 is named as
    left open.
  - a `gh` that fails: exit 3 and a `NOT CLOSED:` line.
  - `--dry-run` closes nothing.
- **Done:** those pass. **Size:** about 25 lines and 35 test lines.

## Item 10. Issue 243: the full suite runs before the final pass, and its result binds the GO

- **Change:**
  - `scripts/builder-codex-pass.sh`, `final` kind, when the install has `fullSuiteBeforeFinal: true`
    (item 11):
    - before the reviewer starts, run `.testCommand`, with `--changed` taken off when it is present, on the
      worktree's tip, under `run-bound.sh` with the step's own cap;
    - save the output to `<unit scratch>/suite-<sha8>.log`;
    - put the path and the summary (passed / failed / timed out, totals, tip, duration) in the prompt;
    - the prompt says: GO only when the run is green for this exact tip.
    - A red run lets the pass go ahead. The round file records it, and the pass's own verdict line becomes NO-GO
      with the failing test named. A NO-GO needs no reviewer's word.
    - No tests ran (no test command): the pass refuses to start and names the setting.
  - The round file gets one line, `Suite: <sha> <pass|fail> <totals> <secs>s <log path>`.
  - `--verify` (the merge's gate) refuses a closing GO whose round file has no green `Suite:` line for the tip,
    when the setting is on.
- **Red first,** `scripts/__tests__/builder-codex-pass.test.sh` (stubbed reviewer, as today):
  - a test command that fails: the round file ends NO-GO, and the failing name is in it.
  - a green command: its `Suite:` line is in the round file and in the prompt.
  - `--verify` on a closing GO with the setting on and no `Suite:` line: refused.
  - the setting off: no run, and the pass behaves as it does today.
- **Done:** those pass. For this repository the setting is on (item 11, `.claude/commandeck.json`). **Size:**
  about 55 lines and 60 test lines.

## Item 11. Issue 244: setup asks whether the full suite runs before the final review

- **Change:**
  - `skills/setup/SKILL.md`, after the merge-check question: `Ask "Full suite before the final review": On
    (recommended) | Off`. "On" is recommended when the suite is known to take under about 10 minutes. The
    description says: "one full run of <testCommand> per build; catches failures a static review misses".
  - The question is skipped when no test command is set. Then setup records `false` and prints one line.
  - `scripts/setup.sh`: a new `--full-suite on|off` flag goes into `TAKES` (`:55`). It is saved as
    `fullSuiteBeforeFinal`, read back as the saved answer (`old .fullSuiteBeforeFinal`) and shown in the plan.
  - `doctor` reports it. This repository's own `.claude/commandeck.json` gets `"fullSuiteBeforeFinal": true`.
- **Red first:**
  - `scripts/__tests__/plugin.test.sh`: the question is in SKILL.md with exactly one "(recommended)", as the test
    at `:148` holds for every question.
  - a setup flag test (the file that drives `setup.sh --plan` today) on a scratch HOME: `--full-suite on --plan`
    shows it, and a re-run without the flag keeps it as saved.
  - with no test command, it records off.
- **Done:** those pass, and item 10's tests read the key. **Size:** about 25 lines and 25 test lines.

## Item 12. Issue 225: two NO-GOs on the same finding class stop the loop

- **Change:**
  - The pass prompt (`builder-codex-pass.sh`, the findings format) asks for each finding's class as one short
    tag: `[P2] (class: old-format-case) <title>`.
  - `scripts/read-verdict.sh` compares the classes of the last two passes. When the same class appears in two
    NO-GOs in a row, it prints `REPEAT CLASS: <class> (r<N-1>, r<N>)`.
  - `scripts/orca-wait.sh`'s `next:` line (`:339`) then says
    `next: ask the owner one class-level question, or merge and file the rest as one issue (two NO-GOs on <class>)`.
  - `templates/main-session.md` (the Details part) gets the rule. `templates/_builder-brief-template.md` says a
    fix-round brief lists every variant of the class.
- **Red first:**
  - `scripts/__tests__/read-verdict.test.sh`: two round files whose NO-GOs share `(class: x)` print
    `REPEAT CLASS: x`. Different classes print nothing.
  - `orca-wait.test.sh`: the next line names the class.
- **Done:** those pass. **Size:** about 35 lines and 30 test lines.

## Item 13. Issue 236: seat.sh collect keeps the full report at a stable path

- **Cause:** `seat.sh collect` writes a report only when `--report` is given (`:404`, `:427-431`). Otherwise the
  findings live only in the pane.
- **Change:**
  - With no `--report`, the report goes to `$SCRATCH/reports/<unit>-<role>-<launched>.md`.
  - `collect` prints `report: <path>` and records `report=<path>` in the seat record.
  - `read-verdict.sh --seat <unit> <role>` reads that path.
- **Red first,** `scripts/__tests__/seat.test.sh` (the file that drives `collect` today):
  - a collect with no `--report` prints a path, and the file holds the findings.
  - `read-verdict.sh --seat` prints the same verdict.
- **Done:** those pass. **Size:** about 15 lines and 20 test lines.

## Item 14. Issue 237: check the merge gate before offering a merge

- **Change:** `templates/main-session.md:27`. The NO-GO line already sends main to the owner before a P2-tail
  merge. It gains: "Before offering a merge, run
  `builder-codex-pass.sh --verify <worktree> <unit> <tip>`, the merge's own gate. When it refuses, offer the pass
  it names instead." `orca-wait.sh` already prints "merge it" only when `--verify` passes (`:331-339`).
- **Red first:** `hooks/__tests__/agent-startup-context.test.sh`: main's print carries `--verify` in that rule.
- **Done:** that passes, within item 22's size room. **Size:** 1 template line and 1 test line.

## Item 15. Issue 233: seat.sh launch returns once the pane exists

- **Cause, read:** `seat.sh launch` writes its record at `:351`. That comes after `terminal create` (`:269`), a
  `tui-idle` wait of up to 120 s (`:284`) and the dispatch retries of up to 60 s (`:320`). A launch whose caller
  times out leaves a live pane with no record, and a retry launches a second one.
- **Change:**
  - Write the record with `phase=launching` (handle, role, unit, spec hash) straight after `:269`.
  - Run the rest in a detached child that updates `phase=dispatched|failed`, logging to `$REC.log`.
  - Print `handle=<h> task=<t> phase=launching` and exit 0.
  - `seat.sh status <role> <unit>` prints the record's phase, handle, task and the log's last line.
  - A second launch for the same unit and role, while the record's pane is live or the seat has not been
    collected, is refused with the status line. `COMMANDECK_SEAT_FORCE=1` still reruns a finished spec.
- **Red first,** `seat.test.sh` with the Orca stub:
  - launch returns before the stub's `tui-idle` wait ends.
  - `status` shows `launching`, then `dispatched`.
  - a second launch while the first is live is refused.
  - a stub dispatch failure ends in `phase=failed`, and the log names the cause.
- **Done:** those pass, and `builder-launch.sh`'s plan-seat path is unchanged. **Size:** about 60 lines and
  50 test lines.

## Item 16. Issue 234: a new unit opens only on an order that names it

- **Cause:** nothing checks that an order names a new unit. The plugin has no order files. The order reaches
  main as the relay's `to-main.sh question` with the owner's words verbatim (`hooks/agent-startup-context.sh:116`),
  and main writes the brief.
- **Change:**
  - `templates/_batch-brief-template.md` gets a required `## Launch` section with
    `Launch: new unit <unit> | add to <unit>` and `Order: <the owner's words verbatim>`.
  - `scripts/builder-launch.sh` refuses a brief whose Launch line is missing, names another unit, or says
    `add to`. For `add to`, it points to `builder-add-work.sh`. This is the same refusal shape as the required
    `## Prior art` and `## Plan` sections (`:41`).
  - `seat.sh launch`, for a plan seat whose launch would create the unit's worktree, refuses a spec without the
    same `Launch: new unit <unit>` line.
- **Red first,** `scripts/__tests__/builder-launch*.test.sh` and `seat.test.sh`:
  - a brief with no Launch line, with `add to x`, or naming another unit: each is refused with the reason.
  - `Launch: new unit <unit>` goes ahead.
  - The existing fixture briefs gain the line.
- **Done:** those pass. **Size:** about 30 lines and 50 test and fixture lines.

## Item 17. Issue 222: every script prints its usage on --help and does nothing else

- **Cause:** 56 scripts under `scripts/` do not handle `--help` or `-h` (checked while planning). `to-main.sh`
  would read `--help` as a message type and send it.
- **Change:** each script that runs has, before it sources anything or reads state:
  `case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac`
  (or the script's existing `usage`). That prints its signature lines from the header. The sourced libraries are
  skipped (`paths.sh`, `install-lib.sh`, `host-services.sh`, `project-main.sh`, `cos-lib.sh`, `requirements.sh`).
  The optional usage card in the startup context is not built: main's print has 286 bytes of room (item 22).
- **Red first,** a new `scripts/__tests__/help.test.sh`, on a scratch HOME with an `orca-ide`/`orca`/`gh` stub
  on `PATH` that records any call:
  - for every runnable script, `--help` exits 0, prints at least one line, makes no stub call, and leaves the
    scratch HOME's file list unchanged.
  - Red today for `to-main.sh`, `cos-tell.sh`, `answer-worker.sh` and `board.sh`.
- **Done:** that passes. **Size:** about 56 one-line edits and 45 test lines.

## Item 18. Issue 223: orca-wait.sh and board.sh default to a compact form under 3 KB

- **Cause:** `orca-wait.sh` prints a `heads-up:` body whole (`:13`, `:269`), and up to 60 lines of any other
  message (`:15`). `board.sh` prints every worktree's diffstat and every task.
- **Change:**
  - Both default to one line per item, with each message's or unit's full text in a named file under the run's
    scratch folder. `orca-wait.sh` keeps `--full`, and `board.sh` gains `--full`.
  - The default output is cut at 3,000 bytes, with a closing line naming the file that holds the rest.
- **Red first:**
  - `orca-wait.test.sh`: a 20 KB heads-up prints its subject line and a path, under 3,000 bytes, and the file
    holds the body.
  - `board.test.sh`: a fixture with 30 worktrees stays under 3,000 bytes.
  - `--full` prints the whole.
- **Done:** those pass. Main's pane gets nothing it got before only in full: `next:` and NEEDS-MAIN lines are
  never cut. **Size:** about 35 lines and 25 test lines.

## Item 19. Issue 229: one summary line per relay watcher wake

- **Change:**
  - Each `scripts/cos-watch-*.sh` ends a wake with one line under 1,500 characters: what woke it, the count, and
    the file that holds the rest.
  - `hooks/agent-startup-context.sh`'s relay block says to read at most the last 600 characters of a watcher's
    output.
  - The relay block gets one rule: a task that would read more than about 10 KB it will not need again goes to a
    subagent that answers in at most 40 lines.
- **Red first,** `scripts/__tests__/cos-tell.test.sh` (which drives the watchers today): a wake with 30 queued
  messages prints one line under 1,500 characters that names the file.
  `hooks/__tests__/agent-startup-context.test.sh`: the relay's print carries the 600-character and subagent rules.
- **Done:** those pass, and the relay print stays under the limit (`startup-size.sh`, chief-of-staff 3,048 bytes
  today). **Size:** about 20 lines and 20 test lines.

## Item 20. Issue 231: a relay-order helper and a picker template

- **Change:**
  - New `scripts/relay-order.sh <decision id> '<the owner's words verbatim>'`. It takes the newest ruling id that
    `ruling-log.sh` logged for those words. It answers the decision (`decision.sh answer <id> <words>`, with no
    `--asked-at`, so `askedAt` is looked up), sends main the order (`to-main.sh question`) and appends the
    `seen` value to the state file that the relay block names. It prints one line.
  - The relay block's decision line (`hooks/agent-startup-context.sh:114`) names the helper.
  - A picker template line: one question per picker. The decoy is first only in a single-question picker
    (`hooks/lib/ask-decoy.sh`).
- **Red first,** a new `scripts/__tests__/relay-order.test.sh` with Orca stubbed: an open decision and a logged
  ruling. The ledger is answered, main's stub gets the order with the ruling id, and the seen file gains one
  line. An unknown id changes nothing and exits 1.
- **Done:** that passes. **Size:** about 40 lines and 35 test lines.

## Item 21. Issue 232: rulings checked before a picker, empty answers read back, a picker time-box

- **Change:**
  - The relay block and `templates/main-session.md` (Details) get two rules. Before a picker, search the rulings
    log for the topic (`ruling-log.sh`'s file) and answer from a ruling that covers it. Keep the decoy out of a
    multi-question picker.
  - `hooks/ruling-log.sh` (PostToolUse on AskUserQuestion) prints the retry text, "the answer came back empty;
    ask it once more as a single question", and records no answer, when an answer is empty or is the decoy's
    label.
  - Question 6, recommended answer: `main-watch.sh` raises the "picker open 30 min" alert. The pane read for it
    is the one item 7 adds.
- **Red first:**
  - `hooks/__tests__/ruling-log.test.sh`: an empty answer prints the retry text and leaves the decision open.
  - main-watch's test: a relay pane in a question prompt for 31 min with 2 messages queued raises the alert; at
    29 min it does not.
- **Done:** those pass. **Size:** about 40 lines and 35 test lines.

## Item 22. Issue 228: main's startup print is held in the hook, with room made for this build's rules

- **What is there:** `resume-context.sh` already holds the resume block under 10,240 bytes, and parts that do
  not fit become pointer lines. `startup-size.sh` holds each hook's print in CI. Measured at 3e588fe: main's
  `agent-startup-context.sh` prints 9,954 of 10,240 bytes, so 286 bytes are left. `opus-orchestrator-autonomy.sh`
  prints 1,938. Items 14, 23 and 24 add rule lines to main's print, about 900 bytes.
- **Change:**
  - `agent-startup-context.sh` caps its own print the way `resume-context.sh` does (its `capped`). A part past
    the cap becomes one pointer line, so a project's long rule file cannot cross the line live.
  - Move the parts of the injected `templates/main-session.md` that main does not use every turn into "Details
    (not injected)", with a pointer line. Make room for items 14, 23 and 24 plus 1,000 bytes. The Builder lists
    what moved, measured with `startup-size.sh`.
  - `templates/checkpoint.md`: task ids, paths and live jobs are not written by hand. `board.sh`, which the
    resume block already carries, prints them.
- **Red first:** `hooks/__tests__/agent-startup-context.test.sh`: a project whose rule file is 20 KB gets a print
  under 10,240 bytes that ends with a pointer line. `startup-size.sh` main is 9,000 bytes or less after items 14,
  23 and 24.
- **Done:** those pass. **Size:** about 15 code lines, 30 moved template lines and 15 test lines.

## Item 23. Issue 230: the do-not list, a merge that backgrounds itself, board.sh --unit --seats

- **Change:**
  - `templates/main-session.md`, at the top of the injected rules: five "do not -> instead" lines, each with its
    command. They cover the blocks main meets: a re-read the wake already printed, a long job in its own pane, a
    raw pane read, an in-place write, and an unbounded grep. The Builder takes the list from the hooks' own
    BLOCKED texts.
  - `scripts/merge-unit-local.sh` and `scripts/run-shell-tests.sh`, when run in main's foreground (main checkout,
    not under `MERGE_UNIT_LOCAL_LOCK`, stdin a terminal or `CLAUDECODE` set, and not `--dry-run`), restart
    themselves detached. The log goes to `<scratch>/merge-<unit>.log`, and they print the log path and the pid.
    The result wakes main through `to-main.sh status`.
  - `scripts/board.sh --unit <u> --seats`: each seat record of that unit, one line each (role, handle, phase from
    item 15, verdict).
  - Every BLOCKED message in `hooks/*.sh` that has no replacement command gets one. The Builder lists those it
    changed.
- **Red first:**
  - `merge-unit-local.test.sh`: run as main's foreground, it returns at once with a log path, and the merge then
    completes in the background (the stub run).
  - `board.test.sh`: `--unit u --seats` prints the fixture's two seats.
  - a test over `hooks/*.sh` that every `BLOCKED:` text has a command in backticks or after a colon.
- **Done:** those pass. **Size:** about 45 lines and 45 test lines.

## Item 24. Issue 235: main ends each turn with one status line

- **Change:** `templates/main-session.md`, injected: "End each turn with one status line. Write a longer report
  only when the owner asks for one or a decision needs the detail."
- **Red first:** `agent-startup-context.test.sh`: main's print carries "one status line".
- **Done:** that passes. **Size:** 1 template line and 1 test line.

## Item 25. Issue 227: action scripts close their own item task

Built as question 5's recommended answer. If the owner answers "close it", this item is dropped.

- **Change:** `merge-unit-local.sh` (after DONE), `answer-worker.sh` (after a delivered answer) and `seat.sh
  collect` (after a verdict) complete the open main-watch item task of their unit or seat. Each one finds it
  with `orca-wait.sh --close`, as main does by hand today.
- **Red first:** each script's test, with the Orca stub: one open item task for the unit is completed after the
  action, and a task of another unit is left open.
- **Done:** those pass. **Size:** about 15 lines and 25 test lines.

## Item 26. Issue 224: cards for main and the Chief of Staff

- **Change:**
  - `scripts/dashboard.sh` reads main's sessions: the main checkout's projects folder. That is the folder
    `unit_costs` leaves out today (`dashboard_limit.py` docstring at `:935`). The relay's sessions are the
    `Chief-of-Staff` worktree's folder.
  - A new `dashboard_limit.py seats` subcommand returns, for each of the two seats: context against its line
    (`hooks/lib/context-size.sh`, `pp_clear_line`), tokens and list cost today, the 7-day daily average,
    restarts today with the average gap (`<checkpoint>.restarted` stamps and `clear-hook.log`), and the restart
    times.
  - `dashboard/index.html`, `app.js` and `app.css` get two cards in the existing card style. The relay card shows
    only when a relay is configured. No new collector.
- **Red first:**
  - `dashboard-built.test.sh`: fixture sessions for main and the relay, and two restart stamps. The seat JSON has
    the cost, the 7-day average and the restart count.
  - `dashboard-view.test.mjs`: both cards render the figures, and the relay card is absent with no relay.
- **Done:** those pass. **Size:** about 190 lines and 70 test lines.

## Item 27. Issue 240: answer a decision from the "Needs me" panel

Built as question 8's recommended answer.

- **Change:**
  - `scripts/decision.sh add ... [--options '<a>|<b>[|<c>[|<d>]]']` stores 2 to 4 options.
    `ask-records-decision.sh` fills them from the picker's labels, with the decoy left out.
  - `scripts/dashboard_serve.py`: a `POST /answer` endpoint, `{id, askedAt, answer}`.
    - It refuses a non-loopback client address, or a `Host`/`Origin` that is not the server's own, with 403.
    - It runs `decision.sh answer <id> <answer> --asked-at <askedAt>`, so a second answer is refused with "already
      answered" (409). It logs a ruling the way `ruling-log.sh` does.
    - It sends main `to-main.sh question '<decision id>' '<answer> (ruling <id>)'`, and tells the relay with
      `cos-tell.sh --note` when one is configured.
    - A failed send is kept in a retry file and sent again on the next refresh. The card shows it.
  - `dashboard/app.js`: option buttons (the default marked), an "Other" box, and the answered state. These
    controls show only when the page is loaded from a loopback address.
- **Red first:**
  - `scripts/__tests__/dashboard-serve.test.sh`:
    - a POST from a non-loopback address is refused, and so is one with a foreign `Origin`.
    - a loopback POST answers the ledger, logs the ruling, and the `to-main.sh` stub gets the message.
    - a second answer to the same id gets 409.
    - a failed send is retried.
  - `decision.test.sh`: `--options` stores at most 4 options.
  - `dashboard-view.test.mjs`: the buttons show on a loopback page and not on another host.
- **Done:** those pass. **Size:** about 170 lines and 90 test lines.

## Item 28. Issue 247: Builders batch, read by range and edit through Edit

- **Change:**
  - `templates/_builder-brief-template.md`: three rule lines. Batch independent looks. Use `grep -n` first, then
    read by range. Use a symbol lookup before grep-and-read.
  - `hooks/batch-independent-looks.sh`: a Builder seat (`COMMANDECK_BUILDER=1`) hears the nudge at its second lone
    look in a row. Other seats keep 3.
  - A new PreToolUse hook on Read (`hooks/read-range-guard.sh`, Builders only) refuses a Read with no
    `offset`/`limit` of a file over 400 lines, and names a range. `hooks.json` registers it.
  - `hooks/builder-search-guard.sh`: an advisory note when a grep pattern is one bare identifier
    (`^[A-Za-z_][A-Za-z0-9_]{3,}$`), naming the symbol lookup to use.
  - `hooks/bash-guardrails.sh` (question 11, recommended answer), Builders only: an inline `python3 -c`, a
    `python3 - <<`, `perl -e` or `node -e` whose text opens a tracked path for writing is refused and pointed
    to Edit. A scratch path (`$TMPDIR`, the unit's scratch folder) is allowed.
- **Red first:**
  - `batch-independent-looks.test.sh`: a Builder nudged at 2, a planner at 3.
  - a new `read-range-guard.test.sh`: an unranged 500-line read is refused, a ranged one passes, a 100-line file
    passes.
  - `builder-search-guard.test.sh`: `rg -n strip_quoted` gets the note, `rg -n 'a.*b'` does not.
  - `bash-guardrails.test.sh`: `python3 -c "open('scripts/x.sh','w').write(...)"` in a Builder is refused, and the
    same write to `$TMPDIR/x` passes.
- **Done:** those pass. **Size:** about 85 lines and 80 test lines.

## Item 29. Issue 249: the batching hook stops paying a fixed 1.5 s on a nudging call

- **Cause, measured while planning** on this Mac, with a 93,886-line transcript: an ordinary run takes 0.055 s
  (`tail` + `jq -s` 0.008 s, `strip_quoted` 0.002 s). The sibling project's 1.73 s median comes from the nudge
  path. There, every call at the threshold sleeps `SIBLING_MS` (1.5 s, `hooks/batch-independent-looks.sh`, the
  `sleep` before the second `count_calls`) so that siblings can land. With the hook on only for planners, most of
  its runs in a build are nudge-path runs.
- **Change:** replace the fixed sleep with a poll. Run `count_calls` every 100 ms for up to `SIBLING_MS`, and
  stop as soon as a sibling appears or a later message is on disk. When nothing changes, the nudge goes out as
  it does today. What it nudges does not change.
- **No red test** (speed). `batch-independent-looks.test.sh` stays green, and a case where a sibling lands at
  200 ms ends the wait within 400 ms. **Done:** the median per-run time on the nudge path is measured before and
  after on the same transcript and recorded in the commit body; it falls when siblings come quickly. **Size:**
  about 10 lines and 10 test lines.

## Item 30. Issue 248: bash-guardrails.test.sh takes a case filter

- **What is there:** the plugin's file has 37 cases and runs in 6 s (measured), so the saving is small here. The
  filter is still cheap, and it is the same shape as `INSTALL_LIB_TEST_CASE` (`install-lib.test.sh:11-12`, `:384`).
- **Change:** `BASH_GUARDRAILS_TEST_CASE=<text>` checks only the cases whose name holds the text. An unmatched
  filter fails ("no case matched"), and the count is printed. `templates/_builder-brief-template.md`'s test line
  names the filter for red runs and fix rounds. The closing run stays the whole file.
- **Red first:** `bash-guardrails.test.sh` run with a filter that matches 1 case reports 1. A filter that matches
  none exits 1.
- **Done:** those pass, and the unfiltered run is unchanged. **Size:** about 4 lines, 8 test lines and 1 template
  line.

## Item 31. Issue 246: red-proof.sh refuses a whole run of a case-aware file, and batches

- **Cause:** the plugin's `red-proof.sh` takes a free test command (`:2`) and makes one scratch worktree per call
  (`:26-37`). It has no `--case`. A file is case-aware when it reads a `*_TEST_CASE` variable:
  `install-lib.test.sh` today, and `bash-guardrails.test.sh` after item 30.
- **Change:**
  - Refuse when the test command runs a case-aware file and does not set that file's variable. The refusal
    names the variable.
  - `red-proof.sh --batch <file>` takes `<file>\t<line>\t<replacement>\t<test command>` lines and runs them all
    in one scratch worktree, restoring the file between proofs.
- **Red first,** `scripts/__tests__/red-proof.test.sh`:
  - `-- bash scripts/__tests__/install-lib.test.sh` without `INSTALL_LIB_TEST_CASE` is refused.
  - with it set, the proof runs.
  - a batch of two proofs makes one worktree (counted with `git worktree list` during the run, or through the
    stub) and reports both.
- **Done:** those pass. **Size:** about 35 lines and 35 test lines.

## Item 32. Issue 250: Codex reviewers can run read-only probes of the guards under review

Built as question 10's recommended answer.

- **Change:**
  - New `scripts/hook-probe.sh <hook> '<command>' [--tool Bash]` builds the hook's payload. It runs the hook with
    `HOME`, `TMPDIR` and `COMMANDECK_HOOK_FIRE_LOG` in a new scratch folder and prints
    `allow | refuse (<exit>) | ask` and the hook's message.
  - The reviewer roles in `config/routing.json` (`codex-reviewer`, `audit-auditor`) run `workspace-write` with
    the scratch folder as the working folder. The prompt names the repository path to read and the probe script.
  - The pass prompt for a change under `hooks/` asks for at least one executed probe in the report.
- **Red first:**
  - a new `hook-probe.test.sh`: `hook-probe.sh hooks/no-poll-loops.sh 'sleep 400'` prints refuse in a worker
    payload, and writes nothing outside its scratch folder (HOME's file list is unchanged).
  - `builder-codex-pass.test.sh`: a pass over a change to `hooks/` has the probe line in its prompt.
  - `plugin.test.sh`: the reviewer roles' sandbox and working folder are as described.
- **Done:** those pass. The Builder records the Codex documentation it checked. **Size:** about 45 lines and
  35 test lines.

## Item 33. Issue 245: Commandeck's settings as plugin options

Built as question 9's recommended answer.

- **Change:**
  - `.claude-plugin/plugin.json` gets a `userConfig` block with the first set from question 9. Each option has
    `type`, `title` and `description`, a default equal to setup's recommended answer, and `options` where setup
    offers a fixed choice. The Builder first checks the field names against the Claude Code plugin manifest
    reference. CI's pinned CLI (2.1.302) is newer than the 2.1.271 that `options` needs.
  - New `scripts/lib/plugin-option.sh`, `plugin_option <key>`, reads in this order:
    `CLAUDE_PLUGIN_OPTION_<KEY>`; `pluginConfigs.commandeck` in `${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json`;
    the project's `.claude/commandeck.json` key; the default.
  - The readers of those keys use it (the Builder lists each reader it changed).
  - `doctor` prints each option's effective value and its source.
  - Setup pre-fills `pluginConfigs` from the owner's answers only when the key is not already there.
  - README: the minimum Claude Code version, if `options` is used.
- **Red first:**
  - a new `plugin-option.test.sh` covers the precedence order with each source present or absent, for one
    boolean, one picker and one number.
  - `plugin.test.sh`: every `userConfig` key has a reader, and every default equals setup's recommended answer.
  - `doctor`'s test names the source.
- **Done:** those pass, and `claude plugin validate .` passes. **Size:** about 170 lines and 85 test lines.

## Version

- `.claude-plugin/plugin.json`: `0.20.0` to `0.21.0` (new behaviour: the second part, per `ci/version-check.sh`).
  `README.md:4`, the badge's URL and alt text, follows it: `plugin.test.sh:33` holds both to the manifest.
- `.claude-plugin/marketplace.json` has no version field, and `plugin.test.sh` holds none there, so there is
  nothing to bump in it. The brief asked for it. The plan does not add the field, because the plugin's own
  manifest carries the version that updates read.
- `CHANGELOG.md`: `## 0.21.0 -- <date>` on top, one bullet per item 1 to 33 with its `#N`. It also says:
  - issues 203-214 shipped in 0.20.0, and 251 was already met (written with `#` there, as CHANGELOG.md does);
  - a worker's `bash -c` wait now counts against the cache budget;
  - the merge now checks its message and closes its issues;
  - the full suite runs before the final review where it is turned on.
- About 45 changed lines.

## Order of work: each shared file is touched once

| Step | Items | Files |
|---|---|---|
| 1 | 1 | ask-records-decision.sh and its test |
| 2 | 2 | main-watch-helper-hold.test.sh (maybe split), maybe main-watch.sh's tick path |
| 3 | 3, 4, 26 | dashboard_limit.py, dashboard.sh, agent-startup-context.sh's main line, dashboard-billing and dashboard-built tests |
| 4 | 5, 26, 27 (page) | dashboard/app.js, app.css, index.html, dashboard-view.test.mjs |
| 5 | 6 | no-poll-loops.sh, strip-quoted.sh, their tests |
| 6 | 7, 21 (alert), 25 | main-watch.sh and its test |
| 7 | 8, 9, 23 (merge), 25 (merge) | merge-unit-local.sh, ci/leak-test.sh, merge-unit-local.test.sh |
| 8 | 10, 11, 12 (prompt), 32 (prompt) | builder-codex-pass.sh and its test; setup.sh, SKILL.md, doctor; .claude/commandeck.json |
| 9 | 12, 13, 15, 16, 23 (board), 25 (seat) | read-verdict.sh, seat.sh, board.sh, builder-launch.sh, orca-wait.sh and their tests |
| 10 | 17, 18 | every scripts/*.sh (one line each), help.test.sh; orca-wait.sh, board.sh |
| 11 | 19, 20, 21, 27 (decision) | cos-watch-*.sh, relay-order.sh, ruling-log.sh, decision.sh, dashboard_serve.py, agent-startup-context.sh's relay block |
| 12 | 22, then 14, 23, 24, 12 (rule) | templates/main-session.md, checkpoint.md, agent-startup-context.sh's cap, its test |
| 13 | 28, 29, 30, 31 | _builder-brief-template.md, batch-independent-looks.sh, read-range-guard.sh, builder-search-guard.sh, bash-guardrails.sh and its test, red-proof.sh |
| 14 | 32, 33 | hook-probe.sh, config/routing.json; plugin.json, plugin-option.sh, its readers, doctor |
| 15 | version | plugin.json, README badge, CHANGELOG; the whole "Done when" list |

- **Same file, more than one item:**
  - `templates/main-session.md`: items 12, 14, 21, 22, 23 and 24. Item 22 goes first and makes the room that the
    others' injected lines need. Main's print has 286 bytes left today.
  - `hooks/agent-startup-context.sh`: items 3 (main's config-folder line), 19, 20 and 21 (relay block), and 22
    (the cap).
  - `scripts/merge-unit-local.sh`: items 8, 9, 23 and 25, in different steps of the script. Item 23's
    self-backgrounding wraps everything, so it goes last in step 7.
  - `scripts/main-watch.sh`: items 2 (maybe), 7, 21 and 25.
  - `scripts/seat.sh`: items 13, 15, 16 and 25. Item 15's record is what items 23 (`board.sh --seats`) and 25
    read.
  - `scripts/read-verdict.sh`: items 12 and 13. `scripts/orca-wait.sh`: items 12, 17 and 18.
  - `scripts/builder-codex-pass.sh`: items 10, 12 and 32. `--verify` changes only in item 10.
  - `scripts/dashboard_limit.py`: items 3, 4 and 26. `dashboard/app.js`: items 3, 5, 26 and 27.
  - `hooks/bash-guardrails.sh` and its test: items 28 and 30.
  - `hooks/batch-independent-looks.sh`: items 28 (threshold) and 29 (the wait).
  - `templates/_builder-brief-template.md`: items 12, 28 and 30.
  - `scripts/decision.sh`: item 27 (options). Item 20 uses `answer` as it is.
  - `.claude-plugin/plugin.json`: item 33 and the version bump.
  - `scripts/board.sh`: items 17, 18 and 23.
- **Same data:** item 15's seat record (`phase`, `report=` from item 13) is read by items 23 and 25. Item 10's
  `Suite:` line is read by `--verify` and by item 33's option `fullSuiteBeforeFinal`, the key item 11 adds.

## Size

About 2,700 changed lines, twice the 0.20.0 build (about 1,400). 0.20.0's plan estimated 1,060, so this estimate
may also be low. Items 26, 27 and 33 (the three new features) are about 760 of it (question 1).

| Item | Lines |
|---|---|
| 27, issue 240 (panel answers) | 260 |
| 26, issue 224 (seat cards) | 260 |
| 33, issue 245 (plugin options) | 255 |
| 28, issue 247 (Builder reads and edits) | 165 |
| 10, issue 243 (suite before final) | 115 |
| 15, issue 233 (non-blocking launch) | 110 |
| 3, issue 226 (account switch) | 110 |
| 17, issue 222 (--help everywhere) | 100 |
| 23, issue 230 (do-not list, background merge, board --seats) | 90 |
| 16, issue 234 (Launch line) | 80 |
| 32, issue 250 (reviewer probes) | 80 |
| 21, issue 232 (pickers) | 75 |
| 20, issue 231 (relay-order helper) | 75 |
| 6, issues 216 + 215 (wait budget) | 70 |
| 31, issue 246 (red-proof) | 70 |
| 12, issue 225 (repeat class) | 65 |
| 2, issue 218 (slow test) | 60 |
| 9, issue 239 (close issues) | 60 |
| 8, issue 221 (message check) | 60 |
| 22, issue 228 (startup cap, room) | 60 |
| 18, issue 223 (compact output) | 60 |
| 7, issue 238 (healed alerts) | 55 |
| 11, issue 244 (setup option) | 50 |
| 4, issue 242 (cost split) | 40 |
| 19, issue 229 (watcher lines) | 40 |
| 25, issue 227 (tasks closed by actions) | 40 |
| 5, issue 217 (folds) | 38 |
| 13, issue 236 (report path) | 35 |
| 29, issue 249 (hook wait) | 20 |
| 1, issue 241 (no relay) | 19 |
| 30, issue 248 (case filter) | 13 |
| 14, issue 237 (gate rule) | 2 |
| 24, issue 235 (status line) | 2 |
| Version and CHANGELOG | 45 |

## Prior art

- **Item 1:** a check that guards a relay is gated on the relay existing, as a feature flag gates its own
  behaviour. No library.
- **Items 2 and 29:** profile before you optimise. Event-driven waits (wait on the done signal, poll with an early
  exit) rather than fixed sleeps.
- **Item 3:** a cache keyed by the identity that produced it is invalidated when that identity changes, as HTTP's
  `Vary` keys a response by the request header it came from.
- **Item 4:** time-sliced attribution: each request goes to the interval it falls in.
- **Item 5:** set-valued fields merged three-way (base, mine, theirs), as an observed-remove set merges adds and
  removes. No CRDT library: two small sets.
- **Item 6:** recursive descent into `bash -c` and `eval` strings, as ShellCheck reads them, using Python's
  `shlex` (standard library). Fail closed on what cannot be read.
- **Items 8 and 9:** pre-commit secret and identity scanning (gitleaks-style pattern lists). GitHub closes an issue
  when the fixing commit merges. Here the merge is local, so the script does the same through `gh`.
- **Items 10 and 11:** a required status check: a GO counts only with a green run for the same commit, as GitHub's
  protected branches require checks on the head SHA.
- **Item 12:** a stop-loss on repeated failures of one class (a circuit breaker), then a human decision.
- **Items 13, 15 and 25:** an idempotent launch with a persisted record (a pid file, a job id), a status verb, and
  reconcile before retry, as systemd units and Kubernetes controllers do.
- **Item 16:** two-person rule: a new unit needs an order that names it.
- **Items 17 and 18:** POSIX utility conventions (`-h`/`--help` prints usage and exits 0), and paged output with
  the full text in a file.
- **Item 22:** a budget enforced where the data is produced, not only in CI.
- **Item 27:** CSRF defence by Origin/Host checks and loopback binding (OWASP). The first answer wins
  (compare-and-set on `askedAt`).
- **Item 28:** read by range and lookups by symbol (LSP), as Serena and ctags provide.
- **Item 32:** a sandboxed writable scratch area with the repository read-only, as Codex's `workspace-write`
  defines it.
- **Item 33:** Claude Code's own `userConfig` in the plugin manifest, so no settings UI is built.
- This repository has no `.claude/paved-road.md`. Nothing here adds a dependency or a service. Item 27 adds one
  endpoint to the existing dashboard server.

## Not built

- Issue 215 spellings (2), (4) and (5), unless the owner answers question 2 otherwise. They are listed in the
  hook header.
- Issue 222's usage card in the startup context. Main's print has no room for it.
- Issue 227's main-watcher points. Main types no watcher in this plugin (question 5).
- Issue 232's "longer term" durable decision consumer.
- Issue 240's phone answering, unless the owner answers question 8 otherwise.
- Settings left out of question 9's first set: the test command and the relay's name and voice stay with setup.
- Anything without a Commandeck issue. `hidden` in item 5 shares `collapsed`'s cause and line, so it is fixed
  with it. No other fix is added.

PLAN-DONE

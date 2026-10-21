# merge-checkpoint-relay-2026-10-21 -- the merge flow, the restart checkpoint and the relay (one of three units)

Order: the owner, "build ALL open Commandeck plugin issues" (ruling of 2026-10-20, kept by a ruling of 2026-10-21;
the ids are in the plan spec and go in the batch brief, which is untracked: `ci/leak-words.txt` refuses a ruling
id in a tracked file, and this plan is committed to main before the launch). The open issues are split into three units built in parallel; this is one of them.
Scope: 29 issues: 218, 221, 222, 227, 231, 232, 235, 237, 239, 243, 244, 245, 252, 253, 254, 255, 258 (its
merge-gate part only), 259, 267, 275, 281, 283, 284, 290, 293, 300, 305, 306 and 307. Twelve are already met
(item 0) and main closes them. This build is the other 17, items 1 to 16, plus item 17, a cleanup with no issue.
The plugin does not add support for a second machine: issues 296 and 297 are closed as won't-do, and issue 307
carries 297's parts that need no second machine. Issues 223 and 228 are on hold until the host project fixes
them, and are not planned. Issues 283 and 293 are P1 and are built first (see "Priority").

Launch: new unit merge-checkpoint-relay-2026-10-21
Order: "after those merge, build ALL open Commandeck plugin issues, batched as main sees fit" (the owner, 2026-10-20)

Base: main 97382ff (0.22.0).

Public repo: no personal names, handles, pane names (other than the existing seat folder name `Chief-of-Staff`)
or user paths in any shipped file, comment, test, commit message or changelog line. Outside CHANGELOG.md an issue
number is written "issue N". "The host project" is the project this plugin was taken from; most items here port
its fixes by commit (owner ruling of 2026-10-20), and its issue numbers are written "host issue N". A ported
fixture is rewritten with neutral item text: no host names, paths or persona names. Commit titles are plain. Test
fixtures use dates before 2000 for ruling ids.

Skill for the build: `mattpocock-skills:tdd`. Every item with logic is red first. Item 5's restart-frequency part
is a measurement, not a red test: the Builder records the numbers before, and main records them after (see item 5).

## Done when

- `bash scripts/run-shell-tests.sh` (the whole suite, not `--changed`) is green on the tip before the final
  review. The Builder records the tip, the time taken and the totals in the brief's evidence. It also passes once
  with jq 1.7 first on `PATH` (CONTRIBUTING.md).
- `dashboard-view.test.sh` runs and is not skipped. `COMMANDECK_TEST_NODE_MODULES` names a node_modules folder
  that has jsdom, and the brief names that folder. No item here changes the page, but the suite run must not skip it.
- `claude plugin validate .`, `bash ci/leak-test.sh`, `bash ci/version-check.sh main` and
  `bash scripts/startup-size.sh` pass.
- No install, uninstall or whole-setup run, and no end-to-end test (owner ruling 2026-10-16). The tests drive
  functions and scripts on scratch HOMEs, as they do today. `dashboard.sh --install`, `main-watch.sh --install`,
  `gh`, `ssh` and `orca-ide` are stubs in every test.
- Every review pass runs through the pass script the brief names (the installed plugin's).
- Each of items 1-17 meets its own "Done" line below. Item 8's covers issue 258's merge-gate part; the rest of
  issue 258 is not in this unit. Items that depend on a pending owner answer (questions 3, 4 and 5 below) are
  built as the recommended answer unless main's brief says otherwise, and the brief says which.
- Before the final pass the unit is rebased on any sibling unit that merged first (see "Files a sibling unit also
  touches").

## Owner answers

The ruling ids are in the plan spec (its answers 1 to 4) and go in the batch brief: `ci/leak-words.txt` refuses
a ruling id in a tracked file, and this plan is committed to main.

1. **No second machine (plan spec, answer 1).** The plugin does not add support for a second machine. Issues 296
   and 297 are closed as won't-do. The old item 17 (tests on a peer host) and every peer-host part of any item
   are dropped. The old question 2 (the peer host's shape) is moot. `board.sh`'s leftover chain lines are removed
   by item 17, with no peer line in their place.
2. **Issue 307 replaces item 16; one unit (plan spec, answer 2).** Issue 307 is 297's non-peer parts: reuse of
   the closing pass's test result and a merge train, on this machine only. It is built in this unit, last. The
   old question 1 (one unit or two) is answered: one unit.
3. **Issue 258's merge-gate part joins item 8 (plan spec, answer 3).** The sibling unit
   hooks-seats-guards-2026-10-21 dropped it.
4. **Sibling overlaps on `merge-unit-local.sh` (plan spec, answer 4).** dashboard-parity-2026-10-21 item 9 and
   hooks-seats-guards-2026-10-21 item 6 (issue 265) also change it. Whichever merges first, this unit rebases on
   it before its final pass.

Pending owner; build the recommended answer unless main's brief says otherwise. Each is written as it was sent.

- Question 3. **Issue 307's reuse (issue 297 item 2 before the split), when the closing pass's test result is
   reused.** Decision `mcr-q3-reuse-2026-10-21`, pending owner. The issue's rule is "rebasing changed
   nothing the unit or its tests touch". In this plugin a test covers shared scripts the unit did not touch
   (`paths.sh`, `hooks/lib/*`), so a main commit to one of those can break the unit's tests while the unit's own
   files are unchanged. **Recommended: reuse only when the merge copy's tree is exactly the tree the closing pass
   tested** (main did not move, or moved only files outside the plugin: the same `PLUGIN` path list
   `ci/version-check.sh` uses). Other answer: the issue's rule, as the host has it.
- Question 4. **Issue 255, the dashboard restart's precondition.** Decision `mcr-q4-dash-restart-2026-10-21`, pending
   owner. The issue's case is "a dashboard restarted behind a new
   login with no password set". The plugin's dashboard has no login today; issue 263 (unit
   dashboard-parity-2026-10-21) adds one. **Recommended: the post-merge allow-list takes `dashboard.sh --install`
   only with a precondition hook that the login unit fills in: when the project has a dashboard login turned on
   and no password, the step refuses. Until issue 263 merges, the precondition has nothing to check and passes.**
   No irreversible step is on the list, so the "typed yes" gate has nothing to guard and is not built. Other
   answer: wait for issue 263 and build item 10 after it.
- Question 5. **Issue 259, what the push request lists.** Decision `mcr-q5-push-request-2026-10-21`, pending owner.
   **Recommended: the commits on main since `origin/main`, each with
   its unit and that merge's check result from the finished-builds row; refused (no row written) when there is
   nothing to push or any listed merge's check is not green.** Other answer: the commits only, with no refusal.

## Item 0. Close as shipped (main closes these; no build)

Each issue was checked at 97382ff, and each one's "done when" is met. 0.21.0 is the commandeck-build-2026-10-19b
unit (c4ece92 to 2b99aad); 0.22.0 is commandeck-build-2026-10-20 (9fb00ef to 8e2ee94).

| Issue | Shipped in | Evidence |
|---|---|---|
| 218 | 0.21.0 (c4ece92) | The file is split in three: `main-watch-helper-hold.test.sh`, `main-watch-claim.test.sh`, `main-watch-wake.test.sh`. Measured while planning, each alone: 27 s, 27 s, 31 s (was 78 s; cap 120 s). Not measured while planning: the four-copies-under-load timing. Main may ask the Builder to take it once and record it in the evidence. |
| 221 | 0.21.0 | `scripts/merge-unit-local.sh:281-297` (message leak check before the merge); `ci/leak-test.sh --text` (`:10-15`); test `merge-unit-local.test.sh:131-136`. Host bb45e387 is a git commit-msg hook in the host's own repo; the plugin's merge makes the commit, so the check there is the twin. |
| 222 | 0.21.0 | `help.test.sh` (every script prints usage on `--help` with no side effect); `to-main.sh:13`, `cos-tell.sh`, `answer-worker.sh`, `board.sh` usage lines. |
| 227 | 0.21.0 | Owner's answer to the 19b plan's question 5: action scripts close their own item task. `pp_close_items`, `scripts/paths.sh:237-250`; callers `answer-worker.sh:99`, `seat.sh:497`, `merge-unit-local.sh:449`. Host e18f3512 and 73bead80 build on a main inbox-wait script the plugin does not have; nothing more to port. |
| 231 | 0.21.0 | `scripts/relay-order.sh`, test `relay-order.test.sh`; `decision.sh answer` finds `askedAt` itself. Host 655041d5's relay-order script is a port of the plugin's. |
| 232 | 0.21.0 | Rulings check and decoy rule: `hooks/agent-startup-context.sh:140`, `templates/main-session.md:105-106`; empty answer retry: `hooks/ruling-log.sh:191`; picker time-box: `scripts/main-watch.sh:443` (the dashboard raises "picker open N min" at 30 min). The table's host commit 655041d5 does not carry host issue 2904, so the PORT tag was wrong; nothing to port. The issue's "longer term" consumer stays under "Not built". |
| 235 | 0.21.0 | `templates/main-session.md:31` (one status line). Host 6abe413f carries host issue 2908, the same rule. |
| 237 | 0.21.0 | `templates/main-session.md:28-30` (`--verify` before offering a merge). Host 6abe413f, host issue 2910, same rule. Item 11 (issue 306, R11) later changes who runs that check. |
| 239 | 0.21.0 | `close_issues`, `scripts/merge-unit-local.sh:181-194`; `merge-unit-local.test.sh`. Host 813b3c67 closes at push, because the host pushes; the plugin merges locally and closes at merge, which is the issue's ask. |
| 243 | 0.21.0 | `scripts/builder-codex-pass.sh:848-905` (closing pass runs the full test command, writes the `Suite:` line); `:618-621` (`--verify` needs a green `Suite:` line when `fullSuiteBeforeFinal`); `builder-codex-pass.test.sh`. |
| 244 | 0.21.0 | `setup.sh --full-suite on\|off` (`:11`, `:115`, `:222`); `doctor.sh:58`. |
| 245 | 0.22.0 (9fb00ef) | `userConfig` in `.claude-plugin/plugin.json`; `pp_option` and `pp_config_option`, `scripts/paths.sh:612-640`; tests `plugin-option.test.sh`, `doctor.test.sh`. Item 1 (issue 293) fixes one setting's recommendation; the options themselves are shipped. |

## Priority

- **P1, issue 293 (item 1).** Labelled P1. A Builder on Sonnet starts at medium effort because set-up recommends
  Medium for every model. Every Sonnet build since 0.22.0 runs below what the owner expects. Small and
  independent, so it goes first.
- **P1, issue 283 (item 4).** Labelled P1. Main's restart checkpoint bloats and restarts come faster, which costs
  every session of main. It builds on items 2 and 3 (issues 252 and 281): the host landed the same three changes
  in that order (91b9b8e5 and cce5984f, then 9db01a9c, then 3215844a and 6b58a886), and each needs the one
  before it. So items 2 and 3 go before it although they are P2.
- Then the rest of the context-clear hook's items (5-7), then the merge flow (8-12), then the planning and relay
  items (13-15), then the `board.sh` cleanup (17), then issue 307 (item 16) last (owner answer 2).

## Item 1. Issue 293 (P1): the Builder's effort follows its model, and /config's value reaches the launch

- **Cause, found while planning:** of the issue's three suspects, (3) is confirmed. `skills/setup/SKILL.md:110-123`
  asks Builder model, then Context, then Builder effort, and offers "Medium (recommended)" whatever the model.
  (1), the launch: on reading the code, `/config`'s value does reach it. `pp_route_json` (`scripts/paths.sh`)
  lays `pp_config_option builderEffort` over the project's `.builder` over `config/routing.json`, and
  builder-launch takes the seat's effort from that. No test asserts it on a launch command, so the Builder writes
  that test first; if it fails, that is the cause instead. One more suspect for (1): if Claude Code writes every
  option's manifest `default` into `settings.json` when any one option is saved, `builderEffort: "medium"` lands
  there and hides the project's answer. The Builder checks Claude Code's plugin docs (`userConfig`); if so, the
  `default` key comes off `builderModel` and `builderEffort` in `.claude-plugin/plugin.json` (the readers already
  fall back without it, `pp_option`). (2), a set-up path that skips the question: the Builder reads the
  `--questions` subsets and the profile presets in the SKILL; any path that asks the model asks the effort.
- **Change:**
  - `skills/setup/SKILL.md`: Builder effort is asked right after Builder model. Recommended: High for Sonnet;
    Medium for Opus and Fable, as today. A saved answer is the recommended one on a re-run (the issue 210 rule
    already in the SKILL), so an update keeps the user's effort.
  - `scripts/doctor.sh:52`: the Builder line prints each value's source (`pp_option <key> source`), e.g.
    `builder: sonnet (/config), effort high (.claude/commandeck.json)`.
  - The precedence (/config, then the project's saved answer, then routing's default) is written once, in the
    `pp_option` header (`paths.sh:625`), and the SKILL points there.
- **Red first:**
  - builder-launch's test: a scratch `settings.json` with `pluginConfigs` `builderEffort: "high"` and a project
    file saying `medium`: the launch command carries `--effort high`.
  - a SKILL text pin (setup cannot be run whole, owner ruling): the effort question directly follows the model
    question, and the Sonnet row names High as recommended.
  - `doctor.test.sh`: the Builder line names both sources (updates the pin at `:205`).
- **Done:** those pass. **Size:** about 25 lines and 35 test lines.

## Item 2. Issue 252: a restarted main keeps its inherited items, and the check no longer strands it

- **Cause:** half fixed already. 7fad239 (0.21.0) stopped `carry` from crediting the new checkpoint's
  `Carries open items of:` reference (`scripts/checkpoint-context.py:250-252`). Two causes are left, both found
  while planning:
  1. `hooks/context-clear-stop.sh:46-59` blocks on every stop of the chain (no `stop_hook_active` pass) and puts
     the whole miss list in the block reason. With a long list every block adds the list to main's context, and
     main is stranded: the host's "15 times in 72 hours".
  2. `closed()` (`checkpoint-context.py:175-181`) accepts any closure line that names the item and says one more
     word. One line naming several items, or one reason pasted on many lines, closes all of them: that is how a
     rewritten checkpoint drops items and still passes.
- **Port:** host 91b9b8e5 and cce5984f.
  - The hook blocks once. The reason names the count, the first item (150 characters) and the command that lists
    them (`checkpoint-context.py carry <base> <cp>`), not the list.
  - On the second stop (`stop_hook_active`), when `carry` still exits 1, the hook copies the missing items into
    the checkpoint under one `## Queue (left unresolved at the restart: restate or close each, one line per item,
    with its own reason)` heading, logs "carried automatically into the checkpoint", and restarts. Exit 2 (an
    unreadable chain) restarts with a log line and copies nothing, as the host does.
  - `closing_lines()` replaces `closed()` in `carry`: a close line closes one item (the longest it names), and
    only when its reason is not any other close line's reason. A pointer line closes nothing.
  - `hooks/resume-context.sh:113-114`: `KEPT` and `KEEP_RE` add `Queue (in order)` and the unresolved Queue, so a
    cut resume still shows the carried items (host 3215844a made the same change).
- **Red first:**
  - `scripts/__tests__/checkpoint-context.test.sh`: a fixture pair shaped like the host's failing pair
    (cce5984f's two fixture files, rewritten with neutral item text): `carry` exits 1 and lists the dropped items.
    One close line naming two items closes neither; one reason on three lines closes none.
  - `hooks/__tests__/context-clear-stop.test.sh`: the first stop blocks with a reason under 400 bytes that names
    the count; the second stop appends the items, restarts, and a `carry` of the restarted checkpoint against
    the old one exits 0.
- **Done:** those pass and the existing context-clear-stop tests stay green. **Size:** about 90 lines and 95 test
  lines.

## Item 3. Issue 281: the second-stop copy adds no duplicates, and the item count stays flat

- **Cause:** item 2 brings the second-stop copy; the plugin does not have it today, so the plugin cannot show the
  growth yet. The host's copy re-added items restated in new words, each time under a new Queue heading
  (197 items, 31 duplicates). This item is the guard that keeps item 2 from growing the same way.
- **Port:** host 9db01a9c.
  - `key(ident)`: an item's subject, without a leading `open:` tag and cut at its first status tail
    (` -- reason:`, ` -- still open:`, ` -- closed:`, ` -- restated:`, ` = todo #`). An item restated with a new
    tail has the same key and counts as carried.
  - `pointed()`: an item that says `= todo #N` is carried when the new checkpoint's open todo #N starts with the
    same first word (the host's `shortcut:` comment comes with it).
  - A `CLOSED:` or `[x]` line outside the Closed section is a closure with its status word removed.
  - `carry` lists each missing key once.
  - The hook copies under the existing unresolved Queue heading when there is one (awk reads the list from a
    file, not argv), so one checkpoint has one such section. A copy that fails does not restart main, and says so
    on stderr.
- **Red first,** `context-clear-stop.test.sh`: three simulated restarts, each rewording two inherited items
  (a new status tail, a `= todo #N` pointer). After the third, the item count equals the first's, no bullet is
  repeated, and there is one unresolved Queue heading. A genuinely dropped item is still listed.
- **Done:** that passes. **Size:** about 90 lines and 105 test lines.

## Item 4. Issue 283 (P1): finished items close themselves, items keep a key, a dedupe command, a size budget

- **Port:** host 3215844a and 6b58a886, and the two log fields from c032363b. Each part maps to the issue's four:
  1. **Auto-close with evidence.** An item ending ` -- done when: <ref>, <ref>` is closed by `carry` when every
     ref holds now: `#N` closed (`gh issue view N --json state`, read only); `decision:<id>` answered (the latest
     row for that id in `$PP_MAIN/.claude/metrics/decisions.jsonl`, `decision.sh:28`); `<unit>` merged (main has
     a `feat(<unit>):` commit, the title `merge-unit-local.sh:224` writes); a sha on `origin/main` (pushed). Each
     lookup is capped at 10 s; a failed lookup leaves the item open. Each close is one `auto-closed: <item> --
     <evidence>` line in `clear-hook.log`; nothing is written to the checkpoint.
  2. **A key that survives rewording.** Queue items start with `Q-<n>` (next free number, never reused). Their
     key is `q-<n>`, whatever the words after it; `Q-7 -- <reason>` closes q-7 under item 2's one-reason rule.
     `templates/checkpoint.md` and the hook's "write the checkpoint" reason say so in one line each.
  3. **Dedupe command.** `checkpoint-context.py dedupe <file>` flattens the file's carry chain into it, one line
     per subject, keeps a backup next to it (and refuses a second run while the backup exists), and re-stamps the
     `.restarted` and `.resumed` markers with the new checksum, in the `cksum` form the hooks write
     (`context-clear-stop.sh:40`, `hooks/lib/context-clear-restart.sh:20`), so the rewrite does not read as a new
     checkpoint.
  4. **Size budget.** The stop hook's log line gains `cp_bytes` and `over=1` when the checkpoint is past the
     10,240-byte resume budget; `resume-context.sh` logs `payload_bytes`. The walk stops after ten generations
     (`MAX_DEPTH`); `checkpoint-context.py aged <base>` lists what that cut drops, the hook writes them to
     `<cp>.aged-out.md`, and the resume prints one pointer line to that file instead of loading it. An item
     carried unseen past the cut gets the ` -- carried unseen: N` tail (6b58a886) and moves to that file only
     once it is written; if it cannot be written, main is not restarted.
- **Red first:**
  - `checkpoint-context.test.sh`: auto-close with a stubbed `gh` and a scratch decisions ledger (ruling ids
    dated 1999), one ref failing keeps the item; a `Q-3` item reworded twice is carried; `dedupe` on a stacked
    fixture (three unresolved Queue sections, duplicates) gives one line per subject, a backup, re-stamped
    markers, and a dropped item is still caught afterwards; `aged` on an eleven-generation chain lists the
    eleventh's items.
  - `context-clear-stop.test.sh`: the log line has `cp_bytes` and `over`; the aged-out file is written and named
    in the resume.
  - Before/after measure of post-restart context (the issue's last ask): the resume's `payload_bytes` on the
    stacked fixture before and after `dedupe`, recorded in the evidence.
- **Done:** those pass. **Size:** about 230 lines and 190 test lines (the largest checker change; 3215844a alone
  is about 400 changed lines on the host).

## Item 5. Issue 300: carry-over alerts that heal themselves, and restart frequency

- **Part 1, mute the self-healing alert: not applicable in the plugin, with reason.** Host 8cf83986 (and
  45e1552d) mute "carried automatically" lines in the host relay's context watcher. No plugin watcher or
  dashboard alert reads `clear-hook.log`'s carry-over lines today (only the hook writes them,
  `context-clear-stop.sh:54`). After item 2, those lines say "carried automatically" and nothing alerts on them,
  which is what the issue asks. A test pins it: `cos-watch-alerts.sh` on a log with one such line prints nothing.
- **Part 2, restart frequency: the host commit in the table does not fix it.** 413dab38 is issue 275's binding
  line (item 7), not a cut in restarts. So this part is planned from the issue text, on the host's measured
  causes: a large checkpoint (item 4's budget, dedupe and aged cut) and a context count that runs below the real
  one (item 6). What is left here:
  - `context-clear-stop.sh`'s log line gains `since_restart_min` (minutes since the newest `.resumed` marker of a
    session in the same project folder, `-` when none), from host c032363b.
  - The Builder records the "before" numbers from this machine's `clear-hook.log` in the evidence: median minutes
    between restarts and median checkpoint bytes over the last 50 restarts. No log text goes in the repo.
  - After the merge, main takes the "after" numbers from the new log fields (`since_restart_min`, `cp_bytes`,
    `payload_bytes`) and adds them to the issue before closing it. That step is in the brief's Post-merge list.
- **Red first,** `context-clear-stop.test.sh`: with a `.resumed` marker 7 minutes old, the line says
  `since_restart_min=7`; with none, `-`. The `cos-watch-alerts.sh` pin above.
- **Done:** those pass and the "before" numbers are in the evidence. **Size:** about 20 lines and 40 test lines.

## Item 6. Issue 267: the clear line and ceiling sit below the auto-compact point

- **Cause, found while planning:**
  - The defaults: `pp_clear_line` (`hooks/lib/project.sh:50-66`) is 200,000, or 150,000 with `standardContext`;
    the ceiling is a fixed 480,000 (`context-clear-stop.sh:65`); a Builder clears at 180,000
    (`pp_builder_clear_line`). The context-line nudge says "PAST the line" at line + 40,000
    (`hooks/context-line.sh`). With a 200K window the host measured compaction at 171K-175K, so a 200K line, a
    480K ceiling and a 190K nudge all come after it. Only `standardContext`'s 150K line is below, by about 20K,
    and one long turn adds more than 15K.
  - The count: `hooks/lib/context-size.sh` sums input, cache read and cache creation, and drops spikes. Claude
    Code's compaction also counts output. So the plugin's number is below the one compaction acts on (host
    48151d13 changed its count the same way).
- **Change:**
  - `context_size` adds the last turn's output tokens. The spike filter stays only if its own test case still
    holds under the new count (the Builder reads its comment first).
  - Defaults by window: with `standardContext` (a 200K window) the line is 140,000 and the ceiling 165,000, at
    least 30,000 under the measured compaction point. The 1M window keeps 200,000 and 480,000. The ceiling becomes
    `pp_clear_ceiling` beside `pp_clear_line`; `COMMANDECK_CLEAR_CEILING` still overrides it.
  - A Builder on `standardContext` clears at 140,000 (`pp_builder_clear_line`, `scripts/worktree-setup.sh:115-118`
    where the window is written).
  - The nudge fires at the line, not 40,000 past it, when the window is standard (the gap left is under 40,000).
- **Red first:**
  - `context-clear-stop.test.sh`: with `standardContext`, a transcript at 141,000 acts (block for the checkpoint
    or restart); the effective ceiling is under 171,000.
  - context-size's test: a transcript whose last turn has 12,000 output tokens counts them.
- **Done:** those pass. **Size:** about 45 lines and 75 test lines.

## Item 7. Issue 275: past the clear line, main may only write its checkpoint

- **Port:** host 413dab38 (its pane-budget-gate and context-line parts; its class-stop and search-log parts have
  no plugin issue and are not ported).
  - `hooks/context-line.sh`: when main's session is past the line, it writes a marker,
    `$HOME/.claude/checkpoints/<sid>.past-line` (the plugin keeps its markers there, not in `/tmp`).
  - `hooks/pane-budget-gate.sh` (matcher `.*`, `hooks/hooks.json:19-20`): a new first branch, before the
    strict-tier early exit (`pp_strict`), for main only (not a linked worktree, not a reviewer, as
    `context-clear-stop.sh:17-18` decide it). With the marker present it refuses every call except: Write or Edit
    of `$HOME/.claude/checkpoints/<sid>.md`; Read of that file, of the checkpoint it resumed from, and of
    `templates/checkpoint.md`; `state-snapshot.sh --out`; `checkpoint-context.py carry`; the task-list tools. The
    message says: write the checkpoint, then end the turn; the stop hook restarts main.
  - Worker panes never reach the branch.
- **Red first,** `hooks/__tests__/pane-budget-gate.test.sh`: main past the line, (1) Bash and Edit of another file
  are refused, (2) the checkpoint Write is allowed, (3) below the line nothing is refused, (4) a worker pane
  with the marker is never refused.
- **Done:** those pass. The issue's "after landing, main restarts instead of compacting" is main's to watch; the
  brief's Post-merge list names it. **Size:** about 45 lines and 65 test lines.

## Item 8. Issues 254 and 258 (merge-gate part): a unit that passes the gate merges itself into local main

- **Port:** host 7c1a4757 (auto-merge gate, `Merge: hold`, merge by sha), adapted to the plugin's
  `main-watch.sh` and `merge-queue.sh`.
- **Change:**
  - `scripts/main-watch.sh`, on a Builder's DONE for a unit: the gate is all of: `builder-codex-pass.sh --verify
    <worktree> <unit> <tip>` exits 0 (a final, not narrowed, pass with GO on that exact tip, and a green `Suite:`
    line when `fullSuiteBeforeFinal` is on, `:618-621`); the worktree is clean; no open decision for that unit
    waits on the owner (the decisions ledger); the brief has no `Merge: hold` line. Every refusal is one line to
    main with the reason (and is judgement, item 9).
  - On a pass it runs `merge-queue.sh <unit>@<tip>` as a background job (`pp_detach`, `paths.sh:230`) that writes
    its exit code to a file; the next tick reads it. 0 is one result line (item 9's digest); anything else is a
    post to main with the log path.
  - Issue 258's merge-gate part (owner answer 3): a unit left waiting to merge (its Builder said DONE, it has not
    merged, and no new DONE came) is not an alert card for a person. main-watch runs the same gate on it at the
    next tick: a pass merges as above, and a refusal is posted once per tip. Issue 258's gates hold: it never
    answers a question for the owner, never acts on or nudges a held unit (`Merge: hold` or an open owner
    decision), and never pushes or deploys. Issue 258's nudges and dead-pane alerts are not in this unit.
  - `scripts/merge-unit-local.sh --auto <sha>`: refuses when the branch tip is no longer `<sha>`. Otherwise
    unchanged: rebase, the test command on the copy, squash, close issues, leak check. It never pushes, opens a
    PR or deploys, as today.
  - The issue's `--report` mode is not added: `merge-queue.sh` already prints one line per unit and keeps the
    log in a file, which is what the mode was for.
  - The issue comment's scope addition (the trial run stops repeating the full safety checks) is already true in
    the plugin: a dry run runs no test (`CHECK_CMD` only when not dry-run, `merge-unit-local.sh:298`), and there is
    no certification chain.
  - `templates/_builder-brief-template.md`: one line documents `Merge: hold`. `templates/main-session.md:28-30`:
    main-watch merges a unit that passes the gate; main offers a merge only for one it held or refused.
- **Red first,** a new `scripts/__tests__/main-watch-auto-merge.test.sh` (its own file, so the main-watch files
  stay under the per-file cap, issue 218): a converged fixture unit lands with one line; a narrowed GO, a NO-GO,
  a dirty tree, a `Merge: hold` brief and an open owner question are each refused with the reason and no merge.
  `merge-unit-local.test.sh`: `--auto` with a moved tip refuses. Issue 258's part, same test file: a unit left
  waiting to merge is gated at the next tick and lands; a held one gets no gate run and no nudge; a refused one
  is posted once for its tip, not on every tick.
- **Done:** those pass (the last case is issue 258's "a held unit gets no nudge" for the merge gate). **Size:**
  about 150 lines and 160 test lines.

## Item 9. Issue 253: routine inbox items stop waking main

- **Port:** the classification of host e18f3512 and 73bead80, placed in `main-watch.sh` (the host's lives in an
  inbox-wait script the plugin does not have).
- **Change:**
  - Each item main-watch would post is routine or judgement. Routine: an auto-merge that landed (item 8), a seat
    verdict main-watch itself acted on, a heads-up that repeats one already posted. Those go to one digest file
    beside main-watch's state, one line each, with no message and no typed wake; the handler closes the item's
    task itself (`pp_close_items`).
  - Everything else is judgement and wakes main as today: questions, NO-GO verdicts, red gates, a refused or
    failed merge, a failed handler, an unknown subject.
  - Issue 288's comment (sibling unit hooks-seats-guards owns `orca-wait.sh`'s hidden batches): a seat verdict
    whose driver is dead, and a lone job-exit notice with a non-zero exit, are judgement here, so this item
    hides neither.
  - `orca-wait.sh` prints one line with the digest's count and path when main next wakes; main reads it only
    when it needs to. `templates/main-session.md` gets one Details line.
- **Red first,** `main-watch-auto-merge.test.sh` (or a new file if that one nears the cap): replaying a recorded
  fixture of 12 items (7 routine) makes at most 6 wakes; a question, a NO-GO, a red gate and a failed handler each
  still wake.
- **Done:** those pass. No feature flag. **Size:** about 70 lines and 80 test lines.

## Item 10. Issue 255: post-merge steps run themselves, and unsafe ones refuse

- **Port:** host 7c1a4757's post-merge allow-list (exit 5) and its has-password precondition.
- **Change:**
  - `templates/_builder-brief-template.md`: a `## Post-merge` section, one command per line.
  - `scripts/merge-unit-local.sh`, after a green merge: each line runs only if it is on the allow-list:
    `dashboard.sh --install`, `main-watch.sh --install`, `run-shell-tests.sh <one test file>`. Anything else
    refuses with exit 5 and the line. Each step runs as a background job; its exit codes go into the unit's
    finished-builds row, and one line is printed.
  - The dashboard step's precondition per question 4. A failed or refused step does not undo the merge and is
    judgement (item 9).
- **Red first,** `merge-unit-local.test.sh` with stubbed scripts: a dashboard step with a login and no password
  refuses; with a password it runs and the row shows exit 0; an off-list line exits 5.
- **Done:** those pass. **Size:** about 55 lines and 65 test lines.

## Item 11. Issue 306: the redundant-steps cleanup (R1-R14)

- **Port:** host c0e61f13, 45e1552d and e221a8bb. Each item ported or marked not applicable:

| Item | Plugin | Why |
|---|---|---|
| R1 | not applicable | The plugin runs no full check after each merge and has no push check run. |
| R2 | not applicable | No check lanes. |
| R3 | not applicable | No class check in the merge. |
| R4 | not applicable | The merge writes one seat-event row once (`merge-unit-local.sh:418-428`). |
| R5 | not applicable | No metrics commit per merge. |
| R6 | not applicable | The worktreereview page is made only on request. |
| R7 | not applicable | No record check. |
| R8 | not applicable | The merge's evidence read is the deletion guard, not keyword noise. |
| R9 | sibling | `builder-launch.sh:90-95` needs the plan committed on main; issue 256 (unit hooks-seats-guards) owns that gate. |
| R10 | port | Drop the rung line from `templates/_builder-brief-template.md:45` and the rung reader in `skills/worktreereview/scripts/review.py:50` (`rungs()`) and its render. |
| R11 | port | `--verify` runs once per tip: item 8's gate records its result in main-watch's state; `orca-wait.sh:338-352` reads that instead of running `--verify` again; main no longer runs it by hand (item 8's line). The merge's own check stays. |
| R12 | not applicable | The plugin writes neither record. |
| R13 | port | `templates/main-session.md:66`: the planner revises only when the judge's verdict is NO-GO; on GO the plan goes as written. |
| R14 | met | The template already says one pane. |

  - "Merge dry runs removed": the plugin flow runs none, and a dry run runs no test; not applicable.
  - e221a8bb's rule, "No redundant steps": one Details line in `templates/main-session.md`, and a "Catches:" line
    rule in `templates/_batch-brief-template.md`: a step added to the build, merge, review or push flow names
    what it catches that no existing step does.
- **Red first:** `worktreereview.test.sh`: an evidence file with no rung lines renders with no rung column;
  `orca-wait.test.sh`: with a recorded gate result for the tip, `--verify` is not called (a stub counts calls).
- **Done:** those pass and every row above is in the evidence. **Size:** about 40 lines and 40 test lines.

## Item 12. Issue 259: a CI watch with one rerun, and a prepared push request

- **Port:** host 7c1a4757 (`--ci` watch, `decision.sh` push-ask), as a plugin script: the plugin has no
  wake-on-exit script.
- **Change:**
  - New `scripts/ci-watch.sh <sha>`, run through `pp_detach`: lists the runs for the sha (`gh run list --commit`),
    waits on each with `gh run watch --exit-status` (no poll loop, so the no-poll-loops guard holds), reruns a
    failed run's failed jobs once (`gh run rerun --failed`, the run id recorded so it never reruns twice), and
    sends main one line with each job's result. A run whose workflow name or file says deploy is watched only:
    no rerun.
  - `scripts/decision.sh push-ask`: writes one decision row asking the owner to push, per question 5. It never
    pushes.
- **Red first,** a new `scripts/__tests__/ci-watch.test.sh` with a stubbed `gh`: a flaky run reports failed, then
  green after one rerun; a second failure is not rerun; a deploy workflow gets no rerun call.
  `decision.test.sh`: push-ask on a clean branch writes one row; with nothing to push it writes none.
- **Done:** those pass. **Size:** about 75 lines and 75 test lines.

## Item 13. Issue 284: planning scratch files no longer block the Builder launch

- **Cause:** `scripts/plan-worktree-close.sh` refuses `--adopt` when the worktree holds any file not identical on
  main, untracked ones included. A judge report written with a relative `--report` (`seat.sh:444`) and specs
  copied in by hand land in the worktree, so builder-launch is refused.
- **Port:** the plan-close scratch move of host 3215844a.
- **Change:** before that check, `plan-worktree-close.sh` moves untracked files under `.claude/briefs/` named
  `<unit>-*` or `_<unit>-*`, and any `report=` path in the unit's seat records that lies in the worktree, to
  `$SCRATCH/<unit>-planning/` (beside the `reports/` folder `seat.sh:446` already uses), one `moved:` line each.
  Anything else still refuses.
- **Red first,** `plan-worktree-close.test.sh`: an untracked `.claude/briefs/<unit>-judge-report.md` no longer
  blocks `--adopt`, and the file is found under the scratch folder; an untracked `scripts/x.sh` still refuses.
- **Done:** those pass. **Size:** about 25 lines and 35 test lines.

## Item 14. Issue 290: the relay's timer check, missed messages, payload caps, picker rules

- **Port:** host 655041d5, verified by its diff: it adds the host's timer check script and the watchers' caps.
  The table's [partly] holds: part of the issue is already in the plugin.
- **Already met (no build):**
  - Payload caps (part 2): issue 229's rule is stricter. `cos_wait` (`scripts/cos-lib.sh`) prints a watcher's
    wake whole only up to 600 bytes, else one summary line and the file, under the issue's 1,200 and 1,500.
  - Rules: a read over about 10 KB goes to a subagent that answers in 40 lines, and rulings before a picker, one
    question per picker, decoy first (`hooks/agent-startup-context.sh:139-140`).
- **Change:**
  - New `scripts/cos-check.sh`: sleeps 50 minutes, then prints one line and exits, which wakes the relay pane. It
    names any watcher that is down (each writes its pid to `<state>.<watcher>.pid`, `cos-lib.sh:11-18`); prints
    and clears held FYI notes (under the inbox watcher's lock); counts messages Orca holds for the pane in the
    last 2 hours that are not in a new seen-ids file, which `cos-watch-inbox.sh` appends each handled id to; and
    the minutes since the owner last typed (from the rulings log). The line is appended to a timer log.
  - The relay block gets the missing rule: with the owner quiet for 30 minutes or more, open no picker; leave the
    question on the decision queue and ask when the owner next types.
  - `hooks/cos-inbox-waiter-stop.sh` requires `cos-check.sh` as a fifth background job, as it requires the four
    watchers.
- **Red first,** a new `scripts/__tests__/cos-check.test.sh` with stubbed `orca-ide` and `pgrep` and the sleep
  shortened by an environment variable: a down watcher is named; an unseen message counts as missed and a seen
  one does not; FYI notes are printed and cleared once. `cos-inbox-waiter-stop.test.sh`: no cos-check job blocks
  the stop.
- **Done:** those pass and `startup-size.sh` passes with the new rule. **Size:** about 75 lines and 75 test
  lines.

## Item 15. Issue 305: a Builder's question to the owner reaches the owner at once

- **Host twin:** host issue 3020 is open with no fix, so this is NO-HOST, built from the issue text.
- **Cause, part 1, found while planning:** `scripts/orca-wait.sh:338-352` records every Builder question as a
  decision `--waits-on main` and runs `--verify` for advice. The owner's relay sees it only after main reads it,
  so a stop-and-ask question waited 21 minutes.
- **Change:** a Builder question that is owner-bound (a repeat-class stop-and-ask, or one that names the owner)
  is recorded without `--waits-on main`, so `cos-watch-decisions.sh` and the dashboard's "Needs me" show it at
  once. Main still gets its line.
- **Part 2, the ask that ended at half its timeout:** cause not found while planning. Plugin workers ask with
  `--timeout-ms 240000` and `--resume` (`hooks/worker-ask-guard.sh:50`), so a 60-minute ask is not one the plugin
  makes. The Builder spends at most 30 minutes on Orca's CLI help and docs for a server-side cap. If one is found,
  `worker-ask-guard.sh`'s comment names it; if not, the brief says so and the part stays under "Not built".
- **Red first,** `orca-wait.test.sh`: an owner-bound Builder question writes a decision with no `waits-on`; an
  ordinary one still waits on main.
- **Done:** that passes and part 2's finding is in the evidence. **Size:** about 20 lines and 40 test lines.

## Item 16. Issue 307: reuse the closing pass's result, and a merge train (this machine only; built last)

(Owner answer 2: built in this unit, after every other item.)

- **Port:** host c032363b's merge train (with `--test-tip` and bisect) and its reuse of a dry run's record when
  its inputs match, from the host's merge-queue and local-merge scripts. None of its peer-host parts.
- **Reuse:** `merge-unit-local.sh` skips running the test command on the merge copy when the closing pass's
  `Suite:` line is green for a tree, and the copy's tree matches it per question 3 (pending; recommended answer).
  The log says "reused" with that `Suite:` line. A stale result (the trees differ in a way the rule counts) is
  refused: the log says why, and the test command runs as today.
- **Merge train:** `merge-queue.sh --train <unit>@<sha> ...` builds the combined tip on a scratch copy on this
  machine, runs the test command once there, and on green merges each unit in order with `--auto`, each reusing
  the train's result for its step tree under the same rule. On red it bisects: it tests the first half's combined
  tip, and so on, until it finds the first unit that turns it red; it merges the ones before it and reports that
  one. Item 8's main-watch uses the train when two or more units pass the gate in one tick.
- **Red first** (issue 307's acceptance): `merge-unit-local.test.sh`: a copy whose tree equals the green `Suite:`
  tree does not call the test command (stub counts calls); a stale one is refused and the command runs. A new
  `merge-queue.test.sh`: a green train of three units runs the test command once and merges all three; a red
  train where the second unit breaks the combined tip merges the first, names the second, and the third waits.
- **Done:** those pass, and the whole suite is green on the tip ("Done when"). **Size:** about 120 lines and 160
  test lines.

## Item 17. `board.sh`'s leftover chain lines (no issue; cleanup)

- **Cause:** `scripts/board.sh:287-309` prints the host project's "CHAIN HOST", "OFFLOADED" and "PLACEMENT WAIT"
  lines. They read machine files no plugin script writes and name scripts the plugin does not ship
  (`chain-run.sh`, `unit-placement.sh`). With no second machine (owner answer 1), nothing replaces them.
- **Change:** delete those lines; the main-watch status line after them stays. `hs_chain_host`
  (`scripts/host-services.sh:47-56`) has no other caller and goes with them.
- **Red first,** `board.test.sh`: board's output on a scratch HOME has no `CHAIN HOST`, `OFFLOADED` or
  `PLACEMENT WAIT` line (today it prints `CHAIN HOST` on every run).
- **Done:** that passes and `rg hs_chain_host` finds nothing. **Size:** about 35 lines (mostly deleted) and 10
  test lines.

## Version

- `.claude-plugin/plugin.json`: `0.22.0` to `0.23.0` (new behaviour, per `ci/version-check.sh`). If a sibling unit
  merges first and takes 0.23.0, the Builder takes the next free minor. `README.md:4`, the badge's URL and alt
  text, follows it: `plugin.test.sh` holds both to the manifest.
- `.claude-plugin/marketplace.json` has no version field and `plugin.test.sh` holds none there, so nothing to
  bump in it.
- `CHANGELOG.md`: `## 0.23.0 -- <date>` on top, one bullet per item 1 to 17 with its `#N` (item 17 has
  none). It also says:
  - issues 218, 221, 222, 227, 231, 232, 235, 237, 239, 243, 244 and 245 shipped in 0.21.0 and 0.22.0 (written
    with `#` there, as CHANGELOG.md does);
  - a unit that passes the gate now merges itself into local main, and never pushes;
  - main restarts at 140K on a 200K window, and past its line it may only write its checkpoint;
  - the restart checkpoint closes finished items, keys Queue items `Q-<n>` and has a dedupe command.
- About 50 changed lines.

## Order of work: each shared file is touched once, except by item 16, which goes last

| Step | Items | Files |
|---|---|---|
| 1 | 1 | SKILL.md (setup), doctor.sh, plugin.json userConfig (maybe), paths.sh header; builder-launch and doctor tests |
| 2 | 2, 3, 4, 5, 6 | checkpoint-context.py, context-clear-stop.sh, resume-context.sh, templates/checkpoint.md, lib/project.sh, lib/context-size.sh, context-line.sh (nudge), worktree-setup.sh; their tests |
| 3 | 7 | context-line.sh (marker), pane-budget-gate.sh and its test |
| 4 | 8 (with issue 258's part), 9, 11 (R11), 15 | main-watch.sh, main-watch-auto-merge.test.sh, orca-wait.sh and its test |
| 5 | 8, 10 | merge-unit-local.sh, merge-queue.sh, their tests |
| 6 | 12 | ci-watch.sh, decision.sh, their tests |
| 7 | 13 | plan-worktree-close.sh and its test |
| 8 | 14 | cos-check.sh, cos-watch-inbox.sh, cos-inbox-waiter-stop.sh, agent-startup-context.sh's relay block |
| 9 | 8, 9, 10, 11 (templates) | main-session.md, _builder-brief-template.md, _batch-brief-template.md; worktreereview review.py and render |
| 10 | 17 | board.sh, host-services.sh, board.test.sh |
| 11 | 16 | first rebase on any sibling unit that merged first; then merge-unit-local.sh, merge-queue.sh, main-watch.sh (the train when two or more units pass in one tick), their tests |
| 12 | version | plugin.json, README badge, CHANGELOG; the whole "Done when" list |

- **Same file, more than one item:**
  - `scripts/checkpoint-context.py` and `hooks/context-clear-stop.sh`: items 2, 3, 4, 5 and 6 (ceiling), in that
    order, which is the host's order. Each builds on the one before.
  - `hooks/context-line.sh`: items 6 (nudge) and 7 (marker).
  - `scripts/main-watch.sh`: items 8 (with issue 258's part), 9, 11 (the recorded gate result) and 16 (the
    train), item 16 last.
  - `scripts/orca-wait.sh`: items 9 (digest line), 11 (R11) and 15.
  - `scripts/merge-unit-local.sh`: items 8 (`--auto`), 10 (post-merge) and 16 (reuse), item 16 last.
  - `scripts/merge-queue.sh`: items 8 and 16, item 16 last.
  - `templates/main-session.md`: items 8, 9, 11 (R13, rule). Main's startup print has about 1.3 KB left (8,916 of
    10,240 bytes); item 8 rewrites the line at `:28-30` instead of adding one, and items 9 and 11 go in Details.
  - `templates/_builder-brief-template.md`: items 8 (`Merge: hold`), 10 (`## Post-merge`) and 11 (R10).
  - `.claude-plugin/plugin.json`: item 1 (maybe) and the version bump.
- **Same data:** item 8's recorded gate result is read by items 9 and 11. The closing pass's `Suite:` line is read
  by items 8 (through `--verify`) and 16. Item 4's log fields are what item 5's "after" numbers read.

### Files a sibling unit also touches

Main sets the merge order from this list.

- `scripts/main-watch.sh`: hooks-seats-guards (issues 238, 258, 301, 302). Issue 258's merge-gate part is item 8
  here; the sibling dropped it.
- `scripts/orca-wait.sh`: hooks-seats-guards (issues 257, 288).
- `scripts/merge-unit-local.sh`, `scripts/merge-queue.sh`: hooks-seats-guards (issue 301).
- `scripts/merge-unit-local.sh`: dashboard-parity-2026-10-21 item 9 ports the host's unit-ledger writer
  (`scripts/unit-ledger.sh`) and its call from `merge-unit-local.sh`; hooks-seats-guards-2026-10-21 item 6
  (issue 265) adds a merge refusal to it. Whichever merges first, this unit rebases on it before its final pass.
- `scripts/decision.sh`: dashboard-parity (issues 240, 276, 292, 295).
- `scripts/plan-worktree-close.sh`, `scripts/builder-launch.sh` (item 1's test only): hooks-seats-guards
  (issues 234, 256, 287).
- `hooks/agent-startup-context.sh`: hooks-seats-guards (issue 268).
- `scripts/paths.sh`: dashboard-parity (issues 280, 291).
- `skills/setup/SKILL.md`, `scripts/doctor.sh`: hooks-seats-guards (issue 289), dashboard-parity (issue 263).
- `templates/main-session.md`: both siblings, several issues; main's 1.3 KB of startup room is shared.
- `templates/_builder-brief-template.md`: hooks-seats-guards (issues 264, 304).
- `scripts/cos-watch-inbox.sh`, `hooks/cos-inbox-waiter-stop.sh`: hooks-seats-guards (issue 229).
- `skills/worktreereview/scripts/review.py`: hooks-seats-guards (issue 262).
- `scripts/board.sh`: hooks-seats-guards (issue 230). Item 17 only deletes lines. dashboard-parity's issue 269
  (a peer panel) was to read the old question 2's peer setting, which is not built (owner answer 1).
- `scripts/dashboard.sh` is only called (item 10's step), not changed; issue 263's login is what item 10's
  precondition reads.
- `.claude-plugin/plugin.json`, `README.md:4`, `CHANGELOG.md`: all three units (the version).

## Size

About 2,600 changed lines, in one unit (owner answer 2). The 0.21.0 plan estimated 2,700 and its build ran
sixteen passes; the 0.20.0 plan estimated 1,060 and changed about 1,400, so this estimate may also be low.
Item 16 (issue 307) is about 280 of it and goes last.

| Item | Lines |
|---|---|
| 4, issue 283 (auto-close, keys, dedupe, budget) | 420 |
| 8, issues 254 + 258's merge gate (auto-merge) | 310 |
| 16, issue 307 (reuse, merge train) | 280 |
| 3, issue 281 (no duplicate carry) | 195 |
| 2, issue 252 (carry, no strand) | 185 |
| 9, issue 253 (routine items) | 150 |
| 12, issue 259 (CI watch, push-ask) | 150 |
| 14, issue 290 (relay timer check) | 150 |
| 6, issue 267 (line and ceiling) | 120 |
| 10, issue 255 (post-merge steps) | 120 |
| 7, issue 275 (binding line) | 110 |
| 11, issue 306 (R1-R14) | 80 |
| 1, issue 293 (Builder effort) | 60 |
| 5, issue 300 (alerts, restart measure) | 60 |
| 13, issue 284 (planning scratch) | 60 |
| 15, issue 305 (owner-bound questions) | 60 |
| 17, `board.sh` chain lines (cleanup) | 45 |
| Version and CHANGELOG | 50 |

## Prior art

- **Item 1:** layered configuration with a stated precedence (user setting over project file over built-in
  default), as git's system/global/local config does, and a `doctor` that names each value's source, as
  `git config --show-origin` does.
- **Items 2-4:** a write-ahead check before a restart, and idempotent carry-over keyed by a stable id (as a
  database migration is keyed by its version, not its text). Auto-close by evidence is GitHub's "closes #N":
  close when a checkable fact holds. The dedupe command keeps a backup first, as `sed -i.bak` does.
- **Item 5:** measure before optimising: log fields first, then before/after numbers.
- **Items 6-7:** a soft limit with a hard limit under the real one (ulimit's soft and hard limits), and a
  write-only mode past it, as a database goes read-only on a full disk except for the log it needs.
- **Items 8, 16:** merge queues (GitHub's merge queue, bors, Zuul): merge only on a green check of the exact
  commit, test the combined tip once, bisect on red.
- **Item 9:** alert routing by severity (Alertmanager): routine to a digest, judgement pages.
- **Item 10:** an allow-list of post-deploy hooks with preconditions, as package managers run only declared
  post-install scripts.
- **Item 11:** remove a step that no failure needs (Lean's "non-value-adding step").
- **Item 12:** GitHub's own `gh run watch` and `gh run rerun --failed`; one retry for a flaky job, as CI
  retry policies cap retries.
- **Item 13:** build artifacts kept out of the source tree (out-of-tree builds).
- **Item 14:** a watchdog timer: one periodic health check that names what is down, instead of a model-driven
  timer.
- This repository has no `.claude/paved-road.md`. Nothing here adds a dependency or a service; `gh` is already a
  requirement.

## Not built

- Issues 223 and 228: on hold until the host project fixes them.
- Issues 296 and 297: closed as won't-do; the plugin does not add support for a second machine (owner answer 1).
  Issue 307 (item 16) carries 297's parts that need none.
- Issue 258's nudges and dead-pane alerts: not in this unit; only its merge-gate part is (item 8).
- Issue 232's "longer term" durable decision consumer.
- Issue 254's `--report` flag (item 8 says why).
- Issue 255's "typed yes for irreversible steps": no irreversible step is on the allow-list (question 4).
- Issue 300 part 1: no plugin watcher alerts on the lines (item 5 says why and pins it).
- Issue 305 part 2's fix, if the time-boxed search finds no cause.
- Issue 306's R1-R9 and R12: not applicable or a sibling's, with reasons in item 11.
- Anything without a Commandeck issue in this unit's table.

PLAN-DONE

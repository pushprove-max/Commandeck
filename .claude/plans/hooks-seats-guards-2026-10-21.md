# hooks-seats-guards-2026-10-21 -- hooks, seats and guards: one of three units for every open plugin issue

Order: the owner: "after those merge, build ALL open Commandeck plugin issues, batched as main sees fit". Main split the
open issues into three units built in parallel. This is one of them. Its scope is 32 issues: 216, 225, 229, 230,
234, 236, 238, 241, 246-250, 256-258, 260-262, 264-266, 268, 278, 282, 287-289 and 301-304. Thirteen of them shipped
in 0.21.0 and main closes them (item 0). Issue 268 is half shipped. This build is the other 19, items 1 to 17.
Issues 215, 233, 279, 285, 286 and 298 wait on the host project and are not planned.

Launch: new unit hooks-seats-guards-2026-10-21
Order: "after those merge, build ALL open Commandeck plugin issues, batched as main sees fit" (owner order, 2026-10-20)

Base: main 97382ff (0.22.0).

Public repo: no personal names, handles, pane names (other than the existing seat folder name `Chief-of-Staff`)
or user paths in any shipped file, comment, test, commit message or changelog line. Outside CHANGELOG.md an issue
number is written "issue N". "The host project" is the project this plugin was taken from. Its issue numbers are
written "host issue N", and no host file path is written anywhere. Commit titles are plain. Test fixtures use dates
before 2000 for ruling ids.

Port rule (owner ruling): a PORT item copies the host commit's change into the plugin's own files. It does not
redesign it. Each PORT item below names the host commit it copies and says what that commit's diff showed. Where the
diff does not fix the issue, the item says so and is built from the issue text.

Skill for the build: `mattpocock-skills:tdd`. Every item with logic is red first. Items that change only text
(the rule lines in items 1, 2 and 17) have a grep test instead of a red run.

## Done when

- `bash scripts/run-shell-tests.sh` (the whole suite, not `--changed`) is green on the tip before the final review.
  The Builder records the tip, the time taken and the totals in the evidence file. The suite also passes once with
  jq 1.7 first on `PATH` (CONTRIBUTING.md).
- `dashboard-view.test.sh` runs and is not skipped. `COMMANDECK_TEST_NODE_MODULES` names a node_modules folder that
  has jsdom, and the evidence file names that folder. This unit does not change the page, but the suite must run it.
- `claude plugin validate .`, `bash ci/leak-test.sh`, `bash ci/version-check.sh main` and
  `bash scripts/startup-size.sh` pass.
- No install, uninstall or whole-setup run, and no end-to-end test (owner ruling 2026-10-16). The tests drive
  functions and scripts on scratch HOMEs, as they do today.
- Each of items 1-17 meets its own "Done" line, built to the owner answers below. Answer 3 is not the answer the
  plan recommended: item 7 builds the `maxBuilders` cap.
- No item adds support for a second machine (a peer host). The Builder checks this in the final diff.

## Owner answers

1. Issue 287: a written rule, no mechanical gate. Item 2.
2. Issues 302, 303 and 304: build them now, from the issue text. Items 15-17.
3. Issue 256: add a `maxBuilders` cap setting, read under one admission lock. Item 7.
4. Issue 258: its merge-gate part goes with issue 254 in the sibling unit merge-checkpoint-relay-2026-10-21.
   Item 14 drops it.
5. Issues 260 and 266: as the host does, `review` stays narrowed before the first closing pass.
   Item 10.
6. Issue 265: port the merge refusal too. Item 6, in `merge-unit-local.sh`.
7. Plugin-wide: the plugin does not add support for a second machine. No item in this unit had a
   peer-host part: none of its 32 issues asks for one. Issue 256's "host load" is not built (item 7).

## Item 0. Close as shipped (main closes these; no build)

Each was checked at 97382ff against its issue's "done when". 0.21.0 is the commit range c4ece92..2b99aad.

| Issue | Shipped in | Evidence |
|---|---|---|
| 216 | 2b99aad (0.21.0) | `hooks/no-poll-loops.sh:22-23`, `:239`, `:317` read the script of `bash -c`, `sh -c`, `zsh -c`, `eval` and `env -S`; tests `hooks/__tests__/no-poll-loops.test.sh:354-362`, one per spelling |
| 225 | 2b99aad | `scripts/read-verdict.sh:351-361` (`--repeat-class`); rule `templates/main-session.md:102-104`; brief line `templates/_builder-brief-template.md:25-26`; tests `scripts/__tests__/read-verdict.test.sh:45-49`, `scripts/__tests__/orca-wait.test.sh:69` |
| 229 | 2b99aad | one line per long wake: `scripts/cos-lib.sh:14`, test `scripts/__tests__/cos-tell.test.sh:279`; 600-character tail and the subagent rule for reads over 10 KB: `hooks/agent-startup-context.sh:139`, test `hooks/__tests__/agent-startup-context.test.sh:68-71` |
| 230 | 2b99aad | do-not list `templates/main-session.md:5`; the merge detaches itself `scripts/merge-unit-local.sh:30-33`, `scripts/run-shell-tests.sh:41`, `scripts/merge-queue.sh:14`; `scripts/board.sh:15`, `:25` (`--unit <u> --seats`); test `scripts/__tests__/run-shell-tests.test.sh:10` |
| 234 | 2b99aad | `scripts/builder-launch.sh:81-89`, `scripts/seat.sh:266-268`; test `scripts/__tests__/seat.test.sh:98` |
| 236 | 2b99aad | `scripts/seat.sh:461-466` (`report=` in the record), `scripts/read-verdict.sh:513-516` (`--seat`); test `scripts/__tests__/seat.test.sh:123-124` |
| 238 | 2b99aad | `scripts/main-watch.sh:483`, `:841` (a second reading before a restart or stopped post); tests `scripts/__tests__/main-watch-wake.test.sh:100`, `scripts/__tests__/main-watch-helper-hold.test.sh:61` |
| 241 | 2b99aad | `hooks/ask-records-decision.sh:16-18`, `:49`; test `hooks/__tests__/ask-records-decision.test.sh:136` (no relay: the repeat goes out), `:14` (a relay keeps the block) |
| 246 | 2b99aad | `scripts/red-proof.sh:8`, `:54` (a whole run of a case-aware file is refused), `:6`, `:17` (`--batch`, one worktree); test `scripts/__tests__/red-proof.test.sh:66-69` |
| 247 | 2b99aad | `hooks/read-range-guard.sh:3`; `hooks/bash-guardrails.sh:8` (inline-script writes); tests `hooks/__tests__/read-range-guard.test.sh:2`, `builder-search-guard.test.sh:91`, `batch-independent-looks.test.sh:33`, `bash-guardrails.test.sh:120` |
| 248 | 2b99aad | `hooks/__tests__/bash-guardrails.test.sh:20-23` (`BASH_GUARDRAILS_TEST_CASE`); `:235-240` pins that a filter counts only its cases and that a filter matching no case fails; the brief line `templates/_builder-brief-template.md:82` |
| 249 | 2b99aad | `hooks/batch-independent-looks.sh:145-151`: it polls every 100 ms for siblings instead of a fixed 1.5 s sleep. **Gap:** the issue asks for the median per-run time before and after, and no commit or evidence file records it. Main may close it as is, or ask this unit's Builder to time 3e588fe against the tip on a nudging call (item 0 adds no build). |
| 250 | 2b99aad | `scripts/hook-probe.sh`; the pass prompt asks for an executed probe when `hooks/` changed, `scripts/builder-codex-pass.sh:948-950`; tests `scripts/__tests__/hook-probe.test.sh`, `scripts/__tests__/builder-codex-pass.test.sh:303-307` |

**Half shipped: issue 268.** Its second part (the CI-only failure) was the Linux truncation fixed in 9fb00ef (0.22.0,
`hooks/agent-startup-context.sh`, `tee -a`). CI on 8e2ee94 passed `agent-startup-context.test.sh` and the whole job
(run 39448157139). The first part, naming every failing case, is item 9.

Host commits listed for shipped issues (413dab38, 655041d5, 6abe413f) were not diffed: nothing is left to port.

## Priority

- **P1, issue 282 (item 1).** An exception that nothing proves can hide a real gap for months, as it did in the host
  project. It is mostly text and a census, and it sets the rule items 4 and 6 follow.
- **P1, issue 287 (item 2).** An old yes can open any new unit. It is a written rule (owner answer 1).
- **P1, issue 288 (item 3).** A lost verdict leaves main idle with no signal. It is built with item 5 (issue 257),
  whose runner it governs, and before the sibling's issue 253 lands, if main can order it so.
- **P1, issue 289 (item 4).** A Sonnet Builder's later fix rounds stay on Sonnet, and those rounds are the hard
  ones.
- **P2:** issue 265 (item 6; a fix round can ship a behaviour the owner has not decided), 256 (item 7), 301 (item 8;
  a leaked lock stalls the next merge for minutes) and 268 (item 9).
- Then the P3 items, grouped by the files they share (see "Order of work").

## Item 1. Issue 282 (P1): a guard's exception stands only when its test proves it

PORT of 4aa3dbd7 (rule text) and the census half of bb45e387. Diff read: 4aa3dbd7 adds the rule to the host's test
rules and review policy. bb45e387 "Cut 5" lists every exception entry in the host's guard tests, then proves,
deletes or keeps each one with a reason.

- **Change:** the same rule in three shipped places: `templates/global-rules.md` "## Tests and planning",
  `templates/_builder-brief-template.md` "How to work", and the review focus in `scripts/builder-codex-pass.sh`
  (`FOCUS_REVIEW`, `:118`, and angle 1, `:134`). The rule: an exception, allowlist or exemption entry in a guard
  or its test stands only when the same test proves the alternative it claims, or the entry cites an owner ruling
  id. A comment is not proof. A reviewer reports an unproven entry as P1.
- **Census:** the Builder lists every exception entry in the plugin's guards and their tests with
  `rg -n -i '(allow|exempt|except|skip|ignore)' hooks scripts ci --glob '!**/fixtures/**'`, and keeps the list in
  the evidence file. Known entries to rule on:
  - `ci/leak-words.txt:5-12`: exempt paths (CHANGELOG.md, the word list, a .png's pixels) and two allowed texts;
    `ci/leak-test.sh:56` (four files may hold the owner's name). Check that `ci/__tests__/leak-test.test.sh` proves
    each one.
  - The `exempt-path-regex` column of each rule in `hooks/edit-content-tripwires.sh` (`:18`, `:375-379`).
  - Scratch paths allowed by the inline-script write guard (`hooks/bash-guardrails.sh:8`), and `own_setup` in
    `hooks/dependency-addition-guard.sh`.
  Each entry is (a) proved by a new case in its own test, (b) given an owner ruling id, or (c) deleted with the test
  still green. An entry that cannot be proved and has no ruling is listed under "Left" for main to ask about. It is
  never deleted when deleting it would block real work.
- **Red first:** one grep test per shipped place (`hooks/__tests__/agent-startup-context.test.sh` already checks
  rule text; put the three greps in `scripts/__tests__/builder-codex-pass.test.sh` for the prompt and a new case in
  `scripts/__tests__/startup-size.test.sh` or `plugin.test.sh` for the templates). Each new proof case is seen red by
  `red-proof.sh` with its entry's alternative broken. Its `Mutation-verified:` line goes in the evidence.
- **Done:** the rule is in all three places. Every census entry has a proof case, a ruling id or a reason under
  "Left". **Size:** about 15 text lines, and 40-80 test lines, depending on the census.

## Item 2. Issue 287 (P1): only the owner's yes that names the unit or its issues is a build order

PORT of 28482350's outcome. Diff read: the host's mechanical order check (its Cuts 1 and 2) was removed before the
merge by the host owner's ruling. What merged is the plan-close fix (host issue 2987, not a plugin issue) and the
pane title (item 13). So the host commit does not build the issue's gate. The owner ruled for the host's shape: a
written rule and no gate (owner answer 1).

- **Change:** in `templates/main-session.md` beside the Launch rule (`:87-92`), and in
  the relay's startup block (`hooks/agent-startup-context.sh`, the block around `:139`): "A build order is the
  owner's yes that names this unit or each issue in its scope. Filing an issue, approving a lesson, or 'this needs
  fixing' is never one. A 'file only' or 'not now' answer is never one. Without such a yes, ask the owner. The
  `Order:` line quotes that yes, with its ruling id, and the batch's scope lists only the issues it names." The
  planner and Builder launch refusals (`builder-launch.sh:86`, `seat.sh:268`) end with "the Order line must quote the
  owner's yes naming this unit or its issues". No launch reads the rulings log for this: no new gate.
- **Red first:** grep cases in `hooks/__tests__/agent-startup-context.test.sh` (main and relay) and in
  `scripts/__tests__/seat.test.sh` for the refusal text.
- **Done:** the cases pass. Startup size stays under its cap (`scripts/startup-size.sh`). **Size:** about 10 lines and
  10 test lines.

## Item 3. Issue 288 (P1): every seat verdict and every lone exit notice reaches main

PORT of 270061d0 and the drain half of e18f3512. Diff read: 270061d0 makes the host's seat runner keep collect's
verdict wake, and fixes its test from "no wake" to "exactly one wake". e18f3512 deletes the drain's rules 4 (hide
`seat <role> <unit>:` while a driver lives) and 5 (hide subjects ending ` exit rc=N`), because the host has no
driver script left.

- **Cause in the plugin:** `scripts/orca-wait.sh:268-275` keeps both rules. The plugin starts no `loop-*` or
  `drive-*` service: no caller of `hs_start` exists outside `scripts/host-services.sh`. So `driver_units` lists only
  stray services, and rule 4 can hide the one copy of a verdict under a dead driver's stale unit. Nothing in the
  plugin sends ` exit rc=N`. A second path, **to verify red first**: `pp_detach` (`scripts/paths.sh:230-235`)
  sends the merge's or a suite's "`<label>: exit <rc>`" as type `status` through `to-main.sh`, from a child of main's
  pane. If Orca stamps that message with main's own handle, rule 8 (`own`, `:281`) hides it as "main's own status
  note", and a lone exit notice is lost.
- **Change:** delete rules 4 and 5 and their comment lines (`:231-242`), and `seat_unit`, as the host did. If the
  `own` case is red, `own` no longer matches a subject ending `: exit <n>`. Item 5's runner keeps collect's wake
  (`seat.sh:484`): it never sets `COMMANDECK_DRIVER=1` for collect.
- **Interaction with the sibling's issue 253** ("wake only for judgement"): if it lands first and an all-hidden batch
  no longer wakes main, these cases still pin that a verdict and an exit notice are never in the hidden set. The
  Builder rebases on it and keeps the cases.
- **Red first,** `scripts/__tests__/orca-wait.test.sh`: (a) `seat certifier u1: GO` while `driver_units` lists
  `u1` is shown; (b) a lone `merge-unit-local.sh u1: exit 1` status from main's handle is shown; (c) item 5's
  `seat.sh run` sends exactly one wake per verdict (in `scripts/__tests__/seat.test.sh`).
- **Done:** the three cases pass, and the drain's other rules' cases are unchanged. **Size:** about 20 lines (most
  deleted) and 35 test lines.

## Item 4. Issue 289 (P1): from the second fix round on, the Builder's fresh session runs on Opus

NO-HOST: no host commit was named or found.

- **Cause:** a plugin fix round is not a new seat. `builder-codex-pass.sh:1166` starts `builder-fresh-round.sh`,
  which types `/clear` into the same pane (`:72`) and then the hand-off pointer (`:74`). The pane keeps the model it
  was launched with (`opts=--model ...` in the seat record, `seat.sh:340`). A Sonnet Builder therefore runs every
  round on Sonnet.
- **Change:** `builder-fresh-round.sh` takes the round from the hand-off's name (`<unit>-fix-r<N>.md`). For a fix
  round after pass 2 or later, it types `/model opus` after the new session is idle and before the pointer. It
  then appends `model=opus` to the seat record. Fix round 1 and work added by `builder-add-work.sh` keep the
  Builder's model. An Opus Builder gets no `/model` line. The dashboard already shows a seat's real model from its
  session log (`scripts/dashboard.sh:182-189`, `seat_actual`), so the step up is seen there with no page change.
- **Red first,** `scripts/__tests__/builder-fresh-round.test.sh` with the stub orca: a Sonnet seat record and
  `fix-r1` gets no `/model`; `fix-r2` and `fix-r3` get `/model opus` between `/clear` and the pointer, and the record
  gains `model=opus`; an Opus record gets none.
- **Done:** those pass. **Size:** about 12 lines and 30 test lines.

## Item 5. Issue 257: `seat.sh run`: launch, wait, collect, one line back

PORT of f84705bf (the `run` verb) with 270061d0 (keep collect's wake). Diff read: `run` refuses `builder` roles,
then launches, waits on the marker (default `VERDICT: GO`), collects, and prints one line:
`seat=<role> unit=<unit> <verdict> report=<path>`. Exit 0 on GO, 1 on NO-GO, 3 with no verdict, the launch's own
code when the launch is refused.

- **Change:** the same verb in `scripts/seat.sh` (usage at `:31-44`, the `case` at `:46`), with the plugin's
  `report=` path from the record (`seat.sh:466`). Main never blocks: in main's own foreground (`pp_main_foreground`)
  `run` restarts itself detached with plain `nohup` and prints its pid and log. It does not use `pp_detach`, whose
  exit note would be a second wake for the same event. collect sends its usual verdict wake (`:484`). A run that
  ends with no verdict or a refused launch sends one `to-main.sh` line itself. So each outcome is one wake (item 3).
- **The issue's gates:** a narrowed review never runs through a seat in the plugin (review passes are the pass
  script's), so `run` cannot close a unit. A dead pane gives exit 3 and "no verdict", never GO. `run` files nothing
  and merges nothing.
- **Red first,** `scripts/__tests__/seat.test.sh` with its stub orca: one line on GO and on NO-GO, with a report path
  that exists; a pane killed mid-run gives exit 3 and no verdict; `run builder` is refused; exactly one wake per
  outcome.
- **Done:** those pass; `templates/main-session.md` names `seat.sh run` where it names launch and collect today.
  **Size:** about 40 lines and 50 test lines.

## Item 6. Issue 265 (P2): a fix round never changes a behaviour the owner has an open question on

PORT of 8750bdda "Cut 3" (host issue 2952). Diff read: the pass prompt gets a block of the owner's decisions that
name the unit (open: "Open question to the owner <id>", answered: "the owner answered <id> (<question>):
<answer>"). The reviewer tags a finding on an open question `[HOLD <id>]`. The fix hand-off gets an
`## Open decisions (HOLD)` section read again just before it is written. A ledger that cannot be read is said so,
never shown as "none". The merge refuses while an open decision names the unit.

- **Change:** `scripts/builder-codex-pass.sh`: a `HOLD_HEAD` block in the prompt (`REST`, `:964`) from
  `decision.sh list` filtered as the host does (`id + question + source` contains the unit), and the HOLD section in
  the hand-off (`:1149-1164`): "Do not fix a finding tagged [HOLD <id>] or one that touches these questions: send
  it to main as a question with the id, and fix the rest." By owner answer 6, `scripts/merge-unit-local.sh` also
  refuses a merge, a dry run and a hand merge included, while such a row is open or the ledger cannot be read. The
  sibling's issue 254 (a unit merges itself after a final GO) goes through the same script, so the refusal holds for
  it too: see "Files a sibling unit also touches".
- **Red first,** `scripts/__tests__/builder-codex-pass.test.sh` with a scratch ledger: an open row naming the unit
  puts its id in the prompt and the hand-off; an answered row shows its question and answer; a malformed ledger
  says "could not be read"; an empty ledger adds nothing. `scripts/__tests__/merge-unit-local.test.sh`: an open row
  refuses with the id; an answered one merges.
- **Done:** those pass. **Size:** about 35 lines and 55 test lines.

## Item 7. Issue 256 (P2): `builder-launch.sh --from-plan`: from a judged plan to a live Builder in one call

PORT of f84705bf (`--from-plan`) and the 813b3c67 follow-up. Diff read: the batch brief defaults to
`<wt>/.claude/briefs/<unit>-batch.md`. The plan in the planning worktree must be byte for byte what the plan judge
read (a `planhash=` the judge's seat record took at launch), or the one revision collected after it. A frozen copy
is checked, installed on main, and only then is the Builder launched. `--dry-run --from-plan` checks the same and
installs nothing. The host's plan install script has no plugin twin. The Builder cap and its admission lock are built
here by owner answer 3. The host-load check is not built: the answer names the cap only.

- **Plugin today:** main commits the plan by hand from `<unit>` (`templates/main-session.md:92`), then
  `builder-launch.sh` checks it is on main (`plan_ok`, `:91-95`). Plan-judge seats exist
  (`config/routing.json:37-65`) but record no plan hash.
- **Change:**
  - `scripts/seat.sh launch plan-judge-*` appends `plan=<path>` and `planhash=<sha256>` of
    `<wt>/.claude/plans/<unit>.md` to the record. collect of `plan-author` appends the same for the plan it leaves.
  - `scripts/builder-launch.sh --from-plan <unit>`: the Launch line is checked first (issue 234, as today), and the
    judge record must hold a verdict for the same plan path. The frozen copy's hash must match the judge's on a GO,
    or the plan author's revision collected after a NO-GO. Then it commits that copy alone to main as
    `plan(<unit>): plan` and launches as today. A failure stops with one `REFUSED:` line. A retry after a later
    failure finds the plan already on main, byte for byte, and goes on.
  - `plan-worktree-close.sh --adopt` accepts the worktree's plan file when it matches the frozen copy.
- **The Builder cap (owner answer 3):**
  - **The option:** `maxBuilders` in `.claude-plugin/plugin.json` `userConfig`: `"type": "number"`, title "Builder
    cap", description "The most Builders that may run at once, over all units. Empty: no cap.", `"min": 1`, and no
    default, as `maxReviewRounds` has none. Empty is today's behaviour. Setup asks nothing for it; the owner sets it in
    `/config`.
  - **Where it is read:** `pp_option maxBuilders` (`scripts/paths.sh:627`), with a new case `maxBuilders)
    p=.builder.maxBuilders`. The `/config` answer comes first; `builder.maxBuilders` in the project's file is read only
    when an owner writes it by hand. The doctor's option list (`il_options_report`) then shows it with no other change.
    A value that is not a whole number of 1 or more refuses the launch and says to change it in `/config`.
  - **Where it is checked:** in `scripts/seat.sh` for role `builder`, just after `pp_builder_lock` (`:284`), so a
    `--from-plan` launch, a plain `builder-launch.sh` launch and a hand launch with `seat.sh` all count. With a cap set,
    the launch takes one admission lock, `$PP_SCRATCH/builder-admission.lock` (`flock -w 600`, held until the process
    exits, as `pp_builder_lock` is), and counts the live Builder panes: rows of `pane-titles.tsv` whose title is a
    Builder title (`pane_title builder <u>`) and whose handle is a connected pane in `orca-ide terminal list --json`.
    At the cap it stops with one line: "REFUSED: <n> Builders are running (<handles>), the maxBuilders cap in
    /config; close one or raise the cap". A pane list that cannot be read refuses too, and says so. The unit lock is
    always taken before the admission lock, so two launches cannot wait on each other. With no cap, no lock is taken
    and nothing is counted.
  - `--dry-run --from-plan` prints the count and the cap, takes no lock, and opens nothing.
- **Red first,** `scripts/__tests__/builder-launch.test.sh`: no judge record refused with the reason; a plan edited
  after the judge's GO refused; a NO-GO plus a collected revision passes; `--dry-run` installs nothing; a full run
  commits the plan and opens one Builder (stub orca); a second call while that Builder is live is refused. For the
  cap, in `scripts/__tests__/seat.test.sh` with the stub orca: cap 1 and one live Builder of another unit refuses
  and opens no pane; cap 2 with the same state launches; no cap launches and takes no lock; a cap of 0 or text
  refuses with the `/config` line; two launches started together under cap 1 open one pane (the lock). In
  `scripts/__tests__/plugin.test.sh`: a `maxBuilders|"none"|-` row, where `-` marks an option setup does not ask
  (the row checks the default only), and the option count goes from 10 to 11. `scripts/__tests__/plugin-option.test.sh`:
  `pp_option maxBuilders` reads `/config` first, then the project's file.
- **Done:** those pass; `templates/main-session.md:92` names `--from-plan`; `README.md` names `maxBuilders` where it
  lists the `/config` options (`:340`). **Size:** about 105 lines and 100 test lines.

## Item 8. Issue 301 (P2): tests under the merge lock do not hold it after the merge ends

PORT of 88237d40 "Cut 1" (host issue 3004). The issue named 73663a12, but its diff fixes Stop-hook log lines and
fixtures and touches neither the lock nor the fresh-round loops. Diff read of 88237d40: the merge takes its lock with
`flock -o`, so children do not inherit the descriptor. The fresh-round test cases run each pass in its own process
group, killed on exit.

- **Reproduced while planning:** `scripts/__tests__/builder-fresh-round.test.sh` (8 passed, 6 s) and
  `scripts/__tests__/builder-codex-pass.test.sh` (53 passed, 46 s), run alone at 97382ff, left no
  `builder-fresh-round.sh` process of this checkout behind (0 before, 0 after). The plugin's stub answers its
  idle wait, so its loops end. The lock half is real: `scripts/merge-unit-local.sh:36` is `flock` without `-o`, so
  any child the merge's tests leave running holds the merge lock. The local `flock` supports `-o`.
- **Change:** `flock -o` at `merge-unit-local.sh:36`. In both fresh-round test files, a check at the end that no
  process carrying this run's scratch path is left, and a `trap` that kills the process groups the file started
  (the host's `frs_group` / `frs_reap`), as a guard for a future stub change.
- **Red first,** `scripts/__tests__/merge-unit-local.test.sh`: a merge whose test command leaves `sleep 30 &`
  behind; after the merge exits, `flock -n <lock> true` succeeds. Red without `-o`. The no-leftover checks are pins
  (green today), and the evidence says so.
- **Done:** the case passes; `pgrep -f term_frs` finds nothing of this checkout after the suite. **Size:** about 3
  lines and 30 test lines.

## Item 9. Issue 268 (P2), first part: the runner names every failing case

NO-HOST. The second part shipped (item 0).

- **Cause:** `scripts/run-shell-tests.sh:148` prints `tail -12` of a failing file. The case that failed early is cut
  off, as on CI run 39419662803 for `agent-startup-context.test.sh` (49 passed, 1 failed, no name).
- **Change:** before the tail, print every line of the file's output that starts with `FAIL ` (the `check` form every
  test uses), at most 20, then the tail.
- **Red first,** `scripts/__tests__/run-shell-tests.test.sh`: a scratch test with an early `FAIL` and 30 later `ok`
  lines; the report names the early case.
- **Done:** it passes. **Size:** about 3 lines and 12 test lines.

## Item 10. Issues 260 and 266: a `review` whose GO could not merge runs as the closing pass

PORT of 8750bdda "Cut 1" (host issues 2953 and 2961). Diff read: a `pick_kind` function upgrades `review` to `final`
and prints "final in place of review: <why>; this is the closing pass, its GO merges and no separate final follows".
It does so when the last closing pass, or a pass after it, found a P0/P1 or ended NO-GO naming nothing, or when
commits came after a closing GO (a replay onto main stays narrowed). With no closing pass on record, `review` stays
narrowed (owner answer 5, as the host does). It runs under `--check` too. `--verify` is unchanged.

- **Plugin today:** `builder-codex-pass.sh:822-825` already upgrades `review` to `final` when the brief or rulings
  changed. The same `PASSES` record (`:811`, fields `${8}` ended, `${9}` read, `${11}` said, kind `${3}`) and the `FINDING` /
  `BLOCKER` patterns (`--verify`'s, from `:540-560`) are what `pick_kind` reads. With `reviewLoop.closingPass` off,
  no final is on record, so nothing changes there.
- **Change:** port `pick_kind` beside the scope upgrade. Call it in `--check` (`:855`) on the index's tree and after
  the commit (`:891`) on the commit's tree. Move `FINDING` and `BLOCKER` to the top so both paths read them. The brief
  template's pass steps (`templates/_builder-brief-template.md`) say "final in place of review" means no separate
  final follows.
- **Red first,** `scripts/__tests__/builder-codex-pass.test.sh` (stub reviewer): after a final NO-GO with a P1,
  `review` runs as `final`; after a final that left P2 only, `review` stays narrowed; after a closing GO and a new
  commit, `final`; with no closing pass, narrowed; `--check` prints the same pick.
- **Done:** those pass, and the existing `--verify` cases are unchanged. **Size:** about 35 lines and 60 test lines.

## Item 11. Issue 261: a repeat of one class asks for an approach that fixes the whole class

PORT of 8750bdda "Cut 2" (host issue 2962). Diff read: the earlier-passes block asks the reviewer to tag
`[same class]` on a finding of the same kind of input in the same function, and a hand-off whose findings carry
the tag adds: do not fix it input by input; write in the evidence the approach that fixes the class (for example a
fixed list instead of a parser), fix the other findings first, then send main that approach as a question.

- **Plugin twin:** the plugin already tags every finding `(class: <tag>)` (`FORMAT`, `:101`) and detects two NO-GOs
  in a row on one class (`read-verdict.sh --repeat-class`). So the hand-off reads that, and no new tag is added.
  `EARLIER_HEAD` (`:150`) adds: "a finding of the same kind of input in the same function as an earlier one keeps
  that finding's class tag".
- **Change:** in the hand-off (`:1149-1164`), when `read-verdict.sh --repeat-class <round file>` prints
  `REPEAT CLASS: <c>`, add the approach line naming `<c>`. Its last clause: "If the approach touches an open
  decision (item 6), ask main first."
- **Red first,** `scripts/__tests__/builder-codex-pass.test.sh`: a second NO-GO with the same class adds the line;
  the first does not; two different classes do not.
- **Done:** those pass. **Size:** about 8 lines and 25 test lines.

## Item 12. Issue 264: each finding in a fix brief names its test file, case filter and command

NO-HOST: no host commit names host issue 2951. 8750bdda only narrows the hand-off's test list to `.test.*` files.

- **Change:** in the hand-off, a `## Tests per finding` section. For each finding line (`-- <file>:<line> --`), the
  test file is the file itself when it is a test; otherwise the same-name test, by the rule `--changed` uses
  (`scripts/run-shell-tests.sh:25-28`: `scripts/x.sh` -> `scripts/__tests__/x.test.sh`, the same for `hooks/`).
  Print the file, the case variable when its header names one (`<NAME>_TEST_CASE`, as `red-proof.sh:8` reads it),
  and the commands `bash scripts/run-shell-tests.sh <file>` and `bash scripts/red-proof.sh <file> <line>
  <replacement> -- <command>`. With no same-name test, it says "no same-name test: name the test file in the evidence
  before the fix". Narrow the touched-tests list (`:1163`) to `.test.` files, as the host did.
- **Red first,** `scripts/__tests__/builder-codex-pass.test.sh`: a finding on `hooks/bash-guardrails.sh` names
  `hooks/__tests__/bash-guardrails.test.sh` and `BASH_GUARDRAILS_TEST_CASE`; a finding on a file with no test says
  so; every named file exists.
- **Done:** those pass. **Size:** about 20 lines and 25 test lines.

## Item 13. Issue 278: seat panes carry their role and unit as the title

PORT of 28482350 "Cut 4" (host issue 2965). Diff read: after the wait for the agent to come up, the launch sets
the pane title with `orca terminal set-pane-title --terminal <h> --title "<Role> — <unit>"`, under `timeout 8`,
`|| true`. The agent retitles its pane as it starts, so a title given at create is lost. An older Orca without the
command still launches.

- **Change:** the same line in `scripts/seat.sh` after the tui-idle wait (`:348`), with `pane_title`
  (`scripts/codex-helpers.sh:42`). The same call in `builder-fresh-round.sh` after the new session is idle (`:73`),
  since `/clear` gives a new session that retitles itself. collect closes the pane, so no clear is needed.
- **Red first,** `scripts/__tests__/seat.test.sh` and `builder-fresh-round.test.sh` with the stub orca: the call
  comes after the wait with the right title; with the stub refusing the command, the launch exits as before and
  opens one pane.
- **Done:** those pass. **Size:** about 6 lines and 20 test lines.

## Item 14. Issues 258 and 262: a stopped Builder is nudged once before main is asked; a monitor wait is test time

**Issue 258.** PORT of 73bead80 (host issue 2959). Diff read: `stopped_nudge` types one "Signal STOPPED: you ended
your turn with no DONE line or verdict. If you are waiting on an answer, say what in one line and end your turn;
this is not an answer. Otherwise continue the batch." into a Builder that stopped without reporting. It does so at
most twice per pane, never while an open decision names the unit (an unreadable ledger counts as held). The history
line is written before the send. The post to main waits one repost window and then says "Nudged N min ago". A
Builder read `idle` takes the `done` path. A gone pane posts at once. e18f3512 is the drain change of item 3.

- **Change:** `stopped_nudge` in `scripts/main-watch.sh`, called just before the "stopped without reporting" post
  (`:846`), after the issue 238 second reading (`:841-845`). It uses `builder_watch`'s per-pane history file
  (`$ST/builder-<u>-<h>`) and the same send call (`:261`). After the second nudge, the post is the escalation. The
  issue's merge-gate part ("for a unit waiting to merge, run the auto-merge gate") is not built here: by owner answer
  4 it goes with issue 254 in the sibling unit merge-checkpoint-relay-2026-10-21.
- **Red first,** `scripts/__tests__/main-watch-helper-hold.test.sh` or a new `main-watch-nudge.test.sh` (mind the
  per-file cap, issue 218): an idle Builder gets one nudge and no post; still stopped one window later, it gets the
  post with "Nudged"; a third stop posts with no nudge; an open decision naming the unit posts with no nudge; a gone
  pane posts at once.

**Issue 262.** PORT of aa4cf9de (host issue 2963). Diff read: the worktree review counts a `Monitor` call as a
background job (`Monitor started (task <id>`), and sends it through the test pattern as it does `Bash`.

- **Change:** the three lines in `skills/worktreereview/scripts/collect.py`: `STARTED` (`:55`), the task id from any
  group (`:181`), and `call_kind` (`:233`).
- **Red first,** `scripts/__tests__/worktreereview.test.sh`: a Monitor whose command runs the shell tests is
  `idle_tests`; one whose text names no test is `idle_job`. Both read `idle`/nothing before.
- **Done:** all cases pass. **Size:** 258 about 25 lines and 50 test lines; 262 about 3 lines and 20 test lines.

## Item 15. Issue 302: a fresh session after a long pass, as after added work

NO-HOST: built now from the issue text (owner answer 2). Half met: work added mid-build already starts a fresh session (`builder-add-work.sh:36`).

- **Change:** `builder-codex-pass.sh` hands a fix round to a fresh session only after a NO-GO (`:1145-1148`). It also
  hands over after a GO when the pass took more than 10 minutes, measured from the lock's start to the round file:
  a short "pass N ended GO; continue from the evidence file" hand-off, through the same `builder-fresh-round.sh`
  call.
- **Red first,** `scripts/__tests__/builder-codex-pass.test.sh` with the time seam the test already uses: a GO
  after 11 minutes writes the hand-off and starts the helper; a GO after 2 minutes does not.
- **Done:** those pass. **Size:** about 15 lines and 30 test lines.

## Item 16. Issue 303: a class-stop fix uses one retry path and is tested state by state

NO-HOST: built now from the issue text (owner answer 2).

- **Change:** the item 11 approach line adds: "The class fix has one retry path that does not depend on where the
  state came from, and its test removes each piece of state between two runs (ticks) and shows the retry still
  happens." The same sentence goes in `templates/_builder-brief-template.md:25-26` and the class rule
  in `templates/main-session.md:102-104`.
- **Red first:** grep cases beside item 11's.
- **Done:** they pass. **Size:** about 4 lines and 6 test lines.

## Item 17. Issue 304: behaviour-changing scope after the first pass becomes a follow-up unit

NO-HOST: built now from the issue text (owner answer 2).

- **Change:** `scripts/builder-add-work.sh` refuses once the unit has a round file (`<unit>-r1-reports.md`), unless
  main passes `--small --reason '<one line>'`. The refusal says: "added scope after the first review pass is a
  follow-up unit; file it, or pass --small for a change under about 50 lines". `templates/main-session.md` (the
  "work added mid-build" rule, `:99-101`) says the same.
- **Red first,** `scripts/__tests__/builder-add-work.test.sh`: no round file passes; a round file refuses; `--small`
  with a reason passes and records the reason in the hand-off.
- **Done:** those pass. **Size:** about 12 lines and 25 test lines.

## Version

- `.claude-plugin/plugin.json`: `0.22.0` to `0.23.0` (new behaviour: the second part, per `ci/version-check.sh`).
  If a sibling unit merges first and takes 0.23.0, the Builder takes the next free minor. `README.md:4`, the badge's
  URL and alt text, follows it: `scripts/__tests__/plugin.test.sh:31` holds both to the manifest.
- `.claude-plugin/marketplace.json` has no version field, and no test holds one there, so nothing changes in it.
- `CHANGELOG.md`: `## 0.23.0 -- <date>` on top, one bullet per item 1-17 with its issue number, written as CHANGELOG.md
  writes them. It also says that issues 216, 225, 229, 230, 234, 236, 238, 241 and 246-250 shipped in 0.21.0, and
  that the CI half of issue 268 shipped in 0.22.0.
- About 40 changed lines.

## Order of work: each shared file is touched once

| Step | Items | Files |
|---|---|---|
| 1 | 1 | global-rules.md, _builder-brief-template.md, builder-codex-pass.sh (focus text), census tests |
| 2 | 2 | main-session.md, agent-startup-context.sh (relay block), builder-launch.sh / seat.sh refusal text |
| 3 | 3, 5 | orca-wait.sh, seat.sh (`run`), maybe paths.sh (`own`), their tests |
| 4 | 4, 13 (fresh round), 15 | builder-fresh-round.sh and its test |
| 5 | 6, 10, 11, 12, 16, 15 (hand-off) | builder-codex-pass.sh and its test, in that order: one pass over the prompt, `pick_kind`, the hand-off |
| 6 | 6 (merge), 8 | merge-unit-local.sh and its test |
| 7 | 7, 13 (seat) | seat.sh (records, title, Builder cap and admission lock), paths.sh (`pp_option maxBuilders`), plugin.json (`maxBuilders` option), builder-launch.sh `--from-plan`, plan-worktree-close.sh, plugin.test.sh, plugin-option.test.sh, README `/config` line |
| 8 | 9 | run-shell-tests.sh and its test |
| 9 | 14 | main-watch.sh and its test; collect.py and worktreereview.test.sh |
| 10 | 17 | builder-add-work.sh and its test; main-session.md |
| 11 | version | plugin.json version, README badge, CHANGELOG; the whole "Done when" list, the peer-host check included |

- **Same file, more than one item:**
  - `scripts/builder-codex-pass.sh`: items 1 (focus text), 6, 10, 11, 12, 15 and 16. Items 6, 11, 12, 15 and 16 all
    write the hand-off (`:1149-1164`). Build them in one step so the section order is set once: findings, HOLD,
    approach, tests per finding, rulings, touched tests.
  - `scripts/seat.sh`: items 2 (refusal text), 5 (`run`), 7 (records, Builder cap) and 13 (title). The cap check goes
    just after `pp_builder_lock`, before the launch stamp, so a refused launch opens no pane.
  - `scripts/builder-fresh-round.sh`: items 4 (`/model`), 13 (title) and 15 (GO hand-off). The title goes after
    `/model`, and both before the pointer.
  - `templates/main-session.md`: items 2, 5, 7, 16 and 17. Main's print has a byte cap (`startup-size.sh`), so each
    is one line or an edit to an existing line.
  - `scripts/builder-launch.sh`: items 2 and 7. `templates/_builder-brief-template.md`: items 1, 10 and 16.
  - `scripts/merge-unit-local.sh`: items 6 (merge refusal) and 8. `scripts/orca-wait.sh`: item 3 only.
  - `scripts/paths.sh`: items 3 (`own`, only if its case is red) and 7 (`pp_option`).
  - `.claude-plugin/plugin.json`: item 7 (the `maxBuilders` option) and the version step.
- **Same data:** item 7's `planhash=` record lines are new; nothing else reads them. Item 7's cap reads
  `pane-titles.tsv` as `live_pane_with_title` does, and writes nothing to it. Items 11 and 16 read
  `read-verdict.sh --repeat-class` as it is.

### Files a sibling unit also touches (sets the merge order)

| File | This unit | Sibling and its issues |
|---|---|---|
| `scripts/merge-unit-local.sh` | items 6 (merge refusal while an open decision names the unit), 8 (`flock -o`) | merge-checkpoint-relay-2026-10-21: 221, 239, 254, 255, 296, 297, 306. Issue 254's self-merge and issue 258's merge-gate part (owner answer 4) go through this file: the unit that merges second keeps item 6's refusal case green |
| `scripts/orca-wait.sh` | item 3 | merge-checkpoint-relay: 227, 253, 290 |
| `scripts/main-watch.sh` | item 14 (nudge only) | merge-checkpoint-relay: 253, 254 (with issue 258's merge gate), 300; dashboard-parity: maybe 292 |
| `scripts/builder-codex-pass.sh` | items 1, 6, 10-12, 15, 16 | merge-checkpoint-relay: 243, 297, 306 |
| `scripts/builder-launch.sh` | items 2, 7 | merge-checkpoint-relay: 284, 293 |
| `scripts/seat.sh` | items 2, 5, 7 (records, Builder cap), 13 | merge-checkpoint-relay: 284 (planning files); dashboard-parity: 291 (session lookup) |
| `scripts/run-shell-tests.sh` | item 9 | merge-checkpoint-relay: 296, 297 |
| `scripts/plan-worktree-close.sh` | item 7 | merge-checkpoint-relay: 284 |
| `templates/main-session.md` | items 2, 5, 7, 16, 17 | merge-checkpoint-relay: 235, 253, 275, 305, 306 |
| `hooks/agent-startup-context.sh` | item 2 | merge-checkpoint-relay: 275, 290 (relay block) |
| `templates/_builder-brief-template.md` | items 1, 10, 16 | merge-checkpoint-relay: 293, 306 |
| `skills/worktreereview/scripts/collect.py` | item 14 | dashboard-parity: 271, 272 may read it |
| `.claude-plugin/plugin.json`, `README.md`, `CHANGELOG.md` | version; item 7 (`maxBuilders` option, README `/config` line) | both siblings |

Item 3 is written to hold whichever of it and issue 253 merges first.

## Size

About 1,055 changed lines: about a third code and text, two thirds tests, 40 for the version. Owner answer 3 adds
about 70 (the `maxBuilders` cap in item 7). Plans here have run low: 0.20.0's plan estimated 1,060 and the build
changed about 1,400. So expect up to about 1,400.

| Item | Lines |
|---|---|
| 7, issue 256 (`--from-plan`, `maxBuilders` cap) | 205 |
| 14, issues 258 + 262 (nudge, monitor wait) | 98 |
| 10, issues 260 + 266 (pick_kind) | 95 |
| 5, issue 257 (`seat.sh run`) | 90 |
| 6, issue 265 (HOLD) | 90 |
| 1, issue 282 (exception proofs) | 75 |
| 3, issue 288 (verdicts reach main) | 55 |
| 15, issue 302 (fresh session after a long pass) | 45 |
| 12, issue 264 (tests per finding) | 45 |
| 4, issue 289 (Opus from round 2) | 42 |
| 17, issue 304 (follow-up unit) | 37 |
| 11, issue 261 (approach line) | 33 |
| 8, issue 301 (merge lock) | 33 |
| 13, issue 278 (pane titles) | 26 |
| 2, issue 287 (order rule) | 20 |
| 9, issue 268 (failing case names) | 15 |
| 16, issue 303 (retry path) | 10 |
| Version and CHANGELOG | 40 |

## Prior art

- **Item 1:** an exception list is code: each entry carries its proof, as a lint baseline entry carries an issue
  link, or as a suppression must name its reason (ESLint `--report-unused-disable-directives`, ShellCheck's
  disable-with-reason convention). No library.
- **Item 2:** two-person rule: a change of scope needs the authority's words that name it.
- **Items 3 and 5:** at-least-once delivery: every outcome sends exactly one wake, and a filter never hides the
  only copy (a dead-letter rule, not a drop). `seat.sh run` is the launch-wait-collect pattern of a job runner (a CI
  job's status line), with the full log in a file.
- **Item 4:** model escalation on retry: a harder retry goes to a stronger model, as a support tier escalates.
- **Items 6 and 17:** change control: work on an undecided question is held (a "blocked by" link); scope added after
  review starts is a new change request.
- **Item 7:** content-addressed approval: what was approved is identified by its hash, and only that content is
  installed, as signed artifacts are. The cap is admission control: a counting semaphore taken under one lock, as a
  CI runner's concurrency limit is.
- **Item 8:** `flock(1)`'s `-o` (close the descriptor before running the command), util-linux and the BSD/macOS
  port both. Process groups and `kill -- -<pgid>` for test cleanup (POSIX job control).
- **Item 9:** test reporters name each failure (TAP's `not ok <n> - <name>`, JUnit's per-case failure).
- **Items 10 and 11:** a required status check on the head commit (GitHub protected branches); a circuit breaker on
  one failure class, then a change of approach.
- **Item 12:** each defect carries its reproduction command (a bug report's "steps to reproduce").
- **Item 13:** Orca's own `terminal set-pane-title` (Orca 1.4.232), best effort.
- **Item 14:** a watchdog's soft action before the page (Kubernetes liveness: restart once before alerting). The
  worktree review counts a background wait by what it waits on, as a profiler labels wait states.
- **Item 15:** checkpoint and restart: state in a file (the evidence) rather than in a long-lived process.
- This repository has no `.claude/paved-road.md`. Nothing here adds a dependency or a service.

## Not built

- Issues 215, 233, 279, 285, 286 and 298: on hold until the host project fixes them.
- Issue 287's mechanical gate (owner answer 1).
- A host-load check for `--from-plan`: owner answer 3 names the cap only.
- Issue 258's merge-gate part (owner answer 4): it goes with issue 254 in merge-checkpoint-relay-2026-10-21.
- Any support for a second machine (a peer host), in any item (owner answer 7).
- Issue 249's before-and-after timing, unless main asks for it (item 0).
- The host's plan install script and plan-close change for host issue 2987: they have no plugin issue.
- Anything without a Commandeck issue in this unit's table.

PLAN-DONE

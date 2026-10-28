# Plan: plugin-open-c-2026-10-27: the ten open plugin issues, one unit

Owner's words: Order: the owner, 2026-10-27 21:55 ET: one unit for ALL open Commandeck issues. ONE unit, no split, whatever the size caps say.

Scope is #419-#428 (`gh issue list -R pushprove-max/Commandeck --state open`, 2026-10-27: exactly these ten). Every
requirement below traces to one of their issue texts (comments included) or to the plan spec's section for it.
Nothing else is added.

Closes (expected): #419, #420, #421, #422, #423, #424, #425; #426, #427 and #428 close only if B1 finds the host unit
merged and their cuts are built (else `Refs`).

- Planned size: 25 files, 1030 changed lines

Tier: Standard. LOCAL merge only. Changed-file tests only (`bash scripts/run-shell-tests.sh --changed main`), no
test-timeout raise. Tests run on the PC. Red proofs only for this plan's `Break:` lines: each is run red before pass 1
and recorded in the evidence file as `Mutation-verified: <test file> -- <check label>: RED, <how>`. One unit, no split.
Never edit, weaken, skip or delete an existing test to make it pass.

Helper subagents: hand work to helpers on the smallest model that can do it, and name the model on every call:
`general-purpose` on Sonnet for reading code, test triage and mechanical edits, `Explore` on Haiku for search. The
Builder brief carries this line.

Sources of every port, from the host's local main (`$HOST` below is the host checkout the Builder brief names):
- PC-chain unit: `ee5efa7e` (build) and `665b3946` (ledger). `git -C "$HOST" log --oneline c4bc239f..main --
  .claude/scripts/run-shell-tests.sh .claude/scripts/chain-run.sh .claude/scripts/chain-transfer.sh
  scripts/ci/verify-record.sh` lists `617423b5` and `ee5efa7e` (2026-10-27, host main). `617423b5` is the newest
  change to `chain-run.sh` and the only one after `ee5efa7e`: it claims each job's epoch-second name under
  `~/.cache/chain-stamps` so two launches in one second never share a run directory, and it keeps the real start
  epoch apart (`START`) for the run's meta. Nothing of it is ported: the plugin's peer run directory is
  `mktemp -d run.XXXXXX` (random, `scripts/peer-offload.sh` in the draft), never a timestamp, so two runs cannot
  share one, and the plugin's run has no epoch meta. The ported hunks (keepalive `:276`, `cc_stamp`/`cc_alive`
  `:216-224`, the fetch) read the same at `ee5efa7e` and at host main.
- Fast-lane unit: `86b6bc0f` (build) and `484fa3ca` (ledger). `git -C "$HOST" diff 86b6bc0f main --` on its
  `worktree-setup.sh` and `agent-model-guard.test.sh` is empty (2026-10-27).
- #423 starts from the uncommitted draft diff in the plugin worktree `tooling-pc-chain-2026-10-27` (base `f626ece`,
  this unit's base too); C5 names the draft's red and its fix.
- #419, #426, #427, #428: the host unit `tooling-open-2026-10-27` (host 3244, 3256, 3255, 3258) has not merged
  (`git -C "$HOST" log --all --oneline -i --grep tooling-open-2026-10-27` empty, 2026-10-27). Their cuts are last and
  wait for it (B1).
- #420, #421: no host fix. `git -C "$HOST" log --oneline -i --grep units` hits only the host's MERGING, stage and
  layout fixes; `--grep today` hits nothing about its units view (2026-10-27). Built from the issue texts.

Timed checks (time-bound checks in the test files this unit edits):
- `scripts/__tests__/run-shell-tests.test.sh`: every runner call runs under `timeout 30` (:24, :86, :94, :98, :109,
  :117, :122, :139, :143, :157, :169, :183, :193, :197). C4's fixture (a three-file repo, two runner calls per case,
  each under `timeout 30`) is the heaviest new fixture and goes last, after :199, before the summary at :201.
- `scripts/__tests__/peer-offload.test.sh`: no time-bound check today (`rg -n 'sleep|timeout|deadline' ...` empty,
  2026-10-27). It runs about 15 s on this Mac (base, two runs). C5 adds two: "a fetch of a run whose wrapper died with
  no status returns 1, ended without a status" and "a fetch of a run whose pid now names another live process returns
  1, ended without a status", each fetch under `timeout 20`. C5's and C6's cases go after the draft's fetch case; the
  heaviest new case, C4's "a file run here while the PC was down goes to the PC once it is back, under --skip-passed"
  (two runner calls), goes last, after both timed checks.
- `scripts/__tests__/fast-lane.test.sh`, `scripts/__tests__/worktree-setup.test.sh`,
  `hooks/__tests__/agent-model-guard.test.sh`, `hooks/units-sources.test.tsx`: none (grep for sleep, timeout,
  deadline and poll is empty; the TS tests use the fixed `NOW`).

## Stated limits

(every reviewer is handed these; a finding beyond one is out of scope: a follow-up issue, never a blocker)

- L1 (#423). A dropped session is noticed within 60 s: `-o ServerAliveInterval=15 -o ServerAliveCountMax=4` on the
  run's ssh (`scripts/peer-offload.sh:89`, `grep -n ServerAlive scripts/peer-offload.sh`, 2026-10-27); C5 adds the same
  to the fetch.
- L2 (#423). The peer's output relay uses GNU `tail --pid -s`. The peer is always Linux: the run needs `systemd-run`
  for its memory cage (`scripts/host-services.sh:236-238`). This Mac's `tail` is GNU coreutils 9.12 (`tail --version`,
  2026-10-27), and the tests run on the PC. A BusyBox peer is not supported.
- L3 (#423). A started run nobody fetches is kept on the peer up to two days (the draft's `find ... -mtime +1` sweep).
- L4 (#422). The result ledger grows by one row per local test file per run, with no trim: 195 rows for a full run
  (`ls hooks/__tests__/*.test.sh scripts/__tests__/*.test.sh | wc -l` = 195, 2026-10-27), about 20 KB. One ledger per
  git dir, so a unit's goes with its worktree. Files run on the peer get no row and always rerun (Decision 4).
- L5 (#421). An ad-hoc pane in the main checkout counts under main: the dashboard attributes spend by the session's
  folder (`scripts/dashboard_limit.py:1255-1257`), and such a pane shares main's.
- L6 (#421). `scripts/codex-ask.sh:64` runs `codex exec --ephemeral`, which writes no session file, so neither the
  dashboard nor `/units` counts it (`grep -n ephemeral scripts/codex-ask.sh`, 2026-10-27). The two totals still match.
- L7 (#426). Plans today: 34 files, median 40,361 B, 90th percentile 95,914 B (`wc -c .claude/plans/*.md`,
  2026-10-27). No existing plan fits the budget, so the plans that exist when this unit lands are exempt by name: 35
  names on 2026-10-27 (`{ git ls-files .claude/plans; git worktree list --porcelain | sed -n 's/^worktree //p' | while
  read -r w; do ls "$w"/.claude/plans/*.md; done; } | xargs -n1 basename | sort -u | wc -l`). Every other plan gets
  both checks (Decision 9).

## Question for the owner

None blocks this plan. Two calls are made here and can be reversed by a word:
- #428: land refuses ANY tracked change (staged or unstaged) in main's checkout, also on paths the lane does not
  touch (Decision 7). The issue asks the plan to decide this.
- #419 closes with no code: the plugin's last unit already fixed it (Decision 8).

## Main answers

- A run with any test-case selector in its environment (or any other partial-scope run) neither writes nor reads the
  passed-at-tree ledger.
- The passed-at-tree skip applies only to the files already chosen to run locally, after the offload split.
- The plan defines the folder mapping from what the collector receives (project roots plus recorded transcript paths),
  nested folders and removed units included; the Builder invents no accounting rule.
- The peer keeps a run's result until the local side has received it and validated the nonce; a second,
  acknowledging call then deletes it.
- The fetch ports the host's PID plus process-start-time identity check; a live but mismatched PID ends the wait.
- An interrupted fetch stream (fake success line, no authenticated footer) fails closed, and the named mutation that
  removes nonce validation is caught by that case.
- No opt-in marker: the budget and citation checks apply to every plan except a fixed list of the plan files that
  exist when this unit lands, committed with the unit, which authors cannot add to. The owner decided this evening that
  the format is mandatory for new plans and in-flight plans are exempt; this list is that exemption.
- The reused-result line keeps the runner's output grammar with a `0s` seconds field, and a parser case pins it.
- B1, C7 and C9 each carry a `Catches:` line.
- The provenance names the current host main; its newest `chain-run.sh` change only reserves unique run names, which
  the plugin's random `mktemp` run directories already give, so nothing of it is ported.

## 1. Item map

| Issue | Host hunks ported | Plugin today (file:line) | Lands at | Cut |
|---|---|---|---|---|
| #424 | host `.claude/scripts/worktree-setup.sh:105-110` (lane flag), `:172-176` (Agent taken off the deny list for the lane); host `agent-model-guard.test.sh` 4-case loop (+16) | `scripts/worktree-setup.sh:130` DENY holds `Agent` for every worker, `:186` removes it only `if $plan`; `hooks/agent-model-guard.sh:10-11` already runs a named model as named outside Builder, plan-author and fix-round panes | `scripts/worktree-setup.sh:173-175`, `:186` | C1 |
| #420 | none | `hooks/units-sources.ts:102` `NOT_UNITS` = chief-of-staff, research, walkthroughs; `scripts/dashboard.sh:335` gives a standing folder the stage of its lowercased name | `hooks/units-sources.ts:102` | C2 |
| #421 | none | `hooks/units-sources.ts:250` `todayUsd` = lifetime cost of units merged today + lifetime cost of in-flight rows; the dashboard's day is `scripts/dashboard_limit.py:1243-1261` | `scripts/dashboard_limit.py:1257-1260`; `hooks/units-sources.ts:102-123`, `:250`, `:257`, `:306` | C3 |
| #422 | host `.claude/scripts/run-shell-tests.sh:1-2` (usage), `:42-51` (flags), `:56-64` (work tree hash), `:93-98` (`last_whole_row`), `:139-158` (`skip_same_tree`), `:160-163`, `:276`; host `run-shell-tests.test.sh:246-286` | no flag, no ledger (`rg -n 'hs_test_run|test-runs' scripts` empty) | `scripts/run-shell-tests.sh:2`, `:69-70`, after `:132`, `:160-174`, `:218` | C4 |
| #423 | host `chain-run.sh:276` (keepalive on every peer ssh), `:544-545` (detached run), `:285-300` and `:468-472` (fetch once by name), `cc_stamp`/`cc_alive` `:216-224` (bounded wait by pid and start time), `:570` (drop message names the fetch); plugin draft diff | `scripts/peer-offload.sh` (144 lines): a live-only run, one ssh session | `scripts/peer-offload.sh`, from the draft | C5 |
| #425 | host `chain-transfer.sh:65-75` and `verify-record.sh:247-249` (admit by tested tree) | no live-HEAD admission exists (A1): the peer checks the tree it was sent (`scripts/peer-offload.sh:108`), and merge reuse compares trees (`scripts/merge-unit-local.sh:604-607`) | tests only, `scripts/__tests__/peer-offload.test.sh` | C6 |
| #428 | host 3258 (waits for host merge) | `scripts/fast-lane.sh:79-170` `land`: branch check :85, verdict read :86-164, `merge --ff-only` :167, `landed` :169; no checkout check at all | `scripts/fast-lane.sh` after :85 and after :167 | C7 |
| #419 | host 3244 (waits for host merge) | fixed at `f626ece`: `scripts/bgrun.sh:7-9`, `:28-36` (process group); `scripts/__tests__/bgrun.test.sh:28-40` holds the issue's failing input | nothing, unless B1 finds a host case the plugin lacks | C8 |
| #426, #427 | host 3256, 3255 (waits for host merge) | `scripts/plan-check.sh:75-84` reads only the size, `Test:` and `Mockup:` lines | `scripts/plan-check.sh` after :84; new `scripts/plan-evidence.py`, `scripts/plan-format-exempt.txt`; `scripts/seat.sh:432-436` | C9 |

## 2. Cuts (build order)

Each cut lists what it changes, what it Produces and Consumes, the existing consumers of any contract it changes, its
size, its acceptance tests and its `Break:` lines.

Shared-file edit order: `scripts/__tests__/worktree-setup.test.sh` C1, C2; `hooks/units-sources.ts` C2, C3;
`hooks/units-sources.test.tsx` C2, C3, C4; `scripts/__tests__/peer-offload.test.sh` C4, C5, C6 (C4's case is appended at the file's end, clear of the draft's hunks); `docs/tests.md` C4, C5;
`README.md` C4, C5, C10; `docs/worker-panes.md` C1, C7.

Order: C1, C2, C3, C4, C5, C6, then B1, then C7, C8, C9 (waits for host merge), then C10.

### C1 -- #424: the Fast lane and the Research lane may spawn helpers (~50 lines, 4 files)

1. `scripts/worktree-setup.sh` beside :173-175: `AGENTS=false; case $SEAT in Fast-lane|Research-lane) AGENTS=true ;;
   esac`. The two names are spelled here on purpose, not read from `pp_standing_wt`, which also holds Chief-of-Staff
   (Decision 1).
2. `:186`: `if $plan then . - ["Agent"]` becomes `if $plan or $agents then . - ["Agent"]`, with `--argjson agents
   "$AGENTS"`. A rerun on a lane whose file still denies Agent takes it out (the jq already rebuilds the list).
3. `docs/worker-panes.md:13-14`: each lane row adds "may spawn Sonnet and Haiku helpers (the Agent tool is allowed)",
   and one line says a setup rerun applies it to an existing lane.

Produces: lane settings with no `Agent` deny. Consumes: `$SEAT` (:173). Consumers of a changed contract: Claude Code in
the lane panes; `scripts/setup.sh:743` (caller, unchanged); `scripts/plan-worktree-close.sh:52` (`--print-settings`,
never run on a lane). The model guard is unchanged: a lane pane sets neither `COMMANDECK_SEAT` nor
`COMMANDECK_BUILDER`, so `hooks/lib/helper-pane.sh` does not match it and a named model runs as named.

Tests:
- `scripts/__tests__/worktree-setup.test.sh` after :250 (the lane fixtures `Fast-lane Research-lane lanep` exist):
  "a lane may spawn helpers: its settings do not deny Agent; an ordinary worker's do" (`0:0:1`, the count of `Agent` in
  each deny list); "the helper allowance is the two lanes only" (`Fast-lane2`, `Research` and `lanep` each keep
  `Agent` denied: `1:1:1`); "a rerun takes an old Agent deny off a lane" (seed `{"permissions":{"deny":["Agent"]}}`,
  run, `0`).
- `hooks/__tests__/agent-model-guard.test.sh` before :125, the host's loop: "a lane's named Sonnet or Haiku helper runs
  as named" (general-purpose and Explore, each with `sonnet` and `haiku`, no seat env: the model is kept, nothing is
  denied).

Break: scripts/__tests__/worktree-setup.test.sh -- "a lane may spawn helpers: its settings do not deny Agent; an ordinary worker's do" -- scripts/worktree-setup.sh:186 drop `or $agents`
Break: scripts/__tests__/worktree-setup.test.sh -- "the helper allowance is the two lanes only" -- scripts/worktree-setup.sh:<C1 item 1> match `Fast-lane*|Research*`

### C2 -- #420: the standing lanes are never units (~30 lines, 4 files)

1. `hooks/units-sources.ts:102`: `NOT_UNITS = new Set(['chief-of-staff', 'fast-lane', 'research-lane'])`, exported, with
   a comment that these are `pp_standing_wt`'s folders lowercased, as `scripts/dashboard.sh:335` writes them. The stale
   `research` and `walkthroughs` go: nothing in the plugin writes them (A4).
2. `scripts/__tests__/worktree-setup.test.sh` drift check (:251-264): `hooks/units-sources.ts` becomes a site; its
   quoted set, upper-cased the folder way, must equal `$SET`. That makes #416's one list cover the units view, as #420
   asks.

Produces: `NOT_UNITS` (exported; C3 reads it). Consumes: the snapshot's `stage`. Consumers: every reader of
`snap.rows` (BUILDING count, band, status line, toasts, `isIdle`), all in `hooks/units-sources.ts` and `hooks/units.tsx`.

Tests:
- `hooks/units-sources.test.tsx` after :86: "the standing lanes are never units: BUILDING 1, neither lane listed" (a
  real unit plus `Fast-lane` and `Research-lane` rows: `rows` is `['u']`, `paneLines` has `BUILDING  1` and no lane
  text).
- `hooks/units-panes.test.tsx:115` idle case: a new sibling case "only lanes and the relay: no live units" (the two
  lane rows beside the relay row: `No live units.`). The existing case is not edited.
- `scripts/__tests__/worktree-setup.test.sh`: the existing "every standing-worktree list names the same three folders"
  now covers the units view.

Break: hooks/units-sources.test.tsx -- "the standing lanes are never units: BUILDING 1, neither lane listed" -- hooks/units-sources.ts:102 drop 'fast-lane'

### C3 -- #421: today's cost is the dashboard's, split by where it was spent (~235 lines, 5 files)

1. `scripts/dashboard_limit.py:1257-1260`: beside `out["today"][name]`, add `byFolder`: today's rows of that project
   grouped by folder key and priced by the same `api_week` call per group. What the collector receives, and so the
   only inputs of the key:
   - per project, three roots: `build`'s `day_projects` is `{name: [path, workspaces, closingCopies]}`
     (`scripts/dashboard.sh:957`, built at `:1147-1148`): the main checkout, the parent folder of every worktree
     (resolved with `pwd -P`, `:1132`), and `$PP_SCRATCH/closing-copy` (`scripts/unit_folders.py:27-28`; empty when
     `unit_folders.py root` fails, and `under` drops an empty root);
   - per row, the folder recorded with it: a Claude transcript line's `cwd` (`scripts/dashboard_limit.py:594`), a
     Codex session's `session_meta` `cwd` (`:1094-1095`). `day` and `codex_day` already carry `(row, cwd, file)`.
   The rows of a project are `own(day, name)`'s, unchanged (longest root wins, `:1255-1257`); a sibling `own_where`
   returns `(row, cwd)` for the same rows. Key of a row, in this order, by path strings only (`under`, `:439-442`; no
   disk read, so a removed worktree or closing copy keeps its name):
   - under `closingCopies`: the first path segment after it (a closing copy is `<closingCopies>/<unit>`,
     `scripts/unit_folders.py:31-32`), so the copy counts under its unit;
   - under `workspaces`: the first path segment after it, with one trailing `-plan` removed (a plan worktree is
     `<unit>-plan`, `scripts/seat.sh:85`); `Fast-lane` and `Research-lane` keep their own names;
   - under `path`: `:main`;
   - anything else (a `cwd` equal to a root itself, or none): `:other`.
   A nested folder takes its first segment (`<workspaces>/u/subdir` is `u`). A unit's worktree, its plan worktree and
   its closing copy share one key, as `unit_folders.belongs` treats them as one unit. The folder roots come before
   `path`, so a main checkout that holds the worktree folder still keys a worktree by its unit.
2. `hooks/units-sources.ts`: `parseSnapshot` reads `limit.today[<project>]` into `snap.day = {total, byFolder,
   complete}` (absent when the snapshot has none).
3. `todayUsd` (:250) returns `snap.day.total` when present, else today's sum with a `units only` mark. New
   `todaySplit(s)`: merged units (a folder named in `finishedBuilds` or `mergedSincePush`), units in flight (a row's
   unit, or `<unit>-plan`), main (`:main`), standing panes and lanes (`NOT_UNITS`, case folded), not attributed
   (`:other`, unknown names, and the total minus the named parts, so the parts always sum to the total).
4. The header (:257) keeps `today <total>`, prefixed `at least` when `complete` is false (as `dashboard/app.js:1696`
   does); one line under it lists the non-zero parts in that order. `summaryLine` (:306) shows the same total.
5. `docs/dashboard.md:181-184` and `:200-203` ("Units mod", "What it reads"): today's total is the dashboard's Cost
   today for the project, since local midnight, split five ways; a pane in main counts under main (L5).

Produces: `limit.today[<project>].byFolder` in `data.js` (an added key), `snap.day`, `todaySplit`. Consumes:
`NOT_UNITS` (C2), `build`'s `day_projects` roots (`scripts/dashboard.sh:957`, unchanged), the rows' recorded `cwd`,
`under`. Consumers of a changed contract: `dashboard/app.js:1674-1696` reads
`limit.today` by named keys (the added key is ignored); `paneModel` and `summaryLine` (the two `todayUsd` callers,
`rg -n todayUsd hooks`); the existing `units-sources.test.tsx` cases at :112-131 run on snapshots with no `limit`, so
they keep their old sums.

Tests:
- New `scripts/__tests__/dashboard-today-split.test.sh` (transcripts built at noon today as
  `dashboard-billing.test.sh:113-127` does; the CLI form of `:67`, `python3 -B dashboard_limit.py build ...`, with the
  real eighth argument `{"p":["$T/r/main","$T/r/ws","$T/r/scratch/closing-copy"]}`, the shape `dashboard.sh:957`
  passes). No fixture folder is created on disk: `cwd` values are strings. One Claude and one Codex request today in
  `$T/r/main`, `$T/r/ws/u`, `$T/r/ws/u/subdir`, `$T/r/ws/u-plan`, `$T/r/scratch/closing-copy/u`,
  `$T/r/scratch/closing-copy/merged-u` (no `ws/merged-u`: the unit was removed) and `$T/r/ws/Fast-lane`, plus one
  request dated yesterday in `$T/r/ws/u`.
  - "byFolder sums to the day's total and leaves yesterday out"
  - "a unit's Codex review in its closing copy counts under the unit" (settles the issue's Codex question for the day
    split)
  - "a nested folder, a plan worktree and a removed unit's closing copy count under their unit by path alone" (keys
    exactly `u`, `merged-u`, `Fast-lane`, `:main`; `u` holds the five folders' spend)
- `hooks/units-sources.test.tsx` near :112-131: "today's total equals the dashboard's and splits by folder" (a
  snapshot with `limit.today.p = {spentUsd 30, complete true, byFolder {merged-unit 10, live-unit 5, :main 8, Fast-lane
  4, :other 3}}` and a `finishedBuilds` cost of 99 for merged-unit: total 30, parts 10/5/8/4/3, their sum 30); "a
  partial day reads at least"; "with no dashboard day the total is the units' own sum, marked units only".

Break: hooks/units-sources.test.tsx -- "today's total equals the dashboard's and splits by folder" -- hooks/units-sources.ts:250 return the old sum when `snap.day` is present
Break: scripts/__tests__/dashboard-today-split.test.sh -- "byFolder sums to the day's total and leaves yesterday out" -- scripts/dashboard_limit.py:<C3 item 1> group every row, not only `own(day, name)`'s

### C4 -- #422: a retry on the same tree reruns only what failed (~150 lines, 6 files)

1. `scripts/run-shell-tests.sh:2` usage and header: `--skip-passed`.
2. Flag parse beside `--own-lane` (:69-70). A partial-scope run is one whose environment holds any variable named
   `*_TEST_CASE`, set even to empty (the selectors the plugin's tests read: `BASH_GUARDRAILS_TEST_CASE`,
   `INSTALL_LIB_TEST_CASE`, `PROFILE_REVOKE_TEST_CASE`, `rg -n '_TEST_CASE' hooks/__tests__ scripts/__tests__`,
   2026-10-27; the same pattern `scripts/peer-offload.sh:82` forwards to the peer). It is read with `compgen -e` before
   any run. Such a run writes no ledger row and reads none; with `--skip-passed` it prints `run-shell-tests: a test-case
   selector is set (<name>); --skip-passed reuses and records nothing` and runs every file. No other partial scope
   exists: `--changed`, `--own-lane` and named files each choose whole files.
3. After :67, the host's work tree hash (host :56-64): `TREE` = `git write-tree` of a temp index holding HEAD plus
   every uncommitted and untracked file (`GIT_INDEX_FILE` copy, `git add -A`), so uncommitted work counts; `-` when
   it cannot be computed.
4. `last_pass <file>` (host `last_whole_row` :93-98): the ledger's last row for that file; a row that is not 4 fields
   or whose first field is not an ISO time clears every earlier pass (a cut or glued line brings back nothing).
5. After the offload split (:116-132), before the selection pass (:173), with `--skip-passed` and not a partial-scope
   run only. It reads `TESTS` as the split left it: the Mac-only files when the peer took the rest (:130), every file
   when nothing was handed off (3 or 4). A file handed to the peer is decided before this step and is never skipped,
   whatever its ledger says (Decision 4); `OFFARGS` (:121) never carries `--skip-passed`. A local file whose last row
   is `ok` at exactly `TREE` is not run; it prints the runner's own result line with a `0s` seconds field,
   `printf -- '-- ok   %-58s %ss (passed at this tree in an earlier run)\n' <file> 0`, so every reader of `-- ok`
   lines (`hooks/units-sources.ts:6` requires `<n>s`) counts it as a finished file. It counts as passed
   (`PASS=$SAMEPASS` at :218). No file left: the summary line and exit 0. `TREE` = `-` skips nothing.
6. `run_one` after :169, not in a partial-scope run: append `<ISO time>\t<file>\t<ok|FAIL>\t<TREE>` to
   `$(git rev-parse --absolute-git-dir)/commandeck-test-runs.tsv`, one `printf` per row.
7. `docs/tests.md` after :18 and `README.md:331-332`, `:338-346`: the flag, "same tree only", "files run on the PC
   are never skipped", and "a run with a test-case selector set records and reuses nothing".

Produces: the ledger and the flag. Consumes: the offload split's `TESTS` (:130). Consumers of a changed contract (the
runner's output): `scripts/post-fix-checks.sh:23`, `scripts/builder-codex-pass.sh:1356-1357`, `:1917`,
`scripts/merge-unit-local.sh:708`, `scripts/wait-test-run.sh:10`, `scripts/dashboard.sh:966-1011`,
`scripts/dashboard_limit.py:619`, `:655` (the `N passed, M failed, K parked` summary is unchanged), the units parser
`FILE` (`hooks/units-sources.ts:6`, which needs the seconds field the reused line keeps). No caller passes the new
flag, so every default run is unchanged.

Tests (`scripts/__tests__/run-shell-tests.test.sh`, a new three-file fixture repo after :199, every call under
`timeout 30`; fixture file `a.test.sh` reads `A_TEST_CASE` as the real selectors do):
- "--skip-passed reruns the failed and the missing file and skips the green one" (a run with b red, then c's row
  removed: the retry runs b and c, prints a as passed at this tree with `0s`, and the summary counts all three)
- "--skip-passed skips nothing after any tree change" (an untracked file added: all three run)
- "a cut or glued ledger line brings back no older pass"
- "without --skip-passed every file runs" (the default is unchanged)
- "a selected-case run neither records nor reuses a pass" (at one tree: `A_TEST_CASE=x` run of a.test.sh adds no
  ledger row; then a.test.sh whole with `--skip-passed` runs it; then, with a's `ok` row at this tree,
  `A_TEST_CASE=x ... --skip-passed` runs it too)

`scripts/__tests__/peer-offload.test.sh`, last (the fake PC):
- "a file run here while the PC was down goes to the PC once it is back, under --skip-passed" (`$T/down`: where.test.sh
  runs here and gets an `ok` row; `$T/down` removed; the same tree with `--skip-passed`: `there where` 1, `here where`
  0, no `passed at this tree` line)

`hooks/units-sources.test.tsx` beside :12:
- "a result reused at the same tree counts as a finished file" (`parseMergeLog` of
  `-- ok   a.test.sh 0s (passed at this tree in an earlier run)\n`: done 1, failed 0)

Break: scripts/__tests__/run-shell-tests.test.sh -- "--skip-passed skips nothing after any tree change" -- scripts/run-shell-tests.sh:<C4 item 5> skip on a row's `ok` without comparing its tree
Break: scripts/__tests__/run-shell-tests.test.sh -- "a cut or glued ledger line brings back no older pass" -- scripts/run-shell-tests.sh:<C4 item 4> drop the field-count test
Break: scripts/__tests__/run-shell-tests.test.sh -- "a selected-case run neither records nor reuses a pass" -- scripts/run-shell-tests.sh:<C4 item 2> drop the partial-scope test
Break: scripts/__tests__/peer-offload.test.sh -- "a file run here while the PC was down goes to the PC once it is back, under --skip-passed" -- scripts/run-shell-tests.sh:<C4 item 5> move the skip before the offload split

### C5 -- #423: a run survives a dropped session and is fetched once by its id (~175 lines, 4 files)

1. Apply the draft diff (`git -C <draft worktree> diff`, 47 lines): `pr_fetch`, the detached run with its output and
   status in `$S`, the `offload: run id` line, the trap that keeps a started run, the two-day sweep, and its fetch case.
2. The draft's red, "a Mac linked worktree with chain host pc: ... exit passed back" (expected `0 1 1 0 1 1`, got
   `0 0 1 0 1 1`). The second value counts the `offload: started on pc tree` line in the caller's output. The draft
   relays `$S/out` with a background `tail -f` started on the empty file, waits for `rc`, sleeps 0.5 s and kills it.
   GNU `tail -f` re-reads a file once a second when it cannot use inotify. The run ends in under 0.2 s, so the relay is
   killed before its first read, and every line the command wrote (the `started` line among them) is lost. The fix is
   in the ported code: the three lines become one foreground `tail -n +1 -s 0.1 --pid=<the wrapper's pid> -f
   "$S/out"`, which ends after the wrapper exits and only after it has printed the rest of the file. This also removes
   the 0.5 s guess. The fix was verified in a scratch copy: 17 passed, twice (A6).
3. Keepalive on the fetch: `pr_fetch`'s ssh gets `-o ServerAliveInterval=15 -o ServerAliveCountMax=4`, as the run's has
   (:89) and as host `chain-run.sh:276` does for every peer ssh.
4. A bounded fetch, ported from host `ee5efa7e:.claude/scripts/chain-run.sh:216-224` (`cc_stamp`, `cc_alive`): a pid
   alone is never trusted, it can be reused. The detached wrapper writes `$S/pid` as `<pid> <start>`, its own `$$` and
   `TZ=UTC LC_ALL=C ps -o lstart= -p $$` trimmed (`pr_stamp`, the host's `cc_stamp`). The fetch body loops: `rc`
   present ends the wait; else the run is alive only while `pr_stamp <pid>` equals the stored start; else it checks
   `rc` once more (the wrapper may have written it in between) and, still none, prints `offload: run <id> ended without
   a status` and exits 3, which `pr_fetch` returns as 1. A dead pid, a reused pid of another live process and a
   missing or empty `pid` file all read as not alive. Today's `until [ -e rc ]` would wait forever after a peer reboot
   or a pid reuse; the keepalive (item 3) cannot see either, since the session stays healthy.
5. The same validation as a live run: `pr_fetch` makes a fresh nonce, the fetch script prints the output, then
   `offload-exit: <nonce> <rc>`, `offload: exit <rc>` and `offload-done: <nonce>`, and `pr_fetch` reads the status with
   the live path's nonce parser (factored into one `pr_status`, used by both). A result counts only when both nonce
   lines arrived; it strips the nonce lines from what it prints. A stream without them (cut, or ending on a fake
   `offload: exit 0` the command printed) never returns 0: ssh exit 255 returns 4, any other returns 1, each with
   `offload: run <id>'s result did not arrive whole (ssh exit <n>); it stays on <peer>: fetch it again`.
6. Acknowledged delivery: the fetch body never deletes the run. Only after item 5 validated both nonce lines does
   `pr_fetch` send a second ssh call, `pr_ack <peer> <id>` (`rm -rf` the run folder, `git worktree prune`, same
   keepalive). So a fetch whose output is lost on the way leaves the run for the next fetch. An ack that fails changes
   no result: it prints `offload: run <id> stays on <peer> until the two-day sweep` and the next fetch returns the same
   status again. A live run that ends in its own session still deletes its folder there (the draft's last line): an
   ack there would add a second ssh call to every run, which the existing case "the run on the PC does not hand off
   again" (`calls` 1) refuses, and a live result lost after that line reads as failed (Accepted failure mode 3).
7. The drop message (:142) names the fetch with the id from the log: `bash scripts/peer-offload.sh --fetch <id>`.
   The script runs `pr_offload "$@"` when it is executed rather than sourced (a two-line guard at the end).
8. `README.md:338-346` (the offload section) and `docs/tests.md`: one line each, saying a dropped run keeps going and
   is collected once with `--fetch <id>`.

Produces: `offload: run id <id>`, `peer-offload.sh --fetch <id>` (exit 0/1 the run's, 1 also for a stream that did not
arrive whole, 2 unknown or already fetched and acknowledged, 4 unreachable), `pr_ack`, `$S/pid` as `<pid> <start>`.
Consumes: `$S` on the peer. Consumers of a changed contract: `scripts/run-shell-tests.sh:123-124` (the only caller;
its exit-code list is unchanged); `scripts/__tests__/peer-offload.test.sh`.

Tests (`scripts/__tests__/peer-offload.test.sh`, after the draft's fetch case; the fake ssh also logs its arguments
and gains two drop modes beside the draft's `cut`: `void` runs the whole body, discards its output and exits 255;
`upto` runs the whole body and passes its output through `sed '/^offload: exit 0$/q'`, exit 0):
- the draft's "a run whose session dropped is fetched by id with its exit status" (kept as written)
- "the files run on the PC ... exit passed back" (the existing case, green again with no edit)
- "a fetched run's status is the nonce line, never a line the command printed" (a test file that prints `offload:
  exit 0` and exits 1: fetch returns 1)
- "a fetch stream cut after a fake success line, before the nonce footer, fails closed and keeps the run" (the same
  test file; the run's session dropped with `cut`; fetch 1 under `upto` ends on the command's own `offload: exit 0`
  with no nonce line; fetch 2 whole; fetch 3. Values: fetch 1's exit, its count of `did not arrive whole`, fetch 2's
  exit, fetch 3's exit; expected `1 1 1 2`. With nonce validation removed, fetch 1 returns 0)
- "an interrupted fetch keeps the run: the next fetch still returns its status" (red.test.sh; fetch 1 under `void`:
  4; fetch 2: 1 with one `offload: exit` line; fetch 3: 2)
- "a fetch of a run whose wrapper died with no status returns 1, ended without a status" (a run folder with `started`
  and `pid` holding a finished process's pid and stamp; the fetch under `timeout 20`)
- "a fetch of a run whose pid now names another live process returns 1, ended without a status" (`pid` holds a live
  `sleep 60`'s pid with another start text; the fetch under `timeout 20`: 1, not 124)
- "every ssh to the peer carries the keepalive" (the run's, the fetch's and the ack's calls all hold
  `ServerAliveInterval=15`)
- "a dropped session's message names the fetch command and its id"

Break: scripts/__tests__/peer-offload.test.sh -- "a fetch stream cut after a fake success line, before the nonce footer, fails closed and keeps the run" -- scripts/peer-offload.sh:<C5 item 5> remove nonce validation from pr_fetch: read the last `offload: exit` line, the draft's `sed -n 's/^offload: exit \([0-9][0-9]*\)$/\1/p' | tail -1`
Break: scripts/__tests__/peer-offload.test.sh -- "an interrupted fetch keeps the run: the next fetch still returns its status" -- scripts/peer-offload.sh:<C5 item 6> delete the run inside the fetch body, as the draft did
Break: scripts/__tests__/peer-offload.test.sh -- "a fetch of a run whose pid now names another live process returns 1, ended without a status" -- scripts/peer-offload.sh:<C5 item 4> test the pid alone (`kill -0`), not its start
Break: scripts/__tests__/peer-offload.test.sh -- "a run whose session dropped is fetched by id with its exit status" -- scripts/peer-offload.sh:<trap> remove the started test, so the trap deletes a started run

### C6 -- #425: a passing run is admitted by the tree it tested (~25 lines, 1 file)

No code: the plugin never compares the live HEAD with a certified commit (A1). The tests pin both halves of the
acceptance in `scripts/__tests__/peer-offload.test.sh`, after C5's cases:
- "a commit that lands in the worktree mid-run leaves a passing run passing" (a fake-ssh mode `commit` commits a docs
  file in `$T/wt` before the run starts on the peer: RC 0, `offload: exit 0`)
- "a peer tree that differs from the tree sent is refused" (a fake-ssh mode `tree` replaces the expected tree hash in
  the script: RC 2, `is not the tree sent`, nothing ran)

Produces and Consumes: nothing. Consumers: none.

Break: scripts/__tests__/peer-offload.test.sh -- "a peer tree that differs from the tree sent is refused" -- scripts/peer-offload.sh:108 remove the tree comparison

### B1 -- the host unit, before C7

Catches: a port built from a guess at host code that has not merged, or from an earlier round of it. No existing check
does: plan-check, the tests and the judges read the plugin's own tree, never whether the host's final code exists.

Run `git -C "$HOST" log --oneline -i --grep tooling-open-2026-10-27 main`.
- Empty: C7 and C9 are not built; #426, #427 and #428 get `Refs` and `partial -- waits for the host fix`. C8 still
  closes #419 (Decision 8).
- Not empty: read that unit's diff for host 3244, 3255, 3256 and 3258. Port its final code onto the landing points
  below. Where its design differs from a cut here, the host's wins, with one Plan change log line per difference.

### C7 -- #428 (waits for host merge): land refuses a main checkout that differs from the commit (~60 lines, 3 files)

Catches: a tracked edit in main's checkout, before or during land, that the landed commit does not hold. The existing
land checks read only the lane branch (:85) and the review verdict (:86-164), never main's checkout, and
`hooks/main-edit-guard.sh` blocks only Edit, Write and MultiEdit tool calls (its header, :1-4), not a shell redirect,
an editor or another pane's `git`.

1. `scripts/fast-lane.sh` after :85: `main_clean` refuses (exit 2, main untouched) when `git -C "$PP_MAIN" diff-index
   --quiet HEAD --` fails or `ls-files -u` prints, and it names the paths. That covers staged and unstaged changes to
   tracked files, on any path (Decision 7). Untracked files are allowed.
2. After the merge (:167), the same check again. A change there exits 2 with `main moved to <sha>, but its checkout
   differs from it: <paths>` and never prints `landed`. Main is not rolled back: a reset would throw away the edit.
3. Header :6-10 and `docs/worker-panes.md:13`: land refuses a main checkout with tracked changes.

Produces: two refusals. Consumes: `PP_MAIN`. Consumers: main's lane line (`hooks/agent-startup-context.sh:182`); the
CLI only.

Tests (`scripts/__tests__/fast-lane.test.sh` before :142; the fixture commits a tracked `base.txt` in `$PROJ`):
- "a staged or unstaged edit in main refuses land, main untouched"
- "an untracked file in main does not block land"
- "an edit made in main while the reviewer runs refuses land" (the reviewer stand-in appends to `base.txt`)
- "an edit made in main while land runs is refused, never landed" (a `python3` shim on PATH appends to `base.txt`, then
  runs the real one: exit 2, no `landed` line)

Break: scripts/__tests__/fast-lane.test.sh -- "a staged or unstaged edit in main refuses land, main untouched" -- scripts/fast-lane.sh:<C7 item 1> check the index only (`--cached`)
Break: scripts/__tests__/fast-lane.test.sh -- "an edit made in main while land runs is refused, never landed" -- scripts/fast-lane.sh:<C7 item 2> remove the check after the merge

### C8 -- #419 (waits for host merge): verified, no code (0 lines)

The issue's failing input (kill only the PID in `<log>.pid`, then `wait <log> --max 0` while the command lives) is the
existing case "a killed wrapper whose command lives on reads still running, never died"
(`scripts/__tests__/bgrun.test.sh:34`). `.pid` names the job's process group (`scripts/bgrun.sh:7-9`, `:28-36`). The
Builder runs `bash scripts/__tests__/bgrun.test.sh` and records it. If B1 finds a host case the plugin lacks (an
explicit "unknown outcome" message), port it and its test, at most 15 lines.

### C9 -- #426, #427 (waits for host merge): the plan budget and the cited-evidence check (~300 lines, 6 files)

Catches: an over-budget plan (a long goal, prose steps, an oversized section) and a citation to a missing file, a line
past a file's end, an undated or future observation, or a plan, before a Builder or judge launches. Today's plan-check
reads only the size line, the `Test:` and `Mockup:` lines and placeholder text (`scripts/plan-check.sh:75-84`), so each
of these reaches a judging round.

Both checks run on every plan except one named in `scripts/plan-format-exempt.txt` (Decision 9). There is no opt-in
marker: a plan cannot choose its own checks.
0. `scripts/plan-format-exempt.txt` (new): one plan file name per line, the plans that exist when this unit lands,
   from the command in L7 (35 names on 2026-10-27). The Builder writes it at C9 and runs the command again just
   before the closing pass, adding any plan started since and recording the list's new `sha256` in this unit's own
   new test. After the merge the list is fixed. plan-check exempts a plan when the basename of its path
   (seat.sh `:315`) or of its label (builder-launch.sh `:113`, stdin) is a line of that file; an exempt plan gets
   exactly today's checks. Authors cannot add to it: `scripts/__tests__/plan-check-budget.test.sh` carries
   `# covers: scripts/plan-format-exempt.txt` in its first five lines, so `--changed` runs it on any edit of the list,
   and its case "the exemption list is closed" compares the file's `sha256` with the value the Builder records in that
   test at C9.
1. #426, in `scripts/plan-check.sh` after :84, in this order:
   - Goal: exactly one `Goal: ` line of at most 200 characters, with no continuation line.
   - `## Steps`: every non-blank line is one item, `- new|modify|delete <path>: <what>`.
   - Prose: a non-blank line outside a fence and outside `## Why` that is not a heading, a list item, an indented
     continuation, a table row or a `Label: value` line is refused, naming its section and line.
   - Caps: each `##` section at most 6,000 bytes (the latest plan's sections: median 1,653 B, 90th percentile 5,241 B),
     and `## Why` at most 1,200.
   - Refusal text: `REFUSED: <plan> section <name> is <n> bytes, over its <cap>-byte cap` (or names the rule broken).
2. #427, new `scripts/plan-evidence.py` (run with `python3 -I`, with the plan text and its checkout root), called from
   plan-check.sh after #426's checks. Each `## Facts` item is `- <claim> -- <path>:<a>[-<b>][, ...] observed:
   YYYY-MM-DD`. It is refused when:
   - its path is not a file under the root;
   - a cited line is past the file's end, or `a > b`;
   - its date is missing, not a real date, or later than today;
   - its path is a plan (`.claude/plans/`).
   An `## Assumptions` item without `check:` is refused, and a plan with no Facts section is refused. If the script
   cannot run (no `python3`, an unreadable root), the result is `REFUSED: evidence check not run: <why>`, never a pass.
3. `scripts/seat.sh:432-436`: the plan-author spec text asks for a Goal line, Steps, Why, Facts and Assumptions
   within the budget; the plan-judge text (:440) adds "the budget and the cited evidence are checked".
4. The header of `scripts/plan-check.sh` (:1-14): one clause on each check. No doc describes plan-check (`rg -n
   plan-check docs README.md CONTRIBUTING.md templates skills` empty, 2026-10-27).

Produces: the refusals. Consumes: the plan text. Consumers of a changed contract: `scripts/builder-launch.sh:113-115`
(parses `size <files> <lines>`, unchanged) and `scripts/seat.sh:315`; neither changes. The in-flight plans those two
re-check are on the exemption list, so they get exactly today's checks.

Tests: new `scripts/__tests__/plan-check-budget.test.sh`:
- "a two-line goal is refused naming Goal"
- "a multi-paragraph step is refused naming Steps"
- "prose outside the why field is refused naming its section"
- "a section over its cap is refused with its size"
- "a plan inside the budget passes"
- "a new plan with no marker, a missing-file citation and over-budget prose is refused" (no `Plan format` line
  anywhere; the refusal names the first fault)
- "a listed plan gets only today's checks" (the same text under a name from the list: `size` line, exit 0)
- "the exemption list is closed" (its `sha256` equals the recorded value)

New `scripts/__tests__/plan-evidence.test.sh`:
- "a missing file is refused with the citation"
- "a line past the end of a file is refused with the citation"
- "an undated observation is refused"
- "a fact that cites a plan is refused"
- "a plan with no Facts section is refused"
- "a plan whose facts all resolve passes"
- "a check that could not run is reported not run, never a pass"

Break: scripts/__tests__/plan-check-budget.test.sh -- "a section over its cap is refused with its size" -- scripts/plan-check.sh:<C9 item 1> skip the cap
Break: scripts/__tests__/plan-evidence.test.sh -- "a line past the end of a file is refused with the citation" -- scripts/plan-evidence.py:<line bound> drop the end-of-file test
Break: scripts/__tests__/plan-evidence.test.sh -- "a check that could not run is reported not run, never a pass" -- scripts/plan-check.sh:<C9 item 2> treat a failed start as a pass
Break: scripts/__tests__/plan-check-budget.test.sh -- "a new plan with no marker, a missing-file citation and over-budget prose is refused" -- scripts/plan-check.sh:<C9 item 0> exempt every plan with no `- Plan format: 2` line, as the first version did

### C10 -- release (~3 lines, 2 files)

`.claude-plugin/plugin.json`: the next free version at merge time (`bash ci/version-check.sh` decides; new behaviour,
so a minor: 0.55.0 if nothing lands first, since main carries 0.54.0). Also the `README.md:4` version badge, which
`scripts/__tests__/plugin.test.sh` "the README's badge shows the manifest's version" checks; that is not release text.
No CHANGELOG entry and no README release text: release notes wait until every ordered plugin unit has merged.

## Data design

- `<git dir>/commandeck-test-runs.tsv` (new, C4): rows `<ISO time>\t<file>\t<ok|FAIL>\t<tree>`.
  - Writer: `run_one`, one `printf` per row after each local file, never in a partial-scope run (a `*_TEST_CASE`
    variable set). Appends under 4 KB are atomic, so parallel files cannot interleave.
  - Reader: `--skip-passed` only, after the offload split and never in a partial-scope run.
  - Reset: none. It goes with a linked worktree's git dir (L4).
  - Retry: the retry is the feature. A lost or cut row only makes a file run again.
- The peer's `~/.cache/commandeck-offload/run.<id>/` (changed, C5): `started`, `out`, `rc`, `pid`, `w/`.
  - Writer: the detached wrapper on the peer.
  - Readers: the live relay and `--fetch`.
  - `pid` holds `<pid> <start>`; the run is alive only while both match a live process (C5 item 4).
  - Reset: a completed live run deletes it in its own session; a fetch never deletes it, the acknowledging `pr_ack`
    call does, after the local side validated both nonce lines; the sweep deletes one older than two days; a refusal
    before the start deletes it (trap).
  - Retry: a fetch whose output did not arrive whole leaves the run, and the next fetch returns it. After a validated,
    acknowledged fetch the id is unknown (2), so a result is collected once. A fetch while the run still runs waits for
    `rc` or the wrapper's end.
- `scripts/plan-format-exempt.txt` (new, C9): the plan names exempt from the budget and evidence checks.
  - Writer: the Builder, at C9 and once before the closing pass; nothing after the merge.
  - Reader: `plan-check.sh`.
  - Guard: the `sha256` case in `plan-check-budget.test.sh`, run by `--changed` on any edit of the list.
- A lane's `.claude/settings.local.json` (changed, C1): no `Agent` in `permissions.deny`.
  - Writer: `worktree-setup.sh`, run by setup.
  - Retry: the same run; it is idempotent.
- `data.js` `limit.today[<project>].byFolder` (added key, C3).
  - Writer: the collector, every run, published with one rename as today.
  - Readers: `/units`; `dashboard/app.js` ignores it.
- C2, C6, C7 and C8 add or change no state.

## Guards changed (before -> after)

| guard | before | after |
|---|---|---|
| lane settings deny list | `Agent` denied in every worker but a plan worktree | also allowed in `Fast-lane` and `Research-lane`, by exact name (C1) |
| fetched peer result | none (new) | status only from a fresh nonce pair, else never 0; deleted only by an ack after validation; a wrapper whose pid and start no longer match reads 1 (C5) |
| same-tree skip | none (new) | only local files after the offload split, only at the exact tree, never in a partial-scope run (C4) |
| peer tree check | refused a tree that differs from the one sent | unchanged, now tested (C6) |
| Fast-lane land | no main-checkout check | refuses tracked changes before the merge, and reports a change after it as exit 2, never `landed` (C7) |
| plan-check | size, Test:, Mockup:, placeholders | for every plan not on the fixed exemption list, also the budget and the cited evidence (C9) |

## Prior art

- GNU coreutils `tail --pid -f` follows a file until a process ends.
- OpenSSH `ServerAliveInterval` and `ServerAliveCountMax` bound how long a dead session goes unseen.
- `nohup` keeps the detached run alive when its session drops.
- `git write-tree` over a temporary `GIT_INDEX_FILE` hashes a working tree without touching the real index.
- The ports are by commit: host `ee5efa7e` and `86b6bc0f`.
- #427 names `skills/review-spec/scripts/check-evidence.py` (specification-first-agentic-development) as prior art. It
  is not on this machine (`find ~/repos ~/.claude -name check-evidence.py` empty, 2026-10-27), so C9's script is
  written from the issue's rules. No outside library is added.

## Decisions

1. **#424's allowance names the two lanes, not `pp_standing_wt`.** That list holds the relay too, and the issue's test
   fails on any widening, a new standing seat included. Test: "the helper allowance is the two lanes only".
2. **#424 changes the deny list, not the model guard, as the host did.** The guard already runs a named Sonnet or Haiku
   as named in any pane but a Builder, plan-author or fix-round one; the lane was blocked only because `Agent` was
   denied. Test: "a lane's named Sonnet or Haiku helper runs as named".
3. **#421: `/units` shows the dashboard's own day figure and splits it by folder.** Computing it again in TypeScript
   would make two numbers that can drift. Test: "today's total equals the dashboard's and splits by folder".
4. **#422 records local runs only; offloaded files always rerun.** The peer runs in a throwaway worktree and returns
   only an exit code. The host built its skip on per-file rows returned from its peer (host Decision 12), and this
   plugin has no such return. So a skip never happens without proof, and the skip is decided after the offload split,
   on the local files only. Test: "--skip-passed reruns the failed and the missing file and skips the green one"
   (fixture with no peer), "a file run here while the PC was down goes to the PC once it is back, under --skip-passed".
5. **#423: the relay ends with the wrapper (`tail --pid`), not after a fixed sleep.** The 0.5 s guess loses output on
   any short run (the red) and can lose output on a long one. Test: the existing "... exit passed back" case.
6. **#423: a fetch validates with its own fresh nonce.** The command's output was written before the fetch existed,
   so it cannot hold that nonce. A nonce kept on the peer could be read by the command. Test: "a fetch stream cut after
   a fake success line, before the nonce footer, fails closed and keeps the run".
7. **#428: land refuses any tracked change in main, on any path.** Main's checkout is the reviewed commit's landing
   place, `main-edit-guard.sh` already keeps edits out of it, and an allow rule per path would need its own review.
   Untracked files are not in the commit and stay allowed. Test: "a staged or unstaged edit in main refuses land, main
   untouched", "an untracked file in main does not block land".
8. **#419 closes with no code.** The last unit's fix round 4 made `.pid` a process group, and its test holds the
   issue's exact failing input. B1 only checks whether the host adds a case. Test: `scripts/__tests__/bgrun.test.sh`
   "a killed wrapper whose command lives on reads still running, never died".
9. **#426/#427 apply to every plan but a fixed exemption list, with no opt-in marker.** The owner decided this evening
   that the format is mandatory for new plans and in-flight plans are exempt. No existing plan fits (L7), and
   builder-launch and seat.sh rerun plan-check on in-flight plans, so those are listed by name when this unit lands; an
   author cannot select the exemption. Test: "a new plan with no marker, a missing-file citation and over-budget prose
   is refused", "a listed plan gets only today's checks", "the exemption list is closed".
10. **#425 adds tests, not code.** The plugin already admits by the tested tree (A1). Test: "a commit that lands in the
    worktree mid-run leaves a passing run passing", "a peer tree that differs from the tree sent is refused".
11. **A Break line for every new refusal, allowance and conditional write; none for prose.** That is the spec's rule.
    Test: each `Break:` line's named check.
12. **#422: a partial-scope run neither records nor reuses a pass.** A pass of one selected case says nothing about
    the whole file, and the ledger records no scope. Test: "a selected-case run neither records nor reuses a pass".
13. **#423: a fetched result is deleted on the peer only by a second, acknowledging call after validation.** A result
    deleted in the same call that sends it is lost whenever that output is. Test: "an interrupted fetch keeps the run:
    the next fetch still returns its status".
14. **#423: a run is alive only while its pid has its stored start time (the host's `cc_alive`).** A pid alone can be
    reused after a reboot. Test: "a fetch of a run whose pid now names another live process returns 1, ended without a
    status".
15. **#422: a reused result keeps the runner's line grammar, with `0s`.** Its readers count `-- ok` lines by their
    seconds field. Test: "a result reused at the same tree counts as a finished file".
16. **#421: the day split is keyed by path strings from the collector's three roots.** The collector receives no
    worktree list, and a removed unit has no folder left to look up. Test: "a nested folder, a plan worktree and a
    removed unit's closing copy count under their unit by path alone".

## Accepted failure modes

1. A new plan given the file name of a listed plan is exempt. Every listed name but two ends in a date on or before
   2026-10-27 (`ls .claude/plans`, 2026-10-27), and a unit name is its plan's name. Test: none, reusing a landed
   unit's name is a naming fault outside plan-check; the judge sees the old date.
2. A run fetched while the peer reboots reads "ended without a status" (exit 1), and the run is not repeated. Test: "a
   fetch of a run whose wrapper died with no status returns 1, ended without a status".
3. A live run's output lost after its last line: the peer has deleted the run in that session (C5 item 6), so the
   caller reads exit 1 and a fetch says unknown. Fails closed, never a false pass. Test: the existing "every ordering
   found so far: an opened session ends ... with ... lost: it fails, nothing runs here, the PC may still be running
   it".
4. After a change appears in main during C7's merge, main has moved and is not rolled back; land exits 2 and names the
   paths. Test: "an edit made in main while land runs is refused, never landed".
5. Ad-hoc panes in main count under main in today's split (L5). Test: none, the dashboard's source holds no pane id.

## Assumptions (each settled, or a Builder check with the action per outcome)

- A1 [settled] No plugin code compares a live HEAD with a certified commit after a peer run. Commands and results,
  2026-10-27:
  - `rg -n -i "certif|origin HEAD|live HEAD|tested tree|admit" scripts ci hooks skills templates`: no peer admission.
  - `rg -n "pr_offload" scripts hooks`: only `scripts/run-shell-tests.sh:123-124` calls it.
  - The peer refuses a tree other than the one sent (`scripts/peer-offload.sh:108`), and merge reuse compares trees
    (`scripts/merge-unit-local.sh:604-607`, read 2026-10-27).
- A2 [settled] #419 is fixed at `f626ece`. `bash scripts/__tests__/bgrun.test.sh`: 16 passed, 5.8 s (helper run,
  2026-10-27).
- A3 [settled] The lanes reach BUILDING because `scripts/dashboard.sh:335` gives them the stages `fast-lane` and
  `research-lane`, and `hooks/units-sources.ts:102` filters only `chief-of-staff`, `research` and `walkthroughs`.
- A4 [settled] `rg -n "'research'|walkthroughs" scripts hooks dashboard --glob '!**/__tests__/**'` hits only
  `hooks/units-sources.ts:102` (2026-10-27).
- A5 [settled] Unit cost records already hold Codex passes: `unit_costs` matches Codex rows to a unit by folder,
  closing copy and plan worktree included (`scripts/dashboard_limit.py:1362-1369`). C3's Codex case pins it for the
  day split.
- A6 [settled] The draft's red is the relay race in C5 item 2. Reproduced 3 of 3 on the draft; the base passes 16 of
  16; with the fix, 17 of 17 twice (14.8 s and 16.1 s) in a scratch copy (helper run, 2026-10-27).
- A7 [settled] The peer is Linux: `hs_cage` refuses with no `systemd-run` (`scripts/host-services.sh:236-238`).
- A8 [settled] `data.js` carries `limit` at its top level (`scripts/dashboard.sh:1196` `part limit limit`), and
  `limit.today[<project>]` holds `spentUsd` and `complete` (`scripts/dashboard_limit.py:1258-1260`).
- A9 [Builder check B1, before C7] Has the host unit merged? See B1 for the action on each outcome.

## What can go wrong

| case | input or starting state | expected result | test name |
|---|---|---|---|
| a selected case, then the whole file | `A_TEST_CASE=x` run of a.test.sh, then a.test.sh whole with `--skip-passed`, same tree | no ledger row from the first; the second runs the file | a selected-case run neither records nor reuses a pass |
| the PC down, then back | where.test.sh run here while `$T/down`, `ok` row at T; PC back; `--skip-passed` at T | the file runs on the PC, none here | a file run here while the PC was down goes to the PC once it is back, under --skip-passed |
| a fetch whose output is lost | fake ssh runs the fetch body, discards its output, exits 255; fetch again | first returns 4, run kept; second returns the status; third 2 | an interrupted fetch keeps the run: the next fetch still returns its status |
| a fetch stream cut after a fake success line | the command printed `offload: exit 0`, exited 1; stream ends there, ssh exit 0 | fetch returns 1, run kept; next fetch 1 | a fetch stream cut after a fake success line, before the nonce footer, fails closed and keeps the run |
| a reused pid | `started`, no `rc`, `pid` names a live `sleep` with another start | fetch ends at once: 1, ended without a status | a fetch of a run whose pid now names another live process returns 1, ended without a status |

Moved out of the table by its five-row cap, tests unchanged among the acceptance tests:
- a retry after one failure (C4, "--skip-passed reruns the failed and the missing file and skips the green one")
- the session drops mid-run (C5, "a run whose session dropped is fetched by id with its exit status")
- a commit lands during a passing run (C6, "a commit that lands in the worktree mid-run leaves a passing run passing")
- a unit merged today with yesterday's spend (C3, "today's total equals the dashboard's and splits by folder")
- the lanes in the snapshot (C2, "the standing lanes are never units: BUILDING 1, neither lane listed")
- spend in a nested folder and in a removed unit's closing copy (C3, "a nested folder, a plan worktree and a removed
  unit's closing copy count under their unit by path alone")
- a new plan with no marker (C9, "a new plan with no marker, a missing-file citation and over-budget prose is
  refused")
- a fetched run whose output prints a fake exit line (C5, "a fetched run's status is the nonce line, never a line the
  command printed")
- a peer that rebooted before the fetch (C5, "a fetch of a run whose wrapper died with no status returns 1, ended
  without a status")
- a cut or glued ledger line (C4, "a cut or glued ledger line brings back no older pass")
- an untracked file after a pass (C4, "--skip-passed skips nothing after any tree change")
- an edit in main while land runs (C7, "an edit made in main while land runs is refused, never landed")
- a look-alike lane folder (C1, "the helper allowance is the two lanes only")

## Claims to falsify

- With no `--skip-passed`, `run-shell-tests.sh` runs exactly the files it ran before this unit.
- `--skip-passed` never skips a file whose last row is not `ok` at the exact current tree.
- A file run on the peer is never skipped by `--skip-passed`.
- The summary line of a `--skip-passed` run counts every file in the inventory.
- `peer-offload.test.sh` "a Mac linked worktree with chain host pc: ... exit passed back" passes with no test edit.
- A run with any `*_TEST_CASE` variable in its environment writes no ledger row and reports no file as passed at this tree.
- `--skip-passed` is applied only to the files left to run locally after the offload split.
- A reused file's line matches `hooks/units-sources.ts:6` `FILE` and counts as one finished file.
- A fetch returns 0 only when its own nonce lines say 0, and a stream without both nonce lines never returns 0.
- No fetch body deletes a run folder; only `pr_ack`, sent after validation, does.
- A second fetch of the same id after a validated, acknowledged fetch exits 2.
- A fetch stops waiting when the stored pid is alive but its start time differs from the stored one.
- `byFolder` keys come from path strings alone: no `os.path.exists` or `isdir` call decides a key.
- Every ssh call to the peer, run or fetch, carries `ServerAliveInterval=15`.
- No plugin code admits or refuses a peer result by comparing the live HEAD with a certified commit.
- Only `Fast-lane` and `Research-lane` worktree settings lose the `Agent` deny; every other worker's keeps it.
- `hooks/agent-model-guard.sh` is not changed by this unit.
- `/units` never lists `Fast-lane`, `Research-lane` or `Chief-of-Staff` under BUILDING.
- When `data.js` holds the project's day, the `/units` total equals `limit.today[<project>].spentUsd`.
- The split's parts always sum to the total.
- `dashboard/app.js` is not changed by this unit.
- `fast-lane.sh land` never prints `landed` while main's checkout differs from the landed commit in a tracked file.
- A plan named in `scripts/plan-format-exempt.txt` gets exactly the plan-check result it gets before this unit; every
  other plan, with or without any marker line, gets the budget and evidence checks.
- `plan-check.sh`'s pass output is still `size <files> <lines>`.
- `scripts/bgrun.sh` is not changed by this unit unless B1 finds a host case.

## Not ordered (found, not planned)

- `scripts/merge-unit-local.sh:604-605` refuses a closing-pass suite whose commit is not the unit's tip, before the
  tree test. An empty commit on top (same tree) would rerun the check. That is a guard on whose proof it is, not #425's
  peer admission. Left as it is.
- `codex-ask.sh` runs uncounted by both totals (L6).
- The host's own units view has the same stale `NOT_UNITS` and no day split. Those are the host twins the issues name
  and belong to the host.

## Progress notes

- #419: built (no code; verified, Decision 8)
- #420: built
- #421: built
- #422: built
- #423: built
- #424: built
- #425: built (tests only, Decision 10)
- #426: partial -- waits for the host fix (B1)
- #427: partial -- waits for the host fix (B1)
- #428: partial -- waits for the host fix (B1)

If B1 finds the host unit merged and C7 or C9 is built, that issue's line becomes `#N: built` and its `Refs #N`
becomes `Closes #N`.

## Version and CHANGELOG

Version: the next free minor at merge time (C10). No CHANGELOG entry and no README release text in this unit.

## Merge commit message

```
feat(plugin-open-c-2026-10-27): same-tree test retries, fetchable peer runs, lane helpers, a units view that matches the dashboard

Closes #419
Closes #420
Closes #421
Closes #422
Closes #423
Closes #424
Closes #425
Refs #426
Refs #427
Refs #428
```

A cut built after B1 changes its `Refs #N` to `Closes #N`. A cut left partial for any other reason changes its
`Closes #N` to `Refs #N` and its progress note to `#N: partial -- <what is left>`.

## Done when

- Every acceptance test named above is green, and the draft's red case is green with no test edit.
- `bash scripts/run-shell-tests.sh --changed main` is green.
- `claude plugin validate .` and `claude plugin test .` pass.
- `bash ci/leak-test.sh` and `bash ci/version-check.sh` pass.
- Each `Break:` line of a built cut has its `Mutation-verified:` row.
- B1's command and output, and C8's bgrun run, are in the evidence.
- A closing (final) pass ends `VERDICT: GO` with no finding named.

## Plan change log

- 2026-10-27: first version.
- 2026-10-27 F1: C4 items 2 and 6 and Data design: a partial-scope run (any `*_TEST_CASE` set) neither writes nor
  reads the ledger; Decision 12; test "a selected-case run neither records nor reuses a pass" and its Break line.
- 2026-10-27 F2: C4 item 5 moved after the offload split (local files only); Decision 4; test "a file run here while
  the PC was down goes to the PC once it is back, under --skip-passed" and its Break line; Timed checks.
- 2026-10-27 F3: C3 item 1 defines the folder key from the collector's three roots and the rows' recorded `cwd`,
  nested folders and removed units by path alone; Decision 16; test "a nested folder, a plan worktree and a removed
  unit's closing copy count under their unit by path alone".
- 2026-10-27 F4: C5 item 6: the fetch body never deletes; `pr_ack` deletes after validation; Data design; Decision
  13; Accepted failure mode 3 (the live path); test "an interrupted fetch keeps the run: the next fetch still returns
  its status" and its Break line.
- 2026-10-27 F5: C5 item 4 ports `cc_stamp`/`cc_alive` (pid plus start time); Decision 14; test "a fetch of a run
  whose pid now names another live process returns 1, ended without a status" and its Break line.
- 2026-10-27 F6: C5 item 5 requires both nonce lines; test "a fetch stream cut after a fake success line, before the
  nonce footer, fails closed and keeps the run"; its Break line replaces the old nonce Break (the draft's parser).
- 2026-10-27 F7: C9 item 0, Decision 9, L7, Accepted failure mode 1: no marker; a fixed exemption list
  (`scripts/plan-format-exempt.txt`); tests "a new plan with no marker, a missing-file citation and over-budget prose
  is refused", "a listed plan gets only today's checks", "the exemption list is closed"; the marker test is gone.
- 2026-10-27 F8: C4 item 5: the reused line carries `0s`; Decision 15; test "a result reused at the same tree counts
  as a finished file".
- 2026-10-27 F9: `Catches:` lines at B1, C7 and C9.
- 2026-10-27 F10: Sources: host main's `617423b5` assessed; nothing ported (random `mktemp` run folders).
- 2026-10-27: size 24 files, 873 lines -> 25 files, 1030 lines (C3 ~235, C4 ~150, C5 ~175, C9 ~300).

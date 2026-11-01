# commandeck-fast-tests -- the whole shell suite on the PC in under 10 minutes

Owner's words: the owner, 2026-10-31: cut the full shell test suite (`bash scripts/run-shell-tests.sh`, about 241 files) to under 10 minutes wall time. Run it on the PC by default, with more jobs in parallel; remove the fixed startup cost of about 10 s per test; trim or split the slow tests that take 2 to 4 minutes. Never raise a time limit.
Owner's additions: Scope 6 of the spec, 2026-10-31: fix the two seat-run.test.sh failures as their own cut, red-first. The answers under Main answers. The push of main's unpushed commits waits for this unit's green PC runs.
Goal: On a Mac with a PC peer configured, a whole-suite run always runs on the PC, slowest first, load-aware jobs, under 10 minutes, or refuses; with no peer it runs locally as today.
Plan: .claude/plans/commandeck-fast-tests.md
Tier: Standard; LOCAL merge only; changed-file tests only during the build; no test-timeout raises of any kind.
Build order: C0, C1, C2, C4, C5, C6, C7; C4 is the Scope 6 cut, red-first; C7 (the measured runs) last. C3 is dropped (r2).
- Planned size: 13 files, 295 changed lines
New tests: commandeck-fast-tests 21 -- 10 new cases plus 11 existing checks moved into one new file, which the pass's counter reads as new
Version: 0.66.0 (a minor: new behaviour), unless `bash ci/version-check.sh` at merge time names another free number.
Closes: none
Timed checks: none affected -- no heavy fixture is added to a file with time-bound checks; the threshold file has none (rg 'sleep|timeout|date' on it, 2026-10-31).
Helpers: every subagent call names its model: Sonnet `general-purpose` for code reading, test triage and the split edits; Haiku `Explore` for search. The Builder brief carries this line.

## Why

The suite already fits in 10 minutes on the PC (runs B, C: 260 s at 8 jobs, 147 s at 16). The slow runs are the ones that never reach it: a whole run from the main checkout, or from a Mac whose chain host is not pc, or with the PC down, runs on the Mac. So on a Mac with a PC peer configured every whole run goes to the PC or refuses; a machine with no peer (an outside contributor's) keeps today's local run. The "10 s per test" startup cost does not exist on the PC (median file reaches its first check in 0.17 s); it is the Mac under load, and routing removes it. On the PC, 16 jobs are HUNG-free only with slowest-first ordering (run C); with the file list a hand-off sends today, the threshold file hung at its 120 s limit (run E). So a whole run hands the PC the bare command, which orders and saves its own seconds, and the threshold file is split by its measured cases. At 16 jobs the wall is bound by total work, not the longest file: a schedule over run C's seconds gives 137 s before and after any split, so merge-unit-local is not split.

## Prior art

- Standard: none governs a test runner's scheduling; the repo's own runner contract (docs/tests.md) governs.
- Library: GNU parallel and xargs -P schedule jobs, but the runner already has its own launch loop, caps and fence; nothing is replaced.
- Built here: the PC hand-off (peer-offload.sh) and the slowest-first list exist; this unit widens their reach.

## Data design

- PC seconds list: `$HOME/.commandeck/shell-test-seconds.tsv` on the PC, `<seconds>\t<basename>`. Written by the PC's whole-scope run (save_seconds, unchanged); read by the next PC whole-scope run. Today it never exists on the PC (checked 2026-10-31: no such file). Resets: never; a row for a file no longer listed drops at the next save (unchanged rule). Retry: a run that dies before save_seconds leaves the old list.
- Mac seconds list: no longer written by a whole run (it always hands off; OFFLOADED=1 skips the save, unchanged); read only by local runs.
- Job count: computed per run, not stored.
- No other state is added or changed.

## Main answers

- Q1 not approved: seat.sh's cap stays as it is, any two judge verdicts end a plan's judging. D9 and the seat.sh change are gone; C4 fixes seat-run in its setup.
- Q2 approved: the whole suite always runs on the PC, with no Mac fallback, whatever chain-host says; with the PC unreachable it refuses with a clear line and a non-zero exit.
- Q3 approved: the stray git line after each PC run goes (D7).
- Q2 narrowed by the owner, 2026-10-31 (r3): the PC-only rule is for a machine with a PC peer configured; on one with none the whole suite runs locally exactly as today, and CONTRIBUTING.md is unchanged.

- seat-run fix, the owner, 2026-10-31: fix it in the test setup, the last two scenarios with their own unit names; seat.sh stays unchanged (C4, D10 as written).
- Q4 yes, the owner, 2026-10-31: the dashboard-serve-answers wait is fixed here; a test edit that follows the intended change and removes or loosens no check may stand; deleting, folding or weakening still goes to the owner.
## Decisions already made

- D1 A peer is configured when `~/.config/devenv/peer` names a destination (pr_peer, peer-offload.sh:9). A whole-suite run is any run the runner gives `SCOPE=whole` (run-shell-tests.sh:214-216: no files named, with or without --own-lane or --skip-passed). Every such run from a Mac (`hs_os` Darwin), outside a test run and not on the PC, sets `PO_WHOLE=1` for the hand-off. In pr_offload, with `PO_WHOLE`: no peer returns 3 first, before the git folder checks (peer-offload.sh:122-124), so a no-peer machine never meets a git refusal; a peer passes the chain-host gate (:121) whatever `hs_chain_host` prints (absent, `mac`, `pc`) and the main-checkout gate (:125). Without `PO_WHOLE` both gates stay as today, so named-file and --changed runs, from main or a worktree, keep the chain-host rule and fallback. No peer: the same files run here; the two lines a no-peer chain-host-pc worktree prints today (peer-offload.sh:127, run-shell-tests.sh:241) are gone. The bare command to the PC drops --skip-passed, as today's hand-off does (only --own-lane travels, :234): files run on the PC are never skipped. Test: peer-offload.test.sh "a whole-suite run from the main checkout runs on the PC", "a whole-suite run with no chain-host file runs on the PC", "a whole-suite run with chain host mac runs on the PC", "a whole-suite run with no peer file runs here, as today"; run-shell-tests.test.sh "a --skip-passed run with no files is a whole run: it hands off with PO_WHOLE and without --skip-passed".
- D2 A whole-suite run whose hand-off returns 4 (a peer configured and unreachable; with `PO_WHOLE` set, no peer is 3, never 4) refuses: exit 2, one line naming the peer and the two ways on (wake the PC, or run named files or --changed), nothing runs, `# host: mac` files included. Test: run-shell-tests.test.sh "a whole-suite run whose PC cannot be reached refuses: exit 2, nothing runs here, one line says why".
- D3 A whole-suite run with no `# host: mac` file hands the PC the bare command, not the file list, so the PC run is whole-scope: it reads and saves its own seconds and starts slowest first. Same file set: both list `hooks/__tests__/*.test.sh scripts/__tests__/*.test.sh` at the same tree. Test: run-shell-tests.test.sh "a whole-suite run with no host: mac file hands the PC the bare command, so the PC reads and saves its own seconds".
- D4 Offloaded default jobs (COMMANDECK_OFFLOADED set): cores minus the integer part of the 1-minute load, at least max(1, cores/4), at most cores; an unreadable load cuts nothing; COMMANDECK_SHELL_TEST_JOBS still wins. The Mac and CI keep today's rule. Idle 16-core PC: 15 or 16. Relies on D3: 16 jobs were HUNG-free slowest first (run C) and not with a file list (run E). Test: run-shell-tests.test.sh "an offloaded run's default jobs are the cores less the load, at least a quarter of the cores".
- D5 One split, by measured cases: the threshold file keeps sections 1-4, 6-8, 11 (36.7 s of a whole-file run on the PC); sections 5, 9, 10 (19.8 s of it) go to a new -cap file, which copies `loop` (:186 stays). Checks move, never change. Test: the label diff under Verification, empty, and both files green on the PC.
- D6 builder-fresh-round's stub writes the session log at once with a future mtime (`touch -t 209901010000`) instead of 1 s late: the script only needs it newer than its stamp (builder-fresh-round.sh:175, :221-226). Test: builder-fresh-round.test.sh, all 33 checks green, file under 15 s on the PC.
- D7 peer-offload's PC script leaves the scratch worktree before deleting it, so no `Unable to read current working directory` follows the exit line. Test: peer-offload.test.sh "a finished run on the PC prints no git error after its exit line".
- D10 seat-run's dead-pane and detached scenarios each run on a unit of their own (`pd`, `pe`), set up as :9-12 sets up `pu`, so neither inherits `pu`'s two judge rounds. seat.sh is not edited, so the cap refuses exactly what it refused: a third round on one plan (seat-judge-rounds.test.sh, unchanged); each new unit is at its first round, below the cap. Test: seat-run.test.sh's two checks, red at 85d01a3 (run C log), green after C4.
- D8 No cap, `# timeout:` header or HUNG bound changes anywhere. Test: none, a diff rule; Verification greps the diff for `timeout` and `TIMEOUT`.

## Accepted failure modes

- Two whole runs on the PC at once: the second starts at cores/4 jobs (load near 16) and its caps stretch with load (bound(), unchanged). Not measured together. Test: none, a stated limit; the floor's arithmetic is in the D4 check.
- A Mac with a peer configured cannot run the whole suite while the PC is down (Q2): it refuses and runs nothing; named files, --changed and CI still run. Test: peer-offload.test.sh "a whole-suite run from the main checkout with the PC down refuses: exit 2, nothing runs here or there".

## Assumptions

- A1 The memory cage (16G, host-services.sh:238) holds 15-16 jobs: [uncertain]. Builder check after C1, before C7: one full hand-off at C1's new default (D4: 15-16 jobs on the idle PC; the line `run-shell-tests: <n> jobs` shows it); on any rc=137 or cage kill, set the floor rule's top to 12 jobs (run D, HUNG-free) and log it in the Plan change log.
- A2 The -cap file needs only the names the moved sections use: [uncertain]. The reader's list: gh stub :15-27, WS :28, tpass :29-37, verify :38, prompt :39, last :40, `loop` :186; LED :41, answer :42-45 and routed :46-51 were not checked against sections 5, 9, 10. Builder check before C2: `rg` each name the moved lines use against the kept lines; copy every definition found; if the -cap file then fails on the PC, report the missing name to main.
- A3 leak-test's red at 85d01a3 is fixed on main by b8f3d98: settled (`git log -1 main`, 2026-10-31). The Builder starts from main.

## Measurements

- Run A: PC, older tree f88e9613, 8 jobs, 305 s.
- Run B: PC hand-off from main's push gate, 85d01a3, 8 jobs, 260 s, 239 passed, 2 failed (leak-test, seat-run). Log: `~/.commandeck/scratch/pc-pushgate-1031.log` (:531).
- Invocation C-E: from this linked worktree (chain host pc), `COMMANDECK_FOREGROUND=1 COMMANDECK_SHELL_TEST_JOBS=<j> COMMANDECK_SHELL_TEST_SECONDS=<list> bash scripts/run-shell-tests.sh`; the list is run B's seconds copied to the PC (C, D), or a missing file (E: today's sorted file list). Each log's line 1 holds its invocation, its last line wall and peak load (5 s samples, `<log>.load`).
- Run C: 16 jobs, slowest first: 147 s, peak load 15.88, no HUNG, 238 passed, 3 failed (leak-test, seat-run, dashboard-serve-answers). Log: `~/.commandeck/scratch/commandeck-fast-tests-r2-runC.log`.
- Run D: 12 jobs, slowest first: 195 s, peak 17.66, no HUNG, 239 passed, 2 failed. Log: `~/.commandeck/scratch/commandeck-fast-tests-r2-runD.log`.
- Run E: 16 jobs, file list: 224 s, peak 22.37, threshold HUNG past 120 s. Log: `~/.commandeck/scratch/commandeck-fast-tests-r2-runE.log`.
- Run F: Mac main checkout, 4 jobs, load 10.9 on 8 cores: 234 passed, 7 failed, 3 HUNG. Log: `~/.commandeck/scratch/<main project>/shell-tests.log`.
- Cases: threshold alone on the PC 56-57 s; sections 1-3, 6-8, 11 27.5 s, section 4 9.2 s, sections 5, 9, 10 19.8 s (two whole-file runs, split by check-line time stamps; no section run alone). Log: `~/.commandeck/scratch/commandeck-fast-tests-r2-cases.log`.
- Fixture: merge-unit-local-setup.sh, with its copy of the repository (566 files, 10 MB, :7), 0.04-0.14 s. Log: `~/.commandeck/scratch/commandeck-fast-tests-r2-fixture.log`.
- Schedule: longest-first over run C's per-file seconds at 16 jobs: 137 s (observed 147 s); sum 2180 s; with the threshold split or the merge-unit-local split, 137 s.
- Setup: each file bare on the PC, time to first ok/FAIL line: median 0.17 s, p90 2.2 s. Hand-off fixed cost: 2.9 s for one 0 s file.

## Slowest 30 (PC run B seconds; where the time goes)

| # | file | s | where |
|---|---|---|---|
| 1 | merge-unit-local | 87 | ~81 real merge/pass script runs; no sleeps |
| 2 | answer-worker | 70 | the script's own sleep-2 polls, ack waits |
| 3 | seat | 65 | 13 real seat.sh launches |
| 4 | builder-codex-pass-threshold | 64 | ~45 real 3-reviewer passes, 20 verifies |
| 5 | builder-codex-pass | 52 | a 31 s probe stub, 4 s ticks, 12 passes |
| 6 | main-watch-nudge | 50 | ~60 main-watch.sh --once ticks |
| 7 | checkpoint-context | 46 | embedded Python size ladders |
| 8 | merge-unit-local-screens | 45 | 29 pass+merge pairs |
| 9 | builder-fresh-round | 41 | 19 hand-offs x one missed 2 s poll |
| 10 | merge-unit-local-cleanup | 31 | 14 passes, 18 merges |
| 11 | builder-codex-pass-closing | 28 | 25 sequential passes, 22 verifies |
| 12 | merge-queue-glob | 27 | 4 pattern cases, 18 passes |
| 13-14 | seat-plan-finish, -marker | 24, 23 | seat.sh waits and collects |
| 15 | builder-codex-pass-rebase | 22 | 12 passes, a 1 s bounded typecheck |
| 16-19 | merge-queue, seat-update-prompt, merge-queue-train, seat-fence | 21, 20, 19, 19 | merges; fixed 1 s sleeps; 3 s windows |
| 20-24 | batch-independent-looks, resume-from-plan, merge-lock, -listing, no-poll-loops | 18 each | 0.3 s sleeps; launches; polls; hook calls |
| 25-30 | cap-gate, -retry, class-return, plan-tier, run-shell-tests, seat-launch | 17, 17, 16, 16, 16, 15 | real passes and launches |

## Reds and hangs in run F

- builder-fresh-round rc=1: load only. `timeout 10` (test :109) fired while the script polled for a log written 1 s late; green on the PC (41 s). C5 removes the wait.
- peer-offload rc=1: load only. The hup stub's signal lands after a 0 s file already finished; green on the PC in runs B-E.
- seat-run rc=1: real. Red on the PC too (runs B-E): GO then NO-GO on unit `pu` use its two judge rounds (seat.sh:337-347), so the dead-pane and detached rounds are refused. Fixed in C4.
- builder-codex-pass-threshold HUNG: load only on the Mac; on the PC 64-86 s slowest first, HUNG at 16 jobs with a file list (run E). C2 splits it.
- builder-codex-pass-closing past its cap: load only (28-30 s on the PC).
- merge-unit-local and main-watch-nudge HUNG at 240 s: load only (87-116 s, 50-71 s on the PC).
- leak-test rc=1: real, fixed on main (A3).
- New in run C: dashboard-serve-answers rc=1 at 16 jobs, a fixed `sleep 0.5` (:439) before counting restarts; green in runs B, D, E. Fixed in C5 (Q4 yes).

## Steps

- modify scripts/peer-offload.sh ~121 -- with PO_WHOLE: no peer returns 3 before the git checks; a peer passes the gate whatever the chain host (D1)
- modify scripts/peer-offload.sh ~125 -- skip the main-checkout gate only with PO_WHOLE (D1)
- modify scripts/peer-offload.sh ~127 -- the no-peer line names the reason only; the runner says what happens
- modify scripts/peer-offload.sh ~201 -- cd to the repo before removing the scratch worktree (D7)
- modify scripts/run-shell-tests.sh ~55 -- offloaded default jobs (D4)
- modify scripts/run-shell-tests.sh ~234 -- PO_WHOLE whenever SCOPE=whole, and the bare command without --skip-passed (D1, D3)
- modify scripts/run-shell-tests.sh ~241 -- a whole run refuses on 4 (D2)
- modify scripts/__tests__/run-shell-tests.test.sh ~342 -- four new checks (D1, D2, D3, D4)
- modify scripts/__tests__/peer-offload.test.sh ~119 -- six new checks (D1, D2, D7); :109 unchanged
- modify scripts/__tests__/builder-codex-pass-threshold.test.sh ~134 -- move sections 5, 9, 10 out
- new scripts/__tests__/builder-codex-pass-threshold-cap.test.sh -- sections 5, 9, 10
- modify scripts/__tests__/seat-run.test.sh ~46 -- units pd and pe for the last two scenarios (D10)
- modify scripts/__tests__/builder-fresh-round.test.sh ~107 -- write the log at once (D6)
- modify scripts/__tests__/dashboard-serve-answers.test.sh ~439 -- wait for the restart line, then the same 0.5 s (Q4 yes)
- modify README.md ~501 -- with a peer, a whole run from any checkout, main included, goes to the PC or refuses; named runs from main stay here; no peer: local
- modify docs/tests.md ~95 -- PC jobs default and slowest-first on the PC
- modify CHANGELOG.md ~3 -- the release entry
- modify .claude-plugin/plugin.json ~3 -- version

## Cuts

- C0 Builder checks A2 and starts from main (A3); A1's cage check runs after C1. Produces: nothing in the tree. Consumes: main at or after b8f3d98. Catches: a stale base (leak-test red) and a missing helper in the -cap file before any edit.
- C1 Hand-off and runner, about 75 lines (run-shell-tests.sh 22, peer-offload.sh 5, run-shell-tests.test.sh 18, peer-offload.test.sh 30). Produces: whole-run routing apart from the chain-host fallback, the refusal (exit 2), bare hand-off, offloaded jobs, a clean tail. Consumes: pr_offload's exit codes 0-4, unchanged. Consumers: run-shell-tests.sh is the one caller of pr_offload (rg, 2026-10-31); runner callers builder-codex-pass.sh:1737, post-fix-checks.sh:23 and merge-unit-local.sh's test lines run named files and keep the fallback; CI runs the whole suite on Linux, never routed. Bad input: the load figure absent, junk, empty or quoted (row 3). Catches: a whole run on a Mac with a peer configured and chain host absent or mac, or from the main checkout, which no existing check runs; a --skip-passed whole run kept local; a no-peer machine losing its local whole run. Ends with A1's cage check at the new default.
- C2 Threshold split, about 171 lines. Old -> new: :134-156 and :183-223 but :186 (11 checks, 26 other lines) -> builder-codex-pass-threshold-cap.test.sh, with the header :1-13, the helpers of A2 and the close :267-268. Kept: 25 checks. Consumes: fixtures/merge-unit-local-setup.sh, unchanged (0.04-0.14 s per extra file). Catches: the threshold HUNG of run E.
- C4 (Scope 6, own cut) seat-run setup, about 16 lines. Red-first: run C's log holds both FAIL lines at 85d01a3; after C4 both pass with seat.sh unchanged. Produces: two fresh units in the test. Consumes: seat-setup.sh, unchanged. Catches: the two seat-run reds every PC run shows.
- C5 builder-fresh-round :107 (1 line out, 1 in); dashboard-serve-answers :439 (Q4 yes). Catches: builder-fresh-round's timeout red on a loaded machine (run F) and the restart-count red of run C; no existing step changes either wait.
- C6 Docs, CHANGELOG (`## 0.66.0 -- <date>`, `### Tests` bullets in the user-facing style), version. Catches: README.md:501-502 still saying main never hands off and a down peer runs on the Mac, and version-check's refusal of an unchanged version.
- C7 Done-when and gain check: on the PC through the hand-off, `COMMANDECK_SHELL_TEST_JOBS=16 COMMANDECK_SHELL_TEST_SECONDS=<run C's list copied> bash scripts/run-shell-tests.sh`, once from a checkout at the base and once at the unit's tip, logs cited; expected: wall within 10 s of each other (schedule: 137 s both), threshold's largest file under 60 s (before 64-86 s), no HUNG. Then two whole runs back to back from the Mac at the default jobs, each under 600 s, fully green. Catches: a slower suite or a load-only red at the new job count, which the per-merge --changed run cannot see.

## Breaks

Break: scripts/__tests__/run-shell-tests.test.sh -- a whole-suite run whose PC cannot be reached refuses: exit 2, nothing runs here, one line says why -- run-shell-tests.sh case 4 whole-scope branch
Break: scripts/__tests__/peer-offload.test.sh -- a whole-suite run with chain host mac runs on the PC -- peer-offload.sh PO_WHOLE gate
Break: scripts/__tests__/peer-offload.test.sh -- a whole-suite run from the main checkout runs on the PC -- peer-offload.sh main gate under PO_WHOLE

## What can go wrong

| case | input or starting state | expected | test |
|---|---|---|---|
| peer configured, PC asleep | ssh exits 255; a whole run, or one named file | whole: exit 2, one line, nothing ran here; named: runs here once, as today | run-shell-tests.test.sh D2 check; peer-offload.test.sh PC-down check and "an unreachable PC: the files run here once, and the reason is said" |
| chain host absent or mac, peer configured, whole run | no `chain-host` file, or `mac` in it | the files run on the PC | peer-offload.test.sh D1 checks |
| no peer file, whole run | `~/.config/devenv/peer` missing (an outside contributor) | runs here, as today, no ssh | peer-offload.test.sh "a whole-suite run with no peer file runs here, as today" |
| load figure absent, junk, empty or quoted | uptime prints no figure, `no figures here`, an empty line, or `"3.0"` | no cut: cores jobs | run-shell-tests.test.sh D4 check |
| busy PC | load 20 on 16 cores | 4 jobs (the floor), never 0 | run-shell-tests.test.sh D4 check |

## Stated limits

(every reviewer is handed these; a finding beyond one is out of scope: a follow-up issue, never a blocker)
- Two PC runs at once: not measured; one run at 16 jobs peaked at load 15.88 (run C, 2026-10-31).
- The Mac's own named runs keep today's job rule.
- merge-unit-local, answer-worker and seat stay whole: at 16 jobs the schedule is 137 s with or without their splits (run C seconds, 2026-10-31).

## Not in this unit

- The busy-Mac reds and the "tree changed" lines of a Mac run.
- A shorter poll step in answer-worker.sh: a script change the measured goal does not need (run C, 147 s).

## Acceptance test

- test file path: scripts/__tests__/run-shell-tests.test.sh (a whole-suite run whose PC cannot be reached refuses: exit 2, nothing runs here, one line says why; a whole-suite run with no host: mac file hands the PC the bare command, so the PC reads and saves its own seconds; an offloaded run's default jobs are the cores less the load, at least a quarter of the cores; a --skip-passed run with no files is a whole run: it hands off with PO_WHOLE and without --skip-passed)
- test file path: scripts/__tests__/peer-offload.test.sh (a whole-suite run from the main checkout runs on the PC; a whole-suite run with no chain-host file runs on the PC; a whole-suite run with chain host mac runs on the PC; a whole-suite run with no peer file runs here, as today; a whole-suite run from the main checkout with the PC down refuses: exit 2, nothing runs here or there; a finished run on the PC prints no git error after its exit line)
- Existing, kept green: peer-offload "the main checkout never hands off: the files run here, no ssh" (:109, a named file, unchanged), seat-run (all 8 checks), seat-judge-rounds, builder-codex-pass-threshold and -cap, builder-fresh-round, peer-offload "a Mac whose chain host is the Mac runs the files here, no ssh" (a named file).

## Claims to falsify

- A whole run from any Mac checkout with a peer configured, chain host absent, mac or pc, runs no test file on the Mac.
- A whole run with a peer configured and the PC down exits 2 and runs nothing.
- A whole run with no peer file runs every file here, and CONTRIBUTING.md has no diff.
- A named-file run with the PC down still runs here once.
- A named-file run from the main checkout makes no ssh call.
- `--skip-passed` with no files hands off and never reaches the PC's command line.
- An offloaded run on an idle 16-core PC prints `run-shell-tests: 15 jobs` or `16 jobs`.
- The PC's whole run starts merge-unit-local in its first 16 launches.
- The sorted check labels of the two threshold files equal the old file's.
- seat.sh has no diff, and seat-run passes on the PC.
- No `timeout`, `TIMEOUT` or `# timeout:` line changes in the diff.
- C7's base and tip runs at 16 jobs end within 10 s of each other, with no HUNG.
- Two back-to-back whole runs from the Mac each end under 600 s, green, no HUNG, no skip, no cap overrun.

## Verification

- `bash scripts/run-shell-tests.sh --changed main` during the build (on the PC through the hand-off).
- Labels: `diff <(git show main:scripts/__tests__/builder-codex-pass-threshold.test.sh | grep -o '^check "[^"]*"' | sort) <(cat scripts/__tests__/builder-codex-pass-threshold*.test.sh | grep -o '^check "[^"]*"' | sort)` prints nothing.
- `git diff main -- scripts hooks | grep -E '^[-+].*(timeout|TIMEOUT)'` shows only moved lines, identical on both sides; `git diff main -- scripts/seat.sh` is empty.
- `claude plugin validate .`, `claude plugin test .`, `bash ci/leak-test.sh`, `bash ci/version-check.sh` pass.
- C7's four logs cited in the Plan change log.
- Review passes until a closing pass says `VERDICT: GO` naming no finding.

## Test edits

Edit rule: the owner's answer to Q4: an edit that follows the intended change and removes or loosens no check may stand. Each line below is one approval main records; `test:` rows name the test, `line:` rows quote the old line whole.
- Test edit: scripts/__tests__/builder-codex-pass-threshold.test.sh test:pass 5 with an open P2 files it and merges: STOP (cap), and --verify takes the NO-GO as a cap stop with one Open finding line per finding -- moved to -cap, unchanged
- Test edit: scripts/__tests__/builder-codex-pass-threshold.test.sh test:two findings of one class file one issue: the open classes are cp.txt and no-file -- moved to -cap
- Test edit: scripts/__tests__/builder-codex-pass-threshold.test.sh test:the merge refuses until the open findings are filed: step 1, naming each class and --filed, main unchanged -- moved to -cap
- Test edit: scripts/__tests__/builder-codex-pass-threshold.test.sh test:a filed issue must be open: a closed one, a class not open, a filing left out and a failed gh read each refuse -- moved to -cap
- Test edit: scripts/__tests__/builder-codex-pass-threshold.test.sh test:a duplicate comments instead of filing: an existing OPEN issue is accepted for each class, and the squash names each filing -- moved to -cap
- Test edit: scripts/__tests__/builder-codex-pass-threshold.test.sh test:blockAt P3: a GO beside a P3 is read as NO-GO, and the prompt names P0 to P3 -- moved to -cap
- Threshold tests 7-11: under ## Test edits, threshold part 2; seat-run, builder-fresh-round and dashboard-serve-answers: under ## Test edits, other files.
- Threshold lines: 26 non-check lines of :134-156 and :183-223 (not :186) move to -cap with them; the Builder pastes the `line:` rows test-edit-labels.sh prints for them.
## Test edits, threshold part 2

- Test edit: scripts/__tests__/builder-codex-pass-threshold.test.sh test:blockAt P1: a GO beside a P2 ends the loop with the P2 open, and the prompt names P0 and P1 -- moved to -cap
- Test edit: scripts/__tests__/builder-codex-pass-threshold.test.sh test:with the default, a GO beside a P2 stays NO-GO and the prompt is the one it always was -- moved to -cap
- Test edit: scripts/__tests__/builder-codex-pass-threshold.test.sh test:a cap of 3 makes the third pass on record a cap stop, and --verify takes it as one -- moved to -cap
- Test edit: scripts/__tests__/builder-codex-pass-threshold.test.sh test:and the default cap of 5 lets the same third pass run on: no stop, and --verify refuses a P2 below the cap -- moved to -cap
- Test edit: scripts/__tests__/builder-codex-pass-threshold.test.sh test:freshClosing no: the closing pass is handed the earlier finding and the history files stay open to it, and --verify takes its GO -- moved to -cap

## Test edits, other files

- Test edit: scripts/__tests__/seat-run.test.sh test:a pane killed mid-run: exit 3, no verdict, never GO, and one wake saying so, of a type main's inbox keeps -- :50 reads unit `pd`
- Test edit: scripts/__tests__/seat-run.test.sh test:a detached run started from a shell that is then killed (with its process group) still finishes and collects -- :70 reads unit `pe` and pe's record
- Test edit: scripts/__tests__/seat-run.test.sh line:OUT=$(rrun plan-judge-sol pu "$T/run-dead.md" 2>/dev/null); RC=$? -- `pu` -> `pd`
- Test edit: scripts/__tests__/seat-run.test.sh line:printf 'Judge the plan, detached.\nPlan: .claude/plans/pu.md\nEnd on a verdict line.\n' > "$T/run-det.md"; echo 'VERDICT: GO' > "$T/screen" -- `pu.md` -> `pe.md`
- Test edit: scripts/__tests__/seat-run.test.sh line:(:60, the heredoc line ending `run plan-judge-sol pu "$T/run-det.md" > "$T/det.out" 2>&1`) -- `pu` -> `pe`; the Builder pastes the exact row test-edit-labels.sh prints
- Test edit: scripts/__tests__/seat-run.test.sh line:DLOG=$(ls "$HOME/.commandeck/scratch/"*/run-*pu-plan-judge-sol.log 2>/dev/null | head -1) -- `pu` -> `pe`
- Test edit: scripts/__tests__/builder-fresh-round.test.sh line:(:107, the fr helper's backgrounded `(sleep 1; echo ...) &` log write) -- written at once with a future mtime; used by its 19 hand-off tests; the Builder pastes the exact row test-edit-labels.sh prints
- Test edit: scripts/__tests__/dashboard-serve-answers.test.sh line:sleep 0.5 -- wait up to 10 s for the second restart line, then the same 0.5 s; serves test "issue 294: four restarts at once run --restart once; the rest get 429"

## Done

- Done: the owner runs the whole suite from any Mac checkout with the PC configured -- it runs on the PC and reports in under 10 minutes
- Done: the owner runs the whole suite while the PC is asleep -- one line says nothing ran and how to proceed, and the Mac stays idle
- Done: an outside contributor with no PC runs the whole suite -- it runs on their own machine, as before
- Done: a contributor runs one named test while the PC is asleep -- it runs on the Mac once, as before

## Routing

- Builder: one, Opus; helpers Sonnet `general-purpose` for the C2 edit, Haiku `Explore` for search.
- Reviews: the default workflow; closing pass last.

## Question for the owner

- none open: the seat-run fix and Q4 are answered (Main answers).

## Plan change log

- 2026-10-31 plan written from runs A-F.
- 2026-10-31 owner's Scope 6 added as its own cut.
- r2 2026-10-31: Main answers recorded; Q1-Q3 removed.
- r2: D9 and the seat.sh change dropped (Q1 no); D10 and C4 fix seat-run in its setup, seat.sh unchanged.
- r2: D1 rewritten (Sol P1, Q2): a whole run from a Mac hands off whatever chain-host says; the escape at the old accepted failure mode removed; peer-offload.test.sh gains chain-host absent, chain-host mac and no-peer checks; a new Break line.
- r2: runs C-E rerun through the hand-off with logs and invocations (Sol P2); the round-1 numbers without logs dropped; run E's HUNG added; D4 notes it relies on D3.
- r2: splits settled by measured cases (Sol P2): C3 (merge-unit-local) dropped, the schedule shows no gain; C2 is one -cap file, not two; the fixture copy measured; C7 names the base-vs-tip gain run.
- r2: Catches: lines on C0-C7 (Sol P3).
- r2: Q4 added (dashboard-serve-answers, new in run C); C5 holds its 1-line fix on yes.
- r2: issue references removed; planned size 14 files, 296 lines; New tests 20.
- r3 2026-10-31 (owner's answer): the PC-only whole-suite rule applies only where a PC peer is configured (D1, D2, Goal, Why, Main answers); with no peer the whole suite runs locally as today; the no-peer check now expects a local run, not a refusal; the What can go wrong rows, Claims, Done and the accepted failure mode follow; CONTRIBUTING.md is no longer changed (13 files, 293 lines). Q4 unchanged.
- r4 (Opus P1): the main-checkout gate stays for runs without PO_WHOLE; peer-offload.test.sh:109 and its header stay unchanged (its Test edit line gone); a new check, a whole run from the main checkout, replaces the flipped one; the Break line, Steps, Claims and the README step follow.
- r4 (Opus P2): PO_WHOLE is set whenever SCOPE=whole, --skip-passed with no files included; the bare command drops --skip-passed; a new run-shell-tests check; New tests 21.
- r4 (Opus P3): D1 says the same files run here and the two no-peer lines are gone, not "exactly as today".
- r4 (Opus P3): A2 is [uncertain] with LED, answer and routed named; the section times are marked as split from whole-file runs (Measurements, D5).
- r4 (Opus Builder guess 3): with PO_WHOLE, no peer returns 3 before the git folder checks (D1, Steps).
- r4 (Sol P2): A1's cage check moves after C1, at C1's new default; C0 no longer runs it.
- r4 (Sol P3): Catches: lines on C5 and C6.
- r4: Sol P1 (C4 in the test setup, not seat.sh) is held for the owner's decision; C4 is unchanged.
- r5 2026-10-31 (owner's answers): the seat-run fix stays in the test setup (C4, D10), seat.sh unchanged, Sol P1 closed; Q4 yes, so C5 fixes the dashboard-serve-answers wait unconditionally; Main answers gain both; the question section is empty; Test edits list each existing test edit by file and test name, or by the exact old line where no test holds it.

- Build 2026-10-31: the three Break lines lose their leading `- `, the form break-run.sh and the pass's break gate read (`^Break: `); as bullets neither saw them. Content unchanged.
- Build 2026-10-31, C7's logs (~/.commandeck/scratch/): commandeck-fast-tests-c7-base.log (155 s), -c7-tip.log (160 s, green, threshold 58 s, no HUNG), -c7-mac-a.log (319 s, 8 jobs) and -c7-mac-b.log (399 s, 4 jobs), both green; -c7-tip-overlapped.log is a tip run that shared the PC with another worker's run (not counted). A1: -c7-a1.log, 15 jobs, no cage kill.

## Facts

- The default job count is half the cores, one less under load -- scripts/run-shell-tests.sh:55-62 (observed: 2026-10-31)
- The hand-off routes only a Mac whose chain host is pc -- scripts/peer-offload.sh:121 (observed: 2026-10-31)
- The peer is the destination in ~/.config/devenv/peer -- scripts/peer-offload.sh:9 (observed: 2026-10-31)
- The chain host is mac when its file is absent -- scripts/host-services.sh:22-28 (observed: 2026-10-31)
- The main checkout never hands off -- scripts/peer-offload.sh:125 (observed: 2026-10-31)
- No peer prints "running here" and returns 4 -- scripts/peer-offload.sh:127 (observed: 2026-10-31)
- Exit 3 or 4 runs the files here; 2 runs nothing -- scripts/run-shell-tests.sh:239-245 (observed: 2026-10-31)
- The hand-off passes the file list, so the PC run is not whole-scope -- scripts/run-shell-tests.sh:233-237 (observed: 2026-10-31)
- Only a whole-scope run that did not hand off saves seconds -- scripts/run-shell-tests.sh:403 (observed: 2026-10-31)
- The whole list is the two test folders -- scripts/run-shell-tests.sh:216 (observed: 2026-10-31)
- The PC exports COMMANDECK_OFFLOADED and runs in a memory cage -- scripts/peer-offload.sh:176-180 (observed: 2026-10-31)
- COMMANDECK_SHELL_TEST_* variables travel to the PC -- scripts/peer-offload.sh:145-148 (observed: 2026-10-31)
- The PC script deletes its scratch worktree from inside it -- scripts/peer-offload.sh:169, scripts/peer-offload.sh:201 (observed: 2026-10-31)
- The cage is a memory limit only -- scripts/host-services.sh:238 (observed: 2026-10-31)
- A file's wall limit grows with load up to 4x its cap -- scripts/run-shell-tests.sh:302-310 (observed: 2026-10-31)
- The existing jobs check -- scripts/__tests__/run-shell-tests.test.sh:339-341 (observed: 2026-10-31)
- The main-checkout and chain-host-mac checks run named files -- scripts/__tests__/peer-offload.test.sh:108-114 (observed: 2026-10-31)
- The fresh-round script needs a log newer than its stamp -- scripts/builder-fresh-round.sh:175, scripts/builder-fresh-round.sh:221-226 (observed: 2026-10-31)
- The test writes that log 1 s late -- scripts/__tests__/builder-fresh-round.test.sh:107 (observed: 2026-10-31)
- Judge rounds per unit are capped -- scripts/seat.sh:337-347 (observed: 2026-10-31)
- seat-run runs four judge rounds on unit pu -- scripts/__tests__/seat-run.test.sh:24, scripts/__tests__/seat-run.test.sh:43-47, scripts/__tests__/seat-run.test.sh:60 (observed: 2026-10-31)
- seat-run sets up pu's planning worktree and plan -- scripts/__tests__/seat-run.test.sh:9-12 (observed: 2026-10-31)
- The cap test pins a third round refused -- scripts/__tests__/seat-judge-rounds.test.sh:21-24 (observed: 2026-10-31)
- `loop` is defined in section 9 -- scripts/__tests__/builder-codex-pass-threshold.test.sh:186 (observed: 2026-10-31)
- The fixture copies the repository -- scripts/__tests__/fixtures/merge-unit-local-setup.sh:7 (observed: 2026-10-31)
- dashboard-serve-answers waits a fixed 0.5 s before counting restarts -- scripts/__tests__/dashboard-serve-answers.test.sh:439-440 (observed: 2026-10-31)
- The docs say main never hands off and a down peer runs on the Mac -- README.md:501-502 (observed: 2026-10-31)
- The docs give the default jobs -- docs/tests.md:94-95 (observed: 2026-10-31)
- CI runs the whole suite -- .github/workflows/ci.yml:49 (observed: 2026-10-31)

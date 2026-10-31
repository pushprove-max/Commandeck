# plugin-open-2026-10-31-b -- every open plugin issue in one unit

Owner's words: the owner, 2026-10-31: "start a unit for all plugin issues". One unit, no split, whatever the size caps say.
Owner's additions: the owner's answers of 2026-10-31: Q1 (a), Q2 (a), Q3 (a) under 50 lines, Q4 (b) a CPU-time bound per test file with no existing limit raised, Q5 (a) every user-visible change listed, Q6 (a) the 4x wall-clock ceiling under load; and the swap of the second plan judge to plan-judge-opus on Opus at high effort with the same trigger, ported from host 6e876e612, its test renames approved, a clean rename of the `planJudgeFable*` settings with no compatibility path, the release notes telling users to rename a stored setting.
Goal: Close the open plugin issues: worktree report fixes, a bad-input plan check, closing-pass gates, a lighter plan route, an empty-read fix, a CPU bound for shell tests, the Opus judge.
Plan: .claude/plans/plugin-open-2026-10-31-b.md
Tier: Standard; LOCAL merge only; changed-file tests only; no test-timeout raises.
Split override: the owner's order names one unit, no split, whatever the size caps say.
Build order: C1 to C13 in order; C13 last. No cut waits on the owner.
- Planned size: 50 files, 655 changed lines
New tests: plugin-open-2026-10-31-b 35 -- 27 new cases plus 8 existing checks whose labels the judge swap renames, which the pass's counter reads as new
Version: 0.65.0 (a minor: new behaviour), unless `bash ci/version-check.sh` at merge time says another number is taken.
Closes: #522 #524 #525 #526 #527 #528 #529 #530 #531
Refs: #506 #513 #523
Timed checks: builder-codex-pass-rebase.test.sh :93-96; builder-launch-resume-from-plan.test.sh :44-48; run-shell-tests.test.sh :14-358; unit-drive.test.sh :44-135 (`rg 'sleep|timeout|wait_for|SECONDS|date \+%s'`, 2026-10-31). New cases go before :93 in builder-codex-pass-rebase.test.sh, at the end elsewhere; the CPU-bound cases, the heaviest (a 2 s sleep, a 2 s busy loop), last.

## Merge

- Merge commit message: `Closes` each issue on the Closes: line, then `Refs #506`, `Refs #513`, `Refs #523`.
- An issue whose outcome below reads partial moves from Closes to Refs before the merge: #531 (A3 red).
- #523: main closes it by hand. The comment carries the exact command, `python3 $PP_SCRATCH/plugin-open-2026-10-31-b-523-measure.py`, with the script's text (its class regexes and its session pick: the largest log in each of the 10 newest unit folders, plugin-open-2026-10-31, -19, fix-ci-red, -23, -5, -15, port-verify, -7, cd-test-rules, restart-wake), and what it prints. Rerun 2026-10-31: file prints 40%, search 21%, git 17%, single test files 6%, the runner 2%. The second judge measured 14% tests and 31% file prints over 11 sessions; test runs do not lead either way. The lead, file prints, may become a new issue.
- Release notes, written after all plugin merges: tell a user who stored a `planJudgeFable*` setting to rename it to `planJudgeOpus*`; nothing reads the old name. C13's CHANGELOG entry carries the same line.
- #492, #500, #501, #508 stay closed (retests under Not in this unit, rerun 2026-10-31): #492's second call exists and no test file carries its header; the code #500, #501 and #508 name is absent at 379f4f4.

## Why

Eight of the ten new issues have host twins built in host a79d14754, so this unit ports them, each issue's part only, fitted to the plugin. The host's id rule for #522 hands a sibling unit's decision (`<unit>-b-...`) to `<unit>`, so the plugin matches its own id shapes exactly and fixes `decision.sh holds` with the same rule, which #525's gate and the merge read. #525 and #526 change behaviour two existing tests pin; the owner approved those edits. #523 was measured and its condition is false. #513's verdicts need the owner. #506: one test's temp folder in the root caused the false tree-changed lines, and the fence now judges each test on its own run; the reds are load-driven, and the owner chose a CPU-time bound per test file. The owner also ordered the second plan judge's swap to Opus.

## Prior art

- Host a79d14754 (on host main; `git log a79d14754..main` touches none of these files, 2026-10-31): #522 (host 3453), #524 (3455), #525 (3456), #526 (3457), #527 (3458), #528 (3459), #529 (3460), #530 (3461). Host 6e876e612: the judge swap.
- No host fix: #506, #531. Host twin measured false and closed: #523 (3454).
- Not ported: the undated-unit id branch and the `-[a-z]` suffix rule (#522); the round report question-line check (#525: no plugin reviewer writes one); `scripts/test-changed.sh` and its repeat refusal (#526); `pp_risky_named` (#527); the `~/.codex-review` read (#528: no plugin writer).
- Standard: templates/test-rules.md. Library: none; Python's `re`, bash `times` and the shell are enough.

## Data design

- `tool_gaps` on a worktree report pass (C4, new): true when a reviewer's message says its symbol search was unavailable, timed out or could not index. Set by read_codex, false on a Claude reviewer's pass. Reader: render.py's note. Old reports read as false.
- `role` on a read session or Codex record (C3, new, in memory only): user messages are read in order to the first one carrying a `Seat tag seat-<role>-<epoch>-<pid>` or a spec name, and that one decides. Reader: the plan split.
- `review-limits.tinyPlanLines` in config/routing.json (C9, new): 50. A routing file without it takes the shipped value, as `oneJudgeLines` does.
- `$STAMP.others` and `$STAMP.t<k>` (C10, new): the untracked, not-ignored files at the run's stamp, and one start stamp per test file, in the git dir beside the run's stamp. Writer: the runner. Reader: fence(). Removed by the runner's exit trap with the stamp.
- `$RES/<k>.cpu` (C11, new): the test file's CPU seconds from `times`. Writer: run_one. Reader: status_line. Removed with `$RES`.
- `$RES/<k>.cpu.tmp` (C11, new): the parsed CPU seconds before run_one renames it to `$RES/<k>.cpu`; a failed parse removes `.cpu` and status_line reads no CPU. Removed with `$RES`.
- `$RES/<k>.rc` (C11, changed): `<rc> <secs>` becomes `<rc> <secs> <limit> <load1> <cores>`, one line, space-separated: the exit, the wall seconds, the cap after the load factor (D11), and the load and cores bound() read (empty load or cores read as 0). Writer: run_one, one `echo` after the file ends. Readers: status_line (all five fields: exit, wall against the cap, the HUNG text) and save_seconds (field 2 alone, the rest discarded); the report reads only that it exists (no file is a failure). The record lives in this run's `$RES` and is removed with it; no later run reads it, and a rerun writes a new one in a new `$RES`. Nothing retries.
- `$STAMP.tick<pid>` (C10, renamed from `$STAMP.tick`): the file tick() touches, one per process, so parallel files ticking their own stamps do not share one. Writer and reader: tick(). Removed by the exit trap's `$STAMP.*`.
- `kind: "planning"` on a worktree report pass (C3, new value): a pass whose `role` is plan gets `n` 0 and kind `planning`. Readers: collect.py's pass counts (n 0 is no pass) and render.py's pass table (prints the kind as text). Old reports have no such pass.
- `planJudgeFable*` to `planJudgeOpus*` (C12, renamed): the four /plugin config keys follow the role name (paths.sh `pp_role_key`). A clean rename (owner, 2026-10-31): a stored `planJudgeFable*` answer is no longer read, and the Opus judge takes the shipped default (on, opus, high) until the user renames it or reruns setup. No compatibility path; the release notes tell users to rename it.
- No other migration: every new key is optional.

## Decisions already made

- D1 #522: an id names the unit when it is exactly `<unit>`, `plan-<unit>` or `review-stop-<unit>-r<digits>`, the shapes the plugin writes. A hand-written `<unit>-<slug>` id is the unit's only through its source or answer, as today. The same id rule, a Python and a jq copy, in collect.py and `decision.sh holds`, each tested. The text fields stay as each reads them today: holds reads question and source, as an open row has no answer; the report reads source and answer.
  Test: "an id-only decision is cut"; "a sibling unit's id is not cut"; "holds lists a plan-<unit> question"; "holds ignores a sibling's review stop"
- D2 #524: plan-check reads `## Steps` and `## Cuts`, as the host does; when they say pars, refus, reject or validat, `## What can go wrong` must name absent or missing, junk or trailing, empty, and quoted; each missing kind is named. A gate-only plan opts out with `Bad input: none, <reason>`. The last unit's plan, plugin-open-2026-10-31.md, is a failing input: with C5 it is asked for bad-input rows.
  Test: "a plan missing bad-input cases is refused"; "a plan with bad-input cases passes"; "the last unit's plan is asked for bad-input rows"
- D3 #526 (Q2 a): a closing pass runs the shell tests that cover the unit's changed files when main has not moved; with none selected `T_TESTS` stays `not run`. A red run with no rebase says `before the closing pass`; the rebase texts stay. The plugin checks are post-fix-checks.sh's, which runs `claude plugin validate .` and `claude plugin test .` after each fix; the rule says run it before the closing pass.
  Test: "a closing pass with main unmoved runs the changed tests first"
- D4 #525 (Q1 a): a closing pass is refused while `decision.sh holds <unit>` prints an open row, a waitsOn main row included, as the merge reads it. An unreadable ledger is not refused: the pass runs and says so, as today (main, 2026-10-31). Only `final`.
  Test: "a closing pass is refused while an owner question is open"
- D5 #527 (Q3 a): the tiny rule reads the trigger pick: only a batch no panel or risk trigger matched, with an `Estimated size:` under `tinyPlanLines`, is One planner, decided before the under-150 downgrade at plan-tier.sh:37-40, so a security item never is. builder-launch.sh runs plan-tier.sh on the batch and accepts no verdict on `tier: One planner`. Dropped: the judge's read and its revise round.
  Test: "a tiny plan skips the judge unless a panel trigger matches"; "a 30-line auth fix keeps a judge"; "a tiny plan launches with no judge verdict"
- D6 #528: a Claude session or Codex record is planning when the first user message, read in order, that carries a seat tag or a spec name says so: a tag naming a `plan-` role (seat.sh:526-527 for a Claude pane; dispatch-task.sh:65's pointer for a Codex pane, after its untagged `# AGENTS.md instructions` message), or a spec named `-plan-spec`, `-plan-author`, `-plan-judge-` or `-plan-revise`. Builder start is the earliest other session or record. When planning ends before it, stage 0 is `Plan and judge`, then `Build`. Planning records stay in `runs`, so their tokens, calls, cost and busy spans count (collect.py:780, :835); they make no stage of their own and are never numbered passes. Codex records are read from t0's day to the day of the run's last record, not cut at t1 + 60, and t1 is the last end of either client. A hand `--split` keeps its stages.
  Test: "plan share splits from build"; "a Codex-only unit splits at its first Builder record"; "a Codex plan judge found by its seat tag is planning"; "planning tokens stay in the stage cost"; "a Codex Builder after Claude planning splits the stages"
- D7 #530: the host's pattern in a reviewer's message. A note only.
  Test: "a reviewer tool gap is recorded"; "a normal reviewer message is no gap"; "a Claude reviewer pass reads no gap"
- D8 #529: a code-writing helper's report quotes its failing run; the Builder reads it before taking the diff.
  Test: "a helper report shows its red run"
- D9 #531: a Read is recorded only when `tool_response.file.content` is a non-empty string. No other branch: the test helper at companion-read-guard.test.sh:30 gains the real shape (Test edits).
  Test: "an empty Read counts for nothing"
- D10 #506: each test is judged on its own run. A kept file newer than the run's stamp, or gone (find's exit status), breaks it. A folder newer than the test's own start stamp breaks it, a kept one or one git does not ignore that holds no kept file (an empty folder, or one of untracked files only: `git ls-files --others --directory` and every folder under each, read when the record is written; an ignored folder is not read, as its content is not TREE; pass 3 P2); tick() takes the stamp it must pass, the run's at the start and the test's own before each file. At the test's start, in this order: its stamp and tick, then the untracked-list check for a folder, kept or untracked, newer than the run's stamp only: the list must equal the stamped one. The reuse check at :238 keeps today's strict rule.
  Test: "a temp folder made and removed before a test leaves its result recorded"; "a folder entry made during a test stops its record"
- D11 #506 (Q4 b, Q6 a): each file's existing cap becomes a CPU bound, with no new configured value. Load factor `min(4, max(1, load1 / cores))` as a decimal (awk, not bash's integer division), read at the file's start; the file runs under `timeout` at cap x factor rounded up to a whole second: load 15.9 on 8 cores gives 1.99, so 239 s for a 120 s cap. A kill at factor 1 prints `HUNG past <cap>s` as today; past it, `HUNG past <n>s (load <load1> on <cores> cores)`. Wall time at or under the cap: as today. Past it: passes only if its exit is 0 and its CPU (bash `times` around the run) is at or under the cap, else FAIL naming both. On an idle machine every bound is as today.
  Test: "a slow test under load passes within its CPU cap"; "an idle machine keeps the wall cap"; "a test past its CPU cap fails"
- D12 owner-ordered: plan-judge-fable becomes plan-judge-opus: model `opus`, effort high, same trigger and seats. `opus` and not `claude-opus-5-5`: Claude seats take aliases only (paths.sh:749-751); the alias runs Opus 5.5 today.
  Test: "the Opus judge is a read-only Claude reviewer on opus at high"

## Accepted failure modes

- F1 #522: a hand-written `<unit>-<slug>` id whose source and answer omit the unit is not the unit's.
  Test: "a sibling unit's id is not cut"
- F2 #530: a gap said in other words shows no note.
  Test: "a normal reviewer message is no gap"
- F3 #528: a planning spec named another way counts as build: 3 of 173 of main's planning briefs (Stated limits).
  Test: none, the names are main's own words
- F4 #506: a test whose run overlaps another's temp folder in the root is still not recorded; a full run is not expected at zero lines.
  Test: "a folder entry made during a test stops its record"
- F5 #506: a process a test leaves running unwaited is outside its CPU count.
  Test: none, `times` counts reaped processes only

## Assumptions

- A1 [settled] A Read past the end answers `content: ""`, `numLines: 0` (this seat, offset 900, transcript row, 2026-10-31).
- A2 [settled] The bad-input check breaks no existing test: plan-check-budget, -caps, -issue-cases, -new-tests, -placeholder-fences, builder-codex-pass-issue, builder-launch-resume-launch-line, seat-run, unit-drive green in a scratch clone with it, 2026-10-31.
- A3 [likely] A PostToolUse `tool_response` for Read is the transcript's `toolUseResult`. Builder check after C1, in a live seat in a scratch repo with `.claude/companions.tsv`: Read the contract at offset 900, then Edit its pair. Refused: Closes #531. Allowed: `#531: partial -- the hook payload shape`, move to Refs.
- A4 [settled] D1's rule gives none of `review-stop-<unit>-b-r7`, `plan-<unit>-b`, `<unit>-aa-q1` to `<unit>` (exact match, by construction).
- A5 [settled] bash `times` around `timeout 100 bash t.sh` read 1.69 s CPU against `/usr/bin/time`'s 1.87 s for 60 python and git calls on the Mac, 2026-10-31.
- A6 [likely] The same holds on the PC. Builder check before C11 on the PC: the same file; within 20%: build; else stop C11, `#506: partial -- the CPU bound`, ask main.
- A7 [settled] The swap's word in main-session.md:65 moves one rule id, 895a7e56 to 6d145326 (`merge-rules.py --units` on a copy, 2026-10-31). Plain rename (main's ruling, round 3, item 12): no key move; a stored keep-mine choice under 895a7e56 stops applying, by owner decision; merge-rules.py:181's dead 895a7e56 entry goes, no ancestry pair is added, and merge-rules.test.sh:58 drops its 895a7e56 pair. Check: hooks/__tests__/agent-startup-context.test.sh:58-63, the stored-choice cases, stays green after C12.

## Steps

- modify hooks/read-record.sh ~32 -- C1
- modify skills/worktreereview/scripts/{collect,render}.py -- C2,C3,C4
- modify skills/worktreereview/SKILL.md -- C2,C3,C4
- modify scripts/decision.sh ~284 -- C2 holds
- modify scripts/plan-check.sh ~468 -- C5
- modify scripts/seat.sh ~501 -- C5
- modify templates/{_batch-brief-template,_builder-brief-template,rules-details,main-session}.md -- C5-C8,C12
- modify scripts/builder-codex-pass.sh ~1740 -- C7,C8
- modify scripts/{plan-tier,builder-launch,codex-helpers,unit-drive}.sh -- C9,C12
- modify scripts/merge-rules.py ~181 -- C12
- modify config/{routing,recommended}.json -- C9,C12
- modify .claude-plugin/plugin.json -- C12,C13
- modify scripts/run-shell-tests.sh -- C10,C11
- modify docs/{hooks,review-loop,first-build,configuration,tests,auto-permission-mode}.md -- C1,C7,C9,C11,C12
- modify {README,CHANGELOG}.md -- C12,C13
- modify skills/setup/SKILL.md ~129 -- C12
- modify hooks/__tests__/companion-read-guard.test.sh -- C1
- modify scripts/__tests__/{worktreereview,decision}.test.sh -- C2,C3,C4
- new scripts/__tests__/plan-check-bad-input.test.sh -- C5
- modify scripts/__tests__/brief-template.test.sh -- C6
- modify scripts/__tests__/builder-codex-pass-{rebase,decisions,threshold}.test.sh -- C7,C8
- modify scripts/__tests__/{plan-tier,builder-launch-resume-from-plan,unit-drive}.test.sh -- C9,C12
- modify scripts/__tests__/run-shell-tests.test.sh -- C10,C11
- modify scripts/__tests__/{plugin,seat-launch,seat-launch-github,seat-run-refused,doctor,codex-ask,merge-rules}.test.sh -- C12

## Cuts

- C1 #531, ~22. D9. read-record.sh:12-15 reads the content's length; :32 needs it. docs/hooks.md:84. New case at the end with its own session id, its tracker removed by an added line. Catches: a past-end Read opening a paired edit. Then A3.
  Produces: none. Consumes: the Read response. Consumers: companion-read-guard.sh reads the tracker as before.
- C2 #522, ~35. D1. collect.py:306-327 ORs the id rule into `mine`; decision.sh:283-284's id test becomes the exact shapes. Catches: an owner wait left on the build clock; a `plan-<unit>` question the merge and the closing pass miss.
  Produces: the id rule. Consumers of holds: merge-unit-local.sh:265, main-watch.sh:289, builder-codex-pass.sh:1943, C8; each sees more open rows, never fewer.
- C3 #528, ~80. D6. `SEAT_TAG`, `PLAN_SPEC` beside `ASK` (:67); `role` in read_session (:142) and read_codex (:350); the Codex read at :664-668 spans t0's day to the day of the run's last record, with t1 the last end of either client; `plan_split` over sessions and `runs` (:696) on both paths (:670-675), before the stages (:700); the stage loop puts a planning record inside `Plan and judge`. The seat-tag fixture opens with an untagged `# AGENTS.md instructions` user message before the tagged pointer. Catches: a report with no planning share; a plan judge shown as a Codex run inside the build; a Codex Builder after Claude planning dropped from the window; planning spend left out of the totals.
  Produces: the stage. Consumes: sessions, Codex records. Consumers: render.py prints stages as it does.
- C4 #530, ~28. D7. `TOOL_GAP`; read_codex sets it; fold_passes (:421) ORs it; the Claude pass at :683-686 sets false; the key list (:1022) adds it; render.py after :209. Catches: a GO resting on text search alone, unseen.
  Produces: `tool_gaps`. Consumers: render.py; extras.finding_value reads passes by key.
- C5 #524, ~65. D2. After plan-check.sh:457-467, before :472, under `[ -n "$SRC" ]`. One sentence after seat.sh:501 and in the batch template. Catches: a parser planned with no bad-input case.
  Produces: the refusal. Consumers: builder-launch.sh and seat.sh run plan-check.sh; A2.
- C6 #529, ~4. D8. After _builder-brief-template.md:75-83; one `check`. Catches: a helper diff with no red run taken as tested.
  Produces: the rule. Consumers: every Builder brief.
- C7 #526, ~45. D3. rebase_and_test (builder-codex-pass.sh:1733-1771): the rebase block under `if [ "$old" != "$new" ]`; `files` is the branch diff, plus main's when it moved. Rule in rules-details.md and the brief template: land pending work, main's judges and post-fix-checks.sh before the closing pass. docs/review-loop.md:33-38. Test edits: rebase.test.sh:56; fin 12's 20 s window at :93-96 now holds two runner calls: the Builder times it on the PC, and over 10 s moves its clock after the pre-review step. Catches: a red changed test found after a closing GO.
  Produces: the earlier red. Consumes: shell-tests-for.sh, test_call. Consumers: the round file's Pre-review line.
- C8 #525, ~55. D4. First line of precheck's final block (:1664), with its own `decision.sh holds` call: holds() is defined at :1943, after precheck runs. Rule: a merge-blocking question goes to main the turn it is named. Test edits: decisions.test.sh, after :28 writes its rows and before :30, adds a review pass 17 carrying the HOLD checks of :30-33, then an answered row for the open id, so pass 18 runs; :39-44 stay as written (an unreadable ledger runs); threshold.test.sh answers q-oc-open before pass 3, and :85 greps it as answered. Catches: a closing pass spent before the answer that changes the code.
  Produces: the refusal. Consumes: holds (C2). Consumers: none new.
- C9 #527, ~65. D5. plan-tier.sh, keyed on the trigger pick before :37-40; builder-launch.sh:160-167; routing.json:96 and its note; _batch-brief-template.md:18 and main-session.md:60-65 say the `Estimated size:` line feeds the tiny route; docs/first-build.md:8, docs/configuration.md. Catches: a one-validator fix paying a judge round.
  Produces: the tier. Consumers: unit-drive.sh reads plan-tier's seats; builder-launch.sh.
- C10 #506, ~60. D10. Stamp (run-shell-tests.sh:139-144) saves `$STAMP.others`; run_one (:275) makes `$STAMP.t<k>` and ticks before the file starts; fence(<k>) (:134-137) prints every newer path. Catches: one test's temp folder marking every later result unrecorded (main-edit-guard.test.sh:22); an entry made and removed during a test passing.
  Produces: the per-test window. Consumers: the ledger write (:290-292); :238 unchanged.
- C11 #506, ~75. D11. run_one (:275-284) reads the factor, sets `timeout`, writes `$RES/<k>.cpu`; status_line (:299-304) adds `past its <cap> s cap: <wall> s wall, <cpu> s CPU`, on an `ok` line past its cap too. `times` prints minutes (`0m1.690s`); the parse reads both parts. docs/tests.md. Tests stub `uptime` and `getconf`, as the default-jobs cases do. Catches: a starved file failing on wall time with CPU to spare; a CPU hog passing on a busy machine.
  Produces: the CPU bound. Consumes: `uptime`, `getconf`, `times`. Consumers: `.githooks/pre-push`, CI, the closing pass's runner calls.
- C12 owner-ordered swap, ~75. D12. Host 6e876e612's lines in routing.json, plan-tier.sh:52-53, builder-launch.sh:162 and :192-198, codex-helpers.sh:51, main-session.md:65; the plugin's own: plugin.json:157-179, recommended.json:24-27, README.md:177, :391-395 (with :392's `the Fable judge always runs on Claude`) and :475, plugin.json:128 (`Off: the Fable judge judges alone`), skills/setup/SKILL.md:129, docs/configuration.md:20 and :43, docs/auto-permission-mode.md:39. unit-drive.sh:10, done when `rg -n Fable scripts/unit-drive.sh` prints nothing. `judge-fable` at codex-helpers.sh:55 is another role; it stays. A7: merge-rules.py:181's dead entry and merge-rules.test.sh:58's pair go; agent-startup-context.test.sh runs after.
  Produces: plan-judge-opus. Consumers: plan-tier's seats, unit-drive, builder-launch, seat.sh by role name, doctor.
- C13 version and docs, ~35. plugin.json, README badge, CHANGELOG in the user-facing style, docs for each changed behaviour.
  Produces: 0.65.0. Consumers: `ci/version-check.sh`.

## Breaks

Break: hooks/__tests__/companion-read-guard.test.sh -- an empty Read counts for nothing -- hooks/read-record.sh content check
Break: scripts/__tests__/decision.test.sh -- holds lists a plan-<unit> question -- scripts/decision.sh holds id rule
Break: scripts/__tests__/plan-check-bad-input.test.sh -- a plan missing bad-input cases is refused -- scripts/plan-check.sh bad-input block
Break: scripts/__tests__/builder-codex-pass-decisions.test.sh -- a closing pass is refused while an owner question is open -- scripts/builder-codex-pass.sh precheck final block
Break: scripts/__tests__/builder-codex-pass-rebase.test.sh -- a closing pass with main unmoved runs the changed tests first -- scripts/builder-codex-pass.sh rebase_and_test
Break: scripts/__tests__/plan-tier.test.sh -- a tiny plan skips the judge unless a panel trigger matches -- scripts/plan-tier.sh tiny rule
Break: scripts/__tests__/run-shell-tests.test.sh -- a folder entry made during a test stops its record -- scripts/run-shell-tests.sh fence per-test window
Break: scripts/__tests__/run-shell-tests.test.sh -- a test past its CPU cap fails -- scripts/run-shell-tests.sh CPU rule

## What can go wrong

| Case | Input or starting state | Expected result | Test |
|---|---|---|---|
| Absent or empty Read text | a Read response with `content: ""`, or with no `file` object | nothing recorded, the paired edit stays refused | an empty Read counts for nothing |
| Junk or trailing text after a unit name in an id | `review-stop-<unit>-b-r7`, `plan-<unit>-b`, `<unit>-aa-q1`, `x<unit>` | not this unit's decision, in the report and in holds | a sibling unit's id is not cut |
| Quoted or empty plan sections | a step with `"parse"` in quotes; an empty What can go wrong; `Bad input: none,` with no reason | refused, naming each missing kind | a plan missing bad-input cases is refused |
| An open row that waits on main, or one whose question alone names the unit | an unanswered `<unit>-msg_x` row with waitsOn main | the closing pass is refused, naming the id, as the merge refuses | a closing pass is refused while an owner question is open |
| An entry made and removed during a test | a test creates `extra` while another test checks it, then removes it | the checking test is not recorded | a folder entry made during a test stops its record |
| An entry in a folder no kept path names | an earlier test leaves an empty folder and a later one makes and removes a file in it; or an empty folder is there before the run and a test leaves a file in it | neither the changing test nor the later one is recorded | a folder no kept path names is fenced too (an earlier test's empty folder; an empty folder there before the run) |

## Stated limits

(every reviewer is handed these; a finding beyond one is out of scope: a follow-up issue, never a blocker)
- #523: 10 Builder sessions, 2026-10-28 to 2026-10-31: test runs 8%, file prints 40% (the measure under Merge, 2026-10-31); the second judge: 14% and 31% over 11.
- #506 reds: 12 files, load 15-120, 8 cores, CPU 23-30% of wall: 8 passed uncapped in 221-534 s, dashboard-live failed 3 of 6 checks and passed alone in 17.5 s, 3 killed at 600 s (`/usr/bin/time -l`, 2026-10-31).
- #528: 170 of 173 planning briefs in main's `.claude/briefs` match (2026-10-31).

## Not in this unit

- #492: the own-lane call exists (builder-codex-pass.sh:1758, run-shell-tests.sh:230); `rg -n '^# own-lane:' scripts hooks` hits one fixture line, so no test file has the header. Stays closed.
- #500, #508: `rg -n 'Subject growth' scripts hooks skills templates config docs` prints nothing. Stay closed.
- #501: `rg -n 'approvals/|continue-\$|answered "lift"' scripts/builder-codex-pass.sh` prints nothing. Stays closed.
- #506's dashboard-live: its 5 s windows are wall time inside the test; and the 3 files killed at 600 s are unexplained.
- #513: under Left for the owner.

## Acceptance test

- test file path: hooks/__tests__/companion-read-guard.test.sh (an empty Read counts for nothing)
- test file path: scripts/__tests__/worktreereview.test.sh (an id-only decision is cut; a sibling unit's id is not cut; plan share splits from build; a Codex-only unit splits at its first Builder record; a Codex plan judge found by its seat tag is planning; planning tokens stay in the stage cost; a Codex Builder after Claude planning splits the stages; a reviewer tool gap is recorded; a normal reviewer message is no gap; a Claude reviewer pass reads no gap)
- test file path: scripts/__tests__/decision.test.sh (holds lists a plan-<unit> question; holds ignores a sibling's review stop)
- test file path: scripts/__tests__/plan-check-bad-input.test.sh (a plan missing bad-input cases is refused; a plan with bad-input cases passes; the last unit's plan is asked for bad-input rows)
- test file path: scripts/__tests__/brief-template.test.sh (a helper report shows its red run)
- test file path: scripts/__tests__/builder-codex-pass-rebase.test.sh (a closing pass with main unmoved runs the changed tests first)
- test file path: scripts/__tests__/builder-codex-pass-decisions.test.sh (a closing pass is refused while an owner question is open)
- test file path: scripts/__tests__/plan-tier.test.sh (a tiny plan skips the judge unless a panel trigger matches; a 30-line auth fix keeps a judge)
- test file path: scripts/__tests__/builder-launch-resume-from-plan.test.sh (a tiny plan launches with no judge verdict)
- test file path: scripts/__tests__/run-shell-tests.test.sh (a temp folder made and removed before a test leaves its result recorded; a folder entry made during a test stops its record; an idle machine keeps the wall cap; a slow test under load passes within its CPU cap; a test past its CPU cap fails)
- test file path: scripts/__tests__/plugin.test.sh (the Opus judge is a read-only Claude reviewer on opus at high)

## Claims to falsify

- No existing fixture plan trips the bad-input check (A2).
- D1's rule gives no sibling unit's id to this unit, in the report or in holds.
- No caller of holds is hurt by more open rows: each refuses or lists, none skips.
- A Read past the end reaches read-record.sh with `file.content` empty (A3).
- Unmoved-main selection equals a rebased one for the branch's files.
- A batch any panel or risk trigger matched never becomes One planner, at any size.
- The wider Codex window turns no existing worktreereview case red.
- `tool_gaps` reaches no gate.
- The per-test fence keeps every ordering of run-shell-tests.test.sh:243-288 rerunning.
- On an idle machine the runner's result for every file is as today.
- After C12 no shipped file but CHANGELOG history names plan-judge-fable.
- A push from a Mac whose chain host is pc runs its tests on the PC (run-shell-tests.sh:194-218).

## Issue cases

- #522 Body 1 -- skills/worktreereview/scripts/collect.py -- an id-only decision is cut
- #524 Body 1 -- scripts/plan-check.sh -- a plan missing bad-input cases is refused
- #525 Body 1 -- scripts/builder-codex-pass.sh -- a closing pass is refused while an owner question is open
- #526 Body 1 -- scripts/builder-codex-pass.sh -- a closing pass with main unmoved runs the changed tests first
- #527 Body 1 -- scripts/plan-tier.sh -- a tiny plan skips the judge unless a panel trigger matches
- #528 Body 1 -- skills/worktreereview/scripts/collect.py -- plan share splits from build
- #529 Body 1 -- templates/_builder-brief-template.md -- a helper report shows its red run
- #530 Body 1 -- skills/worktreereview/scripts/collect.py -- a reviewer tool gap is recorded
- #531 Body 1 -- hooks/read-record.sh -- an empty Read counts for nothing

## Done

- #522 Done: a user reads a unit's worktree report after waiting on a `plan-<unit>` decision whose source omits the unit -- the wait is cut from the build clock with the decision as its reason
- #524 Done: a plan author writes a plan whose steps or cuts parse input with no bad-input rows -- plan-check refuses it and names each missing absent, junk, empty or quoted case
- #525 Done: a Builder starts the closing pass while an owner question on the unit is open -- the pass is refused and names the question to ask first
- #526 Done: a Builder starts the closing pass with a red changed test and main unmoved -- the pass stops before any reviewer and names the red test
- #527 Done: main launches a small fix estimated under 50 changed lines -- the plan is written with no judge round, and the docs say what was given up
- #528 Done: a user reads the worktree report of a unit planned and built in one stage -- a Plan and judge stage shows planning's share apart from the build
- #529 Done: a Builder reads a helper's report before taking its code -- the report quotes the helper's failing run
- #530 Done: a user reads the worktree report of a pass whose reviewer said its symbol search was unavailable -- a note under that pass says so
- #531 Done: an agent reads past the end of a contract file and edits its paired file -- the edit is refused, naming the contract to read

## Progress notes

- One line per issue in the evidence file: `#N: built` or `#N: partial -- <what is left>`.
- #506: partial -- the fence and the CPU bound are built; dashboard-live's wall-clock windows and the 3 unexplained 600 s runs are left.
- #513: partial -- the owner's verdicts (Left for the owner).
- #523: not built, measured false; main closes it with the comment under Merge.

## Verification

- Each Acceptance test green; `bash scripts/run-shell-tests.sh --changed main` green during the build; the full shell tests green before any push.
- `claude plugin validate .` and `claude plugin test .` pass; `bash ci/leak-test.sh` and `bash ci/version-check.sh` pass.
- A3, A6 and A7 run and their outcomes written in Progress notes.
- `plan-check.sh` passes this plan; every Break line has its red run.
- Review passes until the unit converges; the closing pass ends `VERDICT: GO` naming no finding.

## Routing

- Builder: this pane's model. Helpers: Sonnet `general-purpose` for reading code, test triage and mechanical edits; Haiku `Explore` for search. Name the model on every call; the Builder brief carries this line.
- Tests run on the PC; A3 in a live seat. Red runs only for the Break lines.
- Main adds each Test edits line before the pass that carries it.

## Test edits

- Test edit: hooks/__tests__/companion-read-guard.test.sh:30 (readx gains `file.content`) -- owner approved test edits that follow the intended change, 2026-10-31
- Test edit: scripts/__tests__/builder-codex-pass-decisions.test.sh:28-33 (C8's added pass and answered row) -- owner approved test edits that follow the intended change, 2026-10-31
- Test edit: scripts/__tests__/builder-codex-pass-threshold.test.sh:74-85 (q-oc-open answered) -- owner approved test edits that follow the intended change, 2026-10-31
- Test edit: scripts/__tests__/builder-codex-pass-rebase.test.sh:56, and :93-96 if C7's timing asks -- owner approved test edits that follow the intended change, 2026-10-31
- Test edit: the judge swap's renames in plugin, seat-launch, seat-launch-github, seat-run-refused, doctor, codex-ask, plan-tier, unit-drive, builder-launch-resume-from-plan tests, and merge-rules.test.sh:58's 895a7e56 pair removed, by main's ruling, round 3, item 12 (A7) -- owner approved test edits that follow the intended change, 2026-10-31

## Question for the owner

- None open: Q1-Q6 answered 2026-10-31 (Owner's additions).

## User-visible changes

- plan-check: a plan whose steps or cuts parse input with no bad-input rows is refused and told which of absent, junk, empty or quoted to list, or to write `Bad input: none, <reason>`.
- worktree report: a wait on a `plan-<unit>` or review-stop decision is cut from build time; a `Plan and judge` stage, then `Build`; a note under a pass whose reviewer lacked symbol search.
- closing pass: a red changed test stops it with main unmoved: `before the closing pass, tests that cover what <unit> changed are red`; an open owner question refuses it, naming each id and the command to ask main.
- merge and the pass hand-off: an open `plan-<unit>` or review-stop question now holds the merge, as one naming the unit did.
- plan tier: a tiny batch prints `tier: One planner` with its estimate and the limit.
- batch template :18: before, `Estimated size:` only cut a risky unit's judges from two to one; after, it also says that under 50 with no risky trigger the plan has no judge. main-session.md's tier lines say the same.
- read recorder: a Read that showed no text no longer opens a paired edit.
- shell test runner: a test's temp folder no longer marks every later file unrecorded; a file past its cap on a busy machine passes if its CPU stayed under the cap, else fails naming wall and CPU seconds.
- plan judges: the second judge is the Opus judge; its settings are `planJudgeOpus*`, a stored `planJudgeFable*` answer is no longer read, and the release notes tell users to rename it.

## Left for the owner

- #513: the guard review proposes keep for 37 hooks from code alone, narrow for bash-guardrails.sh and builder-search-guard.sh, and calls its evidence test traffic. Recommended: rerun it from a project that installs the plugin, then rule on each.
- main-edit-guard.test.sh:22 and :44 make a temp checkout in the real root; C10 makes it harmless to the runner. Moving it out is an existing-test edit for a later unit.

## Facts

- A decision is the unit's only when source or answer names it -- skills/worktreereview/scripts/collect.py:302-339 (observed: 2026-10-31)
- Codex records on both paths; runs and numbered passes; stages; Claude pass -- skills/worktreereview/scripts/collect.py:662-698, skills/worktreereview/scripts/collect.py:700-713, skills/worktreereview/scripts/collect.py:683-686 (observed: 2026-10-31)
- Readers, fold, keys, pass rows -- skills/worktreereview/scripts/collect.py:142, skills/worktreereview/scripts/collect.py:350, skills/worktreereview/scripts/collect.py:421, skills/worktreereview/scripts/collect.py:1022, skills/worktreereview/scripts/render.py:200-210 (observed: 2026-10-31)
- Read recorded on any existing file; test Read has no file object -- hooks/read-record.sh:12-32, hooks/__tests__/companion-read-guard.test.sh:30 (observed: 2026-10-31)
- holds matches the unit as a whole word; three callers -- scripts/decision.sh:276-286, scripts/merge-unit-local.sh:263-267, scripts/main-watch.sh:289, scripts/builder-codex-pass.sh:1943 (observed: 2026-10-31)
- Plugin decision ids -- templates/main-session.md:24, scripts/builder-codex-pass.sh:492, scripts/orca-wait.sh:349 (observed: 2026-10-31)
- New tests block, then Done block; spec rule -- scripts/plan-check.sh:457-472, scripts/seat.sh:501 (observed: 2026-10-31)
- Helper rules; template test -- templates/_builder-brief-template.md:75-83, scripts/__tests__/brief-template.test.sh:13-15 (observed: 2026-10-31)
- Closing pass returns before tests on an unmoved main -- scripts/builder-codex-pass.sh:1733-1771 (observed: 2026-10-31)
- Pinned r5, timed fin 12 -- scripts/__tests__/builder-codex-pass-rebase.test.sh:53-56, scripts/__tests__/builder-codex-pass-rebase.test.sh:93-96 (observed: 2026-10-31)
- Closing passes with open or unreadable questions, pinned -- scripts/__tests__/builder-codex-pass-decisions.test.sh:25-44, scripts/__tests__/builder-codex-pass-threshold.test.sh:74-85 (observed: 2026-10-31)
- Merge plugin checks; post-fix checks -- scripts/merge-unit-local.sh:664-674, scripts/post-fix-checks.sh:1-4 (observed: 2026-10-31)
- Tiers; seats; launcher verdict -- scripts/plan-tier.sh:20-62, scripts/builder-launch.sh:160-198 (observed: 2026-10-31)
- Fence, stamp, ledger write, trap, run_one -- scripts/run-shell-tests.sh:110-144, scripts/run-shell-tests.sh:238, scripts/run-shell-tests.sh:255, scripts/run-shell-tests.sh:275-304 (observed: 2026-10-31)
- Fence orderings pinned -- scripts/__tests__/run-shell-tests.test.sh:243-288 (observed: 2026-10-31)
- Temp checkout in the root -- hooks/__tests__/main-edit-guard.test.sh:17-22 (observed: 2026-10-31)
- Claude models are aliases; keys follow role names -- scripts/paths.sh:749-751, scripts/paths.sh:1101 (observed: 2026-10-31)
- Seat tag in a seat's first message; a Codex pointer -- scripts/seat.sh:526-527, scripts/dispatch-task.sh:63-65 (observed: 2026-10-31)
- Codex window; runs priced and busy -- skills/worktreereview/scripts/collect.py:664-668, skills/worktreereview/scripts/collect.py:780, skills/worktreereview/scripts/collect.py:835 (observed: 2026-10-31)
- Reworded-rule key; its pinned pair -- scripts/merge-rules.py:181, scripts/__tests__/merge-rules.test.sh:58 (observed: 2026-10-31)
- Judge keys and role -- .claude-plugin/plugin.json:128, .claude-plugin/plugin.json:157-179, config/recommended.json:24-27, scripts/codex-helpers.sh:51-55 (observed: 2026-10-31)

## Main ruling, round 3

Source: main's ruling, copied; judge names and the owner's ruling id replaced (public repo).
- Scope: round 3 was the last judge round (owner order). Apply every ruling, copy it here, add a change-log row, stop. The Builder starts from the revised plan.
- Accepted 1: Codex classifier, collect.py:350 (C3/D6), both judges P2. Scan user messages in order until the first one carrying a seat tag or a spec name; that one decides. The C3 fixture for "a Codex plan judge found by its seat tag is planning" starts with an untagged `# AGENTS.md instructions` user message before the tagged pointer.
- Accepted 2: plan lint, plan-check.sh:468 (C5/D2), second judge P1. Read `## Steps` and `## Cuts`, as the host does. Gate-only plans opt out with `Bad input: none, <reason>`. plugin-open-2026-10-31.md is a failing-input case: with C5 it must ask for bad-input rows.
- Accepted 3: tiny route, plan-tier.sh:33-48 (C9/D5), second judge P2. The tiny rule applies only when no panel or risk trigger matched, decided before the :37-40 under-150 downgrade. A security item never goes to `One planner`; "fix the auth check, ~30 changed lines" stays `Plan + judge` or above. Correct "A Panel trigger keeps both judges under tinyPlanLines".
- Accepted 4: template input (C9), second judge P2. templates/_batch-brief-template.md:18 and the matching main-session.md lines join C9 so `Estimated size:` feeds the tiny route; changed user wording goes under User-visible changes as before and after.
- Accepted 5: A7, both judges P3. hooks/__tests__/agent-startup-context.test.sh exists; :58-63 exercise stored rule choices. Correct A7 and name that test as the check.

## Main ruling, round 3, items 6-12

- Accepted 6: unit-drive.sh:10 (second judge P3) joins C12. Done when `rg -n Fable scripts/unit-drive.sh` prints nothing.
- Accepted 7: run-shell-tests.sh:275 (C10/D10), second judge P3. The test's stamp and tick first, then the untracked-list check.
- Accepted 8: collect.py:664 (C3), second judge P3. "The run's day" is the day of the run's last record.
- Accepted 9: #523 figure (Stated limits), second judge P3. The comment main posts carries the exact command (regex and session list) and reports what it prints. The second judge measured 14% tests / 31% file prints over 11 sessions; the conclusion (test runs do not lead) holds either way.
- Accepted 10: #492 wording (Merge), second judge P3. The own-lane second call exists (builder-codex-pass.sh:1758, run-shell-tests.sh:230); what is missing is any test file with an own-lane header.
- Accepted 11: Builder guess points (second judge). C8: the refusal makes its own `decision.sh holds` call (holds() at :1943, after precheck); cite :1664, not :1673. C11: parse `times` output with minutes (`0m1.690s`); an `ok` line past its cap also gets the "past its cap" text.
- Rejected 12: the merge-rules.py:181 key move 895a7e56 to 6d145326 (both judges P2). The owner, 2026-10-31: no compatibility. Keep the plain rename. A stored "keep mine" choice under 895a7e56 stops applying after this change, by owner decision; no ancestry pair, no test for the old id.

## Plan change log

- 2026-10-31: first version.
- 2026-10-31: plan-check's caps moved the owner ask to short questions; background under Decisions, Stated limits, User-visible changes, Left for the owner.
- 2026-10-31 r2, owner answers Q1-Q5 binding; Q4 is (b): C11 added, no new configured value, about 75 lines. Judge swap ordered: C12, about 75 lines.
- 2026-10-31 r2, both judges' findings, all accepted:
  - C10 kept a stale pass when an entry was made and removed during a test (first judge P1); now judged per test (D10); the second judge's "not looser" P3 closes with it, residual in F4.
  - C4 crashed on a Claude reviewer's pass: false set there (P2).
  - D1 gave `review-stop-<unit>-b-r7` and `<unit>-aa-...` to `<unit>` (P2): exact shapes only, F1.
  - C8 missed `plan-<unit>` through holds (both judges, P2): holds takes D1's rule in this unit.
  - C8's test edits were short of :37-44 and threshold :85 (first judge P2; second judge P1): transitions named under C8.
  - C3 read `~/.codex-review`, which nothing writes, and missed Codex Builders (both, P2): planning read from records already read, both paths.
  - D9's no-file branch kept a read with no text (first judge P2; second judge P3): removed; the test helper gains the real shape.
  - #506 evidence overstated (first judge P3): 8 passed uncapped, not 9; dashboard-live is a wall-clock failure; 3 runs unexplained.
  - D2 read the whole Cuts (second judge P3): Steps only, said as deliberate. D3's guard claim (P3): post-fix-checks.sh named. C7's fin 12 window (P3): timed, clock moves if needed. #523's comment names its lead (P3).
  - The second judge's guess points answered in D2, D3, D4, D5 and D10.
- 2026-10-31 main: an unreadable ledger lets the closing pass run and say so; only an open owner question refuses. decisions.test.sh:39-44 stay unedited; the unreadable-ledger case is dropped (23 new cases).
- 2026-10-31 r3, owner: Q6 (a), the 4x ceiling, now in D11; C11 no longer waits. The settings rename is clean, and the release notes, written after all plugin merges, tell users to rename a stored setting (Merge, Data design).
- 2026-10-31 r3, both judges' findings, all accepted:
  - C3 missed Codex planning seats, whose first message is a pointer (first judge P2): the seat tag names the role, the spec name is the fallback.
  - "Planning records leave runs" dropped their spend (both judges P2): they stay in runs and only make no stage of their own.
  - C3's Codex window ended at the last Claude session (first judge P2): it spans both clients.
  - C8's pass 17 came before the rows it reads (first judge P2): it now comes after :28.
  - D11 never said how load/cores rounds, and bash floors it (second judge P2): a decimal, rounded up to a whole second.
  - Second judge's P3s: the HUNG text (D11); plugin.json:128 and README.md:392 (C12); A7 settled by reading; D1's text fields stated; tick() takes its stamp (D10).
- 2026-10-31 main's ruling, round 3 (no judge round follows): items 1-11 applied (D2 reads Steps and Cuts, its Cuts-alone case replaced by the last unit's plan; D5 keyed on the trigger pick, a 30-line auth fix case; D6 scans to the first tagged message; C3's day; D10's order; C8's holds call at :1664; C11's `times` parse; C9's template line; C12's unit-drive.sh; A7's check; #523's command; #492's wording). Item 12 rejected: plain rename, a stored keep-mine under 895a7e56 stops applying. New tests 35.
- 2026-10-31 fix round 1 (pass 1 P1, data-design): the five-field `$RES/<k>.rc` record is declared, with its writer, readers, cleanup and no retry; the same class turned up `$RES/<k>.cpu.tmp`, `$STAMP.tick<pid>` and the `planning` pass kind, declared too. No code change.
- 2026-10-31 fix round 3 (pass 3 P2, cache-fence, not in the plan list): D10's per-test fence also reads the folders no kept path names (untracked trees, empty ones included); a What can go wrong row and its test. No new state: the listing is read in memory when the record is written.

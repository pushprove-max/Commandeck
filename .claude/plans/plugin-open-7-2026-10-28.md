# plugin-open-7-2026-10-28 -- seven open plugin issues in one unit

Owner's words: "all of those need to be built now; don't wait on the twins"
Goal: Close #429 #430 #433 #434 #435 #436 #439 in one unit: guard fixes, a review base, a new-test cap, template lines, a prune audit mode and a smaller suite.
Plan: .claude/plans/plugin-open-7-2026-10-28.md
Tier: Standard; LOCAL merge only; changed-file tests only; no test-timeout raises.
Build order: C1, C2, C7, C3, C4, C5, C6, C8.
- Planned size: 31 files, 1490 changed lines
Timed checks: run-shell-tests.test.sh `timeout 30` runner calls (:24, :86-139); builder-codex-pass.test.sh STUB_SLEEP and sleep cases (:95-100, :186). New cases go after them, at the end of each file.

## Why

The seven issues are what is open on the plugin and the order is to build all of them now, as one unit, without waiting for any host twin. For six issues no host fix is merged (keyword log search, 2026-10-28; the host's new-test cap branch is not merged), so each is built from its issue text and each issue's failing case is its test. For #436 the host's suite cleanup 782556eb is merged; of its 16 deleted cases one has a plugin twin, and that deletion is ported with the same keepers. Two issues meet facts that change their shape. #429's failing input already passes here: the plugin's guard only blocks a rerun on an unchanged tree, so #429 lands as regression tests. #436's never-weaken rule allows few deletions: no test tests retired tooling, so beyond the ported case it lands as an inventory, a per-file size cap, two file splits and a header trim, with before and after numbers.

## Prior art

- Standard: the plugin's own test rules (templates/test-rules.md): never weaken; every deletion names its keeper.
- #430 review base: copies the review-cap pattern, a main-owned per-unit file in main's briefs folder.
- #433 cap: copies the smallBuild review-loop key (pp_review_loop, setup flag, docs line); no library counts test cases in a shell suite, so a 70-line counter is built.
- #433 test discovery: the skip/only hook's path conventions, moved into one shared lib (none exists today).
- #435: extends the shipped /test-audit workflow, whose agents already run in fresh contexts; no new skill.
- Host: suite cleanup 782556eb (merged) is ported for #436 (one case, D10); no merged fix exists for the other six issues.

## Data design

- Review base: `<main>/.claude/briefs/<unit>-review-base.md`, one line, a 40-hex sha. Written by `builder-launch.sh --review-base <sha>` only; read by builder-codex-pass.sh (each whole-branch pass, build_size, the handoff test list, --verify). Never reset: unit names are unique. A retry of the launch rewrites it with the same value. Absent: every range stays `main...HEAD`, as today.
- New-test cap: `.claude/commandeck.json` `.reviewLoop.newTestCap`, a whole number or `off`, default 40 (the owner's number). Written by `setup.sh --new-test-cap`; read by builder-codex-pass.sh before every pass. A bad value refuses the pass with the reader's message (pp_review_loop).
- Shell test line cap: env `COMMANDECK_SHELL_TEST_MAX_LINES`, default 500 per test file (the owner's answer), read by run-shell-tests.sh per run; no state kept.
- No other state is added or changed.

## Decisions already made

- D1 #429: no full-run block is added to the plugin guard; it blocks only a same-tree rerun, and the issue's failing input exits 0 here. The issue's two cases become tests.
  Test: suite-rerun-guard.test.sh -- both #429 labels (C1)
- D2 #439: a runner alias is a name bound by `const|let|var <name> = ...` whose right side names it, test, describe or context, or by `import { it as <name> }`. Aliases are read from the resulting text: a Write's content; for an Edit or MultiEdit, the file on disk with each old_string replaced by its new_string in order (replace_all honoured; a relative path resolves against the payload's cwd; a missing file is the new text alone). A disk declaration the edit removes no longer counts. `<name>.only|skip(` in the new text then blocks as the literal forms do. No generic `<any>.skip(` match.
  Test: test-skip-only-blocker.test.sh -- the five #439 labels (C2)
- D3 #430: the review base lives in main's briefs folder, where the Builder never edits; `--review-base` refuses a sha that is not a commit on main.
  Test: builder-launch.test.sh -- both #430 labels (C3)
- D4 #430: with a base, the whole-branch head lines name `<sha>...HEAD` in place of `main...HEAD`; with none their text is unchanged, so passes already recorded still prove. session_proof and pass_threads match both forms; the proof's range field for a whole-branch pass is `whole` (main) or `base:<sha>`.
  Test: builder-codex-pass.test.sh -- "a closing pass with a review base reads base...HEAD, work already on main included (issue 430)"
- D5 #430: an adversarial, final or design pass whose range has no diff refuses before any reviewer starts.
  Test: builder-codex-pass.test.sh -- "a whole-branch pass whose range is empty refuses and starts no pass (issue 430)"
- D6 #430: --verify refuses a GO from a whole-branch thread whose recorded range does not start at the unit's base (main when no file).
  Test: builder-codex-pass.test.sh -- "--verify refuses a closing GO whose range does not start at the unit's review base (issue 430)"
- D6b #430: with closingPass=no, --verify also binds the first-pass anchor (C_TID, read at :793), whatever its verdict, NO-GO included: its recorded range must start at the unit's base, else refuse and name the adversarial pass to run. Coverage after the anchor's tip alone never proves X..Y was read.
  Test: builder-codex-pass.test.sh -- "with no closing pass, --verify refuses when the first pass read main...HEAD and not the unit's review base (issue 430)"
- D7 #433: the cap is review-loop key newTestCap (smallBuild pattern), default 40, `off` allowed; not a /config option.
  Test: builder-codex-pass.test.sh -- "a pass over the new-test cap refuses with the count (issue 433)"
- D8 #433: scripts/new-test-count.sh finds test files with `is_test_path` from new hooks/lib/test-path.sh, the skip/only hook's own conventions (`*.test.*|*.spec.*|*__tests__*|*/e2e/*`) moved there; the hook sources the same function. It counts net-new labels over the unit's own change (`merge-base main`..HEAD), never the review base: `check "<label>"` in shell files, `it(`/`test(` with a string label in JS/TS files; a label also on a removed line is moved, not new.
  Test: new-test-count.test.sh -- the five #433 labels (C4)
- D9 #435: prune is a third /test-audit mode with subtraction-only rules. In prune mode batch agents also return `proposals` ({id, proposal, otherTest}); validator `ID:` blocks are parsed for their ID, Proposal and Other test fields. A proposal is kept only when its id matches its source's pattern (batch `^B\d{3}-[A-Za-z0-9]+-\d+$`; validator block `^V\d{3}-(CR|TC|T2)-\d+$`, the form the shared Validator section prescribes, so the validator brief stays one text for all modes and the prefix names the stage), its proposal is `remove` or `merge`, and its otherTest is `<path>:<name>` with a plain path (safePath) and a name of 1-120 characters holding no `|`, backtick or line break.
  Test: test-audit.test.mjs -- the seven #435 tests (C6)
- D9b #435: in prune mode the result publishes no agent-written text. result.report is built by the script alone: a fixed heading, `Kept: <n> of <m> proposals`, the table `| ID | Proposal | Other test |` (one row per kept proposal, batch and validator, from the validated fields), and `Dropped:` lines `<id> | <fixed reason>` (an id that fails its source's pattern prints as `(no valid id)`). The report agent's reply feeds only the Counts check. result.selfCheck is fixed text. In result.validator, the validator findings are the same rows; coverage, split-gap and agent notChecked detail lines become one count line each; a count prints only when it is a whole number. The set-up and file-list stop lines (:198, :212) print fixed text in place of the agent's stop reply. result.notAudited: a path rejected at :143 (not safePath or not in scope) prints as `(withheld)`, its reason unchanged. Sweep of every other returned field (:263-273, :467-476): out passes the OUT name form (:196-197); capped, split, batches and validators hold packed entries, ids or numbers; the counts are integers.
  Test: test-audit.test.mjs -- "prune mode publishes no agent text (issue 435)"; "prune mode stops with no agent text (issue 435)" (C6)
- D10 #436: one deletion, ported from the host's merged cleanup 782556eb: "a Playwright spec under e2e blocks" (test-skip-only-blocker.test.sh:22); keepers "a .spec file blocks" (:21, same `.spec` path rule) and "a test outside a __tests__ dir blocks" (:23, same `$SKIP` form). Its other 15 deleted cases have no plugin twin (label grep, 2026-10-28). No test exercises retired tooling; the inventory goes in evidence.
  Test: the keepers at :21 and :23 stay green after the deletion
- D11 #436: the cap is per shell test file, 500 lines (the owner's answer); the runner fails an over-cap file with the cap named.
  Test: run-shell-tests.test.sh -- both #436 labels (C7)
- D12 #436: dashboard-serve.test.sh splits in three by section, each case moved whole; new-test-file-guard.test.sh's 38-line header is condensed, no case touched.
  Test: the three dashboard-serve files' ok total equals the count before the split (evidence line `Split: 91 ok before, 91 ok after`)

## Accepted failure modes

- A1 #439: an alias made in another module, or a wrapper function around it(), still slips the skip/only guard.
  Test: none, resolving names across files needs a parser; the issue's failing input is caught
- A2 #433: checks made in a loop or through a helper count as one or none.
  Test: none, the counter is a review gate on labels, not a proof of count

## Stated limits

(every reviewer is handed these; a finding beyond one is out of scope: a follow-up issue, never a blocker)
- Line cap 500 per file: largest shell test after the split is 476 lines (`git ls-files | grep -E '\.test\.sh$' | xargs wc -l | sort -rn`, 2026-10-28).
- New-test cap 40: the last 12 feat units added 11-263 check/it/test lines, median 36 (`git show <c> | grep -cE` per commit, 2026-10-28).

## Assumptions

- [settled] #429 input passes here: strict-tier payloads `for f in a.test.ts b.test.ts; do npx vitest run "$f"; done`, `npx vitest run "$f"` and `npx vitest run` each exit 0 (`bash hooks/suite-rerun-guard.sh`, 2026-10-28).
- [settled] Baseline: 205 test files, 27,697 lines (`git ls-files | grep -E '\.test\.(sh|ts|tsx|mjs)$' | xargs wc -l | tail -1`, 2026-10-28).
- [settled] No shared test-path definition exists: `grep -nE 'spec|\.test\.' hooks/lib/*.sh` finds three comments and no definition; new-test-file-guard.sh:90 keeps its narrower `.test.ts` rule for its own purpose.
- [likely] The Builder's passes run the installed plugin's pass script, so the C4 gate does not bind this unit. Builder check before C4: `bash scripts/new-test-count.sh main`; if over 40, cut extras to 40 or below, else go on.
- [likely] Readers of the proof's `whole` field are inside builder-codex-pass.sh. Builder check before C3: `grep -n whole scripts/builder-codex-pass.sh`; each reader accepts `base:<sha>`; a reader outside the file is listed in evidence and changed the same way.
- [likely] dashboard-serve sections 14-235 and 505-584 use no variable set in 236-504. Builder check before the C7 split: run each new file alone; if a section fails alone, copy its setup lines into that file's head.

## Question for the owner

- None open: the owner set the new-test cap default to 40 and the 500-line cap per test file.

## Cuts

- C1 #429 (~6 lines): two checks in hooks/__tests__/suite-rerun-guard.test.sh: "a one-file vitest run named by a shell variable in a per-file loop passes (issue 429)", "a one-file vitest run named by a literal path passes (issue 429)".
  Produces: tests only. Consumes: hooks/suite-rerun-guard.sh as is. Consumers changed: none.
- C2 #439 (~45 lines): new hooks/lib/test-path.sh `is_test_path` (the hook's :31-34 test-path case; the hooks/__tests__ self-test exemption stays in the hook); the hook sources it (a load failure blocks, as the edit-payload load does), collects aliases from the resulting text (D2) and adds them to PATTERN's name list; docs/hooks.md:46 says aliases count. Checks: "an aliased runner's .only in the same payload blocks (issue 439)", "an Edit whose alias is declared in the file on disk blocks (issue 439)", "an imported alias (it as nodeIt) .skip blocks (issue 439)", "a .skip on a name that is no runner alias passes (issue 439)", "a Write that rebinds a former alias to ordinary code passes (issue 439)" (disk `const stream = it;`, Write `const stream = getStream(); stream.skip(2);`).
  Produces: is_test_path; wider block. Consumes: hook_new_text, FILE_PATH, the file on disk. Consumers: hooks.json:57 entry, unchanged; C4's counter.
Break: hooks/__tests__/test-skip-only-blocker.test.sh -- an aliased runner's .only in the same payload blocks (issue 439) -- hooks/test-skip-only-blocker.sh alias names in PATTERN ~40
- C7 #436 (~845 lines, ~760 moved): run-shell-tests.sh fails a `*.test.sh` over COMMANDECK_SHELL_TEST_MAX_LINES (500) before it runs, counted in FAIL so the run exits non-zero, `FAIL <file> over the 500-line cap for one shell test file: split it by section`. Split dashboard-serve.test.sh: keeps 1-235 and 505-584; dashboard-serve-answers.test.sh takes 236-504 and 585-752; dashboard-serve-login.test.sh takes 753-861; both new files carry `# covers: scripts/dashboard_serve.py` in their first 5 lines. Condense new-test-file-guard.test.sh:2-39. Delete test-skip-only-blocker.test.sh:22 (D10). docs/tests.md states the cap. Evidence: D10's inventory and deletion with keepers, before/after counts (Assumptions command), split ok counts. Checks: "a shell test file over the line cap fails with the cap named (issue 436)", "a shell test file at the cap runs (issue 436)".
  Catches: a shell test file regrowing past 500 lines with nobody told.
  Produces: runner cap. Consumes: TESTS list. Consumers: CI `bash scripts/run-shell-tests.sh` (ci.yml), --changed, --own-lane.
Break: scripts/__tests__/run-shell-tests.test.sh -- a shell test file over the line cap fails with the cap named (issue 436) -- scripts/run-shell-tests.sh line-cap check
- C3 #430 (~160 lines): builder-launch.sh `--review-base <sha>` (needval; `git merge-base --is-ancestor <sha> main` else refuse; writes the full sha to main's file; header comment line). builder-codex-pass.sh: one `review_base` helper (file or `main`); RANGE, HEAD_FULL/FINAL/DESIGN text, build_size and the :1929 list use it; empty-range refusal (D5); session_proof, pass_threads and --verify per D4/D6; the anchor check (D6b) beside :793. docs/review-loop.md:5-24 names the base. Checks in a new scripts/__tests__/builder-launch.test.sh (sources fixtures/builder-launch-resume-setup.sh): "--review-base writes main's review-base file with the full sha (issue 430)", "--review-base refuses a commit that is not on main (issue 430)"; in builder-codex-pass.test.sh: the D4, D5, D6, D6b labels.
  Catches: ancestor check: a mistyped or unmerged sha making every pass diff a wrong range.
  Catches: empty-range refusal: a GO from a pass that read nothing (a review-only unit cut from main).
  Catches: --verify base check: a merge on a GO whose range skipped the work the unit was asked to re-review.
  Catches: anchor check: with closingPass=no, X..Y never read while narrowed passes cover only commits after the anchor.
  Produces: review-base file; head line form; proof field `base:<sha>`. Consumes: main's briefs folder. Consumers: merge-unit-local.sh:350 (--verify caller, unchanged), rebase_and_test (the base stays an ancestor of main).
Break: scripts/__tests__/builder-launch.test.sh -- --review-base refuses a commit that is not on main (issue 430) -- scripts/builder-launch.sh ancestor check
Break: scripts/__tests__/builder-codex-pass.test.sh -- a whole-branch pass whose range is empty refuses and starts no pass (issue 430) -- scripts/builder-codex-pass.sh empty-range refusal ~1490
Break: scripts/__tests__/builder-codex-pass.test.sh -- --verify refuses a closing GO whose range does not start at the unit's review base (issue 430) -- scripts/builder-codex-pass.sh --verify base check
Break: scripts/__tests__/builder-codex-pass.test.sh -- with no closing pass, --verify refuses when the first pass read main...HEAD and not the unit's review base (issue 430) -- scripts/builder-codex-pass.sh anchor range check ~793
- C4 #433 (~155 lines): new scripts/new-test-count.sh `<base>` (sources hooks/lib/test-path.sh) prints `<n>` then the new labels; builder-codex-pass.sh reads `pp_review_loop newTestCap 40 '^(off|[1-9][0-9]*)$'` beside :469 and refuses at the pre-pass block: `the change adds <n> new tests, over the new-test cap of <cap> (reviewLoop.newTestCap)` with up to 10 labels. setup.sh `--new-test-cap`; docs/configuration.md:96-101 names the key and default 40. Template line after :115: each new test names the bug it catches; tests past that are listed as extras under `## Extra tests` in the evidence. Checks in new-test-count.test.sh: "a shell test file's added check lines count as new tests (issue 433)", "a check moved with the same label is not new (issue 433)", "an it( or test( case added to a .test.ts file counts (issue 433)", "tests already on main before a review base are not counted (issue 433)", "31 test( cases added to src/a.spec.ts count 31 (issue 433)"; builder-codex-pass.test.sh: the D7 label; brief-template.test.sh: "the Builder template asks each new test to name its bug and lists extras (issue 433)".
  Catches: a change adding more tests than the cap reaching review with no count named.
  Produces: counter output `<n>` + labels; cap refusal. Consumes: C2's is_test_path; nothing from C3 (D8). Consumers: none outside the pass script.
Break: scripts/__tests__/builder-codex-pass.test.sh -- a pass over the new-test cap refuses with the count (issue 433) -- scripts/builder-codex-pass.sh new-test cap refusal
- C5 #434 (~15 lines): template guidance after the C4 line: arrange data with one shared builder per domain object (a fixture function in shell tests), one or two lines per test; extend the builder, never hand-build; a short fenced example. Check: "the Builder template makes a shared builder the default for test data, with an example (issue 434)".
  Produces: template text. Consumes: none. Consumers: builder-launch.sh brief render, unchanged.
- C6 #435 (~240 lines): test-audit.js takes `prune` (mode parse, schema enum, USAGE, meta); the prune batch schema (:246) adds `proposals`; D9 checks batch proposals and validator `ID:` blocks (:381); D9b builds every prune result text (:142, :198, :212, :296-298, :400-466, :474). prompt.md `## Prune mode`: delete or merge only, `Other test: <path>:<name>` required, never add, validator ids keep the V form; the field joins Finding format. run() (:16-30) takes a reply per stage label. Fixture scripts/__tests__/fixtures/test-audit-prune/ (two small test files, one duplicate case). docs/commands.md:27-35, README.md:140 name prune. K = `{id:"B001-T2-1", proposal:"remove", otherTest:"src/b.test.ts:keeper"}`; S = `add a new regression test`. Tests: the C6 Break: labels, and 'prune mode on a fixture folder sends subtraction-only instructions to every batch agent (issue 435)', 'prune mode publishes a kept finding's validated proposal, never the report row's own text (issue 435)' (batch [K], report row `| B001-T2-1 | S1 | Proposal: add await | unknown | low | high |`; report lacks `add await`, holds `| B001-T2-1 | remove | src/b.test.ts:keeper |`), 'prune mode publishes no agent text (issue 435)' (batch [K, B001-T2-2 merge `src/b.test.ts:k | S`]; report `| B001-T2-1 | S1 | duplicate | unknown | low | high |` then `Proposal: S in src/a.test.ts`; S in selfCheck, a validator Residual protection field, notChecked, extra, gaps; phase 1 `{stop:"",count:2,files:[{path:"src/a.test.ts",lines:1,bytes:1},{path:"Proposal: add a new regression test in src/a.test.ts",lines:1,bytes:1}]}`; `JSON.stringify(result)` lacks S; report keeps K's row only; notAudited path `(withheld)`), 'prune mode stops with no agent text (issue 435)' (phase 0, then phase 1 stop replies hold S; no result does), 'prune mode keeps a validator proposal with a V id (issue 435)' (validator findings `"ID: V001-T2-1\nProposal: remove\nOther test: src/b.test.ts:keeper"`; report holds its row and `Kept: 1 of 1 proposals`).
  Produces: mode `prune`; result field `dropped`; prune text per D9b; `(withheld)` notAudited paths. Consumes: the fixture file list; batch `proposals`; validator `ID:` blocks. Consumers, unchanged: install-lib.sh il_test_audit; Counts check (:430, raw reply); test-audit.test.mjs:35; basic and full output; notAudited readers :219, :256, :400, :451.
Break: scripts/__tests__/test-audit.test.mjs -- prune mode drops a validator finding that names no other test or proposes an addition (issue 435) -- templates/test-audit.js prune drop filter
Break: scripts/__tests__/test-audit.test.mjs -- prune mode drops a batch finding with Proposal add await and no Other test from the report and the count (issue 435) -- templates/test-audit.js prune report built by the script ~296
Break: scripts/__tests__/test-audit.test.mjs -- prune mode publishes a kept finding's validated proposal, never the report row's own text (issue 435) -- templates/test-audit.js prune table rows from validated fields ~296
Break: scripts/__tests__/test-audit.test.mjs -- prune mode publishes no agent text (issue 435) -- templates/test-audit.js agent report text unused ~296
Break: scripts/__tests__/test-audit.test.mjs -- prune mode publishes no agent text (issue 435) -- templates/test-audit.js fixed selfCheck ~474, withheld validator detail ~449
Break: scripts/__tests__/test-audit.test.mjs -- prune mode stops with no agent text (issue 435) -- templates/test-audit.js prune stop lines ~198, ~212
Break: scripts/__tests__/test-audit.test.mjs -- prune mode publishes no agent text (issue 435) -- templates/test-audit.js otherTest form check (no `|`), withheld notAudited path ~142
- C8 (~3 lines): plugin.json version: next free minor at merge (`bash ci/version-check.sh` decides). No CHANGELOG or README release text.

## Steps

- modify hooks/__tests__/suite-rerun-guard.test.sh -- #429 checks
- new hooks/lib/test-path.sh -- is_test_path
- modify hooks/test-skip-only-blocker.sh ~30-40 -- lib, aliases
- modify hooks/__tests__/test-skip-only-blocker.test.sh -- #439, :22
- modify docs/hooks.md ~46 -- alias row
- modify scripts/run-shell-tests.sh ~306 -- line cap
- modify scripts/__tests__/run-shell-tests.test.sh -- cap checks
- modify scripts/__tests__/dashboard-serve.test.sh -- keep 1-235, 505-584
- new scripts/__tests__/dashboard-serve-answers.test.sh -- moved cases
- new scripts/__tests__/dashboard-serve-login.test.sh -- moved cases
- modify hooks/__tests__/new-test-file-guard.test.sh ~2-39 -- header
- modify docs/tests.md -- cap
- modify scripts/builder-launch.sh ~54-70 -- --review-base
- new scripts/__tests__/builder-launch.test.sh -- #430 launch
- modify scripts/builder-codex-pass.sh ~1490 -- base, gates
- modify scripts/__tests__/builder-codex-pass.test.sh -- #430 #433
- modify docs/review-loop.md ~5-24 -- base
- new scripts/new-test-count.sh -- counter
- new scripts/__tests__/new-test-count.test.sh -- counter checks
- modify scripts/setup.sh ~371 -- --new-test-cap
- modify docs/configuration.md ~96 -- newTestCap
- modify templates/_builder-brief-template.md ~115 -- #433 #434
- modify scripts/__tests__/brief-template.test.sh -- pins
- modify templates/test-audit.js ~62 -- prune
- modify templates/test-audit-prompt.md ~14 -- prune rules
- modify scripts/__tests__/test-audit.test.mjs -- prune tests
- new scripts/__tests__/fixtures/test-audit-prune/ -- fixture
- modify docs/commands.md ~27 -- prune
- modify README.md ~140 -- prune
- modify .claude-plugin/plugin.json ~3 -- version

## What can go wrong

| Case | Input or starting state | Expected | Test |
|---|---|---|---|
| Empty range | whole-branch pass, branch has no commits past its base | refusal, no reviewer starts | builder-codex-pass.test.sh: a whole-branch pass whose range is empty refuses and starts no pass (issue 430) |
| Main moved | base X; main holds X..Y; closing pass rebases onto main | diff covers X..HEAD | builder-codex-pass.test.sh: a closing pass with a review base reads base...HEAD, work already on main included (issue 430) |
| Alias off-payload | Edit adds `itCompat.only(`; `const itCompat = it` only on disk | block | test-skip-only-blocker.test.sh: an Edit whose alias is declared in the file on disk blocks (issue 439) |
| Moved test | a check removed and re-added with the same label | not counted | new-test-count.test.sh: a check moved with the same label is not new (issue 433) |
| At the cap | a 500-line and a 501-line test file | 500 runs; 501 fails | run-shell-tests.test.sh: a shell test file at the cap runs (issue 436); a shell test file over the line cap fails with the cap named (issue 436) |

## Acceptance test

- Every check label named in Cuts C1-C7, green.
- `bash scripts/run-shell-tests.sh --changed main` green; plus `bash scripts/run-shell-tests.sh scripts/__tests__/dashboard-serve*.test.sh` (moved cases).
- `claude plugin validate .` and `claude plugin test .` pass.
- `bash ci/leak-test.sh` and `bash ci/version-check.sh` pass.

## Claims to falsify

- The plugin guard lets `npx vitest run "$f"` through at HEAD under the strict tier.
- No test in the suite exercises a tool listed in config/retired.tsv.
- Of the host cleanup 782556eb's 16 deleted cases, only "a Playwright spec under e2e blocks" has a plugin twin.
- No shared test-path definition exists in hooks/lib or scripts.
- Only dashboard-serve.test.sh and new-test-file-guard.test.sh are over 500 lines among `*.test.sh`.
- A whole-branch pass at HEAD builds a prompt for an empty `main...HEAD`.
- builder-codex-pass.sh diffs `main...HEAD` only at :1490 and :1929.
- The no-closing-pass chain checks no range for its anchor, only commits after its tip.
- pp_review_loop reads any `.reviewLoop.<key>`, so newTestCap needs no paths.sh change.
- /test-audit publishes the report text with no filter on its findings.
- A report table row that names a kept finding id can carry a proposal its batch never returned.
- The Counts check reads the report agent's raw reply, not the published reportText.
- /test-audit publishes agent text outside the report: selfCheck, validator coverage and notChecked lines, the stop replies.
- A packed path passes safePath, so it holds only `[A-Za-z0-9._/-]` and no space.
- No code outside test-audit.js and its test reads the result's report, selfCheck or validator fields.
- result.notAudited keeps a rejected path verbatim.
- Other returned fields hold only numbers, script text, the form-checked OUT path or packed entries.
- The Validator section prescribes V ids, which a B-only id check drops.

## Verification

- Done when: every named test green; `bash scripts/run-shell-tests.sh --changed main` green; `claude plugin validate .` and `claude plugin test .` pass; `bash ci/leak-test.sh` and `bash ci/version-check.sh` pass; a closing pass ends `VERDICT: GO` with no finding named.
- Tests run on the PC. Red proofs only for the Break: lines, under `## Break runs`.
- Never edit, weaken, skip or delete an existing test to make it pass; a test that looks wrong goes to main as a question.

## Routing

- Helpers: Sonnet `general-purpose` for code reads, test triage and mechanical edits (the C7 split, the header trim); Haiku `Explore` for search; name the model on every call. The Builder brief carries this line.

## Progress notes

- #429: partial -- C1 not built (when green: `#429: built -- the plugin guard never had the full-run block; a regression test pins the allowed per-file run`)
- #430: partial -- C3 not built
- #433: partial -- C4 not built
- #434: partial -- C5 not built
- #435: partial -- C6 not built
- #436: partial -- C7 not built
- #439: partial -- C2 not built
Rule: the Builder sets each line to `#N: built` or `#N: partial -- <what is left>` as its cut ends.
Merge message: `Closes #N` for each built issue, `Refs #N` for each partial one.

## Not in this unit

- #430 "Related": other gates that trust the newest round's GO; a follow-up issue.
- Running the prune audit on this repo's own suite (needs a model run).
- CHANGELOG and README release text: waits until every ordered plugin unit has merged.

## Facts

- Guard's one block is a same-tree rerun -- hooks/suite-rerun-guard.sh:150, hooks/suite-rerun-guard.sh:326 (observed: 2026-10-28)
- Skip/only path rule, runner names; other guard's .test.ts rule -- hooks/test-skip-only-blocker.sh:31-34, hooks/test-skip-only-blocker.sh:40, hooks/new-test-file-guard.sh:90 (observed: 2026-10-28)
- Ported case and its keepers -- hooks/__tests__/test-skip-only-blocker.test.sh:21-23 (observed: 2026-10-28)
- Whole-branch diffs, head lines, handoff list use main...HEAD -- scripts/builder-codex-pass.sh:1489-1492, scripts/builder-codex-pass.sh:172-176, scripts/builder-codex-pass.sh:1929 (observed: 2026-10-28)
- session_proof range `whole`; pass_threads same heads -- scripts/builder-codex-pass.sh:346-347, scripts/builder-codex-pass.sh:388-390, scripts/builder-codex-pass.sh:525-530 (observed: 2026-10-28)
- No-closing-pass anchor: tip only, no range -- scripts/builder-codex-pass.sh:793, scripts/builder-codex-pass.sh:808-815 (observed: 2026-10-28)
- build_size from merge-base main; no empty-diff check -- scripts/builder-codex-pass.sh:484-488, scripts/builder-codex-pass.sh:1494-1502 (observed: 2026-10-28)
- review-cap file pattern -- scripts/review-cap.sh:17-18, scripts/builder-codex-pass.sh:946-949 (observed: 2026-10-28)
- builder-launch.sh option loop -- scripts/builder-launch.sh:54-70 (observed: 2026-10-28)
- Pass 1 needs a run per Break: line -- scripts/builder-codex-pass.sh:1235-1250 (observed: 2026-10-28)
- smallBuild read; pp_review_loop any key; setup flag; doc keys -- scripts/builder-codex-pass.sh:469, scripts/paths.sh:1067-1074, scripts/setup.sh:371, docs/configuration.md:96-101 (observed: 2026-10-28)
- Template evidence lines; never weaken -- templates/_builder-brief-template.md:113-115, templates/test-rules.md:8-11 (observed: 2026-10-28)
- Modes; batch schema; findings sum; report text published -- templates/test-audit.js:62, templates/test-audit.js:246, templates/test-audit.js:260, templates/test-audit.js:296-298 (observed: 2026-10-28)
- Validator count; Counts check reads the raw reply -- templates/test-audit.js:381-382, templates/test-audit.js:430 (observed: 2026-10-28)
- Proposals include additions; id forms B and V; report rows -- templates/test-audit-prompt.md:115, templates/test-audit-prompt.md:109, templates/test-audit-prompt.md:168, templates/test-audit-prompt.md:128-129 (observed: 2026-10-28)
- Audit test fakes agents; reads result.validator -- scripts/__tests__/test-audit.test.mjs:16-30, scripts/__tests__/test-audit.test.mjs:35 (observed: 2026-10-28)
- Stop lines quote the reply; OUT name form check -- templates/test-audit.js:198, templates/test-audit.js:212, templates/test-audit.js:196-197 (observed: 2026-10-28)
- Packed paths pass safePath; a rejected path kept verbatim -- templates/test-audit.js:73, templates/test-audit.js:142-143 (observed: 2026-10-28)
- Validator text quotes agent strings; selfCheck published -- templates/test-audit.js:400-401, templates/test-audit.js:419, templates/test-audit.js:426, templates/test-audit.js:449, templates/test-audit.js:474 (observed: 2026-10-28)
- Result fields; packed-entry filters -- templates/test-audit.js:263-273, templates/test-audit.js:467-476, templates/test-audit.js:262, templates/test-audit.js:383-384 (observed: 2026-10-28)
- notAudited readers -- templates/test-audit.js:219, templates/test-audit.js:256, templates/test-audit.js:451 (observed: 2026-10-28)
- Runner timeout, covers, discovery -- scripts/run-shell-tests.sh:46, scripts/run-shell-tests.sh:159, scripts/run-shell-tests.sh:169 (observed: 2026-10-28)
- Split points -- scripts/__tests__/dashboard-serve.test.sh:242-250, scripts/__tests__/dashboard-serve.test.sh:753-757 (observed: 2026-10-28)
- Retired names -- config/retired.tsv:1-5 (observed: 2026-10-28)
- Docs to update -- docs/commands.md:27-35, README.md:140, docs/hooks.md:46 (observed: 2026-10-28)
- Version 0.58.0 -- .claude-plugin/plugin.json:3 (observed: 2026-10-28)

## Plan change log

- 2026-10-28: first version.
- 2026-10-28: author re-read: the new-test counter counts the unit's own change, not the review base (D8, C4), plus one check for it.
- 2026-10-28: main answered #429: no full-run block in the plugin guard (unordered new behaviour); D1 stands, Q1 removed, the #429 progress note text set.
- 2026-10-28: judge NO-GO answered and owner answers applied: D6b anchor check with closingPass=no (P1); counter discovery from shared is_test_path, `.spec` case (P2); prune filter on batch, report and validator paths (P2); host cleanup 782556eb assessed, its one twin case ported with keepers, false "no host cleanup merged" claim removed (P2); aliases from the resulting text, rebind case (P2); new-test cap 40, line cap per file; Catches: lines on the C3, C4 and C7 gates (P3).

- 2026-10-28: judge round 2 NO-GO answered: an id filter let a kept id publish an addition (P2 #435); D9 and C6 now publish only the validated proposal table, the judge's input is a fourth #435 test with a Break: line, A3 added.
- 2026-10-28: judge round 3 NO-GO answered (P2 #435, A3 let unbound report text publish an addition): A3 dropped; D9b makes every prune-mode result field script text or validated fields (report, selfCheck, validator, stop lines), otherTest form-checked; the judge's input is a fifth #435 test, a sixth covers the stop lines; the report brief no longer names kept ids (its text is unpublished).
- 2026-10-28: judge round 4 NO-GO answered (two P2 #435): D9b withholds rejected notAudited paths after a sweep of every returned field, the fifth test gains the judge's phase-1 input, its Break: line names the withheld path; D9 accepts validator V ids (the shared Validator section's form), a seventh test keeps `V001-T2-1`.

## Author self-check

- Every requirement traces to the owner's words (the seven issues), the plan spec or the owner's two answers.
- No host product name, host path, owner name or ruling id in this file.

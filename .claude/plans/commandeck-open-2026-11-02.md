# commandeck-open-2026-11-02 -- every open plugin issue, and the guard list, in one unit

Owner's words: the owner, 2026-11-01: one unit for every open plugin issue, built and merged before 05:00 ET. One unit, no split, whatever the size caps say. Speed, tokens and friction come first.
Owner's additions: the guard-audit change list of 2026-11-01 (the owner's order): each guard that also exists in the plugin gets the same change; a block that catches nothing goes, a real catch warns or rewrites so the call goes through; a timed-out hook lets the call through; each change gets a test that the false positive passes and a kept catch still holds.
Goal: Turn the plugin's false-positive guard blocks into warnings or rewrites, build the open issues with no unmerged host twin, and leave the rest open with the reason.
Plan: .claude/plans/commandeck-open-2026-11-02.md
Tier: Standard; LOCAL merge only; changed-file tests only; tests run on the PC; no test-timeout raises.
Split override: the owner's order names one unit, no split, whatever the size caps say.
Build order: C1-C10, then C11 (it touches every hook header), then C12-C17 and C19-C34 in any order but C15 before C31-C33, C24 before C27, C13 before C34; C18 last. C27 consumes C24's LENS line, C34 C13's Sol-first order; no other cut waits on another's output.
- Planned size: 141 files, 3805 changed lines
New tests: commandeck-open-2026-11-02 179 -- 159 named cases plus up to 20 host unit-view tests the #555 port carries
Version: 0.68.0 (a minor: new behaviour), unless `bash ci/version-check.sh` at merge time names another free number.
Closes: #513 #532 #533 #535 #537 #538 #539 #540 #541 #542 #544 #545 #546 #547 #548 #549 #550 #551 #552 #553 #559 #564 #565 #566 #567
Refs: #506 #531 #555
Timed checks: none -- no heavy fixture is added; doctor.test.sh:213-224 and seat-plan-marker.test.sh:91 keep their timeouts; new cases go at each file's end, and the seat-launch cases go in a new file, as seat-launch.test.sh:179 says it is near its time cap.

## Merge

- Merge commit message: `Closes` each issue on the Closes: line, then `Refs #506`, `Refs #531`, `Refs #555`.
- An issue whose Progress note reads partial moves from Closes to Refs before the merge.
- #531: A3 green moves it to Closes; red leaves it open with the payload shape in a comment.
- #539, #540: A8 or A9 red moves it to Refs (Progress notes).
- Main closes by hand (D23), with the evidence under Not in this unit: #523, #556, #558, #578.

## Why

Of the 52 open issues, 37 were plugin twins of host issues whose fixes were not on host main; the spec says those wait. By r2, 16 of those host fixes are on host main (the tooling unit and the plan loop), so this unit builds the 9 with no twin, ports those 16 (each its issue's part only), ports the merged host part of #555, and makes the guard list's changes. Five of the 16 are smaller in the plugin than on the host: #540's refusal is already a note, #541's Builder line exists, #542 has no host gap to fill, #551 rides #547's line, and #553 deletes only. The guard list names 19 host guards and four script refusals; 13 have a plugin equivalent. Each block becomes a warning (exit 0 with the text as context) or a rewrite (the corrected command runs), the pattern the plugin's own hooks already use. A real catch the owner kept (a dirty worktree removal, an endless sleep loop, an unbounded cat of saved output) still blocks. The two hooks the list calls slow take 33 ms and 128 ms a call idle, far under their 30 s timeout, so their timeouts come from load and the fix is fail-open, not speed. #535's round cap was lifted by the owner on both sides; only its Sol-before-Opus gate ports.

## Prior art

- Host a5446efad (on host main): #535's Opus gate; its Cap ruling half is superseded by host c4325bb42 and plugin 32ab509.
- Host 4e8531877 (on host main): #555 Part 1 of 3, the unit-view elements the snapshot carries; its decision-ledger `--unit` field is not ported.
- Host rule sections for #544: the host's drift check lists 27 changed sections, read-only run, 2026-11-01.
- Warn shape: pane-budget-gate.sh:170-171 and builder-search-guard.sh:113-115; rewrite shape: bash-guardrails.sh:603-607, no-poll-loops.sh:411-414.
- Standard: templates/test-rules.md. Library: none; jq, bash and Python's `re` are enough.
- Host b4b00efee (on host main): the tooling unit, the fixes for #532, #538-#542, #545-#553's twins; host 0c86f6054 (on host main): #559's plan loop. Each port takes its issue's part; host ledger, metrics and dashboard lines are not ported.

## Data design

- hooks/hooks.json (C5, changed): the 23 `"onFailure": "block"` keys go; timeouts stay. Reader: Claude Code. A hook that times out or crashes is a non-blocking error.
- `$REC.rounds` (C13, restored): one `<tag> <verdict>` line per collected plan-judge round, appended by `seat.sh collect`, read by the Opus gate (distinct tags counted). Lives beside the seat record; removed with it.
- `# Retire when: <condition>` (C11, new): one header line per hooks/*.sh; read by the new guard test and by people.
- `saved` rows from hooks/lib/shell_reads.py (C7, changed, in memory): gain the program and a line bound as tab fields; the hook is the only reader.
- `motion` in plugin.json userConfig (C16, new, default off): read by hooks/units.tsx.
- `maxreview-r<N>-reports.md` (C12, new): written by the skill's loop in the worktree it reviews; read by people.
- No migration: every new key but `mainsha=` is optional; an old `.rounds`-less seat record counts as 0 rounds.
- `mainsha=` in each plan judge's seat record (C28, new): main's commit the judge read, written at launch, read by builder-launch.sh; a record without it is refused and judged again.
- `/tmp/claude-batch-<sid>` (C20, changed): a fourth field `refused`; a three-field file parses as before.
- `$PP_SCRATCH/main-pane.txt` (C19, new): `handle=<pane>`, written by board.sh when it binds, read by main-watch.sh only.
- `.claude/briefs/<unit>-r<N>-causes.txt` (C26, new): one line of sites per shared cause; read by the fix hand-off.
- Cuts (C30): the `- C<n>` bullets under a plan's `## Cuts`, the shape plans already use (this plan; plugin-open-2026-10-31.md:153); a built cut's bullet gains ` -- done` at its end. A `- C<a>-C<b>` bullet is each cut from a to b; a cut on two bullets is one cut, built only by its own `C<n>: built` line (`C<a>-C<b>: built` is not read). Evidence (C30, new): one `C<n>: built` line per finished cut, beside the `#N: built` lines. Read by the merge only.
- `<git-dir>/break-run.bak` and `<git-dir>/break-run.path` (C29, new): the byte copy and its file path while a break runs; removed on restore; a leftover one refuses the next run.
- `$PP_SCRATCH/drive-<unit>.asked` (C34, new): one line `<plan sha256> <epoch>`, the version whose question main was sent and when; written once per version, read by unit-drive.sh as the answer bound; missing, junk or another hash sends again.
- Per-version judge spec `$PP_SCRATCH/drive-<unit>-judge-<tag>.md` and revise spec `.claude/briefs/_<unit>-plan-revise-<tag>.md` (C34, new): written and read by unit-drive.sh.
- hooks/hooks.json (C20, C32, C33): batch-independent-looks.sh joins PreToolUse and UserPromptSubmit, long-reply-stop.sh joins Stop, the checklist-guard.sh entry goes.

## Decisions already made

- D1 G3: the inline-script write block (Builder only) warns: the same text as context, exit 0. The lexer stays, so only a tracked path draws it.
  Test: "an inline tracked-file write runs with a warning"; "a scratch-only inline write draws no warning"
- D2 G4: main's simple search gets the worker's 200-line cap rewrite; any other unbounded search warns with its Try line and runs.
  Test: "main's search of . is rewritten to a 200-line cap"; "a worktree-root search runs with a warning"; "an unrewritable root search runs with a warning"
- D3 G5: past the clear line, `--out=<checkpoint>` passes as `--out <checkpoint>` does; any other call runs with a one-line write-the-checkpoint note.
  Test: "past the line the --out= form passes"; "past the line a call runs with the checkpoint note"
- D4 G6: a lone bare `orchestration check` is rewritten to `bash <plugin>/scripts/orca-wait.sh`, keeping `--run <id>`; a chain, quoted text or junk keeps today's block.
  Test: "a bare inbox check is rewritten to orca-wait.sh"; "a quoted, chained or junk inbox check is never rewritten"
- D5 G8: the unreadable-wait and over-cache-wait blocks warn; the endless loop block stays.
  Test: "a worker's long ask runs with the cache warning"; "an unreadable wait runs with a note"; "an endless sleep loop is still refused"
- D6 G7: `worktree remove --force` passes when `git -C <path> status --porcelain --untracked-files=all` prints nothing; any output, a git failure or a missing path blocks. Merged-branch and merged-list tests are not added: the owner's rule blocks only on uncommitted work, which the status read decides alone.
  Test: "a clean worktree remove --force passes"; "a worktree with uncommitted or untracked work still blocks"
- D7 G9: no refusing hook carries `onFailure: block`; the drift guard is turned to fail any that does. A timed-out hook lets the call through.
  Test: "no refusing hook fails closed"
- D8 G10: a lone `terminal read --terminal <handle>` is rewritten to `bash <plugin>/scripts/read-verdict.sh <handle>`, `<plugin>` as D4's (the hook's `${BASH_SOURCE[0]%/*}/..`); `--lines N` (N 1-500) becomes read-verdict's `[lines]` argument; any other flag, no handle, a `$VAR` handle or a pipe keeps the block.
  Test: "a terminal read with a handle is rewritten to read-verdict.sh"; "a terminal read with --lines 50 is rewritten with 50 as the lines argument"; "a terminal read with no handle, a variable or a pipe still blocks"
- D9 G11: main's picker with no decoy gets the decoy prepended by updatedInput; a question already at 4 options keeps the block. Claude Code runs an event's matching hooks in parallel on the original input, so ask-records-decision.sh (:34-35) records a decoy-less main picker under 4 options itself; a 4-option one stays unrecorded.
  Test: "a picker with no decoy opens with it added"; "a four-option picker with no decoy still blocks"; "a decoy-less picker the guard rewrites is recorded"; "a four-option picker with no decoy is not recorded"
- D10 G13: rg/grep with `-m N` and head/tail with `-n N` (N 1-500) on saved tool output pass; cat, sed and an unbounded or junk bound still block. A1 first.
  Test: "a bounded rg or head on saved output passes"; "an absent, junk or negative bound still blocks"; "cat on saved output still blocks"
- D11 G14: builder-search-guard never blocks: its refusal becomes the hint, the `search-refused` event and the streak count stay.
  Test: "the fourth search of a streak runs with the hint"; "a whole-repo Grep runs with the hint"
- D12 G15: the local-address tripwire skips `*.md`, `*.mdx`, `*.txt`, `docs/`, `*.spec.*`, `test/` and `tests/` paths; app code still blocks.
  Test: "a doc edit naming a local address passes"; "a spec edit naming a local address passes"
- D13 G20: `decision.sh holds` drops a text match on a row whose source is `decision.sh push-ask`; id matches stay.
  Test: "holds ignores an open push question listing the unit"; "holds still lists a unit question from another source"
- D14 #513: each hooks/*.sh carries `# Retire when: <condition>` (12+ characters) in its header, the condition from docs/guard-review-2026-10-31.md, updated for D1-D12. Verdicts are the guard list's.
  Test: "a hook with no Retire when line fails the guard"; "an empty Retire when condition fails the guard"
- D15 #533: skills/maxreview: wording.sh prints the pass script's live angles or closing focus by running in a subshell only the lines between `# wording: begin` and `# wording: end`, two comment lines C12 adds around builder-codex-pass.sh:141-183, after setting `HERE`, `die` and `BLOCK_LEVELS= OPEN= CLOSE=` (set outside the markers at :126-128 and :138; neither wording prints them); its two print cases run under `env -u BLOCK_LEVELS -u OPEN -u CLOSE`; a missing or doubled marker is refused; SKILL.md holds the loop the issue states.
  Test: "wording.sh adversarial prints the live angles"; "wording.sh review prints the closing focus"; "wording.sh refuses a folder with no pass script"; "a renamed wording variable breaks the guard"; "the pass script carries one begin and one end wording marker"; "the skill names adversarial-review for every round"; "the skill holds the proof bar at intake"; "the skill stops for the owner on a user-visible fix"; "the skill keeps fast-lane review for a Fast-lane worktree"; "the skill writes its record ending VERDICT: GO"
- D16 #535: `seat.sh launch plan-judge-opus` is refused until the Sol seat's `.rounds` count is at least the Opus count, unless plan-judge-sol is off in /plugin config (plan-tier.sh:57 then runs Opus alone); the Panel runs Sol first. No round cap returns.
  Test: "an Opus judge with no Sol record is refused"; "an Opus round ahead of Sol's is refused"; "an Opus round level with Sol's launches"; "a third judge round is not capped"; "an Opus round launches when Sol is off in /plugin config"
- D17 #537: main-watch unsets MallocStackLogging and MallocStackLoggingNoCompact; doctor warns on a scratch file over 100 MB.
  Test: "main-watch's child shells see no MallocStackLogging"; "a log past the cap stays under it after many ticks"; "doctor warns on a scratch file over 100 MB"
- D18 #544: the 27 changed host sections are rewritten into their plugin templates, no host name; the 31 map-only entries are the host's.
  Test: "each ported rule section is in its template"
- D19 #555: host Part 1's view code ports as is, fitted to the plugin's snapshot (`needsMax` reads `needsOwner`, a merge's `mergeSha` reads `sha`, its cost the existing `finishedUsd`). Host fields the plugin lacks take the host's own null path, so the element is not drawn: `pc` (no `tests.pc`), `devSha` and a merge's `dest` (no dev deploys). "What each one blocks" is kept: an ask's unit comes from its id by holds' rule (`<unit>`, `plan-<unit>`, `review-stop-<unit>-r<n>`, decision.sh:278), as the plugin ledger has no `--unit` field; another id shows no "blocks". A carried field that is absent or junk joins the host's `unread` note naming it. No element is a placeholder.
  Test: "the header shows stage counts, spend and the 7-day gauge"; "waiting on the owner lists open decisions with age"; "an ask whose id names a unit shows the unit it blocks"; "merged today reads finished builds, so a push does not empty it"; "the band puts owner questions and the limit first, the busiest unit second"; "the status line leads with the worst state"; "sections with nothing to show take no lines"; "a unit card shows stage colour, model, effort and working mark"; "a missing or junk field joins the unread note naming it"; "motion off draws the working mark still"; "the views write no file"
- D20 #564-#567: as their cuts say.
  Test: "--adopt forgives a __pycache__ of only .pyc files"; "--adopt keeps a worktree whose __pycache__ holds another file"; "a plan limit with no id is refused naming the unit brief"; "an unmarked worktree with a live Builder seat is not refused"; "an unmarked worktree with no live Builder seat is still refused"; "a no-sender close is retried once with --from"; "with no sender handle the close is not retried"
- D21 (owner, 2026-11-02, was Q1): the Test edits below are approved.
  Test: none, an approval; the edited asserts are the Acceptance tests
- D22 (owner, 2026-11-02, was Q2): the User-visible changes ship as listed.
  Test: none, an approval; each change has its cut's test
- D23 (owner, 2026-11-02, was Q3): main closes #523, #556, #558, #578 by hand with the evidence under Not in this unit.
  Test: none, an issue close, no code
- D24 #532: only the run's coordinator pane is main for the context line, the stop-hook restart, main-watch's wake and rebind, and board.sh's bind. No run at all (no COMMANDECK_RUN, no run file, run-current names none) answers main, as today, and so does no Orca handle; a known run whose coordinator cannot be read (run-list fails, or the run is not in it) answers unknown: it restarts nothing and says one line; a listed run with an empty coordinator answers no-coordinator, which the context line and stop hook treat as unknown. board.sh asks pp_is_main_pane before run-use (:77) and before it rewrites the run file (:57): only main binds, as today, and writes main-pane.txt. Every other answer binds nothing and writes nothing, since board.sh binds whoever calls it and only `IS_MAIN`, a git-dir check (board.sh:54-55), stands between an Orca automation at the repo root and the run. No-coordinator, and not main with the coordinator no live pane in `orca-ide terminal list` (connected, not orphaned, as paths.sh:443-444), print the not-bound line (board.sh:81) with the reason and the exact command: `THIS TERMINAL IS NOT BOUND: run <run> has no live coordinator (<h>|none); if this pane is main: orca-ide orchestration run-use --id <run>`; after main runs it, its next board.sh answers main and writes main-pane.txt. A live other coordinator, a failed terminal list or unknown print one line naming the coordinator, or `unknown` when run-list did not answer, as before.
  Test: "a second session in the main checkout is not restarted as main"; "the run's coordinator past the line is still restarted"; "main with no Orca run past the line is still restarted"; "an unknown coordinator restarts nothing and says so"; "a second session past the line is told nothing"; "main-watch never types into a claude pane that is not the coordinator"; "board.sh in a second pane neither binds the run nor rewrites the run file"; "a fresh main whose old coordinator pane is closed is told the run-use line and neither binds nor writes main-pane.txt"; "a fresh main on a run with no coordinator is told the run-use line and neither binds nor writes main-pane.txt"
- D25 #539: the hook refuses a second lone read-only call in a row only on proof: its own transcript line, one call in its message, and that message marked complete (A8 names the marker). A message with no complete mark is advice only, however long the wait, since siblings land as separate lines (batch-independent-looks.sh:164-169). Under the advice's tier gate (strict tier, planner seats, Builders); a repeat or a batch passes. A default-tier project keeps the advice only, as the default tier turns strict guards off.
  Test: "a second lone look is refused naming the batching fix"; "a repeat of the refused call passes"; "an edit or test run between looks resets the count"; "calls batched in one turn are never refused"; "a batched call whose sibling line lands late is never refused"; "a new prompt resets the count and keeps the advice said once"; "a seat with no transcript is never refused"; "a default-tier main is never refused"
- D26 #540: a read-only Serena call (six names) sets the first-call mark and passes with no server note; Serena's edit tools and the Edit, Write, Bash budget are unchanged; the Codex wrapper's six names equal the gate's.
  Test: "a Serena read as the first call draws no missing-server note and sets the mark"; "a Serena edit tool as the first call still gets the missing-server note"; "an Edit past the budget is still refused after a Serena call"; "the Codex wrapper lists the same six read-only Serena tools as the gate"
- D27 #541: the Builder still starts builder-fresh-round.sh itself; its told text names `Unit:`, `Cut:`, `Tests:`, `Open findings:` lines; the host's Stop-hook restart is not ported.
  Test: "the Builder line names the unit, cut, test state and open findings lines"; "a Builder under the line is told nothing and leaves no hand-off"
- D28 #546 #547 #549: three typed-prompt lines after seat.sh:517 for plan-judge-* only: restate each section (one not restatable is blocking); is there a smaller change that fully solves it; every named file, function and test exists or is marked new (a `- new` step or a Red-first case). For #559's loop, seat.sh:514's whole sentence from "On a revised plan" ("On a revised plan, recheck only what its Plan change log names; a revised plan is not judged again.") becomes, under COMMANDECK_DRIVER=1 (unit-drive.sh exports it), "Each round is a full read of one plan version."; the plan-judge-sol note in config/routing.json:44 says one round outside unit-drive.sh, a round per version under it.
  Test: "a driven judge's prompt makes each round a full read of one version"; "a driven judge's prompt carries no recheck-only sentence"; "an undriven judge's prompt keeps the one-round sentence"; "a plan judge's typed prompt asks it to restate each plan section"; "a section that cannot be restated is named as a blocking finding in the prompt"; "a plan judge's earlier asks are unchanged"; "a plan judge's typed prompt asks whether a smaller change fully solves the problem"; "a plan judge's typed prompt carries the readiness check"; "the prompt makes a named item neither found nor marked new a blocking finding"; "a plan-author seat's typed prompt carries none of the judge asks"
- D29 #547 #551: one smaller-change sentence in LENS (builder-codex-pass.sh:164, same line), which every pass kind gets, so the closing pass asks it too; a yes names the change and why it fully solves the problem, never a scope cut.
  Test: "the adversarial pass prompt asks whether a smaller change fully solves the problem"; "the closing pass prompt carries the smaller-change question"; "the pass ask makes a yes name the smaller change and why it solves it"
- D30 #550: two findings share a cause when one's class-search hits hold the other's site, transitively; the pass writes the causes file and the hand-off makes each cause one item naming every place.
  Test: "two findings whose searches hit each other's site become one item naming both places and one fix group"; "a finding whose search hits no other finding stays a separate item"
- D31 #538: plan seats stay outside the Builder cap (seat.sh:401 already); a judged plan is refused at launch when a file its Steps name changed on main since the judge's `mainsha`, checked at main's tip and again at the sha the worktree resets to; a record with no `mainsha` is refused.
  Test: "a plan judge seat opens while the Builder cap is full"; "a Builder past the cap is still refused while plan seats run"; "a judged plan whose Steps file changed on main is refused"; "a plan judged before main moved on other files still launches"; "main moving during the launch refuses before adoption"; "a judge record with no main sha is refused"
- D32 #542: break-run.sh gains an apply mode, `<plan> <k> <file> <line> [<replacement>]`: it first runs the test clean and refuses (exit 2) a baseline that fails or already prints `FAIL <label>`; then the text goes in through the environment, the file is restored from a byte copy at `<git-dir>/break-run.bak` on EXIT, INT and TERM, and a missing or unchanged line is refused. A leftover backup refuses the next run and prints the `cp` that restores it, so a SIGKILL (F9) cannot pass unseen. The 2-argument form is unchanged. proof-run.sh is the release measurer and is not touched. Departure from the host's scratch worktree: the Builder's break must run on its uncommitted tree, which a worktree at HEAD lacks.
  Test: "a break run restores the file byte for byte"; "an already-red test is refused before the break"; "a break that changes no line is refused naming the line"; "a line past the end is refused and the file is untouched"; "a replacement with quotes, a dollar sign and backslashes lands as written"; "a run stopped by INT or TERM restores the file"; "a leftover backup from a killed run is refused naming the restore"; "a wrong check label is refused naming the label"
- D33 #545: a merge of a plan with 2+ `- C<n>` cuts under `## Cuts` reads the evidence's `C<n>: built` lines at step 1, beside PARTIAL (merge-unit-local.sh:503). With a cut left: each `#N` its open cut bullets name joins PARTIAL, so the squash message says `Refs` (:507) and close_issues (:727) leaves it open; cleanup skips `unit-close.sh merged` (:153), so the Builder's task stays open; built cuts gain ` -- done`, only the plan is committed, the DONE line ends `unit open: next Cut <n>; plan commit <sha8>` and one task names that cut; its `sha=` is `$MERGE_SHA` (:720; HEAD on a dry run, where :568 skips the merge), never the plan commit. A `- C<a>-C<b>` bullet is each cut a to b (Data design). The merge never fails for it. Departs from the host, which closes the issues (#545: "does not close the unit"). The Builder template says to write `C<n>: built` per finished cut.
  Test: "a merge with a cut left marks the built cut, names the next and tasks it"; "an issue named on an open cut stays open and reads Refs in the squash message"; "a merge with a cut left keeps the Builder's task open"; "a plan with one cut or none is left byte for byte"; "a plan whose every cut is built is marked and names nothing"; "a failed task create is named on the DONE note and the merge goes on"; "a fenced cut line is not counted"; "a plan with uncommitted edits on main is not touched"; "a range cut bullet counts as each cut in it"; "the DONE line names the merge commit, not the plan commit"
- D34 #548: dead-ref keeps its name and warn-only exit; it skips fenced lines and adds link targets, other tracked top-level directories and bare script names no tracked file has.
  Test: "a template citing a gone path, script or link is flagged with file and line"; "a live path, a URL and a fenced example are not flagged"; "the doctor's lint call flags the same gone path"
- D35 #552: one Stop hook, a 3,000-character constant: a closing reply past it naming no path (a word with `/` and an extension) is sent back once; `stop_hook_active` and reviewer panes pass.
  Test: "a reply past 3,000 characters naming no file is sent back once"; "a short reply, one naming a path and the hook's own second stop pass"
- D36 #553: delete with no replacement: the checklist rule, checklist-guard.sh, the Todo list section and resume step, the restart's TaskCreate clause, the gate's todo kind and, per D40, the dashboard's main task list card (dashboard.sh todos() :904-915 and its `part todos` :1170, dashboard/app.js renderTodos :1296-1310 and :1807, the index.html section :162-170, app.css:335's `.todos` selector); Orca's task list stays. The scan test reads templates/*.md, hooks/*.sh, hooks/lib/*, skills/handoff/SKILL.md and scripts/checkpoint-context.py for TaskCreate, TaskUpdate, TaskList, TodoWrite and "Todo list"; three allow-lists stay and are skipped by file and line: pane-budget-gate.sh:85, agent-model-guard.sh:24, doctor.sh:79.
  Test: "no rule, hook, template or checkpoint file names a todo tool or list"; "the dashboard snapshot carries no todos source"; "the resume prompt names no todo tool or list"; "every registered hook file exists"; "the resumed context carries no todo rule"; "a Todo list section carries nothing in the checkpoint gate"
- D37 #559: unit-drive.sh loops plan versions (the plan's sha256) until every judge plan-tier names says GO on one version with no question line; judges launch in plan-tier order and are waited on together; a NO-GO or a question gets a revision carrying every finding; main hears only a question, a seat error or the launch. plan-tier's judge list stays (the host's both-judges-always is a routing change). The question phrase is `Question for the owner:`. The plan's own `## Question for the owner` section gates too, as the host's (0c86f6054): before each judge round the loop reads it; open (not absent, empty or one `None:` paragraph) sends main its text through to-main.sh (as stop() :69 does) once per version, recording `<sha256> <epoch>` in `drive-<unit>.asked` (a restart on that version sends nothing), and waits on `decision.sh list` for a `plan-<unit>` row whose `answeredAt` (`fromdateiso8601`) is at or after that epoch, as the host's question_gate (0c86f6054); the ledger keeps one row per id (decision.sh:43-47), so an older round's answer never releases it; the judge question-line wait uses the same bound; once answered, one revision writes the answer into the plan's Decisions and sets the section to `None: answered as D<n>`, then the round runs. The log is the `at` lines on stderr (:126): each step prints one with its UTC time, the plan hash's first 8 characters and the verdict.
  Test: "an open Question section pauses the loop until plan-<unit> is answered"; "an answered question is written into the plan and the section reads None:"; "each loop step logs its time, plan version and verdict"; "the loop runs the author, then the judges the tier names, then launches"; "a Panel launches Sol then Opus before either is waited on"; "a NO-GO revision carries every finding from both reports"; "both GO on one version launches the Builder"; "the author-to-launch run sends main nothing"; "a GO on an older plan version is not a pass"; "a question line pauses the loop until plan-<unit> is answered"; "an answer from an earlier plan version does not release the pause"; "a failed or refused seat stops the loop with the seat's error"
- D38 (owner, 2026-11-02, was Q4): the r2 Test edits below are approved.
  Test: none, an approval; the edited asserts are the Acceptance tests
- D39 (owner, 2026-11-02, was Q5): the r2 User-visible changes ship as listed.
  Test: none, an approval; each change has its cut's test
- D40 (owner, 2026-11-02, was Q6, /maxauto; pending the owner's yes (decision plan-commandeck-open-2026-11-02-visible)): (a) the dashboard's main task list card is deleted with its two test asserts (D36, C33).
  Test: "the dashboard snapshot carries no todos source"
- D41 (owner, 2026-11-02, was Q7, /maxauto; pending the owner's yes (decision plan-commandeck-open-2026-11-02-visible)): (a) the User-visible changes marked (r3) ship as revised.
  Test: none, an approval; each change has its cut's test

## Accepted failure modes

- F1 G3, G4, G8: a warning lets a Builder write a tracked file around the edit guards, a non-simple search flood main, or a worker wait past the cache; the owner ordered it.
  Test: "an inline tracked-file write runs with a warning"
- F2 G9: a hook that hangs no longer stops its call; a bypass by slowness is possible.
  Test: "no refusing hook fails closed"
- F3 #555: Parts 2-3 (context gauge, round dots, gate strip, receipt, timeline, log, keys) are not built; the host has not built them.
  Test: none, not built here
- F4 #532: inbox-drain.sh still records a main-checkout session's handle at start; gating it would drop a fresh main's queue.
  Test: none, not changed here
- F5 #541: the four carry-over lines are asked for, not checked; the plugin's Builder starts its own restart.
  Test: "the Builder line names the unit, cut, test state and open findings lines"
- F6 #545: a Builder task the merge kept open for a cut left is completed later by a by-hand `unit-close.sh --sweep --apply`, as its worktree is gone (unit-close.sh:9-11); the next-cut task stays open.
  Test: "a merge with a cut left keeps the Builder's task open"
- F7 #559: no round limit (D16); a revision that changes nothing stops the loop.
  Test: "a revision that leaves the plan unchanged stops"
- F8 #539: a lone look whose message never gets the complete mark is advice only, so a slow-streaming lone call costs its turn as today.
  Test: "a batched call whose sibling line lands late is never refused"
- F9 #542: a SIGKILL (`kill -9`, a hard tool timeout) runs no trap, so the break stays in the file until the next break-run.sh call refuses and names the restore.
  Test: "a leftover backup from a killed run is refused naming the restore"

## Assumptions

- A1 [uncertain] G13: a bounded shell read of a saved tool-output path opens no permission prompt. Builder check before C7, live worker seat, `rg -m 1 x <tool-results path>`. No prompt: build C7. A prompt: skip C7, keep the block, `G13: not built -- permission prompt`.
- A2 [likely] G11: with D9's recorder change, a live decoy-less main picker is recorded once and opens with the decoy. Builder check after C6, live main seat. Both hold: done. Recorded twice or not at all: stop C6, keep the block, `G11: not built -- recorder`.
- A3 [likely] #531: a live PostToolUse Read payload carries `tool_response.file.content`. Builder check after C1, live seat, scratch repo with `.claude/companions.tsv`: a normal Read is recorded, an offset-900 Read is not and its paired Edit is refused. Green: Closes #531. Red: `#531: partial -- the payload shape`.
- A4 [likely] G9: Claude Code lets a call through when a hook with no onFailure key times out. Builder check before C5: a probe hook sleeping past a 1 s timeout in a live seat. Through: build. Blocked: stop C5, ask main.
- A5 [likely] #567: Orca accepts `--from <pp_sender>` from a long-job pane. Builder check in C17 on a throwaway task. Refused: `#567: partial -- the sender handle`.
- A6 [settled] The snapshot carries open decisions (dashboard.sh:561-573); hook times measured (Stated limits).
- A7 [likely] C19: a restarted main is bound before its first Stop, and no main-watch test leans on the any-pane fallback. Builder check before C19: `bash scripts/run-shell-tests.sh scripts/__tests__/main-watch*.test.sh` before and after. A new red: give its fixture a coordinator or main-pane.txt, never restore the fallback. A fresh main after main's pane closed is told the run-use line by board.sh (D24) and binds with that one call, so no live path needs the fallback.
- A8 [uncertain] C20: a transcript line carries a message-complete mark: `message.stop_reason` non-null only on a message's last content line. Builder check before C20 ships: a probe PreToolUse hook logging each call's line, 10 live two-call batches (one with a slow second call) and 10 lone reads. The mark holds on all: refuse only on it. No such mark: no refusal, advice only, `#539: partial -- no message-complete mark`.
- A9 [uncertain] C21: a real Codex review seat reaches Serena. serena-shared.test.sh uses stub servers (:3), so it proves the names only. Builder check before #540 is marked built: launch a Codex review seat on a scratch worktree; it reports Serena available and returns a `find_symbol` hit for `pp_seat_pane`. Both: `#540: built`. Either fails: `#540: partial -- Codex seat cannot reach Serena`.
- A10 [likely] C26: the new functions run alone with WT, python3 and rg. Builder check in C26. Works: slice and run them. Fails: run the cases through `fpass` on a round with a seat handle.
- A11 [likely] C28: the merge-base of the planning worktree and main is the main the judge read. Builder check before C28: a fixture judge after a plan commit; `mainsha` equals main's tip at the cut. Differs: record `git rev-parse refs/heads/main` at launch.
- A12 [likely] C30: main's wake for a finished merge carries the DONE line. Builder check before C30: read the wake body main-watch.sh builds. Omits it: the task alone names the cut; note it in evidence.
- A13 [uncertain] C31: the wider dead-ref flags few real rows on the plugin's tree (CI fails on any). Builder check after C31: `bash scripts/rules-audit.sh --repo .`. Zero: done. Real rows: fix each doc line. A missed placeholder style: add it to the skip pattern with a case, never an allowlist.
- A14 [uncertain] C32: Codex's Stop payload carries `last_assistant_message`. Builder check: hooks/codex-dispatch.sh's Stop arm. Present: done. Absent: the hook passes every Codex reply; no change.
- A15 [likely] C34: `seat.sh wait` right after `seat.sh launch` waits out the launch, and a scratch judge spec passes seat.sh's Plan-line check (:464). Builder check before C34. Early return: poll the record's pid first. Spec refused: write it under .claude/briefs/.
- A16 [settled] C23-C25: plugin plans mark new work by a `- new` step (plan-check.sh:140) or a Red-first case (:436); `rg -c 'Produces:' scripts/plan-check.sh templates` printed nothing, 2026-11-01, so the ask names those two.

## Steps

- modify hooks/{bash-guardrails,pane-budget-gate,no-poll-loops,git-safety,worker-ask-guard,generated-read-guard,builder-search-guard,edit-content-tripwires}.sh -- C1-C9
- modify hooks/lib/shell_reads.py ~194 -- C7 bound fields
- modify hooks/hooks.json ~20 -- C5, C20, C32, C33
- modify hooks/__tests__/{bash-guardrails,pane-budget-gate,no-poll-loops,git-safety,worker-ask-guard,generated-read-guard,builder-search-guard,edit-content-tripwires}.test.sh -- C1-C9
- modify hooks/__tests__/hook-on-failure.guard.test.sh -- C5
- modify hooks/ask-records-decision.sh ~35 -- C6 records a decoy-less picker under 4 options
- modify hooks/__tests__/ask-records-decision.test.sh -- C6
- modify scripts/decision.sh ~283 -- C10
- modify scripts/__tests__/decision.test.sh -- C10
- modify hooks/*.sh -- C11 headers
- new hooks/__tests__/hook-retire-when.guard.test.sh -- C11, C33's registered-file case
- new skills/maxreview/{SKILL.md,wording.sh} -- C12
- new scripts/__tests__/maxreview-wording.test.sh -- C12
- modify scripts/{seat,plan-tier}.sh -- C13
- new scripts/__tests__/seat-judge-rounds.test.sh -- C13
- modify scripts/{main-watch,doctor}.sh -- C14
- new scripts/__tests__/main-watch-malloc.test.sh -- C14
- modify scripts/__tests__/doctor.test.sh -- C14
- modify templates/{_batch-brief-template,_builder-brief-template,AGENT_STARTUP,global-rules,main-session,checkpoint}.md -- C13,C15,C20,C28-C30,C32-C34
- new scripts/__tests__/template-sections.test.sh -- C15
- modify hooks/{units-sources.ts,units.tsx} -- C16
- new hooks/units-elements.ts -- C16
- modify hooks/{units-sources,units-panes,units}.test.tsx -- C16
- modify types/index.d.ts -- C16
- modify scripts/{plan-worktree-close,builder-codex-pass,paths}.sh -- C17
- modify scripts/__tests__/{plan-worktree-close,builder-codex-pass-limits,seat-plan-marker}.test.sh -- C17
- new scripts/__tests__/unit-close-sender.test.sh -- C17
- modify docs/{hooks,commands}.md -- C11,C12,C18,C29-C33
- modify {README,CHANGELOG}.md -- C18,C28,C34
- modify .claude-plugin/plugin.json -- C16,C18
- modify hooks/lib/project.sh ~87 -- C19 pp_is_main_pane
- modify hooks/context-line.sh ~27 -- C19 main test at :43; C22 the four fields
- modify hooks/context-clear-stop.sh ~25 -- C19 main test
- modify scripts/board.sh ~57 -- C19 pp_is_main_pane before the run-file write and run-use (:77); main-pane.txt
- modify scripts/__tests__/board.test.sh -- C19 second-pane case
- modify scripts/main-watch.sh ~543 -- C19 MAIN_H
- modify hooks/__tests__/context-clear-stop.test.sh -- C19, C22, C33 fixtures
- modify scripts/__tests__/main-watch-wake-sources.test.sh -- C19
- modify hooks/batch-independent-looks.sh ~46 -- C20
- modify hooks/__tests__/batch-independent-looks.test.sh -- C20
- modify hooks/pane-budget-gate.sh ~95 -- C21 six-name skip
- modify scripts/__tests__/serena-shared.test.sh ~217 -- C21
- modify scripts/seat.sh ~518 -- C23-C25 judge asks and the :514 driver sentence; C28 `mainsha` at ~469
- modify config/routing.json ~44 -- C23-C25 plan-judge-sol note
- new scripts/__tests__/seat-plan-judges.test.sh -- C23-C25, C28
- modify scripts/builder-codex-pass.sh ~164 -- C12 wording markers at :141 and after :183; C24 LENS; C26 at :134, :1419-1497, :2376, :2454
- modify scripts/__tests__/{builder-codex-pass-suite,builder-codex-pass-class-sites}.test.sh -- C24, C26, C27
- modify scripts/builder-launch.sh ~217 -- C28 stale check, again at ~364
- modify scripts/paths.sh ~1005 -- C28 pp_plan_stale
- modify scripts/__tests__/builder-launch-resume-from-plan.test.sh -- C28
- modify scripts/__tests__/fixtures/builder-launch-resume-setup.sh ~53 -- C28 `mainsha=`
- modify scripts/break-run.sh ~16 -- C29
- modify scripts/__tests__/break-run.test.sh -- C29
- modify scripts/merge-unit-local.sh ~803 -- C30
- new scripts/__tests__/merge-unit-local-cuts.test.sh -- C30
- modify scripts/instruction-lint.py ~198-214 -- C31
- modify scripts/__tests__/rules-audit.test.sh -- C31
- new hooks/long-reply-stop.sh -- C32
- new hooks/__tests__/long-reply-stop.test.sh -- C32
- delete hooks/checklist-guard.sh -- C33
- delete hooks/__tests__/checklist-guard.test.sh -- C33
- modify hooks/{resume-context.sh,lib/context-clear-restart.sh,lib/ruling-typed.jq} -- C33
- modify {skills/handoff/SKILL.md,scripts/checkpoint-context.py} -- C33
- modify hooks/__tests__/{context-clear-restart,resume-context,ruling-log}.test.sh -- C33
- modify scripts/__tests__/{brief-template,checkpoint-context}.test.sh -- C33
- modify scripts/dashboard.sh ~904 -- C33 todos() and `part todos` go (D40)
- modify dashboard/{app.js,index.html,app.css} -- C33 the task list card goes (D40)
- modify scripts/__tests__/{dashboard-built-seats.test.sh,dashboard-view.test.mjs} -- C33 todos asserts (D40)
- modify scripts/unit-drive.sh ~153-163 -- C34
- modify scripts/__tests__/unit-drive.test.sh -- C28 stub `mainsha=`, C34

## Cuts

- C1 G3, G4, G10 in bash-guardrails.sh, ~95. D1 at :82; D2 drops the linked-worktree test at :600 and turns :614-621 into a warning; D8 at :786-798. Produces: warnings and two rewrites. Consumes: the lexer, rewrite_safe. Consumers: none read its exit but Claude Code. Catches: a Builder retrying a refused call unchanged.
- C2 G5 in pane-budget-gate.sh, ~20. D3: `one()` at :39 takes `--out=<cp>`; :87-89 becomes the note. Consumers: context-clear-stop.sh restarts main without this gate (`bash hooks/__tests__/context-clear-stop.test.sh` green after). Catches: main frozen at its clear line.
- C3 G6, G8 in no-poll-loops.sh, ~50. D4 at :210-218 with :411-414's JSON; D5 at :426-437. Catches: a refused inbox check or wait retried.
- C4 G7 in git-safety.sh, ~30. D6: `wt_clean` beside `wt_owned` (:281-285), path by `wt_path`/`wt_canon`. Catches: a clean worktree left behind; a dirty one still kept.
- C5 G9, ~50. A4 first. D7: hooks.json keys; hook-on-failure.guard.test.sh inverted. Consumers: Claude Code alone reads the key. Catches: a slow hook under load stopping a call.
- C6 G11 in worker-ask-guard.sh and ask-records-decision.sh, ~30. D9 at :33-39; the recorder's `ask_decoy_first || exit 0` (:35) also passes a main picker under 4 options; A2 after. Consumers: the decision ledger (one row per picker), decision.test.sh unchanged. Catches: main's picker refused for a missing decoy.
- C7 G13, ~45. A1 first. D10: shell_reads.py adds the fields, the hook's `saved)` arm reads them (:46-50). Catches: a bounded read of saved output refused.
- C8 G14 in builder-search-guard.sh, ~37. D11 at :166-180 with :113-115's shape. Consumers: the dashboard reads `search-refused` events (unchanged). Catches: a Builder blocked mid-search.
- C9 G15 in edit-content-tripwires.sh, ~12. D12 at :186-189. Catches: docs and specs refused for naming localhost.
- C10 G20 in decision.sh, ~15. D13 at :283-287. Consumers of holds: builder-codex-pass.sh:1668 and :1959, main-watch.sh:285-293, merge-unit-local.sh; each sees fewer rows only for push asks. Catches: a push question freezing a closing pass.
- C11 #513, ~95. D14: one line in each of the 50 hooks/*.sh headers, below the fire-log arm line (hook-fire-log-coverage.guard.test.sh:86-90 stays green); docs/hooks.md one sentence. Catches: a kept guard with no exit condition.
- C12 #533, ~112. D15; builder-codex-pass.sh gains `# wording: begin` above :141 and `# wording: end` below :183; wording.sh defines `HERE` and `die`, sets `BLOCK_LEVELS= OPEN= CLOSE=` (:141 and :173-174 expand them, set at :126-128 and :138) and runs only the lines between them, so `set -u` holds (FORMAT at :134, outside, needs BLOCK_* vars). Produces: the markers. Consumers: wording.sh, maxreview-wording.test.sh. docs/commands.md lists the skill. Catches: review wording copied by hand and drifting.
- C13 #535, ~55. D16: gate after seat.sh:332; the `.rounds` line after :800; plan-tier.sh:60 order sol before opus; main-session.md says Sol first; the gate passes when plan-judge-sol is off (pp_role_enabled 1), a bad value stops naming the key. Consumers: unit-drive.sh:158-161 runs the Panel in plan-tier's order; builder-launch.sh:164 and :200 read verdicts only. Catches: an Opus round judging a plan Sol has not seen.
- C14 #537, ~45. D17: the unset after main-watch.sh's `set -uo pipefail`; doctor.sh a `warn` (:16) over `$PP_SCRATCH`, a sparse file in the test. Catches: a disk filled by allocator noise.
- C15 #544, ~400. D18. Sonnet helpers, one per template; each section's text rewritten with no host name; `bash scripts/startup-size.sh` within its limit after. Catches: plugin rules behind the host's.
- C16 #555, ~980. D19. Host files map: sources.ts to hooks/units-sources.ts, elements.ts to hooks/units-elements.ts, units.tsx, the three tests, types/index.d.ts, plugin.json's `motion`. Field map and the elements not drawn: D19. Not ported: the host's decision ledger `--unit`, review, merge and report edits. Catches: an owner question or a red state hidden in the views.
- C17 #564-#567, ~90. #564: plan-worktree-close.sh `tool_cache` (:71-73) forgives a `__pycache__/` holding only `.pyc`/`.pyo` files, never a symlink. #565: builder-codex-pass.sh `limits_refuse` (:1612-1613) tells a plan-file limit to go in `.claude/briefs/<unit>.md` with its id, as the leak test bans ids in tracked files. #566: seat.sh :106 also passes an unmarked worktree whose Builder seat record has a live pane (`pp_seat_pane`). #567: `pp_task_close` retries once with `--from "$(pp_sender)"` on `no_active_sender_terminal`, new file for its cases (the shared stub at unit-close.test.sh:40 stays). Catches: each issue's refusal.
- C19 #532, ~135. D24: pp_is_main_pane in project.sh (0 main, 1 not, 2 unknown, 3 no coordinator; COMMANDECK_RUN, else pp_run_file, else run-current; no run from all three is 0; it reads run-list itself, as pp_run_coord's `// ""` (paths.sh:434) folds a missing run into empty: a failed run-list or the run not listed is 2, the run listed with an empty or null coordinator_handle is 3); context-line.sh after :43 and context-clear-stop.sh after :25: 1 exits, 2 and 3 say one line; main-watch.sh:543-544 MAIN_H the coordinator, else main-pane.txt, live claude panes in main's checkout only; board.sh calls it first in its IS_MAIN arm (:56): 0 binds as today and writes main-pane.txt; 1, 2 and 3 skip the run-file write (:57) and run-use (:77) and write no main-pane.txt; 3, and 1 with the coordinator absent from the live terminal list (the fresh main after main's pane closed), print the not-bound line (:81) with the reason and `orca-ide orchestration run-use --id <run>`, never binding, as only an explicit claim shows a pane is main (an automation at the repo root passes IS_MAIN, :54-55); 1 with it live, a failed list, or 2 print `not main: the run's coordinator is <h>`, `<h>` being `unknown` on 2. Produces: pp_is_main_pane (0-3), main-pane.txt. Consumes: the run file, run-current, run-list. Consumers: MAIN_H readers main-watch.sh:502-506, :550, :586, :591, :662, :680, :698; board.sh's RUN, CUR and IS_MAIN readers below :77 (unchanged when 0). Catches: an automation in the main checkout restarted as main, then taking its run and wakes.
- C20 #539, ~100. D25: the hook reads `hook_event_name`; UserPromptSubmit zeroes the count and keeps NAGGED; PreToolUse refuses only when its own line carries A8's complete mark and count_calls reads 1; it waits at most the sibling window in 250 ms steps for its line, and a line with no mark by then is advice only (never a refusal on count 1 alone); a refusal sets the fourth field, the next call clears it. hooks.json: PreToolUse `.*` and UserPromptSubmit, no onFailure. PostToolUse unchanged. Produces: the refusal JSON, the `refused` field. Consumes: read_only, count_calls. Consumers: the state file, this hook only (:75); its tests' three-field files still parse. Catches: one full turn per lone look.
- C21 #540, ~30. D26: a case on the six read-only names after pane-budget-gate.sh:94 touches $MCP_CHECKED and exits 0; serena-shared.test.sh reads the six back from scripts/codex-no-helpers/codex:24 and the gate (name parity only); A9's live Codex seat is the connection proof. Below C2's :87-89, no shared line. Produces: the skip. Consumes: $MCP_CHECKED. Consumers: the mark (:95, :146); read-tracker.sh reads the mcp-down stamp, which a Serena read no longer writes. Catches: a false "serena is not running" note, a 3 s wait and a 10-minute down stamp.
- C22 #541, ~16. D27: context-line.sh:27's told text adds the four lines, the brief and the evidence file, keeping the first sentence and the hand-off-plus-command order the tests at context-clear-stop.test.sh:303-305 read. Produces: the told line. Consumes: HAND, UNIT (:24). Consumers: builder-fresh-round.sh (no field parse), pane-budget-gate.sh:180-199 (headings only). Catches: a hand-off naming no unit, cut, tests or findings.
- C23-C25 #546 #547 #549, ~30. D28: three `[[ $ROLE != plan-judge-* ]] || SPEC_TEXT+=` lines after seat.sh:517; :514's whole "On a revised plan" sentence picked by `${COMMANDECK_DRIVER:-0}`; routing.json:44's note. Produces: the asks in `$REC.prompt` (:647). Consumes: SPEC_TEXT, ROLE, COMMANDECK_DRIVER. Consumers: the judge model only; routing.json's note is read by people and routing-ssot checks (text only). New test file, as seat-launch.test.sh:179 is near its cap. Catches: a judge launched without an ask, or an author handed one.
- C24 #547, ~6. D29: one sentence appended to LENS on builder-codex-pass.sh:164, inside C12's markers, so wording.sh prints it. Produces: the ask in every pass prompt. Consumes: LENS. Consumers: plugin_prompt (:1082), the LENS presence check (:1087). Catches: the ask in one pass kind only.
- C26 #550, ~75. D30: FORMAT (:134) asks one flaw's findings to cite each other's site; class_sites (:1443) gains a causes-file argument and a union of hits; new findings_by_cause; fix_groups (:1419) joins a cause's files; the hand-off prints `## Findings by cause` (:2454). Produces: the causes file, that section. Consumes: class-search hits, the round file. Consumers: class_sites called at :2377 only, fix_groups at :2454 only. Catches: one flaw fixed as two items and back next pass.
- C27 #551, ~1. D29: no code beyond C24; the suite test pins the `final` pass prompt (r14). Produces: none beyond C24. Consumes: LENS. Consumers: none. Catches: the ask kept out of the closing pass.
- C28 #538, ~95. D31: seat.sh:469 adds `mainsha=` to a judge's record; paths.sh pp_plan_stale lists Steps paths changed between two commits (one `{a,b}` group expanded, as plan-check.sh:117); builder-launch.sh checks after the hash match (:217) and at the reset sha (:364, :392). Produces: `mainsha=`, the stale refusal. Consumes: judge records, Steps paths. Consumers: judge records read by builder-launch.sh (rv, :150); fixtures builder-launch-resume-setup.sh:53 and unit-drive.test.sh:24 gain the line. main-session.md and README say plan seats skip the cap. Catches: a Builder started on a plan whose files moved on main.
- C29 #542, ~90. D32: break-run.sh:16 takes the apply form: refuse a leftover `<git-dir>/break-run.bak` naming its `cp`; run the test clean and refuse a failing baseline or one already printing `FAIL <label>` (the :35-37 record read); back up, awk via ENVIRON, run the checks at :32-40, restore on EXIT/INT/TERM, exit 2 when the restore differs; the 2-argument form is unchanged. Produces: the evidence row. Consumes: the k-th Break line, the code file. Consumers: the break gate reads the row (builder-codex-pass.sh:1544); `red:` gains ` with <file>:<line> broken`. The Builder template's break text (:244-248) names the helper. Catches: a hand-made break mangled by quoting or left in the file.
- C30 #545, ~130. D33: open_cuts reads the plan (found as :535 does) and the evidence at step 1, after PARTIAL (:503) and before CLOSE_BODY (:506): open cuts' `#N` join PARTIAL; the plan edit and its commit run before cleanup_step (:803); cleanup_step skips `unit-close.sh merged` (:153) when a cut is left; CUT_NOTE ends the DONE line (:810), whose `sha=` reads `${MERGE_SHA:-HEAD}` (MERGE_SHA set at :720 inside :568's non-dry-run arm, `set -u` at :9) and whose note names the plan commit; open_cuts expands a `- C<a>-C<b>` bullet to each n; one task through orca-task-create.sh; the Builder template says to write `C<n>: built` per finished cut. Produces: PARTIAL's extra issues, the plan edit and its commit, CUT_NOTE, one task. Consumes: the plan's `## Cuts` bullets, the evidence file, PP_RUN_FILE. Consumers: PARTIAL's readers CLOSE_BODY (:507) and close_issues (:442); DONE read by prefix (orca-wait.sh:452, units-sources.ts:46, merge tests' `^DONE unit=` anchors); unit-close.sh --sweep (F6). Catches: a part merge leaving the next cut with no sign.
- C31 #548, ~55 plus any doc it flags. D34: instruction-lint.py:198-214 skips fenced lines for dead-ref only; a helper adds the three reference kinds via `git ls-files`; docstring and docs/commands.md:54. Produces: more `dead-ref` rows, same shape. Consumes: `git ls-files`. Consumers: doctor.sh:45, install-lib.sh:676 (setup count), ci.yml:55 (`rules-audit.sh --repo .` fails on any row), doctor.test.sh:78-92, rules-audit.test.sh:46-62. Catches: a doc citing a deleted script with no flag.
- C32 #552, ~70. D35: new long-reply-stop.sh (fire-log arm, `# Retire when:` line), a Stop entry in hooks.json through run-hook.sh, one rule line in the Builder and main templates, a docs/hooks.md row. Produces: the stop refusal, a fire-log row. Consumes: `last_assistant_message`, `stop_hook_active`. Consumers: Claude Code; hook-fire-log-coverage and codex-parity guards (shebang, arm line, executable). Catches: a long report with no file ending a turn.
- C33 #553, ~290 (100 are deleted file bodies). D36: delete checklist-guard.sh, its test and its hooks.json entry (:30-31); drop main-session.md:34, :120-124, checkpoint.md:30-31, :53, :81-83, resume-context.sh TODO_RULE (:102, :155, :181), the TaskCreate clause in context-clear-restart.sh:77 and ruling-typed.jq:6, skills/handoff/SKILL.md:27's words, checkpoint-context.py's todo kind, the docs/hooks.md:22 row; per D40, last, the dashboard card (D36's sites). Produces: nothing. Consumes: nothing. Consumers: the listed test files (Test edits); the snapshot's `sources.todos` readers dashboard-built-seats.test.sh:71 and the page's tile list dashboard-view.test.mjs:719 (D40); doctor.sh:79's switch, pane-budget-gate.sh:85 and agent-model-guard.sh:24 allow-lists stay. C11 never adds a line to the deleted hook. Catches: main told to load tools that are off.
- C34 #559, ~200. D37: unit-drive.sh:153-163's judge block becomes a loop over plan versions: launch pending judges in plan-tier order, wait together, collect; pass needs every judge GO on the hash with a non-empty report and no question line; else one revision through `seat.sh run plan-author` with COMMANDECK_SEAT_FORCE=1; a question waits on `decision.sh list` for a `plan-<unit>` answer at or after the epoch in `drive-<unit>.asked`, written once per version; the plan's Question section gates each round as D37 says, its answer written in by one revision; each step's `at` line carries time, version and verdict. The header, RULINGS (:46) and the dry-run stages line follow; main-session.md:63 (one edit with C13's) and README:283 say the loop. Produces: the STOP line, per-version and revise specs. Consumes: plan-tier `seat:` lines, seat.sh launch/wait/collect exits (collect 3 no verdict, 4 task not settled), each record's planhash. Consumers: the STOP line (main-watch.sh's done file, unit-drive.test.sh). Catches: a Builder on a version no judge read, or past a question.
- C18 docs and version, ~70. CHANGELOG in the user-facing style, README, docs/hooks.md for C1-C9 and C19-C22, plugin.json 0.68.0. Catches: version-check's refusal.

## Breaks

Break: hooks/__tests__/git-safety.test.sh -- a worktree with uncommitted or untracked work still blocks -- hooks/git-safety.sh wt_clean
Break: hooks/__tests__/generated-read-guard.test.sh -- an absent, junk or negative bound still blocks -- hooks/generated-read-guard.sh saved arm bound check
Break: hooks/__tests__/worker-ask-guard.test.sh -- a four-option picker with no decoy still blocks -- hooks/worker-ask-guard.sh option count
Break: hooks/__tests__/bash-guardrails.test.sh -- a terminal read with no handle, a variable or a pipe still blocks -- hooks/bash-guardrails.sh read rewrite condition
Break: hooks/__tests__/no-poll-loops.test.sh -- a quoted, chained or junk inbox check is never rewritten -- hooks/no-poll-loops.sh bare check rewrite condition
Break: hooks/__tests__/hook-on-failure.guard.test.sh -- no refusing hook fails closed -- hooks/hooks.json onFailure keys
Break: scripts/__tests__/decision.test.sh -- holds still lists a unit question from another source -- scripts/decision.sh holds push-ask filter
Break: scripts/__tests__/seat-judge-rounds.test.sh -- an Opus round ahead of Sol's is refused -- scripts/seat.sh Opus gate
Break: scripts/__tests__/seat-plan-marker.test.sh -- an unmarked worktree with no live Builder seat is still refused -- scripts/seat.sh plan mark condition
Break: scripts/__tests__/plan-worktree-close.test.sh -- --adopt keeps a worktree whose __pycache__ holds another file -- scripts/plan-worktree-close.sh tool_cache
Break: scripts/__tests__/seat-judge-rounds.test.sh -- an Opus round launches when Sol is off in /plugin config -- scripts/seat.sh Opus gate Sol-off arm
Break: hooks/__tests__/context-clear-stop.test.sh -- a second session in the main checkout is not restarted as main -- hooks/context-clear-stop.sh pp_is_main_pane call
Break: hooks/__tests__/batch-independent-looks.test.sh -- calls batched in one turn are never refused -- hooks/batch-independent-looks.sh wait before the count test
Break: hooks/__tests__/batch-independent-looks.test.sh -- a second lone look is refused naming the batching fix -- hooks/batch-independent-looks.sh streak test
Break: hooks/__tests__/pane-budget-gate.test.sh -- an Edit past the budget is still refused after a Serena call -- hooks/pane-budget-gate.sh six-name case
Break: scripts/__tests__/builder-launch-resume-from-plan.test.sh -- a judged plan whose Steps file changed on main is refused -- scripts/builder-launch.sh stale-file refusal
Break: scripts/__tests__/builder-launch-resume-from-plan.test.sh -- main moving during the launch refuses before adoption -- scripts/builder-launch.sh check at the reset sha
Break: scripts/__tests__/builder-launch-resume-from-plan.test.sh -- a judge record with no main sha is refused -- scripts/builder-launch.sh 40-hex test
Break: scripts/__tests__/break-run.test.sh -- a break run restores the file byte for byte -- scripts/break-run.sh restore from the backup
Break: scripts/__tests__/break-run.test.sh -- a break that changes no line is refused naming the line -- scripts/break-run.sh unchanged-line refusal
Break: scripts/__tests__/break-run.test.sh -- a run stopped by INT or TERM restores the file -- scripts/break-run.sh INT and TERM trap
Break: scripts/__tests__/break-run.test.sh -- an already-red test is refused before the break -- scripts/break-run.sh baseline check
Break: scripts/__tests__/break-run.test.sh -- a leftover backup from a killed run is refused naming the restore -- scripts/break-run.sh leftover-backup refusal
Break: scripts/__tests__/merge-unit-local-cuts.test.sh -- an issue named on an open cut stays open and reads Refs in the squash message -- scripts/merge-unit-local.sh open-cut issues into PARTIAL
Break: scripts/__tests__/merge-unit-local-cuts.test.sh -- a merge with a cut left keeps the Builder's task open -- scripts/merge-unit-local.sh cleanup_step unit-close skip
Break: scripts/__tests__/board.test.sh -- board.sh in a second pane neither binds the run nor rewrites the run file -- scripts/board.sh pp_is_main_pane check before run-use
Break: scripts/__tests__/board.test.sh -- a fresh main whose old coordinator pane is closed is told the run-use line and neither binds nor writes main-pane.txt -- scripts/board.sh dead-coordinator arm (pp_is_main_pane 1, coordinator not live)
Break: scripts/__tests__/board.test.sh -- a fresh main on a run with no coordinator is told the run-use line and neither binds nor writes main-pane.txt -- scripts/board.sh no-coordinator arm (pp_is_main_pane 3)
Break: scripts/__tests__/unit-drive.test.sh -- an answer from an earlier plan version does not release the pause -- scripts/unit-drive.sh answeredAt bound
Break: scripts/__tests__/merge-unit-local-cuts.test.sh -- a range cut bullet counts as each cut in it -- scripts/merge-unit-local.sh range expansion in open_cuts
Break: hooks/__tests__/batch-independent-looks.test.sh -- a batched call whose sibling line lands late is never refused -- hooks/batch-independent-looks.sh complete-mark test
Break: hooks/__tests__/ask-records-decision.test.sh -- a four-option picker with no decoy is not recorded -- hooks/ask-records-decision.sh option-count condition
Break: scripts/__tests__/unit-drive.test.sh -- an open Question section pauses the loop until plan-<unit> is answered -- scripts/unit-drive.sh Question section read
Break: scripts/__tests__/maxreview-wording.test.sh -- the pass script carries one begin and one end wording marker -- skills/maxreview/wording.sh marker refusal
Break: scripts/__tests__/merge-unit-local-cuts.test.sh -- a plan with one cut or none is left byte for byte -- scripts/merge-unit-local.sh two-cut guard on the write
Break: scripts/__tests__/merge-unit-local-cuts.test.sh -- a failed task create is named on the DONE note and the merge goes on -- scripts/merge-unit-local.sh task-create failure branch
Break: scripts/__tests__/merge-unit-local-cuts.test.sh -- a plan with uncommitted edits on main is not touched -- scripts/merge-unit-local.sh dirty-plan test
Break: hooks/__tests__/long-reply-stop.test.sh -- a reply past 3,000 characters naming no file is sent back once -- hooks/long-reply-stop.sh length and path conditions
Break: scripts/__tests__/unit-drive.test.sh -- a pass with a missing report is refused with a stop -- scripts/unit-drive.sh pass check
Break: scripts/__tests__/unit-drive.test.sh -- a GO report holding a question line is not a pass -- scripts/unit-drive.sh pass check
Break: scripts/__tests__/unit-drive.test.sh -- a revision that leaves the plan unchanged stops -- scripts/unit-drive.sh revise
Break: scripts/__tests__/unit-drive.test.sh -- a plan edited while it is judged stops -- scripts/unit-drive.sh judge round

## What can go wrong

| Case | Input or starting state | Expected result | Test |
|---|---|---|---|
| Bad input to a rewrite | `orchestration check` absent its run id, with junk or trailing words (`--json x`), empty (`--run ''`), quoted inside an echo, or in a chain | never rewritten; today's block or pass as before | a quoted, chained or junk inbox check is never rewritten |
| Bad bound on saved output | `head -n` absent its number, `-n -5`, `-n abc`, `rg` with no `-m`, a quoted path with a space, `cat` in one stage | blocked as today | an absent, junk or negative bound still blocks |
| Dirty or odd worktree remove | an untracked file; a missing path; a symlinked path; `git status` failing | blocked | a worktree with uncommitted or untracked work still blocks |
| Two judges in either order | Opus launched while Sol's round 1 runs (Sol 0, Opus 1); one Sol launch collected twice | Opus refused; the twice-collected round counts once | an Opus round ahead of Sol's is refused |
| Missing or junk view data | `usedPct` "58", an absent limit, an empty decision list, a 60-character unit name at 40 columns | the unread note names the field, never a throw or NaN | a missing or junk field joins the unread note naming it |
- Bad input C19: no Orca handle, or no run from env, file and run-current, answers main; a junk run file (run not listed) or a failing run-list answers unknown; an empty or null coordinator answers no-coordinator, unknown to the hooks; board.sh binds and writes on main only: on unknown, a live other coordinator or a failed terminal list it names the coordinator, and on no-coordinator or a coordinator not listed live it prints the run-use line; a quoted handle is compared via `jq --arg` -- an unknown coordinator restarts nothing and says so
- Bad input C20: no event name runs as PostToolUse; no transcript or tool_use_id passes; a line with no complete mark, or a junk one, is advice only; a junk or three-field state file resets or parses -- a seat with no transcript is never refused
- Bad input C21: an unlisted or junk Serena name, or an empty name, falls to the check -- a Serena edit tool as the first call still gets the missing-server note
- Bad input C26: an absent or empty causes file, a finding with no site, a known-gap search join nothing -- a finding whose search hits no other finding stays a separate item
- Bad input C28: an absent, empty, non-40-hex or unknown `mainsha` is refused; a `~12` suffix, backticks, a glob and one brace group are read as paths -- a judge record with no main sha is refused
- Bad input C29: a missing file, `3x`, `0`, `-1`, a line past the end, a red baseline or a leftover backup exits 2 and writes nothing; a replacement with quotes, `$`, backticks or backslashes lands as typed -- a line past the end is refused and the file is untouched
- Bad input C30: no plan, no evidence, `- Cx`, a `- C1` outside `## Cuts`, a fenced cut line, `C1: built` quoted in a sentence or a cut naming no issue -- a fenced cut line is not counted
- Bad input C30 ranges: `- C23-C25` is three cuts, `- C25-C23` the same three, a cut on a range and its own bullet one cut, `C23-C25: built` builds none -- a range cut bullet counts as each cut in it
- Bad input C31: an untracked tree, `](#x)`, `](mailto:x)`, a URL, an absolute path, a placeholder span or a fenced line draws no row -- a live path, a URL and a fenced example are not flagged
- Bad input C32: an absent message, junk JSON, an empty reply or exactly 3,000 characters pass -- a short reply, one naming a path and the hook's own second stop pass
- Bad input C34: a missing or empty report, collect rc 3 or 4, a junk verdict, a question line in any case or quoting, a Question section that is absent, empty, `None:` or `none:` with text after, a plan gone mid-loop -- a pass with a missing report is refused with a stop
- Bad input C34 answers: an `.asked` file missing, junk or for another hash sends again; a `plan-<unit>` answer before its epoch, a null or junk `answeredAt` waits on -- an answer from an earlier plan version does not release the pause
- Bad input C12: a missing, doubled or out-of-order wording marker is refused -- the pass script carries one begin and one end wording marker
- Bad input: none, C22-C25, C27 and C33 change fixed text or delete code and parse nothing new

## Stated limits

(every reviewer is handed these; a finding beyond one is out of scope: a follow-up issue, never a blocker)
- Hook speed: bash-guardrails.sh 33 ms, generated-read-guard.sh 128 ms a call, mean of 10 idle runs on the Mac, 2026-11-01; no speed change is planned.
- 23 refusing hooks carried `onFailure: block` (`grep -c` on hooks/hooks.json, 2026-11-01).

## Waiting on the host fix

- Rule: a twin waits until its host fix is on host main. `git -C <host> log --oneline main -E --grep '#<h>([^0-9]|$)'` prints no fix for any row, 2026-11-01 (host main ae4fa4865). Row: plugin issue, host issue, plugin site.
- #554 judges list every finding in one pass -- 3509 -- scripts/seat.sh:517
- #555 Parts 2-3 -- 3510 Parts 2-3, not built -- hooks/units-sources.ts, hooks/units.tsx
- #557 deleted-files check reads the brief copy -- 3512 -- scripts/merge-unit-local.sh:133
- #560 deleted-files check and a plain-text plan -- 3559 -- scripts/merge-unit-local.sh:535
- #561 collect rerun overwrites the report -- 3561 -- scripts/seat.sh:768
- #562 a bulleted Break line passes -- 3569 -- scripts/builder-codex-pass.sh:1539
- #563 a fixed earlier P3 counts as open -- 3572 -- scripts/builder-codex-pass.sh:715
- #568 restart pre-fills the carry-over -- 3580 -- hooks/context-clear-stop.sh:94
- #569 an answer posts to the asking pane -- 3581 -- scripts/decision.sh:215
- #570 scripts send their own status -- 3582 -- scripts/seat.sh:211
- #571 reading a message closes its task -- 3583 -- scripts/paths.sh:602
- #572 main waits on finish messages -- 3584 -- scripts/cos-lib.sh:9
- #573 a clean final review starts the merge -- 3585 -- scripts/main-watch.sh:980
- #574 an approval writes its Test edit line -- 3586 -- scripts/builder-codex-pass.sh:735
- #575 the Stop hook re-arms the waiter -- 3587 -- hooks/cos-inbox-waiter-stop.sh:53
- #576 relay runs one watcher -- 3588 -- scripts/cos-check.sh:50
- #577 a worktree removal stops its servers -- 3591 -- scripts/merge-unit-local.sh:193
- #579 collect loop hangs with a heartbeat -- 3597 -- scripts/dashboard.sh:1462
- #580 units panel undercounts cost -- 3599 -- hooks/units-sources.ts:132
- #581 today's cost for main and relay -- 3600 -- hooks/units-sources.ts:100
- #582 cannot-read warning drawn last -- 3601 -- hooks/units-sources.ts:312
- #583 12-hour clock -- 3602 -- hooks/units-sources.ts:196

## Not in this unit

- #506: the fence and CPU bound are built; dashboard-live's windows and three 600 s runs stay unmeasured. Stays open.
- #523: measured false last unit (file prints lead, test runs 6%); propose close.
- #556: no red-proof script; `rg -n 'TEST_CASE|cases' scripts/break-run.sh` prints nothing. Propose close.
- #558: no Adjacent convention in templates or hooks. Propose close.
- #578: no ledger growth grant; the cap is the plan's New tests line. Propose close.
- G1 the "wake already told you" block: no such refusal; `rg -n -i 'told you|already told' hooks scripts` hits comments only.
- G2 a main read of a worker worktree: pane-budget-gate.sh returns at once for main and never judges a read.
- G12 a foreground long-job wait: no long-job script; `rg -n -i 'long-job' hooks scripts` prints nothing outside tests.
- G16 the twin-line gate: no such gate; `rg -n -i 'twin-gate|twin line' hooks scripts` prints nothing outside tests.
- G17 the dependency guard on message text: already judges only run code; its tests pass a commit message naming an install.
- G18 aws with no profile: no aws guard; `rg -n -i '\baws\b' hooks` prints nothing.
- G19 `gh run watch`: no hook refuses it; scripts/ci-watch.sh calls it itself.
- G21 the growth grant reader (#578): no ledger grant exists; the cap is the plan's New tests line.
- G22 a quoted owner question in finding text: no pass check reads finding text for a question.
- G23 the push-snags pair: part (a) is G20 (built, C10); part (b), a push yes covering later commits, has no plugin push gate to change.
- Script refusals in the last 72 hours with no real catch: the plugin's scripts keep no fire log, so none can be counted here; none is changed.
- #559's both-judges-always: plugin keeps plan-tier's judge list (D37); a routing change for the owner.

## Acceptance test

- test file path: hooks/__tests__/bash-guardrails.test.sh (an inline tracked-file write runs with a warning; a scratch-only inline write draws no warning; main's search of . is rewritten to a 200-line cap; a worktree-root search runs with a warning; an unrewritable root search runs with a warning; a terminal read with a handle is rewritten to read-verdict.sh; a terminal read with --lines 50 is rewritten with 50 as the lines argument; a terminal read with no handle, a variable or a pipe still blocks)
- test file path: hooks/__tests__/pane-budget-gate.test.sh (past the line the --out= form passes; past the line a call runs with the checkpoint note; a Serena read as the first call draws no missing-server note and sets the mark; a Serena edit tool as the first call still gets the missing-server note; an Edit past the budget is still refused after a Serena call)
- test file path: hooks/__tests__/no-poll-loops.test.sh (a bare inbox check is rewritten to orca-wait.sh; a quoted, chained or junk inbox check is never rewritten; a worker's long ask runs with the cache warning; an unreadable wait runs with a note; an endless sleep loop is still refused)
- test file path: hooks/__tests__/git-safety.test.sh (a clean worktree remove --force passes; a worktree with uncommitted or untracked work still blocks)
- test file path: hooks/__tests__/hook-on-failure.guard.test.sh (no refusing hook fails closed)
- test file path: hooks/__tests__/worker-ask-guard.test.sh (a picker with no decoy opens with it added; a four-option picker with no decoy still blocks)
- test file path: hooks/__tests__/ask-records-decision.test.sh (a decoy-less picker the guard rewrites is recorded; a four-option picker with no decoy is not recorded)
- test file path: hooks/__tests__/generated-read-guard.test.sh (a bounded rg or head on saved output passes; an absent, junk or negative bound still blocks; cat on saved output still blocks)
- test file path: hooks/__tests__/builder-search-guard.test.sh (the fourth search of a streak runs with the hint; a whole-repo Grep runs with the hint)
- test file path: hooks/__tests__/edit-content-tripwires.test.sh (a doc edit naming a local address passes; a spec edit naming a local address passes)
- test file path: scripts/__tests__/decision.test.sh (holds ignores an open push question listing the unit; holds still lists a unit question from another source)
- test file path: hooks/__tests__/hook-retire-when.guard.test.sh (a hook with no Retire when line fails the guard; an empty Retire when condition fails the guard; every registered hook file exists)
- test file path: scripts/__tests__/maxreview-wording.test.sh (wording.sh adversarial prints the live angles; wording.sh review prints the closing focus; wording.sh refuses a folder with no pass script; a renamed wording variable breaks the guard; the pass script carries one begin and one end wording marker; the skill names adversarial-review for every round; the skill holds the proof bar at intake; the skill stops for the owner on a user-visible fix; the skill keeps fast-lane review for a Fast-lane worktree; the skill writes its record ending VERDICT: GO)
- test file path: scripts/__tests__/seat-judge-rounds.test.sh (an Opus judge with no Sol record is refused; an Opus round ahead of Sol's is refused; an Opus round level with Sol's launches; a third judge round is not capped; an Opus round launches when Sol is off in /plugin config)
- test file path: scripts/__tests__/main-watch-malloc.test.sh (main-watch's child shells see no MallocStackLogging; a log past the cap stays under it after many ticks)
- test file path: scripts/__tests__/doctor.test.sh (doctor warns on a scratch file over 100 MB)
- test file path: scripts/__tests__/template-sections.test.sh (each ported rule section is in its template)
- test file path: hooks/units-sources.test.tsx (the header shows stage counts, spend and the 7-day gauge; waiting on the owner lists open decisions with age; an ask whose id names a unit shows the unit it blocks; merged today reads finished builds, so a push does not empty it; the band puts owner questions and the limit first, the busiest unit second; the status line leads with the worst state; sections with nothing to show take no lines)
- test file path: hooks/units-panes.test.tsx (a unit card shows stage colour, model, effort and working mark; a missing or junk field joins the unread note naming it)
- test file path: hooks/units.test.tsx (motion off draws the working mark still; the views write no file)
- test file path: scripts/__tests__/plan-worktree-close.test.sh (--adopt forgives a __pycache__ of only .pyc files; --adopt keeps a worktree whose __pycache__ holds another file)
- test file path: scripts/__tests__/builder-codex-pass-limits.test.sh (a plan limit with no id is refused naming the unit brief)
- test file path: scripts/__tests__/seat-plan-marker.test.sh (an unmarked worktree with a live Builder seat is not refused; an unmarked worktree with no live Builder seat is still refused)
- test file path: scripts/__tests__/unit-close-sender.test.sh (a no-sender close is retried once with --from; with no sender handle the close is not retried)
- test file path: hooks/__tests__/context-clear-stop.test.sh (a second session in the main checkout is not restarted as main; the run's coordinator past the line is still restarted; main with no Orca run past the line is still restarted; an unknown coordinator restarts nothing and says so; a second session past the line is told nothing; the Builder line names the unit, cut, test state and open findings lines; a Builder under the line is told nothing and leaves no hand-off)
- test file path: scripts/__tests__/main-watch-wake-sources.test.sh (main-watch never types into a claude pane that is not the coordinator)
- test file path: scripts/__tests__/board.test.sh (board.sh in a second pane neither binds the run nor rewrites the run file; a fresh main whose old coordinator pane is closed is told the run-use line and neither binds nor writes main-pane.txt; a fresh main on a run with no coordinator is told the run-use line and neither binds nor writes main-pane.txt)
- test file path: hooks/__tests__/batch-independent-looks.test.sh (a second lone look is refused naming the batching fix; a repeat of the refused call passes; an edit or test run between looks resets the count; calls batched in one turn are never refused; a batched call whose sibling line lands late is never refused; a new prompt resets the count and keeps the advice said once; a seat with no transcript is never refused; a default-tier main is never refused)
- test file path: scripts/__tests__/serena-shared.test.sh (the Codex wrapper lists the same six read-only Serena tools as the gate)
- test file path: scripts/__tests__/seat-plan-judges.test.sh (a plan judge's typed prompt asks it to restate each plan section; a section that cannot be restated is named as a blocking finding in the prompt; a plan judge's earlier asks are unchanged; a plan judge's typed prompt asks whether a smaller change fully solves the problem; a plan judge's typed prompt carries the readiness check; the prompt makes a named item neither found nor marked new a blocking finding; a plan-author seat's typed prompt carries none of the judge asks; a driven judge's prompt makes each round a full read of one version; an undriven judge's prompt keeps the one-round sentence; a plan judge seat opens while the Builder cap is full; a Builder past the cap is still refused while plan seats run; a driven judge's prompt carries no recheck-only sentence)
- test file path: scripts/__tests__/builder-codex-pass-suite.test.sh (the adversarial pass prompt asks whether a smaller change fully solves the problem; the closing pass prompt carries the smaller-change question; the pass ask makes a yes name the smaller change and why it solves it)
- test file path: scripts/__tests__/builder-codex-pass-class-sites.test.sh (two findings whose searches hit each other's site become one item naming both places and one fix group; a finding whose search hits no other finding stays a separate item)
- test file path: scripts/__tests__/builder-launch-resume-from-plan.test.sh (a judged plan whose Steps file changed on main is refused; a plan judged before main moved on other files still launches; main moving during the launch refuses before adoption; a judge record with no main sha is refused)
- test file path: scripts/__tests__/break-run.test.sh (a break run restores the file byte for byte; an already-red test is refused before the break; a break that changes no line is refused naming the line; a line past the end is refused and the file is untouched; a replacement with quotes, a dollar sign and backslashes lands as written; a run stopped by INT or TERM restores the file; a leftover backup from a killed run is refused naming the restore; a wrong check label is refused naming the label)
- test file path: scripts/__tests__/merge-unit-local-cuts.test.sh (a merge with a cut left marks the built cut, names the next and tasks it; an issue named on an open cut stays open and reads Refs in the squash message; a merge with a cut left keeps the Builder's task open; a plan with one cut or none is left byte for byte; a plan whose every cut is built is marked and names nothing; a failed task create is named on the DONE note and the merge goes on; a fenced cut line is not counted; a plan with uncommitted edits on main is not touched; a range cut bullet counts as each cut in it; the DONE line names the merge commit, not the plan commit)
- test file path: scripts/__tests__/rules-audit.test.sh (a template citing a gone path, script or link is flagged with file and line; a live path, a URL and a fenced example are not flagged; the doctor's lint call flags the same gone path)
- test file path: hooks/__tests__/long-reply-stop.test.sh (a reply past 3,000 characters naming no file is sent back once; a short reply, one naming a path and the hook's own second stop pass)
- test file path: hooks/__tests__/context-clear-restart.test.sh (the resume prompt names no todo tool or list; no rule, hook, template or checkpoint file names a todo tool or list)
- test file path: hooks/__tests__/resume-context.test.sh (the resumed context carries no todo rule)
- test file path: scripts/__tests__/checkpoint-context.test.sh (a Todo list section carries nothing in the checkpoint gate)
- test file path: scripts/__tests__/dashboard-built-seats.test.sh (the dashboard snapshot carries no todos source)
- test file path: scripts/__tests__/unit-drive.test.sh (the loop runs the author, then the judges the tier names, then launches; a Panel launches Sol then Opus before either is waited on; a NO-GO revision carries every finding from both reports; both GO on one version launches the Builder; the author-to-launch run sends main nothing; a GO on an older plan version is not a pass; a question line pauses the loop until plan-<unit> is answered; an open Question section pauses the loop until plan-<unit> is answered; an answered question is written into the plan and the section reads None:; each loop step logs its time, plan version and verdict; a failed or refused seat stops the loop with the seat's error; a pass with a missing report is refused with a stop; a GO report holding a question line is not a pass; a revision that leaves the plan unchanged stops; a plan edited while it is judged stops; an answer from an earlier plan version does not release the pause)

## Claims to falsify

- No guard the owner kept (endless loop, dirty worktree, unbounded cat, four-option picker) passes after this unit.
- No rewrite turns a quoted, chained or junk command into a different command.
- Removing `onFailure: block` changes no hook's verdict on a call it finishes in time.
- The Panel runs Sol before Opus, so the Opus gate never refuses a normal unit-drive run.
- holds still lists every row it listed before but push asks.
- After C11 every hooks/*.sh has a `Retire when:` line and the fire-log coverage guard is green.
- wording.sh runs no line of builder-codex-pass.sh outside its `# wording: begin` and `# wording: end` markers.
- The units views write no file.
- `bash ci/leak-test.sh` passes on every template C15 changes.
- After C33 no hooks.json entry names a missing file, and no template or hook names TaskCreate, TaskUpdate or TaskList for main, outside the allow-lists at pane-budget-gate.sh:85, agent-model-guard.sh:24 and doctor.sh:79.
- unit-drive.sh never launches a Builder on a plan version a judge did not say GO on, nor past a question line or an open Question section.
- break-run.sh leaves the code file byte for byte as it found it on every exit but SIGKILL, and after a SIGKILL the next run refuses until it is restored.
- break-run.sh never prints a red row for a test that failed before the break.
- The batching refusal never refuses a call batched in one turn, however late its sibling's line lands.
- No merge closes, or writes `Closes` for, an issue named on a cut not built.
- board.sh binds a run, or rewrites the run file, only from the run's coordinator pane; a fresh main whose old pane is closed, or on a run with no coordinator, is told the run-use line and binds nothing.
- No `plan-<unit>` answer recorded before main was sent this plan version's question releases unit-drive.sh.
- Main with no Orca run is restarted past its line as before C19.
- A Serena edit tool still gets the first-call check.
- A judge record written before C28 is refused at launch, never passed.

## Issue cases

- #513 Body 1 -- hooks/__tests__/hook-retire-when.guard.test.sh -- a hook with no Retire when line fails the guard
- #533 Body 1 -- skills/maxreview/wording.sh -- wording.sh adversarial prints the live angles
- #533 Body 2 -- skills/maxreview/SKILL.md -- the skill names adversarial-review for every round
- #533 Body 3 -- skills/maxreview/SKILL.md -- the skill holds the proof bar at intake
- #533 Body 4 -- skills/maxreview/SKILL.md -- the skill stops for the owner on a user-visible fix
- #533 Body 5 -- skills/maxreview/SKILL.md -- the skill keeps fast-lane review for a Fast-lane worktree
- #533 Body 6 -- skills/maxreview/SKILL.md -- the skill writes its record ending VERDICT: GO
- #533 Body 7 -- skills/maxreview/wording.sh -- wording.sh refuses a folder with no pass script
- #533 Body 8 -- scripts/__tests__/maxreview-wording.test.sh -- a renamed wording variable breaks the guard
- #535 Body 1 -- scripts/seat.sh -- a third judge round is not capped
- #535 Body 2 -- scripts/seat.sh -- an Opus round ahead of Sol's is refused
- #535 Body 3 -- scripts/seat.sh -- an Opus round level with Sol's launches
- #535 Body 4 -- scripts/__tests__/seat-judge-rounds.test.sh -- an Opus judge with no Sol record is refused
- #537 Fix 1 -- scripts/main-watch.sh -- a log past the cap stays under it after many ticks
- #537 Fix 2 -- scripts/main-watch.sh -- main-watch's child shells see no MallocStackLogging
- #537 Fix 3 -- scripts/doctor.sh -- doctor warns on a scratch file over 100 MB
- #544 Body 1 -- scripts/__tests__/template-sections.test.sh -- each ported rule section is in its template
- #564 Body 1 -- scripts/plan-worktree-close.sh -- --adopt forgives a __pycache__ of only .pyc files
- #565 Body 1 -- scripts/builder-codex-pass.sh -- a plan limit with no id is refused naming the unit brief
- #566 Body 1 -- scripts/seat.sh -- an unmarked worktree with a live Builder seat is not refused
- #567 Body 1 -- scripts/paths.sh -- a no-sender close is retried once with --from
- #532 Body 1 -- hooks/context-clear-stop.sh -- a second session in the main checkout is not restarted as main
- #538 Body 1 -- templates/main-session.md -- a plan judge seat opens while the Builder cap is full
- #538 Body 2 -- scripts/seat.sh -- a plan judge seat opens while the Builder cap is full
- #538 Body 3 -- scripts/builder-launch.sh -- a plan judged before main moved on other files still launches
- #538 Body 4 -- scripts/seat.sh -- a plan judge seat opens while the Builder cap is full
- #538 Body 5 -- scripts/seat.sh -- a Builder past the cap is still refused while plan seats run
- #538 Body 6 -- scripts/builder-launch.sh -- a judged plan whose Steps file changed on main is refused
- #539 Body 1 -- hooks/batch-independent-looks.sh -- a second lone look is refused naming the batching fix
- #539 Body 2 -- hooks/batch-independent-looks.sh -- an edit or test run between looks resets the count
- #539 Body 3 -- hooks/batch-independent-looks.sh -- calls batched in one turn are never refused
- #540 Body 1 -- hooks/pane-budget-gate.sh -- a Serena read as the first call draws no missing-server note and sets the mark
- #540 Body 2 -- scripts/__tests__/serena-shared.test.sh -- the Codex wrapper lists the same six read-only Serena tools as the gate
- #540 Body 3 -- hooks/pane-budget-gate.sh -- an Edit past the budget is still refused after a Serena call
- #541 Body 1 -- hooks/context-line.sh -- the Builder line names the unit, cut, test state and open findings lines
- #541 Body 2 -- hooks/context-line.sh -- the Builder line names the unit, cut, test state and open findings lines
- #541 Body 3 -- hooks/context-line.sh -- a Builder under the line is told nothing and leaves no hand-off
- #542 Body 1 -- scripts/break-run.sh -- a break run restores the file byte for byte
- #542 Body 2 -- scripts/break-run.sh -- a wrong check label is refused naming the label
- #542 Body 3 -- scripts/break-run.sh -- a replacement with quotes, a dollar sign and backslashes lands as written
- #545 Body 1 -- scripts/merge-unit-local.sh -- an issue named on an open cut stays open and reads Refs in the squash message
- #545 Body 2 -- scripts/merge-unit-local.sh -- a plan whose every cut is built is marked and names nothing
- #546 Body 1 -- scripts/seat.sh -- a plan judge's typed prompt asks it to restate each plan section
- #546 Body 2 -- scripts/seat.sh -- a section that cannot be restated is named as a blocking finding in the prompt
- #546 Body 3 -- scripts/seat.sh -- a plan judge's earlier asks are unchanged
- #547 Body 1 -- scripts/builder-codex-pass.sh -- the adversarial pass prompt asks whether a smaller change fully solves the problem
- #547 Body 2 -- scripts/builder-codex-pass.sh -- the pass ask makes a yes name the smaller change and why it solves it
- #548 Body 1 -- scripts/instruction-lint.py -- a template citing a gone path, script or link is flagged with file and line
- #548 Body 2 -- scripts/instruction-lint.py -- a live path, a URL and a fenced example are not flagged
- #548 Body 3 -- scripts/instruction-lint.py -- the doctor's lint call flags the same gone path
- #549 Body 1 -- scripts/seat.sh -- a plan judge's typed prompt carries the readiness check
- #549 Body 2 -- scripts/seat.sh -- the prompt makes a named item neither found nor marked new a blocking finding
- #550 Body 1 -- scripts/builder-codex-pass.sh -- two findings whose searches hit each other's site become one item naming both places and one fix group
- #550 Body 2 -- scripts/builder-codex-pass.sh -- a finding whose search hits no other finding stays a separate item
- #551 Body 1 -- scripts/builder-codex-pass.sh -- the closing pass prompt carries the smaller-change question
- #551 Body 2 -- scripts/builder-codex-pass.sh -- the pass ask makes a yes name the smaller change and why it solves it
- #552 Body 1 -- hooks/long-reply-stop.sh -- a reply past 3,000 characters naming no file is sent back once
- #552 Body 2 -- hooks/long-reply-stop.sh -- a short reply, one naming a path and the hook's own second stop pass
- #553 Body 1 -- templates/main-session.md -- no rule, hook, template or checkpoint file names a todo tool or list
- #553 Body 2 -- templates/checkpoint.md -- no rule, hook, template or checkpoint file names a todo tool or list
- #553 Body 3 -- hooks/hooks.json -- every registered hook file exists
- #553 Body 4 -- hooks/lib/context-clear-restart.sh -- the resume prompt names no todo tool or list
- #553 Body 5 -- hooks/resume-context.sh -- the resumed context carries no todo rule
- #553 Body 6 -- hooks/hooks.json -- every registered hook file exists
- #559 Body 1 -- scripts/unit-drive.sh -- the loop runs the author, then the judges the tier names, then launches
- #559 Body 2 -- scripts/unit-drive.sh -- a Panel launches Sol then Opus before either is waited on
- #559 Body 3 -- scripts/unit-drive.sh -- a NO-GO revision carries every finding from both reports
- #559 Body 4 -- scripts/unit-drive.sh -- both GO on one version launches the Builder
- #559 Body 5 -- scripts/unit-drive.sh -- the author-to-launch run sends main nothing
- #559 Body 6 -- scripts/unit-drive.sh -- a GO on an older plan version is not a pass
- #559 Body 7 -- scripts/unit-drive.sh -- an open Question section pauses the loop until plan-<unit> is answered
- #559 Body 8 -- scripts/unit-drive.sh -- a failed or refused seat stops the loop with the seat's error

## Done

- #513 Done: a maintainer opens any plugin hook to judge whether it still earns its place -- its header says when it may be retired, and a hook without one fails the test suite
- #533 Done: a user runs /commandeck:maxreview on a worktree -- every round uses the review wording the plugin ships today, and it stops for the owner before a user-visible fix
- #535 Done: main launches the Opus plan judge before the Sol judge has judged the same round -- the launch is refused, naming Sol first, and no pane opens
- #537 Done: a user leaves main-watch running for days on a Mac -- its log stays small, and doctor warns if any scratch file passes 100 MB
- #544 Done: a user installs or updates the plugin -- the rule templates they receive carry the 27 rule sections the reference project changed
- #564 Done: a Builder adopts a planning worktree after plan checks ran Python there -- the adoption goes through
- #565 Done: a Builder adds a stated limit to its plan after judging -- the refusal tells it to put the limit in the unit brief, where the ruling id may stand
- #566 Done: a Builder that revised its plan launches a plan judge in its own worktree -- the judge opens
- #567 Done: main merges a unit from a long-job pane -- the Builder's task is closed, not left open
- #532 Done: a user runs an Orca automation in the main checkout while main works past its context line -- the automation is not checkpointed or restarted, and main keeps its run and its wakes; neither the automation's board.sh nor any other pane's takes main's run; a new main pane opened after main's closed, or on a run with no coordinator, is shown the exact `orca-ide orchestration run-use --id <run>` line by its first board.sh and has the run after that one call
- #538 Done: main plans the next unit while every Builder slot is full -- the plan and judge seats open at once, and a launch from a plan whose files moved on main is refused, saying to judge it again
- #539 Done: an agent in a strict-tier project, a planner seat or a Builder asks for a second file alone in its next turn -- the call is refused with a hint to batch, and a repeat or a batched turn goes through
- #540 Done: a Builder's first call in a session is a Serena find_symbol -- it runs at once with no "serena is not running" note
- #541 Done: a Builder passes its context line mid-build -- its next prompt tells it to write a carry-over naming its unit, cut, test state and open findings, then start a fresh session
- #542 Done: a Builder proves a plan's Break line red -- one `break-run.sh <plan> <k> <file> <line>` call breaks the line, runs the test, prints the evidence row and leaves the file as it was
- #545 Done: main merges a unit whose plan still has a cut not built -- the merge's last line says `unit open: next Cut <n>`, that cut's issues and the Builder's task stay open, one task for the cut waits, and finished cuts read ` -- done`
- #546 Done: a user runs a plan judge -- its report restates each plan section first, and a section it cannot restate is a blocking finding naming it
- #547 Done: a user runs a plan judge and a review pass -- each asks if a smaller change fully solves the problem, and a yes names that change
- #548 Done: a user runs doctor or `bash scripts/rules-audit.sh` on a project whose doc names a deleted script -- a `dead-ref` row names the file, line and reference
- #549 Done: a user runs a plan judge on a plan naming a function that does not exist -- the judge reports a blocking finding naming it
- #550 Done: a user runs a review pass where two reviewers report one flaw in two files -- the fix hand-off lists it as one item naming both places
- #551 Done: a user runs the closing review pass after fixes -- it asks again if a smaller change fully solves the problem
- #552 Done: an agent ends a turn with a 4,000-character reply naming no file -- the stop is held once, telling it to write the reply to a file and answer with the path and a short summary
- #553 Done: a user's main session starts, restarts or resumes -- it never loads the todo tools or rebuilds a checklist, and no "couldn't update the checklist" line appears
- #559 Done: main runs one `unit-drive.sh start` for a Panel unit and steps away -- a NO-GO is revised and judged again without main, and the Builder launches once the judges say GO on one version

## Progress notes

- One line per issue in the evidence file: `#N: built` or `#N: partial -- <what is left>`; one per guard item: `G<k>: built` or `G<k>: not built -- <why>`.
- #506: partial -- not worked here (Not in this unit).
- #531: A3's outcome.
- #555: partial -- Part 1 ported; Parts 2-3 wait on the host.
- #539: A8's outcome. #540: A9's outcome.

## Verification

- Each Acceptance test green; `bash scripts/run-shell-tests.sh --changed main` green during the build; the full shell tests green on the PC before any push.
- `claude plugin validate .`, `claude plugin test .`, `bash ci/leak-test.sh`, `bash ci/version-check.sh`, `bash scripts/startup-size.sh` pass.
- A1-A5 and A7-A15 run and their outcomes in Progress notes; every Break line has its red run.
- Review passes until the closing pass ends `VERDICT: GO` naming no finding.

## Routing

- Builder: this pane's model. Helpers, model named on every call: Sonnet `general-purpose` for code reading, test writing and mechanical edits (one per cut for C1-C9, C15's templates, C16's port); Haiku `Explore` for search. The Builder keeps cut order, the hook contracts and integration.
- Tests run on the PC; A1-A5 in live seats. Red runs only for Break lines.
- r2 ports: one Sonnet `general-purpose` helper each for C19-C22, C23-C27, C28-C30, C31-C33 and C34, each handed its cut lines and host commit; the Builder keeps C13-C34's order and the hooks.json and seat.sh merges.

## Test edits

- Test edit: hooks/__tests__/bash-guardrails.test.sh:130, :197, :219, :221, :291, :327 (block to warn or rewrite) -- approved (D21)
- Test edit: hooks/__tests__/pane-budget-gate.test.sh:144-186 (block to note) -- approved (D21)
- Test edit: hooks/__tests__/no-poll-loops.test.sh:228-230, :252-263, :299-308 (block to rewrite or warn) -- approved (D21)
- Test edit: hooks/__tests__/worker-ask-guard.test.sh:84-89 (block to added decoy) -- approved (D21)
- Test edit: hooks/__tests__/generated-read-guard.test.sh:49-50 (the bounded cases pass) -- approved (D21)
- Test edit: hooks/__tests__/builder-search-guard.test.sh:26-63 (block to hint) -- approved (D21)
- Test edit: hooks/__tests__/hook-on-failure.guard.test.sh:2-40 (its rule inverted: fail-open required) -- approved (D21)
- Test edit: scripts/__tests__/plan-tier.test.sh:29, :32, :56 (Panel order Sol first) -- approved (D21)
- Test edit: hooks/units-sources.test.tsx, units-panes.test.tsx, units.test.tsx asserts of the one-row band, the pane text and the status string (host Part 1's new views) -- approved (D21)
- Test edit: scripts/__tests__/unit-drive.test.sh:95, :108-112, :144-150 (run to launch counts; the NO-GO stop becomes a revision) and its stub :13-30, :24 (learns launch, wait, collect; `mainsha=`) -- approved (D38)
- Test delete: hooks/__tests__/checklist-guard.test.sh (its hook is deleted, C33) -- approved (D38)
- Test edit: scripts/__tests__/brief-template.test.sh:72-73, hooks/__tests__/resume-context.test.sh:21, :31-32, hooks/__tests__/ruling-log.test.sh:30, scripts/__tests__/checkpoint-context.test.sh:57-85, hooks/__tests__/context-clear-stop.test.sh:122, :219 (the checklist and Todo list asserts and fixtures go) -- approved (D38)
- Test edit: hooks/__tests__/context-clear-stop.test.sh:31-37 (stub answers run-current and run-list), hooks/__tests__/pane-budget-gate.test.sh:136, :211 (`env -u ORCA_TERMINAL_HANDLE`), scripts/__tests__/fixtures/builder-launch-resume-setup.sh:53 (`mainsha=`); harness only, no assert changes -- approved (D38)
- Test edit: scripts/__tests__/dashboard-built-seats.test.sh:71 (the `sources.todos` assert reads it absent) and scripts/__tests__/dashboard-view.test.mjs:719 (`'todos'` leaves the tile list), the dashboard card going with #553 -- approved (D40), pending the owner's yes (decision plan-commandeck-open-2026-11-02-visible)
## User-visible changes

- Guards: refused before, now run with a one-line note: an inline script writing a tracked file; an unbounded search (main's simple one capped at 200 lines); a call past main's clear line; a long or unreadable wait; a Builder's large search. Rewritten and run: a bare inbox check, a raw pane read with a handle, a picker without the decoy. Passes: a clean `worktree remove --force`, a bounded read of saved output, localhost text in docs and specs. A hook that times out lets the call through instead of blocking it.
- A push question no longer holds a closing pass or the merge.
- New /commandeck:maxreview skill.
- `seat.sh launch plan-judge-opus` is refused until Sol has judged as many rounds; the Panel runs Sol first.
- doctor: a new warning for a scratch file over 100 MB.
- Units pane, band and status line: a header with stage counts, spend and the 7-day gauge, a waiting-on-the-owner list, framed stage-coloured cards, a band of up to 3 rows, a status line led by the worst state, a `motion` option (off).
- A planning worktree with only Python caches is adopted; a plan-limit refusal names the unit brief; a Builder's plan judge opens in its own worktree; merge closes the Builder's task from a long-job pane.
- An Orca automation in the main checkout is no longer checkpointed or restarted as main, and its board.sh no longer binds main's run (r3). Main with no Orca run restarts as today; with a run whose coordinator cannot be read, the restart is skipped with one line (r3).
- A second lone read-only call in a row (strict tier, planner seats, Builders) is refused with a batch hint; before, a hint came after the third.
- A first Serena read draws no "serena is not running" note.
- The Builder's carry-over prompt names Unit, Cut, Tests and Open findings lines.
- Plan judges restate each section, ask for a smaller change and check every named item; review passes ask for a smaller change; the fix hand-off groups one flaw's findings.
- A launch from a plan whose files changed on main is refused, saying to judge it again.
- `break-run.sh <plan> <k> <file> <line>` breaks, runs and restores; it refuses a test already red and a leftover backup (r3).
- A merge of a plan with cuts left marks done cuts, names the next and tasks it; the open cuts' issues and the Builder's task stay open (r3).
- A picker whose decoy the guard adds is recorded in the decision ledger (r3).
- doctor, setup and CI flag more dead references.
- A reply past 3,000 characters naming no file is sent back once.
- The checklist rule and checklist-guard hook are gone.
- unit-drive.sh loops plan versions until the judges say GO, then launches the Builder; an open owner question in the plan pauses it until answered (r3).
- The units views show what each owner question blocks; no PC or dev-deploy element is drawn (r3).
- A fresh main whose old pane closed, or on a run with no coordinator, is no longer bound by board.sh: it is shown the exact `orca-ide orchestration run-use --id <run>` line and spends that one call (r6, #532's Expected).

## Question for the owner

None: Q6 and Q7 (D40, D41) are re-asked to the owner by name by main (decision plan-commandeck-open-2026-11-02-visible).

## Facts

- Inline write block; search rewrite and refusal; pane read block -- hooks/bash-guardrails.sh:82, hooks/bash-guardrails.sh:598-621, hooks/bash-guardrails.sh:786-798 (observed: 2026-11-01)
- Warn shape; clear-line block; --out parse -- hooks/pane-budget-gate.sh:170-171, hooks/pane-budget-gate.sh:87-89, hooks/pane-budget-gate.sh:39 (observed: 2026-11-01)
- Bare check block; rewrite shape; wait blocks -- hooks/no-poll-loops.sh:210-218, hooks/no-poll-loops.sh:411-414, hooks/no-poll-loops.sh:426-437 (observed: 2026-11-01)
- Force-remove rule; session exemption -- hooks/git-safety.sh:350-351, hooks/git-safety.sh:281-285 (observed: 2026-11-01)
- Fail-closed keys; the guard requiring them -- hooks/hooks.json:22-66, hooks/__tests__/hook-on-failure.guard.test.sh:2-6 (observed: 2026-11-01)
- Decoy refusal; recorder skips a decoy-less picker -- hooks/worker-ask-guard.sh:33-39, hooks/ask-records-decision.sh:34-35 (observed: 2026-11-01)
- Saved-output refusal; search-guard refusal and hint shape; localhost exempt list -- hooks/generated-read-guard.sh:46-50, hooks/builder-search-guard.sh:166-180, hooks/builder-search-guard.sh:113-115, hooks/edit-content-tripwires.sh:180-194 (observed: 2026-11-01)
- holds matches text; push ask lists units -- scripts/decision.sh:283-287, scripts/decision.sh:262-271 (observed: 2026-11-01)
- Guard review proposals, no header change -- docs/guard-review-2026-10-31.md:3 (observed: 2026-11-01)
- Wording lines and angles -- scripts/builder-codex-pass.sh:141-183 (observed: 2026-11-01)
- Panel order; judges in that order; gate and collect sites -- scripts/plan-tier.sh:60, scripts/unit-drive.sh:158-161, scripts/seat.sh:326-332, scripts/seat.sh:800 (observed: 2026-11-01)
- main-watch log, trim; doctor warn -- scripts/main-watch.sh:151-152, scripts/main-watch.sh:1621-1631, scripts/doctor.sh:16 (observed: 2026-11-01)
- Unit views; decisions in the snapshot -- hooks/units-sources.ts:289, hooks/units-sources.ts:319, hooks/units-sources.ts:343, scripts/dashboard.sh:561-573 (observed: 2026-11-01)
- Cache forgiveness; plan limit refusal; plan mark refusal; task close -- scripts/plan-worktree-close.sh:71-81, scripts/builder-codex-pass.sh:1604-1615, scripts/seat.sh:106-108, scripts/paths.sh:602-638 (observed: 2026-11-01)
- CPU bound and fence built; read-record content check built -- scripts/run-shell-tests.sh:317-364, hooks/read-record.sh:15 (observed: 2026-11-01)
- Test cap from the plan line only -- scripts/builder-codex-pass.sh:1569-1578 (observed: 2026-11-01)
- Coordinator: none tested; any-pane fallback; rebind; run file -- hooks/context-line.sh:18-43, hooks/context-clear-stop.sh:21, scripts/main-watch.sh:497-510, scripts/main-watch.sh:543-544, hooks/lib/project.sh:90-94 (observed: 2026-11-01)
- Advice only; tier gate; state line; own-line count; wiring -- hooks/batch-independent-looks.sh:160-217, hooks/batch-independent-looks.sh:41-42, hooks/batch-independent-looks.sh:75-76, hooks/batch-independent-looks.sh:93-103, hooks/hooks.json:101 (observed: 2026-11-01)
- First-call check notes, never refuses; Codex's six names -- hooks/pane-budget-gate.sh:164-175, scripts/codex-no-helpers/codex:24 (observed: 2026-11-01)
- Builder line exists and its text; its tests -- hooks/context-line.sh:18-29, hooks/__tests__/context-clear-stop.test.sh:302-313 (observed: 2026-11-01)
- Judge typed-prompt lines; prompt record; seat-launch near its cap -- scripts/seat.sh:508-517, scripts/seat.sh:647, scripts/__tests__/seat-launch.test.sh:179 (observed: 2026-11-01)
- LENS line; every kind gets it; FORMAT; class_sites and fix_groups callers -- scripts/builder-codex-pass.sh:164, scripts/builder-codex-pass.sh:1082, scripts/builder-codex-pass.sh:134, scripts/builder-codex-pass.sh:2376-2377, scripts/builder-codex-pass.sh:2454 (observed: 2026-11-01)
- Cap reads Builders only; judge record lines; hash match; reset to main -- scripts/seat.sh:401, scripts/seat.sh:469, scripts/builder-launch.sh:216-218, scripts/builder-launch.sh:392 (observed: 2026-11-01)
- break-run takes two arguments and runs the test as left; the hand-made break text -- scripts/break-run.sh:16-39, templates/_builder-brief-template.md:244-248 (observed: 2026-11-01)
- Merge finds the plan; DONE line; cleanup -- scripts/merge-unit-local.sh:535, scripts/merge-unit-local.sh:810, scripts/merge-unit-local.sh:803 (observed: 2026-11-01)
- dead-ref's five prefixes; no fence skip; CI audit -- scripts/instruction-lint.py:49, scripts/instruction-lint.py:198-214, .github/workflows/ci.yml:55 (observed: 2026-11-01)
- Stop list; reviewer marker -- hooks/hooks.json:109-117, hooks/context-clear-stop.sh:18 (observed: 2026-11-01)
- Checklist sites -- templates/main-session.md:120-124, templates/checkpoint.md:30-31, hooks/resume-context.sh:102, hooks/lib/context-clear-restart.sh:77, hooks/hooks.json:30-31 (observed: 2026-11-01)
- Judge stage today; seat_stage; collect exits -- scripts/unit-drive.sh:153-166, scripts/unit-drive.sh:128-134, scripts/seat.sh:768 (observed: 2026-11-01)
- Sol off runs Opus alone -- scripts/plan-tier.sh:57 (observed: 2026-11-01)
- New-work markers -- scripts/plan-check.sh:140, scripts/plan-check.sh:436 (observed: 2026-11-01)
- board.sh rewrites the run file and binds any unbound main-checkout pane -- scripts/board.sh:55-57, scripts/board.sh:76-77 (observed: 2026-11-02)
- Sibling lines land separately; no message-complete mark used -- hooks/batch-independent-looks.sh:164-169 (observed: 2026-11-02)
- serena-shared.test.sh uses stub servers -- scripts/__tests__/serena-shared.test.sh:3 (observed: 2026-11-02)
- Cleanup closes the Builder's task; PARTIAL read; squash Refs/Closes; issues closed after merge -- scripts/merge-unit-local.sh:153, scripts/merge-unit-local.sh:503, scripts/merge-unit-local.sh:506-507, scripts/merge-unit-local.sh:442, scripts/merge-unit-local.sh:727 (observed: 2026-11-02)
- Sweep completes records whose worktree is gone -- scripts/unit-close.sh:9-11 (observed: 2026-11-02)
- Judge prompt says a revised plan is not judged again; routing note says one round; driver flag -- scripts/seat.sh:514, config/routing.json:44, scripts/unit-drive.sh:122 (observed: 2026-11-02)
- Stop sends main one line via to-main.sh; stage log line -- scripts/unit-drive.sh:65-71, scripts/unit-drive.sh:127 (observed: 2026-11-02)
- Main task list card sites -- scripts/dashboard.sh:904-915, scripts/dashboard.sh:1170, dashboard/app.js:1296, dashboard/app.js:1807, dashboard/index.html:162, scripts/__tests__/dashboard-built-seats.test.sh:71, scripts/__tests__/dashboard-view.test.mjs:719 (observed: 2026-11-02)
- Pane-read block names read-verdict's lines argument -- hooks/bash-guardrails.sh:796 (observed: 2026-11-02)
- Recorder skips a decoy-less picker -- hooks/ask-records-decision.sh:30-35 (observed: 2026-11-02)
- Holds' id rule for a unit; finished builds carry unit, how, at, sha; finished cost map -- scripts/decision.sh:278, scripts/dashboard.sh:549, hooks/units-sources.ts:99 (observed: 2026-11-02)
- Break record read; seat pane helper -- scripts/break-run.sh:35-37, scripts/paths.sh:975 (observed: 2026-11-02)
- An unbound main-checkout pane binds by run-use; the run-file write -- scripts/board.sh:76-77, scripts/board.sh:54-57 (observed: 2026-11-02)
- IS_MAIN is a git-dir check only; the not-bound line names `orca-ide orchestration run-use --id <run>` -- scripts/board.sh:54-55, scripts/board.sh:79-81 (observed: 2026-11-02)
- rebind takes the run only when no live pane holds it -- scripts/main-watch.sh:494-504 (observed: 2026-11-02)
- A live pane is connected and not orphaned in the terminal list -- scripts/paths.sh:443-444 (observed: 2026-11-02)
- pp_run_coord prints empty both for a run with no coordinator and for a run not listed -- scripts/paths.sh:431-434 (observed: 2026-11-02)
- rebind and run-bound.sh take a run whose coordinator is empty; rebind refuses only on `?` or a live other holder -- scripts/main-watch.sh:503-504, scripts/main-watch.sh:541-542, scripts/run-bound.sh:31-36 (observed: 2026-11-02)
- The ledger keeps the latest snapshot per id; answeredAt is UTC to the second -- scripts/decision.sh:43-47, scripts/decision.sh:88 (observed: 2026-11-02)
- The wording block expands BLOCK_LEVELS, OPEN and CLOSE, set outside it -- scripts/builder-codex-pass.sh:126-128, scripts/builder-codex-pass.sh:138, scripts/builder-codex-pass.sh:141, scripts/builder-codex-pass.sh:173-174 (observed: 2026-11-02)
- The judge's "On a revised plan, recheck only..." sentence -- scripts/seat.sh:514 (observed: 2026-11-02)
- DONE prints HEAD's sha; MERGE_SHA is set only in the non-dry-run arm; set -u -- scripts/merge-unit-local.sh:810, scripts/merge-unit-local.sh:720, scripts/merge-unit-local.sh:568, scripts/merge-unit-local.sh:9 (observed: 2026-11-02)
- push-ask lists a commit with no merge row and refuses only a non-green check -- scripts/decision.sh:266-268 (observed: 2026-11-02)

## Plan change log

- 2026-11-01: first version; the guard list had arrived before the plan was written, so it is in the first version.
- 2026-11-02 r2: (1) Q1-Q3 answered yes, now D21-D23; Test edits and Merge cite them. (2) Host b4b00efee and 0c86f6054 reached host main: #532, #538-#542, #545-#553, #559 ported as C19-C34 with D24-D37, F4-F7, A7-A16, their Steps, Breaks, tests, Issue cases and Done lines; Closes 9 to 25; Waiting on the host fix keeps the 24 still waiting, one line each. (3) D16 and C13 gain the Sol-off arm. (4) Q4 (new test edits) and Q5 (new user-visible changes) open. (5) What can go wrong keeps five rows; the new cuts' bad input is one bullet each under it. (6) Planned size, New tests, Build order, Timed checks, C18 updated.
- 2026-11-02 r3: Q4 and Q5 answered yes (/maxauto), now D38 and D39; Test edits cite D38; Q6 (dashboard card) and Q7 (r3 user-visible lines) open.
- r3 Sol 1 [P1] board.sh takeover: D24, C19 and a board.test.sh case and Break; board.sh asks pp_is_main_pane before the run-file write (:57) and run-use (:77).
- r3 Sol 2 [P2] split arrival: D25, C20, A8 and F8; a refusal needs A8's message-complete mark, else advice only; case "a batched call whose sibling line lands late is never refused" and its Break.
- r3 Sol 3 [P2] connection proof: A9 is a live Codex review seat reaching Serena with a find_symbol hit; serena-shared.test.sh is name parity only (its :3 says stubs).
- r3 Sol 4 [P2] red baseline: D32 and C29 run the test clean first and refuse a red baseline; case and Break added; the 2-argument form unchanged.
- r3 Sol 5 [P1] open cuts closed issues: D33 and C30 read cuts at step 1, open cuts' issues join PARTIAL (Refs, not closed), the Builder's task stays open; F6 rewritten. Sol over host parity, as #545 says "does not close the unit".
- r3 Sol 6 [P2] cut format: the reader takes the `- C<n>` bullets plans already use, the evidence `C<n>: built` lines; Data design, D33, C30 and the What can go wrong bullet updated.
- r3 Opus 1 [P1] Question section gate: D37 and C34 read the plan's Question section each round, wait on plan-<unit>, write the answer in; two cases, a Break, #559 Body 7 now names it. Opus over Sol (Sol's table found no C34 gap) because #559 names the plan's own question.
- r3 Opus 2 [P2] "not judged again": D28 and C23-C25 make seat.sh:514's sentence driver-aware and update the routing.json:44 note; two seat-plan-judges cases.
- r3 Opus 3 [P2] placeholders: D19 maps each host field; pc, devSha and dest are not drawn; "what each one blocks" comes from the ask id by holds' rule; no element is a placeholder; two test names changed, one added.
- r3 Opus 4 [P2] in-place edit and SIGKILL: D32 keeps the backup at a fixed path, refuses a leftover one naming the restore, F9 names SIGKILL; the in-place choice is justified in D32; Claim reworded.
- r3 Opus 5 [P2] no-run case: D24 and C19 make no run at all answer main, as today; unknown only for a known run with an unreadable coordinator; case added; User-visible line updated.
- r3 Opus 6 [P2] todo panel: D36 and C33 delete the dashboard card with its consumers on Q6 (a), as a test edit needs the owner; case added.
- r3 Opus 7 [P2] hard-coded range: D15 and C12 add `# wording: begin`/`# wording: end` markers; marker case, Break and Claim.
- r3 Opus 8 [P3] scan scope: D36 names the scanned files and the three kept allow-lists; Claim reworded.
- r3 Opus 9 [P3] parallel hooks: D9 and C6 build the recorder change; A2 is now a live check of the build; two ask-records-decision cases and a Break.
- r3 Opus 10 [P3] Data design: line 46 excludes `mainsha=`.
- r3 Opus 11 [P3] D8 details: the rewrite writes `bash <plugin>/scripts/read-verdict.sh`, `--lines N` maps to `[lines]`; case added.
- r3 Opus 12 [P3] loop log: D37 names the `at` lines (unit-drive.sh:127) with time, version and verdict; case added.
- 2026-11-02 r4: Q6 and Q7 answered (a) under /maxauto, now D40 and D41; the Question section reads None:; C33, Steps and Test edits cite D40.
- r4 Opus P1 board.sh fresh main: D24 and C19 now bind when the coordinator is no live pane (a dead holder's lease, as rebind() :494-504); a live other coordinator still binds nothing; A7, Claim, #532 Done; case and Break "a fresh main whose old coordinator pane is closed binds the run and writes main-pane.txt".
- r4 Opus P1 / Sol 2 [P2] stale answer: D37 and C34 count a `plan-<unit>` answer only at or after the epoch in `drive-<unit>.asked` (`<sha256> <epoch>`, once per version), as host question_gate; the question-line wait too; Data design, Claim, bad-input row; case and Break "an answer from an earlier plan version does not release the pause". Judges agree.
- r4 Opus P2 half sentence: D28 and C23-C25 replace seat.sh:514's whole "On a revised plan" sentence under COMMANDECK_DRIVER=1; case "a driven judge's prompt carries no recheck-only sentence".
- r4 Opus P3 / Sol 1 [P2] `set -u`: D15 and C12 set `BLOCK_LEVELS= OPEN= CLOSE=` in wording.sh; its two print cases run under `env -u` of all three. Same fix from both; Sol's P2 taken, as the failing command is real.
- r4 Opus P3 range bullet: Data design, D33 and C30 read `- C<a>-C<b>` as each cut a to b, a cut on two bullets once, built only by its own `C<n>: built`; bad-input row; case and Break "a range cut bullet counts as each cut in it".
- r4 Opus P3 DONE sha: D33 and C30 print `${MERGE_SHA:-HEAD}` and name the plan commit on the DONE note; the push question's `(no merge row)` for it is not refused (decision.sh:266-268); case "the DONE line names the merge commit, not the plan commit".
- r5 Opus P2 empty coordinator: pp_is_main_pane splits 3 (run listed, coordinator empty) from 2 (run-list failed or run not listed, read from run-list itself as paths.sh:434 folds both to empty); board.sh binds on 3 and writes main-pane.txt, as rebind() (main-watch.sh:503, :541-542) and run-bound.sh:36; the hooks keep 3 as unknown; `<h>` is `unknown` on 2; D24, C19, bad-input bullet, Claim, #532 Done, two Facts; case and Break "a fresh main on a run with no coordinator binds the run and writes main-pane.txt"; New tests 179. Opus over Sol's GO: the failing input is real (main-watch-setup.sh:81 with an empty coord file).
- r6 Opus P2 board.sh takes an orphaned run for any main-checkout pane: on 3, and on 1 with the coordinator not live, board.sh binds nothing and writes nothing and prints the not-bound line (board.sh:81) with the reason and `orca-ide orchestration run-use --id <run>`; 0 alone binds; 1 with a live coordinator, 2 and a failed list unchanged; D24, C19, A7's last sentence, Claim, #532 Done, bad-input bullet, one Fact, User-visible changes (r6); the two fresh-main cases and Breaks renamed "...is told the run-use line and neither binds nor writes main-pane.txt", New tests unchanged at 179. Opus over Sol's GO (on r4): IS_MAIN is only a git-dir check (board.sh:54-55), so an automation at the repo root reaches the bind, against #532's Expected. D40 and D41 marked pending the owner's yes (decision plan-commandeck-open-2026-11-02-visible); Question section and the D40 Test edit say so.

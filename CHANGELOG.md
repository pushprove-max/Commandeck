# Changelog

## 0.61.1 -- 2026-10-29

### Docs

- The README is brought up to date with what the plugin does today, and now opens with two diagrams: who does what, and how a build earns its GO in the review loop.
- The README now covers the units view and its settings, the plan format, the test rules, the lockfile setup question and the standing worktrees you can keep.

## 0.61.0 -- 2026-10-29

### Reviews

- When a review finding needs a gate to check its input, the fix now refuses any input it does not recognise instead of guessing, so the same kind of finding stops coming back round after round.
- A review pass now checks that the build's notes are complete before it saves the work, so a pass never runs on a half-written record.

### Builds

- An answer to a Builder that is waiting on a question now reaches it straight away instead of queueing behind the wait.
- The slowest builder self-test runs faster.

## 0.60.0 -- 2026-10-28

### Builds

- A build can now go from plan to a running Builder on its own, with the planning effort matched to the size and risk of the work.

## 0.59.1 -- 2026-10-28

### Tests

- The plugin's own test run no longer picks up two sample files that one test uses as input, so the run passes again.

## 0.58.0 -- 2026-10-28

### Tests

- The plugin ships a test rules file. It covers never weakening a test, and what a test must encode: a test that cannot fail when the rule it guards changes is wrong, and a test is deleted or merged only when another named test catches the same failure.
- Builders read the test rules before they write, change or delete a test.
- Every reviewer judges each new, changed or deleted test by these rules. The rules are in the review prompt in full, so a reviewer that can only read the project still applies them.

## 0.57.0 -- 2026-10-28

### Main restarts

- When the typed resume prompt is not taken (a paired phone holding the pane), the restart opens a second pane with the prompt in its start command. The old main closes only once that new main has its checkpoint context.
- When both ways fail, or a new pane that got no prompt cannot be closed, the restart is not tried again: the dashboard raises a critical alert naming the command to restart main by hand. The alert clears once a main session starts with that resume prompt.
- A restart never stops a running helper agent. It waits for the agent, however long, and past the context ceiling it tells main to stop the agent or let it finish.
- Past the context line main can still record a question for the owner and stop a helper agent. Before, the line refused both, so a turn that asked the owner could not end.
- Past the context line, an allowed command reads its quoting as the shell does: a question or value holding an apostrophe (`'What'\''s next?'` or `"What's next?"`) passes, and a quoted value is no longer refused on macOS.

### Panes

- The worktrees whose panes are never closed and that the checkpoint does not list are one list, `keepWorktrees`, in the project config. A missing key keeps the standing worktrees the plugin creates (Research, E2EWalkthroughs, Fast-lane, Research-lane and Chief-of-Staff), so an existing project needs no change. Only an explicit empty list keeps nothing. Setup carries your list over as saved.

## 0.56.0 -- 2026-10-28

### Tests

- A background job counts as stopped only when its command has stopped, not just the shell that started it, so a retry never runs it a second time.

### Lanes

- The Fast lane will not land while main's checkout has a staged change. It reports a landing only when main's checkout matches the reviewed commit on every file the lane changed, and it names any other unsaved edits it left in place.

### Planning

- A plan needs one goal line of at most 200 characters, one line per step, and a facts list. Each fact names the file lines it rests on and the day they were read.
- A fact is refused at launch, before any judge reads the plan, when its file or lines do not exist, it cites another plan, or its date is not a real date up to today.
- A plan written in the earlier format still passes, with a warning to rewrite it in the new one. A plan that has a goal line, a steps section or a facts section is checked in full.
- Prose goes only under the plan's Why section, and each section has a size limit. A plan over a limit is refused, naming the section and its size.
- The plan judge reads the plan as a Builder who cannot ask, tries to disprove each claim and fact, and checks the plan against common practice for the problem.
- A unit over the size limits is split by default. Main keeps it whole only with a written reason.

### Reviews

- The closing review is a fresh reviewer that gets no earlier findings or fix history.
- A reviewer's test that passes does not close its finding: the Builder rules on it.
- Later fix rounds run at medium effort by default.
- A test is never weakened, skipped or deleted to make it pass.

## 0.55.0 -- 2026-10-28

### Units view

- The standing Fast lane and Research lane no longer show up as builds in progress.
- The cost for today now matches the dashboard's Cost today for the project. The line under it splits that total into merged units, units in flight, main, the standing panes and lanes, and the rest. When the day's cost is not available, the view shows the units' own total, marked "units only".

### Tests

- A retry on the same code can rerun only the test files that did not pass. A file that passed on exactly the same code is shown as passed without running again. Runs on the second machine are never skipped this way.
- A test run handed to the second machine keeps going when the connection drops. The failure message gives the run's id, so its result can be collected once it ends.
- A passing run on the second machine counts for the code it actually tested, not for whatever the checkout holds when the result comes back.

### Lanes

- The Fast lane and the Research lane may start helper agents on Sonnet or Haiku when the call names that model.

## 0.54.0 -- 2026-10-27

### Setup

- Setup now makes two standing worktrees beside the relay: a Fast lane for small work it reviews itself, and a Research lane that never builds. Main lands only the Fast-lane commit that was reviewed; a change made after the review waits for a new one. Both keep the one-hour prompt cache and are treated like the relay by the guards. Running setup again creates neither twice.

### Helpers and workers

- One command prints several files, line ranges, plan sections or search hits, and a reviewer's whole input bundle, in a single call.
- A background job started through the new run-and-return command hands back its exit code and last lines in the same call when it ends quickly; a longer one prints the exact command that collects them.
- In a worker, a search over the whole checkout is rewritten to a capped search instead of refused, and it keeps its own exit code. A wait loop is wrapped in a time limit instead of refused, when the call's waits fit the prompt cache.
- A wait loop that sleeps forever is still refused.

### Main session

- A foreground inbox wait is moved to the background instead of refused.
- One snapshot call now fills the checkpoint's goal, stage, next step and queue, and refuses until nothing is left to fill by hand. The first time main crosses its clear line, the snapshot is written for it, and main is not restarted until its goal and unit fields are filled. New queue items never reuse a number from the checkpoint main resumed from.
- Rarely needed startup and rule text moved behind short pointers, so every session starts with less text. When main's card does not fit the startup print, main reads only the card, not the whole file.
- If you saved a "drop this rule" or "keep my version" choice for a rule that moved behind a pointer, or for the reworded clear-line rule, save that choice again: the old choice no longer applies.

## 0.53.0 -- 2026-10-27

### Planning

- A plan or batch that describes placeholder UI is refused at launch, unless the line approves it, sits in a quoted block, or names the issue that tracks it.
- Plan checks read every Markdown code block form (backtick or tilde, indented or not) as a quoted block.

### Builders

- Helper agents may run on the search model when a call names it; any other model still runs as the configured one.
- The read-only Codex helper always works from a temporary folder outside the project, refuses to run inside any of its worktrees, and loads no rules files.

### Reviews

- Codex plan judges and reviewers start with sub-agents switched off.
- The typecheck before a closing pass has a five-minute limit. A run past it stops the pass and says the typecheck gave no result.
- A new build's first typecheck reuses the typecheck cache of a neighbouring build, so it runs about as fast as later ones. The reused cache never hides a type error in the new build's changed code.

### Merging

- Comments in screen code no longer count as placeholder UI, and "under construction" now does.

## 0.52.1 -- 2026-10-26

### Fixes

- Every new command added in 0.52.0 now answers `--help` with its usage instead of an error.
- The checks run again on the Mac's built-in shell, and a check that compared clock minutes no longer fails when a minute turns over mid-check.

## 0.52.0 -- 2026-10-26

### Launching builds

- Launch options now work in any position, before, between or after the unit name and the batch. An option the launcher does not know, an extra word, or an option missing its value is refused with the usage line, so a dry run can never turn into a real launch.
- A plan is checked by the same rules as a launch before any plan judge reads it, so no judging round is spent on a missing section or label.
- A plan names each mockup on its own line, and a launch refuses a plan whose mockup the batch does not carry.

### Builders

- Work added to a running build names a check for each item; work the branch already has is answered "already done" and not sent.
- A closing review pass waits for a green typecheck when the project sets one up.
- Helper agents run on the models set next to the Builder role: search helpers on Haiku, other helpers on Sonnet, enforced in build, planning and fix-round panes. Builders, planners and fix rounds are told to hand work to them, and the build review shows helper spend by model and flags a large build that used none.
- Builders are told to build only what the plan asks for, never a disabled or "coming soon" stand-in.
- Builders, planners and fix rounds can ask Codex a question, read-only, for a search or a second opinion. Each call has a time limit and an answer limit, names the model that answered, and says so plainly when it fails; the build review shows the calls and their time.
- Planners can now start helper agents. Plan judges and reviewers still cannot.

### Merging

- A build that changes screen code merges only with a side-by-side list, a screenshot that exists, or a stated reason that nothing visible changed. Setup asks which folders hold screen code.
- A merge refuses switched-off controls and "coming soon" copy that no plan or ruling asked for, and lists each one. The review treats them as serious findings.
- A merge closes the build's task, a build removed unmerged closes it as failed, and a sweep closes the ones left open before.

### Setup

- Setup denies built-in reads of the project's tracked lockfiles, whole or partial, one rule per lockfile name, added to the project's own deny list without replacing or repeating a rule. It is best-effort for the built-in search tools; shell search such as rg still works and is the way to look inside. Answer Allow to leave them readable.

### Build review

- Time a build was parked on purpose is cut from the review, and gaps with nothing running are shown apart instead of counting as work.

### Fixes

- A failed review pass no longer ends with an error on a Mac's built-in awk.
- The shared script file now says so at once when it is loaded from a shell other than bash.
- The watcher no longer posts "stopped without reporting" while a Builder waits on its own background job, for up to an hour.

## 0.51.0 -- 2026-10-26

### Review loop

- A review round that is missing a reviewer's verdict no longer clears an earlier serious finding: it counts as one still open.
- Once the pass limit is reached and no serious finding is open, a new pass is refused after the loop has stopped, and so is a pass over a change that touches only the plan. A round that was started again after an abandoned launch is judged by its finished run.
- The fresh closing reviewer now reads a clean copy of the branch with the earlier rounds' reports and notes left out, and the unit brief kept. The copy is removed when the pass ends, the merge accepts that pass, and its cost is counted with the build.
- A fix round whose findings touch separate files now lists them as groups that can be fixed side by side.
- A site marked fixed after a failed pass now has to say how it was fixed in every new round. A round handed off before this release keeps its records valid.
- When a pass refuses because a searched site is missing from the checked list, it now names the file that holds the full list of sites.

### Main

- A report of an older review round now says which newer round replaced it, and no next step is posted from a check that could not be read or that changed while it ran.
- A main that restarts is told about every seat run its checkpoint names that stopped with no result.
- The seat status shows when a pane is gone, and the rules say how to start a Builder again in a new pane.

### Builders and plans

- Builders now run on Opus at medium effort by default.
- A Builder keeps a table of its issues, so the units view shows each issue as built when its part lands.
- Before the first review pass a Builder runs the change for real and writes what it ran and saw.
- Plans now list the claims a reviewer should try to disprove, and plan judges ask whether a plan follows the usual practice for its problem.

### Releases

- A release is now published only after the CI run on that commit has passed, so a red commit no longer releases. A version whose CI was red is published by the next commit that passes. A version that was tagged but not published, because publishing failed, is published by the next commit that passes, even when the version did not change.

## 0.50.0 -- 2026-10-26

### Release notes

- Every past release note now reads as plain notes about what changed for you, with no file, script or issue names.
- A release whose notes name internal files, scripts, issue numbers or commits now stops before it is published and says which line to fix.
- The update keeps going when a version's notes break the style, and shows why. A version with no notes at all still stops it.

## 0.49.0 -- 2026-10-26

### Setup

- Setup now offers a recommended set of answers first and lists the options that set changes. The groups that follow are asked in order, and every option stays reachable.
- The recommended values live in one place, and `--recommended` and `--option` apply them without a question.
- Turning on the full test suite before the final review pass is refused when no test command is set. The choice is saved where /config reads it.
- Every value setup saves now follows one order: this run's explicit answer, then the profile or `--recommended`, then the saved value. `--bind`, `--port`, `dashboardBind` and `dashboardPort` now set the address the dashboard is installed at, where before a saved address won.
- Moving the reviewer or the judge to the other agent now resets a saved model that agent cannot run, where before setup refused.
- `--plan` on a machine setup has never run on no longer stops without a message.

### Review loop

- The most review passes a build may run, the lowest severity that holds a merge, and the fresh closing reviewer are now settings. Changing the blocking severity in the middle of a build asks for a new unit, because earlier passes can no longer be read under the new rule.
- A fix round now always goes to the Builder's pane, so the fixer setting applies to every round.
- Two review passes started at the same time no longer clash: one holds the lock and only it releases it.
- Before the first adversarial pass, every `Break:` line in a plan must name a test, a label and a command to run, and a build with a data design must carry a filled failure table. A small risky unit (under 150 changed lines) gets one judge instead of the panel.

### Builders and main

- A Builder launched from a pane in another checkout records that checkout, and a queued message to main says when no main pane was found there.
- An answer queued behind a busy Builder is checked until it is read, ten minutes at most, and ends "not acknowledged" with one follow-up to main instead of two different exit codes.

### Security and maintenance

- The dependency-addition guard now reads a command the way the shell does: an install after `cd x &&` or `;`, or inside a command substitution, still blocks, while quoted text and here-document bodies that only name an install pass. It is a tripwire, not a security boundary: an install handed to another program as text (`bash -c '...'`, `eval`, a here-document sent to a shell) is not read.
- A Builder pane refuses a hand-written commit, because the review pass commits what is staged. The refusal names a model co-author line when the message carries one.
- The leak test allows a build's unit name, an issue number and a commit hash, and now fails on a secret key shape. Names, paths under a person's home and ruling ids still fail.
- The leak test now fails on a spend figure: a dollar sum with cents, comma thousands or three or more digits anywhere, and a one- or two-digit sum in text. The dashboard's test fixtures, which hold made-up figures, are exempt for the figure only. A one- or two-digit failure says how to fix it: a shell parameter in text is written with braces, an amount in words.

## 0.48.0 -- 2026-10-25

### What you need to do

- Answer the prompt-cache questions again at your next setup. Three questions, `mainPromptCacheTtl`, `workerPromptCacheTtl` and `relayPromptCacheTtl` (`5m|1h|leave`), replace the old two, and an old `promptCacheTtl` in your project's Claude settings can be deleted by hand.
- Stop passing `--ponytail` or `--no-ponytail`. The ponytail add-on, its option, its bundled skill and its setup question are gone, and nothing replaces them. The rules audit flags a template that still names the flag.

### Units view

- A new units view shows live units, merges and test runs as a band, a side pane and a status line. `/units` prints the table, and `/units band|pane|status on|off` turns a view on or off for the session.
- Three options, `unitsBand`, `unitsPane` and `unitsStatus` (`auto|on|off`), set each view. `auto` is on in main and the Chief of Staff and off in worker and reviewer panes. The view appears only in a project set up with Commandeck.
- Test runs now keep a live table the view reads, every merge attempt opens its log with an `ATTEMPT` line, and merging a plugin unit now runs `claude plugin validate` and `claude plugin test` on the merged tree.

### Prompt cache

- The prompt cache is now set per role. Main's value is written only into main's own session settings, the workers' and the relay's into each worktree's settings, and `leave` writes nothing. The cache checker proves the worker answer.

### Review loop

- The Panel's second plan judge is now a read-only Claude judge on Fable at high effort. Its options are `planJudgeFableEnabled`, `planJudgeFableModel`, `planJudgeFableEffort` and `planJudgeFableFast`, and the old `planJudgeAstra*` options are read by nothing.
- The first fix round keeps the Builder's model and effort, though a `/plugin` setting or the setup question can still set Opus high for it. Setup's Fixer question lists "Same as Builder, then Opus high" first.
- A pass that names no P0, P1 or P2 now ends GO, so a P3 never holds the loop. From the fifth pass on record (the cap), a closing NO-GO that names an open P2 but no P0 or P1 ends the loop too. A P0 or P1 is never capped: one still open two passes past the cap prints `REVIEW STOP` and waits for your answer.
- The closing reviewer is handed the plan's decisions and accepted failure modes but no earlier finding. What is open at a stop is printed as `Open finding` lines, and the merge refuses until each class names an open issue. Counting passes and findings by severity across a project is not built yet.
- A closing pass's report carries one `Pre-review:` line for the steps that ran before the review.
- The plan's claims and decisions now reach the reviewer after the diff. A planner's instructions ask for a "What can go wrong" table, settled claims, and each cut's Produces and Consumes.
- A new command runs the post-fix checks at once: the named shell tests and, in a plugin checkout, `claude plugin validate` and `claude plugin test`. It reports each exit code, and any red fails the round.
- Rule text catches up: the unit, worktree and dispatch-ledger rules, resource safety, the adversarial-review lines, the startup file's pane rules, a Compact Instructions block in the global rules template, main's small-fix rule, the batch template's half-write and retry-ownership line, and every test run starting in the background whatever its length. Reviewers get the reopen rule, the failing-test default and a `Class search:` line under each blocking finding. A plan-only (design) pass is a pass of its own.

### Chief of Staff

- The Chief of Staff's unfinished-work stop hook now ships switched off: it stays in the plugin but nothing runs it.
- A pass that comes back NO-GO four times raises a `pass-loop` alert on the dashboard, and a new check compares the Chief of Staff's order file against its template.

### Safer worktrees and reports

- Force-removing a temporary worktree is allowed only for one this session added.
- A report for a unit whose worktree is gone now counts the unit's squash commit on main for `Lines changed`.

### Releases

- A release workflow now builds a release from a version's changelog section, and the update command shows the same notes. Nothing runs it yet.

### Security and maintenance

- An evidence heading that names an issue outside the brief no longer crashes the units pane and `/units`: only the brief's issues count as built, and the progress bar stays ten cells wide.
- The answer to a `REVIEW STOP` is matched by its stop id, and a unit the dashboard sees for the first time raises its verdict alert.
- Force-removing a temporary worktree is granted only while the session's claim on it still stands.
- The discard and reset checks read every abbreviation git accepts for a long option (`--forc`, `--har`).
- Six reworded global rules carry their `MADE_FROM` line, so your "keep mine" still holds after an update.
- The picker refusal shown while the Chief of Staff is live names the command that delivers the answer.

## 0.47.0 -- 2026-10-25

### Tests and merging

- Shell tests can now run on the PC. In a Mac linked worktree set up to hand off, the test run sends its files to the peer machine along with the worktree's exact tree, uncommitted work included, and the peer refuses a tree that differs. The files run there in a memory box and their result is the run's. A test file marked as Mac-only stays on the Mac, and the main checkout and the PC itself never hand off.
- When the PC cannot be reached, the files run on the Mac once. When the PC refuses, the run fails with exit 2 and runs nothing. When the connection drops after the files started on the PC, the run fails and the files do not run again on the Mac.
- A narrowed review pass says so. A review that read only the changes since the last pass ends its report with a `NARROWED GO` line, the done marker is written only after a GO that was not narrowed, and the merge's proof is one check run before and after the rebase.
- The dashboard decides "merged" from the branch's newest reflog entry.

### Review loop

- A fix round checks its new code against the plan. After a NO-GO, the next pass needs `## New code checked (pass M)` in the evidence file: each read, write or check the fix added, against the plan's Data design, What can go wrong and failure table. Its reviewers get that list. A class redesign now goes into the plan first and is reviewed alone, to GO, before its code.
- The Codex reviewer is handed the brief's work items. Its sandbox has no network and the host read only the issues a brief marked as closed, so a brief that listed its issues under `## The issues` left the reviewer unable to read them and it ended `BLOCKED: GitHub read failed`. The host now reads those items too.
- Review passes ask for other call sites. After a NO-GO, the next pass does not start until the evidence file holds `## Sites checked (pass M)` with a `Search:` line and a line per site, `fixed` or `not affected, <why>`.
- A finding's `Class search:` line, when the reviewer writes one, is run as a plain ripgrep search with no shell. A search that misses its own finding or hits over 200 lines owes nothing, and the hits go to the fix round, which must list each one in Sites checked. ripgrep (`rg`) joins the requirements, and a pass with no `rg` is refused rather than skipping the searches.
- A finding class that comes back after any earlier pass, a GO pass included, is a class stop.
- A launch now refuses a batch with no Data design section, a plan with no `Planned size:` line or no `What can go wrong` section, and a decision or accepted failure mode with no `Test:` line. A NO-GO of the plan judge on a plan under 150 lines goes on under main's rulings.
- The batch template gains `## What can go wrong`, and the plan author's instructions ask for the size, `Test:` and `Break:` lines.
- The fix hand-off says why it was not made. After a NO-GO the pass hands the fix to a fresh session only from the Builder's own pane. Any other case, and a failed write of the fix file (now written to a temporary file and moved into place), tells main with one line, `NO FIX HAND-OFF after pass <N>: <why>`.
- The fresh fix session takes its round from the fix file's name and records the fixer rule, model, effort and round in the seat record. Two asks are not built: there is no in-place `/model` switch after a NO-GO, and none on a plain handoff. The fresh session stays on its launch model.

### Reports and answers

- A report reaches main before main acts on a seat. A new round file is stamped, posted, and holds the seat's next step until the post is delivered, so a new round file takes three ticks (stamp, post, gate). The board's builder line puts the report first.
- Answers reach a waiting Builder. Answering a worker with no question id replies in the pane's own open question. Resuming an ask reads the full inbox first, so an answer an earlier read acknowledged without printing is not lost, and past its 9 minutes it sends main one "unanswered" question naming the plain answer command.
- An answer can now interrupt a waiting pane: it types the answer in with an interrupt only while it holds that pane's wait token, and the ask does not return until the send is done, so the interrupt never cuts work resumed between slices. A refused interrupt prints the plain command to send instead.
- The background follower still follows the log-tag check, because Orca's `delivered_at` stayed unset after an acknowledged batch (checked 2026-10-25).
- The messages to main from the Chief of Staff and from a Builder already took positional words and built the subject and body themselves, so the bug that was reported does not exist here. Two tests pin it.

### Main's picker and the Chief of Staff

- With the Chief of Staff pane live, a picker question is recorded in the decisions ledger and then refused, naming the ledger id and the relay command. With no pane found, the picker opens as before.
- A new stop hook holds the Chief of Staff's reply (main's, when no Chief of Staff runs) once when it leaves its own work undone ("haven't filed it", "want me to ..."). The second stop of a turn passes. This is the first part of a larger change, and its second part is still open.
- A worker's diff against main (and up to 20 untracked files) is printed once, before its first test run of a session.

### Security and maintenance

- A local fix is in this release: answering a worker detaches its background follower with perl's session call on every host, so the printed pid is no longer already gone on Linux. A plan-tier test now puts its Codex stub back before its effort check, and main's session settings file is ignored as a runtime file.
- The Codex sign-in probe now waits 120 seconds, and both of its messages say so.

## 0.46.0 -- 2026-10-24

### Fewer messages to main

- Main hears a thing once. A turn that ends on `VERDICT: NO-GO` sends nothing, because the Builder's fix round takes it, and a Claude seat's finish is not echoed when its `worker_done` is already in the run inbox. A question or refusal line is always sent.
- A block from the pane gate, the read tracker, the dependency guard or the suite-rerun guard no longer asks main for leave. It tells the Builder to record the item under `## Main-only (deferred)` and go on.
- A failed `/clear` hand-off to a fresh Builder session is tried once more before main is told, and the brief says "one status per decision".
- Main's watcher posts less. Heads-up notes go out as one digest per 30 minutes (`COMMANDECK_MAIN_WATCH_HU_DIGEST_S`), a note that repeats a held one is dropped, a stall or a wait posts once, and a finished or stopped seat whose `worker_done` is already in the inbox posts nothing.
- A seat's finish is sent under a per-seat lock with a delivery receipt, so a finish reaches main once whichever of the two senders gets there first. An unreadable inbox or log still posts: a duplicate, never silence.

### Review loop

- Review passes list every ordering at once. The first full pass and the behaviour angle both ask the reviewer to list and check every ordering of timers, background loads, retries, concurrent writes and tab switches, and to report each that fails.
- A finding class that returns a second time is fixed by design, with one fence or stamp and one test over every ordering found, and it sends main nothing. A third return is one question to main naming the class and the redesign. Main answers redesign unless you must make a policy call, and the wait script no longer tells main to ask you on the second return.
- A closing run wastes less. A new command tells you whether a test file is `unchanged` or `changed` by the files it reads. The Builder brief cites an unchanged file with its commit and ends with one complete run of every touched file on the tip.
- On a finding class's first stop, the hand-off asks for one background read-only sweep of every site where the flaw can occur, with a `Sweep: <file>:<line>: fixed|safe, <why>` evidence line per site.
- Builds state their data design. A batch brief needs a `## Data design` section (state added or changed: where it lives, who writes and reads it, when it resets, what a retry runs; or `none: <why>`), and a launch refuses a batch whose section has no line of its own. A batch with no such heading at all (written before 0.46.0) still opens, and its Builder writes the data design in the evidence file before its first edit.
- The Builder copies the data design into the evidence file, keeps it true, and keeps a `## Failure table` of every failure found. The first review pass reads the Data design before the diff. Every fix brief gets a `## Findings so far` section and names the classes the failure table lacks.
- A class that comes back (its second NO-GO) is redesigned in order: Data design and failure table first, then the code, then a pass over the whole branch, which the pass script now runs as `final`.
- The closing pass rebases first. `final` rebases the Builder's branch onto current local main before it reads anything. When main moved, it runs the shell tests that cover what the unit or main changed (not the full suite). A rebase conflict stops the pass with the files named and the rebase aborted, for main to resolve, and a red test stops it before the reviewer.

### Panes, worktrees and merging

- A pane closes only once, through one helper. Every script that closes a pane now logs the close and its cause, and a test's own `orca-ide` stub must be first on the path or the close is refused.
- A seat's task closes only when its Builder pane is idle and no question of its own is open without a reply in its thread. Collecting a working pane exits 4 and closes nothing.
- A relaunched Builder's record names its new pane and keeps the old one as `prior_pane=`. A seat run starts detached, because a pane's close ends a process still attached to its shell and spares an orphaned one.
- The merge cleanup keeps the worktree when unsure. It closes the unit's panes and stops its Codex helpers first, then archives the briefs. A pane that will not close, a pane list that cannot be read (or is empty), a pane still listed after its close, or any uncommitted path in the worktree after the panes closed holds the worktree (exit 5, the paths on the DONE line).
- The retry is the merge command with `--cleanup`: the cleanup step alone, from the unit's name, for a unit main already holds. The hold line names it and never a forced remove.
- A new command lists the tests that name a changed script, and `--changed [<base>] --callers` runs them. A plan author's instructions ask for a `Timed checks:` line when a plan adds a heavy fixture to a test file with time-bound checks.
- A merged unit is no longer drawn as a live Builder. The dashboard listed every worktree as a unit in flight, so a merged unit whose worktree stayed showed a FIXING card and a QUIET alert. A unit now leaves the in-flight list when committed evidence says merged, and a name reused for new work stays live. A pass whose round report is gone shows "verdict file gone", never a blank.
- A merge made by hand with no finished-builds line still reads live until its worktree is removed, so main's template now says to run the cleanup step after a hand merge.

### Builder launch and fix-round fixes

- Launching a Builder with `--from-plan` takes a plan revision that ends `PLAN-WRITTEN` or `PLAN-REVISED` as it takes `PLAN-DONE`.
- Closing and adopting a planning worktree skips ignored tool caches (the code-search cache, the scratch folder, and the local settings file even when it differs from the generated one). Any other ignored file still stops them.
- Main's watcher types one `Signal INBOX` line into a Builder pane that is idle or done and holds an unread message addressed to it, once per message, and again on the next tick when Orca did not take the typing.
- A fresh fix round retries a typing that Orca refused three times and says each refusal, says why it waits on a busy pane and for how long, and after `COMMANDECK_FRESH_ROUND_MAX_SECONDS` (default 1800) tells main the reason and the re-run line instead of waiting on.
- Main no longer asks you two questions before a build. It runs the plan tier check, uses the configured model and effort for each seat, and tells you in one line the tier, the trigger and each seat's model and effort. You change the trigger file or the `/plugin` settings, or say so in chat for that unit. A plan is still never a build order.

### Guards

- A new hook keeps main's checklist short. It refuses in main's session a ninth open item, a subject over 80 characters or holding an id (issue or PR number, message or task id, commit hash), and a mark of `completed`. A done item is deleted, never marked completed.
- The MCP gate waits at most 3 seconds, only in a session under 15 seconds old and only when no session found the server down in the last 10 minutes. A stopped or zombie server counts as missing. A server still missing blocks nothing: the worker gets one note to record it as deferred, and the dashboard raises an `mcp-down-<server>` alert for 10 minutes.
- The dependency guard blocks an edit that adds something to screen when the project's package file is not valid JSON, or the edit would leave it invalid, and names the file, not a package.
- The verdict reader now reads a macOS pane's environment whole, so a config path with a space no longer loses the handle.
- The dashboard prices a Codex response at the speed tier its file logged (`priority` is the fast rate). A file that logged no tier is priced at the standard rate and counted in `estimatedUsd`.

### `/autodecide`

- `/autodecide` now follows your own rules. The rules the model gets are your prototype, shipped fixed: their standing words, seven "how the owner decides" lines, the one-sentence never-decide list (a non-empty `autoDecideNever` adds a sentence after it) and the limits (any new feature flag included). Times are New York time, marked ET.
- `on` adds a line for the log to the metrics index. The rules are no longer built from the decisions ledger. The relay still records a decision with `--auto`, and a second run in one minute still gets its own log.

### Main waits less

- The answer command now returns at once in main's foreground. It sends the answer, prints the tag of a background follower and exits. The follower runs the log check and the retry, and tells main only when the answer was NOT delivered.
- Main's card gains a rule: any wait over about 30 seconds on external state runs in the background. The merge start and the seat run already returned at once.

### The ruling log

- The ruling log now holds the owner's rulings only. It logged every prompt of every session, so a log reached 220 MB, about 98% of it Builder, reviewer and Codex prompts and wake notices, and a lookup took minutes. It now logs a prompt only from main's checkout or the Chief-of-Staff worktree, never in a reviewer, and never machine text. Picker answers stay logged from every pane.
- A new one-off command moves the old non-ruling rows to an archive beside the log, with the log's counts checked before the live file is replaced. Nothing is deleted, and a full copy sits beside the log until the rewrite is done, so a run stopped midway loses no row. Run it once per project.

### Security and maintenance

- The first closing review passes ran the same fix rounds as part C's release, which left a note on paperwork after a long test run: it took 3 minutes in one part and 1 in another, under the 5-minute line, so no background-paperwork rule was added.

## 0.45.1 -- 2026-10-24

### Security and maintenance

- The dashboard's plan cards work under jq 1.7 (the CI runner's): one object value needed parentheses, and every plan card came out empty on Linux.
- The collector reads each transcript once per cycle again. A session's start time is noted in the one read the request pass makes and kept beside the request cache, so projects sharing one transcript root do not evict each other and a truncated transcript is read again from its start.
- The relay-pane Details rule, reworded in 0.44.0, keeps your own wording of the old rule, as every reworded rule does. So does the Checkpoint rule, which now points to the checkpoint template for its fields, its 5KB cap and its id.
- Tests: the hook count is 48 and the merge-rules count of plugin rules kept is 13. Part C's 14 did not match its own template. One more context-overhead script is listed as one that removes its own temporary folder.
- The release check no longer checks the README badge; the plugin test does, on every push.

## 0.45.0 -- 2026-10-24

### Setup

- Main can now start leaner. Setup turns off the ponytail rules and skill and the `ui-themes` and `mattpocock-skills` plugins for main only, in a settings file git never sees, and prints the `claude --settings` line to start main with. Workers never read it.
- A cut an earlier setup wrote into main's local settings comes out on the next setup run, and the doctor warns while it is there. A key you already set stays as it is and is named, uninstall removes only what setup added, and the doctor warns when a key it turned off is on again.

### Main's startup

- Main's injected card is at most 40 lines, and the size check fails past that. The resumed checkpoint is cut to 3,000 bytes, with a last line naming the full file.
- The awareness banner prints an open decision, a dead main watcher or the cage warning alone when the rest of the block is unchanged.
- Main's memory index at session start holds the active memories only: a memory marked archived moves its index line to an archive index. The lint that does this also finds the memory folder of a profile under `CLAUDE_CONFIG_DIR`.

## 0.44.1 -- 2026-10-24

### Security and maintenance

- The release check now fails whenever the README version badge differs from the plugin's version. The badge was left on 0.43.0 after the 0.44.0 release.

## 0.44.0 -- 2026-10-24

### Rules audit

- A new rules audit runs the deterministic rules check over the always-loaded files and also the templates, briefs, docs and hooks. It has new finding kinds: `unknown-option` (an `--option` key the plugin does not have), `retired-name` (a retired name, with what replaced it) and `dead-ref` (a rule path not on disk). Every row ends with where the rule is written.
- CI runs the audit, and setup's closing report prints the finding count as a warning.

### Auto-decide

- `/autodecide on|off|status` lets the relay pane decide for you while you are away. It survives a restart, shows a band and a status-line entry with the decision count, blocks the question picker, adds its rules to the system prompt and keeps a decision log.
- An auto decision is logged, recorded as `(auto-decided)` and sent to main in one step. Main checks such a message against the decisions ledger alone, so a retried send still lands after `off`.
- `autoDecideSeats` (set in `/plugin`) picks the seats. `autoDecideNever` in the project's Commandeck settings adds to the never-decide list, and setup keeps it.
- The relay line setup adds to auto mode names auto-decided answers, and an update replaces the old line.
- You reverse an auto decision with an ordinary relay order, and the auto answer stays in the row's history. Repeating the same `--auto` call resumes a failed send to main, and a second run in the same minute gets its own log.

### Security and maintenance

- CI now runs `claude plugin test .`.
- The shell test runner starts each test with none of the caller's `COMMANDECK_` variables except CI's two and its own. The merge check runs in main's environment, whose pane folder had sent a relay test's stub messages to the real queue.

## 0.43.0 -- 2026-10-24

### Builder questions

- A Builder can now ask main a question and wait for the answer in slices of at most 240 seconds, up to 9 minutes, then end its turn (main's answer is typed into the pane). It reads only the reply to its own question, and `--resume <id>` waits again after a slice. The Builder brief and the startup text name this command in place of `orchestration ask`.
- The send-to-main command prints the message id on its sent line. A send Orca refuses because the pane closed after the lookup is looked up once more, then queued (exit 3) and shown first when main starts.
- The restart helper records the new main's handle before it closes the old pane. A recorded handle that is no longer live falls back to the pane in main's checkout, or the folder named by `COMMANDECK_MAIN_PANE_DIR`.
- The Codex review pass prints a line every minute while the reviewers run.

### Profile settings

- Setup's changes to the settings file (the status line, the plugin options, and the auto-mode and permission rules it added) are put back into the active profile's file at every session start, for the profile `CLAUDE_CONFIG_DIR` names, when a launch overwrote that file. A value or rule you changed or removed since is kept.
- Setup never writes the shared home settings when `CLAUDE_CONFIG_DIR` is set, and uninstall removes only what setup added. The doctor names a profile file that was repaired, and when.

### Wake log

- Every attempt to wake main, the relay or a Builder is now logged with who sent it, who it was for, why, the result and any error. The log rotates at 1 MiB.
- The main watcher's results are `turn_started`, `no_turn`, `no_pane`, `unreadable`, `blocked`, `held` and `gave_up`. The senders write `sent`, `sent_blocked`, `refused` or `queued`, and the inbox waiters write `woke`.
- The same wake failure for 10 minutes tells the relay once. The watcher's own log drops a repeated line and keeps its last 512 KiB.
- Main's card shows the wakes of the last hour and the failed ones by result. The doctor fails when the watcher cannot find main's pane.

## 0.42.1 -- 2026-10-23

### What you need to do

- Nothing to change by hand. A saved `ponytail: true` or `false` is no longer read as `lite` or `off`: like any value that is not a level, it takes the default, `lite`.

## 0.42.0 -- 2026-10-23

### What you need to do

- Stop passing `--no-ponytail`; it is gone. Use `--ponytail off|lite|full|ultra` in setup, or set the level in `/plugin` config. A project that saved `ponytail: true` or `false` takes the default, `lite`.

### Ponytail

- The ponytail option is now a level, `off`, `lite`, `full` or `ultra`, and `lite` is the default.
- Builders run the saved level (the brief carries it, and carries nothing when it is off), and the worktree hook prints it.

### Main watcher

- `COMMANDECK_MAIN_PANE_DIR` names the checkout main's pane runs in, for a main that drives this repo's units from another project. Without it, that main was never found and no finished seat woke it.

## 0.41.0 -- 2026-10-23

### Dashboard

- The Units card says how each Builder's seats were launched (model and effort, the reviewer of the current round included) and shows a Builder's open question to main as a stop note. A unit whose task is open and whose worktree is gone is listed under Parked, units merged since the last push are listed, and every finished build is kept. The main card shows the last merge.
- Needs lists the open `P1` issues and the `proposed-decision` issues (the five lowest numbers, linked, with a show-all). The strip counts open `P1` issues, and the Issues card counts open issues by priority.
- The main and relay seat cards show whether the seat is working now, 12 hours of tokens, its seven-day totals, the cost of rebuilding its context, the relay's helper runs and the account. The role cost table gets a row for each.
- The Tests card shows the share of the Builders' clock spent in tests, and the seven-day average counts the seven days before today.
- A checkpoint whose carry-over was made but never followed by a restart raises a `checkpoint-rejected` alert.
- A project's page address now sends the browser to that project's page. A project's subagent ledger and hook fire log are read beside its other groups.

### Fixes

- Answering a waiting Builder question now sends a proper reply to it.
- The main session's rules say a reply the duplicate-agent guard blocks is never dropped.
- The batching nudge is said once a session, and the doctor warns when `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` is set for main.
- The reviewer pass records the model and effort it used.

### Context overhead

- A new command replays one scripted main session through the plugin's hooks and prints the bytes each one attaches.

## 0.40.1 -- 2026-10-23

### Security and maintenance

- The restarts reader finds a session's transcript under `CLAUDE_CONFIG_DIR` when it is set, not only in the default home.
- The setup-gate test counts the three search-log hooks that 0.40.0 registered.

## 0.40.0 -- 2026-10-23

### Fixes

- The hook probe gives a hook an absolute `HOME` under a relative `TMPDIR`, and removes its scratch folder when interrupted or stopped.
- The local merge command runs from another repository or by a relative path.
- The merge train runs no dry-run pass; the real merge's first step refuses a unit instead.
- A ruling logged under the other spelling of main's path is now found.
- The relay ignores its own sends under `--from` in any letter case, and clean Chief of Staff check readings say so.
- The merge's deletion check lets a whole directory go when the brief or a plan it names lists it once as a directory, with the plan read as committed at the fork point.
- The relay's wake text is capped, with a pointer to the full row. A Builder's question that is for you reaches the decision queue from the relay's poll.

### Review loop

- The fix hand-off asks for the existing cases to be rerun with a trusted state swapped in.
- The round file records the pass kind and its start and end, and the dashboard shows GO and NO-GO per pass kind and the minutes in review.
- An escape row records its finding class and where it was caught.

### Dashboard

- A Tests card lists test runs going now and finished ones, with a stall flag.
- A network bind now has a login over HTTPS, and `--install` refuses a network bind with no password stored.
- Main's events add a `main-compact` alert and a `carry-failed` alert that the relay wakes on. Both end at main's next restart.
- A restarts report shows restarts per day, the median checkpoint size, the median context after a restart and the checkpoint's share of it. The stop hook logs the checkpoint's size after an automatic carry.
- A Home phone tab, the project name as the page title, the Builder cap on the Units card and per-group collect seconds are new. The dashboard docs gain a "Switching from another collector" section.

### Search log

- A search log records each search a session makes and reports how often one is followed by a read of the file it found.
- A new doc evaluates Orca's Auto mode against the plugin's guards.

## 0.39.2 -- 2026-10-23

### Security and maintenance

- The seat tests no longer need Codex installed on the machine that runs them. Their shared fixture puts a stand-in `codex` on the path, so a Codex seat is not refused as "not installed here" on CI.

## 0.39.1 -- 2026-10-23

### Security and maintenance

- CI is green again after the three earlier merges. The merge test's fixture gives the repo an origin and a `gh` that answers the GitHub reads a review pass makes on the host (the issues a brief closes, and no pull request).
- The two merge-lock guard refusals now name the command to run instead: `kill <pid>`, and the plugin reinstall.

## 0.39.0 -- 2026-10-23

### Review loop

- A review finding now blocks the merge only when normal use would hit the bug. This is your ruling of 2026-10-23, and it replaces 0.29.0's every-finding rule.
- A finding that needs an agent deliberately bypassing a guard, or an odd setup, is a one-line known gap in the evidence file and does not block.
- The reviewer prompt asks for such findings under a `KNOWN GAPS:` line with no level and no class tag. A pass with only known gaps ends GO, and a GO beside a tagged finding is still a NO-GO.
- The global rules, the Builder brief template and the review-loop doc state the same rule.

## 0.38.0 -- 2026-10-23

### Codex update prompt

- Launched Codex panes no longer wait on Codex's "Update available" prompt. Setup turns off the update check at Codex startup, keeps the key if you set it, shows the change in the `--plan` preview, and uninstall takes the line out.
- Setup, the update command and the doctor run `codex update` when a newer Codex is out and say so. A failed or hung update (stopped after 300 seconds) is reported loudly, under "Needs you" in setup, and the run goes on with the current version.
- A pane that still opens on the prompt is answered Skip within a bound, and the answer is logged. One that stays on it ends its launch `phase=failed`, naming the prompt.
- The doctor reports the update check and the installed and latest Codex versions.

## 0.36.0 -- 2026-10-23

### GitHub access for every seat

- Every seat can now read GitHub, and a seat that cannot is not launched. The cause was measured: the Codex read-only sandbox has no network, while the `gh` sign-in is visible in every sandbox.
- The plan judges now run Codex's read-only permission profile with network on, so files stay read-only and `gh` reaches GitHub. They run with network on and your `gh` sign-in, so they can write to GitHub and reach any host. You accepted that, and every guard still runs in their panes.
- Before a seat opens, the launch makes one `gh repo view` the way that seat would, and refuses with the reason: no network in the sandbox, no credentials visible in the sandbox, not signed in to gh, or no GitHub remote. Main's restart makes the same read and, when it fails, leaves the old pane up.

### Review loop

- The review pass makes its GitHub read before any reviewer starts, whether or not the brief lists issues to close.
- The Claude reviewer gets `gh issue view`, `gh pr view` and `gh pr checks`. The Codex reviewer, whose sandbox the Codex plugin fixes without network, is handed the live issues the brief closes whole (body and comments), every issue or pull request they link, and the pull request state, all read on the host.
- A reviewer reply that ends on a `BLOCKED: GitHub read failed:` line refuses the pass, and that round can run again. The line anywhere else in a reply makes it a NO-GO.

### Seats

- A seat that loses GitHub mid-task prints `BLOCKED: GitHub read failed: <command>: <first error line>`, which wakes main like a `QUESTION:` line.
- The doctor reports GitHub read per agent, sandbox mode and seat environment.

## 0.35.0 -- 2026-10-23

### Merging

- A running detached merge is now visible, guarded and not duplicated. While a merge holds main, it records the unit, the reviewed commit, its process, start time, stage and log, and removes that record on every way out. A dead process is a stale lock and blocks nothing. From main's foreground the merge prints `running detached as pid N; watch <log>`.
- A request to merge a unit at a commit that is already running or waiting on the lock is a no-op that says so (exit 4), on the hand path and in the main watcher's automatic merge. From main's foreground the request is queued before it detaches, so a duplicate is refused at once and never empties the running merge's log. A duplicate leaves the running merge's steps in place.
- The "staged work changed during the run" refusal stays hard, is now tested, and its text names a changed index as a cause.
- The startup text and the first-build guide tell the orchestrator that the merge detaches, how to wait on it (its log or the message it sends), and never to re-run it.

### Merge lock guard

- A new hook refuses `git stash`, `checkout`, `reset`, `clean` (and the other commands that move main's tree or index) and edits of files in main's checkout while the merge lock is live, naming the running merge. Each git call is judged on the checkout it changes, whatever way the command points git at it. From main, a command on a Builder's worktree is that worktree's.
- The guard checks a redirection's or an edit's whole file, links followed, and main's search takes only options that read. A file git is given to write is checked the same way, through its environment variables and the arguments of a git call that writes.
- While the lock is live, a command in main's checkout may hold no `$` and no backtick, and `printf` takes no `-v`.
- Accepted gaps: an argument built from data (a `$` value, quoted prose, a glob) or a link the same line makes is not seen. Sending to a terminal from main is not seen, nor is a program git's config names (an external diff, a text filter, a file-system monitor, a pager, a signing program). Outside main's checkout the guard screens only the git calls a command types, so code the command builds from data is not seen. In main's checkout too, script text fed to `bash` or `sh` in place of a script file is not seen.

## 0.34.0 -- 2026-10-23

### Setup

- Codex panes no longer sit on the "hooks need review" menu when another tool's hook changed. Setup asks once, with the saved answer first, "Trust every hook in this Codex home before each Codex launch?" (`--trust-all-hooks on|off`, saved as `trustAllHooks`). The `--plan` preview lists the hooks it would trust.
- With yes, every seat launch and every review pass trusts every hook in the Codex home again right before Codex starts. With no, only the plugin's own hooks are trusted, as before, and a pane that still opens on the review menu ends its launch `phase=failed` within the idle wait, naming the hooks and the fix.
- The doctor now checks every hook in the Codex home and names the ones not trusted or modified.

## 0.33.0 -- 2026-10-23

### Setup

- Setup's own preview and apply pass the dependency guard again. The plugin's setup command is recognised in any one version folder of the plugin cache, so a hook from one plugin version no longer blocks the setup of another.
- A here-document body that only mentions install commands is no longer blocked beside a `cd` or `mkdir`. A body is skipped only on a line of one fixed shape, so a body that a shell, a group, a pipe or a quoted argument could run is still read as code.
- Every one-line question in setup offers 2 to 4 options, so the question tool no longer drops "Worker cuts", "Keep words", "Merge check" or "Relay voice". A failed question call is named with its error, never answered as "None".

### Builders

- The Builder handoff line accepts `140k`, `140K` and `140000`.

## 0.32.0 -- 2026-10-22

### Global rules

- The global rules now carry the reviewer rules: one full scope for every reviewer; a finding names file, line and the failing input, and a P0-P2 finding a failing test; read the diff and brief before the evidence.
- They also say: no `ponytail` tag in comments, one unit per worktree split by code area, stop and reconcile on an unknown worktree, commit or process, and no duplicate agent.
- They add planning rules: a freshness pass, integration surface and siblings, review questions before code, evidence as you go, the anti-over-engineering gate, and acceptance that names the test file and cases.
- The startup text adds: own your scope, fix every copy of a bug pattern, never work round a refusing check, and confirm an irreversible action.

### Review loop

- The Codex and Claude review prompt tells the reviewer to read cold, keep to the diff and its callers, attach a failing test to a P0-P2 finding, and follow the brief over the startup file.
- Each of a first pass's three reviewers leads with its own angle and is handed all three, so no angle rests on one reviewer.

### Builders

- The Builder brief template maps the code with 3-4 read-only helpers before the first edit, and gives an editing helper its own child worktree.

### Merging

- An issue the batch brief lists to close is carried into the merge commit, and the merge closes it. The merge closes only the unit's work items: the list the launch dry run prints and writes at launch, never a parse of the brief at merge time.
- Any other issue the brief text names to close (a quoted example included), and every issue of a unit launched without that list, is printed as a by-hand `gh issue close` under NOT CLOSED, and the merge ends with code 3.

## 0.31.0 -- 2026-10-22

### Security and maintenance

- Main's shell tests pass again after several merges met. Three tests were fixed and the product did not change: one built its data in a way the jq version CI uses refuses, one counted a new plan-reference line as a plan, and one hook comment read as a blocked message.

## 0.30.0 -- 2026-10-22

### Plan seats

- A plan seat that reported its finish in its own message to the run or main ("Plan revised", a `PLAN-DONE` line), or committed a new plan since its latest prompt, now counts as finished, not "stuck" or "stopped". Main's watcher, the seat wait and collect all read it, and collect closes the pane.
- A report quoted in a fence or under a `QUESTION:` or `BLOCKED:` line, one from before main's follow-up, or one made while the turn still runs is not a finish. A report stands in for `PLAN-DONE` only, never for a verdict.
- When the plan is committed and the turn ended without `PLAN-DONE`, the Claude seat's stop hook asks for the line once.

### Messages to main

- A seat pane's turn end, a Builder's own Codex pass included, sends main no "turn complete" echo. Collect sends a finish only when a wait claimed it and the seat did not report it itself.
- A `QUESTION:` or `BLOCKED:` line at a turn's end always reaches main, once. A seat that stops silently is still caught by the watcher's and the seat wait's own timers, and their alert now shows the pane's last words.
- Main's watcher and the commands that message main always send with a sender, main's pane or else the run's live coordinator. Orca had refused every watcher task and message when it listed main's pane with no agent.
- A message from the relay's pane (any pane in the Chief of Staff worktree) always wakes main and prints among the wake's own lines, whatever its type, with or without a ruling id, and whatever `wakeKinds` says.

## 0.29.0 -- 2026-10-22

### Review loop

- Every review finding, P0 to P3, now blocks the merge and is fixed in the unit. The P2 tail is gone: no narrowed-pass acceptance, no "Open at merge:" lines, and no issues filed at merge.
- A finding main cleared is handed to the reviewer as out of scope. It never turns a NO-GO into a merge.
- A reviewer's GO that names any finding is a NO-GO, and after any closing NO-GO the next `review` runs as the closing pass.
- One finding rule now applies to every reader: the merge gate, the hand-on to the next reviewer, the tests per finding and the repeat-class stop all count a line with a P0-P3 level in any form, or a `(class:` tag with no level.

### Merging

- The merge command drops `--area`, `--milestone` and exit code 4, and the merge queue no longer goes on past an exit 4. The command that filed open findings at merge is removed.

### Dashboard

- The dashboard no longer shows findings open at a merge. A finished build has no "Open at merge" line or amber Merge step, and the needs card no longer counts open P1s on finished builds.

## 0.28.0 -- 2026-10-22

### Review loop

- Red proofs are retired. The Builder brief no longer orders them, their command is gone, and a fix-round hand-off names each finding's test and run command only.
- A pass no longer refuses a new guard test for a missing `Mutation-verified:` line and puts none in its commit. The merge no longer carries one into the squash message, and a branch that still has one merges.

### Rules and briefs

- The Builder brief, the batch brief and the global rules follow the owner's current workflow: every review finding, P0 to P3, blocks the merge, and Done is a closing GO that names no finding.
- New rules: send main a question and keep working on what it cannot change; a finding against an owner ruling goes to main; read the inbox with `--ack`; never overlap the closing run with a long run; one test per bug class; a test only for a real regression; name what a new flow step catches; comments carry no credits or P-levels; main may raise a Builder's effort, never lower it.

### Default models

- A Builder now runs Sonnet high (was Opus medium), and every fix round runs Opus high. The first fix round kept the Builder's launch, and `fixerFirstModel=builder` and `fixerFirstEffort=builder` still do that.
- Main runs at medium effort, which setup now writes to main's settings when `orchestratorEffort` is unset. A project's own routing settings keep their seats, and setup's questions recommend the new defaults.

## 0.27.0 -- 2026-10-22

### Waking main

- Only actionable messages wake main. A nudge whose unread mail is all status notes or heartbeats is dropped with no turn spent, and the notes show under "held notes (did not wake you)" at the next real wake, main's own notes included.
- Actionable messages that arrive within one window wake main once, counted across Orca's nudges and the watcher's typed wakes. Each wake that passes carries a silent-wake line: a wake with nothing for the owner ends with no text to them.
- A merge the watcher lands now tells main once. A detached merge's or suite's exit notice is a question, and a heads-up relay is a status note.

### Settings

- Two new `/plugin` options: `wakeKinds` (default `worker_done,escalation,question,decision_gate,merge_ready`) and `wakeWindowSeconds` (default 60; 0 wakes at once).

## 0.26.0 -- 2026-10-22

### What you need to do

- Set your role settings again as options. Role settings an older setup saved in the project's Commandeck settings are no longer read.

### Roles

- Seven roles are left: orchestrator, plan author, the two plan judges, builder, fixer and Codex reviewer. The second plan author, the Claude judge, the Claude reviewer, the design co-author, the platform audit and the three plugin agent files are gone.
- A Panel is now one plan author and both judges. A `--risky` launch opens the Builder at once and its merge waits on three reviewers.
- Helpers are the built-in types: `Explore` runs on Haiku and `general-purpose` on Sonnet. The model guard asks for a type when a call names none.

### Fixer

- A new fixer role runs the fix passes after a review: the first one on the model and effort the Builder was launched with, the later ones on Opus high. The `fixer*` keys change both, and `fixerEnabled=false` keeps every fix pass on the Builder's launch.

### Settings

- Each role's model, effort, agent, on/off and fast tier is now a `/plugin` option, read by one checked reader. A value a role does not take is refused, naming the option. The reviewer and both judges can run on Claude by their agent option.
- Setup takes `--option <key>=<value>` in place of `--builder-model`, `--builder-effort`, `--codex-model`, `--plan-models`, `--plan-fast` and `--codex-fast`, and writes the main session's model and effort.
## 0.25.3 -- 2026-10-22

### Security and maintenance

- Fifteen plugin test cases that another named case already proves are gone, so the suites run fewer duplicate checks.
- The platform audit's "no duplicate answer" case now fails when the verifier stops requiring the duplicate cell. Before, it passed with that rule removed.

## 0.25.2 -- 2026-10-22

### Security and maintenance

- The fresh-session pass test no longer fails on a fast CI runner. Its long-pass case sets the threshold below zero, so a pass that ends in the second it started still counts as long.
- The pass tests' shared fixture clears `CLAUDE_CONFIG_DIR`, so a run inside an Orca pane uses the fixture's stub Codex plugin, not the real one under that profile.

## 0.25.1 -- 2026-10-22

### Main's restart

- A past-line marker left behind by a compaction or a restart that never came no longer blocks main's tools. The gate reads the current context and clears a marker under the line.
- On a first run with no checkpoints folder, the past-line marker is still written, and a marker that cannot be written is reported instead of letting every tool through.
- The restart carry looks up each `done when:` ref once per run, reads the decisions ledger once, and all its lookups together, decisions too, stop after 30 s.
- The carry walk gives each open item the distance of its nearest owning file, with no search per closed key, so its work and memory grow with the chain, not its square. An item one near branch closes and a longer branch keeps open is now carried at its owner's distance.

### Relay

- The relay's "owner quiet" minutes count only prompts typed at the root of main or of the Chief of Staff worktree, not worker prompts such as the watcher's `Signal WARM`, wherever the workspaces folder sits. A prompt from a subfolder of either no longer counts.

### Security and maintenance

- Comments no longer carry personal names or ruling ids.

## 0.25.0 -- 2026-10-21

### Setup and settings

- Setup asks the Builder's effort right after its model and recommends High for Sonnet. The doctor names where the Builder's model and effort come from, and those two `/config` options default to `project`, which keeps the project's answer instead of hiding it.

### Main's restart

- A restarted main is blocked once with the count of dropped items and the command that lists them, not the whole list. On the second stop the missing items are copied into the checkpoint and main restarts. One close line closes one item, with its own reason.
- The second-stop copy keys items by subject and reuses the one unresolved Queue heading, so restarts add no duplicates.
- The restart checkpoint closes finished items itself (`done when:` an issue closed, a decision answered, a unit merged, a commit pushed), keys Queue items `Q-<n>`, has a `dedupe` command, and moves items past ten generations to an aged-out file. The stop hook logs the checkpoint's size.
- The stop hook logs the minutes since the last restart. Nothing alerts on the "carried automatically" lines.
- On a 200K window main restarts at 140K, under the ceiling of 165K, and a Builder clears at 140K. The context count includes the last turn's output.
- Past its line, main may only write its checkpoint: every other tool call is refused until it restarts.

### Merging

- A unit that passes the gate (a final GO on its tip, a clean tree, no open owner decision, no `Merge: hold`) now merges itself into local main, and never pushes. A unit left waiting is gated again at the next tick.
- A merge reuses the closing pass's green suite when that run tested the merged tree itself (same tree hash). `--train` on the merge queue tests several units' combined tip once and bisects on red.
- A brief's `## Post-merge` lines run after a green merge when they are on the allow-list. Any other line is refused with exit 5.
- Redundant steps are removed: the rung line, `--verify` run twice per tip, and a plan revision after a GO verdict.
- A new CI watcher watches a commit's CI runs and reruns a failed run's failed jobs once. A new push-ask command asks the owner to push, and refuses when nothing is to push or a merge's check is not green.
- Planning scratch files in the plan worktree are moved aside and no longer block the Builder launch.

### Messages and relay

- Routine inbox items (a landed merge, a repeated heads-up) go to a digest instead of waking main.
- The relay runs a new 50-minute timer check that names a down watcher, prints held FYI notes and counts missed messages. With the owner quiet for 30 minutes the relay opens no picker.
- An owner-bound Builder question is recorded for the owner at once, not behind main.
- The board no longer prints the host project's chain-host, offloaded and placement-wait lines.

## 0.24.0 -- 2026-10-21

### Dashboard answers and collector

- An answer the dashboard could not send says why, gives up after its tries, and can be cleared from the card. It is no longer sent again on each refresh forever.
- Typing in a decision's answer box no longer hides new decisions and notes: the list is redrawn around the box.
- A project named `__proto__` no longer breaks the other projects' answers.
- A "Restart collector" button on a page on this machine restarts the collector service, at most once a minute, and the page shows the last cycle's time.
- The collector reads only what changed since its last cycle: transcripts, guard-block logs and Builder sessions from stored offsets, and one terminal list per cycle.

### Dashboard cards

- New card "Tokens per unit, 7 days": each unit in flight or finished this week by cost, Claude and Codex apart, its stages behind a toggle.
- A merge writes one row per unit to a unit ledger: rounds, verdicts, seats and tokens. New card "Review loop, 7 days" lists the merged units, most rounds first.
- A new ledger command tags an issue a unit's review let through, and the review card lists the escapes.
- The Issues card shows the issues opened and closed in the last 24 hours and a 7-day sparkline of both.
- Alerts that cleared in the last 24 hours are listed, folded, under the alerts card with their start and clear times.

### Setup and profiles

- A project can move from another collector to the plugin's: the dashboard command's `--import <folder>` takes its limit history, panel layout and cleared builds. A fresh install keeps the scratch and workspace settings, and the first project registered becomes the home project.
- Claude's files are read from `CLAUDE_CONFIG_DIR` when it is set: transcripts, sessions, settings and the account file, in the scripts, the hooks and the collector.
- Uninstall takes the plugin's rules, /config options and status line out of every profile setup wrote to, and gives each profile its own status line back. A move to project scope takes the rules out of every profile.
- Ledgers and caches reach jq as files, so a long ledger no longer fails with "argument list too long".

## 0.23.0 -- 2026-10-21

### Rules and orders

- An exception, allowlist or exemption entry in a guard or its test stands only when its test proves it. The rule is in every worker's rules and the Builder's brief.
- Only the owner's yes that names the unit or each issue in its scope is a build order. A launch's `Order:` line quotes it, and filing an issue or approving a lesson is never one.
- Scope added after the first review pass is a follow-up unit, unless main passes `--small --reason` for a change under about 50 lines.

### Review loop

- A `review` pass whose GO could not merge runs as the closing pass, and says so. A pass that ran long and ended GO hands the Builder to a fresh session, as added work does.
- A second NO-GO on the same finding class asks the Builder for an approach that fixes the whole class. A class-stop fix uses one retry path, and its test removes each piece of state between two runs.
- Each finding in a fix hand-off names its test file, its case filter and the command that runs it.
- A fix round never changes a behaviour the owner has an open question on. The fix hand-off lists the open decisions that name the unit, and the merge refuses while one is open, read again just before the commit.
- From the second fix round on, the Builder's fresh session runs on Opus.
- The test runner names every failing case (first part of this change).

### Builders and seats

- Every seat verdict and every lone exit notice reaches main.
- A new seat run command launches a seat, waits, collects and prints one line back.
- A new Builder launch option, `--from-plan <unit>`, takes a judged plan to a live Builder in one call. It installs on main only the plan the judge read, or the plan author's revision collected `PLAN-DONE` after a NO-GO, and refuses a GO beside another judge's NO-GO on the same plan.
- The new `maxBuilders` option in `/config` caps how many Builders run at once over all units, counted under one admission lock. An exited Builder does not count.
- Seat and Builder panes carry their role and unit as the pane title.
- A Builder that stopped without a DONE line or a verdict is nudged once before main is told, and at most twice per pane. A Monitor wait counts as test time in the worktree review.

### Security and maintenance

- Tests run under the merge lock no longer hold it after the merge ends.

## 0.22.0 -- 2026-10-20

### Dashboard

- The dashboard has a card for the main session and one for the Chief of Staff session: context, today's tokens and cost, the 7-day daily average, and today's restarts with the average gap between them.
- A decision can be answered from the dashboard's "Needs me" panel: its options show as buttons, the default is marked, and an "Other" box takes free text. Only a page on this machine can send an answer, and the phone view stays read-only.
- The first answer wins, the ruling is logged, and main (and the relay) are told. A message that could not be sent is listed on the card and sent again on the next refresh.

### Settings

- The settings that are the same in every project are also the plugin's `/config` options: Builder model and effort, review rounds, closing pass, the prompt cache of main and workers and of the relay, ponytail, dashboard address and port, and the full suite before the final review.
- A `/config` answer beats the project's, setup fills the empty ones from its answers, and the doctor names where each value comes from. This needs Claude Code 2.1.271 or later.

### Security and maintenance

- On Linux, main's startup context no longer loses the lines before its queued messages (the persona, the plugin folder). The startup hook now appends the messages where it used to cut the output short.

## 0.21.0 -- 2026-10-20

### Main and messages

- With no Chief of Staff, main may ask the same question again. The repeat guard applies only where a relay holds the question.
- Main ends each turn with one status line.
- Main checks the merge gate before it offers a merge.
- Main's rules open with a five-line do-not list, and a merge or test run in main's foreground now detaches itself.
- Main's startup print is held under 10,240 bytes: a part that does not fit becomes one pointer line, rules main does not use every turn moved to Details, and checkpoints no longer ask for task ids and paths by hand.
- The merge, a delivered answer and a seat collect close their own main-watch item task.
- A relay watcher's wake prints one summary line and keeps the whole text in a file.
- The wait command and the board print a compact form under 3 KB by default, with `--full` for the whole. The board's `--unit <name> --seats` lists a unit's seats, and every BLOCKED message names a command to run.

### Review loop

- The full suite runs before the final review where it is turned on, and a red run makes the round NO-GO and refuses `--verify`. Setup asks whether to turn it on, On recommended.
- Each finding carries a class tag, and two NO-GOs on the same class stop the review loop with a class-level question.
- A seat collect keeps the full report at a stable path and records it, and the verdict reader prints it with `--seat`.
- A seat launch returns once the pane exists and finishes in the background, and status shows the phase.
- A new unit opens only on a batch whose Launch line names it.
- A worktree used for both plan and build splits its cost by time, each request on its own stage.

### Relay and decisions

- The relay answers a decision with the owner's words and their ruling id, tells main and marks it seen, in one step.
- An empty picker answer is no ruling: it prints a retry and leaves the decision open. The relay checks the rulings log before a picker, and main-watch raises a picker left open for 30 minutes.
- No restart or stopped alert is posted for a pane that has already healed: main-watch reads the session log and takes a second reading first.

### Dashboard

- The limit panel follows the signed-in account: main records its Claude config folder, a reading of another account is dropped with its retry note and history, and the panel names the account.
- Two dashboard pages folding at once keep both folds.

### Builders and workers

- A worker's wait budget reads inside shell strings, so a sleep inside `bash -c` counts against the cache budget, and the quoted forms of the word sleep are read as sleep.
- Builders hear the batching advice at the second lone look. A Builder's unranged read of a file over 400 lines is refused with a range, a search for one bare identifier gets a symbol-lookup note, and an inline script that writes a tracked file is refused toward the edit tool.
- The batching hook polls for siblings every 100 ms instead of sleeping 1.5 s on a nudging call.

### Merging

- The merge checks its own commit message for home paths and the project's leak words. It marks the unit's issues done and names the merge commit, and a dry run says which it would mark.

### Security and maintenance

- The `main-watch` hold test is split in three (hold, claim, wake), and finished seats are dropped between sections, so each file runs well under the per-file cap.
- Every script prints its usage on `--help` and does nothing else.
- A test-case variable runs only the matching bash guardrail cases.
- The red-proof tool refuses a whole run of a case-aware test file, and `--batch` runs many proofs in one scratch worktree.
- A new hook probe runs one hook on a built payload with its state in a scratch folder, and a review pass over a change to the hooks asks for an executed probe.

## 0.20.0 -- 2026-10-19

### Review loop

- After a pass that ended NO-GO, the inbox drain names a fix round, never "merge it". When the merge check would pass the tip under the P2-tail rule, it says that merge is the owner's call, and main's rules say to ask the owner.

### Setup

- Setup's own preview and apply are no longer blocked by the dependency guard when the test command starts with npm. The plugin's own setup command, named by an absolute or home-relative path, is allowed to send its quoted answers.
- No notify question is asked when the Codex wrapper already calls the stable link, or when the old and new lines are the same.
- Setup's marked blocks are replaced where they stand: a run with nothing new writes nothing, the blocks no longer swap places or add a blank line each run, and a preview says "would copy" once per file.
- The merge report names rules already in setup's block from an earlier run.
- A saved setup answer equal to the recommended one, ignoring case and surrounding spaces, counts as one option.
- A planning worktree's settings are compared as JSON, so keys in another order no longer refuse its close.

### Builders and workers

- Helpers answer by their 20th tool call and say `NOT FOUND:` for what they did not find, and Builder briefs reuse an earlier helper's pointers. The cost report counts cold replies and helpers' repeated searches and overruns.
- A 5-minute Builder waiting on a background job, helper or pass gets a `Signal WARM` keep-alive before its cache lapses, when a ping costs less than the rewrite it saves. QUIET now comes at 225 s for Builders on the 5-minute cache, and never while a background job of theirs runs.
- A worker's foreground call may not wait past the prompt cache: its stated waits are summed against 270 s (540 s on the 1-hour cache). A worker's foreground sleep loop is now refused, not advised, and the ask the plugin prints takes `--timeout-ms 240000`.
- The batching advice reads commands with their quoted text set aside, so a search piped to `head`, echo separators and `for` loops count as looks.

### Dashboard

- The dashboard has a phone view: a bottom tab bar (Units, Builds, Alerts, You, More), a More sheet, step chips, and tab badges. A refused layout save re-reads and merges instead of dropping the change.

## 0.19.0 -- 2026-10-19

### Builders and workers

- The batching advice was off in the default hook tier. Planner seats now hear it at the third single-look turn in a row.
- The test-run wait now waits 270 s by default, not 540, so one wait never outlasts the 5-minute prompt cache. Exit 3 says to wait again.

### Security and maintenance

- 0.18.0 stays red on the Linux CI job until this release merges: one setup test found no project from its fixture folders and passed only in an Orca pane. The helper now names its project. There is no change to the plugin's behaviour.
- A test-case variable re-runs only the install-library test cases whose name holds the text you give.

## 0.18.0 -- 2026-10-18

### What you need to do

- Update from 0.17.0 if you run under jq 1.7. 0.17.0 could launch no seat under jq 1.7, the jq of CI's Ubuntu, because one line of the worktree setup used a form only jq 1.8 accepts. A build in progress when the plugin updates moves to a new unit, as the existing `UPDATED` rule says.
- Contributors should run the suite once with jq 1.7 first on `PATH`, as the contributing guide now says.

### Setup

- Setup adds the plugin's role seats that a routing file of your own lacks, checks the routing as it will leave it, and records what it added. Uninstall takes out only those seats, and a later setup run keeps the earlier record.
- Projects sharing one routing file keep the added seats until the last of them uninstalls, however each names it (a relative routing path included). A relative Codex home is recorded as the folder it names.
- A relative routing path an earlier release recorded names no folder it was read from, so uninstall leaves that file and its seats as they are and says so. The same holds for Codex files an earlier release recorded under a relative Codex home, which a later setup no longer takes for its own.
- Uninstall takes a seat out only by its own absolute record that no other project's record could share, and names each seat it keeps and why.

### Review loop

- The review prompts ask about callers the change left untouched and about cost over time.
- A unit is planned and built in one worktree: plan seats run in the unit's own worktree, and the Builder's launch takes it over once every other check has passed. If the launch fails after that and no pane opened in it, the planner gets its worktree back. A unit planned before 0.18.0, in its own planning worktree, goes on planning there and closes as before.

### Dashboard and alerts

- Every dashboard alert ends with the action it asks for, and the cache-builder alert waits until a Builder's 24 h input passes its warm-up.
- An alert seen once stays quiet when only its stamp moves. It is raised again 24 h after the relay's watcher last told it, as Alertmanager repeats, so one that stays on is a daily reminder.

### Main, relay and messages

- The message to main says when the pane it sent to has a question or permission prompt open, and prints Orca's reason when a send fails.
- The watcher tells the relay once when main has not read finished work after its typed wakes, or has a prompt open. The relay's inbox no longer counts the watcher's own notes as sends, and the relay's typed send says why it was not taken.
- Main sends a self-modification step it was denied to the relay as a note. The relay applies it only from a note its inbox watcher names as main's, by Orca's sender, and notes the watcher held from before 0.18.0 print quoted, never as main's.
- The relay pane spends no turn on Orca's notice of messages that are all its own: a new prompt hook acknowledges them and drops the prompt.

### Workers

- New lean worker and lean checker agents start with no CLAUDE instructions file, MCP or skills. Their model and effort come from routing's new lean-worker and lean-checker roles, a general-purpose dispatch is told of them, and the subagent usage report prints each agent type's first-request input.

### Security and maintenance

- The inbox watcher, the verdict reader, the test-run wait, the platform audit and a tripwire hook no longer print "No such file" for a missing file they read on purpose.

## 0.17.0 -- 2026-10-18

### Worker and Builder panes

- Worker and Builder panes take your own cuts on top of 0.16.0's. Setup asks once for the skills (`--worker-skills-off`) and plugins (`--worker-plugins-off`) they turn off, and for keep words (`--keep-word <word>=<names>`). They are saved as `workerSkillsOff`, `workerPluginsOff` and `keeps` in the project's Commandeck settings, and update keeps them.
- `--keep <word>` (or the same flag on the Builder launch) brings a word's set back, a plugin the panes cut by default (the business plugins, memoir, ponytail) included. This holds for the browser skills and Stripe too.
- A rerun after a list shrinks removes the dropped entries, and a name you set yourself in the worktree's local settings keeps your value.
- In a worktree set up before 0.17.0, a default cut, Stripe under `--keep billing` included, stays off under a keep word. Set up a fresh worktree to bring it back.
- The plugin ships no names: with no answer, nothing new is cut. The README says plugin skills cannot be turned off one at a time, only a whole plugin.

## 0.16.0 -- 2026-10-18

### Worker and Builder panes

- Worker and Builder panes start with less context. Worktree setup turns off the Stripe plugin and the `computer-use`, `built-in-browser` and `chrome-browser` skills of `anthropic-skills`, and turns auto memory off. Where the ponytail plugin is on and setup's answer is yes, it swaps its full text for a summary of about 1 KB. Main, the relay pane and a `--keep all` seat keep everything.
- New `--keep <billing|all>[,...]` on worktree setup and the Builder launch: `billing` keeps the Stripe plugin, and `all` changes nothing above. The list is stored in the worktree, so a rerun without the flag keeps it, and a rerun that passes the flag replaces it.
- A rerun removes every setting the script owns before it writes the current set, and a skill override you set yourself stays. The script now refuses an argument it does not know.
- The briefs say auto memory is off in a worker pane: a Builder asks main for a fact the brief lacks, and main copies every memory fact a unit depends on into its brief.

### Doctor

- The doctor, and setup under Needs you, warn for every key the worktree setup writes that the main checkout's local settings also set with a different value. This replaces the check for a prompt-cache TTL there, with the same message for that key.
- Printing the worktree settings now shows the relay pane's settings too.

## 0.15.0 -- 2026-10-18

### What you need to do

- Answer the prompt-cache question again if you chose the old answer. An install that did is asked again under Needs you, and setup's own earlier 1-hour value moves to 5 minutes only on a 5m answer.
- Update any script that passes the old flag values. `--cache-ttl` now takes `5m|leave`, there is a new `--relay-cache-ttl 1h|leave`, and the old `recommended|default` is refused.

### Setup and update

- Setup and update ask the prompt cache per role: 5 minutes for main and every worker pane (Builders included, replacing their 1-hour pin), and 1 hour for the relay pane. Each has a Leave as is answer that writes nothing.
- Rewriting the relay's local settings keeps its other `env` entries.

### Doctor

- The doctor, and setup under Needs you, warn when a TTL in the main checkout's local settings would override the per-worktree answers, and when the relay pane would not run on the 1 hour chosen.
- They also warn when an `env` TTL in your user or project settings, or a `promptCacheTtl` or `subagentPromptCacheTtl` in main's local settings read after the project's, keeps main on a value other than the 5 minutes chosen.

## 0.14.1 -- 2026-10-18

### Security and maintenance

- Main's startup print is back under the 10 KB hook limit (13,227 bytes before, and each role is now under 9,700). The plan-before-build detail, the checklist and four more rules moved below the Details line of main's session rules, with one pointer line.
- An owner's own main-session rules file is also pointed at the plugin template's Details for the moved rules.
- CI now checks the startup size, so a print over 10,240 bytes fails it.

## 0.14.0 -- 2026-10-18

### Setup

- The fast-tier question for plan seats offers None first.
- A dashboard choice sets the bind address too.
- Turning the dashboard off stops collecting the home project and removes the job when no project is left.
- The `generatedFiles` setting survives setup and update.
- Setup and update offer to rebase an out-of-date relay worktree on main, with the commits it is behind. Only a yes runs the rebase.
- Auto mode: a setup question adds two plain-English lines to the classifier's list in your user settings, kept with `"$defaults"`. Leave as is changes nothing, and taking them out removes only setup's lines.

### Doctor

- The doctor warns about an auto mode list without `"$defaults"` and about `autoMode` in a project file.
- The doctor flags an instruction file, rules file or global instruction file over 200 lines, a memory index past 200 lines or 25 KB, and tool search switched off. It points to `/skill-doctor`.

### Dashboard

- Codex limit alerts follow Codex's own billing mode.
- The dashboard's review time keeps a retried pass.
- The Builder's ledger row sums every session it recorded.

### Planning and review

- Auto plan tier reads panel triggers in sub-headings, and planning offers each seat its own default model.
- A branch diff over the reviewer's input limit goes as a file list to read file by file.
- The typed Codex pointer carries the seat tag, and a verdict is printed in one form.
- An answer goes to the planner it names.
- The worktree review skill finds the archive at the merge script's path, counts a Claude reviewer's passes, refuses an unknown project, writes under the project and unit, and reads the batch template's item lines. Claude no longer starts the skill on its own.

### Builders and workers

- The pane budget hook counts turns only when a pane is over budget.
- A lean `commandeck:helper` agent starts without the instructions file and stops at 40 turns.
- The instruction templates are held to 200 lines, and the startup guide says what a compaction keeps.

### Security and maintenance

- CI runs `claude plugin validate .`, and this repo's merge check runs the version check first.

## 0.13.2 -- 2026-10-17

### Dashboard

- A planning card names every plan seat with its model, effort and running or done state, not only the newest, and its Planning stage shows its time and cost while the seats run. A seat's row says "running" until its collect.
- A Codex seat binds its own log into its record, so its spend is its own. No driver badge exists to remove.
- Codex spend also reads the review home's sessions (set with `COMMANDECK_CODEX_REVIEW_HOME`), counted once. A Codex or Claude folder that cannot be searched marks the week and the unit incomplete instead of reading as not installed.
- A typed seat pointer carries its task id.

### Main and planning

- Main's watcher posts nothing while a project's own watcher holds a live claim: finished, stopped and stalled items stand down too, not only heads-up notes. An item the owner cannot have seen is posted once the claim ends, and one it posted is reminded again once the claim ends, until main closes its task.
- Main tells each planner to name a fitting mattpocock-skills skill in the plan when that plugin is installed. An owner who kept their own planning rule keeps it.

### Security and maintenance

- The merge check runs a changed Node test through its shell wrapper.

## 0.13.1 -- 2026-10-17

### Builders and fix rounds

- The fresh-round hand-off waits while the Builder's pane is busy, ends when the pane is gone or Orca fails five times in a row, and runs one at a time per pane.
- A fresh-round failure notice reaches main as a question, with the command that re-runs the hand-off.
- The Builder's ledger row carries its seat tag, so it names the Builder's own session.
- The verdict reader no longer reads a GO as the verdict on a screen that may end inside a fence. Other verdicts are still read.

### Main and watchers

- The watcher no longer posts "stopped without reporting" while a Builder waits on a review pass it started, for up to an hour.
- The wait command shows every message that cites a ruling id or comes from the relay's pane, and keeps every message it hides in a file its summary line names. A batch too large for a command line drains instead of replaying forever.
- The Chief-of-Staff poller always shows a message sent to its own handle, FYI or not.
- Main's watcher posts no heads-up while a project's own watcher holds a live claim, and says so once. A note the owner cannot have seen is posted once the claim ends.

### Setup and planning

- Project lookup from outside a checkout falls back to Orca's entry for the pane, and its failure names where it looked.
- Closing a planning worktree finds the plan author's pane when Orca lists its worktree only by another id.

### Security and maintenance

- The merge test is back with one fast case: the Builder's ledger row.

## 0.13.0 -- 2026-10-17

### Merging and tests

- The merge check (`testCommand`) now runs only the shell tests the change touches, plus the same-name test of each touched script or hook. The whole suite still runs with the test runner's default, and CI still runs it on every push.
- The three slowest shell tests are removed.

### Setup

- Setup names the paved-road template to start from when the project's paved-road file is missing.
- Main's startup text now says a planner's size target is soft.

### Dashboard

- The dashboard shows a unit's planning as its Planning stage: on the plan card, first on the Builder's card and in its cost total, seat by seat, including relaunches and seats in their own Codex home.
- The dashboard now stops on a Mac with BSD stat, naming GNU stat, before it writes anything.

### Seats

- Collecting a seat with no `--marker` closes on the marker the last wait proved from a finished turn. A wait that timed out, or a reply that only quotes the marker (a fenced one on screen too), saves none.
- A seat's sessions are found in the Codex home its role is routed to (`codexHome`).

## 0.12.0 -- 2026-10-17

### Plan before build

- A new plan tier check answers "Write a plan first?" with No plan, Plan + judge or Panel, from a table of triggers (or the project's own table). It goes one tier up when unsure.
- Plan seats (the plan author and the judges) run in a planning worktree named for the unit, cut from main, with one judge round and one revision. A plan is never a build order.
- Launching a Builder closes the unit's planning worktree and its panes once the Builder's pane is open. It keeps the worktree, with one REFUSED line, when the worktree holds a file that is not identical on local main or a pane does not close.
- A rejected plan's worktree closes by hand with the plan worktree close command, and its `--dry-run` removes nothing.
- An unreadable, empty or error pane list now counts as "panes not closed", never as "no panes".

## 0.11.2 -- 2026-10-16

### Builds and dashboard

- The Builder launch refuses a raise whose brief or evidence cannot be read, and keeps the evidence history. It also refuses a directory where a record belongs instead of writing inside it.
- The dashboard keeps an unreadable unit cost record as it is, instead of overwriting it with only the latest units' costs. A corrupt one is still reset, and `--unregister` refuses an unreadable registry instead of emptying it.

### Security and maintenance

- The platform audit verifier refuses a verdict with two rows for one finding. The later row silently replaced the earlier one, so a confirmed P1 could count as refuted and the audit still recorded its result.
- The suite re-run guard is about 40% faster per call and forks less, and its self-test drops from about 77 seconds to about 50, well under the test runner's 120-second limit. It no longer loads a Python module of the same name from the project folder.

## 0.11.1 -- 2026-10-16

### Security and maintenance

- The platform audit now runs its verifiers under bash 5.2 (the Ubuntu CI version) too. Bash 5.2 could not re-read the verifier's per-area function, so no verifier ran and every audit failed.

## 0.11.0 -- 2026-10-16

### What you need to do

- Add a `## Prior art` section to every batch brief before you launch it, including briefs written before 0.11.0. The Builder launch now refuses a batch without one. Under the heading, name the governing standard, the library or service the project's paved-road file approves, and why the batch builds instead if it does.

### Paved road

- A paved-road registry template (empty) is copied to the project's paved-road file. For each area it lists the standards that govern it and the library or managed service it builds on.
- The batch brief template has a required Prior art section, and the Builder brief says that section binds.
- Every review pass, Codex or Claude, now asks whether the change hand-builds what the registry or a published standard covers, and has such a finding cite the registry row.

### Platform audit

- A new platform audit command audits each area of the registry whose files changed since the last recorded audit. One read-only auditor checks each area, then one verifier tries to disprove each finding, and the results merge into one report.
- A change to the registry or the areas file audits every area again.
- An agent that fails, or whose output lacks the template's sections or a verdict for each finding, fails the audit and records nothing. `--dry-run` lists the areas and launches nothing.

## 0.10.0 -- 2026-10-16

### Dashboard

- Each build in Builds in progress now folds to one line on its own toggle: name, seat, stage, issues built, cost so far and last sign. A finished build folds by itself, and your choice is kept with the panel layout.
- The dashboard marks a build that main raised.

### Builder effort

- `--effort high --reason '<one line>'` on the Builder launch raises one Builder above the setup default (medium or high only). The brief and the evidence file record the override, and the launch prints the effort it uses. Launching a Builder by hand holds to the same floor.
- A risky launch's second call opens the Builder at the effort the first recorded, or rewrites the brief and logs the change in the evidence before it opens at a new one.
- That second call refuses while the Builder already runs, and a retry after a failed write finishes every record still owed.

## 0.9.0 -- 2026-10-16

### Setup

- Setup asks the Builder's effort (medium by default), and every Builder launch runs at it.
- Setup asks the Builder clear line (180K by default, or off). Past it the Builder is told to hand off to a fresh session of its pane, and the dashboard's unit card shows its context against the line.
- Setup asks the issue sizing line (40K by default, or off). The batch brief sizes each issue, and the Builder launch flags an independent issue over the line to main, with a split proposed.

### Main and the Chief of Staff

- Main's Stop hook holds a turn once when the message from you that the Chief of Staff passed on has no reply sent back. The relay's watcher flags every main turn that ended with nothing sent to it, with main's last words.
- The Chief of Staff's inbox watcher now wakes on any message main's pane sends to the run, whatever its subject.
- The Chief of Staff's Stop hook requires all four watchers, each checked by its own pid file for this project. Its block names each watcher's start command by the stable plugin link, which survives an update.
- The verdict reader reads main's pane from the newest session log in main's checkout.
- A script run from outside the project finds it from Orca's worktree id when Claude Code gives no project folder.

### Dashboard and builds

- The limit card shows each 7-day tile only where that provider has a subscription window. A failed read still shows it.
- The closing run cites a touched test file already green on the current tree instead of running it again.

### Codex

- Codex fast mode now reads Codex's config as TOML. A quoted `"service_tier"` key or a `'fast'` literal counts, the default profile's tier wins over the top-level one, and a tier set only in an unused profile no longer counts.

### Security and maintenance

- The leak check searches a PNG's text chunks (tEXt, zTXt, iTXt) with the word list. A new or changed image is for you to review.

## 0.8.1 -- 2026-10-16

### Dashboard

- A unit card keeps its Stage band in view and folds the activity rows into a closed Details.
- The stage list names each Codex pass with its round's verdict, GO or NO-GO, or running.
- The dashboard's merged-since-push list was already a pane of its own, Next push.

### Builders and guards

- A fix-round session starts from its hand-off and opens the brief and evidence file only when a finding needs them.
- The search guard counts reads sent together in one turn as one lookup. A whole-repo search is still refused.
- The suite re-run guard checks the head of every suite in a chain, so `npm test && ! npm run typecheck` is no longer recorded as a pass.
- The Codex pass command has a `--check` mode that runs a launch's own checks and stages, commits and sends nothing.
- The commands that add work, answer a worker and message main now find a Builder's pane from its launch record.

### Updating and docs

- The README has an Updating section: the two steps of a plugin update, and going back a version. It also shows the dashboard and Orca, in a What it looks like section.
- The update command shows setup's Needs you list, a failed add-on install or update among it, where it used to hide it.

### Security and maintenance

- The tests no longer install or uninstall the plugin or run setup and uninstall whole. Small checks of the functions they call take their place, and the Builder brief and the contributing guide say not to write new ones.

## 0.8.0 -- 2026-10-16

### Safer removals and paths

- No script can remove a main checkout any more. The dashboard's `--project` option, run by hand with no fixed time, removed the folder it was given, which is how a main checkout was lost. Every computed removal now refuses a checkout, a git folder, your home folder or the root, and the merge refuses a unit folder that is not a linked worktree.
- A main or workspaces path spelled with a dot segment, a doubled slash or a trailing slash now matches the paths Orca, transcripts and setup's records give, on both sides of each compare. Nothing stored is renamed.

### Setup

- Setup installs every add-on and updates each to its latest on every run (`--addons` narrows the list). No command names a version.
- The codebase-memory add-on is updated only while no session is open, and setup says FAILED when a new session cannot reach it.
- The relay pane follows your ponytail setting instead of turning it off, no profile names typescript-lsp, and the worktree summary has its space back after "memoir off,".

### Reviews and merging

- Main can clear a review finding it ruled out, with a line under "Cleared findings" in its rulings file. The merge then counts it as cleared, not as a blocker, and the reviewer is handed it with the stated limits.
- A merge of Commandeck itself runs the shell suite, set as the project's `testCommand`.
- A fix round the Builder's pane never took is now told to main, with Orca's own answer, instead of only written to a log.

### Guards

- The suite re-run guard records a run as passed only when its exit status is the suite's own. A piped or chained failing run is no longer taken for a pass.
- Escaped quotes no longer hide a second suite from the re-run guard.

### Dashboard

- A long Builder name in "Who holds what" no longer squeezes the issue number and title to a letter per line. The name is cut short and shown whole on hover.
- A build's "Cost so far" shows its Claude and Codex parts.
- A Builder's issues built are also read from its evidence's Issue and Status table. A row that says partly built, blocked or not built does not count.

### Security and maintenance

- The two longest setup and merge tests now carry their own time allowance, so the test runner no longer reports them HUNG at its 120-second cap. Every other test keeps that cap.

## 0.7.2 -- 2026-10-16

### Startup and banner

- Main's startup text is 497 bytes shorter (10,198 to 9,701 bytes for the main seat) and states every rule it stated before. A rule you keep your own wording for (`--rules-drop`) stays out after its rewording, until you answer keep both (`--rules-keep`) for the reworded rule.
- Main's prompt banner is about 0.4 seconds faster (1.26 s to 0.83 s, 5-run means), because its three local checks run beside the Orca calls. It prints the same text.

### Worktrees

- A workspaces setting that ends in a slash or a slash and a dot no longer hides this project's worktrees from any script. Version 0.7.0 fixed the prompt banner only.

## 0.7.1 -- 2026-10-16

### Security and maintenance

- A decision reopened or re-asked in the second it was last asked now waits for the next second and takes that as its new ask time. The Chief of Staff's watcher puts it to you again, and an answer read before the reopen cannot close it. This was the 0.7.0 Linux CI failure.

## 0.7.0 -- 2026-10-16

### Setup

- Setup checks the requirements before its first question and says what it found: your own startup files, your project rules, your global rules file, your model's context window when a setting names it, and whether Codex and its fast mode are ready.
- Each question explains its choices, marks the recommended one "(recommended)" and offers it first, and is asked only when it applies. While setup asks, the picker's stray-keypress option is off, and it comes back when setup ends, fails or is cancelled.
- `--plan` prints every file a run would create or change (a diff for a changed one), every copy, job and add-on, and writes nothing. The skill shows it and asks Apply, Change an answer, or Cancel.
- The dashboard, ponytail and add-ons are questions now. Add-ons you pick are installed for the main checkout and reported as installed or failed, with the command.
- Setup asks for the prompt-cache lifetimes. Recommended is 1 hour for main and the Claude panes and 5 minutes for subagents, written to the project's Claude settings (a value you set stays, and uninstall takes out only setup's). On real transcripts 5 minutes cost main about 19% more than 1 hour, and 1 hour cost subagents about 8% more.
- Setup ends with a short summary: done, needs you, optional, and how to change an answer later. The doctor says when your own startup file loads instead of the plugin's.
- Project permission rules now go in the project's local settings, which git never sees, since they name this machine's plugin folder. A rerun moves them out of the shared settings, and a new scope moves them instead of asking for an uninstall first.
- Small build can be turned off, and every first pass then has three reviewers.

### Your rules

- Setup can merge the plugin's rules with your global rules file and your project rules. Exact matches are left out. For a rule that only says the same in other words, or disagrees, you choose after seeing both texts, and a rerun keeps your answer.
- Only a rule a session really loads counts. A rule in a path-scoped rules file (or one whose frontmatter setup cannot read for sure), one a Builder's settings leave out, or one under main's startup text "Details (not injected)" does not.
- Setup also merges with your own startup file and your own main startup file (merge, replace or skip, asked each time). Global rules gain merge.
- Your own text is never changed. The plugin's rules go in marked blocks, a copy of your file is kept beside it first, and uninstall takes out only the blocks.

### Dashboard and relay

- The dashboard loop picks up a changed view file on its own, without `--install`.
- The relay pane explains why its servers read as blocked "by enterprise policy", and the serena line setup and the doctor print reads the saved config.
- The prompt banner lists only this project's Orca worktrees, also when the worktrees folder is named with a trailing slash.

### Builders and guards

- The Builder brief template asks for the brief and every file it names in the first turn.
- The worktree review step marks each item the first render leaves unreviewed, then renders again.
- The whole-disk search guard refuses, and names realpath, when `realpath -m` does not work, instead of blaming the path.
- The startup size report measures each seat in its own folder, so only main's row shows the prompt banner.
- The hook that refused main a read inside a worker's worktree is removed, and the hint that a plugin script answers `--help` is restored for when main reads one.

## 0.6.0 -- 2026-10-15

### Decisions and inbox

- The watcher no longer re-fires an open decision on every restart. A wrong answer can be replaced with `--correct`, and the old answer stays in the decision's history.
- A Builder's question now lands in the decisions ledger as waiting on main and is never counted as the owner's. A prompt closes a plain-chat ask only when it names its id, and a re-asked decision passes for the picker whose header names it.
- A bare inbox check that never acknowledges its batch is blocked and points at the wait command. Notes to the relay pane go to main's run and are confirmed stored.
- Answering a worker whose pane is mid-turn says "queued, not read yet". Main is woken by mail left unread for two minutes while it is idle.
- The ruling log is appended under a lock.

### Builder rounds

- A NO-GO pass from the Builder's own pane now writes a hand-off that stands alone and starts the next round in a fresh session of the same pane. A new command hands added work over the same way.
- Every later pass is handed the evidence file's `## Main-only (deferred)` list as known. A new command shows that a test catches a break, from a scratch copy of the tree.
- A new command raises one unit's round limit. A Codex pass first proves Codex answers.
- A Builder's hand-written poll on test output is nudged toward `run_in_background` and a new wait command that also checks the test runner is still alive.
- The brief template now has a red hang test set its own timeout, writes each evidence heading when its item turns green, keeps a changed setting reading the deployed format (the reviewer checks it), and reads an answer that arrives after the done marker. A test file that times out twice becomes one question to main, and each test result carries the machine's load.

### Merging

- Main is fetched and fast-forwarded before branching or merging.
- A GO followed only by regenerated build files is accepted.
- The merge title is the brief's heading, not the pass subject.
- The board shows each unit's last pass result.

### Dashboard

- The unit card and the Builds panel show cost so far and cost per stage, with a full-width stage list and a Total row when stages are narrow.
- Dotted and prefixed model ids are now priced, and the build timeline starts when the build started.
- Usage-limit tiles are hidden when Claude runs through an API. A Builder under 95% cached over 24 hours raises a warning, and the host-load alert is gone (swap still alerts).

### Setup and launch

- Builders and the headless reviewer run with the advisor switched off when they name none.
- Every review flag and threshold now takes `off`, and typed values are asked inside the picker questions.

### Security and maintenance

- Main reading a worker's code is refused. A read-only Codex run also drops Stop hooks from its keep-list, and the dependency guard returns at once for a command that names no package manager.
- The tested-tree record ignores the evidence file and counts chained runs. The suite-rerun key keeps every argument, and the leak test ignores runtime files.
- `/worktreereview` now reviews every "Where it could shrink" item after each report, counts refusals by hook and reason, and takes cut windows off command and helper seconds.

## 0.5.0 -- 2026-10-14

### Review and read guards

- The 150-line shell read cap, the shell symbols-before-read hook and the symbols-first rule for Read, Grep and Glob are gone. The test heap cap, the repo-wide search block, the main and worktree boundary and the other hooks stay.
- A here-document sent to a shell through process substitution is now judged as commands. A nested substitution after `cd ..` was already judged in the right folder and now has a test.
- The build review runs only when you ask (`/worktreereview <unit>`), never from the merge, and sends no flag message. It keeps the full pass text and lists every pass after the closing one.
- Waits on a pass run elsewhere, or on a review tool that is down, are their own bucket. The share-of-clock flag also needs 10 minutes of tests or idle and names the largest command. Idle after DONE is cut only where an owner decision was open, and a review saved before the waiting field renders it as unknown.
- Lessons become issues only with your approval, with an on-demand sweep. The lessons page can be written by a separate writer session from a shipped hand-off.

### Dashboard

- The unit card is now a run trace.
- Three new GitHub panes show the merge line, who holds what and the next push. They read through `gh` and say so when it is missing.
- An issue in Issue by Issue opens on GitHub.
- A stale page no longer writes its old widths over a newer reset, and a replay of expired clears from a stale tab no longer pushes out newer ones.

### Merging

- A deletion named under "Files deleted" in the unit's evidence file is accepted, and the merge says which file named it.
- A failure after the squash commit exits 3, and the queue says the unit merged.
- The proof-run command prints the three-argument `--verify`, and the board says what it writes.

### Pass script and Builder

- A cache fallback warning no longer ends up in the model id. After main changes the brief or its rulings, the next review pass reads the whole branch.
- Each pass prints the files the round changed and flags a round of comments only. `Different fix r<N>` and `Other cases checked r<N>` evidence lines now reach the reviewer.
- The README says why a build that changes the review prompt makes the next build run one new pass.
- Builder runs Opus at effort high with no advisor, whatever an older setup stored. A live Builder pane is refused when the configured model changed since its launch.
- The brief no longer names the model. It carries the test-run rule (also in the shipped rules), the shared-Mac test rules, and rules for questions answered another way, documented commands, starting helpers together, and rulings that leave something as it is.
- Only the Builder's own DONE marker ends a helper hold, and a Builder that works again clears its hold.

### Security and maintenance

- The hook fire log records an "ask" answer as `ask`, and a guard test fails a hook that prints "ask" without its marker.
- Claude Code 2.1.300: the two hooks that return `updatedInput` send only valid keys (checked live for the agent model guard), and every transcript reader skips the new `api-request` rows, so request counts and prices match the assistant rows.
- A request seen under its request id and its message id counts once across cache reads, and an older cache is rebuilt.
- The leak test compares folders by identity, not letter case. `/test-audit` reads a `read=` field that is not plain ranges as not clean. The project-main command clears Git's routing variables before it probes and pairs a stand-in main under temp only with a workspace under temp. macOS CI runs setup with no Homebrew on the path, and CI installs jsdom again so the dashboard page tests run.

## 0.4.5 -- 2026-10-14

### Setup

- Setup now asks how the review loop runs instead of fixing it: the most review rounds a build may run, whether a closing pass reads the whole branch, the small-build line for a one-reviewer first pass, and the three thresholds that flag a finished build for a written review.
- Each question offers today's value, so taking every default saves nothing and changes nothing. Numbers are saved as typed, and a value the loop cannot use is refused.
- With no closing pass, the narrowed pass that ends GO merges once narrowed passes have read every commit after the first pass.
- Setup offers the plugin's general instructions and working rules, as a new file or a marked block. It never changes your own text, and uninstall takes out only its blocks.
- The default Builder is Opus at effort high with no advisor, a risky build included. `--small --model sonnet` is unchanged.

### Handoff and messages

- The startup context names the plugin by a stable link, a pane that is still main after a handoff says so, the new main's first line confirms the handoff, and the main-pane guard points to `/handoff`.
- The message command finds main's pane when it sends and queues the message when main is down. The next session shows the queue and unread mail to its earlier handles first, and the answer-worker command takes a unit name the same way.

### Codex and Claude Code

- Doctor reads a Codex notify line that calls your own wrapper script, and warns only when the wrapper calls no hook or an older one. Setup asks before it changes such a wrapper, and uninstall names the line to take out of it.
- Claude Code 2.1.299: the ruling log skips a prompt that is a slash command seen before it expands, and the README points at the built-in idle compaction.

### Security and maintenance

- A fast doctor test covers the common path.

## 0.4.4 -- 2026-10-14

### Shell tests

- The shell test suite now runs in under five minutes, down from about 70. It keeps only the critical tests: setup and uninstall complete, each blocking hook blocks what it must and lets through what it must, the leak test, every shell file parses under Bash 3.2, the version check, and a merge is refused without a passing review.
- The Doctor, dashboard, main-watch and proof-run tests are gone, with the tests of the advisory hooks that never block. Uninstall is tested at project scope only.
- The Builder search guard's block cases now have a small test file of their own.

### Security and maintenance

- 125 shell test files were deleted, with the Node and Python tests and fixtures only they used. The kept hook and setup tests were trimmed to their critical cases.
- CI no longer installs jsdom, because no kept test uses it.

## 0.4.3 -- 2026-10-14

### Builders and the dashboard

- A Builder that starts helpers in the background and ends its turn to wait for them is no longer reported to main as stopped or finished. While a helper is out and has written a row in the last 20 minutes, the watcher waits and checks again, for an hour at most. A wait that runs out with no DONE line is posted as stopped.
- A Builder that stopped with no helper out, or printed its DONE line, is still posted at once.
- A helper can log a stop and then go on working. The Builder card now counts a helper as running until a stop that none of its own calls follows, and stop rows from ids that never started change nothing.
- The dashboard no longer shows an idle Builder as waiting on main while its helper or Codex pass is still running.

### Codex

- Codex behind a proxy now finds its model. The model family is looked up in the proxy's own model list, newest version first, then in the local model cache as before. A GitHub Copilot API proxy is asked with no key, and a regular proxy gets the key its settings name, as a bearer token.
- Setup takes a model id for a Codex role, such as `--codex-model codex-reviewer=gpt-6.1-sol`. It is saved in the project's own settings, so a plugin update keeps it, and it wins over the routing defaults, a hand edit of them included. `--codex-model codex-reviewer=` clears it.
- Doctor and setup say whether Codex goes through a proxy, and a refusal names the fix that fits.
- `gpt-6-luna` is priced from its published list price (read 2026-10-14), and a new luna version takes the tier's price and says so.

### Cost

- The "Cost today" tile no longer shows zero behind an API proxy. A session line with no `requestId` is now counted under its message id, else its own id, so a request is never counted twice. A log where every line has a `requestId` totals as before. Dollars are still a list-price equivalent, not a bill.

### Security and maintenance

- The doctor no longer prints the "Python 3.11 or newer" fault twice when Python has no tomllib.

## 0.4.2 -- 2026-10-14

### Security and maintenance

- CI is green again on Linux. The Mac preflight, and the doctor's copy of it, read the self-tests' pretend system, so a Linux runner that a test called a Mac asked for Homebrew and stopped. It now asks the machine it runs on. The plugin works the same for you.
- The plugin test no longer pins version 0.3.0, which broke it on every release. It reads the version from the manifest and checks the README badge and the newest CHANGELOG entry against it.
- The day tile's test now expects the unpriced model names the tile shows, as 0.4.0 says.
- The seat event log is ignored by git.

## 0.4.1 -- 2026-10-14

### Dashboard and cost

- A new Codex version of a known tier is no longer left unpriced. By the owner's ruling it takes the tier's price: `gpt-6.2-sol` is priced as `sol`, with no new row.
- The dashboard's week note and day tile, and the build review page, now say how much of the total is priced by tier and not by exact version. A name with no known tier stays unpriced and the total stays marked partial. Claude prices are unchanged.

### Security and maintenance

- A decision for `unit.-v1`, `unit..v1` or `unit.` no longer counts as one for `unit`. A unit's name now matches only as a whole name made of letters, digits, `.`, `_` and `-`, and a full stop after the name reads as part of it, so the worst case is a missed cut, never a wrong one.

## 0.4.0 -- 2026-10-14

### Dashboard and cost

- A Codex model's price now comes from the parts of its name: the version and the tier word, then the mode and the prompt size. Only a published version and tier is priced. `gpt-6.2-sol` and `gpt-6.1-astra` are, and a name with any other part (`-mini`, a date) stays unpriced, with the total marked partial and the name listed. The old per-model Codex rows are gone, and Claude prices are as they were.
- The build review no longer counts time the Builder spent waiting on you as build time. It finds those waits itself: an idle gap over two minutes after the Builder's DONE line, or inside an open decision that names the unit. It never cuts while any session has a background job or a Codex pass running.
- The cut comes out of wall clock, shares, flags, stage, pass and gap times, and cost is unchanged. The page and the saved result list every cut window and why, and the collector takes `--exclude START=END` (repeatable) to add one by hand.
- Not cut yet, and the page says so: a helper's request and tool subtotals, and command seconds inside a cut review pass. The decisions and the round archive are read from the reviewed project's main checkout, found from its worktree. Once the worktree is removed, give it with `--main`.

### Security and maintenance

- Eleven shell files did not parse under the Mac's own Bash 3.2, and setup was one of them. Each is rewritten in syntax that version accepts, and a test now runs a syntax check under the system's Bash over every shell file, in the macOS CI job too. The test runner still needs Bash 4 and, with none to restart under, now says so and stops.
- The routing log is now in the ignore list, where before only a local exclude covered it.

## 0.3.0 -- 2026-10-13

### Setup

- Hooks now start on an Intel Mac. The requirements check takes the prefix of the `brew` on the path and otherwise looks under both Homebrew locations.
- Setup creates the project's Orca run, or prints the one command when Orca does not answer. It ends with the list of project files it created or changed, each marked to commit or not.
- A relay chosen at setup now gets its worktree and pane. Setup creates the `Chief-of-Staff` worktree and opens its pane under the stored name, and where it cannot, it ends with the exact steps. It says plainly that the session in the main checkout is not the relay, and so does the orchestrator's start-up text, in one line that names where the relay pane is or how to make it.

### Builds and review

- Codex fast mode is now one setup question, off by default (`--codex-fast`, `--no-codex-fast`), saved as `codexFast`. It was on for every review pass, which you never chose. A project set up before has no answer and is off.
- Off is off: the review pass and a launched Codex seat name the normal tier on their own command line, and your Codex config is never edited.
- The dashboard now lists the issues of a brief whose issues sit under a sub-heading or in a section of their own, and an item with no issue number is listed as a line of its own. The launch dry run uses the same reader and says so when a brief names no work item. The batch brief template now starts with "The issues".

### Dashboard and cost

- A refused usage check now waits longer after each refusal in a row, an hour at most and never less than the service's `Retry-After`, which is read as seconds or as a date. The card says when the next try is, and the limit panel keeps the day's cost while the usage reading is refused.
- A model with no price no longer hides what is left out. The total is marked partial, with the count of requests and the names of the models.
- A merged build now writes its Builder's row to the token ledger, which nothing wrote before.

### Security and maintenance

- A new check fails when a plugin file changed against main and the plugin's version did not. Docs and CI files do not count, and the contributing guide holds the rule for the number.

## 0.2.0 -- 2026-10-13

### What you need to do

- Update the plugin between builds, not during one. A build whose earlier review passes ran under the earlier prompt is refused at its next pass and at the merge, and goes on only as a new unit (a new worktree made from its branch), reviewed from pass 1.

### Setup

- Setup now names everything missing in one list, in two groups: "can install", with the one `brew install` or `sudo apt-get install -y` command, and "yours to do" (Orca, Homebrew itself, `gh auth login`, the Codex CLI). Setup, the doctor and the Mac preflight used to keep three lists that did not agree, and now read one.
- `--install-missing` runs the printed commands and no other, then checks again, and without the flag nothing is installed. `gh` and its sign-in are now checked. Setup and the doctor ask for Python 3.11 or newer.
- On a Mac whose first `bash` is the system's 3.2, hooks that did not parse under it failed, and a failed hook blocked every command. Every hook now starts through a small launcher that finds a Bash 4 or newer and runs the hook under it, and with none it prints one line and exits 0. A script started by Bash 3.2 starts itself again once under Homebrew's Bash. CI has a macOS job for both.
- The Mac app ships Orca's command as `orca`, with no `orca-ide`. Setup now offers the link as the exact `ln -s` command when the `orca` it finds really is Orca's, and otherwise names Orca and its releases page. The user settings file can carry its own `env.PATH`, so the check now reads both paths and names a tool found on one and not the other. The link goes into a folder on the PATH a session gets, and your settings file is never edited.
- `/commandeck:setup` passes what you type exactly as typed and asks one fixed question before installing. Its first command is a probe, so a host project's own guard that refuses `orca-ide` is named before any question and never worked round. Only fixed choices go through the question tool, each with a header of 12 characters or fewer and two to four options, at most four per call. Names and commands are asked in plain text, and a refused call is asked again in plain text.
- The plugin now wires itself into Claude Code and into a project, and takes itself back out, through `setup`, `doctor`, `update` and `uninstall`, as skills and as scripts. Setup records every file before it changes it, and uninstall puts each back. Setup installs the ponytail skill (never over one you have), prints a command and a cost for every add-on, and `--status-line '<command>'` sets a status line and records yours. The doctor reports which add-on servers (`serena`, `codebase-memory`) are present.

### Builds, review and merging

- The orchestrator's flow is in: Builder launch with a hard stop for risky work, review passes on Codex or on a second Claude, and a local squash merge that takes only a batch whose last pass ended GO. Hooks are registered in two tiers. The default tier stops lost work and wrong commits, and the strict tier (a setup answer) also holds a session to searching before reading and one test run per change.
- Review is three passes: a first pass by three reviewers, narrowed passes on the fixes, and a closing pass. A closing pass that leaves only P2 or P3 findings still merges and prints each as open, and any P0 or P1 refuses.
- A build's first pass is now one reviewer, told all three angles, when the commit it reads is under 200 changed lines (briefs left out) and main did not launch the build with `--risky`. Otherwise it is three reviewers, as before, and so is a build with a file git gives no line count for or no launch brief in main's checkout. The pass prints which rule chose the count, and the merge refuses a one-reviewer first pass the rule did not allow.
- A reviewer's finding line now ends with the exact failing input or command, and a finding it cannot give one for is left out. The issue filed for a finding left open carries that command. A finding on a GO report counts as resolved only by a word in its title or its reason, never by one in its last field. A review pass is handed the build's stated limits, read from the copy of the brief the launcher keeps in main's checkout.
- `--small` is main's word that a build is expected under 200 changed lines: the Builder starts with no advisor and its brief says so, unless the launch is `--risky`. `--model <alias> --reason '<one line>'` puts one launch on another model and logs the pick with its reason. A Builder may be Opus advised by Opus, and `--builder-advisor none` (or `"advisor": "none"` in the project's config) starts it with no advisor.
- The Builder brief changes. A fix round re-runs only the test files it touched and the one whole run goes beside the closing pass. A second variant of a fixed finding is fixed as a class with a short note to main, not a question that waits. There is no advisor consult before a review pass, a failed consult is retried once, helper answers and long output are capped, and there is one `Ponytail:` line per batch item.
- A merge files each finding left open as an issue, which needs the `gh` CLI logged in and a GitHub remote. Without them the merge still lands, says NOT FILED with the command to run again, and exits 4, and the merge queue goes on past a 4 and ends 4. A merge whose clean-up fails after the commit says MERGED and names the failed step. The merge check runs on a copy of the commit to be made, so files of yours lying in the main checkout neither stop a merge nor take part in its check. The merge's build review opens no tab, and a flagged build is still told to the relay pane.

### Test audit and build review

- `/test-audit <scope dir...> [basic|full] [N agents]` is new, in a project where setup has run. Agents read the project's tests against its code and write a report of what is redundant, slow or missing. It changes no test.
- Setup turns on `"enableWorkflows": true` in the project's settings unless you have set it, and uninstall takes it back. A project with no recorded test runs gets no timing figures, and its token figures are a guide measured in one repository. No pane the plugin starts is refused the Workflow tool any longer.
- The audit prices a split file's part by its real bytes, so a part that holds the long lines is cut further or listed too large. Its coverage check also names a list no finished batch owns, reads an id given twice as wrong, and tells the validator to read every list.
- The audit ends with one more stage, a Sonnet agent that checks the finished audit: that every test file was audited, that the counts agree, which files hit the five-note cap, which notes are plain facts (those become findings) and what the audit missed. It lists every file it did not open. When the stage fails, the audit's result still comes back, with one line saying the report is unchecked.
- A new build review skill makes a page of timings and cost per build at merge. It shows the build's lines changed beside the pass list.

### Dashboard and Chief of Staff

- A Chief-of-Staff relay pane and a dashboard that shows every registered project on one local page are new. The dashboard answers its own page only, so another site's page cannot read the snapshot. `--no-dashboard` is remembered for the project and `--dashboard` takes it back. `--hosts <name>[,<name>]` lets the dashboard answer under another name of this machine, and the doctor names the command when the list is closed.
- The dashboard is rebuilt, with more panels, a price table that knows Codex's prices, Builder alerts and a layout you can save. It colours a build's steps by how they ended (a NO-GO is never green), a panel can be dragged to any height, a stopped helper's open call no longer reads as stuck, and an evidence file headed "Item N" counts.
- The dashboard lists a project's finished builds, drawn as running ones are, and a build you clear stays cleared in every browser. The needs panel carries your own name and stays in view while a finished build has a P1 open.
- The dashboard counts the project's open GitHub issues labelled `P1`. A count above zero keeps the needs panel shown, and a count `gh` could not give within 8 seconds reads "Not measured", never 0.
- The relay's inbox watcher keeps its place and its held notes in one file under a lock, so two watchers never show a note twice or lose a held one. It wakes for every note the orchestrator's pane sends by hand, whatever its subject, while script traffic and worker reports still do not wake it. A note whose subject starts `FYI` is held and shown with the next note that does wake it.
- The relay pane may run its watcher scripts and the decision script without a permission prompt. Each project keeps its own Orca run, and the machine-wide current run is no longer read, so two projects on one machine do not follow one run.

### Security and maintenance

- The public-release files are new: a security policy, a contributing guide and two issue templates (bug report, feature request). CI is hardened: the checkout action is pinned to a commit id, the workflow's token is `contents: read`, and the runner is `ubuntu-24.04`.
- The README is rewritten from the plugin's files. New or longer: the first build walked through with the scripts' own output, review passes by build size, the hooks by group and tier, the Chief of Staff and its watchers, the decision ledger and the ruling log, cost control, checkpoints and resume, the dashboard, the build review, `/test-audit`, and the numbers the proof run printed. Corrected: a first pass is one reviewer under 200 changed lines, setup stores the Chief of Staff's name and does not open its pane, `perl` is needed, and the Builder model choices.
- The licence is Apache-2.0, and the notice names the bundled skill, what the plugin runs on and each optional add-on with its licence. Both manifests name the author, the repository and the licence. The version is 0.2.0: the second part rises for new behaviour, the third for fixes, and it is written in the plugin's manifest and the README's badge.
- The leak test allows two exact texts and nothing near them: the repository's own address anywhere, and the owner's name in the licence, the notice and the two manifests. In a checkout it searches git's own list of files, so an ignore rule hides no tracked file. No ruling id of the source project is left in the tree, and the leak test fails on one. Two old test fixtures that held made-up text are cleaned, and a build's working papers are no longer tracked or exempt from the leak test.
- A script now works for the project it is run in, not the folder the plugin sits in, so one installed copy serves every project. Inside a linked worktree `COMMANDECK_MAIN` and `COMMANDECK_WORKSPACES` are no longer followed as given: the project is the one git says the worktree belongs to, with one exception, a stand-in project under the system's temp folder.
- git-safety reads a quoted `git` word and a command in backticks as the commands they are, the search rule follows a substitution inside another and a search inside a subshell, and an edit that would leave a hook script unparseable is refused.
- A project whose model holds 200K (`standardContext`) checkpoints and restarts at 150K instead of 200K. Codex runs the same hooks as Claude. `--delete-data` on uninstall also removes the project's finished-builds record. The repository no longer carries a second copy of the scripts and hooks, and runs on the plugin tree itself.

## 0.1.0 -- 2026-10-11

### Install

- This is the skeleton. Nothing is wired into Claude Code yet: the plugin installs from a local path through a plugin manifest and a one-plugin marketplace, and the scripts run from a checkout of this repository.

### Builds

- The routing config has four roles (orchestrator, builder, codex-reviewer, claude-reviewer), with model families only.
- The Builder flow and the orchestrator's scripts and hooks are in, copied from the project this workflow was built in and renamed for this one.

### Security and maintenance

- A leak test and a GitHub Actions workflow run it and the shell tests on every push and pull request.

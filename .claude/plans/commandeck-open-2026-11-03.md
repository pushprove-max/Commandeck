# commandeck-open-2026-11-03 -- every open plugin issue, in seventeen cuts, one build slot

Owner's words: the owner, 2026-11-03: take all the open plugin issues, break them up into relevant cuts and build them using one build slot.
Goal: Build every open plugin issue with a code fix and no unmerged host twin, in seventeen cuts built in sequence in one slot; close the fixed and non-plugin ones.
Plan: .claude/plans/commandeck-open-2026-11-03.md
Tier: Standard; LOCAL merge only; changed-file tests only; plugin shell tests on the PC only; no test-timeout raises.
Closes: #587 #589 #590 #592 #593 #594 #595 #596 #597 #598 #601 #602 #603 #604 #607 #611 #612 #616 #617 #619 #620 #622 #623 #624 #625 #626 #627 #628 #629 #630 #632 #634 #635
Refs: #588 #591 #615 #621
Base: local main 991ec40 (the worktree fast-forwarded to it 2026-11-03; it holds main's #631 fix 4530f6f and its paths.sh `--full` inbox reads 991ec40)
Split override: the owner's order names one unit for every open plugin issue, its cuts built one after another in one slot.
Build order: C1 to C17 in number order; each cut after every earlier cut on its files.
- Planned size: 77 files, 2010 changed lines
New tests: commandeck-open-2026-11-03 134 -- 122 new cases, 6 extras on main's ruling; one more on main's ruling answer-1793782183-75924: the one merged check in seat-settle.test.sh is the regression proof for pass 7's NO-GO finding (seat.sh close reported success when the pane close failed), and main decides cap questions (owner ruling 2026-10-30); one more on main's ruling answer-1793783347-63451: the new seat-revise.test.sh check is the regression proof for pass 8's NO-GO finding (revise recorded the plan baseline after dispatch); the dashboard-loop row names an existing check that C7 makes reliable, the seat-revise issue-485 row an existing check D26's stand-in edit keeps proving, and the seat-run and seat-run-refused rows the two existing direct-run checks D28's fixture-wide export keeps passing

## Why

The order asks for every open plugin issue in one unit. Triage read all 55 open issues against this checkout, the two newest merged plans and the host's main; #628-#632 were filed later the same day and are all in this unit (#629 joins C10, the other worktree-removal cut). Twenty-three have a small, testable plugin fix and no unmerged host twin; they group into eight cuts by the scripts they touch, plus a ninth (the hand-launch gate, a port of the host's merged gate) on the fixture edit the owner approved. #588, #591, #615 and #621 build their safe part only (C8, C10-C12). Seventeen are fixed, not plugin code or closed by the owner's answer; main closes them. The owner's answers turned #587, #590, #611 and #620 into cuts C13-C16, and keep eight open for later units. Two issues (#597, #626) asked for opposite things on the same reader; the newer bug (#626) wins and #597's refusal survives only for trailing text that is not a reason. Main fixed #631 itself (4530f6f: collect passes `PP_VERDICT_READ=1`, which skips only the pane state and keeps the open-question check), so C2 reuses that switch for revise (#598) and close (#630) instead of adding a second one. #633, filed while the judge round ran, names no launch path past the existing second-agent block; the owner kept it open for its own unit (D22). #634 and #635, filed the next night, are C17 (a version check in the pre-push hook; a unit argument that starts with a dash refused); #636 asks whether the pane check #631 turned off can come back, which the logs cannot tell; the owner kept it open for its own unit, which first splits that refusal line in two and watches live runs (D27).

## Re-list

- Command: `gh issue list --state open --limit 200` in this repo at 2026-11-03 plan time
- Changed: the 55 open issues match the batch list (#605 is not open); #628, #629, #630, #631 and #632 were filed after it and are all in this unit (#629 added on plan-judge-sol finding 5); #631 was fixed on main in 4530f6f and closes as fixed; #633 was filed 2026-11-04 00:01Z and stays open for its own unit (D22); #634 (00:17Z), #635 and #636 (00:57Z) were filed before the last judge round: #634 and #635 are C17, #636 stays open for its own unit (D27) (`gh issue view <n> --json state,createdAt,body`, 2026-11-03)

## Triage

| Issue | Verdict | Reason or commit |
|---|---|---|
| #589 #592 #593 #594 #596 #597 #598 #601 #602 #603 #604 #607 #612 #616 #617 #619 #622 #623 #624 #625 #626 #627 | build (C1-C7) | plugin code, no unmerged host twin (C1 ports a merged one) |
| #595 | build (C9) | the owner approved the fixture edit |
| #588 | build part (C8) | port of the host's `--full` reads; the loud-fail half stays open |
| #531 | close (approved) | fixed in 29be9ca; companion-read-guard.test.sh carries the #531 case |
| #540 | close (approved) | fixed in a6af3c6; the Codex wrapper and gate cases exist |
| #570 | close (approved) | fixed in a6af3c6 and 38895bb (`pp_relay_event` at every outcome) |
| #572 | close (approved) | fixed in 38895bb (wake-on-exit.sh) |
| #599 #606 | close (approved) | fixed in a6af3c6 (driver loop, judge spec sentence) |
| #609 | close (approved) | fixed in 3a27d88: cleanup tars the evidence file with the briefs |
| #618 | close (approved) | fixed in bc91f715: the round count reads each report's last line |
| #523 #556 #558 #578 #580 | close (approved) | not plugin code (measured false, no red-proof script, no Adjacent convention, no ledger grant, host-only panel) |
| #591 #615 #621 | build part (C10-C12) | the sweep; the says-why line; the planning stage. Left: removal on diff apply; the missed restart's cause; the gap between plan seats |
| #628 | build (C3) | filed 2026-11-03; folded in on main's relay of the owner's order |
| #629 | build (C10) | filed 2026-11-03; a forced remove of a scratch worktree, the sweep's neighbour |
| #630 #632 | build (C2, C4) | filed 2026-11-03 after the plan; the owner's order covers every open plugin issue |
| #631 | close (fixed on main) | fixed in 4530f6f (collect settles with `PP_VERDICT_READ=1`; seat-settle.test.sh carries its cases); main closes it; C2 reuses the switch |
| #634 #635 | build (C17) | filed 2026-11-04; the pre-push hook runs ci/version-check.sh (the issue's own alternative, which covers every push, the Fast lane's included); merge-queue.sh's `--help` as the first argument already prints usage (c4ece92), so only a later dash argument is left |
| #636 | open, own unit (D27) | filed 2026-11-04; an investigation: the refusal it asks about prints one line for a working pane and an unread inbox alike (paths.sh:675), so the logs cannot say which caused #631 |
| #633 | keep open (D22) | filed 2026-11-04 00:01Z; the owner's answer keeps it for its own unit, which starts by finding the launch path; duplicate-agent-guard.sh already blocks a typed second agent in a worktree with a live agent pane, and the issue names no launch path past it |
| #587 #590 #611 #620 | build (C13-C16) | the owner's (a) answers: spec file beside the pointer; dead seats from Orca's exit events; move text unchanged; a Pre-merge hold |
| #506 #571 #600 #613 | close (approved) | the owner's (a) answers: built as far as code goes; landed-merge close kept; not reproducible; folded into #614 |
| #555 #576 #584 #585 #586 #608 #610 #614 | stays open (owner's answer) | waits on the host; the handle map later; live trials first; a measuring unit; own unit; next unit |

## Prior art

- Standard: POSIX sh and Bash 4 for every script; jq for JSON; git worktree porcelain; Orca's `orca-ide` CLI (`orchestration task-list --status`, `--full`)
- Library: none added; the paved road is the plugin's own scripts (`paths.sh`, `read-verdict.sh`, `hooks/lib/ruling-id.sh`)
- Main's own fixes reused: `PP_VERDICT_READ=1` (4530f6f, #631) for revise and close; the three paths.sh inbox reads already pass `--full` (991ec40), so C8 leaves paths.sh alone
- Host twin: one merged host change carries two twins: its `--full` reads (C8 takes only the read sites) and its hand-launch gate (C9 ports the jsonl log row, the `HAND LAUNCH:` line and the 24-hour dashboard alert rule)
- Host twin (C1): the host's merged #3681 verdict fix (its reason rule and choice-list rule; paths.sh `PP_VERDICT_END` and `PP_VERDICT_CHOICE`, read-verdict.sh `LOG_VERDICT_RE` lookahead, on its main 2026-11-03); C1 ports both rules word for word; every other cut has no host twin (none merged)

## Data design

- Hand-launch log (C9): `$PP_SCRATCH/seat-hand-launches.jsonl`, one `jq -nc` row `{at: <epoch s>, unit, role, reason}`; written by seat.sh launch on an override before the pane opens (a failed append refuses, nothing opened); read by dashboard.sh alerts() (rows of the last 24 h); never reset; a retry appends a row; absent means no hand launch
- Probe-pane log (C6): `$PP_SCRATCH/probe-panes.log`, one line `<UTC time> <approval id> <command head>`; written by duplicate-agent-guard.sh; read by the same hook to refuse a second use of an id; never reset
- Seat record `planref=` (C2): rewritten by seat.sh revise to the plan blob at revise time; read by `pp_plan_committed`
- Seat record `pty=` (C14): Orca's `ptyId` for the seat's handle, from `orca-ide terminal list --json` at launch; written by seat.sh launch with the record; read by main-watch's dead-seat check; an unread list writes `pty=` empty and one stderr line; a record with no pty value (any seat launched before this unit) is never reported dead
- Dead-seat item (C14): no new file; the check calls the existing `post dead-<unit>-<role>-<launched> "" <subject> <body> once`, the task argument empty as every other alert's, so post mints its own notification task (main-watch.sh:230-236) and never reads the seat's own task, whose `failed` or `completed` status would write `handled` and send nothing (main-watch.sh:238-240); the existing `$ST/item-<key>` file holds that notification task, a refused send leaves `posted=` empty and the next tick retries, a delivered one is settled `handled` on the next call (main-watch.sh:245), and a relaunch has a new launched epoch, so a new key
- Sweep stamp (C10): `$PP_SCRATCH/main-watch/sweep-stamp`, its mtime the last sweep; written by main-watch after each sweep, whatever its exit; read by main-watch to skip a sweep under an hour old; absent means sweep now; the sweep's output goes to `$PP_SCRATCH/main-watch/sweep.log`, rewritten each run; a failed sweep is retried the next hour
- Task-text file (C13): `$PP_SCRATCH/task-spec-<unit>-<role>-<epoch>.txt`; written by seat.sh launch and revise just before orca-task-create.sh; read by Orca through `--spec-file` (every retry of orca-task-create.sh); removed by seat.sh when task-create returns, ok or not; a crash between leaves one small file, never read again
- The log-missing note (C14) is a main-watch variable, no file; the cos watchers' seen files (C7) are existing state, now recreated when missing
- Pre-merge hold (C16; redesigned after passes 1, 2 and 3 found the heading class three times; main's ruling answer-1793778896-37094): a stamp, no parser. pp_merge_held keeps no state of its own. At every call it reads two files, the brief and `<unit>-evidence.md`, and nothing else.
  - The rule: a misread may only hold more, never less. The reader finds no section, heading or step, so no Markdown shape can drop a step.
  - Trigger: any line of the brief, anywhere and in any shape (heading, bold, list, prose, a code fence), that names pre-merge (`pre-merge`, `pre merge`, `pre_merge` or `premerge`, any case) holds the unit.
  - Done line: the whole line `Pre-merge: done <n>` in the evidence file, where n is the `cksum` of the whole brief file.
    - The hold prints the exact line, and the Builder writes it by hand once the steps have run.
    - A bare, misspelled or older line releases nothing. It needs no reset: any edit to the brief gives another n, so a step added, removed or changed after the line holds again.
    - Cost accepted: an unrelated brief edit after the done line also holds again until a new line is written (held more, never less).
  - A brief that names pre-merge nowhere is not held by this rule (unchanged from before this unit).
  - Retry path: there is one, whatever the source of the state.
    - On each main-watch tick, every DONE unit's gate calls pp_merge_held before it reads anything it keeps: `gate-<unit>`, `merge-<unit>` or the hold's posted item. merge-unit-local --auto calls it again at step 1 and step 4, under the lock.
    - So removing any kept file between two ticks does not release the hold: the next tick reads the brief and the evidence again. It holds while the line is missing or stale, and it merges at the first tick after the line is written.
- Section reader of the review pass (section_lines in builder-codex-pass.sh, for limits_check and plan_section; fix rounds 1 to 5; redesigned after passes 4 and 5 found the class-miss class twice): it keeps no state. For the limits gate it is a fixed list, not a parser: it reads only two literal heading lines and refuses every other line that names one of them.
  - The fixed list: the whole line `## ` plus the limits heading name (the plan's line 429) and the whole line `## ` plus the accepted-failures heading name (the plan's line 362), in column 0, case ignored, trailing spaces allowed. limits_check holds the two names; no other line starts a limits section.
  - Name rule (the gate's refusal): in the Builder's own copies, the worktree brief and the worktree plan, any other line whose letters contain either name refuses the pass, naming the file and the line: `<file> line <n>: names a limits heading outside its one heading line; write the heading as the literal line, and name it in prose as "the limits section"`. Letters means: lower case, HTML tags (`<...>`) and entities (`&...;`) removed, then every character that is not a to z removed. So no shape is parsed: `<h2>`, inline `**` or `_` inside the name, bold, setext, indented, `>`-quoted, a list item, extra words before or after, and prose all refuse alike. No limit of that file is compared until it is fixed.
  - The one exemption: a line that starts with `|` in column 0 (a table row, which is never a heading), so What can go wrong rows may cite the test labels that carry the name.
  - The baselines (main's brief, the plan at the merge base) are not checked: a baseline section read short only leaves more lines added, so it refuses more.
  - End: only a line outside a ``` or ~~~ fence ends a section: 0 to 3 spaces, then `#` or `##`, then a space or the end of the line. A wrong end only adds lines.
  - Lines: every non-blank line before the end is in the section, a deeper heading line and a whole-bold line included. Nothing in the section is filtered, so a bold limit or a new subheading is an added line and needs its approval.
  - Retry path: none is kept. Each pass reads the worktree files, main's brief and main's rulings again and rewrites `$LOCK/plan-at-base` from git, so removing that file or any other between two passes changes nothing: the next pass refuses again until the file is fixed.
  - plan_section feeds only reviewer prompt text (What can go wrong, Claims to falsify, Decisions, the accepted-failures section); it reads the same lines from a column-0 `#` heading that begins with the name and has no refusal, so a heading in another shape leaves that prompt text short and fails no gate.
- Limit approval (C4, #601): a line `Limit: <the limit line, exact> ruling:<id>` in main's `$MAIN/.claude/briefs/<unit>-main-rulings.md`; written by main by hand, the refusal printing the line to add; read by limits_refuse on every pass, which accepts it only when the text matches the added limit line exactly and ruling_id_ok passes the id (logged, not void); never reset by the pass (a void id stops passing at once); a missing or unreadable file approves nothing; a retry reads the file again
- No other state is added or changed

## Cuts

- C1 verdict line (#626, #597), ~75 lines
  - Produces: read-verdict.sh accepts `VERDICT: <word>` followed by `.` `,` `;` `:` or a spaced `-`, `—`, `–` or `(` and a reason (the host's `PP_VERDICT_END`), printing the same canonical `VERDICT: <word>` line; any other trailing text stays no verdict
  - Produces: a verdict line whose reason names a second verdict word (`GO`, `DONE`, `REVISED`, `REQUIRED`, `APPROVED`, `REJECTED`, after any `[A-Z-]` run, so `NO-GO` too) is a choice list and no verdict, in the pane scan (the host's `PP_VERDICT_CHOICE`, a `VERDICT_CHOICE` beside VERDICT_RE) and in both session-log jq regexes (the host's negative lookahead): `VERDICT: GO,NO-GO`, `VERDICT: GO, NO-GO`, `VERDICT: GO (or NO-GO)` read no verdict, never GO
  - Bad input: trailing text is the parse's bad input: a choice list spaced and unspaced, `GO or NO-GO`, `GO means` (four read-verdict.test.sh cases); empty or absent is today's no verdict, unchanged
  - Produces: seat.sh collect's no-verdict message names the bare form when a `VERDICT:` line has other trailing text; the judge spec says the verdict line stands alone
  - Consumes: none
  - Existing consumers: seat.sh collect, main-watch.sh, orca-wait.sh, unit-drive.sh report reads, builder-codex-pass.sh, cos-watch-inbox.sh, board.sh (all read the canonical line, unchanged)
- C2 seat lifecycle (#598, #604, #612, #630), ~146 lines
  - Produces (#598, D16): seat.sh revise of a live pane that does not read idle reads the seat's latest answer with collect's own reader (seat.sh:741-746, moved into one `read_finish` function both call; the marker is the record's `marker=` line); a `VERDICT:` banner or the marker there skips revise's pane-busy refusal and settles the old task with `PP_VERDICT_READ=1 pp_task_close`, main's #631 switch: the open-question check still runs and a refusal exits 1 with the record intact and nothing sent; the live-pane check stays; with no finish read, today's refusal stands, its message adding `no finish in its latest answer`
  - Produces (#598, D16, current revision): when the record's last `revised=` names its current `task=` (a revised seat), the finish counts only once `read-verdict.sh --state --worktree <wt> --task <task> --launched <launched>` prints `session=` (main-watch's revised_ran test, main-watch.sh:1179-1184): before the revised prompt lands, the latest answer is the previous task's; with no proof, today's refusal stands, its message adding `revised prompt not landed`
  - Produces: collect's rerun closes a still-live plan-judge pane (logged by `pp_pane_close`); revise resets the record's `planref=`
  - Produces (#630): `seat.sh close <role> <unit>`: when the record's last `verdict=`/`revised=` line is a verdict, settles each `task=`/`answer_task=` with no `settled=` line through `PP_VERDICT_READ=1 pp_task_close` and closes a live pane, printing `closed seat=<role> unit=<unit> <verdict>`; with no recorded verdict it changes nothing and exits 3 naming `seat.sh collect`; no seat record exits 2
  - #631: no change; main's 4530f6f fix stands (D12)
  - Consumes: main's `PP_VERDICT_READ` switch in pp_task_close (paths.sh:669, unchanged)
  - Existing consumers: pp_task_close is not changed (no new argument), so answer-worker.sh, main-watch.sh, orca-wait.sh, builder-fresh-round.sh, seat.sh collect, merge-unit-local.sh and unit-close.sh keep today's behaviour; revise's callers are main by hand and its docs (unit-drive.sh reruns through `seat.sh run`, unit-drive.sh:183); pp_plan_committed in seat.sh and claude-worker-notify.sh
- C3 labels and decisions (#596, #607, #616, #624, #628), ~195 lines
  - Produces: one unescape rule in all three name readers (test-edit-labels.sh, new-test-count.sh's parser `name()` and its regex `js_regex()`): a backslash before `'`, `"`, a backtick or a backslash is dropped; any other escape stays as written
  - Produces: the reader resolves typescript first (`require.resolve`) and exits 3 when the package is absent, 2 when a found package fails to load or parse (D17); new-test-count.sh falls back to the label regex only on exit 3, printing the reader's line; any other reader failure or unreadable reader output exits 2 naming it
  - Produces: decision.sh test-edit refuses a label the lister does not print for that path in the unit's worktree, printing the exact names; with no worktree it records as today with a warning
  - Produces: decision.sh dup never matches two push asks whose tip suffixes differ; answer sends main one `to-main.sh answer` message when the decision's source is `main` or `decision.sh push-ask` (D5)
  - Consumes: C3's own label fix (the test-edit check runs the fixed lister)
  - Existing consumers: builder-codex-pass.sh (lister, label compare), every decision.sh caller
- C4 driver and pass (#625, #622, #601, #632), ~130 lines
  - Produces: unit-drive.sh copies `(P0)`-`(P3)` findings into the revise brief; builder-fresh-round.sh types nothing for `<unit>-fix-r<N>.md` when a `<unit>-r<M>-reports.md` with M > N exists; limits_refuse passes a limit line that main's rulings file carries as `Limit: <line> ruling:<id>` with a valid id
  - Produces (#632): the question gate, finding no answer in this project's ledger, reads each other repo `orca-ide repo list --json` names (`.result.repos[].path`) through `COMMANDECK_MAIN=<path> decision.sh list`, with the same id and after-ask filter, and takes another repo's row only when its question or source carries this ask's token `plan <first 8 of the plan hash>` (D15); the ask to main says to keep that token in the decision; a matching row without the token says one line on stderr and is not taken; an unreadable repo list or another repo's failed list says one line on stderr per gate entry and the gate goes on with what it read
  - Consumes: none
  - Existing consumers: the gate's only reader is unit-drive.sh itself; decision.sh list is unchanged
- C5 merge (#623, #589, #594), ~85 lines
  - Produces: cut_scan counts cut n built when the brief, outside fences, names exactly one cut (`Cut <n>`) and the closing GO already proven at step 1 holds; cleanup names the worktree and Orca's reason when removal fails or the folder is still there
  - Produces: merge-queue.test.sh fails when the real checkout's own git folder changes during the run
  - Consumes: none
- C6 hooks (#593, #603, #592), ~145 lines
  - Produces: bash-guardrails.sh, for an assignment in a segment after `&&` or `||`, drops any earlier binding of the name and records none, so `F=scripts; true && F=.; rg x "$F"` reads `$F` as unknown; duplicate-agent-guard.sh lets main open one hand-made pane per valid, unused approval id given as a `COMMANDECK_PROBE_PANE=<id>` command prefix, logged
  - Produces: context-line.sh's over-the-line message (the one below the 40K mark) names how far past the line main is, `<n>K past the <line>K line`; context-clear-stop.test.sh pins it at 181K and 466K and silence at 180K
  - Consumes: none
- C7 watchers and helpers (#619, #617, #627, #602), ~120 lines
  - Produces: both cos watchers treat a missing seen file as empty and recreate it; host-services.sh finds its folder under zsh and, not in bash, sets the sourcing shell's PATH from a bash child that loads requirements.sh alone and prints its repaired PATH (kept only when non-empty, D6); dashboard.sh removes a killed cycle's temp files before it logs the kill; answer-worker.sh falls back to the unit's newest live plan-author seat when no Builder runs
  - Consumes: C2's seat record shape
- C8 orchestration reads (#588 part), ~70 lines
  - Produces: `--full` on every `orchestration inbox`, `task-list` and `check` read that uses a field only the full view has; a guard test over scripts and hooks
  - Produces (check reads, D23): `orchestration check` gains `--full` at ask-main.sh:25 and :76 (`thread_id`, `body`, `from_handle`), cos-own-echo.sh:54 (`from_handle`), watch-agents.sh:42 (`body`), inbox-drain.sh:68 (`body`; its sender reads `.from_handle // .from`, since the full row has no `from`) and orca-wait.sh:531 and :533 (`from_handle`, `body`); the worker-brief lines at builder-codex-pass.sh:2464 and builder-add-work.sh:66 that name check's `.result.dispatchId` add `--full`; await-agents.sh:67 reads only `.type`, which the concise row has, and is unchanged
  - Builder check before C8: send this pane a status probe and run `orca-ide orchestration check --terminal <own handle> --wait --timeout-ms 2000 --full --json`; if `.result.deliveryId` is present, ask-main.sh's loop is unchanged beyond `--full`; if absent, ask-main.sh:81 breaks only on an empty batch and acks only when a deliveryId was read, so a batch holding the answer is printed, never dropped
  - Produces: the wake's task-list read (orca-wait.sh:466) passes `--full`, so its landed-merge close (473) and task lines (476-477) see `.spec`; the awareness hook's read (agent-awareness.sh:72) swaps `--brief` for `--full`, so its task lines (124) see `.spec`/`.task_title` (Orca 1.4.246's concise and `--brief` rows carry only id, status and title: settled in Assumptions)
  - Consumes: C4 (builder-codex-pass.sh), C7 (dashboard.sh); paths.sh is not touched (main's 991ec40 added its three `--full` reads)
  - Existing consumers: orca-wait.sh's wake text and landed-merge close; agent-awareness.sh's open-task block; ask-main.sh's answer wait and resume; cos-own-echo.sh's echo drop; watch-agents.sh's answer-needed lines; inbox-drain.sh's start-up drain; the Builder and add-work briefs' dispatch-id line; main-watch.sh, claude-worker-notify.sh, cos-check.sh, cos-watch-inbox.sh, dispatch-task.sh, board.sh and dashboard.sh readers (each reads the same keys, now present)
- C9 hand-launch gate (#595), ~75 lines
  - Produces: seat.sh launch refuses a plan-author, plan-judge or plan-revise launch with neither `COMMANDECK_DRIVER=1` nor `COMMANDECK_HAND_LAUNCH=<reason>`, naming `unit-drive.sh start` and the override
  - Produces (D28): `COMMANDECK_DRIVER=1` is read first: a driver launch passes and logs no row and no `HAND LAUNCH:` line whatever `COMMANDECK_HAND_LAUNCH` holds; an empty `COMMANDECK_HAND_LAUNCH` counts as absent
  - Produces (the host's port, D19): the override appends one jsonl row to the hand-launch log and prints `HAND LAUNCH: <role> <unit>: <reason>` on stderr; a failed append refuses with nothing opened; a dashboard_alerts.jq rule raises one warn alert `hand-launch-<unit>-<role>-<at>` per row of the last 24 h, naming the unit and `unit-drive.sh start`
  - Catches: a plan seat opened by hand that nothing chains, so the finished plan sits idle (#595's 9 idle minutes)
  - Consumes: C2 (seat.sh), C4 (unit-drive.sh hints carry the override)
  - Existing consumers: unit-drive.sh (driver, exports COMMANDECK_DRIVER=1), seat.sh relaunch (passes COMMANDECK_DRIVER=1), every seat test via the shared fixture; dashboard.sh alerts() and the alerts list it feeds (one more input file); the two direct `seat.sh run plan-judge-sol` calls at seat-run-refused.test.sh:50-51 and seat-run.test.sh:63-65, which bypass seat_sh and inherit the fixture-wide export (D28)
- C10 worktree sweep and scratch removal (#591 part, #629), ~251 lines
  - Produces: new scripts/worktree-sweep.sh: removes each git worktree under the checkout's `.claude/worktrees/` (helper) or under `$PP_SCRATCH` (scratch) that is clean (D9a: `git status --porcelain --untracked-files=all` empty and no `git ls-files -v` line tagged lowercase or `S`, as git-safety.sh wt_clean reads it; a failing status or ls-files is not clean), holds no live process's working directory (`lsof -a -d cwd -Fn`; D9b: an lsof that exits non-zero or names no working directory keeps every candidate) and whose index and HEAD log are over 24 hours old, with `git worktree remove` (never `--force`); prints one line per removal
  - Produces (D9): its branch is deleted with `git branch -d` only when the tip is in main (`git merge-base --is-ancestor <tip> refs/heads/main`); an unmerged branch is kept, printed `kept branch <name> <tip>: not in main`; a worktree on a detached HEAD not in main is kept whole and printed
  - Produces: main-watch.sh runs it at most once an hour (the sweep stamp, Data design)
  - Produces (#629, D18): git-safety.sh passes a forced `git [-C <dir>] worktree remove -f|--force <absolute path>` (the existing fixed-list form) whose canonical path lies strictly under the scratch root `${COMMANDECK_SCRATCH:-$HOME/.commandeck/scratch}`, dirty or not; anywhere else the clean-status rule stands
  - Catches: stale helper and scratch copies left by a missed removal (#591's about 70 in three days), never unmerged commits
  - Consumes: none
  - Existing consumers: every agent Bash call through git-safety.sh (only a forced remove under the scratch root changes)
- C11 restart says why (#615 part), ~40 lines
  - Produces: context-clear-stop.sh, when the context size cannot be read in main's pane, prints one line on stderr and in clear-hook.log instead of exiting silently
  - Consumes: none
- C12 re-judged unit stage (#621 part), ~45 lines
  - Produces: dashboard.sh sets stage `planning`, not `waiting-main`, for a built unit with a plan seat record launched after the Builder's first stage whose last `verdict=`/`revised=` line is not a verdict (none, or a later `revised=`: the seat.sh:801 rule); units-elements.ts already draws planning with Build and Review todo
  - Consumes: C8 (dashboard.sh)
  - Existing consumers: hooks/units-elements.ts stepsOf, the units view and band
- C13 spec file (#587), ~35 lines
  - Produces: seat.sh launch and revise write the task text (the typed pointer, unchanged) to a file in `$PP_SCRATCH` and pass `--spec-file` to orca-task-create.sh instead of `--spec`, so Orca's task holds it whole; the typed pointer stays, so verdict lookups by pointer text are unchanged
  - Consumes: C9 (seat.sh)
  - Existing consumers: dispatch-task.sh type_pointer (reads the task spec back, same text), main-watch.sh's own task-create (unchanged)
- C14 dead seats (#590), ~107 lines
  - Produces: seat.sh launch writes `pty=<ptyId>` for its handle from `orca-ide terminal list --json` (Data design)
  - Produces: each main-watch tick reads the tail of Orca's daemon log (D20: `COMMANDECK_ORCA_LOG`, else `$HOME/Library/Application Support/orca/logs/daemon.log` on Darwin, `$HOME/.config/orca/logs/daemon.log` elsewhere), one JSON object per line, taking rows with `event == "session-exited"` whose `sessionId` equals a seat's `pty=` exactly and whose `ts` is at or after its launch, then keeping only the latest such row per sessionId, and only then dropping it when its `cause` is `operator_close` (D11: an `unknown` row followed by an `operator_close` row is an operator close); a non-Builder seat whose current episode has no finish (D21), whose pane is not in the terminal list and whose latest exit row survives gets one main-watch item naming the seat and its unit, posted through the existing `post <key> "" ... once` path with an empty task argument (Data design), no mark file of its own
  - Produces (D21): a seat's current episode has a finish when any holds: its record's last `verdict=`/`revised=` line is a verdict (the seat.sh:801 rule; a revise appends `revised=`, so an old verdict stops counting); main-watch's own state for its current task (`$ST/kind-seat-<handle>-<task>`, the key seat() writes, main-watch.sh:1188; revise replaces `task=`, so the key is new) holds `finished`, never `silent` or any other word (main-watch.sh:1263-1266); the seat-bound report reader finds a finish in its session log: `read-verdict.sh <handle> 5 <worktree> <agent> "" "" "" <launched>` prints a `VERDICT:` or `-DONE` line (has_result's test, main-watch.sh:726-731, bound by the seat's worktree, agent and launch epoch, so the log is read with the pane gone: settled in Assumptions), and for a revised seat (its record's last `revised=` names its current task) only when `revised_ran <worktree> <revised task> <launched>` (main-watch.sh:1182) says the revised prompt landed, since the reader takes the answer after the session's latest prompt, which before that is the old task's; no other reader and no `--state` result counts
  - Produces: no log found prints one line once per main-watch start, never a silent skip
  - Catches: a seat whose pane died before its verdict, which today main learns of late or never (#590)
  - Consumes: C10 (main-watch.sh), C13 (seat.sh)
  - Existing consumers: every seat record reader (board.sh, dashboard.sh plan_seats, seat.sh, the awk readers) reads named keys, so one more `pty=` line changes none
- C15 startup trim (#611), ~40 lines
  - Produces: templates/main-session.md moves three procedural lines of its injected part (the background-run line, the gone-Builder relaunch line, the plan-question send line) word for word under its Details heading, each leaving a one-line pointer; the injected part drops from 6,198 bytes to about 5,500
  - Consumes: C9 (main-session.md)
- C16 pre-merge hold (#620), ~40 lines
  - Produces: pp_merge_held also holds a unit whose brief names pre-merge on any line, in any shape, until its evidence file has the `Pre-merge: done <n>` line the hold names, n the cksum of the whole brief (Data design, the stamp); the builder brief template describes the hold without the word, since a template line naming it would hold every unit
  - Catches: an auto-merge that lands before a step the brief says must run first (#620)
  - Consumes: none (no earlier cut edits paths.sh)
  - Existing consumers: main-watch.sh merge gate, merge-unit-local.sh --auto
- C17 push and queue guards (#634, #635), ~40 lines
  - Produces (#634): .githooks/pre-push, for a push to refs/heads/main whose pushed tree holds ci/version-check.sh, runs it in the pushed tree's worktree (the one the shell tests already use) against the remote's old sha, or origin/main when that sha is all zeros, and refuses the push on any non-zero exit, version-check's own lines on stderr
  - Produces (#635): merge-queue.sh refuses a unit argument that does not start with a letter or digit (`u1 --help`, `--train --help`), exit 2 with its usage, nothing merged; a first `-h`/`--help` keeps its usage exit 0 (merge-queue.sh:16)
  - Bad input: listed in What can go wrong (a later `--help` argument); the remote sha is git's own pre-push stdin, all zeros for a new branch (origin/main then)
  - Catches: a plugin change pushed to main with no version bump, which today only GitHub's CI catches after main is red (#634)
  - Consumes: C5 (merge-queue.test.sh)
  - Existing consumers: every push to main from a checkout wired to .githooks; main-watch.sh merge_start (main-watch.sh:1141, unit names only) and main by hand call merge-queue.sh

Break: scripts/__tests__/read-verdict.test.sh -- a spec line VERDICT: GO means is still no verdict -- scripts/read-verdict.sh VERDICT_RE
Break: scripts/__tests__/read-verdict.test.sh -- an unspaced choice list VERDICT: GO,NO-GO is no verdict in the pane or the session log -- scripts/read-verdict.sh VERDICT_CHOICE
Break: scripts/__tests__/seat-settle.test.sh -- seat.sh revise on a revised seat whose revised prompt has not landed is refused though the old answer ends on PLAN-DONE -- scripts/seat.sh revise current-revision check
Break: scripts/__tests__/main-watch-dead-seat.test.sh -- a dead seat whose own task is failed in the task list still gets one item -- scripts/main-watch.sh dead-seat post call
Break: scripts/__tests__/seat-collect-once.test.sh -- a judge pane with no verdict yet is not closed -- scripts/seat.sh collect rerun close
Break: scripts/__tests__/seat-settle.test.sh -- seat.sh revise on a finished seat with an open question is still refused and sends nothing -- scripts/seat.sh revise verdict-read settle
Break: scripts/__tests__/seat-settle.test.sh -- seat.sh revise on a seat whose pane reads working with no finish in its latest answer is still refused -- scripts/seat.sh revise finish read
Break: scripts/__tests__/seat-settle.test.sh -- seat.sh close on a seat with no recorded verdict closes nothing and names collect -- scripts/seat.sh close verdict check
Break: scripts/__tests__/unit-drive.test.sh -- an answer in another repo's ledger from before the ask does not release the gate -- scripts/unit-drive.sh question gate other-ledger read
Break: scripts/__tests__/decision.test.sh -- a near-miss test-edit label is refused and the exact names are printed -- scripts/decision.sh test-edit
Break: scripts/__tests__/builder-fresh-round.test.sh -- a fix brief whose round has a later pass report types nothing -- scripts/builder-fresh-round.sh skip check
Break: scripts/__tests__/builder-codex-pass-limits.test.sh -- a limit whose rulings id is void or absent is refused -- scripts/builder-codex-pass.sh limits_refuse
Break: hooks/__tests__/bash-guardrails-assign.test.sh -- a search path from an assignment after && is judged unresolved -- hooks/bash-guardrails.sh load_segments
Break: hooks/__tests__/duplicate-agent-guard.test.sh -- a reused approval id is blocked -- hooks/duplicate-agent-guard.sh hand case
Break: scripts/__tests__/seat-plan-judges.test.sh -- a hand launch of a plan seat is refused naming unit-drive.sh -- scripts/seat.sh launch gate
Break: scripts/__tests__/worktree-sweep.test.sh -- a helper worktree with uncommitted files is kept -- scripts/worktree-sweep.sh remove call
Break: scripts/__tests__/worktree-sweep.test.sh -- a stale helper worktree with an assume-unchanged edit is kept -- scripts/worktree-sweep.sh clean check
Break: scripts/__tests__/worktree-sweep.test.sh -- a stale clean helper worktree is kept when lsof fails -- scripts/worktree-sweep.sh process check
Break: scripts/__tests__/main-watch-dead-seat.test.sh -- a seat revised after its verdict whose pane then exits is reported -- scripts/main-watch.sh dead-seat finish check
Break: scripts/__tests__/unit-drive.test.sh -- another repo's answer that names no plan hash does not release the gate and says one line -- scripts/unit-drive.sh question gate token check
Break: scripts/__tests__/worktree-sweep.test.sh -- a stale clean helper worktree whose branch is not in main is removed and its branch kept -- scripts/worktree-sweep.sh branch delete
Break: hooks/__tests__/git-safety.test.sh -- a forced remove whose path climbs out of the scratch root with .. is blocked -- hooks/git-safety.sh worktree remove rule
Break: hooks/__tests__/git-safety.test.sh -- a forced remove of a dirty worktree outside the scratch root is blocked -- hooks/git-safety.sh worktree remove rule
Break: scripts/__tests__/ci-pre-push.test.sh -- a push to main of a plugin change with no version bump is refused naming version-check -- .githooks/pre-push version check
Break: scripts/__tests__/merge-queue.test.sh -- a unit argument that starts with a dash is refused and nothing merges -- scripts/merge-queue.sh argument check
Break: scripts/__tests__/main-watch-merge-gate.test.sh -- a brief with a Pre-merge section holds the merge until the evidence says Pre-merge: done -- scripts/paths.sh pp_merge_held

## Steps

- modify scripts/read-verdict.sh ~496 -- VERDICT_RE, the two session-log jq regexes (~649, ~675), verdict_word (~552) and drop_go (~538) accept a reason by the host's PP_VERDICT_END; print the canonical line (~934)
- modify scripts/read-verdict.sh ~529 -- a new VERDICT_CHOICE (the host's PP_VERDICT_CHOICE) excludes a choice-list line in the pane scan, and the host's lookahead does so in both jq regexes (~649, ~675)
- modify scripts/seat.sh ~535 -- the plan-judge spec says the verdict line stands alone with nothing after it
- modify scripts/seat.sh ~802 -- the no-verdict message names the bare `VERDICT: GO` form when a `VERDICT:` line has other trailing text
- modify scripts/seat.sh ~741 -- collect's report read (741-746) becomes `read_finish`, called by collect unchanged and by revise
- modify scripts/seat.sh ~245 -- revise: a pane not read idle whose latest answer `read_finish` reads as finished skips the pane-busy refusal and settles the old task with `PP_VERDICT_READ=1 pp_task_close`; otherwise the refusal stands, adding `no finish in its latest answer` (#598)
- modify scripts/seat.sh ~245 -- revise: for a revised seat (last `revised=` equals `task=`) the finish counts only when `read-verdict.sh --state --task <task>` prints `session=`; else the refusal stands, adding `revised prompt not landed`
- modify scripts/seat.sh ~801 -- a collect rerun on a plan-judge seat with a recorded verdict closes its pane when still live
- modify scripts/seat.sh ~257 -- revise rewrites `planref=` to the worktree's current plan blob
- modify scripts/seat.sh ~62 -- `close <role> <unit>` in the command list and usage: settle with `PP_VERDICT_READ=1` and close a seat with a recorded verdict; exit 3 naming collect when none (#630)
- modify scripts/test-edit-labels.sh ~44 -- a quoted label skips escaped quotes and applies the one unescape rule
- modify scripts/new-test-count.sh ~112 -- name() applies the one unescape rule to a string literal's text
- modify scripts/new-test-count.sh ~151 -- js_regex() applies the same unescape rule to each captured label
- modify scripts/new-test-count.sh ~51 -- the reader resolves typescript before loading it: exit 3 when absent, exit 2 for a load failure
- modify scripts/new-test-count.sh ~163 -- js_tests_all: regex only on the reader's exit 3, said on stderr; any other reader failure exits 2
- modify scripts/decision.sh ~278 -- test-edit refuses a label the lister does not print for the path in the unit's worktree; warns and records when there is no worktree
- modify scripts/decision.sh ~127 -- dup skips a candidate when both ids are push asks with different tip suffixes
- modify scripts/decision.sh ~66 -- deliver_answer sends main one `to-main.sh answer` message for source `main` or `decision.sh push-ask`
- modify scripts/unit-drive.sh ~295 -- the finding grep also copies `(P0)`-`(P3)` lines
- modify scripts/unit-drive.sh ~236 -- the question gate also reads each other Orca repo's ledger through `COMMANDECK_MAIN=<path> decision.sh list`, taking a row only with the `plan <hash8>` token (#632)
- modify scripts/unit-drive.sh ~230 -- the ask to main says to keep `plan <hash8>` in the decision's question
- modify scripts/builder-fresh-round.sh ~105 -- after the idle wait, skip a fix hand-off whose round has a later reports file
- modify scripts/builder-codex-pass.sh ~1666 -- limits_refuse passes a line main's rulings file carries with a valid id; the refusal names that rulings line
- modify scripts/merge-unit-local.sh ~536 -- cut_scan adds the one cut the brief names, outside fences
- modify scripts/merge-unit-local.sh ~204 -- cleanup reports the worktree name and Orca's reason, and checks the folder is gone
- modify hooks/bash-guardrails.sh ~123 -- the splitter flags a segment after `&&` (flag 3; `||` is already 2)
- modify hooks/bash-guardrails.sh ~214 -- load_segments, for an assignment in a flag 2 or 3 segment, keeps the unset of the earlier binding and records no alias
- modify hooks/context-line.sh ~76 -- the over-the-line message names `<n>K past the <line>K line`
- modify hooks/duplicate-agent-guard.sh ~208 -- the main-checkout hand block passes a `COMMANDECK_PROBE_PANE=<id>` prefix with a valid, unused id, logged; the block message names it
- modify scripts/cos-watch-alerts.sh ~38 -- a missing seen file reads as empty
- modify scripts/cos-watch-decisions.sh ~13 -- poll recreates the seen file before each read
- modify scripts/host-services.sh ~11 -- HS_DIR falls back to `${0}` under zsh; line 16, not in bash, sets and exports PATH from `bash -c` loading requirements.sh alone and printing PATH
- modify scripts/dashboard.sh ~1648 -- remove the killed cycle's temp files before the kill log line
- modify scripts/answer-worker.sh ~75 -- with no Builder pane, use the unit's newest live plan-author seat record's handle
- modify {scripts/main-watch.sh,hooks/claude-worker-notify.sh,scripts/cos-check.sh,scripts/cos-watch-inbox.sh,scripts/dispatch-task.sh,scripts/board.sh} -- add `--full` to the inbox and task-list reads that use full-only fields
- modify scripts/dashboard.sh ~1044 -- add `--full` to the inbox read
- modify scripts/orca-wait.sh ~466 -- the wake's task-list read passes `--full`
- modify hooks/agent-awareness.sh ~72 -- the task-list read passes `--full` in place of `--brief`
- modify {scripts/ask-main.sh,hooks/cos-own-echo.sh,scripts/watch-agents.sh,scripts/inbox-drain.sh} -- `orchestration check` reads pass `--full`; inbox-drain's sender reads `.from_handle // .from` (D23)
- modify scripts/orca-wait.sh ~531 -- the two `check` reads (531, 533) pass `--full`
- modify {scripts/builder-codex-pass.sh,scripts/builder-add-work.sh} -- the brief line naming check's `.result.dispatchId` adds `--full` (2464; 66)
- modify scripts/ask-main.sh ~81 -- only if the C8 Builder check finds no deliveryId: break on an empty batch only, ack only a read deliveryId
- new scripts/__tests__/orca-full-flag.test.sh -- guard: each read of a full-only field passes `--full`, `check` reads included
- modify scripts/seat.sh ~281 -- launch gate for plan seats; the override appends the jsonl row (refusing on a failed append) and prints `HAND LAUNCH:`
- modify scripts/dashboard.sh ~1101 -- alerts() passes the hand-launch rows of the last 24 h to the rules
- modify scripts/dashboard_alerts.jq -- one warn alert per hand-launch row, naming the unit and `unit-drive.sh start`
- modify scripts/__tests__/dashboard-alerts.test.sh -- hand-launch alert cases
- modify scripts/unit-drive.sh ~277 -- every hand-rerun hint carries `COMMANDECK_HAND_LAUNCH`
- modify templates/main-session.md ~8 -- plan seats launch through unit-drive.sh; a hand launch needs the override
- modify scripts/__tests__/fixtures/seat-setup.sh ~11 -- `export COMMANDECK_HAND_LAUNCH=fixture` fixture-wide, so seat_sh and the direct seat.sh runs in seat-run-refused.test.sh and seat-run.test.sh inherit it; a refusal case unsets it in its own subshell (D8, D28)
- modify {scripts/__tests__/read-verdict.test.sh,scripts/__tests__/seat-collect-once.test.sh,scripts/__tests__/seat-plan-judges.test.sh,scripts/__tests__/seat-settle.test.sh,scripts/__tests__/seat-revise.test.sh} -- new cases
- modify {scripts/__tests__/test-edit-labels.test.sh,scripts/__tests__/new-test-count.test.sh,scripts/__tests__/decision.test.sh,scripts/__tests__/unit-drive.test.sh,scripts/__tests__/builder-fresh-round.test.sh} -- new cases
- modify {scripts/__tests__/builder-codex-pass-limits.test.sh,scripts/__tests__/merge-unit-local-cuts.test.sh,scripts/__tests__/merge-unit-local-cleanup.test.sh,scripts/__tests__/merge-queue.test.sh} -- new cases
- modify {hooks/__tests__/bash-guardrails.test.sh,hooks/__tests__/duplicate-agent-guard.test.sh,hooks/__tests__/context-clear-stop.test.sh} -- new cases
- modify {scripts/__tests__/cos-tell.test.sh,scripts/__tests__/long-job.test.sh,scripts/__tests__/answer-worker.test.sh} -- new cases
- new scripts/worktree-sweep.sh -- the idle helper and scratch worktree sweep; clean is empty status and no assume-unchanged or skip-worktree tag (D9a); `git branch -d` only for a tip in main
- modify scripts/main-watch.sh ~26 -- run worktree-sweep.sh at most once an hour from the machine-safety tick, stamp and log in `$PP_SCRATCH/main-watch`
- new scripts/__tests__/worktree-sweep.test.sh -- sweep cases
- modify hooks/git-safety.sh ~330 -- a forced remove in the fixed-list form passes when its canonical path is under the scratch root (#629)
- modify hooks/__tests__/git-safety.test.sh -- scratch-root forced-remove cases
- modify hooks/context-clear-stop.sh ~29 -- an unreadable context size in main's pane says why in one line
- modify scripts/dashboard.sh ~401 -- a built unit with a plan seat launched after its Builder whose last verdict=/revised= line is not a verdict shows planning
- modify {hooks/__tests__/context-clear-stop.test.sh,scripts/__tests__/dashboard-built-planning.test.sh} -- new cases
- modify scripts/seat.sh ~566 -- launch passes the task text with `--spec-file` and removes the file after; revise (~249) the same
- modify scripts/__tests__/seat-revise.test.sh ~14 -- the task-create stand-in also logs the text of the file `--spec-file` names; the issue-485 check unchanged (D26)
- modify scripts/seat.sh ~573 -- launch writes `pty=` from the terminal list for its handle
- modify scripts/__tests__/fixtures/seat-setup.sh ~49 -- the task-create stand-in records its arguments (an added line)
- modify scripts/main-watch.sh ~1298 -- the dead-seat check from Orca's latest exit row per exact pty, cause filtered after that pick, posted by `post <launch key> "" ... once` (empty task: post mints its own notification task), skipping a seat whose current episode has a finish (D21: a `finished` state file only, and the seat-bound positional reader only, gated by revised_ran for a revised seat); the log default per D20
- new scripts/__tests__/main-watch-dead-seat.test.sh -- dead-seat cases on the main-watch fixture
- modify templates/main-session.md ~7 -- move lines 7, 11 and 24 under Details word for word, a pointer in each place
- modify scripts/paths.sh ~1478 -- pp_merge_held holds on a brief naming pre-merge with no `Pre-merge: done <n>` evidence line for the whole brief
- modify templates/_builder-brief-template.md ~8 -- one sentence on the hold and its done line, without the word itself
- modify {scripts/__tests__/seat-launch.test.sh,scripts/__tests__/startup-size.test.sh,scripts/__tests__/main-watch-merge-gate.test.sh} -- new cases
- modify README.md ~283 -- unit-drive.sh start is how plan seats launch; a hand `seat.sh launch` of a plan seat needs `COMMANDECK_HAND_LAUNCH=<reason>`, which is logged and shows a dashboard alert for 24 h (C9)
- modify docs/commands.md ~73 -- seat revise: a seat whose latest answer holds its finish is revised though its pane reads working, an open question still refuses, and collect ends a seat (it closes the pane), so revise comes before collect; a new `## seat close` section: usage, the recorded-verdict rule, exit 3 naming collect; a hand plan-seat launch needs `COMMANDECK_HAND_LAUNCH=<reason>` (C2, C9)
- modify docs/hooks.md ~18 -- duplicate-agent-guard.sh: main opens one owner-approved probe pane with a `COMMANDECK_PROBE_PANE=<approval id>` prefix, one pane per id, logged (C6); git-safety.sh row (~15): a forced remove under the scratch root passes dirty or not, elsewhere the clean-status rule stands (C10)
- modify CHANGELOG.md -- plain user-facing notes for the new version
- modify .claude-plugin/plugin.json -- version bump
- modify .githooks/pre-push ~29 -- in the pushed tree's worktree, run ci/version-check.sh when present against the remote sha (origin/main for all zeros); refuse on non-zero (#634)
- modify scripts/merge-queue.sh ~22 -- the unit pattern starts with a letter or digit, so a later dash argument is refused with usage (#635)
- modify {scripts/__tests__/ci-pre-push.test.sh,scripts/__tests__/ask-main.test.sh,scripts/__tests__/to-main.test.sh} -- new cases (C17; C8)

## Decisions already made

- D1 (#626 over #597): the reader accepts a reason by the host's merged #3681 rule (after `.,;:` or a spaced `-`, `—`, `–` or `(`) and drops a line whose reason names a second verdict word (the host's choice-list rule), in the pane scan and both session-log readers; other trailing text stays no verdict, and collect then names the bare form. #626 is the newer bug and keeps the end anchor's guard against injected spec text; the choice rule keeps a template's `VERDICT: GO, NO-GO` from reading GO.
  - Test: scripts/__tests__/read-verdict.test.sh -- a spec line VERDICT: GO or NO-GO is still no verdict; an unspaced choice list VERDICT: GO,NO-GO is no verdict in the pane or the session log; a spaced choice list VERDICT: GO, NO-GO is no verdict in the pane or the session log
- D2 (#595): the gate covers plan seats only. Builders launch through builder-launch.sh, and main-session.md documents a hand `seat.sh launch builder` relaunch, so gating Builders would refuse the sanctioned paths.
  - Test: scripts/__tests__/seat-plan-judges.test.sh -- a driver launch of a plan seat passes with no override
- D3 (#627): the cause is the kill log line printed before the cleanup, not a shared path (the test already has its own out2); the code order is the fix, and the existing check stays unedited.
  - Test: scripts/__tests__/dashboard-loop.test.sh -- a killed cycle leaves no temporary files and no data.js
- D4 (#623): only a brief that names exactly one cut adds it; a brief naming two or more adds nothing beyond the evidence markers.
  - Test: scripts/__tests__/merge-unit-local-cuts.test.sh -- a brief naming two cuts marks neither from the brief
- D5 (#624): sources `main` and `decision.sh push-ask` wake main: both are main's own questions (the push ask is written by main-watch's push_ask, with no pane of its own); AskUserQuestion and `<unit> asks` sources were answered in their own pane.
  - Test: scripts/__tests__/decision.test.sh -- answering a push ask sends main one message with the answer
- D6 (#617): under zsh, PATH is set in the sourcing shell from `bash -c` that loads requirements.sh alone (its req_path repair, no project resolution) and prints PATH; an empty print leaves PATH as it was. A child's own environment change would not reach the caller.
  - Test: scripts/__tests__/long-job.test.sh -- sourcing host-services.sh from zsh on a stubbed Darwin exports the repaired PATH
- D7 (#592): the warning past 40K already names the overage; the warning below it does not, so context-line.sh's second message gains `<n>K past`; tests use `COMMANDECK_CLEAR_LINE=180000`, leaving the 200K default alone.
  - Test: hooks/__tests__/context-clear-stop.test.sh -- main at 181K with a 180K line is warned 1K past the line

- D8 (owner's answers, 2026-11-03): close the thirteen fixed or non-plugin issues with the commit or reason in Triage (main closes them; this seat posts nothing); the #595 fixture passes a `fixture` reason by default and every check still runs; the user-visible wording is approved as written; each of the other open issues is a build step or one concrete question.
  - Test: none, an owner ruling with no code of its own; C9's cases test the fixture default
- D9 (#591): the sweep removes only a clean worktree, never with `--force`, and deletes its branch only with `git branch -d` when the tip is in main; an unmerged branch stays as the durable reference to its commits, and a detached HEAD not in main keeps its worktree; a dirty worktree or one in use is never touched.
  - Test: scripts/__tests__/worktree-sweep.test.sh -- a stale clean helper worktree whose branch is not in main is removed and its branch kept
- D9a (#591): clean means `git status --porcelain --untracked-files=all` prints nothing and `git ls-files -v` tags no file lowercase (assume-unchanged) or `S` (skip-worktree), the rule git-safety.sh wt_clean applies; status hides those files' edits and a plain `git worktree remove` deletes them, so a tagged file keeps the worktree whatever its content; a status or ls-files that exits non-zero keeps it too; each kept worktree is printed `kept <path>: <reason>` in sweep.log.
  - Test: scripts/__tests__/worktree-sweep.test.sh -- a stale helper worktree with an assume-unchanged edit is kept
- D9b (#591): the in-use check runs `lsof -a -d cwd -Fn` once per sweep; an lsof that exits non-zero or prints no `n` record keeps every candidate, printed `kept <path>: lsof failed (exit <n>) or named no working directory` in sweep.log, the rule main-watch.sh reap_brokers applies before it kills a broker.
  - Test: scripts/__tests__/worktree-sweep.test.sh -- a stale clean helper worktree is kept when lsof fails

- D10 (owner's answers, 2026-11-03, decision plan-commandeck-open-2026-11-03): all sixteen questions answered (a): close #506, #571, #600 and #613; build #587, #590, #611 and #620 here; #555, #576, #584, #585, #586, #608, #610 and #614 stay open for later units.
  - Test: none, an owner ruling; C13-C16 carry their own cases
- D11 (#590): only non-Builder seats are reported; a Builder ends through its own hand-off, and a pane closed by an operator is never a death. An exit row belongs to a seat only by exact pty id (Orca's sessionId), never by worktree path, so two seats in one worktree are told apart. Of a seat's exit rows since launch only the latest counts, and the operator-close test reads that row's cause, so an earlier `unknown` row never outvotes a later `operator_close`.
  - Test: scripts/__tests__/main-watch-dead-seat.test.sh -- two seats in one worktree: only the seat whose pty exited is reported; an unknown exit row followed by an operator_close row for one pty is not reported
- D12 (#631): main fixed it in 4530f6f: collect settles with `PP_VERDICT_READ=1`, which skips only the pane state, and an open question or an unreadable check still refuses. This unit adds no second mechanism; revise and close reuse the switch, and main closes #631 as fixed.
  - Test: scripts/__tests__/seat-settle.test.sh -- seat.sh revise on a finished seat with an open question is still refused and sends nothing
- D13 (#632): the driver reads every Orca repo's ledger, the issue's first fix, rather than have the answer tool write a second project's ledger: one reader change, no write outside the project.
  - Test: scripts/__tests__/unit-drive.test.sh -- an owner answer recorded in another Orca repo's ledger releases the question gate
- D14 (#630): close acts only on a seat whose record's last `verdict=`/`revised=` line is a verdict, the same test collect's rerun uses, so a revised seat at work is never closed.
  - Test: scripts/__tests__/seat-settle.test.sh -- seat.sh close on a seat with no recorded verdict closes nothing and names collect
- D15 (#632): another repo's answer counts only when its question or source carries `plan <hash8>`, the token the driver's ask already names, so a same-named unit's answer elsewhere, or one to an older plan, never releases the gate; this project's own ledger keeps today's id and after-ask filter.
  - Test: scripts/__tests__/unit-drive.test.sh -- another repo's answer that names no plan hash does not release the gate and says one line
- D16 (#598): the proof of a finish is the seat's latest answer read by collect's own reader (seat.sh:741-746: a `VERDICT:` banner, or the record's `marker=` line), not Orca's completed listing (the seat's own worker_done claim) and not a recorded `verdict=` line: collect closes the pane (seat.sh:834) before it writes `verdict=`, so a recorded verdict and a live pane to revise never meet. revise reads that finish when its pane is not read idle, skips its own pane-busy refusal (seat.sh:245-246) and settles through `PP_VERDICT_READ=1`; the open-question check still wins. pp_task_close is not changed and no task-list read is added. For a revised seat the finish must be the current task's: the reader takes the answer after the session's latest prompt, which until the revised prompt lands is the previous task's, so revise requires `read-verdict.sh --state --task <current task>` to print `session=` first (main-watch's revised_ran test, the C14 rule).
  - Test: scripts/__tests__/seat-settle.test.sh -- seat.sh revise on a seat whose latest answer ends on its marker sends the revision though its pane reads working; seat.sh revise on a revised seat whose revised prompt has not landed is refused though the old answer ends on PLAN-DONE; seat.sh revise on a revised seat whose revised prompt landed and whose answer ends on PLAN-DONE sends the revision
- D17 (#628): absence is `require.resolve('typescript')` failing (exit 3, the regex fallback); a package that resolves but throws while loading, or fails a parse, is a broken reader (exit 2).
  - Test: scripts/__tests__/new-test-count.test.sh -- a typescript that throws while loading exits 2 naming the failure
- D18 (#629): a forced remove passes only in the existing fixed-list form and only for a canonical absolute path strictly under the scratch root, so `..`, a symlink out, or the root itself stays blocked; elsewhere the clean-status rule is unchanged.
  - Test: hooks/__tests__/git-safety.test.sh -- a forced remove whose path climbs out of the scratch root with .. is blocked
- D19 (#595): the override's alert is a dashboard alert, as the host's merged gate does; the relay note is dropped, since pp_relay_event sends nothing without a recorded run.
  - Test: scripts/__tests__/dashboard-alerts.test.sh -- a hand launch in the last 24 h raises one warn alert naming the unit and unit-drive.sh start
- D20 (#590): the exit log default is `$HOME/Library/Application Support/orca/logs/daemon.log` on Darwin and `$HOME/.config/orca/logs/daemon.log` elsewhere, `COMMANDECK_ORCA_LOG` first; both read on 2026-11-03 (Assumptions); the shape read is one JSON object per line with `event`, `sessionId`, `cause` and `ts`, and a line that is not JSON is skipped.
  - Test: scripts/__tests__/main-watch-dead-seat.test.sh -- with COMMANDECK_ORCA_LOG unset the log under the host's default Orca folder is read
- D21 (#590): a dead seat is one whose current episode has no finish: no collected verdict since its last revise, no `finished` state main-watch settled for its current task (a `silent` one is no finish), and no `VERDICT:` or `-DONE` line in its session log's latest answer, read by the seat-bound positional reader, which counts for a revised seat only once revised_ran proves the revised prompt landed. A raw `verdict=` line anywhere in the record is not the test, since revise keeps the old one (seat.sh:257), and a turn that merely ended (`--state` `state=complete`) is not a finish.
  - Test: scripts/__tests__/main-watch-dead-seat.test.sh -- a seat revised after its verdict whose pane then exits is reported; a seat revised before its new prompt landed whose session still ends in the old PLAN-DONE is reported when its pane exits
- D22 (owner's answer, 2026-11-03, decision plan-commandeck-open-2026-11-03, Q1 (a)): #633 stays open for its own unit, which starts by finding the launch path past duplicate-agent-guard.sh; this unit adds no cut, step or test for it and does not close it.
  - Test: none, an owner ruling with no code in this unit
- D23 (#588 part): Orca 1.4.246's concise `check` row carries `id`, `type`, `from`, `subject` and `payload`; `body`, `thread_id`, `from_handle` and the result's `dispatchId` come only with `--full`, so every check reader using one passes `--full`; a reader using only `type` keeps the concise view.
  - Test: scripts/__tests__/ask-main.test.sh -- ask-main prints an answer only Orca's full check view carries
- D24 (#634): the version check runs in the pre-push hook, the issue's named alternative, not in fast-lane.sh land: it covers every push to main, the Fast lane's included, and ci/version-check.sh is this repository's, absent from the shipped plugin folders a user's Fast lane runs in.
  - Test: scripts/__tests__/ci-pre-push.test.sh -- a push to main of a plugin change with no version bump is refused naming version-check
- D25 (#635): merge-queue.sh's first-argument `--help` already prints usage and exits 0 (c4ece92) and the queue writes no push ask (no push-ask call in merge-queue.sh); what is left is a later dash argument passing the unit pattern, so the pattern must start with a letter or digit.
  - Test: scripts/__tests__/merge-queue.test.sh -- a unit argument that starts with a dash is refused and nothing merges
- D26 (owner's answer, 2026-11-03, decision plan-commandeck-open-2026-11-03, Q1 (a)): C13 moves both launch and revise to `--spec-file`; seat-revise.test.sh's task-create stand-in also logs the text of the file `--spec-file` names, and its issue-485 check is unchanged, so it still proves Orca receives the revision text (a test edit that follows the intended change).
  - Test: scripts/__tests__/seat-revise.test.sh -- a revision gets a new task (issue 485)
- D27 (owner's answer, 2026-11-03, decision plan-commandeck-open-2026-11-03, Q2 (a)): #636 stays open for its own unit, which first splits the paths.sh:675 refusal line in two and watches live runs; this unit adds no cut, step or test for it, does not close it, and collect's pane check stays off.
  - Test: none, an owner ruling with no code in this unit
- D28 (#595, plan-judge-sol round 7 F1): the fixture's `fixture` reason (D8) is exported once at the top of seat-setup.sh, not passed by seat_sh, because seat-run-refused.test.sh:50-51 and seat-run.test.sh:63-65 call `bash "$REAL/scripts/seat.sh" run plan-judge-sol` directly to prove detachment, and routing them through seat_sh would change what they prove; the driver is read first, so srun launches (COMMANDECK_DRIVER=1 plus the export) log nothing; the refusal and driver-only cases run `(unset COMMANDECK_HAND_LAUNCH; ...)`.
  - Test: scripts/__tests__/seat-plan-judges.test.sh -- a driver launch with the fixture's override set logs no hand-launch row and prints no HAND LAUNCH

## Accepted failure modes

- A1 (#593): `cd x && WT=/p; git -C "$WT" log` stops resolving `$WT` and gets whatever the guard does today for any `$` it cannot resolve (block or warning, unchanged by this unit): erring in the safe direction, as the guard's existing conditional-cd limit does.
  - Test: hooks/__tests__/bash-guardrails.test.sh -- a plain assignment before a search still resolves
- A2 (#607): with no unit worktree the label is recorded with a warning, as today; the review pass still checks it.
  - Test: scripts/__tests__/decision.test.sh -- a test-edit for a unit with no worktree records with a warning
- A3 (C1): a report ending `VERDICT: GO. reason` reads GO to collect, but the merge's round count (`grep -cx` on the raw last line) reads that round as unknown and blanks both counts, never a wrong count.
  - Test: none, the merge count's unknown path is existing behaviour and unchanged
- A5 (#590): a seat record with no pty value (launched before this unit, or the terminal list unread at launch, which says one line) is never reported dead; the next launch of that seat records it.
  - Test: scripts/__tests__/main-watch-dead-seat.test.sh -- a seat record with no pty value is not reported
- A6 (#632): an answer another repo's main recorded without the `plan <hash8>` token is not taken; the gate says one line naming the repo, and main re-records it with the token.
  - Test: scripts/__tests__/unit-drive.test.sh -- another repo's answer that names no plan hash does not release the gate and says one line
- A7 (#598): main's revise of a seat whose pane reads working and whose latest answer holds no finish is still refused; revise after collect is refused as not live, since collect ends the seat by closing its pane (seat.sh:834), and a further round is a new launch (`seat.sh run`, as the driver does, unit-drive.sh:183).
  - Test: scripts/__tests__/seat-settle.test.sh -- seat.sh revise on a seat whose pane reads working with no finish in its latest answer is still refused

## Assumptions

- The PC is the Linux test peer (`~/.config/devenv/peer`, scripts/peer-offload.sh:5), not where Orca runs seats: settled 2026-11-03 over ssh: `uname -s` Linux; its Orca lists 0 terminals and 0 repos (`orca-ide terminal list --json`, `orca-ide repo list --json` in a login shell); every test stubs orca-ide through its fixture, so the Orca contracts below are the Mac's and no Builder check on the PC is needed
- Orca 1.4.246's concise and `--brief` task-list rows hold only `id`, `status` and `title`; `--full` adds `spec`, `task_title`, `display_name` and `result`: settled on the Mac 2026-11-03 (`orca-ide orchestration task-list --run <run> [--brief|--full] --json`, first task's keys; `task-list --help` says the same)
- The plan seats' records are `seat-<unit>-<role>.txt` under `$PP_SCRATCH`, and a revise keeps role plan-author: settled by the fixture's `settle` reader and seat.sh revise
- Every seat test that launches a plan seat inherits the fixture-wide `COMMANDECK_HAND_LAUNCH` export: settled 2026-11-03, 14 files source seat-setup.sh (`grep -ln seat-setup.sh scripts/__tests__/*.sh`); `grep -rn 'bash "$REAL/scripts/seat.sh"' scripts/__tests__` outside the fixture finds only seat-run-refused.test.sh:51 and seat-run.test.sh:65, both run with the export inherited (their `env -u` lists omit it); resume-context and builder-launch-resume only write records; unit-drive.test.sh stubs seat.sh
- Builder check before C6: run hooks/__tests__/bash-guardrails.test.sh on the PC after the change; if an existing case relied on a `&&` assignment resolving, stop and ask main (never edit it)
- Builder check in C6: the #593 cases assert the guard's current outcome for an unresolved `$` (read it from an existing unresolved-variable case first), never a new block
- C9's fixture edit is approved by the owner (2026-11-03)
- Orca's daemon log is one JSON object per line; a `session-exited` row reads `{"src":"daemon","ts":"<ISO>","pid":<n>,"event":"session-exited","sessionId":"<id>::<worktree path>@@<hash>","code":<n>,"cause":"<word>"}`: settled 2026-11-03: the Mac's `$HOME/Library/Application Support/orca/logs/daemon.log` holds 2,072 such rows (causes `operator_close` and `unknown`); the PC's `$HOME/.config/orca/logs/daemon.log` (with `daemon.log.1`) holds 2,070 (10 `exited`, 2,060 `signaled`, no `operator_close`); `~/.config/orca/logs` does not exist on the Mac; these two paths are D20's defaults
- `orca-ide terminal list --json` gives each terminal's `ptyId` in the same `<id>::<worktree path>@@<hash>` form as a `session-exited` row's sessionId: settled on the Mac 2026-11-03 (`jq '.result.terminals[0].ptyId'` prints that form); of 2,057 exit rows, 8 sessionIds repeat, hence the at-or-after-launch bound
- `orca-ide orchestration task-create` takes `--spec-file <path|->`: settled, its `--help` (2026-11-03); orca-task-create.sh passes its arguments through
- `orca-ide repo list --json` lists each repo's path under `.result.repos[].path`: settled on the Mac 2026-11-03: four repos (this one and three of the owner's other projects)
- #632's answer sat in another repo's ledger: settled, `grep plan-commandeck-open-2026-11-03` on both ledgers, 2026-11-03: the host project's ledger answered at 22:44:08Z, this project's only by a hand copy at 23:09:38Z
- `lsof` is on both hosts: settled 2026-11-03: `/usr/sbin/lsof` on the Mac, `/usr/bin/lsof` on the PC (`command -v lsof` over ssh)
- The seat-bound positional reader reads a gone pane's session log (C14): settled 2026-11-03: `bash scripts/read-verdict.sh term_1233ed85-e1f5-442f-81d9-a189b9d9dd8d 5 <this worktree> codex "" "" "" 1793754800`, that handle absent from `orca-ide terminal list --json` (0 matches), printed `VERDICT: NO-GO` and the findings banner
- Orca 1.4.246's concise `check` rows lack `body`, `thread_id` and `from_handle`, and its result lacks `dispatchId`: settled from scripts/__tests__/fixtures/orca-1.4.246-views.json (captured 2026-11-03, values untouched) and `orca-ide orchestration check --all [--full] --json` here on 2026-11-03 (result keys `messages` against `acknowledged, count, dispatchId, messages, runId`); whether `--wait` returns a `deliveryId` is the C8 Builder check
- #629's scratch root: git-safety.sh does not load paths.sh, so it reads `${COMMANDECK_SCRATCH:-$HOME/.commandeck/scratch}`, the default paths.sh builds PP_SCRATCH under: settled, paths.sh:64 (2026-11-03)

## User-visible changes

- #626/#597: before, a judge ending `VERDICT: NO-GO. reason` read as no verdict and the driver stopped / after, it reads NO-GO; other trailing text, and a choice list like `VERDICT: GO, NO-GO`, gets a message naming the bare form
- #595: before, a plan seat launched by hand ran outside the driver / after, it is refused naming `unit-drive.sh start` unless `COMMANDECK_HAND_LAUNCH=<reason>` is set; an override prints `HAND LAUNCH: <role> <unit>: <reason>` and the dashboard shows a warn alert for 24 h
- #603: before, main could not open an approved probe pane / after, the block message names the `COMMANDECK_PROBE_PANE=<approval id>` prefix, one pane per id
- #593: before, a variable set after `&&` was treated as set / after, it is treated as unknown in path checks, with the guard's existing handling of an unknown variable
- #628: before, a broken TypeScript reader fell back to a text count with no word / after, the count stops naming the reader's failure; a project with no typescript still gets the text count, now with a one-line notice
- #607: before, a near-miss test name was recorded and failed at the next pass / after, the record command refuses and prints the exact names
- #598, #630, #632: main revises a finished seat whose pane still reads working with no refusal (a seat with no finish in its latest answer, or a revised seat whose revised prompt has not landed, is still refused); main closes a finished seat with one `seat.sh close` command; an answer given in the host project's main session releases the driver
- Docs: README.md says a hand plan-seat launch needs `COMMANDECK_HAND_LAUNCH=<reason>`; docs/commands.md gains `seat close` and the new revise rule; docs/hooks.md names the probe-pane prefix and the scratch-root forced remove
- #616, #624, #589, #617, #612: a new push ask is no longer a false repeat; main is told of an answer to its own or a push question; a failed cleanup names the worktree and reason; no zsh error line, and the zsh shell's PATH is repaired; no false finished alert
- #592: before, main between the line and 40K past it was told only that it was over / after, every warning names how far past the line it is
- #591 (C10): before, idle helper and scratch worktrees piled up / after, once an hour main-watch removes each clean one no process uses and untouched for 24 h, writing one line per removal to `$PP_SCRATCH/main-watch/sweep.log`; a branch not in main is kept and named there, never deleted
- #629: before, an agent could never remove a scratch worktree holding edits / after, a forced `git worktree remove` of a path under the scratch root passes; elsewhere it is blocked as before
- #615 (C11): before, an unreadable context size on main stopped the restart silently / after, one line says why on stderr and in clear-hook.log
- #621 (C12): before, a built unit being re-planned showed waiting on main / after, it shows planning until the plan seat's verdict
- #587 (C13): before, a long task text could be cut short in Orca / after, Orca's task holds it whole; the typed pointer is unchanged
- #590 (C14): before, a seat whose pane died before its verdict went unnoticed / after, main-watch posts one item naming the seat and its unit within a tick; an operator close is never reported
- #611 (C15): before, main loaded three procedure lines at every start / after, each is under Details, one pointer away
- #620 (C16): before, an auto-merge ignored a pre-merge step / after, a brief naming a pre-merge step holds the merge until the evidence has the `Pre-merge: done <n>` line the hold names
- #588 (C8, check reads): before, ask-main.sh could miss main's answer and the inbox drain showed messages with no body / after, both read Orca's full view
- #634 (C17): before, a plugin change with no version bump reached main and only CI caught it / after, the push to main is refused with version-check's message
- #635 (C17): before, `merge-queue.sh u1 --help` ran a merge of a unit named `--help` / after, it is refused with the usage line

- A8 (C1): a verdict line whose reason names another verdict word (`VERDICT: NO-GO. GO only after C2`) reads no verdict, as on the host since #3681; collect names the bare form and the seat rewrites its line: a false GO from a template costs more than one more turn.
  - Test: scripts/__tests__/read-verdict.test.sh -- a spaced choice list VERDICT: GO, NO-GO is no verdict in the pane or the session log
- A9 (#598): a revised seat whose session log cannot be read (no log, or `--state` fails) is refused by revise while its pane reads working, as today; main waits for it to read idle.
  - Test: scripts/__tests__/seat-settle.test.sh -- seat.sh revise on a revised seat whose revised prompt has not landed is refused though the old answer ends on PLAN-DONE

## Question for the owner

None: answered as D26 (Q1) and D27 (Q2)

## Stated limits

(every reviewer is handed these; a finding beyond one is out of scope: a follow-up issue, never a blocker)
- L1 (#617): the zsh PATH-repair case runs on the PC with a `uname` stub printing Darwin and a fake Homebrew through COMMANDECK_BREW_PREFIX, never a real Mac's layout (`grep -n COMMANDECK_BREW_PREFIX scripts/requirements.sh`: line 28, 2026-11-03)
- L2 (#627): after the swap the check has the gap before the next cycle, at least 1 s (`COMMANDECK_DASHBOARD_CYCLE_S=1`, dashboard-loop.test.sh:91), polled every 0.1 s (dashboard-loop.test.sh:21), read 2026-11-03
- L3 (#588): the loud failure on concise output stays open under #588; this unit only adds `--full`
- L4 (#621): between a collected revise and the next judge launch no seat is unfinished, so the view can still read waiting on main for that gap; it stays open under #621 (an active revise is covered: C12 reads the last verdict=/revised= line)
- L5 (#590): the operator-close exclusion trusts Orca's `cause` word; the PC's Orca writes no `operator_close` (2,070 rows: 10 `exited`, 2,060 `signaled`; `grep session-exited ~/.config/orca/logs/daemon.log | jq -r .cause | sort | uniq -c` over ssh, 2026-11-03), so on a host like it an operator-closed seat with no finish would get one item; the PC runs no seats (0 terminals, 0 repos, same day)
- L6 (#617): the PC has no zsh (`command -v zsh` empty, login shell too, over ssh 2026-11-03), so the three long-job.test.sh zsh cases print `skip: no zsh` there; #617 is recorded built only if a run where zsh exists passes them, else `#617: partial -- zsh cases not run`

## What can go wrong

| Case | Input or starting state | Expected | Test |
|---|---|---|---|
| empty or absent worktree | test-edit for a unit with no worktree | recorded with a warning | scripts/__tests__/decision.test.sh -- a test-edit for a unit with no worktree records with a warning |
| absent or missing seen file | a watcher's seen file deleted between polls | next poll delivers the new item and recreates the file | scripts/__tests__/cos-tell.test.sh -- the alerts watcher still tells a new alert after its seen file is deleted |
| junk or trailing argument | `merge-queue.sh u1 --help` | refused exit 2 with usage, nothing merged | scripts/__tests__/merge-queue.test.sh -- a unit argument that starts with a dash is refused and nothing merges |
| quoted or echoed approval id | `echo "COMMANDECK_PROBE_PANE=<id>"` then a hand pane | blocked | hooks/__tests__/duplicate-agent-guard.test.sh -- an approval id only inside an echo is blocked |
| Pre-merge step under a subheading (pass 1) | `## Pre-merge`, `### Staging`, `- run migration`, no evidence line | held, the hold naming the done line | scripts/__tests__/main-watch-merge-gate.test.sh -- a brief with a Pre-merge section holds the merge until the evidence says Pre-merge: done |
| Pre-merge done line older than its steps (pass 1) | the done line written, then a step added | held again | scripts/__tests__/main-watch-merge-gate.test.sh -- a brief with a Pre-merge section holds the merge until the evidence says Pre-merge: done |
| Pre-merge heading indented (pass 2) | `  ## Pre-merge` then `- run migration`, no evidence line | held, the hold printing the done line | scripts/__tests__/main-watch-merge-gate.test.sh -- a brief with a Pre-merge section holds the merge until the evidence says Pre-merge: done |
| Pre-merge heading in another Markdown shape (class redesign) | a closed `## Pre-merge ##`, a setext `Pre-merge` over `---`, `**Pre-merge**`, a fenced `## Pre-merge` | held, the hold printing the done line | scripts/__tests__/main-watch-merge-gate.test.sh -- a brief with a Pre-merge section holds the merge until the evidence says Pre-merge: done |
| Pre-merge step in bold only (pass 3) | `## Pre-merge` then `**Run the staging migration before merging.**`, no evidence line | held, the hold printing the done line | scripts/__tests__/main-watch-merge-gate.test.sh -- a brief with a Pre-merge section holds the merge until the evidence says Pre-merge: done |
| kept gate state removed between two ticks (class redesign) | a held unit's `gate-<unit>`, `merge-<unit>` and posted item removed between ticks | still held at the next tick; merged at the first tick after the done line | scripts/__tests__/main-watch-merge-gate.test.sh -- a brief with a Pre-merge section holds the merge until the evidence says Pre-merge: done |
| Pre-merge heading the reader does not know (pass 1) | `## Pre-merge steps` with a step under it | held, the hold printing the done line | scripts/__tests__/main-watch-merge-gate.test.sh -- a brief with a Pre-merge section holds the merge until the evidence says Pre-merge: done |
| brief edited after the done line (class redesign, pass 3) | `Pre-merge: done <n>` written, then any line of the brief changed (a step reworded in bold) | held again, the hold printing the new line | scripts/__tests__/main-watch-merge-gate.test.sh -- a brief with a Pre-merge section holds the merge until the evidence says Pre-merge: done |
| bold or heading line added inside Stated limits (pass 3) | `**No writes to prod.**` or a new `### Hosts` line added under Stated limits, no id | refused | scripts/__tests__/builder-codex-pass-limits.test.sh -- a limit added under a subheading of Stated limits with no id is refused |
| limits heading in an unread shape (pass 4) | `<h2>Stated limits</h2>` then `- Skip production verification.` in the worktree brief or plan; also a setext, bold, indented or `>`-quoted `Stated limits` | refused, naming the file and the line of the heading | scripts/__tests__/builder-codex-pass-limits.test.sh -- a limit added under a subheading of Stated limits with no id is refused |
| limits heading name with inline markup (pass 5) | `## Stated **limits**` then `- Skip production verification.`, or the accepted-failures heading with `**` inside, in the worktree brief or plan | refused, naming the file and the line | scripts/__tests__/builder-codex-pass-limits.test.sh -- a limit added under a subheading of Stated limits with no id is refused |
| limit under a subheading of Stated limits (fix round 1) | `### Hosts` then a new limit line, no id | refused | scripts/__tests__/builder-codex-pass-limits.test.sh -- a limit added under a subheading of Stated limits with no id is refused |
| limit approval with a void or absent id (pass 1) | `Limit: <line> ruling:<void id>` in main's rulings | refused | scripts/__tests__/builder-codex-pass-limits.test.sh -- a limit whose rulings id is void or absent is refused |
| pane close refused (pass 7) | `seat.sh close plan-author u` with a recorded verdict and a live pane, or `seat.sh collect` (first run or 604's rerun), while Orca answers the close `ok:false` | exit 5, no `closed seat=` line, Orca's answer and `seat.sh close` on stderr; collect still records the verdict and runs no on-go/on-nogo | scripts/__tests__/seat-settle.test.sh -- a pane close Orca refuses is no closed seat: seat.sh close, collect and its rerun exit 5 naming seat.sh close, collect records the verdict and runs no on-go, and the rerun closes once Orca takes it |
| revised worker commits before dispatch returns (pass 8) | `seat.sh revise plan-author u` while the worker-start call commits a new plan before it answers | planref= is the plan from before the revision was sent; the worker's commit reads as its finish | scripts/__tests__/seat-revise.test.sh -- a revise seat that commits its plan before dispatch returns keeps the plan it inherited as planref and reads as finished |
| odd data: unmerged work in a stale worktree | a clean helper worktree over 24 h old, no process, its branch one commit ahead of main | worktree removed, branch kept and named | scripts/__tests__/worktree-sweep.test.sh -- a stale clean helper worktree whose branch is not in main is removed and its branch kept |

## Acceptance test

- test file path: scripts/__tests__/read-verdict.test.sh (a NO-GO verdict with a reason after a full stop reads as NO-GO; a GO verdict with a reason after a dash reads as GO; a spec line VERDICT: GO or NO-GO is still no verdict; a spec line VERDICT: GO means is still no verdict; an unspaced choice list VERDICT: GO,NO-GO is no verdict in the pane or the session log; a spaced choice list VERDICT: GO, NO-GO is no verdict in the pane or the session log)
- test file path: scripts/__tests__/seat-collect-once.test.sh (collect records NO-GO from a judge whose verdict line has a reason after it; a verdict line with other trailing text is refused naming the bare form; a judge pane left open after its verdict is closed by a rerun of collect; a judge pane with no verdict yet is not closed)
- test file path: scripts/__tests__/seat-plan-judges.test.sh (a plan judge's prompt says the verdict line stands alone; a hand launch of a plan seat is refused naming unit-drive.sh; a hand launch with the override opens, logs one row and prints HAND LAUNCH; a driver launch of a plan seat passes with no override; a driver launch with the fixture's override set logs no hand-launch row and prints no HAND LAUNCH)
- test file path: scripts/__tests__/seat-run-refused.test.sh (in main's own foreground run returns at once, and its log ends on the one line)
- test file path: scripts/__tests__/seat-run.test.sh (a detached run started from a shell that is then killed (with its process group) still finishes and collects)
- test file path: scripts/__tests__/seat-settle.test.sh (seat.sh revise on a seat whose latest answer ends on its marker sends the revision though its pane reads working; seat.sh revise on a seat whose pane reads working with no finish in its latest answer is still refused; seat.sh revise on a finished seat with an open question is still refused and sends nothing; seat.sh close settles a collected seat's open task and closes its live pane; seat.sh close on a seat with no recorded verdict closes nothing and names collect; seat.sh revise on a revised seat whose revised prompt has not landed is refused though the old answer ends on PLAN-DONE; seat.sh revise on a revised seat whose revised prompt landed and whose answer ends on PLAN-DONE sends the revision)
- test file path: scripts/__tests__/seat-revise.test.sh (a revise seat does not read as finished from the plan it inherited; a revise seat that commits a new plan reads as finished; a revision gets a new task (issue 485))
- test file path: scripts/__tests__/test-edit-labels.test.sh (a single-quoted label with an escaped apostrophe reads with a plain apostrophe; a double-quoted label with an escaped quote reads with a plain quote)
- test file path: scripts/__tests__/new-test-count.test.sh (a test name with an escaped apostrophe is counted under the runner's name; a test name with an escaped apostrophe reads the same with and without typescript; a project with typescript is read by the parser, not the label regex; a reader that fails with typescript loaded exits 2 naming the failure; a typescript that throws while loading exits 2 naming the failure)
- test file path: scripts/__tests__/decision.test.sh (a near-miss test-edit label is refused and the exact names are printed; the exact test-edit label is recorded; a test-edit for a unit with no worktree records with a warning; two push asks at different tips with the same commit count are both written; the same tip asked twice is refused as a repeat; answering a decision main opened sends main one message with the answer; answering a push ask sends main one message with the answer; an answer to an AskUserQuestion decision sends main nothing)
- test file path: scripts/__tests__/unit-drive.test.sh (a judge finding written as `**F1 (P1):**` reaches the revise brief; an owner answer recorded in another Orca repo's ledger releases the question gate; an answer in another repo's ledger from before the ask does not release the gate; another repo's answer that names no plan hash does not release the gate and says one line; an unreadable Orca repo list keeps the gate on this project's ledger with one line said)
- test file path: scripts/__tests__/builder-fresh-round.test.sh (a fix brief whose round has a later pass report types nothing; a fix brief with no later report is still typed)
- test file path: scripts/__tests__/builder-codex-pass-limits.test.sh (a limit with no inline id passes when main's rulings file carries it with a real id; a limit whose rulings id is void or absent is refused)
- test file path: scripts/__tests__/merge-unit-local-cuts.test.sh (a cut the brief alone names counts built on a closing GO; a brief naming two cuts marks neither from the brief)
- test file path: scripts/__tests__/merge-unit-local-cleanup.test.sh (a removal Orca refuses fails the cleanup naming the worktree and the reason; a removal that answers ok but leaves the folder fails naming the worktree; a successful removal prints no failure)
- test file path: scripts/__tests__/merge-queue.test.sh (the real checkout's git folder is unchanged by the run; a unit argument that starts with a dash is refused and nothing merges)
- test file path: scripts/__tests__/ci-pre-push.test.sh (a push to main of a plugin change with no version bump is refused naming version-check; a push to main of a plugin change with a version bump passes)
- test file path: scripts/__tests__/ask-main.test.sh (ask-main prints an answer only Orca's full check view carries)
- test file path: scripts/__tests__/to-main.test.sh (inbox-drain shows a message's body and sender from Orca's full check view)
- test file path: hooks/__tests__/bash-guardrails.test.sh (a search path from an assignment after && is judged unresolved; a wait note from an assignment after && is judged unresolved; a conditional reassignment after && drops the earlier value; a plain assignment before a search still resolves)
- test file path: hooks/__tests__/duplicate-agent-guard.test.sh (main opens a probe pane with a valid approval id and the use is logged; main with no approval prefix is still blocked; a void approval id is blocked; a reused approval id is blocked; an approval id only inside an echo is blocked)
- test file path: hooks/__tests__/context-clear-stop.test.sh (main at 181K with a 180K line is warned 1K past the line; main at 466K is warned 286K past the line; main at 180K is not warned; an unreadable context size on main says why in one line)
- test file path: scripts/__tests__/cos-tell.test.sh (the alerts watcher still tells a new alert after its seen file is deleted; the decisions watcher still fires a new decision after its seen file is deleted)
- test file path: scripts/__tests__/long-job.test.sh (sourcing host-services.sh from zsh in another folder prints nothing on stderr; sourcing host-services.sh from zsh sets HS_DIR to the scripts folder; sourcing host-services.sh from zsh on a stubbed Darwin exports the repaired PATH)
- test file path: scripts/__tests__/answer-worker.test.sh (an answer by unit name reaches a plan-revise seat's pane when no Builder runs; an answer by handle reaches a plan-revise seat's pane; a plan judge's pane is never picked by unit name)
- test file path: scripts/__tests__/dashboard-loop.test.sh (a killed cycle leaves no temporary files and no data.js)
- test file path: scripts/__tests__/worktree-sweep.test.sh (an idle clean helper worktree older than 24 hours is removed and reported; a stale clean helper worktree whose branch is not in main is removed and its branch kept; a stale helper worktree detached at a commit not in main is kept; a helper worktree a live process uses is kept; a stale clean helper worktree is kept when lsof fails; a helper worktree with uncommitted files is kept; a stale helper worktree with an assume-unchanged edit is kept; a stale helper worktree with a skip-worktree edit is kept; a stale helper worktree whose index cannot be read is kept; a helper worktree touched under 24 hours ago is kept; a stale scratch worktree under the scratch folder is removed)
- test file path: hooks/__tests__/git-safety.test.sh (a forced remove of a dirty worktree under the scratch root passes; a forced remove of a dirty worktree outside the scratch root is blocked; a forced remove whose path climbs out of the scratch root with .. is blocked)
- test file path: scripts/__tests__/dashboard-alerts.test.sh (a hand launch in the last 24 h raises one warn alert naming the unit and unit-drive.sh start; a hand launch older than 24 h raises no alert)
- test file path: scripts/__tests__/dashboard-built-planning.test.sh (a built unit whose plan judge launched after its Builder and has no verdict shows planning; a built unit whose plan seat was revised after an old verdict shows planning; a built unit whose later plan seat has its verdict still shows waiting on main)
- test file path: scripts/__tests__/seat-launch.test.sh (a task text over 200 characters reaches Orca whole through --spec-file; a launch records the pane's pty id in the seat record)
- test file path: scripts/__tests__/main-watch-dead-seat.test.sh (a seat whose pane exited with no verdict is reported once naming the seat and unit; a seat that exited after its verdict is not reported; an operator-closed seat pane is not reported; two seats in one worktree: only the seat whose pty exited is reported; a seat record with no pty value is not reported; a seat revised after its verdict whose pane then exits is reported; a seat whose session log holds its verdict but was not collected is not reported when its pane exits; a seat whose last turn ended with no verdict and whose state reads silent is reported when its pane exits; with COMMANDECK_ORCA_LOG unset the log under the host's default Orca folder is read; an unknown exit row followed by an operator_close row for one pty is not reported; a seat revised before its new prompt landed whose session still ends in the old PLAN-DONE is reported when its pane exits; a dead seat whose own task is failed in the task list still gets one item)
- test file path: scripts/__tests__/startup-size.test.sh (the plugin's main-session injected part is under 5,600 bytes; each moved main-session line appears word for word under Details)
- test file path: scripts/__tests__/main-watch-merge-gate.test.sh (a brief with a Pre-merge section holds the merge until the evidence says Pre-merge: done; a brief that names no pre-merge step does not hold)
- test file path: scripts/__tests__/orca-full-flag.test.sh (an inbox read that uses a full-only field passes --full; a task-list read that uses spec or display_name passes --full; the wake's and the awareness hook's task-list reads pass --full; a check read that uses body, thread_id or from_handle passes --full; a worker brief that names check's dispatchId names --full)
- Bug each catches: the case name says it; each new case fails on today's code for the issue it names
- Typescript stub: the #628 and #596 cases put a stub `typescript` module in the fixture repo's node_modules: one whose tree walk finds no test (a count of 0 where the regex gives 1), one whose createSourceFile throws, one whose index.js throws at load, and one that returns the literal's text for the parity case; no real typescript is needed
- Zsh Darwin stub: the PATH case puts a `uname` printing Darwin first on PATH and a fake Homebrew gnubin under COMMANDECK_BREW_PREFIX, then reads PATH in the zsh shell after sourcing
- Choice-list cases: each checks both readers in one check, as the host's test does: read-verdict.sh's exit 3 on the pane text and the session-log regex's `false` on the same line
- Revised-seat log: the two revised-seat revise cases run the real read-verdict.sh over a Claude session log the case writes under the fixture's projects folder (as read-verdict.test.sh:40-43 does): its last user row holds task_1's prompt (not landed) or task_2's id (landed), its last answer ends PLAN-DONE, the pane reads working (ps-working); the not-landed case expects exit 2, nothing sent and no task closed
- Zsh: the three long-job.test.sh zsh cases print `skip: no zsh` and count no pass when zsh is absent on the PC

## Claims to falsify

- read-verdict.sh today accepts nothing after the verdict word but spaces, stars and a quote -- scripts/read-verdict.sh:496
- seat.sh revise leaves `planref=` as written at the first launch
- read-verdict.sh's pane scan and both session-log regexes have no second-verdict-word exclusion, so a reason rule alone would read `VERDICT: GO,NO-GO` as GO -- scripts/read-verdict.sh:529
- seat.sh revise has no test that the latest answer belongs to the current task; it only reads the pane busy -- scripts/seat.sh:243-248
- main-watch's post writes `handled` and sends nothing for a task argument whose status is failed or completed -- scripts/main-watch.sh:238-240
- decision.sh dup refuses a second push ask for a new tip when the question reads alike
- unit-drive.sh copies only `[P<n>]` findings and owner questions into the revise brief
- builder-codex-pass.sh limits_refuse reads only an inline `ruling:` id
- merge-unit-local.sh cleanup prints no worktree name or reason on a failed removal
- load_segments records an alias from an assignment after `&&`
- cos-watch-alerts.sh fails on a missing seen file instead of reading it as empty
- dashboard.sh logs a killed cycle before it removes the cycle's temp files
- answer-worker.sh queues an answer by unit name when only a plan seat runs
- only seat-run-refused.test.sh and seat-run.test.sh launch a plan seat with seat.sh outside the fixture's seat_sh
- seat.sh has no close command -- scripts/seat.sh:62
- seat.sh revise refuses a finished seat whose pane reads working, before it reaches pp_task_close -- scripts/seat.sh:245-248
- the awareness hook's `--brief` task list carries no spec, so its task lines show no text -- hooks/agent-awareness.sh:72
- a revised seat's record still holds its old `verdict=` line, so "any verdict= line" reads it as finished -- scripts/seat.sh:257
- unit-drive's question gate reads only this project's decisions ledger -- scripts/unit-drive.sh:236-241
- deliver_answer sends nothing for source `decision.sh push-ask` -- scripts/decision.sh:66
- the reader exits 2 for every typescript load failure, absent or broken -- scripts/new-test-count.sh:51-56
- js_regex returns a label with its escapes as written -- scripts/new-test-count.sh:151-155
- the below-40K warning names no overage -- hooks/context-line.sh:76
- host-services.sh's PATH repair runs only in a bash that sources it -- scripts/host-services.sh:16
- git-safety blocks a forced remove of a dirty worktree under the scratch root -- hooks/git-safety.sh:330
- seat.sh revise keeps an earlier `verdict=` line in the record -- scripts/seat.sh:257
- terminal list's ptyId and an exit row's sessionId share one form
- a concise `orchestration check` row carries no body, thread_id or from_handle -- scripts/__tests__/fixtures/orca-1.4.246-views.json
- ask-main.sh reads the answer by `thread_id` from a check read with no `--full` -- scripts/ask-main.sh:76-84
- collect closes the seat's pane before it writes `verdict=`, so revise after collect finds no live pane -- scripts/seat.sh:834-835
- the pre-push hook runs the shell tests and no version check -- .githooks/pre-push:29
- merge-queue.sh's unit pattern accepts an argument that starts with a dash -- scripts/merge-queue.sh:22
- `git status --porcelain` prints nothing for an edited assume-unchanged or skip-worktree file, and a plain `git worktree remove` then deletes the edit -- git 2.55.0, scratch repo, 2026-11-03: status empty, ls-files -v `h`/`S`, remove exit 0, folder gone

## Progress notes

- One line per issue, written by the Builder as each cut lands: `#N: built` or `#N: partial -- <what is left>`
- Expected partial: #588 -- the loud failure on concise output; #591 -- removal at diff apply (a brief rule the model follows); #615 -- the missed restart's cause; #621 -- the gap between a collected revise and the next judge launch
- Merge commit: `Closes #N` for each issue built, `Refs #N` for each partial

## Done

- #589 Done: a merge whose worktree Orca will not remove -- the cleanup line names the worktree and Orca's reason
- #592 Done: main keeps working past its restart line -- every turn shows the size and how far past the line it is
- #593 Done: an agent sets a variable after a failing `&&` and searches it -- the guard judges the variable as unknown
- #594 Done: a developer runs merge-queue.test.sh -- the run fails if the real git folder changed
- #595 Done: main launches a plan judge by hand -- the launch is refused naming the driver command, unless an override is given, which is logged and shows a dashboard alert
- #596 Done: main approves an edit to a test named with an apostrophe -- the approval matches the runner's name
- #597 Done: a plan judge ends with a verdict and a reason -- the verdict is collected or the message names the bare form
- #598 Done: a seat finishes with its pane still reading working and main revises it -- the revision goes in with no refusal, and a question the seat left open still stops it
- #601 Done: main records a limit's ruling in its rulings file -- the review pass accepts the limit and the plan carries no id
- #602 Done: main answers a plan seat's question by unit name -- the answer reaches the plan seat's pane
- #603 Done: main opens an owner-approved probe pane with its approval id -- the pane opens once and the use is logged
- #604 Done: main reruns collect on a judge whose pane stayed open -- the judge pane closes
- #628 Done: a project with a broken TypeScript reader runs the new-test count -- the count stops with the reader's error instead of a silent text count
- #607 Done: main records a test-edit approval with a near-miss name -- it is refused at once with the exact names
- #612 Done: a plan author revises a plan and pauses -- no finished alert reaches main until it commits
- #616 Done: main asks to push new commits after an earlier push -- the new ask is written, not refused as a repeat
- #617 Done: a user sources host-services.sh from zsh in any folder -- no error line, and the load reading works
- #619 Done: a watcher's seen file is deleted mid-run -- the next new alert or decision still reaches the relay
- #622 Done: the fresh-round retyper meets a fix brief whose round already has a later report -- nothing is typed
- #623 Done: a unit merges with a closing GO and a brief naming its cut -- the cut is marked done, no stray task opens
- #624 Done: the owner answers a decision main opened -- main gets a message with the answer and acts
- #625 Done: a judge writes findings as `**F1 (P1):**` -- the plan author's revise brief carries them
- #626 Done: a judge ends with `VERDICT: NO-GO.` and a reason -- collect records NO-GO and the driver goes on
- #587 Done: main launches a seat whose task text runs past 200 characters -- Orca's task holds the text whole
- #590 Done: a seat's pane exits before it writes a verdict -- main gets one item naming the seat and its unit within a tick
- #611 Done: main starts or restarts -- it loads a smaller rules card, and each moved rule is one pointer away
- #620 Done: a unit's brief names a pre-merge step -- the auto-merge waits until the evidence says the step is done
- #627 Done: a developer runs the dashboard-loop test in a parallel run -- the killed-cycle check passes
- #629 Done: an agent force-removes a scratch worktree holding edits, by its absolute path under the scratch root -- the worktree is gone and no guard blocks it
- #630 Done: main runs `seat.sh close <role> <unit>` on a collected seat whose pane stayed open -- the pane closes and Orca shows its task completed
- #632 Done: the owner answers a driven unit's plan question in the host project's main session -- the driver picks up the answer and starts the revise
- #634 Done: a developer pushes a plugin change to main without raising the version -- the push is refused with version-check's message and main on GitHub stays green
- #635 Done: main runs `merge-queue.sh u1 --help` -- it prints the usage line, merges nothing and no push ask is written

## Issue cases

- #587 Body 1 -- scripts/seat.sh -- a task text over 200 characters reaches Orca whole through --spec-file
- #590 Body 1 -- scripts/main-watch.sh -- a seat whose pane exited with no verdict is reported once naming the seat and unit
- #590 Body 2 -- scripts/main-watch.sh -- a seat that exited after its verdict is not reported
- #611 Body 1 -- templates/main-session.md -- each moved main-session line appears word for word under Details
- #620 Body 1 -- scripts/paths.sh -- a brief with a Pre-merge section holds the merge until the evidence says Pre-merge: done
- #628 Body 1 -- scripts/new-test-count.sh -- a project with typescript is read by the parser, not the label regex
- #589 Body 1 -- scripts/merge-unit-local.sh -- a removal Orca refuses fails the cleanup naming the worktree and the reason
- #589 Body 2 -- scripts/merge-unit-local.sh -- a successful removal prints no failure
- #592 Body 1 -- hooks/__tests__/context-clear-stop.test.sh -- main at 466K is warned 286K past the line
- #592 Body 2 -- hooks/__tests__/context-clear-stop.test.sh -- main at 180K is not warned
- #593 Body 1 -- hooks/bash-guardrails.sh -- a search path from an assignment after && is judged unresolved
- #594 Body 1 -- scripts/__tests__/merge-queue.test.sh -- the real checkout's git folder is unchanged by the run
- #595 Body 1 -- scripts/seat.sh -- a hand launch of a plan seat is refused naming unit-drive.sh
- #595 Body 2 -- scripts/seat.sh -- a hand launch with the override opens, logs one row and prints HAND LAUNCH
- #595 Body 3 -- scripts/seat.sh -- a driver launch of a plan seat passes with no override
- #595 Body 4 -- scripts/seat.sh -- a hand launch of a plan seat is refused naming unit-drive.sh
- #596 Body 1 -- scripts/test-edit-labels.sh -- a single-quoted label with an escaped apostrophe reads with a plain apostrophe
- #596 Body 2 -- scripts/new-test-count.sh -- a test name with an escaped apostrophe is counted under the runner's name
- #596 Body 3 -- scripts/test-edit-labels.sh -- a single-quoted label with an escaped apostrophe reads with a plain apostrophe
- #597 Body 1 -- scripts/read-verdict.sh -- a GO verdict with a reason after a dash reads as GO
- #597 Body 2 -- scripts/seat.sh -- a verdict line with other trailing text is refused naming the bare form
- #598 Body 1 -- scripts/seat.sh -- seat.sh revise on a seat whose latest answer ends on its marker sends the revision though its pane reads working
- #598 Body 2 -- scripts/seat.sh -- seat.sh revise on a seat whose pane reads working with no finish in its latest answer is still refused
- #598 Body 3 -- scripts/seat.sh -- seat.sh revise on a finished seat with an open question is still refused and sends nothing
- #601 Body 1 -- scripts/builder-codex-pass.sh -- a limit with no inline id passes when main's rulings file carries it with a real id
- #601 Body 2 -- scripts/builder-codex-pass.sh -- a limit with no inline id passes when main's rulings file carries it with a real id
- #601 Body 3 -- scripts/builder-codex-pass.sh -- a limit whose rulings id is void or absent is refused
- #602 Body 1 -- scripts/answer-worker.sh -- an answer by unit name reaches a plan-revise seat's pane when no Builder runs
- #602 Body 2 -- scripts/answer-worker.sh -- an answer by handle reaches a plan-revise seat's pane
- #603 Body 1 -- hooks/duplicate-agent-guard.sh -- main opens a probe pane with a valid approval id and the use is logged
- #603 Body 2 -- hooks/duplicate-agent-guard.sh -- main with no approval prefix is still blocked
- #603 Body 3 -- hooks/duplicate-agent-guard.sh -- a void approval id is blocked
- #604 Body 1 -- scripts/seat.sh -- a judge pane left open after its verdict is closed by a rerun of collect
- #604 Body 2 -- scripts/seat.sh -- a judge pane with no verdict yet is not closed
- #604 Body 3 -- scripts/seat.sh -- a judge pane left open after its verdict is closed by a rerun of collect
- #607 Body 1 -- scripts/decision.sh -- a near-miss test-edit label is refused and the exact names are printed
- #612 Body 1 -- scripts/seat.sh -- a revise seat does not read as finished from the plan it inherited
- #616 Body 1 -- scripts/decision.sh -- two push asks at different tips with the same commit count are both written
- #616 Body 2 -- scripts/decision.sh -- the same tip asked twice is refused as a repeat
- #616 Body 3 -- scripts/decision.sh -- two push asks at different tips with the same commit count are both written
- #617 Body 1 -- scripts/host-services.sh -- sourcing host-services.sh from zsh in another folder prints nothing on stderr
- #617 Body 2 -- scripts/host-services.sh -- sourcing host-services.sh from zsh sets HS_DIR to the scripts folder
- #619 Body 1 -- scripts/cos-watch-alerts.sh -- the alerts watcher still tells a new alert after its seen file is deleted
- #619 Body 2 -- scripts/cos-watch-decisions.sh -- the decisions watcher still fires a new decision after its seen file is deleted
- #622 Body 1 -- scripts/builder-fresh-round.sh -- a fix brief whose round has a later pass report types nothing
- #623 Body 1 -- scripts/merge-unit-local.sh -- a cut the brief alone names counts built on a closing GO
- #624 Body 1 -- scripts/decision.sh -- answering a decision main opened sends main one message with the answer
- #625 Body 1 -- scripts/unit-drive.sh -- a judge finding written as `**F1 (P1):**` reaches the revise brief
- #626 Body 1 -- scripts/read-verdict.sh -- a NO-GO verdict with a reason after a full stop reads as NO-GO
- #627 Body 1 -- scripts/dashboard.sh -- a killed cycle leaves no temporary files and no data.js
- #629 Body 1 -- hooks/git-safety.sh -- a forced remove of a dirty worktree under the scratch root passes
- #630 Body 1 -- scripts/seat.sh -- seat.sh close settles a collected seat's open task and closes its live pane
- #632 Body 1 -- scripts/unit-drive.sh -- an owner answer recorded in another Orca repo's ledger releases the question gate
- #634 Body 1 -- .githooks/pre-push -- a push to main of a plugin change with no version bump is refused naming version-check
- #635 Body 1 -- scripts/merge-queue.sh -- a unit argument that starts with a dash is refused and nothing merges

## Facts

- main-watch's broker reaper reaps nothing when lsof exits non-zero or names no working directory -- scripts/main-watch.sh:840-843 (observed: 2026-11-03)
- read-verdict.sh's verdict pattern ends in an end-of-line anchor that keeps injected spec text out -- scripts/read-verdict.sh:494-496 (observed: 2026-11-03)
- seat.sh launch stores `planref=` as the plan blob at launch -- scripts/seat.sh:571-573 (observed: 2026-11-03)
- seat.sh revise rewrites only `task=` and `revised=` in the record -- scripts/seat.sh:257 (observed: 2026-11-03)
- collect exits on a recorded verdict with no pane close, and prints `no VERDICT yet` otherwise -- scripts/seat.sh:801-802 (observed: 2026-11-03)
- collect swallows a failed pane close, then writes `verdict=` -- scripts/seat.sh:834-835 (observed: 2026-11-03)
- pp_task_close settles a seat's task by its pane's state unless PP_VERDICT_READ=1, which skips only the pane state -- scripts/paths.sh:657-670 (observed: 2026-11-03)
- decision.sh dup matches by question similarity, and gate refuses a match with another id -- scripts/decision.sh:127-132, scripts/decision.sh:188-191 (observed: 2026-11-03)
- the push ask id is `push-<date>-<main tip>` -- scripts/decision.sh:324-325 (observed: 2026-11-03)
- test-edit records whatever label it is given after the ruling check -- scripts/decision.sh:286-290 (observed: 2026-11-03)
- deliver_answer returns with no send for sources main, AskUserQuestion and decision.sh -- scripts/decision.sh:64-66 (observed: 2026-11-03)
- the driver exports COMMANDECK_DRIVER=1, and its stop hint reruns a judge with `seat.sh run` -- scripts/unit-drive.sh:126, scripts/unit-drive.sh:277 (observed: 2026-11-03)
- the revise brief copies only `[P<n>]` and owner-question lines -- scripts/unit-drive.sh:295 (observed: 2026-11-03)
- the fresh-round retyper's idle loop ends before the fix-round parse -- scripts/builder-fresh-round.sh:104-113 (observed: 2026-11-03)
- limits_refuse reads only an inline `ruling:` id -- scripts/builder-codex-pass.sh:1666-1676 (observed: 2026-11-03)
- cut_scan counts only `C<n>: built` evidence lines -- scripts/merge-unit-local.sh:536-538 (observed: 2026-11-03)
- cleanup checks only the remove command's exit code -- scripts/merge-unit-local.sh:204 (observed: 2026-11-03)
- the splitter ends a segment at `&&` with the same flag as `;` -- hooks/bash-guardrails.sh:117-123 (observed: 2026-11-03)
- load_segments records an alias from any plain assignment -- hooks/bash-guardrails.sh:211-220 (observed: 2026-11-03)
- main's hand-made pane is blocked outright -- hooks/duplicate-agent-guard.sh:205-209 (observed: 2026-11-03)
- ruling_id_state checks an id's shape and its log row -- hooks/lib/ruling-id.sh:7-12 (observed: 2026-11-03)
- hooks read the ruling log at `$HOME/.claude/rulings/<project>.jsonl` by default -- hooks/ruling-cite-gate.sh:34-35 (observed: 2026-11-03)
- the alerts watcher touches its seen file once and reads it bare in each poll -- scripts/cos-watch-alerts.sh:13-15, scripts/cos-watch-alerts.sh:38 (observed: 2026-11-03)
- the decisions watcher touches its seen file once, before poll -- scripts/cos-watch-decisions.sh:13-17 (observed: 2026-11-03)
- host-services.sh finds its folder by BASH_SOURCE and sources paths.sh on Darwin -- scripts/host-services.sh:11-16 (observed: 2026-11-03)
- paths.sh refuses any shell but bash -- scripts/paths.sh:19-20 (observed: 2026-11-03)
- dashboard.sh logs a killed cycle before removing its temp files -- scripts/dashboard.sh:1646-1649 (observed: 2026-11-03)
- the dashboard-loop check runs straight after the kill log line, polling every 0.1 s -- scripts/__tests__/dashboard-loop.test.sh:21, scripts/__tests__/dashboard-loop.test.sh:93-95 (observed: 2026-11-03)
- answer-worker.sh by unit name looks up only the Builder pane, else queues -- scripts/answer-worker.sh:75-77 (observed: 2026-11-03)
- pp_relay_event is a no-op with no recorded run and never changes its caller's exit -- scripts/paths.sh:370-381 (observed: 2026-11-03)
- builder-launch.sh launches a Builder through `seat.sh launch builder` -- scripts/builder-launch.sh:302-304 (observed: 2026-11-03)
- an undriven plan-judge launch is a case in the seat tests -- scripts/__tests__/seat-plan-judges.test.sh:43 (observed: 2026-11-03)
- the shared seat fixture's seat_sh runs seat.sh with an `env -u` list that keeps an exported variable it does not name -- scripts/__tests__/fixtures/seat-setup.sh:24-25 (observed: 2026-11-03)
- srun exports COMMANDECK_DRIVER=1 only in its own subshell -- scripts/__tests__/fixtures/seat-setup.sh:84 (observed: 2026-11-03)
- seat-run-refused.test.sh runs `seat.sh run plan-judge-sol` directly, not through seat_sh -- scripts/__tests__/seat-run-refused.test.sh:50-51 (observed: 2026-11-03)
- seat-run.test.sh runs `seat.sh run plan-judge-sol` directly from a script whose process group is then killed -- scripts/__tests__/seat-run.test.sh:63-65 (observed: 2026-11-03)
- review limits are 1000 changed lines and 5 issues -- config/routing.json:94-95 (observed: 2026-11-03)
- the context hook exits silently when the size read fails -- hooks/context-clear-stop.sh:29-31 (observed: 2026-11-03)
- dashboard.sh sets waiting-main when no agent is working -- scripts/dashboard.sh:400-401 (observed: 2026-11-03)
- stepsOf draws planning with Build and Review todo, and waiting-main with no GO as after(3) -- hooks/units-elements.ts:76-80 (observed: 2026-11-03)
- plan_seats reads each seat record's launched, role and unit -- scripts/dashboard.sh:183-187 (observed: 2026-11-03)
- main-watch's tick has a machine-safety block -- scripts/main-watch.sh:25-27 (observed: 2026-11-03)
- collect writes `verdict=` into the seat record -- scripts/seat.sh:835 (observed: 2026-11-03)
- launch and revise pass the task text with `--spec` -- scripts/seat.sh:249, scripts/seat.sh:566 (observed: 2026-11-03)
- the typed pointer keeps the spec on disk because a large paste failed -- scripts/seat.sh:505-509 (observed: 2026-11-03)
- dispatch-task.sh reads a task's spec back from Orca to type it -- scripts/dispatch-task.sh:55-59 (observed: 2026-11-03)
- pp_merge_held holds on `Merge: hold` or an open owner decision -- scripts/paths.sh:1474-1483 (observed: 2026-11-03)
- the brief template names `Merge: hold` and `## Post-merge` -- templates/_builder-brief-template.md:8 (observed: 2026-11-03)
- main-session.md's injected part ends at its Details heading -- templates/main-session.md:41 (observed: 2026-11-03)
- startup-size.sh fails an injected part past 40 lines -- scripts/startup-size.sh:8 (observed: 2026-11-03)
- the reader exits 2 when typescript cannot be loaded from the project -- scripts/new-test-count.sh:52-57 (observed: 2026-11-03)
- any non-zero reader exit falls back to the label regex, its stderr captured unread -- scripts/new-test-count.sh:158-163 (observed: 2026-11-03)
- the test file's only JS case runs with no typescript on the module path -- scripts/__tests__/new-test-count.test.sh:51-55 (observed: 2026-11-03)
- seat.sh accepts only launch, collect, wait, effort, status, run and revise -- scripts/seat.sh:62 (observed: 2026-11-03)
- collect retries settling until COMMANDECK_SEAT_SETTLE_RETRY_S ends, then exits 4 with the pane kept open and no verdict recorded -- scripts/seat.sh:820-825 (observed: 2026-11-03)
- a record whose last verdict=/revised= line is a verdict counts as collected -- scripts/seat.sh:801 (observed: 2026-11-03)
- pp_task_close checks open questions only when the pane reads idle or PP_VERDICT_READ=1, and refuses a working or unread one -- scripts/paths.sh:669-676 (observed: 2026-11-03)
- the question gate reads only `decision.sh list` for an answer at or after the ask -- scripts/unit-drive.sh:236-241 (observed: 2026-11-03)
- decision.sh's ledger is the decisions file of PP_MAIN -- scripts/decision.sh:40 (observed: 2026-11-03)
- deliver_answer's no-send case covers every `decision.sh*` source -- scripts/decision.sh:66 (observed: 2026-11-03)
- push-ask records its decision with source `decision.sh push-ask` -- scripts/decision.sh:324-325 (observed: 2026-11-03)
- main-watch's push_ask runs `decision.sh push-ask` from the watcher, not from a pane -- scripts/main-watch.sh:1148-1152 (observed: 2026-11-03)
- the driver's ask to main names `plan <first 8 of the hash>` and the decision id plan-<unit> -- scripts/unit-drive.sh:230 (observed: 2026-11-03)
- the reader's one catch exits 2 for any failure to load typescript -- scripts/new-test-count.sh:52-57 (observed: 2026-11-03)
- name() returns a string literal's source text with its escapes kept -- scripts/new-test-count.sh:112-116 (observed: 2026-11-03)
- js_regex returns each captured label as written -- scripts/new-test-count.sh:151-155 (observed: 2026-11-03)
- the regex fallback runs on any non-zero reader exit -- scripts/new-test-count.sh:163 (observed: 2026-11-03)
- load_segments unsets a name's earlier bindings before it records a new alias -- hooks/bash-guardrails.sh:214 (observed: 2026-11-03)
- requirements.sh repairs and exports PATH when loaded, Darwin only -- scripts/requirements.sh:18-19, scripts/requirements.sh:47-49 (observed: 2026-11-03)
- requirements.sh's Homebrew folder can be moved by COMMANDECK_BREW_PREFIX -- scripts/requirements.sh:28 (observed: 2026-11-03)
- main's warning names the overage only past LINE + 40K -- hooks/context-line.sh:71-76 (observed: 2026-11-03)
- a forced worktree remove passes only in a fixed-list form -- hooks/git-safety.sh:218 (observed: 2026-11-03)
- a forced worktree remove of a worktree whose status is not clean is blocked -- hooks/git-safety.sh:330 (observed: 2026-11-03)
- wt_clean reads `git ls-files -v` first and treats a lowercase or `S` tag, or a failing ls-files, as not clean -- hooks/git-safety.sh:239-243 (observed: 2026-11-03)
- the hook's tests mark files assume-unchanged and skip-worktree with `update-index` and expect the forced remove blocked -- hooks/__tests__/git-safety.test.sh:145-148 (observed: 2026-11-03)
- PP_SCRATCH defaults under `$HOME/.commandeck/scratch` unless COMMANDECK_SCRATCH is set -- scripts/paths.sh:64 (observed: 2026-11-03)
- revise's awk drops only `revised=` lines and replaces `task=`, so an earlier `verdict=` stays -- scripts/seat.sh:257 (observed: 2026-11-03)
- the seat record's keys are written in one printf at launch -- scripts/seat.sh:573 (observed: 2026-11-03)
- launch passes the task text to orca-task-create.sh with `--spec` -- scripts/seat.sh:566 (observed: 2026-11-03)
- orca-task-create.sh passes its arguments to `orchestration task-create` -- scripts/orca-task-create.sh:30 (observed: 2026-11-03)
- main-watch's state folder is `$SCRATCH/main-watch` -- scripts/main-watch.sh:67 (observed: 2026-11-03)
- dashboard.sh alerts() feeds its inputs to dashboard_alerts.jq -- scripts/dashboard.sh:1095-1101 (observed: 2026-11-03)
- collect settles each task with PP_VERDICT_READ=1 pp_task_close (main's #631 fix) -- scripts/seat.sh:816 (observed: 2026-11-03)
- revise refuses a pane that is not live, then any pane not read idle, before it settles the old task -- scripts/seat.sh:243-248 (observed: 2026-11-03)
- the driver collects with `seat.sh collect` and reruns a revise through `seat.sh run`, not `seat.sh revise` -- scripts/unit-drive.sh:211, scripts/unit-drive.sh:183 (observed: 2026-11-03)
- main-watch keys a seat's state by handle and current task, and reads its settled finish from `kind-<key>` -- scripts/main-watch.sh:1188, scripts/main-watch.sh:1206 (observed: 2026-11-03)
- has_result reads a seat's report through read-verdict.sh and takes a `VERDICT:` or `-DONE` line as its finish -- scripts/main-watch.sh:726-731 (observed: 2026-11-03)
- a seat's latest answer is the one after its last prompt -- scripts/main-watch.sh:1262 (observed: 2026-11-03)
- read-verdict.sh takes a worktree path and launch epoch to bind a seat's session log -- scripts/read-verdict.sh:16-17 (observed: 2026-11-03)
- the wake reads task-list with no `--full` and uses `.spec` for the landed-merge close and the task lines -- scripts/orca-wait.sh:466, scripts/orca-wait.sh:473-477 (observed: 2026-11-03)
- the awareness hook reads task-list `--brief` and prints `.spec // .task_title` -- hooks/agent-awareness.sh:72, hooks/agent-awareness.sh:124 (observed: 2026-11-03)
- paths.sh's three inbox reads already pass `--full` -- scripts/paths.sh:473, scripts/paths.sh:551, scripts/paths.sh:621 (observed: 2026-11-03)
- duplicate-agent-guard blocks a hand agent pane in a worktree whose pane list shows a live agent -- hooks/duplicate-agent-guard.sh:214-219 (observed: 2026-11-03)
- the README's driver step says unit-drive.sh start runs the plan seats, with no word on a hand launch -- README.md:283-287 (observed: 2026-11-03)
- the seat revise docs say revise refuses a busy pane, and no seat close section exists -- docs/commands.md:73-78 (observed: 2026-11-03)
- the hooks docs say a forced worktree remove passes only for a clean worktree, and name no probe-pane prefix -- docs/hooks.md:15, docs/hooks.md:18 (observed: 2026-11-03)
- the PC test peer is an ssh destination read from `~/.config/devenv/peer` -- scripts/peer-offload.sh:5 (observed: 2026-11-03)
- collect reads the seat's latest answer with read-verdict.sh and takes a `VERDICT:` banner or the done marker as its finish -- scripts/seat.sh:741-746 (observed: 2026-11-03)
- collect closes the seat's pane, then writes `verdict=` -- scripts/seat.sh:834-835 (observed: 2026-11-03)
- revise refuses a pane that is not in Orca's terminal list -- scripts/seat.sh:243 (observed: 2026-11-03)
- main-watch writes `finished` or `silent` as a seat's settled kind -- scripts/main-watch.sh:1263-1266 (observed: 2026-11-03)
- the concise check row has `from` and no body, thread_id or from_handle; the full row has them -- scripts/__tests__/fixtures/orca-1.4.246-views.json:1-6 (observed: 2026-11-03)
- ask-main.sh's resume and wait read `thread_id`, `body` and `from_handle` from check with no `--full` -- scripts/ask-main.sh:25, scripts/ask-main.sh:76-84 (observed: 2026-11-03)
- cos-own-echo.sh reads `from_handle` from check with no `--full` -- hooks/cos-own-echo.sh:54-57 (observed: 2026-11-03)
- watch-agents.sh prints each question's `body` from check with no `--full` -- scripts/watch-agents.sh:42-51 (observed: 2026-11-03)
- inbox-drain.sh prints `.body` and `.from` from check with no `--full` -- scripts/inbox-drain.sh:68-74 (observed: 2026-11-03)
- orca-wait.sh's two check reads pass no `--full`, and its wake reads `from_handle` and `body` -- scripts/orca-wait.sh:531-533, scripts/orca-wait.sh:121, scripts/orca-wait.sh:316 (observed: 2026-11-03)
- the Builder and add-work briefs name `.result.dispatchId` of a check with no `--full` -- scripts/builder-codex-pass.sh:2464, scripts/builder-add-work.sh:66 (observed: 2026-11-03)
- await-agents.sh's check read uses only `.type` -- scripts/await-agents.sh:67-68 (observed: 2026-11-03)
- pp_task_close prints one refusal line for a working pane and an unread inbox alike -- scripts/paths.sh:675 (observed: 2026-11-03)
- the pre-push hook runs only the shell tests in a worktree of the pushed commit -- .githooks/pre-push:22-33 (observed: 2026-11-03)
- version-check.sh compares the tree with a base, exit 1 when the plugin changed and its version did not -- ci/version-check.sh:1-12 (observed: 2026-11-03)
- merge-queue.sh prints usage on a first `-h`/`--help` and its unit pattern allows a leading dash -- scripts/merge-queue.sh:16, scripts/merge-queue.sh:22 (observed: 2026-11-03)
- seat-revise.test.sh's own task-create stand-in logs only Orca's arguments and the issue-485 check counts the revision text there -- scripts/__tests__/seat-revise.test.sh:14, scripts/__tests__/seat-revise.test.sh:29 (observed: 2026-11-03)
- revised_ran proves a revised prompt landed by `--state --task` on user rows, so an old PLAN-DONE or a same-second prompt answers no -- scripts/main-watch.sh:1179-1184 (observed: 2026-11-03)
- the claude report reader takes the answer after the session's last prompt -- scripts/read-verdict.sh:664-671 (observed: 2026-11-03)
- `post <key> ... once` keeps the task, retries while `posted=` is empty and settles a delivered item `handled` -- scripts/main-watch.sh:212-245 (observed: 2026-11-03)
- flush writes `posted=<now>` only after Orca took the send -- scripts/main-watch.sh:448-451 (observed: 2026-11-03)
- VERDICT_RE ends at `$` with only spaces, stars and a quote after the word -- scripts/read-verdict.sh:496 (observed: 2026-11-03)
- the pane scan keeps every unfenced line matching VERDICT_RE with no second-word test -- scripts/read-verdict.sh:529 (observed: 2026-11-03)
- both session-log readers select answers by one jq regex each, end-anchored, with no second-word test -- scripts/read-verdict.sh:649, scripts/read-verdict.sh:675 (observed: 2026-11-03)
- revise refuses any pane pane_is_busy does not read idle, then settles the record's `task=` -- scripts/seat.sh:243-248 (observed: 2026-11-03)
- revise replaces `task=` with the new task and appends `revised=<new task>` -- scripts/seat.sh:257 (observed: 2026-11-03)
- collect's finish read is read-verdict.sh on the handle, the banner, then the marker, then pp_seat_done -- scripts/seat.sh:741-747 (observed: 2026-11-03)
- read-verdict.sh --state takes `--task` and `--launched` -- scripts/read-verdict.sh:237-246 (observed: 2026-11-03)
- post mints a notification task when its task argument is empty -- scripts/main-watch.sh:230-236 (observed: 2026-11-03)
- post writes `handled` and returns before any send when its task's status is completed or failed -- scripts/main-watch.sh:238-240 (observed: 2026-11-03)
- seat-settle.test.sh reads the real read-verdict.sh over a screen fixture with the pane reading working -- scripts/__tests__/seat-settle.test.sh:12-23 (observed: 2026-11-03)
- read-verdict.test.sh writes a Claude session log under the fixture home's projects folder -- scripts/__tests__/read-verdict.test.sh:40-43 (observed: 2026-11-03)

## Plan change log

- 2026-11-03: the owner's answers folded in (D8): C9 approved, wording approved, thirteen closes approved; #591, #615 and #621 became partial cuts C10-C12; the other sixteen open issues became one question each
- 2026-11-03: the owner answered all sixteen questions (a) (D10): C13-C16 added for #587, #590, #611, #620; #506, #571, #600, #613 closed by main; eight stay open
- 2026-11-03: #628 folded into C3 on main's relay of the owner's order (two cases, about 30 lines); main reports the seventeen closes done on GitHub
- 2026-11-03: revise on decision plan-commandeck-open-2026-11-03 (all sixteen (a)): already held as D10; the question section reads None: answered as D10; no cut, step or test changed
- 2026-11-03: #631 folded into C2 (D12): collect's last settle passes `done`, skipping only the pane-working refusal; two seat-settle cases, about 25 lines
- 2026-11-03: #630 folded into C2 (D14): `seat.sh close <role> <unit>` for a seat with a recorded verdict; two seat-settle cases, about 75 lines
- 2026-11-03: #632 folded into C4 (D13, A4): the question gate also reads each other Orca repo's ledger; three unit-drive cases, about 50 lines; Closes, sizes and New tests updated
- 2026-11-03: plan-judge-sol F1 accepted: D5 and C3 wake main for source `decision.sh push-ask` too (main-watch writes it, no pane asked); decision case added
- 2026-11-03: plan-judge-sol F2 accepted: C10/D9 delete a branch only with `git branch -d` when its tip is in main; an unmerged branch is kept and named, a detached HEAD not in main keeps its worktree; two sweep cases and a Break line added
- 2026-11-03: plan-judge-sol F3 accepted: A4 dropped; D15 and C4 take another repo's row only with the ask's `plan <hash8>` token, the ask tells main to keep it; A6 and a unit-drive case added
- 2026-11-03: plan-judge-sol F4 accepted: the picker id and the internal host issue reference removed from D10, D12 and this log
- 2026-11-03: plan-judge-sol F5 accepted: #629 built in C10 (D18): a forced remove under the scratch root passes in git-safety.sh; Closes, Triage, Done, Issue cases and three git-safety cases added
- 2026-11-03: plan-judge-sol F6 accepted: D16 sets the order in pp_task_close (question check first, always wins); two seat-settle cases for completed plus open question and completed plus unread inbox
- 2026-11-03: plan-judge-sol F7 accepted: D17: the reader exits 3 when `require.resolve` finds no typescript, 2 for a load or parse failure; only 3 falls back; an import-time-throw case added
- 2026-11-03: plan-judge-sol F8 accepted: one unescape rule in the lister, `name()` and `js_regex()`; a parser-and-fallback parity case added
- 2026-11-03: plan-judge-sol F9 accepted: C6 says a conditional reassignment drops the earlier binding (the existing unset at bash-guardrails.sh:214 stays); a `F=scripts; true && F=.` case added
- 2026-11-03: plan-judge-sol F10 accepted: D6 sets the sourcing shell's PATH from a bash child loading requirements.sh alone; a stubbed-Darwin zsh case added and L1 narrowed to the stub
- 2026-11-03: plan-judge-sol F11 accepted: C9 ports the host's jsonl log, `HAND LAUNCH:` line and 24-hour dashboard alert (D19), dropping the relay note; Prior art names the twin; two dashboard-alerts cases added
- 2026-11-03: plan-judge-sol F12 accepted: C12 reads the last `verdict=`/`revised=` line, so an active revise after an old verdict shows planning; a case added
- 2026-11-03: plan-judge-sol F13 accepted: C14 and D11 match an exit row by exact pty id, which launch records (`pty=`); A5 and two cases (two seats in one worktree; no pty value) added
- 2026-11-03: plan-judge-sol F14 accepted: D7 corrected, the below-40K warning lacked the overage; context-line.sh gains `<n>K past` and the 181K case asserts 1K past
- 2026-11-03: plan-judge-sol F15 accepted: Data design names the pty field, dead-seat mark, sweep stamp and log, task-text file and the hand-launch jsonl, each with writer, reader, lifetime, retry and absent behaviour
- 2026-11-03: plan-judge-sol F16 accepted: User-visible changes adds #592, #591, #629, #615, #621, #587, #590, #611 and #620, the sweep's removal included
- 2026-11-03: plan-judge-sol F17 accepted: `Catches:` lines added to C9, C10, C14 and C16
- 2026-11-03: base moved: the worktree fast-forwarded from 21c4f1d to local main 991ec40 (main's 4530f6f #631 fix, 991ec40 paths.sh `--full` reads, b7629bc new-test-count read change); drifted Facts lines re-read and corrected
- 2026-11-03: plan-judge-sol (round 2) F1 accepted: the private repo names left in Assumptions replaced with plain descriptions (this one and three of the owner's other projects; the host project's ledger)
- 2026-11-03: plan-judge-sol F2 accepted: #633 given a disposition: Triage row and owner question Q1 ((a) keep open for its own unit, recommended; (b) build as C17 once main names the launch command); decision.sh rulings for the question's words found no earlier pick on it
- 2026-11-03: plan-judge-sol F3 accepted: #631 is fixed on main (4530f6f); C2's 4th `done` argument, last settle and its paths.sh/seat.sh steps dropped; #631 moved from Closes to a close-as-fixed Triage row; its Done and Issue cases rows removed; D12 rewritten to reuse `PP_VERDICT_READ=1`
- 2026-11-03: plan-judge-sol F3 follow-on: D16 rewritten: #598's proof is collect's recorded verdict, not Orca's completed listing, so pp_task_close is unchanged and the fixture's task-list stand-in step and five Orca-listing seat-settle cases are dropped
- 2026-11-03: plan-judge-sol F4 accepted: C8 adds orca-wait.sh:466 (`--full`) and agent-awareness.sh:72 (`--brief` to `--full`), each with its consumers; one orca-full-flag case added; Assumptions settle that concise and `--brief` rows carry no spec; C8's paths.sh step dropped (main's 991ec40)
- 2026-11-03: plan-judge-sol F5 accepted: C14's finish test is D21 (current-episode verdict, main-watch's own finish state for the current task, or the session-log report reader), not any raw `verdict=` line; two dead-seat cases cover both judge inputs; Builder check before C14 settles the reader call with a gone pane
- 2026-11-03: plan-judge-sol F6 accepted: revise skips its own pane-busy gate (seat.sh:245-246) only for a seat with a recorded verdict and settles through `PP_VERDICT_READ=1`, the open-question check kept; A7 and three seat-settle cases run the real revise command
- 2026-11-03: plan-judge-sol F7 accepted: PC and Mac contracts settled at plan time over ssh: the PC is the Linux test peer with no seats (0 terminals, 0 repos) and tests stub orca-ide, so the PC Builder checks for terminal list, repo list and lsof are removed; D20 fixes the exit-log default per host with the row shape; L5 states the PC's missing `operator_close` cause
- 2026-11-03: plan-judge-sol F8 accepted: README.md, docs/commands.md and docs/hooks.md steps added (hand-launch override, `seat close`, the revise rule, the probe-pane prefix, the scratch-root forced remove); planned size 67 files
- 2026-11-03: found in passing: the PC has no zsh, so the #617 zsh cases skip there; L6 records it and makes #617 partial unless they pass where zsh exists
- 2026-11-03: revise on decision plan-commandeck-open-2026-11-03 Q1 (a): D22 added (#633 stays open for its own unit); Why, Re-list and the #633 Triage row say so; the question section reads None: answered as D22; no cut, step, test, Closes or size changed
- 2026-11-03: plan-judge-sol (round 3) F1 accepted: C8 adds `--full` to the `orchestration check` reads that use full-only fields (ask-main.sh, cos-own-echo.sh, watch-agents.sh, inbox-drain.sh with `.from_handle // .from`, orca-wait.sh) and to the two brief lines naming check's dispatchId (D23); a Builder check settles ask-main's deliveryId break; four cases added
- 2026-11-03: plan-judge-sol F2 accepted: D16 and C2 rewritten: revise reads the finish from the seat's latest answer with collect's own reader (`read_finish`), not a recorded verdict, since collect closes the pane first; A7, the three revise cases, Break lines, docs and #598's Done and Issue cases follow
- 2026-11-03: plan-judge-sol F3 accepted: C14's Builder check and its `--state` fallback dropped (the seat-bound positional reader read a gone pane's VERDICT, settled in Assumptions); a state file counts only when it holds `finished`; D21 says a turn that merely ended is no finish; a `silent` case added
- 2026-11-03: plan-judge-sol F4 accepted: #634 and #635 built in C17 (D24 pre-push version check, D25 merge-queue argument pattern), three cases, Break lines; #636 is owner question Q2; Triage, Re-list, Closes, Done, Issue cases and What can go wrong (merge-queue junk argument row replaces the test-edit no-worktree row, the verdict-junk row moves out, its case still under D1 and a Break line) updated
- 2026-11-03: plan-judge-sol F5 (question for the owner): Q1 asks to approve editing seat-revise.test.sh's task-create stand-in to log the `--spec-file` text; `decision.sh rulings` for its words and #636's found no earlier pick; planned size 77 files, 1945 lines; New tests 111
- 2026-11-03: the owner answered Q1 (a) (D26): C13's revise moves to `--spec-file` as planned; a step edits seat-revise.test.sh's task-create stand-in to log the `--spec-file` text, the issue-485 check unchanged and named in Acceptance test; planned size 1948 lines; New tests 112 (110 new)
- 2026-11-03: the owner answered Q2 (a) (D27): #636 stays open for its own unit; Why, Re-list and Triage say so; no cut, step or test added
- 2026-11-03: Question for the owner reads `None: answered as D26 (Q1) and D27 (Q2)`
- 2026-11-03: plan-judge-sol (round 3) F1 accepted: D21's session-log finish counts for a revised seat only once revised_ran says the revised prompt landed; C14, Steps, D21 and a dead-seat case (old PLAN-DONE, revised prompt not landed, pane exits: reported) updated; Facts cite main-watch.sh:1179-1184 and read-verdict.sh:664-671
- 2026-11-03: plan-judge-sol (round 3) F2 accepted: C14 and D11 pick the latest exit row per exact pty since launch before the `operator_close` test; a dead-seat case (unknown then operator_close for one pty: not reported) added
- 2026-11-03: plan-judge-sol (round 3) F3 accepted: the dead-seat mark file is dropped; C14 posts through the existing `post <launch key> ... once` path, whose item file already retries a refused send and settles a delivered one; Data design and Steps updated; Facts cite main-watch.sh:212-245 and 448-451; New tests 114 (112 new), planned size 1950 lines
- 2026-11-03: plan-judge-sol (round 4) F1 accepted: C1 ports the host's merged #3681 rules word for word (PP_VERDICT_END, PP_VERDICT_CHOICE, the LOG_VERDICT_RE lookahead), so a choice list `VERDICT: GO,NO-GO` reads no verdict in the pane and both session-log readers; Prior art and Triage now name C1's merged host twin; D1, C1, Steps, Break, User-visible changes, Claims and Facts updated
- 2026-11-03: plan-judge-sol (round 4) F1 tests: two read-verdict.test.sh cases (unspaced and spaced choice list, each checking pane and session-log readers); A8 accepts a reason naming another verdict word as no verdict, as on the host
- 2026-11-03: plan-judge-sol (round 4) F2 accepted: C2/D16 revise counts a finish for a revised seat only once `read-verdict.sh --state --task <current task>` prints `session=` (the revised_ran test C14 uses); Steps, Break, User-visible changes, Claims and Facts updated; A9 states a revised seat with an unreadable log stays refused
- 2026-11-03: plan-judge-sol (round 4) F2 tests: two seat-settle.test.sh cases on the real read-verdict.sh over a session log (revised prompt not landed: refused; landed: sent)
- 2026-11-03: plan-judge-sol (round 4) F3 accepted: C14 calls `post <key> "" ... once`, the task argument empty so post mints its own notification task, never the seat's; Data design, C14, Steps, Break, Claims and Facts (main-watch.sh:230-240) updated; a dead-seat case (the seat's own task failed: one item) added
- 2026-11-03: sizes after round 4: C1 ~75, C2 ~146, C14 ~107 lines; planned size 77 files, 1968 lines; New tests 119 (117 new)
- 2026-11-03: Data design's `once` settle citation corrected from main-watch.sh:239 to main-watch.sh:245, where the `once` handled line sits
- 2026-11-03: plan-judge-sol (round 5) F1 accepted: C10's clean is defined (D9a): empty status and no `ls-files -v` lowercase or `S` tag, as git-safety.sh wt_clean; a failing status or ls-files keeps the worktree; reproduced on git 2.55.0 (a plain remove deleted an assume-unchanged edit); three sweep cases, a Break line and a Claims line added; planned size 1998 lines, New tests 122 (120 new)
- 2026-11-03: plan-judge-sol (round 5) F2 accepted: the batch's `## The issues` line lacked #629, #630, #632, #634 and #635, so brief-issues.sh froze 28 issues against the plan's 33 Closes; the five added to the batch line, brief-issues.sh now prints all 33; no plan line changes
- 2026-11-03: plan-judge-sol (round 6) F1 accepted: C10's in-use check is fail-closed (D9b): an lsof that exits non-zero or names no working directory keeps every candidate and says why in sweep.log, as main-watch.sh reap_brokers (840-843); on this Mac `lsof -a -d cwd -Fn` exits 0 and names 353 directories (lsof 4.91, 2026-11-03); one sweep case with a failing lsof stub, a Break line and a Facts line added; planned size 2004 lines, New tests 123 (121 new)
- 2026-11-03: plan-judge-sol (round 7) F1 accepted: the #595 fixture override moves from seat_sh to a fixture-wide export (D28), so the direct `seat.sh run plan-judge-sol` calls at seat-run-refused.test.sh:50-51 and seat-run.test.sh:63-65 keep their detachment checks; the driver is read first; one new case (driver launch with the override set logs nothing) and the two existing checks named in Acceptance test; the Assumption, the Claims line and the seat_sh Fact corrected (14 files source the fixture, not 11); planned size 2010 lines; New tests 126 (122 new)
- 2026-11-04: the Builder, on main's ruling: the Host twin line drops the host repository's name and its two commit ids, which the public repository's leak test refuses
- 2026-11-04: the Builder, on main's ruling: the host-services.sh line writes `${0}` for the shell parameter, which the leak test otherwise reads as a spend figure
- 2026-11-04: the Builder, on main's ruling (answer-1793775031-9404): the #593 Break line names hooks/__tests__/bash-guardrails-assign.test.sh, where C6 put the case (bash-guardrails.test.sh was at the runner's line cap)
- 2026-11-04: the Builder, on main's ruling (answer-1793776103-66533): the New tests: cap rises from 126 to 131; the build adds 5 more checks than planned, each catches its own bug with a red under break (evidence, ## Extra tests)
- 2026-11-04: the Builder, fix round 1: pass 1's findings add the Pre-merge done line and the limit approval to Data design; the Pre-merge section reads its subsections, the done line carries the cksum of the steps, and any other heading naming pre-merge holds; four What can go wrong rows, their checks inside the existing C16 test
- 2026-11-04: the Builder, on main's ruling (answer-1793776694-99898): section_lines in builder-codex-pass.sh ends a section at a heading of its own level or higher, so a limit under a `###` below the limits heading is compared; the New tests: cap rises to 132 for its red check, its own label (main's cap call: the fix needs its red check)
- 2026-11-04: the Builder, fix round 2 (class redesign, premerge-heading found in passes 1 and 2): Data design's Pre-merge entry becomes a fail-closed reader contract (one exact start shape, every other heading-like shape naming pre-merge holds, a section ends only at a sure level 1 or 2 heading outside a fence, the tick the one retry path); four What can go wrong rows; design-only final pass before the code
- 2026-11-04: the Builder, fix round 3 (premerge-heading third return, main's ruling answer-1793778896-37094): the Pre-merge hold becomes a stamp with no parser (any line naming pre-merge holds until `Pre-merge: done <cksum of the whole brief>`); section_lines keeps every non-blank line in its section, heading and bold lines included; What can go wrong: the bold-only step and brief-edited-after-done rows, the bold/heading limit row, the heading-shape rows now expect the done line; design-only final pass before the code
- 2026-11-04: the Builder, fix round 4 (pass 4, class-miss): section_lines' start is the one column-0 `#` shape; limits_check refuses, naming the line, every other line in the Builder's brief or plan that begins with a limits heading name once markup is stripped (the allowlist); plan_section stays display-only; What can go wrong gains the unread-shape row; design-only final pass before the code
- 2026-11-04: the Builder, fix round 5 (class-miss found in passes 4 and 5; class redesign): the limits gate becomes a fixed list (two literal heading lines) plus a name rule (any other non-table line whose letters contain a limits heading name refuses, naming its line); prose names it as the limits section; What can go wrong gains the inline-markup row; design-only final pass before the code
- 2026-11-04: the Builder, after design pass 6 GO (code to the design): C16's Produces, Steps and User-visible lines follow the stamp; the second merge-gate check becomes "a brief that names no pre-merge step does not hold" (an empty section names it, so it now holds); the brief template describes the hold without the word, which would otherwise hold every unit
- 2026-11-04: the Builder, fix round 7 (pass 7, ignored-close-failure): What can go wrong gains the refused-pane-close row (seat.sh close and collect exit 5, never `closed seat=`)
- 2026-11-04: the Builder, on main's ruling (answer-1793782183-75924): the New tests: cap rises from 132 to 133 for the one merged check in seat-settle.test.sh, the regression proof for pass 7's NO-GO finding (seat.sh close reported success when the pane close failed); main decides cap questions (owner ruling 2026-10-30)
- 2026-11-04: the Builder, fix round 8 (pass 8, revision-baseline-race): seat.sh revise reads planref= before it sends the revision; What can go wrong gains the commit-before-dispatch row
- 2026-11-04: the Builder, on main's ruling (answer-1793783347-63451): the New tests: cap rises from 133 to 134 for the new seat-revise.test.sh check, the regression proof for pass 8's NO-GO finding (revise recorded the plan baseline after dispatch); main decides cap questions (owner ruling 2026-10-30)

# commandeck-open-2026-11-04 -- every open plugin issue in one unit, 28 cuts

Owner's words: the owner, 2026-11-04: one plugin unit for all open plugin issues.
Goal: Build all 37 open plugin issues in 28 cuts in one unit, one merge; #631 closes as already fixed on main.
Plan: .claude/plans/commandeck-open-2026-11-04.md
Tier: Panel; LOCAL merge only; changed-file tests only; no test-timeout raises; plugin shell tests on the PC only, the full shell suite on the PC before the merge.
Closes: #555 #576 #584 #585 #586 #588 #591 #608 #610 #614 #615 #621 #633 #636 #637 #638 #639 #640 #641 #645 #646 #647 #648 #649 #650 #651 #652 #653 #654 #655 #656 #657 #658 #659 #660 #662 #663
Split override: the owner's order names one unit for all open plugin issues, and the owner's answer to this plan's scope question chose all 38 in one plan, built cut by cut in one slot.
Build order: C1, C2, C3, then CB1-CB2, CC1-CC3, CD1-CD4, CE1-CE4, CF1-CF4, CG1-CG3, CH1-CH4, each after every cut it names; a cut marked after rules-port waits for that unit's merge; C4 last
Merge message: `Closes #N` for each issue fully done, `Refs #N` for each left partial (Progress notes name the conditions)
- Planned size: 130 files, 6150 changed lines
New tests: commandeck-open-2026-11-04 287 -- 286 new cases; one is the existing seat-settle.test.sh check named as #631's proof

## Why

The order puts every open plugin issue in one unit, and the owner's answer to this plan's scope question confirmed all 38, the units redesign (#555) in full and the Orca trials (#584, #585, #586) and the coordinator measure (#608) as scripted trials plus the removals they unlock. #631 is already fixed on main. Part 1 (C1-C4) goes first: it stops the plan driver and Builder answers stalling silently, which every later cut's build depends on. The other cuts are grouped by code area: seat and judge readers (CB), same-named units, Serena and push answers (CC), messages between panes and Orca output (CD), the cuts that wait for the rules-port unit (CE), coordinator load and recovery (CF), the Orca trials (CG) and the units views (CH). Each fix sits in the script that has the fault; each new file names the simpler alternative it beat. Cuts that edit a file the rules-port unit is changing (main-watch.sh, builder-launch.sh, builder-codex-pass.sh, merge-unit-local.sh, merge-rules.py, the Builder template, README.md, CHANGELOG.md, the manifest) are marked and wait for its merge.

## Prior art

- Standard: Bash 4 and jq for every script; git worktree porcelain (`git worktree list --porcelain`); the Orca CLI (`repo list --json`, `orchestration inbox --full`, `task-list`); Claude Code session logs, one JSON row per line (types user, assistant, queue-operation, attachment)
- Library: none added; the paved road is the plugin's own `paths.sh` (`pp_open_ask`, `pp_seat_open_ask`), `read-verdict.sh --state`, `host-services.sh` and `decision.sh list`
- Host twin: #648 asks the host project's driver for the same check, under the host's own issue; nothing is ported from the host
- Style reference (#555): the Flightdeck mod (MIT) for layout ideas only; no code is copied, so NOTICE gains no line
- Owner decisions carried: the order and the owner's scope answer of 2026-11-04 (all 38; trials before removals)

## Data design

- Driver log (new, C2): `$PP_SCRATCH/scratchpad/<unit>-drive-<epoch>.log`, the epoch the service name's suffix; written by `unit-drive.sh run` (its stderr, copied with tee); read by board.sh, orca-wait.sh and close-done-panes.sh, which already look for that name; a new start writes a new file; a retry is a new start
- Re-send mark (C1): in the run's memory only (`SAID`, as `say_once` keeps); a driver restart may re-send once more
- Ledger rows (C1): unchanged on disk; `decision.sh` reads a row with keys beyond its set, and its writers carry those keys through unchanged (the answer branch appends the whole previous row with two fields set, decision.sh:288); no writer change
- Pane map (CD1, #576): `$PP_SCRATCH/pane-map.json`, the cached Orca terminal list; written by `pp_pane_map` (temp file and rename) when older than its TTL (default 20 s); read by the pane lookup sites, except those that read fresh (`PP_PANE_MAP_FRESH=1`: to-main's retry, unit-drive's live-Builder check, cos-tell's relay lookup); a lookup (`pp_seat_pane`, `pp_pane_of`) that finds no pane in the stored map reads Orca once more before it answers none, so a pane opened since the map was read is found (one fence for the class: a miss is never served from the map); a failed read writes nothing
- Serena home (CC2, #649): `$PP_SCRATCH/serena-home/<PP_PROJECT>-<cksum of PP_PROJECT_DIR>-<folder slug>-<path cksum>`, one per repository and unit; written by serena-shared.sh start; read by the Serena it starts; removed with the unit's other scratch
- Recovery once-file (CF2, #663): `$PP_SCRATCH/main-watch/recovered`, one row `<recovery> <unit-or-task> <condition-key>`; the row is written before the act, so each recovery acts once per unit per condition; a half row is ignored
- Driver args (CF2, #663 R4): `$PP_SCRATCH/drive-<unit>.args`, four lines (absolute author spec, judge spec, batch, the service name); written by `unit-drive.sh start` under its lock before the service starts, replaced on each start, removed by start's EXIT trap when the start is refused; the run's trap leaves it, so it outlives a crash; removed by the run when it ends DONE (pass 18: merged, or launched with no Builder record to watch), while a STOP keeps it for R4b; read by recover-stalls.sh R4 and R4b; a missing or short file means no restart, and R4 also skips a unit with a merged row at or after the start epoch in the service name
- Supervisor (CF3, #655): `$COS_KEY.cos-supervise.pid`, `$COS_KEY.cos-supervise.lock` (its flock, one supervisor per key) and `$COS_KEY.supervise.log`; written by cos-supervise.sh; read by the inbox waiter Stop hook; a dead pid is a missing supervisor
- Trial record (CG1, #584 #585 #586): `docs/orca-native-trial.json`, committed, starting `unrun` for each trial; written only by orca-native-trial.sh `record_result`; read by the removal gates and their tests; `send` is keyed by agent and host (`uname -s`, DG7), with its own `closed` entry (DG8); anything but an exact `pass` reads `unrun`; a trial run's scratch is `$PP_SCRATCH/native-trial/`
- Supervisor acknowledgement ledger (CF3, #655, pass 1): `$COS_KEY.supervise.acked`, one wake-file name per line; written only by cos-supervise.sh: the first start ever writes every wake file then present (old finds are not replayed: their writers woke the pane by their own exit), except the non-empty find of a hand-armed watcher this start stopped (its writer was killed before its exit could wake the pane), which it publishes then acks, after waiting up to 2 s for the stopped watchers to end (pass 14), and `deliver` appends a file's name after that file is typed (turn_started in the receipt, or accepted into the busy pane's queue: pass 4), held or dropped; a non-empty wake file is delivered when its watcher exits, whatever the exit status (pass 5: a watcher that dies after its find and its seen or told mark leaves that find only there); read by the next start's drain, which publishes, oldest first, each non-empty unacked relay wake file whose writer pid is dead (lane files skipped); never reset, only appended; a crash between the delivery and the append replays that one find once at the next start, and nothing is lost; deliveries are serialised under the ledger's flock, so two never interleave
- Lane poller state (CD3, #614, pass 1): `$COS_KEY.lane-<lane>.inbox-seq` (and its `.lock`), the same format as the relay's `inbox-seq` under a key of its own, so a lane never moves the relay's place; written by cos-watch-inbox.sh `save` (temp file and rename, under the flock). Redesign pass 2 (class lane-seed-loss), one fence: Orca's per-row read flag. On every poll, not only the first, a lane delivers (prints, or holds an FYI note) only a row that is sent to its own handle, not sent by itself, and unread in Orca (`.read` 0 or absent); a row Orca marks read is never delivered, wherever it sits against the place. The place only keeps a row from being delivered twice by two polls. One retry path, whatever the state's origin (a fresh lane, a deleted or emptied file, a stray `.new` never renamed): with no place, the poll re-derives the lane's mail from Orca, saves the place just before its oldest unread row to its handle (else at the newest row) and delivers every unread row to its handle above it. Orderings covered: unread only; unread then read (r2); read then unread (r1); unread, read, unread; none. Delivery is at least once: a row shown while still unread is shown once more after the place is lost, and a pending batch or held notes lost with the file come back the same way while unread; nothing unread is lost. `inbox-seen-ids` stays cos-check's handled count only, never a fence: removing it changes no delivery. The relay keeps its rule: no place starts at the newest row, and read rows count (main's own loop reads relay mail within seconds, so read is no fence there)
- Serena watchdog (CC2, #650): `${REC%.txt}.watch.pid` (the sweep loop's pid) and `${REC%.txt}.watch.log` (one line per child stopped over the cap: pid, command, worktree, size, cap); written by serena-shared.sh `watch` and `sweep`; the pid is read by `watch` (a live one is reused) and `stop` (killed only when its args name serena-shared.sh); a dead pid means the next start starts a new loop; `stop` removes the pid file; the log only grows
- Serena project folder (CC2, #649, DC7, pass 1): a template without `$projectFolderName` is copied into the per-unit home unchanged, so Serena reads the same folder, settings and memories as before and nothing is written; a `$projectFolderName` template's folder becomes `K-<folder name>` and the folder Serena used before (the filled template, else `$WT/.serena`) is copied there by `cp -R` once, only when the new one is absent; never removed by `stop` (it is outside the home); a half copy is kept and is not redone (known gap: delete the folder to copy again)
- Merged-row proof fields (CC3, #610 #656): `checkRun` (`green` or `none`) and `closingGo` (true or false) on the `merged` row of `$HOME/.commandeck/builds/<project>.jsonl`; written once by merge-unit-local.sh in the row's one append under the home folder's flock; read only by decision.sh push-ask's `auto_push_answer`; a row without them (older merges) reads as not green and not closing GO, so the ask stays manual; no rewrite, no retry: a lost append costs the list one build and the push stays a manual ask
- Seat record pane fields (CG3 #585, builder-fresh-round.sh): the record's `handle=` line is rewritten in place to the live pane and the old pane is appended as `prior_pane=<old>` (awk to `$REC.tmp`, then mv), also by `pp_follow_up` on a reopened closed seat; read by pp_open_ask/pp_task_close (prior panes' questions still hold the task) and the first-line readers; a stop before the mv leaves the old record and a stray `.tmp`; a rerun rewrites it again
- Restart holds (CF1, #615): one `restart: HELD: cp=<cp|none> session=<sid> cwd=<dir>: <why>` line appended to `$HOME/.claude/checkpoints/clear-hook.log` by context-clear-stop.sh per held restart; read by dashboard_limit.py as `restartHeld`, one per session, until a later `restart: new pane ... resumed from <cp>.md` names its cp or a later hold replaces it; a `cp=none` hold expires after 30 min; a log line cut mid-way does not match and is skipped
- Units pane atoms (CH4, #555): `unitsExpanded` and `unitsFocus`, plugin atoms in memory (hooks/units.tsx, typed in types/index.d.ts); written by the pane's keys, read by its views; reset to null when Claude Code restarts; no file is written (the test "views write no file" pins it)
- Gate heading and record readers (class class-miss, passes 5, 6 and 7; main answers answer-1793896004-21509 and answer-1793897396-35438): no state; each read starts from the file or the command output, so the one retry path is the next read (the driver's next start, the merge or pass run again, the next hook call), whatever was removed in between (the driver's ASKED file, its `drive-<unit>.qsec` scratch, its done file; COMMANDECK_RUN, the run file). One rule in fence.sh for every heading a gate opens a section on: `hletters(title)` keeps only the text CommonMark displays, by one fixed drop list, not one case per syntax found: it drops link and image destinations and titles (`](...)`), full reference labels (`][...]`), footnote marks (`[^...]`), raw HTML and autolink brackets (every `<...>` run) and named entities (`&name;`), and decodes numeric references (`&#NN;`, `&#xHH;`) to their ASCII character; emphasis, code spans and backslash escapes display their own text, so dropping every non-letter after that list and lowercasing gives the visible letters (`## [Cuts](#cuts)` gives `cuts`, `## [Cuts][c]` gives `cuts`, `## &#81;uestion for the owner` gives `questionfortheowner`). Rejected: refusing any marked-up heading whose letters contain a key (the `plan` key alone hits 57 headings in today's plans and briefs); `hgate(accept, key, how)` after `heading()` returns 1 when the title is accepted as written, 2 (the reader refuses, naming `<file>:<line>` and the heading) when it is not accepted but its letters match the key, else 0. The keys: the question gate (unit-drive.sh QSEC), accepted `Question for the owner` exactly, key: letters contain both `question` and `owner`, any depth; `Cuts` (merge-unit-local.sh cut_scan), `Post-merge` (merge-unit-local.sh, letters start `postmerge`), `Close as shipped` (merge-unit-local.sh close list, letters contain `closeasshipped`), `Steps` (paths.sh pp_plan_stale), `Plan` (paths.sh pp_plan_section_paths, accepted `Plan`, `Plan: ...`, `Plan <words>` as today, key letters `plan`), `Data design` (builder-codex-pass.sh table_gate, accepted any case as today, key letters start `datadesign`): letters equal the one word unless named; containment is used only where no real section shares the letters (`## Template cuts` is a real section, so Cuts is equality). The Break line reader (builder-codex-pass.sh break gate) refuses a margin line `break:` in any other case than `Break: `. The run-current record: `pp_run_id_of` reads only `result.run` null (no run, 0), `result.run` an object whose `id` is a non-empty string (the id, 0), or the concise `runId` form (4); any other `run` value is said on stderr, status 5; no output at all stays 1. pp_is_main_pane keeps pp_orca_run_id's status (no `$(...)` that drops it) and answers 2 (unknown) on status 4 or 5, never 0 (context-line.sh's advice then names an unreadable run-current answer, not Orca's run list); status 1 (Orca gives no output, and no COMMANDECK_RUN or run file) stays 0, main (main's ruling, pass 7: main-only behaviour is not withheld while Orca is down). Refusals reach the act through the refusal stamp (pass 8, main answer-1793898818-92350; it replaces pass 7's status chain, which every pass found one more caller of): every gate reader runs its awk through fence.sh `pp_gate_awk`, which writes each hgate refusal, and any awk failure of a gate read (an unreadable file, a fatal error), as one `<file>:<line>: <why>` line to `$PP_GATE_STAMP` and to stderr, whatever its caller then does with the status or the output (a pipe stage, `< <(...)`, `|| true`, an unchecked `$(...)`, `|| continue`, a function ending `return 0`); each entry point checks the stamp with `pp_gate_check` before each act it cannot take back (see Gate refusal stamp). The gate readers: unit-drive.sh QSEC and preflight's Plan read, merge-unit-local.sh cut_scan, the Close as shipped list, the Screenshots, Files deleted and both Post-merge reads, paths.sh pp_plan_section_paths (and so pp_brief_plans) and pp_plan_stale, builder-codex-pass.sh evidence_section, table_gate and the Break line read. Fenced lines never open, close or feed a section (merge-unit-local.sh close list: a fenced `## Close as shipped` line is an example and adds no issue). Known gaps: plan-check.sh (unchanged on this branch) still reads `## Decisions`, `## Steps` and `## Facts` by raw regex, reported to main; a pane in a run with no COMMANDECK_RUN and no run file reads as main while Orca gives no output (main's ruling, pass 7)
- Gate refusal stamp (class class-miss, pass 8; main answer-1793898818-92350): one file per entry-point run, `mktemp "$PP_SCRATCH/gate-stamp.XXXXXX"`, exported as `PP_GATE_STAMP`; created empty at the start of merge-unit-local.sh, builder-launch.sh, unit-drive.sh (start and run) and builder-codex-pass.sh, always a fresh one (an inherited `PP_GATE_STAMP` from a parent entry point is replaced, so a child never acts on, or stops for, its parent's reads); written only by `pp_gate_awk` (append, one line per refusal); read only by `pp_gate_check`, which refuses naming every line when the file is non-empty, and refuses as well when the file is missing (made at the start, so a missing stamp is lost state, never a clean read). The check sits on the acts, not at chosen points (pass 9, main answer-1793899716-75840): every act an entry point cannot take back runs only through fence.sh `pp_gate_act <cmd...>`, which runs `pp_gate_check` immediately before the command and refuses instead of running it; so a gate read made at any time before an act is checked at that act, and a fresh read after an earlier act is checked at the next one. The fixed act list, per entry point: builder-launch.sh: the plan copy and commit onto main (:253-254), the adoption or worktree create (:399-429), the batch rewrite (:424), the worktree reset (:426), worktree-setup.sh (:430), the worktree settings, brief, evidence and brief commit (:446-458), main's brief copies and review-base file (:460-469), `seat.sh launch` (:309), the planner worktree close (:314); merge-unit-local.sh: `git merge --squash` (:753), the briefs tar append (:822), the squash commit (:842), each `gh issue close` (:472), each post-merge step start (:893 loop), cut_step's plan-mark commit (:614) and next-cut task (:622), cleanup_step (:950, its worktree remove at :205 included); unit-drive.sh: preflight's batch append (:67), the revise spec write and its plan-author seat, each `seat.sh launch` (:288), the builder-launch.sh call; builder-codex-pass.sh: the real staging (:1613), its commit (:1895), the reviewer launch (:2276), the hand-off mv (:2541) and the GO and fix-round fresh-round dispatches (:2477, :2571: each starts a background child, so it is checked by `pp_gate_check` in the foreground immediately before the `&` and not again in the child, whose check would race the pass's EXIT removal of the stamp, pass 13; the reviewer launch's background `pp_gate_act` stays, as the pass waits for it before its EXIT), with refusals_flush (:86) still the first check. Not on the list, each by its reason: pp_sync_main (a fast-forward of main to origin: no unit content, and any later run does the same), locks (released at exit), scratch, log and record files under `$PP_SCRATCH` or `.git` (no other reader acts on them), and the refusal's own reports (to-main and relay sends, the driver's STOP line, the merge's fail line: they say the refusal). Reads first: merge-unit-local.sh reads the Close as shipped list and the Post-merge step list in step 1, with the other step 1 reads, into variables; close_issues and the post-merge loop consume those (pass 9: today the close list is first read at :864, after the squash commit), so a refused heading stops the merge before the squash. A reader run with no `PP_GATE_STAMP` (a caller outside these four) writes no file and returns 2 on a refusal, as today. Removed by the entry point at its normal end; a crash leaves a stray file that no later run reads (each run reads only the file it made). Retry: the next run makes a new empty stamp and reads the plan, brief, batch and evidence again, whatever was removed in between
- No other state is added or changed

## Already fixed

- #631: fixed in 4530f6f; `seat.sh collect` settles a seat whose report holds its verdict with `PP_VERDICT_READ=1`; main closes it citing that commit

## Issue table

| Issue | Part | Plugin files | Fix | Test |
|---|---|---|---|---|
| #657 | 1 (C1) | unit-drive.sh, seat.sh | a lone none closes the section; a question with no decision is re-sent once with a NEEDS-MAIN line; the spec names `None: <reason>` | qopen list none closed |
| #662 | 1 (C1) | decision.sh, unit-drive.test.sh | the ledger reader takes rows with extra keys; the plan tag rule stays (D1) | host row with unit field and tag releases |
| #648 | 1 (C2) | unit-drive.sh | start refuses a name a worktree of another Orca repo uses | same name in another project refuses |
| #659 | 1 (C2) | unit-drive.sh, orca-wait.sh | the driver logs to the name its readers use, ends DONE, stops on a Builder whose turn never started | unproven Builder launch stops at launch |
| #658 | 1 (C3) | answer-worker.sh, board.sh | a tag counts only in a user row; an idle Builder on an open question shows as stopped | queued-row tag is not delivered |
| #637 | CB1 | scripts/paths.sh | a turn-complete note is no open question | turn-complete question settles a finished seat |
| #647 | CB1 | scripts/seat.sh, scripts/orca-wait.sh, scripts/dashboard.sh, scripts/board.sh | bold `(P2)` findings counted and shown | collect summary shows bold P2 finding |
| #660 | CB2 | scripts/json-clean.sh, scripts/paths.sh, scripts/orca-wait.sh, scripts/read-verdict.sh | lone surrogate cleaned before jq; cause checked live | verdict read through a lone surrogate |
| #636 | CB1 | scripts/paths.sh, scripts/seat.sh | refusal line split; live check picks restore or keep-off | working pane refusal names the pane |
| #646 | CC1 | scripts/answer-worker.sh | unit open in two projects: use the asking project's pane or refuse naming both | same unit in two projects refuses naming both |
| #649 | CC2 | scripts/serena-shared.sh | own Serena home per repository and unit | same-named folders in two repos get distinct homes |
| #650 | CC2 | scripts/serena-shared.sh | sweep stops a child over 2 GB and logs it | child above cap is stopped and logged |
| #652 | CC2 | scripts/__tests__/serena-shared.test.sh | skip names the cases; real run is a Builder check | skipped cases are named without Serena |
| #610 | CC3 | scripts/decision.sh, scripts/merge-unit-local.sh | yes only on recorded GO and green on exact tip | push ask with GO and green is answered yes |
| #656 | CC3 | scripts/decision.sh | a clean push gets no open ask | push ask with GO and green is answered yes |
| #638 | CD1 | scripts/paths.sh, scripts/to-main.sh | pane lookup adds the run's coordinator; exit 3 kept for no pane | main pane found as run coordinator |
| #576 | CD1, CD3 | scripts/paths.sh, scripts/to-main.sh, hooks/__tests__/cos-inbox-waiter-stop.test.sh | stored pane map with a 20 s freshness; two wakes re-arm without a turn | pane map read once for two lookups |
| #639 | CD2 | scripts/ask-main.sh | wait also finds the reply by thread id in the full view | reply marked read by another reader still arrives |
| #641 | CD2 | scripts/paths.sh, scripts/orca-wait.sh | a QUESTION body always wakes and is never hidden | reply with QUESTION body wakes main |
| #614 | CD3 | hooks/cos-inbox-arm-stop.sh, scripts/cos-watch-inbox.sh, scripts/cos-check.sh | lane poller, routine notes held, fault in the watcher line | Fast lane stop arms its own poller |
| #633 | CD3 | hooks/duplicate-agent-guard.sh | split into a lane is checked; replace only by naming the live idle pane | split beside a live agent is blocked |
| #588 | CD4 | hooks/lib/project.sh, scripts/{orca-wait,board,run-bound,setup,unit-close,close-done-panes,dashboard,poll-agents,main-watch}.sh | run-current read with --full; concise form fails loudly; fixtures per parser | run-current concise form fails loudly |
| #640 | CE1 | fence.sh, paths.sh, builder-codex-pass.sh, merge-unit-local.sh, seat.sh, merge-rules.py | one fail-closed heading reader, 12 sites moved onto it | indented heading ends a section |
| #640 | CE2 | unit-drive.sh | question and Plan readers use it | setext Question heading opens the gate |
| #654 | CE3 | brief-template.test.sh, docs, templates, scripts | rg check; leftovers fixed; one rule pinned | template docs and script state one pass rule |
| #653 | CE3 | templates/_builder-brief-template.md, merge-unit-local.sh, tripwire hook | 14 sections cut, each with its refusal proof; pinning checks edited | cut sections leave a pointer naming the refusing script |
| #651 | CE4 | unit-drive.sh | watch stage to merge, attach on a live Builder | live Builder is attached, never relaunched |
| #655 | CF3 | scripts/cos-supervise.sh, hooks/cos-inbox-waiter-stop.sh | one supervisor restarts dead watchers and wakes for exceptions only | dead watcher is restarted and logged |
| #663 | CF2 | scripts/recover-stalls.sh, main-watch.sh, answer-worker.sh, close-done-panes.sh | six recoveries, once per unit per condition, one line each | ready task with live pane is dispatched once |
| #615 | CF1 | hooks/context-clear-stop.sh, scripts/dashboard_limit.py | a held restart logs and raises why; test past the line | session past the line restarts |
| #591 | CF2 | scripts/helper-apply.sh, templates/_builder-brief-template.md | child worktree removed with its applied diff | applied helper worktree is removed |
| #608 | CF4 | scripts/context-rank.sh | rank context cost of both panes, remove what it names | tool result bytes are ranked by tool key |
| #584 | CG1 CG2 | scripts/orca-native-trial.sh, docs/orca-native-trial.json, hooks/cos-inbox-arm-stop.sh, scripts/cos-supervise.sh, scripts/await-agents.sh, scripts/watch-agents.sh | trial the native wake, then retire the relay re-arm and the wait scripts; the poller stays as the filter under the supervisor | wake record gates wait-loop removal |
| #585 | CG1 CG3 | scripts/orca-native-trial.sh, scripts/paths.sh, scripts/answer-worker.sh, scripts/main-watch.sh, scripts/seat.sh, scripts/builder-fresh-round.sh | trial follow-ups to finished and closed workers, then send by orchestration send | send record gates terminal-send removal |
| #586 | CG1 CG3 | scripts/orca-native-trial.sh, scripts/main-watch.sh, scripts/answer-worker.sh | trial a wake typed into a busy pane, then drop the unsent-wake text; the dashboard outbox stays | submit record gates wake-text removal |
| #555 | CH2 CH3 CH4 | hooks/units-elements.ts, units-sources.ts, units.tsx, scripts/dashboard.sh, types/index.d.ts, docs/dashboard.md | every element from live data or a named placeholder; band and status line redesign; layouts; keys | header counts, cost, limit at both widths |
| #621 | CH1 | scripts/dashboard.sh, hooks/units.tsx | a re-planned built unit reads Planning in the dashboard and the mod | a built unit whose plan judge said NO-GO shows planning |
| #645 | CH1 | hooks/units.tsx, hooks/units-world.ts | `pane on` always opens and the reply says placed or why not | pane on reopens an unplaced pane |

## Cuts

### C1 (#657 #662) the question gate -- est. 100 lines

- `qopen` (unit-drive.sh:174-181): a section whose only non-blank line is `none`, `None`, `none.` or `None.`, list marker optional, is closed; `None: <reason>` stays closed; a quoted none or one with trailing words stays open (D3)
- `question_gate`: after one poll that finds no `plan-<unit>` row in this ledger, the question is sent again once and one line `NEEDS-MAIN: <unit> asked main plan-<unit> at <time> and no decision exists; record it with decision.sh add plan-<unit>` goes to the driver's log; a to-main.sh exit 3 (queued) logs the same line at once (D4)
- `fold` (decision.sh:52-59): a row needs the seven keys and may carry more; a row missing one still makes the ledger malformed (D1)
- seat.sh:614: the plan-author spec adds `With no question, the section is one line: None: <reason>.`
- Produces: the NEEDS-MAIN log line; a ledger read that accepts host rows
- Consumes: `decision.sh list`, to-main.sh's exit codes (to-main.sh:9)
- Consumers of the changed reader: unit-drive.sh, relay-order.sh, dashboard.sh, cos-watch-decisions.sh, builder-codex-pass.sh, state-snapshot.sh, answer-worker.sh, hooks/ask-records-decision.sh, hooks/agent-awareness.sh; none writes extra keys, so their own ledgers read as before

### C2 (#648 #659) driver start, log and Builder launch -- est. 120 lines

- `preflight` in start: for each repo `orca-ide repo list --json` names other than this one (the reader at unit-drive.sh:236), `git -C <repo> worktree list --porcelain`; a worktree whose folder name is the unit refuses with exit 2 before the owner file, a worktree or a seat: `REFUSED: <unit>: <path> in another project already uses this name; pick another unit name`; an unreadable list prints one warning and the start goes on (D2)
- `run`: stderr is copied into `$PP_SCRATCH/scratchpad/<unit>-drive-<epoch>.log` (D6); `stop()` also logs its whole `STOP unit=... next: ...` line; the clean end logs `DONE unit=<unit> stage=launch: Builder launched`
- After builder-launch.sh returns (a seat launch returns before its pane is typed into and the record's pid runs the rest, unit-drive.sh:204, builder-launch.sh:303): a 60 s deadline from that return, as the issue asks ("working or flagged within a minute"). The driver polls every 5 s for a started turn: `read-verdict.sh --state` on the Builder worktree (C3's source) reads a session that started after the record's `launched=` (the session-log proof seat.sh:774-778 uses; `phase` alone is only launching, dispatched or failed, seat.sh:7-8). Started inside 60 s: the clean DONE end; CE4 later replaces it with `watch_unit`. Not started at 60 s, whatever the launch pid is doing (the tui-idle wait alone may take 120 s, seat.sh:724): one line `FLAG: <unit> Builder pane <h> has no started turn 60 s after launch (task <t>, phase <p>)` goes to the driver log and to main (to-main.sh) once, inside the minute. Then the driver keeps waiting for the launch pid to end: a turn that starts later reaches the same clean end; a `phase=failed` record or an `UNPROVEN SUBMISSION` line in its `.log` stops at launch: `the Builder pane <h> opened but no turn started (task <t>)`, next `bash scripts/dispatch-task.sh <t> terminal:<h>, then read the pane` (D5). The 60 s is a fixed constant (no setting); a new `now` helper reads `COMMANDECK_NOW` when set, as cos-watch-inbox.sh:106 does (a test seam, not documented), so the test runs without waiting a minute
- orca-wait.sh:446: a route follows `next=` or `next: `
- Produces: the driver log, its DONE and STOP lines, the start refusal
- Consumes: the Builder seat record (handle, task, pid, phase) and its `.log` (seat.sh:663-664, seat.sh:774-803)
- Consumers of the log name: board.sh:148, board.sh:332, orca-wait.sh:189, orca-wait.sh:434, close-done-panes.sh:69, close-done-panes.sh:135

### C3 (#658) answers to a Builder that ended its turn -- est. 80 lines

- answer-worker.sh:337: delivered needs the tag in a prompt row of a turn started at or after the send (D7): Claude, the prompt shape read-verdict.sh:132-133, never a tool result (:133) other than its own waiting call's (D7, pass 19); Codex, a user `response_item` (:112) with a `task_started` (:103) after the send. Any other row is not delivered, so the check goes on and types the answer once `idle` reads true (D7). One jq filter per `KIND`, run on the lines `grep -F "$TAG"` finds, so the large-log cost stays one grep
- The turn-start observation is produced here: `read-verdict.sh --state` today prints `prompted=` but no turn start, and its `result` (read-verdict.sh:87-94) drops `.start`. C3 keeps `start: .start` in the running and complete objects of `result` and adds `"start=\(.start // "")"` to the printed list (:342). What `.start` is: Codex, the newest `event_msg` `task_started` row (:103-104), the separate row Codex writes; Claude, the newest user text row (:127-131), the same row that holds a typed prompt, so for Claude the tagged prompt row dated at or after the send is itself the turn start. Delivered (D7): Claude, a prompt-shape row holding the tag with its timestamp at or after the send; Codex, a user `response_item` holding the tag and `start=` at or after the send. Every other `--state` reader (main-watch.sh:341, :756, :1188, :1280, answer-worker.sh:157-158) greps its own `^key=` line, so one more line changes none
- board.sh: a Builder seat Orca reads as working, with an open question (`pp_seat_open_ask`) and a session log idle 5 min or more (`read-verdict.sh --state`, idle_seconds), is listed under panes that have stopped: `<unit> builder: idle <n>m on open question <id>` (D8)
- Produces: the stricter delivered line; the board row; the `start=` line of `read-verdict.sh --state`
- Consumes: the session log rows; `pp_seat_open_ask` (paths.sh:659-677)
- Consumers of the new `start=` line: answer-worker.sh (this cut) and CF2 R2; the other `--state` readers ignore it
- Consumers of answer-worker's exit: decision.sh deliver_answer (decision.sh:64-82), main's foreground follower; exit codes unchanged

### CB1 (#637 #647 #636) open-question check, finding readers, refusal split -- est. 130 lines
- `pp_open_ask` (scripts/paths.sh:659-675): the jq filter skips a `question` whose subject holds "turn complete" unless it reads "turn complete: QUESTION" or "turn complete: BLOCKED"; the same rule orca-wait.sh already applies (:262 `noisy`, :341). A Codex judge's final text posted as a question then no longer holds collect's settle (rc 4)
- `pp_task_close` (scripts/paths.sh:711-717): the one refusal line "its pane is working or could not be read (pane state, a dispatch or inbox)" becomes two: pane busy or unreadable names the pane; an unread dispatch or inbox names the open-question check as unread, with the rerun hint. The open-question line (:713) is unchanged
- `seat.sh collect` summary (scripts/seat.sh:850) and `enrich` in scripts/orca-wait.sh:185: the grep pattern gains the bold form `**F2 (P2):` (`^(- )?(\*\*)?[A-Za-z0-9.-]+ \(P[0-3]\)`) beside the bracket forms
- `builder_progress` (scripts/dashboard.sh:269) and the same count in scripts/board.sh:179 (a fourth bracket-only reader; same defect, fixed here): the counting grep gains `^[[:space:]]*([-*] )?\*\*[A-Za-z0-9.-]+ \(P[0-3]\)`, cut to `P[0-3]` by the existing second grep
- #636: after the split, a Builder check decides the restore (below). Restore shape: `settle_seat` (scripts/seat.sh:906-914) calls `pp_task_close` without `PP_VERDICT_READ=1` until `SETTLE_END` (:915) and with it only for the last try, so a finished pane that still reads working is waited for, never refused for good, and the open-question check holds throughout. Keep-off: a comment above `settle_seat` with the written reason
- Produces: `pp_open_ask` return 1 for a lone turn-complete note; two refusal texts; bold-form findings in collect summary, wake summary, dashboard counts and board counts
- Consumes: `pp_seat_open_ask` (paths.sh:680-690) unchanged; `pane_is_busy` (scripts/codex-helpers.sh:161-169) unchanged
- Consumers of a changed contract: `pp_open_ask` is called only by `pp_seat_open_ask` (paths.sh:689); that is called by `pp_task_close` (paths.sh:711) and answer-worker.sh:116 (rg 'pp_open_ask|pp_seat_open_ask'); answer-worker.sh then also finds no "question" to reply to for a turn-complete note, which is right (it asks nothing). The refusal text at paths.sh:716 is matched by no test or script (rg 'working or could not be read' finds paths.sh:716 alone). `unit-drive.sh:217` maps collect rc 4 to "verdict read, task not settled" and is unchanged

### CB2 (#660) lone surrogate in seat and inbox JSON -- est. 115 lines
- New `pp_json_clean [file]` in new scripts/json-clean.sh (sourced like fence.sh: by paths.sh at :1563, and atop read-verdict.sh, whose `--state` dispatch at :418 precedes paths.sh at :588): stdin (or the file) to stdout with each lone `\uD800-\uDFFF` escape turned into `�`; a valid pair and an escaped backslash (`\\ud83d`) are kept. Perl is the tool (macOS and Linux ship it; hooks/edit-content-tripwires.sh:359 already uses it). With a file argument it runs `grep -qiE '\\u[dD][89a-f]'` first and plain `cat`s a file with no such escape, so a large session log costs one grep
- Apply it at the reads that jq parses: `pp_open_ask` inbox read (paths.sh:661) before the jq at :662; scripts/orca-wait.sh `out=$(orca-ide ... --json)` at :531 and :533 (the drained check output every later `jq` parses); scripts/read-verdict.sh `fetch` (:469, between `orca-ide terminal read` and `jq`), and `codex_report` / `claude_report` (:633, :670) through the file form; read-verdict.sh `session_state` (:168-172, `--state` and :853) reads `pp_json_clean "$2" | jq`: one bad row now sets `.bad` (:129-131), pinning `state=unknown`
- jq 1.8.2's parse error on one: Assumptions; cleaned, `x` U+FFFD `y` parses
- Produces: a jq-safe copy of what the readers take; a verdict line and `--state` read past a lone surrogate
- Consumes: paths.sh (orca-wait.sh:57) sources json-clean.sh; read-verdict.sh sources it before :418; C3's `start=` line
- Consumers of a changed contract: no existing function changes its arguments; all `jq` calls on the cleaned streams keep their filters. `read-verdict.sh` is run by seat.sh, orca-wait.sh `enrich` (:185), close-round.sh and main-watch.sh (`--state`: main-watch.sh:341, :756, :1188, :1280); they read stdout; `--state` keys stay

### CC1 (#646) same unit name in two projects: resolve in the asking project or refuse naming both -- est. 60 lines, after C2
- Order: after C2 (#648's start refusal stops new same-named units; CC1 handles the ones already open).
- scripts/answer-worker.sh unit branch (:85-92): after `pp_seat_pane` and `plan_seat_pane` find no pane in this project's `$PP_WORKSPACES/<unit>`, list `orca-ide terminal list --json` panes whose worktree folder is named `<unit>` under another workspaces root. If any: print `answer-worker: unit <unit> is open in two projects: <this root>/<unit> (no live pane) and <other path>; nothing sent or queued. Send to the right one by handle: bash answer-worker.sh <handle> '<text>'` and exit 1. With none: the queue path stays as it is. A live pane found in this project still wins: the answer is resolved in the project that asked (the ledger and `$PP_WORKSPACES` are that project's).
- scripts/decision.sh deliver_answer (:67-82): no code change; an exit 1 with that line is already `not delivered: <id> to <unit>: <last line>` (:81), so the owner's answer names both candidates in the ledger line and relay-order.sh prints it from decision.sh's stderr (relay-order.sh:77-78). Test only.
- Produces: the two-candidate refusal line.
- Consumes: Orca terminal list (the `wtp` path reader, scripts/project-main.sh:57), `PP_WORKSPACES`.
- Consumers of a changed contract: answer-worker.sh exit codes unchanged (1 for not delivered); callers decision.sh:67 deliver_answer, relay-order.sh via decision.sh answer, main-watch follower, ask-main.sh.

### CC2 (#649 #650 #652) Serena home per repository and unit, memory watchdog, loud skip -- est. 150 lines
- #649 lever: Serena keys its project registry and (for a `$projectFolderName` template) its `.serena` folder by the folder name; the home that holds the registry is `SERENA_HOME`. scripts/serena-shared.sh `start` (:88-117) first sets its own project names: it sources `$HERE/../hooks/lib/project.sh` and calls `pp_project "$WT"`, which sets `PP_PROJECT` (the primary checkout's basename) and `PP_PROJECT_DIR` (its full path) for the worktree's own repository (hooks/lib/project.sh:7-20); serena-shared.sh sources only paths.sh today (:34), which defines neither, and no caller exports them, so nothing is inherited and `set -u` (:30) never meets an unset name. K = `<PP_PROJECT>-<cksum of PP_PROJECT_DIR>`: the basename for reading, the path checksum so `/a/app` and `/b/app` differ. Before launching, build `$PP_SCRATCH/serena-home/K-<pp_slug of folder name>-<cksum of WT>` (H) from the source home S: `$SERENA_HOME` when the user set it, else `~/.serena`. H holds a copy of S's `serena_config.yml` with `project_serena_folder_location` set to the literal project folder P below, and symlinks to S's `language_servers`, `prompt_templates`, `contexts`, `modes`, `memories` folders (so nothing is downloaded twice); launch with `SERENA_HOME=H` in the env of the existing `(cd "$WT" && exec nohup ...)` line (:103). A user-set `SERENA_HOME` is thus the source, never a bypass: two same-named worktrees in two repositories get two homes in every case. P (DC7) is the folder Serena resolves today, outside H, so it outlives stop and restart; H holds only the registry config and symlinks, never written into the worktree. With no config file in S at all: H gets no config copy and the launch is as today (Serena's default `$projectDir/.serena` is per worktree already). Two same-named folders in different repositories then have separate registries and separate `project.yml` files (each with its own `language_servers`).
- #650: new function `sweep` and a `sweep <worktree>` command (added to the command list at :31 and the `case` at :120). One pass: `ps -axo pid=,ppid=,rss=,args=`, the descendants of the recorded server pid, each direct child's subtree RSS summed (kB); a child above 2048 MB (a fixed constant, the issue's 2 GB) is killed (TERM, then KILL after 2 s) with its subtree, and one line is appended to `${REC%.txt}.watch.log`: `<utc> killed pid=<p> cmd=<first 60 chars> worktree=<WT> rss_mb=<n> cap_mb=2048`. The watch loop `while kill -0 <server pid>; do sleep 30; sweep; done` (30 s fixed) starts as soon as the server pid is recorded (:106), before the answer wait at :112, so a language-server child that grows during initialization and keeps the server from answering is swept too; its pid goes to `${REC%.txt}.watch.pid`; it ends with the server. Adoption: the early return at :89 (a running, answering server) first starts a watch loop when `.watch.pid` names no live loop, so a server started before this change, or whose loop died, gets one. A server pid that is not ours (`running` false) is never swept.
- #652: in scripts/__tests__/serena-shared.test.sh the `else` at :215-217 prints one `SKIPPED (no Serena python): <case names>` line naming the six bridge cases (:196-213) and repeats it after the `passed, failed` line at :227; nothing else about the exit code changes (a machine without Serena still exits 0, the skipped names are on screen and in the last line). The real-Serena run is the Builder check below.
- Produces: the Serena home folder per repository+unit; `serena-shared.sh sweep`; the watch log; the SKIPPED line.
- Consumes: `pp_project` (hooks/lib/project.sh:7-20, called by `start` on `$WT`) for `PP_PROJECT` and `PP_PROJECT_DIR`, `pp_slug` (scripts/paths.sh:21), `PP_SCRATCH`, the server pid in the record (`$REC`).
- Consumers of a changed contract: seat.sh:533, builder-codex-pass.sh:2162 (start, seat-args: unchanged output), plan-worktree-close.sh:165, merge-unit-local.sh:203, unit-close.sh:115, builder-codex-pass.sh:2116 (the `stop` command removes H; P is kept).
- Assumptions settled here: Serena 2.1.0 is on this machine; see ASSUMPTIONS.

### CC3 (#610 #656) a push ask is answered yes by script only on a recorded closing GO and green checks for the exact tip -- est. 130 lines, after rules-port
- Order: after rules-port (it edits scripts/merge-unit-local.sh comments at :373-377, :408-409, :544; CC3 edits only the row write at :899-902 and the `CHECKED` lines, so the two touch different lines, but the Builder rebases onto its result).
- scripts/merge-unit-local.sh row write (:899-902): add two fields to the `merged` row: `checkRun` (`green` when `CHECKED` starts `check green` or `check reused`, else `none`) and `closingGo`. The name is `checkRun`, not `check`: push-ask reads `check` with `// "green"` (decision.sh:359) and refuses any value but green (:361), so writing `check: "none"` would turn today's manual ask for a merge with no testCommand into a refusal. `closingGo` is true only when the merge's verified `BUILDER_PROOF` (set by `prove()` :398-401, before the write) names `rule: closing GO`, read as :916 reads it; `first-pass GO`, `no closing pass` (a narrowed GO, builder-codex-pass.sh:971), `cap stop` and `threshold stop` write false (DC6). No round file is read for it. Those are facts the merge already proved before it commits; the row stays one line, appended once.
- scripts/decision.sh push-ask (:345-364): the existing refusals stay as they are and still read `check`. After them, and instead of `exec bash "${0}" add ...` at :363, run `add` (the manual ask, written in every case that passes the refusals), then call a new function `auto_push_answer <id>`. It answers yes only when all hold: the file `<main>/.claude/metrics/autodecide.on` names a log (auto-answer mode on, same switch as relay-order.sh:47); every listed commit has a `merged` row of this main with `closingGo == true` and `checkRun == "green"`; the newest listed row's `sha` equals `refs/heads/main` (the exact tip being pushed); no commit subject in the range names production (`prod`, `production`, `deploy`, whole word, any case). Then: `COMMANDECK_MAIN_TOLD=1 decision.sh answer <id> "yes: closing GO and green checks on <tip8> (auto-decided)"` (the ending relay-order.sh:84-85 reverses on the owner's word), then one `to-main.sh question "answer <id>" "Auto-answered <id>: <answer>"` from any cwd (DC7), exit 0 or 3 told, else a `not delivered: <id> to main` line; main pushes, the script never does; and an entry appended to the autodecide log in the relay-order.sh:55-61 shape (Question, Picked, Why, Reversible). No model turn is involved. Any condition failing (including `checkRun: "none"` or a row with no `checkRun`): nothing else happens, the ask stays open for the owner (the row `add` wrote), so a failed automatic gate always leaves the manual ask #610 keeps.
- Why #656 closes (D4): a push passing every gate "needs no ask": its row is written and closed in one call, the owner sees a log line; one failing any gate keeps the open ask, as #656 asks. The gates are #610's (closing GO, green fast checks, exact tip).
- Produces: the two row fields; `auto_push_answer`; the auto-answer log entry.
- Consumes: the finished-builds rows (`$HOME/.commandeck/builds/$PP_PROJECT.jsonl`), `refs/heads/main`, `<main>/.claude/metrics/autodecide.on`.
- Consumers of a changed contract: rows are read by decision.sh:354-357 (push-ask), the dashboard finished-builds list, uninstall (rewrites the file); added fields change none of their reads. main-watch.sh:1155 `push_ask` ignores the output (`>/dev/null 2>&1 || true`): unchanged. Rows written before this change have neither field: they never auto-answer (the ask stays manual), which is the safe side.

### CD1 (#638 #576) find main's pane the way the watcher does; one stored pane map -- est. 90 lines
- scripts/paths.sh `pp_seat_pane` (1077-1087): for key `main`, after the handle file and the folder lookup (`pp_pane_of`) find nothing, take the bound run's coordinator pane: run id from `$PP_RUN_FILE`, `pp_run_coord` (paths.sh:487-490), kept only if that handle is live in the pane map. Same source main-watch uses (`resolve_main`, main-watch.sh:546-554). Order stays: recorded handle, then folder, then coordinator.
- scripts/paths.sh new `pp_pane_map` (next to `pp_pane_of`, paths.sh:1061): prints the cached `orca-ide terminal list --json` from `$PP_SCRATCH/pane-map.json` when the file is under 20 seconds old (a fixed constant; the test ages the file with `touch -t`), else reads Orca once (`timeout 10`), writes the file by temp file and rename, prints it. A failed read prints nothing, returns 1, and keeps no file (never a stale map). `PP_PANE_MAP_FRESH=1` skips the cache.
- `pp_pane_of` (1061-1067) and `pp_seat_pane` (1079-1083) read `pp_pane_map` instead of calling `terminal list` themselves: the lookup sites for the stored map. Other `terminal list` callers (pane_state_read, close paths) stay live reads: they decide on state, not on handle.
- scripts/to-main.sh:50: the second look after `terminal_not_found` runs with `PP_PANE_MAP_FRESH=1`, so a pane closed inside the cache window is not looked up again from the map.
- scripts/ask-main.sh is not changed here: its send goes through to-main.sh (ask-main.sh:30), and the no-pane exit stays 3 with the queued line (ask-main.sh:34), see Q5.
- Produces: `pp_pane_map`, `$PP_SCRATCH/pane-map.json`, a third main lookup
- Consumes: `pp_run_coord`, `$PP_RUN_FILE`, `orca-ide terminal list --json`
- Consumers of a changed contract: `pp_seat_pane` callers to-main.sh:39,50, paths.sh:476,497 (`pp_sender`), scripts/cos-tell.sh, scripts/answer-worker.sh; `pp_pane_of` callers paths.sh:1084, scripts/cos-tell.sh, scripts/seat.sh, scripts/dashboard.sh (rg `pp_pane_of|pp_seat_pane` over scripts hooks, 20 hits; the Builder lists them again before the edit)

### CD2 (#639 #641) a reply is never lost to a second reader; a question always wakes main -- est. 80 lines
- scripts/ask-main.sh: the full-view read at 25-27 becomes a function `from_full` (same `check --terminal H --all --full --json`, matches `thread_id == $ID`); `--resume` still calls it first; the wait loop also calls it after each pass that finds no reply (after line 94) and once after the loop ends (before line 96). A reply that another reader on this pane took and marked read is found by its `thread_id`, not by the unread flag. One extra read per empty slice, at most 3 per question (slices of 240 s, ask-main.sh:53).
- scripts/paths.sh `PP_JQ_WAKES` (589-610): new `def wk_question: (.body // "") | test("^\\s*QUESTION\\b");` and `wk_required` (595) also true for it, so `wake_class` returns `now` for main and the relay's FYI hold skips it, whatever the subject. A repeat inside 10 minutes still drops (wk_repeat runs first, line 604).
- scripts/orca-wait.sh KEEP (272): the select also passes `wk_question`, so the drain never files a question in hidden.jsonl.
- `pp_inbox_actionable` (paths.sh:556-568) uses the same `wake_class`, so main-watch's wake sees the question too; main-watch.sh itself is not edited.
- Produces: `wk_question`; `from_full` in ask-main.sh
- Consumes: `wake_class`, the drain's KEEP filter, `check --all --full`
- Consumers of a changed contract: `wk_required` and `wake_class` callers: paths.sh:563, scripts/orca-wait.sh (KEEP), scripts/cos-watch-inbox.sh:100 and the relay hook hooks/cos-own-echo.sh:73-76 (relay class), scripts/main-watch.sh via `pp_inbox_actionable`

### CD3 (#614 #633) lane inbox waiter, its fault, and one writer per lane -- est. 150 lines
- hooks/cos-inbox-arm-stop.sh:24: the pane test also passes a linked worktree named `Fast-lane` or `Research-lane` (the `PP_STANDING_SEATS` names, hooks/lib/project.sh:38). For a lane, `COS_KEY` becomes `$COS_KEY.lane-<name>` right after `pp_cos_key` (line 32), and the poller starts as `cos-watch-inbox.sh <handle> --lane <name>` (line 66). The "already running" scan (50-62) is unchanged: it matches by script name and pane handle. Re-arm after each wake is the existing `stop_hook_active` + `.inbox-woke` chain (34-36).
- scripts/cos-watch-inbox.sh: `--lane <name>` after the handle sets `COS_KEY=$COS_KEY.lane-<name>` after `cos-lib.sh` is read (the pid file `$COS_KEY.cos-watch-inbox.pid` and the state file follow it); `admit` (line 92) is `.to_handle == $me` only (run and coordinator passed empty); the `_class` override at line 100 is dropped for a lane, so a routine note (`FYI` subject on a non-required type) stays held and prints with the next wake or after 30 minutes; `main_silent` (lines 58-77) is skipped for a lane. Lane start (no sequence file): today a missing file saves the newest place and exits 4 with nothing printed (cos-watch-inbox.sh:122-126), which would drop a message that reached the lane before its first Stop. For a lane, the place is saved just before the oldest admitted row (`.to_handle == $me`) that Orca marks unread (the row's read flag in the `--full` inbox row; the field name is a Builder check), so the first poll prints that mail; with no such row, the newest place, as today. A relay run is unchanged.
- scripts/cos-check.sh:16: the watcher scan also names `fast-lane` / `research-lane` waiters. A lane counts only when it has a live pane (`pp_pane_of` on its folder, paths.sh:1061) and its pid file `$COS_KEY.lane-<name>.cos-watch-inbox.pid` does not run `cos-watch-inbox.sh`; the line then reads `watchers down: ... fast-lane-inbox`. This is the place the relay's other watcher faults show (cos-check.sh:47).
- hooks/duplicate-agent-guard.sh:180-182: `terminal split --command <agent>` prints `split<TAB><--terminal handle>` (only `create` has one today, :182); the hook takes that handle's `.worktreePath` from `orca-ide terminal list --json` and runs the live-agent check (233-242) on it, not on the caller's cwd (:235): split has an optional `--terminal` and no `--worktree` (`orca-ide terminal split --help`, Orca 1.4.248, 2026-11-05). Bad input: no `--terminal` blocks (`split-target-unnamed`), a `$` handle blocks, an unlisted handle blocks (`split-target-unknown`), an unreadable list blocks as `pane-list-unreadable`; a quoted handle is the plain handle (the scanner strips quotes, :100-122). The prefix `COMMANDECK_REPLACE_PANE=<handle>` (read like the probe prefix, line 176) lets a launch pass only when that handle is one of the live agent panes listed and its agent is not mid-turn (`pane_is_busy`, codex-helpers.sh:161); any other value, or a busy pane, still blocks. The block text names the prefix.
- Produces: lane pollers and their key; the `fast-lane-inbox` fault; the split and replace rule in the guard
- Consumes: `PP_STANDING_SEATS`, `pp_cos_key`, `wake_class` (relay class), `pane_is_busy`
- Consumers of a changed contract: `cos-watch-inbox.sh` callers: hooks/cos-inbox-arm-stop.sh:66, hooks/cos-inbox-waiter-stop.sh (matches the name only, not edited), scripts/cos-check.sh; `COS_KEY` files: cos-check.sh:13,22, cos-watch-*.sh (a lane key is its own, the relay's files do not move); guard consumers: hooks/hooks.json PreToolUse entry only

### CD4 (#588) every orchestration parser reads the 1.4.246 form, or fails loudly -- est. 110 lines; after rules-port
- hooks/lib/project.sh new `pp_run_id_of` (reads run-current JSON on stdin, prints the run id): a result with `run` gives `.run.id // empty`; a result with `runId` and no `run` prints `pp_run_id_of: concise run-current output; the call needs --full` on stderr and returns 4; junk returns 1. New `pp_orca_run_id` runs `orca-ide orchestration run-current --full --json | pp_run_id_of`. scripts/paths.sh sources hooks/lib/project.sh after project-main.sh (:57), so each reader has the helpers before first use (orca-wait.sh loads project.sh at :288, after its :76 read; the others load paths.sh only); project.sh is definitions only and shares no name with paths.sh (`rg`, 2026-11-05).
- The five run-current readers use it: hooks/lib/project.sh:104, scripts/orca-wait.sh:76, scripts/board.sh:64, scripts/run-bound.sh:22, scripts/setup.sh:727 (its own `run_id` filter keeps its job for the id's character check). Each already tolerates an empty run; a return of 4 prints its stderr line and the site then takes its existing no-run branch, so the failure is said, not silent.
- Task-list readers on id and status stay as they are but their guards demand the shape: scripts/main-watch.sh:1741 (`orca_op '.result.tasks'`), scripts/close-done-panes.sh:138, scripts/unit-close.sh:46-48, scripts/dashboard.sh:150, scripts/poll-agents.sh:65 (`--brief`) get `all(.[]; has("id") and has("status"))` in their jq guards; a row without them is an error that existing failure branches already print (unit-close.sh:48 "could not read the task list", main-watch.sh:1742, dashboard.sh open_tasks "failed read").
- Dispatch-show readers (the judge's addition, absent from the first inventory): scripts/dispatch-task.sh:92 reads `assignee_handle`, `status` and `last_failure`; scripts/paths.sh:685 reads `has("dispatch")` and `.dispatch.id`; scripts/paths.sh:735 reads `.dispatch.id`. All three call `dispatch-show` without `--full`; each gets `--full` unless the capture shows the concise form keeps every field it reads.
- Write readers (r3 judge's addition): task-create (orca-task-create.sh:30-32), worker-start (dispatch-task.sh:78-89) and the `.ok` readers of send, reply and task-update are parsers too; each gets a case against its captured reply, and a site whose capture lacks a field it reads gets `--full` and a case for that field
- Parser inventory (`rg -n 'orchestration (dispatch-show|run-current|task-list|run-list|task-show|worker-show)' scripts hooks`, 2026-11-04; write verbs by `rg -n 'orchestration [a-z-]+' scripts hooks --glob '!**/__tests__/**'`, 2026-11-05), each with its case in orca-output-parsers.test.sh:

- Inventory: `## Parser inventory`

- scripts/__tests__/orca-full-flag.test.sh stays as is (6 checks); the new file gets the cases in the table's last column.
- Produces: `pp_run_id_of`, `pp_orca_run_id`, the fixtures, a test per parser
- Consumes: Orca 1.4.246 output (captured)
- Consumers of a changed contract: the dispatch-show sites keep their outputs, so their callers read as before (`pp_seat_open_ask`: pp_task_close paths.sh:711, answer-worker.sh:116; paths.sh:735 sits in `pp_task_close`'s task_not_startable retry; dispatch-task.sh's callers seat.sh:324, seat.sh:736 and main by hand); run-current readers above; `PP_MAIN_RUN` readers (hooks/lib/project.sh:100-110 callers: hooks/agent-awareness.sh, hooks/cos-own-echo.sh, others by `rg pp_is_main_pane`)

### CE1 (#640) one heading reader in fence.sh, used by 12 of the 14 sites -- est. 270 lines -- after rules-port
- `scripts/fence.sh` (PP_AWK_FENCE): add awk `heading(line)`, called once per line, in order, after `fence()`, only when `!flen`: sets `hlvl` (1-6, 0 for none) and `htxt` (title, trimmed, closing `#`s removed); `hold()`/`flush()` (DE13). Reads ATX at 0-3 spaces of indent (open `## T` and closed `## T ##`), and a setext underline (`===` level 1, `---` level 2, 0-3 spaces) directly under a plain paragraph (title: the whole paragraph, DE12). A paragraph is plain only when its first line (after a blank line, a heading or the file start) is not a list item (`-`, `*`, `+`, or digits then `.` or `)`, then a space), a quote (`>`), a table row (`|`) or indented 4 or more: a list or quote paragraph stays one through its lazy continuation lines up to the next blank line, so `- first limit` then `---` is a thematic break and the section goes on, as CommonMark reads it. An underline under a non-plain paragraph is text (`===`) or a thematic break (`---`), never a heading, so no section ends early. No heading is read inside an HTML block (DE9). A heading-like line indented 4 or more spaces, in a fence, or under a blank line (a thematic break) is not a heading. Three more edits in `fence()`: a fence opens only at 0-3 spaces of indent (D2), never while `heading()` holds an HTML block open (DE10), and never on a backtick run with a backtick after it (DE11).
- `scripts/paths.sh`: `pp_plan_section_paths` (:1442-1450) and `pp_plan_stale` (:1682-1683) use `heading()` for the Plan / Steps start and end (issue sites :1405 and :1644).
- `scripts/builder-codex-pass.sh` (find by function; rules-port deletes lines above ~1000, so every number below moves up): `section_lines` (:1419-1422), `evidence_section` (:1445-1447), `table_gate` (:1629), the LIMITS awk (:2039), the DEFERRED awk (:2046). These five sit where the issue lists :1436 :1619 :2020. Start of a section is matched loosely (any heading form with the title), end only at a strict heading, so a wrong end adds lines and a gate refuses more (D3).
- `scripts/merge-unit-local.sh`: Screenshots (:320), close-as-shipped (:461), Cuts (:554), Files deleted (:636), Post-merge (:886). :886 also keeps its fence-line drop.
- `scripts/seat.sh`: the report body cut at :844 (`sed -n '/^# /,$p'`) becomes the fence-aware reader: the body starts at the first level-1 heading outside a fence; none found keeps the whole pane text as today.
- `scripts/merge-rules.py`: a Python twin `heading_level(line, prev)` with the same rule (DE9, DE10, DE11); :282 (`re.split(r"^## Details ...")`) walks lines with the file's own fence state (:208-227) and cuts at the first strict level-2 `Details (not injected)` heading in any form.
- Produces: `heading()`, `hlvl`, `htxt`, `hold()`, `flush()` in PP_AWK_FENCE; `heading_level` in merge-rules.py; test file `scripts/__tests__/fence-heading.test.sh`.
- Consumes: the existing `fence()`/`flen` contract (callers: paths.sh:1445, 1568, 1586, 1591, 1613-1640, 1682; builder-codex-pass.sh:1613; merge-unit-local.sh:541, 546, 553; seat.sh:211-217), all unchanged but the indent bound, DE10 and DE11.
- Consumers of a changed contract: every `fence(` caller above now sees a 4-space-indented triple backtick, or a backtick run with a backtick after it, as text (rg 'PP_AWK_FENCE|fence\(' over scripts, hooks: paths.sh, builder-codex-pass.sh, merge-unit-local.sh, seat.sh, read-verdict.sh, plan-check.sh, close-round.sh, refute.sh).

### CE2 (#640) the driver's Question and Plan readers -- est. 75 lines -- after C1 and rules-port
- `scripts/unit-drive.sh`: `qsection` (:173) and `qopen` (:176-181) are rewritten by C1; CE2 only swaps their `^## Question for the owner` start and `^## ` end for `heading()` (start: any level, any form, title `Question for the owner`; end: the next heading of level 2 or less). Body lines go through `hold()` (DE13). C1's rule (a lone `none` closes the section, a quoted one stays open) is kept.
- `preflight` (:61): the batch's `Plan` heading test uses `heading()`, so `## Plan ##`, an indented `  ## Plan` and a setext `Plan` / `----` all count, and a `## Plan` inside a fence does not.
- Produces: none new. Consumes: CE1's `heading()`, `hold()`; C1's `qopen`.
- Consumers of a changed contract: `question_gate` (:253), `qlines` (:168), the loop head (:262-336) call `qopen`/`qsection`; unit-drive.test.sh cases :270-323.

### CE3 (#654 #653) one pass rule pinned; 14 template sections cut, each with its refusal proof -- est. 200 lines -- after rules-port
- #654, check step: `rg -n -i 'cap stop|STOP \(cap|pass cap' docs templates scripts README.md skills hooks config .claude-plugin --glob '!scripts/__tests__/**'`. At HEAD it lists the lines rules-port rewrites (README.md:112, :246, :319; docs/review-loop.md:138; builder-codex-pass.sh:29, :437, :962, :1042, :1338, :2456; main-watch.sh:964-979; builder-launch.sh:348; setup.sh:158, :307, :381; templates/main-rulings.md:15; skills/setup/SKILL.md:272, :278; docs/configuration.md:101; docs/setup-questions.md:58; plugin.json:191). Each hit left after rules-port merges is reworded to the one rule (passes run until clean; every pass from the Closing pass setting is a closing pass; `STOP (threshold)` and `REVIEW STOP` end the loop).
- #654, test: `scripts/__tests__/brief-template.test.sh` gets one case that greps the template, docs/review-loop.md, builder-codex-pass.sh and main-watch.sh for the pattern (none allowed) and for `until clean` in the template and docs/review-loop.md. rules-port edits :101-103 of this file; CE3 adds below them and edits no existing check.
- #653, cut three bullets from `templates/_builder-brief-template.md` (sizes in bytes, `sed -n '<lines>p' | wc -c`, HEAD):

- Template cuts table: `## Template cuts`

- Before: 29730 bytes (`wc -c templates/_builder-brief-template.md`). After: about 25,313 (about 4,417 bytes cut, a one-line pointer left per section that names the refusing script, about 15 percent). The sections left are judgment rules or steps no script refuses (the helper map of 2026-11-04, Stated limits).
- The refusal at merge-unit-local.sh:327 does not yet show the three row forms (they are only in the comment :297-299), so its text is extended to print `- side-by-side: <mockup> | <screenshot>`, `- screenshot: <path>` or `- none: no visual change: <reason>`, and "put screenshots at absolute paths outside the worktree". The other two refusals already explain the right action (read at the lines in the table).
- Pinning checks edited (Q6 b, D10): brief-template.test.sh:21, :59 and :176 deleted (proofs: the table's tests), :58 narrowed to the one-row-per-save rule; each with a `Test edit:` line that main writes into its private rulings file for this unit, the file builder-codex-pass.sh:803-810 reads (the Builder asks main by `ask-main.sh`; the ruling id is looked up there with `decision.sh rulings`, never written into this plan, the template, a doc or a commit). Checks of kept text stay: brief-template.test.sh:113, plugin.test.sh:138, template-sections.test.sh:25-26, seat-plan-marker.test.sh:39, main-watch-merge-gate.test.sh:96, test-rules.test.sh:17-37.
- Refusal extensions: builder-codex-pass.sh:1620-1621 adds the `break-run.sh <plan> <k> <file> <line> [<replacement>]` command; merge-unit-local.sh:874-875 adds the allowed lines (`dashboard.sh --install`, `main-watch.sh --install`, `run-shell-tests.sh <one test file>`). Those two sections are cut after these cases pass.
- New case `cut sections leave a pointer naming the refusing script` (brief-template.test.sh): per table row, the pointer line is in the template and the cited refusal string is in its script.
- New case `template keeps the new-test naming rule` (brief-template.test.sh): `Each new test names the bug it catches.` is still a template line after the cut; nothing past the cap enforces it.
- Produces: the shorter template; one new case in each of five test files (merge-unit-local-screens, edit-content-tripwires, builder-codex-pass-test-edit, builder-codex-pass, merge-unit-local) and the pointer case in brief-template.test.sh; the two extended refusal texts. Consumes: rules-port's template (:278-286, :359-360 reworded); line numbers of the cut bullets move by rules-port's edits, so the Builder finds them by their first words.
- Consumers of a changed contract: builder-codex-pass.test.sh:239-244 and merge-unit-local.test.sh:255-258 grep the extended refusals' kept old text; brief-template.test.sh, template-sections.test.sh (:25-26 pin other bullets), test-rules.test.sh (:17, :37), plugin.test.sh (:138), main-watch-merge-gate.test.sh, seat-plan-marker.test.sh read the template; the Builder checks each still passes.

### CE4 (#651) the driver carries a launched unit to merge -- est. 190 lines -- after C1, C2 and CE2
- `scripts/unit-drive.sh` (extended, not a new driver, D4): a `watch_unit` function and one call after the Builder launch (:331-336, replacing C2's clean end), and the same call from the top of `run` when a Builder is already live (D5).
- Attach: before the plan loop, `pp_seat_pane "unit-$UNIT" "$PP_WORKSPACES/$UNIT"` (paths.sh:1077, the read main uses). Non-empty -> one line `unit-drive: <unit> attached to its Builder <handle>`, `builder-launch.sh` is never called, go to `watch_unit`. Empty -> the plan stages and the launch run as today (Out of scope: plan stages unchanged).
- `watch_unit` polls every `COMMANDECK_LOOP_POLL_SECONDS` (default 30, :275) and, in this order:
  - Generation: the current build is the Builder seat record `seat-<unit>-builder.txt` its `launched=` epoch L and the worktree's HEAD; both observations below are bound to it, so yesterday's build of a reopened unit never ends or stops today's.
  - Merged: a `how: "merged"` row of this unit in `$HOME/.commandeck/builds/$PP_PROJECT.jsonl` (written at merge-unit-local.sh:899-902) whose `at` is at or after L -> C2's DONE ending, exit 0. The row's `sha` is the squash commit (merge-unit-local.sh:854) and cleanup removes the worktree (:205), so neither sha nor HEAD can bind it; L does. An older row is history and the driver keeps polling. A fix round never ends the driver; it keeps polling.
  - Builder question open (`pp_seat_open_ask`, paths.sh:680) -> `stop builder-question "<subject>" "answer it with decision.sh, then $AGAIN"`.
  - Review stop: `builder-codex-pass.sh --verify <worktree> <unit> HEAD` (the entry main-watch uses, main-watch.sh:972), run only when `pp_gate_key` (paths.sh:1534) changed; output holding `REVIEW STOP:` -> `stop review "<that line>" "answer decision <id>, then $AGAIN"`.
  - Merge refused: `$PP_SCRATCH/main-watch/merge-<unit>` names a log whose `.rc` is non-zero (merge_collect, main-watch.sh:1107-1122), the `.rc` file's mtime is after L (generation) and the record's line 1 (the tip that job tried, main-watch.sh:1111) equals the worktree HEAD; any other tip's refusal is ignored -> `stop merge "<last merge-queue line>" "bash merge-unit-local.sh <unit>, then $AGAIN"`.
  - Builder pane gone with no merge record -> `stop builder "its pane closed before the merge" "<resume command of builder-launch.sh, see Builder check>"`.
  - Builder quiet (`pp_seat_turn` / `pp_turn_quiet`, paths.sh:297, :306) for 3 polls in a row, no merge record, no open question -> `stop idle "the Builder is idle and nothing merges" "$AGAIN"`.
- Every stop is the driver's existing `stop` (:69-75): one line `STOP unit= stage= : reason; next: command` in the done file and sent to main once. One owner per unit stays the existing lock/owner file (:36-48): a second `start` is refused while the first runs.
- Why not a new driver: it would need its own lock, owner file, stop line, log and `--dry-run`; two owners for one unit is what the issue forbids. `unit-drive.sh` already owns all four.
- Produces: `watch_unit`; stop stages `builder-question`, `review`, `merge`, `builder`, `idle`. Consumes: C2's log and DONE ending; C1's `stop`/`qopen`; CE2's readers; main-watch's gate and merge records (read only).
- Consumers of a changed contract: callers of `unit-drive.sh start` (README.md:283, :288; docs/commands.md:93); readers of `unit-loop-<unit>.done` (board.sh, orca-wait.sh, close-done-panes.sh per C2); unit-drive.test.sh stubs `seat.sh`, `builder-launch.sh`.

### CF1 (#615) a held restart says why, and a test drives a session past the line -- est. 110 lines

- Cause settled from the hook's own log (see Assumptions): the hook fires, reads the right threshold and is the main pane's; the restart is held behind turns the model must take first (carry-over block, unfilled skeleton, already-restarted marker), each growing context by about 15K, and the three hold branches print their reason only on stderr of an exit-0 stop
- `hooks/context-clear-stop.sh`: new function `held <why>` near the top: one line `<time> restart: HELD: cp=<checkpoint basename, or none> session=<session_id> cwd=<PWD>: <why>` appended to `clear-hook.log`, plus the existing stderr line. `session_id` is the `sid` the hook already reads (:22); `cp` is the checkpoint the restart line names (`restart: new pane <h> resumed from <cp>.md`, the form dashboard_limit.py:1442 parses), `none` before one exists. Called at the silent holds: restart-failed marker (~54-58, cp none when not yet computed), already restarted (~73-77), unfilled skeleton (~89, ~97-101), carry-over block (~116-129, first stop), the no-checkpoint block (~162-168), and the background-agent hold (~185-190: `stop-hook: held: <n> background agents running`, which today logs no cp or session); each keeps its existing log line
- `scripts/dashboard_limit.py` `main_events` (~1648): holds are keyed by (session, cp). A `restart: HELD:` line is current when no later `restart: new pane ... resumed from <cp>.md` names its cp (cp known) and no later HELD line of the same session supersedes it; a `cp=none` hold clears on the next HELD or restart line of the same session, or after 30 min with none. Only this project's holds count: a cp-keyed hold by the existing `ours(cp)` test (dashboard_limit.py:1642), a `cp=none` hold by its `cwd` being the main checkout, so another session's or project's restart in the machine-wide log never clears or shows it. Each current hold is one entry of `restartHeld` ({cp, session, at, why}); the alert shows `main restart held: <why>`, which the relay's alerts watcher already prints and the owner sees on the board
- hooks/context-clear-stop.sh:20 (exit in a linked worktree) is NOT the cause for main: the log shows main stops from the main checkout (cwd=<main checkout>); it stays, with no change
- Produces: `restart: HELD: cp=<cp|none> session=<sid> cwd=<dir>: <why>` log line; `restartHeld` ({cp, session, at, why}) in the main-events record
- Consumes: the hook's existing branches; `main_events(now, proj, log)` (dashboard_limit.py:1603)
- Consumers of a changed contract: dashboard_limit.py main-events output is read by scripts/dashboard.sh and scripts/dashboard_alerts.jq (rg `restartFailures`); an added key changes no reader

### CF2 (#663 #591) stall recoveries and helper worktree removal -- est. 275 lines -- after rules-port, after C1, C2, C3

- New `scripts/recover-stalls.sh`, run once per tick from `main-watch.sh` `tick` (after `dead_seats`, ~1782), taking the tick's pane and task lists as `close-done-panes.sh` does (COMMANDECK_PS_JSON, COMMANDECK_TERMINALS_JSON). A new file because main-watch.sh is 1829 lines and the recoveries need a test that runs without the whole tick; the simpler alternative (a function in main-watch.sh) loses on that and on rules-port also editing the file. The tick change is one call and one printed line
- One state file `$PP_SCRATCH/main-watch/recovered` with a row `<recovery> <unit-or-task> <condition-key>`; a recovery acts only when its row is absent, writes the row first, then acts: once per unit per condition; R3b, R4 and R4b write it only after their start exits 0 (DF1)
- Each act prints one line `recovered: <what> <unit>: <condition>` to stdout; the script never calls `digest` or `post` (both are functions inside main-watch.sh, :215 and :923, not exported). Its only output contract, read by a new `recover_tick` in main-watch.sh: a `recovered: ...` line goes to `digest "$line"`, so it reaches main with the next wake and is never a question; a line `ask: <key><TAB><subject><TAB><body file>` (the body written first to `$PP_SCRATCH/main-watch/recover-<key>.txt`) goes to `post "recover-<key>" "" "<subject>" "$(cat <body file>)" once`; any other line goes to stderr. Every "one `post`" below (R2's `recovery failed once`, R3b's second missing pane, R4's second death, a missing args file, a row already present) is such an `ask:` line. A nonzero exit prints `main-watch: recover-stalls.sh exited <rc>` to stderr; the lines it printed before are still read
- Recoveries R1-R6 and the never-done list: `## Recovery rules`
- #591 helper removal (helper-apply.sh): `## Helper removal`
- #591 scratch worktrees: the three script sites already remove theirs when their step ends (builder-codex-pass.sh:2117 `drop_copy`, merge-unit-local.sh:709-711, merge-queue.sh:68); the red-proof and base-comparison copies a Builder makes by hand are covered by the brief line (`git worktree remove` after the comparison, in the same template block) and by the sweep; no code change at the three sites
- #591 periodic sweep: already built (worktree-sweep.sh:1-54, called hourly from main-watch.sh:1666-1670); its two criteria tests exist, the new tests name them in the Issue cases only through the helper cases
- Produces: `recovered: ...` and `ask: ...` lines (read only by main-watch.sh `recover_tick`); the `recovered` state file; helper-apply.sh's `applied <path>` / `REFUSED: <why>` lines
- Consumes: C1 (NEEDS-MAIN, `question_gate`), C2 (driver log, stop line, `ready` dispatch command), C3 (board idle rule, user-row delivery check); `hs_active` (host-services.sh); decision.sh list
- Consumers of a changed contract: answer-worker.sh retry (callers: decision.sh deliver_answer, main-watch.sh, ask-main follow-ups; exit codes unchanged); dead_seats change (consumers: the `once` key `dead-<unit>-<role>-<launched>` in `post`, unchanged); close-done-panes.sh new rule (caller: main-watch.sh:1805, board readers of its stdout columns unchanged)

### CF3 (#655) one supervisor for the cos watchers -- est. 190 lines -- after CF2 is not needed; independent

- New `scripts/cos-supervise.sh`: the one background command that arms the watchers (the relay's only other arm is `cos-check.sh`). It starts the four watchers (`cos-watch-decisions.sh`, `cos-watch-alerts.sh`, `cos-watch-limit.sh`, `cos-watch-units.sh`) as its own children, each in a loop; `cos-check.sh` is never its child (owner condition, 2026-11-05: the check must report a dead supervisor, and a child dies with the supervisor's EXIT trap); the inbox poller stays with `hooks/cos-inbox-arm-stop.sh` in this cut (Q9 a; CG2 moves it). `hooks/agent-startup-context.sh:138-144` (the relay's `# Wake-ups:` list, the one source that tells the relay to arm each watcher; `rg cos-watch templates/*.md` finds none, 2026-11-05) keeps its inbox line (:140) and replaces the decisions, alerts, limit and units lines with one: run `bash <plugin>/scripts/cos-supervise.sh` in the background and start it again only when it exits; the cos-check line stays, reworded (CF3 cos-check bullet); the owner-facing text of each watcher (ask the owner word for word, relay-order.sh, the alerts-seen file, the unit marks itself seen) stays under it as what to do with each kind of line. A new file because the watchers exit on a find (cos-lib.sh:16-31, `exit 0`) and each exit is today a model wake; a loop around them cannot live in any one of them
- Per child: run it, capture its output; a find is classed by the one wake rule `wake_class` (paths.sh:599) with `$for = relay`, from a message built from the line: decisions line -> `{type: "question"}`; limit line and units line (a unit idle with no closing GO, for the owner) -> `{type: "escalation"}`; alerts line -> `escalation` when it carries a crit severity, read from the `whole text: <file>` a summary line names (output over 600 bytes, cos-lib.sh:22-23), else `{type: "status", subject: "FYI alert"}`; cos-check -> routine when its line starts `cos-check: nothing for the owner`, else `escalation`
- The unit of delivery is one wake file: the exited child's `$COS_KEY.<watcher>-wake-<epoch>-<child pid>.txt` (cos_wait writes it before it prints, cos-lib.sh:20-21). Each file is acked on its own, by appending its basename to `$COS_KEY.supervise.acked`, only after its own delivery is proven; one file's ack never covers another (DF4)
- Producer order: a watcher prints and flushes a find before its seen or told mark, so a kill between them leaves a non-empty unacked wake file and an unmoved mark; cos-watch-alerts (:80-92), -limit (:30-31), -units (:45-47) are reordered, -decisions already prints first (:22-24); formats unchanged
- class `now`: the supervisor types the file's line into its own pane (`terminal send --terminal $ORCA_TERMINAL_HANDLE --text <line> --enter --wait-submit 10 --json`, as main-watch wakes main, main-watch.sh:709) and counts it delivered when the receipt's stages hold `turn_started` (the test main-watch.sh:710 applies) or the receipt is `ok` with `accepted: true` and no turn yet (pass 4: the pane is busy and its queue submits the text when its turn ends, the #586 submit trial; typing it again put the same wake in the pane three times); then it acks the file and keeps running: no re-arm per event (#576, DF4). The receipt reader takes only those two shapes: a failed send, `accepted:false`, or a receipt of any other shape (named in the supervise log) leaves the file unacked and is tried again 20 s later; after the third refused try the supervisor prints the line and exits, the one case the model re-arms, and the file, still unacked, is published by the next start; `batch`: the line is appended to the held notes (`$COS_KEY.inbox-seq`, under the same lock cos-check.sh:33-36 clears them under), then acked, and printed with the next wake or the 50-minute check; `drop`: logged, then acked
- A child that exits with no output or a failing status is a death: restarted at once, one line in `$COS_KEY.supervise.log`; three deaths of one child within 10 min are an exception: the supervisor prints `cos-supervise: <watcher> died 3 times in 10 min; log <file>` and exits (no watcher dies unnoticed)
- One supervisor per `COS_KEY`: it takes `flock -n` on `$COS_KEY.cos-supervise.lock` (fd held for its life) before any child starts; a second start that cannot take it prints `cos-supervise: already running (pid <p>)` and exits 0 with no child, so a re-arm while one runs adds nothing. Owned at start: a watcher pid file naming a live `cos-watch-*.sh` that is not its child (`cos-check.sh` excepted: it is not the supervisor's) (a hand re-arm from before) is sent TERM first, then the supervisor starts its own, so no watcher runs twice. Shutdown: each child runs in its own process group; a `trap` on EXIT, INT and TERM sends TERM to every child group, waits 2 s, then KILL, and removes their pid files, so every exit path (a failed wake send, the three-deaths exception, a kill) leaves no child running and the next arm starts clean. Drain at start: DF4
- `cos-check.sh` stays the relay's own background arm beside the supervisor, every 50 min, and the source of the "watchers down" and "missed messages" counts. Its down scan (cos-check.sh:16-20) gains `cos-watch-units` (armed at startup :143 but never scanned: a pre-existing gap) and `supervise`: down when `$COS_KEY.cos-supervise.pid` does not name a running `cos-supervise.sh`, by the same `ps -o command=` test as :18-20 (owner condition). A clean check (:51) no longer prints and exits: it appends its line to `cos-check.log` and sleeps again, so the about 29 clean wakes a day (24 h / 50 min) stop; a check with anything down, missed or held prints its line and exits, which wakes the relay as today. The startup line for it (:144) says it prints only when something needs the relay
- `hooks/cos-inbox-waiter-stop.sh` (~76-80): additive only: when any watcher is missing and no supervisor runs (pid file `$COS_KEY.cos-supervise.pid` not a live `cos-supervise.sh`), the block reason starts with `Arm the supervisor once instead of each watcher: bash <plugin>/scripts/cos-supervise.sh`; the existing per-watcher lines stay in the text, so the hook passes while the supervisor's children run (they write the same pid files, cos-lib.sh:20)
- Produces: `$COS_KEY.cos-supervise.pid`, `$COS_KEY.supervise.log`, `$COS_KEY.supervise.acked`; the single exception line; the one-supervisor startup line
- Consumes: wake_class (paths.sh:599-610); the children's pid files and wake files (cos-lib.sh:16-31); the held-notes file; the send receipt's `stages`
- Consumers of a changed contract: the waiter-stop hook (hooks/hooks.json:122 neighbours); the relay pane reading the startup text (hooks/agent-startup-context.sh:138-144; its size is pinned by scripts/__tests__/startup-size.test.sh, which a shorter list keeps green); cos-check.sh's new `supervise` and `units` names and its quiet clean check (readers: the relay, which acts on a printed line; `hooks/cos-inbox-waiter-stop.sh`, which reads only its pid file, unchanged; scripts/__tests__/cos-check.test.sh)

### CF4 (#608) rank what fills the two coordinator panes, then hold the routine wakes it names -- est. 180 lines

- New `scripts/context-rank.sh <session.jsonl>...` (jq): reads Claude session logs and ranks by bytes three kinds: tool calls (key = tool name plus, for Bash, the script basename), tool outputs (same key), and inbound messages (user rows that are not typed prompts: key = first words of the text, e.g. `cos-check:`, `main-watch:`, a watcher name). Output: `bytes<TAB>count<TAB>share%<TAB>kind<TAB>key`, top 20, with `--session main|relay` choosing the newest log for the main checkout or the Chief-of-Staff worktree (the project folder is the `claude-profiles` or `~/.claude/projects` slug of the cwd). A new file because `context-overhead.sh` replays hook output only and reads no session log
- Builder check (before CF4) runs it on both panes; the top keys decide (DF8). Held routine wakes are CF3's (the clean check, routine alerts) and wake_class's (`status` is already `batch` for main, paths.sh:599-607)
- Removals the measure unlocks, each only if its key is in the top 10 of either pane: a re-arm of `cos-watch-*.sh` or `cos-check.sh` (key `Bash cos-watch-...`): covered by CF3, whose edit of the relay's arm list (hooks/agent-startup-context.sh:138-144, its one source) makes it a supervisor line and a finding-only cos-check line, so CF4 edits nothing more for it; an inbox, board or merge-log dump: the script the key names pipes its default output through new `pp_cut_output` (paths.sh, DF10); no template edit (DF9)
- Produces: the ranked table; its run in Progress (top 10 per pane); `pp_cut_output`
- Consumes: the two session logs
- Consumers of a changed contract: a capped script's stdout, read by main's pane and that script's tests (named in Steps when the measure names it, DF10)

### CG1 (#584 #585 #586) the live trial script and its record -- est. 185 lines
- New `scripts/orca-native-trial.sh <wake|send|submit> <phase>`: a Builder runs it live against Orca. Three trials, one record. `record_result <trial> <pass|fail> <why>` is the only writer of `docs/orca-native-trial.json`.
- Why a new script: doctor.sh is read-only and quick, proof-run.sh runs on stubs (no real job starts), hook-probe.sh probes one hook; a file that drives `orca-ide` and writes one record is smaller than bending any of them.
- Record `docs/orca-native-trial.json` (committed; the tests and the removal cuts read it): `{"orca": "<version>", "date": "<utc>", "wake": {"result": "unrun|pass|fail", "why": ""}, "send": {"<agent>": {"<host>": {"result": ..., "why": "", "form": "handle|dispatch", "closed": {"result": ..., "why": ""}}}}, "submit": {"result": ..., "why": ""}}`. It starts with all three `unrun`. Anything else (absent file, junk, a missing key, a value outside the three) reads as `unrun`. Only `pass` unlocks a removal.
- Trial `wake` (#584): phase `start` makes a throwaway run (`orchestration run-create`), starts one worker (`worker-start --agent claude --model <cheap model>`) whose spec is "send worker_done succeeded, then end", writes `$PP_SCRATCH/native-trial/wake.json` (run id, worker dispatch, coordinator handle, epoch), checks that no process named `cos-watch-inbox`, `await-agents`, `watch-agents` or `poll-agents` runs (pgrep), prints "end your turn now" and exits. Orca must then wake the coordinator pane. Phase `restart` (optional, run when the first wake passed) closes the coordinator pane and reopens it with the host project's own restart path (`hooks/lib/context-clear-restart.sh`), starts a second worker, and ends the turn again. Phase `finish` runs in the woken pane: it passes only when each worker's `worker_done` is in the coordinator's inbox read with `orchestration check --peek`, the pane's session log shows a turn that started after the worker report (a user row or a wake row dated after the stamp), and the pgrep check is still empty. Any missing proof is `fail` with the missing proof as `why`.
- Trial `send` (#585), run once per Builder agent, `--agent claude` and `--agent codex` (Orca binds no Mac Codex pane, dispatch-task.sh:7-11): makes a worker that finishes (`worker_done`), waits until `worker-show` says settled, then sends a follow-up with `orchestration send --to <handle>` (the open worker: `send.<agent>.<host>.result`, `why`, `form`). Closed case (DG8; after CG3's `pp_follow_up`): pane opened and closed as seats do, then `pp_follow_up <old handle>` (`PP_FOLLOW_UP_TRIAL=1`); pass = the text a user row and a new turn in that worktree, and the record names a listed pane; result `send.<agent>.<host>.closed`. Each entry is under `send.<agent>.<host>`, host the trial machine's `uname -s`; CG3 reads this host's entry only (DG7).
- Trial `submit` (#586): starts a worker on a long foreground command (a 60 s sleep), then types three wakes with `terminal send --enter --wait-submit 10 --json` and no resend, no `accepted:false` retry and no Escape. Passes only when all three texts are user rows in the worker's session log after its turn ends, in order, none typed twice, and no receipt says `accepted:false`.
- Consumes: `orca-ide` (`orchestration run-create|worker-start|worker-show|dispatch-show|send|check`, `terminal create|send|list|read|close`), paths.sh (`PP_SCRATCH`, `pp_task_close`, `pp_pane_close`, CG3's `pp_follow_up`), dispatch-task.sh.
- Produces: `docs/orca-native-trial.json`; three new rows (items 7, 8, 9) in the `docs/troubleshooting.md` retest table with the record's result and why, written by the Builder after each trial (heading renamed "Orca 1.4.241-1.4.248 retest").
- A failed trial keeps the old path: `record_result` writes `fail` and the why, the removal in CG2 or CG3 for that trial is skipped, and the issue stays partial.
- Consumers of a changed contract: none (new file); `docs/troubleshooting.md:37-48` gains rows.
- The consistency test in `scripts/__tests__/orca-native-trial.test.sh` ("wake record gates wait-loop removal", "send record gates terminal-send removal", "submit record gates wake-text removal") holds at every commit: with `unrun` or `fail` the old files and sites must exist; with `pass` the deleted files are gone and nothing in scripts, hooks or docs names them but the trial's own files (the script, its test, the record, the retest rows), the CG2 claims' scope.

### CG2 (#584) retire the relay poller's Stop-hook re-arm and main's wait loops; the poller stays as the filter -- est. 70 lines -- after CF3 and CD3
- Gate: only the deletion of `scripts/await-agents.sh` and `scripts/watch-agents.sh` (main's wait loops, below) runs only when `docs/orca-native-trial.json` has `wake.result = pass`; otherwise those two stay and #584 is partial. The poller's move under the supervisor and the drop of the hook's relay branch (D11) run in every case: the supervisor wakes the relay by its own proven typed line (DF4), not by Orca's native wake, so a failed wake trial leaves no reason to keep the per-Stop re-arm, and #576's one long-lived watcher lands either way.
- Q11 b (D11): `scripts/cos-watch-inbox.sh` stays whole (filters, `inbox-seq`, `inbox-seen-ids`, tests). Only its re-arm goes: the relay branch of `hooks/cos-inbox-arm-stop.sh` (pane test line 24, start lines 64-66).
- The poller's starter becomes `scripts/cos-supervise.sh` (CF3): a child `cos-watch-inbox.sh <handle>` whose output is class `now` (the poller already applied `wake_class`), so the supervisor types it into the relay pane and keeps running (DF4). CF3 leaves the poller alone (Q9 a); this cut moves it.
- The hook and `hooks/hooks.json:122` stay for CD3's lane panes: lanes have no supervisor, and the trial covers no lane mail.
- Delete `scripts/await-agents.sh` and `scripts/watch-agents.sh` (main's background polls of its inbox and board; their only readers are `scripts/__tests__/to-main.test.sh:336-351` and a comment at `scripts/poll-agents.sh:40`). Q11 names only the relay poller, so main's wait loops still go (assumption, Plan change log).
- Keep `scripts/orca-wait.sh` (one foreground drain; its batch ack is still needed, `docs/troubleshooting.md:44`), `scripts/poll-agents.sh`, `hooks/cos-inbox-waiter-stop.sh` and `scripts/cos-check.sh` (the poller and its pid file still exist).
- Startup and docs: `hooks/agent-startup-context.sh:140` (the inbox line folds into CF3's one supervisor line), `docs/hooks.md:37` (lane panes only), `docs/chief-of-staff.md:34`, `docs/troubleshooting.md:26` name the supervisor as the poller's starter.
- Tests (Q10 a): the relay arm cases in `hooks/__tests__/cos-inbox-waiter-stop.test.sh:78-155`, with `two wakes in a row re-arm the poller without a turn`, move to a `Fast-lane` pane; new `relay stop starts no poller` and (cos-supervise.test.sh) `inbox poller text wakes through the supervisor`; the wait-script cases at `scripts/__tests__/to-main.test.sh:336-351` go.
- Consumers of a changed contract (`rg 'cos-inbox-arm-stop|await-agents|watch-agents'`): the startup, comment, docs and test sites above; `hooks/hooks.json:122` (kept); `docs/guard-review-2026-10-31.md` (history, left); CF3's child list.
- Produces: a relay whose poller runs under the supervisor with no per-Stop re-arm; an orchestrator Orca wakes with no wait loop; lane panes armed by the hook as in CD3.
- Consumes: CG1's record; CF3's supervisor and its `now` class; CD3's lane branch of the hook.

### CG3 (#585 #586) follow-ups by `orchestration send`; drop the unsent-wake handling, keep the dashboard outbox -- est. 230 lines -- after rules-port, after C3
- `after rules-port`: it edits `scripts/main-watch.sh`, which rules-port also edits (its step edits ~962 only; this cut edits the `inbox_wake` function near 316-335 and the wake block near 583-660, so plan against rules-port's text and re-read line numbers). `after C3`: C3 edits `scripts/answer-worker.sh` (tag counted only in a user row), which this cut also edits.
- Part A (#585), per agent: a site uses `pp_follow_up` only for a pane whose agent has `send.<agent>.<host>.result = pass` for this host (`pp_send_form`, DG7); otherwise `pp_follow_up` returns 3 and the site keeps its typed path (a Mac Codex pane keeps its pointer). Add `pp_follow_up <handle> <subject> <text>` to `scripts/paths.sh` (one function: `orchestration send` in the record's `form`, `--type dispatch`, returns Orca's exit code; four callers justify it). Move these sites to it:
  - Closed panes (DG8): `pp_follow_up` sends to a handle Orca no longer lists by `--to dispatch:<id>`, gated on `send.<agent>.<host>.closed` (`--check`: gates only); answer-worker.sh:143 calls it before its no-pane exit, seat.sh revise (:301) before its not-live refusal; return 3 keeps each refusal.
  - `scripts/answer-worker.sh:300-309` (idle and working panes get typed text) and `:340-347` (re-type once the turn ended): for a pane whose agent passed, the answer text goes by `pp_follow_up` in every pane state, the one route the send trial proves starts a turn in an ended pane; with an open question (`QID`) the thread also gets `orchestration reply --id $QID --body "answered: <TAG>"` (the settle form answer-worker.sh:134 already prints), since the trial never proves a reply wakes an ended pane (#658's case: an ended Builder with an open question, answered today by reply alone, :310-316). A pane `working` inside `orchestration ask` returns on the reply (:311), so for it the reply keeps the full text and no follow-up is sent; The re-type branch (:337-347), `idle` and `working` stay (DG9). The tag-in-log delivered proof (`:353`) and the ACK wait stay: they prove the worker read it.
  - `scripts/main-watch.sh` `inbox_wake` (`:316-335`): the function, its call, its `.inbox` history files and `scripts/__tests__/main-watch-inbox-wake.test.sh` stay. Skip per message: for a pane whose agent passed on this host (`pp_send_form`), only an own-thread message (`(.thread_id // .id) == .id`, paths.sh:668: what `send` makes, proven to wake) leaves `new`; a reply (paths.sh:670, unproven) and any message to a pane whose agent did not pass keep the "Signal INBOX" pointer (main-watch.sh:302-306). The pane's agent comes from `pane_kind_of` (codex-helpers.sh:189, as answer-worker.sh:145) on the tick's `$ps` and `$terms` (main-watch.sh:1756); sourcing codex-helpers.sh is safe (returns at :203).
  - `scripts/seat.sh:325-327` (the revision typed when `dispatch-task.sh` fails, "NO-WAKE"): becomes `pp_follow_up` with the revision text and task id; the NO-WAKE message goes.
  - `scripts/builder-fresh-round.sh` `send()` (`:51-62`): the hand-off order after the `/clear` goes by `pp_follow_up`; the `/clear` itself stays typed (a slash command is a keystroke for the TUI, not an order), and so does its `accepted:false` retry only for `/clear`. Its gone-pane `fail` (:98) stays (DG8).
- Sends kept, with the reason each stays (not the old-limit workaround):
  - `scripts/answer-worker.sh:263` (Escape) and `:296` (`--interrupt` into a parked `ask-main.sh` wait): they interrupt a live turn; the trial does not cover interrupts.
  - `scripts/main-watch.sh:296` (STOPPED), `:388` (WARM), `:401` (STUCK/QUIET/LOOP): nudges to a pane that is busy or has just stopped, not orders to a finished worker; `scripts/main-watch.sh:709` is the wake of main's own pane (Part B).
  - `scripts/seat.sh:351` (`/effort`), `:651` (first order to a fresh pane: no earlier turn exists), `:712` (menu answer), `:789` (Ctrl+U composer recovery); `scripts/seat-go.sh:15` (first-turn `go`); `scripts/dispatch-task.sh:65` (Codex pointer: Orca never binds Codex on the Mac, `dispatch-task.sh:4-14`); `scripts/cos-tell.sh:39` (the owner's dictation to the relay pane, not a worker); `hooks/lib/context-clear-restart.sh:78` (the first prompt of a new pane in a restart); `scripts/codex-hook-trust.py:289` (a comment).
  - `hooks/duplicate-agent-guard.sh:184` blocks a hand-typed new job into a busy pane; it stays (it guards the stays above).
- Part B (#586), runs only when `submit.result = pass`; Q12 b (D12): the dashboard outbox stays whole (`answer-retry.json`, `/unsent`, `needsOwner.unsent`, its alert and row): it keeps failed sends of any cause (`scripts/dashboard_serve.py:261-262`), not wakes left unsent. Only text naming a wake typed but not submitted goes:
  - Builder check before Part B: `rg -n -i 'wake' dashboard/app.js scripts/dashboard_serve.py scripts/dashboard.sh scripts/dashboard_alerts.jq docs/dashboard.md`; at plan time the only hits are the wake-log fact (`dashboard/app.js:1195-1198`, `scripts/dashboard.sh:1087-1093`; it reports `no_turn`, kept by DG3) and watcher lines. A hit naming an unsent wake -> delete it here and add its file to Steps; none -> Part B edits no dashboard file and the Progress note says so.
  - `scripts/answer-worker.sh`: no state of its own remains for unsent wakes; the `wake refused` log rows for a failed send stay (they are the wake log's record, read by the dashboard main card).
  - `scripts/main-watch.sh:583-660` (`WAKE_TRIES`, `$ST/wake` try counter, `wake-first`, `wake-streak`, `wake-alert`): kept. They answer `no_turn` (Orca took the text but no turn started), which the submit trial does not prove gone; deleting them would hide a lost wake. Said in Decisions DG3.
- Docs: `docs/troubleshooting.md:27` (answer-worker text: typed-in answers go; the ACK wait stays).
- Consumers of a changed contract: Part A: `scripts/answer-worker.sh` callers (`scripts/decision.sh` `deliver_answer`, `scripts/dashboard_serve.py` `deliver_to_unit`, main by hand), `scripts/seat.sh` (revise path), `scripts/builder-codex-pass.sh` / `scripts/builder-add-work.sh` (call `builder-fresh-round.sh`; builder-add-work.test.sh:49 counts `terminal send`). Part B: none (the outbox and its readers are unchanged; a file the Builder check finds is listed with its readers then).
- Existing checks this contradicts (Question for the owner Q10): typed-answer cases at `scripts/__tests__/answer-worker.test.sh:29,156,298,377`, `answer-worker-interrupt.test.sh:28` (stays: interrupt kept), `scripts/__tests__/seat.test.sh:78`, `scripts/__tests__/builder-fresh-round.test.sh:34`, `scripts/__tests__/builder-add-work.test.sh:49`, `scripts/__tests__/builder-codex-pass-fresh-round.test.sh:84-160`.
- Produces: follow-ups through `orchestration send`; no typed re-send on the `pp_follow_up` route (answer-worker's re-type stays for reply-only and no-pass panes, DG9); the dashboard outbox for failed sends as today.
- Consumes: CG1's record (`send.<agent>.<host>`, `submit.result`); C3's answer-worker.

### CH1 (#621 #645) re-planned unit reads Planning; '/units pane on' always opens and reports -- est. 120 lines
- scripts/dashboard.sh `replanning` (~203-218): a plan seat record launched after the Builder's first stage whose last `verdict=` is a NO-GO (no `revised=` after it yet) also counts as re-planning; today only "no verdict" or "revised after a verdict" does. The awk gains `nogo = (k == "verdict" && v ~ /NO-GO/)` and ends `exit !(ok && m != "" && m > a + 0 && (!done || nogo))`, with `m` the record's newest `launched=` (DH8). A `verdict=GO` record still reads waiting-main (existing check at scripts/__tests__/dashboard-built-planning.test.sh:155 is kept as it is).
- hooks/units.tsx `enrich` (~97-107): a row at stage `waiting-main` also reads its plan-author and plan-judge seat records (today only `planning` rows do), counting only records whose file mtime is at or after the row's `startedAt` (the Builder's start) so the Builder's own old planning never counts. If either seat reads `running`, or the newest plan-judge record (mtime at or after `startedAt`) ends in a NO-GO `verdict=` with no `revised=` after it (DH8), the row's `stage` becomes `planning` (so stage name, colour, counts and the step row follow the planning branch of `stepsOf`). The snapshot is up to 5 minutes old and the seat files are read every poll, so this closes the gap the dashboard rule cannot see.
- hooks/units.tsx `showPane` and the `command.run` handler (~270-336): the `pane on` path calls `$.ui.open({ id: PANE, title: 'Units' })` every time (the person's explicit ask, which the engine places at any width), then reads `$.ui.panes()` and finds the pane's `isPlaced`. The reply becomes `units pane: on for this session` when placed, else `units pane: on for this session, waiting undrawn (the window is under 110 columns wide; widen it or run /units pane on again)`. `showPane` keeps its `up === paneUp` guard for polls (no open per poll); only the command bypasses it.
- hooks/units.tsx `showPane` for the session-start / poll open: after `ui.open`, if `isPlaced` is false it logs the reason once per start (Builder check below for the log call).
- hooks/units-world.ts: the mock gains an `ui.panes` handler returning the opened ids with a settable `isPlaced` (default true) and a `w.placed` switch; `ui.open` keeps its return.
- Produces: row `stage` = planning for a re-planned built unit (mod and dashboard); reply text with placed state.
- Consumes: seat records `$PP_SCRATCH/seat-<unit>-plan-*.txt` (`launched=`, `first=`, `verdict=`, `revised=`), `Row.startedAt`, `$.ui.panes()` (`UiPane.isPlaced`).
- Consumers of a changed contract: `replanning` has one caller, scripts/dashboard.sh:418; `stage` of a row is read by hooks/units-elements.ts (stageOf, stageColor, stepsOf, stageCounts), hooks/units-sources.ts (paneModel, bandModel, summaryLine, busiest) and scripts/dashboard_alerts.jq:60; the reply text has no other reader (rg "for this session" hooks docs README.md).

### CH2 (#555) collectors and parsers: what the views read -- est. 190 lines
- scripts/dashboard.sh Builder block (~449-452, next to `context`/`clearLine`): `bj` also carries `compactions` (count of `"subtype":"compact_boundary"` rows in the Builder's session log, `grep -c` then a number or null when the log is unreadable) and `tools`, copied from `b` (:412). dashboard_builders.jq (already run on `builder-events.jsonl`, :408) makes it: the last 3 `tool-start` rows as `{tool, ts, running}`, `running` = `.use` not in its `$endedSet` (:43), which holds the end rule: a `tool-end`, `search-refused` or `tool-refused` with that `use`, a `batch-end` holding it, or a `subagent-stop` of the call's helper placed after the call (:39-41). A helper's call after its stop (:32-33) runs. No new file.
- hooks/units-sources.ts `Row` (:93-98) gains `context: {tokens, line} | null`, `compactions: number | null`, `rounds: Dot[]` (review passes from `builder.verdicts`, a JSON object keyed by round, value "VERDICT: GO|NO-GO..."), `judgeRounds: Dot[]` (set by units.tsx `enrich`), `history: {stage, from, to}[]` (from `builder.stageHistory`), `tools: {tool, ts, running}[]`, `steps` last entry (for the receipt); `Snap` gains `gates: {blocks, lastHour, items:[{at, hook}]} | null` (from `p.guardBlocks`) and `seatCtx: {main: Ctx|null, chiefOfStaff: Ctx|null, mainCompactions: number|null}` (from `p.seats.main.context/line`, `p.seats.relay.context`, `p.mainEvents.compactions` length, 24 h), and `unpushed: string[] | null` (the unit names in `u.mergedSincePush`, kept apart from `day.merged`, which units-sources.ts:236 builds by joining finished and unpushed names and so cannot tell them apart; null when the dashboard wrote null (its read failed, dashboard.sh:530) or the value is not an array, and then `unpushed: unreadable` goes to `unread`). `parseSnapshot` fills them; a field of the wrong type is junk and goes to `unread` with a name (`context <unit>: unreadable`). A key the snapshot lacks leaves the field `undefined` (optional `?:` types); null and undefined differ (DH9).
- hooks/units.tsx: a new `readEvents` reads the tail (last 40 whole lines, cache by size and mtime like `parsed`) of `$PP_SCRATCH/unit-events.jsonl` (`{at, unit, event}`) into `State.events`; a file over MAX_LOG, or absent, gives `events: null` and a placeholder `unit log: not read (no unit-events file)`; `enrich` also reads `verdict=` lines of the unit's plan-judge records into `judgeRounds`.
- types/index.d.ts (:5-12, :14-19): `UnitsRow`/`UnitsState` get the same fields (the file says it mirrors units-sources.ts).
- Produces: `Row.context|compactions|rounds|judgeRounds|history|tools`, `Snap.gates`, `Snap.seatCtx`, `Snap.unpushed`, `State.events`.
- Consumes: dashboard.sh fields `builder.context`, `builder.clearLine` (existing, :450-451), `builder.verdicts` (:428-438), `builder.stageHistory` (:412), `builder.steps`, new `builder.compactions`, `builder.tools`; `p.guardBlocks` (:789, part :1177); `p.seats` (:1081-1094); `p.mainEvents` (:1099-1103); `p.finishedBuilds`/`mergedSincePush` (:530-531); ledger-like file unit-events.jsonl (paths.sh `pp_unit_event`, :254-258); seat records.
- Consumers of a changed contract: dashboard_builders.jq's object (additive key) by dashboard.sh:408 and main-watch.sh:263; `bj` keys are read by dashboard/app.js and scripts/dashboard_alerts.jq (rg "builder\." dashboard/app.js scripts/dashboard*), adding keys breaks none (page reads named keys); `parseSnapshot` callers: hooks/units.tsx:78 and hooks/units-sources.test.tsx; `emptySnap` (:122) callers: units.tsx:72,73,217,369, units-sources.test.tsx; `State` literal in units.tsx:222 and :369.

### CH3 (#555) the pane elements and layouts -- est. 260 lines
- hooks/units-elements.ts gains one pure function per element, each returning `Line[]` and `[]` when it has nothing (so an empty section takes no space): `layoutOf(w)` (`mini` under 48 columns, `compact` 48-79, `wide` from 80); `ctxGauge(row, w)` (bar of `context.tokens / context.line`, `C.bad` at or past the line, a `· N compactions` suffix, the placeholder `context: not read` when `context` is null); `roundDots(row)` (from `rounds` and `judgeRounds` only, not `verdict`; one `●` per plan-judge round then per review pass, `C.ok` for GO, `C.bad` for NO-GO, `C.dim` `○` for a pass with no verdict); `gateStrip(snap, rows)` (one cell per newest `gates.items` hook, red; one amber cell per row with `red`, "at its prompt"; placeholder `gates: hook fire log not read` when `gates` is null); `receiptLine(row)` (last step's duration from `steps[0]`, edits as `edits not recorded` (the 3 kept `tools` rows are the newest calls, not one step's), errors as codex steps with `rc != 0`, a `running` tool's name with `command not recorded` (the event log keeps a checksum of the call, never its text, hooks/builder-event-log.sh:43), and cost added as `not recorded`: the owner's Q14 pick (D9)); `timelineLanes(s, w)` (one lane per row, a cell per `w - 24` slots across local midnight to now, each slot coloured by `stageColor` of the `history` stage that covers it, dim `·` where none); `whereLine(merged, snap)` (one dim line after the MERGED TODAY rows: `pushed m, x · merged here y`, by `snap.unpushed` as DH3; `push state not read` when null; nothing when undefined or none merged); `eventLog(s, w)` (last 5 events, `clockOf(at)`, unit, event).
- hooks/units-elements.ts `cardModel` (:148-167): after the step row, the `ctxGauge` and `roundDots` rows; before the red row, the `receiptLine`; `expanded` rows (see CH4) add the last 3 `tools`. A row is drawn only when its element returns lines (DH9). `mergedModel` (:170) is unchanged.

Placeholder: hooks/units-elements.ts | 'edits not recorded', ...(r.step ? [`errors ${r.step.errors}`] : []), 'cost added not recorded', | the owner's Q14 pick (D9): the event log keeps no edit or cost count, so the receipt names them `not recorded` rather than guessing
Placeholder: hooks/units-elements.ts | ...(run ? [`running ${run.tool} · command not recorded`] : []), | the owner's Q14 pick (D9): the event log keeps a checksum of a call, never its text (hooks/builder-event-log.sh:43)

- hooks/units-sources.ts `paneModel` (:321-343): sections in this order, each drawn only if non-empty: header, CANNOT READ, legend, WAITING ON OWNER (amber, first section), SEATS (one `ctxGauge` short row each for main and the chief of staff from `snap.seatCtx`, with main's 24 h compaction count; `main context: not read` / `chief of staff context: not read` when null; drawn with or without unit rows, so #555's live-seat gauges have a consumer), units (cards; in `mini` a one-line row per unit with no card), GATES, MERGING, TESTS, TIMELINE (wide only), MERGED TODAY, UNIT LOG (wide and compact; mini omits). `compact` omits TIMELINE and the per-stage cost split row. `FIGURE` (:308) gains `context ` so a Builder context gap shows under CANNOT READ only.
- hooks/units.tsx (:356): the Pane width cap `Math.min(72, ...)` goes to `Math.min(120, ...)` so `wide` can draw.
- Produces: the element functions above; `paneModel(s, w, frame, ui)` with the layout chosen from `w`.
- Consumes: the CH2 fields; `C` theme keys (units-elements.ts:6, no raw colours); `workMark` for motion (off by default, the `motion` option).
- Consumers of a changed contract: `paneModel` callers: units.tsx:360, `paneLines` (units-sources.ts:345), `tableText` (:391) used by `/units` (units.tsx:335); `cardModel` callers: paneModel only (rg cardModel hooks); `mergedModel` callers: paneModel only (unchanged); units-panes.test.tsx (:61-66, :71) and units.test.tsx pin card and merged-row text, and their fixtures carry no new key, so by DH9 they run unedited.

### CH4 (#555) band, status line, keys, docs -- est. 190 lines
- hooks/units-sources.ts `bandModel` (:353-384): row 2 (the busiest unit) appends the context gauge short form (`ctx 62%` red past the line) and keeps its cost; rows 1 and 3 keep their content and order (owner questions and the limit first). `layoutOf`: in `mini` the band keeps row 1 and row 2 cut to the width; `compact` and `wide` as now.
- hooks/units-sources.ts `summaryLine` (:394-413): unchanged order and unchanged signature (worst first: `✗` for a pane at its prompt or a refused merge, then `◆` owner question, then counts, merged today, 7d limit with reset, today's cost). No narrow-width branch: its one production caller, `sendStatus` (hooks/units.tsx:259), has no width to pass, so a `w` parameter would have no caller. `$.ui.status` takes plain text, so red and amber are the `✗` and `◆` marks, as today.
- hooks/units.tsx: the pane's keys. The pane draws one `Button` per unit labelled `[n] name` and three `[d] [t] [l]` Buttons; `onPress` updates an `expanded` atom (unit name or null) and a `focus` atom (`decisions`, `timeline`, `log` or null); those atoms are the only new state, nothing is written to disk. `paneModel` puts the focused section first and gives the expanded unit its last 3 tool calls (`tool`, clock time, `running`).
- docs/dashboard.md `## Units mod` (:187-252): new subsections for the context gauge, round dots, gate strip, receipt, timeline, merged today, unit log, keys, layouts, the placeholder text each element shows, and the sources (which dashboard fields or files). README.md:265 (`/units` row) adds the keys, written in C4 after rules-port (rules-port edits README.md); README.md:420 is unchanged.
- NOTICE: no code is copied from the style reference (Flightdeck, MIT): only the idea of the sections; so NOTICE gets no line. Each new function is written from the issue text.
- Produces: `expanded` and `focus` atoms (`PluginState` in types/index.d.ts gains `unitsExpanded: string | null; unitsFocus: string | null`); band row 2 with context; `summaryLine` unchanged.
- Consumes: CH3 `ctxGauge`/`layoutOf`; `ButtonProps.onPress` (the `ui.press` event).
- Consumers of a changed contract: `summaryLine` callers: units.tsx `sendStatus` (:259), units.test.tsx, units-sources.test.tsx; `bandModel` callers: units.tsx:347, units-panes.test.tsx and units.test.tsx (`band` helper units-world.ts:111). `summaryLine` keeps its signature, so no caller changes.

### C4 release notes -- est. 30 lines

- docs/commands.md ~93: start's refusal, the driver log and NEEDS-MAIN; docs/troubleshooting.md ~28: an answer counts once its turn has it
- The doc lines of earlier cuts that sit in rules-port files, written here after rules-port merges: docs/configuration.md ~128 (CD1: main found as the run's coordinator), README.md ~32 (CD3: lanes watch their inbox), README.md ~265 (CH4: `/units` keys). No cut before C4 edits README.md or docs/configuration.md except CE4, which is itself after rules-port
- CHANGELOG.md, .claude-plugin/plugin.json and README.md:4's badge (image URL and alt text): the next minor after main's version, plain user-facing style of the newest entries

## Recovery rules

- Scope: the recoveries recover-stalls.sh and dead_seats act on (cut CF2, #663)
- R1 close a pane: the new rule in close-done-panes.sh (beside the orphan rule, ~72) names when two existing protections end for one proven generation; every other NEVER-closed rule of its header stays. Today a Builder handle is protected while any `seat-*-builder.txt` names it (close-done-panes.sh:66) and a seat record with no `verdict=` claims its handle (CLAIMED, :76-78). For a record whose `launched=` is L: (a) merged: the unit's `merged` row has `at` at or after L (L alone binds it, as in CE4); both protections end for that record's handle and the pane closes; (b) stopped: `unit-loop-<unit>.done` holds a STOP or DONE line written after L (its file mtime) and Orca reports the pane's agent exited (no agent in `worktree ps`, the issue's "whose agent has exited"); both end. A stopped unit whose agent is alive and idle is kept: its STOP line asks main to act in that pane. A record older than the newest merged row of an earlier build of the same unit name never matches (a) for a newer record, since L is after that row's `at`
- R2 answer to an idle pane: found from the delivery record, not the open-thread test, because answer-worker writes its thread reply before the receipt (answer-worker.sh:314) and `pp_open_ask` then counts the question answered (paths.sh:670). Condition: the wake log (`pp_wake_log`, answer-worker.sh:224) has an `answer <TAG> sent` row for the pane's handle; that tag's follower log `$PP_SCRATCH/answer-worker-<TAG>.log` (answer-worker.sh:366) has no `delivered` line; the tag is in no prompt row with a turn started after the send (C3's per-agent rule); and the pane is idle 5 min or more (`read-verdict.sh --state`). Act: `answer-worker.sh <handle> <answer text>` once (C3: typed once idle, delivered only once it starts a turn, #663 item 2); not delivered is one `recovery failed once` post. The answer text is the decision ledger row the follower log names (Builder check before CF2)
- R3 task left ready: a Builder seat record whose task Orca lists `ready`, whose pane is listed and whose launch is over 3 min old: `dispatch-task.sh <task> terminal:<handle>` once per task (C2's driver stop line names this command and never sends it itself, D5)
- R3b Builder pane that never got its task (#663 item 3): a Builder seat record whose task Orca lists `ready`, whose handle is not listed, launch over 3 min old, no `merged` row at or after `launched=`: `seat.sh launch builder <unit> <record's spec=>` once (no plan gate for builder, seat.sh:414; the call builder-launch.sh:303 makes), then `pp_task_close` (paths.sh:711) on the old task; row `R3b <unit> nopane` after the launch exits 0; a second missing pane is one `post`, no relaunch
- R4 dead driver (DF9): the args file's fourth line names the service NAME, `hs_active NAME` is false, no `unit-loop-<unit>.done`, and `drive-<unit>.owner` is absent or names NAME: `unit-drive.sh start <unit> <author-spec> <judge-spec> <batch>` once, the three paths read from that file (it resumes: unit-drive.sh header 17-19); the second death of the same unit (a second distinct owner name) is one `post` question with the log tail (main-watch.sh:215), no restart. Durable source of the arguments: `start` writes `drive-<unit>.args` (four lines: the absolute author spec, judge spec and batch, the `abs` values it passes to `hs_start` at unit-drive.sh:112, then NAME; start's EXIT trap removes it on a refused start, DF9) under the lock, beside the owner file (:100), before the service starts; it is a plain file in `$PP_SCRATCH`, so both service backends (launchd and systemd, host-services.sh) read the same source and no process argv is needed. A missing or short args file: no restart, one `post` question naming the file
- R4b seat ended with no verdict: `dead_seats` (main-watch.sh:1678-1713) relaunches once before posting, by the route the launch gate allows: a `plan-*` seat (refused by seat.sh:415 outside the driver unless a hand-launch reason is set) waits for a running driver's own `no verdict` STOP (DF10), then is relaunched by R4's `unit-drive.sh start` with the args file, which re-runs only seats with no verdict on this version (header 15-17) under `COMMANDECK_DRIVER=1`; any other role (no plan gate) by `seat.sh launch <role> <unit> <spec>`, the spec path from the seat record. Never `COMMANDECK_HAND_LAUNCH`: a recovery is not a hand launch. The existing question stays for the second exit of the same seat
- R5 question with no decision: C1's `question_gate` in the driver; R4 covers a dead driver (the restarted driver re-sends once). No new code
- R6 unread pane list: `answer-worker.sh:140-141` retries the two list reads inside a 12 s list budget counted from the first try (bash `SECONDS`): 1 s between tries, each read's `timeout` the smaller of 8 s and the seconds left in the budget, no try started with under 1 s left; then it fails as today (exit 1, same stderr line). The budget fits the production caller: decision.sh wraps answer-worker in `timeout 20` (decision.sh:74), so the list phase ends by 12 s and leaves 8 s for the send, which in main's foreground returns at once (the wait detaches, answer-worker.sh:362-365). A first read that hangs its full 8 s leaves one try of up to 3 s
- Never done by a recovery (the owner's list): deleting uncommitted work, branches or worktrees with unmerged commits, money, production, security, and any recovery whose row already exists (it reports `recovery failed once: <what>` through `post`)

## Helper removal

- Scope: scripts/helper-apply.sh, the #591 removal tied to its apply (cut CF2)
- #591 helper removal: new `scripts/helper-apply.sh <child-worktree>` applies the child's whole delta to the current checkout: `B=$(git merge-base HEAD <child HEAD>)`, then `git -C <child> diff --binary $B` (the child's commits since the fork and its uncommitted edits, working tree against B) plus its untracked files (`git -C <child> ls-files -o --exclude-standard`), `git apply --check` first. A path in both the child's `diff --cached --name-only` and `diff --name-only` holds staged bytes the delta lacks: `REFUSED: <path> has staged content that differs from its working tree; nothing removed`. A tracked path the child's index hides from `git diff` (in `git -C <child> ls-files -v`, a lowercase tag is assume-unchanged and `S` is skip-worktree: the rule worktree-sweep.sh:24-25 already refuses on) is refused before any apply: `REFUSED: <path> is marked assume-unchanged or skip-worktree; nothing removed`. An ignored file (`git -C <child> ls-files -o -i --exclude-standard`: node_modules, __pycache__, settings.local.json, .gitignore:1-3) is in neither the diff nor the untracked list, so `--force` would delete it: before any apply, each one must exist in the parent with the same `git hash-object`, else `REFUSED: <path> is ignored and the parent lacks it or holds other bytes (<n> more); copy or delete it, then rerun; nothing removed`. Removal needs proof that every byte reached the parent: for each path in `git -C <child> diff --name-only $B` and each untracked path, `git hash-object` of the child's file equals the parent's (a deleted path is absent in both). Only then it removes the child with `git worktree remove --force` and its branch with `git branch -D`; one differing path prints `REFUSED: <path> differs after apply; nothing removed`. A helper that commits A and leaves B uncommitted thus lands A and B, or keeps its branch. It refuses a path that is not under `<main>/.claude/worktrees/` or the scratch folder, one that a live process uses (worktree-sweep.sh's lsof test, shared by sourcing nothing: the same four lines), and a diff that does not apply (nothing is removed). A new file because removal must be tied to the apply, and the sweep (worktree-sweep.sh) removes only what is over 24 hours old. templates/_builder-brief-template.md:93-97 says `run scripts/helper-apply.sh <child worktree>` instead of "git apply and remove that worktree"

## Template cuts

- Scope: the template sections CE3 cuts to one-line pointers (cut CE3, #653)

| Section cut | Template lines | Bytes | Script line that refuses | Test that proves the refusal |
|---|---|---|---|---|
| Screenshots rows (Issue 392) | 36-39 | 398 | scripts/merge-unit-local.sh:327 (`check_screens`: "screen code changed ... has no ## Screenshots ... row") | merge-unit-local-screens.test.sh:46 |
| Placeholder copy (Issue 398) | 40-42 | 314 | hooks/edit-content-tripwires.sh:309 (BLOCKED, names the `Placeholder: <file> \| <line> \| <why>` form) | edit-content-tripwires.test.sh:118-126 |
| Edit of an existing test | 138-144 | 520 | scripts/builder-codex-pass.sh:812 (prints the `Test edit:` lines to add and `--ack-rulings`) | builder-codex-pass-test-edit.test.sh:26 |
| Long reply in a file | 129-130 | 173 | hooks/long-reply-stop.sh:23-24 | hooks/__tests__/long-reply-stop.test.sh:19 |
| `grep -n` then a range (that clause only) | 68-69 | ~120 | hooks/read-range-guard.sh:18 | hooks/__tests__/read-range-guard.test.sh:14 |
| No poll loop on test output | 155-159 | 388 | hooks/no-poll-loops.sh:424 | hooks/__tests__/no-poll-loops.test.sh:15 |
| Never commit by hand (`Never push.` stays) | 234-235 | 114 | hooks/git-safety.sh:350 | hooks/__tests__/git-safety.test.sh:111 |
| Extra tests and the cap (134's second sentence-137; `- Each new test names the bug it catches.` stays: the cap refusal at :1644-1652 runs only past the cap, so no refusal enforces the naming rule) | 134-137 | 272 | scripts/builder-codex-pass.sh:1651 | scripts/__tests__/builder-codex-pass.test.sh:319 |
| Ask main at the new-test cap | 118 | 145 | scripts/builder-codex-pass.sh:1651 | scripts/__tests__/builder-codex-pass.test.sh:319 |
| Sites and New code checked (303-304, 307-308 stay) | 300-306 | ~690 | scripts/builder-codex-pass.sh:1585-1586, :1452-1453 | scripts/__tests__/builder-codex-pass-class-return.test.sh:64 |
| No Builder-added limit | 332 | 184 | scripts/builder-codex-pass.sh:1695 | scripts/__tests__/builder-codex-pass-limits.test.sh:70 |
| Failure-table row shape (sentence only) | 24-25 | ~150 | scripts/builder-codex-pass.sh:1639 | scripts/__tests__/builder-codex-pass.test.sh:260 |
| Break runs | 258-263 | 606 | scripts/builder-codex-pass.sh:1620-1621, extended | scripts/__tests__/builder-codex-pass.test.sh:239; new `break-run refusal names break-run.sh` |
| Post-merge list (line 7 stays) | 8-10 | 343 | scripts/merge-unit-local.sh:874-875, extended | scripts/__tests__/merge-unit-local.test.sh:257; new `post-merge refusal lists the allowed lines` |

## Parser inventory

- Scope: every production reader of Orca orchestration output CD4 tests (cut CD4, #588)

| Site | Verb, flag today | Fields read | Case |
|---|---|---|---|
| hooks/lib/project.sh:104, scripts/orca-wait.sh:76, scripts/board.sh:64, scripts/run-bound.sh:22, scripts/setup.sh:727 | run-current, concise | `.result.run.id` | run-current concise form fails loudly; every run-current site uses pp_orca_run_id |
| scripts/main-watch.sh:1741, scripts/close-done-panes.sh:138, scripts/unit-close.sh:46, scripts/dashboard.sh:150, scripts/poll-agents.sh:65 | task-list, concise (`--brief` at poll-agents) | `id`, `status` | task-list concise row without status is refused |
| scripts/dispatch-task.sh:92 | dispatch-show, concise | `assignee_handle`, `status`, `last_failure` | dispatch-show readers keep assignee and failure fields |
| scripts/paths.sh:685, scripts/paths.sh:735 | dispatch-show, concise | `dispatch`, `dispatch.id` | dispatch-show full form reads the dispatch id |
| hooks/lib/project.sh:106, scripts/run-bound.sh:31, scripts/cos-watch-inbox.sh:85, scripts/paths.sh:489 | run-list, `--full` | `runs[].id`, `coordinator_handle` | run-list full form reads the coordinator |
| scripts/board.sh:189, hooks/agent-awareness.sh:72, scripts/dispatch-task.sh:58, scripts/orca-wait.sh:466 | task-list, `--full` | per site | task-list full form reads open ids |
| scripts/inbox-drain.sh:68 | check `--unread --full` | `.ok`, rows | already `--full`; pinned by orca-full-flag.test.sh (unchanged) |
| scripts/main-watch.sh:315, :627, :1178, scripts/orca-wait.sh:550, scripts/paths.sh:475, :559, :662, scripts/dashboard.sh:1068, scripts/cos-watch-inbox.sh:90, scripts/cos-check.sh:22, hooks/cos-own-echo.sh:63, hooks/claude-worker-notify.sh:84 | inbox, `--full` | `.result.messages[]` `id`, `type`, `from_handle`, `to_handle`, `created_at`, `subject`, `body`, `thread_id`, per site | inbox full row missing a field leaves the other rows read |
| scripts/orca-wait.sh:107, scripts/poll-agents.sh:76-78, hooks/cos-own-echo.sh:61, scripts/ask-main.sh:25, :77 | check, `--full` (`--peek`, `--ack`, `--wait` per site) | `.result.deliveryId`, `.result.messages[]` `payload` (`taskId`), `body`, `type`, `from_handle` | check full batch missing payload is refused by pp_orca_full |
| scripts/orca-task-create.sh:30-32 | task-create, concise | the first `task_` string under any `.id` or `.taskId` | task-create reply yields the task id |
| scripts/dispatch-task.sh:78-89 | worker-start, concise | `.ok`, `.error.message` (and the `no longer bound` / `no_active_sender` text) | worker-start refusal reads the error message |
| scripts/to-main.sh:43-44, scripts/seat.sh:877-878, scripts/main-watch.sh:452, :611 (`orca_op '.ok == true'`, :486), scripts/cos-tell.sh:24-25, scripts/answer-worker.sh:133, scripts/paths.sh:720-738, hooks/claude-worker-notify.sh:115-119, hooks/codex-notify.sh:74-78 | send, reply, task-update, concise | `.ok` (cos-tell also a `msg_` id and no `not durable` text) | send and reply readers need ok true |

## Break lines


### C1
Break: scripts/__tests__/unit-drive.test.sh -- unasked question raises NEEDS-MAIN once -- unit-drive.sh question_gate re-send
Break: scripts/__tests__/decision.test.sh -- missing field still refuses -- decision.sh fold

### C2
Break: scripts/__tests__/unit-drive.test.sh -- same name in another project refuses -- unit-drive.sh preflight
Break: scripts/__tests__/unit-drive.test.sh -- unproven Builder launch stops at launch -- unit-drive.sh launch wait
Break: scripts/__tests__/unit-drive.test.sh -- unstarted Builder is flagged within a minute -- unit-drive.sh launch flag

### C3
Break: scripts/__tests__/answer-worker.test.sh -- tool-result tag is not delivered -- answer-worker.sh prompt-row
Break: scripts/__tests__/answer-worker.test.sh -- queued-row tag is not delivered -- answer-worker.sh confirm
Break: scripts/__tests__/answer-worker.test.sh -- Codex user-message tag is delivered -- answer-worker.sh confirm filter

### CB1
Break: scripts/__tests__/seat-settle.test.sh -- turn-complete question settles a finished seat -- paths.sh pp_open_ask
Break: scripts/__tests__/seat-settle.test.sh -- turn-complete QUESTION still holds settle -- paths.sh pp_open_ask
Break: scripts/__tests__/seat-settle.test.sh -- working pane refused until retry ends -- seat.sh settle_seat

### CB2
Break: scripts/__tests__/read-verdict.test.sh -- verdict read through a lone surrogate -- json-clean.sh pp_json_clean
Break: scripts/__tests__/read-verdict.test.sh -- pair and escaped backslash are kept -- json-clean.sh pp_json_clean

### CC1
Break: scripts/__tests__/answer-worker.test.sh -- same unit in two projects refuses naming both -- answer-worker.sh unit

### CC2
Break: scripts/__tests__/serena-shared.test.sh -- child above cap is stopped and logged -- serena-shared.sh sweep
Break: scripts/__tests__/serena-shared.test.sh -- same-named folders in two repos get distinct homes -- serena-shared.sh start
Break: scripts/__tests__/serena-shared.test.sh -- existing project settings carry into the new home -- serena-shared.sh seed copy
Break: scripts/__tests__/serena-shared.test.sh -- user SERENA_HOME is the source of a per-unit home -- serena-shared.sh source home
Break: scripts/__tests__/serena-shared.test.sh -- child over cap during startup is stopped -- serena-shared.sh watch
Break: scripts/__tests__/serena-shared.test.sh -- running server without a watcher gets one -- serena-shared.sh adoption
Break: scripts/__tests__/serena-shared.test.sh -- same-named repos at two paths get distinct project folders -- serena-shared.sh K checksum

### CC3
Break: scripts/__tests__/decision.test.sh -- push ask without closing GO stays open -- decision.sh auto_push_answer
Break: scripts/__tests__/decision.test.sh -- push ask with red or absent check stays open -- decision.sh auto_push_answer
Break: scripts/__tests__/decision.test.sh -- push ask on another tip stays open -- decision.sh auto_push_answer
Break: scripts/__tests__/decision.test.sh -- push ask names production stays open -- decision.sh auto_push_answer
Break: scripts/__tests__/decision.test.sh -- mode off leaves push ask open -- decision.sh auto_push_answer
Break: scripts/__tests__/decision.test.sh -- push ask with no check proof stays a manual ask -- decision.sh push-ask add
Break: scripts/__tests__/merge-unit-local.test.sh -- closingGo is false on a narrowed GO with no closing pass -- merge-unit-local.sh closingGo
Break: scripts/__tests__/decision.test.sh -- auto push answer from the main checkout tells main once -- decision.sh auto_push_answer

### CD1
Break: scripts/__tests__/to-main.test.sh -- stored map older than its limit is read again -- paths.sh pp_pane_map
Break: scripts/__tests__/to-main.test.sh -- send to a closed mapped pane looks up fresh -- to-main.sh retry

### CD2
Break: scripts/__tests__/orca-wait-drain.test.sh -- reply with QUESTION body wakes main -- paths.sh wk_question
Break: scripts/__tests__/ask-main.test.sh -- reply marked read by another reader still arrives -- ask-main.sh from_full

### CD3
Break: hooks/__tests__/cos-inbox-waiter-stop.test.sh -- Fast lane stop arms its own poller -- cos-inbox-arm-stop.sh lane test
Break: scripts/__tests__/cos-watch-inbox.test.sh -- lane FYI note stays held -- cos-watch-inbox.sh lane _class
Break: scripts/__tests__/cos-watch-inbox.test.sh -- lane ignores the relay tag -- cos-watch-inbox.sh admit
Break: scripts/__tests__/cos-watch-inbox.test.sh -- first lane poll delivers unread addressed mail -- cos-watch-inbox.sh lane seq
Break: hooks/__tests__/duplicate-agent-guard.test.sh -- split beside a live agent is blocked -- duplicate-agent-guard.sh plan split
Break: hooks/__tests__/duplicate-agent-guard.test.sh -- replace of a busy pane still blocks -- duplicate-agent-guard.sh create
Break: hooks/__tests__/duplicate-agent-guard.test.sh -- split from another lane checks the target pane's worktree -- duplicate-agent-guard.sh split
Break: hooks/__tests__/duplicate-agent-guard.test.sh -- split naming no terminal is blocked -- duplicate-agent-guard.sh split unnamed
Break: hooks/__tests__/duplicate-agent-guard.test.sh -- split naming an unlisted terminal is blocked -- duplicate-agent-guard.sh unknown

### CD4
Break: scripts/__tests__/orca-output-parsers.test.sh -- run-current concise form fails loudly -- hooks/lib/project.sh pp_run_id_of
Break: scripts/__tests__/orca-output-parsers.test.sh -- run-current fallback works with no saved run in every reader -- paths.sh project.sh source
Break: scripts/__tests__/orca-output-parsers.test.sh -- task-list concise row without status is refused -- unit-close.sh task guard
Break: scripts/__tests__/orca-output-parsers.test.sh -- dispatch-show readers keep assignee and failure fields -- dispatch-task.sh dispatch-show

### CE1
Break: scripts/__tests__/fence-heading.test.sh -- four-space fence opens nothing -- fence.sh fence
Break: scripts/__tests__/fence-heading.test.sh -- fence line inside an HTML block opens no fence -- fence.sh fence
Break: scripts/__tests__/fence-heading.test.sh -- backtick span line opens no fence -- fence.sh fence
Break: scripts/__tests__/merge-rules.test.sh -- twin: backtick span line opens no fence -- merge-rules.py parse
Break: scripts/__tests__/merge-rules.test.sh -- twin: fence line inside an HTML block opens no fence -- merge-rules.py parse
Break: scripts/__tests__/fence-heading.test.sh -- script-prefixed word opens no HTML block -- fence.sh heading
Break: scripts/__tests__/merge-rules.test.sh -- twin: script-prefixed word opens no HTML block -- merge-rules.py heading_level
Break: scripts/__tests__/fence-heading.test.sh -- heading in fence is not a heading -- fence.sh heading
Break: scripts/__tests__/fence-heading.test.sh -- setext underline under a list item is not a heading -- fence.sh heading paragraph
Break: scripts/__tests__/fence-heading.test.sh -- less-than text before a heading keeps the heading -- fence.sh heading HTML
Break: scripts/__tests__/merge-unit-local.test.sh -- Post-merge heading closed is read -- merge-unit-local.sh post-merge awk
Break: scripts/__tests__/builder-codex-pass.test.sh -- failure table under indented heading -- builder-codex-pass.sh table_gate

### CE2
Break: scripts/__tests__/unit-drive.test.sh -- setext Question heading opens the gate -- unit-drive.sh qopen
Break: scripts/__tests__/unit-drive.test.sh -- Plan heading closed form is seen -- unit-drive.sh preflight

### CE3
Break: scripts/__tests__/merge-unit-local-screens.test.sh -- screens refusal shows the row forms -- merge-unit-local.sh check_screens
Break: hooks/__tests__/edit-content-tripwires.test.sh -- placeholder block shows the plan line form -- edit-content-tripwires.sh placeholder
Break: scripts/__tests__/builder-codex-pass-test-edit.test.sh -- test edit refusal shows the ruling line form -- builder-codex-pass.sh test-edit
Break: scripts/__tests__/builder-codex-pass.test.sh -- break-run refusal names break-run.sh -- builder-codex-pass.sh NOBREAK
Break: scripts/__tests__/merge-unit-local.test.sh -- post-merge refusal lists the allowed lines -- merge-unit-local.sh step 4
Break: scripts/__tests__/brief-template.test.sh -- cut sections leave a pointer naming the refusing script -- _builder-brief-template.md pointers

### CE4
Break: scripts/__tests__/unit-drive.test.sh -- live Builder is attached, never relaunched -- unit-drive.sh watch
Break: scripts/__tests__/unit-drive.test.sh -- REVIEW STOP stops with one line -- unit-drive.sh watch
Break: scripts/__tests__/unit-drive.test.sh -- refused merge stops with resume command -- unit-drive.sh watch
Break: scripts/__tests__/unit-drive.test.sh -- closed Builder pane stops -- unit-drive.sh watch
Break: scripts/__tests__/unit-drive.test.sh -- idle Builder stops after three polls -- unit-drive.sh watch
Break: scripts/__tests__/unit-drive.test.sh -- earlier merge of a reopened unit does not end the driver -- unit-drive.sh watch merged
Break: scripts/__tests__/unit-drive.test.sh -- merge refusal of an older tip does not stop -- unit-drive.sh watch refusal
Break: scripts/__tests__/unit-drive.test.sh -- merge refusal of an earlier attempted tip does not stop a newer HEAD -- unit-drive.sh tip

### CF1
Break: hooks/__tests__/context-clear-stop-why.test.sh -- held restart logs one why line -- context-clear-stop.sh held
Break: scripts/__tests__/dashboard-limit-restarts.test.sh -- held restart raises alert until new pane -- dashboard_limit.py main_events
Break: scripts/__tests__/dashboard-limit-restarts.test.sh -- held restart of another session stays apart -- dashboard_limit.py main_events key
Break: hooks/__tests__/context-clear-stop-why.test.sh -- background agent hold logs one why line -- context-clear-stop.sh held

### CF2
Break: scripts/__tests__/helper-apply.test.sh -- staged change hidden by working tree refuses removal -- helper-apply.sh staged
Break: scripts/__tests__/helper-apply.test.sh -- assume-unchanged edit in helper refuses removal -- helper-apply.sh ls-files -v
Break: scripts/__tests__/helper-apply.test.sh -- ignored file only in helper refuses removal -- helper-apply.sh ignored
Break: scripts/__tests__/main-watch-dead-seat.test.sh -- recovery ask line reaches post once -- main-watch.sh recover_tick ask
Break: scripts/__tests__/recover-stalls.test.sh -- driver crashed past its owner file is restarted once -- recover-stalls.sh R4 service
Break: scripts/__tests__/recover-stalls.test.sh -- refused restart leaves no once-row -- recover-stalls.sh row after start
Break: scripts/__tests__/recover-stalls.test.sh -- dead plan seat under a live driver waits for its stop -- recover-stalls.sh R4b live test
Break: scripts/__tests__/recover-stalls.test.sh -- ready Builder task with no pane relaunches once -- recover-stalls.sh R3b
Break: scripts/__tests__/recover-stalls.test.sh -- ready task with live pane is dispatched once -- recover-stalls.sh R3
Break: scripts/__tests__/recover-stalls.test.sh -- second driver death goes to the owner with the log -- recover-stalls.sh R4
Break: scripts/__tests__/recover-stalls.test.sh -- answered idle pane retyped once -- recover-stalls.sh R2
Break: scripts/__tests__/recover-stalls.test.sh -- unmerged unit pane is not closed -- recover-stalls.sh R1
Break: scripts/__tests__/recover-stalls.test.sh -- stopped unit with live idle Builder is kept -- close-done-panes.sh stopped
Break: scripts/__tests__/recover-stalls.test.sh -- answer sent as inbox reply with no turn is redelivered once -- recover-stalls.sh R2
Break: scripts/__tests__/recover-stalls.test.sh -- dead plan seat relaunches through the driver -- recover-stalls.sh R4b
Break: scripts/__tests__/unit-drive.test.sh -- start writes the args file before the service -- unit-drive.sh start args
Break: scripts/__tests__/helper-apply.test.sh -- path outside helper folders is refused -- helper-apply.sh path guard
Break: scripts/__tests__/helper-apply.test.sh -- diff that does not apply removes nothing -- helper-apply.sh apply check
Break: scripts/__tests__/helper-apply.test.sh -- committed helper change is applied before removal -- helper-apply.sh hash compare
Break: scripts/__tests__/answer-worker.test.sh -- unread pane list is retried -- answer-worker.sh list read

### CF3
Break: scripts/__tests__/cos-supervise.test.sh -- event consumed before shutdown is published at next start -- cos-supervise.sh drain
Break: scripts/__tests__/cos-supervise.test.sh -- long crit alert summary still wakes -- cos-supervise.sh text class
Break: scripts/__tests__/cos-supervise.test.sh -- other watcher's later delivery does not ack an earlier event -- cos-supervise.sh ack
Break: scripts/__tests__/cos-supervise.test.sh -- refused send stays pending -- cos-supervise.sh turn_started
Break: scripts/__tests__/cos-supervise.test.sh -- units watcher runs under the supervisor -- cos-supervise.sh child list
Break: scripts/__tests__/cos-supervise.test.sh -- alert killed at its seen mark is still in its wake file -- cos-watch-alerts.sh print
Break: scripts/__tests__/cos-supervise.test.sh -- limit line killed at its told mark is still in its wake file -- cos-watch-limit.sh print
Break: scripts/__tests__/cos-supervise.test.sh -- idle unit killed at its seen mark is still in its wake file -- cos-watch-units.sh print
Break: scripts/__tests__/cos-supervise.test.sh -- dead watcher is restarted and logged -- cos-supervise.sh child loop
Break: scripts/__tests__/cos-supervise.test.sh -- third death in ten minutes wakes -- cos-supervise.sh deaths
Break: scripts/__tests__/cos-check.test.sh -- clean check line does not wake -- cos-check.sh clean branch
Break: scripts/__tests__/cos-check.test.sh -- dead supervisor is reported down -- cos-check.sh supervise
Break: scripts/__tests__/cos-supervise.test.sh -- decision line wakes once -- cos-supervise.sh classify
Break: scripts/__tests__/cos-supervise.test.sh -- second supervisor is refused while one runs -- cos-supervise.sh flock
Break: scripts/__tests__/cos-supervise.test.sh -- supervisor exit stops its children -- cos-supervise.sh EXIT trap

### CF4
Break: scripts/__tests__/context-rank.test.sh -- tool result bytes are ranked by tool key -- context-rank.sh rank
Break: scripts/__tests__/context-rank.test.sh -- unreadable log is named not skipped -- context-rank.sh read
Break: scripts/__tests__/paths-cut-output.test.sh -- output under the cap passes whole and saves no file -- pp_cut_output

### CG1
Break: scripts/__tests__/orca-native-trial.test.sh -- pass refused with poller running -- orca-native-trial.sh record_result
Break: scripts/__tests__/orca-native-trial.test.sh -- fail keeps why and old path -- orca-native-trial.sh record_result
Break: scripts/__tests__/orca-native-trial.test.sh -- junk record reads as unrun -- orca-native-trial.sh read_result

### CG2
Break: hooks/__tests__/cos-inbox-waiter-stop.test.sh -- relay stop starts no poller -- cos-inbox-arm-stop.sh pane test
Break: scripts/__tests__/cos-supervise.test.sh -- inbox poller text wakes through the supervisor -- cos-supervise.sh child list

### CG3
Break: scripts/__tests__/answer-worker.test.sh -- ended pane gets orchestration send -- answer-worker.sh main
Break: scripts/__tests__/answer-worker.test.sh -- ended pane with open question gets follow-up and thread reply -- answer-worker.sh QID
Break: scripts/__tests__/main-watch-inbox-wake.test.sh -- mixed send record keeps the typed wake for the Codex pane -- main-watch.sh inbox_wake
Break: scripts/__tests__/main-watch-inbox-wake.test.sh -- a reply to a passed pane keeps the typed wake -- main-watch.sh inbox_wake reply
Break: scripts/__tests__/answer-worker.test.sh -- PC send pass leaves a Mac Codex pane typed -- paths.sh pp_send_form
Break: scripts/__tests__/answer-worker.test.sh -- closed seat pane reopened by its dispatch gets the answer -- paths.sh pp_follow_up
Break: scripts/__tests__/answer-worker.test.sh -- closed pane without a closed-send pass keeps the refusal -- paths.sh pp_follow_up gate
Break: scripts/__tests__/seat.test.sh -- revise of a closed seat reopens it by dispatch -- seat.sh revise

## Catches

- Layout: what each cut catches, one line per cut (moved from the cut bodies)

- C1 catches: a `- none` plan held for ever (#657); a question main never got, unseen; a host answer dropped for its `unit` key (#662)
- C2 catches: two projects' units sharing one name (#648); `driver inactive with no log` after a clean launch, and a Builder pane left on an undispatched task (#659)
- C3 catches: "delivered" for an answer still queued in an ended pane (#658)
- CB1 catches: a judge's GO posted as a `question` that keeps `seat.sh collect` at rc 4; a real "turn complete: QUESTION" wrongly dropped by the new skip; a `**F2 (P2):` finding missing from collect, wake, dashboard and board; a working-pane stop told as an unread-inbox stop
- CB2 catches: a seat report or inbox row holding a lone surrogate that turns a read into "cannot tell" (rc 2 from `pp_open_ask`), an empty read or a `--state` pinned at `unknown` (no turn start or end), so collect refuses or finds no verdict; a cleaner that eats a valid emoji pair or an escaped backslash
- CC1 catches: an owner's answer silently queued for the wrong project's unit, or waiting with no pane, when one unit name is open in two projects (#646).
- CC2 catches: a second repository's same-named worktree inheriting the first one's language servers (#649); a runaway language-server child going unseen (#650); a missing Serena hiding failed bridge cases (#652).
- CC3 catches: a push auto-answered on a tip that moved after the review (#610); a push auto-answered with a missing or red check, or the mode off; an auto-yes on a production-named commit.
- CD1 catches: a Builder whose main runs in the host project's checkout and sets no pane folder, whose question is queued and unseen (#638); a pane lookup that asks Orca on every call (#576); a closed pane served from the map after a refused send (#576)
- CD2 catches: a Builder `QUESTION:` sent as `Re: answer from main` held or hidden for 15 minutes (#641); a reply marked read by a stray watcher (#639)
- CD3 catches: a message to an idle lane pane that nobody reads (#614); an FYI note that wakes a lane (#614); a lane whose poller died and nothing says so (#614); a second agent split into the Fast lane beside a live one (#633)
- CD4 catches: a bound run read as no run because `run-current` printed `runId` (#588, every wake, board and setup would act as unbound); a task list without `status` read as no open tasks (#588)
- CE1 catches: a gate that reads `Cuts`, `Post-merge`, `Limits` or `Failure table` under an indented, setext or closed heading as "no section", or reads text inside a fenced example as a section; each site has a red case in its own test file.
- CE2 catches: a plan whose question section is written `Question for the owner` with a setext underline reads as "no question", so the Builder launches over an open question; a batch with `## Plan ##` gets a second Plan section appended.
- CE3 catches: a Builder brief that contradicts the pass script on the pass rule; a template cut whose script refusal does not carry the right action, so the Builder loses the instruction (the new cases fail if a refusal text drops the form or a pointer line goes).
- CE4 catches: a re-run that launches a second Builder over a live one; a unit that stops after its first fix round; a REVIEW STOP, refused merge or closed pane that no one is told about; a driver that exits right after launch (today) while the unit idles.
- CF1 catches: a restart held for a reason nobody can see (#615 body 2); a session past the line whose restart never starts (#615 body 3)
- CF2 catches: a Builder idle on an answer that sits in its inbox (#663-1); a Builder pane whose task stayed ready (#663-2); a dead driver that nobody restarts (#663-3, #663-10); a seat that stopped without a verdict relaunched forever (second exit goes to the owner); panes left open after a merge (#663-5); a delivery lost to one unreadable list (#663-6); a helper worktree left after its diff was applied (#591)
- CF3 catches: a clean 50-minute check waking the relay (#655); a dead watcher found only by a Stop hook turn; a routine alert paying a whole turn
- CF4 catches: guessing which wake to hold (#608); a held wake that was not in the top of the list
- CG1 catches: a trial that reports pass while a poller still runs (the wake would be the poller's, not Orca's); a pass written from a half-finished run; a junk record that unlocks a removal; a removal that lands while its trial is `fail` or `unrun`.
- CG2 catches: a relay Stop starting a second poller beside the supervisor's; a relay with no poller; a lane that lost its poller; a tree file naming a deleted wait script.
- CG3 catches: an order typed into a finished pane that is never submitted (the bug these removals cover); a follow-up sent to a closed worker that starts no turn; text that still tells the owner a typed wake sat unsent.
- CH1 catches: a reopened unit whose judge answered NO-GO drawn as Waiting on main with Build done; a pane command that skips `ui.open` because the poll opened the pane unplaced.
- CH2 catches: a context gauge fed from the wrong key; a compaction count of 0 shown for an unreadable log; a unit log that reads the whole file every poll.
- CH3 catches: a gauge not red at the line; a dot red for GO; a section header drawn above no rows; a card line that grows past the width in `mini`; a lane cell for a stage that has no history.
- CH4 catches: a band row 2 without the context of the busiest Builder; a status line that puts the spend ahead of a refused merge; a key press that writes a file.

## Builder checks

- Builder check (before C1): run scripts/__tests__/startup-size.test.sh and seat-plan-marker.test.sh with the new sentence; green: go on; a size check red: shorten the sentence to `No question: None: <reason>.` and run again
- Builder check (before C3): find the #658 case: an `answer-worker-<tag>.log` in the scratch folder saying `inbox as a reply`, then a typed answer to the same pane in wake-log.jsonl within 60 min; list that tag's rows by type in the pane's session log; a queue-operation or attachment row only: build as planned; a user row: build as planned and leave #658 `Refs` with what was found; no such case: build as planned, note it in Progress notes
- Builder check (before CB1's #636 step): run a driven unit in a real Orca. Per finished seat (3 seats of the kinds plan-judge, plan-author, reviewer), once its report holds its VERDICT, run `for i in $(seq 1 24); do bash -c '. scripts/codex-helpers.sh; pane_is_busy <handle>; echo $?'; sleep 5; done` and note the first second the pane reads idle (exit 1). Outcomes: all 3 idle within 30 s and `seat.sh collect` ends rc 0 with no PP_VERDICT_READ -> restore (write the restore step and its test); any pane reads working past 60 s after its VERDICT, or the 3 differ -> keep off: write the reason (the pane-state source `worktree ps` is separate from the inbox `--full` read, paths.sh:661; the pane still lags its turn end) as the comment above `settle_seat` and in the plan Progress; a trial cannot be run (no Orca) -> keep off for now, issue stays partial
- Builder check (before CB1's #647 test): `rg -l 'reports\.md' scripts/__tests__/dashboard*.test.sh` picks the dashboard test file that already builds a unit with a report; if none builds findings, add the case to scripts/__tests__/dashboard-built-units.test.sh with a report written in its setup
- Builder check (before CB2 is called done): the "are missing plan-judge-sol verdicts caused by this" half. For each of the 5 stopped judge seats the issue names (or the 5 newest with no verdict), find the session log (`bash scripts/read-verdict.sh --seat <unit> plan-judge-sol`; else `rg -l 'plan-judge-sol' ~/.commandeck/scratch`) and run `grep -ciE '\\u[dD][89a-f]' <log>`, then `jq -e . <log> >/dev/null; echo $?`. Outcomes: the jq parse fails on at least one of the logs and passes after `pp_json_clean` -> the surrogate caused those missing verdicts; keep the fix, close #660; every log parses and no lone escape is found -> the surrogate is not the cause of the stops: keep the fix (it is still a real read error), mark #660 `Refs`, and write the next lead (the seat stops with no VERDICT line: read the last 20 pane lines for a turn that ended on a question or a limit) in the plan Progress; no log can be found -> partial, same note
- Builder check (before CC1): reproduce #646 at HEAD: two projects with a worktree of the same folder name, one Builder pane live in the other project only; run `bash scripts/relay-order.sh` for an answer to the first project's unit. Outcomes: exit 3 and `queued` for a pane that exists elsewhere = the fault is the missing-pane queue path, build as planned; delivered to the wrong project's pane = the pane match is by name somewhere else, find it with `rg -n 'basename|##\*/' scripts/answer-worker.sh scripts/paths.sh`, name it in the PR and refuse there too; delivered correctly = #646 is already fixed by path matching, keep only the test and close with the test as proof.
- Builder check (before CC2) #652: on the second machine that has Serena, run `bash scripts/__tests__/serena-shared.test.sh` and the four failing cases. Outcomes: all pass = the failure was a missing `mcp` module in that machine's Serena python (`$REALPY -c 'import mcp'`), note it in the PR and change the guard at :166 to name that cause in the SKIPPED line; the four fail with a real Python = run the bridge by hand against a real server (`serena-shared.sh start <wt>`, then `serena-shared.sh seat-args codex <address>`, one `find_symbol` call by a Codex seat): a working call = fix the test setup (the stub server in the test), a broken call = fix scripts/serena-bridge.py and keep #652 open until a real seat call passes. This machine already passes (run 2026-11-04: `11 passed, 0 failed`).
- Builder check (before CC2) #649: on this machine start a worktree before and after the change with an existing `~/.serena`: `serena-shared.sh start <wt>` then `status`. Outcomes: answers and `language_servers` appear in the worktree's own `project.yml` = keep; the first start downloads language servers again = the symlink to `language_servers` is wrong, fix the link target before merging.
- Builder check (before CC3): after the first merge on the new build, `tail -1 ~/.commandeck/builds/<project>.jsonl | jq '{checkRun, closingGo}'`. Outcomes: `green` and `true` = go on; `none` for a unit that had a testCommand = `CHECKED` is set after the row write on some path, move the field read; `null` = the row write was not reached, re-read :899.
- Builder check (before CD1): in the layout of #638, read `$PP_SCRATCH/current-run` from a Builder pane and run `pp_run_coord` on it. A live coordinator handle: go on. Empty or no file: the run file is not shared with that main; stop and ask main whether the host's main writes the run file under the plugin's scratch (board.sh is its one writer, paths.sh:64-67); until answered, ship only the pane map (#576) and mark #638 partial.
- Builder check (before CD2): feed the issue's message (type `status`, then `reply`, then `question`; subject `Re: answer from main`; body `QUESTION: x`) through `pp_inbox_actionable` and the drain's KEEP with a fake Orca, and say which rule held it. Class `batch` (held, not woken): the plan stands. Dropped as a repeat: the Builder's earlier identical row was in the page; record it and keep the rule (a repeat is by design). Hidden by KEEP's `noisy` or `harness`: add `wk_question` to the KEEP select only and say so in the commit message.
- Builder check (before CD3), #633 routes: for each route (`terminal create`, `terminal split`, `terminal send` of an agent command into a shell pane, `orchestration worker-start --agent`, `worktree create --agent`, a script's own `orca-ide` call) run `hooks/duplicate-agent-guard.sh` against a fake Orca that lists one live agent pane in the lane, and run `seat.sh launch` and `builder-launch.sh` pointed at the lane folder. Only `split` passes (as read now): go on. A further route passes: add it to the same `create` line and a test per route. A script route opens a second pane (`open_pane` finds panes by title or handle, codex-helpers.sh:116-124): make `open_pane` refuse a worktree with any live agent pane, and add the case. Also read `~/.commandeck` hook-fire logs for a `second-agent` row in the lane to see which route it was; no row: record that no live proof exists.
- Builder check (before CD3), lane start: `orca-ide orchestration inbox --limit 5 --full --json | jq '.result.messages[0] | keys'` from a lane pane. A read flag is present (for example `read` or `read_at`): the lane seed uses it. None: the lane seed instead uses `orca-ide orchestration check --terminal <lane handle> --unread --full --json` (the unread view inbox-drain.sh:68 reads) and seeds before its oldest row; neither readable: the lane seeds at place 0 for its own handle's rows newer than the pane's start epoch, so mail since the pane opened is printed once.
- Builder check (before CD3), #614 state: the lane's first Stop starts the poller. In `cos-watch-inbox.sh` read lines 100-235 for any use of the relay name or the run beyond the three places above (`owedf`, `sent`); one found: skip it for a lane the same way and add a case.
- Builder check (before CD4), capture first: on Orca 1.4.246 or later, from a pane bound to a run, save `orca-ide orchestration run-current --json`, with and without `--full`; `task-list --run <run> --json`, with and without `--full`; `dispatch-show --task <id> --json`, with and without `--full`; `run-list --json` and `--full`; `orchestration inbox --limit 5 --full --json`; `orchestration check --peek --full --json`; in a throwaway run, `task-create`, `worker-start` (one accepted, one refused), `send`, `reply` and `task-update` with `--json`. Into `scripts/__tests__/fixtures/orca-1.4.246/<verb>-{concise,full}.json` with ids replaced by `run_1`, `task_1`. Outcomes: concise `run-current` holds `result.runId` and no `result.run` (as the unbound capture in Assumptions shows): `--full` and the loud guard are needed. `task-list` concise keeps `id` and `status`: those readers (below) get a fixture test only, no flag. A concise `task-list` row lacks `id` or `status`: add `--full` there too. A concise `dispatch-show` lacks any of `assignee_handle`, `status`, `last_failure` (dispatch-task.sh:92) or `dispatch.id` (paths.sh:685, :735): add `--full` at that site and its fixture case checks the field; it keeps them all: those sites get the fixture case only, no flag. Cannot capture (no run): the cut is partial; write the fixtures by hand from the two unbound captures plus the header of orca-full-flag.test.sh and say so.
- Builder check (before CE1): run `for f in plan-stale-fence plan-check-placeholder-fences seat-fence builder-launch merge-unit-local-cuts; do bash scripts/__tests__/$f.test.sh | tail -2; done` after the `fence()` indent change. All pass -> keep D2. One fails on a fixture with a fence indented 4 or more spaces -> keep `fence()` unbounded for that case, record it in Facts, and bound only `heading()`; do not edit the fixture.
- Builder check (before CD4 is called done): `rg -n 'orchestration [a-z-]+' scripts hooks --glob '!**/__tests__/**'`, every verb, and keep each line whose output reaches `jq`, `grep` or a `case` (a line that only prints help text or a permission pattern, such as board.sh:102 or worktree-setup.sh:93, is no parser). Every such site is in the Parser inventory -> done. One is not -> add its row and a fixture case before #588 closes.
- Builder check (before CE1): `rg -n 'sed -n .*\^#|awk .*\^#' scripts hooks --glob '!__tests__'` and name any heading reader the 14 sites missed. None -> go on. Any -> add it to CE1 with a red case.
- Builder check (before CE2): `rg -n 'qopen|qsection' scripts/unit-drive.sh` after C1 merged. The names are unchanged -> edit them. Renamed by C1 -> follow the new names.
- Builder check (before CE3): after rules-port merged, run the rg above. No hit -> add only the test. A hit in a file outside rules-port's list -> reword it to the one rule and name it in the Done notes.
- Builder check (before CE3): `for t in brief-template template-sections test-rules plugin; do bash scripts/__tests__/$t.test.sh | tail -1; done` after the cut. All pass -> done. One fails on a cut bullet -> restore that bullet and record it in Facts; never edit the check.
- Builder check (before CE4): `rg -n 'resume' scripts/builder-launch.sh | head` and `ls scripts/__tests__ | grep builder-launch-resume`. A resume entry exists -> the `builder` stop names it. None -> the stop names `builder-launch.sh --from-plan` and the test pins that text.
- Builder check (before CE4): `ls "$PP_SCRATCH/main-watch/" | head` in a unit that merged. `merge-<unit>` and `mergejob-*.rc` present as main-watch.sh:68, :1139-1147 write them -> use them. Different -> read the merge log named by `merge-<unit>` line 2 for a `merge-queue: <unit> merged; ` line instead.
- Builder check (before CE4): a live Orca trial (one Builder pane, kill its pane, re-run `unit-drive.sh start`) cannot run in the plan; the stubbed test covers attach and stops. Trial attaches and prints no launch line -> done. Trial launches a second Builder -> `pp_seat_pane` misses the pane; read `handle=` from `seat-<unit>-builder.txt` instead and mark #651 partial until a second trial passes.
- Builder check (before C4): `git log --oneline --grep='feat(rules-port-2026-11-04)' main` names a commit: rebase on it and take the next minor; none: C4 waits and main is asked

## Steps

- modify scripts/unit-drive.sh ~176 -- lone none closes; re-send and NEEDS-MAIN
- modify scripts/unit-drive.sh ~331 -- C2: driver log, DONE line, 60 s FLAG line, launch-end stop; `now` helper
- modify scripts/unit-drive.sh ~100 -- CF2: start writes `drive-<unit>.args` (4 lines) under the lock
- modify scripts/decision.sh ~56 -- fold reads rows with extra keys; a missing key still refuses
- modify scripts/seat.sh ~614 -- plan-author spec names `None: <reason>`
- modify scripts/orca-wait.sh ~446 -- a route after `next: ` too
- modify scripts/answer-worker.sh ~337 -- tag counts only in a prompt row after the send
- modify scripts/read-verdict.sh ~87-94 -- `--state` prints `start=`
- modify scripts/__tests__/read-verdict.test.sh -- the turn-start case
- modify scripts/board.sh ~264 -- an idle Builder on an open question is listed as stopped
- modify scripts/__tests__/{unit-drive,decision,orca-wait,answer-worker,board,seat-plan-marker}.test.sh -- the new cases
- modify docs/commands.md ~93 -- refusal, driver log, NEEDS-MAIN
- modify docs/troubleshooting.md ~28 -- an answer counts once its turn has it
- modify scripts/paths.sh ~659-675 -- `pp_open_ask`: skip a turn-complete note unless it reads QUESTION or BLOCKED
- modify scripts/paths.sh ~711-717 -- `pp_task_close`: refusal split into working-pane and unread-check lines
- new scripts/json-clean.sh -- `pp_json_clean`
- modify scripts/paths.sh ~1563 -- source json-clean.sh
- modify scripts/paths.sh ~661 -- `pp_open_ask` reads the inbox through `pp_json_clean`
- modify scripts/seat.sh ~850 -- collect summary pattern takes the bold `(P[0-3])` form
- modify scripts/seat.sh ~906-915 -- `settle_seat` waits for an idle pane before `PP_VERDICT_READ=1`
- modify scripts/orca-wait.sh ~185 -- `enrich` pattern takes the bold `(P[0-3])` form
- modify scripts/orca-wait.sh ~531-533 -- drained check output through `pp_json_clean`
- modify scripts/read-verdict.sh ~469 -- `fetch` through `pp_json_clean`
- modify scripts/read-verdict.sh ~633-670 -- `codex_report` and `claude_report` read the log through `pp_json_clean <file>`
- modify scripts/read-verdict.sh ~168 -- `session_state` reads through json-clean.sh
- modify scripts/dashboard.sh ~269 -- `builder_progress` count takes the bold `(P[0-3])` form
- modify scripts/board.sh ~179 -- finding counts take the bold `(P[0-3])` form
- modify scripts/__tests__/seat-settle.test.sh ~46 -- turn-complete, refusal-split, collect summary, surrogate inbox cases
- modify scripts/__tests__/seat-settle.test.sh ~30 -- if the #636 check restores: the retry case
- modify scripts/__tests__/orca-wait.test.sh ~96 -- wake summary bold case and lone-surrogate drain case
- modify scripts/__tests__/read-verdict.test.sh ~31 -- lone-surrogate and pair-kept cases; ~140 the state case
- modify scripts/__tests__/board.test.sh ~70 -- bold finding count case
- modify scripts/__tests__/dashboard-built-units.test.sh -- bold finding count case (file per the CB1 Builder check)
- modify CHANGELOG.md -- one line per user-visible change (C4 owns the file; added after its draft)
- modify scripts/answer-worker.sh ~85 -- two-candidate refusal: same unit name in another project, no pane here
- modify scripts/__tests__/answer-worker.test.sh -- the two-project cases
- modify scripts/serena-shared.sh ~31 -- add `sweep` to the command list
- modify scripts/serena-shared.sh ~88 -- start: Serena home per repository and unit (`pp_project "$WT"`), `SERENA_HOME`, watch loop
- modify scripts/serena-shared.sh ~122 -- `stop` arm removes H (pp_rm_rf), keeps P
- modify scripts/serena-shared.sh ~120 -- new `sweep` function and case arm
- modify scripts/__tests__/serena-shared.test.sh ~215 -- SKIPPED line, nested no-Serena run, the CC2 cases
- modify scripts/merge-unit-local.sh ~899 -- merged row gains `checkRun` and `closingGo`
- modify scripts/__tests__/merge-unit-local.test.sh -- the three merged-row cases (names in Acceptance)
- modify scripts/decision.sh ~345 -- push-ask calls new `auto_push_answer`; header comment
- modify scripts/__tests__/decision.test.sh ~46 -- six push-ask auto-answer cases
- modify scripts/__tests__/relay-order.test.sh -- owner's no reverses an auto-answered push
- modify docs/commands.md ~106 -- /autodecide section: a push ask meeting the gates is answered by script and logged
- modify docs/troubleshooting.md ~27 -- the Serena watch log path and its `killed` line (CC2)
- modify scripts/paths.sh ~1061 -- new pp_pane_map; pp_pane_of and pp_seat_pane read it
- modify scripts/to-main.sh ~50 -- the second look reads fresh
- modify scripts/ask-main.sh ~25 -- from_full function; called after an empty pass and after the loop
- modify scripts/paths.sh ~595 -- wk_question inside wk_required
- modify scripts/orca-wait.sh ~272 -- KEEP passes wk_question
- modify hooks/cos-inbox-arm-stop.sh ~24 -- lane panes arm a lane poller
- modify scripts/cos-watch-inbox.sh ~92 -- --lane: own key, own-handle admit, notes held, lane seed (~122)
- modify scripts/cos-check.sh ~16 -- lanes, units, supervise in the down line; quiet clean check
- modify hooks/duplicate-agent-guard.sh ~180 -- split checked; COMMANDECK_REPLACE_PANE
- modify hooks/lib/project.sh ~104 -- pp_run_id_of, pp_orca_run_id
- modify scripts/{orca-wait,board,run-bound,setup}.sh -- run-current readers use pp_orca_run_id
- modify scripts/paths.sh ~57 -- source hooks/lib/project.sh
- modify scripts/{main-watch,close-done-panes,unit-close,dashboard,poll-agents}.sh -- task-list guards demand id and status
- modify scripts/dispatch-task.sh ~92 -- dispatch-show read by the capture's rule (`--full` where a read field drops)
- modify scripts/paths.sh ~685 -- the two dispatch-show reads (:685, :735) by the capture's rule
- new scripts/__tests__/orca-output-parsers.test.sh -- one case per parser against captured fixtures
- new scripts/__tests__/fixtures/orca-1.4.246/{run-current,task-list,dispatch-show,run-list}-{concise,full}.json -- captures
- new scripts/__tests__/fixtures/orca-1.4.246/{inbox-full,check-full,task-create,worker-start-ok,worker-start-refused,send,reply,task-update}.json -- captures
- modify scripts/__tests__/{to-main,ask-main,orca-wait-drain,cos-watch-inbox,cos-check}.test.sh -- the new cases
- modify hooks/__tests__/{cos-inbox-waiter-stop,duplicate-agent-guard}.test.sh -- the new cases
- modify docs/troubleshooting.md ~27 -- lane waiter fault, pane map, replace prefix
- modify scripts/fence.sh ~10 -- `fence()` opens at 0-3 spaces; add `heading()`, `hlvl`, `htxt`
- modify scripts/paths.sh ~1445 -- `pp_plan_section_paths` uses `heading()`
- modify scripts/paths.sh ~1682 -- `pp_plan_stale` Steps start and end use `heading()`
- modify scripts/builder-codex-pass.sh ~1419 -- `section_lines`, `evidence_section`, `table_gate`, LIMITS and DEFERRED awks use `heading()`
- modify scripts/merge-unit-local.sh ~320 -- Screenshots, close-as-shipped (~461), Cuts
- modify scripts/merge-unit-local.sh ~327 -- the screens refusal prints the three row forms
- modify scripts/seat.sh ~844 -- the report body starts at the first level-1 heading outside a fence
- modify scripts/merge-rules.py ~282 -- `heading_level` twin; the Details cut walks lines with fence state
- new scripts/__tests__/fence-heading.test.sh -- the reader's own cases (no test file covers fence.sh
- modify scripts/__tests__/{merge-unit-local-screens,merge-unit-local-cuts,merge-unit-local-deletions,merge-unit-local,plan-stale-fence,builder-launch,builder-codex-pass,seat-fence,merge-rules}.test.sh -- a red case per gate site
- modify scripts/unit-drive.sh ~61 -- `preflight` Plan heading uses `heading()`
- modify scripts/unit-drive.sh ~173 -- `qsection`/`qopen` use `heading()` (after C1)
- modify scripts/unit-drive.sh ~331 -- `watch_unit`, the attach check in `run`; header lines 2-23 name the new stages
- modify scripts/__tests__/unit-drive.test.sh ~323 -- reader cases and six driver cases
- modify scripts/__tests__/brief-template.test.sh ~110 -- the one-pass-rule and naming-rule cases
- modify templates/_builder-brief-template.md ~36 -- cut the fourteen CE3 sections to one-line pointers naming the refusing script
- modify scripts/__tests__/brief-template.test.sh ~21 -- delete :21, :59 and :176, narrow :58 (owner Q6 b); add the pointer case
- modify scripts/builder-codex-pass.sh ~1620 -- break-run refusal names break-run.sh
- modify scripts/merge-unit-local.sh ~874 -- post-merge refusal lists the allowed lines
- modify scripts/__tests__/merge-unit-local.test.sh ~257 -- post-merge refusal lists the allowed lines
- modify hooks/__tests__/edit-content-tripwires.test.sh ~126 -- placeholder block shows the plan line form
- modify scripts/__tests__/builder-codex-pass-test-edit.test.sh ~26 -- refusal shows the ruling line form
- modify docs/review-loop.md ~138 -- only if the rg check finds a leftover cap sentence after rules-port
- modify README.md ~283 -- unit-drive.sh now carries the unit to merge (the Builder-launch paragraph and :288)
- modify docs/commands.md ~93 -- `unit-drive.sh start` chain continues to merge, attach on a live Builder
- modify hooks/context-clear-stop.sh ~54 -- `held` function and its calls at the silent holds
- modify scripts/dashboard_limit.py ~1648 -- `restart: HELD:` line becomes `restartHeld`
- modify hooks/__tests__/context-clear-stop-why.test.sh -- session past the line restarts
- modify scripts/__tests__/dashboard-limit-restarts.test.sh -- held restart raises alert until new pane
- new scripts/recover-stalls.sh -- R1-R4b, once-only state, one-line reports
- modify scripts/main-watch.sh ~1782 -- `recover_tick` runs recover-stalls.sh, reads its lines
- modify scripts/__tests__/main-watch-dead-seat.test.sh -- the ask-line case
- modify scripts/close-done-panes.sh ~72 -- R1: both protections end for a merged or exited-stopped generation
- modify scripts/answer-worker.sh ~140 -- retry the two list reads
- modify scripts/answer-worker.sh ~366 -- follower log names its decision id (if the CF2 R2 Builder check finds none)
- new scripts/helper-apply.sh -- apply a helper diff, then remove its worktree and branch
- modify templates/_builder-brief-template.md ~95 -- name helper-apply.sh
- new scripts/__tests__/recover-stalls.test.sh -- the recovery cases
- new scripts/__tests__/helper-apply.test.sh -- apply and removal cases
- modify scripts/__tests__/close-done-panes.test.sh -- merged unit pane closed, unmerged kept
- new scripts/cos-supervise.sh -- the supervisor
- modify scripts/cos-watch-{alerts,limit,units}.sh -- print before mark
- modify hooks/cos-inbox-waiter-stop.sh ~76 -- supervisor line first in the reason
- new scripts/__tests__/cos-supervise.test.sh -- the supervisor cases
- modify hooks/agent-startup-context.sh ~139-144 -- supervisor and cos-check arm lines
- modify hooks/__tests__/agent-startup-context.test.sh -- the one-supervisor case
- new scripts/context-rank.sh -- rank context cost from session logs
- new scripts/__tests__/context-rank.test.sh -- ranking cases
- modify docs/{commands,troubleshooting}.md -- recoveries, supervisor, helper-apply, held restart line
- new scripts/orca-native-trial.sh -- trials wake, send, submit; `record_result`, `read_result`
- new docs/orca-native-trial.json -- the record, all three `unrun`
- new scripts/__tests__/paths-cut-output.test.sh -- cut filter, red first
- new scripts/__tests__/orca-native-trial.test.sh -- record writer, junk reader, three gate-consistency cases
- modify docs/troubleshooting.md ~37-48 -- retest heading to 1.4.241-1.4.248
- modify hooks/cos-inbox-arm-stop.sh ~24 -- drop the relay branch; lane panes only
- modify scripts/cos-supervise.sh -- the inbox poller joins the child list, class now
- delete scripts/await-agents.sh -- orchestrator wait script (only when wake passes)
- delete scripts/watch-agents.sh -- orchestrator watch script (only when wake passes)
- modify hooks/agent-startup-context.sh ~140 -- the poller line says the supervisor runs it
- modify scripts/poll-agents.sh ~40 -- comment naming the removed watch script
- modify docs/hooks.md ~37 -- arm hook row: lane panes only
- modify docs/chief-of-staff.md ~34 -- the supervisor starts the relay poller
- modify docs/troubleshooting.md ~26 -- "Relay is silent" checks the supervisor runs the poller
- modify hooks/__tests__/cos-inbox-waiter-stop.test.sh ~78-155 -- relay arm cases for a lane pane; add relay stop starts no poller
- modify scripts/__tests__/cos-supervise.test.sh -- inbox poller text wakes through the supervisor
- modify scripts/__tests__/to-main.test.sh ~304 -- drop the await and watch cases (needs Q10)
- modify scripts/paths.sh -- add `pp_send_form`, `pp_follow_up` (closed route, `--check`), `pp_cut_output`
- modify scripts/answer-worker.sh ~163 -- passed agent by `pp_follow_up`; re-type kept for reply-only, no-pass (DG9); closed pane by dispatch
- modify scripts/main-watch.sh ~316-335 -- `inbox_wake` skips a sent message to a passed agent's pane
- modify scripts/seat.sh ~301-327 -- revision by `pp_follow_up`; drop NO-WAKE; closed pane by dispatch
- modify scripts/builder-fresh-round.sh ~51-62 -- the order by `pp_follow_up`; `/clear` stays typed
- modify docs/troubleshooting.md ~27 -- answer-worker text
- modify scripts/__tests__/answer-worker.test.sh ~29 -- typed-answer stubs become orchestration send checks; add the new cases
- modify scripts/__tests__/seat.test.sh ~78 -- revision by orchestration send (needs Q10); closed case
- modify scripts/__tests__/builder-fresh-round.test.sh ~34 -- order by orchestration send (needs Q10)
- modify scripts/__tests__/main-watch-inbox-wake.test.sh -- 3 new cases
- modify scripts/__tests__/builder-add-work.test.sh ~49 -- count of `terminal send` becomes count of orchestration send
- modify scripts/__tests__/builder-codex-pass-fresh-round.test.sh ~84-160 -- same (needs Q10)
- modify scripts/dashboard.sh ~203-218 -- `replanning`: a post-Builder plan seat's NO-GO counts as re-planning
- modify scripts/dashboard.sh ~412 -- `bj` copies `tools` from `b`; ~449 `compactions`
- modify scripts/dashboard_builders.jq ~66 -- key `tools`: last 3 tool-starts, `running` from `$endedSet`
- modify hooks/units.tsx ~97-107 -- `enrich`: planning on a running plan seat or NO-GO judge
- modify hooks/units.tsx ~270-336 -- `pane on` always calls `ui.open`, reads `ui.panes()` and replies placed or waiting
- modify hooks/units.tsx ~215-229 -- `collect` reads the unit-events tail into `State.events`
- modify hooks/units.tsx ~338-363 -- pane width cap 120; Buttons for unit expand and d/t/l focus
- modify hooks/units-sources.ts ~93-125 -- CH2 `Row`, `Snap`, `State` fields, `parseSnapshot`
- modify hooks/units-sources.ts ~308-413 -- `FIGURE`, `paneModel` section order and layouts, `bandModel` row 2 context
- modify hooks/units-elements.ts ~92-171 -- the element functions (CH3)
- modify hooks/units-world.ts ~21-111 -- mock `ui.panes`, `w.placed`, helper to set up context, history, events
- modify types/index.d.ts ~5-35 -- new row, snapshot and state fields; `unitsExpanded`, `unitsFocus`
- modify hooks/units-panes.test.tsx -- the pane element cases and the re-planned unit case
- modify hooks/units.test.tsx -- band, status line and `pane on` cases
- modify hooks/units-sources.test.tsx -- parser cases for the new fields and the events tail
- modify scripts/__tests__/dashboard-built-planning.test.sh ~132-157 -- the NO-GO re-planning case (fixture `pr5`)
- modify scripts/__tests__/dashboard-built-seat-figures.test.sh -- compaction, tools, refused-tool, resumed-helper cases
- modify docs/dashboard.md ~187-252 -- the new elements, sources, placeholders, keys, layouts, `pane on` reply
- modify {CHANGELOG.md,.claude-plugin/plugin.json,README.md} -- notes, version, badge; after rules-port
- modify docs/configuration.md ~128 -- C4, after rules-port: main found as the run's coordinator (CD1's doc line)
- modify README.md ~32 -- C4, after rules-port: the lanes watch their inbox (CD3's doc line)
- modify README.md ~265 -- C4, after rules-port: `/units` row names the keys (CH4's doc line)

## Decisions already made

- D1 (#662): the `plan <hash8>` rule stays; only unknown keys stop being a fault. The issue lets the plan pick between id matching and a tagged host ask; id matching would let a same-named unit's answer in the other project release this gate, which an existing check pins (unit-drive.test.sh:316-320). The driver's message already tells main to keep the tag.
  Test: host row with unit field and tag releases
- D2 (#648): other projects are the repos Orca's repo list names, the source the driver already reads; any worktree there whose folder name is the unit refuses. An unreadable list warns once and starts, as the answer reader does.
  Test: same name in another project refuses; repo list unreadable starts with warning
- D3 (#657): the none forms are matched case-insensitively on the section's only non-blank line, list marker optional, one trailing period allowed; anything else stays open, so a misread costs a revision, never a skipped question.
  Test: qopen list none closed; quoted or trailing none stays open
- D4 (#657): one re-send per plan version per driver run; the NEEDS-MAIN line is said once.
  Test: unasked question raises NEEDS-MAIN once
- D5 (#659): the driver never re-dispatches; it stops with the dispatch command, so a task is never sent twice.
  Test: unproven Builder launch stops at launch
- D6 (#659): the log takes the name board.sh and orca-wait.sh already read, so neither reader changes its glob.
  Test: driver log ends with DONE
- D7 (#658): delivered means the tag is in a prompt row (never a tool result, except the result of the pane's own waiting call -- `ask-main.sh`, `orchestration ask` or `check` -- matched by its tool_use id or Codex call_id, which returned the answer to the model; pass 19, duplicate-answer) and the pane's turn started at or after the send, read by the new `start=` line C3 adds to `read-verdict.sh --state` (Codex: its `task_started` row; Claude: the tagged prompt row itself), as #658 Fix 2 asks ("Report delivered only once the pane has started a turn"); exit codes stay as they are.
  Test: queued-row tag is not delivered; ended turn with unread inbox answer is typed once; state output carries turn start; reply-only answer to an asking worker is typed once its turn ends, never when its waiting call returned the answer
- D8 (#658): the board's stop rule for an open question is 5 min idle on the session log.
  Test: idle Builder on open question listed stopped
- DB1 (#637): reuse orca-wait.sh's rule (a "turn complete" subject is a finish; "turn complete: QUESTION|BLOCKED" is a question) inside `pp_open_ask`, rather than make the poster type it differently, because the poster is Orca, outside the plugin; one rule for the two readers
  Test: turn-complete question settles a finished seat; turn-complete QUESTION still holds settle
- DB2 (#647): the bold form is `<id> (P<n>)` at line start, optionally after `- ` and `**`; a `(P2)` in the middle of a sentence is not a heading and is not counted (unit-drive.sh:328 matches it anywhere, but it only feeds a revise spec, where a wider net costs nothing)
  Test: collect summary shows bold P2 finding; wake summary shows bold P2 finding; board counts bold P2 finding; dashboard counts bold P2 finding
- DB3 (#660): replace a lone surrogate with U+FFFD, never drop the row, so the verdict line beside it is still read; fast path by `grep -q` for files
  Test: verdict read through a lone surrogate; pair and escaped backslash are kept; settle reads an inbox with lone surrogate; wake drain survives a lone surrogate; state reads a finished turn past a lone surrogate
- DB4 (#636): split the refusal as the owner picked first (a working pane and an unread check are two lines), then let live evidence pick restore or keep-off
  Test: working pane refusal names the pane; unread inbox refusal says unread
- DB5 (#636): the restore waits out the retry window before it trusts the read verdict, instead of refusing for good, because a refusal that ends the driver is the #631 fault
  Test: working pane refused until retry ends
- D1 (#649): the lever is a Serena home per repository and unit (`SERENA_HOME`), not a project name alone, because the Serena source resolves a registered project by name (error "Multiple projects found with name") and a `$projectFolderName` template keys the `.serena` folder by folder name; a distinct `project_name` fixes the first but not the second, a distinct home fixes both. The home is symlinks plus one config copy with the folder template pinned to `$projectDir/.serena`, so downloaded language servers are shared and nothing downloads twice.
  Test: same-named folders in two repos get distinct homes; single-repo worktree keeps its language servers
- D2 (#650): RSS of the process tree via `ps -axo pid=,ppid=,rss=,args=`, summed per direct child of the server, cap 2048 MB, a fixed constant (no setting: the issue names the cap, no caller needs another); a watchdog loop, not `ulimit`, because macOS does not enforce RSS limits and a child's children (the 40 GB case) must count. Sweep runs every 30 s inside `serena-shared.sh` and ends with the server.
  Test: child above cap is stopped and logged; normal-sized child is untouched
- D3 (#652): a missing Serena stays a skip (exit 0) but is named on screen twice (where it is skipped and after the totals), every one of the six checks of the guarded branch by its label (serena-shared.test.sh:196-213, the last the no-address refusal at :213); the no-Serena case fails when any of the six labels is missing from either line. A hard failure would break every machine without Serena, including the shell suite on the PC.
  Test: skipped cases are named without Serena
- D4 (#610 #656): one build, in `push-ask` (not the watcher), so every route that writes a push ask gets the same gate. The answer is the ledger answer plus main's tell; the script never pushes. "Production" is kept out by refusing any commit subject naming prod, production or deploy; this is a refusal list, so a deploy hidden under another word still gets the ask only if the owner turns the mode off (see QUESTIONS).
  Test: push ask names production stays open
- D5 (#610): the record is two fields on the existing merged row, not a new file: the merge already proves both facts, one writer, and the row is keyed by the commit sha so "exact tip" is a string compare with `refs/heads/main`.
  Test: merged row records closing GO and green check; push ask on another tip stays open
- DC6 (#610): `closingGo` is the verifier's own `rule: closing GO`, proved on this tip; a narrowed GO under `reviewLoop.closingPass` no, a first-pass GO, a cap stop and a threshold stop answer nothing and the ask stays manual (the safe side), since #610 names a closing final-review GO.
  Test: closingGo is true only on rule closing GO; closingGo is false on a narrowed GO with no closing pass; closingGo is false on a first-pass GO
- DC7 (#610): the automatic yes tells main itself: `answer` runs with `COMMANDECK_MAIN_TOLD=1`, then one to-main.sh send from any cwd, because tell_main returns in the main checkout (decision.sh:92), where `main-watch.sh --once` runs push-ask, and deliver_answer skips `decision.sh*` sources (:69). An answer recorded by hand keeps both suppressions. The answer is written before the send, so main never hears a yes the ledger lacks.
  Test: auto push answer from the main checkout tells main once; manual push answer in the main checkout sends main nothing
- D6 (#646): resolve by path (the asking project's `$PP_WORKSPACES/<unit>`, as pp_seat_pane already does), and only when this project has no pane and another project has the name, refuse naming both. Not a project-qualified unit syntax: no caller can supply one.
  Test: own project's pane wins over another project's; same unit in two projects refuses naming both
- DD1 (#638): main's pane is also the coordinator of the run in `$PP_RUN_FILE`, the source main-watch trusts; no new setting. The Builder env var (builder-launch.sh:427-437) stays the first fallback.
  Test: main pane found as run coordinator; recorded handle wins over coordinator
- DD2 (#638): with no pane at all `ask-main.sh` keeps exit 3, the queued line and no wait (existing check, ask-main.test.sh:102-103); nothing is queued silently because the line already says so. See Q5.
  Test: main down: the question is queued and the line says the answer arrives typed (existing)
- DD3 (#639): the issue offers two fixes; the wait reads by thread id (the second), because a refusal to start a second watcher needs every watcher start to take part and a stray one can be any shell job.
  Test: reply marked read by another reader still arrives; another question's read reply is not taken
- DD4 (#641): a body starting `QUESTION` wakes main by the one wake rule, and the drain keeps it out of hidden.jsonl; only repeats and true echoes stay hidden.
  Test: reply with QUESTION body wakes main; reply with QUESTION body is not hidden; plain answer echo stays held
- DD5 (#614): lanes reuse the relay's poller with `--lane`, not a new script; a new script would copy 250 lines of the sequence/held-note state. Admit only mail to the lane's own handle (a lane is not the relay).
  Test: lane ignores the relay tag; Fast lane stop arms its own poller; Research lane stop arms its own poller
- DD6 (#614): routine notes are the relay's FYI class (`wake_class`, paths.sh:599-608) held until the next wake or 30 minutes; no new definition of "routine".
  Test: lane FYI note stays held
- DD7 (#614): a lane waiter is a fault only when the lane has a live pane; a lane with no pane is the owner's normal state (setup.sh:773-777).
  Test: lane with no pane is no fault; lane pane with dead poller is named
- DD8 (#633): the guard is the lane's refusal; replace needs the named handle to be live in that worktree and idle, and the caller closes it.
  Test: replace of a busy pane still blocks; replace naming an idle live pane passes; replace naming another handle blocks
- DD9 (#576): the map is a 20 s cache of Orca's pane list, read by the two lookup sites; a send refused as `terminal_not_found` reads fresh. The one-long-watcher half: today the asyncRewake poller (hooks/cos-inbox-arm-stop.sh:2-9) is restarted by each Stop; after CG2 the relay poller runs under CF3's supervisor, which wakes the pane by a typed line and never exits per event (DF4).
  Test: pane map read once for two lookups; stored pane map older than its limit is read again; two wakes in a row re-arm the poller without a turn
- DD10 (#588): a verb gets `--full` only where its concise form lacks a field the parser reads; the guard on a parser that needs `status` or `run` fails loudly rather than reading empty.
  Test: run-current concise form fails loudly; task-list concise row without status is refused
- D1 (#640): the reader is an awk function in fence.sh's PP_AWK_FENCE, because every awk gate already includes it and `fence()` is its state; merge-rules.py gets a twin because Python cannot include awk. One test table drives both.
  Test: indented heading ends a section; Details heading closed form splits template
- D2 (#640): a fence opens only at 0-3 spaces of indent. Four or more is indented code, not a fence; a longer indent that opened a fence swallowed later headings and let a gate read fewer lines. Nested-list fences are the cost: they read as text, which makes gates read more.
  Test: four-space fence opens nothing
- D3 (#640): a section starts on a loose title match and ends only on a strict heading, per section_lines' own rule (builder-codex-pass.sh:1416-1418): a wrong end only adds lines, so a gate refuses more. Where a gate needs the opposite (none known), it names it.
  Test: limits section ended by setext heading
- D4 (#651): extend unit-drive.sh. A second driver would split the lock, owner file and stop line.
  Test: live Builder is attached, never relaunched
- D5 (#651): "live" is `pp_seat_pane` (the read main uses for the same pane), not a new check, so main and the driver agree.
  Test: live Builder is attached, never relaunched; no live Builder runs plan stages first
- D6 (#651): the Builder drives its own passes and fix rounds, and main-watch merges (gate at main-watch.sh:1083). The driver does not run passes; it watches, and stops on what main would have had to act on.
  Test: fix round does not end the driver
- D7 (#653): a section is cut only when a script refuses its wrong action and the refusal says the right one, with a test that proves the refusal; where a check pins the cut text, that check is edited (D10). Fourteen sections, about 4,460 bytes.
  Test: screens refusal shows the row forms; placeholder block shows the plan line form; test edit refusal shows the ruling line form; cut sections leave a pointer naming the refusing script
- D8 (#654): no code change. rules-port makes the rule; CE3 only checks, fixes leftovers and pins it.
  Test: template docs and script state one pass rule
- DF1 (#663): a recovery writes its once-row before it acts, so a crash between the two skips a recovery and never repeats one; the start routes (R3b, R4, R4b) write it after a start that exits 0, since a start the live driver or its lock refuses has done nothing; the row key is recovery + unit + condition, so a new condition of the same unit acts again.
  Test: recovery row blocks a second act
- DF2 (#663): R1 closes a pane only when the unit's branch tip is in main or the unit has a STOP/DONE line; a unit with unmerged commits and a live agent is never closed (the owner's list).
  Test: unmerged unit pane is not closed
- DF3 (#663): the second driver death for a unit, and a second exit of a relaunched seat, are questions with the log tail; the recovery never loops.
  Test: second driver death goes to the owner with the log
- DF4 (#655 #576): the supervisor types a `now` line into its pane and keeps running (one long-lived watcher, #576), exiting only after a third refused send of one line or on the three-deaths exception; a held (`batch`) line rides the existing held-notes file, so no new queue exists. Drain: a watcher marks its records seen when it prints them (cos-watch-decisions.sh:22-24, cos-watch-alerts.sh:87-89) and cos_wait writes that output to a wake file first (cos-lib.sh:20-21), so each wake file is acked by name in `$COS_KEY.supervise.acked` only after its own delivery (`turn_started` in the send receipt or the text accepted into the busy pane's queue, appended to the held notes, or dropped by rule), never by a time stamp: watcher B's file written at T1 stays pending when watcher A's later file is delivered at T2. At start the supervisor publishes, oldest first, every non-empty `$COS_KEY.*-wake-*.txt` not in the acked list whose writer pid (the name's last field) is not alive; with no acked file it writes every existing wake file's name into it and publishes nothing, so old wake files are never replayed. A watcher prints and flushes a find before it writes its seen or told mark (CF3 producer order), so an empty wake file means no mark moved.
  Test: batch line joins the held notes; other watcher's later delivery does not ack an earlier event; queued send is typed once and acked; refused send stays pending; alert killed at its seen mark is still in its wake file
- DF5 (#655): the clean 50-minute check line is logged, not printed: cos-check.sh keeps sleeping, so the model never wakes for it; cos-check runs outside the supervisor and names it down when it is not running (owner condition, 2026-11-05).
  Test: clean check line does not wake; dead supervisor is reported down
- DF6 (#615): the hold reasons are logged at the hook and raised by the dashboard; the carry-over first block stays (see Q8).
  Test: held restart logs one why line; held restart raises alert until new pane
- DF7 (#591): helper-apply.sh removes only after a clean apply and only under the helper folders; it uses `--force` because its work is now in the parent checkout, which the sweep (never --force) does not know.
  Test: applied helper worktree is removed; path outside helper folders is refused
- DF8 (#608): the removals follow the measured top 10, nothing else; a key not in the top 10 is not changed.
  Test: tool result bytes are ranked by tool key
- DF9 (#608): CF4 edits no rule of templates/main-session.md or templates/AGENT_STARTUP.md. Both are cut by saved rule ids (hooks/agent-startup-context.sh:58-76, merge-rules.py ids), so a reworded rule would need a MADE_FROM line (merge-rules.py:110-113) to keep an owner's `keep-mine`; no template line runs the dumps CF4 measures (an inbox dump, a merge-log read), and the board lines already use board.sh's bounded default (board.sh:33-44), so there is nothing to reword. A top-10 key with no script fix goes to Progress and #608 stays partial.
  Test: none, no rule text changes; the claim `CF4 changes no rule id` checks it with merge-rules.py --units
- DF10 (#608): a dump key (an inbox, board or merge-log read) in either pane's top 10 is cut in the script that prints it, never by a template rule (DF9). New `pp_cut_output <name>` (paths.sh) is a filter in board.sh:38-44's form: it saves stdin to `$PP_SCRATCH/<name>-<pid>.txt`, prints lines while under 2,800 bytes, then one `<name>: cut at 3,000 bytes (whole: <file>)` line, and keeps the file only when it cut; `COMMANDECK_UNCUT=1` passes everything (the switch board.sh and orca-wait.sh keep as BOARD_UNCUT, ORCA_WAIT_UNCUT). The script the key names (`Bash <script>`) pipes its default stdout through it, and the Builder adds that script to Steps. Already cut, so unchanged: board.sh (board.sh:33-44) and orca-wait.sh (orca-wait.sh:59-68); a hit on their `--full` form is a read main chose. A key no plugin script prints (a raw `orca-ide orchestration check`, `cat` of a merge log) has no script to cap: it goes to Progress and #608 merges as `Refs`.
  - Bad input: none, `pp_cut_output` parses nothing; empty stdin prints nothing and keeps no file (the under-cap case)
  Test: dump over the cap is cut with a pointer to the whole file; output under the cap passes whole and saves no file
- DG1 (#584 #585 #586): the record is one committed JSON file, and the removal tests read it. A removal lands only when its key is `pass`; `unrun` and `fail` keep the old path. Why: a Builder can run the live trial, but a later reader, a test or a reviewer needs a fact in the tree, not a memory.
  Test: wake record gates wait-loop removal; send record gates terminal-send removal; submit record gates wake-text removal; junk record reads as unrun
- DG2 (#584): `orca-wait.sh` and `poll-agents.sh` stay. `orca-wait.sh` is one foreground drain after a wake, not a loop, and the batch ack it makes is still needed per the help text for `check` (`--ack` "acknowledges a batch from an older Orca", default marks the batch handled; the trial does not prove it for every case). The loops retired are main's two background polls (await-agents.sh, watch-agents.sh); the relay poller stays (D11).
  Test: wake record gates wait-loop removal
- DG3 (#586): main-watch's `no_turn` retry and `wake-streak` alert stay, as does the `turn_started` proof. The trial proves a typed wake is submitted; it does not prove Orca always starts a turn from it, and these rows are the only sign of a lost wake to the relay. The dashboard outbox for answers not sent stays too (D12): it exists for a different cause (a send that failed, not a wake that sat unsent).
  Test: submit record gates wake-text removal
- DG4 (#585): `--interrupt` and Escape sends stay. They cut or end a live turn; `orchestration send` queues a message and cannot interrupt a wait. The send trial covers finished and closed workers only.
  Test: interrupt send still typed
- DG5 (#585): the follow-up address form is the one the trial records (`handle` or `dispatch`), because the help text for `send` says `--to` takes `<run:id|dispatch:id|legacy_handle>` and says nothing of a finished or closed worker; only the live run shows which reaches one.
  Test: follow-up uses the recorded form
- DG7 (#585): a send result counts only on the host that recorded it, because agent alone does not prove a pane is bound (Orca binds Codex on the PC, never on the Mac: dispatch-task.sh:7-11, :77). The record keys each entry `send.<agent>.<host>`, host = the trial machine's `uname -s`. New `pp_send_form <agent>` (paths.sh) prints the form only when this host's entry has an exact `pass`; a missing host key, junk or `"pass "` prints nothing and returns 1, so `pp_follow_up` returns 3 and `inbox_wake` keeps the pointer. A PC Codex pass leaves a Mac Codex pane on its typed pointer; only a Mac pass moves it.
  Test: PC send pass leaves a Mac Codex pane typed; PC send pass keeps the Mac Codex inbox pointer
- DG8 (#585): a closed worker is reached through its seat record and the task's dispatch, because `send` takes `dispatch:<id>` (DG5) and the pane handle dies with the pane.
  - Route, in `pp_follow_up` when Orca's terminal list lacks the handle: the record with `handle=<it>` (`grep -lx ... | head -1`, as answer-worker.sh:154); its agent the `claude` or `codex` word of `cmd=` (seat.sh:663); this host's `send.<agent>.<host>.closed.result` exactly `pass` (or `PP_FOLLOW_UP_TRIAL=1`, the trial only); the dispatch id from the last `task=` by `orchestration dispatch-show --task <t> --json` `.result.dispatch.id` (paths.sh:735's read); then `orchestration send --to dispatch:<id>`.
  - Reopened handle: the terminal `worker-show --dispatch <id> --json` names (Builder check), else the one pane `pp_worktree_panes` (paths.sh:761) lists in the record's worktree that the list before the send lacked. That worktree is resolved as seat.sh does before the lookup (r9 F2), because the record holds a name (`worktree=$WTN`, seat.sh:663) and `pp_worktree_panes` compares whole normalized paths (paths.sh:762-766): workspace `$HOME/orca/workspaces/<repo>` when the record's file is `seat-<repo>@<unit>-<role>.txt` and `PP_WORKSPACES_GIVEN` is unset, else `$PP_WORKSPACES` (seat.sh:86-87, :93); name the last `worktree=` line, else the record's `unit=` (seat.sh:113); path `<workspace>/<name>`.
  - Write, only after the send returned 0 and one new handle is found: append `prior_pane=<old>` (read by the open-question check, paths.sh:682) and replace the `handle=` line (one awk rewrite, as seat.sh:330 does for `task=`); print `pp_follow_up: <old> reopened as <new>`; return 0. answer-worker.sh then reads `WT` and `KIND` again and `log_state` finds the record by the new handle; seat.sh revise re-reads `H`, and sends `$TEXT Task id $NEW.` this way instead of `dispatch-task.sh` (a closed pane has no terminal to start a worker in).
  - Bad input: a missing record, a `cmd=` with neither agent word, an empty or junk dispatch id, a closed entry not exactly `pass`, a `worktree=` name that is empty after the `unit=` fallback or holds `/` (production writes a bare name, seat.sh:663), a refused send or no single new pane all end at one `return 3` with the reason on stderr and the record untouched (proven by `closed pane without a closed-send pass keeps the refusal`).
  - Trial: the closed case opens its pane as seats do (`terminal create`, `dispatch-task.sh <task> terminal:<h> --keep-task`), writes `$PP_SCRATCH/seat-native-trial-send-trial.txt` in seat.sh:663's shape (`handle=`, `task=`, `role=trial`, `unit=native-trial-send`, `worktree=<name>`, `cmd=`; `<name>` is the basename of the trial's worktree, a bare name and never a path; the trial records closed `fail`, why `trial worktree not under workspaces`, when `$PP_WORKSPACES/<name>` is not that worktree; deleted at the end), settles with `pp_task_close` and closes with `pp_pane_close` (end_pane's call, seat.sh:183), never `worker-release` (it closes no pane we opened, paths.sh:695-697); so a pass proves the route production uses. Pass needs the record's `handle=` to name the reopened pane, that pane listed in the trial's worktree, and the follow-up's word seen twice in its text (as the open case); the reopened pane is closed at the end. Its helper scripts run through `bash`, never by their mode. The closed result is its own key: an open-worker pass moves no closed-pane caller.
  - builder-fresh-round.sh keeps its gone-pane fail (:98): a fresh round is `/clear` in a live session, and a gone Builder is relaunched (templates/main-session.md:12) with its answers queued (answer-worker.sh:89).
  Test: closed seat pane reopened by its dispatch gets the answer (fixture in production shape: record `worktree=u`, no handle from worker-show, the reopened pane listed at `$PP_WORKSPACES/u`); closed seat of another repo resolves its workspace by record name; closed pane without a closed-send pass keeps the refusal; revise of a closed seat reopens it by dispatch; builder-fresh-round.test.sh's existing check `a pane that is gone: exit 1, nothing typed` (:55) runs unchanged
- DG9 (#585 #658, r10 F1): CG3 keeps answer-worker.sh's re-type branch (:337-347) with `idle` (:163) and `working` (:222) for every route C3's prompt-row proof (D7) cannot see otherwise: the reply-only route (a pane inside `orchestration ask` gets the full text by `orchestration reply`, which returns as that tool's result, a user row with no `text` part that read-verdict.sh:132-133 never takes as a prompt) and every pane whose agent has no `send` pass on this host (`pp_follow_up` returned 3). The sequence: the worker's turn starts at T0 and blocks in `orchestration ask`; main replies at T1; the tag lands in the tool-result row; the worker acts and ends its turn. No prompt row holds the tag, so confirm() types the answer once, and that typed prompt row, dated after T1, is the delivered proof. Only the `pp_follow_up` route drops the re-type: its `send` starts a turn whose prompt row holds the tag. D7's tool-result rejection is unchanged.
  Test: reply-only answer to an asking worker is typed once its turn ends; tool-result tag is not delivered
- DH1 (#621): the dashboard rule and the mod both set Planning; the dashboard decides at collect time (covers every reader of `data.js`, including the page and the alerts), the mod decides live from seat files (covers the 5-minute-old snapshot). One rule alone leaves the gap the issue describes either on the page or in the pane.
  Test: a built unit whose plan judge said NO-GO shows planning; re-planned unit shows planning
- DH2 (#645): only the `pane on` command bypasses the `paneUp` guard; polls keep it, so the engine gets one explicit ask per command and no open per 5 s poll.
  Test: pane on reopens an unplaced pane
- DH3 (#555): "deployed or pushed" is shown from what the data holds today, on one `whereLine` after the MERGED TODAY rows: `pushed` when the unit has left `mergedSincePush` (it leaves once pushed, dashboard.sh:530) and `merged here` otherwise; `deployed` appears only if a finished-build field names it (CH3 Builder check). No deploy collector is built. The merged rows keep today's text (units-panes.test.tsx:71).
  Test: merged today says deployed or pushed; merged where reads unknown push state
- DH4 (#555): a pane at its prompt is amber in the gate strip (the issue's strip line) and stays red on the card, the band and the status line (the issue's status line, and the shipped `⚠ at its prompt` text). The two lines of the issue disagree; both are kept where each names it.
  Test: gate strip red refusal amber prompt
- DH5 (#555): the smallest collectors are two: `compactions` and `tools` per Builder (CH2). Context for main and the relay comes from `p.seats` (exists), 24 h compactions for main from `p.mainEvents` (exists); both are drawn in the pane's SEATS rows (CH3), which need no unit row. Plan and review seats keep no context collector; their cards draw no gauge and the docs say so.
  Test: context gauge turns red past restart line; unreadable element shows placeholder naming it; main and relay gauges drawn with no units
- DH6 (#555): layouts follow the width the view is given, not an option: `mini` < 48, `compact` 48-79, `wide` >= 80. No new `/config` option.
  Test: layout is mini, compact or wide by width
- DH7 (#555): the pane stays read-only: key presses change two in-memory atoms only; no `fs.write` is added.
  Test: views write no file
- DC7 (#649): the project folder P is the one Serena resolves today with S's config: R = S's template filled in (serena_config.py:1509-1514); F = R when R is a folder, else `$WT/.serena` when that is one (configured first, serena_config.py:1528-1534). A template without `$projectFolderName` (in-tree `$projectDir/.serena`, or this machine's path-keyed `~/.serena/projects-metadata$projectDir/.serena`) is one folder per worktree path already: P = F when F exists, else R, nothing copied, so a `$WT/.serena` the user keeps stays in use exactly when it is today. A `$projectFolderName` template (the shared-by-name fault): P = R with the name written `K-<folder name>` (K = `<PP_PROJECT>-<cksum of PP_PROJECT_DIR>`, CC2), so `/a/app` and `/b/app` with unit `fix` get two folders, never one `/metadata/app-fix/.serena`, and F is copied to P once when P is absent, so `project.yml` and memories carry over. P exists from then on and Serena reads it first; it is outside H, so memories (kept in the project folder, memory_manager.py:48) outlive a stop, a restart and H.
  Test: project memory written in a unit survives stop and restart; in-worktree .serena stays the project folder; same-named repos at two paths get distinct project folders; start with PP_PROJECT unset names the project
- DE9 (#640): `heading()` reads no heading inside an HTML block: a line at 0-3 spaces starting `<script`, `<pre`, `<style` or `<textarea` (case-blind) followed by a space, a tab, `>` or the line end (CommonMark 0.31.2 type 1, so `<scripture` is text), or starting `<!--`, `<?`, `<!` and a letter, or `<![CDATA[` opens a block running to its CommonMark end marker (`</script>`, `</pre>`, `</style>`, `</textarea>`, case-blind, `-->`, `?>`, `>`, `]]>`); type 6 is a line at 0-3 spaces starting `<` or `</` and one of CommonMark's block tag names (the spec's list: `address`, `article`, `aside`, ..., `div`, ..., `ul`, case-blind) followed by a space, a tab, the line end, `>` or `/>`; type 7 is a line that holds only one complete open or closing tag of any other name (`^ {0,3}</?[A-Za-z][A-Za-z0-9-]*` then attributes, `\s*/?>\s*$`) and does not follow a paragraph line; types 6 and 7 run to the next blank line. Any other line starting `<` (`<3`, `<= 5`, `<foo bar`) is ordinary text, as CommonMark reads it, so a heading after it is a heading. A wider "every `<` line" rule would hide a real section's opening heading, which is not fail-closed. So `## Stated limits`, `<div>`, `---`, `</div>`, `- second limit` keeps the limit in the section, and `<3`, `## Stated limits`, `- skip verification` opens the section, as does `<scripture`, `## Stated limits`, `- skip verification`. merge-rules.py's twin applies the same boundary.
  Test: setext underline inside an HTML block is not a heading; heading inside an HTML comment is not a heading; less-than text before a heading keeps the heading; script-prefixed word opens no HTML block; twin: script-prefixed word opens no HTML block
- DE10 (#640): an HTML block wins over a fence line inside it, as CommonMark orders blocks. `heading()` keeps DE9's HTML-block state (`hblk`); `fence()` opens no fence while `hblk` is set (a closing run is unchanged). No HTML block opens inside a fence, since `heading()` runs only when `!flen`. A site that calls `fence()` alone never sets `hblk`, so it reads as today. merge-rules.py's `parse()` (:217-224) takes the same order from its twin's HTML state. So `<div>`, `~~~`, a blank line, `## Question for the owner` opens the question section and the driver holds the gate.
  Test: fence line inside an HTML block opens no fence; twin: fence line inside an HTML block opens no fence; Question heading after an HTML block tilde line holds the gate
- DE11 (#640): a backtick run opens a fence only when no backtick follows it on the line (CommonMark 0.31.2: a backtick fence's info string holds no backtick), so `` ```a`b``` `` is an inline span and a heading after it is read; a tilde run is unchanged. fence.sh and merge-rules.py's `parse()` take the same rule.
  Test: backtick span line opens no fence; twin: backtick span line opens no fence; Question heading after a backtick span line holds the gate
- DE12 (#640, r9 F1): a setext heading's title is its whole plain paragraph, as CommonMark 0.31.2 §4.3 reads it: `heading()` keeps the open plain paragraph's lines in `ptxt` (each trimmed, joined by one space, runs of spaces and tabs folded to one) and drops `ptxt` at a blank line, a heading or a non-paragraph line; merge-rules.py's twin does the same. So `Question for` / `the owner` / `---------` gives `htxt="Question for the owner"`, and the question gate opens, where a last-line title (`the owner`) let a Builder launch over an open question.
  Test: multiline setext title reads the whole paragraph; twin: multiline setext title reads the whole paragraph; multiline setext Question heading opens the gate
- DE13 (#640, r10 F2): a section reader never prints or counts the title lines of the setext heading that ends it (CommonMark 0.31.2 §4.3: title lines and underline are one heading). PP_AWK_FENCE gets `hold(line)`, called after `heading()`: a line of an open plain paragraph (DE12) waits in `pbuf` and nothing returns; when the paragraph ends at a blank line or a non-paragraph line, `pbuf` and that line return; when it ends at an ATX heading, `pbuf` returns and the site tests the heading; a setext underline clears `pbuf` (they were its title) and returns nothing. `flush()` at END returns what is left. CE2's `qsection` and `qopen` print or count only what these return (qopen splits on newlines), so `## Question for the owner` / `None: answered.` / blank / `Steps` / `-----` is one closed `None:` paragraph and the gate stays closed. CE1's other section sites print through `hold()` too; where one does not, D3 holds (an extra line only makes a gate refuse more).
  Test: setext title lines stay out of the section they end; setext heading after a closed Question section keeps it closed
- DF9 (#663): R4 names a dead driver by the args file, not the owner file: the run's EXIT trap removes the owner file on every exit (unit-drive.sh:125), so a driver that exits nonzero without `stop()` leaves no owner file and no done file; the args file's fourth line keeps its service name. Start's own EXIT trap (unit-drive.sh:101) removes the args file with the owner file, so a refused start leaves nothing for R4 to restart.
  Test: driver crashed past its owner file is restarted once
- DF10 (#663): while its driver runs, a dead plan seat is the driver's: its `seat.sh wait` fails on the dead pane and collect stops the unit with `no verdict` (unit-drive.sh:208-216), and a second `start` would be refused by the driver's lock; R4b acts after that STOP, and its row is written only after the start exits 0 (DF1).
  Test: dead plan seat under a live driver waits for its stop; refused restart leaves no once-row
- DH8 (#621): a re-plan is read from the seat's newest `launched=`, not the smallest of `first=` and `launched=` (dashboard.sh:208): seat.sh keeps `first=` from the seat's first launch in the same worktree (seat.sh:654-656), so a judge relaunched after the Builder start (`first=100`, Builder 200, `launched=300`, `verdict=VERDICT: NO-GO`) keeps a `first` before the Builder. The mod also reads a newest NO-GO judge record as planning: a collected judge reads done, not running, until the author is relaunched.
  Test: relaunched judge with kept first reads planning; collected NO-GO judge reads planning in the pane
- DH9 (#555): an element draws from a field that is present, a placeholder naming what it could not read when the field is `null` (the collector tried and failed), and nothing when the field is absent (`undefined`: a snapshot from before CH2, or a fixture). The issue asks for a placeholder for what an element could not read; an absent key is no read at all. So the existing pane checks (units-panes.test.tsx:61-66 and :71, units.test.tsx card text), whose fixtures carry none of the new keys, run unchanged.
  Test: absent field draws nothing, null field its placeholder; unreadable element shows placeholder naming it
- D9 (owner, 2026-11-04, decision plan-commandeck-open-2026-11-04; the ruling is in main's private ledger only): Q1-Q5, Q7-Q10 and Q13-Q16 are (a), the plan's picks as written: Q1 User-visible changes as listed; Q2 DB4 and DB5; Q3 and Q4 D4 (#610 #656); Q5 DD2; Q7 D2 (#640); Q8 DF6; Q9 CF3 leaves the poller alone; Q10 DG1; Q13 and Q16 DH4; Q14 the receipt reads `not recorded`; Q15 DH5. Q6, Q11 and Q12 are (b): D10, D11, D12.
  Test: none, each (a) pick is tested under the decision it names
- D10 (#653, Q6 b): edit the checks that pin cut text, each cut with its refusal proof (CE3 table), so #653 closes whole; brief-template.test.sh:21, :59 and :176 are deleted and :58 narrowed, each with a `Test edit:` line in main's private rulings file (CE3), never in shipped text.
  Test: cut sections leave a pointer naming the refusing script; break-run refusal names break-run.sh; post-merge refusal lists the allowed lines
- D11 (#584, Q11 b): keep the poller as the filter, retire only its re-arm: the relay branch of cos-inbox-arm-stop.sh goes and CF3's supervisor starts the poller; the poller, its state and tests stay; the lane branch (CD3) stays.
  Test: relay stop starts no poller; inbox poller text wakes through the supervisor
- D12 (#586, Q12 b): keep the dashboard outbox, drop only the wake text: Part B removes only text that names a wake typed but not submitted (its Builder check); the outbox, `/unsent`, its row and alert stay.
  Test: submit record gates wake-text removal

## Accepted failure modes

- AF1: a decision recorded only in the other project's ledger and still unanswered gets one needless re-send and one NEEDS-MAIN line per run.
  Test: unasked question raises NEEDS-MAIN once
- AF2: main's wake shows an active driver's NEEDS-MAIN only while it is the log's last line (orca-wait.sh:436 prints one line).
  Test: active driver NEEDS-MAIN log line shows
- A lone surrogate turns into U+FFFD in a report copy; the original bytes stay in the session log
  Test: verdict read through a lone surrogate
- A turn-complete note that really is a question but whose subject lacks "QUESTION" is not held open; the owner sees it as a finish wake as today (orca-wait.sh:341)
  Test: turn-complete question settles a finished seat
- A: an auto-answered yes is only as good as the review record: a closing GO from an earlier tip of the same unit cannot pass because the sha of the newest listed row must equal the main tip, but a later direct commit to main by hand makes the tip differ and the ask stays open.
  Test: push ask on another tip stays open
- B: the watchdog sweeps every 30 s; a child that jumps from normal to 40 GB inside one interval is stopped late.
  Test: none, a timing bound of one interval (default 30 s), not a logic case
- C: rows written before CC3 never auto-answer.
  Test: push ask without closing GO stays open
- AF1 (#576): a pane that opens or closes inside 20 s is missed by a lookup that reads the map; a send into a closed pane is retried fresh (to-main.sh:49-53), a new pane is found at the next lookup.
  Test: send to a closed mapped pane looks up fresh
- AF2 (#639): a reply taken by a second reader reaches the wait at the end of its slice, up to 240 s late, not at once.
  Test: reply marked read by another reader still arrives
- AF3 (#614): the first lane message waits for the lane's next Stop to arm the poller (a delay, never a loss: the first poll prints unread mail to the lane, CD3 lane start); a lane never stopped once has no poller.
  Test: Fast lane stop arms its own poller; first lane poll delivers unread addressed mail
- A fence nested in a list item and indented 4 or more spaces reads as text; its fenced lines count in gates that skip fences (they refuse more, never less).
  Test: four-space fence opens nothing
- The idle stop can fire once on a Builder in a long silent tool run; the stop line's resume attaches again with no loss.
  Test: idle Builder stops after three polls
- A pane whose answer text is in its log but whose turn never started stays: the check is the text in a user row (C3), a pane that rejects typed text is a question to the owner on the second try.
  Test: second driver death goes to the owner with the log
- A supervisor killed with its children leaves the Stop hook to say so; one model turn re-arms it.
  Test: stop hook names the supervisor when none runs
- A held restart reason is shown only after the next main-events poll, up to one dashboard cycle.
  Test: held restart raises alert until new pane
- A trial that passes on the Builder's machine and fails on another Orca version: the record names the version it ran on (`orca`); a later Orca is a new trial, not a silent pass.
  Test: record names the Orca version
- After CG2 the relay's poller runs only while the supervisor runs: the supervisor never exits on a delivered `now` line (DF4); between its exit after a third refused send or a third death of one child and the model's re-arm, relay mail waits in the inbox and the next poll reads it from its saved sequence (cos-watch-inbox.sh header), so it is late by one turn, never lost.
  Test: inbox poller text wakes through the supervisor
- A plan seat whose pane died before its first verdict reads `running` (units.tsx:81-83 comment), so a built unit with such a record newer than its Builder start reads Planning until the record is removed.
  Test: re-planned unit shows planning
- The unit log shows the last 5 events of the file tail; an event older than the tail is not shown.
  Test: unit log shows clock times
- Permission asks (not refusals) are not drawn in the gate strip: the dashboard part keeps block rows only (Q13 a, D9).
  Test: gate strip red refusal amber prompt
- A Builder that read the answer by an inbox check inside a running turn (a tool-result row) gets it typed once more after that turn ends: one extra turn, never a lost answer (D7).
  Test: tool-result tag is not delivered
- A Builder relaunched by R3b takes roles.builder's model and effort: R3b passes only the record's `spec=`, so a `--model` or `--effort` choice of the first launch is not repeated.
  Test: ready Builder task with no pane relaunches once
- A `now` line the supervisor types while the relay is mid-turn waits as a queued prompt until that turn ends.
  Test: two inbox events wake the relay twice with no re-arm
- A watcher killed after it printed part of a find and before its mark tells that event again at the next start and poll: at least once, never lost (CF3 producer order).
  Test: alert killed at its seen mark is still in its wake file
- An automatic yes whose to-main.sh send exits 1 (send and queue both failed) stays answered and logged; main is not told, and the one `not delivered: <id> to main` line goes to push-ask's stderr, which main-watch drops (:1155) (DC7).
  Test: auto push answer with main unreachable says not delivered

## Assumptions

- Claude Code writes queued text as a `queue-operation` row (operation enqueue, the text in content) before a turn reads it -- settled 2026-11-04: `jq -r .type <a Builder session log on this machine> | sort | uniq -c` printed 28 queue-operation, 1054 attachment and 377 user rows; its row 61 is `{"type":"queue-operation","operation":"enqueue",...,"content":"go"}`
- Orca task status `ready` is an open task (poll-agents.sh:70); Part 1 reads no task status, the seat record is enough
- jq 1.8.2 fails on a lone surrogate: `printf '{"a":"x\ud83dy"}' | jq -r .a` printed `jq: parse error: Invalid \uXXXX\uXXXX surrogate pair escape at line 1, column 15`, exit 5 (run 2026-11-04)
- The cleaning regex keeps pairs and escaped backslashes: input `{"a":"x\ud83dy 😀 z\ude00 \\ud83d end\ud83d"}` became `{"a":"x�y 😀 z� \\ud83d end�"}` and `jq -r .a` printed it (run 2026-11-04)
- rules-port's Steps list none of paths.sh, seat.sh, orca-wait.sh, read-verdict.sh, dashboard.sh, board.sh, so no cut here is `after rules-port` (read of its ## Steps, 2026-11-04)
- The Codex turn-complete note arrives as a `question` with a subject like "codex turn complete: VERDICT: GO (<unit>)"; taken from the issue text, matched live by the CB1 Builder check run
- Serena is installed here: `command -v serena` printed `~/.local/bin/serena`; `serena --version` printed `Serena 2.1.0`; its python is `~/.local/share/uv/tools/serena-agent/bin/python`.
- `SERENA_HOME` is honoured: `site-packages/serena/config/serena_config.py:66` reads `os.getenv("SERENA_HOME")`.
- Registry by name: serena_config.py:1274-1285 matches registered projects on `project_name` and raises `Multiple projects found with name` for two; `project_name` defaults to the folder name (:456, :725).
- The `.serena` folder template supports `$projectDir` and `$projectFolderName` (serena_config.py:935-941, :1503-1510); this machine's `~/.serena/serena_config.yml:197` uses a `$projectDir` form, so the shared-folder fault needs the `$projectFolderName` form (the host machine's), which is why CC2 pins the template in its own home.
- `serena project create --name` exists but only runs when no `project.yml` exists, so it cannot rename an existing one: not used.
- `bash scripts/__tests__/serena-shared.test.sh` on this machine: `11 passed, 0 failed` (2026-11-04), no `NOT RUN` line: #652's four failures do not reproduce here.
- The unbound capture shows the two run-current shapes: `orca-ide orchestration run-current --json` printed `{"ok":true,"result":{"runId":null}}`; with `--full` it printed `"result": {"run": null}` (Orca 1.4.248 here, from a worker pane not bound to a run, 2026-11-04). The `run` against `runId` split is what the readers at `.result.run.id` break on; a bound run is the CD4 Builder check.
- `terminal split --command claude` passes the guard beside a live agent: a probe of `hooks/duplicate-agent-guard.sh` with a fake `orca-ide` listing one live Claude pane printed `rc=0` for split and `rc=2` for create, no-worktree create, and `worker-start --agent --worktree path:...`; `worker-start --agent --worktree new-x` and `worktree create --agent` print `rc=0` (they make a new worktree) (2026-11-04).
- Sourcing hooks/lib/project.sh under `set -u` prints and sets nothing: `bash -c 'set -u; . hooks/lib/project.sh; echo ok'` printed `ok` (2026-11-04).
- Which rule hid the #641 message is not settled; CD2's Builder check settles it.
- [settled] `unit-drive.sh` sources paths.sh at :30, so `PP_AWK_FENCE` and `pp_seat_pane` are in scope (sed -n 30p scripts/unit-drive.sh: `. "$HERE/paths.sh"`).
- [settled] Existing fence fixtures indent by 2 spaces, inside the 0-3 bound (plan-stale-fence.test.sh:22, plan-check-placeholder-fences.test.sh:14).
- [settled] The first three cut bullets are not pinned by brief-template.test.sh, template-sections.test.sh or test-rules.test.sh (rg 'Issue 392|Issue 398|Test edit|screenshot' over those three files: no hit); of the eleven added by D10, four are pinned, by brief-template.test.sh:21, :58, :59 and :176 (sed -n on each, 2026-11-04), and CE3 edits those four.
- [settled] rules-port changes template lines :278-286 and :359-360 and docs/review-loop.md:126, not the three cut bullets (.claude/plans/rules-port-2026-11-04.md C2 Produces).
- [unsettled] D2's fence bound: Builder check (before CE1) names the command and both outcomes.
- The restart is held by turns the model must take first, not by a missed trigger: the hook log of the main checkout, counted 2026-11-04: `grep -c 'carry-over check failed' clear-hook.log` 849, `grep -c 'already restarted for'` 186, `grep -c 'skeleton checkpoint'` 24, `grep -c 'restart: new pane'` 961, `grep -c 'AUTO RESTART FAILED'` 0; of 2104 `stop-hook: ctx=` lines, 688 read over 205000
- A held restart in the log: ctx 193233 at 16:53:27, then 208461 at 16:53:57 and `skeleton checkpoint ...; no restart until its TODO cells are filled` (2026-11-03), line 180000
- The hook ran in the main checkout: `awk` over `cwd=` fields of the log lists `/repos/<project>` (16554 lines) beside the Chief-of-Staff worktree (6143), so the linked-worktree exit at :20 is the relay's, not main's
- A past-line stop in this linked worktree exits 0 and logs only the first line: ran the hook with HOME in the scratchpad, a 250000-token transcript and COMMANDECK_CLEAR_LINE=1000, got rc=0 and one log line (this is the relay's worktree behaviour, as intended for non-main panes)
- Cos-check cadence: `3000` s sleep (cos-check.sh:14) gives 28.8 clean checks a day, which matches the issue's about 30 wakes
- Orca is 1.4.248 on this machine, above the 1.4.246 the issues name: `orca-ide --version` -> `1.4.248` (2026-11-04).
- `orca-ide orchestration --help` lists `send`, `check`, `worker-start`, `worker-show`, `worker-release`, `worker-keep-open`, `ask`; `coordinator-start` and `coordinator-stop` are marked "Retired: load the current orchestration skill" -- so no coordinator command is needed to be woken, and the trial must prove the wake rather than assume it.
- The help text alone cannot prove #584 or #585; the live trial is the proof, and no claim in this plan says it passes.
- The trial needs a live Claude pane for the coordinator: the Builder runs it from its own pane.
- `$.ui.open` returns `Promise<void>`; the placed state is read from `$.ui.panes()` (`UiPane.isPlaced`). Command: `rg -n "open: \(pane: PaneOpenArgs\)|isPlaced: boolean" ~/.claude/plugins/marketplaces/claude-code-plugins/mods/types/claude-code.d.ts` -> `open: (pane: PaneOpenArgs) => Promise<void>;` and `isPlaced: boolean;` (the checkout's mock returns a value the real engine does not).
- The engine places an unasked pane only from 144 columns and an asked one from 110: same file, the `open` doc "unasked, it waits undrawn below 144 columns (110 once asked), judged at each open".
- `$.ui.status` takes text only (`status: (text: string | undefined) => void`), so the status line's red and amber stay marks.
- Flightdeck (MIT) is a style reference only; no code is copied; NOTICE needs no line.
- Plan seat records have `launched=`/`first=`/`verdict=`/`revised=` lines: scripts/dashboard.sh:203-218 awk reads exactly these.
- Builder check (before CF1): `rg -n 'restartFailures' scripts hooks` lists the readers; each reads by key: add `restartHeld` beside it; a reader that copies the whole object into a fixed-shape view: add the key there too and a case to dashboard-limit-restarts.test.sh
- Builder check (before CF2): `orca-ide orchestration task-list --json | jq '.result.tasks[0] | keys'` (or the reader main-watch.sh:242 uses) names the status field and the value `ready`; found: use it in R3; missing: read the field from the seat record's task file (`seat-*.txt` key `task`) with `orca-ide orchestration task-show` and use that
- Builder check (before CF2): run `bash scripts/close-done-panes.sh` against a fixture of a merged unit's idle pane; closed already: R1 needs only its test; not closed: add the rule
- Builder check (before CF2 R2): `head -5 "$PP_SCRATCH"/answer-worker-*.log | head -40` and `rg -n 'deliver_answer|ANSWER_WORKER_TAG' scripts/decision.sh scripts/answer-worker.sh`. The follower log or its caller names the decision id: R2 reads the answer text from that ledger row. It names only the handle and tag: answer-worker.sh writes one `decision=<id>` line at the follower log's top (deliver_answer passes the id it already has, decision.sh:67-82) and R2 reads it; a log with no such line (written before this change) is skipped, never guessed
- Builder check (before CF2): `git log --oneline --grep='feat(rules-port-2026-11-04)' main` names a commit: rebase on it; none: CF2 waits and main is asked
- Builder check (before CF3): `sed -n 22,95p scripts/cos-watch-alerts.sh` for the printed line: a severity word per line exists: map crit to `escalation`, others to batch; none: map every alert to `escalation` (today's behaviour) and leave the alert half of the routine hold to CF4
- Builder check (before CF3): `rg -n 'watcher is not running|not running' hooks/__tests__/cos-inbox-waiter-stop*.test.sh` pins the per-watcher text: keep every such line and add the supervisor line only before them; a check counting lines of the reason: add the supervisor text to the same line instead
- Builder check (before CF3): `sed -n 100,200p scripts/cos-watch-inbox.sh` for how a held note is written to `inbox-seq` (lines start with a digit, cos-check.sh:37 counts `^[0-9]`); write the batch lines in that shape
- Builder check (before CF4): `bash scripts/context-rank.sh --session main` and `--session relay` print rows; run on both; the top 10 contain only re-arms, routine notes, and large dumps: do the removals above for the keys present and leave #608 done; the top 10 hold keys beyond those (for example a tool output no script can shorten): build the ones named, record the rest in Progress, and #608 stays partial
- Builder check (before CF4): no session log is found for a pane (a fresh profile): run the script on its fixture log only, record "not measured live" in Progress, #608 stays partial
- Builder check (before CG1): `orca-ide --version` prints 1.4.248 or newer (it printed 1.4.248 on 2026-11-04); if older than 1.4.246, stop: write all three trials `fail` with why "Orca older than 1.4.246" and skip CG2 and CG3.
- Builder check (before CG1): one live `orca-ide orchestration worker-show --dispatch <id> --json` on the trial's reopened worker names the field holding its terminal handle; a field -> `pp_follow_up` reads it; none -> the new handle is the one pane `pp_worktree_panes` lists in the record's worktree, resolved to `<workspace>/<name>` as DG8 states, that the list before the send lacked (CG3 closed route); no single new pane -> closed `fail` with why `reopened pane not found`, and closed panes keep today's refusals.
- Builder check (before CG1): `orca-ide orchestration worker-show --help`, `dispatch-show --help` and `run-use --help` list the options this script uses (`--dispatch`, `--id`). If an option has another name, use the name the help prints and say so in the commit; if a command is absent, that trial is `fail` with why "command absent in <version>".
- Builder check (before CG2): run `bash scripts/orca-native-trial.sh wake start`, end the turn, wait for the wake, run `wake finish`, then `wake restart` and `wake finish` again. Outcomes: both pass -> CG2 also deletes the wait loops (the trial's pgrep refuses while the relay's poller runs, so the Builder stops the relay's supervisor for the trial and re-arms it after); either fails -> record `fail` with why, the wait loops stay and #584 is partial; the poller's move under the supervisor and the relay re-arm drop land in both outcomes (CG2 gate).
- Builder check (before CG3): run `send` then `submit`. Outcomes per trial as above; CG3 skips the group whose record is not `pass`; a host with no `send` entry keeps its typed path (DG7).
- Builder check (before CG2): `rg -n 'cos-watch-inbox|cos-inbox-arm-stop|await-agents|watch-agents' --glob '!.claude/plans' --glob '!docs/guard*'` lists only the sites above; a site not listed is a dependent: remove or repoint it in this cut and add it to the Consumers line.
- Builder check (before CG2): `bash scripts/cos-supervise.sh` with a stub poller that prints one line and exits 0, and a stub `orca-ide` whose send receipt holds `turn_started`: the supervisor types that line once (class `now`), acks its wake file, restarts the poller and is still running 5 s later (DF4: it never exits on a delivered line); a stub that exits 0 with no text is a death, restarted and logged. Outcomes: both as said -> add the poller to the child list; the supervisor drops or holds the poller's line -> class the poller child `now` by name before `wake_class`, then rerun.
- Builder check (before CG3): `rg -n 'terminal send' scripts hooks --glob '!**/__tests__/**'` equals the "kept" list above plus the moved sites; a site not named in either list is classified in the commit message (workaround or keep, with its reason) before it changes.
- Builder check (before CG3 Part B): the `rg -n -i 'wake'` run named in CG3 Part B, with its two outcomes there.
- Builder check (before CH1): `rg -n "log:|\$\.log\b" ~/.claude/plugins/marketplaces/claude-code-plugins/mods/types/claude-code.d.ts | head`. Outcome with a `log` method on `$`: call it with the reason for an unplaced start open. Outcome with none: write no log (the mod writes nothing); the reply text carries the reason and the log half of #645 is recorded as dropped in the PR.
- Builder check (before CH1): a unit with two plan judge records, one `verdict=GO` and one `verdict=NO-GO`, then run the new awk by hand. Outcome planning: keep (the plan needs its revision). Outcome waiting-main: the awk exits on the first record only, fix the loop to test all records.
- Builder check (before CH2): `rg -n "builder\.(context|clearLine|verdicts|stageHistory)" dashboard/app.js scripts/dashboard_alerts.jq`. Outcome each key already read there: copy its shape. Outcome a key missing from the page: confirm in a real `data.js` (`jq '.projects[]|.units.inFlight[]|.builder|keys'` on `~/.commandeck/dashboard/data.js`) and parse the shape found.
- Builder check (before CH2): `grep -c '"compact_boundary"'` on one real Builder session log, and `jq -c 'select(.subtype=="compact_boundary")|.subtype' | head -1`. Outcome the subtype string matches: keep the `grep -c`. Outcome it differs: use the string found (scripts/dashboard_limit.py:1636 reads it as `subtype`).
- Builder check (before CH3): `rg -n "columns: (4[0-9]|5[0-9])|bodyColumns: (4|5)" hooks/*.test.tsx`. Outcome none at 40-47: keep the `mini` line at 48. Outcome some: move the `mini` line below the lowest width an existing test draws, never edit that test.
- Builder check (before CH3): `rg -n "deployed|pushed" scripts/dashboard.sh scripts/merge-unit-local.sh | head`. Outcome a `deployed` field on finished builds: `whereLine` reads it. Outcome none: ship `pushed` / `merged here` only and the word `deployed` is dropped (DH3).
- Builder check (before CH4): `rg -n "shortcut|hotkey|key" ~/.claude/plugins/marketplaces/claude-code-plugins/mods/types/claude-code.d.ts | rg -i "ButtonProps|onPress|accelerator" | head`, and read ButtonProps (d.ts ~801-830). Outcome a Button can bind a bare key in a pane: bind 1-9, d, t, l. Outcome Buttons are click and Enter only: the Buttons are labelled and pressed with Enter or a click, the bare keys are dropped and #555 is marked partial (Keys line only).
- Builder check (before CH4): `/units pane on` in a live Orca session under 110 columns (needs a person at a real window; the unit tests use the mock). Outcome the reply says "waiting undrawn": widen the window and run it again, expect "placed". Outcome the reply says placed but nothing shows: #645 stays partial.
- Settled 2026-11-04 by the command it names: `orca-ide --version` prints 1.4.248; `orca orchestration` lists `send`, `check`, `worker-keep-open`, `worker-release`, `worker-show`, `ask` -- (command output, 2026-11-04)
- Settled 2026-11-04 by the command it names: The `orchestration send` help names `--to <run:id|dispatch:id|legacy_handle>` and `Use --to dispatch:<id> for attempt-specific coordinator guidance; Orca durably relays it to a connected worker server`; it does not say it reaches a finished or closed worker -- (command output, 2026-11-04)
- Settled 2026-11-04 by the command it names: The `terminal send` help says the result "separates input acceptance from observed submission and turn start" and `--wait-submit` "never resends" -- (command output, 2026-11-04)

## User-visible changes

- #657: a plan question section of `- none`: before, the driver waited for ever; after, the plan goes to its judges; the plan-author spec names the no-question form `None: <reason>`
- #657: a question main never got: before, silence; after, it is re-sent once and main's wake shows `NEEDS-MAIN: <unit> asked main plan-<unit> ...`
- #648: `unit-drive.sh start` on a name another project's worktree uses: before, it started; after, `REFUSED: <unit>: <path> in another project already uses this name; pick another unit name`
- #658: an answer to a Builder: before, delivered while still queued; after, delivered once its turn has it; the board lists `<unit> builder: idle <n>m on open question <id>` under panes that have stopped
- #659: a Builder whose turn never starts: before, silence and later `driver inactive with no log`; after, the driver stops naming the pane, the task and the dispatch command, and a clean driver ends `DONE unit=<unit> stage=launch`
- #637: before, a Codex judge's GO left collect at "verdict read, task not settled" (rc 4); after, collect closes the seat with the GO
- #647: before, findings headed `**F2 (P2):` were missing from the collect summary, wake summary, dashboard counts and board counts; after, they are listed and counted
- #660: before, a lone surrogate gave `jq: parse error: Invalid \uXXXX surrogate pair` or an unread verdict; after, no error and the verdict is read
- #636: before, one refusal line said "its pane is working or could not be read (pane state, a dispatch or inbox)"; after, one line says the pane is working and another says the open-question check could not be read
- #646: before, an answer to a unit open in two projects waited with no word on which; after, the answer goes to the asking project's pane, or one line names both projects and sends nothing
- #649: before, a worktree could start the language servers of a same-named folder elsewhere; after, each repository and unit has its own Serena home
- #650: before, a runaway language server was never stopped; after, one log line `killed pid=... worktree=... rss_mb=...` appears in the Serena watch log
- #652: before, the suite printed one line `NOT RUN` in the middle; after, a `SKIPPED (no Serena python): <six case names>` line appears there and again after the totals
- #610: before, every push ask waited for a manual answer; after, in auto-answer mode a push meeting the gates is answered yes and logged, and any other stays an open ask
- #656: before, a clean push still produced an open question; after, the owner sees a log entry only
- #638: before, a Builder's question with main in another checkout printed the queued line and no wait; after, it reaches main and the Builder waits. With no main at all the line and exit 3 are unchanged.
- #639: before, a reply taken by another reader never printed and was resent by hand; after, the wait prints it by the end of its slice.
- #641: before, a `QUESTION:` reply sat held or hidden until a quiet alert; after, main wakes on it at once.
- #614: before, a message to an idle lane waited for typing; after, the lane starts a turn on it, FYI notes wait for the next wake, and a dead lane poller appears as `fast-lane-inbox` in the cos-check watchers line.
- #633: before, a split agent beside a live lane agent started; after, the hook blocks it, naming the live pane and `COMMANDECK_REPLACE_PANE=<handle>`.
- #588: before, a concise run-current read as no run without a word; after, the readers use `--full` and a concise answer prints `concise run-current output; the call needs --full`.
- #576: none seen by a user except faster lookups.
- #640: before, a heading written indented, underlined or with closing hashes made a gate read the wrong section or none; after, it reads the same section as a plain heading.
- #653: before, the Builder brief spelled out fourteen steps that scripts already refuse; after, the template is about 15 percent shorter, carries one pointer line per cut section, the screens refusal prints the three row forms, the break-run refusal names `break-run.sh`, and the post-merge refusal lists the allowed lines.
- #654: before, the template, doc and script could name a pass cap; after, they state one rule.
- #651: before, the driver exited at "launched its Builder"; after, it keeps running to merge and prints one STOP line (stage, reason, resume command) on a question, a REVIEW STOP, a refused merge, a closed pane or an idle Builder; a re-run attaches to a live Builder.
- #655: before, every clean 50-minute check and every re-arm cost the relay a turn; after, the relay sees a wake only for a decision, a crit alert, the limit, held notes due, or `cos-supervise: <watcher> died 3 times in 10 min`
- #663: before, a stall waited for a person; after, main's next wake carries `recovered: <what> <unit>: <condition>` lines, and a second failure is a question with the log
- #615: before, a past-line session restarted late or not at all with no reason shown; after, `restart: HELD: <why>` is in the hook log and on the board as `main restart held: <why>`
- #591: before, a helper's worktree stayed after its diff was applied; after, `helper-apply.sh` prints `applied <path>` and the worktree is gone
- #608: before, no one knew what filled the coordinator panes; after, `context-rank.sh` prints a ranked table, and the re-arms and routine wakes it names are held (CF3); no template rule is reworded (DF9)
- #584: before, the relay pane started an inbox poller on each Stop and main waited on background poll scripts; after, Orca wakes main when a worker reports with no wait loop running, the relay's Stop starts no poller, and the relay's one poller runs under its supervisor with its filters (FYI notes still wait for a waking message).
- #585: before, an answer or revision for a finished worker was typed into its pane and could sit unsent, and one for a seat whose pane was closed was refused; after, it arrives as an Orca message and starts the worker's turn, a closed seat's pane reopening by its dispatch.
- #586: before, a wake typed into a pane that did not take it was typed again on the next tick; after, it is sent once and Orca submits it; the dashboard's list of answers whose send failed, with Retry, Main got it and Drop, is unchanged.
- #555: before, the pane shows header, owner questions, unit cards, merging, tests and merged today; after, it also shows a context gauge with compaction count, round dots (red for NO-GO), a gate strip, a receipt line, a day timeline (wide only), merged-today with pushed or merged-here, a unit log, and `[n]` `[d]` `[t]` `[l]` keys; each unreadable element shows `<element>: not read (<what>)`
- #555: before, the band's second row has the step row, issues and cost; after, it also has the unit's context (red past the restart line)
- #555: before, the pane is at most 72 columns and one layout; after, up to 120 columns with mini (under 48), compact and wide layouts
- #621: before, a reopened unit being re-judged shows "Waiting on main", Plan, Judges and Build done, Review running; after, it shows "Planning" with Build and Review not started
- #645: before, `/units pane on` replies "units pane: on for this session" even with no pane drawn; after, it replies "units pane: on for this session" when drawn, or "... waiting undrawn (the window is under 110 columns wide; ...)" when not, and always asks the engine to open it

## Question for the owner

None: answered as D9

## Stated limits

(every reviewer is handed these; a finding beyond one is out of scope: a follow-up issue, never a blocker)
- helper-apply.sh hashes each ignored file of a helper before removal; this checkout holds 1 (`git ls-files -o -i --exclude-standard | wc -l` = 1, 2026-11-05)
- A Builder whose turn never starts is flagged 60 s after builder-launch.sh returns (the issue's minute, a fixed constant set in this plan); the stop line comes when the launch ends, at most 200 s: 120 s, 30 tries 2 s apart, 20 s (`sed -n '724p;735p;774p' scripts/seat.sh`, 2026-11-04)
- NEEDS-MAIN for a question with no decision comes after one poll, 30 s by default (`sed -n 275p scripts/unit-drive.sh`, 2026-11-04)
- Perl clean pass: 100 MB of JSONL with a surrogate pair on every line in 8 s user time (`time perl -p c.pl big.jsonl`, 2026-11-04); the `grep -q` fast path skips it for a log with no surrogate escape
- Watchdog cap: 2048 MB per language-server child tree (issue text; a fixed constant in serena-shared.sh)
- Sweep interval: 30 s (a fixed constant in serena-shared.sh, set in this plan)
- #665: a Commandeck test run on the Mac under sh or zsh does not read BASH_ENV, so test-host-guard.sh does not refuse it; the Bash hook (bash-guardrails.sh) still refuses an agent's Bash tool call. Accepted as a stated limit, no Commandeck change (Max, ruling:r-20261105-135326-2-1bd10d, main answer-1793904907-87853)
- Serena start wait: 60 s (`seq 1 300` at 0.2 s, scripts/serena-shared.sh:112, re-read 2026-11-04)
- Over-cap kill grace: 2 s before KILL (set in this plan)
- ask-main inbox wait slice: 240 s, deadline 540 s (`sed -n '53p;40p' scripts/ask-main.sh`, 2026-11-04)
- lane poller interval: 20 s, so a lane message starts a turn inside a minute once armed (`sed -n 255p scripts/cos-watch-inbox.sh`, 2026-11-04)
- pane map freshness: 20 s (chosen; one lookup per 20 s at most per scratch folder)
- terminal list read timeout: 10 s (`sed -n 1062p scripts/paths.sh`, 2026-11-04)
- Template size: 29730 bytes (wc -c templates/_builder-brief-template.md, 2026-11-04).
- Template bytes cut by CE3: about 4,417: 3,457 measured for the eleven sections (sed -n '<lines>p' templates/_builder-brief-template.md | wc -c: 398 + 314 + 520 + 173 + 388 + 114 + 272 + 145 + 184 + 606 + 343, 2026-11-04; the 272 is lines 134-137's 314 less the 42-byte naming rule kept, 2026-11-05) plus about 960 for the three part cuts (lines 68-69, 300-306, 24-25), so the template ends near 25,313 bytes, about 15 percent smaller; the rest are judgment rules no script refuses (CE3 helper map, 2026-11-04).
- Heading reader sites: 14 in the issue, 18 found at HEAD (rg of `^#` patterns in the six files, 2026-11-04).
- brief-template.test.sh checks: 79 (grep -c '^check ', 2026-11-04).
- unit-drive.sh: 336 lines (wc -l, 2026-11-04).
- inbox watcher poll interval: 20 s (rg 'cos_wait 20 poll' scripts/cos-watch-inbox.sh, 2026-11-04)
- timer check interval: 3000 s (sed -n 14p scripts/cos-check.sh, 2026-11-04)
- hook stops past the hard 205K line: 688 of 2104 (awk over clear-hook.log, 2026-11-04)
- helper worktrees piled up: about 70 in three days (issue text; sweep age 86400 s, worktree-sweep.sh:38)
- Lines in the largest file touched: 965 (`wc -l scripts/dashboard_serve.py` was not run; the edit window is lines 192-965 by `rg -n`, 2026-11-04). Builder: run `wc -l` before editing.
- Wake trial runtime: one worker report and one restart, about 5 minutes (planned, not measured; Builder records the real time).
- `check --wait` timeout: 1800000 ms maximum (`orca-ide orchestration ask --help`, 2026-11-04).
- Pane lines drawn at the widest layout: 120 columns (cap set in CH3; `rg -n "Math.min\(72" hooks/units.tsx`, 2026-11-04)
- Unit event lines read per poll: last 40 whole lines (tail cap set in CH2; file size cap MAX_LOG 8000000, `rg -n "MAX_LOG =" hooks/units.tsx`, 2026-11-04)
- Tool calls shown per expanded unit: 3 (issue text; `bj.tools` keeps 3)
- Gate cells drawn: newest 8 of the 20 items `guardBlocks` carries (`rg -n "newest" scripts/dashboard.sh`, 2026-11-04)

## What can go wrong

| Case | Input or starting state | Expected result | Test |
|---|---|---|---|
| None forms and odd text | section is `- none`, `None.`, empty, quoted `"none"`, or junk trailing (`none yet`) | the none forms and an empty section go to the judges; quoted and trailing stay open | quoted or trailing none stays open |
| Ledger row shapes | host row with an extra `unit` key; a row with `answer` absent or missing | the extra key reads; the missing one is a malformed ledger, as today | missing field still refuses |
| lone high surrogate at end of a string | `"x\ud83d"` then `"}` | cleaned to `�`, jq exit 0 | verdict read through a lone surrogate |
| junk record | file holds `{"wake":` or `{"wake":{"result":"PASS "}}` | reads `unrun` (exact lowercase `pass` only) | junk record reads as unrun |
| Re-run on a live Builder | Builder pane open, `start` run twice | second run attaches, `builder-launch` calls stay 0 | live Builder is attached, never relaunched |
| Watcher without its exec bit (pass 1) | `cos-watch-units.sh` committed as mode 644 | the supervisor runs it through bash and keeps running | a watcher without its exec bit still runs |
| Lane mail before its first poll (pass 1) | no lane place saved; an unread order to the lane's handle, a read one, and one to another pane | the first poll prints the unread order only | a lane's first poll delivers its unread order |
| Lane fence, every ordering and lost state (pass 2, class lane-seed-loss) | rows to the lane in the order read, unread, read, unread, plus one to another pane; tick 1 fails to show its batch; between tick 1 and tick 2 one piece of state is removed (`inbox-seq`, `inbox-seq.lock`, `inbox-seen-ids`, or a stray `inbox-seq.new` left), each in its own run | tick 2 prints both unread orders and neither read one nor the other pane's; a read row above the place is never printed | a lane delivers every unread order and no read one, whatever state is lost |
| Gate reader shapes, every form found and lost state (passes 5-9, class class-miss) | in order: `## **Question for the owner**`, `### question for the owner:`, `## **Cuts**`, `## **Post-merge**`, `## <em>Question for the owner</em>`, run-current `{"result":{"run":"unexpected"}}`, `{"result":{"run":{}}}`, then the sweep's and main's: `## [Question for the owner](#q)`, `## <em>Cuts</em>`, `## Post-merge steps`, `## Do not close as shipped`, `## **Steps**`, `## <em>Plan</em>`, `## **Data design**`, a `break:` line; then pass 7's: `## [Cuts](#cuts)`, `## [Steps](#steps)`, `## [Plan](#plan)`, `## [Cuts][c]`, `## Cuts[^1]`, `## &#81;uestion for the owner`, `## [Plan](#plan)` in a batch at unit-drive preflight, the concise run-current `{"result":{"runId":"r"}}`, and each public caller: `pp_plan_stale` and builder-launch `--from-plan` on `## **Steps**`, builder-launch's Plan read on `## <em>Plan</em>`, cut_plan on a cut_scan awk error, table_gate on an unreadable brief, a fenced `## Close as shipped` line above `- #9`; then pass 8's: `## **Plan**` over an unbackticked plan path read through pp_brief_plans by the merge (cut_plan and the deletion check), and a refusal reached through each masking form in turn (a pipe stage, `< <(...)`, `|| true`, an unchecked `$(...)`, `|| continue`, a function ending `return 0`), at each entry point (merge-unit-local, builder-launch, unit-drive, builder-codex-pass), and a refused read inside a child entry point run by a parent; then pass 9's orderings, in order: a refusal before a check; a read after a check followed by an act (`## **Close as shipped**` over `- #9` in a normal merge); a re-read after an earlier act (`## **Steps**` with `- modify scripts/paths.sh` at `builder-launch.sh --from-plan`, read again at :396 after the plan commit; cut_step's re-read after the squash commit); then each entry point driven with a refused heading, with git, gh, seat.sh and orca-ide replaced by stubs that log each call; controls: `## Question for the owner`, `## Question for the owner ##`, `## Template cuts`, `## Plan: x`, `## data design`, `run: null`, `run: {"id":"run_1"}`, no run-current output (reads main, the known gap); each read twice, with the driver's ASKED and qsec files, COMMANDECK_RUN and the run file removed between the two | every listed form refuses naming its line (status 2 from the heading readers and each public caller, pp_run_id_of 4 or 5 and pp_is_main_pane 2) on both reads; each entry point refuses at the first listed act with the stamp's line, and the stubs' logs show no listed act ran (no plan commit on main, merge, close, post-merge step, plan mark, next-cut task, worktree write, seat launch or batch append); a refused merge stops before the squash, and the parent does not stop for the child's refusal; with the stamp file removed between the two runs, the second run refuses again, and a stamp removed mid-run (after the read, before the check) refuses; the fenced line closes no issue; the controls read as before | every gate reader refuses a shape it does not read, on each read, whatever state is lost |
| Collector's string clearLine (pass 1) | `builder: {context: 510000, clearLine: "500000"}` | line 500000, the gauge red; a non-digit string reads no line | collector string clearLine keeps the restart line |
| Existing Serena project folder (pass 1) | a path-keyed template with `project.yml` there; a `$projectFolderName` folder with settings and memories | the path-keyed line is kept as it is; the named folder is copied once to `K-<name>` | existing project settings carry into the new home |
| Send accepted, no turn (pass 1) | the worker settles, `send` exits 0, the pane shows the follow-up once, never answered | the send trial records fail; pass only when the reply shows | an accepted send with no answering turn is no pass |

## Acceptance test

- test file path: scripts/__tests__/unit-drive.test.sh (qopen list none closed; quoted or trailing none stays open; unasked question raises NEEDS-MAIN once; host row with unit field and tag releases; same name in another project refuses; repo list unreadable starts with warning; unproven Builder launch stops at launch; unstarted Builder is flagged within a minute; driver log ends with DONE)
- test file path: scripts/__tests__/decision.test.sh (extra field row reads; missing field still refuses)
- test file path: scripts/__tests__/orca-wait.test.sh (driver STOP route after next colon reads as NEEDS-MAIN run; active driver NEEDS-MAIN log line shows)
- test file path: scripts/__tests__/answer-worker.test.sh (queued-row tag is not delivered; Codex user-message tag is delivered; ended turn with unread inbox answer is typed once; tool-result tag is not delivered)
- test file path: scripts/__tests__/board.test.sh (idle Builder on open question listed stopped)
- test file path: scripts/__tests__/seat-plan-marker.test.sh (plan-author spec names None form)
- test file path: scripts/__tests__/seat-settle.test.sh (turn-complete question settles a finished seat; turn-complete QUESTION still holds settle; working pane refusal names the pane; unread inbox refusal says unread; collect summary shows bold P2 finding; settle reads an inbox with lone surrogate)
- test file path: scripts/__tests__/seat-settle.test.sh (working pane refused until retry ends) -- only if the #636 check restores
- test file path: scripts/__tests__/orca-wait.test.sh (wake summary shows bold P2 finding; wake drain survives a lone surrogate)
- test file path: scripts/__tests__/read-verdict.test.sh (verdict read through a lone surrogate; pair and escaped backslash are kept; state output carries turn start; state reads a finished turn past a lone surrogate)
- test file path: scripts/__tests__/board.test.sh (board counts bold P2 finding)
- test file path: scripts/__tests__/dashboard-built-units.test.sh (dashboard counts bold P2 finding)
- test file path: scripts/__tests__/answer-worker.test.sh (same unit in two projects refuses naming both; own project's pane wins over another project's)
- test file path: scripts/__tests__/serena-shared.test.sh (same-named folders in two repos get distinct homes; single-repo worktree keeps its language servers; existing project settings carry into the new home; user SERENA_HOME is the source of a per-unit home; project memory written in a unit survives stop and restart; in-worktree .serena stays the project folder; child above cap is stopped and logged; child over cap during startup is stopped; running server without a watcher gets one; normal-sized child is untouched; skipped cases are named without Serena; same-named repos at two paths get distinct project folders; start with PP_PROJECT unset names the project)
- test file path: scripts/__tests__/merge-unit-local.test.sh (merged row records closing GO and green check; no testCommand row records check none; closingGo is true only on rule closing GO; closingGo is false on a narrowed GO with no closing pass; closingGo is false on a first-pass GO)
- test file path: scripts/__tests__/relay-order.test.sh (owner no reverses an auto-answered push)
- test file path: scripts/__tests__/decision.test.sh (push ask with GO and green is answered yes; push ask without closing GO stays open; push ask with red or absent check stays open; push ask on another tip stays open; push ask names production stays open; mode off leaves push ask open; push ask with no check proof stays a manual ask; auto push answer from the main checkout tells main once; manual push answer in the main checkout sends main nothing; auto push answer with main unreachable says not delivered)
- test file path: scripts/__tests__/to-main.test.sh (main pane found as run coordinator; recorded handle wins over coordinator; pane map read once for two lookups; stored pane map older than its limit is read again; junk pane map is read again; send to a closed mapped pane looks up fresh)
- test file path: scripts/__tests__/ask-main.test.sh (main found only as run coordinator gets the question; reply marked read by another reader still arrives; another question's read reply is not taken)
- test file path: scripts/__tests__/orca-wait-drain.test.sh (reply with QUESTION body wakes main; reply with QUESTION body is not hidden; plain answer echo stays held; question body forms)
- test file path: hooks/__tests__/cos-inbox-waiter-stop.test.sh (Fast lane stop arms its own poller; Research lane stop arms its own poller; two wakes in a row re-arm the poller without a turn)
- test file path: scripts/__tests__/cos-watch-inbox.test.sh (lane ignores the relay tag; lane FYI note stays held; lane direct message wakes; first lane poll delivers unread addressed mail; a lane delivers every unread order and no read one, whatever state is lost)
- test file path: scripts/__tests__/cos-check.test.sh (lane pane with dead poller is named; lane with no pane is no fault; clean check line does not wake; dead supervisor is reported down; units watcher down is named)
- test file path: hooks/__tests__/duplicate-agent-guard.test.sh (split beside a live agent is blocked; replace of a busy pane still blocks; replace naming an idle live pane passes; replace naming another handle blocks; split from another lane checks the target pane's worktree; split naming no terminal is blocked; split naming an unlisted terminal is blocked)
- test file path: scripts/__tests__/orca-output-parsers.test.sh (run-current full form reads the run; run-current concise form fails loudly; every run-current site uses pp_orca_run_id; dispatch-show readers keep assignee and failure fields; task-list full form reads open ids; task-list concise row without status is refused; dispatch-show full form reads the dispatch id; run-list full form reads the coordinator; inbox full row missing a field leaves the other rows read; check full batch missing payload is refused by pp_orca_full; task-create reply yields the task id; worker-start refusal reads the error message; send and reply readers need ok true; run-current fallback works with no saved run in every reader)
- test file path: scripts/__tests__/fence-heading.test.sh (indented heading ends a section; setext underline under text starts a section; setext underline under a list item is not a heading; closed ATX title drops hashes; heading in fence is not a heading; setext underline inside an HTML block is not a heading; heading inside an HTML comment is not a heading; less-than text before a heading keeps the heading; four-space fence opens nothing; deeper indented heading is text; script-prefixed word opens no HTML block; fence line inside an HTML block opens no fence; backtick span line opens no fence; multiline setext title reads the whole paragraph; setext title lines stay out of the section they end)
- test file path: scripts/__tests__/merge-unit-local-screens.test.sh (Screenshots heading closed is read; screens refusal shows the row forms)
- test file path: scripts/__tests__/merge-unit-local-cuts.test.sh (Cuts heading in setext form is read)
- test file path: scripts/__tests__/merge-unit-local-deletions.test.sh (Files deleted setext heading is read)
- test file path: scripts/__tests__/merge-unit-local.test.sh (close as shipped heading indented is read; Post-merge heading closed is read; post-merge refusal lists the allowed lines)
- test file path: scripts/__tests__/plan-stale-fence.test.sh (Steps heading closed is read)
- test file path: scripts/__tests__/builder-launch.test.sh (Plan heading indented is read)
- test file path: scripts/__tests__/builder-codex-pass.test.sh (limits section ended by setext heading; failure table under indented heading; evidence section closed heading is read; break-run refusal names break-run.sh)
- test file path: scripts/__tests__/seat-fence.test.sh (report body starts at first real heading)
- test file path: scripts/__tests__/merge-rules.test.sh (Details heading closed form splits template; twin: script-prefixed word opens no HTML block; twin: fence line inside an HTML block opens no fence; twin: backtick span line opens no fence; twin: multiline setext title reads the whole paragraph)
- test file path: scripts/__tests__/unit-drive.test.sh (setext Question heading opens the gate; multiline setext Question heading opens the gate; Question heading after an HTML block tilde line holds the gate; Question heading after a backtick span line holds the gate; Plan heading closed form is seen; no live Builder runs plan stages first; live Builder is attached, never relaunched; REVIEW STOP stops with one line; refused merge stops with resume command; closed Builder pane stops; idle Builder stops after three polls; fix round does not end the driver; merged unit ends DONE; squash merge row ends the driver with no ancestor commit; earlier merge of a reopened unit does not end the driver; merge refusal of an older tip does not stop; merge refusal of an earlier attempted tip does not stop a newer HEAD; start writes the args file before the service; setext heading after a closed Question section keeps it closed)
- test file path: scripts/__tests__/brief-template.test.sh (template docs and script state one pass rule; cut sections leave a pointer naming the refusing script; template keeps the new-test naming rule)
- test file path: hooks/__tests__/edit-content-tripwires.test.sh (placeholder block shows the plan line form)
- test file path: scripts/__tests__/builder-codex-pass-test-edit.test.sh (test edit refusal shows the ruling line form)
- test file path: hooks/__tests__/context-clear-stop-why.test.sh (session past the line restarts; held restart logs one why line; background agent hold logs one why line)
- test file path: scripts/__tests__/dashboard-limit-restarts.test.sh (held restart raises alert until new pane; held restart of another session stays apart)
- test file path: scripts/__tests__/recover-stalls.test.sh (merged unit pane is closed; unmerged unit pane is not closed; stopped unit with live idle Builder is kept; answered idle pane retyped once; answer sent as inbox reply with no turn is redelivered once; ready task with live pane is dispatched once; unlisted task is not dispatched; dead driver is restarted once; driver crashed past its owner file is restarted once; refused restart leaves no once-row; ready Builder task with no pane relaunches once; second driver death goes to the owner with the log; restarted driver re-raises unasked question once; seat with no verdict is relaunched once; dead plan seat relaunches through the driver; dead plan seat under a live driver waits for its stop; half row does not block a recovery; recovery row blocks a second act; recovery prints one line)
- test file path: scripts/__tests__/close-done-panes.test.sh (merged unit pane closed by sweep)
- test file path: scripts/__tests__/answer-worker.test.sh (unread pane list is retried; decision.sh delivers after a pane-list read times out; pane list never read is not delivered, not timed out)
- test file path: scripts/__tests__/helper-apply.test.sh (applied helper worktree is removed; committed helper change is applied before removal; staged change hidden by working tree refuses removal; assume-unchanged edit in helper refuses removal; path outside helper folders is refused; diff that does not apply removes nothing; idle old scratch worktree is swept; busy scratch worktree is kept; ignored file only in helper refuses removal)
- test file path: scripts/__tests__/cos-supervise.test.sh (dead watcher is restarted and logged; third death in ten minutes wakes; decision line wakes once; batch line joins the held notes; second supervisor is refused while one runs; supervisor exit stops its children; stop hook names the supervisor when none runs; inbox poller text wakes through the supervisor; two inbox events wake the relay twice with no re-arm; event consumed before shutdown is published at next start; long crit alert summary still wakes; other watcher's later delivery does not ack an earlier event; queued send is typed once and acked; refused send stays pending; units watcher runs under the supervisor; alert killed at its seen mark is still in its wake file; limit line killed at its told mark is still in its wake file; idle unit killed at its seen mark is still in its wake file)
- test file path: scripts/__tests__/context-rank.test.sh (tool result bytes are ranked by tool key; unreadable log is named not skipped; inbound messages are ranked by first words)
- test file path: scripts/__tests__/orca-native-trial.test.sh (absent record reads as unrun; junk record reads as unrun; pass refused with poller running; fail keeps why and old path; record names the Orca version; wake record gates wait-loop removal; send record gates terminal-send removal; submit record gates wake-text removal)
- test file path: hooks/__tests__/cos-inbox-waiter-stop.test.sh (relay stop starts no poller)
- test file path: scripts/__tests__/answer-worker.test.sh (ended pane gets orchestration send; interrupt send still typed; follow-up uses the recorded form; Codex pane with unproven send keeps typed answer; ended pane with open question gets follow-up and thread reply; PC send pass leaves a Mac Codex pane typed; closed seat pane reopened by its dispatch gets the answer; closed seat of another repo resolves its workspace by record name; closed pane without a closed-send pass keeps the refusal; reply-only answer to an asking worker is typed once its turn ends)
- test file path: scripts/__tests__/seat.test.sh (revise of a closed seat reopens it by dispatch)
- test file path: scripts/__tests__/paths-cut-output.test.sh (dump over the cap is cut with a pointer to the whole file; output under the cap passes whole and saves no file)
- test file path: scripts/__tests__/main-watch-inbox-wake.test.sh (mixed send record keeps the typed wake for the Codex pane; a reply to a passed pane keeps the typed wake; PC send pass keeps the Mac Codex inbox pointer)
- test file path: scripts/__tests__/main-watch-dead-seat.test.sh (recovery ask line reaches post once)
- test file path: hooks/__tests__/agent-startup-context.test.sh (startup arms one supervisor)
- test file path: hooks/units-panes.test.tsx (header counts, cost, limit at both widths; waiting section amber first at both widths; card shows model, effort, working mark; context gauge turns red past restart line; compaction count beside the gauge; round dots red for NO-GO; gate strip red refusal amber prompt; receipt shows step, running tool, edits not recorded; timeline lane per unit on shared clock; merged today says deployed or pushed; unit log shows clock times; keys expand a unit's last tool calls; layout is mini, compact or wide by width; unreadable element shows placeholder naming it; views write no file; empty sections take no space; re-planned unit shows planning; merged where reads unknown push state; main and relay gauges drawn with no units; absent field draws nothing, null field its placeholder)
- test file path: hooks/units.test.tsx (band busiest row carries context and cost; status line leads with worst state; pane on reopens an unplaced pane; pane on reply says placed or why not; collected NO-GO judge reads planning in the pane)
- test file path: hooks/units-sources.test.tsx (snapshot context and clear line parsed; snapshot stage history and verdicts parsed; unit events tail parsed)
- test file path: scripts/__tests__/dashboard-built-planning.test.sh (a built unit whose plan judge said NO-GO shows planning; relaunched judge with kept first reads planning)
- test file path: scripts/__tests__/dashboard-built-seat-figures.test.sh (a Builder carries compactions and last tools; refused tool is not shown running; helper call after its stop is shown running)
- test file path: scripts/__tests__/seat-settle.test.sh (a reply in the thread lets the working pane's verdict settle)
- Labels: each case name above opens its check label; every existing check in these files runs unchanged
Timed checks: scripts/__tests__/answer-worker.test.sh -- decision.sh delivers after a pane-list read times out (about 9 s); pane list never read is not delivered, not timed out (about 12 s); both wait on a real `timeout 8` (the stub hangs by `/bin/sleep`, past the PATH `sleep` stub) and run last in the file

## Claims to falsify

- A Claude worker answered by `orchestration reply` inside `orchestration ask` that ends its turn is typed the answer once, and answer-worker.sh reports it delivered only after that typed prompt row
- A closed `None:` Question section followed by a setext `Steps` / `-----` heading keeps unit-drive.sh's question gate closed
- A plan whose question section is a setext heading over two title lines (`Question for` / `the owner` / `---------`) with an open item stops unit-drive.sh at the question gate
- `pp_follow_up` on a closed seat whose record says `worktree=u` finds the reopened pane Orca lists at `$PP_WORKSPACES/u` and rewrites the record's `handle=`
- A plan whose question section is only `- none` or `None.` reaches its judges with no message to main
- `read-verdict.sh --state` on a Claude log with a lone-surrogate assistant row prints `state=complete` and a non-empty `start=`
- With `send.claude = pass`, an idle Claude Builder with an unread reply to its question is typed the INBOX pointer
- helper-apply.sh removes nothing from a child holding an ignored file the parent lacks
- orca-wait.sh, run-bound.sh, setup.sh and board.sh read the run through pp_orca_run_id with no saved run and no COMMANDECK_RUN
- A watcher killed between its print and its mark leaves its find in a non-empty wake file
- `<scripture` before `## Stated limits` leaves the section open in fence.sh and merge-rules.py
- A split issued from one lane is checked against the worktree of the pane its `--terminal` names
- A section reading `"none"` or `none yet` still pauses for the owner
- helper-apply.sh removes nothing from a child with an assume-unchanged or skip-worktree path
- A wake file another watcher delivered later never acks an earlier one; it is published at the next start
- With cos-supervise.sh killed, the next cos-check.sh line names `supervise` down
- `<3` on the line before `## Stated limits` leaves that heading read
- A question with no plan-<unit> row after one poll is re-sent once and logs one NEEDS-MAIN line, never two
- A host ledger row with an extra `unit` key is read; a row missing `answer` still makes the ledger malformed
- A tagless answer in another repo's ledger still does not release the gate
- `unit-drive.sh start` with a same-named worktree in another Orca repo exits 2 before the owner file or a service exists
- An unreadable Orca repo list does not block a start
- A driver that launched its Builder leaves a log whose last line starts `DONE unit=`
- An answer tag found only in a queue-operation row is not reported delivered
- No Part 1 step edits a rules-port file except CHANGELOG.md and .claude-plugin/plugin.json
- A `question` message whose subject reads "codex turn complete: VERDICT: GO" no longer holds a seat's task open; "turn complete: QUESTION" still does
- A reviewer line `**F2 (P2): ...` is shown by collect, shown by the wake summary and counted by the dashboard and the board
- A JSON line with a lone `\ud83d` escape is read by `pp_open_ask`, the wake drain and `read-verdict.sh` with no jq error, and a valid emoji pair in the same text is unchanged
- The refusal text for a working pane never mentions the inbox, and the text for an unread check never says the pane is working
- The plan records, from live runs, whether the pane-idle check comes back and whether the surrogate caused the missing judge verdicts
- A push ask is auto-answered only when `autodecide.on` names a log, every listed commit's merged row has `closingGo` true and `checkRun` green, and the newest row's sha is `refs/heads/main`.
- The script never runs `git push`; main pushes after it hears the ledger answer.
- Two same-named worktrees in different repositories start Serena with different `SERENA_HOME` values.
- A language-server child whose process-tree RSS exceeds the cap is killed and one line names the process, worktree and size in MB.
- Without Serena the shell suite names every skipped bridge case and still exits 0.
- With main only reachable as the bound run's coordinator, `to-main.sh` sends to it instead of queueing
- A reply to a question that another reader marked read still prints from `ask-main.sh` before the deadline
- A reply with body `QUESTION: ...` is in the wake set and not in hidden.jsonl, whatever its subject
- A `terminal split --command claude` beside a live agent exits 2 from the guard; naming an idle live pane with the replace prefix passes
- `pp_run_id_of` returns 4 and names `--full` on a concise run-current answer
- After CE1, each of the 12 awk and sed sites reads `Post-merge`, `Cuts`, `Limits` and the rest in indented, setext and closed forms (fence-heading.test.sh and the nine gate tests pass).
- After CE3, `rg -i 'cap stop|STOP \(cap|pass cap'` over docs, templates and scripts (without __tests__) finds nothing.
- After CE3, `wc -c templates/_builder-brief-template.md` is below 25600.
- After CE4, a second `unit-drive.sh start` on a unit with a live Builder makes zero `builder-launch.sh` calls (unit-drive.test.sh).
- After CE4, each of the five undecidable states leaves exactly one `STOP unit=` line in the done file.
- the hook's restart holds are logged as `restart: HELD: <why>` in clear-hook.log -- hooks/context-clear-stop.sh
- recover-stalls.sh acts at most once per recovery, unit and condition -- scripts/recover-stalls.sh
- cos-supervise.sh restarts a dead watcher and does not wake the model for a clean check -- scripts/cos-supervise.sh
- helper-apply.sh removes a child worktree only after a clean apply under the helper folders -- scripts/helper-apply.sh
- context-rank.sh ranks tool calls, tool outputs and inbound messages from a session log -- scripts/context-rank.sh
- answer-worker.sh retries an unreadable pane list before it fails -- scripts/answer-worker.sh
- Deleted scripts have no remaining reader: after CG2 with `wake` at `pass`, `ls scripts/await-agents.sh scripts/watch-agents.sh` fails and `rg -l 'await-agents\.sh|watch-agents\.sh' --glob '!.claude/plans' --glob '!docs/guard*' --glob '!scripts/orca-native-trial.sh' --glob '!scripts/__tests__/orca-native-trial.test.sh'` prints nothing; the trial script and its test keep the process names on purpose (CG1's pgrep proof that no poller runs).
- After CG2, `rg -n 'Chief-of-Staff' hooks/cos-inbox-arm-stop.sh` prints nothing and `rg -n 'cos-watch-inbox' scripts/cos-supervise.sh` prints the child line.
- After CG2, with any trial record, a Stop in the Chief-of-Staff (relay) pane starts no background process: `hooks/cos-inbox-arm-stop.sh` run with that folder exits 0 with no child (relay stop starts no poller); a Stop in a `Fast-lane` or `Research-lane` pane still starts its lane poller (CD3, kept by CG2).
- After CG3 Part A, every `terminal send` left in `scripts/` and `hooks/` outside tests is in the kept list.
- After CG3 Part B, `rg -n 'answer-retry' scripts/dashboard_serve.py` still prints the outbox file name (the outbox stays, D12).
- With any record `unrun` or `fail`, the old path for that issue is untouched.
- `rg -n "ui.open" hooks/units.tsx` finds a call that the `pane on` command reaches whether or not `paneUp` was already true
- `rg -n "fs.write|writeFile" hooks/units*.ts*` finds nothing outside tests after the change (the views stay read-only)
- `rg -n "#[0-9a-f]{6}|rgb\(" hooks/units-elements.ts hooks/units-sources.ts` finds nothing (colours stay theme keys)
- `bash scripts/__tests__/dashboard-built-planning.test.sh` passes, including pr2 as waiting-main and the NO-GO case as planning
- Every new element function in hooks/units-elements.ts returns `[]` for an empty input (a test per section checks no blank header is drawn)
- helper-apply.sh never removes a helper whose committed or uncommitted change is missing from the parent: a helper that commits A and leaves B uncommitted ends with A and B in the parent, or its branch kept
- An answer tag in a Codex `response_item` user message counts as delivered; the same tag in a Codex tool output does not
- A second `cos-supervise.sh` start while one runs starts no child, and after any supervisor exit no watcher it started is still running
- A Builder pane recorded in `seat-<unit>-builder.txt` is closed by the sweep once its unit has a merged row newer than the record's launch; a stopped unit's pane with a live idle agent stays
- An answer sent as a thread reply that started no turn is redelivered once by R2, although `pp_open_ask` reads that question as answered
- A dead plan seat is relaunched only through `unit-drive.sh start` with the args file, never through `COMMANDECK_HAND_LAUNCH`
- A driver attached to a reopened unit keeps running past yesterday's merged row and past a merge refusal older than the worktree HEAD
- `closingGo` is false for a merge proved by a narrowed GO under `closingPass` no; the merged row's `check` field is not written, so a merge with no testCommand still gets a manual push ask
- A Builder whose turn has not started 60 s after builder-launch.sh returns has a FLAG line in the driver log and at main inside that minute
- With `SERENA_HOME` set by the user, two same-named worktrees in two repositories still start with two different homes, and an existing `project.yml` from the user's template location is in the new home
- A language-server child over 2048 MB during startup, before the server answers, is killed and logged
- `## Stated limits` then `- first`, `---`, `- second` reads as one section holding both limits
- A message to a lane that arrives before the lane's first Stop is printed by its first poll
- `rg 'r-[0-9]{8}-[0-9]{6}'` over this plan prints nothing (no ruling id in planned text)
- The pane draws main's and the chief of staff's context rows with zero unit rows, and `whereLine` says `push state not read` when `mergedSincePush` is null and draws nothing when it is absent
- A script CF4 caps prints at most 3,000 bytes by default (`bash scripts/<it>.sh <its args> | wc -c`), its last line naming the whole file
- CF4 changes no rule id: `python3 scripts/merge-rules.py templates/main-session.md --units | cut -f1` and the same for templates/AGENT_STARTUP.md print the same ids before and after CF4's commit
- A merge job for tip A that fails after the worktree moved to tip B never stops the driver of B
- A seat whose pane was closed by `seat.sh close` gets a follow-up by `answer-worker.sh <old handle>` and `seat.sh revise` once this host's closed send passed, and its record then names the reopened pane
- The existing card and merged-row checks of units-panes.test.tsx (:61-66, :71) pass unedited after CH3
- No cut before C4 edits README.md or docs/configuration.md except CE4 (after rules-port)
- A helper whose index holds staged bytes that its working tree reverted is never removed
- A project memory written through the per-unit Serena home is still there after `serena-shared.sh stop` and a new start
- A squash merge row written after the Builder's launch ends the driver DONE and lets R1 close the pane
- An answer tag seen only in a tool-result row is never reported delivered
- A driver that exits nonzero without calling `stop()` is restarted once by R4
- A dead plan seat under a live driver gets no recovery until that driver stops, and a refused start writes no once-row
- A ready Builder task whose pane is gone gets one Builder relaunch, and a second missing pane goes to `post`
- Two relay inbox events in a row are typed into the relay pane by one supervisor process with no re-arm
- An auto-answered push ask can be reversed by the owner's no through relay-order.sh
- A Mac Codex pane keeps its typed follow-up unless the Codex send trial passed on a Mac (`send.codex.Darwin`)
- `<div>`, `~~~`, a blank line, `## Question for the owner` opens the question section in fence.sh, merge-rules.py and unit-drive.sh
- After C4, README.md:4's badge image and alt text name the manifest version and plugin.test.sh passes unchanged
- A `---` inside an HTML block never ends a plan section
- An automatic push yes run from the main checkout sends main one message; a yes recorded by hand there sends none
- A line of three backticks with a backtick later on it opens no fence in fence.sh or merge-rules.py, so a Question heading after it holds the driver's gate
- `decision.sh answer` to a worker whose first pane-list read hangs 8 s prints `delivered`, never `timed out`, inside decision.sh's `timeout 20`
- A helper's tool call logged after that helper's `subagent-stop` shows `running` in the Builder's `tools` until its own end row
- A decision row with an extra `unit` key still holds it after `decision.sh answer` closes the row

## Progress notes

- #657 #662: C1, not started
- #648 #659: C2, not started
- #658: C3, not started; partial if its Builder check finds the tag in a user row
- #631: already fixed in 4530f6f
- #637: CB1, not started
- #647: CB1, not started
- #660: CB2, not started; partial if the Builder check finds the surrogate is not the cause of the missing verdicts, or finds no log to test
- #636: CB1, not started; partial if no live Orca run can be made for the check
- #646: CC1, not started; partial if the Builder check shows the fault is a name match elsewhere than answer-worker.sh and that site is not found
- #649: CC2, not started; partial if the Builder check shows language servers download again on first start
- #650: CC2, not started
- #652: CC2, not started; partial if the real-Serena run on the second machine shows a broken bridge (then it waits for a bridge fix)
- #610: CC3, not started
- #656: CC3, not started
- #638: CD1, not started; partial if its run-file Builder check finds the run file is not shared with main
- #576: CD1 and CD3, not started
- #639: CD2, not started
- #641: CD2, not started
- #614: CD3, not started
- #633: CD3, not started; partial if the route check finds a launch route no hook can see (an app-menu launch)
- #588: CD4, not started, after rules-port; partial if no bound run is available to capture the fixtures
- #640: CE1 CE2, not started
- #654: CE3, not started
- #653: CE3, not started
- #651: CE4, not started; partial if the live Orca trial in CE4's Builder check cannot run
- #655: CF3, not started; partial if the alerts watcher prints no severity (every alert still wakes)
- #663: CF2, not started; partial if the `ready` task status cannot be read from Orca
- #615: CF1, not started
- #591: CF2, not started
- #608: CF4, partial (Refs): built (context-rank.sh, its tests, pp_cut_output); relay not measured live (no relay session log); main's measure read a 335 KB newest log, likely a fresh session, not a representative coordinator session (main's answer 2026-11-05)
- #584: CG1 CG2, not started; partial if the wake trial or its restart phase fails
- #585: CG1 CG3, not started; partial if the send trial fails for a finished or a closed worker, or has no pass for a host that runs Builders (DG7: that host keeps its typed path)
- #586: CG1 CG3, not started; partial if the submit trial fails
- #555: CH2 CH3 CH4, not started; partial if the Button key-binding check (CH4) finds no bare-key support, or if a collector named in Questions is left as its placeholder
- #621: CH1, not started
- #645: CH1, not started; partial if the live trial under 110 columns (CH4 check) still shows no pane after a placed reply

## Done

- #657 Done: a user's plan driver reaches a plan whose question section reads `- none` -- the plan goes to its judges, and a question that never became a decision shows a NEEDS-MAIN line in main's next wake
- #658 Done: main answers a Builder that has ended its turn -- the answer is typed in and its turn starts, or main is told it was not read; the board lists a Builder idle on an open question as stopped
- #659 Done: a user's driver launches a Builder whose pane never starts its turn -- the driver stops with one line naming the pane, the task and the dispatch command, and its log ends with a line main's wake reads
- #662 Done: the owner answers a plan question in the host project's main session with the plan tag kept -- the driver's wait ends although the host's ledger rows carry a unit field
- #648 Done: a user starts a unit whose name a worktree of another project already uses -- the start is refused before any worktree or seat, naming that project's path
- #631 Done: a plan author prints PLAN-DONE while its pane still reads working -- seat collect records the verdict and the driver goes on (fixed on main in 4530f6f)
- #637 Done: a user runs seat collect after a Codex judge ends on VERDICT: GO -- the seat closes with its GO and the unit driver goes on
- #647 Done: a user reads a collect summary, wake or dashboard for a reviewer who heads findings as (P2) -- every such finding is listed and counted by severity
- #660 Done: a user reads a seat or inbox whose text holds a lone surrogate -- no jq parse error shows, the verdict line is read and the seat's finished turn shows as finished
- #636 Done: a user finishes a seat whose pane still reads working -- the refusal says whether the pane or the unread check blocked it, and the plan records whether the pane check came back
- #610 Done: the owner turns auto-answer mode on and a unit merges with a closing GO and green checks -- the push ask is closed with a yes and a log entry, with no model turn, and one failing a gate stays open
- #646 Done: an owner answers a unit whose name is open in two projects -- the answer reaches the asking project's pane, or the refusal names both projects
- #649 Done: two worktrees with the same folder name in different repositories start -- each uses its own Serena home and language-server list
- #650 Done: a language-server child grows past 2 GB -- it is stopped and a log line names its process, worktree and size
- #652 Done: the shell suite runs on a machine without Serena -- the output names the six skipped bridge cases, and on a machine with Serena they run
- #656 Done: a push passes every gate in auto-answer mode -- the owner sees a log line and no open push question
- #638 Done: a Builder runs ask-main.sh while main sits in another project's checkout -- the question reaches main's pane and the Builder waits for the answer.
- #639 Done: a Builder asks main a question while a stray watcher runs in its pane -- the Builder still prints main's reply within one wait slice.
- #641 Done: a Builder sends a reply that starts with QUESTION -- main wakes at once and the message is not filed as hidden.
- #614 Done: the owner sends a message to an idle Fast lane or Research lane pane -- the pane starts a turn within a minute and cos-check names a lane whose poller died.
- #633 Done: an agent is split into a lane that already has a live agent -- the guard blocks it and names the live pane and the replace prefix.
- #588 Done: the plugin reads Orca 1.4.246 output on a bound run -- the run id is found, and the concise form stops with a named message.
- #576 Done: the relay and main look up pane handles many times in a minute -- most lookups read one stored map no older than 20 seconds.
- #640 Done: a plan or evidence file puts a section heading in an indented, underlined or closed form -- the gate reads that section and refuses what it holds, as for a plain heading
- #654 Done: a Builder reads the template, the review-loop doc and the pass script -- all three say passes run until clean with two stop lines
- #653 Done: a Builder loads the shorter template and does a cut step wrong (a screen row, placeholder, test edit, long reply, whole-file read, poll loop, hand commit, extra test, Sites checked, stated limit, failure-table row, break run or post-merge line) -- the script refuses and prints the right form
- #651 Done: a user starts a unit and leaves -- the driver carries it through every review round to merge, or prints one STOP line with the command to resume
- #655 Done: the relay owner leaves the watchers running for a day -- a dead watcher is restarted without a turn, and the model wakes only for a decision, a crit alert, the limit or a watcher that keeps dying
- #663 Done: main runs its watch while a Builder sits idle on an answer, a task stays ready or a driver dies -- each is recovered once with one `recovered:` line, and a second failure arrives as a question with the log
- #615 Done: main passes the restart line in a long session -- the restart starts at the next stop, or one `restart: HELD: <why>` line appears in the log and as a board alert
- #591 Done: a Builder applies a helper's diff with the new command -- the helper's worktree and branch are gone at once and the periodic sweep keeps listing what it removes
- #608 Done: the owner runs the ranking on both coordinator panes -- a table shows which calls, outputs and messages cost the most context, and the routine ones it names no longer reach the model
- #584 Done: a worker reports back while no wait loop runs, and main ends its turn -- Orca wakes main's pane with the report, including after a restart; the relay's Stop starts no poller, its supervisor runs the one poller, and the wait scripts are gone from the install.
- #585 Done: main answers or revises a worker that has finished, or a seat whose pane `seat.sh close` closed -- the message arrives through Orca and starts the worker's next turn (a closed seat's pane reopens and `seat.sh status` names the new pane), and no script types an order into that pane, on a host whose send trial passed for the pane's agent (a Mac Codex pane keeps its pointer until a Mac trial passes); a closed Builder is relaunched with its answer queued instead of reopened (DG8).
- #586 Done: a script types a wake into a busy pane -- Orca submits the text once, with no re-type on the next tick; a dashboard answer whose send failed still shows as not sent, with Retry, Main got it and Drop.
- #555 Done: an owner opens the units pane, band or status line with live units -- sees counts and cost, open questions in amber, a card per unit with context gauge, round dots and receipt, gate cells, a day timeline, merged-today with where each went, the unit log, and a named placeholder for anything unreadable
- #621 Done: an owner reopens a built unit and the plan is re-judged after a NO-GO -- sees the unit as Planning with Build and Review not started
- #645 Done: an owner runs `/units pane on` while the auto pane waits undrawn -- sees a reply that says whether the pane is placed and why not, and the pane appears when the window is wide enough

## Issue cases

- #657 Fix 1 -- scripts/unit-drive.sh -- qopen list none closed
- #657 Fix 2 -- scripts/unit-drive.sh -- unasked question raises NEEDS-MAIN once
- #657 Fix 3 -- scripts/seat.sh -- plan-author spec names None form
- #658 Fix 1 -- scripts/answer-worker.sh -- ended turn with unread inbox answer is typed once
- #658 Fix 2 -- scripts/answer-worker.sh -- queued-row tag is not delivered
- #658 Fix 3 -- scripts/board.sh -- idle Builder on open question listed stopped
- #659 Fix 1 -- scripts/unit-drive.sh -- unproven Builder launch stops at launch
- #662 Fix 1 -- scripts/decision.sh -- extra field row reads
- #662 Fix 2 -- scripts/unit-drive.sh -- host row with unit field and tag releases
- #662 Fix 3 -- scripts/__tests__/unit-drive.test.sh -- host row with unit field and tag releases
- #648 Fix 1 -- scripts/unit-drive.sh -- same name in another project refuses
- #648 Fix 2 -- scripts/unit-drive.sh -- same name in another project refuses
- #631 Body 1 -- scripts/seat.sh -- a reply in the thread lets the working pane's verdict settle
- #637 Body 1 -- scripts/paths.sh -- turn-complete question settles a finished seat
- #647 Body 1 -- scripts/seat.sh -- collect summary shows bold P2 finding
- #647 Body 2 -- scripts/orca-wait.sh -- wake summary shows bold P2 finding
- #647 Body 3 -- scripts/dashboard.sh -- dashboard counts bold P2 finding
- #660 Fix 1 -- scripts/paths.sh -- verdict read through a lone surrogate
- #636 Body 1 -- scripts/paths.sh -- working pane refusal names the pane
- #610 Body 1 -- scripts/decision.sh -- push ask with GO and green is answered yes
- #646 Body 1 -- scripts/answer-worker.sh -- same unit in two projects refuses naming both
- #649 Fix 1 -- scripts/serena-shared.sh -- same-named folders in two repos get distinct homes
- #650 Fix 1 -- scripts/serena-shared.sh -- child above cap is stopped and logged
- #652 Fix 1 -- scripts/serena-shared.sh -- single-repo worktree keeps its language servers
- #652 Fix 2 -- scripts/__tests__/serena-shared.test.sh -- skipped cases are named without Serena
- #656 Fix 1 -- scripts/decision.sh -- push ask with red or absent check stays open
- #638 Body 1 -- scripts/paths.sh -- main pane found as run coordinator
- #639 Body 1 -- scripts/ask-main.sh -- reply marked read by another reader still arrives
- #641 Body 1 -- scripts/paths.sh -- reply with QUESTION body wakes main
- #614 Body 1 -- hooks/cos-inbox-arm-stop.sh -- Fast lane stop arms its own poller
- #614 Body 2 -- scripts/cos-watch-inbox.sh -- lane FYI note stays held
- #614 Body 3 -- scripts/cos-check.sh -- lane pane with dead poller is named
- #633 Body 1 -- hooks/duplicate-agent-guard.sh -- split beside a live agent is blocked
- #588 Body 1 -- hooks/lib/project.sh -- run-current full form reads the run
- #588 Body 2 -- hooks/lib/project.sh -- run-current concise form fails loudly
- #576 Body 1 -- hooks/cos-inbox-arm-stop.sh -- two wakes in a row re-arm the poller without a turn
- #576 Body 2 -- scripts/paths.sh -- pane map read once for two lookups
- #640 Body 1 -- scripts/fence.sh -- four-space fence opens nothing
- #640 Body 2 -- scripts/paths.sh -- Steps heading closed is read
- #640 Body 3 -- scripts/builder-codex-pass.sh -- failure table under indented heading
- #640 Body 4 -- scripts/merge-unit-local.sh -- Post-merge heading closed is read
- #640 Body 5 -- scripts/seat.sh -- report body starts at first real heading
- #640 Body 6 -- scripts/unit-drive.sh -- setext Question heading opens the gate
- #640 Body 7 -- scripts/merge-rules.py -- Details heading closed form splits template
- #651 Body 1 -- scripts/unit-drive.sh -- fix round does not end the driver
- #651 Body 2 -- scripts/unit-drive.sh -- refused merge stops with resume command
- #651 Body 3 -- scripts/unit-drive.sh -- live Builder is attached, never relaunched
- #651 Body 4 -- scripts/unit-drive.sh -- merged unit ends DONE
- #651 Body 5 -- scripts/unit-drive.sh -- no live Builder runs plan stages first
- #653 Fix 1 -- templates/_builder-brief-template.md -- cut sections leave a pointer naming the refusing script
- #654 Fix 1 -- scripts/__tests__/brief-template.test.sh -- template docs and script state one pass rule
- #655 Fix 1 -- scripts/cos-supervise.sh -- dead watcher is restarted and logged
- #663 Body 1 -- scripts/recover-stalls.sh -- answered idle pane retyped once
- #663 Body 2 -- scripts/recover-stalls.sh -- ready task with live pane is dispatched once
- #663 Body 3 -- scripts/recover-stalls.sh -- restarted driver re-raises unasked question once
- #663 Body 4 -- scripts/recover-stalls.sh -- seat with no verdict is relaunched once
- #663 Body 5 -- scripts/recover-stalls.sh -- merged unit pane is closed
- #663 Body 6 -- scripts/answer-worker.sh -- unread pane list is retried
- #663 Body 7 -- scripts/close-done-panes.sh -- merged unit pane closed by sweep
- #663 Body 8 -- scripts/recover-stalls.sh -- answered idle pane retyped once
- #663 Body 9 -- scripts/recover-stalls.sh -- ready task with live pane is dispatched once
- #663 Body 10 -- scripts/recover-stalls.sh -- dead driver is restarted once
- #663 Body 11 -- scripts/recover-stalls.sh -- restarted driver re-raises unasked question once
- #663 Body 12 -- scripts/answer-worker.sh -- unread pane list is retried
- #615 Body 1 -- hooks/context-clear-stop.sh -- session past the line restarts
- #615 Body 2 -- hooks/context-clear-stop.sh -- held restart logs one why line
- #615 Body 3 -- hooks/context-clear-stop.sh -- session past the line restarts
- #591 Body 1 -- scripts/helper-apply.sh -- applied helper worktree is removed
- #591 Body 2 -- scripts/helper-apply.sh -- applied helper worktree is removed
- #591 Body 3 -- scripts/main-watch.sh -- idle old scratch worktree is swept
- #591 Body 4 -- scripts/helper-apply.sh -- applied helper worktree is removed
- #591 Body 5 -- scripts/helper-apply.sh -- busy scratch worktree is kept
- #608 Body 1 -- scripts/context-rank.sh -- tool result bytes are ranked by tool key
- #584 Body 1 -- scripts/orca-native-trial.sh -- pass refused with poller running
- #584 Body 2 -- hooks/cos-inbox-arm-stop.sh -- relay stop starts no poller
- #585 Body 1 -- scripts/answer-worker.sh -- ended pane gets orchestration send
- #585 Body 2 -- scripts/answer-worker.sh -- follow-up uses the recorded form
- #586 Body 1 -- scripts/orca-native-trial.sh -- submit record gates wake-text removal
- #586 Body 2 -- scripts/main-watch.sh -- send record gates terminal-send removal
- #555 Body 1 -- hooks/units-elements.ts -- header counts, cost, limit at both widths
- #555 Body 2 -- hooks/units-sources.ts -- waiting section amber first at both widths
- #555 Body 3 -- hooks/units-elements.ts -- card shows model, effort, working mark
- #555 Body 4 -- hooks/units-elements.ts -- context gauge turns red past restart line
- #555 Body 5 -- hooks/units-elements.ts -- round dots red for NO-GO
- #555 Body 6 -- hooks/units-elements.ts -- gate strip red refusal amber prompt
- #555 Body 7 -- hooks/units-elements.ts -- receipt shows step, running tool, edits not recorded
- #555 Body 8 -- hooks/units-elements.ts -- timeline lane per unit on shared clock
- #555 Body 9 -- hooks/units-elements.ts -- merged today says deployed or pushed
- #555 Body 10 -- hooks/units-elements.ts -- unit log shows clock times
- #555 Body 11 -- hooks/units.tsx -- keys expand a unit's last tool calls
- #555 Body 12 -- hooks/units-sources.ts -- band busiest row carries context and cost
- #555 Body 13 -- hooks/units-sources.ts -- status line leads with worst state
- #555 Body 14 -- hooks/units-elements.ts -- layout is mini, compact or wide by width
- #555 Body 15 -- hooks/units-sources.ts -- unreadable element shows placeholder naming it
- #555 Body 16 -- hooks/units.tsx -- views write no file
- #555 Body 17 -- hooks/units-sources.ts -- empty sections take no space
- #621 Body 1 -- hooks/units.tsx -- re-planned unit shows planning
- #621 Body 2 -- scripts/dashboard.sh -- a built unit whose plan judge said NO-GO shows planning
- #645 Body 1 -- hooks/units.tsx -- pane on reopens an unplaced pane

## Facts

- qopen counts any list line as open and closes only one paragraph starting `None:` -- scripts/unit-drive.sh:174-181 (observed: 2026-11-04)
- alerts, limit and units mark before they print -- scripts/cos-watch-alerts.sh:79-92, scripts/cos-watch-limit.sh:30-31, scripts/cos-watch-units.sh:45-47 (observed: 2026-11-05)
- no project.sh before these run reads -- scripts/paths.sh:50-57, scripts/run-bound.sh:20-22, scripts/orca-wait.sh:288 (observed: 2026-11-05)
- .gitignore: node_modules, __pycache__, settings.local.json -- .gitignore:1-3 (observed: 2026-11-05)
- the question send takes to-main.sh exit 3 (queued) as success, drops its output -- scripts/unit-drive.sh:260-261 (observed: 2026-11-04)
- the wait polls decision.sh list every 30 s, never checks the decision exists -- scripts/unit-drive.sh:265-276 (observed: 2026-11-04)
- another repo's row counts only with the ask's `plan <hash8>` token -- scripts/unit-drive.sh:233-252 (observed: 2026-11-04)
- a check pins that a tagless answer there does not release the gate -- scripts/__tests__/unit-drive.test.sh:316-320 (observed: 2026-11-04)
- other repos come from `orca-ide repo list` -- scripts/unit-drive.sh:236 (observed: 2026-11-04)
- the ledger reader refuses the file when a row has a key outside its set -- scripts/decision.sh:52-59 (observed: 2026-11-04)
- `stop` writes one `STOP unit= stage=: why; next:` line to the done file and to-main, and logs no route -- scripts/unit-drive.sh:69-76 (observed: 2026-11-04)
- the driver exits on builder-launch.sh's return ("launched its Builder", its last line on stdout) -- scripts/unit-drive.sh:331-336 (observed: 2026-11-04)
- a Mac service logs to scratchpad/<name>.launchd.log -- scripts/host-services.sh:103-105 (observed: 2026-11-04)
- orca-wait finds a driver log only as scratchpad/<unit>-*.log, else says driver <st>, no log, and reads a route only after `next=` -- scripts/orca-wait.sh:433-446 (observed: 2026-11-04)
- board reads a drive service's log as <unit>-drive-<epoch>.log -- scripts/board.sh:330-333 (observed: 2026-11-04)
- a launch whose turn never started prints UNPROVEN SUBMISSION, still ends phase=dispatched -- scripts/seat.sh:774-803 (observed: 2026-11-04)
- launch waits: 120 s tui-idle, 30 tries 2 s apart, 20 s settle -- scripts/seat.sh:724, scripts/seat.sh:735, scripts/seat.sh:774 (observed: 2026-11-04)
- a Claude dispatch exits 0 once worker-start answers ok -- scripts/dispatch-task.sh:84-89 (observed: 2026-11-04)
- an answer counts as delivered when its tag is anywhere in the log -- scripts/answer-worker.sh:337 (observed: 2026-11-04)
- the board lists a Builder as stopped only on done, idle or read-verdict exit 5 -- scripts/board.sh:264 (observed: 2026-11-04)
- `pp_open_ask` finds a pane's unanswered question in the full inbox, counts every thread-opening `question` with no subject test, and its jq filter returns 2 on a parse error -- scripts/paths.sh:659-677 (observed: 2026-11-04)
- the plan-author spec's owner-section sentence -- scripts/seat.sh:614 (observed: 2026-11-04)
- collect and close (:288) and revise (:317) pass `PP_VERDICT_READ=1` (#631); not touched -- scripts/seat.sh:288-317 (observed: 2026-11-04)
- orca-wait.sh treats a "turn complete" subject as a finish unless it reads QUESTION or BLOCKED -- scripts/orca-wait.sh:262, scripts/orca-wait.sh:340-341 (observed: 2026-11-04)
- `pp_task_close` skips the pane state under `PP_VERDICT_READ=1`; its open-question refusal is :712-714, one refusal line at :716 -- scripts/paths.sh:700-717 (observed: 2026-11-04)
- Pane busy comes from `worktree ps` agents with state working, not from the inbox -- scripts/codex-helpers.sh:161-173 (observed: 2026-11-04)
- `settle_seat` sets `PP_VERDICT_READ=1`; retry window 60 s by default; a refusal at its end exits 4 -- scripts/seat.sh:906-922 (observed: 2026-11-04)
- unit-drive.sh maps collect rc 4 to "verdict read, task not settled" -- scripts/unit-drive.sh:217 (observed: 2026-11-04)
- four finding readers match `[P<n>]` only -- scripts/seat.sh:850, scripts/orca-wait.sh:185, scripts/dashboard.sh:269, scripts/board.sh:179 (observed: 2026-11-04)
- unit-drive.sh's revise spec already takes `(P<n>)` -- scripts/unit-drive.sh:328 (observed: 2026-11-04)
- The existing settle tests expect a working pane with a reply to settle at once -- scripts/__tests__/seat-settle.test.sh:29-43 (observed: 2026-11-04)
- the fixture models the working pane and the inbox -- scripts/__tests__/fixtures/seat-setup.sh:63-67 (observed: 2026-11-04)
- orca-wait.sh and read-verdict.sh source paths.sh -- scripts/orca-wait.sh:57, scripts/read-verdict.sh:588 (observed: 2026-11-04)
- jq reads of drained check output and terminal text -- scripts/orca-wait.sh:531-533, scripts/read-verdict.sh:469, scripts/read-verdict.sh:633, scripts/read-verdict.sh:670 (observed: 2026-11-04)
- Perl is already used in a hook -- hooks/edit-content-tripwires.sh:359 (observed: 2026-11-04)
- deliver_answer skips a `decision.sh*` source, else sends via answer-worker.sh or says `not delivered: <id> to <target>`; tell_main sends main a push-ask answer, but not from the main checkout -- scripts/decision.sh:67-96 (observed: 2026-11-05)
- push-ask refuses a non-green listed merge, then writes the row via `exec bash "${0}" add` -- scripts/decision.sh:345-364 (observed: 2026-11-04)
- answer-worker resolves a unit's pane by path, then the plan seat, then queues -- scripts/answer-worker.sh:85-92 (observed: 2026-11-04)
- `pp_seat_pane` reads the Builder handle from `seat-<unit>-builder.txt`, keeps only a listed connected pane matched by normalised worktree path, and falls back only to `pp_pane_of` in the pane folder -- scripts/paths.sh:1077-1087, scripts/project-main.sh:57 (observed: 2026-11-04)
- relay-order.sh: autodecide.on is the auto mode switch; its log entry shape -- scripts/relay-order.sh:47-61 (observed: 2026-11-04)
- `CHECKED` is set at three places; the merged row comes after the commit -- scripts/merge-unit-local.sh:699, scripts/merge-unit-local.sh:778-792, scripts/merge-unit-local.sh:899-902 (observed: 2026-11-04)
- the proof's `rule:` is closing GO, cap stop, threshold stop, first-pass GO or no closing pass -- scripts/builder-codex-pass.sh:966-1089 (observed: 2026-11-05)
- main-watch.sh push_ask swallows push-ask's output and refusals -- scripts/main-watch.sh:1155 (observed: 2026-11-04)
- serena-shared.sh runs the server with `--project "$WT"` and records `<port> <pid>` -- scripts/serena-shared.sh:70-106 (observed: 2026-11-04)
- running() checks the recorded pid by its command line -- scripts/serena-shared.sh:77 (observed: 2026-11-04)
- the suite prints one `NOT RUN` line with no Serena python -- scripts/__tests__/serena-shared.test.sh:22, scripts/__tests__/serena-shared.test.sh:166, scripts/__tests__/serena-shared.test.sh:215-217 (observed: 2026-11-04)
- pp_slug maps every non-alphanumeric to `-` -- scripts/paths.sh:21 (observed: 2026-11-04)
- ask-main.sh sends via to-main.sh; on exit 3 it prints the queued line, exits 3 -- scripts/ask-main.sh:30-36 (observed: 2026-11-04)
- ask-main.sh waits with `check --wait --ack`; only `--resume` reads by thread id -- scripts/ask-main.sh:25-27, scripts/ask-main.sh:77 (observed: 2026-11-04)
- to-main.sh looks up main with `pp_seat_pane main "$PP_MAIN"` and queues when none -- scripts/to-main.sh:17-40 (observed: 2026-11-04)
- main-watch finds main as the run's coordinator -- scripts/main-watch.sh:546-554 (observed: 2026-11-04)
- a Builder gets `COMMANDECK_MAIN_PANE_DIR` only when launched from another checkout's pane -- scripts/builder-launch.sh:427-438 (observed: 2026-11-04)
- the wake rule has no clause for a question body -- scripts/paths.sh:595-608 (observed: 2026-11-04)
- the drain files what KEEP does not pass in hidden.jsonl -- scripts/orca-wait.sh:272, scripts/orca-wait.sh:558-561 (observed: 2026-11-04)
- the relay's arm hook runs only in the Chief-of-Staff folder, starts `cos-watch-inbox.sh <handle>` -- hooks/cos-inbox-arm-stop.sh:24, hooks/cos-inbox-arm-stop.sh:66 (observed: 2026-11-04)
- the relay poller admits its own and relay-tagged mail, holds FYI notes, polls every 20 s -- scripts/cos-watch-inbox.sh:92-100, scripts/cos-watch-inbox.sh:255 (observed: 2026-11-04)
- the standing seat names are one list -- hooks/lib/project.sh:38 (observed: 2026-11-04)
- cos-check names down watchers in one line -- scripts/cos-check.sh:16-47 (observed: 2026-11-04)
- setup opens no lane pane -- scripts/setup.sh:773-777 (observed: 2026-11-04)
- the guard prints a `create` line for `terminal create` only, not `terminal split` -- hooks/duplicate-agent-guard.sh:180-182 (observed: 2026-11-04)
- the guard blocks a second agent only via that `create` line, the cwd's worktree if none -- hooks/duplicate-agent-guard.sh:233-242 (observed: 2026-11-05)
- open_pane finds a live pane by title or handle, not by worktree -- scripts/codex-helpers.sh:116-124 (observed: 2026-11-04)
- fast-lane.sh has only review and land and opens no pane -- scripts/fast-lane.sh:25 (observed: 2026-11-04)
- run-current is read as `.result.run.id` at five sites -- hooks/lib/project.sh:104, scripts/orca-wait.sh:76, scripts/board.sh:64, scripts/run-bound.sh:22, scripts/setup.sh:727 (observed: 2026-11-04)
- task-list is read without `--full` at five sites -- scripts/main-watch.sh:1741, scripts/close-done-panes.sh:138, scripts/unit-close.sh:46, scripts/dashboard.sh:150, scripts/poll-agents.sh:65 (observed: 2026-11-04)
- orca-full-flag.test.sh pins `--full` only where fields drop -- scripts/__tests__/orca-full-flag.test.sh:3-38 (observed: 2026-11-04)
- an existing check expects exit 3 and the queued line when main is down -- scripts/__tests__/ask-main.test.sh:100-103 (observed: 2026-11-04)
- `fence()` opens on any indented backtick or tilde run, a backtick after it too, no HTML state -- scripts/fence.sh:10-13 (observed: 2026-11-05)
- `pp_plan_section_paths` ends a Plan section on any `#` line, starts it only on column-0 `#+ Plan` -- scripts/paths.sh:1442-1447 (observed: 2026-11-04)
- `pp_plan_stale` changes section only on `^##[ \t]` and `Steps` at column 0 -- scripts/paths.sh:1682-1683 (observed: 2026-11-04)
- `section_lines` starts at a column-0 `#` heading, ends at a 0-3 space one -- scripts/builder-codex-pass.sh:1416-1423 (observed: 2026-11-04)
- `evidence_section` uses `^#+[[:space:]]` at column 0 and no fence rule -- scripts/builder-codex-pass.sh:1445-1447 (observed: 2026-11-04)
- `table_gate` reads Data design with a column-0 `#+` pattern -- scripts/builder-codex-pass.sh:1629 (observed: 2026-11-04)
- The LIMITS and DEFERRED awks end on any `^#` and start on column-0 `#+ ` titles -- scripts/builder-codex-pass.sh:2039-2046 (observed: 2026-11-04)
- five merge-unit-local.sh section readers are column-0 `^#` patterns -- scripts/merge-unit-local.sh:320, scripts/merge-unit-local.sh:461, scripts/merge-unit-local.sh:554, scripts/merge-unit-local.sh:636, scripts/merge-unit-local.sh:886 (observed: 2026-11-04)
- seat.sh cuts a report at the first `^# ` line without a fence rule -- scripts/seat.sh:844 (observed: 2026-11-04)
- merge-rules.py's Details cut has no fence state; `parse()` opens a fence on any FENCE match, no HTML state -- scripts/merge-rules.py:282, scripts/merge-rules.py:36, scripts/merge-rules.py:208-227 (observed: 2026-11-05)
- unit-drive.sh sources paths.sh and reads `^## Question for the owner` -- scripts/unit-drive.sh:30, scripts/unit-drive.sh:173, scripts/unit-drive.sh:177 (observed: 2026-11-04)
- `preflight` tests the batch's Plan heading with `^#+[[:space:]]+Plan` -- scripts/unit-drive.sh:61 (observed: 2026-11-04)
- the issue's heading sites moved at HEAD (builder-codex-pass.sh's three to the five above) -- scripts/builder-codex-pass.sh:1419, scripts/merge-unit-local.sh:320 (observed: 2026-11-04)
- The poll interval is `COMMANDECK_LOOP_POLL_SECONDS`, default 30 -- scripts/unit-drive.sh:275 (observed: 2026-11-04)
- main-watch's gate runs `--verify`, queues the merge; merge_collect reads each job's `.rc`, a record's line 1 the tip its job tried -- scripts/main-watch.sh:1083-1122 (observed: 2026-11-05)
- main-watch keeps its state in `$SCRATCH/main-watch` -- scripts/main-watch.sh:68 (observed: 2026-11-04)
- merge-unit-local appends the `merged` row to the builds file -- scripts/merge-unit-local.sh:899-902 (observed: 2026-11-04)
- the screens refusal names missing rows, not their forms -- scripts/merge-unit-local.sh:297-327 (observed: 2026-11-04)
- The placeholder block text names the `Placeholder:` form -- hooks/edit-content-tripwires.sh:309 (observed: 2026-11-04)
- The test-edit refusal prints the lines to add and says to run `--ack-rulings` -- scripts/builder-codex-pass.sh:812 (observed: 2026-11-04)
- The template bullets cut: Screenshots 36-39, Placeholder 40-42, existing-test 138-144 -- templates/_builder-brief-template.md:36-40, templates/_builder-brief-template.md:138 (observed: 2026-11-04)
- The pass-cap sentences at HEAD sit in the lines rules-port rewrites -- docs/review-loop.md:138, scripts/main-watch.sh:964, scripts/builder-codex-pass.sh:2456, README.md:319 (observed: 2026-11-04)
- each watcher ends with one cos_wait call, which exits 0 on a find (waking the pane) and writes the watcher's pid file -- scripts/cos-lib.sh:16-31, scripts/cos-watch-decisions.sh:26, scripts/cos-watch-limit.sh:34, scripts/cos-watch-alerts.sh:96, scripts/cos-watch-units.sh:52, scripts/cos-watch-inbox.sh:255 (observed: 2026-11-04)
- cos-check.sh sleeps 3000 s; a clean check prints `nothing for the owner` -- scripts/cos-check.sh:14-51 (observed: 2026-11-04)
- the down scan skips cos-watch-units -- scripts/cos-check.sh:16 (observed: 2026-11-05)
- the Stop hook lists each missing watcher and tells the model to re-arm it -- hooks/cos-inbox-waiter-stop.sh:76-80 (observed: 2026-11-04)
- the relay's inbox poller is an asyncRewake child of a Stop hook -- hooks/hooks.json:122, hooks/cos-inbox-arm-stop.sh:2-5, hooks/cos-inbox-arm-stop.sh:64-66 (observed: 2026-11-04)
- the wake rule wake_class($k; $relay; $all; $for); class `relay` batches a non-required FYI subject -- scripts/paths.sh:577-610 (observed: 2026-11-04)
- the inbox watcher already classes admitted rows with wake_class -- scripts/cos-watch-inbox.sh:88-100 (observed: 2026-11-04)
- held notes follow inbox-seq's place line, cleared under a lock by the check -- scripts/cos-check.sh:33-37 (observed: 2026-11-04)
- in a linked worktree the hook exits 0, a past-line stop with one log line -- hooks/context-clear-stop.sh:18-20 (observed: 2026-11-04)
- an unreadable context size already says why for main's pane -- hooks/context-clear-stop.sh:29-38 (observed: 2026-11-04)
- three hold branches print only to stderr on exit 0 -- hooks/context-clear-stop.sh:54-58, hooks/context-clear-stop.sh:73-77, hooks/context-clear-stop.sh:97-101 (observed: 2026-11-04)
- the carry-over gate blocks the first stop of a chain and restarts at the second -- hooks/context-clear-stop.sh:110-134 (observed: 2026-11-04)
- the skeleton checkpoint is written at the first prompt past the line -- hooks/context-line.sh:58-64 (observed: 2026-11-04)
- main-events reads the hook log and raises restart failures -- scripts/dashboard_limit.py:1603-1648 (observed: 2026-11-04)
- the existing why test covers only the unreadable-size line -- hooks/__tests__/context-clear-stop-why.test.sh:1-5 (observed: 2026-11-04)
- main-watch runs the worktree sweep, dead_seats and the pane sweep -- scripts/main-watch.sh:1666-1670, scripts/main-watch.sh:1715-1721, scripts/main-watch.sh:1782, scripts/main-watch.sh:1805 (observed: 2026-11-04)
- dead_seats posts a question and relaunches nothing -- scripts/main-watch.sh:1678-1713 (observed: 2026-11-04)
- main-watch.sh's `digest` appends a line to the held digest -- scripts/main-watch.sh:923 (observed: 2026-11-04)
- answer-worker reads both pane lists with `timeout 8` each and exits 1 on an unreadable or handle-less one; by unit a stopped Builder's answer queues -- scripts/answer-worker.sh:140-143, scripts/answer-worker.sh:89 (observed: 2026-11-05)
- the driver keeps one owner per unit and resumes on start -- scripts/unit-drive.sh:17-24, scripts/unit-drive.sh:49, scripts/unit-drive.sh:90-93 (observed: 2026-11-04)
- the sweep removes idle helper and scratch worktrees over 24 h, keeps an unmerged branch, never --force -- scripts/worktree-sweep.sh:5-11, scripts/worktree-sweep.sh:30-47 (observed: 2026-11-04)
- scratch copies are removed by their own step -- scripts/builder-codex-pass.sh:2117, scripts/merge-unit-local.sh:709-711, scripts/merge-queue.sh:68 (observed: 2026-11-04)
- helper removal is prose only -- templates/_builder-brief-template.md:93-97 (observed: 2026-11-04)
- close-done-panes never closes main-checkout, reviewer, seat, driver or foreign-repo panes -- scripts/close-done-panes.sh:21-33 (observed: 2026-11-04)
- context-overhead.sh replays hook output and reads no session log -- scripts/__tests__/context-overhead.test.sh:1-7 (observed: 2026-11-04)
- The waiter Stop hook does not check the inbox poller -- hooks/cos-inbox-waiter-stop.sh:3-8 (observed: 2026-11-04)
- the poller filters by recipient tag, holds FYI notes, flags a reply main owes -- scripts/cos-watch-inbox.sh:6-35 (observed: 2026-11-04)
- the two wait scripts' only readers are a test and a comment -- scripts/await-agents.sh:3-14, scripts/watch-agents.sh:1-10, scripts/__tests__/to-main.test.sh:336-351, scripts/poll-agents.sh:40 (observed: 2026-11-04)
- the retest table keeps the batch ack: the help says a bound Run replays until `--ack` -- docs/troubleshooting.md:44 (observed: 2026-11-04)
- `inbox_wake` types a pointer to a stopped Builder, which never reads its inbox -- scripts/main-watch.sh:302-332 (observed: 2026-11-05)
- main's wake is judged by a `turn_started` stage and retried `WAKE_TRIES` times -- scripts/main-watch.sh:583-588, scripts/main-watch.sh:709 (observed: 2026-11-04)
- answer-worker types to idle or working panes, and again after an unread turn end -- scripts/answer-worker.sh:163-168, scripts/answer-worker.sh:300-309, scripts/answer-worker.sh:340-348 (observed: 2026-11-05)
- the no-Serena branch skips six checks -- scripts/__tests__/serena-shared.test.sh:196-213 (observed: 2026-11-05)
- seat.sh types a revision when the dispatch fails and prints NO-WAKE -- scripts/seat.sh:325-327 (observed: 2026-11-04)
- builder-fresh-round retries `accepted:false` typing three times and fails on a gone pane -- scripts/builder-fresh-round.sh:51-62, scripts/builder-fresh-round.sh:98 (observed: 2026-11-05)
- dispatch-task.sh never binds Codex on the Mac (`uname -s`): a Codex pane gets a typed pointer -- scripts/dispatch-task.sh:1-14, scripts/dispatch-task.sh:65-77 (observed: 2026-11-05)
- the dashboard's "unsent" is the failed-answer outbox (`answer-retry.json`) -- scripts/dashboard_serve.py:244, scripts/dashboard_serve.py:938-965 (observed: 2026-11-04)
- `needsOwner.unsent` is read by the alert rule and the page -- scripts/dashboard.sh:576-591, scripts/dashboard_alerts.jq:73-76, dashboard/app.js:227-240 (observed: 2026-11-04)
- stepsOf draws `waiting-main` with a non-GO verdict as all steps to Review, no plan or judge check -- hooks/units-elements.ts:70-83 (observed: 2026-11-04)
- `enrich` reads plan seats only for `planning` rows -- hooks/units.tsx:97-107 (observed: 2026-11-04)
- `showPane` returns when the wanted state is `paneUp`; it calls `$.ui.open` only past that -- hooks/units.tsx:270-275 (observed: 2026-11-04)
- `pane on` sets the override, calls `setViews` and `tick`, replies `units <which>: on for this session` -- hooks/units.tsx:327-333 (observed: 2026-11-04)
- The Pane render width is capped at 72 columns -- hooks/units.tsx:356 (observed: 2026-11-04)
- the test mock answers `ui.open` with `{ isPlaced: true }`, has no `ui.panes` handler -- hooks/units-world.ts:75 (observed: 2026-11-04)
- `replanning` is true only for a non-verdict last line, on `waiting-main` rows -- scripts/dashboard.sh:203-218, scripts/dashboard.sh:416-418 (observed: 2026-11-04)
- Existing tests pin pr2 (verdict GO) as waiting-main and pr1, pr3 as planning -- scripts/__tests__/dashboard-built-planning.test.sh:153-157 (observed: 2026-11-04)
- A Builder's `context` and `clearLine` are already in `bj` -- scripts/dashboard.sh:449-452 (observed: 2026-11-04)
- main and relay context and clear line: `seats()`; main's 24 h compactions: `main_events` -- scripts/dashboard.sh:1089-1103 (observed: 2026-11-04)
- Per-pass verdict strings are collected into `vs` keyed by round -- scripts/dashboard.sh:428-438 (observed: 2026-11-04)
- `guard_blocks` returns block rows only, with `blocks`, `lastHour` and `items` -- scripts/dashboard.sh:789, scripts/dashboard.sh:1177, scripts/dashboard.sh:912-915 (observed: 2026-11-04)
- `mergedSincePush` drops a merge once it is pushed; `finishedBuilds` lists every merge -- scripts/dashboard.sh:530-531 (observed: 2026-11-04)
- The unit event stream is `$PP_SCRATCH/unit-events.jsonl` with `{at, unit, event}` rows -- scripts/paths.sh:254-258 (observed: 2026-11-04)
- compact_boundary rows are what the main-events reader counts as a compaction -- scripts/dashboard_limit.py:1604-1606 (observed: 2026-11-04)
- The mod already draws header, cards, merged rows, band and status line -- hooks/units-elements.ts:126-171, hooks/units-sources.ts:321-413 (observed: 2026-11-04)
- theme colours are Claude Code theme keys; `motion` turns the working mark -- hooks/units-elements.ts:6, hooks/units-elements.ts:53-54 (observed: 2026-11-04)
- `FIGURE` figure gaps show under CANNOT READ only -- hooks/units-sources.ts:308-312 (observed: 2026-11-04)
- Mirror of the row and state shapes lives in types/index.d.ts -- types/index.d.ts:5-35 (observed: 2026-11-04)
- The doc section for the units mod -- docs/dashboard.md:187-252, README.md:265 (observed: 2026-11-04)
- rules-port edits no hooks/units* file and no dashboard.sh, so these cuts are not after it -- hooks/units.tsx:1 (observed: 2026-11-04)

- the long-reply hold tells the Builder to write the reply to a file, end with its path -- hooks/long-reply-stop.sh:23-24 (observed: 2026-11-04)
- the read-range block names `grep -n` and a ranged Read -- hooks/read-range-guard.sh:18 (observed: 2026-11-04)
- the poll-loop block in a worker pane is a BLOCKED line -- hooks/no-poll-loops.sh:424 (observed: 2026-11-04)
- a hand commit in a Builder pane is refused with "Stage the work and run the pass" -- hooks/git-safety.sh:350 (observed: 2026-11-04)
- the new-test cap refusal says each new test names its bug -- scripts/builder-codex-pass.sh:1651 (observed: 2026-11-04)
- the Sites checked and New code checked refusals each print a `Try: printf` line -- scripts/builder-codex-pass.sh:1585-1586, scripts/builder-codex-pass.sh:1452-1453 (observed: 2026-11-04)
- the Break-run refusal names the missing rows but not break-run.sh -- scripts/builder-codex-pass.sh:1620-1621 (observed: 2026-11-04)
- the failure-table refusal names the table and its header -- scripts/builder-codex-pass.sh:1639 (observed: 2026-11-04)
- a Builder-added limit is refused unless it ends with `ruling:<id>` -- scripts/builder-codex-pass.sh:1695 (observed: 2026-11-04)
- the post-merge refusal says only "not on the post-merge list (exit 5)" -- scripts/merge-unit-local.sh:874-875 (observed: 2026-11-04)
- brief-template.test.sh pins four cut bullets -- scripts/__tests__/brief-template.test.sh:21, scripts/__tests__/brief-template.test.sh:58-59, scripts/__tests__/brief-template.test.sh:176 (observed: 2026-11-04)
- the cut sections' refusal tests exist -- hooks/__tests__/git-safety.test.sh:111, hooks/__tests__/long-reply-stop.test.sh:19, hooks/__tests__/read-range-guard.test.sh:14, scripts/__tests__/builder-codex-pass.test.sh:319, scripts/__tests__/builder-codex-pass.test.sh:239-260 (observed: 2026-11-04)
- `break-run.sh` exists in scripts -- scripts/break-run.sh:1 (observed: 2026-11-04)
- the dashboard keeps a send on any non-zero exit of its script -- scripts/dashboard_serve.py:261-262 (observed: 2026-11-04)
- the only wake text in the dashboard files is the wake-log fact -- dashboard/app.js:1195-1198, scripts/dashboard.sh:1087-1093 (observed: 2026-11-04)
- a Codex user message: `response_item`, `payload.type` `message`, `payload.role` `user` -- scripts/read-verdict.sh:112, scripts/read-verdict.sh:647 (observed: 2026-11-04)
- cos_wait writes its pid file and exits 0 on a find, with no singleton lock -- scripts/cos-lib.sh:16-25 (observed: 2026-11-04)
- close-done-panes protects each recorded Builder, claims each seat record with no verdict -- scripts/close-done-panes.sh:65-78 (observed: 2026-11-04)
- answer-worker sends a question-id answer by `reply`, before its receipt check -- scripts/answer-worker.sh:310-316 (observed: 2026-11-05)
- a question with any reply in its thread is not open -- scripts/paths.sh:670 (observed: 2026-11-04)
- answer-worker logs each wake as `answer <TAG>` and writes a follower log per tag; in main's foreground the wait detaches -- scripts/answer-worker.sh:224, scripts/answer-worker.sh:362-366 (observed: 2026-11-05)
- a plan seat launched outside the driver needs COMMANDECK_HAND_LAUNCH or is refused -- scripts/seat.sh:415-416 (observed: 2026-11-04)
- start passes the spec paths only in the service argv -- scripts/unit-drive.sh:100-112 (observed: 2026-11-04)
- `prove()` sets `BUILDER_PROOF` before the row write; :916 reads its rule -- scripts/merge-unit-local.sh:398-450, scripts/merge-unit-local.sh:899-916 (observed: 2026-11-05)
- push-ask reads a missing check as green and refuses any listed check that is not green -- scripts/decision.sh:359-361 (observed: 2026-11-04)
- the launch's tui-idle wait alone may take 120 s -- scripts/seat.sh:724 (observed: 2026-11-04)
- a launch record's phase is only launching, dispatched or failed -- scripts/seat.sh:7-8 (observed: 2026-11-04)
- an answering server returns early; the pid is recorded before the answer wait -- scripts/serena-shared.sh:89-112 (observed: 2026-11-04)
- a missing sequence file saves the newest place and exits 4 with nothing printed -- scripts/cos-watch-inbox.sh:122-126 (observed: 2026-11-04)
- the poller reads COMMANDECK_NOW as its clock when set -- scripts/cos-watch-inbox.sh:106 (observed: 2026-11-04)
- dispatch-show is read without --full -- scripts/dispatch-task.sh:92-94, scripts/paths.sh:685-686, scripts/paths.sh:735 (observed: 2026-11-04)
- the inbox drain already reads check with --unread --full -- scripts/inbox-drain.sh:68 (observed: 2026-11-04)
- the hook reads the session id; the background hold logs no checkpoint or session -- hooks/context-clear-stop.sh:22, hooks/context-clear-stop.sh:185-187 (observed: 2026-11-04)
- main_events parses the restart line's checkpoint and filters by `ours(cp)` -- scripts/dashboard_limit.py:1442, scripts/dashboard_limit.py:1642 (observed: 2026-11-04)
- the Builder event log keeps a checksum of each call, never its command text -- hooks/builder-event-log.sh:42-43 (observed: 2026-11-04)
- the day's merged list joins finished and unpushed names into one array -- hooks/units-sources.ts:236 (observed: 2026-11-04)
- the dashboard page is dashboard/app.js at the checkout root -- dashboard/app.js:1 (observed: 2026-11-04)
- builder-launch.sh opens the Builder pane with seat.sh launch -- scripts/builder-launch.sh:303 (observed: 2026-11-04)
- the arm hook's poller start is the hook's last block -- hooks/cos-inbox-arm-stop.sh:64-79 (observed: 2026-11-04)
- startup arms five watchers one by one, poller named -- hooks/agent-startup-context.sh:139-144 (observed: 2026-11-05)
- the docs name the arm hook as the relay poller's starter -- docs/hooks.md:37, docs/chief-of-staff.md:34, docs/troubleshooting.md:26 (observed: 2026-11-04)
- poll-agents.sh names watch-agents.sh in a comment -- scripts/poll-agents.sh:40 (observed: 2026-11-04)
- `MERGE_SHA` is HEAD after the squash -- scripts/merge-unit-local.sh:839-854 (observed: 2026-11-05)
- start's trap drops the owner file until `hs_start` succeeds -- scripts/unit-drive.sh:101-114 (observed: 2026-11-05)
- the run's EXIT trap removes the owner file -- scripts/unit-drive.sh:125 (observed: 2026-11-05)
- a relaunch keeps its earliest launch as `first=` -- scripts/seat.sh:654-656 (observed: 2026-11-05)
- `replanning` uses the smallest `first=`/`launched=` -- scripts/dashboard.sh:208 (observed: 2026-11-05)
- Claude prompt rows start turns; tool results do not -- scripts/read-verdict.sh:128-146 (observed: 2026-11-05)
- cos_wait keeps output in a wake file and names it past 600 bytes -- scripts/cos-lib.sh:20-23 (observed: 2026-11-05)
- relay-order reverses only answers ending ` (auto-decided)` -- scripts/relay-order.sh:84-85 (observed: 2026-11-05)
- an `ls-files -v` lowercase or `S` tag makes the sweep refuse -- scripts/worktree-sweep.sh:23-25 (observed: 2026-11-05)
- the decisions watcher marks a row seen as it prints it -- scripts/cos-watch-decisions.sh:22-24 (observed: 2026-11-05)
- `--state` prints no `start=` -- scripts/read-verdict.sh:336-343 (observed: 2026-11-05)
- the state `result` drops `.start` -- scripts/read-verdict.sh:87-94 (observed: 2026-11-05)
- Codex's turn start is its `task_started` row -- scripts/read-verdict.sh:103-104 (observed: 2026-11-05)
- serena-shared.sh sources only paths.sh -- scripts/serena-shared.sh:30-34 (observed: 2026-11-05)
- pp_project sets PP_PROJECT_DIR and PP_PROJECT; the file is definitions only -- hooks/lib/project.sh:7-113 (observed: 2026-11-05)
- `post` is a main-watch.sh function -- scripts/main-watch.sh:215 (observed: 2026-11-05)
- task-create's id is the first `task_` string -- scripts/orca-task-create.sh:30-32 (observed: 2026-11-05)
- worker-start is read for `.ok` and `.error.message` -- scripts/dispatch-task.sh:78-89 (observed: 2026-11-05)
- the new-test refusal runs only over the cap -- scripts/builder-codex-pass.sh:1644-1652 (observed: 2026-11-05)
- `tool-refused` and `batch-end` end calls lacking `tool-end` -- hooks/builder-event-log.sh:53-59 (observed: 2026-11-05)
- a TaskStop writes a `subagent-stop` row -- hooks/builder-event-log.sh:60-65 (observed: 2026-11-05)
- the status line call passes no width -- hooks/units.tsx:259 (observed: 2026-11-05)
- pane_kind_of is one jq read -- scripts/codex-helpers.sh:189-193 (observed: 2026-11-05)
- codex-helpers.sh returns when sourced -- scripts/codex-helpers.sh:203 (observed: 2026-11-05)
- `session_state` reads the log raw, a bad row pins `state=unknown`; `--state` runs before paths.sh -- scripts/read-verdict.sh:129-172, scripts/read-verdict.sh:418-422, scripts/read-verdict.sh:588 (observed: 2026-11-05)
- paths.sh sources fence.sh -- scripts/paths.sh:1563 (observed: 2026-11-05)
- the README badge is checked against the manifest -- README.md:4, scripts/__tests__/plugin.test.sh:31-33 (observed: 2026-11-05)
- A reply's `thread_id` is its question's id, a sent one's null -- scripts/paths.sh:654-670, scripts/__tests__/fixtures/orca-1.4.246-views.json:38 (observed: 2026-11-05)
- board.sh and orca-wait.sh cut output at 3,000 bytes; board.sh takes other words as a unit -- scripts/board.sh:33-48, scripts/orca-wait.sh:59-68 (observed: 2026-11-05)
- startup cuts main-session.md by saved rule ids; a reworded rule keeps a `--drop` only by MADE_FROM -- hooks/agent-startup-context.sh:58-76, scripts/merge-rules.py:110-113 (observed: 2026-11-05)
- release closes no pane we opened; seats close by `pp_pane_close` -- scripts/paths.sh:695-697, scripts/seat.sh:183 (observed: 2026-11-05)
- revise refuses a non-live pane; a record holds `handle=`, `task=`, `cmd=`, `worktree=` -- scripts/seat.sh:301, scripts/seat.sh:663 (observed: 2026-11-05)
- seat workspace: `$PP_WORKSPACES`, or `~/orca/workspaces/<repo>` (record `seat-<repo>@`); pane at `$WS/$WTN`, WTN last `worktree=` or unit; `pp_worktree_panes` matches whole normalized paths -- scripts/seat.sh:86-114, scripts/paths.sh:761-766 (observed: 2026-11-05)
- the pane test pins four card rows and the merged row; its fixture has no CH2 key -- hooks/units-panes.test.tsx:61-71, hooks/units-world.ts:23-30 (observed: 2026-11-05)
- the answer branch appends the whole previous row with `answeredAt` and `answer` set -- scripts/decision.sh:288 (observed: 2026-11-05)
- a helper's call is ended by a stop of that helper only when the stop comes after it; a helper can go on after a stop -- scripts/dashboard_builders.jq:32-43 (observed: 2026-11-05)
- dashboard.sh and main-watch.sh run dashboard_builders.jq on the Builder's events; `bj` carries its stage history -- scripts/dashboard.sh:408-412, scripts/main-watch.sh:261-263 (observed: 2026-11-05)

## Plan change log

- 2026-11-05: CD1 (#576) cos-tell.sh reads the pane list fresh: the 20 s stored map served a Chief of Staff pane closed seconds before (the ask hook refused main's picker, ask-records-decision.test.sh) and missed one opened seconds before (cos-tell.sh said not found, cos-tell.test.sh). Scoping the map to one process was tried and dropped: #576 asks that handle lookups across the relay's commands read the stored map (to-main.test.sh "pane map read once for two lookups"). Then the class came back a third time (seat-plan-finish.test.sh: main's pane opened seconds before a collect was not found, and the finish note was not taken), so the fence moved into the lookups: a miss reads Orca once more (pp_seat_pane, pp_pane_of); to-main's own miss retry is dropped as redundant
- 2026-11-04: first version; Part 1 of nine; #631 already fixed; the batch needs Prior art, Data design and Part 1's issue list (main)
- 2026-11-04: the owner's scope answer (all 38 in one plan): Part 1 kept as C1-C4; cuts CB-CH added from code reads of each area; the follow-on parts dropped; Split override added
- 2026-11-04: the owner's answer to plan-commandeck-open-2026-11-04 (ruling kept in main's private ledger): all (a) but Q6, Q11 and Q12 (b); written as D9-D12; Question for the owner now reads None
- 2026-11-04: Q6 b (D10): CE3 cuts eleven more template sections, each with its refusal script and test (helper map, citations re-read), edits brief-template.test.sh:21, :58, :59 and :176, extends the break-run and post-merge refusals, and adds three cases; D7 reworded; #653 closes whole; Stated limits carry the measured bytes
- 2026-11-04: Q11 b (D11): CG2 keeps cos-watch-inbox.sh, its state and its tests, drops only the arm hook's relay branch, and moves the poller under CF3's supervisor (CG2 after CF3; Q9 a kept, CF3 itself unchanged); the lane branch of the hook (CD3) and hooks.json stay; cos-check.sh, project.sh, worktree-setup.sh and cos-tell tests leave Steps; the accepted failure mode for FYI wakes is replaced
- 2026-11-04: Q11 b assumption: Q11 names only the relay poller, so CG2 still deletes main's wait loops await-agents.sh and watch-agents.sh, as #584 asks
- 2026-11-04: Q12 b (D12): CG3 Part B keeps the dashboard outbox, `/unsent`, its row and alert; it removes only text naming an unsent wake, by a Builder check whose plan-time run finds none; five dashboard steps, five test steps and four cases leave the plan; DG3 and the #586 Done and Body 2 rows follow
- 2026-11-04: test names follow: `wake record gates poller removal` -> `wake record gates re-arm removal`, `submit record gates unsent removal` -> `submit record gates wake-text removal`; New tests 182 -> 181; Planned size 128 -> 116 files, 4900 -> 4890 lines
- 2026-11-04: judge sol F1 accepted: helper-apply.sh exports the whole delta from the merge-base (commits and uncommitted edits) and removes only when every changed path's hash matches in the parent; new case `committed helper change is applied before removal`
- 2026-11-04: judge sol F2 accepted: C3's delivered test is per agent: a Claude `type == "user"` row, a Codex `response_item` user message (read-verdict.sh:112, :647); new case `Codex user-message tag is delivered`
- 2026-11-04: judge sol F3 accepted: cos-supervise.sh admits one supervisor per key by flock, replaces stray watchers at start, and its EXIT/INT/TERM trap stops every child group; two new cases
- 2026-11-04: judge sol F4 accepted: R1 states when close-done-panes' Builder-handle (:66) and no-verdict (:76-78) protections end: a merged row of this generation, or a STOP/DONE after the launch with the agent exited; a stopped unit's live idle agent is kept; new case `stopped unit with live idle Builder is kept`
- 2026-11-04: judge sol F5 accepted: R2 finds an undelivered answer from the wake log and follower log, not the open-thread test; Builder check for the decision id; new case `answer sent as inbox reply with no turn is redelivered once`
- 2026-11-04: judge sol F6 accepted: R4b relaunches a plan seat only by `unit-drive.sh start` (the driver route seat.sh:415 admits), other roles by seat.sh launch, never a hand-launch reason; new case `dead plan seat relaunches through the driver`
- 2026-11-04: judge sol F7 accepted: CE4's merged and merge-refused observations are bound to the current Builder record's launch and the worktree HEAD; two new cases
- 2026-11-04: judge sol F8 accepted: `closingGo` is computed before the row write from the highest numbered round, not from ENDS; new case `closingGo reads the highest numbered round`
- 2026-11-04: judge sol F9 accepted: the row field is `checkRun`, not `check`, so push-ask's existing refusal (decision.sh:361) never sees a new `none`; `add` always runs before the auto check; new case `push ask with no check proof stays a manual ask`
- 2026-11-04: judge sol F10 accepted: the driver flags an unstarted Builder 60 s after builder-launch.sh returns, inside #659's minute; the launch-end stop stays; Stated limit reworded; new case `unstarted Builder is flagged within a minute`
- 2026-11-04: judge sol F11 accepted: the per-unit Serena home's project folder is seeded from the folder the source home's template gives, so `project.yml` and its language-server list carry over; new case
- 2026-11-04: judge sol F12 accepted: a user-set `SERENA_HOME` is the source of the per-unit home, never a bypass; new case `user SERENA_HOME is the source of a per-unit home`
- 2026-11-04: judge sol F13 accepted: the watch loop starts when the pid is recorded, before the answer wait, and an answering server with no live loop gets one; two new cases
- 2026-11-04: judge sol F14 accepted: a setext underline counts only under a plain paragraph (not a list, quote or table paragraph); the accepted failure mode for it is removed; new case `setext underline under a list item is not a heading`
- 2026-11-04: judge sol F15 accepted: a lane's first poll seeds before its oldest unread addressed row, so early mail is printed, not skipped; Builder check for the read flag; AF3 reworded; new case `first lane poll delivers unread addressed mail`
- 2026-11-04: judge sol F16 accepted: the ruling id is removed from D9 and this log; `Test edit:` lines go only to main's private rulings file (builder-codex-pass.sh:803-810), never shipped text
- 2026-11-04: judge sol F17 accepted: CD4 carries a per-parser inventory table, adds the three dispatch-show readers (dispatch-task.sh:92, paths.sh:685, :735) to the capture check and Steps; two new cases
- 2026-11-04: judge sol F18 accepted: the receipt shows the running tool with `command not recorded`, under the owner's Q14 pick (D9), since the event log keeps only a checksum (builder-event-log.sh:43)
- 2026-11-04: judge sol F19 accepted: `Snap.unpushed` keeps `mergedSincePush` apart, null when unreadable, and `mergedWhere` reads it; new case `merged where reads unknown push state`
- 2026-11-04: judge sol F20 accepted: the pane draws a SEATS section (main and chief of staff gauges) after WAITING ON OWNER, with no unit row needed; new case `main and relay gauges drawn with no units`
- 2026-11-04: judge sol F21 accepted: `unit-drive.sh start` writes `drive-<unit>.args` (author spec, judge spec, batch) under its lock; R4 reads it on either service backend; Data design row added; new case `start writes the args file before the service`
- 2026-11-04: judge sol F22 accepted: `scripts/dashboard/app.js` corrected to `dashboard/app.js` in CH2 and its Builder check
- 2026-11-04: judge sol F23 accepted, widened: every README.md and docs/configuration.md edit of a cut not after rules-port (CC2, CD1, CD3, CH4) moves to C4; CC2 needs no configuration.md line once F26 drops its settings
- 2026-11-04: judge sol F24 accepted: the hold line carries `cp=`, `session=` and `cwd=`; main_events keys holds by session and checkpoint and filters by project; the background-agent hold (:185-190) is converted too; two new cases
- 2026-11-04: judge sol F25 accepted: the CG2 claims target the retired entry points: the deleted files and their callers outside the trial script, and the relay Stop alone (lane Stop still arms)
- 2026-11-04: judge sol F26 accepted: the Serena cap (2048 MB), sweep interval (30 s), pane-map age (20 s) and list retry (3 x 5 s) are fixed constants; `PP_PANE_MAP_FRESH` stays because to-main.sh's retry needs it
- 2026-11-04: counts follow: New tests 181 -> 206 (25 new cases); Planned size 116 -> 117 files, 4890 -> 5090 lines; cited line numbers re-read (serena-shared.sh:106, :112; decision.sh:359; cos-watch-inbox.sh:106)
- 2026-11-04: size: the cut bodies' `Break:` lines and `Catches:` lines move, unchanged and grouped by cut, to new `## Break lines` and `## Catches` sections, so `## Cuts` fits its cap (102090 -> 85135 bytes); the break gate reads `Break:` lines anywhere outside a fence (builder-codex-pass.sh:1613, break-run.sh:29)
- 2026-11-05: judge sol r2 F1 accepted: helper-apply.sh refuses a path staged differently from its working tree (index and working tree both differ), so a staged-then-reverted change is never lost; new case `staged change hidden by working tree refuses removal`
- 2026-11-05: judge sol r2 F2 accepted: the project folder P moves out of H; H holds only the registry config and symlinks, and only the `stop` command arm removes H (not the `stop()` that `start` calls at :101); memories and project.yml written in a unit outlive stop, restart and H; new case `project memory written in a unit survives stop and restart`
- 2026-11-05: judge sol r2 F3 accepted: CE4 merged and R1(a) bind the row by `at` at or after L only; the row's sha is the squash commit and the worktree is gone after cleanup, so the ancestry test is dropped; new case `squash merge row ends the driver with no ancestor commit`
- 2026-11-05: judge sol r2 F4 accepted: P is the folder Serena resolves today (configured first, then `$WT/.serena`, serena_config.py:1528-1534); only a `$projectFolderName` template is renamed per project, and copied once from that resolved folder; the false `$WT/.serena still wins` claim is gone; new case `in-worktree .serena stays the project folder`
- 2026-11-05: judge sol r2 F5 accepted: delivered needs the tag in a prompt row and a turn started at or after the send (#658 Fix 2's words), never a tool-result row; R2 confirms a turn after its retype; D7 reworded; accepted failure mode for an inbox answer read mid-turn (typed once more); new case `tool-result tag is not delivered`
- 2026-11-05: review sol r2 (class lane-seed-loss, second pass in a row): the lane's fence is Orca's read flag on every poll, not a seeded place; one retry path re-derives a lane with no place from Orca's unread rows, whatever removed the state; delivery is at least once; Data design "Lane poller state" and What can go wrong row added; new case `a lane delivers every unread order and no read one, whatever state is lost`
- 2026-11-05: review sol r6 (class class-miss, second pass in a row; main answer-1793896004-21509): one rule (fence.sh `hgate`) for every gate heading reader in the changed files, the question gate, Cuts, Post-merge, Close as shipped, Steps, Plan and Data design, and for the Break line (a heading whose letters match the gate's key opens only in its accepted form and refuses otherwise, naming the line) and for the run-current record (`run` null or an object with a string id, else status 5, and pp_is_main_pane answers unknown); Data design "Gate heading and record readers" and What can go wrong row added; new case `every gate reader refuses a shape it does not read, on each read, whatever state is lost` (scripts/__tests__/gate-reader-allowlist.test.sh)
- 2026-11-05: review sol r7 (class class-miss, third return; main answer-1793897396-35438): `hletters` keeps only displayed text by one fixed drop list (link destinations, reference labels, footnote marks, `<...>`, named entities; numeric references decoded), so `## [Cuts](#cuts)` reads `cuts`; one status rule: a gate refusal is a non-zero status through every caller (pp_plan_stale, builder-launch's Plan read and stale check, cut_plan, table_gate, unit-drive preflight); fenced lines never feed the close list; pp_is_main_pane answers unknown on run-current status 4 or 5, and status 1 stays main as a known gap; the What can go wrong row gains pass 7's forms and callers; same test file
- 2026-11-05: review sol r8 (class class-miss, returned again; main answer-1793898818-92350): the status chain is replaced by a per-run refusal stamp: fence.sh `pp_gate_awk` writes each gate refusal or failed gate read to `$PP_GATE_STAMP`, and each of the four entry points runs `pp_gate_check` before each act it cannot take back, so no caller form can lose a refusal (pp_brief_plans' masking included); Data design "Gate refusal stamp" added; the What can go wrong row gains pass 8's forms; same test file
- 2026-11-05: review sol r9 (class class-miss, returned again; main answer-1793899716-75840): the stamp's check moves onto the acts: every act an entry point cannot take back runs through fence.sh `pp_gate_act` from a fixed per-script list (exclusions named with their reasons), so no act runs before or between checks; the merge reads its close and Post-merge lists in step 1, before the squash; the What can go wrong row gains pass 9's orderings and the stubbed act runs; same test file
- 2026-11-05: judge sol r2 F6 accepted: the args file's fourth line is the service name, so R4 finds a driver whose run trap removed the owner file; start's trap removes the args file on a refused start; Data design reworded; new case `driver crashed past its owner file is restarted once`
- 2026-11-05: judge sol r2 F7 accepted: R4b waits while the driver runs (its collect stops the unit with `no verdict`), then resumes it; R3b, R4 and R4b write their row only after a start that exits 0; DF1 reworded; new cases `dead plan seat under a live driver waits for its stop`, `refused restart leaves no once-row`
- 2026-11-05: judge sol r2 F8 accepted: new R3b relaunches a ready Builder whose pane is gone by `seat.sh launch builder` (no plan gate) once, closing the old task; accepted failure mode for the model override it does not repeat; new case `ready Builder task with no pane relaunches once`
- 2026-11-05: judge sol r2 F9 accepted: the send trial runs per agent (claude, codex) and records `send.<agent>`; each CG3 site moves only for an agent whose trial passed, so a Mac Codex pane keeps its typed path; new case `Codex pane with unproven send keeps typed answer`
- 2026-11-05: judge sol r2 F10 accepted: `replanning` reads the newest `launched=`, not the minimum with the kept `first=`; the mod reads a newest NO-GO judge record as planning; new cases `relaunched judge with kept first reads planning`, `collected NO-GO judge reads planning in the pane`
- 2026-11-05: judge sol r2 F11 accepted: an alerts summary line (output over 600 bytes) is classed from the whole-text file it names; new case `long crit alert summary still wakes`
- 2026-11-05: judge sol r2 F12 accepted: the supervisor publishes, at start, every wake file newer than its stamp, so an event a watcher marked seen before a shutdown is not lost; new case `event consumed before shutdown is published at next start`
- 2026-11-05: judge sol r2 F13 accepted: the supervisor types a `now` line into its pane and keeps running (#576's own Change text), exiting only on a failed send or the three-deaths exception; DF4 and DD9 reworded; D11 (the owner's Q11 b) stands: the hook's relay branch still goes; new case `two inbox events wake the relay twice with no re-arm`
- 2026-11-05: judge sol r2 F14 accepted: CD4's table gains the inbox `--full` and check `--full` readers (12 and 5 sites), the captures add both verbs, and a Builder check sweeps every orchestration read; new cases `inbox full row missing a field leaves the other rows read`, `check full batch missing payload is refused by pp_orca_full`
- 2026-11-05: judge sol r2 F15 accepted: heading() reads no heading inside an HTML block (types 1-5 to their end marker, any other `<` line to the next blank line, the fail-closed side); new cases `setext underline inside an HTML block is not a heading`, `heading inside an HTML comment is not a heading`
- 2026-11-05: judge sol r2 F16 accepted: C2 ends at its clean DONE line after a started turn; CE4 replaces that end with `watch_unit`, so no cut calls a later cut's function
- 2026-11-05: judge sol r2 F17 accepted: the automatic push answer is `yes: closing GO and green checks on <tip8> (auto-decided)`, the ending relay-order.sh:84 reverses; new case `owner no reverses an auto-answered push` in relay-order.test.sh, its step added
- 2026-11-05: judge sol r2 F18 accepted: the receipt shows `edits not recorded` (the owner's Q14 pick) instead of counting the 3 newest tool rows; case renamed `receipt shows step, running tool, edits not recorded`
- 2026-11-05: judge sol r2 F19 accepted: the CG1 consistency test checks retired entry points only, with the trial's own files excepted, the CG2 claims' scope
- 2026-11-05: judge sol r2 F20 accepted: the conditional settle case goes into seat-settle.test.sh beside its working-pane cases; seat-settle-pane.test.sh leaves Steps
- 2026-11-05: counts follow: New tests 206 -> 226 (20 new cases); Planned size 117 -> 116 files, 5090 -> 5290 lines; 11 claims, 8 facts, 8 Break lines, 3 accepted failure modes and 5 decisions (DC7, DE9, DF9, DF10, DH8) added, D7 reworded; the CD4 parser table moves to `## Parser inventory` so `## Cuts` fits its cap
- 2026-11-05: judge sol r3 F1 accepted: helper-apply.sh refuses a child whose `ls-files -v` shows an assume-unchanged or skip-worktree path (worktree-sweep.sh:24-25's rule), before any apply; new case `assume-unchanged edit in helper refuses removal`
- 2026-11-05: judge sol r3 F2 accepted: the supervisor acks each wake file by name after its own proven delivery; no global stamp; start publishes unacked files whose writer is dead; DF4 reworded; new case `other watcher's later delivery does not ack an earlier event`
- 2026-11-05: judge sol r3 F3 accepted: DE9 reads HTML types 6 (block tag names) and 7 (one complete tag, not after a paragraph) as CommonMark does; any other `<` line is text; new case `less-than text before a heading keeps the heading`
- 2026-11-05: judge sol r3 F4 accepted: C3 produces the turn start: `result` keeps `.start` and `--state` prints `start=`; Codex reads its `task_started` row; D7 reworded; new case `state output carries turn start`
- 2026-11-05: judge sol r3 F5 accepted: serena-shared.sh `start` sources hooks/lib/project.sh and runs `pp_project "$WT"`, so PP_PROJECT is set under `set -u`; new case `start with PP_PROJECT unset names the project`
- 2026-11-05: judge sol r3 F6 accepted: K = `<PP_PROJECT>-<cksum of PP_PROJECT_DIR>` keys both H and P, so `/a/app` and `/b/app` get two project folders; DC7 and Data design reworded; new case `same-named repos at two paths get distinct project folders`
- 2026-11-05: judge sol r3 F7 accepted: `inbox_wake`, its history files and main-watch-inbox-wake.test.sh stay; it skips only panes whose agent's send trial passed; the delete step goes; new case `mixed send record keeps the typed wake for the Codex pane`
- 2026-11-05: judge sol r3 F8 accepted: an ended pane with an open question gets the answer by `pp_follow_up` (the proven route) and a thread reply `answered: <TAG>`; a pane inside `orchestration ask` keeps the full-text reply; new case `ended pane with open question gets follow-up and thread reply`
- 2026-11-05: judge sol r3 F9 accepted: recover-stalls.sh never calls `digest` or `post`; main-watch's new `recover_tick` reads its `recovered:` and `ask:` lines; new case `recovery ask line reaches post once` in main-watch-dead-seat.test.sh
- 2026-11-05: judge sol r3 F10 accepted: `templates/chief-of-staff.md` does not exist; the relay's re-arm text is hooks/agent-startup-context.sh:139-144, edited by CF3; CF4's template step is templates/main-session.md reader lines only
- 2026-11-05: judge sol r3 F11 accepted: CG2's poller move and relay re-arm drop run whatever the wake trial says; only the deletion of await-agents.sh and watch-agents.sh waits for `wake.result = pass`; Q9 a (CF3 leaves the poller) and D11 kept; consistency case renamed `wake record gates wait-loop removal`
- 2026-11-05: judge sol r3 F12 accepted: a supervisor send counts only with `turn_started` in its receipt (main-watch.sh:710's test); otherwise the file stays pending, retried, and after three tries the supervisor exits with the line; new case `accepted send with no turn started stays pending`
- 2026-11-05: judge sol r3 F13 accepted: the accepted failure mode and the CG2 supervisor Builder check now expect a supervisor that keeps running after a delivered `now` line
- 2026-11-05: judge sol r3 F14 accepted: Parser inventory gains task-create, worker-start and the `.ok` readers of send, reply and task-update; the done sweep covers every verb; captures and 8 fixtures added; new cases `task-create reply yields the task id`, `worker-start refusal reads the error message`, `send and reply readers need ok true`
- 2026-11-05: judge sol r3 F15 accepted: cos-watch-units.sh is a supervisor child (class escalation) and the startup arm list becomes the supervisor line; new cases `units watcher runs under the supervisor`, `startup arms one supervisor`
- 2026-11-05: judge sol r3 F16 accepted: `Each new test names the bug it catches.` stays in the template; only the Extra tests and cap text go (272 bytes, not 314); stated limit recomputed; new case `template keeps the new-test naming rule`
- 2026-11-05: judge sol r3 F17 accepted: a tool call is running only when no `tool-end`, `tool-refused`, `batch-end` or (for a helper's call) `subagent-stop` names it; new case `refused tool is not shown running`
- 2026-11-05: judge sol r3 F18 accepted: the narrow-width branch of `summaryLine` is dropped (its only production caller, units.tsx:259, has no width); signature unchanged
- 2026-11-05: owner condition on F11 (via main, the owner's answer under /maxauto: keep F11 as revised, no fallback mail-watcher restart): cos-check.sh leaves the supervisor's children so it outlives a dead supervisor, names `supervise` (and `units`, a pre-existing gap) down, and logs a clean check instead of waking; DF5 reworded; new cases `dead supervisor is reported down`, `units watcher down is named`; `clean check line does not wake` moves to cos-check.test.sh
- 2026-11-05: counts follow: New tests 226 -> 245 (19 new cases); Planned size 116 -> 125 files (8 fixtures, 2 test files; templates/chief-of-staff.md out), 5290 -> 5520 lines; 4 claims, about 20 facts, 14 Break lines added; CF2's recovery list and CE3's table move to `## Recovery rules` and `## Template cuts`, and Facts and Steps lines are shortened, so `## Cuts`, `## Facts` and `## Steps` fit their caps
- 2026-11-05: judge sol r4 F1 accepted: helper-apply.sh refuses removal while the child holds an ignored file the parent lacks or holds with other bytes (`ls-files -o -i --exclude-standard`, hash compare), before any apply; new case `ignored file only in helper refuses removal`; stated limit and claim added
- 2026-11-05: judge sol r4 F2 accepted: scripts/paths.sh sources hooks/lib/project.sh after project-main.sh (:57), so orca-wait.sh (:76), run-bound.sh (:22), setup.sh (:727) and board.sh (:64) have pp_orca_run_id before first use; new case `run-current fallback works with no saved run in every reader`; step added
- 2026-11-05: judge sol r4 F3 accepted: each watcher prints and flushes a find before its seen or told mark (alerts, limit and units reordered; decisions already does), so an empty wake file means no mark moved; DF4 and CF3 reworded; accepted failure mode (a duplicate tell after a mid-print kill) added; three new cases `alert/limit line/idle unit killed at its mark is still in its wake file`; 3 files added to Steps
- 2026-11-05: judge sol r4 F4 accepted: DE9's type-1 openers `<script`, `<pre`, `<style`, `<textarea` need a space, tab, `>` or line end after the name (CommonMark 0.31.2), case-blind, in fence.sh and the merge-rules.py twin; new cases `script-prefixed word opens no HTML block` and `twin: script-prefixed word opens no HTML block`
- 2026-11-05: judge sol r4 F5 accepted: `terminal split` prints a `split` record; the guard resolves the `--terminal` pane's worktree from `terminal list --json` and checks it, blocks a split with no `--terminal` or an unlisted handle (`terminal split --help`, Orca 1.4.248: `--terminal` optional, no `--worktree`); three new cases
- 2026-11-05: counts follow: New tests 245 -> 255 (10 new cases); Planned size 125 -> 128 files (cos-watch-alerts, -limit, -units), 5520 -> 5720 lines; 5 claims, 15 facts, 10 Break lines, 1 accepted failure mode, 1 stated limit added
- 2026-11-05: section caps after r4: about 40 Facts claims reworded shorter, 4 near same-file citations collapsed to one range, 2 new facts folded into existing ones (project.sh:7-113, duplicate-agent-guard.sh:233-242), 3 Steps parentheticals and 2 Cuts asides dropped; no claim, citation target or step changed
- 2026-11-05: judge sol r5 F1 accepted: `session_state` (read-verdict.sh:168-172, the `--state` reader) now reads the log through `pp_json_clean`; the helper moves to new scripts/json-clean.sh (fence.sh's pattern), sourced by paths.sh and at the top of read-verdict.sh, so it exists before the `--state` dispatch at :418. Not paths.sh sourced earlier: sourcing it costs 0.12 s (`time bash -c '. scripts/paths.sh'`, 3 runs, 2026-11-05) on a path main-watch runs per Builder per tick. `given_spec` (:225) stays: its `fromjson?` skips a bad row without `.bad`, and the rows it needs are script-written prompts. Reproduced: `printf '{"a":"x\\ud83dy"}\n' | jq -Rn '[inputs|fromjson?]'` prints `[]` (jq 1.8.2, 2026-11-05). New case `state reads a finished turn past a lone surrogate`
- 2026-11-05: judge sol r5 F2 accepted: `inbox_wake` skips per message, not per pane: for a passed agent only an own-thread message (`(.thread_id // .id) == .id`, the `orchestration send` shape the trial proves) is dropped; a reply keeps the typed pointer. Bad input: a message with no `thread_id` reads as own-thread (`// .id`, as pp_open_ask reads a question); a junk `thread_id` never equals `.id`, so it keeps the pointer (the safe side). New case `a reply to a passed pane keeps the typed wake`
- 2026-11-05: pre-existing fix: the `inbox_wake` fact cited main-watch.sh:316-335; the function and its comment are :302-332 in this checkout (re-observed 2026-11-05)
- 2026-11-05: counts follow r5: New tests 255 -> 257 (2 new cases); Planned size 128 -> 129 files (scripts/json-clean.sh), 5720 -> 5750 lines; CB2 est. 100 -> 115; 2 claims, 3 facts, 1 Break line added
- 2026-11-05: section caps after r5 (each was within 30 bytes of its cap): CB2 and CG3 case details live in Claims to falsify only; CB2's jq repro points to Assumptions; 15 Facts citation pairs within 40 lines collapsed to one range; 7 Steps and 5 Break site texts reworded shorter; the CB2 `session_state` Break line dropped (a changed read, not a new check or conditional write)
- 2026-11-05: judge sol r6 F1 accepted: an HTML block wins over a fence line inside it (DE10): `fence()` opens nothing while `heading()`'s `hblk` is set, and merge-rules.py's `parse()` takes the twin's HTML state first; new cases `fence line inside an HTML block opens no fence`, `twin: fence line inside an HTML block opens no fence`, `Question heading after an HTML block tilde line holds the gate`
- 2026-11-05: judge sol r6 F2 accepted: the send record is keyed by agent and host (`send.<agent>.<host>`, `uname -s`); new `pp_send_form` gives the form only for this host's exact `pass`, read by `pp_follow_up` and `inbox_wake`, so a PC Codex pass leaves a Mac Codex pane typed (DG7); new cases `PC send pass leaves a Mac Codex pane typed`, `PC send pass keeps the Mac Codex inbox pointer`; #585's Done line names the host limit
- 2026-11-05: judge sol r6 F3 accepted: C4 also moves README.md:4's version badge (image URL and alt text) to the new version; plugin.test.sh:33 stays as is
- 2026-11-05: caps after r6: 45 Break-line site texts shortened to their function or check name (labels and files unchanged), the Break lines' Layout bullet dropped (the per-cut headings say it); two dispatch-task.sh facts and two merge-rules.py facts merged
- 2026-11-05: counts follow r6: New tests 257 -> 262 (5 new cases); Planned size 5750 -> 5790 lines (files unchanged: README.md, paths.sh and the test files were already listed); CE1 est. 230 -> 240, CG3 140 -> 150; 2 decisions, 3 Break lines, 2 claims, 2 facts added; CG1's Why-a-new-script bullet and 3 Steps or Facts texts shortened to stay under the caps
- 2026-11-05: judge sol r7 F1 accepted: `closingGo` is the verified `BUILDER_PROOF` rule `closing GO` (DC6), not the highest round's last line, so a narrowed GO under `closingPass` no never auto-answers; `closingGo reads the highest numbered round` renamed `closingGo is true only on rule closing GO`; new cases `closingGo is false on a narrowed GO with no closing pass`, `closingGo is false on a first-pass GO`; the two round-file facts replaced by the proof-rule facts
- 2026-11-05: judge sol r7 F2 accepted: a backtick run with a backtick after it opens no fence in fence.sh and merge-rules.py (DE11, CommonMark 0.31.2); new cases `backtick span line opens no fence`, `twin: backtick span line opens no fence`, `Question heading after a backtick span line holds the gate`
- 2026-11-05: judge sol r7 F3 accepted: the automatic yes runs `answer` with `COMMANDECK_MAIN_TOLD=1` and sends main one to-main.sh message from any cwd (DC7); manual answers keep tell_main's main-checkout suppression; new cases `auto push answer from the main checkout tells main once`, `manual push answer in the main checkout sends main nothing`, `auto push answer with main unreachable says not delivered`; one accepted failure mode (send exit 1) added
- 2026-11-05: counts follow r7: New tests 262 -> 270 (8 new cases); Planned size 5790 -> 5830 lines (files unchanged: every touched file was listed); 3 Break lines, 3 decisions, 2 claims added; caps: Break-line sites drop the `scripts/` prefix (no reader parses a site), CC3's Why-#656 bullet shortened; Facts: the deliver_answer and tell_main facts merged into one decision.sh:67-96 fact, the dispatch-task.sh and merge-rules.py claims reworded shorter (citations unchanged)
- 2026-11-05: judge sol r8 F1 accepted: closed-worker follow-ups get a production route (DG8): `pp_follow_up` on a handle Orca no longer lists sends `--to dispatch:<id>` from the seat record's last task, records `prior_pane=` and the reopened `handle=`, and gates on a separate `send.<agent>.<host>.closed` pass; answer-worker.sh:143 and seat.sh revise :301 use it; the trial's closed case opens and closes its pane as seats do and calls `pp_follow_up` itself; builder-fresh-round.sh keeps its gone-pane fail (a closed Builder is relaunched, answer queued); new cases `closed seat pane reopened by its dispatch gets the answer`, `closed pane without a closed-send pass keeps the refusal`, `revise of a closed seat reopens it by dispatch`; one Builder check (worker-show's handle field)
- 2026-11-05: judge sol r8 F2 accepted by removing the rewrite: CF4 edits no templates/main-session.md rule (DF9; it has no inbox-dump or merge-log reader line, and its board lines already use the bounded default), so no rule id changes and saved `keep-mine` choices such as c34eb141 hold; the Steps line for templates/main-session.md is dropped; claim `CF4 changes no rule id` added
- 2026-11-05: judge sol r8 F3 accepted: absent and null differ (DH9): a key the snapshot lacks draws nothing, a null draws its placeholder, so the existing fixtures (no new keys) keep units-panes.test.tsx:61-66 and :71 unedited; the where word moves from the merged row to one `whereLine` after the MERGED TODAY rows (DH3), `mergedModel` unchanged; new case `absent field draws nothing, null field its placeholder`
- 2026-11-05: judge sol r8 F4 accepted: a merge refusal stops the driver only when the merge record's line 1 (the tip the job tried, main-watch.sh:1111) equals the worktree HEAD; the `.rc` generation check stays; new case `merge refusal of an earlier attempted tip does not stop a newer HEAD`
- 2026-11-05: judge sol r8 F5 accepted: board.sh has no `--brief` (board.sh:48 reads it as a unit name); CF4 names no board flag, its board reader is the bounded default (board.sh:33-44), folded into DF9
- 2026-11-05: counts follow r8: New tests 270 -> 275 (5 new cases); Planned size 129 -> 128 files (templates/main-session.md dropped), 5830 -> 5980 lines (CG3 150 -> 200, CG1 170 -> 185, CF4 130 -> 120, test cases); 3 decisions (DF9, DG8, DH9), 4 Break lines, 4 claims, 1 Builder check added; CG1's closed trial runs after CG3 lands `pp_follow_up` (it calls it); CG1 Consumes names dispatch-show, terminal create/close and the paths.sh helpers, not worker-release
- 2026-11-05: main's r8 follow-up accepted as (a): CF4 caps a top-10 dump key in the script that prints it, through new `pp_cut_output` (paths.sh, board.sh:38-44's form, DF10); board.sh and orca-wait.sh are already cut; a key no plugin script prints goes to Progress and #608 merges as Refs; no template rule reworded (DF9 holds); new test file paths-cut-output.test.sh with `dump over the cap is cut with a pointer to the whole file` (written and run red first) and `output under the cap passes whole and saves no file`; New tests 275 -> 277; Planned size 128 -> 129 files, 5980 -> 6040 lines (CF4 120 -> 180); 1 decision, 1 Break line, 1 claim, 1 step; CF4 trimmed to fit the Cuts cap (rank columns, re-arm evidence)
- 2026-11-05: caps after main's follow-up: Break-line sites drop the `hooks/` prefix and `watch_unit` reads `watch` (labels and files unchanged); the units-elements.ts step names the element functions by CH3; two facts reworded shorter (citations unchanged)
- 2026-11-05: judge sol r9 F1 accepted: a setext heading's title is its whole plain paragraph (lines trimmed, joined by one space, whitespace folded), new decision DE12 (CE1 points to it), so a two-line `Question for` / `the owner` title opens the question gate; new cases `multiline setext title reads the whole paragraph` (fence-heading.test.sh), `twin: multiline setext title reads the whole paragraph` (merge-rules.test.sh), `multiline setext Question heading opens the gate` (unit-drive.test.sh); no new Break lines: they refine heading() and qopen, whose Break lines (fence-heading.test.sh, unit-drive.test.sh qopen) stand
- 2026-11-05: judge sol r9 F2 accepted: DG8 resolves the record's bare `worktree=` name to `<workspace>/<name>` as seat.sh:86-87, :93, :113 do (another repo's record by its `<repo>@` file name) before `pp_worktree_panes`; a name holding `/` or empty is a bad input (return 3); the trial writes its record in seat.sh:663's shape with a bare name; the reopened-pane fixture uses `worktree=u` with the pane at `$PP_WORKSPACES/u`; new case `closed seat of another repo resolves its workspace by record name` (answer-worker.test.sh), under DG8's existing pp_follow_up Break line; Builder check line updated
- 2026-11-05: counts follow r9: New tests 277 -> 281 (4 new cases); Planned size 6040 -> 6090 lines (CE1 240 -> 260, CE2 55 -> 65, CG3 200 -> 230), files unchanged at 129
- 2026-11-05: caps after r9: the setext title detail sits in DE12 (CE1 points to it, Cuts at its cap); Facts merged to fit: the two worktree-sweep facts, the two answer-worker.sh:310-316 facts and the two main-watch.sh:923 facts each became one
- 2026-11-05: judge sol r10 F1 accepted: CG3 no longer deletes answer-worker.sh's re-type branch, `idle` or `working`; they stay for the reply-only route (an `orchestration ask` reply returns as a tool result, which C3 rejects) and for agents with no send pass on this host, and only the `pp_follow_up` route drops the re-type (new DG9, CG3 points to it); new case `reply-only answer to an asking worker is typed once its turn ends`; `tool-result tag is not delivered` is unchanged; no new Break line: the branch is existing code, kept, not a new write
- 2026-11-05: judge sol r10 F2 accepted: CE1 adds `hold()`/`flush()` to PP_AWK_FENCE, which hold an open plain paragraph's lines until it ends and drop them when a setext underline makes them a title; CE2's `qsection` and `qopen` print or count only what those return, so a `Steps` / `-----` heading after a closed `None:` section no longer reopens it (new DE13); new cases `setext title lines stay out of the section they end` (fence-heading.test.sh), `setext heading after a closed Question section keeps it closed` (unit-drive.test.sh); no new Break line: hold() is a reader change under the existing `setext Question heading opens the gate` Break (unit-drive.sh qopen)
- 2026-11-05: judge sol r10 F3 accepted: the guarded bridge branch has six checks, not five (serena-shared.test.sh:213, the no-address refusal); CC2, D3 (#652), User-visible changes and Done now name six, and the no-Serena case fails on a missing label (new fact for :196-213)
- 2026-11-05: counts follow r10: New tests 281 -> 284 (3 new cases); Planned size 6090 -> 6110 lines (CE1 260 -> 270, CE2 65 -> 75), files unchanged at 129; 2 decisions (DG9, DE13); caps: the two answer-worker re-type facts merged into one to make room for the six-check fact
- 2026-11-05: citation fix found in r10: C3 cited read-verdict.sh:128-129 for the Claude prompt shape and :146 for the tool-result rejection; the user-row prompt test is :132-133 (a tool-result row has no `text` part), :146 is the queued_command branch; C3 and DG9 now cite :132-133
- 2026-11-05: judge sol r11 F1 accepted: R6's 3 tries 5 s apart outran decision.sh's `timeout 20` (decision.sh:74); R6 now retries inside a 12 s list budget (each read capped by the time left), leaving 8 s for the send; two new cases run through decision.sh with a real `timeout 8`; Timed checks line added
- 2026-11-05: judge sol r11 F2 accepted: CH2's `running` treated any earlier `subagent-stop` as the end of a helper's call; `tools` is now made in dashboard_builders.jq from its `$endedSet`, whose stop must follow the call (:39-41); step added for that file; new case `helper call after its stop is shown running`
- 2026-11-05: judge sol r11 F3 accepted: Steps' answer-worker.sh line and CG3's Produces said no re-type; both now keep the re-type for reply-only and no-pass panes, as DG9 says (DG9 is the newer rule)
- 2026-11-05: judge sol r11 F4 accepted: Data design said decision.sh never writes unknown keys; the answer branch copies the whole row (decision.sh:288), so the contract now says they pass through unchanged; no writer change; claim added
- 2026-11-05: counts follow r11: New tests 284 -> 287 (3 new cases); Planned size 129 -> 130 files (scripts/dashboard_builders.jq), 6110 -> 6150 lines (CF2 est. 260 -> 275); 3 claims, 6 facts added; caps: Steps' duplicate answer-worker.test.sh line dropped (the ~29 line adds the new cases)
- 2026-11-05: main answer-1793887615-82495 (msg_925920a24cfb): the new-test cap for this unit is 287, set by main (owner ruling 2026-10-30, main decides cap questions); the draft plan is added as this plan file to carry the `New tests:` line; no test is cut
- 2026-11-05: review sol r4 (class queued-wake-retry) supersedes r3 F12's retry of an accepted send: a receipt `ok` with `accepted: true` and no `turn_started` is the text in a busy pane's queue, which submits it when its turn ends (the #586 submit trial); retrying it typed the same wake three times. The supervisor's receipt reader now takes two shapes (turn_started; accepted into the queue) and retries every other one, its receipt logged. Case `accepted send with no turn started stays pending` becomes `refused send stays pending` (receipt `accepted:false`); new case `queued send is typed once and acked`. Known gap: a queued text Orca accepted and the pane then lost is not retried (the trial is the proof it is submitted)
- 2026-11-05: review sol r4 (class symlink-loss): helper-apply.sh copies an untracked symlink as a link (target kept) and proves each path equal as a link to the same target, never by the bytes it points at; a dangling link is copied too; new case `untracked symlink is applied as a link`
- 2026-11-05: main answer-1793892975-98721 widens #665: the Mac refusal also reads a test file named inside a wrapper (timeout, nohup, nice, command, exec, env, `bash -c`) or by a short path after an earlier `cd`; only the runner (wrapped or not) and a reader command pass; new case `a wrapped run or one after cd is refused too; the wrapped hand-off and a reader pass`
- 2026-11-05: main answers answer-1793897806-20012 (Max via Skippy msg_f4e30219e8f2) and answer-1793897920-58931 widen #665 to tests a script starts: new scripts/test-host-guard.sh, loaded through `BASH_ENV`, refuses (exit 2, naming scripts/run-shell-tests.sh) a `__tests__/*.test.sh` started on the Mac without the runner's marker `COMMANDECK_TEST_RUNNER`, which run-shell-tests.sh sets for each file it starts; builtins only, silent on a non-match, safe under `set -u`, inert off the Mac. Main adds `BASH_ENV=<main checkout>/scripts/test-host-guard.sh` to the settings env at merge. New test scripts/__tests__/test-host-guard.test.sh `a test file a script starts on the Mac is refused unless the runner started it` (cap 289, main's call)
- 2026-11-05: review sol r11 (trial-format-mismatch): the send trial recorded Orca's flag text `--to handle` as its form, which `pp_send_form` never reads; it records `handle`, and `record_result` refuses any form but `handle` or `dispatch` (the writer takes only what the reader reads); case `send entry keeps its form, the one pp_send_form reads, and another form is refused`. Review sol r11 (unfinished-trial): `send <agent> closed` is built as DG8's trial says (seat-shaped pane, settle, close, `PP_FOLLOW_UP_TRIAL=1 pp_follow_up`, pass on the reopened pane listed, named by the record and answering); new case `the closed send trial reopens the pane by its dispatch and records its own key` (cap 290 asked of main)
- 2026-11-05: review sol r12 (guard-scope): the settings give every project `BASH_ENV`, and scripts/test-host-guard.sh refused any `__tests__/*.test.sh`; it now refuses only a Commandeck checkout's test by the hook's rule (bash-guardrails.sh:489: the `__tests__` folder in a checkout holding scripts/run-shell-tests.sh), and reads `./x.test.sh` (found red in the same test) like a full path; case `a test file a script starts on the Mac is refused unless the runner started it` gains `./` and another project's test (runs)
- 2026-11-05: review sol r16 (placeholder-ui): the receipt's three `not recorded` texts are the owner's Q14 pick (D9) but had no `Placeholder:` line; CH3 now names both source lines (hooks/units-elements.ts:213-214). (config-scalar-parsing): serena-shared.sh's `folder_line` reads the folder value by allowlist (double-quoted without backslash, single-quoted without inner quote, or a plain path, each with an optional ` # comment`) and refuses any other shape naming the line before a config is written; the start fails with it.
- 2026-11-05: review sol r17 (recovery-retry-loop): R3b, R4 and R4b wrote their row only after a start that worked (pass 13), so a refused start was retried every tick and main was never asked. Every recovery now follows one rule: the row comes before the act, and a failed act asks main once with the tail of its error (recover-stalls.sh `try`/`error`). The Data design line Recovery once-file (row before the act) now holds for every recovery, with no exception.
- 2026-11-05: review sol r18 (completed-driver-restart): a driver that ended DONE (merged, or launched with no Builder record to watch) left its args file and wrote no done file, so R4 restarted a finished unit. unit-drive.sh `ended` removes the args file on both DONE exits; R4 skips a unit with a merged row at or after its driver's start epoch, and R4b skips a seat of a unit merged since that seat launched. So the skip holds however the file was left behind. The Driver args Data design line says so.

# wake-waste-2026-11-04 -- one wake rule, recipient routing, owner reply check

Owner's words: the owner, 2026-11-04: plan and build a plugin unit for issues #642, #643 and #644 now, at the same time as the host's own unit for the same three fixes. Do not wait for the host's version and do not port from it; this unit is designed from the plugin's own code.
Main's addition A: the owner's question to main, 2026-11-04 (why must main be an Orca coordinator at all), relayed: test main with no bound coordinator first, before any filtering; list every place that needs a bound coordinator, test each with --run from an unbound pane on a throwaway Run, report what breaks.
Main's addition B: the owner's words to main, 2026-11-04 (those messages should not reach main's pane in the first place), relayed: zero Orca-typed "You have N orchestration message(s)" wakes in main's pane, or each remaining one has its reason written down.
Goal: One wake rule judges each inbox message (now, 30-min batch, 10-min repeat drop); the relay wakes only on its mail and owed replies and holds replies needing nothing.
Owner's ruling A: 2026-11-04, host plan: keep waking main at once for review GOs, pushes and merges (D25).
Owner's ruling B: 2026-11-03: job-finished wakes keep the copied limits, one an hour at most (D19).
Owner's ruling C: 2026-11-04, host plan: a stop check may refuse once a reply that is only verdicts, still-running lines or counts (D9).
Tier: Standard; LOCAL merge; changed-file tests on the PC; no timeout raises.
Closes: #642 #643 #644
Base: local main fca058c
Build order: P1-P3, P5, C1-C4 (C4 on P3's pass, D28)
New tests: wake-waste-2026-11-04 82
Timed checks: to-main.test.sh:185 (5 s); after it "await-agents ignores a status", "await-agents skips repeat" (1 s), "watch-agents shows gate once, unread", "watch-agents skips repeat" (3 s); "full page keeps question" last
Merge message: `Closes #N` per built issue; `Refs #N` if partial
- Planned size: 47 files, 990 changed lines

## Why

Main and the relay spend whole turns on messages that need nothing. Wakes are decided today by PP_JQ_WAKES, await-agents.sh's and watch-agents.sh's consuming checks, main-watch's Builder INBOX wake, the relay poller's subject regex and FYI hold, and the nudge hook's relay branch. PP_JQ_WAKES becomes the one rule, a class per message (now, batch, drop), and every inbox waker asks it with Orca's inbox page as repeat history. A required kind (question, decision gate, worker_done, escalation, the owner's words) is never batched; every Orca stopped notice is an escalation, its worker's only report (Assumptions). Senders mark an OK result as status, except the push, deploy, merge and seat results the owner keeps waking main. The drain's display hides stay, after the class. A batch clock spaces batches. Relay mail carries a recipient tag; untagged mail passes until the new main-watch runs. The owner reads the relay's pane and no hook runs before reply text prints, so the check is the relay's Stop hook (ruling C). The owner said yes to C4 (D28): it is built once every no-coordinator probe passes. No observer marks mail read, and a full page still yields its rows.
## Prior art

- Standard: alert routing with severity tiers, grouping windows, repeat windows and explicit recipients; Claude Code Stop hooks (decision block, stop_hook_active once per turn), as the plugin's own Stop hooks use them.
- Library or service: none new. Bash, jq and python3 as the scripts use them; the Orca CLI's existing message `payload` (or `--thread-id`) field for the recipient tag.
- Why build: the wake rules are the plugin's own; no Orca option filters or mutes nudges or stopped notices (P3 records the help text). Orca 1.4.247 added plugin hooks on terminal sends (stablyai/orca#37287); whether Orca's own typed nudge passes through one is P4, recorded only: an Orca plugin is not this unit.

## Data design

| State | Lives | Written by | Read by | Resets | Retry |
|---|---|---|---|---|---|
| Recipient tag `{"to":"chief-of-staff"}` | Orca payload; if P1 shows payload keys dropped, thread id `commandeck:to=chief-of-staff` | cos-tell.sh --note, main-watch.sh tell_relay | one jq def `recipient` (payload.to, else that thread id), used by wake_class, the relay poll and cos-own-echo.sh | never; one per message | a resend carries the same tag |
| Repeat history | Orca's inbox page (`inbox --limit 500 --full --json`, read rows included) | Orca | wake_class's `$all`, read by pp_inbox_actionable (main-watch, the nudge hook's main branch, await-agents.sh), the nudge hook's relay branch, the relay poll, the drain (once per delivery with a non-heartbeat row) and inbox_wake (its own `inbox --terminal` read) | Orca's own | a page not read is `[]`: no repeat, never a hidden row |
| Main batch clock `<epoch>` | $PP_SCRATCH/main-watch/batch-at | orca-wait.sh drain, when it prints a batch row | pp_inbox_actionable | each drain that prints a batch row | unreadable or absent reads as no clock (age rule alone) |
| Relay batch clock `since=<epoch>` | first line of $COS_KEY.inbox-seq, beside `pending`/`enc` | cos-watch-inbox.sh poll, under the inbox-seq lock (starts it, an empty inbox too; drops it when the notes print); cos-check.sh, under the same lock, drops it with the notes it clears | cos-watch-inbox.sh | dropped when held notes print, are cleared (cos-check.sh), or are empty | a failed save leaves the old file: the next poll recomputes, the next cos-check.sh clears again |
| Shown ids `shown` | watch-agents.sh process memory (a shell variable, one Orca message id a line) | watch-agents.sh loop, as it prints a row's ANSWER NEEDED lines | watch-agents.sh loop, before printing: an id in it prints no more | process start: empty, so a restart prints each still-actionable row once more; never pruned while the process lives (one id per row printed) | none needed: it marks nothing read in Orca, so a row it skips stays in main's inbox for the drain |
| Recipient cutover `<epoch>` | $PP_SCRATCH/main-watch/tags-relay | main-watch.sh, each tick while the file is absent | cos-watch-inbox.sh (D21) | never | a failed write is tried at the next tick; absent reads as no cutover yet |
| Dropped repeats | $MSGDIR/hidden.jsonl (existing) | orca-wait.sh drain | the owner and main by hand | never (existing) | none |
- Mixed versions: an old cos-check.sh keeps the first line whole (cos-check.sh:35); an old poller tests header words by membership only (cos-watch-inbox.sh:130-132) and its save drops `since=`, notes kept; an empty-notes header keeps no clock; notes with no clock start it at the next poll, an empty inbox too. Untagged relay mail: D21.
- Clock clear (cos-check.sh:33-37), under the inbox-seq lock: 1 copy the notes to $ARCH; 2 write line 1 without `since=` to inbox-seq.new; 3 move it over inbox-seq; 4 print the notes or $ARCH's path. Stopped after 1 or 2: the old file stands, notes and clock kept, $ARCH an extra copy; the next cos-check.sh clears them. Stopped after 3: notes and clock gone from inbox-seq; the notes are in $ARCH ($COS_KEY.cos-check-notes-<epoch>-<pid>.txt), the one recovery.

## Cuts

### Builder checks before C1 (record command and output in the evidence file)
- P1 recipient tag: from a throwaway Run, send `--to run:<R> --type status --subject p1 --payload '{"to":"chief-of-staff"}' --json`, and a second with `--thread-id commandeck:to=chief-of-staff`; read both with `inbox --limit 20 --full --json`. Payload kept -> writers use payload. Payload dropped, thread id kept -> writers use the thread id; readers read both from C2 on either way; log a plan change. Both dropped -> BLOCKED to main.
- P2 one-pane delivery: send `--to <busy pane B handle>`; pass only when B's own `orchestration check --peek` (run as B) lists it and main's and a third pane's checks do not. Record the result for #643; D7 holds either way; log it as a plan change line.
- P3 unbound coordinator (D16): from a pane that never ran run-use, on a throwaway Run: run-create (does it bind?), task-create, dispatch, worker-start --task, gate-create, task-update, reply, a worker's ask and worker_done, `check --run --peek`, consuming `check --run`, bare `check --peek` and `check --ack`; record the nudge text typed into the unbound pane (with or without `--run`) and count them; find whether a bound run can be left unbound; after the coordinating pane's turn ends, whether `worker-list` still lists the running worker (Orca 1.4.247, #37219); whether a dispatch reaches a worker terminal still bound to an older Run (1.4.248, #37548). Outcome per D11.
- P5 peek delivery id (before C2): from the relay pane, `orca-ide orchestration check --run <R> --peek --full --json` with one unread own-echo row; record whether `.result.deliveryId` is present, and, after a held unacked nudge, how many more nudges Orca types in 5 minutes. Present -> the own-echo ack uses the peek's id (D14). Absent -> own echoes are held unacked like any row (no turn spent either way); log a plan change.
- P4 nudge hook (record only, no build): with a development plugin listing `terminal.send`, trigger one orchestration message to a CLI pane and log whether the hook saw Orca's typed "You have N orchestration message(s)" text and its inputKind. Seen -> the evidence names the hook as the way to drop remaining nudges (addition B's reasons). Not seen -> the evidence says so. Neither changes a cut.

### C1 (#642) the one wake rule -- est. 300 lines
- Produces: `wake_class($k; $relay; $all; $for)` (`$for` main, relay or seat) and `recipient` in PP_JQ_WAKES, class now, batch or drop per D2, D4 and D24 (`$all` the inbox page); `wakes($k; $relay)` = class now with `$all` = [], kept only for the drain's held sort; main batch clock.
- Consumes: Orca rows (type, from_handle, to_handle, subject, body, created_at, sequence, payload, thread_id); pp_option wakeKinds (paths.sh:1234, accepted values unchanged).
- Changes: pp_inbox_actionable keeps now rows plus batch rows per D3 (COMMANDECK_NOW seam), its page passed as `$all`; a full page (500 rows) returns the actionable rows on it, and fails only when it holds none (today's unknown: main-watch.sh:664-665 keeps the wake, :593 arms none) (D27); orca-wait.sh reads the inbox page once per delivery with a non-heartbeat row, KEEP hides drop rows to hidden.jsonl unless from the relay, then applies its existing noisy/harness hides to now rows as today (D23), prints batch under held notes and writes batch-at; await-agents.sh sources paths.sh and stops on a non-empty pp_inbox_actionable array, never a consuming check (D20); watch-agents.sh does the same each poll and prints each row once per id, its heartbeat ack gone (D26); inbox_wake (main-watch.sh:307-330) keeps only rows wake_class(...; "seat") calls now (D24), its page passed as `$all`; long-job.sh:138 sends `status` on rc 0; wake-on-exit.sh:191 sends `status` on exit 0 unless EV is push or deploy (wake-on-exit.sh:160-163, D25); pp_detach (paths.sh:514) sends `status` on exit 0 unless its label starts `merge-` (D25); `question` otherwise; wake-on-exit.sh's hour stamp unchanged (D19); main-watch.sh's landed-merge post unchanged (a merge, D25); pp_relay_event sends main through to-main.sh, `status` on ok, `question` on fail (each caller already sends main its own result: D25's wakes come from those).
- Test edit (D18): reverse long-job.test.sh:209-216 to expect `status` for an rc 0; it still asserts the message reaches main; the edited lines' comment says the owner allows a test edit that keeps its claim (2026-10-30). to-main.test.sh:186-188 (a detached merge is a question) holds unchanged (D25); orca-wait.test.sh:67-73 holds unchanged (D23); main-watch-inbox-wake.test.sh's `msg` fixture gives each id its own subject (`answer <id>`), so its distinct messages stay distinct under D4 and every claim holds (D24).
- Test migration (D29), claims kept: wake-on-exit.test.sh:407-424 reads the to-main stub's body (one ok `status`, one fail `question` `FYI event:` line; 2 sends per push job; RELAY_LOG empty; the stub exits $EVENT_RC on an event, for RELAY_RC); ci-watch.test.sh:99-103, builder-launch-resume-launch-line.test.sh:138-141, merge-unit-local.test.sh:337-340 read their orca log plus queue/main.jsonl, counts kept, 0 `--to run:` events; seat-run.test.sh:82, seat-run-refused.test.sh:59-63 count $T/wakes plus $SQ, the log kept; seat-run.test.sh:84 reads main-session.md:132's new sentence.
- Audited, unchanged: main-watch-wake-sources.test.sh:26-30 (status: batch), main-watch-wake-race.test.sh (questions), agent-startup-context.test.sh:66-112 (C3 adds a line).
- Wake gates: a now row passes the existing wakeWindowSeconds window and claim (cos-own-echo.sh:43-44, main-watch.sh:671, :704), unchanged: see the limits section.
- Existing consumers: pp_inbox_actionable callers hooks/cos-own-echo.sh:38, scripts/main-watch.sh:593 and :669, and now await-agents.sh (same contract: an array of actionable rows); pp_seat_inbox (paths.sh:482, finish rows are worker_done or question: unchanged); orca-wait.sh:271, :552 and :571; await-agents.sh and watch-agents.sh have no script caller (main runs them; AWAIT: and ANSWER NEEDED line formats unchanged); inbox_wake's one caller main-watch.sh:1759 (Signal INBOX text and once-per-id history unchanged); pp_detach callers run-shell-tests.sh:76 and ci-watch.sh:14 (status on exit 0), merge-queue.sh:34 and merge-unit-local.sh:62 (labels start `merge-`: question, unchanged); pp_relay_event callers builder-launch.sh:304-305, ci-watch.sh:16, wake-on-exit.sh:165, seat.sh:254, merge-unit-local.sh:134 (same arguments; the note now goes to main; their suites per D29); seat.sh's own result to main (seat.sh:257, question: unchanged).

### C2 (#643) recipient routing -- est. 275 lines
- Produces: recipient tag on cos-tell.sh --note and main-watch.sh tell_relay; main-watch.sh writes $PP_SCRATCH/main-watch/tags-relay (D21); the relay's poll admits only rows to its handle or tagged for it in its run, plus D21's cutover rows, classed by wake_class(...; "relay"); relay batch clock and cutover word per Data design; the nudge hook matches both nudge forms (D22) and its relay branch peeks, never consumes, and holds unacked a delivery with no row the relay admits as now (D14); cos-tell.sh --note sends a `FYI event: ` subject untagged and keeps its owed exception (D21).
- Consumes: C1's wake_class and recipient, piped through jq before the poll's python.
- Removes: the subject regex `want`, the coordinator-wrote-it rule, the `FYI event:` rule and the subject exclusion list (cos-watch-inbox.sh:139-151); the FYI hold regex (:214, now in wake_class for the relay only). cos-tell.sh's `FYI event:` owed exception (:24-27) stays: an old process's pp_relay_event still sends through it (D21).
- Changes (D13, D17): main_silent (cos-watch-inbox.sh:67-86) keeps only its owed-reply flag (:77); the `what=anything` branch (:78), the main-turn file (:72-73), the main-sent write (:166-169, :244 argument) and their header comment (:36-49) go.
- Test edit (D12): tag relay rows reached by subject or as main's; reverse cos-tell.test.sh:98, :401, :415, each still asserting the routing; :391-394 unchanged: its `note "FYI event: ..."` is the legacy path and still expects `marked:cleared` (D21); a weaker line stops the Builder for main.
- Test edit (D29): cos-watch-inbox.test.sh:26-27 `row` tags every row in P1's form, so :31-43's wake-log claims hold.
- Test edit (D17): reverse cos-tell.test.sh:213-235 to expect no flag for a turn with nothing owed, the owed mark's kept/gone claims unchanged; drop the main-turn `rm` (:229); the comment at :211-212 says the owner allows a test edit that keeps its claim (2026-10-30) and names D17.
- Existing consumers: cos-check.sh (inbox-seq first line), main-watch.sh's $ST (tags-relay is a new file beside batch-at), dashboard_serve.py:184 (--note: now tagged, still wakes the relay), templates/main-session.md:132-138, hooks.json registration of cos-own-echo.sh (unchanged); the nudge RE (cos-own-echo.sh:24) has no other reader.

### C3 (#644) owner reply check -- est. 85 lines
- Produces: in cos-inbox-waiter-stop.sh after the relay guard (:23), a check of `last_assistant_message` per D9: a reply that is only verdict, still-running or count lines is held once (decision block, Owner's ruling C) naming the kind and matched words, the reason saying to end the turn as is if the owner must act; a rule line in the relay heredoc of agent-startup-context.sh.
- Consumes: the Stop payload. Existing consumer: hooks.json:121 registration, unchanged.

### C4 (main's addition A) main with no coordinator -- est. 150 lines, built per D11 and D28
- Produces: setup.sh records a run with no coordinator and writes main-pane.txt per D15; context-clear-restart.sh moves the record to the new pane per D15; board.sh, run-bound.sh, orca-wait.sh, resume-context.sh and main-watch.sh rebind stop calling run-use; orca-wait.sh and dispatch-task.sh pass `--run`; orca-task-create.sh adds `--run <run file>` when its args have none (the one path seat.sh:101 reaches); pp_is_main_pane's code-3 case compares the recorded main pane per D15; cos-watch-inbox.sh takes main's handle the same way.
- Existing consumers of pp_is_main_pane: board.sh:59, context-line.sh:48, context-clear-stop.sh:33, main-script-card.sh:15, main-background-only.sh:65, peer-code-sync.sh:16, bash-guardrails.sh:283 (same return codes); of main-pane.txt: board.sh:61-63 (writer, unchanged), main-watch.sh:549 (reader, unchanged); of orca-task-create.sh: main-watch.sh:232 and merge-unit-local.sh:619 (pass --run already: unchanged), seat.sh:101.

### Release -- est. 15 lines
- CHANGELOG.md 0.71.0 in the newest entries' plain style; .claude-plugin/plugin.json version.

## Routing

- Builder helpers name the model on every call: Sonnet general-purpose for test writing and mechanical edits per cut; Haiku Explore for searches.
- Codex passes run until clean.

## Steps

- modify scripts/paths.sh ~566 -- wake_class, recipient; batch rule; pp_detach status unless merge; pp_relay_event to main
- modify scripts/orca-wait.sh ~552 -- page per delivery; drops hidden, batch held, batch-at
- modify scripts/{long-job,wake-on-exit}.sh -- status on exit 0; push, deploy stay question
- modify scripts/await-agents.sh ~67 -- stop on pp_inbox_actionable, no consuming check
- modify scripts/watch-agents.sh ~42 -- pp_inbox_actionable, once per id; no consuming check or ack
- modify scripts/main-watch.sh ~307 -- inbox_wake via wake_class seat; tell_relay tag; tags-relay
- modify scripts/{cos-watch-inbox,cos-tell,cos-check}.sh -- recipient tag (not events), wake_class, relay clock, cutover
- modify hooks/cos-own-echo.sh ~24 -- both nudge forms; peek; hold unacked
- modify hooks/cos-inbox-waiter-stop.sh ~23 -- hold a reply that needs nothing from the owner
- modify hooks/agent-startup-context.sh ~124 -- relay rule: tell the owner only what needs them
- modify {README.md,docs/chief-of-staff.md,docs/hooks.md,templates/main-session.md} -- describe the new rules
- modify scripts/__tests__/{to-main,orca-wait,orca-wait-drain,long-job,wake-on-exit,main-watch-inbox-wake,cos-tell,cos-check,cos-watch-inbox,seat-run,seat-run-refused,ci-watch,builder-launch-resume-launch-line,merge-unit-local,board,setup}.test.sh -- new checks (await/watch-agents in to-main); D29 migrations; C4 cases
- modify hooks/__tests__/{cos-own-echo,cos-inbox-waiter-stop}.test.sh -- nudge and owner reply cases
- modify scripts/{setup,board,run-bound,dispatch-task,orca-task-create}.sh -- C4 only: no run-use, explicit --run, main's record
- modify hooks/{resume-context.sh,lib/project.sh,lib/context-clear-restart.sh} -- C4 only: main by its recorded pane
- modify templates/checkpoint.md -- C4 only: drop the run-use advice
- modify hooks/__tests__/context-clear-restart.test.sh -- C4 record handover case
- modify {CHANGELOG.md,.claude-plugin/plugin.json} -- 0.71.0 notes and version

## Decisions already made

1. D1 The one rule is wake_class in PP_JQ_WAKES (scripts/paths.sh), extended; not a new script: every inbox waker but await-agents.sh already sources paths.sh.
   Test: no watcher keeps own wake rule
2. D2 Class, first match wins. Main: heartbeat drop; recipient chief-of-staff drop; relay-pane sender now; repeat (D4) drop; a required type (question, decision_gate, worker_done, escalation, so every Orca stopped notice, `finished` or `needs-input`) now, whatever wakeKinds says; another type wakeKinds lists now; else batch. Relay (rows its poll admits): heartbeat drop; repeat drop; an FYI subject on a non-required type batch; else now. Seat: D24. No subject rule for main; no payload wake tag; no text rule on stopped notices (Assumptions).
   Test: done-marker notice with action wakes now
3. D3 Batch delivery: a batch row is actionable when it is 1800 s old (no time reads as aged) and the main batch clock is absent or 1800 s old; so two batch wakes are at least 1800 s apart.
   Test: untimed row waits for clock
4. D4 Repeat: same type, sender, to_handle, recipient, subject, body and payload as an earlier row of the inbox page (Data design, read rows included) within 600 s; a page not read, or a row with no time, is no repeat; the relay's own words are never dropped.
   Test: acked question repeat dropped later
5. D5 Senders mark OK results by type: status on exit 0 or ok, question on failure, except the results D25 keeps waking (push, deploy, merge, seat); no new flag (the judge brief allows none).
   Test: ok test run status, merge question
6. D6 worker_done keeps waking at once: a worker's final report is the result main acts on. Decided under /maxauto, 2026-11-04.
   Test: worker_done wakes now
7. D7 The recipient tag stays whatever P2 finds: a pane handle changes on restart (cos-tell.sh:5), so mail to the old one is lost.
   Test: tagged note wakes only relay
8. D8 Relay batch: held FYI rows wake the relay once the clock is 1800 s old; mixed versions per Data design.
   Test: held FYI wakes relay at 30 min
9. D9 The owner check extends the relay's Stop hook (no hook runs before reply text prints; Owner's ruling C). Pass: any `?`; a QUESTION:/BLOCKED: line; an ask word (approve, decide, confirm, choose, pick, reply, roll back) opening a line (after a bullet, `>`, `**` or `Please`) or right after `you` (`can you confirm`); `your call`. Hold once: no pass form and every line a verdict, still-running or `N of M`/`N/M` count line (ruling C's "only"). A `%` limit line passes.
   Test: verdict with news passes
10. D10 Orca's stopped notices have no per-worker off switch (worker-start and dispatch help, 2026-11-04): they are classed per D2: now.
   Test: prompt wait wakes now
11. D11 C4 builds (D28) when every P3 command works unbound and a run can be left unbound; otherwise C4 is not built, each failure goes in the evidence and one QUESTION to main, and docs/chief-of-staff.md names why nudges remain.
   Test: main known by recorded pane
12. D12 Relay test rows that reach the relay by subject or as main's (cos-tell.test.sh:180-187, :222-226) get the recipient tag, claims kept; :98, :401, :415 reversed, each still asserting the routing, else the Builder stops for main; :391-394 unchanged (D21).
   Test: script event wakes main not relay
13. D13 main_silent keeps only its owed-reply flag (an owner's message main has not answered when its turn ends), at most once per mark; the flag for a turn with nothing owed goes, with its main-turn and main-sent files (D17).
   Test: silent turn nothing owed no wake
14. D14 The relay's nudge branch reads `check --run <R> --peek` (today's :54 check consumes main's rows) and the inbox page (D4); with no row wake_class(...; "relay") calls now it holds the nudge, acking nothing; it acks only all-own-echo deliveries (:58-60, P5).
   Test: relay nudge with no mail dropped
15. D15 With no coordinator, main is the pane in main-pane.txt when it is connected in main's checkout; no record, or one not listed, is not main (resolve_main refuses to guess, main-watch.sh:546-553). Writers: setup.sh records the pane that runs it in main's checkout when the run has no coordinator and no listed record, as run-create makes that pane coordinator today (setup.sh:729); context-clear-restart.sh moves the record beside pp_handle_record (:128) only when it names the old pane. A main opened any other way is not main until setup.sh runs in it.
   Test: setup records its pane as main
16. D16 Decided under /maxauto, 2026-11-04 (last round's Q1 (a)): keep additions A and B; P3 is A's test and report (C4: D28).
   Test: two panes no record not main
17. D17 Decided under /maxauto, 2026-11-04 (last round's Q2 (b)): the relay wakes only on mail addressed to it and on replies main owes the owner; cos-tell.test.sh:213-235 reversed to assert that.
   Test: owed reply wakes relay once
18. D18 Decided under /maxauto, 2026-11-04 (last round's Q3 (a)): long-job.test.sh:209-216 reversed, still asserting arrival at main as a batched status; to-main.test.sh:186-188 stays (D25).
   Test: ok job is status, failed is question
19. D19 wake-on-exit's hour stamp (wake-on-exit.sh:185-188) stays as is, label and exit, no checksum: Owner's ruling B. It acts before a message exists: a sender rule, not a watcher's (#642 Body 5).
   Test: none, the code is unchanged and wake-on-exit.test.sh:343-374 pins it
20. D20 await-agents.sh sources paths.sh and stops when `pp_inbox_actionable <run> "$ORCA_TERMINAL_HANDLE"` is non-empty (now, or a batch due per D3): repeats judged as main's, nothing marked read; a failed or junk read is no news; AWAIT_AGENTS_SKIP_MESSAGES unchanged.
   Test: await-agents stops on question, unread
21. D21 Cutover follows the writers: cos-tell.sh runs fresh per note; main-watch is the one long-lived old writer (main-watch.sh:182). New main-watch writes tags-relay (epoch E) when absent. Without it the poller admits main's untagged statuses to run:R (the old rule); with it, only those created before E. No subject is read by the poller. An old process's pp_relay_event (ci-watch.sh:12-16) calls the new cos-tell.sh --note with `FYI event: `: sent untagged, owed mark kept (:24-27), so the relay admits it only before E.
   Test: old watcher note admitted late
22. D22 The nudge hook matches `check --run run_…` and the bare `check` form; the bare form takes the run from $PP_RUN_FILE (main) and the relay branch runs `check` and `--ack` with the args the nudge named; no run file passes the prompt, as today.
   Test: bare nudge with nothing actionable held
23. D23 The drain's hides (KEEP's `noisy` and `harness`, orca-wait.sh:258-272) stay drain-only, after wake_class, on now rows, as today; drop rows go first, batch rows print held. Not in wake_class: they read systemctl and the pane-to-unit map.
   Test: driven verdict echo hidden, ok status held
24. D24 inbox_wake asks wake_class(...; "seat"): heartbeat drop, repeat (D4, its `inbox --terminal` page) drop, else now. A repeat stays unread for its next check. Fixture: one subject per id.
   Test: Builder repeat types nothing
25. D25 Owner's ruling A: push, deploy, merge and seat results keep waking main: wake-on-exit's push/deploy labels and pp_detach's `merge-` labels send `question` on exit 0 too; seat.sh's result and the landed-merge post stay questions.
   Test: OK ci exit status, push question
26. D26 watch-agents.sh reads pp_inbox_actionable (run from $PP_RUN_FILE), no consuming check, printing each row once per id as ANSWER NEEDED; its heartbeat ack goes: the nudge hook holds those (cos-own-echo.sh:40).
   Test: watch-agents shows gate once, unread
27. D27 pp_inbox_actionable on a full page returns its actionable rows; it fails, as today, only when it holds none (mail may sit past it).
   Test: full page keeps question
28. D28 The owner, 2026-11-04 (Q1 yes): build C4 in this unit once every P3 test passes. Builder, 2026-11-04: P3 failed (an unbound pane is consumer_fenced on task-create, task-update and check --run; a bound Run cannot be left unbound), so C4 was not built (D11); the evidence file records each failure. Main, 2026-11-04: C4's two Break lines (board.test.sh, context-clear-restart.test.sh) are deleted, since a cut not built has no break run.
   Test: no script binds main
29. D29 pp_relay_event keeps its run-file guard, subject and body, sends `to-main.sh status` on ok and `question` on fail (each caller already sends main its result), and logs any non-zero exit (3 queued, 1 refused) to relay-events.log; its suites migrate per C1, C2.
   Test: ok event note batched

## Accepted failure modes

- The owner check runs after the pane printed the reply (Owner's ruling C allows this refuse-once Stop check): it holds the turn, costing one short turn, and logs the kind; it cannot hide the text. A false hold (an ask with no listed form) costs that one turn only; the reason says to end as is.
  Test: action line with count passes
- With main-watch down, a batch waits for main's next real wake.
  Test: none, main-watch down already raises its own doctor alert and no new path runs
- Until the new main-watch first ticks, the relay still gets main's own untagged statuses to the run (today's rule); where main-watch is never installed (setup with a plan, setup.sh:646) that lasts until it is.
  Test: old untagged note reaches relay

## Assumptions

- [settled] Orca returns payload as a JSON string: `orca-ide orchestration inbox --limit 400 --full --json | jq '[... .payload | type]'` gave null 320, string 80 (2026-11-04).
- [settled] A stopped notice is type escalation, subject "Worker stopped without reporting", payload stopReason `finished` (46 of 400 rows), or `needs-input` (subject "Worker is waiting on a prompt"), its worker text after `Last output:`, closed by a `Full output:` line (same command, 2026-11-04).
- [settled] 0 of the 46 had a worker_done for its payload dispatchId in the page: each is its worker's only report (jq over the same page, 2026-11-04).
- [settled] Of the 46, 14 end in a done marker with no `?` or QUESTION:/BLOCKED: line, and their last lines still ask main to act ("For you to confirm", "Main merges the branch", "Main files the shrink"): a done marker does not show nothing is asked (jq on the text before `Full output:`, 2026-11-04).
- [settled] Orca's consuming `check` marks its batch handled; a watcher must use `--peek` (`orca-ide orchestration check --help`, 1.4.248, 2026-11-04).
- [uncertain] a custom payload key or thread id survives a send: Builder check P1 before C1, actions there.
- [uncertain] Orca delivers mail to one busy pane only: Builder check P2 before C2; D7 holds either way.
- [uncertain] every coordinator command works unbound: Builder check P3 before C4; D11 names both outcomes.
- [settled] Orca here is 1.4.248 (`orca-ide --version`); `gh release view v1.4.248|v1.4.247 -R stablyai/orca` lists #28567, #37550, #37548, #37564, #37219 and the plugin hooks #37287/#37295/#37303 (2026-11-04).
- [settled] #28567 (whole messages) is for native chats only: this CLI pane got "You have 1 orchestration message. Run `orca orchestration check`." on 2026-11-04, so addition B's nudge count stands, and D22 covers that form.
- [settled] #37550 adds no traffic here: the worker preamble it writes says to message the coordinator only to ask, report a blocker or finish (this dispatch, 2026-11-04).
- [uncertain] Orca's typed nudge passes a `terminal.send` hook: P4, recorded only.
- [uncertain] a `--peek` check returns a delivery id: Builder check P5 before C2; D14 names both outcomes.

## User-visible changes

- Main, before: an OK long job, an OK detached test run or CI watch, an OK CI job and a status note each woke main. After: they wait and arrive together, at most one batch per 30 minutes; a question, a push, deploy, merge or seat result, and a worker that stopped without reporting still wake main within the wake window.
- Main, before: await-agents.sh marked the messages it saw read, so main's drain could miss them. After: it only looks; main's drain shows them.
- A Builder, before: woken by any unread row. After: not by a heartbeat or a 10-minute repeat (left unread).
- watch-agents.sh, before: marked messages read, showed questions and escalations. After: only looks; shows each wake once.
- Main, before: a wakeKinds setting without question or escalation kept those from waking main. After: they always wake main; wakeKinds only adds kinds.
- Main, before: the same message twice in 10 minutes printed twice. After: the second never wakes or prints; it is logged in hidden.jsonl.
- Relay, before: woke on a subject that starts `cos:` or names the owner, on main's plain messages to its run, on any Orca nudge with another sender, and held script event notes. After: wakes only on mail sent to it (cos-tell.sh --note, or its own handle) and on a reply main owes the owner (D13); events go to main only.
- Relay, before: woke whenever main ended a turn having sent it nothing. After: only when that turn left the owner's message unanswered (D17).
- Relay, before: a held FYI waited for the next wake or the 50-minute check. After: it wakes the relay at 30 minutes.
- Relay, before: any reply reached the owner unchecked. After: a reply that is only verdict updates, still-running lines or progress counts, with no ask, is held once with the reason (already shown).
- Main with C4 built: no Orca "You have N orchestration messages" prompts; main-watch wakes main.

## Question for the owner

None: answered as D28

## Stated limits

(every reviewer is handed these; a finding beyond one is out of scope: a follow-up issue, never a blocker)
- Stopped notices: 46 of 400 rows, 0 with a worker_done, all now (`inbox --limit 400 --full --json`, 2026-11-04).
- Driver starts: 0 (`rg 'drive-[a-z$]*\.service' scripts hooks`, 2026-11-04).
- Windows 1800 s, 600 s (`gh issue view 642`, 2026-11-04).
- At once: 120 s, wakeWindowSeconds 60 (paths.sh:1225) + 60 s tick (main-watch.sh:62), 2026-11-04.
- Repeat page 500 rows; #642's sample 401 in 12 h (`gh issue view 642`, 2026-11-04); rows past 500 unseen (paths.sh:553).
## What can go wrong

| Case | Input or starting state | Expected | Test |
|---|---|---|---|
| Bad payload | payload absent, junk, empty, trailing-space tag, or quoted JSON string | absent, junk, empty, trailing: no tag, the type decides; quoted JSON: its tag | bad payload no tag, quoted tagged |
| Missing time after a batch | batch drained at T; a status with no created_at at T+60 | waits until the clock is 1800 s old | untimed row waits for clock |
| Repeat across deliveries | question A drained and acked at T; at T+300 duplicate A with question B in a new delivery | A dropped to hidden.jsonl, B printed | acked question repeat dropped later |
| Old watcher outlives a merge | new poller at T; a merge keeps the old main-watch alive; at T+1801 its untagged tell_relay | admitted: tags-relay is absent until the new main-watch ticks | old watcher note admitted late |
| Full page | 500 rows: 499 read, one unread question to run:R older than the window | the question is returned and wakes main; 500 read rows: unknown, as today | full page keeps question |
Bad input: the Stop payload absent or its reply empty passes; payload and thread-id junk are row 1; the nudge text: no `--run` takes the run file, junk or trailing text after the command, an empty prompt or a quoted one does not match and passes, as today; await-agents.sh and watch-agents.sh: a failed, empty or junk pp_inbox_actionable answer is no news (D20, D26); tags-relay absent, empty or junk reads as no cutover yet; no new flag or argument is parsed.

## Acceptance test

- test file path: scripts/__tests__/to-main.test.sh (question wakes now; decision gate wakes now; push ask wakes now; deploy ask wakes now; worker_done wakes now; failed long job wakes now; failed event note wakes now; prompt wait wakes now; done-marker notice with action wakes now; FYI-subject question wakes now; owner's words wake now, repeats too; ok event note batched; status note batched; full page keeps question; batch wakes once at 30 min; no second batch wake in 30 min; untimed row waits for clock; repeat in 10 min dropped; repeat after 10 min kept; relay and main copies not repeats; bad payload no tag, quoted tagged; untimed row never a repeat; relay note never wakes main; ok test run status, merge question; no watcher keeps own wake rule; wakeKinds lacking question wakes; status kind wakes now; await-agents ignores a status; await-agents stops on question, unread; await-agents skips repeat; watch-agents shows gate once, unread; watch-agents skips repeat)
- test file path: scripts/__tests__/orca-wait.test.sh (driven verdict echo hidden, ok status held)
- test file path: scripts/__tests__/orca-wait-drain.test.sh (drain shows batch held, logs repeat; drain sets batch clock; acked question repeat dropped later)
- test file path: scripts/__tests__/long-job.test.sh (ok job is status, failed is question)
- test file path: scripts/__tests__/wake-on-exit.test.sh (OK ci exit status, push question)
- test file path: scripts/__tests__/main-watch-inbox-wake.test.sh (heartbeat to Builder types nothing; status to Builder wakes it; Builder repeat types nothing; watcher writes relay tag once)
- test file path: hooks/__tests__/cos-own-echo.test.sh (question after batch waits for window; relay nudge with no mail dropped; relay nudge leaves main's unread; relay nudge with note passes; bare nudge with nothing actionable held; bare relay nudge with no mail dropped; relay nudge repeat dropped)
- test file path: scripts/__tests__/cos-tell.test.sh (script event wakes main not relay; tagged note wakes only relay; owner-named subject no relay wake; addressed note wakes relay; held FYI wakes relay at 30 min; clock with no notes ignored; notes start clock next poll; relay repeat in 10 min dropped; thread-id tag read like payload; silent turn nothing owed no wake; owed reply wakes relay once; old untagged note reaches relay; untagged note after cutover not admitted; old watcher note admitted late; old event note keeps owed)
- test file path: scripts/__tests__/cos-check.test.sh (clearing notes resets clock)
- test file path: hooks/__tests__/cos-inbox-waiter-stop.test.sh (verdict update held naming why; still-running held; progress count held; incidental ask word held; question passes; bold question passes; action line with count passes; limit percent passes; empty or absent reply passes; verdict with news passes)
- test file path: scripts/__tests__/board.test.sh (main known by recorded pane; two panes no record not main; seat task names run; no script binds main)
- test file path: scripts/__tests__/setup.test.sh (setup records its pane as main)
- test file path: hooks/__tests__/context-clear-restart.test.sh (restart moves main's record)

## Break proofs

Break: hooks/__tests__/cos-inbox-waiter-stop.test.sh -- verdict update held naming why -- cos-inbox-waiter-stop.sh hold
Break: hooks/__tests__/cos-inbox-waiter-stop.test.sh -- incidental ask word held -- cos-inbox-waiter-stop.sh ask
Break: scripts/__tests__/main-watch-inbox-wake.test.sh -- heartbeat to Builder types nothing -- main-watch.sh inbox_wake
Break: scripts/__tests__/orca-wait-drain.test.sh -- drain sets batch clock -- orca-wait.sh batch-at
Break: scripts/__tests__/orca-wait-drain.test.sh -- acked question repeat dropped later -- orca-wait.sh page
Break: scripts/__tests__/cos-tell.test.sh -- owner-named subject no relay wake -- cos-watch-inbox.sh recipient
Break: scripts/__tests__/cos-tell.test.sh -- held FYI wakes relay at 30 min -- cos-watch-inbox.sh since=
Break: scripts/__tests__/cos-tell.test.sh -- clock with no notes ignored -- cos-watch-inbox.sh clock drop
Break: scripts/__tests__/cos-tell.test.sh -- untagged note after cutover not admitted -- cos-watch-inbox.sh tags-relay
Break: scripts/__tests__/main-watch-inbox-wake.test.sh -- watcher writes relay tag once -- main-watch.sh tags-relay
Break: scripts/__tests__/cos-check.test.sh -- clearing notes resets clock -- cos-check.sh rewrite
Break: hooks/__tests__/cos-own-echo.test.sh -- relay nudge with no mail dropped -- cos-own-echo.sh ack
Break: hooks/__tests__/cos-own-echo.test.sh -- relay nudge leaves main's unread -- cos-own-echo.sh peek
Break: scripts/__tests__/cos-tell.test.sh -- old event note keeps owed -- cos-tell.sh event guard
Break: scripts/__tests__/cos-tell.test.sh -- silent turn nothing owed no wake -- cos-watch-inbox.sh owed flag

## Claims to falsify

- After C1, `rg -n 'def (wakes|wake_class)\(\$' scripts hooks` shows one definition each, in scripts/paths.sh.
- After C1, no row of a required type, stopped notices included, is class batch, whatever wakeKinds says.
- After C1, by default an OK long job, detached test run or CI watch does not wake main before its message is 1800 s old.
- After C1, a push, deploy or merge job that exits 0 still sends main a question.
- After C1, scripts/await-agents.sh and watch-agents.sh run no consuming `orchestration check`; await-agents counts no row by type alone.
- After C1, inbox_wake types no INBOX line into a Builder whose unread rows are all heartbeats.
- After C1, every inbox waker (pp_inbox_actionable, orca-wait.sh, await-agents.sh, watch-agents.sh, inbox_wake, cos-watch-inbox.sh, cos-own-echo.sh) calls wake_class.
- After C2, no line of scripts/cos-watch-inbox.sh decides admission or wake from `subject`.
- After C2, pp_relay_event sends nothing the relay's poller admits.
- After C1, the six event suites D29 migrates count one event per outcome at main, 0 to `run:`.
- After C2, an Orca nudge in the relay pane, in either form, with no row addressed to it costs the relay no turn.
- Orca's worker-start and dispatch help list no option turning stopped notices off.
- After C2, `rg -n 'main-turn|main-sent' scripts hooks` finds nothing.
- After C2, the poller admits an untagged row only before tags-relay's epoch.
- After C2, every `check` in hooks/cos-own-echo.sh carries `--peek`.
- After C2, an `FYI event: ` note is untagged and keeps the owed mark.

## Not in this unit

- The host project's own unit for the same issues.
- The decisions, alerts, limit and units watchers: they read files, not inbox messages.
- Configurable batch or repeat windows: not asked.
- A faster path past the existing 60 s wake window: issue 318's coalescing stays as it is.
- An Orca plugin that filters nudges through a `terminal.send` hook (1.4.247): P4 records whether it could.
- Whether Orca 1.4.248 #37564 explains part of the relay's 14 restarts: not one of #642-#644.

## Verification

- Per cut: `bash scripts/run-shell-tests.sh --changed` on the PC; before the merge, the full shell suite on the PC.
- After the merge (D16), a 2-hour run: count cos-own-echo.sh fires in the hook fire log for main's pane (Orca-typed nudges); 0 with C4, else each has its reason in docs/chief-of-staff.md.

## Progress notes

- #642: planned
- #643: planned
- #644: planned

## Done

- #642 Done: a long job finishes OK while main is idle -- main is not woken; the result shows under held notes in its next wake within 30 minutes, and a question arriving meanwhile wakes main within a minute or two
- #643 Done: a script reports a merge, push or seat outcome -- main is woken with the result and the chief-of-staff pane stays asleep; a note main sends with cos-tell.sh wakes only that pane
- #644 Done: the chief-of-staff pane ends a turn telling the owner a verdict, a still-running line or a progress count -- the turn is held with the reason; a reply with a question or an ask passes

## Issue cases

- #642 Body 1 -- scripts/paths.sh -- question wakes now
- #642 Body 2 -- scripts/paths.sh -- no second batch wake in 30 min
- #642 Body 3 -- scripts/paths.sh -- repeat in 10 min dropped
- #642 Body 4 -- scripts/paths.sh -- status note batched
- #642 Body 5 -- scripts/await-agents.sh -- await-agents ignores a status
- #643 Body 1 -- scripts/paths.sh -- script event wakes main not relay
- #643 Body 2 -- scripts/cos-watch-inbox.sh -- owner-named subject no relay wake
- #643 Body 3 -- scripts/cos-tell.sh -- tagged note wakes only relay
- #643 Body 4 -- scripts/paths.sh -- script event wakes main not relay
- #643 Body 5 -- hooks/cos-own-echo.sh -- relay nudge with no mail dropped
- #643 Body 6 -- scripts/cos-watch-inbox.sh -- owner-named subject no relay wake
- #644 Body 1 -- hooks/cos-inbox-waiter-stop.sh -- verdict update held naming why
- #644 Body 2 -- hooks/cos-inbox-waiter-stop.sh -- question passes

## Facts

- pp_inbox_actionable: unread wakeKinds rows, full page fails; PP_JQ_WAKES shared -- scripts/paths.sh:549-569 (observed: 2026-11-04)
- wakeKinds may be status alone; window 60 -- scripts/paths.sh:1224-1234 (observed: 2026-11-04)
- pp_detach sends a question -- scripts/paths.sh:504-514 (observed: 2026-11-04)
- pp_relay_event: run-file guard, cos-tell --note, a failed send logged -- scripts/paths.sh:374-381 (observed: 2026-11-04)
- to-main.sh queues with no live pane, exit 3 -- scripts/to-main.sh:9-42 (observed: 2026-11-04)
- ci-watch's EXIT trap calls pp_relay_event -- scripts/ci-watch.sh:12-16 (observed: 2026-11-04)
- RE needs `--run`; relay check consumes -- hooks/cos-own-echo.sh:24-61 (observed: 2026-11-04)
- Typed wake: same window and claim -- scripts/main-watch.sh:669-704 (observed: 2026-11-04)
- resolve_main: coordinator or main-pane.txt; full page arms no wake; tell_relay untagged to run:R -- scripts/main-watch.sh:546-611 (observed: 2026-11-04)
- --install restarts the watcher -- scripts/main-watch.sh:182 (observed: 2026-11-04)
- Questions; push/deploy events; hour stamp -- scripts/wake-on-exit.sh:160-193 (observed: 2026-11-04)
- Consuming check; any non-heartbeat exits -- scripts/await-agents.sh:26-72 (observed: 2026-11-04)
- Consumes; question/escalation only -- scripts/watch-agents.sh:42-62 (observed: 2026-11-04)
- Drain hides driven echoes, self-tests (no driver starts); classes each delivery alone -- scripts/orca-wait.sh:234-556 (observed: 2026-11-04)
- A driven verdict echo is pinned hidden -- scripts/__tests__/orca-wait.test.sh:67-73 (observed: 2026-11-04)
- inbox_wake wakes on any unread row -- scripts/main-watch.sh:307-330 (observed: 2026-11-04)
- Rows share a subject -- scripts/__tests__/main-watch-inbox-wake.test.sh:13-29 (observed: 2026-11-04)
- seat.sh's result is a question -- scripts/seat.sh:101-257 (observed: 2026-11-04)
- merge- detaches pinned as questions -- scripts/__tests__/to-main.test.sh:186-188 (observed: 2026-11-04)
- --note: status to run:R; handles change; `FYI event: ` keeps owed -- scripts/cos-tell.sh:5-27 (observed: 2026-11-04)
- main_silent: owed, else silent turn; admits by subject, coordinator, `FYI event:` -- scripts/cos-watch-inbox.sh:65-151 (observed: 2026-11-04)
- cos-check clears notes, keeps line 1 -- scripts/cos-check.sh:33-35 (observed: 2026-11-04)
- The Stop hook passes all but the relay -- hooks/cos-inbox-waiter-stop.sh:23 (observed: 2026-11-04)
- pp_is_main_pane: 0 coordinator, 3 none -- hooks/lib/project.sh:95-113 (observed: 2026-11-04)
- Only the coordinator writes main-pane.txt -- scripts/board.sh:61-63 (observed: 2026-11-04)
- setup.sh: main-watch with no plan, run-create, records the run -- scripts/setup.sh:646-731 (observed: 2026-11-04)
- A restart records main's handle -- hooks/lib/context-clear-restart.sh:128 (observed: 2026-11-04)
- OK long jobs pinned as questions -- scripts/__tests__/long-job.test.sh:209-216 (observed: 2026-11-04)
- An event note keeps marked:cleared -- scripts/__tests__/cos-tell.test.sh:391-394 (observed: 2026-11-04)
- Untagged question wakes relay -- scripts/__tests__/cos-watch-inbox.test.sh:26-43 (observed: 2026-11-04)
- Pins one relay event, the sentence -- scripts/__tests__/seat-run.test.sh:77-84 (observed: 2026-11-04)
- Events go "to the relay" -- templates/main-session.md:132 (observed: 2026-11-04)
- Push event at cos-tell stub -- scripts/__tests__/wake-on-exit.test.sh:407-424 (observed: 2026-11-04)
- CI event in orca log -- scripts/__tests__/ci-watch.test.sh:95-103 (observed: 2026-11-04)
- Launch event in orca log -- scripts/__tests__/builder-launch-resume-launch-line.test.sh:136-141 (observed: 2026-11-04)
- Merge event in orca-calls -- scripts/__tests__/merge-unit-local.test.sh:335-340 (observed: 2026-11-04)
- Refused: fail event, log -- scripts/__tests__/seat-run-refused.test.sh:57-63 (observed: 2026-11-04)
- Status-only window: no wake -- scripts/__tests__/main-watch-wake-sources.test.sh:26-30 (observed: 2026-11-04)

## Plan change log

- 2026-11-04 rounds 1-2: main's additions A/B (P3 first, C4 conditional, nudge count); stopped notice with a QUESTION/BLOCKED line wakes now; judges 1-16 (precedence, wake gates, relay nudge branch, silent turn, OK senders, batch clock, repeat key, tag fallback, one-pane proof, main identity, relay clock versions, owner check holds, no new flag, no new test files); last round's questions D16-D18 and the Orca 1.4.247/.248 probes P3/P4.
- 2026-11-04 judge sol 1-13 (stopped notices, relay notes, nudge forms, wakeKinds, hour stamp, await-agents, repeat history, main record, cutover, ask words, private ids, attribution, claim search): each answered in D2-D22 and the tests named there; superseded parts are logged in round r3 below.
- 2026-11-04 judge sol r3 1 (done marker): D2 drops the done-marker batch; every stopped notice wakes now; 14 measured done-marker notices still asked main to act and 0 of 46 had a worker_done (Assumptions); test "done-marker notice with action wakes now" uses the judge's body; three stopped-notice tests folded into it.
- 2026-11-04 judge sol r3 2 (consuming check): D20 has await-agents.sh read through pp_inbox_actionable (inbox page, marks nothing); test "await-agents stops on question, unread".
- 2026-11-04 judge sol r3 3 (checksum): rebutted with the owner's 2026-11-03 ruling (one job-finished wake an hour, copied exactly): D19 keeps the hour stamp unchanged, so the checksum, its test and the judge sol 5 change go; the stamp is a sender rule, not a watcher's.
- 2026-11-04 judge sol r3 4 (history): await-agents.sh gets the page through pp_inbox_actionable, the nudge hook's relay branch reads it (D14), Data design lists every reader; tests "await-agents skips repeat", "relay nudge repeat dropped".
- 2026-11-04 judge sol r3 5 (drain hides): D23 keeps KEEP's noisy/harness hides after wake_class on now rows; orca-wait.test.sh:67-73 unchanged; test "driven verdict echo hidden, ok status held"; a line in the limits section.
- 2026-11-04 judge sol r3 6 (inbox_wake): D24 routes it through wake_class seat (heartbeat drop, else now); two main-watch-inbox-wake tests; Why's claim now holds; accepted failure mode for seat repeats.
- 2026-11-04 judge sol r3 7 (new test file): await-agents.test.sh dropped; its cases go in to-main.test.sh, whose fake inbox already lists and empties per handle, the smaller arrangement.
- 2026-11-04 owner's 2026-11-04 ruling found by decision.sh rulings: D25 keeps push, deploy, merge and seat results waking main; the landed-merge POST_OK change and its main-watch-auto-merge test go; to-main.test.sh:186-188 is no longer reversed (D18); D5, User-visible changes, claims and #643 Done follow.
- 2026-11-04 judge sol r4 1 (owner check after display): rebutted: the owner reads the relay's pane and no Claude Code hook runs before reply text prints, so no check can come before delivery; the owner's own 2026-11-04 ruling (decision.sh rulings) allows a check that refuses once a reply that is only verdicts, still-running lines or counts: Owner's ruling C, D9 and the accepted failure mode cite it; D9 narrowed to that "only"; test "verdict with news passes".
- 2026-11-04 judge sol r4 2 (watch-agents.sh): D26 reads it through pp_inbox_actionable, once per id, no consuming check, heartbeat ack dropped (cos-own-echo.sh:40 holds those nudges); C1, Steps, claims, User-visible changes; tests "watch-agents shows gate once, unread", "watch-agents skips repeat" (timed).
- 2026-11-04 judge sol r4 3 (cutover window): D21 ties cutover to main-watch's restart (tags-relay marker), not tag+1800; `tag=` word and its accepted failure mode go; WCGW row is the judge's sequence; tests "old watcher note admitted late", "watcher writes relay tag once".
- 2026-11-04 judge sol r4 4 (event test): cos-tell.test.sh:394 is no longer reversed; its fixture calls pp_relay_event and keeps `marked:cleared` (C2, D12).
- 2026-11-04 judge sol r4 5 (Builder repeats): D24 applies D4 to seats, the row left unread; the inbox-wake fixture gives each id its own subject, claims kept; its accepted failure mode goes; test "Builder repeat types nothing".
- 2026-11-04 Owner's words copy the `Order:` line word for word; sections trimmed to their caps (test names shortened, Facts merged, sol 1-13 log lines folded into one, the wakeKinds Break line dropped); size 850 -> 910 lines, 40 -> 41 files; New tests 72 -> 78.
- 2026-11-04 judge sol r5 1: D14 peeks, holds unacked, acks own echoes only (P5); test "relay nudge leaves main's unread".
- 2026-11-04 judge sol r5 2: D27 full page keeps its rows; WCGW "Full page" replaces "Question after a batch wake"; test "full page keeps question".
- 2026-11-04 judge sol r5 3: cos-tell's `FYI event:` owed guard stays, untagged (D21, D12); test "old event note keeps owed".
- 2026-11-04 judge sol r5 Q: Q1 to the owner (rulings: no match); D11/D16 hold C4; 950 lines, 81 tests.
- 2026-11-04 owner's Q1 yes: D28; D11, D16, Build order, Why, C4 build C4 on P3's pass; Question `None: answered as D28`.
- 2026-11-04 judge sol r6 1 (existing routing tests): accepted; D29 (pp_relay_event guard, subject, log); C1, C2 name each suite's migration and the audited ones; Steps, claim, Facts; D10 says now (was batch); 47 files, 990 lines; no new cases.
- 2026-11-04 Builder, at main's word: the decision id dropped from D28 and the Q1 log line (public repo); D28 records P3 failed, so C4 is not built (D11). P5: a peek returns no delivery id, so the relay's nudge branch acks nothing (D14's absent branch).
- 2026-11-04 Builder, pass 1 fix round: Data design gains the `Shown ids` row (watch-agents.sh) and names cos-check.sh as the relay clock's clearing writer, with the Clock clear steps and recovery; the poll starts a legacy notes clock on an empty inbox too (Mixed versions line). No new cases.
- 2026-11-04 main approved (answer-1793822594-17690): New tests 81 -> 82; the extra case is the red test of the pass-3 P2 finding (a dropped repeat of main's reply cleared a newer owed mark), cos-watch-inbox.test.sh "a dropped repeat of main's reply keeps a newer owed question".

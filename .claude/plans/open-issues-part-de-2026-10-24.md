# Plan: open-issues-part-de-2026-10-24 -- message cuts and ordering rules (part D), the checklist trim, the host tooling twins (part E), and issues 336 to 339

Tier: Standard
Order: the owner, 2026-10-24, "start the next plugin unit with all the remaining open plugin issues"; one unit (owner answer 2026-10-24)
Closes: issue 336, issue 337, issue 338, issue 339
Split: recommended
Split override: the owner chose one unit over the cap on 2026-10-24

The Closes line is in the plugin's own issue form: `#` and a number fails `ci/leak-test.sh` in this tracked file
(`ci/leak-words.txt`). The `#` form for the batch brief, which `merge-unit-local.sh:263` parses, is in the map.
Map: `.claude/briefs/open-issues-part-de-2026-10-24-map.md` (edited owners, in flight, sites, readers).

Size: about 2,250 changed lines in 67 files and 24 build items, in 10 groups (section 6). That is over the plugin's
plan cap (four cuts, 40 files, 20 edited owners), and under the 3,000-line review limit (`config/routing.json:101`).
Sections 1, 2, 3 and 3b (named "part D", "part E", "part F" and "the port" below) are groups of this one unit, built
by one Builder: D ~885 lines in ~31 files, E ~945 in ~33, F ~160 in ~10, the port ~215 in 3.

LOCAL merge only, no push.
Base: main 02f3ac3 (0.45.1). The file:line sites below were read on dc0a3ee. 02f3ac3 changes 14 files against
dc0a3ee (`git show --stat 02f3ac3`). Of the files this plan cites, four changed: `templates/main-session.md` (one hunk
at :180, below every line cited here), `scripts/dashboard.sh` (one line at :192; :840 and :1036-1046 did not move),
`templates/checkpoint.md` (+1 line) and `scripts/dashboard_limit.py` (cited as on 02f3ac3). `ci/version-check.sh`
also changed: it no longer compares the README badge with `plugin.json` (section 9).

Launch: new unit open-issues-part-de-2026-10-24

Public repo: no personal names, seat nicknames, host product name, host paths, ruling ids or `#<number>` issue
references in any shipped file, test, commit message or this plan (`ci/leak-words.txt`). Outside CHANGELOG.md a
plugin issue is written "issue N" and a host issue "host issue N".

Changed-file tests only (`bash scripts/run-shell-tests.sh --changed main`), no red-proof run, no `Mutation-verified:`
line, no test-timeout raise. The runner does not run a shared helper's callers' tests (`run-shell-tests.sh:72`), so
each group in section 5 names the test files to run by hand. Every review finding, P0 to P3, blocks the merge; done
is a closing pass `VERDICT: GO` that names no finding.

Port rule (the owner's order for this unit): where the host fix has merged on the host's local main, PORT it from the
named host commit (adapt it to the plugin site; do not redesign it). Where it has not merged, BUILD it here from the
issue text, so that the host can port it back from the plugin commit: one function or block per item, its comment
naming the plugin issue or the host issue, no plugin-only names inside the logic.

## Main answers

- The owner's order: one plugin unit for all remaining open plugin work (this plan).
- F13 as first planned (task tools off for main) is dropped. The checklist trim replaces it (section 1c).
- F16 is not in this unit: it still waits for the owner and is reported as waiting.

## Decisions (ponytail ladder; one line per cut)

- D1, D2: rung 2, port host commit `cf68915e` (message cuts) per site. Rejected lazier: section 3a of the earlier
  plan as written. It differs from the host commit in two places, and this plan follows the host commit:
  (a) D2 fix 3: the host keeps `--repeat-class` at two rounds. It finds the third return from the previous round's
  hand-off, which already carries the second-return line (host `builder-codex-pass.sh` ~931-937). It does not
  change `read-verdict.sh --repeat-class` to three rounds. (b) D1 cut 4: the host guards the finished and the
  stopped posts with a `reported()` check against Orca's run inbox (a worker_done from the seat's pane), not with a
  30-minute window.
- Checklist trim: rung 2, port host commit `e9ddd881` for "a done item is deleted, never marked completed"
  (`main-session.md`, `resume-context.sh` TODO_RULE, `checkpoint.md`). The host commit has no cap, no subject
  limit, no id rule and no guard hook. Those four parts of the owner's rule are BUILT here: one PreToolUse hook,
  `hooks/checklist-guard.sh`. It finds the task folder the way `dashboard.sh` `todos()` (:840) does and tells main
  from a worker as `read-tracker.sh:79-80` does. Rejected lazier: a card line only. Without a guard the
  rule holds only as long as the model remembers it, and the list grows back.
- F12 (short command card): dropped, already done. Part C made the injected part of `templates/main-session.md`
  a 40-line card (lines 1-40, then `## Details (not injected)` at :41). `scripts/startup-size.sh:37-40` fails a card
  over 40 lines. The host's `e9ddd881` card split applies to a host-only rule file; the plugin has no twin of it
  (`templates/global-rules.md` is 6,938 bytes, the size of the host's new card).
- E1 host issue 2998 (no settle under a live Builder): rung 2, port host commit `c8b82ae5`'s final form only:
  `pp_open_ask`, the `pp_task_close` refusal and collect settling first, as of that commit's last fix round. Do
  not port its intermediate rounds. Rejected lazier: a pane-busy check alone. The host found in three later
  passes that an open question also has to hold the task.
- E1 host issue 3009 (panes vanish): rung 2, port `c8b82ae5` Cut 1: one logged close, `pp_pane_close`, for every
  script close, plus the runner's refusing `orca-ide` stub. Also port its culprit fix: close-done-panes' done rule
  spares an uncollected seat pane. Rejected lazier: the log alone (the culprit would stay).
- E1 host issue 3011: rung 2, port `c8b82ae5` (`builder-fresh-round.sh` rewrites `handle=` in place and keeps
  `prior_pane=`). Rejected lazier: a `seat.sh relaunch` verb (a new command where one line in the existing
  hand-off does the job).
- E1 host issue 3162 (seat run dies with main's pane): checked in the plugin, and real. `seat.sh run` from main's
  foreground (:165-170) starts with plain `nohup ... &` in main's own pane. The plugin's restart closes that pane
  (`hooks/lib/context-clear-restart.sh:84`), and nohup shields only from SIGHUP. Not checked live: whether
  Orca's pane close sends more than SIGHUP. The Builder's first step is a probe (section 2). Rung 2: the
  detach `hooks/context-clear-stop.sh:184-185` already uses (`setsid`, else perl `POSIX::setsid`). Rejected
  lazier: route it through a long-job pane (the plugin has no `long-job.sh`, and the host's fix needs one).
- E2 host issue 3028: rung 2, port `1e0e07b9` step 5 (hold, do not delete, a worktree with uncommitted paths; exit 5
  named on the DONE line). Its pane-stop order uses this unit's `pp_pane_close` (E1).
- E2 host issue 2997: rung 2, port `1e0e07b9`'s `shell-tests-for.sh` as is (paths re-rooted at `hooks/` and
  `scripts/`). It is used ONCE, in the complete run on the merge tip (issue 336), through a new
  `run-shell-tests.sh --changed <base> --callers`. Rejected: adding the callers' tests to every closing run.
  That reverses main's ruling of 2026-10-17 (`run-shell-tests.sh:72`) and would cost every closing run what
  issue 336 tries to save. Main's answer (round 1): kept; the callers' tests run once, on the merge tip.
- E2 host issue 2999: rung 5, one sentence in the plan-author spec line `seat.sh:400` (every plan seat gets it).
  The plugin has no plan template and no plan-check script. Rejected: building a plan-check for one line.
- E3 host issue 3147: BUILT (no host commit). Rung 2: the gate that blocks is `hooks/pane-budget-gate.sh`
  :86-123. Its server check already waits 10 s (:97-99). Change: a missing server lets the call through with one
  note per session, and a host-wide stamp lets later sessions skip the wait. The hint `bash-guardrails.sh` ~583
  does not gate on codebase-memory: it only advises it on an unbounded search, so it is unchanged.
  `read-tracker.sh` ~92 changes as noted in section 2. Root cause of the host's MCP timeouts: host-only, not in
  this unit.
- E3 host issue 3038: BUILT (the host batch is unmerged). Rung 2: copy the host's `KERN_PROCARGS2` reader
  (python3 ctypes over `sysctl`, from the host's chain cleanup) into `read-verdict.sh` `pane_sessions` :348-358.
- E3 host issue 3029: checked in the plugin, and real. When the on-disk `package.json` is not JSON,
  `dependency-addition-guard.sh:478` (`jq -e ... has($n)`) fails to parse it and calls `block_manifest`. The block
  then names a non-dependency key (a script name) as a new package. Rung 5: one parse check before the loop,
  which blocks with a plain message naming the file.
- E4 host issue 3053: BUILT. It is almost fixed in the plugin: `dashboard_limit.py` reads `service_tier` per
  record (:1085 on 02f3ac3) and prices `priority` at the `:fast` rate (:993). A switch mid-session is priced
  per row, and `worktreereview/scripts/collect.py:314-317` uses the same `codex_row`. Gap: a file with no
  `thread_settings_applied` record gets `tier=None`, which is priced at the standard rate without a mark.
  Rung 5: that case counts under `estimatedUsd`. `unit-cost.sh` prints Codex tokens only, no dollars
  (:108-114), so nothing changes there.
- Issue 336: BUILT (no host twin found: the host issue list has no match for its title or text). Rung 2, reusing
  the basename relation of `shell-tests-for.sh` (E2) in reverse: a test's inputs are the test file plus every
  `hooks/` or `scripts/` file it names by basename. The new `scripts/test-inputs.sh <commit> <file>...` prints
  `unchanged`/`changed` per file. Rejected lazier: a brief line alone (a Builder cannot tell by eye which sourced
  script changed).
- Issues 337, 338, 339: BUILT (host issues 3164-3166 are not built). Rung 5: rule text in the brief template, the
  fix-round class block and main's card. Issue 339 measures first, on this unit's own build.
- One unit (owner answer): "part D/E/F" means sections 1/2/3 of this unit. One version (the next free minor) and
  one CHANGELOG entry with a paragraph per section; a "per part" line in section 9 or Done when reads "per section".
- In flight, merge order: no live plugin unit edits these files. Host unit tooling-b4-dashboard-2026-10-24 builds
  the host twins of host issues 3038 and 3053 (another repo, no shared file). Under the port rule: if it merges on the
  host's local main before group 7 starts, group 7 ports those two items from its commit; if not, they are built here
  as planned and the host ports back. This unit's merge does not wait for it.
- Autodecide port (owner order 2026-10-24, section 3b): rung 2, port the owner's prototype as is. Allowed changes
  only: names and keys, paths, the seat gate and config already in the plugin, the public-repo scrub. Rejected: the
  ledger-computed pattern and the shortened never list of issue 333 (the order: they ship as the prototype has
  them). The clock goes back to the prototype's Eastern zone, since a zone change is not an allowed change. Rows
  12, 15 and 16 of 3b depart without an allowed reason: they are kept, as the owner's choice (owner answer 2026-10-24).
- If `scripts/__tests__/seat.test.sh` outgrows its time budget, the settle cases go in the new file
  `scripts/__tests__/seat-settle.test.sh` (section 2, host issue 2998); no other new file is allowed by that clause.

## 1. Part D

### 1a. D1 message cuts (host commit `cf68915e`)

| Cut | Plugin site (today) | Change (as the host commit) | Test (file, case) |
|---|---|---|---|
| 1. Verdict echoes | `hooks/codex-notify.sh` marker exit :37, send :67-72; `hooks/claude-worker-notify.sh` marker exit :67, send :98-103; `scripts/paths.sh` new `pp_worker_done_since` (beside `pp_wake_log` :401) | both new exits sit after `ASK` is set (`codex-notify.sh:32`, `claude-worker-notify.sh:49`) and each is skipped when `ASK` is not empty (`[ -n "$ASK" ] \|\| ...`, the form of the hooks' own gates), so a question or refusal line still reaches main (`codex-notify.sh:28`, `claude-worker-notify.sh:45`). Both hooks: a turn with no ask line whose last non-blank line, trimmed, is `VERDICT: NO-GO` exits silently (awk, host text). Claude hook only: it exits when the run inbox (`orchestration inbox --terminal run:<run> --limit 500 --json`) holds a worker_done from `$ORCA_TERMINAL_HANDLE` created in a later second than this turn's prompt (the last user line with a string or text block). An unreadable inbox, no handle or no prompt time keeps the echo. Codex keeps its GO/DONE echo (its payload has no transcript), as a comment says | `hooks/__tests__/worker-notify.test.sh`: "a turn ending VERDICT: NO-GO sends nothing (each hook)"; "`QUESTION: Which rollback policy applies?` then `VERDICT: NO-GO` still sends, the question in the subject (each hook)"; "a `BLOCKED:` line in a turn whose worker_done Orca accepted still sends"; "a NO-GO quoted earlier in a turn that ends on a DONE marker still sends (each hook)"; "a turn whose worker_done Orca accepted sends nothing"; "a worker_done Orca refused (exit 1, `requires outcome`) still sends"; "a worker_done from before this turn's prompt still sends" |
| 2. No-marker turns | done: `codex-notify.sh:37`, `claude-worker-notify.sh:67` | none | the Builder names the existing `worker-notify.test.sh` case |
| 3. Heads-up digest | `scripts/main-watch.sh` `flush` :354-380 (relay subject :362, inbox-only return :369), the heads-up post :1295 and its tick call | one digest per `COMMANDECK_MAIN_WATCH_HU_DIGEST_S` (default 1800). `$ST/hu-last` is written only after an accepted relay. A note that repeats any ledger group (held or posted, same session, line and explanation) or a handled note is dropped. Existing main-watch tests set the digest to 0 in their tick helper, as the host does | new `scripts/__tests__/main-watch-message-cuts.test.sh`: "two heads-up ticks inside the digest window post one digest"; "a note repeating a held note is not posted"; "a refused digest is retried on the next tick" |
| 4. main-watch repeats | finished :1037-1040, stopped without reporting :1052, stalled `wait-` post :1023, `post ... once` :236, `settle`/`am_handled`, `flush` :354; `scripts/read-verdict.sh` new ordinal `prompt` (host ~768-779) | `reported <handle> <since> <launched>` (one non-draining inbox read per tick, `pp_worker_done_since`) guards the finished and stopped posts. An unreadable inbox or prompt time answers no: a duplicate post, never a missed finish. The stall and wait posts are `once`. `flush` takes each seat's delivery lock (`COMMANDECK_MAIN_WATCH_LOCK_S`, default 20; it sends anyway when no lock comes in time) and re-reads the receipt under it. A delivered item goes through `mark_handled`, the one fence that settles a minted task or an owed close (host text). First red lane: no plugin sender (no chain runner). Kept unchanged: the merge-gate and ready-to-merge posts (:860-871, the "not merged" branch at :1037) and the nudge posts (:284, :345) | `main-watch-message-cuts.test.sh`: "a finished seat whose worker_done is in the inbox posts nothing"; "an unreadable inbox still posts"; "a stall seen on three ticks posts once"; "a collect that lands between queue and flush is not posted twice"; "a minted task whose send was refused is closed once the seat reports"; `read-verdict.test.sh` "ordinal prompt prints the latest prompt's epoch; no log exits 3" |
| 5. MCP escalations | `hooks/pane-budget-gate.sh` send :111-120; `hooks/read-tracker.sh` send :83-92 | no send to main and no wake line: the BLOCKED or MCP UNUSED line to the worker only, which says "record it under `## Main-only (deferred)` in the evidence file and go on" (host text). E3 then changes the same gate block (section 2) | `hooks/__tests__/pane-budget-gate.test.sh` "a missing server sends nothing to main"; `hooks/__tests__/read-tracker.test.sh` "MCP unused warns the worker once and sends nothing" |
| 6. Tool-blocked questions | `hooks/dependency-addition-guard.sh` `block` :43, `block_manifest` :278; `hooks/suite-rerun-guard.sh` BLOCKED :326 | one more stderr line: "If you need this package, record it as a main-only deferred item (one line under ## Main-only (deferred) in the evidence file) and go on without it; do not ask main." The suite-rerun line ends with the host's `$DEFER` text. Blocking is unchanged | `dependency-addition-guard.test.sh` "the new-dependency block tells the worker to record a main-only deferred item"; the suite-rerun guard's test (the Builder names it; one new case if none) the same for :326 |
| 7. Duplicate result posts | none (no wake-on-exit or chain runner in the plugin; `pp_detach` sends once per job) | none | none |
| 8. Hand-off not typed | `scripts/builder-fresh-round.sh` `tell` :25-31, `fail` :33, lock section | `fail` retries the whole hand-off once, under the lock already held (`exec` with a retry flag, `ARGS` kept, stamp removed); only a failed retry tells main | `builder-fresh-round.test.sh` "a first typing failure that succeeds on retry tells main nothing; two failures tell main once" |
| 9. Halfway reports | none (no plugin template asks for one) | none | none |
| 10. Duplicate seat notices | `scripts/seat.sh` collect send :620-628 | check, send and receipt in one step under `delivered-seat-<handle>-<task>.lock`, the lock main-watch's flush takes. The receipt names the log as it stood before the verdict was read (`read-verdict.sh --pane-log`, size), and is written only after an accepted send (`.ok == true`) | `seat.test.sh` "a second collect sends nothing"; "a collect waiting on a held lock sends after it, once" |
| 11. worktreereview flags | none (`review.py` prints, sends nothing) | none | none |
| 12. Worker progress notes | `templates/_builder-brief-template.md` rules list (:28-38); `templates/AGENT_STARTUP.md` | one rule: "One status per decision: message main only for a decision only main or the owner can make. No progress notes; progress goes in the evidence file." | `brief-template.test.sh` "the brief and AGENT_STARTUP.md both carry the one-status-per-decision rule" |

Keep: worker_done; the owner's orders, answers and decisions (`relay-order.sh`, `cos-tell.sh`); the class-stop
question on the third return (D2); ready-to-merge, QUIET-after-nudge and FAILED alerts. Test:
`main-watch-merge-gate.test.sh` and `main-watch-nudge.test.sh` pass unchanged. The evidence file lists each Keep
sender with the case that shows it still sends.

### 1b. D2 ordering bugs (host commit `cf68915e`)

| Fix | Plugin site | Change | Test (file, case) |
|---|---|---|---|
| 1. Every ordering in the first pass | `scripts/builder-codex-pass.sh` `LATER` :119, `FOCUS_REVIEW` :122, the behaviour angle | one sentence used by both: when the diff involves timers, background loads, retries, concurrent writes or tab/page switches, list EVERY ordering of those events in the first pass, check each, and report every ordering that fails, not the first (host `_reviewer-tools.md` item 4) | `builder-codex-pass.test.sh` "the full pass and the behaviour angle prompts both carry the every-ordering sentence" |
| 2. Second return: fix the design | `builder-codex-pass.sh` `## The same class again` :1216-1227; `templates/_builder-brief-template.md` :33-36, :177-186 | on the second return: fix the design for the whole class (one fence or stamp) and add one test covering every ordering found so far. The existing retry-path sentence stays word for word in the brief template and in `main-session.md` ("The class fix has one retry path ... the retry still happens", checked at `brief-template.test.sh:44` and `:49`): the new text is added beside it, not in its place. Send main nothing (the 100-token status at :183-185 goes). The review loop goes on | `builder-codex-pass.test.sh` "the fix round after a class's second return says fix the design, one test for every ordering, send main nothing"; `brief-template.test.sh` "the class rule says the same"; the cases at `brief-template.test.sh:44` and `:49` pass unchanged |
| 3. Third return: redesign | `builder-codex-pass.sh` same block; `templates/main-session.md` :99-103 | the block checks the previous round's hand-off (`-r<N-1>.md`) for the second-return line. If it is there, this is the third return: the Builder builds the other findings first, then asks main one question through the plugin's addressed, threaded wait, `bash scripts/ask-main.sh "<class>: third return" "<the proposed redesign>"` (issue 335), not the host's `orchestration send --type question`, and builds main's answer. Neither template names a raw send for it (`brief-template.test.sh:97`). Main's card rule: answer redesign by default; ask the owner only for a real policy call. `read-verdict.sh --repeat-class` (:360-375) is unchanged | `builder-codex-pass.test.sh` "a third return (the previous hand-off holds the second-return line) asks main once through ask-main.sh, and the block names neither `send --type question` nor `orchestration ask`"; `brief-template.test.sh` "main-session.md sends the Builder to redesign on the third return and asks the owner only for a policy call"; the case at `:97` passes unchanged |

### 1c. Checklist trim (host commit `e9ddd881` part; the rest built)

| Item | Plugin site | Change | Test (file, case) |
|---|---|---|---|
| Done = deleted (port) | `templates/main-session.md` :113-115; `hooks/resume-context.sh` TODO_RULE :102; `templates/checkpoint.md` TODO LIST line (:81 on 02f3ac3) | add "an item done is deleted (TaskUpdate status deleted), never marked completed; the checkpoint's Closed section keeps it". The plugin's resume still recreates only the unfinished items | `resume-context.test.sh` "the resumed TODO line says a done task is deleted, not completed" |
| Cap, subject, ids (built) | `templates/main-session.md` :113-115 | "At most 8 open items; a subject of 80 characters at most, with no ids (no message, task or dispatch id, commit hash or issue number)" | `brief-template.test.sh` "main's checklist rule names the 8-item cap, the 80-character subject and no ids" |
| Guard hook (built) | new `hooks/checklist-guard.sh`; `hooks/hooks.json` PreToolUse matcher `TaskCreate\|TaskUpdate` | main's session only (git dir == common dir). It refuses: a TaskCreate when 8 items in `<config>/tasks/<session_id>/` are pending or in_progress; a subject over 80 characters or one holding an id (`#[0-9]+`; the plugin's own spelling, `(^\|[^A-Za-z])(issues?\|pr)[ -]?#?[0-9]+` without regard to case, which covers "issue 336", "issue-336" and "host issue 3147"; `(msg\|task\|ctx\|term\|dcap)_[A-Za-z0-9]+`; a 7-40 hex word); a TaskUpdate to `completed` ("delete it: status deleted"). Each refusal is one BLOCKED line saying what to do. An unreadable task folder lets the call through (it guards list size, not data) | new `hooks/__tests__/checklist-guard.test.sh`: "a ninth open item is refused, the eighth passes"; "an 81-character subject is refused, 80 passes"; "a subject naming a msg_ id, a commit hash, a hash sign before a number, or an issue number (`Fix issue 336`, `issue-336`) is refused; `Trim the 8 open items` passes"; "TaskUpdate to completed is refused with the delete line; to deleted passes"; "a worker session is not checked" |

The dashboard's Checklist panel (`dashboard.sh` `todos()` :840) then shows open items only. That is the point of
the trim; no panel change.

## 2. Part E -- host tooling twins

| Item | Source | Plugin site (today) | Change | Test (file, case) |
|---|---|---|---|---|
| E1 host issue 2998 | port `c8b82ae5` | `scripts/paths.sh` `pp_task_close` :569-597, new `pp_open_ask` before it; `scripts/seat.sh` collect :620-640 (settle at :637), silent relaunch :746-757; `scripts/answer-worker.sh` (reply in the question's thread when given its id) | `pp_task_close` settles a task held by a seat record (`task=` or `answer_task=`) only when the pane reads idle (`pane_is_busy` 1) AND `pp_open_ask` reads "none open" since the record's `launched=`, across every id the record holds (handle, `prior_pane=`, tasks, their dispatches). Working, an open question or any read that fails refuses, and names the answer command. collect settles first (retry `COMMANDECK_SEAT_SETTLE_RETRY_S`, 60; tests 0); if still refused it closes no pane, writes no `verdict=`, and exits 4 with the rerun line; `settled=<task>` prevents a second close. A task with no record works as before | `scripts/__tests__/seat.test.sh` (or a new `seat-settle.test.sh` if it outgrows the budget): "settle refused while the Builder pane works"; "settle refused while its question has no reply in its thread"; "a reply in the thread lets it settle"; "an unreadable inbox refuses"; "collect on a working pane exits 4, closes nothing; the rerun on an idle pane settles once" |
| E1 host issue 3009 | port `c8b82ae5` Cut 1 + culprit | new `pp_pane_close <handle> <cause>` in `scripts/paths.sh` (logs to `pane-closes.log`, `.ok == true` only, answer in `PP_CLOSE_RES`); callers: `close-done-panes.sh:116`, `hooks/lib/context-clear-restart.sh:69` and `:84`, `seat.sh:379`, `:413`, `:639`, `:754`, `merge-unit-local.sh:550`, `plan-worktree-close.sh:141`, `codex-helpers.sh:123`; `close-done-panes.sh` done rule :105; `scripts/run-shell-tests.sh` before `run_one` | every script close goes through `pp_pane_close`, so each one is logged with its caller. The done rule also spares a handle claimed by a seat record with no `verdict=` (as the orphan rule :107 does). The runner puts a stub `orca-ide` first on PATH: it refuses `terminal close` and names the test file (`COMMANDECK_RUNNING_TEST`), and passes everything else to the real binary | new `scripts/__tests__/close-done-panes.test.sh` "an uncollected seat pane in state done is kept; a collected one is closed and logged"; `context-clear-restart.test.sh` "both closes write a pane-closes.log line"; `run-shell-tests.test.sh` "a test without its own stub cannot close a pane: refused, named" |
| E1 host issue 3011 | port `c8b82ae5` | `scripts/builder-fresh-round.sh` after the session line :131-132 | when the record's `handle=` differs from the pane that ran this round, rewrite that one line in place (awk, temp then mv) and add `prior_pane=<old>`; a record with no `handle=` is left alone | `builder-fresh-round.test.sh` "a relaunched Builder's record names the new pane, keeps prior_pane, no second handle= line" |
| E1 host issue 3162 | built | `scripts/seat.sh` run :165-170 | first, a probe: start `nohup sleep 300 &` in a scratch Orca pane, close the pane, check the pid. If the sleep survives, drop the item and record that in the evidence file. If not: launch with the detach from `context-clear-stop.sh:184-185` (`setsid`, else perl `POSIX::setsid`) in front of the `nohup bash "${0}" run`. Comment: "a seat run started by main survives main's pane closing" | `seat-run.test.sh` "a detached run started from a shell that is then killed (with its process group) still finishes and collects" |
| E2 host issue 3028 | port `1e0e07b9` | `scripts/merge-unit-local.sh` step 4 brief archive :417-422, step 5 :545-552, exit summary and DONE line | the host's order, quiesce before archive: before step 4 archives any brief file, stop the unit's panes (`pp_pane_close` per handle; a pane that will not close holds) and its Codex helpers (`codex-helpers.sh stop "$WT"`, moved up from after the remove at :552). `.claude/briefs/` is ignored (`.gitignore:5`), so no status check sees a write there; with no live writer left, none can come after the archive. A hold at this point archives nothing and removes nothing (exit 5; the merge commit stands). Then the briefs are archived, then `git status --porcelain --untracked-files=all` in the worktree: any path except a deletion holds. Held: the worktree is kept, the DONE line names up to 3 paths and the remove command, exit 5 | `merge-unit-local.test.sh` "a worktree with an uncommitted file is kept, exit 5, the path on the DONE line"; "a clean worktree is removed as before"; "a deleted tracked file does not hold"; "the panes close and the Codex helpers stop before any brief is archived (stub call log order)"; "a pane that will not close: no brief archived, the worktree kept, exit 5" |
| E2 host issue 2997 | port `1e0e07b9` | new `scripts/shell-tests-for.sh` (host file with `.claude/` dropped from its paths); `scripts/run-shell-tests.sh` `--changed` :67-80 gains `--callers` | `--changed <base> --callers` adds every test that names a changed or deleted `hooks/` or `scripts/` file by basename, to a fixed point (the host's shortcut comment kept). Plain `--changed` is unchanged | new `scripts/__tests__/shell-tests-for.test.sh` "a change to a script named only by an unrelated test selects that test"; "a deleted test file selects nothing but still seeds"; `run-shell-tests.test.sh` "--callers runs the referencing test; plain --changed does not" |
| E2 host issue 2999 | port `1e0e07b9` (text) | `scripts/seat.sh` plan-author SPEC_TEXT :400 | add: "A plan that adds a heavy fixture to a test file with time-bound checks names them on a `Timed checks:` line and orders the heavy case after them." | `seat-launch.test.sh` "a plan-author spec carries the Timed checks line" |
| E3 host issue 3147 | built | `hooks/pane-budget-gate.sh` :86-123 (after D1 cut 5); `hooks/read-tracker.sh` `mcp_unused_tripwire` :26-95; `scripts/dashboard.sh` `alerts()` :1036-1046; `scripts/dashboard_alerts.jq` | bounded: the wait (`COMMANDECK_MCP_WAIT`, default down from 10 to 3 s) runs only while the claude pid is under 15 s old (`ps -o etime=`: its server may still be starting). An older session with no server is read as missing at once, with no wait. A server process stopped or a zombie (`ps -o stat=` T or Z) counts as missing: alive but not answering (shortcut: process state stands in for a protocol ping; upgrade if a hung server with a running state is seen). A server still missing no longer blocks: one stderr note per session ("<server> is not running in this session; reads go through without it; record it under `## Main-only (deferred)`") and exit 0. Host-wide stamp: `mcp-down-<server>` (epoch) in `${COMMANDECK_MCP_HEALTH_DIR:-$HOME/.commandeck/mcp-health}`, not `$PP_SCRATCH` (one per project, `paths.sh:62`). A session of any project that finds a stamp under 10 minutes old skips the wait, so the host pays at most one 3-second wait per 10 minutes. A session that sees the server running removes the stamp. The tripwire is skipped in a session whose gate saw the server missing. Dashboard: `alerts()` passes the stamps to the rules (`--slurpfile mcp`, one `{server, at}` per stamp file), and `dashboard_alerts.jq` raises one `mcp-down-<server>` alert while a stamp is under 10 minutes old | `pane-budget-gate.test.sh` "server running: unchanged, and a stamp is removed"; "server missing, session over 15 s old, no stamp: the call passes at once (under 2 s) with the note once per session"; "a new session, no stamp, no server: the call returns in under 5 s"; "a stopped (T) server process counts as missing"; "a stamp written by a session of one project (one `COMMANDECK_SCRATCH`) makes a session of another project skip the wait"; `read-tracker.test.sh` "no MCP-unused warning in a session whose gate saw the server missing"; `dashboard-alerts.test.sh` "a fresh mcp-down stamp raises one alert; an old one none"; and, through `dashboard.sh`'s collect (the Builder names the test that drives `alerts()`: `dashboard-alerts.test.sh` or `dashboard-main-events.test.sh`), "a fresh `mcp-down-serena` stamp in the health folder lists one `mcp-down-serena` alert" |
| E3 host issue 3038 | built | `scripts/read-verdict.sh` `pane_sessions` :348-358 | on macOS, read each claude pid's NUL-separated environment with the host's `KERN_PROCARGS2` reader (python3 ctypes `sysctl`, `kern.argmax` buffer) and match whole `ORCA_TERMINAL_HANDLE=<h>` entries. `/proc` systems are unchanged | `read-verdict.test.sh` "a claude whose other variable holds ' ORCA_TERMINAL_HANDLE=term_x' is not linked to term_x; one whose own entry is term_x is" (a stand-in binary named `claude` started with that environment) |
| E3 host issue 3029 | built | `hooks/dependency-addition-guard.sh` before the loop :475 | with candidates, two parses with `jq -e .`: the on-disk file, and the manifest the edit would leave. That result is built as the tool applies it: Write's `content`; Edit's `old_string` replaced by `new_string` in the on-disk text (every match under `replace_all`, else the first); MultiEdit's edits in order, if the hook screens MultiEdit. On-disk invalid: "BLOCKED: <file> is not valid JSON, so this edit cannot be screened for a new dependency; fix the file first (a Write of valid JSON is screened)." Result invalid: "BLOCKED: this edit leaves <file> as invalid JSON; make the edit keep it valid." Exit 2 either way; the candidate loop runs only when both parse | `dependency-addition-guard.test.sh` "an edit to an invalid package.json blocks naming the file, not a package"; "on a valid `{"scripts":{"check":"old"}}`, an Edit of `"check":"old"` to `"check":"new",` blocks as invalid after the edit and does not name `check`"; "a valid edit of a valid file screens as before" |
| E4 host issue 3053 | built | `scripts/dashboard_limit.py` `codex_row` (:993 on 02f3ac3), its two callers (:1085, `skills/worktreereview/scripts/collect.py:314-317`), the Codex request cache's version check :1035 and writer :1104 | a file with no `thread_settings_applied` before the row passes a "tier not read" value. The row is priced at the standard rate and counted in `estimatedUsd`. `service_tier` null (read, standard) is unchanged. The cache version goes from 4 to 5 at :1035 and :1104, so a version-4 cache is read again and its rows get the mark (main's answer: no migration code) | `dashboard-billing.test.sh` (the file with the Codex `:fast` case; the Builder confirms): "fast tier priced at the fast rate"; "standard unchanged"; "a switch mid-file prices each part at its own rate"; "no settings record: standard rate, counted as estimated"; "a version-4 cache that holds an unchanged log with no settings record is read again: its rows are in estimatedUsd" |

## 3. Part F -- issues 336 to 339

| Issue | Source | Plugin site | Change | Test (file, case) |
|---|---|---|---|---|
| 336 closing run cites unchanged inputs | built (no host twin) | new `scripts/test-inputs.sh <commit> <test file>...`; `templates/_builder-brief-template.md` closing-run rule :91-102 | `test-inputs.sh` prints `unchanged <file>` or `changed <file>`. A file's inputs are the file, every `hooks/` or `scripts/` file it names by basename (`shell-tests-for.sh`'s relation, in reverse), and then, to a fixed point, every file those inputs source: a `.` or `source` line whose path ends in a literal basename found under `hooks/` or `scripts/` (so `read-verdict.sh:522`'s `. "$(dirname ...)/paths.sh"` adds `paths.sh`). A source line with no literal basename (a variable path) makes the file `changed`: when coverage is not certain, the file runs. It compares the inputs with `git diff --quiet <commit> HEAD --`. Shortcut comment: "inputs by basename and literal source lines; a file read some other way is not seen; upgrade to a traced run if one is missed". Brief: in a closing run, a touched file that passed at an earlier commit of this build, and whose inputs are unchanged since then, is cited: `Closing run: <file>: cited <log> at <commit>, <n> passed, <n> failed`. Before the hand-off, once the closing pass ends GO, every touched file runs on that tip (one complete run), with `--callers` (E2) | new `scripts/__tests__/test-inputs.test.sh` "after a commit that changes no input, the file is unchanged"; "a change to a script the file names makes it changed"; "a change to `paths.sh` alone makes `read-verdict.test.sh` changed (it names `read-verdict.sh`, which sources `paths.sh`)"; "a source line with no literal basename makes the file changed"; `brief-template.test.sh` "the closing-run rule names the cite-at-commit line and the complete run on the tip" |
| 337 class-stop sweep | built (host issue 3164) | `builder-codex-pass.sh` `## The same class again` :1216-1227 (as D2 changes it); `_builder-brief-template.md` class rule :33-36 | on the first class stop, the Builder starts one background read-only agent. It lists every site in the changed files, and the scripts they source, where the class's flaw can occur, checked against the class's ruling, as a compact list. The Builder fixes or justifies each site before the next pass. The evidence file gets one line per site: `Sweep: <file>:<line>: fixed` or `: safe, <why>` | `brief-template.test.sh` "the class rule names the background sweep and the Sweep line"; `builder-codex-pass.test.sh` "the class-again block starts the sweep" |
| 338 main delegates large reads | built (host issue 3165) | `templates/main-session.md` card (40 lines, at the cap) and Details | one card line, folded into an existing line so the card stays at 40: a read over 10 KB (merge log, review report, run result) goes to a background read-only agent with one precise question, and the answer comes back as a few lines with file:line. Main reads directly when it must act on exact text (a commit, an edit, a ruling quote). Details holds one example prompt | `brief-template.test.sh` "main's card names the large-read rule and the 10 KB line"; `bash scripts/startup-size.sh` green |
| 339 paperwork beside long runs | built (host issue 3166), measure before and after | each part's evidence file; `_builder-brief-template.md` (only if material); `CHANGELOG.md` | Measure: the minutes from the end of a closing run to the hand-off. Baseline, before any rule: part D's and part E's builds each record `Paperwork after tests: baseline <n> min (part D)` (and `(part E)`). If the owner keeps one unit, the two baselines are taken at group 4's and group 7's test-run ends, to the end of that group's evidence sections. If the larger baseline is 5 minutes or more, part F adds the brief rule: beside a test run expected over about 5 minutes, start a background agent to draft the evidence sections that do not depend on results, run the leak check, and draft the hand-off; fill in the totals at the end. Part F's own closing run then records `Paperwork after tests: with the rule <n> min`. Issue 339 closes only with the baseline and the after number in part F's CHANGELOG entry. Under 5 minutes: no rule, no after run; the baselines go in the CHANGELOG entry as the issue's closing note | if the rule is added: `brief-template.test.sh` "the brief names the background paperwork rule beside runs over 5 minutes"; either way: the evidence lines above, checked under Done when |

## 3b. Autodecide port (owner order 2026-10-24)

The owner's order: "the plugin needs to be based on my decisions here. thats the entire point. i never said to make
it different form whats here. fine change the name but who told you to change anything else". The plugin's
`/autodecide` (`hooks/autodecide.tsx`) becomes the owner's prototype, ported as is. The ONLY allowed changes:

- names and keys: `/autodecide`, "auto-decide"/"AUTO-DECIDE" in text, the `commandeck` atoms `autoDecideSince` and
  `autoDecideCount`, the `autodecide:rules` section id;
- paths: the log `<main>/.claude/metrics/autodecide-<stamp>.md` (with its `mkdir -p`), the Orca tab's
  `--worktree path:<session root>`, the plugin's script paths;
- the seat gate and config already in the plugin: `seatOf` and `autoDecideSeats`, the `mode:<main>` and
  `lastCount:<main>` store keys, the redraw in `active` and the 5 s poll (both exist because two seats share one
  mode), `neverOf` and `autoDecideNever`;
- the public-repo scrub: the owner's name becomes "the owner" (pronouns "they/their"), main's name "main", the
  relay's nickname, a product name and a private project are removed.

The decision patterns and the never-decide list ship fixed, as the prototype has them; `autoDecideNever` extends
the list. The ledger-reading code goes: `ownerPattern` (:84-108), `EXAMPLES` (:24-31) and `Mode.how`.

Departures (the owner's prototype against `hooks/autodecide.tsx` on 02f3ac3, read line by line), each with its fix:

| # | Where | Prototype | Plugin today | Fix |
|---|---|---|---|---|
| 1 | rules head | "... turned it on at <since> ET with /<name> on" | no "ET" | "ET" back (row 8) |
| 2 | rules opening | the owner's standing words of 10-23, quoted | a one-line paraphrase | the quote back, word for word |
| 3 | no-ask bullet | "no AskUserQuestion picker (it is blocked while this is on)"; "picking what is best for the platform's long-term health, not the fastest path" | "the question picker is blocked"; the long-term clause moved to the opening, "platform" read as "project" | prototype text |
| 4 | How the owner decides | a fixed list of 7 lines, "(from the owner's last 100 picks, 10-22 to 10-23; they took the recommended option at least 71 times)" | computed from the decisions ledger at `on`; a 5-line fallback without the backward-compatibility and token-only-wakes lines, two lines shortened | the 7 lines word for word (the host project's name becomes "the host project"; the owner's quote about zero customers stays) |
| 5 | never-decide | one sentence, 8 items: an admin PROD login; copying PROD images or personal data; the licence or consent of training data; verification or score lines; a seat's network or write access; password or security minimums; accepting a rollout gap on a security change; the configured values of product settings in DEV or PROD, with the owner's note "leave things as they are, i'll change them myself" | `NEVER` (:15-22), 6 reworded items; no score lines, no rollout gap, no note, no "password", no DEV/PROD | the sentence word for word (the product name drops out of "score lines"). A non-empty `autoDecideNever` adds one sentence after it: "The owner's own additions (`autoDecideNever`): <a>; <b>." |
| 6 | limits | "any PROD deploy or PROD read beyond counts, any push to any repo, any irreversible delete, any new feature flag, any new unit or build ..., and any policy call they reserved. Do not start new work beyond what the owner already approved." | "production", "remote", no "any new feature flag", "Start no new work" | prototype text; the private-project item goes (scrub) |
| 7 | Summary and last bullets | "Keep a "## Summary" at the top of the log current: ..."; "give them a short account of what you decided (point them at the log). Mode stays on until they run /autodecide off." | reworded | prototype text; the log path stays named in the Summary bullet while row 12 keeps the log bullet out |
| 8 | clock | `date` under `TZ=America/New_York`; every time shown with " ET" (rules head, already-on, status, band, off line, log head) | the machine's zone, no "ET" | the prototype's zone and " ET" back |
| 9 | log head | title names the relay's nickname and the owner; "**why**" in bold; "Limits kept: no PROD deploy, no push, no irreversible delete, no new feature flag, no new unit, ..." | no Limits kept line; "the why" | "# Decisions made for the owner (auto-decide, from <since> ET)", "**why**", the Limits kept line without the private project |
| 10 | `on` | appends "- <day> <name> decision log: <file>" to the reports index; replies "Decisions are mine until /<name> off." | no index; "Decisions are made for you until" | the index line goes to `<main>/.claude/metrics/INDEX.md` (path change; the folder is ignored, `.gitignore:7`); prototype reply |
| 11 | `off`, status, description, deny | "OFF after <n> decision(s)"; "turned off by the owner at <t> ET."; "Autonomous decisions for the owner: /autodecide on \| off \| status"; deny "... Decide this yourself, log it with its why, and do not ask." | "decision"/"decisions"; "Decide for the owner while away"; the deny names `relay-order.sh --auto` | prototype text |
| 12 | record step | the model writes the entry under "## Decisions" ("### HH:MM ET: <unit or id>, <short title> (my decision)", **Question**, **Picked**, **Why**, **Reversible**) before it answers, then `relay-order.sh <id> '<label>'`, else `decision.sh answer` and the seen mark; it tells main itself | one `relay-order.sh --auto` call writes the entry, records `<words> (auto-decided)`, marks it seen and tells main | kept (owner answer 2026-10-24) |
| 13 | log section order | Summary, Decisions, Waiting | Summary, Waiting, Decisions (`--auto` appends at the file's end) | follows row 12 |
| 14 | `off` log write | reads the log, writes it back with the end line | appends (`tee -a`), so an `--auto` entry in flight is kept | follows row 12 |
| 15 | same-minute run | a second `on` in one minute writes over the first log | the next free `-<n>` name | kept (owner answer 2026-10-24) |
| 16 | recount guard | no `.catch` | `.catch`: a failed recount does not fail the tool call | kept (owner answer 2026-10-24) |

Rows 12, 15 and 16: no allowed change covers them; they are kept (owner answer 2026-10-24). Main's check of a relay decision rests on the `(auto-decided)` ledger
answer (`templates/main-session.md:139-142`). The prototype's `relay-order.sh <id>` needs an owner ruling, so for
the model's own pick it always takes the `decision.sh answer` fallback, which main cannot check. Row 15 stops a log
from being written over. The other choice, strict: rows 12-16 take the prototype's form. Then `relay-order.sh --auto`
and the `autodecide.on` file have no user and go, with their readers (map, "Autodecide port"). The fallback writes
the plugin's seen file (`relay-order.sh:77`, `id@askedAt`) and tells main through `to-main.sh`. That adds about 120
lines in 8 files to group 9.

Test (`hooks/autodecide.test.tsx`): one new case, "the rules are the owner's own, shipped fixed: each How the owner
decides line, the never-decide sentence and the limits sentence are word for word, and a ledger of 105 departing
answers changes no word of them". The rules come from the owner, not from a reading of the ledger. Updated: the
status, band and off-line cases gain " ET" (:115, :128, :137, :248); the date stub checks `TZ=America/New_York`;
the rules case checks "any push to any repo", "any new feature flag" and the `autoDecideNever` sentence (:149-153);
the log-head case checks the Limits kept line and the index line (:111). Deleted: the two ledger cases (:285-317).
`docs/chief-of-staff.md` :65-66 says the list is the owner's own, shipped fixed. Leak: no shipped text keeps a name
the scrub removes (`bash ci/leak-test.sh`).

## 4. Dropped, done, waiting

- F12: done by part C (`templates/main-session.md:1-40`, `scripts/startup-size.sh:37-40`). Dropped.
- F13 (task tools off for main): dropped by the owner's order; replaced by 1c.
- F16: waits for the owner. Not in this unit; reported as waiting.
- D1 cuts 2, 7, 9, 11: no plugin sender, or already done (section 1a).
- Host issue 3147's root cause (MCP timeouts on the host's Mac): host-only.
- Issue 337's and 338's "measure on the next builds/sessions": after this unit; main's to record.

## 5. Build order

Each group's changed-file tests and the by-hand tests it names are green before the next group starts.

Part D:
1. D1 cuts 1, 5, 6, 8, 12 (hooks, fresh round, brief text). First, before any edit: the Builder records each D1
   sender's line count in the wake log (`pp_wake_log`, `paths.sh:401`; part A is on main) in the evidence file, one
   line per sender, `Wake count before: <sender> <n>`. By hand: `hooks/__tests__/worker-notify.test.sh`,
   `pane-budget-gate.test.sh`, `read-tracker.test.sh`, every test of a `paths.sh` caller that greps the wake log
   (`main-watch-wake-log.test.sh`).
2. D1 cuts 3, 4, 10 (main-watch, seat collect, read-verdict `prompt`). **Riskiest group of the unit**: a wrong cut
   silences news main must act on, and the delivery lock is shared by collect and flush. By hand: every
   `scripts/__tests__/main-watch-*.test.sh`, `seat.test.sh`, `seat-run.test.sh`, `read-verdict.test.sh`.
3. D2. By hand: every `builder-codex-pass*.test.sh`, `brief-template.test.sh`.
4. 1c checklist. By hand: `resume-context.test.sh`, `agent-startup-context.test.sh`.

Part E (after D: it changes the same `pane-budget-gate.sh` block and the same collect):
5. E1 (3009 first, since 2998, 3028 and 3162 use `pp_pane_close`; then 2998, 3011, 3162). **Riskiest group of
   part E**: `pp_task_close` gates every settle. By hand: every test that runs `seat.sh collect` or
   `pp_task_close` (`rg -l 'pp_task_close|seat.sh collect' scripts/__tests__ hooks/__tests__`), `orca-wait.test.sh`,
   `answer-worker.test.sh`, `context-clear-restart.test.sh`, `plan-worktree-close.test.sh`.
6. E2. By hand: `merge-unit-local*.test.sh`, `run-shell-tests.test.sh`, `seat-launch.test.sh`.
7. E3, E4. By hand: `pane-budget-gate.test.sh`, `read-tracker.test.sh`, `dashboard-alerts.test.sh`,
   `dashboard-main-events.test.sh`, `main-watch-wake.test.sh` (both read `alerts()` output), `read-verdict.test.sh`,
   `dependency-addition-guard.test.sh`, `dashboard-billing.test.sh`, every `dashboard-built*.test.sh` (they source
   `dashboard_limit.py`).

Part F (after E: 336 uses `shell-tests-for.sh` and `--callers`; 337 edits the block D2 rewrites):
8. Issues 336, 337, 338, then 339's after measurement at this part's own closing run. By hand:
   `brief-template.test.sh`, `builder-codex-pass.test.sh`, `startup-size.test.sh`.

The port (section 3b; after F, before the version step; it shares no file with groups 1-8, and the owner's word on
rows 12, 15 and 16 is in before it starts):
9. The autodecide port. By hand: `claude plugin test .` (it runs `hooks/autodecide.test.tsx`;
   `run-shell-tests.sh` runs no `.tsx` test; CI runs it at `.github/workflows/ci.yml:37`), `bash ci/leak-test.sh`.
   Strict choice only: also `relay-order.test.sh`, `brief-template.test.sh`, `install-lib.test.sh`.

## 6. Size (changed lines, code + tests, estimates)

| Item | Lines | Group total | Files (group) |
|---|---|---|---|
| D1 cut 1 (NO-GO and worker_done exits, ask exemption) | ~80 | | |
| D1 cut 5 (MCP escalations) | ~35 | | |
| D1 cut 6 (tool-blocked lines) | ~25 | | |
| D1 cut 8 (fresh-round retry) | ~35 | | |
| D1 cut 12 (one status per decision) | ~15 | 1: ~190 | 12 |
| D1 cut 3 (heads-up digest) | ~150 | | |
| D1 cut 4 (`reported()`, once, lock, `mark_handled`, `prompt`) | ~230 | | |
| D1 cut 10 (collect receipt under lock) | ~90 | 2: ~470 | 7 |
| D2 fix 1 (every ordering) | ~20 | | |
| D2 fix 2 (second return) | ~25 | | |
| D2 fix 3 (third return through ask-main.sh) | ~35 | 3: ~80 | 5 |
| Checklist: done = deleted | ~20 | | |
| Checklist: cap, subject, ids text | ~15 | | |
| Checklist: guard hook and its test | ~110 | 4: ~145 | 7 |
| **Part D** | | **~885** | **~31** |
| E1 host issue 3009 (`pp_pane_close`, culprit, runner stub) | ~170 | | |
| E1 host issue 2998 (`pp_open_ask`, settle refusal) | ~190 | | |
| E1 host issue 3011 (record follows the pane) | ~40 | | |
| E1 host issue 3162 (probe, setsid detach) | ~50 | 5: ~450 | 16 |
| E2 host issue 3028 (quiesce before archive, step 5 hold) | ~75 | | |
| E2 host issue 2997 (`shell-tests-for.sh`, `--callers`) | ~95 | | |
| E2 host issue 2999 (Timed checks line) | ~10 | 6: ~180 | 7 |
| E3 host issue 3147 (bounded gate, host-wide stamp, dashboard alert) | ~150 | | |
| E3 host issue 3038 (NUL-safe env read) | ~60 | | |
| E3 host issue 3029 (both manifests parsed) | ~55 | | |
| E4 host issue 3053 (tier mark, cache version 5) | ~50 | 7: ~315 | 13 |
| **Part E** | | **~945** | **~33** |
| Issue 336 (`test-inputs.sh`, transitive inputs, brief rule) | ~100 | | |
| Issue 337 (class sweep) | ~25 | | |
| Issue 338 (large-read delegation) | ~15 | | |
| Issue 339 (measurement; the rule only if material) | ~20 | 8: ~160 | 8 |
| Port: rules, log head, clock and texts as the prototype (3b rows 1-11) | ~75 | | |
| Port: ledger code deleted (`ownerPattern`, `EXAMPLES`, `Mode.how`) | ~40 | | |
| Port: `autodecide.test.tsx` cases, `docs/chief-of-staff.md` | ~100 | 9: ~215 | 3 |
| Version, CHANGELOG, docs (per part) | ~45 | | 3 |
| **Total** | | **~2,250** | **67 distinct** |

Over the cap: 24 items in 10 groups and 67 files (46 non-light owners in the map), against four cuts, 40 files and
20 owners. Built as one unit by the owner's answer (header, `Split override:`). The strict choice of 3b adds about
120 lines in 8 files (about 2,370 lines in 71 files), still under the 3,000-line limit.

## 7. Halfway cut

The cut list runs past an hour. The halfway cut is the end of group 4 (all of part D, ~885 lines, 4 of 10 groups):
group 4's by-hand tests green, then the part D `Paperwork after tests: baseline` line and a checkpoint in the
evidence file before group 5 starts. A stop there leaves a tree whose finished groups' tests pass; groups 5-9 are
not started.

Questions for main: none (the split was answered).

## 8. Catches (each added flow step)

- NO-GO silence, worker_done check: main woken for a fix round it never acts on, or twice for one finish.
- Ask exemption on both exits: a question or refusal silenced because the turn also ended NO-GO or was reported.
- Heads-up digest and repeat drop: the same note posted every tick.
- `reported()`, stall once, delivery lock, `mark_handled`: duplicate finish posts; a minted task left pending.
- Fresh-round retry: main told about a typing failure that one retry fixes.
- Every-ordering prompt, second and third return rules: one ordering bug found per pass.
- Third return through ask-main.sh: a class question main never sees in its thread, or a reply the Builder never waits on.
- Checklist guard: the reminder re-sending a long list of done items every turn.
- `pp_task_close` refusal: a Builder's dispatch settled while it waits on main.
- `pp_pane_close` log and runner stub: a pane gone with no cause on record; a test closing a real pane.
- Uncollected seat pane kept: a plan seat swept before collect reads its verdict.
- Record follows the live pane: fresh rounds typed into a dead handle.
- setsid detach: a seat run killed with main's old pane.
- Quiesce before archive: a live worker's last evidence lines written after the archive and lost with the worktree.
- Step 5 hold: uncommitted work deleted with the worktree.
- `--callers` on the tip: a caller's test turned red by a merge, unseen until CI.
- Timed checks line: a heavy fixture eating an older check's time budget.
- Bounded MCP gate and host-wide stamp: every fresh session, in every project, waiting on a server that is down host-wide.
- Dashboard mcp-down alert: a host-wide MCP outage nobody sees until a worker reports it.
- NUL-safe env read: a verdict read from another pane's session.
- Invalid-JSON block, on disk or after the edit: a script key named as a new package.
- Tier-not-read mark and cache version 5: Codex dollars shown as exact when the tier is unknown, including rows already cached.
- Cite at commit, transitive inputs: re-running files whose inputs did not change; citing one whose sourced script did.
- Class sweep: the next pass finding another site of the same flaw.
- Large-read delegation: a log read once and paid for on every later turn.
- Background paperwork (only if issue 339's baseline is 5 minutes or more): minutes of evidence writing after every long run.

## 9. Version and CHANGELOG

Main carries 0.45.1 today. Each part takes the next free minor when its build starts (part D: 0.46.0 unless
another unit takes it first): `.claude-plugin/plugin.json:3` (`ci/version-check.sh` fails when the plugin changed
and that number did not), the README badge (by hand: since 02f3ac3, `version-check.sh` no longer compares it) and a
CHANGELOG.md entry in the format of the 0.45.1 entry. Part D's entry names the message cuts, the ordering rules and
the checklist trim. Part E's names each host twin. Part F's entry names issues 336 to 339 in the CHANGELOG's own
issue form (the one file where that form is allowed), with issue 339's baseline and, if the rule is added, its after
number. The plan's `Closes:` line (header) is in the leak-safe form; main copies the map's `#` form into the batch
brief, which is what `merge-unit-local.sh:263` reads.

## Files edited

Part D:
- `hooks/codex-notify.sh` ~37, ~67-72; `hooks/claude-worker-notify.sh` ~67, ~98-103; `hooks/__tests__/worker-notify.test.sh`
- `scripts/paths.sh` ~401 (new `pp_worker_done_since`)
- `scripts/main-watch.sh` ~236, ~354-380, ~1023, ~1037-1052, ~1295 and the tick's heads-up call;
  `scripts/__tests__/main-watch-message-cuts.test.sh` (new); the tick helpers of the existing `main-watch-*.test.sh`
  (digest 0, lock 1 s)
- `scripts/read-verdict.sh` (ordinal `prompt`), `scripts/__tests__/read-verdict.test.sh`
- `scripts/seat.sh` ~620-628; `scripts/__tests__/seat.test.sh`
- `hooks/pane-budget-gate.sh` ~111-120, `hooks/__tests__/pane-budget-gate.test.sh`; `hooks/read-tracker.sh` ~83-93,
  `hooks/__tests__/read-tracker.test.sh`
- `hooks/dependency-addition-guard.sh` ~43, ~278, `hooks/__tests__/dependency-addition-guard.test.sh`;
  `hooks/suite-rerun-guard.sh` ~326 and its test
- `scripts/builder-fresh-round.sh` ~25-33 and the lock section, `scripts/__tests__/builder-fresh-round.test.sh`
- `scripts/builder-codex-pass.sh` ~119-122, ~1216-1227; `scripts/__tests__/builder-codex-pass.test.sh`
- `templates/_builder-brief-template.md` ~28-38, ~33-36, ~177-186; `templates/AGENT_STARTUP.md`;
  `templates/main-session.md` ~99-103, ~113-115; `templates/checkpoint.md` ~81; `scripts/__tests__/brief-template.test.sh`
- `hooks/resume-context.sh` ~102, `hooks/__tests__/resume-context.test.sh`
- `hooks/checklist-guard.sh` (new), `hooks/hooks.json` PreToolUse, `hooks/__tests__/checklist-guard.test.sh` (new);
  `docs/hooks.md` (one row)

Part E:
- `scripts/paths.sh` ~569-597 (`pp_task_close`), new `pp_open_ask`, new `pp_pane_close`
- `scripts/seat.sh` ~165-170, ~379, ~413, ~400, ~620-640, ~746-757; `scripts/answer-worker.sh` (thread reply);
  `scripts/__tests__/seat.test.sh`, `seat-run.test.sh`, `seat-launch.test.sh`, `answer-worker.test.sh`
- `scripts/close-done-panes.sh` ~105, ~116, `scripts/__tests__/close-done-panes.test.sh` (new)
- `hooks/lib/context-clear-restart.sh` ~69, ~84, `hooks/__tests__/context-clear-restart.test.sh`
- `scripts/plan-worktree-close.sh` ~141, `scripts/codex-helpers.sh` ~123
- `scripts/builder-fresh-round.sh` ~131-132, `scripts/__tests__/builder-fresh-round.test.sh`
- `scripts/merge-unit-local.sh` ~417-422 (quiesce before the brief archive), ~545-552 and the DONE line,
  `scripts/__tests__/merge-unit-local.test.sh`
- `scripts/run-shell-tests.sh` ~67-80 (`--callers`), the stub before `run_one`; `scripts/__tests__/run-shell-tests.test.sh`
- `scripts/shell-tests-for.sh` (new), `scripts/__tests__/shell-tests-for.test.sh` (new)
- `hooks/pane-budget-gate.sh` ~86-123, `hooks/read-tracker.sh` ~26-95, `scripts/dashboard.sh` ~1036-1046 (`alerts()`),
  `scripts/dashboard_alerts.jq`, their tests and `scripts/__tests__/dashboard-alerts.test.sh` (or
  `dashboard-main-events.test.sh`, whichever drives `alerts()`)
- `scripts/read-verdict.sh` ~348-358, `scripts/__tests__/read-verdict.test.sh`
- `hooks/dependency-addition-guard.sh` ~475, its test
- `scripts/dashboard_limit.py` ~993, ~1035, ~1085, ~1104; `skills/worktreereview/scripts/collect.py` ~314-317;
  `scripts/__tests__/dashboard-billing.test.sh`
- `docs/troubleshooting.md` (pane-closes.log, the step 5 hold, the MCP health folder), `docs/commands.md` (`--callers`)

Part F:
- `scripts/test-inputs.sh` (new), `scripts/__tests__/test-inputs.test.sh` (new)
- `templates/_builder-brief-template.md` ~33-36, ~91-102 (and the issue 339 rule only if material);
  `scripts/builder-codex-pass.sh` ~1216-1227; `templates/main-session.md` card and Details;
  `scripts/__tests__/brief-template.test.sh`, `builder-codex-pass.test.sh`

The port (section 3b):
- `hooks/autodecide.tsx` (rules, log head, clock, `on`/`off`/status texts, deny; `ownerPattern`, `EXAMPLES` and
  `Mode.how` deleted), `hooks/autodecide.test.tsx`; `docs/chief-of-staff.md` ~65-66
- Strict choice only: `scripts/relay-order.sh` (the `--auto` branch), `scripts/__tests__/relay-order.test.sh` (its
  `--auto` cases, ~86 on), `templates/main-session.md` ~139-142, `scripts/__tests__/brief-template.test.sh` ~50-54,
  `scripts/install-lib.sh` ~324, `scripts/__tests__/install-lib.test.sh` ~102-112, `docs/commands.md` ~66-73,
  `docs/chief-of-staff.md` ~70-77

Every part: `.claude-plugin/plugin.json` ~3, `README.md` badge, `CHANGELOG.md`.

## Done when

- Every row of sections 1-3 is built, or dropped with its evidence line (sections 1c, 2 and 4), and each test case
  it names passes on the branch.
- Section 3b: every row of its table is fixed as stated (rows 12-16 as the owner's word says); `claude plugin
  test .` passes; `rg -n 'ownerPattern|EXAMPLES|decisions\.jsonl' hooks/autodecide.tsx` prints nothing; every
  difference left between `hooks/autodecide.tsx` and the owner's prototype is one of the allowed changes.
- `bash scripts/run-shell-tests.sh --changed main` and every by-hand test the part's groups name in section 5
  pass. `claude plugin validate .`, `bash scripts/startup-size.sh` (and `--per-prompt`) and `bash ci/leak-test.sh`
  pass.
- Each Keep sender of 1a still sends, and the evidence file names the case that shows it.
- Part D's evidence file has one `Wake count before: <sender> <n>` line per D1 sender, recorded before group 1's
  first edit.
- Host issue 3162's probe result is in the evidence file (the item is built, or dropped because the run survives).
- Issue 339: part D's and part E's evidence files each have a `Paperwork after tests: baseline <n> min` line. If the
  larger is 5 minutes or more, the rule is in the brief template and part F's evidence has a `Paperwork after tests:
  with the rule <n> min` line; part F's CHANGELOG entry gives the numbers either way.
- Each part's version is the next free minor in `plugin.json` and the README badge, with its CHANGELOG entry;
  part F's entry closes issues 336 to 339.
- Each part's closing (final) review pass ends `VERDICT: GO` naming no finding; local squash merge only, no push.

## Judge round 1

One line per finding of the round 1 NO-GO; each is taken, none is disputed.

- P1 quiesce before archive: taken. Panes and Codex helpers stop before step 4's brief archive (`merge-unit-local.sh:417-422`; the helper stop moves up from :552); two new cases (section 2, host issue 3028).
- P2 ask lines and the new exits: taken. Both exits are skipped when `ASK` is set (`codex-notify.sh:32`, `claude-worker-notify.sh:49`); the judge's `QUESTION:` then `NO-GO` reply is a case (1a cut 1).
- P2 third return transport: taken. The question goes through `scripts/ask-main.sh`; the retry-path sentence stays word for word; `brief-template.test.sh:44`, `:49` and `:97` pass unchanged (1b fixes 2, 3).
- P2 plain issue numbers: taken. The guard's pattern covers "issue 336", "issue-336" and "host issue N"; `Fix issue 336` is a case (1c).
- P2 bounded, host-wide health check: taken. The wait is 3 s, only while the session is under 15 s old; a stopped or zombie server counts as missing; the stamp folder is host-wide, not `$PP_SCRATCH` (`paths.sh:62`). Assumption: "bounded" read as these two limits, the host issue text not re-read this round.
- P2 dashboard collector: taken. `dashboard.sh` `alerts()` (:1036-1046) passes the stamps to `dashboard_alerts.jq`; a collect case is named (section 2, host issue 3147).
- P2 proposed manifest: taken. The guard parses the manifest the edit leaves as well as the on-disk one; the judge's `"check":"new",` edit is a case (host issue 3029).
- P2 cached Codex rows: taken. The cache version goes from 4 to 5 (`dashboard_limit.py:1035`, :1104), as main ruled; a version-4 cache case (host issue 3053).
- P2 transitive inputs: taken. `test-inputs.sh` follows literal source lines to a fixed point and reads an unresolved one as changed; the judge's `paths.sh` case is named (issue 336).
- P2 issue 339 before and after: taken. Baselines at parts D and E, the after number at part F's closing run; the issue closes only with both (issue 339, Done when).
- P3 background paperwork catch: taken (section 8, last line).
- P3 D1 before counts: taken. `Wake count before:` lines before group 1's first edit (section 5 group 1, Done when), as the earlier plan's :269 required.
- P3 per-item estimates: taken. Section 6 now gives lines per item, then group totals.
- P3 current-main evidence: taken. 02f3ac3 is 0.45.1 and changes 14 files (top of the plan); `ci/version-check.sh` no longer compares the README badge, so the badge is raised by hand (section 9).

## Routing

- Class: cross-file runtime because one delivery lock, `delivered-seat-<handle>-<task>.lock`, is a contract
  written by `scripts/seat.sh` collect and taken by `scripts/main-watch.sh` `flush`, and the new `pp_task_close`
  refusal sits on the settle path of five callers (map, "Readers").
- Riskiest cut: group 2 (D1 cuts 3, 4 and 10). A wrong `reported()` or lock silences a finish main must act on, or
  posts it twice; the reviewer's first question is number 1 below.
- Recommended seat change: none.
- Planned size: 67 files, 2250 changed lines

## Stated limits (every reviewer is handed these; a finding beyond one is a follow-up issue, not a blocker)

- Checklist guard: one session's task folder per TaskCreate/TaskUpdate. Largest folder 49 files of 322 folders:
  `for d in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/tasks/*/; do ls "$d" | wc -l; done | sort -n | tail -1`, 2026-10-24.
- `scripts/test-inputs.sh` and `scripts/shell-tests-for.sh` fixed points: 117 scripts and 159 test files.
  `ls hooks/*.sh hooks/lib/*.sh scripts/*.sh | wc -l`; `ls hooks/__tests__/*.test.sh scripts/__tests__/*.test.sh | wc -l`,
  2026-10-24.
- `reported()`: one inbox read per tick, `--limit 500` (a fixed bound, not measured). A run with more messages can
  miss an older worker_done; the result is a duplicate post, the accepted direction (1a cut 4).
- MCP wait: at most one 3-second wait per server per 10 minutes host-wide (a bound by design, not measured).
- `pane-closes.log`: one line per close, no rotation. Not measured (the log does not exist before this unit).

## How this will be reviewed

What to check, in particular:

1. Group 2: can `reported()`, the `once` posts, the delivery lock or `mark_handled` drop a finish, stop or minted
   task main must act on, in any order of collect, flush and tick? An unreadable inbox or prompt time must post.
2. Group 1: does a `QUESTION:` or `BLOCKED:` line still reach main from a turn that ends `VERDICT: NO-GO` or whose
   worker_done Orca accepted (both hooks)? Does a refused worker_done still echo?
3. Group 5: does `pp_task_close` still settle a task with no seat record as before (`orca-wait.sh`, `main-watch.sh`,
   `paths.sh` ~557), and refuse on every failed read? Does any script close a pane outside `pp_pane_close`?
4. Group 6: is any brief archived, or the worktree removed, while a pane or a Codex helper of the unit is live, or
   with an uncommitted path? Is plain `--changed` unchanged?
5. Group 7: does the MCP gate never block on a missing server, wait only in a session under 15 s old, and share the
   stamp across projects? Does the manifest guard parse both manifests before the loop? Is a row with no settings
   record in `estimatedUsd`, and is a version-4 cache read again?
6. Group 3 and issue 337: is the retry-path sentence word for word, do `brief-template.test.sh` :44, :49, :97 and
   `builder-codex-pass-decisions.test.sh` ~46-52 pass, and does the third return go through `ask-main.sh` only?
7. Group 4: does `hooks/checklist-guard.sh` check main's session only, and let the call through on an unreadable
   folder? Does every id pattern in 1c, and only those, refuse?
8. Group 8: does `test-inputs.sh` call a file `changed` on any unresolved source line? Is `main-session.md`'s
   card still 40 lines (`startup-size.sh`)? Does the CHANGELOG entry carry issue 339's numbers?
9. Every file: no leak word (`bash ci/leak-test.sh`), and each Keep sender still sends.
10. Group 9: is every departure of `hooks/autodecide.tsx` from the owner's prototype one of the allowed changes
    (names and keys, paths, the seat gate and config, the scrub), or a row 12, 15 or 16 the owner answered? Do the
    rules carry the prototype's How the owner decides lines, never-decide sentence and limits word for word, with
    no ledger read?

## Author self-check

- Every "existing" input has a producer line and an emitter: `ASK` (`codex-notify.sh:32`,
  `claude-worker-notify.sh:49`), the wake log (`paths.sh:401`), the seat record's `handle=`, `task=`, `launched=`
  (`seat.sh:419`), `service_tier` (`dashboard_limit.py` ~1038-1042, from the Codex log's `thread_settings_applied`).
  `answer_task=` has no producer in the plugin (`rg -n answer_task scripts hooks` is empty, 2026-10-24), so the
  2998 refusal reads `task=` only, unless the port of `c8b82ae5` brings the line that writes it. `autoDecideNever`
  is the owner's own key in `.claude/commandeck.json`, kept by `setup.sh:126` and read by `autodecide.tsx:62-70`.
- The map's Edited owners list has a current and a projected count per file. Two owners are `.tsx`
  (`hooks/autodecide.tsx` 246 to ~225, `hooks/autodecide.test.tsx` 317 to ~320), both under the 400 cap
  (`hooks/file-size-cop.sh:59`), so none is past a cap; 21 rows are `(light)`.
- No edited owner is in the map's In flight list (plugin: none); Decisions names the order with the host unit.
- Every file the unit creates is named by its full repository path (1a, 1c, section 2, section 3, Decisions).
- Each performance or growth concern is under Stated limits, with the command and date, or marked not measured.

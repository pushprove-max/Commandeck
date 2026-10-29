# plugin-open-5-2026-10-29 -- the open plugin issues in one unit

Owner's words: the owner, 2026-10-29 ~02:04 ET: start a unit for all remaining plugin issues. One unit for the five open Commandeck issues, no split, whatever the size caps say.
Owner's additions: #456, #457 and #458 (owner, 2026-10-29 ~02:32 ET), #455 (owner, 2026-10-29) and #461 (owner, 2026-10-29), each added to this unit by number; their host twins are not waited on.
Goal: Close #450-#458 and #461 (#453 Refs) in one unit: gate-reader rule, one-refusal precheck, fast builder tests, Orca retest, ask-main answers, plan rules, CI green, quieter relay watchers.
Plan: .claude/plans/plugin-open-5-2026-10-29.md
Tier: Standard; LOCAL merge only; changed-file tests only; no test-timeout raises; one unit, no split.
Build order: C1 (#450), C2 (#451), C3 (#454), C4 (#453), C5 (#452), C6 (#455), C7 (#456), C8 (#457), C9 (#458), C11 (#461), C10 (version, notes).
- Planned size: 34 files, 620 changed lines
Timed checks: rebase.test.sh typecheck `sleep 30` with a 1 s limit :93-96; answer-worker.test.sh WAIT/ACK :49, :153, `timeout 8` :161, `sleep 3` :184; context-clear-stop.test.sh `wait_for` :66, `sleep 1` :357, :375; builder-fresh-round.test.sh `timeout 10` :46, :108, :197; fresh-round.test.sh `timeout 30` :102, :183; agent-startup-context.test.sh `timeout -s KILL 3` :230; cos-tell.test.sh none (rg sleep|timeout, 2026-10-29). Every new case goes after them, at the end of its file; the final-pass rebase case (C2) is the heavy one.
Version: 0.61.0 (a minor: new behaviour), unless `bash ci/version-check.sh` at merge time says another number is taken.
Closes: #450 #451 #452 #454 #455 #456 #457 #458 #461
Merge commit message: `Closes #450`, `Closes #451`, `Closes #452`, `Closes #454`, `Closes #455`, `Closes #456`, `Closes #457`, `Closes #458`, `Closes #461`, `Refs #453` (owner, 2026-10-29: no live Orca restart).

## Why

The order is every open plugin issue in one unit. #450, #451 and #452 twin host issues whose fixes sit committed, not merged, on the host branch; each is ported from host commit 5b4ce55d, adapted, not redesigned. #451 needs less here than on the host: the plugin already runs its evidence checks before it stages, commits or rebases, so the port is the collector (one refusal for all failed checks) and the rebase-state checks. #454 is built from its issue text: a Builder in ask-main.sh's wait reads as busy, so the answer is typed behind a wait of up to 240 s. #453 is a retest: each workaround is kept with its reason; the one real gap is main's restart, which drops the permission mode when the launch line has quotes or braces, and the fix reads the parent's real argv, never the flat ps line. #455's two files fail in any checkout: each test misses setup a later script change needs. #456-#458 are plan-tooling rules from one benchmark grade: a Done line must be what a user sees, a stated limit may not strand a fix, and deferred work needs a filed issue. #461: the relay's watchers stop waking it for what it cannot act on; the plugin has no idle-unit watcher, so one is added.

## Prior art

- #450: host 5b4ce55d, `.claude/briefs/_builder-brief-template.md` hunk @@ -277 (the allowlist paragraph) and `builder-codex-pass.sh` hunk @@ -97 (the LENS sentence `Gate readers`). The host's reference-doc hunk has no plugin twin file; the plugin's fix hand-off bullets play that part.
- #451: host 5b4ce55d, `builder-codex-pass.sh` hunks @@ -66 (`REFUSALS`, `refuse`, `refusals_flush`), @@ -877 and @@ -886 to @@ -1019 (`die` to `refuse` in the evidence and cap checks), @@ -1145 (`precheck`), @@ -1188 (`refusals_flush` after the real staging). The host's review-base and installed-brief hunks belong to other issues.
- #452: host 5b4ce55d splits `case_warm` out of `case_fresh`; the plugin already names each new session log, so only the split ports (D8).
- The host branch may still change before it merges; the port names 5b4ce55d.
- #454: the existing parked-wait classifier (`simple_wait`) and the `--interrupt` wait token; no new mechanism.
- #453: read-verdict.sh `pid_env` reads a process's NUL-separated entries from /proc or KERN_PROCARGS2; C4 reads argv the same way.
- #456-#458: seat.sh's role spec lines and plan-check.sh's existing checks; no host commit is ported (twins not merged).
- #461: the owner's local `watch-units.sh` and host `watch-alerts.sh`, reference only; the plugin's code is cos-watch-alerts.sh and `cos_wait`.
- Standard: templates/test-rules.md: never weaken a test; each new test names its bug.

## Data design

- ask-main.sh writes `$PP_SCRATCH/ask-main/<id>.asking` (`pid=`, `pane=`, tmp then `mv`) once before its first inbox wait and removes it on exit (EXIT trap, after `unwait`); a killed call's file names a dead pid. answer-worker.sh reads it, read only, to find the question id when none is given: it stays between two inbox waits, when `<id>.wait` is gone (fix r3). `<id>.wait` keeps its meaning: only `--interrupt` reads and claims it.
- builder-codex-pass.sh: `REFUSALS`, an in-process array, empty at start, flushed once before the `--check` exit and once after the real staging. Nothing on disk.
- Index copy: `$LOCK/index`, as `--check` uses today, now made for every pass; removed with the lock.
- context-clear-stop.sh reads the parent's argv (NUL-separated): `/proc/$PPID/cmdline`, else KERN_PROCARGS2 on macOS; test input `COMMANDECK_PARENT_ARGV`, a file in that format. Read only.
- plan-check.sh reads only the plan text it reads today.
- C3 tests, at the end of answer-worker.test.sh: the simple call (stub ask-main shape `bash scripts/ask-main.sh q body`), the compound call (typed), and the ledger case: `answer-worker.sh <pane> answer`, no seat record, a live `msg_new.wait` for the pane, `u1-msg_new` and `u1-msg_q4` open; the reply's thread is `msg_new`, `u1-msg_new` closes, `u1-msg_q4` stays open.
- C4 cases, at the end of context-clear-stop.test.sh: argv `claude --settings {"a":1} --permission-mode acceptEdits` gives `claude --permission-mode acceptEdits`; argv `claude --settings {"env":{"NOTE":" --dangerously-skip-permissions "}} --permission-mode acceptEdits` gives exactly `claude --permission-mode acceptEdits`, and `claude --append-system-prompt --dangerously-skip-permissions` gives `claude`.
- C11 fixtures: two cases at the end of cos-tell.test.sh with `alert`/`alertwatch` (:285-286): a `builder-demo/u1-quiet-<t>` and a `stage-demo/u1-<t>` alert print nothing, a `builder-demo/u1-stuck-<t>` and a `stale-gh-<t>` alert print; a limit alert prints once, then nothing at the next poll and nothing under a stamp 10 min later, no seen line added by hand. cos-watch-units.test.sh, in cos-tell.test.sh's env shape (:40) with `COMMANDECK_WATCH_ONCE=1`, repos aged by `GIT_COMMITTER_DATE` and `touch -t` (20 min old): u1 r9 NO-GO and r10 GO, r10's mtime the commit's own second (silent); u2 newest NO-GO, u3 GO older than its commit (each one `IDLE` line); an idle `Chief-of-Staff` worktree (silent); a second poll prints nothing. agent-startup-context.test.sh greps the relay print (as :65) for `scripts/cos-watch-units.sh`.
- cos-watch-alerts.sh: `<state>/<project>.alerts-seen` (ids, one a line) now also gets each id the watcher prints, after the told write; `.alerts-told` and cos_wait's pid and wake files unchanged.
- cos-watch-units.sh (new): `<state>/<project>.units-idle-seen`, one `<unit> <short sha>` line per idle unit printed; reads each `$PP_WORKSPACES/<unit>` worktree, its newest `.claude/briefs/<unit>-r<N>-reports.md` and `$PP_SCRATCH/merge-<unit>.log`. cos_wait's writes, as every watcher's: `<state>/<project>.cos-watch-units.pid` (each start, no reader), `<state>/<project>.cos-watch-units-wake-<epoch>-<pid>.txt` per poll (removed on no find, kept unpruned on a wake), one `$PP_SCRATCH/wake-log.jsonl` line per wake; the header names them all. No other state is added or changed.
- C6 checkout (CI's: ci.yml:9 checks out one commit, :44 fetches main's history before the shell tests at :48-49): `B=$(git branch --show-current)`; `git clone -q --no-local --depth 1 --branch "$B" "file://$PWD" "$C"`; `git -C "$C" checkout -q --detach`; `git -C "$C" branch -q -D "$B"`; in `$C`, ci.yml:44 as written: `git fetch --no-tags --unshallow origin main 2>/dev/null || git fetch --no-tags origin main`. Then, as A6: no `refs/heads/main`, HEAD detached, not shallow, `b15d8ee` present. Removed after the run.
- C8 kept files: the seat fixture's EXIT trap (seat-setup.sh:7) removes `$T`, which holds the judge prompt (`$REC.prompt`, seat.sh:574) and the spec it names (`$T/judge-spec.md`, seat.sh:402, test :77). Run the test unedited as `BASH_ENV=$K/keep-env.sh bash scripts/__tests__/seat-plan-marker.test.sh` ($K a scratch dir, never exported); the file is written with `$K` expanded at write time to its absolute path, so it holds no `$K`: `unset BASH_ENV` and `trap() { if [ "${*: -1}" = EXIT ]; then printf '%s\n' "$T" > '<abs K>/T'; return 0; fi; builtin trap "$@"; }`; the run must still end `0 failed` (A7). Case `C8 kept files, K not exported`: with `K` set but not exported, the run ends `0 failed` and `<abs K>/T` names the fixture's `$T`; a file holding a literal `$K` fails it (`K: unbound variable` under `set -u` when seat-setup.sh:7 sets the trap). Then `KT=$(cat "$K/T")`, per fixture f: `{ cat "$KT"/home/.commandeck/scratch/*/seat-pu-plan-judge-sol.txt.prompt; printf '\nThe plan to judge is the file %s. End with VERDICT: GO or VERDICT: NO-GO.\n' "$PWD/scripts/__tests__/fixtures/plan-judge-reach/$f.md"; } | claude -p --model sonnet`; then `rm -rf "$KT"`.

## Decisions already made

- D1 #450: one rule, three places, the host's words: (a) a bullet in the fix hand-off after the trust-state bullet (builder-codex-pass.sh ~1932), (b) the template's class-fix lines (~277), (c) the LENS sentence (~147), which is what makes a review flag a one-shape fix (Done 2). docs/review-loop.md gets one sentence.
  Test: builder-codex-pass-class-return.test.sh -- "a fix hand-off and a reviewer prompt both carry the gate-reader allowlist rule (issue 450)"
- D2 #451: the plugin's evidence checks already run before staging (:1239-1308) and the commit (:1467); what is ported is the collector. `refuse` replaces `die` in: the cap gate (:1088-1089), Sites checked (:1247, :1252), `new_code_checked` (:1150), `break_gate` (:1280), `table_gate` (:1299), the new-test cap (:1307) and the no-testCommand refusal (:1326). A `die` for a failed read (could not count, could not list) stays a `die`. One flush before the `--check` block (:1332); one refusal prints `REFUSED: <text>` exactly as today, two or more print `REFUSED: <k> checks failed:` and a `- <text>` line each.
  Test: builder-codex-pass-class-return.test.sh -- "two failed checks are refused in one, before any commit (issue 451)"; builder-codex-pass-suite.test.sh -- "a final after a NO-GO with no evidence and no test command lists all three refusals at once (issue 451)"
- D3 #451: `precheck` (host @@ -1145): every pass stages into the index copy (`cp -p`), then, for a final, refuses a rebase in progress (`rebase-merge` or `rebase-apply` in the git dir) and tracked files the copy leaves changed; then the flush. `--check` reuses it and exits. The real `stage_and_check` (:1367) follows.
  Test: builder-codex-pass-rebase.test.sh -- "a final with a rebase in progress and a changed tracked file is refused once, before it commits (issue 451)"
- D4 #454: `simple_wait` also reads as a wait one simple command whose program is `ask-main.sh` by base name, run directly or as the first word after `bash` or `sh`. The same shell-split rules hold: an operator or substitution anywhere reads as work.
  Test: answer-worker.test.sh -- "a pane waiting in ask-main.sh gets its answer as a reply in its question's thread, nothing typed (issue 454)"
- D5 #454: with no question id from the argument or the seat record, the id is the name of this pane's live call token (`<id>.asking` naming `pane=<handle>`; `.wait` before fix r3, which a gap between waits lost), set as `QID=<id> Q=$QID`, as the seat-record lookup sets both (:99): `close_asks` filters on `Q` (:53-62) and the detached follower is handed only `Q` (:281). No token, no id: today's send.
  Test: answer-worker.test.sh -- "an answer with no id and no seat record replies in the waiting question's thread and closes only that question (issue 454)"
- D6 #453: every workaround is kept; results are recorded in docs/troubleshooting.md, one row per Orca item, with the reason. Items 1 (seat.sh's turn-start proof), 2 (orca-wait.sh's drain; Orca's 1.4.243 help still says a delivery replays until acknowledged), 3 (the hooks guard cost), 5 (heartbeats dropped unread; no off switch): kept. Item 4: main's restart opens a new pane on purpose, so replay stays.
  Test: none, a doc of results; the stub tests cannot show real Orca behaviour (Stated limits).
- D7 #453 item 4: when the flat line cannot be replayed (context-clear-stop.sh:215), the fallback builds `claude` plus permission options read from the parent's real argv, one entry each, never from the flat ps line. Boundaries: entries after argv[0] up to a `--` entry; an entry is an option only when it is the whole entry and the entry before it is argv[0], an entry not starting with `-`, or a permission option already taken. Taken: `--dangerously-skip-permissions`; `--permission-mode <v>` or `--permission-mode=<v>` with v exactly one of acceptEdits, auto, bypassPermissions, manual, dontAsk, plan (claude 2.1.312's choices, A4). Two mode options: none kept. Any other entry adds nothing; argv unreadable: bare `claude`, as today.
  Test: context-clear-stop.test.sh -- "a launch line with a JSON value restarts with its permission mode kept (issue 453)"; "a permission flag inside an option's value grants nothing on restart (issue 453)"
- D8 #452: the plugin has no builder.test.sh; its twins are builder-codex-pass-fresh-round.test.sh (56 s) and builder-fresh-round.test.sh (73 s). Cut the cost and split, no timeout raised: (a) builder-fresh-round.test.sh's `fr` writes the new session's log under the slug of the hand-off's own worktree, not u9's, so the two u8 hand-offs stop waiting out `timeout 10` (a fixture bug); (b) the warm-or-fresh table (fresh-round.test.sh:162-204; the BSD-awk branch's `fi` at :160 stays) moves unchanged into builder-codex-pass-warm-round.test.sh.
  Test: fresh-round files under 60 s each; "a fix round goes to the live Builder session under its clear line and starts fresh otherwise (issue 445)", in its new file
- D9 #455: reproduce each file's failure in a CI-like checkout first (C6), then fix what the test or script lacks; no case is skipped, parked or loosened.
  Test: builder-codex-pass-class-sites.test.sh and merge-unit-local.test.sh green in that checkout; Done 1 is read on main's CI after the push
- D10 #456: the plan-author spec (seat.sh) asks for a `## Done` section, one `- #<n> Done: <user action> -- <what the user sees>` line per closed issue, with one good and one bad example, and, where the issue names only a component, the user path and every hop, or the missing hop as a stated limit. plan-check.sh refuses a Done line under `## Done` with no ` -- `, a side under three words, or a one- or two-word parenthesized label such as `(API)`.
  Test: seat-plan-marker.test.sh -- "the plan-author prompt asks for a user-observable Done line per issue, with a good and a bad example (issue 456)"; plan-check-budget.test.sh -- "a plan whose issue Done line names only a component is refused (issue 456)"
- D11 #457: one plan-judge line in seat.sh: a stated limit that leaves a planned fix with no real caller in production (no client sends it, a gate blocks it, nothing routes to it) makes the verdict NO-GO unless the owner approved that limit by name. Two fixture plans differ only in that hop.
  Test: seat-plan-marker.test.sh -- "the judge's prompt makes a stated limit that leaves a fix with no real caller a NO-GO (issue 457)"
- D12 #458: plan-check.sh refuses, naming the line, a line outside a fence that carries no `#N` or `owner/repo#N` and is either (a) under `## Stated limits` and says follow-up (`follow-up`, `follow up`, `followup`, any case), the section's opening line exempt word for word, or (b) starts with `Follow-up:`. The word anywhere else (Why, the change log) passes.
  Test: plan-check-budget.test.sh -- "a stated limit naming later work with no issue number is refused, naming the line, and passes with one (issue 458)"
- D13 #461 Fix 1, 2: `new` (cos-watch-alerts.sh:67) drops a fingerprint starting `stage-` (all stage alerts: the id names no stage, dashboard_alerts.jq:58; the owner's version skips all) or starting `builder-` and ending `-quiet`; after the told write each printed id goes to seen. The 24 h repeat stays (cos-tell.test.sh:294-296).
  Test: cos-tell.test.sh -- "quiet and stage alerts do not wake the relay; others do (issue 461)"; "an alert wakes the relay once, under any stamp (issue 461)"
- D14 #461 Fix 3: the plugin has no idle-unit watcher, so new cos-watch-units.sh (`cos_wait 60`) prints `IDLE <unit>: ...` and a seen line for a `$PP_WORKSPACES` git worktree, not standing, with: last commit under 24 h, `<unit> <sha>` unseen, newest round (by number) not a GO at or after that commit, merge log and files (bar hook-written builder-events.jsonl) unchanged 12 min. Startup text, allowlist and doc name it.
  Test: cos-watch-units.test.sh -- "a unit whose newest GO is newer than its last commit is not idle (issue 461)"; "a NO-GO or older-GO unit is reported idle once (issue 461)"; agent-startup-context.test.sh -- "the relay is told to run the idle-unit watcher (issue 461)"

## Assumptions

- A1 [settled] ask-main.sh's question id is the Orca message id answer-worker replies to: to-main.sh prints `.result.message.id` (to-main.sh:58) and ask-main.sh keeps it (ask-main.sh:38-40).
- A2 [settled] Orca 1.4.243 is installed: `orca --version` printed `1.4.243` on 2026-10-29.
- A3 [settled] The 1.4.243 help for `orchestration check` says a bound Run replays the same delivery until `--ack` (`orca orchestration check --help`, 2026-10-29).
- A4 [settled] `claude --help` (2.1.312, 2026-10-29) lists `--permission-mode <mode>` with choices acceptEdits, auto, bypassPermissions, manual, dontAsk, plan, and `--dangerously-skip-permissions` taking no value.
- A5 [settled] #455 reproduced 2026-10-29: `bash scripts/__tests__/<f>.test.sh` in the worktree and in `git clone --no-local --depth 1` gave class-sites 1 passed, 11 failed (`REFUSED: the range main...HEAD has no change`) and merge-unit-local 50 passed, 11 failed (`no test rules file`); with C6's edits in the clone, 11/0 and 60/1, the 1 a depth-1 artifact (:163 reads commit b15d8ee; ci.yml:44 unshallows first).
- A6 [settled] C6's CI-like checkout (2026-10-29, at de4872a, before C6's edits): after the clone, detach and branch delete and ci.yml:44's fetch, `refs/heads/main` is absent, HEAD detached, `--is-shallow-repository` false, `cat-file -e b15d8ee^{commit}` succeeds; merge-unit-local gave 50 passed, 11 failed, all 11 the `templates/` bug, the :163 check passing.
- A7 [settled] C8's kept files (2026-10-29): seat-plan-marker.test.sh run unedited under C8's `BASH_ENV` file gave 66 passed, 0 failed (3:49 wall, loaded machine); `$T/judge-spec.md` and `seat-pu-plan-judge-sol.txt.prompt`, which names it, were still on disk.
- A8 [settled] The relay's startup print in a bare project is 5,246 bytes (`LC_ALL=C wc -c`, 2026-10-29): D14's ~150 bytes stay under 10,240.
- A10 [settled] Today's alerts watcher printed one alert at two polls in a row and its new stamp at a third, no seen line added (scratch HOME, `1 1 1`, 2026-10-29).

## Steps

- modify scripts/builder-codex-pass.sh ~76-1932 -- refuse, flush, precheck; LENS and hand-off rule (#450, #451)
- modify templates/_builder-brief-template.md ~277 -- allowlist rule (#450)
- modify docs/review-loop.md ~50 -- allowlist rule; one refusal (#450, #451)
- modify scripts/__tests__/builder-codex-pass-{class-return,rebase,suite}.test.sh -- #450/#451 cases
- modify scripts/answer-worker.sh ~93-176 -- ask-main.sh wait; id from its token (#454)
- modify scripts/__tests__/answer-worker.test.sh -- #454 cases
- modify hooks/context-clear-stop.sh ~215 -- argv permission options (#453)
- modify hooks/__tests__/context-clear-stop.test.sh -- argv cases; stop_hook 3rd arg (#453)
- modify docs/{troubleshooting,auto-permission-mode}.md -- Orca retest; restart mode (#453)
- modify scripts/__tests__/builder-fresh-round.test.sh ~106 -- fr logs under its unit (#452)
- modify scripts/__tests__/builder-codex-pass-fresh-round.test.sh ~162-204 -- warm table out (#452)
- new scripts/__tests__/builder-codex-pass-warm-round.test.sh -- the warm table, unchanged (#452)
- modify scripts/__tests__/{builder-codex-pass-class-sites,merge-unit-local}.test.sh -- CI setup (#455)
- modify scripts/seat.sh ~440-445 -- Done-line and reachability rules (#456, #457)
- modify scripts/plan-check.sh ~360 -- Done-line and issue-number checks (#456, #458)
- modify scripts/__tests__/{seat-plan-marker,plan-check-budget}.test.sh -- #456-#458 cases
- new scripts/__tests__/fixtures/plan-judge-reach/{stranded,reachable}.md -- fixtures (#457)
- modify scripts/{cos-watch-alerts,worktree-setup}.sh -- skip quiet/stage, mark seen; allow units (#461)
- new scripts/{cos-watch-units.sh,__tests__/cos-watch-units.test.sh} -- idle-unit watcher (#461)
- modify {hooks/agent-startup-context.sh,hooks/__tests__/agent-startup-context.test.sh,scripts/__tests__/cos-tell.test.sh,docs/chief-of-staff.md} -- relay text, #461 cases
- modify {.claude-plugin/plugin.json,README.md,CHANGELOG.md} -- 0.61.0 and its entry

## Cuts

- C1 #450, ~20 lines. What: D1, the host's sentence (5b4ce55d @@ -277) with its issue number dropped, as a fix hand-off bullet after :1932, a template line after :277 and a LENS sentence (host @@ -97) at the end of :147's string; one sentence in docs/review-loop.md after :53. Test at the end of class-return.test.sh: `hand` of the last NO-GO and `input` of a narrowed pass each grep the rule.
  Produces: the rule text in the fix hand-off, the brief template and every reviewer prompt. Consumes: nothing new.
  Consumers: every Builder (template), fix round (hand-off) and reviewer (LENS); the checks counting hand-off or prompt lines (class-return, threshold) stay green unedited.
- C2 #451, ~100 lines. What: D2 and D3, ported from host 5b4ce55d. `REFUSALS`, `refuse` and `refusals_flush` after `die` (:76). The listed `die`s become `refuse`, :1326 included, so the flush before the `--check` block reports it with the rest. `precheck` replaces the body of the `--check` block (:1332-1337): `cp -p` the index to `$LOCK/index`, `GIT_INDEX_FILE` staging, for a final the two rebase-state checks, then `refusals_flush`; `--check` prints its line and exits; otherwise the pass goes on to the sign-in probe and the real `stage_and_check` (:1367). The three tests go at the ends of their files; the suite case runs pass 15 final after pass 14's NO-GO (:48-53) with `.fullSuiteBeforeFinal = true`, `del(.testCommand)` and no evidence sections, then restores the config.
  Catches: a final on a stopped rebase or a dirty tracked file, which today fails only after the commit (:1383-1387).
  Produces: `REFUSED: <k> checks failed:` and `- <text>` lines (k >= 2); a single refusal unchanged. Consumes: the index copy path `$LOCK/index` (exists today).
  Consumers: the Builder reading stderr; every builder-codex-pass*.test.sh that greps a `REFUSED:` text (cap-gate, class-return, class-sites, threshold, closing, rebase, suite :38-39); each stays green unedited.
Break: scripts/__tests__/builder-codex-pass-suite.test.sh -- a final after a NO-GO with no evidence and no test command lists all three refusals at once (issue 451) -- scripts/builder-codex-pass.sh:1326 refuse back to die
- C3 #454, ~30 lines. What: D4 in `simple_wait` (:160-176): after the env-assignment pop, a first word `bash` or `sh` is dropped once, then a word whose base name is `ask-main.sh` with at least one more word is a wait. D5 at the end of the lookup block (:93-104): when `QID` is still empty and not in the follower, the first `$PP_SCRATCH/ask-main/*.asking` (`*.wait` before fix r3) holding `pane=$H` whose `pid=` is a live ask-main.sh (claim_wait's test :80-87, without the `mv`) names the id: `QID=${f##*/}` minus `.asking`, then `Q=$QID`, said on stderr as the seat-record lookup does. Tests: Data design's `C3 tests`.
  Catches: an id-less answer to a pane with no seat record, which today replies outside ask-main.sh's thread and leaves its question open.
  Produces: the inbox route and question id for a pane in ask-main.sh's wait. Consumes: the wait token (ask-main.sh:59-72), read only.
  Consumers: `idle`, `working` and `confirm` read `pending_state`; `close_asks` and the follower read `Q`; the `--interrupt` path (answer-worker-interrupt.test.sh) skips the lookup; the two-open case (:90-92) has no token, unchanged.
Break: scripts/__tests__/answer-worker.test.sh -- an answer with no id and no seat record replies in the waiting question's thread and closes only that question (issue 454) -- scripts/answer-worker.sh token lookup `Q=$QID`
- C4 #453, ~60 lines. What: D7 in context-clear-stop.sh's fallback (:215-218): read argv from `COMMANDECK_PARENT_ARGV`, else `/proc/$PPID/cmdline`, else (Darwin) python3 KERN_PROCARGS2 as read-verdict.sh:347-377 reads it, the argc entries in place of the environment; walk it by D7's rules into `cmd=claude ...`; the log line names what was kept. `stop_hook` (:56-62) gains `${3:+COMMANDECK_PARENT_ARGV="${3}"}`; no existing call changes. Cases: Data design's `C4 cases`. D6: a docs/troubleshooting.md table `Orca 1.4.241-1.4.243 retest`, one row per item; docs/auto-permission-mode.md one line on the restart.
  Catches: a permission word that is data (in a value, or an option's value), which splitting the flat ps line would grant.
  Produces: the restart command's mode on the fallback path. Consumes: `COMMANDECK_PARENT_ARGS` (exists), `COMMANDECK_PARENT_ARGV` (new test input).
  Consumers: hooks/lib/context-clear-restart.sh `open_main` runs the command as given; unchanged.
Break: hooks/__tests__/context-clear-stop.test.sh -- a permission flag inside an option's value grants nothing on restart (issue 453) -- hooks/context-clear-stop.sh argv walk predecessor rule
- C5 #452, ~110 lines (~45 moved). What: D8. (a) builder-fresh-round.test.sh:106: `$LOGS` becomes the slug dir of `${BR%/.claude/briefs}` (as builder-fresh-round.sh:220 computes it), made with `mkdir -p`. (b) the comment and table at fresh-round.test.sh:162-204 go, line for line, to the new file after a header (`set -uo pipefail`, the fixture source, a comment naming issues 445 and 452) and the closing count lines; :160's `fi` and :205-206 stay. Builder check before the cut: `time bash` each of the three files; any over 60 s: split the fresh-round passes (56-145) the same way; times go in the evidence file.
  Produces: three files, each under 60 s. Consumes: the fixture (cfg, check, FB, SC, REPO), unchanged.
  Consumers: shell-tests-for.sh selects the new file for builder-fresh-round.sh by name; run-shell-tests.sh runs it.
Break: scripts/__tests__/builder-codex-pass-warm-round.test.sh -- a fix round goes to the live Builder session under its clear line and starts fresh otherwise (issue 445) -- scripts/builder-fresh-round.sh:165 `-ge` to `-gt`
- C6 #455, ~4 lines. What: D9; both are test setup bugs: each fails the same in the worktree and a depth-1 clone (A5). (a) class-sites.test.sh:10 writes `echo base`, the base commit's own a.sh, so pass 1's `main...HEAD` is empty and the empty-range guard (builder-codex-pass.sh:1535-1537) refuses; write `echo first` instead (not `built`, which class-return uses). (b) merge-unit-local.test.sh's plugin copy (:248, :268-269) leaves out `templates/`, so the copied pass script dies on test-rules.md (:146); add `templates` to the two `cp` lists and the `git add`. No check line changes.
  CI-like checkout: Data design's `C6 checkout`, after C6's commit; :163 unedited (red there: redo the checkout, never the check).
  Catches: a fix green only where a local `main` or full history exists.
  Produces: two green files in CI. Consumes: the fixture repo, unchanged. Consumers: run-shell-tests.sh in ci.yml:48-49.
Break: scripts/__tests__/builder-codex-pass-class-sites.test.sh -- the pass runs the reviewer's search and keeps every hit as path:line -- scripts/builder-codex-pass.sh:1179 class_sites writes no hit
Break: scripts/__tests__/merge-unit-local.test.sh -- the refused dashboard step never ran --install, and the off-list line is named -- scripts/merge-unit-local.sh:710 off-list line runs
- C7 #456, ~45 lines. What: D10. seat.sh: one plan-author line after :440 with the rule, good example `- #2739 Done: a user retries an import from the dashboard after a lost response -- no duplicate import appears`, bad example `- #2739 Done: retry key handling (API)`. plan-check.sh: a Python block after the budget block, before `issue_check` (:361), reading `PC_FENCED`; each failing Done line is one `REFUSED: <plan> line <n> Done line names a component, not what a user sees: <line>`. Tests at the ends of seat-plan-marker.test.sh (prompt grep, as :45-46) and plan-check-budget.test.sh (`pc` with `ok` plus a Done section: `(API)` line refused, label line refused, good line passes).
  Catches: a component-only Done line (`(API)`), which passes today.
  Produces: the refusal; the author rule. Consumes: nothing new. Consumers: seat.sh (judge launch) and builder-launch.sh run plan-check; plans with no `## Done` section are unchanged.
Break: scripts/__tests__/plan-check-budget.test.sh -- a plan whose issue Done line names only a component is refused (issue 456) -- scripts/plan-check.sh Done-line check
- C8 #457, ~35 lines. What: D11. seat.sh: one plan-judge line after :445. Fixtures `stranded.md` (its stated limit says no client sends the fix's header) and `reachable.md` (that hop in its Cuts). Test at the end of seat-plan-marker.test.sh greps the judge prompt, as :86-87. Builder check after the test: Verification's `C8 judge check`.
  Catches: a stated limit that strands a fix (stranded.md); today's judge prompt is silent on it.
  Produces: the judge rule. Consumes: nothing. Consumers: every plan judge seat.
- C9 #458, ~35 lines. What: D12 in the same new Python block as C7; one refusal lists every line: `REFUSED: <plan> names later work with no filed issue (#N or owner/repo#N):` then `  - line <n>: <line>`. Test at the end of plan-check-budget.test.sh: `ok` plus `## Stated limits` and its exact opening line plus `- the import UI key is a follow-up` is refused naming that line, as is a `Follow-up: the CORS header` line; each with `(#12)` or `other/repo#3` passes; the word in `## Why` and `## Plan change log` with no number passes.
  Catches: a deferral line with no filed issue, which passes today.
  Produces: the refusal. Consumes: nothing. Consumers: as C7; no test's plan fixture holds the word (rg, 2026-10-29).
Break: scripts/__tests__/plan-check-budget.test.sh -- a stated limit naming later work with no issue number is refused, naming the line, and passes with one (issue 458) -- scripts/plan-check.sh issue-number check
- C11 #461, ~160 lines. What: D13, D14; headers say what each watcher marks; tests per Data design's `C11 fixtures`.
  Catches: a quiet or stage alert waking the relay; an alert reprinted at the next poll (A10); a unit idle after its closing GO reported.
  Produces: fewer wakes; seen lines; `IDLE <unit>:` lines. Consumes: data.js alerts, worktrees, round files, merge logs (read only).
  Consumers: the relay pane and its own seen appends (a set, :38); three other tests run the alerts watcher (Facts), green unedited; cos-check.sh, the Stop hook unchanged (F4).
- C10 version, ~15 lines. What: plugin.json and the README badge to 0.61.0 (or what `ci/version-check.sh` gives); a `## 0.61.0 -- <merge date>` CHANGELOG entry, plain bullets under `### Reviews`, `### Workers` and `### Planning`, no file, issue, function or hash names.
  Produces: the version. Consumes: C1-C9 and C11 done. Consumers: ci/version-check.sh, release-notes.sh --check.

## What can go wrong

| Case | Input or starting state | Expected result | Test |
|---|---|---|---|
| Round order and equal times | u1 with r9 NO-GO and r10 GO (r10 sorts before r9 as text); r10's mtime equal to the commit second | r10 is the newest; equal counts as newer; u1 not reported | a unit whose newest GO is newer than its last commit is not idle (issue 461) |
| Rebase stopped | a final pass with a rebase stopped at `break` and a changed tracked brief | one refusal naming both, before any commit or rebase; HEAD unchanged | a final with a rebase in progress and a changed tracked file is refused once, before it commits (issue 451) |
| Helper wait, odd shapes | pending `bash scripts/ask-main.sh q body`, no seat record, a live token; then `ask-main.sh q b; npm test` | the first: an inbox reply in the token's thread, nothing typed; the second: typed (work) | a pane waiting in ask-main.sh gets its answer as a reply in its question's thread, nothing typed (issue 454) |
| Flag inside a value | argv `claude --settings {"env":{"NOTE":" --dangerously-skip-permissions "}} --permission-mode acceptEdits` | restart command exactly `claude --permission-mode acceptEdits` | a permission flag inside an option's value grants nothing on restart (issue 453) |
| Slow fix round | a fix round touching builder-fresh-round.sh runs its twin files | each under 60 s; the u8 hand-offs end without a timeout; the warm table still fails on today's bug | fresh-round files under 60 s each |
| Done action a label | `- #39 Done: (API) -- no duplicate import appears` | refused, naming the line | a plan whose issue Done line names a component as the user action is refused (issue 456) |
| Idle watcher state | the watcher runs once finding and once not | every file it leaves is named in its header | every file the idle watcher writes is named in its header |
| Token gap | a no-id answer while ask-main.sh is between two inbox waits (`.wait` gone, `.asking` held) | a reply in the question's thread, nothing typed | an answer sent while ask-main.sh is between two inbox waits replies in its question's thread |

## Accepted failure modes

- F1 A Builder that runs ask-main.sh inside a compound command reads as working and gets the answer typed at its next tool result, as today: the safe direction.
  Test: the D4 test's compound case.
- F2 A permission option right after a value-less option (`claude --verbose --dangerously-skip-permissions`) is not kept: the restart asks for permissions, the safe direction.
  Test: none, the safe direction; D7's rule is tested by the value case
- F3 plan-check reads only the Done line's shape (#456) and the follow-up word (#458); other component-only wording is the judge's to flag.
  Test: none, the shape rule is what a script can decide; D10 and D12 tests cover it
- F4 The idle-unit watcher is not held by the Stop hook or cos-check.sh: if it dies, no idle-unit wake, as today (no such watcher). Holding it changes cos-check.test.sh:59-60, :135 and cos-inbox-waiter-stop.test.sh:58.
  Test: none, the fallback is today's state; D14's startup test proves the relay is told to run it

## Stated limits

(every reviewer is handed these; a finding beyond one is out of scope: a follow-up issue, never a blocker)
- Real Orca behaviour (#453 items 1-5) is not proven by stub tests; measured: `orca --version` 1.4.243, `orca orchestration check --help`, 2026-10-29.
- Under 60 s is per file, at the load of the run: measured 56 s and 73 s (`time bash scripts/__tests__/<f>.test.sh`, 2026-10-29).
- Idle-unit scan: 0.013 s per worktree of 507 files (`time find`, D14's prunes, `-mmin -0`, 2026-10-29).

## Acceptance test

- class-return.test.sh: "a fix hand-off and a reviewer prompt both carry the gate-reader allowlist rule (issue 450)"; "two failed checks are refused in one, before any commit (issue 451)"
- builder-codex-pass-suite.test.sh: "a final after a NO-GO with no evidence and no test command lists all three refusals at once (issue 451)"
- rebase.test.sh: "a final with a rebase in progress and a changed tracked file is refused once, before it commits (issue 451)"
- answer-worker.test.sh: "a pane waiting in ask-main.sh gets its answer as a reply in its question's thread, nothing typed (issue 454)"; "an answer with no id and no seat record replies in the waiting question's thread and closes only that question (issue 454)"
- context-clear-stop.test.sh: "a launch line with a JSON value restarts with its permission mode kept (issue 453)"; "a permission flag inside an option's value grants nothing on restart (issue 453)"
- fresh-round files under 60 s each: `time bash` on the three files of C5.
- warm-round.test.sh: "a fix round goes to the live Builder session under its clear line and starts fresh otherwise (issue 445)"
- class-sites.test.sh and merge-unit-local.test.sh: every check green, unedited checks, in the worktree and Data design's `C6 checkout`, "a leak-test.sh older than --text: the merge goes on and says the word list was not applied" included (#455)
- C8 judge check: evidence records `C8 judge check: stranded` NO-GO, `C8 judge check: reachable` GO (#457)
- seat-plan-marker.test.sh: "the plan-author prompt asks for a user-observable Done line per issue, with a good and a bad example (issue 456)"; "the judge's prompt makes a stated limit that leaves a fix with no real caller a NO-GO (issue 457)"
- plan-check-budget.test.sh: "a plan whose issue Done line names only a component is refused (issue 456)"; "a stated limit naming later work with no issue number is refused, naming the line, and passes with one (issue 458)"
- cos-tell.test.sh: "quiet and stage alerts do not wake the relay; others do (issue 461)"; "an alert wakes the relay once, under any stamp (issue 461)"
- cos-watch-units.test.sh: "a unit whose newest GO is newer than its last commit is not idle (issue 461)"; "a NO-GO or older-GO unit is reported idle once (issue 461)"
- agent-startup-context.test.sh: "the relay is told to run the idle-unit watcher (issue 461)"
Break: scripts/__tests__/builder-codex-pass-class-return.test.sh -- two failed checks are refused in one, before any commit (issue 451) -- scripts/builder-codex-pass.sh refusals_flush
Break: scripts/__tests__/answer-worker.test.sh -- a pane waiting in ask-main.sh gets its answer as a reply in its question's thread, nothing typed (issue 454) -- scripts/answer-worker.sh simple_wait ask-main.sh branch
Break: hooks/__tests__/context-clear-stop.test.sh -- a launch line with a JSON value restarts with its permission mode kept (issue 453) -- hooks/context-clear-stop.sh fallback permission options
- Every existing test in the changed files, unedited, green.

## Claims to falsify

- The plugin runs every evidence check before `git add` (:1314) and the commit (:1467).
- No existing test reads a `REFUSED:` line that a second failed check would change.
- `simple_wait` reads no ask-main.sh call as a wait today.
- ask-main.sh returns at once on a reply in its question's thread, and on no other message.
- context-clear-stop.sh restarts a quoted launch line as bare `claude`.
- No plugin script needs a workaround removed for Orca 1.4.241-1.4.243.
- No plugin file is named builder.test.sh; the fresh-round files are its twins.
- The warm table reads only fixture state, so it runs alone in its own file.
- The u8 hand-offs in builder-fresh-round.test.sh end by `timeout 10` today.
- With builder-fresh-round.sh:165's `-ge` made `-gt`, the warm table's `equal` case (:192) comes out `warm:0:0:1:0`, not `fresh:1:0:1:0` (:204).
- Without `Q=$QID`, the ledger case leaves `u1-msg_new` open.
- With :1326 left a `die`, the suite case prints one refusal, not three.
- No doc names plan-check.sh's checks (`rg plan-check docs README.md templates`: no hit, 2026-10-29).
- Today an alert printed once prints again at the next poll, under its stamp or a new one, unless the pane adds a seen line.
- No plugin script reports an idle unit worktree to the relay.
- A unit's round files are git-ignored, so its last commit never holds its newest report.
- No test that runs cos-watch-alerts.sh expects a stage or Builder-quiet alert.

## Issue cases

- #450 Fix 1 -- scripts/builder-codex-pass.sh -- a fix hand-off and a reviewer prompt both carry the gate-reader allowlist rule (issue 450)
- #450 Fix 2 -- templates/_builder-brief-template.md -- a fix hand-off and a reviewer prompt both carry the gate-reader allowlist rule (issue 450)
- #451 Fix 1 -- scripts/builder-codex-pass.sh -- a final with a rebase in progress and a changed tracked file is refused once, before it commits (issue 451)
- #451 Fix 2 -- scripts/builder-codex-pass.sh -- two failed checks are refused in one, before any commit (issue 451)
- #452 Fix 1 -- scripts/__tests__/builder-fresh-round.test.sh -- fresh-round files under 60 s each
- #452 Fix 2 -- scripts/__tests__/builder-codex-pass-warm-round.test.sh -- a fix round goes to the live Builder session under its clear line and starts fresh otherwise (issue 445)
- #453 Fix 1 -- docs/troubleshooting.md -- a launch line with a JSON value restarts with its permission mode kept (issue 453)
- #453 Fix 2 -- docs/troubleshooting.md -- a launch line with a JSON value restarts with its permission mode kept (issue 453)
- #453 Fix 3 -- hooks/context-clear-stop.sh -- a launch line with a JSON value restarts with its permission mode kept (issue 453)
- #454 Body 1 -- scripts/answer-worker.sh -- a pane waiting in ask-main.sh gets its answer as a reply in its question's thread, nothing typed (issue 454)
- #455 Fix 1 -- scripts/__tests__/builder-codex-pass-class-sites.test.sh -- class-sites.test.sh and merge-unit-local.test.sh: every check green
- #455 Fix 2 -- scripts/__tests__/merge-unit-local.test.sh -- class-sites.test.sh and merge-unit-local.test.sh: every check green
- #456 Fix 1 -- scripts/seat.sh -- the plan-author prompt asks for a user-observable Done line per issue, with a good and a bad example (issue 456)
- #456 Fix 2 -- scripts/seat.sh -- the plan-author prompt asks for a user-observable Done line per issue, with a good and a bad example (issue 456)
- #457 Fix 1 -- scripts/seat.sh -- the judge's prompt makes a stated limit that leaves a fix with no real caller a NO-GO (issue 457)
- #458 Fix 1 -- scripts/plan-check.sh -- a stated limit naming later work with no issue number is refused, naming the line, and passes with one (issue 458)
- #461 Fix 1 -- scripts/cos-watch-alerts.sh -- quiet and stage alerts do not wake the relay; others do (issue 461)
- #461 Fix 2 -- scripts/cos-watch-alerts.sh -- an alert wakes the relay once, under any stamp (issue 461)
- #461 Fix 3 -- scripts/cos-watch-units.sh -- a unit whose newest GO is newer than its last commit is not idle (issue 461)

## Done

- #450 Done: a reviewer reads a one-shape gate-reader fix -- flags it, and the fixer's hand-off names the allowlist rule
- #451 Done: a Builder starts a pass that fails several checks -- sees every failure in one refusal, nothing committed
- #452 Done: a Builder runs a fix round's fresh-round test files -- each file finishes in under 60 seconds
- #453 Done: the owner restarts a main launched with a JSON value -- the new main keeps its permission mode
- #454 Done: main answers a Builder waiting in ask-main.sh -- the Builder reads the answer in that wait, nothing typed
- #455 Done: the owner pushes main -- CI on main is green and the release job publishes the version
- #456 Done: a plan author writes a component-only Done line -- plan-check refuses it, naming the line
- #457 Done: a judge reads a stated limit that strands a fix -- the verdict is NO-GO
- #458 Done: a plan author names later work without an issue -- plan-check refuses it, naming the line
- #461 Done: a Builder goes quiet, a unit idles after its closing GO, a limit alert fires -- the relay pane wakes once, for the limit alert only

## Progress notes

- #450: built when C1's test is green.
- #451: built when C2's tests are green.
- #452: built when C5's run is under 60 s and its warm test is green.
- #453: partial -- a live Orca restart of a main pane in a known mode (owner, 2026-10-29: not run; merges as Refs #453).
- #454: built when C3's tests are green.
- #455: built when both files are green in the CI-like checkout; its Done (CI on main green, the release job run) is read only after the push, which this LOCAL merge does not do.
- #456, #457, #458: built when C7, C8 and C9's tests are green and C8's judge check is recorded.
- #461: built when C11's five tests are green; the idle-unit watcher starts in a relay pane only after that pane restarts and reads the new startup text.

## Verification

- Each Acceptance test green; `bash scripts/run-shell-tests.sh --changed main` green.
- `claude plugin validate .` and `claude plugin test .` pass; `bash ci/leak-test.sh` and `bash ci/version-check.sh` pass.
- Review passes until the unit converges; the closing pass ends `VERDICT: GO` naming no finding.
Break: scripts/__tests__/builder-codex-pass-rebase.test.sh -- a final with a rebase in progress and a changed tracked file is refused once, before it commits (issue 451) -- scripts/builder-codex-pass.sh precheck rebase-in-progress check
Break: scripts/__tests__/builder-codex-pass-rebase.test.sh -- a final with a rebase in progress and a changed tracked file is refused once, before it commits (issue 451) -- scripts/builder-codex-pass.sh precheck dirty-tracked check
Break: scripts/__tests__/cos-tell.test.sh -- an alert wakes the relay once, under any stamp (issue 461) -- scripts/cos-watch-alerts.sh printed-id seen write
Break: scripts/__tests__/cos-watch-units.test.sh -- a NO-GO or older-GO unit is reported idle once (issue 461) -- scripts/cos-watch-units.sh seen-file write
- C8 kept files, K not exported, first: its run ends `0 failed` and `<abs K>/T` exists, else `BLOCKED:` to main with the output.
- C8 judge check: one `claude -p --model sonnet` run per fixture on Data design's `C8 kept files`; evidence `C8 judge check: <f>` holds verdict and output; stranded NO-GO, reachable GO, else `BLOCKED:` to main with both outputs, no rerun.

## Routing

- Builder: this pane's model. Helpers: Sonnet `general-purpose` for reading code, test triage and mechanical edits; Haiku `Explore` for search. Name the model on every call; the Builder brief carries this line.

## Question for the owner

- Answered 2026-10-29: no live Orca restart; #453 merges as `Refs #453`.

## Facts

- `die`; LENS; lone dies; `--check` copy lacks `-p`; staging, commit, late rebase failure; hand-off bullet; template lines -- scripts/builder-codex-pass.sh:76, scripts/builder-codex-pass.sh:147, scripts/builder-codex-pass.sh:1086-1474, scripts/builder-codex-pass.sh:1932, templates/_builder-brief-template.md:276-277 (observed: 2026-10-29)
- Tests read refusal texts; suite pass 14 ends NO-GO; the rebase test's timed typecheck -- scripts/__tests__/builder-codex-pass-class-return.test.sh:63-64, scripts/__tests__/builder-codex-pass-suite.test.sh:36-53, scripts/__tests__/builder-codex-pass-rebase.test.sh:93-96 (observed: 2026-10-29)
- answer-worker: `QID`/`Q` lookup, `close_asks`, claim_wait, `simple_wait`, routes, follower `Q`; ask-main id, slices, token; ledger and parked cases -- scripts/answer-worker.sh:45-281, scripts/to-main.sh:58, scripts/ask-main.sh:38-88, scripts/__tests__/answer-worker.test.sh:87-242 (observed: 2026-10-29)
- Flat ps line, unplain restarts bare; `stop_hook` under `env -i`; `pid_env` -- hooks/context-clear-stop.sh:211-218, hooks/__tests__/context-clear-stop.test.sh:56-62, scripts/read-verdict.sh:347-377 (observed: 2026-10-29)
- #453 workarounds 1, 2, 3, 5; no permission mode set -- scripts/seat.sh:578-580, scripts/orca-wait.sh:7-10, hooks/no-poll-loops.sh:202-206, scripts/seat.sh:418-425, docs/auto-permission-mode.md:3-4 (observed: 2026-10-29)
- Test split; `fr` logs under u9; u8 hand-offs; clear line; warm table -- scripts/__tests__/fixtures/builder-codex-pass-setup.sh:6-7, scripts/__tests__/builder-fresh-round.test.sh:98-137, scripts/builder-fresh-round.sh:165-226, scripts/__tests__/builder-codex-pass-warm-round.test.sh:8-50 (observed: 2026-10-29)
- Spec path; author/judge lines; prompt file, tests; EXIT trap removes `$T`; plan-check budget, `pc` -- scripts/seat.sh:402-451, scripts/seat.sh:574, scripts/__tests__/seat-plan-marker.test.sh:45-87, scripts/__tests__/fixtures/seat-setup.sh:7, scripts/plan-check.sh:272-361, scripts/__tests__/plan-check-budget.test.sh:15-22 (observed: 2026-10-29)
- #455 sites; :163 reads b15d8ee; CI unshallows first; release needs a green push; version 0.60.0 -- scripts/__tests__/builder-codex-pass-class-sites.test.sh:10, scripts/builder-codex-pass.sh:1535-1537, scripts/__tests__/merge-unit-local.test.sh:163-269, scripts/__tests__/fixtures/merge-unit-local-setup.sh:7, .github/workflows/ci.yml:9-49, .github/workflows/release.yml:16, .claude-plugin/plugin.json:3, README.md:4, CHANGELOG.md:3 (observed: 2026-10-29)
- Alerts watcher (unseen id and fingerprint new without `told`); alert ids and kinds -- scripts/cos-watch-alerts.sh:35-77, scripts/dashboard_alerts.jq:55-114, scripts/dashboard_builders.jq:85-109 (observed: 2026-10-29)
- Alerts-watcher tests: daily repeat, hand seen line; other runs -- scripts/__tests__/cos-tell.test.sh:40-309, scripts/__tests__/dashboard-built.test.sh:76-81, scripts/__tests__/dashboard-main-events.test.sh:38-43, hooks/__tests__/context-clear-stop.test.sh:194-196 (observed: 2026-10-29)
- Relay: `cos_wait`; four watchers, held by Stop hook, cos-check, their tests; startup lines, its test; allowlist -- scripts/cos-lib.sh:5-30, docs/chief-of-staff.md:22-33, hooks/cos-inbox-waiter-stop.sh:57-64, scripts/cos-check.sh:16-21, scripts/__tests__/cos-check.test.sh:59-135, hooks/__tests__/cos-inbox-waiter-stop.test.sh:58, hooks/__tests__/agent-startup-context.test.sh:65, hooks/agent-startup-context.sh:137-142, scripts/worktree-setup.sh:94-96 (observed: 2026-10-29)
- Units: workspaces, standing names; round files, verdict last line; briefs ignored; merge log; hook-written events; `stat -c %Y` -- scripts/paths.sh:76, scripts/dashboard.sh:320-324, scripts/dashboard.sh:452, hooks/lib/project.sh:37-40, scripts/builder-codex-pass.sh:399-406, scripts/builder-codex-pass.sh:994, scripts/builder-codex-pass.sh:1239, .gitignore:5-6, scripts/merge-unit-local.sh:59, hooks/lib/hook-fire-log.sh:340, hooks/context-clear-stop.sh:40 (observed: 2026-10-29)

## Plan change log

- 2026-10-29: first version.
- 2026-10-29: owner answered the #453 question: no live Orca restart; #453 is partial and merges as `Refs #453`.
- 2026-10-29: answered the judge's NO-GO: the warm Break now mutates :165 `-ge` to `-gt`, which the table's `equal` case catches (the :184 guard changed nothing); D5 sets `Q=$QID`, with the two-open ledger case; :1326 joins the collector, with the three-refusal suite case; D7 reads real argv under stated boundaries and mode values, with the flag-inside-a-value case; the moved block is 162-204; Catches: lines on the precheck, the token lookup and the argv walk. Added the owner's #455 (reproduced: two test setup bugs, C6), #456, #457 and #458 (C7-C9), a Closes: line, a ## Done section, version cut renumbered C10; #458's check narrowed to Stated limits and `Follow-up:` lines at main's request.
- 2026-10-29: answered the judge's round-2 NO-GO: C6 names the CI-like checkout (depth-1 clone, detached HEAD, no local `main`, then ci.yml:44's fetch), settled by a run (A6), and acceptance runs both files there, the :163 check unedited; C8 keeps the judge prompt and its spec past the fixture's EXIT trap with a `BASH_ENV` trap override on the unedited test (A7), one `claude -p` run per fixture, a wrong verdict a BLOCKED with no rerun; `Catches:` lines on C6-C9.
- 2026-10-29: answered the judge's round-3 NO-GO: C8's `keep-env.sh` is written with `K`'s absolute path, never a literal `$K`, and the case `C8 kept files, K not exported` runs first. Added the owner's #461 as C11 (D13, D14, F4): the alerts watcher skips quiet and stage alerts and marks what it prints seen; the plugin had no idle-unit watcher, so a new cos-watch-units.sh skips a unit whose newest GO is not older than its last commit; five tests, two Break lines (the two seen writes). Fitting the caps: steps grouped, facts merged, C3/C4 test detail moved to Data design, two rebase Break lines moved to Verification, the "Three checks fail" row gave its place to the round-order row (its test and Break stay); C4's third-argument expansion braced for the leak test.
- 2026-10-29 (build): D5's token lookup runs only when the pane reads parked in a wait (`pending_state parked`), after the pane's log is read: as planned it also took answer-worker-interrupt.test.sh's issue-351 case (a mid-turn pane with a live token) off the inbox route, a named consumer that stays green unedited.
- 2026-10-29 (build): the Facts line on the warm table cites its new file, since C5 moved those lines and plan-check refuses a citation past a file's end.
- 2026-10-29 (build): C7's good and bad Done examples use `#39`, not a four-digit number: the brief's public-safe search allows no four-digit issue number in the diff.
- 2026-10-29 (fix r1): pass 1 found the Done check read only the outcome side (both sides now) and the units watcher's cos_wait pid, wake files and wake-log line missing from Data design (named there and in its header); a What can go wrong row and a test each.
- 2026-10-29 (fix r3): pass 3 found the no-id lookup lost the thread between two inbox waits (ask-main.sh removes `.wait` after each batch). ask-main.sh now holds a call-long `<id>.asking`, which the lookup reads (Data design, D5); `.wait` stays the interrupt's alone. A What can go wrong row and tests in answer-worker.test.sh and ask-main.test.sh.
